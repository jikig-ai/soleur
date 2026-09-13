---
title: "fix(release): the Web Platform Release Docker build fails on a static `new URL(…, import.meta.url)` in the cron containment hook"
date: 2026-09-13
slug: fix-release-build-turbopack-taxonomy-url
branch: feat-one-shot-release-build-turbopack-taxonomy-url
type: bug
lane: single-domain
domain: engineering
priority: p1
brand_survival_threshold: aggregate pattern
detail_level: minimal
---

## Enhancement Summary

**Deepened on:** 2026-09-13
**Sections enhanced:** Phase 1 (guard design), Phase 2 step 3 (hook comment), Guard Contract (assembly + matrix), Acceptance Criteria (AC8), Risks & Mitigations, Sharp Edges, Phase 4 (deferral issue), Research Insights
**Research agents used:** git-history-analyzer, test-design-reviewer, security-sentinel, architecture-strategist, verify-the-negative sweep (standard tier), Context7 `/vercel/next.js`

### Key Improvements
1. Regex hardening: `[^"\x27\n]*` prevents a comment-quoted `'../` from swallowing the next real escaping import (a silent false negative measured at deepen time).
2. A second zero floor (`saw_url`) with two harness rows (H2/H3) so a partially dark scan — the `.mjs` glob or the `new URL` branch dropped — cannot stay green behind ~660 `.ts` hits.
3. Attribution corrected (#6877 added the guard), the wider four-instance family named (#5890, #6852, #7666, #8074), and the sibling `.dockerignore` guard cross-referenced so the deferral issue lists both partial guards.

### New Considerations Discovered
- The failure path of the fix is strictly safer than today: a module-load throw was fail-open (D-new-1); the lazy call sits inside two catch layers and degrades to DENY.
- In the Next bundle `import.meta.url` is a getter over the bundle path, so `filingTaxonomyPath()` is only meaningful under the standalone-CLI identity — named in the hook comment; the bundled consumer never calls it.

## Overview

Every push to `main` since `0f649dbfb` (#8074, 2026-09-13 17:55 UTC) fails the Web Platform Release push arm at "Build and push Docker image", so production is stale on `ef8b987f4` (prod `/health` read at plan time: `"build_sha":"ef8b987f4d0b59c8975e3daf7bfccd3a2998411e"`). The measured cause is a build-time asset reference: `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` computes its taxonomy path with `fileURLToPath(new URL("../../../../.claude/hooks/lib/user-surface-taxonomy.txt", import.meta.url))` at module load, and #8074's new `server/cron-filing-deny-marker.ts` imports three pure functions (`filingShape`, `splitSegments`, `tokenize`) from that hook, which pulls the hook into the Next.js server bundle (`app/api/inngest/route.ts` → `cron-compound-promote.ts` → `_cron-claude-eval-substrate.ts` → `cron-filing-deny-marker.ts`) for the first time. Turbopack treats a static-string `new URL(…, import.meta.url)` as an asset it must resolve; the path escapes `apps/web-platform/`, and the Docker build context is `apps/web-platform` only (`reusable-release.yml` `docker_context: "apps/web-platform"`, Dockerfile `COPY . .`), so the containerized `npm run build` fails. A local `npm run build` on the full checkout does NOT fail (the file is present four levels up) — the same trap as learning `2026-07-23-cross-root-import-passes-local-next-build-fails-docker-context.md`, and the reason PR CI was green.

The fix is one file: resolve the taxonomy path with `path.resolve` over a runtime string, computed lazily inside the only function that reads it, so the bundler sees no asset and the standalone hook still resolves `<clone>/.claude/hooks/lib/user-surface-taxonomy.txt` from its own location. The regression guard is an extension of the existing `apps/web-platform/scripts/lib/no-cross-context-import.test.sh` (which already fails the class for relative `import`/`require` in `.ts`/`.tsx`) to also cover `new URL('../…', import.meta.url)` and `.mjs`/`.js` production files. It is RED on the current tree and GREEN after the fix.

**Verified at plan time (2026-09-13):**

- BEFORE reproduction (exact CI shape): `cd apps/web-platform && docker build --target builder .` → exit 1 with `Error: Turbopack build failed with 1 error: ./server/inngest/cron-bash-allowlist-hook.mjs:78:3 Error: Module not found: Can't resolve '../../../../.claude/hooks/lib/user-surface-taxonomy.txt'` then `ERROR: process "/bin/sh -c npm run build" did not complete successfully: exit code: 1` — byte-identical to run 34775115167.
- AFTER probe (throwaway copy of `apps/web-platform` in the scratchpad with the candidate patch applied, same command): exit 0, `✓ Compiled successfully in 24.5s`, no `cron-bash-allowlist-hook` diagnostic. In the compiled server chunk the hook's `import.meta.url` becomes a `get url(){return e.F("server/inngest/cron-bash-allowlist-hook.mjs")}` getter (a valid runtime `file://` URL), and the patched `filingTaxonomyPath()` survives verbatim — nothing is constant-folded.
- Standalone probe from a non-repo cwd (`cd /tmp && printf '<PreToolUse JSON for gh issue create --body-file <User-Impact + Fix-Size 240/9>>' | node <worktree>/apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs <allowlist with "gh issue create">`) → `permissionDecision:"allow"` on the current hook, proving exit 2 resolves the taxonomy from the module location today; the fixed hook must return the same from the same command.
- The esbuild `npm run build:server` bundle (`dist/server/index.cjs`) does NOT include the hook (0 matches for `user-surface-taxonomy` / `SOLEUR_CRON_FILING_DENY`), so only the Next/Turbopack bundle is affected.

## Research Insights

**Premise Validation (Phase 0.6).** `0f649dbfb` is the #8074 merge (2026-09-13 17:55:41 UTC); `ef8b987f4` is #8121 (17:22:18 UTC); `gh run list --workflow=web-platform-release.yml --branch main`: push-arm runs 34773058045 (`0f649dbfb`) and 34775115167 (`273f29a80`) are `failure`, 34771392796 (`ef8b987f4`) is `success`; the workflow_run deploy arms after those are `failure` (`release_failed`). Prod `/health` `build_sha` = `ef8b987f4…`. `git show origin/main:apps/web-platform/server/cron-filing-deny-marker.ts` exists (added in `0f649dbfb`) and imports `./inngest/cron-bash-allowlist-hook.mjs`. `.claude/hooks/lib/user-surface-taxonomy.txt` exists at the repo root (1337 bytes). The feature description's second import trace (`server/workspace.ts ← app/api/repo/setup/route.ts`) does NOT hold — `server/workspace.ts` imports nothing cron-related; the CI log shows the only App Route trace is via `app/api/inngest/route.ts` (also reachable through `oneshot-recheck-4217-calibration.ts` → same route). No stale premise otherwise. `origin/main` is `273f29a80` (a git-data evidence commit, untouched by this plan).

**Property List (Phase 0.6b).**

- P1 — The Next.js server bundle compiles inside the Docker build context (`apps/web-platform` only, no `.claude/`).
- P2 — The hook, executed standalone as `node <clone>/apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs <allowlist>` inside the cron sandbox, still resolves the taxonomy at `<clone>/.claude/hooks/lib/user-surface-taxonomy.txt` regardless of CWD (the clone is a full `git clone --depth=1`, `_cron-claude-eval-substrate.ts` `HOOK_REL_PATH`; the hook's own comment records that CWD-relative resolution silently broke under vitest).
- P3 — The deny marker keeps using the hook's own `filingShape` / `tokenize` / `splitSegments` (the one-predicate invariant of #8074).
- P4 — A PR-time guard fails when any bundled production module references a path above `apps/web-platform` via `new URL(<static>, import.meta.url)` (and, as already, via a relative import).
- P5 — Prod `/health` `build_sha` advances past `ef8b987f4` after merge.

**Cut List (Phase 0.6b).**

- Option (a) "move the pure functions into a bundle-safe module the hook re-exports" → buys P1 + P3, but so does option (b) at ~8 lines instead of a ~300-line tokenizer relocation with two files to keep in sync. Cut.
- "A test that the Next build resolves every module the inngest route imports" → buys P4 only by running a full `next build` against a context copy; the existing `no-cross-context-import.test.sh` (scripts shard, seconds) already covers the class for imports and is the mechanism the 2026-07-23 learning chose. Extend it instead. Cut.
- `process.cwd()`-based resolution (suggested by the learnings agent) → violates P2; the hook comment at the `FILING_TAXONOMY_PATH` site documents the measured failure. Cut.
- (plan-review) A second scan arm + per-arm counters/floors for `new URL` → one `perl -0777` alternation covers all four syntaxes with the existing single floor. Cut. A `*.js` glob → zero tracked production `.js` files exist. Cut. AC3 textual-shape assertions (filename count, definition/call count) → AC2/AC6/AC7 already prove the behaviour. Cut.

**Relevant files.**

- `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` — `FILING_TAXONOMY_PATH` (module load, line 77-79); the sole reader is `filingJustificationReason` (`readTaxonomy(FILING_TAXONOMY_PATH)`, line 194); CLI guard `if (invokedPath.endsWith("cron-bash-allowlist-hook.mjs")) main();` at the end.
- `apps/web-platform/server/cron-filing-deny-marker.ts` — imports `filingShape, splitSegments, tokenize` from the hook; never calls `filingJustificationReason` or `decide`.
- `apps/web-platform/server/inngest/functions/_cron-claude-eval-substrate.ts` — `HOOK_REL_PATH = "apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs"`, hook command `<node> <spawnCwd>/<HOOK_REL_PATH> <spawnCwd>/.claude/cron-allow.txt`; clone is `git clone --depth=1` (full tree).
- `apps/web-platform/scripts/lib/no-cross-context-import.test.sh` — the existing guard: `git grep -nE "(from|import|require)\s*\(?\s*['\"]\.\.?/"` over `apps/web-platform/**/*.ts|tsx` minus tests/e2e, `realpath -m` each specifier, FAIL if outside `$APP`, vacuity floor `checked -eq 0 → FAIL`. Discovered by `scripts/test-all.sh` SUITE_GLOBS `'apps/web-platform/scripts/lib/*.test.sh'` (scripts shard).
- `apps/web-platform/test/server/inngest/cron-bash-allowlist-hook.test.ts` — the exit-2 cases (`"exit 2 — a named surface with a size ABOVE the inline threshold allows"`) read the REAL taxonomy through the hook's own path, so they are the existing P2 guard under vitest.
- `apps/web-platform/test/server/cron-filing-deny-marker.test.ts`, `apps/web-platform/test/server/inngest/cron-claude-eval-substrate.test.ts` — the other consumers' suites (hook + deny-marker suites: 151 tests, all green on the unfixed tree at plan time, 2 files).
- `apps/web-platform/Dockerfile` (`COPY . .` at line 10, `RUN npm run build` at line 31), `apps/web-platform/.dockerignore`, `.github/workflows/reusable-release.yml` (`docker_context: "apps/web-platform"`), `.github/workflows/web-platform-release.yml` (`release` push-arm job; workflow_run arm `resolve-target` → `deploy` with the `/health` `build_sha` gate around line 1476; `notify-gated` Slacks on `release_failed`; `live-verify`).
- Current tracked `.mjs`/`.js` relative specifiers under `apps/web-platform` (outside `public/`, `test/`, `e2e/`): `scripts/plugin-root-sandbox-propagation-probe.mjs` (`./sandbox-canary.mjs`, `../server/agent-runner-sandbox-config.ts`, `../server/agent-env.ts`), `scripts/sandbox-canary.mjs` (`new URL(\n  "../infra/sandbox-canary-argv.json",\n  import.meta.url)` — a MULTI-LINE `new URL`, resolving inside the app), and the offending hook line. Widening the guard's glob creates no false positive.
- **A line-based `git grep` cannot see the multi-line `new URL(` form** (`sandbox-canary.mjs` is the in-repo proof: `git grep -nE "new URL\(\s*['\"]\.\.?/"` returns only the hook, while a `perl -0777` multiline scan returns both). The guard's `new URL` arm must therefore be multiline-safe: `git ls-files -z -- <pathspecs> | xargs -0 perl -0777 -ne 'while (/\bnew\s+URL\s*\(\s*["\x27](\.\.?\/[^"\x27]*)["\x27]/g) { print "$ARGV\t$1\n" }'` (verified at plan time: prints exactly `scripts/sandbox-canary.mjs ../infra/sandbox-canary-argv.json` and `server/inngest/cron-bash-allowlist-hook.mjs ../../../../.claude/hooks/lib/user-surface-taxonomy.txt`; `perl` is `/usr/bin/perl` locally and present on `ubuntu-latest`). Every other `new URL(` in `app/**`, `lib/**` is an absolute or bare-specifier URL and does not match.

**Institutional learnings applied.**

- `knowledge-base/project/learnings/2026-07-23-cross-root-import-passes-local-next-build-fails-docker-context.md` — the same class (#6852 broke it, #6875 inlined the fix, #6877 `fe772ec27` added the guard — verified via `git log --diff-filter=A`); green local `next build` is not proof; guard the boundary mechanically; the container build is the authority.
- `knowledge-base/project/learnings/best-practices/2026-06-05-never-at-runtime-often-means-never-import-spawn-a-preinstalled-cli.md` — a bundler only analyses what is static; a runtime-computed path is outside its analysis.
- `knowledge-base/project/learnings/2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-four-rounds-four-instances.md` and `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — write the mutation matrix before the guard; include a harness row and a non-canonical must-PASS.
- `knowledge-base/project/learnings/2026-07-18-backlog-issue-with-merged-code-closes-on-deploy-gate-not-merge.md` — merged is not deployed; the close condition is the deploy gate (`/health` `build_sha`).

**CLAUDE.md / AGENTS conventions applied.** `cq-write-failing-tests-before` (the extended guard is RED on the current tree before the fix lands); `hr-verify-repo-capability-claim-before-assert` (guard, clone layout, and esbuild reach were grepped, not assumed); typecheck via `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, tests via `./node_modules/.bin/vitest run <path>` (never `npm run -w`, never `bun test` in this package).

**Plan Review (post-draft panel: dhh, kieran, code-simplicity, cto-devex; spec-flow ran in Phase 3).** All findings classified Mechanical and applied: single `perl -0777` scan replaces the two-arm design (simplicity), `:(glob)` pathspecs so top-level app files are in scope (kieran P1), H4 as a PATH shim only — `xargs` never sees a bash function (kieran P1), matrix trimmed to M1/M2/M3/M5/H1/H4/P2/P3 (dhh, simplicity), AC3 reduced to one behavioural perl check (all three), count floors replaced by `> 0` (dhh), AC10 reduced to the push-arm conclusion on `--commit <merge-sha>` (dhh), AC4/observability/sharp-edges ceremony cut (dhh), scratch-copy fallback recorded with its caveats and `.dockerignore` named as an assembly limit (cto), deferral tracking issue for a context-faithful PR-CI build moved from Sharp Edges to a Phase 4 task per `wg-when-deferring-a-capability-create-a` (cto — a workflow-gate obligation, so Mechanical). Not applied: cto's batching of `realpath -m` (pre-existing ~7 s cost, noted in the header comment only). No Taste / User-Challenge findings remained, so no `decision-challenges.md` was written.

**Deepen pass (2026-09-13; git-history-analyzer, test-design-reviewer, security-sentinel, architecture-strategist, verify-the-negative sweep, Context7).** Applied: guard-origin attribution corrected (#6877 `fe772ec27` added the guard; #6875 only inlined); regex negated class gets `\n` (a comment-quoted `'../` otherwise swallows the next real import — measured); keyword capture + `saw_url` second floor with H2/H3 rows (a partial-dark scan is invisible to the single `checked` floor); H1/H4/P3 expectations anchored on floor/OK text, not exit code; mutation-landed preamble; AC8 made evidence-shaped; sibling guard `test/docker-context-import-containment.test.ts` cross-referenced and the family widened to four instances (#5890, #6852, #7666, #8074); hook comment names the dual-identity seam; Risks record the strictly-safer failure path. Verified-negative sweep: 8/9 claims confirmed (the 9th was the probe's own phrasing — the App Route chain is transitive via `cron-*.ts`, exactly as the plan states). Context7 (`/vercel/next.js`): Turbopack resolves `new URL(<literal>, import.meta.url)` as a static asset and reports `Module not found: Can't resolve <request>` from `turbopack-core/src/issue/resolve.rs` when the file is absent; `turbopackOptional` applies to `import()`/`require()` only, not to `new URL`, so there is no magic-comment escape for this shape. No ADR/C4 impact (zero hits for the hook or guard in the three `.c4` files; ADR-033/058/216 reference the containment contract, not the path mechanism).

**Community / external research (Phases 1.5, 1.5b, 1.6).** No stack gap; functional-discovery queried 3/3 registries with zero overlap for a Turbopack build-context guard (nothing installed). No external research: failure and fix were reproduced in the exact CI shape at plan time.

## Research Reconciliation — Spec vs. Codebase

| Feature-description claim | Reality | Plan response |
|---|---|---|
| Second import trace `← server/workspace.ts ← app/api/repo/setup/route.ts` | `server/workspace.ts` has no cron / hook import; the CI log's only `[App Route]` trace is `app/api/inngest/route.ts` (via `cron-compound-promote.ts` and `oneshot-recheck-4217-calibration.ts`) | Ignore; scope unchanged (one bundle entry) |
| "reproduce the failure locally with `cd apps/web-platform && npm run build`" | On the full checkout that command is GREEN (the file exists four levels up; PR CI ran exactly this and passed). Only the context-faithful build reproduces | Reproduction command is `cd apps/web-platform && docker build --target builder .` (verified red BEFORE / green AFTER at plan time) |
| Option (b) example `path.resolve(fileURLToPath(import.meta.url), "../../../../..", …)` | Off by one: `fileURLToPath(import.meta.url)` is the FILE; `resolve(file, "../../../../..")` is five ups from the file = four ups from its directory — correct, but easier to read as `resolve(dirname(file), "../../../..", …)` which mirrors the original `new URL` relative form exactly | Use `dirname(...)` + `"../../../.."` |

## Implementation Phases

### Phase 1 — RED: extend the guard so it fails on the current tree

Edit `apps/web-platform/scripts/lib/no-cross-context-import.test.sh` — replace the line-based `git grep` producer with ONE multiline scan that carries both reference syntaxes:

1. Define the pathspecs once, in a bash array, using git's `:(glob)` magic so top-level app files are in scope (a plain `apps/web-platform/**/*.ts` pathspec requires a `/` after the app dir and silently skipped `next.config.ts`, `middleware.ts`, `instrumentation.ts`, `sentry.*.config.ts` — a pre-existing gap): `':(glob)apps/web-platform/**/*.ts' ':(glob)apps/web-platform/**/*.tsx' ':(glob)apps/web-platform/**/*.mjs'` plus the excludes `':!apps/web-platform/**/*.test.ts' ':!apps/web-platform/**/*.test.tsx' ':!apps/web-platform/**/*.test.mjs' ':!apps/web-platform/**/*.spec.ts' ':!apps/web-platform/**/*.spec.tsx' ':!apps/web-platform/test/**' ':!apps/web-platform/e2e/**' ':!apps/web-platform/public/**'`. No `.js` glob: zero tracked production `.js` files exist under the app today (measured); add it the day one appears.
2. Replace the producer with a single `perl -0777` pass — one regex, one loop, one `checked` counter — because the in-repo `scripts/sandbox-canary.mjs` already spells `new URL(` with the string on the NEXT line, which no line-based grep can see, and a Prettier reflow of an over-long `import(`/`require(` produces the same shape. The regex captures the KEYWORD too, so the loop can tell which arm produced each hit:

   ```bash
   saw_url=0
   while IFS=$'\t' read -r file spec kind; do
     [[ -z "$file" ]] && continue
     checked=$((checked+1))
     [[ "$kind" == url ]] && saw_url=1
     resolved="$(realpath -m "$(dirname "$ROOT/$file")/$spec")"
     case "$resolved" in
       "$APP"/*) : ;;
       *) echo "FAIL: $file references '$spec'"
          echo "        → resolves to $resolved (OUTSIDE apps/web-platform/ — absent from the Docker build context)"
          fail=1 ;;
     esac
   done < <(cd "$ROOT" && git ls-files -z -- "${PATHSPECS[@]}" \
            | xargs -0r perl -0777 -ne 'while (/\b(from|import|require|new\s+URL)\s*\(?\s*["\x27](\.\.?\/[^"\x27\n]*)["\x27]/g) { my $k = ($1 =~ /^new/) ? "url" : "import"; print "$ARGV\t$2\t$k\n" }' 2>/dev/null)
   ```

   `[^"\x27\n]*` — NOT `[^"\x27]*` — is load-bearing under `-0777`: a JS string literal cannot contain a raw newline, and without `\n` in the class a stray `'../` inside a COMMENT swallows the following real `import … from "../../../../escape"` into one capture and the escaping import is never reported (measured by security-sentinel at deepen time). Process substitution (not `| while`) so `fail`/`checked`/`saw_url` are mutated in the main shell; `cd "$ROOT"` so `$ARGV` is repo-relative; `xargs -0r` so an empty list never runs `perl -ne` against STDIN; `2>/dev/null` mirrors the old arm for a tracked-but-deleted file. Measured on this tree: 671 hits (2 of kind `url`) in 0.09 s; the old grep arm reported 662 lines — the delta is the top-level configs, the `.mjs` files, and the hook line.
3. Two zero floors, each anchored on a text the matrix rows assert: keep the existing `checked -eq 0 → FAIL: no relative references scanned …; exit 1` (a dark scan of any cause — perl absent, broken pathspecs, unopenable files — yields zero hits), and ADD `saw_url -eq 0 → echo "FAIL: the new URL(…) arm produced zero hits — scripts/sandbox-canary.mjs is a known positive on every tree; the .mjs pathspec or the alternation went dark"; exit 1`. The second floor exists because the first cannot see a PARTIAL dark: drop only the `.mjs` pathspec or only `|new\s+URL` from the regex and ~660 `.ts` hits keep `checked > 0` while the exact class this PR fixes is unscanned (learning 2026-08-13 §3: a floor per layer). `OK:` line: `OK: $checked relative reference(s) scanned; none escape apps/web-platform/ (Docker build context intact).`
4. Header comment: name #8074 / this fix as the second instance of the class this guard sees (a static `new URL(<literal>, import.meta.url)` is an asset reference to Turbopack the moment the file is bundled — a standalone `.mjs` becomes bundled the day a `.ts` imports one function from it), and the fourth release-build failure of the wider "green locally, red in the Docker context" family (#5890, #6852, #7666, #8074); cross-reference the sibling vitest guard `apps/web-platform/test/docker-context-import-containment.test.ts`, which models the OTHER axis (`.dockerignore` exclusions for context-root `*.config.ts`) so nobody "consolidates" one into the other; say why the scan is `perl -0777` and not `git grep` (multi-line `new URL(` in `scripts/sandbox-canary.mjs`) and why `[^"\x27\n]`; state the assembly limits — tracked files only (untracked until `git add`; in CI everything is tracked), the model is "resolves inside the app dir", not "inside the context" (`.dockerignore` prunes `scripts/`/`infra/` except re-includes — the sibling guard covers that for configs); note that the regex does not skip comments (never quote a `'../` specifier in a comment of a scanned file — it is a hit, and if it escapes, a FAIL) and that perl's `-n` uses 2-arg magic open, closed only because every path is `apps/…`-prefixed by the globs; and say that the two zero floors, not stderr, are the detection path for a dark scan — do not "clean up" either. Also note the pre-existing ~7 s cost (one `realpath` fork per hit) as known, not for this PR.
5. Run `bash apps/web-platform/scripts/lib/no-cross-context-import.test.sh` → MUST print `FAIL: apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs references '../../../../.claude/hooks/lib/user-surface-taxonomy.txt'` and exit 1, while `scripts/sandbox-canary.mjs`'s in-app `../infra/sandbox-canary-argv.json` is counted but not failed.

### Phase 2 — GREEN: the one-file fix

Edit `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs`:

1. Add `import { dirname, resolve } from "node:path";` next to the existing `node:fs` / `node:url` imports.
2. Replace the module-load constant

   ```js
   const FILING_TAXONOMY_PATH = fileURLToPath(
     new URL("../../../../.claude/hooks/lib/user-surface-taxonomy.txt", import.meta.url),
   );
   ```

   with a lazily-called function that resolves from THIS module's directory over plain strings:

   ```js
   function filingTaxonomyPath() {
     return resolve(
       dirname(fileURLToPath(import.meta.url)),
       "../../../..",
       ".claude/hooks/lib/user-surface-taxonomy.txt",
     );
   }
   ```

   and change the single reader in `filingJustificationReason` to `readTaxonomy(filingTaxonomyPath())`.
3. In the existing comment block above it (the one that explains module-location resolution), add three lines: resolved lazily via `path.resolve` over plain strings — a static `new URL(literal, import.meta.url)` is a build-time asset reference to Turbopack once this module is bundled (`cron-filing-deny-marker.ts` imports it), and `.claude/` is outside the Docker build context, which broke the release build on every push to `main` from #8074 until this fix. Do not quote any `'../` specifier in the comment (the guard's regex scans comments — it would be a hit, and if it escapes, a FAIL), and do not claim laziness is what fixes the build — `path.resolve` over strings is; laziness only moves the computation inside the existing `try/catch` layers (`readTaxonomy` at the call site and `main()`'s backstop), so a throw there now degrades to DENY instead of the module-load fail-open the header's D-new-1 warns about. Add one sentence that `filingTaxonomyPath()` is valid only under the standalone-CLI identity (in the Next bundle `import.meta.url` is a getter over the bundle's own path, so a future bundled caller of `filingJustificationReason` would silently get exit 2 = does not apply); keep it a `function` declaration, not a `const` arrow.
4. Nothing else changes: `cron-filing-deny-marker.ts`, the hook's exports, the CLI guard, and the exit-2 semantics (empty/unreadable taxonomy → exit 2 does not apply) are untouched.

### Phase 3 — Prove it

1. `bash apps/web-platform/scripts/lib/no-cross-context-import.test.sh` → `OK: <N> relative reference(s) scanned; none escape apps/web-platform/ (Docker build context intact).`, exit 0, N > 0.
2. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-bash-allowlist-hook.test.ts test/server/cron-filing-deny-marker.test.ts test/server/inngest/cron-claude-eval-substrate.test.ts` → 0 failures (the exit-2 `allows` case inside the first file is the vitest-side P2 proof).
3. `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` → clean.
4. Standalone P2 probe from a non-repo cwd, against the fixed hook AT ITS WORKTREE PATH (a copy outside the repo legitimately denies — no `.claude/` above it):

   ```bash
   S=$(mktemp -d); printf 'gh issue create\n' > "$S/allow.txt"
   printf 'User-Impact: the /dashboard route 500s for org owners\nFix-Size: 240 lines / 9 files\n' > "$S/body.md"
   cd /tmp && printf '{"tool_name":"Bash","tool_input":{"command":"gh issue create --title t --body-file %s"}}' "$S/body.md" \
     | node "<worktree>/apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs" "$S/allow.txt"
   ```

   → `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}`. Replace `Fix-Size: 240 lines / 9 files` with `Fix-Size: 19 lines / 1 file` → `deny` with reason matching `inline threshold.*ADR-131` (proves the taxonomy was actually read, not that exit 2 was skipped).
5. Context-faithful build, the authority: `cd apps/web-platform && docker build --target builder .` → exit 0; record the `✓ Compiled successfully` line and the absence of any `cron-bash-allowlist-hook` diagnostic. (~30 s with the `npm ci` layer cached from the BEFORE run; minutes cold.) Fast pre-check when Docker is unavailable or cold — a copy of the app with no `.claude/` four levels up: `S=$(mktemp -d) && rsync -a --exclude .next --exclude dist apps/web-platform/ "$S/wp/" && (cd "$S/wp" && npm run build)` (node_modules travels with the copy; it does not apply `.dockerignore` and uses the host Node, so it is a pre-check, not the AC1/AC2 evidence). The plain `npm run build` on the full checkout is NOT evidence for this class and must not be cited as such.
6. Guard mutation matrix (see `## Guard Contract`): run each row; list any row deviating from expectation in the PR body (expected: none).

### Phase 4 — Ship and verify delivery

Via `/soleur:ship`: PR with `Closes` nothing (no issue number was cited — if `/ship` files or finds a tracking issue for the stale-prod incident, reference it with `Ref`), auto-merge. Post-merge: the push-arm `release` job on the merge commit MUST be `success` and prod `/health` `build_sha` MUST be the merge commit or a descendant (AC10/AC11) — read-only probes `/ship`'s `postmerge` already runs; no operator step.

Deferral tracking (`wg-when-deferring-a-capability-create-a`, plan-skill Step 6): the plan declines a context-faithful `next build` in PR CI (Non-Goals). File ONE tracking issue at ship time — title `feat(ci): context-faithful web-platform build in PR CI (Docker builder stage or apps/web-platform copy) when apps/web-platform/** changes`, body carrying `Mandated-By: wg-when-deferring-a-capability-create-a`, the four release-build instances of the "green locally, red in the Docker context" family (#5890 `sandbox-canary.mjs` re-include, #6852 → #6875 fix + #6877 guard, #7666 `vitest.config.ts` → eight red releases, #8074 → this PR), the two partial guards it would supersede (`scripts/lib/no-cross-context-import.test.sh` — syntax-enumerating, app-dir model; `test/docker-context-import-containment.test.ts` — `.dockerignore` model for context-root configs only), and the re-evaluation criterion "a fifth instance of the family, or the guard grows a third syntax" — labels `domain/engineering`, `type/feature` (verified via `gh label list`; `type/enhancement` does not exist), milestone per `knowledge-base/product/roadmap.md`. Reference it from the PR body with `Ref`.

## Files to Edit

- `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` — the fix (import line, function replacing the constant, one call site, comment).
- `apps/web-platform/scripts/lib/no-cross-context-import.test.sh` — the guard extension (`:(glob)` pathspec array incl. `.mjs`, the single multiline `perl -0777` scan replacing the line-based `git grep` producer, header comment, `FAIL:`/`OK:` wording "references"/"reference(s)").

## Files to Create

None.

## Non-Goals

- Relocating `filingShape`/`tokenize`/`splitSegments` into a separate module (option a) — cut, see Cut List.
- Touching `.claude/hooks/lib/user-surface-taxonomy.txt`, `guardrails.sh`, the deny marker, the substrate, or the git-data birth files (`apps/web-platform/infra/git-data-*`, `273f29a80`).
- A PR-CI `next build` against a Docker-context copy — the extended guard is the cheaper, seconds-long approximation the 2026-07-23 learning already chose. Deferred with a tracking issue filed in Phase 4 (second instance of the class in seven weeks; the guard enumerates syntaxes and does not model `.dockerignore`).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open --json number,title,body --limit 200` (65 open) piped through `jq --arg path` for `cron-bash-allowlist-hook.mjs`, `no-cross-context-import.test.sh`, and `cron-filing-deny-marker` returned zero matches (run at plan time, 2026-09-13).

## User-Brand Impact

**If this lands broken, the user experiences:** nothing new directly — the failure mode is that the release build stays red and every fix merged to `main` (including any user-facing one) never reaches production, which is the current state; a second failure shape (the hook's standalone resolution regressing) would make cron agents' exit-2 filings (`User-Impact:` + `Fix-Size:` above the inline threshold) be denied, so scheduled findings that name a user surface stop being filed — silently narrower, never wider, containment.

**If this leaks, the user's data is exposed via:** no exposure vector — the change touches a build-time path string and a CI grep; no user data, secret, or auth surface is read or written. The hook's containment (deny-by-default, secret-path deny) is not altered; the taxonomy read stays wrapped in the same `try/catch` that degrades exit 2 to "does not apply".

**Brand-survival threshold:** aggregate pattern — a stale production over days is a trust problem in aggregate (fixes announced but not live), not a single-user incident.

## Acceptance Criteria

- [ ] AC1 — BEFORE (recorded in the PR body from the plan-time run or re-run on the branch base): `cd apps/web-platform && docker build --target builder .` exits 1 and its log contains `Module not found: Can't resolve '../../../../.claude/hooks/lib/user-surface-taxonomy.txt'` attributed to `./server/inngest/cron-bash-allowlist-hook.mjs` (anchor on the text, not the line number).
- [ ] AC2 — AFTER: the same command exits 0 and its log contains `✓ Compiled successfully` and no line matching `cron-bash-allowlist-hook`.
- [ ] AC3 — `perl -0777 -ne 'print "$ARGV\n" while /\bnew\s+URL\s*\(\s*["\x27]/g' apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` prints nothing (no `new URL(<literal>` remains in the hook, single- or multi-line; the hook's `new URL(url)` in `browserNavigateReason` takes a variable and is legitimately untouched).
- [ ] AC4 — `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-bash-allowlist-hook.test.ts test/server/cron-filing-deny-marker.test.ts test/server/inngest/cron-claude-eval-substrate.test.ts` → 0 failures.
- [ ] AC5 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] AC6 — Standalone probe (Phase 3 step 4) from `cd /tmp` against the worktree hook returns `"permissionDecision":"allow"` for `Fix-Size: 240 lines / 9 files` and `"permissionDecision":"deny"` with a reason matching `inline threshold.*ADR-131` for `Fix-Size: 19 lines / 1 file`.
- [ ] AC7 — On the branch BEFORE Phase 2 (only the guard change applied), `bash apps/web-platform/scripts/lib/no-cross-context-import.test.sh` exits 1 naming `apps/web-platform/server/inngest/cron-bash-allowlist-hook.mjs` and the `../../../../.claude/…` specifier; after Phase 2 it exits 0 with an `OK:` line whose count is > 0.
- [ ] AC8 — For every `## Guard Contract` matrix row the PR body carries three things: the mutation's `git diff --stat` line, the guard's exit code, and the stdout line the Expected column names (the `FAIL:` line naming the file for M-rows — both files for M3; the floor text for H-rows; the `OK:` line for P-rows). A row missing any of the three is a deviation.
- [ ] AC9 — `bash scripts/test-all.sh scripts` (the scripts shard, which auto-discovers `apps/web-platform/scripts/lib/*.test.sh`) is green with the extended guard included in its suite list.
- [ ] AC10 — Post-merge: `gh run list --workflow=web-platform-release.yml --commit <merge-sha> --event push --json conclusion --jq '.[0].conclusion'` prints `success`.
- [ ] AC11 — Post-merge: `SHA=$(curl -sf --max-time 10 https://app.soleur.ai/health | jq -r .build_sha)`; `git fetch -q origin main && git merge-base --is-ancestor <merge-sha> "$SHA"` exits 0 (prod is at the merge commit or a descendant — a later merge deploying first is not a failure) AND `[[ "$SHA" != ef8b987f4* ]]`.
- [ ] AC12 — `git diff --name-only origin/main..HEAD` lists exactly: the two files in `## Files to Edit`, this plan, `knowledge-base/project/specs/feat-one-shot-release-build-turbopack-taxonomy-url/tasks.md`, and (if `/ship` writes it) a learning file under `knowledge-base/project/learnings/` — nothing else.

## Guard Contract

### Guard 1 — no-cross-context-import (extended)

**Property.** No production source file under `apps/web-platform/` (`.ts`, `.tsx`, `.mjs`, including the top-level `next.config.ts`/`middleware.ts`/`instrumentation.ts`; excluding `*.test.*`, `*.spec.*`, `test/**`, `e2e/**`, `public/**`) references, via a relative specifier (`./` or `../`) in `import … from`, `import(…)`, `require(…)`, or `new URL(…, …)` — on one line or across lines — a path that resolves outside `apps/web-platform/`, because such a reference compiles on the full checkout and fails inside the Docker build context.

**Assembly.** ONE pathspec array (`PATHSPECS`, `:(glob)` magic) selects every tracked production file; ONE `perl -0777` scan with ONE alternation reads them all and feeds ONE resolver loop with ONE `fail` flag and ONE `checked` counter guarded by ONE zero floor. Members are not enumerated — any tracked file matching the globs is in scope the moment it is added, and any of the four syntaxes flows through the same regex, which also tags each hit `import`/`url`. TWO zero floors: `checked -eq 0` (a fully dark scan — perl absent, broken pathspecs, unopenable files) and `saw_url -eq 0` (a PARTIALLY dark scan — the `.mjs` pathspec or the `new URL` alternation removed while ~660 `.ts` hits keep the first floor quiet); the in-tree `scripts/sandbox-canary.mjs` multi-line `new URL(` is asserted present on every tree, not assumed. Stated limits (in the header comment): tracked files only; the model is "inside the app dir", not "inside the Docker context" — `.dockerignore` is modelled by the sibling `apps/web-platform/test/docker-context-import-containment.test.ts` for context-root configs only. There is no second injection site (Dockerfile `COPY . .` copies exactly the app dir minus `.dockerignore`).

**Mutation matrix** (each applied as a temporary edit to a TRACKED file in the worktree, run `bash apps/web-platform/scripts/lib/no-cross-context-import.test.sh`, then reverted). Before running each row, `git diff --stat -- <file>` MUST list the mutated file; a row whose diff is empty is recorded as INVALID, not as passed (a mutation that did not land reports the baseline):

| # | Mutation | Expected |
|---|---|---|
| M1 | Restore `new URL("../../../../.claude/hooks/lib/user-surface-taxonomy.txt", import.meta.url)` in the hook (`.mjs`, single line) — the literal BEFORE state | RED, exit 1, naming the hook and the specifier |
| M2 | Add `import { stripFrontmatter } from "../../../../../scripts/lib/frontmatter-strip/strip";` to `server/inngest/functions/cron-compound-promote.ts` — the #6852 shape (`.ts`, import syntax) | RED (existing behaviour retained) |
| M3 | With M1 in place, ALSO add `const u = new URL("../../../plugins/soleur/x.txt", import.meta.url);` to `scripts/sandbox-canary.mjs` — a SECOND escaping member in a different file | RED naming BOTH files (the loop does not stop at the first member) |
| M5 | Add the MULTI-LINE form `const u = new URL(\n  "../../../../.claude/x.txt",\n  import.meta.url,\n);` to `scripts/sandbox-canary.mjs` (string on its own line, the shape already in that file) | RED — the row a line-based grep could not see |
| H1 (harness) | Change every pathspec to `':(glob)apps/web-platform/**/*.nope'` | RED, exit 1, stdout contains `FAIL: no relative references scanned` — a suite that scans nothing cannot pass |
| H2 (harness) | Remove ONLY the `':(glob)apps/web-platform/**/*.mjs'` pathspec | RED, exit 1, stdout contains `FAIL: the new URL(…) arm produced zero hits` — ~660 `.ts` hits must NOT mask the unscanned `.mjs` class |
| H3 (harness) | Delete `\|new\s+URL` from the alternation | RED, exit 1, same `new URL(…) arm` floor text |
| H4 (harness) | PATH shim only (a bash function is never seen by `xargs`): `D=$(mktemp -d); printf '#!/bin/sh\nexit 127\n' > "$D/perl"; chmod +x "$D/perl"; PATH="$D:$PATH" bash apps/web-platform/scripts/lib/no-cross-context-import.test.sh` | RED, exit 1, stdout contains `FAIL: no relative references scanned` — a missing scanner cannot pass |
| P2 (must-PASS, non-canonical) | Add `const w = new URL("pdfjs-dist/build/pdf.worker.min.mjs", import.meta.url);` to `components/kb/pdf-preview.tsx` (bare specifier, the real-world pattern already in that file) | exit 0 (not a relative specifier) |
| P3 (must-PASS) | The unmodified fixed tree — which already carries the in-app multi-line `new URL(` in `scripts/sandbox-canary.mjs` and the three in-app `.mjs` imports in `scripts/plugin-root-sandbox-propagation-probe.mjs` | exit 0, stdout contains the `OK:` line with count > 0 and does NOT contain `FAIL:` |

## Observability

```yaml
liveness_signal:
  what: web-platform-release.yml push-arm `release` job conclusion on main, then the workflow_run `deploy` job's /health build_sha gate (`Deploy verified: version … build_sha=<sha>`)
  cadence: every push to main
  alert_target: notify-gated job → operator Slack on `release_failed` (workflow_run arm); deploy-half email on deploy failure
  configured_in: .github/workflows/web-platform-release.yml (`release`, `resolve-target`, `deploy`, `notify-gated`)
error_reporting:
  destination: GitHub Actions run log, step "Build and push Docker image" (Turbopack error text) + Slack via notify-gated; runtime hook denials → SOLEUR_CRON_FILING_DENY pino WARN → Better Stack (#8076)
  fail_loud: yes — docker build exit 1 fails the `release` job; there is no continue-on-error on that step
failure_modes:
  - mode: a bundled production module references a path outside apps/web-platform (import or new URL)
    detection: apps/web-platform/scripts/lib/no-cross-context-import.test.sh reddens in the PR `test-scripts` shard (layer 1, PR CI); if it slips, the push-arm release job reddens (layer 1, post-merge)
    alert_route: PR check failure; notify-gated Slack on release_failed
  - mode: the hook's standalone taxonomy resolution regresses (exit 2 goes dark inside the cron sandbox)
    detection: cron-bash-allowlist-hook.test.ts exit-2 `allows` case at PR time (layer 1); at runtime, a rise in SOLEUR_CRON_FILING_DENY markers for crons that file `User-Impact:` findings (layer 4, Better Stack; runbook betterstack-log-query.md) — the marker carries capture_status so a dark channel is distinguishable from zero denials
    alert_route: PR check failure; Better Stack query per the #8076 runbook
logs:
  where: GitHub Actions run logs (release workflow, 90-day retention); Better Stack app_container_warn_filter for the hook's runtime marker
  retention: 90 days (GHA); Better Stack per plan tier
discoverability_test:
  command: bash apps/web-platform/scripts/lib/no-cross-context-import.test.sh
  expected_output: "OK: <N> relative reference(s) scanned; none escape apps/web-platform/ (Docker build context intact)."
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — build-pipeline / tooling regression fix inside the engineering domain.

## Test Scenarios

1. Fixed tree, Docker builder stage → green (AC2).
2. Fixed hook run standalone from `/tmp` with a taxonomy-naming body above the threshold → allow; inside the threshold → deny naming ADR-131 (AC6).
3. Guard on the pre-fix tree → RED on the hook line (AC7); guard on the fixed tree → OK (AC7).
4. Guard mutation matrix M1/M2/M3/M5 RED, H1/H4 RED via the `checked` floor, H2/H3 RED via the `saw_url` floor, P2/P3 PASS (AC8).
5. Existing vitest suites for hook, deny marker, substrate → green (AC4).

## Risks & Mitigations

- **Turbopack could still analyse `resolve(dirname(fileURLToPath(import.meta.url)), …)`** — measured at plan time: it does not (the function survives verbatim in the compiled chunk, build green). Sibling precedent in the same log: `_cron-claude-eval-substrate.ts:609` (`join(spawnCwd, HOOK_REL_PATH)`) and `agent-runner-sandbox-config.ts:98` only produce `Module not found: Can't resolve <dynamic>` WARNINGS, never errors.
- **`import.meta.url` inside the bundle is a getter (`e.F(...)`) rather than a literal** — irrelevant to the bundled consumer (never calls `filingJustificationReason`), and even if called it yields a valid `file://` URL; lazy evaluation removes the module-load throw class entirely.
- **A hidden third consumer of the hook** — grepped: only `cron-filing-deny-marker.ts` (bundled) and the substrate's `node <hook>` spawn (standalone) plus tests; esbuild's `dist/server/index.cjs` does not contain it.
- **Widened guard glob false-positives** — enumerated: the only `.mjs` relative specifiers today resolve inside the app; `public/**` is excluded explicitly. The `:(glob)` widening brings the top-level configs into scope; measured, their only relative refs (`next.config.ts → ./lib/security-headers`, `vitest.config.ts → ./test/repo-wide-suites`) are in-app. Dev-only configs (`eslint.config.mjs`, `playwright.config.ts`) are never loaded by the build, so an escape there would be a benign FAIL — acceptable for one uniform cheap rule.
- **Failure-path delta is strictly safer** — today a throw in `new URL`/`fileURLToPath` at module load happens before `main()`'s backstop exists = no decision = fail-open (header D-new-1); after the change the computation sits inside two catch layers and degrades to DENY (security-sentinel, deepen pass). The happy-path bytes are identical (probed for plain, space-bearing, `%20`-bearing and `#`-bearing clone paths).
- **Dual-identity seam** — in the bundle `import.meta.url` is a getter over the bundle's own path, so `filingTaxonomyPath()` would resolve to `/.claude/…` inside the container. Nothing bundled calls it today (`cron-filing-deny-marker.ts` imports only the three pure functions) and the read is try/catch-wrapped, so a future bundled caller would degrade exit 2 to "does not apply", never widen. Named in the hook comment (Phase 2 step 3); a bundled-import-surface assertion is a possible follow-up, not this PR.
- **Sibling guard overlap** — `apps/web-platform/test/docker-context-import-containment.test.ts` (vitest) checks context-root `*.config.ts` imports against `.dockerignore` (#7666, #5890). The two guards model orthogonal axes (this one: "resolves inside the app dir"; that one: "not pruned by `.dockerignore`") and now overlap on `next.config.ts`/`vitest.config.ts`; cross-referenced in both header comments, listed together in the Phase 4 deferral issue as the partial coverage a context-faithful PR-CI build would supersede.

## Sharp Edges

- Do NOT cite `cd apps/web-platform && npm run build` on the full checkout as proof for this class — it is green before AND after the fix. The authority is the Docker builder stage (or a copy of `apps/web-platform` with no `.claude/` four levels up, Phase 3 step 5).
- The scratch-copy AFTER probe DENIES the exit-2 filing (no repo root above it); that is expected and is why AC6 runs the hook at its worktree path.
- The guard scans tracked files only. When running the mutation matrix, mutate existing tracked files (or `git add -N` a new one); an untracked fixture is invisible to `git ls-files`.
- `git grep` is line-based. The in-repo `scripts/sandbox-canary.mjs` spells `new URL(` with the string on the next line; a guard written as a one-line grep would have passed a multi-line copy of the exact defect this plan fixes. The scan is a single `perl -0777` pass for that reason — do not "simplify" it back to `git grep`, do not remove either zero-hit floor (the `checked` floor is what makes a missing `perl` visible; the `saw_url` floor is what makes a dropped `.mjs` glob or alternation branch visible), and keep `\n` in the negated class (without it a `'../` inside a comment swallows the next real import).
- The regex scans comments and does not care about quoting context: a comment quoting `'../../x'` is a hit (a FAIL if it escapes), and a specifier containing an apostrophe (`"../foo's/bar"`) captures `../foo` — the directory prefix still resolves correctly, so escape detection survives. Never write an escaping `'../` literal in a scanned file, even as prose.
- A future syntax the regex does not name (`require.resolve('../…')`, a `new URL` whose first argument is a `const` declared elsewhere, `path.join(__dirname, '../../../..')` — the last is only a WARNING to Turbopack, not an error) or a reference into a `.dockerignore`d path would pass the guard; the Phase 4 tracking issue is where a context-faithful PR-CI build closes those.
