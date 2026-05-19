---
category: best-practices
tags: [planning, regex, ac-design, cross-artifact-drift, test-portability, mawk, gawk]
date: 2026-05-17
issue: 3924
pr: 3939
---

# AC Vocabulary-Regex Blind Spots + Multi-Runner Awk Portability

## Problem

PR #3939 enforced cross-artifact vocabulary alignment via AC13b:

```bash
git grep -nlE 'Object Lock Governance|--bypass-governance-retention|Bypass Governance Retention' \
  knowledge-base/engineering/ops/runbooks/ docs/ apps/ plugins/ \
  | grep -v knowledge-base/project/{learnings,plans,specs}/
```

After applying the rewrites in Phase 3, the gate returned **0 hits** — green.
But the multi-agent review then caught a real leak the gate missed:

- `docs/legal/data-protection-disclosure.md:104` (and its plugin mirror) said
  **"Object Lock is enabled in *Governance mode* with a ten (10) year
  retention floor"**. Semantically identical to the deprecated vocabulary the
  AC was meant to catch. The regex `Object Lock Governance` requires those
  three words to be adjacent — "is enabled in" between them silently
  bypassed the gate.

Separately, the RED test suite committed at `025033ec` (Phase 1) shipped with
`awk match($0, /data_len=([0-9]+)/, m)` — the **3-argument `match()`** form is
**gawk-only**. The host system ships mawk (1.3.4). On mawk, the test file
aborted at parse error (`syntax error at or near ,`) immediately after
TS-OVERRIDE.a's PASS — every subsequent case never ran. The RED commit
"appeared to fail correctly" only because shellcheck and bash `-n` parsed
the file, and the first test passed.

## Root Cause

Two distinct flavors of the same defect class: **a syntactic gate's literal
form does not span the semantic equivalence class it was meant to enforce**.

