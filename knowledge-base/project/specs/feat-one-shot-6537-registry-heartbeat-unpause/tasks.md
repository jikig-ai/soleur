---
title: 'Tasks — arm the registry liveness heartbeat, then unpause'
plan: knowledge-base/project/plans/2026-07-16-fix-inert-monitor-invariant-registry-heartbeat-plan.md
issue: 6537
lane: cross-domain
brand_survival_threshold: aggregate pattern
status: pending
---

# Tasks — #6537

Derived from the finalized (post-7-agent-review) plan. **Read the plan's `## Premise Validation`
and `## The cadence constraint` before starting** — two premises that look obvious are false, and
they invert the work.

**Do NOT unpause `soleur-registry-prd` until Phase 4.3 measures a real ping.** Unpausing an unfed
heartbeat is a guaranteed false alarm (#6210).

## Phase 0 — Preconditions (verify; do not assume)

- [x] 0.1 Re-pull `/api/v2/heartbeats`; confirm `registry_prd` still `paused`; capture its **id**
      (`470365` today) for the arming `PATCH`.
      `doppler run -p soleur -c prd_terraform -- bash -c 'curl -fsS -m 30 -H "Authorization: Bearer $BETTERSTACK_API_TOKEN" https://uptime.betterstack.com/api/v2/heartbeats' | jq '.data[] | select(.attributes.name=="soleur-registry-prd") | {id, status, paused: .attributes.paused}'`
- [x] 0.2 `git grep -c "ZOT_HEARTBEAT_URL" -- ':!knowledge-base' | cut -d: -f2` → expect **1**
      (definition only). **If a feeder landed meanwhile, STOP and re-plan** — the premise inverts.
- [x] 0.3 Re-confirm `betteruptime_heartbeat.registry_prd` is still in `OPERATOR_APPLIED_EXCLUSIONS`
      (`plugins/soleur/test/terraform-target-parity.test.ts:584`). **If it is now targeted, STOP** —
      the "no resource change" constraint relaxes and widening `period` becomes available.
- [x] 0.4 `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts` → green baseline.
- [x] 0.5 Identify the registry cloud-init assertion suite:
      `git grep -l cloud-init-registry -- '*test*'`. **If none exists, Phase 1.1's RED tests land in
      the parity test — do NOT invent a new suite.**
- [x] 0.6 Re-verify the next free ADR ordinal against a freshly-fetched `origin/main`
      (`git fetch origin main`; highest today: ADR-115 → provisional **ADR-117**).
- [x] 0.7 Confirm the GHCR fallback is still warm (the `## Downtime & Cutover` precondition):
      ADR-096 status is `Adopting` AND `grep -c 'app_ghcr_fallback' apps/web-platform/infra/cloud-init.yml` ≥ 1.
      **If Phase-5 has retired GHCR, STOP** — the replace is no longer latency-only.

## Phase 1 — The feeder (RED first)

- [x] 1.1 **RED:** write T1–T4 against the Phase 0.5 suite, before any script exists:
      T1 zot answers on `10.0.1.30:5000/v2/` → ping emitted;
      **T2** zot dead, host alive, disk <85% → **NO ping**;
      **T3** private NIC absent, `localhost:5000` still answers → **NO ping** (*the most important
      test in this PR*); T4 zot slow >10s → no ping, no hang.
      Fixtures are **synthesized** (stub `curl`); **no live host in the test path**.
- [x] 1.2 Add `zot-liveness-heartbeat.sh` to `apps/web-platform/infra/cloud-init-registry.yml`,
      mirroring `zot-disk-heartbeat.sh:148-157`. Guard on the host's **own private IP**:
      `curl -fsS -m 10 -o /dev/null "http://${private_ip}:5000/v2/"` — **NEVER `localhost`**
      (zot binds `0.0.0.0`; see `:324-328`). Ping only inside the guard.
- [x] 1.3 Add the systemd `.service` + `.timer` (`OnBootSec=30s`, `OnUnitActiveSec=60s`), mirroring
      `inngest-bootstrap.sh:196-207`; enable in `runcmd`. **NOT `/etc/cron.d`** — cron's 60s floor
      leaves no margin against the 90s deadline.
- [x] 1.4 **No `doppler run` wrapper** — the URL is baked, so there is no empty-variable failure
      mode (#4116).
- [x] 1.5 GREEN: T1–T4 pass.

## Phase 2 — Wire the URL through `user_data`

- [x] 2.1 `zot-registry.tf` — add `liveness_heartbeat_url = betteruptime_heartbeat.registry_prd.url`
      to the `templatefile` vars, mirroring `disk_heartbeat_url` (`:310`).
- [x] 2.2 **Assert the negative:** no change to `period`, `grace`, or `paused`; no resource deleted.
      `git diff origin/main -- apps/web-platform/infra/zot-registry.tf | grep -cE '^[-+]\s*(period|grace|paused)\s*='` → **0**.
      *(`registry_prd` is an `OPERATOR_APPLIED_EXCLUSION` — a resource edit could never apply.)*

## Phase 3 — Executable arming (the manifest)

- [x] 3.1 Extract `MANIFEST` + `Arming` + `ManifestEntry` (`heartbeat-reprovision-parity.test.ts:57-79`)
      into `plugins/soleur/lib/heartbeat-manifest.ts`. Move the `:30-43` header semantics with it.
- [x] 3.2 Add the `feeder` field:
      `{kind:"cron"|"timer"; evidence:{file,pattern}} | {kind:"none"; url_secret: string|null; tracking_issue: number}`.
- [x] 3.3 **RED:** forward assertion — `evidence.file` exists **AND** `grep -F -c <pattern> <file>` ≥ 1.
      **Two distinct messages** — `grep -F` exits **2** on a missing file vs **1** on no-match.
- [x] 3.4 **RED:** inverse assertion — for `kind:"none"` with a non-null `url_secret`, that secret has
      **zero consumers** repo-wide (outside `.tf` / `knowledge-base/`). *This is the forcing
      function: when #5274 PR C ships a `GIT_DATA_HEARTBEAT_URL` consumer, CI goes red.*
- [x] 3.5 **RED:** `kind:"none"` ⇒ `tracking_issue` is a positive integer.
- [x] 3.6 Populate (see the plan's Phase 3 table). `registry_prd` → `{kind:"timer", evidence:{file:"apps/web-platform/infra/cloud-init-registry.yml", pattern:"zot-liveness-heartbeat.timer"}}`.
- [x] 3.7 **`registry_prd`'s `arming` flips `web-host-cron` → `dedicated-host-boot`** (it is now armed
      by the registry's own cloud-init) and its `exempt_reason` is deleted. This makes ADR-103's
      `replace_target` requirement fire — satisfied by the existing `registry-host-replace` choice.
      **This is intended, not a workaround.**
- [x] 3.8 GREEN: `bun test plugins/soleur/test/heartbeat-reprovision-parity.test.ts`.

## Phase 4 — Ship, reprovision, verify, arm (post-merge, automated)

- [ ] 4.1 Merge. *(The `user_data` change reaches the host only on a fresh boot — cloud-init is
      per-instance. Nothing here needs the per-PR apply to do anything.)*
- [ ] 4.2 `gh workflow run apply-web-platform-infra.yml -f apply_target=registry-host-replace -f reason="arm the zot liveness heartbeat (#6537)"`
      — the sanctioned non-SSH reprovision path. The OCI store volume is **preserved** by the
      destroy-guard.
- [ ] 4.3 **Measure a ping before arming** (ask #1). Confirm a beat landed within ~2 timer intervals
      of boot. **If no ping lands, STOP — do not arm.** Diagnose with
      `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h --grep SOLEUR_ZOT_DISK`
      (the co-located disk self-report proves whether the host's timers run at all).
- [ ] 4.4 **Arm:** `PATCH /api/v2/heartbeats/<id> {"paused": false}` with `BETTERSTACK_API_TOKEN`
      (`::add-mask::` it; never echo).
- [ ] 4.5 Bounded poll → `status == "up"` and `paused == false` within 60 + 30s + margin.
      **This is the literal answer to #6537.**
- [ ] 4.6 Informational: `--grep ghcr-fallback --since 1h` — a fallback event during the replace
      window is **expected and correct**, not a defect.

## Phase 5 — Correct the false comments

- [x] 5.1 `zot-registry.tf:406-413` — rewrite: the probe is **UNBUILT**; the liveness layer is now
      the on-host self-ping; `paused = true` in source is deliberate (`ignore_changes=[paused]`;
      live is armed by API). **Delete the dangling by-hand unpause sentence** — that instruction,
      with no owner and no forcing function, is the proximate cause of this bug.
- [x] 5.2 `zot-registry.tf:435-436` — the **second** false forward reference
      (*"so the (Phase-3/soak) web-host probe cron can read it"*), same class, same resource.
- [x] 5.3 `alerts-github-webhook.tf:50-54` — delete the false *"the webhook route deliberately
      pings"* claim. **Note:** it attaches only to `github_webhook_sig_failures`;
      `github_api_429_sustained` has **no** corresponding comment.
- [x] 5.4 `git-data.tf:271-274` — the TODO is already honest; add the ADR-117 pointer only.

## Phase 6 — ADR + C4

- [x] 6.1 Create `ADR-117-executable-heartbeat-arming.md`, `status: accepted`. Decision rests on the
      **general** property (source ≠ live), **not** on `ignore_changes=[paused]` — the heartbeat is
      *also* untargeted, so a source unpause is a no-op regardless. Alternatives Considered must
      record: unpause-without-feeder (rejected, #6210), prose `arming` (rejected, false for months),
      forward-only grep (rejected), nightly live-reconcile (deferred). Record that the invariant
      admits **two** legal resolutions: feed it, or **delete** it.
- [x] 6.2 Amend `ADR-096` — its #6285 note (*"that layer does not exist yet"*) is now **stale**;
      record the on-host self-ping + private-IP rationale, and that the **consumer-perspective**
      probe remains #6438 §1. Fix the stale citation `zot-registry.tf:359` → `:441`.
- [x] 6.3 Amend `ADR-103` — record `feeder` as the executable upgrade to its prose `arming` axis.
- [x] 6.4 `model.c4` ×3 — extend `zotRegistry -> betterstack` (`:420`) with the liveness ping;
      correct the false git-data paging claims at `:264` and `:450`. **Anchor edits on grep-able
      tokens, not line numbers** (`model.c4:437` states the repo's own rule).
- [x] 6.5 `bun test` / vitest: `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 7 — Close the loop

- [x] 7.1 Comment on **#6438** with this plan's evidence, and add the finding it did not have:
      **its §1 arming blocker option (a) is unsound** — dropping `ignore_changes=[paused]` still
      leaves the heartbeat untargeted, so a source unpause remains a CI no-op. Its remaining scope
      is the **consumer-perspective** probe only.
- [x] 7.2 File tracking issues: `git_data_prd` feeder (note its **unexplained live absence** — it has
      **no** `count` gate, so this is drift, not tier-gating → delegate to
      `scheduled-terraform-drift.yml`); **one** issue for both webhook heartbeats (shared re-eval
      trigger); nightly live-reconcile as a step in `scheduled-terraform-drift.yml`.
      **Verify every label exists** (`gh label list --limit 200`) before `gh issue create`.
- [x] 7.3 Put the issue numbers into the manifest's `tracking_issue` fields; re-run Phase 3.8.
- [x] 7.4 `bash scripts/test-all.sh` → green (catches orphan suites the targeted runs miss).
- [ ] 7.5 PR body: `Closes #6537`, `Ref #6438`. Include the plan's **Founder-Facing Summary** and
      the live heartbeat table as evidence (`hr-no-dashboard-eyeball-pull-data-yourself`).
- [ ] 7.6 `gh issue close 6537` only **after** Phase 4.5 passes.

## Notes for the implementer

- **The single highest-risk slip is `localhost` vs the private IP.** T3 exists solely to catch it.
- **Do not "fix" a red parity test by relaxing `arming`.** If `registry_prd`'s `dedicated-host-boot`
  class demands a `replace_target`, that is the guard working.
- **Do not add `-target=` lines** for the heartbeat to make a resource change apply. That breaks the
  CTO's `OPERATOR_APPLIED_EXCLUSIONS` ruling. If you find yourself wanting to, re-read
  `## The cadence constraint`.
- Typecheck for `apps/web-platform`: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
  (**not** `npm run -w …` — the repo root declares no `workspaces`).
