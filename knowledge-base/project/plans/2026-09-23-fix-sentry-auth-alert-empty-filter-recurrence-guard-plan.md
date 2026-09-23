---
title: "fix(sentry): close #4781 — the empty-filter guard already exists; fix the probe's frozen-rule misclassification and correct the red-herring lore"
date: 2026-09-23
slug: fix-sentry-auth-alert-empty-filter-recurrence-guard
branch: feat-one-shot-4781-auth-alert-empty-filters
issue: 4781
closes: 4781
type: fix
priority: p2
domain: engineering
lane: single-domain
brand_survival_threshold: aggregate pattern
---

# fix(sentry): close #4781 — auth alert empty-filter recurrence guard

## Overview

After the 2026-06-02 incident, when the four `auth-*` Sentry alert rules were found with
**empty trigger conditions and empty tag filters** (so each one emailed on every issue in the
project), issue #4781 asked for two things:

1. a **recurrence guard**. Option 1 was an audit-gate assertion; option 2 was making
   Terraform own the filters.
2. a **correction of the repo's lore**, which says an email "triggered by
   auth-callback-no-code-burst" is a coincidental red herring.

**Measured today (2026-09-23), the guard half of the issue is already done.**

- Option 2 shipped in #7650 Phase 2 (2026-09-04). The three burst rules are `sentry_alert`
  blocks with real `trigger_conditions` and `action_filters`, and `ignore_changes =
  [environment]` only.
- The fourth rule, `auth-per-user-loop`, was adopted as a frozen `sentry_alert` in #8453
  (2026-09-21). Its live content is pinned against a committed capture.
- A stronger form of option 1 exists. `scripts/sentry-alert-live-fidelity.sh` compares every
  declared rule field-for-field against live Sentry. It runs daily (Inngest
  `cron-sentry-alert-drift` → `scheduled-sentry-alert-drift.yml`, last green run today) and
  after every apply.

This plan builds neither option. It fixes two small defects in how the probe **reports**
the one #4781 variant it currently mislabels. It corrects the lore, including two living
runbooks and two stale comments. Then it closes #4781 with the measurements.

## Research Reconciliation — Issue vs. Codebase

