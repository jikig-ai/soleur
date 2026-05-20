---
title: "Sentry residency reframe — PR-1: token-scope probe + PIR Gate-3b reopen + same-PR breadcrumbs"
date: 2026-05-19
type: feat
parent_issue: 3861
closes_issues: [3962]
references_issues: [3861, 3849]
draft_pr: 4044
brand_survival_threshold: single-user incident
lane: cross-domain
triad: [CPO, CLO, CTO]
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md
spec: knowledge-base/project/specs/feat-sentry-residency-reframe-3861/spec.md
---

## Overview

PR-1 of a two-PR corrective series under #3861. Establishes first-party reproducible evidence (a 3-step token-scope probe report) that supports reframing the falsified "phantom-ingest to unowned third-party org" narrative committed 2026-05-17 (PR-α #3904 + PR-β #3945 + PR-γ #3946). Reopens the PIR per Phase 8 Gate 3b prescription, strikes the now-falsified Art-33 flags, refines one historical comment in the audit script, and adds dated forward-pointer breadcrumbs in 3 cited consumers so the live disclosure register does not read as falsified-truth between PR-1 and PR-2 merges.

**PR-2 (Article 30 PA8 §(d) retract-in-place, ADR-031, learnings — full corpus sweep) is OUT OF SCOPE here.** PR-1 ships the evidence; PR-2 ships the corpus retraction that points at it.

