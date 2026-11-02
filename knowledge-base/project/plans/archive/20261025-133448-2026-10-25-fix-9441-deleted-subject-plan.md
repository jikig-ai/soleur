---
title: "fix: a declared affected edge to a deleted subject must still select its suite (#9441)"
type: fix
date: 2026-10-25
slug: fix-9441-deleted-subject-edge
branch: feat-one-shot-9441-deleted-subject-edge
issue: 9441
closes: 9441
lane: engineering
---

# fix: a declared affected edge to a deleted subject must still select its suite

## Overview

`scripts/test-all.sh`'s affected pre-pass drops every edge that fails an
`[[ -e ]]` probe. Declared and consumed edges re-enter the edge set through
the same `_affected_add_edge` used for derived tokens, so a diff that DELETES
a declared subject discards the edge naming it — and the suite that guards
the deleted path is declined on exactly the diff that needs it. ADR-242
decision 12 chose that drop deliberately and named the orphan census as the
catch; issue #9441 reverses that clause. The issue spells a five-part,
all-or-nothing change; this plan executes it verbatim.

## Problem Statement / Motivation

`_affected_classify` (scripts/test-all.sh:3436) loads a label's declared
array verbatim via `_affected_resolve_edges`, buffers it in `_decl`, derives
the suite's own edge set, then re-adds every declared entry through
`_affected_add_edge` (line 3478). `_affected_add_edge`'s `[[ -e ]]` filter
(line 2939) exists for DERIVED tokens — argv words and `-c` payload strings
that may not resolve — but it also filters the re-added declared entries.
So a PR deleting `apps/web-platform/infra/sentry` declines
`tests/scripts/destroy-guard-counter-sentry` even though
`AFFECTED_TESTS_SCRIPTS_DESTROY_GUARD_COUNTER_SENTRY_PATHS` names that
directory: the one diff whose blast radius includes deletion selects nothing.

## Research Insights

**Verified live on this branch** (all line numbers read, not recalled):

- `_affected_add_edge` at `scripts/test-all.sh:2878-2953`; the `-e` filter
  is `[[ -n "$_p" ]] && _affected_probe e "$_p" || return 0` at :2939. The
  `-d` normalisation (`if _affected_probe d "$_p"; then _p="${_p%/}/"; fi`)
  at :2943 is what turns a slash-less LIVE directory into the `^dir/`
  prefix edge; with the subject deleted the probe cannot answer, so the
  trailing slash must be carried by the DECLARED spelling.
