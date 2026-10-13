---
title: "feature-tweet skill — cross-post ship tweets to X AND Bluesky"
type: enhancement
date: 2026-06-15
branch: feat-one-shot-feature-tweet-bluesky
semver: minor
lane: single-domain
requires_cpo_signoff: false
closes: 5022
---

> Closes #5022 — the canonical OPEN issue "feat: Bluesky channel for short-form
> ship tweets" (deferred from #5021 on 2026-06-08). Its re-evaluation criterion
> ("after the v1 X-only path is validated in production") was satisfied 2026-06-15
> when the first X-only ship tweet published. No new sub-issue filed — this PR
> targets the existing issue.

# ✨ feature-tweet — publish ship tweets to BOTH X and Bluesky

## Enhancement Summary

**Deepened on:** 2026-06-15
**Sections enhanced:** Research Insights added; deepen-plan halt gates (4.6/4.7/4.8/4.9) + realism passes (4.4/4.45) run inline.

### Halt-gate results (all pass)
- **4.6 User-Brand Impact:** present; threshold `none`; diff touches NO sensitive path (SKILL.md + repo-root `scripts/lib/*.sh` — not `apps/web-platform/{server,supabase,app/api,...}` nor `plugins/*/scripts/`). Pass.
- **4.7 Observability:** present; correctly justifies skip (no `apps/*` or `plugins/*/scripts/` code-class file; validator lives at `scripts/lib/`). Pass.
- **4.8 PAT-shaped variable:** none. Pass.
- **4.9 UI-wireframe:** no UI-surface file in Files-to-Edit (SKILL.md + two bash scripts). Skip — pass-through.

### Verify-the-negative pass (confirmed against implementation)
- **"never reaches X/Bluesky until operator flips `status: scheduled`"** — CONFIRMED at `scripts/content-publisher.sh:800` (`[[ "$status" == "scheduled" ]] || continue`) and `:804` (skips when `publish_date` < today / empty). A `status: draft` + empty `publish_date` draft is doubly parked. No new auto-publish path.
- **"`channels: x, bluesky` fires the Bluesky path"** — CONFIRMED at `:892-898` (`bluesky)` case calls `post_bluesky`), reached via the channel loop at `:844-900`. The loop **trims each token with `xargs`** (`:845`), so the comma+space form `x, bluesky` matches `bluesky)` correctly.

### Precedent-diff (4.4)
- Validator change mirrors the existing `x`/`## X/Twitter Thread` assertion shape verbatim (channel-token loop + heading-grep + awk-body-extract) — established canonical form in the same file; no novel pattern.
- The dual-channel draft shape (`channels: x, bluesky` + `## X/Twitter Thread` + `## Bluesky`) has a live working precedent: `knowledge-base/marketing/distribution-content/soleur-vs-crewai.md` (`channels: discord, x, bluesky, linkedin-company`), which publishes through this exact code path today.

### Key Improvements
1. Confirmed the comma+space `channels: x, bluesky` form is the publisher's validated input (xargs-trimmed) — the plan's prescribed frontmatter is correct as written.
2. Confirmed the parked-draft invariant is enforced at two independent gates in content-publisher (status AND publish_date) — User-Brand Impact "recoverable / no auto-publish" claim is load-bearing-true.
3. No 40-agent fan-out: a 3-file SKILL.md + bash-validator + bash-test change with a live precedent and externalized brand rules does not warrant the full review panel (ADR-053 tier discipline). The targeted verify-the-negative + precedent-diff passes carry the recall here.

## Overview

The `feature-tweet` skill converts a merged, verified-live PR into a **draft**
short-form post for operator approval, written to the
`knowledge-base/marketing/distribution-content/*.md` format drained by the
existing `content-publisher.sh` cron. Today it emits an **X-only** draft
(`channels: x`, one `## X/Twitter Thread` section) and explicitly defers Bluesky.

Bluesky is already fully wired everywhere **except** this skill:

- `BSKY_HANDLE` + `BSKY_APP_PASSWORD` creds exist in Doppler prd (consumed by
  `content-publisher.sh:687`).
- `content-publisher.sh` already cross-posts `channels: x, bluesky` for pillar
  content: its `extract_section` channel→heading map at line **185** is
  `bluesky → "Bluesky"` (i.e. `## Bluesky`), it iterates the comma-separated
  `channels` field at line **900**, and `post_bluesky` (line 683) extracts the
  `## Bluesky` section and enforces a **300-character** limit at line **705**.
