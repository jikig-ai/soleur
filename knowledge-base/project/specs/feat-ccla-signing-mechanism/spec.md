---
title: "Corporate CLA signing mechanism"
date: 2026-09-04
type: spec
lane: cross-domain
brand_survival_threshold: single-user incident
closes: [3210]
related: [3211, 7813, 7814, 7816, 7625, 7668, 7670]
brainstorm: knowledge-base/project/brainstorms/2026-09-04-ccla-signing-mechanism-brainstorm.md
branch: feat-ccla-signing-mechanism
pr: 7828
---

# Spec — Corporate CLA signing mechanism

## Problem Statement

`docs/legal/corporate-cla.md` is published and binding, but **no code path records a Corporate CLA**. Recognising a corporate contributor today means hand-editing the `allowlist:` string in `.github/workflows/cla.yml`, which is wrong on three counts: it is a task for a non-technical operator inside a `pull_request_target` workflow; it writes a permanent "maintainer-class bypass" record into a 10-year write-once archive for a contributor who *does* have an IP grant; and a malformed edit blocks every PR in the repo (precedent: #7597).

Two published artifacts already describe a CCLA record that has never existed — `corporate-cla.md` §0 ("two copies are made") and `article-30-register.md` PA-7 §(c) ("For Corporate CLA: signatory name + corporate email + corporate identity"). A real corporate contributor (Convergence) is now at the gate, which converts a latent documentation defect into a live one.

## Goals

- G1. Record a Corporate CLA so that `cla-check` can answer "is this contributor covered by an employer CCLA?" without editing workflow YAML.
- G2. Keep signatory PII off any world-readable surface, and out of the `soleur-cla-evidence` R2 bucket until #7813/#7814/#7816 close.
- G3. Correct the two false disclosures and the ICLA disjunction ambiguity.
- G4. Give the operator a skill-shaped affordance; they never open `cla.yml`.
- G5. Unblock Convergence's `feat-opencode-harness` PR **this week**, with zero code and no allowlist entry.

## Non-Goals

- NG1. A hosted CCLA signing flow at `soleur.ai` — deferred until org count justifies it; the roster becomes its write target, nothing is thrown away.
- NG2. ICLA PII expansion — split to a separate P3 issue with its original re-evaluation criteria.
- NG3. `soleur.ai/account/cla` (#3211) — independent, stays P2/Post-MVP.
- NG4. Forking or replacing `contributor-assistant/github-action`.
- NG5. A third required status check.
- NG6. Writing CCLA records to the R2 evidence bucket (deferred, blocked).
- NG7. Any decision about whether to accept opencode as a third harness.

## Functional Requirements

- **FR1.** A public **coverage map** maps employer legal name → authorized GitHub logins (numeric `id` as the match key, `login` for display) → `signed_at` → CCLA doc `git_sha` + `content_sha256`. Contains no personal data.
- **FR2.** A private **signatory record** holds signatory name, title, corporate email, and the verbatim representation of authority. Enumerated fields only — **no free text, no email body**.
- **FR3.** Representatives are never deleted; removal sets `removed_at`. A merge must be evaluable against the roster as of that merge.
- **FR4.** Roster verification is a **step inside the existing `cla-evidence` job**, reading the roster **only from the base ref**.
- **FR5.** `apps/cla-evidence/roster/` is added to `.github/CODEOWNERS`.
- **FR6.** An operator skill (`soleur:ccla-add` / `cla-record-corporate`) prompts for org, legal name and representative logins; resolves logins → numeric ids via `gh api`; validates against a zod schema; opens a PR touching only the roster. It never opens `cla.yml`.
- **FR7.** The bot's `custom-notsigned-prcomment` and `CONTRIBUTING.md` lead with the ICLA action, state that the CCLA is the maintainer's to chase, and name a turnaround.
- **FR8.** `docs/legal/corporate-cla.md` §0 is amended to describe the register that exists; §5 and `individual-cla.md` §1 + §4(a) gain the both-instruments clarification.
- **FR9.** PA-7 §(c) and §(e) are corrected, and the CCLA field set + the non-adequate-country (Pakistan) outbound leg are reflected in `privacy-policy.md` §4.5/§10, `gdpr-policy.md` §3.4/§6, `data-protection-disclosure.md` §2.3(d)/§6.4.

## Technical Requirements

- **TR1.** Roster at `apps/cla-evidence/roster/ccla-roster.json`; schema at `apps/web-platform/scripts/cla-evidence/roster-schema.ts` (zod, sibling to `schema.ts`), asserting `schema_version` at parse.
- **TR2.** Legal register at `knowledge-base/legal/ccla-register.md`, modelled on `side-letter-register.md` / `tenant-dpa-register.md` (`type: counterparty-ledger`, `custodian: clo`, `schema_version`, `template:`).
- **TR3.** `build-record.ts`'s literal `path: "docs/legal/individual-cla.md"` becomes a discriminant, as do the three hardcoded occurrences in `cla-evidence.yml` (`:55` comment, `:128` hash computation, `:217` receipt body).
- **TR4.** Doc hash captured at countersigning: `git rev-parse HEAD` + `git show <sha>:docs/legal/corporate-cla.md | sha256sum`.
- **TR5.** Every canonical `docs/legal/*.md` edit is paired with its `plugins/soleur/docs/pages/legal/*.md` mirror **and** a `LEGAL_DOC_SHAS` re-pin in the same commit.
- **TR6.** Add a test that runs the allowlist regex against the real `cla.yml`, closing the #7597 gap.
- **TR7.** No change to `cla.yml`'s `allowlist:` value, and no change to its format (the `build-bypass.ts` regex `/^\s*allowlist:\s*["']([^"']+)["']\s*$/m` is a runtime contract).
- **TR8.** Record an ADR — none governs the CLA mechanism.

## Acceptance Criteria

- AC1. A corporate contributor's PR greens `cla-check` via the normal one-comment ICLA path, with no allowlist entry and no second check.
- AC2. `git grep -n 'allowlist' .github/workflows/cla.yml` shows the value unchanged from `main`.
- AC3. The coverage map contains no personal data; the signatory record is not on a world-readable surface.
- AC4. A roster edit on a PR head ref does not affect that PR's own verification.
- AC5. No CCLA record is written to `soleur-cla-evidence` while #7813, #7814 or #7816 is open.
- AC6. `docs/legal/corporate-cla.md` §0 no longer asserts a record that is not written, and the canonical/mirror SHA gate passes.
- AC7. The operator adds a corporate contributor end-to-end without opening a `.yml` file.

## Sequencing

**Tier 0 — this week, hours, no mechanism.** Reply to Convergence requesting a named signatory (not the role mailbox) with the §Signing fields; ship the FR7 copy fix; their contributor comments the ICLA line as normal and the PR merges on its merits; countersign and hand-record the CCLA. One manual record is fine — two is a pattern.

**Tier 1 — the mechanism.** FR1–FR6, TR1–TR3, TR6, TR8.

**Tier 2 — corpus corrections.** FR8, FR9, TR5. Route the cross-document sweep through `legal-compliance-auditor`.

**Carried, not dropped — roadmap row 4.13.** The CPO's recommended row is:

> `| 4.13 | Corporate CLA recording mechanism (public coverage map + private signatory record + operator affordance; no allowlist widening) | P1 | First corporate contributor at the gate (2026-09-04); Art. 30 PA-7 and corporate-cla.md §0 already declare processing that has no machinery | #3210 |`

It is **not** in this PR: `knowledge-base/product/roadmap.md` fails `markdown-lint` on `main` with 5 pre-existing errors, and the hook lints staged files, so any commit touching it is blocked. Tracked at **#7832**, which also records that `markdownlint-cli2 --fix` damages line 74 (it deletes a real space, producing `All-in burn**$643.24/mo**`). Add the row in the same change that fixes #7832. Note `wg-every-feature-listed-in-a-roadmap-phase` runs the other way — it requires roadmap rows to carry linked issues, which this row does — so nothing is out of compliance in the interim.

**Blocked / referred.** R2 write (on #7813 + #7814 + #7816); Pakistani employment-law question, Art. 49-vs-SCCs, CCLA §3 moral rights, and #7668 extended to the CCLA population — all to outside French counsel.
