import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../board/model.dart' show ArrowStyle, Paper;
import '../../calendar/calendar_model.dart' show CalendarInfo, CalendarKind, FeedFrom;
import '../../calendar/calendar_state.dart';
import '../../canvas/gestures.dart' show ScribbleLevel;
import '../../library/library.dart';
import '../../recognition/handwriting_index.dart';
import '../../recognition/models.dart';
import '../../recognition/recognizer.dart';
import '../../spelling/my_handwriting.dart';
import '../../state/save_location.dart';
import '../../state/settings.dart';
import '../../sync/cloud.dart';
import '../../sync/sync_state.dart';
import '../../theme/colors.dart';
import '../../theme/palettes.dart';
import '../common.dart' show showComingSoon;
import '../dialogs.dart';
import '../icons.dart';
import '../canvas/shortcuts.dart';
import '../library/format.dart' show folderLabel;
import '../library/new_notebook_dialog.dart' show NotebookChoices, NewNotebookSettings;
import '../spell/teach_handwriting.dart';
import 'settings_rows.dart';

// The Settings screen's sections (Settings.dc.html `D`), as data: each row
// says what it shows and which setting it reads and changes. Rows of
// settings that don't do anything yet are saved all the same (see
// docs/PROGRESS.md, Update 02b).

enum SettingsSection {
  general('General', 'How Endless opens, looks and feels day to day.'),
  account('Account', 'Who you are signed in as, and which services Endless can use.'),
  pen('Pen & S Pen', 'How the pen writes and what your fingers do.'),
  handwriting('Handwriting & search', 'Endless reads your handwriting on this tablet, so search and spell check work offline.'),
  notes('Notebooks & pages', 'Defaults for new notes and what happens to deleted pages.'),
  sync('Sync & backup', ''),
  themes('Themes & dark mode', 'Changes apply everywhere: library, pages, widgets and menus.'),
  notify('Notifications', 'Choose what Endless may remind you about.'),
  calendar('Calendar',
      'Endless shows your Google and Outlook events. Two-way sync, where changes in Endless go back to your calendar, is coming later.'),
  storage('Storage', 'What Endless keeps on this tablet.'),
  privacy('Privacy & security', 'Your notes stay on this tablet and in your own cloud. Endless has no server of its own that stores them.'),
  about('About', 'Endless · a notebook that never runs out of paper.');

  const SettingsSection(this.label, this.intro);

  final String label;
  final String intro;

  /// The heading on the page (Notifications is "Notifications & reminders").
  String get title => this == notify ? 'Notifications & reminders' : label;

  static SettingsSection parse(String? s) => values.where((v) => v.name == s).firstOrNull ?? general;

  /// Sync & backup and Themes & dark mode have screens of their own (with
  /// a chevron in the menu).
  bool get ownScreen => this == sync || this == themes;

  EIconData get icon => switch (this) {
        general => EIcons.sliders,
        account => EIcons.person,
        pen => EIcons.pencil,
        handwriting => EIcons.spellPlain,
        notes => EIcons.notebook,
        sync => EIcons.cloud,
        themes => EIcons.palette,
        notify => EIcons.bellThin,
        calendar => EIcons.calendar,
        storage => EIcons.storage,
        privacy => EIcons.lockRow,
        about => EIcons.info,
      };
}

/// One row of a section.
sealed class SettingDef {
  const SettingDef(this.label, this.desc, {this.shown});

  final String label;
  final String desc;

  /// Whether the row shows now (null: always).
  final bool Function(WidgetRef ref)? shown;

  /// The text search matches (label and description).
  String get searchText => '$label $desc'.toLowerCase();
}

class ToggleDef extends SettingDef {
  const ToggleDef(super.label, super.desc, {required this.get, required this.set});

  final bool Function(WidgetRef ref) get;
  final void Function(WidgetRef ref, bool on) set;
}

class ChoiceDef extends SettingDef {
  const ChoiceDef(super.label, super.desc, {required this.options, required this.get, required this.set});

  final List<String> options;
  final int Function(WidgetRef ref) get;
  final void Function(WidgetRef ref, int i) set;
}