- A working multi-channel precedent draft exists:
  `knowledge-base/marketing/distribution-content/soleur-vs-crewai.md` declares
  `channels: discord, x, bluesky, linkedin-company` and carries both a
  `## X/Twitter Thread` and a `## Bluesky` section.

This change closes the gap **purely inside the feature-tweet skill + its
validator**: generate BOTH an X thread and a Bluesky post, write `channels: x,
bluesky` with both sections, remove the deferral notes, and extend the
structural validator to assert the Bluesky channel token + a non-empty
`## Bluesky` section. The draft-only parked state (`status: draft`, empty
`publish_date`) is unchanged. The X behavior is unchanged. `content-publisher.sh`
is NOT touched (it already supports bluesky).

**Date-anchored context (no action):** on 2026-06-15 a ship tweet for the
workspace-reconnect feature published to X but not Bluesky — the X-only gap this
plan closes.

## Research Reconciliation — Spec vs. Codebase

The ARGUMENTS block cites two file paths that do not match the repo. Verified
live at plan time:

| Claim (ARGUMENTS) | Reality (verified `find` / `grep`) | Plan response |
|---|---|---|
| Validator at `plugins/soleur/skills/feature-tweet/scripts/validate-tweet-draft.sh` | Validator is at repo-root **`scripts/lib/validate-tweet-draft.sh`**. The `feature-tweet` skill dir contains ONLY `SKILL.md` (no `scripts/` subdir). SKILL.md Step 6 already references the correct path `scripts/lib/validate-tweet-draft.sh`. | Edit the **actual** file `scripts/lib/validate-tweet-draft.sh`. No path change to SKILL.md needed. |
| Test "under `plugins/soleur/test/` or a `*.test.sh`" | Test is at repo-root **`scripts/lib/validate-tweet-draft.test.sh`**. Run by `scripts/test-all.sh:183` via the `scripts/lib/*.test.sh` glob. | Update **`scripts/lib/validate-tweet-draft.test.sh`** in lockstep (TDD-first). |
| "Bluesky already wired in content-publisher" | Confirmed: `extract_section` map line 185 (`bluesky → "Bluesky"`), channel loop line 900, `post_bluesky` + 300-char cap lines 683/705. | No change to `content-publisher.sh`. |
| tweet-eligibility.sh + lint-distribution-content.sh channel-agnostic | Confirmed read-only. `tweet-eligibility.sh` operates on PR labels/title/paths only — no channel/section logic. `lint-distribution-content.sh` only scans for unrendered Liquid markers (one Bluesky mention is a comment, not logic). | Verify-only (no edits). Acceptance Criteria assert agnosticism via grep. |
| Brand-guide has Bluesky guidance | Confirmed: `### Bluesky` at `knowledge-base/marketing/brand-guide.md:439` — 300-char grapheme limit (line 446), no hashtags (448), no emojis in standalone posts (449), and line 464: **"Do not cross-post identical content from X/Twitter. Adapt the message."** | Step 4 instruction must require an **adapted** Bluesky post (not a copy of the X hook), anchored to `### Bluesky`. |

**Premise Validation:** all four ARGUMENTS-cited mechanisms (Doppler creds,
`bsky-community.sh`, `content-publisher.sh` cross-post, `extract_section`
mapping) hold. Two file paths in the ARGUMENTS block are wrong (validator +
test live at repo-root `scripts/lib/`, not under the skill dir); both corrected
above. No GitHub issue/PR is cited by reference, so there is no stale-issue
premise to validate.

## User-Brand Impact

**If this lands broken, the user experiences:** a malformed distribution-content
draft — either the validator wrongly rejects a correct dual-channel draft (the
skill deletes the file and the operator gets no ship post at all), or the
validator wrongly accepts a draft missing the `## Bluesky` section, which then
dies silently at `post_bluesky` publish time ("No Bluesky content found … Skipping
Bluesky", `content-publisher.sh:699`). Both are recoverable (drafts are parked,
never auto-posted; the standalone catch-up path re-runs the skill).

