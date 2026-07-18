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
- [ ] 0.1 Read `diagrams/{model.c4,views.c4,spec.c4}` — confirm no new external actor/system/store/
      access-relationship is introduced (bug fix on already-modeled elements → no C4 edit).
- [ ] 0.2 Confirm the `doppler_token`/write-token value available in `server.tf` scope for the token
      file, OR decide to mint a read-scoped `doppler_service_token` (web-arm-write-token.tf pattern).
- [ ] 0.3 Confirm `vector.toml` render path (`@@HOST_NAME@@` via `soleur-host-bootstrap.sh:342`, or
      re-invoke `/usr/local/bin/soleur-vector-install`) for the new provisioner.
- [ ] 0.4 Confirm the arm workflow's `-target` list scope for a new `terraform_data` resource
      (apply-web-platform-infra.yml ~:393).

## Phase 1 — Observability delivery + token file (SHIP FIRST)
- [ ] 1.1 Add `terraform_data.web_vector_reload_install` in `server.tf`: SSH to web-1; deliver
      `vector.toml` → `/etc/vector/vector.toml` (rendered) + reload the vector agent; write
      `/etc/default/web-probes` (root:root, 600, `DOPPLER_TOKEN=<prd-read token>`).
      `triggers_replace = sha256(join(...,[file(vector.toml), host_name, token ref]))`. Idempotent.
- [ ] 1.2 (RED→GREEN) Drift-guard test: assert `server.tf` has a resource delivering `vector.toml`
      + writing `/etc/default/web-probes` root:root 600; `triggers_replace` hashes `vector.toml`.
- [ ] 1.3 (post-merge, automated) Apply Phase 1 (`-target` new provisioner), then self-pull telemetry:
      `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep web-zot-consumer-probe --grep 'Doppler Error'`.
      **Evidence checkpoint:** probe-tagged stderr now ships AND shows the predicted `$HOME`/auth error.

## Phase 2 — Unit-start fix (verified against the Phase-1 reading)
- [ ] 2.1 (RED) Drift-guard test asserting each probe `.service` has `Environment=HOME=/root` +
      `EnvironmentFile=/etc/default/web-probes`, does NOT source `webhook-deploy`, does NOT set
      `User=deploy` w/o `PrivateTmp=true`, and references no `/tmp/.doppler`. Register in
      `infra-validation.yml`. Test file `.test.sh` in `apps/web-platform/test/`.
- [ ] 2.2 (GREEN) Edit the 3 `.service` files: add `Environment=HOME=/root` +
      `EnvironmentFile=/etc/default/web-probes`; keep root-run; **fail loud, no degrade guard**.
- [ ] 2.3 ADR-123 amendment note (web-1 root-doppler-unit auth contract).
- [ ] 2.4 (post-merge, automated) Apply Phase 2 — the `.service` edits re-fire the `*_install`
      provisioners (`triggers_replace` hashes the `.service`) → re-deliver + daemon-reload + enable.
      Self-pull telemetry: units succeed (no `Failed with result exit-code`), a real beat lands.

## Phase 3 — Arm the heartbeats
- [ ] 3.1 (post-merge) `gh workflow run apply-web-platform-infra.yml --ref main -f reason='arm L3
      probes after unit-start fix (#6438/#6548)'`; watch the "Arm web-host probe heartbeats" step
      report all 3 monitors `status=up` (deadlines 230/470/230s).

## Phase 4 — Soak handoff (do NOT touch)
- [ ] 4.1 Confirm `scripts/followthroughs/l3-probe-armed-6438.sh` enrollment intact (directive +
      `follow-through` label on #6438; `BETTERSTACK_API_TOKEN` wired). It closes #6438/#6548 on its
      own (earliest 2026-07-25). This PR does NOT close them.

## Testing / Verification
- [ ] T1 Drift-guard tests green (`tsc` + shell `.test.sh`); registered in `infra-validation.yml`.
- [ ] T2 SpecFlow analysis on the infra change (constitution: infra requires SpecFlow).
- [ ] T3 `discoverability_test` (Observability schema) returns probe-tagged rows, NO ssh.
- [ ] T4 PR body uses `Ref #6438 #6548`; `semver:` label set if plugins/ touched (it is not).

## Lifecycle
- [ ] L1 Compound learning: "web-1 has no root-doppler-auth systemd precedent; new doppler units need
      HOME=/root + a dedicated prd token file; vector.toml has no running-host delivery path."
- [ ] L2 `/ship` renders decision-challenges.md (§1 two-PR split) → operator `action-required` issue.
- [ ] L3 Evaluate `/ship` Phase 5.5 Incident-PIR gate (no user impact; learning likely suffices).
