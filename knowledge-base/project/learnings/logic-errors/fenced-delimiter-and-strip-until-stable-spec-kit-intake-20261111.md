---
module: spec-kit-intake
date: 2026-11-11
problem_type: logic_error
component: tooling
symptoms:
  - "A --- line inside an open fence was treated as a frontmatter delimiter, so one real delimiter spliced the fence and a fenced user story became a requirement."
  - "One pass of the control strip left a line break when a C0 or DEL byte sat inside U+0085, U+2028, or U+2029."
  - "Dropping a dot component and then walking .. left the pin, even when the path still ended in specs/<leaf>."
root_cause: logic_error
resolution_type: code_fix
severity: high
status: open
tags: [spec-kit-intake, frontmatter, fence, control-strip, containment]
---

# Troubleshooting: A fenced delimiter and a one-pass control strip both forged the intake receipt

## Problem

`plugins/soleur/scripts/spec-kit-intake.sh` projects a read-only Spec Kit directory into a Soleur spec on the same stdout stream as the receipt. Two parser bugs on that stream turned non-requirements into requirements, and a path walk treated `..` as ordinary after `.` was dropped.

## Environment

- Module: spec-kit-intake
- Affected Component: `plugins/soleur/scripts/spec-kit-intake.sh` and `plugins/soleur/skills/plan/references/spec-kit-intake.md`
- Date: 2026-11-11
- Lane: cross-domain. Brand-survival threshold: single-user incident.
- Issue: #12531. PR: #12653.

## Symptoms

- A file whose only real frontmatter pair sat outside a fence lost its Success Criteria into a functional requirement, because a `---` inside the fence closed the pair early.
- A heading that contained a split UTF-8 line-separator still broke `splitlines` after one strip pass.
- `specs/./../specs/001-demo` still ended in `specs/001-demo` after `.` was dropped, and walking `..` would have left the directory pin.

## What Didn't Work

**Attempted Solution 1:** Strip C0 (except tab and LF), DEL, U+0085, U+2028, and U+2029 once, then decode.

- **Why it failed:** A C0 or DEL byte inside the UTF-8 sequence of U+0085, U+2028, or U+2029 survives the first pass and reassembles the separator. The parent one-pass strip fails the `split breaks stripped` pin.

**Attempted Solution 2:** Treat every `---` line with only trailing spaces or tabs as a delimiter, including inside a fence.

- **Why it failed:** The heading loop already ignored fences. The delimiter scan did not. One real delimiter then spliced the fence, and a fenced P1 user story became a requirement. Commit `b4e643a239` introduced that hole. Commit `fef4e488` closed it.

**Attempted Solution 3:** Pin `..` on `specs/./../001-demo`.

- **Why it failed:** After `.` is dropped, `parts[-2]` is not `specs`, so the shape check already refuses that path. The pin does not prove the `..` guard. The load-bearing path is `specs/./../specs/001-demo`.

## Session Errors

**Prior-session research seats reported tool-error counts and still exited 0.** CPO 1, CLO 2, CTO 1, repo-research 1, learnings 5. Each returned a usable assessment.

- **Recovery:** Accepted the exit-0 assessments. Did not resume the seats.
- **Prevention:** Read the final status, not a mid-run error count. An exit 0 with a usable report is a recovered one-off, not a failed seat.

**Continuation research seats each logged Errors: 1 while waiting.** functional-discovery, repo-research, and learnings. All three exited 0.

- **Recovery:** Waited for exit 0. Did not respawn them.
- **Prevention:** Do not kill or resume a seat because a wait snapshot shows Errors: 1 while it is still running.

**collision-precheck exited 10, and foreign test-all PIDs were already holding the shared lock.** The exit was not a duplicate of #12531.

- **Recovery:** Treated the precheck as a false collision. Left the foreign PIDs alone.
- **Prevention:** Confirm a collision against the issue number before stopping. Do not `pkill` another worktree's test-all.

**The Kieran plan-review wait logged Errors: 1 and the seat still exited 0.**

- **Recovery:** Used the exit-0 report.
- **Prevention:** Same as the research seats: the wait line is not the verdict.

**The main review panel logged tool-error counts while seats were still running.** The seats exited 0 with usable reports. Performance and semgrep showed no tool errors. The structural seat logged Errors: 0.

- **Recovery:** Waited out the panel. Did not start a replacement round.
- **Prevention:** Disposition findings from the written report after exit 0, not from the in-progress error counter.

**The coverage consult `01a1cc66-6da7-79a2-b07d-9e5aae02c34a` exited 0 with Errors: 0.** Listed so this inventory matches the handoff. It was not a fault.

- **Recovery:** None needed. The consult class was verified in `emit`.
- **Prevention:** Do not record a zero-error consult as a failure. Keep it in the inventory when the handoff names it, and say the count was zero.

**Fix-round 1 seats each logged Errors: 1 while running.** Simplicity logged 2. All exited 0.

