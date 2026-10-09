# Tasks: rehearse dockerd deny probe (Ref #9799, item 5)

Plan: knowledge-base/project/plans/2026-10-09-fix-rehearse-dockerd-hosts-cache-race-plan.md

## Phase 1 - Tests first
- 1.1 Create apps/web-platform/infra/zot-image-rehearse-probe.test.sh (mode 755): harness, instrument self-test, row floor, PATH shims (sudo, docker, sleep, systemctl)
- 1.2 Rows 1-4: refused pull (sleep 7 before the one pull), successful pull with marker (evidence printed, returns 1), successful pull with empty output (returns 1), different denial message (returns 0)
- 1.3 Row 5: static check over zot-image-rehearse.sh (one pull line, no /dev/null on it, deny applied before the call)
- 1.4 Mutation battery M1-M4 via sed copies; harness row with a non-logging docker shim
- 1.5 Run it and confirm it fails before the fix

## Phase 2 - Fix
- 2.1 Add HOSTS_CACHE_WAIT_S=7, assert_dockerd_denied and the source guard after `set -euo pipefail`, before STORE= parsing
- 2.2 Replace the discarding probe (lines ~105-107) with the call site and the die message
- 2.3 Add the comment: rehearsal's probe, not a claim about the registry host
- 2.4 Explicit returns (function runs under `||`), `&& rc=0 || rc=$?` capture, best-effort diagnostics, no use of STORE/W/dk, no hosts write

## Phase 3 - Verify (targeted local only)
- 3.1 New suite green; each mutation red
- 3.2 shellcheck on both files
- 3.3 web-ghcr-deny.test.sh (census); read SKIP honestly
- 3.4 test-infra-suite-registration.sh; regenerate shard rows only if asked
- 3.5 Confirm git diff touches none of cloud-init-registry.yml, zot-registry.tf, variables.tf, server.tf, deploy_pipeline_fix triggers

## Phase 4 - PR
- 4.1 Body: Ref #9799, hypothesis wording, real-host ordering finding, web-host copies not examined; no close keyword; no new issues
- 4.2 Rely on CI rehearse (classic|containerd|host) for live verification

## Notes (deepen-plan, 2026-10-09)
- Observability discovery command is `grep -c '^HOSTS_CACHE_WAIT_S=7$' apps/web-platform/infra/zot-image-rehearse.sh` (expects 1); keep the constant on its own line.
- Phase 1 (new suite) and the source guard are queued as a User-Challenge in decision-challenges.md; implement them unless the operator cuts them.

## Work log (2026-10-09)
- Operator ruling applied: no new behavioural suite and no source guard. The probe is covered by a static `probe` check in web-ghcr-deny.test.sh (39 assertions, floor 39); five hand mutations (delete sleep, restore /dev/null, wait 1 s, second pull site, drop the deny) each red it.
- Fix: assert_dockerd_denied in zot-image-rehearse.sh (unconditional 7 s wait, captured pull output, diagnostics on a successful pull). Function dry-run with shimmed sudo/docker/sleep: refused pull returns 0 after one sleep 7; successful pull prints the evidence block and returns 1.
- Lints: lint-shell-capture-exit (0 new), lint-shell-trace-credential-refusal --changed (OK). Broad battery left to CI.
