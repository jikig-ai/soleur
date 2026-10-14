---
plan: knowledge-base/project/plans/2026-09-17-feat-upstream-devin-cloud-parity-asks-plan.md
issue: 8160
branch: feat-devin-upstream-asks-posture
lane: cross-domain
---

# Tasks — feat: upstream asks to Cognition (#8160)

## Phase 1 — Evidence package

- [x] 1.1 Recreate `knowledge-base/project/specs/feat-devin-upstream-asks-posture/` and write `upstream-asks.md`:
  - §1 hook-dispatch defect (doc-vs-measured discrepancy: docs claim `command` hooks run for non-SessionStart/SessionEnd events; two-arm probe measured zero dispatch across plugin `hooks.json`, `.devin/config.json`, `.claude/settings.json`, catch-all `matcher: ""`; ask: fix or correct docs, all events incl. PostCompaction)
  - §2 plugin-subagent parity FR (`agents/**/*.md` as cloud subagent types; web-app vs DRS-sandbox `run_subagent` divergence)
  - §3 contract-semantics bundle (`ask_user_question` availability + safe unattended semantics; `message_user` blocking; `permissionDecision:"ask"`/`"defer"`; `PermissionRequest`; `.cwd` envelope parity; SessionStart source matcher; `requiredPlugins` precedence; PostCompaction dispatch)
  - Every claim cites producing command/probe or a docs.devin.ai page + fetch date; one-line DPA disclaimer; #8159/#8155 citations; no `YYYY-MM-DD HH:MM` strings
- [x] 1.2 Verify every cited repo path resolves on `origin/main`

## Phase 2 — Disclosure gate

- [x] 2.1 `bash scripts/upstream-report-scrub.sh <package>` → exit 0
- [x] 2.2 CLO checklist pass: capability-delta framing only; no org slugs / session IDs / abs paths / env values / VM internals / founder-identifying data / billing posture; not a security-vulnerability framing; DPA disclaimer present

## Phase 3 — Drift watcher + monitor

- [x] 3.1 Write `.github/workflows/scheduled-devin-docs-drift.yml` (marketplace-drift pattern):
  - `gate-override: new-scheduled-cron-prefer-inngest` header (3 clauses + `Ref #8253` disposable note)
  - Watched surfaces: plugin-ecosystem limitations page + CLI changelog + Cognition release-notes surface
  - Polarity-aware capability anchors (hooks = claim-text change/admission, not presence; subagents = limitations absence claim; changelog = keyword anchor-grep, not raw diff)
  - `set +e` + `|| rc=$?`; sanitize() incl. backtick/`<!--`/`@` neutralization for body-bound values; fail-closed fetch; verdict-as-data
  - Issue egress: label bootstrap → `gh issue list --label` (failed lookup never creates) → update-in-place; close-on-clean; body carries `Ref #8160`
  - `contents: read` + `issues: write` only; concurrency group; `workflow_dispatch`; sentry-heartbeat with all three `SENTRY_INGEST_*` forwards
- [x] 3.2 `apps/web-platform/infra/sentry/cron-monitors.tf`: `sentry_cron_monitor` for the workflow slug (crontab = workflow cron + sibling margin)
- [x] 3.3 `actionlint` clean; `sentry-monitor-iac-parity` suite green

## Phase 4 — Register + bookkeeping (pre-merge)

- [x] 4.1 `plugins/soleur/devin/INSTRUCTIONS.md` upstream-requests block → time-invariant wording ("filing package at `<path>`; submission state tracked on #8160")
- [x] 4.2 Context comments on #8161 + #8162 → archived brainstorm/spec
- [x] 4.3 Reconciliation comment on #8159 (open despite merged PR #8155 — operator judgement to close)
- [x] 4.4 Write `scripts/file-upstream-ask-8160.sh` (posting-log update + retrievable-body re-scrub + watcher-run verify)

## Phase 5 — Filing + tracking (post-merge)

- [ ] 5.1 Operator: send email verbatim to `support@cognition.ai` (agent prepares `mailto:` link or paste text; body cites `blob/<merge-sha>/` permalink)
- [x] 5.2 Agent: compose + attempt Devin `/bug` for §3 items 2–4 (the defect-class items); paste handoff if interactive-only — operator filed 2026-09-18, logged on #8160
- [x] 5.3 Run `file-upstream-ask-8160.sh`: posting log on #8160 (destinations/dates/state + verbatim-send attestation + delivery-unverifiable note); `/bug` body re-scrub where retrievable — `pending-send` + `filed` entries posted 2026-09-18
- [~] 5.4 Confirm `apply-sentry-infra.yml` applied the new monitor; `gh run list --workflow=scheduled-devin-docs-drift.yml` shows ≥1 run — watcher verified (35333427096 + 35340407015 green incl. check-in after the #8280 checkout fix); monitor apply blocked by #7985 (two surviving `sentry_issue_alert` rules 410; upstream provider fix #950 merged but unreleased, >v0.15.7) — tracked at #8282
- [x] 5.5 Annotate spec FR5 with the plan-review deviation (directive cut → `Ref #8160` linkage)

## Sunset (on #8160 close)

- [ ] S.1 Delete `scheduled-devin-docs-drift.yml`, the `sentry_cron_monitor` resource, the drift label, the INSTRUCTIONS.md register row, the `NON_INNGEST_MONITORS` entry in `function-registry-count.test.ts`, and `scripts/devin-docs-drift-check.test.sh` + its `run_suite` line in `scripts/test-all.sh`
