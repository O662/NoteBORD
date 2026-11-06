import '../sync/cloud.dart' show CloudKind;
import '../sync/sync_state.dart' show SyncSettings;
import 'settings.dart';

/// Where a notebook is saved (Update 02): on this tablet only, or in
/// Google Drive or OneDrive as well. Stored in notebook.json as `saveTo`
/// (`device`, `google`, `onedrive`); a notebook from before has none and
/// goes to every cloud that's on, as it always did.
enum SaveLocation {
  device('This tablet only'),
  google('Google Drive'),
  onedrive('OneDrive');

  const SaveLocation(this.label);

  final String label;

  static SaveLocation? parse(Object? name) => values.where((v) => v.name == name).firstOrNull;

  /// The cloud it's saved to, or null for this tablet.
  CloudKind? get cloud => switch (this) {
        device => null,
        google => CloudKind.google,
        onedrive => CloudKind.onedrive,
      };

  static SaveLocation forCloud(CloudKind kind) => kind == CloudKind.onedrive ? onedrive : google;
}

/// Whether a notebook saved to [location] (null: one from before there was
/// a choice) goes to [cloud].
bool syncsTo(SaveLocation? location, CloudKind cloud) => location == null || location.cloud == cloud;

/// Where new notes go: Settings › Notebooks & pages › "Save new notes to",
/// or before that's picked, Google Drive or OneDrive if one is on, else
/// this tablet.
SaveLocation defaultSaveLocation(AppSettings settings, SyncSettings sync) {
  final picked = SaveLocation.parse(settings.saveNewTo);
  if (picked != null) return picked;
  if (sync.google.active) return SaveLocation.google;
  if (sync.onedrive.active) return SaveLocation.onedrive;
  return SaveLocation.device;
}
