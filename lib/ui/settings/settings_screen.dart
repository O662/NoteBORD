import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../canvas/live_items.dart' show agoText;
import '../../library/library.dart';
import '../../sync/cloud.dart';
import '../../sync/doc.dart' show MergePolicy;
import '../../sync/sync_state.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../canvas/top_bar.dart' show showQuickSettings;
import '../dialogs.dart';
import '../icons.dart';
import '../routes.dart';

// Settings (Sync.png). Sync & backup is built; the other sections open
// what exists so far (the stand-in Settings dialog) until they're designed
// into this screen.

enum SettingsSection {
  account('Account'),
  pen('Pen & S Pen'),
  handwriting('Handwriting & search'),
  sync('Sync & backup'),
  themes('Themes & dark mode'),
  about('About');

  const SettingsSection(this.label);

  final String label;

  static SettingsSection parse(String? s) => values.where((v) => v.name == s).firstOrNull ?? sync;
}

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.section = SettingsSection.sync});

  final SettingsSection section;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late var _section = widget.section;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.bg,
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(
          container: true,
          label: 'Settings',
          explicitChildNodes: true,
          child: Container(
            width: 272,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
            decoration: BoxDecoration(color: c.side, border: Border(right: BorderSide(color: c.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 4, children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(spacing: 6, children: [
                  Semantics(
                    button: true,
                    label: 'Back to library',
                    excludeSemantics: true,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(Radii.button),
                      onTap: () => context.canPop() ? context.pop() : context.go(Routes.start),
                      child: SizedBox(width: 44, height: 44, child: Center(child: EIcon(EIcons.back, size: 22, color: c.text))),
                    ),
                  ),
                  Flexible(
                    child: Text('Settings',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 26, color: c.text)),
                  ),
                ]),
              ),
              for (final s in SettingsSection.values)
                Semantics(
                  button: true,
                  selected: s == _section,
                  label: s.label,
                  excludeSemantics: true,
                  child: Material(
                    color: s == _section ? c.sideSelected : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _section = s),
                      child: Container(
                        height: 46,
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        alignment: Alignment.centerLeft,
                        child: Text(
                          s.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: s == _section ? FontWeight.w600 : FontWeight.w400, color: c.text),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 56, vertical: 32),
                child: _section == SettingsSection.sync ? const SyncSettingsPanel() : _OtherSection(_section),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Sections not built into this screen yet.
class _OtherSection extends StatelessWidget {
  const _OtherSection(this.section);

  final SettingsSection section;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final about = section == SettingsSection.about;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 16, children: [
      Text(section.label, style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 40, height: 1.2, color: c.text, letterSpacing: -0.8)),
      Text(
        about
            ? 'Endless · a handwriting-first notebook. Licences for the fonts, models and packages it uses are on the licences page.'
            : 'These settings are in the Settings window for now (also from ⋯ → Settings in a notebook).',
        style: TextStyle(fontSize: 15, color: c.textMuted),
      ),
      SecondaryButton(
        label: about ? 'Licences' : 'Open Settings',
        onPressed: () => about ? showLicensePage(context: context, applicationName: 'Endless') : showQuickSettings(context),
      ),
    ]);
  }
}

/// Settings › Sync & backup (Sync.png).
class SyncSettingsPanel extends ConsumerWidget {
  const SyncSettingsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final sync = ref.watch(syncProvider);
    final s = sync.settings;
    final ctrl = ref.read(syncProvider.notifier);
    final busy = sync.phase == SyncPhase.syncing;
    final problem = switch (sync.phase) {
      SyncPhase.offline || SyncPhase.waitingForWifi || SyncPhase.signedOut || SyncPhase.failed => sync.message,
      _ => null,
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 24, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, spacing: 24, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 6, children: [
            Semantics(
              header: true,
              child: Text('Sync & backup',
                  style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 40, height: 1.2, color: c.text, letterSpacing: -0.8)),
            ),
            Text(
              'Notebooks are saved on this tablet first, then copied to your cloud. You can keep writing offline.',
              style: TextStyle(fontSize: 15, color: c.textMuted),
            ),
            if (problem != null)
              Semantics(liveRegion: true, child: Text(problem, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.clay))),
          ]),
        ),
        PrimaryButton(
          label: busy ? 'Syncing…' : 'Sync now',
          icon: EIcons.sync,
          height: 46,
          padding: 18,
          onPressed: busy || !s.anyOn ? null : () => ctrl.syncNow(manual: true),
        ),
      ]),
      _Section(title: 'Cloud storage', children: [
        _CloudRow(kind: CloudKind.google, setting: s.google, other: s.onedrive),
        _CloudRow(kind: CloudKind.onedrive, setting: s.onedrive, other: s.google),
      ]),
      _Section(title: 'What gets synced', children: [
        _SwitchRow(
          title: 'Notebooks as board files',
          subtitle: 'Fully editable on your other devices',
          value: s.boardFiles,
          onChanged: (v) => ctrl.setOptions(boardFiles: v),
        ),
        _SwitchRow(
          title: 'Also save a PDF copy of each notebook',
          subtitle: 'Lets you open notes straight from Drive or OneDrive',
          value: s.pdfCopy,
          onChanged: (v) => ctrl.setOptions(pdfCopy: v),
        ),
        _SwitchRow(
          title: 'Images and imported PDFs',
          subtitle: 'Turn off to save cloud space',
          value: s.media,
          onChanged: (v) => ctrl.setOptions(media: v),
        ),
        _SwitchRow(
          title: 'Only sync on Wi-Fi',
          subtitle: 'Saves mobile data',
          value: s.wifiOnly,
          onChanged: (v) => ctrl.setOptions(wifiOnly: v),
        ),
      ]),
      Container(
        constraints: const BoxConstraints(minHeight: 64),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(16)),
        child: Row(spacing: 16, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text('When a notebook changed on two devices', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text)),
              Text(
                s.policy == MergePolicy.mergeBoth
                    ? 'Strokes never overwrite each other; each one has its own ID.'
                    : 'The copy changed last wins; the other is kept in version history.',
                style: TextStyle(fontSize: 13, color: c.textMuted),
              ),
            ]),
          ),
          _PolicyButton(policy: s.policy, onPick: (p) => ctrl.setOptions(policy: p)),
        ]),
      ),
    ]);
  }
}

