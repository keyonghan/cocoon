// Copyright 2019 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart';

class AccessClientProvider {
  /// Returns an OAuth 2.0 authenticated access client for the device lab service account.
  Future<Client> createAccessClient({
    List<String> scopes = const <String>['https://www.googleapis.com/auth/cloud-platform'],
    Client? baseClient,
  }) async {
    return clientViaApplicationDefaultCredentials(scopes: scopes, baseClient: baseClient);
  }
}

class FirestoreBaseClient extends BaseClient {
  FirestoreBaseClient({
    this.defaultHeaders = const <String, String>{
      'x-goog-request-params': 'project_id=flutter-dashboard&database_id=cocoon-experiment',
    },
  });
  final Map<String, String> defaultHeaders;
  final Client client = Client();
  @override
  Future<StreamedResponse> send(BaseRequest request) {
    request.headers.addAll(defaultHeaders);
    return client.send(request);
  }
}
