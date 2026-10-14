# Learning: a heuristic scorer over attacker-written text needs a cost bound and a bypass model before its first green

## Problem

#4671 shipped a rule-based prompt-injection scorer (`apps/web-platform/server/untrusted-content.ts`) with a corpus eval
(recall 0.96, FPR 0.000), unit/wiring tests and a 7-mutant battery, all green. An 11-seat review then found, in code that
had passed all of that: regexes with adjacent or nested unbounded quantifiers that were quadratic (one pattern needed
24 s at 16 KB; the 256 KB cap bounds length, not time, and `classify()` is synchronous on the shared dispatch event loop);
a quote/fence "discount" that one leading fence or quote character turned into a bypass (score 2.0 became 0.81); six invisible
character classes the stripper missed (soft hyphen, bidi controls, the Unicode tag block); and a verification round that found
the first fix for the cost problem still had a 32 s URL-query regex. Everything was green because the corpus and the mutation
battery were written by the scorer's author, against the shapes the author was thinking about.

## Solution

- Every regex over attacker text: no adjacent `\s*...\s*`, no `^\s*` under `m` (`\s` matches newlines), no unbounded run
  followed by a second scan; bound every run (`{0,N}`); prefer a linear `indexOf` walk to a lazy `[\s\S]` regex.
- A permanent adversarial-size timing test (256 KB of newlines, spaces, repeated `http://`, `send:http://`,
  unterminated comments, NFKC-expanding characters) that runs under the production engine (V8 via vitest).
- A discount or allowlist is an attacker-settable key: require CLOSED quoting, require two distinct corroborating terms,
  keep full weight for any one unquoted occurrence, and give cap exhaustion full weight (a decoy flood must not buy a discount).
- Normalise on a copy, decode hidden channels (the tag block) in place, re-apply the size cap AFTER normalisation and report
  `truncated` when expansion pushed text past it.
- Telemetry that must reach Better Stack ships at WARN (the shipper drops INFO), hashes the workspace id (it equals the
  user id for sole-owned workspaces), and every catch either mirrors to Sentry or is marked.

## Key Insight

For a guard whose input is written by the adversary, "green" from the author's corpus and the author's mutation battery
measures the author's imagination. Two instruments find what those cannot, and both are cheap: (1) a cost probe over
adversarial 256 KB inputs run under the production runtime, and (2) feeding the pristine guard the cheapest evasion of each
heuristic it contains (one quote character, one invisible separator, one decoy flood). The verification round after the fixes
found two more defects in the fixes themselves, and two of seven new mutants survived until the tests were rebuilt so that
only the fixed behaviour could satisfy them.

## Session Errors

1. **First scorer shipped quadratic regexes (P0), visible only to a review seat that measured.** Recovery: bounded every run, linear
   comment walk, timing test. **Prevention:** the plan sharp edge added with this learning requires the adversarial-size timing
   row for any scorer over untrusted text.
2. **Quote/fence/mention discount was a one-character bypass; the first fix (require meta-vocabulary) still left unclosed
   fences, an 8-match cap and one-word vocabulary.** Recovery: closed-quote rule, two distinct terms, cap exhaustion = full weight.
   **Prevention:** same sharp edge (bypass model per discount).
3. **The Edit/Write tool stored raw zero-width characters in a regex literal and in a test file** (invisible, caught by grep).
   Recovery: converted to `\u` escapes. **Prevention:** already covered by `cq-regex-unicode-separators-escape-only`; grep for
   non-ASCII after writing any invisible-character literal.
4. **Phase 0 section titled "measured on the shipped runtime" when it was static analysis of typings and binary strings, and
   "silently falls back" when the binary logs an error.** Recovery: reworded with the SDK version. **Prevention:** label the
   instrument in the heading; quote the code you read.
5. **A mutation battery's first run left two survivors (NFKC re-cap, in-place tag decode) because another rule satisfied the
   fixture.** Recovery: new truncation assertion and runs under the 12-char rule. **Prevention:** a survivor is a fixture-gap or an
   equivalent mutant: decide which, then fix the fixture.
6. **flip.sh `FLAG_ENV_VARS` was not updated for two new runtime flags (the fourth recurrence: #4923, #6182, #6526).** Recovery:
   added entries and `plugins/soleur/test/flip-flag-map-parity.test.sh` (mutation-proven) so the next one reds. **Prevention:** the test.
7. **The affected-test gate reported one RED (`test-all-weight-drift` C8, rc=4) caused by sibling-worktree contention.** Recovery:
   suite re-run in isolation 50/0. **Prevention:** none needed (one-off; the runner names the contention class).
8. **A decision-challenges row used a category outside the closed list and a mechanical fix was classed `technical`.** Recovery:
   `production-mutating`, reclassified as `taste`. **Prevention:** run `technical-ruling-gate.sh --branch` after each row edit.
9. **Bash cwd drifted to the bare repo root after a `cd` inside a compound command.** One-off; recovered by re-entering the worktree.
