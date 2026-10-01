---
module: Sentry alert drift probe
date: 2026-09-23
problem_type: logic_error
component: shell_script
symptoms:
  - "probe printed `PASS (all 29 in-scope rules match ...)` at rc=0 having compared 28"
  - "a guard rendered on zero inputs while reading as protective"
  - "63/63 green suite could not distinguish the shipped code from code with the guard deleted"
root_cause: unaccounted_handoff
severity: high
tags: [guards, vacuity, jq, mutation-testing, silent-failure, sentry]
synced_to: [review]
---

# A hand-off to a later pass is a silent-clean hole unless it is accounted

## Problem

`scripts/sentry-alert-live-fidelity.sh` compares every declared `sentry_alert`
against live Sentry. PR #8576 added a class for a rule that LEAVES the comparison
scope (Sentry adds a trigger type the provider cannot express), and to reach it
the per-rule loop `continue`d — deferring the declared name to a later census
pass rather than reporting `DELETED or RENAMED`.

The census can only classify members of `$O`, and `$O` excludes every
Terraform-FROZEN name **by construction**. So for one reachable shape — a
declared name whose only live bearer is frozen — the loop skipped it and the
census could not see it. Measured:

```text
sentry_alert live fidelity: comparing 29 declared rule(s) against 28 live in-scope rule(s)
sentry_alert live fidelity: PASS (FIXTURE — not live) (all 29 in-scope rules match …)   rc=0
```

A clean verdict over a rule nothing compared, and a **regression**: the
pre-change probe reported `DELETED or RENAMED` for the identical input. None of
the suite's 63 rows could see it; two independent review seats and a direct
re-run found it.

## Solution

Account the hand-off rather than narrowing the predicate. Every deferral is
recorded, and after the later pass runs, each recorded name must have been NAMED
by it:

```bash
handed_off=()
# …in the per-rule loop, where the declared name is absent from the projection
# but present in the raw payload:
handed_off+=("$name"); continue

# …after the census emits its findings:
for _ho in ${handed_off[@]+"${handed_off[@]}"}; do
  grep -qF -- "'${_ho}'" <<<"$frozen_report" && continue
  _finding "UNRECONCILED HAND-OFF: '$(_safe "$_ho")' is declared … and NOTHING compared the declaration."
done
```

This also keeps the verdict's count honest **by construction**: an unreconciled
deferral always emits, so the PASS branch is unreachable while one is
outstanding — no second counter and no reworded PASS literal were needed.

## Key Insight

**When a check defers a case to a later check, name the later check's POPULATION
and ask whether the deferred case is in it.** "It will be handled downstream" is
a claim about set membership, and it is the claim nobody states out loud — the
deferral reads as routing, not as an assertion. If the answer is "usually", the
deferral needs a ledger, because the exceptions are exactly the cases that then
pass silently.

The tell is asymmetry between the two populations: here the loop's predicate was
*"some live workflow bears this name"* and the census's was *"excluded-type AND
not frozen"*. Nothing forced those to agree, and nothing noticed when they did
not.

### Three more, each measured this session

1. **A `.`-read in a `jq -n` program is `null`.** `X as $v | …` does NOT rebind
   `.`, so a guard written `if (.name as $n | $set | index($n)) != null` is dead
   on **every** input while reading as protective (`null | .name` → `null`;
   `index(null)` → `null`). Every sibling arm in the same program bound `$w`.
   Four review seats converged; the suite was green with it dead, and the guard
   was the only warning on a path whose remedy ends in `DELETE`.
   **Litmus:** in a `jq -n` program, a bare `.field` outside a `map`/`select` is
   almost certainly a bug.

