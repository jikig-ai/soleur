# Learning: a receipt generated after the install measures the install

PR 12199 resolved the #10448 boundary-prefix deferred item with the CTO-ruled
arm (a') measured-verdict install: `suite-durations.tsv` floor→measured 718 ms,
`ALWAYS_ON_SUITES` entry, `_MIN_ALWAYS_ON_DECLARED` 111→112, the suite's 13
accept rows + 3 kb-consumers rows drained. Three review findings cost fix
rounds; all three trace to sequencing or convention checks I skipped, not to
the design.

## Problem

1. **The evidence receipt was self-referential.** The plan's glob-rate step is
   meant to evidence the suite's PRE-install selection rate. My
   `--print-selection` rows were generated while the queue held the dump — the
   run executed after the `ALWAYS_ON_SUITES` edit had already landed in the
   tree, so the selector classified the suite `always_on` and
   `glob_existing_hit` returned true on all 151 attributable units
   (`rate_conservative=200/200`, `rate_excluded=151/151`). The receipt then
   permanently reads 100% — a verdict measured against its own consequence.
   The install verdict itself stood on the honest pre-install PR5d readings
   (97/200, 48/151, both >25%), so the ruling was unaffected — but the receipt
   as written evidenced nothing and is non-reproducible forever.
2. **A "mention" pair was actually delete-sensitive.** The
   `real-sdk-ask-probe-workflow.test.sh` → `apps/web-platform/server/approval/ops.ts`
   pair lives in the suite's `EXCLUDED|path|reason` classification table —
   textually a mention. But the suite's `TABLE-STALE` check compares every
   table row against the live `git ls-files` set, so the file's *existence*
   feeds the verdict: deleting ops.ts reds the suite. An accept row would have
   shipped a silent hole — the file's delete diffs would never select the
   suite. All ~20 sibling classification-table rows were already
   edge-declared with a `delete-sensitive` annotation for exactly this reason;
   I followed the pair's line-kind, not its verdict-relevance.
3. **Convention misses each cost a seat flag.** The repair accept row went to
   EOF instead of the C-locale suite-grouped position (the file's only
   disorder); the justifications row used bespoke phrasing instead of the
   `always-on class:` sibling shape; a stale `~48%`/`~164` figure copied from
   the plan's prose landed in three committed sites while the true values were
   "PR5d readings (97/200, 48/151)" and ~170 files.

## Solution

- Generate evidence receipts BEFORE the install they evidence. The
  `--print-selection` dump must come from a tree that does not yet contain
  the edge change — sequence dump → measure → install, or re-derive the
  counterfactual from a clean base index. Annotated the receipt and
  session-state with the post-install basis (oracle's recommendation).
- For disposition, classify by VERDICT-RELEVANCE, not line-kind: before
  calling a pair a mention, check whether any suite check reads the file's
  existence (TABLE-STALE / UNRESOLVED-IMPORT / `git ls-files` membership).
  ops.ts re-dispositioned to a declared `delete-sensitive:` edge, matching all
  ~20 siblings in `AFFECTED_..._REAL_SDK_ASK_PROBE_WORKFLOW_TEST_SH_PATHS`.
- Check a generated/shared file's ordering and phrasing convention before
  appending: `LC_ALL=C sort` on the TSV, `always-on class:` prefix on the
  ledger, and never copy a figure from plan prose into committed comments —
  re-derive it or cite the measurement it came from.

## Key Insight

An instrument reads the state of the tree at the moment it runs, and the
tree it runs against includes your own uncommitted edits. "Measure then
install" is not two independent steps — the measurement's validity is a
precondition of the install, and a queued/backgrounded measurement can
silently execute *after* the install it was meant to precede. The same trap
hit twice in one session: a backgrounded `--print-selection` read my new
edge state, and a byte-offset edit to `test-all.sh` under that same
in-flight run broke it mid-read (rc=2).

## Session Errors

1. **glob-rate receipt measured post-install coverage** — Recovery:
   receipt + session-state annotated with the post-install basis and the
   honest PR5d readings recorded as the decision evidence — **Prevention:**
   generate selection dumps before editing the selector's inputs; when a
   measurement queues, do not edit the inputs it will read.
2. **ops.ts dispositioned as accept row (mention class) when the suite's
   TABLE-STALE check made it delete-sensitive** — Recovery: security seat's
   P2; swapped to a declared `delete-sensitive:` edge, accept row removed,
   ratchet re-verified `live=0` — **Prevention:** for every pair, grep the
   suite for a check that reads the named file's existence before writing
   "never reads the file".
3. **Edited `test-all.sh` while the background `--print-selection` run held
   it open** — bash read the file by byte offset and hit a mid-line syntax
   error (rc=2, zero rows) — Recovery: re-ran the dump after edits landed —
   **Prevention:** the rule exists (work SKILL §1172); check `ps` for
   in-flight runs of a file before editing it mid-session.
4. **Repair accept row appended at EOF** breaking the file's C-locale
   suite-grouped order — Recovery: moved into the suite's block (later
   deleted entirely on the P2 re-disposition) — **Prevention:** check a
   generated/shared file's ordering invariant before appending.
5. **Stale `~48%` and `~164` figures propagated from plan prose into three
   committed sites** — Recovery: replaced with the attributed PR5d readings
   and ~170 in all three — **Prevention:** re-derive or attribute every
   number a diff adds; plan prose is planning evidence, not a citable
   measurement.
6. **`--runs 5` manifest regen fetched artifact-less pull_request runs and
   degraded hundreds of `measured` rows to `floor`** — Recovery: reverted;
   downloaded merge_group `suite-timings-*` artifact sets for a surgical
   single-row promotion with an evidence receipt — **Prevention:** only
   merge_group runs carry `suite-timings-scripts-N` artifacts; a timings-free
   regen is an all-floor degrade, not a refresh.
7. **`(~164 files)` replace pattern silently no-opped** (parens not in the
   comment text) — Recovery: pattern-recognition seat flagged the residual;
   fixed literally — **Prevention:** assert the edit landed (`grep` the new
   string) before reporting it done.
8. **decision-challenges Notes bullet left asserting rulings were
   `pending - assumed` after they were ruled** — Recovery: code-quality
   seat; bullet rewritten — **Prevention:** when a ruling lands, grep the
   file for the word `pending` — the prose framing goes stale before the
   table does.
9. **`/usr/bin/time` absent on this host** — Recovery: `date +%s%N` deltas —
   **Prevention:** none; one-off.

## Tags
category: integration-issues
module: ci-pr-affected, affected-index, test-selection, audit-ratchet
