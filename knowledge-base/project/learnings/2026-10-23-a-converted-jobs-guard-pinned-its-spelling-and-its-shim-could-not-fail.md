# Learning: converting two CI jobs to a template's shape — the guard pinned spelling, the shim could not fail

## Problem

PR #10936 converted the two orphan-sweep jobs in `scheduled-terraform-drift.yml` from the loader-exported (read/write) Hetzner token to the read-only token, in the shape of `sole-copy-protection-check`, and added a failure email. The first guard (suite rows R7/R8/R9) was green at 211/211 and still let a third lister with another name, a workflow-level `env:`, a wrapper action, a `continue-on-error` on the sweep step, an email placed before the sweep, and a dropped `curl -f` through. Nine review seats found no P1 and ten P2s; every P2 was in the guard, the failure paths, or prose that claimed more than the job could reach.

## Solution

- Workflow defects fixed inline: the rung-2 orphan filer gate `always() && orphans != '0'` fired when the sweep exited before publishing `orphans` (an unset output is `''`, and `'' != '0'`); the failure-email de-duplication keyed on `steps.X.outcome != 'success'`, but the notify action exits 0 with `sent=false` when Resend rejects, so the finding could vanish; job `timeout-minutes` (10) was below the sum of the step bounds, and a job-level cancel makes `failure()` false; the rung-2 requests had no `--max-time`.
- The guard was rebuilt around the property ("the read/write credential cannot reach a Hetzner lister"): workflow-level env, the EXACT loader/environment population, listers outside the suffix, a closed job-key shape, an allowed-actions set, a closed set of `doppler` calls with project flags, the install body compared byte for byte with the template job's, bounds on every step, and email last / exactly `failure()` / keyed.
- The behavioural shims were made unable to pass over a broken script: the `curl` shim honours `-f`, records stdin, and the clean case requires `--max-time` and the token on EVERY request; the `doppler` shim refuses any argv but the reviewed one. Each guard fix was then proven by mutating the REAL workflow and watching the suite redden.

## Key Insight

A guard written to match two jobs' current text passes over every edit that keeps the text and breaks the property; derive the population from behaviour and close the shape. A test shim that ignores argv and stdin cannot fail on the arguments it was meant to pin. And `outcome == 'success'` is not "the email was sent" when the action swallows its own failure. Prove each new guard by mutating the shipped file, not only a fixture.

## Session Errors

1. **First gate bash call exceeded the tool timeout** — Recovery: ran in the background — Prevention: run `cleanup-merged` and other slow gates with `run_in_background`.
2. **`pgrep -f` blocked by the self-match hook** — Recovery: dropped the check — Prevention: the hook already instructs (`list_runs`, captured PID); no change.
3. **Heredoc written to `$TMPDIR/...` with `$TMPDIR` unset** — Recovery: re-sent the block via the Write tool to the scratchpad — Prevention: write scratch files to the session scratchpad directory, never `$TMPDIR`.
4. **Leftover `... if False else None` in a patch snippet silently skipped an edit** — Recovery: re-ran the edit — Prevention: apply edits with asserted counts and print a landing check after every patch.
5. **Non-unique patch anchors** — Recovery: lengthened the anchors; the count assertion caught it before any write — Prevention: keep the `assert s.count(old) == 1` pattern.
6. **Proposed epic item 5 as parallel work without checking it was already shipped (#10524)** — Recovery: the fork verified and stopped without a PR — Prevention: check merged PRs for an epic item before offering it as a candidate.
7. **Started a full-gate run, then committed on top of it** — Recovery: it was still queued on the advisory lock; killed by exact pid and re-planned for after the last commit — Prevention: commit everything first, then start the gate (already in the review skill's sharp edges).
8. **TLS handshake timeout on `gh issue create`** — Recovery: searched by title for a duplicate, then retried — Prevention: search for the title before retrying any non-idempotent `gh` create.
9. **Three checker bugs in the first guard rewrite** (`TF_VAR_hcloud_token` case, `doppler run -- env` argv shape, a comment-line mutation shape) — Recovery: the suite's own mutation rows reddened; fixed pre-commit — Prevention: keep one mutation row per rule so a vacuous rule fails its own row.
10. **Stop-hook: closing text named an action without taking it** — Recovery: ended with a `Paused:` sentence — Prevention: end a waiting turn with the label and the one thing waited on.

## Tags
category: ci-workflows
module: scheduled-terraform-drift, token-drift-workflow-causes.test.sh
