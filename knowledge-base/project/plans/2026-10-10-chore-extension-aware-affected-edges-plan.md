---
title: "chore: extension-aware affected edges for *.sh corpus walkers"
type: chore
date: 2026-10-10
slug: extension-aware-affected-edges
branch: feat-one-shot-9813-extension-aware-edges
issue: 9813
closes: 9813
lane: cross-domain
requires_cpo_signoff: true
---

# chore: extension-aware affected edges for *.sh corpus walkers

## Overview

The local test gate's affected-edge grammar knows two declared entry kinds —
literal file paths and directory prefixes — minted `^file` / `^dir/` by
`_affected_add_edge` and matched by `_diff_edge_hit` in `scripts/test-all.sh`.
Six `*.sh` corpus-walker suites declare `knowledge-base/` because that tree
genuinely hosts shell (all 9 tracked kb `.sh` files live under
`knowledge-base/project/specs/`), so a kb-only `.md` diff pays their full cost
even though no `.md` can move their verdict — re-measured on this branch:
118 of 596 registrations selected on a kb-`.md` probe, the seven edge-selected
suites totalling ~330 committed seconds.

This plan adds a third declared entry kind — `glob:<literal-head>/<pattern>` —
evaluated as "diff line matches the bash pattern", so the walkers keep covering
`knowledge-base/**.sh` while a `.md`-only kb diff declines them. The change is
fail-toward-match at both layers (a malformed entry degrades at mint and
selects at hit, never narrows), touches the closed registration-only grammar
and the census linter so the new spelling is first-class, and extends the
dropped-consumer ratchet oracle so `^glob:` edges count as coverage.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-10-10
**Sections enhanced:** 7 (Observability, Encryption Posture, Proposed Solution,
Risks, Guard Contract, Scope Check, References)
**Research agents used:** inline — this environment has no Task/subagent
spawn; every deepen phase (skills discovery, learnings sweep, per-section
research, 4.4 precedent-diff, 4.45 verify-the-negative + self-audit,
4.6–4.12 halt gates) ran sequentially in-process and its gates were executed
mechanically where a script exists (`lint-guard-contract.py` green on 5
entries; PAT sweep clean; Scope Check fence-count 1; UI-surface, network,
downtime triggers absent).

### Key Improvements

1. Malformed-mint corrected: a bare `^` edge is NOT always-match
   (`e=""` evaluates `*\n\n*`, which narrows on non-empty blobs) — malformed
   entries mint `^glob:<verbatim>` so the hit arm's own malformed rule
   matches. Found by reading `_diff_edge_hit`'s actual `case` arms during
   the 4.45 verify-the-negative pass.
2. `glob:` semantics pinned to bash `[[ == ]]` (`*` crosses `/`), explicitly
   distinct from lefthook's gobwas `**` = 1+ dirs
   (learning `2026-03-21-lefthook-gobwas-glob-double-star`) — the `**/`
   spelling is self-documentation, not semantics.
3. Extension-level coverage honesty: the census validates glob *structure*
   and the kb-consumers ratchet covers dir *reach*, but neither checks
   extension *completeness* (self-edge lesson,
   `2026-09-20-a-classified-edge-that-pointed-at-itself-read-as-coverage`) —
   the disposition table's per-suite verified read set is the pin, cited
   again in Risks.
4. Mint-site census: `grep -n '="^' scripts/test-all.sh` shows exactly one
   `^` minter (`_p="^$_p"` at `_affected_add_edge`) — the "single chokepoint"
   claim is verified, not asserted.

### New Considerations Discovered

- A `glob:` token in a `test-relevance-paths.sh`/consumed array is a dead
  unanchored substring, never a glob — limitation documented + risk row.
- `fanout-suite-scope`'s sandbox may lack `knowledge-base/` — mint degrade
  and census must agree on what a missing head dir means (Phase 3 task).
- FR-5 rewritten: the bench's byte-compare flags the six labels' rows on
  EVERY probe (edge text changes), so identity is asserted by a scripted
  row-wise stream-diff, not a bare bench exit code.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality on this branch (verified) | Plan response |
|---|---|---|
| "118 of 585 registrations … ~331 committed seconds" | Reproduced 2026-10-10: `selected=118 of=596 always_on=111 edge=7` (corpus grew 11 registrations since 2026-10-09); the seven rows sum to 329,843 ms in `scripts/suite-durations.tsv` | Carry the re-measured numbers; the substance is identical |
| "Six of the seven are `*.sh` corpus walkers (`find … -name '*.sh'` / `grep --include='*.sh'`)" | Five are strictly `*.sh`-scoped under kb. `scripts/lint-trap-tempfile-ownership` scans `.sh|.bash|.py|.ts|.mjs|.js` **and** `bunfig.toml` — scope list at `ALL_EXT` + `_in_scope` in `scripts/lint-trap-tempfile-ownership.py` — and kb tracks 7 `.py` + 1 `.js` files | That suite gets a 7-entry glob set, not `**.sh` — a sh-only edge would silently under-cover its `py`, `ts` and `bunfig` population |
| (implicit) all six read `knowledge-base/` | `plugins/soleur/test/operator-ack-guard.test.sh` **excludes** `^knowledge-base/` from its Guard-1 population (`g1_population` + caller census, two `grep -vE` sites) — a kb diff of any extension cannot move its verdict | It still gets the `glob:` form: uniform mechanism, honours the issue's AC ("kb-sh still selects them"), and keeps coverage if the exclusion is ever relaxed. Edge removal is recorded as the rejected alternative |
| "swap `knowledge-base/` for the glob form" | Three other grammar consumers also need the kind: the census linter (`-d`/tracked check flags `glob:` as dead edge), the registration-only classifier (G3 charset `[A-Za-z0-9_.\/-]` admits neither `:` nor `*`), and the kb-consumers oracle `covers()` (a `^glob:` edge never covers a ref) | The plan names all four touchpoints plus their test arms — a matcher-only change would ship a dead/refused edge |

## Problem Statement

A kb-only `.md` diff selects 118 of 596 registrations — the 111 always-on plus
7 edge-selected suites totalling ~330 committed seconds (≈430 s+ locally per
the ~2–3× multiplier in `learnings/2026-10-09-committed-ci-weights-are-not-local-costs.md`):

