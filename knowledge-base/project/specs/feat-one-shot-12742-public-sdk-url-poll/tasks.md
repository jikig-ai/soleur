# Tasks — feat-one-shot-12742-public-sdk-url-poll (#12742 item 1)

Plan: `knowledge-base/project/plans/2026-11-17-feat-inngest-sdk-url-sync-evidence-strict-preflight-plan.md`

## Phase 1 — probe sync evidence + F4(ii) + schema 10

- [x] T1. `apps/web-platform/infra/inngest-bootstrap.sh`:
  - add `readonly SDK_SYNC_GQL_QUERY='query SdkSyncProbe { apps { url error } }'` beside
    `FUNCTIONS_GQL_QUERY` (~L650; verify exact GQL field names against the pinned Inngest version —
    a wrong name must fail to `__UNREADABLE__`, not silently).
  - sanitize `image_ref` (bind ~L679) and `cli_version` (bind ~L704) to charset
    `[A-Za-z0-9_:.@/+-]` → `_`, reusing the in-file `tr` precedent (`probe_scan_err`, ~L978).
  - bind `sdk_sync=n/a`, `sdk_app_url=n/a` with the other unconditional-emit binds (~L755).
  - inside the dedicated arm beside `registry_fns` (~L955-995): second curl to
    `http://127.0.0.1:8288/v0/gql` with the new query; same failure arms (`http_code!=200`, no `jq`,
    curl/jq failure, non-array) → `__UNREADABLE__`; empty array → `no_apps`/`none`; every `error`
    null/empty → `sdk_sync=ok`, else `error`; `sdk_app_url` = sanitized `,`-joined `.data.apps[].url`.
    Never ship GQL error text (stderr stays `2>/dev/null`-swallowed; no response content emitted).
  - `probe_schema=9` → `probe_schema=10` (~L740).
  - append ` sdk_sync=$sdk_sync sdk_app_url=$sdk_app_url` after `data_luks` on BOTH the emit line
    (L1335) and the vector-down phone-home detail (L1366), same order.
  - refresh the stale `co-located web-platform` carrier comment (#12742 item 9 trigger; see
    decision-challenges row).
- [x] T2. `tests/scripts/lib/inngest-host-dark-gate.sh` L128: `_IHDG_EXPECTED_SCHEMA="9"` → `"10"`;
  update the `stale_schema` comment if it hardcodes "9".
  - T2a. Add a `#12742` comment at the `stale_schema`→`refusal` arm in
    `scripts/inngest-gate-witness-classify.sh` (~L60) recording the deliberate choice — CTO ruled
    2026-11-17 (decision-challenges row 5): the witness measures execute-gate satisfiability, not
    host darkness, so `refusal` is the truthful token during the merge→replace window; no
    alive/not-dark mapping is added (it would forgive a stuck replace past the 2026-11-20 ledger
    expiry). `cutover-inngest.sh` L1105 wants the refusal (designed-for). `infra-validation.yml`
    L205 is presence-only.
- [x] T3. `scripts/followthroughs/inngest-luks-field-8525.sh` (~L104-110): accept `probe_schema` 9
  or 10 (`>=9` semantics preserved: a schema-10 row must not read TRANSIENT/not_schema9).
- [x] T4. `apps/web-platform/infra/inngest.test.sh` (~L1365+): `PROBE_7695_FIELDS` +=
  `sdk_sync sdk_app_url`; add both to `PROBE_7695_NEVER_ZERO` (no `0` is meaningful for either);
  `probe_schema=9( |$)` assert → `10`; stub the `apps` GQL response per arm — dedicated serving:
  `ok` + URL; `apps[].error` non-empty arm: `sdk_sync=error` with `registry_fns>0` (the stale-registry
  discriminator); empty array: `no_apps`; GQL down: `__UNREADABLE__`; web arm: `n/a`.
- [x] T5. `apps/web-platform/test/infra/inngest-registry-empty-alert.test.sh`:
  - presence row: both sanitize applications exist on the `image_ref`/`cli_version` binds in BOOT.
  - `mutate_red` BOOT row: remove one sanitize call → presence row reds.
  - rendered-line row: substitute a hostile value containing ` registry_fns=5 ` through the sanitize
    pipeline extracted from BOOT; assert `_fires` still true on `registry_fns=0` for EMIT and PH.
  - bump `PRESENCE_ROWS`/`MUT_ROWS` (L674-675) for each added row; re-render assertions pick up the
    appended fields.
- [x] T6. `scripts/inngest-probe-heartbeat-feeder.test.sh`: fixtures `probe_schema=9` → `10` where
  they model the current emitter.
- [x] T7. Sweep `grep -rn 'probe_schema' apps/ scripts/ tests/ plugins/ .github/` — update only live
  pins (asserts/expects); leave historical comments describing past schemas.

## Phase 2 — live-mode preflight replaces typed confirm

