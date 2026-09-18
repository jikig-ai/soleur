#!/usr/bin/env python3
"""A `uses: ./…` step resolves from the runner's WORKSPACE, so its job must have checked out.

WHY THIS EXISTS. `scheduled-marketplace-drift.yml`'s `drift-check` job is deliberately
checkout-free (every input is a public URL fetched over HTTPS) and ended in
`uses: ./.github/actions/sentry-heartbeat` under `if: always()` + `continue-on-error: true`.
GitHub resolves a `./` action from the checked-out workspace; this job has none, so on every
tick the runner printed

    ##[error]Can't find 'action.yml', 'action.yaml' or 'Dockerfile' under
    '/home/runner/work/soleur/soleur/.github/actions/sentry-heartbeat'.
    Did you forget to run actions/checkout before running your local action?

and `continue-on-error` turned that into a green step. All 36 scheduled runs after the
2026-08-13 "repair" (which forwarded the composite's inputs and verified a green step) carry that
line; 33 of them concluded `success`; the Sentry monitor recorded zero check-ins from the day it
was created. The same class was repaired in `scheduled-devin-docs-drift.yml` on 2026-09-18 by
adding a checkout (#8280, merged 11:34:15Z — that workflow was created the same day). Nothing in the repo asserted the property, so it recurred.

THE RULE. For every job in every workflow, every step whose `uses:` starts with `./` must be
preceded — earlier in the SAME job's `steps` list — by a step whose `uses:` matches
`^actions/checkout(@|$)` that is USABLE for it. `checkout_usable()` is the authority on that
word and enforces five conditions, not one: no `continue-on-error: true`; no `with: repository:`;
no `with: path:`; no `with: sparse-checkout:` cone that excludes `.github`; and either no `if:`
or an `if:` byte-identical to the local step's. A checkout skipped by its own condition is no
checkout (a `./` step under `if: always()` after a checkout under `if: ${{ inputs.x }}` is a
finding); with several earlier checkouts, any qualifying one satisfies the step.

Every other `uses:` value needs no checkout and is IGNORED — `$/path` (GitHub's self-repository
reference: resolved from the repository at the running commit, no checkout required, documented
as the recommended form for same-repo actions and the one checkout-free jobs must use),
`owner/repo[/path]@ref`, and `docker://…` are all downloaded during `Set up job`, and a bad one
fails the job loudly before any step runs. One explicit reject outside that rule: a `$/` value
carrying an `@` — GitHub rejects it at setup, but actionlint 1.7.7 ACCEPTS it (measured), so
this lint names it.

SECOND SURFACE. No composite step under `.github/actions/**` may `uses:` a `./` path (a nested
`./` resolves from the CALLER's workspace, which no lint can see; GitHub documents `$/` for
composite steps), and the `$/…@ref` reject applies there too. The walk is RECURSIVE — an action
at `.github/actions/<a>/<b>/action.yml` resolves fine for GitHub, so a one-level glob would let
`git mv` move a composite out of the guard's reach with every caller still working. The actions
directory is the sibling of the scanned workflows directory (`<dir>/../actions`), so a tree
copied under `mktemp -d` scans both; the count is printed so "scanned nothing" is legible, and
a tree whose workflows reference `./.github/actions/…` while that directory is ABSENT exits 2
rather than silently walking zero composites.

NAMED NON-PROPERTIES (so the claim is not overstated). `if:` is compared as a string, never
evaluated — a `./` step whose `if:` legitimately narrows its checkout's is a loud false positive
with an obvious fix. Whether the checkout ref is pinned (`@v4` vs `@<sha>`) is a separate property.
Job-level `uses:` (a reusable-workflow call) is not a step and is skipped. A job that checks out
via `run: git clone` is not recognised as checked out (0 such jobs today).

THE FLOOR. `MIN_SAME_REPO_STEPS` counts `./` and `$/` steps TOGETHER, so a future `./` → `$/`
migration cannot drive this guard to "scanning nothing": 54 today, floor 30. Below it is rc 2.

DIRECTION OF ERROR. A false positive blocks a PR loudly, and the fix is to add
`actions/checkout` or switch to `$/`. A false negative is the 37-day dark window above (36 of those days followed a post-mortem that recorded the incident as resolved). Every
non-scan outcome — usage, an unreadable or unparseable file, a file with no `jobs` mapping, a
non-mapping job or step, a non-string `uses:`, zero files, the floor — is rc 2 NAMING the cause,
never a silent skip.

Measured on origin/main's 80 workflows: exactly ONE finding
(`scheduled-marketplace-drift.yml:drift-check`), fixed in this PR, so the `-live` arm registered
in scripts/test-all.sh is green on merge.

POSTURE. `./` + `actions/checkout` stays canonical for jobs that already check out (53 steps);
`$/` is for checkout-free jobs (1 step). Both are accepted here.

Usage: python3 scripts/lint-workflow-local-action-checkout.py [<dir>]   (default .github/workflows)
Exit: 0 clean, 1 findings, 2 usage/parse
"""
import re
import sys
from pathlib import Path

