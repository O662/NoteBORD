import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../recognition/models.dart';
import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../icons.dart';

/// A small note while a handwriting model downloads on first use ("Getting
/// English handwriting ready…"), then that it's ready or couldn't be had.
/// Those two stay a few seconds.
class ModelNoteView extends ConsumerStatefulWidget {
  const ModelNoteView({super.key});

  static const shown = Duration(seconds: 5);

  @override
  ConsumerState<ModelNoteView> createState() => _ModelNoteViewState();
}

class _ModelNoteViewState extends ConsumerState<ModelNoteView> {
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final note = ref.watch(inkModelsProvider);
    _timer?.cancel();
    if (note == null) return const SizedBox.shrink();
    if (note.phase != ModelPhase.downloading) {
      _timer = Timer(ModelNoteView.shown, () {
        if (mounted) ref.read(inkModelsProvider.notifier).seen(note);
      });
    }
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 340),
        padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
        decoration: BoxDecoration(
          color: c.surface,
          border: Border.all(color: c.line),
          borderRadius: BorderRadius.circular(Radii.button),
          boxShadow: c.pillShadow,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, spacing: 10, children: [
          switch (note.phase) {
            ModelPhase.downloading =>
              SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.accent)),
            ModelPhase.ready => EIcon(EIcons.searchCheck, size: 16, color: c.green),
            ModelPhase.failed => EIcon(EIcons.close, size: 14, color: c.clay),
          },
          Flexible(child: Text(note.text, style: TextStyle(fontSize: 13, height: 1.3, color: c.text))),
        ]),
      ),
    );
  }
}