| Issue #4781 claim | Reality on `origin/main` (2026-09-23) | Plan response |
|---|---|---|
| The 4 rules use `conditions_v2 = []` / `filters_v2 = []` placeholders under a wide `ignore_changes` | False since #7650 Phase 2 and #8453. The 3 burst rules have real triggers and filters with `ignore_changes = [environment]`. `auth-per-user-loop` has real `action_filters`, its trigger by type only, and `ignore_changes = all` (the provider cannot express its trigger, #7985) | Option 2 is done for 3 of the 4. No `.tf` attribute change |
| Nothing asserts non-empty filters | False. The fidelity probe reds on any field difference: native rules against the Terraform projection, frozen rules against the capture. Measurement 1: all four #4781 shapes exit 1 | Option 1 is subsumed |
| Repair is a re-PUT of the `configure-sentry-alerts.sh` definitions | That script cannot run. The legacy `rules/` API returns **410** (measured 2026-09-23), and its header is marked superseded (#8451) | The runbook is corrected |
| "5 learnings" call the email a red herring | 4 learnings plus 1 runbook say so. 2 more learnings put an auth-rule firing down to another cause (census below) | 6 notes + 1 anchor closing note + 2 runbook edits |

## Research Insights

### Premise Validation

- **#4781** is OPEN, with no closing PR. The three merged PRs that cite it do not close it
  (collision-gate finding). **Draft PR #8654** is open, with an empty body.
- In `apps/web-platform/infra/sentry/issue-alerts.tf`:
  - `sentry_alert.auth_callback_no_code_burst`: `event_frequency_count {15m, 3}`, filters
    `feature=auth AND op=callback_no_code`, an email action, `ignore_changes = [environment]`.
  - The exchange-code and signout burst rules have the same shape.
  - `auth_per_user_loop` is frozen: `legacy_trigger_conditions`, `ignore_changes = all`.
- **ADR corpus.** ADR-031's Amendment 2026-09-04 (#7650 Phase 2) and Amendment 2026-09-21
  (#8451) already record the ownership change. Option 2 is therefore an executed decision.
  No ADR amendment is needed, since this plan makes no architectural decision.

### Measurement 1 — does the fidelity probe catch the #4781 shape? (fixture run)

Method, the same as the suite's:

- **Live side:** the committed capture
  `knowledge-base/project/specs/fix-7650-sentry-alert-migration/phase34-live-workflows-capture-2026-09-09.json`.
- **Reference:** derived from the capture through the projection module
  (`jq --arg side live | jq --arg side reference`).
- **Shapes:** each one is a single scoped `jq` edit, run in fixture mode
  (`SENTRY_FIXTURE_RULES`), so no network call is made.

| Shape | Edit | rc | Findings |
|---|---|---|---|
| A — one native rule | `auth-callback-no-code-burst`: `triggers.conditions=[]`, every `actionFilters[].conditions=[]` | **1** | `DRIFT: 'auth-callback-no-code-burst'.triggerConditions` (only declared: `event_frequency_count {15m,3}`) + `DRIFT: ….actionFilters` (only live: `"conditions":[]`) |
| B — the incident as observed | the same edit on all four auth rules | **1** | DRIFT on both fields for each of the 3 burst rules; auth-per-user-loop as in D |
| C — filters only | `auth-callback-no-code-burst`: `actionFilters[].conditions=[]` | **1** | `DRIFT: ….actionFilters` |
| D — the frozen rule | `auth-per-user-loop`: `triggers.conditions=[]`, `actionFilters[].conditions=[]` | **1** | `FROZEN DRIFT: 'auth-per-user-loop'.triggerConditions captured=[event_unique_user_frequency_count {5m,3}] live=[]` + `FROZEN DRIFT: ….actionFilters`, **plus** `UNMANAGED: 'auth-per-user-loop' … declared nowhere … delete it in Sentry` **and** `line 373: def: command not found` |

**Answer: the probe catches every #4781 variant (rc=1 on all four).** Shapes A–C need no new
row. Shape D shows two reporting defects:

1. **Stray command substitution; the remedy text is dropped.** This affects every UNMANAGED
   finding, not just #4781's. Line 373 of `scripts/sentry-alert-live-fidelity.sh` puts
   `` `def excluded` `` in unescaped backticks inside a double-quoted string. Bash runs
   `def excluded` as a command, and the finding prints `add the type to  in tests/…` with the
   noun missing. It reproduces on suite row F10's own fixture. It was introduced in #8545
   (`2cbf7b9efc`, per `git log -S`). The suite never saw it because `_run` merges stderr into
   `$_out`, and F10 greps only the finding's prefix. Measured census of executable backticks:
   L191 and L287 are escaped, L584 sits inside the single-quoted jq program, and L373 is the
   only live instance.
2. **A false, destructive co-finding when a frozen rule leaves the excluded scope.** Once
   `auth-per-user-loop` loses its excluded trigger type live, `in_scope` admits it. The
   reference cannot declare it (`tf_legacy_floor`), so the UNMANAGED loop calls it "declared
   nowhere … delete it in Sentry", and all three claims are false. The drift issue's guide
   then contradicts itself. Its `UNMANAGED` bullet says "if declared … touch NOTHING in
   Sentry", while its `FROZEN DRIFT` bullet says "PUT from the capture". No suite row covers
   this transition. G4-25 and G4-26 cover the reverse direction, and G4-11 covers a frozen
   tag filter emptied with the trigger still excluded.

### Measurement 2 — are the live auth rules non-empty? (read-only, real Sentry)

```text
$ doppler run --project soleur --config prd --command 'SENTRY_AUTH_TOKEN="$SENTRY_IAC_AUTH_TOKEN" SENTRY_ORG=jikigai-eu SENTRY_API_HOST=jikigai-eu.sentry.io bash scripts/sentry-alert-live-fidelity.sh'
sentry_alert live fidelity: comparing 31 declared rule(s) against 31 live in-scope rule(s)
sentry_alert live fidelity: frozen-rule pin: compared 2 of 2 Terraform-frozen rule(s) against the committed capture (2 other excluded-type live workflow(s) are registered Sentry defaults, matched by id and name, content not pinned)
sentry_alert live fidelity: PASS (all 31 in-scope rules match the committed reference field-for-field)
rc=0
```

A direct `GET /api/0/organizations/jikigai-eu/workflows/?per_page=100` returned:

| Rule (id) | enabled | trigger | tag filters | dateCreated | dateUpdated |
|---|---|---|---|---|---|
| auth-callback-no-code-burst (566683) | true | `event_frequency_count {3, 15m}` | `feature=auth`, `op=callback_no_code` | 2026-05-17T14:52Z | 2026-06-02T07:32Z |
| auth-exchange-code-burst (566682) | true | `event_frequency_count {5, 15m}` | `feature=auth`, `op=exchangeCodeForSession` | 2026-05-17T14:52Z | 2026-06-02T07:32Z |
| auth-signout-burst (566672) | true | `event_frequency_count {5, 15m}` | `feature=auth`, `op=signOut` | 2026-05-17T14:48Z | 2026-06-02T07:32Z |
| auth-per-user-loop (566671) | true | `event_unique_user_frequency_count {3, 5m}` | `feature=auth` | 2026-05-17T14:48Z | 2026-06-02T07:32Z |

**Answer: all four rules are non-empty.** None has been written since the 2026-06-02 repair.
`GET /api/0/projects/jikigai-eu/web-platform/rules/` returns **410**, measured the same day.

### Why the lore is wrong: the drift window

The rules were **created on 2026-05-17** with empty placeholders and **repaired on 2026-06-02
at 07:32Z** (live `dateCreated` and `dateUpdated`). Between those two dates every auth rule
matched every issue in the project. Every incident the lore calls a coincidence falls inside
that window: 05-27, 05-29 (twice), 05-30 and 06-01. In each one, the named rule really fired.

### Lore census (grepped by subject and by paraphrase; plans, specs and archive excluded as point-in-time records)

| File | Kind | Claim | Action |
|---|---|---|---|
| `learnings/bug-fixes/2026-05-27-sentry-cron-community-monitor-missed-checkin.md` L21 | dated | "this was a red herring (coincidental unrelated Sentry issue alert…)" | note |
| `learnings/bug-fixes/2026-05-30-inngest-cron-desync-regression-needs-runtime-self-heal-not-ci-guard.md` L29 | dated | "a red-herring alert-routing artifact" | note |
| `learnings/bug-fixes/2026-06-01-best-effort-cron-monitor-liveness-not-success-and-offhost-visible-warn.md` L19 | dated | "a **coincidental red herring**" | note |
| `learnings/best-practices/2026-05-29-uptime-monitor-fuse-must-tolerate-self-inflicted-deploy-windows.md` L76-82 | dated | "That footer is a **documented red-herring**" | note (the advice to read the alert body still holds; the stated reason does not) |
| `learnings/2026-05-29-warn-level-debounce-for-recovered-fallback-sentry-floods.md` L16 | dated | puts an `auth-callback-no-code-burst` firing on a `feature=feature-flags` event down to a burst | note: with its intended filters that rule cannot match that event |
| `learnings/best-practices/2026-05-27-sentry-warning-level-still-triggers-alert-rules.md` L7 | dated | exchange-code and callback-no-code bursts firing on OAuth `access_denied` (`op=callback_provider_error`, `app/(auth)/callback/route.ts:105,117`) | note: neither rule's intended `op` matches; only `auth-per-user-loop` (`feature=auth`) does |
| `learnings/bug-fixes/2026-06-02-…-not-a-red-herring.md` | dated (anchor, correct framing) | "Recurrence guard tracked in **#4781**" | closing note: the guard, the drift window, and how to check today |
| `engineering/operations/runbooks/cloud-scheduled-tasks.md` L468 | **living** | "was coincidental (unrelated issue alert type)" | edit in place |
| `engineering/operations/runbooks/oauth-probe-failure.md` ~L600-625 | **living** | `auth-per-user-loop` owner is "this script"; "(the 2026-06-02 mode — see #4781, still open)" | edit in place, narrowly |

Two files were cut from the note list by the plan review:

- `2026-05-17-sentry-issue-alert-create-dedup-…md` never frames the email as a red herring.
- `2026-08-19-i-proposed-deleting-a-control-…md` says "#4781 still open", which was true on
  its date, and it already carries a maintained amendment. Neither file reaches a reader
  who greps "red herring".

### Stale comments on the #4781 posture (same class as the lore)

- `apps/web-platform/infra/sentry/issue-alerts.tf`: the block between
  `auth_callback_no_code_burst` and `auth_exchange_code_burst` still says "IMPORT-ONLY … Do
  NOT migrate these to `sentry_alert`" directly above `sentry_alert` blocks. The research
  pass found no test or lint that pins its text.
- `.github/workflows/apply-sentry-infra.yml` L38-41: "The 4 AUTH issue-alert resources carry
  `ignore_changes` on their v2 attributes (they are import-only …)". This is false today
  (CTO review).
- `scripts/sentry-create-gate.sh` L15 ("the 4 formerly-untargeted import-only alerts") is
  historical narrative and correct as history. **Not edited.**

### Property List

- **P1** — A live auth rule whose triggers or tag filters are emptied makes the scheduled
  probe exit non-zero within a day. *(Already true, Measurement 1.)*
- **P2** — That report names each affected rule under the class whose remedy fits its
  ownership, and carries no destructive or contradictory co-finding.
- **P3** — The repo's written lore does not tell a future session that a "triggered by
  auth-*" email is automatically coincidental.
- **P4** — #4781's state matches reality: closed, with evidence.

### Cut List

- **Option 1 as written** (an audit-gate non-empty assertion). P1 is already bought, more
  strictly, by the fidelity probe.
- **Option 2 as written** (a `.tf` authority change). Done by #7650 for 3 rules. For
  `auth-per-user-loop` it is blocked on the provider (#7985).
- **New rows for native shapes A/B/C.** P1 is already caught. F35 below exists for P2, and
  it covers B as a side effect.
- **A silent `continue` for frozen names** (spec-flow). It is safe only while each frozen
  capture entry carries an excluded type. Nothing enforces that, so reclassification was
  chosen instead.
- **Hoisting the frozen-name derivation above the UNMANAGED loop** (DHH). Moving the
  UNMANAGED loop DOWN to sit after the derivation needs no split around the
  vendor-registry check and moves no refusal. The per-rule DRIFT loop stays above every
  refusal.
- **F36, the G4-16 reorder row, and a 13-row mutation matrix** (DHH, simplicity). These
  covered speculative shapes or a reorder this design no longer makes.
- **An ADR-031 amendment.** It adds nothing new.

### Relevant files and conventions

- `scripts/sentry-alert-live-fidelity.sh`:
  - per-rule loop at L261-362;
  - UNMANAGED loop at L364-374;
  - excluded-set lift at L413-427;
  - frozen-name derivation and refusals at L429-476;
  - frozen pin at L478-600;
  - epilogue at L630-632.
- `tests/scripts/test-sentry-alert-live-fidelity.sh`:
  - `EXPECTED_TESTS=67`, and the `_drift_case` helper (one marker per call);
  - F10 `t_unmanaged_new_rule` (L343);
  - F22;
  - registered in `scripts/test-all.sh:2908`.
  - Baseline: `=== 67 passed, 0 failed ===`, and the run takes more than 120 s.
- `tests/scripts/lib/sentry-alert-projection.jq`: **not edited**. `def excluded` stays as it
  is (guardrail).
- `.github/workflows/scheduled-sentry-alert-drift.yml` L196-205: the issue-body class guide.
  `tests/scripts/test-sentry-alert-drift-workflow.sh` does not pin its text (grep, measured).
- Learnings are dated records. They are corrected with an appended
  `> **Corrected 2026-09-23 (#4781) — …**` blockquote placed right after the claim, with the
  original left as written. That convention is already in use
  (`> **Superseded 2026-08-19 (#7590)`). Runbooks are living documents and are edited in place.
- Pre-push baselines, measured:
  - `bash scripts/lint-diagnosis-claims.sh` → `OK — 1 … (baseline 1)`;
  - `python3 scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"` → `OK`.
  - This plan edits no SKILL.md.

### Plan-time consults applied

- **SpecFlow:**
  - Replace the silent skip with reclassification.
  - Correct M3's expected RED.
- **Advisor:**
  - Keep the per-rule DRIFT loop above every refusal.
  - Treat the backtick bug as a class and add the `_drift_case` guard.
  - Cover a second frozen member.
- **DHH / simplicity:**
  - Move the loop instead of hoisting.
  - Cut F36, the G4-16 reorder row and most of the matrix.
  - Keep notes short.
  - Cut 2 notes.
  - Keep the `.tf` edit small.
- **CTO:**
  - Add the new class to the drift guide's FROZEN bullet.
  - Fix the stale comment in `apply-sentry-infra.yml`.
  - Put "how to check today" in the anchor note only.
  - The closing comment states its limits and cites the post-merge apply run.
- **Kieran** (fixtures run in the scratchpad; no P0):
  - The F35 fixture must use `map(if … else . end)`, not `map(select(…))`, and it gets a
    fixture-guard assertion.
  - F22 and F35 get their own `command not found` checks, and M2's red set is corrected.
  - The refusal-order trade is stated.
  - AC3 records the full red set.
- **Simplicity vs DHH/advisor conflict on the `_drift_case` guard:** kept. It is one line,
  and it covers the class the measured bug belongs to.

## Implementation Phases

### Phase 1 — RED

`tests/scripts/test-sentry-alert-live-fidelity.sh`, with `EXPECTED_TESTS` going 67 → **68**:

1. **`_drift_case` guard** (no count change): a row fails when `$_out` contains
   `command not found`.
2. **New row F35 `t_auth_rules_emptied_4781`.** This is the #4781 incident, plus the second
   frozen member. It is a custom function, because `_drift_case` takes one marker.
   - **Fixture:** `_mutant auth4781` with the program
     `map(if (.name | IN("auth-callback-no-code-burst", "auth-exchange-code-burst",
     "auth-signout-burst", "auth-per-user-loop", "sandbox-startup-failure")) then
     .triggers.conditions=[] | .actionFilters=[.actionFilters[]|.conditions=[]] else . end)`.
     Fail on `JQFAIL` or `NOOP`. Use `map(if … else . end)`, **not** `map(select(…))`: the
     `select` form deletes the other 26 workflows, and every assertion below would still pass
     on that wrong fixture (Kieran P1, measured).
   - **Assertions,** each a separate `grep -qF`:
     - `_rc == 1`;
     - fixture guard: no `DELETED or RENAMED`, and the header reads
       `comparing ${N} declared rule(s) against $((N + 2)) live in-scope rule(s)`. `N` is the
       suite's derived reference count; the two frozen copies now count as in scope.
     - for each of the 3 burst rules, `DRIFT: '<name>'.triggerConditions` and
       `DRIFT: '<name>'.actionFilters`;
     - `FROZEN DRIFT: 'auth-per-user-loop'.triggerConditions`;
     - for both frozen names, `FROZEN RULE LEFT SCOPE: '<name>'` present and
       `UNMANAGED: '<name>'` absent;
     - no `command not found`. This row bypasses `_drift_case`, so it needs its own check.
3. **F22** (custom row, no count change): add `! grep -qF 'command not found'`. F22 is the
   other row that emits UNMANAGED outside `_drift_case`.
4. **Tighten F10** (no count change): assert that the UNMANAGED finding contains the literal
   `` `def excluded` ``.

Run the suite in the background. Expected result: F35 and F10 RED (F10 also trips the
`_drift_case` guard), and every other row green.

### Phase 2 — GREEN

`scripts/sentry-alert-live-fidelity.sh`:

1. Escape the backticks on the UNMANAGED line (`` \`def excluded\` ``).
2. **Move the UNMANAGED loop down** so it sits after the `missing_cap` refusal (L476) and
   before the frozen pin (L478). `frozen_names_json` exists at that point. Inside the loop, a
   name that belongs to `frozen_names_json` emits
   **`FROZEN RULE LEFT SCOPE: '<name>'`** in place of `UNMANAGED:`. The message says:
   - the rule is Terraform-frozen (`legacy_trigger_conditions`, `ignore_changes = all`);
   - its live copy no longer carries an excluded trigger type, so the frozen-rule pin
     compares it and the reference does not;
   - do NOT delete it, and do NOT register it as a vendor default;
   - repair it per the `FROZEN …` findings for the same name (PUT from the capture entry).

   Wrap the name in `_safe`, and use no unescaped backticks. The loop's header comment gains
   one sentence covering the frozen arm. No refusal moves, and the per-rule loop stays above
   all of them.
3. Epilogue (L631): add one clause to the class list: "FROZEN RULE LEFT SCOPE is a
   Terraform-frozen rule whose live copy lost its excluded trigger: repair it from the
   capture, never delete it".

`.github/workflows/scheduled-sentry-alert-drift.yml`, one guide bullet (L200):

4. Add `` / `FROZEN RULE LEFT SCOPE` `` to the `FROZEN DRIFT / … / FROZEN DUPLICATE` class
   list, plus the clause "never delete it or register it as a default". A reader matching by
   exact class name then lands on the capture-PUT remedy, and not on UNMANAGED or GAINED
   (CTO).

Re-run the suite and expect **68 passed, 0 failed**. Then run the Guard Contract matrix and
revert each mutation.

### Phase 3 — Lore correction (docs)

For each of the six non-anchor learnings in the census, add a **2–3 line** blockquote right
after the claim, with the original text untouched:

> **Corrected 2026-09-23 (#4781):** this rule really fired. All four `auth-*` rules had
> empty trigger conditions and tag filters from 2026-05-17 to 2026-06-02 07:32Z and
> matched every issue in the project. See
> `bug-fixes/2026-06-02-sentry-auth-alert-rules-drifted-to-empty-filters-not-a-red-herring.md`.

Add a file-specific sentence only where the learning's own conclusion rests on the attribution:

- **warn-level debounce:** a `feature=feature-flags` event cannot match
  `feature=auth AND op=callback_no_code`. The debounce still bounds any rule that does match.
- **warning-level:** neither named rule's intended `op` matches `callback_provider_error`.
  `auth-per-user-loop` does match. "Level does not gate alert rules" stays true.

The **anchor** note is the only one that carries:

- the guard (the fidelity probe; the frozen pin for `auth-per-user-loop`);
- the limits: detection only for the frozen rule, repair is a capture PUT, and native
  restore waits on #7985;
- how to check today (the `workflows/` read already in its 2026-08-19 note);
- the list of corrected files.

Runbooks, edited in place:

- `cloud-scheduled-tasks.md` L468: the rule really fired because its filters were blank
  from 2026-05-17 to 2026-06-02 (#4781). Link the anchor.
- `oauth-probe-failure.md`:
  - the ownership row for `auth-per-user-loop` becomes "Terraform-frozen `sentry_alert`
    (`ignore_changes = all`); repair with a PUT from its capture entry";
  - the "Only `auth-per-user-loop` still declares `conditions_v2`/`filters_v2` as `[]` …"
    paragraph states the post-#8451 fact and cites the script's superseded header;
  - "(see #4781, still open)" becomes "(#4781; detected daily by
    `scripts/sentry-alert-live-fidelity.sh`)".
  - The blocked script recipe is left alone (#7634).

### Phase 4 — Stale comments (comment-only)

- `issue-alerts.tf`: delete the stale block (from "# Issue alerts for the auth observability
  stack" through its "(#4610)" box) and replace it with **3–4 lines**:
  - the three burst rules are Terraform-owned (`ignore_changes = [environment]`, #7650);
  - drift is caught by `scripts/sentry-alert-live-fidelity.sh`;
  - `auth-per-user-loop` is frozen (see its banner);
  - match by id, never by name.
  - No attribute changes, and `alert-reference.json` is not regenerated.
- `apply-sentry-infra.yml` L38-41: rewrite the sentence to say that the auth rules are
  `sentry_alert`, three owned outright and one frozen (`ignore_changes = all`), and that
  all of them plan as no-op under full-root.

### Phase 5 — Ship and close

- **PR #8654 body, first line** (sharp edge on infra diffs): "Merging this does not mutate
  production. The only `apps/web-platform/infra/sentry/**` change is a comment, and the
  push-to-main `apply-sentry-infra.yml` it triggers plans 0 changes and re-runs the live
  fidelity probe." The rest of the body carries `Closes #4781`, Measurements 1 and 2, the
  census, and the limits (see the anchor note).
- **Before every push:** the two operator-mandated lints,
  `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main`, and
  `npx markdownlint-cli2` on the edited `.md` files.
- **Deferral (file during /work):** open an issue for a parity check between the probe's
  finding classes and the drift guide's bullets (CTO P2). Without it, the next new class
  misses the guide the same way.
- **After merge:** once the push-to-main apply and its post-apply probe are green, post one
  comment on the (auto-closed) #4781 that cites that run and the limits.

## Files to Edit

- `scripts/sentry-alert-live-fidelity.sh`
- `tests/scripts/test-sentry-alert-live-fidelity.sh`
- `.github/workflows/scheduled-sentry-alert-drift.yml` (one guide bullet)
- `.github/workflows/apply-sentry-infra.yml` (comment only)
- `apps/web-platform/infra/sentry/issue-alerts.tf` (comment only)
- `knowledge-base/project/learnings/bug-fixes/2026-05-27-sentry-cron-community-monitor-missed-checkin.md`
- `knowledge-base/project/learnings/bug-fixes/2026-05-30-inngest-cron-desync-regression-needs-runtime-self-heal-not-ci-guard.md`
- `knowledge-base/project/learnings/bug-fixes/2026-06-01-best-effort-cron-monitor-liveness-not-success-and-offhost-visible-warn.md`
- `knowledge-base/project/learnings/bug-fixes/2026-06-02-sentry-auth-alert-rules-drifted-to-empty-filters-not-a-red-herring.md`
- `knowledge-base/project/learnings/best-practices/2026-05-29-uptime-monitor-fuse-must-tolerate-self-inflicted-deploy-windows.md`
- `knowledge-base/project/learnings/best-practices/2026-05-27-sentry-warning-level-still-triggers-alert-rules.md`
- `knowledge-base/project/learnings/2026-05-29-warn-level-debounce-for-recovered-fallback-sentry-floods.md`
- `knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md`
- `knowledge-base/engineering/operations/runbooks/oauth-probe-failure.md`

The pipeline also writes `knowledge-base/project/specs/feat-one-shot-4781-auth-alert-empty-filters/`
(`tasks.md`, session state) and may regenerate `knowledge-base/INDEX.md`.

## Files to Create

None.

## Non-Goals

- `tests/scripts/lib/sentry-alert-projection.jq` (`def excluded` untouched).
- The frozen rules' `.tf` blocks and live content (#7985).
- `configure-sentry-alerts.sh` and its write path (#7634).
- `scripts/sentry-create-gate.sh` L15: historical narrative, and correct as history.
- Siblings #6612, #8630, #6437, #8349, #8495, #7619, #3829, #6591, #7634 and #7985 are not
  absorbed.
- `knowledge-base/project/{plans,specs}/**`: point-in-time records.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` was checked against every file in
Files to Edit on 2026-09-23.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The indirect path is a
  bad UNMANAGED arm. If it swallowed an undeclared live rule, a paging rule that guards a
  user flow (`byok-art-33-breach`, or the auth bursts that page on OAuth breakage) could go
  dark unreported. The first user hit by that flow would then not reach the operator.
- **If this leaks, the user's data is exposed via:** nothing new. The probe's credential
  handling (token on stdin, destination pin, xtrace refusal) is unchanged, and findings
  print only rule names and configuration.
- **Brand-survival threshold:** `aggregate pattern`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `bash tests/scripts/test-sentry-alert-live-fidelity.sh` → `=== 68 passed, 0 failed ===`, exit 0.
- [ ] AC2: Before Phase 2, the same suite reports F35 and F10 FAILED and every other row
  passed. The RED output is quoted in the PR body.
- [ ] AC3: Every Guard Contract mutation reds the row it names, and was observed doing so
  (each one reverted). The PR body records the **full** red set for each mutation, including
  expected collateral (for example, M3 also reds F35, and M6's abort also reds F10 and F22),
  so a later reviewer can tell collateral from a regression.
- [ ] AC4: `git diff origin/main -- tests/scripts/lib/sentry-alert-projection.jq apps/web-platform/infra/sentry/alert-reference.json`
  is empty. In `issue-alerts.tf` and `apply-sentry-infra.yml`, every changed line is a
  comment or blank:
  `git diff -U0 origin/main -- <file> | grep -E '^[+-][^+-]' | grep -vE '^[+-][[:space:]]*(#|$)'`
  prints nothing.
- [ ] AC5: Each of the 7 learnings contains `Corrected 2026-09-23 (#4781)`, and
  `git diff --numstat origin/main -- <file>` shows 0 deleted lines for each (dated records
  are appended to, never rewritten).
- [ ] AC6: `cloud-scheduled-tasks.md` no longer contains
  `was coincidental (unrelated issue alert type)` and does link the anchor learning.
  `oauth-probe-failure.md` no longer contains `see #4781, still open`, and its
  `auth-per-user-loop` ownership row no longer names `configure-sentry-alerts.sh`.
  (Presence and exact-literal checks only. A corrected sentence can legitimately contain
  "not coincidental".)
- [ ] AC7: `scheduled-sentry-alert-drift.yml`'s guide contains `FROZEN RULE LEFT SCOPE`
  inside the FROZEN bullet, and `actionlint` passes on it.
- [ ] AC8: The pre-push lints pass: `lint-diagnosis-claims.sh` at or below baseline 1,
  `lint-skill-body-budget.py` OK, `lint-infra-no-human-steps.py --changed --base origin/main`
  OK, and `markdownlint-cli2` clean on the plan, `tasks.md` and every edited `.md`.
- [ ] AC9: CI `apply-sentry-infra.yml` `plan_pr` shows 0 resource changes, with a green
  reference gate.

### Post-merge

- [ ] AC10: The push-to-main `apply-sentry-infra.yml` run is green, and its post-apply
  probe prints `PASS (all N in-scope rules match …)`.
- [ ] AC11: #4781 is closed (via `Closes`), and it carries one comment that cites the AC10
  run and the limits (detection only for `auth-per-user-loop`; restore waits on #7985).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected. This is an infrastructure and tooling change: an
internal drift probe's finding classification, plus corrections to internal docs.

## Guard Contract

### Guard 1 — fidelity probe classification of the #4781 shape

**Property.** Any live state where a declared auth rule's triggers or tag filters are
emptied, or where a Terraform-frozen rule's live copy leaves the excluded-trigger scope,
exits with code 1. Each affected rule is named under a class whose remedy fits its ownership: `DRIFT` for
Terraform-owned rules; `FROZEN …` plus `FROZEN RULE LEFT SCOPE` for frozen ones. No finding
tells the reader to delete a Terraform-declared rule. No stray command runs while the report
is built.

**Assembly.** All finding text flows through the chokepoint `_finding` in
`scripts/sentry-alert-live-fidelity.sh`, whose callers are four emitters:

1. the per-rule loop;
2. the UNMANAGED loop, which gains the frozen arm;
3. the frozen pin's `FINDING` lines;
4. the hand-off reconciliation.

Frozen membership has one source, the `awk` derivation over `$FROZEN_TF_DIR/*.tf`. After
this change, emitters 2 and 3 both consume it. Scope membership comes from `in_scope` in
the projection module, which is unchanged.

**Mutation matrix.** Every mutation must turn the suite RED.

| # | Mutation | Expected RED row |
|---|---|---|
| M1 | Remove the frozen arm (frozen names fall through to `UNMANAGED:`) | F35 |
| M1b | Replace the frozen arm with a silent `continue` (the rejected design) | F35 (`FROZEN RULE LEFT SCOPE` absent) |
| M2 | Un-escape the backticks on the UNMANAGED line | F10 (the literal check and the `_drift_case` guard) and F22 (its own `command not found` check). F10 is the only `_drift_case` row that emits UNMANAGED (Kieran, measured) |
| M3 | Unconditional `continue` in the UNMANAGED loop | F10 and F22 |
| M4 | **Dispatch**: drop `t_auth_rules_emptied_4781` from the call list (leave `EXPECTED_TESTS=68`) | harness count check (`ran 67, expected 68`) |
| M5 | **Second member**: apply the frozen arm only to the first frozen name encountered | F35 (asserts both frozen names) |
| M6 | **Order**: move the UNMANAGED loop back above the frozen-name derivation | F35. The expected outcome is an abort under `set -u` (unset `frozen_names_json`), and either an abort or a fall-through reds F35 |

**Harness rows.**

- **H1 (a suite edit that must RED):** point F35's selector at a non-existent name. The
  `_mutant` landing check reports `NOOP` and F35 fails.
- **H2 (inputs that must PASS but are not canonical):** F1 identity, F13 (API-shaped payload)
  and G4-6 (frozen pin identity) stay green after Phase 2.

**Anchor.** The suite's reference is derived at run time from the committed capture, and
`EXPECTED_TESTS` is a reviewed literal. A weakening has to edit both the row and the literal
in one visible diff.

## Observability

```yaml
liveness_signal:
  what: "scheduled-sentry-alert-drift.yml run of scripts/sentry-alert-live-fidelity.sh, with a Sentry cron check-in (slug scheduled-sentry-alert-drift) that fires only for Inngest-dispatched runs"
  cadence: "daily (Inngest cron-sentry-alert-drift) + after every apply-sentry-infra.yml apply"
  alert_target: "GitHub issue labelled ci/sentry-alert-drift + priority/p1-high on a failing verdict; Sentry missed-check-in issue if the daily run does not start"
  configured_in: ".github/workflows/scheduled-sentry-alert-drift.yml; apps/web-platform/server/inngest/functions/cron-sentry-alert-drift.ts"

error_reporting:
  destination: "GitHub issue body (probe stdout verbatim, between fences) + workflow run log"
  fail_loud: "probe exits 1 and prints 'ERROR: sentry_alert live fidelity FAILED'"

failure_modes:
  - mode: "a Terraform-owned auth burst rule's triggers or tag filters emptied live"
    detection: "probe per-rule loop: DRIFT on triggerConditions / actionFilters"
    alert_route: "ci/sentry-alert-drift p1 issue; remedy re-run apply-sentry-infra.yml"
  - mode: "auth-per-user-loop (frozen) emptied or its trigger type changed live"
    detection: "probe frozen pin FROZEN DRIFT + FROZEN RULE LEFT SCOPE (no UNMANAGED co-finding after this change)"
    alert_route: "ci/sentry-alert-drift p1 issue; remedy PUT from the capture entry"
  - mode: "the probe itself does not run"
    detection: "Sentry cron monitor missed check-in for scheduled-sentry-alert-drift"
    alert_route: "Sentry issue → operator email"

logs:
  where: "GitHub Actions run logs for scheduled-sentry-alert-drift.yml and apply-sentry-infra.yml"
  retention: "GitHub Actions default log retention (90 days)"

discoverability_test:
  command: "bash scripts/sentry-alert-live-fidelity.sh"
  expected_output: "PASS (all"
  credentials_required: "Sentry IaC token (Doppler prd SENTRY_IAC_AUTH_TOKEN exported as SENTRY_AUTH_TOKEN, with SENTRY_ORG=jikigai-eu and SENTRY_API_HOST=jikigai-eu.sentry.io), read-only — the property is the LIVE content of the org's alert workflows, which no unauthenticated endpoint exposes"
```

## Encryption Posture

```yaml
# Triggered only by the comment-only edit to issue-alerts.tf. No persistent store and no
# new cross-component connection; the probe's HTTPS GET to jikigai-eu.sentry.io is unchanged.
at_rest: []
in_transit: []
```

## Test Scenarios

- **T1 (F35):** all four auth rules and `sandbox-startup-failure` emptied → rc 1.
  - DRIFT on both fields for each burst rule.
  - `FROZEN DRIFT` and `FROZEN RULE LEFT SCOPE` for `auth-per-user-loop`, and
    `FROZEN RULE LEFT SCOPE` for `sandbox-startup-failure`.
  - No UNMANAGED for either frozen rule.
- **T2 (F10):** an undeclared rule created in the UI → UNMANAGED, with the remedy text
  intact and no `command not found`.
- **T3:** F1, F13 and G4-6 still PASS.
- **T4 (optional, needs credentials):** the live read-only probe prints `PASS (all 31 …)`.

## Sharp Edges

- A plan whose `## User-Brand Impact` is empty or has no threshold fails `deepen-plan`
  Phase 4.6. It is filled in above.
- The suite takes over 120 s. Run it with `run_in_background`. A 2-minute tool timeout is not
  a test failure.
- `_run` merges stderr into `$_out`, and that is how defect 1 stayed hidden. The
  `_drift_case` guard makes stderr noise a failure.
- Do not fix defect 2 in the projection (`def excluded` or `in_scope`). The scope transition
  is legitimate, and the pin already classifies it. The fix belongs in the reporting.
- Reclassify, never silently skip. A skip is safe only while every frozen capture entry
  carries an excluded type, and nothing enforces that.
- After the loop moves, UNMANAGED lines print after four refusals: `excluded_def`
  (L418-427), the vendor registry (L444-448), zero frozen names (L459-462) and
  `missing_cap` (L464-476). A run that refuses on any of them shows no UNMANAGED lines.
  **This trade is accepted:** the refusal exits 1 and is the thing to fix first, and the
  per-rule DRIFT lines still print above every refusal. The rejected alternative is to
  hoist `tf_files` and the `awk` pass above L364. That works too, because neither depends
  on the registry check, but it splits a block for no gain in P1 or P2.
- Keep the new finding's remedy wording as "the `FROZEN …` findings for the same name",
  **without** a quoted `'<name>'` next to `FROZEN DRIFT`. Otherwise any
  `grep -c "FROZEN DRIFT: '<name>'"` count would be off by one.
- The `.tf` edit is comment-only, but the paths filter still triggers the push-to-main
  apply. That run is harmless and doubles as a live check. State this on the PR body's
  first line.
