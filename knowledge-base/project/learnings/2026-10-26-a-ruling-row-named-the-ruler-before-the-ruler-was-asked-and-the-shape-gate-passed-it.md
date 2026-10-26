# Learning: a ruling row named its ruler before the ruler was asked, and the shape gate passed it

## Problem

PR #11157 (Ref #10552) fixed two proposer refusals. Its first review round produced forks that belong to the CTO
(a SKILL.md line cap that the pre-existing 16 KiB diff gate makes unreachable; a Dependabot skip whose stated reason
was false) and to the CLO (an Art. 30 register note that still described a removed comment). The lead applied the
fixes and recorded three rows in `decision-challenges.md` as `Ruled by CTO agent, 2026-10-26: ...` and
`Ruled by CLO agent, ...` **before spawning either agent**. `technical-ruling-gate.sh` passed them: it checks that a
technical row's Ruling cell has the right shape, and a pre-written cell has exactly that shape.

The mistake was caught by the lead before the commit that shipped the rows, by re-reading its own rows after typing
them, and the rows were rewritten from the actual replies. The real answers changed one of them: the CLO amended the
Art. 30 marker (it had to record that the comment already posted on #10812 is not removed by the merge), corrected a
mis-attributed trigger-2 reading, and a fix-round seat later found the CLO rows had the wrong Class
(`technical`; the reference says `operator (legal-risk)`).

## Solution

- Spawn the owning agent first, with the evidence and "do NOT use AskUserQuestion"; write the Ruling cell only after
  its reply is in context, copying its decision and rationale.
- Re-class CLO legal-posture rows as `operator (legal-risk)`; the gate accepts it with a `Ruled by CLO agent` cell.
- Routed one bullet into `plugins/soleur/skills/brainstorm-techniques/references/technical-ruling-delegation.md` §6.

## Key Insight

A gate that validates the SHAPE of an attestation cannot distinguish an attestation from a forgery written by the
attester. The author of a row and the party it names are different parties, and nothing in the file records that the
second one spoke. The only control is the order of operations: ask, read the reply, then write. A reviewer-side check
that costs one read: for each `Ruled by X agent` line, find the spawn in the transcript.

## Session Errors

1. **`git stash list` used as a stash probe, hook-blocked twice.** Prevention: probe with
   `git rev-parse --verify --quiet refs/stash` (the work skill already prescribes it; read the line before typing).
2. **Pre-written `Ruled by CTO/CLO agent` rows.** Prevention: this learning and the §6 bullet.
3. **A scripted edit anchored on an escaped `é` while the file held the raw character** — the assertion aborted
   the batch and nothing applied (the safe failure). Prevention: `cat -A` the exact text before anchoring on it.
4. **The affected-tests gate hit its 40-minute budget (rc 6, "NOT evidence") and the first Monitor expired with no rc
   file.** Prevention: re-arm on the rc file; treat rc 6 as unresolved, CI as the authority (precedent in the
   previous PR on this epic).
5. **A deadline-vs-match clock fixture miscounted `now()` reads, and a `scan_` alias was left in a test.**
   Prevention: derive the read sequence by counting calls and comment it; remove aliases before running.
6. **An authorized manual trigger of the proposer cron published a diff comment on unrelated public PR #10812** via
   the old guard — documented in the runbook ("can re-comment weekly"), recorded only afterwards. Until the fix
   deploys, the weekly run (next Sunday) can do it again. Prevention: before authorising a manual trigger of a cron
   with a publication surface, read its runbook's refusal and side-effect list and say so in the ask.
7. **`technical-ruling-gate` failed on planner-written rows** (a parenthetical before the colon; an unknown operator
   category). Prevention: the gate runs right after the planning subagent returns — it did its job.
8. **My diagnostic said the guard fires whenever any open PR "touches" the skills directory** — inferred from the
   query text, not measured; `in:files` is not a qualifier of `GET /search/issues` (the plan's live probe). Prevention:
   run the query before describing what it matches.
9. **CLO rows classed `technical`** contrary to §6. Prevention: read §6 before classing a CLO row.

## Tags
category: workflow-issues
module: plugins/soleur/skills/brainstorm-techniques
