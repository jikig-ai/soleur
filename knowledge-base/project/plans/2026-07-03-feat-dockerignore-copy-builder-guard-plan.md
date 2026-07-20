---
title: "Generic pre-merge guard for Dockerfile COPY --from=builder of .dockerignore-stripped context paths"
type: feat
date: 2026-07-03
lane: single-domain
brand_survival_threshold: none
---

# Generic pre-merge guard: `COPY --from=builder` of a `.dockerignore`-stripped context path

## Enhancement Summary

**Deepened on:** 2026-07-03
**Agents:** code-simplicity-reviewer, architecture-strategist (2 targeted; full 40-agent fan-out
skipped per budget discipline for a test-only change).

### Key improvements from the deepen pass

1. **Simpler evaluator (simplicity review).** Dropped the general `*`/`**`/last-match-wins glob
   engine. All in-scope `.dockerignore` excludes are literal directory prefixes (`infra/`,
   `scripts/`) and all re-includes are exact `!<path>` — so the guard reuses the existing
   `dockerignoreInfraReincludes()` Set pattern (test lines 306-317), generalized beyond `infra/`:
   *excluded-dir-prefix set + exact-`!`-reinclude set + ancestor-prefix check*. Fail-loud-safe: a
   future glob re-include (`!infra/*.json`) would produce a **loud spurious violation on the
   clean-repo test**, prompting the author to extend — never a silent miss.
2. **Inline, no helper module (simplicity review).** The only non-trivial pure logic left is the
   multi-line `COPY` parser; `cloud-init-user-data-size.test.ts` already keeps such logic inline.
   Dropped the `plugins/soleur/test/lib/dockerfile-copy-parity.ts` module — functions live at the
   top of the new test file. Files-to-Create shrinks to one.
3. **Trimmed tests (simplicity review).** Cut the tautological "old host-scripts regex misses a
   single-line COPY" assertion (it tests another file's deliberate limitation). Trimmed the
   per-src classification block to non-vacuity + the single genuine false-positive case: `.next`
   (the only build-generated src that actually falls under an exclusion, `.next/`).
4. **Wholesale close — builder `RUN` scripts too (architecture review).** The same release-break
   class fires when a builder-stage `RUN bash scripts/<x>.sh` consumes a `.dockerignore`-stripped
   context script (historical: `RUN bash scripts/assert-dev-signin-eliminated.sh` at Dockerfile:36,
   re-included at `.dockerignore:55-61` — the comment there records the `exit 127` break). The guard
   is extended to also scan builder-stage `RUN` shell-script invocations and apply the identical
   check, so it closes the COPY-bake **and** the RUN-consume subsets, not just COPY.

### New considerations discovered

- Of the three build-generated srcs, only `.next` matches any `.dockerignore` exclusion; `dist/server`
  and `next.config.mjs` match no pattern at all, so they cannot be flagged in either design — the
  git-tracked discriminator's live false-positive surface today is a single path (`.next`). Keep the
  discriminator (principled, one bounded `git ls-files` call) but do not over-frame its necessity.
- The `next.config.mjs` trap is handled correctly: the guard resolves the literal COPY src token
  (`next.config.mjs`, untracked → skip), never the sibling `next.config.ts` (tracked).

## Overview

`apps/web-platform/Dockerfile` is a 3-stage build. The `builder` stage runs `COPY . .` (line 10),
which is filtered by `apps/web-platform/.dockerignore`. The `runner` stage then bakes specific
build artifacts into the final image via `COPY --from=builder /app/<path> ...`. When `<path>` is a
**context-sourced** file (committed in the repo, copied into the builder by `COPY . .`) that lives
under a `.dockerignore` exclusion (e.g. `infra/`, `scripts/`) **with no matching `!`-re-include**,
the builder never has the file, the runner `COPY` fails with `"/app/infra/<file>": not found`, the
`release` job goes red, `deploy` is skipped, and prod stays frozen on the prior image. Because the
break lands on `main`, **every web-platform release fails until it is hotfixed**.

