---
feature: feat-one-shot-aup-tos-autonomous-cmd-disclosure
issue: 4952
ref: 4949
lane: cross-domain
plan: knowledge-base/project/plans/2026-06-04-feat-aup-tos-autonomous-command-disclosure-plan.md
---

# Tasks — AUP + ToS autonomous command execution disclosure

Derived from the plan. Phase order is load-bearing: canonical → mirrors → SHAs LAST.

## Phase 0 — Preconditions (verify, no code)

- [ ] 0.1 `cd` into the worktree before any git command (bare-root exits 128).
- [ ] 0.2 Re-confirm current SHAs match pinned literals (AUP `d979595e…`, T&C `e87c8b45…`);
      if drifted, an unrelated edit landed — re-check the "edit trips guard" assumption.
- [ ] 0.3 Read `knowledge-base/legal/tc-version-bump-policy.md` §Tier 1 + §semver-for-legal-docs;
      lock `TC_VERSION 2.2.1 → 2.3.0`.
- [ ] 0.4 Read `AUTONOMOUS_DISCLOSURE_COPY` (autonomous-disclosure-banner.tsx:21-27) and
      `BLOCKED_BASH_PATTERNS` (permission-callback.ts:84) for prose consistency.

## Phase 1 — AUP canonical disclosure

- [ ] 1.1 Add AUP §5.7 "Autonomous command execution (Web Platform)" per Drafting Bar
      (residual-risk admission + git-backed + visible-in-chat + trust-only responsibility +
      cross-ref T&C §3a.7 / §10.4 + banner).
- [ ] 1.2 Add §2 (Scope) clause noting autonomous command execution is in scope.
- [ ] 1.3 Update AUP `**Last Updated:**` prose line (prepend June 4, 2026 entry) + YAML
      `last-updated: 2026-06-04`.

## Phase 2 — T&C canonical disclosure

- [ ] 2.1 Add T&C §3a.7 (consent model, soft-gate ack, autonomous/trusted toggle, residual-
      risk admission, own-workspace-vs-third-party Art. 22 distinction).
- [ ] 2.2 Add T&C §10.4 "Autonomous command execution — residual risk" (new disclaimer text
      = Tier-1 material; blocklist not exhaustive, no warranty against harmful auto-run,
      mitigations named).
- [ ] 2.3 Add §9 (Acceptable Use) sibling bullet cross-referencing §3a.7 / AUP §5.7.
- [ ] 2.4 Update T&C `**Last Updated:**` prose line + YAML date.

## Phase 3 — Eleventy mirrors (3-way lockstep, same PR)

- [ ] 3.1 Mirror §5.7 + §2 clause into `plugins/soleur/docs/pages/legal/acceptable-use-policy.md`
      (heading + body identical).
- [ ] 3.2 Update AUP mirror hero `<p>` date AND body `**Last Updated:**` date.
- [ ] 3.3 Mirror §3a.7 + §10.4 + §9 clause into
      `plugins/soleur/docs/pages/legal/terms-and-conditions.md` (heading + body identical,
      for body-equivalence step).
- [ ] 3.4 Update T&C mirror hero `<p>` date AND body `**Last Updated:**` date.

## Phase 4 — Version guards (LAST — after final canonical bytes)

- [ ] 4.1 `sha256sum docs/legal/acceptable-use-policy.md` → `LEGAL_DOC_SHAS["acceptable-use-policy"]`.
- [ ] 4.2 `sha256sum docs/legal/terms-and-conditions.md` → `TC_DOCUMENT_SHA`.
- [ ] 4.3 Bump `TC_VERSION` `2.2.1 → 2.3.0`; update `TC_BUMP_METADATA`
      (`lastUpdated: "June 4, 2026"`, `substantiveChange: "§Autonomous command execution
      residual-risk disclosure"`).

## Phase 5 — Compliance register

- [ ] 5.1 Run gdpr-gate (Phase 2.7) on the disclosure; record Art. 30 disposition (default:
      no new PA — existing PA 21/22; else PA 27).
- [ ] 5.2 Add `compliance-posture.md` Completed Compliance Work entry.

## Phase 6 — Verify (full-suite exit gate)

- [ ] 6.1 Run `scripts/test-all.sh` (NOT touched-file-only); exit 0.
- [ ] 6.2 Confirm green: `legal-doc-consistency.test.ts`, `legal-doc-shas-guard.test.ts`,
      `tc-version.test.ts`, `accept-terms-copy-regression.test.tsx`.
- [ ] 6.3 Negative control (sanity): editing canonical T&C without the bump fails
      `check-tc-document-sha.sh`; a mirror-only sentinel fails body-equivalence.

## Phase 7 — Sign-off + ship

- [ ] 7.1 CPO sign-off recorded (single-user-incident threshold).
- [ ] 7.2 CLO sign-off recorded (Tier-1 material T&C change).
- [ ] 7.3 PR body: `Closes #4952`, `Ref #4949`; title
      `legal(tc): TC_VERSION → 2.3.0 — disclose autonomous command execution + residual risk`.
