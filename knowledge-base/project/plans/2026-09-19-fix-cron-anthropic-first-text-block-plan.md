---
title: "fix(cron): postAnthropicMessage reads the first text block, not content[0]"
type: fix
date: 2026-09-19
slug: fix-cron-anthropic-first-text-block
branch: feat-one-shot-8392-anthropic-text-block
issue: 8392
closes: 8392
priority: P1
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(cron): postAnthropicMessage reads the first text block, not content[0]

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-19 · **Panels:** `plan-review` eng (DHH, Kieran, code-simplicity) + named devex (CTO); `deepen-plan` (observability-coverage, test-design, verify-the-negative sweep); ADR-083 scoped advisor consult.

### Key improvements

1. **Scope corrected from two files to the class.** The original premise grepped only `apps/web-platform/server` and under-counted. A repo-wide census found `scripts/compound-promote.sh:231` — same feature, same `claude-sonnet-5` pin, **live-broken** — plus a latent bench twin. AC2 is now a tree-wide census (measured: 4 today → 0 on the branch), so "Deferred items: none" is verified rather than assumed.
2. **The workflow gap that hid it for ten weeks is fixed.** `audit-models.sh` printed `thinking-API shape: … (no-op)` — true of the request side, irrelevant to the response side, and contradicting its own SKILL.md row. Its replacement census must reuse the script's `$ROOT`-anchored, rc-discriminating scan, or it would print a clean verdict meaning "the scan ran nowhere".
3. **Test ordering inverted so RED means something.** Fixtures normalize first (backward-compatible); every new case then lands before any production change. The green fixture run is explicitly *not* credited as verification — the instrument is AC4's 8 → 0 count.
4. **A vacuous test case was caught and sharpened.** The thinking-only pin returned `""` under both the old and new readers and killed no mutant; it now carries a decoy `text` on the thinking block, making it a second RED that pins *selection by type, not position*.
5. **Two unfalsifiable gates were rewritten.** AC10's original "clusters > 0 OR a named status" admitted every outcome; the `discoverability_test` accepted both rc 0 and rc 2. Both now have exactly one passing condition, and AC10's `inngest.run_id` join has an executable read.

### New considerations discovered

- The layer-7 citation for the two shell arms is accepted as **ephemeral-only**, with the reason stated — the durable arm for this feature is the Inngest cron's marker.
- `cron-weekly-release-digest.test.ts` runs in the `repo-wide` vitest project, not `unit`; the two halves are gated differently in CI.
- AC2 cannot self-match the census it adds to `audit-models.sh`, because that script carries the pattern backslash-escaped. Keep the escapes.

## Overview

