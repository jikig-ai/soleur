---
title: Inngest public sdk_url — merge-before-replace safety work (#12742 item 1)
date: 2026-11-17
slug: feat-inngest-sdk-url-sync-evidence-strict-preflight
branch: feat-one-shot-12742-public-sdk-url-poll
issue: 12742
pr: 12876
type: feat
lane: solo
status: planned
related: [10538, 10479, 12737, 12726, 12742, 9139, 7228]
---

# Inngest public sdk_url — merge-before-replace safety work (#12742 item 1)

## Overview

PR #12737 (merged 2026-11-16) changed the declared Inngest `--sdk-url` from
`http://10.0.1.10:3000/api/inngest` (private plaintext) to
`https://app.soleur.ai/api/inngest` (public-CA TLS to the Cloudflare edge, `strict` TLS to origin) —
remedy (c) of #10538. The value reaches the live dedicated host only when the owner runs
`inngest-host-replace`. Two safety gaps must be closed in this repo **before** that production act:

1. **No stale-registry evidence.** The registry-empty alert added by #12737 fires only on a
   zero/unreadable `registry_fns`. The Inngest registry persists in Postgres across a replace, so a
   server whose *latest* sync fails keeps a stale non-zero count and the alert stays silent. The
   `SOLEUR_INNGEST_SERVER_PROBE` event must emit a field proving the server's last sync succeeded.
2. **A typo-guard gate, not a live-mode gate.** Both dispatches that boot `hcloud_server.inngest`
   (`inngest_host_replace`, `inngest_host`) gate on a typed confirm token that says nothing about the
   live Cloudflare TLS mode. The gate must be replaced by a fail-closed preflight that refuses unless
   the **last** Cloudflare config-settings rule matching `app.soleur.ai` has `ssl = strict`.

This plan covers **#12742 item 1 only**, plus its mandated F4(ii) hardening of free-text probe
fields. Items 2–9 (the owner's replace, hop-1 measurement, private-poll measurement, ledger row 6,
C4 diagram, published wording, owner late record, stale comment) are out of scope; they are
production acts or separate PRs.

## Premise Validation (Phase 0.6 results)

- `#12742` OPEN; item 1 verbatim: *"Add a field to `SOLEUR_INNGEST_SERVER_PROBE` showing that the
  server's last successful sync is recent. This must merge before the replace. The registry-empty
  alert added in #12737 cannot see a stale non-zero registry (CTO ruling 2026-11-13)."*
- `#10538` OPEN (issue body says "closed by #12737" but a later comment corrects it — do NOT restate
  it as closed). `#10479` OPEN. `#12726` OPEN. `#12737` MERGED 2026-11-16. `#12876` OPEN draft = this
  branch (collision precheck: self, not a foreign duplicate).
- The Cloudflare `strict` precondition is **procedural**, not yet a live check: `confirm` tokens are
  typo-guards (`knowledge-base/engineering/operations/runbooks/inngest-server.md` §confirm inputs:
  "The `confirm` input is a typo-guard, **not** the authorization").
- `plugins/soleur/scripts/cloudflare-readonly.sh` is the sanctioned read path: subcommand
  `config-entrypoint` → `GET /zones/{zone}/rulesets/phases/http_config_settings/entrypoint`, bound to
  `CF_API_TOKEN_RULESETS`, refuses wrong source/env, emits
  `cloudflare-readonly: config-entrypoint ok` + a JSON projection carrying each rule's `ref`,
  `enabled`, `ssl`, and an `app.soleur.ai`-mention flag. It must be invoked as
  `doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh <sub>`
  (never wrapped in a shell under `doppler run`; the script may exec that exact argv).
- Byte budget: `.github/workflows/apply-web-platform-infra.yml` is **489,995 B — 5 B under** the
  490,000 B gate in `plugins/soleur/test/workflow-file-size.test.ts`. Every edit to that file must be
  net-negative or net-zero bytes. Removing the two typed-confirm steps (~330 B each) funds the two
  replacement preflight steps; keep step comments to one line, relocate prose to the job-rationale
  runbook (the gate's own error text prescribes that relocation).

## Research Insights

### Where things live (exact anchors)

- **Probe emitter:** `apps/web-platform/infra/inngest-bootstrap.sh`
  - `readonly FUNCTIONS_GQL_QUERY='query RegistryProbe { functions { ... } }'` at ~L650 — a second
    `readonly` GQL constant must be added beside it (drift-pinned; the pin greps
    `^readonly FUNCTIONS_GQL_QUERY=`).
  - `image_ref` bound ~L679 from `/etc/default/soleur-inngest-image` (raw free text).
  - `cli_version` bound ~L704 from `inngest version | head -1` (raw free text).
  - `probe_schema=9` at ~L740.
  - `registry_fns` gather block ~L955–995: `http_code != 200` → `__UNREADABLE__`; `jq` absent →
    `__UNREADABLE__`; else `curl` the GQL → `jq` count; non-numeric → `__UNREADABLE__`. This is the
    template for the new gather.
  - Sanitize precedent in-file: `tr -c 'A-Za-z0-9' '_' | cut -c1-48` (`probe_scan_err`, ~L978).
  - Emit line: L1335 `logger -t "$LOG_TAG" "SOLEUR_INNGEST_SERVER_PROBE ... registry_fns=$registry_fns
    data_luks=$data_luks"`.
  - Vector-down phone-home twin: L1366 — identical field string passed as the `detail` arg. Any emit
    change must be mirrored there (the registry-empty guard pins the two lines' `registry_fns=` count
    to 2 via BOOT mutation row 6).
- **Registry-empty alert:** `apps/web-platform/infra/betterstack-logs-alerts.tf` —
  `logtail_exploration.inngest_registry_empty` + `logtail_exploration_alert.inngest_registry_empty`;
  incident_cause already admits: *"This alert does NOT detect a stale non-zero registry (#12742 adds
  that field)."*
- **Drift guard:** `apps/web-platform/test/infra/inngest-registry-empty-alert.test.sh` — derives
  needles from source, renders EMIT/PH lines (`_render`, L251), evaluates them (`_fires`, L261),
  runs `mutate_red`/`mutate_green`/`mutate_self_red` matrix; assertion floors `PRESENCE_ROWS=49`,
  `MUT_ROWS=28` (L674-675).
- **Schema consumers:**
  - `tests/scripts/lib/inngest-host-dark-gate.sh` L128 `_IHDG_EXPECTED_SCHEMA="9"`, verdict
    `stale_schema` when the host's newest `probe_schema=` row ≠ expected (G4, L541-563). The lib is
    sourced by THREE callers, so a bump fans out:
    (a) `scripts/cutover-inngest.sh` L1104-1105 — owner-run registry/execute gate (stale_schema
        refusal on the pre-replace host is designed-for);
    (b) `scheduled-inngest-health.yml` ~L1294-1320 — the #8080 darkness witness calls
        `inngest_execute_registry_gate` in REPORT-ONLY mode; the verdict token is regex-validated
        and "counted by the streak rather than crashing the arm". A `stale_schema` token counted as a
        refusal streak during the merge→replace window could misread a HEALTHY-emitting host as a
        streak event — the witness must map `stale_schema` to alive/not-dark (or the streak
        classification must be audited and pinned) as part of the bump task;
    (c) `infra-validation.yml` L205 — required-path presence pin only (no semantics).
  - `scripts/followthroughs/inngest-luks-field-8525.sh` greps `probe_schema=9` rows (`newest9`,
    ~L104-110); a schema-10 host would read TRANSIENT — must accept `9|10` (or `>=9`).
  - `apps/web-platform/infra/inngest.test.sh` ~L1370: `PROBE_7695_FIELDS` list +
    `assert "probe_schema=9( |$)"` + never-zero semantics (`registry_fns` deliberately excluded —
    `0` is its meaningful reading; the new fields take `n/a`/`__UNREADABLE__` sentinels, never `0`).
  - `scripts/inngest-probe-heartbeat-feeder.test.sh` fixture rows hardcode `probe_schema=9`
    (fixtures, not pins — update for realism, not required for correctness).
  - `scripts/inngest-host-state.sh` parses `key=value` fields generically (L332 prints
    `probe_schema`) — appended fields need no parser change.
- **Gate call sites:** `.github/workflows/apply-web-platform-infra.yml`
  - `inngest_host` job ~L1719-1724; `inngest_host_replace` job ~L1902-1907. Both: step index 1,
    name `Validate dispatch inputs (PUBLIC-SDK-URL[-BIRTH] confirm token, #12742)`, env
    `CONFIRM_RAW: ${{ inputs.confirm }}`, run `bash tests/scripts/lib/inngest-public-sdk-url-confirm.sh
    <TOKEN>` — before `hashicorp/setup-terraform` and `Load infra credentials (tiered)`.
  - `confirm:` input declared L51 and consumed by ~10 OTHER targets (L2747, 3157, 3764, 4509, 4721,
    5165, 5720, 6182, 6755) — **the input stays**; only the two inngest jobs stop consuming it.
  - Precedent for the replacement: `Pre-apply entrypoint gate` ~L928-955 — reads
    `CF_API_TOKEN_RULESETS`/`CF_ZONE_ID` from Doppler with `|| true`, `::add-mask::`, calls a
    `tests/scripts/lib/*-gate.sh` that is default-deny (ADR-136).
- **B10 pins to replace:** `plugins/soleur/test/terraform-target-parity.test.ts` ~L5186-5305 —
  four tests: per-job gate-step shape, token distinctness, live-recipe sweep (≥6 recipes), script
  refusal table. Also the G2f registration pin comment at L113 (count `349 -> 353`) may drift.
- **CODEOWNERS:** `.github/CODEOWNERS` L48 pins
  `/tests/scripts/lib/inngest-public-sdk-url-confirm.sh @deruelle` — repoint to the new script.
- **Known recipe carriers** (B10 sweep finds all; grep must confirm the final set):
  `scripts/cutover-inngest.sh` (3 recovery lines),
  `scripts/followthroughs/inngest-private-nic-8539.sh`,
  `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md`,
  `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`,
  the workflow's own `hcloud_server.inngest` error line, plus `inngest-server.md` §confirm sections.
- **`scripts/test-all.sh`** L7009 comment references the G2f pin — update if it names the removed
  tests.

### Chosen mechanisms (see decision-challenges.md for ruling status)

- **Sync evidence (item 1):** second host-local GQL query `query SdkSyncProbe { apps { url error } }`
  against the same `http://127.0.0.1:8288/v0/gql`, run inside the same arm as `registry_fns`.
  Emit two appended fields (after `data_luks`, mirrored in the phone-home detail):
  - `sdk_sync=` — enum `ok|error|no_apps|n/a|__UNREADABLE__`: `ok` only when every returned app row
    has an empty/null `error`; `error` when any app row carries a non-empty `error` (that field is
    refreshed by the server's own pollSDKs loop each cycle, so `ok` proves the **last** sync attempt
    succeeded — recent by construction within one poll interval plus the probe's own cadence);
    `no_apps` when the array is empty (pre-registration / diagnostic boot); `n/a` on the web arm;
    `__UNREADABLE__` on GQL failure, non-200, or missing jq.
  - `sdk_app_url=` — sanitized joined app URLs (charset `[A-Za-z0-9_:.@/+-]`, `,` separators,
    `__UNREADABLE__`/`n/a`/`none` sentinels), so a stale `http://10.0.1.10:3000` row or a missing
    `https://app.soleur.ai` registration is legible in the same row. This doubles as the read-only
    evidence item 4 will need ("the stored `url` of each app row (host-local GQL, as the probe
    already does)").
  - `probe_schema` bumps `9` → `10`; `_IHDG_EXPECTED_SCHEMA` bumps to `10`. The bump cannot block
    the owner's replace (the `inngest_host_replace` job never routes through the dark gate — it is
    terraform `-target` apply; the gate is only sourced by `cutover-inngest.sh`, the health witness,
    and its own tests). It DOES change the witness's reported token to `stale_schema` for the whole
    merge→replace window: a task must audit the witness streak's classification of that token and,
    if it counts toward a page-bearing streak, add the explicit `stale_schema`→alive/not-dark mapping
    (a host emitting old-schema rows is emitting — not dark). See decision-challenges row 5.
  - The registry-empty **alert SQL is unchanged**: a stale non-zero registry with failing sync is
    surfaced by `sdk_sync=error`/`sdk_app_url=` in the same row for the responder, and a future alert
    on `sdk_sync=` is a separate decision (extending a live paging surface now, pre-replace, has
    worse risk/return — see Alternatives).
- **F4(ii) masking fix (ruling: sanitize, not countMatches):** sanitize `image_ref` and
  `cli_version` at their bind sites with the file's existing `tr` shape extended to the permitted
  charset `[A-Za-z0-9_:.@/+-]` → `_`. Chosen over the `countMatches(msg, ' registry_fns=') != 1`
  SQL alternative because a space-bearing free-text value corrupts field tokenization for **every**
  `key=value` consumer of the row (`inngest-host-state.sh`, the heartbeat classifier, this alert,
  any grep) — fixing the data at the source protects all consumers; the SQL fix protects only one.
  The guard gains: (a) a presence row pinning the sanitize applications on both bind sites, (b) a
  `mutate_red` BOOT row removing a sanitize call → red, (c) a rendered-line row that substitutes a
  hostile ` registry_fns=5 `-bearing value through the sanitize pipeline extracted from BOOT and
  asserts the alert still fires on `registry_fns=0`.
- **Preflight:** new `tests/scripts/lib/inngest-public-sdk-url-preflight.sh` — fail-closed gate
  taking no positional args (or a `--from-file` test seam); in CI it execs
  `doppler run -p soleur -c prd_terraform -- "$REPO/plugins/soleur/scripts/cloudflare-readonly.sh
  config-entrypoint"`, captures stdout+rc, and passes only when: output begins
  `cloudflare-readonly: config-entrypoint ok`, the JSON projection parses, ≥1 enabled rule has
  `mentions_app_host: true`, and the **last** such rule has `ssl == "strict"`. The projection shape
  is pinned (cloudflare-readonly.sh L426): `.rules[]` in order, each carrying `ref`, `enabled`
  (already normalized to `enabled != false`), `ssl` (from `.action_parameters.ssl`), and the
  booleans `mentions_app_host` / `mentions_lb_staging_host`; top-level `rule_count`,
  `enabled_ssl_rules`, `last_updated`. Refusals (distinct `::error::` per arm, never echoing tokens
  or raw bodies): missing `DOPPLER_TOKEN`, doppler/wrapper rc≠0, `unverified` output, malformed
  JSON, no matching enabled rule, last match `ssl != strict`, ambiguous shape. Note the wrapper's
  own verdict is a dated snapshot (rule_count=3 / ref-pinned, 2026-11-13) — the preflight judges the
  per-rule projection, not the baked verdict, so added rules re-key the answer while any wrapper
  non-`ok` line still refuses. `--from-file <path>` reads a captured projection instead of calling
  doppler — the parity test's behavior table runs that seam (live path is exercised by the
  dispatch itself, never by CI tests).
