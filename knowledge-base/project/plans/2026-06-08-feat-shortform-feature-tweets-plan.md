---
feature: shortform-feature-tweets
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
status: draft
issue: 5021
date: 2026-06-08
branch: feat-shortform-feature-tweets
pr: 5017
brainstorm: knowledge-base/project/brainstorms/2026-06-08-shortform-feature-tweets-brainstorm.md
spec: knowledge-base/project/specs/feat-shortform-feature-tweets/spec.md
---

# Plan — Short-Form Feature Tweets from Shipped PRs ✨

## Overview

Add a thin `soleur:feature-tweet` skill that converts a feature **just shipped to production**
(a merged PR, verified live) into a **draft** short-form X post — a single tweet or a ≤3-tweet
thread — written to the existing `knowledge-base/marketing/distribution-content/*.md` format and
drained by the existing `scripts/content-publisher.sh` cron. No new publishing path. The skill is
invoked by `/soleur:postmerge` **after its Phase-3 production-health check succeeds** (only tweet
what actually deployed), and is runnable standalone (`/soleur:feature-tweet #<pr>`) as a catch-up path.

The brand-critical floor is a **deterministic, fail-closed eligibility filter** (`scripts/lib/tweet-eligibility.sh`)
that excludes security/infra/internal/unlabeled PRs *before* any draft is generated, so a forbidden PR
never reaches the operator's approval queue. Tweet copy is generated against the existing
`brand-guide.md` `### X/Twitter` voice spec (sanitized to user-facing benefit only), and the assembled
draft is validated by a **skill-owned structural check** (required frontmatter fields + `## X/Twitter
Thread` heading) AND `scripts/lint-distribution-content.sh` (Liquid markers). Nothing reaches X without
the operator flipping `status: draft → scheduled`.

The only genuinely net-new code is (1) the eligibility filter script + its test, (2) the
generation/draft-write skill, (3) a postmerge hook, (4) a brand-guide ship-tweet voice sub-section,
(5) a count-assertion test on the existing tweet extractor, and (6) a stale-draft flag in campaign-calendar.

## Research Reconciliation — Spec vs. Codebase

All claims below were verified by direct read/grep on `feat-shortform-feature-tweets` (today).

| Spec / brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "Extract changelog's gh-PR logic into shared `scripts/lib/recent-merged-prs.sh`." | `changelog/SKILL.md` is **prose-only** (L26) — no script to extract. postmerge passes a **known PR number** ⇒ no time-window scan needed. | **Refine:** build the deterministic **eligibility filter** instead. **Defer** `recent-merged-prs.sh` + changelog refactor + batch mode (follow-up issue). |
| Default channels `x, bluesky`. | `content-publisher.sh` `channel_to_section` (L178-188) requires **one body section per channel**; `bluesky` with no `## Bluesky` section extracts empty. | **v1 = `channels: x`** (single `## X/Twitter Thread`). Bluesky fast-follow (deferred issue). |
| New skill `feature-tweet` with a `description:`. | Cumulative description budget is **at cap**: `SKILL_DESCRIPTION_WORD_BUDGET = 1984`, current = **1984 (zero headroom)** (`components.test.ts:15,147`). Second gate: per-skill **1024-char** limit (`components.test.ts:16,167`). | **Primary: bump the constant** by the new description's word count with a `// #5021` justification comment (precedent #4742) — zero-risk, no unrelated-skill edits. Trim of `trigger-cron`/`schedule` is the documented fallback. New description must clear BOTH the cumulative word gate AND the 1024-char gate. **DHH F5 escalation filed as a follow-up issue** (zero-headroom monolith smell). |
| Eligibility reads changed files via `gh pr view --json files`. | `--json files` can **paginate/truncate** on large PRs → a deny-path file beyond the page → **fail-OPEN** hole inside a fail-closed filter. postmerge itself uses `gh pr diff --name-only` (SKILL.md:215,250) which does not truncate the same way. | **Use `gh pr diff <n> --name-only`** as the deny-path source (align with postmerge). |
| postmerge has a hook point + a health signal. | postmerge has no content hook (grep clean). Phase 3 (L75-97) curls health: success branch L91 ("Record the response and proceed"), warn branch L93 ("no URL configured → warn and proceed"). Existing phases 3.5/3.6/3.7 run after. The "recorded response" is **prose**, not a shell variable. | Introduce explicit `HEALTH_VERIFIED=true/false` set in **both** Phase-3 branches; insert the tweet phase **after Phase 3.7**, gated on `HEALTH_VERIFIED=true`. |
| Lint gate validates the draft. | `lint-distribution-content.sh` (full file) checks **only** unrendered Liquid markers — it validates **no** frontmatter field or `## X/Twitter Thread` heading. | **Add a skill-owned structural assertion** (required fields + heading + non-empty title) that aborts before write; lint remains the Liquid-marker gate only. |
| Stale drafts are handled by the publisher. | `content-publisher.sh:800` skips `status != scheduled` before the stale-sweep at L804-808 — so a `draft` **never ages out, never alerts**. | Add a draft-age signal: postmerge report surfaces the draft path + flip instruction in-session; campaign-calendar flags `draft` files older than N days as a distinct "Stale Draft" group. |
| Voice from `brand-guide.md`. | `brand-guide.md` has `## Voice` (L51), `### X/Twitter` (L295, full spec), `### Audience Voice Profiles` (L98), `### Value Proposition Framings` (L122). | Generation follows `### X/Twitter` verbatim; add `#### Ship Tweets` cross-referencing the two profiles. (Voice guidance only — sanitization is **enforced** by the generation prompt + human gate, not by the brand-guide section.) |