- [x] T8. Write `tests/scripts/lib/inngest-public-sdk-url-preflight.sh` (fail-closed):
  - default mode: `doppler run -p soleur -c prd_terraform -- plugins/soleur/scripts/cloudflare-readonly.sh
    config-entrypoint`, capture stdout+rc (requires `DOPPLER_TOKEN` in env; missing → refuse).
  - `--from-file <path>` test seam: read a captured projection file instead of calling doppler.
  - pass iff output is `cloudflare-readonly: config-entrypoint ok` + parseable JSON projection AND
    ≥1 enabled rule mentions `app.soleur.ai` AND the LAST enabled app-host rule with non-null `ssl`
    has `ssl=strict` AND no enabled rule positioned after it carries `ssl` in `{off, flexible}`
    (CTO-strengthened predicate, decision-challenges row 4: closes the wildcard-expression evasion).
    Amended by review rulings R1 to R3 (decision-challenges.md, "Review-round rulings"); the current predicate is the
    preflight script's header.
  - refuse rc=1 with distinct `::error::` messages: no token / doppler rc / `unverified` / malformed
    JSON / no matching rule / all matches disabled / last match `ssl!=strict` / trailing rule
    `ssl ∈ {off, flexible}` / ambiguous shape. Never echo the token or the raw API body.
- [x] T9. `.github/workflows/apply-web-platform-infra.yml` (byte budget: 489,995 / 490,000):
  - `inngest_host` (~L1719) and `inngest_host_replace` (~L1902): delete the
    `Validate dispatch inputs … confirm token` step; insert after `Load infra credentials (tiered)`
    and before the first terraform step:
    `- name: Public sdk_url strict-SSL preflight (#12742)` with `env: DOPPLER_TOKEN: ${{ secrets.DOPPLER_TOKEN }}`,
    `run: bash tests/scripts/lib/inngest-public-sdk-url-preflight.sh`; one-line rationale comment
    pointing at the job-rationale runbook.
  - remove the `hcloud_server.inngest` `PUBLIC-SDK-URL` error line.
  - do NOT touch `inputs.confirm` (L51) or its ~10 other consumers.
  - verify `wc -c` ≤ 490,000 after edits.
- [x] T10. `plugins/soleur/test/terraform-target-parity.test.ts` (~L5186-5305): replace the four
  B10 tests —
  - per-job preflight step shape: unconditional, positioned after `Load infra credentials` and
    before first terraform step, `env.DOPPLER_TOKEN` present, `run` is the preflight script, no
    `CONFIRM_RAW`/`continue-on-error`/`if`; keep the "no always()/failure() step touches secrets
    after the gate" verifier and the no-job-env/no-checkout-`with` pins.
  - neither job consumes `inputs.confirm`. Amended by review ruling R5 (decision-challenges.md, "Review-round
    rulings"): the replace job requires `confirm=REPLACE-INNGEST-HOST` (typo-guard); the birth stays token-free.
  - inverted recipe sweep: ≥6 live recipes for the two targets still found (non-vacuity) AND zero
    may carry `confirm=PUBLIC-SDK-URL[-BIRTH]`; assert zero offenders.
  - script behavior table over `--from-file` fixtures: strict-last → 0; flexible-last, all-disabled,
    no-match, `unverified`, malformed JSON, missing file, strict-then-trailing-flexible → 1 with the
    right `::error::` arm (the trailing-flexible arm is the CTO-strengthened predicate).
  - keep G2f and all unrelated pins; check the L113 `349 -> 353` count comment for drift.
- [x] T11. Delete `tests/scripts/lib/inngest-public-sdk-url-confirm.sh`; repoint
  `.github/CODEOWNERS` L48 to the new script.
- [x] T12. Remove `PUBLIC-SDK-URL`/`PUBLIC-SDK-URL-BIRTH` from every live carrier (B10 sweep + grep):
  `scripts/cutover-inngest.sh` (3 recovery lines),
  `scripts/followthroughs/inngest-private-nic-8539.sh`,
  `knowledge-base/engineering/operations/runbooks/inngest-config-refresh.md`,
  `knowledge-base/engineering/operations/runbooks/inngest-luks-cutover-6894.md`,
  `knowledge-base/engineering/operations/runbooks/inngest-server.md` (§confirm sections — note the
  preflight is automatic),
  `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
  (§inngest_host, §inngest_host_replace),
  `scripts/test-all.sh` L7009 comment if it names removed tests.
  Also restate the preflight's placement property in `inngest-server.md` (~L2709) and
  `apply-web-platform-infra-job-rationale.md` (~L1447): the new property is "immediately after
  `Load infra credentials (tiered)`, before `Terraform init`, unconditional, fail-closed" — the
  old "before any credential loads" wording describes a property that no longer exists (CTO row 6
  dissent).
- [x] T13. Final sweeps: `grep -rn 'PUBLIC-SDK-URL' --exclude-dir=node_modules` → archive/history
  only; `grep -rn 'inngest-public-sdk-url-confirm'` → archive/history only.

## Phase 3 — verification

- [ ] T14. Run: `bash apps/web-platform/infra/inngest.test.sh`,
  `bash apps/web-platform/test/infra/inngest-registry-empty-alert.test.sh`,
  `bun test plugins/soleur/test/terraform-target-parity.test.ts`,
  `bun test plugins/soleur/test/workflow-file-size.test.ts`, plus affected suites
  (`inngest-probe-heartbeat-feeder.test.sh`, `cloud-init-inngest-bootstrap.test.sh`,
  `cutover-inngest-workflow.test.sh` as applicable).
- [ ] T15. `bash scripts/test-all.sh` (or the repo CI subset) green.
- [x] T16. At ship time, post a comment on #12742 recording the deferred `sdk_sync=error` paging
  decision (CTO row 3: "page on `sdk_sync=error` post-measurement" — deferred until the field has
  production history after the owner's replace).
