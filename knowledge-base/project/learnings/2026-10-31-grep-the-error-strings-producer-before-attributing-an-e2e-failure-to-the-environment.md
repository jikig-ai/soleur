# Learning: before attributing an e2e failure cascade to the environment, grep the repo for the error string — a test may be fabricating it

## Problem

Issue #9167 filed "dev-Supabase `Signups not allowed for otp` cascades ~35
authenticated-suite reds" and prescribed an audit of the E2E Supabase
OTP-signup toggle or fixture bootstrap. The premise was wrong end-to-end:
no dev Supabase is reachable in the e2e suite, and the error string is
**manufactured inside the test repo itself** — `otp-login.e2e.ts` fulfills
`page.route("**/auth/v1/otp*")` with `status: 400` and
`code: "otp_disabled"`. The app's `console.error` then logs the fabricated
text into the CI log as `[browser]` console noise. In cited run 36449125669
the actual cascade was the (already-closed) #8785 Turbopack font
`Module not found`; the OTP string merely co-occurred in the same log.
The mis-read repeated three times (the issue, and twice inside PR triage).

## Investigation

The discriminating probe costs one grep: `rg -F "Signups not allowed for otp"`.
The only hits are the mock payload itself and docs — no production path emits
it. Second check: where does a dev Supabase URL appear in the e2e path? Both
`webServer` entries use a fake `test.supabase.co` or the in-process
`mock-supabase.ts` — there is no OTP-toggle surface to fix. Third: pull the
cited run's logs and look at what the failed tests actually report, not what
the browser console happens to print between them.

Measurement that closed it: ~300 merge-group e2e jobs, zero OTP/font-mechanism
recurrences; the 6 in-window reds were all `ERR_CONNECTION_REFUSED :3100` —
a different signature owned by #11299 (the managed webServer dying mid-run,
which the PR's `e2e/web-server.sh` exit marker now makes visible).

## Solution

For "environment failure" issues keyed on an error string:

1. `rg -F "<exact string>"` — if the only producer is test code
   (`page.route`, a mock server, a fixture body), the string is evidence of
   nothing environmental; label it (`[e2e-mock]` tag shipped in this PR) so
   the next triage cycle can't re-read it as signal.
2. Read the run's failed-step log for the mechanism the TESTS report, not the
   lines that merely co-occur (browser console noise rides every log).
3. Re-measure before closing: list merge-group runs, check every non-success
   job's conclusion and signature; never carry forward a stale "N/N green"
   figure (this session's first draft claimed 60/60 — the true window had 6
   signature-different reds).

## Key Insight

A fabricated string in CI logs is indistinguishable from a real vendor error
unless you grep for its producer. Self-labeling mock output (`[e2e-mock]`)
is cheap insurance against N future mis-triage cycles — one line in the
fixture, zero trips through issue triage.

Related pattern (same session, different mechanism): when sanitizing an
emitted line through `tr -d '\000-\037\177'`, the writer's own trailing
newline is inside the deletion range — keep `\n` in the alphabet
(`\000-\011\013-\037\177`) or sanitize fields, not the whole line.

## Tags

e2e, triage, mock-fabrication, playwright, flakiness, #9167, #11299
