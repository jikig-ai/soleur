# Tasks: Wave A2 infra and CI early-exit pipes (plus J, C evidence)

Plan: `knowledge-base/project/plans/2026-10-06-fix-pipefail-early-exit-wave-a2-infra-ci-plan.md`
Branch: `feat-one-shot-merge-queue-pipefail-wave-a2` | Draft PR: #9587 | Tracker: #9217 (Ref only, never Closes)

Forms: F1 `-q` to `-c` plus `>/dev/null` (default, dialect-neutral, byte-exact); F2 here-string for the 3 output-bearing `-m1` sites; F3 `# sigpipe-demo: intentional` for the 3 demo lines in `sigpipe-triage-feasibility.sh`; F4 rewrite the drain prompt literal.

## Phase 0 - Preflight and census (no edits)

- [ ] 0.1 Re-run `gh pr list --state open`; fetch and confirm `origin/main` is an ancestor of HEAD
- [ ] 0.2 Comment on #9529 and #9571 (shared files): zero rule plus line-level overlap
- [ ] 0.3 Regenerate the 140-line census with the guard's own `PATTERN_V2`; classify each hit by dialect, pipefail, deploy class (H, W, C, CI)
- [ ] 0.4 Escape-aware pin census over `*.test.sh`, `*.test.ts`, `scripts/check-*`; list the suites to run per file
- [ ] 0.5 Verify every path and glob the plan names resolves (`git ls-files`)

## Phase 1 - RED first: guard table and real-table probe rows

- [ ] 1.1 Reproduce J (3,000-iteration loop, both SIGPIPE modes), record `miss=N`
- [ ] 1.2 Edit `SWEEP_DEFERRALS`: delete the drain, `.github/*`, `lefthook.yml` rows; replace the infra row with four file-exact `=` rows (13, 4, 3, 1) with the replace-class reason
- [ ] 1.3 Add the permanent real-table checks (mutation row 1 via `scan_sweep` on a scratch root, row 6 test-shaped assertion) and harness rows H1-H3; run rows 2, 3, 4, 7 once by hand; bump `SWEEP_PROBE_CHECKS` and `V2_GOOD_LINES`
- [ ] 1.4 Add the F1 row to the guard header's forms table
- [ ] 1.5 Run the guard: it must be RED until Phases 2-4 land

## Phase 2 - J and class C (nothing deployed)

- [ ] 2.1 Convert the 5 sites in `gen-github-egress-cidr.test.sh`; loop reads `miss=0`; suite passes; lower the `apps/web-platform/*.test.sh` ceiling 188 to 183
- [ ] 2.2 Convert the three `*-userdata-budget.sh`, `zot-image-oci-archive.sh`, `inngest-luks-cutover.sh`, `audit-bwrap-uid.sh` (F1); `sigpipe-triage-feasibility.sh` (F3); twins identical

## Phase 3 - CI

- [ ] 3.1 `.github/workflows/*.yml` (42 lines, 18 files) and the two `.github/scripts/check-*.sh` (F1; F2 for supabase scan and `reusable-release.yml` tag lookup, keeping its fall-through); lockstep `pr-quality-guards.yml:760` and `skill-security-scan-postmerge.yml:119`
- [ ] 3.2 `lefthook.yml:449` (F1)
- [ ] 3.3 Drain workflow prompt `:181,184` (F4) and `SKILL.md:84`; syntax-check by `new Function`; run the drain tests
- [ ] 3.4 Validate workflows (actionlint if present) and the path-gated batteries they arm

## Phase 4 - Class W (auto-applied on merge; do NOT use `[skip-deploy-fix-apply]`)

- [ ] 4.1 `ci-deploy.sh` (15) in lockstep with `soleur-host-bootstrap.sh:454`; keep `ci-deploy.test.sh:9697-9701` mutation rows applying
- [ ] 4.2 `soleur-host-bootstrap.sh`, `web-private-nic-guard.sh`, `cron-egress-*.sh`, `cloud-init.yml:511` (F1)
- [ ] 4.3 `server.tf` (9) and `workspaces-luks.tf:253` inline strings (F1); `terraform fmt -check` and `validate`; enumerate every workflow that can apply each edited `.tf`
- [ ] 4.4 Run the owning suites by name (including `cloud-init-user-data-size.test.ts`, `cron-egress-enforce-probe.test.sh`, `soleur-host-bootstrap-observability.test.sh`, `cloud-init-ghcr-seed-login.test.sh`, `inngest-luks-cutover.test.sh`) plus `bash -n`, `sh -n`, shellcheck
- [ ] 4.5 Confirm the four replace-class files are untouched (AC3 command)

## Phase 5 - Verify, evidence, ship

- [ ] 5.1 Ratchets: `grep -lis ratchet ...` by name, `test-affected-kb-consumers.test.sh`, `pre-push-ratchet-lane.sh`, `c4-count-parity.test.sh`, the plan lints, markdownlint
- [ ] 5.2 Evidence comment on #9217 (J numbers, per-row before and after, replace-class carve-out, form decision); one-liners on #7376, #6601, #7005
- [ ] 5.3 Evidence comment on #9167 (merge-group `e2e` outcomes: 4 of 43 failed before the font-vendoring merge, 0 of 12 after; re-measure)
- [ ] 5.4 Two learnings (user_data ForceNew carve-out, source-text pin as a pipe); the F1 rationale lives in the guard header
- [ ] 5.5 PR body: `Ref` lines, T0.3 table, Not fixed section
- [ ] 5.6 Rebase, re-run the guard, ONE batched push; ship; postmerge (AC15)

## Descope valve

If class W is blocked (a sibling conflict in `ci-deploy.sh`, an unsatisfiable parity gate), ship phases 1-3 with the infra row lowered to 71, and move W (50 hits) to a follow-on PR A2b.
