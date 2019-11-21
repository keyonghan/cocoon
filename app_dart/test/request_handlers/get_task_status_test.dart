// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:cocoon_service/src/model/appengine/commit.dart';
import 'package:cocoon_service/src/model/appengine/task.dart';
import 'package:cocoon_service/src/request_handlers/get_task_status.dart';
import 'package:cocoon_service/src/service/datastore.dart';
import 'package:test/test.dart';

import '../src/datastore/fake_cocoon_config.dart';
import '../src/request_handling/api_request_handler_tester.dart';
import '../src/request_handling/fake_authentication.dart';

void main() {
  group('GetTaskStatus', () {
    FakeConfig config;
    ApiRequestHandlerTester tester;
    GetTaskStatus handler;

    setUp(() {
      config = FakeConfig(maxTaskRetriesValue: 2);
      tester = ApiRequestHandlerTester();
      tester.requestData = <String, dynamic>{
        'TaskKey': 'ahNzfmZsdXR0ZXItZGFzaGJvYXJkclgLEglDaGVja2xpc3QiOGZsdXR0ZXIvZmx1dHRlci8xNTlhNDdkYTY0OGEzN2YwZmNkOWU1ZTVjMGY2MTIxYjJlMDc1YmFhDAsSBFRhc2sYgICQ9-mwwggM'
      };
      handler = GetTaskStatus(
        config,
        FakeAuthenticationProvider(),
        datastoreProvider: () => DatastoreService(db: config.db),
      );
    });

    test('return true for a Succeeded task', () async {
      final Commit commit = Commit(key: config.db.emptyKey.append(Commit, id: 'flutter/flutter/159a47da648a37f0fcd9e5e5c0f6121b2e075baa'));
      final Task task = Task(key: commit.key.append(Task, id: 4795548400091136), commitKey: commit.key, status: 'Succeeded', attempts: 1);
      config.db.values[task.key] = task;
      final GetTaskStatusResponse response = await tester.post(handler);
      expect(response.task.attempts, 1);
      expect(response.task.toString(), 'Task(id: 4795548400091136, parentKey: flutter/flutter/159a47da648a37f0fcd9e5e5c0f6121b2e075baa, key: 4795548400091136, commitKey: flutter/flutter/159a47da648a37f0fcd9e5e5c0f6121b2e075baa, createTimestamp: 0, startTimestamp: 0, endTimestamp: 0, name: null, attempts: 1, isFlaky: false, timeoutInMinutes: null, reason: , requiredCapabilities: null, reservedForAgentId: , stageName: null, status: Succeeded)');
    });
  });
}
