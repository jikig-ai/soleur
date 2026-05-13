---
title: incident-commander — implementation tasks
issue: 2725
branch: feat-incident-commander-2725
plan: knowledge-base/project/plans/2026-05-13-feat-incident-commander-skill-plan.md
brand_survival_threshold: single-user incident
lane: cross-domain
status: pending
date: 2026-05-13
---

# Tasks: `/soleur:incident` skill (#2725)

Implementation breakdown derived from the plan. Each task has a hard checklist; refer to plan for full FR/AC/TR specification.

## Step 0 — D1 prerequisite (separate branch, tracked under #3724)

- [ ] **0.1** Update issue #3724 body to reflect REVERSED direction (rename minority forms → `brand_survival_threshold:`).
- [ ] **0.2** Operator runs `/soleur:one-shot #3724` (or equivalent) on a separate branch to execute the D1 rename sweep.
- [ ] **0.3** PR1 merges to `main`. Verify:
  - `git grep -l "^brand_survival:\|^brand_threshold:" -- '*.md' '*.yml' '*.yaml' '*.json'` returns zero non-archived hits.
  - `git grep -l "single-user-incident" -- '*.md' '*.yml' '*.yaml'` returns zero non-archived hits.
- [ ] **0.4** On `feat-incident-commander-2725`: `git fetch origin main && git rebase origin/main`.

## Step 1 — Skill scaffold + NOTICE + templates + RED tests

- [ ] **1.1** Create `plugins/soleur/skills/incident/SKILL.md` with frontmatter (`name: incident`, single-line third-person description ≤80 chars) and Phase 0-8 header outline. Phase bodies empty.
- [ ] **1.2** Create `plugins/soleur/skills/incident/NOTICE` with MIT attribution to alirezarezvani/claude-skills.
- [ ] **1.3** Create `plugins/soleur/skills/incident/templates/pir.md` with substitution-point comments + conditional `Step 0: REVOKE FIRST` block for secret-leak triggers.
- [ ] **1.4** Create `plugins/soleur/skills/incident/test/fixtures/positive-corpus.md` — synthesized positives for every regex class (JWT, email, UUID, Stripe sk_/pk_/rk_/whsec_/acct_/cus_/pi_/seti_/sub_/in_, IPv4, env-var). Synthesize from format specs (no real production strings) per `cq-test-fixtures-synthesized-only`.
- [ ] **1.5** Create `plugins/soleur/skills/incident/test/fixtures/dry-run-incident.json` and `dry-run-secret-leak.json`.
- [ ] **1.6** Create `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` with 4 RED tests:
  - Test 1: negative-baseline (existing PIR exits 0).
  - Test 2: positive-corpus (each regex class triggers ≥1).
  - Test 3: invalid arg (exit 2).
  - Test 4: output format (`at offset \d+: .{8}\*\*\*.{8}`).
- [ ] **1.7** Run `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh` — verify all RED.

## Step 2 — Redaction sentinel implementation (GREEN)

- [ ] **2.1** Create `plugins/soleur/skills/incident/scripts/redact-sentinel.sh`. Bash + `grep -nE` + `awk`.
- [ ] **2.2** Regex set per plan FR3 (verbatim): JWT, email, UUID, Stripe (sk/pk/rk_, whsec_, acct_, cus/pi/seti/sub/in_), IPv4, env-var-with-value.
- [ ] **2.3** Output format: `at offset N: <8-prefix>***<8-suffix> matched pattern P`. No full token in output.
- [ ] **2.4** Exit codes: 0 = clean, 1 = redaction needed, 2 = invalid args.
- [ ] **2.5** Re-run test harness — verify all 4 GREEN.

## Step 3 — SKILL.md authoring (Phase 0-8 body)

- [ ] **3.1** Phase 0 — capture operator facts via inline prompts (title, detected_at UTC, symptom prose, suspected_change PR/SHA, affected_user_count).
- [ ] **3.2** Phase 1 — render `brand_survival_threshold` decision criteria text inline BEFORE asking for confirm. Advisory + rationale. Operator confirms/overrides; override emits `classification_override` to PIR frontmatter.
- [ ] **3.3** Phase 2 — compute `art_33_deadline = detected_at + 72h`. Block Phase 3+ on Art. 33 OR Art. 34 trigger. Separate operator acks if both fire.
- [ ] **3.4** Phase 3 — `awk`-scan `knowledge-base/engineering/ops/runbooks/*.md` for `triggers:` frontmatter; literal-substring match; surface top-3; selected runbook slugs auto-populate Phase 4 `triggers[]` verbatim. Surface "no runbook matches" if none.
- [ ] **3.5** Phase 4 — `sed`-substitute against `templates/pir.md`. Frontmatter MUST use `brand_survival_threshold:` (NOT `brand_threshold:`). Body sections per FR2 Phase 4.
- [ ] **3.6** Phase 5 — emit one-line "Public-summary deferred to #3732" note (no public artifact in MVP).
- [ ] **3.7** Phase 6 — invoke `scripts/redact-sentinel.sh` against draft BEFORE writing to disk OR emitting inline (pre-inline-emit gate per FR3).
- [ ] **3.8** Phase 7 — emit cleared draft INLINE. Commit gate prompts: `To commit, type exactly: COMMIT-PIR`. Parser matches LITERAL string, case-sensitive. Free-form yes is rejected. No literal `ABORT` token — Ctrl-C documented.
- [ ] **3.9** Phase 8 — grep `^status:\s*resolved$` in the PIR file. On match: emit PIR body inline to conversation transcript, then invoke `skill: soleur:compound-capture --headless` (NO positional args). On mismatch: block with `Phase 8 requires PIR status: resolved. Current: <value>.`.

