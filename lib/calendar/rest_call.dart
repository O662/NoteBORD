import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../sync/cloud.dart';
import '../sync/cloud_auth.dart';
import 'remote.dart';

// Calls to Google Calendar and Microsoft Graph with the account's token,
// signing in again once if it's refused, with failures as CloudExceptions
// (offline, signed out, other), RemoteConflict (412) and RemoteGone (404,
// 410).

class RestCall {
  RestCall(this.auth, this.client, this.app);

  final CloudAuth auth;
  final http.Client client;

  /// "Google Calendar" or "Outlook", for messages.
  final String app;

  /// Sends [method] [url] with [body] (JSON) and [headers]; on 401 once more
  /// with a new token.
  Future<http.Response> send(String method, Uri url, {Object? body, Map<String, String> headers = const {}}) async {
    for (var attempt = 0;; attempt++) {
      final token = await auth.token(fresh: attempt > 0);
      final q = http.Request(method, url)
        ..headers['Authorization'] = 'Bearer $token'
        ..headers.addAll(headers);
      if (body != null) {
        q.headers['Content-Type'] = 'application/json; charset=utf-8';
        q.body = jsonEncode(body);
      }
      final http.Response r;
      try {
        r = await http.Response.fromStream(await client.send(q).timeout(const Duration(seconds: 40)));
      } on SocketException catch (e) {
        throw CloudException(CloudFailure.offline, e.message);
      } on http.ClientException catch (e) {
        throw CloudException(CloudFailure.offline, e.message);
      } on TimeoutException {
        throw CloudException(CloudFailure.offline, '$app didn’t answer');
      }
      if (r.statusCode == 401 && attempt == 0) continue;
      if (r.statusCode == 401) throw CloudException(CloudFailure.signedOut, 'Sign in to $app again');
      return r;
    }
  }

  /// [send], expecting JSON back (2xx). 404/410: [RemoteGone]; 412:
  /// [RemoteConflict].
  Future<Map<String, dynamic>> json(String method, Uri url, {Object? body, Map<String, String> headers = const {}, String what = 'Calendar'}) async {
    final r = await send(method, url, body: body, headers: headers);
    check(r, what);
    return r.body.isEmpty ? <String, dynamic>{} : (jsonDecode(r.body) as Map).cast<String, dynamic>();
  }

  void check(http.Response r, String what) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    if (r.statusCode == 404 || r.statusCode == 410) throw const RemoteGone();
    if (r.statusCode == 412) throw const RemoteConflict();
    if (r.statusCode == 429 || r.statusCode >= 500) throw CloudException(CloudFailure.offline, '$app is busy (${r.statusCode}); trying again later');
    if (r.statusCode == 403 && r.body.contains('rateLimit')) throw CloudException(CloudFailure.offline, '$app is busy; trying again later');
    throw CloudException(CloudFailure.other, '$what: $app said no (${r.statusCode}${_reason(r.body)})');
  }

  static String _reason(String body) {
    try {
      final j = jsonDecode(body);
      final m = j is Map ? (j['error'] is Map ? (j['error'] as Map)['message'] : j['error_description'] ?? j['error']) : null;
      return m is String && m.isNotEmpty ? ': $m' : '';
    } on Object {
      return '';
    }
  }
}

/// Runs [work] over [items], [n] at a time.
Future<List<R>> inBatches<T, R>(Iterable<T> items, int n, Future<R> Function(T) work) async {
  final list = items.toList(), out = <R>[];
  for (var i = 0; i < list.length; i += n) {
    out.addAll(await Future.wait(list.skip(i).take(n).map(work)));
  }
  return out;
}
