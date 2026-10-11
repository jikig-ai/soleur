---
module: System
date: 2026-10-10
problem_type: workflow_issue
component: testing_framework
symptoms:
  - "A knowledge-base-only .md diff selected all six corpus-walker suites (kb-md probe: selected=118 of 596) — 'knowledge-base/' was the finest edge a two-kind grammar could express, so every kb change paid ~330 committed seconds"
  - "The consumer oracle's covers() flagged two REAL kb reads no literal edge covered: provision-* DPA_FILE .md for operator-ack-guard, ADR-207 for operator-agent-runnable"
  - "The plan's malformed-entry mint was a bare '^' — select-NOTHING (e=\"\" → *\\n\\n*), the inverse of the intended always-match (CPO blocking condition, amended pre-work)"
  - "Review B1: path-semantic malformed heads (.., /, //, /./, /../) minted dead edges that pass a -d probe yet can never match a repo-relative diff line — a silent narrow the census admitted"
  - "A '*/'-terminated glob tail is well-formed yet no path can ever satisfy it — same dead-edge class, caught by the same doctrine pass"
root_cause: scope_issue
resolution_type: code_fix
severity: medium
tags: [affected-selection, declared-edges, glob-grammar, fail-toward-coverage, dead-edge, coverage-honesty]
synced_to: [plan, work, review]
---

# Learning: a declared edge must say what the walker reads, and a malformed one must fail wide

Issue #9813 / PR #9945 (`Closes #9813`). The affected-test selector's declared-edge grammar knew two kinds — `dir/` prefix and exact file — so the six kb corpus-walker suites declared `knowledge-base/` and selected on *any* kb diff, including pure-.md changes the corpus scan could never be moved by.

## Problem

1. **Granularity, not direction.** Dir-prefix edges exist for walk-class suites; what was missing was an edge kind that can express "under this dir, only these extensions." Measured cost of the over-selection: a `.md`-only kb diff selected 118 of 596 registrations — 111 always-on plus 7 edge-selected suites totalling ~330 committed seconds (~248 s attributable to the five extension-bounded walkers; kb-consumers selects by design, agent-runnable kept its edge — see 4).
2. **A grammar hole invites silent narrowing.** The first mint design degraded a malformed `glob:` entry to a bare `^` edge — but an empty pattern evaluates `*\n\n*` against the normalized diff blob: it matches only diffs containing an empty line. The intended always-match was a select-nothing in disguise (CPO blocking condition; five plan sites carried the defect).
3. **Review B1: `-d` truth is path-semantic, not match-semantic.** A `../x/*.sh` or `/x/*.sh` glob passes a `-d` probe — the dirs resolve — yet can never match a repo-relative diff line. The mint emitted a well-formed `^glob:` edge that selected nothing: a dead edge that *narrows*, the dangerous direction, while every static guard read green. `a//b`, `a/./b`, `a/../b`, and `*/`-terminated tails are the same class.
4. **"All six walkers are `*.sh`-bounded" was a premise, not a measurement.** `operator-agent-runnable`'s Guard-1 discovers its corpus by `git grep -l --untracked` for the generated-script marker on ANY extension — a content-keyed read. A kb `.md` quoting the marker is in its corpus; `**.sh` would under-cover it. It keeps `knowledge-base/` (~16 committed s is the price of honesty), documented inline at `test-affected-paths.sh`.

## Solution

A third declared-edge kind `glob:<literal-head>/<glob-tail>` mints `^glob:<pattern>`; a diff line under the literal head matching the tail under bash `[[ == ]]` semantics (`*` crosses `/`, so `knowledge-base/**.sh` covers both `x.sh` and `a/b/c.sh`) selects the suite. The degrade ladder fails toward coverage at every rung:

- **valid + live head** → `^glob:<pattern>`
- **missing head dir** → `^<head>/` — the dir-prefix edge the entry replaced, never narrower
- **malformed** (charset byte, non-repo-relative or non-`/` head, `*`-less or `/`-terminated tail) → `^glob:<entry verbatim>` — always-match: the hit arm's own malformed rule `return 0`s it
- **no metachar** → recurses as a literal path entry

The malformed-shape doctrine — closed charset `[-A-Za-z0-9_./*]`, repo-relative head, matchable tail — is pinned identically at four behavioral sites (mint arm, `_diff_edge_hit` revalidation, census arm, `covers()` oracle) with a fifth deliberately permissive: `GLOBENT` in the registration-only classifier admits a superset (e.g. `../` heads) because admission only marks a diff registration-only — the malformed member still mints always-match and the census REDs it. The asymmetry to internalize: a malformed *edge* must match everything (widen at runtime); a malformed *declaration* must be a loud static RED (fail closed at lint).

