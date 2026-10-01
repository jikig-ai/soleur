---
module: test-runner
date: 2026-09-08
problem_type: process_issue
component: shell_script
symptoms:
  - "a mutation battery reported per-row verdicts against a RED unmutated control"
  - "a search-based assertion matched zero lines and printed a PASS verdict"
  - "a shard's log was truncated and its rc file emptied by /tmp reaping"
root_cause: unverified_instrument
severity: high
tags: [mutation-testing, measurement, instrument-verification, tmp-durability, ci-gates]
related_issues: [7795, 7908]
synced_to: [work, review]
---

# Six of my instruments were broken, and three of them printed a verdict anyway

## Problem

One session on #7795 (PR #7908). The engineering work — splitting the repo-write-boundary
`refs/tags/*` harm partition on create-vs-move — was reviewed by eight agents, which found 26
findings including three P1s. That is the visible story and it is not the durable one.

The durable one: **six separate measuring instruments I built to check my own work were broken,
and three of them reported a confident verdict from a result that measured nothing.** Every
finding below was caught only because something else contradicted it, never because the
instrument announced its own failure.

## What broke, in the order it bit

| # | Instrument | Failure | How it presented |
| --- | --- | --- | --- |
| 1 | `shellcheck … \| head -40` | reports **`head`**'s exit code | `SHELLCHECK_RC=0` on an unread result |
| 2 | mutation battery in a sandbox | sandbox copied only `scripts/`, so the suite lost repo context | **control RED — every row void**, yet each row printed KILLED/SURVIVED |
| 3 | `sed -i 's\|…\|…\|'` | `\|` delimiter against patterns containing `\|\|` | 4 rows silently void |
| 4 | `cp -r scripts "$sb/"` (2nd call) | copies **into** the existing dir, not over it | row 2 re-ran row 1's mutation and reported a FALSE RED |
| 5 | T9 anchoring check | BRE `\$` is a literal `$`; then unescaped `\(tag\)` | matched **0 lines**, printed "all end-anchored" — twice |
| 6 | `comm -23` on unsorted input | GNU `comm` warns and continues | a blast-radius count I quoted before re-deriving |

Numbers 2, 4 and 5 are the dangerous class: they did not error, they *answered*.

## Root cause

An instrument is code, and I applied to it none of the discipline I was simultaneously applying
to the code under test. In the same session I was writing an instrument self-test *for a test
suite* — because review had proved that suite could not fail — while running six unverified
instruments to check that very work.

The asymmetry has a cause: an instrument's output arrives already shaped like an answer. A row
that prints `KILLED` looks identical whether it killed a mutant or measured a broken sandbox.
Nothing about the shape of the output distinguishes the two.

## Solution

Verify the instrument before reading its output. Each check is seconds and mechanical:

```bash
# 1. CONTROL FIRST. An unmutated run must be GREEN *in the harness that will run the rows*.
#    A red control voids every row; the rows will still print verdicts.
bash "$SUITE" >/dev/null 2>&1 && echo "control GREEN" || echo "control RED — BATTERY VOID"

# 2. ASSERT THE MUTATION LANDED, against a pristine copy — never against HEAD (the tree is
#    legitimately dirty mid-review). A mutation that does not land reports the BASELINE.
pre=$(md5sum "$f" | cut -d' ' -f1); apply_mutation; post=$(md5sum "$f" | cut -d' ' -f1)
[[ "$pre" == "$post" ]] && { echo "MUTATION DID NOT LAND (void row)"; return; }

# 3. A SEARCH THAT MATCHES NOTHING MUST ABORT, not conclude.
hits = [...]
assert hits, "INSTRUMENT FOUND NOTHING — do not read a verdict off this"

# 4. Capture rc directly; never through a pipe.
cmd > "$log" 2>&1; rc=$?      # not: cmd | head   (reports head's status)

# 5. Fresh sandbox per row. `cp -r dir "$sb/"` copies INTO an existing dir.
sb=$(mktemp -d); cp -r scripts "$sb/scripts"   # explicit destination
```

## The second class: `/tmp` is not durable, and I fixed the instance not the class

`/tmp` is actively reaped on this machine. It bit twice:

1. A mutation battery's **restore source** in the session scratchpad was swept between turns. The
   restore silently failed and left a tracked file mutated; `git status` caught it, not the script.
2. A 374-suite shard's log was truncated at exactly **114688 bytes** (28 x 4096) mid-word and its
   `rc` file emptied — so the monitor reported `SHARD_DONE rc=` as though the empty string were a
   result.

After the first hit I moved the *backup* to `/var/tmp` and left the *shard artifacts* in `/tmp`.
That is the fix-the-instance-not-the-class trap, and it cost a full 374-suite re-run.

**Rule:** long-lived run artifacts — logs, rc files, restore sources, pristine copies — go on
`/var/tmp` or in the worktree. Never `/tmp`. And a monitor must distinguish an *empty* rc from a
*present* one:

