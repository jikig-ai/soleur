---
title: "chore(legal): AUP §2 scope names the Playwright MCP alongside agent-browser"
type: chore
date: 2026-09-15
slug: chore-aup-scope-names-playwright-mcp
branch: feat-one-shot-7981-aup-scope-playwright-mcp
issue: 7981
closes: 7981
pr: 8207
priority: p2-medium
domain: legal
brand_survival_threshold: none
lane: cross-domain
---

# AUP §2 scope: name both browser-automation surfaces

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed). (No `spec.md` exists for this branch.)

## Enhancement Summary

**Deepened on:** 2026-09-15
**Sections enhanced:** 4 (Implementation, Acceptance Criteria, Risks & Sharp Edges, Research Insights)
**Agents used:** clo (planning ruling), learnings-researcher, functional-discovery, dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer (plan-review), legal-compliance-auditor (deepen cross-document audit). The skill's "run every agent" fan-out was deliberately scoped to these for a one-bullet notice-document edit (operator: keep it small); every mechanical deepen gate below ran in full.

### Key Improvements

1. Plan-review cut six non-load-bearing ACs and the Test Scenarios section, fixed an AC that could never fail (PR-token grep), moved every diff check to `origin/main...HEAD`, scoped the addendum check so the pre-existing A4 "DISCHARGED, unchanged" cannot satisfy it, and added `probe-legal-corpus-truth.sh` plus the three lint unit arms to the gate set.
2. Last Updated annotation reworded "adds" → "now names" (auditor: "adds" reads as a new capability; the change is a Tier 2 clarification).
3. Single-sourced the `TC_VERSION` reasoning (Domain Review in the plan; tier line in the PR body only).

### New Considerations Discovered

- `apps/web-platform/server/agent-runner.ts` reads the plugin manifest's `mcpServers`, so if #8156 makes the plugin register Playwright, the hosted runner would inherit it — the neutral "a … server driven by Soleur agents or skills" wording stays true either way.
- Auditor suggestions considered and declined (see Risks & Sharp Edges).

## Overview

The Acceptable Use Policy's Section 2 scope list names browser automation through the
agent-browser subsystem only. Soleur's skills also drive a Playwright MCP server. This plan
widens that one scope bullet in the canonical document and its Eleventy mirror together,
refreshes the raw-file SHA pin, dates the change, discharges the one CLO re-evaluation trigger
this landing fires, and records the `TC_VERSION` verdict: **not engaged** (reasoning: Domain Review).

This is under-inclusion, not misstatement: the §2 list is introduced by "including but not
limited to", and §4 already prohibits misuse of "browser automation capabilities" generically.

## Research Reconciliation — Brief vs. Codebase

| Brief / issue claim | Reality (verified) | Plan response |
|---|---|---|
| "the plugin also drives the Playwright MCP" | The plugin's skills drive it (`mcp__playwright__*` in 5 files under `plugins/soleur/skills/`), but `plugins/soleur/.claude-plugin/plugin.json` registers **no** Playwright server; only this repo's `.mcp.json` does. The hosted agent-runner registers none. #8156 (OPEN) may make the plugin register one by default. | Bullet names "**a** Playwright MCP server driven by Soleur agents or skills" — true before and after #8156, silent on who registers it, no Web Platform claim. |
| TC_VERSION "not engaged, because no clause changes" | A clause does change (a scope bullet); the verdict holds for a structural reason instead. | Verdict not engaged — see Domain Review (single place in this plan) and the PR-body tier line. |
| "refresh the raw-file SHA pin" | `LEGAL_DOC_SHAS["acceptable-use-policy"]` is drift-only (read only by `check-tc-document-sha.sh`); the SHA covers raw bytes **including frontmatter**. | Pin computed after every canonical byte is final. |
| (not in brief) | The #7980 CLO attestation lists "#7981 lands or is closed without landing" under `re_evaluation_triggers`. | Append a short dated addendum discharging it. |

## Files to Edit

1. `docs/legal/acceptable-use-policy.md` — §2 bullet; frontmatter `last-updated:`; prepend `**Last Updated:**` entry.
2. `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` — same bullet; hero `<p>` date; prepend body `**Last Updated:**` entry.
3. `apps/web-platform/lib/legal/legal-doc-shas.ts` — `"acceptable-use-policy"` value only.
4. `knowledge-base/legal/compliance-posture.md` — Legal Documents table row `Acceptable Use Policy` Last-Updated cell; frontmatter `last_updated:`. No HTML-comment changelog entry, no other row.
5. `knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md` — append-only addendum at end of file.

