"""Builds the offline English word list and dictionary in assets/dictionary/.

Spell check and the dictionary drawer (design/screens/Spell.png) work
offline from two bundled files:

  en_words.txt.gz        every word spell check accepts, grouped by how
                         common it is (SCOWL size levels: 10 is the most
                         common, 80 the rarest we keep)
  en_dictionary.sqlite.gz  definitions, examples, synonyms and opposites
                         (Open English WordNet) and a pronunciation
                         respelling for each headword (CMU Pronouncing
                         Dictionary), unpacked by the app on first use

Sources (download them first; none are fetched by this script):

  Open English WordNet 2025, WN-LMF XML (CC BY 4.0)
    https://github.com/globalwordnet/english-wordnet/releases/download/2025-edition/english-wordnet-2025.xml.gz
  CMU Pronouncing Dictionary (BSD-2-Clause)
    https://raw.githubusercontent.com/cmusphinx/cmudict/master/cmudict.dict
  SCOWL 2020.12.07 (MIT-like; see its Copyright file)
    https://downloads.sourceforge.net/wordlist/scowl-2020.12.07.tar.gz

Run:

  python tool/build_dictionary.py --oewn english-wordnet-2025.xml.gz \
      --cmudict cmudict.dict --scowl scowl-2020.12.07/final

Bump DICTIONARY_VERSION when the output changes, and the same constant in
lib/spelling/dictionary.dart, so tablets unpack the new file.
"""

import argparse
import gzip
import io
import os
import re
import sqlite3
import tempfile
import xml.etree.ElementTree as ET

DICTIONARY_VERSION = 1

# SCOWL levels kept for spell check. 60 is what Hunspell's en_US uses.
# Capitalized words and names go a little further, so ordinary names
# ("Maya") aren't flagged.
WORD_LEVELS = (10, 20, 35, 40, 50, 55, 60)
NAME_LEVELS = WORD_LEVELS + (70, 80)
SCOWL_KINDS = {
    "words": WORD_LEVELS,
    "contractions": WORD_LEVELS,
    "abbreviations": WORD_LEVELS,
    "upper": NAME_LEVELS,
    "proper-names": NAME_LEVELS,
}
# Single words that are in the dictionary but not in SCOWL: accepted, but
# suggested last.
WORDNET_LEVEL = 80

POS = {"n": "n", "v": "v", "a": "a", "s": "a", "r": "r"}

_plain_word = re.compile(r"^[A-Za-z][A-Za-z'\-]*$")


def scowl_words(final_dir):
    """word -> its lowest (most common) level."""
    out = {}
    for name in os.listdir(final_dir):
        m = re.match(r"^(english|american)-([a-z\-]+)\.(\d+)$", name)
        if not m or m.group(2) not in SCOWL_KINDS:
            continue
        level = int(m.group(3))
        if level not in SCOWL_KINDS[m.group(2)]:
            continue
        with open(os.path.join(final_dir, name), encoding="latin-1") as f:
            for line in f:
                w = line.strip()
                if not w or not _plain_word.match(w):
                    continue
                if w not in out or level < out[w]:
                    out[w] = level
    return out


def read_wordnet(path):
    opener = gzip.open if path.endswith(".gz") else open
    entries = {}  # entry id -> (written, pos, [sense ids])
    forms = {}  # entry id -> [irregular forms]
    sense_entry = {}  # sense id -> entry id
    sense_synset = {}  # sense id -> synset id
    antonyms = {}  # sense id -> [target sense ids]
    synsets = {}  # synset id -> (pos, definition, [examples], [similar synset ids])
    with opener(path, "rb") as f:
        entry = None
        for event, el in ET.iterparse(f, events=("start", "end")):
            tag = el.tag
            if event == "start":
                if tag == "LexicalEntry":
                    entry = [el.get("id"), None, None, []]
                continue
            if tag == "Lemma" and entry is not None:
                entry[1] = el.get("writtenForm")
                entry[2] = POS.get(el.get("partOfSpeech"))
            elif tag == "Form" and entry is not None:
                forms.setdefault(entry[0], []).append(el.get("writtenForm"))
            elif tag == "Sense" and entry is not None:
                sid = el.get("id")
                entry[3].append(sid)
                sense_entry[sid] = entry[0]
                sense_synset[sid] = el.get("synset")
                for rel in el.findall("SenseRelation"):
                    if rel.get("relType") == "antonym":
                        antonyms.setdefault(sid, []).append(rel.get("target"))
            elif tag == "LexicalEntry":
                if entry[2] is not None:
                    entries[entry[0]] = (entry[1], entry[2], entry[3])
                entry = None
                el.clear()
            elif tag == "Synset":
                definition = el.findtext("Definition") or ""
                examples = [(e.text or "").strip() for e in el.findall("Example")]
                similar = [r.get("target") for r in el.findall("SynsetRelation") if r.get("relType") == "similar"]
                synsets[el.get("id")] = (POS.get(el.get("partOfSpeech"), "n"), definition.strip(), examples, similar)
                el.clear()
    return entries, forms, sense_entry, sense_synset, antonyms, synsets


