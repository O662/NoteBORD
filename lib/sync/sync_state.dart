import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'dart:ui' show AppExitResponse;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import '../audio/platform_audio.dart' show audioToolsProvider;
import '../board/model.dart';
import '../board/store.dart';
import '../library/library.dart';
import '../recognition/handwriting_index.dart';
import '../state/changes.dart';
import '../state/notebook.dart';
import '../state/settings.dart';
import '../study/study_state.dart';
import '../transfer/transfer.dart';
import '../video/video_files.dart';
import 'cloud.dart';
import 'cloud_auth.dart';
import 'cloud_rest.dart';
import 'doc.dart';
import 'engine.dart';
import 'stamps.dart';

// Cloud sync in the app (Phase 9a, Sync.png): the settings, when it runs,
// what the title pill and the sidebar say, and moving big videos to the
// cloud. The engine (engine.dart) does the copying.

const defaultSyncFolder = 'Endless Notebooks';

/// One cloud's settings.
@immutable
class CloudSetting {
  const CloudSetting({this.on = false, this.folder = defaultSyncFolder, this.account, this.lastSync});

  final bool on;
  final String folder;
  final CloudAccount? account;
  final DateTime? lastSync;

  bool get connected => account != null;
  bool get active => on && connected;

  CloudSetting copyWith({bool? on, String? folder, CloudAccount? Function()? account, DateTime? Function()? lastSync}) =>
      CloudSetting(
        on: on ?? this.on,
        folder: folder ?? this.folder,
        account: account == null ? this.account : account(),
        lastSync: lastSync == null ? this.lastSync : lastSync(),
      );

  Json toJson() => {
        'on': on,
        'folder': folder,
        'account': ?account?.toJson(),
        'lastSync': ?lastSync?.toUtc().toIso8601String(),
      };

  static CloudSetting fromJson(Object? j) => j is Map
      ? CloudSetting(
          on: j['on'] == true,
          folder: (j['folder'] as String?)?.trim().isNotEmpty == true ? j['folder'] as String : defaultSyncFolder,
          account: CloudAccount.fromJson(j['account']),
          lastSync: DateTime.tryParse(j['lastSync'] as String? ?? '')?.toUtc(),
        )
      : const CloudSetting();
}

/// Sync & backup's settings (sync/settings.json; this device's only).
@immutable
class SyncSettings {
  const SyncSettings({
    this.device = '',
    this.google = const CloudSetting(),
    this.onedrive = const CloudSetting(),
    this.boardFiles = true,
    this.pdfCopy = false,
    this.media = true,
    this.wifiOnly = true,
    this.policy = MergePolicy.mergeBoth,
    this.synced = const {},
  });

  /// This device's id in stamps.
  final String device;
  final CloudSetting google;
  final CloudSetting onedrive;
  final bool boardFiles;
  final bool pdfCopy;
  final bool media;
  final bool wifiOnly;
  final MergePolicy policy;

  /// Notebook id → when the version last synced was last edited.
  final Map<String, DateTime> synced;

  CloudSetting of(CloudKind k) => k == CloudKind.onedrive ? onedrive : google;

  /// The clouds that are on and signed in.
  List<CloudKind> get active => [
        if (google.active) CloudKind.google,
        if (onedrive.active) CloudKind.onedrive,
      ];

  bool get anyOn => active.isNotEmpty;

  /// The last time every cloud that's on was synced.
  DateTime? get lastSync {
    DateTime? out;
    for (final k in active) {
      final t = of(k).lastSync;
      if (t == null) return null;
      if (out == null || t.isBefore(out)) out = t;
    }
    return out;
  }

  SyncSettings copyWith({
    String? device,
    CloudSetting? google,
    CloudSetting? onedrive,
    bool? boardFiles,
    bool? pdfCopy,
    bool? media,
    bool? wifiOnly,
    MergePolicy? policy,
    Map<String, DateTime>? synced,
  }) =>
      SyncSettings(
        device: device ?? this.device,
        google: google ?? this.google,
        onedrive: onedrive ?? this.onedrive,
        boardFiles: boardFiles ?? this.boardFiles,
        pdfCopy: pdfCopy ?? this.pdfCopy,
        media: media ?? this.media,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        policy: policy ?? this.policy,
        synced: synced ?? this.synced,
      );