class ValueDef extends SettingDef {
  const ValueDef(super.label, super.desc, {required this.value, this.onTap});

  final String Function(WidgetRef ref) value;
  final void Function(BuildContext context, WidgetRef ref)? onTap;
}

class ButtonDef extends SettingDef {
  const ButtonDef(super.label, super.desc, {required this.button, required this.onTap, this.kind = SettingsButtonKind.plain, this.descOf, super.shown});

  final String Function(WidgetRef ref) button;
  final void Function(BuildContext context, WidgetRef ref) onTap;
  final SettingsButtonKind kind;

  /// A description that changes (Connected · …), instead of [desc].
  final String Function(WidgetRef ref)? descOf;
}

class SettingsGroup {
  const SettingsGroup(this.title, this.rows);

  final String title;
  final List<SettingDef> rows;
}

// Helpers for rows of AppSettings.prefs.

void _set(WidgetRef ref, AppSettings Function(AppSettings s) change) => ref.read(settingsProvider.notifier).apply(change);

ToggleDef _flag(String key, String label, [String desc = '']) => ToggleDef(
      label,
      desc,
      get: (ref) => ref.watch(settingsProvider.select((s) => s.pref<bool>(key))),
      set: (ref, on) => _set(ref, (s) => s.withPref(key, on)),
    );

ChoiceDef _choice(String key, String label, List<String> options, [String desc = '']) => ChoiceDef(
      label,
      desc,
      options: options,
      get: (ref) => ref.watch(settingsProvider.select((s) => s.pref<int>(key))).clamp(0, options.length - 1),
      set: (ref, i) => _set(ref, (s) => s.withPref(key, i)),
    );

ToggleDef _setting(String label, String desc, bool Function(AppSettings s) get, AppSettings Function(AppSettings s, bool on) set) =>
    ToggleDef(label, desc, get: (ref) => ref.watch(settingsProvider.select(get)), set: (ref, on) => _set(ref, (s) => set(s, on)));

void _soon(BuildContext context, WidgetRef ref, String what) => showComingSoon(context, what);

String _cloudStatus(WidgetRef ref, CloudKind kind, String what) {
  final c = ref.watch(syncProvider.select((s) => s.settings.of(kind)));
  if (!c.connected) return 'Not connected · $what';
  return 'Connected · ${c.account!.email}${c.on ? '' : ' · turned off'}';
}

const _papers = [Paper.dots, Paper.lines, Paper.grid, Paper.blank];

