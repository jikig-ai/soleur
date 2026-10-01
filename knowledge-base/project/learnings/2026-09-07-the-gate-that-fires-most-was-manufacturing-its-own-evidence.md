# The gate that fires most was manufacturing its own evidence

## Problem

#7853 was filed because a self-test wrote fabricated deny rows into the operator's real
incident ledger. The fix contained the self-test. But the ledger kept gaining rows with the
fixture payload `gh pr merge 123` — 140 of them — and none came from a test suite at all.

`post-dispatch-watch-gate.sh` greps `$HOOK_CMD` **raw**. Every pattern it uses is a bare
`gh ...` substring, so any command whose text merely *quotes* a dispatch armed the gate, and
its label extractor lifted the quoted fixture's PR number back out as the incident's identity:

```
grep -oE 'gh workflow run [A-Za-z0-9._-]+|gh run rerun [0-9]+|gh pr merge [0-9]+'
    ->  "gh pr merge 123"
```

The bursts line up with **this session's own greps for that string** — including the commands
used to investigate the contamination. The instrument was producing the readings it was being
read for, and the harder I looked, the more it produced.

## Why it stayed invisible

`post-dispatch-watch-gate` is not in the AGENTS.md corpus, so `rule-metrics-aggregate.sh`
exempted it structurally: it reached no rule's `prevented_errors`, no named summary field, and
no orphan gate. It was *the single largest emitter in the ledger* — 2708 rows — and appeared
nowhere in the committed artifact.

It became visible only because this PR added `summary.non_corpus_counts` for an unrelated
reason: a namespace rule had replaced nine exemption stanzas with a predicate, and the stanzas
had been a **forcing function** — a new id used to exit 5 and make an author add a readout. The
predicate removed the failure without replacing the function. Adding the counts back was meant
to restore visibility; the first run printed `post-dispatch-watch-gate=2708` and the defect
fell out of it.

**An exemption is not a classification, it is a decision to stop looking.** When you replace
enumerated exemptions with a predicate, you delete whatever the enumeration was forcing someone
to do. Ask what the old failure made a human write, and keep that.

## The pattern this belongs to

Every guard I examined on this branch had a blind spot **of exactly the class it guarded**.
Not related to it — the same class:

| guard | its subject | its own defect |
|---|---|---|
| hostile-env injection test | the inherited value must not survive | injected `GIT_CONFIG_KEY0`; git spells it `GIT_CONFIG_KEY_0`, so 2 of 3 assertions compared against a value never set |
| helper return-check | find calls that ignore a refusal | stripped every double-quoted span, which deletes the call: `eval "$(git_fixture_env "$d")"` → `eval $d` |
| waiver rot-check | the waiver scrubs the git-location family | passed on any ONE of three patterns, so 3-of-9 cleared a claim of nine |
| out-of-scope block | "they source test-helpers.sh, so the tripwire is armed" | false for 7 of the 20 it was reassuring the reader about |
| `tests/conftest.py` | "enforced by git-env-list-parity.test.sh" | that file contained no reference to conftest |
| derivation A | never pool read verbs (its own comment says so, for files) | pooled them per LINE: `git status && git commit` read as read-only |

This is the sibling of
[[2026-09-04-every-fix-reintroduced-the-class-it-was-fixing]] and
[[2026-09-02-every-guard-i-wrote-was-satisfiable-by-a-guard-that-asserts-nothing]].
Those are about the remediation carrying the defect. This is one step worse: the **detector**
carries it, so the defect is invisible *by construction* — the thing that would report it is
the thing that has it.

I reproduced it myself while confirming a report of it. Checking which suites source
`test-helpers.sh`, I used `grep -c test-helpers.sh` — a bare-token count — and got 6 where the
truth is 7: `fixture-dir-operand-assert.test.sh` names the file twice in prose and sources it
zero times. That is `cq-assert-anchor-not-bare-token`, committed live while verifying a finding
about anchors. The rule is not hard to remember; it is hard to remember *while doing something
else*.

