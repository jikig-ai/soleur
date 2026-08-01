---
title: An alert step and its own fallback died together — guard fallbacks with `!cancelled()`
date: 2026-08-01
category: engineering
tags: [github-actions, observability, alerting, fail-closed, shellcheck]
issue: '#7136'
type: learning
---

# An alert step and its own fallback died together

`release-outcome`'s "Email the operator (release did NOT reach production)" step read
`${R_DEPLOY}`, declared in the `env:` of a **different** step. Step-level `env:` does not
cross step boundaries, so under `set -u` bash killed the step *before* the `curl` that sends
the mail. Every failed release since PR #7097 introduced the branch went unannounced —
the path had never once delivered.

## 1. A fallback guarded by the default `success()` is not a fallback

The design was explicitly two-channel: an email step that always exits 0 and reports through
`delivered`, plus a "Mirror non-delivery to Sentry and fail loudly" step, so that "a missing
API key and a dead Resend take the SAME path — neither can end in silence."

It ended in silence. The mirror step had no `if: always()` / `!cancelled()`, so it inherited
the implicit `success()` guard. When the email step *failed* — rather than exiting 0 with
`delivered=0` — the mirror was **skipped**. Run 30703438860: email=`failure`,
mirror=`skipped`.

**The rule:** a compensating step whose condition can only be evaluated when its subject
*succeeded* cannot compensate for that subject *failing*. Any step that exists to catch
another step's failure needs `!cancelled()` (or `always()`), and the fallback's own
crash-path must be considered, not just the value it reads. Reasoning about the *output* of
the step you are compensating for (`delivered != '1'`) silently assumes it ran to completion.

## 2. shellcheck structurally cannot catch a cross-step `env:` reference

actionlint already pipes every `run:` body through shellcheck, and SC2154 ("referenced but
not assigned") is exactly the right rule — it does not fire here **by design**: SC2154
exempts `ALL_CAPS` names as presumed-environment, and shellcheck has no view of the
workflow's `env:` blocks at all. Measured on the pre-fix body: zero findings.

So "we already run a shell linter" is not coverage for this class. The check has to be
workflow-aware: `scripts/lint-workflow-step-env-refs.py` resolves each reference against the
step's / job's / workflow's `env:`, in-body assignments, and earlier `$GITHUB_ENV` exports.

## 3. Guard defaults are the tell — and the direction of the default matters

Every other expansion in the step was defensively guarded (`${VERSION:-unknown}`,
`${TAG:-no tag was created}`, `${RESEND_API_KEY:-}`). The one bare `${R_DEPLOY}` was the one
that chose which of two message bodies to send. **A lone unguarded expansion among guarded
siblings is a defect signature**, and it is mechanically detectable: the linter treats
"guarded anywhere in this step" as the author having considered unset, which is also what
kept its false-positive count at zero.

Which branch an unset value falls into is a safety decision, not a style one. `${R_DEPLOY:-}`
now takes the "production was NOT updated" branch: over-warn rather than falsely reassure.

## 4. A branch that has never executed is not a branch that works

The `deploy == success` branch had never run, because the step always died first. It was
missing the run link and the failed-job list — while the shared closing paragraph told the
operator to *"send the run link above to your engineer."* Fixing the crash is what makes such
a branch reachable for the first time; **audit the newly-reachable path in the same change**,
because nothing has ever exercised it.

## 5. Verify an alert by executing it, not by reading it

The acceptance criterion asked for verification "against a forced-failure run, not only by
reading the YAML". Better than a one-off dispatch: the test extracts the step's `run` body
from the shipped workflow and executes it under `bash` with stubbed `curl`/`jq`, for
`deploy=failure`, `deploy=success`, and `R_DEPLOY` absent — on every CI run.

It carries a **mutation proof**: the same harness against the pre-fix body must die with
`unbound variable` having captured no payload. Without that case, the harness could pass
vacuously while never exercising the branch at all.

## 6. Measure a new linter's exemptions; never assume them

The check went 1046 → 69 → 23 → 7 → 1 findings as each exemption was added and *measured*
against the 70 workflow files on `main`. The last six were literal `$VAR` text inside single
quotes or written `\$VAR` — never expanded by bash. Landing at exactly one finding (the bug)
is what let it ship fail-closed with **no allowlist and no highwater baseline**.

Related: a first-revision regex for `mapfile`'s option grammar
(`(?:-\w+\s+\S*\s*)*`) was flagged by CodeQL as `py/redos` — `\S*` can consume the next
`-flag`, so each option parses two ways. For a scanner where over-counting assignments only
*suppresses* findings, a broad linear scan beats a precise ambiguous one.

## 7. A clean sweep of nothing reads as success

Twice while developing this, a stale CWD made the glob match zero files and print
`TOTAL: 0` — indistinguishable from a clean run. The shipped linter exits non-zero when it
scans zero files, matching `scripts/lint-workflows.sh`. This is the same shape as
`hr-empty-telemetry-is-not-evidence-of-absence`: nothing found because nothing was looked at
is not the same as nothing found because nothing is there, and the first one reads as safety.
