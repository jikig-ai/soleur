## Problem

The cc-path safe-bash wiring landed in PR #3802 (`feat(cc-path): widen Bash
via safe-bash allowlist (Closes #3344)`). It's **wiring-only** — Bash now
routes through `canUseTool` and shares the legacy path's existing safe-bash
allowlist from `apps/web-platform/server/safe-bash.ts`. It does **NOT**
extend the allowlist itself.

The original ask in #3344 named several KB-exploration verbs that the
cc-router emits in practice but are NOT in the current allowlist:

- `find` (path-scoped variants, e.g., `find knowledge-base/...`)
- `grep` / `rg`
- `sort`, `uniq`

Today these route to `review_gate` (the modal path) when the cc-router
emits them — which is correct fail-safe behavior under the current
security review, but is the gap the user originally surfaced in #3338's
follow-through list ("we want to be able to do in the web platform the
same process that we do in here in the claude code plugin").

## Why this was deferred from PR #3802

the omission-rationale comment at the top of `safe-bash.ts` carries an explicit **load-bearing** rationale for
omitting `find` and `grep` from the allowlist:

> `find` and `grep` are intentionally OMITTED — both accept `-exec` and
> could shell out. `find` is also redundant with the SDK's `Glob` tool
> which is auto-allowed via FILE_TOOLS.

Re-evaluating this decision needs its own security-sentinel review pass.
Specifically:

1. Does the SDK's `Glob` tool already cover the `find` use cases the
   cc-router actually emits? Empirical telemetry needed.
2. What's the right argument-shape allowlist regex for `find` that
   excludes `-exec` / `-execdir` / `-ok`?
3. Same question for `grep -P` / `grep --perl-regexp` (regex DoS surface)
   and `grep -e` patterns starting with `-` (option-injection).
4. `rg` (ripgrep) — narrower surface than `grep`, but `--files-with-matches`
   + `--no-config` need pinning. Does `rg -e` / `rg --regexp` have its
   own injection surface?
5. `sort`/`uniq` — appear benign but `sort` accepts `--check-output` and
   `--files0-from`, which are file-write/file-read surfaces respectively.

A clean follow-up PR should land a **per-verb argument-shape regex** for
each verb, mirroring the existing pattern at `safe-bash.ts:69` (each
verb has its own narrow regex; arg shapes that don't match route to
`review_gate`).

## Proposed Fix

Open a security-sentinel review pass on:

1. Extend `SAFE_BASH_PATTERNS` in `safe-bash.ts:69` with narrow per-verb
   regexes for `find` (path-scoped, no `-exec`), `grep` (no `-P`/`-e`-
   starting-with-dash), `rg`, `sort`, `uniq`.
2. Update the load-bearing comment at the omission-rationale comment at the top of `safe-bash.ts` explaining why
   the new allowlist additions are safe (per-verb argument shapes).
3. Add `cc-dispatcher-bash-safe-allowlist.test.ts` regression rows
   pinning each new verb's auto-approve behavior AND the `-exec`/option-
   injection denial path.

## Acceptance

- [ ] Each new verb has a narrow per-arg regex in `SAFE_BASH_PATTERNS`.
- [ ] `cc-dispatcher-bash-safe-allowlist.test.ts` extended with
  positive (auto-approve) AND negative (review-gate routing) cases
  per verb.
- [ ] security-sentinel review pass approves the new allowlist shape.
- [ ] the omission-rationale comment at the top of `safe-bash.ts` comment updated to reflect the new state.

## Ref

- PR #3802 (`Closes #3344` — wiring-only Bash widening; deferred this
  extension).
- the omission-rationale comment at the top of `safe-bash.ts` (load-bearing `find`/`grep` omission rationale).
- #3338 follow-through plan §"Follow-Through Issues" (the original
  user-stated requirement).
