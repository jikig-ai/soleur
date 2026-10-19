---
title: "GitHub Code Quality baseline (CodeQL quality suite) on main 30407a8597"
date: 2026-10-14
type: audit
issue: 10331
status: baseline
last_updated: 2026-10-19
---

# GitHub Code Quality baseline, 2026-10-14

Snapshot of the open findings GitHub Code Quality reports for `jikig-ai/soleur` on `main` at `30407a8597`, taken after the feature was re-enabled on 2026-10-14 (about 22:10Z) and its "CodeQL Setup" scan completed. Tracker: #10331. Scope authority: ADR-276 Decision 6 (CodeQL code scanning and Code Quality are separate features). Cost lever: the S5 row of ADR-276 (#9730).

## Method and limits

- Read from the GitHub UI (Security and quality, Code quality, Standard findings). The code-scanning REST API does not return these findings.
- Totals: 22 rules, 169 open findings. Maintainability "Fair" (84), Reliability "Poor" (85), plus 7 AI suggestions that this file does not list.
- **File lists are first-page only and de-duplicated per file.** For the high-volume rules (`js/unused-local-variable` 60, `py/file-not-closed` 36, `py/empty-except` 20) the list below is a sample of the files, not every location. Re-read the rule page for the full set.
- Classification (product, shipped plugin script, repo script, test or fixture, archived scratch) is by path and was not reviewed by a person.
- GitHub's severity labels are used as reported (Note, Warning, Error).

## Rules

| Rule | Lang | Category | Severity | Findings |
|---|---|---|---|---|
| js/unused-local-variable | JS/TS | Maintainability | Note | 60 |
| py/file-not-closed | Python | Reliability | Warning | 36 |
| py/empty-except | Python | Reliability | Note | 20 |
| js/trivial-conditional | JS/TS | Reliability | Warning | 8 |
| js/useless-assignment-to-local | JS/TS | Maintainability | Warning | 8 |
| js/superfluous-trailing-arguments | JS/TS | Reliability | Warning | 7 |
| py/catch-base-exception | Python | Reliability | Note | 5 |
| py/unused-import | Python | Maintainability | Note | 5 |
| py/unused-global-variable | Python | Maintainability | Note | 4 |
| js/comparison-between-incompatible-types | JS/TS | Reliability | Warning | 2 |
| js/overwritten-property | JS/TS | Reliability | Error | 2 |
| py/unused-local-variable | Python | Maintainability | Note | 2 |
| js/regex/unmatchable-caret | JS/TS | Reliability | Error | 1 |
| js/regex/duplicate-in-character-class | JS/TS | Reliability | Warning | 1 |
| js/string-instead-of-regex | JS/TS | Reliability | Warning | 1 |
| js/useless-assignment-to-property | JS/TS | Maintainability | Warning | 1 |
| js/useless-comparison-test | JS/TS | Reliability | Warning | 1 |
| py/comparison-of-identical-expressions | Python | Maintainability | Warning | 1 |
| py/mixed-returns | Python | Reliability | Note | 1 |
| py/procedure-return-value-used | Python | Maintainability | Warning | 1 |
| py/regex/duplicate-in-character-class | Python | Maintainability | Warning | 1 |
| rb/useless-assignment-to-local | Ruby | Maintainability | Warning | 1 |

## Files by rule (first page, de-duplicated)

Class key: P = product code (`apps/web-platform` app, server and components), S = plugin script that ships to users, R = repo script or hook (including `apps/web-platform/infra` and `apps/web-platform/scripts`), T = test, fixture or test support, A = archived spec scratch.

### js/unused-local-variable (60 findings; 21 files seen)

