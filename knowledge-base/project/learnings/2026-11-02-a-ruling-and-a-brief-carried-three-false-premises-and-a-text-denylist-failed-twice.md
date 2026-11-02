# Learning: three false premises rode into rulings and briefs, and a text denylist failed two rounds running

## Problem

PR #11815 (the Inngest flip-token split, #9927 item 4) was reviewed by a 12-seat panel, two CTO rulings
batches and two targeted fix rounds. No seat found a P1, and the defects that mattered were all in sentences
the work itself had written, not in the Terraform:

1. **A premise stated as a fact entered a binding ruling, then every brief.** Ruling R9 said the 384 B
   headroom floor "stays in the required infra-validation job". Three seats and a direct read of the workflow
   showed `infra-validate-required` has `needs: [detect-changes, validate]` only, the ruleset has no matching
   context, and the size test's floor rows skip when terraform is absent. A floor breach can merge. R8's
   rationale ("an extra heredoc line is inert because the file is never sourced") was true of the flip file
   and false of `/etc/default/inngest-doppler`, which root `.`-sources. My own coverage-consult note said
   "neither gate reads `.after`", and the replace gate does read it for its firewall check.
2. **A liveness claim was inherited, not measured.** The plan, the runbook, the ADR and issue #11820 all said
   the G3/G3.7 liveness refusal catches a dead flip token. The readers key on host, host name and
   `SYSLOG_IDENTIFIER == inngest-cutover-flip` only, deliberately not on a reason, so a failing unit's own
   doppler error line counts as "audible". The first flip-token use was also mislabelled `op=arm`; on a
   replaced host that inherits `done` it is the unit's own read, and the first write happens only after
   `op=resume`.
3. **A text denylist over a script's source produced new gaps in two consecutive rounds.** T-flipsh was a
   regex over the comment-stripped text of the baked flip script, meant to prove it never dumps
   `DOPPLER_TOKEN`. Round one found bare `export`, `declare -x` and `/proc/*/environ`; the widened regex then
   missed `env;`, `$(env)`, a backtick `env`, a redirected `export >&2`, text after a quoted ` #`, and jq
   `$ENV`.
4. **The sizes were measured on stand-ins.** Only the two Doppler token stubs in the budget script were
   high-entropy; three others were repeated filler that gzips to almost nothing. The quoted "576 B headroom,
   108 B under the budget" were not real margins (honest: 424 B, 32,344 B stored).
5. **My last edit broke a repo-global ratchet that the fix agents had satisfied.** Pinning the canary scan's
   wiring added redirect operands to a suite with a baseline of 2 fixture-relative sites; live became 13.

## Solution

- Each premise was settled by running the command that falsifies it, not by arguing: read the rollup's
  `needs:`; read `_current_instance_row_counts` and the unit's `SyslogIdentifier`; `dash -n` the whole
  assembled runcmd; re-measure the budget with all five stubs hash-derived.
- The CTO's second batch ruled on the premises: reword the floor as a PR-visible check (the 32,768 B cap is
  the hard gate, enforced by `--cap-only` on the replace dispatch); keep R8 with a corrected rationale and a
  measured reconsideration trigger (a `dp.` prefix guard costs 44 B stored, leaving 380 B against a 384 B
  floor); delete the text tripwire and replace it with a runtime canary scan.
- The canary: the real flip script runs in the existing stub harness with a synthetic token in
  `DOPPLER_TOKEN`, every runner site captures output instead of `/dev/null`, and `teardown_case` fails if the
  canary appears anywhere in the case's work dir. Two FATAL controls pin the wiring itself (the scan fails a
  case whose `out.log` carries the canary; every runner site still captures), each mutation-proven in a
  sandbox. The new operands use `${VAR:?}` so the ratchet baseline did not grow.

## Key Insight

A fact stated inside a ruling or a brief is a claim, not an input. The reviewer fan-out is good at finding
defects in code and poor at questioning a premise that arrives pre-labelled as decided, so the premise has to
be checked when it enters the document that will be copied: one command per factual sentence ("is this job
required", "is this file sourced", "does this gate read `.after`"). Two further generalisations. A text
denylist over source code that fails twice is the wrong instrument: state the contract and move the property
to a runtime recorder in the harness that already executes the script. And a number measured on stand-ins is a
bound on the stand-in, so label the margin with what was measured (here: all five stubs hash-derived, 424 B).

## Session Errors

1. **A CTO ruling named `systemctl --root cat`, which systemd refuses** (forwarded from the plan phase) —
   Recovery: measured; used `systemd-analyze --root=<dir> cat-config`. **Prevention:** a ruling that names a
   tool invocation gets that invocation run before it is copied into a plan.
2. **`mint-inngest-bootstrap-tag.sh --dry-run` reported `reason=shallow`** (forwarded) — Recovery: unshallowed,
   then `result=noop`. **Prevention:** the plan's acceptance line already says "unshallow first"; no change.
3. **Three false premises carried into a binding ruling and the briefs** (required job; never sourced; neither
   gate reads `.after`) — Recovery: seats and a second CTO batch corrected them. **Prevention:** a bullet in
   the review fix-round briefing reference (added with this learning): run the command that falsifies each
   factual premise before it enters a brief or a ruling request, and verify any path or invocation you hand an
   agent.
4. **The implementer found three repo-global ratchets only through the full affected gate** (workflow size
   gate, suite weight row, fixture-relative-assert) — Recovery: fixed in `7fb0c7de32`. **Prevention:** already
   covered by the existing rule to brief fix agents on the repo-global ratchets by name.
5. **My final edit tripped fixture-relative-assert (13 sites against a baseline of 2)** — Recovery: ran the
   ratchets after the last edit, guarded the new operands with `${VAR:?}`. **Prevention:** re-run the
   ratchets after the final edit, not after the one before it (already the practice).
6. **My brief told fix agent X to find the fixture-relative lint with a grep that returns nothing** — Recovery:
   X located the suite elsewhere. **Prevention:** the item-3 bullet (verify a pointer you hand an agent).
7. **A `STAGED=` comparison with `grep -n` line numbers reported "DIFFERS"** — Recovery: content-only compare
   was identical. **Prevention:** compare content, not line numbers, after any edit above the line.
8. **I guessed the sole-copy drift check's path (rc 127)** — Recovery: `git ls-files | grep`. **Prevention:**
   resolve a suite's path with `git ls-files` before running it.
9. **`cd` into a mutation sandbox reset the shell to the main checkout** — Recovery: explicit `cd` to the
   worktree at the start of every call. **Prevention:** known trap, already recorded in the review reference.
10. **The Stop hook repeatedly flagged closing text that named an action not yet taken** — Recovery: ended
    every closing message with a `Paused:` sentence. **Prevention:** existing hook; no change.
11. **A merge conflict on `suite-durations.tsv` after merging `origin/main`** (two independent row
    additions) — Recovery: kept both. **Prevention:** none needed; one-off.

## Tags

category: workflow-patterns
module: inngest-flip-token-split, review