| suite | committed ms | kb read set (verified against source) | disposition |
|---|---:|---|---|
| `plugins/soleur/test/operator-ack-guard.test.sh` | 109,036 | none — `^knowledge-base/` excluded from population (`g1_population`, `:167,:361`) | `glob:knowledge-base/**.sh` (uniform; see Alternatives) |
| `plugins/soleur/test/operator-script.test.sh` | 98,487 | `*.sh` only (`grep -rl --include='*.sh'`) | `glob:knowledge-base/**.sh` |
| `scripts/test-affected-kb-consumers` | 68,386 | any kb path (the ratchet itself) | **keep `knowledge-base/`** |
| `scripts/lint-trap-tempfile-ownership` | 20,587 | `.sh .bash .py .ts .mjs .js` + `bunfig.toml` (`ALL_EXT`, `scripts/lint-trap-tempfile-ownership.py:155-159`) | `glob:knowledge-base/**.sh`, `**.bash`, `**.py`, `**.ts`, `**.mjs`, `**.js`, `glob:knowledge-base/*bunfig.toml` |
| `plugins/soleur/test/operator-agent-runnable.test.sh` | 15,761 | `*.sh` only (`ls-tree -- knowledge-base plugins` piped `grep '\.sh$'`, `:365`) | `glob:knowledge-base/**.sh` |
| `scripts/lint-shell-capture-exit-live` | 11,192 | `*.sh` only (`git ls-files -z '*.sh'`, `lint-shell-capture-exit.py:1559`) | `glob:knowledge-base/**.sh` |
| `scripts/lint-shell-trace-credential-refusal` | 8,494 | `*.sh` only (rule-E YAML pathspecs are `.github/` + `apps/**/cloud-init*.yml`; `.md` never scanned) | `glob:knowledge-base/**.sh` |

Saving on a kb-`.md` diff: the six walkers, ≈261.5 committed seconds.

File-level edges were rejected by the issue and the rejection holds: a NEW
`.sh` under kb/ would not be enumerated, so a diff adding only that file would
decline a walker that reads it — silent under-coverage. Directory prefixes
exist precisely for walk-class suites; the gap is granularity, not direction.

## Proposed Solution

A third declared-entry kind, `glob:<literal-head>/<glob-tail>`:

- **Grammar (declared arrays):** `<literal-head>` is the longest leading
  metachar-free segment and must end in `/`; `<glob-tail>` is a non-empty bash
  pattern containing `*` and no `?`/`[`. `*` crosses `/` (same convention as
  the `git ls-files '*.sh'` pathspecs the suites themselves use), so
  `glob:knowledge-base/**.sh` matches `knowledge-base/x.sh` and
  `knowledge-base/a/b/c.sh` alike. `**` and `*` are equivalent under bash
  `[[ == ]]`; the `**` spelling is kept for self-documentation. This is bash
  pattern semantics only — do NOT confuse with lefthook's gobwas `**`
  (1+ directories, learning `2026-03-21-lefthook-gobwas-glob-double-star`),
  which this grammar never invokes.
- **Mint (`_affected_add_edge`, before the `[[ -e ]]` probe):**
  - well-formed + `<literal-head>` is an existing dir (`_affected_probe d`) →
    mint `^glob:<pattern>`;
  - well-formed but head dir missing → mint `^<head>/` — the same dir-prefix
    edge the entry replaced, never narrower;
  - malformed (no `*/` head, empty tail, tail without `*`, `?`/`[` present) →
    mint `^glob:<entry verbatim>` — the hit arm's own malformed rule matches
    it (never narrows) and the receipt shows the bad entry verbatim. A bare
    `^` does NOT work: `e=""` evaluates `*\n\n*` and only matches a blob with
    an empty line — measured against `_diff_edge_hit`'s `case` arms, it
    narrows;
  - `glob:` with no metachar at all → recurse as a literal path entry.
- **Hit (`_diff_edge_hit`, new `glob:*)` arm before `*/)`):** recompute head +
  validity — malformed in-flight (head not ending `/`, empty tail, tail
  without `*`, `?`/`[` present) → `return 0` (match, never narrow). Cheap
  pre-check `[[ "$_n" == *"${_NL}<head>"* ]]` short-circuits non-kb blobs;
  otherwise iterate non-empty lines of `_DEH_N` (already TAB-split for rename
  sources, C-quote-unwrapped) and match `[[ "$line" == $pattern ]]`.
- **Census (`scripts/lint-orphan-test-suites.sh`):** `glob:` arm in the
  declared-array member check — head must end `/`, `[[ -d ]]`, tail non-empty
  with `*` and no `?[` — a dead or malformed declared glob is a static RED,
  not a silent narrow.
- **Registration-only classifier (G3, `scripts/test-all.sh` awk):** new
  `GLOBENT` line-shape `^  "glob:[-A-Za-z0-9_./]*\*[-A-Za-z0-9_./*]*"( +#.*)?$`
  admitted alongside `ENT` at the in-block member check and both INDEX-ANCHOR
  preceding-line sites (admission is a bounded-selection question, not a
  semantics one — a superset is the safe direction). `ALWAYS_ON_SUITES`
  membership stays label-shaped.
