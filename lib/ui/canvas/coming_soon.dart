import 'package:flutter/material.dart';

import '../../theme/colors.dart';
import '../../theme/tokens.g.dart';
import '../dialogs.dart';

/// A card for something in the Insert menu that isn't built yet: what it
/// is, that it's coming, and what it will do.
Future<void> showComingSoonCard(
  BuildContext context, {
  required String title,
  required String message,
  required Widget icon,
}) =>
    showEndlessDialog<void>(
      context,
      builder: (context) => _ComingSoonCard(title: title, message: message, icon: icon),
    );

class _ComingSoonCard extends StatelessWidget {
  const _ComingSoonCard({required this.title, required this.message, required this.icon});

  final String title;
  final String message;
  final Widget icon;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: '$title: coming soon',
      explicitChildNodes: true,
      child: Container(
        width: 400,
        padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: c.modalShadow,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            icon,
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: c.accentTint, borderRadius: BorderRadius.circular(Radii.chip)),
              child: Text(
                'Coming soon',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.accentDeep),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Text(title, style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 28, height: 1.15, color: c.text)),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(fontSize: 15, height: 1.45, color: c.textMuted)),
          const SizedBox(height: 22),
          Align(
            alignment: Alignment.centerRight,
            child: PrimaryButton(label: 'Got it', onPressed: () => Navigator.of(context).pop()),
          ),
        ]),
      ),
    );
  }
}