This has bitten the release repeatedly: the sandbox-canary re-includes (`#5875`/`#5890`, ADR-079)
and the 25 baked host-bootstrap scripts (`#5921`/`#5922`, ADR-080), each fixed reactively by adding
`!infra/<file>` / `!scripts/<file>` lines after the release had already broken.

CI does **not** run the Docker build (the release build is the first place the `COPY` is exercised),
so a **source-level `bun test` assertion is the only pre-merge catch**.

**Existing guard is PARTIAL.** `plugins/soleur/test/cloud-init-user-data-size.test.ts` already
asserts re-inclusion — but only for the **multi-line** host-scripts `COPY` block. Its
`dockerfileBakedSet()` regex is deliberately scoped to the `\`-continued COPY ending in
`/opt/soleur/host-scripts/` (test file lines 277-318). It does **not** cover the single-line
sandbox-canary `COPY` (line 155), nor any future baked path under a different excluded dir.

**Deliverable:** a generalized, self-maintaining guard that parses **every**
`COPY --from=<stage> <src...> <dst>` in the Dockerfile **plus every builder-stage `RUN` shell-script
invocation** (e.g. `RUN bash scripts/<x>.sh`), resolves each referenced `<src>` to its build-context
path, and — for any `<src>` that is context-sourced (git-tracked) **and** stripped by a
`.dockerignore` exclusion with no `!`-re-include — fails `bun test`. Scope is test-only (one new test
file, functions inline); no Dockerfile/.dockerignore behavior change is required (the current repo is
already clean — sandbox-canary, host-scripts, and `assert-dev-signin-eliminated.sh` are all
re-included), unless the generalized guard surfaces a real currently-uncovered gap.

The `RUN`-script leg was added at deepen-plan time (architecture review): a builder `RUN bash
scripts/<x>.sh` that `.dockerignore` strips fails with `exit 127` at build — the **same** red-`main`
+ frozen-prod release-break signature as the runner `COPY` case. `apps/web-platform/.dockerignore`
lines 55-61 record exactly this history for `scripts/assert-dev-signin-eliminated.sh`. Covering both
legs is what makes the guard close the class *wholesale* rather than the COPY subset only.

## Problem Statement / Motivation

The failure class is a **cross-stage invariant** that no single-file review reliably catches: the
`COPY --from=builder` in the Dockerfile and the `!infra/<file>` in `.dockerignore` are ~130 lines
apart in two different files, and the coupling is invisible until the release build runs. Each prior
incident was caught only in production-release CI, incurring a red `main` + a frozen prod image + a
reactive hotfix. The recurring cost justifies a wholesale guard rather than another per-path
re-include.

The existing partial guard proves the pattern works but only closes one instance (the host-scripts
multi-line COPY). Generalizing it converts a whack-a-mole into a closed class.

## Proposed Solution

Add a **dedicated bun test** (pure functions inline, no separate module) that models the release-build
invariant at source level:

1. **Parse** all `COPY --from=<stage> <src...> <dst>` statements (single-line and `\`-continued
   multi-line) from `apps/web-platform/Dockerfile`; last token = `<dst>`, every preceding
   `/app/`-prefixed token = a `<src>` (stripped of `/app/`).
2. **Also parse builder-stage `RUN` shell-script invocations** — for `RUN` lines between
   `FROM … AS builder` and the next `FROM`, extract shell-script path args matching
   `(?:bash|sh|source|\.)\s+(\S+\.sh)\b` with a relative path. These are context srcs the builder
   needs at build time (strip → `exit 127`).
3. **Classify** each referenced `<src>` via the build context's git-tracked set:
   - **context-sourced** (git-tracks the path, or any file under it) → it entered the builder via
     `COPY . .` and therefore **must survive `.dockerignore`**.
   - **build-generated** (not git-tracked — e.g. `.next`, `dist/server`, `next.config.mjs`) → it is
     produced by a `RUN` step inside the builder, independent of `.dockerignore` → **skip** (this is
     the false-positive guard that makes the check safe).
4. For each context-sourced `<src>`, decide whether `.dockerignore` strips it via the **simplified
   evaluator** (deepen-plan simplicity review): an *excluded-dir-prefix set* (non-`!`, non-`#`,
   non-glob patterns, trailing `/` stripped) + an *exact-`!`-reinclude set* (`!<path>` lines, no
   globs). A `<src>` is **stripped** iff some excluded prefix is an ancestor
   (`src === pref || src.startsWith(pref + "/")`) **and** `<src>` is not in the reinclude set. On a
   stripped src, emit a violation naming the `<src>`, its Dockerfile line, and the exact `!<path>`
   re-include to add.
