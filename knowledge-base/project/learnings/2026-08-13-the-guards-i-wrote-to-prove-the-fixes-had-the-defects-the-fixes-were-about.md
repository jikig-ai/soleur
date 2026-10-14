---
date: 2026-08-13
category: test-failures
module: git-data / ci-guards
issues: [7485, 7501, 7506]
pr: 7507
tags: [vacuous-guard, mutation-testing, fail-open, agent-convergence, fixture-direction]
---

# The guards I wrote to prove the fixes had the defects the fixes were about

## Problem

One PR closed three defects — an evidence hash that aborted on a correct tree (#7485), a
container fixture whose starvation was attributed to the emitter (#7501), and a CI guard that
died before it could reopen anything (#7506). All three are instances of one class: *a check
that cannot report is indistinguishable from one that passed.*

The fixes were correct and measured. The **guards written to prove them** contained three
vacuities and the shipped code contained three fail-opens. Not one was found by reading.

## What was found, and by what

| Defect | Found by | Read as, before |
|---|---|---|
| "requires ALL THREE URLs" unpinned — every fixture had 3 or 0 | mutation | 13/13 green |
| field 2's `conclusion` check inert — the stub param never changed an outcome | mutation | 13/13 green |
| `-lt 9` floor free to sit anywhere in 3..9 | mutation | 68/68 green |
| trailing `[[ $fails -eq 0 ]]` — appending any line greens all four suites | mutation | rc=0 |
| sweep plant 1-of-1, so `head -1` invisible | mutation | 13/13 green |
| module dir unenumerable (`chmod 111`) → both siblings dropped at rc=0 | agent probe | "the loop aborts rather than drops" |
| liveness sentinel touched BEFORE the emitter was installed | agent enumeration | gate reported live |
| sweep claimed "the repository", walked 5 dirs, missed 93 tracked files | agent enumeration | "clean" |
| starved path totalled 44 vs floor 45 → "harness did not execute fully" | 4 agents independently | matrix would have gone green |

## Key insights

**1. A mutation battery only covers the AXES it edits.** Mine had 17 rows across four axes and
reported all-caught. The five untouched axes — harness verdict channel, fixture *direction* on
one field, set cardinality, floor *boundary*, injection dispatch — held every remaining defect.
Before crediting a battery, enumerate the axes, not the count. N rows on one axis is one row.

**2. A red control voids the battery, and a subtree sandbox is how you get one.** My first run
reported "control: 14 passed, 1 failed" — the sandbox copied `.github scripts tests` but not
`.git`, so a guard deriving its corpus from `git ls-files` reported `scanned=0`. Every row after
that was noise shaped like a result. `git init` in the sandbox fixed it; the rule is to require a
GREEN unmutated control before reading any row, and to attribute per named arm rather than by
`rc != 0`.

**3. Agent convergence is not corroboration when the agents share a model.** Three independent
agents reported that a `.tf` in a SUBDIRECTORY of the render module was a live fail-open,
each with a measurement ("digest byte-identical"). All three were wrong: Terraform does not
recurse into subdirectories, and the module declares no `module {}` block, so such a file is
never loaded and the digest is *correctly* unmoved. They measured a non-property. The CONCUR
gate caught it; three-way agreement had already made it feel established. Two sibling
non-findings went the same way (`sha256sum` follows symlinks — so does Terraform's `file()`;
and a mirror-equivalence bound already pinned by four other arms).

**4. The moment a body must both ASSERT a thing and EXPLAIN it, they collide.** This bit twice
in one session, in the arm that exists to catch it. A workflow step's `$VAR`-declaration check
read the literal `$VAR` out of a comment written to describe that very rule; and an AC's
residue grep matched the comment documenting the deleted mechanism. Strip comments at
EXTRACTION time — once, where the artifact is read — so every later assertion inherits the
immunity instead of having to remember it.

**5. A fix's own verification inherits the framing of the defect it removes.** The `printf`
fix made a reopen path live for the first time — and the text on that path told the operator to
produce a run-URL for `scheduled-oauth-probe.yml`, a workflow deleted in #4227. The guard had
been demanding a nonexistent artifact class for a year, which is *why* any green run satisfied
it. The natural fix (assert `workflowName`) would have deadlocked it fail-closed forever.

**6. Cardinality must be path-invariant before a floor means anything.** A gate emitting 1
assertion when healthy and 3 when starved makes a starved run total one BELOW the floor, so the
suite's last word is "harness did not execute fully" — naming a cause it did not measure, on
exactly the path the change existed to make legible. Route every arm through one helper so each
contributes one assertion on every path.

## Prevention

- Enumerate a battery's **axes** before trusting its score; require a GREEN control and per-arm
  attribution; assert each mutation LANDED against a pristine copy.
- For every `∀ x ∈ S` guard, ask *where does S come from* — derive it (`git ls-files`) rather
  than hand-listing directories, so coverage equals the property's own noun.
- Give every fixture set two members on the axis the guard quantifies over, and at least one
  fixture on each side of any transform.
- End suites with an explicit `exit`, never a trailing test expression.
- Run every lint the way its **gate** runs it (`--baseline`, `TEST_GROUP`), not bare.
- Never `pkill -f <pattern>` where the pattern appears in the pkill command line.

## Session Errors

1. **A7/A8 needles omitted the `../../` prefix the extractor preserves.** Recovery: measured the
   real abort text. Prevention: derive a needle from observed output, never from memory.
2. **Ran `lint-shell-capture-exit` without `--baseline`** and read its exit 1 as a regression.
   Recovery: re-ran the gate's own argument form (0 new findings). Prevention: grep the runner
   for the invocation before quoting a lint's verdict.
3. **AC6's residue grep matched my own explanatory comment.** Recovery: re-grepped
   comment-stripped. Prevention: anchor on the code construct, never a bare token.
4. **`pkill -f 'guard2-battery.sh'` matched its own command line** and killed the invoking shell
   (exit 144), leaving cleanup half-done. Recovery: cleaned up by hand. Prevention: kill by PID,
   or split the literal.
5. **First mutation battery ran against a RED control** (subtree sandbox, no git repo). Recovery:
   `git init` in the sandbox and re-ran. Prevention: require a green control.
6. **My own fix introduced `RUNNER_TEMP`, undeclared in the step's `env:`**, breaking C11.
   Recovery: replaced with `mktemp`. Prevention: the arm caught it — that is the arm working.
7. **A comment's literal `$VAR` was read by C11 as an undeclared variable.** Recovery: strip
   comments before extraction. Prevention: see insight 4.
8. **`tr -d '\0'` collapsed NUL-delimited paths onto one line**, so `wc -l` returned 0 and the
   sweep reported `scanned=0`. Recovery: `tr '\0' '\n' | grep -c .`. Prevention: never count
   NUL-delimited records with `wc -l` after deleting the delimiter.
9. **C15's needle pinned prose I then rewrote**, reddening the suite. Recovery: re-anchored on
   stable content. Prevention: anchor needles on the semantic claim, not the sentence.
10. **A `sed` floor-bump also rewrote a HISTORICAL statement** (a comment recording the old
    44-vs-45 defect). Recovery: restored the figure. Prevention: scope sweeps away from prose
    that records past state — a dated record is append-only.
11. **Nearly filed three non-findings** on three agents' convergent-but-wrong model. Recovery:
    CONCUR gate DISSENTed; verified each myself. Prevention: see insight 3.
12. **The plan's Non-Goals carried wrong figures** ("20 × 30 s retry", "hardcoded rc=2 summary");
    the real bound is `SECONDS + 16 * 60` and the summary interpolates the observed rc.
    Recovery: verified against the file and corrected. Prevention: a Non-Goal's measurement is a
    claim like any other.
13. **Environmental, not a defect:** load 32 and a mirror taking 19s for a small file made each
    container 3–16 min against a ~108 s baseline, costing several monitor timeouts and one
    abandoned battery. Prevention: check `uptime` and mirror latency before reading a container
    suite's timing as signal.
14. **Forwarded from the planning phase** (`session-state.md`): a first-draft #7485 fix that
    introduced a fail-open, an inverted #7506 defect shape, and an inverted `bash -e` premise —
    all caught before the plan was finalised.