## Addendum — 2026-09-08: the instrument reported the wrong process, and CI caught what I could not

Two more instances of the same shape, both found after the write-up above, both worse than what it
describes — because here the thing that was wrong was the *measurement itself*.

**My sweep harness never measured the suites.** For hours I reported suite results as:

```bash
timeout 1800 bash "$s" >/dev/null 2>&1
printf '  %-52s rc=%s\n' "$(basename "$s")" "$?"
```

Bash expands arguments left to right, so `$(basename …)` runs *before* `$?` is read: every number
I printed was basename's exit status, which is always 0. Demonstrated with a function returning 7 —
`rc=0` under that form, `rc=7` when the status is captured first. Every "rc=0 each" I reported from
that pattern was void, and I repeated it across several sweeps and stated it as verification in a
PR body.

The tell was there and I walked past it: `gdpr-gate-self-test.test.sh` printed **"ALL TESTS PASSED"
and exited 2**. A suite whose own summary disagrees with its exit code is a broken instrument, not
a passing suite.

**What it was hiding.** `trap -p` prints a re-executable command whose body carries bash's own
quoting, so an embedded single quote returns as `'\''`. The sandbox block strips the outer quotes
with `sed` and re-wraps the remainder in double quotes — which leaves those escapes unbalanced and
makes the composed trap a syntax error:

```
test-helpers.sh: exit trap: line 1: unexpected EOF while looking for matching `''
```

Three files carried it; one predates this branch. The fix is to stop re-parsing the quoting at all:
`trap -p`'s output round-trips exactly through `eval`, and the trap string then holds fixed text
with nothing interpolated.

**The general lesson is about where verification comes from.** I had run those suites perhaps
twenty times locally and never once seen the failure, because my harness could not report one. CI
saw it on the first try. When a local check and a clean-room check disagree, the local one is the
suspect — and a local harness you wrote yourself in the same session is the *prime* suspect.

Corollary for reporting: I published "10 affected shell suites: rc=0 each" into a PR body on the
strength of that harness. A measurement's provenance is part of the claim. If the number came from
a one-liner improvised minutes earlier, it has not been verified — it has been asserted with extra
steps.

**And the honest bound on the fix.** Driving the repaired composition against the old broken one
reddens only ONE of the three new assertions: in that probe the malformed trap still removed the
sandbox and still exited 0. So the "971 leaked directories" I attributed to this bug are
*consistent* with it and not demonstrated by it. That link is recorded as unproven in #7889 rather
than claimed — which is the same discipline the body of this learning asks for, applied to the
learning's own follow-up.

## Prevention

- **A detector must be driven, never inspected.** Every fix here ships a mutation that makes
  the guard RED and a positive control that stays GREEN under the same mutation. The pair is
  what distinguishes "the guard works" from "the guard always passes" — `_a_control` catches
  per-line pooling at `mixed-flagged=0` while its other two arms are unmoved.
- **Ask what a normalisation deletes.** `_strip_shell_data` deletes quoted spans so a verb
  survives — correct for classifying verbs, catastrophic for finding calls. Same function, two
  callers, one of them silently wrong. A stripper is part of a check's *semantics*, not
  plumbing; name the caller it was written for.
- **`sed` cannot pair quotes.** My first repair, `s/"[^"$]*"//g`, matched the ` || setup_die `
  BETWEEN two quoted arguments and turned a correctly-checked call into a reported violation.
  If a statement-boundary anchor already rejects prose, do not strip at all.
- **Clean fabricated telemetry on `rule_id` AND exact snippet equality, never substring.** The
  archives held real denials whose payloads *quote* the fixture string — including one whose
  `gh issue` body documents this very contamination. A substring sweep destroys the evidence.
- **An artifact generated before a cleanup ships the contamination.** `rule-metrics.json` was
  generated 28 minutes before the first quarantine and reported 99 and 80 where the truth was
  79 and 72. Regenerate as the *last* step, and verify the metric delta equals the row count —
  that equality is what proves the discriminator took nothing else.
