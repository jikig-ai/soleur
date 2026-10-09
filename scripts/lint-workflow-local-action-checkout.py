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

THIRD SURFACE (ADR-280). A job that sends a credential through `scripts/lib/bearer-curl.sh` — by
`uses:` of a composite whose steps source it (the set is DERIVED from `.github/actions/**/action.yml`
by the basename `bearer-curl.sh`, and always includes `notify-ops-email` and `anthropic-preflight`), or by a
`run:` step that names the library — needs a checkout that actually materialises `scripts/lib/`: usable per
`checkout_usable()` (so no `path:`, no foreign `repository:`), AND, when it carries a `sparse-checkout:`
cone, one that names `scripts`, `scripts/**`, `scripts/lib` or a path under `scripts/lib/` (a string prefix such
as `scripts-old`, a sibling such as `scripts/ci`, or a later negation of scripts does not count). The library is
sourced from the job's own workspace, so a job without it cannot send, and there is no argv fallback. The
workflow must also not be triggered by `pull_request_target` (it runs with secrets against a ref the author
controls), and a consumer job on a `workflow_run`/`issue_comment`/`pull_request_review*`/`issues` trigger may
only check out the default branch's own ref (on `pull_request_review*` even the implicit and `github.sha` refs are the PR's merge
ref, so only an explicit default-branch spelling counts): any other `ref:` (a head sha, `refs/pull/N/merge`, a step output)
fails closed. Measured when this was written: the 26 composite call steps (23 `notify-ops-email`, 3
`anthropic-preflight`) all follow a checkout whose ref is the default one, except `fix-constraints-stage-a`
(checks out the PR head under plain `pull_request`, so it resolves the composite and the library from the same
tree); `cla`, `cla-evidence` and `dev-ledger-reconcile` are the `pull_request_target` workflows and call neither
composite. This makes those properties checked.

NAMED NON-PROPERTIES (so the claim is not overstated). `if:` is compared as a string, never
evaluated — a `./` step whose `if:` legitimately narrows its checkout's is a loud false positive
with an obvious fix. Whether the checkout ref is pinned (`@v4` vs `@<sha>`) is a separate property.
Job-level `uses:` (a reusable-workflow call) is not a step and is skipped. A job that checks out
via `run: git clone` is not recognised as checked out (0 such jobs today). For the library surface: a composite that only calls
another library composite is not derived; and a reusable workflow's callers' triggers are invisible to the
`pull_request_target` and untrusted-ref checks (`workflow_call` is not a trigger the lint can judge). A `run: gh pr
checkout` after the checkout is not seen either. A script that sources the library and is CALLED by a step IS detected
(next paragraph), but only by name: a `run:` that reaches the script through a variable that never spells its directory
and its basename together, or through a command substitution, is not.

SCRIPT CONSUMERS (S4, Guard 3). A tracked `.sh` file that itself names `bearer-curl.sh` (anywhere in its text, comments
included: fail closed) outside `scripts/lib/` is a SCRIPT CONSUMER, and a `run:` step that names one is a library
consumer exactly like a step that names the library: same checkout, sparse-cone, `pull_request_target` and untrusted-ref
rules, same messages (each finding gains a trailing `[script consumer: <path>]`). The set is DERIVED from the tree, never
listed: `git ls-files` (cached + untracked-not-ignored) when the repository root holds a `.git`, otherwise a walk of that
root (a fixture tree or a `git ls-files | tar` copy). The repository root is `<dir>/../..` when `<dir>` is
`.github/workflows`, else `<dir>/..`. A `run:` names a script by its repo-relative path (a path boundary on both sides,
so `./.github/actions/x/track.sh` and `$GITHUB_WORKSPACE/.github/actions/x/track.sh` count), or by its directory and its
basename together (`cd .github/actions/x && bash track.sh`); a composite's own `run:` also names a script that sits in the
composite's directory by basename (`${{ github.action_path }}/track.sh`). The derived-set size is printed on its own
line (`script-consumers: N derived (...), M step(s) run one`) and is INFORMATIONAL here: an empty set is a legitimate
tree (before the S4 conversions land there is none outside `scripts/lib/` that a workflow runs), so the lint never fails
on it. The set-size FLOOR lives where the set is known not to be empty: the suite's fixture rows assert the exact count
for a tree built with known consumers (so a derivation emptied by a mutation turns them red), and the argv-bearer
battery asserts the real tree's count once the conversions have landed.

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
import os
import re
import subprocess
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
# Third surface (ADR-280): the steps that send a credential through the shared library. The population floor
# lives in the suite's live row, where the real tree is scanned, not here: a fixture tree legitimately has few.
LIB_PATH = "scripts/lib/bearer-curl.sh"
# Detection needle: the basename, so `source "$GITHUB_WORKSPACE/$LIBDIR/bearer-curl.sh"` is still recognised.
LIB_NEEDLE = "bearer-curl.sh"
LIB_COMPOSITE_DEFAULT = ("notify-ops-email", "anthropic-preflight")
UNTRUSTED_REF_TRIGGERS = {"workflow_run", "issue_comment", "pull_request_review", "pull_request_review_comment", "issues"}
# For these two the default `GITHUB_SHA`/`github.ref` is the PR's MERGE ref, i.e. the PR tree: only an explicit default-branch
# spelling is acceptable.
PR_TREE_TRIGGERS = {"pull_request_review", "pull_request_review_comment"}
DEFAULT_BRANCH_ONLY = re.compile(r"^(\$\{\{\s*github\.event\.repository\.default_branch\s*\}\}|main|master)$")
# Under those triggers the only checkout ref the library may be sourced from is the default branch's own: any other
# `ref:` (a head sha, `refs/pull/N/merge`, a step output, an input) can name a tree the author controls. Fail closed.
DEFAULT_REF_OK = re.compile(
    r"^(\$\{\{\s*(github\.sha|github\.ref|github\.event\.repository\.default_branch)\s*\}\}|main|master)$"
)


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
            if not cone_names_github(cone_patterns(sparse)):
                return False  # a cone that excludes .github cannot materialise the action
    if "if" not in checkout:
        return True
    return str(checkout.get("if")) == str(step.get("if"))