- **Workflow placement:** replace each `Validate dispatch inputs` step with a one-comment +
  four-line step placed **after** `Load infra credentials (tiered)` and **before** any terraform
  step: env `DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}`, run
  `bash tests/scripts/lib/inngest-public-sdk-url-preflight.sh`. The old gate's
  "before any credential" property is vacated by design — a live-mode check needs the credential;
  the protected property becomes "after credentials, before any terraform write, unconditional,
  fail-closed" (mirrors the ADR-136 entrypoint gate's shape).
- **Token/recipe removal:** delete `tests/scripts/lib/inngest-public-sdk-url-confirm.sh`; remove
  `PUBLIC-SDK-URL`/`PUBLIC-SDK-URL-BIRTH` from every carrier; rewrite recipes to show the dispatch
  without a confirm token and note the automatic preflight; update CODEOWNERS L48; update
  `inngest-server.md` §confirm sections and `apply-web-platform-infra-job-rationale.md` §inngest_host
  / §inngest_host_replace.

## Files to Edit / Create

**Create**
- `tests/scripts/lib/inngest-public-sdk-url-preflight.sh` — the fail-closed gate (replaces the
  confirm script's role; behavior-table testable via `--from-file`).

**Edit — probe**
- `apps/web-platform/infra/inngest-bootstrap.sh` — new `readonly` GQL const; sanitize `image_ref`/
  `cli_version` binds; `probe_schema=10`; new `sdk_sync`/`sdk_app_url` gather block beside
  `registry_fns` (same unconditional-emit contract: bound `n/a` above the dedicated arm,
  `__UNREADABLE__` on every failure arm, never `0`, never shipped GQL error text); append both
  fields to the emit line (L1335) and the phone-home detail (L1366). Item-9 note: this file is
  changing "for a real reason", so the stale `co-located web-platform` carrier comment named by
  #12742 item 9 SHOULD be refreshed in the same diff (zero marginal cost; see
  decision-challenges.md row on scope tension).

