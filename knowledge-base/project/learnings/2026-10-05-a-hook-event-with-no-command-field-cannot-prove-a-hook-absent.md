# Learning: a hook event with no command field cannot prove a hook absent, and a "nothing printed" filter proves nothing

## Problem

ADR-271's acceptance check asked whether the removed `browser-cleanup` `Stop` hook still ran, using a headless
`claude -p --include-hook-events` process kept alive across three turns. The recipe said to pass when "no `Stop` hook event
names `browser-cleanup`" and when a transcript `attachment` filter printed 0. The first run passed on both, and four review
seats then showed neither could have failed:

- A stream `Stop` event (`hook_started` / `hook_response`) carries no `command` field, so "no event names X" is vacuous.
- The `attachment` filter sees only hooks that printed. The removed hook prints only when it killed something, and the child
  transcript had no `Stop` attachment at all, so the filter printed 0 whether or not the hook had loaded.
- "Equal to the kill-text filter" was false: 169 rows against 155 once the stderr clause was added, the difference being
  `hook_non_blocking_error` rows (exit 127, script missing) from a session whose registry still named the removed script.
- Nothing showed a Chrome was alive at any `Stop`, and `about:blank` after an idle gap cannot tell a surviving browser from a
  relaunched one.

## Solution

Use evidence that can show the bad state:

1. The transcript's `stop_hook_summary` records list every `Stop` hook that ran, silent ones included
   (`jq -c 'select(.subtype=="stop_hook_summary")|{hookCount,cmds:[.hookInfos[].command]}'`). Assert none names
   `browser-cleanup` and that `hookCount` equals the `Stop` commands the loaded `hooks.json` registers.
2. Navigate to a `data:` page with a unique title in turn 1; every later snapshot must return it (a relaunch reports
   `about:blank`).
3. Sample one Chrome main process pid under the child with `pstree -p <claude pid>`; it must predate the first `Stop` and be
   present after the last.
4. Run the child with the interactive session's own browser closed: the plugin registration has no lease, so an open browser
   in the launching session fails the child with "Browser is already in use".

## Key Insight

Before crediting an acceptance filter, ask what it prints when the thing it guards is present and silent. A guard whose input
channel cannot express the failure (an event with no `command`, an attachment that exists only for hooks that printed) is
satisfied by the broken state exactly as it is by the fixed one, and a "survived" claim needs a witness that distinguishes the
same object from a replacement.

## Session Errors

1. **First headless run was INCONCLUSIVE** (my own open browser held the plugin profile; the project registration needs real
   Chrome and the host has none). — Recovery: closed my browser, ran the plugin registration only. — **Prevention:** the
   ADR-271 recipe now states both limits; close the launching session's browser before starting a child.
2. **Driver `results()` printed `0` twice** (`grep -c` prints 0 and exits 1, so `|| echo 0` appended a second line). —
   Recovery: `n=$(grep -c …); echo "${n:-0}"`. — **Prevention:** never pair `grep -c` with `|| echo 0`.
3. **`pgrep -f` and `ps | awk '/pattern/'` were blocked by the PreToolUse self-match hook, twice**, the second time because my
   own heredoc text quoted `pgrep -f`. — Recovery: stopped tasks by id and captured pid; wrote prose that names the phrase
   with the Write tool, which the hook does not scan. — **Prevention:** already hook-enforced; keep hook-trigger strings out of
   Bash command text.
4. **Probe misparsed `/proc/<pid>/stat`** (field 4 shifts when comm contains spaces, e.g. `npm exec @playw`), so the in-driver
   probe printed NONE for a live Chrome. — Recovery: a separate `pstree` sampler. — **Prevention:** strip the `( … )` comm
   before indexing stat fields, or use `pstree`/`ps -o ppid=`.
5. **Idle gaps stated as 76 s and 27 s**, then recomputed from transcript timestamps as 80 s and 26 s. — **Prevention:** state
   an interval as the two logged events that bound it, computed from the transcript, never from the driver's `sleep` values.
6. **First-run evidence overclaimed** (survival inferred, step-3 filter vacuous, "equal" claim false). — Recovery: second
   run with marker page, pid sampler and `stop_hook_summary`; ADR rewritten. — **Prevention:** a positive control or a
   witness that distinguishes the states for every acceptance filter.

## Tags

category: test-failures
module: agent-browser, hooks, ADR-271
