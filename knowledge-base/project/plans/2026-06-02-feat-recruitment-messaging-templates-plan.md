---
title: "feat: Draft recruitment messaging templates per channel (M4)"
type: feature
issue: 1445
roadmap: Pre-Phase 4 Marketing Positioning Gate (M4)
lane: single-domain
owner: CMO
requires_cpo_signoff: false
brand_survival_threshold: none
created: 2026-06-02
---

# ✨ feat: Draft recruitment messaging templates per channel (M4)

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Channel strategy (per-channel research insights), Acceptance Criteria (AC5 verify command tightened), Risks.
**Research mode:** Inline (Task subagent spawning unavailable in this environment — deepening performed by direct source reads of brand-guide channel notes, marketing-strategy channel priority, and the two relevant learnings; deepen-plan hard gates 4.6/4.7/4.8 run mechanically and all pass).

### Key Improvements

1. Per-channel research insights grounded in the brand-guide channel notes (Discord/GitHub/X/Twitter/IndieHackers) — concrete tone, format, and length constraints per channel.
2. AC5 verify command made unambiguous (names the real file path; bare-count regex no longer matches `+`-suffixed soft floors as false positives).
3. The proof-point/citation discipline (learning 2026-04-22) is wired as both an AC and a Sharp Edge so /work cannot ship an unverified external citation.

### Deepen-plan gate results

- **4.6 User-Brand Impact:** PASS — section present, threshold `none`, scope-out reason bullet present, Files-to-Edit do not match the sensitive-path regex.
- **4.7 Observability:** SKIP (correct) — pure-docs plan, all Files-to-Edit under `knowledge-base/`.
- **4.8 PAT-shaped variable:** PASS — no PAT-shaped vars/literals.
- **4.4 / 4.5:** No precedent-diff target (no SQL/lock/atomic-write/cron), no network-outage trigger keywords → skip.

## Overview