def cone_patterns(sparse) -> list:
    """The cone's patterns as clean path segments: split on whitespace, `/`-anchoring and a trailing `/` dropped."""
    raw = sparse.split() if isinstance(sparse, str) else list(sparse or [])
    return [str(p).strip().lstrip("/").rstrip("/") for p in raw]


def cone_names_github(patterns: list) -> bool:
    """A cone materialises the composites iff a pattern IS `.github`, `.github/**`, `.github/actions` (or `/**`) or lies
    under `.github/actions/`. A string prefix (`.github-old`) or `.github/workflows` alone does not."""
    return any(p in (".github", ".github/**", ".github/actions", ".github/actions/**") or p.startswith(".github/actions/") for p in patterns)


def cone_names_scripts(patterns: list) -> bool:
    """A cone materialises scripts/lib/ iff a pattern IS `scripts` / `scripts/**` / `scripts/lib` or lies under
    `scripts/lib/`. A string prefix (`scripts-old`) or a sibling directory (`scripts/ci`, `scripts/lib-old`) does
    not, and a negation that mentions scripts (`!scripts/lib`) can take it away again, so it refuses."""
    for p in patterns:
        neg = p[1:].lstrip("/") if p.startswith("!") else ""
        if neg == "scripts" or neg.startswith("scripts/"):
            return False
    return any(p in ("scripts", "scripts/**", "scripts/lib", "scripts/lib/**") or p.startswith("scripts/lib/") for p in patterns)


def checkout_has_lib(checkout: dict, step: dict) -> bool:
    """A checkout that serves `step` AND materialises scripts/lib/ (a sparse cone must name `scripts`)."""
    if not checkout_usable(checkout, step):
        return False
    with_ = checkout.get("with")
    if isinstance(with_, dict):
        sparse = with_.get("sparse-checkout")
        if sparse is not None and not cone_names_scripts(cone_patterns(sparse)):
            return False
    return True


def checkout_ref_untrusted(checkout: dict, strict: bool = False) -> bool:
    """True when the checkout names a ref other than the default branch's own. `strict` (the PR-review triggers, where
    the implicit and `github.sha` refs are the PR's merge ref) accepts only an explicit default-branch spelling."""
    with_ = checkout.get("with")
    ref = with_.get("ref") if isinstance(with_, dict) and "ref" in with_ else None
    if ref is None:
        return strict
    ok = DEFAULT_BRANCH_ONLY if strict else DEFAULT_REF_OK
    return not (isinstance(ref, str) and ok.match(ref.strip()))


def lib_composites(actions_root: Path) -> set:
    """Composites whose steps source the library: the always-included pair plus every action.yml that names it.
    A composite is keyed by its path under the actions root (`a` or `group/a`). A file that cannot be read, or whose
    `runs` is not a mapping, is skipped here: the second surface reports it by name."""
    names = set(LIB_COMPOSITE_DEFAULT)
    if actions_root.is_dir():
        for action in list(actions_root.rglob("action.yml")) + list(actions_root.rglob("action.yaml")):
            try:
                doc = yaml.safe_load(action.read_text(encoding="utf8"))
            except (OSError, UnicodeDecodeError, RecursionError, yaml.YAMLError):
                continue
            runs = doc.get("runs") if isinstance(doc, dict) else None
            steps = runs.get("steps") if isinstance(runs, dict) else None
            if isinstance(steps, list) and any(
                isinstance(st, dict) and isinstance(st.get("run"), str) and LIB_NEEDLE in st["run"] for st in steps
            ):
                names.add(action.parent.relative_to(actions_root).as_posix())
    return names