5. Assert the real repo produces **zero violations**; assert **synthetic fixtures** (one COPY form,
   one `RUN`-script form) with no re-include each produce a violation (proves the guard bites).

Two design choices are load-bearing:

- **Git-tracked discriminator (step 3):** self-maintaining (no hardcoded build-output allow-list to
  drift) and non-flaky (unlike on-disk existence, which a stray local `npm run build` corrupts by
  materializing `.next`/`dist`/`next.config.mjs`). *Today its only live false-positive surface is
  `.next`* — `dist/server` and `next.config.mjs` match no `.dockerignore` pattern — but it remains the
  correct general classifier.
- **Simplified evaluator (step 4), not a glob engine:** every real in-scope exclude is a literal dir
  prefix and every real re-include is an exact `!<path>`, so a `*`/`**`/last-match-wins engine is
  unexercised generality (YAGNI). The Set+prefix form is **fail-loud-safe**: a future glob re-include
  it cannot model surfaces as a *spurious violation on the clean-repo test* (safe direction), which
  the author fixes by extending — it never silently passes a real strip.

## Research Reconciliation — Spec vs. Codebase

Verified against `origin`-worktree `HEAD` at plan time:

| Claim | Reality (verified) | Plan response |
|-------|--------------------|---------------|
| Build context root is `apps/web-platform` | `.github/workflows/web-platform-release.yml:50` `docker_context: "apps/web-platform"` | Resolve `<src>` `/app/foo` → context `foo` → repo `apps/web-platform/foo`. |
| 7 `COPY --from=builder` statements | Confirmed: lines 142, 143, 146, 154, 155, 158, 177 (multi-line) | Parser must handle single-line **and** `\`-continued multi-line. |
| `public`, `scripts/sandbox-canary.mjs`, `infra/sandbox-canary-argv.json`, 25 host-scripts are context-sourced | `git ls-files` returns each → tracked | Must survive `.dockerignore`; all currently re-included (repo clean). |
| `.next`, `dist/server`, `next.config.mjs` are build-generated | `git ls-files` returns **nothing** for each (only `next.config.ts` tracked) | Classified build-generated → skipped → no false positive. |
| Existing guard covers only host-scripts multi-line COPY | `dockerfileBakedSet()` regex anchored to `/opt/soleur/host-scripts/` (test lines 277-318) | Generalized guard subsumes it; keep old test as-is (parity trio). |
| Repo is currently clean (no uncovered gap) | sandbox-canary re-included at `.dockerignore:19`,`:67`; host-scripts `:29-53` | No Dockerfile/.dockerignore change needed; guard ships green. |
| Builder `RUN` also consumes a context script | `Dockerfile:36` `RUN bash scripts/assert-dev-signin-eliminated.sh`, re-included `.dockerignore:55-61` (comment records the `exit 127` break) | Same release-break class → guard covers builder `RUN .sh` args; currently clean. |

## Technical Considerations

### Files to Create

- **`plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts`** — the `bun:test` suite with
  the pure functions **inline at the top of the file** (the convention `cloud-init-user-data-size.test.ts`
  already uses; no separate `lib/` module — deepen-plan simplicity review). Functions:
  - `parseBuilderCopySources(dockerfileText): { src: string; line: number }[]`
    — every `/app/`-prefixed `<src>` (context-relative, `/app/` stripped) from all
    `COPY --from=<stage> …` statements, single-line and `\`-continued multi-line; last token per
    statement = `<dst>` (excluded); tolerates optional `--chown=`/`--chmod=` flags.
  - `parseBuilderRunScriptSources(dockerfileText): { src: string; line: number }[]`
    — for `RUN` lines inside the `builder` stage (between `FROM … AS builder` and the next `FROM`),
    the relative `.sh` path args matching `(?:bash|sh|source|\.)\s+(\S+\.sh)\b`.
  - `dockerignoreExclusionModel(dockerignoreText): { excludedDirPrefixes: string[]; reincludes: Set<string> }`
    — excluded-dir-prefix set (non-`!`/non-`#`/non-glob patterns, trailing `/` stripped) + exact
    `!<path>` reinclude set. (Simplified evaluator — no glob engine.)
  - `findReincludeViolations({ dockerfileText, dockerignoreText, trackedContextPaths }): { src; line }[]`
    — the composed guard over `parseBuilderCopySources ∪ parseBuilderRunScriptSources`: skip srcs not
    context-sourced (not in, and not an ancestor of any path in, `trackedContextPaths`); flag a
    context-sourced src iff an excluded prefix is its ancestor **and** it is not in `reincludes`.

