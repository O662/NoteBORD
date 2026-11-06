import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:flutter/foundation.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'cloud.dart';

// Signing in to Google Drive and OneDrive. Endless talks to them straight
// from the device; there's no Endless server. Each needs the app
// registered with Google and Microsoft (docs/CLOUD_SETUP.md), whose client
// ids come in when the app is built:
//
//   flutter build apk --dart-define=GOOGLE_WEB_CLIENT_ID=… \
//                     --dart-define=MICROSOFT_CLIENT_ID=…
//
// On Android, Google's own sign-in (google_sign_in) and, for Microsoft,
// the system browser (AppAuth). On Windows, the browser for both, coming
// back to Endless on this computer (127.0.0.1). The sign-in that lasts (a
// refresh token) is kept in the platform's secure storage, never in a file.
//
// Scopes: Google `drive.file` (only files Endless made: not the rest of
// your Drive; Google rates it non-sensitive); Microsoft `Files.ReadWrite`
// and `offline_access`.

/// The client ids this build was made with (empty: not set up). Client
/// ids aren't secrets, so Endless's own are the defaults; a build can use
/// others with --dart-define. The Windows client secret is never in the
/// code: it comes from config/cloud_secrets.json (git ignores it), with
/// --dart-define-from-file=config/cloud_secrets.json.
class CloudIds {
  /// Google Cloud project "Endless", Web client "Endless (for Android sign-in)".
  static const googleWeb = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '559291719909-ge9bkocsv6ksho8su1h1b0kt5mag87mn.apps.googleusercontent.com',
  );
  static const googleDesktop = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_ID');
  static const googleDesktopSecret = String.fromEnvironment('GOOGLE_DESKTOP_CLIENT_SECRET');
  static const microsoft = String.fromEnvironment('MICROSOFT_CLIENT_ID');
}

const googleScopes = ['https://www.googleapis.com/auth/drive.file'];
const microsoftScopes = ['Files.ReadWrite', 'User.Read', 'offline_access'];

/// Who's signed in.
@immutable
class CloudAccount {
  const CloudAccount(this.email, {this.name});

  final String email;
  final String? name;

  Map<String, dynamic> toJson() => {'email': email, if (name != null) 'name': name};

  static CloudAccount? fromJson(Object? j) =>
      j is Map && j['email'] is String ? CloudAccount(j['email'] as String, name: j['name'] as String?) : null;
}

/// Signing in to one cloud, and the access tokens that come with it.
abstract class CloudAuth {
  CloudKind get kind;

  /// Why signing in can't work in this build or on this device, or null.
  String? get notReady;

  /// Asks the person to sign in (opens Google's or Microsoft's sign-in).
  Future<CloudAccount> signIn();

  /// Signs in again without asking, if the last sign-in still holds.
  Future<CloudAccount?> restore();

  /// A token for the cloud's API. [fresh]: the last one was refused.
  /// Throws [CloudException] (signedOut) if the person has to sign in.
  Future<String> token({bool fresh = false});

  Future<void> signOut();
}

/// Google on Android and iOS: Google's own sign-in.
class GoogleAuth implements CloudAuth {
  GoogleAuth();

  @override
  CloudKind get kind => CloudKind.google;

  static Future<void>? _init;
  GoogleSignInAccount? _account;

  @override
  String? get notReady => CloudIds.googleWeb.isEmpty ? _missing('Google') : null;

  Future<void> _ready() => _init ??= GoogleSignIn.instance.initialize(serverClientId: CloudIds.googleWeb);

  @override
  Future<CloudAccount> signIn() async {
    await _ready();
    try {
      final account = _account = await GoogleSignIn.instance.authenticate(scopeHint: googleScopes);
      await account.authorizationClient.authorizeScopes(googleScopes);
      return CloudAccount(account.email, name: account.displayName);
    } on GoogleSignInException catch (e) {
      throw CloudException(
          e.code == GoogleSignInExceptionCode.canceled ? CloudFailure.signedOut : CloudFailure.other, e.description ?? e.code.name);
    }
  }