**If this leaks, the user's data is exposed via:** no new exposure vector. The
draft is parked (`status: draft`, empty `publish_date`) and never reaches X or
Bluesky until the operator manually flips `status: scheduled`. Sanitization rules
(benefit-only, no PII/contributor names, no customer names, no naked numbers) are
unchanged and apply to BOTH the X thread and the Bluesky post. The fail-closed
`tweet-eligibility.sh` floor (excludes security/infra/credential/payment PRs
before any draft is generated) is unchanged and is channel-agnostic.

**Brand-survival threshold:** none.

Rationale (threshold = none, and the diff touches NO sensitive path per the
preflight Check 6 canonical regex — only a SKILL.md, a bash validator, and its
test): the change adds a second draft section to an operator-gated, parked draft.
Nothing auto-publishes; the eligibility floor and sanitization rules are
untouched; no schema, auth, migration, or secret surface is involved.

## Implementation Phases

### Phase 0 — Preconditions (re-verify at /work time)

Cheap re-greps before editing (guard against drift between plan and /work):

```bash
# Validator + test live at repo-root scripts/lib/ (NOT under the skill dir)
test -f scripts/lib/validate-tweet-draft.sh
test -f scripts/lib/validate-tweet-draft.test.sh
# content-publisher bluesky→"Bluesky" map + 300-char cap (do NOT edit this file)
grep -n 'bluesky)' scripts/content-publisher.sh           # ~line 185
grep -n 'char_count > 300' scripts/content-publisher.sh   # ~line 705
# Channel-agnostic verify targets
grep -nE 'bluesky|Bluesky|channels|## ' scripts/lint-distribution-content.sh   # only a comment
grep -nE 'bluesky|Bluesky|channels|section' scripts/lib/tweet-eligibility.sh   # nothing
# The test runner that exercises *.test.sh (bash convention — NOT bats/jest)
grep -n 'scripts/lib/\*\.test\.sh' scripts/test-all.sh    # line 183
```

If any path drifts, halt and re-resolve before continuing.

### Phase 1 — RED: extend the validator test (TDD-first)

File: `scripts/lib/validate-tweet-draft.test.sh`

The existing `VALID` fixture (lines 36-49) uses `channels: x` and a single
`## X/Twitter Thread` section. After the validator change it must require BOTH a
`bluesky` channel token AND a non-empty `## Bluesky` section. Steps:

1. **Update the `VALID` fixture** to the dual-channel shape so it stays a
   passing fixture:
   - `channels: x` → `channels: x, bluesky`
   - Append a `## Bluesky` section with a non-empty body after the X thread, e.g.:

     ```markdown
     ## Bluesky

     Your AI team now operates on your actual codebase -- open, file-based, no black box.
     ```

2. **Fix the now-stale existing assertions** that assumed X-only:
   - Line 80 `_expect_reject "rejects channels without x" "${VALID/channels: x/channels: bluesky}"` — the substitution target `channels: x` no longer exists verbatim in the new `VALID` (it is now `channels: x, bluesky`). Rewrite this rejection to target `channels: x, bluesky` → `channels: bluesky` (still asserts "missing x ⇒ reject").
   - Lines 98-101 (inline-list / quoted-form pass+reject cases) substitute
     `channels: x`; retarget them to the new `channels: x, bluesky` literal, and
     ensure each PASS variant still carries `x` AND `bluesky` (e.g.
     `channels: [x, bluesky]`), each REJECT variant drops one required token.
   - Note: the `_expect_reject "rejects channels: [bluesky] (no x)"` case (line
     101) stays valid as a missing-x rejection.

3. **Add NEW RED assertions** (these MUST fail against the unmodified validator,
   proving the new behavior is genuinely tested):
   - `_expect_reject "rejects channels without bluesky"` — fixture with
     `channels: x` only (no bluesky token) ⇒ must be rejected.
   - `_expect_reject "rejects missing ## Bluesky heading"` — an explicit fixture
     (mirroring the `NO_HEADING` pattern at line 83) with `channels: x, bluesky`,
     a valid `## X/Twitter Thread`, but NO `## Bluesky` heading ⇒ rejected.
   - `_expect_reject "rejects empty ## Bluesky body"` — fixture with the
     `## Bluesky` heading present but an empty body (mirroring `EMPTY_THREAD` at
     line 117) ⇒ rejected.
   - `_expect_pass "accepts channels: [x, bluesky] with both sections"` — confirm
     the inline-list form with both sections passes.