**Edit — gate**
- `.github/workflows/apply-web-platform-infra.yml` — swap the two confirm steps for the two
  preflight steps after `Load infra credentials`; remove the `hcloud_server.inngest`
  `PUBLIC-SDK-URL` error line; keep `confirm:` input and all other consumers untouched; keep net
  bytes ≤ 0 vs 490,000 cap (verify `wc -c` before/after; relocate prose to the rationale runbook).

**Edit — tests**
- `plugins/soleur/test/terraform-target-parity.test.ts` — replace the four B10 tests: (1) per-job
  preflight step shape (unconditional, after `Load infra credentials`, before first terraform step,
  `DOPPLER_TOKEN` env, runs the script, no `CONFIRM_RAW`); (2) neither job consumes
  `inputs.confirm`; (3) inverted recipe sweep — zero live recipes for the two targets may carry
  `confirm=PUBLIC-SDK-URL*` (keep the ≥6-recipe non-vacuity floor); (4) script behavior table over
  `--from-file` fixtures: strict-last passes; flexible-last, disabled-only, no-match, unverified,
  malformed, missing-file all refuse rc=1 with the right `::error::` arm.
- `apps/web-platform/test/infra/inngest-registry-empty-alert.test.sh` — F4(ii) rows above;
  `PRESENCE_ROWS`/`MUT_ROWS` floors adjusted; emit-line renders pick up the new fields.