  @override
  Future<CloudAccount?> restore() async {
    await _ready();
    try {
      final account = _account = await GoogleSignIn.instance.attemptLightweightAuthentication();
      return account == null ? null : CloudAccount(account.email, name: account.displayName);
    } on Object {
      return null;
    }
  }

  String? _last;

  @override
  Future<String> token({bool fresh = false}) async {
    await _ready();
    final account = _account ?? await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (account == null) throw const CloudException(CloudFailure.signedOut, 'Sign in to Google Drive again');
    _account = account;
    if (fresh && _last != null) await GoogleSignIn.instance.authorizationClient.clearAuthorizationToken(accessToken: _last!);
    final auth = await account.authorizationClient.authorizationForScopes(googleScopes);
    if (auth == null) throw const CloudException(CloudFailure.signedOut, 'Allow Endless to use Google Drive again');
    return _last = auth.accessToken;
  }

  @override
  Future<void> signOut() async {
    await _ready();
    _account = null;
    await GoogleSignIn.instance.signOut();
  }
}

String _missing(String who) =>
    '$who sign-in isn’t set up in this version of Endless yet (it needs the app’s $who client id: docs/CLOUD_SETUP.md).';

/// Tokens that last: an access token, until when, and the refresh token.
class _Tokens {
  _Tokens(this.access, this.expires, this.refresh);

  String access;
  DateTime expires;
  String? refresh;
}

/// Microsoft on Android and iOS: the system browser, through AppAuth.
class MicrosoftAuth implements CloudAuth {
  MicrosoftAuth({FlutterSecureStorage? storage, http.Client? client})
      : _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client();

  @override
  CloudKind get kind => CloudKind.onedrive;

  static const redirect = 'com.endless.endless://auth';
  static const _config = AuthorizationServiceConfiguration(
    authorizationEndpoint: 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize',
    tokenEndpoint: 'https://login.microsoftonline.com/common/oauth2/v2.0/token',
  );
  static const _key = 'endless.cloud.onedrive.refresh';

  final FlutterSecureStorage _storage;
  final http.Client _client;
  final _appAuth = const FlutterAppAuth();
  _Tokens? _tokens;

  @override
  String? get notReady => CloudIds.microsoft.isEmpty ? _missing('Microsoft') : null;

  @override
  Future<CloudAccount> signIn() async {
    try {
      final r = await _appAuth.authorizeAndExchangeCode(AuthorizationTokenRequest(
        CloudIds.microsoft,
        redirect,
        serviceConfiguration: _config,
        scopes: microsoftScopes,
        promptValues: const ['select_account'],
      ));
      _tokens = _Tokens(r.accessToken!, r.accessTokenExpirationDateTime ?? DateTime.now().add(const Duration(minutes: 50)), r.refreshToken);
      if (r.refreshToken != null) await _storage.write(key: _key, value: r.refreshToken);
      return await microsoftAccount(_client, r.accessToken!);
    } on FlutterAppAuthUserCancelledException {
      throw const CloudException(CloudFailure.signedOut, 'Sign-in was cancelled');
    } on FlutterAppAuthPlatformException catch (e) {
      throw CloudException(CloudFailure.other, e.message ?? 'Microsoft sign-in failed');
    }
  }

  @override
  Future<CloudAccount?> restore() async {
    try {
      return await microsoftAccount(_client, await token());
    } on Object {
      return null;
    }
  }