# Pronunciation respelling from ARPAbet: "conserve" K AH0 N S ER1 V -> "kən-SURV".

VOWELS = {
    "AA": "ah", "AE": "a", "AH": "uh", "AO": "aw", "AW": "ow", "AY": "y", "EH": "e", "ER": "ur",
    "EY": "ay", "IH": "i", "IY": "ee", "OW": "oh", "OY": "oy", "UH": "uu", "UW": "oo",
}
CONSONANTS = {
    "B": "b", "CH": "ch", "D": "d", "DH": "dh", "F": "f", "G": "g", "HH": "h", "JH": "j", "K": "k",
    "L": "l", "M": "m", "N": "n", "NG": "ng", "P": "p", "R": "r", "S": "s", "SH": "sh", "T": "t",
    "TH": "th", "V": "v", "W": "w", "Y": "y", "Z": "z", "ZH": "zh",
}
# Consonant clusters a syllable may start with.
ONSETS = {
    ("P", "R"), ("T", "R"), ("K", "R"), ("B", "R"), ("D", "R"), ("G", "R"), ("F", "R"), ("TH", "R"), ("SH", "R"),
    ("P", "L"), ("K", "L"), ("B", "L"), ("G", "L"), ("F", "L"), ("S", "L"),
    ("S", "P"), ("S", "T"), ("S", "K"), ("S", "M"), ("S", "N"), ("S", "W"), ("S", "F"),
    ("T", "W"), ("D", "W"), ("K", "W"), ("G", "W"), ("TH", "W"),
    ("P", "Y"), ("B", "Y"), ("F", "Y"), ("V", "Y"), ("K", "Y"), ("M", "Y"), ("HH", "Y"),
    ("S", "P", "R"), ("S", "T", "R"), ("S", "K", "R"), ("S", "P", "L"), ("S", "K", "W"), ("S", "K", "Y"), ("S", "P", "Y"),
}
# Short vowels: a stressed one keeps the next consonant ("collision" -> kə-LIZH-ən).
SHORT = {"AE", "EH", "IH", "UH", "AA"}


def respell(phones):
    syllables = []  # [onset, nucleus, stress, coda]
    pending = []
    for ph in phones:
        base = ph.rstrip("012")
        if base in VOWELS:
            stress = int(ph[-1]) if ph[-1].isdigit() else 0
            if syllables:
                # Split the consonants between vowels: the longest legal onset goes to this syllable.
                cut = len(pending)
                for k in range(len(pending)):
                    rest = tuple(pending[k:])
                    if len(rest) == 1 or rest in ONSETS:
                        cut = k
                        break
                syllables[-1][3] += pending[:cut]
                onset = pending[cut:]
            else:
                onset = pending
            syllables.append([onset, base, stress, []])
            pending = []
        else:
            pending.append(base)
    if not syllables:
        return None
    syllables[-1][3] += pending
    # A stressed short vowel that ends its syllable takes the next consonant.
    for i in range(len(syllables) - 1):
        s, nxt = syllables[i], syllables[i + 1]
        if s[2] == 1 and s[1] in SHORT and not s[3] and nxt[0]:
            s[3] = [nxt[0][0]]
            nxt[0] = nxt[0][1:]
    out = []
    for i, (onset, nucleus, stress, coda) in enumerate(syllables):
        if nucleus == "AH" and stress == 0:
            vowel = "ə"
        elif nucleus == "IH" and stress == 0 and not coda and i == len(syllables) - 1:
            vowel = "ee"
        elif nucleus == "AY" and not onset:
            vowel = "eye"
        else:
            vowel = VOWELS[nucleus]
        end = "".join(CONSONANTS[c] for c in coda)
        if nucleus == "AY" and onset and coda:
            end += "e"  # "bite" -> byte, as Wikipedia's respelling key does
        text = "".join(CONSONANTS[c] for c in onset) + vowel + end
        out.append(text.upper() if stress == 1 and len(syllables) > 1 else text)
    return "-".join(out)


def read_cmudict(path):
    out = {}
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.split("#", 1)[0].strip()
            if not line:
                continue
            word, *phones = line.split()
            if "(" in word:  # alternative pronunciations: keep the first
                continue
            out[word] = phones
    return out