### Files to Edit

- **None required for behavior.** The generalized guard ships green against the current repo.
  - If GREEN unexpectedly surfaces a real uncovered gap (it should not, per Research Reconciliation),
    the fix is to add the missing `!infra/<file>` / `!scripts/<file>` line to
    `apps/web-platform/.dockerignore` — enumerate it in a follow-up commit within the same PR.
  - Optional (documentation only): a one-line comment in `cloud-init-user-data-size.test.ts` noting
    that its host-scripts re-include test is now **subsumed** by the generalized guard and retained
    for the AC2 parity trio. Not load-bearing; skip if it risks the existing suite.

### Evaluator: simplified Set+prefix form, not a glob engine (scope boundary)

Every in-scope `.dockerignore` exclude that a real baked/consumed `<src>` hits is a **literal
directory prefix** (`infra/`, `scripts/`) and every re-include is an **exact** `!<path>` — verified
against all 7 COPY srcs + the one builder `RUN` script (deepen-plan architecture review). A full
Docker `patternmatcher` port (`*`/`**`/last-match-wins/ancestor globbing) is therefore unexercised
generality and is **out of scope** (YAGNI). The Set+prefix model is **fail-loud-safe**: if a future
`.dockerignore` adds a glob re-include the simple model cannot represent (e.g. `!infra/*.json`), the
clean-repo zero-violation test flags a *spurious* violation (safe direction) — the author then
extends the model. It never silently passes a real strip. Do **not** mistake this for a general
Docker-ignore engine.

### Scope: builder-stage `COPY --from=<stage>` and `RUN` shell-scripts

In scope: (a) `COPY --from=<stage>` statements (the bake-then-extract class), and (b) builder-stage
`RUN` shell-script invocations (`bash|sh|source|.` + a `.sh` path). Both fail the release with the
same signature when `.dockerignore` strips a needed context file.

Out of scope: direct context `COPY <src> <dst>` (e.g. `COPY _plugin-vendored /opt/soleur/plugin` at
Dockerfile:165) — a direct-context COPY fully stripped fails immediately/visibly at the same step, and
`_plugin-vendored` is CI-vendored (not git-tracked) with its own allow-list. Also out of scope:
builder `RUN` steps that consume non-`.sh` context files (`RUN node scripts/foo.mjs`) — none exist
today; the `.sh` regex is intentionally narrow to avoid false-matching `RUN npm run build` /
`RUN ./node_modules/.bin/esbuild next.config.ts`. Widen the regex if such a `RUN` is later added.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this is a CI test guard. A
  *false negative* (guard fails to catch a real missing re-include) reproduces the status quo: a red
  web-platform release and a frozen prod image until hotfixed. A *false positive* (guard flags a
  build-generated path) would red a PR's CI spuriously and block unrelated merges.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A — the change touches only
  test code (one new bun test file); no runtime surface, no data path, no secret.
- **Brand-survival threshold:** `none` — test-only tooling change; touches no sensitive path
  (per preflight Check 6 sensitive-path regex: schemas, migrations, auth, API routes, infra `.tf`).

## Observability

