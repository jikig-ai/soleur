---
title: "infra: Inngest batch-1 — wrong-volume drift-guard coverage, spawn dead-letter once-per-replay, encryption-posture step-call leg"
type: chore
date: 2026-10-31
slug: infra-inngest-batch1-guard-deadletter-posture
branch: feat-one-shot-11528-8841-9139-batch1
issue: 11528
closes: [11528, 8841, 9139]
lane: cross-domain
brand_survival_threshold: aggregate pattern
domain: engineering
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- The flag fired on the verbatim `## Operator Holds` record, which names acts this batch must NOT perform, not prescribed steps. Phase 2.8 evaluated: zero new infrastructure and no `.tf` edit, so no `## Infrastructure (IaC)` section is owed. -->

## Overview

Batch-1 of the Inngest host/scheduling arc (epic #10390) per the 2026-10-31 CTO batching ruling, shipping three open issues in one merge-queue cycle:

- **#11528** — close the `inngest_luks_wrong_volume` drift-guard coverage gaps mapped by the structural-enumeration seat: dead-text needle satisfaction (comment/decoy-heredoc re-arming of the `LOCAL_SQL` extraction), exploration→source wiring, whole-alert mute knobs, and the window conjunct — plus the guard-family spread decision and the `MUT_SKIP` env-axis decision.
- **#8841** — make `persistFailure` in `agent-on-spawn-requested.ts` report the spawn dead-letter exactly once under Inngest replay (today it calls `reportSpawnDeadLetter` outside `step.run`, so each replay re-reports), with a regression test on `inngest-step-harness.ts`'s `runLikeInngest` replay model.
- **#9139** — complete the encryption-posture modelling of the Cloudflare serve-URL step-call leg in `encryption-posture-ledger.json`: PR #11487 already narrowed the private-`sdk_url` entry and created the Cloudflare-edge entry naming the leg, but the leg's enforcement anchors (`route.ts` `serveOrigin`/`SERVE_HOST`, `dns.tf` `cloudflare_record.app`) and the Inngest-server HTTP-client cert-verification hop are not yet recorded in the row.

The co-rider deletion of `scripts/followthroughs/inngest-verify-clean-10390.sh` was verified already complete on `origin/main` (removed by PR #11381, commit `101b34a974`); no diff is needed for it — an AC asserts the residual-zero grep instead.

## Operator Holds

Delegation: https://github.com/jikig-ai/soleur/issues/10390#issuecomment-6361717901
Envelope: knowledge-base/engineering/operations/runbooks/inngest-epic-10390-envelope.md

- Hold: Operator-reserved: op=backup dispatch — the operator runs the cutover-inngest.yml op=backup dispatch themselves; it performs a Hetzner create_image write on a third-party system, is outside the recorded Scope, and is on the Excluded list
- Hold: Operator-reserved: DOPPLER_TOKEN_INFRA_PRIVILEGED seed — the operator seeds the privileged Doppler token themselves; a secret-store write is never delegable

**Gated acts in this plan: none.** Every deliverable is a test file, a server-source edit, a ledger JSON edit, or a CI workflow step-env pin. No Terraform apply, no host write, no secret-store write, no vendor-dashboard act is prescribed, so no envelope file is created; the Envelope line above names the recommended path should a later batch need one. The two recorded holds are untouched by this batch (the op=backup dispatch and the Doppler seed belong to other epic workstreams).

## Problem Statement / Motivation

Three defects, one merge-queue cycle (CTO ruling 2026-10-31):

1. **#11528 — the wrong-volume drift guard is satisfiable by dead text.** `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` pins the alert predicate by `grep -cF` presence needles over a plain-text heredoc extraction (`test.sh:128`). The CTO structural map (issue comment) enumerates how each weakens silently: `/* */`- or `#`-wrapped decoy copies of the heredoc/variable-block/resource lines satisfy presence rows while the live text is gutted; `source_variable`/`values`/`FROM {{source}}`, `alert_type`/`operator`/`value`/`check_period`, `count`/`for_each`/`lifecycle.ignore_changes`, and `WHERE time BETWEEN {{start_time}} AND {{end_time}}` are unpinned; `# query_period = 99999` comment lines feed the first-hit `grep -oE`; the floor is self-referential; `MUT_SKIP=1` exported in CI halves the battery with no red; and `LUKS_GUARD_{TF,VARS,WF}` can point inner runs at doctored fixtures. The merged sibling `inngest-luks-key-probe-alert.test.sh` (PR #11601) already carries the newer convention set — canonical-equality SQL compare, `res_block`/`param()` block-scoped pins, fragment-scored `_red_verdict`, `mutate_floor_red`, `mutate_green`, `PRESENCE_ROWS`/`MUT_ROWS` constants — and this issue is explicitly "per sibling-guard convention".
2. **#8841 — `persistFailure` reports each dead-letter once per replay.** `reportSpawnDeadLetter` sits before and outside `step.run` (`agent-on-spawn-requested.ts:1348`). In async mode each new step ends the request and replays the handler, so the report runs again on every invocation until `persist-failure` is memoized: two Sentry events per dead-lettered spawn, three when `notify-cost-breaker` runs. Event counts, `event_frequency_count` triggers and Better Stack pino lines are inflated. The leader-loop suite cannot see it because its mock `step.run` never replays.
3. **#9139 — the ledger misattributes step outputs.** `scripts/encryption-posture-ledger.json` attributed Inngest step outputs to the plain-HTTP private `sdk_url` link, but per #8611/ADR-243 `sdk_url` is only the registration poll; steps are invoked at the registered serve URL `https://app.soleur.ai/api/inngest` (Cloudflare-proxied `cloudflare_record.app` → web-1). PR #11487 already narrowed the private entry's `does_not_defend` and created the Cloudflare-edge entry naming the leg; what remains is anchoring the row in the connecting code (`route.ts` `serveOrigin` pin) and modelling the two hops explicitly (inngest host → CF edge over HTTPS verified by the Inngest server's HTTP client; CF edge → web-1 per the #10479 measurement).

## Proposed Solution

**WS-A (#11528):** rewrite `inngest-luks-wrong-volume-alert.test.sh` onto the sibling guard's conventions, in place:

- Extraction → canonical equality: `sql_local inngest_luks_wrong_volume_sql | tr -d '[:space:]'` compared byte-for-byte to `WRONGVOLUME_CANON` built from the derived literals (`INNGEST_PROBE_MARKER`, `MUT_EMITTER`, `MUT_STAGE`, `MUT_SHIPPER`, and the literal `${local.inngest_luks_wrong_volume_alias}` interpolation text). One equality row subsumes `SELECT`/`count(*)`/`{{time}}`/`FROM {{source}}`/`WHERE…BETWEEN`/`GROUP BY`, every conjunct, inline-tautology neutralization, `$$`-escapes, in-heredoc comments, and decoy-heredoc concatenation — any added/dead text breaks equality. A handful of named-property greps stay for failure-message clarity (the canonical row fails first with the diff).
- `res_block()` + `param()` (exactly-once, line-anchored, block-scoped) for: exploration `source_variable = "source"`, `values = [local.vector_prd_source_id]`, `sql_query` collapse; alert `exploration_id`, `name`, `alert_type "threshold"`, `operator "higher_than"`, `value 0`, `check_period 300`, `query_period 5400`, `recovery_period 10800`, `on_missing_data`, `paused`, `confirmation_period`, `email`, escalation_target block, `metadata.runbook` + `incident_cause` naming `local.inngest_luks_wrong_volume_runbook_url`; the runbook local's exact URL line and the runbook heading's existence in the runbook file.
- Negative param rows: no `count`, `for_each`, `lifecycle`, or `ignore_changes` token inside either resource block.
- `VAR_BLOCK` extraction hardened: assert exactly one `variable "inngest_luks_cutover_complete"` opener across the file, so a `/* */`-wrapped decoy block fails the count.
- `PRESENCE_ROWS`/`MUT_ROWS` constants replacing the `_floor=44/22` magic numbers; `mutate_floor_red` (raise `PRESENCE_ROWS` by one in a scratch copy → must trip the floor); `_red_verdict` fragment-scored rc discrimination and `mutate_green` must-PASS rows, per sibling.
- New mutation rows for every newly pinned property (see Guard Contract): decoy heredoc before the live local with the live body gutted; `/* */`-wrapped decoy variable block; commented `paused`/`on_missing_data`/`exploration_id` lines; `count(*)`→`0`; `FROM {{source}}` repoint; `values` repoint; `WHERE…BETWEEN` dropped; `operator`/`value` flip; `check_period`/`query_period`/`recovery_period` widened; `lifecycle.ignore_changes`/`for_each`/`count` added; `$$` escape; inline tautology `(… = 0 OR … > 0)`; runbook needle moved into a comment.
- `.github/workflows/infra-validation.yml`: pin the env axes on the two run lines that execute the epic-family suites — `env -u MUT_SKIP -u LUKS_GUARD_TF -u LUKS_GUARD_VARS -u LUKS_GUARD_WF bash …wrong-volume…` and `env -u MUT_SKIP -u KEYPROBE_GUARD_TF -u KEYPROBE_GUARD_WF -u KEYPROBE_GUARD_FLIP -u KEYPROBE_GUARD_CI -u KEYPROBE_GUARD_RB -u KEYPROBE_GUARD_VT bash …key-probe…`. The remaining MUT_SKIP-idiom suites (bwrap-probe-rollback, egress-gw, faithful-canary-sandbox, ghcr-blocked, inngest-step-524, registry-clientip-not-rfc1918, registry-store-not-luks, registry-zot-credential-shape, workspaces-luks-deadman-fired, betterstack-send-failed) are the **family remainder**, filed as a tracking issue in Phase 4 — same scope-out the issue offers ("or scope explicitly to this file and file the family remainder").

**WS-B (#8841):** move the `reportSpawnDeadLetter` call in `persistFailure` from before `notify-cost-breaker`/`persist-failure` to after the `persist-failure` try/catch and before `return` — the exact convention the same file's `agentOnSpawnSettleHandler` already documents at `:1641` ("After the memoized step, so a replay never re-reports"). On the final invocation every step is memoized and the report runs once; earlier invocations end at a step boundary before reaching it. A `notify-cost-breaker` final failure propagates to `onFailure`→settle, which already covers that run's dead-letter (`lifecycle: "settle_failed"` path). Update the code comment that records the Sentry-mirror-first ordering to state the new ordering rationale. Regression test in `agent-on-spawn-lifecycle.test.ts` (it already imports `runLikeInngest`, spies Sentry, and fakes the DB): drive `agentOnSpawnRequestedHandler` through `runLikeInngest` to a `persistFailure` path — the no-notify arm (`resolve-installation` throws → `github_installation_unauthorized`, 2 invocations) and a notify arm (a paused `check-runtime-pause` read → cost-breaker notify + persist, 3 invocations) — asserting `deadLetters().length === 1` in each and `invocations ≥ 2` so the replay was actually exercised. Seed the fake `workspaces` row for the notify arm; `LEADER_CLASSES_DISABLED` or a real `LEADER_PROMPTS` class keys the path choice.

**WS-C (#9139):** amend `scripts/encryption-posture-ledger.json` `connections[6]` (the Cloudflare-edge row) — `enforced_at` gains `apps/web-platform/app/api/inngest/route.ts (serveOrigin: SERVE_HOST — the registered serve URL the step call targets, #8611/ADR-243)`; `tls`/`does_not_defend` prose models the two hops explicitly: hop 1 dedicated inngest host → Cloudflare edge over HTTPS with certificate verification performed by the Inngest server's own HTTP client (public CA; not yet measured against the server build — state honestly), hop 2 Cloudflare edge → web-1 origin per the row's existing #10479 posture. `cert_verification` stays `off` (the origin hop is unverified) and the existing `exception` block is unchanged. `connections[5]` (the private link) already names only event sends/registration/`/v1` + the attribution note — verify, not rewrite. `model.c4`'s `inngest -> api` edge already records the leg (`diagrams/model.c4:794-799`) — no C4 edit. `lint-encryption-posture.py` needs no change (it validates schema fields, all present).

## Research Insights

**Premise Validation (Phase 0.6).** #11528 OPEN (2 comments incl. the CTO structural map — fetched, authoritative); #8841 OPEN (bot attempt stalled on env, never landed); #9139 OPEN; PRs #11559 and #11601 MERGED as stated; #11653 OPEN and in-flight touching `betterstack-logs-alerts.tf` (soft race noted in Risks); collision-precheck hits only this pipeline's own draft PR #11695 — benign. `scripts/followthroughs/inngest-verify-clean-10390.sh` is ABSENT on origin/main — deleted by PR #11381; residual grep across `scripts/ .github/ plugins/ apps/ infra/` is already zero. `inngest-luks-key-probe-fail-alert.test.sh` does not exist; the probe guard is `inngest-luks-key-probe-alert.test.sh` on origin/main (this worktree is 3 commits behind; Phase 0 syncs).

**Property List (0.6b).** (a) No weakening of the wrong-volume alert's predicate, parameters, or wiring leaves the drift guard green — including dead-text/decoy satisfaction. (b) Each spawn dead-letter is reported exactly once across Inngest replays. (c) The ledger's in-transit row for the step-call leg names the route that actually carries step outputs and its real cert-verification state. (d) The verify-clean followthrough script is gone from the tree (property already true — assertion only).

**Cut List (0.6b).** New shared guard-helper lib (`test/infra/lib/`) — cut: the family remainder is explicitly descoped to a filed issue, so the dedup mechanism buys nothing this PR. A dedicated third ledger `connections[]` entry for the step-call leg — cut: the Cloudflare-edge row already exists carrying the leg (#11487); a third row would double-model one connection. A `terraform apply` or any `.tf` edit — cut: the current `.tf` already carries every value the new pins assert; this batch pins source, it does not change it. `inngest_luks_key_probe_dark` — cut: explicitly deferred by the batch ruling. Comment/HCL-aware extraction as a shared family fix — cut to the remainder issue (canonical-equality on this file is the remedy).

**Repo findings.** `inngest-luks-key-probe-alert.test.sh` (origin/main) is the convention donor: `sql_local`+`tr -d` canon compare (`FAIL_CANON`:135), `res_block`/`param()` (`:123-131`), `values` pin (`:235`), threshold pins (`:244`), escalation/runbook pins (`:256-263`), census awk (`:309-389`), `_red_verdict`+`mutate_red`+`mutate_green`+`mutate_floor_red` (`:437-534`), `PRESENCE_ROWS=37`/`MUT_ROWS=46` (`:703-704`). Wrong-volume guard current shape: `_floor=44` outer/`22` inner (`:478-479`), 22 presence + 22 mutation rows, `LOCAL_SQL` awk at `:128`, `line_is` at `:133-135`, `VAR_BLOCK` awk at `:248`, QP/RP first-hit extraction at `:265-266`, runbook `grep -qF` at `:273`. The `.tf` block under guard: `betterstack-logs-alerts.tf:306-404` (sql local 306-328, exploration 333-353, alert 355-404). `infra-validation.yml:896` runs the wrong-volume guard, `:902` the key-probe guard; no `MUT_SKIP`/`GUARD_*` env is set anywhere in workflows today (verified `grep -rn` — the battery currently runs in full). `agent-on-spawn-requested.ts`: `persistFailure` `:1320-1407`, the offending call `:1348`, notify step `:1372`, persist step `:1386`, catch `:1396-1405`; the settle-side convention `:1641`. `agent-on-spawn-lifecycle.test.ts` already has `runLikeInngest`, `deadLetters()`, `runSettle`/`runOnFailure` helpers, FakeQuery DB (`:80-153`), and the T21 exactly-once precedent test (`:528-537`). `inngest-step-harness.ts` models one-new-step-per-request replay (`:91-209`); `sentEvents`/`memo`/`attempt` hooks exist. `route.ts` pins `SERVE_HOST` (`:121`, used as `serveOrigin` `:216`). Ledger `connections[5]`/`[6]` already carry the #9139/#10479 wording; lint schema requires `connection`/`enforced_at`/`in_transit.{tls,cert_verification,does_not_defend}` + `exception` when cert off (`lint-encryption-posture.py:1438-1464,1571-1585`).

**Learnings applied.** `verdict=`→`token=` scrub-immunity compound learning: for every new needle verify emit↔transform↔predicate — the wrong-volume needles (`data_mount_devid`, `host_role`, marker, `shipper`, `stage`) are not in vector.toml's `pii_scrub_string` alternation; a scrub-immunity presence row mirroring the sibling's (`keyprobe :213-215`) is added for the wrong-volume keys. `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`: must-PASS rows, fragment-scored verdicts, floor self-mutation. `2026-09-19-cleanup-on-failure-…`: exit-site ordering for the moved report (after the last step, before return). `cq-assert-anchor-not-bare-token`: param() pins anchored whole-line, never bare substring.

**External research:** skipped — strong in-repo convention (sibling guard) covers every mechanism; high-risk topic (security-adjacent guard) but the authoritative pattern is two files over, not the web.

## Research Reconciliation — Spec vs. Codebase

| Spec/brief claim | Reality | Plan response |
|---|---|---|
| "remove scripts/followthroughs/inngest-verify-clean-10390.sh" | File already absent on origin/main (PR #11381) | No deletion diff; AC asserts zero residual refs |
| #8841 "not in any step.run" at `persistFailure` | Confirmed `:1348` | Move call after `persist-failure` catch |
| #9139 "the path itself is not modelled" | Partially stale — #11487 modelled the leg into `connections[6]` and narrowed `[5]` | Amend `[6]`'s `enforced_at`/prose; verify `[5]` |
| Probe guard `inngest-luks-key-probe-fail-alert.test.sh` | Name is `inngest-luks-key-probe-alert.test.sh`, only on origin/main (worktree 3 behind) | Phase 0 syncs; convention read from origin/main copy |
| #11528 gap set (issue items 1-5) | Confirmed at `test.sh:128,133,248,265,273,478` | All mapped to rows/mutations in WS-A |

## Implementation Phases

- **Phase 0 — Premise sync.** `git fetch origin main` and rebase/merge the worktree forward so `inngest-luks-key-probe-alert.test.sh` (PR #11601) is present locally; re-run `gh issue view 11653 --json state` (if it landed mid-queue, re-run the wrong-volume guard against the updated `.tf` — it edits the same file).
- **Phase 1 — WS-A (#11528).** Rewrite `inngest-luks-wrong-volume-alert.test.sh` per sibling convention (extraction → `WRONGVOLUME_CANON` equality; `res_block`/`param()`; `VAR_BLOCK` count==1; constants; `_red_verdict`/`mutate_green`/`mutate_floor_red`; new presence + mutation rows; updated header contract text). Pin `env -u` on the two run lines in `infra-validation.yml`. Run the suite until `0 failed` outer AND `MUT_SKIP=1` inner.
- **Phase 2 — WS-B (#8841).** Move `reportSpawnDeadLetter` below the `persist-failure` catch in `persistFailure`; update the ordering comment; add the replay regression test(s) to `agent-on-spawn-lifecycle.test.ts`; run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/agent-on-spawn-lifecycle.test.ts`.
- **Phase 3 — WS-C (#9139).** Amend `connections[6]` in `scripts/encryption-posture-ledger.json`; `python3 scripts/lint-encryption-posture.py` and `bash scripts/lint-encryption-posture.test.sh` green.
- **Phase 4 — Close-out.** `gh issue create` the family remainder (comment/decoy-aware extraction + env-pin spread across the remaining MUT_SKIP-idiom alert guards, listing each file); verify ACs; PR body names `Closes #11528`, `Closes #8841`, `Closes #9139`.

## Files to Edit

- `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` — WS-A rewrite (largest diff).
- `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` — move `reportSpawnDeadLetter` + ordering comment.
- `apps/web-platform/test/server/inngest/agent-on-spawn-lifecycle.test.ts` — replay regression tests.
- `scripts/encryption-posture-ledger.json` — `connections[6]` amendment.
- `.github/workflows/infra-validation.yml` — `env -u` pins on the two guard run lines.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-11528-8841-9139-batch1/decision-challenges.md` — decision record (batched CTO ruling + pending technical rows).
- `knowledge-base/project/specs/feat-one-shot-11528-8841-9139-batch1/tasks.md` — task breakdown (pipeline artifact).

No new product code, workflow, Inngest function, cron, Terraform, or store is created.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — the failure mode is a drift guard that stays green while the wrong-volume alert weakens, or a Sentry dead-letter count that stays inflated. The founder's card and agent runs are unaffected.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure — the batch hardens detection/attribution of an existing volume-encryption alert and corrects an observability count; it introduces no data flow.
- **Brand-survival threshold:** `aggregate pattern` — per issue #11528's own declaration ("drift-guard soundness across the Better Stack alert family"); a guard-family-wide dead-text class aggregated across the fleet is exactly the pattern tier.
- **Threshold decision (challengeable):** recorded as a taste row in `decision-challenges.md`.

## Observability

```yaml
liveness_signal:
  what:            "CI green for the guard suite + vitest lifecycle suite + encryption-posture lint (the change IS the observability machinery; the alerts it guards stay inert until #11266's signed bundle)"
  cadence:         "every PR (deploy-script-tests + vitest), every push to main (test-all + apply workflows)"
  alert_target:    "CI required-check failure / notify-main-failure email"
  configured_in:   ".github/workflows/infra-validation.yml:896,902; apps/web-platform/test/server/inngest/agent-on-spawn-lifecycle.test.ts; scripts/lint-encryption-posture.py"

error_reporting:
  destination:     "Sentry web-platform (reportSpawnDeadLetter unchanged path, now once per replay); guard/vitest failures print [FAIL]/assertion diffs to CI log"
  fail_loud:       "a [FAIL] line or nonzero exit in the guard; a red vitest assertion; a lint FAIL line"

failure_modes:
  - mode:          "drift-guard silently weakened (dead-text, decoy, mute knob, env-axis halving)"
    detection:     "new mutation rows each requiring inner-run rc=1 with a named [FAIL] fragment; mutate_floor_red trips the floor"
    alert_route:   "infra-validation.yml required check red"
  - mode:          "persistFailure double-reporting regresses"
    detection:     "runLikeInngest replay test asserts deadLetters()==1 with invocations>=2"
    alert_route:   "vitest suite red"
  - mode:          "ledger misdescribes the step-call leg again"
    detection:     "lint-encryption-posture.py resolves every schema field + disclosed_as anchor"
    alert_route:   "test-all.sh leg red"

logs:
  where:           "GitHub Actions run logs (infra-validation, vitest, test-all); guard [ok]/[FAIL] ledger lines"
  retention:       "GitHub Actions default retention"

discoverability_test:
  command:         bash -c 'env MUT_SKIP=1 bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh'
  expected_output: "0 failed"
```

## Encryption Posture

```yaml
at_rest: []  # no new persistent store — the batch edits a guard, a report call, a ledger row and a CI env pin
in_transit:
  - connection: "dedicated inngest host -> Cloudflare edge -> web-1 origin (app.soleur.ai/api/inngest step-call leg — the ledger row being amended, connections[6])"
    enforced_at: "apps/web-platform/app/api/inngest/route.ts (serveOrigin: SERVE_HOST, :121,216); apps/web-platform/infra/dns.tf (cloudflare_record.app); apps/web-platform/infra/seo-config-rules.tf"
    tls: "hop 1 inngest->CF edge: HTTPS, certificate verified by the Inngest server's HTTP client against a public CA (recorded as not-yet-measured against the server build, per the issue's 'measured against the Inngest server's HTTP client'); hop 2 CF edge->origin: per the row's existing #10479 posture (NONE if flexible)"
    cert_verification: off  # hop 2 unverified — unchanged from the existing row
    does_not_defend: "step-call inputs and outputs readable/alterable on the CF->origin hop while it is unverified (#10479 tracks the fix)"
    disclosed_as: "not-publicly-claimed"
exception:
  justification: "unchanged from the existing row — the CLO ruled 2026-10-27 (#10479) this hop is fixed, not accepted; the block exists because the schema requires one for a connection without certificate verification"
  tracking_issue: "#10479"
  reevaluate_when: "the origin serves TLS with a Cloudflare-verifiable certificate, the app.soleur.ai rule is strict and a handshake probe is recorded; or app.soleur.ai is routed through the Cloudflare Tunnel; or 2026-11-12, whichever is first"
  expires_on: "2026-11-12"
```

## Guard Contract

### Guard 1 — `inngest-luks-wrong-volume-alert.test.sh` (hardened)

**Property.** No weakening of the `inngest_luks_wrong_volume` alert's predicate, parameters, source wiring, arming path, or the guard's own battery leaves the suite green — and no dead text (comment-wrapped or decoy copies) satisfies a presence row.

**Assembly.** The extraction chokepoint (`sql_local` awk over `betterstack-logs-alerts.tf` feeding the whitespace-stripped canonical-equality compare — every conjunct, literal and window flows through it), the two `res_block`-scoped `param()` assertion sets on the exploration and alert resources, the `VAR_BLOCK` single-opener count over `variables.tf`, the `-target=` rows over `apply-web-platform-infra.yml`, the emitter/stage/shipper derivations over `inngest-bootstrap.sh` + `cloud-init-inngest.yml` + `scripts/lib/inngest-probe-row.sh`, and the battery's own dispatch (`mutate_red` rc-discrimination, instrument control, `PRESENCE_ROWS`/`MUT_ROWS` floor). Structural, not member-enumerated: the canon covers the predicate whatever conjuncts it grows; `param()` binds attributes whatever their values' spelling.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | `/* */`-wrap a verbatim conjunct copy + a decoy `…_sql = <<-SQL` opener before the live local while gutting the live body | RED (canon equality — extraction no longer matches) |
| 2 | Comment out `paused = !var.inngest_luks_cutover_complete` inside the alert block and add `paused = true` | RED (param exactly-once within block) |
| 3 | `count(*)` → `0` in the SELECT | RED |
| 4 | `values = [local.vector_prd_source_id]` → another source local, or `FROM {{source}}` → `{{other}}` | RED |
| 5 | Drop `WHERE time BETWEEN {{start_time}} AND {{end_time}}` | RED |
| 6 | `operator = "higher_than"` → `"lower_than"`, or `value = 0` → `999999` | RED |
| 7 | Add `lifecycle { ignore_changes = [paused] }` (or `count`/`for_each`) inside the alert block | RED (negative param rows) |
| 8 | `/* */`-wrap a decoy `variable "inngest_luks_cutover_complete" { default = true }` ahead of the real block | RED (VAR_BLOCK opener count == 1) |
| 9 | `data_mount_devid=$${local…}` `$$` interpolation escape in the SQL | RED (canon) |
| 10 | Neutralize a needle by inline tautology `(… = 0 OR … > 0)` | RED (canon) |
| 11 | Wrap the runbook local reference in a `#` comment | RED (param on `metadata.runbook`/`incident_cause` naming the local) |
| 12 | DISPATCH: raise `PRESENCE_ROWS` by one in a scratch copy | RED (floor trips — `mutate_floor_red`) |
| 13 | SECOND MEMBER: a second `logtail_exploration_alert "inngest_luks_wrong_volume_x"` pinning `exploration_id` to the same exploration | RED (param/census count on the pair) |
| 14 | must-PASS: reword a `#` comment outside any resource block | GREEN (`mutate_green`) |
| 15 | must-PASS: add a `#`-comment line inside the locals block that names no pinned token | GREEN (`mutate_green`) |

### Guard 2 — spawn-dead-letter exactly-once (replay regression)

**Property.** `persistFailure` emits `reportSpawnDeadLetter` exactly once per dead-lettered spawn no matter how many requests the run replays across.

**Assembly.** The single call site inside `persistFailure` — the one chokepoint all ~15 call sites funnel through — positioned after the last `step.run` in that function, verified by `runLikeInngest`'s replay model driving the exported handler.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Move `reportSpawnDeadLetter` back above the `notify-cost-breaker` step | RED (`deadLetters() == 2` on the no-notify arm) |
| 2 | Wrap the report inside a new `step.run` callback AND leave a direct call | RED (count > 1 or harness flags duplicate step id) |
| 3 | DISPATCH: memo-preseed `persist-failure` so `invocations < 2` — the test cannot observe a replay | RED (the `invocations >= 2` assertion fails, not vacuous green) |
| 4 | SECOND MEMBER: a second out-of-step `reportSpawnDeadLetter` added after the first | RED (count == 2) |
| 5 | must-PASS: reorder the two memoized steps' ids (e.g., persist before notify in a seeded memo) without touching the report | GREEN |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "[issue #11528] Decide which of 2–4 deserve presence+mutation rows per sibling-guard convention, and add them." | WS-A presence+mutation rows (Phase 1); Guard 1 matrix rows 2-11 | mapped |
| 2 | "[issue #11528] For 1: decide whether the fix is an anchored line-regex, an `exit` on terminator + decoy-opener detection, or a comment/HCL-aware extraction — then apply the same remedy across the guard family (or scope explicitly to this file and file the family remainder)." | Canon-equality remedy on this file + Phase 4 remainder issue; decision-challenges row | mapped |
| 3 | "[issue #11528] For 5: decide whether CI should pin `MUT_SKIP` unset." | `env -u` pins on the two epic-family run lines + remainder issue | mapped |
| 4 | "[issue #8841] Each dead-letter is reported exactly once, for example by reporting after the last step, or from a memoized step." | WS-B call-site move (Phase 2) | mapped |
| 5 | "[issue #8841] Add a regression test on `test/helpers/inngest-step-harness.ts` (`runLikeInngest`), which models the replay." | WS-B vitest replay tests | mapped |
| 6 | "[issue #9139] Add an in-transit entry for the step-call leg. Its `enforced_at` would be the route.ts `SERVE_HOST` and `dns.tf` `cloudflare_record.app`. Its `tls` would be HTTPS through the Cloudflare proxy, and its cert verification should be measured against the Inngest server's HTTP client." | WS-C `connections[6]` amendment (entry already exists per #11487 — amend not duplicate) | mapped |
| 7 | "[issue #9139] Then narrow the existing entry's `does_not_defend` to what actually crosses the private link: event sends, registration and the `/v1` API." | Verify-only AC (already narrowed by #11487) | mapped |
| 8 | "[brief] remove scripts/followthroughs/inngest-verify-clean-10390.sh" | AC residual-zero grep | descoped — justification: file already deleted on origin/main by PR #11381; only the assertion remains |
| 9 | "[brief] record this section VERBATIM in the plan file" (Operator Holds) | `## Operator Holds` verbatim | mapped |
| 10 | "[brief] record the CTO batching ruling as a row (Class: technical …)" | decision-challenges.md row 1 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `inngest-luks-wrong-volume-alert.test.sh` rewrite | "Decide which of 2–4 deserve presence+mutation rows per sibling-guard convention, and add them." | asked |
| `env -u` pins in `infra-validation.yml` | "decide whether CI should pin `MUT_SKIP` unset." | asked |
| `reportSpawnDeadLetter` move | "reporting after the last step" | asked |
| replay regression tests | "Add a regression test on `test/helpers/inngest-step-harness.ts` (`runLikeInngest`)" | asked |
| `connections[6]` ledger amendment | "Add an in-transit entry for the step-call leg" + "narrow the existing entry's `does_not_defend`" | asked |
| family-remainder issue (Phase 4) | "or scope explicitly to this file and file the family remainder" | asked |
| `decision-challenges.md`, `tasks.md` | "record the CTO batching ruling as a row"; pipeline-mandated artifacts | asked |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform` (test + server + workflow), `scripts` (ledger), `knowledge-base` (spec artifacts)
- Planned files: 7 | Estimated changed lines: ~500 (guard rewrite ~350, test ~60, ledger ~15, workflow ~2, server ~10)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — below every threshold; the three issues share the epic and the merge-queue cycle was CTO-ruled as one batch.

## Domain Review

**Domains relevant:** engineering (infra/observability machinery) — assessed in-process.

No cross-domain implications detected beyond Engineering — a drift-guard/test/ledger hardening batch with no user-facing surface, no legal-doc wording change (`disclosed_as` stays `not-publicly-claimed`), no ops procedure change. No Agent tool exists in this harness, so domain leaders could not be spawned; the limitation and the self-assessment are recorded in `decision-challenges.md` per the established headless convention.

## Architecture Decision (ADR/C4)

No architectural decision is made: the batch pins existing resources, fixes an observability bug on an existing path, and corrects a ledger description of an edge `model.c4` already records (`inngest -> api`, `diagrams/model.c4:794-799` — verified: serve URL, Cloudflare proxy, web-1 execution, `--sdk-url` as registration poll are all present in the edge prose; views include it via the `inngest` container). No ADR, no `.c4` edit. C4 completeness enumeration checked: external actors (none new), external systems (Inngest self-hosted server, Cloudflare — both modelled), containers/data-stores (none new), access relationships (inngest→api step-call — already modelled).

## Acceptance Criteria

- [ ] **AC1.** `bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` exits 0 with `0 failed`; `env MUT_SKIP=1 bash …` also `0 failed`. The suite prints `PRESENCE_ROWS`/`MUT_ROWS`-derived floors, not magic numbers.
- [ ] **AC2.** The guard asserts canonical-equality of the whitespace-stripped `inngest_luks_wrong_volume_sql` against `WRONGVOLUME_CANON` built from `INNGEST_PROBE_MARKER`/`MUT_EMITTER`/`MUT_STAGE`/`MUT_SHIPPER` (grep: `WRONGVOLUME_CANON` present; `[ "$…_SQL" = "$WRONGVOLUME_CANON" ]` or equivalent compare row present).
- [ ] **AC3.** `param()`-style rows pin, each exactly-once within its `res_block`: `source_variable`, `values`, `sql_query`, `exploration_id`, `name`, `alert_type`, `operator`, `value`, `check_period`, `query_period`, `recovery_period`, `on_missing_data`, `paused`, `confirmation_period`, `email`, escalation block, `runbook`/`incident_cause` naming `local.inngest_luks_wrong_volume_runbook_url`; and a negative row rejects `count`/`for_each`/`lifecycle`/`ignore_changes` inside either resource block.
- [ ] **AC4.** `VAR_BLOCK` extraction asserts exactly one `variable "inngest_luks_cutover_complete"` opener file-wide.
- [ ] **AC5.** The battery includes mutation rows for: decoy heredoc with gutted live body; `/* */` decoy variable block; commented `paused` line; `count(*)`→`0`; source repoint; `WHERE…BETWEEN` drop; `operator`/`value` flip; `query_period`/`check_period` widen; `lifecycle`/`for_each`/`count` add; `$$` escape; inline tautology; runbook-in-comment; floor self-mutation; ≥2 `mutate_green` must-PASS rows — each fragment-scored through `_red_verdict`.
- [ ] **AC6.** A scrub-immunity row asserts `data_mount_devid`/`host_role`/`shipper`/`stage`/the marker key are absent from `vector.toml`'s `pii_scrub_string` `replace(msg` rewrites (mirroring the sibling's `verdict` row).
- [ ] **AC7.** `infra-validation.yml`'s wrong-volume and key-probe run lines carry `env -u MUT_SKIP` plus the suites' own `*_GUARD_*` overrides.
- [ ] **AC8.** In `persistFailure`, `reportSpawnDeadLetter(` occurs exactly once and textually AFTER the `persist-failure` `step.run` (and its catch), before `return`; the ordering comment states the new rationale.
- [ ] **AC9.** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/agent-on-spawn-lifecycle.test.ts` is green, including a replay test asserting `deadLetters().length === 1` with `invocations >= 2` on at least the no-notify arm (notify arm if the pause path is reachable with the existing fakes).
- [ ] **AC10.** `python3 scripts/lint-encryption-posture.py` exits clean; `connections[6]`'s `enforced_at` names `app/api/inngest/route.ts` and `cloudflare_record.app`, and its `in_transit` prose distinguishes the two hops; `connections[5]`'s `does_not_defend` no longer attributes step outputs to the private link.
- [ ] **AC11.** `git grep -n "inngest-verify-clean-10390" -- scripts/ .github/ plugins/ apps/ infra/` returns zero lines.
- [ ] **AC12.** `gh issue view <family-remainder>` exists and names each remaining MUT_SKIP-idiom guard file + the comment/decoy extraction class.
- [ ] **AC13.** No `grep | grep -q` pipes in the rewritten guard (grep-q-pipe-guard #9217); `grep -cF`/`grep -cE` `>/dev/null` forms only.
- [ ] **AC14.** No edit touches `inngest-cutover-flip.sh`, `cloud-init-*.yml`, or any `betterstack-logs-alerts.tf` content (GuardA carrier + #11653 race); `git diff --name-only origin/main...HEAD` confirms the file set ⊆ {the 7 files above}.

## Test Scenarios

- Given a `/* */`-wrapped decoy heredoc carrying every conjunct placed before the live local with the live body reduced to `SELECT 1`, when the guard runs, then the canon-equality row goes RED (unit, mutation battery).
- Given `paused = true` plus a commented `paused = !var…` decoy line inside the alert block, when the guard runs, then the `paused` param row goes RED (unit).
- Given `MUT_SKIP=1` exported in the environment, when the workflow step runs, then `env -u` clears it and the outer battery executes (integration — verified by reading the run line; CI proves it at merge).
- Given a dead-lettered spawn path replaying across ≥2 invocations, when `agentOnSpawnRequestedHandler` runs under `runLikeInngest`, then `deadLetters().length === 1` (unit).
- Given `reportSpawnDeadLetter` moved before the steps (the pre-fix shape), when the same test runs, then the count is ≥2 — the test reds on the old code (unit, verified once during implementation then reverted).
- Given the amended ledger, when `lint-encryption-posture.py` runs, then all schema fields resolve and `does_not_defend`/`exception` checks pass (integration).
- Given `git grep -n "inngest-verify-clean-10390"` over the code scopes, when the tree is checked, then zero hits (integration).

## Open Code-Review Overlap

3 open scope-outs touch planned files:

- **#10112** (encryption-posture-ledger.json — rehearsal-volume `stores` rows, #9786 residuals): **acknowledge** — different ledger section (`stores`, not `connections`); no conflict, not folded (its dissent is recorded).
- **#8735** (infra-validation.yml — notify-main-failure misses cancelled jobs): **acknowledge** — different job/step; the `env -u` edit touches run lines only.
- **#7942** (`*.mutation.sh` naming in `plugins/soleur/test/`): **acknowledge** — different tree (`plugins/`, not `apps/web-platform/test/infra/`); no naming change this PR.

## Non-Goals / Out of Scope

- `inngest_luks_key_probe_dark` dead-man alert — explicitly deferred (do NOT add; negative row precedent exists in the sibling guard).
- Comment/decoy-aware extraction + `env -u` spread across the other MUT_SKIP-idiom guards — filed as the family remainder (Phase 4), per the issue's own scope option.
- Leg-A paren-asymmetry symmetry fix vs `ghcr_hostsfile_deny_lost_sql` — deferred per the CTO map's own deferral note.
- The probe going live — inert until #11266's signed-bundle delivery; no alert claims operational coverage of host behavior.
- `lint-encryption-posture.py` changes — schema already satisfied by the amendment.
- The envelope file `inngest-epic-10390-envelope.md` — no gated acts prescribed (see Operator Holds note).

## Risks & Mitigations

- **#11653 lands mid-queue** and edits `betterstack-logs-alerts.tf`: the guard asserts the wrong-volume block's exact text — a neighboring edit that shifts the block's shape reds the guard. Mitigation: Phase 0 re-checks `gh issue view 11653 --json state`; on race, re-baseline `WRONGVOLUME_CANON`/anchors on re-push.
- **Canon-equality brittleness**: any legitimate .tf edit to the predicate now requires updating the canon in the same PR — intended (that coupling IS the drift guard); the guard's failure message prints the extracted-vs-canon diff context, and a `mutate_green` row proves comment-only edits stay green.
- **Notify-arm test reachability**: driving `check-runtime-pause` needs the resolver + prompt-module + pause-row mocks; if the pause path proves unreachable with the existing fakes, the no-notify arm (2 invocations, the exact defect) still proves the fix and the notify arm is covered by code inspection + the settle-side convention — recorded as a test-scope note, not a gap.
- **Ordering inversion** (notify now precedes the dead-letter report in wall time): accepted — a `notify-cost-breaker` final failure propagates to `onFailure`→settle, which reports the run's dead-letter itself; the mirrored ordering comment is updated.
- **Move loses the report on `persist-failure` step exhaustion**: the step's StepError is caught by the existing `catch` → `reportSpawnPersistFailed`, then the moved report still fires — both events land exactly once.

## References

- Issues: #11528 (structural map comment is the authoritative enumeration), #8841, #9139, epic #10390; delegation comment `…issuecomment-6361717901`.
- PRs: #11559 (wrong-volume dual-channel), #11601 (key-probe sibling guard — convention donor), #11487 (ledger CF-edge entry), #11381 (verify-clean deletion).
- Files: `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` (sibling), `apps/web-platform/test/helpers/inngest-step-harness.ts`, `scripts/encryption-posture-ledger.json`, `scripts/lint-encryption-posture.py`, `apps/web-platform/infra/betterstack-logs-alerts.tf:306-404`, `.github/workflows/infra-validation.yml:896-903`, `apps/web-platform/app/api/inngest/route.ts:121,216`, `model.c4:794-799`.
- ADRs: ADR-100, ADR-140, ADR-243 (#8611 serve-URL), ADR-294.