- The single declared/consumed re-entry site is
  `for _e in ${_decl[@]…}; do _affected_add_edge "$_e"; done` at
  scripts/test-all.sh:3478 (inside `_affected_classify`'s union arm).
- Selection: `_aff_sel[$_aff_ordinal]` at :3976-3981 —
  `edge:*` + non-empty `_AC_EDGES` + `_diff_touches` miss ⇒ decline;
  `_diff_edge_hit` at :2200-2268 (`^dir/` = prefix, `^file` = exact line).
  `_suite_affected` (argv signals) runs FIRST at :1719 — a fixture suite
  must pass it independently (corpus scanners like
  `scripts/guard-vacuity-floor.test.sh` pass via signal 4's
  `git ls-files` backstop), then `_aff_sel` decides.
- Slash-less declared directories in `scripts/lib/test-affected-paths.sh`,
  enumerated by parse + `os.path.isdir`: **23 entries** — the issue's "22"
  is stale by one (`.claude/hooks/lib` in
  `AFFECTED_TESTS_HOOKS_INCIDENTS_PATHS` was added later). Three are `/.`
  spellings (`plugins/.`, `plugins/soleur/.`, `plugins/soleur/skills/.`)
  which mint dead `^<dir>/./` edges today; the other 20 migrate to
  trailing-slash form. Deleting a `/.` member leaves both arrays non-empty
  (verified: each retains ≥10 members).
- The census arm is `scripts/lint-orphan-test-suites.sh:1189-1271`: `glob:*`
  entries classify through `_affected_glob_split`; `*/` entries need
  `[[ -d ]]`; everything else needs `_tracked_member` — whose dir-prefix
  arm (lines 112-118) makes a slash-less LIVE directory pass today.
- The battery's row convention: mutation rows `run_M1..M35` are gated by
  `in_range`/DECLARED_TOTAL=35 and tiled across two `--rows` registrations;
  unconditional rows (C0, R1, R1b) tick `ROWS` and are conserved by
  `_UNCONDITIONAL_SITES=3` at :1284. A unit row added beside R1b bumps the
  constant to 4 — no DECLARED_TOTAL bump, no re-tiling of
  `scripts/test-all.sh`'s `--rows` ranges.
- Extraction span: `scripts/test-all-affected.test.sh:2594` extracts
  `^_affected_in_list() {` → first `^}` after `^_affected_add_edge() {` —
  a function placed immediately before `_affected_add_edge` is carried
  verbatim. The derive suite's own extraction
  (`scripts/test-affected-derive.test.sh:72`, `_AC_CLASS=""` →
  `_affected_derive` close) covers the same span, and the derive cache's
  code hash (scripts/lib/test-affected-derive-cache.sh:136) keys on it —
  the new function flushes stale records by design.
- m9 (test-all-affected.test.sh:2606-2618) asserts
  `s.count(old) == 1` for the `-d` normalisation line; an identical twin
  function makes it 2 — m9 must scope its replace to `_affected_add_edge`'s
  body and gain a twin for `_affected_add_declared_edge`.
- `MIN_CASES=239` at :3994, `PASS+FAIL==cases` conservation at :3989-3992.
- `.claude/hooks/grep-q-pipe-guard.test.sh:91` documents `plugins/.` as the
  declared entry that "matches nothing" — updated with the deletion.

## Property List

1. A diff deleting a path an `AFFECTED_*_PATHS`/`AFFECTED_CONSUMED_EDGES`
   array declares still selects the suite that guards it.
2. Declared directory subjects are written `<dir>/`: the 20 live slash-less
   entries migrate; the three `/.` dead-edge spellings are deleted.
3. The census linter REDs a slash-less entry that resolves to an existing
   directory, naming the array; a trailing-slash entry and a tracked file
   stay green.
4. Derived-token minting keeps the `-e` filter verbatim (argv/payload
   garbage still mints nothing).
5. Selection output for every EXISTING declared subject is byte-identical
   (slash-less `dir` already minted `^dir/` via the `-d` probe).

## Proposed Solution

The issue's five parts, all-or-nothing:

1. **Declarations.** In `scripts/lib/test-affected-paths.sh`, rewrite the 20
   slash-less directory entries to trailing-slash form and delete
   `plugins/.`, `plugins/soleur/.`, `plugins/soleur/skills/.`. Update the
   header doctrine paragraph (the `-d` probe normalises a LIVE slash-less
   dir, but the slash is what survives deletion) and the stale `plugins/.`
   comment in `.claude/hooks/grep-q-pipe-guard.test.sh`.
2. **Census.** In `scripts/lint-orphan-test-suites.sh`'s declared-edge `*)`
   arm, reject a slash-less entry that `[[ -d ]]`s (`.` exempt — its
   semantics differ), before the `_tracked_member` check; unit row R2 in
   `scripts/lint-orphan-test-suites.test.sh` (unconditional site,
   `_UNCONDITIONAL_SITES` 3→4) injects `"scripts"` into a sandbox array and
   asserts RED naming the arm.
3. **Mint.** New `_affected_add_declared_edge` in `scripts/test-all.sh`,
   immediately before `_affected_add_edge`: byte-identical minus the `-e`
   probe line (and recursing to itself for metachar-free `glob:` payloads).
   `_affected_classify`'s union re-add calls it for the `_decl` buffer.
4. **Battery pins.** Scope m9's mutation to `_affected_add_edge`'s half of
   `_edge_src`; add m9b mutating the twin's own `-d` normalisation.
5. **Fixture.** A sandbox arm whose mutated `test-affected-paths.sh` injects
   `zzz-deleted-subject/` into `AFFECTED_SCRIPTS_GUARD_VACUITY_FLOOR_PATHS`:
   `SANDBOX_DIFF_NAMES=zzz-deleted-subject/qzx9.sh` must RAN
   `scripts/guard-vacuity-floor` (signal-4 argv pass + `^zzz-` prefix edge)
   while `scripts/lint-orphan-test-suites` declines; a SANDBOX_MUT twin
   restoring the filtered call site proves the mechanism binds. Mint-level
   pins: `_affected_add_declared_edge` mints `^zzz-deleted-subject/` for a
   nonexistent path where `_affected_add_edge` mints nothing.

## Guard Contract

### Guard 1 — declared/consumed edges survive subject deletion

**Property.** Any diff whose changed lines start with a declared `<dir>/`
prefix, or equal a declared file path, selects the suite owning the
declaration — independent of whether the named path exists at selection
time.

**Assembly.** (1) `_affected_add_declared_edge` + the `_decl` re-add call
site inside `_affected_classify` (scripts/test-all.sh) — every
declared/consumed edge re-enters through it; (2) `_diff_touches` /
`_diff_edge_hit` over the minted set — the only consumers of the edges;
(3) the sandbox fixture arm + mint pins in
`scripts/test-all-affected.test.sh` — the dispatch that observes selection;
(4) `scripts/test-affected-derive.test.sh`'s extraction (eval's the same
span) and `scripts/test-affected-kb-consumers.test.sh`'s covers() oracle —
the Python mirrors pinned to the minted forms.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Re-point the `_decl` re-add at `_affected_add_edge` (restore the `-e` filter for declared edges) | RED — the fixture arm's RAN disappears |
| 2 | Delete the `-d` normalisation inside `_affected_add_declared_edge` | RED — m9b mints `^scripts/lib` (no slash), t11b rejects |
| 3 | Write `zzz-deleted-subject` without the trailing slash in the fixture array | The exact-line `^zzz-deleted-subject` mints; the prefix diff declines — the census row is what keeps the declared form honest (documented, not executed: the fixture uses the `/` form) |
| 4 | Gut `_affected_add_declared_edge` to `return 0` | RED — the fixture declines AND every declared suite loses its union members |
| 5 | Must-PASS: a diff under an EXISTING declared dir | PASS — unchanged selection, p1/f rows pin |