2. **A mutation battery whose rows all perturb ONE axis is a one-row battery.**
   Ours had 8 rows, all on the census chain's content. An audit found six
   survivors on axes no row edited: the `elif` ORDER, the census tally, the id
   TYPE, and the suite's own DISPATCH. The dispatch one is the sharpest —
   routing `_report`'s fail branch into `pass` left the suite `63 passed, 0
   failed`, exit 0, with real failures on stderr, because the `EXPECTED_TESTS`
   gate reconciles counters that only that helper moves. A floor computed from
   the helper it backstops is not a floor. The fix is an instrument self-test
   that drives the verdict helper in BOTH directions and aborts if either
   counter fails to move.

3. **Live third-party strings reached a PUBLIC issue body verbatim.** A Sentry
   workflow name carrying a newline terminates the finding line; the remainder
   escapes the markdown code fence (a 3-space-indented fence closes it) and
   reaches the Actions runner as its own `::`-prefixed line. Measured end to
   end. The repo already had a `_safe` scrub for the two ENV values — the
   asymmetry with the API's values is the tell. Vendor data is not more
   trustworthy than environment data on a surface whose whole purpose is
   detecting that vendor's unilateral edits.

## Prevention

- For every `continue` / early-return that defers rather than decides: write down
  the downstream population and check membership. If the deferral cannot be
  proven total, record it and reconcile.
- Before trusting a mutation battery, enumerate the AXES it edits (SUT content /
  fixture shape / fixture direction / member cardinality / harness dispatch).
  N rows on one axis is one row.
- Give every verdict-owning helper a self-test that drives it in both
  directions; a floor that shares its counters is not independent.
- Scrub every third-party string that can reach an operator-facing or public
  sink, not just the ones from the environment.

## Session Errors

1. **Apostrophe inside a single-quoted jq program — three times** (`rule's`,
   `probe's`, `API's`). Each terminated the program string early and produced a
   bash syntax error attributed to a line far from the edit (once ~30 lines
   away, reported as `syntax error near unexpected token`).
   **Recovery:** reworded each to avoid the apostrophe.
   **Prevention:** after any edit inside a single-quoted embedded program, run a
   mechanical apostrophe grep bounded by the program's own delimiters. Three
   recurrences in one session is evidence this is not a care problem: it needs a
   check, and the check is two lines of `awk`.

2. **Edited the suite file while it was running.** Bash reads scripts by byte
   offset, so the running shell executed garbage and reported a syntax error in
   a file `bash -n` calls clean; the run was void and briefly read as a real
   regression.
   **Recovery:** confirmed the file with `bash -n`, discarded the run, re-ran
   after all edits settled.
   **Prevention:** treat a launched suite as owning its file until it exits —
   the same rule the repo already applies to full-gate runs and the worktree.

3. **A jq `gsub` character class written through a Python heredoc acquired
   doubled backslashes**, turning `[\u0000-\u001f…]` into a literal-character
   SET that stripped letters from data (`evil` → `v`). The scrub appeared to
   work; only the output's shape gave it away.
   **Recovery:** probed both spellings side by side against a known input, then
   corrected the escaping.
   **Prevention:** for any escape-bearing regex written through a heredoc,
   measure both spellings against a known input BEFORE shipping. A silently
   over-aggressive scrub is worse than none.

4. **Read `grep -c` on my own probe output as evidence a finding had vanished**,
   when it had merely been reformatted onto one line.
   **Recovery:** re-ran asserting the positive.
   **Prevention:** assert the finding is present and correct before concluding
   anything from a zero — a zero is compatible with "absent" and with "different
   shape".

5. **Ran a guard suite from a wrong path, got rc=127, briefly recorded it as a
   failing gate.**
   **Recovery:** re-ran from the correct path; 23/23 green.
   **Prevention:** distinguish "command not found" from "assertion failed"
   before reporting any rc.

6. **Wrote a commit-message file under a `$$`-derived name**, then referenced it
   from a later shell where `$$` differed: `COMMIT_RC=128`, `could not read log
   file`.
   **Recovery:** rewrote the message to a fixed path.
   **Prevention:** echo the generated path and reuse the echoed literal.

7. **A task notification reported "exit code 0" for a commit lefthook
   REJECTED** — the trailing `git log` owned the status.
   **Recovery:** read the explicit `COMMIT_RC=` line, which said 1.
   **Prevention:** `git commit …; echo "COMMIT_RC=$?"` on the very next line.
   **This is already a hard rule and it recurred anyway.**

8. **First `git push` reported `PUSH_RC=0` through a `| tail`** that masked a
   non-fast-forward rejection.
   **Recovery:** inspected the remote, confirmed it held only this branch's own
   pre-rebase commits, pushed with `--force-with-lease` pinned to the measured
   SHA.
   **Prevention:** never take an exit code through a pipe.
   **This is already a hard rule and it recurred anyway.**