- P: `apps/web-platform/server/cc-dispatcher.ts`, `apps/web-platform/server/notifications.ts`, `apps/web-platform/components/settings/dsar-export-job-list.tsx`, `apps/web-platform/server/inngest/functions/cron-ux-audit.ts`
- T (17): `plugins/soleur/test/cloud-init-user-data-size.test.ts`, `apps/web-platform/test/agent-runner-system-prompt.test.ts`, `plugins/soleur/test/web-host-escrow-preflight-census.test.ts`, `apps/web-platform/test/ws-deferred-attachments-only.test.ts`, `apps/web-platform/test/live-verify/perf-probe.test.ts`, `plugins/soleur/test/preflight-discoverability-test.test.ts`, `plugins/soleur/test/skill-security-scan.test.ts`, `plugins/soleur/test/harness-parity.test.ts`, `plugins/soleur/test/harness-model-map.test.ts`, `plugins/soleur/test/heartbeat-live-reconcile.test.ts`, `test/content-publisher.test.ts`, `apps/web-platform/test/pwa/sw-reset.test.tsx`, `apps/web-platform/test/agent-runner-result-branch-finalization.test.ts`, `apps/web-platform/test/components/tour/tour-provider.test.tsx`, `apps/web-platform/test/cc-reprovision-git-discriminator.test.ts`, `apps/web-platform/test/server/session-sync-workspace-last-synced.test.ts`, `plugins/soleur/test/model-launch-review.test.ts`

### py/file-not-closed (36 findings; 12 files seen)

- A (7): `knowledge-base/project/specs/archive/20261014-132045-feat-one-shot-grep-q-pipe-guard-s7c-derivation-recall/j0-stubs.py`, `.../j0-instrument.py`, `.../j0-sites.py`, `knowledge-base/project/specs/archive/20261013-051752-feat-serena-mcp-eval/measurement/a1_bracket.py`, `knowledge-base/project/specs/archive/20261012-033826-feat-one-shot-grep-q-pipe-guard-s7b-producer-join/j0-derive.py`, `knowledge-base/project/specs/archive/20261006-171255-feat-one-shot-7843-argv-bearer-to-config-stdin/census-argv-bearer.py`, `knowledge-base/project/specs/archive/20260922-133038-feat-c4-model-mergeable/replay/replay.py`
- R (3): `scripts/regenerate-shard-manifest.py`, `scripts/lint-shell-capture-exit.py`, `apps/web-platform/infra/doppler-download-error-channel.mutation.py`
- T (2): `plugins/soleur/skills/agent-browser/test/fixtures/fake-playwright-mcp.py`, `plugins/soleur/test/fixtures/codeql-main-alert-gate-workflow-wiring/wiring_facts.py`

### py/empty-except (20 findings; 9 files seen)

- S (4): `plugins/soleur/scripts/scan-ancestor-signal-helpers.py`, `plugins/soleur/skills/preflight/scripts/founder-check.py`, `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py`, `plugins/soleur/skills/resolve-debt/scripts/resolve-debt.py`
- R (2): `.claude/hooks/security_reminder_hook.py`, `scripts/lint-rule-ids.py`
- T (3): `tests/conftest.py`, `plugins/soleur/skills/agent-browser/test/fixtures/proxy-session-driver.py`, `plugins/soleur/skills/agent-browser/test/fixtures/capture-playwright-mcp-fixtures.py`

### js/trivial-conditional (8 findings; 7 files seen)

- P (4): `apps/web-platform/server/ws-handler.ts`, `apps/web-platform/app/(auth)/callback/route.ts`, `apps/web-platform/server/session-sync.ts`, `apps/web-platform/app/api/analytics/track/route.ts`
- T (3): `apps/web-platform/test/server/inngest/agent-on-spawn-requested-leader-loop.test.ts`, `apps/web-platform/test/inbox-surface-cache.test.tsx`, `apps/web-platform/test/server/inngest/workspace-reconcile-on-push.test.ts`

### js/useless-assignment-to-local (8 findings; 7 files seen)

- P (4): `apps/web-platform/server/cc-dispatcher.ts`, `apps/web-platform/server/session-sync.ts`, `apps/web-platform/server/inngest/functions/cron-stale-deferred-scope-outs.ts`, `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts`
- R (1): `apps/web-platform/scripts/sandbox-canary.mjs`
- T (2): `apps/web-platform/test/github-app-manifest-parity.test.ts`, `apps/web-platform/test/server/messages-insert-workspace-id-sweep.test.ts`