Items 1–3 land in one commit (AUP is in `BODY_EQUIVALENCE_DOCS`; the required check is red between them).

## Files to Create

None.

## Implementation

`WORK_DATE` = UTC date at /work time (`date -u +%F`; expected `2026-09-15`). Long form, e.g. `September 15, 2026`.

### Phase 1 — Canonical + mirror + pin (one commit)

1. In both AUP files, replace the exact line
   `- Browser automation via the agent-browser subsystem;`
   with the exact line (CLO-ruled, byte-identical on both surfaces)
   `- Browser automation via the agent-browser subsystem or a Playwright MCP server driven by Soleur agents or skills;`
2. Canonical frontmatter: `last-updated: 2026-09-13` → `last-updated: <WORK_DATE>`.
3. Both body `**Last Updated:**` lines: replace only the prefix `**Last Updated:** September 13, 2026 *(` with
   `**Last Updated:** <Long WORK_DATE> *(Section 2 scope now names browser automation through a Playwright MCP server.)* Previous: September 13, 2026 *(`
   — the ~3 kB history tail is not retyped. The parenthetical says WHAT changed only: no rationale, no PR/issue tokens (public doc).
4. Mirror hero: `| Last Updated September 13, 2026</p>` → `| Last Updated <Long WORK_DATE></p>`.
5. Last: `sha256sum docs/legal/acceptable-use-policy.md` → paste into `LEGAL_DOC_SHAS["acceptable-use-policy"]`. Any later canonical tweak means repinning.

### Phase 2 — Register date + trigger discharge

6. `compliance-posture.md`: the `Acceptable Use Policy` row's `2026-09-13` → `<WORK_DATE>`; frontmatter `last_updated: 2026-09-14` → `<WORK_DATE>`.
7. Append at end of the #7980 attestation (after the final `> **Note — 2026-09-14, after this addendum …**` blockquote), in the file's existing addendum style:

   ```markdown
   ## Addendum — #7981 re-evaluation trigger, <WORK_DATE>

   The frontmatter trigger "#7981 lands or is closed without landing" fired: PR #8207 widened the
   published AUP §2 bullet to name "a Playwright MCP server driven by Soleur agents or skills", and
   the bullet states nothing about any snapshot control. **Disposition: DISCHARGED, unchanged.**
   ```

   Frontmatter, carve-outs, the two browser-snapshot posture rows, and ADR-213 stay as written (dated history that remains true).

### Phase 3 — Verify and ship

