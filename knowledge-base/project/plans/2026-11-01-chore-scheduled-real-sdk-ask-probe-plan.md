---
title: "chore(security): scheduled real-SDK probe on SDK bump and a synthetic hosted-ask canary for the must-ask lane"
date: 2026-11-01
slug: scheduled-real-sdk-ask-probe
branch: feat-one-shot-10111-sdk-probe-schedule
issue: 10111
closes: none
type: chore
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# chore(security): automate the real-SDK ask probe (Part 1 of #10111); the synthetic canary (Part 2) is scoped out

## Enhancement Summary

**Deepened on:** 2026-11-01
**Sections enhanced:** Premise Validation, Research Insights, GDPR gate, Phase 4 (pins), verification record below
**Agents / gates used:** CTO (3 spawns), CLO, CPO, learnings-researcher, functional-discovery (no overlap), code-simplicity-reviewer, architecture-strategist, a sharp-edges verification agent over the catalogue, `soleur:gdpr-gate`; mechanical halts 4.4, 4.6, 4.7, 4.8, 4.11, 4.12, 4.13 run and passed (4.9 and 4.10 not triggered).

### Key Improvements

1. The CTO's closure-coverage test was falsified by measurement (189-file closure) and replaced by a depth-1 coverage test with a classification table (Guard 1).
2. Review found and the plan now fixes: the rerun silently doubling the $4 cap (shared remaining budget), an evicted-run hole in the lockfile early-exit (baseline = last completed non-cancelled run), a silent-red path when setup fails (empty outcome files the blind issue), a `pr-fanout-ledger.txt` row owed by any `on: pull_request`, unscoped forbidden-token ACs that would match the plan itself, and a merge-base form for the "does not touch X" ACs.
3. The CPO condition (`Ref`, not `Closes`) superseded the first F6 ruling; #10111 is the single tracked deferral (no new issue, nothing for net-issue-flow to override).

### New Considerations Discovered

- The Article 30 register was already stale before this change (`scheduled-machinery-drain.yml` missing from PA-33); the compliance edit fixes it in the same pass.
- Re-evaluation criterion 1 had already fired before this PR, so ADR-284 Flip criterion 5 is currently unmet on `origin/main`; the first self-test run is also the overdue re-run.
- A scheduled PASS runs repo head on a CI host and so can never discharge Flip criterion 1 or 5 without a `build_sha` match.

## Overview

Issue #10111 (child of epic #9601) asks for two automations around the hosted must-ask lane (ADR-284, status `adopting`):

1. **A scheduled / on-change run of the real-SDK probe** `apps/web-platform/scripts/dev-probe-destroy-ask.ts`, the only check that exercises hook-then-`canUseTool` precedence against the real SDK and bundled CLI. Today its re-run is a human step.
2. **A synthetic hosted ask canary**, a production write that would observe arrival of the lane's pino line and Sentry event in the production sinks.

**Scope narrowing (recorded on purpose).** This plan builds Part 1 only. Part 2 is a production write the issue itself says needs explicit operator authorisation before it is built, and the brief confirms the hold. Nothing in this PR emits into a production sink. Part 2 is carried by issue #10111 itself, which the work phase edits in place into the Part 2 tracker under an `Operator-reserved:` hold (CTO ruling, Option Y; PR body uses `Ref #10111`, never `Closes`, per the CPO condition). The PR files no new issue and closes none, so the net-issue-flow gate has nothing to override.

**What ships (Part 1):**

- A non-required, non-blocking workflow `.github/workflows/scheduled-real-sdk-ask-probe.yml` (push to main on a narrow path set, a weekly cron, `workflow_dispatch`, and a same-repo-only self-test run on edits of its own files) running the probe on a direct `ubuntu-latest` runner with the CI-partitioned `ANTHROPIC_API_KEY` repo secret.
- A committed runner script `apps/web-platform/scripts/real-sdk-ask-probe.sh` (`should-run`, `run`, `file-issue`) so the exit-code mapping, rerun policy and issue dedupe are testable offline.
- Probe additions: measured `costUsd` per case and in total, a $4 per-run hard cap (`maxBudgetUsd` per case plus a cumulative stop), and a distinct `CANT-RUN:budget-exceeded` outcome.
- Two deduped GitHub issues as the failure surface: "regression" (p1, human-closed) and "blind" (p2, self-closing on a later PASS).
- An ADR-284 amendment (no new ADR), one `model.c4` edge-description update, and factual compliance upkeep (Article 30 PA-33, `expenses.md`, `api-spend-reconciliation.md`, LIA/DPIA one-liners).

**What does not ship:** a synthetic canary, any production-sink emission, any feature flag, any toggle or legal-document wording change beyond the factual register upkeep the control itself requires, any CI-gating of the live probe (CTO 2026-10-12, reaffirmed), a Sentry cron heartbeat.

## Premise Validation

Checked before the research fan-out:

- **#10111** is `OPEN`, milestone "Phase 4: Validate + Scale", labels `priority/p2-medium`, `type/chore`, `domain/engineering`; no closing PR. Epic **#9601** `OPEN`. Draft PR **#11784** is this branch's own PR (the collision pre-check hit is our own, not a duplicate).
- **Cited artifacts exist on `origin/main`:** the probe (466 lines), `sdk-bump-sandbox-gate.sh` (+ its `.test.sh`), ADR-284 (`status: adopting`), `ci.yml` jobs `sandbox-canary-capture-gate` and `plugin-root-propagation-gate`. The probe is *built*, not "never built"; the plan shape is *automate an existing check*.
- **Mechanism vs the ADR corpus.** ADR-284 does not reject scheduling the probe (its Flip checklist names #10111 as the follow-up in three places). ADR-079 deferral B (creds-gated real-argv capture) is the sibling precedent. ADR-033 prefers Inngest crons for scheduled work; the hook `new-scheduled-cron-prefer-inngest` accepts an override for repo-scoped, CI-key-only work with no prd credentials (precedent `scheduled-integration-suites.yml`), which holds here. ADR-244 governs the CI key ($100/month workspace cap).
- **ADR corpus grep** (mechanism nouns, not the issue number): `git grep -il -e bwrap -e apparmor -e 'scheduled-' -e canUseTool -e anthropic-preflight -- knowledge-base/engineering/architecture/decisions` dispositioned: ADR-284 (amended here), ADR-079 (sibling, creds-gated capture, no rejection of a scheduled probe), ADR-033 (Inngest preference, handled by the override), ADR-244 (key partition, applied). No ADR lists a scheduled probe among its rejected alternatives. No new ADR ordinal is claimed, so the ordinal-collision class does not apply.
- **Stale premises found:** (a) the issue says the re-run "is enforced only by a human acknowledgement (`sdk-bump-sandbox-gate.sh`)"; that gate fires only on a lockfile SDK version change and its capture-gate trigger set is sandbox-config and outer-wrap files, so it cannot see `permission-callback.ts`, `sandbox-hook.ts` or `destroy-ask-*` changes (the actual causes of #10054). (b) `api-spend-reconciliation.md` and the Article 30 register's PA-33 snapshot are already stale (the register omits `scheduled-machinery-drain.yml`; CLO finding), which the compliance upkeep task must fix in the same edit.

## Re-evaluation Criteria (decision: has any fired?)

| # | Criterion (any one) | Evidence | Verdict |
|---|---|---|---|
| 1 | Any SDK, bundled-CLI or sandbox-option bump lands | `git diff dfb9e2dba5 HEAD` (the 2026-10-12 fix deploy) over `apps/web-platform/server/{agent-runner-sandbox-config,sandbox-hook,agent-runner-query-options,permission-callback}.ts` shows +1312/-1324 lines across 4 files (#11303 pre-approval guard, #10455 unix-deny seccomp selector, untrusted-content hooks, durable approval slice). The SDK pin (0.3.284) and claude-code (2.1.293) are unchanged. `sdk-bump-sandbox-gate.sh` cannot see any of it. | **FIRED** (sandbox-option / hook / option-builder class). This is also ADR-284 Flip checklist criterion 5 being violated: the probe has to be re-run on the current build. The first scheduled/self-test run is that re-run. |
| 2 | First workspace with more than one active member uses autonomous mode | not measurable from the repository | not claimed |
| 3 | First external founder | not measurable from the repository | not claimed |
| 4 | 7-day soak closes with zero natural asks and no accepted substitute | the soak window closed 2026-10-19T08:40Z but ADR-284 is still `adopting`, #9776 and #9976 are open, and no soak numbers are recorded; the substitute acceptance is an operator decision (Flip criterion 4) | not demonstrably fired; stays with the operator, untouched |

Criterion 1 alone justifies Part 1. It does not touch Part 2.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality | Plan response |
|---|---|---|
| Mechanism "`soleur:schedule` (a cron workflow) or a job gated on the paths the acknowledgement gate already watches" | `soleur:schedule` generates `claude-code-action` workflows that run a Soleur *skill*; the probe is a bun script, so the wrapper adds nothing (curl-vs-wrapper test). A new `scheduled-*.yml` with `schedule:` trips the ADR-033 hook. The ack gate's watched paths are a different, narrower set than the probe's inputs. | One hand-written workflow (CTO F1) with the gate-override marker + justification; own push path set (CTO F2). |
| "It needs an Anthropic key and a model call: check the repo's existing secret/Doppler/CI conventions and budget" | Precedent: `secrets.ANTHROPIC_API_KEY` repo secret in `ci.yml` real-turn gates, `fix-constraints-stage-a.yml`, `scheduled-machinery-drain.yml`; key lives in the `soleur-ci-eval` Console workspace, $100/month cap, $80 notice (ADR-244, #8505); `anthropic-preflight` soft-skips a cap hit; the documented probe command uses Doppler `ci` but the probe itself reads only `ANTHROPIC_API_KEY`, `NODE_ENV`, `PATH`, `HOME`. | Repo secret, no Doppler (CTO F5). Self-test run verifies nothing else is needed. |
| Probe "cost is not measured" | True; the SDK result frame carries `total_cost_usd` and options accept `maxBudgetUsd` (verified in `sdk.d.ts`). | Probe prints measured cost; $4 cap enforced (CTO F3). |
| CTO F2 premise: "test that the filter covers the probe's static import closure" | Measured: closure is **189 files** (186 under `server/`) because the probe imports `permission-callback` -> `agent-runner` -> most of `server/`. | Superseded by the CTO's second ruling: narrow allowlist + depth-1 coverage test with an explicit classification table. |
| ADR-284: "nothing in CI does" / "criterion 5 is the only guard" | After this PR a non-blocking automated guard exists for the files in the filter. | ADR amendment rewrites those sentences. |

## Research Insights

### Property List (Phase 0.6b)

- **P1.** After a change to the SDK pin, the bundled CLI, a sandbox option, a hook or the option builder reaches main, the hook-then-`canUseTool` precedence is re-checked against the real binary without a human having to remember.
- **P2.** Drift not caused by a diff (model behaviour, an unpinned transitive, the runner image) is caught on a bounded cadence.
- **P3.** A regression is surfaced loudly and deduped; a run that could not measure is distinguishable from a pass and never reads as green.
- **P4.** The paid, nondeterministic call is non-blocking, capped per run, and bounded per month inside the existing CI-key cap.
- **P5 (Part 2).** Arrival of the lane's pino line and Sentry event in the production sinks is observed. Operator-reserved production write: **not built**.

### Cut List (Phase 0.6b)

| Mechanism | Property | Disposition |
|---|---|---|
| Part 2 synthetic hosted-ask canary (named by the issue) | P5 | **Cut from this PR**: production write needing explicit operator authorisation; tracked in #10111 (edited in place). |
| Make the probe a required / PR-gating check | P1 | Cut: CTO 2026-10-12 ruling (nondeterministic paid call; deterministic subset exists). Reaffirmed 2026-11-01 (F1). |
| Extend `sdk-bump-sandbox-gate.sh` or its `ci.yml` capture gate to run the probe | P1 | Cut: neither covers the probe's inputs (`permission-callback.ts`, `sandbox-hook.ts`, `destroy-ask-*`); the capture gate runs in `node:22-slim` with a bwrap PATH shim and checks argv drift, a different property; both are PR-time, which re-introduces the gate. |
| Sentry cron heartbeat + cron-monitors entry | P3 | Cut (F4): infra change and `model.c4` count moves for one weekly non-blocking job; the issue + summary + artifact are the surface. Residual named in the ADR. |
| `PROBE_DECODE_ONLY` offline mode in the scheduled run | P3 | Cut: it execs the soak script slated for retirement at the ADR flip; not part of the property. |
| `soleur:schedule` / `claude-code-action` wrapper | P1 | Cut (curl-vs-wrapper): the probe is a bun script. |
| Doppler `ci` config read in the workflow | P1 | Cut (F5): a second secret to read one value. |

| Scheduling the sibling real-SDK probe `apps/web-platform/scripts/dev-probe-approval-gate.ts` (#11303, gated-tier allowlist property) | different property (pre-approval bypass, not the must-ask lane) | Out of scope for #10111; recorded here so the next reader sees it was considered. Not filed as an issue (`wg-defer-only-after-inline-triage`: no re-evaluation trigger distinct from this one). |

Authority grepped for "does something already run the probe": `git grep -ln 'dev-probe-destroy-ask\|dev-probe-approval-gate' -- . ':!knowledge-base'` returns `apps/web-platform/scripts/dev-probe-approval-gate.ts`, `dev-probe-destroy-ask.ts`, `apps/web-platform/test/agent-sandbox-seccomp-selector.test.ts`, `apps/web-platform/test/approval-guard1-mutation.test.sh`, `apps/web-platform/test/cc-dispatcher-real-factory.test.ts` and the soak script `scripts/followthroughs/hosted-destroy-ask-window-9776.sh`; none is a workflow, so nothing schedules or gates either probe.

### Value-proposition measurement (Phase 0.6c)

The cost justification is a *bound*, not a saving. Commands that produced the numbers (all measured 2026-11-01 on `origin/main`):

- Probe import closure size (the Phase 0 extractor re-derives this and the Guard 1 floors): a 20-line resolver over relative imports starting at the probe (script kept in the session scratchpad) printed 189 files, 186 under `server/`.
- Main push volume over the last 30 days: `git rev-list --first-parent --since=2026-10-02 origin/main | wc -l` = 87.
- Push runs under each filter: the exact Phase 4 allowlist (`git rev-list --first-parent --since=2026-10-02 origin/main -- <the 11 existing allowlist paths incl. plugins/soleur/hooks> | wc -l`) = **10** commits (the two new scripts and the workflow do not exist at origin/main, so add none); exact closure + package files = **15**; `server/**`+`lib/**`+`scripts/**`+package files = **25** (`git rev-list --first-parent --since=2026-10-02 origin/main -- <paths> | wc -l`).
- Plugin hook directory churn: 1 commit in 30 days (`plugins/soleur/hooks`, `plugins/soleur/.claude-plugin`).
- Per-run cost: **unmeasured**; the first self-test run measures it (`costUsd`). Run-count basis for the ceiling: 10 push + ~4 cron (weekly) + ~2 self-test = ~16 runs/month. The $1.5 figure used for the ceiling is an UNVERIFIED planning estimate.

### Deepen-pass verification record (2026-11-01)

- **SDK semantics (docstring verbatim, `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts`):** `maxBudgetUsd?: number;` — "Maximum budget in USD for the query. The query will stop if this budget is exceeded, returning an `error_max_budget_usd` result." (lines 1921-1925); result `subtype: 'error_during_execution' | 'error_max_turns' | 'error_max_budget_usd' | ...` (line 5609); `total_cost_usd: number` — "Cumulative estimated cost in USD for this query() call ... each result carries the running total so far, so read the latest result rather than summing across results ... An estimate, not a billing statement." (lines 5612-5618). Consequences kept in the plan: per-case cost is the latest `total_cost_usd`, the ledger sums across CASES (each case is its own `query()`), and cost is an estimate to be compared with the workspace spend view, not an invoice.
- **Action pins (40-char SHAs already in use, counts from `git grep -hE 'uses: <action>@[0-9a-f]+' .github/workflows`):** `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5` (193 uses, v4.3.1), `oven-sh/setup-bun@3d267786b128fe76c2f16a390aa2448b815359f3` (19, v2.1.2), `actions/setup-node@49933ea5288caeca8642d1e84afbd3f7d6820020` (18, v4.4.0), `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02` (27, v4.6.2). The workflow reuses exactly these (no new pin is introduced); the workflow suite asserts every `uses:` is a 40-hex SHA.
- **Cited issues/PRs read live:** #10054, #9776, #9976, #9601, #10455, #7098, #7942, #8800, #8881, #7797, #7125, #11237, #9543 OPEN; #11303 (the gated-tier `allowedTools` fix) CLOSED; #8505 (CI key partition) CLOSED; #11442 MERGED; #11669 CLOSED.
- **Rule ids cited** all resolve to active rules (`grep -qE "\[id: <id>\]" AGENTS.md AGENTS.rules.md` for every id in this plan: none missing).
- **Scheduled-work pattern (4.4):** Inngest cron functions exist (ADR-033 canonical); the GHA exception holds because the work is repo-scoped test execution with the CI key and no prd credentials, needs no app context and gains nothing from `step.run` replay; the PreToolUse override marker plus justification is the sanctioned form (precedent `scheduled-integration-suites.yml`).
- **Precedent diff (4.4, pattern-bound behaviours):** the bubblewrap + socat + userns-sysctl step is copied from `ci.yml` (lines ~1374-1380, also `main-health-monitor.yml`); the file-or-comment / auto-close issue filer follows `scheduled-realtime-probe.yml` with the two deliberate differences (exact-title `jq` equality instead of fuzzy `--search`; the regression issue is never auto-closed). No precedent exists for the `actions: read` baseline lookup or for a two-class issue filer; both are novel and are covered by Guards 3 and 4.
- **Verify-the-negative sweep (4.45):** negative claims in the plan checked against the repo — "no workflow runs the probe" (re-grepped, confirmed above); "the probe reads nothing beyond `ANTHROPIC_API_KEY`/`NODE_ENV`/`PATH`/`HOME`" (grep of `process.env` in the probe shows `PROBE_*` diagnostics only; the production option builder `buildAgentEnv` is allowlisted and the self-test is the final arbiter); "no `ci.yml` edit" (none planned).
- **Post-edit self-audit (4.45):** after the review-round edits no symbol was dropped; the removed items (Phase 0.2 grep, 600 s rerun gate, `cost=unknown` flag, Guard 1 H3, xtrace scenario in the runner suite) were grepped out of the plan, tasks.md and decision-challenges.md.

### GDPR gate output (soleur:gdpr-gate, plan scope)

**This is not legal review. Findings are heuristic. Consult `soleur:legal:clo` + `soleur:legal:legal-compliance-auditor` before merging.**

gdpr-gate: path scan complete — 0 examined, 0 matched (the plan edits no schema migration, `lib/auth`, `server/*auth*`, `app/api` or `.sql` path; `permission-callback.ts` is read by the new test, not edited).

- `GDPR-Chapter-V` — **Suggestion.** The probe sends fixed synthetic prompts and public plugin descriptions to Anthropic under the existing Jikigai key; no new non-EEA vendor, no new env var class. Disposition: PA-33 member (9) plus the `compliance-posture.md` dated row (already tasks 6.3).
- `GDPR-Art-6`, `GDPR-Art-5e`, `GDPR-Art-17`, `GDPR-Art-9`: no schema column or personal-data store introduced; the 90-day artifact holds probe stdout only. No `Critical` finding, so no escalation block and no `compliance/critical` issue.
- Cross-controller trigger (a) (new processing using an external LLM API on operator-session-derived data): the data is not operator-session-derived; the CLO ruling above stands.

### Institutional learnings applied

- `2026-10-11-a-mocked-sdk-could-not-see-the-permission-callback-never-ran.md`: a run where the model did not call Bash is CANT-RUN, never PASS; the probe drives the real SDK and production option builder, no `pathToClaudeCodeExecutable`.
- `2026-04-19-llm-sdk-security-tests-need-deterministic-invocation.md`: verdict separates "model did not attempt" (CANT-RUN) from "tool call happened and the gate did not fire" (FAIL).
- `2026-07-27-a-check-that-cannot-report-is-indistinguishable-from-one-that-passed.md`: the runner requires `RESULT: PASS` *and* exit 0 *and* the full case count; the step cannot be skipped by `if:`.
- `2026-09-24-routing-59-cron-monitors-every-guard-was-narrower-than-its-name.md`: path-filter coverage is a guard with its own contract (below).
- `best-practices/2026-07-02-self-validating-regression-when-runtime-capability-unverifiable-locally.md`: `ubuntu-latest` defaults `kernel.apparmor_restrict_unprivileged_userns=1`; set the sysctl as `ci.yml` does; a bwrap uid-map failure is CANT-RUN, not FAIL.
- `2026-03-21-github-actions-heredoc-yaml-and-credential-masking.md`: build issue bodies with `printf` + `--body-file`; `gh issue list --search` is fuzzy, so dedupe by exact `jq` title match.
- #7797 / `knowledge-base/engineering/operations/post-mortems/bash-x-credential-trace-exposure-postmortem.md`: runner script carries the xtrace refusal (`scripts/lint-shell-trace-credential-refusal.py` Rule A and B).
- ADR-244: a cap hit never pages; non-preflighted consumers fail at the cap, so this workflow runs `anthropic-preflight` first.

### Open Code-Review Overlap

Open `code-review` issues naming a planned file: **#8800** (touches `scripts/lib/test-affected-paths.sh`: census-sandbox write-through fixture hazard) and **#8881** (`scripts/suite-shard-legs.tsv` rebalance record), **#7098** (audit of `run:` bodies whose `set` omits `-e`, `.github/workflows/`), **#7942** (mutation batteries named `*.mutation.sh` run in no gate). Disposition: **acknowledge** all four, different concerns. Two consequences are folded in without closing them: the new workflow's `run:` steps use `shell: bash` with an explicit `set` line (#7098's class), and the new suites are named `*.test.sh` and registered through the mechanisms cited in AC15 (#7942's class). Directory-wide matches (`apps/web-platform/scripts/`, `.github/workflows/`) are noise from issue bodies naming the directory.

## Domain Review

**Domains relevant:** Engineering (CTO), Legal (CLO), Product (CPO sign-off for the single-user-incident threshold). Finance, Operations, Marketing, Sales, Support: no implications beyond the bounded spend inside the existing key and cap (below).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** three spawns, all recorded in `knowledge-base/project/specs/feat-one-shot-10111-sdk-probe-schedule/decision-challenges.md`. Decisions: F1 one non-required workflow on a direct runner; F2 narrow allowlist + depth-1 coverage test (closure test withdrawn after the 189-file measurement); F3 default model, `costUsd`, $4/run cap, $25/month ceiling, $2.50 review trigger; F4 exit-code mapping and two deduped issues, no Sentry heartbeat; F5 repo secret; F6 build no canary, then Option Y for #10111; F7 amend ADR-284, edit one C4 edge description, do the compliance upkeep. The cost/cadence delegation came from the operator brief ("rule via the CTO on cost/cadence") and the spend stays inside the already-authorised key and cap (ADR-244), so no operator row is raised.

### Legal (CLO)

**Status:** reviewed
**Assessment:** `Ruled by CLO agent, 2026-11-01`: the workflow is a PA-33 member under the secret-keyed predicate; no new processor, no new data category, no public claim, nil personal data (synthetic commands + public plugin descriptions; PR-head source never read by the model); no operator decision. Register edits: PA-33 (a), (c), (d), (f), (g) + member block; (b), lawful basis, (e), Art. 9/10, (h) unchanged. The register is already stale (`scheduled-machinery-drain.yml` is a missing member, plus two unnamed non-members), so the count sentence is corrected in the same edit. v1 internal sign-off on a draft that needs a lawyer's review. Wording is applied by the work phase; legal documents other than the factual register/LIA/DPIA upkeep, and all toggle copy, stay untouched.

### Product (CPO)

**Status:** reviewed
**Assessment:** sign-off YES with conditions, carried as acceptance criteria: every user-visible string carries the host-only residual and "production arrival not observed" and never says "verified in production"; a green run never closes a regression issue (it may add a "subsequently passed" note); the probe must be able to go red on an inert lane (negative control); the workflow is non-blocking and its path-set miss is documented; `Ref #10111`, not `Closes`; no agent records the operator's acceptance of the Flip-criterion-4 substitute; failure-issue body links the ADR-284 C9 result and the 2026-10-11 post-mortem.

No UI surface (no `components/**`, `app/**/page.tsx`, `layout.tsx` in Files to Create/Edit): the Product/UX gate tier is NONE.

## User-Brand Impact

- **If this lands broken, the user experiences:** a hosted autonomous session that can force-push over the default branch or run an infrastructure teardown command with no Approve card (the lane silently inert again, as in #10054), while the product tells the founder their work is backed up; a broken probe would let that stay unnoticed through the next SDK/option-builder change. A probe that false-alarms instead trains maintainers to ignore the p1 issue.
- **If this leaks, the user's workflow / money is exposed via:** the CI-partitioned `ANTHROPIC_API_KEY` reaching logs or an artifact (xtrace, an echoed env, a stdout line), or PR-head probe code reading it on the self-test run; blast radius is the `soleur-ci-eval` workspace ($100/month cap), never the production key (ADR-244).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** inherited from ADR-284 (`brand_survival_threshold: single-user incident`): this is the detection control for that ADR's exposure; `aggregate pattern` would under-weight a single founder losing default-branch history.

`requires_cpo_signoff: true` is set; the CPO sign-off above covers plan time. `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-284** (no new ADR; CTO F7). Status stays `adopting`; Flip criteria 4 and 6 (operator-reserved arrival evidence) are not touched; no agent records any acceptance. Edits, all in the work phase:

1. `### Runtime proof`, last paragraph ("Re-run the probe ... nothing in CI does"): replace with a pointer to the amendment.
2. `## Flip checklist`, criterion 5 and the closing sentence ("the follow-up that does is #10111 ... until it exists criterion 5 above is the only guard"): reword to say a non-blocking automated guard now covers the filtered files and criterion 5's human check remains for everything outside the filter.
3. New `## Amendment 2026-11-01 (#10111, Part 1)`: the workflow and its trigger set; the cap numbers ($4/run, $25/month, $2.50 review trigger and the concrete reduction shape); outcome mapping; the **host-only statement** ("the real-SDK probe passes against the deployed SDK, CLI and option builder on a CI host with host bwrap; production telemetry arrival is not yet observed"; never "verified in production"); residuals: no heartbeat (a never-ran/disabled schedule is not detected), nondeterminism, a change outside the filter is caught only at the next weekly cron, the self-test run executes the same-repo PR-head tree with the key in the probe step's environment (same posture as the `ci.yml` real-turn gates; fork PRs and the Dependabot actor excluded); a scheduled PASS runs repo head on a CI host, so it never discharges Flip criterion 1 or 5 without a `build_sha` match against the deployed build, and the workflow reads the repo secret where the documented command uses Doppler `ci`; a two-line pointer that Part 2 lives in #10111 under an `Operator-reserved:` hold.
4. Record the re-evaluation verdict (table above) in the amendment.

### C4 views

C4 completeness check (all three model files read: `spec.c4` in full; `views.c4` include lists for context/containers/components; `model.c4` element declarations and relationships at lines ~395-405 and ~600-730):

- External human actors: the founder (`founder`) reads the failure issues, already modeled. The contributor (`contributor`) gets no new relationship: the self-test run is same-repo only and fork authors get no secrets.
- External systems: Anthropic (`anthropic`) and GitHub (`github`) only, both modeled; the edge `github -> anthropic` ("CI Claude turns (claude-code-action, ci.yml real-turn gates) on the soleur-ci-eval workspace key ...", `model.c4` line ~727) already exists and renders in the context view (both endpoints are in its include list). No Doppler, Sentry or Better Stack edge is added.
- Containers/data stores: none; the artifact and job summary live under `github`.
- Actor-surface access relationships: unchanged.

Only change: extend the **description** of the `github -> anthropic` edge to name the scheduled real-SDK probe (host-bwrap, same CI key, non-blocking). No new element, no new edge, no heartbeat, so no derived count moves. Validation: `plugins/soleur/test/c4-count-parity.test.sh`, `apps/web-platform/test/c4-code-syntax.test.ts`, `apps/web-platform/test/c4-render.test.ts`, and the committed-artifact freshness suite (`plugins/soleur/test/c4-model-freshness.test.sh`, regenerated with `scripts/regenerate-c4-model.sh`).

### Sequencing

The ADR describes the shipped state now (a workflow that runs weekly and on filtered pushes); the soak/flip stays a separate later PR.

## Task Design

```yaml
tasks:
  - task: scheduled-real-sdk-ask-probe (.github/workflows/scheduled-real-sdk-ask-probe.yml)
    trigger: push to main on a narrow path allowlist (early-exits when only package files changed and neither SDK version moved since the last completed run), a weekly Monday 09:17 UTC cron, workflow_dispatch, and a same-repo pull_request limited to edits of the workflow and the three files that execute with the key
    services: reads the repo checkout and the SDK packages from npm; calls the Anthropic Messages API through the SDK on the CI-partitioned key; writes a job summary, a 90-day Actions artifact, and (filer job only) GitHub issues in this repository
    next: nothing automatic; a FAIL files the p1 regression issue and a blind run files the p2 blind issue, which a human triages
    human_reentry: comment on the tracking issue; rerun with gh workflow run scheduled-real-sdk-ask-probe.yml (post-merge only; pre-merge verification is the own-file pull_request run); stop it with soleur:cron-delete or by disabling the workflow; the regression issue is closed only by a human
    dedupe: the filer matches open issues by exact title through a jq equality filter (never the fuzzy search) and comments on the existing issue instead of creating a second; the runner reruns the whole probe at most once, on the remaining budget, and never on budget-exceeded; lockfile-only pushes early-exit when neither SDK version moved
    source_dedupe: the exact-title match is the ticket-source dedupe (one open issue per class, titles "[ci/real-sdk-ask-probe] real-SDK ask probe regression" and "[ci/real-sdk-ask-probe] real-SDK ask probe blind")
```

## Observability

```yaml
liveness_signal:
  what: GitHub Actions run history of scheduled-real-sdk-ask-probe.yml plus the RESULT line in each job summary (layer: GitHub Actions run log, CI layer; no Sentry heartbeat by CTO ruling F4)
  cadence: weekly cron (Monday 09:17 UTC) plus every qualifying push to main
  alert_target: GitHub issue labelled ci/real-sdk-ask-probe (regression p1, blind p2) in jikig-ai/soleur
  configured_in: .github/workflows/scheduled-real-sdk-ask-probe.yml and apps/web-platform/scripts/real-sdk-ask-probe.sh

error_reporting:
  destination: job summary, 90-day artifact real-sdk-ask-probe-<run_id>, and the two deduped GitHub issues (the probe's own Sentry capture is an in-process transport by design and never leaves the process)
  fail_loud: job concludes red and the filer job opens or comments on the regression or blind issue; a billing skip prints SKIPPED in the summary with a ::warning::

failure_modes:
  - mode: lane inert again (probe verdict FAIL, exit 1)
    detection: runner classifies RESULT FAIL plus exit 1 as outcome=fail
    alert_route: regression issue (p1) opened or commented
  - mode: probe could not measure (CANT-RUN, diagnostic, crash with no RESULT line, budget exceeded)
    detection: runner outcome=blind after one whole-probe rerun (none for budget-exceeded or no key)
    alert_route: blind issue (p2) opened or commented; closes itself on a later PASS
  - mode: setup or runner failure leaves no outcome (npm or apt failure, step timeout, preflight exit 1, crash before classify)
    detection: probe job red with an empty outcome output; the filer maps it to blind / no-outcome
    alert_route: blind issue (p2) opened or commented
  - mode: Anthropic spend cap or transient API error before the run
    detection: anthropic-preflight output ok=false
    alert_route: workflow warning and SKIPPED summary only, job green, never counted as a pass; retried at the next trigger
  - mode: schedule never fires or the workflow is disabled
    detection: not detected (accepted residual per CTO ruling F4, no heartbeat); recorded in the ADR-284 amendment
    alert_route: none by design; the criterion-5 human check at flip time is the backstop
  - mode: a code change outside the push filter re-inerts the lane
    detection: next weekly cron run
    alert_route: regression issue

logs:
  where: Actions run log, job summary, and artifact real-sdk-ask-probe-<run_id> (redacted stdout of the probe)
  retention: 90 days

discoverability_test:
  command: grep -cF "17 9 * * 1" .github/workflows/scheduled-real-sdk-ask-probe.yml
  expected_output: 1
```

## Files to Create

| File | Purpose | Provenance |
|---|---|---|
| `.github/workflows/scheduled-real-sdk-ask-probe.yml` | the workflow (jobs `probe` and `file-issue`) | asked: "A scheduled or on-change run of the real-SDK probe" |
| `apps/web-platform/scripts/real-sdk-ask-probe.sh` | `should-run`, `run`, `file-issue` subcommands; xtrace refusal; exit-code mapping; rerun policy; summary text | inferred: the exit-code mapping and issue dedupe must be testable offline or the guard rots in YAML |
| `apps/web-platform/scripts/real-sdk-ask-probe.test.sh` | offline suite (stub probe, stub `gh`, fixture lockfiles) | inferred: enforcement contract for the runner (guards 3 and 4) |
| `apps/web-platform/scripts/lib/probe-budget.ts` | pure helpers: cap constants, per-case budget, cumulative ledger, `costFromResult` | inferred: probe top-level code cannot be unit-tested by import; the $4 cap needs a test |
| `apps/web-platform/test/probe-budget.test.ts` | vitest for the helpers | inferred: same |
| `plugins/soleur/test/real-sdk-ask-probe-workflow.test.sh` | workflow posture lint + push-filter coverage guard + user-visible-string assertions | inferred: guards 1, 2 and the CPO string conditions |
| `knowledge-base/project/specs/feat-one-shot-10111-sdk-probe-schedule/tasks.md` | task list | process |

(`decision-challenges.md` already exists in the same directory.)

## Files to Edit

| File | Change | Provenance |
|---|---|---|
| `apps/web-platform/scripts/dev-probe-destroy-ask.ts` | print `costUsd` per case and a `TOTAL costUsd=` line; per-case `maxBudgetUsd`; cumulative cap; map `error_max_budget_usd` to `CANT-RUN:budget-exceeded`; header comment: the re-run is now automated (#10111) | asked: "A scheduled or on-change run of the real-SDK probe" + brief: "check ... budget" |
| `knowledge-base/engineering/architecture/decisions/ADR-284-hosted-bash-must-ask-lane-for-destroy-families.md` | amendment per the ADR section | asked: brief "design it as far as a doc/ADR note" + "Record the scope narrowing clearly" |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | one edge description | inferred: the edge text enumerates the CI surfaces and would be falsified |
| `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (and `c4-model.md` if the renderer rewrites it) | regenerated by `scripts/regenerate-c4-model.sh` (a wrapper over `plugins/soleur/scripts/render-c4-model.sh`); commit every file it changes | inferred: the committed artifact must match the model (freshness suite) |
| `scripts/pr-fanout-ledger.txt` | add a row for `scheduled-real-sdk-ask-probe.yml` (columns per the file header: jobs 2, paths yes, cancel no, note: same-repo own-file pull_request self-test, queue-not-cancel) | inferred: adding `on: pull_request` to any workflow owes a ledger row or the enumerator suite reds |
| `knowledge-base/legal/article-30-register.md` | PA-33: member (9) block, fields (a)(c)(d)(f)(g), corrected snapshot counts, add the missing `scheduled-machinery-drain.yml` member (8) and the two named non-members | inferred: PA-33's secret-keyed scope predicate makes the new file a member |
| `knowledge-base/legal/legitimate-interest-assessments/2026-07-31-claude-eval-fleet-and-ci-lia.md` | one line in Arm C | inferred: CLO item (3) |
| `knowledge-base/legal/audits/2026-07-31-dpia-screening-claude-eval-fleet-and-ci.md` | dated `Superseded` marker on the "6 files / 7 job-level surfaces" sentence | inferred: CLO item (3) |
| `knowledge-base/legal/compliance-posture.md` | dated row | inferred: CLO item (3) |
| `knowledge-base/operations/expenses.md` | extend the "Anthropic API (CI)" row: the probe is a surface that can draw the key, metered by its own `costUsd`, outside the ledger | inferred: the row enumerates draw surfaces |
| `knowledge-base/engineering/operations/runbooks/api-spend-reconciliation.md` | add the probe to the "unmetered by the ledger, metered by its own summary" note | inferred: same |
| `scripts/lib/test-affected-paths.sh` | add one entry per file the new plugin suite reads to the flat `AFFECTED_PLUGINS_SOLEUR_PATHS` array (the workflow YAML, `infra/github/ruleset-ci-required.tf`, ADR-284, `apps/web-platform/scripts/dev-probe-destroy-ask.ts`, `apps/web-platform/scripts/real-sdk-ask-probe.sh`, `apps/web-platform/server/permission-callback.ts`), each with an evidence comment in the file's style | brief: "declare the path in AFFECTED_PLUGINS_SOLEUR_PATHS ... when the suite really reads it" |
| `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` | register `apps/web-platform/scripts/real-sdk-ask-probe.test.sh` like `sdk-bump-sandbox-gate.test.sh` | inferred: suite registry for `apps/web-platform/scripts/*.test.sh` |

Not edited (checked): `ci.yml` (no new job there), `sdk-bump-sandbox-gate.sh` (its ack contract is unchanged; the probe complements it), Terraform/infra (none), `cron-monitors.tf` and `.github/actions/sentry-heartbeat` users (no heartbeat), any flag file, `docs/legal/**`.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "scheduled real-SDK probe on SDK bump" [issue #10111] | Workflow + runner + probe edits (FR1-FR6) | mapped |
| 2 | "a synthetic hosted-ask canary for the must-ask lane" [issue #10111] | not built; `#10111` edited in place under an `Operator-reserved:` hold; ADR pointer | descoped — justification: production write needing explicit operator authorisation (issue body and brief both say do NOT build or enable it) |
| 3 | "decide in the plan whether any criterion has fired" [brief] | `## Re-evaluation Criteria` | mapped |
| 4 | "do NOT CI-gate the live probe; mechanism via soleur:schedule or a path-gated job" [brief] | non-required workflow, F1 | mapped |
| 5 | "check the repo's existing secret/Doppler/CI conventions and budget, and rule via the CTO on cost/cadence" [brief] | Research Reconciliation + CTO F3/F5 + decision-challenges rows | mapped |
| 6 | "Record the scope narrowing clearly in the plan" [brief] | Overview + Cut List + Ask Mapping row 2 | mapped |
| 7 | "ship nothing that emits into production sinks" [brief] | AC10 (no production-sink emission in the diff) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Workflow file | "A scheduled or on-change run of the real-SDK probe" | asked |
| Probe cost/budget edits | "check the repo's existing secret/Doppler/CI conventions and budget" | asked |
| Runner script + its suite | — | inferred — justification: the exit-code mapping, rerun policy and issue dedupe are the guard; inside YAML they cannot be tested offline and the guard rots (learning 2026-07-27) |
| `probe-budget.ts` + vitest | — | inferred — justification: the probe's top level cannot be imported by a test, and a $4 hard cap that is never exercised is not a cap |
| Workflow lint/coverage suite | — | inferred — justification: path-filter narrower than its property is the documented recurring defect (learning 2026-09-24); the CTO made this test an acceptance criterion |
| ADR-284 amendment | "design it as far as a doc/ADR note" | asked |
| `model.c4` edge text | — | inferred — justification: the edge description enumerates CI Claude surfaces; leaving it stale makes the architecture record false |
| Article 30 / LIA / DPIA / posture / expenses / spend-runbook upkeep | — | inferred — justification: PA-33's scope predicate keys on the secret, so shipping the file without the register edit ships a known Art. 30(1) gap |
| `test-affected-paths.sh` + suite registry rows | "declare the path in AFFECTED_PLUGINS_SOLEUR_PATHS" | asked |

### Split Assessment

- Subsystems touched: 4 — `.github`, `apps/web-platform`, `knowledge-base`, `plugins/soleur` (+ `scripts`, counted with the first path segment: 5 roots)
- Planned files: 7 created + 15 edited = 22 | Estimated changed lines: ~900 (workflow ~220, runner ~260, runner suite ~220, workflow suite ~200, probe/budget ~110, vitest ~60, docs/legal ~150)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR — the roots are over the file-count heuristic only because the compliance/ADR upkeep rides with the control (shipping the register edit separately would ship a known register gap, and the ADR amendment describes the state this PR creates). The seam to split on if review asks: (a) probe + runner + workflow + tests, (b) docs/legal upkeep; they must merge together.

## Implementation Phases

### Phase 0 — measure before building (no code)

- 0.1 Confirm the six unverified items the CTO listed: label names (verified present: `type/security`, `priority/p1-high`, `priority/p2-medium`, `domain/engineering`; `ci/real-sdk-ask-probe` is created idempotently by the filer), whether `plugins/soleur/hooks/hooks.json` is in the probe's wiring (the probe loads `plugins/soleur` as an SDK plugin; `plugins/soleur/hooks/**` is therefore in the push filter, 1 commit/30d), and that the probe needs nothing beyond `ANTHROPIC_API_KEY`+`NODE_ENV=test` (settled by the self-test run, Phase 5).
- 0.1b Measure the import-extractor floors for Guard 1: write the extractor (static `import`/`export ... from`, multi-line imports, dynamic `import()`), run it on `dev-probe-destroy-ask.ts` and `permission-callback.ts`, record the counts, and set the floors to them.

### Phase 1 — RED tests first (`cq-write-failing-tests-before`)

Write `probe-budget.test.ts`, `real-sdk-ask-probe.test.sh` and `real-sdk-ask-probe-workflow.test.sh` against not-yet-existing files; confirm they fail for the right reason (file/function absent), including the mutation rows of each Guard Contract below.

### Phase 2 — probe changes

`dev-probe-destroy-ask.ts`: read the latest `result` frame's `total_cost_usd` per case (cumulative per query, so the latest, not a sum); add `costUsd=` to each `PROBE` line; accumulate a ledger (`probe-budget.ts`); read `PROBE_RUN_BUDGET_USD` (honoured downward only: a larger value than the $4 constant is ignored, so the runner can pass the remainder on a rerun and nothing can raise the cap); pass `maxBudgetUsd: <run budget> / caseCount` as a harness-only option (documented as not part of the production option shape); when the ledger reaches $4 every remaining case prints `PROBE <case> verdict=CANT-RUN:budget-exceeded`; a `result` with `subtype === "error_max_budget_usd"` is CANT-RUN `budget-exceeded`, never FAIL; print `TOTAL costUsd=<n>` before `RESULT`. No change to the verdict logic for an unexhausted budget; `PROBE_DECODE_ONLY` untouched. Contingency (decided on the self-test's measured per-case cost, CTO consulted if it changes a ruled number): if a legitimate case exceeds `$4 / 8`, change only the per-case figure and keep the $4 run cap.

### Phase 3 — runner script

`real-sdk-ask-probe.sh` (first lines: the `case "$-"` xtrace refusal when a credential variable is set, exit 78; `set -uo pipefail`):

- `should-run` (push events only; every other event prints `run=true`): the baseline is the head SHA of the last COMPLETED, non-cancelled run of this workflow on main (read with `gh api` under `permissions: actions: read` on the probe job), so a run evicted from the concurrency queue (which GitHub records as cancelled) cannot hide an SDK change from a later lockfile-only push; no such run, a baseline that cannot be fetched (`git fetch --no-tags --depth=1 origin <baseline>`), an all-zero `github.event.before`, or any error -> `run=true`. It lists the files changed `<baseline>..$SHA` as a tree diff, which needs only the two commits, so a multi-commit push from a grouped landing is covered (fixture override for tests); any changed file in the allowlist other than `apps/web-platform/package.json` / `package-lock.json` → `run=true`; if only those two changed, compare the resolved `@anthropic-ai/claude-agent-sdk` and `@anthropic-ai/claude-code` versions in base vs head lockfiles with `jq` (same extraction as `sdk-bump-sandbox-gate.sh`); differing or unreadable → `run=true`; both equal → `run=false` with a notice. **Fail toward running** on any uncertainty.
- `run`: executes `PROBE_CMD` (default `bun run apps/web-platform/scripts/dev-probe-destroy-ask.ts`, `NODE_ENV=test`) with output redacted (`sk-ant-...`, `sk-[A-Za-z0-9_-]{20,}`) into the artifact file; classifies (single `classify()` function) over exit code, the final `RESULT:` line, the count of `PROBE <case>` lines, `cases-run=N` and `PROBE remote-refs-unchanged=true`: `pass` only if exit 0 AND `RESULT: PASS` AND `cases-run>=8` AND at least 8 case lines AND remote refs unchanged; exit 1 + `RESULT: FAIL` -> `fail`; exit 3 with `CANT-RUN:budget-exceeded` or `no-anthropic-key` -> `blind`, no rerun; other exit 3 -> rerun the whole probe once with the REMAINING budget (the runner passes `PROBE_RUN_BUDGET_USD=<cap minus first-pass spend>`, which the probe honours downward only, so the $4 cap holds across both passes; no rerun when the remainder is under $0.50), then `blind`; exit 4, missing/garbled RESULT, or exit/RESULT disagreement -> `blind` (`crash` / `contract-drift`), no rerun. Writes `outcome`, `reason`, `cost` to `$GITHUB_OUTPUT`; writes the job summary (always including the host-only residual line and "production arrival not observed"); exits 0 only for `pass`.
- `file-issue` (filer job, `main` only; `reason` is constrained to a fixed enum and `cost` to a numeric regex in `classify()` before they cross the job boundary, and raw probe lines are never interpolated into an issue body): for `fail` -> exact-title match on the open regression issue, comment if found else create (`type/security`, `domain/engineering`, `priority/p1-high`, `ci/real-sdk-ask-probe`; body via `printf` + `--body-file`; links ADR-284 C9 result, the 2026-10-11 post-mortem, the run URL, cost, SDK/CLI provenance); for `blind` -> same with the blind title and `priority/p2-medium`; for `pass` -> close the open blind issue with a comment and, if a regression issue is open, add a "subsequently passed" comment **without closing it**; for `skipped` -> nothing.

### Phase 4 — workflow

`scheduled-real-sdk-ask-probe.yml`, top comment carries `<!-- gate-override: new-scheduled-cron-prefer-inngest -->` and the justification (repo-scoped; CI key only; no prd credentials; Inngest runs in the prd container) plus the `# Task design:` header; the header and every comment must NOT contain the cron literal (the discoverability probe counts it with `grep -cF`; the Task Design block above deliberately omits it). Shape:

- `on:` `push` (branches `[main]`, `paths:` = the allowlist below), `schedule` (`17 9 * * 1`, the only line containing that literal), `workflow_dispatch`, `pull_request` (`paths:` = exactly four files: the workflow file, `apps/web-platform/scripts/dev-probe-destroy-ask.ts`, `apps/web-platform/scripts/real-sdk-ask-probe.sh` and `apps/web-platform/scripts/lib/probe-budget.ts`, the three that execute with the key; a clarification of the CTO's "its own files" ruling, no wider). `concurrency: group: real-sdk-ask-probe`, `cancel-in-progress: false`. Top-level `permissions: contents: read`.
- Push allowlist (single source for the guard): `apps/web-platform/package.json`, `apps/web-platform/package-lock.json`, `apps/web-platform/server/agent-runner-sandbox-config.ts`, `.../sandbox-hook.ts`, `.../agent-runner-query-options.ts`, `.../permission-callback.ts`, `.../destroy-ask-classifier.ts`, `.../destroy-ask-lane.ts`, `.../agent-env.ts`, `apps/web-platform/scripts/dev-probe-destroy-ask.ts`, `apps/web-platform/scripts/real-sdk-ask-probe.sh`, `apps/web-platform/scripts/lib/probe-budget.ts`, `plugins/soleur/hooks/**`, the workflow file.
- Job `probe` (`permissions: contents: read, actions: read`; `if:` for `pull_request`: `github.event.pull_request.head.repo.full_name == github.repository && github.actor != 'dependabot[bot]'`; `timeout-minutes` provisional 65 job / 50 probe step (covers two worst-case passes of 8 x 180 s), re-derived from the self-test's measured elapsed): checkout (`persist-credentials: false`, SHA-pinned), `should-run`, setup-bun (`.bun-version`), setup-node 22, `npm ci --ignore-scripts` in `apps/web-platform`, apt `bubblewrap socat` + the apparmor userns sysctl exactly as `ci.yml` lines ~1374-1380, `.github/actions/anthropic-preflight`, the probe step (the ONLY step with `env: ANTHROPIC_API_KEY`), the SKIPPED summary when preflight says `ok=false`, `actions/upload-artifact` (90 days, `if: always()`). `shell: bash` with an explicit `set` line on every `run:`; no xtrace.
- Job `file-issue`: `needs: probe`, `if: always() && github.event_name != 'pull_request' && github.ref == 'refs/heads/main' && needs.probe.result != 'skipped'`; the filer maps an EMPTY `outcome` from a probe job that is `failure` or `cancelled` (npm/apt failure, step timeout, a preflight exit 1, a runner crash before `classify()`) to `blind` with `reason=no-outcome`, so a red job can never be silent; `skipped` is only ever an explicit output (`should-run=false` or preflight `ok=false`), `permissions: contents: read, issues: write`, no API key.

### Phase 5 — self-test evidence (pre-merge)

Push the branch; the own-file `pull_request` trigger runs the PR-head copy of the workflow on the PR (a fork or non-same-repo PR gets no key). Quote in the PR: PROVENANCE, all `PROBE` lines, `RESULT`, `TOTAL costUsd`, elapsed. Then apply the CTO's review triggers: first measured cost above $2.50/run, or a projected 30-day spend above $25 -> switch to shape (c) (push filter narrowed to SDK-version moves + `agent-runner-sandbox-config.ts` + `sandbox-hook.ts`; cron and dispatch kept) **before merge**. If the first run is CANT-RUN or flaky, record the pass rate and do not claim guard proof. The filer job does not run on the PR, so the self-test files no issue.

### Phase 6 — docs, ADR, C4, compliance

ADR-284 amendment; `model.c4` edge text + `scripts/regenerate-c4-model.sh`; PA-33 / LIA / DPIA / posture / expenses / spend-runbook edits with CLO wording review of the register block (applying the CLO's draft member block, numbered (9), count sentence "8 files / 9 job-level surfaces" after the edit, "7 files / 8" before, `scheduled-machinery-drain.yml` as (8), the two unnamed non-members named; verify the counts again with the grep at edit time).

### Phase 7 — registry, lints, #10111 edit

Declare the plugin suite's read paths in `scripts/lib/test-affected-paths.sh`; add the two suite-registry rows and the `scripts/pr-fanout-ledger.txt` row; run `bash scripts/lint-orphan-test-suites.sh` once the files are tracked; run the lints (`lint-shell-trace-credential-refusal.py`, `lint-guard-contract.py`, `lint-legal-registers.sh`, `lint-art30-reverification.sh`, `lint-infra-no-human-steps.py`, workflow lint). After the PR is ready, edit #10111 in place with `gh issue edit`: retitle to "synthetic hosted-ask canary for the must-ask lane (operator-reserved production write)", rewrite the body (Part 1 delivered by PR #11784 with link; Part 2 under `Operator-reserved:`; design sketch: what it would emit, which principal (the live-verify principal or a `probe` emission), `environment=probe` tag, kill switch, how arrival is read back; original re-evaluation criteria kept; milestone/labels unchanged). Body via `--body-file` with a literal absolute path written in a separate call. PR body: `Ref #10111`, the budget disclosure (`hr-autonomous-loop-skill-api-budget-disclosure`: cost ceilings, key partition), the gate-override line is NOT needed (0 filed / 0 closed).

## GDPR / Compliance Gate (Phase 2.7)

Triggers (a) and (d)-adjacent fire: a new processing activity calling an external LLM API. Outcome: nil personal data (fixed synthetic commands, public plugin descriptions, throwaway workspace; PR-head source never read by the model); PA-33 member (9) with the CLO's block; no new processor (Anthropic is already the PA-33 processor under the Jikigai key); no lawful-basis change; no DPIA trigger. `soleur:gdpr-gate` is invoked at deepen-plan against this section.

## Infrastructure (IaC)

None. No server, unit, secret, account, DNS or vendor change; the secret already exists (`ANTHROPIC_API_KEY` repo secret written by the existing Terraform from the same source as Doppler `ci`). Encryption posture: no new store or connection (GitHub-hosted artifact + the existing HTTPS edge `github -> anthropic`); section skipped per Phase 2.11.

## Guard Contract

### Guard 1 — Push path filter covers the probe's decision-relevant inputs

**Property.** Every file whose change can alter hook-then-`canUseTool` precedence for the probe's wiring (the files ADR-284 Flip criterion 5 names, plus the decision-logic files the probe and `permission-callback.ts` import directly) is matched by the workflow's `on.push.paths`, or appears in the test's classification table as an explicit exclusion with a reason.

**Assembly.** The single `on.push.paths` array in the workflow (and, separately, `on.pull_request.paths`, asserted own-files-only in Guard 2); the file set named in ADR-284's criterion-5 sentence; the static `import`/`export ... from`/dynamic `import()` lines of `dev-probe-destroy-ask.ts` and of `permission-callback.ts` (every direct local import); the classification table in the test (`IN` or `EXCLUDED: <reason>`) that every direct import must appear in. Matching is done by a GitHub-glob matcher in the test against `git ls-files`, never by string equality. The chokepoint is the one `paths:` array; the extractor reads it from the parsed YAML, not from a regex over comments.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | delete `permission-callback.ts` from `on.push.paths` | RED, naming the file |
| 2 | point the extractor at an empty probe fixture so it finds zero imports (the guard's own dispatch) | RED via the floor (measured at Phase 0 with the real extractor; the one-line `grep` estimates are 5 direct `../server/` imports for the probe and 14 `./` imports for `permission-callback.ts`, so the floors start at 5 and 10 and are set to the measured counts) |
| 3 | add two new direct imports to a copy of `permission-callback.ts` after the compliant ones, neither in the filter nor in the table | RED, both named (the check does not stop at the first) |
| 4 | reword the ADR-284 criterion-5 sentence so the extractor yields zero files | RED via the floor (>= 6 named files) |
| 5 | replace an entry with a near-miss path (`server/permission-callbak.ts`) so the precondition "an entry exists" holds but matches no tracked file | RED (matcher against `git ls-files`, not string equality) |
| 6 | classify a new import `EXCLUDED` with an empty reason | RED |
| 7 | drop one `on.push.paths` entry from the ADR-284 amendment's trigger list (doc-vs-code parity) | RED |

**Harness rows:** (H1) edit the suite's matcher to always return true: the negative control (`apps/web-platform/server/logger.ts`, in the closure, deliberately excluded) must then fail, turning the suite RED. (H2) must-PASS, non-canonical: a filter that lists `apps/web-platform/server/destroy-ask-*.ts` as a glob instead of the two file names passes.

**Anchor.** The stored value (the allowlist) and the protected thing (the import graph) can be edited in one diff, so the guard proves consistency, not integrity; what must also move for a weakening to pass is the test's `RULED_SET` constant and the classification table (both in a reviewed test file) plus the ADR sentence. Integrity rests on review plus the weekly cron backstop (named residual in the ADR), not on this test.

### Guard 2 — Workflow posture (secret scope, permissions, triggers, tracing)

**Property.** The API key is exposed to exactly one step of one job, no job other than the filer holds `issues: write`, no step can trace the key, and the `pull_request` trigger cannot run for any change except an edit of the workflow's own files or the probe and never for a fork.

**Assembly.** Every `env:` block in the workflow (workflow, job and step level), every `permissions:` block, every `run:`/script that sources the key (the workflow and `real-sdk-ask-probe.sh`), `on.pull_request.paths`, every job-level `if:` that guards forks, every `uses:` reference (SHA pin), the `shell:`/`set` lines. Parsed with a YAML parser, not grep over text, so a key referenced under a different spelling (`${{ secrets['ANTHROPIC_API_KEY'] }}`) is found.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | move `ANTHROPIC_API_KEY` to job-level `env:` | RED |
| 2 | add a second step that also reads `secrets.ANTHROPIC_API_KEY` (a second member after a compliant first) | RED |
| 3 | add `set -x` / `bash -x` to any `run:` step of the workflow YAML (the runner script's own refusal is the lint's job, AC13) | RED |
| 4 | widen `on.pull_request.paths` to `apps/web-platform/**` | RED |
| 5 | drop the same-repo `if:` on the `pull_request` job | RED |
| 6 | grant `issues: write` at workflow level | RED |
| 7 | the guard's dispatch: run the lint against an empty workflow file | RED via the floor (>= 1 key reference found, >= 2 jobs) |

**Harness rows:** (H1) edit the suite so the YAML parse returns an empty document: RED. (H2) must-PASS non-canonical: an extra read-only job with no secret and `contents: read` passes; a reordered `env:` passes.

**Anchor.** No stored value is compared; the guard reads the live file. Required-ness: the workflow is not in the ruleset's required checks and must not be added (asserted: its name is absent from `infra/github/ruleset-ci-required.tf`).

### Guard 3 — Outcome classification: `pass` is only reachable by a complete passing matrix

**Property.** The runner reports `pass` only when the probe exited 0, printed `RESULT: PASS`, ran at least 8 cases, printed at least 8 case lines and `remote-refs-unchanged=true`; every other terminal state reports a non-pass outcome that reaches the filer and turns the job red, and no budget stop is retried.

**Assembly.** The single `classify()` function in `real-sdk-ask-probe.sh` over (exit code, last `RESULT:` line, case-line count, `cases-run`, remote-refs line); its three consumers (step outputs, job summary, the job's own exit status); and the rerun branch. Only one place computes the outcome.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | stub prints `RESULT: PASS (cases-run=8)` but exits 1 | not `pass` |
| 2 | stub exits 0 with no `RESULT` line (the guard's own dispatch: "0 checked" must not pass) | not `pass` (`blind`) |
| 3 | stub PASS with `cases-run=7` | not `pass` |
| 4 | stub PASS with only 5 `PROBE` case lines | not `pass` |
| 5 | stub PASS with `PROBE remote-refs-unchanged=false` | not `pass` |
| 6 | stub exits 3 with `CANT-RUN:budget-exceeded` | `blind`, probe invoked exactly once |
| 7 | stub exits 3 with `CANT-RUN:model-did-not-attempt-bash` on both passes | `blind`, probe invoked exactly twice |
| 8 | stub exit 4 / `RESULT: DIAGNOSTIC` | `blind`, invoked once |
| 9 | first pass prints `TOTAL costUsd=3.20` then `CANT-RUN:model-did-not-attempt-bash` | second invocation receives `PROBE_RUN_BUDGET_USD=0.80` (and none when the remainder is under $0.50) |
| 10 | stub prints a `reason` outside the enum or a non-numeric cost | `blind`, value replaced by the enum fallback / `cost=unknown` never reaches `$GITHUB_OUTPUT` as raw text |

**Harness rows:** (H1) mutate a copy of the runner to always print `outcome=pass`: the suite must go RED. (H2) must-PASS non-canonical: a stub that prints 9 case lines, an unknown extra case name and `cases-run=9` with exit 0 is `pass`; a stub that fails the first pass with `CANT-RUN:model-did-not-attempt-bash` and passes the second is `pass`.

**Anchor.** None: the guard compares live output to the contract, no stored value. The `>= 8` floor mirrors the probe's `MIN_DEFAULT_CASES`; the suite asserts the two constants are equal by reading the probe source, so a floor raised in the probe cannot silently leave the runner behind.

### Guard 4 — Issue filer: exact-title dedupe and no self-clearing regression

**Property.** At most one open issue exists per class (regression, blind); a green run never closes the regression issue; the blind issue is closed only by a PASS; no fuzzy match can adopt or close an unrelated issue.

**Assembly.** The `file-issue` subcommand's four paths (fail, blind, pass, skipped) and its `gh` calls (`issue list`, `issue create`, `issue comment`, `issue close`, `label create`), exercised through a stub `gh` on `PATH` that records every call and serves a decoy issue whose title merely contains the real title.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | replace the `jq` equality with a substring/`contains` match | RED (decoy adopted) |
| 2 | `pass` path closes the regression issue | RED |
| 3 | `fail` run with an existing open issue creates a second (second-member case) | RED |
| 4 | `blind` path labelled `priority/p1-high` | RED |
| 5 | filer invoked with `outcome=` empty (the guard's own dispatch) | RED: no `gh` write calls, non-zero exit |
| 6 | `skipped` outcome performs any `gh` write | RED |
| 7 | empty `outcome` with the probe job `failure` (setup failure) takes the skip path instead of filing `blind` / `no-outcome` | RED |
| 8 | an injected `reason` (`x\n## owned`) reaches the issue body unfiltered | RED |
| 9 | two open issues carry the exact blind title: the filer comments on the oldest and creates no third; a PASS closes both blind issues and never a regression issue | RED on any other behaviour |

**Harness rows:** (H1) stub `gh` that records nothing: the suite fails (recorded-call floor >= 1 per path). (H2) must-PASS non-canonical: an existing issue whose body differs from the template but whose title matches exactly is commented on, not duplicated.

**Anchor.** The exact titles are constants shared by the runner, the test and the issue bodies; weakening one requires editing the test in the same diff (consistency, not integrity); human review is the integrity layer.

### Guard 5 — Budget: a run cannot silently exceed the $4 cap

**Property.** The cumulative recorded cost of a probe run never exceeds the $4 cap by more than one case's own cap without the run ending as `CANT-RUN:budget-exceeded`, and a budget stop is never reported as PASS or FAIL.

**Assembly.** `probe-budget.ts` (`RUN_BUDGET_USD`, `perCaseBudgetUsd`, the ledger, `costFromResult`) and its three call sites in the probe (per-case option, cost read after each case, the remaining-cases stop); the `result` subtype mapping.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | ledger never adds (cost read returns 0) | RED |
| 2 | cap constant changed to $40 | RED (the test pins $4) |
| 3 | after a stop, the next case still runs (a second case after the first stop) | RED |
| 4 | `error_max_budget_usd` mapped to FAIL | RED |
| 5 | `costFromResult` fed zero cases (dispatch) | RED via the floor (>= 1 cost sample) |
| 6 | the ADR-284 amendment states a cap figure different from `RUN_BUDGET_USD` | RED |

**Harness rows:** (H1) vitest with the ledger stubbed to a constant: RED. (H2) must-PASS: a run whose total is exactly $3.99 completes; a missing or non-numeric cost on a crash result is treated as 0 (never NaN); `maxBudgetUsd` plus the cumulative stop do the bounding.

**Anchor.** The cap constant lives in code and in the ADR amendment; the test pins the code value and the workflow suite asserts the ADR amendment's $4 / $25 / $2.50 figures against `RUN_BUDGET_USD` (consistency); the real bound is Anthropic's workspace cap (ADR-244), outside this commit.

## Acceptance Criteria

### Functional

- [ ] AC1. `scheduled-real-sdk-ask-probe.yml` exists with the triggers and path allowlist in Phase 4, runs the probe on a direct `ubuntu-latest` runner, and is **not** in the required-checks ruleset. Merge-base proof: `git diff --quiet origin/main...HEAD -- infra/github/ruleset-ci-required.tf .github/workflows/ci.yml apps/web-platform/scripts/sdk-bump-sandbox-gate.sh apps/web-platform/server/agent-runner-query-options.ts` exits 0 (three-dot, so a sync with main cannot make it vacuous).
- [ ] AC2. The probe prints `costUsd` per case and `TOTAL costUsd=`; the $4 cap and `CANT-RUN:budget-exceeded` behave per Guard 5.
- [ ] AC3. Exit-code mapping, rerun policy and issue filing behave per Guards 3 and 4 (offline suite green).
- [ ] AC4. Self-test evidence is quoted in the PR body: PROVENANCE, 8 `PROBE` lines, `RESULT: PASS ... cases-run=8` (or the recorded flaky pass rate), `TOTAL costUsd`, elapsed; the CTO's $2.50 / $25 triggers were applied before merge. The evidence is for the host-only boundary and is not described as production verification.
- [ ] AC5. Negative control: the PR body records that the probe can go red (the existing pre-fix-tree self-check from ADR-284, `PROBE_SANDBOX=noauto` run showing `canUseToolCalls=[]`, or an equivalent documented control), so a probe that can only pass is excluded (CPO).
- [ ] AC6. User-visible strings: every issue body, the job summary and the workflow `name:` contain the host-only residual and "production arrival not observed"; the string "verified in production" appears nowhere in the workflow YAML, `real-sdk-ask-probe.sh` or its issue/summary template strings (scoped grep, excluding `*.test.sh`, the plan, specs and the ADR amendment that quote it as a prohibition; the suite builds the forbidden literal by concatenation so it does not match itself), and the host-only residual string is present at least once in each of those files (positive assertion).
- [ ] AC7. A green run does not close a regression issue (adds a "subsequently passed" note only); the blind issue self-closes on a PASS (Guard 4).
- [ ] AC8. ADR-284 amended as specified; `status: adopting` unchanged; Flip criteria 4 and 6 text unchanged; `git grep -n -e 'nothing in CI does' -e 'criterion 5 above is the only guard' -- knowledge-base/engineering/architecture/decisions/ADR-284-hosted-bash-must-ask-lane-for-destroy-families.md` returns nothing. The amendment states that a scheduled PASS never discharges Flip criterion 1 or 5 without a `build_sha` match, and that the workflow reads the repo secret where the documented command uses Doppler `ci`.
- [ ] AC9. Compliance upkeep done with CLO-reviewed wording: PA-33 member (9), corrected snapshot counts and the `scheduled-machinery-drain.yml` member, LIA/DPIA/posture one-liners, `expenses.md` row, spend-runbook note; both register lints green.
- [ ] AC10. The diff contains no production-sink emission: no Sentry DSN, no Better Stack token, no `betterstack-query`/ingest call, no `environment=probe` emission outside the probe's existing in-process transport, no feature-flag creation or flip (asserted by a scoped grep in the workflow suite over the workflow YAML and `real-sdk-ask-probe.sh` only; the suite, the plan and the ADR name these tokens as prohibitions and are excluded).
- [ ] AC11. `#10111` is edited in place (retitled, body rewritten, `Operator-reserved:` hold, milestone and labels unchanged); the PR body says `Ref #10111`; no issue is filed or closed; the PR body carries the API-budget disclosure.
- [ ] AC12. `model.c4` edge description updated, `model.likec4.json` (and `c4-model.md` if rewritten) regenerated and committed, and `c4-count-parity`, `c4-code-syntax`, `c4-render`, `c4-model-freshness` green.

### Non-Functional / Quality gates

- [ ] AC13. `scripts/lint-shell-trace-credential-refusal.py` clean for `real-sdk-ask-probe.sh` (Rules A and B); `lint-guard-contract.py` counts 5 entries for this plan; no unresolved-marker tokens in any new file.
- [ ] AC14. All `uses:` pinned to a commit SHA; `persist-credentials: false`; `concurrency` queue-not-cancel; `timeout-minutes` set on the job and the probe step with the derivation comment citing the measured elapsed.
- [ ] AC15. Registration, each mechanism cited: the plugin suite is discovered by the `plugins/soleur/test/*.test.sh` entry in `SUITE_GLOBS` (`scripts/test-all.sh` line ~97) and its read paths are entries in the flat `AFFECTED_PLUGINS_SOLEUR_PATHS` array of `scripts/lib/test-affected-paths.sh` (quote the line that expands the array when adding them); the runner suite has rows in `scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv` like `sdk-bump-sandbox-gate.test.sh`; after the files are tracked `bash scripts/lint-orphan-test-suites.sh` reports no orphan among the three suites; the registry ratchet suite (`scripts/test-affected-kb-consumers.test.sh`) is green.
- [ ] AC17. `scripts/pr-fanout-ledger.txt` has the new row and its enumerator suite is green.
- [ ] AC18. Doc-vs-code parity: the workflow suite asserts that the ADR-284 amendment lists every `on.push.paths` entry and states the $4 / $25 / $2.50 figures equal to `RUN_BUDGET_USD` and the Phase 5 triggers (mutation rows: Guard 1 row 7, Guard 5 row 6).
- [ ] AC19. `grep -cF '17 9 * * 1' .github/workflows/scheduled-real-sdk-ask-probe.yml` returns exactly 1, run in the work phase (the discoverability probe cannot run before the file exists).
- [ ] AC16. Preflight Check 4 (reads Doppler) is **skipped** per the standing brief, and said so in the PR body. CI is the test gate (local runs are unreliable under load).

## Test Scenarios

- **Runner suite (`real-sdk-ask-probe.test.sh`, stub probe/gh):** the eight Guard 3 rows, the Guard 4 rows, `should-run` with fixture lockfiles (SDK moved -> run; only non-SDK dependency moved -> skip; lockfile unreadable -> run; allowlisted code file changed -> run; non-push event -> run; all-zero `before` -> run; multi-commit range -> covered; baseline older than `before` after a cancelled run -> an SDK move in the evicted push still triggers a run), redaction of a planted `sk-ant-...` in stub output (the xtrace refusal itself is covered by `lint-shell-trace-credential-refusal.py`, AC13).
- **Workflow suite (`real-sdk-ask-probe-workflow.test.sh`):** Guards 1 and 2, AC6 string assertions, AC10 grep, the cron literal appears exactly once, required-checks absence.
- **Vitest (`probe-budget.test.ts`):** Guard 5.
- **Integration (the PR self-test run):** Phase 5 evidence. This is the only layer that exercises the real SDK; it is a measurement, not a gate.
- **Edge cases:** burst of pushes (concurrency queue keeps one pending); fork PR touching the workflow file (job skipped, no secrets); billing cap hit (SKIPPED, green, not a pass); runner without unprivileged userns (probe reports sandbox not engaged / model-did-not-attempt -> CANT-RUN -> blind, never FAIL).

## Dependencies & Risks

- **Cost is unmeasured until the self-test run.** Worst case if the $1.5 estimate is badly wrong: 16 runs x $4 = $64/month, inside the $100 cap but above the $80 notice. Mitigation: the $2.50 trigger on the first measurement, the $4 per-run cap, and the CTO-ruled reduction to shape (c).
- **Nondeterminism.** CANT-RUN is expected sometimes (the model may not call Bash). One whole-probe rerun, then a p2 blind issue; never a FAIL.
- **Host-only proof.** A pass is not a sandbox witness for the hosted container (the variable behind #10054). Stated in every output.
- **Path-set residual.** A code change outside the filter is caught only by the next weekly cron (<= 7 days) and the human criterion-5 check.
- **Dead schedule not detected** (no heartbeat, CTO F4); named in the ADR.
- **The self-test run executes the PR-head TREE with the key in the probe step's environment.** The path filter only decides *when* it triggers, not what runs: a same-repo PR that edits one of the four filtered files runs that PR's whole `server/**` import closure and its `package-lock.json` install (`npm ci --ignore-scripts`) under bun with `ANTHROPIC_API_KEY` set. Same posture as the `ci.yml` real-turn gates; fork PRs and the Dependabot actor are excluded by the job `if:` (Guard 2 asserts the `head.repo.full_name == github.repository` comparison); blast radius is the `soleur-ci-eval` workspace ($100/month cap). CLO classed it as secrets hygiene, not Art. 30. Stated in the ADR residuals.
- **Setup failures** (npm/apt, preflight exit 1, timeouts) are surfaced as the blind issue with `reason=no-outcome`, not silently red.
- **Runner image drift** (`ubuntu-latest` bwrap/AppArmor): surfaces as CANT-RUN, never as a false pass.
- **Operator holds respected:** no flag created/flipped; #11237 untouched; #9543 not re-opened; legal sign-off at flag-on not engaged. Pre-existing open Better Stack incidents `soleur-egress-gw-probe-silent-prd` (Oct 12), `soleur-luks-monitor-host-timer-dark-prd` (Sep 27) and `soleur-claude-cost-capture-dark-prd` (Sep 23) are unrelated and not ours; `ci/main-broken` #11669 (`cron-egress-nftables.test.sh` timeout in deploy-script-tests 2/4; it reads CLOSED at deepen time, 2026-11-01) is not ours.

## References & Research

- Issue #10111, epic #9601, trackers #10054, #9976, #9776; ADR-284, ADR-079, ADR-244, ADR-033; post-mortem `2026-10-11-hosted-bash-ask-bypassed-by-sdk-auto-allow-postmortem.md`.
- Files: `apps/web-platform/scripts/dev-probe-destroy-ask.ts`, `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh`, `.github/workflows/ci.yml` (`sandbox-canary-capture-gate`, bubblewrap step), `.github/workflows/scheduled-integration-suites.yml` (override-marker precedent), `.github/workflows/scheduled-realtime-probe.yml` (filer pattern), `.github/actions/anthropic-preflight`.
- CTO rulings: `knowledge-base/project/specs/feat-one-shot-10111-sdk-probe-schedule/decision-challenges.md`.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6; it is filled above.
- The CTO's first F2 test (closure coverage) was infeasible as written (189 files); the second ruling replaced it. Any future widening of the filter must re-measure push volume with the command in Research Insights before changing the $25 ceiling.
- `maxBudgetUsd` is a harness-only option: it must never leak into the production option builder (`agent-runner-query-options.ts` is not edited).
- The cron literal `17 9 * * 1` must appear on exactly one line (the observability discoverability probe counts lines with `grep -cF`); do not repeat it in comments.
- The own-file `pull_request` trigger runs only for edits of the workflow and the probe script; adding other paths there widens who can read the key and is a Guard 2 RED.
- No agent may record the operator's acceptance of the Flip-criterion-4 substitute, flip ADR-284 to `accepted`, or describe the hosted gate as verified in production.
