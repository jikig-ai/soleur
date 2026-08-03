# ADR-156 — Hook stdin is model-controlled and untrusted

- **Status:** Accepted
- **Date:** 2026-08-02
- **PR:** #7168
- **Issue:** #7164 (`eval` over `jq @sh` in 10 PreToolUse hooks executes attacker-named commands)
- **Related:** [ADR-157](./ADR-157-a-hook-that-cannot-parse-its-input-asks.md) (the response posture
  this boundary implies), `.claude/hooks/lib/hook-input.sh` (the mechanism),
  `.claude/hooks/security_reminder_hook.py` (the pre-existing Python precedent this converges on),
  `knowledge-base/engineering/architecture/diagrams/model.c4` (the `claude -> hooks` edge that
  encodes this boundary),
  [ADR-165](./ADR-165-what-ask-means-on-a-harness-with-no-ask-state.md) (extends this boundary to
  the `.openhands/` mirror, whose protocol has no `ask` state)

> **Ordinal.** Renumbered 155 -> 156 at `/ship` time: a sibling PR landed its own ADR-155
> (cross-gate exemption markers) on `origin/main` during this pipeline, and `adr-ordinals` is not a
> required check, so the collision would have surfaced as red CI on `main` post-squash.

## Context

Every `PreToolUse` hook receives a JSON envelope on stdin describing the tool call it is being asked
to adjudicate. That envelope is assembled from the model's own tool-call output. It is not operator
input, it is not harness-internal state, and it is not validated by anything the hook can see.

Ten hooks parsed it with one line:

```
eval "$(echo "$INPUT" | jq -r '@sh "COMMAND=\(.tool_input.command // "")"' ...)"
```

The reasoning recorded in those hooks' own comments was that `@sh` shell-escapes each field, so
`eval` is safe. That is true for a **string**. `jq @sh` shell-quotes each element of an **array** as
a separate word, so a `tool_input.command` of `["x","touch","/tmp/PWNED"]` renders as
`COMMAND='x' 'touch' '/tmp/PWNED'` — an assignment followed by a **command**, executed by `eval`
before the permission prompt, with the operator's full privileges. Reproduced against all ten hooks,
four times independently.

The narrower and more durable observation is that the safety argument depended on a property of the
input (`.tool_input.command` is a string) that the hook asserted but never checked, and that nothing
inside this repository can establish. Whether the harness type-validates `tool_input` before
dispatching `PreToolUse` could not be determined from here. `PreToolUse` also receives MCP and other
tool shapes, whose envelopes this repo does not define.

The type confusion is also, separately, a **guard evasion** — and it survives fixing the `eval`.
Eight further hooks read `.tool_input.command` via `$( )` and never call `eval`; they are not
vulnerable to code execution and are still defeated by the same payload, because `jq -r`
pretty-prints an array across lines and no anchored guard regex matches the result. Measured:
`["git","stash"]` matches neither the stash guard nor the commit-to-main guard.

## Decision

**Hook stdin is model-controlled and untrusted. A hook must not depend on an invariant of that input
which it cannot itself verify.**

Three consequences bind:

1. **No shell evaluation of hook input, ever.** Not `eval`, in any spelling. The value of a field
   may be read, matched, and compared; it may never be executed, and it may never be interpolated
   into a program text that is then executed.
2. **A contracted field's type is checked, not assumed.** A hook that expects a string must
   establish that it received a string. Absence and empty are legitimate; a different JSON type is
   not.
3. **Normalization is not a substitute for verification.** Coercing a non-string into a string
   (`tojson`), scrubbing a byte out of it, case-folding it, or transliterating it does not restore
   the invariant — it produces a *different* value that the downstream matcher was never written
   against. Both remedies of this shape were tried while fixing #7164 and both were falsified by
   running the real guard regex against the normalized value.

This ADR governs the **boundary**. It deliberately says nothing about the mechanism that enforces it
(the shared helper, the field set, the separator, the lint) or about what a hook should do when the
check fails — those are [ADR-157](./ADR-157-a-hook-that-cannot-parse-its-input-asks.md) and the
hooks README. The split is intentional: a future refactor of the helper must not be able to
supersede the trust boundary along with it.

**This ADR must never be superseded.** It may be extended.

## Scope

Binding for every hook that reads the tool-call envelope and can affect whether a tool call proceeds:
the `Bash`-matcher hooks and the blocking write guards (20 files across `.claude/hooks/`, plus the
two `.openhands/hooks/` mirrors). Advisory and `PostToolUse` hooks that gate nothing are exempt from
the *mechanism*, never from clause 1 — they are enumerated with their reason in
`.claude/hooks/README.md`.

`security_reminder_hook.py` already complied before this ADR existed: it uses `json.loads` and an
explicit `isinstance(new_string, str)` check. It is the precedent the bash hooks converge on, not an
exception to it.

## Consequences

- A previously-invisible class of change becomes reviewable: any hook reading the envelope without a
  type assertion is now a defect against a written boundary, not a matter of taste.
- The `eval` idiom is banned mechanically rather than by prose. Prose did not stop it: the idiom was
  copied into nine hooks across four months, each time carrying the comment asserting it was safe.
- Hooks gain a dependency on a shared helper. The status quo it replaces is twenty byte-identical
  copies of the same defect, so this centralizes a failure mode that was already centralized in
  everything but name.
- Four in-source comments and one learning file asserted the `@sh` safety property. They are
  corrected rather than deleted; the historical finding stays legible, with a dated correction.
