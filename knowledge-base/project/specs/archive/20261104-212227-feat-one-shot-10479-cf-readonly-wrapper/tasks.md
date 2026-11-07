# Tasks: Cloudflare read-only wrapper for Class R (#10479 A/B/C/E)

Plan: `knowledge-base/project/plans/2026-11-04-feat-cloudflare-readonly-class-r-wrapper-plan.md`
Hard limits: stop at draft PR #12061, unarmed; no live Cloudflare call, no Doppler read, no dispatch, no tracker edit.

## Phase 0: Verify
- 0.1 Re-confirm against vendor docs what deepen could not (ssl GET wrapping in result, entrypoint top-level version, action_parameters.ssl, audit since/before requirement, Audit Logs Read permission name); record dated citations; unverifiable items degrade to unverified
- 0.2 Read model.c4, views.c4 and spec.c4 in full; confirm "No C4 change"
- 0.3 Read full on:/paths:/types: blocks of every workflow for the push gate

## Phase 1: Tests first (RED)
- 1.1 Create plugins/soleur/test/cloudflare-readonly.test.sh (sandbox copy with the CURL= line rewritten to the stub; fixture-file stub; instrumented mutate helper with pristine and benign-edit controls; wire assertions; env dump; grep -F scans with controls; mutation rows from Guards 1 and 2; anti-vacuity floors; in-worktree scratch TMPDIR)
- 1.2 Edit plugins/soleur/test/components.test.ts: 11 PAIRS rows, structural tests (subcommand parity non-empty and length 4, Credentials variable set, item 4 .github pin, polarity), REQUIRED additions, PAIRS_FLOOR 48 -> 59
- 1.3 Run both and confirm RED

## Phase 2: Wrapper
- 2.1 Create plugins/soleur/scripts/cloudflare-readonly.sh, executable (prologue with PATH pin, token-source pins, token trim and shape check, per-subcommand binding, cf_get chokepoint: /usr/bin/env -i /usr/bin/curl --disable ... --config - < <(printf ...), type-guarded jq projections, enum and regex checks on vendor strings, status map, Records mapping header, --list)
- 2.2 Make the suite GREEN; run each mutation row

## Phase 3: Text
- 3.1 standing-delegation.md section 9: item 2, item 4 clause, Credentials, Boundary
- 3.2 cto.md: one sentence in "Class R first" (path, four subcommands, Records mapping pointer, 403 never widened)
- 3.3 ADR-289 addendum 2026-11-04 (via soleur:architecture)

## Phase 4: Verify
- 4.0 Guard 3 sandbox-copy drive (7 rows), results recorded for the PR
- 4.1 Suites, pin test, c4-count-parity, the three shell lints, orphan lint, guard-contract lint, technical-ruling gate, opencode adapter test (one at a time)

## Phase 5: Ship phase (stop at draft)
- 5.1 Push gate by hand; push only if no matching workflow deploys, applies or spends; else commit locally and report one sentence
- 5.2 Verify closingIssuesReferences is [] before and after saving the PR body; Ref #10479 and Ref #10205 only; owner-review items first
- 5.3 Do not mark ready, merge or arm
