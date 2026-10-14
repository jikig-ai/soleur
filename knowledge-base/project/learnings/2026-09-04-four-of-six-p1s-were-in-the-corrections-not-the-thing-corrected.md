---
title: "Four of six P1s were in the corrections, not in the thing being corrected"
date: 2026-09-04
issue: 7791
pr: 7838
category: workflow-patterns
tags: [correction-pr, review, attestation, legal, guard, verification, backticks, grep]
---

# Four of six P1s were in the corrections, not in the thing being corrected

## Problem

Issue #7791 existed to produce a missing CLO attestation and to correct stale claims in a statutory
register. Every gate was green — guard `7 assertion(s), 0 failed`, unit suite 36/36, three sibling
suites, shellcheck clean, the plan's nine test scenarios, a two-pass CLO signature. An 8-agent
review panel then found **6 P1 and 11 P2**.

**Four of the six P1s were introduced by this PR, and three sat in text that had already been
reported to the operator as verified.**

## The generalizable shape

On a PR whose deliverable is a CORRECTION, the corrections are the highest-risk surface in the
diff — higher than the thing being corrected. The author writes them while holding the defect in
mind, so the replacement text inherits the defect's framing and nobody re-checks prose written to
explain a fix. Concretely, in one PR:

- A marker faulting a 2026-09-03 annotation for quoting `"Four rows are…"` — text silently edited
  out of the file — was added in the **same diff** that replaced `"Six rows are…"` with
  `"All eight rows below…"`. `grep "Six rows"` at HEAD then returned **only that marker's own
  quotation**. The append-only failure was reproduced inside the correction for it.
- A finding (`N5`) recorded a rotted evidence pointer, then downgraded itself with
  *"reachable at the correct path, which is also cited in the same sentence."* Measured: the
  grounding sentence at post-mortem line 144 cites **only** the missing path; the live one is at
  line 302, 158 lines away. The mitigation was false, and it was the sentence that downgraded the
  finding — and it had propagated verbatim into the tracking issue.
- Applying a CLO ruling as "frontmatter only" flipped an audit to `SIGNED-OFF` over a body still
  reading `**Overall disposition: BLOCKED.**` at line 38. One document, two answers.

**Gate:** for every causal or universal sentence a correction ADDS, name the command that would
falsify it and run it. Review the new ASSERTIONS before the new content.

## A certification that could not detect the thing it certifies

The attestation's Method section certified against a guard summary line as a *falsifiable
condition*:

```
7 assertion(s), 0 failed (registers=4 rows=5 produced=12 waived=8 waiver-parity=ok)   exit 0
```

Both `produced` (a match count) and `waived` (`${#NOT_TRANSCRIBED[@]}`) are **cardinality**, and the
swap the PR performs conserves both. Reconstructing the pre-swap tree — the commit where the
attestation file is **absent** — and running the guard yields a byte-identical line:

| Tree | Attestation file | Summary line |
|---|---|---|
| pre-swap (`164ce0fd6`) | ABSENT | `produced=12 waived=8 waiver-parity=ok` |
| post-swap (HEAD) | present | `produced=12 waived=8 waiver-parity=ok` |

So a rebase dropping the atomic commit would print the certified string over a register citing a
file that does not exist. The plan's own AC5/AC6 membership greps close it — but the plan is not
shipped and is not the certified instrument.

**Rule:** a certification stated over a CONSERVED quantity certifies nothing about the operation
that conserves it. State it on MEMBERSHIP: the set differs by exactly `{−X, +Y}`, plus `test ! -f X`
and `test -f Y`. The corrected Method carries four such conditions, each executed.

## Improving a guard can invalidate a signed instrument

The review surfaced a real latent gap: the waiver loop asserts each waived path EXISTS and CITES an
issue, but never that the file is still in the producer's reach — so a reword that drops a file's
last `Art. 33` citation takes it out of `produced` while the waiver stays, at `0 failed`.

The fix was ~15 lines and mutation-proven (control 8/0 green; mutant 8/1 red with clean
attribution, parity held `ok` so only the new check fired). **It was reverted before merge.**

It takes the guard from 7 to 8 assertions, and that string is transcribed at **eight sites, three of
them append-only or signed**. Landing it would have made three signed instruments assert a figure
the guard no longer emits — and the attestation's own Method would then read as *"the swap went
wrong"* when nothing had. It also broke the suite's `MIN_CHECKS` floor until ratcheted in lockstep
(35/1 until 7→8).

**Rule:** before improving a guard, grep for its output's transcriptions. A volatile count written
into an append-only instrument cannot be corrected in place, so the instrument constrains the guard.
The deeper fix — stop transcribing `produced=`/`waived=`/assertion counts into signed text, cite
`exit 0` plus a date — is recorded on #7787.

## Two shell traps, same root, both hit in one session

**Backticks inside double quotes are command substitution.** The repo already documents this for
`git commit -m`. It bites in two more places:

1. A bash array element: `"path | reason … \`audits/foo.md\` …"` — the guard exited **127**,
   `audits/…: No such file or directory`. Loud, caught immediately.
2. An **unquoted** heredoc (`<<PY`, used to interpolate a shell variable into a Python script) —
   backticks inside the Python *string literal* were substituted by bash before Python ever saw
   them. This ate a filename out of a GitHub issue body and left `> appears at line 302` with no
   subject. **Silent.**

Use `<<'PY'` and pass variables via the environment (`export X=…; os.environ["X"]`). Markdown
backticks are safe in markdown files and unsafe in every shell-quoted context that carries them.