  @override
  Future<String> token({bool fresh = false}) async {
    final t = _tokens;
    if (!fresh && t != null && t.expires.isAfter(DateTime.now().add(const Duration(minutes: 2)))) return t.access;
    final refresh = t?.refresh ?? await _storage.read(key: _key);
    if (refresh == null) throw const CloudException(CloudFailure.signedOut, 'Sign in to OneDrive again');
    try {
      final r = await _appAuth.token(TokenRequest(
        CloudIds.microsoft,
        redirect,
        serviceConfiguration: _config,
        refreshToken: refresh,
        scopes: microsoftScopes,
      ));
      _tokens = _Tokens(r.accessToken!, r.accessTokenExpirationDateTime ?? DateTime.now().add(const Duration(minutes: 50)),
          r.refreshToken ?? refresh);
      if (r.refreshToken != null && r.refreshToken != refresh) await _storage.write(key: _key, value: r.refreshToken);
      return r.accessToken!;
    } on FlutterAppAuthPlatformException catch (e) {
      if (e.code == 'token_failed' || '${e.message}'.contains('invalid_grant')) {
        throw const CloudException(CloudFailure.signedOut, 'Sign in to OneDrive again');
      }
      throw CloudException(CloudFailure.offline, e.message ?? 'Couldn’t reach Microsoft');
    }
  }

  @override
  Future<void> signOut() async {
    _tokens = null;
    await _storage.delete(key: _key);
  }
}

/// The signed-in Microsoft account's address.
Future<CloudAccount> microsoftAccount(http.Client client, String token) async {
  final r = await client.get(Uri.parse('https://graph.microsoft.com/v1.0/me?\$select=mail,userPrincipalName,displayName'),
      headers: {'Authorization': 'Bearer $token'});
  if (r.statusCode != 200) throw CloudException(CloudFailure.other, 'Couldn’t read the Microsoft account (${r.statusCode})');
  final j = jsonDecode(r.body) as Map;
  return CloudAccount((j['mail'] ?? j['userPrincipalName'] ?? 'Microsoft account') as String, name: j['displayName'] as String?);
}

/// Windows (and other desktops): the browser signs in and comes back to
/// Endless at 127.0.0.1 on a port picked then (OAuth for installed apps,
/// with PKCE).
class LoopbackAuth implements CloudAuth {
  LoopbackAuth(this.kind, {FlutterSecureStorage? storage, http.Client? client, Future<bool> Function(Uri)? open})
      : _storage = storage ?? const FlutterSecureStorage(),
        _client = client ?? http.Client(),
        _open = open ?? ((u) => launchUrl(u, mode: LaunchMode.externalApplication));

  @override
  final CloudKind kind;
  final FlutterSecureStorage _storage;
  final http.Client _client;
  final Future<bool> Function(Uri) _open;
  _Tokens? _tokens;

  bool get _google => kind == CloudKind.google;
  String get _clientId => _google ? CloudIds.googleDesktop : CloudIds.microsoft;
  String get _key => 'endless.cloud.${kind.name}.refresh';
  Uri get _authorize => Uri.parse(_google
      ? 'https://accounts.google.com/o/oauth2/v2/auth'
      : 'https://login.microsoftonline.com/common/oauth2/v2.0/authorize');
  Uri get _tokenUri =>
      Uri.parse(_google ? 'https://oauth2.googleapis.com/token' : 'https://login.microsoftonline.com/common/oauth2/v2.0/token');
  List<String> get _scopes => _google ? [...googleScopes, 'email'] : microsoftScopes;

  @override
  String? get notReady => _clientId.isEmpty ? _missing(_google ? 'Google' : 'Microsoft') : null;

  static String _random(int n) {
    final r = math.Random.secure();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    return List.generate(n, (_) => chars[r.nextInt(chars.length)]).join();
  }

