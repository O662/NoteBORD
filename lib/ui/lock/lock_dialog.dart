import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../canvas/pane.dart';
import '../../state/biometric.dart';
import '../../state/notebook.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../dialogs.dart';
import '../icons.dart';

/// Shortest password accepted.
const minPasswordLength = 4;

/// ⋯ → Password protect (design/screens/Lock.png). For a page or notebook
/// that already has a password, offers to lock it now or remove it.
Future<void> showLockDialog(BuildContext context, Pane pane) => showEndlessDialog<void>(
      context,
      dismissible: false,
      builder: (context) => _LockDialog(pane: pane),
    );

class _LockDialog extends ConsumerWidget {
  const _LockDialog({required this.pane});

  final Pane pane;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nb = ref.watch(notebookProvider(pane.notebookId));
    final pageId = nb.pageAt(pane.page).id;
    if (nb.hasPageLock(pageId) || nb.notebookLocked) {
      return _ManageLock(pane: pane, pageLock: nb.hasPageLock(pageId));
    }
    return SetPasswordDialog(pane: pane);
  }
}

enum LockScope { page, notebook }

class SetPasswordDialog extends ConsumerStatefulWidget {
  const SetPasswordDialog({super.key, required this.pane});

  final Pane pane;

  @override
  ConsumerState<SetPasswordDialog> createState() => _SetPasswordDialogState();
}

class _SetPasswordDialogState extends ConsumerState<SetPasswordDialog> {
  final _password = TextEditingController();
  final _again = TextEditingController();
  final _hint = TextEditingController();
  LockScope _scope = LockScope.page;
  bool _biometric = true;
  bool? _biometricAvailable;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(biometricProvider).isAvailable().then((ok) {
      if (mounted) setState(() => _biometricAvailable = ok);
    });
  }

  @override
  void dispose() {
    _password.dispose();
    _again.dispose();
    _hint.dispose();
    super.dispose();
  }

  bool get _ready => _password.text.length >= minPasswordLength && _again.text.isNotEmpty;

  Future<void> _lock() async {
    if (_password.text != _again.text) {
      setState(() => _error = 'The passwords don’t match');
      return;
    }
    setState(() {
      _error = null;
      _busy = true;
    });
    final notebook = ref.read(notebookProvider(widget.pane.notebookId).notifier);
    final pageId = ref.read(notebookProvider(widget.pane.notebookId)).pageAt(widget.pane.page).id;
    final biometric = _biometric && (_biometricAvailable ?? false);
    if (_scope == LockScope.page) {
      await notebook.lockPage(pageId, _password.text, hint: _hint.text, biometric: biometric);
    } else {
      await notebook.lockNotebook(_password.text, hint: _hint.text, biometric: biometric);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(widget.pane.notebookId));
    final page = widget.pane.page.clamp(0, nb.pages.length - 1) + 1;
    final available = _biometricAvailable ?? false;
    return DialogFrame(
      title: 'Password protect',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
        Semantics(
          label: 'What to lock',
          container: true,
          explicitChildNodes: true,
          child: Row(spacing: 10, children: [
            Expanded(
              child: _ScopeCard(
                label: 'This page',
                sub: 'Page $page only',
                selected: _scope == LockScope.page,
                onTap: () => setState(() => _scope = LockScope.page),
              ),
            ),
            Expanded(
              child: _ScopeCard(
                label: 'Whole notebook',
                sub: nb.pages.length == 1 ? 'Its 1 page' : 'All ${nb.pages.length} pages',
                selected: _scope == LockScope.notebook,
                onTap: () => setState(() => _scope = LockScope.notebook),
              ),
            ),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 12, children: [
          LabeledField(
            label: 'Password',
            controller: _password,
            obscure: true,
            autofocus: true,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _error = null),
          ),
          LabeledField(
            label: 'Type it again',
            controller: _again,
            obscure: true,
            errorText: _error,
            textInputAction: TextInputAction.next,
            onChanged: (_) => setState(() => _error = null),
          ),
          LabeledField(label: 'Hint (optional)', controller: _hint, hint: 'Something only you would understand'),
        ]),
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(spacing: 16, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                Text('Unlock with fingerprint or face', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text)),
                Text(
                  _biometricAvailable == false
                      ? 'This tablet can’t check a fingerprint or face'
                      : 'The password still works on your other devices',
                  style: TextStyle(fontSize: 13, color: c.textMuted),
                ),
              ]),
            ),
            EndlessSwitch(
              label: 'Unlock with fingerprint or face',
              value: _biometric && available,
              onChanged: available ? (v) => setState(() => _biometric = v) : null,
            ),
          ]),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: c.warningTint, borderRadius: BorderRadius.circular(Radii.button)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, spacing: 12, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: EIcon(EIcons.warning, color: c.onWarning)),
            Expanded(
              child: Text(
                _scope == LockScope.page
                    ? 'Locked pages are encrypted here and in the cloud. If you forget the password, nobody can recover them — not even us.'
                    : 'Locked notebooks are encrypted here and in the cloud. If you forget the password, nobody can recover them — not even us.',
                style: TextStyle(fontSize: 14, height: 1.45, color: c.onWarning),
              ),
            ),
          ]),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [
          SecondaryButton(label: 'Cancel', onPressed: _busy ? null : () => Navigator.of(context).pop()),
          PrimaryButton(
            label: _busy ? 'Locking…' : (_scope == LockScope.page ? 'Lock page' : 'Lock notebook'),
            icon: EIcons.lock,
            onPressed: _busy || !_ready ? null : _lock,
          ),
        ]),
      ]),
    );
  }
}

