<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 opt-out rationale. The IaC gate matched `systemctl daemon-reload` in this plan's
  prose. Every occurrence is a CITATION of the historical defect #7220 was filed for (the
  ungranted daemon-reload that killed the config handler), never a step this plan prescribes.
  This plan edits exactly one bash TEST file and introduces no server, service, unit, cron,
  secret, DNS record, or vendor account — there is nothing to route through Terraform. See
  "Gates Assessed and Skipped" below.
-->
---
title: "fix(infra): pin the #7220 regression guard to an immutable SHA"
date: 2026-08-04
type: fix
branch: feat-one-shot-7220-pin-regression-guard-ref
pr: 7271
refs: [7220]
lane: procedural
brand_survival_threshold: none
---

# fix(infra): pin the #7220 regression guard to an immutable SHA

## Overview

`apps/web-platform/infra/infra-config-apply.test.sh` contains a proof-of-red guard,
`test_fatal_channel_red_against_main`, whose job is to demonstrate that the fatal-channel
assertions above it genuinely fail against the handler they were written to catch. It reads that
"old" handler from the **moving ref `origin/main`**.

The handler fix (PR-A) merged to main as `c2de2581e` on 2026-08-03/04. From that moment
`origin/main` carries the **fixed** handler, so the guard's two assertions inverted and now fail
permanently:

```
=== Results: 144 passed, 2 failed ===
  FAIL: pre-fix handler carried NO fatal_line (this is #7220)
  FAIL: pre-fix handler reported the hardcoded files_total=0
```

