# Learning: a detector step whose failure reaches no reporter channel reports `ok`

## Problem

On PR #12968 (rundevoo.run zone onboarding) a new `if: always()` probe step
("DNS whole-list set equality") was added mid-job in
`scheduled-terraform-drift.yml`. A step failure reddens the job — that part
works. But every notification channel in the job keyed exclusively on
`steps.plan.outputs.exit_code`:

- the infra-drift issue filer: `exit_code == '2'`
- the email pair: `exit_code != '0'`
- the Sentry check-in: `(exit_code == '0' || '2') && 'ok' || 'error'`

A probe-only failure (an unmanaged DNS record on a company domain — the exact
incident the probe exists to detect) produced `exit_code == '0'`: no issue, no
email, and the heartbeat **actively reported `ok`**. The green-washing is worse
than silence — a monitor that says `ok` on a failed run suppresses the next
look. The coverage consult caught it only by asking "which defect class is
absent from the panel's list" — no lens enumerated the notification channel
surface.

## Solution

`id:` on the probe step (`dns_equality`), then fold
`steps.dns_equality.outcome == 'failure'` into all three channel `if:`s and the
check-in status expression. `outcome` is `skipped` on matrix legs where the
step doesn't run, so `!= 'failure'` preserves sibling-leg behavior with no
flag plumbing. A bare step failure (no `continue-on-error`) already keeps the
job red — no enforce step needed. The issue/email bodies each needed a
probe-specific arm too: the shared preamble asserted "plan returned exit code
2", which would have lied on a probe-only failure.

Companion shape found the same session:
`err=$(failing cmd)` inside a `set -e` test harness is a *dead test* — the
assignment's non-zero exit kills the suite before the assertion runs. Any
capture-the-stderr-of-a-failure idiom needs `|| true` (or `|| rc=$?`).

## Key Insight

When a new check step joins a job whose reporters key on one step's output,
the step's *failure domain* is unmapped until someone names every channel and
asks what each prints on its red. "The job fails" is not notification — it is
the absence of notification with a red icon. The litmus: for each reporter,
state the expression it fires on, then ask whether the new step's failure
satisfies it. Channels that report `ok` under a failed sibling step are the
worst case — they convert a detection into a green claim.

## Session Errors

1. `err=$(bash "$VERDICT" success failure 2>&1 >/dev/null)` in
   `test-rundevoo-destroy-gate-verdict.sh` exited the suite at T17 — the
   command substitution's exit status propagates through the assignment and
   `set -e` kills the script. **Prevention:** audit every `var=$(...)`
   assignment in `set -e` test code for whether the command may legitimately
   fail; the sibling sentry verdict suite is checked in #12999.
2. `lint-infra-no-human-steps` red on `spec.md`/`issue-body.md` — the
   heuristic matched `terraform apply` prose describing the *workflow-driven*
   apply's acceptance property. **Prevention:** when writing AC/goal prose
   that names the absence of a human step, expect the co-occurrence heuristic
   and pre-wrap in `<!-- lint-infra-ignore start: <reason> -->`.
3. Filing gate rejected `gh issue create` — the body named no user-visible
   consequence. **Prevention:** machinery findings take `--label
   meta/machinery` on the first try (already recorded in an earlier compound
   pass; it still tripped once).
4. Playwright MCP pinned `channel: chrome` to a nonexistent binary.
   **Prevention:** fall back to playwright-core + the bundled Chromium in the
   npx cache; the persistent-profile path carries the login session.
5. `git rebase --continue` blocked on the `nvim` editor. **Prevention:**
   `GIT_EDITOR=true` on rebase continue in non-interactive shells.
6. A background review seat completed with an empty report. **Prevention:**
   `run_subagent resume` with a re-emit request recovers it; treat an empty
   completion as a degraded pass needing a resume, not a clean verdict.

## Tags
category: workflow-patterns
module: ci-workflows