String policyLabel(MergePolicy p) => switch (p) {
      MergePolicy.mergeBoth => 'Merge both',
      MergePolicy.newestWins => 'Keep the newest',
    };

class _PolicyButton extends StatelessWidget {
  const _PolicyButton({required this.policy, required this.onPick});

  final MergePolicy policy;
  final ValueChanged<MergePolicy> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopupMenuButton<MergePolicy>(
      tooltip: '',
      initialValue: policy,
      onSelected: onPick,
      color: c.surface,
      itemBuilder: (_) => [
        for (final p in MergePolicy.values)
          PopupMenuItem(value: p, height: 48, child: Text(policyLabel(p), style: TextStyle(fontSize: 15, color: c.text))),
      ],
      child: Semantics(
        button: true,
        label: 'When a notebook changed on two devices: ${policyLabel(policy)}',
        excludeSemantics: true,
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(border: Border.all(color: c.lineStrong), borderRadius: BorderRadius.circular(10)),
          child: Row(mainAxisSize: MainAxisSize.min, spacing: 8, children: [
            Text(policyLabel(policy), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.text)),
            EIcon(EIcons.chevronDown, size: 14, color: c.text),
          ]),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: [
      Semantics(
        header: true,
        child: Text(title.toUpperCase(),
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.96, color: c.textMuted)),
      ),
      Container(
        decoration: BoxDecoration(color: c.surface, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(16)),
        child: Column(children: [
          for (final (i, child) in children.indexed)
            DecoratedBox(
              decoration: BoxDecoration(border: i < children.length - 1 ? Border(bottom: BorderSide(color: c.lineSoft)) : null),
              child: child,
            ),
        ]),
      ),
    ]);
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.title, required this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minHeight: 60),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      child: Row(spacing: 16, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text)),
            Text(subtitle, style: TextStyle(fontSize: 13, color: c.textMuted)),
          ]),
        ),
        SyncSwitch(label: title, value: value, onChanged: onChanged),
      ]),
    );
  }
}

