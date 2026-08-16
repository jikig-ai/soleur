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
Measured while writing this: a naive scan reported 5 offenders, of which 4 were false —
2 already held the scope and 2 make no tracker write at all. Only `inngest-watchdog-restart-dispatch`
was real.

Exit 0 clean, 1 on a violation, 2 on a usage/parse error.
"""
import re
import sys
from pathlib import Path

# `gh issue <verb>` for verbs that WRITE. `gh issue view/list` are reads and need nothing.
WRITE_CALL = re.compile(r"\bgh\s+issue\s+(comment|create|edit|close|reopen|lock|unlock|pin|unpin|transfer|delete)\b")
# The REST/GraphQL equivalents, which bypass the `gh issue` surface entirely.
API_WRITE = re.compile(r"\bgh\s+api\b[^\n]*(--method\s+(POST|PATCH|PUT|DELETE)|-X\s*(POST|PATCH|PUT|DELETE))[^\n]*\bissues\b")
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
    root = Path(argv[1]) if len(argv) > 1 else Path(".github/workflows")
    if not root.is_dir():
        print(f"lint-workflow-issue-write-scope: {root} is not a directory", file=sys.stderr)
        return 2

    violations = []
    scanned = 0
    for wf in sorted(root.glob("*.yml")) + sorted(root.glob("*.yaml")):
        text = wf.read_text(encoding="utf8")
        scanned += 1
        writes = []
        if WRITE_CALL.search(text):
            writes.append("gh issue <write-verb>")
        if API_WRITE.search(text):
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
        api_only = writes == ["gh api (issues, mutating method)"] or writes == [
            "gh api graphql (addComment/createIssue/updateIssue)"
        ]
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
