import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart';
import '../../canvas/live_items.dart' show clockText;
import '../../canvas/page_runtime.dart';
import '../../canvas/pane.dart';
import '../../library/library.dart' show clockProvider;
import '../../state/notebook.dart';
import '../../sync/versions.dart';
import '../../theme/colors.dart';
import '../dialogs.dart';
import '../library/format.dart';
import 'panels.dart' show paintPageFitted;

// ⋯ → Version history: earlier versions of the page shown, kept on this
// tablet (lib/sync/versions.dart), each with a preview, and Restore. Not in
// the designs (docs/SPEC.md, Phase 10); built plainly, in the dialogs' style.

Future<void> showVersionHistory(BuildContext context, Pane pane) =>
    showEndlessDialog<void>(context, builder: (_) => _VersionHistory(pane: pane));

/// "Before changes from Kim's tablet", "While writing", …
String versionReason(PageVersion v) => switch (v.reason) {
      VersionReason.edit => 'While writing',
      VersionReason.sync => v.device == null ? 'Before changes from another device' : 'Before changes from ${v.device}',
      VersionReason.restore => 'Before an earlier version was restored',
    };

class _VersionHistory extends ConsumerStatefulWidget {
  const _VersionHistory({required this.pane});

  final Pane pane;

  @override
  ConsumerState<_VersionHistory> createState() => _VersionHistoryState();
}

class _VersionHistoryState extends ConsumerState<_VersionHistory> {
  List<PageVersion>? _versions;
  PageVersion? _picked;
  PageRuntime? _preview;
  bool _unreadable = false;
  late final String _pageId;
  late final int _pageNumber;

  NotebookNotifier get _nb => ref.read(notebookProvider(widget.pane.notebookId).notifier);

  @override
  void initState() {
    super.initState();
    final nb = ref.read(notebookProvider(widget.pane.notebookId));
    final i = widget.pane.page.clamp(0, nb.pages.length - 1);
    _pageId = nb.pages[i].id;
    _pageNumber = i + 1;
    _nb.versionsOf(_pageId).then((v) {
      if (!mounted) return;
      setState(() => _versions = v);
      if (v.isNotEmpty) _pick(v.first);
    });
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _pick(PageVersion v) async {
    setState(() {
      _picked = v;
      _unreadable = false;
    });
    final page = await _nb.loadVersion(_pageId, v);
    if (!mounted || _picked != v) return;
    setState(() {
      _preview?.dispose();
      _preview = page == null ? null : PageRuntime(page);
      _unreadable = page == null;
    });
  }

  Future<void> _restore() async {
    final page = _preview?.page;
    if (page == null) return;
    final ok = await _nb.restoreVersion(_pageId, page);
    if (!mounted) return;
    Navigator.of(context).pop();
    if (ok) {
      widget.pane.toast('Restored the version from ${_when(_picked!)}', undoPageId: _pageId);
    } else {
      widget.pane.toast('This page can’t be changed now');
    }
  }

  String _when(PageVersion v) {
    final now = ref.read(clockProvider)().toUtc();
    return '${dayWhen(v.at, now)}, ${clockText(v.at.toLocal(), seconds: false)}';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final versions = _versions;
    final sealed = ref.read(notebookProvider(widget.pane.notebookId)).isSealed(_pageId);
    return DialogFrame(
      title: 'Version history',
      width: 860,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
        Text(
          'Page $_pageNumber · earlier versions kept on this tablet: one while you write (at most every 10 minutes) '
          'and one before another device’s changes come in.',
          style: TextStyle(fontSize: 14, color: c.textMuted),
        ),
        if (sealed)
          Text('Unlock the page to see its versions.', style: TextStyle(fontSize: 15, color: c.text))
        else if (versions == null)
          const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
        else if (versions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No earlier versions of this page yet.', style: TextStyle(fontSize: 15, color: c.text)),
          )
        else
          SizedBox(
            height: 400,
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 16, children: [
              SizedBox(
                width: 290,
                child: Semantics(
                  container: true,
                  label: 'Versions',
                  explicitChildNodes: true,
                  child: ListView.separated(
                    itemCount: versions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, i) {
                      final v = versions[i];
                      final on = v == _picked;
                      return Semantics(
                        button: true,
                        selected: on,
                        label: '${_when(v)}. ${versionReason(v)}',
                        excludeSemantics: true,
                        child: Material(
                          color: on ? c.accentWash : Colors.transparent,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: on ? c.accent : c.line),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => _pick(v),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, spacing: 2, children: [
                                Text(_when(v), style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                                Text(versionReason(v), style: TextStyle(fontSize: 13, color: c.textMuted)),
                              ]),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: c.bg, border: Border.all(color: c.line), borderRadius: BorderRadius.circular(12)),
                  clipBehavior: Clip.antiAlias,
                  child: _unreadable
                      ? Center(
                          child: Text('This version can’t be opened (it was sealed with an older password).',
                              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: c.textMuted)),
                        )
                      : _preview == null
                          ? const SizedBox.shrink()
                          : Semantics(
                              label: 'Preview of the version from ${_when(_picked!)}',
                              child: CustomPaint(painter: _VersionPainter(_preview!, Theme.of(context).brightness, c)),
                            ),
                ),
              ),
            ]),
          ),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [
          SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
          PrimaryButton(label: 'Restore this version', onPressed: _preview == null || sealed ? null : _restore),
        ]),
      ]),
    );
  }
}

class _VersionPainter extends CustomPainter {
  _VersionPainter(this.page, this.brightness, this.colors);

  final PageRuntime page;
  final Brightness brightness;
  final EndlessColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final content = page.contentBounds;
    if (content == null) return;
    final padded = content.inflate(math.max(content.width, content.height) * 0.06 + 12);
    paintPageFitted(canvas, (Offset.zero & size).deflate(12), padded, page, brightness, colors);
  }

  @override
  bool shouldRepaint(_VersionPainter old) => old.page != page || old.brightness != brightness;
}

/// A version's page, for tests.
@visibleForTesting
BoardPage? previewOf(State s) => s is _VersionHistoryState ? s._preview?.page : null;
