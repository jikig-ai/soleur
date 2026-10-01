---
title: An evidence verdict that summarizes the session's own log inherits the summarizer's model — quote the artifact verbatim for every load-bearing claim
date: 2026-09-17
category: engineering
tags: [evidence, verification, cloud-mode, sweeper, verbatim, provenance, claims-vs-measurements]
symptoms:
  - "SC3 PASS recorded on timing correlation + agent-reported gate attribution while the session's findings log held the verbatim 'Cloud Mode rule 3 fired' line unpulled"
  - "evidence section recorded `devin cloud drs rm`, a subcommand that does not exist (rm is top-level `devin rm`)"
  - "plan asserted '~30 SKILL.md files' carry the cloud-mode marker as 'grep-verified'; actual count 64"
  - "two review agents and one user-impact agent independently flagged claims that a verbatim quote or a --help call would have made unassailable"
module: knowledge-base
component: evidence-recording
problem_type: process
resolution_type: documentation_practice
root_cause: asserted-instead-of-measured
severity: medium
issues: [8228, 8257, 8172]
---

# Learning: Evidence verdicts need verbatim provenance, not summarized attribution

## Problem

On #8228 (post-merge Devin Cloud verification of SC1/SC3/SC4), the committed
evidence section recorded correct verdicts — but three of its load-bearing
claims were summaries of what the session reported rather than quotes of the
session's own record:

1. **SC3 PASS rested on timing inference.** The verdict row said the ack gate
   "fired unprompted" before `doppler secrets get`, inferred from the Step-3
   marker → silence → suspension sequence. The `doppler` binary was absent on
   the VM, so a hostile reading could attribute the stall to the missing
   binary instead of the gate. The session's own findings log already held
   the verbatim attribution — `Cloud Mode rule 3 (acknowledgement gate)
   fired: blocking message_user ack requested before running doppler secrets
   get …` plus the doppler-absence recorded as a *pre-check* — but the
   committed artifact did not quote it until review forced the pull.
2. **Two authored claims were wrong in the fail-safe direction.**
   `devin cloud drs rm` was written into the evidence as the cleanup command
   (no `rm` exists under `drs`; the real surface is top-level `devin rm`),
   and the plan called the cloud-mode marker population "~30 SKILL.md files"
   as "grep-verified" — actual count 64. Both were written from assumption,
   both caught by review agents, both fixable by one command each at write
   time.
3. **A compound record can contradict itself across sections.** The
   `## Deferral record` bullet still listed the verification session as an
   open residual item while the appended section recorded it discharged —
   same file, both statements live.

The sweeper (`cloud-mode-postmerge-evidence-8159.sh`) detected *presence*
correctly and fired exit 5; adequacy is deliberately the operator's call, so
the quality bar for these claims is set by the review panel, not by any gate.

## Solution

For every load-bearing claim in a session-evidence artifact:

1. **Quote the source record, don't summarize it.** When the session writes
   its own log (`/tmp/sc-verify/findings.md`), pull the verbatim lines into
   the committed artifact for gate attribution, suspension liveness, and any
   claim an operator could otherwise attribute to a different cause. A
   `drs run` read-back of the log costs one command; it converts
   "agent-reported" into "recorded".
2. **Measure claims at write time, not from memory.** `--help` for command
   names, `grep -l … | wc -l` for counts, `git merge-base` for ancestry —
   each fix in this session was one command; each claim that skipped it was
   a review finding.
3. **Annotate, don't leave self-contradiction.** When an append-only file
   gains a section that discharges an earlier open item, mark the earlier
   item discharged in place rather than striking it (the file records
   history honestly) or leaving it ambiguous.

## Key Insight

An evidence file's job is to survive a hostile re-reading by someone who was
not in the session. Every claim that says "X happened" needs to answer
"says which artifact?" — and the strongest form is the artifact's own words
committed into the record. Timing correlation and agent say-so are the
second-best forms; they invite exactly the alternative-attribution reading
the evidence exists to exclude. The same discipline applies to the boring
claims (command names, file counts) — those are the ones written fastest and
checked never.

This is the evidence-recording half of the documented
`hr-no-dashboard-eyeball-pull-data-yourself` / "verify artifact output, not
invocation success" rules: the artifact must be *quoted*, not merely
referenced.

## Session Errors

1. **`devin cloud drs rm` recorded as the cleanup command — does not exist.**
   Recovery: `devin cloud drs --help` + `devin --help` showed `rm` is a
   top-level command; corrected in two files. **Prevention:** run `--help`
   on any CLI surface named in a committed artifact; a recorded remediation
   command that does not exist is dead advice.

2. **Plan asserted "~30 SKILL.md files" as grep-verified — actual 64.**
   Recovery: `grep -l 'soleur-cloud-mode:start' plugins/soleur/skills/*/SKILL.md
   | wc -l` → 64, corrected. **Prevention:** a count written with the word
   "verified" must be produced by the command it cites, in the same session —
   never recalled.

3. **SC3 verdict initially rested on timing inference alone.** Recovery:
   pulled the verbatim gate-attribution lines (findings.md:223-224) from the
   suspended session and quoted them in the verdict row. **Prevention:** for
   every verdict whose correctness is a *cause* (gate fired) rather than a
   *result* (no output), quote the causal record, not the absence.

4. **`gh issue create` denied by the milestone-required gate.** Recovery:
   retried with `--milestone "Post-MVP / Later"` → #8257 filed.
   **Prevention:** already hook-enforced — the deny message names the fix;
   include `--milestone` on the first attempt.

5. **Commit blocked by commit-on-main guard via `workdir:` exec param**
   (forwarded from session-state.md). Recovery: `cd <worktree>` in a
   persistent shell so the guard resolves the feat branch. **Prevention:**
   session-state already records that exec CWD does not persist — always
   `cd` explicitly inside worktree sessions.

6. **Background SC3 poll interrupted; early check at ~4 min into the 10-min
   window.** Recovery: bounded foreground `drs run` re-checks until the full
   persistence window elapsed. **Prevention:** none needed — the plan's
   bounded-loop design absorbed it; record the observation timestamps so the
   window is auditable.

7. **Deferral-record bullet left listing a discharged session.** Recovery:
   annotated in place. **Prevention:** when appending a discharge section,
   grep the file for the item's earlier open mention and annotate it.

8. **Generated `knowledge-base/INDEX.md` diff needed manual reconciliation.**
   Recovery: verified the rides-along convention (`generate-kb-index.sh`
   runs via lefthook with a `--check` freshness gate) and included the diff
   in the commit rather than reverting it. **Prevention:** treat generated
   index diffs as expected content when `knowledge-base/` files are added —
   the `--check` gate makes including them mandatory, not optional.

## Cross-References

- Issue #8228 (post-merge cloud verification — this session)
- Follow-up #8257 (SC4 marginal-effect clean-account arm), tracker #8172 item 5
- `scripts/followthroughs/cloud-mode-postmerge-evidence-8159.sh` (presence sweeper)
- `knowledge-base/project/learnings/2026-09-15-devin-dual-hook-registries-dead-matchers-fires-then-noops.md` (cloud hook surface)
- `2026-05-29-plan-reverify-must-assert-the-invariant-not-a-proxy` (invariant-vs-proxy — the SC3 attribution finding is this class)
