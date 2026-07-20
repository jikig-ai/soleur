# Learning: CodeQL "default setup" enabled alongside the committed advanced `codeql.yml` silently rejects every SARIF upload — masking real critical alerts repo-wide

category: best-practices
module: .github/workflows, ci, codeql

## Problem

During the 2026-06-30 ship of the `fix-constraints` recovery dispatcher (#5791 / held PR #5804),
the required **CodeQL** check failed. The failure was NOT a code finding — the analysis ran, but the
final "Waiting for processing to finish" step reported:

```
Analysis upload status is failed.
##[error]Code Scanning could not process the submitted SARIF file:
CodeQL analyses from advanced configurations cannot be processed when the default setup is enabled
```

This is a repo-level configuration conflict: GitHub's UI **"Default setup"** for code scanning was
enabled at the same time as the repo's committed **advanced** workflow (`.github/workflows/codeql.yml`).
When both are on, GitHub rejects the advanced workflow's SARIF upload — so the CodeQL check fails at
the *upload* step on **every** run, repo-wide. `main`'s own CodeQL was red for the same reason, and
the failure was intermittent per-run (a race on which upload GitHub accepted first), which initially
read like a flake.

The dangerous part: because the SARIF upload was being rejected, the analysis's **actual findings
were never stored** — so the check looked like a generic infra failure rather than "there are real
alerts here." A green-because-the-uploader-is-broken (or red-for-the-wrong-reason) CodeQL is worse
than an honestly-red one: it hides the security signal.

## Solution

Because the repo commits an advanced `codeql.yml` (the version-controlled, intended config), the
correct resolution is to **disable Default setup** and keep the advanced workflow as canonical:

```bash
gh api -X PATCH repos/<owner>/<repo>/code-scanning/default-setup -f state=not-configured
# verify:
gh api repos/<owner>/<repo>/code-scanning/default-setup --jq '.state'   # -> not-configured
```

Disabling Default setup (a) unblocked the repo-wide CodeQL failure (main + all PRs) and (b) let the
advanced workflow's SARIF upload succeed — which immediately surfaced **3 real critical
`actions/untrusted-checkout-toctou` alerts** that had been masked. Those alerts drove the security
redesign (#5814 → the two-stage split in #5816, ADR-074).

Do the opposite fix (remove the advanced `codeql.yml`, keep Default setup) only if Default setup is
the *intended* config — but a committed advanced workflow is strong evidence it is not.

## Key Insight

A failing CodeQL required check that errors at the **SARIF-upload / "processing"** step — not at a
query — is a **configuration** problem (default-setup-vs-advanced-workflow conflict), not a flake and
not (yet) a code finding. It is a repo-security-posture change to resolve (operator-authorized). And
critically: while the upload is broken, **CodeQL cannot report the findings it did compute**, so a
real critical alert can hide behind the generic upload error. When you see
`analyses from advanced configurations cannot be processed when the default setup is enabled`, fix the
config first, then re-read the alerts — the redesign-forcing finding may be waiting underneath.

## Tags

category: best-practices
module: codeql, github-actions, ci
related: [[2026-07-01-two-stage-privileged-workflow-split-and-its-review-traps]]
