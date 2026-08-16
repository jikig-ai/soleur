#!/usr/bin/env python3
"""A workflow that writes to the issue tracker must hold the scope to do it.

WHY THIS EXISTS. `registry-host-replace-dispatch.yml` shipped a step whose entire purpose was
"a delivery refusal must never be only a red run nobody owns". On its first real refusal
(run 31976455167, 2026-08-16) it emitted:

    GraphQL: Resource not accessible by integration (addComment)

because the workflow granted `actions: write` + `contents: read` and no `issues: write`. The call
ended in `|| true`, so the step reported SUCCESS while posting nothing. The artifact that exists
to make a refusal visible was itself invisible — a green mechanism doing nothing, which is the
failure class the PR that shipped it was written to remove.

WHAT MAKES THIS MECHANICAL RATHER THAN A REVIEW NOTE. The scope is declared in one place and
consumed in another, the failure appears only at the moment the workflow tries to report (i.e.
during an incident), and the natural `|| true` on a best-effort comment converts it into silence.
Nothing about reading the diff surfaces it.

TOKEN-AWARE, deliberately. A workflow authenticating with a GitHub App installation token or a
PAT carries its own grants and does NOT need the workflow-scoped permission. Flagging those would
be a false positive on the repo's preferred auth (hr-github-app-auth-not-pat), so a step is only
in scope when its `GH_TOKEN`/`GITHUB_TOKEN` resolves to `secrets.GITHUB_TOKEN` or `github.token`.
Measured against `origin/main`'s 75 workflows: this lint reports exactly TWO violations —
`inngest-watchdog-restart-dispatch.yml` and `registry-host-replace-dispatch.yml`, the latter being
the motivating defect of the PR that added this file. Both are fixed in that same PR, so the
`-live` arm registered in scripts/test-all.sh is green on merge.

KNOWN LIMITS, stated because a permissions gate that overstates its reach is worse than none.
This scans `.github/workflows/*.yml` only, so it does NOT see: a tracker write inside a script
the workflow invokes (7 such scripts have 8 workflow call sites today — all currently hold the
scope, by convention rather than by this gate), a composite action under `.github/actions/`, or
a reusable workflow whose CALLER bounds the token. The write-form patterns are single-line, and
`has_issue_write` is text-anywhere, so a grant on a DIFFERENT job than the writing one satisfies
it. Widening any of these is safe to do incrementally; narrowing the claim is not optional.

Exit 0 clean, 1 on a violation, 2 on a usage/parse error.
"""
import re
import sys
from pathlib import Path

# `gh issue <verb>` for verbs that WRITE. `gh issue view/list` are reads and need nothing.
WRITE_CALL = re.compile(r"\bgh\s+issue\s+(comment|create|edit|close|reopen|lock|unlock|pin|unpin|transfer|delete)\b")
# The REST equivalent, which bypasses the `gh issue` surface entirely.
#
# SPLIT, not one regex with two floating `[^\n]*` around the alternation. That shape was O(n^3)
# — measured 140s on a single 33KB line, a CI hang any PR could add — and it also silently
# required the method to appear BEFORE the path, so the ordering this repo actually writes
# (`gh api "repos/o/r/issues/$N/comments" -X POST`, see cla-evidence.yml) was never matched.
# Scanning each `gh api` LINE for the three components independently is linear and order-free.
GH_API_LINE = re.compile(r"^.*\bgh\s+api\b.*$", re.M)
MUTATING_METHOD = re.compile(r"--method\s+(POST|PATCH|PUT|DELETE)\b|-X\s*(POST|PATCH|PUT|DELETE)\b", re.I)


def has_api_issue_write(text: str) -> bool:
    """A mutating `gh api` call against the issues path, in any argument order."""
    return any(
        "issues" in line and MUTATING_METHOD.search(line) for line in GH_API_LINE.findall(text)
    )


GRAPHQL_WRITE = re.compile(r"\bgh\s+api\s+graphql\b[^\n]*(addComment|createIssue|updateIssue)")

WORKFLOW_TOKEN = re.compile(r"\$\{\{\s*(secrets\.GITHUB_TOKEN|github\.token)\s*\}\}")
APP_OR_PAT_TOKEN = re.compile(r"\$\{\{\s*(secrets\.(?!GITHUB_TOKEN)[A-Z0-9_]+|steps\.[A-Za-z0-9_-]+\.outputs\.token)\s*\}\}")


