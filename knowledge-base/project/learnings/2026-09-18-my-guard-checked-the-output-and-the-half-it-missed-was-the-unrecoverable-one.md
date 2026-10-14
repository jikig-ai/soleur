---
title: "My guard checked the output, and the half it missed was the unrecoverable one"
date: 2026-09-18
category: logic-errors
module: plugins/soleur/lib/harness-parity.ts
issue: 8299
pr: 8300
tags: [guard-design, mutation-testing, remediation-tooling, instrument-verification, fixture-direction]
---

# Learning: a guard that judges its own OUTPUT is blind to exactly the damage that cannot be undone

## Problem

PR #8300 built a gate proving every component reference in plugin docs is canonical
(`soleur:<name>`), plus a `--fix` remediation tool, and used it to rewrite 1029 sites across
62 docs.

An early review round found `--fix` turning `~/plan` into `~soleur:plan` — destroying a
filesystem path and converging on a state the classifier calls NONCANONICAL forever. I fixed it
two ways: `~` joined the path class, and `fixDoc` gained a post-condition refusing any rewrite
whose result would not re-classify CANONICAL. I wrote in the code that this was **"the general
guard for that class"**, added a fixture (`fix-refuses-unsound.md` — `!/plan`, `%/plan`,
`~/ship`), and moved on.

Four review agents later converged on the same finding: `--fix` had **already destroyed four
real bytes**, and the guard could not see any of them.

```text
plugins/soleur/skills/rclone/SKILL.md:33
-  cp "$d"/rclone-*/rclone ~/.local/bin/
+  cp "$d/rclone-"*soleur:rclone ~/.local/bin/
```

That is the documented rclone install one-liner an agent executes verbatim. The glob matched
nothing, `cp` failed, the `&&` chain aborted, and rclone was never installed — while the skill's
later steps assumed it was.

## Root cause

The post-condition re-classified the **rewritten token** and bailed unless the result was
CANONICAL. `fixDoc` splices at `s - 1`, consuming the character before the token — so the test
that matters is whether *that consumed character was a sigil*, which the post-condition never
asked.

The two halves of the class are not symmetric:

| consumed byte left behind | residue classifies | guard fires? | recoverable? |
|---|---|---|---|
| a non-boundary char (`~`, `!`, `%`) | NONCANONICAL | **yes** | yes — it stays RED |
| a boundary char (`` ` ``, `"`, `*`, `)`) | **CANONICAL** | **no** | **no** — census reports clean forever |

So the guard covered the **self-repairing** half and was blind to the **unrecoverable** half.
Every fixture I wrote sat on the covered side, which is why 153 tests were green over a dead
install command.

## Solution

The discrimination is real but belongs in the **classifier**, not the fixer: a slash after a
delimiter that CLOSES a span is a path separator; inside an OPEN delimiter the same slash is the
grok sigil. Parity over the line prefix is the only available discriminator.

```ts
export function closesSpan(prev2: string, linePrefix: string): boolean {
  if (prev2 === "*" || prev2 === ")" || prev2 === "]" || prev2 === "}") return true;
  if (prev2 !== "`" && prev2 !== '"' && prev2 !== "'") return false;
  return (linePrefix.split(prev2).length - 1) % 2 === 1;   // odd => the delimiter closes
}
```

Placed beside `PATH_PREV` and consumed by `pathctx`, so a path is never *reported* as a site —
which means there is nothing for `--fix` to rewrite and the two cannot disagree. One predicate,
shared.

Verified in both directions, because a widening that swallows real grok slashes would be a
silent narrowing:

```text
kept     cp "$d"/rclone-*/rclone      rewrote  Run `/plan` now
kept     the `lastSeen`/deploy        rewrote  Run /plan now
kept     "$(id -u)/agent-browser/"    rewrote  (/plan) here
```

Four mutations of `closesSpan` — delete it, invert it, drop the parity, drop the glob arm — are
each KILLED.

## Key Insight

**A guard that validates its own OUTPUT can only catch the failures that stay visible. Ask
instead what the operation CONSUMED.**

The generalisation: for any transform that destroys input (a splice, a truncation, a merge, an
in-place migration), the post-condition must test a property of the *thing removed*, not of the
*thing produced*. Output-shaped checks partition the failure space by visibility, and visibility
is inversely correlated with severity — a bad output that still looks wrong is the recoverable
case.

Two corollaries that cost the most time here:

- **Fixture DIRECTION is a coverage axis, and a green mutation battery cannot see a gap in it.**
  Every mutation perturbs the implementation and is scored through the same fixtures; if all
  fixtures sit on one side of a discriminator, no row can reach the other. My 24-row matrix was
  19/19 KILLED throughout.
- **The comment claiming a control is general is itself review surface.** "The general guard for
  that class" was written in the same commit that shipped three instances of the class. A claim
  about a control's coverage needs the same treatment as a measurement: name the input it does
  NOT cover, or do not make the claim.

## Prevention

- For any destructive transform, write the post-condition over the **consumed** operand. Litmus:
  *name an input where this rewrite is wrong but the output still looks right.* If you can, the
  guard is output-shaped.
- Sweep fixtures by **direction** before trusting a battery: for each discriminator, name the
  mutation that makes it too permissive AND the one that makes it too aggressive, and say which
  fixture reds for each.
- When a review finds one instance of a destructive class, **sweep for the class** before fixing
  the instance. I fixed `~/plan` and shipped four more; the sweep took one script.

## Session Errors

1. **`--fix` destroyed four real bytes, and my guard for that exact class could not see them.**
   Recovery: reverted all four from `origin/main`, moved the discrimination into the classifier
   as `closesSpan`, added fixtures for both directions, mutation-proved it 4/4.
   **Prevention:** post-conditions on destructive transforms test the consumed operand, never
   only the produced one (above).

2. **My damage-detector returned `0` and read as a clean result.** It looked for a non-boundary
   character before `soleur:` — but the consumed `/` leaves the *previous* char adjacent, which
   is usually a boundary char. Caught only because rclone was a known positive and the instrument
   failed to report it.
   **Prevention:** run every detector against a case whose answer you already know, BEFORE
   reading its verdict. An instrument never shown to produce a positive has not returned a
   negative — it has returned silence.

3. **A literal `*/` inside a JSDoc block comment closed it early** (writing `*/rclone` in prose).
   Four cascading parse errors pointing at unrelated lines.
   **Prevention:** already `work/SKILL.md` ("Never write a literal `*/` inside a block comment").
   Obeyed after the fact, not before — the rule is present and was not consulted while writing a
   comment *about* globs.

4. **Widening `PATH_PREV` silently disarmed mutation row N5b**, which anchors its mutation on
   that exact literal. The battery reported `ROWS=18` instead of 19.
   **Prevention:** the battery's md5 landing assertion is what caught it — a mutation that does
   not land reports the BASELINE, indistinguishable from a pass. After editing any constant, grep
   the battery for that literal. Anchors now assert `s.count(a) == 1`.

5. **A PreToolUse hook denial rejected the ENTIRE Bash call**, so a `gh pr edit` chained ahead of
   `gh pr ready` never ran. I then read a stale PR body twice and concluded the override marker
   "didn't register".
   **Prevention:** already `work/SKILL.md`. The tell I missed: when a write appears not to have
   landed, check whether it was in the same call as a denied command before re-running it.

6. **A stale committed eval projection made a required-context suite RED** — my go.md edits
   landed inside an `eval-gate` region without regenerating `prompts/go-skill.txt`.
   **Prevention:** a repo-global ratchet references none of the files you changed, so no
   file-selected suite set can reach it. When a diff touches a doc carrying an `eval-gate:block:`
   or similar marker, regenerate its projection in the same commit.

7. **Three per-harness entry-point shims were canonicalised into falsehood** —
   `skills/{go,help,sync}` each say "You are the `/soleur:<name>` slash command for the Soleur
   plugin on Devin CLI", and the rewrite made each one's self-description a form its harness does
   not have. The `EXCLUDED_BY_PATH` list already carved out `commands/help.md` on exactly this
   basis and was one category short of its own stated principle.
   **Prevention:** when a rule carries an exclusion list, enumerate the CLASS the exclusion names
   and check every member, not just the instance that prompted it.

8. **Three acceptance criteria were ticked against checks that did not hold.** AC1 asked for a
   figure to be re-derived against `origin/main`, which made it unsatisfiable the moment a sibling
   merged; AC5's matrix was missing 5 of 24 rows; task 2.7 claimed a set "diffs empty" that went
   20 → 78.
   **Prevention:** already `work/SKILL.md` (an acceptance checkbox is a CLAIM). Each was amended
   explicitly rather than quietly satisfied by a looser variant.

9. **Blocked a `sleep 45 && gh pr checks` chain** — the harness requires `Monitor` with an
   until-loop for waits. One-off; obeyed.

## Tags

category: logic-errors
module: plugins/soleur/lib/harness-parity.ts