```yaml
liveness_signal:
  what:            "bun test suite plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts (CI PR gate)"
  cadence:         "per-PR (every push) and per-merge, via scripts/test-all.sh bun shard"
  alert_target:    "PR status check (red X blocks merge); operator sees failing CI on the PR"
  configured_in:   "scripts/test-all.sh:180 (run_suite \"plugins/soleur\" bun test plugins/soleur/)"

error_reporting:
  destination:     "GitHub Actions job log (ci.yml bun shard) — no Sentry (build-time test, not runtime)"
  fail_loud:       "bun test non-zero exit → failing required check on the PR; violation message names the <src>, Dockerfile line, and the exact !re-include to add"

failure_modes:
  - mode:          "A new COPY --from=builder bakes a context path under an excluded dir with no !re-include"
    detection:     "generalized guard emits a violation → bun test fails on the PR before merge"
    alert_route:   "PR red check → author"
  - mode:          "Guard false-positives on a build-generated src (regression in the git-tracked discriminator)"
    detection:     "real-repo zero-violation assertion fails; classification test names the misclassified src"
    alert_route:   "PR red check → author"

logs:
  where:           "GitHub Actions run logs for the bun shard"
  retention:       "GitHub default (90 days)"

discoverability_test:
  command:         "bun test plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts"
  expected_output: "all tests pass; 0 violations against the real Dockerfile + .dockerignore"
```

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)

- [x] Confirm build context root is `apps/web-platform` (`web-platform-release.yml:50`).
- [x] Re-confirm the git-tracked classification (all verified at plan time): context-sourced =
      `public`, `scripts/sandbox-canary.mjs`, `infra/sandbox-canary-argv.json`, 25 host-scripts,
      `scripts/assert-dev-signin-eliminated.sh` (builder `RUN` arg); build-generated = `.next`,
      `dist/server`, `next.config.mjs`.
- [x] Confirm the suite is discovered by `bun test plugins/soleur/` (default `*.test.ts` glob; root
      `bunfig.toml` `pathIgnorePatterns` excludes only `.worktrees/**` and `apps/web-platform/**`,
      not `plugins/**`).

### Phase 1 — RED (failing test first, per `cq-write-failing-tests-before`)

- [x] Create `plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts` with the four functions
      **inline** at the top, each a **stub** (e.g. `findReincludeViolations` returns `[]`).
- [x] **Gap-demonstration fixture tests** (synthesized inline strings, `cq-test-fixtures-synthesized-only`):
      (a) COPY form — a synthetic Dockerfile with `COPY --from=builder /app/infra/new-baked.sh ./…`
      + `.dockerignore` with `infra/` but **no** `!infra/new-baked.sh` + `trackedContextPaths` ⊇
      `{infra/new-baked.sh}` → assert `findReincludeViolations(...)` is non-empty;
      (b) RUN form — a synthetic builder stage with `RUN bash scripts/new-run.sh` + `.dockerignore`
      with `scripts/` and no re-include + tracked `scripts/new-run.sh` → assert a violation.
- [x] Run the suite → the two fixture tests **fail** (stub returns `[]`). Commit RED.

### Phase 2 — GREEN (implement the functions inline)

- [x] `parseBuilderCopySources`: join `\`-continuation lines into one logical statement; regex-locate
      `COPY\s+(?:--\w+=\S+\s+)*--from=\S+`; tokenize the remainder; last token = `<dst>`; keep
      `/app/`-prefixed preceding tokens as srcs (strip `/app/`); record the `COPY` keyword's line.
- [x] `parseBuilderRunScriptSources`: slice the Dockerfile between `FROM … AS builder` and the next
      `FROM`; for each `RUN` line, extract `(?:bash|sh|source|\.)\s+(\S+\.sh)\b` matches as srcs.
- [x] `dockerignoreExclusionModel`: iterate lines (skip blank/`#`); a non-`!` pattern with no glob
      metachar (`*?[`) and (trailing `/` **or** bare path) → `excludedDirPrefixes` (trailing `/`
      stripped); a `!<path>` with no glob → `reincludes` Set.