4. **Run RED:** `bash scripts/lib/validate-tweet-draft.test.sh` — the new
   bluesky assertions (and the updated `VALID`) MUST fail/error against the
   current validator (which neither requires the bluesky token nor the
   `## Bluesky` section). Capture the failing output.

> Note on `_expect_reject` rigor: the helper (lines 59-67) requires the
> validator's own `invalid:` marker on stderr, NOT just any non-zero exit — so a
> broken script (`rc=127`) cannot pass vacuously. New reject messages MUST use
> the `invalid:` prefix to satisfy this.

### Phase 2 — GREEN: extend the validator

File: `scripts/lib/validate-tweet-draft.sh`

Mirror the existing `x` + `## X/Twitter Thread` assertions for bluesky. Three
edits, each parallel to its X counterpart:

1. **Header comment** (lines 11-16): add two bullets documenting the new
   assertions (`channels` includes `bluesky`; non-empty `## Bluesky` section).

2. **Channels token check** (after the `channels_has_x` block, lines 65-73): add
   a `channels_has_bluesky` check using the SAME punctuation-stripping loop
   (handles `[x, bluesky]`, `"x, bluesky"`, `x, bluesky`):

   ```bash
   channels_has_bluesky=0
   for _tok in ${_channels_clean//,/ }; do
     [[ "$_tok" == "bluesky" ]] && channels_has_bluesky=1
   done
   if [[ "$channels_has_bluesky" -ne 1 ]]; then
     echo "invalid: 'channels' must include the 'bluesky' token (got '${channels:-<missing>}')" >&2
     exit 1
   fi
   ```

   (`_channels_clean` is already computed once at line 66 — reuse it; do not
   recompute.)

3. **`## Bluesky` heading + non-empty body check** (after the X thread body
   check, lines 76-91): add a grep for the heading and an awk-extract of the
   body, mirroring lines 76-91 exactly but for `## Bluesky`:

   ```bash
   if ! grep -qE '^## Bluesky[[:space:]]*$' "$file"; then
     echo "invalid: missing '## Bluesky' heading" >&2
     exit 1
   fi
   bluesky_body=$(awk '
     /^## Bluesky[[:space:]]*$/ { grab=1; next }
     grab && /^## / { exit }
     grab { print }
   ' "$file" | grep -vE '^[[:space:]]*$' || true)
   if [[ -z "$bluesky_body" ]]; then
     echo "invalid: '## Bluesky' section is empty" >&2
     exit 1
   fi
   ```

4. **Run GREEN:** `bash scripts/lib/validate-tweet-draft.test.sh` — all
   assertions (existing + new) pass.

### Phase 3 — SKILL.md content changes

File: `plugins/soleur/skills/feature-tweet/SKILL.md`

1. **Step 4 head + 280-char rule (lines 66-88):** broaden the step to generate
   BOTH an X thread AND a Bluesky post.
   - Retitle context so the step covers two outputs.
   - Keep the X thread rules verbatim (shape, `2/`/`3/` prefixes, **280-char per
     tweet**, links in final tweet).
   - Add a Bluesky sub-block anchored to `knowledge-base/marketing/brand-guide.md`
     → `### Bluesky`: a single standalone post (or short reply chain), **300-char
     limit per post** enforced during generation, **no hashtags**, **no emojis in
     a standalone post**, and — per brand-guide line 464 — the Bluesky post must
     be **adapted, not an identical copy** of the X hook.
   - Sanitization rules (benefit-only, no contributor/customer names, no naked
     numbers) apply identically to BOTH outputs — state once, scope to both.

2. **Step 5 frontmatter (line 103):** `channels: x` → `channels: x, bluesky`.

3. **Step 5 body template (lines 111-118):** add a `## Bluesky` section after the
   `## X/Twitter Thread` block:

   ```markdown
   ## X/Twitter Thread

   <hook tweet>

   2/ <body tweet>

   3/ <final tweet, link only if applicable>

   ## Bluesky

   <single adapted Bluesky post, ≤300 chars, no hashtags>
   ```

4. **Remove the deferral note (lines 120-122):** the sentence
   "`channels: x` only — Bluesky is deferred (the publisher needs one body
   section per channel)." Replace with text affirming the now-supported
   dual-channel state: `publish_date: ""` + `status: draft` is the parked state;
   `channels: x, bluesky` produces one body section per channel, both drained by
   `content-publisher.sh`.

