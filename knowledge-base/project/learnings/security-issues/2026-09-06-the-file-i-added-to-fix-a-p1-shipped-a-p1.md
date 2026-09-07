---
module: observability
date: 2026-09-06
problem_type: security_issue
component: shell_script
symptoms:
  - "an include guard keyed on an inheritable env var let one exported variable send a live ingest write token to an attacker host"
  - "a readback that could never succeed was laundered into a public vendor data-loss accusation"
  - "a destination glob accepted https://evil.com/?x=.betterstackdata.com/"
root_cause: guard_narrower_than_the_property_it_names
severity: critical
tags: [credential-forwarding, guard-vacuity, ap-021, mutation-testing, verification-defects]
issue: 7855
pr: 7856
synced_to: [review, work, compound]
---

# The file I added to fix a P1 shipped a P1

## Problem

Issue #7855: the rung-2 rehearsal could not reach a verdict because every read against the git-data
Better Stack source returned `CLUSTER_DOESNT_EXIST`, and the capture reported that twenty times as
*"the Better Stack query transport exited 22 (unreachable or unauthorised)"* — naming two causes the
run had not measured. The fix was small and the diagnosis was right.

**Every defect review found was in the VERIFICATION, not in the fix.** Two of them were P1s in code
this PR added, and a third was in the guard added to close the second.

## The three instances

### 1. The shared-constants file, added to fix a P1, shipped a P1

An architecture finding was correct: the write-refusal invariant (*never write to whatever source the
rung-2 capture reads as its control*) was enforced across three independent spellings of one source,
joined only by prose. Nothing asserted they named the same thing, so changing the capture's control
table would silently stop the probe's refusal from following — at the gate authorising a production
host's birth.

The fix — `scripts/lib/betterstack-sources.sh`, declaring the identity once so both sides derive from
it — was right. It opened with a conventional include guard:

```bash
[[ -n "${_BS_SOURCES_LIB_LOADED:-}" ]] && return 0
_BS_SOURCES_LIB_LOADED=1
```

`_BS_SOURCES_LIB_LOADED` is an ordinary, non-namespaced, **inheritable environment variable**. Set it
and `source` returns before assigning a single constant, leaving whatever the caller exported under
those names in place. The destination allowlist then compares two attacker-supplied strings:

```bash
RT_INGEST_URL="${GIT_DATA_BETTERSTACK_INGEST_URL:-$BS_GIT_DATA_INGEST_URL}"
if [[ "$RT_INGEST_URL" != "$BS_GIT_DATA_INGEST_URL" ]]; then   # both env-controlled
```

Reproduced with a stub `curl` on PATH: the live write token reached
`https://attacker.example.org/collect` and the script emitted a clean `ROUNDTRIP_DARK`. No refusal
fired. Pointed at the shared source instead, it silently defeats the invariant the file exists to
make derivable.

The file defines no functions and has no side effects, so re-sourcing costs nothing and the guard
bought nothing. Removed; assign unconditionally. (Not `readonly` — the capture sources this alongside
`betterstack-absence.sh` in one process, and a second `source` would then abort.)

### 2. A readback that could never succeed, laundered into a vendor accusation

The new round-trip probe polled a readback and, on timeout, consulted a CONTROL source — a
*different* table — to decide its verdict. It ignored the readback's exit code entirely:

```bash
_out="$(rt_read)"; _read_rc=$?
if [[ "$_read_rc" -eq 0 ]]; then   # a non-zero rc leaves no trace at all
```

`rt_read` was a `UNION ALL` over `remote($BS_TABLE)` and `s3Cluster(primary, $BS_TABLE_S3)`. For this
source the archive named collection does not exist (`669 NAMED_COLLECTION_DOESNT_EXIST`, measured),
and a `UNION ALL` fails if **either** arm fails. So the readback errored on every poll whether or not
the row was stored; the control (a healthy table) answered `LIVE`; and the probe emitted
`ROUNDTRIP_NOT_STORED` — exit 1, a public vendor data-loss accusation on the tracker — off a query
that never ran.