### Guard 2 — the declared-member census enforces the slash form

**Property.** No `AFFECTED_*_PATHS` element that resolves to an existing
directory is accepted without a trailing `/`.

**Assembly.** (1) the `*)` arm of the declared-edge walk in
`scripts/lint-orphan-test-suites.sh` (the only element-classification site
for non-`glob:`, non-`*/` members); (2) `_tracked_member`'s dir-prefix arm
— the path a slash-less dir previously escaped through; (3) unit row R2 in
`scripts/lint-orphan-test-suites.test.sh` driving the synthetic sandbox;
(4) `materialise()`'s `-d` branch — what makes the sandbox's `scripts` a
real directory for the row to observe.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Revert the `[[ -d ]]` conjunct so the `*)` arm is `_tracked_member` only | RED — R2's injected `"scripts"` passes silently (row fails) |
| 2 | Narrow the check to a hard-coded dir list instead of `[[ -d ]]` | RED — R2's injected entry is not in any list (row fails) |
| 3 | Flag the `*/` arm instead of the `*)` arm (wrong case label) | RED — slash-less entries never reach it (row fails) |
| 4 | Must-PASS: `"scripts/"` (correctly-slashed dir) | PASS — C0 + R2's `assert_lacks` on the slashed spelling |

## Implementation Phases

### Phase 1 — plan + declarations (this file, then test-affected-paths.sh)

- Write this plan; `python3 scripts/lint-guard-contract.py` clean.
- Migrate the 20 slash-less entries, delete the three `/.` entries, header
  doctrine edit, `grep-q-pipe-guard.test.sh:91` comment.

### Phase 2 — the mint + call site (scripts/test-all.sh)

- Insert `_affected_add_declared_edge` before `_affected_add_edge`;
  re-point the `_decl` re-add; comment updates (mint-site lists in the
  glob-invariant comments).

### Phase 3 — census + unit row (lint-orphan-test-suites*.sh)

- `*)` arm `[[ -d ]]` rejection; R2 unconditional row; `_UNCONDITIONAL_SITES` 4.

### Phase 4 — battery pins (test-all-affected.test.sh)

- `_decl_edge_run` helper; t11b mint pins; m9 scoped + m9b twin; the
  deleted-subject fixture arm + its SANDBOX_MUT twin; `MIN_CASES` bump.

### Phase 5 — verify

- `bash -n` on every edited file; `bash scripts/test-all-affected.test.sh`;
  `bash scripts/lint-orphan-test-suites.test.sh` (a `--rows` spot-check plus
  unconditional tail); live `--paths` selection check on the real runner;
  `python3 -I scripts/ci-pr-affected-replay.py ratchet` for pair drift.
