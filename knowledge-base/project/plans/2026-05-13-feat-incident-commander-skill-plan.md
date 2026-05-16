---
title: incident-commander skill — SEV classification + redaction-gated PIR scaffold
issue: 2725
parent_issue: 2718
branch: feat-incident-commander-2725
brainstorm: knowledge-base/project/brainstorms/2026-05-13-incident-commander-brainstorm.md
spec: knowledge-base/project/specs/feat-incident-commander-2725/spec.md
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
status: planned
date: 2026-05-13
child_issues:
  - 3724  # D1 brand_survival_threshold rename sweep (PR1 prerequisite — direction REVERSED from brainstorm)
  - 3725  # ROPA / Art. 30 register consumption wiring (post-MVP)
  - 3726  # cq-pir-redaction-sentinel promotion to AGENTS.core.md rule (post-first-real-incident)
  - 3732  # Public-safe PIR summary artifact (deferred per plan review — opens after first real customer-impact incident)
---

# Plan: `/soleur:incident` skill — SEV classification + redaction-gated PIR scaffold (#2725)

**Issue:** #2725 (parent #2718)
**Branch:** `feat-incident-commander-2725`
**Brainstorm:** [2026-05-13-incident-commander-brainstorm.md](../brainstorms/2026-05-13-incident-commander-brainstorm.md)
**Spec:** [knowledge-base/project/specs/feat-incident-commander-2725/spec.md](../specs/feat-incident-commander-2725/spec.md)
**Draft PR:** #3721

## Overview

Ship a standalone `/soleur:incident` skill at `plugins/soleur/skills/incident/` that classifies a live incident's `brand_survival_threshold` in <60s, gates PIR drafting behind a GDPR Art. 33/34 notification-trigger evaluation, and scaffolds a redaction-gated internal PIR per the existing `dashboard-error-postmortem.md` shape.