8. Commit, then run AC1–AC8 (AC5 holds the gates' own invocations).
9. PR body: `Closes #7981`; one tier line — "Tier 2 (clarifying) by analogy; `TC_VERSION` not engaged: the T&C canonical is byte-unchanged and the AUP is a non-T&C notice doc (tc-version-bump-policy §Non-T&C legal docs)"; a pointer to the attestation addendum; `Ref #7980, #8156`. No committed file other than this plan restates the tier/TC_VERSION reasoning.

## Research Insights

**Premise Validation.** #7981 OPEN; draft PR #8207 OPEN on this branch. Cited artifacts exist: the §2 bullet in both files, `legal-doc-shas.ts`, `check-tc-document-sha.sh` with `acceptable-use-policy` in `BODY_EQUIVALENCE_DOCS`. Two brief claims corrected in the Reconciliation table. No ADR proposes or rejects a mechanism here.

**Property List.**

- P1. The published AUP §2 scope list names both browser-automation surfaces Soleur agents and skills drive, without asserting who registers the Playwright server or any safety property.
- P2. Canonical and mirror remain body-equivalent (required check stays green).
- P3. `LEGAL_DOC_SHAS["acceptable-use-policy"]` equals the new canonical bytes.
- P4. The change is dated consistently: canonical body and frontmatter, mirror body and hero, compliance register row.
- P5. The #7980 attestation's `#7981 lands` re-evaluation trigger is recorded as fired and discharged.
- P6. The `TC_VERSION` verdict and tier are recorded where the bump policy requires (PR body).

**Cut List.**

- `TC_VERSION` bump → P6 needs a recorded verdict, not a bump.
- New CLO attestation file → P5/P6 covered by the addendum + PR-body tier line; a new file would also need a breach-register waiver row and a `NOT_TRANSCRIBED` entry.
- New sentinel row in `legal-doc-consistency.test.ts` → P2 already enforced by body-equivalence, P3 by the SHA guard.
- HTML-comment changelog in `compliance-posture.md` → would restate rationale (operator: single-source).
- Editing the dated "#7981 stays Ref-only" statements (posture rows, ADR-213, attestation carve-outs) → remain true as history.
- Privacy Policy "MCP servers, browser automation tools" sentence → already generic and accurate.
- (plan-review) An undertaking-token grep, a fixed-literal PR-token grep (replaced by AC3's capture form), a separate T&C-untouched diff, a same-commit log diff, a post-merge curl, and a Test Scenarios section → each duplicated AC1/AC2/AC6/body-equivalence or could not fail.

**Relevant files.** `docs/legal/acceptable-use-policy.md` (§2 Scope list); `plugins/soleur/docs/pages/legal/acceptable-use-policy.md` (hero `<p>`, body Last Updated, §2); `apps/web-platform/lib/legal/legal-doc-shas.ts`; `apps/web-platform/scripts/check-tc-document-sha.sh` (`BODY_EQUIVALENCE_DOCS`); `apps/web-platform/lib/legal/tc-version.ts`; `knowledge-base/legal/tc-version-bump-policy.md` §Non-T&C legal docs; `apps/web-platform/test/legal-doc-consistency.test.ts` ("Last Updated date is identical between source and mirror"); `scripts/lint-legal-scope-block-placement.sh` (`LOCALITY_RE` = scope verb within 60 chars of a locality claim — the new bullet has neither); `scripts/lint-legal-mirror-drift-baseline.sh`; `scripts/lint-legal-registers.sh` (the #7980 attestation is already waived); `scripts/probe-legal-corpus-truth.sh`; `knowledge-base/legal/compliance-posture.md` row "Playwright-MCP snapshot redaction proxy" (reach a–d). Not affected (checked at plan-review): `plugins/soleur/test/seo-aeo-drift-guard.test.ts` (stub existence only), `legal-doc-cross-document-gate.yml` (DSAR paths only).

**Institutional learnings.**

- `knowledge-base/project/learnings/2026-05-29-legal-doc-triple-lockstep-and-rpc-grants-invoker-before-definer.md` — SHA pin + both mirror date locations move together.
- `knowledge-base/project/learnings/2026-03-20-eleventy-mirror-dual-date-locations.md` — the mirror hero `<p>` date is the one usually missed.
- `knowledge-base/project/learnings/2026-05-12-public-legal-doc-annotations-no-pr-numbers.md` — public Last-Updated annotations carry no PR/issue tokens.

**Precedent.** #8119 (substantive AUP edit: Last Updated + posture row moved); #7955 (cosmetic autolink: Last Updated untouched). The attestation already carries an `## Addendum — relay rebuild, 2026-09-14` section.

**Functional overlap.** functional-discovery: no meaningful community overlap. **External research:** skipped (strong local context; CLO ruling obtained).

## Open Code-Review Overlap

None (65 open `code-review` issues checked against all five planned paths).

## User-Brand Impact

- **If this lands broken, the user experiences:** a published AUP page whose §2 bullet differs between the repository canonical and soleur.ai, or a red required check blocking unrelated merges until the SHA pin is fixed.
- **If this leaks, the user's workflow is exposed via:** bullet wording that implied Jikigai ships or secures the Playwright server would create an undertaking the #7980 attestation disclaims; the CLO-ruled wording avoids it.
- **Brand-survival threshold:** `none`

*Scope-out override:* `threshold: none, reason: the only sensitive-path file touched, apps/web-platform/lib/legal/legal-doc-shas.ts, is a drift-detection literal with no runtime consumer, and the AUP wording change adds no obligation, processing purpose, recipient, or safety undertaking.`

## Observability

Required only because `apps/web-platform/lib/legal/` matches the preflight sensitive-path regex; there is no runtime surface.

```yaml
liveness_signal:
  what: "CI required check tc-document-sha-guard (SHA pin + canonical/mirror body-equivalence)"
  cadence: "every PR and merge-queue run"
  alert_target: "red required status check on the PR"
  configured_in: ".github/workflows/ci.yml job tc-document-sha-guard"
error_reporting:
  destination: "GitHub Actions ::error:: annotations on tc-document-sha-guard"
  fail_loud: "::error::legal doc \"acceptable-use-policy\" content changed but LEGAL_DOC_SHAS[...] is stale / ::error::acceptable-use-policy body drift"
failure_modes:
  - mode: "canonical and mirror diverge, or pin stale"
    detection: "apps/web-platform/scripts/check-tc-document-sha.sh"
    alert_route: "red required check on the PR"
  - mode: "Last Updated dates diverge across canonical body, mirror body, mirror hero"
    detection: "apps/web-platform/test/legal-doc-consistency.test.ts parity test"
    alert_route: "red test job on the PR"
logs:
  where: "GitHub Actions run logs"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: python3 -c "print('legal-doc-sha-guard OK' if __import__('subprocess').run(['bash','apps/web-platform/scripts/check-tc-document-sha.sh']).returncode == 0 else 'legal-doc-sha-guard RED')"
  expected_output: "legal-doc-sha-guard OK"
```

## Acceptance Criteria

### Pre-merge (PR)

All `git diff` checks run after committing, against the merge base (`origin/main...HEAD`), so a moving `main` cannot flip them.

- [x] AC1 — New bullet present exactly once per surface, old bullet gone: `grep -cxF -- '- Browser automation via the agent-browser subsystem or a Playwright MCP server driven by Soleur agents or skills;' docs/legal/acceptable-use-policy.md plugins/soleur/docs/pages/legal/acceptable-use-policy.md` → `:1` each; `grep -cxF -- '- Browser automation via the agent-browser subsystem;' <same two files>` → `:0` each.
- [x] AC2 — Canonical dated: `grep -c '^last-updated: <WORK_DATE>$' docs/legal/acceptable-use-policy.md` → 1; `grep -cF '**Last Updated:** <Long WORK_DATE> *(Section 2 scope now names browser automation through a Playwright MCP server.)* Previous: September 13, 2026 *(Harness-neutral' docs/legal/acceptable-use-policy.md` → 1. (Mirror body/hero parity is AC5's vitest.)
- [x] AC3 — The new public annotation carries no PR/issue token: `sed -n 's/^\*\*Last Updated:\*\* \(.*\) Previous: September 13, 2026.*/\1/p' docs/legal/acceptable-use-policy.md plugins/soleur/docs/pages/legal/acceptable-use-policy.md | grep -c '#[0-9]'` → 0 (capture stops before older history, which legitimately contains `PR #4949`).
- [x] AC4 — SHA pin: `git diff -U0 origin/main...HEAD -- apps/web-platform/lib/legal/legal-doc-shas.ts | grep -cE '^[+-] '` → 2 (only the AUP value line).
- [x] AC5 — Gates green, own invocations: `bash apps/web-platform/scripts/check-tc-document-sha.sh`; `bash scripts/lint-legal-mirror-drift-baseline.sh`; `bash scripts/lint-legal-scope-block-placement.sh`; `bash scripts/lint-legal-registers.sh`; `bash scripts/probe-legal-corpus-truth.sh`; `bash scripts/lint-legal-scope-block-placement.test.sh`; `bash scripts/lint-legal-mirror-drift-baseline.test.sh`; `bash scripts/lint-legal-registers.test.sh` — each exits 0; `cd apps/web-platform && ./node_modules/.bin/vitest run test/legal-doc-consistency.test.ts test/legal-doc-shas-guard.test.ts` → 2 files passed, 0 failed. (Plan-time baseline 2026-09-15: all eight scripts exit 0; vitest 43/43.)
- [x] AC6 — Diff scope: `git diff --name-only origin/main...HEAD` is a subset of the 5 Files to Edit + this plan + `knowledge-base/project/specs/feat-one-shot-7981-aup-scope-playwright-mcp/{tasks.md,session-state.md}` + the generated `knowledge-base/INDEX.md`, and `git diff --name-only origin/main...HEAD | grep -E '^(docs/legal|plugins/soleur/docs/pages/legal)/|tc-version\.ts$'` lists exactly the two AUP files (T&C and `TC_VERSION` untouched).
- [x] AC7 — Register: ``grep -cE '^\| Acceptable Use Policy \| `docs/legal/acceptable-use-policy.md` \| — \| <WORK_DATE> \| Active \|$' knowledge-base/legal/compliance-posture.md`` → 1; `grep -c '^last_updated: <WORK_DATE>$' knowledge-base/legal/compliance-posture.md` → 1.
- [x] AC8 — Attestation addendum append-only and scoped: `git diff --numstat origin/main...HEAD -- knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md` shows 0 deletions; `grep '^## ' <that file> | tail -1` is `## Addendum — #7981 re-evaluation trigger, <WORK_DATE>`; `awk '/^## Addendum — #7981 re-evaluation trigger/{f=1} f' <that file> | grep -c 'DISCHARGED, unchanged'` → 1.
- [ ] AC9 — PR #8207 body contains `Closes #7981`, the Tier 2 / `TC_VERSION` not-engaged line, and a pointer to the attestation addendum.

## Domain Review

**Domains relevant:** Legal

### Legal

**Status:** reviewed
**Assessment:** CLO planning ruling (draft requiring professional legal review).

- **Wording (Q1):** as in Phase 1. "A", not "the"/"Soleur's", so it survives #8156 and makes no registration or Web Platform claim; no redaction/safety wording, so no undertaking contrary to ADR-213 / the #7980 attestation; no scope-verb+locality shape.
- **Tier and TC_VERSION (Q2):** Tier 2 (clarifying) by analogy ("adding examples that illustrate an existing rule"). `TC_VERSION` **not engaged**. Decisive reason: the bump mechanism pins `docs/legal/terms-and-conditions.md` (`TC_DOCUMENT_SHA`), whose bytes do not change. The AUP is a non-T&C notice document with no version constant or acceptance ledger (tc-version-bump-policy §Non-T&C legal docs). The T&C entire-agreement clause incorporates the AUP by name, not a frozen revision, and AUP §8 governs its own changes (material ones only). The issue's own reason ("no clause changes") is imprecise — a clause does change.
- **Dates (Q3):** Last Updated moves in canonical body, mirror body, mirror hero, canonical frontmatter, the posture row and posture frontmatter.
- **Trigger (Q4):** discharge via an appended addendum on the #7980 attestation; no new attestation file; PR-body tier line suffices.
- **Lockstep (Q5):** nothing else in the published corpus names agent-browser or needs to move.

No Product/UX gate: no UI surface in Files to Edit (Eleventy legal markdown prose only).

## Risks & Sharp Edges

- The `**Last Updated:**` line is one ~3 kB line; replacing only its short prefix avoids retyping history. Body-equivalence catches a canonical/mirror mismatch but not an identical corruption on both — review the diff hunk.
- `WORK_DATE` may differ from the plan date; every AC uses the placeholder.
- #8156 may land first; the ruled wording is deliberately neutral to it.
- Declined auditor wording suggestions (deepen pass): (a) "a Playwright MCP server **that you configure**" — false once #8156 ships a default registration, which the CLO ruling expressly guards against; Privacy Policy §5.4 "initiated by you, configured by you" stays consistent because the user initiates the Soleur session that drives the server. (b) "a browser-automation MCP server (such as Playwright MCP)" — broader than the issue asks; the §2 list is already non-exhaustive ("including but not limited to"), and naming the concrete surface is the stated fix. Both are wording taste against a binding CLO ruling; recorded here, not persisted as a challenge.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold fails `deepen-plan` Phase 4.6.

### Deepen-plan verification record (2026-09-15)

- Phase 4.6: `## User-Brand Impact` present; threshold `none` with a `threshold: none, reason:` scope-out (required: `apps/web-platform/lib/legal/` matches `SENSITIVE_PATH_RE`). PASS.
- Phase 4.7: all five Observability fields present with children; no `ssh`; `plugins/soleur/skills/preflight/scripts/probe-verb-gate.sh` on the `discoverability_test.command` → exit 0. PASS.
- Phase 4.8: PAT-shape sweep → no match. 4.5/4.55/4.9/4.10/4.11: not triggered (no network symptom, downtime op, UI surface, store/connection, or guard).
- Verify-the-negative: plugin manifest registers no Playwright server (`plugins/soleur/.claude-plugin/plugin.json` `mcpServers` = context7, cloudflare, vercel, stripe); no Playwright reference under `apps/web-platform/server/` outside `server/inngest/` (Jikigai-internal cron fleet); `LEGAL_DOC_SHAS` has no consumer besides `check-tc-document-sha.sh`; no public page outside `docs/legal/acceptable-use-policy.md` names agent-browser; the Eleventy mirror has no `last-updated` frontmatter key (only the hero `<p>` and body line carry dates).
- Citations verified live: #7947 CLOSED, #7980 CLOSED, #8156 OPEN, #8119 MERGED (moved the posture AUP row 2026-08-11 → 2026-09-13 — precedent holds), #7955 MERGED, #8207 OPEN draft, #7981 OPEN. No AGENTS rule IDs cited in the plan body. Cited learning paths exist.

## Gates Skipped (with reason)

- GDPR gate (2.7): no schema/migration/auth/API surface; no new processing activity, recipient, or distribution surface.
- IaC (2.8), Encryption Posture (2.11), Guard Contract (2.12): no infrastructure, store, connection, or guard introduced.
- ADR/C4 (2.10): no architectural decision.
- Advisor consult (4.5): mechanical edit; wording fixed by the CLO ruling.

## References

- Issue #7981; draft PR #8207; related #7947, #7980, #8156.
- `knowledge-base/legal/audits/2026-09-14-clo-attestation-7980-playwright-mcp-redact-proxy.md` (`re_evaluation_triggers`).
- `knowledge-base/legal/tc-version-bump-policy.md` §Non-T&C legal docs.
