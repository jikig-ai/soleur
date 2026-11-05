# Pattern Recognition Specialist — PR #12127 (feat-one-shot-10861-pr5z-strict-zero)

Seat: `soleur:engineering:review:pattern-recognition-specialist` · HEAD `79db88e18b` · diff `origin/main...HEAD` (10 commits)
Scope read: `scripts/ci-pr-affected-replay.py`, `plugins/soleur/test/ci-pr-affected-replay.test.sh`, `scripts/lib/test-affected-paths.sh`, `scripts/ci-pr-affected-audit.accept.tsv`, `scripts/test-all.sh`, `.github/workflows/ci.yml`, `.gitattributes`, runbook §7, ADR-276 amendment, `scripts/followthroughs/ratchet-observation-window-10865.sh` (probe — the marker/STEP consumer).
Report-only. Verified against a hand-built fixture in `mktemp -d -t soleur-seat.RYEe` (git repo: base commit without a baseline, PR commit adding `scripts/bl-ok.tsv` + empty `scripts/bl-empty.tsv`; real `lint-ratchet.py`, real `--list` rows) — three live `ratchet` runs plus a base-unresolved control. No writes to the worktree; no suite runs.

## Executive summary

- Findings: 0 P1 · 1 P2 · 5 P3
- The change is a clean class-level fix: the `baseline-reintroduced` arm is placed exactly where the settled ruling put it (before the `baseline-deleted`/`new-pair` block, so `findings[0]` names the marker while `elif new:` still emits per-pair detail), every downstream consumer of the token grammar accepts it unchanged (`[a-z0-9-]+` in ci.yml's sed and the probe's `MARKER_RE`), the 42 accept rows deleted are exactly the set keyed on the removed path, and the new edge array follows the file's declaration convention rather than restating a computed predicate. The one P2 is the textbook instance-not-class miss this seat exists for: the contract sentence is restated in three spots inside the same file, and the docstring sweep updated two of them (`ORDER`, `BASELINE STATE`) while leaving the definitional sentence and its argparse `help=` restatement in the old vocabulary.
- Verified live: base-absent/HEAD-present exits 1 with `reason=baseline-reintroduced` for a contentful file, an empty file, and a covered live set; `new-pair` detail co-fires beneath the marker; `grown` never prints; and a malformed re-add co-fires `stale-line` — which drags in a remedy tail that instructs an impossible `git checkout origin/main -- <rel>` and a `--print-baseline` recipe that re-creates the forbidden file.

## Findings

### P2-1 — Contract restatement swept by instance, not by class: two definitional spots still describe the committed-baseline world

- **Location:** `scripts/ci-pr-affected-replay.py:135-136` (RATCHET paragraph, opening sentence) and `scripts/ci-pr-affected-replay.py:2517` (`sub.add_parser("ratchet", help=...)`).
- **Pattern:** the fix-updated-instances-not-the-class miss. The PR's own sweep list (spec `tasks.md` 1.2) named ORDER, BASELINE STATE, "(adoption, deletion)" and `--print-baseline` — and updated exactly those — but the same contract is *restated* at the paragraph's own opening ("green on a tree whose audit exits 1: the live gap set … must EQUAL a committed, shrink-only baseline") and again, in shorter form, in the argparse `help=` string ("green on a tree the audit fails: live gap pairs must equal the committed shrink-only baseline"). Both survived unchanged.
- **Why it matters:** runbook §7 defers to this exact text as the contract ("Its contract … is the RATCHET section of `python3 scripts/ci-pr-affected-replay.py --help`"), so the cited contract opens by describing a file that no longer exists and a comparison that can never run; an operator reading `--help` during triage of a `baseline-reintroduced` red is told the check "EQUALs a committed baseline" one paragraph before being told a re-added baseline is refused. A sweep that greps *restatable* phrases ("committed", "shrink-only", "EQUAL") rather than a task list would have caught both sites. (`grep -n 'shrink-only' scripts/ci-pr-affected-replay.py` still returns hits.)
- **Suggested fix:** one-line rewrite of each to the strict-zero shape already used in ci.yml's comment ("live gap pairs must be empty; a baseline file at the watched path is `baseline-reintroduced`"). No test pins either string.

### P3-1 — Co-firing `stale-line`/`baseline-dup`/`baseline-order` emits remedies that contradict the verdict (verified live)

