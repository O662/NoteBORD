import '../board/model.dart';
import 'speakers.dart';

/// What speech to text heard: a stretch of speech with its words' times.
class HeardSegment {
  const HeardSegment(this.t0, this.t1, this.text, this.words);

  final int t0;
  final int t1;
  final String text;

  /// (start ms, end ms, word as heard, with its leading space).
  final List<(int, int, String)> words;
}

/// Transcript lines from what was heard, without speakers yet.
List<TranscriptLine> linesHeard(Iterable<HeardSegment> heard) => [
      for (final s in heard)
        if (_clean(s.text).isNotEmpty) TranscriptLine(tMs: s.t0, endMs: s.t1, text: _clean(s.text)),
    ];

/// [lines] with who said them. A line that changes speaker partway is split
/// where it changes, at a word (so a quick "Right." after a question gets
/// its own line), when [heard] has its words.
List<TranscriptLine> withSpeakers(List<TranscriptLine> lines, SpeakerTimeline speakers, {Iterable<HeardSegment> heard = const []}) {
  if (speakers.count == 0) return lines;
  final words = {for (final s in heard) s.t0: s.words};
  final out = <TranscriptLine>[];
  for (final line in lines) {
    final ws = words[line.tMs];
    if (ws == null || ws.length < 2 || speakers.count < 2) {
      out.add(TranscriptLine(tMs: line.tMs, endMs: line.endMs, speaker: speakers.at(line.tMs, line.endMs), text: line.text, extra: line.extra));
      continue;
    }
    // Each word's speaker; a run shorter than 2 words follows its neighbours.
    final who = [for (final w in ws) speakers.at(w.$1, w.$2)];
    for (var i = 0; i < who.length; i++) {
      if (who[i] == null) who[i] = i > 0 ? who[i - 1] : null;
    }
    for (var i = who.length - 1; i >= 0; i--) {
      if (who[i] == null && i + 1 < who.length) who[i] = who[i + 1];
    }
    for (var i = 1; i < who.length - 1; i++) {
      if (who[i] != who[i - 1] && who[i] != who[i + 1] && who[i - 1] == who[i + 1]) who[i] = who[i - 1];
    }
    var from = 0;
    for (var i = 1; i <= ws.length; i++) {
      if (i < ws.length && who[i] == who[from]) continue;
      final text = _clean(ws.sublist(from, i).map((w) => w.$3).join());
      if (text.isNotEmpty) {
        out.add(TranscriptLine(
          tMs: from == 0 ? line.tMs : ws[from].$1,
          endMs: i == ws.length ? line.endMs : ws[i - 1].$2,
          speaker: who[from],
          text: text,
        ));
      }
      from = i;
    }
  }
  return out;
}

String _clean(String s) => s.replaceAll(RegExp(r'\s+'), ' ').trim();

/// "12:40" or "1:02:05", from ms.
String clockOf(int ms) {
  final s = (ms / 1000).floor().clamp(0, 1 << 31);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  final ss = sec.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
}

/// The transcript as plain text: "12:02 Professor: …", a line each.
String transcriptText(AudioItem clip, {bool times = true}) => [
      for (final l in clip.transcript)
        [
          if (times) clockOf(l.tMs),
          if (l.speaker != null) '${clip.speakerName(l.speaker)}:',
          l.text,
        ].join(' '),
    ].join('\n');

/// The language name for a code Whisper gives, in English.
String languageName(String? code) => switch (code) {
      null || '' => '',
      'en' => 'English',
      'es' => 'Spanish',
      'fr' => 'French',
      'de' => 'German',
      'it' => 'Italian',
      'pt' => 'Portuguese',
      'nl' => 'Dutch',
      'pl' => 'Polish',
      'ru' => 'Russian',
      'uk' => 'Ukrainian',
      'tr' => 'Turkish',
      'ar' => 'Arabic',
      'he' => 'Hebrew',
      'hi' => 'Hindi',
      'ja' => 'Japanese',
      'ko' => 'Korean',
      'zh' => 'Chinese',
      'vi' => 'Vietnamese',
      'id' => 'Indonesian',
      'sv' => 'Swedish',
      'da' => 'Danish',
      'no' => 'Norwegian',
      'fi' => 'Finnish',
      'el' => 'Greek',
      'cs' => 'Czech',
      'ro' => 'Romanian',
      'hu' => 'Hungarian',
      'tl' => 'Filipino',
      _ => code.toUpperCase(),
    };
