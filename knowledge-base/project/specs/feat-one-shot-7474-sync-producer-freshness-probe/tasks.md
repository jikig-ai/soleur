---
title: "Tasks — /soleur:sync per-site producer guards (#7474)"
date: 2026-08-11
branch: feat-one-shot-7474-sync-producer-freshness-probe
issue: 7474
lane: cross-domain
plan: knowledge-base/project/plans/2026-08-11-fix-sync-producer-freshness-probe-plan.md
---

# Tasks

Derived from the finalized (post-review) plan. Phase order is load-bearing: the tests land
before the `sync.md` edit (`cq-write-failing-tests-before`).

**Do not** edit the Phase 0 identity-gate fence in `plugins/soleur/commands/sync.md`. The
redesign deliberately leaves it untouched — no `exit 0`, no STOP-prose retarget. *(Held: the
fence is not in the diff.)*

## Deviations from the plan — measured, not preferred

Three, each recorded where it happened rather than folded silently into a checked box.

1. **3.1 — the guard form is `if … then … else … fi`, not `[ -f ] && … || echo …`.** The plan
   specified the `&&`/`||` one-liner. Measured: when the producer is **present but exits
   non-zero**, that form falls through to the `||` and reports it MISSING. That is a
   confidently wrong remedy, which the plan's own `## User-Brand Impact` ranks worst — strictly
   worse than today's unattributed error. Shipped as `if/then/else`, and **T0l** pins the
   semantics (not the syntax) via a form-agnostic block extractor, so reintroducing the
   rejected form goes RED rather than becoming invisible.
2. **2.3.8 held, but the sibling BASH extractor was widened.** `RUNNER_RE` and
   `DIRECT_EXEC_RE` are untouched (AC6 verified). Separately, the reachability suite has its
   own line-start-anchored `extract_from`, which the plan's Deepening Verification never
   examined — it only checked the vitest extractors. Measured: without a command-position
   normalization there, the `&&`-form mutation of a guarded site reports "target not in
   inventory" instead of the defect it introduces, i.e. **T0l could not fail**. Widened, and
   **T0d** now carries a command-position control so narrowing it back is caught.
3. **5.2 — the update-path defect was inlined as docs, not filed as an issue.** The
   `code-simplicity-reviewer` CONCUR gate DISSENTED and was right on two counts, both verified
   before adopting: the work is 3 files / ~25 lines (inside the inline-it threshold), and a
   milestone issue in *this* tracker could never be closed because the two-step behaviour
   belongs to the Claude Code plugin harness. Net issue flow **-1** rather than 0.

## Phase 1 — Preconditions (verify, never assume)

- [x] **1.1** Re-derived at HEAD: **3 distinct paths across 6 sites**, matching the plan.
- [x] **1.2** Both hand-ratcheted anti-vacuity floors read:
  - [x] **1.2.1** `expect(assertions).toBe(8)` (8 `seen()` calls).
  - [x] **1.2.2** `EXPECTED_CASES=9`, enforced twice.
- [x] **1.3** Both suites confirmed green before editing:
  - [x] **1.3.1** vitest 9/9 (**vitest, never `bun test`**).
  - [x] **1.3.2** reachability 9/9.

## Phase 2 — RED (tests first)

- [x] **2.1** Marker-emission cases added — **three**, because each alone is satisfiable by a
      wrong implementation: T0j (absent → marker, not invoked), T0k (present → no marker,
      invoked), T0l (present but failing → not reported missing).
  - [x] **2.1.1** Synthesized identity-valid roots (manifest + name + `scripts/`), producers
        as marker-touchers — never the real payload, which would mutate this repo.
  - [x] **2.1.2** Exact marker asserted, including `affects=` and `reason=absent-from-verified-root`.
  - [x] **2.1.3** Guarded producer asserted **not** executed; present siblings asserted still run.
  - [x] **2.1.4** T0i's `fi`-counting extractor left alone.