`postAnthropicMessage` in `apps/web-platform/server/inngest/functions/_cron-shared.ts` returns `data.content?.[0]?.text ?? ""`. Since `EXECUTION_MODEL` became `claude-sonnet-5` (2026-07-01, #5849), the first content block is an adaptive-thinking block and the structured-output text sits at index 1, so every `cron-compound-promote` run has read an empty string since the cron was
enabled on 2026-07-06 (#6100 — the model swap on 07-01 is when the defect was born,
07-06 is when it started running), mirrors `Empty Anthropic response` to Sentry, and reports `no-qualifying-clusters` after billing the full output. The fix takes the first block whose `type === "text"`.

Evidence (verified by the parent session, cited not re-derived): manual fire 2026-09-19T20:06:47Z emitted `SOLEUR_CLAUDE_COST output_tokens=12306` followed by `SOLEUR_COMPOUND_PROMOTE_OUTCOME status=no-qualifying-clusters clusters_proposed=0`; Better Stack 30d shows the same `Empty Anthropic response` silent-fallback on the 2026-09-13 00:01Z cron run.

**Scope is the CLASS, not the one file.** A repo-wide census (below) finds exactly four readers that index content position 0; two are live-broken under `claude-sonnet-5` and two are latent under `claude-haiku-4-5`. All four are one-expression fixes and all four land here.

## Research Insights

**Premise Validation (Phase 0.6, corrected at plan-review).** #8392 is OPEN with no closing PR. Every cited symbol exists: `_cron-shared.ts:659` is verbatim `return { text: data.content?.[0]?.text ?? "", stopReason: data.stop_reason };` with the cast at `:629` reading `content?: Array<{ text?: string }>`; `domain-router.ts:181` is verbatim `const text = data.content[0]?.type === "text" ? (data.content[0].text ?? "") : "";`. Both compound-promote and the weekly digest pass `model: ANTHROPIC_MODEL = EXECUTION_MODEL`, so the digest is the same class and is covered by the same helper fix; `cron-anthropic-credit-probe.ts:83` passes `maxTokens: 1` and discards `text`. No ADR mentions thinking blocks, `content[0]`, or adaptive thinking — the mechanism is a parse fix, not an architectural decision. #8281 and #8293 are OPEN.

**Correction — the original premise scoped its grep to `apps/web-platform/server` and therefore under-counted the class** (the exact failure the plan's own cited learning, `2026-02-22-model-id-update-patterns.md`, warns about: *grep every reader of the shape*). The corrected repo-wide census, run against the working tree:

```bash
grep -rn 'content\[0\]\|content?\.\[0\]' --include=*.ts --include=*.sh --include=*.mjs --include=*.js \
  apps plugins scripts .github | grep -viE 'test|\.md:'
```

returns exactly **four** sites. Scoped honestly at review: that is a claim about
this GREP (two spellings, four extensions), not about the class. A fifth reader,
`apps/web-platform/server/email-triage/summarize.ts`, already selected by type before
this PR; `apps/web-platform/server/agent-runner.ts` reads `content[content.length - 1]`
through an aliased binding, which is invisible to any such grep and is deliberate
last-block streaming behaviour, not this defect. The durable guard is
`scripts/lint-anthropic-content-position.py`, twin-registered in `scripts/test-all.sh`:

| Site | Model | State |
|---|---|---|
| `apps/web-platform/server/inngest/functions/_cron-shared.ts:659` | `claude-sonnet-5` | **live-broken** — the reported defect |
| `scripts/compound-promote.sh:231` | `claude-sonnet-5` (pinned at `:218`) | **live-broken** — `jq -r '.content[0].text // empty'`, then `exit 1` with `::error::Anthropic API returned empty content`. Same feature's shell arm; strictly worse than the latent sites the issue already names |
| `apps/web-platform/server/domain-router.ts:181` | `claude-haiku-4-5-20251001` | latent — Haiku 4.5 emits no thinking block when `thinking` is omitted |
| `scripts/learning-retrieval-bench.sh:360` | Haiku bench | latent — same `jq` one-liner |

**Property List (Phase 0.6b).**

- P1. When the response carries a text block at any index, every reader returns that block's text.
- P2. When the response carries no text block (empty `content`, or only non-text blocks), every reader returns `""`/empty and the caller's existing guard still fires.
- P3. The digest and compound-promote Inngest callers need no change: the helper is the single choke point for both, and no caller parses `content` itself.
- P4. No reader silently degrades the day its model string is bumped to a thinking-by-default model.
- P5. The per-model-release audit stops asserting that the thinking axis is a no-op, which is what let P1 stay false for ten weeks.

**Cut List (Phase 0.6b).**

- "Join all text blocks" → P1 → cut: structured outputs (`output_config.format: json_schema`) yield exactly one text block; first-text is what the issue prescribes and what `domain-router.ts` already does. Concatenation is a behavior change with no property behind it. (Re-raised by the ADR-083 advisor; kept cut — see DC1.)
- "Add `thinking: {type: \"disabled\"}` to the request" → P1 → cut: hides the symptom instead of fixing the parser, changes model behavior and cost, and the `claude-api` skill records that disabling thinking on current models has its own failure modes.
- "Wrap the helper in `@anthropic-ai/sdk`" → P1 → cut: the helper is raw `fetch` by design (no SDK dependency in `functions/`), and the fix is one expression.
- "New Sentry marker / drift-guard test for the two-copy parse" → P4 → cut: `reportSilentFallback("Empty Anthropic response")` already distinguishes a genuine empty once the parser is right, and a lint rule for two call sites is over-engineering at this size. The repo-wide census AC is the mechanical guard instead.
- "Digest handler-level thinking-first test" → P3 → cut at plan-review: once the digest fixtures carry `type: "text"`, the existing digest happy-path suite already runs through the new picker, and the thing actually worth pinning — that no caller parses `content` itself — is the census grep, not a test.

**Relevant files.**

- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — `postAnthropicMessage`, its response cast and return line.
- `apps/web-platform/server/domain-router.ts` — the deliberately-inlined classify fetch, plus the NOTE comment that tells future editors to mirror changes into both copies.
- `scripts/compound-promote.sh` — the shell arm of the same feature; no workflow invokes it (`grep -rn compound-promote.sh .github` is empty), but `lefthook.yml:140`, `scripts/compound-promote.test.sh` and `scripts/lint-agents-compound-sync.sh:134` all treat it as live, and it is operator/agent-runnable.
- `scripts/learning-retrieval-bench.sh` — retrieval bench invoked from `plugins/soleur/skills/kb-search/SKILL.md`.
- `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` — prints, under `[3] pricing + tier-map + dormant work`, `thinking-API shape: carried by the claude-code-action pin's SDK; no config params today (no-op).` That line is true about the *request* side and irrelevant to the *response* side, and it contradicts the skill's own `SKILL.md` row 3, which records that the CLI injects `thinking:{type:"adaptive"}` itself. It is the workflow gap that made ten consecutive audits report this axis clear.
- `apps/web-platform/test/server/inngest/cron-shared.test.ts` — `describe("postAnthropicMessage (shared Anthropic transport)")`; `okResponse()` builds a real `Response`. Five fixtures carry no `type`. The `content: []` → `""` case already exists.
- `apps/web-platform/test/server/inngest/cron-weekly-release-digest.test.ts` — three type-less fixtures, including the shared `validAnthropicResponse()` factory at `:131`.
- `apps/web-platform/test/domain-router.test.ts` — `describe("routeMessage classify (auto) path")`; its fixtures already carry `type: "text"`.
- `scripts/followthroughs/compound-promote-outcome-8281.sh` — the existing probe that field-isolates outcome rows on `.fn` (so an issue-body echo of the marker name cannot satisfy it) and requires `trigger == "cron"`, which is why the manual fire below cannot close #8281 and is not asked to.
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` § `SOLEUR_COMPOUND_PROMOTE_OUTCOME` — the post-deploy query recipe.

**Test command (single file):** `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-shared.test.ts`. The in-package binary form is deliberate — the repo root `package.json` declares no `workspaces` field (verified: `grep -c '"workspaces"' package.json` → 0), so `npm run -w apps/web-platform …` aborts with `No workspaces found`. Shell arm: `bash scripts/compound-promote.test.sh`.

**Vitest project split — worth knowing before running the gates.** `vitest.config.ts` defines three projects. `cron-shared.test.ts` and `domain-router.test.ts` are collected by `unit` (`include: ["test/**/*.test.ts", …]`), while `cron-weekly-release-digest.test.ts` is a member of `REPO_WIDE_SUITES` (`test/repo-wide-suites.ts:83`) and therefore runs in the `repo-wide` project, excluded from `unit`. A path-filtered `vitest run` spans both, so the AC8 command is correct as written — but the two halves are gated differently in CI, and only `repo-wide` always runs. This plan adds **no new test file**, so `test/repo-wide-containment.test.ts` (which recomputes that membership from disk) needs no update; adding one later would.

**Type-widening check (`hr-type-widening-cross-consumer-grep`).** The widened shape is a local `as` cast inside `postAnthropicMessage`'s body, not an exported type (`grep -rn "content?: Array" apps/web-platform/server` → exactly one site, `_cron-shared.ts:629`), and the function's public return type `{ text: string; stopReason?: string }` is unchanged. Of the three call sites, two destructure `{ text, stopReason }` (`cron-weekly-release-digest.ts:259`, `cron-compound-promote.ts:901`) and the credit probe destructures nothing at all — a bare `await postAnthropicMessage(…)` discarding the whole return value. No consumer edit follows.

**Skill-description budget (Phase 1.8).** The `model-launch-review` edit touches a table cell in the SKILL.md **body** and one `echo` line in its script — not the `description:` frontmatter — so the cumulative `SKILL_DESCRIPTION_WORD_BUDGET` check does not fire.

**Institutional learnings applied.**

- `2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md` — a fixture that does not match the shape the code under test sees passes vacuously; the type-less `{ text }` fixtures are exactly why a green suite could not see this bug.
- `2026-02-22-model-id-update-patterns.md` — a model swap changes shape; grep every reader, independently of the issue's inventory. This plan's own first pass violated it and plan-review caught it.

**Scoped advisor consult (ADR-083, Step 4.5).** Two changes adopted: fixture normalization is sequenced **before** the helper change (it is backward-compatible with the index-0 picker, so the new case becomes the single red signal instead of eight simultaneous reds), and the post-deploy read captures `stop_reason` so a `max_tokens` truncation mid-thinking is not misread as "the fix did not work". A third suggestion (`filter(text).join("")` for `find`) was declined — DC1.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #8392) | Reality | Plan response |
|---|---|---|
| "fixture `[{type:"text",...}]` unchanged" | The repo's fixtures for this helper and the digest are `[{ text: … }]` with no `type` key. A strict `type === "text"` picker returns `""` for them, so five cron-shared cases and the digest's shared happy-path factory would go red for the wrong reason. | Normalize the eight fixtures to `{ type: "text", text: … }` (the real wire shape) **first**, in their own green commit — `okResponse(body: unknown)` and `validAnthropicResponse` both `JSON.stringify` an untyped object, so no excess-property check fires and the added key is inert under the current picker. |
| "`domain-router.ts:181` already does it right … but only checks index 0" | Correct, and it pins Haiku 4.5 — latent, not live. | Fold in (one line + one test). Same class, behavior-neutral today, and `model-launch-review` swaps model IDs without re-reading parsers — which is precisely how this defect was born. |
| "Blast radius: callers of `postAnthropicMessage`" | Under-counts the class. The shape has two more readers outside `apps/`, one of them (`scripts/compound-promote.sh:231`) live-broken on `claude-sonnet-5`. | Widen to the repo-wide census and fold both `jq` one-liners in. "Deferred items: none" is now true rather than assumed. |
| "Type the block union (`{type: string; text?: string}`)" | The helper's cast is `Array<{ text?: string }>`; `domain-router.ts:178` already spells it `Array<{ type: string; text?: string }>`. | Adopt the sibling's non-optional spelling. The cast is erased, so neither form can throw at runtime — the tiebreak is that the two copies of this parse should read identically. |

## Open Code-Review Overlap

None — 65 open `code-review` issues scanned by body against every planned path; zero matches.

## Proposed Solution

`apps/web-platform/server/inngest/functions/_cron-shared.ts`:

```ts
const data = (await resp.json()) as {
  content?: Array<{ type: string; text?: string }>;
  stop_reason?: string;
  // ...usage/model unchanged
};
// ...
// Sonnet 5 (EXECUTION_MODEL since #5849) runs adaptive thinking when `thinking`
// is omitted, so the first block is a thinking block and the structured-output
// text follows it. Take the first text block; an empty or thinking-only
// response still yields "" so every caller's empty-guard keeps its meaning (#8392).
const text = data.content?.find((b) => b.type === "text")?.text ?? "";
return { text, stopReason: data.stop_reason };
```

`apps/web-platform/server/domain-router.ts` — the mirrored inline copy:

```ts
const text = data.content.find((b) => b.type === "text")?.text ?? "";
```

…and widen its NOTE comment from *"Mirror any request-contract change (header version, `output_config` shape, new required field) in BOTH places"* to cover **response-parse** changes too, naming content-block ordering as the example. Every example the NOTE currently lists is request-side, which is exactly why the two copies drifted silently.

`scripts/compound-promote.sh` and `scripts/learning-retrieval-bench.sh` — the same pick in `jq`:

```bash
jq -r 'first(.content[] | select(.type == "text") | .text) // empty'
```

`plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` — replace the `(no-op)` claim with a request-vs-response split and print the census, so the next model launch re-reads the readers:

```bash
echo "  - thinking-API shape: REQUEST side is a no-op (config sets no thinking params)."
echo "    RESPONSE side is NOT: a thinking-by-default model puts a thinking block FIRST,"
echo "    so any reader indexing a fixed content position silently returns empty (#8392)."
# Reuse this script's own scan convention — see the reject conditions below.
```

**The census must route through the script's existing `$ROOT`-relative scan, not a bare `grep`.** Every other scan in `audit-models.sh` resolves paths against `$ROOT` (set from `git rev-parse --show-toplevel`, overridable by `--root DIR`, which `plugins/soleur/test/model-launch-review.test.ts` uses), and the `collect_config_hits` helper already implements the convention this census needs: it discriminates grep `rc 1` (no match — genuinely clean) from `rc >= 2` (the scan itself failed) and prints `audit-models: scan FAILED (grep rc=$rc) under '$ROOT' — refusing to report clean.` rather than a green. A bare `grep … apps scripts || echo "no fixed-position readers"` would be **cwd-relative**, so under `--root DIR` or from any other working directory it scans nothing, exits 1, and prints a clean verdict that means "the scan ran nowhere" — reintroducing the exact vacuity class this whole plan is about. Reuse the helper (or mirror its rc-discrimination and `"$ROOT"` anchoring verbatim); the existing `EXCLUDE_RE` already filters `/test/`, `knowledge-base/` and `/model-launch-review/`, so the census cannot report itself.

## Files to Edit

- `apps/web-platform/server/inngest/functions/_cron-shared.ts` — widen the response cast; first-text pick; citing comment.
- `apps/web-platform/server/domain-router.ts` — first-text pick; widen the NOTE's change-class wording.
- `scripts/compound-promote.sh` — the `jq` pick at `:231`.
- `scripts/learning-retrieval-bench.sh` — the `jq` pick at `:360`.
- `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` — replace the thinking-API `(no-op)` line with the request/response split + census.
- `plugins/soleur/skills/model-launch-review/SKILL.md` — one sentence in the item-3 row: a model swap can change response block ordering; re-read every `data.content` reader.
- `apps/web-platform/test/server/inngest/cron-shared.test.ts` — five fixtures normalized (Phase 1); two cases added (Phase 2), both RED before the fix.
- `apps/web-platform/test/server/inngest/cron-weekly-release-digest.test.ts` — three fixtures normalized (Phase 1), including the shared `validAnthropicResponse()` factory.
- `apps/web-platform/test/domain-router.test.ts` — one case added (Phase 2).
- `scripts/compound-promote.test.sh` — two rows:
  1. A thinking-first variant of `make_mock_curl`. That helper currently hardcodes `{"content":[{"type":"text","text":"[]"}]}` (anchor: `# Emit a canned Anthropic response: empty clusters array.`), so **parameterize the body** rather than adding a second near-copy. The row must assert the parse path was actually reached — the harness has arms (pre-pass, week-cap, no-config) where curl is never called, so a bare `exit 0` assertion would pass on a short-circuit. Assert that the `$CURL_CAPTURE` file exists, and use a **non-empty** cluster payload so the outcome is distinguishable from a legitimate `no-qualifying-clusters` (the current `"[]"` body makes those two states identical).
  2. A `jq`-parity row covering the fourth reader behaviorally: extract the `jq` program from `scripts/compound-promote.sh:231` and `scripts/learning-retrieval-bench.sh:360`, assert they are byte-identical, and run it once against a thinking-first body expecting the JSON text. One row closes the bench — which otherwise receives a production edit with zero behavioral coverage — and retires AC3's reliance on spelling for the shell arm.

## Files to Create

None. (`decision-challenges.md` and `tasks.md` under `knowledge-base/project/specs/<branch>/` are pipeline-written planning artifacts, not deliverables.)

## Implementation Phases

Phase order is load-bearing: fixture normalization is backward-compatible with the current picker, so it lands green first and leaves the new cases as the only red signal. Every new test lands in Phase 2, **before** any production expression changes, so each has a real RED transcript (`cq-write-failing-tests-before` applies per surface, not once per PR).

1. **Fixture normalization.** Add `type: "text"` to the eight type-less fixtures in `cron-shared.test.ts` and `cron-weekly-release-digest.test.ts`. Run both files — green under the *unchanged* readers.

   **The green run is not this phase's instrument, and must not be claimed as one.** `okResponse(body: unknown)` (`cron-shared.test.ts:902`) and `validAnthropicResponse` (`cron-weekly-release-digest.test.ts:131`) both `JSON.stringify` an untyped object and the reader touches only `[0].text`, so no excess-property check exists and the added `type` key is unobservable by construction — the suite *cannot* go red here. The real instrument is **AC4's `rg -UP` count going 8 → 0**, which has a measured known-positive baseline. Credit that; treat the green run as sequencing hygiene.
2. **RED, all surfaces.** Add: two cases to `cron-shared.test.ts`; the thinking-first classify case to `domain-router.test.ts`; the two rows to `compound-promote.test.sh`. Run all four files — **every new case is RED**, including the thinking-only one (see AC1: its fixture carries a decoy `text` on the thinking block precisely so it discriminates position-indexing from type-selection).
3. **GREEN.** Apply all four production picks (helper, domain-router, the two `jq` one-liners) plus the NOTE widening. Re-run — every file green, no other case disturbed.
4. **Workflow-gap fix.** Apply the `audit-models.sh` and `model-launch-review/SKILL.md` edits; run `bash plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` and confirm the `[3]` block prints the census instead of `(no-op)`.
5. **Per-file gates, run in-session** (the hooked `test-all.sh` flock may queue behind sibling worktrees; the standing decision is rely-on-CI — commit with `LEFTHOOK=0` and disclose it in the PR body): the three vitest files, `bash scripts/compound-promote.test.sh`, `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`, and `./node_modules/.bin/eslint server/inngest/functions/_cron-shared.ts server/domain-router.ts`.
6. **Ship-time.** Sync via rebase (rename-guard #8348), regenerate `knowledge-base/INDEX.md` with `bash scripts/generate-kb-index.sh` before merge (a stale index reds main's AC17), `Closes #8392` in the PR body.
7. **Post-deploy verification (runs inside the `soleur:postmerge` pipeline phase — every step is a command the pipeline executes; nothing is handed off).** Gate on the DEPLOY arm and `/health` `build_sha == merge sha` (not the push-arm build), polled with `Monitor`. Fire `bash plugins/soleur/skills/trigger-cron/scripts/trigger.sh --event cron/compound-promote.manual-trigger --config prd` once, then read the run's `SOLEUR_COMPOUND_PROMOTE_OUTCOME` row via the `betterstack-log-query.md` recipe together with its `SOLEUR_CLAUDE_COST` row and `stop_reason`. Paste the captured row into the PR body, and post it as a comment on #8281.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing — the affected surfaces are the weekly self-improvement cron (which proposes skill/rule edits as PRs), the weekly release digest (a Discord post), and two operator-runnable scripts. A regression returns the digest to its deterministic fallback text and the promoter to `no-qualifying-clusters`: the exact state production has occupied since 2026-07-01.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no new exposure vector — the change reads one more field of a response the process already holds. No new logging, no new payload leaves the process; the existing redaction (`formatTailForSentry`, redact-then-throw) is untouched.
- **Brand-survival threshold:** `none`
- `threshold: none, reason: the touched server paths are cron-side response parsers with no request-path, auth, or tenant-data surface; the domain-router line is behavior-neutral for its pinned Haiku 4.5 model and only changes which index a text block is read from.`

## Observability

This block is required by `hr-observability-as-plan-quality-gate` because Files-to-Edit touches `apps/*/server/`. The change adds no new error path, log line or failure mode — it makes an existing silent-fallback signal trustworthy. Every layer citation below is to already-shipped instrumentation.

```yaml
liveness_signal:
  what: "Sentry cron monitor check-in for cron-compound-promote and cron-weekly-release-digest (postSentryHeartbeat, untouched) plus the per-run SOLEUR_COMPOUND_PROMOTE_OUTCOME WARN marker (emitOutcomeMarker, PR #8344)"
  cadence: "weekly (0 0 * * 0 for compound-promote; the digest's own weekly schedule) and on every manual-trigger fire"
  alert_target: "Sentry cron monitor missed/failed check-in -> operator email; outcome marker rows -> Better Stack app_container_warn_filter source"
  configured_in: "apps/web-platform/server/inngest/functions/cron-compound-promote.ts (emitOutcomeMarker call sites), apps/web-platform/server/compound-promote-marker.ts, apps/web-platform/server/inngest/functions/_cron-shared.ts (postSentryHeartbeat)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN — reportSilentFallback(feature: cron-compound-promote, op: anthropic-cluster) on 'Empty Anthropic response' / 'Malformed Anthropic JSON'; the digest's curate step mirrors its throw to Sentry"
  fail_loud: "A run emitting BOTH a SOLEUR_CLAUDE_COST row with output_tokens > 0 AND a reportSilentFallback 'Anthropic returned empty content' on the same inngest.run_id is the pre-fix signature; after this fix that pair must not co-occur"

failure_modes:
  - mode: "Parser regresses (text block not found) — model answer billed and discarded again"
    detection: "SOLEUR_CLAUDE_COST output_tokens > 0 on the same inngest.run_id as reportSilentFallback('Empty Anthropic response'); the cron-shared.test.ts thinking-first case reds in CI before merge"
    observability_layer: "Layer 1 (Inngest sentry-correlation middleware tags the capture with inngest.run_id/fn_id) + Layer 2 (pino -> Sentry mirror carries the SOLEUR_CLAUDE_COST WARN) + Layer 3 (Vector ships the WARN line to the Better Stack app-container source, where the marker is queried)"
    alert_route: "Sentry issue (feature: cron-compound-promote) -> operator email; CI red blocks merge"
  - mode: "Anthropic returns a genuinely empty content array (refusal / upstream fault)"
    detection: "Same reportSilentFallback path, now a TRUE positive; outcome marker status=no-qualifying-clusters with clusters_proposed=0 and no SOLEUR_CLAUDE_COST output tokens"
    observability_layer: "Layer 1 (scope tags + final-error capture) + Layer 2 (pino -> Sentry breadcrumb for the outcome marker)"
    alert_route: "Sentry issue -> operator email (unchanged behavior, now trustworthy)"
  - mode: "Digest falls back to deterministic text despite a healthy model answer"
    detection: "In prod, the Discord post carries the deterministic fallback copy while the run's SOLEUR_CLAUDE_COST shows output tokens; pre-merge, the normalized digest fixtures run the existing happy-path suite through the new picker"
    observability_layer: "Layer 1 (the curate step's throw is captured with inngest.run_id) + Layer 2 (the step's logger.warn mirrors as a breadcrumb)"
    alert_route: "Sentry event from the curate step's catch -> operator email"
  - mode: "A shell arm (compound-promote.sh / learning-retrieval-bench.sh) regresses"
    detection: "compound-promote.sh exits 1 with '::error::Anthropic API returned empty content' (scripts/compound-promote.sh:233) in the invoking session; scripts/compound-promote.test.sh reds in CI"
    observability_layer: >-
      Layer 7 (self-hosted CLI synchronous consumer), accepted here as EPHEMERAL-ONLY — an
      explicit, reasoned exception to layer 7's usual stdout+durable-artifact pairing, not an
      oversight. Verified: `grep -rn 'compound-promote.sh\|learning-retrieval-bench.sh' .github/`
      returns zero, so no scheduler invokes either script and layers 1-6 genuinely do not reach
      them. Three reasons the durable half is not required: (1) `cron-compound-promote.ts` is a
      byte-for-byte TS port and its own header records that the .sh "remains on disk for
      operator-local" use — the DURABLE arm for this feature is the Inngest cron's outcome
      marker, which layers 1-3 already cover; (2) the shell arm's failure is a loud non-zero
      exit, the opposite of the silent-fallback class this plan exists to fix, so an operator
      cannot miss it in the session that ran it; (3) adding artifact-writing to an
      operator-local script would be new machinery with no property behind it (Cut List).
    alert_route: "Non-zero exit in the invoking session; CI red blocks merge"

logs:
  where: "Better Stack app-container pino source (WARN markers: SOLEUR_CLAUDE_COST, SOLEUR_COMPOUND_PROMOTE_OUTCOME); Sentry for reportSilentFallback events"
  retention: "Better Stack 30d (the window the evidence was read from); Sentry per-project retention (90d)"

discoverability_test:
  command: >-
    bash -c 'doppler run -p soleur -c prd_terraform -- bash scripts/betterstack-query.sh
    --since 30d --grep SOLEUR_COMPOUND_PROMOTE_OUTCOME --limit 50
    | jq -R -r "fromjson? | (.raw|fromjson?).message
    | select(type == \"object\" and .SOLEUR_COMPOUND_PROMOTE_OUTCOME == true
    and .fn == \"cron-compound-promote\") | .status" | wc -l'
  expected_output: "a count >= 1 — at least one decoded outcome row is readable, proving an operator can see what this cron DID without SSH. Exactly one passing condition; 0 is a fail (the channel is dark)."
  credentials_required: "BETTERSTACK_QUERY_HOST / BETTERSTACK_QUERY_USERNAME / BETTERSTACK_QUERY_PASSWORD (read-only Logs SQL) — the property is the content of warehouse rows, which have no unauthenticated read path"
```

## Domain Review

**Domains relevant:** none

No cross-domain implications — infrastructure/tooling change. No UI-surface file appears in Files to Edit or Files to Create, so the Product/UX gate does not fire. The `soleur:engineering:cto` devex lens was run as part of plan-review (findings folded in: the `model-launch-review` workflow-gap fix and the NOTE widening).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1. `cron-shared.test.ts` contains two cases, **both RED against `origin/main`'s helper** (transcripts in the PR body):
  1. fixture `[{ type: "thinking", thinking: "" }, { type: "text", text: '{"clusters":[]}' }]` → `result.text === '{"clusters":[]}'`. Old reader yields `""`.
  2. fixture `[{ type: "thinking", thinking: "", text: "must-not-be-read" }]` → `result.text === ""`. Old reader yields `"must-not-be-read"`.

  The decoy `text` on the thinking block in (2) is a **deliberate synthetic discriminator, not a wire shape** — the API never sends it. Without it the case is vacuous: a bare `[{ type: "thinking", thinking: "" }]` has no `text` key, so `content?.[0]?.text ?? ""` and `find(...)?.text ?? ""` both return `""` and it kills no mutant the existing `content: []` case does not already kill. With it, the case pins the actual property — *selection is by type, not by position* — and reds both the index-0 mutant and a `!== "text"` inversion.
- [ ] AC2 (repo-wide census, not enumeration). **No** reader anywhere in the repo indexes a fixed content position. Verified command — measured at plan time, where it returns exactly the **four** sites this plan fixes, so it is known to be capable of going red:

  ```bash
  grep -rn 'content\[0\]\|content?\.\[0\]' --include=*.ts --include=*.sh --include=*.mjs --include=*.js \
    apps plugins scripts .github | grep -viE 'test|\.md:'
  ```

  Must return **0** on the branch. **Superseded at review** by
  `scripts/lint-anthropic-content-position.py`, which strips comment lines before
  matching — this raw grep does not, so the moment a fix must both ASSERT a literal
  and DOCUMENT it, the prose satisfies the assertion (`cq-assert-anchor-not-bare-token`).
  Measured: it fired once on this branch, on the comment explaining the fix. This quantifies over the tree rather than the file list, so a reader the plan never inventoried is still caught — which is exactly how `scripts/compound-promote.sh` was found. It needs no comment-stripping because it matches the expression, and the prescribed comments describe the shape in prose (`the first block is a thinking block`) rather than reproducing the token.

  **Self-reference is avoided by escaping, and that is load-bearing.** Phase 4 adds this same census *into* `audit-models.sh`, inside `plugins/` — which AC2 searches. It does not self-match because the script carries the pattern as the regex literal `content\[0\]` (with backslashes), while AC2's pattern matches the plain text `content[0]`. Verified at plan time against a scratch tree containing only the new script: the census returns no rows. A future edit that "simplifies" the audit script's grep to an unescaped pattern would silently red AC2 — keep the escapes.
- [ ] AC3 (anchor, not whole-expression). Each of the four readers selects by type: `grep -c 'b.type === "text"' apps/web-platform/server/inngest/functions/_cron-shared.ts apps/web-platform/server/domain-router.ts` → `1` each, and `grep -c 'select(.type == "text")' scripts/compound-promote.sh scripts/learning-retrieval-bench.sh` → `1` each. Anchored on the discriminating sub-expression rather than the full call spelling so a legal reformat does not red it (`cq-assert-anchor-not-bare-token`). This is a cheap spelling pin, **not** the gate — the behavioral gates are AC1, AC6 and AC2.
- [ ] AC4. No Anthropic response fixture under `apps/web-platform/test/` builds a content block without `type`. Verified command — returns exactly the **8** fixtures this plan normalizes today, and must return 0 on the branch:

  ```bash
  rg -UP -c 'content: \[\s*\{(?![^}]*type:)' apps/web-platform/test/
  ```

  The PCRE negative-lookahead form is deliberate: it matches across line breaks, so it covers both the inline `content: [{ text: … }]` shape and the multi-line block, and — unlike a `grep -A<N>` window — it cannot be defeated by a reformat that moves `text:` one line further down. MCP tool-result reads (`result.content[0].text`) are a read, not a fixture construction, and are excluded by AC2's `test` filter.
- [ ] AC5. The existing `content: []` → `{ text: "", stopReason: "end_turn" }` case passes unchanged, and the existing `POSTs to the messages endpoint … returns {text, stopReason}` case — now carrying `type: "text"` — still asserts its text verbatim.
- [ ] AC6. `test/domain-router.test.ts` has a thinking-first classify case resolving `{ leaders: ["cmo"], source: "auto" }`, RED before the one-line change — and discriminating, because the old reader yields `""`, `JSON.parse("")` throws, and the catch falls back to `["cpo"]` (`domain-router.ts:195`). `scripts/compound-promote.test.sh` has both rows from Files to Edit, and the thinking-first row asserts the `$CURL_CAPTURE` file exists (proving the parse path was reached, not short-circuited by a pre-pass/week-cap/no-config arm) plus a sentinel from a **non-empty** cluster payload.
- [ ] AC7. `bash plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` prints, under `[3]`, the request-vs-response split and the census output — and does **not** print the string `no-op` on the thinking-API line: `bash …/audit-models.sh 2>&1 | grep -c 'thinking-API shape.*no-op'` → `0`. **Measured baseline:** that same command returns `1` on `origin/main` today, so the `0` is known to be capable of failing. Additionally, running the script with `--root <a scratch dir containing one fixed-position reader>` must report that reader rather than a clean verdict — the check that the census is `$ROOT`-anchored rather than cwd-relative.
- [ ] AC8. `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-shared.test.ts test/server/inngest/cron-weekly-release-digest.test.ts test/domain-router.test.ts` exits 0; `bash scripts/compound-promote.test.sh` exits 0; `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` reports no error. (This AC claims only the per-file gates it actually runs — the full-battery claim is CI's.)
- [ ] AC9. `knowledge-base/INDEX.md` regenerated by `bash scripts/generate-kb-index.sh` is byte-identical to the committed copy at merge time (`git diff --exit-code knowledge-base/INDEX.md` → clean), and the PR body carries `Closes #8392` plus the `LEFTHOOK=0` disclosure with the AC8 gate output.

### Post-merge (pipeline-executed, `soleur:postmerge`)

- [ ] AC10 (REWRITTEN at review — the original was unfalsifiable three ways, all
  measured). One fire of `cron/compound-promote.manual-trigger` on `prd`, gated on the
  DEPLOY arm and `/health` `build_sha == merge sha`, produces a run whose
  `SOLEUR_CLAUDE_COST` row carries `output_tokens > 0` AND whose
  `SOLEUR_COMPOUND_PROMOTE_OUTCOME` row for the SAME `run_id` is not accompanied by a
  `Anthropic returned empty content` pino row. Both halves are read from Better Stack
  with `scripts/betterstack-query.sh`; the join key is `run_id`, which the cost marker
  now carries (it previously carried only the cron NAME, so the join was wall-clock only).

  **Why it was rewritten.** (a) The cost marker emitted `id: args.markerSource` — a
  constant — so the prescribed join had no key; `markerRunId` was added. (b) The
  original asserted the ABSENCE of `Anthropic returned empty content` *in Sentry*;
  `reportSilentFallback` passes that string as `safeMessage` to pino only, while Sentry
  receives `captureException(err)` whose message is `Empty Anthropic response` — so the
  assertion matched nothing, ever, and could not go red. (c) It prescribed
  `scripts/sentry-issue.sh --search`, which does not exist (the parser ends
  `-*) unknown flag; exit 64`). Re-basing on Better Stack removes all three.

  Still deliberately NOT the gate: `clusters_proposed > 0`. The model may legitimately
  find nothing, so a pass condition admitting "clusters OR a named status" would admit
  every outcome. `anthropic-truncated` with `stop_reason: max_tokens` is a named,
  observable, different failure and does not falsify this AC.

**Not an acceptance criterion:** posting the captured row to #8281. It is a courtesy to another issue's gate — recorded in Pipeline notes as a Phase 7 step, per the operator's request — and this PR's done-ness does not depend on it. #8281 continues to be graded by `scripts/followthroughs/compound-promote-outcome-8281.sh`, which requires `trigger == "cron"` and is echo-safe (it field-isolates on `.fn`, so a marker name quoted in an issue body cannot satisfy it).

## Test Scenarios

Only scenarios not already stated verbatim in an AC:

- Given a response with a thinking block followed by a text block, when `postAnthropicMessage` is called, then the caller's `if (!text)` guard does **not** fire and `JSON.parse(text)` succeeds.
- Given a response whose only block is `{type:"thinking"}`, when called, then `text === ""` and the caller's empty-guard fires — a genuine empty is still reported as one.
- Given `scripts/compound-promote.sh` receives a thinking-first response body, when it extracts `CLUSTERS_TEXT`, then the value is the JSON cluster payload and the script does not `exit 1`.
- **API verify (post-deploy, credentialed, pipeline-run):**

  ```bash
  doppler run -p soleur -c prd_terraform -- \
    bash scripts/betterstack-query.sh --since 1h --grep SOLEUR_COMPOUND_PROMOTE_OUTCOME --limit 20 \
    | jq -R -r 'fromjson? | . as $r | ($r.raw|fromjson?).message
                | select(type == "object" and .SOLEUR_COMPOUND_PROMOTE_OUTCOME == true and .fn == "cron-compound-promote")
                | [$r.dt, .trigger, (.run_id//"-"), .status, (.corpus_count//"-"),
                   (.clusters_proposed//"-"), (.clusters_opened//"-"),
                   ((.refusals//[])|join(","))] | @tsv'
  ```

  expects one `manual` row. `.run_id` is in the projection deliberately — it is the join key the AC10 Sentry read consumes, and without it the described join has no executable path.

## Context

- The helper is transport-only by design (#5186): it returns `{ text, stopReason }` and every empty/truncated/shape decision stays at the call site. This plan keeps that contract — only the extraction expression changes.
- Sonnet 5 thinking blocks arrive with `display: "omitted"` by default, so the thinking block is `{ type: "thinking", thinking: "" }` — the AC1 fixture is the real wire shape.
- **Plan-review panel disagreements, resolved and recorded:** the simplification panel proposed cutting the `domain-router.ts` test (its Haiku 4.5 fixture cannot occur in prod today). Kept: the case is genuinely RED against the current code, and it is the one mechanical thing that will red when a future model-ID swap makes the scenario live — which is the exact history this plan is fixing. The same panel proposed cutting the digest handler-level test; that one **was** cut (Cut List), because normalizing the digest fixtures already routes its existing happy-path suite through the new picker.
- Deferred items: none. The class is closed repo-wide by AC2.

## Pipeline notes

- Sync via rebase, not merge (rename-guard #8348).
- Regenerate `knowledge-base/INDEX.md` with `bash scripts/generate-kb-index.sh` before merge.
- Hooked commits may queue behind sibling worktrees' `test-all.sh` flock; standing decision is rely-on-CI — `LEFTHOOK=0` after running the per-file gates by hand, disclosed in the PR body.
- Every poll (CI, deploy arm, `/health`) goes through `Monitor`, never a backgrounded poll loop (`hr-monitor-not-run-in-background-for-polling`).
- Phase 7 posts the captured outcome row as a comment on #8281 after pasting it in the PR body.

## References

- Issue: #8392 (closes). Related: #8281 (needs a recorded no-action whose cause is observable), #8293, #8344 (outcome marker through pino), #5849 (EXECUTION_MODEL → claude-sonnet-5), #5186 (helper extraction), #8348 (rename-guard).
- `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` § `SOLEUR_COMPOUND_PROMOTE_OUTCOME`.
- `claude-api` skill, Thinking & Effort table: Sonnet 5 omitting `thinking` runs adaptive; Haiku 4.5 omitting `thinking` runs no thinking.
- Panel decision challenges: `knowledge-base/project/specs/feat-one-shot-8392-anthropic-text-block/decision-challenges.md`.
