---
title: Fix runtime-plugin deploy gap to the Concierge host
type: bug-fix
classification: ops-remediation
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
issue: TBD (production-incident remediation — file at ship time)
branch: feat-one-shot-plugin-deploy-gap
created: 2026-07-02
cto_ruling: "Option A (extend path filters). Option B disqualified (image-vs-mount silent regression)."
---

# 🐛 Fix runtime-plugin deploy gap to the Concierge host

## Overview

Runtime-affecting changes to the Soleur plugin (skills/hooks/agents/scripts/commands the
Concierge agent executes) never reliably reach the production Concierge host. They only land
by coincidence when an *unrelated* `apps/web-platform/**` change happens to trigger a
web-platform image rebuild + deploy. This is a production-incident remediation: a
`worktree-manager.sh` stale-git-lock self-heal fix merged the evening of 2026-07-01 but
Concierge kept hitting the original failure the next day, because the host mount still ran
the pre-fix script; the fix only reached the host via a coincidental `apps/` deploy the
following morning.

**Fix (per CTO ruling, Option A):** add the runtime-plugin path subset to the web-platform
release pipeline's change-detection filters so a runtime-plugin merge rebuilds+deploys the
image. The mount re-seeds from that freshly built image, so image and host mount stay
consistent **by construction**. No new host-write infra, no new seed logic.

**Complexity:** Small (hours). Two path-filter edits + inner change-detection multi-pathspec
support + drift-guard tests + one ADR.

## Root Cause (verified)

The Concierge runs plugin components from `/mnt/data/plugins/soleur`, a read-only bind-mount:

- `apps/web-platform/server/workspace.ts` symlinks each workspace's `./plugins/soleur` to
  `/app/shared/plugins/soleur`; `apps/web-platform/server/plugin-path.ts:17`
  `SOLEUR_PLUGIN_PATH_DEFAULT = "/app/shared/plugins/soleur"`.
- The host mount is seeded from the web-platform Docker image's baked plugin tree:
  `reusable-release.yml` "Vendor plugin into build context" copies `plugins/soleur` →
  `apps/web-platform/_plugin-vendored`; `apps/web-platform/Dockerfile:156`
  `COPY _plugin-vendored /opt/soleur/plugin`.
- On **every** deploy, `apps/web-platform/infra/ci-deploy.sh` (~L665-690) re-seeds the mount
  from the freshly pulled image: `docker create` → `find "$PLUGIN_MOUNT_DIR" -mindepth 1
  -delete` → `docker cp <ephemeral>:/opt/soleur/plugin/. "$PLUGIN_MOUNT_DIR/"` → writes the
  `.seed-complete` sentinel. `PLUGIN_MOUNT_DIR` defaults to `/mnt/data/plugins/soleur`.
- The **only** workflow that rebuilds+deploys that image is
  `.github/workflows/web-platform-release.yml`, which triggers on `push` to main with
  `paths: ['apps/web-platform/**']` (+ manual `workflow_dispatch`).

So a plugins-only merge rebuilds no image, runs no deploy, and never re-seeds the mount.
`version-bump-and-release.yml` (fires on `plugins/soleur/**`) only cuts a plugin git tag +
GitHub Release; `deploy-docs.yml` (fires on `plugins/soleur/{docs,agents,skills,commands}/**`)
only publishes the GitHub Pages docs site. **Neither touches the Concierge host mount.**

## Research Reconciliation — Spec vs. Codebase

No `spec.md` exists for this branch; the feature description carried a fully-verified root
cause. All cited artifacts were confirmed against the working tree during planning:

