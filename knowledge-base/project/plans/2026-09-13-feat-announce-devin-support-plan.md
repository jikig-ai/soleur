---
title: "feat: announce Devin CLI harness support on X/Twitter and Bluesky"
type: feat
date: 2026-09-13
slug: feat-announce-devin-support
branch: feat-announce-devin-support
pr: 8121
domain: marketing
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

## Enhancement Summary

**Deepened on:** 2026-09-13
**Sections enhanced:** Research Insights (premise validation, publisher/parser contract, publish_date decision), Acceptance Criteria (parser-contract ACs), Risks (stale-flip risk)
**Research agents used:** none spawnable — this deepen ran inside a pipeline planning subagent with no Task/agent tool; every gate was executed inline with the mechanical checks the skill prescribes (greps, `gh`, `git ls-tree`, `date`). See `## Deepen-Plan Verification` for the per-gate record.

### Key Improvements

1. Fixed an elided learning citation (`2026-06-12-...` → full filename) so every cited path resolves.
2. Confirmed `publish_date: 2026-09-14` weekday math: 2026-09-13 is Sunday (today's 14:00 UTC cron already fired), 09-15 is the occupied Tuesday slot (grok file), 09-17 would be the next free auto-promotion slot — 09-14 remains the earliest viable and correct choice for a missed announcement.
3. All halt gates (4.6–4.11) evaluated with their prescribed mechanical checks; results recorded in `## Deepen-Plan Verification`.

### New Considerations Discovered

- Credential-skip is survivable: if `X_*`/`BSKY_*` env vars are unset on the cron host, channels skip individually and a `Published nowhere` action-required issue is filed — the file is never lost, only delayed. No plan change needed; noted in Risks.
- `channels:` token parsing splits on commas (`content-promotion.ts` `parseContentFrontmatter`) — `x, bluesky` is the canonical form the precedent uses; do not reformat to a YAML list.

## Overview

> Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed); the spec directory exists but is empty (no spec.md to carry a lane forward).