/// Sync.dc.html's switch: a 50 × 30 track in a 56 × 44 target.
class SyncSwitch extends StatelessWidget {
  const SyncSwitch({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      toggled: value,
      label: label,
      enabled: onChanged != null,
      excludeSemantics: true,
      onTap: onChanged == null ? null : () => onChanged!(!value),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: SizedBox(
          width: 56,
          height: 44,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 50,
              height: 30,
              padding: const EdgeInsets.all(3),
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              decoration: BoxDecoration(color: value ? c.accent : c.switchOff, borderRadius: BorderRadius.circular(Radii.chip)),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: c.surface,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: c.shadow, blurRadius: 2, offset: const Offset(0, 1))],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One cloud: its icon, name, what it's doing, Change folder or Connect,
/// and its switch.
class _CloudRow extends ConsumerWidget {
  const _CloudRow({required this.kind, required this.setting, required this.other});

  final CloudKind kind;
  final CloudSetting setting;
  final CloudSetting other;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final ctrl = ref.read(syncProvider.notifier);
    final sync = ref.watch(syncProvider);
    final now = ref.read(clockProvider)().toUtc();
    final last = setting.lastSync;
    final String sub;
    if (!setting.connected) {
      sub = other.connected ? 'Not connected. Turn on both to keep a copy in each.' : 'Not connected.';
    } else if (!setting.on) {
      sub = '${setting.account!.email} · turned off';
    } else {
      final when = sync.phase == SyncPhase.syncing ? 'syncing…' : (last == null ? 'not synced yet' : 'synced ${agoText(last, now)}');
      sub = 'Connected · saving to “${setting.folder}” · $when';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(spacing: 16, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: setting.active ? c.greenTint : c.accentTint, borderRadius: BorderRadius.circular(Radii.button)),
          child: Center(child: EIcon(setting.active ? EIcons.cloudCheck : EIcons.cloud, size: 22, color: setting.active ? c.green : c.accent)),
        ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
            Text(kind.label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
            Text(sub, style: TextStyle(fontSize: 13, color: c.textMuted)),
          ]),
        ),
        if (setting.connected) ...[
          SecondaryButton(
            label: 'Change folder',
            height: 44,
            padding: 14,
            onPressed: () => showFolderDialog(context, ref, kind),
          ),
          SyncSwitch(
            label: 'Sync with ${kind.label}',
            value: setting.on,
            onChanged: (v) => _report(context, ctrl.setOn(kind, v)),
          ),
        ] else
          Semantics(
            button: true,
            label: 'Connect ${kind.label}',
            excludeSemantics: true,
            child: Material(
              color: c.accent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _report(context, ctrl.connect(kind)),
                child: Container(
                  height: 44,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  alignment: Alignment.center,
                  child: Text('Connect', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.onAccent)),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Future<void> _report(BuildContext context, Future<String?> done) async {
    final why = await done;
    if (why == null || !context.mounted) return;
    await showMessage(context, title: google ? 'Can’t connect Google Drive' : 'Can’t connect OneDrive', message: why);
  }

  bool get google => kind == CloudKind.google;
}

/// Change folder: the folders Endless can use there, or a new name.
Future<void> showFolderDialog(BuildContext context, WidgetRef ref, CloudKind kind) =>
    showEndlessDialog<void>(context, builder: (_) => _FolderDialog(kind: kind));

class _FolderDialog extends ConsumerStatefulWidget {
  const _FolderDialog({required this.kind});

  final CloudKind kind;

  @override
  ConsumerState<_FolderDialog> createState() => _FolderDialogState();
}

class _FolderDialogState extends ConsumerState<_FolderDialog> {
  late final _name = TextEditingController(text: ref.read(syncProvider).settings.of(widget.kind).folder);
  List<String>? _folders;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(syncProvider.notifier).foldersIn(widget.kind).then((f) {
      if (mounted) setState(() => _folders = [...f]..sort());
    }, onError: (Object e) {
      if (mounted) setState(() => _error = 'Couldn’t list folders: $e');
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _use() async {
    final name = _name.text.trim();
    if (name.isEmpty || name.contains('/')) {
      setState(() => _error = 'Give the folder a name (without “/”).');
      return;
    }
    await ref.read(syncProvider.notifier).setFolder(widget.kind, name);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final folders = _folders;
    return DialogFrame(
      title: widget.kind.label,
      width: 520,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 14, children: [
        if (ref.watch(syncProvider).settings.of(widget.kind).account case final account?)
          Row(spacing: 12, children: [
            Expanded(
              child: Text('Signed in as ${account.email}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text)),
            ),
            SecondaryButton(
              label: 'Use another account',
              height: 44,
              padding: 14,
              onPressed: () async {
                final ctrl = ref.read(syncProvider.notifier);
                Navigator.of(context).pop();
                await ctrl.disconnect(widget.kind);
                await ctrl.connect(widget.kind);
              },
            ),
          ]),
        Text(
          widget.kind == CloudKind.google
              ? 'Notebooks go in this folder in My Drive. Endless can only see folders it made, so pick one of those or name a new one.'
              : 'Notebooks go in this folder at the top of your OneDrive. Pick one or name a new one.',
          style: TextStyle(fontSize: 14, color: c.textMuted),
        ),
        if (folders == null && _error == null)
          const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
        else if (folders != null && folders.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: ListView(shrinkWrap: true, children: [
              for (final f in folders)
                ListTile(
                  minTileHeight: 48,
                  title: Text(f, style: TextStyle(fontSize: 15, color: c.text)),
                  trailing: f == _name.text ? EIcon(EIcons.check, size: 18, color: c.accent) : null,
                  onTap: () => setState(() => _name.text = f),
                ),
            ]),
          ),
        TextField(
          controller: _name,
          inputFormatters: [LengthLimitingTextInputFormatter(80)],
          decoration: const InputDecoration(labelText: 'Folder name'),
          onSubmitted: (_) => _use(),
        ),
        if (_error != null) Text(_error!, style: TextStyle(fontSize: 13, color: c.clay)),
        Text(
          'Changing the folder copies your notebooks into it; the old folder stays as it is.',
          style: TextStyle(fontSize: 13, color: c.textMuted),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [
          SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
          PrimaryButton(label: 'Use this folder', onPressed: _use),
        ]),
      ]),
    );
  }
}

/// Opens Settings › Sync & backup.
void openSyncSettings(BuildContext context) => context.push(Routes.settings('sync'));
