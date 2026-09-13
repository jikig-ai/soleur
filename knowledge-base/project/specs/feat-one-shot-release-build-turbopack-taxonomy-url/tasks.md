# Tasks: fix(release) — Turbopack static `new URL(…, import.meta.url)` in the cron containment hook

Plan: `knowledge-base/project/plans/2026-09-13-fix-release-build-turbopack-taxonomy-url-plan.md`

## Phase 1: RED — extend the guard (`apps/web-platform/scripts/lib/no-cross-context-import.test.sh`)

- [ ] 1.1 Define `PATHSPECS` once as a bash array with `:(glob)` magic for `**/*.ts`, `**/*.tsx`, `**/*.mjs` plus the `:!` excludes (`*.test.*`, `*.spec.*`, `test/**`, `e2e/**`, `public/**`); no `.js` glob
- [ ] 1.2 Replace the line-based `git grep` producer with the single `(cd "$ROOT" && git ls-files -z -- "${PATHSPECS[@]}" | xargs -0r perl -0777 -ne '…' 2>/dev/null)` scan (one alternation for `from|import|require|new URL`, prints `$ARGV\t$1`), fed by process substitution into the existing resolver loop
- [ ] 1.3 Keep the single zero-hit floor; reword floor + `OK:` line to "reference(s)"; reword `FAIL:` to "references"
- [ ] 1.4 Header comment: second instance of the class (#8074), why `perl -0777` not `git grep`, the two assembly limits (tracked-only; `.dockerignore` not modelled), floor is the detection path, pre-existing ~7 s `realpath` cost noted
- [ ] 1.5 Run the guard on the unfixed tree → exit 1 naming the hook and `../../../../.claude/…` (AC7 RED half)

## Phase 2: GREEN — the one-file fix (`apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`)

- [ ] 2.1 Add `import { dirname, resolve } from "node:path";`
- [ ] 2.2 Replace the module-load `FILING_TAXONOMY_PATH` constant with the lazily-called `filingTaxonomyPath()` (`resolve(dirname(fileURLToPath(import.meta.url)), "../../../..", ".claude/hooks/lib/user-surface-taxonomy.txt")`)
- [ ] 2.3 Change the single reader in `filingJustificationReason` to `readTaxonomy(filingTaxonomyPath())`
- [ ] 2.4 Add the three-line comment (no filename, no call spelling, no "laziness fixes the build" claim)

## Phase 3: Prove it

- [ ] 3.1 Guard → `OK:` exit 0, count > 0 (AC7 GREEN half)
- [ ] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-bash-allowlist-hook.test.ts test/server/cron-filing-deny-marker.test.ts test/server/inngest/cron-claude-eval-substrate.test.ts` → 0 failures (AC4)
- [ ] 3.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean (AC5)
- [ ] 3.4 Standalone probe from `/tmp` against the worktree hook: allow at 240/9, deny naming ADR-131 at 19/1 (AC6)
- [ ] 3.5 `cd apps/web-platform && docker build --target builder .` → exit 0, `✓ Compiled successfully`, no `cron-bash-allowlist-hook` diagnostic (AC2); BEFORE log (exit 1, `Can't resolve '../../../../.claude/…'`) recorded for AC1
- [ ] 3.6 AC3: `perl -0777 -ne 'print "$ARGV\n" while /\bnew\s+URL\s*\(\s*["\x27]/g' <hook>` prints nothing
- [ ] 3.7 Guard mutation matrix: M1, M2, M3, M5 RED; H1, H4 (PATH shim) RED via the floor; P2, P3 PASS — deviations (expected none) listed in the PR body (AC8)
- [ ] 3.8 `bash scripts/test-all.sh scripts` green (AC9)
- [ ] 3.9 `git diff --name-only origin/main..HEAD` = the two edited files + plan + this tasks.md (+ learning if written) (AC12)

## Phase 4: Ship and verify delivery

- [ ] 4.1 `/soleur:ship` — PR (no `Closes`; `Ref` any incident/tracking issue), auto-merge
- [ ] 4.2 File the deferral tracking issue for a context-faithful PR-CI web-platform build (`Mandated-By: wg-when-deferring-a-capability-create-a`; re-evaluate on a third instance or a third guard syntax); `Ref` it from the PR body
- [ ] 4.3 Post-merge: push-arm release run on `<merge-sha>` concludes `success` (AC10)
- [ ] 4.4 Post-merge: prod `/health` `build_sha` is the merge commit or a descendant and no longer `ef8b987f4*` (AC11)
