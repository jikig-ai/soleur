# Learning: a test that executes the CONSUMER with hand-set inputs cannot see its PRODUCERS, and a stub that answers any argv cannot see the call line

## Problem

#7079 item 3 made the release workflow's `Finalise` step overwrite an orphaned draft's notes in
the same `gh release edit` call that publishes it. The first suite (T8/T8b) executed the REAL
parsed `Finalise` block under a `gh` stub, with 77 -> 92 assertions and a 9-mutation battery all
RED. Ten review seats then found the one P1 that battery could not express:

- **The producers were unpinned.** T8 set `DRAFT_EXISTS`, `PR_NUMBER` and `RELEASE_NOTES_FILE`
  directly and T8b pinned the consumer's `env:` literals, so a producer that stopped emitting the
  value (the changelog step gated on `draft_exists == 'false'`, the `Find merged PR` step renaming
  `number=`, the notes file written to a different tmpfile) left every row green while the feature
  published the stale notes forever. Four mutants of that shape survived at 92/92.
- **The fix repeated the shape one level out.** The new T8c ran the real producer blocks but its
  `gh` stub answered `api` and `pr` regardless of the endpoint, `--jq` and `--json` fields, so a
  mutated call line (`--jq` dropped, endpoint changed, `body` dropped from `--json`) read the right
  answer. Eight of fifteen producer mutants survived until the stub refused any argv it did not
  model (exit 64, logged, asserted empty).
- **A snapshot compared a file to itself.** The stub snapshotted the `--notes-file` content at
  call time, but row (a) compared it to the same file the block had been handed, so a mutation
  emptying that file made both sides empty. Fix: compare to a pristine copy taken before the run.

## Solution

Execute the producers too, and chain them into the consumer: run `Create secure temp files`,
`Find merged PR` and `Extract changelog from PR body` for real, take the changelog step's title
and body from the PR step's own outputs, and feed `number=` into `Finalise`. Make the stub strict:
it answers only the exact argv the block is expected to send and exits 64 otherwise, and the suite
asserts the refusal log is empty. Drive every empty-number arm (`workflow_dispatch`, commit-message
fallback, `give_up` with no PR, `gh pr view` failing, a non-integer API answer) through the real
block and into `Finalise`. Compare content byte-for-byte against a pristine copy, never against the
file the block can rewrite.

## Key Insight

Executing the real consumer block proves what the consumer decides. It says nothing about whether
its inputs are ever produced, because the harness supplies them. Name every input the executed
block reads, then ask which step produces it and which assertion would go red if that step stopped.
The stub is part of the oracle: if it answers regardless of what it was asked, every mutation of
the call line is scored through a fake that cannot see it.

## Session Errors

1. **A Stop hook fired five times on closing sentences like "I'll apply the batch once the
   remaining seats report".** Recovery: end the turn with one `Paused: <what I am waiting on>`
   sentence. **Prevention:** while waiting on background agents, never end a message with a
   first-person future commitment; state the wait in the `Paused:` form from the first message.
2. **A placeholder `Monitor` was armed with a 1 ms timeout, expired immediately and produced a
   spurious notification.** Recovery: ignored it and waited on the agent completion events.
   **Prevention:** arm a Monitor only with a real until-loop over a file or marker the producer
   writes, and a timeout that outlives the producer.
3. **`ps -eo ... | awk '/flock/ && /test-all/'` was blocked by `pkill-self-match-guard.sh`.**
   Recovery: `source scripts/lib/proc.sh; list_runs; kill_mine`, which resolves ownership through
   `/proc/<pid>/cwd` and refused a sibling session's run. **Prevention:** use `proc.sh` for any
   process census or kill; never hand-roll a `ps | awk`.
4. **A mutation row `f3` (fallback to a plain publish after a failed notes edit) survived because
   the stub failed EVERY `gh release edit`, so the fallback failed too.** Recovery: added a
   `MOCK_GH_EDIT_FAIL_NOTES` knob that fails only the call carrying `--notes-file`.
   **Prevention:** when a mutation survives, label it fixture-gap vs equivalent before touching the
   guard; a stub that fails uniformly cannot distinguish "fallback present" from "fallback absent".
5. **A mutation anchor (`s2`) matched twice and did not land.** Recovery: re-anchored on the
   enclosing env block. **Prevention:** the battery runner asserts `count == 1` before replacing and
   prints `NOT-LANDED`; read that line before reading any rc.
6. **While replacing the stub's body default with a literal, the escaping went wrong (a doubled
   backslash survived into the JSON), and the suite reddened two rows.** Recovery: corrected the
   escape. **Prevention:** after editing a heredoc-embedded stub, run the suite before committing;
   the assertion that read the stub's output caught it within seconds.
7. **A review seat asserted T8 was a static grep of the workflow text; it executes the real parsed
   block.** Recovery: rejected the finding after reading the test. **Prevention:** reconcile a
   seat's claim about a test's mechanism against the test body before acting on it.
8. **A first draft of the failing-edit rows used `set -- $scenario` on a string containing a path
   with a space.** Recovery: caught before running and replaced with explicit calls.
   **Prevention:** never word-split a value that embeds a path from a fixture directory named with a
   space; the fixture dir is named that way on purpose to catch an unquoted `--notes-file`.

## Tags
category: test-failures
module: release-workflow, reusable-release-idempotency
