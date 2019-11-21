// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:appengine/appengine.dart';
import 'package:gcloud/db.dart';
import 'package:meta/meta.dart';

import '../datastore/cocoon_config.dart';
import '../model/appengine/key_helper.dart';
import '../model/appengine/task.dart';
import '../request_handling/api_request_handler.dart';
import '../request_handling/authentication.dart';
import '../request_handling/body.dart';
import '../request_handling/exceptions.dart';
import '../service/datastore.dart';

@immutable
class GetTaskStatus extends ApiRequestHandler<GetTaskStatusResponse> {
  const GetTaskStatus(
    Config config,
    AuthenticationProvider authenticationProvider, {
    @visibleForTesting DatastoreServiceProvider datastoreProvider,
  })  : datastoreProvider =
            datastoreProvider ?? DatastoreService.defaultProvider,
        super(config: config, authenticationProvider: authenticationProvider);

  final DatastoreServiceProvider datastoreProvider;

  static const String taskKeyParam = 'TaskKey';

  @override
  Future<GetTaskStatusResponse> post() async {
    final String taskKeyValue = requestData[taskKeyParam];
    if (taskKeyValue == null) {
      throw const BadRequestException(
          'Missing required query parameter: $taskKeyParam');
    }

    final DatastoreService datastore = datastoreProvider();
    final ClientContext clientContext = authContext.clientContext;
    final KeyHelper keyHelper =
        KeyHelper(applicationContext: clientContext.applicationContext);

    Key taskKey;
    try {
      taskKey = keyHelper.decode(taskKeyValue);
    } catch (error) {
      throw BadRequestException('Bad task key: ${requestData[taskKeyParam]}');
    }

    final Task task = await datastore.db.lookupValue<Task>(taskKey, orElse: () {
      throw BadRequestException('No such task: ${taskKey.id}');
    });

    return GetTaskStatusResponse(task);
  }
}

@immutable
class GetTaskStatusResponse extends JsonBody {
  const GetTaskStatusResponse(this.task)
      : assert(task != null);

  final Task task;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'Attempts': task.attempts,
      'Task': task.toString(),
    };
  }
}
