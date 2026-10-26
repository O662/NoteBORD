# Makes test/fixtures/study/fsrs_reference.json: what the reference FSRS
# scheduler (py-fsrs 6.3.2, open-spaced-repetition) says for a few runs of
# answers, which test/study/fsrs_test.dart checks lib/study/fsrs.dart against.
#
#   python -m venv .venv && .venv/bin/pip install fsrs==6.3.2
#   .venv/bin/python tool/fsrs_reference.py > test/fixtures/study/fsrs_reference.json
import json
from datetime import datetime, timedelta, timezone

from fsrs import Scheduler, Card, Rating

s = Scheduler(enable_fuzzing=False)
start = datetime(2026, 9, 25, 10, 0, tzinfo=timezone.utc)

# Each step: the rating, and how long after the card's due date it's answered
# (minutes); None answers at the start time.
sequences = {
    'good_path': [('Good', 0), ('Good', 0), ('Good', 0), ('Good', 0), ('Hard', 60 * 24), ('Easy', 0)],
    'lapse': [('Easy', 0), ('Good', 0), ('Again', 0), ('Good', 0), ('Good', 60 * 24 * 3)],
    'learning': [('Again', 0), ('Hard', 0), ('Hard', 0), ('Good', 0), ('Again', 0), ('Again', 0), ('Good', 0)],
    'early': [('Good', 0), ('Good', 0), ('Good', -60 * 24), ('Again', -60)],
}
out = {}
for name, seq in sequences.items():
    card = Card()
    now = start
    rows = []
    for rating, late in seq:
        if card.due is not None and rows:
            now = card.due + timedelta(minutes=late)
            if now < card.last_review:
                now = card.last_review + timedelta(minutes=1)
        card, _ = s.review_card(card, Rating[rating], now)
        rows.append({
            'rating': rating,
            'at': now.isoformat(),
            'state': card.state.name,
            'step': card.step,
            's': card.stability,
            'd': card.difficulty,
            'due': card.due.isoformat(),
        })
    out[name] = rows
print(json.dumps(out, indent=1))
