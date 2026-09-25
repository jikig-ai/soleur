---
title: "fix(inngest-cutover): de-fang the op=verify missed-tick enumeration (unrunnable command, never-due re-fire lines)"
type: fix
date: 2026-09-25
slug: fix-cutover-missed-tick-defang
branch: feat-one-shot-6939-cutover-missed-tick-defang
issue: 6939
closes: 6939
priority: p1
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix(inngest-cutover): de-fang the op=verify missed-tick enumeration

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this
one-shot branch.)

## Enhancement Summary

**Deepened on:** 2026-09-25 (headless, one-shot).
**Sections enhanced:** Output contract, Runbook recovery procedure, Observability, Guard Contract
(both guards), Acceptance Criteria (AC4 and AC5), Test Scenarios, Sharp Edges, Plan Review
Disposition.
**Agents:** security-sentinel, test-design-reviewer, observability-coverage-reviewer,
git-history-analyzer, and a verify-the-negative / self-audit sweep (standard tier). This came after
a 7-seat plan-review panel and an advisor consult.

### Key improvements

1. **Validate operator- and host-supplied values; stripping them is not enough.** GitHub decodes
   `%0A` inside annotations, `date -d` accepts `tomorrow`, and `for fn in $(…)` globs. Window values
   must now match an ISO shape. Function ids are shape-filtered in jq, assigned first so `set -e`
   sees a failure, and read with `while read`.
2. **Guard 1 as first drafted would have passed vacuously.** `grep -E '--function-id|…'` is read as
   an option, and `|| true` plus `-eq 0` then passes on `''`. It now uses `-e` patterns, an exact
   `'0'` compare, and greps the real files, not the `$WF` view that drops the script preamble.
3. **The canonical ON case checks the exact sorted candidate set and the footer,** not just a count
   and a regex, which an off-by-one bucket range would satisfy. All three invalid-window arms are
   tested, and every rc check is exact.
4. **Every failure mode cites layer 6**, and there are new runtime failure modes. The runbook's
   Sentry step reads the check-ins API. `SENTRY_MONITOR_SLUG` replaces an invented `MONITOR_SLUG`.

### New considerations discovered

- `deploy-script-tests` (which hosts the suite) is **not** a required check on `main`, so a red
  guard is visible but does not block a merge.
- The verify arm's CI protection for the verdict is behavioural (the existing suite) plus a
  review-time `cmp` (AC6). There is no permanent byte-identity guard, by design (it would compare
  main with main after merge).

## Overview

