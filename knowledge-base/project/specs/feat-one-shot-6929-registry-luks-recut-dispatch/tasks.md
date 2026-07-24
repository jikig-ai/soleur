---
feature: feat-one-shot-6929-registry-luks-recut-dispatch
issue: 6929
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-24-feat-registry-luks-recut-dispatch-plan.md
---

# Tasks — guarded `registry-luks-recut` `workflow_dispatch`

Derived from the **post-review (v2)** plan. Design-decision IDs (D1-D15) and acceptance-criteria IDs (AC1-AC23) refer to that document. Taste/User-Challenge splits are in `decision-challenges.md` (DC-1 … DC-6) — read them before starting, since DC-2 (a `.tf` scope addition) and DC-5 (is a recut actually scheduled?) may change scope.

## Phase 0 — Preconditions (premise-falsifying reads only; record each answer for AC22)

- [ ] 0.1 `apps/web-platform/infra/zot-registry.tf`: confirm no `prevent_destroy`, no `create_before_destroy`, fixed name literals (`soleur-registry`, `soleur-registry-store`), and `hcloud_server.registry`'s `depends_on` includes `doppler_secret.registry_luks_key`.
- [ ] 0.1b Re-verify the from-empty `-target` closure listed in the plan's §Gate design against `zot-registry.tf` + `network.tf`. If any member is inside the allow-set or named-live set, add an explicit `birth_shape` counter instead of relying on `out_of_scope`.
- [ ] 0.2 **D10 positive control** — prove `betterstack-query.sh --grep ghcr-fallback --grep local-cache` returns rows on a known-degraded historical window. If it cannot be shown to go red, D10 ships as a `::warning::` rather than a gate. Record which.
- [ ] 0.3 **Disposability premise (CPO C3)** — is every tag currently in the live zot store guaranteed present in GHCR? A negative answer makes the recut data loss and invalidates D12 + the §User-Brand Impact framing; stop and re-derive both.
- [ ] 0.4 Re-read the `blkid` discriminator in `cloud-init-registry.yml` (anchor `#6895: guest-side LUKS-at-rest mount + resize of the zot store volume`): the three arms, the empty-key guard, and the 60 s device wait.
- [ ] 0.5 **Runner reality** — confirm `bun test plugins/soleur/test/terraform-target-parity.test.ts` collects from **this worktree** given root `bunfig.toml` `pathIgnorePatterns = [".worktrees/**", …]`. If not, AC13 runs from the main checkout; record it.
- [ ] 0.6 Cite Hetzner's documented `uniqueness_error` behaviour (D3's "`create_before_destroy` is impossible" premise).
- [ ] 0.7 `bash scripts/regenerate-c4-model.sh` on the unmodified tree → confirm a no-op diff.

## Phase 1 — RED → GREEN (gate lib + heartbeat poller)