- `apps/web-platform/infra/inngest.test.sh` — `PROBE_7695_FIELDS` += `sdk_sync sdk_app_url`;
  `probe_schema=9` assert → `10`; per-arm fixture expectations for the new fields (dedicated serving
  arm `ok` + URL; web arm `n/a`; GQL-fail arm `__UNREADABLE__`); never-zero list unchanged (the new
  fields' sentinels are non-numeric, so they cannot render `0`; add them to the never-zero list only
  if a `0` could meaningfully degrade — they join it: `sdk_sync`, `sdk_app_url` have no `0`
  meaning).
- `tests/scripts/lib/inngest-host-dark-gate.sh` — `_IHDG_EXPECTED_SCHEMA="10"`.
- `scripts/followthroughs/inngest-luks-field-8525.sh` — accept `probe_schema` `9|10` (`>=9`).
- `scripts/inngest-probe-heartbeat-feeder.test.sh` — fixtures to `probe_schema=10` where they model
  the current emitter.
- Any other `probe_schema=9` literal pins found by repo grep at implementation time.

**Edit — recipe carriers / docs**
- `scripts/cutover-inngest.sh`, `scripts/followthroughs/inngest-private-nic-8539.sh`,
  `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md`,
  `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`,
  `knowledge-base/engineering/operations/runbooks/inngest-server.md`,
  `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`,
  `.github/CODEOWNERS`, `scripts/test-all.sh` (comment sweep).

**Delete**
- `tests/scripts/lib/inngest-public-sdk-url-confirm.sh`

## Implementation Phases

### Phase 1 — Probe sync evidence + F4(ii) + schema 10

1. `inngest-bootstrap.sh`: add `readonly SDK_SYNC_GQL_QUERY='query SdkSyncProbe { apps { url error } }'`
   beside `FUNCTIONS_GQL_QUERY`; bind `sdk_sync=n/a` / `sdk_app_url=n/a` with the other top-level
   binds; add the gather block inside the dedicated arm beside `registry_fns` mirroring its
   failure-arm shape; sanitize `image_ref`/`cli_version` at bind; `probe_schema=10`; append
   `sdk_sync=$sdk_sync sdk_app_url=$sdk_app_url` after `data_luks` on **both** emit and phone-home
   lines; refresh the item-9 carrier comment.
2. `inngest-host-dark-gate.sh`: `_IHDG_EXPECTED_SCHEMA="10"`.
3. `inngest-luks-field-8525.sh`: accept schema `9|10`.
4. `inngest.test.sh`: field list, schema assert, per-arm fixtures incl. a stubbed `apps` GQL
   response; prove `__UNREADABLE__`/`n/a` arms.
5. `inngest-registry-empty-alert.test.sh`: sanitize presence rows, BOOT `mutate_red` removing a
   sanitize, rendered-line hostile-input row, floor bumps.
6. `inngest-probe-heartbeat-feeder.test.sh`: fixture refresh.
7. Sweep: `grep -rn 'probe_schema=9\|probe_schema=[0-9]'` over consumers; update pins only (leave
   historical/doc references that describe past schemas).

### Phase 2 — Live-mode preflight replaces the typed-confirm gate

1. Write `tests/scripts/lib/inngest-public-sdk-url-preflight.sh` (TDD: parity table red first).
2. Workflow: swap both gate steps; remove the `hcloud_server.inngest` error line; verify
   `wc -c` ≤ 490,000.
3. Parity suite: replace the four B10 tests; keep G2f/other pins intact.
4. Delete `inngest-public-sdk-url-confirm.sh`; repoint CODEOWNERS; sweep
   `grep -rn 'PUBLIC-SDK-URL'` to zero live carriers; update the six known carrier files +
   `inngest-server.md` + job-rationale runbook + `test-all.sh` comment.
5. Verify no other `inputs.confirm` consumer is affected.

### Phase 3 — Verification

1. `bash apps/web-platform/infra/inngest.test.sh`; `bash
   apps/web-platform/test/infra/inngest-registry-empty-alert.test.sh`; `bun test
   plugins/soleur/test/terraform-target-parity.test.ts`; `bun test
   plugins/soleur/test/workflow-file-size.test.ts`; affected shell suites.
2. `grep -rn 'PUBLIC-SDK-URL\|inngest-public-sdk-url-confirm' --exclude-dir=node_modules` → only
   history/archive references.