  SyncSettings withCloud(CloudKind k, CloudSetting c) => k == CloudKind.onedrive ? copyWith(onedrive: c) : copyWith(google: c);

  Json toJson() => {
        'device': device,
        'google': google.toJson(),
        'onedrive': onedrive.toJson(),
        'boardFiles': boardFiles,
        'pdfCopy': pdfCopy,
        'media': media,
        'wifiOnly': wifiOnly,
        'policy': policy.name,
        'synced': {for (final e in synced.entries) e.key: e.value.toUtc().toIso8601String()},
      };

  static SyncSettings fromJson(Json? j) {
    if (j == null) return const SyncSettings();
    return SyncSettings(
      device: j['device'] as String? ?? '',
      google: CloudSetting.fromJson(j['google']),
      onedrive: CloudSetting.fromJson(j['onedrive']),
      boardFiles: j['boardFiles'] != false,
      pdfCopy: j['pdfCopy'] == true,
      media: j['media'] != false,
      wifiOnly: j['wifiOnly'] != false,
      policy: MergePolicy.values.where((p) => p.name == j['policy']).firstOrNull ?? MergePolicy.mergeBoth,
      synced: {
        if (j['synced'] is Map)
          for (final e in (j['synced'] as Map).entries)
            if (DateTime.tryParse('${e.value}') case final t?) e.key as String: t.toUtc(),
      },
    );
  }
}

/// What sync is doing.
enum SyncPhase {
  /// Nothing to do, or done.
  idle,
  syncing,

  /// No connection: it syncs when there is one.
  offline,

  /// "Only sync on Wi-Fi", and on mobile data.
  waitingForWifi,

  /// A cloud wants signing in again.
  signedOut,

  /// Something went wrong ([SyncState.message] says what).
  failed,
}

/// A big video going to the cloud.
@immutable
class VideoUpload {
  const VideoUpload({required this.notebookId, required this.itemId, required this.name, required this.kind, this.progress = 0, this.error});

  final String notebookId;
  final String itemId;
  final String name;
  final CloudKind kind;
  final double progress;
  final String? error;

  VideoUpload copyWith({double? progress, String? Function()? error}) => VideoUpload(
        notebookId: notebookId,
        itemId: itemId,
        name: name,
        kind: kind,
        progress: progress ?? this.progress,
        error: error == null ? this.error : error(),
      );
}

@immutable
class SyncState {
  const SyncState({
    required this.settings,
    this.phase = SyncPhase.idle,
    this.message,
    this.dirty = const {},
    this.uploads = const {},
  });

  final SyncSettings settings;
  final SyncPhase phase;
  final String? message;

  /// Notebooks changed here since they were last synced.
  final Set<String> dirty;

  /// Big videos going to the cloud, by item id.
  final Map<String, VideoUpload> uploads;

  /// Whether notebook [id], last edited [updatedAt], is the same here and
  /// in every cloud that's on.
  bool isSynced(String id, DateTime updatedAt) {
    if (!settings.anyOn || dirty.contains(id)) return false;
    final at = settings.synced[id];
    return at != null && !at.isBefore(updatedAt);
  }

  /// "Google Drive", "OneDrive", or "Google Drive and OneDrive".
  String get cloudNames => settings.active.map((k) => k.label).join(' and ');

  SyncState copyWith({
    SyncSettings? settings,
    SyncPhase? phase,
    String? Function()? message,
    Set<String>? dirty,
    Map<String, VideoUpload>? uploads,
  }) =>
      SyncState(
        settings: settings ?? this.settings,
        phase: phase ?? this.phase,
        message: message == null ? this.message : message(),
        dirty: dirty ?? this.dirty,
        uploads: uploads ?? this.uploads,
      );
}

/// Whether there's a connection, and whether it's unmetered (Wi-Fi).
typedef NetworkCheck = Future<({bool online, bool unmetered})> Function();

const _net = MethodChannel('endless/net');

Future<({bool online, bool unmetered})> _platformNetwork() async {
  if (kIsWeb || !Platform.isAndroid) return (online: true, unmetered: true);
  try {
    final r = await _net.invokeMapMethod<String, bool>('unmetered');
    return (online: r?['online'] ?? true, unmetered: r?['unmetered'] ?? true);
  } on Object {
    return (online: true, unmetered: true);
  }
}

