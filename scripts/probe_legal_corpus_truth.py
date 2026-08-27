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

# The Chapter V safeguard must remain disclosed. Deleting the disclosure must not
# be a way to pass this probe.
REQUIRED = "EU-US Data Privacy Framework"

# The three superseded claims, as ASSERTIONS. Matched case-insensitively -- safe
# only because the quoting correction notes are removed first.
FORBIDDEN = [
    "no third-country transfer for archive contents at rest",
    "does not introduce a third-country transfer",
    "Intra-EU processing for archive contents at rest",
]


def main() -> int:
    failures: list[str] = []

    for surface, root in SURFACES.items():
        for name in DOCS:
            path = root / name
            if not path.is_file():
                print(f"PROBE-CANNOT-RUN: missing {path}", file=sys.stderr)
                return 2

            raw = path.read_text(encoding="utf-8")
            stripped = CORRECTION_NOTE.sub("", raw)

            if REQUIRED not in stripped:
                failures.append(f"{surface}/{name}: lost the safeguard disclosure ({REQUIRED!r})")

            lowered = stripped.lower()
            for claim in FORBIDDEN:
                if claim.lower() in lowered:
                    failures.append(f"{surface}/{name}: asserts superseded claim {claim!r}")

    if failures:
        for line in failures:
            print(f"CORPUS-FALSE: {line}", file=sys.stderr)
        return 1

    print("CORPUS-OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
