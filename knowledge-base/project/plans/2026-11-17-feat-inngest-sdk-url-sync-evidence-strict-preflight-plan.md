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
    `stale_schema` when the host's newest `probe_schema=` row ≠ expected (G4, L541-563).
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
  - `probe_schema` bumps `9` → `10`; `_IHDG_EXPECTED_SCHEMA` bumps to `10` (dark-gate `stale_schema`
    on the pre-replace host is the designed-for signal that the host predates the emitter that can
    prove recent sync — record; it cannot block the owner's replace, which does not route through
    that gate).
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
  `cloudflare-readonly: config-entrypoint ok`, the JSON projection parses, ≥1 enabled rule mentions
  `app.soleur.ai`, and the **last** such rule has `ssl == "strict"`. Refusals (distinct `::error::`
  per arm, never echoing tokens or raw bodies): missing `DOPPLER_TOKEN`, doppler/wrapper rc≠0,
  `unverified` output, malformed JSON, no matching rule, `enabled=false` on all matches, last match
  `ssl != strict`, ambiguous shape. `--from-file <path>` reads a captured projection instead of
  calling doppler — the parity test's behavior table runs that seam (live path is exercised by the
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

| Ask | Covered by |
|---|---|
| Probe field proving recent last-sync, merged pre-replace | Phase 1 tasks 1–4; AC 1–2 |
| Registry-empty alert can't see stale non-zero | Preserved property + new `sdk_sync` discriminator in same row; AC 1 |
| Fail-closed live-mode preflight on both dispatches | Phase 2 tasks 1–3; AC 4 |
| Replace (not merely delete) confirm script | New script + delete + CODEOWNERS; AC 5 |
| Remove B10 sweep recipes + both tokens | Phase 2 task 4; AC 5 |
| F4(ii): sanitize fields OR countMatches + rendered mutation row | Sanitize chosen; Phase 1 task 5; AC 3 |
| Items 2–9 out of scope | Non-Goals; item-9 carrier-comment tension recorded |
| No product/YAML/test edits during planning | This run wrote only `knowledge-base/project/**` |

## Observability & Signal Discrimination

The probe row is the diagnostic surface. Post-change, one `SOLEUR_INNGEST_SERVER_PROBE` row
discriminates: healthy cutover (`registry_fns≥1 sdk_sync=ok sdk_app_url=https://app.soleur.ai…`),
stale registry after failed replace (`registry_fns≥1 sdk_sync=error`), diagnostic boot
(`registry_fns=0 sdk_sync=no_apps`), dead local API (`__UNREADABLE__` pair), pre-replace host
(`sdk_app_url=http://10.0.1.10…`). No alert SQL changes: the registry-empty alert keeps its
ruling-F1 scope; the new fields are responder evidence in the same row (the single-event,
no-correlation rationale from the #10538 decision). A future `sdk_sync=error` page is possible but
deferred — the field must first exist on the live host to tune against.

## Encryption Posture

The new edge (GHA job → Cloudflare API via `cloudflare-readonly.sh`) is already-in-repo, HTTPS,
token-scoped (`CF_API_TOKEN_RULESETS`), no persistence, no payload beyond the ruleset read; the
credential rides Doppler injection and is never printed (wrapper's xtrace refusal + `::add-mask::`
precedent). Probe-side, the new GQL read is loopback-only; `sdk_app_url` carries URLs (hostnames,
not secrets) through the same allowed-charset sanitize that precedent `probe_scan_err` uses; no GQL
error text is shipped to the warehouse (existing comment contract preserved). Ledger row 6
conversion is item 5 — out of scope.

## User-Brand Impact

The Inngest sdk_url carries workflow event traffic. Today the live host polls over plaintext HTTP on
the private network; remedy (c) is what retires that exposure. If `inngest-host-replace` ran while a
`flexible` rule still matched `app.soleur.ai`, the public hop would serve TLS-to-edge/plaintext-to-
origin (or worse) — the exact class this remedy exists to kill — while the repo's published posture
claims strict. The typed token cannot see that; the preflight can. Exposure description for users:
event names and payloads (which embed user identifiers) traversing an unencrypted segment contrary
to stated privacy commitments. Brand-survival threshold: **zero replaces dispatched while any
applicable `app.soleur.ai` rule is non-strict** — the gate must fail closed on unverifiable reads
because "unknown" is not "safe". The sync-evidence field protects a different brand surface: a
silent post-replace failure would leave customer workflows un-executed while every dashboard reads
healthy — the row-level `sdk_sync=error` is the first discriminating signal.

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

New guards ship with mutation evidence: the preflight's behavior table covers every refusal arm;
the parity tests mutate step shape (removed `if`, moved position, dropped env); the alert guard adds
the sanitize-removal `mutate_red` and the hostile-rendered-line row; floors (`PRESENCE_ROWS`,
`MUT_ROWS`) are bumped so an untested row cannot go uncounted. Type/token widening is swept via
`grep` for `PUBLIC-SDK-URL`, `probe_schema=9`, `inngest-public-sdk-url-confirm` across all consumers
(cq-type-widening-cross-consumer-grep).

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

## Open Questions / Decision Records

See `knowledge-base/project/specs/feat-one-shot-12742-public-sdk-url-poll/decision-challenges.md`
for pending-assumed rulings: sync-evidence field names/GQL shape, F4(ii) sanitize-vs-countMatches
choice, alert-extension deferral, preflight script interface details, schema-10 `stale_schema`
window consequence, item-9 carrier-comment scope tension.
