# Tasks — feat-one-shot-11526-vector-down-fallback

Plan: `knowledge-base/project/plans/2026-10-29-fix-inngest-luks-wrong-volume-vector-down-plan.md`
Issue: #11526 (Ref, never Closes — the merge-triggered apply is part of remediation)

## Phase 1 — Predicate + comments + guard + docs (one commit)

- [ ] 1.1 Restructure `local.inngest_luks_wrong_volume_sql` in `apps/web-platform/infra/betterstack-logs-alerts.tf` to the dual-path OR (leg-A conjuncts unchanged inside the parenthesized group; leg-B arm pinning `shipper='cloud-init-phone-home'` + `stage='inngest-server-probe-vector-down'` + `detail`-anchored `host_role` + negated `detail` devid); `time BETWEEN` wraps both legs (`AND` binds tighter than `OR` — keep the OR inside the group). Run `terraform fmt -check` on the file.
- [ ] 1.2 Rewrite the local's "three residual edges" comment block: vector-down bullet → CLOSED note citing #11526; append new residual edges (detail-absent fail-loud; self-attested `dt` unmeasured per #9784; leg-B literals load-bearing). Keep `#8516`, `treat_as_zero`, `inngest_server_probe` tokens in the alert's comment region (sibling guard `inngest-server-probe-heartbeat.test.sh` pins them). Add the dated `LIVE-PROBED` entry scaffold (Phase 2 fills counts).
- [ ] 1.3 Extend `apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh`: header bullet; `MUT_STAGE` derivation by grepping `inngest-server-probe-vector-down` from `apps/web-platform/infra/inngest-bootstrap.sh` (FATAL if empty); +5 presence rows (shipper eq, stage eq via `${MUT_STAGE}`, detail host_role, detail negated devid, OR-arm structure); retarget the two devid mutation needles to the `message`-extracted form and the emitter-conjunct mutations to the un-ANDed first-line shape; +5 `mutate_red` rows (drop shipper, drop stage, flip stage literal, detail devid `=0`→`>0`, delete `OR (…)` arm); floors `29→39` / `MUT_SKIP 15→20`.
- [ ] 1.4 Run `bash apps/web-platform/test/infra/inngest-luks-wrong-volume-alert.test.sh` → `39 passed, 0 failed`; run `bash apps/web-platform/infra/inngest-server-probe-heartbeat.test.sh` → green (citation region preserved).
- [ ] 1.5 Update `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` standing-alarms row (~:46-59): dual-channel admission note + `.shipper`/`.stage` readback recipe.
- [ ] 1.6 Append a dated amendment to `knowledge-base/engineering/architecture/decisions/ADR-218-native-better-stack-logs-alerts-are-terraform-managed-via-the-logtail-provider.md`: dual-channel predicate convention (alerts enumerate every channel a dual-channel emitter can take; envelope-field identity on the markerless channel) — the pattern #11527 applies and #11528 pins.
- [ ] 1.7 Amend `knowledge-base/engineering/architecture/diagrams/model.c4` `inngest -> betterstack` edge (~:792) to name the curl-direct phone-home channel into source 2457081; run `bun test apps/web-platform/test/c4-code-syntax.test.ts apps/web-platform/test/c4-render.test.ts`.

## Phase 2 — Live-probe the new predicate (pre-merge)

- [ ] 2.1 Run controls A–E via `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh` raw-SQL over hot `remote()` UNION `s3Cluster` archive (48h, `dt` window): A leg-A population `>0`; B `shipper='cloud-init-phone-home'` GROUP BY `stage` census + `stage='inngest-server-probe-vector-down'` count; C full predicate w/ live alias `=0`; D wrong-alias needle `=` A + leg-B rows; E synthetic-raw leg-B evaluations `1`/`0`/`1` (wrong devid / live alias / detail-absent). Record all numbers + window into the `.tf` `LIVE-PROBED` comment.

## Phase 3 — Apply through the normal path (merge-triggered)

- [ ] 3.1 PR body first line states the merge-mutates-production disclosure; body carries `Ref #11526`.
- [ ] 3.2 After merge, read the `apply-web-platform-infra.yml` run on the merge SHA: `logtail_exploration.inngest_luks_wrong_volume` updated in place (both resources already in the `-target=` allowlist, :653-654 — no workflow edit).
- [ ] 3.3 `gh issue close 11526 -c "<apply run + Phase-2 numbers>"` once the apply lands; `scheduled-terraform-drift.yml` is the continuous backstop. Optional: re-run control C post-apply.

## Verification / gates

- [ ] V1 At verification, distinguish the pre-existing `deploy-script-tests` red on `main` (unrelated `vinngest` tag/pin drift, `cloud-init-inngest-bootstrap.test.sh` AC6, owned by another in-flight worktree) from this diff's results.
- [ ] V2 `decision-challenges.md` T1 carries the obtained CTO ruling (or `pending - assumed:` until the parent pipeline obtains it — spawn forbidden at this level); if the ruling is REJECT, collapse to the comment-only arm and drop 1.1/1.3/Phase 2.
- [ ] V3 The two `## Operator Holds` in the plan stand verbatim — no delegation or gate discharges them; do not implement #11527 or #11528.