## User-Brand Impact

_(Carried forward from brainstorm Phase 0.1 — `USER_BRAND_CRITICAL=true`.)_

- **If this lands broken, the user experiences:** a public tweet on @soleur_ai that is off-brand,
  inaccurate, hypes a feature that didn't ship, or — worst case — **amplifies a security fix /
  unannounced internal work to a non-watching audience**, collapsing patch-adoption windows or tipping competitors.
- **If this leaks, the user's data/workflow is exposed via:** generated copy lifting implementation
  detail from a diff, a contributor's name (personal data, no marketing consent), or a customer name
  from a PR title (confidentiality/NDA).
- **Brand-survival threshold:** `single-user incident`. → `requires_cpo_signoff: true` (CPO signed off at
  brainstorm Phase 0.5; carried forward). `user-impact-reviewer` runs at PR-review time.

**Mandatory guardrails (CLO verdict — all required):**
1. **Fail-closed eligibility filter** (deterministic script): require a `feat(` (conventional-commit
   feature) PR **title** AND the `app:web-platform` label; deny labels `type/security`/
   `security/leak-suspected`/`infra-drift`/`no-auto-ship`; deny path globs (auth, migrations, secrets,
   CI/infra). **Deny-checks short-circuit to excluded REGARDLESS of the allow-set.**
   Missing/empty/`gh`-error/truncation-risk ⇒ excluded.
   _**Label reconciliation (#5021, verified live at /work):** the plan was authored against
   `user-facing`+`type/feature` allow labels and `security`/`infra`/`internal`/`dark-launch` deny
   labels — none of which this repo applies to PRs (they are issue-triage labels or do not exist). The
   real merge-time signals are a `feat(` title + `app:web-platform`; the live deny mappings are the
   labels listed above. Operator-approved during /work._
2. **Human approval gate:** files written `status: draft`; operator flips to `scheduled`. No straight-through post. **This is an explicit, owned operator step** (see Post-merge AC).
3. **Content sanitization** (enforced in the generation prompt): user-facing benefit only — no
   diff/implementation detail, no contributor PII/author attribution, no customer names (explicit customer-name/NDA scan).
4. **Draft-only posture** (clears X automated-posting ToS; the existing publisher performs the human-approved post).

## Implementation Phases

### Phase 1 — Eligibility filter (the brand-critical floor)
Create `scripts/lib/tweet-eligibility.sh <pr-number>`. Read labels+title via `gh pr view <n> --json
labels,title,url` and changed paths via `gh pr diff <n> --name-only` (non-truncating; postmerge's
approach). Return exit 0 + `eligible` **only when ALL hold**: title matches `^feat(` (also `feat:`/
`feat!`) AND carries the `app:web-platform` label; carries **none** of the deny labels (`type/security`,
`security/leak-suspected`, `infra-drift`, `no-auto-ship`); touches **no** deny-path glob. **Deny
evaluation short-circuits to `excluded` regardless of the allow-set** (a `feat(`+`app:web-platform`+
`type/security` PR is excluded). Any other state (missing labels, empty fields, `gh` error) ⇒ exit 1 +
`excluded: <reason>` (fail-closed), read-only, no network write. Write
`scripts/lib/tweet-eligibility.test.sh` (`.test.sh` convention) covering: eligible feature PR; each
deny-label alone; each deny-path alone; **collision: feat(+app:web-platform+type/security → excluded**;
**collision: feat(+app:web-platform + touches `**/migrations/**` → excluded**; unlabeled → excluded;
non-`feat(` title → excluded; `gh`-error → excluded.

### Phase 2 — `feature-tweet` skill
Create `plugins/soleur/skills/feature-tweet/SKILL.md`. Flow:
1. Parse `#<pr>` (or `--headless #<pr>`).
2. **Idempotency:** if a `distribution-content/*.md` already has `pr_reference: "#<n>"`, no-op with a message (don't overwrite an operator-edited draft).
3. Run `tweet-eligibility.sh`; **if excluded, exit silently with the reason** (no draft).
4. If eligible, fetch PR title/body; generate a single tweet or ≤3-tweet **numbered** thread (`2/`,`3/`)
   per `brand-guide.md` `### X/Twitter` + `#### Ship Tweets`, applying sanitization (benefit-only, no
   diff/PII/customer names, "no naked numbers"); read author identity from `site.json` `author.name` (never infer).
5. Write `distribution-content/<YYYY-MM-DD>-<slug>.md` with frontmatter (`title`, `type: feature-launch`,
   `publish_date: ""`, `channels: x`, `status: draft`, `pr_reference: "#<n>"`, `issue_reference` if present;
   `blog_url` deliberately omitted — a ship tweet has no blog) and a `## X/Twitter Thread` section. Include
   a top comment: `<!-- To publish: set BOTH publish_date AND status: scheduled -->`.
6. **Structural assertion (skill-owned, not lint):** grep the assembled file for a non-empty `title`,
   `status: draft`, `channels: x`, and a `## X/Twitter Thread` heading; abort (non-zero, no file left) on any miss.
7. Run `scripts/lint-distribution-content.sh <file>` (Liquid markers); abort on non-zero.
Headless mode never posts.

### Phase 3 — postmerge hook (after Phase 3.7, green-gated)
Edit `plugins/soleur/skills/postmerge/SKILL.md`:
- In Phase 3, set `HEALTH_VERIFIED=true` on the health-success branch (L91) and `HEALTH_VERIFIED=false`
  on the no-URL/unhealthy branch (L93).
- Add **Phase 3.8 — Feature-Tweet Draft** (after the existing 3.7): run `tweet-eligibility.sh #<merged-pr>`
  first. If eligible AND `HEALTH_VERIFIED=true` → invoke `feature-tweet #<merged-pr>` and surface the draft
  path + "set publish_date + status: scheduled to publish" in the Phase 7 report. If eligible AND
  `HEALTH_VERIFIED=false` → **print a catch-up instruction** ("eligible PR #N: no verified-live signal, no
  draft — run `/soleur:feature-tweet #N` after confirming deploy") rather than silently no-op'ing. If
  ineligible → silent no-op.
- **Multi-PR contract (explicit v1):** one tweet per eligible PR via postmerge's single bound PR number;
  batching is deferred (#2). If a deploy bundled multiple PRs, only the bound PR is drafted; note in the
  Phase 7 report that other eligible PRs need the standalone catch-up path. `/soleur:merge-pr`-only flows
  bypass this hook by design — standalone `/soleur:feature-tweet #N` is the recovery.

### Phase 4 — brand-guide ship-tweet voice
Edit `knowledge-base/marketing/brand-guide.md`: add `#### Ship Tweets (feature-launch)` under `### X/Twitter`
— ship-tweet shape (single tweet or ≤3-tweet thread, present-tense "just shipped X"), lead with the
build-in-public peer voice (cross-ref `### Audience Voice Profiles`), land one concrete user-facing benefit
for buyers (cross-ref `### Value Proposition Framings`), restate benefit-not-implementation. This is **voice
guidance**; sanitization is enforced in the Phase-2 generation prompt + human gate.

### Phase 5 — extractor count-assertion test
Edit `test/content-publisher.test.ts`: assert a feature-tweet-shaped file extracts the authored count
(1-tweet hook-only → 1; 3-tweet numbered → 3), guarding the silent-collapse class (#2496).

### Phase 6 — stale-draft visibility
Edit `plugins/soleur/skills/campaign-calendar/SKILL.md`: classify `status: draft` files older than N days
(default 7) into a distinct "Stale Draft — needs approval" group, sorted oldest-first. Closes the
strand-forever gap (the publisher's stale-sweep never touches `draft`).

## Files to Create
- `scripts/lib/tweet-eligibility.sh` — deterministic fail-closed filter.
- `scripts/lib/tweet-eligibility.test.sh` — filter tests incl. the two collision cases.
- `plugins/soleur/skills/feature-tweet/SKILL.md` — the skill (description ≤25 words, ≤1024 chars).

## Files to Edit
- `plugins/soleur/skills/postmerge/SKILL.md` — `HEALTH_VERIFIED` flag + Phase 3.8 (after 3.7).
- `knowledge-base/marketing/brand-guide.md` — `#### Ship Tweets` under `### X/Twitter`.
- `test/content-publisher.test.ts` — extractor count-assertion.
- `plugins/soleur/skills/campaign-calendar/SKILL.md` — stale-draft group.
- `plugins/soleur/test/components.test.ts` — **bump `SKILL_DESCRIPTION_WORD_BUDGET` by the new description's
  word count** with a `// #5021 feature-tweet skill` comment (primary; trim of `trigger-cron`/`schedule` is the fallback).

## Acceptance Criteria

### Pre-merge (PR)
- [x] `tweet-eligibility.sh` returns `excluded` (exit 1) for: a `type/security` PR; an `infra-drift` PR;
      a `no-auto-ship` PR; an unlabeled PR; a non-`feat(` (e.g. `fix(`) PR; a PR touching `**/migrations/**`;
      **a `feat(`+`app:web-platform`+`type/security` PR**; **a `feat(`+`app:web-platform` PR that also
      touches `**/migrations/**`**; and on `gh` error. _(live-label reconciliation #5021.)_
- [x] It returns `eligible` (exit 0) for a `feat(`-titled, `app:web-platform`-labelled PR touching only app UI paths.
- [x] `feature-tweet` on an excluded PR writes **no** file and prints the reason.
- [x] `feature-tweet` on an eligible PR writes a draft with `status: draft`, `channels: x`, `pr_reference`,
      and a `## X/Twitter Thread` section; the **skill's structural assertion** passes and `lint-distribution-content.sh` exits 0.
- [x] `feature-tweet` on a PR that already has a draft (`pr_reference` match) no-ops without overwriting.
- [x] A structurally-incomplete draft (missing `## X/Twitter Thread` or `channels`) is **rejected by the
      skill's structural assertion** (proves the gate is not the Liquid linter).
- [x] `test/content-publisher.test.ts` count-assertion passes (1→1, 3→3).
- [x] postmerge sets `HEALTH_VERIFIED` in both Phase-3 branches; Phase 3.8 invokes `feature-tweet` only
      when `HEALTH_VERIFIED=true`, and prints the catch-up instruction when eligible-but-`false`.
- [x] `brand-guide.md` contains `#### Ship Tweets` under `### X/Twitter` referencing the two voice profiles.
- [x] `components.test.ts` is green on BOTH the cumulative word budget AND the 1024-char per-skill limit.
- [x] campaign-calendar surfaces `draft` files older than N days as a "Stale Draft" group.
- [x] Sanitization (human review of the generation prompt + one sample draft): no contributor names,
      customer names, or diff/implementation detail. _(Human gate — not automated coverage.)_

### Post-merge (operator) — explicit owned step
- [ ] **Operator approval gate (the brand-critical human step):** for the first eligible feature shipped
      through `/soleur:postmerge`, the operator reviews the surfaced draft, then sets **both** `publish_date`
      **and** `status: scheduled` (the `publish_date: ""`+`draft` parked state is intentionally skipped by
      `content-publisher.sh:788`; setting only one field leaves it parked). The existing cron then publishes on date.
      _Automation: not feasible — this is the human judgment gate the threshold requires; it cannot be auto-approved._

## Domain Review

**Domains relevant:** Marketing, Product, Engineering, Legal _(carried forward from brainstorm `## Domain Assessments`)._

### Marketing (CMO) — reviewed (carry-forward)
Right lever — fixes cadence by converting a merged PR into a post. Reuse classifier + existing publisher; net-new is a generator. Ship-tweet voice = present-tense, first-person, concrete benefit.
### Product (CPO) — reviewed (carry-forward; sign-off recorded)
Integration gap, not greenfield. Thin generator, draft-gated, not auto-on-every-merge.
### Engineering (CTO) — reviewed (carry-forward)
Reuse is cheapest correct path. Emit canonical numbered format. Trigger on postmerge gated on the health check.
### Legal (CLO) — reviewed (carry-forward)
"Merged to prod" ≠ "safe to announce". Fail-closed exclusion + human approval + benefit-only sanitization all required; draft-only clears ToS.
### Product/UX Gate
**Tier:** none. No UI surface (skill prose, shell scripts, markdown content, tests — no `components/**`, `app/**/page.tsx`). No wireframes. **Pencil available:** N/A.

## Observability

```yaml
liveness_signal:
  what: draft file created after an eligible green ship (creation signal) AND a draft-age signal (campaign-calendar "Stale Draft" group flags drafts > N days un-approved); publish-time liveness owned by the existing content-publisher cron + its Sentry monitor
  cadence: per eligible merged PR (event-driven via postmerge); draft-age scanned by campaign-calendar
  alert_target: existing content-publisher Sentry cron monitor (publish stage); stale-draft group surfaced in campaign-calendar + postmerge Phase 7 report (creation/approval stage)
  configured_in: scripts/content-publisher.sh + cron-content-publisher (publish); campaign-calendar (draft-age); postmerge Phase 7 report (in-session surfacing)
error_reporting:
  destination: skill output (operator-facing) + non-zero exit from tweet-eligibility.sh / structural assertion / lint-distribution-content.sh; publish-stage errors mirror to Sentry via the existing publisher
  fail_loud: true — eligibility, structural assertion, and lint all exit non-zero; the skill aborts the draft on any failure
failure_modes:
  - mode: silent thread collapse (3 tweets posted as 1)
    detection: test/content-publisher.test.ts count-assertion
    alert_route: CI test failure
  - mode: forbidden PR (security/infra/internal) reaches draft queue
    detection: tweet-eligibility.sh fail-closed default + deny-short-circuit + .test.sh collision cases
    alert_route: CI test failure; runtime = skill prints "excluded: <reason>", writes nothing
  - mode: structurally-broken draft passes lint and dies silently at publish
    detection: skill-owned structural assertion (required fields + heading) before write
    alert_route: skill abort (non-zero) before the file is finalized
  - mode: draft stranded un-approved forever (cadence miss)
    detection: campaign-calendar stale-draft group (> N days)
    alert_route: campaign-calendar report; postmerge Phase 7 in-session surfacing
  - mode: gh file-list truncation hides a deny-path (fail-open)
    detection: use gh pr diff --name-only (non-truncating) instead of --json files
    alert_route: design-level (no truncation), verified at /work Phase 0
logs:
  where: skill stdout (operator session) + the draft file as durable artifact; publish logs in the existing publisher
  retention: git history for content files; session transcript for skill runs
discoverability_test:
  command: "bash scripts/lib/tweet-eligibility.sh <a-known-security-labelled-PR#>; echo $?   # expect non-zero + 'excluded'"
  expected_output: "exit 1 with 'excluded: <security reason>' — no ssh required"
```

## Infrastructure (IaC)

N/A — no new server, secret, vendor account, DNS, cron, or persistent runtime process. X posting
credentials and the publisher cron already exist; this feature only writes a markdown file the existing
pipeline drains. (Phase 2.8 scan: no SSH/systemd/doppler-set/dashboard wording.)

## Open Code-Review Overlap

None. Queried 63 open `code-review` issues against every planned file path — zero matches.

## Test Scenarios
1. Eligibility (Phase-1 test): each deny label, each deny path, **both collision cases**, unlabeled, gh-error, happy path.
2. Generation: eligible PR → draft with correct frontmatter + `## X/Twitter Thread`; structural assertion + lint clean.
3. Structural-reject: malformed draft (missing heading/channels) → skill aborts.
4. Idempotency: re-run on a PR with an existing draft → no-op.
5. Extraction: 1-tweet and 3-tweet drafts extract the right count.
6. Sanitization (manual): PR title with a customer name → copy omits it.
7. postmerge integration (manual): healthy deploy of eligible PR → draft + surfaced path; no-URL → catch-up instruction, no draft.

## Risks & Mitigations
- **Approval fatigue.** → Exclusion filter removes forbidden PRs before drafting (floor-before-ceiling).
- **Stranded draft = silent cadence miss.** → campaign-calendar stale-draft group + postmerge in-session surfacing.
- **`gh` file-list truncation → fail-open.** → Use `gh pr diff --name-only` (non-truncating).
- **`extract_tweets` count drift.** → Count-assertion test + canonical numbered format.
- **Budget bump grows always-loaded context.** → Bump is minimal (one short description); DHH F5 monolith issue filed separately.
- **Deferred Bluesky/changelog-helper orphan scope.** → Tracking issues at plan exit.

## Sharp Edges
- Empty `## User-Brand Impact` / `TBD` fails `deepen-plan` Phase 4.6 — this plan's section is filled.
- The postmerge hook MUST gate on `HEALTH_VERIFIED=true` (set explicitly in both Phase-3 branches), not
  on "reached this line" — the warn-and-proceed branch also falls through to "proceed."
- `eligibility.sh` MUST fail closed on `gh` error/empty labels AND deny-check short-circuit regardless of
  allow-labels — an "allow on uncertainty" or "allow-label-wins" default re-introduces the forbidden-PR leak.
- The Liquid linter validates **no** frontmatter/section structure — the skill's own structural assertion
  is the field/heading gate. Do not lean on lint for shape.
- The publisher's stale-sweep never touches `status: draft` — un-approved drafts strand silently without the campaign-calendar flag.
- `channels: bluesky` without a `## Bluesky` section is incomplete; v1 is `x`-only by design.
- Trim `trigger-cron`/`schedule` filler, never `social-distribute` (its platform enumeration is the routing signal) — but bump-the-constant is the primary, lower-risk path.

## Alternative Approaches Considered
| Approach | Why not |
|---|---|
| Extend `changelog` to emit X drafts | Overloads the internal-Discord-batch skill; CPO/CMO rejected. |
| Inline generation in `/soleur:postmerge` | Buries brand-critical exclusion/sanitization; not standalone-runnable; not independently testable. |
| `recent-merged-prs.sh` shared helper | postmerge passes a known PR#; no scan needed for v1. Deferred (changelog is prose-only). |
| `channels: x, bluesky` v1 | Publisher needs a section per channel. Bluesky deferred. |
| Auto-post (no draft gate) | Fails CLO threshold + X automated-posting ToS. |
| Trim siblings as the primary budget fix | Shuffles description-budget debt onto unrelated skills; bump the constant instead (precedent #4742). |

## Deferred items (file tracking issues at plan exit)
1. **Bluesky ship-tweet channel** — `## Bluesky` generation + `channels: x, bluesky`. Re-eval: after v1 X path validated.
2. **`recent-merged-prs.sh` + changelog refactor + batch/scan mode.** Re-eval: when a weekly batch cadence is wanted.
3. **Skill-description budget mechanism (DHH F5).** 70+ skills at a single 1984-word cap with zero headroom; every new skill pays a horse-trading tax. Re-eval: per-skill allocation vs catalog pruning. Label `deferred-scope-out`.