def repo_root_of(root: Path) -> Path:
    """The repository root the script set is derived from: `<dir>/../..` for `.github/workflows`, else `<dir>/..`
    (a fixture tree keeps its scripts next to its `workflows` and `actions` directories)."""
    r = root.resolve()
    return r.parent.parent if r.parent.name == ".github" else r.parent


def tracked_shell_files(repo: Path):
    """(files, how): repo-relative posix paths of every `.sh` file. `git ls-files` when the root is a git checkout,
    else a walk (a tree copied out with `git ls-files | tar` has no `.git`; neither does a fixture)."""
    if (repo / ".git").exists():
        try:
            out = subprocess.run(
                ["git", "-C", str(repo), "ls-files", "-z", "--cached", "--others", "--exclude-standard", "--", "*.sh"],
                capture_output=True, check=True, timeout=60,
            ).stdout
            return sorted({f for f in out.decode("utf8", "replace").split("\0") if f}), "git ls-files"
        except (OSError, subprocess.SubprocessError):
            pass  # fall through to the walk: a failed derivation must not become an empty set
    found = []
    for dirpath, dirnames, filenames in os.walk(repo):
        dirnames[:] = [d for d in dirnames if d not in (".git", "node_modules")]
        for fn in filenames:
            if fn.endswith(".sh"):
                found.append((Path(dirpath) / fn).relative_to(repo).as_posix())
    return sorted(found), "tree walk"


def lib_scripts(repo: Path):
    """The script consumers: tracked `.sh` files OUTSIDE `scripts/lib/` whose text names the library."""
    files, how = tracked_shell_files(repo)
    found = []
    for rel in files:
        if rel.startswith("scripts/lib/"):
            continue
        f = repo / rel
        try:
            if f.is_file() and LIB_NEEDLE in f.read_bytes().decode("utf8", "replace"):
                found.append(rel)
        except OSError:
            continue
    return found, how


def _bounded(path: str) -> "re.Pattern":
    """`path` as a whole path: not glued to a longer name on the left (a `/` or `.` before it is fine: `./x`,
    `$WS/x`), not followed by a name character on the right."""
    return re.compile(r"(?<![A-Za-z0-9_-])" + re.escape(path) + r"(?![A-Za-z0-9_.-])")


def run_names_script(run: str, scripts: list, action_dir: str = "") -> str:
    """The first script consumer a `run:` text names: by repo-relative path, by directory plus basename together, or
    (inside a composite, whose `action_dir` is its repo-relative directory) by basename of a script in that directory."""
    for rel in scripts:
        if _bounded(rel).search(run):
            return rel
        d, _, base = rel.rpartition("/")
        if d and _bounded(d).search(run) and _bounded(base).search(run):
            return rel
        if action_dir and d == action_dir and _bounded(base).search(run):
            return rel
    return ""


def lib_composites(actions_root: Path, repo: Path, scripts: list = ()) -> set:
    """Composites whose steps source the library: the always-included pair plus every action.yml that names it, or
    that runs a script consumer. A composite is keyed by its path under the actions root (`a` or `group/a`). A file that
    cannot be read, or whose `runs` is not a mapping, is skipped here: the second surface reports it by name."""
    names = set(LIB_COMPOSITE_DEFAULT)
    if actions_root.is_dir():
        for action in list(actions_root.rglob("action.yml")) + list(actions_root.rglob("action.yaml")):
            try:
                doc = yaml.safe_load(action.read_text(encoding="utf8"))
            except (OSError, UnicodeDecodeError, RecursionError, yaml.YAMLError):
                continue
            runs = doc.get("runs") if isinstance(doc, dict) else None
            steps = runs.get("steps") if isinstance(runs, dict) else None
            if not isinstance(steps, list):
                continue
            key = action.parent.relative_to(actions_root).as_posix()
            try:
                action_dir = action.parent.resolve().relative_to(repo.resolve()).as_posix()
            except ValueError:
                action_dir = ""  # the actions tree lies outside the repository root: no directory to match against
            for st in steps:
                run = st.get("run") if isinstance(st, dict) else None
                if isinstance(run, str) and (LIB_NEEDLE in run or run_names_script(run, list(scripts), action_dir)):
                    names.add(key)
                    break
    return names


