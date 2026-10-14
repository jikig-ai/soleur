# Learning: a shared argv array carried a set-only flag into every doppler verb — and the stub was taught the same wrong model

## Problem

#9429: `workspaces-luks-verify`'s `web2_marker` job (added in #9352) reds
daily with `could not read the marker (Doppler fault)`, Sentry posting
error check-ins — four consecutive red runs before it was diagnosed. The
suspect set was token scope/expiry vs. a missing marker; the actual cause
was neither. `marker_args=(-p "$PROJ" -c "$CFG" --no-interactive)` was
shared across `doppler secrets get`, the write `set`, the read-back `get`,
and `delete` — but on the installed CLI (v3.76.6) `--no-interactive` exists
ONLY on `secrets set` (it skips the set confirmation prompt). `get` and
`delete` reject it as `unknown flag`, so every marker read exited 1 before
any evidence was judged — the job was born red.

Three compounding failures made a one-flag defect invisible for four days:

1. **The stub was taught the same wrong flag table.** The Guard-3 doppler
   stub REQUIRED `--no-interactive` on every verb — the suite certified the
   buggy call shape and could never see it. A stub that models the contract
   you *wrote* rather than the contract the tool *has* is a mirror, not a
   check. The fix's first step was re-teaching the stub the real surface
   (required on `set`, refused on `get`/`delete`) — which reproduced the
   production failure exactly before any workflow edit.
2. **The fault arm swallowed the CLI's own error.** `marker_state()`
   captured `2>&1` into `out`, matched one not-found string, and returned
   1 — the log recorded only the wrapper's "Doppler fault" text, so the
   underlying `unknown flag` never reached a human. Diagnosing it required
   re-running the exact argv locally. Any error-swallowing guard owes a
   self-describing print to stderr (never stdout — the caller captures
   stdout as the verdict).
3. **The diagnosis opened with credentials.** Token scope and expiry were
   checked first because they are the usual suspect; the deterministic
   answer was in `doppler secrets get --help`. Reproduce the exact argv
   before auditing the credential.

## Solution

- `marker_args` narrowed to the shared scope flags (`-p`/`-c`); the
  verb-scoped flag lives inline on the `secrets set` argv.
- `marker_state()`'s fault arm now prints the sanitized CLI error — token
  substituted, `dp.*` shapes masked, every line prefixed so a forged
  `::command` is inert, printable-only, 8K cap (the same posture
  `show_ssh_stderr` applies to remote stderr — remote error text is remote
  input).
- The stub models the real flag surface per verb, and mutation row 17h
  proves the model is load-bearing: folding the flag back into
  `marker_args` reds S01 via the stub's refusal.
- Bonus defect class pinned: when a suite requires a flag that the real
  tool rejects, the suite is certifying the bug — stub-per-verb flag
  tables should be built from the CLI's actual `--help`/rejection behavior,
  not from the code under test.