- **Location:** `scripts/ci-pr-affected-replay.py:2090-2097` (the shared remedy tail), triggered from `:2066-2074`.
- **Evidence (live run):** a re-added `scripts/bl-ok.tsv` containing one non-live line produced `baseline-reintroduced` + its correct `remedy: delete <rel>` — followed by `stale-line` detail and the tail `remedy: … restore main's copy with git checkout origin/main -- scripts/bl-ok.tsv, then run: python3 -I scripts/ci-pr-affected-replay.py ratchet --print-baseline > scripts/bl-ok.tsv.new && mv …`. Post-merge, `origin/main` has no such file (that is the definition of the state the arm catches), so the first command cannot succeed; the second re-creates the file the verdict forbids, keeping the run red.
- **Nuance:** CTO ruling row 11 settled that the *verdict lines* may co-fire ("a malformed re-add … correct") — this finding is narrower: the *remedy text* the co-firing drags in assumes the file should be repaired, which is never true under `baseline-reintroduced`. Gate the tail on `base_text is not None` (or on `"baseline-reintroduced" not in names`). Confusing, self-limiting — not dangerous.

### P3-2 — Asymmetric assertion depth: the new arm's emitted text is unasserted

- **Location:** `plugins/soleur/test/ci-pr-affected-replay.test.sh:2473-2474` vs the established idiom at `:2475` (`row_rt_deleted` greps its remedy verbatim: `grep -qxF -- 'remedy: restore it from main: git checkout origin/main -- scripts/bl-ok.tsv'`).
- **Pattern:** `row_rt_reintroduced` asserts the marker (`rt_in … 1 baseline-reintroduced` → anchored `reason=` regex — good, satisfies cq-assert-anchor-not-bare-token) and `! grep -q '^grown'` (the load-bearing absent-grown assertion the ruling demanded), but neither the `baseline-reintroduced\t<rel>\t…` detail line nor the `remedy: delete …` line is asserted anywhere. A string-replace mutant that guts the new arm's message while keeping the reason token survives all three new mutants' proof row. One `grep -qF 'remedy: delete scripts/bl-ok.tsv'` closes the asymmetry with a pattern the file already uses.

### P3-3 — "Adoption" vocabulary survives at five sites (renamed contract, unrenamed labels)

- `plugins/soleur/test/ci-pr-affected-replay.test.sh:2970` — chk description still reads "a PR-tree helper that always reports adoption changes no verdict" while the same row's inline comment (`:2515`) was updated to "baseline-reintroduced" — an inconsistency introduced *inside this diff*.
- `plugins/soleur/test/ci-pr-affected-replay.test.sh:4889,4895` — mutant names `ratchet-adoption-refused` / `ratchet-unresolved-base-is-an-adoption` (the latter now yields a `baseline-reintroduced`-shaped outcome).
- `scripts/ci-pr-affected-replay.py:1869` — `ratchet_base` docstring "An unresolvable base is exit 2, never an adoption." The mechanism is right (and now more important — a fake `None` base is what manufactures `baseline-reintroduced`); the noun is retired.
- `plugins/soleur/test/ci-pr-affected-replay.test.sh:2273` — fixture `rt_b_adopt`/`rt_p_adopt`/`adopt` now builds the reintroduced shape; the name describes a verdict that no longer exists.
- All cosmetic; the settled token is used everywhere it is load-bearing. Flagged so the next reader does not re-derive that "adoption" is dead vocabulary in this file while it lives in `lint-ratchet.py` (a different, still-living contract — correctly untouched).

### P3-4 — Runbook merged row contradicts this PR's own ruling record on co-firing

- **Location:** `knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` remedy table — "`stale-line`, `baseline-dup`, `baseline-order`, `grown` … unreachable at the default path now that no committed baseline exists".
- **Evidence:** the PR's own `decision-challenges.md` row 11 records "`stale-line`/dup/order may co-fire on a malformed re-add (correct)", and my live run confirms they print under the `baseline-reintroduced` marker. "Unreachable at the default path" is true only for `grown` (gated on `base_text is not None`); the other three are reachable whenever a malformed file is re-added. One clause — "unreachable unless a baseline is re-added (then they co-fire as detail under `baseline-reintroduced`)" — makes the doc agree with the code and the ruling.

### P3-5 — Residual stale framing in surfaces the PR touched but did not finish sweeping

- Runbook §7 `pass` row still reads "live equals the baseline" and the section still opens "The audit exits 1 on `main` today" with a `wc -l` instruction on the deleted file (`receipts/audit-final.txt` on this branch records `gap_suites=0`).
- `.github/workflows/ci.yml` comment (rewritten in this PR) keeps the now-vacuous framing "green on a tree whose audit exits 1 when the live set … is empty" — audit-red ⟺ ratchet-red under strict zero, so the antecedent is dead.
- Both are the same sweep-completeness class as P2-1; folded here because a sibling seat's P2 already prices the runbook opening.

## Settled rulings — verified, with the one caveat each

