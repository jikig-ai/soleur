# Tasks — Fix runtime-plugin deploy gap to the Concierge host

Plan: `knowledge-base/project/plans/2026-07-02-fix-runtime-plugin-deploy-to-concierge-host-plan.md`
Lane: cross-domain | Threshold: single-user incident | CTO ruling: Option A (B disqualified)

## Phase 0 — Preconditions
- [ ] 0.1 Confirm each runtime glob matches ≥1 real file: `git ls-files | grep -E 'plugins/soleur/(skills|hooks|agents|commands|scripts|\.claude-plugin)/'`
- [ ] 0.2 Confirm host runtime does NOT read plugin-root `plugins/soleur/AGENTS.md` at exec time (if it does, add to the glob set)
- [ ] 0.3 Confirm the drift-guard test runner + discovery glob (`bun test`) before pinning the new test path
- [ ] 0.4 Re-read `reusable-release.yml` L84-104 and `web-platform-release.yml` L1-40 before editing

## Phase 1 — Runtime trigger set (allowlist)
- [ ] 1.1 Freeze the 6 globs: `skills/**`, `hooks/**`, `agents/**`, `commands/**`, `scripts/**`, `.claude-plugin/**` (exclude `docs/**`, `test/**`)

## Phase 2 — Inner change-detection (load-bearing)
- [ ] 2.1 (RED) Write change-detection proof test: plugins-runtime-only diff → `changed=true`; docs-only diff → `changed=false` (web-platform component)
- [ ] 2.2 Add optional `extra_path_filter` input to `reusable-release.yml`; OR it into `check_changed` using MULTIPLE `git diff` pathspec args (not one space-joined quoted string)
- [ ] 2.3 Preserve `force_run` short-circuit + `HEAD~1` squash-merge assumption; keep `plugin` component caller behavior byte-unchanged
- [ ] 2.4 (GREEN) 2.1 passes

## Phase 3 — Outer trigger
- [ ] 3.1 Add the 6 runtime globs to `web-platform-release.yml` `on.push.paths` (alongside `apps/web-platform/**`)
- [ ] 3.2 Pass the 6 globs to the reusable workflow via `extra_path_filter`

## Phase 4 — Drift-guard test
- [ ] 4.1 (RED) Assert runtime globs present in BOTH outer `push.paths` AND inner change-detection input; `docs/**`+`test/**` absent; extract each side by shape (not hardcoded)
- [ ] 4.2 (GREEN) implement; ensure `ship-deploy-pipeline-fix-gate.test.ts` stays green (no coupling regression)

## Phase 5 — ADR
- [ ] 5.1 `/soleur:architecture create 'Runtime-plugin changes deploy via image rebuild, not host-direct re-seed'`; record Decision + Alternatives (Option B rejected: image-vs-mount silent regression); cross-ref ADR-030 + incident

## Phase 6 — Soak follow-through
- [ ] 6.1 Add `scripts/followthroughs/<short-name>-<issue>.sh` (exit 0 when health.build_sha matches a runtime-plugin merge SHA)
- [ ] 6.2 Add `<!-- soleur:followthrough … -->` directive + `follow-through` label; wire any new `secrets=` into `scheduled-followthrough-sweeper.yml`

## Phase 7 — Verification / ship
- [ ] 7.1 `bun test` green for new tests + `ship-deploy-pipeline-fix-gate.test.ts`
- [ ] 7.2 `actionlint` on both workflows; `bash -c` on any extracted `run:` snippet
- [ ] 7.3 PR body uses `Ref #N` (ops-remediation — closure post-deploy)
- [ ] 7.4 Post-merge: verify `web-platform-release` deploy re-seeds mount (`/hooks/deploy-status` exit_code=0; `app.soleur.ai/health` build_sha == merge SHA)
- [ ] 7.5 Author PIR/learning (bug-fixes) capturing the two-gate model + why Option B regresses