- [x] `findReincludeViolations`: union the two parsers; skip srcs not context-sourced (not in, and no
      tracked path `startsWith(src + "/")` — handles dir srcs like `public`); flag a context-sourced
      src iff some `excludedDirPrefixes` entry `p` satisfies `src === p || src.startsWith(p + "/")`
      **and** `src ∉ reincludes`.
- [x] Build the real `trackedContextPaths` via
      `execSync("git ls-files apps/web-platform", { cwd: REPO_ROOT })` (bounded output;
      `hr-never-run-commands-with-unbounded-output` satisfied) → split → strip `apps/web-platform/`
      prefix → `Set`.
- [x] **Real-repo zero-violation test:** read the real Dockerfile + `.dockerignore`, run the guard,
      assert `violations` is `[]`.
- [x] **Non-vacuity + false-positive tests (trimmed per simplicity review):**
      (a) `parseBuilderCopySources(real)` returns ≥1 `/app/infra/…` and ≥1 `/app/public` (guards a
      vacuous green); `parseBuilderRunScriptSources(real)` returns `scripts/assert-dev-signin-eliminated.sh`;
      (b) the one genuine false-positive case — `.next` (git-untracked, under the `.next/` exclusion)
      is **skipped** and never flagged.
- [x] **Evaluator unit tests (minimal):** dir-prefix exclusion (`infra/foo` under `infra/` with no
      re-include → violation), exact-negation re-include (`!infra/foo` → no violation), un-excluded
      top-level (`public` → no violation).
- [x] Run the suite → **passes**. Commit GREEN.

### Phase 3 — Regression + docs

- [x] Run `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` → still green (existing
      host-scripts re-include assertion unchanged; now subsumed by the generalized guard).
- [x] Optionally add the one-line "subsumed by generalized guard" comment in
      `cloud-init-user-data-size.test.ts` (skip if it risks the suite).
- [x] Run the full plugin bun shard: `bun test plugins/soleur/` → green.

## Alternative Approaches Considered

| Approach | Why rejected |
|----------|--------------|
| Add another `!infra/<file>` per future baked path (status quo) | Whack-a-mole; each miss is a red `main` + frozen prod. The task is explicitly to close the class wholesale. |
| Widen the existing host-scripts regex in `cloud-init-user-data-size.test.ts` | That test is about `user_data` size + the AC2 parity trio; overloading it with a generic COPY parser couples two unrelated concerns. A dedicated file is more discoverable for the recurring class. |
| On-disk existence to discriminate build-generated vs context-sourced | Flaky: a local `npm run build` materializes `.next`/`dist`/`next.config.mjs`, turning them into false positives. Git-tracked is deterministic. |
| Hardcode a build-generated allow-list (`.next`, `dist`, `next.config.mjs`) | Drifts the moment a new build output is baked; the git-tracked check is self-maintaining. |
| Run the actual `docker build` in CI to catch it directly | Prohibitively slow/heavy for a per-PR gate; the whole point is a cheap source-level assertion (`hr-observability-as-plan-quality-gate` — the pre-merge catch must not require the expensive real build). |
| Full Docker `patternmatcher` port (glob `*`/`**`, last-match-wins) | Over-engineered — every real in-scope exclude is a literal dir prefix and every re-include an exact `!<path>`. The Set+prefix model covers all real srcs and is fail-loud-safe. (deepen-plan simplicity review) |
| Separate `lib/` helper module | Ceremony once the evaluator collapses to Set+prefix; the only non-trivial pure logic is the parser, which the sibling `cloud-init-user-data-size.test.ts` keeps inline. (deepen-plan simplicity review) |
| Cover `COPY --from` only (not builder `RUN` scripts) | Leaves the same release-break class half-closed — a `RUN bash scripts/<x>.sh` strip is `exit 127` with the identical signature (`.dockerignore:55-61` history). Folded in. (deepen-plan architecture review) |

## Dependencies & Risks

- **Risk: simplified evaluator can't model a future glob re-include.** Fail-loud-safe by construction:
  such a pattern surfaces as a *spurious* violation on the clean-repo zero-violation test (safe
  direction), prompting the author to extend the model — never a silent miss. Mitigated further by
  the minimal evaluator unit tests.
