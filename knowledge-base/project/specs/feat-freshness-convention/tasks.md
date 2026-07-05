---
lane: cross-domain
tracks_issue: 5999
plan: knowledge-base/project/plans/2026-07-05-feat-freshness-last-reviewed-integrity-gate-plan.md
last_updated: 2026-07-05
review_cadence: quarterly
---

# Tasks: Freshness `last_reviewed` — Source-Fix + Audit Tripwire (#5999)

Deepened 2026-07-05 (5-agent review). Contract-before-consumer: **Phase 2 (strip) precedes Phase 3 (frontmatter)**. The integrity is the source fixes (Phase 4); the gate (Phase 1) is a detective tripwire.

## Phase 0 — Preconditions
- [x] 0.1 Re-measure B_ALWAYS (`wc -c AGENTS.md + AGENTS.core.md` vs 23000; ~22976).
- [x] 0.2 Re-grep automated `last_reviewed` WRITERS (classify read vs write); confirm the set = {`brainstorm/SKILL.md:121`, `cron-campaign-calendar.ts:108`}; add any third to Phase 4.
- [x] 0.3 Read `follow-through-directive-gate.sh` + `lib/incidents.sh` for `strip_command_bodies`, `resolve_command_cwd`, `emit_incident`.

## Phase 1 — Reviewed-audit gate (tripwire)
- [x] 1.1 Create `.claude/hooks/context-reviewed-gate.sh`: fire on `git commit`; `resolve_command_cwd`; delta = union of `--cached` AND (for `-a`/`-am`/`-o`/pathspec) working-tree; fire only on a **removed/changed** `last_reviewed` line (`^-.*[Ll]ast_[Rr]eviewed`), exempt pure net-new additions; widened regex (quote/space/case); full commit-message extraction (multi-`-m`, `-am`, `--message=`, `-F`, heredoc); trailer present → allow, absent → deny + `emit_incident deny`; fail-open split (benign silent / error → `emit_incident warn hook_self_fault`); advisory `warn` on unverifiable silent-bypass.
- [x] 1.2 Create `.claude/hooks/context-reviewed-gate.test.sh`: staged-no-trailer→deny; **`-am`-no-trailer→deny**; net-new add→allow (no trailer); quoted/spaced/case change→deny; deletion→deny; trailer (incl. 2nd `-m`, `-F`)→allow; `last_updated`-only→allow; non-commit→silent; `-F` unreadable→error fail-open+incident; `git -C /other`→correct repo.
- [x] 1.3 Register hook in `.claude/settings.json` (PreToolUse→Bash).

## Phase 2 — Frontmatter-strip (enables Phase 3)
- [x] 2.1 Create `scripts/lib/frontmatter-strip` shared contract + fixtures + cross-check test (loader vs lint byte-identical).
- [x] 2.2 Edit `session-rules-loader.sh`: shared strip fn at ALL THREE sites (`:50`, `:149`, `:162`); over-strip guard (sentinel rule-id survival + `TOTAL_RULES` pre==post → fail-closed loud); preserve ≤200B header.
- [x] 2.3 Loader test: injected context (main + fallback `:50` paths) has rule text, NOT `last_reviewed:`; malformed-frontmatter fixture keeps all `- [id:` lines.
- [x] 2.4 Edit `lint-agents-rule-budget.py`: strip `AGENTS.core.md` frontmatter before byte count; ERROR (not shrink) if strip removes a `- [id:` line; comment the loaded-vs-disk reinterpretation.
- [x] 2.5 Edit `lint-agents-rule-budget.test.sh`: frontmatter excluded from B_ALWAYS; malformed fixture → lint ERRORS.

## Phase 3 — Rule layer under the clock
- [x] 3.1 Add `last_reviewed: 2026-07-05` + `review_cadence: monthly` + `owner:` frontmatter to `AGENTS.core.md`.
- [x] 3.2 Confirm ALL THREE AGENTS lints green (`lint-agents-rule-budget.py`, `lint-rule-ids.py`, `lint-agents-enforcement-tags.py`).

## Phase 4 — Source-fix BOTH writers (real integrity)
- [x] 4.1 Edit `plugins/soleur/skills/brainstorm/SKILL.md:121`: `last_updated`-only; cite ADR-086.
- [x] 4.2 Edit `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts:108`: agent-prompt bumps `last_updated`, not `last_reviewed` (server-side — gate can't see it).
- [x] 4.3 Fix any third writer from 0.2.

## Phase 5 — Extend overdue-review scan
- [x] 5.1 Edit `.github/workflows/review-reminder.yml`: add repo-root `AGENTS.core.md` to the `find` feed; run-time required-constitutional-path liveness assert (`::error::` if not evaluated). (Slug branch optional polish.)

## Phase 6 — ADR + C4
- [x] 6.1 Create `ADR-086-freshness-last-reviewed-source-fix-and-audit-tripwire.md` via `/soleur:architecture` (boundary + source-fix-first + verbatim guarantee-boundary statement + pre-existing-3-parsers ack + C4-none). Optional AP-016 in principles-register. Ordinal re-verified at work: ADR-085 was taken by the inbox ADR (#6007), so this shipped as ADR-086.

## Phase 7 — Verify
- [x] 7.1 Run test suite + all new `.test.sh` + 3 AGENTS lints + strip cross-check + two-case discoverability probe (discriminate on `permissionDecision:deny` JSON).
- [x] 7.2 Walk AC1–AC10.