class _ScopeCard extends StatelessWidget {
  const _ScopeCard({required this.label, required this.sub, required this.selected, required this.onTap});

  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      button: true,
      label: '$label, $sub',
      excludeSemantics: true,
      child: Material(
        color: selected ? c.accentWash : c.surface,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: selected ? c.accent : c.lineSoft, width: 2),
          borderRadius: BorderRadius.circular(Radii.card),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.card),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
              Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
              Text(sub, style: TextStyle(fontSize: 13, color: c.textMuted)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The design's switch: 50×30 track, 24 dp knob, in a 56×44 target.
class EndlessSwitch extends StatelessWidget {
  const EndlessSwitch({super.key, required this.label, required this.value, required this.onChanged});

  final String label;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? () => onChanged!(!value) : null,
        child: SizedBox(
          width: 56,
          height: 44,
          child: Center(
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
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
                    boxShadow: [BoxShadow(color: c.shadow.withValues(alpha: 0.25), blurRadius: 2, offset: const Offset(0, 1))],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A page or notebook that already has a password.
class _ManageLock extends ConsumerStatefulWidget {
  const _ManageLock({required this.pane, required this.pageLock});

  final Pane pane;
  final bool pageLock;

  @override
  ConsumerState<_ManageLock> createState() => _ManageLockState();
}

class _ManageLockState extends ConsumerState<_ManageLock> {
  bool _busy = false;

  Future<void> _run(Future<void> Function(NotebookNotifier n, String pageId) action) async {
    setState(() => _busy = true);
    final n = ref.read(notebookProvider(widget.pane.notebookId).notifier);
    final pageId = ref.read(notebookProvider(widget.pane.notebookId)).pageAt(widget.pane.page).id;
    await action(n, pageId);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final page = widget.pane.page + 1;
    return DialogFrame(
      title: 'Password protect',
      width: 520,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
        Text(
          widget.pageLock
              ? 'Page $page has a password. It is unlocked until you lock it again or leave the notebook.'
              : 'This notebook has a password. It is unlocked until you lock it again or leave it.',
          style: TextStyle(fontSize: 15, height: 1.45, color: c.textMuted),
        ),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [
          SecondaryButton(
            label: 'Remove password',
            onPressed: _busy
                ? null
                : () => _run((n, id) => widget.pageLock ? n.removePageLock(id) : n.removeNotebookLock()),
          ),
          PrimaryButton(
            label: widget.pageLock ? 'Lock page now' : 'Lock notebook now',
            icon: EIcons.lock,
            onPressed: _busy ? null : () => _run((n, _) => n.lockNow()),
          ),
        ]),
      ]),
    );
  }
}
