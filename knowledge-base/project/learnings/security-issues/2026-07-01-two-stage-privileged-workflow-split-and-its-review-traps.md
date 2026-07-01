---
category: security-issues
module: github-actions / constraint-scaffold
tags: [github-actions, workflow_run, untrusted-checkout-toctou, pwn-request, git-data-api, code-review]
issue: 5814
pr: 5816
adr: ADR-074
date: 2026-07-01
---

# Learning: the two-stage `pull_request`→`workflow_run` privileged split, and the review traps it hides

## Problem

A recovery dispatcher (`fix-constraints.yml`, #5791) that runs an agent to auto-fix a tripped CI gate
tripped **3 critical CodeQL `actions/untrusted-checkout-toctou` alerts**: an `issue_comment`-triggered
job held `ANTHROPIC_API_KEY` + `contents: write`, checked out PR-head code, and executed it. Targeted
hardening (SHA-pin, `--ignore-scripts`, base-branch gate) does not clear the finding — CodeQL keys on
the *structural* sink (a privileged trigger executing untrusted PR-derived code with secrets/write).

## Solution — the canonical "pwn-request" split (ADR-074)

Split the workflow so the **write-capable stage never co-locates with untrusted code execution**:

- **Stage A — `pull_request`, `contents: read` only, NO write token.** Runs the gate + agent over
  PR-head code (the *expected, safe* thing — `pull_request` is CodeQL's designated untrusted context),
  and uploads the fix as a **patch artifact** (full post-image file contents + per-file sha256 + meta.json).
- **Stage B — `workflow_run`, privileged (`contents: write`).** GitHub always runs Stage B's file from
  the **default branch**, so its logic is trusted. It validates the artifact and builds the commit via
  the **Git Data API** (blob→tree→commit→ref) — **no `actions/checkout` of head, no `git apply`, no
  `bun install`, no PR-script execution.** The untrusted-checkout sink is *structurally absent* (no
  checkout step to flag), not merely downscoped.

## Key insight — the non-obvious traps (each cost a review finding or a plan correction)

1. **`pull_request` runs the FORK'S OWN Stage A definition** (unlike `pull_request_target`, which runs
   the base's). So the artifact — contents AND meta.json — is **100% attacker-controlled**. "Forks get
   no key → safe artifact" is WRONG: a fork rewrites Stage A to skip the agent and upload anything while
   keeping `name:` to fire Stage B. The real defense is Stage B's **`isCrossRepository == false` +
   exactly-one-open-PR gate before any write**, with routing identity sourced from the trusted
   `workflow_run.head_sha` (validated `^[0-9a-f]{40}$`), never the artifact.
2. **`base_tree` is MANDATORY** on the tree create — omit it and the bot commit deletes every other repo
   file. Blobs must be `base64` of RAW bytes (CRLF/BOM survive) + sha256-verified against meta.json.
3. **`workflow_run: workflows: [X]` matches Stage A's `name:` field, NOT its filename.** A rename drift
   makes Stage B silently never trigger (no error). Assert `Stage A name: == Stage B workflows:` in a test.
4. **"No terminal state is silent" needs a give-up marker.** Stage A produces a recovery patch only when
   it ships an in-scope fix, so give-up cases (no key / no edit / still-red / out-of-scope) leave Stage B
   with nothing to comment on → the founder is silently deadlocked (the exact failure the feature exists
   to prevent). Fix: Stage A emits a *second* artifact `fix-constraints-giveup-<pr>` on a red gate with no
   patch; Stage B comments off it (read-only, event-sourced identity). No marker on a green gate (no spam).
5. **`emit() { echo "detail=$2" >> "$GITHUB_OUTPUT"; }` is an output-injection sink** when `$2` embeds
   attacker artifact data (a `jq -r`-decoded newline injects extra `state=`/`pr_url=` lines → forged ✅
   comment). Sanitize (strip `\n`/control) at the single `emit()` choke point.
6. **`git diff` ignores untracked files** — a fix that CREATES a new file is silently dropped or shipped
   partial. Use `git status --porcelain` for the changed-check and `git add -A && git diff --cached
   --name-only -z` for enumeration (so the allowlist still sees out-of-scope edits to abort on).
7. **Dogfood copies escape the emit-test's guards.** The emit test only inspects freshly-*emitted* tenant
   fixtures, never the committed repo-root dogfood workflows. A parity test must cover the dogfood too —
   Stage B gets strict body-parity (zero intentional divergence); Stage A gets invariant assertions
   (name-coupling, read-only, no checkout/apply) because it diverges (dogfood-only api-spend steps).
8. **A tenant template must not `uses:` a repo-local action the scaffold doesn't emit** (`./.github/
   actions/anthropic-preflight`) — tenant recovery is dead-on-arrival. Inline a self-contained check.

## Prevention

- For any privileged-trigger workflow, spawn `security-sentinel` **and** `user-impact-reviewer` with the
  `untrusted-checkout-toctou` / fork-runs-its-own-`pull_request`-definition class **named explicitly** in
  the prompt — this is the class LLM review missed on #5804; naming it is what surfaces traps 1/4/5.
- Mutation-test a **body-parity** guard with a NON-comment line (a `strip_body` guard intentionally
  ignores `#`-comments; a comment-line mutation passes vacuously — my first mutation test did exactly this).

## Session Errors

- **Edit string-mismatch after a `sed` rewrote the target in-place** (Stage A template header:
  `apps/web-platform`→`__TARGET_DIR__`) and an ADR paraphrase (`exact-match-command` vs `exact-command`).
  Recovery: re-Read then Edit. **Prevention:** after a bulk `sed`/linter touches a file, re-Read the exact
  region before constructing an Edit `old_string` from memory. *(one-off)*
- **Vacuous parity mutation test** — injected a `#`-comment to verify the new Stage B body-parity check,
  but `strip_body` strips comments, so it passed and looked non-catching. Recovery: re-mutated with a real
  code line (`MAX_FILES` value) → check failed correctly. **Prevention:** see Prevention above. *(one-off, self-caught)*
- **`gh api --jq` does not forward `--arg`** + a literal backtick in a single-quoted `sed` tripped
  shellcheck SC2016. Recovery: pipe to a standalone `jq --arg`; use a `bt='`'` var. **Prevention:** already
  covered by [[2026-04-15-gh-jq-does-not-forward-arg-to-jq]]. *(recurring, pre-covered)*
- **Advisory hook denies** (`hr-in-github-actions-run-blocks-never-use`, `hr-never-write-to-claude-code-memory-claude`)
  fired as telemetry on workflow Writes; the `command_snippet`s were the hook's canonical dangerous-input
  examples, not this PR's code (which env/argv-passes every event input). **Prevention:** none — expected
  advisory reminder on any workflow write; not a violation. *(one-off / telemetry)*