final networkCheckProvider = Provider<NetworkCheck>((ref) => _platformNetwork);

/// Signing in, per cloud.
final cloudAuthProvider = Provider.family<CloudAuth, CloudKind>((ref, kind) => cloudAuthFor(kind));

/// The cloud for [kind], with its sign-in, in [folder].
typedef CloudFactory = CloudDrive Function(CloudKind kind, CloudAuth auth, String folder);

final cloudFactoryProvider = Provider<CloudFactory>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return (kind, auth, folder) => switch (kind) {
        CloudKind.onedrive => OneDriveCloud(auth, client, folder: folder),
        _ => GoogleDriveCloud(auth, client, folder: folder),
      };
});

/// Whether sync starts by itself (after changes, every few minutes, when
/// the app comes back). Tests turn it off and call [SyncController.syncNow].
final autoSyncProvider = Provider<bool>((ref) => true);

/// Settings as the app started (bootstrap loads sync/settings.json).
final initialSyncSettingsProvider = Provider<SyncSettings>((ref) => const SyncSettings());

final syncProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);

class SyncController extends Notifier<SyncState> {
  /// After a change to folders or decks, sync waits this long for more.
  static const settle = Duration(seconds: 8);

  /// A notebook changed here goes to the cloud at most this long after
  /// the change, even while writing goes on (only the notebooks changed).
  static const quickEvery = Duration(seconds: 5);

  /// And runs at least this often while the app is open.
  static const every = Duration(minutes: 5);

  late BoardStore _store;
  Timer? _soon;
  Timer? _tick;
  AppLifecycleListener? _life;
  Future<void>? _running;
  bool _again = false;

  /// Notebooks changed since the last quick sync, and its timer.
  final _quickIds = <String>{};
  Timer? _quick;
  final _againOnly = <String>{};

  @override
  SyncState build() {
    _store = ref.read(boardStoreProvider);
    var settings = ref.read(initialSyncSettingsProvider);
    if (settings.device.isEmpty) {
      settings = settings.copyWith(device: Stamper.newDevice());
      unawaited(_store.saveSyncFile('settings', settings.toJson()));
    }
    final changes = ref.read(localChangesProvider);
    void onChange() => _changed(changes.last);
    changes.addListener(onChange);
    ref.onDispose(() {
      changes.removeListener(onChange);
      _soon?.cancel();
      _tick?.cancel();
      _quick?.cancel();
      _life?.dispose();
    });
    return SyncState(settings: settings);
  }

  /// Starts syncing by itself (from the app, once it's up).
  void start() {
    if (!ref.read(autoSyncProvider)) return;
    _tick?.cancel();
    _tick = Timer.periodic(every, (_) => _auto());
    _life ??= AppLifecycleListener(onResume: _auto, onInactive: _leaving, onExitRequested: _exiting);
    _soon = Timer(const Duration(seconds: 3), _auto);
  }

  void _auto() {
    if (state.settings.anyOn) unawaited(syncNow());
  }

  /// Leaving the app (Home, another app, the screen off, or closing it):
  /// what isn't in the cloud yet goes now, while Endless is still allowed
  /// to finish. Nothing runs later in the background.
  void _leaving() => unawaited(finishBeforeLeaving());

  /// Closing the window on a computer: syncs first (at most 20 s).
  Future<AppExitResponse> _exiting() async {
    await finishBeforeLeaving(limit: const Duration(seconds: 20));
    return AppExitResponse.exit;
  }

  /// Whether anything here isn't in the cloud yet: a notebook saved since
  /// its last sync, or one open with changes still being written.
  bool get hasChangesToSend {
    if (!state.settings.anyOn) return false;
    if (state.dirty.isNotEmpty) return true;
    for (final n in ref.read(libraryProvider).notebooks) {
      if (ref.exists(notebookProvider(n.id)) && ref.read(notebookProvider(n.id).notifier).hasUnsaved) return true;
      if (!state.isSynced(n.id, n.updatedAt)) return true;
    }
    return false;
  }

