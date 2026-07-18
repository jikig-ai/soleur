---
feature: feat-one-shot-6438-web-probe-unit-start-fix
lane: cross-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-18-fix-web-probe-unit-start-doppler-auth-plan.md
issues: "Ref #6438 #6548 (NOT Closes — soak-gated)"
---

# Tasks — web-1 probe unit-start fix (doppler-auth + vector Source 4 delivery)

Derived from the finalized plan. **Phase ordering is load-bearing** (observability ships/verifies
before the fix is validated; learning 2026-07-16 §2). **Ref #6438 #6548**, never `Closes`.

## Phase 0 — Preconditions (verify against live repo, no guessing)
- [x] 0.1 Confirmed no new C4 element/edge — delivery/auth fix on already-modeled elements (ADR-123
      §C4 already covers the probe edges from 14075d1b); no `diagrams/*.c4` edit.
- [x] 0.2 Confirmed `terraform_data.journald_persistent` IS on the workflow `-target` list
      (apply-web-platform-infra.yml:685) — folded vector delivery into it, no new -target for vector.
- [x] 0.3 Confirmed `@@HOST_NAME@@` render path: two sentinels in vector.toml (`.host_name` ×2);
      remote-exec renders via `sed 's|@@HOST_NAME@@|${hcloud_server.web["web-1"].name}|g'` (=
      soleur-web-platform, the same value cloud-init passes as SOLEUR_HOST_NAME) → /etc/vector/vector.toml.
- [x] 0.4 Cadence reconciled — canary rate-limited to ~1/h (not per-fire); arm-deadline reconciliation
      is a post-merge/arm-time concern (Phase 3).

## Phase 1 — Token (folded) + vector delivery + positive-control canary
- [x] 1.1 Added `doppler_service_token.web_probes` (`config=prd, access=read`) in new
      `web-probe-read-token.tf`. Self-provisioning; NOT `var.doppler_token`.
- [x] 1.2 Appended `DOPPLER_TOKEN=` (+ `DOPPLER_ENABLE_VERSION_CHECK=false`, fleet convention) to each
      of the 3 `*_install` env-file writes (server.tf); hashed `nonsensitive(sha256(...key))` into each
      `triggers_replace`.
- [x] 1.3 Folded `vector.toml` delivery + agent reload into `terraform_data.journald_persistent`
      (IaC remote-exec); hashed `file(vector.toml)` into its `triggers_replace`; positive assertions
      (probe tags present + agent active) fail the apply loud.
- [x] 1.4 Added rate-limited (~1/h, /run marker) `SOLEUR_PROBE_CANARY` row on healthy zot-probe runs
      (one probe proves the shared Source-4 path; a dead agent kills all tags). Chose a low-freq
      distinct line over unconditional `SOLEUR_PROBE_VERBOSE=1` (60s-cadence quota).

## Phase 2 — Unit-start fix
- [x] 2.1 (RED→GREEN) Drift-guards folded into web-{zot-consumer,git-data}-probe + web-private-nic-guard
      + journald-config `.test.sh` (all already registered in `infra-validation.yml`). RED verified,
      then GREEN. Comment-robust negatives (strip `#` lines).
- [x] 2.2 (GREEN) Added `Environment=HOME=/root` to the 3 `.service` files; root-run; fail-loud.
- [x] 2.3 ADR-123 amended (web-1 root-doppler-unit auth contract; #6459 fresh-host token-bake blocker).
- [ ] 2.4 (post-merge, automated) The merge apply re-fires the `*_install` provisioners (token + unit)
      and folds vector delivery; self-pull telemetry: units succeed (no `Failed with result
      exit-code`), classification + positive-control canary rows reach Source 4, a real beat lands.

## Phase 3 — Arm the heartbeats
- [ ] 3.1 The arm step runs on the merge PUSH (same job) — it arms GREEN if units already beat, else
      fail-loud rolls back (safe). Deliberate retry once telemetry confirms beats:
      `gh workflow run apply-web-platform-infra.yml --ref main -f reason='arm L3 probes after
      unit-start fix (#6438/#6548)'`; watch all 3 monitors reach `status=up`.

## Phase 4 — Soak handoff (do NOT touch)
- [ ] 4.1 Confirm `scripts/followthroughs/l3-probe-armed-6438.sh` enrollment intact (directive +
      `follow-through` label on #6438; `BETTERSTACK_API_TOKEN` wired). It closes #6438/#6548 on its
      own (earliest 2026-07-25). This PR does NOT close them.

## Testing / Verification
- [x] T1 Drift-guard tests green (4 shell `.test.sh`, all registered in `infra-validation.yml`);
      `terraform fmt -check` + `terraform validate` pass.
- [x] T2 SpecFlow ran in the deepen-plan phase (spec-flow-analyzer); infra change is a delivery/auth
      fix within the reviewed ADR-123 design (no new user flow).
- [ ] T3 `discoverability_test` returns probe-tagged rows, NO ssh — post-merge/arm-time (Source 4 goes
      live on web-1 on the merge-apply).
- [ ] T4 PR body uses `Ref #6438 #6548` (set at /ship); no `plugins/` touched → no `semver:` label.

## Lifecycle
- [ ] L1 Compound learning: "web-1 has no root-doppler-auth systemd precedent; new doppler units need
      HOME=/root + a dedicated prd token file; vector.toml has no running-host delivery path."
- [ ] L2 `/ship` renders decision-challenges.md (§1 two-PR split) → operator `action-required` issue.
- [ ] L3 Evaluate `/ship` Phase 5.5 Incident-PIR gate (no user impact; learning likely suffices).
