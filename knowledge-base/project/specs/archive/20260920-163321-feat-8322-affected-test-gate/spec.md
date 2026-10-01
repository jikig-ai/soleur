---
feature: 8322-affected-test-gate
lane: cross-domain
brand_survival_threshold: single-user incident
refs: [8322, 8231, 8247, 8045, 7494, 7553, 6789, 6480]
brainstorm: knowledge-base/project/brainstorms/2026-09-18-affected-test-gate-default-brainstorm.md
status: draft
created: 2026-09-18
---

# Spec — Local test gate defaults to affected-suites + always-on ratchets

## Problem Statement

The local test gate (`bash scripts/test-all.sh`) runs every registered suite — ~46 min serial —
on every `work`/`review`/`ship` session. Measured on the PR #8270 review session (2026-09-18):
24 findings (8 P1) all came from affected suites + repo-global ratchets + the review panel; the
full battery contributed **zero** and was refused twice (`rc=4 CAPACITY_CONTENDED`) plus one
watcher-cap expiry over ~3 h on sibling contention. CI already shards the full battery as the required `test` context
on every merge — the local full run mostly buys contention, not coverage.

## Goals

- `scripts/test-all.sh --affected` (and as the default local mode) runs: the suites a diff can
  break (edge-derived) **plus every repo-global property suite** (always-on class), and prints
  the derived set with per-suite selection reasons before running.
- The full battery runs in CI (unchanged) or on explicit `--full`; `ship` runs `--affected` by
  default, `--full` only when `battery-owed.sh` says OWED **and** the operator opts in.
- Every selection failure mode fails toward coverage: undeterminable diff → full set; empty
  derived set → UNRESOLVED/refuse; unclassified registration → always-run.
- Honest accounting: not-selected suites are counted in the denominator (`M-k/M … N
  not-affected`), never conflated with "passed".

## Non-Goals

- Parallelizing suite execution (#8231's scheduler — this change reframes it to CI/`--full`;
  both systems key on the same `--enumerate` label namespace).
- File-level refinement inside the mega-registrations (`bun test plugins/soleur/`,
  `apps/web-platform [unit]`) — all-or-nothing v1; `vitest related` refinement is follow-up.