### js/superfluous-trailing-arguments (7 findings; 3 files seen)

- T: `apps/web-platform/test/git-lock-marker-telemetry.test.ts`, `apps/web-platform/test/context-queries-hook.test.ts`, `apps/web-platform/test/theme-provider.test.tsx`

### py/catch-base-exception (5 findings; 3 files seen)

- S (2): `plugins/soleur/scripts/scan-ancestor-signal-helpers.py`, `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py`
- A: `knowledge-base/project/specs/archive/20261013-051752-feat-serena-mcp-eval/measurement/a1_bracket.py`

### py/unused-import (5 findings; 5 files seen)

- S: `plugins/soleur/skills/skill-creator/scripts/quick_validate.py`
- R: `scripts/backfill-frontmatter.py`
- T: `tests/scripts/test_lint_rule_ids.py`
- A (2): `knowledge-base/project/specs/archive/20261013-051752-feat-serena-mcp-eval/measurement/a1_measure.py`, `knowledge-base/project/specs/archive/20260922-133038-feat-c4-model-mergeable/replay/replay.py`

### py/unused-global-variable (4 findings; 3 files seen)

- T (2): `plugins/soleur/skills/agent-browser/test/fixtures/fake-playwright-mcp.py`, `tests/conftest.py`
- A: `knowledge-base/project/specs/archive/20261014-132045-feat-one-shot-grep-q-pipe-guard-s7c-derivation-recall/j0-instrument.py`

### js/comparison-between-incompatible-types (2 findings) - review first

- P: `apps/web-platform/server/account-delete.ts`, `apps/web-platform/server/dsar-export.ts` (account deletion and data export; GDPR-sensitive)

### js/overwritten-property (2 findings, Error)

- T: `plugins/soleur/test/ship-incident-pir-gate.test.ts`, `test/content-publisher.test.ts`

### Single-finding rules

- js/regex/unmatchable-caret (Error): T `plugins/soleur/test/legal-template-vendor-surface.test.ts`
- js/regex/duplicate-in-character-class: T `apps/web-platform/test/server/inngest/cron-community-monitor-allowlist.test.ts`
- js/string-instead-of-regex: T `plugins/soleur/test/terraform-target-parity.test.ts`
- js/useless-assignment-to-property: R `plugins/soleur/docs/scripts/screenshot-gate.mjs`
- js/useless-comparison-test: T `apps/web-platform/test/helpers/bundled-server.ts`
- py/unused-local-variable (2 findings): R `scripts/backfill-frontmatter.py`
- py/comparison-of-identical-expressions: T `plugins/soleur/test/fixtures/codeql-main-alert-gate-workflow-wiring/wiring_facts.py`
- py/mixed-returns: S `plugins/soleur/scripts/scan-ancestor-signal-helpers.py`
- py/procedure-return-value-used: S `plugins/soleur/skills/agent-browser/scripts/playwright-mcp-redact-proxy.py`
- py/regex/duplicate-in-character-class: R `scripts/lint-anthropic-content-position.py`
- rb/useless-assignment-to-local: S `plugins/soleur/skills/dspy-ruby/assets/config-template.rb`

## Reading

- Most of the volume is tests, fixtures, archived spec scratch and repo scripts. The "Poor" Reliability score is driven mainly by `py/file-not-closed` (every sampled location is outside product code) and `py/empty-except`.
- Two groups matter beyond the score: the empty `except` and `BaseException` handlers in plugin scripts that ship to users and in repo hooks, and the two incompatible-type comparisons in account deletion and data export.
- Most are lint-class findings; the incompatible-type comparisons are untriaged and may be real logic bugs. Only the per-rule totals are complete, so per-file ratcheting needs a full re-export. A deterministic linter in the `work` and `review` gates (ruff for Python, eslint `no-unused-vars` for JS/TS) with a ratcheting baseline catches them without CodeQL's runner cost. That work is tracked in #10331.

