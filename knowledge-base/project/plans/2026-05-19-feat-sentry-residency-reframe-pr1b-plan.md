---
title: "Sentry residency reframe — PR-1b: probe report v2 + PIR Phase 9 narrative + audit-script comment refinement + remaining-consumer breadcrumbs"
date: 2026-05-19
type: feat
parent_issue: 3861
closes_issues: [3962]
references_issues: [3861, 3849]
brand_survival_threshold: single-user incident
lane: cross-domain
triad: [CPO, CLO, CTO]
requires_cpo_signoff: true
supersedes: knowledge-base/project/plans/2026-05-19-feat-sentry-residency-reframe-pr1-plan.md
brainstorm: knowledge-base/project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md
spec: knowledge-base/project/specs/feat-sentry-residency-reframe-3861/spec.md
divergence_note: knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md
follows_pr: 4044
---

## Overview

PR-1b of a three-PR corrective series under #3861 (the original plan's two-PR
shape was re-split into three after the T3-triad-respawn). PR-1a (the
emergency interim breadcrumb, draft PR #4044 → ready → auto-merge) shipped
two surfaces: Article 30 PA8 §(d) re-falsification-immune breadcrumb + PIR
frontmatter strike (`status: open`, `art_33_triggered → "superseded-pending-
Phase-9"`, `art_33_deadline → "superseded-…"`). It made NO causal claim. This
PR-1b ships the now-load-bearing causal claim — backed by the T3 verification
appendix in the divergence note, the runtime token's identity is now
empirically known and the PIR Phase 9 narrative can be authored with §5(2)
precision.

**Supersedes** `2026-05-19-feat-sentry-residency-reframe-pr1-plan.md` — the
original plan's causal theory (T1 "token-scope mismatch") was falsified
during its own Phase 1 probe and replaced by the refined T3 ("Internal
Integration auth token, proxy-user identity with `jikigai-eu`-only
membership"). The original plan remains in git history for provenance.

**PR-2 remains OUT OF SCOPE here.** PR-2 (Article 30 PA8 §(d) retract-in-
place, Vendor DPAs row revision, ADR-031, learnings sweep, three-dimensional
URL/cluster/identity model) follows PR-1b.

## Research Reconciliation — what changed vs. the original plan

| Original-plan assumption | Reality (post-T3 probe 2026-05-19T13:28:41Z) | PR-1b response |
|---|---|---|
| Phase 1 probe: `STEP1 == 401 && STEP2 == 200 && STEP3 == 200` confirms theory | STEP1=403 (not 401); T1 imprecise (scope-flags aren't per-slug); T2 falsified (jikigai-eu has zero Org Auth Tokens); T3 confirmed via single read-only `/api/0/` call | Probe is no longer a Phase-1-of-implementation gate — it ran, result is in the divergence note's Appendix A. PR-1b authors the probe-report-v2 from that evidence. |
| Mint a fresh `org:read` Personal Token via Playwright with ACK gate | Already done in PR-1a's halt-flow; token revoked within 2m43s; bytes redacted from divergence note via history rewrite | No new mint in PR-1b. Probe report v2 cites the existing evidence chain. |
| Audit-log timestamps from `https://jikigai.sentry.io/settings/audit-log/` | Personal Token mint/revoke do NOT appear in Organization Audit Log (Sentry surface finding) | Substitute evidence chain: local UTC + post-revoke HTTP 401 verify + UI absence. AC2 + AC8 rewording reflects this. |
| Audit script L127-128 reframe: "destination-controllability split-state failure mode #3861 originally framed as 'phantom-ingest' before the 2026-05-19 Gate-3b correction" | Operational header at L72 unchanged; L127-128 is historical comment | CTO recommendation: keep "destination-controllability" as the L127 abstraction level. The precise mechanism (Internal Integration proxy-user) belongs in PIR Phase 9 prose, not in the script comment. The audit script is a runtime defense gate, not a forensic narrative. |
| Three breadcrumbs in cited consumers (PA8 §(d), compliance-posture row 89, 2026-05-17 audit) | PA8 §(d) landed in PR-1a; compliance-posture row 89 and 2026-05-17 audit deferred to PR-1b per CLO's tight bound at triad-respawn | PR-1b ships the remaining two breadcrumbs. |

## Open Code-Review Overlap

`gh issue list --label code-review --state open` cross-referenced against all
PR-1b paths: **None at plan-authoring time.** Verify at /work start.

## Files to Create

1. **`knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-report.md`** — the canonical probe report. Derivative of the divergence note's Appendix A. Frontmatter: `title`, `date`, `parent_issue: 3861`, `gate: 3b`, `probe_run_at`, `probe_token_minted_at_utc`, `probe_token_revoked_at_utc`, `verdict`, `supersedes_divergence_note: false` (the divergence note remains canonical as halt-evidence; the probe report is the clean derivative for external readers). Sections: Purpose · Probe sequence (STEP1/2/3 + T3 verification) · Results table · Verbatim Sentry support replies · Sentry audit log evidence (operator-local UTC + post-revoke HTTP 401 verify + UI absence) · Verdict · Forward pointer (PIR §Phase 9). ≤ 6KB.

## Files to Edit

1. **`knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md`** — append `## Phase 9 — Gate 3b Correction (2026-05-19)` section after the existing Phase 8 content. Contents:
   - (a) Both verbatim Sentry replies (billing + Rodolfo, reproduced from the brainstorm).
   - (b) Three bullets — what the original framing got wrong: (i) named third-party org claim; (ii) recipient drift claim; (iii) 49-day phantom-ingest window framing.
   - (c) Probable root cause, **post-T3 sharpened to:** "Internal Integration auth token. The runtime `SENTRY_AUTH_TOKEN` issued by the `web-platform-ci` Internal Integration installed on `jikigai-eu` post-2026-05-17 cutover. The token authenticates as a Sentry-generated proxy-user (`web-platform-ci-…@proxy-user.sentry.io`, user ID `4569715`, `dateJoined: 2026-05-17T11:25:11Z`) which is a member of `jikigai-eu` only. The 403 against `jikigai/` is a clean organization-membership-boundary failure for that proxy-user identity — not a scope-flag mismatch (the token carries `org:read`), not an Org Auth Token slug-binding (`jikigai-eu` has zero Org Auth Tokens)."
   - (d) `Closes #3962` cross-link + supersedes notice for PR-α/PR-γ corpus that PR-2 will retract.
   - (e) Wider-than-expected scope finding: the runtime token's `auth.scopes` includes `project:write` + `project:releases` on `jikigai-eu`. Write-capable, not read-only.
   - **Frontmatter additions (in same edit):** `gate_3_resolution: 3b`, `gate_3_resolution_evidence: knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-report.md`. (The `correction_pending: true` + `correction_evidence: …divergence-note` fields landed in PR-1a; leave them or update `correction_evidence` to point at the probe report path. CLO call — recommend keeping divergence-note path as the load-bearing evidence pointer; the probe report is a derivative.) Optionally also update `classification_override.chosen` from `none` to `superseded-2026-05-19` and prefix the `classification_override.reason` value with `"[Superseded 2026-05-19 per Phase 9 Gate-3b correction.] "` (the original plan's frontmatter delta; carry forward).

2. **`apps/web-platform/scripts/sentry-monitors-audit.sh` (L127-128 only)** — refine the historical comment per the original plan (unchanged from PR-1's prescription, since CTO confirmed at triad-respawn that the precise mechanism belongs in PIR Phase 9, not in the script comment):
   - **Current L127-128:** `# token rotated but runtime DSN still points at the old org (the phantom- \n # ingest failure mode #3861 originally documented).`
   - **New:** `# token rotated but runtime DSN still points at the old org (the destination- \n # controllability split-state failure mode #3861 originally framed as \n # "phantom-ingest" before the 2026-05-19 Gate-3b correction; see PIR Phase 9).`
   - Operational header at L72 ("4-gate destination-controllability check") UNCHANGED.
   - `bash -n` exit 0.

3. **`knowledge-base/legal/compliance-posture.md`** (row 89 breadcrumb) — append AT END of the L89 row's narrative cell:
   `**[2026-05-19 NOTE: phantom-ingest framing superseded by PIR Phase 9 Gate-3b correction (see knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md §Phase 9). Org 4511… confirmed operator-owned by Sentry support 2026-05-19. PR-2 corpus sweep in flight under #3861.]**`
   - Original prose UNCHANGED — breadcrumb only.

4. **`knowledge-base/legal/audits/2026-05-17-sentry-phantom-ingest-window-auth-users-audit.md`** (frontmatter breadcrumb only) — add new frontmatter key:
   `superseded_by_note: "2026-05-19 PIR Phase 9 Gate-3b correction — see knowledge-base/engineering/ops/post-mortems/sentry-phantom-ingest-destination-unreachable-postmortem.md §Phase 9 and knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-report.md. Title encodes pre-correction framing; SQL count + categorization remain factually true; PR-2 retracts the 'phantom-ingest' framing while preserving the data."`

## External state changes (not file edits)

- New draft PR (PR-1b): `gh pr create --base main --head feat-sentry-residency-reframe-3861-pr1b --draft …`.
- Rebase: after PR-1a merges, rebase `feat-sentry-residency-reframe-3861-pr1b` onto updated `main` so the PR-1a content is in shared history (not duplicated).
- `gh pr ready <PR-1b-number>` after gates.
- Post-merge: `gh issue close 3962 --comment "<PR-1b-URL> — Gate-3b resolution evidence: …/audits/2026-05-19-sentry-token-scope-probe-report.md"`; append PR-1b number to issue bodies #3861 (parent stays open) and #3849 (partial-unblock note + path-(b)-recommendation reference for the IaC token-mint decision).

## Implementation Phases

### Phase 0 — Preflight

- Worktree: `git rev-parse --show-toplevel` ends with `.worktrees/feat-sentry-residency-reframe-3861-pr1b`.
- Branch: `feat-sentry-residency-reframe-3861-pr1b` (must be branched off `feat-sentry-residency-reframe-3861` OR rebased onto post-PR-1a `main` before merge).
- PIR pre-edit state: frontmatter currently has `status: open`, `art_33_triggered: "superseded-pending-Phase-9"`, `art_33_deadline: "superseded-2026-05-19T12:50:00Z"`, `correction_pending: true`, `correction_evidence: knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md` (from PR-1a). Halt if reality differs.

### Phase 1 — Probe report v2

Author `…/audits/2026-05-19-sentry-token-scope-probe-report.md`. Derivative of the divergence note's Appendix A. The probe was already run during PR-1a's halt flow — Phase 1 of PR-1b is documentation, not execution.

### Phase 2 — PIR Phase 9 narrative

Append the `## Phase 9 — Gate 3b Correction (2026-05-19)` section per "Files to Edit" §1 above. Update PIR frontmatter (`gate_3_resolution: 3b`, `gate_3_resolution_evidence: …`; optionally `classification_override.*`).

### Phase 3 — Audit script comment + remaining breadcrumbs

3.1. Edit `apps/web-platform/scripts/sentry-monitors-audit.sh` L127-128 per "Files to Edit" §2. Run `bash -n` — must return exit 0.

3.2. Add the L89 breadcrumb to `knowledge-base/legal/compliance-posture.md` per "Files to Edit" §3.

3.3. Add the `superseded_by_note` frontmatter key to `…/audits/2026-05-17-sentry-phantom-ingest-window-auth-users-audit.md` per "Files to Edit" §4. Run a YAML parse to confirm valid frontmatter post-edit.

### Phase 4 — Commit + push + transition draft → ready

- `git add` explicit file list. Conventional commit message subject: `feat: PR-1b — probe report v2 + PIR Phase 9 + audit-script L127 + remaining breadcrumbs`. Body cites probe verdict + `Closes #3962` (PR body, not title) + `Refs #3861` (do NOT close) + `Refs #3849` (partial-unblock + path-(b) recommendation) + brand-survival threshold + triad sign-off line + `Co-Authored-By: …`.
- `git push`. `gh pr create` (or `gh pr edit <num> --body …` + `gh pr ready <num>` if PR already exists).

### Phase 5 — Review gates

5.1. **`/soleur:gdpr-gate` against PR-1b diff.** Expected PASS (no code-layer surfaces touched; the canonical regex won't fire — gate skips silently). The probe-report file at `…/audits/…probe-report.md` is document-layer, same class as PR-1a's surfaces. AC9 (carry-forward).

5.2. **`user-impact-reviewer` at PR review** (required per `brand_survival_threshold: single-user incident`). Re-checks brainstorm + divergence-note CPO sign-off against the actual PR-1b diff. AC10 (carry-forward).

5.3. (Advisory, optional) `security-sentinel` scans the probe report for token-value or PII residue. The divergence note's R2-class incident is documented; the probe report v2 should NOT repeat the verbatim leaked-token bytes — only reference them by the redacted form `sntryu_<REDACTED-...; revoked 2026-05-19T10:45:03Z; verified dead via HTTP 401 post-revoke>`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1.** Probe report v2 committed at `…/audits/2026-05-19-sentry-token-scope-probe-report.md`. References the divergence note's Appendix A for the T3 evidence chain. NO verbatim leaked-token bytes; uses the redacted form only.
- [ ] **AC2.** PIR Phase 9 section appended with (a) both verbatim Sentry replies, (b) 3-bullet original-framing-wrong list, (c) sharpened root cause: "Internal Integration auth token, proxy-user identity scoped to `jikigai-eu`-only membership," (d) `Closes #3962` cross-link, (e) wider-than-expected scope finding.
- [ ] **AC3.** PIR YAML parses cleanly post-edit: `python3 -c "import yaml; yaml.safe_load(open('…').read().split('---',2)[1])"` returns exit 0. Frontmatter has `status: open`, `gate_3_resolution: 3b`, `gate_3_resolution_evidence: <probe-report-path>`, no `art_33_triggered: true` (carried over from PR-1a's `superseded-pending-Phase-9` form), no `art_33_deadline` as a live deadline (carried over as `superseded-…`).
- [ ] **AC4.** `apps/web-platform/scripts/sentry-monitors-audit.sh` lines 127-129 contain the refined historical-context comment; line 72 (operational header) UNCHANGED; `bash -n` returns exit 0.
- [ ] **AC5.** Breadcrumb landed in `knowledge-base/legal/compliance-posture.md` row 89. One-line dated `[2026-05-19 NOTE: …]` append; original prose verbatim.
- [ ] **AC6.** `superseded_by_note` frontmatter key landed in `…/audits/2026-05-17-sentry-phantom-ingest-window-auth-users-audit.md`. YAML parse exit 0.
- [ ] **AC7.** PR body contains `Closes #3962` (not in title, per `wg-use-closes-n-in-pr-body-not-title-to`), `Refs #3861`, `Refs #3849`.
- [ ] **AC8.** `/soleur:gdpr-gate` ran against PR-1b diff. Expected: skip silently (no code-layer surfaces; canonical regex does not fire) — that satisfies AC8 by being the documented PASS shape for document-layer-only diffs. Critical findings block merge per `compliance-posture.md` auto-write path (none expected).
- [ ] **AC9.** PR has approving review from `user-impact-reviewer` (label or comment trail).
- [ ] **AC10.** Draft PR-1b transitioned to ready via `gh pr ready <num>`.

### Post-merge (operator)

- [ ] **AC11.** `#3962` auto-closed via `Closes #3962` in PR-1b body. `#3861` body updated with PR-1b number + "PR-2 corpus sweep next under same parent issue." `#3849` body updated with probe-report link + path-(b) recommendation note for the IaC token-mint decision (operator picks (a) widen existing Internal Integration vs (b) new least-privilege `iac-terraform-prd` Internal Integration vs (c) Org Auth Token — see divergence note Appendix A §"How this changes the revised plan's shape" item 4).

## Risks

| # | Risk | Mitigation |
|---|------|------------|
| R1 | **Re-falsification of T3.** The /api/0/ probe established the runtime token's identity at one point in time. If the token were rotated in-place during PR-1b authoring (operator manually edits Doppler or a CI workflow auto-rotates), the runtime token's identity could change and the PIR Phase 9 claim could become stale. | Probe report v2 captures the T3 probe's UTC (`2026-05-19T13:28:41Z`) as load-bearing. If the operator rotates between then and PR-1b merge, re-run the probe. Frontmatter pointer to probe report v2 anchors the claim to that snapshot. |
| R2 | **PIR Phase 9 narrative repeats the redacted-bytes pattern wrong.** The probe report must NOT include the verbatim leaked-token bytes (those exist only in operator-local Playwright YAML files post-PR-1a's history rewrite). | Phase 1 of PR-1b explicitly uses the redacted form. AC1 enforces. Security-sentinel optional scan at Phase 5.3. |
| R3 | **`gdpr-gate` falsely activates** on the probe report path if the canonical regex were tightened. | The current canonical regex covers code-layer paths only (`apps/web-platform/...`, `*.sql`). The probe report at `knowledge-base/legal/audits/…` is document-layer — `legal-compliance-auditor` is the correct skill for that class. AC8 documents skip-silently as PASS. |
| R4 | **`#3849` IaC-token decision blocks** PR-1b unintentionally. | PR-1b ships only the partial-unblock note in `#3849` body. The actual token-mint operator action is OUT OF SCOPE for PR-1b — it belongs to a separate workstream the operator initiates. |

## Sharp Edges

- **Phase 1 is documentation, not execution.** The probe already ran during PR-1a's halt flow; the probe report v2 is derivative. Do NOT re-run the probe under PR-1b's Phase 1.
- **The divergence note's Appendix A is canonical for T3.** The probe report v2 references it; do not duplicate the full Appendix A content in the probe report (single source of truth principle).
- **Operational header at audit-script L72 is UNCHANGED.** Only L127-128 historical-context comment changes.
- **Compliance-posture row 89 breadcrumb is forward-pointer-only.** PR-2's retract-in-place lives on a separate PR; PR-1b adds the breadcrumb without touching the original row prose.
- **Wider-than-expected runtime token scope finding** belongs in PIR Phase 9 prose (the `project:write` + `project:releases` capability). Do NOT add it to the audit script comment, the compliance-posture breadcrumb, or the 2026-05-17 audit frontmatter — those are forward-pointer surfaces only.
- **Token-leak R2-class incident** is documented in the divergence note (already on PR-1a's branch, now on main post-merge). The probe report v2 must NOT repeat the verbatim leaked bytes; it references the redacted form.
- **Brand-survival threshold for PR-1b is unchanged from PR-1a:** `single-user incident`. user-impact-reviewer required at PR review. CPO sign-off carry-forward.
- **#3849 IaC token-mint is OUT OF SCOPE for PR-1b.** PR-1b body's `Refs #3849` is a partial-unblock note + the path-(b) recommendation pointer, not a closure or implementation.
- **Phase 9 heading name is intentionally distinct from Gate-3 sub-options** (Phase 1-8 + Gate 3 with sub-options 3a/3b/3c/3d). "Phase 9 — Gate 3b Correction" reads as forward-time append; "Gate 3b Resolution" would have buried it inside Phase 8's branch structure.

## Domain Review

**Domains relevant:** Engineering, Legal, Product (brainstorm + divergence-note carry-forward — CPO + CLO + CTO triad signed off; full re-spawn assessment captured in conversation transcript and in the divergence note's Appendix A "How this changes the revised plan's shape").

**Product/UX Gate:** NONE — PR-1b touches no UI surfaces.

**GDPR Gate (Phase 2.7 of /soleur:plan):** Trigger (b) `single-user incident` fires. Gate is expected to skip silently at /work time (document-layer-only diff). AC8 codifies the skip-silently-as-PASS shape.

**Brainstorm-recommended specialists:** none.

## User-Brand Impact

**If this lands broken, the user experiences:** Regulator / DPA reads the live disclosure register after PR-1a merged and sees the PIR `status: open` + `correction_pending: true` + breadcrumb on PA8 §(d), but NO causal explanation of the original 401/403 anywhere on the public surface. The §5(2) accountability standard is "be able to demonstrate compliance" — PR-1a satisfied the half about "stop making the false affirmative claim"; PR-1b is the half about "explain the correct mechanism." Without PR-1b, the corpus reads as "we know it was wrong but we won't say why" — which on its own is a credibility regression vs. the pre-PR-1a state (which at least had a complete-if-wrong narrative).

**If this leaks, exposure vector:** The probe report v2 references the redacted-form token bytes only. No new leak surface introduced. The wider-than-expected scope finding (`project:write` + `project:releases` on `jikigai-eu`) is itself a documented operational fact, not a leak — the runtime token's capability is a configuration question, not a credential disclosure.

**Brand-survival threshold:** `single-user incident`. Audience: institutional (regulators, counsel). End-user impact: indirect (brand-credibility).

## Infrastructure (IaC)

Skip — no new infrastructure. PR-1b uses existing files only. The wider-than-expected scope finding informs `#3849`'s separate workstream but does not introduce new infra in PR-1b itself.

## Test Strategy

No code paths in PR-1b. Verification = AC1 (probe report), AC3 (PIR YAML parse), AC4 (`bash -n`), AC6 (audit frontmatter YAML parse), AC8 (gdpr-gate skip-silently), AC9 (user-impact-reviewer). No bun-test / vitest / jest invocations.

## References

- Brainstorm: `knowledge-base/project/brainstorms/2026-05-19-sentry-residency-reframe-3861-brainstorm.md`
- Spec: `knowledge-base/project/specs/feat-sentry-residency-reframe-3861/spec.md`
- Supersedes plan: `knowledge-base/project/plans/2026-05-19-feat-sentry-residency-reframe-pr1-plan.md`
- Divergence note (canonical input + Appendix A T3 evidence): `knowledge-base/legal/audits/2026-05-19-sentry-token-scope-probe-divergence.md`
- New learning shipped on a separate branch (independent of residency-reframe): `knowledge-base/project/learnings/2026-05-19-playwright-snapshot-leaks-vendor-token-display-elements.md` (PR #4064).
- Pre-existing learnings carrying forward: `knowledge-base/project/learnings/2026-05-19-sentry-401-is-not-unowned-verify-token-scope-first.md`, `knowledge-base/project/learnings/2026-05-19-sentry-url-routing-three-orthogonal-dimensions.md`. (The first now has an inline gitleaks-allow waiver landed in PR-1a's lint-fix commit.)
- Falsified-framing PRs (to be retracted in PR-2): PR-α #3904, PR-β #3945, PR-γ #3946 (all merged 2026-05-17).
- Issues: parent #3861 (do not close), #3962 (Gate-3b T+14d follow-through; resolves with PR-1b's `Closes #3962`), #3849 (Sentry IaC AC13-AC16 blocked; partial-unblock in PR-1b body, full unblock requires the separate IaC token-mint workstream).
- Draft PR (PR-1a, predecessor): #4044 (merged or merging).
- AGENTS.md rules invoked: `hr-weigh-every-decision-against-target-user-impact`, `hr-gdpr-gate-on-regulated-data-surfaces`, `wg-use-closes-n-in-pr-body-not-title-to`, `wg-plan-prescribed-skills-must-run-inline`, `hr-never-git-add-a-in-user-repo-agents`.
