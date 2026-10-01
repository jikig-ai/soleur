# I swept by literal when the property was a claim, and the site I missed was in a file I had already edited

**PR:** #8003 · **Closes:** #7957 · **Date:** 2026-09-09

## Problem

#7957 reported a false clause in `plugins/soleur/skills/work/SKILL.md`'s wrapper-as-guard
paragraph: it told readers a backgrounded command's completion notification exists "precisely so
you need not infer from a tail". A background task's exit code is that of the **last command the
shell executed**, so a trailing convenience line becomes the reported verdict.

The fix is two prose hunks. Everything expensive in this session came from the *propagation* and
the *verification*, not the fix.

## Key Insight

**A propagation sweep must be indexed by the CLAIM, not by the LITERAL — and line-wrapping is
only the second of three failure modes.**

The repo already documents two: correct the OLD string (not the new one), and be wrap-insensitive
because a blockquote splits a phrase across lines. I handled both — a wrap-insensitive pass over
all 9,684 tracked `*.md`. The third mode has no such coverage: **paraphrase**. The site I missed
said

> **Prevention:** wait for the completion notification; a mid-stream hook line is not the verdict.

as the remedy for an error the same bullet names "Inferred a commit **verdict**". It contains none
of the swept literal, and it sits 57 lines below the bullet I had *just corrected*, in the same
file, under `## Session Errors` — the operative-conclusion-far-from-the-edited-paragraph position
the repo warns about. Two independent review agents found it; no literal grep could.

The property-shaped sweep finds it in one command:

```bash
grep -rniE "(wait for|trust)[[:space:]]+(the[[:space:]]+)?(harness'?s?[[:space:]]+)?(task-)?(completion[[:space:]]+)?notification" --include=*.md .
```

**Corollary:** the highest-risk site for a paraphrase is a `**Prevention:**` line, because it is
the part a future session actually executes.

## Second insight: a correction PR is where the corrected class recurs

The PR exists to delete a false prescriptive claim. My own correction commit then shipped five
more instances of the same family, every one in prose or verification rather than in the fix:

| What shipped | Why it is the same class |
|---|---|
| Append-only violated | I rewrote two dated records' bullet bodies — in the PR that ships the append-only rule. The house idiom, stated verbatim in the nearest precedent, is *"The bullet is left exactly as written."* |
| Flat prohibition, no LIVENESS carve-out | Contradicted `work/SKILL.md:1326` (notification as a required death check) and the shipped `monitor-supersede-guard.sh`, whose comment says that route *"WORKS, and is what the hook uses"* |
| One parenthetical, two mechanisms | A trailing command and a reaped run are independent routes to a false green. Stated as one, it invites "so if my string ends in the command that matters, the notification IS the verdict" — exactly wrong |
| `echo "RC=$?" >> log`, no placement rule | Appended to the END of the incident string it captures the `git log`'s status: the identical defect, written into the log the guidance says to trust |
| "enforced rather than filed" | `enforced` is a defined term (resolved from `[hook-enforced:]`/`[skill-enforced:]`); `grep -c notification AGENTS.rules.md` → **0**. The tier moved to *documented* |

Review the new **assertions** and new **prose** of a fix PR before its code.

## Third insight: a verbatim hunk from an issue is still a claim to measure

#7957 supplied replacement text and I applied it verbatim, as the plan required. The supplied text
says the exit code is "the LAST command in the backgrounded **string**". Measured:

```
$ bash -c 'false && true'; echo $?
1
```

`true` *is* the last command in the string. The correct form is the last command **executed**.
Shipping the imprecise version to honour verbatim-ness would have reproduced the PR's own defect
class, so the word was corrected and the deviation from AC1's literal text recorded rather than
quietly satisfied.

## Fourth insight: "per-site" was a non-sequitur

AC6 checks that four trailing-space code spans still render with their trailing space. I mutated
each of the four and each reddened only its own value, and concluded the check was "genuinely
per-site". It is not: `found` accumulates rendered spans from **anywhere in the file**, so
`want - found` cannot know which *line* supplied a member. Independent mutation of four values
proves the four VALUES are independent — not that any SITE is pinned. A review agent built three
working attacks:

1. **Relocate** — delete the real span's bullet, add a throwaway mention elsewhere → rc 0.
2. **Fence** — hide one in a fenced block; the regex is fence-unaware, and this file is a document
   *about* markdown idioms.
3. **Fifth span** — `want` is a hardcoded four-literal snapshot; a new deliberate span is unguarded.

The property-shaped form is per-LINE, keyed on the MD038 `disable-line` directives. Not committed;
recorded as an explicit gap in the plan.

## What the verification DID establish

`scripts/markdown-lint.sh` is **measurably vacuous** for this property, on all four spans:
mutating a trailing-space span leaves `1 file(s) clean` at rc 0 while the documented meaning
changes (`` `## ` `` is a heading prefix; `` `##` `` is not). Measured 4/4, control first, each
mutation proven landed by `diff`. The plan's CommonMark table also needed a fourth row, confirmed
against `markdown-it` rather than from memory:

