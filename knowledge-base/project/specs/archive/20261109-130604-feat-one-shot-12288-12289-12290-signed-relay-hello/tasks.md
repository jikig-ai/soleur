# Tasks: signed relay hello, pre-TLS allowlist, bounded deny reporting (PR A of #8211 / #12167)

Plan: `knowledge-base/project/plans/2026-11-09-feat-signed-relay-hello-pre-tls-allowlist-plan.md`
Closes #12288, #12289, #12290. Owner-gated (never agent steps): merge, release, apply dispatch, Doppler writes, `flip.sh`, `cf-lb-overlay` dispatch.

Every phase: tests first (capture RED to `/var/tmp/relay-a-red-<phase>.log`), implement to GREEN, then mutate every added guard on a sandbox copy in the same commit (`bash scripts/soleur-sandbox.sh new|run-isolated|rm`; control green first; assert the mutation landed; enumerated shapes beside any equivalent-mutant claim). No secrets on command lines; synthesize keys at test time; scratch under `/var/tmp`; never `git stash`.

## Phase 0 - Baseline
- 0.1 Run control suites and record counts (web-platform relay tests, destroy-guard suite = 121, `terraform-target-parity.test.ts`)
- 0.2 Re-run `/var/tmp/relay-spike/spike.mjs` under Node 22

## Phase 1 - Bounded deny reporter (commit 1)
- 1.1 RED: `test/proxy-deny-report.test.ts` (5 events/60 s/reason, exact counter, summary event, accepted counter, `relay_hello_window` line)
- 1.2 GREEN: `server/proxy-deny-report.ts`
- 1.3 Mutate Guard 2 rows 1-6 in a sandbox

## Phase 2 - Pre-TLS admission, #12288 (commit 2)
- 2.1 RED: `test/session-proxy-admission.test.ts` (allowed, denied, undefined address via real `net.Socket`, IPv4-mapped, 200-burst, hello-less hold-open >1.2 s, `relay_probe` grammar)
- 2.2 GREEN: `prependListener("connection")` + shared predicate + in-`wss` re-check + probe-contract comment
- 2.3 Mutate Guard 1 rows 1-4 (rows 5-6 recorded equivalent with enumerated shapes)

## Phase 3 - Hello protocol and key isolation (commit 3)
- 3.1 RED: `test/proxy-hello.test.ts` (known-answer vector, shapes, size cap, skew, replay expiry from `ts`), `test/proxy-hello-key-isolation.test.ts`, `loadProxyHelloKey` cases in `proxy-tls.test.ts`
- 3.2 GREEN: `server/proxy-hello.ts`, `loadProxyHelloKey`, `sensitive-keys.ts` entry
- 3.3 Mutate Guards 3 (rows 1-6, 8), 4, 5 (rows 1-6), 9

## Phase 4 - Verifier wiring, sender, startup guard (commit 4)
- 4.1 RED: `test/session-proxy-hello.test.ts`, rewritten `session-proxy.test.ts` fixtures (synthesized UUIDs), key stubs in `proxy-listener-status.test.ts`
- 4.2 GREEN: check order allowlist -> cap -> shape -> MAC -> ts -> replay (sync, before the `await`) -> AP-2; sender signing; `createProxyServer.no-hello-key` after tls/bind/allowlist checks
- 4.3 One-time real-old-parser characterization from `git show origin/main:...`; record in the commit message
- 4.4 Mutate Guards 5 (rows 7-8), 6

## Phase 5 - Port parse and guarded listen, #12290 (commit 5)
- 5.1 RED: port shapes, throwing `listen`, sender invalid port
- 5.2 GREEN: `resolveProxyPort`, try/catch around `listen`, delete `PROXY_LISTEN_PORT`
- 5.3 Mutate Guard 7

## Phase 6 - Destroy-guard counter (commit 6)
- 6.1 `git grep` the work list for `luks_passphrase_rotations|luks_passphrase_addrs`
- 6.2 RED: rows T66a-T66o + fixtures + parity-test extension
- 6.3 GREEN: `.jq` counter, workflow read/validation/HALT (own diagnostic grep), parity test lock-step, comment fix, job-rationale runbook
- 6.4 Floor 136 from a green run; mutate Guard 8

## Phase 7 - Release-time presence gate (commit 7)
- 7.1 RED: `apps/web-platform/scripts/verify-required-secrets.test.sh` (V1-V6) + flag-coupling parity row
- 7.2 GREEN: `REQUIRED` entry; floor 6; mutate Guard 10

## Phase 8 - Records (commit 8)
- 8.1 Read all three `.c4` files; record the "no C4 impact" enumeration
- 8.2 ADR-323; amend ADR-068 and ADR-118 (`check-adr-ordinals.sh`)
- 8.3 `betterstack-log-query.md`: "Signed hello rollout (#12289)" section and `denied` update
- 8.4 File the residuals tracking issue

## Gate and review
- G.1 Run the Pre-push Gate List from the plan (with CI flags, including `lint-trap-tempfile-ownership.py --check-highwater`)
- G.2 Review panel: security-sentinel, test-design-reviewer (minimum), architecture-strategist, code-simplicity-reviewer, observability-coverage-reviewer, user-impact-reviewer, semgrep-sast