  /// Saves what's open and syncs it, if anything isn't in the cloud yet.
  /// On Android a notification ("Syncing your notes") keeps Endless going
  /// until it's done, for [limit] at most, so leaving the app or swiping it
  /// away doesn't stop it halfway. Offline, nothing is lost: the notes are
  /// on the tablet and go the next time Endless is open.
  Future<void> finishBeforeLeaving({Duration limit = const Duration(minutes: 2)}) async {
    if (!hasChangesToSend) return;
    final tools = ref.read(audioToolsProvider);
    final kept = await tools.keepGoing(true, kind: 'sync', title: 'Syncing your notes', text: 'To ${state.cloudNames}');
    try {
      for (final n in ref.read(libraryProvider).notebooks) {
        if (ref.exists(notebookProvider(n.id))) await ref.read(notebookProvider(n.id).notifier).flush();
      }
      await syncNow().timeout(limit);
    } on TimeoutException {
      // What's left goes next time.
    } finally {
      if (kept) await tools.keepGoing(false, kind: 'sync');
    }
  }

  /// How many times each notebook has changed (so a change made while a
  /// sync runs isn't taken as sent).
  final _changes = <String, int>{};

  void _changed(String? notebookId) {
    if (!state.settings.anyOn) return;
    if (notebookId != null) _changes[notebookId] = (_changes[notebookId] ?? 0) + 1;
    if (notebookId != null && !state.dirty.contains(notebookId)) {
      state = state.copyWith(dirty: {...state.dirty, notebookId});
    }
    if (!ref.read(autoSyncProvider)) return;
    if (notebookId == null) {
      // Folders or decks: a full sync once the changes settle.
      _soon?.cancel();
      _soon = Timer(settle, _auto);
      return;
    }
    // A notebook: sent within a few seconds, and again every few seconds
    // while writing goes on (the timer isn't put off by more changes).
    _quickIds.add(notebookId);
    _quick ??= Timer(quickEvery, () {
      _quick = null;
      final ids = {..._quickIds};
      _quickIds.clear();
      if (ids.isEmpty || !state.settings.anyOn) return;
      // A notebook gone from here (deleted for good) is the full sync's.
      final here = {for (final n in ref.read(libraryProvider).notebooks) n.id};
      unawaited(ids.every(here.contains) ? syncNow(only: ids) : syncNow());
    });
  }

  Future<void> _save(SyncSettings s) async {
    state = state.copyWith(settings: s);
    await _store.saveSyncFile('settings', s.toJson());
  }

  /// What other devices' version history calls this one.
  String get deviceName {
    final who = ref.read(settingsProvider).userName?.trim();
    final what = kIsWeb
        ? 'browser'
        : Platform.isAndroid || Platform.isIOS
            ? 'tablet'
            : 'computer';
    return who == null || who.isEmpty ? 'Another $what' : '$who’s $what';
  }

  // Settings.

  /// Why [kind] can't be signed in to in this build, or null.
  String? notReady(CloudKind kind) => ref.read(cloudAuthProvider(kind)).notReady;

  /// Signs in to [kind] and turns it on. Returns why not, or null.
  Future<String?> connect(CloudKind kind) async {
    final auth = ref.read(cloudAuthProvider(kind));
    final why = auth.notReady;
    if (why != null) return why;
    try {
      final account = await auth.signIn();
      await _save(state.settings.withCloud(kind, state.settings.of(kind).copyWith(on: true, account: () => account)));
      unawaited(syncNow());
      unawaited(moveBigVideos());
      return null;
    } on CloudException catch (e) {
      return e.message;
    }
  }

  /// Signs out of [kind]; what's in the cloud stays there. Connecting
  /// again (with this account or another) sends everything to that one.
  Future<void> disconnect(CloudKind kind) async {
    await ref.read(cloudAuthProvider(kind)).signOut();
    await _save(state.settings.withCloud(kind, state.settings.of(kind).copyWith(on: false, account: () => null, lastSync: () => null)));
    await _forgetCloud(kind);
  }

  /// Forgets what [kind]'s folder had (another account or folder: start over).
  Future<void> _forgetCloud(CloudKind kind) async {
    for (final n in await _store.listSyncFiles()) {
      if (!n.startsWith('nb_') && n != 'pdf') continue;
      final side = await _store.loadSyncFile(n);
      if (side == null) continue;
      (side['remote'] as Map?)?.remove(kind.name);
      if (n == 'pdf') side.remove(kind.name);
      await _store.saveSyncFile(n, side);
    }
  }

