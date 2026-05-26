---
issue: 3708
branch: feat-one-shot-3708
related_issues: [3638, 3685, 3698, 3696, 3754]
related_prs: [3701, 3731, 3751]
related_adrs: [ADR-029]
date: 2026-05-13
deepened: 2026-05-13
lane: cross-domain
brand_survival_threshold: aggregate pattern
type: docs-legal
requires_cpo_signoff: false
---

# Plan: DPD §(l) Operational telemetry & breach detection user-facing entry (#3708)

## Enhancement Summary

**Deepened on:** 2026-05-13
**Sections enhanced:** 6 (Research Reconciliation, Files to Edit, Phase 1 draft wording, Acceptance Criteria, Risks, Sharp Edges)
**Research sources:** worktree-aware re-grep of both DPD files; learning carry-forward from `2026-03-18-dpd-processor-table-dual-file-sync.md` + `2026-03-10-first-pii-collection-legal-update-pattern.md` + `2026-02-21-gdpr-article-30-compliance-audit-pattern.md`; AGENTS.md rule-ID verification; gdpr-gate canonical regex inspection; cited PR/issue live verification via `gh`.

### Key Improvements

1. **Corrected Research Reconciliation row 1** — initial plan misread the canonical DPD §2.3 as ending at §(h); worktree-aware re-grep shows both files already enumerate §(a)-(k) in lockstep. The §(i)/§(j)/§(k) backfill follow-up is dropped (does not apply). §(l) inserts uniformly after §(k) in both files.
2. **Corrected gdpr-gate trigger framing** — the canonical regex at `plugins/soleur/skills/gdpr-gate/SKILL.md:54-60` is `^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)`. `docs/legal/**` does NOT match. The gdpr-gate is therefore NOT auto-invoked at plan Phase 2.7 by path-glob; the hard rule `hr-gdpr-gate-on-regulated-data-surfaces` extends-via-trigger-(d) ("new artifact distribution surface — plugin update, public PR body, package release") covers user-facing legal docs. Invoke `/soleur:gdpr-gate "<plan-path>"` manually at PR review.
3. **Live-verified all cited PR / issue numbers via `gh`** — #3701, #3731, #3751 are MERGED PRs; #3638, #3685 are CLOSED issues (with merged PRs); #3696, #3698, #3754 are CLOSED/OPEN issues, not PRs. Frontmatter split into `related_issues` and `related_prs` to prevent future paraphrase drift.
4. **Verified all cited AGENTS.md rule IDs** — `hr-gdpr-gate-on-regulated-data-surfaces`, `hr-weigh-every-decision-against-target-user-impact`, `wg-after-merging-a-pr-that-adds-or-modifies` all active in `AGENTS.core.md`. No retired or fabricated citations.
5. **Carry-forward dual-file sync discipline** from `2026-03-18-dpd-processor-table-dual-file-sync.md` — every structural change must touch BOTH files in the SAME commit (not just the same PR). Added explicit AC and grep gate.
6. **Added blanket-statement sweep** per `2026-03-10-first-pii-collection-legal-update-pattern.md` — `grep -nE "phone home|no telemetry"` returns hits in `privacy-policy.md:39` (both files), but those statements are scoped to the **Plugin** (local CLI), not the **Web Platform**. Verified no contradiction with §(l) (Web Platform-scoped). Sweep result recorded as AC17.

### New Considerations Discovered

- The `_site/legal/data-protection-disclosure/index.html` build artifact MUST contain the literal substring `Operational telemetry & breach detection` (AC8). Eleventy permalink stable at `legal/data-protection-disclosure/`.
- Sentry's DPA URL in §4.2 row: confirmed canonical at `https://sentry.io/legal/dpa/` (Sentry's standard EU-region DPA terms link, public).
- Hetzner is already in §4.2 (canonical line 151, Eleventy mirror equivalent). §(l) cross-reference to Hetzner is symmetric without new row.
- §7.2 "Platform Breaches" already covers the breach-notification disclosure timing (72-hour Art. 33 commitment, GitHub repository + email channel). §(l) need not duplicate; cross-reference instead.

## Overview

Add a user-readable §(l) entry to `docs/legal/data-protection-disclosure.md` (and its Eleventy mirror at `plugins/soleur/docs/pages/legal/data-protection-disclosure.md`) covering operational telemetry and breach detection. The entry mirrors `knowledge-base/legal/article-30-register.md` PA8 §(c)/§(d)/§(e)/§(f) wording in user-readable form, with no internal file paths or implementation detail. Closes the deferred-scope-out surfaced by CLO during brainstorm for #3698: PA8 in the Article 30 register documents pino stdout + Sentry telemetry processing in detail, but the user-facing DPD does not — exactly the "register has detail; DPD does not" mismatch a CNIL auditor would flag.

This is a docs-only legal change. No `apps/web-platform/` code is touched. No new processing activity is introduced — the activity exists since PRs #3701/#3731/#3751 shipped; this plan only fills the disclosure gap.

Reuse the §(f)/§(g)/§(h) wording style of post-#3751 (post-PR-C) §2.3 entries: bold sub-heading, what is processed (high-level, no file paths), legal basis, retention, cross-reference to §4.2 and §6.4 where relevant.

## User-Brand Impact

- **If this lands broken, the user experiences:** an opaque sentence in a legal document that under-discloses or over-discloses the actual processing. The realistic failure mode is wording drift between DPD §(l) and Article 30 register PA8 (the source of truth) — an auditor reading both side-by-side would see inconsistent claims and treat the DPD as the unreliable artifact. No user data is harmed by a wording failure; the harm is regulatory trust at the brand level.
- **If this leaks, the user's [data / workflow / money] is exposed via:** N/A — this PR introduces no new data flow. The leak vector being disclosed (pino stdout + Sentry, both pseudonymised at the helper/formatter/scrub boundaries per ADR-029) is already in place and already documented in PA8.
- **Brand-survival threshold:** `aggregate pattern` — this is a transparency-improvement disclosure that benefits all data subjects symmetrically. It is not a single-user incident class; no per-user breach is being remediated. The auditor-visibility framing (PA8 detail vs DPD silence) is structural, not per-user. `single-user incident` would over-claim — this PR adds no new defence and removes no existing one.

