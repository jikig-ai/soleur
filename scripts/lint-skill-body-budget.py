#!/usr/bin/env python3
"""Per-file byte ceiling for lifecycle SKILL.md bodies, anchored to the merge base.

THE PROPERTY: no lifecycle SKILL.md exceeds its pinned ceiling, and a ceiling can
only be lowered.

WHY THE ANCHOR IS THE MERGE BASE AND NOT THE WORKING TREE. A ceiling read from the
working tree lets one diff raise both the file and its own limit, so the guard
certifies itself. That is not hypothetical: SKILL_DESCRIPTION_WORD_BUDGET in
plugins/soleur/test/components.test.ts sits at 2442 after FIFTEEN bumps (counted 2026-09-18), most
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
reporting a clean sweep over nothing. Three refinements, each closing a measured
escape from review:

  - KEYS AND DESTINATIONS. A destination-only node (`one-shot`, reachable from
    brainstorm) has no key and was unmeasured while being the orchestrator every
    `/go fix` routes to. The set is keys | all destinations.
  - BASE AND WORKING TREE. Reading the view from the working tree alone let one
    diff drop a node from the view AND bloat that node's SKILL.md: the ratchet
    then reported OK over the survivors. The set is the union of the view at
    the base and the view in the working tree, so a removed node is still
    measured against the base ceiling in the diff that removes it.
  - ORPHAN ROWS. A ceiling row for a name that is not a node is an UNCLASSIFIED
    row and fails, mirroring the node-with-no-row bucket below. Without it, a
    row could outlive its node silently.
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
    ap = argparse.ArgumentParser(
        description=(__doc__ or "").strip().splitlines()[0],
        epilog="Run from the repository root (paths resolve via `git rev-parse --show-toplevel`). Full rationale: the module docstring.",
    )
    ap.add_argument("--base", required=True, help="git ref to read ceilings from")
    args = ap.parse_args()

    errors: list[str] = []

    # Paths are repo-relative; resolve the toplevel so a wrong cwd is named as
    # such instead of blaming a file that exists.
    top = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    if top.returncode != 0:
        print("FATAL: not inside a git repository (run from the soleur checkout).", file=sys.stderr)
        return 2
    import os
    os.chdir(top.stdout.strip())

    # --- the base must resolve. Never degrade to the working tree. ------------
    if not ref_exists(args.base):
        print(
            f"FATAL: base ref '{args.base}' does not resolve.\n"
            "       This is a hard failure, never a skip. Falling back to the working\n"
            "       tree would let one diff raise a ceiling and satisfy itself, which is\n"
            "       the defect this guard exists to prevent. In CI: check out with\n"
            "       fetch-depth: 0 and fetch origin/main first. Locally: `git fetch origin main`.",
            file=sys.stderr,
        )
        return 2

    # --- the node set defines what must be covered ---------------------------
    view_path = Path(VIEW_REL)
    if not view_path.is_file():
        print(f"FATAL: {VIEW_REL} not readable — cannot determine the lifecycle node set.", file=sys.stderr)
        return 2
    try:
        wt_view = json.loads(view_path.read_text()).get("transitions", {})
    except json.JSONDecodeError as exc:
        print(f"FATAL: {VIEW_REL} is not valid JSON: {exc}", file=sys.stderr)
        return 2
    rc_v, base_view_raw, _ = git_show(args.base, VIEW_REL)
    base_view: dict = {}
    if rc_v == 0:
        try:
            base_view = json.loads(base_view_raw).get("transitions", {})
        except json.JSONDecodeError as exc:
            print(f"FATAL: {VIEW_REL} at base '{args.base}' is not valid JSON: {exc}", file=sys.stderr)
            return 2
    node_set: set[str] = set()
    for view in (wt_view, base_view):
        node_set.update(view.keys())
        for dests in view.values():
            node_set.update(dests)
    nodes = sorted(node_set)

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
            "       to exceed, so every file would pass. Restore it: git checkout <base> -- "
            f"{BUDGET_REL}",
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
        #
        # NARROWER STILL: bootstrap is only legal when THIS LINT is also absent at
        # the base. Review found the rename escape -- `git mv` the ceiling file
        # and update BUDGET_REL in the same diff, and every ceiling re-seeds
        # itself with the monotonic check skipped. If the lint existed at the
        # base, the ceiling file existed too (they land together), so a missing
        # base file under an existing base lint is a rename, not an introduction.
        rc_l, _, _ = git_show(args.base, "scripts/lint-skill-body-budget.py")
        if rc_l == 0:
            print(
                f"FATAL: {BUDGET_REL} is absent at base '{args.base}' but this lint is present\n"
                "       there. That is a RENAME or deletion of the ceiling file, not its\n"
                "       introduction, and it would re-seed every ceiling with the monotonic\n"
                "       check skipped. Keep the file at its base path.",
                file=sys.stderr,
            )
            return 2
        base_ceilings = {}
        bootstrap = True
        print(
            f"NOTE: {BUDGET_REL} does not exist at base '{args.base}' — treating this as the\n"
            "      introducing commit. The monotonic check is skipped for files with no base\n"
            "      ceiling; every other check still applies.",
            file=sys.stderr,
        )

    # --- the changed-file set decides whether a raise is legal --------------
    # `git diff --name-only <base> HEAD` plus the working tree: CI runs on a
    # committed HEAD, but the local gate may run on an uncommitted tree, and a
    # raise staged beside an unstaged SKILL.md growth must still be refused.
    changed: set[str] = set()
    for argv in (["git", "diff", "--name-only", args.base, "HEAD"],
                 ["git", "diff", "--name-only", "HEAD"],
                 ["git", "diff", "--name-only", "--cached"]):
        r = subprocess.run(argv, capture_output=True, text=True)
        if r.returncode != 0:
            print(f"FATAL: {' '.join(argv)} failed: {r.stderr.strip()}", file=sys.stderr)
            return 2
        changed.update(line for line in r.stdout.splitlines() if line)
    raise_only_diff = changed == {BUDGET_REL}

    # Orphan rows are pinned on the TypeScript side (workflow-fidelity.test.ts:
    # budget keys == FSM nodes ∪ destinations ∪ ONE_SHOT_CHILD_SKILLS), because
    # the lifecycle also includes sub-skills the FSM does not model (qa,
    # deepen-plan) and only the TS constants know that set. Here every ROW is
    # measured and every NODE must have a row; a row the TS side does not
    # authorise reds there.
    # --- per-row checks: every node needs a row; every row is measured --------
    for node in sorted(node_set | set(current)):
        skill = Path(f"plugins/soleur/skills/{node}/SKILL.md")

        # A lifecycle skill with no row is UNCLASSIFIED and fails. Without this,
        # adding a skill to the lifecycle silently escapes the ratchet.
        if node not in current:  # only reachable for a NODE with no row
            errors.append(
                f"{node}: no ceiling in {BUDGET_REL} — every lifecycle skill needs one, "
                f"or it escapes the ratchet entirely"
            )
            continue

        ceiling = current[node]

        # Monotonic: a ceiling may fall, never rise -- EXCEPT in a diff whose
        # only change is the ceiling file itself. Review found the earlier text
        # ("raising one is a separate PR") prescribed a remedy that could not
        # pass: the separate PR was compared against the same base and reddened
        # identically, so the only ways through were an admin bypass of a
        # required check or editing this lint in the raising PR. A gate whose
        # documented remedy cannot pass trains contributors to bypass it. The
        # legal raise is now mechanical: the diff base..HEAD touches NOTHING but
        # the ceiling file, so a raise structurally cannot ride with the growth
        # it would license. That diff is still independently reviewed.
        if node in base_ceilings and ceiling > base_ceilings[node] and not raise_only_diff:
            errors.append(
                f"{node}: ceiling RAISED {base_ceilings[node]} -> {ceiling}. Ceilings ratchet "
                f"down only, except in a diff that changes ONLY {BUDGET_REL} (this diff also "
                f"touches: {', '.join(sorted(changed - {BUDGET_REL})[:5])}). Land the raise as "
                f"its own PR with no other file in it; doing it in the same diff as the growth "
                f"is what {BUDGET_REL} exists to stop."
            )

        if not skill.is_file():
            errors.append(f"{node}: {skill} not found, but a ceiling is declared for it")
            continue

        size = skill.stat().st_size
        if size > ceiling:
            errors.append(
                f"{node}: {skill} is {size} bytes, ceiling is {ceiling} "
                f"({size - ceiling} over). Trim the body, or extract a block into references/ "
                f"behind a load directive gated on a named step (ADR-225 records that an "
                f"unconditional extraction saves bytes only per-turn, not per-invocation)."
            )

    if errors:
        print("lint-skill-body-budget: FAIL", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1

    scope = f"{len(node_set | set(current))} lifecycle skill(s)"
    suffix = " [bootstrap: no base ceilings]" if bootstrap else ""
    print(f"lint-skill-body-budget: OK ({scope} within ceilings, base={args.base}){suffix}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
