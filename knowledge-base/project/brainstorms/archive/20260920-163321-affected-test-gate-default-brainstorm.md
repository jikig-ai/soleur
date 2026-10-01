---
date: 2026-09-18
topic: affected-test-gate-default
issue: 8322
branch: feat-8322-affected-test-gate
lane: cross-domain
brand_survival_threshold: single-user incident
---

# #8322 — local test gate defaults to affected-suites + always-on ratchets; full battery is CI or `--full`

## What We're Building

Change `scripts/test-all.sh`'s default selection from "every registered suite" to "the suites a
diff can actually break, plus every repo-global property suite" — an `--affected` mode that
becomes the default local gate, with the ~46-min full battery reserved for CI (which already
shards it as the required `test` context) or an explicit `--full`.

The measured case is the issue's own: in the PR #8270 review session, 24 findings (8 P1) came
entirely from hand-run affected suites + hand-run ratchets + the review panel; the full battery
contributed zero and refused three times on sibling contention (`rc=4`). Five sibling worktrees
were serializing behind the same 46-min gate.

## User-Brand Impact

- **Artifact:** the local test gate — `scripts/test-all.sh` selection machinery and `ship`'s
  battery policy (`battery-owed.sh`, `ship/SKILL.md` Phase 4).
- **Vector:** a wrongly-narrow affected set produces a false-green local gate; for a
  non-technical operator, green *is* the trust contract — a defect that "the gate said was fine"
  is the worst-case narrative, and it ships to the installed alpha tester's plugin.
- **Threshold:** `single-user incident`.

Tagged user-brand-critical automatically per #5175.

## Why This Approach

**A — `--affected` flag + declared edge index (chosen).** A new flag at the registration
chokepoint (`_shard_selects`-adjacent, where `run_suite`/`skip_suite` already filter), consuming
a sourced edge-index data lib (`scripts/lib/test-affected-paths.sh` or an extension of
`test-relevance-paths.sh`) that follows the RELEVANCE_ARRAYS six-site idiom exactly: declared
arrays, self-inclusion, min-element floors, de-reference anchors, all enforced by
`lint-orphan-test-suites.sh` with a mutation suite. Every registration is classified
**edge-derived OR always-on**; an unclassified registration defaults to *always-run* — every
classification mistake fails toward coverage, matching `_diff_touches`'s existing fail-safe
(undeterminable diff → run everything).

Rejected:

