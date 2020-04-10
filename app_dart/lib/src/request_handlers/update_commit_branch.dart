// Copyright 2019 The Chromium Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:appengine/appengine.dart';
import 'package:cocoon_service/src/model/appengine/commit.dart';
import 'package:cocoon_service/src/model/appengine/time_series_value.dart';
import 'package:meta/meta.dart';

import '../datastore/cocoon_config.dart';
import '../request_handling/api_request_handler.dart';
import '../request_handling/authentication.dart';
import '../request_handling/body.dart';
import '../service/datastore.dart';

@immutable
class UpdateCommitBranch extends ApiRequestHandler<UpdateCommitBranchResponse> {
  const UpdateCommitBranch(
    Config config,
    AuthenticationProvider authenticationProvider, {
    @visibleForTesting
        this.datastoreProvider = DatastoreService.defaultProvider,
  }) : super(config: config, authenticationProvider: authenticationProvider);

  final DatastoreServiceProvider datastoreProvider;


  @override
  Future<UpdateCommitBranchResponse> get() async {
    Logging log = config.loggingService;
    const String master = 'master';
    final DatastoreService datastore = datastoreProvider(config.db);
    final List<TimeSeriesValue> timeSeriesValues = await datastore.queryRecentTimeseriesValueNoBranch(limit: 1000000, timestamp: 1583969363840).toList();
    timeSeriesValues.forEach((TimeSeriesValue timeSeriesValue) => timeSeriesValue.branch=master);
    await datastore.insert(timeSeriesValues);
    log.debug('inserted ${timeSeriesValues.length} timeSeriesValues');
    
    return UpdateCommitBranchResponse('${timeSeriesValues.length}');
  }
}

@immutable
class UpdateCommitBranchResponse extends JsonBody {
  const UpdateCommitBranchResponse(this.token) : assert(token != null);

  final String token;

  @override
  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'Token': token,
    };
  }
}
