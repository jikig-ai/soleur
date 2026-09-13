# Tasks: fix(release) — Turbopack static `new URL(…, import.meta.url)` in the cron containment hook

Plan: `knowledge-base/project/plans/2026-09-13-fix-release-build-turbopack-taxonomy-url-plan.md`

## Phase 1: RED — extend the guard (`apps/web-platform/scripts/lib/no-cross-context-import.test.sh`)

- [x] 1.1 Define `PATHSPECS` once as a bash array with `:(glob)` magic for `**/*.ts`, `**/*.tsx`, `**/*.mjs` plus the `:!` excludes (`*.test.*`, `*.spec.*`, `test/**`, `e2e/**`, `public/**`); no `.js` glob
- [x] 1.2 Replace the line-based `git grep` producer with the single `(cd "$ROOT" && git ls-files -z -- "${PATHSPECS[@]}" | xargs -0r perl -0777 -ne '…' 2>/dev/null)` scan — regex `\b(from|import|require|new\s+URL)\s*\(?\s*["\x27](\.\.?\/[^"\x27\n]*)["\x27]` (the `\n` in the negated class is load-bearing), prints `$ARGV\t$2\t<import|url>` — fed by process substitution into the existing resolver loop (`read -r file spec kind`)
- [x] 1.3 Two zero floors: keep `checked -eq 0 → FAIL: no relative references scanned …`; add `saw_url -eq 0 → FAIL: the new URL(…) arm produced zero hits …` (set `saw_url=1` when `kind == url`); reword `OK:`/`FAIL:` to "reference(s)"/"references"
- [x] 1.4 Header comment: #8074 as second guard instance / fourth of the family (#5890, #6852, #7666, #8074); cross-reference `test/docker-context-import-containment.test.ts`; why `perl -0777` and why `[^"\x27\n]`; assembly limits (tracked-only; model is "inside the app dir", `.dockerignore` covered by the sibling for configs); comments are scanned; perl 2-arg open closed by the `apps/` prefix; both floors are the detection path; pre-existing ~7 s `realpath` cost noted
- [x] 1.5 Run the guard on the unfixed tree → exit 1 naming the hook and `../../../../.claude/…` (AC7 RED half)

## Phase 2: GREEN — the one-file fix (`apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`)

- [x] 2.1 Add `import { dirname, resolve } from "node:path";`
- [x] 2.2 Replace the module-load `FILING_TAXONOMY_PATH` constant with the lazily-called `filingTaxonomyPath()` (`resolve(dirname(fileURLToPath(import.meta.url)), "../../../..", ".claude/hooks/lib/user-surface-taxonomy.txt")`)
- [x] 2.3 Change the single reader in `filingJustificationReason` to `readTaxonomy(filingTaxonomyPath())`
- [x] 2.4 Add the comment (no `'../` specifier quoted; `path.resolve` over strings is the fix, laziness moves the computation inside the catch layers; `filingTaxonomyPath()` is valid only under the standalone-CLI identity; keep a `function` declaration)

## Phase 3: Prove it

- [x] 3.1 Guard → `OK:` exit 0, count > 0 (AC7 GREEN half)
- [x] 3.2 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-bash-allowlist-hook.test.ts test/server/cron-filing-deny-marker.test.ts test/server/inngest/cron-claude-eval-substrate.test.ts` → 0 failures (AC4)
- [x] 3.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean (AC5)
- [x] 3.4 Standalone probe from `/tmp` against the worktree hook: allow at 240/9, deny naming ADR-131 at 19/1 (AC6)
- [x] 3.5 `cd apps/web-platform && docker build --target builder .` → exit 0, `✓ Compiled successfully`, no `cron-bash-allowlist-hook` diagnostic (AC2); BEFORE log (exit 1, `Can't resolve '../../../../.claude/…'`) recorded for AC1
- [x] 3.6 AC3: `perl -0777 -ne 'print "$ARGV\n" while /\bnew\s+URL\s*\(\s*["\x27]/g' <hook>` prints nothing
- [x] 3.7 Guard mutation matrix: M1, M2, M3, M5 RED; H1, H4 (PATH shim) RED via the `checked` floor; H2 (drop `.mjs` glob), H3 (drop `|new\s+URL`) RED via the `saw_url` floor; P2, P3 PASS — for every row the PR body carries `git diff --stat`, exit code, and the named stdout line (AC8)
- [ ] 3.8 `bash scripts/test-all.sh scripts` green (AC9) — REFUSED locally (rc=4, two sibling full-gate runs in flight); substitute: the guard itself (OK 670, 5.1 s, shellcheck clean, CI=1 identical) + its 10-row matrix + 7 consumer vitest files (437 tests, no Doppler); the required `test` context on the PR is the authoritative scripts-shard run
- [x] 3.9 `git diff --name-only "$(git merge-base origin/main HEAD)"..HEAD` = the two edited files + plan + this tasks.md + INDEX.md (+ learning if written) (AC12)

## Phase 4: Ship and verify delivery

- [ ] 4.1 `/soleur:ship` — PR (no `Closes`; `Ref` any incident/tracking issue), auto-merge
- [ ] 4.2 File the deferral tracking issue for a context-faithful PR-CI web-platform build (labels `domain/engineering`, `type/feature`; body `Mandated-By: wg-when-deferring-a-capability-create-a`; four instances #5890/#6852/#7666/#8074; both partial guards named; re-evaluate on a fifth instance or a third guard syntax); `Ref` it from the PR body
- [ ] 4.3 Post-merge: push-arm release run on `<merge-sha>` concludes `success` (AC10)
- [ ] 4.4 Post-merge: prod `/health` `build_sha` is the merge commit or a descendant and no longer `ef8b987f4*` (AC11)