/// The rows of [section] (Sync & backup and Themes & dark mode are panels;
/// their rows here are what search finds in them).
List<SettingsGroup> settingsGroups(SettingsSection section) => switch (section) {
      SettingsSection.general => [
          SettingsGroup('When I open Endless', [
            _choice('openTo', 'Open to', ['Start page', 'Last note I was in']),
            ValueDef('Language', 'Menus and the dictionary', value: (_) => 'English (US)'),
            _choice('dateFormat', 'Date format', ['Sep 25', '25 Sep', '9/25']),
            _choice('weekStart', 'Week starts on', ['Sunday', 'Monday']),
          ]),
          SettingsGroup('Feel', [
            _flag('haptics', 'Haptic feedback', 'A light tap when a shape snaps or a tool changes'),
            _flag('sounds', 'Sounds'),
            _flag('leftHanded', 'Left-handed mode', 'Moves the tool menu and page bar to the right side'),
          ]),
        ],
      SettingsSection.account => [
          SettingsGroup('You', [
            ButtonDef('Your name', 'For the Start page greeting',
                descOf: (ref) => ref.watch(settingsProvider.select((s) => s.userName)) ?? 'For the Start page greeting',
                button: (_) => 'Edit profile',
                onTap: _editName),
          ]),
          SettingsGroup('Signed in with', [
            ButtonDef('Google', '',
                descOf: (ref) => _cloudStatus(ref, CloudKind.google, 'Drive'),
                button: (ref) => ref.watch(syncProvider.select((s) => s.settings.google.connected)) ? 'Manage' : 'Connect',
                onTap: (context, ref) => openSettings(context, SettingsSection.sync)),
            ButtonDef('Microsoft', '',
                descOf: (ref) => _cloudStatus(ref, CloudKind.onedrive, 'OneDrive'),
                button: (ref) => ref.watch(syncProvider.select((s) => s.settings.onedrive.connected)) ? 'Manage' : 'Connect',
                kind: SettingsButtonKind.primary,
                onTap: (context, ref) => openSettings(context, SettingsSection.sync)),
          ]),
          SettingsGroup('This tablet', [
            ButtonDef('Sign out of this tablet', 'Your notes stay on this tablet and in your cloud',
                button: (_) => 'Sign out', kind: SettingsButtonKind.danger, onTap: _signOut),
          ]),
        ],
      SettingsSection.pen => [
          SettingsGroup('Writing', [
            _setting('Pressure changes thickness', '', (s) => s.pressure, (s, on) => s.copyWith(pressure: on)),
            _setting('Fingers can draw', 'Off: only the S Pen draws; fingers pan and zoom', (s) => s.fingerDraws,
                (s, on) => s.copyWith(fingerDraws: on)),
            _choice('spenButton', 'S Pen button', ['Erase', 'Select', 'Laser'], 'Hold it while writing'),
            _flag('hoverMenus', 'Hover menus', 'Hover the pen over the left menu to open it (Air view)'),
            ButtonDef('Toolbar shortcuts', 'Up to 6 tools on the left toolbar, one tap away',
                descOf: (ref) {
                  final names = [
                    for (final id in ref.watch(settingsProvider.select((s) => s.shortcuts))) ?shortcutById(id)?.label,
                  ];
                  return names.isEmpty ? 'None yet. Up to 6 tools on the left toolbar' : names.join(' · ');
                },
                button: (_) => 'Edit',
                onTap: (context, ref) => showShortcutsDialog(context)),
          ]),
          SettingsGroup('Gestures', [
            _setting('Hold to straighten lines and shapes', '', (s) => s.snap, (s, on) => s.copyWith(snap: on)),
            _setting('Flick back to make an arrow', '', (s) => s.arrows, (s, on) => s.copyWith(arrows: on)),
            ChoiceDef('Arrowheads', 'How flicked arrows end',
                options: const ['Open', 'Filled', 'Like my ink'],
                get: (ref) => ref.watch(settingsProvider.select((s) => s.arrowStyle.index)),
                set: (ref, i) => _set(ref, (s) => s.copyWith(arrowStyle: ArrowStyle.values[i]))),
            _setting('Scribble to erase', '', (s) => s.scribble, (s, on) => s.copyWith(scribble: on)),
            ChoiceDef('How much scribbling counts', '',
                options: const ['Light', 'Normal', 'Firm'],
                get: (ref) => ref.watch(settingsProvider.select((s) => s.scribbleLevel.index)),
                set: (ref, i) => _set(ref, (s) => s.copyWith(scribbleLevel: ScribbleLevel.values[i]))),
          ]),
          SettingsGroup('Menus', [
            _setting('Show the extra colors tray', 'Up to 10 colors under the tool bar', (s) => s.trayOpen,
                (s, on) => s.copyWith(trayOpen: on)),
            _setting('Swipe up to tuck menus away', 'Pull down on the tool bar to bring them back', (s) => s.swipeTuck,
                (s, on) => s.copyWith(swipeTuck: on)),
            _choice('penAgain', 'Double-tap the pen tool for', ['Pen settings', 'Eraser']),
          ]),
        ],
      SettingsSection.handwriting => [
          SettingsGroup('Reading handwriting', [
            ValueDef('Languages', 'Downloaded for offline use',
                value: (ref) => inkLanguage(handwritingLanguage(ref.watch(settingsProvider))).name, onTap: _pickLanguage),
            _flag('searchable', 'Make handwriting searchable'),
            _choice('convertMode', 'Convert to text', ['Replace ink', 'Keep ink too', 'Ask each time'], 'What happens to the ink'),
          ]),
          SettingsGroup('Spelling & math', [
            _flag('spellLive', 'Underline spelling mistakes as I write', 'Off: only when you open Spell check'),
            ValueDef('Personal dictionary', 'Words you added', value: (ref) {
              final n = ref.watch(settingsProvider.select((s) => s.myWords.length));
              return n == 1 ? '1 word' : '$n words';
            }),
            ButtonDef('My handwriting', 'Spell check fixes words in your own letters. Kept on this tablet only',
                button: (ref) => ref.watch(myHandwritingProvider) == null ? 'Write it' : 'Write it again',
                onTap: (context, ref) => showTeachHandwriting(context)),
            ButtonDef('Forget my handwriting', 'Spell check types its fixes instead',
                shown: (ref) => ref.watch(myHandwritingProvider) != null,
                button: (_) => 'Forget it',
                onTap: (context, ref) => ref.read(myHandwritingProvider.notifier).forget()),
            ValueDef('Math reading', 'Built-in model · personal use only for now', value: (_) => 'On this tablet'),
          ]),
        ],
      SettingsSection.notes => [
          SettingsGroup('New notes', [
            _choice('newNoteAsk', 'When I create a new note', ['Ask for name and location', 'Use my defaults']),
            ValueDef('Default folder', '', value: (ref) {
              final f = ref.watch(settingsProvider.select((s) => s.defaultFolder));
              return f.isEmpty ? 'No folder' : folderLabel(f);
            }, onTap: _pickFolder),
            ChoiceDef('Save new notes to', '',
                options: [for (final l in SaveLocation.values) l == SaveLocation.device ? 'This tablet' : l.label],
                get: (ref) => defaultSaveLocation(ref.watch(settingsProvider), ref.watch(syncProvider.select((s) => s.settings))).index,
                set: (ref, i) => _set(ref, (s) => s.withPref('saveNewTo', SaveLocation.values[i].name))),
            ChoiceDef('Default paper', '',
                options: const ['Dots', 'Lines', 'Grid', 'Blank'],
                get: (ref) => _papers.indexOf(ref.watch(settingsProvider.select((s) => s.defaultPaper))),
                set: (ref, i) => _set(ref, (s) => s.withPref('defaultPaper', _papers[i].name))),
          ]),
          // Update 04: "Use these every time and stop asking" in New notebook.
          SettingsGroup('New notebooks', [
            ChoiceDef('When I make a notebook', 'Its name, folder, save place and backup',
                options: const ['Ask each time', 'Use my choices'],
                get: (ref) => ref.watch(settingsProvider.select((s) => s.notebookDefaults)) == null ? 0 : 1,
                set: (ref, i) => _set(
                    ref,
                    (s) => s.withPref(
                        'newNotebookDefaults',
                        i == 0
                            ? null
                            : (s.notebookDefaults ??
                                    NotebookChoices(
                                      folder: s.defaultFolder,
                                      backup: defaultSaveLocation(s, ref.read(syncProvider).settings) != SaveLocation.device,
                                    ))
                                .toJson()))),
            ValueDef('My choices', 'What new notebooks get without asking',
                value: (ref) {
                  final d = ref.watch(settingsProvider.select((s) => s.notebookDefaults));
                  if (d == null) return 'Asks each time';
                  final place = d.place == SaveLocation.device
                      ? (d.backup ? 'This tablet, backed up' : 'This tablet, no backup')
                      : d.place.label;
                  return [if (d.folder.isNotEmpty) folderLabel(d.folder), place].join(' · ');
                }),
          ]),
          SettingsGroup('Pages', [
            _flag('pageNumbers', 'Show page numbers'),
            _choice('pageTrash', 'Keep deleted pages in Trash', ['7 days', '30 days', 'Until I empty it']),
            _choice('versionDays', 'Keep versions for', ['7 days', '30 days', '90 days'],
                'Versions you name are kept until you delete them'),
          ]),
        ],
      SettingsSection.sync => [
          SettingsGroup('Cloud storage', [
            ButtonDef('Google Drive', '', descOf: (ref) => _cloudStatus(ref, CloudKind.google, 'Drive'), button: (_) => 'Open',
                onTap: (context, ref) => openSettings(context, SettingsSection.sync)),
            ButtonDef('OneDrive', '', descOf: (ref) => _cloudStatus(ref, CloudKind.onedrive, 'OneDrive'), button: (_) => 'Open',
                onTap: (context, ref) => openSettings(context, SettingsSection.sync)),
          ]),
          SettingsGroup('What gets synced', [
            ToggleDef('Only sync on Wi-Fi', 'Not on mobile data',
                get: (ref) => ref.watch(syncProvider.select((s) => s.settings.wifiOnly)),
                set: (ref, on) => ref.read(syncProvider.notifier).setOptions(wifiOnly: on)),
            ToggleDef('Also save a PDF copy', 'Of every notebook, next to its board file',
                get: (ref) => ref.watch(syncProvider.select((s) => s.settings.pdfCopy)),
                set: (ref, on) => ref.read(syncProvider.notifier).setOptions(pdfCopy: on)),
          ]),
        ],
      SettingsSection.themes => [
          SettingsGroup('Mode', [
            ChoiceDef('Dark mode', 'Light, dark or match the tablet',
                options: const ['Light', 'Dark', 'Match tablet'],
                get: (ref) => [ThemeMode.light, ThemeMode.dark, ThemeMode.system].indexOf(ref.watch(settingsProvider.select((s) => s.themeMode))),
                set: (ref, i) => _set(ref, (s) => s.copyWith(themeMode: [ThemeMode.light, ThemeMode.dark, ThemeMode.system][i]))),
            ValueDef('Theme', 'Paper, Midnight, Sage, Blush, Graphite, High contrast, Harbor',
                value: (ref) => themeNames[ref.watch(settingsProvider.select((s) => s.theme))] ?? 'Paper',
                onTap: (context, ref) => openSettings(context, SettingsSection.themes)),
            ValueDef('Accent color', '', value: (ref) {
              final a = ref.watch(settingsProvider.select((s) => s.accent));
              return accentNames[a] ?? 'Theme default';
            }, onTap: (context, ref) => openSettings(context, SettingsSection.themes)),
            _flag('keepPagesLight', 'Keep pages light in dark mode', 'Menus go dark, the paper stays like real paper'),
          ]),
        ],
      SettingsSection.notify => [
          SettingsGroup('Reminders', [
            _flag('reminders', 'Need to remember reminders'),
            ValueDef('Flashcards due', 'A daily nudge when cards are due', value: (_) => 'Daily · 6:00 PM'),
            _choice('calendarAlerts', 'Calendar events', ['Off', '10 min before', '30 min before']),
          ]),
          SettingsGroup('Quiet', [_flag('quietHours', 'Quiet hours', 'No reminders 10 PM – 7 AM')]),
        ],
      SettingsSection.calendar => [
          const SettingsGroup('Connected calendars', []),
          SettingsGroup('Show', [
            _flag('declinedEvents', 'Declined events'),
            ToggleDef('Note deadlines', 'Dates from Need to remember and planner to-dos',
                get: (ref) => ref.watch(calendarProvider.select((d) => d.calendars.where((c) => c.id == CalendarInfo.deadlinesId).firstOrNull?.shown ?? true)),
                set: (ref, on) => ref.read(calendarProvider.notifier).toggle(CalendarInfo.deadlinesId)),
          ]),
        ],
      SettingsSection.storage => [
          SettingsGroup('Offline downloads', [
            ValueDef('Handwriting model', 'For search and Convert to text', value: (ref) => inkLanguage(handwritingLanguage(ref.watch(settingsProvider))).name),
            ValueDef('Math model', 'Reads handwritten math', value: (_) => 'Built in'),
            ValueDef('Dictionary & thesaurus', 'Definitions and similar words', value: (_) => 'Built in'),
          ]),
          SettingsGroup('Videos & cache', [
            _choice('bigVideos', 'Large videos', ['Keep on this tablet', 'Move to my cloud']),
            ButtonDef('Clear cache', 'Thumbnails and previews are rebuilt when needed',
                button: (_) => 'Clear', onTap: (context, ref) => _soon(context, ref, 'Clearing the cache')),
          ]),
        ],
      SettingsSection.privacy => [
          SettingsGroup('Locks', [
            _flag('appLock', 'Lock the app', 'Ask for fingerprint or face when Endless opens'),
            _choice('lockAfter', 'Lock again after', ['Right away', '1 min', '5 min']),
            ValueDef('Locked pages', 'Encrypted on this tablet', value: (ref) {
              final lib = ref.watch(libraryProvider);
              final pages = lib.active.fold<int>(0, (n, e) => n + e.lockedPages);
              final books = lib.active.where((e) => e.locked).length;
              return '${pages == 1 ? '1 page' : '$pages pages'} · ${books == 1 ? '1 notebook' : '$books notebooks'}';
            }),
          ]),
          SettingsGroup('Your data', [
            _flag('usageData', 'Share anonymous usage data', 'Off: Endless sends nothing about you or your notes'),
            ButtonDef('Export all my notes', 'Every notebook as board files',
                button: (_) => 'Export', onTap: (context, ref) => _soon(context, ref, 'Exporting every notebook at once')),
            ButtonDef('Delete all data on this tablet', 'Your cloud copies are not touched',
                button: (_) => 'Delete…', kind: SettingsButtonKind.danger, onTap: (context, ref) => _soon(context, ref, 'Deleting all data')),
          ]),
        ],
      SettingsSection.about => [
          SettingsGroup('App', [
            ValueDef('Version', '', value: (_) => appVersion),
            ValueDef('What’s new', '', value: (_) => '', onTap: (context, ref) => _soon(context, ref, 'What’s new')),
            ValueDef('Help & tips', '', value: (_) => '', onTap: (context, ref) => _soon(context, ref, 'Help & tips')),
            ValueDef('Open-source licenses', 'Fonts, models and packages Endless uses',
                value: (_) => '', onTap: (context, ref) => showLicensePage(context: context, applicationName: 'Endless')),
            ButtonDef('Send feedback', '', button: (_) => 'Write to us', onTap: (context, ref) => _soon(context, ref, 'Feedback')),
          ]),
        ],
    };

