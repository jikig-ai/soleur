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
cto_ruling: "Option A (image rebuild+deploy, NOT host-direct re-seed). Option B disqualified (image-vs-mount silent regression). Deepen-plan refined the sub-mechanism: denylist filter, reuse path_filter, fail-loud inner gate."
---

# 🐛 Fix runtime-plugin deploy gap to the Concierge host

## Enhancement Summary

**Deepened on:** 2026-07-02
**Reviewers:** CTO (A-vs-B ruling), spec-flow-analyzer, architecture-strategist, code-simplicity-reviewer
**Sections enhanced:** mechanism (Phase 1-3), tests, Risks, ADR, Observability

### Key improvements from deepen-plan
1. **Reuse the existing `path_filter` (drop the quotes) instead of a new `extra_path_filter` input** — simpler AND avoids the empty-quoted-pathspec match-all hazard (spec-flow G2; simplicity + architecture converged).
2. **Inner gate uses git directory-PREFIX pathspecs with NO `**`, under `set -f`** — an unquoted `plugins/soleur/skills/**` is filesystem-glob-expanded by bash and silently misses newly-added files (spec-flow G1 CRITICAL, simplicity). Outer `on.push.paths` keeps Actions `**` glob syntax — the two dialects are deliberately different.
3. **Fail-loud inner gate:** add `set -euo pipefail` + explicit git rc check. The current `CHANGED=$(git diff … | head -1)` swallows every error into `changed=false` → a green no-op that reproduces the incident (spec-flow G3 CRITICAL).
4. **Flip allowlist → DENYLIST** (`plugins/soleur/**` minus `docs/**`, `test/**`). The incident IS "a runtime file class silently never deploys"; an allowlist fails in exactly that direction for future runtime surfaces, and it already has a concrete hole: `plugins/soleur/CLAUDE.md` (`@AGENTS.md`) + `AGENTS.md` are runtime instruction files an allowlist excludes (spec-flow G4/G5). A denylist is failure-mode-complete and covers them by default — no fragile "is CLAUDE.md runtime-loaded?" determination needed.
5. **Behavioral drift-guard test** (synthesized diff → verdict), not cross-dialect string comparison — a string-equality test would force the buggy `**` inner form or fail the correct one (spec-flow G6).

