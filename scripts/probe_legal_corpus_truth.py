#!/usr/bin/env python3
"""Corpus-truth probe for the CLA-evidence transfer disclosure (#7624).

Invoked by scripts/probe-legal-corpus-truth.sh, which is in turn the
`discoverability_test.command` of the #7624 plan. See that wrapper's header for
why this is a script rather than an inline grep chain, and why the correction
notes are stripped before the negative arm runs.

Exit 0 and print CORPUS-OK when the corpus is truthful; exit 1 with a per-failure
diagnostic otherwise. Exit 2 means the probe could not run (a document is
missing) -- never a silent pass.
"""

import pathlib
import re
import sys

# The audit-trail spans that legitimately QUOTE superseded wording. Verified at
# authoring time: 20 such notes across both surfaces, none containing an internal
# asterisk, so the non-greedy span match cannot over-consume.
CORRECTION_NOTE = re.compile(r"\*\(Corrected [0-9-]+, ref #\d+:.*?\)\*", re.S)

SURFACES = {
    "canonical": pathlib.Path("docs/legal"),
    "mirror": pathlib.Path("plugins/soleur/docs/pages/legal"),
}

DOCS = ["privacy-policy.md", "gdpr-policy.md", "data-protection-disclosure.md"]

# Claims that must REMAIN present. Deleting a disclosure must not be a way to pass
# this probe.
#
# This was a single string until #7786. That was sufficient while the only property
# guarded was a Chapter V safeguard, but it is NOT sufficient for a corrected factual
# claim: with FORBIDDEN alone, the property "the corpus discloses off-host log
# shipping" is guarded by ABSENCE only, so deleting the clause wholesale PASSES. That
# is exactly the minimal framing rejected on the facts in #7786 -- deleting the
# parenthetical turns a self-announcing contradiction into a silent omission, which is
# strictly worse. The affirmative anchor is what lets the probe tell a CORRECTION from
# a DELETION.
REQUIRED = [
    "EU-US Data Privacy Framework",
    # The off-host disclosure, anchored on the recipient and the date the
    # application-container stream actually started shipping (PR #4786).
    "Better Stack",
    "2026-06-02",
]

# The three superseded claims, as ASSERTIONS. Matched case-insensitively -- safe
# only because the quoting correction notes are removed first.
FORBIDDEN = [
    "no third-country transfer for archive contents at rest",
    "does not introduce a third-country transfer",
    "Intra-EU processing for archive contents at rest",
    # --- #7786 / #6474: the off-host-log denial and the misattributed cap. ---
    # FIVE phrasings, because the corpus stated one claim five ways and a sweep
    # anchored on any single literal reads as complete while missing the rest.
    "no off-host log shipping is configured",
    "no off-host copies",
    "rolling Docker log buffer",
    # LOAD-BEARING and nearly missed. gdpr-policy.md stated the false mechanism
    # TWICE, and the second occurrence -- "pino stdout retained in the
    # fixed-capacity Hetzner-local rolling buffer" -- carries NONE of the other
    # four literals. Without this entry that occurrence is invisible to every
    # other guard in this file.
    "Hetzner-local rolling buffer",
    # The daemon default misattributed to a container that runs --log-driver journald.
    "30 MB",
]


# Anti-vacuity floor. ABSOLUTE literals, deliberately NOT `len(SURFACES) * len(DOCS)`:
# that expression is satisfied by `DOCS = []` at `0 == 0`, so the guard meant to prove
# the probe examined something would itself pass having examined nothing -- the exact
# defect class this repo has documented repeatedly. Hand-ratcheted, like MIN_TRACKED_SUITES
# / MIN_CHECKS / MIN_CASES elsewhere in scripts/.
MIN_SURFACES = 2
MIN_DOCS = 3


def main() -> int:
    failures: list[str] = []
    checked = 0

    for surface, root in SURFACES.items():
        for name in DOCS:
            path = root / name
            if not path.is_file():
                print(f"PROBE-CANNOT-RUN: missing {path}", file=sys.stderr)
                return 2

            raw = path.read_text(encoding="utf-8")
            stripped = CORRECTION_NOTE.sub("", raw)
            checked += 1

            for required in REQUIRED:
                if required not in stripped:
                    failures.append(
                        f"{surface}/{name}: lost a required disclosure ({required!r}) -- "
                        "a deletion is not a correction"
                    )

            lowered = stripped.lower()
            for claim in FORBIDDEN:
                if claim.lower() in lowered:
                    failures.append(f"{surface}/{name}: asserts superseded claim {claim!r}")

    if checked < MIN_SURFACES * MIN_DOCS:
        print(
            f"PROBE-VACUOUS: examined {checked} document(s), expected at least "
            f"{MIN_SURFACES * MIN_DOCS} ({MIN_SURFACES} surfaces x {MIN_DOCS} docs). "
            "A probe that examines nothing must not report success.",
            file=sys.stderr,
        )
        return 2

    if failures:
        for line in failures:
            print(f"CORPUS-FALSE: {line}", file=sys.stderr)
        return 1

    print(f"CORPUS-OK ({checked} document(s) examined)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