1. **AC vocabulary regex (PR #3939):** The plan author chose three literal
   strings (`Object Lock Governance`, `--bypass-governance-retention`,
   `Bypass Governance Retention`) to enumerate the deprecated S3 Object Lock
   vocabulary. The prose under review was rewritten by multiple PR authors
   (#3209, #3918, #3920) using slightly different phrasings of the same
   concept. Adjacency-anchored regex caught the canonical form but not the
   `<noun-1> <prep> <noun-2>` variant. The blind spot is fundamental to
   literal regex over prose: human writers vary word order and inject
   prepositions; mechanical regex doesn't.

2. **awk portability (PR #3924 RED):** gawk's 3-arg `match()` is convenient
   (`match($0, /re/, captures-array)`) and reads like JS-style regex
   captures. mawk implements only POSIX 2-arg `match()` (sets `RSTART` and
   `RLENGTH` instead). The author had gawk installed locally; CI and the
   review host had mawk. A 1-character change to the test (`-F`-split
   form: `awk -F'data_len=' '{...}'`) is portable across both runners.

## Solution

**For prose-alignment ACs:** pair the literal regex with a **fuzzy
proximity** variant that catches token-rearrangements. Example for the
PR #3939 vocabulary:

```bash
# Strict: exact adjacency (what AC13b had)
git grep -E 'Object Lock Governance|--bypass-governance-retention|Bypass Governance Retention' <paths>

# Loose: tokens within ~5 words of each other on the same line
git grep -E '(Object Lock.{0,40}Governance|Governance.{0,40}Object Lock|Bypass.{0,40}Governance|Governance.{0,40}Bypass)' <paths>
```

Run both gates. The strict gate is the contract for the rewrite; the loose
gate is the canary for phrasings the rewrite missed. False-positives in the
loose gate require human-eyeballed disposition (a feature, not a bug) —
they surface exactly the cases where prose drifted without tripping the
strict literal.

**For multi-runner bash tests:** restrict awk usage to POSIX features. The
common offenders are:

| gawk-only | POSIX equivalent |
|---|---|
| `match($0, /re/, m)` then `m[1]` | `match($0, /re/)` then `substr($0, RSTART, RLENGTH)` |
| `gensub(/re/, repl, "g", $0)` | `gsub(/re/, repl)` (mutates `$0`) |
| `length(arr)` for assoc array | track count manually: `for (k in arr) n++` |
| `arr["key"]` then iterate ordered | maintain insertion-order via parallel array |
| `printf` with `%i` for integer | `%d` (POSIX) |
| `\b`, `\B`, `\d`, `\D`, `\s`, `\S`, `\w`, `\W` | `[[:digit:]]`, `[[:space:]]`, etc. |

Cheapest detection at suite start:

```bash
awk_impl=$(awk --version 2>&1 | head -1)
if [[ "$awk_impl" != *"GNU Awk"* ]] && grep -qE 'match\([^,]+,[^,]+,[^)]+\)|gensub|length\(.*\[' "$BASH_SOURCE"; then
  echo "WARN: gawk-only syntax detected but awk is '$awk_impl' — tests may fail mysteriously" >&2
fi
```

## Why It's Easy to Miss

- **The strict gate appears to work.** AC13b returned 0 hits after Phase 3;
  every literal phrasing the rewrite knew about was scrubbed. The phrasing
  the rewrite didn't know about silently survived. The strict gate cannot
  surface gaps in its own enumeration — only review of the underlying prose
  can.

- **gawk and mawk both pass shellcheck and `bash -n`.** Parser-level
  validation cannot distinguish "3-arg match()" from "2-arg match() with a
  trailing comma syntax error" until awk itself runs. The RED commit looked
  green to every gate that ran before runtime.

- **Multi-agent review surfaces both.** In PR #3939, `data-integrity-
  guardian` independently read the DPD file and noticed the "is enabled in"
  phrasing despite AC13b green. No single static gate would have caught it.
  Multi-agent review's value-add is exactly this kind of literal-vs-semantic
  divergence detection.

## Generalizable Heuristic

When designing an AC that asserts **"vocabulary X must not appear in
artifacts Y"**, expect to ship TWO gates:

1. **Strict literal** — the binding contract. Green = the rewrite scrubbed
   every phrasing the author enumerated.
2. **Loose proximity** — the canary. Hits = phrasings the author did NOT
   enumerate, requiring human disposition (false-positive → ignore; real
   drift → fix).

Treat the loose gate's output as advisory review noise, not a merge blocker.
A loose gate that returns zero hits is the only honest "vocabulary aligned"
signal — strict-only is wishful thinking.

## Session Errors

This learning was triggered by the following session errors during PR #3939:

- **mawk vs gawk awk portability.** RED suite's `awk match($0, /re/, m)`
  3-arg syntax is gawk-only; mawk errored at parse. Whole TS suite aborted
  after TS-OVERRIDE.a's PASS. Recovery: rewrote to POSIX `-F`-split form.
  **Prevention:** add a suite-startup probe (`awk --version` check + grep
  for gawk-only constructs in the test file) per the snippet above.

- **`${VAR:-default}` colon-form silently substituted empty-explicit
  values.** TS-OVERRIDE.g (missing-env test) failed because `run_sut` used
  `${GDPR_REQUEST_REF:-DSAR-2026-STUB-001}` — the empty value the test
  passed got replaced by the default. Recovery: switched to `${VAR-default}`
  (no colon) so empty-explicit reaches the SUT. **Prevention:** for
  test-helper env-default substitution, default to bare `-` not `:-`; treat
  `:-` as a code smell in any helper that exercises missing-env paths of
  the SUT.

- **Legal-doc `Last Updated` hero/body parity.** Body bumped to "May 17,
  2026" in `docs/legal/gdpr-policy.md`; the Eleventy plugin-mirror's `<p>`
  hero line at `plugins/soleur/docs/pages/legal/gdpr-policy.md:11` stayed
  at "May 16, 2026". Caught by `apps/web-platform/test/legal-doc-
  consistency.test.ts` Test 7. Recovery: synced hero. **Prevention:** the
  test already enforces this; the lesson is to run `bash scripts/test-
  all.sh` before declaring a docs-touching phase done, not after pushing.

- **cla-evidence script tests never CI-wired.** Plan §Test Strategy
  assumed `apps/cla-evidence/scripts/*.test.sh` were CI-covered (per
  sibling precedent); they weren't. Recovery: one-line addition to
  `scripts/test-all.sh` discovery glob (6 sibling suites now run).
  **Prevention:** when a plan invokes a precedent ("wire X to the same
  CI as siblings"), grep the cited CI workflows for the sibling literal
  before claiming the precedent — `grep -rn 'upload-bypass.test\|inspect.
  test.sh' .github/workflows/` should return non-zero hits.

- **Tombstone key suffix schism (`<sha>.json` vs `<sha>.deleted.json`).**
  Driver wrote `tombstones/<sha>.json`; runbook §7.5/§7.6 verification grep,
  DPD §2.3(n), and privacy-policy §4.5 all committed to
  `<sha>.deleted.json`. Caught by `git-history-analyzer` +
  `data-integrity-guardian` in /review. Recovery: synced driver + runbook
  §7.3/§7.4 example to `.deleted.json`. **Prevention:** when adding a new
  write-path whose consumed-by-step is documented in a separate file,
  grep the consumer's literal key shape before coding the writer.

- **Brittle `NR==3`/`NR==4` awk in tests.** TS-OVERRIDE.b/.k pinned
  assertions to driver-internal curl call ordering; any preflight insertion
  silently miscounts. Caught by code-quality + test-design in /review.
  Recovery: added `data_tag=put-modify|put-restore` field to stub log,
  switched to content-based grep. **Prevention:** when asserting against
  multi-call stub logs, prefer content-based selection (`/data_tag=foo/`)
  over positional indices.
