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
# The corpus writes corrections in SEVERAL shapes, and stripping only one of them is
# a fail-RED: a future correction that legitimately QUOTES superseded wording reds this
# probe on a corpus that is correct, and the cheapest way out of that red is to delete
# the quote -- which is exactly what the REQUIRED anchors below exist to prevent.
# Measured shapes actually present in the corpus (2026-09-07):
#   *(Corrected 2026-08-20, ref #7624: ...)*        <- the original, ISO + "ref #"
#   *(corrected June 11, 2026: ...)*                 <- lowercase, word-date, no ref
#   **Corrected September 7, 2026 (#7786 / #6474).** <- bold, word-date, parenthesised refs
#   *(Updated 2026-09-07, #7786: ...)*               <- "Updated", comma-ref
#   **[2026-09-07 CORRECTION (#6474). ...]**         <- the register's bracket form
# Case-insensitive, both Corrected/Updated, ISO or word dates, ref optional.
_DATE = r"(?:[0-9]{4}-[0-9]{2}-[0-9]{2}|[A-Z][a-z]+ [0-9]{1,2}, [0-9]{4})"
CORRECTION_NOTE = re.compile(
    r"\*+\(?(?:Corrected|Updated)\s+" + _DATE + r"[^)*]*\)?\*+"      # inline note forms
    r"|\*\((?:Corrected|Updated)\s+" + _DATE + r".*?\)\*"            # spanning note form
    r"|\*\*\[" + _DATE + r"\s+CORRECTION\b.*?\]\*\*",             # register bracket form
    re.S | re.IGNORECASE,
)

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
]

# A bare "30 MB" was the first shape of the entry below and was wrong in BOTH directions.
# Too broad: the corpus legitimately discloses size limits in exactly that shape (`1 MB` in
# privacy-policy, `24 MB` twice in acceptable-use-policy), so a future PR disclosing a
# 30 MB attachment cap would red this blocking gate on EVERY open PR -- and the author's
# escapes would be to reword it or to wrap a true statement in a retraction note, both of
# which corrupt the corpus to satisfy the guard. Too narrow: `30MB`, `30 megabytes` and
# `max-size=10m` all reintroduce the retracted claim and evade the literal.
#
# Anchored on the CO-OCCURRENCE that made the claim false -- the figure standing next to
# the mechanism it was misattributed to -- rather than on the number alone.
FORBIDDEN_PATTERNS = [
    re.compile(
        r"(?:30\s*(?:MB|megabytes?)|max-size\s*=?\s*10m)"
        r"[^.]{0,120}?"
        r"(?:json-file|rolling buffer|rolling per container|per container)",
        re.IGNORECASE,
    ),
    re.compile(
        r"(?:json-file|rolling buffer|rolling per container)"
        r"[^.]{0,120}?"
        r"(?:30\s*(?:MB|megabytes?)|max-size\s*=?\s*10m)",
        re.IGNORECASE,
    ),
]


# Anti-vacuity floor. ABSOLUTE literals, deliberately NOT `len(SURFACES) * len(DOCS)`:
# that expression is satisfied by `DOCS = []` at `0 == 0`, so the guard meant to prove
# the probe examined something would itself pass having examined nothing -- the exact
# defect class this repo has documented repeatedly. Hand-ratcheted, like MIN_TRACKED_SUITES
# / MIN_CHECKS / MIN_CASES elsewhere in scripts/.
MIN_SURFACES = 2
MIN_DOCS = 3

# The walk's cardinality is floored above; the CLAIM LISTS were not, so `FORBIDDEN = []`
# printed `CORPUS-OK (6 document(s) examined)` at rc=0 -- six documents examined against
# nothing. Absolute, hand-ratcheted, and set to the current exact counts: the lists only
# ever grow, and slack in a floor is narrowing budget rather than safety margin.
MIN_FORBIDDEN = 8
MIN_REQUIRED = 3

# An empty or near-empty REQUIRED entry is FAIL-OPEN, and asymmetrically so: `"" in text`
# is always True, so a blanked entry silently widens the guard to accept everything --
# defeating the affirmative anchor whose entire job is telling a CORRECTION from a
# DELETION. (The FORBIDDEN direction is safe: a blank entry matches everything and fails
# closed, noisily.) A length floor also kills the degenerate-but-nonempty case, e.g. an
# entry reduced to "the".
MIN_CLAIM_LEN = 8


# A correction note is an INLINE span. `re.S` + a lazy `.*?` lets one run to the next `)*`
# anywhere in the file, so wrapping a region in a fake audit note hides every FORBIDDEN
# claim inside it -- disarming this guard with a document edit and no code change at all.
# Reproduced against the real corpus before this was added: two live claims, `CORPUS-OK`,
# rc=0. Measured discriminator: of the 20 legitimate notes in the corpus, ZERO contain a
# blank line, because a correction note is a parenthetical, not a section. A LENGTH cap
# does not discriminate (the longest legitimate note is 880 chars, longer than the exploit).
PARAGRAPH_BREAK = re.compile(r"\n[ \t]*\n")