  /// Turns syncing with [kind] on or off (signing in first if needed).
  Future<String?> setOn(CloudKind kind, bool on) async {
    final c = state.settings.of(kind);
    if (on && !c.connected) return connect(kind);
    await _save(state.settings.withCloud(kind, c.copyWith(on: on)));
    if (on) unawaited(syncNow());
    return null;
  }

  /// Syncs with [kind] in the folder called [folder] from now on.
  Future<void> setFolder(CloudKind kind, String folder) async {
    final f = folder.trim();
    if (f.isEmpty) return;
    await _save(state.settings.withCloud(kind, state.settings.of(kind).copyWith(folder: f, lastSync: () => null)));
    // Everything goes to the new folder: forget what the old one had.
    await _forgetCloud(kind);
    unawaited(syncNow());
  }

  /// Folders that can be picked for [kind] (Google: ones Endless made).
  Future<List<String>> foldersIn(CloudKind kind) async {
    final cloud = _cloud(kind);
    return switch (cloud) {
      GoogleDriveCloud() => cloud.folders(),
      OneDriveCloud() => cloud.folders(),
      _ => const <String>[],
    };
  }

  Future<void> setOptions({bool? boardFiles, bool? pdfCopy, bool? media, bool? wifiOnly, MergePolicy? policy}) async {
    await _save(state.settings.copyWith(boardFiles: boardFiles, pdfCopy: pdfCopy, media: media, wifiOnly: wifiOnly, policy: policy));
    if (pdfCopy == true || media == true || wifiOnly == false) unawaited(syncNow());
  }

  CloudDrive _cloud(CloudKind kind) =>
      ref.read(cloudFactoryProvider)(kind, ref.read(cloudAuthProvider(kind)), state.settings.of(kind).folder);

  // Syncing.

  /// Syncs now with every cloud that's on (Sync now, and the automatic
  /// runs). A call while one runs makes it run once more after.
  ///
  /// [only]: a quick sync of just those notebooks (while writing).
  Future<void> syncNow({bool manual = false, Set<String>? only}) {
    if (_running != null) {
      if (only == null) {
        _again = true;
      } else {
        _againOnly.addAll(only);
      }
      return _running!;
    }
    final run = _running = _run(manual: manual, only: only).whenComplete(() {
      _running = null;
      if (_again) {
        _again = false;
        _againOnly.clear();
        unawaited(syncNow());
      } else if (_againOnly.isNotEmpty) {
        final ids = {..._againOnly};
        _againOnly.clear();
        unawaited(syncNow(only: ids));
      }
    });
    return run;
  }

