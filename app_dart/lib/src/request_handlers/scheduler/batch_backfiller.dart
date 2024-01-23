// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:cocoon_service/src/foundation/utils.dart';
import 'package:cocoon_service/src/model/appengine/commit.dart';
import 'package:cocoon_service/src/model/appengine/task.dart';
import 'package:cocoon_service/src/request_handling/body.dart';
import 'package:cocoon_service/src/service/datastore.dart';
import 'package:cocoon_service/src/service/scheduler/policy.dart';
import 'package:gcloud/db.dart';
import 'package:github/github.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:meta/meta.dart';
import 'package:retry/retry.dart';

import '../../model/ci_yaml/ci_yaml.dart';
import '../../model/ci_yaml/target.dart';
import '../../request_handling/exceptions.dart';
import '../../request_handling/request_handler.dart';
import '../../service/config.dart';
import '../../service/firestore.dart';
import '../../service/logging.dart';
import '../../service/luci_build_service.dart';
import '../../service/scheduler.dart';

/// Cron request handler for scheduling targets when capacity becomes available.
///
/// Targets that have a [BatchPolicy] need to have backfilling enabled to ensure that ToT is always being tested.
@immutable
class BatchBackfiller extends RequestHandler {
  /// Creates a subscription for sending BuildBucket requests.
  const BatchBackfiller({
    required super.config,
    required this.scheduler,
    @visibleForTesting this.datastoreProvider = DatastoreService.defaultProvider,
  });

  final DatastoreServiceProvider datastoreProvider;
  final Scheduler scheduler;

  @override
  Future<Body> get() async {
    final List<Future<void>> futures = <Future<void>>[];

    // for (RepositorySlug slug in config.supportedRepos) {
    futures.add(backfillRepository(RepositorySlug('flutter', 'flutter')));
    // }

    // Process all repos asynchronously
    await Future.wait<void>(futures);

    return Body.empty;
  }

  Future<void> backfillRepository(RepositorySlug slug) async {
    final DatastoreService datastore = datastoreProvider(config.db);
    final List<FullTask> tasks = await (datastore.queryRecentTasks(slug: slug, commitLimit: 5)).toList();
    final FirestoreService firestoreService = await config.createFirestoreService();
    final List<Write> writes = <Write>[];
    final Set<String> commitSet = <String>{};
    for (FullTask task in tasks) {
      if (task.task.buildNumberList == null) {
        continue;
      }
      final Commit commit = task.commit;
      if (!commitSet.contains(commit.sha)) {
        final Document commitDocument = Document(
          name: 'projects/flutter-dashboard/databases/cocoon-experiment/documents/commits/${commit.sha}',
          fields: <String, Value>{
            'avatar': Value(stringValue: commit.authorAvatarUrl),
            'branch': Value(stringValue: commit.branch),
            'createdTimestamp': Value(integerValue: commit.timestamp.toString()),
            'login': Value(stringValue: commit.author),
            'message': Value(stringValue: commit.message),
            'repositoryPath': Value(stringValue: commit.repository),
            'sha': Value(stringValue: commit.sha),
          },
        );
        writes.add(Write(update: commitDocument, currentDocument: Precondition(exists: false)));
        commitSet.add(commit.sha!);
      }

      final List<String> builds = task.task.buildNumberList!.split(',');
      int i = 1;
      for (String build in builds) {
        final Document taskDocument = Document(
          name: 'projects/flutter-dashboard/databases/cocoon-experiment/documents/tasks/${commit.sha}_${task.task.name}_${i++}',
          fields: <String, Value>{
            'builderNumber': Value(integerValue: build),
            'createTimestamp': Value(integerValue: task.task.createTimestamp.toString()),
            'endTimestamp': Value(integerValue: task.task.endTimestamp.toString()),
            'flaky': Value(booleanValue: task.task.isFlaky),
            'name': Value(stringValue: task.task.name),
            'startTimestamp': Value(integerValue: task.task.startTimestamp.toString()),
            'status': Value(stringValue: task.task.status),
            'testFlaky': Value(booleanValue: task.task.isTestFlaky),
            'commmitSha': Value(stringValue: task.commit.sha),
          },
        );
        writes.add(Write(update: taskDocument, currentDocument: Precondition(exists: false)));
      }
    }
    const String database = 'projects/flutter-dashboard/databases/cocoon-experiment';
    final BeginTransactionRequest beginTransactionRequest =
        BeginTransactionRequest(options: TransactionOptions(readWrite: ReadWrite()));
    final BeginTransactionResponse beginTransactionResponse =
        await firestoreService.beginTransaction(beginTransactionRequest, database);
    final CommitRequest commitRequest =
        CommitRequest(transaction: beginTransactionResponse.transaction, writes: writes);
    await firestoreService.commit(commitRequest, database);

    // await datastore.withTransaction<void>((Transaction transaction) async {
    //     transaction.queueMutations(inserts: inProgressTasks);
    //   });
  }

