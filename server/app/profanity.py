"""Display-name profanity hook: `is_allowed(text)`. The only place to swap in a moderation service later.

Matching (see the header of app/data/blocked_terms.txt for the file format): lowercase, strip accents, map
leetspeak (0->o, 1->i or l, 3->e, 4->a, 5->s, @->a, $->s), split into words, join runs of single characters
("f u c k", "c.u.n.t"), then
  * whole-word entries must equal a word (so "Scunthorpe Sam" and "Dickens" pass),
  * substring entries (`*stem`) are looked for in every word and in the name with all separators removed.
Runs of the same letter are also tried collapsed ("fuuuck").
"""

from __future__ import annotations

import re
import unicodedata
from functools import lru_cache
from pathlib import Path

_LEET = {"0": "o", "3": "e", "4": "a", "5": "s", "@": "a", "$": "s", "7": "t"}
_DEFAULT_LIST = Path(__file__).parent / "data" / "blocked_terms.txt"


def name_key(name: str) -> str:
    """The key display names are searched by (users.name_lower)."""
    return name.lower()


def _fold(text: str) -> str:
    text = unicodedata.normalize("NFKD", text.lower())
    return "".join(c for c in text if not unicodedata.combining(c)).replace("ß", "ss")


@lru_cache(maxsize=8)
def _load(path: str) -> tuple[frozenset[str], tuple[str, ...]]:
    whole: set[str] = set()
    stems: list[str] = []
    for raw in Path(path or _DEFAULT_LIST).read_text(encoding="utf-8").splitlines():
        line = raw.split("#", 1)[0].strip().lower()
        if not line:
            continue
        if line.startswith("*"):
            stems.append(_fold(line[1:]))
        else:
            whole.add(_fold(line))
    return frozenset(whole), tuple(stems)


def _variants(folded: str) -> set[str]:
    base = "".join(_LEET.get(c, c) for c in folded)
    out = {base.replace("1", "i"), base.replace("1", "l")}
    return out | {re.sub(r"(.)\1+", r"\1", v) for v in out}


def _words(text: str) -> list[str]:
    parts = re.findall(r"[^\W_]+", text)
    merged: list[str] = []
    run = ""
    for p in parts:
        if len(p) == 1:
            run += p
            continue
        if run:
            merged.append(run)
            run = ""
        merged.append(p)
    if run:
        merged.append(run)
    return merged


def is_allowed(text: str, list_path: str = "") -> bool:
    """False when the text contains a blocked term (see the module doc). Never raises."""
    whole, stems = _load(list_path)
    folded = _fold(text)
    for v in _variants(folded):
        words = _words(v)
        if any(w in whole for w in words):
            return False
        squashed = "".join(words)
        if any(s in w for s in stems for w in (*words, squashed)):
            return False
    return True