```bash
if [ -s "$D/rc" ]; then   # -s, not -f: an empty rc is truncation, not a verdict
```

## The third class: a green check answers a question about the SET you handed it

`gh pr checks 7908` returned **9 checks, all pass**. I was about to report CI green. The set was
CodeQL and CLA only — `test-scripts` was not in it, because `ci.yml` is `on: push: branches:
[main]` plus `pull_request`, so feature-branch pushes never trigger it and it had last run on the
plan commit, before any of the six code commits.

**Before reading a green as coverage, name the check you expected and confirm it is in the set.**

## Also: wall-clock elapsed is not liveness

A sibling `test-all.sh` showed `elapsed_s=42636` (11.8 h) with **0 s CPU**. I diagnosed it as
orphaned and reached for `SOLEUR_ALLOW_FULL_GATE=1`. Both wrong: the laptop had **hibernated**,
and the runner's own stale-sibling exclusion had already admitted my run — the lock then cleared
in 127 ms on its own. The signal that would have told me was printed and unread:

```text
[contention] BANNER LOCK_WAIT_HEARTBEAT: queued, not hung — test-all waited=60s of 900s
```

`queued, not hung` with an elapsed counter is exactly the wait-vs-wedge discriminator. Read the
preamble before overriding it. Note also that any heuristic keyed on wall-clock elapsed —
including that stale-sibling exclusion — treats a hibernation as age.

## Prevention

- Run the **control first** and require GREEN, in the harness that will run the rows.
- Assert every mutation **landed** against a pristine copy; treat baseline-identical as UN-RUN.
- Give every search-based assertion a **non-empty guard** that aborts rather than concludes.
- Never take an exit code through a pipe.
- Put durable artifacts on `/var/tmp`; test `-s` not `-f` on an rc file.
- Name the check you expect before reading a green check-set as coverage.

## Session Errors

- **A mutation battery ran against a RED control** — Recovery: re-ran in-place with a pristine
  backup after committing. **Prevention:** control-first, and require GREEN before reading rows.
- **`sed` `|` delimiter against `||` patterns voided 4 rows** — Recovery: re-ran via Python with
  an exact-occurrence assertion. **Prevention:** assert the mutation landed.
- **A second `cp -r` copied into the sandbox dir** — Recovery: fresh sandbox per row.
  **Prevention:** always name the destination explicitly.
- **T9 instrument matched 0 lines and printed a verdict, twice** — Recovery: added `assert hits`.
  **Prevention:** a zero-match search must abort.
- **`shellcheck | head` reported head's rc** — Recovery: redirect and read `$?`.
- **`comm` on unsorted input** — Recovery: `LC_ALL=C sort` both sides first.
- **`/tmp` swept a restore source, leaving a tracked file mutated** — Recovery: `git checkout --`
  from the commit. **Prevention:** durable artifacts on `/var/tmp`.
- **`/tmp` truncated a shard log and emptied its rc** — Recovery: full re-run with `/var/tmp`
  artifacts. **Prevention:** the same fix, applied to the CLASS the first time.
- **Nearly reported CI green from a 9-check set that excluded `test-scripts`** — Recovery: read
  the check names. **Prevention:** name the expected check first.
- **Diagnosed a hibernated sibling as orphaned; used an unnecessary override** — Recovery: none
  needed; the lock cleared on its own. **Prevention:** read the `queued, not hung` heartbeat.
- **`mv` of a `>`-created file dropped the exec bit (100755 -> 100644)** — Recovery:
  `git update-index --chmod=+x`. **Prevention:** check `git ls-files -s` after a rewrite-by-move.
- **An inserted test arm severed a pre-existing comment mid-sentence** — Recovery: relocated it
  above the block. **Prevention:** read what an insertion anchor sits *inside*, not just near.
- Forwarded from `session-state.md`: a `head -5`-truncated grep produced a false absence claim; a
  plan claim that a forced refspec "lands on the FATAL side" was false; a research subagent
  mis-attributed quotes to ADR-133; two MCP servers failed to connect (neither needed).

## See also

- [`2026-08-03-my-battery-measured-one-axis-and-every-fixture-i-checked-my-work-with-was-broken.md`](./2026-08-03-my-battery-measured-one-axis-and-every-fixture-i-checked-my-work-with-was-broken.md)
  — the axis-coverage half of this class. It does not cover a RED control, which is what voided
  the battery here.
- [`2026-08-10-my-sweep-missed-two-red-suites-and-my-battery-certified-garbage-mutations.md`](./2026-08-10-my-sweep-missed-two-red-suites-and-my-battery-certified-garbage-mutations.md)
  — the same landing-assertion gap, reached from the sweep side.
- [`2026-03-28-tmpfs-guard-cron-defense-in-depth.md`](./2026-03-28-tmpfs-guard-cron-defense-in-depth.md)
  — why `/tmp` is reaped on this machine.
- [`ADR-207`](../../engineering/architecture/decisions/ADR-207-repo-write-boundary-harm-partition.md)
  — the partition this session's engineering work widened.
