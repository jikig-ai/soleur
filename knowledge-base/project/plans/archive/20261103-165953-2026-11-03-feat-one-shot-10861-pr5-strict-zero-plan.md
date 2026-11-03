# Plan: S4 affected-index PR5, strict zero — accept rows, non-code pairs, delete the baseline (Ref #10861)

Series: Ref #10448 (index-completion tracker), Ref #9729 (S4 epic), ADR-276.
Plan source: `plans/archive/20261023-144502-2026-10-22-feat-s4-affected-index-pr3-required-ratchet-plan.md` §PR5.
Merged slices already landed under this issue: #10945 (PR4, 238 pairs), #11109 (PR4b, 11 edges + 25 accepts), #11131 (PR4c, 8 edges + 26 accepts), #11226 (PR5 measurement slice — `glob-rate` tool + `grep-q-pipe-guard.test.sh` → `ALWAYS_ON_SUITES`, 104 baseline lines drained).
Draft PR: #11950 (unlabelled; claim `s4-drain` on it at first drain slice, mirror comment on #10448).

Holds, unchanged everywhere below: no `CI_PR_AFFECTED`, no activation-lock removal, no PR D (#10414), no PR3b (#10859), no evidence re-run (`collect`/`ejections`/`aggregate`/`verdict`), no flip PR. One `s4-drain` PR at a time; each drain PR merged inside the PR3b observation window restarts it — recorded, not optimized around.

## Measured current state (this worktree, HEAD cfb6fc4dc8, 2026-11-03)

Live audit (`python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv`, ~5 min):

```
SOLEUR_PR_AFFECTED_AUDIT suites=724 always_on=116 audited=608 unaudited=0 gap_suites=252 gap_refs=1512 accepted=234 stale=0 refs=4031 files_read=1203
```

Baseline file: 1,510 lines. Accept file: 459 rows. Live set = baseline + **2 drift pairs** on main that no drain owns yet (the ratchet is red `new-pair` on a fresh PR today; the first slice absorbs them):

- `scripts/image-cve-triage → scripts/betterstack-query.sh` (`QUERY="${IMAGE_CVE_QUERY_SCRIPT:-$REPO_ROOT/scripts/betterstack-query.sh}"` — deepen evidence, decision-challenges row 12: the no-override arm `image-cve-triage.test.sh:~429` `[[ -f ]]`-stats the real file but never executes it; `edge-real` if the stat counts as a read, and then it rides an edge slice leaving 5a red `new-pair` on it alone — documented exception)
- `scripts/betterstack-emitter-read → scripts/image-cve-triage.sh` (manifest data row in `lint-betterstack-emitter-read.sh:148` — mention)

### Pair-class breakdown of the 1,512 live pairs

| Class | Pairs | Suites | Disposition |
|---|---|---|---|
| code-ext, PR4-classified `mention` | 546 | — | accept rows (762 boundary lines measured via `audit --all-refs`) |
| code-ext, `deferred-real` held-back edges | 66 | 27 | declare edge + accept rows for revealed mentions, per edge, atomically |
| code-ext, `deferred-real` deferred-sweep | 21 | 3 | whole-tree policy call (§D2): `plugins/soleur` 16, `tests/scripts/argv-bearer-sweep` 5 (`grep-q-pipe-guard`'s 22 already drained by #11226) |
| non-code, unclassified | 877 | 219 | per-pair read-vs-mention classification (2,087 boundary lines; heuristic read-pattern ≈15-40% real reads) |
| new drift (above) | 2 | 2 | classify like the rest |

`tests/scripts/git-data-birth-readiness-gate`'s held-back edge → `.claude/hooks/grep-q-pipe-guard.test.sh` is inside the 66: a real read (`sed -n` extracts the PATTERN literal, `test-git-data-birth-readiness-gate.sh:2970-2972`), whose exact-file declaration reveals **151 pairs** (144 code-ext) in the PR4c trial — all anchored in one 67-commits-in-90-days file.

### Why it must split

- Ruling-5 stop line (drain PRs): round-1 reveal < 60 per chain, ≤130 summed, ≤4 rounds, cumulative ≤150 accepted mentions counted. The remaining held-back edges' recorded all-at-once reveal is ~407 pairs (475 minus the 68 now-moot `grep-q-pipe-guard` reveal) — over the cap on its own.
- ~2,500-3,000 new accept rows (one row per boundary line per mention pair, not per pair) is far past one reviewable diff.
- The machinery change (adoption-arm removal) wants a clean final PR with live=0.

## D1 — Strict-zero strategy: five slices, deletion last (recommended)

**Ruling needed: none** — slicing follows the series precedent and the stop line directly.

| Slice | Contents | Index edit? | Battery |
|---|---|---|---|
| **PR5a** | Non-code classification table (receipt) + accept rows for **all mention pairs** (~700-800 pairs, ~1,500-2,300 rows); split a1/a2 by suite area if review demands. Includes the 546 already-classified code mentions and the 2 drift pairs if mentions. | no | normal gate (accept.tsv is an oracle input — notice only, not a runner trigger) |
| **PR5b** | Non-code **real-read** edges (reveal-free — only `^file` code-ext entries join the naming walk) + held-back edges in ascending-reveal order, each edge + its revealed-mention accept rows in the same commit, cumulative reveal ≤150 | yes | full battery once (runner-changed) |
| **PR5c** | Remaining held-back edges (second ≤150 tranche) + the forbidden-config edges (`>10` accept rows or hot anchor — see D3) | yes | full battery once |
| **PR5d** | The 21 deferred-sweep pairs (`glob-rate` at work time + the §D2 explicit call) + `git-data-birth-readiness-gate` mega-edge + `boundary-prefix` glob scope + leftovers | yes | full battery once |
| **PR5z** | Strict zero: assert live=0, delete the baseline, remove the adoption arm + strict-zero test rows, ADR-276 closing line, runbook, `.gitattributes` row | yes (replay.py) | full battery once |

Rejected: one giant PR (stop-line breach; ~3,000-row review; machinery buried in data), and interleaving accepts with edges per suite (each extra index-edit PR costs a full-battery cycle; grouping all edges into two slices minimizes battery runs while staying under the reveal cap).

## D2 — The 21 deferred-sweep pairs: the explicit call the rulings demand

The standing policy (PR4b row 6, verbatim in the runbook): a `glob:` edge at `measured` ≤60 s and ≤25% of 200 merged PRs; `ALWAYS_ON_SUITES` at ≤30 s (≤10 s installable — `test-all-fast-tier-budget`) when selected more often; **otherwise baselined until a PR5 decision**; never an accept row for a real whole-tree reader. PR5 must re-run `glob-rate` at work time (`suite<TAB>entry` candidates + `--pairs` scope + `--spot-check 3`).

**Expected verdicts at work time** (current `suite-durations.tsv`, regenerated 2026-11-02): `plugins/soleur` → `duration-missing` (a whole `bun test` run, no row), `tests/scripts/argv-bearer-sweep` → `rate-over-and-duration-over-30s` (47,034 ms measured, ~64% existing selection), `plugins/soleur/test/boundary-prefix.test.sh` → `duration-floor` (1,222 ms, src=floor). All three verdict `baselined` — **but the baseline is being deleted in this same issue, so the else-branch cannot be the answer.**

**Recommended ruling (the explicit call, recorded per suite in the PR):** per-pair honest dispositions —

1. Non-code named pairs of the sweep suites (`plugins/soleur` 59, `argv-bearer-sweep` 14 — corrected count, decision-challenges row 11; the deferred-sweep tag itself covers only code pairs): **exact-file edges** where they classify edge-real. True per-pair reads, reveal-free (non-`^file`-code entries never join the naming walk), zero added selection beyond the named files.
2. Code deferred-sweep pairs — **all 21 of them** (`plugins/soleur` 16× `.sh`/`.mjs`/`.ts`/`.py`, `argv-bearer-sweep` 5× `.sh`; there are no non-code deferred-sweep pairs — corrected, row 11): trial-declare on a scratch worktree first. Reveal under the per-edge cap → exact-file edge + accept rows. Reveal over the cap, or accept anchors landing on a >8-commits file → **narrow `glob:` spelling** `glob:<dir>/<stem>*.<ext>` covering essentially that file (a `*` tail is required — `tail-no-star` is malformed). A glob entry is never a naming-walk node, so the reveal collapses to zero while the edge stays a true declaration of the file the suite reads.
3. The completeness residual — the suite's *unnamed* swept files stay uncovered — is the audit's documented lower bound, unchanged from today; record it on #10448, not in the index.

Reasoning: per-file edges are the only disposition no ruling forbids — accept rows are barred for real whole-tree readers, `ALWAYS_ON_SUITES` is duration-gated out, sweep-scope `glob:` needs qualifying measurements these suites cannot produce, and `baselined` dies with the file. Per-file edges strictly improve on today's state (baseline pairs carry zero selection weight) and keep criterion c's saving intact.

**Rejected alternatives:** (a) sweep-scope `glob:`/`@tree` sets despite >25% — the complete-honest answer, but the stop line ("no pair is globbed unless both measurements meet row 6") forbids it without an amendment, and a ~90%-selected `plugins/soleur` is a budget-owner question, not a drain one — take it to the CTO only if the per-file route dead-ends on a pair's walk reveal; (b) `ALWAYS_ON_SUITES` — duration-gated (fast-tier cap 10 s); (c) `*` accept rows — refused for suites with tracked input and for real readers; (d) leaving the pairs undrained — contradicts strict zero.

If the implementer or the CTO agent reads PR4c row 7 ("no pair is globbed unless…") as covering the narrow-glob spellings of item 2, the fallback is exact-file edge + atomic accept rows wherever the >10-rows/hot-anchor rules allow, and any still-blocked pair is a named CTO call in the PR — **with the baseline deletion held out into PR5z so the impasse never blocks the drain.**

## D3 — The `git-data-birth-readiness-gate` mega-edge and other forbidden configs

`tests/scripts/git-data-birth-readiness-gate → .claude/hooks/grep-q-pipe-guard.test.sh`: real read (sed-extracts PATTERN). An exact-file edge reveals ~151 pairs, and their accept rows are **doubly forbidden** — an edge needing >10 accept rows is held back, and every anchor sits in `grep-q-pipe-guard.test.sh` at **67 commits/90 d** (>8 hot). The remaining sanctioned spelling is the **narrow glob** `glob:.claude/hooks/grep-q-pipe-guard*.test.sh`: honest (the suite reads exactly that file), covers the pair, joins no naming walk → zero reveals, marginal over-selection limited to hypothetical same-prefix siblings (the safe direction — over-selecting can never hide an escape). The same spelling covers `plugins/soleur → .claude/hooks/grep-q-pipe-guard.test.sh` and any held-back edge whose accept rows would anchor on a hot file (`guardrails.sh` 13 commits, `betterstack-query.sh` 7 — borderline, re-count at work time).

Rejected: exact-file edge + ~151 atomic accept rows (both limits breached; ~151 rows on a 67-commit file is permanent stale-accept churn), a suite-side refactor to shrink the read (out of drain scope), CTO escalation as first resort (the glob spelling is a sanctioned edge shape; the ruling fork is recorded in D2/DC).

## D4 — Baseline deletion mechanics and the strict-zero check

Verified in `scripts/ci-pr-affected-replay.py` (`ratchet`):

- base present / HEAD absent passes **only when live is empty** (`baseline-deleted` otherwise) → the deletion commit rides the last drain PR with live=0 verified first.
- absent at both = strict zero: every live pair is a `new-pair` — the permanent post-merge state, no job change needed (the `affected-index-ratchet` job's name, `if:`, `continue-on-error` and advisory status are untouched; only its comment block references the baseline and gets a doc edit).
- **ADR-276 amendment item 5(d) is load-bearing**: "in the commit that deletes the baseline, also remove the adoption arm from the state table and add a row proving that a re-added baseline exits 1." Today base-absent/HEAD-present passes when live equals the baseline — a hole: a PR could re-add the file plus pairs that equal it and the growth check would never see it (and an *empty* re-added file passes trivially). Removal = a HEAD baseline while the base lacks one is exit 1 unconditionally (name the reason, e.g. `baseline-reintroduced`; a non-empty re-add already fails `stale-line`, the arm removal makes it unconditional).
- Test suite (`plugins/soleur/test/ci-pr-affected-replay.test.sh`): baseline-only rows retire (`row_rt_adopt*`, `row_rt_grow_*`, `row_rt_helper_pr_tree_ignored`'s adoption arm, the stale-line/dup/order/grown chks at ~2899-2906, mutations ~4883-4892 that target baseline-present logic); strict-zero rows added — empty live passes, one planted gap → `new-pair`, a reintroduced baseline → exit 1, `baseline-deleted` while live → exit 1.
- Follow-on sweep: `.gitattributes:2` (`linguist-generated` line for the deleted file — remove), `scripts/lib/inngest-probe-row.test.sh:143` (fixture table row keyed to the baseline file — verify and remove/adjust), the observation-window probe `ratchet-observation-window-10865.sh` (already tolerates baseline-absent-at-tip — verify only), `ratchet --print-baseline` post-deletion prints every live pair (document as the diagnostic listing it becomes), `scripts/test-affected-kb-consumers.baseline.txt` regenerated if edge additions moved its rows.

## D5 — Accept-row conventions (verified)

- Format: `suite<TAB>path<TAB>anchor12<TAB>ordinal<TAB>false-positive: <kind>: <file:line>: <evidence>`, C-locale sorted file, one row **per boundary line** — a pair exempts only when *every* boundary line has a row (`judge_rules` all-of), and `audit --all-refs` (the `ref` lines) is the complete source of truth, never the ratchet report.
- Closed kind list: `message`, `JSDoc/comment`, `PR-body string`, `help/menu text`, `data row not fed to a read loop`, `code line in a file read only as text` (last one needs recorder evidence: suite file opened, named path not opened, in `--mode check` both recordings).
- Reasons assert about the suite's *entire* read surface — enumerate real-tree arms or cite the always-on twin (learning 2026-10-31); a boundary line that is a whole-line comment can never anchor (comments are stripped — verify anchor content before writing).
- `*` rows only for a suite with no tracked input; re-adding a row's first four columns with a different reason is `stale-accept` (duplicate).
- An edge's revealed mentions get their rows in the **same commit** as the edge (the anchors exist only once the file is walked).
- Held-back limits: an edge needing >10 accept rows, or rows anchored on a file with >8 commits/90 d, is held back → narrow-glob spelling instead (D3).
- Agent-drafted reasons are reviewed in the PR (raised on #10448).

## Phases

See `specs/feat-one-shot-10861-pr5-strict-zero/tasks.md` for the numbered list. Outline:

- **Phase 0 — measure and classify (no PR)**: rebase, record `BASE`; fresh `audit --all-refs` receipts; classify all 1,512 pairs (edge-real / mention / sweep / drift) into `receipts/pairs-decisions.tsv`; `glob-rate` for the four sweep labels; trial-declare candidate edges on a scratch worktree for reveal counts; write the slice map.
- **Phase 1 — PR5a (accept bulk)**: rows for every mention pair; prune baseline (`ratchet --print-baseline`, never by hand); audit `stale=0`.
- **Phase 2 — PR5b/PR5c (edges)**: non-code real-read edges first (reveal-free), then held-back edges ascending-reveal ≤150 cumulative per slice, edge+accepts atomically; narrow-glob for forbidden configs; fixpoint audit after each slice.
- **Phase 3 — PR5d (sweeps + mega-edge)**: `glob-rate` verdicts, §D2 dispositions per suite, `git-data-birth` narrow glob, `boundary-prefix` scope decision.
- **Phase 4 — PR5z (strict zero)**: assert `gap_suites=0 unaudited=0 stale=0` and live empty; delete `scripts/ci-pr-affected-audit.baseline.tsv`; remove the adoption arm + retire/add the test rows; ADR-276 closing line ("audit exits 0, ratchet strict; replay and go/no-go re-ruling pending"); runbook update; `.gitattributes` + `inngest-probe-row.test.sh` sweep; full replay suite.

## Acceptance criteria (grep-able)

- `python3 -I scripts/ci-pr-affected-replay.py audit --accept scripts/ci-pr-affected-audit.accept.tsv` exits 0 and prints `gap_suites=0 unaudited=0 stale=0`.
- `test ! -f scripts/ci-pr-affected-audit.baseline.tsv`
- `python3 -I scripts/ci-pr-affected-replay.py ratchet --base origin/main` exits 0 on the final tree; a planted pair exits 1 `new-pair`; a reintroduced baseline file exits 1 (test row name in the replay suite).
- `grep -n "audit exits 0, ratchet strict" knowledge-base/engineering/architecture/decisions/ADR-276-*.md` — the closing dated stage-status line exists.
- `grep -n "strict zero" knowledge-base/engineering/operations/runbooks/ci-pr-affected-activation.md` — runbook updated; the failure table's baseline rows are retired to the strict-zero rows.
- `grep -c . scripts/ci-pr-affected-audit.accept.tsv` records the final row count in the last slice's body.
- `git log --oneline origin/main..HEAD -- scripts/ci-pr-affected-audit.baseline.tsv` shows the deletion commit, in the same PR as the adoption-arm removal.
- Holds: `grep -n PR_AFFECTED_LOCKED scripts/ci-pr-selection.sh` still matches; `gh api repos/jikig-ai/soleur/variables/CI_PR_AFFECTED` still 404; `grep -c affected-index-ratchet scripts/required-checks.txt` = 0.
- Each drain slice's marker: `SOLEUR_PR_AFFECTED_RATCHET exit=0 reason=pass live=<shrinking> baseline=<shrinking>`; the deletion slice's marker prints `baseline=0`.
- `gh pr list --label s4-drain --state open` shows at most one PR at any time; #10448 carries the mirror comment.

## Risks

- **Stale anchors mid-drain**: accept rows key on line content; sibling PRs editing named files (hot files: `grep-q-pipe-guard.test.sh` 67/90 d, `guardrails.sh` 13, `scripts/rule-metrics-aggregate.sh` 7 — re-measured; was 15 at planning) churn rows. Mitigate: regenerate `--all-refs` on every rebase; land accept slices fast; narrow-glob the forbidden configs instead of writing rows on hot files.
- **Walk-reveal explosion** on exact-file code edges (the 151-pair file is the extreme): every candidate code edge gets a scratch-worktree trial declaration first; over-cap → narrow glob.
- **Ruling-gap residual**: if PR4c row 7 is read as forbidding all glob spellings, the narrow-glob fallbacks close and remaining pairs go to an explicit CTO line in PR5d; the deletion is isolated in PR5z so nothing blocks it.
- **plugins/soleur scale**: 90 pairs / 254 boundary lines on one dir-suite label — classification care (its rows share the label; the audit treats the label once).
- **Review burden**: ~3,000 TSV rows across slices; each row carries file:line evidence in the reason and the per-pair classification receipt is the review table.
- **Window restarts**: each merged drain slice restarts the PR3b observation window — expected, recorded on #10448.
- **Two drift pairs** make the ratchet red on any fresh PR today; PR5a absorbs them first.
- **Scope creep into selection semantics**: swept-scope completeness vs criterion c is a budget-owner fork — the plan keeps the audit's lower-bound framing and routes any `rate>25%` glob installation through the CTO, never unilaterally.

## Out of scope

Activation (`CI_PR_AFFECTED`, lock removal, PR D #10414), PR3b (#10859), the `no-run` investigation (#10862), the evidence re-run and go/no-go re-ruling, `suite-durations.tsv` regeneration (`--timings-dir` re-price is its own PR), any `glob:` edge installed above a 25% measured rate without a CTO confirm, product code outside the CI oracle files.