/// The app's version (pubspec.yaml).
const appVersion = '0.1.0 · build 1';

/// The connected calendars as switches (Settings › Calendar).
List<SettingDef> calendarRows(WidgetRef ref) {
  final cals = ref.watch(calendarProvider.select((d) => d.calendars));
  return [
    for (final cal in cals)
      if (cal.id != CalendarInfo.deadlinesId)
        ToggleDef(
          cal.name.isEmpty ? 'Calendar' : cal.name,
          switch ((cal.kind, cal.from)) {
            (CalendarKind.local, _) => 'On this tablet',
            (_, FeedFrom.google) => 'Google · read-only',
            (_, FeedFrom.outlook) => 'Outlook · read-only',
            _ => 'Calendar link · read-only',
          },
          get: (ref) => ref.watch(calendarProvider.select((d) => d.calendars.where((c) => c.id == cal.id).firstOrNull?.shown ?? false)),
          set: (ref, on) => ref.read(calendarProvider.notifier).toggle(cal.id),
        ),
  ];
}

/// Opens Settings at [section].
void openSettings(BuildContext context, SettingsSection section) => SettingsNav.of(context)?.call(section);

/// The Settings screen gives its rows a way to switch section.
class SettingsNav extends InheritedWidget {
  const SettingsNav({super.key, required this.go, required super.child});

