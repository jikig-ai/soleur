# Learning: a fake that ignores its selectors lets every selector mutation pass, and my own fix-round added the pipefail flake

## Problem

PR #9936 (#9438) added a host feeder whose healthy path shells out to `findmnt`, `systemctl show`, `df`, `mountpoint` and `find`. The suite drove the real script against PATH fakes and went 234/234 green through a 13-seat review. A 7-seat targeted fix-round then found:

1. **The `findmnt` and `systemctl` fakes keyed on the last operand only.** Mutating the script's `-o SOURCE,OPTIONS` to `-o SOURCE`, or `-p LoadState -p ActiveState` to `-p LoadState`, stayed green. On a real host each of those is a guaranteed false page on every tick (the options field is empty, so `store_readonly`; ActiveState is empty, so `unmeasured:units`). Four seats found it independently.
2. **A fix I made in the previous round introduced a flake.** `line="$(_i findmnt ... | head -n 1)"` under `set -o pipefail` takes SIGPIPE whenever the writer prints two or more lines: measured 760/1500 pipeline runs, 17/30 ticks of the real script with a two-line fake. My own H3 row ("a multi-line findmnt answer pings") passed only by luck.
3. **Comments and prose overclaimed the bound.** `timeout 3` without `-k` cannot cut a child that ignores TERM (measured: a `trap '' TERM` sleep ran its full 4 s) and nothing cuts uninterruptible sleep. "A hung instrument is a recorded miss", "every seam but the run dir stripped" (two seams were not in the `env -u` list) and "a device READ" (a first-dirent listing is served from cache) were all stronger than the code.
4. **The run-dir refusal was a denylist of spellings** (`//mnt/x`, `/./mnt/x`, bare `/mnt` passed).

## Solution

- Fakes accept exactly the argv the script is meant to pass and refuse everything else with exit 64 plus a `fake.refused` line; one epilogue row asserts no behavioural fixture ever refused, so a selector mutation reds through the healthy-tick control rather than needing its own row. Where a real tool prints different output for a different selector, the fake prints only the requested fields.
- Take the first line in the shell (`${out%%$'\n'*}` and `read -r a b _ <<<"$line"`), never `| head -n 1` on a captured command under pipefail; treat a missing second field as unmeasured, not as an empty-options "read-only".
- `timeout -k 1 2` for every instrument, a TERM-ignoring hang fixture, and one uncached `dd iflag=direct` block read as the real device read; state in the script, ADR and runbook that uninterruptible sleep survives both signals and is ended by the unit timeout, with the absent heartbeat as the page.
- Derive set-equality rows from the script (seams read vs `env -u` operands; repeat counts for the tick budget) instead of hand-typing the list; add the third tick path (a hung root `df` is the one hang that does not become a miss).
- Spelling-canonical run-dir guard plus "not under the store".

## Key Insight

A fake is a claim about the real tool's contract, and a fake that does not refuse what it does not model makes every mutation of the script's call line survivable. The check that finds this is cheap: mutate the selector, not the logic, and see whether anything reds. Separately, a fix commit is the least-audited surface in the diff: the SIGPIPE flake was born inside the commit that closed the previous round's findings, and only a seat that re-ran the suite repeatedly saw it.

## Session Errors

1. **Script not executable, so the fake `doppler` `exec` failed and every ping was absent** — Recovery: `chmod +x` — Prevention: the mutation helper now chmods mutants and requires `bash -n` plus a healthy-tick control before trusting RED.
2. **Fixture dirs reused across rows contaminated mutation rows** — Recovery: `new_fixture` removes the dir first — Prevention: a fixture helper owns its directory lifecycle.
3. **Mutation rows could pass vacuously (a non-executable or non-pinging mutant)** — Recovery: `assert_red` healthy-gate — Prevention: every RED row proves the mutant is a working feeder first.
4. **`cmd | grep -q` SIGPIPE flake under pipefail in the suite, then the same class in the script (`| head -n 1`) in my own fix** — Recovery: here-strings and shell parameter expansion — Prevention: grep SUT and suite for `| head`/`| grep -q` under pipefail whenever a fix touches a pipeline.
5. **State file mode 644 when pre-created** — Recovery: temp file plus `mv` — Prevention: write secrets-adjacent state via umask-077 temp and rename.
6. **Fixture-relative scanner rejected `$RUN_DIR/...` operands** — Recovery: `"${RUN_DIR:?}/..."` forms — Prevention: run the fixture scanners with the first edit of a suite.
7. **Repo-global ratchets moved (guard-vacuity ledger 47→48, strip-parity count, census A4 pair, discoverability 53→54, budget pins, PyYAML for the rehearsal suite)** — Recovery: promoted/updated each — Prevention: already covered by the file-selected-suite rule; add the ratchet suites to the first targeted run.
8. **`systemd-analyze verify` flagged the missing ExecStart binary** — Recovery: `/bin/sh -c 'exec …'` shape — Prevention: copy the sibling unit's ExecStart shape.
9. **Stop-hook "unkept promise" feedback while waiting on background seats** — Recovery: stated the block with a `<stop>` line — Prevention: do not announce a follow-up action when the next event is an external notification.
10. **`gh issue create` was refused twice: body written in the same command, then no filing justification** — Recovery: body via Write to the scratchpad, `Mandated-By: wg-when-deferring-a-capability-create-a` line — Prevention: already hook-enforced; write the body first and include the mandate line.
11. **A Python replace aborted on a 3- vs 4-space indent assumption; a chained `sleep` was blocked by the harness** — Recovery: `cat -A` the lines, then re-ran; used a plain read — Prevention: inspect exact whitespace before multi-line replaces (one-off).
12. **A new T13 row for an empty run-dir could not fire (`${VAR:-default}` never yields empty)** — Recovery: dropped the unreachable row — Prevention: prove a refusal arm is reachable before writing its row.
13. **`origin/main` moved 18 commits during the review rounds and conflicted in three shared-ratchet files** — Recovery: merged, regenerated the C4 JSON from the merged sources, kept both promoted-file sets and re-counted the probe baseline — Prevention: merge-tree check before each push (done), never hand-merge a generated artifact.