def _strip_correction_notes(raw: str, where: str, failures: list[str]) -> str:
    """Strip correction notes, refusing any that spans a paragraph break."""
    kept: list[str] = []
    last = 0
    for m in CORRECTION_NOTE.finditer(raw):
        if PARAGRAPH_BREAK.search(m.group(0)):
            failures.append(
                f"{where}: a correction note spans a paragraph break "
                f"({len(m.group(0))} chars). A note is an inline parenthetical; one that "
                "crosses a blank line hides everything inside it from this probe."
            )
            continue  # do NOT strip it -- leave the span visible to the claim checks
        kept.append(raw[last:m.start()])
        last = m.end()
    kept.append(raw[last:])
    return "".join(kept)


def main() -> int:
    failures: list[str] = []
    # A SET of (surface, doc) pairs, not a counter. A plain counter is satisfied by a
    # DUPLICATE member (DOCS = [privacy, privacy, gdpr] still reaches 6) and so cannot
    # tell "examined six documents" from "examined one document three times".
    seen: set[tuple[str, str]] = set()

    for surface, root in SURFACES.items():
        for name in DOCS:
            path = root / name
            if not path.is_file():
                print(f"PROBE-CANNOT-RUN: missing {path}", file=sys.stderr)
                return 2

            raw = path.read_text(encoding="utf-8")
            stripped = _strip_correction_notes(raw, f"{surface}/{name}", failures)
            seen.add((surface, name))

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

            for rx in FORBIDDEN_PATTERNS:
                m = rx.search(stripped)
                if m:
                    failures.append(
                        f"{surface}/{name}: asserts superseded claim "
                        f"{m.group(0)[:80]!r} (misattributed json-file cap)"
                    )

    # The length floor applies to REQUIRED ONLY, and the asymmetry is the whole point:
    # a short/blank REQUIRED entry matches every document and widens the guard to accept
    # anything (fail-OPEN), while a short/blank FORBIDDEN entry matches every document and
    # rejects everything (fail-CLOSED, noisily). `30 MB` is a legitimate 6-character
    # FORBIDDEN literal -- applying the floor to both lists refuses the corpus on a
    # correct configuration, which this guard did on its first run.
    short_req = [c for c in REQUIRED if len(c.strip()) < MIN_CLAIM_LEN]
    blank_forb = [c for c in FORBIDDEN if not c.strip()]
    if short_req or blank_forb:
        print(
            f"PROBE-VACUOUS: REQUIRED entries shorter than {MIN_CLAIM_LEN} chars: "
            f"{short_req!r}; blank FORBIDDEN entries: {blank_forb!r}. A blank or trivial "
            "REQUIRED entry matches every document and silently widens this guard to "
            "accept anything.",
            file=sys.stderr,
        )
        return 2

    if (
        len(FORBIDDEN) + len(FORBIDDEN_PATTERNS) < MIN_FORBIDDEN
        or len(REQUIRED) < MIN_REQUIRED
    ):
        print(
            f"PROBE-VACUOUS: FORBIDDEN has {len(FORBIDDEN)} entries (floor {MIN_FORBIDDEN}) "
            f"and REQUIRED has {len(REQUIRED)} (floor {MIN_REQUIRED}). A walk over every "
            "document proves nothing if the claim lists were emptied.",
            file=sys.stderr,
        )
        return 2

    # INDEPENDENT FACTORS, not their product. `checked < MIN_SURFACES * MIN_DOCS` is
    # satisfied by TRADING one factor against the other -- three surfaces x two documents
    # still reaches 6 while an entire published legal document goes unexamined. Measured:
    # dropping data-protection-disclosure.md and adding a third surface kept the count at
    # 6 and made a reintroduced `Hetzner-local rolling buffer` invisible.
    seen_surfaces = {sfc for sfc, _ in seen}
    seen_docs = {doc for _, doc in seen}
    if len(seen_surfaces) < MIN_SURFACES or len(seen_docs) < MIN_DOCS:
        print(
            f"PROBE-VACUOUS: examined {len(seen_surfaces)} surface(s) and "
            f"{len(seen_docs)} distinct document(s); floors are {MIN_SURFACES} and "
            f"{MIN_DOCS}. These are checked as independent factors -- a walk that trades "
            "a document for a surface leaves a published document unexamined while the "
            "total stays the same.",
            file=sys.stderr,
        )
        return 2

    checked = len(seen)
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