Per-suite dispositions were verified against each suite's discovery code, not its name: five extension-bounded walkers took globs (`lint-trap-tempfile-ownership` carries the 7-entry `ALL_EXT` + `bunfig.toml` set — the issue's `*.sh` framing would have under-covered it), agent-runnable kept `knowledge-base/` (content-keyed), `test-affected-kb-consumers` kept `knowledge-base/` (any kb file is a consumer), and the two real `.md` reads the oracle surfaced got literal file edges — the `.md`-decline contract holds for the corpus scan, not for reads a suite actually has.

## Key Insight

- **Trace every degraded form through the real matcher to a direction verdict.** Syntax-validity, filesystem-existence, and diff-line-matchability are three different predicates — B1's heads passed the first two and failed the third. Widen is visible cost; narrow is silent under-selection on exactly the diffs the suite guards.
- **Verify the read set at the discovery code, not the naming.** A disposition table needs a mechanism column per suite: path-walk vs content-keyed (`git grep` marker) vs any-file consumer. Uniformity is not evidence.
- **"Same logic at N sites" is not a contract.** Name each site's required relation (identical / deliberate superset), state why the permissive direction is safe, and pin the divergence with a test row (`ok_idx_glob_dotdot`) — otherwise the permissive site drifts undetected.
- **Over-coverage hides under-coverage.** Honest narrow edges are what let the consumer oracle see the two real `.md` reads; the broad `knowledge-base/` edge had masked them.
- **Fixture needles must be spelled un-matchably** under a corpus oracle: composed literals (`"knowledge""-base"`, `${_KB}`) and `sandbox`/`fixture` tokens keep test strings from being charged as real reads.

## Session Errors

