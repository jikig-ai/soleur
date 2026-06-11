# Upstream Pencil bug report — `open_document` truncates non-empty `.pen` and returns success

**Target channel:** https://github.com/highagency/pencil-desktop-releases (issues enabled; MCP-bug precedent #14, #15, #17, #20, #21)
**Soleur tracking issue:** #4859 (deferred upstream non-goal from #3274)
**Filing status:** Filed 2026-06-11 → https://github.com/highagency/pencil-desktop-releases/issues/22 (operator-confirmed). Satisfies #4859 re-evaluation criterion (a).

---

## Title

Bug: `open_document` overwrites a non-empty tracked `.pen` with empty document state and returns success

## Body

### Summary

The `open_document` MCP tool can silently overwrite a non-empty `.pen` file on disk with empty document state (`{"version":"...","children":[]}`) while returning a success string (`Opened ...`). No error is surfaced (`isError` is not set), and a follow-up `get_editor_state` confirms the in-memory state is already empty. All node data is lost, and because the success return looks normal, the loss is invisible until someone inspects the file size.

### Reproduction

1. Create a complete document and `save` it — e.g. a 130 KB `.pen` with multiple frames/children.
2. In a separate MCP session, call `open_document` on that same path.
3. `open_document` returns a success string.
4. Inspect the file on disk: it is now ~41 bytes (`{"version":"2.11","children":[]}`); the timestamp matches the open call. All node data is gone.

Observed at least twice on committed, non-empty files (a 133 KB design, and later a navigation rail `.pen` zeroed twice in one session).

### Expected behavior

`open_document` MUST NOT overwrite a non-empty `.pen` with empty document state. On a parse/read failure it should:

- return `isError: true` with a descriptive message, and
- leave the on-disk source file **untouched** (never truncate it).

A legitimate "opened an empty document" result should only ever write empty state to disk if the source was already empty.

### Impact

- Irreversible data loss of user-authored design files between iteration cycles.
- The success return hides the failure, so automated/agent-driven workflows that follow the documented "open the existing `.pen` and iterate" pattern destroy work without any error signal.

### Environment

- Pencil MCP server (`@pencil.dev/cli` headless adapter / MCP bridge).
- Driven via Claude Code MCP client; `open_document` called with a `filePath` argument.

### Workaround in place downstream (not a fix)

We added a deterministic PostToolUse recovery hook that restores the file from version control (`git HEAD`) when it detects the collapse, plus a PreToolUse guard that refuses to open untracked `.pen` (no recovery anchor). These mitigate data loss for tracked files only — they cannot prevent the truncation itself, which is why this upstream fix is needed.
