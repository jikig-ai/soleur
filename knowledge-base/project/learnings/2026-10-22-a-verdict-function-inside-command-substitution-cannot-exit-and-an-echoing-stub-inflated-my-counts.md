---
title: "A verdict function inside command substitution cannot exit, and an echoing stub inflated my counts"
date: 2026-10-22
category: test-failures
tags: [bash, followthrough, probe, exit-codes, fixtures]
issues: [10390]
pr: 10864
---

Two coupled defects found by the new verdict-matrix suite on `inngest-verify-clean-10390.sh`:

1. `run_one` was invoked as `SCAN_OUT="$(run_one "$SCAN_SQL")"` — its `exit 3` (CANNOT ESTABLISH)
   exited only the subshell, so a transport rc=3 surfaced as NOT YET(2) instead of 3. Fix:
   `SCAN_OUT="$(run_one …)" || SCAN_RC=$?` then `case` re-raise. **Any `exit N` inside a
   `$( )` call is a grade-quiet bug** — capture and re-raise, or the function's contract is fiction.
2. The phone-home test stub echoes the marker text (`PHONE_HOME <marker>`), so an unanchored
   `grep -c 'SOLEUR_INFRA_PULL_VERIFY_FAIL reason=signature'` reads **2 lines per emit** —
   my stamp-rekey arm read 4 ≠ 2. Anchor emit counts at `^` whenever a second channel echoes
   the same text.

Also this session: first-match classifiers need ORDER pins (cosign's identity error contains
"certificate"; `identity` must precede `chain` — proven by an overlapping-token fixture
`x509: certificate issuer mismatch`, which only order can decide), and a `> /dev/null`
swallow-negative over-matches the legal spaced-redirect shape — scope negatives to the
actual swallow (`> /dev/null 2>&1`).