3. `bash scripts/test-all.sh` (or the repo's fast CI subset) green.

## Acceptance Criteria

- [ ] A serving dedicated-host probe row carries `sdk_sync=ok` and `sdk_app_url=` naming the
      registered URL(s); a stale-registry/failed-poll row carries `sdk_sync=error`; web rows carry
      `n/a`; every failure arm renders `__UNREADABLE__`, never `0`, never absent.
- [ ] `probe_schema=10` on both emit lines; `_IHDG_EXPECTED_SCHEMA="10"`; `inngest-luks-field-8525.sh`
      accepts 9 and 10.
- [ ] `image_ref`/`cli_version` are sanitized to `[A-Za-z0-9_:.@/+-]`; the guard's new rendered-line
      row proves a hostile ` registry_fns=5 ` value cannot mask `registry_fns=0` on either emit or
      phone-home.
- [ ] Both `inngest_host` and `inngest_host_replace` run the preflight unconditionally after
      credential load and before terraform; the preflight passes only when the last enabled
      `app.soleur.ai` config rule is `ssl=strict`, and refuses distinctly on every ambiguity
      (unverified API read included).
- [ ] `PUBLIC-SDK-URL`/`PUBLIC-SDK-URL-BIRTH` appear in zero live recipes, zero workflow lines, zero
      scripts; `inngest-public-sdk-url-confirm.sh` is deleted and CODEOWNERS repointed.
- [ ] `apply-web-platform-infra.yml` ≤ 490,000 bytes; `inputs.confirm` and its other consumers
      unchanged.
- [ ] All touched guard suites green; mutation rows prove each new pin turns red when its protected
      property is removed.
- [ ] No change enables, schedules, or documents the owner's `inngest-host-replace` dispatch beyond
      the recipes' preflight note.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "[issue #12742 item 1] Add a field to `SOLEUR_INNGEST_SERVER_PROBE` showing that the server's last successful sync is recent. This must merge before the replace." | Phase 1 T1–T4 (`sdk_sync`/`sdk_app_url`, schema 10); AC 1–2 | mapped |
| 2 | "[issue #12742 item 1] The registry-empty alert added in #12737 cannot see a stale non-zero registry (CTO ruling 2026-11-13)." | `sdk_sync` discriminator in same row; AC 1 | mapped |
| 3 | "[brief] Replace `tests/scripts/lib/inngest-public-sdk-url-confirm.sh` with a fail-closed live-mode preflight. Both `inngest_host_replace` and `inngest_host` birth must invoke it... refuse unless the last Cloudflare config rule matching `app.soleur.ai` has `ssl = strict`." | Phase 2 T8–T10; Guard 1; AC 4 | mapped |
| 4 | "[brief] Remove the B10 recipe sweep... including: three recovery lines in `scripts/cutover-inngest.sh`; `scripts/followthroughs/inngest-private-nic-8539.sh`; runbooks inngest-config-refresh.md and inngest-luks-cutover-6894.md; the workflow's own `hcloud_server.inngest` error line. Remove both confirmation tokens." | Phase 2 T10–T13; Guard 3; AC 5 | mapped |
| 5 | "[brief/CTO F4(ii)] `image_ref` and `cli_version` are free-text fields... A value containing ` registry_fns=5 ` could mask a real `registry_fns=0`. Choose one permitted remedy: sanitize both fields... or change the alert... Add a rendered-line mutation row either way." | Phase 1 T1 (sanitize) + T5 (guard rows); Guard 2; AC 3 | mapped |
| 6 | "[brief] Do not plan or touch issue #12742 items 2–9." | Non-Goals; item-9 tension recorded in decision-challenges row 7 | mapped |
| 7 | "[brief] changed paths must be limited to `knowledge-base/project/(plans\|specs)/`" during planning | This run wrote only `knowledge-base/project/**` | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `sdk_sync`/`sdk_app_url` fields + gather block | asks 1–2 | asked |
| `probe_schema` 9→10 + `_IHDG_EXPECTED_SCHEMA` | — | inferred — justification: the emit schema declares the new fields' contract; all consumers pin it (`probe_schema=9` asserts, dark gate G4, luks-field followthrough), so leaving 9 ships a lie about the row's shape |
| `image_ref`/`cli_version` sanitize + guard rows | ask 5 | asked |
| `inngest-public-sdk-url-preflight.sh` + step swap | ask 3 | asked |
| B10 successor tests + inverted recipe sweep + token removal | asks 3–4 | asked |
| Witness `stale_schema`→alive audit (T2 subtask) | — | inferred — justification: the schema bump is required, and an unaudited streak classification could misread a healthy-emitting host during the merge→replace window |
| CODEOWNERS repoint | ask 4 ("the live-mode preflight must take its place") | inferred — justification: the pinned path is deleted; a dead CODEOWNERS line silently un-owns the replacement |
| Item-9 carrier-comment refresh | — | inferred — justification: item 9's own trigger is "the next time that file changes for a real reason"; tension with the items-2–9 exclusion recorded as decision row 7 |

### Split Assessment

- Subsystems touched: 3 — `apps/web-platform/infra` (probe emitter + alert guard tests), `tests/`+`plugins/soleur/test`+`.github` (gate lib, parity suite, workflow, CODEOWNERS), `scripts/`+`knowledge-base/engineering/operations/runbooks` (recipe sweep, followthroughs)
- Planned files: ~18 | Estimated changed lines: ~700 (incl. ~90 new script lines)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the issue mandates the probe field AND the gate swap land in the same merge (the gate exists to protect the replace the fields must precede); splitting re-opens the window

## Observability

```yaml
liveness_signal:
  what:            SOLEUR_INNGEST_SERVER_PROBE journald row -> Vector -> Better Stack (existing pipeline; this PR appends sdk_sync/sdk_app_url fields, probe_schema=10)
  cadence:         per-probe tick (systemd timer on the dedicated host; unchanged)
  alert_target:    operator email + push via logtail_exploration_alert.inngest_registry_empty (existing; SQL unchanged) and the #8080 health witness
  configured_in:   apps/web-platform/infra/betterstack-logs-alerts.tf (logtail_exploration{,_alert}.inngest_registry_empty); emitter apps/web-platform/infra/inngest-bootstrap.sh:1335

error_reporting:
  destination:     Better Stack logs-alerts (probe rows + vector-down phone-home detail); GHA job log for the dispatch gate
  fail_loud:       probe row carries sdk_sync=error or __UNREADABLE__ (stale registry / dead local GQL); preflight prints a distinct ::error:: per refusal arm and exits 1

failure_modes:
  - mode:          stale non-zero registry after a failed post-replace sync (the gap the #12737 alert cannot see)
    detection:     same-row sdk_sync=error with registry_fns>=1 — responder evidence, not a new page (alert extension deferred per Alternatives)
    alert_route:   existing registry-empty alert unchanged; witness/dark-gate verdicts unchanged
  - mode:          dispatch attempted while last enabled app.soleur.ai rule is not ssl=strict (or CF read unverifiable)
    detection:     inngest-public-sdk-url-preflight.sh refuses rc=1 with a distinct ::error:: arm before any terraform step
    alert_route:   the dispatching job fails red in the Actions UI
  - mode:          free-text probe field (image_ref/cli_version) injects a second ` registry_fns=` token
    detection:     charset sanitize at bind + rendered-line row in inngest-registry-empty-alert.test.sh proving the decoy cannot mask registry_fns=0
    alert_route:   pre-merge test failure (drift guard)

logs:
  where:           journald on the dedicated host (LOG_TAG soleur-inngest-probe) -> Better Stack; vector-down fallback via inngest-boot-phone-home.sh (shipper=cloud-init-phone-home)
  retention:       Better Stack plan retention (existing; unchanged by this PR)

discoverability_test:
  command:         bash apps/web-platform/test/infra/inngest-registry-empty-alert.test.sh
  expected_output: "0 failed"
```

**Signal discrimination.** Post-change, one `SOLEUR_INNGEST_SERVER_PROBE` row discriminates: healthy
cutover (`registry_fns>=1 sdk_sync=ok sdk_app_url=https://app.soleur.ai…`), stale registry after a
failed replace (`registry_fns>=1 sdk_sync=error`), diagnostic boot (`registry_fns=0
sdk_sync=no_apps`), dead local API (`__UNREADABLE__` pair), pre-replace host
(`sdk_app_url=http://10.0.1.10…`). No alert SQL changes: the registry-empty alert keeps its
ruling-F1 scope; the new fields are responder evidence in the same row (the single-event,
no-correlation rationale from the #10538 decision). A future `sdk_sync=error` page is possible but
deferred — the field must first exist on the live host to tune against.

## Encryption Posture

```yaml
at_rest: []  # no new persistent stores; the projection is evaluated in-memory and discarded
in_transit:
  - connection:        GHA runner (inngest_host / inngest_host_replace jobs) -> api.cloudflare.com rulesets entrypoint (via cloudflare-readonly.sh config-entrypoint)
    enforced_at:       plugins/soleur/scripts/cloudflare-readonly.sh (fixed https URL, absolute curl path, credential on stdin config)
    tls:               https (TLS 1.2+ via Cloudflare edge policy; curl default verification)
    cert_verification: on
    does_not_defend:   a stolen CF_API_TOKEN_RULESETS still authorizes ruleset WRITES (token is write-capable; a read-only equivalent is owner credential work, not this PR)
    disclosed_as:      not-publicly-claimed
```

Notes: the probe's new GQL read reuses the existing loopback socket
(`http://127.0.0.1:8288/v0/gql`, same as `registry_fns`) — not a new connection. `sdk_app_url`
carries hostnames (not secrets) through the `[A-Za-z0-9_:.@/+-]` sanitize; no GQL error text is
shipped (stderr stays swallowed per the existing comment contract). Ledger row 6 conversion is
item 5 — out of scope.

## User-Brand Impact

- **If this lands broken, the user experiences:** a post-replace sync failure invisible to every
  surface — workflow events stop being scheduled while the registry-empty alert, the health
  witness, and the probe row all still read healthy (stale Postgres registry masks it); the
  user-visible symptom is automations silently not running.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the Inngest sdk_url poll
  carrying event names and payloads (which embed user identifiers) over a TLS-to-edge /
  plaintext-to-origin path — exactly what happens if `inngest-host-replace` is ever dispatched while
  the last applicable `app.soleur.ai` rule is not `ssl=strict`, contrary to the stated privacy
  posture (Privacy Policy s11 / DPD 8.1(c) carve-out this remedy retires).
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** exposure is all-users' event traffic on the shared
  scheduler, not one user's session — above `single-user incident`; it is bounded by a single
  dispatch decision, not a systemic recurring leak, so not the maximal reading either.

## Domain Review

| Domain | Relevance | Assessment |
|---|---|---|
| Engineering/Infra | PRIMARY | Probe emitter, IaC-adjacent workflow gates, Cloudflare read path, mutation-tested guards |
| Legal/CLO | ADVISORY | The gate protects a CLO-ruling condition (#10479-strict precondition); published-wording item 7 stays with CLO; no wording change here |
| Security | RELEVANT | Fail-closed credential handling, token non-echo, no raw third-party response content shipped to logs |
| Product | NONE | No UI/route/user-surface files touched |
| Finance/Sales/Marketing/Support/Ops | NONE | No artifacts in scope |

Assessment performed inline (no agent-spawn capability in this session); Legal/CLO flagged as
advisory for the eventual PR review, not blocking planning.

## Guard Contract

### Guard 1 — strict-SSL dispatch preflight (`inngest-public-sdk-url-preflight.sh` + job steps)

**Property.** Neither `inngest_host` nor `inngest_host_replace` may reach a terraform step unless
the live Cloudflare config-settings entrypoint shows the LAST enabled rule mentioning
`app.soleur.ai` with `ssl=strict`; every unreadable or ambiguous read refuses.

**Assembly.** Each job's step list is the sole path from dispatch to `terraform plan/apply` for
`hcloud_server.inngest`; the gate step sits after `Load infra credentials (tiered)` (which makes
`doppler`/the CF token reachable) and before the first terraform step in BOTH jobs, is
unconditional (no `if`, no `continue-on-error`, no `shell`/`working-directory` override), and the
script is the single evaluator of the wrapper's `.rules[]` projection — a closed verdict set:
pass iff `>=1` enabled `mentions_app_host` rule AND its last member has `ssl == "strict"`;
everything else (no token, doppler rc, `unverified`, malformed JSON, no match, non-strict last,
ambiguous shape) refuses rc=1 with a distinct `::error::` and no echoed credential or body.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Step moved after `Terraform plan` (or deleted from one job) | parity step-shape row RED |
| 2 | `continue-on-error: true` or an `if:` added to the step | parity row RED (gate tolerated) |
| 3 | `env.DOPPLER_TOKEN` dropped | RED — the missing-token arm must be reachable |
| 4 | `--from-file` fixture: last enabled app-host rule `ssl=flexible`; fixture: `strict` but disabled leaving no enabled match | script rc=1 in both (behavior table) |
| 5 | Fixture: wrapper prints `... unverified - <reason>`; malformed JSON | rc=1, distinct `::error::` (not a crash) |

### Guard 2 — probe-field masking sanitize (F4(ii))

**Property.** No free-text field on the probe row may inject a second space-delimited ` key=` token
— a ` registry_fns=5 ` inside `image_ref`/`cli_version` must never mask a real `registry_fns=0`.

**Assembly.** The emit line and its phone-home twin are the ONLY producers of the row; the ruling
names `image_ref` (L~679) and `cli_version` (L~704) as the free-text binds — the remaining fields
are enum/numeric sentinels or infra-fixed tokens (boot_id hex, mount device paths) whose values are
structurally space-free on this host. Routing both named binds through the `[A-Za-z0-9_:.@/+-]` charset
sanitize (in-file `tr` precedent at L1184) at bind time covers every emitted path structurally,
including the phone-home detail that reuses the same variables.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Remove the sanitize from the `image_ref` bind | guard presence row RED |
| 2 | Remove the sanitize from the `cli_version` bind | RED |
| 3 | Rendered line: hostile value containing ` registry_fns=5 ` through the extracted sanitize pipeline | alert still fires on `registry_fns=0` (EMIT and PH) |
| 4 | Fixture emit where `image_ref` survives un-sanitized | the ` registry_fns=[1-9]` positive needle must not satisfy off the real field |

### Guard 3 — B10 successor parity pins (terraform-target-parity.test.ts)

**Property.** The retired confirm mechanism leaves no live carrier: zero workflow steps, zero
recipes, zero script references to `PUBLIC-SDK-URL*`/`inngest-public-sdk-url-confirm.sh`; the two
jobs each keep exactly one unconditional preflight step in the post-credentials/pre-terraform slot.

**Assembly.** The git-ls-files census the old B10 sweep already walks (`scripts`,
`tests/scripts/lib`, `apps/web-platform/infra`, `.github/workflows`,
`knowledge-base/engineering/operations/runbooks`, `plugins/soleur/skills`) is the same set the new
sweep re-walks with the inverted predicate; the step-shape assertions re-run over the parsed YAML
job blocks — same chokepoints, inverted claim.

**Mutation matrix.**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | A recipe re-introduces `-f confirm=PUBLIC-SDK-URL` | inverted sweep RED |
| 2 | A job's preflight step deleted or renamed | step-shape row RED |
| 3 | `CONFIRM_RAW` reintroduced on a step | RED (no `inputs.confirm` consumer remains) |
| 4 | `inngest-public-sdk-url-confirm.sh` restored to disk | file-absence row RED |

Floors (`PRESENCE_ROWS`, `MUT_ROWS` in the alert guard; the parity suite's counts) are bumped per
added row so an untested assertion cannot go uncounted. Token widening is swept via `grep` for
`PUBLIC-SDK-URL`, `probe_schema=9`, `inngest-public-sdk-url-confirm` across all consumers
(hr-type-widening-cross-consumer-grep).

## Architecture Decision

No new ADR: the change swaps the mechanism on an existing enforced boundary (dispatch → live
Cloudflare read → refuse) already modeled by ADR-136's entrypoint-gate precedent; the trust boundary
(job runs an in-repo, read-only, credential-bound check before terraform) is unchanged in shape.
C4 `inngest -> api` edge update is explicitly item 6 — out of scope.

## Alternatives Considered

- **`countMatches(msg, ' registry_fns=') != 1` alert predicate** (permitted alternative for F4(ii)):
  rejected — fixes one consumer; sanitize fixes the data for all consumers. Recorded as
  pending-assumed decision.
- **Extend the registry-empty alert to page on `sdk_sync=error`**: rejected for this PR — the field
  does not exist on any live host until the replace; tuning a new page against a field with no
  production history risks alert fatigue on the most sensitive paging surface. Responder-visible
  evidence ships now; paging decision can follow with data.
- **Preflight inside Terraform (external data source / provisioner)**: rejected — puts a live API
  read inside plan evaluation, violates the ADR-136 job-step gate shape and couples a read to the
  apply lifecycle.
- **Keep `inputs.confirm` consumption as belt-and-suspenders**: rejected — a dead token invites
  recipe drift and re-splits the gate's meaning; the issue mandates replacement.
- **`sdk_sync` from `functions[].synced`-style data or a second `deploys` query**: the `apps{url
  error}` pair is the smallest surface that both proves last-attempt success and serves item 4's
  URL-listing need; `deploys`/`functions` expose no last-attempt discriminator in the dev-server GQL.
  Exact GQL field spellings (`error`, `url`) verified at implementation against the pinned Inngest
  version; sentinel arms make a schema drift fail loud, not silent.

## Non-Goals

- Owner's `inngest-host-replace` dispatch and every prerequisite for it (#10479 closure, #12726,
  `INNGEST_CUTOVER_FLIP`, zot mirror pin, concurrency check) — production act, item 2.
- Hop-1 measurement, private-poll cessation measurement (items 3–4 — post-replace).
- `scripts/encryption-posture-ledger.json` row 6, C4 `model.likec4.json`, privacy-policy/DPD
  wording, owner accepted-risk record (items 5–8).
- Any new paging alert on `sdk_sync` (deferred, see Alternatives).
- Any change to `inputs.confirm` or the ~10 other targets consuming it.

## Downtime & Cutover

The user_data rendered from `inngest-bootstrap.sh` changes, which marks `hcloud_server.inngest`
for replacement on any apply that targets it — but no such apply runs on merge: the per-PR CI
apply strips both inngest targets (`stripDispatchJobs` parity pin), and the only applicator is the
owner's `workflow_dispatch` of `inngest_host_replace` (item 2, a sanctioned production act with its
own runbook, downtime model, and now a stricter preflight). This PR introduces **no new
offline-inducing operation**: the host keeps serving on the old image until the owner chooses the
replace window; a replace is itself a drain-by-destruction act already owned by that runbook. The
zero-downtime path is therefore "deferred to the owner act it already is"; residual risk noted:
between merge and replace the witness reports `stale_schema` (truthful, see Observability/
decision-challenges row 5), and `inngest-luks-field-8525.sh`-style consumers are updated to read
both schemas so no measurement silently empties.

## Risks & Mitigations

| Risk | Mitigation |
|---|---|
| `apps { url error }` GQL field names differ on the pinned Inngest version | `__UNREADABLE__` fail-loud arms; verify against the installed build at implementation (fixture-driven test in `inngest.test.sh` pins the JSON shape the probe parses) |
| Witness streak counts `stale_schema` as a page-bearing refusal during the merge→replace window | T2 subtask: audit the streak classification; map the token to alive/not-dark if needed; recorded as decision row 5 |
| Workflow edit exceeds the 5-byte headroom | Net-negative diff (removes ~660 B, adds ~520 B); `wc -c` verified before commit; prose relocated to the job-rationale runbook per the gate's own error text |
| Wrapper's dated-snapshot verdict drifts (rules added after 2026-11-13) | Preflight judges `.rules[]` projection, not the baked verdict; a non-`ok` wrapper line still refuses — fail closed in both directions |
| Sanitize changes a legitimate `image_ref`/`cli_version` value | Charset `[A-Za-z0-9_:.@/+-]` covers docker refs, semver, and registry paths; `must-PASS` fixture row keeps a representative real value green |

### Precedent-diff (pattern-bound behaviors)

| New shape | Sibling precedent | Delta |
|---|---|---|
| `inngest-public-sdk-url-preflight.sh` fail-closed gate + `--from-file` seam | `tests/scripts/lib/preapply-entrypoint-gate.sh` (ADR-136, `--gate tfplan.json`, `::add-mask::`, default-deny) | same verdict shape; reads a captured projection instead of a plan file; adds the doppler-exec arm |
| `SDK_SYNC_GQL_QUERY` + gather block | `FUNCTIONS_GQL_QUERY` + `registry_fns` block (L650/L955-995) | identical failure-arm taxonomy (`__UNREADABLE__`, swallowed stderr, jq-guarded) |
| `image_ref`/`cli_version` sanitize | `probe_scan_err` `tr -c 'A-Za-z0-9' '_' \| cut -c1-48` (L1184) | extended charset (`_:.@/+-` retained) — docker refs/versions need them; no truncation (the mask property doesn't require a 48-char cut) |
| Step placement post-credentials | `Pre-apply entrypoint gate` step (workflow ~L928-955) | same post-credential, pre-write position; lighter env (single `DOPPLER_TOKEN`) |

No novel pattern lacks a repo sibling.

## Enhancement Summary

Deepen-plan pass (2026-11-17) sharpened the plan on: (1) the exact `.rules[]` projection shape at
cloudflare-readonly.sh L426 (`enabled` pre-normalized, `mentions_app_host` boolean) and the
wrapper's dated-snapshot verdict — the preflight judges the projection, not the verdict; (2) the
dark-gate lib's THREE sourcing callers — the witness's report-only `stale_schema` token needs a
streak classification audit (new T2 subtask, decision row 5); (3) `hr-` (not `cq-`) rule-id
citation fix; (4) gate-schema sections (Observability/Encryption/Guard Contract/Scope Check/
Downtime) emitted in template form; (5) precedent-diff table for all four new shapes.
Reviewed-Coverage: sequential-fallback — no agent-spawn capability in this session; research,
verify-the-negative, and review passes ran inline.

## Open Questions / Decision Records

See `knowledge-base/project/specs/feat-one-shot-12742-public-sdk-url-poll/decision-challenges.md`
for pending-assumed rulings: sync-evidence field names/GQL shape, F4(ii) sanitize-vs-countMatches
choice, alert-extension deferral, preflight script interface details, schema-10 `stale_schema`
window + witness classification consequence, item-9 carrier-comment scope tension.
