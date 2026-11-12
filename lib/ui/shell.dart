import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/settings.dart';
import '../theme/colors.dart';
import '../theme/tokens.g.dart';
import 'common.dart';
import 'icons.dart';
import 'library/sidebar.dart';
import 'logo.dart';
import 'routes.dart';
import 'settings/settings_screen.dart' show openSyncSettings;
import 'settings/sync_widgets.dart';

// Layouts switch with the window's width, not the device (UPDATE_04 §8):
// narrower than [narrowWidth] is the portrait layout, whether that's a
// tablet held upright, a phone, or a narrow window on Windows.

/// Below this width (dp) screens use their portrait layout.
const narrowWidth = 900.0;

extension LayoutWidth on BuildContext {
  /// The window is narrower than [narrowWidth] (portrait).
  bool get narrow => MediaQuery.sizeOf(this).width < narrowWidth;
}

/// The library screens' frame: the sidebar beside the screen, folded to its
/// rail when the setting says so (Update 04 §9); in portrait, a 72 dp top
/// bar whose ☰ opens the sidebar as a drawer (§8).
///
/// Takes a [Row]'s children: the [AppSidebar] first, then the screen.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.children});

  final List<Widget> children;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  bool _drawer = false;

  @override
  Widget build(BuildContext context) {
    final sidebar = widget.children.first as AppSidebar;
    final rest = widget.children.skip(1).toList();
    if (!context.narrow) {
      _drawer = false;
      final collapsed = ref.watch(settingsProvider.select((s) => s.sidebarCollapsed));
      return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        sidebar.withMode(collapsed ? SidebarMode.rail : SidebarMode.full),
        ...rest,
      ]);
    }
    final c = context.colors;
    return Stack(children: [
      Positioned.fill(
        child: ExcludeSemantics(
          excluding: _drawer,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            PortraitTopBar(onMenu: () => setState(() => _drawer = true), drawerOpen: _drawer),
            Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: rest)),
          ]),
        ),
      ),
      if (_drawer) ...[
        Positioned.fill(
          child: Semantics(
            button: true,
            label: 'Close menu',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _drawer = false),
              child: ColoredBox(color: c.scrim),
            ),
          ),
        ),
        Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: -1, end: 0),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            builder: (context, t, child) => FractionalTranslation(translation: Offset(t, 0), child: child),
            child: DecoratedBox(
              decoration: BoxDecoration(
                boxShadow: [BoxShadow(color: c.shadow, blurRadius: 48, offset: const Offset(24, 0), spreadRadius: -24)],
              ),
              child: sidebar.withMode(SidebarMode.drawer),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// Portrait's top bar (StartPortrait.dc.html `header`): ☰, the logo, then
/// search, sync status and Settings.
class PortraitTopBar extends StatelessWidget {
  const PortraitTopBar({super.key, required this.onMenu, this.drawerOpen = false});

  final VoidCallback onMenu;
  final bool drawerOpen;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(color: c.bg, border: Border(bottom: BorderSide(color: c.lineSoft))),
      child: Row(spacing: 8, children: [
        ChromeButton(
          label: 'Open menu',
          icon: EIcons.menu,
          iconSize: 22,
          width: 48,
          height: 48,
          expanded: drawerOpen,
          onPressed: onMenu,
        ),
        const EndlessMark(width: 40),
        Text(
          'Endless',
          style: TextStyle(fontFamily: FontFamilies.serif, fontSize: 24, fontWeight: FontWeight.w500, color: c.text),
        ),
        const Spacer(),
        ChromeButton(
          label: 'Search notes and handwriting',
          icon: EIcons.search,
          iconSize: 22,
          width: 48,
          height: 48,
          onPressed: () => context.push(Routes.search()),
        ),
        SyncStatusIcon(boxed: false, onTap: () => openSyncSettings(context)),
        ChromeButton(
          label: 'Settings',
          icon: EIcons.gear,
          iconSize: 22,
          width: 48,
          height: 48,
          onPressed: () => context.push(Routes.settings()),
        ),
      ]),
    );
  }
}
