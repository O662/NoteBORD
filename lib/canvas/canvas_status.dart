/// A message at the bottom of the canvas from a pen gesture: a status while
/// the pen is down ("Hold to straighten…"), or what just happened with an
/// Undo button ("Line straightened · Undo").
class CanvasStatus {
  const CanvasStatus(this.text, {this.undoPageId});

  final String text;

  /// The page whose last step the Undo button takes back, or null for a
  /// plain status.
  final String? undoPageId;
}
