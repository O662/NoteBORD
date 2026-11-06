import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../library/library.dart';
import '../../state/notebook.dart';
import '../../sync/cloud.dart';
import '../../sync/sync_state.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../icons.dart';
import '../library/format.dart';

// Sync's status where it shows outside Settings: the title pill, the
// sidebar card (Main.png: "Synced · Google Drive / 2 minutes ago"), the
// "Waiting to sync" badge on covers, and a big video's upload card
// (Video.png).

/// What the title pill says after "Page 2 of 5 · ".
String saveStatusLabel(SaveStatus save, SyncState sync, String notebookId, DateTime updatedAt) => switch (save) {
      SaveStatus.saving => 'Saving…',
      SaveStatus.failed => 'Couldn’t save · retrying',
      SaveStatus.saved when !sync.settings.anyOn => 'Saved on this tablet',
      SaveStatus.saved when sync.isSynced(notebookId, updatedAt) => 'Synced to ${sync.cloudNames}',
      SaveStatus.saved => 'Saved',
    };

/// The sidebar's card: what sync is doing, and when it last synced. A tap
/// opens Settings › Sync & backup.
class SyncStatusCard extends ConsumerWidget {
  const SyncStatusCard({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sync = ref.watch(syncProvider);
    final now = ref.read(clockProvider)().toUtc();
    final s = sync.settings;
    final last = s.lastSync;
    final (EIconData icon, Color tint, String title, String sub) = switch (sync.phase) {
      _ when !s.anyOn => (EIcons.deviceSaved, c.green, 'Saved on this tablet', 'Sync isn’t set up'),
      SyncPhase.syncing => (EIcons.sync, c.accent, 'Syncing…', sync.cloudNames),
      SyncPhase.offline => (EIcons.cloudOff, c.textMuted, 'Waiting to sync', 'Offline'),
      SyncPhase.waitingForWifi => (EIcons.cloudOff, c.textMuted, 'Waiting to sync', 'Waiting for Wi-Fi'),
      SyncPhase.signedOut => (EIcons.cloudOff, c.clay, 'Sign in again', sync.message ?? sync.cloudNames),
      SyncPhase.failed => (EIcons.cloudOff, c.clay, 'Couldn’t sync', sync.message ?? 'Tap for details'),
      SyncPhase.idle when last == null => (EIcons.cloud, c.textMuted, 'Waiting to sync', sync.cloudNames),
      SyncPhase.idle => (EIcons.cloudCheck, c.green, 'Synced · ${_short(sync)}', _capital(agoPhrase(last!, now))),
    };
    return Semantics(
      button: true,
      label: '$title. $sub. Sync and backup settings',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(side: BorderSide(color: c.line), borderRadius: BorderRadius.circular(Radii.button)),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(spacing: 10, children: [
              EIcon(icon, size: 22, color: tint),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                  Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
                  Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.textMuted)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  static String _short(SyncState s) => s.settings.active.length > 1 ? 'Drive and OneDrive' : s.cloudNames;
  static String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

/// "Waiting to sync" on a cover (Main.dc.html), when the notebook has
/// changes the cloud doesn't have yet.
class WaitingToSyncBadge extends ConsumerWidget {
  const WaitingToSyncBadge({super.key, required this.entry});

  final NotebookEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final waiting = ref.watch(syncProvider.select((s) => s.settings.anyOn && !s.isSynced(entry.id, entry.updatedAt)));
    if (!waiting) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: c.warningTint, borderRadius: BorderRadius.circular(Radii.chip)),
      child: Text('Waiting to sync', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.onWarning)),
    );
  }
}

/// A big video going to the cloud (Video.png): its name, "Uploading to
/// Google Drive · 64%", Cancel, the bar, and what happens.
class VideoUploadCard extends ConsumerWidget {
  const VideoUploadCard({super.key, required this.upload});

  final VideoUpload upload;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final pct = (upload.progress * 100).round();
    final failed = upload.error != null;
    return Semantics(
      container: true,
      label: 'Uploading a video',
      explicitChildNodes: true,
      child: Container(
        width: 390,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Radii.card),
          boxShadow: [BoxShadow(color: c.shadow, blurRadius: 24, offset: const Offset(0, 12), spreadRadius: -18)],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
          Row(spacing: 10, children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: c.plumTint, borderRadius: BorderRadius.circular(10)),
              child: Center(child: EIcon(EIcons.video, size: 18, color: c.plum)),
            ),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 1, children: [
                Text(upload.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.text)),
                Text(
                  failed ? 'Couldn’t upload to ${upload.kind.label} · ${upload.error}' : 'Uploading to ${upload.kind.label} · $pct%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: failed ? c.clay : c.textMuted),
                ),
              ]),
            ),
            Semantics(
              button: true,
              label: failed ? 'Try again' : 'Cancel',
              excludeSemantics: true,
              child: Material(
                color: Colors.transparent,
                shape: RoundedRectangleBorder(side: BorderSide(color: c.lineStrong), borderRadius: BorderRadius.circular(Radii.chip)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Radii.chip),
                  onTap: () {
                    final sync = ref.read(syncProvider.notifier);
                    sync.cancelVideo(upload.itemId);
                    if (failed) sync.moveVideo(upload.notebookId, upload.itemId);
                  },
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    alignment: Alignment.center,
                    child: Text(failed ? 'Try again' : 'Cancel', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
                  ),
                ),
              ),
            ),
          ]),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.chip),
            child: SizedBox(
              height: 6,
              child: Stack(children: [
                Positioned.fill(child: ColoredBox(color: c.side)),
                FractionallySizedBox(widthFactor: upload.progress.clamp(0, 1), child: ColoredBox(color: c.plum)),
              ]),
            ),
          ),
          Text(
            'You can already play it here. Big videos live in your ${upload.kind == CloudKind.google ? 'Drive' : 'OneDrive'}; the page keeps a link.',
            style: TextStyle(fontSize: 12, color: c.textMuted),
          ),
        ]),
      ),
    );
  }
}