- **Recovery:** Read the reports. The planned fixes landed in `d4d557fe9c`.
- **Prevention:** Cap the round. Do not spawn a third seat because a mid-run counter moved.

**Round-2 seats logged Errors: 1 while running.** Security, code-quality, and the wait status each showed 1. Pattern, test-design, agent-native, and security exited 0. Code-quality exited 0 last. Structural Errors: 0.

- **Recovery:** The new P2 (a `---` inside an open fence matched `is_delim`) was fixed in `fef4e488` after the seat returned. A mid-run status check showed the worktree still clean.
- **Prevention:** If a review seat calls an editor, confirm `git status --porcelain` before writing the follow-up, and attribute the fix to the commit that contains the guard.

**The verifier `01a1ccb6-8ff4-7262-8c7f-e3ed906f8708` exited 0.** About 833 seconds, 29 tool calls. No new tool-error count was reported in its final status.

- **Recovery:** None. Strip class closed. Frontmatter pair class, including a fenced `---`, closed. No new parser defect.
- **Prevention:** One verifier after two targeted rounds. Do not open a third seat round when that verifier exits 0.

## Solution

Repeat the byte strip until a pass removes nothing, then drop any remaining U+0085, U+2028, or U+2029. A delimiter is `---` plus only trailing space or tab, and only while no fence is open. Skip only the first closed pair, wherever it starts. An unclosed opener does not consume later headings. Drop `.` before the specs/leaf check and still refuse `..` before any open. The receipt and the projected body share stdout, so a projected line that equals a marker, or that matches a receipt key, refuses the whole intake.

The fence-aware scan:

```python
def parse_sections(text):
    if text.startswith("\ufeff"):
        text = text[1:]
    lines = text.split("\n")
    opener = None
    closer = None
    fence = None
    for idx, line in enumerate(lines):
        if fence is not None:
            if fence_closer(line, fence[0], fence[1]):
                fence = None
            continue
        opened = fence_marks(line)
        if opened is not None:
            fence = (opened[0], opened[1])
            continue
        if not is_delim(line):
            continue
        if opener is None:
            opener = idx
            continue
        closer = idx
        break
    if opener is not None and closer is not None:
        lines = lines[:opener] + lines[closer + 1 :]
```

`is_delim` stays `line.startswith("---") and line[3:].strip(" \t") == ""`. `parts_of` drops `.`, then refuses any `..`, then requires `specs/<leaf>`.

Product bytes: `fef4e488`. Suite at that tree: `spec-kit-intake: 107 passed`. Shellcheck: `SOLEUR_REVIEW_SCAN_GATE ok engine=shellcheck files=2 rules=0 findings=0`.

## Why This Works

The heading loop and the delimiter scan have to share one fence rule. A `---` inside a fence is text, so it cannot open or close frontmatter. The first closed pair out of a fence is the only pair that is dropped. Later pairs stay ordinary text.

The strip loop is bounded by a strictly shrinking length. A non-shrinking change refuses `intake: unreadable`. The translate backstop still drops U+0085, U+2028, and U+2029 after decode. The hash is sha256 of the raw accepted bytes, before the strip. The cap is `st_size` before the read.

`..` never reaches `open`, because `openat("..")` would leave the directory pin. `.` is not an escape. A symlink, including one in the same directory, is `intake: symlink-escape` via `O_NOFOLLOW`, not via `lstat` then open.

## Prevention

- Keep the delimiter scan on the same fence rules as the heading loop. A new frontmatter rule that does not consult `fence_marks` will splice a fenced story into a requirement again.
- Pin `..` on a path that still ends in `specs/<leaf>` after `.` is dropped. `specs/./../001-demo` is refused by the shape check alone.
- Do not call the translate backstop dead. Removing only the loop or only the translate stays green on the current fixture. Both stay.
- The projected body is on the receipt's stdout. After `project`, refuse a line that is a marker or a receipt key.
- State the ASCII user-story boundary. An underscore or a non-ASCII letter is outside `[A-Za-z0-9]`. Do not widen it to `\b`.
- Skill needles must occur in the raw file and after HTML-comment stripping. A comment-only second copy can satisfy the two checks on different copies. That residual is stated in the test header. Do not rewrite `need()` in a drive-by.

## Related Issues

- See also: [exported containment primitives must self-validate](../security-issues/2026-10-27-exported-containment-primitives-must-self-validate.md) — `O_NOFOLLOW` on the final component is not a walk from `/`.
- See also: [lstat-then-open reopens the TOCTOU](../2026-04-17-kb-share-mcp-parity-lstat-toctou-and-mock-cascade.md) — this intake does not `lstat` before `open`.
- Similar to: [open once, fstat, then read](../2026-10-27-a-red-codeql-check-on-my-own-pr-was-the-real-finding-and-i-called-it-unrelated.md).

## Key Insight

A receipt that shares stdout with the document it describes has to parse that document with the same fence and line-break rules the tests pin, or the document can forge the receipt.

## Tags

category: logic-errors
module: spec-kit-intake