  final ValueChanged<SettingsSection> go;

  static ValueChanged<SettingsSection>? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SettingsNav>()?.go;

  @override
  bool updateShouldNotify(SettingsNav old) => old.go != go;
}

Future<void> _editName(BuildContext context, WidgetRef ref) async {
  final name = await showNamePrompt(context, title: 'Your name', initial: ref.read(settingsProvider).userName ?? '', label: 'Name');
  if (name == null) return;
  _set(ref, (s) => s.copyWith(userName: () => name.trim().isEmpty ? null : name.trim()));
}

Future<void> _signOut(BuildContext context, WidgetRef ref) async {
  final ok = await showConfirm(
    context,
    title: 'Sign out of this tablet?',
    message: 'Endless stops syncing with Google Drive and OneDrive here. Your notes stay on this tablet and in your cloud.',
    action: 'Sign out',
  );
  if (!ok) return;
  final sync = ref.read(syncProvider.notifier);
  for (final kind in [CloudKind.google, CloudKind.onedrive]) {
    if (ref.read(syncProvider).settings.of(kind).connected) await sync.disconnect(kind);
  }
}

Future<void> _pickLanguage(BuildContext context, WidgetRef ref) async {
  final current = handwritingLanguage(ref.read(settingsProvider));
  final tag = await showEndlessDialog<String>(
    context,
    builder: (context) => _PickList(
      title: 'Handwriting language',
      note: 'For search and Convert to text. Read on this tablet, offline.',
      options: [for (final l in inkLanguages) (l.tag, l.name)],
      selected: current,
    ),
  );
  if (tag == null || tag == current) return;
  _set(ref, (s) => s.copyWith(handwritingLanguage: () => tag));
  ref.read(inkModelsProvider.notifier).ensure(tag).then((_) => ref.read(handwritingIndexProvider).catchUp());
}