| Source | Renders as | Trailing space? |
|---|---|---|
| `` `## ` `` (single backtick — what #7955 used) | `## ` | yes |
| `` `` ## `` `` (double, symmetric padding) | `##` | **no — the space is lost** |
| `` `` ##  `` `` (double, two trailing spaces) | `## ` | yes |
| `` ``## `` `` (double, trailing pad only) | `## ` | yes |

So a *source-form* check keyed on "does the content start with a space" would be right twice for
the wrong reason and wrong once. The rendered-form check gets all four right.

## Fifth insight: verifying the plan's residue refuted half of it

The plan listed four residue items to file against open PR #7879. Checked against that PR's head:

- **Item 1 understated.** Not six-of-seven: **every** `live_mark` sits at its arm's opening,
  including `T10-ac7-sweep` at line 871, which the plan claimed #7879 had moved to emission.
- **Item 2 holds.** `passes` is initialised at 61, incremented at 84, read only at 1187/1191 to
  render `RESULT:`. No floor compares against it.
- **Items 3 and 4 REFUTED.** `E2E_LOG` is scratch-scoped at 906 with T5c actively guarding against
  a CWD-relative read; the `else` branch skips all six live arms on **any** decline outcome.

Filing the list as written would have published two false claims about an open PR. #8008 carries
the corrected version *and records the refutations* so nobody re-files them.

## Instruments that were wrong before their output was read

Four, all in one session, each producing a confident-looking result:

- **A per-file `python3` spawn over 9,683 files** hit the 120 s ceiling — one process per file. One
  in-process pass finishes in seconds.
- **`git ls-files` quotes non-ASCII paths**, so the sweep crashed on an unrelated worktree's
  filename. `git ls-files -z` + NUL splitting is the fix.
- **#7879's branch head moved mid-review** (`fa6539a4` → `fcf3d2c8`). I caught it only because I
  re-read the SHA while writing a public correction. The blobs were byte-identical so every cited
  number held — but the citations were verified at one commit and published against another.
- **This learning file could not be written by a shell heredoc.** Its Session Errors section names
  a guarded command literal, and the guardrail matches the whole command line — so the heredoc
  body tripped the hook the file was documenting. That is the documented "a detector owns every
  file that mentions its literal" class, hit while writing it up. Written with the file tool.

## Session Errors

1. **AC3 swept by literal where the property is a claim.** Recovery: property-shaped sweep;
   superseded note appended to the missed site. **Prevention:** for any correction sweep, write the
   claim as a sentence and grep its paraphrases; treat `**Prevention:**` lines as the highest-risk
   position. Applied to `work/SKILL.md` in this PR.
2. **Append-only violated in the PR that ships the rule.** Recovery: originals restored
   byte-identical to `main` (verified by `diff`), correction appended beneath. **Prevention:** the
   house idiom is "the bullet is left exactly as written" — grep the nearest existing `Superseded`
   note for the form before editing a dated record.
3. **LIVENESS carve-out dropped from the skill.** Recovery: clause restored. **Prevention:** when
   porting a correction from a learning into a skill, diff the two texts — the clause that gets
   dropped is the one that makes the rest self-consistent.
4. **Two mechanisms stated as one parenthetical.** Recovery: split into (i) and (ii).
   **Prevention:** if a claim cites two examples, check they share a mechanism.
5. **`echo "RC=$?"` shipped with no placement rule.** Recovery: added "immediately after the
   command whose status matters, before any convenience line". **Prevention:** a positive
   instruction needs a WHERE whenever `$?` is involved.
6. **"enforced" overstated.** Recovery: reworded to *documented*, residue recorded.
   **Prevention:** `enforced` is resolved from enforcement tags — grep `AGENTS.rules.md` before
   claiming a tier.
7. **AC6 mislabelled per-site.** Recovery: claim retracted in place, three attacks recorded.
   **Prevention:** for any "for all x" check, ask what SET it quantifies over and whether the
   assertion can name the member that supplied a hit.
8. **Verbatim issue hunk was imprecise.** Recovery: corrected to "last command executed", swept
   across five sites. **Prevention:** a supplied remedy is a claim to measure even when quoting it
   verbatim is the instruction.
9. **Provenance split (#7912 vs #7957) across three files.** Recovery: normalised to
   "#7912 (filed as #7957)". **Prevention:** distinguish the PR that MEASURED from the issue that
   TRACKS when citing.
10. **A process-matching kill used a self-matching pattern.** Recovery: the guardrail hook denied
    it; used the harness's task-stop tool instead. **Prevention:** already hook-enforced.
11. **Stray `git stash list` in a compound command.** Recovery: guardrail denied it; command rerun
    without. **Prevention:** already hook-enforced.
12. **Per-file process spawn over the whole corpus timed out.** Recovery: single in-process pass.
    **Prevention:** never spawn per file across a 9k-file corpus.
13. **Sweep crashed on a git-quoted non-ASCII path.** Recovery: `git ls-files -z`.
    **Prevention:** use `-z` for any `ls-files` loop.
14. **Published a SHA the verification had not used.** Recovery: blob-identity check proved the
    citations held. **Prevention:** capture the SHA at verification time, not at write-up time.
15. **Two stop-hook fires on forward-looking closing text.** Recovery: acted in-turn.
    **Prevention:** already hook-enforced.
16. **Framed #7879 as "someone else's PR" without checking.** Recovery: `gh pr view --json author`
    showed it is ours. **Prevention:** check authorship before reasoning about third-party harm.
17. **27 `gdpr-gate-staleness` denies observed** (prefixes 95–999 days). Not attributable to this
    diff; already tracked by #7255. **Prevention:** n/a — pre-existing and tracked.
18. **This learning file tripped the guardrail it documents.** Recovery: written with the file tool
    rather than a shell heredoc. **Prevention:** when a write's CONTENT names a guarded literal,
    use a non-shell writer — the hook reads the command line, not the intent.

Forwarded from `session-state.md`: four planning premise failures (the #7956 no-op fix, the
inverted mechanism, #7957 §2 already resolved by #7955, and the planner's own first-draft
relaxation that would have made a broken `discover_claude_pid` report GREEN).

## Tags

category: workflow-patterns
module: work-skill, review-skill, knowledge-base
