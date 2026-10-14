# Tasks — plugin-root security-subset migration (#6156 / subset of #6154)

Plan: `knowledge-base/project/plans/2026-07-08-fix-plugin-root-security-subset-migration-plan.md`
Lane: single-domain · Threshold: single-user incident (`requires_cpo_signoff: true`)

## Phase 1 — Migrate the three sites (redaction gate first)

- [x] 1.1 `legal-generate/SKILL.md:60` — rewrite `SENTINEL=` to
      `${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/incident/scripts/redact-sentinel.sh`
      (preserve git-root fallback verbatim).
- [x] 1.2 `legal-generate/SKILL.md:55–57` — prose touch-up: describe deployed-root-first resolution
      (`${CLAUDE_PLUGIN_ROOT}` deployed, git-root fallback for CLI/worktree). Keep the `[[ -r "$SENTINEL" ]]`
      fail-closed guard (line 61) and `bash "$SENTINEL"` (line 62) unchanged.
- [x] 1.3 `incident/SKILL.md:217` — rewrite to the **hardened guard block** (mirrors legal-generate for
      the identical script; security review S1+S2):
      ```bash
      SENTINEL="${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/incident/scripts/redact-sentinel.sh"
      [[ -r "$SENTINEL" ]] || { echo "incident: redaction sentinel not found — halt (fail closed)"; exit 2; }
      bash "$SENTINEL" <draft-tmpfile>
      ```
      The `[[ -r ]]` `exit 2` routes through the existing exit-2 "cannot-evaluate → halt" branch (lines
      221–223, unchanged). Do NOT touch `dry-run.sh:31` (`${SKILL_DIR}` self-locating), the line-24
      markdown reference-link, or the repo-root `/scripts/` invocations at line 35 (distinct non-plugin class).
- [x] 1.4 `trigger-cron/SKILL.md:40,43,47` — prefix each `trigger.sh` invocation with
      `${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/` (preserve bare `plugins/soleur` anchor, no `bash` prefix).
      Do NOT touch the line-36 markdown reference-link or the line-63 worktree-CWD Sharp Edge.

## Phase 2 — Guardrail verification (no code-side change)

- [x] 2.1 `git diff --stat` shows ONLY the three SKILL.md files (no `safe-bash.ts`, no test files).
- [x] 2.2 `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh` — Tests 11a/11b/11c green.
- [x] 2.3 `cd apps/web-platform && ./node_modules/.bin/vitest run test/plugin-root-list-carveout-coupling.test.ts` green.
- [x] 2.4 `bun test plugins/soleur/test/trigger-cron-allowlist-parity.test.ts` green
      (adapt to the plugin test entrypoint if `bun test` filter misses; the suite `execFileSync`s `trigger.sh`).

## Phase 3 — Dual-resolution proof (per site, from a worktree)

- [x] 3.1 For each of the 3 invocation forms: `unset CLAUDE_PLUGIN_ROOT` → path expands to the
      git-root/`plugins/soleur` fallback and `[[ -r <path> ]]` is true.
- [x] 3.2 For each form: `CLAUDE_PLUGIN_ROOT=/app/shared/plugins/soleur` → path expands to the deployed copy.
- [x] 3.3 Record both expansions in the PR body / work log.

## Phase 4 — Ship prep

- [ ] 4.1 PR body: `Closes #6156` (body, not title) + "Scope carved out of #6154" paragraph; leave #6154 OPEN.
- [ ] 4.2 PR body: `## Changelog` section; labels `semver:patch`, `type/security`.
- [ ] 4.3 Post-merge: verify `#6156` closed and `#6154` still OPEN (`gh issue view` via /ship — not operator-manual).
- [ ] 4.4 Post-merge: `gh issue edit 6154` to strike `legal-generate` / `incident` / `trigger-cron` from
      #6154's body/checklist (spec-flow SF2 — keep the issue scope honest; automatable via /ship).

## Acceptance grep quick-ref

- `grep -c 'bash scripts/redact-sentinel.sh' plugins/soleur/skills/incident/SKILL.md` → `0`
- `grep -cE '^\s*plugins/soleur/skills/trigger-cron/scripts/trigger\.sh' plugins/soleur/skills/trigger-cron/SKILL.md` → `0`
- `grep -Fc '${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/trigger-cron/scripts/trigger.sh' plugins/soleur/skills/trigger-cron/SKILL.md` → `3` (fixed-string `-F`: the `${…}` is a literal, not BRE)
- `git diff --name-only origin/main...HEAD -- apps/web-platform/server/safe-bash.ts` → empty