- **Risk: parser misses a `--chown`/`--chmod` flag form or a `RUN`-script shape.** No flag forms
  present today; parser tolerates `--\w+=\S+` flags between `COPY` and `--from`. The `RUN` regex is
  intentionally narrow (`.sh` only) to avoid false-matching `RUN npm run build` /
  `RUN ./node_modules/.bin/esbuild next.config.ts`; both shapes covered by fixtures.
- **Risk: git unavailable in the test environment.** CI runs in a full `actions/checkout` git repo;
  `git ls-files` is standard and used by sibling tests. Bounded output.
- **Precedent (deepen-plan Phase 4.4):** the existing `dockerignoreInfraReincludes()` +
  `dockerfileBakedSet()` in `cloud-init-user-data-size.test.ts:277-318` is the direct precedent this
  guard generalizes (`infra/`-only → any excluded dir; multi-line COPY → all COPY + builder RUN).
  Not novel; the diff is a widened scope + the git-tracked discriminator.
- **Dependency: none** — no new packages (`bun:test`, `node:fs`, `node:child_process`, `node:path`
  only). Satisfies the plugin "no new dependencies" norm.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (61 open) and searched bodies for
`cloud-init-user-data-size`, `dockerfile-copy`, `dockerignore`, `Dockerfile`, `.dockerignore`,
`plugins/soleur/test/lib` — zero matches. The new test file is greenfield.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — this is an engineering test-tooling change (a CI guard). No
UI surface (Files-to-Create are `plugins/soleur/test/**`, matching no UI-surface glob), no product/
legal/finance/ops/sales/support implication.

## Architecture Decision (ADR/C4)

Not applicable. This guard enforces an **existing** implicit contract (Dockerfile baked `<src>` ⇔
`.dockerignore` re-include) that ADR-079 (sandbox-canary) and ADR-080 (host-scripts bake-and-extract)
already established. It introduces no new ownership/tenancy boundary, substrate, resolver, or trust
boundary, and reverses no ADR. C4: no external actor, external system, container, or data-store
changes — the guard is a build-time test with no runtime element. A competent engineer reading the
existing ADRs + C4 would not be misled by this change. Skip per Phase 2.10.

## Acceptance Criteria

### Pre-merge (PR)

- [x] `bun test plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts` exits 0.
- [x] The suite runs `findReincludeViolations` against **two synthetic fixtures** — (a) an `infra/`-baked
      `COPY --from=builder` lacking a re-include, (b) a builder `RUN bash scripts/<x>.sh` lacking a
      re-include — and asserts each returns a **non-empty** violation list (guard bites on both legs).
- [x] The suite runs the guard against the **real** `apps/web-platform/Dockerfile` + `.dockerignore` +
      the live `git ls-files apps/web-platform` tracked set and asserts **zero** violations.
- [x] `parseBuilderCopySources(real)` returns ≥1 `/app/infra/…` and ≥1 `/app/public` src (non-vacuity);
      `parseBuilderRunScriptSources(real)` returns `scripts/assert-dev-signin-eliminated.sh`.
- [x] The one genuine false-positive case is asserted: `.next` (git-untracked, under the `.next/`
      exclusion) is **skipped** and never flagged.
- [x] `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` still exits 0 (existing
      host-scripts re-include assertion unchanged; now subsumed by the generalized guard).
- [x] `bun test plugins/soleur/` (full plugin shard) is green.
- [x] The RED fixture-test commit precedes the GREEN implementation commit in branch history
      (`cq-write-failing-tests-before`).

### Post-merge (operator)

- None. Pure test/tooling change; no operator action.

## Test Scenarios

### RED-phase targets

- Given a Dockerfile baking `/app/infra/new-baked.sh` via `COPY --from=builder` and a `.dockerignore`
  with `infra/` but no `!infra/new-baked.sh` (and `infra/new-baked.sh` tracked), when the guard runs,
  then it reports a violation naming `infra/new-baked.sh`. *(Fails against the stub.)*
- Given a builder stage with `RUN bash scripts/new-run.sh`, `scripts/` excluded with no re-include,
  and `scripts/new-run.sh` tracked, when the guard runs, then it reports a violation. *(Fails against
  the stub.)*