Future<void> _pickFolder(BuildContext context, WidgetRef ref) async {
  final folders = ref.read(libraryProvider).folders;
  final current = folderKey(ref.read(settingsProvider).defaultFolder);
  final key = await showEndlessDialog<String>(
    context,
    builder: (context) => _PickList(
      title: 'Default folder',
      note: 'New notes go here.',
      options: [('', 'No folder'), for (final f in folders) (f.key, folderLabel(f.path))],
      selected: current,
    ),
  );
  if (key == null) return;
  final path = key.isEmpty ? <String>[] : folders.firstWhere((f) => f.key == key).path;
  _set(ref, (s) => s.withPref('defaultFolder', path));
}

/// A dialog of choices, the chosen one ticked.
class _PickList extends StatelessWidget {
  const _PickList({required this.title, required this.note, required this.options, required this.selected});

  final String title;
  final String note;
  final List<(String, String)> options;
  final String selected;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DialogFrame(
      title: title,
      width: 480,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 8, children: [
        Text(note, style: TextStyle(fontSize: 14, color: c.textMuted)),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: ListView(shrinkWrap: true, children: [
            for (final (id, name) in options)
              Semantics(
                button: true,
                selected: id == selected,
                label: name,
                excludeSemantics: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.of(context).pop(id),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(color: id == selected ? c.accentWash : null, borderRadius: BorderRadius.circular(10)),
                    child: Row(children: [
                      Expanded(child: Text(name, style: TextStyle(fontSize: 15, color: c.text))),
                      if (id == selected) EIcon(EIcons.check, size: 18, color: c.accent),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

/// A row of [def], built.
class SettingRowView extends ConsumerWidget {
  const SettingRowView(this.def, {super.key});

  final SettingDef def;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (def) {
        final ToggleDef d => SettingsRowView(
            label: d.label,
            desc: d.desc,
            trailing: SettingsSwitch(label: d.label, value: d.get(ref), onChanged: (v) => d.set(ref, v)),
          ),
        final ChoiceDef d => SettingsRowView(
            label: d.label,
            desc: d.desc,
            trailing: SettingsChoice(label: d.label, options: d.options, selected: d.get(ref), onChanged: (i) => d.set(ref, i)),
          ),
        final ValueDef d => SettingsRowView(
            label: d.label,
            desc: d.desc,
            trailing: SettingsValue(label: d.label, value: d.value(ref), onTap: d.onTap == null ? null : () => d.onTap!(context, ref)),
          ),
        final ButtonDef d => SettingsRowView(
            label: d.label,
            desc: d.descOf?.call(ref) ?? d.desc,
            danger: d.kind == SettingsButtonKind.danger,
            trailing: SettingsButton(label: d.button(ref), kind: d.kind, onPressed: () => d.onTap(context, ref)),
          ),
      };
}