- [x] **2.2** `EXPECTED_CASES` 9 → **13** (T0j, T0k, T0l, T0m).
- [x] **2.3** **P6** parity assertion added.
  - [x] **2.3.1** Inserted **above** P5.
  - [x] **2.3.2** Scoped to `sync.md`'s entry of `parsed`.
  - [x] **2.3.3** Restricted to anchored operands in command position.
  - [x] **2.3.4** `affects=` closed set `{c4, coverage, domain-model}`, comma-split.
  - [x] **2.3.5** Non-vacuity (`>= 3`) asserted **before** the set comparison.
  - [x] **2.3.6** Remedy-bearing failure strings.
  - [x] **2.3.7** Parser scoped to fence bodies (ADR-179's worked examples are inline spans).
  - [x] **2.3.8** `RUNNER_RE` / `DIRECT_EXEC_RE` untouched — see Deviation 2.
- [x] **2.4** `expect(assertions).toBe(8)` → `toBe(9)`.
- [x] **2.5** Both suites confirmed RED for the right reason before the `sync.md` edit.

## Phase 3 — GREEN (the guard)

- [x] **3.1** All 6 producer invocations wrapped — **`if/then/else`, see Deviation 1**.
  - [x] **3.1.1** `scripts/generate-c4-from-components.ts` → `affects=c4`
  - [x] **3.1.2** `scripts/write-kb-coverage.ts` (plain **and** `--degraded`) → `affects=coverage`
  - [x] **3.1.3** `scripts/domain-model-drift.sh` (`drift`, `write-row`, `init`) → `affects=domain-model`
  - [x] **3.1.4** Every operand bare-anchored and quoted; no `:-`, no `:?` (T0b + P1b green).
- [x] **3.2** Verbatim operator message: attribution → remedy → remedy-rationale → fallback →
      what still worked. Pinned by **T0m** against a whitespace-normalized `sync.md`.
- [x] **3.3** Headless variant added (web-platform users have no plugin to reinstall).
- [x] **3.4** `--degraded` reuse note with both limits stated once.
- [x] **3.5** Pointer comment above the first guarded invocation naming both suites.
- [x] **3.6** `domain-model`'s two contracts left distinct.
- [x] **3.7** Both suites green (13/13 and 10/10).

## Phase 4 — ADR

- [x] **4.1** `SOLEUR_SYNC_PRODUCER_MISSING` added to ADR-179's `## Consequences` enumeration.
- [x] **4.2** Recorded that decision 5 (fail-closed in isolation) binds the freshness axis and
      is why the guard is per-site; also that this does **not** close the durability residual.

## Phase 5 — Tracking and exit gate

- [x] **5.1** SHA-divergence mechanism deferral appended to #7452 with re-evaluation criteria
      (comment `#issuecomment-5264170579`).
- [x] **5.2** ~~File the update-path UX defect~~ → **inlined as docs**, see Deviation 3.
      `README.md` `## Updating`, `plugins/soleur/README.md` `## Known Issues`,
      `docs/pages/getting-started.njk` callout, plus
      `feature-request-plugin-update-surfaces-install-divergence.md` for the upstream half.
- [x] **5.3** #7474 assigned to **Phase 4: Validate + Scale**.
- [x] **5.4** `bash scripts/test-all.sh` → `rc=1`, **297/301 suites passed** (297 passed, 1
      failed, 0 killed, 3 skipped as not-relevant-to-this-diff). The single failure is
      `plugins/soleur`, from two `changelog.js data file` cases that fetch the GitHub Releases
      API and timed out at 5000 ms (`[github.js] GitHub API failed … This operation was
      aborted`). Confirmed an environment flake three ways, as the `SIBLING_RUN_DETECTED` /
      `LOCK_CONTENDED_PROCEEDING` banners require: (a) isolated re-run of
      `plugins/soleur/test/changelog-data.test.ts` → **3 pass, 0 fail**; (b) `ci.yml` green on
      `main`; (c) the diff touches no `_data/` or `changelog` path, so it cannot reach that
      code. The run proceeded past a 900 s lock wait with two sibling worktrees running the
      same suite, which is the documented interleaving condition.
      Epilogue also records `apps/web-platform/infra/ is NOT covered above (diff does not
      touch it)` — correct for this diff.
- [ ] **5.5** PR body: `Closes #7474`, links 5.1-5.3, renders `decision-challenges.md`.

## Mutation matrix — every guard driven RED, then restored GREEN

| # | Mutation | Goes RED |
| --- | --- | --- |
| M1 | c4 `else`-branch deleted | T0j |
| M2 | c4 presence test inverted (`[ -f` → `[ ! -f`) | T0j, T0k, T0l |
| M3 | c4 guard rewritten as the rejected `&&`/`||` form | **T0l only** |
| M4 | `extract_from` narrowed to line-start | T0d |
| M5 | `affects=c4` typo'd to `c4x` | P6 closed-set |
| M6 | new unguarded producer invocation added | P6 parity |
| M7 | domain-model guard unwrapped to a bare invocation | P6 parity |
| M8 | "not with your project" attribution clause deleted | T0m |
| M9 | headless variant deleted | T0m |