| Claim in feature description | Reality (verified) | Plan response |
|---|---|---|
| Seed re-run on every deploy in `ci-deploy.sh:668-695` | Confirmed at ~L665-690 (`find -delete` + `docker cp` + `.seed-complete`) | Unchanged by this plan (Option A reuses it) |
| `web-platform-release.yml` triggers on `paths: ['apps/web-platform/**']` | Confirmed (L4-6) | Add runtime-plugin globs |
| Adding outer `paths:` is the whole fix | **FALSE — landmine.** `reusable-release.yml`'s `check_changed` (L84-104) re-gates on `git diff -- "$PATH_FILTER"` (`apps/web-platform/`). Every build/deploy step is `if: check_changed == 'true'`. A plugins-only diff → `changed=false` → workflow runs but builds/deploys NOTHING (green no-op). | Plan MUST widen BOTH the outer `paths:` AND the inner change-detection. This is the load-bearing edit. |
| Proven-incident file `worktree-manager.sh` | Lives at `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — under `skills/`, NOT top-level `scripts/` | `skills/**` is the single most load-bearing glob |

## User-Brand Impact

**If this lands broken, the user experiences:** the Concierge agent keeps executing stale
plugin skills/hooks after a fix merges — the exact 2026-07-01 incident recurs. A specific
failure mode: a shipped `worktree-manager.sh` self-heal never runs on the host, so Concierge
repeatedly fails to create/reset worktrees until a coincidental `apps/web-platform` deploy.

**If this leaks, the user's workflow is exposed via:** no data-leak surface. The risk is
*availability/correctness* — a runtime fix silently not deploying — not confidentiality.

**Brand-survival threshold:** single-user incident. (Concierge is the single-operator
product surface; a silently-undeployed runtime fix is a per-user outage.) `requires_cpo_signoff:
true` — CPO sign-off required at plan time before `/work`; the technical approach was ruled by
the CTO agent during planning (Option A). `user-impact-reviewer` runs at review time.

## CTO Ruling — Option A vs Option B (mandated)

**RULING: Option A — extend the change-detection path filters. Option B is disqualified.**

- **Why B is disqualified (not merely costlier):** the plugin tree **is baked into the image**
  (`Dockerfile:156`), and every deploy's re-seed does `find -delete` + `docker cp` from that
  image. Under B, a host-direct re-seed pushes plugin vN to the mount, then the next unrelated
  `apps/web-platform` deploy re-seeds from an image that still bakes v(N-1) → **wipes vN and
  restores the stale tree.** That is *worse than status quo*: the fix appears to work, then
  silently reverts on a coincidental deploy — reproducing the incident signature. Any B
  mitigation ("also rebuild the image") collapses B back into A. The
  `apply-deploy-pipeline-fix.yml` precedent does **not** license B: it pushes host-resident
  files that are **not baked into any image**, so it has no image-vs-host drift surface — the
  precise property B lacks.
- **Consistency vs cost, explicit:** A costs one gated image build + prod cutover
  (await-ci → migrate → verify-doppler-secrets → deploy → live-verify) per runtime-plugin PR —
  minutes of CI + one gated container swap, reusing the existing seed path with zero new infra.
  A's consistency is total (image and mount derive from the same build every time). B is cheaper
  per-merge but introduces a new silent-regression failure mode + new host-write ops surface.
  At the single-user-incident threshold, trading CI-minutes for a self-healing invariant is
  correct.

## Architecture Decision (ADR/C4)

### ADR
Create an ADR via `/soleur:architecture create 'Runtime-plugin changes deploy via image
rebuild, not host-direct re-seed'` (in-scope task of THIS plan, not a follow-up). It must record:
`## Decision` — runtime-plugin surface is part of the web-platform deployable; a runtime-plugin
merge triggers a full image rebuild + gated deploy that re-seeds the mount. `## Alternatives
Considered` — Option B (host-direct re-seed), rejected for the image-vs-mount silent-regression
hazard above. Cross-reference ADR-030 (multi-tenant deploy substrate) and the incident. Rationale
for authoring now: without the ADR a future engineer re-proposes B as the "cheaper" option.

### C4 views
**No C4 impact.** Read all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`). The change is
a CI trigger *condition* on the already-modeled CI→image→host-deploy path — it introduces no new
external human actor, no new external system/vendor, no new container/data-store, and no new
actor↔surface access relationship. Elements already modeled and checked: the Soleur Plugin
system (`model.c4:66`), skill/plugin loader + "Plugin Discovery" (`model.c4:57-58`), the
`claude -> skillloader "Loads plugin"` edge (`model.c4:273`), the deploy/rolling-deploy infra
(`model.c4:192`), and GitHub CI/CD ("Source control, CI/CD, issue tracking, and releases",
`model.c4:212`) with its plugin/container/component views (`views.c4:28-50`). C4 does not model
workflow path-filters, so a trigger-condition widening is below its granularity. The decision is
captured in the ADR, not the C4.

## Infrastructure (IaC)

**No new infrastructure.** Option A edits only GitHub Actions workflow YAML + a Bun test. It
adds no server, service, cron, secret, DNS record, vendor account, or host-write path. The host
re-seed (`ci-deploy.sh`) is unchanged and already provisioned. Phase 2.8 IaC routing gate: skip
(pure CI-config change against already-provisioned surfaces). Explicitly NOT Option B (which
*would* have introduced host-write infra).

## Implementation Phases

Phases are ordered by dependency: the contract-changing inner-gate edit (Phase 2) must precede
the outer-trigger edit conceptually, but both land in one atomic PR. Tests are written RED first.

### Phase 1 — Define the runtime-plugin trigger set (allowlist)
Canonical runtime globs (allowlist — no glob-then-negate; naturally excludes `docs/**` + `test/**`):

```
plugins/soleur/skills/**
plugins/soleur/hooks/**
plugins/soleur/agents/**
plugins/soleur/commands/**
plugins/soleur/scripts/**
plugins/soleur/.claude-plugin/**
```

Verification items for /work Phase 0:
- Confirm `git ls-files | grep -E` matches ≥1 real file for each glob.
- Confirm the host runtime does NOT read the plugin-root `plugins/soleur/AGENTS.md` at execution
  time; if it does, add `plugins/soleur/AGENTS.md` to the set. (Default: excluded.)
- Confirm `docs/**` and `test/**` are absent from the set.

### Phase 2 — Widen the INNER change-detection (load-bearing; the no-op landmine)
`reusable-release.yml` `check_changed` (L84-104) runs `git diff --name-only HEAD~1 --
"$PATH_FILTER"` with a single quoted pathspec. It must recognize the runtime-plugin paths for the
`web-platform` component WITHOUT changing the `plugin` component caller's semantics.

Chosen mechanism (deepen-plan to finalize exact shape): add an OPTIONAL `extra_path_filter` input
(newline- or space-separated pathspec list) that is OR'd into the change check. `git diff --
<pathspecA> <pathspecB>` accepts multiple pathspecs, so expand the list to multiple unquoted args
(NOT a single space-joined quoted string — that becomes one pathspec-with-a-space and silently
never matches). `web-platform-release.yml` passes the 6 runtime globs via `extra_path_filter`;
`version-bump-and-release.yml` leaves it empty (unchanged behavior).
- `path_filter` for web-platform stays `apps/web-platform/`.
- Preserve `force_run` short-circuit and the `HEAD~1` squash-merge assumption (call it out).

### Phase 3 — Widen the OUTER trigger
`web-platform-release.yml` `on.push.paths`: add the 6 runtime globs alongside
`apps/web-platform/**`. This decides whether the workflow *starts*; Phase 2 decides whether it
*builds*. Both are required.

### Phase 4 — Drift-guard tests
Add/extend a Bun test (mirror `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts`
patterns) asserting:
- The runtime globs are present in BOTH the outer `web-platform-release.yml` `push.paths` AND the
  inner `reusable-release.yml`/`web-platform-release.yml` change-detection input, so a future
  edit cannot silently drop `skills/**` and regress to the incident.
- `docs/**` and `test/**` are NOT in the set (the "does NOT fire on docs-only" assertion).
- Per learning `2026-06-11-cross-file-drift-guards-extract-every-operand-by-shape.md`: extract
  the glob set by shape from each file and compare, never hardcode one side.

### Phase 5 — Change-detection unit proof
Add a test proving a **plugins-runtime-only** diff yields `changed=true` (reaches the docker
build) and a **docs-only / test-only** plugin diff yields `changed=false` for the web-platform
component. Prefer testing the extracted `check_changed` logic against a synthesized diff (mirror
`apps/web-platform/infra/ci-deploy.test.sh` style) over a live workflow run —
`workflow_dispatch` cannot verify a not-yet-on-default-branch change.

### Phase 6 — ADR
Author the ADR (see Architecture Decision section).

## Files to Edit
- `.github/workflows/web-platform-release.yml` — outer `on.push.paths` (Phase 3) + pass
  `extra_path_filter` to the reusable workflow (Phase 2).
- `.github/workflows/reusable-release.yml` — new optional `extra_path_filter` input + widen
  `check_changed` to multi-pathspec (Phase 2, L84-104).
- `plugins/soleur/test/*` — drift-guard test + change-detection proof (Phases 4-5). New file name
  chosen at /work time (e.g. `plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts`);
  verify the runner (`bun test`) + discovery glob before pinning the path.

## Files to Create
- `knowledge-base/engineering/architecture/decisions/ADR-0NN-runtime-plugin-deploys-via-image-rebuild.md`
  (number assigned by `/soleur:architecture`; latest is ADR-079).
- (Optional) new drift-guard test file per Phase 4/5.

## Files NOT to touch
- `apps/web-platform/infra/ci-deploy.sh` seed logic — correct as-is; Option A reuses it.
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` stale-lock sweep — already
  merged and correct; out of scope.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `web-platform-release.yml` `on.push.paths` contains all 6 runtime globs + `apps/web-platform/**`
  (grep-verifiable).
- [ ] `reusable-release.yml` `check_changed` recognizes the runtime globs for the web-platform
  component via `extra_path_filter`; the `plugin` component caller is byte-unchanged in behavior.
- [ ] The inner `git diff` uses multiple pathspec ARGS (not one space-joined quoted string).
- [ ] Drift-guard test: runtime globs present in BOTH outer and inner filters; `docs/**` +
  `test/**` absent. Test extracts each side by shape.
- [ ] Change-detection proof: a synthesized `plugins/soleur/skills/…` diff → `changed=true`;
  a `plugins/soleur/docs/…`-only diff → `changed=false` (web-platform component).
- [ ] `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` still green (no
  coupling regression).
- [ ] ADR authored and committed in this PR (status may be `adopting`).
- [ ] PR body uses `Ref #N` (ops-remediation: closure is post-deploy, not at merge).

### Post-merge (operator/automated)
- [ ] After merge, `web-platform-release.yml` fires and its `deploy` job re-seeds the mount from
  the new image (verify via the existing `/hooks/deploy-status` read + `app.soleur.ai/health`
  `build_sha` == merge SHA — automatable, no SSH).
- [ ] Follow-through soak: no recurrence of "runtime fix merged but host stale" over the next
  runtime-plugin merge (enroll per Observability §soak). Close the tracking issue only after the
  first post-fix runtime-plugin merge is observed to deploy.

## Test Scenarios
1. Plugins-runtime-only PR (`skills/git-worktree/scripts/worktree-manager.sh`) → workflow starts
   AND builds AND deploys AND re-seeds. (The exact 2026-07-01 incident.)
2. Docs-only plugin PR (`plugins/soleur/docs/**`) → web-platform release does NOT build/deploy;
   `deploy-docs.yml` still handles GH Pages.
3. Test-only plugin PR (`plugins/soleur/test/**`) → web-platform release does NOT build/deploy.
4. Mixed PR (`apps/web-platform/**` + `plugins/soleur/skills/**`) → single workflow run, single
   build+deploy (no double-deploy).
5. `apps/web-platform`-only PR → unchanged behavior (regression check).

## Observability

```yaml
liveness_signal:
  what: "web-platform-release deploy job succeeds + /hooks/deploy-status reports exit_code=0 for the new tag; app.soleur.ai/health build_sha == merge SHA"
  cadence: "per runtime-plugin merge to main"
  alert_target: "existing release Slack channel (notify-gated job) + GitHub Actions run status"
  configured_in: ".github/workflows/web-platform-release.yml (deploy, live-verify, notify-gated jobs)"
error_reporting:
  destination: "GitHub Actions run (red job) + Slack via notify-gated; live-verify emits a gate=live-verify Sentry event"
  fail_loud: true
failure_modes:
  - mode: "Inner change-detection stays false for a plugins-only diff (the no-op landmine)"
    detection: "Phase 5 unit test (synthesized diff → changed=true); post-merge deploy-status build_sha != merge SHA"
    alert_route: "CI red (test) pre-merge; deploy verify step ::error:: post-merge"
  - mode: "A runtime glob silently dropped from one filter (drift)"
    detection: "Phase 4 drift-guard test (both filters compared by shape)"
    alert_route: "CI red (test)"
  - mode: "docs-only PR wrongly triggers a full image build (cost regression)"
    detection: "Phase 5 test (docs-only diff → changed=false)"
    alert_route: "CI red (test)"
logs:
  where: "GitHub Actions run logs; host /hooks/deploy-status JSON; app.soleur.ai/health"
  retention: "GitHub Actions default; deploy-status ephemeral state file on host"
discoverability_test:
  command: "gh run list --workflow=web-platform-release.yml --branch main --limit 3 --json conclusion,headSha AND curl -s https://app.soleur.ai/health | jq .build_sha"
  expected_output: "latest run conclusion=success; health build_sha == the runtime-plugin merge SHA"
```

### Soak follow-through enrollment
Enroll a follow-through so the tracking issue auto-closes after the first post-fix runtime-plugin
merge is observed to deploy (script under `scripts/followthroughs/<short-name>-<issue>.sh`, exit 0
when `health.build_sha` matches a runtime-plugin merge SHA; `<!-- soleur:followthrough … -->`
directive + `follow-through` label; wire any new `secrets=` into
`.github/workflows/scheduled-followthrough-sweeper.yml`). Finalize in deepen-plan/work.

## Domain Review

**Domains relevant:** Engineering (only).

### Engineering (CTO)
**Status:** reviewed
**Assessment:** CTO agent gave a binding ruling during planning — Option A, Option B disqualified
(image-vs-mount silent-regression hazard). Independently confirmed the double-gate no-op landmine
(inner `reusable-release.yml` `check_changed`). Prescribed the exact allowlist globs, flagged
the drift-guard-test coupling, version-tag semantics (`wg-never-bump-version-files-in-feature`
interaction), and the double-pipeline (host image + GH Pages) for docs+runtime PRs. Recommended
the ADR.

No Product/UI surface (no files under `components/**`, `app/**/page.tsx`, `app/**/layout.tsx`) →
Product/UX Gate: NONE. No regulated-data surface → GDPR gate: skip. No new infra → IaC gate: skip.

## Open Code-Review Overlap
Two open `code-review` issues mention adjacent files, neither overlapping this change:
- #3220 (postmerge verification of trigger-bearing migrations, `web-platform-release.yml`) —
  **Acknowledge:** different concern (migration verification), not the trigger-path widening.
- #3216 (dpf-regex canary-bundle review, resolved inline) — **Acknowledge:** historical, resolved.

## Risks & Mitigations / Sharp Edges
- **The double-gate no-op (highest risk).** Adding only the outer `paths:` ships green and does
  nothing. Gate the PR on the Phase 5 test (plugins-runtime diff → `changed=true` → reaches
  docker build).
- **Multi-pathspec shell shape.** `git diff -- "$A $B"` (single quoted, space-joined) is ONE
  pathspec-with-a-space and never matches. Expand to multiple unquoted args / word-split a
  newline list. Add the change-detection proof so this can't regress.
- **Drift-guard coupling.** `ship-deploy-pipeline-fix-gate.test.ts` couples several trigger
  surfaces — do not disturb it; add a SEPARATE guard for the new outer+inner filter pair, and
  extract every operand by shape (learning `2026-06-11-cross-file-drift-guards-extract-every-operand-by-shape.md`).
- **Version-tag semantics.** Runtime-plugin merges now cut a `web-v*` bump + image tag (correct —
  vendored image content genuinely changed). Note the interaction with
  `wg-never-bump-version-files-in-feature` (that gate is about editing version files in the
  feature branch, not about CI cutting a tag — no conflict, but state it).
- **Double pipeline, not double deploy.** A PR touching runtime + `docs/**` fires
  `web-platform-release` (host image) AND `deploy-docs.yml` (GH Pages) — independent surfaces,
  not a conflict. A mixed `apps/web-platform` + `plugins/skills` PR is one workflow run / one
  build.
- **Recover proven shapes from git history** (learning
  `2026-06-02-reintroduce-removed-ci-mechanism-from-git-history.md`): when editing the reusable
  workflow's change-detection, prefer adapting the proven `check_changed` block over re-deriving.
- **The empty `## User-Brand Impact` / `TBD` failure:** this section is filled; do not blank it —
  deepen-plan Phase 4.6 halts on an empty threshold.

## PIR / Learning
This is an ops-remediation for a recurring silent-non-deploy. A PIR/learning is warranted
capturing: the image-baked-plugin bind-mount seeding model, the two-gate change-detection (outer
`on.push.paths` + inner `reusable-release.yml check_changed`), and why host-direct re-seed (Option
B) silently regresses. Author at ship time (`/soleur:incident` or a learning under
`knowledge-base/project/learnings/bug-fixes/`).