> Sharp edge: A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue body) | Codebase reality | Plan response |
|---|---|---|
| `docs/legal/data-protection-disclosure.md` §(k) is Resend retention; new §(l) appends after it. | **CORRECTED at deepen-pass** — initial plan paraphrased a stale read from a non-worktree path. Worktree-authoritative re-grep at `git ls-files`-rooted paths confirms BOTH files enumerate §(a)-(k) in lockstep: §(a) Docs Site hosting, …, §(h) Web Platform infrastructure hosting, §(i) Web Platform conversation management, §(j) Web Platform push notification subscriptions, §(k) Web Platform transactional email notifications (Resend). No drift exists in the worktree. Verified via `grep -nE '^- \*\*\([a-l]\)\*\*' apps/web-platform/...` and equivalent against both files — both return identical (a)-(k) listings. | Plan to add §(l) to BOTH files at the same insertion point: after §(k) in both. The §(l) wording is identical in both files. No backfill follow-up issue needed; the previously suspected drift is plan-paraphrase artifact, not codebase reality. Generalizes `2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` — verify worktree-authoritative state before asserting drift. |
| Wording mirrors "PA8 §(c) post-#3698". | Post-#3698, post-#3751 PA8 detail spans §(c) (data categories), §(d) (recipients), §(e) (third-country transfers), and §(f) (retention). The pseudonymisation claim is concretised across PRs #3701 (pino `formatters.log`), #3731 (Sentry `sentry-scrub.ts` symmetric coverage), #3751 (operator CLI + retention pin: `30 MB rolling per container, max-size=10m × max-file=3` pinned in `cloud-init.yml:303-310`, with `__TBD_OBSERVED_VOLUME__` sentinel pending operator measurement). ADR-029 documents the pattern. | Mirror the post-PR-C wording. §(l) cites: (1) **what's logged** (structured app logs to pino stdout on EU-only Hetzner; error and breadcrumb events to Sentry in DE region); (2) **pseudonymisation** (Recital 26 — `userId` renamed to a pseudonymous hash at the logger and Sentry-event boundaries; controller cannot re-identify from hash without server-resident pepper held in Doppler); (3) **retention** (Sentry: 90 days rolling; Hetzner pino stdout: `30 MB rolling per container` — quote the §(f) structural cap, do NOT invent a day count, do NOT inline the `__TBD_OBSERVED_VOLUME__` sentinel into user-facing prose); (4) **legal basis** (Art. 6(1)(f) legitimate interest in service reliability and security + Art. 6(1)(c) compliance with breach-notification obligation under Art. 33); (5) **Art. 17 erasure interaction** (the pseudonymous identifier ages out per Sentry/Hetzner retention; no active processor-side erasure call required for the pseudonym alone under Recital 26). |
| Sub-processor cross-references match `article-30-register.md` rows for Hetzner + Sentry. | PA8 §(d) recipients: Sentry (Functional Software GmbH, DE region, SCCs); Hetzner (Helsinki, FI, EU-only AVV); the on-call rotation (internal). Existing §4.2 of canonical DPD already lists Hetzner; Sentry is **NOT** listed in §4.2 of canonical DPD nor in the Eleventy mirror's §4.2 Web Platform Processors table. | The §(l) entry cross-references Hetzner via existing §4.2 row + §6.4 transfer mechanism. For Sentry, the §(l) entry names "Sentry (Functional Software GmbH, DE region; SCCs)" inline with the same disclosure rigor as the other §2.3(f)-(k) entries (Stripe, Hetzner, Cloudflare). Adding a Sentry row to §4.2 is **bundled in this PR** — without it the §(l) cross-reference is asymmetric with sibling entries. Out-of-scope: adding Sentry to §6.4 international-transfers as DE region is intra-EU (SCCs only required for inter-region Sentry sub-processor flow, which Soleur does not use today; PA8 §(e) confirms "Sentry processed in DE region under SCCs (Sentry's standard EU-region terms). pino stdout never leaves Hetzner Finland."). |
| CLO sign-off via legal-compliance-auditor agent or human counsel review. | `agents/legal/legal-compliance-auditor.md` exists; `agents/legal/clo.md` is the domain leader. **CORRECTED at deepen-pass:** the gdpr-gate canonical regex at `plugins/soleur/skills/gdpr-gate/SKILL.md:58-60` is `^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)`. `docs/legal/**` does NOT match this regex. The gdpr-gate is therefore not auto-invoked at plan Phase 2.7 by path-glob. Hard rule `hr-gdpr-gate-on-regulated-data-surfaces` extension trigger (d) ("new artifact distribution surface — plugin update, public PR body, package release") arguably covers user-facing legal docs but is operator-judgment. | Plan-time: invoke `legal-compliance-auditor` agent at plan §Phase 4 (review) to verify the §(l) wording mirrors PA8 truthfully. PR-time: manually invoke `/soleur:gdpr-gate "knowledge-base/project/plans/2026-05-13-feat-dpd-operational-telemetry-disclosure-plan.md docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md"` as advisory check. Counsel review can run in parallel or be deferred to the quarterly cadence — the disclosure is not blocked by external counsel sign-off because it strictly increases transparency without adding new processing. |
| Brand-survival threshold framing. | Brainstorm for #3698 set threshold `single-user incident` for the parent (raw `userId` on disk = personal data per Art. 4(1)). This child (DPD disclosure) is a downstream documentation gap, not a new exposure surface. | Threshold `aggregate pattern` is correct here. The disclosure does not introduce or remove a defence; it improves transparency symmetrically across all data subjects. Sharp edge from `2026-05-12-defense-in-depth...` applies inverted: we are NOT relaxing a defence; we are not introducing one either. |

## Files to Edit