def build(args):
    os.makedirs(args.out, exist_ok=True)
    print("Reading SCOWL…")
    words = scowl_words(args.scowl)
    print(f"  {len(words)} words")
    print("Reading Open English WordNet…")
    entries, forms, sense_entry, sense_synset, antonyms, synsets = read_wordnet(args.oewn)
    print(f"  {len(entries)} entries, {len(synsets)} synsets")
    print("Reading CMUdict…")
    cmu = read_cmudict(args.cmudict)

    # Spell check: SCOWL, plus single dictionary words and their irregular forms.
    known = {w.lower() for w in words}
    added = 0
    for eid, (written, _, _) in entries.items():
        for w in [written, *forms.get(eid, [])]:
            if w and _plain_word.match(w) and w.lower() not in known:
                words[w] = WORDNET_LEVEL
                known.add(w.lower())
                added += 1
    print(f"  {added} words added from the dictionary")
    by_level = {}
    for w, level in words.items():
        by_level.setdefault(level, []).append(w)
    text = io.StringIO()
    for level in sorted(by_level):
        text.write(f"#{level}\n")
        for w in sorted(by_level[level]):
            text.write(w + "\n")
    with gzip.open(os.path.join(args.out, "en_words.txt.gz"), "wb", compresslevel=9) as f:
        f.write(text.getvalue().encode("utf-8"))

    # The dictionary.
    synset_ids = {sid: i + 1 for i, sid in enumerate(sorted(synsets))}
    with tempfile.TemporaryDirectory() as tmp:
        db_path = os.path.join(tmp, "en_dictionary.sqlite")
        db = sqlite3.connect(db_path)
        db.executescript(
            """
            CREATE TABLE info(k TEXT PRIMARY KEY, v TEXT) WITHOUT ROWID;
            CREATE TABLE senses(key TEXT NOT NULL, word TEXT NOT NULL, pos TEXT NOT NULL,
                                n INTEGER NOT NULL, synset INTEGER NOT NULL, ants TEXT);
            CREATE TABLE synsets(id INTEGER PRIMARY KEY, pos TEXT NOT NULL, def TEXT NOT NULL,
                                 ex TEXT, similar TEXT);
            CREATE TABLE say(key TEXT PRIMARY KEY, say TEXT NOT NULL) WITHOUT ROWID;
            CREATE TABLE forms(form TEXT NOT NULL, key TEXT NOT NULL, PRIMARY KEY(form, key)) WITHOUT ROWID;
            """
        )
        db.executemany(
            "INSERT INTO info VALUES (?, ?)",
            [
                ("version", str(DICTIONARY_VERSION)),
                ("source", "Open English WordNet 2025 (CC BY 4.0); CMU Pronouncing Dictionary (BSD-2-Clause)"),
                ("language", "en-US"),
            ],
        )
        rows = []
        for eid, (written, pos, senses) in entries.items():
            for n, sid in enumerate(senses):
                ants = []
                for target in antonyms.get(sid, []):
                    te = sense_entry.get(target)
                    if te in entries and entries[te][0] not in ants:
                        ants.append(entries[te][0])
                rows.append((written.lower(), written, pos, n, synset_ids[sense_synset[sid]], "|".join(ants) or None))
        db.executemany("INSERT INTO senses VALUES (?, ?, ?, ?, ?, ?)", rows)
        db.executemany(
            "INSERT INTO synsets VALUES (?, ?, ?, ?, ?)",
            [
                (
                    synset_ids[sid],
                    pos,
                    definition,
                    "\n".join(e.strip('"“”') for e in examples if e) or None,
                    " ".join(str(synset_ids[t]) for t in similar if t in synset_ids) or None,
                )
                for sid, (pos, definition, examples, similar) in synsets.items()
            ],
        )
        heads = {w.lower() for (w, _, _) in entries.values()}
        says = []
        for key in heads:
            phones = cmu.get(key)
            if phones:
                say = respell(phones)
                if say:
                    says.append((key, say))
        db.executemany("INSERT INTO say VALUES (?, ?)", says)
        db.executemany(
            "INSERT OR IGNORE INTO forms VALUES (?, ?)",
            [(f.lower(), written.lower()) for eid, (written, _, _) in entries.items() for f in forms.get(eid, [])],
        )
        db.executescript(
            """
            CREATE INDEX senses_key ON senses(key);
            CREATE INDEX senses_synset ON senses(synset);
            """
        )
        db.commit()
        db.execute("VACUUM")
        db.close()
        with open(db_path, "rb") as src, gzip.open(os.path.join(args.out, "en_dictionary.sqlite.gz"), "wb", compresslevel=9) as dst:
            dst.write(src.read())
    print(f"  {len(rows)} senses, {len(says)} pronunciations")
    for name in ("en_words.txt.gz", "en_dictionary.sqlite.gz"):
        print(f"  {name}: {os.path.getsize(os.path.join(args.out, name)) / 1e6:.1f} MB")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--oewn", required=True, help="english-wordnet-2025.xml(.gz)")
    parser.add_argument("--cmudict", required=True, help="cmudict.dict")
    parser.add_argument("--scowl", required=True, help="SCOWL's final/ folder")
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "assets", "dictionary"))
    build(parser.parse_args())