## Asserting an absence from a line-oriented grep

An agent reported two contradicting sentences in a signed audit. `grep -n "null on purpose"`
returned nothing, so the claim was corrected as half-wrong. The phrase wraps a line break
(`… are null on` / `purpose.`). A whitespace-normalised search finds it:

```bash
tr '\n' ' ' < "$f" | tr -s ' ' | grep -oE "does not sign off anything.{0,90}"
```

The agent was right on both sentences; the correction was the error. **An absence claimed from a
line-oriented grep is not an absence** — the repo documents this for symbol lookups; it applies
identically to prose.

## Other traps worth the line

- **`.git` is a FILE in a worktree.** A rebase-resolution loop testing `[ -d .git/rebase-merge ]`
  exited immediately reporting success with six commits unapplied. Use
  `git rev-parse --git-path rebase-merge`.
- **A sandbox for a guard that reads `git ls-files` must be a git repo.** The first attempt's
  control came back RED with 5 × `not TRACKED`; every mutation row measured against it would have
  been noise. `git init && git add -A` inside the sandbox fixes it. A red control voids the battery.
- **`echo "X"` after a command runs regardless of its exit** when separated by a newline rather than
  `&&`. Reported COMMITTED on a commit the pre-commit hook had rejected.
- **A `git log -S` search is confounded by your own diff** when the correction quotes the string it
  supersedes.
- **A shard `rc=1` can be a sibling's release.** `scripts` failed on
  `[FATAL] A SUITE WROTE TO THE LIVE REPOSITORY` naming two tags — both pointing at another
  session's merge (#7824), mid-run. All four suites covering the diff passed in isolation.

## Session Errors

**1. Plan baseline stale on its own first step.** #7803 landed mid-planning and moved the guard from
`produced=10 waived=6` to `12/8`; Phase 0.1 asserted `waived=6`. — Recovery: re-measured in a
git-backed sandbox with a green control and updated 25 operative sites, leaving the planning-review
record verbatim under a dated supersession. — **Prevention:** already enforced (`work` Phase 0.5
check 6 hard-fails for `knowledge-base/legal/**`); it fired correctly.

**2. First sandbox incomplete** — missing the delegated `tenant-dpa-register-guard.sh`, guard exit 2.
— Recovery: copied the full `scripts/`. — **Prevention:** the control caught it by aborting rather
than reporting a number; this is the harness rule working.

**3. Second sandbox control RED** (5 × `(b) not TRACKED`) because it was not a git repo. — Recovery:
`git init && git add -A`. — **Prevention:** route to `review/SKILL.md` — a sandbox for a guard
reading git must be a repo.

**4. Rebase loop exited claiming success with 6 commits unapplied** — `.git/rebase-merge` never
matches in a worktree. — Recovery: `git rev-parse --git-path`; nothing lost, reflog intact. —
**Prevention:** route to `git-worktree`.

**5. Backticks as command substitution, twice** (bash array → exit 127; unquoted heredoc → silent
text loss in an issue body). — Recovery: plain text in the shell copy; quoted heredoc + `os.environ`.
— **Prevention:** route to `work/SKILL.md`, extending the existing `-m` warning.

**6. Asserted a sentence absent using a line-oriented grep.** — Recovery: whitespace-normalised
re-search; the agent was right. — **Prevention:** already enforced in `review/SKILL.md`; route the
Why.

**7. Over-claimed a verification to the operator** — reported AC4's exact-string match as though it
discriminated the swap. — Recovery: measured both trees, corrected in the next message. —
**Prevention:** already enforced; the lesson is that "exact match" and "discriminating" are
different properties.

**8. Added a guard assertion without ratcheting `MIN_CHECKS`** → suite 35/1. — Recovery: 7→8, then
reverted the whole change for the transcription reason above. — **Prevention:** recorded on #7787.

**9. Stopped the pipeline on a forward-looking sentence** — wrote "Continuing the pipeline" and
ended the turn; the operator had to ask why. — **Prevention:** already enforced in
`review/SKILL.md` ("CI is running is NOT a handoff"); the same shape applies to *any* trailing
intention.

**10. markdown-lint blocked three commits** (MD022/MD032, MD032 from a marker landing mid-list,
MD012 from a trailing newline). — one-off.

**11. `echo "COMMITTED"` ran on a rejected commit.** — one-off, but it is the documented
`$?`-after-a-pipeline family.

**12. Environment:** `github` MCP failed auth; `playwright` MCP disconnected mid-session; a
pre-existing orphan worktree could not be reaped (EACCES); 3 of 6 plan-review agents stalled and
were recovered by resume rather than respawn. — one-off / not ours.

**13. Token-efficiency report under-measures.** It reported `Largest subagent: n/a (0 tokens)`
because the telemetry files are unpopulated in this worktree. Actual subagent spend was ~2.1M
tokens (planning ~532k, two CLO passes ~405k, the 8-agent panel ~1.13M). A zero from an
uninstrumented channel is not a measurement. — **Prevention:** treat `n/a` as a gap, never as
"within thresholds".

## Key insight

A green gate certifies the property it measures, not the property it is named for. Three instruments
in this PR were green while asserting something false: a guard summary that could not distinguish a
completed swap from an absent one, a signed audit whose frontmatter contradicted its own body, and a
correction marker quoting text its own commit had removed. The panel found them; no gate could,
because each gate was measuring exactly what it claimed to.

Net issue flow: closes #7791, files #7847, #7848, #7851 (+2). One further finding was recorded as a
comment on #7787 rather than filed, keeping it from being +3.