Operator-invoked only (no Sentry/cron substrate exists; deferred). Pre-write redaction sentinel (mechanical regex pass) is the load-bearing defense against the operator-named worst-outcome ("PIR leaks PII / session tokens / secrets"). Sentinel runs BEFORE inline-emit to the operator transcript, not just before disk commit — transcripts ARE write boundaries (SpecFlow Critical #2). All prod-touching steps are advisory + ack-gated per `hr-menu-option-ack-not-prod-write-auth`; commit gate requires a literal `COMMIT-PIR` token, not free-form yes. Skill calls `/soleur:compound-capture --headless` at Phase 8 after operator-confirmed `status: resolved` (clean seam: incident-commander writes PIR; compound-capture writes fix-learning).

Ships in two PRs by design:

- **PR1 (#3724) — D1 prerequisite, separate branch.** Frontmatter key + value-form rename sweep. **Direction reversed from spec.md FR1** (see Research Reconciliation). No behavior change.
- **PR2 (#3721, this branch) — D2 + D3 bundled.** Skill + template + redaction sentinel + Art. 33/34 gate + `/soleur:go` intent extension. Lands AFTER PR1 merges.

**Public-safe PIR summary artifact (originally spec FR5, FR7) is deferred to #3732** per plan-review YAGNI consensus (DHH + code-simplicity converged). Soleur has ~0 ICP usage; designing public-comms infrastructure ahead of customer presence is speculative. Internal PIR is the load-bearing artifact for MVP.

## Research Reconciliation — Spec vs. Codebase

| Spec / brainstorm claim | Codebase reality (verified 2026-05-13 via `git grep`) | Plan response |
|---|---|---|
| spec FR1: rename `brand_survival_threshold` / `brand_survival` / `threshold` → `brand_threshold` (singular) | `brand_survival_threshold:` frontmatter appears in **97 files** (dominant). `brand_threshold:` in **1 file** (`dashboard-error-postmortem.md`). `brainstorm/SKILL.md:396` MANDATES `brand_survival_threshold:` in spec frontmatter. `preflight/SKILL.md:463` greps `**Brand-survival threshold:**`. The spec's "rename TO singular" is the minority direction. | **REVERSE D1 direction.** Rename minority forms (`brand_threshold` 1 file, `brand_survival` 5 files, semantic `threshold:` 7 files) → `brand_survival_threshold:`. ~13 files instead of ~110. Operator-confirmed 2026-05-13. Plan FR1 + AC1-AC3 reflect corrected direction; spec.md gets `[Updated 2026-05-13]` markers across **Problem Statement, Goals, Non-Goals, FR1, AC1-AC3** (Kieran P1 — earlier draft missed Problem/Goals/Non-Goals). Issue #3724 body updated reciprocally before PR1 begins. |
| spec FR2 Phase 4 frontmatter "verbatim from `dashboard-error-postmortem.md`" includes `brand_threshold:` | The 1-file legacy form. Dominant form is `brand_survival_threshold:`. | New PIR template writes `brand_survival_threshold:`. Legacy file renamed in D1. |
| brainstorm: `silent-failure-hunter` agent in Phase 7 review | Verified: no `silent-failure-hunter.md` at `plugins/soleur/agents/` expected path. Available as `pr-review-toolkit:silent-failure-hunter` (subagent_type via Agent tool's registry). Brainstorm CTO mis-claimed absence due to CWD path-resolution drift. | Plan Step 7 invokes `pr-review-toolkit:silent-failure-hunter` via Task subagent. |
| spec TR3 fixture-test against `dashboard-error-postmortem.md` as negative-baseline | File exists. Body contains literal `eyJ...` references, commit SHAs, hostnames. | Sentinel must distinguish hand-redacted PIR (negative-baseline) from real un-redacted content. If sentinel false-positives on existing PIR, regex set is wrong AT TEST TIME, not at production-write time. AC4 enforces. |
| brainstorm: "No Sentry-alert auto-firing — operator-invoked only" | Verified zero Sentry-webhook substrate. `configure-sentry-alerts.sh` is one-way. | Honored. Sentry auto-fetch deferred per spec Non-Goals. |
| spec FR4: `/soleur:go` intent regex | Verified at `plugins/soleur/commands/go.md:45-50`. Existing table: header line 45, separator 46, rows 47=`fix`, 48=`drain`, 49=`review`, 50=`default`. | Plan FR4 prescribes inserting new `incident` row **between line 49 (`review`) and line 50 (`default`)** — i.e., new line 50 pushes `default` to 51. Kieran P0 — earlier "45-50" wording was ambiguous, now fixed. |
| `compound-capture` skill argument contract | Verified: only `--headless` is documented in `$ARGUMENTS`. Skill EXTRACTS context from conversation transcript at Step 2, NOT from positional structured args. | Plan FR5 + Step 8 corrected (Kieran P0): skill emits PIR body inline to transcript, then invokes `/soleur:compound-capture --headless` — letting compound-capture's normal transcript scrape pick up the just-emitted PIR content. No structured arg passing. |
| brainstorm: existing PIR shape in 24 runbooks | Verified: 1 PIR (`dashboard-error-postmortem.md`), 20 runbooks, 3 hybrid. | Reuse existing `runbooks/` dir for `<slug>-postmortem.md`. CTO's brainstorm-time `incidents/` subdirectory suggestion overruled. |
| Stripe key regex `\b(sk\|pk\|rk)_(live\|test)_[A-Za-z0-9]{16,}\b` | Verified missing: `whsec_` (webhook signing — highest-PII risk), `acct_` (Connect), `seti_` (setup intent), `sub_` (subscription), `in_` (invoice). | Plan FR3 + AC5 add: `\bwhsec_[A-Za-z0-9]{16,}\b`, `\bacct_[A-Za-z0-9]{16,}\b`, `\b(seti\|sub\|in)_[A-Za-z0-9]{14,}\b`. Kieran P1 — `whsec_` was the highest-PII omission. |
| brainstorm CLO: PIR `status:` lifecycle field is `closed` | Verified inconsistency in initial plan draft: plan body used `closed` AND `resolved` in 6 different sites. spec.md Phase 4 defines `status: open` initial. | Plan standardizes on `status: resolved` for the terminal closed-via-recovery-verification state. Phase 8 + AC10e gates on `status: resolved` (NOT `closed`). Kieran P0. |

## Open Code-Review Overlap

1 open issue touches our path neighbourhood:

- **#3413 — review: hourly health probe for jikig-ai/kb-template.** Lives at `.github/workflows/kb-template-health-probe.yml` + `knowledge-base/engineering/ops/runbooks/kb-template-drift.md`. **Disposition: acknowledge.** Same parent dir, different file class. #3413 stays open.

No other matches across `plugins/soleur/skills/incident`, `plugins/soleur/commands/go.md`, `.claude/hooks/lib/incidents.sh`, or `AGENTS.core.md`.

## User-Brand Impact

Carried forward from brainstorm `## User-Brand Impact` section.

**Artifact:** `/soleur:incident` skill output — internal PIR markdown (`<slug>-postmortem.md`) committed to `knowledge-base/engineering/ops/runbooks/`.

**Failure modes the diff must mitigate:**

- **If this lands broken:** misclassification of a live incident (operator under-reacts, customer impact compounds before the right runbook fires) — or worse, the founder burns the 72h CNIL window on PIR narrative drafting instead of issuing a notification.
- **If this leaks:** the PIR markdown is committed to a public repo containing un-redacted JWT fragments / customer emails / Stripe IDs / Supabase user UUIDs / session tokens / Doppler env-var values copy-pasted from logs during timeline reconstruction.
- **If sentinel false-positives on existing PIR baseline:** operator can't ship a PIR at all → workflow regression.
- **If trust breaks via wrong-cause framing:** generated PIR points at innocent PR, erodes operator confidence.

**Brand-survival threshold:** `single-user incident`. CPO sign-off via brainstorm `## Domain Assessments` (carry-forward per `cm-tiered-signoff-model`). `user-impact-reviewer` agent auto-fires at PR review per `plugins/soleur/skills/review/SKILL.md` conditional-agent block.

**Mitigations baked into the plan:**

1. Pre-write redaction sentinel (FR3) — mechanical regex, blocking, runs BEFORE inline-emit AND before disk commit.
2. Phase-0 Art. 33/34 notification-trigger gate (FR2) — blocks PIR drafting if EITHER triggers fire, until operator acks notification path.
3. Operator ack on commit (FR2 Phase 7) — drafts emitted INLINE first; commit requires literal `COMMIT-PIR` token.
4. Actor-key + per-command ack on every prod-touching step (TR4) — binds to `hr-menu-option-ack-not-prod-write-auth`.
5. LLM-trust boundary (TR8) — skill computes incident slug + branch name + IDs itself.
6. `user-impact-reviewer` auto-fires at review (TR6).

## Acceptance Criteria

### Pre-merge (PR2)

- [x] **AC1:** PR1 (#3724) merged to `main`. `git grep -l "^brand_survival:\|^brand_threshold:" -- '*.md' '*.yml' '*.yaml' '*.json'` returns zero non-archived hits AND `git grep -l "single-user-incident" -- '*.md' '*.yml' '*.yaml'` returns zero non-archived hits. (Kieran P1: `*.yaml` glob added.) PR2 rebases on top of merged main.
- [x] **AC2:** Files exist: `plugins/soleur/skills/incident/SKILL.md`, `templates/pir.md`, `scripts/redact-sentinel.sh`, `test/redact-sentinel.test.sh`, `test/fixtures/positive-corpus.md`, `test/fixtures/dry-run-incident.json`, `test/fixtures/dry-run-secret-leak.json`, `NOTICE`. Total: **8 new files** (down from 11 — public-PIR artifacts removed per #3732 deferral).
- [x] **AC3:** `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh` exits 0.
- [x] **AC4:** Negative-baseline: `bash plugins/soleur/skills/incident/scripts/redact-sentinel.sh knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md` exits 0.
- [x] **AC5:** Positive-corpus: `bash plugins/soleur/skills/incident/scripts/redact-sentinel.sh plugins/soleur/skills/incident/test/fixtures/positive-corpus.md` exits non-zero with each pattern class flagged at least once: JWT three-segment, email, UUID, Stripe `sk_/pk_/rk_`, Stripe `whsec_`, Stripe `acct_`, Stripe `cus_/pi_/seti_/sub_/in_`, IPv4, env-var-with-value.
- [x] **AC6:** `grep -lE "emit_incident\b|\.rule-incidents\.jsonl\b" plugins/soleur/skills/incident/` returns zero. `grep -lE "^event_type:" plugins/soleur/skills/incident/templates/` returns zero. (Kieran P1: added `event_type` enum collision check.)
- [x] **AC7:** `plugins/soleur/skills/incident/SKILL.md` description is one third-person line per constitution Code Style. `name: incident` in frontmatter. Word count ≤3000 (reduced from 5000 per DHH "SKILL.md under 1500 words" target — relaxed to 3000 given 9-phase content).
- [x] **AC8:** `--dry-run` mode invocation: `bash plugins/soleur/skills/incident/scripts/dry-run.sh test/fixtures/dry-run-incident.json > /tmp/pir-dry-run.txt` produces inline-style output to the tmp file (so subsequent grep ACs are runnable). Output contains `<slug>-postmortem.md` draft body BEFORE any file is written under `runbooks/`. (Kieran P1: addresses "inline output ungreppable" by defining a captured-output mode.)
- [x] **AC9:** Phase 1 dry-run renders the decision-criteria text inline BEFORE asking for confirmation. `grep -c 'criterion' /tmp/pir-dry-run.txt` returns ≥3. (SpecFlow Critical #1.)
- [x] **AC10:** Phase 6 sentinel runs BEFORE Phase 7 inline-emit. Verified via positive-corpus fixture: `/tmp/pir-dry-run.txt` contains NO un-redacted matches before the sentinel-pass confirmation line. Sentinel-precedes-emit verified by grep ordering: `grep -n 'sentinel:.*pass' /tmp/pir-dry-run.txt` line number < `grep -n '<draft begins>' /tmp/pir-dry-run.txt` line number. (SpecFlow Critical #2.)
- [x] **AC11:** Phase 7 commit gate requires literal `COMMIT-PIR` token. Dry-run subprocess inputs `yes` / `y` / `ok` / `approved` are all REJECTED with "Type exactly: COMMIT-PIR" prompt. Input `COMMIT-PIR` writes the PIR file; input absence times out without writing. (SpecFlow Critical #3.)
- [x] **AC12:** Art. 33/34 dry-run: fixture with `data_categories_breached: ["email", "userId"]` and `affected_user_count: 1` AND `risk_to_subjects: high` blocks Phase 3+ with operator ack prompt naming BOTH 72h Art. 33 deadline AND "without undue delay" Art. 34 advisory. Setting fixture `risk_to_subjects: low` triggers only the Art. 33 ack (Art. 34 advisory NOT raised). (SpecFlow Important #4: Art. 34 parity.)
- [x] **AC13:** Phase 8 dry-run: when fixture PIR has `status: open`, invoking Phase 8 exits non-zero with `Phase 8 requires PIR status: resolved. Current: open.` Operator updates fixture `status: resolved` → Phase 8 invokes `/soleur:compound-capture --headless` and verifies via `grep -n 'compound-capture' /tmp/pir-dry-run.txt`. (SpecFlow Important #5 + Kieran P0: compound-capture takes `--headless` only; PIR body inline-emitted to transcript for the skill's own scrape.)
- [x] **AC14:** `/soleur:go` intent table row added between line 49 (`review`) and line 50 (`default`) of `plugins/soleur/commands/go.md`. New row: `| incident | The user describes a live or recent production incident (outage, breach, customer-impact, Sentry alert) needing classification + PIR | \`/soleur:incident\` |`. Verified by line-count: `wc -l plugins/soleur/commands/go.md` shows file is 1 line longer than at branch base. (Kieran P0: corrected line range.)
- [x] **AC15:** `NOTICE` present with MIT attribution to alirezarezvani/claude-skills + statement "Clean-room derivation; no upstream code lifted verbatim." `SKILL.md` carries `Inspiration:` header pointing at `NOTICE`.
- [x] **AC16:** Spec.md `[Updated 2026-05-13]` markers added to ALL D1-direction call-sites: Problem Statement, Goals, Non-Goals, FR1, AC1-AC3. Brainstorm doc Key-Decisions row gets one marker. Issue #3724 body rewritten before PR1 begins. (Kieran P1: earlier scope was too narrow.)
- [x] **AC17:** Secret-leak fixture (`triggers: ["api_key_leaked"]`) demonstrates PIR template's `Step 0: REVOKE FIRST` preamble hardcoded section per learning `2026-02-10-api-key-leaked-in-git-history-cleanup.md`. Verified: `grep -c "REVOKE FIRST" /tmp/pir-dry-run.txt` ≥1 for secret-leak fixture; returns 0 for non-secret-leak fixture.
- [ ] **AC18:** Multi-agent review at Step 7 fires `user-impact-reviewer` (auto-triggered by `brand_survival_threshold: single-user incident`), `pr-review-toolkit:silent-failure-hunter` on sentinel script, and `security-sentinel` on regex set. All three CONCUR before merge.
- [ ] **AC19:** Closes #2725 (via `Closes #2725` in PR body, not title — per `wg-use-closes-n-in-pr-body-not-title-to`). References #3724 as merged prerequisite and #3732 as deferred public-PIR follow-up.

### Post-merge (operator)

- [ ] **AC20:** First real-incident invocation: when a real production incident occurs, run `/soleur:incident` and verify the 9-phase flow produces the internal PIR. Validates regex-set false-positive rate against real (not synthesized) content. Re-evaluation criterion for #3726 (sentinel-to-AGENTS-rule promotion), #3725 (ROPA wiring), and #3732 (public-PIR scope-back-in trigger).

## Functional Requirements

### FR1: D1 rename sweep (PR1, separate branch — tracked under #3724, **direction reversed**)

**Reversed from spec FR1.** Rename TOWARD dominant forms:

- Frontmatter key: `brand_threshold:` (1 file) → `brand_survival_threshold:`
- Frontmatter key: `brand_survival:` (5 files) → `brand_survival_threshold:`
- Frontmatter key: `threshold:` semantic uses (audit each — 7 files) → `brand_survival_threshold:`
- Value-form: `single-user-incident` (hyphenated, 50 files) → `single-user incident` (space)

Total touch: ~13 frontmatter renames + ~50 value-form renames. No behavior change.

Reciprocal updates in PR2: spec.md gets `[Updated 2026-05-13]` markers in Problem Statement + Goals + Non-Goals + FR1 + AC1-AC3 (per AC16); brainstorm doc gets a marker; issue #3724 body rewritten before PR1 begins.

### FR2: `/soleur:incident` skill (PR2)

9 phases (Phase 0 through Phase 8 — the skill-internal numbering, distinct from this plan's Implementation Steps). Adjustments per plan-time research + SpecFlow + Kieran:

- **Phase 0** — Capture operator-provided facts: title, detected_at (UTC), symptom prose, suspected_change pointer (PR# or commit SHA), affected_user_count estimate.
- **Phase 1** — Classification (<60s target). Skill renders the `brand_survival_threshold` decision-criteria text INLINE first (SpecFlow Critical #1) — operator sees the criteria before confirming. Output: advisory recommendation + rationale. Operator confirms or overrides with `classification_override: {advisory: X, chosen: Y, reason: "<text>"}` written to PIR frontmatter.
- **Phase 2** — Art. 33/34 gate. Emit `art_33_triggered: bool`, `art_34_triggered: bool`, `art_33_deadline = detected_at + 72h` (CNIL hard deadline), `art_34_advisory = "as soon as feasible per Art. 34 — no fixed numeric"`. Phase 3+ BLOCKS if EITHER triggers fire (SpecFlow Important #4 — Art. 34 parity with Art. 33). Operator ack required to proceed; ack types each deadline separately if both fire.
- **Phase 3** — Runbook routing. `awk`-scan 24 existing runbook files for `triggers:` frontmatter; literal-substring match against operator symptom tokens; surface top-3 matches with similarity score. If 0 matches: surface `no runbook matches — proceed to ad-hoc response` (no dead-end). Operator selects 0-N matches; selected runbook slugs **auto-populate Phase 4 `triggers[]` verbatim** (SpecFlow Important #5).
- **Phase 4** — Internal PIR scaffold. Substitute via `sed` against `templates/pir.md`. Frontmatter: `title`, `date`, `incident_pr`, `incident_window`, `suspected_change`, `brand_survival_threshold`, `status: open`, `triggers[]`, `classification_override` (if applicable), `art_33_triggered`, `art_34_triggered`. Body sections: Symptom, Root-cause hypothesis (table), Timeline (actor-key tagged), Recovery verification, Follow-ups, Who-was-affected (enumerated by USER ROLE: prospect / authenticated app user / legal-document signer / admin via Access / billing customer / OAuth installation owner per `2026-05-06-user-impact-section-by-role-not-surface.md`).
- **Phase 5** — (no separate public artifact in MVP — deferred to #3732). Skill emits a one-line note in dry-run output: `Public-summary deferred to #3732`.
- **Phase 6** — Redaction sentinel (BLOCKING). Runs BEFORE Phase 7 inline-emit (FR3 pre-inline-emit gate). On non-zero exit: surfaces offsets, blocks Phase 7, operator iterates. No max-iteration cap (DHH/code-simplicity cut: if operator stuck, fix regex — `Ctrl-C` always exits the skill).
- **Phase 7** — Operator review + commit. Drafts emitted INLINE for operator review (sentinel has already cleared them in Phase 6). Commit requires **literal `COMMIT-PIR` token** (SpecFlow Critical #3) — operator types exactly `COMMIT-PIR`, case-sensitive, no LLM fuzzy-interpretation. Free-form yes is REJECTED. On `COMMIT-PIR`: write `<slug>-postmortem.md` to `runbooks/`. No `ABORT` token — `Ctrl-C` is documented as the abort path.
- **Phase 8** — Compound-capture handoff. **BLOCKS until operator confirms `status: resolved`** on the PIR (SpecFlow Important #5). When status flips to resolved: skill emits the closed-PIR body inline to the conversation transcript (so compound-capture's Step 2 transcript scrape sees it), then invokes `/soleur:compound-capture --headless` (Kieran P0 — only `--headless` is supported; no structured args). The skill MUST NOT pass positional args other than `--headless`.

### FR3: Pre-write redaction sentinel (PR2)

- **Mode arg:** removed — sentinel runs in single "internal" mode only (no public mode in MVP — deferred to #3732).
- **Exit-code contract:** 0 = clean; 1 = redaction needed; 2 = invalid arguments. (No exit 3 / max-iterations; DHH/code-simplicity cut.)
- **Output offset format:** `at offset N: <8-prefix>***<8-suffix> matched pattern P`. No full token in output (meta-redaction).
- **Pre-inline-emit gate:** sentinel runs BEFORE Phase 7 emits anything inline to operator transcript (SpecFlow Critical #2).
- **Regex set (Stripe expanded per Kieran P1):**
  - JWT three-segment: `eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}`
  - Email: `\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b`
  - UUID v1-v5: `\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b` (version-agnostic per Supabase `auth.users.id` shape)
  - Stripe API keys: `\b(sk|pk|rk)_(live|test)_[A-Za-z0-9]{16,}\b`
  - **Stripe webhook signing secret: `\bwhsec_[A-Za-z0-9]{16,}\b`** (highest-PII addition — Kieran P1)
  - Stripe Connect account: `\bacct_[A-Za-z0-9]{16,}\b`
  - Stripe customer / payment-intent / setup-intent / subscription / invoice: `\b(cus|pi|seti|sub|in)_[A-Za-z0-9]{14,}\b`
  - IPv4: `\b(?:\d{1,3}\.){3}\d{1,3}\b` (IPv6 deferred via `# TODO(post-MVP): IPv6 — file follow-up issue` per Kieran P1 + `wg-when-deferring-a-capability-create-a`)
  - Env-var-with-value: `\b(DOPPLER|SENTRY|STRIPE|SUPABASE|OPENAI|ANTHROPIC|GITHUB|VERCEL|CLOUDFLARE)_[A-Z_]+=[^[:space:]]+`

### FR4: `/soleur:go` intent routing extension (PR2)

Insert new intent row into `plugins/soleur/commands/go.md` immediately after line 49 (`review` row), before line 50 (`default` row). New row content (Kieran P0 corrected wording — no inline backticks inside table cells, since markdown table parsing breaks on unbalanced backticks):

```
| incident | The user describes a live or recent production incident (outage, breach, customer-impact, Sentry alert) needing classification + PIR | `/soleur:incident` |
```

The backticks around `/soleur:incident` are balanced and standard for the existing rows. The trigger-signals cell uses prose only — no inline-code markup mid-cell.

### FR5: Compound-capture handoff (PR2, Kieran P0 corrected)

Phase 8 invokes `/soleur:compound-capture --headless`. The argument contract is the ONLY supported one (verified via `plugins/soleur/skills/compound-capture/SKILL.md`). Mechanism:

1. Skill emits the closed PIR body (frontmatter + sections) inline to the conversation transcript.
2. Skill invokes `skill: soleur:compound-capture --headless`.
3. compound-capture's Step 2 transcript-scrape picks up the PIR body and processes it normally.

This avoids modifying compound-capture's contract. If structured arg-passing becomes load-bearing, file a cross-skill change request — out of scope here.

Phase 8 BLOCKS until PIR frontmatter shows `status: resolved` (SpecFlow Important #5). Skill greps `^status:\s*resolved$` in the current PIR file before invoking compound-capture.

### FR6: Naming-collision avoidance (PR2)

Per spec.md FR6 + Kieran P1 addition: skill MUST NOT define or write any of:

- Function name `emit_incident()` (collides with `.claude/hooks/lib/incidents.sh:156`)
- File path `.claude/.rule-incidents.jsonl`
- Frontmatter / output field `event_type:` with values from `{deny, bypass, applied, warn}` (rule-telemetry enum at `.claude/hooks/lib/incidents.sh:127,162,227`)

AC6 enforces all three via `grep -lE`.

### FR7: LLM-trust boundary (PR2)

Skill computes identifiers locally:

- Incident slug: `awk` over title field → kebab-case, drop non-`[a-z0-9-]`.
- File paths: locally derived from slug.
- `incident_pr` value: skill validates is numeric before substitution. `incident_window` value: skill validates against ISO-8601 regex. LLM-emitted IDs that fail validation cause Phase 4 to halt with explicit operator-fix prompt.

## Technical Requirements

### TR1: SKILL.md contract

- Single-line description, third person.
- `name: incident`.
- Word count ≤3000 (DHH-influenced ceiling).
- Bash + `gh` + `git` + `jq` + `awk` only. No stdlib Python CLI per parent #2718 audit.

### TR2: Template structure

- `templates/pir.md` heredoc-friendly substitutions: `{{TITLE}}`, `{{DATE}}`, `{{INCIDENT_PR}}`, `{{INCIDENT_WINDOW}}`, `{{SUSPECTED_CHANGE}}`, `{{BRAND_SURVIVAL_THRESHOLD}}`, `{{STATUS}}`, `{{TRIGGERS_LIST}}`, `{{WHO_AFFECTED_BY_ROLE}}`, `{{ART_33_DEADLINE}}` (conditional), `{{CLASSIFICATION_OVERRIDE_BLOCK}}` (conditional).
- NO `|` inside inline-code in tables per `2026-04-18-compliance-runbook-authoring-gotchas.md`.
- When `triggers:` contains a secret-leak token (`api_key_leaked`, `credentials_exposed`, `token_exposed`, `secret_in_logs`), template hardcodes `Step 0: REVOKE FIRST` preamble per `2026-02-10-api-key-leaked-in-git-history-cleanup.md`.

### TR3: Redaction-sentinel testing

- Negative-baseline: `dashboard-error-postmortem.md` (post-D1-rename) must NOT trigger.
- Positive-corpus: `test/fixtures/positive-corpus.md` synthesized per `cq-test-fixtures-synthesized-only` — every regex class triggers ≥1.
- Bash test harness follows `git-worktree/test/lease-protects-active.test.sh` pattern (PASS/FAIL counter, trap cleanup, `set -uo pipefail`).

### TR4: Actor-key + ack-gate compliance

Every operator-directed step in PIR template tagged `agent` / `agent-with-ack` / `human` per `dashboard-error-postmortem.md` (post-rename) convention. Prod-touching steps cite `hr-menu-option-ack-not-prod-write-auth` inline.

### TR5: MIT attribution

- `NOTICE` — MIT-attribution to alirezarezvani/claude-skills.
- `SKILL.md` one-line `Inspiration:` header pointing at NOTICE.

### TR6: user-impact-reviewer integration

PIR frontmatter `brand_survival_threshold: single-user incident` automatically triggers `user-impact-reviewer` per `plugins/soleur/skills/review/SKILL.md`. AC18 enforces CONCUR before merge.

### TR7: ROPA-emission scope

Per spec TR7 — Art. 33/34 fields emitted in PIR frontmatter; ROPA wiring to `knowledge-base/legal/article-30-register.md` is DEFERRED to #3725.

### TR8: LLM-trust boundary

Per FR7. Skill validates LLM-emitted format-sensitive fields before substituting into templates.

### TR9: GDPR Gate carry-forward

CLO assessment from brainstorm `## Domain Assessments` carries forward. Full `/soleur:gdpr-gate` invocation runs at `/work` Phase 2 exit per `hr-gdpr-gate-on-regulated-data-surfaces`.

## Implementation Steps

(Renamed from "Phases" to "Steps" to avoid collision with the skill-internal Phase 0-8 numbering — Kieran P2 fix.)

### Step 0 — D1 prerequisite (separate branch, tracked under #3724)

Operator-driven; this plan does NOT execute D1. Acceptance: PR1 merges to `main` with the reversed direction. Before Step 1 begins:

```bash
git fetch origin main && \
  git rebase origin/main && \
  git grep -l "^brand_survival:\|^brand_threshold:" -- '*.md' '*.yml' '*.yaml' '*.json' && \
  git grep -l "single-user-incident" -- '*.md' '*.yml' '*.yaml'
```

All three commands return zero non-archived hits.

### Step 1 — Skill scaffold + NOTICE + templates (RED tests authoring)

1. Create `plugins/soleur/skills/incident/SKILL.md` with frontmatter (`name: incident`, single-line description) and Phase 0-8 header outline. Phase bodies empty.
2. Create `NOTICE` with MIT attribution.
3. Write `templates/pir.md` with substitution-point comments + secret-leak conditional `Step 0: REVOKE FIRST` block.
4. Write `test/fixtures/positive-corpus.md` with synthesized positives for every regex class.
5. Write `test/fixtures/dry-run-incident.json` (synthetic incident) and `test/fixtures/dry-run-secret-leak.json` (synthetic secret-leak with `triggers: [api_key_leaked]`).
6. Write `test/redact-sentinel.test.sh` (BATS-style). Tests:
   - **Test 1 (RED):** Negative-baseline — exit 0 on existing PIR.
   - **Test 2 (RED):** Positive-corpus — each regex class triggers ≥1.
   - **Test 3 (RED):** Invalid mode/arg — exit 2.
   - **Test 4 (RED):** Output format match (`at offset \d+: .{8}\*\*\*.{8}`).
7. Run tests — all RED.

### Step 2 — Redaction sentinel implementation (GREEN)

1. Implement `scripts/redact-sentinel.sh`. Bash + `grep -nE` + `awk`.
2. Output format per FR3.
3. Run test harness — all 4 tests pass.

### Step 3 — SKILL.md authoring (Phase 0-8 body)

1. Author each skill-internal Phase 0-8 body in `SKILL.md`. Inline output via standard skill bash patterns.
2. Phase 1: render decision criteria text inline BEFORE asking for confirm.
3. Phase 2: compute `art_33_deadline = detected_at + 72h` via `date -u -d "${detected_at} +72 hours"`. Block on Art. 33 OR Art. 34 trigger.
4. Phase 3: `awk`-scan runbooks for `triggers:`; literal-substring match; surface top-3; selected runbook slugs auto-populate Phase 4 `triggers[]`.
5. Phase 4: `sed`-substitute against template.
6. Phase 6: invoke `redact-sentinel.sh` against draft BEFORE writing to disk OR emitting inline.
7. Phase 7: emit cleared draft INLINE; commit ack requires literal `COMMIT-PIR` token; on token, `git add` + write to `runbooks/`.
8. Phase 8: grep `^status:\s*resolved$` in PIR file; on match, emit PIR body inline to transcript, then invoke `skill: soleur:compound-capture --headless`.

### Step 4 — `--dry-run` mode + integration tests

1. Implement `scripts/dry-run.sh` that wraps the skill with output-redirect for grep-based ACs (AC8-AC13 are dry-run-mode tests). Captures phase output to a tmp file.
2. Dry-run on `dry-run-incident.json`: verify draft emit + ack-gate behavior + sentinel ordering.
3. Dry-run on `dry-run-secret-leak.json`: verify `Step 0: REVOKE FIRST` preamble present.

### Step 5 — `/soleur:go` intent routing extension

1. Edit `plugins/soleur/commands/go.md` — insert new `incident` row between line 49 (`review`) and line 50 (`default`). Wording per FR4.
2. Verify table renders: `cat plugins/soleur/commands/go.md | head -52 | tail -10` shows 5 data rows.

### Step 6 — Documentation reciprocal updates

1. Spec.md `[Updated 2026-05-13]` markers in: Problem Statement (line 21 quotes `brand_threshold`), Goals (4 occurrences), Non-Goals (1 occurrence), FR1, AC1-AC3. (Per Kieran P1 — scope widened from earlier draft.)
2. Brainstorm doc Key-Decisions row marker.
3. Issue #3724 body re-written with reversed direction BEFORE PR1 begins.
4. `dashboard-error-postmortem.md` (post-rename) header note pointing at `/soleur:incident`.

### Step 7 — Multi-agent review

1. Spawn `user-impact-reviewer` (auto-fires per brand-threshold).
2. Spawn `pr-review-toolkit:silent-failure-hunter` on `scripts/redact-sentinel.sh`.
3. Spawn `soleur:engineering:review:security-sentinel` on regex set for OWASP / CWE coverage.
4. Spawn `soleur:engineering:review:pattern-recognition-specialist` for cross-skill consistency.
5. Spawn `soleur:engineering:review:code-simplicity-reviewer` for final YAGNI check.
6. Apply P0/P1 findings inline; P2/P3 → scope-out tracking issues per `/soleur:ship` conventions.

### Step 8 — PR ready + merge

1. Confirm PR1 (#3724) merged to main.
2. `git fetch origin main && git rebase origin/main`.
3. Update PR body: include `Closes #2725`, link to brainstorm + spec + plan, full AC checklist.
4. `/soleur:ship` for preflight + final review wiring.
5. `gh pr ready 3721 && gh pr merge 3721 --squash --auto`.

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| Extend `/soleur:compound --incident` mode | Compound reads `.rule-incidents.jsonl` for rule-telemetry; overload re-triggers naming collision |
| Two thin skills (`/soleur:sev` + `/soleur:pir`) | Compound complexity not justified; operator-friction higher |
| Parallel SEV-1/2/3/4 taxonomy | Reuse canonical `brand_survival_threshold` post-D1-reversal |
| Sentry auto-fire | No webhook substrate; violates `hr-menu-option-ack-not-prod-write-auth` |
| Public summary in MVP | Soleur has ~0 ICP usage; deferred to #3732 per DHH + code-simplicity convergence |
| Single-artifact w/o sentinel | Worst-case-named PII leak — sentinel is brand-survival defense |
| Wholesale port of alirezarezvani upstream | Clean-room with NOTICE attribution per parent #2718 |
| Rename TO `brand_threshold:` (original spec direction) | ~110 files vs ~13; breaks brainstorm + preflight tooling |
| Max-iterations + `--justify-pattern` escape hatch on sentinel | DHH + code-simplicity converge: solves hypothetical compliance for product with no auditors — Ctrl-C suffices |
| Split commit tokens (`COMMIT-PIR-INTERNAL` + `COMMIT-PIR-PUBLIC`) | Moot with public artifact deferred — single `COMMIT-PIR` |
| Literal `ABORT` token in every phase | Ctrl-C is universal abort; codifying adds parser surface w/o behavior |
| `--resume <slug>` state file | YAGNI; revisit if real-incident usage shows operator re-runs mid-flow |

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Sentinel false-positives on existing PIR baseline → blocks PIR commits | Medium | High | Step 1 Test 1 (negative-baseline) + AC4 |
| Sentinel false-negatives on real production content → PII commit | Medium-High | Brand-survival | AC20 (post-merge first-real-incident) validates; multi-agent review at Step 7 cross-checks regex coverage |
| LLM interprets ambiguous "yes" as commit approval (Critical) | Medium | High (PII commit) | FR2 Phase 7 literal `COMMIT-PIR` token; AC11 enforces |
| Unredacted draft hits transcript before sentinel runs (Critical) | Medium-High | Brand-survival | FR3 pre-inline-emit gate; AC10 enforces ordering |
| Phase 8 compound-capture fires on `status: open` PIR | Medium | Medium | FR5 blocks on `status: resolved`; AC13 enforces |
| Art. 34 (higher severity) not blocking while Art. 33 was | Medium | High (compliance gap) | FR2 Phase 2 parity; AC12 enforces |
| `/soleur:go` regex false-positive routing (e.g. "we had an incident yesterday") | Low | Low | Trigger keywords reasonably specific; `/soleur:go` AskUserQuestion fallback exists |
| Spec.md D1 reversal reciprocal-update scope missed (Problem/Goals/Non-Goals — Kieran P1) | Low (caught) | Low | AC16 widens marker scope |
| Compound-capture arg contract mismatch (Kieran P0) | Caught | Caught | FR5 uses `--headless` + transcript-scrape, no positional args |
| `status: closed` vs `status: resolved` enum drift (Kieran P0) | Caught | Caught | Standardized on `resolved` across all 6 sites |
| `/soleur:go` line-range miswording (Kieran P0) | Caught | Caught | FR4 + AC14 specify line-49+50 insertion |
| Stripe `whsec_` PII omission (Kieran P1) | Caught | High | FR3 regex set expanded |
| D1 (#3724) never merges → PR2 indefinitely blocked | Low | High | PR1 mechanically simple; escalate via /soleur:plan-review on #3724 if blocked >1 week |
| `event_type` enum collision sneaks in via PIR frontmatter (Kieran P1) | Low | Medium | AC6 grep block |
| AC1 / `*.yaml` glob miss (Kieran P1) | Caught | Low | AC1 globs all three extensions |
| AC9/AC10 ungreppable inline output (Kieran P1) | Caught | Medium | `--dry-run` flag (Step 4) writes to tmp file; ACs use that file |

## Domain Review

**Domains relevant:** Product, Legal, Engineering, Marketing (carry-forward from brainstorm — CPO + CLO + CTO + CMO).

### Product (CPO) — carry-forward

**Status:** reviewed (brainstorm)
**Assessment:** Reframe outcome to "correct SEV <60s + redaction-gated PIR scaffold." Skill, not agent. Reuse canonical `brand_survival_threshold` 3-tier. Ship D1 first as PR1.

### Legal (CLO) — carry-forward

**Status:** reviewed (brainstorm)
**Assessment:** Phase-0 Art. 33/34 gate BEFORE drafting. Pre-write redaction sentinel. ROPA frontmatter (Art. 30 input). gdpr-gate placement pre-write blocking-by-acknowledgment.

**Plan-time addendum:** Plan extends Art. 34 blocking parity per SpecFlow Important #4 — Art. 34 is higher severity than Art. 33.

### Engineering (CTO) — carry-forward

**Status:** reviewed (brainstorm). **Plan-time addendum:** CTO's file-existence claims had CWD path-resolution drift; orchestrator verified all claims via direct grep. Skill not agent — confirmed. Clean-room SEV taxonomy resolved to `brand_survival_threshold` (post-D1-reversal).

### Marketing (CMO) — carry-forward + revision

**Status:** reviewed (brainstorm); **plan-time revision:** CMO's two-artifact scope-expansion DEFERRED to #3732 per DHH + code-simplicity convergence. Internal PIR is MVP load-bearing artifact; public-safe summary opens after first real customer-impact incident (re-evaluation criteria in #3732).

### Product/UX Gate

**Tier:** NONE
**Decision:** N/A
**Agents invoked:** none
**Skipped specialists:** none
**Pencil available:** N/A

No `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` files. Mechanical escalation rule does not fire.

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder, or omits the threshold will fail `deepen-plan` Phase 4.6.** This plan's section is populated (carry-forward); do not strip.
- **D1 direction reversal must be reciprocated.** Plan FR1 reverses; spec.md gets `[Updated 2026-05-13]` markers in **Problem Statement + Goals + Non-Goals + FR1 + AC1-AC3** (Kieran P1 — earlier scope was narrower); brainstorm marker; issue #3724 body MUST be updated BEFORE PR1 begins.
- **PR1 (#3724) is a hard prerequisite for PR2.** Step 0 enforces. If PR2 lands first, the skill writes the right key but the rename sweep hasn't happened → ~13 legacy minority-form files remain inconsistent.
- **Public-safe PIR is OUT of MVP** (deferred to #3732). If a real customer-impact incident happens and operator needs public copy NOW, hand-author it and re-open #3732 with the patterns observed.
- **Negative-baseline fixture-test is load-bearing.** If sentinel false-positives on `dashboard-error-postmortem.md` (post-rename), regex set is wrong → unusable for future PIRs.
- **Test fixtures are synthesized only** per `cq-test-fixtures-synthesized-only`. Do NOT paste real production JWT/email/Stripe ID into `test/fixtures/`. Synthesize from format specs.
- **`/soleur:go` intent extension is 1 line, trigger tokens are load-bearing.** Picked: `incident`, `outage`, `down`, `breach`, `errored`, `customer says`, `Sentry alert`, `production is down`. Validate with synthetic test invocations before merge.
- **Naming-collision avoidance enforced by grep.** AC6 greps three surfaces (function name, jsonl path, event_type enum). Per learning `2026-04-24-rule-metrics-emit-incident-coverage-session-gotchas.md`.
- **"Pre-write" means pre-INLINE-EMIT, not just pre-disk-commit.** SpecFlow Critical #2: transcripts are write boundaries. Phase 6 runs before Phase 7 emit. AC10 ordering check enforces.
- **Free-form "yes" is a commit-bypass vector.** SpecFlow Critical #3: LLM orchestrating the skill could fuzzy-interpret "ok looks good" as commit. Literal `COMMIT-PIR` token only, case-sensitive. AC11 enforces.
- **Art. 34 blocking parity is intentional.** SpecFlow Important #4 — Art. 34 is higher severity than Art. 33.
- **Phase 3 → Phase 4 `triggers[]` auto-population.** Selected runbook slugs become `triggers[]` entries verbatim. No re-typing.
- **Phase 8 BLOCKS on `status: open`.** SpecFlow Important #5 — premature compound-capture pollutes learning. Skill greps `^status:\s*resolved$` before invoking.
- **No max-iterations on sentinel.** DHH + code-simplicity: operator iterates or `Ctrl-C`. If genuinely stuck, fix regex.
- **No literal `ABORT` token.** `Ctrl-C` is universal. Plan does NOT add parser surface for it.
- **CPO sign-off recorded at brainstorm time** per `cm-tiered-signoff-model`. Plan-time does not re-invoke CPO; PR-review-time invokes `user-impact-reviewer`.
- **Step 6 reciprocal doc updates are docs-only.** Plan SKILL body itself is the code surface that triggers `AGENTS.rest.md` loading.
- **compound-capture takes ONLY `--headless`** (Kieran P0). FR5 uses transcript-scrape via `--headless` invocation — does NOT pass positional structured args.
- **`status: resolved` is canonical** (Kieran P0). All 6 plan call-sites use `resolved`; spec.md gets `[Updated 2026-05-13]` markers if it diverges.
- **Stripe regex set was incomplete in spec** (Kieran P1). FR3 adds `whsec_` (webhook secrets — highest PII), `acct_`, `seti_`/`sub_`/`in_`.
- **AC1 globs include `*.yaml` AND `*.yml`** (Kieran P1). YAML extension variance matters for `.github/workflows/`.
- **Reading brainstorm vs spec vs plan: the plan is most authoritative.** When in doubt, defer to plan-time `## Research Reconciliation`.

## Test Plan

**Unit (RED-then-GREEN per `cq-write-failing-tests-before`):**

- Step 1 writes 4 RED tests in `test/redact-sentinel.test.sh`. Step 2 implements GREEN.

**Integration (Step 4):**

- Dry-run on `dry-run-incident.json` — verify ack-gate, sentinel ordering, transcript-scrape for compound-capture.
- Dry-run on `dry-run-secret-leak.json` — verify `Step 0: REVOKE FIRST` preamble.

**Multi-agent review (Step 7):**

- `user-impact-reviewer` (CONCUR per AC18).
- `pr-review-toolkit:silent-failure-hunter` on sentinel.
- `security-sentinel` on regex set.
- `pattern-recognition-specialist` for cross-skill consistency.
- `code-simplicity-reviewer` for final YAGNI check.

**Post-merge:**

- AC20: first real-incident invocation.

## Files to Create

| Path | Purpose |
|---|---|
| `plugins/soleur/skills/incident/SKILL.md` | Main skill orchestration, Phase 0-8 body |
| `plugins/soleur/skills/incident/NOTICE` | MIT attribution |
| `plugins/soleur/skills/incident/templates/pir.md` | Internal PIR template |
| `plugins/soleur/skills/incident/scripts/redact-sentinel.sh` | Pre-write redaction sentinel |
| `plugins/soleur/skills/incident/scripts/dry-run.sh` | `--dry-run` wrapper for AC8-AC13 capturable output |
| `plugins/soleur/skills/incident/test/redact-sentinel.test.sh` | RED-then-GREEN test harness |
| `plugins/soleur/skills/incident/test/fixtures/positive-corpus.md` | Synthesized positive corpus |
| `plugins/soleur/skills/incident/test/fixtures/dry-run-incident.json` | Synthetic incident fixture |
| `plugins/soleur/skills/incident/test/fixtures/dry-run-secret-leak.json` | Synthetic secret-leak fixture |

**Total: 9 new files** (down from 11 in earlier draft; public-PIR artifacts removed per #3732 deferral).

## Files to Edit

| Path | Change |
|---|---|
| `plugins/soleur/commands/go.md` | Insert `incident` intent row between line 49 (`review`) and line 50 (`default`) per FR4. |
| `knowledge-base/project/specs/feat-incident-commander-2725/spec.md` | Add `[Updated 2026-05-13: D1 direction reversed per plan Research Reconciliation]` markers in **Problem Statement, Goals, Non-Goals, FR1, AC1-AC3** (Kieran P1 scope-widened). |
| `knowledge-base/project/brainstorms/2026-05-13-incident-commander-brainstorm.md` | Add `[Updated 2026-05-13]` marker to Key-Decisions row for D1 direction. |
| `knowledge-base/engineering/ops/runbooks/dashboard-error-postmortem.md` | Header note pointing at `/soleur:incident` for future PIR scaffolding. (Frontmatter key already renamed by D1.) |

**Files NOT edited (deferred):**

- `AGENTS.core.md` — no rule add/remove. `cq-pir-redaction-sentinel` promotion is #3726.
- `plugins/soleur/skills/preflight/SKILL.md` — already greps correct prose form.
- `plugins/soleur/skills/review/SKILL.md` — `user-impact-reviewer` already auto-wires.
- `knowledge-base/legal/article-30-register.md` — ROPA wiring is #3725.

## Resume Prompt

```
/soleur:work knowledge-base/project/plans/2026-05-13-feat-incident-commander-skill-plan.md

Branch: feat-incident-commander-2725
Worktree: .worktrees/feat-incident-commander-2725/
Issue: #2725
PR: #3721 (draft)
Brainstorm: knowledge-base/project/brainstorms/2026-05-13-incident-commander-brainstorm.md
Spec: knowledge-base/project/specs/feat-incident-commander-2725/spec.md
Child issues:
  - #3724 (D1 prerequisite — direction REVERSED; update issue body before PR1)
  - #3725 (ROPA wiring, post-MVP)
  - #3726 (sentinel-to-AGENTS-rule promo, post-first-real-incident)
  - #3732 (public-PIR artifact, deferred per plan review)
Brand-survival threshold: single-user incident
Lane: cross-domain
Plan reviewed; YAGNI cuts applied (public-PIR deferred, no max-iter escape hatch, single COMMIT-PIR token, Ctrl-C abort). P0+P1 correctness fixes applied (compound-capture --headless, status: resolved, line-49+50 go.md insert, Stripe whsec_, *.yaml globs, event_type collision check, --dry-run mode).
PR1 (#3724) is hard prerequisite for PR2.
```