## Step 4 — `--dry-run` mode + integration tests

- [ ] **4.1** Create `plugins/soleur/skills/incident/scripts/dry-run.sh` wrapping the skill with output captured to a tmp file for grep-based ACs.
- [ ] **4.2** Dry-run on `dry-run-incident.json` — verify draft emit, sentinel ordering, ack-gate behavior, compound-capture handoff via `--headless`.
- [ ] **4.3** Dry-run on `dry-run-secret-leak.json` — verify `Step 0: REVOKE FIRST` preamble present in template output.
- [ ] **4.4** Verify Art. 33/34 blocking: fixture with `risk_to_subjects: high` triggers both acks; `low` triggers only Art. 33.

## Step 5 — `/soleur:go` intent routing extension

- [ ] **5.1** Edit `plugins/soleur/commands/go.md` — insert new `incident` row immediately after line 49 (`review` row), before line 50 (`default` row). Row content per plan FR4 (prose-only trigger-signals cell, no inline-code mid-cell).
- [ ] **5.2** Verify: `wc -l plugins/soleur/commands/go.md` shows file 1 line longer than at branch base.
- [ ] **5.3** Manual smoke: `/soleur:go "production is down"` routes to `/soleur:incident`.

## Step 6 — Documentation reciprocal updates

- [ ] **6.1** Add `[Updated 2026-05-13: D1 direction reversed per plan Research Reconciliation]` markers to spec.md in **Problem Statement, Goals (4 occurrences), Non-Goals, FR1, AC1-AC3**.
- [ ] **6.2** Add `[Updated 2026-05-13]` marker to brainstorm doc Key-Decisions row for D1 direction.
- [ ] **6.3** Add cross-reference header note to `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md` (post-rename) pointing at `/soleur:incident` for future PIRs.
- [ ] **6.4** Issue #3724 body update already covered by Step 0.1.

## Step 7 — Multi-agent review

- [ ] **7.1** Spawn `user-impact-reviewer` (auto-fires per `brand_survival_threshold: single-user incident`). Require CONCUR before AC18.
- [ ] **7.2** Spawn `pr-review-toolkit:silent-failure-hunter` on `scripts/redact-sentinel.sh` + `scripts/dry-run.sh`.
- [ ] **7.3** Spawn `soleur:engineering:review:security-sentinel` on the redaction regex set (validate OWASP / CWE coverage; flag any high-PII pattern still missing).
- [ ] **7.4** Spawn `soleur:engineering:review:pattern-recognition-specialist` for cross-skill consistency (vs `postmerge`, `preflight`, `compound-capture`).
- [ ] **7.5** Spawn `soleur:engineering:review:code-simplicity-reviewer` for final YAGNI check.
- [ ] **7.6** Apply P0/P1 findings inline. P2/P3 → scope-out tracking issues per `/soleur:ship` conventions.

## Step 8 — PR ready + merge

- [ ] **8.1** Confirm PR1 (#3724) merged to main.
- [ ] **8.2** `git fetch origin main && git rebase origin/main` on this branch.
- [ ] **8.3** Update PR body with full AC checklist + `Closes #2725` (body, not title — per `wg-use-closes-n-in-pr-body-not-title-to`). Reference #3724 as prerequisite, #3725/#3726/#3732 as deferrals.
- [ ] **8.4** `/soleur:ship` for preflight + final review wiring.
- [ ] **8.5** `gh pr ready 3721 && gh pr merge 3721 --squash --auto`.

## Post-merge (operator-driven, AC20)

- [ ] **9.1** On first real production incident, run `/soleur:incident`. Validate regex-set false-positive rate against real content. Re-evaluation criterion for #3725 (ROPA wiring), #3726 (sentinel → AGENTS rule), #3732 (public-PIR scope-back-in).