That is the AP-021 defect this issue exists to remove, reintroduced in its own fix. The script's
header even claimed the opposite: *"If the columns differ the read fails loudly … which degrades to
UNKNOWN rather than to a verdict."*

**This also corrected a claim already reported to the operator.** A live run of the probe had returned
`ROUNDTRIP_NOT_STORED` and it was reported as *the* evidence that Better Stack acknowledges writes it
does not store. The finding survives — but on an **independent** check, not the probe's verdict:
`remote(t520508_soleur_git_data_prd_logs)` still answers `CLUSTER_DOESNT_EXIST` after an acknowledged
write, and Better Stack creates that table on the first *stored* row. The probe would have said
`NOT_STORED` either way.

### 3. The guard added to close #2 had #2's shape

Review found the round trip was **unasserted**: the query stub synthesized its answer from the READ
query, so nothing tied the row returned to what `curl` actually posted. Pointing the payload at a
different marker stayed GREEN — the script's entire purpose was untested.

The fix was a write-aware stub. Its first version:

```bash
if [[ -n "$marker" && -s "${STUB_WROTE_FILE:-/dev/null}" ]]; then
  grep -qF "$marker" "$STUB_WROTE_FILE" || exit 0
fi
```

The `-s` means *skip this check when nothing was written* — exactly backwards. An empty ledger means
nothing was POSTed, so the readback must find nothing. With the `-s` in place, deleting `--data-raw`
from the POST entirely still passed. Caught by the mutation battery, not by reading.

### 4. A fourth round, at ship, found the same class one layer down — including in the fixes above

The two review rounds ended, both sign-offs were recorded, and the `/ship` Phase 5.5 completeness
consult then found **five more defects, two of them P1**, in the code those rounds had just
approved. The reviewer's own verdict — *"there is no path from a failed or unread warehouse query
to the evidence-file writer"* — was **false**, and I had already published it in the PR body.

`scripts/betterstack-query.sh` runs `curl --fail-with-body`, which returns **0** for an HTTP 200
whose body is a ClickHouse mid-stream exception. Every read in the capture was gated on that rc
alone:

```bash
fatal_out="$(_run_query "$FATAL_SQL")"; fatal_rc=$?
if [[ "$fatal_rc" -ne 0 ]]; then
  transient "... an unanswered fatal query is NOT a clean bill."
fi
...
if grep -q '"level":"fatal"' <<<"$fatal_out"; then   # an exception body contains no such string
```

Reproduced end to end: with the fatal read answering
`Code: 241. DB::Exception: Memory limit (for query) exceeded (MEMORY_LIMIT_EXCEEDED)` at rc 0, the
capture wrote **`RUNG2_BOOT_REHEARSAL=PASS`** — a host cleared for birth on a fatal check that never
ran, while the evidence file's own header says *"CLEAN = a fatal read returned zero rows."*

Two details make this the sharpest instance in this file:

- **The comment beside the gate states the correct invariant.** It says an unanswered fatal query is
  not a clean bill. The code then measures the transport's rc, which is not whether the query was
  answered. Prose and predicate disagreed, and the prose is what every reviewer read.
- **The right predicate already existed, in this PR, three files away.** `bs_absence_response_is_answer`
  discriminates on line shape precisely because a mid-stream exception arrives as a bare line — and
  the capture used it for its *control* leg while its own three reads went unguarded. The library
  was `source`d **inside** the anchor-failed branch: reachable only from the one path that cannot
  need it.

The same rc-only gate was in the round-trip probe's `_read_ever_answered`, whose comment block
describes §2 above in full and then keys on `_read_rc` — so §2's fix was incomplete, through the
other door, in the paragraph that explains §2.

And the guard-audits-the-guard problem recurred a third time: `GUARD1/H3b`, the arm asserting the
Rule-1 property that `user-impact-reviewer` had just signed off, was **vacuous**. An earlier arm
wrote

```bash
BETTERSTACK_INGEST_PROBE="$TMP/no-such-probe.sh" \
  out="$(run_sut ...)"; rc=$?
```