- Promoting `infra-validation.yml` to a required check (#6480) — inherited ceiling, preserved
  via `_infra_in_diff` rather than closed here.
- Cost-granular contention accounting (affected runs counted same as full runs in the sibling
  census) — recorded limitation, not solved.
- Cross-suite interaction detection (#7442 class) — disclosed limitation; CI's sharded full run
  is the backstop by design.

## Functional Requirements

### FR1: `--affected` flag at the registration chokepoint

Parsed beside `--enumerate` (before TMPDIR/bare-repo/`tc_acquire` side effects); filters at the
`_shard_selects`-adjacent point inside `run_suite`/`skip_suite` so declines stay counted
verdicts (ADR-181). Composes multiplicatively with `TEST_GROUP`/`SCRIPTS_SHARD`/`--enumerate`.
A `--print-affected-set` early-exit mode (the `--print-suite-globs` pattern: no lock, no side
effects) prints each selected suite with its selection reason.

### FR2: Edge index in a sourced data lib

`scripts/lib/test-affected-paths.sh` (or extension of `test-relevance-paths.sh`) following the
RELEVANCE_ARRAYS six-site contract idiom: declared arrays, self-inclusion, min-element floors,
`TEST_RELEVANCE_PREFIXES`-style prefix coverage, de-reference anchors — all enforced in
`lint-orphan-test-suites.sh` with a mutation suite. Edge sources (union): `--enumerate-commands`
argv literals; suite-file self-edge; `source`/`import` closure incl. `source "$HERE/x.sh"`
indirection and TS imports; name-stem convention; prefix rules for coarse registrations;
new-vocabulary diff tokens (`SOLEUR_[A-Z_]+`, labels, enum members → drift guards);
cross-language subprocess consumers (`Bun.spawnSync` et al.).

### FR3: Always-on classification with census

Every registration is classified edge-derived OR always-on; the always-on set covers the
issue's 8 named ratchets **plus** all whole-tree suites: the ~24 `-live` repo-scanners, legal-
corpus gates (`lint-legal-*-live`, `probe-legal-corpus-truth-live`, `check-pa-22-live`,
`tenant-dpa-register-guard-live`), credential lints, runner-SUT suites, and
`apps/web-platform [repo-wide+component]`. Unclassified registration → always-run. Census
enforced in `lint-orphan-test-suites.sh` (the RELEVANCE_ARRAYS anti-rot pattern), not a name
pattern — `-live` is a convention, not a contract.

### FR4: Fail-safe semantics

Undeterminable diff → select everything + announce degradation. Empty derived set →
UNRESOLVED/refuse, never green. Non-empty floor (derived set < ratchet count = broken selector).
`CI` env → affected filter inert (required `test` context can never be narrowed by a leaked
env). `SOLEUR_TEST_FORCE_ALL=1` → degrade `--affected` to full. `--full` is the explicit
spelling for the complete battery.

### FR5: Infra diffs select the infra runner

`_infra_in_diff` inherited verbatim (two prefixes: `apps/web-platform/infra/`,
`apply-web-platform-infra.yml`; fail-safe on undeterminable). Preserves ADR-183 Ceiling 1:
the local battery is the only *blocking* gate for the infra shard pending #6480.

### FR6: `battery-owed.sh` verdict dimension

OWED → ship runs `--affected`; OWED + explicit operator opt-in → ship runs `--full`;
SKIPPABLE (`42`, CI verified exact SHA) → skip. `ship-battery-owed.test.sh` gains mutation rows
pinning the new default in both directions, including: `docs/legal/**` diff → legal-corpus
gates selected; infra-only diff → infra runner selected; undeterminable diff → full;
`.md`-only diff → ratchets + legal gates; `plugins/soleur/test/lib/gitleaks-probe.sh`-only
diff → its four sourcing suites.

### FR7: Caller audit in the same PR

Every no-args/explicit caller gets a written decision: `lefthook.yml` `bun-test` → `--affected`
(claims the #8045 win); `ship/SKILL.md` Phase 4 → `--affected` + `fullsuite-merge-gate.test.ts`
re-pinned to the new invariant; `grok-pre-push-gate.sh` → explicit decision documented;
`work/SKILL.md` §9 + `ship/SKILL.md` Phase 4 docs move together; `package.json` `"test"`
becomes affected (intended); `scripts/hooks/pre-push` superseded by `--affected` or documented
as the weak form (decision at plan time).

### FR8: Refusal policy

`tc_acquire` + sibling census unchanged (same tmpfs). `--affected` exempted from the
`SOLEUR_SUBAGENT=1` refusal (its advice IS affected mode). The #7553 sibling-full-gate refusal
and `--capacity` preamble stay; expected to fire rarely.

### FR9: Disclosure

`test-all.sh` header + `ship` skill state plainly: affected+ratchets does not exercise
suite×suite interactions; CI's sharded full run is the backstop. Local `--affected` green is
never presented as equivalent to full coverage.

## Technical Requirements

### TR1: Selector mutation-pinned

New `scripts/test-all-affected.test.sh` (the `ship-battery-owed.test.sh` shape): mutation rows
that *narrow* the selection (drop a consumer edge, drop a ratchet, empty set, undeterminable
diff) must each produce refusal/full-fallback — never a smaller green.

### TR2: Reuse `_diff_names`/`_diff_touches` wholesale

HEAD diff + `origin/main...HEAD` + `--name-status -M` rename arms + untracked under
`TEST_RELEVANCE_PREFIXES`; `grep -qF` substring matching (over-match = run = safe).

### TR3: No enumerate-stream breakage

`--enumerate`/`--enumerate-commands` record shapes unchanged (consumed fail-closed by
`battery-tag-authorship.test.sh`, `scripts-shard-totality`); the affected enumeration emits the
same record types.

### TR4: No hardcoded suite counts

All floors derive at runtime (the `MIN_TRACKED_SUITES` pattern); every literal count in
comments is commit-keyed and marked stale-on-arrival.

### TR5: ADR + sequencing

New ADR recording the default flip — amends ADR-181 (declines → positive selection), ADR-133
(contention machinery demoted to `--full` path), ADR-183 (ship full → ship affected). Verify
the next free ordinal against #8231's reserved ADR-225 before assigning. #8322 lands first;
#8231 rebases onto it.

## Acceptance (refines the issue's sketch)

- `bash scripts/test-all.sh --affected` derives its set from the edge index + always-on
  classification and prints it (with reasons) before running.
- A `plugins/soleur/test/lib/gitleaks-probe.sh`-only diff selects its four sourcing suites —
  mutation-proven.
- A `.md`-only `knowledge-base/` diff runs the always-on set (ratchets + legal-corpus gates).
- An `apps/web-platform/infra/` diff selects the infra runner.
- `ship` runs `--affected` by default; `--full` requires OWED + opt-in;
  `ship-battery-owed.test.sh` pins it.
- Undeterminable diff → full run, announced. Empty derived set → refuse, never green.
- The #7553 refusal and contention preamble stay; `SOLEUR_SUBAGENT=1` refusal exempts
  `--affected`.
