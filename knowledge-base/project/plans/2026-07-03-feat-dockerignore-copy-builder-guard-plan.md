---
title: "Generic pre-merge guard for Dockerfile COPY --from=builder of .dockerignore-stripped context paths"
type: feat
date: 2026-07-03
lane: single-domain
brand_survival_threshold: none
---

# Generic pre-merge guard: `COPY --from=builder` of a `.dockerignore`-stripped context path

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
`COPY --from=<stage> <src...> <dst>` in the Dockerfile, resolves each `<src>` to its build-context
path, and — for any `<src>` that is context-sourced (git-tracked) **and** stripped by a
`.dockerignore` exclusion with no `!`-re-include — fails `bun test`. Scope is test-only plus a small
helper module; no Dockerfile/.dockerignore behavior change is required (the current repo is already
clean — sandbox-canary and host-scripts are all re-included), unless the generalized guard surfaces a
real currently-uncovered gap.

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

Add a **pure helper module** + a **dedicated bun test** that together model the release-build
invariant at source level:

1. **Parse** all `COPY --from=<stage> <src...> <dst>` statements (single-line and `\`-continued
   multi-line) from `apps/web-platform/Dockerfile`.
2. For each statement, take the **last token as `<dst>`** and every preceding `/app/`-prefixed token
   as a `<src>`; strip the `/app/` prefix to get a build-context-relative path.
3. **Classify** each `<src>` via the build context's git-tracked set:
   - **context-sourced** (git-tracks the path, or any file under it) → it entered the builder via
     `COPY . .` and therefore **must survive `.dockerignore`**.
   - **build-generated** (not git-tracked — e.g. `.next`, `dist/server`, `next.config.mjs`) → it is
     produced by a `RUN` step inside the builder, independent of `.dockerignore` → **skip** (this is
     the false-positive guard that makes the check safe).
4. For each context-sourced `<src>`, **evaluate `.dockerignore`** (order-sensitive, negation-aware,
   last-match-wins) to decide whether the builder's `COPY . .` kept it. If it evaluates to
   **excluded**, emit a violation naming the `<src>`, the Dockerfile line, and the missing
   `!`-re-include the author must add.
5. Assert the real repo produces **zero violations**; assert a **synthetic fixture** with an
   infra-baked COPY lacking a re-include produces a violation (proves the guard bites).

The git-tracked discriminator (step 3) is the key design choice: it is **self-maintaining** (no
hardcoded allow-list of build outputs to drift) and **non-flaky** (unlike on-disk existence, which a
stray local `npm run build` would corrupt by materializing `.next`/`dist`).

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

## Technical Considerations

### Files to Create

- **`plugins/soleur/test/lib/dockerfile-copy-parity.ts`** — pure helper module (sibling to the
  existing `plugins/soleur/test/lib/discoverability-test-parser.ts`). Exports:
  - `parseBuilderCopySources(dockerfileText: string): { src: string; line: number }[]`
    — returns every `/app/`-prefixed `<src>` (context-relative, `/app/` stripped) from all
    `COPY --from=<stage> …` statements, single-line and multi-line; tolerates optional
    `--chown=`/`--chmod=` flags; last token per statement is treated as `<dst>` and excluded.
  - `isIgnoredByDockerignore(contextPath: string, dockerignoreText: string): boolean`
    — replays `.dockerignore` patterns in file order (skip blanks/`#`), negation-aware (`!` prefix),
    trailing-slash-normalized, dir-prefix + `*`/`**` glob matching, **last-match-wins**; returns
    `true` iff `contextPath` is net-excluded from the build context.
  - `findBuilderCopyReincludeViolations(args: { dockerfileText; dockerignoreText; trackedContextPaths: Set<string> }): { src: string; line: number }[]`
    — the composed guard: for each parsed `<src>`, skip if not context-sourced (not in / not a prefix
    of `trackedContextPaths`), else include if `isIgnoredByDockerignore` returns `true`.
- **`plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts`** — the `bun:test` suite
  (fixture RED tests + real-repo zero-violation assertion + classification assertions).

### Files to Edit

- **None required for behavior.** The generalized guard ships green against the current repo.
  - If GREEN unexpectedly surfaces a real uncovered gap (it should not, per Research Reconciliation),
    the fix is to add the missing `!infra/<file>` / `!scripts/<file>` line to
    `apps/web-platform/.dockerignore` — enumerate it in a follow-up commit within the same PR.
  - Optional (documentation only): a one-line comment in `cloud-init-user-data-size.test.ts` noting
    that its host-scripts re-include test is now **subsumed** by the generalized guard and retained
    for the AC2 parity trio. Not load-bearing; skip if it risks the existing suite.

### `.dockerignore` evaluator fidelity (scope boundary)

Full Docker `patternmatcher` glob fidelity (`filepath.Match` non-`/`-crossing `*`, ancestor-dir
matching for every pattern) is **out of scope**. The evaluator targets the pattern **classes actually
present** in `apps/web-platform/.dockerignore`: literal directory prefixes (`infra/`, `scripts/`,
`supabase/`), exact-path negations (`!infra/<file>`), and `*`/`**` globs (`*.md`,
`_plugin-vendored/**`). It is validated by a fixture suite covering each class. Because every real
`COPY --from=builder` `<src>` is either an exact file under `infra/`/`scripts/` or a top-level dir
(`public`), evaluator correctness on exotic patterns (`*.md` cross-directory semantics) is **not
load-bearing** for the real assertions — only for defense. This is stated explicitly so a future
editor does not mistake the evaluator for a general Docker-ignore engine.

### Scope: `--from=<stage>` only

The guard processes only `COPY --from=<stage>` statements (the two-stage bake-then-extract class).
Direct context `COPY <src> <dst>` (e.g. `COPY _plugin-vendored /opt/soleur/plugin` at Dockerfile:165)
is **out of scope**: a direct-context COPY that `.dockerignore` fully strips fails immediately and
visibly at the same build step, and `_plugin-vendored` is CI-vendored (not git-tracked) with its own
allow-list. The named problem class is specifically the builder-staged pattern.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — this is a CI test guard. A
  *false negative* (guard fails to catch a real missing re-include) reproduces the status quo: a red
  web-platform release and a frozen prod image until hotfixed. A *false positive* (guard flags a
  build-generated path) would red a PR's CI spuriously and block unrelated merges.
- **If this leaks, the user's data/workflow/money is exposed via:** N/A — the change touches only
  test code and a test-helper module; no runtime surface, no data path, no secret.
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

- [ ] Confirm build context root is `apps/web-platform` (`web-platform-release.yml:50`).
- [ ] Re-confirm the git-tracked classification for the 7 `<src>` (all verified at plan time):
      context-sourced = `public`, `scripts/sandbox-canary.mjs`, `infra/sandbox-canary-argv.json`,
      25 host-scripts; build-generated = `.next`, `dist/server`, `next.config.mjs`.
- [ ] Confirm the suite is discovered by `bun test plugins/soleur/` (default `*.test.ts` glob; root
      `bunfig.toml` `pathIgnorePatterns` excludes only `.worktrees/**` and `apps/web-platform/**`,
      not `plugins/**`).

### Phase 1 — RED (failing test first, per `cq-write-failing-tests-before`)

- [ ] Create `plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts` importing the
      (not-yet-implemented) helper API from `./lib/dockerfile-copy-parity`.
- [ ] **Gap-demonstration fixture test** (synthesized inline strings, `cq-test-fixtures-synthesized-only`):
      a synthetic Dockerfile containing `COPY --from=builder /app/infra/new-baked.sh ./infra/new-baked.sh`
      + a synthetic `.dockerignore` containing `infra/` but **no** `!infra/new-baked.sh`
      + a `trackedContextPaths` set containing `infra/new-baked.sh`. Assert
      `findBuilderCopyReincludeViolations(...)` returns a violation for `infra/new-baked.sh`.
- [ ] **Old-regex-misses-it assertion** (documents why generalization is needed): assert that the
      existing host-scripts-scoped regex form (`/COPY --from=builder\s*\\\n[\s\S]*?\/opt\/soleur\/host-scripts\//`)
      does **not** match the synthetic single-line infra COPY — i.e. the partial guard would let it through.
- [ ] Run `bun test plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts` → **fails**
      (helper unimplemented). Commit RED.

### Phase 2 — GREEN (implement the helper)

- [ ] Create `plugins/soleur/test/lib/dockerfile-copy-parity.ts` with the three pure exports above.
      - Parser: join `\`-continuation lines into one logical statement; regex-locate
        `COPY\s+(?:--\w+=\S+\s+)*--from=\S+`; tokenize the remainder; last token = `<dst>`; keep
        `/app/`-prefixed preceding tokens as srcs; record the source line number of the `COPY` keyword.
      - Evaluator: iterate patterns; track `ignored` (default `false`); for each non-blank/non-`#`
        pattern, compute negation + strip leading `!` + strip trailing `/`; translate to a full-match
        regex (`**`→`.*`, `*`→`[^/]*`, `?`→`[^/]`, escape metachars); a pattern **matches** `path` if
        the regex matches `path` OR matches any ancestor prefix of `path` (dir-prefix semantics);
        on match set `ignored = !negated`; return final `ignored`.
      - Composed guard: skip srcs not in the tracked set (membership = exact match OR any tracked path
        `startsWith(src + "/")`); for the rest, flag when `isIgnoredByDockerignore` is `true`.
- [ ] Build the real `trackedContextPaths` in the test via
      `execSync("git ls-files apps/web-platform", { cwd: REPO_ROOT })` (bounded output;
      `hr-never-run-commands-with-unbounded-output` satisfied) → split lines → strip the
      `apps/web-platform/` prefix → `Set`.
- [ ] **Real-repo zero-violation test:** read the real Dockerfile + `.dockerignore`, run the guard,
      assert `violations` is `[]`.
- [ ] **Classification tests:** assert `.next`, `dist/server`, `next.config.mjs` are skipped
      (build-generated) and `public`, `scripts/sandbox-canary.mjs`, `infra/sandbox-canary-argv.json`,
      a sampled host-script are treated as context-sourced-and-satisfied. Assert the parser finds
      all 7 `COPY --from=builder` statements (non-vacuity: `parseBuilderCopySources(...).length > 0`
      and includes at least one `/app/infra/…` and one `/app/public`).
- [ ] **Evaluator unit tests:** dir-prefix exclusion (`infra/foo` under `infra/` → ignored), exact
      negation re-include (`!infra/foo` → not ignored), later-negation-wins ordering, un-excluded
      top-level path (`public` → not ignored).
- [ ] Run the suite → **passes**. Commit GREEN.

### Phase 3 — Regression + docs

- [ ] Run `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` → still green (existing
      host-scripts re-include assertion unchanged).
- [ ] Optionally add the one-line "subsumed by generalized guard" comment in
      `cloud-init-user-data-size.test.ts` (skip if it risks the suite).
- [ ] Run the full plugin bun shard: `bun test plugins/soleur/` → green.

## Alternative Approaches Considered

| Approach | Why rejected |
|----------|--------------|
| Add another `!infra/<file>` per future baked path (status quo) | Whack-a-mole; each miss is a red `main` + frozen prod. The task is explicitly to close the class wholesale. |
| Widen the existing host-scripts regex in `cloud-init-user-data-size.test.ts` | That test is about `user_data` size + the AC2 parity trio; overloading it with a generic COPY parser couples two unrelated concerns. A dedicated file is more discoverable for the recurring class. |
| On-disk existence to discriminate build-generated vs context-sourced | Flaky: a local `npm run build` materializes `.next`/`dist`/`next.config.mjs`, turning them into false positives. Git-tracked is deterministic. |
| Hardcode a build-generated allow-list (`.next`, `dist`, `next.config.mjs`) | Drifts the moment a new build output is baked; the git-tracked check is self-maintaining. |
| Run the actual `docker build` in CI to catch it directly | Prohibitively slow/heavy for a per-PR gate; the whole point is a cheap source-level assertion (`hr-observability-as-plan-quality-gate` — the pre-merge catch must not require the expensive real build). |
| Full Docker `patternmatcher` port | Over-engineered for the pattern classes present; YAGNI. A focused evaluator + fixture suite covers the real srcs. |

## Dependencies & Risks

- **Risk: `.dockerignore` evaluator infidelity.** Mitigated by scoping to the pattern classes present
  + a fixture suite per class + the real-repo zero-violation assertion (any evaluator bug that
  mis-includes a real src surfaces as a spurious violation on the clean repo).
- **Risk: parser misses a `--chown`/`--chmod` flag form.** None present today; parser tolerates
  `--\w+=\S+` flags between `COPY` and `--from`. Covered by a fixture.
- **Risk: git unavailable in the test environment.** CI runs in a full `actions/checkout` git repo;
  `git ls-files` is standard and used by sibling tests. Bounded output.
- **Dependency: none** — no new packages (`bun:test`, `node:fs`, `node:child_process`, `node:path`
  only). Satisfies the plugin "no new dependencies" norm.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (61 open) and searched bodies for
`cloud-init-user-data-size`, `dockerfile-copy`, `dockerignore`, `Dockerfile`, `.dockerignore`,
`plugins/soleur/test/lib` — zero matches. The new test file + helper are greenfield.

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

- [ ] `bun test plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts` exits 0.
- [ ] The suite includes a test that runs `findBuilderCopyReincludeViolations` against a **synthetic**
      Dockerfile+`.dockerignore` with an `infra/`-baked COPY lacking a re-include and asserts the
      returned violation list is **non-empty** (guard bites).
- [ ] The suite includes a test that runs the guard against the **real**
      `apps/web-platform/Dockerfile` + `.dockerignore` + the live `git ls-files apps/web-platform`
      tracked set and asserts **zero** violations.
- [ ] `parseBuilderCopySources` against the real Dockerfile returns srcs for all 7
      `COPY --from=builder` statements, including at least one `/app/infra/…` and one `/app/public`
      (non-vacuity).
- [ ] Classification is asserted: `.next`, `dist/server`, `next.config.mjs` are **skipped**
      (build-generated / not git-tracked); `scripts/sandbox-canary.mjs` and
      `infra/sandbox-canary-argv.json` are treated as **context-sourced-and-satisfied**.
- [ ] The suite asserts the pre-existing host-scripts-scoped regex does **not** match a single-line
      infra COPY (documents the closed gap).
- [ ] `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` still exits 0 (existing
      host-scripts re-include assertion unchanged).
- [ ] `bun test plugins/soleur/` (full plugin shard) is green.
- [ ] The RED fixture-test commit precedes the GREEN helper commit in the branch history
      (`cq-write-failing-tests-before`).

### Post-merge (operator)

- None. Pure test/tooling change; no operator action.

## Test Scenarios

### RED-phase targets

- Given a Dockerfile baking `/app/infra/new-baked.sh` and a `.dockerignore` with `infra/` but no
  `!infra/new-baked.sh` (and `infra/new-baked.sh` in the tracked set), when the guard runs, then it
  reports a violation naming `infra/new-baked.sh`. *(Fails before the helper exists.)*

### Regression / real-repo

- Given the real `apps/web-platform/Dockerfile` + `.dockerignore` + live tracked set, when the guard
  runs, then it returns zero violations (sandbox-canary + host-scripts + `public` all satisfied).
- Given `.next` / `dist/server` / `next.config.mjs` srcs (not git-tracked), when the guard runs, then
  they are skipped and never flagged (no false positive).

### Evaluator edge cases

- Given `.dockerignore` = `["infra/", "!infra/keep.txt"]`, when evaluating `infra/keep.txt`, then
  not-ignored; when evaluating `infra/drop.txt`, then ignored.
- Given a `\`-continued multi-line `COPY --from=builder`, when parsed, then every `/app/…` src is
  returned and the trailing `/opt/…/` dest is excluded.
- Given a `COPY --from=builder --chown=1001:1001 /app/foo ./foo`, when parsed, then `foo` is returned
  (flag tolerated) and `./foo` (dest) is excluded.

## References & Research

### Internal

- `apps/web-platform/Dockerfile:142-203` — the 7 `COPY --from=builder` statements (target surface).
- `apps/web-platform/.dockerignore:4-67` — `infra/`/`scripts/` exclusions + sandbox-canary +
  host-scripts re-includes.
- `plugins/soleur/test/cloud-init-user-data-size.test.ts:271-319` — existing partial guard
  (`dockerfileBakedSet()` + host-scripts re-include test) that this subsumes.
- `plugins/soleur/test/lib/discoverability-test-parser.ts` — sibling pure-helper convention.
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
- The evaluator is **not** a full Docker patternmatcher (see "evaluator fidelity" above). If a future
  `.dockerignore` adds a pattern class the evaluator doesn't model (e.g. `[abc]` character classes),
  add a fixture and extend the translator rather than assuming coverage.
- Keep the guard scoped to `COPY --from=<stage>`; direct-context `COPY` (e.g. `_plugin-vendored`) is a
  different, immediately-visible failure class and is intentionally excluded.