## Cost context (not part of the baseline)

- Enabling Code Quality bills $10 per active committer per month plus AI credits and Action minutes (GitHub's confirm dialog, 2026-10-14).
- Runner cost measured by `scripts/ci-demand-census.sh` over 2026-10-14 10:00-12:00Z (the job was already running then, before the re-enable above): the `dynamic/github-code-quality/codeql` job was 141.1 of 3,234.6 job-min (4.4%). The raw census output was not saved; re-run the script to reproduce.

## Resolution: js/comparison-between-incompatible-types (2026-10-15, PR1 of #10331)

Both findings were located through the repository's Code Quality alert list (the code-scanning REST API does not return these alerts). Neither is a behavior bug. Both are `typeof x === "object" && x !== null` guards that CodeQL's type inference reads as comparing a non-null value to null.

| Site | What the code does | Verdict | Action |
|---|---|---|---|
| `apps/web-platform/server/account-delete.ts:849` (`:850` after this PR) | Formats the failure detail inside `if (anonOrgErr)`, so `anonOrgErr` is already truthy and the `!== null` is always true. The erasure abort and the Sentry mirror happen before this line and are unchanged. | Redundant check, harmless | Removed the redundant comparison and added a test pinning the stable contract of the abort message (stage prefix, non-empty detail, `message` used when present). The alert clears on the next scan of `main`. |
| `apps/web-platform/server/dsar-export.ts:285` | `isPlainObject` is a standalone `v is Record<string, unknown>` type guard. `typeof null === "object"`, so the `v !== null` is required for the guard's own contract. Within this file its only caller (`dsarNormalize`, line 302) returns on null first, which is what the analysis keys on. | False positive | No production change and no new test: `isPlainObject` is unexported and unreachable with null through `dsarStringify`, so a test cannot discriminate the guard. Alert dismissed as a false positive on 2026-10-15; GitHub's dismiss action takes no reason field, so the reason is recorded here. Dismissed list: `https://github.com/jikig-ai/soleur/security/quality/rules/js%2Fcomparison-between-incompatible-types?query=is%3Adismissed` (reopen from there). |

No GDPR-sensitive behavior changed, so no Art. 33 assessment was needed.

Observation, not changed here: this stage interpolates the raw RPC error message into the `result.error` that the account-delete route returns to the client, while the sibling anonymise stages return a generic message. That was added deliberately in #4553 and the same error is mirrored to Sentry; changing what a user sees on a failed erasure is a product decision outside PR1.

## Final snapshot before disable (2026-10-19, slice 4 of #10331)

Read from the repository's Code Quality alert list (Standard findings, filter `is:open`) at about 20:50 local on 2026-10-19, with no new scan triggered. Python findings were last seen at 18:38Z and JavaScript findings at 18:41Z, both on `main` at `b3dca43` (the head of `main` at that moment, so the scan includes the handler fixes of #10375 and #10503 and the baseline drawdown of #10579). Totals: 112 open findings (Maintainability 70 "Fair", Reliability 42 "Poor") across 23 rules, against 22 rules on 2026-10-14.

| Rule | Open | Severity | Language | Change since 2026-10-14 |
|---|---|---|---|---|
| js/unused-local-variable | 47 | Note | JavaScript | 60 to 47 |
| py/file-not-closed | 18 | Warning | Python | 36 to 18 |
| js/trivial-conditional | 8 | Warning | JavaScript | 8 |
| js/useless-assignment-to-local | 8 | Warning | JavaScript | 8 |
| js/superfluous-trailing-arguments | 7 | Warning | JavaScript | 7 |
| py/unused-global-variable | 5 | Note | Python | 4 to 5 |
| js/overwritten-property | 2 | Error | JavaScript | 2 |
| py/unused-import | 2 | Note | Python | 5 to 2 |
| js/comparison-between-incompatible-types | 1 | Warning | JavaScript | 2 to 1 (one was fixed and one dismissed as a false positive on 2026-10-15, see above; which alert is still open was not identified in this snapshot) |
| js/regex/duplicate-in-character-class | 1 | Warning | JavaScript | |
| js/regex/unmatchable-caret | 1 | Error | JavaScript | |
| js/string-instead-of-regex | 1 | Warning | JavaScript | |
| js/useless-assignment-to-property | 1 | Warning | JavaScript | |
| js/useless-comparison-test | 1 | Warning | JavaScript | |
| py/catch-base-exception | 1 | Note | Python | 5 to 1 |
| py/comparison-of-identical-expressions | 1 | Warning | Python | |
| py/implicit-string-concatenation-in-list | 1 | Warning | Python | new |
| py/import-and-import-from | 1 | Note | Python | new |
| py/imprecise-assert | 1 | Note | Python | new |
| py/mixed-returns | 1 | Note | Python | |
| py/procedure-return-value-used | 1 | Warning | Python | |
| py/regex/duplicate-in-character-class | 1 | Warning | Python | |
| rb/useless-assignment-to-local | 1 | Warning | Ruby | |

`py/empty-except` (20 findings on 2026-10-14) is absent from the open list, and its rule page returns 404. This is the verification issue #10381 asked for: a scan of the current head of `main`, taken after the handler PRs merged, shows no open `py/empty-except` finding in any file. The issue gives per-file counts (proxy 4, scan-ancestor 1, redact-engine 2) and does not name file paths; the five files in the plan are derived from those counts, and the rule is absent everywhere, so the derivation does not change the verdict. `py/unused-local-variable` (2 findings on 2026-10-14) is also absent from the open list now.

The AI-findings panel read 0 findings. The alert list is UI-only (the REST API does not return these alerts), so this table is the last record of it before the feature is switched off.

Code scanning state captured before the disable, to be compared after it: `GET repos/jikig-ai/soleur/code-scanning/default-setup` returned `state: configured`, languages `actions, javascript, javascript-typescript, python, typescript`, `query_suite: extended`, `threat_model: remote`, `schedule: weekly`, `runner_type: standard`, `updated_at: 2026-07-20T10:09:47Z`. Workflow `CodeQL - Code Quality` (id 343194280) was `active`. Every push to the PR branch started both a `PR #N` run (code scanning) and a `Code Quality: PR #N` run (Code Quality), for example head `54d6948` of the slice-4 PR.

## Disable result (2026-10-19, slice 4 of #10331)

Code Quality was turned off on 2026-10-19 around 20:51 local (18:51Z) through the repository settings page (Settings, Security and quality, Code quality, "Code Quality analysis" toggle). The AI findings "Scans" toggle on the same page was already Off, and was left as it was. A reload showed the page offering "Enable code quality" (the off state).

Checks after the change:

- Runs: heads pushed before the change (`f5c0d9f`, `7f60e4d`, `54d6948` of the slice-4 PR) each started both a `PR #10605` run and a `Code Quality: PR #10605` run. Head `79ff915`, pushed after the change, started only `PR #10605` (code scanning). A second PR's push at 18:52:52Z (`4df7c14`, `PR #10525`) also started no `Code Quality: PR` run.
- Code scanning default setup is identical to the capture above (`state: configured`, same languages, `extended` suite, `weekly` schedule).
- The 2026-10-14 sections above describe the operator re-enabling Code Quality that day; the usage meter shows daily charges continuously from 2026-09-22 (sporadic lines before that), so the feature was already billing before the 2026-10-14 re-toggle.
- Caveat: `GET repos/jikig-ai/soleur/actions/workflows/343194280` still returns `state: active` (`updated_at` 2026-09-03) after the change. The dynamic workflow object stays listed; the absence of new `Code Quality: PR` runs is the evidence that it is off, and it is re-read at the postmerge step.
