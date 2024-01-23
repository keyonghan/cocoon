// Copyright 2020 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:googleapis/bigquery/v2.dart';
import 'package:googleapis/firestore/v1.dart';
import 'package:http/http.dart';

import 'access_client_provider.dart';

/// The sql query to query the build statistic from the
/// `flutter-dashboard.datasite.luci_prod_build_status`.
///
/// The schema of the `luci_prod_build_status` table:
/// time	            TIMESTAMP
/// date	            DATE
/// sha	              STRING
/// flaky_builds	    STRING
/// succeeded_builds	STRING
/// branch	          STRING
/// device_os       	STRING
/// pool	            STRING
/// repo	            STRING
/// builder_name	    STRING
/// success_count	    INTEGER
/// failure_count	    INTEGER
/// is_flaky	        INTEGER
///
/// This returns latest [LIMIT] number of build stats for each builder.

class FirestoreService {
  const FirestoreService(this.accessClientProvider);

  /// AccessClientProvider for OAuth 2.0 authenticated access client
  final AccessClientProvider accessClientProvider;

  /// Return a [TabledataResource] with an authenticated [client]
  Future<ProjectsDatabasesDocumentsResource> defaultDatabase() async {
    final Client client = await accessClientProvider.createAccessClient(
      scopes: const <String>[FirestoreApi.datastoreScope],
      baseClient: FirestoreBaseClient(),
    );
    return FirestoreApi(client).projects.databases.documents;
  }

  /// Return the top [limit] number of current builder statistic.
  ///
  /// See getBuilderStatisticQuery to get the detail information about the table
  /// schema
  Future<Document> getDocument(
    String name,
  ) async {
    final ProjectsDatabasesDocumentsResource databasesDocumentsResource = await defaultDatabase();
    Document document = Document();
    try {
      document = await databasesDocumentsResource.get(name);
    } catch (e) {
      print(e.toString());
      print('test');
    }
    return document;
  }

  Future<Document> createDocument(Document document, String parent, String collectionId) async {
    final ProjectsDatabasesDocumentsResource databasesDocumentsResource = await defaultDatabase();
    return databasesDocumentsResource.createDocument(document, parent, collectionId);
  }

  Future<BatchWriteResponse> batchWriteDocuments(BatchWriteRequest request, String database) async {
    final ProjectsDatabasesDocumentsResource databasesDocumentsResource = await defaultDatabase();
    return databasesDocumentsResource.batchWrite(request, database);
  }

  Future<BeginTransactionResponse> beginTransaction(BeginTransactionRequest request, String database) async {
    final ProjectsDatabasesDocumentsResource databasesDocumentsResource = await defaultDatabase();
    return databasesDocumentsResource.beginTransaction(request, database);
  }

  Future<CommitResponse> commit(CommitRequest request, String database) async {
    final ProjectsDatabasesDocumentsResource databasesDocumentsResource = await defaultDatabase();
    return databasesDocumentsResource.commit(request, database);
  }

  Future<RunQueryResponse> runQuery(RunQueryRequest request, String parent) async {
    final ProjectsDatabasesDocumentsResource databasesDocumentsResource = await defaultDatabase();
    return databasesDocumentsResource.runQuery(request, parent);
  }
}
