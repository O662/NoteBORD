import 'package:endless/board/store.dart';
import 'package:endless/sync/cloud.dart';
import 'package:endless/sync/cloud_auth.dart';
import 'package:endless/sync/sync_state.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

/// Signs in at once, as [email]; or can't ([notReady]).
class FakeAuth implements CloudAuth {
  FakeAuth(this.kind, {this.email = 'kim@example.com', this.notReady});

  @override
  final CloudKind kind;
  final String email;
  @override
  final String? notReady;
  int signIns = 0;
  bool signedOut = false;

  @override
  Future<CloudAccount> signIn() async {
    signIns++;
    signedOut = false;
    return CloudAccount(email, name: 'Kim');
  }

  @override
  Future<CloudAccount?> restore() async => signedOut ? null : CloudAccount(email);

  @override
  Future<String> token({bool fresh = false}) async =>
      signedOut ? throw CloudException(CloudFailure.signedOut, 'Sign in to ${kind.label} again') : 'token';

  @override
  Future<void> signOut() async => signedOut = true;
}

/// Overrides for an app syncing with [cloud] (for Google Drive and
/// OneDrive alike), on [network].
List<Override> syncOverrides(
  MemoryCloud cloud, {
  MemoryCloud? onedrive,
  bool online = true,
  bool unmetered = true,
  String? notReady,
}) =>
    [
      cloudAuthProvider.overrideWith((ref, kind) => FakeAuth(kind, notReady: notReady)),
      cloudFactoryProvider.overrideWithValue((kind, auth, folder) => kind == CloudKind.onedrive ? (onedrive ?? cloud) : cloud),
      networkCheckProvider.overrideWithValue(() async => (online: online, unmetered: unmetered)),
    ];

/// [store] set up to sync with Google Drive as this device [device].
void syncingWithGoogle(MemoryBoardStore store, {String device = 'dv_a', DateTime? lastSync}) {
  store.saveSyncFile(
    'settings',
    SyncSettings(
      device: device,
      google: CloudSetting(on: true, account: const CloudAccount('kim@example.com'), lastSync: lastSync),
    ).toJson(),
  );
}
