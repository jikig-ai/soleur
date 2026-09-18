#!/usr/bin/env python3
"""Per-file byte ceiling for lifecycle SKILL.md bodies, anchored to the merge base.

THE PROPERTY: no lifecycle SKILL.md exceeds its pinned ceiling, and a ceiling can
only be lowered.

WHY THE ANCHOR IS THE MERGE BASE AND NOT THE WORKING TREE. A ceiling read from the
working tree lets one diff raise both the file and its own limit, so the guard
certifies itself. That is not hypothetical: SKILL_DESCRIPTION_WORD_BUDGET in
plugins/soleur/test/components.test.ts sits at 2442 after FOURTEEN bumps, most
recorded "against an N/N zero-headroom baseline" -- a budget that has never once
forced a trim, because raising it is a one-token edit in the same commit. Reading
the ceiling from the base makes a same-diff raise impossible, so raising one costs
a separate, independently reviewed PR.

WHERE THIS RUNS IS PART OF THE CONTRACT. A merge-base read needs a fetched
origin/main. The obvious home -- alongside the existing budget in
components.test.ts -- is a CI job with NO fetch-depth, where at depth 1
origin/main is not a ref at all: the read would fail on every run, and any
working-tree fallback would be permanently fail-open, degrading this guard into
the changelog it replaces. So it lives in a fetch-depth: 0 job (the rule-body-lint
shape), and an unavailable base is a HARD FAILURE rather than a skip.

ONE-SIDED BY DESIGN. Driving a number DOWN never reds. A two-sided pin would
punish exactly the behaviour the ratchet exists to encourage.

The node set comes from .claude/workflow-transitions.json, so "lifecycle skill" is
a machine-readable set rather than a hand-listed one -- a skill added to the
lifecycle cannot silently escape the ratchet, and an empty set fails rather than
reporting a clean sweep over nothing.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

BUDGET_REL = "plugins/soleur/test/skill-body-budget.json"
VIEW_REL = ".claude/workflow-transitions.json"


def git_show(ref: str, path: str) -> tuple[int, str, str]:
    r = subprocess.run(
        ["git", "show", f"{ref}:{path}"], capture_output=True, text=True
    )
    return r.returncode, r.stdout, r.stderr


def ref_exists(ref: str) -> bool:
    r = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"{ref}^{{commit}}"],
        capture_output=True,
        text=True,
    )
    return r.returncode == 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--base", required=True, help="git ref to read ceilings from")
    args = ap.parse_args()

    errors: list[str] = []

    # --- the base must resolve. Never degrade to the working tree. ------------
    if not ref_exists(args.base):
        print(
            f"FATAL: base ref '{args.base}' does not resolve.\n"
            "       This is a hard failure, never a skip. Falling back to the working\n"
            "       tree would let one diff raise a ceiling and satisfy itself, which is\n"
            "       the defect this guard exists to prevent. Ensure the job checks out\n"
            "       with fetch-depth: 0 and fetches origin/main before running.",
            file=sys.stderr,
        )
        return 2

    # --- the node set defines what must be covered ---------------------------
    view_path = Path(VIEW_REL)
    if not view_path.is_file():
        print(f"FATAL: {VIEW_REL} not readable — cannot determine the lifecycle node set.", file=sys.stderr)
        return 2
    try:
        nodes = sorted(json.loads(view_path.read_text()).get("transitions", {}).keys())
    except json.JSONDecodeError as exc:
        print(f"FATAL: {VIEW_REL} is not valid JSON: {exc}", file=sys.stderr)
        return 2

    # An empty node set would make every check below vacuously true and report a
    # clean sweep over nothing. That is the anti-vacuity floor.
    if not nodes:
        print(
            "FATAL: the lifecycle node set is EMPTY — this guard would pass over zero\n"
            "       files and report success. Refusing to report OK.",
            file=sys.stderr,
        )
        return 2

    # --- current ceilings -----------------------------------------------------
    budget_path = Path(BUDGET_REL)
    if not budget_path.is_file():
        print(
            f"FATAL: {BUDGET_REL} is missing from the working tree.\n"
            "       Deleting it is not an escape hatch: with no ceilings there is nothing\n"
            "       to exceed, so every file would pass.",
            file=sys.stderr,
        )
        return 2
    try:
        current = json.loads(budget_path.read_text()).get("ceilings", {})
    except json.JSONDecodeError as exc:
        print(f"FATAL: {BUDGET_REL} is not valid JSON: {exc}", file=sys.stderr)
        return 2

    # --- base ceilings, with an explicit bootstrap arm ------------------------
    rc, base_raw, _err = git_show(args.base, BUDGET_REL)
    if rc == 0:
        try:
            base_ceilings = json.loads(base_raw).get("ceilings", {})
        except json.JSONDecodeError as exc:
            print(f"FATAL: {BUDGET_REL} at base '{args.base}' is not valid JSON: {exc}", file=sys.stderr)
            return 2
        bootstrap = False
    else:
        # The PR that INTRODUCES the ceiling file has no base version of it. This
        # arm is narrow on purpose: the base ref itself resolved (checked above),
        # so this is "the file is new", not "the base is unavailable".
        base_ceilings = {}
        bootstrap = True
        print(
            f"NOTE: {BUDGET_REL} does not exist at base '{args.base}' — treating this as the\n"
            "      introducing commit. The monotonic check is skipped for files with no base\n"
            "      ceiling; every other check still applies.",
            file=sys.stderr,
        )

    # --- per-node checks ------------------------------------------------------
    for node in nodes:
        skill = Path(f"plugins/soleur/skills/{node}/SKILL.md")

        # A lifecycle skill with no row is UNCLASSIFIED and fails. Without this,
        # adding a skill to the lifecycle silently escapes the ratchet.
        if node not in current:
            errors.append(
                f"{node}: no ceiling in {BUDGET_REL} — every lifecycle skill needs one, "
                f"or it escapes the ratchet entirely"
            )
            continue

        ceiling = current[node]

        # Monotonic: a ceiling may fall, never rise. Compared against the BASE, so
        # raising it in this diff cannot satisfy it.
        if node in base_ceilings and ceiling > base_ceilings[node]:
            errors.append(
                f"{node}: ceiling RAISED {base_ceilings[node]} -> {ceiling}. Ceilings ratchet "
                f"down only. Raising one is a separate, independently reviewed PR — doing it "
                f"in the same diff as the growth is what {BUDGET_REL} exists to stop."
            )

        if not skill.is_file():
            errors.append(f"{node}: {skill} not found, but a ceiling is declared for it")
            continue

        size = skill.stat().st_size
        if size > ceiling:
            errors.append(
                f"{node}: {skill} is {size} bytes, ceiling is {ceiling} "
                f"({size - ceiling} over). Trim the body or extract a block into "
                f"references/ behind a conditional load directive."
            )

    if errors:
        print("lint-skill-body-budget: FAIL", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    scope = f"{len(nodes)} lifecycle skill(s)"
    suffix = " [bootstrap: no base ceilings]" if bootstrap else ""
    print(f"lint-skill-body-budget: OK ({scope} within ceilings, base={args.base}){suffix}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