  /// Filters [config.backfillerTargetLimit] targets to backfill.
  ///
  /// High priority targets will be guranteed to get back filled first. If more targets
  /// than [config.backfillerTargetLimit], pick the limited number of targets after a
  /// shuffle. This is to make sure all targets are picked with the same chance.
  List<Tuple<Target, FullTask, int>> getFilteredBackfill(List<Tuple<Target, FullTask, int>> backfill) {
    if (backfill.length <= config.backfillerTargetLimit) {
      return backfill;
    }
    final List<Tuple<Target, FullTask, int>> filteredBackfill = <Tuple<Target, FullTask, int>>[];
    final List<Tuple<Target, FullTask, int>> highPriorityBackfill =
        backfill.where((element) => element.third == LuciBuildService.kRerunPriority).toList();
    final List<Tuple<Target, FullTask, int>> normalPriorityBackfill =
        backfill.where((element) => element.third != LuciBuildService.kRerunPriority).toList();
    if (highPriorityBackfill.length >= config.backfillerTargetLimit) {
      highPriorityBackfill.shuffle();
      filteredBackfill.addAll(highPriorityBackfill.sublist(0, config.backfillerTargetLimit));
    } else {
      filteredBackfill.addAll(highPriorityBackfill);
      normalPriorityBackfill.shuffle();
      filteredBackfill
          .addAll(normalPriorityBackfill.sublist(0, config.backfillerTargetLimit - highPriorityBackfill.length));
    }
    return filteredBackfill;
  }

  /// Schedules tasks with retry when hitting pub/sub server errors.
  Future<void> _scheduleWithRetries(List<Tuple<Target, FullTask, int>> backfill) async {
    const RetryOptions retryOptions = Config.schedulerRetry;
    try {
      await retryOptions.retry(
        () async {
          final List<List<Tuple<Target, Task, int>>> tupleLists =
              await Future.wait<List<Tuple<Target, Task, int>>>(backfillRequestList(backfill));
          if (tupleLists.any((List<Tuple<Target, Task, int>> tupleList) => tupleList.isNotEmpty)) {
            final int nonEmptyListLenght = tupleLists.where((element) => element.isNotEmpty).toList().length;
            log.info('Backfill fails and retry backfilling $nonEmptyListLenght targets.');
            backfill = _updateBackfill(backfill, tupleLists);
            throw InternalServerError('Failed to backfill ${backfill.length} targets.');
          }
        },
        retryIf: (Exception e) => e is InternalServerError,
      );
    } catch (error) {
      log.severe('Failed to backfill ${backfill.length} targets due to error: $error');
    }
  }

  /// Updates the [backfill] list with those that fail to get scheduled.
  ///
  /// [tupleLists] maintains the same tuple order as those in [backfill].
  /// Each element from [backfill] is encapsulated as a list in [tupleLists] to prepare for
  /// [scheduler.luciBuildService.schedulePostsubmitBuilds].
  List<Tuple<Target, FullTask, int>> _updateBackfill(
    List<Tuple<Target, FullTask, int>> backfill,
    List<List<Tuple<Target, Task, int>>> tupleLists,
  ) {
    final List<Tuple<Target, FullTask, int>> updatedBackfill = <Tuple<Target, FullTask, int>>[];
    for (int i = 0; i < tupleLists.length; i++) {
      if (tupleLists[i].isNotEmpty) {
        updatedBackfill.add(backfill[i]);
      }
    }
    return updatedBackfill;
  }

  /// Creates a list of backfill requests.
  List<Future<List<Tuple<Target, Task, int>>>> backfillRequestList(List<Tuple<Target, FullTask, int>> backfill) {
    final List<Future<List<Tuple<Target, Task, int>>>> futures = <Future<List<Tuple<Target, Task, int>>>>[];
    for (Tuple<Target, FullTask, int> tuple in backfill) {
      // TODO(chillers): The backfill priority is always going to be low. If this is a ToT task, we should run it at the default priority.
      final Tuple<Target, Task, int> toBeScheduled = Tuple(
        tuple.first,
        tuple.second.task,
        tuple.third,
      );
      futures.add(
        scheduler.luciBuildService.schedulePostsubmitBuilds(
          commit: tuple.second.commit,
          toBeScheduled: [toBeScheduled],
        ),
      );
    }

    return futures;
  }

  /// Returns priority for back filled targets.
  ///
  /// Uses a higher priority if there is an earlier failed build. Otherwise,
  /// uses default `LuciBuildService.kBackfillPriority`
  int backfillPriority(List<Task> tasks, int pastTaskNumber) {
    if (shouldRerunPriority(tasks, pastTaskNumber)) {
      return LuciBuildService.kRerunPriority;
    }
    return LuciBuildService.kBackfillPriority;
  }

  /// Returns the most recent [FullTask] to backfill.
  ///
  /// A [FullTask] is only returned iff:
  ///   1. There are no running builds (yellow)
  ///   2. There are tasks that haven't been run (gray)
  ///
  /// This is naive, and doesn't rely on knowing the actual Flutter infra capacity.
  ///
  /// Otherwise, returns null indicating nothing should be backfilled.
  FullTask? _backfillTask(Target target, List<FullTask> tasks) {
    final List<FullTask> relevantTasks = tasks.where((FullTask task) => task.task.name == target.value.name).toList();
    if (relevantTasks.any((FullTask task) => task.task.status == Task.statusInProgress)) {
      // Don't schedule more builds where there is already a running task
      return null;
    }

    final List<FullTask> backfillTask =
        relevantTasks.where((FullTask task) => task.task.status == Task.statusNew).toList();
    if (backfillTask.isEmpty) {
      return null;
    }

    // First item in the list is guranteed to be most recent.
    // Mark task as in progress to ensure it isn't scheduled over
    backfillTask.first.task.status = Task.statusInProgress;
    return backfillTask.first;
  }
}
