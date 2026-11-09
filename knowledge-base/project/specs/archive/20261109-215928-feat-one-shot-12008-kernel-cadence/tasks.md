# Tasks: feat-one-shot-12008-kernel-cadence

Plan: knowledge-base/project/plans/2026-11-09-feat-host-kernel-patch-cadence-and-nonweb-exposure-check-plan.md
Issue: #12008 items 2 and 3 (Ref, not Closes). Nothing production-mutating runs; see the plan's Deferred Production Acts.

## Phase 0: Failing tests first (RED)

- 0.1 Write scripts/followthroughs/host-kernel-cadence-12008.test.sh (synthesized reader rows, env -i, case-count floor): precedence, boundary, reader exit 4, zero rows, summary-only output, unseen role row, stderr token, byte pin, ignored-role and column-shape rows, reader role-table pin, xtrace refusal, no arguments, hygiene scan. (Acknowledgement cases were removed by the review ruling A; they belong to the arming change, #12504.)
- 0.2 Write scripts/host-tcp-exposure.test.sh (synthesized .tf fixtures in the file): parser liveness, dynamic block, non-web inbound rule, binding ratchet, unmapped server, zero servers, servers with zero firewalls, ignored comment and removed block, real-tree design invariant.
- 0.3 Confirm both suites are RED before any implementation.

## Phase 1: The probe

- 1.1 Create scripts/followthroughs/host-kernel-cadence-12008.sh: readonly CADENCE_DAYS_* constants (no acknowledgement constants: deferred to the arming change, #12504); xtrace refusal; no arguments; cd to repo root; HKC_READER override only under HKC_TEST=1; parse reader rows, ignore the trailing summary line; classify_row and aggregate chokepoints; one fixed stdout line (the sweeper wraps it in a heading and fold); exits 5, 2, 3; header with credential posture, proxy caveat (uptime is a lower bound on kernel age, so within cadence never shows a patched kernel) and RETIREMENT list.
- 1.2 Make suite 0.1 GREEN.

## Phase 2: Exposure suite

- 2.1 Implement assertions 1 to 8 in scripts/host-tcp-exposure.test.sh (grep and awk by resource boundary over every .tf file; resource addresses only in failure messages).
- 2.2 Make suite 0.2 GREEN against fixtures and the real tree.

## Phase 3: Runbook

- 3.1 Create knowledge-base/engineering/operations/runbooks/host-kernel-patch-cadence.md: class table, per-class paragraphs (web incl. the host with no activation path, inngest, registry, git-data own path), per-class session procedure, tracker vocabulary, proxy caveat (uptime is a lower bound; nothing-to-report is not a patched-kernel claim), replace-does-not-guarantee-a-patch statement, an After-a-typed-go paragraph, literal reader and probe commands with a per-class awk view, the arming preconditions and order (#12504), headless escalation, exposure suite section. No SSH, no kernel strings, no CVE ids, no host names.

## Phase 4: Registration and hygiene

- 4.1 Add run_suite lines (label equals manifest key) plus each suite's AFFECTED_*_PATHS block and ALWAYS_ON_SUITES entry to scripts/test-all.sh.
- 4.2 Regenerate shard manifests with python3 scripts/regenerate-shard-manifest.py --incremental --write (no hand edits).
- 4.3 Verify bash scripts/test-all.sh --print-selection --paths=apps/web-platform/infra/firewall.tf selects the exposure suite; else register as always-on.
- 4.4 Run lint-orphan-test-suites.sh, c4-count-parity (13/0), lint-infra-no-human-steps.py on the runbook, lint-guard-contract.py on the plan, hold-gate-eval.sh on the plan (exit 0), technical-ruling-gate.sh on decision-challenges.md.
- 4.5 Confirm git diff --name-only origin/main...HEAD has no path under apps/, plugins/, infra/ or .github/.

## Phase 5: Follow-ups and PR

- 5.1 DONE (#12502): reboot_required column in host-state.sh plus matching overdue clause (plugin-release trigger noted; component-map pointer bundled).
- 5.2 DONE (#12503): should cloud-init upgrade packages so a replace brings a patched kernel (registry delivery gate on merge noted).
- 5.3 DONE: comment on #6442 (firewall_ids for registry and git-data; live firewall corroboration as a session-only read).
- 5.4 DONE (#12504): the UNARMED arming tracker (directive inside a code fence; precondition text; Ref #12008). It also carries the deferred acknowledgement scope. The arming order (real `earliest=`, label and body edit together outside 18:00 UTC, sweeper dry run, verify via the sweeper log) is in the runbook's arming section.
- 5.5 DONE: comments on #12385 and #12386 about the new dependency.
- 5.6 Commit with LEFTHOOK_EXCLUDE=bun-test git commit -F <file>; draft PR, CI, ready, merge queue; PR body: Ref #12008, Deferred Production Acts in plain words, nothing production-mutating ran, why the acts are not under a hold section.

## Post-merge (read-only)

- 6.1 Run the merged probe once under injected read credentials; expect one of the three fixed lines (session only).
- 6.2 gh run list --commit <merge sha>: no apply, replace or release workflow started.
- 6.3 Run soleur:postmerge.
