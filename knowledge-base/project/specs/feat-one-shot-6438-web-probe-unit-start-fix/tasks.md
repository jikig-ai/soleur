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
- [ ] 0.2 Confirm `terraform_data.journald_persistent` (server.tf:668) is on the workflow SSH
      `-target` list (apply-web-platform-infra.yml ~:681-694) — if yes, fold vector delivery into it
      (no new -target); if no, use a new resource + append it to the -target list + Files to Edit.
- [ ] 0.3 Confirm `vector.toml` render path (re-invoke `/usr/local/bin/soleur-vector-install`, which
      already renders `@@HOST_NAME@@`).
- [ ] 0.4 Reconcile the Observability period figures (180/360/180) with the live arm deadlines
      (230/470/230) — nic-guard 5-min cadence gives ~1 fire inside 470s.

## Phase 1 — Token (folded) + vector delivery + positive-control canary
- [ ] 1.1 Add `doppler_service_token.web_probes` (`config=prd, access=read`) in a token `.tf`
      (web-arm-write-token.tf pattern). Self-provisioning; NOT `var.doppler_token`.
- [ ] 1.2 In each of the 3 `*_install` remote-execs (server.tf:463/506/549), append `DOPPLER_TOKEN=`
      (from `doppler_service_token.web_probes.key`) to the existing `printf > /etc/default/web-<probe>`
      line; hash the token key into each installer's `triggers_replace`. (No new file, no new
      EnvironmentFile, no ordering race.)
- [ ] 1.3 Fold `vector.toml` delivery + reload into `terraform_data.journald_persistent`
      (or a new -targeted resource); hash `file(vector.toml)` into its `triggers_replace`.
- [ ] 1.4 Add the positive-control healthy canary row to Source 4 (luks-#6604 pattern) — /work picks
      the cadence-appropriate mechanism (low-freq `[probe] ok` line vs `SOLEUR_PROBE_VERBOSE=1`;
      weigh the 60s quota cost).

## Phase 2 — Unit-start fix
- [ ] 2.1 (RED) Drift-guard test: each probe `.service` has `Environment=HOME=/root`; each
      `/etc/default/web-<probe>` write includes `DOPPLER_TOKEN=`; no `webhook-deploy` source, no
      `User=deploy` w/o `PrivateTmp=true`, no `/tmp/.doppler`; a `vector.toml` delivery/reload path with
      `triggers_replace` hashing `file(vector.toml)`; if a NEW vector resource, it is in the -target
      list. Fold into the existing infra drift-guard (no new test file); register in `infra-validation.yml`.
- [ ] 2.2 (GREEN) Edit the 3 `.service` files: add ONLY `Environment=HOME=/root`; keep root-run;
      **fail loud, no degrade guard**.
- [ ] 2.3 ADR-123 amendment note (web-1 root-doppler-unit auth contract — dedicated read token in the
      per-probe env files; #6459 fresh-host token-bake blocker recorded).
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
- [ ] T1 Drift-guard tests green (`tsc` + shell `.test.sh`); registered in `infra-validation.yml`.
- [ ] T2 SpecFlow analysis on the infra change (constitution: infra requires SpecFlow).
- [ ] T3 `discoverability_test` (Observability schema) returns probe-tagged rows, NO ssh.
- [ ] T4 PR body uses `Ref #6438 #6548`; `semver:` label set if plugins/ touched (it is not).

## Lifecycle
- [ ] L1 Compound learning: "web-1 has no root-doppler-auth systemd precedent; new doppler units need
      HOME=/root + a dedicated prd token file; vector.toml has no running-host delivery path."
- [ ] L2 `/ship` renders decision-challenges.md (§1 two-PR split) → operator `action-required` issue.
- [ ] L3 Evaluate `/ship` Phase 5.5 Incident-PIR gate (no user impact; learning likely suffices).
