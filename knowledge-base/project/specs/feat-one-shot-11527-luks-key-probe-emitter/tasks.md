# Tasks — feat-one-shot-11527-luks-key-probe-emitter

Plan: `knowledge-base/project/plans/2026-10-30-fix-inngest-luks-key-probe-emitter-plan.md`
Issue: #11527 (Ref, never Closes — the merge-triggered apply is part of remediation)

## Phase 1 — Predicate + comment + guard + docs (one commit)

- [x] 1.1 Restructure `local.inngest_luks_key_probe_fail_sql` in `apps/web-platform/infra/betterstack-logs-alerts.tf` to the emitter-OR form: shared `dt BETWEEN` filter + position-1 `SOLEUR_INNGEST_LUKS_KEY_PROBE` anchor; leg A `SYSLOG_IDENTIFIER='inngest-cutover-flip'` AND `token=fail_` on `message`; OR leg B `shipper='cloud-init-phone-home'` AND `stage='luks-key-probe'` AND (`detail = ''` OR `token=fail_` on `detail`); OR inside the parenthesized group (`AND` binds tighter than `OR`). If the D2 ruling prefers strict shared conjuncts, drop the `detail = '' OR` fragment and hoist the token check to a shared `message` conjunct. Extend the local's comment block: emitter-identity sentence (row set pinned to the probe's two real emitters; `{`-prefix exclusion incidental per #8846), residual edges (jq-failure payload uncounted; `detail=''` arm semantics; self-attested `dt` unmeasured; `value` ≤ 2 inflation under `higher_than 0`); scaffold the dated `LIVE-PROBED` entry. `terraform fmt -check`.
- [x] 1.2 Extend `apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh`: header bullet; `FAIL_CANON` rewritten to the new canonical; derived needles `MUT_TAG` (`readonly LOG_TAG=` call-form in `$FLIP`), `MUT_STAGE` (bounded first arg of the phone-home call form in `$FLIP`), `MUT_SHIPPER` (`shipper:"…"` in `cloud-init-inngest.yml`), all FATAL-on-empty; +6 presence rows (leg-A emitter eq, leg-B shipper eq, leg-B stage eq, leg-B detail `token=fail_`, leg-B `detail=''` disjunct, OR-arm structure); exactly-1 cardinality pin on the `luks-key-probe` emit site; retarget the two `token=fail_` mutation needles to the `message`-extracted form; +7 `mutate_red` rows (drop leg-A conjunct; flip literal to `'doppler'`; drop shipper; drop stage; flip stage; delete `OR (…)` arm; neutralize `detail=''` disjunct); floors `PRESENCE_ROWS=30`→`36`, `MUT_ROWS=30`→`37`, `_floor`→`73`, `MUT_SKIP` floor→`36`.
- [x] 1.3 Run `bash apps/web-platform/test/infra/inngest-luks-key-probe-alert.test.sh` → `73 passed, 0 failed`; run `bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` and `bash apps/web-platform/infra/betterstack-alert-structure.test.sh` → both stay green.
- [x] 1.4 Update `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` standing-alarms row (~:26-34): dual-channel pin note + `.shipper`/`.stage` readback + empty-`.detail` decode.
- [x] 1.5 Amend `knowledge-base/engineering/architecture/diagrams/model.c4` `inngest -> betterstack` edge (~:792): the key-probe sentence notes the alert reads BOTH emitters since #11527; `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-code-syntax.test.ts test/c4-render.test.ts` passes (regenerate `model.likec4.json` if the render path requires it, as the sibling PR did).

## Phase 2 — Enumerate emitters + live-probe (pre-merge)

- [x] 2.1 Run controls A–E via `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh` raw-SQL over hot `remote()` UNION `s3Cluster` archive (48 h, `dt` window, `SELECT dt, raw` in BOTH arms): A marker-anchored emitter census (GROUP BY `SYSLOG_IDENTIFIER`/`shipper`/`stage`); B `shipper='cloud-init-phone-home'` stage census + `stage='luks-key-probe'` count; C full predicate `= 0`; D emitter-OR coverage delta vs the bare marker-anchor count; E synthetic-raw leg evaluations `1/0/1/0/1/0/0` (journald fail / journald ok / phone-home fail / phone-home ok / identity-pinned detail-absent / jq-failure shape / doppler-shaped forgery). Record all numbers + window into the `.tf` `LIVE-PROBED` comment.

## Phase 3 — Apply through the normal path (merge-triggered)

- [ ] 3.1 PR body first line states the merge-mutates-production disclosure; body carries `Ref #11527`.
- [ ] 3.2 After merge, read the `apply-web-platform-infra.yml` run on the merge SHA: `logtail_exploration.inngest_luks_key_probe_fail` updated in place (both resources already in the `-target=` allowlist, :655-656 — no workflow edit).
- [ ] 3.3 `gh issue close 11527 -c "<apply run + Phase-2 numbers>"` once the apply lands; `scheduled-terraform-drift.yml` is the continuous backstop. Optional: re-run control C post-apply.

## Verification / gates

- [x] V1 At verification, distinguish the pre-existing `deploy-script-tests` red on `main` (unrelated `vinngest` tag/pin drift, `cloud-init-inngest-bootstrap.test.sh` AC6, owned by another in-flight worktree) from this diff's results.
- [x] V2 `decision-challenges.md` D2/D3 carry obtained CTO rulings (or `pending - assumed:` until the parent pipeline obtains them — spawn forbidden at this level); if D2 resolves to strict shared conjuncts, drop the `detail=''` arm before Phase 1 lands.
- [x] V3 The two `## Operator Holds` in the plan stand verbatim — no delegation or gate discharges them; do not implement #11528 or #11266.
