---
title: "fix: close #9639 residuals — git-data probe wrapper expansion, boot-trail emit, nic-guard unpinned_url alert"
date: 2026-10-26
slug: fix-9639-probe-residuals
branch: feat-one-shot-9639-probe-residuals
issue: 9639
---

## Overview

Issue #9639 groups the residual findings of the egress-probe credential-hardening review
(PR #9632 plan-deepen). F5 and the nic-guard/zot arms of F6 already shipped via merged PRs
(#10637, #10363). Three findings remain open:

- **F6 residual:** `apps/web-platform/infra/web-git-data-probe.service` is the last doppler-run
  unit whose `ExecStart` expands an injected secret (`export GIT_DATA_HEARTBEAT_URL="$${!GIT_DATA_HEARTBEAT_URL_KEY}"`
  inside an inner `bash -c`) before the target script can refuse to run under xtrace. The sibling
  fix — script resolves the URL through the `*_KEY` name itself, after an unconditional xtrace
  refusal — has not been applied here because the script carries no refusal at all today.
- **F7:** `cloud-init.yml` poweroffs the host when `cron-egress-enforce-probe.sh` exits non-zero,
  with no `soleur-boot-emit` beforehand — a refused (exit 78, deliberately silent) or failed probe
  is invisible without the cloud-init log.
- **F8:** no standing `logtail_exploration_alert` covers `SYSLOG_IDENTIFIER='web-nic-guard'` rows
  containing `unpinned_url` — the refused-direct-POST mode is only visible through a post-merge
  query.

# fix: close #9639 residuals — git-data probe wrapper expansion, boot-trail emit, unpinned_url alert

PR body: `Closes #9639` (all four findings resolved once F6's last arm, F7 and F8 land). Draft PR follows the merge queue; two infra PRs ahead of this branch carry the post-#11159 test-red fixes — expect a rebase/queue refresh before merge.

## Problem Statement / Motivation

Issue #9639 groups the residual findings of the egress-probe credential-hardening review
(PR #9632 plan-deepen). F5 (root sourcing a deploy-owned file) and the nic-guard/zot arms of
F6 shipped via merged PRs (#10637, #10363). Three findings remain open, all measured present on
`origin/main` today:

- **F6 residual (credential exposure):** `web-git-data-probe.service:28` runs
  `doppler run … -- bash -c 'export GIT_DATA_HEARTBEAT_URL="$${!GIT_DATA_HEARTBEAT_URL_KEY}"; exec /usr/local/bin/web-git-data-probe.sh'`.
  The inner `bash -c` resolves the heartbeat URL — a credential — *before* the script can refuse
  to run under xtrace, so a traced launch (`SHELLOPTS=xtrace`, `BASH_ENV`, `bash -x`) prints the
  secret to stderr → journald → off-box. It is the **only** doppler-run unit still carrying the
  shape (grep over every `*.service` Exec directive confirms; `web-bash-synthetic.service` wraps
  its target in `bash -p` but expands nothing).
- **F7 (blind poweroff):** `cloud-init.yml` invokes `cron-egress-enforce-probe.sh` after the app
  container starts and `poweroff -f`s on non-zero exit with no `soleur-boot-emit` first. The
  probe's xtrace refusal (exit 78) is deliberately silent — no Sentry event — so a refused boot
  is visible only in the cloud-init log the operator cannot reach.
- **F8 (unpaged refusal mode):** `web-private-nic-guard.sh`'s `unpinned_url` arm refuses to POST
  the Better Stack token to an unpinned destination and withholds the beat — visible today only
  through a post-merge query. The marker is `[nic]`-prefixed (not `SOLEUR_`) and journald-tagged
  `SYSLOG_IDENTIFIER=web-nic-guard`, so the `monitor_send_failed` alert's `SOLEUR_*`/`PRIORITY='2'`
  predicate cannot see it.

## Research Reconciliation — Spec vs. Codebase

| Routing claim (input brief) | Measured on `origin/main` | Plan response |
|---|---|---|
| "`web-git-data-probe.service` line ~28 still expands `${!GIT_DATA_HEARTBEAT_URL_KEY}` inside an inner `bash -c`" | Confirmed verbatim at `:28`; the only `*.service` Exec directive carrying `${!` | F6 arm proceeds as scoped |
| "`web-git-data-probe.sh`'s xtrace refusal" | The script has **no** refusal at all — `set -u`, `URL="${GIT_DATA_HEARTBEAT_URL:-}"` at `:27` | The script gains the refusal AND the post-refusal key resolution (both halves of the sibling contract) |
| "extend `doppler-injection-bound.test.sh` coverage to the git-data unit the same way it covers the fixed siblings" | The suite already enforces the invariant; the unit is exempted via `WRAPPER_ACK_REASONS` (cardinality-pinned 1, the "surviving unfixed sibling") and its own stale-ack check `wrapper_stale` **requires** the entry be deleted once the unit stops expanding | Extend coverage = delete the ack entry + lower pin 1→0; the mutation rows that name the unit as "the unfixed sibling" (G1.6, G1.10, G1.10b/c, `drop-wrapper-ack`, `ack-extra-name`) must be re-scoped in the same diff |
| "F7: cloud-init.yml ~line 822 runs `poweroff -f` … with no soleur-boot-emit beforehand" | Confirmed at `:822-825`; sibling fail-closed block at `:771` already emits `hostscripts_incomplete` before its poweroff | Emit `soleur-boot-emit <stage> fatal` before `poweroff -f`; capture the probe's real exit code into `/run/soleur-stage-detail.d/<stage>` so refused(78) vs failed(1) is discriminated |
| "F8: lacks a logtail_exploration_alert on `SYSLOG_IDENTIFIER='web-nic-guard'` rows containing `unpinned_url`" | Confirmed — no `web-nic-guard` or `unpinned_url` conjunct in `betterstack-logs-alerts.tf`; `SYSLOG_IDENTIFIER` conjunct idiom exists (e.g. `:901` luks-monitor) | New alert per the 7-step recipe at `betterstack-logs-alerts.tf:42-58` (incl. `-target=` allowlist lines, drift-guard suite, runbook, standing-alarms row, exploration-count bump 17→18) |
| "the fixed-nic-guard PR #10637 precedent shows how units propagate" | PR #10637 MERGED 2026-10-20: `terraform_data.git_data_probe_install` `triggers_replace` hashes the three files → per-merge apply re-fires SSH `file` provisioners to web-1; web-2 gets them baked via `soleur-host-bootstrap.sh` | No host replace; propagation = the routine per-merge apply. Stale-comment sweep (envwrite + web-probe.tf + scanner headers + ADR-202) is a required task — the F6 retro counted ~8 prose sites still describing the old wrapper expansion |

## Research Insights

**Premise Validation (Phase 0.6).** Checked: `gh issue view 9639` → OPEN, no closing PRs; every
cited file exists on `origin/main`; PR #10637 merged; the residual shapes measured directly
(grep over all `Exec*` directives, script source, cloud-init block, alert .tf, ack dicts).
Stale: one — the brief says the script's "xtrace refusal" exists; it does not, so the F6 arm
adds both the refusal and the key resolution (the sibling contract is two halves, not one).
ADR corpus: ADR-202's 2026-10-20 addendum already rules the mechanism ("a unit that runs a
credential-handling script must not resolve the secret by indirect expansion in an `Exec*`
directive") and names the two unfixed units — the plan applies that ruling, it does not
re-litigate it; the addendum's ack-set sentence becomes stale on merge and is amended in-plan.

**Property List (Phase 0.6b).**

- P1: no `doppler run` unit's `Exec*` directive expands an injected secret — the unit wrapper is inside the refusal's reach (ADR-202 addendum).
- P2: a refused-or-failed boot-time egress probe leaves a boot-trail event before `poweroff -f` kills the host.
- P3: `unpinned_url` refusals page without a post-merge query.

**Cut List (Phase 0.6b).**

- Marker-rename (emit `SOLEUR_*_REFUSED` instead of `[nic] unpinned_url`) to opt into `monitor_send_failed` → P3 → rejected: the opt-in path is documented as SOLEUR_*/PRIORITY-2-only, the `[nic]` refusal lines are the sibling-consistent telemetry shape, and the issue prescribes the alert.
- A refusal-rate limiter (`_refusal_due`) for the git-data script's `SOLEUR_CREDENTIAL_REFUSED` → buys nothing in the ask; not in the sibling-required contract for the URL-resolution move → cut (documented in Non-Goals).
- Any shared helper for the `_key_ok` + resolve block → infra scripts are deliberately self-contained/inlined ("this host has no checkout, so this is the inline form of the library") → cut; byte-parity test rows bind the copies instead.

**Files of record.**

- `apps/web-platform/infra/web-git-data-probe.service:28` — the residual `ExecStart` (target of F6).
- `apps/web-platform/infra/web-git-data-probe.sh` — gains unconditional xtrace refusal (sibling shape: `case "$-" in *x*) … exit 78`) + `_key_ok` + post-refusal `URL="${!GIT_DATA_HEARTBEAT_URL_KEY:-}"` resolution into an unexported var.
- `apps/web-platform/infra/web-private-nic-guard.sh:155-160`, `inngest-consumer-probe.sh:100-112`, `web-zot-consumer-probe.sh:262-269` — the byte-shape to mirror (fourth `_key_ok` copy → parity row binds all four, learning 2026-10-25).
- `apps/web-platform/infra/doppler-injection-bound.test.sh` — `WRAPPER_ACK_REASONS` `:325-330`, `WRAPPER_ACK_CARDINALITY` `:334`, header scoping items 4-5 `:47-69`, INNER_C comments `:341-380`, mutation programs `:1240-1295`, G1.x rows `:1341-1422`.
- `apps/web-platform/infra/web-git-data-probe.test.sh` — env harness (`GIT_DATA_HEARTBEAT_URL=` → key-name + value pair) + new F6 block mirroring `inngest-consumer-probe.test.sh:525-666`.
- `apps/web-platform/infra/server.tf:1295-1347` (`terraform_data.git_data_probe_install`, `triggers_replace` sha256 over the three files — propagation, unchanged) + `:1340` (env-file printf already writes `GIT_DATA_HEARTBEAT_URL_KEY=GIT_DATA_HEARTBEAT_URL`).
- `apps/web-platform/infra/web-probe-envwrite.sh:83` (same env printf for fresh hosts) + its stale comment at `:46-48`.
- `apps/web-platform/infra/web-probe.tf:~128` — stale "git-data and inngest units still do it in their wrapper" comment.
- `apps/web-platform/infra/cloud-init.yml:757-827` — F7 site (`:822-825`) and the `:771` emit-before-poweroff precedent.
- `apps/web-platform/infra/soleur-host-bootstrap.sh:243-311` — `soleur-boot-emit <stage> [level]`; stage name is free-form (used as Sentry tag + `/run/soleur-stage-detail.d/<stage>` file).
- `apps/web-platform/infra/betterstack-logs-alerts.tf` — add-alert recipe `:42-58`; `SYSLOG_IDENTIFIER` idiom `:901`; `monitor_send_failed` alert shape `:122-165` (paging semantics to copy); `escalation_target` paid-tier ternary.
- `.github/workflows/apply-web-platform-infra.yml:~651-684` — MAIN plan `-target=` allowlist (two lines per alert).
- `.github/workflows/infra-validation.yml` — per-alert drift-guard `run: bash` steps `:863-931` + `paths:` filters.
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh:269-280` — `assert s.count(old) == 17` pins the `values = [local.vector_prd_source_id]` exploration count → 18.
- `apps/web-platform/test/infra/ghcr-blocked-alert.test.sh` — the drift-guard suite template (`*_GUARD_*` env overrides, emitter-pinned needles, mutation rows).
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md:16-31,1194-1207` — standing-alarms table + existing `unpinned_url` decode guidance.
- `knowledge-base/engineering/architecture/decisions/ADR-202-enforce-runtime-state-hazards-with-a-carried-self-refusal.md:210-214` — the addendum to amend.

**Learnings applied.**

- `2026-10-25-third-copy-of-a-security-guard-needs-a-parity-row.md` — fourth `_key_ok` copy gets a four-way byte-parity row and the upper-case-led body-clause key table; a "lean port" must not drop the hostile-key/env axis rows.
- `security-issues/2026-10-19-a-hostile-fixture-must-put-the-payload-in-the-value-the-fix-reads.md` — hostile payload goes in the KEY value (`a[$(touch PLANT)]`), the consumption point the fix reads.
- `test-failures/2026-10-20-a-privacy-narrowing-of-my-env-dump-by-name-removed-the-property-the-row-tested.md` — env-capture row must exclude the key-named line only, not the property.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` — mutation matrix in the Guard Contract below is derived from the design, not the diff.
- `2026-09-22-my-sweep-was-keyed-on-a-literal-and-the-claim-had-another-spelling.md` + the F6 retro ("about eight prose sites") — the stale-claim sweep greps the *claim* repo-wide, not the files the diff touches.
- `test-failures/2026-10-14-a-mutation-row-is-vacuous-until-a-fixture-distinguishes-the-mutant.md` — re-scoped G1.x rows keep a fixture that distinguishes the mutant.
- `test-failures/2026-10-11-a-unit-file-content-pin-must-model-systemds-parser-not-the-files-bytes.md` — static unit rows join backslash continuations as systemd reads them.
- `2026-10-11-conditioning-a-unit-also-conditions-every-detector-wired-to-its-failures.md` — removing the unit's expansion is what *trips* the stale-ack check; the ack removal and the unit fix are one atomic diff.

**External research:** skipped — security topic, but the sibling implementation (merged PRs
#10637/#10363) plus its codified CTO rulings and ADR-202 addendum are the authoritative pattern;
every open question is repo-ruled, not industry-open.

## Technical rulings (persisted in `specs/feat-one-shot-9639-probe-residuals/decision-challenges.md`)

- Refusal form in `web-git-data-probe.sh`: unconditional (matches nic-guard/inngest — the script always resolves a credential; no `--canary-only` context exists where the key is legitimately unset, unlike zot's conditional). `pending - assumed` (no spawn surface).
- F8 mechanism: new `logtail_exploration_alert` (issue-prescribed) vs marker-rename + `monitor_send_failed` needle — `pending - assumed: new alert` (opt-in path is SOLEUR_*/PRIORITY-2-only; renaming re-opens the sibling-consistent `[nic]` refusal telemetry shape).
- F7 emit naming + detail: stage `egress_enforce_probe`, detail file carries `rc=<exit>` so refused(78)/failed(1) discriminate — mechanical, mirrors `hostscripts_incomplete` at `cloud-init.yml:771`.

## Architecture Decision (ADR/C4)

### ADR

**Amend ADR-202** (`knowledge-base/engineering/architecture/decisions/ADR-202-enforce-runtime-state-hazards-with-a-carried-self-refusal.md`, 2026-10-20 addendum at `:210-214`): the sentence "except for two units not yet fixed (`web-git-data-probe`, `inngest-consumer-probe`, recorded on #9639)" becomes false on merge — inngest was already fixed by #10363 and this PR fixes web-git-data-probe. Rewrite it as a status line: all four probe units now resolve their `*_URL_KEY` inside the script after the refusal; `WRAPPER_ACK_REASONS` is drained to empty (cardinality 0, ratchet-down only). In-plan task (Phase 4), not a follow-up issue — `wg-architecture-decision-is-a-plan-deliverable`.

### C4 views

No C4 impact. Read for this check: `model.c4` (1032 lines), `views.c4` (142), `spec.c4` (54). Enumerated per the completeness mandate: (a) external human actors — none added or changed; (b) external systems — Better Stack (`betterstack`, `model.c4:489`) and Doppler are already modeled and their edges are unchanged (the new logtail alert is a Better-Stack-side object on an already-modeled system, identical in kind to the seven sibling `logtail_exploration_alert`s none of which are individually modeled); (c) containers/data stores — none touched; per-unit systemd probe units are not modeled (the F6 sibling reached the same conclusion after the same read); (d) actor↔surface access relationships — unchanged (the F6 arm moves WHERE an existing credential is resolved, not who can read it). The work phase re-runs `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` (no `.c4` file is edited, so they must stay green).

### Sequencing

The ADR amendment describes the state after this PR merges and applies; no soak gate.

## Guard Contract

### Guard 1 — Unit wrappers never expand a doppler-injected secret (wrapper stage in `doppler-injection-bound.test.sh`)

**Property.** No `Exec{Start,StartPre,StartPost}` of any `doppler run` unit the scanner enumerates contains an indirect expansion (`${!NAME}` plus operator spellings) unless the unit is in the authored, cardinality-pinned `WRAPPER_ACK_REASONS` dict, and every ack names a unit that still expands — post-merge the dict is EMPTY (the last survivor is fixed) and any re-introduced expansion is an unacked `FINDING`.

**Assembly.** The scanner's four unit surfaces plus the injected-directive surface (`service`, `sh-heredoc`, `tf-heredoc`, `cloud-init`, `sh-injected`), every `Exec*` directive of every enumerated unit (`infos`, not first match). Chokepoints: `analyse_exec()`'s `indirect` list for detection; the `stale_w` check (`WRAPPER_ACK_REASONS − wrapper_hits`) for ack hygiene — it is the check that *forces* this PR's ack deletion, so the unit fix and the dict edit are one atomic change. Population side: the script-side `${!<NAME>_KEY}` expansion keeps the unit in the Guard-2 population through its existing `ACK_REASONS` entry (cardinality 9, unchanged).

**Mutation matrix.**

| # | Mutation (fixture copy of the tree, never the real files) | Must go RED because |
|---|---|---|
| W1 | Restore `export GIT_DATA_HEARTBEAT_URL="$${!GIT_DATA_HEARTBEAT_URL_KEY}"` in the fixture git-data unit | unacked unit-side indirect → `FINDING unit=web-git-data-probe.service reason=wrapper expands a secret` (rc 2) — proves the ack was the only thing covering it |
| W2 | Delete `wrapper_checked += 1` (stage counter) in the scanner source | own-dispatch: `CENSUS_FAIL wrapper_units_checked` (rc 3) — a stage checking 0 units is vacuous |
| W3 | Append a second `ExecStartPre=` carrying `${!GIT_DATA_EXTRA_KEY}` to the fixture git-data unit | the check quantifies over every directive, not the first → `FINDING … wrapper expands` |
| W4 | Add a wrapper-ack entry for the now-fixed git-data unit (pin raised to match) | stale ack → `ACK_FAIL wrapper_stale=web-git-data-probe.service` (rc 5) |
| W5 | Edit `WRAPPER_ACK_CARDINALITY` without the dict | `ACK_FAIL wrapper_ack_cardinality=<n> expected=<n-1>` (rc 5) — the pin cannot drift silently |
| W6 | Leave the git-data `WRAPPER_ACK_REASONS` entry in place while fixing the unit | `ACK_FAIL wrapper_stale` (rc 5) — the drift direction this PR itself creates; proves the atomic-edit requirement is enforced |
| W7 (harness) | must-PASS: the fixed `ExecStart` shape (`doppler run … -- /usr/local/bin/web-git-data-probe.sh`, no inner `bash -c`) in the fixture tree | GREEN — the contract is "no expansion", not a spelling; a scanner that rejects everything cannot pass this |

**Anchor.** The ack dict and pin live in the same file as the check (consistency, not integrity). Outside anchor: issue #9639 names the unit's fixed status; the dict can only ratchet down, and any new entry is a visible diff to a named tracked set.

### Guard 2 — The git-data unit's real `ExecStart` never leaks the secret under xtrace, and the script resolves it only after the refusal (`web-git-data-probe.test.sh` F6 block)

**Property.** Launching the unit's real `ExecStart` (systemd `$$` unescaped, `doppler` stubbed) under `SHELLOPTS=xtrace` or a `BASH_ENV` `set -x` exits 78 with the refusal message and the synthetic secret value appears in neither stream; and without xtrace the same launch resolves the key-named variable and delivers its value to `curl`'s stdin config — never argv, never a child environment under any other name.

**Assembly.** Launch forms: `SHELLOPTS=xtrace`, `BASH_ENV` (the unit carries no `bash -x` token). Code paths that touch the secret: every `Exec*` directive of the unit (static dollar-free/export-free sweep over continuations joined), the script's `_key_ok` validation and `${!GIT_DATA_HEARTBEAT_URL_KEY:-}` expansion (order row: lookup line must follow the refusal line), the resolved `URL` uses (`_hb_curl` stdin config, refusal markers, WARN arm), and the child environment (envdump row excluding the key-named line, which doppler legitimately injects). Mirrors `inngest-consumer-probe.test.sh:525-666` — the closest sibling (identity key, unconditional refusal, fail-soft ping).

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|---|---|
| G1 | fixture `.service` with the pre-fix `ExecStart` restored (literal in the test) | negative control: the xtrace launch MUST show the synthetic secret — proves the harness can see the defect |
| G2 | script copy with the lookup hoisted above the refusal `case` | reorder row: under `SHELLOPTS=xtrace` the secret reaches `ERR` (an ORDER property needs a reorder row, not a delete row) |
| G3 | script copy without `_key_ok`'s charset check | hostile key `a[$(touch PLANT)]` (payload in the value the fix reads — the F5 hostile-fixture lesson) executes → `PLANT` exists |
| G3b | script copy without `_key_ok`'s BODY clause (`*[!A-Z0-9_]*`) | upper-case-led hostile keys (`A[$(touch …)]`, `A[0]`, `A=B`, `A.B`, `A/B`) — the third-copy learning's discriminating table |
| G4 | script copy that `export`s the resolved URL | env-capture row: stub curl's `env` dump minus the key-named line must not contain the value |
| G5 | add a second `ExecStartPre=` expanding the secret to the fixture `.service` | the static row quantifies over every `Exec*` directive |
| G6 | stub `doppler` that exits 0 without exec'ing the script | own-dispatch: refusal text + rc 78 prove the script RAN — "no secret in output" cannot pass a launch that never ran |
| G7 (harness) | must-PASS non-canonical: production-shaped key `GIT_DATA_HEARTBEAT_URL` (identity mapping), a valid-but-unset named var (resolves empty → WARN arm, exit 0), and a stray bare `GIT_DATA_HEARTBEAT_URL` with no KEY (resolves nothing — no bare-var fallback) | GREEN — contract-permitted inputs the rows must not reject |
| G8 (harness) | `_key_ok` byte-parity row: the git-data copy vs all three siblings (nic-guard, zot, inngest) — fourth copy, per learning 2026-10-25 | RED on any drift of the copied guard, incl. the `local LC_ALL=C` pin |

**Anchor.** The pre-fix `ExecStart` literal is the only stored value and is compared to nothing in the tree (it is the mutant, not a reference) — a weakening cannot hide by editing both. Scanner Guard 1 is the independent structural backstop.

### Guard 3 — A refused/failed boot-time egress probe emits before poweroff (`cron-egress-enforce-probe.test.sh` wiring rows)

**Property.** In `cloud-init.yml`'s post-container block, a `soleur-boot-emit <stage> fatal` appears between the `cron-egress-enforce-probe.sh` invocation and `poweroff -f`, and the stage's detail file is written with the probe's real exit code — so a refused (78) or failed probe is visible without the cloud-init log.

**Assembly.** The one `if … poweroff -f; fi` site (`cloud-init.yml:~822`) — chokepoint is the block itself, extracted by awk from `if /usr/local/bin/cron-egress-enforce-probe.sh` to the closing `fi` (the `!` form is re-structured to capture `rc`; `if ! probe; then` loses the exit code to the negation). Rows live beside the existing "cloud-init boot wiring" asserts at `cron-egress-enforce-probe.test.sh:176-179`.

**Mutation matrix.**

| # | Mutation | Must go RED because |
|---|---|---|
| C1 | fixture cloud-init with the `soleur-boot-emit` line deleted from the probe block | ordering row: emit must precede `poweroff -f` inside the extracted block |
| C2 | fixture cloud-init with emit moved AFTER `poweroff -f` | order property: emit after the kill is dead code — a reorder row, not a delete |
| C3 | fixture cloud-init where the block captures no `rc` into `/run/soleur-stage-detail.d/` | the detail is what discriminates refused(78) vs failed(1); without it the emit names a stage and nothing else |
| C4 (harness) | must-PASS: the `hostscripts_incomplete` block at `:771` keeps its emit-first shape | the sibling precedent stays green — proves the extractor is not just counting `soleur-boot-emit` anywhere in the file |

**Anchor.** No stored value; the row reads the real cloud-init block each run. The emitter's own semantics (`always returns 0`, stage→detail-file mapping) are pinned by `doppler-download-error-channel.test.sh` — unchanged by this plan.

### Guard 4 — The `unpinned_url` Logs alert exists with the prescribed paging semantics and is wired into apply (new drift-guard suite `web-nic-guard-unpinned-url-alert.test.sh`)

**Property.** `betterstack-logs-alerts.tf` carries a `logtail_exploration` whose SQL selects `SYSLOG_IDENTIFIER='web-nic-guard'` rows containing `unpinned_url` on the pinned prd source, and a `logtail_exploration_alert` on it with `monitor_send_failed`'s paging semantics (threshold `higher_than 0`, `check_period 60`, `query_period 300`, `confirmation_period 0`, `recovery_period 600`, `on_missing_data="treat_as_zero"`, email-only free-tier channel, `critical_alert=false`, paid-tier escalation ternary, runbook-linked `incident_cause`); both resources sit in the apply workflow's MAIN `-target=` allowlist and the exploration's `values` is `[local.vector_prd_source_id]`.

**Assembly.** All of: the `locals` SQL heredoc (needle read from the emitter, `web-private-nic-guard.sh:138` — a reworded needle reds here), the two resources, the two `-target=` lines in `apply-web-platform-infra.yml` (the ONLY enforcement for logtail resources — `terraform-target-parity.test.ts` covers `terraform_data` only), the runbook file + its standing-alarms row in `betterstack-log-query.md`, the exploration-count pin in `betterstack-send-failed-alert-mutation.test.sh` (17→18), and the suite's own `run: bash` step + `paths:` entry in `infra-validation.yml`. Modeled on `ghcr-blocked-alert.test.sh` (`*_GUARD_*` env overrides, mutation rows over fixture copies).

**Mutation matrix.**

| # | Mutation (fixture copies) | Must go RED because |
|---|---|---|
| A1 | drop the `SYSLOG_IDENTIFIER='web-nic-guard'` conjunct from the SQL | unpinned rows from any identifier would satisfy — the conjunct is the scoping |
| A2 | reword `unpinned_url` in the .tf while the emitter's `[nic] unpinned_url:` line is unchanged | the needle is pinned to the emitter's source line — a one-sided reword silently disarms the alert |
| A3 | delete one `-target=` line from the apply allowlist | both resources must be in the per-merge apply or the alert never exists (logtail has no other parity guard) |
| A4 | drop `on_missing_data` / change it off `treat_as_zero` | a count query with no rows returns NO bucket — without it an open incident can never observe recovery |
| A5 | remove the suite's own `run:` step or `paths:` entry in `infra-validation.yml` | own-dispatch: a guard that does not run is vacuous — the registration is part of the deliverable |
| A6 | repoint `exploration_id` to another exploration | identity row (the `monitor_send_failed` battery's M20 precedent) |
| A7 (harness) | must-PASS: a `host_name`-FREE predicate (the refusal can fire on web-1 or web-2 — the #8706 host-conjunct trap cuts the other way here) | GREEN — both hosts' rows must satisfy the predicate; scoping to one host would blind half the fleet |

**Anchor.** Emitter-side needle read from `web-private-nic-guard.sh` itself; the live-probe positive control (betterstack-query.sh against the real table before merge) is the outside-of-repo verification — same shape as `monitor_send_failed`'s 2026-09-12 live probe.

## Implementation Phases

### Phase 1 — RED tests first (`cq-write-failing-tests-before`)

- 1.1 Add the F6 block to `web-git-data-probe.test.sh` (mirrors `inngest-consumer-probe.test.sh:525-666`): static `Exec*` dollar/export-free sweep, real-`ExecStart` launches under `SHELLOPTS=xtrace` and `BASH_ENV` (exit 78 + refusal text + secret in neither stream), pre-fix `ExecStart` leak control, stub-`doppler` dispatch row, untraced positive delivery, production-shaped identity key, no-key/stray-var/unset-var input cells, hostile-key + body-clause tables, four-way `_key_ok` parity, not-exported envdump + `export`/`URL`-preset mutants, hoist-reorder mutant, lookup-after-refusal line-order row. Update `run_seam`/`run_real`/`run_transport` env injection: `GIT_DATA_HEARTBEAT_URL_KEY=GIT_DATA_HEARTBEAT_URL` + `GIT_DATA_HEARTBEAT_URL=<synthetic>` (the bare-var form becomes the "no key → WARN arm" row). Raise `MIN_ASSERTS` in the same edit.
- 1.2 Add the F7 wiring rows to `cron-egress-enforce-probe.test.sh` beside `:176-179` (awk-extract the probe→`fi` block; assert emit precedes `poweroff -f` and the `rc` detail write exists).
- 1.3 Author `apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh` (new drift-guard suite, Guard 4 shape) — RED until Phase 3 lands the resources.
- 1.4 Run all three suites + `doppler-injection-bound.test.sh`: the git-data F6 rows fail (no refusal/lookup in the script), the F7 rows fail (no emit), the alert guard fails (no resources), and the scanner's `wrapper_stale` arm is proven by the W6 dry-run.

### Phase 2 — GREEN: the F6 residual fix

- 2.1 `web-git-data-probe.sh`: add the unconditional xtrace refusal at top (sibling shape, `exit 78`); replace `URL="${GIT_DATA_HEARTBEAT_URL:-}"` with the resolve block — `_key_ok` (byte-identical to the three siblings), `unset URL; URL=""; KEY_BAD=false; if _key_ok "${GIT_DATA_HEARTBEAT_URL_KEY:-}"; then URL="${!GIT_DATA_HEARTBEAT_URL_KEY:-}"; else KEY_BAD=true; fi` — placed after the refusal; `KEY_BAD`/`empty` falls into the existing WARN arm with a value-free key line; update the `CONFIG IS ENV` header comment to describe key-name resolution.
- 2.2 `web-git-data-probe.service`: `ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- /usr/local/bin/web-git-data-probe.sh'` (the exact sibling spelling — `inngest-consumer-probe.service:40`); rewrite the `EnvironmentFile` comment to describe script-side resolution after the refusal (sibling comment at `web-private-nic-guard.service:23-29` is the shape).
- 2.3 `doppler-injection-bound.test.sh`: delete the `web-git-data-probe.service` `WRAPPER_ACK_REASONS` entry; `WRAPPER_ACK_CARDINALITY` 1→0; re-scope the G1.x rows and mutation programs that named the unit as "the unfixed sibling" (`drop-wrapper-ack`, `ack-extra-name`, G1.6, G1.10, G1.10b, G1.10c) onto fixture-built arms (W1/W4/W5 matrix above) or delete the now-unreachable arm with an in-file note; update header scoping items 4-5, the WRAPPER/INNER_C comment blocks, and the F6-section comment at `:1353-1356`. Keep `ACK_REASONS`'s git-data entry (script-side `${!*_KEY}` keeps it in the population) and refresh its reason text to script-side wording. `ACK_CARDINALITY`, `MIN_POPULATION`, `MIN_DOPPLER_UNITS`, `MIN_WRAPPER_UNITS`, `MIN_INNER_C_UNITS` unchanged — verify by a green run + `CENSUS:` lines unchanged.
- 2.4 `cloud-init.yml`: restructure the probe block so the real exit code survives (`if /usr/local/bin/cron-egress-enforce-probe.sh; then :; else rc=$?; …fi`), write `rc=<n>` into `/run/soleur-stage-detail.d/egress_enforce_probe`, `soleur-boot-emit egress_enforce_probe fatal`, keep the FATAL stderr line, then `poweroff -f`.

### Phase 3 — GREEN: the F8 alert + wiring (7-step recipe at `betterstack-logs-alerts.tf:42-58`)

- 3.0 Live-probe the predicate FIRST via `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh` with a positive control (the recipe requires it; the SQL is not validated by `terraform validate`).
- 3.1 `betterstack-logs-alerts.tf`: `locals { web_nic_guard_unpinned_url_sql }` (`SYSLOG_IDENTIFIER='web-nic-guard'` AND `position(message,'unpinned_url') > 0`; NO `host_name` conjunct — both web hosts can refuse); `logtail_exploration` + `logtail_exploration_alert.web_nic_guard_unpinned_url` copying `monitor_send_failed`'s paging semantics verbatim incl. `treat_as_zero`, channels, `critical_alert`, the escalation ternary, `incident_cause` + `metadata.runbook` pointing at the new runbook.
- 3.2 `apply-web-platform-infra.yml`: two `-target=` lines beside the sibling alerts.
- 3.3 New runbook `knowledge-base/engineering/operations/runbooks/web-nic-guard-unpinned-url-alert.md` (readback SQL, decode table reusing `betterstack-log-query.md:1194-1207` content, remediation: fix the Doppler value or the pin) + a standing-alarms row in `betterstack-log-query.md`.
- 3.4 `betterstack-send-failed-alert-mutation.test.sh`: exploration `values`-literal count 17→18 and the "SEVENTEEN explorations" comment.
- 3.5 `infra-validation.yml`: `run: bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh` step + the new suite + runbook + .tf paths in `paths:` filters.

### Phase 4 — Stale-claim sweep + ADR + verification (before push)

- 4.1 Claim-sweep by noun, not by file: `grep -rn` for `git.data.*wrapper|wrapper.*git.data|ExecStart.*GIT_DATA|still.*resolve.*wrapper|not.*fixed.*9639` over the repo and `apps/web-platform/infra/` — update `web-probe-envwrite.sh:46-48` (also already stale re: inngest), `web-probe.tf:~128`, the scanner headers, and any other live-and-now-false prose site; mark historical ones as such (the F6 retro counted ~8 sites).
- 4.2 ADR-202 addendum status-line amendment (Phase 4 task above).
- 4.3 Repo-global ratchets: run `bash apps/web-platform/infra/run-registered-suites.sh` (or at minimum `doppler-injection-bound`, `web-git-data-probe`, `cron-egress-enforce-probe`, `fresh-boot-parity`, `journald-config`, `templatefile-bare-dollar-guard`, `cron-egress-ghcr-probe`), `bash apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`, `terraform fmt -check`/`validate` on the infra root, `grep-q-pipe-guard.test.sh` + `lint-trap-tempfile-ownership` + `guard-vacuity-floor` per the F6 retro's own pre-push list.
- 4.4 Merge-queue note: rebase on the post-#11159 test-red fixes when they land (acl-writer POSIX charset, credential-persist-home-guard, inngest pin) — this diff must not add new reds to `deploy-script-tests` (not a required check, but Infra Validation runs them on main).

## Files to Edit

- `apps/web-platform/infra/web-git-data-probe.sh` — xtrace refusal + post-refusal `${!GIT_DATA_HEARTBEAT_URL_KEY}` resolution (F6)
- `apps/web-platform/infra/web-git-data-probe.service` — ExecStart runs the script directly; comment rewrite (F6)
- `apps/web-platform/infra/web-git-data-probe.test.sh` — env-harness rewiring + F6 block + `MIN_ASSERTS` bump (Guard 2)
- `apps/web-platform/infra/doppler-injection-bound.test.sh` — drain `WRAPPER_ACK_REASONS`, pin 1→0, re-scope G1.x rows/mutation programs, comment updates (Guard 1)
- `apps/web-platform/infra/cloud-init.yml` — emit `soleur-boot-emit` + `rc` detail before the probe `poweroff -f` (F7)
- `apps/web-platform/infra/cron-egress-enforce-probe.test.sh` — emit-before-poweroff ordering rows (Guard 3)
- `apps/web-platform/infra/betterstack-logs-alerts.tf` — `web_nic_guard_unpinned_url` locals + exploration + alert (F8)
- `apps/web-platform/infra/web-probe-envwrite.sh` — stale wrapper-resolution comment (claim sweep)
- `apps/web-platform/infra/web-probe.tf` — same (claim sweep)
- `apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh` — exploration count 17→18
- `.github/workflows/apply-web-platform-infra.yml` — two `-target=` allowlist lines
- `.github/workflows/infra-validation.yml` — drift-guard step + `paths:` entries
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` — standing-alarms row
- `knowledge-base/engineering/architecture/decisions/ADR-202-*.md` — addendum status line

## Files to Create

- `apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh` — F8 drift-guard suite (Guard 4)
- `knowledge-base/engineering/operations/runbooks/web-nic-guard-unpinned-url-alert.md` — alert runbook

## Files NOT touched (constraint record)

- `apps/web-platform/infra/server.tf` — the `GIT_DATA_HEARTBEAT_URL_KEY=GIT_DATA_HEARTBEAT_URL` printf (`:1340`) already bakes the key name the script now reads; `triggers_replace` already hashes the three unit files — propagation needs no edit.
- `apps/web-platform/infra/web-probe-envwrite.sh` printf block — same env key set (`fresh-boot-parity.test.sh` §12 pins parity; no key added).
- `apps/web-platform/infra/web-git-data-probe.timer`, `apps/web-platform/infra/vector.toml`, `apps/web-platform/infra/git-data.tf` — cadence, journal routing and the 180 s heartbeat grace are unchanged.
- `cron-egress-enforce-probe.sh` — its refusal/emit_fail contract is unchanged; only its caller gains an emit.
- `apps/web-platform/infra/web-private-nic-guard.sh` — the `unpinned_url` emitter wording is pinned by Guard 4, not edited.
- No new doppler secret: `GIT_DATA_HEARTBEAT_URL` is already injected by `doppler run`; the change moves resolution, not the secret set.

## Open Code-Review Overlap

- **#11171** (`doppler-injection-bound.test.sh`, inner-c grammar scope-out): **acknowledge** — the scope-out tracks the INNER_C stage's grammar gaps (double-quoted bodies, fused flags, ANSI-C quoting, sentinel producers, target-script bodies, the escaped-arm row); this PR drains the *wrapper* ack stage, a different mechanism. Interaction handled: the INNER_C comments citing the git-data unit (`:363-373`) are updated in the same diff; the six grammar gaps remain open on #11171.
- **#9705** (dead-probe heartbeat for the inngest wrong-volume alert): **acknowledge** — different alert resource; no interaction with the `web_nic_guard_unpinned_url` alert.
- **#7098** (`run:` bodies `set -e` audit): **acknowledge** — the new step follows the existing `run: bash <suite>` single-line shape the siblings use; the audit's lint shape is unchanged.

## Infrastructure (IaC)

### Terraform changes

- `apps/web-platform/infra/betterstack-logs-alerts.tf`: +`logtail_exploration.web_nic_guard_unpinned_url`, +`logtail_exploration_alert.web_nic_guard_unpinned_url` (existing root; Better Stack `logtail` provider already in use).
- `.github/workflows/apply-web-platform-infra.yml`: two `-target=` lines (the per-merge apply is `-target`-scoped — new resources are invisible to it without them).
- No new providers, no new sensitive variables, no new hosts.

### Apply path

**Per-merge `-target` apply (no host replace).** Units propagate the same way #10637 did: `terraform_data.git_data_probe_install`'s `triggers_replace = sha256(join(",", [file(...sh), file(...service), file(...timer), token hash]))` (server.tf:1299-1305) changes on merge → the next apply re-runs the SSH `file` provisioners to web-1 + `daemon-reload` + re-enable timer. Fresh hosts (web-2 class) get the fixed files baked via `soleur-host-bootstrap.sh` + the server.tf file list; `cloud-init.yml` F7 lands on next web-host build. Expected downtime/blast radius: none — `Type=oneshot` timer-driven unit re-delivered between ticks; the alert is additive vendor-side config.

### Host fan-out

One SSH `remote-exec` consumer: `terraform_data.git_data_probe_install` → web-1 only (`hcloud_server.web["web-1"]`), same as its three siblings; classified per `plan-host-fanout.md` — this is the existing single-host delivery path, unchanged.

### Distinctness / drift safeguards

- `dev != prd`: the apply runs only on main (`on.push.paths`), prd-scoped (`--config prd`, `prd_terraform`); the alert binds `local.vector_prd_source_id` (pinned literal, drift-guarded).
- Deletion semantics documented in-file: a later removal of these resources is a silent no-op until the `[ack-destroy]` procedure runs — the runbook says so.
- State: encrypted R2 backend; no secret values in the new resources.

### Vendor-tier reality check

Better Stack free tier: the alert's channel is `email = true` team email + the `var.betterstack_paid_tier` escalation ternary — identical to every sibling (the free-tier `betteruptime_policy` rejection precedent is why the ternary exists). The alert count is tracked in ADR-218; this is the eighteenth `logtail_exploration` — same class, no new capability requirement.

## Observability

```yaml
liveness_signal:
  what:            "git_data_prd Better Stack heartbeat (web-git-data-probe.timer pings on every reachable run); the probe's [git-data-probe] WARN/SUPPRESS/SOLEUR_CREDENTIAL_REFUSED lines ship via SYSLOG_IDENTIFIER=web-git-data-probe → vector.toml Source 4 → source 2457081"
  cadence:         "60s timer; heartbeat grace 180s (fail-soft — sustained break only)"
  alert_target:    "Better Stack heartbeat absence + (new) soleur-web-nic-guard-unpinned-url-prd email page"
  configured_in:   "apps/web-platform/infra/git-data.tf (~:598) + apps/web-platform/infra/web-git-data-probe.timer + vector.toml Source 4"

error_reporting:
  destination:     "Sentry via soleur-boot-emit (F7: stage=egress_enforce_probe fatal) + the probe's own emit_fail envelope"
  fail_loud:       "boot-trail event before poweroff; '[FATAL] refusing to run under xtrace' rc 78 on stderr → journald → Better Stack"

failure_modes:
  - mode:          "traced unit launch prints GIT_DATA_HEARTBEAT_URL to journal (F6)"
    detection:     "doppler-injection-bound.test.sh wrapper stage (unacked FINDING) + web-git-data-probe.test.sh xtrace rows"
    alert_route:   "CI red on the PR; post-merge the script's own rc-78 refusal line in Better Stack"
  - mode:          "nic-guard refuses direct POST to unpinned ingest URL and withholds its beat (F8)"
    detection:     "logtail_exploration_alert.web_nic_guard_unpinned_url on SYSLOG_IDENTIFIER='web-nic-guard' + 'unpinned_url'"
    alert_route:   "team email (free tier) / uptime escalation policy (paid tier)"
  - mode:          "boot-time egress probe refused/failed → poweroff (F7)"
    detection:     "soleur-boot-emit stage=egress_enforce_probe fatal + /run/soleur-stage-detail.d/egress_enforce_probe rc=<n> discriminating 78 vs 1"
    alert_route:   "Sentry boot-trail + host-absence page"

logs:
  where:           "journald (SyslogIdentifier per unit) → vector.toml → Better Stack source 2457081; cloud-init log on-host (pre-poweroff only)"
  retention:       "Better Stack Logs retention; journald persistent per terraform_data.journald_persistent"

discoverability_test:
  command:         "grep -c \"unpinned_url\" apps/web-platform/infra/betterstack-logs-alerts.tf"
  expected_output: "2"
```

## Post-merge verification (no SSH; run by `soleur:postmerge`)

1. **Unit delivery:** `gh run list -R jikig-ai/soleur -w apply-web-platform-infra.yml -L 3`; `gh run view <run-id> --log | grep -E 'git_data_probe_install|Creation complete'` — the triggers_replace hash changed, so the apply log shows the resource replaced (per the runbook's own guidance at betterstack-log-query.md:~1182).
2. **Alert exists:** `terraform show` drift is covered by the untargeted drift cron; the live `logs_alert` arm of `reconcile-live-heartbeats.ts` (twice daily) reads the alert — confirm the exploration appears in the next reconcile output.
3. **Suite green on main:** Infra Validation run on the merge commit — `doppler-injection-bound`, `web-git-data-probe`, `cron-egress-enforce-probe`, the new alert guard all green (deploy-script-tests stay non-red as required by the constraint).
4. **F7 dry-run impossible pre-boot:** accepted — the emit is a cloud-init code path; its wiring rows are the coverage, and the sibling `hostscripts_incomplete` emit proves the mechanism live.

## Rollback

`git revert` the merge. The unit's `triggers_replace` hash flips back → next apply re-delivers the pre-fix `ExecStart` + script to web-1 (one timer tick of exposure window, identical to the F6 sibling's accepted rollback). The alert resources are `-target`-scoped: reverting drops the `-target=` lines AND the resources — destruction needs the documented `[ack-destroy]` procedure, else the alert lingers vendor-side (documented in `betterstack-logs-alerts.tf:63-64` + runbook). cloud-init reverts with the file; already-booted hosts are unaffected either way.

## Non-Goals

- No `_refusal_due` hourly limiter on the git-data script's `SOLEUR_CREDENTIAL_REFUSED` (sibling mechanism, not asked; behavior-preserving constraint).
- No `--canary-only` arm for git-data (zot-specific Source-4 positive control; git-data has no such need today).
- No change to the `git_data_prd` heartbeat's arming decision (#6982 deliberately left it unarmed).
- No inner-`bash -c` grammar widening — tracked on #11171.
- No host replace, no vendor dashboard changes, no new secrets.

## Test Scenarios

Derived from the ACs; every mutation-style row is in the Guard Contract matrices above (W1-W7, G1-G8, C1-C4, A1-A7). Pyramid layer `unit` (fixture-copy harness + stub launches) unless noted.

- Given the git-data unit's real `ExecStart` launched under `SHELLOPTS=xtrace`, when the script starts, then it exits 78 with the refusal line and the synthetic heartbeat URL appears in neither stream — `unit` (web-git-data-probe.test.sh F6 rows)
- Given the same launch without xtrace, when the script runs, then it resolves `GIT_DATA_HEARTBEAT_URL` through `GIT_DATA_HEARTBEAT_URL_KEY` and delivers it to curl's stdin config exactly once — `unit`
- Given the pre-fix `ExecStart` restored in a fixture, when launched under xtrace, then the secret IS visible — `unit` (negative control)
- Given `GIT_DATA_HEARTBEAT_URL_KEY=a[$(touch PLANT)]` or any upper-case-led hostile key (`A[0]`, `A=B`, `A.B`, `A/B`), when the script runs, then nothing executes, no heartbeat fires, and a value-free key line is logged — `unit`
- Given a stray bare `GIT_DATA_HEARTBEAT_URL` with no KEY set, when the script runs, then nothing resolves (no bare-var fallback) → WARN arm, exit 0 — `unit`
- Given `_key_ok` drift in any of the four copies, when the parity row runs, then it fails — `unit`
- Given the wrapper ack entry still present after the unit fix, when the scanner runs, then `ACK_FAIL wrapper_stale` — `unit`
- Given a `bash -c` probe-block fixture missing the emit or with emit after `poweroff -f`, when the F7 rows run, then RED — `unit`
- Given a fixture cloud-init where the probe exits 78, when the block runs, then `soleur-boot-emit egress_enforce_probe fatal` fires with `rc=78` in the stage detail — `unit` (harness: stub probe + capture)
- Given the .tf lacking the `SYSLOG_IDENTIFIER` conjunct or the `unpinned_url` needle, when the alert guard runs, then RED — `unit`
- Given the alert's `-target=` lines missing from the apply allowlist, when the guard runs, then RED — `unit`
- Given a real `unpinned_url` row exists in the prd source, when the predicate is live-probed via `betterstack-query.sh` pre-merge, then it returns ≥1 row (positive control per the recipe) — `integration` (operator-visible at work time; no SSH)
- Given the merge lands, when the next apply runs, then `terraform_data.git_data_probe_install` shows replaced and web-1 runs the fixed unit on the next 60s tick — `integration` (post-merge check 1)

## Acceptance Criteria

- [ ] **AC1 (F6):** `web-git-data-probe.service`'s `ExecStart` (and every `Exec*` directive) expands and exports nothing — `ExecStart=/bin/bash -c 'doppler run --project soleur --config prd -- /usr/local/bin/web-git-data-probe.sh'`; grep over all `*.service` Exec directives shows zero `${!` expansions repo-wide.
- [ ] **AC2 (F6):** `web-git-data-probe.sh` refuses under xtrace (exit 78) BEFORE resolving the URL; it resolves `GIT_DATA_HEARTBEAT_URL` through `GIT_DATA_HEARTBEAT_URL_KEY` (charset-validated `_key_ok`, `${!KEY:-}`, unexported, no bare-var fallback); an unset/invalid key degrades to the existing WARN arm with a value-free key line and fail-soft exit 0.
- [ ] **AC3 (F6):** `web-git-data-probe.test.sh` carries the F6 block (launch, control, hostile-key + body-clause tables, four-way `_key_ok` parity, envdump/export/preset/hoist mutants, order row) and is green; `MIN_ASSERTS` raised in the same edit.
- [ ] **AC4 (F6):** `doppler-injection-bound.test.sh` has `WRAPPER_ACK_REASONS = {}` and `WRAPPER_ACK_CARDINALITY = 0`; the suite is green with `CENSUS:` lines unchanged from main (doppler_run_units, bound_required_population); the mutation rows formerly anchored on the unfixed sibling are re-scoped or removed with notes.
- [ ] **AC5 (F7):** in `cloud-init.yml`, a `soleur-boot-emit egress_enforce_probe fatal` precedes the probe's `poweroff -f`, and the stage detail file carries the probe's real exit code (78 vs 1 discriminated); `cron-egress-enforce-probe.test.sh` pins the ordering.
- [ ] **AC6 (F8):** `betterstack-logs-alerts.tf` contains `logtail_exploration` + `logtail_exploration_alert.web_nic_guard_unpinned_url` matching `SYSLOG_IDENTIFIER='web-nic-guard'` + `unpinned_url`, with `monitor_send_failed`'s paging semantics incl. `on_missing_data = "treat_as_zero"`, and the exploration-count pin reads 18.
- [ ] **AC7 (F8):** both new resources appear in `apply-web-platform-infra.yml`'s MAIN `-target=` allowlist; the new drift-guard suite + its `run:` step + `paths:` entries exist; the runbook + standing-alarms row exist.
- [ ] **AC8:** ADR-202's addendum reflects all four units fixed and the wrapper-ack dict drained; the claim-sweep (`git.data.*wrapper`, `still.*wrapper`, `not.*fixed.*9639`, `ExecStart.*GIT_DATA`) finds no live-and-now-false prose in `apps/web-platform/infra/` or the KB.
- [ ] **AC9:** `bash apps/web-platform/infra/doppler-injection-bound.test.sh`, `bash apps/web-platform/infra/web-git-data-probe.test.sh`, `bash apps/web-platform/infra/cron-egress-enforce-probe.test.sh`, `bash apps/web-platform/test/infra/betterstack-send-failed-alert-mutation.test.sh`, `bash apps/web-platform/test/infra/web-nic-guard-unpinned-url-alert.test.sh`, and `run-registered-suites.sh` (or the stated subset) are green; `terraform fmt -check`/`validate` green; no new deploy-script-tests reds vs main.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — worst case is a fail-soft probe whose heartbeat URL fails to resolve, degrading to the existing WARN arm (the git-data beat lapses, which reads as a git-data reachability blip, not a product defect); or a wrongly-firing alert email.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the git_data_prd heartbeat URL (an internal Better Stack beat-path credential — not user data); this diff *reduces* that exposure by moving resolution inside the refusal's reach.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** no user-facing surface, no regulated data, no new credential — the change hardens an internal ops credential and adds internal observability; a `single-user incident` claim would have to name a user-visible artifact and none exists.

*Scope-out override:* `threshold: none, reason: internal ops-probe credential hygiene + observability on host units — no user-facing surface or user data touched` (the diff touches `apps/web-platform/infra/**`, a sensitive path).

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Assessment:** Mechanism was ruled by the CTO at the F6 arm (2026-10-20, ADR-202 addendum + decision-challenges in the archived spec dir); this plan applies those rulings to the last unit and two sibling findings. No product, marketing, legal, finance, sales, support or operations implication: host-script/unit/test/terraform + runbook changes with no user-facing surface, no new vendor and no spend (the alert rides the existing free-tier email channel). The Product/UX mechanical override did not fire — no file in Files to Edit/Create matches the UI-surface glob set.

## Encryption Posture

Detection fires (`.tf`, `cloud-init.yml` in the file lists) but the plan introduces **no new persistent store and no new cross-component connection** — the alert is vendor-side config on an existing connection; the probe's ping path is unchanged. Posture of the touched connections, declared for completeness:

```yaml
at_rest: []
in_transit:
  - connection: "web host -> Better Stack Logs ingest (vector sink + the nic-guard's pinned BETTERSTACK_INGEST_URL)"
    enforced_at: "apps/web-platform/infra/vector.toml; web-private-nic-guard.sh (pinned literal, unpinned_url refusal)"
    tls: "https, TLS 1.2+"
    cert_verification: on
    does_not_defend: "a leaked BETTERSTACK_LOGS_TOKEN writing forged rows; journal-side PII beyond Vector's scrub"
    disclosed_as: "not-publicly-claimed"
  - connection: "terraform apply -> Better Stack provider API (logtail resources)"
    enforced_at: "existing betterstack provider config in the infra root"
    tls: "https, TLS 1.2+"
    cert_verification: on
    does_not_defend: "a leaked Better Stack API token managing alerts"
    disclosed_as: "not-publicly-claimed"
  - connection: "web host -> Doppler API (doppler run secret injection, unchanged)"
    enforced_at: "existing doppler-run units; web_probes read-scoped token (server.tf)"
    tls: "https, TLS 1.2+"
    cert_verification: on
    does_not_defend: "the read-scoped token's own leak surface (pre-existing, narrowed by this diff on the journal side)"
    disclosed_as: "not-publicly-claimed"
```

No ledger row required: `logtail_exploration*` is a non-store resource type (alert config, not a data store); no `store_classes` instance is added.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "move the indirect lookup into the script after the refusal, matching the nic-guard/zot pattern (the script resolves the URL via the key NAME itself)" [issue #9639 F6 + brief] | Phases 1.1, 2.1-2.2 / AC1-AC3 / Files: web-git-data-probe.{sh,service,test.sh} | mapped |
| 2 | "Check web-zot-consumer-probe.service and any other sibling probe units for the same shape" [brief] | Research Insights grep evidence (zero `${!` in other `*.service` Exec directives) + AC1's repo-wide zero-expansion assertion | mapped |
| 3 | "extend [`doppler-injection-bound.test.sh`] coverage to the git-data unit the same way it covers the fixed siblings" [brief] | Phase 2.3 / AC4 / Guard 1 | mapped |
| 4 | "emit a boot-trail event before that poweroff so a refused/failed probe is visible without the cloud-init log" [issue #9639 F7 + brief] | Phases 1.2, 2.4 / AC5 / Guard 3 | mapped |
| 5 | "add one copying the paging semantics of the luks_monitor_host_timer_dark / monitor_send_failed precedents incl. treat_as_zero" [issue #9639 F8 + brief] | Phase 3 / AC6-AC7 / Guard 4 | mapped |
| 6 | "the fixed-nic-guard PR #10637 precedent shows how units propagate (verify and cite it in the plan)" [brief] | IaC > Apply path + Research Reconciliation row 6 | mapped |
| 7 | "your diff must not add new reds there" (deploy-script-tests on main) [brief constraints] | Phase 4.3-4.4 / AC9 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| F6 unit+script+test edits | "move the indirect lookup into the script after the refusal" | asked |
| doppler-injection-bound.test.sh ack drain + row re-scope | "extend its coverage to the git-data unit the same way it covers the fixed siblings" | asked |
| cloud-init emit + ordering rows | "emit a boot-trail event before that poweroff" | asked |
| F8 alert + exploration + targets + drift suite + runbook + count bump | "add a logtail_exploration_alert on SYSLOG_IDENTIFIER='web-nic-guard' rows containing `unpinned_url`" | asked |
| ADR-202 addendum amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable`; the addendum's "two units not yet fixed" sentence becomes false on merge |
| Stale-claim sweep (envwrite/web-probe.tf/scanner headers) | — | inferred — justification: the F6 retro's measured lesson (~8 prose sites) + learning 2026-09-22 sweep-by-claim; leaving them re-creates the recorded lie class |
| Four-way `_key_ok` parity row + body-clause table | — | inferred — justification: learning 2026-10-25 (third-copy parity); the fourth copy's comment-asserted identity fails without it |
| `rc` detail file for the boot-emit | — | inferred — justification: F7's stated purpose is visibility of "a refused/failed probe"; without `rc`, the emit names a stage but cannot discriminate refused(78) from failed(1) |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform`, `.github`, `knowledge-base`
- Planned files: 14 edited + 2 created | Estimated changed lines: ~600-750 (F6 block port ~140, scanner re-scope ~120, tf+workflows+guard suite ~250, script/unit/cloud-init ~60, docs/ADR ~30)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — one issue, one coherent fix family; under all split thresholds

## Sharp Edges

- **The unit fix and the ack drain are ONE atomic edit.** Split them and either side is red: fix without ack-removal trips `wrapper_stale` (rc 5); ack-removal without the fix trips the unacked `FINDING` (rc 2).
- **`if ! probe; then` destroys the exit code.** The F7 detail needs the real `rc`, so the block must restructure to `if probe; then :; else rc=$?` — an `else` after a non-negated `if` keeps `set -e` semantics identical.
- **The env-file key set does NOT change** — `GIT_DATA_HEARTBEAT_URL_KEY=GIT_DATA_HEARTBEAT_URL` is already baked by both writers (server.tf + envwrite); `fresh-boot-parity.test.sh` §12 must stay green without edits.
- **Mutation rows anchored on "the unfixed sibling" die with this diff** — `drop-wrapper-ack`, `ack-extra-name`, G1.6/G1.10/G1.10b/G1.10c must be re-scoped in the same edit or the suite self-aborts on missing anchors (`SystemExit`), which reads as suite-broken not suite-red.
- **`expected_output "2"` for the discoverability probe** counts `unpinned_url` occurrences in the .tf (locals SQL + alert comment/name) — if the implementer writes the word more places, bump the literal; it is a presence signal, not a count invariant.
- **Two merge-queue PRs ahead carry test-red fixes** — rebase before queue join; the diff must not add new deploy-script-tests reds on main (constraint, restated).
- **A plan whose `## User-Brand Impact` section is empty or omits the threshold fails deepen-plan Phase 4.6** — filled above with the sensitive-path scope-out bullet.
- **Apply the F6 retro verbatim:** sweep stale prose by CLAIM (grep the noun), not by files touched; the parity/body-clause/hostile-fixture rows are not optional "lean port" cuts.
- **Merge-queue ruleset** — `gh pr merge` is not the path; the PR joins the queue with `Ref #9639`/`Closes #9639` semantics per the ship skill, and deploy-script-tests are not required checks but must not regress on main.
- **The alert needs its live positive control BEFORE authoring is final** — `betterstack-query.sh` probe of the predicate against the prd table (recipe step 1); a `dt` vs `time` column choice is settled by what the live query returns (siblings use both).

## References

- Issue: #9639 (this work closes it). Tracker #9217. Findings PR #9632.
- Shipped precedents: PR #10637 (F6 nic-guard/zot arm, MERGED 2026-10-20), #10363 (inngest arm), F5 PR (root sources deploy-owned file).
- Plans: `knowledge-base/project/plans/archive/20261020-063243-2026-10-20-fix-nic-guard-url-lookup-after-xtrace-refusal-plan.md` (F6 arm — script contract, test shape, Guard Contract precedent).
- ADRs: ADR-202 (refusal reach incl. unit wrapper — amended in-plan), ADR-218 (logtail alert class/free-tier), ADR-280 (credentials reach curl on stdin config), ADR-154 (bridge vs bridge-less apply stages), ADR-147.
- Learnings: `2026-10-25-third-copy-of-a-security-guard-needs-a-parity-row.md`, `security-issues/2026-10-19-a-hostile-fixture-must-put-the-payload-in-the-value-the-fix-reads.md`, `test-failures/2026-10-20-a-privacy-narrowing-of-my-env-dump-by-name-removed-the-property-the-row-tested.md`, `2026-09-22-my-sweep-was-keyed-on-a-literal-and-the-claim-had-another-spelling.md`, `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md`.
- Runbook: `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` (standing alarms + unpinned_url decode at ~:1194-1207); `apply-web-platform-infra-job-rationale.md`, `monitor-send-failed-alert.md`.