### New considerations discovered
- A runtime-plugin merge now fires THREE workflows (web-platform-release, version-bump-and-release plugin tag, deploy-docs) and cuts TWO tags (`web-v*` + `v*`) → two GitHub Releases + two Slack/email notifications (architecture P1). Documented in Risks.
- The full prod deploy pipeline (`migrate` + `verify-doppler-secrets` under `DOPPLER_TOKEN_PRD`) now runs on plugin-only merges — idempotent, but can fail-closed-block a runtime fix on unrelated prod drift (architecture P1). Documented in Risks.
- Corrected two inaccurate premises: NO tag collision (prefixes `v`/`web-v` are regex-isolated, #4082); concurrency group is per-component (`release-web-platform` vs `release-plugin`), NOT shared.

## Overview

Runtime-affecting changes to the Soleur plugin (skills/hooks/agents/scripts/commands/instructions the
Concierge agent executes) never reliably reach the production Concierge host. They only land by
coincidence when an *unrelated* `apps/web-platform/**` change triggers a web-platform image rebuild +
deploy. Production-incident remediation: a `worktree-manager.sh` stale-git-lock self-heal fix merged the
evening of 2026-07-01 but Concierge kept hitting the original failure the next day (host mount ran the
pre-fix script); the fix only reached the host via a coincidental `apps/` deploy the next morning.

**Fix (CTO ruling, Option A):** make a runtime-plugin merge rebuild+deploy the web-platform image. The
mount re-seeds from that freshly built image, so image and host mount stay consistent **by
construction**. No new host-write infra, no new seed logic — a widening of the pipeline's two
change-detection filters.

## Root Cause (verified)

The Concierge runs plugin components from `/mnt/data/plugins/soleur`, a read-only bind-mount:
- `apps/web-platform/server/workspace.ts` symlinks each workspace's `./plugins/soleur` →
  `/app/shared/plugins/soleur`; `apps/web-platform/server/plugin-path.ts:17`
  `SOLEUR_PLUGIN_PATH_DEFAULT = "/app/shared/plugins/soleur"`.
- Seeded from the image's baked tree: `reusable-release.yml` "Vendor plugin into build context" copies
  `plugins/soleur` → `apps/web-platform/_plugin-vendored`; `apps/web-platform/Dockerfile:156`
  `COPY _plugin-vendored /opt/soleur/plugin`. The vendor step bakes the WHOLE tree (docs/test included);
  the trigger set only governs WHEN to rebuild, not WHAT is baked.
- Re-seeded on **every** deploy: `apps/web-platform/infra/ci-deploy.sh` (~L665-690) — `docker create` →
  `find "$PLUGIN_MOUNT_DIR" -mindepth 1 -delete` → `docker cp <ephemeral>:/opt/soleur/plugin/.
  "$PLUGIN_MOUNT_DIR/"` → `.seed-complete` sentinel. `PLUGIN_MOUNT_DIR` defaults to
  `/mnt/data/plugins/soleur`.
- The **only** workflow that rebuilds+deploys is `.github/workflows/web-platform-release.yml`, triggered
  on `push` to main with `paths: ['apps/web-platform/**']` (+ manual `workflow_dispatch`).

A plugins-only merge rebuilds no image, runs no deploy, never re-seeds. `version-bump-and-release.yml`
(fires on `plugins/soleur/**`) only cuts a plugin git tag + GitHub Release; `deploy-docs.yml` (fires on
`plugins/soleur/{docs,agents,skills,commands}/**`) only publishes GitHub Pages. **Neither touches the
Concierge host mount.**

## Research Reconciliation — Spec vs. Codebase

No `spec.md` for this branch (lane defaults to `cross-domain`, fail-closed). All cited artifacts verified
during planning + deepen:

| Claim | Reality (verified) | Plan response |
|---|---|---|
| Seed re-run every deploy, `ci-deploy.sh:668-695` | Confirmed ~L665-690 | Unchanged (Option A reuses it) |
| `web-platform-release.yml` triggers on `apps/web-platform/**` | Confirmed L6 | Widen (denylist) |
| Adding outer `paths:` is the whole fix | **FALSE — landmine.** `reusable-release.yml:94` `check_changed` re-gates on `git diff --name-only HEAD~1 -- "$PATH_FILTER"` (`apps/web-platform/`); every build/deploy step is `if: check_changed=='true'`. Plugins-only diff → `changed=false` → green no-op. | Widen BOTH gates |
| Inner gate can reuse the outer `**` globs | **FALSE — shell-glob landmine (spec-flow G1).** Unquoted `plugins/soleur/skills/**` is bash-glob-expanded before git sees it → silently misses new files. | Inner uses `plugins/soleur/` prefix pathspecs, NO `**`, `set -f` |
| Allowlist is drift-free (initial CTO lean) | **Has a hole.** `plugins/soleur/CLAUDE.md`(`@AGENTS.md`)+`AGENTS.md` are runtime instruction files an allowlist excludes; future runtime dirs silently missed. | Flip to denylist (fail-safe) |
| Proven-incident file `worktree-manager.sh` | `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` | Covered by `plugins/soleur/**` denylist |
| Shared inner gate risks the plugin caller | `version-bump-and-release.yml:28` passes single-token `path_filter: "plugins/soleur/"` — word-splits to itself, byte-unchanged | Reuse path_filter safely |
| No tag collision / shared concurrency (my earlier premise) | **Corrected:** prefixes `v`/`web-v` are regex-isolated (`reusable-release.yml:205-216`, #4082); concurrency group is `release-${component}` (per-component). | Note in Risks (lock traffic, not collision) |

## User-Brand Impact

**If this lands broken, the user experiences:** the Concierge keeps executing stale plugin
skills/hooks/instructions after a fix merges — the 2026-07-01 incident recurs (e.g. a shipped
`worktree-manager.sh` self-heal never runs on the host).

**If this leaks, the user's workflow is exposed via:** no data-leak surface. Risk is
*availability/correctness* (a runtime fix silently not deploying), not confidentiality.

**Brand-survival threshold:** single-user incident. `requires_cpo_signoff: true` — CPO sign-off required
at plan time before `/work`; technical approach ruled by the CTO agent (Option A). `user-impact-reviewer`
runs at review time.

## CTO Ruling — Option A vs Option B (mandated)

**RULING: Option A — rebuild+deploy the image on runtime-plugin merges. Option B disqualified.**

- **Why B is disqualified (not merely costlier):** the plugin tree **is baked into the image**
  (`Dockerfile:156`) and every deploy re-seeds via `find -delete` + `docker cp` from that image. Under B,
  a host-direct re-seed pushes plugin vN to the mount, then the next unrelated `apps/web-platform` deploy
  re-seeds from an image that still bakes v(N-1) → **wipes vN, restores the stale tree.** *Worse than
  status quo*: the fix appears to work, then silently reverts on a coincidental deploy — reproducing the
  incident signature. Any B mitigation ("also rebuild the image") collapses B back into A. The
  `apply-deploy-pipeline-fix.yml` precedent does NOT license B: it pushes host-resident files **not baked
  into any image**, so it has no image-vs-host drift surface — the property B lacks.
- **Consistency vs cost, explicit:** A costs one gated image build + prod cutover per runtime-plugin PR
  (minutes of CI + one gated container swap), reusing the existing seed path with zero new infra. A's
  consistency is total. B is cheaper per-merge but adds a silent-regression failure mode + new host-write
  ops surface. At single-user-incident threshold, trading CI-minutes for a self-healing invariant is
  correct.
- **Sub-mechanism (deepen-plan refinement of Option A):** the CTO's Option A description leaned allowlist
  ("no glob-then-negate"). Deepen-plan's three reviewers surfaced concrete allowlist holes (runtime
  CLAUDE.md/AGENTS.md excluded; future runtime dirs silently missed) and converged on a **denylist** as
  failure-mode-complete for a silent-non-deploy remediation. This refines the sub-mechanism WITHIN
  Option A (still image-rebuild, not host-reseed); flagged for CTO/operator awareness at sign-off.

## Chosen Mechanism (denylist, fail-loud)

Two gates, both widened to "everything under `plugins/soleur/` except non-runtime `docs/` and `test/`":

**Gate 1 — outer `on.push.paths`** (`web-platform-release.yml`, GitHub-Actions glob syntax, supports `!`):
```yaml
on:
  push:
    branches: [main]
    paths:
      - 'apps/web-platform/**'
      - 'plugins/soleur/**'
      - '!plugins/soleur/docs/**'
      - '!plugins/soleur/test/**'
```

**Gate 2 — inner `check_changed`** (`reusable-release.yml`, git-pathspec syntax, NO `**`). Reuse
`path_filter` (drop the quotes so it word-splits to multiple pathspecs) under `set -euo pipefail` + `set -f`
(disable bash globbing) + explicit git rc check (fail loud, never default-to-skip):
```bash
set -euo pipefail
if [ "$FORCE_RUN" = "true" ]; then echo "changed=true" >> "$GITHUB_OUTPUT"; exit 0; fi
set -f                                   # no filesystem globbing of pathspec tokens
# shellcheck disable=SC2086  # word-split PATH_FILTER into multiple git pathspecs (intentional)
if ! CHANGED=$(git diff --name-only HEAD~1 -- $PATH_FILTER | head -1); then
  echo "::error::check_changed: git diff failed for PATH_FILTER='$PATH_FILTER'"; exit 1
fi
set +f
[ -z "$CHANGED" ] && echo "changed=false" >> "$GITHUB_OUTPUT" || echo "changed=true" >> "$GITHUB_OUTPUT"
```
The web-platform caller widens its existing input; the plugin caller is untouched:
```yaml
# web-platform-release.yml
path_filter: "apps/web-platform/ plugins/soleur/ :(exclude)plugins/soleur/docs/ :(exclude)plugins/soleur/test/"
# version-bump-and-release.yml — UNCHANGED (single token; word-splits to itself)
path_filter: "plugins/soleur/"
```
`:(exclude)…` git pathspec magic drops docs/test from an otherwise-matching `plugins/soleur/` set. No new
input, no OR-branch. Update the `path_filter` input `description:` in `reusable-release.yml` to document the
new "space-separated pathspec list; no embedded spaces; globbing disabled" contract.

**Denylist fail-direction:** rare non-runtime root-file edits (`README.md`, `LICENSE`, `NOTICE`) will
over-trigger a build — an accepted, harmless over-deploy. The incident class (silent under-deploy) is what
we refuse to reintroduce.

**Recommended hardening (evaluate at /work):** `HEAD~1` assumes squash-merge. A non-squash or multi-commit
push could diff the wrong range → `changed=false` → recurrence (spec-flow G7). Prefer the push-range
compare `${{ github.event.before }}...${{ github.sha }}` (the `live-verify` job already uses the GH compare
API for this at `web-platform-release.yml:744`, sidestepping `fetch-depth`). If retained, keep `HEAD~1`
called out as a squash-only invariant. Do NOT alter the shared plugin caller's diff basis without
re-verifying its behavior.

## Architecture Decision (ADR/C4)

### ADR
Create a new ADR via `/soleur:architecture create 'Runtime-plugin changes deploy via image rebuild, not
host-direct re-seed'` (in-scope task). `## Decision` — the runtime-plugin surface is part of the
web-platform deployable; a runtime-plugin merge triggers a full image rebuild + gated deploy that re-seeds
the mount. `## Alternatives Considered` — Option B (host-direct re-seed), rejected for the image-vs-mount
silent-regression hazard; allowlist filter, rejected for the silent-under-deploy fail-direction. New ADR
(not an amend): this is a trigger-topology decision, distinct from ADR-030's tenant credential-aggregation
concern. Cite prior ADRs by **filename/slug** (the decisions dir has duplicate ADR-030 numbers). Cross-ref
`ADR-030-multi-tenant-deploy-substrate.md`, `ADR-064-live-production-verification-harness.md`,
`ADR-078-graceful-cron-drain-before-container-swap.md`. This ADR becomes the canonical record for the
image-baked-plugin seed model (originated in #3045, `Dockerfile:151`, previously undocumented).

### C4 views
**No C4 impact.** Read `model.c4`, `views.c4`, `spec.c4`. The change is a CI trigger *condition* on the
already-modeled CI→image→host-deploy path (plugin system `model.c4:66`, loader `model.c4:57`,
`claude -> skillloader "Loads plugin"` `model.c4:273`, deploy infra `model.c4:192`, GitHub CI/CD
`model.c4:212`). No new external actor/system/container/data-store/access-relationship; C4 does not model
workflow path-filters. Decision captured in the ADR.

## Infrastructure (IaC)

**No new infrastructure.** Only GitHub Actions YAML + a Bun test. No server/service/cron/secret/DNS/vendor/
host-write path added; the host re-seed (`ci-deploy.sh`) is unchanged. Phase 2.8 IaC gate: skip. Explicitly
NOT Option B (which would have added host-write infra).

## Implementation Phases

### Phase 0 — Preconditions
- Confirm the denylist covers the incident file: a diff touching
  `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` must produce `changed=true`.
- Confirm docs/test are the only non-runtime top-level dirs; `ls plugins/soleur/` = {AGENTS.md, CLAUDE.md,
  LICENSE, NOTICE, README.md, agents, commands, docs, hooks, scripts, skills, test}. (Denylist includes
  the instruction files by default — no CLAUDE.md-loaded determination required.)
- Re-read `reusable-release.yml` L84-104 and `web-platform-release.yml` L1-40.

### Phase 1 — Inner gate (load-bearing)
Reuse `path_filter` unquoted with `set -f` + `set -euo pipefail` + git rc check (see Chosen Mechanism).
Preserve the `force_run` short-circuit. Update the input `description:`.

### Phase 2 — Outer gate
Add `plugins/soleur/**` + `!docs/**` + `!test/**` to `web-platform-release.yml` `on.push.paths`; widen the
`path_filter` value passed to the reusable workflow.

### Phase 3 — Behavioral test (collapses drift-guard + change-detection proof)
One Bun test running the byte-identical `check_changed` bash (same shell flags) against synthesized diffs:
- `plugins/soleur/skills/…` → `changed=true` (the incident); also `plugins/soleur/AGENTS.md`,
  `plugins/soleur/CLAUDE.md`, hypothetical `plugins/soleur/mcp/x` (future-surface) → `changed=true`.
- `plugins/soleur/docs/…`-only and `plugins/soleur/test/…`-only → `changed=false`.
- `apps/web-platform/…`-only → `changed=true` (regression guard).
- `force_run=false` for all rows (a dispatch test passes vacuously — spec-flow G10).
Plus a one-line grep asserting the outer `on.push.paths` contains `plugins/soleur/**` and the two `!`
exclusions. Do NOT string-compare the outer (`**`) and inner (`/`) dialects (spec-flow G6). Do NOT touch
`ship-deploy-pipeline-fix-gate.test.ts` — it guards an orthogonal host-resident-file trigger triangle
(architecture P2).

### Phase 4 — ADR (see Architecture Decision).

### Phase 5 — Soak follow-through (secret-free)
One post-merge health check: `curl -s https://app.soleur.ai/health | jq .build_sha` equals the
runtime-plugin merge SHA. Enroll a follow-through (`scripts/followthroughs/<short>-<issue>.sh`, exit 0 when
matched; `<!-- soleur:followthrough … -->` + `follow-through` label). No secrets to wire (health is public).

## Files to Edit
- `.github/workflows/reusable-release.yml` — `check_changed` (L84-104): `set -euo pipefail` + `set -f` +
  unquoted `$PATH_FILTER` + git rc check; update `path_filter` input `description:`.
- `.github/workflows/web-platform-release.yml` — `on.push.paths` denylist; widen the `path_filter` value.
- `plugins/soleur/test/web-platform-runtime-plugin-trigger.test.ts` (new; verify `bun test` discovery glob
  before pinning the path).

## Files to Create
- `knowledge-base/engineering/architecture/decisions/ADR-0NN-runtime-plugin-deploys-via-image-rebuild.md`
  (number from `/soleur:architecture`; latest is ADR-079).

## Files NOT to touch
- `apps/web-platform/infra/ci-deploy.sh` seed logic — correct; reused.
- `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` — merged & correct; out of scope.
- `plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` — orthogonal trigger set (architecture P2).
- `.github/workflows/version-bump-and-release.yml` — unchanged (single-token path_filter, unaffected).

## Acceptance Criteria

### Pre-merge (PR)
- [x] Outer `on.push.paths` contains `plugins/soleur/**`, `!plugins/soleur/docs/**`,
  `!plugins/soleur/test/**` (grep).
- [x] Inner `check_changed` uses unquoted `$PATH_FILTER` under `set -f` + `set -euo pipefail`, with an
  explicit git rc check that fails loud (`::error::`), never defaulting to skip.
- [x] Inner pathspecs contain NO `**` token.
- [x] `path_filter` input `description:` documents the space-separated-pathspec-list contract.
- [x] Behavioral test green for all rows (AGENTS.md/CLAUDE.md/future-surface → `changed=true`;
  docs-only/test-only → `changed=false`), run with `force_run=false`.
- [x] `bun test plugins/soleur/test/ship-deploy-pipeline-fix-gate.test.ts` still green.
- [x] `actionlint` clean on both workflows; `bash -c` on the extracted `check_changed` snippet.
- [x] ADR authored & committed (status may be `adopting`); cross-refs by slug. (ADR-080)
- [ ] PR body uses `Ref #N` (ops-remediation — closure is post-deploy). (ship phase)

### Post-merge (automated)
- [ ] `web-platform-release` fires and `deploy` re-seeds the mount; verify via `/hooks/deploy-status`
  exit_code=0 + `app.soleur.ai/health` `build_sha` == merge SHA (no SSH).
- [ ] Follow-through soak closes the tracking issue after the first post-fix runtime-plugin merge deploys.

## Test Scenarios
1. `skills/git-worktree/scripts/worktree-manager.sh` → builds+deploys+reseeds (the incident).
2. `plugins/soleur/AGENTS.md` / `CLAUDE.md` only → builds+deploys (denylist includes instruction files).
3. `plugins/soleur/docs/**` only → web-platform does NOT build; `deploy-docs.yml` still runs GH Pages.
4. `plugins/soleur/test/**` only → web-platform does NOT build.
5. Mixed `apps/web-platform/**` + `plugins/soleur/skills/**` → one build/deploy (no double web deploy).
6. `apps/web-platform`-only → unchanged.
7. `live-verify` correctly SKIPs on plugin-only merges — its own trigger gate reads
   `apps/web-platform/scripts/live-verify/trigger-paths.txt` (WS/auth/DOM paths only), which no
   `plugins/**` diff matches (`triggered=0 → BLOCK=0 → SKIPPED`) — verified benign, no false block.

## Observability

```yaml
liveness_signal:
  what: "web-platform-release deploy job succeeds; /hooks/deploy-status exit_code=0 for the new tag; app.soleur.ai/health build_sha == merge SHA"
  cadence: "per runtime-plugin merge to main"
  alert_target: "release Slack channel (notify-gated job) + GitHub Actions run status"
  configured_in: ".github/workflows/web-platform-release.yml (deploy, live-verify, notify-gated jobs)"
error_reporting:
  destination: "GitHub Actions red job + Slack (notify-gated); live-verify emits gate=live-verify Sentry event"
  fail_loud: true
failure_modes:
  - mode: "Inner gate green no-op (git error or bad pathspec swallowed → changed=false)"
    detection: "set -euo pipefail + explicit rc check fails loud in CI; Phase 3 behavioral test; post-merge build_sha != merge SHA"
    alert_route: "CI red pre-merge; deploy verify ::error:: post-merge"
  - mode: "Shell-glob expansion of an inner ** token silently drops new files"
    detection: "set -f in the gate; Phase 3 test asserts NO ** in inner pathspecs"
    alert_route: "CI red"
  - mode: "docs-only/test-only PR wrongly triggers a full build (cost regression)"
    detection: "Phase 3 test (docs-only/test-only -> changed=false)"
    alert_route: "CI red"
  - mode: "Future runtime surface added but silently not deployed"
    detection: "denylist includes it by default; Phase 3 future-surface row (plugins/soleur/mcp/x -> changed=true)"
    alert_route: "CI red if the row regresses"
logs:
  where: "GitHub Actions run logs; host /hooks/deploy-status JSON; app.soleur.ai/health"
  retention: "GitHub Actions default; deploy-status ephemeral host state file"
discoverability_test:
  command: "gh run list --workflow=web-platform-release.yml --branch main --limit 3 --json conclusion,headSha AND curl -s https://app.soleur.ai/health | jq .build_sha"
  expected_output: "latest run conclusion=success; health build_sha == the runtime-plugin merge SHA"
```

### Soak follow-through enrollment
Secret-free health check (see Phase 5). Finalize the script + directive at /work.

## Domain Review

**Domains relevant:** Engineering only.

### Engineering (CTO + deepen reviewers)
**Status:** reviewed
**Assessment:** CTO gave the binding A-vs-B ruling (Option A; B disqualified). Deepen-plan reviewers
(spec-flow-analyzer, architecture-strategist, code-simplicity-reviewer) refined the sub-mechanism:
denylist over allowlist, reuse `path_filter`, no-`**` inner pathspecs under `set -f`, fail-loud gate,
behavioral test. Architecture flagged the dual-release co-fire + prod-pipeline coupling (Risks) and
confirmed drift-guard separation + new-ADR. No Product/UI surface → Product/UX Gate NONE. No regulated
data → GDPR skip. No new infra → IaC skip.

## Open Code-Review Overlap
- #3220 (postmerge migration verification, `web-platform-release.yml`) — **Acknowledge:** different concern.
- #3216 (dpf-regex canary review, resolved inline) — **Acknowledge:** historical.
Neither overlaps the trigger-path widening.

## Risks & Mitigations
- **Inner-gate green no-op (highest).** Fixed by `set -euo pipefail` + rc check + Phase 3 behavioral test.
- **Shell-glob `**` in inner pathspecs.** Fixed by prefix pathspecs + `set -f` + a no-`**` assertion.
- **Empty/quoted pathspec = match-all.** Avoided by reusing the always-non-empty `path_filter` (not a
  nullable extra input).
- **Dual-release co-fire (architecture P1).** A runtime-plugin merge fires web-platform-release (`web-v*`,
  deploy) + version-bump-and-release (`v*` plugin tag/Release/Slack) + deploy-docs (GH Pages). Separate
  concurrency groups, isolated tag prefixes → no collision/double-deploy, but TWO Releases + TWO Slack/email
  notifications per PR. Accepted for correctness; consolidating/suppressing the plugin `v*` announcement for
  runtime merges is a follow-up (touches shared reusable-release.yml) — do not scope-creep here.
- **Prod pipeline runs on plugin-only merges (architecture P1).** `migrate` + `verify-doppler-secrets`
  (under `DOPPLER_TOKEN_PRD`) now execute on runtime-plugin merges — idempotent (no new migrations → no-op),
  but a runtime fix's delivery can now be fail-closed-blocked by unrelated prod-secret/migration drift.
  Correct trade-off (the image genuinely changed → full deploy is right); named so it is not a surprise.
- **`deploy-docs.yml` is a third consumer** of `skills/agents/commands` paths (its own GH-Pages surface).
  No conflict; do not "consolidate" the three filters.
- **`HEAD~1` squash-merge assumption (spec-flow G7).** Residual re-open path on non-squash/multi-commit
  pushes; mitigate by evaluating the push-range compare at /work (see Chosen Mechanism hardening).
- **Denylist over-deploys on rare root-file edits** (README/LICENSE/NOTICE) — accepted (fail-safe).

## PIR / Learning
Ops-remediation for a recurring silent-non-deploy. Author a PIR/learning at ship time capturing: the
image-baked-plugin bind-mount seed model; the two-gate change-detection (outer Actions-glob + inner
git-pathspec) and their DIALECT difference; why host-direct re-seed (Option B) silently regresses; and why
the fail-loud + denylist choices are load-bearing. (`/soleur:incident` or
`knowledge-base/project/learnings/bug-fixes/`.)
