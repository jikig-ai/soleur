# Decision challenges: credential-hardening pass (2026-10-06)

Persisted by plan (headless). Rendered into the PR body by ship. Neither item is auto-applied.

## 1. User-Challenge: the cron probe's Sentry curl is NOT hardened in this pass

- Operator direction: "(b) `--disable` and `--noproxy '*'` on every credentialed curl".
- Challenge: the one credentialed curl in `cron-egress-enforce-probe.sh` is the Sentry DSN POST. Editing it alone
  reds `cron-egress-enforce-probe.test.sh` "Sentry TRANSPORT parity" (byte-identical to
  `soleur-host-bootstrap.sh:58`); a third copy sits in `workspaces-luks-emit.sh:361`. The lint does not classify
  that curl as credentialed (header `X-Sentry-Auth`, variable `$KEY`), so the lint goal is met without it, and the
  CTO review judged the omission acceptable on the merits (ingest-only public DSN key, one run per fresh boot).
- Plan default: leave it; file issue F1 (all three copies together plus the Rule D blind spot). The NIC guard's
  bearer POST and its secret-URL heartbeat curls are hardened in this pass.
- Decision needed from the operator if they want the whole Sentry family in this PR: it adds
  `soleur-host-bootstrap.sh` (baked fresh-boot installer) and `workspaces-luks-emit.sh` (LUKS security-review
  scope) to the diff and to the blast radius.

## 2. Informational: the brief's "REQUIRED check" premise

- `lint-shell-trace-credential-refusal.py --changed` runs in the advisory `lint-bot-statuses` job, not in the CI
  Required ruleset; only the baseline-suppressed repo-wide run is required. The pass proceeds anyway (drawdown
  policy, and the baseline suppresses by file), but it does not unblock a required gate. No action needed.

## 3. Taste: how much test machinery for a ~25-line script change

- DHH and code-simplicity: cut the in-suite mutation runner, exact floors, H1/H2 and dispatch rows, the real-curl
  listener row, lint-echo rows, a placement parser, `bash -f`, and trim X3. Kieran independently found the runner
  unimplementable for the cron suite as drafted. Plan default: applied (both panels fired on the same scope, so
  delete beat fix). The mutation matrix stays in the plan and is run once by hand, recorded in the PR body.
- Kept against the cuts: three launch forms in X1 and X1b (the lint accepts a conditional refusal for the NIC
  guard, so X1b is the only guard of the unconditional property), the heartbeat flags, X3c parity.

## 4. Taste: one-line correction in `.claude/hooks/grep-q-pipe-guard.test.sh`

- code-simplicity: cut it (the next pass edits that file anyway). Kieran: fix the false "required check" wording.
  Plan default: keep a comment-only correction with no PR number. Reverse it if a third subsystem touch is
  unwelcome.