1. **Mid-run edits of files a running battery executes (twice).** Bash reads scripts incrementally; spliced bytes produce phantom failures — killed and re-ran. **Prevention:** if a battery is in flight, edits to files it executes wait, or run against a snapshot copy (the `build_sandbox`/`run_arm` idiom already runs copies).
2. **`EXPECTED_ASSERTIONS=3` declared on a 2-assertion row (M25)** — aborted aggregation. **Prevention:** the declared floor is itself a pin; count `assert_*` calls in the row before writing it.
3. **Stale `selected=N of=M` pins after the sandbox keep-list grew** (p1/p4 `of=6`→`of=13`). **Prevention:** corpus-derived counts are floors or membership assertions, never bare equalities — durable forms already exist (`_n >= 11`, `MIN_CASES`).
4. **tg5 mutator targeted the removed `"knowledge-base/"` literal** after the array swap. **Prevention:** mutators anchor on the NEW text; grep the mutator's needle exists post-swap.
5. **"Six extension-bounded walkers" premise** — agent-runnable is content-keyed; disposition changed under review. **Prevention:** Rule B above — mechanism column, not naming.
6. **M26 vacuity floor `>=12` stale** after the disposition revert (11 entries). **Prevention:** floors citing counts re-derive at run time — the grep already does; the constant must follow the disposition.
7. **Real-runner arms failed empty under sibling-gate contention** (f2b/tg2 rc=1/empty stream; #8163-class). **Prevention:** re-run to isolate before diagnosing; the runner's contention banner is the tell.
8. **tmp-reaper deleted a mid-run TESTROOT** (rc=143 arm kills ×2). **Prevention:** external host flake; retry.
9. **Two-dot `git diff origin/main` showed upstream workflow drift as if it were the branch's change** — resolved via three-dot diff + `git log origin/main..HEAD -- path`. **Prevention:** NFR checks always use the three-dot merge-base form.
10. **Substring-unique fixture anchors collide with ANY deeper-indented `*) return 0 ;;`** — `test-all-killed-classification`'s budget splice counts `    *) return 0 ;;` as a *substring*, so a bare arm at ≥4-space indent is a silent second occurrence (T14 broke on CI, nothing local did). **Prevention:** prefer `[[ == ]]` tests over a bare `*) return 0 ;;` arm inside `case` blocks in test-all.sh; the file is grep'd for structural literals by at least two downstream batteries (the `--rows` tiling anchors in `scripts-shard-totality-mutations` are the sibling trap — a `DECLARED_TOTAL` bump must grep the range literals repo-wide).
11. **Forwarded (planning):** label-vs-file confusion on `test-affected-kb-consumers` (a suite label, not a script path); malformed-mint redesign pre-CPO; 4 MD038 violations fixed.

## Test-case patterns worth copying

- **Extracted-SUT mutation sandbox** (`test-affected-derive.test.sh`): the derive block is cut from the runner by content anchor and `eval`'d in a subshell — the runner's own logic unit-tested without a second implementation.
- **One row, all malformed shapes, verbatim-mint assertion** (Rg3, 13 shapes): the expected mint for each shape is part of the assertion, not "something degraded."
- **Ordinal-anchored mutation** (`mutate_glob_entry`): replaces the N-th member anchored at a named array — needed because siblings carry byte-identical entries.
- **Vacuity floor as a precondition** (M26's `>=11` entry count) so a GREEN can never mean "the walk never reached the entries" — plus `EXPECTED_ASSERTIONS` per-row floors and `PASS+FAIL==cases` conservation.
- **Deliberate-superset pin** (`ok_idx_glob_dotdot`): proves GLOBENT *does* admit `../`, making permissive-on-purpose falsifiable.
- **Stream-diff verification**: byte-comparing `AFFECTED_SELECTED` rows merge-base vs HEAD proved zero sel-bit flips — "cannot narrow" verified empirically, not argued.

## Related Documents

- ADR-242 decision 22 (this amendment); ADR-262 (CI always-selects backstop); #9307 anchored-edge spec `feat-affected-parallel-test-gate/edge-anchoring-corpus.md` (verify-the-negative replay method).
- `learnings/test-failures/2026-09-20-a-classified-edge-that-pointed-at-itself-read-as-coverage.md` — fail-toward-coverage doctrine's origin (#8322).
- `learnings/2026-10-01-anchoring-a-matcher-flips-its-error-direction-and-the-ratchet-i-wrote-never-ran.md` — anchoring flips error direction (#9307).
- `learnings/test-failures/2026-09-29-my-elif-arm-ate-the-selection-walk-and-two-review-seats-caught-what-my-unrun-arm-would-have.md` — #9197 arm-consumption; why GLOBENT went inside existing alternations.
- `learnings/2026-09-14-i-tested-both-endpoints-and-left-the-wire-between-them-unpinned.md` — file-selected suites can't see repo-global ratchets.
- `learnings/2026-10-06-one-self-inclusion-claim-hid-three-edge-provenances-across-four-suites.md` — edge-provenance classification method.
- `learnings/2026-10-09-committed-ci-weights-are-not-local-costs.md` — walker-scope enumeration + ~2-3× local multiplier.
- `learnings/2026-03-21-lefthook-gobwas-glob-double-star.md` — `[[ == ]]` vs gobwas `**` semantics.
- `learnings/2026-09-23-a-packed-string-searched-by-glob-is-a-quadratic-map.md` — why the hit arm is a line loop, not a packed-glob map.
- `learnings/2026-10-07-my-watcher-suite-sampled-one-shape-per-axis-and-my-comment-called-a-load-bearing-flag-redundant.md` — one-shape-per-axis fixture failure.
- `learnings/2026-10-05-a-guard-built-from-spellings-needed-an-allowlist-and-the-affected-run-saw-two-ratchets-my-targeted-tests-could-not.md` — #8659 fixture idiom lineage.
- Issues: #9813 (this work), #9763 (arc), #9812/PR #9824 (derive cache — `_affected_probe` discipline), #9307 (epic), #9814/#9815 (arc siblings), #9564, #9441, #8621, #8163 (flake class), PR #9893 (merged mid-review; additive, no conflict).

## Follow-ups

- **Deferred-scope-out (filed at ship):** under-cover siblings — `guard-vacuity-floor`/`lint-orphan-test-suites` declare edge arrays over the roots that hold tests today; a `*.test.*` under an unlisted root (`knowledge-base/`, `bin/`) is scanned but never selects; `repo-write-boundary` reads whole-tree `*.sh` with no declared array. The `glob:` kind now makes the fix expressible.
- **Deferred advisories:** `_affected_glob_split` extraction (next grammar touch); `|` in verbatim mints (cosmetic); `*bunfig.toml` overmatch (widen-only); edge-satisfiability witness arm in the census (a synthesized `head+x`-shaped diff line would subsume future unenumerated dead classes — prevention seat's top candidate).

## Tags

category: workflow-issues
module: System
