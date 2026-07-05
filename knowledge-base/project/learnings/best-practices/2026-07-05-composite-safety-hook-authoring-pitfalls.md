---
title: "Composite safety-hook authoring — decouple critical guards from optional sources; lexical guards need self-expansion + literal-token tests"
date: 2026-07-05
category: best-practices
module: .claude/hooks
issue: 5988
tags: [pretooluse-hooks, guardrails, set-e, shell-expansion, test-masking, fail-open, fail-soft]
---

# Composite safety-hook authoring pitfalls (guardrails.sh delete-guard + freeze edit-lock)

Two generalizable lessons from hardening `.claude/hooks/guardrails.sh` (#5988), each
of which shipped green through the first implementation and was caught only later
(one by a test-suite failure, one by 3 independent review agents).

## Lesson A — A composite/safety hook must FAIL-SOFT on optional-dependency sources

**Symptom.** Adding a new library to a `set -euo pipefail` hook via a bare
`source "$(dirname "${BASH_SOURCE[0]}")/lib/freeze-lock.sh"` (no `|| true`) broke
16/21 assertions in `tests/hooks/test_hook_emissions.sh` — including the *pre-existing*
`rm -rf`, `require-milestone`, and `commit-on-main` guards that the PR never touched.

**Root cause.** The emissions-test sandbox copies the hook + `incidents.sh` but not the
new `freeze-lock.sh`. Under `set -e`, a failed `source` aborts the WHOLE hook before any
guard runs. For a safety hook this is a fail-OPEN disaster: a missing/broken *optional*
helper silently disarms *every* guard, including the safety-critical delete/commit/stash
gates that don't even use the helper.

**Fix (two parts).**
1. Source optional helpers fail-soft and gate the optional feature on the function's
   existence, so the critical guards are never coupled to it:
   ```bash
   source ".../lib/freeze-lock.sh" 2>/dev/null || true
   ...
   if [[ -n "$FILE_PATH" && -z "$COMMAND" ]] && declare -f freeze_active_prefix >/dev/null 2>&1; then
   ```
   `incidents.sh` (used by every guard's `emit_incident`) stays hard-sourced — that IS a
   hard dependency. Only the *optional-feature* helper is soft.
2. A test sandbox that copies a hook MUST copy every lib the hook sources (add the
   `cp .../freeze-lock.sh` beside the existing `cp .../incidents.sh`).

**Generalization.** When a hook composes N guards where only guard K needs helper H,
sourcing H hard couples guards 1..N to H's availability. Decouple: fail-soft source +
`declare -f`-gate guard K. A guard's failure posture is a design decision — a safety
guard that degrades to a no-op on an unrelated dependency's absence is a silent fail-open.

## Lesson B — A lexical guard needs self-expansion, and its test must use LITERAL tokens

A PreToolUse hook sees the command string **before** the shell applies tilde/variable
expansion. So a guard that `realpath`s `rm` target tokens is bypassed by the most natural
accidental forms: `rm -rf $HOME`, `rm -rf ~`, `rm -rf $PWD` all reached the hook as the
literal tokens `$HOME`/`~`/`$PWD` (which resolve to `<cwd>/$HOME` etc., not the protected
target) while the shell deletes `$HOME` at exec. **3 review agents (security-sentinel,
user-impact, pattern-recognition) independently flagged this**; the single-agent-vs-quiet
cross-reconcile rule made it a firm CONFIRM.

**The test MASKED it.** The `delete: $HOME denies` fixture built the payload with
`mk_payload "rm -rf $HOME"` inside double quotes, so the *test shell* pre-expanded `$HOME`
to `/home/jean` before the hook saw it — proving only the already-covered absolute-path
case. A guard test for a shell-metachar input MUST pass the **literal** token (single
quotes: `mk_payload 'rm -rf $HOME'`) and control `HOME` hermetically, or it validates the
wrong thing.

**Fix.** Expand the common protected refs (`~`, `~/`, `$HOME`, `${HOME}`, `$PWD`,
`${PWD}`) inside the guard before `realpath`; add single-quoted-literal fixtures + a
HOME-overriding runner. Arbitrary `$VAR`/aliases/`xargs rm`/`find -exec`/glob remain out
of reach (a lexical pre-exec guard can't model them) — document that scope explicitly,
like `no-memory-write.sh` does ("for accidental rationalization, not bypass-defeat").

**Companion:** detect on the body-stripped `$SCAN` but tokenize the raw `$COMMAND` — the
unquoted `rm -rf` flags survive `$SCAN` (so a heredoc/commit-message body no longer false-
denies) while `$COMMAND` tokenization still recovers a real quoted path argument (no
false-negative).

## Session Errors

1. **[forwarded] deepen-plan Phase 4.9 UI-grep false-positive** on plan prose explaining
   there is no UI surface. Recovery: none needed (prose was correct). Prevention: the UI
   grep should exclude prose that negates a UI surface — one-off, known deepen-plan noise.
2. **[forwarded] MEMORY.md cited a stale `constitution.md` path** (`overview/` vs
   `project/`). Recovery: planning subagent used the correct `knowledge-base/project/`
   path. Prevention: MEMORY.md already warns constitution lives at `project/`; one-off.
3. **Hard-source of `freeze-lock.sh` disarmed the whole hook under `set -e`.** Recovery:
   fail-soft source + `declare -f` gate + copy the lib into the test sandbox. Prevention:
   Lesson A above — optional-helper sources in a composite safety hook must be `|| true`
   + function-gated so a missing helper never disarms the critical guards.
4. **Probe harness used a relative hook path after `cd`** → silent script-not-found →
   empty output misread as `<allow>` (false bypass alarm). Recovery: absolute `$HOOK`
   path. Prevention: a probe/test harness that `cd`s before invoking the script under
   test MUST use an absolute path to that script (the committed tests already do).
5. **Diagnostic Bash commands tripped the guard-under-development** (`git stash list`;
   a `.worktrees/` literal). Recovery: rephrase / move the probe into a script file so
   the trigger literals live in the file, not the command line. Prevention: when
   developing a guard, keep its trigger literals out of your own diagnostic command lines.
6. **`freeze-lock.test.sh` reader helper tripped the CLI-dispatch guard** by invoking the
   sourced script with `$0 == BASH_SOURCE[0]`. Recovery: wrapper `$0` (`_srcwrap`) ≠ the
   sourced path. Prevention: to unit-test a dual-mode (source + CLI) script's sourced
   functions, invoke via `bash -c 'source "$1"; fn' _wrapper "$SCRIPT"` so the
   `BASH_SOURCE[0]==$0` dispatch guard stays off.
7. **OpenHands smoke test asserted `git stash` denies**, but the OpenHands `block-stash`
   is cwd-gated (fires only in `.worktrees` paths), unlike Claude's unconditional version.
   Recovery: used `gh issue create` without `--milestone` (require-milestone fires
   unconditionally) as the non-shadow probe. Prevention: the OpenHands port diverges from
   the Claude hook on several gates (block-stash cwd-gating, no `$SCAN` body-strip, no
   external-repo milestone exemption) — a portable "sentinel still fires" probe must use
   an unconditional gate.
8. **shellcheck SC2088 false-positive** on the `"~/"*` case pattern (it is a pattern
   matching a literal `~`, not a path to expand). Recovery: `# shellcheck disable=SC2088`
   with a comment. Prevention: literal-tilde case patterns trip SC2088; suppress locally.

## Key Insight

A safety hook's value is being airtight; its two silent-failure modes are (a) a critical
guard disarmed because it was coupled to an optional dependency, and (b) a guard that
tests green against the wrong (pre-expanded / body-included) input shape. Both ship
through green CI — the first is caught by running the FULL suite (orphan sandbox surfaced
it), the second only by adversarial multi-agent review that drives the LITERAL attacker
input. Related: [[2026-06-15-runtime-guardrail-observable-signal-not-cooperative-marker]].
