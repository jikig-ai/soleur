# Tasks — Fix runtime-plugin deploy gap to the Concierge host

Plan: `knowledge-base/project/plans/2026-07-02-fix-runtime-plugin-deploy-to-concierge-host-plan.md`
Lane: cross-domain | Threshold: single-user incident
CTO ruling: Option A (image rebuild, NOT host reseed). Deepen refinement: denylist + reuse path_filter + fail-loud inner gate.

## Phase 0 — Preconditions
- [x] 0.1 Confirm denylist covers the incident file: a diff touching `plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh` yields `changed=true`
- [x] 0.2 `ls plugins/soleur/` — confirm docs/ and test/ are the only non-runtime top-level dirs (denylist includes AGENTS.md/CLAUDE.md by default — no runtime-load determination needed)
- [x] 0.3 Re-read `reusable-release.yml` L84-104 and `web-platform-release.yml` L1-40

## Phase 1 — Inner gate (load-bearing) — reusable-release.yml check_changed
- [x] 1.1 (RED) Behavioral test harness runs the byte-identical `check_changed` bash (same shell flags) against synthesized diffs
- [x] 1.2 Add `set -euo pipefail`; keep `force_run` short-circuit; `set -f` before the diff; drop quotes on `$PATH_FILTER` (word-split to multiple git pathspecs); `set +f` after
- [x] 1.3 Explicit git rc check — fail loud (`::error::` + exit 1) on git failure, NEVER default to `changed=false`
- [x] 1.4 Update `path_filter` input `description:` to document the space-separated-pathspec-list contract (no embedded spaces; globbing disabled)
- [x] 1.5 Verify no `**` token in any inner pathspec

## Phase 2 — Outer gate — web-platform-release.yml
- [x] 2.1 `on.push.paths`: add `plugins/soleur/**`, `!plugins/soleur/docs/**`, `!plugins/soleur/test/**` (Actions glob syntax)
- [x] 2.2 Widen `path_filter` value: `"apps/web-platform/ plugins/soleur/ :(exclude)plugins/soleur/docs/ :(exclude)plugins/soleur/test/"`
- [x] 2.3 Confirm `version-bump-and-release.yml` path_filter is UNTOUCHED (single token, unaffected)

## Phase 3 — Behavioral test (drift-guard + change-detection in one)
- [x] 3.1 Rows → changed=true: skills/worktree-manager.sh, AGENTS.md, CLAUDE.md, plugins/soleur/mcp/x (future-surface), apps/web-platform/x
- [x] 3.2 Rows → changed=false: plugins/soleur/docs/x only, plugins/soleur/test/x only
- [x] 3.3 All rows run with `force_run=false` (dispatch passes vacuously — spec-flow G10)
- [x] 3.4 One grep asserting outer `on.push.paths` has `plugins/soleur/**` + the two `!` exclusions
- [x] 3.5 Do NOT string-compare outer(`**`)/inner(`/`) dialects; do NOT edit ship-deploy-pipeline-fix-gate.test.ts
- [x] 3.6 Verify `bun test` discovery glob before pinning the new test path

## Phase 4 — ADR
- [x] 4.1 `/soleur:architecture create 'Runtime-plugin changes deploy via image rebuild, not host-direct re-seed'`
- [x] 4.2 Record Decision + Alternatives (Option B rejected: image-vs-mount regression; allowlist rejected: silent under-deploy); cross-ref ADR-030/064/078 BY SLUG (duplicate ADR-030 numbers exist); note it's the canonical record for the #3045 image-baked seed model

## Phase 5 — Soak follow-through (secret-free)
- [x] 5.1 `scripts/followthroughs/<short>-<issue>.sh` — exit 0 when `curl -s app.soleur.ai/health | jq .build_sha` matches a runtime-plugin merge SHA
- [ ] 5.2 `<!-- soleur:followthrough … -->` directive + `follow-through` label (no secrets to wire)

## Phase 6 — Verify / ship
- [x] 6.1 `actionlint` both workflows; `bash -c` on the extracted check_changed snippet
- [x] 6.2 `bun test` green: new behavioral test + ship-deploy-pipeline-fix-gate.test.ts
- [x] 6.3 (Hardening, evaluate) push-range compare `${{ github.event.before }}...${{ github.sha }}` vs HEAD~1 squash-only invariant
- [ ] 6.4 PR body uses `Ref #N` (ops-remediation — closure post-deploy)
- [ ] 6.5 Post-merge: verify deploy re-seeds mount (`/hooks/deploy-status` exit_code=0; health build_sha == merge SHA)
- [x] 6.6 PIR/learning (bug-fixes): two-gate dialect model + why Option B regresses + fail-loud/denylist rationale
