// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';

import 'package:appengine/appengine.dart';
import 'package:cocoon_service/src/foundation/github_checks_util.dart';
import 'package:cocoon_service/src/model/github/checks.dart';
import 'package:cocoon_service/src/model/luci/buildbucket.dart';
import 'package:github/github.dart' as github;

import '../../cocoon_service.dart';
import '../model/luci/push_message.dart' as push_message;
import 'luci_build_service.dart';

/// Controls triggering builds and updating their status in the Github UI.
class GithubChecksService {
  GithubChecksService(this.config, {GithubChecksUtil githubChecksUtil})
      : githubChecksUtil = githubChecksUtil ?? const GithubChecksUtil();

  Config config;
  GithubChecksUtil githubChecksUtil;
  Logging log;

  static Set<github.CheckRunConclusion> failedStatesSet = <github.CheckRunConclusion>{
    github.CheckRunConclusion.cancelled,
    github.CheckRunConclusion.failure,
  };

  // This method has to be called before calling any other methods.
  void setLogger(Logging log) {
    this.log = log;
  }

  /// Takes a [CheckSuiteEvent] and trigger all the relevant builds if this is a
  /// new commit or only failed builds if the event was generated by a click on
  /// the re-run all button in the Github UI.
  /// Relevant API docs:
  ///   https://docs.github.com/en/rest/reference/checks#create-a-check-suite
  ///   https://docs.github.com/en/rest/reference/checks#rerequest-a-check-suite
  Future<void> handleCheckSuite(CheckSuiteEvent checkSuiteEvent, LuciBuildService luciBuilderService) async {
    final github.RepositorySlug slug = checkSuiteEvent.repository.slug();
    final github.GitHub gitHubClient = await config.createGitHubClient(slug.owner, slug.name);
    final github.PullRequest pullRequest = checkSuiteEvent.checkSuite.pullRequests[0];
    final int pullRequestNumber = pullRequest.number;
    final String commitSha = checkSuiteEvent.checkSuite.headSha;
    switch (checkSuiteEvent.action) {
      case 'requested':
        // Trigger all try builders.
        await luciBuilderService.scheduleTryBuilds(
          prNumber: pullRequestNumber,
          commitSha: commitSha,
          slug: checkSuiteEvent.repository.slug(),
          checkSuiteEvent: checkSuiteEvent,
        );
        break;

      case 'rerequested':
        // Trigger only the builds that failed.
        final List<Build> builds = await luciBuilderService.failedBuilds(slug, pullRequestNumber, commitSha);
        final Map<String, github.CheckRun> checkRuns = await githubChecksUtil.allCheckRuns(
          gitHubClient,
          checkSuiteEvent,
        );

        for (Build build in builds) {
          final github.CheckRun checkRun = checkRuns[build.builderId.builder];
          await luciBuilderService.rescheduleTryBuildUsingCheckSuiteEvent(
            checkSuiteEvent,
            checkRun,
          );
        }
        break;
    }
  }

  /// Reschedules a failed build using a [CheckRunEvent]. The CheckRunEvent is
  /// generated when someone clicks the re-run button from a failed build from
  /// the Github UI.
  /// Relevant APIs:
  ///   https://developer.github.com/v3/checks/runs/#check-runs-and-requested-actions
  Future<void> handleCheckRun(CheckRunEvent checkRunEvent, LuciBuildService luciBuildService) async {
    switch (checkRunEvent.action) {
      case 'rerequested':
        final String builderName = checkRunEvent.checkRun.name;
        final bool success = await luciBuildService.rescheduleUsingCheckRunEvent(checkRunEvent);
        log.debug('BuilderName: $builderName State: $success');
    }
  }

  /// Updates the Github build status using a [BuildPushMessage] sent by LUCI in
  /// a pub/sub notification.
  /// Relevant APIs:
  ///   https://docs.github.com/en/rest/reference/checks#update-a-check-run
  Future<bool> updateCheckStatus(
    push_message.BuildPushMessage buildPushMessage,
    LuciBuildService luciBuildService,
    github.RepositorySlug slug,
  ) async {
    final github.GitHub gitHubClient = await config.createGitHubClient(slug.owner, slug.name);
    final push_message.Build build = buildPushMessage.build;
    if (buildPushMessage.userData.isEmpty) {
      return false;
    }
    final Map<String, dynamic> userData = jsonDecode(buildPushMessage.userData) as Map<String, dynamic>;
    if (!userData.containsKey('check_run_id') ||
        !userData.containsKey('repo_owner') ||
        !userData.containsKey('repo_name')) {
      log.error(
        'UserData did not contain check_run_id,'
        'repo_owner, or repo_name: $userData',
      );
      return false;
    }
    final github.CheckRun checkRun = await githubChecksUtil.getCheckRun(
      gitHubClient,
      slug,
      userData['check_run_id'] as int,
    );
    final github.CheckRunStatus status = statusForResult(build.status);
    final github.CheckRunConclusion conclusion =
        (buildPushMessage.build.result != null) ? conclusionForResult(buildPushMessage.build.result) : null;
    // Do not override url for completed status.
    final String url = status == github.CheckRunStatus.completed ? checkRun.detailsUrl : buildPushMessage.build.url;
    github.CheckRunOutput output;
    // If status has completed with failure then provide more details.
    if (status == github.CheckRunStatus.completed && failedStatesSet.contains(conclusion)) {
      final Build build =
          await luciBuildService.getTryBuildById(buildPushMessage.build.id, fields: 'id,builder,summaryMarkdown');
      output = github.CheckRunOutput(title: checkRun.name, summary: build.summaryMarkdown ?? 'Empty summaryMarkdown');
    }
    await githubChecksUtil.updateCheckRun(
      gitHubClient,
      slug,
      checkRun,
      status: status,
      conclusion: conclusion,
      detailsUrl: url,
      output: output,
    );
    return true;
  }

  /// Transforms a [push_message.Result] to a [github.CheckRunConclusion].
  /// Relevant APIs:
  ///   https://developer.github.com/v3/checks/runs/#check-runs
  github.CheckRunConclusion conclusionForResult(push_message.Result result) {
    switch (result) {
      case push_message.Result.canceled:
        // Set conclusion cancelled as a failure to ensure developers can retry
        // tasks when builds timeout.
        return github.CheckRunConclusion.failure;
      case push_message.Result.failure:
        return github.CheckRunConclusion.failure;
      case push_message.Result.success:
        return github.CheckRunConclusion.success;
    }
    throw StateError('unreachable');
  }

  /// Transforms a [ush_message.Status] to a [github.CheckRunStatus].
  /// Relevant APIs:
  ///   https://developer.github.com/v3/checks/runs/#check-runs
  github.CheckRunStatus statusForResult(push_message.Status status) {
    switch (status) {
      case push_message.Status.completed:
        return github.CheckRunStatus.completed;
      case push_message.Status.scheduled:
        return github.CheckRunStatus.queued;
      case push_message.Status.started:
        return github.CheckRunStatus.inProgress;
    }
    throw StateError('unreachable');
  }
}