The guard did not detect a regression — **it consumed its own fix.** Its own header states the
intent correctly ("a regression guard that passes against the code it was written to catch is
decoration"); only the implementation is wrong.

The fix is to pin the old handler to the immutable pre-fix commit
`701e76e6bfce84ceed91096a58d88df7da5b6932` instead of a branch name. That is what makes the guard
*mean* something: it asserts a specific historical handler failed these properties, which stays
true forever, instead of asserting a live branch is still broken, which stops being true the
instant you fix it.

## Research Reconciliation — Spec vs. Codebase

Every premise inherited from the issue was probed before planning. Two corrections:

| Claim (from #7220) | Reality (measured) | Plan response |
|---|---|---|
| Guard reads `origin/main`; two assertions fail | **Holds.** Reproduced locally: `144 passed, 2 failed`, exactly the two named assertions. Confirmed on freshly-fetched `origin/main` @ `9336356` that line 1352 still carries the moving ref. | Proceed as scoped. |
| `701e76e6b` is the correct pre-fix commit | **Holds, and verified against the assertions rather than assumed.** At that SHA the handler contains `fatal_line` **0 times** (→ `$old_line` is `MISSING`) and hardcodes `"files_total":0` in the EXIT trap at line 222. Both assertions are satisfied by this exact object. | Pin to it. Use the **full 40-char SHA**, not the 9-char abbreviation. |
| "reds Infra Validation on **every** infra PR" | **Partly overstated.** The job goes red, but `deploy-script-tests` is **ADVISORY** — `.github/workflows/infra-validation.yml:472-475` records it does not block merge today (tracked by #6480). | Keep the fix; state the urgency honestly (below). Do **not** claim the merge queue is blocked. |
| *(not in the issue — checked because the fix depends on it)* Can CI even see a pinned SHA? | **Yes.** The suite runs at `infra-validation.yml:808`, inside `deploy-script-tests` (job spans 339–1155), whose checkout at 418–421 sets `fetch-depth: 0` + `fetch-tags: true`. A full clone reaches `701e76e6b`. | Pin is safe. Without this, the pin would have converted a failing test into a permanently-skipping one. |

**Why this still matters despite being advisory.** A permanently-red correctness gate is precisely
how a gate becomes decoration. #7266 already merged with this check red, justified as "proven
pre-existing" — and that PR's own author flagged the risk that this "does not quietly become the
norm." That is the cost being paid, and it compounds silently.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this is a test-only change on
  an advisory CI gate with no runtime surface. The realistic failure is indirect: a wrong pin (or a
  weakened skip) leaves the fatal-channel assertions unproven, so a future regression in
  `infra-config-apply.sh` — the handler that delivers 19 config files to the prod host — could ship
  believing it was guarded when it was not.
- **If this leaks, the user's data / workflow / money is exposed via:** no exposure vector. The
  change touches no secrets, no persistent store, no network path, no user data. The pinned SHA is
  public repo history.
- **Brand-survival threshold:** none
- Scope-out: threshold: none, reason: a test-file change to an advisory, offline CI suite with no
  runtime, data, or user-facing surface — the diff touches only bash test harnesses and markdown.

## Files to Edit

- `apps/web-platform/infra/infra-config-apply.test.sh` — the only file. Five regions
  (regions 4–5 added at review; see "Review Findings Applied" below):
  - `test_fatal_channel_red_against_main` (~1346–1378): the `git show` ref, the skip/fail
    predicate, and the pin-rationale comment.
  - Block header (~1107–1108): "proven RED against **origin/main's** handler" — now false.
  - Section marker (~1340): "PROVE THE ARMS ABOVE ARE RED AGAINST **origin/main**" — now false.
  - **Function rename** — `test_fatal_channel_red_against_main` →
    `test_fatal_channel_red_against_pre_fix`, plus the runner call site (~1526). The name is
    itself the stale prose Phase 2 sweeps: it asserts the guard runs against main, which is
    exactly the misconception this PR exists to kill. Not prescribed in the original draft;
    added because leaving it would contradict the comment being added two lines away.
  - **Assertion-count floor** (~1555) — `APPLY_MIN_ASSERTIONS`, ratcheted 142 → 146. See the
    P1 below; this is the mechanical backstop that makes a silently-skipping guard red.

No other file. Scope is deliberately confined so this merges fast.

## Open Code-Review Overlap

Checked `gh issue list --label code-review --state open` against
`apps/web-platform/infra/infra-config-apply.test.sh`: **None.**

## Implementation Phases

### Phase 1 — Pin the ref (the fix)

Introduce a named constant near the test so the SHA is stated once, with the rationale attached:

```bash
# The pre-fix handler, pinned to an IMMUTABLE commit — NOT `origin/main`.
#
# `origin/main` is the natural thing to write here and is exactly wrong: the moment the fix
# merges, main carries the FIXED handler and these two assertions invert and fail forever. A
# guard pinned to a moving ref consumes its own fix (that is #7220's second defect, filed after
# PR-A merged as c2de2581e and turned this suite permanently red). A pinned SHA asserts that a
# specific historical handler failed these properties — true forever. Do not "helpfully" restore
# the branch name.
#
# 701e76e6b = the last commit to touch infra-config-apply.sh BEFORE c2de2581e. Full SHA, not the
# abbreviation, so no future object can make it ambiguous. Verified: at this commit the handler
# contains `fatal_line` zero times and hardcodes "files_total":0 in the EXIT trap.
readonly PRE_FIX_HANDLER_SHA="701e76e6bfce84ceed91096a58d88df7da5b6932"
```

Then swap the read and the predicate. **The two-arm structure is preserved exactly** — only the
thing being tested changes, from "does the branch resolve" to "is the commit present":

```bash
  if ! git -C "$SCRIPT_DIR" show "${PRE_FIX_HANDLER_SHA}:apps/web-platform/infra/infra-config-apply.sh" > "$old" 2>/dev/null; then
    # FAIL, not SKIP, when the commit IS present but the show fails — that is a real breakage,
    # not an unavailable environment. A silent skip here makes the PR's only proof-of-red one
    # `fetch-depth: 1` away from not existing, and nothing downstream consumes a skip.
    if git -C "$SCRIPT_DIR" cat-file -e "${PRE_FIX_HANDLER_SHA}^{commit}" 2>/dev/null; then
      echo "  FAIL: pinned pre-fix commit resolves but the handler could not be read — mutation proof is broken, not skipped"
      FAIL=$((FAIL + 1))
    else
      echo "  SKIP (loud): pinned pre-fix commit ${PRE_FIX_HANDLER_SHA:0:9} unavailable (shallow clone) — mutation proof NOT run"
    fi
    teardown
    return 0
  fi
```

`git cat-file -e <sha>^{commit}` is the correct presence predicate — `rev-parse --verify` on a raw
SHA succeeds on syntax alone in some git versions and would collapse the skip arm.

### Phase 2 — Sweep the stale prose

A stale prose claim must not outlive the assertion it describes.

- ~1107: `# Every arm below is proven RED against origin/main's handler by` → name the pinned
  pre-fix handler instead.
- ~1340: `# --- #7220: PROVE THE ARMS ABOVE ARE RED AGAINST origin/main ---` → `... AGAINST THE
  PINNED PRE-FIX HANDLER ---`.
- ~1342–1344: the body prose says "runs the pre-#7220 handler from git" (still true) and
  "shallow clone / detached worktree" (still true) — re-read and adjust only what the pin
  falsifies.

Then `grep -n 'origin/main'` the whole file and confirm every survivor is either gone or is
deliberate rationale prose explaining why the branch name is *not* used.

### Phase 3 — Verify

Run the suite and show real output. Expected: the two named assertions flip to PASS, giving
**146 passed, 0 failed** (146 = the current 144 + 2).

```bash
bash apps/web-platform/infra/infra-config-apply.test.sh 2>&1 | tail -5
```

## Acceptance Criteria

Note on AC design: a naive `grep -c 'origin/main' == 0` would **false-fail**, because Phase 1's
rationale comment legitimately names `origin/main` to warn against it. The ACs below therefore
assert the *guardrail's presence* and scope the absence check to **non-comment lines**.

### Pre-merge (PR)

1. **The pin exists and is the full SHA.**
   `grep -c '^readonly PRE_FIX_HANDLER_SHA="701e76e6bfce84ceed91096a58d88df7da5b6932"$' apps/web-platform/infra/infra-config-apply.test.sh` → `1`

2. **No executable line reads the moving ref.** Strip comment lines first:
   `grep -vE '^\s*#' apps/web-platform/infra/infra-config-apply.test.sh | grep -c 'origin/main'` → `0`

3. **The pin is CORRECT, not merely present** — the pinned object actually carries both pre-fix
   properties (this is the AC that catches a wrong SHA). Note `grep -c` exits 1 on a zero
   match, so run these un-chained (a `set -e` / `&&` runner aborts on a *passing* AC):
   - `git show 701e76e6b…:…/infra-config-apply.sh | grep -c fatal_line` → `0`
   - Anchored on the **mechanism**, not prose — the EXIT trap is a `printf` with escaped
     quotes, and a bare `"files_total":0` also matches an explanatory comment at line 141:
     `git show 701e76e6b…:…/infra-config-apply.sh | grep -c 'printf.*files_total\\\\":0'` → `≥ 1`

3b. **The floor catches a silent skip** (the P1 this review found). With the pin repointed at an
   absent object, the suite must NOT exit 0:
   - non-CI → loud `SKIP` + `FAIL: assertion-count floor — only 144 assertions ran, expected >= 146`
   - `CI=true` → `FAIL: pinned pre-fix commit … is absent under CI` + the floor failure
   Both measured; pre-fix behaviour was `144 passed, 0 failed`, exit 0.

4. **The guardrail comment is present** (asserted by presence, per the note above):
   `grep -c 'Do not "helpfully" restore the branch name' apps/web-platform/infra/infra-config-apply.test.sh` → `1`

5. **Loud-skip semantics preserved — both arms still exist:**
   - `grep -c 'cat-file -e "${PRE_FIX_HANDLER_SHA}^{commit}"' …` → `1`
   - `grep -c 'FAIL: pinned pre-fix commit resolves but the handler could not be read' …` → `1`
   - `grep -c 'SKIP (loud): pinned pre-fix commit' …` → `1`

6. **Stale prose swept:** neither of the two stale claims survives.
   `grep -c "proven RED against origin/main's handler" …` → `0`
   `grep -c 'RED AGAINST origin/main ---' …` → `0`

7. **Suite green, with the run output pasted into the PR body — not asserted without it:**
   `bash apps/web-platform/infra/infra-config-apply.test.sh` → `=== Results: 146 passed, 0 failed ===`

8. **Scope held:** `git diff origin/main...HEAD --name-only` lists only
   `apps/web-platform/infra/infra-config-apply.test.sh` plus this plan and its spec artifacts.

### Post-merge (operator)

None. Nothing to apply, provision, or verify by hand — this is a test-file change on an offline
CI suite. `#7220` **stays OPEN**: this lands the CI repair only; the ungranted privileged
unit-reload the issue was filed for is still ungranted (PR-B).

## Test Scenarios

The suite is its own test. Three states worth confirming during Phase 3:

1. **Happy path (full clone, this worktree):** the guard runs, both assertions PASS, 146/0.
2. **The guard can still fail** — sanity-check the proof is not vacuous by temporarily pointing
   `PRE_FIX_HANDLER_SHA` at `c2de2581e` (the *fixed* handler); the two assertions must FAIL.
   Revert immediately. This is the control that proves the pin still discriminates.
3. **Shallow-clone arm:** not reproducible in this worktree; covered by inspection of the two-arm
   structure (AC5). CI runs `fetch-depth: 0`, so the skip arm is not expected to fire in practice.

## Observability

This plan edits a file under `apps/web-platform/infra/`, so the gate is named rather than skipped
silently — but the change introduces **no runtime surface**: no new error path, no log call, no
failure mode reachable from production. The edited file is a test harness that runs only in CI and
locally.

- `liveness_signal`: the suite's own `=== Results: N passed, M failed ===` line, emitted per run of
  `deploy-script-tests` (`infra-validation.yml:808`) on every infra-path PR.
- `error_reporting`: assertion failures print `FAIL: <name>` to the job log and increment the
  suite's exit-code accounting. Fail-loud by construction — and this PR's whole purpose is
  restoring that property.
- `failure_modes`: (a) *pin unreachable* → detection: **the assertion-count floor reds the
  suite** (`144 < 146`), and under `CI` the arm additionally emits a `FAIL`. The pre-review
  draft cited "the loud `SKIP` line in the job log" here, which was a citation that read as
  covered and was not: the run exited 0, printed a normally-shaped results line, emitted no
  annotation, moved no counter, and sits in an advisory job. A layer only counts when a
  consumer can distinguish the signal.
  (b) *pin present but unreadable* → detection: the `FAIL` arm, which reds the suite;
  (c) *pin points at the wrong object* → detection: the non-vacuity control (repointing at
  `c2de2581e` must red the two assertions). AC3 is a one-time pre-merge grep, not ongoing
  detection — stated plainly rather than counted as a monitored layer.
- `logs`: GitHub Actions job logs for `Infra Validation / deploy-script-tests`; retention per repo
  default.
- `discoverability_test` — the load-bearing property is that the pinned commit is REACHABLE in the
  checkout; if it is not, the guard degrades to a skip (locally) or a loud FAIL (under CI). That is
  the one thing an operator can check in a second, with no SSH and no credentials:

```yaml
discoverability_test:
  command: git cat-file -t 701e76e6bfce84ceed91096a58d88df7da5b6932
  expected_output: commit
```

  The full proof is `bash apps/web-platform/infra/infra-config-apply.test.sh` (also no SSH), which
  runs ~40s — too slow for the 15s preflight cap, so the reachability probe above is the gate and
  the suite is the deeper check.

## Gates Assessed and Skipped

- **GDPR / compliance (2.7):** no regulated-data surface — no schema, migration, auth flow, API
  route, or `.sql`. None of the (a)–(d) expansion triggers fire. Skipped.
- **Infrastructure-as-Code (2.8):** introduces no server, service, cron, secret, DNS record, or
  vendor account — one bash test file. The gate's keyword match is on citations of the historical
  defect, not on prescribed steps; ack comment at the top of this file. Skipped.
- **Architecture Decision ADR/C4 (2.10):** no architectural decision. This is a bug fix on an
  existing test surface; no actor, external system, container, or access relationship changes.
  A competent engineer reading the current ADRs + C4 would not be misled after this ships.
  Skipped.
- **Encryption Posture (2.11):** no persistent store, no new cross-component connection. Skipped.
- **Soak follow-through (2.9.1):** no time-gated close criterion. Skipped.

## Domain Review

**Domains relevant:** none

No cross-domain implications — an internal CI-tooling correctness fix with no user-facing,
product, legal, or financial surface. No file matches the UI-surface term list, so the mechanical
Product override does not fire.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| The pin is unreachable, silently converting the guard into a permanent skip | **This was under-mitigated in the pre-review draft and is the PR's main review finding.** Two agents independently reproduced a real fail-open: a shallow clone printed `144 passed, 0 failed` and exited 0. Corrected three ways: (a) `APPLY_MIN_ASSERTIONS` ratcheted 142 → 146, so the skip's 2 lost assertions now red the suite; (b) under `CI` the absent pin is a **FAIL**, not a skip, because `fetch-depth: 0` makes reachability a contract there; (c) reachability documented as resting on the tags + fetch-tags, not on the SHA's length. The original mitigation — "AC5 asserts both arms survive" — was wrong: AC5 asserts the arms exist *in source*, which does not make a *fired* skip fail anything. |
| A future reader "helpfully" restores `origin/main` | The rationale comment names the failure mode explicitly and says not to; AC2 + AC4 encode it mechanically. |
| The chosen SHA is wrong | AC3 asserts the pinned object's *properties* (`fatal_line` absent, `files_total:0` hardcoded), not just that the SHA resolves — a wrong pin fails the AC. |
| Scope creep into PR-B's grant work | Explicit non-goal; AC8 pins the diff to one source file. |

## Non-Goals

- The privileged unit-reload sudoers grant (PR-B, worktree
  `feat-7220-pr-b-daemon-reload-grant` — commits present, unpushed, no PR open). Untouched.
- Making `deploy-script-tests` a required check — that is #6480's scope, and folding it in would
  turn a 1-file test repair into a merge-queue policy change.