def has_pr_write(text: str) -> bool:
    """`pull-requests: write`, which legitimately covers a PR comment.

    THE REST PATH LIES ABOUT THE SCOPE. GitHub serves pull-request comments from
    `/repos/{o}/{r}/issues/{n}/comments` — the ISSUES path — but they are governed by
    `pull-requests: write`, not `issues: write`. A lint that reads the path and demands
    `issues: write` therefore false-positives on every PR-commenting workflow.

    Measured: the first draft of this lint flagged `pr-auto-close-scanner.yml`, which comments on
    PRs via that path and correctly declares `pull-requests: write`. Acting on that would have
    widened a workflow's token scope to fix a defect it did not have — the precise "verify the
    finding before propagating it" failure this repo keeps paying for.
    """
    return re.search(r"^\s*pull-requests:\s*write\s*(#.*)?$", text, re.M) is not None


def has_issue_write(text: str) -> bool:
    """`issues: write` anywhere — workflow-level OR job-level.

    Deliberately not a YAML-structural check. Job-level `permissions:` blocks are common here,
    and a per-job grant is as valid as a top-level one; requiring the top-level form would push
    authors to widen scope, which is the wrong direction for a permissions lint.
    """
    return re.search(r"^\s*issues:\s*write\s*(#.*)?$", text, re.M) is not None


def uses_workflow_token(text: str) -> bool:
    """True when the file authenticates with the workflow-scoped token at least once.

    If a file ONLY ever uses an App/PAT token, the workflow permission is irrelevant to it. If it
    uses both, the workflow token may be the one reaching the write, so it stays in scope — the
    conservative direction for a security-adjacent lint.
    """
    if WORKFLOW_TOKEN.search(text):
        return True
    # No explicit GH_TOKEN at all: `gh` falls back to the workflow token inside Actions.
    return not APP_OR_PAT_TOKEN.search(text)


def main(argv: list[str]) -> int:
    if len(argv) > 2:
        print(f"lint-workflow-issue-write-scope: expected at most one path, got {len(argv) - 1}", file=sys.stderr)
        return 2
    root = Path(argv[1]) if len(argv) > 1 else Path(".github/workflows")
    if not root.is_dir():
        print(f"lint-workflow-issue-write-scope: {root} is not a directory", file=sys.stderr)
        return 2

    violations = []
    scanned = 0
    for wf in sorted(list(root.glob("*.yml")) + list(root.glob("*.yaml"))):
        # A decode failure is a PARSE error (rc 2), not a violation (rc 1). Unguarded, it raised
        # UnicodeDecodeError mid-loop: the traceback exited 1 — indistinguishable from a real
        # finding — AND aborted before the violations accumulated so far were ever printed, so a
        # genuine offender sorting earlier was silently swallowed.
        try:
            text = wf.read_text(encoding="utf8")
        except (UnicodeDecodeError, OSError) as exc:
            print(f"lint-workflow-issue-write-scope: cannot read {wf}: {exc}", file=sys.stderr)
            return 2
        scanned += 1
        writes = []
        if WRITE_CALL.search(text):
            writes.append("gh issue <write-verb>")
        if has_api_issue_write(text):
            writes.append("gh api (issues, mutating method)")
        if GRAPHQL_WRITE.search(text):
            writes.append("gh api graphql (addComment/createIssue/updateIssue)")
        if not writes:
            continue
        if not uses_workflow_token(text):
            continue
        if has_issue_write(text):
            continue
        # A raw `/issues/{n}/` API call may be addressing a PULL REQUEST, which
        # `pull-requests: write` covers. `gh issue <verb>` cannot be — it only addresses issues —
        # so that form still requires `issues: write` even when pull-requests is granted.
        # Expressed as "no `gh issue` verb present", NOT as equality against each singleton list.
        # The equality form silently failed on a file using BOTH API forms: `writes` is then a
        # two-element list matching neither singleton, so `api_only` went False and a correct
        # PR-commenting workflow declaring `pull-requests: write` was FLAGGED. GraphQL
        # `addComment` takes a subjectId that is legitimately a PR, so both forms are PR-capable
        # and both must be excused — and a false positive here is a recommendation to widen a
        # token's scope, which is the one outcome this lint must never produce.
        api_only = "gh issue <write-verb>" not in writes
        if api_only and has_pr_write(text):
            continue
        violations.append((wf, writes))

    if scanned == 0:
        print("lint-workflow-issue-write-scope: scanned 0 workflows — wrong path?", file=sys.stderr)
        return 2

    if violations:
        for wf, writes in violations:
            print(
                f"::error file={wf}::{wf.name} writes to the issue tracker "
                f"({', '.join(writes)}) using the workflow token, but declares no `issues: write`. "
                f"The call will fail at runtime with "
                f"'Resource not accessible by integration' — and if it is followed by `|| true` "
                f"the step will report success while posting nothing. Add `issues: write` to the "
                f"workflow's or the job's `permissions:` block.",
                file=sys.stderr,
            )
        print(f"lint-workflow-issue-write-scope: {len(violations)} violation(s) across {scanned} workflow(s)", file=sys.stderr)
        return 1

    print(f"lint-workflow-issue-write-scope: OK — {scanned} workflows scanned, every tracker-writing one holds `issues: write`")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
