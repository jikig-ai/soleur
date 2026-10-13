# Tasks — argv-bearer follow-ups (#10119, #10120, #10091, #10092, #10093)

Plan: knowledge-base/project/plans/2026-10-13-fix-argv-bearer-followups-registry-inngest-probes-community-plan.md

## PR A (this branch): community write-env, lib validator, marker comment, markdown snippets

### 1. Baselines (read-only)

- 1.1 Green baseline: community-argv.test.sh, operator-script.test.sh, test-argv-bearer-sweep.sh (record the total), git-lock-marker-telemetry vitest, c4-count-parity.
- 1.2 Reproduce the duplicate-key race with N parallel write-env runs (RED evidence).
- 1.3 `git grep` populations: `.env` writers under plugins/soleur/skills/community/scripts and the lib; bearer headers in plugins/**/*.md.

### 2. #10091 setup scripts (RED first)

- 2.1 Add rows to community-argv.test.sh: parallel-run, no-flock, same-dir + mode-at-rename shim, artifact, unreadable-.env, killed-run/stale lock, must-PASS rows; new `_wenv_write` block drift rows + widening mutation.
- 2.2 Implement the byte-identical `_wenv_write` helper in the four scripts; replace the removal-and-append body of each cmd_write_env.
- 2.3 Run the whole community suite (stdout/stderr text pins must not move).

### 3. #10091 lib validator

- 3.1 Rows in operator-script.test.sh (control-char refusal, legit-credential must-PASS, value-free marker).
- 3.2 Add the control-character check to soleur_op_env_upsert; record the lib's .env consumers.

### 4. #10092

- 4.1 Comment-only edit above MARKER_RE (six emitters, phase=write-env shape, registry emitters out of scope); diff shows comments only; tsc + vitest.

### 5. #10093 markdown + stage S7

- 5.1 Convert seven files / ten curls (postmerge SKILL, sentry-error-count-delta GET and PUT, reproduce-bug, preflight, ship SKILL (record budget headroom), infra-security, deployment-verification-agent); reword the flag-delete/flag-list prose; shape case + `--config -` + one sentence on /proc/<pid>/cmdline.
- 5.2 Add stage S7 with allowlist (api-security.md), ceiling, floor, mutation rows; re-pin EXPECTED_TESTS from the measured total.

### 6. Docs and gates

- 6.1 ADR-280 follow-up paragraph (PR A).
- 6.0 File the `deferred-scope-out` tracker for the lib upsert/reset lock (Post-MVP / Later).
- 6.2 markdownlint, c4 parity, lint --changed; review, QA, ship (Closes #10091, #10092; Ref #10093, Ref #9757).

## PR B: registry template (#10119) and registry heartbeats (#10093 part) — stops at a ready PR

- 7.1 New branch from main (after A merges or rebased). Baselines: registry-boot-guard, htpasswd-stdin, battery, registry-userdata-budget (record stored size), grep-q-pipe-guard.
- 7.2 RED first: rendered-boot-block row, 127/6/1-through-pipe row, registry-heartbeat row, S6 converted-site rows.
- 7.3 Convert _htp_verify, boot step (install -m 600), the two heartbeat curls; reword argv-naming comments; measure budget, pay any shortfall in the same file.
- 7.4 Delete S6_ALLOW (ceiling 0), re-pin EXPECTED_TESTS, re-measure grep-q-pipe-guard; ADR-280 paragraph.
- 7.5 PR body: first line replace warning, hand-over note (merge command, watch, read-only post-merge check, abort path), Ref #10119, Ref #10093, Ref #9757, Tracks #<follow-through>. Mark ready; DO NOT MERGE.
- 7.6 File the follow-through tracker and ship `scripts/followthroughs/registry-htpasswd-stdin-10119.sh` + test (closes #10119 on PASS).

## PR C: inngest heartbeat (#10120) and probe scripts (#10093 last part) — stops at a ready PR

- 8.1 New branch from main after B has settled (or rebased; merge only after B settles). Baselines incl. cloud-init-inngest-bootstrap.test.sh (GuardA green on main, pin vinngest-v1.1.52).
- 8.2 Re-implement inngest-bootstrap.sh heartbeat guided by b48247d559 (do not cherry-pick); inngest.test.sh rows incl. dash row; floor re-measured.
- 8.3 Convert web-zot-consumer-probe.sh, inngest-consumer-probe.sh, web-private-nic-guard.sh; repoint every stub/negative row to the recorded stdin line.
- 8.4 Read-only live shape count of the three probe URLs (counts only).
- 8.5 Delete S6H_ALLOW (ceiling 0), extend S6H_CONVERTED, mutation rows, re-pin EXPECTED_TESTS; re-measure grep-q-pipe-guard; ADR-280 paragraph.
- 8.6 PR body: first line mint + re-delivery warning, GuardA window, B-before-C, verification commands, Ref #10120, Ref #10093, Ref #9757, Tracks #<follow-through>. Mark ready; DO NOT MERGE.
- 8.7 File the follow-through tracker and ship `scripts/followthroughs/inngest-heartbeat-stdin-10120.sh` + test (closes #10120, #10093 on PASS).

## Umbrella

- 9.1 Tick #9757 checklist items as each PR lands; close #9757 only when the last item is done.