  Future<void> _run({required bool manual, Set<String>? only}) async {
    final settings = state.settings;
    final clouds = settings.active;
    if (clouds.isEmpty) {
      state = state.copyWith(phase: SyncPhase.idle, message: () => null);
      return;
    }
    final net = await ref.read(networkCheckProvider)();
    if (!net.online) {
      state = state.copyWith(phase: SyncPhase.offline, message: () => 'Offline · syncs when you’re connected');
      return;
    }
    if (settings.wifiOnly && !net.unmetered) {
      state = state.copyWith(phase: SyncPhase.waitingForWifi, message: () => 'Waiting for Wi-Fi');
      return;
    }
    state = state.copyWith(phase: SyncPhase.syncing, message: () => null);
    final changesBefore = {..._changes};
    final engine = SyncEngine(
      store: _store,
      host: _AppHost(ref),
      stamper: Stamper(settings.device),
      versions: ref.read(versionStoreProvider),
      options: SyncOptions(
        boardFiles: settings.boardFiles,
        pdfCopy: settings.pdfCopy,
        media: settings.media,
        policy: settings.policy,
        deviceName: deviceName,
      ),
    );
    Map<String, DateTime>? syncedEverywhere;
    var s = settings;
    try {
      for (final kind in clouds) {
        final report = await engine.syncAll(_cloud(kind), only: only);
        final now = ref.read(clockProvider)().toUtc();
        s = s.withCloud(kind, s.of(kind).copyWith(lastSync: () => now));
        syncedEverywhere = syncedEverywhere == null
            ? {...report.synced}
            : {
                for (final e in report.synced.entries)
                  if (syncedEverywhere.containsKey(e.key)) e.key: e.value,
              };
      }
      if (!ref.mounted) return;
      final synced = {...state.settings.synced, ...?syncedEverywhere};
      // Notebooks gone from here are no longer tracked.
      final ids = {for (final n in ref.read(libraryProvider).notebooks) n.id};
      synced.removeWhere((id, _) => !ids.contains(id));
      // A notebook changed again while syncing stays waiting.
      final stillDirty = {
        for (final id in state.dirty)
          if (_changes[id] != changesBefore[id] || !(syncedEverywhere?.containsKey(id) ?? false)) id,
      };
      state = state.copyWith(phase: SyncPhase.idle, message: () => null, dirty: stillDirty);
      await _save(state.settings.copyWith(
        google: s.google.copyWith(lastSync: () => s.google.lastSync),
        onedrive: s.onedrive.copyWith(lastSync: () => s.onedrive.lastSync),
        synced: synced,
      ));
      if (manual) unawaited(moveBigVideos());
    } on CloudException catch (e) {
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: switch (e.failure) {
          CloudFailure.offline => SyncPhase.offline,
          CloudFailure.signedOut => SyncPhase.signedOut,
          _ => SyncPhase.failed,
        },
        message: () => switch (e.failure) {
          CloudFailure.offline => 'Offline · syncs when you’re connected',
          _ => e.message,
        },
      );
    } on Object catch (e, st) {
      debugPrint('Sync failed: $e\n$st');
      if (!ref.mounted) return;
      state = state.copyWith(phase: SyncPhase.failed, message: () => 'Couldn’t sync: $e');
    }
  }

  // Big videos.

  /// The cloud big videos go to: Google Drive if it's on, else OneDrive.
  CloudKind? get videoCloud => state.settings.active.firstOrNull;

  final _cancels = <String, CloudCancel>{};

  /// Sends video [itemId]'s file (a big one kept on this device) to the
  /// cloud; the page keeps a link. Nothing if no cloud is on.
  Future<void> moveVideo(String notebookId, String itemId) async {
    final kind = videoCloud;
    if (kind == null || state.uploads.containsKey(itemId)) return;
    final nb = ref.read(notebookProvider(notebookId).notifier);
    final found = nb.videoClip(itemId);
    if (found == null) return;
    final (pageId, video) = found;
    final link = video.link;
    if (link == null || video.cloud != null) return;
    final file = File(p.join((await ref.read(videosDirProvider)()).path, link));
    if (!await file.exists()) return;
    final cancel = _cancels[itemId] = CloudCancel();
    void put(VideoUpload? u) => state = state.copyWith(uploads: {
          for (final e in state.uploads.entries)
            if (e.key != itemId) e.key: e.value,
          itemId: ?u,
        });
    var upload = VideoUpload(notebookId: notebookId, itemId: itemId, name: video.name, kind: kind);
    put(upload);
    final path = 'Videos/${p.basenameWithoutExtension(link)}${p.extension(link)}';
    try {
      final size = await file.length();
      await _cloud(kind).upload(path, file, cancel: cancel, progress: (f) {
        upload = upload.copyWith(progress: f);
        put(upload);
      });
      // The page keeps a link: where it is in the cloud.
      if (ref.exists(notebookProvider(notebookId))) {
        final now = ref.read(notebookProvider(notebookId).notifier).videoClip(itemId)?.$2;
        if (now != null) {
          ref.read(notebookProvider(notebookId).notifier).setQuietly(pageId, now.copyWith(cloud: () => VideoCloud(kind.name, path, size: size)));
        }
      }
      // Moved: this device's copy goes (it's fetched again when needed).
      final cache = await cachedVideo(link);
      await file.rename(cache.path).catchError((Object _) => file);
      put(null);
    } on CloudCancelled {
      put(null);
    } on CloudException catch (e) {
      put(upload.copyWith(error: () => e.message));
    } finally {
      _cancels.remove(itemId);
    }
  }

  void cancelVideo(String itemId) {
    _cancels[itemId]?.cancel();
    state = state.copyWith(uploads: {
      for (final e in state.uploads.entries)
        if (e.key != itemId) e.key: e.value,
    });
  }

  /// Sends every big video in open notebooks that isn't in the cloud yet.
  Future<void> moveBigVideos() async {
    if (videoCloud == null) return;
    for (final n in ref.read(libraryProvider).notebooks) {
      if (!ref.exists(notebookProvider(n.id))) continue;
      for (final (_, v) in ref.read(notebookProvider(n.id).notifier).mediaClips) {
        if (v is VideoItem && v.link != null && v.cloud == null) await moveVideo(n.id, v.id);
      }
    }
  }

  /// Where a big video moved to the cloud is kept when it's fetched again
  /// (the cache: Android may clear it).
  Future<File> cachedVideo(String link) async {
    final dir = Directory(p.join((await ref.read(videosDirProvider)()).path, 'cloud'));
    await dir.create(recursive: true);
    return File(p.join(dir.path, p.basename(link)));
  }

  /// Fetches video [v] from the cloud into the cache (to grab frames, trim
  /// or transcribe), or returns the copy already here.
  Future<File?> fetchVideo(VideoItem v, {void Function(double)? progress}) async {
    final link = v.link, c = v.cloud;
    if (link == null || c == null) return null;
    final f = await cachedVideo(link);
    if (await f.exists()) return f;
    final kind = CloudKind.values.where((k) => k.name == c.kind).firstOrNull;
    if (kind == null || !state.settings.of(kind).connected) return null;
    await _cloud(kind).download(c.path, f, progress: progress);
    return f;
  }

  /// Where to stream video [v] from the cloud, and the headers to send.
  Future<(Uri, Map<String, String>)?> streamVideo(VideoItem v) async {
    final c = v.cloud;
    if (c == null) return null;
    final kind = CloudKind.values.where((k) => k.name == c.kind).firstOrNull;
    if (kind == null || !state.settings.of(kind).connected) return null;
    try {
      return await _cloud(kind).media(c.path);
    } on CloudException {
      return null;
    }
  }
}