def consumes_lib(step: dict, composites: set, scripts: list = ()) -> str:
    """"" when the step does not consume the library; else a label: "lib" (the composite, or a `run:` naming the
    library) or the repo-relative path of the script consumer the `run:` names."""
    uses = step.get("uses")
    if isinstance(uses, str):
        m = re.match(r"^(\./|\$/)\.github/actions/([A-Za-z0-9._/-]+?)/?$", uses)
        if m and m.group(2) in composites:
            return "lib"
    run = step.get("run")
    if isinstance(run, str):
        if LIB_NEEDLE in run:
            return "lib"
        return run_names_script(run, list(scripts))
    return ""


def triggers(doc: dict) -> set:
    """The workflow's trigger names. PyYAML parses a bare `on:` key as boolean True."""
    on = doc.get("on", doc.get(True))
    if isinstance(on, str):
        return {on}
    if isinstance(on, list):
        return {str(t) for t in on}
    if isinstance(on, dict):
        return {str(t) for t in on}
    return set()


def main(argv: list[str]) -> int:
    if len(argv) > 2:
        return usage_error(f"expected at most one path, got {len(argv) - 1}")
    root = Path(argv[1]) if len(argv) > 1 else Path(".github/workflows")
    if not root.is_dir():
        return usage_error(f"{root} is not a directory")
    actions_root = root.parent / "actions"
    repo = repo_root_of(root)
    scripts, scripts_how = lib_scripts(repo)
    composites = lib_composites(actions_root, repo, scripts)

    findings: list[str] = []
    scanned = 0
    local_steps = 0
    self_steps = 0
    actions_scanned = 0
    lib_steps = 0
    script_steps = 0
    references_actions_dir = False

    try:
        for wf in sorted(list(root.glob("*.yml")) + list(root.glob("*.yaml"))):
            doc = load(wf)
            if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
                return usage_error(f"{wf} has no `jobs` mapping — not a workflow?")
            scanned += 1
            wf_triggers = triggers(doc)
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
                    consumer = consumes_lib(step, composites, scripts)
                    if consumer:
                        lib_steps += 1
                        via = ""
                        if consumer != "lib":
                            script_steps += 1
                            via = f" [script consumer: {consumer}]"
                        lib_label = step.get("name") or f"step[{idx}]"
                        if not any(checkout_has_lib(c, step) for c in checkouts):
                            findings.append(
                                f"::error file={wf}::{wf.name}: job '{job_name}', step '{lib_label}' sends a "
                                f"credential through {LIB_PATH} but no earlier usable actions/checkout in this "
                                f"job materialises scripts/lib/ (no path:, no foreign repository:, and a "
                                f"sparse-checkout cone must name scripts) — the library is sourced from the "
                                f"job's own workspace and there is no argv fallback{via}"
                            )
                        if wf_triggers & UNTRUSTED_REF_TRIGGERS and any(
                            checkout_ref_untrusted(c, bool(wf_triggers & PR_TREE_TRIGGERS)) for c in checkouts if checkout_usable(c, step)
                        ):
                            findings.append(
                                f"::error file={wf}::{wf.name}: job '{job_name}', step '{lib_label}' sends a "
                                f"credential through {LIB_PATH} in a job triggered by {sorted(wf_triggers & UNTRUSTED_REF_TRIGGERS)} "
                                f"that checks out a ref other than the default branch's own (a head sha, refs/pull/N/merge, a step output) — "
                                f"the library would be sourced from a tree the author controls{via}"
                            )
                        if "pull_request_target" in wf_triggers:
                            findings.append(
                                f"::error file={wf}::{wf.name}: job '{job_name}', step '{lib_label}' sends a "
                                f"credential through {LIB_PATH} in a workflow triggered by pull_request_target "
                                f"— that trigger runs with secrets against a ref the author controls{via}"
                            )
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

    # Informational, never a gate (see SCRIPT CONSUMERS): the size of the derived set and how many steps run one.
    script_info = (
        f"{NAME}: script-consumers: {len(scripts)} derived ({scripts_how}), {script_steps} step(s) run one"
    )
    if findings:
        for line in findings:
            print(line, file=sys.stderr)
        print(f"{NAME}: {len(findings)} violation(s) across {scanned} workflow(s)", file=sys.stderr)
        print(script_info)
        return 1

    print(
        f"{NAME}: OK — {scanned} workflows scanned, {local_steps} local-action steps, "
        f"{self_steps} self-repository steps, {actions_scanned} composite action file(s); "
        f"every local-action step is preceded by actions/checkout in its job; "
        f"{lib_steps} library-consuming step(s) each have a checkout that materialises scripts/lib/"
    )
    print(script_info)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
