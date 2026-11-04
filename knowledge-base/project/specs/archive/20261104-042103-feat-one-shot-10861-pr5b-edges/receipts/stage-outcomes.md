# PR5b stage outcomes (Ref #10861) — measured on worktree feat-one-shot-10861-pr5b-edges

Baseline is shrink-only; each commit pruned via `ratchet --print-baseline` to a temp file (in-place redirect truncates).

## Stage 1 (commit e36a429bab): 170 non-code reveal-free exact-file edges
- 123 members appended to 56 existing arrays; 33 new arrays created; members carry `file:line` evidence comments + `# THIS FILE`.
- Synthetic-rows audit: `gap_suites=34 gap_refs=190` (from 360), zero new pairs. Baseline 239 -> 87.

## Stage 2 (commit 6ac9b8460b): 59 exact-file code edges + revealed-pair fixpoint
- 58 appends + 1 array. Fixpoint over 3 rounds (77 -> 59 -> 0 new reveals):
  - 29 edge-real reveals declared (all verified real reads: source/cp/bash exec/var-assign + `[[ -f ]]` consumption), +2 round-3 (incidents.sh 5c/90d, session-state.sh 3c/90d — under the >8-commits/90d refusal).
  - 48 + 56 mention pairs accepted (64 + 61 anchor-keyed rows; reasons name the line kind + cite file:line, matching the existing `false-positive: <kind>: <file:line>` vocabulary).
  - 4 pre-existing accept rows went stale `not-a-gap` (edge-covered) and were dropped; 1 key-dupe dropped.
- Audit after fixpoint: `gap_suites=26 gap_refs=131 accepted=1497 stale=0`. Baseline 87 -> 48.
- Dangerous-direction check: 3 suspect mention refs flipped to edge-real (cp-into-sandbox + bash exec).

## Stage 3 (pending commit): 33 narrow-glob edges
- `glob:<dir>/<stem>*.<ext>` spellings with `real read; <justification>` comments (reveal >10 rows and/or anchor churn >8 commits/90d per reveal-trials-v2-pr5b.tsv).
- Residuals left for PR5c/PR5d: plugins/soleur deferred-sweep, argv-bearer-sweep, drift pairs (inngest-luks-sole-copy, jobs1-stopgap, test-suite-lanes, test-all-killed-classification, git-data-birth-readiness-gate).

## Real-selector verification (post-stage-3)
- `bash scripts/test-all.sh --print-selection --paths=README.md` → 726 rows (receipts/selector-rows-post-stages.txt).
- `audit --list <real>`: `gap_suites=6 gap_refs=26 accepted=1274 stale=0 refs=4203 files_read=1222`.
- Remaining 26 refs are PR5c/d scope: argv-bearer-sweep 18 (deferred), inngest-luks-sole-copy 4 (drift), git-data-birth-readiness-gate 1, key-rotate-workflow drift 3 (jobs1-stopgap, test-all-killed, test-suite-lanes).
- 315 accept rows removed as `not-a-gap` (edge/glob coverage subsumes them — includes pre-existing rows whose pairs the stage edges now cover).
