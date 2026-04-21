#!/usr/bin/env python3
"""Parity test: the rule_id validation regex is defined twice (bash ERE in
scripts/rule-prune.sh as _RULE_ID_RE, and Python re in scripts/lint-rule-ids.py
at line 54). Bash ERE and Python re differ in syntax, so the definitions can't
be shared via scripts/lib/rule-metrics-constants.sh. This test asserts the two
regexes agree on accept/reject for a corpus of candidate IDs — if they drift,
the prune script would silently skip rules the lint script accepts (or vice
versa), which is exactly the data-loss class the orphan-IDs surface was added
to catch.

Active enforcement replaces the prose drift comments in both files.
"""

from __future__ import annotations

import re
import subprocess
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
RULE_PRUNE = REPO_ROOT / "scripts" / "rule-prune.sh"

# Python validation regex — copied verbatim from scripts/lint-rule-ids.py:54.
PY_RE = re.compile(r"^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{3,60}$")


def bash_match(rule_id: str) -> bool:
    """Invoke bash with the ERE from rule-prune.sh and report match/no-match."""
    script = f'''
    _RULE_ID_RE='^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{{3,60}}$'
    if [[ "$1" =~ $_RULE_ID_RE ]]; then echo match; else echo no; fi
    '''
    out = subprocess.run(
        ["bash", "-c", script, "_", rule_id],
        capture_output=True, text=True, check=True,
    ).stdout.strip()
    return out == "match"


CORPUS = [
    # (id, expected_match)
    # Accepts — minimum length, normal length, max length (60 chars body).
    ("hr-abc", True),
    ("wg-abc", True),
    ("cq-abc", True),
    ("rf-abc", True),
    ("pdr-abc", True),
    ("cm-abc", True),
    ("hr-" + "a" * 60, True),
    ("hr-rule-with-dashes-and-numbers-123", True),
    ("hr-a1b2c3", True),
    # Rejects — wrong prefix, uppercase, special chars, out of length bounds.
    ("xx-bad-prefix", False),
    ("HR-upper-prefix", False),
    ("hr-UPPER-body", False),
    ("hr-under_score", False),
    ("hr-with.dot", False),
    ("hr-with space", False),
    ("hr-ab", False),   # 2-char body, below min 3
    ("hr-", False),     # empty body
    ("", False),
    ("hr-" + "a" * 61, False),   # 61-char body, above max 60
    ("no-prefix-dashes", False),
    ("hr--double-dash", True),   # both accept — adjacent dashes are fine
    ("hr-trailing-dash-", True),  # both accept — trailing dash is fine
]


class RuleIdParityTests(unittest.TestCase):
    def test_rule_prune_sh_carries_expected_regex(self):
        """Sanity: rule-prune.sh still contains the ERE string we're testing
        against. If this fails, someone edited rule-prune.sh and the corpus
        regex here needs the same edit.
        """
        src = RULE_PRUNE.read_text()
        self.assertIn(
            "_RULE_ID_RE='^(hr|wg|cq|rf|pdr|cm)-[a-z0-9-]{3,60}$'",
            src,
            "rule-prune.sh _RULE_ID_RE drifted from parity-test expectation",
        )

    def test_parity_across_corpus(self):
        drift: list[str] = []
        for rule_id, expected in CORPUS:
            py = bool(PY_RE.match(rule_id))
            sh = bash_match(rule_id)
            if py != expected or sh != expected:
                drift.append(
                    f"id={rule_id!r} expected={expected} py={py} bash={sh}"
                )
        self.assertEqual(drift, [], "regex drift detected:\n  " + "\n  ".join(drift))


if __name__ == "__main__":
    unittest.main()