which is an **assignment list, not a command prefix** — bash assigns both names in the current
shell, and since that variable was `export`ed at the top of the suite, every later arm reaching the
probe leg ran against a probe that does not exist. H3b passed on *"the ingest probe is unreadable"*.
Measured: with a readable probe, H3b's identical input exits **0** and writes `PASS`.

## Key insight (revised after the ship round)

The original insight below still holds. What this fourth round adds is sharper and worse:

**A comment that states the invariant correctly is the most effective camouflage a wrong predicate
can have.** Three separate reviews — two panels and a targeted user-impact pass — read
*"an unanswered fatal query is NOT a clean bill"* directly above `if [[ "$fatal_rc" -ne 0 ]]`, and
none asked whether `rc == 0` means *answered*. The prose was doing the reviewing.

So the litmus per guard is now two questions, and the second is the one that was missing:

1. What does this guard's PASSING state look like, and is it distinguishable from the guard being
   broken, inverted, or never reached?
2. **Does the value it tests actually carry the property its comment claims?** Name the API that
   produces that value and read its contract — `--fail-with-body` is documented to return 0 on a
   200, and one `man` line falsifies the whole arm.

## Key insight (original)

**On a fix PR, review the new ASSERTIONS before the new code.** The fix is written while holding the
defect in mind, so its verification inherits the defect's framing — and the guard written to close a
gap is where that gap most often recurs, because it feels like bookkeeping rather than authorship.

Litmus per guard: *what does this guard's PASSING state look like, and is it distinguishable from the
guard being broken, inverted, or never reached?*

## Prevention

- **Ask what an include guard's key is.** A non-namespaced shell variable is attacker-settable. If a
  file declares only constants, it needs no guard; if it needs idempotence, key it on something the
  environment cannot forge (`declare -F`), and assign **before** any early return.
- **A composite read fails as its weakest arm.** Before `UNION`ing two sources, verify each answers
  independently; a `UNION ALL` over a healthy and an absent arm is an always-failing query.
- **Never let a verdict rest on an instrument that was not shown to work.** Track "did this read ever
  succeed" and report UNKNOWN when it did not — the control source is a *different* table and its
  health licenses nothing about yours.
- **A negated precondition on a guard is usually inverted.** `if [[ -s "$evidence" ]]` around a check
  means "skip when there is no evidence", which is the case the check exists for.
- **An exit code is not an answer.** Before gating on `rc`, read the transport's contract: `curl
  --fail-with-body` returns 0 for an HTTP 200 carrying an application-level error, so every
  `rc == 0` branch downstream of it needs a SHAPE check on the body. This repo already ships one
  (`bs_absence_response_is_answer`); the defect was that it was `source`d inside the branch that
  could not need it. Source shared predicates at top level, so the reachable set is not an accident
  of where the fix happened to land.
- **`VAR=x cmd` is a prefix; `VAR=x out="$(cmd)"` is an assignment list.** The second assigns in the
  CURRENT shell and, if the name is exported, silently reconfigures every later arm in the file. It
  reads identically to the first. Grep a suite for `^[A-Z_]*=.* out="\$(` before trusting any arm
  that follows one.
- **Run the cheap deterministic gates before the agent panel.** On this PR `shellcheck` found the
  highest-severity defect of one round (`_rt_host` referenced but not assigned after the parser was
  replaced — under `set -u` that aborts both the STORED and NOT_STORED paths). Reading missed it and
  so did two agents. Yields are disjoint; the lints cost seconds and the panel costs orders more.
- **Audit a battery's AXES, not its count.** The author's batteries all edited SUT *content*; the
  stubs were never edited, and that is where the vacuity was.

## Session Errors

- **A failed write produced a false `SYNTAX OK`.** The scratchpad directory did not exist, the heredoc
  write failed, and the `bash -n` that followed validated the *unmodified* file. **Prevention:**
  `mkdir -p` the destination in the same command that writes it, and confirm the file exists and
  changed before interpreting any check that reads it.
- **A stray `git stash list` in a scratch command was hook-blocked, twice**, killing the entire Bash
  call both times so nothing else in it ran. **Prevention:** never include a `git stash` verb in a
  composed diagnostic command; `git show <commit>:<path>` is the sanctioned read.