1. `docs/legal/data-protection-disclosure.md` (canonical / GitHub-rendered source)
   - Insert `- **(l)** **Operational telemetry & breach detection:** …` after current §(k) (Web Platform transactional email notifications / Resend). Verified line: `99-101` window for §(i)/§(j)/§(k); new §(l) lands at the equivalent next line.
   - Update `**Last Updated:**` line 12 with a one-line append: bump date prefix to "May 13, 2026" and append the parenthesised history fragment `(added Section 2.3(l) Operational telemetry & breach detection covering pino stdout and Sentry processing, added Sentry row to Section 4.2 Web Platform Processors table, extended Section 6.4 international transfers with Sentry DE region under SCCs)`. Preserve the existing March 20, 2026 history string verbatim.
   - Add a **Sentry (Functional Software GmbH)** row to the Web Platform Processors table in §4.2 (after the Cloudflare row) with: Processing Activity = "Error monitoring and breach detection (Sentry SDK)"; Data Processed = "Error messages, stack traces, request metadata, pseudonymous user identifier (`userIdHash`)"; Legal Basis = "Legitimate interest (Article 6(1)(f)) for service reliability; legal obligation (Article 6(1)(c)) for Article 33 breach-notification timeliness"; Sub-processor List = `[Sentry Sub-processors](https://sentry.io/legal/dpa/)` (canonical DPA URL verified at deepen-pass).
   - Extend §6.4 (Web Platform international transfers) with a Sentry bullet: "**Sentry:** DE region (Frankfurt, Germany), processed by Functional Software GmbH. Transfer mechanism: Standard Contractual Clauses (Sentry's standard EU-region terms). Intra-EU processing — no third-country transfer. DPA self-executing via Sentry's terms of service (verified 2026-05-13)." Prefer §6.4 bullet over new §6.5 subsection (minimal diff; verification-date pattern matches Cloudflare line `verified 2026-03-19`).

2. `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` (Eleventy mirror / user-rendered HTML source)
   - Insert `- **(l)** **Operational telemetry & breach detection:** …` after current §(k) (line 110, Resend transactional email). **Identical wording to file #1.**
   - Update both `Last Updated` lines:
     - Line 11 hero `<p>` → `Effective February 20, 2026 | Last Updated May 13, 2026` (no colon between "Updated" and date per `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`).
     - Line 21 body → `**Last Updated:** May 13, 2026 (added Section 2.3(l) Operational telemetry & breach detection covering pino stdout and Sentry processing, added Sentry row to Section 4.2 Web Platform Processors table, extended Section 6.4 international transfers with Sentry DE region under SCCs)`. Preserve the existing May 12, 2026 history string verbatim (Resend Legal Basis column trim from prior PR).
   - Add the same Sentry row to §4.2 and the same §6.4 Sentry bullet as file #1.

3. `knowledge-base/legal/compliance-posture.md`
   - Append a one-line Article 30 row note recording that DPD §(l) now mirrors PA8 §(c)/§(d)/§(e)/§(f) for the operational telemetry processing activity. Pattern matches PR #3751's append-pattern (verified at deepen-pass via `gh pr view 3751` body).

## Files to Create

None. This is a pure disclosure update to existing legal documents.

## Implementation Phases

### Phase 0 — Preflight (Plan-Time, Already Done)

