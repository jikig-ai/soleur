---
title: "fix: no-SSH cutover enumerate observability + ENUMERATE_FROM epoch-default root cause"
issue: 5492
branch: feat-one-shot-fix-5492-cutover-enumerate-observability
type: bug-fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-06-17
---

# fix: no-SSH cutover enumerate observability + ENUMERATE_FROM epoch-default root cause (#5492)

🐛 **Bug.** The live Inngest durable-backend cutover (#5450) is blocked: `op=enumerate` returns **HTTP 500 against prod with an empty body**, and the failure is NOT no-SSH-diagnosable. Prod is untouched (no quiesce, no deploy; the #5432-class armed reminder is safe on the old backend). This fix makes the failure diagnosable without SSH + fixes its likely cause + hardens the reviewer/learning surface so the class cannot recur. **It does NOT run the live prod cutover.**

## Enhancement Summary

**Deepened on:** 2026-06-17 (ultrathink). **Agents:** observability-coverage-reviewer (dogfood), code-simplicity-reviewer, verify-the-negative+bash-realism pass; WebFetch against pinned adnanh/webhook v2.8.2 source.

### Key corrections (load-bearing)
1. **P0 premise reversal.** The issue's stated mechanism — "adnanh/webhook `include-command-output` is STDOUT-only, so stderr causes are invisible" — is **FALSE**. webhook **v2.8.2** uses `cmd.CombinedOutput()` (combined stdout+stderr in the 500 body). The empty body is caused by the **workflow discarding the response body** (gap 2 / **AC4 is the real fix**), not by a stream-capture gap. The STDOUT echoes (was gaps 1) are demoted to **defensive/optional (AC11)**, re-justified as portability, and explicitly do NOT gate the fix.
2. **Reviewer hardening re-authored stream-agnostically (AC8/AC9).** The new `observability-coverage-reviewer` check + learning must NOT encode the refuted "stdout-only" rationale; the durable rule is *the synchronous consumer must `cat` the webhook response body on non-2xx before failing*. A 6th synchronous layer (webhook-response-body / workflow-run-log) is added to the reviewer's layer list.
3. **AC5 bash-safety.** The `date -u -d '90 days ago'` default needs the repo's BusyBox-safe named-variable fallback (`wiped:104`) — a bare inline `${VAR:-$(...)}` aborts under `set -e` on non-GNU `date`.
4. **Simplifications (code-simplicity).** Cut the second env var `ENUMERATE_LOOKBACK_DAYS` (`ENUMERATE_FROM` is the override); replaced the rejected `INNGEST_DUMP_REQUEST_BODY` shipped test-seam with a `build_request_body()` function extraction; folded the guard test into AC6; demoted the byte-count AC to a prose note; dropped the async wiped-volume script from required scope.

### New considerations discovered
- **AC4's body dump is payload-bearing on the malformed-response path** (since webhook captures stderr too, the raw `$resp` at `enumerate:93` now reaches the collaborator-readable workflow log). /work must confirm `$resp` can't carry event `.data`, or redact it — a privacy tightening the corrected premise surfaced.
- **90-day lookback is a silent-drop risk** if a reminder's arm→fire horizon exceeds 90d; /work must verify against the route's accepted range.

> **[Updated 2026-06-17 — deepen-plan correction.]** The original issue (and this plan's v1) asserted the empty 500 body was caused by adnanh/webhook capturing **STDOUT only** while the scripts wrote to STDERR. **That premise is FALSE.** The pinned **adnanh/webhook v2.8.2** (`cloud-init.yml:553`) uses `cmd.CombinedOutput()` and writes the **combined stdout+stderr** to the 500 body when `include-command-output-in-response-on-error: true` (verified against `github.com/adnanh/webhook/blob/2.8.2/webhook.go`). The stderr cause from `enumerate:92-93` **was already in the 500 body the hook returned** — the workflow just never `cat`s it (gap 2). The real diagnostic fix is **gap 2 (AC4)**, not the STDOUT echoes. This correction rewrites the gap-1 framing, the AC9/AC10 reviewer-hardening rationale, and the sequencing claim. See Research Reconciliation row 1 + the observability-coverage-reviewer dogfood finding.

## Overview

Three defects, plus a reviewer/learning hardening:

1. **Diagnosability — workflow discards the captured cause (THE FIX).** `cutover-inngest.yml`'s `enumerate` branch discards the webhook response body on the non-200 path (no `cat /tmp/enum-body`, unlike the `rearm` branch at `:96`). The 500 body the hook returns already contains the script's stderr cause (webhook v2.8.2 = `CombinedOutput()`); the workflow throws it away, so the operator sees only `::error::enumerate returned HTTP 500` with no cause. **AC4 is the load-bearing diagnostic fix.**

2. **Robustness — fatal cause should also reach STDOUT (defensive, not the fix).** The scripts write every fatal cause to STDERR + `logger -t <tag>` only. With webhook v2.8.2's `CombinedOutput()` the stderr already reaches the response body, so this is NOT load-bearing for *this* harness. It is kept as a **defensive/portability** improvement: a script whose fatal cause is on STDOUT is diagnosable under any output-capturing harness (a future hook flip to stdout-only capture, a `$(...)` caller that drops stderr, a pipe). Re-justified as such — NOT "the diagnostic enabler that must land first."

3. **Likely root cause of the 500 itself (hypothesis — confirmed-on-read, falsify-at-dry-run).** `inngest-enumerate-reminders.sh:45` defaults `ENUMERATE_FROM=1970-01-01T00:00:00Z` and passes it verbatim as the `eventsV2` `filter:{from}` bound (`:76`). The pinned v1.19.4 schema probe used a *recent* `from` ("wide receivedAt lower bound"), never the epoch (`inngest-graphql-schema.md:29`). Real inngest very likely rejects the 1970 bound → no `.data.eventsV2` → the guard at `:90` fires → `exit 1` → 500. **This is the most likely *content* of the now-visible error**; AC4 makes it visible, the clamp (AC5) fixes it.

4. **Skill/rule hardening.** Harden `observability-coverage-reviewer` to require fatal causes reach the **synchronous no-SSH signal** (the workflow run log via a body-`cat`), not merely journald/Better Stack (async Layer 3) — **stream-agnostically** (webhook captures both streams; the gap is the *consumer* discarding the body, not the *stream*). Add a learning capturing (a) the corrected webhook-v2.8.2 `CombinedOutput()` fact + the consumer-must-not-discard-body rule, and (b) the read-only-dry-run-first rule when R4 blocks pre-merge workflow validation.

**Sequencing** (per `2026-05-10-plan-phase-order-load-bearing-when-contract-changes`): AC4 (workflow body dump) is the diagnostic enabler and can land independently. The clamp (AC5) is implemented in the same PR; its *confirmation* is a post-merge read-only dry-run (AC15) that now shows the cause regardless of whether AC1-AC3 STDOUT echoes ship. AC1-AC3 are defensive and do not gate AC15.

## Research Reconciliation — Spec vs. Codebase

| Claim (from issue/args) | Reality (verified at plan time) | Plan response |
|---|---|---|
| adnanh/webhook `include-command-output-in-response-on-error` captures **STDOUT only** → stderr cause is invisible in the 500 body | **FALSE.** webhook **v2.8.2** (pinned at `cloud-init.yml:553`) uses `cmd.CombinedOutput()` and writes **combined stdout+stderr** to the 500 body on error (verified vs `github.com/adnanh/webhook/blob/2.8.2/webhook.go`). The stderr cause from `enumerate:92-93` **was** in the 500 body | Re-frame: the empty-body bug is **gap 2** (workflow discards the body), NOT a stream-capture gap. AC4 is the fix. AC1-AC3 (STDOUT echoes) demoted to defensive/portability |
| Scripts write fatal causes to STDERR + `logger -t` only | Confirmed: `enumerate:91-94`, `rearm:46,59,62,96-98`, `wiped:66-67` | Add STDOUT echo before each `exit 1` as a **robustness** improvement (not the fix) |
| hooks set `include-command-output-in-response-on-error: true` | Confirmed: `hooks.json.tmpl:103` (enumerate), `:122` (rearm). Wiped-volume hook is `false` (`:140`) — async 202, polled via verify-status state file (`reason` field) | AC4 targets the enumerate workflow branch; wiped-volume's STDOUT is non-load-bearing (its `reason` is the synchronous carrier) → AC3 is **non-blocking optional** |
| `cutover-inngest.yml` enumerate branch discards 500 body | Confirmed: `:68-70` has no `cat /tmp/enum-body`; `rearm:96` does `cat /tmp/rearm-body` | Add body dump + `::error::` to enumerate branch (AC4 — the fix) |
| `ENUMERATE_FROM` defaults to `1970-01-01T00:00:00Z` | Confirmed: `:45`, passed at `:76` | Clamp default to recent lookback. **`ENUMERATE_FROM` IS the override** — no second env var (see code-simplicity finding) |
| Default `date -u -d '90 days ago'` is safe under `set -euo pipefail` | **NEEDS FALLBACK.** The host's `date` flavor is unverified; BusyBox `date` lacks `-d 'N days ago'`. The repo's own pattern at `wiped:104` is `date ... 2>/dev/null \|\| date -u +...`. A bare `$(date -d 'N days ago')` under `set -e` aborts the script if `date` fails | AC5 MUST use a named-variable assignment with the `wiped:104` fallback shape (BusyBox-safe epoch-format fallback), not an inline `${VAR:-$(date -d 'N days ago')}` |
| Existing tests exercise the `from` default | **FALSE** — all tests set `INNGEST_GQL_FIXTURE_DIR`, which `cat`s `page-N.json` and `return 0`s in `fetch_page` (`:64-67`) BEFORE the request body is built. `FROM_TS`/`filter.from` is unobservable through the fixture seam | Extract a `build_request_body()` function (the `jq -nc … filter:{from:$from…}` block at `:71-76`); the test sources the script and calls it directly — genuine RED/GREEN on the default path, no new production env (see code-simplicity finding) |
| shellcheck runs in CI | **FALSE** — no shellcheck gate in `.github/workflows/`; only inline `# shellcheck disable=` directives | "shellcheck clean" is a **local** verify gate; run `shellcheck apps/web-platform/infra/inngest-*.sh` in /work |
| `*.test.sh` run in CI | Confirmed: `infra-validation.yml` `deploy-script-tests` job, `:187-194` | New/updated tests land in the same files; CI exercises them automatically |

## User-Brand Impact

**If this lands broken, the user experiences:** the operator cannot complete the Inngest durable-backend cutover, so the single armed reminder (#5432 class) remains on the old ephemeral backend and silently vanishes the next time the inngest volume is wiped — the user's pending reminder never fires, with no error surfaced to anyone.

**If this leaks, the user's workflow is exposed via:** N/A for the diagnostic surface itself — but the new STDOUT error lines and the workflow body-dump MUST preserve the existing `P2-sec-a` invariant (counts + `reminder_id`s ONLY, NEVER comment bodies / payload `.data`). A naive "echo the whole malformed GraphQL response to stdout" would leak event payloads into the workflow log (world-readable to repo collaborators). The structured error line must be cause-only.

**Brand-survival threshold:** single-user incident. (CPO sign-off required at plan time; `user-impact-reviewer` invoked at review time.)

## Acceptance Criteria

### Pre-merge (PR)

**THE FIX (load-bearing):**

- [ ] **AC4 (workflow body dump — THE diagnostic fix).** `cutover-inngest.yml` `enumerate` branch (`:68-70`) `cat`s `/tmp/enum-body` on the non-200 path AND emits an `::error::` annotation that includes the body cause, mirroring the `rearm` branch shape (`:96-99`). CR/LF in the body is stripped before the `::error::` echo (`${var//[$'\n\r']/ }`) per the log-injection Sharp Edge. **This alone makes the existing (already-captured) stderr cause visible without SSH.**
- [ ] **AC5 (clamp the epoch default — fixes the 500's likely cause).** `inngest-enumerate-reminders.sh:45` default changes from `1970-01-01T00:00:00Z` to a ~90-day lookback, env-overridable (`ENUMERATE_FROM` still wins — it IS the override; **no second env var**). The default MUST be assigned to a named variable with the repo's BusyBox-safe fallback (mirror `wiped:104`), NOT an inline `${VAR:-$(date -d 'N days ago')}` (which aborts under `set -e` if `date` lacks `-d 'N days ago'`):

  ```bash
  # ~90-day receivedAt lower bound; the client-side occurredAt/ts future filter
  # does the real selection. 90d MUST exceed the max reminder arm→fire horizon
  # (verify against the schedule-reminder route's accepted fire_at range — a
  # reminder armed >90d before firing would be excluded by this receivedAt bound,
  # silently dropping it: the exact #5492 failure class). Epoch (1970) was wrong:
  # inngest rejects it as an out-of-range Time! bound (gap 3 root cause).
  _default_from=$(date -u -d '90 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u +%Y-%m-%dT%H:%M:%SZ)   # BusyBox fallback: now (caller sets ENUMERATE_FROM for a wider window)
  FROM_TS="${ENUMERATE_FROM:-$_default_from}"
  ```
  The `90` carries the inline derivation comment above (magic-number obligation). **/work MUST verify 90d ≥ the max arm→fire horizon the schedule-reminder route accepts**; if the route allows a longer horizon, widen the default accordingly.
- [ ] **AC6 (RED/GREEN default-path test via function extraction).** Extract the request-body construction (`inngest-enumerate-reminders.sh:71-76`) into a `build_request_body()` function that reads `FROM_TS`. A new test in `inngest-enumerate-reminders.test.sh` sources the script (or invokes the function) with NO `ENUMERATE_FROM` override and asserts the emitted `filter.from` is the clamped recent instant (within the last ~2 years), NOT `1970`. **RED before AC5, GREEN after** (verify by stashing the clamp). No new production env var, no test-only debug seam in shipped code. (This subsumes the former AC7 guard — the "not 1970 / within 2 years" assertion lives here.)
- [ ] **AC7 (no-leak — `P2-sec-a` preserved).** A test asserts the enumerate malformed-response cause line (wherever it is emitted) does NOT contain the fixture's raw event `data` payload. The raw GraphQL response stays STDERR-only (`enumerate:93`); only a cause-only summary may be added to STDOUT.

**REVIEWER + LEARNING HARDENING (gap 4 — operator-requested recurrence prevention):**

- [ ] **AC8 (reviewer agent — stream-AGNOSTIC synchronous-signal check).** `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` gains a new check step (and a 6th layer) — authored **stream-agnostically**, since webhook v2.8.2 captures BOTH streams via `CombinedOutput()`. Required shape (do NOT encode "stdout-only"):
  - Add a **6th signal** to the five-layers list: *webhook-response-body / workflow-run-log* — the synchronous, request-scoped no-SSH signal, distinct from the five async/Sentry layers. Amend Step 2 to accept it for `failure_modes` whose surface is a synchronous webhook.
  - Add a check step: for each host script invoked by an adnanh/webhook hook with `include-command-output-in-response-on-error: true` (grep `hooks.json.tmpl`), the fatal cause must (a) reach stdout OR stderr (webhook captures both) AND (b) be **surfaced by the synchronous consumer** — the calling GitHub Actions step MUST `cat` the response-body file (`/tmp/*-body`) on the non-2xx branch before `exit 1`. A hook with `…on-error: true` whose workflow branch discards the body on non-200 = **P1** (this is #5492 gap 2). A fatal cause reaching only Layer 3 (journald/Better Stack, async) with no synchronous-consumer dump = **P1**.
  - Note that **Layer 3 (Vector journald) is asynchronous and not keyboard-visible in the failing request** — it does not by itself satisfy no-SSH diagnosability for a synchronous webhook.
- [ ] **AC9 (learning — corrected facts).** A learning file under `knowledge-base/project/learnings/` captures: (a) **adnanh/webhook v2.8.2 `include-command-output-in-response-on-error` returns COMBINED stdout+stderr** (`CombinedOutput()`) — the empty-500 bug is a *consumer discarding the response body*, NOT a stream-capture gap; the durable rule is "the synchronous consumer (workflow) must `cat` the response body on non-2xx before failing, and emit a cause to either stream"; (b) when R4 (pre-merge workflow validation) is blocked and a script has runtime-only default args, the first prod action must be a read-only dry-run whose failure path is visible. Referenced from `observability-coverage-reviewer.md` body (the routing target). **Must NOT assert "echo to stdout because webhook is stdout-only"** — that is the refuted premise.
- [ ] **AC10 (AGENTS.md budget — no new always-loaded rule).** NO new `hr-*`/`wg-*`/`cq-*` rule is added to `AGENTS.md` or its sidecars. `B_ALWAYS` (AGENTS.md + AGENTS.core.md) is at **22979/23000 bytes — 21 bytes slack** (measured 2026-06-17); a new pointer (~50-60 bytes) cannot land without a demotion, and none is justified. The hardening lives in the agent body + learning file only (per `2026-06-15-agents-budget-at-cap-descopes-planned-rule`). (Prose note, not a checkbox-ceremony AC, but verify B_ALWAYS unchanged: `echo $(( $(wc -c < AGENTS.md) + $(wc -c < AGENTS.core.md) ))` stays 22979.)

**DEFENSIVE / OPTIONAL (NOT the fix — do not gate AC14/AC15 on these):**

- [ ] **AC11 (STDOUT-on-error — defensive robustness, non-blocking).** OPTIONALLY echo a cause-only one-line summary to STDOUT before fatal `exit 1` in the **synchronous** scripts — `inngest-enumerate-reminders.sh:90-94` (malformed response) and `inngest-rearm-reminders.sh` fatal exits (`:46` no-secret, `:59` enum-failed, `:62` non-array, `:96-98` 503-quiesce-abort, `:111` failed>0). Cause-only (no payload — `P2-sec-a`). `logger`+`>&2`+raw-response-to-stderr KEPT. **Rationale: portability** (diagnosable under any output-capturing harness), NOT a fix for *this* harness (webhook already captures stderr). The async `inngest-wiped-volume-verify.sh` `abort()` is **explicitly out of scope** — its `reason` field in the verify-state file is already the synchronous carrier the workflow polls; adding STDOUT there is gratuitous (code-simplicity finding). If AC11 is implemented, AC7's no-leak assertion extends to the new lines.

**SHELLCHECK / SUITE / PR:**

- [ ] **AC12 (shellcheck local).** `shellcheck apps/web-platform/infra/inngest-enumerate-reminders.sh inngest-rearm-reminders.sh inngest-wiped-volume-verify.sh` is clean (local gate; not CI). Existing `# shellcheck disable=SC2016` directives preserved.
- [ ] **AC13 (all suites pass).** `bash apps/web-platform/infra/inngest-enumerate-reminders.test.sh && bash apps/web-platform/infra/inngest-rearm-reminders.test.sh && bash apps/web-platform/infra/inngest-wiped-volume-verify.test.sh` all exit 0.
- [ ] **AC14 (PR body).** `Closes #5492` (code fix that merges complete; the cutover is a separate operator action, NOT this PR's deliverable). PR body notes the cutover is NOT run by this PR.

### Post-merge (operator)

- [ ] **AC15 (confirm root cause — read-only dry-run).** After merge + deploy, run `gh workflow run cutover-inngest.yml --field op=enumerate` against prod (read-only; no quiesce, no wipe). With AC4 the cause is now visible regardless of AC11. Verdict: 200 + still-armed count ⇒ confirmed fixed, `gh issue close 5492`; 500 + a now-VISIBLE structured cause in the workflow log ⇒ the primary deliverable (no-SSH diagnosability) is met — triage the surfaced cause (expected: the GraphQL `from`-bound error the clamp addresses). **Automation:** `gh workflow run` + `gh run view --log` (no SSH). The ONLY prod action; strictly read-only.

## Implementation Phases

### Phase 1 — AC4: workflow body dump (THE diagnostic fix; lands first, independent)
1. `cutover-inngest.yml:68-70` — on `CODE != 200`: `BODY=$(cat /tmp/enum-body 2>/dev/null || echo "")`, strip CR/LF, `echo "::error::enumerate returned HTTP $CODE: $BODY"`; keep `exit 1`. Mirror the `rearm` branch (`:96-99`).

### Phase 2 — AC5/AC6/AC7: clamp + RED/GREEN default-path test
2. Extract `build_request_body()` from `inngest-enumerate-reminders.sh:71-76`.
3. Add the failing default-path test (AC6) + no-leak test (AC7) FIRST (RED against the epoch default).
4. `inngest-enumerate-reminders.sh:42-45` — clamp via the named-variable + BusyBox-fallback shape (AC5); rewrite the comment with the 90d-horizon derivation. Tests go GREEN. Verify 90d ≥ max arm→fire horizon.

### Phase 3 — AC8/AC9/AC10: reviewer hardening + learning (docs)
5. `observability-coverage-reviewer.md` — add the 6th synchronous signal + the stream-agnostic consumer-must-not-discard-body check; reference the new learning.
6. Write the learning file (AC9) with the corrected `CombinedOutput()` facts.
7. Verify AGENTS.md B_ALWAYS unchanged (AC10).

### Phase 4 (optional) — AC11: defensive STDOUT echoes
8. If desired, add cause-only STDOUT lines to the synchronous scripts' fatal exits. Non-blocking; extend AC7 no-leak coverage if so.

## Domain Review

**Domains relevant:** Engineering (CTO — infra/observability), Product (CPO — single-user-incident threshold sign-off).

This is an infrastructure/tooling + reviewer-agent change. No UI surface (no files under `components/**`, `app/**/page.tsx`); Product/UX Gate tier = **NONE** for wireframes, but CPO sign-off is required by the `single-user incident` threshold (see User-Brand Impact). No new persistent infrastructure (scripts already provisioned via the infra-config push); Phase 2.8 IaC gate skipped. No regulated-data surface (no schema/auth/API/.sql); Phase 2.7 GDPR gate skipped — but note the `P2-sec-a` no-payload-leak invariant is a privacy-adjacent constraint already enforced and preserved (AC8).

## Observability

```yaml
liveness_signal:
  what: cutover-inngest.yml op=enumerate returns HTTP 200 + still-armed count
  cadence: operator-triggered (not scheduled)
  alert_target: workflow run log (gh run view) + ::notice:: annotation
  configured_in: .github/workflows/cutover-inngest.yml
error_reporting:
  destination: Layer-6 synchronous workflow run log (the fatal cause is in the webhook 500 body via CombinedOutput(); AC4 makes the enumerate branch cat /tmp/enum-body → ::error::) AND Layer-3 journald → Vector → Better Stack (async)
  fail_loud: true — non-200 now dumps the captured cause to the workflow log; exit 1 keeps the job red
failure_modes:
  - mode: GraphQL from-bound rejected by inngest (the #5492 likely root cause; clamped by AC5)
    detection: cause in 500 body surfaced via AC4 enumerate body-dump in the workflow run log (Layer 6, no-SSH); also Layer 3 (Vector journald → Sentry message)
    alert_route: workflow ::error:: annotation
  - mode: enumeration returns non-array / malformed GraphQL response (enumerate:90-94)
    detection: cause in 500 body surfaced via AC4 body-dump (Layer 6); raw response on stderr also lands Layer 3
    alert_route: workflow ::error:: annotation
  - mode: re-arm INNGEST_MANUAL_TRIGGER_SECRET unavailable (rearm:44-47, exit 1)
    detection: cause in rearm 500 body, already cat'd by the rearm branch (cutover-inngest.yml:96, Layer 6)
    alert_route: workflow ::error:: annotation
  - mode: re-arm partial failure — some reminders re-armed, failed>0 final exit 1 (rearm:101-111)
    detection: per-reminder failure lines + final summary in rearm 500 body (Layer 6); logger -t per reminder (Layer 3)
    alert_route: workflow ::error:: annotation
  - mode: re-arm hits 503 (INNGEST_CUTOVER_QUIESCE still set; rearm:93-100)
    detection: quiesce-clear remediation line in /tmp/rearm-body (already cat'd by the rearm branch, Layer 6)
    alert_route: workflow ::error:: annotation
  - mode: wiped-volume async verify reaches a non-zero terminal exit_code (wiped abort or post-wipe assert)
    detection: verify-state file `reason` field polled by cutover-inngest.yml:139-156 (synchronous carrier for the async op); Layer 3 journald for the host-side abort
    alert_route: workflow ::error:: annotation (on terminal non-zero exit_code)
logs:
  where: GitHub Actions workflow run log (Layer 6, synchronous, primary no-SSH signal); host journald via logger -t (Layer 3, async, Better Stack)
  retention: GitHub Actions default (90 days); Better Stack per plan
discoverability_test:
  command: gh workflow run cutover-inngest.yml --field op=enumerate && gh run view --log
  expected_output: HTTP 200 + still-armed count, OR a structured ERROR line naming the cause (NOT an empty 500)
```

> **Layer 6 (new, proposed by AC8):** the *synchronous, request-scoped* webhook-response-body / workflow-run-log signal — distinct from the five async Sentry/Vector layers in `observability-coverage-reviewer.md`. The #5492 class is invisible to Layers 1-5 in the failing request because they are all async; the cause must reach Layer 6 (consumer `cat`s the body) to be no-SSH-diagnosable.

## Open Code-Review Overlap

None — checked `gh issue list --label code-review --state open` against the Files-to-Edit set; no open scope-out touches `apps/web-platform/infra/inngest-*.sh`, `cutover-inngest.yml`, or `observability-coverage-reviewer.md`.

## Files to Edit

- `.github/workflows/cutover-inngest.yml` — **AC4 (THE fix)**: enumerate-branch body dump + `::error::` (`:68-70`)
- `apps/web-platform/infra/inngest-enumerate-reminders.sh` — AC5 clamp (`:42-45`, named-var + BusyBox fallback); AC6 extract `build_request_body()` from `:71-76`; AC11 (optional) STDOUT cause at `:90-94`
- `apps/web-platform/infra/inngest-enumerate-reminders.test.sh` — AC6 default-path RED/GREEN (via `build_request_body`), AC7 no-leak
- `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` — AC8 (6th synchronous layer + stream-agnostic consumer-must-not-discard-body check) + AC9 learning reference
- `apps/web-platform/infra/inngest-rearm-reminders.sh` — AC11 (optional) STDOUT cause at fatal exits
- `apps/web-platform/infra/inngest-rearm-reminders.test.sh` — (only if AC11 implemented) assert cause lines on stdout
- `knowledge-base/engineering/operations/runbooks/inngest-server.md` — (optional) no-SSH "enumerate 500 diagnosis" note pointing at the workflow body dump (cutover section ~`:270-356`)

**Out of scope (code-simplicity finding):** `inngest-wiped-volume-verify.sh` + its test — the async hook's `reason` field is already the synchronous carrier; AC11 STDOUT there is gratuitous. Touch only if a reviewer insists on symmetry.

## Files to Create

- `knowledge-base/project/learnings/<topic>.md` — AC9 (date chosen at write-time; topic: `adnanh-webhook-combinedoutput-consumer-must-not-discard-body-and-dry-run-first`)

## Sharp Edges

- **The webhook captures BOTH streams (corrected premise).** adnanh/webhook **v2.8.2** uses `cmd.CombinedOutput()` (verified vs `github.com/adnanh/webhook/blob/2.8.2/webhook.go`). The empty-500 bug is NOT a stream-capture gap — it is the *consumer* (`cutover-inngest.yml:68-70`) discarding the response body. The fix is AC4. Do NOT re-introduce a "must echo to stdout because webhook is stdout-only" rationale into the agent body or learning — that premise is refuted.
- **The default-`from` test seam: use function extraction, NOT a production debug env.** The fixture seam (`fetch_page:64-67`) `cat`s `page-N.json` and `return 0`s before the request body (with `filter.from`) is constructed, so `FROM_TS` is unobservable through fixtures. AC6 extracts `build_request_body()` from `:71-76`; the test sources the script and calls it with no `ENUMERATE_FROM` override, asserting `filter.from` is recent (not 1970). This is a genuine RED-before/GREEN-after on the *default* path with NO test-only production env var (the earlier `INNGEST_DUMP_REQUEST_BODY` idea was rejected by code-simplicity as a shipped seam that only exists for tests). **Do NOT** use a source-grep-only guard (vacuous) and **do NOT** assert against the epoch literal by substring (that is the bug, not the contract).
- **`set -euo pipefail` + `date -d 'N days ago'` (AC5).** A bare `${ENUMERATE_FROM:-$(date -u -d '90 days ago' ...)}` aborts the script under `set -e` if the host's `date` is BusyBox (no `-d 'N days ago'`). Use the named-variable + `2>/dev/null || date -u +...` fallback shape proven at `wiped:104`. Host `date` flavor is unverified — assume it may be non-GNU.
- **90-day lookback is a magic number that can silently re-introduce the bug.** A reminder armed >90 days before its fire date is excluded by the `receivedAt` lower bound and the client-side `occurredAt` filter never sees it — a silently-dropped reminder (the exact #5492 class). /work MUST verify 90d ≥ the max arm→fire horizon the `schedule-reminder` route accepts, and comment the derivation inline.
- **Plan whose `## User-Brand Impact` section is empty / TBD will fail `deepen-plan` Phase 4.6.** This section is filled; do not blank it.
- **No-leak invariant (`P2-sec-a`).** The enumerate malformed-response path echoes the raw GraphQL response to STDERR (`:93`). Keep raw payloads STDERR-only — but note: since webhook captures BOTH streams, even the stderr raw response now lands in the (collaborator-readable) 500 body once AC4 `cat`s it. AC4's body dump is cause-bearing AND payload-bearing on the malformed path. **/work MUST confirm the malformed-response stderr (`:93`) does not echo event payload `.data`** — it currently echoes `$resp` (the whole GraphQL response, which for a *malformed* response is an error envelope, not event data; for a well-formed-but-unexpected response it could carry `.data`). If `$resp` can carry payload, AC4 must dump a redacted/truncated form, or `:93` must be scoped to the error envelope only. This is a privacy tightening the corrected premise surfaces.
- **AGENTS.md is at 21 bytes of slack.** Adding any always-loaded rule pointer fails `lint-agents-rule-budget.py`. The hardening MUST stay in the agent body + learning file (AC10). If a reviewer suggests an AGENTS rule, the correct response is the learning-routing pattern, not a demotion.
- **`Closes #5492` is correct here (not `Ref`).** This PR's deliverable is the code fix (diagnosability + clamp), which merges complete. The post-merge dry-run (AC15) *confirms* the root cause but is not the fix — distinct from the ops-remediation class where the fix itself runs post-merge. The cutover is a separate operator action and is explicitly out of scope.
- **shellcheck is a local gate, not CI.** Run it by hand in /work; do not assume CI will catch a regression.
- **Test stdout/stderr capture (only if AC11 implemented).** Existing abort-message asserts capture combined `2>&1` (e.g. `wiped:103`, `rearm:147`) — those keep passing. A new STDOUT-specific assert must capture stdout via `bash "$TARGET" 2>/dev/null`.

## Architecture Decision (ADR/C4)

None. This is a bug fix on an existing surface (the cutover orchestration shipped under #5450 / ADR-030/033). No ownership boundary, substrate, or trust-boundary change; a competent engineer reading the existing ADRs + C4 is not misled by this fix. Phase 2.10 gate: skip.