- **A `python3` heredoc terminated early** because the patch payload contained a line that was exactly
  the delimiter (`PY`). **Prevention:** use a delimiter that cannot appear in the payload.
- **The banned `${VAR:?}` form was written into a double-quoted bash string**, where bash expanded it
  and aborted the suite — the exact trap the assertion was testing for. **Prevention:** escape `\$`
  when a message must *name* a shell construct it forbids.
- **A bare-token grep matched its own explanatory comment** (`INGEST_ACCEPTING`), and the
  eyeball-instruction guard fired on newly written text **twice**. **Prevention:** the moment a task
  requires both "assert X absent" and "document X", anchor on a syntactic construct (`emit "X"`,
  `^\s*`) or strip comments before scanning — this is `cq-assert-anchor-not-bare-token` and it
  recurred three times in one session.
- **Two overstated claims were reported to the operator** before review caught them: the live
  `NOT_STORED` attributed to the probe (§2 above), and "perpetual production writer", which
  `sweep-followthroughs.sh`'s `closed_precheck` refutes — it refuses to re-litigate an issue carrying
  the sweeper's own PASS block, and the closed set is capped at 14 days with `REOPEN_MAX=3`.
  **Prevention:** before stating a consequence about another component's behaviour, read that
  component's code; "the sweeper runs scripts on the closed set" was true and the conclusion drawn
  from it was not.
- **The plan's `## Infrastructure (IaC)` declared that no secret was introduced**, and both the IaC and
  encryption-posture gates were skipped on that premise — a secret was mirrored into GitHub Actions
  during implementation. **Prevention:** when implementation introduces a resource class the plan
  denied, correct the plan section rather than letting a skipped gate stand on a false premise.
- **Three false count claims were written** ("both controls", "its only other production consumer",
  "three places … queryable"). **Prevention:** for every count a diff asserts, run the command that
  produces it — the PR that adds a second caller is exactly the PR that invalidates "the only caller".
- **A scope-out criterion was misread** — "files in the same top-level directory" was applied as
  *sub*-directory, which carried the unrelated-file count from 2 to 3 and made the criterion appear
  met. The CONCUR gate DISSENTed correctly. **Prevention:** quote the criterion verbatim and resolve
  its terms against the actual paths before claiming it.
- **An inline fix broke another suite and was reverted** — `zot-inventory.sh`'s destination pin refused
  that suite's real loopback listeners. **Prevention:** a review finding is a hypothesis; implement,
  measure, and revert with the reason recorded rather than forcing it through. Tracked as #7873.
- **A loop's trailing `&&` made a wrapper exit 1 while every suite returned rc=0.** **Prevention:** do
  not let a conditional be the last statement of a loop whose exit status is read.
- **A backgrounded command redirected into a `mktemp` log left the task output file empty**, which read
  as "no output". **Prevention:** either drop the redirect or echo the log path, and never infer a
  result from an empty task file.
- **Four review agents died on a transient server-side cascade.** Resumed from transcript rather than
  respawned, per the rule that a dead agent is resumable. **Prevention:** already covered.
- **`plugin:github:github` MCP failed to connect (400, malformed Authorization header)** and the
  `playwright` MCP disconnected mid-session. Worked around with the `gh` CLI; no impact on output.
- **A Python slice left a dangling `fi`**, and one edit dropped an `anchor_out=` assignment.
  **Prevention:** `bash -n` after every structural edit — both were caught that way within seconds.

## Related

- `knowledge-base/project/learnings/2026-09-04-three-review-rounds-each-found-defects-in-the-last-rounds-fixes.md`
  — the same shape, two days earlier: fixes carrying the defect class they close.
- `knowledge-base/project/learnings/2026-09-03-every-p1-was-in-the-verification-not-the-fix.md`
- ADR-192 (`## Amendment — 2026-09-04 (#7855)`) — the composed reading, the narrowed writing rule, and
  the permanent-table-creation consequence.
- `knowledge-base/engineering/architecture/principles-register.md` — the AP-024 carve-out this work
  registered, and the AP-020 precedent requiring it be registered rather than left in an ADR.