**The finding about 7 and 8 is that they are already documented hard rules and
recurred regardless.** For these two the prose rule is not working, and the
honest disposition is a mechanical check rather than another sentence — which is
the same conclusion this repo reached for every PreToolUse hook it now carries.

9. **Routed a 947-byte bullet into a SKILL.md that had 658 bytes of headroom.**
   `rule-body-lint` red: `work/SKILL.md` 362289 bytes against a pinned ceiling of
   362000. Compound routes learnings into lifecycle skills by design; nothing in
   that step reads the ceiling.
   **Recovery:** trimmed the bullet to 515 bytes, keeping the hazard, the vector
   and the mechanical remedy, dropping the worked example the learning already
   carries.
   **Prevention:** before routing a bullet, run `python3
   scripts/lint-skill-body-budget.py --base "$(git merge-base origin/main HEAD)"`
   and size the bullet against the headroom it reports.
   **It reddened a SECOND time, and that is the real finding.** The trimmed
   515-byte bullet passed with 143 bytes to spare, then went 288 over after a
   routine BEHIND resync pulled main's own growth in — the branch never touched
   the file again. Measured: main took `work/SKILL.md` from 361342 to 361772 in
   about four hours, leaving 228 bytes under a 362000 ceiling. The bullet was
   dropped rather than trimmed a third time.
   **The durable point:** headroom on a shared file is not yours to spend, and a
   trim sized against today's headroom is re-reddened by any unrelated commit
   while your PR sits in the queue. Below a few hundred bytes the only stable
   moves are to extract into `references/` or not to route at all — a bullet
   small enough to fit is too small to carry a learning. `soleur:compound` can no
   longer route into `work/SKILL.md`; recorded on #8305 with the measurements.

10. **Shipped an operator-facing finding naming three causes the probe never
    measured.** `lint-diagnosis-claims` red (ADR-166). Two were hedged on their
    face ("its live bearer is Terraform-frozen, **or it left the census another
    way**"); the detector matched the third, "this means the committed reference
    is STALE" — a conclusion drawn from the pin's SILENCE, which is consistent
    with staleness and with shapes the probe never separates.
    **Recovery:** reworded to report the entry as UNVERIFIED by this run and to
    phrase the remedy as a comparison to perform, not a state to assume. The
    hypothesis moved into the block comment, which is not operator-facing.
    **Prevention:** a finding written for a case the code CANNOT distinguish is
    the one most likely to assert a cause, because the author is compensating for
    the ambiguity in prose. When an arm exists precisely because two shapes are
    indistinguishable, say which two and stop there.

11. **A half-archival exits 0 and prints a success line.** Discharging this
    branch's deferred `archive-kb.sh` run with the obvious slug archived the
    SPEC and silently left the PLAN live. The plan and the spec carry different
    slugs (`sentry-alert-fidelity-p3-cleanups` vs
    `one-shot-sentry-fidelity-p3-cleanups`), and the script is per-slug, so
    either one alone reports `Archived 1 artifact(s)` and returns 0.
    **Recovery:** ran it twice, once per slug.
    **Prevention:** the script already warns (`found a spec for slug "..." but
    NO plan`) and that warning is the whole signal — it is printed ABOVE the
    success line, so a `tail` of the output hides it while showing the green.
    Read archive-kb.sh output from the TOP, and assert both halves moved before
    calling the archival done. Generalises past this script: when a tool is
    keyed on a name the artifacts do not have to share, success on one is not
    evidence about the other.

**9 and 10 are repo-global ratchets, and neither references a changed
file.** That is why the diff-scoped substitute run — the sanctioned fallback when
`test-all.sh` refuses a full gate under sibling contention, which it did here
(rc=4, 6 siblings in flight) — could not reach either. The blind spot is
structural and does not improve with care: the ratchets have to be named and run
by hand. For this branch that list was `lint-skill-body-budget.py`,
`lint-diagnosis-claims.sh`, `guard-vacuity-floor.test.sh` and
`fixture-relative-assert.test.sh`.

## Related

- `knowledge-base/project/learnings/2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
- `knowledge-base/project/learnings/2026-07-16-a-mutation-battery-only-covers-what-you-mutate.md`
- PR #8576; parent #7985 (BLOCKED on the provider release, not closed by that PR)