- [ ] 1.1 Write `tests/scripts/test-registry-luks-recut-gate.sh`: ~22 core cases, the five resume-arm cases (both-bare-create; volume no-op + server create; volume+server no-op + attachment create; probe-not-absent ⇒ ABORT; zero-creates ⇒ ABORT), and the cross-gate divergence block. **Every ABORT case asserts its named counter in stdout, not `rc` alone** (AC4). Run it — it MUST fail. Record the RED output.
- [ ] 1.2 Write `tests/scripts/lib/registry-luks-recut-gate.sh` (9 counters; two arms selected by the plan's own delete-set; per-change id-pin; fail-closed on a non-numeric `$expected`). Header must carry the delta-vs-`registry_region_migrate_gate.sh` paragraph, the #6497 do-not-widen rule, the firewall update-in-place note, and the **countable** `SOLEUR-DEBT` marker from the plan.
- [ ] 1.3 Write `scripts/registry-heartbeat-poll.sh` + its own suite (D11): heartbeat id from tfstate not a name filter; `BETTERSTACK_API_TOKEN` read + masked; wait ≥ 90 s or observe a non-`up` sample before the `up` window opens; poll ≤ 8 min; `paused` is a distinct failure; fail-closed on an unreadable token.
- [ ] 1.4 All suites green; `shellcheck` clean on all three new shell files.
- [ ] 1.5 One-time mutation spot-check on `volume_provisioned`, `volume_id_mismatch`, `luks_key_touched`, `out_of_scope` — each must turn ≥1 case red, asserting the `return 1` halt. Revert each.

## Phase 2 — Workflow job

- [ ] 2.1 Add input `expected_registry_store_volume_id`; add `[registry-luks-recut]` / `[workspaces-luks-recut]` tags to both id-pin descriptions and `confirm`'s; add the input-budget comment above `inputs:`. **No new boolean inputs.**
- [ ] 2.2 Fix the `confirm` input's comment block (it asserts the `environment:` gate is the sole authorization — false for the registry target).
- [ ] 2.3 Add `registry-luks-recut` to `apply_target.options`; convert `description:` to a block scalar and shorten it to a runbook pointer.
- [ ] 2.4 Add the `registry_luks_recut` job after `registry_region_migrate`: `timeout-minutes: 30`, no `environment:`, no job-level `concurrency:`. Steps in the plan's order — confirm/id validation → D10 → keygen → creds → init → plan + D4 probe + destroy-guard → `stock_preflight_gate` → **pre-apply** web-1/workspaces zero-touch assert → apply + completeness backstops → D11 poller → best-effort disk heartbeat → summary emitting the **new volume id** + the empty-store/paging sentence.
- [ ] 2.5 Correct the `host_creates` HALT `hcloud_server.registry` line per D14 (the current claim is already false).
- [ ] 2.6 `actionlint` the workflow; `bash -c` the extracted `run:` snippets (never `bash -n` on the `.yml`).

## Phase 3 — Registration + parity

- [ ] 3.1 `scripts/test-all.sh`: one `run_suite "tests/scripts/registry-luks-recut-gate" …` beside the `workspaces-luks-recut-gate` entry, with the sibling rationale comment.
- [ ] 3.2 `plugins/soleur/test/terraform-target-parity.test.ts` — five additions: strip-list + pin; the new `describe` block (6 targets, 3 sorted `-replace`s, exclusions, `not.toContain("resource_changes")`); allow-set⇄`-target` parity across all three registry jobs; job⇄gate-lib pairing; step-order index assertion.
- [ ] 3.3 Sweep: `git grep -ln "registry_region_migrate\|workspaces_luks_recut" -- tests/ scripts/ plugins/ .github/` and update every artifact that enumerates dispatch jobs or target sets.

## Phase 4 — Terraform + docs

- [ ] 4.1 **DC-2 gate:** add `lifecycle { prevent_destroy = true }` to `hcloud_volume.workspaces` in `apps/web-platform/infra/server.tf` (D13). `terraform validate`; confirm no dispatch path's plan changes.
- [ ] 4.2 Amend ADR-096's 2026-07-24 amendment: shipped vehicle + confirm token + id-pin provenance, and record the empty-store/paging window, the corrected HALT invariant, the two ordering windows, and the `registry_region_migrate` residual. Sweep the `lint-infra-ignore` comment body too. FOOTGUN paragraph byte-unchanged.
- [ ] 4.3 File the DC-3 tracking issue (the weaker sibling gate) and the CPO-R2 issue (ledger `at_rest.mechanism` vs. its downstream renderers).
- [ ] 4.4 Write `knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md` covering **every row** of the plan's §Operator flow: the bounded one-command Hetzner id lookup, each abort's exit, the D11 `registry-host-replace`-vs-full-recut decision rule, the empty-store force command, and the do-not-use warning **scoped to the plaintext case**. No SSH.
- [ ] 4.5 Correct the posture-audit row (drop `**plaintext ext4**` and the `format = "ext4"` fragment; content anchor instead of `:407`) and the `model.c4` registry description — both phrased **code-declared / live-pending**, never live-verified. Then `bash scripts/regenerate-c4-model.sh`.

## Phase 5 — Verification

- [ ] 5.1 `bash tests/scripts/test-registry-luks-recut-gate.sh` → green.
- [ ] 5.2 The heartbeat-poller suite → green.
- [ ] 5.3 `bash scripts/test-all.sh scripts` → green, **and** the new suite's name appears in the output.
- [ ] 5.4 `bun test plugins/soleur/test/terraform-target-parity.test.ts` → green (per the Phase 0.5 answer).
- [ ] 5.5 `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` → green.
- [ ] 5.6 `python3 scripts/lint-encryption-posture.py --repo-sweep` → exit 0.
- [ ] 5.7 `actionlint` + `shellcheck` + `terraform validate` clean.
- [ ] 5.8 Full `bash scripts/test-all.sh` → exit 0.
- [ ] 5.9 PR body: `Closes #6929` plus the AC22 record (from-empty closure re-verification, D10 positive-control result, disposability answer, worktree-runner answer, name-uniqueness citation).

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
