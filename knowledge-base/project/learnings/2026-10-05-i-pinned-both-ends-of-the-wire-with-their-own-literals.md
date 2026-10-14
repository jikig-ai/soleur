# Learning: both ends of a handoff were pinned, each with its own literal, and they disagreed

## Problem
PR #9532 (the single-use web-2 LUKS rebirth workflow, #9372) shipped through a 17-seat review with every suite green while carrying a defect that
would have refused every real apply: the pre-plan step exported `graded=pre`, and `scripts/web2-rebirth.sh delete-volume` required
`PRE_PLAN == graded`. The workflow suite pinned the step's output, the script suite pinned the script's input, each with its own literal.
Only a verification seat reading both files side by side saw it. Other defects of the same review rounds:

- a read-only `resume:post_apply` window could not complete a partly failed apply (a missing NIC, attachment or firewall update);
- a step captured a script's stdout to a file, and that stdout carries `::add-mask::<secret>` lines, so a masked value reached the runner's disk;
  the same shape survived in a second step and was found only by the verification pass;
- `date -d ""` is midnight today, so an absent creation time read as an age of a few hours and offered a resume; it was fixed at three sites over
  two rounds, the third only by the verification seat (the sweep keyed on the phrasing of the first fix, not on the subject: every `date -d` over
  an API field);
- an earlier jq filter error inside a command substitution made a safety row pass silently.

## Solution
- A joint row compares the literal one side EXPORTS with the literal the other side REQUIRES (S12m, S12m2, S12m3) and each destructive step takes a
  proof from the step that earns it (`FLIP=met`, `PRE_PLAN=graded`, `NEVER_POOLED=absent`, `EMPTINESS=PASS*`), refusing on anything else.
- Resume became a real mode (a third gate mode that may only ADD; no `-replace`; never-pooled and the reboot gated on the soak marker).
- Facts travel through a dedicated file (`W2_FACTS_FILE`); a step never writes a script's stdout to disk, and the mask line goes to stderr.
- Empty timestamps stay "unknown" at every `date -d` site, with a row per site.

## Key Insight
Pinning both endpoints of a handoff with independent literals is two covered endpoints and an uncovered wire. For every value one step hands to
another, put the producer's literal and the consumer's literal in ONE assertion, and prefer a consumer that refuses on anything but the exact
proof. When a defect class is found, sweep its SUBJECT repo-wide (every `date -d` over an API field, every capture of a script's stdout), not the
phrase of the first fix. A run that cannot be dispatched offline (here: no live step is allowed) needs its wiring proven by driving the real step
bodies under the production shell against shims.

## Session Errors
1. **graded=pre vs graded** — Recovery: joint literal rows. **Prevention:** compare producer and consumer literals in one row for every cross-step value.
2. **Read-only resume could not heal** — Recovery: add-only third gate mode. **Prevention:** for each recovery window ask which plan mode can complete it.
3. **stdout captured to disk carried `::add-mask::`** — Recovery: `W2_FACTS_FILE`, mask to stderr. **Prevention:** a capture of a script's stdout is a secret-on-disk risk by default; grep every `> "$out"` of a script that masks.
4. **`date -d ""` read as midnight today (3 sites)** — Recovery: unknown stays unknown. **Prevention:** sweep by subject (`date -d` over API fields), not phrase.
5. **Silent jq filter error in a safety row** — Recovery: fail-closed plus a positive control. **Prevention:** every filter-based guard needs a must-pass row.
6. **Registering a suite in `scripts/test-all.sh` forces the full ~2 h battery** — Recovery: resume prompt for improving the runner-changed fallback. **Prevention:** none yet (tracked as a user decision).
7. **Hook blocked a Bash call whose heredoc text contained the string for a forbidden process-kill flag** — Recovery: Write tool for briefs. **Prevention:** write prose briefs with Write, not heredocs.
8. **A stray `cat >` waiting on stdin stalled a Bash call** — Recovery: rerun without it. **Prevention:** never leave a bare `cat >` in a one-liner.
9. **Mutants whose edit text no longer matched after the workflow text changed** — Recovery: re-anchored them (the harness correctly failed them). **Prevention:** after editing a workflow step, rerun the suite before anything else and treat "did not land" as a sweep list.

## Tags
category: logic-errors
module: web2-luks-rebirth (workflow, scripts, suites)