Create the missed social announcement for the Devin CLI harness support that merged 2026-09-11/2026-09-12 (lead PR #8083 plus follow-ups #8084, #8087, #8088, #8089). The deliverable is one markdown file at `knowledge-base/marketing/distribution-content/2026-09-13-devin-cli-harness-support.md`, modeled on the precedent `2026-09-12-grok-build-plugin-workflow-fidelity.md`, so the daily `cron-content-publisher` (14:00 UTC) picks it up and posts to X/Twitter and Bluesky.

## Research Insights

**Premise Validation (Phase 0.6).** Every cited reference verified live:

- `gh pr view` confirmed all five content PRs MERGED with titles matching the brief: #8083 "feat: add Devin CLI harness support" (2026-09-11), #8084 "fix: add Devin-native plugin manifest and correct install instructions" (2026-09-11), #8087 "fix: expose /soleur:go, /soleur:sync, /soleur:help as Devin slash commands" (2026-09-11), #8088 "feat(devin): add Devin plugin scaffolding parity with Codex/Grok harnesses" (2026-09-12), #8089 "docs: add Devin plugin update instructions and fix stale install command" (2026-09-11). Draft PR #8121 "WIP: feat-announce-devin-support" is OPEN on this branch.
- The precedent file `knowledge-base/marketing/distribution-content/2026-09-12-grok-build-plugin-workflow-fidelity.md` exists on this branch and carries exactly the frontmatter contract named in the brief (`title`, `type: feature-launch`, `publish_date`, `channels: x, bluesky`, `status: scheduled`, `pr_reference`; it also carries `issue_reference`).
- `git ls-tree origin/main` confirms no Devin announcement file exists on main — the announcement is genuinely missed, not duplicated. The only Devin-named file, `soleur-vs-devin.md`, is a `type: pillar` comparison piece already `status: published` (2026-04-21); not an announcement and not a conflict.
- The "Content Publisher publishes files with BOTH publish_date AND status: scheduled" premise is verified against the mechanism: `scripts/content-publisher.sh` main loop skips files missing either field, requires `status == scheduled`, marks `publish_date < today` files `status: stale` (never posts them), and posts only on `publish_date == today`. The cron is `cron-content-publisher` at `0 14 * * *` UTC in `apps/web-platform/server/inngest/functions/cron-content-publisher.ts` (`{ cron: "0 14 * * *" }` plus a `cron/content-publisher.manual-trigger` event). `scheduled-content-publisher.yml` was retired per #4483 — the Inngest cron is the publisher now.
- Mechanism vs ADR corpus: grepped `knowledge-base/engineering/architecture/decisions/` for `distribution-content|publish_date|content-publisher`; the hits (ADR-033 Inngest cron spawn, ADR-054 bot-PR write path, ADR-179 plugin-root anchor) describe the substrate this file rides on — none rejects frontmatter-gated scheduled publishing.

**Publisher/parser contract the file must satisfy (all verified in code, not inferred):**

- Channel→section map (`content-publisher.sh` `channel_to_section`): `x` → `## X/Twitter Thread`, `bluesky` → `## Bluesky`. Declared channels with an empty/missing section are skipped per-channel; all channels skipped files a "Published nowhere" action-required issue and leaves `status: scheduled` (re-fires daily until fixed — a stale-emitting loop).
- Tweet splitting (`extract_tweets`): two authoring formats — labeled (`**Tweet N (...) -- N chars:**`, label dropped) or numbered (hook tweet un-prefixed; tweets 2+ begin `N/ ` on a fresh line, prefix preserved, sequence-enforced). Published precedent (`2026-07-06-agent-audits-its-own-governance-rulesets.md`) uses the numbered form. Per `learnings/bug-fixes/2026-04-17-extract-tweets-numbered-format.md`, a malformed section collapses to a single 1-tweet post — the plan must pin the format in an AC.
- Bluesky: `> 300` chars is truncated to 297 + `...` with only a stderr warning (`content-publisher.sh` `post_bluesky`). Copy must be ≤300 graphemes.
- X: 280 chars/tweet is enforced at authoring per `social-distribute/SKILL.md` ("Character limits are enforced during generation"); the publisher itself does not pre-validate, so a >280 tweet fails at the X API and produces a partial-thread fallback issue. The plan must require a per-tweet char count.
- Liquid/Jinja markers (`{{`, `}}`, `{%`, `%}`) anywhere in the body are rejected twice: lefthook `distribution-content-liquid-guard` at commit (`scripts/lint-distribution-content.sh`) and the publisher's own gate which refuses all channels for the file. The copy must contain none.
- `validate-tweet-draft.sh` (`scripts/lib/`) is the draft-path structural gate (`status: draft` asserted). This file ships `status: scheduled` directly per the brief and the grok precedent — that validator is context, not a gate — but its structural assertions (non-empty title, `x` + `bluesky` tokens, both sections non-empty) are exactly what the ACs should pin.

**publish_date decision (load-bearing).** Now = 2026-09-13 ~15:04 UTC; today's 14:00 UTC cron already ran. A `publish_date: 2026-09-13` file would never publish — next run it is `publish_date < today` → flipped to `status: stale`. Earliest viable: **2026-09-14** (publishes at Monday 14:00 UTC if merged before then). Auto-promotion (`content-promotion.ts`) assigns *drafts* to Tue/Thu slots skipping occupied dates, and 2026-09-15 is occupied by the grok file — but that Tue/Thu rule binds only the draft-promotion path, not a hand-scheduled file; for a missed announcement the honest move is the earliest viable date per `learnings/2026-06-12-brainstorm-verify-capability-claims-against-code-and-decouple-build-from-news-window.md` (news windows decay; ship the honest version now). If merge slips past 2026-09-14 14:00 UTC, the file still must not sit with a past publish_date — /work should verify the date is still `> today` at ship time, or bump it.

**Verified copy claims (each traced to merged code/docs — the plan's fact base):**

- Devin CLI is the **fourth** supported harness, alongside Claude Code, Grok Build, and Codex (PR #8083: `lib/harness.ts` Devin detection/routing, `devin/INSTRUCTIONS.md` tool mappings).
- `/soleur:go`, `/soleur:sync`, `/soleur:help` are exposed as Devin slash commands via `skills/{go,sync,help}/SKILL.md` wrappers (PR #8087).
- Install: `devin plugins install jikig-ai/soleur#plugins/soleur -y` (verified `README.md:21`, `plugins/soleur/README.md:12`, `devin/INSTRUCTIONS.md`); requires `devin auth login`; local fallback `bash scripts/setup-devin.sh`; update via `devin plugins update soleur` (PR #8089).
- Devin-native manifest `.devin-plugin/plugin.json` and scaffolding parity with Codex/Grok (PRs #8084, #8088): `devin/skills/{go,help,sync}` wrappers, `hooks/devin-session-start.sh`, `.devin/config.json` SessionStart + PreToolUse hooks.

**Applicable learnings:**

- `2026-04-17-extract-tweets-numbered-format.md` — pin the numbered-format contract; a broken thread posts only the hook while reporting success.
- `2026-06-12-brainstorm-verify-capability-claims-against-code-and-decouple-build-from-news-window.md` (full name; earlier mention in this file elided) — every capability claim in the copy must trace to merged code (done above); ship now rather than hold for completeness.
- `2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md` — frontmatter is parsed line-wise by awk/sed; keep `channels: x, bluesky` on one line, values unquoted or double-quoted only.
- `2026-03-11-multi-platform-publisher-error-propagation.md` — partial failures file fallback issues; correct-by-construction beats post-failure repair.
- `integration-issues/github-token-pr-no-ci-trigger-ContentPublisher-20260326.md` — bot-authored content PRs have CI-trigger quirks; /ship should confirm checks actually ran on PR #8121.

**CLAUDE.md/constitution conventions applied:** kebab-case filename; plan frontmatter `title`/`type`/`date`; no second person in copy is a content choice — the published precedent uses first-person agent voice ("Shipped: ...", "my agent now audits...") — voice modeled on precedent, not invented.

**Property List (Phase 0.6b).** (1) A file exists at the publisher-scanned path `knowledge-base/marketing/distribution-content/2026-09-13-devin-cli-harness-support.md`. (2) Its frontmatter carries `publish_date` + `status: scheduled` + `channels: x, bluesky` so the cron both selects and routes it. (3) Its body carries `## X/Twitter Thread` and `## Bluesky` sections that satisfy the parser contract above. (4) Every claim in the copy traces to merged PRs 8083/8084/8087/8088/8089. (5) `publish_date` is a date the cron can still honor (`> 2026-09-13`).

**Cut List (Phase 0.6b).** Nothing cut — the brief proposes exactly one mechanism (one markdown file) and the pipeline scope forbids every other surface (no workflow YAML, no publisher changes). All five properties are bought by the single file; no existing mechanism covers them (the file does not exist on `origin/main`).

**Research posture:** local-only; no external research needed — the publisher contract, precedent, and PR facts are all in-repo/verified via `gh`. External facts (X 280, Bluesky 300) are already codified in `social-distribute/SKILL.md` and `content-publisher.sh`.

## User-Brand Impact

- **If this lands broken, the user experiences:** a public-facing announcement that is wrong or malformed — a 1-tweet "thread" that silently dropped its body (the #2496 failure class), a mid-sentence-truncated Bluesky post, a fabricated install command a follower copy-pastes and watches fail, or a `status: stale` flip that means the feature was never announced at all.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user data or secrets are involved — the file is public marketing copy. The exposure vector is reputational: an incorrect capability claim or a broken install command published under the brand account.
- **Brand-survival threshold:** `aggregate pattern` — an error here is visible to the whole follower audience at once; it is not a single user's breach. Mitigation is structural: every claim is pinned to a verified source line in Research Insights, and ACs make the parser contract checkable before merge.

## Proposed Content (direction for /work — finalize copy and re-count chars at write time)

Voice: match the published precedent — first-person, concrete, no hashtags, no Liquid markers. Lead with the differentiator (fourth harness; the pipeline actually runs in-session), then the one-command install.

Frontmatter (exact):

```yaml
---
title: "Soleur on Devin CLI: /soleur:go runs the real workflow"
type: feature-launch
publish_date: 2026-09-14
channels: x, bluesky
status: scheduled
pr_reference: "#8083"
---

<!-- To publish: set BOTH publish_date AND status: scheduled -->
```

`## X/Twitter Thread` — numbered format (hook un-prefixed; `2/ `, `3/ ` on fresh lines). Required beats, each tweet ≤280 chars:

- Hook: Devin CLI is the fourth supported harness (alongside Claude Code, Grok Build, Codex); `/soleur:go` runs the matching skill in-session.
- Install: `devin plugins install jikig-ai/soleur#plugins/soleur -y` — verbatim from `README.md:21`; `/soleur:go`, `/soleur:sync`, `/soleur:help` work as native Devin slash commands (PR #8087).
- Parity + update: Devin-native `.devin-plugin/plugin.json`, session-start hooks, `devin plugins update soleur` (PRs #8084/#8088/#8089).

`## Bluesky` — one paragraph ≤300 graphemes covering: fourth harness + install command + update command. No hashtags.

Every sentence must trace to the "Verified copy claims" list in Research Insights — do not add unverified claims (no benchmark numbers, no feature lists beyond the five PRs).

## Implementation Phases

### Phase 1 — Author the file

1.1. Create `knowledge-base/marketing/distribution-content/2026-09-13-devin-cli-harness-support.md` with the frontmatter block above and the two body sections, modeled on `2026-09-12-grok-build-plugin-workflow-fidelity.md` and `2026-07-06-agent-audits-its-own-governance-rulesets.md` (numbered thread).
1.2. Char-count every tweet (`≤280`) and the Bluesky body (`≤300`) at write time; keep `channels:` on one line; no `{{`/`}}`/`{%`/`%}` anywhere in the body.

### Phase 2 — Validate and commit

2.1. `bash scripts/lint-distribution-content.sh <file>` → exit 0.
2.2. Re-run the extraction the publisher runs (`awk` section extraction + numbered-mode tweet split from `content-publisher.sh` `extract_section`/`extract_tweets`) and confirm the tweet count equals the authored count — not 1.
2.3. publish_date freshness: `publish_date` must be strictly after `date -u +%F` at ship time; if it is not, bump to the next day in the same commit.
2.4. Commit to this branch (`feat-announce-devin-support`); PR #8121 is the carrier.

## Files to Create

- `knowledge-base/marketing/distribution-content/2026-09-13-devin-cli-harness-support.md`

## Files to Edit

- None.

## Open Code-Review Overlap

One open code-review issue touches the `distribution-content` surface: #3649 ("marketing: PR-A2 #3603 content brief — schedule for PR-C merge"). **Disposition: acknowledge** — it is a scheduling tracker for a different feature's content brief; it does not name this file and needs no fold-in. No other matches.

## Acceptance Criteria

- [ ] AC1 — `knowledge-base/marketing/distribution-content/2026-09-13-devin-cli-harness-support.md` exists, starts with `---`, and has a terminated frontmatter block.
- [ ] AC2 — Frontmatter carries `type: feature-launch`, `status: scheduled`, `channels: x, bluesky`, `pr_reference: "#8083"`, a non-empty `title:`, and `publish_date` strictly later than `date -u +%F` at ship time.
- [ ] AC3 — `## X/Twitter Thread` and `## Bluesky` headings each exist (exact strings) with non-empty bodies; running the publisher's `extract_section` awk against each returns content.
- [ ] AC4 — Thread format is well-formed: hook paragraph un-prefixed and each subsequent tweet begins `N/ ` with N sequential from 2 (labeled format equally acceptable if every tweet carries a `**Tweet N` label); an `extract_tweets`-equivalent run yields the authored count, not 1.
- [ ] AC5 — Each extracted tweet is `≤280` chars (`wc -m`); the `## Bluesky` body is `≤300` chars.
- [ ] AC6 — `bash scripts/lint-distribution-content.sh <file>` exits 0 (no Liquid markers in body).
- [ ] AC7 — The copy contains the exact string `devin plugins install jikig-ai/soleur#plugins/soleur -y` and `devin plugins update soleur`, matching `README.md:21`/`README.md:26` verbatim; no claim in the file lacks a source in the "Verified copy claims" list.
- [ ] AC8 — `git log origin/main --oneline -- knowledge-base/marketing/distribution-content/` confirms no pre-existing Devin announcement file (no double-post).

## Domain Review

**Domains relevant:** marketing

### Marketing

**Status:** reviewed (inline — the planning subagent has no Task/agent spawn; assessment performed against `brainstorm-domain-config.md`'s Marketing question and the verified PR facts; deepen-plan may re-run cmo if the pipeline wants a second pass)

**Assessment:** This is a pure marketing deliverable — public-facing feature announcement. The load-bearing marketing risks are (a) claim accuracy — closed by the verified-claims list; every copy assertion traces to a merged PR or README line; (b) timing — a missed announcement decays in value daily, so earliest-viable `publish_date` (2026-09-14) beats waiting for the next Tue/Thu auto-promotion slot (2026-09-17, since 09-15 is occupied by the grok file); (c) voice — precedent's first-person "Shipped/Soleur now runs on X" register is the established pattern for harness launches. `soleur-vs-devin.md` already exists as a published pillar comparison; this announcement should not re-litigate positioning — it announces capability.

### Product/UX Gate

Product domain assessed **not relevant** — the plan creates a markdown content file under `knowledge-base/marketing/`; the mechanical UI-surface override did not fire (no path in `## Files to Create`/`## Files to Edit` matches the ui-surface-terms glob superset: no `components/`, `app/**/page.tsx`, `*.njk`, etc.). Tier: none — skipped.

## Gates Evaluated (skipped — recorded for deepen-plan)

- **GDPR (2.7):** no regulated-data surface (no schema/migration/auth/API/`.sql`); none of the (a)–(d) extended triggers fire — the distribution *surface* (`cron-content-publisher`) already exists; this plan adds content to it, no new processing activity.
- **IaC (2.8):** no infrastructure introduced.
- **Observability (2.9):** pure-docs plan — no Files-to-Edit under code/infra paths. The publisher's own observability (stale emit, fallback issues, "published nowhere" issue) is pre-existing and unchanged.
- **ADR/C4 (2.10):** no architectural decision; the publishing substrate (ADR-033 Inngest spawn, ADR-054 bot-PR write path) is unchanged.
- **Encryption (2.11):** no store or connection.
- **Guard Contract (2.12):** deliverable includes no guard/gate/lint; ACs are one-shot verification commands, not shipped controls.
- **SpecFlow (3):** no conditional control flow; contract is declarative frontmatter + fixed section headings.
- **Scoped advisor (4.5):** skipped — trivially mechanical (single file, no architecture choice), and this subagent cannot spawn Task agents.

## Test Scenarios

- Given the authored file, when `bash scripts/lint-distribution-content.sh knowledge-base/marketing/distribution-content/2026-09-13-devin-cli-harness-support.md` runs, then exit code is 0.
- Given the file, when `awk '/^## X\/Twitter Thread/{f=1;next} /^## /{if(f)exit} f' <file>` runs, then non-empty copy prints; same for `## Bluesky`.
- Given the file, when each tweet block (split on `^N/ ` boundaries) is piped to `wc -m`, then every count ≤280 and the Bluesky body ≤300.
- Given the file, when `awk '/^publish_date:/{print $2}' <file>` is compared to `date -u +%F`, then publish_date is strictly greater (strict `>` so a merge-day `== today` file can't go stale if the 14:00 UTC cron already ran).
- Given a counterexample, when a malformed thread (no `2/ ` markers) is checked by the AC4 extraction, then the count reads 1 — proving the check discriminates.

## Risks & Non-Goals

- **Risk:** PR #8121 merges after 2026-09-14 14:00 UTC → file lands with `publish_date` in the past → publisher flips it to `stale` unposted. Mitigation: AC2's strict-`>` check at ship time + Phase 2.3 bump step.
- **Risk:** copy drift — an implementer adds unverified claims (star counts, "seamless", unsupported features). Mitigation: AC7 pins claims to the verified list.
- **Risk:** bot-PR CI quirk (`learnings/integration-issues/github-token-pr-no-ci-trigger-ContentPublisher-20260326.md`) — confirm checks ran on #8121 at ship time.
- **Risk:** cron-host credentials absent → per-channel skip + `Published nowhere` fallback issue; file is preserved (still `scheduled`), so this degrades to a delay, not a loss. No action needed in this plan.
- **Non-goals:** no LinkedIn/Discord sections (precedent ships x+bluesky only for feature-launch; adding channels is scope expansion); no changes to `content-publisher.sh`, workflows, or the promotion slot logic; no announcement for the grok file (already scheduled).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6 — it is filled above.
- `publish_date` is the single load-bearing field: the cron runs `0 14 * * *` UTC and flips past-dated files to `stale` **without posting**. Never ship `publish_date <= today` unless today < 14:00 UTC — and prefer strictly-future.
- The numbered `N/ ` thread format is sequence-enforced starting at 2 — a `1/`-prefixed hook or a skipped number collapses the thread into one tweet while the publisher reports success.

## References

- Precedent: `knowledge-base/marketing/distribution-content/2026-09-12-grok-build-plugin-workflow-fidelity.md` (scheduled), `2026-07-06-agent-audits-its-own-governance-rulesets.md` (published, numbered thread)
- Publisher: `scripts/content-publisher.sh` (`channel_to_section`, `extract_section`, `extract_tweets`, `post_bluesky`, main loop stale logic); `apps/web-platform/server/inngest/functions/cron-content-publisher.ts` (`0 14 * * *` UTC); `apps/web-platform/server/inngest/functions/content-promotion.ts` (Tue/Thu draft slots)
- Authoring contract: `plugins/soleur/skills/social-distribute/SKILL.md`; `scripts/lib/validate-tweet-draft.sh`; `scripts/lint-distribution-content.sh`
- PRs: #8083, #8084, #8087, #8088, #8089 (merged); #8121 (draft carrier for this work)
- Learnings: `learnings/bug-fixes/2026-04-17-extract-tweets-numbered-format.md`, `learnings/2026-06-12-brainstorm-verify-capability-claims-against-code-and-decouple-build-from-news-window.md`, `learnings/2026-03-12-directory-driven-content-discovery-frontmatter-parsing.md`, `learnings/integration-issues/github-token-pr-no-ci-trigger-ContentPublisher-20260326.md`

## Deepen-Plan Verification

Per-gate record for the 2026-09-13 deepen pass (all gates run inline; no Task subagents available to this planning subagent — skill/research/review fan-outs from deepen-plan Phases 2–5 were substituted with the mechanical checks each gate prescribes):

- **4.5 Network-outage:** no trigger pattern in plan (no SSH/firewall/timeout/terraform-provisioner). Skipped.
- **4.55 Downtime & Cutover:** no downtime-inducing operation (single new markdown file). Skipped.
- **4.6 User-Brand Impact:** PASS — section present, non-empty, threshold `aggregate pattern` (valid enum; no sensitive-path scope-out required since threshold ≠ `none`).
- **4.7 Observability:** pure-docs — `## Files to Edit` is empty and the sole `## Files to Create` path matches `^knowledge-base/`. Skipped per trigger list.
- **4.8 PAT-shaped variables:** PASS — the prescribed grep returned zero hits.
- **4.9 UI wireframe:** no UI-surface file in Files to Create/Edit (checked against `ui-surface-terms.md` glob superset). Skipped.
- **4.10 Encryption Posture:** no `.tf`/`.sql`/`cloud-init`/`docker-compose` file, no store or new connection. Skipped.
- **4.11 Guard Contract:** no guard-shaped deliverable. Skipped.
- **4.4 Precedent-diff:** pattern-bound file (distribution-content frontmatter + sections) diffed against TWO precedents — `2026-09-12-grok-build-plugin-workflow-fidelity.md` (scheduled, same channel set) and `2026-07-06-agent-audits-its-own-governance-rulesets.md` (published, numbered thread). Frontmatter key set, section headings, and the `<!-- To publish ... -->` comment match precedent shape exactly; only `issue_reference` is dropped (no issue exists for this work) — `get_frontmatter_field` treats it as optional.
- **4.45 verify-the-negative (inline):** "no Devin announcement on main" → `git ls-tree origin/main knowledge-base/marketing/distribution-content/` confirms only `soleur-vs-devin.md` (published pillar, different type). "Publisher does not pre-validate X length" → confirmed by reading `post_x_thread` (no char check; X API enforces). "`N/ ` collapse" → confirmed in `extract_tweets` numbered mode.
- **Quality checks:** all cited PR numbers re-verified live (`gh pr view` states+titles above); cited file paths glob-verified (only the to-be-created deliverable is absent, by design); no SHA/label/secret citations; no rule-ID citations (grep for `(hr|wg|cq|rf|pdr|cm)-` tokens in this file returns none); no grep-AC scans a scope containing this plan or tasks.md (AC8 scopes to `knowledge-base/marketing/distribution-content/` only); weekday math verified with `date -d`.