- Token `baseline-reintroduced`: implemented; accepted by every `[a-z0-9-]+` consumer (ci.yml `sed` extractor, probe `MARKER_RE`) with no consumer change needed — the closed `baseline-*` grammar paid off.
- Present/present `--baseline` machinery kept: `:2066-2078` intact; `row_rt_grow_*`/`stale`/`dup`/`order` rows unchanged and still reachable via `--baseline`/stale bases. `baseline-deleted` retained (`:2061`).
- Arm BEFORE new-pair block (marker=`findings[0]`): verified in code (`:2058` before `:2061`) and live — `reason=baseline-reintroduced` printed with `new-pair` detail lines beneath it.
- Reintroduced row asserts absent-grown: `! grep -q '^grown'` at `:2473`; by construction `grown` cannot fire when `base_text is None` (`:2075`), so the assertion exists solely to kill `ratchet-adoption-refused` — correct.
- Sequence-after-#12128: drift receipt records the absorbed `codeql-to-issues` edge; commit `79db88e18b` declares it.
- Label release post-merge / single deletion commit: `ab487915f1` bundles `git rm` + arm + tests + `.gitattributes` + 42 accept rows + range — one commit, as ruled.
- ci.yml step name untouched: confirmed `Ratchet the audit against the committed baseline` byte-identical; the probe keys on it (`ratchet-observation-window-10865.sh:88 STEP=`) — the ruling's justification verified, and the probe already treats baseline-absent-at-tip as the end state (`:498`).

## Prompt-specific checks

- **Anti-patterns duplicated from surrounding code:** the new arm clones the `baseline-deleted` shape including bare `% rel` (unquoted) in remedy text vs `q(rel)` in the detail line — an inherited idiom, identical on both arms; not a new defect.
- **Assertion rows a comment could satisfy:** none — every reworked row's assertions are load-bearing (each half of `row_rt_reintroduced` kills a distinct mutant: `std adopt` kills `tolerated`/`live-gated`, `good adopt` kills `content-weakened` since `head_text=""` is falsy).
- **Test rows that vacated:** `row_rt_adopt`/`row_rt_adopt_unequal` were replaced by `row_rt_reintroduced`/`row_rt_reintroduced_newpair` covering the same fixture arms at parity-plus (the deleted contract cannot vacate); no `chk` references dead rows; `DECLARED_TOTAL=599` matches `473 ^mutate + 126 ^ow_mutate` and ranges tile 1-193/194-386/387-599 (new mutants at ordinals 458-461, inside arm c).
- **Edge arrays that restate a computed predicate:** the new `AFFECTED_PLUGINS_SOLEUR_TEST_CODEQL_TO_ISSUES_SWEEP_WIRING_TEST_SH_PATHS` (`test-affected-paths.sh:519-523`) is a genuine declaration — the suite reads `.github/workflows/codeql-to-issues.yml` through a `WF` variable at test line 25 that derivation cannot reach; label mapping, alphabetical slot, `file:line` anchor and `THIS FILE` self-edge all match convention. Not a restated predicate.
- **Class-not-instance:** satisfied for the behavioral contract (all consumers enumerated above) — the miss is confined to restated *text* (P2-1, P3-4, P3-5).

## Dissent notes

No contradiction to any settled ruling. Ruling row 11 blessed verdict-line co-firing; P3-1 flags only the remedy *text* that co-firing imports, and P3-4 notes the runbook row undersells the co-firing the ruling itself recorded. The `adopt` fixture-name retention (P3-3) is accepted-as-ruled — the rulings fixed the verdict token, not fixture vocabulary.

## One-paragraph summary

PR #12127 implements the strict-zero contract cleanly: the `baseline-reintroduced` arm sits in the ruled position, fires unconditionally on a base-absent/HEAD-present baseline (verified live on contentful, empty and covered-set shapes), co-fires `new-pair` detail beneath the marker, and never emits `grown`. The accept sweep is exact (42/42 rows keyed on the deleted path), `.gitattributes` is cleaned with the file, the mutation census (599) and arm ranges are consistent, and every downstream consumer — ci.yml's reason extractor, the observation probe's `MARKER_RE` and absent-at-tip handling, the preactivation script — already tolerates the new token and state. The single P2 is the class-vs-instance miss this seat watches for: the same contract is restated three times in `ci-pr-affected-replay.py` and the sweep updated two (ORDER, BASELINE STATE) while the definitional opening sentence and the argparse `help=` string still promise a committed, shrink-only baseline — in the exact text the runbook cites as the contract. The remaining findings are a contradictory remedy tail on malformed re-adds, an unasserted message string on the new arm, surviving "adoption" vocabulary, and runbook wording that undersells the co-firing this PR's own ruling record blesses — all P3, none blocking.