- **kb-consumers oracle (`scripts/test-affected-kb-consumers.test.sh`
  `covers()`):** `^glob:` arm — a kb ref `p` is covered iff `fnmatch(p, g)`
  (file ref) or `p`/`head` nest (dir ref intersects the glob's reach).

Consumed edges (`AFFECTED_CONSUMED_EDGES` → `test-relevance-paths.sh` arrays)
are unchanged: the kind is declared-array-only, and `_diff_touches`' `^`
dispatch routes `^glob:` into the new arm with no call-site edits.

## Technical Approach

### Architecture

All edge semantics live in three chokepoints; every consumer flows through
them, so the kind is defined once:

1. **Mint** — `_affected_add_edge` (`scripts/test-all.sh:2710`) is the only
   site that prepends `^`. Declared entries reach it via the classify union
   (`_affected_classify:3249-3251` buffers `_decl` and re-adds each through
   `_affected_add_edge`), so a `glob:` arm placed before the `-e` probe covers
   both fresh classification and the union re-add. Every existence probe in
   the arm goes through `_affected_probe` (not bare `[[ -d ]]`) or the
   derive-cache input census (`scripts/test-affected-derive-cache.test.sh`)
   fails — the probe is the recording channel (ADR-242 decision 21).
2. **Match** — `_diff_edge_hit` (`scripts/test-all.sh:2096`) is the only
   matcher; `_diff_touches:2535` strips `^` and calls it, and the
   `R100<TAB>old<TAB>new` rename rows are already split into `_DEH_N` lines.
   The glob arm reads the same blob — no second diff channel.
3. **Static census** — `scripts/lint-orphan-test-suites.sh:1099-1134` walks
   every `AFFECTED_*_PATHS` array; the entry-shape loop is the single site
   that must learn the kind (its own suite's fixture census at
   `lint-orphan-test-suites.test.sh:190-199` mirrors it).

The G3 awk grammar inside the registration-only classifier is a fourth,
bounded-selection-only surface: it decides whether a runner/index diff is
"nothing but new-suite registration". The six array edits in THIS diff are
removals+additions → `semantic` → full battery, which is correct; the grammar
extension serves FUTURE diffs where a newly-registered suite declares `glob:`
entries.

### Implementation Phases

#### Phase 1: matcher + mint arms (`scripts/test-all.sh`)

- `_affected_add_edge` `glob:*` arm (well-formed→`^glob:`; missing head
  dir→`^head/`; malformed→`^`; no-metachar→recurse). All probes via
  `_affected_probe`.
- `_diff_edge_hit` `glob:*)` arm (malformed→match; head pre-check; line loop
  over `_DEH_N`).
- Header comments on both functions updated (third kind, degrade ladder).
- Success: `derive_run` fixtures mint all four forms; `SANDBOX_DIFF_NAMES`
  drives hit/miss/malformed rows (Phase 3 wires them).
- Estimated: ~80 lines + comments.

#### Phase 2: index + grammar consumers

- `scripts/lib/test-affected-paths.sh`: header grammar doc (three kinds); the
  six arrays per the disposition table; per-array comment naming the verified
  read set.
- G3 awk: `GLOBENT` + admit at the three entry-shape sites (member check,
  entry-anchor precede, array-opener precede).
- `scripts/lint-orphan-test-suites.sh`: `glob:` arm in the member check.
- `scripts/test-affected-kb-consumers.test.sh`: `covers()` `^glob:` arm.
- Success: census green on the real index; a `glob:`-bearing fixture array
  validates; oracle covers `glob:`-edged suites.
- Estimated: ~60 lines + comments.

#### Phase 3: test arms

- `scripts/test-affected-derive.test.sh` — R-rows: `glob:` mint; missing-head
  degrade `^head/`; malformed mint `^`; no-metachar recurse; dedup of a glob
  edge; `^glob:` appears in `--print-selection` receipts.
- `scripts/test-all-affected.test.sh` — t-rows over `SANDBOX_DIFF_NAMES`:
  kb `.sh` selects / kb `.md` declines / nested `.sh` selects /
  malformed selects / `?`/`[` degrades / R100 rename-source `.sh` selects;
  awk mutation rows: `glob:` entry admitted (bounded), `glob:` with `?`/`[`
  → `INDEX-SHAPE`/`semantic`, glob entry as valid anchor.
- `scripts/lint-orphan-test-suites.test.sh` — fixture + mutation rows for the
  census arm (bad head dir RED, `*`-less tail RED, `?`/`[` RED, valid GREEN,
  second-member-after-first RED).
- `plugins/soleur/test/fanout-suite-scope.test.sh` — verify its sandbox run
  still passes with `glob:` entries in the copied index (its sandbox may lack
  `knowledge-base/`; the mint degrade + census arm must agree on what that
  means — fix forward if it flags).
- New test rows follow the #8659 fixture idiom: scratch-root per-process dirs,
  `assert_fixture_dir` twice, no second `EXIT` trap, no `mktemp` outside the
  helper; no new shared-inode write paths per #8800.
- Success: all new rows land; mutation rows red when their mutation is
  applied by hand.
- Estimated: ~250 lines across three suites.

#### Phase 4: verification + decision record

- `bash scripts/test-all.sh --print-selection --paths=knowledge-base/project/specs/foo.md`
  → exactly the six labels absent; `test-affected-kb-consumers` present;
  every other row byte-identical to a `main` capture.
- `--paths=<a kb .sh>` → the six select.
- `bash scripts/affected-prepass-bench.sh --base origin/main --runs 1` →
  identity holds outside the six rows' edge-column/selected-bit deltas.
- ADR-242 amendment: decision 22 (third edge kind) + the
  alternatives table entry.
- Estimated: ~40 lines ADR + bench run.

## Files to Edit

| File | Change |
|---|---|
| `scripts/test-all.sh` | `_affected_add_edge` `glob:` arm; `_diff_edge_hit` `glob:` arm; G3 awk `GLOBENT` + admit sites |
| `scripts/lib/test-affected-paths.sh` | header doc; `knowledge-base/` → `glob:` in six arrays (+ six more `glob:` entries for trap-tempfile) |
| `scripts/lint-orphan-test-suites.sh` | `glob:` arm in declared-member census |
| `scripts/lint-orphan-test-suites.test.sh` | mirrored census arm + mutation rows |
| `scripts/test-affected-kb-consumers.test.sh` | `covers()` `^glob:` arm in oracle |
| `scripts/test-affected-derive.test.sh` | R-rows for mint/receipt |
| `scripts/test-all-affected.test.sh` | t/m rows for hit + G3 grammar |
| `plugins/soleur/test/fanout-suite-scope.test.sh` | verify; fix forward only if the sandbox flags `glob:` |
| `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` | decision 22 + alternatives |

## Files to Create

None (test rows live in existing suites; no new suite files).

## Alternative Approaches Considered

| Alternative | Why rejected |
|---|---|
| Enumerate existing `knowledge-base/**/*.sh` as `^file` edges | Unsound for walk-class suites — a NEW `.sh` under kb/ is invisible (issue's own argument; the premise re-verified: `git ls-files` shows all 9 kb `.sh` under `knowledge-base/project/specs/` but nothing bounds future locations) |
| Narrow `knowledge-base/` → `knowledge-base/project/specs/` (zero-machinery) | Covers today's 9 files but buys a strictly weaker property — a future `.sh` elsewhere under kb/ (e.g. a runbook-adjacent script) silently under-covers, the same unsoundness class as file edges at dir granularity |
| Remove `knowledge-base/` from `operator-ack-guard` only (its corpus formally excludes kb) | Honest today, but: the issue's AC says a kb-`.sh` diff still selects "them" (the six); removal creates a new oracle baseline row; and if the `^knowledge-base/` exclusion is ever relaxed the suite silently under-covers (though the kb-consumers ratchet would catch the uncovered ref). Uniform `glob:` keeps the AC verbatim and costs the same on kb-`.md` diffs |
| Magic in the `^` arm (`*` in an edge = glob) | `*` is a legal git filename character; implicit kind detection can silently re-interpret a literal edge. Explicit `glob:` is a closed, census-checkable kind |
| `ext:<dir>:<ext-list>` instead of a glob | A second bespoke grammar with the same power; bash `[[ == ]]` pattern matching is already the repo's convention (`git ls-files` pathspecs) and needs no parser |
| extglob (`@(...|...)`) for the trap-lint multi-extension set | Requires `shopt -s extglob` in the runner — a shell-option change inside the derive span (env-fingerprinted by the #9812 cache) for a property seven entries already buy |
| Skip the G3 grammar extension | Fail-safe (future glob-bearing registration diffs go `semantic` → full battery) but silently re-charges the bounded-selection saving the next suite-adding PR expects — the issue names this interaction explicitly |
| Token-level diff edges / per-suite runner-SUT marker | Already deferred/rejected — ADR-242 decision-table rows and the #9564 keep-deferred record (2026-10-06 brainstorm) |

## User-Brand Impact

- **If this lands broken, the user experiences:** a local `--affected` gate that
  under-selects — a kb-shell regression reaching a green local verdict (the
  gate is the contributor/agent pre-ship instrument, `scripts/test-all.sh` +
  `scripts/lib/test-affected-paths.sh`).
- **If this leaks, the user's [data / workflow / money] is exposed via:** a
  silently shrunk safety gate; the exposure is contributor trust in gate
  verdicts, not end-user data. Merge-time backstop: CI `merge_group`/`push`
  runs every battery (ADR-262).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** no end user is touched, but the
  artifact is a coverage gate whose narrowing is invisible by construction —
  same class the #9564 domain review rated `single-user incident` (always-on
  default, #5175).

CPO sign-off required at plan time before `soleur:work` begins — invoke the
CPO domain leader or confirm prior coverage; `soleur:engineering:review:user-impact-reviewer`
is invoked at review time (review skill conditional-agent block).

## Observability

```yaml
liveness_signal:
  what: AFFECTED_SELECTED receipt rows carrying ^glob: edges, and the AFFECTED_SUMMARY selected= count on every --affected / --print-selection walk
  cadence: per local --affected / --print-selection run
  alert_target: none — local dev tooling; the receipt is operator-visible in run output
  configured_in: scripts/test-all.sh (the AFFECTED_SELECTED emit loop)
error_reporting:
  destination: stderr of the invoking run (repo convention for the runner) plus RED exits from the census linter and the kb-consumers ratchet
  fail_loud: a malformed glob entry is visible verbatim as ^glob:<entry> in the receipt AND flagged statically by lint-orphan-test-suites; a genuinely uncovered kb read is VIOLATION in test-affected-kb-consumers
failure_modes:
  - mode: a glob edge silently narrows (the failure this design exists to prevent)
    detection: kb-.sh / kb-.md probe arms in scripts/test-all-affected.test.sh assert the selected-bit for each disposition; malformed rows assert match
    alert_route: suite RED on the diff that introduces the arm
  - mode: a declared glob head dir is deleted or renamed
    detection: lint-orphan-test-suites census arm flags the dead head statically; mint degrade mints ^<head>/ so selection never narrows between landing and lint
    alert_route: census RED at pre-push
  - mode: the derive cache serves records minted under the old grammar
    detection: the #9812 derive-code hash covers _affected_add_edge + _diff_edge_hit; new code flushes every record once by design
    alert_route: none — self-healing on the next run
logs:
  where: the AFFECTED_SELECTED / AFFECTED_SUMMARY lines on stdout of the run
  retention: run lifetime (no persistent log)
discoverability_test:
  command: rg -n glob: scripts/lib/test-affected-paths.sh
  expected_output: glob:knowledge-base/**.sh
```

## Encryption Posture

```yaml
# No new store or cross-component connection is introduced. The only store this
# plan references is the pre-existing #9812 derive cache
# (.soleur/cache/affected-derive/), whose plaintext-exception posture was
# declared at
# knowledge-base/project/plans/2026-10-09-feat-affected-derive-cache-plan.md
# §Encryption Posture — this change adds no records, fields, or readers to it.
at_rest: []
in_transit: []
```

## Architecture Decision (ADR/C4)

### ADR

Amend `knowledge-base/engineering/architecture/decisions/ADR-242-the-local-gate-defaults-to-affected-suites-and-always-on-ratchets.md` —
new decision 22 ("declared edges gain a `glob:` kind") recording the mint/hit
degrade ladder, the G3 `GLOBENT` extension, and the per-suite dispositions;
add the rejected alternatives (file enumeration, specs/-only prefix,
magic-`*`, `ext:` grammar, extglob) to the alternatives table. This EXTENDS
decision 12's anchored matching (a third kind beside `^file`/`^dir/`) and
decision 20's closed grammar; it does not reverse either. The `#9813`
supersedes/related line joins the ADR's preamble list.

### C4 views

No C4 impact. Checked against all three model files
(`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`):

- **External human actors** — none new. The diff's actors (contributors,
  agents) are inside the repo boundary; the model's `contributor` actor
  (untrusted PR author) already exists and its only interaction surface (CI
  isolation) is untouched.
- **External systems / vendors** — none (no new service, webhook, store).
- **Containers / data-stores** — none; the local test gate is a repo-internal
  tool below the modeled component granularity (model.c4's only `affected`
  token is an unrelated observability comment at :816).
- **Actor↔surface access relationships** — unchanged.

After the ADR edit, run `apps/web-platform/test/c4-code-syntax.test.ts` +
`c4-render.test.ts` per the completeness mandate.

### Sequencing

The decision is true at merge — a single `status: accepted` amendment, no
adopting-window needed.

## Guard Contract

### Guard 1 — `glob:` edge mint (`_affected_add_edge`)

**Property.** A `glob:` declared entry mints an edge that never narrows below
the dir-prefix coverage it replaces: well-formed+dir→`^glob:`, missing head
dir→`^head/`, malformed→`^` (always-match).

**Assembly.** The single mint site `_affected_add_edge` in
`scripts/test-all.sh`, reached by every classification path (argv/stem
derivation, the `_decl` union re-add in `_affected_classify`,
`_affected_resolve_edges` buffered entries). One chokepoint; no second mint
exists.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `glob:` arm probes head with bare `[[ -d ]]` instead of `_affected_probe d` | RED — the derive-cache input census fails (unrecorded probe) |
| 2 | Mint drops the malformed arm (`glob:bad` mints a form the hit arm can miss — e.g. bare `^`, which evaluates `*\n\n*` and narrows on non-empty blobs) | RED — a malformed entry must mint `^glob:<verbatim>` and never narrow |
| 3 | Mint skips the `-d` check on head (missing dir still mints `^glob:`) | RED — dead `^glob:` edge where `^head/` preserves coverage |
| 4 | Second glob entry after a compliant first is lost (add only the first member) | RED — the union re-add must mint every `glob:` member |
| 5 | (harness) `_affected_probe` stubbed to report dir missing for a present head | RED — degrade path must be exercised, not assumed |
| 6 | (must-PASS) `glob:knowledge-base/**.sh` on the real tree | PASS — mints `^glob:knowledge-base/**.sh` |

### Guard 2 — `glob:` edge hit (`_diff_edge_hit`)

**Property.** `^glob:<head>/<pattern>` matches exactly the diff lines equal to
the bash pattern under `<head>/` — kb `.sh` selects, kb `.md` declines,
nested depths match (`*` crosses `/`), and a malformed edge matches
(never narrows).

**Assembly.** The `glob:*)` arm of `_diff_edge_hit` reading `_DEH_N` — the
same newline/TAB-split blob the `^file`/`^dir/` arms read, fed by every diff
source (name-only HEAD + range diffs, `--name-status -M` rename rows,
scoped+unscoped untracked appends, `--paths`). One matcher, one blob.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Glob arm misses the rename-source line (`R100<TAB>old.sh<TAB>new`) | RED — tab-split coverage is the property, not the file kind |
| 2 | Glob arm returns miss on malformed edge instead of match | RED — never narrow |
| 3 | Head pre-check uses substring not `\n<head>` line-boundary (`kb/x` matching `akb/x`) | RED — anchoring, not containment |
| 4 | Nested `a/b/c.sh` under head declines (a `*` that does not cross `/`) | RED — pathspec semantics |
| 5 | (dispatch) `_diff_touches` swallows `^glob:` before `_diff_edge_hit` sees it | RED — a dispatch row against the guard's own routing |
| 6 | (must-PASS) `knowledge-base/x.sh` at head root (non-canonical depth) | PASS — glob covers more than the canonical specs/ location |

### Guard 3 — census `glob:` member validation (`lint-orphan-test-suites.sh`)

**Property.** Every `glob:` entry in every `AFFECTED_*_PATHS` array resolves:
head ends `/` and is `[[ -d ]]`, tail non-empty containing `*` and no `?[` —
a dead or malformed declared glob is a static RED, never a runtime narrow.

**Assembly.** The per-entry loop over `declare -p | grep AFFECTED_*_PATHS`
arrays (the structural chokepoint — new arrays enter automatically by naming
convention). Mirrored by the suite's own fixture census.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `glob:` head names a missing dir | RED — dead edge flagged |
| 2 | `glob:` tail without `*` (a literal path in glob spelling) | RED — malformed flagged |
| 3 | `glob:` carrying `?` or `[` | RED — grammar closed at `*` |
| 4 | A bad `glob:` entry AFTER a compliant first in the same array | RED — check must not stop at member one |
| 5 | (dispatch) every `AFFECTED_*_PATHS` array emptied → 0 members checked | RED — vacuous-walk arm |

### Guard 4 — G3 closed grammar admits `glob:` entries

**Property.** A registration-only diff whose added `AFFECTED_*_PATHS` block
contains `glob:` entries stays `registration-only` (bounded selection);
entries outside the glob charset, or `glob:` in `ALWAYS_ON_SUITES`, stay
`semantic` (full battery).

**Assembly.** The awk block in the registration-only classifier
(`scripts/test-all.sh`): the in-block member regex, the two INDEX-ANCHOR
preceding-line acceptances, and the ALWAYS_ON member shape — all sites where
an entry-shaped line is judged. Admission-side only: `semantic` is the safe
arm, so the grammar may err wide on line shape but never on label binding.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `GLOBENT` absent → `glob:` entry in an added array | RED → `semantic` observed (the un-extended grammar fails safe but loses bounded selection — the property is the admission itself) |
| 2 | `glob:` entry carrying `?`/`[` admitted | RED — must stay `semantic` |
| 3 | Added array opened directly below a `glob:` entry (anchor sees glob shape) | PASS — INDEX-ANCHOR must accept the new shape |
| 4 | `glob:` line inside `ALWAYS_ON_SUITES` | RED — stays `semantic` |
| 5 | (second-member) added array with `glob:` second entry after plain first | PASS — bounded |

### Guard 5 — kb-consumers oracle `covers()` `^glob:` arm

**Property.** A `^glob:` edge covers a suite's kb ref iff the ref's subtree
can hold a glob-matching read — no false VIOLATION for a glob-covered suite,
no false green for a genuinely uncovered ref.

**Assembly.** `covers()` in the oracle heredoc inside
`scripts/test-affected-kb-consumers.test.sh` — the single coverage predicate
the ratchet's `violations()` consults for every (suite, ref) pair.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `^glob:` arm absent → all five glob'd suites flag uncovered | RED — VIOLATION rows, not a silent pass |
| 2 | Dir ref disjoint from glob head judged covered | RED — coverage must nest |
| 3 | File ref matching glob pattern judged uncovered | RED — `fnmatch` arm required |
| 4 | (dispatch) oracle run with empty rows | RED — existing `VACUOUS` arm still fires |
| 5 | (must-PASS) `knowledge-base/project/specs/…/bootstrap.sh` under `^glob:knowledge-base/**.sh` | PASS |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Add an extension/glob-aware edge kind to the edge grammar (`_affected_classify` / `_diff_edge_hit`): e.g. declared-array entries spelled `glob:knowledge-base/**.sh` evaluated as \"diff path under dir AND matches extension\"." | Proposed Solution; Phase 1 mint+hit arms; `scripts/test-all.sh` | mapped |
| 2 | "Walker suites that scan `*.sh` swap `knowledge-base/` for the glob form." | Disposition table; Phase 2 index edits | mapped |
| 3 | "`test-affected-kb-consumers` keeps `^knowledge-base/` — any kb file can be a consumer." | Disposition table row 3; array untouched | mapped |
| 4 | "fail-safe behaviour on malformed patterns (treat as match, never narrow)" | Mint degrade ladder + hit `return 0`; Guards 1–2 | mapped |
| 5 | "the census linter shape for the new kind" | Phase 2 census arm; Guard 3 | mapped |
| 6 | "interaction with the registration-only classifier's closed grammar" | Phase 2 `GLOBENT`; Guard 4 | mapped |
| 7 | "`--print-selection --paths=<kb-md-file>` no longer selects the six `*.sh` walkers; `--paths=<kb-sh-file>` still selects them." | AC FR-1/FR-2; Phase 3 t-rows | mapped |
| 8 | "`scripts/test-affected-kb-consumers` keeps selecting on any kb path." | AC FR-3 | mapped |
| 9 | "Mutation arm: a malformed glob edge fails safe (selects), never declines." | AC FR-4; Phase 3 malformed rows | mapped |
| 10 | "Byte-identical selection otherwise — `scripts/affected-prepass-bench.sh`." | AC FR-5; Phase 4 bench | mapped |
| 11 | "No CI coverage change: CI legs already run the full battery." | AC NFR-1; no workflow edits in Files to Edit | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `glob:` mint+hit arms (`scripts/test-all.sh`) | "Add an extension/glob-aware edge kind to the edge grammar" | asked |
| Six array edits (`scripts/lib/test-affected-paths.sh`) | "Walker suites that scan `*.sh` swap `knowledge-base/` for the glob form" | asked |
| Trap-tempfile 7-extension glob set | — | inferred — justification: the suite's verified read set is `.sh .bash .py .ts .mjs .js` plus `bunfig.toml`; a `**.sh` edge silently under-covers a real tracked population (kb holds 7 `.py` + 1 `.js`) — the "honest scope" doctrine from the demotion audit |
| Census `glob:` arm | "the census linter shape for the new kind" | asked |
| G3 `GLOBENT` extension | "interaction with the registration-only classifier's closed grammar" | asked |
| kb-consumers oracle `covers()` arm | — | inferred — justification: the ratchet asserts every kb-reading suite is covered by an edge; a `^glob:` edge it cannot parse flags all five glob'd suites VIOLATION — the edge kind is refused by its own coverage oracle without the arm |
| R/t/m test rows | "Mutation arm: a malformed glob edge fails safe" | asked |
| ADR-242 amendment | — | inferred — justification: `wg-architecture-decision-is-a-plan-deliverable` — a third edge kind extends ADR-242 decisions 12/20 and the decision record must ship with the change |
| `fanout-suite-scope.test.sh` verify | — | inferred — justification: it copies the index into a sandbox runner; unverified consumers are how the #7761 inert-edge class recurs |

### Split Assessment

- Subsystems touched: 3 — `scripts/`, `knowledge-base/engineering/architecture/`, `plugins/soleur/test/`
- Planned files: 9 | Estimated changed lines: ~550
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Functional Requirements

- [ ] FR-1 — `bash scripts/test-all.sh --print-selection --paths=knowledge-base/project/specs/foo.md` selects 112 registrations: the six walker labels absent from `AFFECTED_SELECTED` selected-rows, `scripts/test-affected-kb-consumers` present.
- [ ] FR-2 — `--paths=knowledge-base/project/specs/feat-sdd-implementation-mirror-guard/bootstrap.sh` (a real tracked kb `.sh`, verified via `git ls-files`) selects all six walkers (uniform `glob:` coverage, including `operator-ack-guard` per the issue's wording).
- [ ] FR-3 — `scripts/test-affected-kb-consumers` still selects on any kb path (`.md`, `.c4`, `.tsv`).
- [ ] FR-4 — malformed `glob:` entry (no `*/` head / `?`/`[` / `*`-less tail) fails safe: selects at hit, degrades at mint per the ladder, RED at census.
- [ ] FR-5 — stream-diff the two `AFFECTED_SELECTED` captures (`origin/main` vs HEAD, same probes): every row for a label outside the six is **byte-identical on every probe**; each of the six rows may differ ONLY in the kb-edge token (`^knowledge-base/` → `^glob:knowledge-base/…`) and, on the kb-`.md` probe only, the selected bit. The bench's raw row-compare flags the six rows on every probe (their edge text changes), so the identity assertion is a scripted row-wise diff, not a bare bench exit code; `bash scripts/affected-prepass-bench.sh --base origin/main --runs 1` still runs for interleaved timing + the walker's row-fidelity line.
- [ ] FR-6 — a synthetic registration-only diff adding an `AFFECTED_*_PATHS` block with `glob:` entries classifies `registration-only` (bounded), while `glob:` entries carrying `?`/`[` classify `semantic`.
- [ ] FR-7 — the census linter flags a `glob:` entry whose head dir is missing and passes all real entries.

### Non-Functional Requirements

- [ ] NFR-1 — no CI coverage change: `git diff --quiet origin/main...HEAD -- .github/workflows/` is clean (merge-base form, not the moving tip); `merge_group`/`push` still run every battery (ADR-262 preserved).
- [ ] NFR-2 — derive span probes all routed through `_affected_probe` (cache recording census green).
- [ ] NFR-3 — `glob:` arm adds no per-registration forks (pure bash `[[ == ]]` + line loop; head pre-check memo-friendly).

### Quality Gates

- [ ] `scripts/test-affected-derive.test.sh` green incl. new R-rows
- [ ] `scripts/test-all-affected.test.sh` green incl. new t/m rows (its own battery is selected by this diff: runner+index touched)
- [ ] `scripts/lint-orphan-test-suites` + its `.test.sh` green
- [ ] `scripts/test-affected-kb-consumers` green
- [ ] `plugins/soleur/test/fanout-suite-scope.test.sh` green
- [ ] `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` green after ADR edit
- [ ] `bash scripts/affected-prepass-bench.sh --base origin/main --runs 1` exit 0 (expected-delta documented)
- [ ] Full `scripts/test-all.sh --affected` run green (this diff touches runner+index → degraded-full path exercised)

## Test Scenarios

### Acceptance Tests (RED phase targets)

- **unit** — Given `glob:knowledge-base/**.sh` in a declared array, when `_affected_add_edge` runs on a tree where `knowledge-base/` exists, then `_AC_EDGES` gains `^glob:knowledge-base/**.sh` (derive R-row).
- **unit** — Given head dir absent, when mint runs, then the edge is `^knowledge-base/` (degrade, never narrow).
- **unit** — Given `glob:x` malformed, when mint runs, then the edge is `^` (always-match).
- **unit** — Given `SANDBOX_DIFF_NAMES=knowledge-base/project/specs/foo.md`, when `_diff_edge_hit '^glob:knowledge-base/**.sh'` runs, then miss; `…/x.sh` → hit; `knowledge-base/x.sh` → hit; `a/b/c.sh` under head → hit; `R100\told.sh\tnew` → hit.
- **integration** — Given the real index, when `--print-selection --paths=<kb .md>` runs, then exactly the six labels unselect; `--paths=<kb .sh>` re-selects them.

### Regression Tests

- **unit** — Given a `^glob:` edge with head that no longer exists at hit time, when the arm evaluates, then `return 0` (match) — the in-flight fail-safe.
- **unit** — Given the oracle `covers()`, when fed (`^glob:knowledge-base/**.sh`, `knowledge-base/project/specs`), then covered; fed a disjoint dir ref, then uncovered.

### Edge Cases

- Given a registration-only diff adding an array with `glob:` entries, when G3 walks it, then `registration-only`; with `?`/`[` in the glob entry, then `semantic`.
- Given `glob:` in `ALWAYS_ON_SUITES`, when G3 walks it, then `semantic`.
- Given an added array opened directly below a `glob:` entry line, when the anchor check runs, then accepted.

## Success Metrics

- kb-`.md` probe selection: 118 → 112 registrations; the six walkers (~261.5 committed s / ~340 s+ local) no longer pay on docs-only diffs.
- Zero narrowing: every mutation arm above lands RED when applied by hand before merge.

## Dependencies & Prerequisites

None beyond the tree itself. This diff touches `scripts/test-all.sh` +
`scripts/lib/test-affected-paths.sh` → `runner-changed` → the affected run
degrades to the full battery (by design; the `semantic` arm is exercised, not
a surprise).

## Risk Analysis & Mitigation

| Risk | Mitigation |
|---|---|
| Under-coverage: a glob'd suite actually reads non-globbed kb files | Per-suite verified read set recorded in the disposition table (source lines cited); trap-tempfile's 7-extension set is the explicit counterexample the issue's `*.sh` framing missed; the kb-consumers ratchet flags any uncovered ref |
| The `#9812` derive cache serves stale records across the grammar change | The derive-code hash keys on the extracted span — new code in the span flushes every record once (by design); no manual invalidation |
| A `glob:` token lands in a `test-relevance-paths.sh` / `AFFECTED_CONSUMED_EDGES`-referenced array | Consumed entries are copied verbatim by `_affected_resolve_edges` and matched as unanchored substrings — a `glob:` there is a dead edge, never a glob. The kind is declared-array-only; a comment at `AFFECTED_CONSUMED_EDGES` states it, and the census arm is scoped to `AFFECTED_*_PATHS` by construction |
| Sibling pins on line-anchored extractions in `test-all-affected.test.sh` (e.g. the `git ls-files` opener+3 pin, the `_AFFECTED` block extraction) drift when lines are inserted nearby | The new code lives in `_affected_add_edge` / `_diff_edge_hit`, not in the pinned blocks; plan instructs re-deriving any pin whose anchor text the diff touches (learning 2026-10-05 Session Error 5) |
| `fanout-suite-scope` sandbox lacks `knowledge-base/` so mint degrades `^glob:`→`^knowledge-base/` mid-run | Phase 3 verifies; if its linter arm flags missing head dirs the fix is forward (fixture dir or arm ordering), not reverting to substring semantics |
| A `glob:`-in-`ALWAYS_ON_SUITES` or non-`*` glob in a future bounded diff silently admitted | Guard 4 rows pin `semantic` for both |
| Extension-level coverage honesty: a structurally-valid glob that misses a scanned extension (the trap-lint `**.py` case) passes every static arm while silently under-covering | The census checks glob *structure*; the kb-consumers ratchet checks dir *reach*; neither sees *extension completeness* (the self-edge lesson, `2026-09-20-…-itself-read-as-coverage`). The pin is the disposition table's per-suite verified read set + the t-rows asserting each extension family selects |

**Precedent-diff (deepen 4.4).** Pattern precedent exists — the
`^file`/`^dir/` mint+match pair this grammar extends. Side-by-side:

- mint: existing arms probe the full path with `_affected_probe e` then
  `-d`-normalize to `^<dir>/`; the `glob:` arm probes only `<head>` with
  `_affected_probe d` (the full pattern is not a filesystem object) and
  mints `^glob:` / `^<head>/` / `^glob:<verbatim>` per the degrade ladder —
  same probe-channel, same single minter.
- match: `*/)` and `*)` arms are one `[[ == ]]` substring test on the
  memoized blob; the `glob:` arm is a head pre-check plus a per-line
  `[[ == ]]` — same blob, same anchoring contract, one extra loop.
- degrade class: same as every `_AFF_LIB` consumer — fail toward match,
  never narrow, never block the walk.

## Resource Requirements

Single-agent implementation; ~550 changed lines; one full local battery for
the degraded-full proof plus the targeted suite set.

## Future Considerations

The same `glob:` kind can narrow other over-broad dir edges later (e.g. the
walkers' `plugins/`/`scripts/` prefixes on `.ts`-only diffs) — deliberately
out of scope here: the issue asks for the kb edge only, and each further swap
needs its own verified read set. #9814 (weight-drift detector) and #9815
(vitest related-files) are separate issues in the #9763 arc.

## Documentation Plan

- ADR-242 amendment (decision 22) — in this diff.
- Array-header grammar comment in `scripts/lib/test-affected-paths.sh` —
  three entry kinds, degrade ladder.
- `plugins/soleur/skills/work/SKILL.md` needs no edit (it names edge
  *mechanisms*, not entry kinds).
- PR body: `Closes #9813`; `semver:patch` label (no `plugins/soleur/` product
  code — check at ship: the touched `plugins/soleur/test/*.test.sh` is
  test-only; `## Changelog` section still required if the label set applies).

## References & Research

### Internal References

- `scripts/test-all.sh` — `_diff_edge_hit:2096`, `_diff_touches:2489-2548`,
  `_affected_add_edge:2710`, `_affected_classify:3209`, registration-only awk
  (G0–G5, `:2270-2466`), `_affected_probe:2662`, `_aff_label_map:2200`
- `scripts/lib/test-affected-paths.sh` — header contract, six arrays
  (`:1776-2014`), `AFFECTED_SCRIPTS_TEST_AFFECTED_KB_CONSUMERS_PATHS:441`,
  `AFFECTED_CONSUMED_EDGES:294`
- `scripts/lint-orphan-test-suites.sh:1099-1134` — declared-member census
- `scripts/test-affected-kb-consumers.test.sh` — oracle `covers():268-275`,
  `KB` regex `:108`, baseline `scripts/test-affected-kb-consumers.baseline.txt`
- `scripts/lint-trap-tempfile-ownership.py:155-159,1209` — `ALL_EXT`/`_in_scope`
- `plugins/soleur/test/operator-ack-guard.test.sh:161-167,358-361` — `^knowledge-base/` exclusions
- `plugins/soleur/test/operator-agent-runnable.test.sh:365` — `ls-tree … | grep '\.sh$'`
- `scripts/lint-shell-capture-exit.py:1559` — `git ls-files -z '*.sh'`
- `scripts/lint-shell-trace-credential-refusal.py:1180-1184,2233` — Rule-E pathspecs
- ADR-242 (decisions 12 anchored edges, 16 bench contract, 18 closure leaves,
  19 demotion ratchet, 20 bounded registration-only, 21 derive cache),
  ADR-262 (PR-gated batteries), ADR-193 (vacuity floor), ADR-181 (counted
  declines)
- `knowledge-base/project/brainstorms/2026-10-06-runner-sut-registration-narrowing-brainstorm.md` —
  machinery map, fail-toward-coverage hazards, "Soleur-repo-only" scoping
- `knowledge-base/project/learnings/2026-10-09-committed-ci-weights-are-not-local-costs.md` —
  measure on the paying machine; enumerate walker scope mechanically
- `knowledge-base/project/learnings/2026-07-15-narrowing-is-not-anchoring-and-a-documented-class-recurred-four-times-in-one-pr.md`,
  `2026-09-30-print-affected-set-prints-classes-not-selection-…`,
  `2026-10-06-one-self-inclusion-claim-hid-three-edge-provenances-…`,
  `2026-10-05-a-guard-built-from-spellings-…` (fixture idiom + TEST_GROUP leak),
  `2026-09-23-a-packed-string-searched-by-glob-is-a-quadratic-map.md` (no
  packed-glob maps — the line loop is over a memoized blob, not a glob map),
  `2026-03-21-lefthook-gobwas-glob-double-star.md` (gobwas `**` ≠ bash
  `[[ == ]]` — semantics pinned in Proposed Solution),
  `test-failures/2026-09-20-a-classified-edge-that-pointed-at-itself-read-as-coverage.md`
  (structure-valid ≠ coverage-correct — the extension-completeness risk row)

### Related Work

- Issue #9813 (this), arc parent #9763 (closed), epic #9307 (open),
  #9812/PR #9824 (derive cache, merged 2026-10-10), #9564 (keep-deferred;
  `scripts/watch-registration-narrowing-9564.sh` is the measurement trigger —
  untouched by this change), #9814/#9815 (siblings)

## Research Insights

**Premise Validation (Phase 0.6).** Issue #9813 OPEN. Cited refs verified:
#9763 CLOSED (arc continues via sub-issues), #9307 OPEN, #9812 CLOSED via
merged PR #9824 (squash `302f311d82`, 2026-10-10). Every cited file/symbol
exists: `scripts/test-all.sh` (`_affected_classify:3209`, `_diff_edge_hit:2096`),
`scripts/lib/test-affected-paths.sh`, `scripts/affected-prepass-bench.sh`,
`scripts/test-affected-kb-consumers.test.sh` (the issue's `test-affected-kb-consumers`
is a suite label, not a script path), `scripts/suite-durations.tsv`, the
weights learning. Measurement reproduced: `selected=118 of=596 always_on=111
edge=7` on `--paths=knowledge-base/project/specs/foo.md`. Nothing stale.
One refinement, not a reversal: `operator-ack-guard` formally excludes kb —
kept on `glob:` to honor the AC and uniform mechanism (see Reconciliation).

**Property List (Phase 0.6b).** (a) kb-`.md`-only diff declines the six
walkers (~261.5 committed s saved); (b) kb `.sh` diff (incl. a NEW `.sh`)
still selects them; (c) `test-affected-kb-consumers` selects on any kb path;
(d) malformed new-kind entries fail toward match, never narrow; (e) selection
byte-identical everywhere else; (f) no CI coverage change.

**Cut List (Phase 0.6b).** file-edge enumeration → property (b) unsound
(issue's own argument, re-verified). specs/-only dir prefix → weaker (b′),
future kb `.sh` elsewhere under-covers. Remove `knowledge-base/` from
ack-guard → breaks AC wording + baseline churn + future-exclusion drift;
recorded in Alternatives. `ext:` grammar / extglob / magic-`*` → mechanisms
buying nothing over the `glob:` form; each recorded in Alternatives. Second
mechanism (consumed-edge remap) → consumed edges are substring/unanchored and
would widen, not narrow.

**Value-Proposition Measurement (Phase 0.6c).** Claim measured, not asserted:
`--print-selection --paths=knowledge-base/project/specs/foo.md` on this
branch → `selected=118 of=596`; the seven edge rows sum 329,843 ms
(`scripts/suite-durations.tsv`); the six removable rows sum 261,457 ms.
Local multiplier ~2–3× per the cited learning.

**Consumers of the edge grammar (grepped, not assumed).** Mint: `_affected_add_edge`
only. Match: `_diff_edge_hit` only (via `_diff_touches`). Static: census
linter + its own suite's fixture arm + `grep-q-pipe-guard.test.sh` (reads one
unrelated array) + `fanout-suite-scope.test.sh` (copies index into sandbox).
Coverage oracle: `test-affected-kb-consumers` `covers()`. Grammar: G3 awk.
Docs: `plugins/soleur/skills/work/SKILL.md` (mechanism-level, no edit).
`scripts/watch-registration-narrowing-9564.sh` (watch only).
`scripts/lib/test-affected-derive-cache.sh` (span-hash flush by design;
probe-channel rule binds the implementation). `.claude/hooks/*` tests
(fixture mentions only). `plugins/soleur/skills/plan/references/plan-sharp-edges.md`
(catalogue; its own rule about naming list-consumers applied here).

**Functional overlap (Phase 1.5b, inline — no subagent capability in this
environment):** no community artifact substitutes for a grammar kind inside
this repo's runner; the check ran as a consumer grep instead of the
`soleur:engineering:discovery:functional-discovery` spawn. Same for
`repo-research-analyst`/`learnings-researcher` (Phase 1) and the
domain-leader/spec-flow/advisor spawns — all ran inline; findings are
recorded in the body sections they feed.

**External research (Phase 1.6):** skipped — repo-internal machinery with a
complete local evidence base; no security/payments/external-API surface.

## Domain Review

**Domains relevant:** Engineering only — internal test-gate machinery; no
user-facing surface (mechanical UI-surface override checked: no `*.tsx`,
`page.tsx`, `components/**` in Files to Create/Edit).

### Engineering

**Status:** reviewed (inline — subagent spawn unavailable in this
environment)
**Assessment:** dev-experience/cost work on Soleur's own local gate;
fail-toward-coverage is the binding doctrine throughout (ADR-242);
Soleur-repo-only concept — do not leak `glob:` into the #9307 PR-2
user-facing spec.

### Product/UX Gate

Not applicable — Product domain not flagged and the mechanical UI-surface
override did not fire.

## Open Code-Review Overlap

- **#8659** (33 suites replace test-helpers' composed EXIT trap) — touches
  `scripts/test-all.sh` in its body. **Acknowledge:** different concern; the
  new test rows in this plan follow the prescribed fixture idiom (scratch-root
  per-process dirs, `assert_fixture_dir`, no second `EXIT` trap).
- **#7942** (two `*.mutation.sh` batteries run in no gate) — names
  `scripts/test-all.sh`. **Acknowledge:** registration-shape issue, not the
  edge grammar.
- **#8800** (census sandbox shares inodes/symlinks with live repo) — touches
  `scripts/lib/test-affected-paths.sh` + `scripts/test-all-affected.test.sh`.
  **Acknowledge:** new battery rows use `SANDBOX_DIFF_NAMES` env-driven diffs
  and introduce no new write-through paths.

## Sharp Edges

- The `^glob:` mint depends on `_affected_add_edge`'s `glob:` arm being placed
  BEFORE the `[[ -e ]]` probe — after it, every `glob:` entry dies silently
  on the existence test.
- Every existence check inside the derive span MUST go through
  `_affected_probe` — a bare `[[ -d ]]` is an unrecorded input and the
  derive-cache input census fails.
- `test-all-affected.test.sh` anchors blocks by line position (`grep -A3`
  pin at opener+3, awk-range extractions); inserting lines inside a pinned
  block without moving the sibling pin reddens the battery for a reason
  unrelated to this change.
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO` text, or omits the threshold fails `deepen-plan` Phase 4.6 —
  filled above.
- The `runner-changed` full-battery degrade on this diff is expected output,
  not a regression — budget the run.