5. **Step 6 assertion prose (lines 130-131):** update to mention the new
   assertions — "Asserts a non-empty `title`, `status: draft`, a `channels` value
   including BOTH `x` and `bluesky`, and non-empty `## X/Twitter Thread` AND
   `## Bluesky` sections."

6. **Multi-PR contract (lines 152-157):** remove the `channels: x` /
   Bluesky-deferred framing if present (the section currently frames "one tweet
   per eligible PR" — re-read at /work; drop any "X-only" wording, keep the
   one-PR-per-draft + standalone catch-up semantics).

7. **Description frontmatter (line 3):** OPTIONAL. Current description says
   "draft short-form X post". Consider broadening to "X and Bluesky" for routing
   accuracy. **Budget gate:** before editing `description:`, run
   `bun test plugins/soleur/test/components.test.ts` and confirm ≥10 words of
   headroom under the 1800-word cap; if at/near cap, leave the description
   unchanged (the routing meaning is unaffected) rather than trimming siblings
   for a cosmetic gain. Treat this edit as droppable.

### Phase 4 — Verify (no edits)

1. **Channel-agnosticism (assert, don't change):**
   - `grep -nE 'bluesky|Bluesky|## |section' scripts/lib/tweet-eligibility.sh`
     → no channel/section logic (PR-metadata only).
   - `grep -nE '## X|## Bluesky|extract_section|channels' scripts/lint-distribution-content.sh`
     → only the one descriptive comment; no per-channel branching.
2. **`content-publisher.sh` untouched:** `git diff --name-only` must NOT list
   `scripts/content-publisher.sh`.
3. **Full test suite for the validator class:**
   `bash scripts/lib/validate-tweet-draft.test.sh` green; and
   `bash scripts/lib/tweet-eligibility.test.sh` still green (unchanged behavior).
4. **End-to-end sanity:** write a temp dual-channel draft matching the new Step 5
   template and run `bash scripts/lib/validate-tweet-draft.sh <tmp>` (exit 0) and
   `bash scripts/lint-distribution-content.sh <tmp>` (exit 0). Then a negative:
   the same draft with the `## Bluesky` section removed must be REJECTED by the
   validator.

## Files to Edit

- `plugins/soleur/skills/feature-tweet/SKILL.md` — Step 4 (dual output + Bluesky
  rules), Step 5 (`channels: x, bluesky` + `## Bluesky` body section), remove
  deferral note (L120-122), Step 6 prose (L130-131), Multi-PR contract
  (L152-157), optional `description:` (L3, budget-gated/droppable).
- `scripts/lib/validate-tweet-draft.sh` — add `bluesky` channel-token assertion +
  `## Bluesky` heading/non-empty-body assertion, mirroring the existing `x` +
  `## X/Twitter Thread` checks; update header comment.
- `scripts/lib/validate-tweet-draft.test.sh` — TDD-first: update `VALID` fixture
  to dual-channel, retarget stale `channels: x` substitutions, add RED
  bluesky-missing / heading-missing / empty-body / both-sections-pass assertions.

## Files to Create

None.

## Files NOT to Edit (constraints)

- `scripts/content-publisher.sh` — already supports `bluesky` (map L185, loop
  L900, `post_bluesky` + 300-char cap L683/705). Do not touch.
- `scripts/lib/tweet-eligibility.sh` — channel-agnostic; verify only.
- `scripts/lint-distribution-content.sh` — channel-agnostic; verify only.
- X behavior in SKILL.md and the validator — unchanged.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` returns no issue whose
body names `feature-tweet`, `validate-tweet-draft.sh`, or the SKILL.md path —
re-run the standalone-jq overlap query at /work to confirm.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 (RED captured):** before the Phase 2 validator change, the new
  bluesky assertions in `validate-tweet-draft.test.sh` fail — a draft with
  `channels: x` (no bluesky) and/or no `## Bluesky` section is NOT rejected by
  the current validator. Failing output captured in the PR/commit.
- [ ] **AC2 (GREEN):** `bash scripts/lib/validate-tweet-draft.test.sh` exits 0
  with all assertions passing (existing + new), printing
  `=== validate-tweet-draft: N passed, 0 failed ===`.
- [ ] **AC3 (channel token):** `bash scripts/lib/validate-tweet-draft.sh <draft>`
  exits 1 with `invalid: 'channels' must include the 'bluesky' token` for a draft
  whose `channels` lacks `bluesky`; exits 0 when both `x` and `bluesky` are
  present (incl. inline-list `[x, bluesky]` and quoted forms).
- [ ] **AC4 (section gate):** the validator exits 1 with
  `invalid: missing '## Bluesky' heading` (no heading) and
  `invalid: '## Bluesky' section is empty` (heading, empty body); exits 0 with a
  non-empty `## Bluesky` body.
- [ ] **AC5 (X unchanged):** all pre-existing X assertions still pass; a draft
  missing `x` or `## X/Twitter Thread` is still rejected with the existing
  messages.
- [ ] **AC6 (SKILL.md dual-channel):** `grep -n 'channels: x, bluesky'
  plugins/soleur/skills/feature-tweet/SKILL.md` returns the Step 5 frontmatter;
  `grep -nE '^## Bluesky' plugins/soleur/skills/feature-tweet/SKILL.md` returns
  the body-template section; and `grep -in 'bluesky is deferred'
  plugins/soleur/skills/feature-tweet/SKILL.md` returns NOTHING.
- [ ] **AC7 (parked state unchanged):** SKILL.md Step 5 still shows
  `publish_date: ""` and `status: draft`; the `<!-- To publish: set BOTH
  publish_date AND status: scheduled -->` comment is retained.
- [ ] **AC8 (char limits stated):** SKILL.md Step 4 states the **280-char per
  tweet** limit for X (unchanged) AND a **300-char per post** limit for Bluesky.
- [ ] **AC9 (content-publisher untouched):** `git diff --name-only origin/main`
  does NOT include `scripts/content-publisher.sh`.
- [ ] **AC10 (agnostic siblings verified):** the Phase 4 greps confirm
  `tweet-eligibility.sh` and `lint-distribution-content.sh` carry no per-channel
  section/branch logic; `bash scripts/lib/tweet-eligibility.test.sh` still green.
- [ ] **AC11 (end-to-end):** a temp draft matching the new Step 5 template passes
  BOTH `validate-tweet-draft.sh` and `lint-distribution-content.sh` (exit 0); the
  same draft with `## Bluesky` removed is rejected by the validator.
- [ ] **AC12 (suite):** `bash scripts/test-all.sh` (or at minimum the two
  `scripts/lib/*.test.sh` tweet tests it globs) passes.
- [ ] **AC13 (semver):** PR carries the `semver:minor` label and a `## Changelog`
  section (skill enhancement). No edits to `plugin.json` / `marketplace.json`
  version fields.

### Post-merge (operator)

- [ ] None. No infra, migration, or external-service state change. The
  content-publisher cron already supports `bluesky`; the next eligible ship tweet
  produces a dual-channel draft that the operator approves as usual.

## Domain Review

**Domains relevant:** Marketing (advisory, self-assessed)

### Marketing

**Status:** reviewed (self-assessed — no leader spawn warranted)
**Assessment:** The change governs how ship-tweet *drafts* are authored for two
channels. Brand-voice rules are already externalized to
`knowledge-base/marketing/brand-guide.md` (`### X/Twitter` and `### Bluesky`),
which the skill references rather than restates. The single substantive brand
constraint to honor is line 464 — "Do not cross-post identical content from
X/Twitter; adapt the message" — folded into Phase 3 Step 4. No new brand artifact
is produced; the operator approval gate (parked draft) is the human review point.
No CMO/copywriter spawn needed for a draft-authoring instruction change that
defers all voice rules to the existing brand guide.

### Product/UX Gate

Not applicable. No UI surface: the Files-to-Edit list is one `SKILL.md`, one bash
validator, one bash test — none match `components/**/*.tsx`, `app/**/page.tsx`,
`app/**/layout.tsx`, or any UI-surface term. Mechanical override does not fire.

## Observability

Not applicable (skip per Phase 2.9 skip rule). The Files-to-Edit list contains no
code-class file under `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or
`plugins/*/scripts/`, and introduces no new infrastructure surface. The validator
is a synchronous skill-time gate whose failure is surfaced immediately to the
operator (the skill deletes the partial draft and aborts — SKILL.md Step 6);
publish-time Bluesky failures are already handled by `content-publisher.sh`'s
existing `create_bluesky_fallback_issue` path (line 663), which this plan does not
change.

## Infrastructure (IaC)

Not applicable. Pure code/docs change against already-provisioned surfaces
(Doppler creds + content-publisher cron already exist). No new server, service,
cron, secret, vendor, or DNS/TLS resource. Phase 2.8 skip rule applies.

## GDPR / Compliance

Skipped — no regulated-data surface. The diff touches a SKILL.md, a bash
validator, and a bash test; none of schema/migration/auth/API-route/`.sql`
surfaces. No new LLM processing of operator-session data, no new distribution
surface (the distribution-content + Bluesky channel already existed), threshold
is `none`. None of the (a)-(d) expansion triggers fire.

## Test Scenarios

| Scenario | Input | Expected |
|---|---|---|
| Valid dual-channel draft | `channels: x, bluesky` + both sections non-empty | validator exit 0; lint exit 0 |
| Missing bluesky token | `channels: x` + both sections | exit 1 `invalid: 'channels' must include the 'bluesky' token` |
| Missing `## Bluesky` heading | `channels: x, bluesky`, only `## X/Twitter Thread` | exit 1 `invalid: missing '## Bluesky' heading` |
| Empty `## Bluesky` body | heading present, no body | exit 1 `invalid: '## Bluesky' section is empty` |
| Inline-list channels | `channels: [x, bluesky]` + both sections | exit 0 |
| Missing x (regression) | `channels: bluesky` | exit 1 `invalid: 'channels' must include the 'x' token` |
| Missing X thread (regression) | no `## X/Twitter Thread` | exit 1 (existing message) |
| Unterminated frontmatter (regression) | opening `---`, no closing fence | exit 1 (existing message) |

## Sharp Edges

- The validator + its test live at **repo-root `scripts/lib/`**, NOT under
  `plugins/soleur/skills/feature-tweet/scripts/` (which does not exist). The
  ARGUMENTS block's paths are wrong; SKILL.md's `scripts/lib/...` references are
  right. Edit the repo-root files.
- The `.test.sh` files run under the **bash `.test.sh` convention** via
  `scripts/test-all.sh:183` (glob `scripts/lib/*.test.sh`). Do NOT introduce
  bats/jest. Use the existing `_expect_pass`/`_expect_reject` helpers.
- `_expect_reject` requires the validator's own `invalid:` stderr marker (not
  just non-zero exit) — every new reject message MUST use the `invalid:` prefix.
- Reuse `_channels_clean` (already computed once in the validator) for the
  bluesky token loop — do not recompute the punctuation-strip.
- The existing `VALID` fixture uses `channels: x`; once it becomes
  `channels: x, bluesky`, every test substitution targeting the literal
  `channels: x` (lines 80, 98-101) breaks silently (bash `${VAR/find/replace}`
  is a no-op when `find` is absent). Retarget each to the new literal in lockstep
  with the fixture change.
- Brand-guide line 464: the Bluesky post must be **adapted**, not an identical
  copy of the X hook (different char budget — 300 vs 280 — and no hashtags).
- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold fails `deepen-plan`
  Phase 4.6. This plan's threshold is `none` with a documented sensitive-path
  scope-out reason.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Author the Bluesky post as a verbatim copy of the X hook | Violates brand-guide line 464 ("do not cross-post identical; adapt"). The 300-char budget and no-hashtag rule also differ from X. |
| Make `channels` configurable (flag to opt out of Bluesky) | YAGNI. The task is to make X+Bluesky the standard ship-tweet shape; the operator can still edit `channels` in the parked draft before publishing. |
| Edit `content-publisher.sh` to special-case ship tweets | Out of scope and unnecessary — the publisher already cross-posts `channels: x, bluesky` for pillar content via the same code path. The gap was only in the skill + validator. |
| Put the validator under the skill dir to match ARGUMENTS | The validator already lives at `scripts/lib/` and is correctly referenced by SKILL.md + globbed by `test-all.sh`. Moving it would be a gratuitous, churn-heavy rename. |

## Changelog (for PR body)

- `feat(feature-tweet): cross-post ship tweets to X and Bluesky` — the
  feature-tweet skill now generates BOTH an X thread and an adapted Bluesky post
  (`channels: x, bluesky`, `## X/Twitter Thread` + `## Bluesky` sections); the
  structural validator asserts the `bluesky` channel token and a non-empty
  `## Bluesky` section. Draft-only parked state and X behavior unchanged.
  (`semver:minor`)
