import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../templates/templates.dart' show TemplateTarget;
import '../templates/templates_dialog.dart';

/// New notebook (Start's Notebook tile and the Library's New notebook).
Future<void> newNotebook(BuildContext context, WidgetRef ref, {List<String> folder = const []}) =>
    showTemplatesDialog(context, target: TemplateTarget.newNotebook, initial: 'dots', folder: folder);
