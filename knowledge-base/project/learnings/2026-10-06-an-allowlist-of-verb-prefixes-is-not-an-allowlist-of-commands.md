# Learning: an allowlist of verb prefixes is not an allowlist of commands (#7122)

## Problem

Issue #7122 asked for an output allowlist between a model reading attacker-authorable community text and
public publication surfaces. The first design closed the publish verbs, removed file tools and rendered
the digest and issue handler-side from a closed zod schema. Review then found the containment itself had a
window narrower than its property:

- The hook matched an allowlisted verb **prefix**, and its metacharacter screen stripped single-quoted
  spans, so the trailing arguments of an allowed router verb were never inspected. Two platform scripts
  put them straight into `python3 -c` source and bash arithmetic (`(( limit ))`). One allowed command gave
  arbitrary code execution with the spawn environment.
- The handler ran git in a workspace the agent had written to: planted `.git` state (clean filters,
  `refs/replace`, `commondir`, a second `remote.origin.url`) ran in the handler's own steps with the
  write token.
- Prose in the fix asserted things no command had measured: a single "Last 1 day" window for collectors
  that look back 1 day, 7 days, "latest 50" or "totals".

## Solution

- Make the allowlist **exact literals**: each `;`/`&&` segment must equal one allowlist line token for
  token, with a single `<uint>` placeholder. No trailing argument exists to inspect.
- Keep the charset check as a second layer and validate operands in the scripts (leading zeros rejected:
  `08` was an octal arithmetic error that exited 0 with `[]`). Pass free text to interpreters through argv.
- Treat the agent's workspace as untrusted in the handler: sanitise `.git`, require HEAD to be the fetched
  origin tip, refuse symlinked git entries, require exactly one origin URL, stage via `hash-object
  --no-filters`, verify the staged blob byte for byte against the rendered bytes.
- State collection windows as a fixed constant per platform instead of one label.

## Key Insight

A guard that matches a prefix guards the prefix. When the property is "the agent cannot make this program
do anything but X", enumerate what the allowed command *accepts* (arguments, interpolation sinks, state it
reads) and pin the whole command. Then ask the same of every claim the fix's prose adds: name the command
that falsifies it and run it (the window claim fell to reading five scripts).

## Session Errors

1. **Allowlist matched a verb prefix; trailing arguments reached interpreter source (P1).** Recovery: exact
   literals plus script operand validation. **Prevention:** for a command allowlist, assert the full
   command shape, never a prefix (review skill bullet on parser-consumer seams already covers the class).
2. **Handler git steps trusted agent-touched `.git` state (P1 defence in depth).** Recovery: sanitiser,
   origin-tip check, byte comparison. **Prevention:** any handler step that runs git in a directory an
   agent wrote to must start from a known-good shape, not from subtraction.
3. **"Last 1 day" window asserted for collectors with 1-day, 7-day, latest-N and snapshot semantics.**
   Recovery: fixed per-platform window note. **Prevention:** read each collector script before writing a
   claim about what it measures.
4. **A fix agent died on a weekly rate limit mid-slice (429), leaving partial edits and three failing tests
   (a fixture cloned an unborn default branch, a test asserted a filter did not run where git's racy-clean
   index write still executes it, a stale error-message regex).** Recovery: reconciled `git status`, ran
   the whole suite, fixed the three in place. **Prevention:** after any agent failure, run the broad
   suite and read `git status` before re-dispatching (already in the review skill).
5. **A test-design verification seat was cut off by a session restart with its results on disk.**
   Recovery: read the per-mutation result files directly and acted on the survivors (rename gate,
   required `expectedContent`, symlink entries, case-sensitive literals). **Prevention:** have mutation
   seats write per-row results incrementally (they did; that is why this recovered).
6. **Stop-hook "unkept promise" blocks on closing text that named a next step.** One-off: answered with
   an explicit BLOCKED stop while background seats ran.
7. **Hook-blocked `pgrep -f` and chained `sleep` waits.** One-off: used `proc.sh` ownership helpers and a
   Monitor until-loop.
