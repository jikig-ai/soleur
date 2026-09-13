---
title: "A post-write probe cannot be referenced to a capture taken before the write"
date: 2026-09-11
category: integration-issues
module: System
problem_type: integration_issue
component: tooling
symptoms:
  - "Apply sentry infra red on main after a COMPLETE apply: `UNMANAGED: 'ops-email-delivery-failure' is live and in scope but absent from the capture`"
  - "The tracking issue's prescribed remedy (re-run the failed job) redded deterministically — same SHA, same stale capture"
  - "The daily drift job filed a drift issue AND a 'could not establish a verdict' issue whose body read `Verdict reached: drift`"
root_cause: logic_error
resolution_type: code_fix
severity: high
tags: [sentry, terraform, drift-probe, derived-reference, fixture-provenance, review-panel, mutation-testing, subshell, jq, rebase-conflict]
issues: [8050, 8057, 8058, 7997, 8023]
pr: 8069
synced_to: [work, review, one-shot, plan]
---

# A post-write probe cannot be referenced to a capture taken before the write

## Problem

`apply-sentry-infra.yml` went red on `main` after PR #7989 added a `sentry_alert`. The
apply itself was complete — the apply step exited 0, AC17 (state list vs declared
`.tf`) was green, and the forensics artifact showed 28 → 29 `sentry_alert` exactly. The
red came from step 15, the post-apply probe `scripts/sentry-alert-live-fidelity.sh`,
which compared live Sentry against a **committed live capture taken two days earlier**
and reported the new, Terraform-managed, correctly-applied rule as `UNMANAGED … created
outside Terraform, or the capture is stale. Nothing in this repo manages it.` Two of those
three clauses were false. The same class had fired once before (#7772 → #7985) and been
patched with a name carve-out that was later deleted.

The tracking issue (#8050) prescribed "re-run the failed job on THIS run" as the only
gesture that works. It cannot: a re-run checks out the same SHA whose capture lacks the
rule, so the finding recurs deterministically.

A sibling defect surfaced in the same failure: the daily drift workflow's
"probe-unavailable" filer was gated `if: always() && failure()`, and the drift filer two
steps above it ends in a deliberate `exit 1` on every drift verdict — so the dead-man's
switch fired on the one class of run it was written to exclude, filing #8058 ("could not
establish a verdict", body: `Verdict reached: drift`) alongside the correct #8057.

## Root cause

**A rule cannot be live-captured before it is applied.** A post-apply probe whose
reference is a snapshot of live state is structurally red on the merge that applies any
new rule — the reference is a property of the moment it was taken, not of what the `.tf`
declares. The probe inferred "managed" from the capture rather than from Terraform, so its
message blamed the rule when only "the capture is stale" was true.

The drift-workflow defect is the job-scoped-`failure()` class: `failure()` is true when
*any* earlier step failed, and a filer that exits 1 by design is an earlier step.

## Solution

Make the Terraform plan the probe's reference (PR #8069):

- `tests/scripts/lib/sentry-alert-projection.jq` — one module, `--arg side tf|live|reference`,
  one `canon`/`normalise` for all three sides. The `tf` side reads `terraform show -json`
  (plan or state); `live` is the probe's former inline projection; `reference` normalises
  an already-projected document. Two measured normalisations: lifecycle triggers (`{}` in
  the provider, `comparison: true` live) and trigger `logicType`, which provider v0.15.7
  hard-codes to `any-short` on every write (`resource_alert_impl.go` 803/835) while
  imported single-trigger rules still read `all` — single-trigger rules project the
  constant `single` on both sides. Against the real plan and the 2026-09-09 capture:
  28 common rules, 0 mismatches.
- The **apply job projects its own reference from the plan it applies**
  (`${RUNNER_TEMP}/sentry-alert-reference.json`), so a divergence after the apply is
  live state Terraform does not own or evidence the apply did not do what it reported —
  true by construction. It never reads the committed copy.
- `apps/web-platform/infra/sentry/alert-reference.json` — a committed projection that
  exists ONLY for the daily job (no Terraform access), held equal to the plan at PR time
  by `scripts/sentry-alert-reference-gate.sh` in `plan_pr`. On mismatch the gate prints the
  leaf diff and writes the expected document; the workflow sweeps it and publishes it to
  the step summary and an artifact, so the credential-free remedy is `gh run download`.
- The drift filer is gated on the verdict pair `(verdict, filed)` with `!cancelled()`,
  and its closer carries the matching `filed == 'true'` conjunct so the two are disjoint
  inside one run.

## Key insight

**When a check compares a live system to a reference, ask what the reference is a
function OF.** A capture is a function of the moment it was taken; a projection of the
plan is a function of what the code declares. Only the second can be true on the merge
that changes the declaration. The same question decides where a committed derived file
may live: it is valid exactly for the consumers that cannot recompute it (here, a cron
job without credentials), and it must be gated equal to its source wherever the source
can change.

## What the review panel found that the author's battery could not

The PR shipped with three suites and a plan-time Guard Contract whose mutation matrices
all perturbed **fixtures**. An eleven-seat review (plus a structural-enumeration seat
replacing `performance-oracle`) found the defects on every axis those matrices never
touched:

- **A stale base that reads as a clean diff.** `#8023` — an independent fix of the same
  probe for #7997 — merged onto `main` two hours after this branch's Phase 0 fetch.
  `git merge-tree origin/main HEAD` reported three conflicts and a contract break: `main`'s
  drift workflow greps `^ERROR: refusing (org|destination host)` with exit 2, and this
  branch's refusal text matched neither. Every local suite was green; only a reviewer who
  fetched `origin/main` saw it. The fix kept every `#8023` control (env-scrub prologue,
  `_safe`, RFC-1035 org gate + `readonly`, `--proto '=https' -g`, exit-2 anchors) and added
  the literal pins and the bearer header on stdin. The #7997 comment posted from the stale
  branch was wrong and had to be corrected.
- **The live side had no floors.** `INDEX(.name)` on the live side is last-writer-wins,
  so a disabled managed rule shadowed by an enabled same-name copy measured PASS
  depending on API order; a live rule with `name: ""` was skipped by every
  `[[ -n "$name" ]] || continue`, i.e. exempt from the UNMANAGED loop; and
  `trigger_logic_type($n; null)` DEFAULTED a multi-trigger live rule with no `logicType`
  to `any-short` — equal to the TF side — under a header that said "EVERY FLOOR IS AN
  error, NEVER A DEFAULT". Three agents converged; all three now refuse.
- **Allowlist one element kind, pass the others through.** Action kinds were allowlisted
  (`["email"]`); condition kinds were passed through as `comparison: .value`. Read from
  the provider's wire structs: five condition types serialise under different keys live
  (`target_id` → `targetIdentifier`, `comparison_type` → `comparisonType`,
  `{comparison: 75}` → `75`, `{}` → `true`, `null` → `omitempty`-absent). The first rule
  to use one would pass the PR-time gate (tf vs tf) and red `main` after the apply — the
  exact class the PR closed. Condition and trigger kinds are now allowlists too.
- **A single sweep site, and it must precede BOTH channels.** The gate wrote the expected
  document into `$GITHUB_STEP_SUMMARY` itself and a later workflow step swept only the
  artifact copy — a later step cannot retract an earlier step's summary. The gate now
  writes neither channel; the sweep step publishes both after sweeping, the upload is
  gated on `steps.sweep.outcome`, and the sentinel regex lives once at workflow `env`.
- **Substring presence on a GitHub `if:` is not an assertion.** Replacing
  `(verdict == 'drift' && filed != 'true')` with a bare `filed != 'true'` — which files the
  "could not establish a verdict" issue on every CLEAN run — left the drift suite 14/14
  green, because the check grepped fragments. The suite now compares the exact
  whitespace-collapsed expression and has a mutation row for that unpairing.
- **The verdict branch was pinned by stubs exiting 0 or 1.** The probe also exits 78
  (xtrace refusal), 2 (destination refusal), 5 (jq error) and 127; an `-eq 0` → `-ne 1`
  refactor would have classified all of them `verdict=clean`. W3b drives each.
- **A route to the field the operator reads.** The apply-job filer body told the reader
  to carry "the expected reference the gate printed" for a plan-step failure in a job
  where the gate never runs and nothing prints an expected document.
- **A re-derived count carried a false neighbour.** The `model.c4` edge was rewritten
  from 27/3 to 29/2 and kept "`byok_cap_exceeded` alone sets NoOne" — `git_data_boot_warning`
  also does; the split is 27 + 2, not 28 + 1. The number was re-derived; the sentence
  beside it was not re-measured.

## Session Errors

1. **Planning subagent tripped `iac-plan-write-guard.sh` on the phrase "in the Sentry UI".** — Recovery: reworded; no opt-out marker. — **Prevention:** one-off false positive; if it recurs, widen the guard's vendor-dashboard exemption for "UI" as a NOUN naming where drift originates, not a click-path.
2. **`plan/SKILL.md` Phase 2.10 names `apps/web-platform/test/c4-count-parity.test.sh`, which does not exist.** — Recovery: C4 impact verified via `scripts/regenerate-c4-model.sh` + `plugins/soleur/test/c4-model-freshness.test.sh`. — **Prevention:** routed to the plan skill (the citation is replaced with the gates that exist).
3. **`learnings-researcher` surfaced the 2026-06-12 learning's `-target=` allow-list step, stale since #6589 made the apply full-root.** — Recovery: recorded in Research Reconciliation, not acted on. — **Prevention:** a superseded-by note on that learning.
4. **An outer `<<'PY'` heredoc was terminated by an inner test block's own `PY` heredoc terminator, producing a python `SyntaxError` and a bash `unexpected token`.** — Recovery: wrote the block with the Write tool. — **Prevention:** when a heredoc's BODY contains heredocs, pick an outer terminator that appears nowhere in the body (`OUTER_EOF`), or write the body to a file first.
5. **A splice asserted `count == 1` on a label shared by a row's pass and fail branches and aborted.** — Recovery: regex renumbering. — **Prevention:** one-off.
6. **`_mut_plan` was called with jq args in the program slot.** — Recovery: `jq "${@:3}" "$2"` before the first run. — **Prevention:** one-off.
7. **`excluded | index(.key)` evaluated `.key` against the LIST.** — Recovery: `.key as $k | (excluded | index($k))`; caught by rc 5 on the first parity run. — **Prevention:** routed to the work skill (jq idiom).
8. **`paths(scalars)` dropped every `false`/`null` leaf, rendering `enabled: false` as `<absent>` — the pre-existing probe carried the same idiom.** — Recovery: `paths(type != "array" and type != "object")` at every leaf-walk site; caught by gate row M7. — **Prevention:** routed to the work skill (jq idiom); a `false`/`null` leaf fixture belongs in every leaf-diff suite.
9. **`live_json="$(fetch_rules)"` ran the function in a subshell, so `FIXTURE_MODE=1` never reached the parent; the fixture-mode PASS line had never printed in the probe's history.** — Recovery: set the flag in the parent from the env var; F1 asserts the full fixture literal. — **Prevention:** already documented (2026-07-27 subshell learning); the new point is that a suite grepping a substring both PASS lines share cannot see it — assert the full literal.
10. **`! grep -q 'PASS'` matched the fixture warning's prose ("A PASS here says…").** — Recovery: anchor `live fidelity: PASS`. — **Prevention:** `cq-assert-anchor-not-bare-token`, already a rule.
11. **The new sweep step's `grep -qE …; rc=$?` ran under Actions' inherited `bash -e`; the rc capture was dead code on the clean path.** — Recovery: `set +e`/`set -e` bracket, caught by `test-sentry-full-root-apply.sh` T13, then the step was extracted and driven under `bash -eo pipefail` on a clean and a tainted file. — **Prevention:** already in the work skill; T13 is the mechanical gate.
12. **`git push` rejected non-fast-forward: the draft-PR init commit was pushed before the branch was rebased onto `origin/main`.** — Recovery: verified the remote held only the init commit, `--force-with-lease=<branch>:<sha>`. — **Prevention:** routed to one-shot Step 0c.
13. **Stale base: #8023 landed on the same probe after Phase 0's fetch; found at review as a P1 with a contract break.** — Recovery: rebase, three-way reconciliation keeping both PRs' controls, corrected #7997 comment. — **Prevention:** routed to the review skill — run `git fetch origin main && git merge-tree --write-tree origin/main HEAD` BEFORE spawning the panel and treat a conflict on a file the diff rewrites as the first finding.
14. **`sleep 60 && gh …` blocked by the tool guard.** — Recovery: Monitor tool. — **Prevention:** one-off.
15. **Monitor timed out at 25 min: `plan_pr` pending behind 98 queued runs org-wide.** — Recovery: re-armed at 1h; the required check is enforced at merge regardless. — **Prevention:** external; none.
16. **Splicing T14 into a suite dropped the T13 CALL; both versions printed 13 `[ok]` lines.** — Recovery: diffed the `[ok]` label SETS against HEAD's run, not the counts. — **Prevention:** after any splice near a suite's call list, diff the row-label set against the previous version.
17. **`EXPECTED_TESTS` typed from prose three times (24→21, 25→23, 21→20).** — Recovery: derived from the run each time. — **Prevention:** the work skill already says derive counts from the as-written file; this is the class recurring.
18. **`model.c4` routing split re-derived arithmetically around a prose claim ("alone") that was not re-measured.** — Recovery: histogram over `alert-reference.json` (27 ActiveMembers, 2 NoOne). — **Prevention:** when a number changes in a sentence, re-measure every neighbouring claim in the same sentence, not just the number.
19. **Fixed-name `${TMPDIR}/…err` files in the gate and probe; measured losing jq's message in 5/8 concurrent runs.** — Recovery: `mktemp` + `trap`. — **Prevention:** `mktemp` for every capture file, no exceptions for "short-lived" ones.
20. **Live-side floors missing (duplicate name, empty name, null `logicType`).** — Recovery: three module errors + F29–F31. — **Prevention:** for every `INDEX(key)` / `group_by` / `[[ -n ]]` skip on the OTHER side of a comparison, ask which inputs collapse or vanish.
21. **Condition kinds passed through while action kinds were allowlisted.** — Recovery: allowlists for trigger and condition kinds + M13/M17. — **Prevention:** when one element position gets an allowlist, every element position gets one.
22. **Phase 2 shard exit gate not run — `test-all.sh --capacity` measured two sibling full-gate runs.** — Recovery: targeted suites; shard deferred to ship's Phase 4. — **Prevention:** none needed — the runner's rc-4 refusal is the mechanism.
23. **Plan-quoted counts (AC7 `25`, AC9 `8`, AC13 "no findings") were estimates.** — Recovery: ACs reconciled to as-written counts and the pre-existing actionlint baseline. — **Prevention:** already a rule (plan-quoted numbers are preconditions).
24. **A review agent's `SHELLOPTS=xtrace` probe fell through to a live GET against `jikigai-eu.sentry.io` with a dummy token (401), contrary to the brief's "nothing against live Sentry".** — Recovery: the agent disclosed it; no credential left the machine. — **Prevention:** routed to the review skill — briefs must say "install the shim BEFORE any invocation that can reach the live branch; a bare live call, even with a dummy token, is out of bounds".
25. **Pre-existing stale "28" in `sentry-issue-alert-create-tripwire.sh`'s message.** — Recovery: fixed inline (29 + the #7989 authoring). — **Prevention:** count-free wording where the count has no consumer.

## Related

- `2026-07-17-derive-replicated-literal-and-nonvacuous-drift-guard.md` — derive the artifact from the single source; prove the guard non-vacuous by mutation.
- `2026-04-03-lockfile-sync-ci-check-pattern.md` — regenerate the derived file in CI, diff against the committed one, fail the PR on divergence.
- `2026-07-30-the-guard-i-wrote-for-the-failure-path-could-not-run-on-the-failure-path.md` — GitHub `if:` status-function semantics; here the mirror image, a `failure()` true on the intended-exclusion path.
- `2026-07-27-the-subshell-bug-i-was-fixing-bit-me-three-more-times.md` — `x=$(fn)` discards every effect but stdout.
- `2026-09-10-my-battery-killed-all-26-and-could-not-see-any-of-the-20-escapes.md` — a battery that mutates fixtures only is blind to escapes on the SUT.
- ADR-031 (amended 2026-09-11), `apps/web-platform/infra/sentry/README.md` §Drift detection.