/// The app's side of the engine.
class _AppHost implements SyncHost {
  _AppHost(this.ref);

  final Ref ref;

  @override
  bool isOpen(String id) => ref.exists(notebookProvider(id));

  @override
  Future<void> flush(String id) async {
    if (isOpen(id)) await ref.read(notebookProvider(id).notifier).flush();
    await ref.read(writeQueueProvider).idle;
  }

  @override
  bool applyOpen(String id, BoardDoc from, BoardDoc to) =>
      isOpen(id) && ref.read(notebookProvider(id).notifier).applyRemote(from, to);

  @override
  Future<void> notebookWritten(String id, {required bool added}) async {
    await ref.read(libraryProvider.notifier).addFromStore(id);
    ref.read(studyProvider.notifier).forget(id);
    final index = ref.read(handwritingIndexProvider);
    await index.forgetNotebook(id);
    unawaited(index.catchUp());
  }

  @override
  Future<void> deleteNotebook(String id) => ref.read(libraryProvider.notifier).deleteForever(id);

  @override
  Future<void> applyRoot({
    required Map<String, Object?> foldersFrom,
    required Map<String, Object?> foldersTo,
    required Map<String, Object?> decksFrom,
    required Map<String, Object?> decksTo,
  }) async {
    if (hashJson(foldersFrom) != hashJson(foldersTo)) {
      await ref.read(libraryProvider.notifier).applyRemoteFolders(foldersFrom, foldersTo);
    }
    if (hashJson(decksFrom) != hashJson(decksTo)) ref.read(decksProvider.notifier).applyRemote(decksFrom, decksTo);
  }

  @override
  Future<Uint8List?> pdfOf(String id) async {
    final loaded = ref.listen(loadedNotebookProvider(id), (_, _) {});
    try {
      await ref.read(loadedNotebookProvider(id).future);
      final open = ref.listen(notebookProvider(id), (_, _) {});
      try {
        final file = await ref.read(transfersProvider).export(id, scope: ExportScope.notebook, format: ExportFormat.pdf, current: 0);
        return file.bytes;
      } finally {
        open.close();
      }
    } on Object catch (e) {
      debugPrint('Sync: no PDF of $id: $e');
      return null;
    } finally {
      loaded.close();
    }
  }

  @override
  Future<T> exclusive<T>(Future<T> Function() task) async {
    late T out;
    await ref.read(writeQueueProvider).run(() async => out = await task());
    return out;
  }
}

/// Loads sync/settings.json (bootstrap).
Future<SyncSettings> loadSyncSettings(BoardStore store) async => SyncSettings.fromJson(await store.loadSyncFile('settings'));

/// The settings file as text (for tests).
String debugSyncSettings(SyncSettings s) => jsonEncode(s.toJson());
