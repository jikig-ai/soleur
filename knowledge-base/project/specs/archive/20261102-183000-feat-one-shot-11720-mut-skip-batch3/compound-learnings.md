# Compound learnings — batch-3 MUT_SKIP port (#11720, final batch)

Sharable mechanics discovered during this port (extends the batch-2 list):

1. **Greedy emitter needles are a dead-text surface too.** `grep 'unpinned_url' | grep 'echo'`
   matches `# echo …` decoys — comment-filter selectors (`grep -vE '^[0-9]+:[[:space:]]*#'` after
   `grep -n`) AND a mutation row that comments the live line are the pair; either alone is unproven.
2. **`-target=` allowlist checks must read a sliced plan region, not the whole workflow** — and the
   slice terminator is a live-needle claim: `rc=${PIPESTATUS[0]}` ≠ `rc=$?`. Family-wide: all five
   sibling `MAIN_PLAN` awk extractions overshoot to ~line 3624 (filed #11899 item 1-adjacent).
3. **`$$` inside unquoted `<<PY` heredocs is intent-ambiguous** — `\x24\x24` inside the python
   string literalizes `$$` for every caller shape (single- vs double-quoted prog args).
4. **A `mutate_red` row needs its fragment to byte-match the `no` message** — review seats caught
   fragment-vs-message drift twice; verify `grep -F "<fragment>" <file>` lands inside the `no "…"` line.
5. **shellcheck `-S warning` catches port-introduced defects CI doesn't** — SC2183 (format arg),
   SC2034 (dead vars the port orphaned). Run it on every ported file pre-panel.
6. **Four parallel file-scoped port agents on disjoint .tf surfaces worked cleanly** — each got the
   donor path + plan's Port Contract + landmines; orchestrator verified via suite runs + meta-guard
   FIRES classification rather than re-reading every diff.
