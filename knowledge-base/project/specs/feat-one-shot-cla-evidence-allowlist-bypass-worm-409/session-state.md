# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-05-18-fix-cla-evidence-allowlist-bypass-worm-409-plan.md
- Status: complete

### Errors
None. CWD verified at session start. User-Brand Impact gate (Phase 4.6) passed with threshold `none` + non-empty scope-out reason; diff scope does not match the canonical sensitive-path regex (no schema, no auth, no API route, no SQL, no migration, no `doppler*.yml`, no infra Terraform). Phase 4.5 (network-outage) did not trigger. Phase 2.7 GDPR gate did not trigger. Phase 2.8 IaC gate did not trigger. All cited PRs/runs/labels/AGENTS.md rule IDs verified live.

### Decisions
- Chose option (c): map 409/403 + `ObjectLockedByBucketPolicy` body to idempotent-duplicate at the shared `r2-conditional-put.sh` primitive layer. Rejected (a) HEAD/GET-before-PUT (round-trip + race) and (b) per-run keys + mutable canonical pointer (breaks GDPR §3.4 balancing-test WORM property).
- Broadened status disjunction from `409` (v1) to `409 OR 403` (v2). Cloudflare R2 docs `ObjectLockedByBucketPolicy` at HTTP 403; production run 26042357131 surfaced 409. Body code is the stable identifier; handle both envelopes.
- Corrected specificity counterexample in `Bypass.b3` from `ObjectLockedRetention` (not documented for R2) to `SignatureDoesNotMatch` (real R2 4xx code).
- Folded in a Phase 1 prerequisite: `upload-evidence.test.sh`'s `mk_curl_stub` does not honor `-o <file>` body-fixture injection; mirror `upload-bypass.test.sh`'s stub form before adding new test case. Corrected test-case label from `Evidence.b2` (v1) to `TS6.f`.
- Empirically verified under `set -euo pipefail` that the `if (( code == 409 || code == 403 )) && body_excerpt | grep -q -F '<Code>ObjectLockedByBucketPolicy</Code>'; then ... fi` shell form behaves correctly across match / non-match / empty body / status short-circuit. Pinned shell-form in Research Insights.

### Components Invoked
- `soleur:plan` (Step 1)
- `soleur:deepen-plan` (Step 2)
- Bash (gh pr view, gh run view, gh issue list, gh label list), Read, Write, Edit
- WebSearch + WebFetch (Cloudflare R2 Error Codes page, Bucket Locks docs)
- Empirical bash repro under strict mode