**Conditional-halt invariant (TR8):** the probe outcome bounds validity of everything downstream. The /work flow MUST check `STEP1 == 401 && STEP2 == 200 && STEP3 == 200` before any markdown edit. On any divergence, halt — do NOT pre-commit reframe narrative.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified 2026-05-19) | Plan response |
|---|---|---|
| FR10: audit-script header reframe `phantom-ingest` → `destination-controllability` | Operational header at L72 already says "4-gate destination-controllability check"; "phantom" framing only appears in the L127 historical-context comment. | Narrow to a one-line comment refinement at L127. Operational header untouched. |
| Brainstorm input cited PIR at `…/runbooks/…` | PIR is at `…/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md` (Article 30 register L160 references the correct path). | Use the actual post-mortems path. |
| Spec FR5 said "strike `art_33_*` + `classification_override.chosen: none`" | Lines 8/13/15/16 in PIR carry these keys; `classification_override` object holds a load-bearing `reason:` provenance string. | DELETE `art_33_triggered` + `art_33_deadline` lines (not blank). Update `classification_override.chosen: none` → `chosen: superseded-2026-05-19`. Prefix `reason:` value with `"[Superseded 2026-05-19 per Phase 9 Gate-3b correction.] "`. |
| Spec assumes PR-1 = probe + PIR only | Architecture-strategist P0 (plan review): PIR `status: open` while cited consumers (PA8 §(d), compliance-posture row 89, 2026-05-17 audit) still narrate phantom-ingest as fact creates an inconsistency window between PR-1 and PR-2 merges. | Add 3 dated-breadcrumb one-liners (NOT retract-in-place; that is PR-2's job). Breadcrumbs preserve the still-falsified prose verbatim and add a forward pointer to PIR Phase 9. |

## Open Code-Review Overlap

`gh issue list --label code-review --state open` cross-referenced against all 6 PR-1 paths: **None**.

## Files to Create

1. **`knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-report.md`** — probe outputs, audit-log timestamps, verbatim Sentry replies, redacted screenshots, verdict, forward pointer to PIR Phase 9.

2. **`knowledge-base/legal/audits/screenshots/2026-05-19-sentry-token-scope-probe/`** — redacted PNGs (`mint.png`, `revoke.png`, `audit-log.png`).

## Files to Edit

1. **`knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md`**
   - Frontmatter: `status: resolved` → `open`; DELETE `art_33_triggered` line; DELETE `art_33_deadline` line; update `classification_override.chosen` → `superseded-2026-05-19`; prefix `classification_override.reason` value with `"[Superseded 2026-05-19 per Phase 9 Gate-3b correction.] "`; ADD `gate_3_resolution: 3b`; ADD `gate_3_resolution_evidence: knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-report.md`.
   - Body: append `## Phase 9 — Gate 3b Correction (2026-05-19)` section with (a) both verbatim Sentry replies, (b) what original framing got wrong (3 bullets — US shadow org, recipient drift, 49-day phantom window), (c) probable root cause (token-scope mismatch with link to probe report + the workflow-defect learning `2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md`), (d) `Closes #3962` cross-link + supersedes notice for PR-α/PR-γ corpus that PR-2 will retract.

2. **`apps/web-platform/scripts/sentry-monitors-audit.sh`** (L127 + L128 only)
   - Current L127-128: `# token rotated but runtime DSN still points at the old org (the phantom- \n # ingest failure mode #3861 originally documented).`
   - New: `# token rotated but runtime DSN still points at the old org (the destination- \n # controllability split-state failure mode #3861 originally framed as \n # "phantom-ingest" before the 2026-05-19 Gate-3b correction; see PIR Phase 9).`
   - Operational header at L72 ("4-gate destination-controllability check") UNCHANGED.

3. **`knowledge-base/legal/article-30-register.md`** (PA8 §(d) breadcrumb only)
   - Locate the "Recipient-drift after-the-fact disclosure" sentence at L160. Append AT END of the §(d) cell (after the existing "drift-detection gate, not a continuous-controllability guarantee." sentence): `**[2026-05-19 NOTE: Phase 9 of the PIR (linked above) supersedes the "unowned third-party Sentry organization" claim above; Sentry support confirmed 2026-05-19 that org `4511123328466944` is operator-owned. Full retract-in-place lands in PR-2 of the corrective series under #3861.]**`
   - Original prose UNCHANGED — breadcrumb only.

4. **`knowledge-base/legal/compliance-posture.md`** (L89 breadcrumb only)
   - Append AT END of the L89 row's narrative cell: ` **[2026-05-19 NOTE: phantom-ingest framing superseded by PIR Phase 9 Gate-3b correction; org 4511... confirmed operator-owned by Sentry support. PR-2 corpus sweep in flight.]**`

5. **`knowledge-base/legal/audits/2026-05-17-sentry-phantom-ingest-window-auth-users-audit.md`** (frontmatter breadcrumb only)
   - Add new frontmatter key: `superseded_by_note: "2026-05-19 PIR Phase 9 Gate-3b correction — see knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md §Phase 9. Title encodes pre-correction framing; SQL count + categorization remain factually true; PR-2 retracts the 'phantom-ingest' framing while preserving the data."`

## External state changes (not file edits)

- `gh pr ready 4044` — transition draft → ready
- `gh pr edit 4044 --body "<see PR body shape below>"`
- Post-merge: append PR-1 number to issue bodies #3861 and #3849 via `gh issue edit`

PR body shape: Summary (3 sentences) · What changed (5-bullet list mirroring "Files to Create/Edit") · Test plan (mirror AC1–AC11) · `Closes #3962` · `Refs #3861` (do NOT close) · `Refs #3849` (partial-unblock). Brand-survival threshold + triad sign-off lines.

## Implementation Phases

### Phase 0 — Preflight (single checklist, not numbered subtasks)

- Worktree: `git rev-parse --show-toplevel` ends with `.worktrees/feat-sentry-residency-reframe-3861`; `git branch --show-current` = `feat-sentry-residency-reframe-3861`.
- Doppler `prd` token accessible: `doppler secrets get SENTRY_AUTH_TOKEN -p soleur -c prd --plain >/dev/null && echo OK`.
- PIR pre-edit state: `sed -n '7,20p' <pir>` shows `status: resolved`, `art_33_triggered: true`, `art_33_deadline: …`, `classification_override: { advisory: …, chosen: none, reason: … }`. Halt if reality differs.
- Playwright MCP reachable: `mcp__playwright__browser_navigate` callable.
- Sentry UI session: verify operator is logged in as `jean.deruelle@jikigai.com` (NOT a co-owner / invited member). Phase 1.4 below re-asserts at mint screen.

### Phase 1 — Probe (3 steps, with inline halts and retry policy)

Retry policy for all probe `curl` calls: **3 attempts × 30s curl `--max-time` × 5s linear backoff** on HTTP 429/5xx OR connection timeout. After 3 attempts, halt and surface to operator. Treat 4xx other than 401/200/403/404 as non-retriable.

1.1. **Step 1** — prd token vs `jikigai` (expected 401):

```bash
SENTRY_AUTH_TOKEN_PRD=$(doppler secrets get SENTRY_AUTH_TOKEN -p soleur -c prd --plain)
STEP1=$(curl -sS --max-time 30 -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer $SENTRY_AUTH_TOKEN_PRD" \
  https://sentry.io/api/0/organizations/jikigai/)
unset SENTRY_AUTH_TOKEN_PRD
```

1.2. **Step 2** — prd token vs `jikigai-eu` (expected 200 — control):

```bash
STEP2=$(curl ... https://sentry.io/api/0/organizations/jikigai-eu/)
```

1.3. **Step 3** — operator-ack at mint screen, then scope-matched token vs `jikigai`:
- Playwright opens `https://jikigai.sentry.io/settings/account/api/auth-tokens/`.
- Agent halts the workflow and presents the operator a **chat ACK gate** (via AskUserQuestion or equivalent): "READY TO MINT — scope: `org:read` ONLY · org: `jikigai` · label: `probe-2026-05-19-revoke` · lifetime: shortest UI-available bucket (typically 1 day; the binding constraint is same-session revoke ≤ 10 min after mint, NOT the mint lifetime). Type `ACK` to proceed, `ABORT` to cancel." On `ABORT`, agent closes the Playwright tab and exits.
- Operator-driven button click on their own observation of the Sentry UI (or explicitly ACKs a Playwright-driven click — agent surfaces the choice).
- Capture `PROBE_TOKEN_MINTED_AT` from Sentry audit log at `https://jikigai.sentry.io/settings/audit-log/` (poll up to 60s with `browser_wait_for` for the entry to surface).
- Run probe Step 3 curl with the new token; capture `STEP3`.
- Revoke token IMMEDIATELY in the same Playwright session; capture `PROBE_TOKEN_REVOKED_AT` from audit log (poll up to 60s).
- Token VALUE never written to disk, terminal logs, or Playwright form fields beyond the single curl.

1.4. **Conditional halts (load-bearing — TR8):**

| Observation | Verdict | Action |
|---|---|---|
| Step 1 = 401, Step 2 = 200, Step 3 = 200 | Token-scope theory CONFIRMED. Proceed to Phase 2. |
| Step 1 = 200 | Prd token is broader-scoped than runbook claims — security event. Halt; surface as separate incident class; do NOT edit PIR. |
| Step 1 = 403 / 404 | Theory weakened (different signal class). Halt; re-spawn triad with new framing. |
| Step 2 ≠ 200 | Runtime token gone — page operator IMMEDIATELY (prd Sentry is broken). Halt PR-1 entirely. |
| Step 3 ≠ 200 (with scope-matched token) | Token-scope theory DEAD. Halt; re-spawn triad. Sentry replies were directionally right but the workflow defect is elsewhere. |
| ALL three return 200 (Step 1 also 200) | "Success" that invalidates the theory. Most dangerous branch. Halt; write a probe report documenting the negative finding (the original 2026-05-16 401 is now unexplained); re-spawn triad. |
| Audit log shows no mint entry within 60s | Treat as probe-execution failure. Manually revoke via Sentry UI `Personal API Tokens` if token visible; surface to operator. Halt PR-1. |
| Revoke ack'd in UI but no audit-log entry within 60s | R2 escalation — token lives without revoke evidence. Operator manually revokes via UI; commits an incident note in the probe report. |
| Step 3 mint grants broader scope than `org:read` | Revoke IMMEDIATELY. Retry once with explicit scope re-selection. If second mint also broadens, halt; this is a Sentry UI behavior the plan does not reckon with. |

Halt path execution: **no markdown edits.** Surface findings to operator; do not pre-commit reframe narrative.

### Phase 2 — Screenshots + redaction

- Playwright `browser_take_screenshot` for: audit-log page showing mint + revoke entries, token list page showing `probe-2026-05-19-revoke` + post-revoke state.
- **TR9 redaction sweep (per-screenshot):** no token values · no card numbers · no full emails other than `jean.deruelle@jikigai.com` · no Sentry internal IDs other than `4511123328466944` (jikigai) and `4511404939345920` (jikigai-eu) · no CSRF tokens / sudo cookies in URL bars / dev-tool surfaces.
- Redaction tool: ImageMagick (`convert input.png -draw "rectangle x1,y1 x2,y2" -fill black output.png`) is the canonical CLI fallback; opaque-pixel overlays only, not blurs. If a GUI editor (Pencil etc.) is available, that works too.
- Output: `knowledge-base/legal/audits/screenshots/2026-05-19-sentry-token-scope-probe/{mint,revoke,audit-log}.png`.

### Phase 3 — Write probe report + edit PIR + edit script comment + breadcrumbs

3.1. **Write probe report** at `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-report.md`. Frontmatter: `title`, `date`, `parent_issue: 3861`, `gate: 3b`, `probe_run_at`, `probe_token_minted_at`, `probe_token_revoked_at`, `verdict`. Sections: Purpose · Probe sequence · Results table (step / endpoint / token-scope / HTTP status / expected / verdict) · Verbatim Sentry support replies (billing + forensics) · Sentry audit log evidence (timestamps + screenshot links) · Verdict · Forward pointer (PIR §Phase 9 + brainstorm + spec).

3.2. **Edit PIR frontmatter** via `Edit` tool — DELETE the two `art_33_*` lines entirely (not blank); update `classification_override.chosen` value; prefix `classification_override.reason` value; add the two new keys (`gate_3_resolution`, `gate_3_resolution_evidence`).

3.3. **Append PIR Phase 9 section** — see "Files to Edit" §1 contents bullet.

3.4. **YAML parse gate** (TR5 — Kieran P0 fold-in): after Phase 3.2 + 3.3 edits, run:

```bash
python3 -c "import yaml,sys; doc = open('<pir>').read().split('---')[1]; yaml.safe_load(doc); print('PIR YAML OK')"
```

If the parse fails, `git checkout` the PIR file and re-attempt the Edit. Do NOT proceed to Phase 4 with broken frontmatter.

3.5. **Edit audit script** at `apps/web-platform/scripts/sentry-monitors-audit.sh` lines 127-128 (and insert one new line per "Files to Edit" §2). Run `bash -n apps/web-platform/scripts/sentry-monitors-audit.sh` — must return exit 0.

3.6. **Breadcrumbs in 3 cited consumers** (architecture P0 fold-in). One-line dated `[2026-05-19 NOTE: …]` append in each, per "Files to Edit" §§3-5. Original prose UNCHANGED — breadcrumb only.

### Phase 4 — Commit + push + transition draft → ready

- `git add` explicit file list (per `hr-never-git-add-a-in-user-repo-agents`).
- Commit subject: `feat: PR-1 — token-scope probe + PIR Gate-3b reopen + breadcrumbs`. Body cites probe verdict + `Closes #3962` + `Refs #3861` + `Refs #3849` + brand-survival threshold + triad sign-off line.
- `git push`.
- `gh pr edit 4044 --body "<PR body>"` then `gh pr ready 4044`.

### Phase 5 — Review gates

5.1. **`/soleur:gdpr-gate` first (fast-fail)** against PR-1 diff. Treat as genuinely gating — not optimistic. If Critical findings (Art. 9 special-category, missing lawful basis, Art. 30 trigger that PR-1's diff actually introduces), block merge per `compliance-posture.md` auto-write. **The expected outcome IS PASS/LOW (the diff retracts a falsified Art-33 claim — net risk-reducing), but the gate is the canonical check, not the brainstorm CLO sign-off.**

5.2. **`user-impact-reviewer` at PR review** (required per `brand_survival_threshold: single-user incident`). Runs after gdpr-gate gives PASS/LOW. Re-checks brainstorm CPO sign-off against the actual diff.

5.3. (Advisory, optional) `security-sentinel` confirms no token values / PII leaks in screenshots; `data-integrity-guardian` confirms PIR delete-not-blank pattern preserves audit-trail integrity.

### Operator-driven parallel — AC12

Operator replies to Sentry billing thread choosing "transfer credit to `jikigai-eu`" + pastes card-last-4 + expiry directly into the Sentry reply (NOT into agent conversation per `hr-never-paste-secrets-via-bang-prefix`). **Trigger:** anytime after Phase 0. **Migrate criterion:** if Sentry acknowledgment not received by Phase 5 completion, AC12 migrates from Pre-merge to Post-merge.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** Probe results match (`STEP1 == 401 && STEP2 == 200 && STEP3 == 200`) AND `PROBE_TOKEN_REVOKED_AT ≤ PROBE_TOKEN_MINTED_AT + 10 minutes` per Sentry audit log — OR halt-path executed and no PIR edit appears in the diff (verifiable via `gh pr diff 4044 -- knowledge-base/engineering/ops/post-mortems/`).
- [ ] **AC2.** Probe report committed at `…/audits/2026-05-19-sentry-token-scope-probe-report.md` with verbatim HTTP status codes (3 steps), mint + revoke timestamps from Sentry audit log, both verbatim Sentry support replies, redacted screenshot links.
- [ ] **AC3.** PIR YAML parses cleanly: `python3 -c "import yaml; yaml.safe_load(open('…').read().split('---')[1])"` returns exit 0. Frontmatter has `status: open`, no `art_33_triggered` key, no `art_33_deadline` key, `classification_override.chosen: superseded-2026-05-19`, `gate_3_resolution: 3b`, `gate_3_resolution_evidence: <probe-report-path>`.
- [ ] **AC4.** PIR contains `## Phase 9 — Gate 3b Correction (2026-05-19)` heading with both Sentry replies quoted verbatim, the 3-bullet "what original framing got wrong" list, and forward pointers to the probe report + the workflow-defect learning.
- [ ] **AC5.** `apps/web-platform/scripts/sentry-monitors-audit.sh` lines 127-129 contain the refined historical-context comment; line 72 (operational header) UNCHANGED; `bash -n` returns exit 0.
- [ ] **AC6.** Breadcrumbs landed in `article-30-register.md` PA8 §(d) cell, `compliance-posture.md` row 89, and `audits/2026-05-17-sentry-phantom-ingest-window-auth-users-audit.md` frontmatter. Each is a one-line dated `[2026-05-19 NOTE: …]` append; original prose verbatim.
- [ ] **AC7.** PR body contains `Closes #3962` (not in title, per `wg-use-closes-n-in-pr-body-not-title-to`), `Refs #3861`, `Refs #3849`.
- [ ] **AC8.** Screenshots in `…/screenshots/2026-05-19-sentry-token-scope-probe/` redacted per TR9 (no token values, card numbers, non-operator emails, non-public Sentry IDs).
- [ ] **AC9.** `/soleur:gdpr-gate` ran against PR-1 diff with no Critical findings. Critical findings block merge per `compliance-posture.md` auto-write path.
- [ ] **AC10.** PR has approving review from `user-impact-reviewer` (label or comment trail).
- [ ] **AC11.** Draft PR #4044 transitioned to ready via `gh pr ready 4044`.

### Pre-merge (operator-driven, parallel — migrates to Post-merge if not done by Phase 5 completion)

- [ ] **AC12.** Operator replied to Sentry billing thread with "transfer credit to jikigai-eu" + card-last-4 + expiry direct to Sentry. Acknowledgment screenshot attached to PR-1 OR captured for the follow-up.

### Post-merge (operator)

- [ ] **AC13.** #3962 auto-closed via `Closes #3962`. #3861 body updated with PR-1 number + "PR-2 corpus sweep next." #3849 body updated with probe-report link + partial-unblock note.

## Risks

| # | Risk | Mitigation |
|---|------|------------|
| R1 | **Halt-path discipline.** /work proceeds to PIR edit on incomplete/contradictory probe evidence. | TR8 halt table in Phase 1.4 explicitly enumerates 9 branches. `STEP1 == 401 && STEP2 == 200 && STEP3 == 200` must be true BEFORE any markdown edit. AC1 verifies via diff inspection. |
| R2 | **Token revoke race.** Mint UI returns but revoke fails or audit-log entry missing — token lives beyond ≤10-min budget. | Phase 1 escalation row (audit log shows no revoke within 60s) routes to manual UI revoke + incident note in probe report. AC1 cross-checks `MINTED_AT` and `REVOKED_AT` against the 10-min window. |
| R3 | **PIR frontmatter delete-not-blank YAML.** Edit leaves `key:` with empty value, breaks downstream YAML parsers (compliance-posture cron, dashboards). | Phase 3.4 hard parse gate via `python3 yaml.safe_load`. On parse failure, `git checkout` and re-edit. AC3 codifies. |
| R4 | **`/soleur:gdpr-gate` Critical finding.** The diff removes a regulator-facing `art_33_*` assertion; gate may flag the delta regardless of brainstorm CLO sign-off. | AC9 treats gate as genuinely gating. Critical findings block merge + trigger `compliance-posture.md` auto-write. The brainstorm CLO sign-off is plan-time evidence; the gate at /work time is the canonical check. |

## Sharp Edges

- **Probe Step 3 is the load-bearing falsifier.** Token-scope theory only holds if Step 3 returns 200 with scope-matched token. Any other Step 3 outcome dies the narrative — re-spawn triad, do NOT proceed to PIR edit.
- **No broader-scope token mint.** Step 3 scope = `org:read` ONLY. Broader mint widens credential blast radius (TR1/TR2 strict).
- **Same-session revoke is the binding constraint, not the mint lifetime bucket.** Sentry UI offers fixed lifetime buckets (1d/7d/30d/90d/never); arbitrary ≤10min is not selectable. Use the shortest available bucket and revoke within 10 min in the same Playwright session.
- **Audit-trail pattern split: `## Phase 9` heading append for PIR (this PR), dated `[2026-05-19 UPDATE: …]` in-place retract for PA8 §(d) (PR-2).** Different surfaces, different patterns. The breadcrumb in PA8 §(d) here is `[2026-05-19 NOTE: …]` (forward-pointer only — does NOT retract; PR-2's UPDATE will).
- **`classification_override.chosen: superseded-2026-05-19` + reason-prefix.** Striking `chosen: none` while leaving `advisory: aggregate pattern` and `reason: …` creates a stale partial object. Use the prescribed superseded-value + reason-prefix to make the supersession explicit at parse-read time.
- **Operator-ack mechanism: chat-gate before mint button click.** Not a silent auto-mint. Agent halts via AskUserQuestion-style ACK gate with explicit scope/org/label/lifetime; operator types `ACK` or `ABORT`. `ABORT` closes Playwright tab and exits cleanly.
- **Screenshot redaction is non-optional.** ImageMagick CLI fallback is the canonical tool. Opaque-pixel rectangles, NOT blurs.
- **Sentry audit-log entries ARE the §5(2) accountability evidence.** Without timestamps the probe is hearsay-by-curl. 60s poll with `browser_wait_for` before screenshot capture.
- **Do NOT close #3861 in PR-1.** PR-2 closes it. PR-1 only closes #3962 (the Gate-3b T+14d follow-through).
- **Bundled PR scope is fixed.** PA8 §(d) retract-in-place and the auth.users audit reframe stay in PR-2. PR-1 breadcrumbs are forward-pointer only.
- **Phase 9 heading name is intentionally distinct from Gate-3 sub-options.** PIR has Phase 1-8 + Gate 3 with sub-options 3a/3b/3c/3d. "Phase 9 — Gate 3b Correction" reads as a forward-time append; "Gate 3b Resolution" would have buried it inside Phase 8's branch structure.
- **Architecture P0 breadcrumbs are PR-1 scope.** Without them, PIR `status: open` while PA8 §(d) still narrates phantom-ingest as fact creates the inconsistency-window brand-survival surface the single-user threshold is invoked to protect. The breadcrumb is the minimum architectural-consistency fix; the retract-in-place is PR-2's job.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (brainstorm carry-forward — CPO + CLO + CTO triad signed off; full assessments in `knowledge-base/project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md` §Domain Assessments).

**Product/UX Gate:** NONE — PR-1 touches no UI surfaces.

**GDPR Gate (Phase 2.7):** Trigger (b) `single-user incident` fires. Gate runs at /work time per AC9 (treated as genuinely gating, NOT brainstorm-carry-forward optimistic).

**Brainstorm-recommended specialists:** none.

## User-Brand Impact

**If this lands broken, the user experiences:** Regulator / DPA reads the live Article 30 register today and sees an affirmative recipient-drift admission with a named third-party org and Art-33 deadline. PR-1 introduces an inconsistency the architecture P0 breadcrumbs prevent: PIR `status: open` while PA8 §(d) still narrates phantom-ingest as fact between PR-1 and PR-2 merges. Without the breadcrumbs, the live register reads as falsified-truth — the very brand-survival surface the threshold protects.

**If this leaks, exposure vector:** The Step 3 token mint grants Sentry org-level read scope. Leaked or non-revoked probe token exposes `jikigai` org-metadata read access. R2 + TR1/TR2 + Phase 1.4 escalation table bound the budget to ≤10-min, single-use, same-session-revoke.

**Brand-survival threshold:** `single-user incident`. Audience: institutional (regulators, counsel). End-user impact: indirect (brand-credibility).

## Infrastructure (IaC)

Skip — no new infrastructure. Probe uses existing Sentry UI session + existing Doppler token. Audit script is unchanged (one comment line).

## Test Strategy

No code paths in PR-1. Verification = AC1 (probe), AC3 (PIR YAML parse), AC5 (`bash -n`), AC8 (screenshot redaction), AC9 (gdpr-gate), AC10 (user-impact-reviewer). No bun-test / vitest / jest invocations.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-sentry-residency-reframe-3861/spec.md`
- New learnings (already committed in this worktree):
  - `knowledge-base/project/learnings/2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md`
  - `knowledge-base/project/learnings/2026-05-19-sentry-url-routing-three-orthogonal-dimensions.md`
- Falsified-framing PRs: PR-α #3904, PR-β #3945, PR-γ #3946 (all merged 2026-05-17)
- Issues: parent #3861 (do not close), #3962 (Gate-3b T+14d follow-through), #3849 (IaC blocked)
- Draft PR: #4044
- AGENTS.md rules invoked: `hr-weigh-every-decision-against-target-user-impact`, `hr-menu-option-ack-not-prod-write-auth`, `hr-never-paste-secrets-via-bang-prefix`, `hr-gdpr-gate-on-regulated-data-surfaces`, `hr-exhaust-all-automated-options-before`, `wg-use-closes-n-in-pr-body-not-title-to`, `wg-plan-prescribed-skills-must-run-inline`, `hr-never-git-add-a-in-user-repo-agents`.