import yaml

NAME = "lint-workflow-local-action-checkout"
CHECKOUT = re.compile(r"^actions/checkout(@|$)")
MIN_SAME_REPO_STEPS = 30
# The second surface needs its own floor: `actions_scanned` was printed and compared to nothing,
# so an actions tree that moved out of `<dir>/../actions` reach walked zero files and reported OK.
# 7 composites today; the floor only binds when the directory exists, so fixture trees with a
# deliberately empty actions dir (and the absent-dir case, which `references_actions_dir` owns)
# are unaffected.
MIN_ACTION_FILES = 1


def usage_error(msg: str) -> int:
    print(f"{NAME}: {msg}", file=sys.stderr)
    return 2


def load(path: Path):
    """Parse one YAML file; any failure is a usage/parse error naming the file."""
    try:
        return yaml.safe_load(path.read_text(encoding="utf8"))
    except (UnicodeDecodeError, OSError, RecursionError, yaml.YAMLError) as exc:
        raise ValueError(f"cannot parse {path}: {str(exc).splitlines()[0]}") from exc


def checkout_usable(checkout: dict, step: dict) -> bool:
    """A checkout serves a later step only if it is guaranteed to have RUN and SUCCEEDED.

    Four ways a checkout fails to populate the path the action lives at: `continue-on-error:
    true` (the job stays green with an empty workspace — the original defect one step earlier);
    `with: repository:` (a different repo's tree); `with: path:` (a workspace subdirectory, so
    `./…` still resolves to nothing); and `with: sparse-checkout:` whose cone excludes `.github`.
    Measured 2026-09-18: 0 of 144 checkouts in the tree carry any of them, so none was observed
    as a live escape — each was reasoned from the runner's behaviour and is covered by a
    synthesized suite row. This is fail-closed against a future edit, not a reclassification of
    anything shipping today.
    A checkout with no `if:` serves every later step; a conditional one only its twin.
    """
    if checkout.get("continue-on-error") is True:
        return False
    with_ = checkout.get("with")
    if isinstance(with_, dict):
        if "repository" in with_ or "path" in with_:
            return False  # checks out a different repo, or into a workspace subdirectory
        sparse = with_.get("sparse-checkout")
        if sparse is not None:
            patterns = sparse.split() if isinstance(sparse, str) else list(sparse or [])
            if not any(str(pat).lstrip("/").startswith(".github") for pat in patterns):
                return False  # a cone that excludes .github cannot materialise the action
    if "if" not in checkout:
        return True
    return str(checkout.get("if")) == str(step.get("if"))