- [x] Read PA8 source-of-truth wording at `knowledge-base/legal/article-30-register.md:157-163` (post-#3751).
- [x] Verify §(l) is the next available enumerator in both DPD files (corrected at deepen-pass: §(k) is the last entry in BOTH files; the §(l) heading is unambiguous in both).
- [x] Verify ADR-029 invariants relevant to the disclosure (I1 rename-not-redact, I5 PA8 §(c) coupling, I10 two-primitive separation — only the `hashUserId` primitive needs DPD disclosure; the DSAR cross-tenant primitive `hashUserIdForSentry` is a breach-anchoring alarm channel, not a routine telemetry surface).
- [x] Confirm Sentry is not in canonical §4.2 (gap to close in same PR — keeps §(l)'s cross-reference symmetric).
- [x] Confirm threshold is `aggregate pattern` (no `requires_cpo_signoff: true`).

### Phase 1 — Draft §(l) wording

Draft 1 paragraph of ~150-200 words for §(l) covering the five framing axes from the Research Reconciliation row 2. Author the prose as a list-item bullet matching the §(f)/§(g)/§(h)/§(k) shape:

```markdown
- **(l)** **Operational telemetry & breach detection:** The Web Platform emits two operational telemetry streams to support service reliability and breach-detection obligations under GDPR Articles 32 and 33. (i) **Structured application logs** are written to standard output by the application server on Hetzner infrastructure in Helsinki, Finland (EU-only) and retained in a rolling Docker log buffer (capacity-bounded; no off-host log shipping is configured). (ii) **Error and breadcrumb events** are sent to Sentry (Functional Software GmbH, DE region; Standard Contractual Clauses) for error monitoring. In both streams, user identifiers are pseudonymised at the emission boundary by replacing the raw `userId` with a keyed cryptographic hash (`userIdHash`) computed using a server-resident secret pepper held in Doppler. Under GDPR Recital 26, the controller cannot re-identify a data subject from the hash alone without the pepper. Legal basis: legitimate interest (Article 6(1)(f) GDPR) in service reliability, security, and abuse prevention, balanced against the pseudonymisation safeguard; together with legal obligation (Article 6(1)(c) GDPR) for compliance with the Article 33 breach-notification timeline. Retention: Sentry events retained for 90 days (rolling); pino stdout retained in a fixed-capacity Hetzner-local rolling buffer (no off-host copies). Right to erasure (Article 17 GDPR): hashed identifiers age out per the rolling retention windows; the controller cannot perform processor-side targeted erasure of a pseudonym whose subject cannot be re-identified, consistent with Recital 26.
```

Decisions encoded in the draft:

- **No file paths.** "the application server", "the emission boundary", "the application server on Hetzner infrastructure" — never `apps/web-platform/server/logger.ts` or `formatters.log()`. The user-facing DPD must read for a data subject, not for an engineer. PA8 §(c) §(ii) carries the implementation detail (ADR-029 §I5 coupling); DPD §(l) carries the disclosure summary.
- **No `__TBD_OBSERVED_VOLUME__`.** The sentinel in PA8 §(f) is an operator measurement marker; surfacing it in a legal document would be incoherent. Quote the structural cap behaviour ("fixed-capacity rolling buffer; no off-host copies") without committing to a day count. When the post-merge operator measurement (#3754) lands, the §(l) prose does not need to change — only PA8 §(f) does.
- **HMAC-SHA256 not named.** "keyed cryptographic hash" + the Recital 26 framing is sufficient for the data subject. PA8 names HMAC-SHA256 explicitly for the auditor. ADR-029 names the primitive for the architect.
- **Don't mention `hashUserIdForSentry`.** The DSAR cross-tenant primitive (ADR-029 §I10) is a salt-keyed alarm primitive, not a routine telemetry channel. It does not need DPD surfacing; it is correctly disclosed at PA8 §(c) §(i) "cross-tenant DSAR-export breach-detection path".
- **Anchor the legal basis on Art. 6(1)(f) + Art. 6(1)(c).** Brainstorm CLO confirmed this dual basis. The `(c)` legal-obligation pin on Article 33 is the auditor-defensible framing for the retention window (you must retain breach-investigation context until the 72-hour clock + investigation buffer closes, even if the user requests erasure).
- **Art. 17 framing follows Recital 26.** This is the key Plain-English claim: "we cannot erase what we cannot re-identify; it ages out." Mirror PA8 §(f) Note on Art. 17.

### Phase 2 — Wire the Sentry row into §4.2

Add the Sentry processor row to the Web Platform Processors table immediately after the Cloudflare row in both files. Wording for Sub-processor List: link to `https://sentry.io/legal/dpa/`. Wording for Data Processed: "Error messages, stack traces, request metadata, pseudonymous user identifier (`userIdHash`)" — note the `userIdHash` token is the established naming contract from ADR-029 / PA8 §(c) and is intentionally surfaced (it makes the pseudonymisation defensive posture machine-greppable across the disclosure stack).

### Phase 3 — Wire §6.4 Sentry bullet

Prefer extending §6.4 with a Sentry sub-bullet (minimal diff over adding §6.5). Wording template: "**Sentry:** DE region (Frankfurt, Germany), processed by Functional Software GmbH. Transfer mechanism: Standard Contractual Clauses (Sentry's standard EU-region terms). Intra-EU processing — no third-country transfer. DPA self-executing via Sentry's terms of service (verified 2026-05-13)." The verification date matches the plan date; this is the standard pattern (see §6.4 Cloudflare line: "verified 2026-03-19").

### Phase 4 — Bundle Last-Updated history line

Both files carry a parenthesised history list in the `**Last Updated:**` line. Append: `(added Section 2.3(l) Operational telemetry & breach detection covering pino stdout and Sentry processing, added Sentry row to Section 4.2 Web Platform Processors table, cross-referenced Section 6.4 international transfers for Sentry DE region under SCCs)`. Preserve existing history strings verbatim (canonical has a March 20, 2026 entry; Eleventy mirror has a May 12, 2026 entry). The hero `<p>` in the Eleventy mirror must also bump to "Last Updated May 13, 2026" (no colon, per `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`).

### Phase 5 — Cross-document propagation

- `knowledge-base/legal/compliance-posture.md`: append one Article 30 row note. Pattern follows PR #3751's append-pattern verbatim.
- **Sibling-doc sweep** (per `2026-03-10-first-pii-collection-legal-update-pattern.md`): grep all legal docs for blanket statements that could contradict the new §(l). Patterns to scan: `"phone home"`, `"no telemetry"`, `"does not transmit"`, `"no analytics"`. Confirmed at deepen-pass: `privacy-policy.md:39` and the Eleventy mirror line 48 say "The **Plugin** does not phone home, send telemetry, or transmit analytics to Jikigai-operated servers" — scope is the local CLI Plugin, NOT the Web Platform. No contradiction. No edit needed. (Sweep result preserved as AC17 for re-verification at /work.)
- No follow-up issue required for §2.3 enumeration drift — confirmed at deepen-pass that canonical and Eleventy mirror are in lockstep on §(a)-(k) (initial plan's drift assertion was paraphrase-from-stale-read; corrected).

### Phase 6 — Verification

#### Acceptance Criteria

##### Pre-merge (PR)

- [ ] **AC1** — `grep -nE '^\- \*\*\(l\)\*\* \*\*Operational telemetry & breach detection:\*\*' docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns exactly one match per file.
- [ ] **AC2** — `grep -cE 'Sentry \(Functional Software GmbH\)|Functional Software GmbH' docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns ≥ 2 per file (one in §(l), one in §4.2 row; possibly one more in §6.4 bullet).
- [ ] **AC3** — Tolerant regex `'Last Updated[: *]+May 13, 2026'` per `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`. Per-file counts: canonical `docs/legal/data-protection-disclosure.md` returns 1 (body `**Last Updated:**` line only — canonical has no hero `<p>`); Eleventy mirror returns 2 (hero `<p>` line + body `**Last Updated:**` line). Verification command: `for f in docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md; do printf '%s: %s\n' "$f" "$(grep -cE 'Last Updated[: *]+May 13, 2026' "$f")"; done` returns 1, 2 in order. Do NOT use the literal `'Last Updated May 13, 2026'` form that misses the body's `:**` separator.
- [ ] **AC4** — `grep -nE 'userIdHash|pseudonymous|Recital 26' docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns ≥ 2 distinct hits per file inside the §(l) region.
- [ ] **AC5** — `grep -nE 'Article 6\(1\)\(f\)|Article 6\(1\)\(c\)' docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns the §(l) legal-basis lines (dual basis) in each file.
- [ ] **AC6** — `grep -nE 'Article 17|right to erasure|ages out' docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns the §(l) Art. 17 interaction line in each file.
- [ ] **AC7** — `knowledge-base/legal/compliance-posture.md` carries a new append-line referencing #3708 and the PA8 §(c)/§(d)/§(e)/§(f) DPD mirror.
- [ ] **AC8** — `bun run docs:build` (or `bunx @11ty/eleventy --input=plugins/soleur/docs --output=_site`) succeeds and emits a valid `_site/legal/data-protection-disclosure/index.html` containing the literal substring `Operational telemetry & breach detection`.
- [ ] **AC9** — `gdpr-gate` skill invocation produces no `compliance/critical` finding. Per the gate spec, this disclosure is advisory-only by construction (`docs/legal/**` is in the canonical regex; the change improves transparency and does not introduce new processing).
- [ ] **AC10** — `legal-compliance-auditor` agent runs at PR review against the §(l) draft and confirms wording mirrors PA8 §(c)/§(d)/§(e)/§(f) truthfully. Agent output is captured in the PR description's review log.
- [ ] **AC11** — No raw `userId` / `user_id` / `hashUserId` / `hashUserIdForSentry` / `formatters.log` / file-path tokens (`apps/web-platform`, `server/logger.ts`, `sentry-scrub.ts`) appear in §(l) prose. The §(l) entry is user-facing; implementation tokens belong to PA8 / ADR-029. Verification: `grep -nE 'apps/web-platform|formatters\.log|sentry-scrub|hashUserId(ForSentry)?' docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns no matches.
- [ ] **AC12** — Both DPD files end §2.3 enumeration at the new (l). Verification: `grep -cE '^- \*\*\(l\)\*\* ' docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns 1 per file, AND `grep -cE '^- \*\*\(m\)\*\* ' docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md` returns 0 per file (no §(m) — §(l) is the final entry).
- [ ] **AC13** — Dual-file commit invariant per `2026-03-18-dpd-processor-table-dual-file-sync.md`: both DPD files must be in the SAME commit. Verification (HEAD-state, union-trap-safe per `2026-05-11-plan-review-caught-git-log-union-trap...`): the §(l) AC1 grep passes on BOTH files at the PR's HEAD; the §(l) wording is byte-identical across the two files (`diff <(awk '/^- \*\*\(l\)\*\*/,/^- \*\*\([m-z]\)\*\*/{if(/^- \*\*\([m-z]\)\*\*/)exit;print}' docs/legal/data-protection-disclosure.md) <(awk '...' plugins/soleur/docs/pages/legal/data-protection-disclosure.md)` returns empty).
- [ ] **AC14** — PR body uses `Closes #3708` (deferred-scope-out class; standard close-on-merge; not the `Ref #N` ops-remediation pattern).

##### Pre-merge (PR) — additional verifications

- [ ] **AC17** — Sibling-doc blanket-statement sweep (per `2026-03-10-first-pii-collection-legal-update-pattern.md`): `grep -nE 'phone home|no telemetry|does not transmit|no analytics|"does not collect"' docs/legal/*.md plugins/soleur/docs/pages/legal/*.md` returns the existing Plugin-scoped statements (privacy-policy.md:39 + mirror line 48) — they are scoped to the local CLI Plugin, NOT the Web Platform; no contradiction with the new Web Platform-scoped §(l). Sweep result documented in PR body.

##### Post-merge (operator)

- [ ] **AC15** — None required. This is a docs-only change. No `terraform apply`, no migration, no external-service mutation. Automation feasibility per `2026-04-22-plan-ac-external-state-must-be-api-verified.md`: not applicable.
- [ ] **AC16** — Quarterly CLO audit cadence (per `agents/legal/clo.md` review cycle) re-reads the §(l) prose against the current PA8 wording to detect silent drift in either direction. Tracked as a recurring item, not a per-PR step.

#### Test Scenarios

This is a docs-only change. No code path is exercised. Test "scenarios" are document-coherence checks (covered by AC1-AC12).

#### Hypotheses

None — no investigative hypothesis. The disclosure gap is empirically observable (PA8 has detail; DPD does not). The fix is a mechanical mirror.

## Open Code-Review Overlap

None. Verified via `gh issue list --label code-review --state open` then `jq` on file-path matches for `data-protection-disclosure.md` and `article-30-register.md` — both returned zero. Recorded so the next planner can see this check ran.

## Domain Review

**Domains relevant:** Legal (primary), Engineering (advisory — Eleventy build, file-path verification).

### Legal (CLO)

**Status:** carry-forward from brainstorm for #3698 (Phase 0.5 brainstorm CLO assessment: "DPD `docs/legal/data-protection-disclosure.md` lacks a telemetry entry — pre-existing gap, separate follow-up issue (not in #3698 scope)").
**Assessment:** Adding §(l) closes a transparency gap without adding new processing. PA8 is the source of truth (post-PRs #3701/#3731/#3751 wording is settled). Mirror the §(c)/§(d)/§(e)/§(f) framing in user-readable prose. Include the Sentry row in §4.2 in the same PR to keep cross-references symmetric. Quarterly CLO audit cadence re-checks drift.

### Engineering (CTO)

**Status:** advisory.
**Assessment:** No code touched. Verify the Eleventy build at AC8 (the `_site/legal/data-protection-disclosure/index.html` artifact). Confirm no `_site/` paths or workflow `test -f` predicates break (see `2026-04-28-learning-sharp-edges-need-tracking-issues-not-memory.md` — the DPD permalink is `legal/data-protection-disclosure/` which has been stable; no path-token sweep needed for this PR).

### Product/UX Gate

**Tier:** NONE. No user-facing UI surface is created. Eleventy renders prose only; no new components, no new flows. Per the mechanical escalation rule (`components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`), no new files match. Confirmed NONE.

## Alternative Approaches Considered

| Approach | Why considered | Why rejected |
|---|---|---|
| **A — Single-file edit (Eleventy mirror only)** | Eleventy mirror is the user-visible artifact (rendered at `https://soleur.ai/legal/data-protection-disclosure/`). | Canonical `docs/legal/data-protection-disclosure.md` is referenced by AGENTS.md `hr-gdpr-gate-on-regulated-data-surfaces` canonical regex and is the audit source-of-record. Two-file parity is the established convention (sibling PRs #3701/#3731/#3751 all touched both). |
| **B — ~~Backfill §(i)/§(j)/§(k) into canonical in same PR~~** | ~~Closes the canonical-vs-Eleventy drift in one motion.~~ | **Withdrawn at deepen-pass.** Worktree-authoritative re-grep confirmed no drift exists; both files already enumerate §(a)-(k) in lockstep. The plan's initial assertion was paraphrase-from-stale-read; corrected in Research Reconciliation row 1. |
| **C — Replace §(l) prose with a verbatim PA8 §(c) quote** | Zero drift risk by construction. | PA8 wording is auditor-grade engineering prose ("`formatters.log` boundary", `apps/web-platform/server/logger.ts:N`, "ADR-029 §I4"). A data subject reading the DPD should not need to parse implementation detail. The two-document split (PA8 = engineer/auditor; DPD = data subject) is intentional. |
| **D — Add §(l) but skip the §4.2 Sentry row** | Smaller diff. | Cross-reference asymmetry: §(l) mentions "Sentry (Functional Software GmbH, DE region; SCCs)" but §4.2 does not enumerate Sentry. An auditor reading §(l) and consulting the §4.2 processor table for the DPA link would find the link missing. Symmetry with §(f)/§(g)/§(h) requires the §4.2 row. |
| **E — Defer to a quarterly CLO audit cycle (no PR)** | Issue is `priority/p3-low`. | The deferred-scope-out class explicitly leaves the issue open; the brand-survival framing for this issue is `aggregate pattern` and merits closure when the fix is mechanical. The cost of writing §(l) is bounded and the closure improves the disclosure stack symmetrically. |

## Non-Goals / Out of Scope

- **~~Backfill of §(i)/§(j)/§(k) into canonical DPD.~~** Withdrawn at deepen-pass — no drift to backfill (Research Reconciliation row 1 correction).
- **Adding Sentry to §6.4 third-country transfers table.** Sentry DE region is intra-EU; SCCs cover it via the §6.4 sub-bullet (Phase 3). No third-country transfer to disclose.
- **Documenting the DSAR cross-tenant `hashUserIdForSentry` primitive in user-facing DPD.** ADR-029 §I10 establishes the two-primitive split; only the routine telemetry primitive (`hashUserId`) needs DPD disclosure. The cross-tenant primitive is correctly disclosed at PA8 §(c) §(i) "cross-tenant DSAR-export breach-detection path" as an internal breach-anchoring channel.
- **PA8 §(f) `__TBD_OBSERVED_VOLUME__` resolution.** Tracked by #3754 (PR-C follow-through, post-merge operator measurement). DPD §(l) does NOT cite the observed day count to avoid stale-coupling.
- **Client-side `lib/client-observability.ts` user-facing disclosure.** Tracked as #3696. When #3696 lands, a follow-up may extend §(l) with a (iii) browser-bundle bullet — explicitly out of scope for #3708.
- **Pepper rotation runbook / Doppler rotation cadence disclosure.** YAGNI per parent #3638 brainstorm.

## Risks

- **R1 — Wording drift from PA8 post-merge.** If PA8 wording changes in a future PR (e.g., when #3754 resolves the observed-volume sentinel) and the DPD §(l) prose does not change in lockstep, an auditor reading both will see inconsistency. **Mitigation:** ADR-029 §I5 establishes the PA8 §(c) coupling pattern; extend the same coupling discipline to PA8 §(d)/§(e)/§(f) ↔ DPD §(l). Add a one-line comment in PA8 §(c) §(ii) and §(f) noting "User-facing mirror: DPD §(l)" (deferred to follow-up — adds drift coupling without a hard CI gate; quarterly CLO audit is the soft gate today).
- **R2 — Over-disclosure of pepper location.** The §(l) prose says "server-resident secret pepper held in Doppler". An attacker reading this learns the pepper-management vendor (Doppler). **Mitigation:** vendor naming is already public in §2.1b (Web Platform processors include Doppler-equivalent disclosure via the supabase/stripe/hetzner/cloudflare table); the pepper's secrecy is the keying material itself, not the secrets-manager identity. The PA8 wording already names Doppler explicitly. No additional risk introduced.
- **R3 — Eleventy build regression on the changed permalink section.** Permalink `legal/data-protection-disclosure/` is stable; `2026-04-28-learning-sharp-edges-need-tracking-issues-not-memory.md` flags permalink-change sweeps, not prose changes. **Mitigation:** AC8 runs the build and asserts the rendered substring.
- **R4 — Sentry §4.2 row drift from §(l) prose.** The §(l) Sentry naming ("Sentry (Functional Software GmbH, DE region; SCCs)") must match the §4.2 row Processor column exactly. **Mitigation:** AC2 enforces the literal `Functional Software GmbH` token in both locations per file.
- **R5 — Plan paraphrase-without-verification on §2.3 enumeration.** Initial plan drafted against a non-worktree path read of `docs/legal/data-protection-disclosure.md` that returned an out-of-date view (§(a)-(h) only); worktree-authoritative re-grep at deepen-pass confirmed both files are in lockstep on §(a)-(k). Per AGENTS.md `hr-when-in-a-worktree-never-read-from-bare`: when working in a worktree, always read paths rooted at the worktree, never at the bare repo. Caught at deepen-pass via second worktree-aware grep. No residual risk in the corrected plan.
- **R6 — Sibling-doc blanket-statement contradiction with §(l).** Per `2026-03-10-first-pii-collection-legal-update-pattern.md`, transitions from zero-telemetry framing to disclosed telemetry can leave stale "Plugin does not phone home" statements in `privacy-policy.md` and `terms-and-conditions.md`. **Mitigation:** verified at deepen-pass — all such statements are scoped to the **Plugin** (local CLI), not the **Web Platform**. The Plugin/Web Platform two-surface split is already established in §2.1 vs §2.1b; the §(l) entry sits squarely in the Web Platform surface (§2.3 sub-paragraphs (f)-(l) are all Web Platform-scoped). AC17 re-runs the grep at PR-review to confirm no new contradictions surface.

## Sharp Edges

- **SE1 — §(l) prose MUST NOT contain implementation tokens.** AC11 enforces. The temptation to write "via `formatters.log()`" is real; resist. The DPD is for data subjects; PA8 is for auditors.
- **SE2 — Hero vs body Last-Updated regex.** Per `2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md`, hero `<p>` uses `Last Updated May 13, 2026` (no colon); body uses `**Last Updated:** May 13, 2026 (…)`. AC3 uses the tolerant regex `'Last Updated[: *]+May 13, 2026'` to match both. A literal-string regex would silently miss the body.
- **SE3 — Don't quote `__TBD_OBSERVED_VOLUME__` in DPD prose.** The sentinel is an operator measurement marker for PA8 only. Surfacing it in legal prose is incoherent. Quote the structural cap ("fixed-capacity rolling buffer") without committing to a day count.
- **SE4 — Don't backfill §(i)/§(j)/§(k) into canonical here.** Moot at deepen-pass — no drift exists; both files in lockstep. Retained as a tombstone so a future planner who notices the worktree-vs-bare-repo confusion does not re-file the false drift.
- **SE5 — Verify follow-up issue labels via `gh label list` before AC13.** Per `2026-05-06-plan-prescribed-labels-must-be-verified.md`. `type/security`, `domain/legal`, `priority/p3-low` are confirmed to exist (verified at plan time via `gh label list --limit 200 | grep`).
- **SE6 — `gdpr-gate` invocation is operator-driven for this PR.** Verified at deepen-pass: canonical regex at `plugins/soleur/skills/gdpr-gate/SKILL.md:58-60` is `^(apps/web-platform/supabase/migrations/|apps/web-platform/lib/auth/|apps/web-platform/server/.*auth.*\.(ts|tsx|js)|apps/web-platform/app/api/.*\.(ts|tsx)$|.*\.sql$)`. `docs/legal/**` does NOT match this regex — gdpr-gate is NOT auto-fired at plan Phase 2.7 by path. The `hr-gdpr-gate-on-regulated-data-surfaces` rule's trigger (d) ("new artifact distribution surface") arguably applies to user-facing legal docs but is operator-judgment. Run `/soleur:gdpr-gate "docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md"` manually at PR review as advisory check. Advisory-only by construction (improves transparency); should not produce `compliance/critical` findings.
- **SE7 — Canonical and Eleventy file edits MUST land in the SAME commit.** Per `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md` adapted: the two files form a contract pair (canonical = source-of-record; Eleventy = user-rendered). Asymmetric commits would ship the user-visible mirror without the audit source-of-record, or vice versa. Bundle in the same commit (not just the same PR). Verification: `git log --format='%H' -- docs/legal/data-protection-disclosure.md plugins/soleur/docs/pages/legal/data-protection-disclosure.md | sort -u | wc -l` returns 1 over the PR's commits. Note the union-trap from `2026-05-11-plan-review-caught-git-log-union-trap-and-cross-module-field-assumption.md`: this `git log` returns commits touching EITHER file; for the same-commit invariant use the tempfile + per-commit `git show` walk pattern, OR rely on the HEAD-state grep over both files passing AC1 simultaneously.
- **SE8 — Mark the PR as deferred-scope-out close.** Per the issue's `deferred-scope-out` label and the AGENTS.md `hr-when-an-audit-identifies-pre-existing` rule: this closure does NOT count as a ship-Phase-5.5 blocker for any other PR; it stands on its own.

## Compound Capture Targets

- **Learning** — "User-facing legal docs mirror engineering disclosure docs through paired commits, not paired PRs." Captures SE7 + the canonical-vs-Eleventy drift class.
- **Learning** — "DPD §(l) wording rules: no implementation tokens, dual legal basis (Art. 6(1)(f) + 6(1)(c)), Recital 26 framing on Art. 17 erasure." Operational for future telemetry-class disclosure additions.

## PR Body Reminders

- `Closes #3708`
- Title format: `feat(legal): add DPD §(l) operational telemetry & breach detection user-facing entry`
- Labels at PR-create: inherit `domain/legal`, `priority/p3-low`, `type/security` from the issue; add `chore` if appropriate.
- Reference parent context: #3698 (parent telemetry-pseudonymisation track); related PRs #3701, #3731, #3751.
- Note in PR body: "Plan: `knowledge-base/project/plans/2026-05-13-feat-dpd-operational-telemetry-disclosure-plan.md`. Brainstorm: carry-forward from `knowledge-base/project/brainstorms/2026-05-12-pino-userid-formatters-log-brainstorm.md` §Sub-Issues."

## References

- Article 30 register source-of-truth: `knowledge-base/legal/article-30-register.md:157-163` (PA8 post-#3751).
- ADR-029: `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md`.
- Brainstorm: `knowledge-base/project/brainstorms/2026-05-12-pino-userid-formatters-log-brainstorm.md` §Sub-Issues + §Domain Assessments / Legal (CLO).
- Spec for #3698: `knowledge-base/project/specs/feat-pino-userid-redaction-3698/spec.md` Non-Goals (#3708 explicitly listed).
- Sibling PRs: #3701 (PR-A formatters.log — MERGED, verified via `gh pr view 3701`), #3731 (PR-B Sentry symmetric — MERGED), #3751 (PR-C operator CLI + PA8 §(f) retention pin — MERGED).
- Sibling issues: #3638 (CLOSED parent), #3685 (CLOSED), #3696 (CLOSED follow-up — client-side, not blocking), #3698 (CLOSED parent), #3754 (OPEN follow-through for `__TBD_OBSERVED_VOLUME__` resolution — does NOT block #3708).
- Hard rules verified active in `AGENTS.core.md`:
  - `hr-gdpr-gate-on-regulated-data-surfaces` (line 31)
  - `hr-weigh-every-decision-against-target-user-impact` (line 29)
  - `wg-after-merging-a-pr-that-adds-or-modifies` (line 52)
- gdpr-gate canonical regex: `plugins/soleur/skills/gdpr-gate/SKILL.md:58-60`. `docs/legal/**` does NOT match → manual invocation at PR review.
- Sharp-edge learnings carried forward:
  - `knowledge-base/project/learnings/2026-03-18-dpd-processor-table-dual-file-sync.md` — every structural change touches BOTH DPD files in the SAME commit; processor-table summary cross-references detail sections (don't reproduce implementation specifics).
  - `knowledge-base/project/learnings/2026-03-10-first-pii-collection-legal-update-pattern.md` — blanket-statement grep sweep across all legal docs after the targeted edits, not just on sections changed. Verified at deepen-pass; AC17 enforces.
  - `knowledge-base/project/learnings/2026-02-21-gdpr-article-30-compliance-audit-pattern.md` — Article 30 register is the source of truth; user-facing docs mirror.
  - `knowledge-base/project/learnings/2026-05-12-region-replacement-acs-must-enumerate-trailing-paragraphs.md` — hero vs body Last-Updated regex (AC3).
  - `knowledge-base/project/learnings/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` — paraphrase-without-verification (caught at deepen-pass; corrected R5).
  - `knowledge-base/project/learnings/2026-05-06-plan-prescribed-labels-must-be-verified.md` — `gh label list` verified for AC13.
  - `knowledge-base/project/learnings/2026-04-22-plan-ac-external-state-must-be-api-verified.md` — no API state mutation; AC15 records the rationale.
  - `knowledge-base/project/learnings/2026-05-11-plan-review-caught-git-log-union-trap-and-cross-module-field-assumption.md` — AC13 dual-file commit invariant uses HEAD-state grep, not `git log -- A B` (which is a union filter and silently green-lights asymmetric commits).

## Deepen-Pass Verifications

Inline record of authoritative checks run at deepen-pass (timestamp: 2026-05-13):

| Claim verified | Method | Result |
|---|---|---|
| Canonical DPD §2.3 enumerates (a)-(k) in worktree | `grep -nE '^- \*\*\([a-l]\)\*\* ' .worktrees/feat-one-shot-3708/docs/legal/data-protection-disclosure.md` | (a)-(k) listed; (l) absent (this PR adds it). Initial plan misread from non-worktree path; corrected. |
| Eleventy mirror §2.3 enumerates (a)-(k) in worktree | same grep against `.worktrees/feat-one-shot-3708/plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | (a)-(k) listed. Both files in lockstep. |
| Sentry NOT in either DPD file's §4.2 | `grep -nE 'Sentry' <both DPD files>` | Zero matches in canonical; zero matches in Eleventy mirror. New row addition required for §(l) cross-reference symmetry. |
| PA8 carries the source-of-truth wording | `grep -nE 'PA8\|Hetzner\|pino\|Sentry\|userIdHash' knowledge-base/legal/article-30-register.md` | Full PA8 §(c)/§(d)/§(e)/§(f) wording present at lines 157-163. Mirror target stable. |
| `hr-gdpr-gate-on-regulated-data-surfaces` rule active | `grep -nE '\[id: hr-gdpr-gate-on-regulated-data-surfaces\]' AGENTS.core.md` | Active at line 31. Cited correctly. |
| `hr-weigh-every-decision-against-target-user-impact` rule active | same grep | Active at line 29. Cited correctly. |
| `wg-after-merging-a-pr-that-adds-or-modifies` rule active | same grep | Active at line 52. Cited correctly. |
| gdpr-gate canonical regex does NOT match `docs/legal/**` | `grep -nA 5 'Path globs (canonical)' plugins/soleur/skills/gdpr-gate/SKILL.md` | Regex: `^(apps/web-platform/supabase/migrations/\|apps/web-platform/lib/auth/\|apps/web-platform/server/.*auth.*\.(ts\|tsx\|js)\|apps/web-platform/app/api/.*\.(ts\|tsx)$\|.*\.sql$)`. `docs/legal/` is not in the regex; gdpr-gate is NOT auto-fired. Plan corrected to manual invocation. |
| PR #3701 is MERGED | `gh pr view 3701 --json title,state` | `{"state":"MERGED","title":"feat(observability): pino formatters.log() pseudonymises userId at logger boundary (PR-A of #3698)"}` |
| PR #3731 is MERGED | `gh pr view 3731 --json title,state` | `{"state":"MERGED","title":"feat(observability): symmetric Sentry userId pseudonymisation (PR-B of #3698)"}` |
| PR #3751 is MERGED | `gh pr view 3751 --json title,state` | `{"state":"MERGED","title":"feat(ops): operator hash-user-id CLI + PA8 §(f) Hetzner retention pin"}` |
| #3696 / #3754 are issues (not PRs) | `gh pr view 3696` / `gh pr view 3754` | Both return `Could not resolve to a PullRequest`. Confirmed as issues via `gh issue view`: #3696 CLOSED ("pseudonymize userId in lib/client-observability.ts"); #3754 OPEN ("PA8 §(f) Hetzner pino observed-volume measurement"). Frontmatter split into `related_issues` + `related_prs`. |
| GitHub labels for AC13 / PR labels exist | `gh label list --limit 200 \| grep -E 'priority/p3-low\|type/security\|domain/legal\|chore'` | All four exist. `priority/p3-low`, `type/security`, `deferred-scope-out` already on issue #3708. |
| Blanket "phone home" / "no telemetry" statements are Plugin-scoped | `grep -nE 'phone home\|no telemetry' docs/legal/*.md plugins/soleur/docs/pages/legal/*.md` | Hits in `privacy-policy.md:39` + mirror line 48 — explicit "The **Plugin** does not phone home" (local CLI scope). No contradiction with Web Platform-scoped §(l). |
| §7.2 "Platform Breaches" already covers breach-notification timing | `awk '/^### 7\.2/,/^---$/' docs/legal/data-protection-disclosure.md` | Already covers Art. 33 72-hour clock + notification channel (GitHub repo + email). §(l) cross-references §7.2 instead of duplicating. |
| ADR-029 invariants relevant to disclosure | Read `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md` | I1 (rename-not-redact), I5 (PA8 §(c) coupling — extends to DPD §(l) via this PR), I10 (two-primitive separation — only `hashUserId` primitive needs DPD surfacing). |
