import 'dart:math' as math;

import 'package:flutter/foundation.dart' show immutable;

// FSRS-6, the spaced-repetition scheduler (Study.png's Again · Hard · Good ·
// Easy). It follows py-fsrs 6 (open-spaced-repetition), with its default
// weights, learning steps of 1 and 10 minutes, a relearning step of 10
// minutes, 90% retention, and no fuzz (so the same answers always give the
// same dates).

enum Rating {
  again(1),
  hard(2),
  good(3),
  easy(4);

  const Rating(this.value);

  final int value;
}

enum CardPhase { learning, review, relearning }

/// What's known about how well one side of a card is remembered. A card
/// never studied has no state: it is new, and due now.
@immutable
class CardState {
  const CardState({
    required this.phase,
    this.step,
    required this.stability,
    required this.difficulty,
    required this.due,
    required this.lastReview,
    this.reps = 0,
    this.lapses = 0,
  });

  final CardPhase phase;

  /// Which learning or relearning step it's on (null in review).
  final int? step;

  /// Days for recall to fall to 90%.
  final double stability;

  /// 1 (easy) to 10 (hard).
  final double difficulty;
  final DateTime due;
  final DateTime lastReview;
  final int reps;

  /// Times it was forgotten after being learned.
  final int lapses;

  static CardState? fromJson(Object? json) {
    if (json is! Map) return null;
    final due = DateTime.tryParse(json['due'] as String? ?? '');
    final last = DateTime.tryParse(json['last'] as String? ?? '');
    final s = (json['s'] as num?)?.toDouble();
    final d = (json['d'] as num?)?.toDouble();
    if (due == null || last == null || s == null || d == null) return null;
    return CardState(
      phase: CardPhase.values.firstWhere((p) => p.name == json['phase'], orElse: () => CardPhase.review),
      step: (json['step'] as num?)?.toInt(),
      stability: s,
      difficulty: d,
      due: due.toUtc(),
      lastReview: last.toUtc(),
      reps: (json['reps'] as num?)?.toInt() ?? 0,
      lapses: (json['lapses'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toJson() => {
        'phase': phase.name,
        if (step != null) 'step': step,
        's': _round(stability),
        'd': _round(difficulty),
        'due': due.toUtc().toIso8601String(),
        'last': lastReview.toUtc().toIso8601String(),
        'reps': reps,
        'lapses': lapses,
      };

  static double _round(double v) => (v * 10000).roundToDouble() / 10000;
}

class Fsrs {
  const Fsrs({
    this.weights = defaultWeights,
    this.retention = 0.9,
    this.learningSteps = const [Duration(minutes: 1), Duration(minutes: 10)],
    this.relearningSteps = const [Duration(minutes: 10)],
    this.maxInterval = 36500,
  });

  /// py-fsrs 6's defaults.
  static const defaultWeights = [
    0.212, 1.2931, 2.3065, 8.2956, 6.4133, 0.8334, 3.0194, 0.001, 1.8722, 0.1666, 0.796, //
    1.4835, 0.0614, 0.2629, 1.6483, 0.6014, 1.8729, 0.5425, 0.0912, 0.0658, 0.1542,
  ];

  static const _minStability = 0.001;

  final List<double> weights;
  final double retention;
  final List<Duration> learningSteps;
  final List<Duration> relearningSteps;

  /// In days.
  final int maxInterval;

  double get _decay => -weights[20];
  double get _factor => math.pow(0.9, 1 / _decay) - 1;

  /// How likely it is to be remembered [days] after the last review.
  double retrievability(double stability, double days) =>
      math.pow(1 + _factor * math.max(0, days) / stability, _decay).toDouble();

  /// Whole days until recall falls to [retention].
  int interval(double stability) {
    final days = stability / _factor * (math.pow(retention, 1 / _decay) - 1);
    return days.round().clamp(1, maxInterval);
  }

  double _initialStability(Rating r) => math.max(weights[r.value - 1], _minStability);

  double _initialDifficulty(Rating r, {bool clamp = true}) {
    final d = weights[4] - math.exp(weights[5] * (r.value - 1)) + 1;
    return clamp ? d.clamp(1, 10).toDouble() : d;
  }

  double _nextDifficulty(double d, Rating r) {
    final delta = -weights[6] * (r.value - 3);
    final damped = d + delta * (10 - d) / 9;
    // Toward Easy's starting difficulty, unclamped (as py-fsrs does).
    final reverted = weights[7] * _initialDifficulty(Rating.easy, clamp: false) + (1 - weights[7]) * damped;
    return reverted.clamp(1, 10).toDouble();
  }

  double _shortTermStability(double s, Rating r) {
    var increase = math.exp(weights[17] * (r.value - 3 + weights[18])) * math.pow(s, -weights[19]);
    // Only Again can lower it within a day.
    if (r != Rating.again) increase = math.max(increase, 1.0);
    return s * increase;
  }

  double _recallStability(double s, double d, double r, Rating rating) {
    final hard = rating == Rating.hard ? weights[15] : 1.0;
    final easy = rating == Rating.easy ? weights[16] : 1.0;
    return s *
        (1 +
            math.exp(weights[8]) *
                (11 - d) *
                math.pow(s, -weights[9]) *
                (math.exp((1 - r) * weights[10]) - 1) *
                hard *
                easy);
  }

  double _forgetStability(double s, double d, double r) {
    final long = weights[11] *
        math.pow(d, -weights[12]) *
        (math.pow(s + 1, weights[13]) - 1) *
        math.exp((1 - r) * weights[14]);
    final short = s / math.exp(weights[17] * weights[18]);
    return math.min(long, short);
  }

  /// The card's state after answering [rating] at [now]. [card] is null for
  /// a card never studied.
  CardState review(CardState? card, Rating rating, DateTime now) {
    now = now.toUtc();
    final phase = card?.phase ?? CardPhase.learning;
    final step = card == null ? 0 : card.step;
    double s, d;
    if (card == null) {
      s = _initialStability(rating);
      d = _initialDifficulty(rating);
    } else {
      // Whole days, as py-fsrs counts them.
      final days = now.difference(card.lastReview).inDays;
      if (days < 1) {
        s = _shortTermStability(card.stability, rating);
      } else {
        final r = retrievability(card.stability, days.toDouble());
        s = rating == Rating.again
            ? _forgetStability(card.stability, card.difficulty, r)
            : _recallStability(card.stability, card.difficulty, r, rating);
      }
      d = _nextDifficulty(card.difficulty, rating);
    }
    s = math.max(s, _minStability);

    var nextPhase = phase;
    int? nextStep = step;
    Duration wait;
    var lapses = card?.lapses ?? 0;

    Duration reviewIn() => Duration(days: interval(s));

    switch (phase) {
      case CardPhase.learning || CardPhase.relearning:
        final steps = phase == CardPhase.learning ? learningSteps : relearningSteps;
        final at = step ?? 0;
        if (steps.isEmpty || (at >= steps.length && rating != Rating.again)) {
          nextPhase = CardPhase.review;
          nextStep = null;
          wait = reviewIn();
        } else {
          switch (rating) {
            case Rating.again:
              nextStep = 0;
              wait = steps[0];
            case Rating.hard:
              nextStep = at;
              if (at == 0 && steps.length == 1) {
                wait = steps[0] * 1.5;
              } else if (at == 0) {
                wait = (steps[0] + steps[1]) ~/ 2;
              } else {
                wait = steps[at];
              }
            case Rating.good:
              if (at + 1 >= steps.length) {
                nextPhase = CardPhase.review;
                nextStep = null;
                wait = reviewIn();
              } else {
                nextStep = at + 1;
                wait = steps[at + 1];
              }
            case Rating.easy:
              nextPhase = CardPhase.review;
              nextStep = null;
              wait = reviewIn();
          }
        }
      case CardPhase.review:
        if (rating == Rating.again) {
          lapses++;
          if (relearningSteps.isEmpty) {
            wait = reviewIn();
          } else {
            nextPhase = CardPhase.relearning;
            nextStep = 0;
            wait = relearningSteps[0];
          }
        } else {
          wait = reviewIn();
        }
    }

    return CardState(
      phase: nextPhase,
      step: nextStep,
      stability: s,
      difficulty: d,
      due: now.add(wait),
      lastReview: now,
      reps: (card?.reps ?? 0) + 1,
      lapses: lapses,
    );
  }
}

/// "in 1 min", "in 10 min", "in 2 days" (Study.png's rating buttons).
String waitLabel(Duration d) {
  if (d.inMinutes < 60) return 'in ${math.max(1, d.inMinutes)} min';
  if (d.inHours < 24) {
    final h = (d.inMinutes / 60).round();
    return h == 1 ? 'in 1 hour' : 'in $h hours';
  }
  final days = (d.inHours / 24).round();
  if (days < 31) return days == 1 ? 'in 1 day' : 'in $days days';
  final months = (days / 30.4).round();
  if (months < 12) return months == 1 ? 'in 1 month' : 'in $months months';
  final years = days / 365;
  return years < 1.5 ? 'in 1 year' : 'in ${years.toStringAsFixed(years < 10 ? 1 : 0)} years';
}