Issue [#1445](https://github.com/jikig-ai/soleur/issues/1445) (roadmap row M4) calls for **recruitment messaging templates, one per channel**, to support Phase 4 founder recruitment. The deliverable is a single content artifact in `knowledge-base/marketing/` — channel-specific copy that the founder sends/posts to recruit 10 solo founders for problem interviews and guided onboarding.

This is the recruitment-phase successor to the existing **problem-interview** outreach in `knowledge-base/marketing/validation-outreach-template.md`. That document recruits for *15-minute research calls, no pitch*. M4 recruits for *Phase 4 participation* — onboarding onto the platform and 2-week unassisted usage. Same audience, different ask. The new file complements (does not replace) the validation template.

**The load-bearing constraint** (from the issue and roadmap line 342): **at least 3 of 10 founders must NOT be current Claude Code users.** Recruiting entirely from the Claude Code ecosystem validates only the plugin-to-cloud migration path, not the cloud-platform value proposition from cold. Therefore the templates must split into two voice registers — the brand guide already defines these as **Technical register** (CC-native, HN/GitHub/Discord) and **General register** (non-technical, web/LinkedIn/X). Channels that reach non-CC founders (X/Twitter solopreneur network, direct network outreach, parts of IndieHackers) must lead with the **General register** and the pain-point / memory-first framings, never with CC-specific vocabulary ("plugin," "Claude Code," "skills," "agents" un-defined).

**Channels to cover** (verbatim from issue body + roadmap line 340):

1. Claude Code Discord
2. GitHub (developers with business-operations repos)
3. IndieHackers
4. X/Twitter solopreneur network
5. Direct network outreach

**Gate:** This work is itself a gate item (M4). No recruitment outreach fires until M1-M4 (and the broader M12-M63 + Multi-User gate) complete. M1 (#1004), M2 (#1129) are Done; M3 (#1051) is the sibling in-progress item. This plan produces the artifact; it does NOT send any outreach.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality | Plan response |
|---|---|---|
| Issue is open, M4 not started | `gh issue view 1445` → OPEN; roadmap line 240 → "Not started" | Premise holds; proceed as net-new artifact |
| 5 channels named in issue | Roadmap line 340 lists the identical 5 channels | Cover all 5; no divergence |
| 3/10 non-CC constraint | Roadmap line 342 states the constraint with rationale | Promote to a structural requirement (dual register), not a footnote |
| "Recruitment templates" deliverable | Existing `validation-outreach-template.md` is *problem-interview* outreach (different ask) | New, complementary file — cross-link both |
| Brand voice for non-CC founders | brand-guide.md "General register" + "Audience Voice Profiles" + "Value Proposition Framings" (pain-point won 7/10 synthetic personas) | Adopt brand-guide registers verbatim as the register-split spine |

No stale premises. Premise Validation: issue OPEN, roadmap rows + channel list + mix constraint all confirmed against `knowledge-base/product/roadmap.md` and the live issue. No cited file/symbol/migration to falsify. No external premises beyond the roadmap (verified).

## Goals

1. Produce one recruitment message per channel (5 channels), each in the correct brand-guide register and tone for that channel.
2. Make the 3/10 non-CC constraint operable: every General-register template is jargon-free and leads with pain-point or memory-first framing; a short "Channel → register → non-CC suitability" matrix tells the founder which channels feed the non-CC quota.
3. Reuse the brand guide as the single source of truth for voice, framings, proof points, and prohibited terms — no new positioning invented.
4. Keep all proof-point claims (PR count, agent/skill counts, time saved, price) on brand-guide *soft floors* or verified values — no fabricated stats or citations.
5. Cross-link with `validation-outreach-template.md` so the two outreach assets are discoverable as a pair.

## Non-Goals

- **Sending any outreach.** This is artifact creation only; the gate forbids outreach until M1-M63 complete.
- **Replacing** `validation-outreach-template.md` (problem-interview outreach stays as-is).
- **Pricing commitments.** The $49/month figure appears in the roadmap exit criteria; templates reference willingness-to-pay framing only where the brand guide / pricing-strategy already permit, and never quote a committed price as a CTA (pricing is still under validation — marketing-strategy.md "What This Strategy Does NOT Include" #5).
- **New marketing channels** beyond the 5 named (no Reddit/HN recruitment templates — HN explicitly rejects product/recruitment posts per brand-guide HN notes; if a 6th channel is wanted, file a follow-up).
- **Automation / scheduling** of outreach (no workflow, no cron). Pure markdown.

## User-Brand Impact

**If this lands broken, the user experiences:** A recruited solo founder reads outreach copy that says "plugin" or "Claude Code" to a non-CC audience, or quotes a fabricated stat (e.g., a wrong PR count or an unverifiable external citation). First-touch trust fails: the founder either bounces (off-positioning) or, worse, accepts and then finds the product does not match the over-claimed message at onboarding.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this artifact contains no user data, credentials, schemas, or runtime code. It is internal marketing copy committed to the knowledge base.

**Brand-survival threshold:** none.

> threshold: none, reason: This is an internal marketing-copy markdown file with no PII, no schema, no auth, no API route, and no runtime code path — it touches no sensitive surface per preflight Check 6 canonical regex.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — File exists with correct frontmatter.** `knowledge-base/marketing/recruitment-messaging-templates.md` exists with YAML frontmatter matching the sibling pattern (`last_updated`, `last_reviewed`, `review_cadence: quarterly`, `owner: CMO`, `depends_on: [knowledge-base/marketing/brand-guide.md, knowledge-base/marketing/marketing-strategy.md, knowledge-base/product/business-validation.md]`). Verify: `head -12 knowledge-base/marketing/recruitment-messaging-templates.md`.
- [x] **AC2 — All 5 channels present.** The file contains a top-level template section for each of: Claude Code Discord, GitHub, IndieHackers, X/Twitter, Direct network. Verify: `grep -cE '^## (Channel|Template):' knowledge-base/marketing/recruitment-messaging-templates.md` returns ≥ 5, AND each of the 5 channel names appears as a heading: `for c in "Claude Code Discord" "GitHub" "IndieHackers" "X/Twitter" "Direct"; do grep -q "$c" knowledge-base/marketing/recruitment-messaging-templates.md || echo "MISSING: $c"; done` prints nothing.
- [x] **AC3 — Non-CC quota is operable.** The file contains a "Channel → register → non-CC suitability" matrix that marks ≥ 3 channels (X/Twitter, Direct network, IndieHackers-general) as General-register / non-CC-suitable, and the prose states the 3/10 constraint explicitly. Verify: `grep -iq "3 of 10\|3/10\|non-Claude" knowledge-base/marketing/recruitment-messaging-templates.md`.
- [x] **AC4 — Prohibited-term compliance on General-register copy.** No General-register (non-technical) template uses "plugin," "Claude Code," "copilot," "assistant," "AI-powered," "just," "simply," or "terminal-first" in body copy. (Technical-register Discord/GitHub copy MAY reference "Claude Code" since that audience uses it.) Verify per the brand-guide Don'ts list with a scoped grep over the General-register sections (work phase pins the exact command).
- [x] **AC5 — Proof-point claims use soft floors / verified values only.** Agent and skill counts use the "60+" soft-floor form (never an exact hardcoded count — brand-guide line 79); the PR count uses the brand-guide "420+ merged PRs" form or is dropped; no external URL citation is embedded unless it has been WebFetch-verified (per learning `2026-04-22-copywriter-citation-fabrication-needs-webfetch-gate.md`). Verify (substitute the real path for `$F=knowledge-base/marketing/recruitment-messaging-templates.md`): `grep -nE '[0-9]+ (agents|skills|merged PRs)' "$F" | grep -vE '[0-9]+\+ '` returns nothing (every count is `+`-suffixed soft floor, no bare exact count); `grep -oE 'https?://[^ )]+' "$F"` returns zero un-verified marketing-claim URLs (or each is annotated `<!-- verified: YYYY-MM-DD -->`).
- [x] **AC6 — Cross-link to validation template.** The new file links to `validation-outreach-template.md` and explains the difference (problem-interview research vs. Phase 4 recruitment). Verify: `grep -q "validation-outreach-template.md" knowledge-base/marketing/recruitment-messaging-templates.md`.
- [x] **AC7 — No committed price as CTA.** No template uses "$49" (or any dollar figure) as a call-to-action or commitment. Verify: `grep -n '\$[0-9]' knowledge-base/marketing/recruitment-messaging-templates.md` returns nothing, or only appears inside an explicitly-labeled "not a price commitment" willingness-to-pay research note.
- [x] **AC8 — Voice register correctness.** Discord + GitHub templates use Technical register; X/Twitter + Direct network use General register; IndieHackers provides both a technical and a general variant (mixed community). Confirmed by CMO/marketing review (manual read against brand-guide Audience Voice Profiles).
- [x] **AC9 — X/Twitter copy respects the 280-char-per-post rule** and the no-mid-thread-links rule (brand-guide X/Twitter notes). Verify: each tweet block ≤ 280 chars (work phase pins an awk/wc check per tweet block).
- [x] **AC10 — Channel ToS guardrail note present.** The file includes a one-paragraph "Outreach etiquette" note: respect each community's self-promotion rules (Discord/IndieHackers anti-spam), personalize DMs, one message per person, no mass-DM blasts. (Recruitment outreach that reads as spam is a brand-risk vector.)

### Post-merge (operator)

- [x] **AC11 — Roadmap status flip.** After merge, update roadmap M4 (line 240) status from "Not started" to "Done — [#1445]". `Automation: feasible` — handled inline via Edit + `gh issue close 1445` in the ship phase (read-only `gh` + repo file edit, no infra). Use `Ref #1445` in the PR body (not `Closes`) only if closure must follow merge; for a docs-only artifact `Closes #1445` is acceptable since there is no post-merge apply step.

## Implementation Phases

> NEVER CODE during planning. These phases are the /work breakdown.

### Phase 1 — Skeleton + register spine

- Create `knowledge-base/marketing/recruitment-messaging-templates.md` with frontmatter (AC1) and a top section: purpose, relationship to `validation-outreach-template.md` (AC6), the 3/10 non-CC constraint statement (AC3), and the Channel → register → non-CC-suitability matrix.
- Matrix columns: Channel | Brand-guide register | Non-CC-suitable? | Primary framing | Primary CTA.
- Pull register definitions verbatim from `brand-guide.md` "Audience Voice Profiles" and framings from "Value Proposition Framings" (pain-point primary, memory-first variant).

### Phase 2 — Per-channel templates (Technical register)

- **Claude Code Discord:** builder-to-builder, direct, bold (brand-guide Discord notes). May reference Claude Code natively. Ask: join Phase 4, onboard, use 2 weeks. Sparing structural emoji OK.
- **GitHub:** maximum technical precision, no marketing language (brand-guide GitHub notes). Frame as: "developers with business-operations repos" — outreach via issue/discussion engagement or profile DM where appropriate. Grounded in what the platform does.

### Phase 3 — Per-channel templates (General register + mixed)

- **X/Twitter:** General register, declarative, ≤280 chars/post, links in final post only, no mid-thread links (AC9, brand-guide X/Twitter notes). Lead with pain-point ("You're doing 8 jobs") or memory-first framing. A short recruitment DM variant + a public call-for-participants thread variant.
- **Direct network outreach:** General register, warm/personal, 1:1. Highest non-CC yield. Outcome-focused, jargon-free.
- **IndieHackers:** mixed community — provide BOTH a technical-leaning post and a general-leaning post; community-post format (brand-guide / mirror the existing validation-template community-post shape).

### Phase 4 — Guardrails + proof-point pass

- Add the "Outreach etiquette" ToS note (AC10).
- Sweep every proof-point claim to soft floors / verified values (AC5); drop or annotate any external URL.
- Sweep General-register copy for prohibited terms (AC4) and dollar-figure CTAs (AC7).
- Self-review against brand-guide Do's/Don'ts and Audience Voice Profiles (AC8).

### Phase 5 — Cross-references + roadmap wiring

- Cross-link from `validation-outreach-template.md` (and optionally `marketing-strategy.md` Channel Strategy / `campaign-calendar.md`) to the new file so the recruitment asset is discoverable.
- Prepare the post-merge roadmap M4 status flip (AC11).

### Research Insights — per-channel constraints (from brand-guide channel notes)

These are the load-bearing per-channel rules the /work author must encode. All are quoted/derived from `knowledge-base/marketing/brand-guide.md` "Channel Notes" + "Audience Voice Profiles".

**Claude Code Discord (Technical register, CC-native):**
- Tone "casual but retains the boldness… builder-to-builder." Sparing structural emoji (arrows/checkmarks) acceptable; concise — link out instead of walls of text.
- May say "Claude Code," "skills," "agents" un-defined (this audience uses them). This is the one channel where CC vocabulary is on-brand.
- Recruitment ask: invite to Phase 4 (onboard + 2-week unassisted usage), not just a research call.

**GitHub (Technical register):**
- "Maximum technical precision. No marketing language." Targets "developers with business-operations repos" — engage via the developer's own repos/discussions, then a grounded DM. Frame around what the platform does, not positioning.
- "Soleur" always capitalized in prose.

**X/Twitter (General register, primary non-CC channel):**
- ≤280 chars per post, enforced during generation. Links in the FINAL post only; no mid-thread links (kills impressions). No hashtags in body; ≤1 in the final post (#solofounder / #buildinpublic).
- Hook-first: first post must stand alone. No "excited to announce." Lead with pain-point ("You're doing 8 jobs") or memory-first ("The AI that already knows your business").
- Provide two variants: a recruitment DM and a public call-for-participants thread.

**Direct network outreach (General register, highest non-CC yield):**
- Warm, 1:1, personalized. Outcome-focused, jargon-free. This is where the 3/10 non-CC quota is most reliably met — the founder's own network of non-technical builders.

**IndieHackers (mixed community → both registers):**
- Community-post format (mirror the existing `validation-outreach-template.md` community-post shape). Provide a technical-leaning variant and a general-leaning variant.
- IH norms reward transparent build-in-public framing ("revenue: $0, users: 1") over pitch — per marketing-strategy Channel 2 guidance.

**Trust scaffolding (all General-register channels):** include a human-in-the-loop / "starting point, not final answer" phrase — the #1 objection across 8/10 synthetic personas was "what if the output is wrong?" (brand-guide Value Proposition Framings).

## Files to Edit

- `knowledge-base/marketing/validation-outreach-template.md` — add a one-line cross-link to the new recruitment file (sibling-asset discoverability).
- `knowledge-base/product/roadmap.md` — line 240 M4 status flip (post-merge / ship phase).
- `knowledge-base/marketing/marketing-strategy.md` — OPTIONAL: add the recruitment-templates file to "Cascade Documents" / Channel Strategy if it improves discoverability (low-risk, single table row).

## Files to Create

- `knowledge-base/marketing/recruitment-messaging-templates.md` — the deliverable.

(No `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` created → Product/UX Gate mechanical escalation does NOT fire. No code/infra files → Observability gate skips.)

## Open Code-Review Overlap

None. (Queried open `code-review`-labeled issues against the planned file paths — `knowledge-base/marketing/recruitment-messaging-templates.md`, `validation-outreach-template.md`, `roadmap.md`, `marketing-strategy.md` — no open scope-out touches these marketing-copy files. Re-verify at /work time with: `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/r.json` then `jq` per path.)

## Domain Review

**Domains relevant:** Marketing

### Marketing (CMO)

**Status:** reviewed (inline — Task subagent spawning unavailable in this environment; assessment derived directly from the authoritative CMO sources: `brand-guide.md`, `marketing-strategy.md`, `business-validation.md`).

**Assessment:** This is squarely a CMO-owned deliverable (the roadmap row, the issue label `domain/marketing`, and the file owner are all CMO). The marketing-critical decisions:

1. **Register split is the core design choice.** The brand guide already encodes two registers (Technical / General) and three framings (pain-point primary at 7/10 synthetic personas, memory-first variant, CaaS education-heavy secondary). The non-CC quota maps cleanly onto the General register. The plan adopts these verbatim rather than inventing new positioning — correct per marketing-strategy's "every initiative high-leverage, no new positioning."
2. **Channel-tone fidelity matters.** Each channel has distinct brand-guide notes (Discord casual-but-bold, GitHub no-marketing, X 280-char/no-mid-thread-links, HN explicitly off-limits for recruitment). The templates must respect these or they read as off-brand spam.
3. **Trust scaffolding.** brand-guide "Value Proposition Framings" flags the #1 objection (8/10 personas): "What if the output is wrong?" Recruitment copy should include human-in-the-loop / "starting point not final answer" trust language, especially for non-CC founders who can't inspect the code.
4. **Proof-point discipline.** Soft floors only ("60+", "420+ merged PRs"); no fabricated external citations (learning 2026-04-22). No committed price (pricing under validation).
5. **No conversion-optimizer / ux-design-lead needed** — there is no page layout or visual structure, only copy. The CMO recommendation to delegate to those agents (domain-config) fires only "when the assessment involves visual layout or page structure"; it does not here.

**Product/UX Gate:** Not applicable — Product domain NOT relevant. This creates an internal markdown content artifact, not a user-facing page, multi-step flow, or UI component. No `components/**/*.tsx` / `app/**/page.tsx` / `app/**/layout.tsx` in Files to Create → mechanical escalation does not fire. Tier: NONE.

**Brainstorm-recommended specialists:** none (no brainstorm document; plan entered directly).
**Skipped specialists:** none required (copywriter optional — see Sharp Edges; the founder/CMO authors copy directly from the brand guide).

## Test Scenarios

This is a content artifact; "tests" are the AC verification greps (above) plus a manual brand-voice read. No automated test suite applies (`bun test` / vitest cover code, not marketing markdown). The components.test.ts budget check does NOT apply (no SKILL.md description edited).

| Scenario | Check |
|---|---|
| Non-CC founder reads X/Twitter copy | No CC/plugin jargon (AC4); pain-point/memory framing leads |
| Founder picks channels for the non-CC 3/10 quota | Matrix marks ≥3 General-register channels (AC3) |
| Reader clicks an embedded link | Every link is WebFetch-verified or dropped (AC5) |
| Tweet exceeds platform limit | Each tweet block ≤280 chars (AC9) |
| Community moderator sees the post | Etiquette note enforces anti-spam personalization (AC10) |

## Risks & Mitigations

- **Off-positioning to non-CC founders.** *Mitigation:* dual-register split + AC4 prohibited-term sweep scoped to General-register sections.
- **Fabricated stats / dead citation links** (the 2026-04-22 copywriter class). *Mitigation:* AC5 — soft floors only, WebFetch-verify or drop every URL. If copy is delegated to the `copywriter` agent at /work time, fact-checker MUST run as a shipping gate (not advisory).
- **Quoting a price as a commitment** when pricing is unvalidated. *Mitigation:* AC7 — no dollar-figure CTA.
- **Recruitment copy reading as spam** → community bans / brand damage. *Mitigation:* AC10 etiquette note; templates are personalize-then-send, never mass-blast.
- **Drift from `validation-outreach-template.md`** (two outreach assets diverge). *Mitigation:* cross-link both; shared frontmatter `depends_on` the same brand-guide source.

## Sharp Edges

- **This plan's `## User-Brand Impact` threshold is `none`** with the required scope-out reason bullet — it will pass `deepen-plan` Phase 4.6 and preflight Check 6. Do not remove the reason bullet.
- **If /work delegates drafting to the `copywriter` agent**, every embedded URL is unverified until fact-checker confirms (learning `2026-04-22-copywriter-citation-fabrication-needs-webfetch-gate.md`). Prefer authoring directly from the brand guide with zero external citations — recruitment DMs/posts rarely need them. If a citation is genuinely load-bearing (e.g., the Amodei billion-dollar-solo-founder prediction), WebFetch it first and annotate `<!-- verified: YYYY-MM-DD source: <url> -->`.
- **Exact agent/skill counts drift** as components ship. Use the brand-guide "60+" soft floors in prose (brand-guide line 79); never hardcode an exact count in this static file.
- **HN is deliberately excluded** as a recruitment channel — HN readers punish recruitment/marketing posts (brand-guide HN notes). Do not add an HN template; if HN reach is wanted later, it is article-submission, not recruitment outreach (file a separate issue).
- **The Task tool / subagent spawning was unavailable** in this planning environment, so repo-research-analyst, learnings-researcher, and CMO domain-leader Tasks were performed inline by reading the authoritative source files directly (brand-guide, marketing-strategy, business-validation, roadmap, domain-config, and the two relevant learnings). Plan-review (DHH/Kieran/Simplicity) and deepen-plan likewise depend on Task; if they cannot spawn, the one-shot pipeline should note the degraded review depth.

## Research Insights

- **Authoritative sources read:** `knowledge-base/marketing/brand-guide.md` (registers, framings, channel notes, prohibited terms), `knowledge-base/marketing/marketing-strategy.md` (ICP, channel priority, validation imperative), `knowledge-base/marketing/validation-outreach-template.md` (sibling asset, format precedent), `knowledge-base/product/roadmap.md` (M4 row 240, channels 340, mix constraint 342, gate 301).
- **Relevant learnings:** `integration-issues/2026-04-22-copywriter-citation-fabrication-needs-webfetch-gate.md` (citation/stat verification gate → AC5 + Sharp Edge); `2026-03-26-synthetic-user-research-methodology.md` (the pain-point-framing 7/10 finding behind the General-register choice).
- **Brand-guide soft-floor rule** (line 79): "60+ agents / 60+ skills" in prose; live site renders exact counts. Applied to AC5.
- **Premise validation:** issue #1445 OPEN; roadmap M4 "Not started"; 5 channels + 3/10 constraint confirmed against live roadmap. No stale premises.
- **Skill description budget check:** N/A — no `plugins/soleur/skills/*/SKILL.md` `description:` edit is candidate or finalized.
- **GDPR gate (Phase 2.7):** skipped — no schema, migration, auth flow, API route, `.sql`, no LLM processing of operator/user data, threshold `none`, no new distribution surface (internal KB markdown). None of the (a)-(d) expansion triggers fire.
- **IaC gate (Phase 2.8):** skipped — no server, service, cron, vendor account, secret, DNS, or persistent runtime process. Pure docs.
- **Observability gate (Phase 2.9):** skipped — pure-docs plan, no Files-to-Edit under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`.
