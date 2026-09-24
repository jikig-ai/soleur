---
title: "feat: test-all local gate defaults to affected-suites + always-on ratchets; full battery is CI or explicit --full"
type: feat
date: 2026-09-18
slug: test-all-affected-gate-default
branch: feat-8322-affected-test-gate
issue: 8322
closes: 8322
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

## Overview

The local test gate (`scripts/test-all.sh`) currently runs the entire ~46-minute serial battery on every invocation. Issue #8322 makes the local default an affected-suites-plus-always-on-ratchets gate: the runner derives the suite set a change can actually move, always runs every suite whose verdict is a repo-global property, and reserves the full battery for CI or an explicit local `--full`. The `ship` workflow's local gate inherits the affected default; `battery-owed.sh` stays the mechanical authority for whether a battery is owed, with `--full` gated on operator opt-in. Selection fails toward coverage — undecidable diffs run full, unclassified registrations run always — and the derived set is printed before execution so it is reviewable.

Spec: `knowledge-base/project/specs/feat-8322-affected-test-gate/spec.md`
Brainstorm: `knowledge-base/project/brainstorms/2026-09-18-affected-test-gate-default-brainstorm.md`

## User-Brand Impact

- **Artifact:** the local test gate — `scripts/test-all.sh` selection semantics plus `/ship` Phase 4 and `/work` Phase 2 exit policy that invoke it.
- **Vector:** a wrongly-narrow affected set ships a false-green local gate and pushes defect discovery to CI or production. Mitigated by design: every selection failure fails toward coverage (undecidable → full; unclassified → always-run; empty → refuse), never toward a smaller green.
- **Threshold:** single-user incident (auto tag per #5175 — the gate is the merge-quality instrument every PR passes through).
- **Evidence base:** on PR #8270's review session, 24 findings (8 P1) came from affected suites, global ratchets, review agents, and direct probes; the full battery contributed zero findings and was refused 3× over ~3 h on sibling contention (`rc=4`, `CAPACITY_CONTENDED reason=sibling_runs`).

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Verified? | Notes |
|---|---|---|
| `run_suite`/`skip_suite` are the registration chokepoint | Yes | `test-all.sh:905`, `:1067`; both gate on `_shard_selects || return 0` (`:835-842`) then enumerate-dispatch then `suites++`. |
| Early flag parsing exists before side effects | Yes | Four `$1` flags only: `--print-suite-globs` (`:96`), `--capacity` (`:121`), `--enumerate` (`:175`), `--enumerate-commands` (`:178`) — all before TMPDIR/bare-repo/`tc_acquire`. No `--help`. |
| Diff machinery reusable wholesale | Yes | `_diff_names` (`:1133-1162`): HEAD diff + `origin/main...HEAD` + `--name-status -M` + untracked under `TEST_RELEVANCE_PREFIXES`; `_diff_touches` (`:1173-1201`) substring `grep -qF` with `CI`/`SOLEUR_TEST_FORCE_ALL`/fail-safe arms; `_infra_in_diff` (`:1207-1221`) two-prefix + fail-safe. |
| Six-site relevance contract is the enforcement idiom | Yes | `scripts/lib/test-relevance-paths.sh:10-26` — declared `*_PATHS` arrays + `RELEVANCE_ARRAYS` registry + prefix coverage + `GATED` list in `scripts/test-all-infra-coverage-notice.test.sh` + `lint-orphan-test-suites.sh`. |
| Always-on class ≫ issue's list of 8 | Yes | ~49 candidates: ~24 `-live` repo-scanners, ~19 runner-SUT suites, ~5 credential/path lints, plus repo-wide+component web-platform arms and legal-corpus gates. |
| `_infra_in_diff` must be inherited | Yes | ADR-183 Ceiling 1: `infra-validation.yml` is not a required check — the local battery is the only blocking gate for `apps/web-platform/infra/`. |
| `battery-owed.sh` contract | Yes | `42`=SKIPPABLE / `0`=OWED / `2`=UNDECIDABLE(treat as OWED) / other=OWED; stdout `battery-owed:` single-line sanitized verdict; callers treat not-42 as run (`battery-owed.sh:4-8,21-23,40-42,388`). |
| Enumerate consumers fail closed | Yes | `battery-tag-authorship.test.sh:224,250`, `scripts-shard-totality.test.sh:92-97,316-357`, `lint-orphan-test-suites.sh:229` (`--print-suite-globs`). |

### Inventory corrections the spec needed

- ~226 explicit `run_suite` callsites plus glob/mega registrations — ~440 total registrations, not the handful the issue implies. The edge index must be *mostly derived*; a per-registration declaration mandate (~440 records) is the C-approach burden we rejected. Declarations exist only for edges derivation cannot reach.
- Two on-disk test files with no obvious `run_suite` registration: `tests/scripts/test-sentry-brownout-retry.sh`, `tests/hooks/test_drop_sentinel_parity.sh` — feed to the orphan-lint check; do not silently ignore.
- `main-health-monitor.yml:309` invokes `bash scripts/test-all.sh` bare (and `:323` `TEST_GROUP: infra`) — a CI caller whose "bare" invocation must not silently become affected (inert under `CI` env — confirmed; still must appear in the caller audit).
- `fullsuite-merge-gate.test.ts` pins three separate surfaces of the current contract: the `"Then run the project's full test suite."` literal (`ship/SKILL.md:336`, pinned `:55,210-219`), a CEILING asserting every Phase 4 fenced invocation is unsharded (`:179-189`), and a FLOOR requiring `/work` §9 prescribe ≥1 sharded invocation and zero unsharded (`:230-253`). All three re-pin in this PR.
- `lefthook-bun-test-merge-skip.test.sh:26` pins the exact lefthook run-string — re-pin with the hook change.
- `fanout-suite-scope.test.sh:144-465` drives the real runner for refusal guards — SOLEUR_SUBAGENT exemption changes touch it.
- Sandboxed-runner suites (`test-all-killed-classification`, `test-all-runtime-ceiling`, `test-all-infra-coverage-notice`, `test-all-capacity-signal`) copy/patch `test-all.sh` — they are in the always-on class and will self-select on this diff; expect edits where they assert runner internals.

## Research Insights

### Premise validation (Phase 0.6)

- #8322 OPEN; #8231 sibling is OPEN draft PR #8270 (Phase-0-blocked on a 20-red baseline, weeks out) — #8322 lands first, #8231 rebases. Property holds; proceed.
- All cited artifacts exist on `origin/main`: `test-all.sh` TEST_GROUP partitioning, `battery-owed.sh` + contract suite, `_diff_*` machinery, `RELEVANCE_ARRAYS` idiom.
- **Mechanism minimality cut list** (Phase 0.6b, already decided in brainstorm): `TEST_GROUP=affected` value — cut (orthogonal axis); separate entry-point runner — cut (bypasses env/lock/sandbox/exit contracts); source-closure-only derivation — cut (misses argv literals); decline-only extension of all relevance arrays — cut (never reaches <5 min); shadow-mode rollout — cut (flip in one PR).

### Property list (what the change must guarantee)

1. **Fail-toward-coverage:** no mutation of the index, derivation, or diff detection produces a *smaller* selected set silently — narrowing faults refuse or degrade to full.
2. **Classification totality:** every registration is classified edge-derived OR always-on; unclassified runs (runtime) and census-flags (lint).
3. **Counted declines:** a suite assigned to this run but not selected is a counted verdict — denominator `M-k/M`, `N not-affected` disclosed.
4. **Orthogonality:** composes multiplicatively with `TEST_GROUP`, `SCRIPTS_SHARD`; enumerate streams are unaffected (registry enumeration ≠ selection).
5. **Contract preservation:** `SUITE_REGISTRATION`/`SUITE_COMMAND`/`SUITE_COMMAND_DECLINED` record shapes unchanged; `_infra_in_diff`, `tc_acquire`, sibling census, refusal arms unchanged except the affected exemption.

### Always-on classification (census-derived, not hand list)

Predicate: *the suite's verdict is a property of the whole tree, not of a diff* — repo-wide scanners, whole-corpus legal gates, runner-SUT suites (the runner is always its own SUT here), credential/path lints. Candidate set from inventory (~49): ~24 `*-live` scanners (`lint-legal-*-live`, `probe-legal-corpus-truth-live`, `check-pa-22-live`, `tenant-dpa-register-guard-live`, credential scanners), ~19 runner-SUT suites (`test-all-*.test.sh`, `fanout-suite-scope`, `scripts-shard-totality`, `battery-tag-authorship`, `preflight-check10-suite-integrity`), ~5 credential/path lints, repo-wide+component web-platform arms. **The lib declares the set; a lint census re-derives membership from the predicate and floors it** (`|ALWAYS_ON| ≥ count(*-live)` registrations — the name convention is the independently-derived anchor).

### Edge index — derived-first, declared-for-the-gaps

`scripts/lib/test-affected-paths.sh` — **declarations only** (same doctrine as `test-relevance-paths.sh` — the linter sources it):

- `ALWAYS_ON_SUITES=( label … )` — census classification.
- `AFFECTED_<LABEL>_PATHS=( prefix|glob … )` — declared edges where derivation cannot reach: mega-registrations (`bun test plugins/soleur/` → `plugins/soleur/**`), coarse prefix rules (`apps/web-platform [unit]` → reuse `WEBPLAT_APP_PATHS`), cross-language subprocess consumers (`Bun.spawnSync`).
- Self-inclusion doctrine: every declared array includes the suite file and `test-affected-paths.sh` itself.
- Header carries the same "how to add a classification" contract block as `test-relevance-paths.sh:10-26`, and **each lib points at the other** — a suite author landing in either learns the whole model.

**Reuse, don't re-declare:** the five existing `*_PATHS` arrays (`REGISTRY_BATTERY_PATHS`, `CF_TUNNEL_BATTERY_PATHS`, `C4_PRODUCER_PATHS`, `GITHUB_SCRIPTS_SUITE_PATHS`, `WEBPLAT_APP_PATHS`) are already-declared edge sets for exactly the suites derivation cannot reach (e.g., the registry battery *copies* SUTs into a sandbox — source closure never sees them). The edge index **consumes** them; a parallel `AFFECTED_*` copy of the same dependency set would drift — the hazard the six-site contract exists to prevent. Corollary: under `--affected`, the relevance-decline wrappers and edge non-selection coincide on the same predicate — the relevance axis is semantically subsumed; the `skip_suite` wrappers are kept *only* to preserve `SUITE_COMMAND_DECLINED` enumerate records (property 5). State this in the lib header so the dual axis doesn't read as accidental.

**CUT for v1 — vocabulary-token edges (`AFFECTED_TOKEN_SUITES`, diff-introduced `SOLEUR_[A-Z_]+`/label/enum tokens).** Both review panels converged: this is the only edge source requiring diff *content* (`_diff_names` carries paths only — a second `git diff` channel), and it only *narrows*: token-scanning suites left unclassified already run via the unclassified→always-run arm, so coverage needs nothing here. Deviates from spec FR2's edge-source union — coverage is preserved by the fail-safe; land later only if misses are observed.

**Derived edges** (computed once in the preamble, no declaration cost): suite-file self-edge from argv literals (argv stream obtained via a **nested `$0 --enumerate-commands` self-call** — reuses the `SUITE_COMMAND` contract and is never affected-filtered; the registration stream cannot be read statically at preamble time); bash `source`/`.` closure and TS `import` closure over suite files (reverse file→suites map, bounded depth, memoized, **must resolve variable indirection** — `source "$HERE/lib/x.sh"` is the dominant pattern); name-stem convention (`<x>.test.sh`→`<x>.sh`, `test-<x>.sh`→`<x>`). Confidence ordering — each added rule only *shrinks* the selected set, so false-green surface lives in the weaker rules: self-edge > name-stem > source/import closure.

### Diff semantics (TR2 — reuse, do not extend)

`_diff_names` + `_diff_touches` wholesale: HEAD + `origin/main...HEAD`, `--name-status -M` renames, untracked under `TEST_RELEVANCE_PREFIXES`, `grep -qF` substring. Over-match safe, under-match unsafe. `_diff_detect_ok=0` → degrade to full + announce. `_infra_in_diff` inherited verbatim → infra runner selected.

### Caller blast radius (complete census — agent-verified)

| Caller | Invocation today | This PR |
|---|---|---|
| `lefthook.yml:311-332` `bun-test` | `SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh` | `bash scripts/test-all.sh --affected` — override drops because affected is refusal-exempt by construction, not because the refusal vanished (the #8045 cost site: 3667 s → <5 min) |
| `ship/SKILL.md:387` Phase 4 | `TEST_GROUP=all bash scripts/test-all.sh` | explicit `/ship --full` → `bash scripts/test-all.sh --full` (outranks SKIPPABLE); else OWED/not-42 → `bash scripts/test-all.sh --affected` |
| `ship/SKILL.md:336,441,489` | "full test suite" literal; detached `TEST_GROUP=all`; Phase-5 checklist literal | prose re-pin (see `fullsuite-merge-gate.test.ts` below) |
| `work/SKILL.md:945-947` §9 | three `TEST_GROUP=<g> bash scripts/test-all.sh` invocations | single `bash scripts/test-all.sh --affected`; §9 shard-map prose rewritten — the runner now derives "which suites gate my diff" itself; also fix the now-false "the lead runs this gate, not a delegate" (`:1011-1015` — `SOLEUR_SUBAGENT`+affected is allowed, so the gate IS delegatable) and state that `TEST_GROUP=<g>` spellings now compose with explicit-ask semantics |
| `grok-pre-push-gate.sh:165` | `env SOLEUR_ALLOW_FULL_GATE=1 bash scripts/test-all.sh` | `bash scripts/test-all.sh --affected` — push-time gate = affected coverage; also re-label the step ("test-all (CI test aggregator)" / "sanctioned full-gate run" comments misdescribe an affected run) |
| `scripts/hooks/pre-push` | basename-stem mapper (opt-in `core.hooksPath`) | **supersede**: body → `bash scripts/test-all.sh --affected`; kills the second selection implementation (drift hazard). Keep the bun-absent + empty-diff graceful skips before delegating; re-write the header — the hook swaps seconds-scale file-level tests for a minutes-scale suite-level gate, and it is now refusable (full mode only — affected is exempt) |
| `package.json:5` | `"test": "bash scripts/test-all.sh"` | unchanged — bare invocation defaults to affected locally (document in audit) |
| `ci.yml:914,942,1222` | `bash scripts/test-all.sh <group>` | unchanged — `CI` env makes the filter inert |
| `main-health-monitor.yml:309,323` | bare + `TEST_GROUP: infra` | unchanged — `CI` env inert (documented; monitor wants full coverage and gets it) |
| `one-shot/SKILL.md:25` | invokes `grok-pre-push-gate.sh` | inherits the gate's change; prose check |

### Test/pin re-specification

- `plugins/soleur/test/fullsuite-merge-gate.test.ts` — pins move to the new invariant: imperative literal (`:55,210-219`) → `--affected` prescription; CEILING (`:179-189`) → every Phase 4 battery invocation carries `--affected` or `--full`; FLOOR (`:230-253`) → `/work` §9 prescribes ≥1 `--affected` invocation. **Detector changes too**: `--print-affected-set` joins `QUERY_FLAGS` (`:131`) or a print-mode line satisfies a battery floor; `shardTokensOn` (`:137-164`) must learn the mode flags or `--affected`/bare narrowing spellings are invisible to it.
- `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh:26` — run-string re-pin.
- `plugins/soleur/test/fanout-suite-scope.test.sh:144-465` — refusal arms re-pin for BOTH arms: `SOLEUR_SUBAGENT=1` + `--affected` → allowed; + `--full` → rc=4; sibling-run + `--affected` → allowed; sibling + `--full` → rc=4; degraded-to-full under `SOLEUR_SUBAGENT` → rc=4.
- `plugins/soleur/test/ship-battery-owed.test.sh` — contract unchanged (script unchanged); gains rows pinning the script's documented consumer contract (OWED→`--affected`, opt-in→`--full`, not-42→run). Recorded deviation: spec FR6 names this suite for selection-example rows — those live in `test-all-affected.test.sh` instead (this suite tests the rc contract, not the selector); `docs/legal/** → legal gates` is covered implicitly because those gates are always-on (comment this).
- `plugins/soleur/skills/ship/scripts/battery-owed.sh` — header re-word only: OWED routes to `--affected`, not "a full local run".
- Sandboxed runner-SUT suites — re-baseline where they copy `test-all.sh` internals (≥7 lib-mirror sites; the missing-lib degrade arm keeps them working).

## Proposed Solution

### Flag semantics (FR1)

Parsed at `test-all.sh:175-211` — before TMPDIR, bare-repo guard, TEST_GROUP validation, `tc_acquire`. **Parsing becomes a `while` loop over leading flags** (not the current single `$1` `if/elif`): mode flags can appear in any order and combine with the positional group; after flag consumption `(( $# > 1 ))` → exit 2. This closes the silent-narrowing hole (`bash test-all.sh scripts --full` today would leave `--full` unread in `$2` and run affected∩scripts — narrower coverage presented as wider). `--affected --full` together → explicit conflict error, exit 2. A new `--help`/`-h` early-exit (same discipline as `--print-suite-globs`) prints the flag/env table, and the `:621` usage line is expanded to name the mode flags — the runner gains 7 flags + ~8 env levers and today has no discovery surface.

| Invocation (local) | Meaning |
|---|---|
| `bash scripts/test-all.sh` | **affected** — the new default; all-scope × affected set |
| `bash scripts/test-all.sh --affected [<group>]` | affected ∩ scope (all, or the given group) |
| `bash scripts/test-all.sh <group>` (non-`all`, positional or `TEST_GROUP`) | **explicit ask: the group's registrations run** — the affected filter governs the `all` scope only. This preserves the existing explicit-ask contract (`:607-611`, infra's bypass arm) and makes `TEST_GROUP=infra` honest rather than green-over-zero (see P0 below). `--affected <group>` is the spelling for the narrow form. |
| `bash scripts/test-all.sh --full [<group>]` | complete battery (group if given): affected filter off **and** relevance declines defeated — `--full` sets the same early-return `CI`/`SOLEUR_TEST_FORCE_ALL` set in `_diff_touches` **and** conjuncts into the infra arm (`:2797`) so `--full` ≥ today's `TEST_GROUP=all`+FORCE_ALL (the retired middle mode — all-groups-with-declines-intact — is documented as gone: `--full` runs strictly more than yesterday's default). |
| `--print-affected-set` | a **third enumerate-family mode** (see below) — NOT an early-exit; exit 0. |
| `SOLEUR_TEST_FORCE_ALL=1` under `--affected` | degrades to full (announced) — FORCE_ALL remains the session-wide "run everything" lever; `--full` is the per-invocation spelling (relationship stated once in the header). |
| `CI` env | affected filter inert regardless of flags |
| `--enumerate`/`--enumerate-commands` | **never** affected-filtered — enumerate answers "what is registered"; derivation cost is skipped entirely in enumerate mode (consumers invoke it repeatedly). Record this interpretation in the ADR (spec FR1's "composes with --enumerate" is ambiguous vs TR3). |

**`--print-affected-set` is enumerate-shaped, not early-exit-shaped** (three panels converged): the label universe only exists once registrations flow through the chokepoint — an early exit prints nothing, and a separate static derivation would be a second selector (the defect class this PR removes from `scripts/hooks/pre-push`). Shape: `_PRINT_AFFECTED=1` + `_ENUMERATE=1` plumbing — `SOLEUR_DISABLE_SESSION_STATE=1`, refusal/`tc_acquire`/`tc_preamble` exemptions via the existing `_ENUMERATE == 0` conjuncts, per-registration `AFFECTED_CLASS <label> <class> <reason>` lines emitted at the chokepoint, terminate at the enumerate terminator (`:2879`). It must also join `fullsuite-merge-gate.test.ts`'s `QUERY_FLAGS` (`:131`) so a print-mode fenced line can't satisfy a battery floor. Output contract: prints *selection class + resolved verdict* (a suite can be affected-selected yet still relevance-declined — the print folds the decline predicates so it shows what would actually run), composes with a group arg the same way a run does.

### Selection at the chokepoint (FR3/FR5)

**No `declare -A` — bash 3.2 is a platform contract** (`:300`, `:769-771`, `:2740`; macOS `/bin/bash` is the lefthook caller's shell). The membership map uses the file's own idioms: an indexed array keyed by the registration ordinal `_shard_ordinal` (`:836`), or the linter's pipe-delimited + `eval`-by-name idiom (`lint-orphan-test-suites.sh:583-606`) — never associative arrays.

Classification is computed **lazily per-registration at the chokepoint** (the argv stream for self-edges comes from a nested `$0 --enumerate-commands` self-call — see edge index), with `_affected_class_of <label> <argv…>` consulted once per registration and memoized in the indexed arrays:

1. Always-on membership → selected, reason `always-on`.
2. Diff file matches a declared/derived edge (incl. the five consumed `*_PATHS` arrays) → selected, `edge:<path>`.
3. `_infra_in_diff` → infra runner selected, `infra-diff`. **The infra label is positively classified edge-derived** (edges = the two infra prefixes) — it must never fall through to unclassified→always-run, or the ~15-min infra runner executes on every gate and inverts the <5-min goal.
4. **Explicit non-`all` group ask** → group memberships selected, `group:<g>` (the `TEST_GROUP=infra` P0 fix).
5. **Runner/index self-edge**: `scripts/test-all.sh` or `scripts/lib/test-affected-paths.sh` in the diff → full set (`AFFECTED_FALLBACK reason=runner-changed`) — the runner is its own registry's SUT; a repointed `run_suite` argv can't under-select.
6. Unclassified (no edge, not always-on) → **selected**, `unclassified` (fail toward coverage) + surfaced via `--print-affected-set` for the census.
7. Selection receipt: per-registration `AFFECTED_CLASS` lines emitted as each label is classified (there is no whole-set preamble table — the label universe only exists as registrations flow; `--print-affected-set` is the whole-set surface). A loud `MODE=affected|full` banner prints at run start.

Then in the chokepoints (illustrative, not verbatim):

```bash
run_suite() {
  local label="$1"; shift
  _shard_selects || return 0
  if (( _ENUMERATE == 1 )); then _shard_enumerate_dispatch "$label" "$@"; return 0; fi
  if ! _affected_selected "$label"; then
    <counted decline — same emit tail as skip_suite: suites++, skipped++,
     [skip] <label> (not-affected), rerun "bash scripts/test-all.sh --full">
    return 0
  fi
  suites=$((suites + 1)); …
}
```

```bash
skip_suite() {
  local label="$1" reason="$2" rerun="$3"
  _shard_selects || return 0
  if (( _ENUMERATE == 1 )); then _shard_enumerate_declined_dispatch "$label" "$rerun"; return 0; fi
  if ! _affected_selected "$label"; then reason="not-affected"; rerun="bash scripts/test-all.sh --full"; fi
  suites=$((suites + 1)); skipped=$((skipped + 1)); …
}
```

Ordering is load-bearing: `_shard_selects` first (it maintains the shard ordinal — a non-selected suite must not shift leg membership), then the enumerate short-circuit (enumerate is never affected-filtered), then the affected check as a **counted** decline (shard non-selection is invisible; affected non-selection is a verdict — the key semantic difference). A doubly-declined suite (relevance + not-affected) reports `not-affected` — the outermost selection axis wins the reason (note `_relevance_declined` increments at the *callsite* before `skip_suite` rewrites the reason — the two counters coexist; comment this).

Decline emit details (Kieran/CTO/DHH converged):
- **Distinct counter**: `_affected_declined`, separate from `_relevance_declined` — the epilogue `N not-affected` is its own class, not folded into "declined — not relevant to this diff" (`:3058`).
- **Compact emit**: ~390 not-affected declines per run would print ~2000 lines with `skip_suite`'s 5-line block — not-affected uses a one-line `[skip] <label> (not-affected)`; relevance/incident declines keep the full block.
- **Rerun hint**: `skip_suite` keeps the suite's *original* rerun string and *appends* the `--full` alternative — overwriting it would replace a seconds-long direct-suite re-run with a 46-min suggestion.
- **Zero-executed refusal**: mirror the shard zero-assignment refusal (`:2862-2867`) — a run whose affected∩scope intersection executes zero suites refuses `AFFECTED_UNRESOLVED`, never exits 0 over near-nothing (covers the `TEST_GROUP=infra` green-over-zero arm and foreign-group diffs).

### Failure semantics (FR4/FR5)

- Degrade to full on **either** diff flag — `_diff_detect_ok == 0` **or** `_diff_head_ok == 0` (`:1195`; the HEAD arm fails independently under `index.lock` contention — the realistic parallel-worktree case — and carries uncommitted work): `AFFECTED_FALLBACK reason=undecidable-diff`. Also: runner/index diff → `reason=runner-changed`; missing/unparseable `test-affected-paths.sh` → `reason=index-missing` (**degrade, not hard-fail** — a `_REL_LIB`-style exit-2 would kill ≥7 sandboxed runner-SUT copies; the lint census sources the lib directly and remains the hard-fail layer).
- Below the floor → refuse `AFFECTED_UNRESOLVED`, **exit 3** (distinct from 2 usage / 4 refused; verify against the exit-class table in `test-fix-loop`). Floor = count of `*-live` labels in the **live `--enumerate-commands` stream** — never `${#ALWAYS_ON_SUITES[@]}` (self-referential: a shrunken array would shrink its own floor).
- Refuse/degrade arms are **gated on executing mode** — they must never fire under `--enumerate*`/`--print-affected-set` (fail-closed consumers run those inside the advisory lock).
- Untracked-file arm: use **unscoped** `git ls-files --others --exclude-standard` (not just `TEST_RELEVANCE_PREFIXES`) — new suites in `tests/hooks/`, `apps/cla-evidence/` etc. are otherwise invisible; strictly safer, near-zero cost.
- `bash -c '…'` argv bodies: argv-literal extraction greps *inside* `-c` strings (`:2593-2598`, `:2640`) or those self-edges vanish.
- `SOLEUR_SUBAGENT=1` + degraded-to-full → **re-evaluate the refusal** post-derivation → rc=4 (the refusal keys on *effective* full, not argv — closes the FORCE_ALL/undecidable-diff bypass).

### Refusal policy (FR8) — resolved: affected is exempt from **both** arms

Three panels independently found the contradiction: dropping `SOLEUR_ALLOW_FULL_GATE` while keeping the sibling census unchanged leaves lefthook/grok/pre-push refusable — `git commit` blocked during any sibling gate (the exact #8270 pain). Resolution: **affected mode is exempt from both refusal arms** — the `SOLEUR_SUBAGENT` refusal (`:690`) *and* the sibling-census refusal (`:1379`, same `_ENUMERATE`-style conjunct). Rationale: the refusal's own advice ("run the suite covering your files") *is* affected mode; the sibling arm's rationale (46-min timing inflation) is weak for a <5-min run; and affected runs remain counted in the sibling census (a `--full` ask still refuses rc=4 during any sibling run). This is a *change* to FR8's "unchanged" wording — recorded as the resolved design. `SOLEUR_ALLOW_FULL_GATE` continues to override full-mode refusals (lefthook drops it only because affected is now exempt by construction); refusal advice strings are updated to name `--full`.

### Ship dispatch (FR6)

```bash
bash …/battery-owed.sh; rc=$?
if <operator asked --full>; then bash scripts/test-all.sh --full      # explicit ask outranks SKIPPABLE
elif [[ "$rc" -eq 42 ]]; then echo "battery SKIPPED: CI verified this exact SHA (#8247)"
else bash scripts/test-all.sh --affected; fi                          # OWED + UNDECIDABLE + errors
```

Opt-in spelling: **`/ship --full` only** (composes with existing `--headless` parsing). `SOLEUR_SHIP_FULL=1` dropped — one spelling; `SOLEUR_TEST_FORCE_ALL=1` documented as the session-wide escape hatch. Undecidable/error → owed → affected. `battery-owed.sh`'s header ("owes a **full** local run") is re-worded in the same PR — OWED now routes to `--affected`. Disclose in Phase 4: affected green ≠ full coverage; CI's sharded `test` context remains the merge gate.

## Files to Create

- `scripts/lib/test-affected-paths.sh` — declarations only (ALWAYS_ON census, `AFFECTED_*_PATHS` edge arrays, prefix rules; token edges CUT — see §Edge index); self-inclusion doctrine; how-to header + cross-reference to `test-relevance-paths.sh`.
- `scripts/test-all-affected.test.sh` — selector mutation suite (TR1); itself registered always-on.
- `knowledge-base/engineering/architecture/decisions/ADR-227-local-test-gate-affected-default.md` — provisional ordinal; **re-verify free at creation time** (225/226/228 claimed on sibling branches).

## Files to Edit

- `scripts/test-all.sh` — `while`-loop flag parsing + `--help` + `$#` guard (`:175-211`, `:621`), `_affected_*` classification beside `_diff_*` (`:1133-1221`), chokepoint filter + `_affected_declined` (`:905`, `:1067`), refusal exemptions on **both** arms (`:690`, `:1379`) + post-derivation effective-full re-check, infra arm `_FULL` conjunct (`:2797`), missing-lib degrade, `MODE=` banner, epilogue `N not-affected` + lever re-point (`:3058-3112` region), header/usage disclosure — **bash 3.2 only, no `declare -A`**.
- `scripts/lint-orphan-test-suites.sh` — classification census consuming `--print-affected-set` + `*-live` floor anchor + repo-wide-idiom grep arm; resolve the two unregistered `test-*.sh` files (register — preferred — or tracked exclusion; note the `git ls-files '*.test.sh'` producer won't see `test-*.sh` names).
- `plugins/soleur/skills/ship/SKILL.md` — Phase 4 dispatch, detached-launch literal, Phase-5 checklist, interpretation/disclosure block.
- `plugins/soleur/skills/work/SKILL.md` — §9 touched-shard gate → single `--affected` invocation + prose.
- `plugins/soleur/scripts/grok-pre-push-gate.sh:165` — `--affected`.
- `lefthook.yml:332` — `--affected` (drop `SOLEUR_ALLOW_FULL_GATE` — affected is refusal-exempt by construction).
- `scripts/hooks/pre-push` — supersede body → `--affected` wrapper.
- `plugins/soleur/test/fullsuite-merge-gate.test.ts` — three re-pins (above).
- `plugins/soleur/test/lefthook-bun-test-merge-skip.test.sh` — run-string re-pin.
- `plugins/soleur/test/fanout-suite-scope.test.sh` — refusal arms for the exemption.
- `plugins/soleur/test/ship-battery-owed.test.sh` — consumer-contract rows.
- Sandboxed runner-SUT suites as internals assert (`test-all-killed-classification`, `test-all-runtime-ceiling`, `test-all-infra-coverage-notice`, `test-all-capacity-signal`) — re-baseline only where they pin affected-relevant internals.
- `package.json` — unchanged (bare = affected; record in audit, no edit).

## Implementation Phases

**Phase 0 — preconditions.** Re-run insertion-point greps (chokepoint/flag-parse/`_diff_*` anchors); run live `bash scripts/test-all.sh --enumerate-commands` + `--enumerate scripts` to confirm registration counts (static inventory is estimate-bounded); re-verify ADR-227 free across `git branch -a`/`git tag`.

**Phase 1 — declarations + census (RED first).** `scripts/lib/test-affected-paths.sh` (always-on set, declared edges, token edges, prefix rules). Census rows in `lint-orphan-test-suites.sh`: every enumerated registration classified edge-derived or always-on; `|ALWAYS_ON| ≥ count(*-live)` floor; unclassified → RED listing the label. RED: census fails on the unclassified residue before Phase 2 lands the derivation that classifies it.

**Phase 2 — runner mechanics (TDD: `test-all-affected.test.sh` RED → implementation GREEN).** Flags; `_diff_names` consumption + edge derivation preamble; `_affected_selected`; chokepoint counted declines; fallback/refuse arms; `--print-affected-set`; refusal exemption; epilogue `N not-affected`; header disclosure.

**Phase 3 — caller audit + pin re-spec.** lefthook, ship, work, grok gate, pre-push supersession; `fullsuite-merge-gate.test.ts`, `lefthook-bun-test-merge-skip.test.sh`, `fanout-suite-scope.test.sh`, `ship-battery-owed.test.sh` rows; sandboxed SUT re-baselines.

**Phase 4 — ADR-227 + disclosure.** New ADR (amends ADR-181 declines→positive selection, ADR-133 contention machinery demoted to the rare full path, ADR-183 ship default). Header + `/ship` prose: affected+ratchets does not test suite×suite interaction; CI's sharded full run is the backstop; local affected green ≠ full coverage.

**Phase 5 — verification.** Mutation matrix (below) executed; enumerate consumers green; caller pin suites green; `lint-orphan-test-suites.sh` green; live `--print-affected-set` on this diff reviewed by a human before push.

## Observability

This is dev tooling, not production infra — the observable surface is the gate's own output and its lint/mutation guardians.

- **liveness_signal:** `lint-orphan-test-suites.sh` census runs every CI `scripts` leg (classification can't silently rot); `test-all-affected.test.sh` is registered always-on (selector correctness re-verified on every local gate + CI).
- **failure_modes:** undecidable diff / runner-changed / index-missing → `AFFECTED_FALLBACK` + full set; below-floor or zero-executed set → `AFFECTED_UNRESOLVED` rc=3; unclassified registration → runs + census RED; `SOLEUR_SUBAGENT`/sibling + `--full` or degraded-full → rc=4 (affected exempt); trailing positional flags → exit 2; `--affected --full` → exit 2.
- **logs/traces:** `MODE=affected|full` banner at run start; per-registration `AFFECTED_CLASS <label> <class> <reason>` receipt lines as each label is classified (no whole-set preamble table — labels only exist as registrations flow); compact `[skip] <label> (not-affected)` decline lines with `--full` rerun hint; epilogue `M-k/M … N not-affected` (distinct `_affected_declined` counter) and the recovery lever re-pointed to `--full`.
- **dashboards/metrics:** none — local gate output is the artifact; CI backstop unchanged.
- **discoverability_test.command:** `bash scripts/test-all.sh --print-affected-set`
- **discoverability_test.expected_output:** classification table (`always-on`/`edge`/`derived`/`unclassified-run` tokens present) or the `AFFECTED_FALLBACK` degrade banner — both are success-shaped.

## Guard Contract

**Guard 1 — always-on census** (`scripts/lint-orphan-test-suites.sh`)
- **Property:** every registration is classified edge-derived or always-on; a new suite cannot merge silently unclassified; a *misclassified* whole-tree suite cannot silently become declinable.
- **Assembly:** the census **consumes `--print-affected-set` output** (the linter's own doctrine — "a contract, not a parse" — it asks the runner, never re-implements the classifier) plus the `-live` floor computed over `--enumerate-commands` labels. Second arm: **repo-wide-idiom grep** — suite sources matching `git ls-files` without pathspec, `grep -r`, `find .` must appear in `ALWAYS_ON` or carry a declared edge (mechanical over-approximation of the whole-tree predicate; the self-edge-only class is the danger — every suite gets a self-edge, so derivation alone can't distinguish a scanner). `--print-affected-set` also surfaces `unclassified` rows for human audit.
- **Anchor:** the `-live` naming convention in the live registration stream — `|ALWAYS_ON| ≥ count(*-live)`, floor derived from `--enumerate-commands` (never the array's own size).
- **Mutation matrix:** (a) add a registration with no classification → RED naming it; (b) neuter the classifier (classify zero) → RED via floor/vacuity; (c) second unclassified registration after a classified first → RED (quantifies over ALL); (d) move an always-on suite to edge-derived with no edges → RED; (e) register a suite whose body runs `git ls-files` unscoped but classify it edge-derived → RED via the idiom grep.

**Guard 2 — selector fail-safe** (`scripts/test-all-affected.test.sh`)
- **Property:** no mutation to the index/derivation/diff-detection produces a smaller selected set silently — narrowing faults refuse or degrade to full.
- **Assembly:** `_affected_class_of` + edge derivation + refuse/degrade arms + the `-live` floor.
- **Anchor:** behavioral rows pin *named labels* — `plugins/soleur/test/test-helpers.sh` is the real multi-consumer edge (~51 sourcing suites; **replaces the spec's `gitleaks-probe.sh` example, which does not exist on this branch** — it was a #8270 artifact; synthesized fixtures per `cq-test-fixtures-synthesized-only` where a real edge doesn't fit), so removing an entry a row names → RED.
- **Mutation matrix:** (a) delete a `test-helpers.sh` consumer edge → its sourcing suites still selected or run refuses — never a smaller green; (b) truncate the edge index to zero → `AFFECTED_UNRESOLVED` (rc=3); (c) undeterminable diff → full set + `AFFECTED_FALLBACK` — *both* flag arms (`_diff_detect_ok`, `_diff_head_ok`); (d) remove an always-on entry → census RED + suite still runs (unclassified→always-run); (e) drop the second element of a two-path declared edge → second path still selects or row fails; (f) `test-helpers.sh`-only diff → its sourcing suites + always-on; (g) `.md`-only KB diff → always-on + legal gates only; (h) `apps/web-platform/infra/` diff → infra runner selected; (i) explicit `TEST_GROUP=infra` on non-infra diff → infra runner **runs** (P0 regression row — no green-over-zero, no false `_infra_ran`); (j) `--enumerate` under affected → full registry stream; (k) `--print-affected-set` → `AFFECTED_CLASS` lines, no lock, exit 0; (l) `SOLEUR_SUBAGENT=1 --affected` → runs; `--full` → rc=4; sibling + `--affected` → runs; sibling + `--full` → rc=4; degraded-full under `SOLEUR_SUBAGENT` → rc=4; (m) non-empty-below-floor set (always-on membership neutered, edges still select) → `AFFECTED_UNRESOLVED`; (n) trailing flag `test-all.sh scripts --full` → exit 2, never silent-narrow; (o) missing `test-affected-paths.sh` → `AFFECTED_FALLBACK reason=index-missing`, full set; (p) `scripts/test-all.sh` in diff → `reason=runner-changed` full set.

**Guard 3 — ship/caller dispatch pin** (`fullsuite-merge-gate.test.ts`, `lefthook-bun-test-merge-skip.test.sh`)
- **Property:** `/ship` Phase 4 invokes `--affected` by default and `--full` only behind the explicit `/ship --full` ask; the lefthook commit gate invokes `--affected`.
- **Assembly:** `ship/SKILL.md` dispatch block + lefthook run-string + the pin suites (+ `QUERY_FLAGS`/detector updates).
- **Anchor:** the pins assert invocation *shape* (flag presence + opt-in gating), not counts — a prose reword that drops the flag is RED.
- **Mutation matrix:** (a) flip Phase 4 back to `TEST_GROUP=all bash test-all.sh` → CEILING RED; (b) make `--full` unconditional (drop the opt-in condition) → RED; (c) revert lefthook run-string → pin RED; (d) drop the `--affected` invocation from `/work` §9 → FLOOR RED; (e) fenced `--print-affected-set` line satisfying a battery floor → `QUERY_FLAGS` RED.

## Architecture Decision

- **New ADR-227** (provisional — re-verify): *local test gate defaults to affected-suites + always-on ratchets*. Amends: **ADR-181** (relevance declines become positive selection — the decline machinery becomes the `--full`-defeated path), **ADR-133** (contention machinery demoted to the rare full path; census stays run-granular), **ADR-183** (ship changes from full local run to affected default; `--full` behind opt-in).
- **C4:** no diagram change. Enumeration checked — `model.c4`, `spec.c4`, `views.c4`, `model.likec4.json`, `c4-model.md`: the only modeled component in scope is `ship`, whose description stays accurate; no new actors/systems/relationships. `plugins/soleur/test/c4-count-parity.test.sh` green 10/10 at plan time.

## Domain Review (carry-forward from brainstorm)

- **CPO:** proceed — user-brand-critical, single-user-incident threshold; false-green is the named failure and every mutation arm fails toward coverage. Sign-off carried from brainstorm assessment.
- **CLO:** no GDPR gate — test-gate machinery, no regulated data surface; no third-party content claims.
- **CTO:** proceed — land before #8231; the chokepoint design composes with the future parallel scheduler (same `run_suite` stream).

## Open Code-Review Overlap

- **#7942** (`*.mutation.sh` unregistered batteries): acknowledges `test-all.sh` glob semantics but is a registration/naming issue — not folded in. If it lands first, the two newly-registered suites flow through the census like any registration.
- **#2963** (Supabase typegen): mentions `package.json` for a different script — no overlap.

## Acceptance Criteria

- [ ] `bash scripts/test-all.sh` and `… --affected` run affected-set + always-on; `… --full` runs the complete battery (declines defeated, infra arm included); explicit non-`all` `<group>` asks run the group; `--affected <group>` intersects; `scripts --full` → exit 2.
- [ ] `--print-affected-set` emits `AFFECTED_CLASS` records per registration via the enumerate plumbing, no lock, exit 0; `--help` prints the flag/env table.
- [ ] Undecidable diff (either `_diff_detect_ok` or `_diff_head_ok`) → `AFFECTED_FALLBACK` + full; runner/index diff → `reason=runner-changed` full; missing lib → `reason=index-missing` full; below-`*-live`-floor or zero-executed set → `AFFECTED_UNRESOLVED` rc=3; unclassified → run + census flag.
- [ ] Epilogue accounts `N not-affected` (distinct `_affected_declined` counter) inside `M-k/M`; `MODE=affected|full` banner at run start.
- [ ] `plugins/soleur/test/test-helpers.sh`-only diff → its sourcing suites + always-on; `.md`-only diff → always-on + legal gates; infra diff → infra runner; explicit `TEST_GROUP=infra` on non-infra diff → infra runner runs (no green-over-zero, no false `_infra_ran`).
- [ ] `SOLEUR_SUBAGENT=1` or sibling run: `--affected` proceeds, `--full` and degraded-to-full refuse rc=4; `SOLEUR_ALLOW_FULL_GATE` overrides full refusals.
- [ ] `CI` env → filter inert; enumerate streams unfiltered + never refuse/degrade; record shapes unchanged.
- [ ] `/ship`: `/ship --full` → `--full` (outranks SKIPPABLE); else OWED/not-42 → `--affected`; SKIPPABLE → skip.
- [ ] lefthook `bun-test`, grok gate, `scripts/hooks/pre-push`, `/work` §9 all invoke `--affected`.
- [ ] Census + mutation suite + re-pinned guards green; ADR-227 merged; header + ship disclosure present.

## Test Scenarios

See Guard 2 mutation matrix (rows a–l) plus: `TEST_GROUP` intersection, `SCRIPTS_SHARD` interplay (shard non-selection still invisible, affected non-selection counted), `SOLEUR_TEST_FORCE_ALL=1`+`--affected` → full, `main-health-monitor` unaffected under `CI`, battery-owed fixture rows for OWED/opt-in/SKIPPABLE/undecidable dispatch.

## Risks / Non-Goals

**Risks:** (a) a missed edge under-selects — mitigated: unclassified runs, census, fail-toward-coverage, `--print-affected-set` human review; (b) derivation drift vs. real registrations — mitigated: census derives floors from the live enumerate stream; (c) pin-suite re-baselines are the bulk of the diff — expected, mechanical.

**Non-goals:** suite parallelization (#8231); file-level refinement inside mega-registrations; promoting `infra-validation.yml` to required; cost-granular contention accounting; cross-suite interaction detection; a separate affected entry point; `TEST_GROUP=affected`; decline-only extension; shadow-mode rollout.
