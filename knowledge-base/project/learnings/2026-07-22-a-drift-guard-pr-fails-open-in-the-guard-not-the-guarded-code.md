# Learning: a drift-guard PR's vacuities live in the guard you built, not the code it guards — and your own green mutation battery already blessed them

## Problem

#6461 asked to reconcile a stale byte-budget rubric with its linter and confirm the
commit gate fires. The deliverable grew a new table-driven CI drift-guard
(`scripts/lint-agents-compound-sync.sh`) that asserts every restatement of the
`B_ALWAYS` budget agrees with the authority `scripts/lint-agents-rule-budget.py`.

Before review I ran a mutation battery on the guard and reported it airtight: 13
site-constant mutations all RED, 7 SITES-row deletions all RED, 6 guard-internal
mutations all RED, suite green. Ten-agent review then found **three independent
fail-open holes, every one inside the guard I built** — not in the cron, the
rubric, or any pre-existing code:

1. **A file-wide `grep -q '2>&1'`** meant to assert the rubric kept its
   stderr-redirect was VACUOUS: the SKILL.md contains `2>&1` three times (the
   invocation, prose *explaining* the redirect, an unrelated aggregator line), so
   deleting it from the invocation left the guard green. I caught this one myself
   on a re-probe — but only because I probed the REAL file, not the minimal
   fixture the suite used.

2. **The authority fail-closed path was unpinned.** The whole SITES loop is gated
   on `[[ -n "$EXPECT_WARN" && ... ]]`; if the authority linter is missing or its
   constants are renamed, the loop is SKIPPED and zero sites are checked. Only two
   `err()` calls kept that fail-closed, and NO test pinned them — neutering either
   left the suite green while the guard printed `OK ... 13 sites` with empty
   `warn=/reject=`, exit 0. A fully fail-open guard, blessed by CI. (security-sentinel)

3. **The anti-drift regex was lowercase-`k`, comma-only**, so `23K`, `23 000`,
   `23_000`, `23.000` re-added to the guarded region all EVADED it. Uppercase K
   and non-comma separators are natural prose forms. (test-design-reviewer)

The degrade table in the rewritten rubric also reported a *healthy* budget on a
*blocked* commit (a per-rule-body breach prints `[OK] B_ALWAYS=826` AND `ERROR`
at exit 1; the table keyed on the `[OK]` line and missed the exit code) —
agent-native's P1.

## Root cause

A mutation battery is evidence about the mutations its author imagined, and its
green is byte-indistinguishable from the green of a fully-covered guard. My battery
mutated the SITES *rows* and the site *constants* — because those were the parts I
was thinking about — and never touched (a) the authority-extraction branch, (b) the
notation-breadth of the region regex, or (c) the fixture SHAPE (every fixture was
minimal, so the `2>&1`-decoy case and the multi-fence case could not arise). Each
hole sat in exactly the axis the battery didn't probe.

The deeper trap is specific to guard-building PRs: the thing under construction IS
a verifier, so a bug in it is a bug in the checker, which fails *open* (certifies
broken as fine) rather than *closed*. A fail-open verifier is worse than none —
it retires the suspicion that would catch the drift next time. The guard's own
header said exactly this about the code it checks; it was not applied to the guard
itself.

## Solution

- **2>&1 check:** anchored on the fenced code block containing the invocation, not
  a bare token anywhere in the file; fixture gained decoys + a self-check.
- **Authority fail-open:** added a `CHECKED` tally incremented per site actually
  read+compared, with a backstop refusing `OK` unless `CHECKED == ${#SITES[@]}` —
  so a fail-open now requires defeating TWO guards. Pinned by T10 (authority
  missing) and T11 (constants renamed), each also asserting no `sync: OK`.
- **Notation evasion:** widened the separator class to `[ ,_.]?` and the suffix to
  `[kK]`; T6d pins that each notation reds.
- **Degrade table:** restructured to key on the EXIT CODE first — non-zero with a
  verdict line means the commit is blocked regardless of tier.

Every fix was verified by re-running the specific previously-surviving mutation and
confirming it now reds.

## Key Insight

**When the PR builds a verifier, adversarially review the verifier itself, and
treat your own green mutation battery as a floor, not a ceiling.** Before trusting
a battery, ask per property: *what AXIS did I not mutate?* The recurring axes a
battery misses are (a) the verifier's own most-important INPUT (here the authority
it extracts from), (b) the BREADTH of a pattern (all the notations a literal can
take, not just the one form the fixture uses), and (c) the fixture SHAPE (a minimal
fixture cannot exhibit the decoy/multi-instance cases the real file does). A
verifier bug fails OPEN — it certifies broken as fine — so it is strictly more
dangerous than a bug in the guarded code, and it is exactly the class a same-author
battery is worst at finding.

Corollary confirmed again this session: multi-agent adversarial review with
per-lens defect-class prompts caught what a green full-suite run, a clean
shellcheck, a clean semgrep, and a self-run mutation battery all missed — and
git-history independently CONFIRMED every historical claim in the PR body, which no
other lens had checked.

## Session Errors

- **File-wide `grep -q '2>&1'` was vacuous** (my prose defeated my own check). Recovery: anchor on the fenced block + decoy fixture. Prevention: `cq-assert-anchor-not-bare-token` — the moment a task requires both "assert X" and "document X", a bare-token check collides with the documentation.
- **Authority fail-closed path unpinned; neutering the err() stayed green.** Recovery: `CHECKED` backstop + T10/T11. Prevention: when a guard's loop is gated on an extracted value, the extraction of that value is the single most important thing to pin — mirror the fail-closed tests you wrote for the leaf inputs onto the ROOT input.
- **Anti-drift regex missed `23K`/`23 000`.** Recovery: widen separators + case; T6d. Prevention: a pattern's claimed breadth is vacuous until asserted — pin every notation the literal can take, not the one the fixture happens to use.
- **Degrade table reported healthy on a blocked commit.** Recovery: key on exit code first. Prevention: for a tool whose exit code IS the source of truth, the verdict-line text is secondary — read the code first.
- **Greedy-ERE extracted `0` from `20000 warn`** (`sed 's@.*(re).*@\1@'`). Recovery: two-step grep-isolate then anchored re-extract. Prevention: POSIX ERE has no lazy quantifier; a leading `.*` before a capture is greedy — never wrap a capture in unbounded `.*` on both sides.
- **Two restatement sites missed** (grok-fidelity-gate, runbook). Recovery: added SITES rows. Prevention: for a replicated-literal PR, enumerate the literal independently with a broad grep before freezing the guard's site list — the narrative enumeration is a hypothesis, the grep is the work-list.
- **Incomplete `sed`->`grep` sweep** left "Cite the `sed` output" dangling. Recovery: fixed both mirrored bullets. Prevention: when swapping a command token, grep the surrounding prose for the OLD token in the same edit cycle.
- **5 review agents failed mid-run** (API errors / 600s stalls). Recovery: re-ran the failed lenses focused on genuinely-uncovered ground, against the fixed tree. Prevention: none needed — transient infra; partial coverage is acceptable per the review skill's rate-limit gate.
- **push rejected after rebase.** Recovery: `--force-with-lease`. Prevention: expected after a rebase that rewrote the draft-branch base; one-off.
- **Shell-escape artifact in an awk comment.** Recovery: `bash -n` caught it immediately. Prevention: `bash -n` after any edit to a shell/awk file; one-off.

## Tags
category: workflow-patterns
module: review, compound, lint-agents-compound-sync