- **B — derived forward map (the issue's literal sketch).** The six registration surfaces are a
  *reverse* mapping (suite→registration); a forward file→suite index must be *built* from argv
  literals + `source`/`import` closure + name-stem + prefix rules regardless. Building it as a
  standalone derivation beside the existing relevance machinery adds an eighth selection lever
  and is fail-deadly on missed edges — the "looks complete, is worse than today" failure the
  issue itself names.
- **C — extend relevance declines only.** ~460 per-suite `*_PATHS` declarations, never reaches
  the <5-min target, and declines still pay full registration cost.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Selection locus | `--affected` flag at the `run_suite`/`skip_suite` chokepoint; parses beside `--enumerate` before side effects | TEST_GROUP selects *which suites exist*; affected is a *slice axis* — composes multiplicatively with groups/shards/`--enumerate`. A separate entry point bypasses the runner's env guarantees (the `scripts/hooks/pre-push` mistake: basename-stem mapping, no lib fan-out, no ratchets, no TMPDIR/sandbox/exit contract). |
| Edge sources | union of: `--enumerate-commands` argv literals; suite-file self-edge; `source`/`import` closure (incl. `source "$HERE/lib/x.sh"` indirection + TS imports); name-stem convention; prefix rules for coarse registrations; new-vocabulary tokens from the diff (`SOLEUR_[A-Z_]+`, labels, enums → drift guards); cross-language subprocess consumers (`Bun.spawnSync` et al.) | Each edge class maps to a documented blind spot: lib fan-out (PR #8270's `gitleaks-probe.sh` → 4 suites), new-vocabulary drift guards (the substituted-shard-that-was-red learning), cross-language reach (`Bun.spawnSync` blast-radius learning). |
| Always-on set | **declared classification with census**, not the issue's hand list of 8 | The real whole-tree class is ~3× larger: ~24 `-live` repo-scanners + legal-corpus gates (`lint-legal-*-live`, `probe-legal-corpus-truth-live`, `check-pa-22-live`, `tenant-dpa-register-guard-live`) + credential lints + runner-SUT suites + `apps/web-platform [repo-wide+component]`. A literal list rots on the next `-live` registration (#8023/#8092/#8177). Unclassified → always-run. |
| Infra diffs | inherit `_infra_in_diff` verbatim (two prefixes, fail-safe on undeterminable) | ADR-183 Ceiling 1: `infra-validation.yml` is **not** a required check — the local battery is the *only* blocking gate for `apps/web-platform/infra/` and `apply-web-platform-infra.yml`. An infra diff MUST select the infra runner. `battery-owed.sh` already returns OWED on infra diffs — aligned. |
| Fail-safe semantics | undecidable diff → full set (announce degradation); empty derived set → UNRESOLVED/refuse, never green; non-empty floor on derived set | `_diff_touches` precedent + `MIN_TRACKED_SUITES` doctrine. A selector returning < ratchet count is broken, not a small diff. |
| Honest accounting | declines counted in the denominator (`M-k/M … N not-affected`); per-suite selection reason printed (`--print-affected-set` early-exit, no lock — the `--print-suite-globs` pattern); derived set printed before running | ADR-181's counted-decline model; "green" must never conflate "not selected" with "passed". |
| Rollout | **flip the default in one PR** (operator decision) | Operator chose direct flip over shadow-then-flip. Mitigations that make this acceptable: the selector is mutation-pinned (`test-all-affected.test.sh` with selection-narrowing mutations requiring refusal, not smaller green); every miss fails toward coverage (unclassified → run); CI's required `test` context remains the merge gate — the local run is a fail-fast checkpoint, not the gate (ADR-183 naming correction). |
| `battery-owed` semantics | OWED → run `--affected`; OWED + operator opt-in → run `--full`; SKIPPABLE → skip | New verdict dimension on the existing mutation-pinned contract suite; `42` stays the only silent skip. |
| Refusals | keep `tc_acquire` + sibling census (same tmpfs, still contends); **exempt `--affected` from the `SOLEUR_SUBAGENT=1` refusal** | The subagent refusal's advice — "run the suite covering your files" — *is* affected mode; refusing it there is incoherent. Sibling-run accounting stays run-granular (recorded limitation, not solved). |
| Caller audit (same PR) | `lefthook.yml:332` `bun-test` → inherits `--affected` (claims the #8045 win); `ship/SKILL.md:387` `TEST_GROUP=all` → `--affected` (re-pin `fullsuite-merge-gate.test.ts` to the new invariant); `grok-pre-push-gate.sh` → explicit decision (it is the Grok arm's *second* full run — pin `all` or document accepting affected); `work/SKILL.md` §9 + `ship/SKILL.md` Phase 4 docs move together; `package.json` `"test"` bare invocation becomes affected — intended | A silent semantic flip at an unflagged caller is the top blast radius; every no-args caller gets a written decision in the PR. |
| Mega-registrations | all-or-nothing v1 (`bun test plugins/soleur/`, `apps/web-platform [unit]`) | File-level refinement (`vitest related`) is a follow-up; coarse-but-correct beats precise-and-fragile. |
| Sequencing vs #8231 | **#8322 lands first; #8231 rebases** | #8231 is Phase-0-descoped and blocked on a green baseline (9 residual host-vs-CI reds). #8322 removes most of the collision surface ADR-133's lock exists for and reframes #8231's scheduler as a CI/`--full` optimization. Key both systems on the same `--enumerate` label namespace so per-registration metadata doesn't fork into two registries. Coordinate ADR ordinals — #8231's plan reserves ADR-225; this change amends ADR-181 (declines → positive selection), ADR-133 (contention machinery demoted to rare path), ADR-183 (ship full → ship affected). |
| Disclosure | `test-all.sh` header + `ship` skill state plainly: affected+ratchets does not exercise suite×suite interactions (#7442 class); CI's sharded full run is the backstop for that class | The issue's own "known limitation" requirement, extended to the whole selection mechanism — local green ≠ full coverage, ever. |

## Open Questions

1. `scripts/hooks/pre-push` (the weak basename-stem mapper): supersede by routing through
   `--affected`, or leave as documented-weak? Two affected implementations is the drift hazard;
   recommend supersede.
2. `--affected` + `TEST_GROUP` interaction: `TEST_GROUP=scripts --affected` = affected ∩
   scripts (sensible); should bare `--affected` imply `all`? (Recommended: yes.)
3. Should the sibling census count *affected* runs as siblings for a waiting full run?
   Run-granular accounting is the status quo; cost-granular is a measurement question for the
   `--capacity` instrument, recorded not solved.
4. ADR ordinal: next free number after checking #8231's reserved ADR-225 and the register.
5. `SOLEUR_TEST_FORCE_ALL=1` under `--affected`: force-full-within-affected, or is `--full` the
   spelling? (Recommended: `--full` is the spelling; FORCE_ALL degrades `--affected` → full.)

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** Right call; the false-green legibility problem is the product risk — green is the
operator's trust contract. Recommended (and adopted): coverage-receipt epilogue, caller-blast-radius
audit in the same PR, docs move together, undeterminable-diff ⇒ full, infra ⇒ infra runner, ratchet
census mutation-pinned. Flagged sequencing: do not gate on #8231.

### Legal (CLO)

**Summary:** Low direct legal exposure; no GDPR gate warranted (no regulated-data surface). The
material finding: the issue's 8-ratchet list omits the legal-corpus `-live` gates and the infra
shard is the one place the local battery is the *only* blocking gate (Art. 32 TOM-backing suites).
Recommended (and adopted): always-on = every whole-tree suite; `_infra_in_diff` inherited;
undecidable ⇒ full; contract-suite rows for legal-corpus and infra diffs.

### Engineering (CTO)

**Summary:** Directionally sound; the proposal is a generalization of ADR-181's existing machinery,
not a new system. The issue's "the index exists" is half-true — the forward map must be built
(argv literals + self + source/import closure + stem + prefix + curated always-on). Recommended
(and adopted): flag at the chokepoint, edge index in a sourced data lib, declared always-on
census, per-reason annotation, counted declines, CI structurally immune, `battery-owed` owns the
verdict dimension, ADR amends -181/-133/-183.

### Not matched

Marketing, Operations, Sales, Finance, Support — no assessment-question match for an internal
gate-policy change (`meta/machinery`).

## Prior Art Loaded

- **ADR-181** (`test-relevance-paths.sh`, `_diff_touches`, counted `skip_suite` declines) — the
  mechanism this generalizes; five `*_PATHS` arrays already ARE affected-rules for their suites.
- **ADR-133** + 6 addenda — contention machinery; demoted to the `--full` path by this change.
- **ADR-183** — moved the work-Phase-2 gate to touched shards; this is the same move one position
  later, with Ceiling 1 (infra = only blocking gate) inherited and preserved via `_infra_in_diff`.
- **#7494/PR #7495** — prior diff-gate precedent (the relevance predicates above).
- **`scripts/hooks/pre-push`** — the weak prior implementation (basename-stem only, bypasses the
  runner): existence proof of both demand and failure modes.
- **Keystone learning** `2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md`
  — ratchets are structurally unreachable by file-based selection; the "which suite population can
  this diff break" litmus.
- **Selector-completeness corpus** — substituted-shard-was-red, skipped-gate-hid-red-consumer,
  Bun.spawnSync blast radius, mutation-battery coverage limits: all encode "enumerate the universe
  and prove each non-selected suite unreachable" — the whitelist-over-blacklist invariant the
  edge index + census implements.