The `op=verify` arm of the Inngest cutover prints a per-bucket "missed tick" list after its
double-fire verdict. That list has two defects (#6939):

1. **Every line is unrunnable.** It prints `soleur:trigger-cron --function-id <UUID> --missed-tick <TS>`.
   The trigger-cron skill accepts only `--list`, `--event cron/<name>.manual-trigger`, `--data`,
   and `--dry-run`. Nothing in the repo maps a function UUID to a cron name.
2. **Some lines are harmful.** The loop takes every function seen anywhere in the scan and lists
   every empty `CRON_PERIOD` bucket in the gap window. For a cron slower than `CRON_PERIOD`, most
   of those buckets were never due. Re-firing one causes the double-fire the cutover exists to
   prevent. The output cannot tell the real misses from the harmful ones.

This plan applies the fix the issue asks for first. The per-bucket output moves behind a new
`workflow_dispatch` boolean input, `missed_tick_candidates`, which defaults to **off**. The
opt-in output changes shape so no line can be pasted as a command. The default output becomes one
pointer to the correct recovery procedure. The double-fire verdict is not touched. The proper fix
(the registry probe reporting trigger type and a per-function period) cannot be done in this PR. It
is folded into the existing tracker #6940 rather than filed as a new issue.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #6939 / task brief) | Reality on `origin/main` | Plan response |
|---|---|---|
| The block lives in `.github/workflows/cutover-inngest.yml` | Since ADR-150 (#7002) the `run:` body is `scripts/cutover-inngest.sh`. The block starts at `# ---- Missed-tick auto-enumeration (P2-16)` in the `verify)` arm. The YAML only declares inputs and maps env. | Edit the **script** for behaviour. Edit the **YAML** for the new input and its env mapping only. |
| "ADR-143 § Deferred 2" | ADR-143 is now `ADR-143-active-active-web-ingress-drain-gated-host-lifecycle.md`. The cited ADR was renumbered to **ADR-146** (`ADR-146-trust-anchor-for-cutover-coexistence-window.md`). Its § Deferred item 2 is this defect, word for word. | Amend **ADR-146** § Deferred item 2. Do not touch ADR-143. |
| trigger-cron takes only `--event cron/<name>.manual-trigger` | Verified: `plugins/soleur/skills/trigger-cron/scripts/trigger.sh` parses `--list`, `--event`, `--data`, `--dry-run`, and checks `--event` against the allowlist derived from `cron-manifest.ts` (`trigger.sh:128-132`). | The pointer names the real form with a literal `<name>` placeholder. The allowlist rejects that placeholder, so copying it blindly fails safely. |
| No UUID→cron-name map exists | Verified: `inngest-registry-probe.sh` queries `functions { id }` only (`FUNCTIONS_GQL_QUERY`). `inngest-doublefire-probe.sh` returns `{id, functionID, status, queuedAt, startedAt, endedAt}`. Neither returns a slug, name, or trigger. | Candidate lines stay keyed by UUID and are labelled unmapped. Naming them is the proper fix (#6940). |
| The proper fix needs the registry probe to emit trigger type | It also needs (a) a cron-expression evaluator to decide which ticks were due (none in the repo; no `cron-parser`/`croner` dependency in `apps/web-platform/package.json`), and (b) a change to an on-host hook script, which only reaches production through a host hook-config redeploy. | Out of scope here: the brief allows no prod change and no host replace. Folded into #6940 item 1 with the extra scope written down. |

## Problem Statement

`scripts/cutover-inngest.sh`, `verify)` arm, after the 2.6 verdict (current `origin/main` text):

```bash
for fn in $(echo "$BODY" | jq -r '[.runs[].functionID] | unique | .[]'); do
  for (( b=FROM_BUCKET; b<=UNTIL_BUCKET; b++ )); do
    HAS=$(echo "$OBSERVED" | jq --arg fn "$fn" --argjson b "$b" 'any(.[]; .fn == $fn and .bucket == $b)')
    if [[ "$HAS" != "true" ]]; then
      TICK_TS=$(date -u -d "@$(( b * CRON_PERIOD ))" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo "bucket-$b")
      echo "  soleur:trigger-cron --function-id $fn --missed-tick $TICK_TS"
```

Three facts make this dangerous:

- The operator runbook (`knowledge-base/engineering/operations/runbooks/inngest-server.md`, the
  `op=verify` step and `### Bounded-outage note`) tells the operator to "Re-fire that list via
  `soleur:trigger-cron`". The list is presented as an instruction.
- The function set is `[.runs[].functionID] | unique` over the whole open-topped scan. That set
  includes event-driven functions and crons of any period.
- Among the crons that can be re-fired are three destructive or user-facing ones:
  `cron-workspace-gc`, `cron-rule-prune`, and `cron-action-required-sla`. The last one can send a
  duplicate notification to a user.

## Proposed Solution

### Output contract

*[Revised after plan review, 2026-09-25. The disposition is in `## Plan Review Disposition`.]*

The whole block moves into one top-level function, `missed_tick_report()`, in
`scripts/cutover-inngest.sh`. It sits beside the other helpers, before `case "$OP" in`. The
`verify)` arm calls it exactly once, **on one line**, after the `2.6 SCOPE CAVEAT` echo. The line is
about 120 characters, and keeping it whole is what lets AC3 pin it exactly (Kieran P1-2):

```bash
    missed_tick_report "${CUTOVER_MISSED_TICK_CANDIDATES:-}" "$BODY" "$CRON_PERIOD" "${CUTOVER_WINDOW_FROM:-}" "${CUTOVER_WINDOW_UNTIL:-}"
```

**The inputs are positional arguments, not env globals** (advisor consult). The suite drives the
ON/OFF matrix by passing arguments. The call site is the only place `CUTOVER_MISSED_TICK_CANDIDATES`
appears in the script, and one exact-line assertion pins it. `CUTOVER_WINDOW_FROM` is also read
by `doublefire_from()`, and that read is unchanged.

**The call is plain, with no `|| exit 1`.** Bash ignores `set -e` inside a function called from a
`||`/`&&` list, and inside anything that function runs. A trailing `|| exit 1` would therefore let
a `jq` crash inside the body carry on silently. A plain call keeps the `set -e` the inline block
has today. Each failure arm does an explicit `return 1`, and under the script's
`set -euo pipefail` that exits the run with status 1, the same as today's `exit 1`. (Known limit,
Kieran: a failing `jq` inside `for fn in $(jq …)` is invisible to `set -e` wherever the call sits.
The exact candidate counts in the Test Scenarios catch that.)

The definition line is **bare**, with the argument notes on a comment line above it. That keeps
the suite's `awk '/^missed_tick_report\(\) \{$/,/^\}$/'` extraction working, and matches
`g3_decide`/`flush_latch_decide`. A trailing comment on the definition line would make the
extraction come back empty (architecture P2-4, Kieran P1-1). A second comment line names the three
invisible couplings (CTO #6):

```bash
# args: $1 gate ("true" = ON)  $2 body-json  $3 cron-period-s  $4 win-from  $5 win-until
# DO NOT RESHAPE: the P2-16 header below is ADR-106's content anchor; the OBSERVED jq call must keep
# its `jq -c --argjson period "$CRON_PERIOD"` shape (the suite's perl extractor + null harness).
missed_tick_report() {
  local BODY="$2" CRON_PERIOD="$3"
  # ---- Missed-tick auto-enumeration (P2-16)
  if [[ "$1" != "true" ]]; then  # OFF: the default
```

The gate is a strict string compare. The boolean input only ever sends `true` or `false`, and
anything that is not exactly `true` means OFF.

**Input hygiene (P7). Validate; do not just strip.** *[Deepened 2026-09-25, security-sentinel]*
Stripping CR/LF is not enough, for three reasons. GitHub decodes `%0A`/`%0D`/`%25` inside an
annotation message, so a value carrying `%0A…` renders a fake second line inside the one notice
that says "recover ONLY via…". `date -u -d` accepts natural language (`tomorrow`). And the host's
function ids pass through shell word-splitting and globbing (`for fn in $(…)`), where an id of `*`
expands to file names. Apply these rules instead:

- **Window values.** A value is used (printed or passed to `date -d`) only when it matches
  `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`. In OFF, a non-matching value prints as
  `<invalid>`, is never parsed, and the return is still 0. In ON, a non-matching value takes the
  invalid-window arm (rc 1, "verdict above STANDS").
- **Function ids.** Select them in jq, not in the shell, and assign the result before looping, so
  `set -e` sees a jq failure (observability P2-3):
  `FNS=$(jq -r '[.runs[].functionID | select(type == "string" and test("^[A-Za-z0-9._-]{1,128}$"))] | unique | .[]' <<<"$BODY")`,
  then `while IFS= read -r fn; do …; done <<<"$FNS"`. Count the ids that were dropped, and if any
  were dropped print `::warning::missed-tick candidates: N function id(s) failed the shape check and
  were skipped`.
- The OBSERVED jq program is **not** touched (AC8). Only the function-set expression changes, and a
  UUID or the fixture ids `fn-h`/`fn-d`/`fn-q` all pass the shape check, so the counts of 4 and 7
  stand.

| State | Window parsed? | Prints | Return |
|---|---|---|---|
| **OFF** (default; anything except `true`) | **No.** A malformed `CUTOVER_WINDOW_*` cannot redden a clean verdict run. | One short `::notice::` pointer (text below), with the raw window values echoed but not parsed. **No line contains a function id.** | `0`, always |
| ON, window not supplied | No | `::warning::` saying candidates were requested but `CUTOVER_WINDOW_FROM` and `CUTOVER_WINDOW_UNTIL` are not both set | `0` |
| ON, window invalid, or span outside `[1,10000]` | Yes | `::error::` that names the bad window **and states that the exactly-once verdict above STANDS**, so only the opt-in list failed | `1` (same as today's `exit 1`) |
| ON, window valid | Yes | An UNVERIFIED `::warning::` header, then one line per empty (function, bucket) pair, then a `::notice::` count footer | `0` |

**ON candidate line format:** two leading spaces, then
`candidate function_id=<uuid> empty_bucket_start=<YYYY-MM-DDTHH:MM:SSZ>` (AC5 pins it by regex).

**OFF pointer.** This is the only thing the default prints. It is deliberately short: DHH, CTO and
simplicity all flagged that a 900-character essay inside one annotation would drift from the
runbook and get skimmed. The recovery procedure lives **only** in the runbook, so it has a single
source. The pointer contains no cron names (CTO #2, drift) and no command. It has no double quotes
and no apostrophes (Kieran P2-5):

> `::notice::missed-tick candidates NOT EMITTED (default, #6939). A per-bucket list cannot tell a tick that was due from one that was never due, and re-firing a never-due tick double-fires that cron. Gap window as configured: [<from>, <until>]. A tick skipped in the gap is the accepted ADR-100 residual. Recover one ONLY via knowledge-base/engineering/operations/runbooks/inngest-server.md § Bounded-outage note. Unverified per-bucket candidates: re-dispatch op=verify with missed_tick_candidates=true. Proper fix: #6940.`

**ON header.** Each line is a (function UUID, `${CRON_PERIOD}s` bucket) inside the window with no
run. The header says the list is NOT a re-fire list. It says a line may be any of three things: an
event-driven function; a cron slower than `${CRON_PERIOD}s` that was never due in that bucket; or,
for a cron faster than `${CRON_PERIOD}s` (for example `cron-ghcr-token-minter`, every 20 minutes),
a bucket with a run that can still hide a miss (spec-flow P2-6). It also says UUIDs have no in-repo
name mapping. It points to the same runbook section.

The ON candidate lines contain no `soleur:` token and no `--` flag, so pasting one into a shell does
nothing useful. The OBSERVED jq program moves into the function with its invocation shape intact
(`local BODY CRON_PERIOD` binding). The suite's null-`startedAt` harness keeps counting and
executing it as the third `fromdateiso8601` site without edits (AC8).

### Runbook recovery procedure (the single source)

`### Bounded-outage note` in `knowledge-base/engineering/operations/runbooks/inngest-server.md`
replaces "`op=verify` enumerates them for `soleur:trigger-cron` re-fire" with the steps below.
Spec-flow P0-1 applies here: the default must be safe when step 2 cannot be done.

1. **Default: do nothing.** A tick skipped in the quiesce→register gap is ADR-100's accepted
   bounded residual, and the cron's next scheduled tick runs normally.
2. Re-fire only when a skipped tick matters **and** all three checks hold:
   - (a) The cron's schedule (the `{ cron: }` trigger in `apps/web-platform/server/inngest/functions/cron-<name>.ts`)
     placed a tick strictly inside the gap window printed by op=verify. A function with no `{ cron: }`
     trigger is event-only and is never missed.
   - (b) The cron's Sentry monitor shows a **missed** check-in for that tick. The slug is the
     `SENTRY_MONITOR_SLUG` constant in `cron-<name>.ts`, which is not always `cron-<name>` (for example,
     `cron-workspace-gc` uses `scheduled-workspace-gc`). Check it only after the tick time plus the
     monitor's `checkin_margin_minutes` in `apps/web-platform/infra/sentry/cron-monitors.tf`
     (spec-flow P1-3). Read it through the API rather than a dashboard
     (`hr-no-dashboard-eyeball-pull-data-yourself`). This is the same read
     `knowledge-base/engineering/operations/runbooks/github-app-drift.md` uses:
     `curl -s -H "Authorization: Bearer $SENTRY_AUTH_TOKEN" "https://de.sentry.io/api/0/organizations/jikigai-eu/monitors/<slug>/checkins/?limit=10" | jq -r '.[] | "\(.dateCreated) \(.status)"'`.
     **If the cron has no monitor, no-run cannot be confirmed, so do not re-fire.**
   - (c) Only then run `soleur:trigger-cron --event cron/<name>.manual-trigger`.
3. Take particular care with the destructive or user-facing crons (`cron-workspace-gc`,
   `cron-rule-prune`, `cron-action-required-sla`). This is the one place those names are written.

The op=verify step text drops "It also auto-emits the missed-tick `soleur:trigger-cron` list … Re-fire
that list" and replaces it with the default pointer plus the opt-in input.

### Why this option (the least harmful of the three the brief names)

| Option for the default (OFF) state | Harm if an operator acts on it | Chosen |
|---|---|---|
| A. Keep a per-function list but print it in the runnable `--event cron/<name>…` form | Impossible to build: no UUID→name map. If it could be built, it would still list never-due ticks, now in a form that **runs**, so the double-fire gets easier. | No |
| B. Print nothing | Safe, but the operator loses the recovery path the runbook promises for real gap misses. They end up guessing or reaching for SSH. | No |
| **C. No list; one short pointer to the runbook procedure, which gives the correct form with a `<name>` placeholder behind a fail-safe due-check** | The script prints no runnable form at all. The runbook's form needs the operator to open the cron's schedule to fill in `<name>`, and the due-check happens there. A blind paste fails at trigger.sh's allowlist. With no monitor to confirm no-run, the default is not to re-fire. | **Yes** |

The opt-in arm is kept (CTO: "justified, but only just"). For any cron whose period equals
`CRON_PERIOD` (the hourly crons at the 3600 s default), an empty bucket in the gap really is a
miss. The ON arm keeps that signal without printing anything that looks like a command.

### Workflow YAML

Add under `on.workflow_dispatch.inputs` (next to `cron_period_seconds`):

```yaml
      missed_tick_candidates:
        description: "op=verify only: print the UNVERIFIED per-bucket missed-tick candidates (#6939). NOT a re-fire list — see the run's notice before re-firing anything."
        required: false
        type: boolean
        default: false
```

Add to the step `env:` block (the only place the value enters; never interpolated into `run:`):

```yaml
          # #6939 — opt-in, UNVERIFIED missed-tick candidates for op=verify. Boolean input → the
          # string "true"/"false"; the script's gate is a strict == "true", so anything else is OFF.
          CUTOVER_MISSED_TICK_CANDIDATES: ${{ inputs.missed_tick_candidates }}
```

Update **both** stale YAML comments (Kieran P2-7, architecture P2-3) to say the window bounds the
**opt-in** candidate list in `missed_tick_report()`. They are the `CUTOVER_ANCHOR_FROM` comment
("that variable also means the quiesce→register gap START to the missed-tick auto-enumeration") and
the `CUTOVER_WINDOW_FROM`/`UNTIL` comment ("drive the missed-tick auto-enumeration (P2-16, below)").
Update the matching `doublefire_from()` comment in `scripts/cutover-inngest.sh` the same way.
**Neither YAML comment may contain the string `inputs.missed_tick_candidates`**, or the AC2 and
discoverability count becomes 2. **Keep both mappings.** `doublefire_from()` still reads `CUTOVER_WINDOW_FROM` as its last-resort anchor
(`scripts/cutover-inngest.sh`, the `if [[ -z "$anchor_e" && -n "${CUTOVER_WINDOW_FROM:-}" ]]`
branch), and suite assertion `#6919 workflow maps CUTOVER_WINDOW_FROM` pins it.

## Alternative Approaches Considered

| Alternative | Why not |
|---|---|
| Delete the block outright, with no input | Loses the correct hourly-cron signal. It would also break the suite's `#6178 at least 3 bucketing sites` census and leave ADR-106's content anchor pointing at nothing. The issue prefers the gate. |
| Infer each function's cadence from its own observed runs (for example, the gap between successive buckets) | A heuristic that looks confident: event-driven functions have irregular gaps, and a slow cron seen once has no cadence. This is the false-confidence shape the issue warns about. Cut. |
| Registry probe emits `slug` + `triggers { type value }`, plus a cron evaluator (the proper fix) | Needs an on-host hook script change and a host hook-config redeploy, which the brief forbids, and there is no cron parser in the repo. Folded into #6940 item 1 (Phase 4 of this plan). |
| Replace the per-bucket bash loop (one `jq` spawn per bucket per function) with a single jq program | Only matters when the list is opted into (it is capped at 10000 buckets). It would also change the OBSERVED program the null-safety harness executes. Not worth the churn here. |

## Research Insights

**Premise Validation.** #6939 is OPEN, with no closing PR and no comments (labels `priority/p1-high`,
`type/bug`, `domain/engineering`; milestone "Phase 4: Validate + Scale"). #6940 is OPEN, has no
comments, and its item 1 says the proper fix is "blocked on extending `inngest-registry-probe.sh` to
emit trigger type". PR #6933 (#6178) MERGED 2026-07-26. What held: the defect text matches `origin/main`
exactly (`scripts/cutover-inngest.sh`, `echo "  soleur:trigger-cron --function-id $fn --missed-tick
$TICK_TS"`). What was stale: the file location (the ADR-150 extraction moved it into the script) and
the ADR number (143 → 146). The brief's capability claims about trigger-cron were checked
against `trigger.sh` itself, not against a consumer.

**Provenance (verified at deepen, git-history-analyzer).**

- The P2-16 block was introduced by `bae1fbebf7` (Phase-2 op=execute cutover, Ref #6178, 2026-07-08) and later touched by `957350d82d` (#6218). It was not introduced by #6933.
- The body was extracted into the script by `67820a4403` (#7002 / ADR-150).
- Suite path coverage for the script comes from `4436ba24ca` (#8079).
- The ADR was renumbered 143 → 146 by `7071166a5a`, after #6919 claimed 143.

**Property List (Phase 0.6b).**

- P1: No line that op=verify (or any op) prints contains a trigger-cron flag the skill does not accept.
- P2: With the default settings, op=verify prints no per-function missed-tick line.
- P3: The double-fire verdict of op=verify is unchanged: same checks, same output, same exit status.
- P4: An operator with a real gap miss has a correct, safe pointer to the recovery procedure.
- P5: The empty-bucket candidate data is still available to an operator who explicitly asks for it,
  labelled as unverified and not shaped like a command.
- P6: The default run's exit status depends on the verdict alone. A malformed `CUTOVER_WINDOW_*`
  cannot redden it.
- P7 (added at plan review): no operator- or host-supplied value (window vars, function ids) can
  forge an extra annotation line.

**Cut List (Phase 0.6b).**

- Cadence inference from observed runs → P2/P4 → cut. The pointer's schedule check covers P4
  without guessing.
- Vectorising the jq loop → no property (performance, ON only) → cut.
- A per-function runnable `--event` list → P4 → impossible (no name map). The `<name>`-placeholder
  pointer covers it.
- New tracking issue for the proper fix → covered by #6940 (comment adds scope; the brief says do
  not file a new one).
- (Plan review) The long OFF pointer procedure in the script → P4 → covered by the runbook's
  `§ Bounded-outage note`, which is now the single source. Cut to a short pointer.
- (Plan review) AC6b byte-identity `cmp` of the OBSERVED program → no property → AC8 already runs
  the program against fixtures. Cut.
- (Plan review; reversed at deepen) Gate values `TRUE`/`1`/`yes` were cut, then `TRUE`, `1` and a
  trailing-space `true` were restored, because they kill a loose-gate mutation (test-design).
- (Plan review) A per-cron suite test that every scheduled cron has a Sentry monitor (spec-flow P0-1
  fix option) → P4 → covered by the runbook's fail-safe default ("no monitor → do not re-fire"). Cut.

**Relevant files.**

- `scripts/cutover-inngest.sh` — `verify)` arm; `# ---- 2.6 exactly-once double-fire check`; `# ---- Missed-tick auto-enumeration (P2-16)`; helper block ends before `case "$OP" in`.
- `.github/workflows/cutover-inngest.yml` — `cron_period_seconds` input (precedent for a dispatch input mapped into env), step `env:` block, `CUTOVER_WINDOW_FROM/UNTIL` comment.
- `apps/web-platform/infra/cutover-inngest-workflow.test.sh` — `$WF` reconstruction (YAML + script re-indented 10 spaces); line-207 assertion `verify auto-emits the missed-tick trigger-cron list (P2-16)` (it greps `soleur:trigger-cron`, which the new OFF pointer would also satisfy, so it is vacuous under this change); `VERIFY_ARM_FILE` comment-stripped arm extraction; `BUCKET_PROGS` perl extraction plus `BUCKET_SITE_N` exact count and the `-ge 3` floor; the `else` branch that runs the OBSERVED program against `NULL_FIXTURE` (expects 4 pairs); `OP_REFS` injection-safety pattern (exactly one `${{ inputs.op` ref); the awk-extract-and-execute pattern for helpers (`g3_decide`, `flush_latch_decide`, `resume_liveness_decide`).
- `.github/workflows/infra-validation.yml` — step "Run cutover-inngest.yml workflow tests"; `paths:` already covers `.github/workflows/cutover-inngest.yml` and (since #8079) the extracted script.
- Boolean-input precedents: `.github/workflows/workspaces-luks-cutover.yml` (`dry_run`/`rollback`/`clean_stray`, mapped to env, consumed as `[[ "$X" == "true" ]]`); `git-data-rung2-rehearsal.yml`.
- `plugins/soleur/skills/trigger-cron/scripts/trigger.sh` — flag parser and allowlist check.
- `apps/web-platform/infra/inngest-registry-probe.sh` (`FUNCTIONS_GQL_QUERY='query RegistryProbe { functions { id } }'`), `apps/web-platform/infra/inngest-doublefire-probe.sh` (node projection).
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — op=verify step ("It also auto-emits the missed-tick `soleur:trigger-cron` list … Re-fire that list via `soleur:trigger-cron`.") and `### Bounded-outage note` ("`op=verify` enumerates them for `soleur:trigger-cron` re-fire.").
- `knowledge-base/engineering/architecture/decisions/ADR-146-…` § Deferred item 2; `ADR-106-…` content-anchors the block by its header comment `# ---- Missed-tick auto-enumeration (P2-16)`, so **keep that header line verbatim**.

**Current suite baseline.** `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` → 914 PASS, 0 FAIL (repo-research run, 2026-09-25).

**Institutional learnings applied.**

- `2026-04-18-fabricated-cli-commands-in-docs.md`: when a command can't be verified, printing nothing beats printing an invalid one. That is why no candidate line is command-shaped.
- `2026-09-25-a-proof-by-absence-close-on-a-flag-gated-surface-proves-nothing.md`: a flag-gated surface needs both arms *executed* in tests, not just read. Hence the behavioural ON/OFF cases against the extracted function.
- `2026-09-19-every-fix-for-a-silent-drop-was-itself-a-silent-drop.md`: advisory output must not decide the exit status. Hence P6 and the OFF arm never parsing the window.
- `best-practices/2026-07-09-phased-feature-enforce-disabled-mode-by-hard-stop-not-process-gate.md`: off means the loop does not run, not that it runs and hides its output.
- `2026-05-09-llm-authored-plans-cite-fabricated-and-retired-rule-ids.md`: the ADR-143 → ADR-146 renumber was checked against the file system.
- `best-practices/2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`: the tests trace input → env mapping → gate → call site, not only the function.
- `2026-08-01-my-mutation-battery-inferred-the-verdict-from-the-input-under-test.md`: every behavioural case sets the gate value itself, and its expected output comes from the fixture, never from the gate value.

**External research.** Skipped. The codebase has strong local patterns (boolean dispatch inputs,
awk-extract-and-execute harness), and the change touches no external API.

**Community / functional overlap.** functional-discovery searched 3 registries and found no overlap
(only generic GitHub Actions tooling). Nothing was installed. No uncovered stack.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (200 issues) was searched for
`scripts/cutover-inngest.sh`, `.github/workflows/cutover-inngest.yml`,
`apps/web-platform/infra/cutover-inngest-workflow.test.sh`, `ADR-146`, and
`runbooks/inngest-server.md`. There were zero matches.

## Files to Edit

| File | Change |
|---|---|
| `scripts/cutover-inngest.sh` | Add top-level `missed_tick_report()` (contract above). Replace the inline block in `verify)` with one call. Rewrite the block's explanatory comment (keep the first line `# ---- Missed-tick auto-enumeration (P2-16)` verbatim for ADR-106's anchor). Remove every `--function-id`/`--missed-tick` token, including in comments. Update the `doublefire_from()` comment that names the missed-tick auto-enumeration. |
| `.github/workflows/cutover-inngest.yml` | Add the `missed_tick_candidates` boolean input (default `false`). Add the `CUTOVER_MISSED_TICK_CANDIDATES` env mapping. Update the `CUTOVER_ANCHOR_FROM` and `CUTOVER_WINDOW_FROM/UNTIL` comments; neither may contain `inputs.missed_tick_candidates`. |
| `apps/web-platform/infra/cutover-inngest-workflow.test.sh` | Replace the line-207 assertion. Add the Guard 1 and Guard 2 assertions and the behavioural cases (Test Scenarios). Update the `-ge 3` description text only (the count stays). |
| `knowledge-base/engineering/operations/runbooks/inngest-server.md` | op=verify step: replace "auto-emits … Re-fire that list" with the new default pointer plus the opt-in input. `### Bounded-outage note`: replace "enumerates them for `soleur:trigger-cron` re-fire" with the procedure in "Runbook recovery procedure" above. This is its single source. |
| `knowledge-base/engineering/architecture/decisions/ADR-146-trust-anchor-for-cutover-coexistence-window.md` | § Deferred: correct the header count ("All three are tracked by #6940"; the section lists four). Add a dated "Interim de-fang landed" note to item 2. Add a **new, separate** item 5 for the #6939 proper fix, with its own re-check condition. |
| `knowledge-base/engineering/architecture/decisions/ADR-106-inngest-cutover-preflight-scan-bounding-and-in-surface-marker.md` | One dated sentence where the Decision item 4 text places the P2-16 block "in the `op=verify` arm of `cutover-inngest.yml`". Since ADR-150 the block lives in `scripts/cutover-inngest.sh`, and since #6939 it sits in `missed_tick_report()` and is opt-in. The anchor text itself is unchanged. |

## Files to Create

None.

## Implementation Phases

### Phase 1 — RED: tests first (`cq-write-failing-tests-before`)

1.1 In `cutover-inngest-workflow.test.sh`, delete the assertion `verify auto-emits the missed-tick
trigger-cron list (P2-16)` (it greps `soleur:trigger-cron` anywhere, and the new OFF pointer would
satisfy it too).

1.2 Add Guard 1 (nonexistent-flag absence), Guard 2 (default-OFF gate) and the workflow-shape
assertions exactly as the Guard Contract and Test Scenarios specify. Extract `missed_tick_report()`
with the suite's pattern `awk '/^missed_tick_report\(\) \{$/,/^\}$/' "$BODY_SH" > "$MTR_FN"`
(register it in `SCRATCH`). Run each case **without an `||` or `&&` context**, so the errexit
semantics match the production call:

```bash
set +e
( set -euo pipefail; source "$MTR_FN"; missed_tick_report "$gate" "$body" 3600 "$from" "$until" ) \
  > "$MTR_OUT" 2>&1
rc=$?
set -e
```

Do **not** write `out=$(…) || rc=$?`. The `||` turns off `set -e` inside the subshell, so a case
would pass on a function whose own errexit is broken.

1.3 Run the suite. The new assertions must be RED against the unchanged SUT (the function does not
exist yet; the flags are still printed; the input is missing). Record the RED count.

### Phase 2 — GREEN: implementation

2.1 Script: add `missed_tick_report()`, move the block into it, apply the output contract, and
replace the inline block with the single call. The 2.6 verdict code stays byte-identical. A
diff-scope check at the end of Phase 3 confirms this.

2.2 YAML: add the input and the env mapping. Update the comment.

2.3 Run the suite until GREEN, with the pre-change count plus the new assertions and zero FAIL. Also
run `actionlint .github/workflows/cutover-inngest.yml` if it is installed (infra-validation runs
it), and `bash -n scripts/cutover-inngest.sh`.

### Phase 3 — Docs + ADR

3.1 Runbook edits (Files to Edit). The OFF pointer names `§ Bounded-outage note`. Keep that heading
text unchanged so the pointer resolves.

3.2 ADR-146 § Deferred amendment (Architecture Decision section).

3.3 Check that the verdict did not change (Kieran P1-3; a hunk-range check fails on diff context).
Cut the range from `# ---- 2.6 exactly-once double-fire check` through the `2.6 SCOPE CAVEAT` echo
out of both trees, strip leading whitespace, and compare the two with `cmp`. The exact command is
AC6.

### Phase 4 — Tracker hand-off (no new issue)

4.1 `gh issue comment 6940` adds the #6939 proper fix as a **new, separate item**. Item 1 is
slow-cron discovery, and folding this into it would mix two fixes (architecture P1-2). The new item
says:

- the registry probe must return `slug` and `triggers { type value }`, not just `id`;
- a per-function period or cron-expression evaluator decides which ticks in
  `[CUTOVER_WINDOW_FROM, CUTOVER_WINDOW_UNTIL]` were due;
- only then may op=verify print named `soleur:trigger-cron --event cron/<name>.manual-trigger` lines,
  filtered to due ticks with no run.

Its re-check condition is keyed to something that will actually happen: **before the next production
op=verify dispatch against a newly cut-over dedicated host, whatever `missed_tick_candidates` is set
to** (architecture P1-1). The old condition, "a cutover that uses missed-tick enumeration", can no
longer fire now that the list is off by default. The comment also names the interim state, so nobody
switches the input on expecting a re-fire list. Moving #6940's milestone or priority is left to the
operator (see `decision-challenges.md`).

4.2 PR body: `Closes #6939` (body, not title, per `wg-use-closes-n-in-pr-body-not-title-to`) and
`Ref #6940`.

## Plan Review Disposition

A 7-seat panel ran on 2026-09-25 (headless): DHH, Kieran, code-simplicity, architecture-strategist,
spec-flow-analyzer, and named CTO (devex) and CPO (plan-time sign-off, above). An advisor consult
ran at Step 4.5.

**Applied (mechanical):**

- Bare definition line, so the awk extraction works (Kieran P1-1, architecture P2-4).
- One-line call pinned by `grep -cxF` (Kieran P1-2).
- AC6 rewritten as an awk-cut plus `cmp` (Kieran P1-3); the command was dry-run on this branch
  (`rc=0`, 154 lines).
- The unset case collapsed into `""` (Kieran P2-4).
- No quotes or apostrophes in the pointer (Kieran P2-5).
- ADR-106 dated sentence, plus the second YAML comment and the `doublefire_from()` comment (Kieran
  P2-6/P2-7, architecture P2-3).
- ADR-146: a separate item 5 with a reachable re-check condition, and the header count corrected
  (architecture P1-1/P1-2).
- The OFF pointer shortened, with the procedure moved into the runbook as the single source and no
  cron names in the script (DHH P1-2, CTO #1/#2, simplicity).
- A fail-safe runbook default of "no monitor means do not re-fire", the `SENTRY_MONITOR_SLUG` lookup and the
  check-in margin timing (spec-flow P0-1, P1-3).
- Raw window values printed in the pointer (spec-flow P1-2).
- A faster-than-bucket note in the ON header (spec-flow P2-6).
- The magic line-count floor replaced by an anchor check (CTO #5).
- A table-driven OFF loop (CTO #3).
- A comment on the 7-count (CTO #4) and a "do not reshape" comment (CTO #6).
- Positional arguments and a plain call (advisor).

**Cut (simplification, mechanical):**

- AC6b `cmp` of the OBSERVED program (DHH, simplicity; AC8 executes it).
- `TRUE`/`1`/`yes` gate cases (DHH, simplicity). *Reversed by the deepen pass: `TRUE`, `1` and a trailing-space `true` were restored (see below).*

**Kept against a cut recommendation, each with the mutation it kills:**

- The 7-count null case (simplicity asked to cut it). It kills a silent `jq` failure inside
  `for fn in $(jq …)`, which neither `set -e` nor AC8 sees.
- The reorder/line-order assertion (simplicity asked to cut it). It kills a move of the call above
  the `DUPES` check, where an ON-arm `return 1` would pre-empt the verdict. That breaks P3.
- The full-coverage must-PASS case. It is required by the Guard Contract (Phase 2.12 item 4), which
  needs a must-PASS row that is not the canonical input.

**Refuted:**

- Spec-flow P1-4 said the watchdog might already have re-fired the tick. It does not:
  `cron-inngest-cron-watchdog.ts` says it "no longer reads the registry, fires manual-triggers, or
  restarts". It is a liveness beacon.
- Spec-flow P2-6 named `cron-inngest-config-drift` as event-only. The files with no `{ cron: }` are
  `cron-gh-pages-cert-reissue.ts` and `cron-gh-pages-cert-state.ts`, so the runbook states the rule
  ("no `{ cron: }` trigger → event-only") rather than a list.

**Declined, with rationale:**

- Spec-flow P0-1 fix option (a suite test that every scheduled cron has a monitor or an entry on an
  "unconfirmable" list). The fail-safe default already makes a cron with no monitor safe, and a
  census test would add upkeep on every new cron.
- DHH P2-7 (cut the Observability, C4 and Guard Contract sections). Those sections are
  gate-mandated at this threshold.

**Deepen pass (2026-09-25)** — security-sentinel, test-design-reviewer, observability-coverage-reviewer,
git-history-analyzer and a verify-the-negative sweep. Applied:

- Window values validated against an ISO shape, and function ids validated by shape in jq, then read
  with `while read` (security P2-1..4). This replaces CR/LF stripping as the P7 mechanism.
- Guard 1 now greps `$BODY_SH` and `$WF_YAML` directly with `-e` patterns and an exact `'0'`
  compare, because a bare `-E '--…'` passes vacuously (test-design).
- The canonical case compares the exact sorted set and the footer; all three invalid-window arms are
  tested; rc checks are exact; P7 cases for `\r`, `%0A`, `$5` and function ids are added; the table
  loop runs outside any `if`/`||` (test-design).
- `TRUE`, `1` and `true` with a trailing space are **restored** as OFF cases. Test-design showed that a `== true*` or
  `-n && != false` gate survives with only `""`/`false`. This overrides the plan-review cut, and in
  a table loop each case costs one row.
- Every failure mode now has a layer-6 citation, and there are new runtime failure modes (ON invalid
  window, function-id shape skips). The runbook step (b) reads Sentry through the check-ins API, not a
  dashboard (observability).
- The "required CI" claim is corrected: `deploy-script-tests` is not in the main ruleset's required
  contexts (read with `gh api repos/jikig-ai/soleur/rules/branches/main`).
- The constant is `SENTRY_MONITOR_SLUG`, not `MONITOR_SLUG`, and the "only place the env names
  appear" claim is now scoped to `CUTOVER_MISSED_TICK_CANDIDATES` (sweep).

**Surfaced to the operator (taste / user-challenge) in
`knowledge-base/project/specs/feat-one-shot-6939-cutover-missed-tick-defang/decision-challenges.md`:**

- DHH P1-1: delete the ON arm entirely. This challenges the issue's stated direction, so it is a
  user-challenge.
- Architecture P1-1: move #6940 or its new item to Phase 4 / p1.

## User-Brand Impact

- **If this lands broken, the user experiences:** a founder running the cutover is again shown
  re-fire lines for ticks that were never due. Acting on one double-fires a cron: a duplicate
  `cron-action-required-sla` notification email to a user, or a second `cron-workspace-gc` /
  `cron-rule-prune` sweep over a user's workspace or rules.
- **If this leaks, the user's data is exposed via:** no new vector. The output is function UUIDs and
  bucket timestamps only (AC-NOBODY holds), the input is a boolean, and it reaches the shell only
  through `env:`, never interpolated into `run:`.
- **Brand-survival threshold:** `single-user incident` (inherited from ADR-146, the op=verify
  surface's ADR; confirmed by CPO: one wrong re-fire harms one user).
- `soleur:engineering:review:user-impact-reviewer` runs at review time (review skill conditional
  block). CPO sign-off: **approved** at plan time (Domain Review below).

## Observability

```yaml
liveness_signal:
  what: "the op=verify run log's ::notice::missed-tick candidates line (OFF) or its ::warning:: UNVERIFIED header (ON), printed once per dispatch"
  cadence: "per operator dispatch of cutover-inngest.yml op=verify (no schedule; the cutover is operator-triggered)"
  alert_target: "the dispatching operator via GitHub Actions run annotations; a red run conclusion on ON + invalid window"
  configured_in: "scripts/cutover-inngest.sh missed_tick_report(); .github/workflows/cutover-inngest.yml step env CUTOVER_MISSED_TICK_CANDIDATES"
error_reporting:
  destination: "GitHub Actions ::error:: annotations + run conclusion (this surface has no Sentry DSN; unchanged from the existing op=verify arm)"
  fail_loud: "::error::missed-tick candidates: invalid window … the exactly-once verdict above STANDS (ON only; exit 1)"
failure_modes:
  - mode: "gate inverted or its default flipped, so the default run prints per-function lines again"
    detection: "layer 6: workflow run log of infra-validation.yml (job deploy-script-tests, step 'Run cutover-inngest.yml workflow tests') goes red on Guard 2's behavioural OFF cases and YAML default assertion, on the PR that makes the change"
    alert_route: "red PR check (deploy-script-tests is NOT in the main ruleset's required contexts, so it is visible but does not block merge; review reads it)"
  - mode: "a nonexistent trigger-cron flag reintroduced at any emission site"
    detection: "layer 6: workflow run log of infra-validation.yml, Guard 1 (comment-stripped token assertion over the whole script plus the YAML)"
    alert_route: "red PR check (same job, not required)"
  - mode: "env mapping dropped, so the input is silently ignored"
    detection: "layer 6: workflow run log of infra-validation.yml, exact mapping-line and single-reference assertions. The failure is in the safe direction (always OFF)"
    alert_route: "red PR check (same job, not required)"
  - mode: "ON with an invalid or out-of-range window, or a window value failing the ISO shape check"
    detection: "layer 6: ::error:: in the cutover-inngest.yml workflow run log (it says the exactly-once verdict above STANDS). The run concludes red, which is visible without SSH because the script runs on ubuntu-latest"
    alert_route: "the dispatching operator (run conclusion and annotation)"
  - mode: "a function id from the host fails the shape check"
    detection: "layer 6: ::warning:: in the cutover-inngest.yml workflow run log, with the count of skipped ids"
    alert_route: "the dispatching operator (annotation)"
logs:
  where: "GitHub Actions run log of cutover-inngest.yml (op=verify)"
  retention: "GitHub Actions default log retention for the repository (90 days)"
discoverability_test:
  command: "grep -c inputs.missed_tick_candidates .github/workflows/cutover-inngest.yml"
  expected_output: "1"
```

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-146** (`ADR-146-trust-anchor-for-cutover-coexistence-window.md`) § Deferred. There is no
new ADR: this changes the status of a deferred item, not a boundary.

- Header: "All three are tracked by **#6940**" becomes the correct count, because the section
  lists four items, and a fifth is added below.
- Item 2: append `**Interim de-fang landed (#6939, PR #<N>, <merge date>).**` The per-bucket list is
  opt-in via the `missed_tick_candidates` dispatch input (default `false`) and prints non-command
  `candidate function_id=… empty_bucket_start=…` lines under an UNVERIFIED header. The default output
  is a single recovery pointer. `--function-id`/`--missed-tick` no longer appear anywhere. The defect
  is closed. What remains is naming and due-tick precision, which is item 5's job.
- New item 5 (#6939 proper fix, tracked on #6940): the registry probe emits slug and trigger
  type/value, and a per-function period or cron evaluator decides which ticks were due. Only after
  that may op=verify print named `--event cron/<name>.manual-trigger` lines. Re-check condition:
  before the next production op=verify dispatch against a newly cut-over dedicated host.
- The issue cites "ADR-143 § Deferred 2". The amendment adds no cross-reference to ADR-143. The PR
  body notes the renumber so reviewers are not sent to the wrong file.

**ADR-106 gets one dated sentence** (architecture P2-3, Kieran P2-6). Its Decision item 4 places
the anchored block "in the `op=verify` arm of `cutover-inngest.yml`", which has been stale since
ADR-150. The new sentence says where the block lives now (`missed_tick_report()` in
`scripts/cutover-inngest.sh`) and that it is opt-in since #6939. The anchor text
(`# ---- Missed-tick auto-enumeration (P2-16)`) stays verbatim. Its reasoning ("a narrower window
feeds false missed ticks into the enumeration → operator re-fire → double-fire") still explains
correctly why the window must stay ⊇ the coexistence region.

### C4 views

No C4 impact. Checked against `knowledge-base/engineering/architecture/diagrams/{model,views,spec}.c4`:

- (a) External human actors: the operator (founder) already appears as the actor who dispatches
  workflows. No new actor.
- (b) External systems: none are added. GitHub Actions (`github`) and the Inngest dedicated host are
  already modelled. `cutover-inngest.yml` is referenced only in the Inngest store description
  (`model.c4`, op=luks-rollback), which this change does not affect.
- (c) Containers or stores touched: none. No store, queue, or probe changes.
- (d) Access relationships: unchanged. The new input is a local display toggle.

`bash plugins/soleur/test/c4-count-parity.test.sh` → `ALL TESTS PASSED` (Failed: 0), run 2026-09-25
on this branch.

### Sequencing

Not needed. The decision is true the moment this PR merges.

## Guard Contract

### Guard 1 — no nonexistent trigger-cron flag at any emission site

**Property.** No non-comment line of `scripts/cutover-inngest.sh` or `.github/workflows/cutover-inngest.yml`
contains the token `--function-id` or `--missed-tick`, the flags the trigger-cron skill does not
accept.

**Assembly.** Every line either file can print is an emission site. That covers all 14 `case "$OP"`
arms, every top-level helper, every heredoc/`printf`/`echo`, and the YAML itself. So the chokepoint
is the **whole comment-stripped files**: `$BODY_SH` and `$WF_YAML` each grepped directly, not
the reconstructed `$WF`. `$WF` drops every script line above `set -euo pipefail` (about 33 lines)
and re-indents the rest, so a flag in the preamble would be invisible there. It is not the
`verify)` arm (`VERIFY_ARM_FILE`) either, because an arm-scoped grep would miss a second emission
site in `doublefire-probe)`. The grep uses `-e` for each pattern
(`grep -vE '^[[:space:]]*#' "$f" | grep -c -e '--function-id' -e '--missed-tick' || true`). A bare
`grep -E '--function-id|…'` is read as an option: grep exits 2, `|| true` yields `''`, and
`[[ '' -eq 0 ]]` passes. The assertion checks that the count equals exactly `0`, using `== '0'`, never
`-eq`. Non-vacuity: before the grep, a precondition asserts that the file being grepped contains the
anchor lines `missed_tick_report() {` (column 0) and the `verify)` case label with its two-space indent. Both are
read from `$BODY_SH`; in `$WF` they are indented and neither matches. Then a mis-pointed or truncated `$BODY_SH`
cannot make the token count trivially zero. This replaces an earlier line-count floor; a magic
number would break on a legitimate script split (CTO #5).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Restore `echo "  soleur:trigger-cron --function-id $fn --missed-tick $TICK_TS"` inside the ON branch of `missed_tick_report()` | RED |
| 2 | Point the guard at an empty or missing body (typo `$BODY_SH`, or reconstruct `$WF` from the YAML only): the guard's own dispatch | RED (anchor-presence precondition) |
| 3 | Leave the function compliant and add a **second** emission site: `printf '%s --missed-tick %s\n' …` in the `doublefire-probe)` arm | RED |
| 4 | Put the flag inside a string built by concatenation, e.g. `F="--missed"; echo "${F}-tick"` | GREEN. Known limit: token-based guards can't see built strings, so Guard 2's behavioural output assertions (no candidate line contains `--`) cover the ON output shape. |

**Harness rows.** (H1, suite edit) Change the guard's grep from comment-stripped to raw, so the
rewritten explanatory comment's prose would count. The guard must still be GREEN on the compliant SUT,
because the rewrite also removes the tokens from comments (Files to Edit). If it reds, the comment
rewrite is incomplete. (H2, must-PASS non-canonical) A comment line `# formerly printed
--missed-tick` is allowed by the property, and the comment-stripped guard must stay GREEN on it.

**Anchor.** n/a. The guard compares no stored value, and it greps the live SUT at test time.

### Guard 2 — default-OFF gate on per-function missed-tick output

**Property.** Unless `CUTOVER_MISSED_TICK_CANDIDATES` is exactly the string `true`,
`missed_tick_report` prints no line containing a function id and returns 0, whatever the window
variables hold.

**Assembly.** A value can reach this output through exactly three structural points, and the guard
checks all three. (i) The YAML input `missed_tick_candidates` (`type: boolean`, `default: false`) is
the only source. (ii) The single env mapping `CUTOVER_MISSED_TICK_CANDIDATES: ${{
inputs.missed_tick_candidates }}` is the only path into the shell; there is exactly one `${{
inputs.missed_tick_candidates` reference, following the `OP_REFS` pattern. (iii) The call site is
the only place the env value becomes the function's `$1`. One exact-line assertion pins its first
argument as `"${CUTOVER_MISSED_TICK_CANDIDATES:-}"`, with no default. (iv) `missed_tick_report()`
is the only printer: the comment-stripped `verify)` arm calls it exactly once and contains no
per-function loop of its own (no `candidate function_id=` and no `for fn in`).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Gate rewritten as `!= "false"` (so empty counts as ON) | RED (the `""` OFF case prints fixture ids) |
| 2 | Default in YAML flipped to `default: true` | RED (YAML shape assertion) |
| 3 | Call site rewritten with a default, `"${CUTOVER_MISSED_TICK_CANDIDATES:-true}"`, or with `|| exit 1` appended | RED (exact whole-line `grep -cxF` assertion) |
| 4 | Guard's own dispatch: function renamed (`missed_tick_report` → `mtr`), or a trailing comment added to its definition line, so extraction yields an empty file | RED (the extracted file must be non-empty and contain `missed_tick_report() {`, and the executed-case counter must be ≥ the declared case count, in the suite's `ACT_EVALS` idiom) |
| 5 | Second member: a compliant function plus an inline `for fn in …; echo "  candidate function_id=$fn …"` left in the `verify)` arm | RED (arm-level no-loop assertion) |
| 6 | **Reorder**: the `missed_tick_report` call moved above the 2.6 `DUPES` check | RED (line-order assertion: the call's line number in the comment-stripped arm is greater than that of the LAST `exactly-once VERIFIED` echo; there are two, the qualified `::warning::` and the full `::notice::`) |
| 7 | OFF arm parses the window and `return 1`s on a malformed one | RED (OFF with a window-from argument of `garbage` must return 0) |

**Harness rows.** (H1, suite edit) Move the ON fixture's window outside every run so it has no gaps.
The `ON emits exactly 4 candidate lines` assertion must go RED. The count comes from the fixture
(hourly `fn-h` missing one bucket, plus daily `fn-d` missing three), never from the gate value.
The canonical case also compares the **sorted candidate set** exactly (`fn-d 11:00, fn-d 12:00,
fn-d 13:00, fn-h 12:00`) and checks that the footer says 4. A count plus a regex survives an
off-by-one bucket range (10–12 also gives 4) and a bucket-end timestamp. A never-incremented
counter survives a check that only reads the full-coverage footer. (H2, must-PASS non-canonical) ON with a full-coverage fixture (every observed function has a run in
every window bucket) must print 0 candidate lines, a footer counting 0, and return 0. This shows the
guard does not reject everything. (H3, must-PASS) OFF with a valid window and the canonical fixture
must return 0 and print the pointer line, and no fixture id may appear.

**Anchor.** n/a. There is no stored value. The YAML default and the gate are read live from the SUT.

## Acceptance Criteria

- [ ] **AC1** Class-wide over every operator-facing surface: `git grep -n -e '--function-id' -e '--missed-tick' -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs' ':!**/archive/**' ':!apps/web-platform/infra/cutover-inngest-workflow.test.sh' ':!knowledge-base/engineering/architecture/decisions/ADR-146-trust-anchor-for-cutover-coexistence-window.md'` prints nothing. The two exclusions are deliberate. The suite has to name the forbidden tokens for its guard to check them. ADR-146 § Deferred item 2 quotes the defect as history. Measured before the change, the only hit is `scripts/cutover-inngest.sh` (the `echo` line).
- [ ] **AC2** The workflow declares input `missed_tick_candidates` with `type: boolean` and `default: false`. It maps `CUTOVER_MISSED_TICK_CANDIDATES: ${{ inputs.missed_tick_candidates }}` in the step env, and `grep -c 'inputs.missed_tick_candidates' .github/workflows/cutover-inngest.yml` prints `1`.
- [ ] **AC3** `missed_tick_report()` exists as a top-level function with a bare definition line (`grep -cx 'missed_tick_report() {' scripts/cutover-inngest.sh` prints `1`). The call is one whole line: `grep -cxF '    missed_tick_report "${CUTOVER_MISSED_TICK_CANDIDATES:-}" "$BODY" "$CRON_PERIOD" "${CUTOVER_WINDOW_FROM:-}" "${CUTOVER_WINDOW_UNTIL:-}"' scripts/cutover-inngest.sh` prints `1`. In the comment-stripped `verify)` arm the call comes after the last `exactly-once VERIFIED` echo, and the arm contains no `for fn in` loop.
- [ ] **AC4** Behavioural, executed by the suite in a table-driven loop (the declared count is derived from the table length, not hard-coded): with gate arguments `""`, `false`, `TRUE`, `1` and `true` followed by one trailing space, the function prints no `candidate function_id=` line, none of the fixture's function ids, and no `--function-id` or `--missed-tick`. It prints the pointer containing `knowledge-base/engineering/operations/runbooks/inngest-server.md` and `Bounded-outage note`, and returns exactly 0, including with a window-from argument of `garbage` (printed as `<invalid>`). The pointer contains no double quote and no apostrophe.
- [ ] **AC5** Behavioural (every rc check is exact, `== 0` / `== 1`, so a 127 from a missing function or a 5 from a jq crash cannot pass): with the gate `true` and the canonical fixture, it prints the UNVERIFIED header, a footer counting 4, and exactly 4 lines, and the sorted set equals `fn-d@11:00,fn-d@12:00,fn-d@13:00,fn-h@12:00` (each line matching `^  candidate function_id=[^ ]+ empty_bucket_start=[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$`, ), no candidate line contains `soleur:` or `--`, and it returns 0. With the null fixture it returns 0 and prints exactly 7. For each of three invalid windows (reversed, unparseable / non-ISO such as `tomorrow`, and a span over 10000 buckets) it returns 1, and the `::error::` line contains `verdict above STANDS`. With one window argument empty it prints a `::warning::` and returns 0. With a full-coverage fixture it prints 0 candidate lines and returns 0.
- [ ] **AC6** The 2.6 verdict code is byte-identical (Kieran P1-3). This is a work/review-time check, not a suite assertion. Run: `cut26() { awk '/# ---- 2.6 exactly-once double-fire check/{f=1} f{sub(/^[[:space:]]+/,""); print} /2.6 SCOPE CAVEAT/{exit}'; }; cmp <(git show origin/main:scripts/cutover-inngest.sh | cut26) <(cut26 < scripts/cutover-inngest.sh)`. It must exit 0, and the cut must be non-empty (`cut26 < scripts/cutover-inngest.sh | wc -l` over 100).
- [ ] **AC7** `grep -c '# ---- Missed-tick auto-enumeration (P2-16)' scripts/cutover-inngest.sh` prints `1` (ADR-106 content anchor preserved).
- [ ] **AC8** The existing null-`startedAt` harness still passes unedited: `BUCKET_PROG_N` equals `BUCKET_SITE_N`, is still ≥ 3, and the OBSERVED program still yields 4 pairs.
- [ ] **AC9** `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh` exits 0, with 0 FAIL and a PASS count strictly above the 914 baseline.
- [ ] **AC10** Runbook: `grep -c 'Re-fire that list' knowledge-base/engineering/operations/runbooks/inngest-server.md` prints `0`. The `### Bounded-outage note` section (up to the next heading) still exists and contains `--event cron/<name>.manual-trigger`, `SENTRY_MONITOR_SLUG`, `checkin_margin_minutes`, `do not re-fire`, and the names `cron-workspace-gc`, `cron-rule-prune`, `cron-action-required-sla`. `scripts/cutover-inngest.sh` contains none of those three cron names in the pointer, so the runbook stays the single source.
- [ ] **AC11** ADR-146 § Deferred item 2 contains `Interim de-fang landed (#6939`. A new item 5 names the #6939 proper-fix scope and its re-check condition, and the section header count matches the item count. ADR-106 carries the dated location sentence.
- [ ] **AC12** #6940 has a comment (posted in this PR's lifecycle) adding the #6939 proper fix as a separate item, with the re-check condition from Phase 4.1. The PR body carries `Closes #6939` and `Ref #6940`.
- [ ] **AC13** No production write, host replace, or live dispatch happens as part of this PR. Verification is the static and behavioural suite only.

## Domain Review

**Domains relevant:** Engineering, Product (sign-off only; no UI surface)

### Engineering

**Status:** reviewed
**Assessment:** CTO approves, with changes that are folded in. (1) Keep the opt-in arm; it is
justified, but only just, by the hourly-cron signal, and deleting the block would break the
`-ge 3` bucketing census and ADR-106's anchor. (2) The line-207 assertion is vacuous under the new
pointer, so it is replaced with behavioural ON/OFF cases plus a file-wide flag-token check.
(3) Keep `CUTOVER_WINDOW_FROM` mapped: `doublefire_from()` reads it as the last-resort anchor.
(4) Under ON, an invalid window keeps `exit 1`, but the message must say the verdict above STANDS.
(5) Say how event-only crons are handled. After plan review this lives in the runbook as a rule ("no `{ cron: }` trigger → event-only"), not as a list in the pointer. Injection risk: low; the input is a
boolean, env-mapped, with a strict compare. Deferring the proper fix to #6940 is correct.

### Product/UX Gate

**Tier:** none (no UI-surface file in Files to Edit/Create; operator run-log text only)
**Decision:** reviewed (CPO sign-off required by the `single-user incident` threshold)
**Agents invoked:** soleur:product:cpo
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface)

#### Findings

CPO: the threshold (`single-user incident`) and framing are right. Two gaps are folded in. (1) The
pointer itself is a path to firing a cron, so the checks come first: confirm a tick fell in the gap,
confirm it has no run, then fire. The pointer names the three destructive or user-facing crons.
(2) The deferral must point at an issue that owns the work, so Phase 4 comments the proper-fix scope
onto #6940. Checks added: candidate lines have no `soleur:` and nothing that runs; the input defaults
to false; the verdict output is unchanged byte for byte (AC6). **CPO sign-off: approved.**

## Test Scenarios

All of these run in `apps/web-platform/infra/cutover-inngest-workflow.test.sh` against the
extracted `missed_tick_report()`, called with positional arguments `<gate> <body> 3600 <from> <until>` using the Phase 1.2 capture pattern.

**Canonical fixture** (`MTR_FIXTURE`, all dates 2026-07-08). `fn-h` (hourly) runs at `10:00:05Z`,
`11:00:03.2Z` (a fractional-second stamp, the Postgres shape) and `13:00:01Z`, so it has no run in the
12:00 bucket. `fn-d` (daily) runs once at `00:00:02Z`. The window
`[2026-07-08T11:30:00Z, 2026-07-08T13:30:00Z]` covers buckets 11, 12, and 13, so under ON the
expected output is 4 lines: `fn-h`@12:00 and `fn-d`@11:00/12:00/13:00. The `fn-d` lines are the
never-due class this change labels. The count comes from the fixture.

**Null-`startedAt` fixture** (`MTR_NULL_FIXTURE`) is the canonical fixture plus `fn-q` with a single
`startedAt: null` run. The function set stays `[.runs[].functionID] | unique` (unchanged, so it
includes `fn-q`), and the expected count is therefore **7** (4 + `fn-q`×3). This case asserts
rc=0 (no jq exit 5) and the exact count 7. Changing the function-set expression is out of scope, and
that exact count is what would catch someone changing it silently. It is also what catches a `jq`
failure inside `for fn in $(jq …)`, which `set -e` cannot see (Kieran). The suite comment must say
that #6940's item 5 is expected to change this count, so the next engineer does not read the change
as a regression (CTO #4).

- Given a gate argument of `""` or `false` (one table-driven loop), with the canonical fixture and a valid window, when `missed_tick_report` runs, then there is no `candidate function_id=` line and no `fn-h`/`fn-d` text, the pointer (runbook path, raw window values) is printed, and rc=0. (An unset env var reaches the function as `""` through the call site's `:-`; AC3 pins that.)
- Given the gate empty and a window-from argument of `garbage`, when it runs, then rc=0 and the pointer is printed (the window is never parsed).
- Given the gate `true` and the canonical fixture (no `fn-q`), when it runs, then the header contains `UNVERIFIED` and `NOT a re-fire list`, there are exactly 4 candidate lines (`fn-h`@12:00, `fn-d`@11:00/12:00/13:00), none contains `soleur:` or `--`, and rc=0.
- Given the gate `true` and a full-coverage fixture, when it runs, then there are 0 candidate lines, the footer reports 0, and rc=0 (must-PASS non-canonical).
- P7 injection cases (each case also asserts rc `== 0` and that the pointer line is present, so a function that prints nothing cannot pass). With the gate `false`, a window-from value containing `\n::notice::FORGED`, a window-until value containing `\r::notice::FORGED`, and a value containing `%0A` must each print `<invalid>`, and no output line may start with `::notice::FORGED`. With the gate `true` and a fixture whose function ids include `*`, `a\rb` and a 200-character id, none of those ids appears, the shape-check `::warning::` count is 3, and no file name from the working directory appears.
- Given the gate `true` with the until argument before the from argument, when it runs, then rc=1 and the `::error::` contains `verdict above STANDS`.
- Given the gate `true` and one window argument empty, when it runs, then a `::warning::` is printed and rc=0.
- Given the gate `true` and `MTR_NULL_FIXTURE`, when it runs, then it does not crash (jq exit 5 was the #6178 crash class), rc=0, and there are exactly 7 candidate lines.
- Regression (#6939): the file-wide comment-stripped token count for `--function-id|--missed-tick` is 0.
- Workflow shape: the input block has `type: boolean` and `default: false`; the env mapping line exists; exactly one `${{ inputs.missed_tick_candidates` reference; `OP_REFS` still equals 1; the exact whole-line call assertion (AC3) holds.
- Ordering: in the comment-stripped `verify)` arm, the line number of the `missed_tick_report` call is greater than that of the LAST of the two `exactly-once VERIFIED` echoes.
- Counter: the number of behavioural cases executed is at least the number declared, in the suite's `ACT_EVALS` idiom (anti-vacuity).

## Risks

- **The operator switches ON and treats candidates as a re-fire list.** Mitigation: the header says
  otherwise, no line is command-shaped, and the runbook and ADR describe it as unverified.
- **The ON arm's invalid-window `exit 1` reddens a run whose verdict was clean.** This is accepted,
  opt-in only, and the message says the verdict STANDS. The default (OFF) arm can never do it.
- **Pointer text drifts from the runbook heading.** AC4 pins the runbook path and heading text in
  the pointer, and AC10 pins the heading. The procedure itself exists only in the runbook, so there
  is nothing else to drift.
- **The pointer may not appear in the annotations panel.** The verify arm already prints about 12
  `::notice::` lines, and GitHub caps the annotations shown per step (architecture P2-5, not
  measured). The pointer is still in the run log. Its safety role does not depend on the panel,
  because the harmful list is gone either way. Adding a `$GITHUB_STEP_SUMMARY` mirror was
  considered and cut: the script has no step-summary precedent (`grep -c GITHUB_STEP_SUMMARY` returns
  0), and it would buy no property on the list.
- **Pre-existing, not changed here:** the per-bucket `jq` spawn loop is O(functions × span) (capped
  at 10000 buckets), ON only.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder
  text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan fills it in.
- The suite rebuilds `$WF` by re-indenting the script by 10 spaces. The `verify)` arm matcher is
  `/^            verify\)$/` (12 spaces). A top-level function in the script becomes 10-space
  indented in `$WF`, so extract `missed_tick_report()` from `$BODY_SH` (column 0), **not** from `$WF`.
- `grep -c` exits 1 on zero matches. Under `set -euo pipefail` in the suite, wrap it as
  `… | grep -c … || true` (the suite's existing idiom) so a correct zero is not read as a crash.
- Moving the OBSERVED jq program changes nothing in the perl extractor (`jq[^']{0,160}'…fromdateiso8601…'`),
  as long as the `jq -c --argjson period "$CRON_PERIOD"` prefix stays within 160 characters of the quote.
  Keep the invocation shape identical.
- The issue's "ADR-143" citation is stale (renumbered to ADR-146). Do not edit ADR-143.
- **Keep the OBSERVED jq invocation byte-identical inside the function.** Bind
  `local BODY="$2" CRON_PERIOD="$3"` at the top of `missed_tick_report()`. That way the moved line
  still reads `jq -c --argjson period "$CRON_PERIOD"` over `"$BODY"`, and AC8 (which executes this program against fixtures) holds. Renaming
  to `"$3"` would still pass the suite's count-based extractor, but it breaks the invocation shape the
  "do not reshape" comment protects.
- **`set -e` inside a function called from `||`/`&&` is ignored, and so is everything that function
  runs.** This is why the call site is plain (Output contract) and why the suite runs every case
  under `set +e; ( set -euo pipefail; … ) > file; rc=$?; set -e` rather than `$(…) || rc=$?`
  (Phase 1.2).
- **Do not run the table loop inside `if`, `||` or `assert`.** Bash disables `set -e` for the
  whole compound command, including a subshell that re-sets it. Capture rc on its own line, then
  assert on the captured value.
- **Scope the YAML `default: false` assertion to the `missed_tick_candidates:` input block**
  (for example `awk '/^      missed_tick_candidates:$/{f=1;next} f&&/^      [a-z_]+:$/{exit} f'`). An
  unscoped grep is satisfied by any other boolean input.
- **Known limit of the ordering assertion:** it checks line order only. It cannot tell that the call
  sits after an `exit`. AC6's review-time `cmp` over the verdict range covers that shape.
- **GNU `date -u -d` is Linux-only.** The ON arm and its suite cases use it, as the rest of the
  script already does. The suite runs on the Linux `infra-validation.yml` runner. Do not add a macOS
  fallback in this PR; it is not a new portability surface.
- **Print no operator- or host-supplied value into an annotation unsanitized.** Strip CR/LF from the
  window arguments and each function id before echoing (Output contract, "Annotation hygiene").
- Run `npx markdownlint-cli2` on this plan and on `tasks.md` before committing.
