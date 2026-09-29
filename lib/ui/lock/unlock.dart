import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/notebook.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../dialogs.dart';
import '../icons.dart';

/// Over a locked page: the frosted page and the unlock card
/// (design/screens/Lock.png, "locked" state).
class LockedOverlay extends ConsumerWidget {
  const LockedOverlay({
    super.key,
    required this.notebookId,
    required this.pageId,
    required this.pageNumber,
    this.onBack,
    this.compact = false,
  });

  final String notebookId;
  final String pageId;
  final int pageNumber;

  /// "Back to library"; hidden when null.
  final VoidCallback? onBack;

  /// Inside a split pane: a narrower card without autofocus.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    return Stack(fit: StackFit.expand, children: [
      ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: ColoredBox(color: c.frost),
        ),
      ),
      Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: UnlockCard(
            key: ValueKey(pageId),
            notebookId: notebookId,
            pageId: pageId,
            pageNumber: pageNumber,
            onBack: onBack,
            compact: compact,
          ),
        ),
      ),
    ]);
  }
}

class UnlockCard extends ConsumerStatefulWidget {
  const UnlockCard({
    super.key,
    required this.notebookId,
    required this.pageId,
    required this.pageNumber,
    this.onBack,
    this.compact = false,
  });

  final String notebookId;
  final String pageId;
  final int pageNumber;
  final VoidCallback? onBack;
  final bool compact;

  @override
  ConsumerState<UnlockCard> createState() => _UnlockCardState();
}

class _UnlockCardState extends ConsumerState<UnlockCard> {
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  NotebookNotifier get _notebook => ref.read(notebookProvider(widget.notebookId).notifier);

  Future<void> _unlock() async {
    if (_password.text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await _notebook.unlock(widget.pageId, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'That password didn’t work. Try again.';
    });
  }

  Future<void> _biometric() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await _notebook.unlockWithBiometrics(widget.pageId, reason: 'Unlock your notes');
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = 'Couldn’t unlock with your fingerprint. Use the password.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final nb = ref.watch(notebookProvider(widget.notebookId));
    final entry = nb.lockFor(widget.pageId);
    final wholeNotebook = !nb.hasPageLock(widget.pageId);
    return Semantics(
      container: true,
      label: 'Locked',
      explicitChildNodes: true,
      child: Container(
        width: widget.compact ? 360 : 420,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(22),
          boxShadow: c.modalShadow,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, spacing: 14, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: c.side, shape: BoxShape.circle),
            child: Center(child: EIcon(EIcons.lock, size: 30, color: c.text)),
          ),
          Semantics(
            header: true,
            child: Text(
              wholeNotebook ? 'This notebook is locked' : 'This page is locked',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 28, color: c.text),
            ),
          ),
          if (entry?.hint != null)
            Text('Hint: ${entry!.hint}', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.textMuted)),
          LabeledField(
            label: 'Password',
            controller: _password,
            obscure: true,
            autofocus: !widget.compact,
            errorText: _error,
            textInputAction: TextInputAction.go,
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _unlock(),
          ),
          SizedBox(
            width: double.infinity,
            child: PrimaryButton(
              label: _busy ? 'Unlocking…' : 'Unlock',
              expand: true,
              onPressed: _busy ? null : _unlock,
            ),
          ),
          if (entry?.biometric ?? false)
            SizedBox(
              width: double.infinity,
              child: SecondaryButton(
                label: 'Use fingerprint',
                icon: EIcons.fingerprint,
                expand: true,
                onPressed: _busy ? null : _biometric,
              ),
            ),
          if (widget.onBack != null)
            Semantics(
              link: true,
              label: 'Back to library',
              excludeSemantics: true,
              child: InkWell(
                onTap: widget.onBack,
                child: SizedBox(
                  height: 44,
                  child: Center(
                    child: Text('Back to library', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.accent)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
