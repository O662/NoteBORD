import 'package:flutter/material.dart';

import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import 'icons.dart';

// Dialog parts shared by Templates, Password protect and the library
// (Lock.dc.html: 22 px corners, Newsreader 30 title, 48 dp fields and buttons).

/// Shows [child] as a modal over the scrim.
Future<T?> showEndlessDialog<T>(BuildContext context, {required WidgetBuilder builder, bool dismissible = true}) =>
    showDialog<T>(
      context: context,
      barrierDismissible: dismissible,
      barrierColor: context.colors.scrim,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.all(24),
        child: builder(context),
      ),
    );

/// The dialog surface: title, close button and content.
class DialogFrame extends StatelessWidget {
  const DialogFrame({
    super.key,
    required this.title,
    required this.child,
    this.width = 580,
    this.onClose,
    this.padding = const EdgeInsets.fromLTRB(28, 24, 28, 24),
  });

  final String title;
  final Widget child;
  final double width;
  final VoidCallback? onClose;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      label: title,
      explicitChildNodes: true,
      child: Container(
        width: width,
        padding: padding,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(22),
          boxShadow: c.modalShadow,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
          Row(children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 30, color: c.text, height: 1.2),
              ),
            ),
            DialogCloseButton(onPressed: onClose ?? () => Navigator.of(context).pop()),
          ]),
          child,
        ]),
      ),
    );
  }
}

class DialogCloseButton extends StatelessWidget {
  const DialogCloseButton({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: 'Close',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.button),
        onTap: onPressed,
        child: SizedBox(width: 44, height: 44, child: Center(child: EIcon(EIcons.close, color: c.textMuted))),
      ),
    );
  }
}

/// The dark filled button ("Lock page", "Use …", "Open").
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({super.key, required this.label, required this.onPressed, this.icon, this.height = 48, this.expand = false});

  final String label;
  final VoidCallback? onPressed;
  final EIconData? icon;
  final double height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final enabled = onPressed != null;
    final fg = enabled ? c.onInverse : c.onInverse.withValues(alpha: 0.6);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: enabled ? c.inverse : c.inverse.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(Radii.button),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onPressed,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: icon == null ? 22 : 20),
            child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, spacing: 8, children: [
              if (icon != null) EIcon(icon!, size: 18, color: fg),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: fg),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The outlined button ("Cancel", "Split view", "Import").
class SecondaryButton extends StatelessWidget {
  const SecondaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 48,
    this.expand = false,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final EIconData? icon;
  final double height;
  final bool expand;

  /// Surface background (the library header buttons) instead of transparent.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: filled ? c.surface : Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(color: c.lineStrong),
          borderRadius: BorderRadius.circular(Radii.button),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.button),
          onTap: onPressed,
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: icon == null ? 20 : 16),
            child: Row(mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, spacing: 8, children: [
              if (icon != null) EIcon(icon!, size: 18, color: c.text),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.text),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A labeled text field (Lock.dc.html inputs).
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.errorText,
    this.textInputAction,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final bool obscure;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final TextInputAction? textInputAction;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(Radii.button),
          borderSide: BorderSide(color: color, width: width),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 6, children: [
      Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.text)),
      TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        obscureText: obscure,
        enableSuggestions: !obscure,
        autocorrect: !obscure,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        textInputAction: textInputAction,
        cursorColor: c.accent,
        style: TextStyle(fontSize: 16, height: 1.25, color: c.text, letterSpacing: obscure ? 2 : null),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(fontSize: 16, height: 1.25, color: c.textMuted, letterSpacing: 0),
          filled: true,
          fillColor: c.surface,
          // 48 dp tall: 20 dp of text plus 14 above and below.
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          enabledBorder: border(c.lineStrong, 1),
          focusedBorder: border(c.accent, 1.5),
          errorBorder: border(c.danger, 1.5),
          focusedErrorBorder: border(c.danger, 1.5),
          errorText: errorText,
          errorStyle: TextStyle(fontSize: 13, color: c.danger),
        ),
      ),
    ]);
  }
}

/// Asks for a name (new folder, rename, save as template).
Future<String?> showNamePrompt(
  BuildContext context, {
  required String title,
  String initial = '',
  String label = 'Name',
  String action = 'Save',
  String? hint,
}) =>
    showEndlessDialog<String>(context, builder: (context) => _NamePrompt(title, initial, label, action, hint));

class _NamePrompt extends StatefulWidget {
  const _NamePrompt(this.title, this.initial, this.label, this.action, this.hint);

  final String title;
  final String initial;
  final String label;
  final String action;
  final String? hint;

  @override
  State<_NamePrompt> createState() => _NamePromptState();
}

class _NamePromptState extends State<_NamePrompt> {
  late final _name = TextEditingController(text: widget.initial)
    ..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _done() {
    final v = _name.text.trim();
    if (v.isNotEmpty) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) => DialogFrame(
        title: widget.title,
        width: 460,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
          LabeledField(
            label: widget.label,
            controller: _name,
            hint: widget.hint,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _done(),
            textInputAction: TextInputAction.done,
          ),
          Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [
            SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop()),
            PrimaryButton(label: widget.action, onPressed: _name.text.trim().isEmpty ? null : _done),
          ]),
        ]),
      );
}

/// Asks to confirm something (delete forever, empty trash).
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
}) async {
  final ok = await showEndlessDialog<bool>(
    context,
    builder: (context) => DialogFrame(
      title: title,
      width: 460,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 18, children: [
        Text(message, style: TextStyle(fontSize: 15, height: 1.45, color: context.colors.textMuted)),
        Row(mainAxisAlignment: MainAxisAlignment.end, spacing: 10, children: [
          SecondaryButton(label: 'Cancel', onPressed: () => Navigator.of(context).pop(false)),
          PrimaryButton(label: action, onPressed: () => Navigator.of(context).pop(true)),
        ]),
      ]),
    ),
  );
  return ok ?? false;
}