def main(argv: list[str]) -> int:
    if len(argv) > 2:
        return usage_error(f"expected at most one path, got {len(argv) - 1}")
    root = Path(argv[1]) if len(argv) > 1 else Path(".github/workflows")
    if not root.is_dir():
        return usage_error(f"{root} is not a directory")
    actions_root = root.parent / "actions"

    findings: list[str] = []
    scanned = 0
    local_steps = 0
    self_steps = 0
    actions_scanned = 0
    references_actions_dir = False

    try:
        for wf in sorted(list(root.glob("*.yml")) + list(root.glob("*.yaml"))):
            doc = load(wf)
            if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
                return usage_error(f"{wf} has no `jobs` mapping — not a workflow?")
            scanned += 1
            for job_name, job in doc["jobs"].items():
                if not isinstance(job, dict):
                    return usage_error(f"{wf}: job {job_name!r} is not a mapping")
                if "uses" in job:
                    continue  # a reusable-workflow call: no steps, resolved from the repo ref
                steps = job.get("steps") or []
                if not isinstance(steps, list):
                    return usage_error(f"{wf}: job {job_name!r} `steps` is not a list")
                checkouts: list[dict] = []
                for idx, step in enumerate(steps):
                    if not isinstance(step, dict):
                        return usage_error(f"{wf}: job {job_name!r} step[{idx}] is not a mapping")
                    uses = step.get("uses")
                    if uses is None:
                        continue
                    if not isinstance(uses, str):
                        return usage_error(f"{wf}: job {job_name!r} step[{idx}] `uses` is not a string")
                    label = step.get("name") or f"step[{idx}]"
                    if CHECKOUT.match(uses):
                        checkouts.append(step)
                        continue
                    if uses.startswith("$/"):
                        self_steps += 1
                        if "@" in uses:
                            findings.append(
                                f"::error file={wf}::{wf.name}: job '{job_name}', step '{label}' uses "
                                f"'{uses}' — a self-repository reference must not carry an @ref suffix "
                                f"(GitHub rejects it at Set up job; actionlint 1.7.7 does not)"
                            )
                        continue
                    if uses.startswith("./"):
                        local_steps += 1
                        if uses.startswith("./.github/actions/"):
                            references_actions_dir = True
                        if not any(checkout_usable(c, step) for c in checkouts):
                            findings.append(
                                f"::error file={wf}::{wf.name}: job '{job_name}', step '{label}' uses "
                                f"'{uses}' with no preceding actions/checkout in this job — a ./ action "
                                f"resolves from the workspace, which this job never populates; add "
                                f"actions/checkout before it or reference it as $/{uses[2:]}"
                            )
                        continue
                    # owner/repo[/path]@ref and docker://… resolve at Set up job — ignored.

        # Second surface: composites must not nest `./` (it would resolve from the CALLER's workspace).
        if actions_root.is_dir():
            for action in sorted(actions_root.rglob("action.yml")) + sorted(actions_root.rglob("action.yaml")):
                actions_scanned += 1
                doc = load(action)
                if not isinstance(doc, dict):
                    return usage_error(f"{action} does not parse to a mapping — not an action?")
                runs = doc.get("runs")
                if not isinstance(runs, dict):
                    return usage_error(f"{action} has no `runs` mapping — not an action?")
                steps = runs.get("steps")
                if steps is None:
                    steps = []  # a docker/node action declares no steps; nothing to check
                elif not isinstance(steps, list):
                    return usage_error(f"{action}: `runs.steps` is not a list")
                for idx, step in enumerate(steps):
                    if not isinstance(step, dict):
                        return usage_error(f"{action}: step[{idx}] is not a mapping")
                    uses = step.get("uses")
                    if not isinstance(uses, str):
                        continue
                    rel = action.relative_to(actions_root.parent)
                    if uses.startswith("./"):
                        findings.append(
                            f"::error file={action}::{rel}: step[{idx}] uses '{uses}' inside a composite "
                            f"— a nested ./ resolves from the caller's workspace; use $/{uses[2:]}"
                        )
                    elif uses.startswith("$/") and "@" in uses:
                        findings.append(
                            f"::error file={action}::{rel}: step[{idx}] uses '{uses}' — a self-repository "
                            f"reference must not carry an @ref suffix (GitHub rejects it at Set up job; "
                            f"actionlint 1.7.7 does not)"
                        )
    except ValueError as exc:
        return usage_error(str(exc))

    if scanned == 0:
        return usage_error(f"scanned 0 workflows under {root} — wrong path?")
    if references_actions_dir and not actions_root.is_dir():
        return usage_error(
            f"{scanned} workflows reference ./.github/actions/… but {actions_root} is not a "
            f"directory — the composite surface would be scanned with zero files; wrong tree?"
        )
    if actions_root.is_dir() and actions_scanned < MIN_ACTION_FILES:
        return usage_error(
            f"only {actions_scanned} composite action file(s) under {actions_root}, below "
            f"MIN_ACTION_FILES={MIN_ACTION_FILES} — the second surface is scanning nothing; "
            f"has the actions tree moved?"
        )
    same_repo = local_steps + self_steps
    if same_repo < MIN_SAME_REPO_STEPS:
        return usage_error(
            f"only {same_repo} same-repo (./ or $/) steps across {scanned} workflows, below "
            f"MIN_SAME_REPO_STEPS={MIN_SAME_REPO_STEPS} — the guard is scanning nothing; wrong tree?"
        )

    if findings:
        for line in findings:
            print(line, file=sys.stderr)
        print(f"{NAME}: {len(findings)} violation(s) across {scanned} workflow(s)", file=sys.stderr)
        return 1

    print(
        f"{NAME}: OK — {scanned} workflows scanned, {local_steps} local-action steps, "
        f"{self_steps} self-repository steps, {actions_scanned} composite action file(s); "
        f"every local-action step is preceded by actions/checkout in its job"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