### Regression / real-repo

- Given the real `apps/web-platform/Dockerfile` + `.dockerignore` + live tracked set, when the guard
  runs, then it returns zero violations (sandbox-canary + host-scripts + `public` +
  `assert-dev-signin-eliminated.sh` all satisfied).
- Given `.next` (not git-tracked, under `.next/`), when the guard runs, then it is skipped and never
  flagged (no false positive).

### Parser / evaluator edge cases

- Given `.dockerignore` model `{ excludedDirPrefixes: ["infra"], reincludes: {"infra/keep.txt"} }`,
  when checking `infra/keep.txt` → no violation; `infra/drop.txt` → violation.
- Given a `\`-continued multi-line `COPY --from=builder`, when parsed, then every `/app/…` src is
  returned and the trailing `/opt/…/` dest is excluded.
- Given a `COPY --from=builder --chown=1001:1001 /app/foo ./foo`, when parsed, then `foo` is returned
  (flag tolerated) and `./foo` (dest) is excluded.
- Given `RUN npm run build` and `RUN ./node_modules/.bin/esbuild next.config.ts` in the builder stage,
  when `parseBuilderRunScriptSources` runs, then neither is extracted (no `.sh` arg) — no false match.

## References & Research

### Internal

- `apps/web-platform/Dockerfile:142-203` — the 7 `COPY --from=builder` statements (target surface).
- `apps/web-platform/.dockerignore:4-67` — `infra/`/`scripts/` exclusions + sandbox-canary +
  host-scripts re-includes.
- `plugins/soleur/test/cloud-init-user-data-size.test.ts:271-319` — existing partial guard
  (`dockerfileBakedSet()` + `dockerignoreInfraReincludes()` + host-scripts re-include test) that this
  generalizes and subsumes; also the convention for inline pure functions in a bun test.
- `apps/web-platform/Dockerfile:36` + `.dockerignore:55-61` — the builder `RUN`-script leg
  (`assert-dev-signin-eliminated.sh`) and its historical `exit 127` release-break note.
- `scripts/test-all.sh:180` — `run_suite "plugins/soleur" bun test plugins/soleur/` (CI discovery).
- `.github/workflows/web-platform-release.yml:50` — `docker_context: "apps/web-platform"`.
- `knowledge-base/project/learnings/2026-03-20-dockerignore-nextjs-vs-bun-patterns.md` — prior
  `.dockerignore` gotcha (config files the build reads must not be excluded).

### Related work

- ADR-079 (sandbox-canary bake), ADR-080 (host-scripts bake-and-extract).
- PRs: `#5875`/`#5890` (sandbox-canary re-include), `#5921`/`#5922` (host-scripts re-include +
  release-break hotfix), `#5939` (baked host-scripts re-include follow-up). *No open issue — this is a
  recurring-class fix; none of the cited PRs are a work target.*

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text,
  or omits the threshold will fail `deepen-plan` Phase 4.6. This section is filled (`threshold: none`).
- The git-tracked discriminator is load-bearing: **do not** switch it to on-disk `existsSync` — a
  local `npm run build` materializes `.next`/`dist`/`next.config.mjs` and would flip them to false
  positives.
- The evaluator is a deliberate **Set+prefix simplification**, not a full Docker patternmatcher (see
  "Evaluator" section). Its safety rests on fail-loud: a future glob re-include it cannot model shows
  up as a *spurious* violation on the clean-repo test (safe direction) — extend the model then. Do not
  "fix" that by widening the discriminator to silence it.
- Keep the guard scoped to builder-stage `COPY --from=<stage>` + `RUN .sh`; direct-context `COPY`
  (e.g. `_plugin-vendored`) and `RUN` steps consuming non-`.sh` files are intentionally excluded
  (immediately-visible / non-existent today). Widen the `RUN` regex only if a `RUN node scripts/*.mjs`
  form is later added.
- The `RUN`-script regex is intentionally narrow (`.sh` via `bash|sh|source|.`). Broadening it risks
  false-matching `RUN npm run build` and flag-args; add a targeted fixture before widening.