  @override
  Future<CloudAccount> signIn() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirect = _google ? 'http://127.0.0.1:${server.port}' : 'http://localhost:${server.port}';
      final verifier = _random(64);
      final challenge = base64Url
          .encode((await Sha256().hash(utf8.encode(verifier))).bytes)
          .replaceAll('=', '');
      final state = _random(24);
      final url = _authorize.replace(queryParameters: {
        'client_id': _clientId,
        'redirect_uri': redirect,
        'response_type': 'code',
        'scope': _scopes.join(' '),
        'code_challenge': challenge,
        'code_challenge_method': 'S256',
        'state': state,
        if (_google) 'access_type': 'offline',
        'prompt': _google ? 'consent select_account' : 'select_account',
      });
      if (!await _open(url)) throw const CloudException(CloudFailure.other, 'Couldn’t open the browser to sign in');
      final req = await server.first.timeout(const Duration(minutes: 5),
          onTimeout: () => throw const CloudException(CloudFailure.signedOut, 'Sign-in took too long'));
      final q = req.uri.queryParameters;
      req.response
        ..statusCode = 200
        ..headers.contentType = ContentType.html
        ..write('<!doctype html><meta charset="utf-8"><body style="font-family:sans-serif;padding:40px">'
            '<h2>${q['code'] != null ? 'Signed in' : 'Not signed in'}</h2><p>You can close this tab and go back to Endless.</p>');
      await req.response.close();
      if (q['state'] != state || q['code'] == null) {
        throw CloudException(CloudFailure.signedOut, q['error_description'] ?? q['error'] ?? 'Sign-in was cancelled');
      }
      final r = await _client.post(_tokenUri, body: {
        'client_id': _clientId,
        if (_google) 'client_secret': CloudIds.googleDesktopSecret,
        'code': q['code']!,
        'redirect_uri': redirect,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
        if (!_google) 'scope': _scopes.join(' '),
      });
      final token = _takeTokens(r, null);
      return await _account(token);
    } finally {
      await server.close(force: true);
    }
  }

  String _takeTokens(http.Response r, String? oldRefresh) {
    if (r.statusCode == 400 || r.statusCode == 401) {
      throw CloudException(CloudFailure.signedOut, 'Sign in to ${kind.label} again');
    }
    if (r.statusCode != 200) throw CloudException(CloudFailure.other, 'Sign-in failed (${r.statusCode})');
    final j = jsonDecode(r.body) as Map;
    final refresh = j['refresh_token'] as String? ?? oldRefresh;
    _tokens = _Tokens(j['access_token'] as String, DateTime.now().add(Duration(seconds: (j['expires_in'] as num?)?.toInt() ?? 3000)), refresh);
    if (refresh != null && refresh != oldRefresh) unawaited(_storage.write(key: _key, value: refresh));
    return _tokens!.access;
  }

  Future<CloudAccount> _account(String token) async {
    if (!_google) return microsoftAccount(_client, token);
    final r = await _client.get(Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'), headers: {'Authorization': 'Bearer $token'});
    if (r.statusCode != 200) return const CloudAccount('Google account');
    final j = jsonDecode(r.body) as Map;
    return CloudAccount((j['email'] ?? 'Google account') as String, name: j['name'] as String?);
  }

  @override
  Future<CloudAccount?> restore() async {
    try {
      return await _account(await token());
    } on Object {
      return null;
    }
  }

  @override
  Future<String> token({bool fresh = false}) async {
    final t = _tokens;
    if (!fresh && t != null && t.expires.isAfter(DateTime.now().add(const Duration(minutes: 2)))) return t.access;
    final refresh = t?.refresh ?? await _storage.read(key: _key);
    if (refresh == null) throw CloudException(CloudFailure.signedOut, 'Sign in to ${kind.label} again');
    try {
      final r = await _client.post(_tokenUri, body: {
        'client_id': _clientId,
        if (_google) 'client_secret': CloudIds.googleDesktopSecret,
        'refresh_token': refresh,
        'grant_type': 'refresh_token',
        if (!_google) 'scope': _scopes.join(' '),
      });
      return _takeTokens(r, refresh);
    } on SocketException catch (e) {
      throw CloudException(CloudFailure.offline, e.message);
    } on http.ClientException catch (e) {
      throw CloudException(CloudFailure.offline, e.message);
    }
  }

  @override
  Future<void> signOut() async {
    _tokens = null;
    await _storage.delete(key: _key);
  }
}

/// The sign-in for [kind] on this platform.
CloudAuth cloudAuthFor(CloudKind kind) {
  final mobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  return switch (kind) {
    CloudKind.google => mobile ? GoogleAuth() : LoopbackAuth(CloudKind.google),
    CloudKind.onedrive => mobile ? MicrosoftAuth() : LoopbackAuth(CloudKind.onedrive),
    CloudKind.folder => throw ArgumentError('A folder needs no sign-in'),
  };
}
