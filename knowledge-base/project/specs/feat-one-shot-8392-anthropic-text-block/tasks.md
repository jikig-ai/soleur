# Tasks — fix(cron): postAnthropicMessage reads the first text block, not content[0]

Derived from `knowledge-base/project/plans/2026-09-19-fix-cron-anthropic-first-text-block-plan.md` (post-plan-review).
Branch: `feat-one-shot-8392-anthropic-text-block` · Issue: #8392 · Lane: `cross-domain` (fail-closed; no spec.md)

Phase order is load-bearing. Fixtures normalize first (backward-compatible), all new tests land before any production expression changes so each has a real RED transcript.

## Phase 1 — Fixture normalization (suite stays green)

- [ ] 1.1 `apps/web-platform/test/server/inngest/cron-shared.test.ts` — add `type: "text"` to the five type-less fixtures (anchors: `content: [{ text: "ok" }]` ×2, `content: [{ text: '{"highlights":[]}' }]`, `content: [{ text: "{}" }]` ×2).
- [ ] 1.2 `apps/web-platform/test/server/inngest/cron-weekly-release-digest.test.ts` — add `type: "text"` to the three type-less fixtures, including the shared `validAnthropicResponse()` factory and the multi-line `#5080 fence-stripping regression test` block.
- [ ] 1.3 Run `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-shared.test.ts test/server/inngest/cron-weekly-release-digest.test.ts` — GREEN under the unchanged readers.
- [ ] 1.4 **This phase's real instrument** — verify the AC4 census goes 8 → 0: `rg -UP -c 'content: \[\s*\{(?![^}]*type:)' apps/web-platform/test/`. Do NOT credit 1.3's green run as verification: `okResponse(body: unknown)` and `validAnthropicResponse` both `JSON.stringify` an untyped object and the reader touches only `[0].text`, so the added `type` key is unobservable and the suite cannot go red here.

Note: `cron-weekly-release-digest.test.ts` is a `REPO_WIDE_SUITES` member (`test/repo-wide-suites.ts:83`) and runs in the `repo-wide` vitest project, not `unit`. A path-filtered `vitest run` spans both. No new test FILE is added anywhere in this plan, so `test/repo-wide-containment.test.ts` needs no update.

## Phase 2 — RED, every surface

- [ ] 2.1 `cron-shared.test.ts` — add `it("#8392 — returns the first text block when a thinking block precedes it")`, fixture `[{ type: "thinking", thinking: "" }, { type: "text", text: '{"clusters":[]}' }]`, expect `result.text === '{"clusters":[]}'`. RED (old reader → `""`).
- [ ] 2.2 `cron-shared.test.ts` — add the type-selection pin, fixture `[{ type: "thinking", thinking: "", text: "must-not-be-read" }]`, expect `result.text === ""`. **Also RED** (old reader → `"must-not-be-read"`). The decoy `text` on the thinking block is a deliberate synthetic discriminator, not a wire shape — WITHOUT it the case is vacuous (a thinking block with no `text` key returns `""` under both readers and kills no mutant the existing `content: []` case does not).
- [ ] 2.3 `apps/web-platform/test/domain-router.test.ts` — add a case in `describe("routeMessage classify (auto) path")` with fixture `[{ type: "thinking", thinking: "" }, { type: "text", text: '{"leaders":["cmo"]}' }]`, expect `{ leaders: ["cmo"], source: "auto" }`. RED and discriminating: the old reader yields `""` → `JSON.parse("")` throws → catch falls back to `["cpo"]` (`domain-router.ts:195`).
- [ ] 2.4 `scripts/compound-promote.test.sh` — **parameterize** `make_mock_curl`'s canned body (it currently hardcodes `{"content":[{"type":"text","text":"[]"}]}` at `:147`) rather than adding a near-copy, then add a thinking-first row. The row MUST assert the `$CURL_CAPTURE` file exists — the harness has arms (pre-pass, week-cap, no-config) where curl is never called, so a bare `exit 0` would pass on a short-circuit — and use a **non-empty** cluster payload so the result is distinguishable from a legitimate `no-qualifying-clusters`.
- [ ] 2.5 `scripts/compound-promote.test.sh` — add a `jq`-parity row: extract the `jq` program from `scripts/compound-promote.sh:231` and `scripts/learning-retrieval-bench.sh:360`, assert byte-identical, and run it once against a thinking-first body expecting the JSON text. This is the ONLY behavioral coverage the bench script gets; without it the fourth reader ships on a spelling grep alone.
- [ ] 2.6 Run all four files. **Every new case is RED** — capture all four transcripts for the PR body (AC1, AC6).

## Phase 3 — GREEN, all four readers

- [ ] 3.1 `apps/web-platform/server/inngest/functions/_cron-shared.ts` — widen the response cast to `content?: Array<{ type: string; text?: string }>` (matching `domain-router.ts`'s spelling); replace `return { text: data.content?.[0]?.text ?? "", … }` with the `find((b) => b.type === "text")` pick; add the comment citing #8392 and the adaptive-thinking cause.
- [ ] 3.2 `apps/web-platform/server/domain-router.ts` — replace the index-0 ternary with `data.content.find((b) => b.type === "text")?.text ?? ""`.
- [ ] 3.3 `apps/web-platform/server/domain-router.ts` — widen the NOTE comment's change-class from "Mirror any request-contract change (header version, `output_config` shape, new required field)" to cover **response-parse** changes too, naming content-block ordering as the example. Every current example is request-side, which is why the copies drifted.
- [ ] 3.4 `scripts/compound-promote.sh:231` — `jq -r 'first(.content[] | select(.type == "text") | .text) // empty'`.
- [ ] 3.5 `scripts/learning-retrieval-bench.sh:360` — same `jq` pick.
- [ ] 3.6 Re-run all four test surfaces — every file GREEN, no previously-passing case disturbed.
- [ ] 3.7 Verify the AC2 repo-wide census returns 0: `grep -rn 'content\[0\]\|content?\.\[0\]' --include=*.ts --include=*.sh --include=*.mjs --include=*.js apps plugins scripts .github | grep -viE 'test|\.md:'`.

## Phase 4 — Workflow-gap fix (`wg-when-a-workflow-gap-causes-a-mistake-fix`)

- [ ] 4.1 `plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` — replace the `thinking-API shape: … (no-op).` line under `[3]` with the request-vs-response split plus a fixed-position census.
- [ ] 4.2 **The census MUST route through the script's own `$ROOT`-anchored scan convention**, not a bare `grep`. Mirror `collect_config_hits` (`:128-162`): paths resolved against `"$ROOT"` (set from `git rev-parse --show-toplevel`, overridable by `--root DIR`, which `plugins/soleur/test/model-launch-review.test.ts:274` uses), and rc-discrimination that prints `audit-models: scan FAILED (grep rc=$rc) under '$ROOT' — refusing to report clean.` on rc >= 2. A cwd-relative `grep … apps scripts || echo "clean"` scans NOTHING under `--root` and prints a green meaning "the scan ran nowhere" — the exact vacuity class this plan exists to fix. The existing `EXCLUDE_RE` (`:119`) already filters `/test/`, `knowledge-base/` and `/model-launch-review/`, so the census cannot report itself.
- [ ] 4.3 Keep the census pattern **backslash-escaped** (`content\[0\]`). AC2's repo-wide census matches the plain text `content[0]`, so the escaped literal does not self-match — verified at plan time against a scratch tree. An "simplifying" edit to an unescaped pattern would silently red AC2.
- [ ] 4.4 `plugins/soleur/skills/model-launch-review/SKILL.md` — one sentence in the item-3 row (body table at `:41`, below the frontmatter that closes at `:3`): a model swap can change response block ordering; re-read every `data.content` reader.
- [ ] 4.5 Run `bash plugins/soleur/skills/model-launch-review/scripts/audit-models.sh` and confirm `[3]` prints the census; verify `… 2>&1 | grep -c 'thinking-API shape.*no-op'` → `0` (measured baseline on `origin/main`: `1`, so the 0 is known-capable of failing).
- [ ] 4.6 Run the script with `--root <scratch dir containing one fixed-position reader>` and confirm it REPORTS that reader rather than a clean verdict — the check that 4.2 landed.
- [ ] 4.7 Confirm no `description:` frontmatter changed, so the skill-description word budget is untouched.

## Phase 5 — Per-file gates (run in-session; commit with `LEFTHOOK=0` + disclosure)

- [ ] 5.1 `cd apps/web-platform && ./node_modules/.bin/vitest run test/server/inngest/cron-shared.test.ts test/server/inngest/cron-weekly-release-digest.test.ts test/domain-router.test.ts`
- [ ] 5.2 `bash scripts/compound-promote.test.sh`
- [ ] 5.3 `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`
- [ ] 5.4 `cd apps/web-platform && ./node_modules/.bin/eslint server/inngest/functions/_cron-shared.ts server/domain-router.ts`
- [ ] 5.5 Commit with `LEFTHOOK=0` (sibling-worktree `test-all.sh` flock; standing decision is rely-on-CI) and record the 5.1-5.4 output for the PR body disclosure.

## Phase 6 — Ship

- [ ] 6.1 Sync via **rebase**, not merge (rename-guard #8348).
- [ ] 6.2 `bash scripts/generate-kb-index.sh`; confirm `git diff --exit-code knowledge-base/INDEX.md` is clean before merge.
- [ ] 6.3 PR body: `Closes #8392`, the RED transcripts from 2.5, the `LEFTHOOK=0` disclosure with 5.1-5.4 output, and the rendered `decision-challenges.md` (DC1-DC3).
- [ ] 6.4 Run `soleur:qa` / `soleur:review` per the normal lifecycle before marking ready.

## Phase 7 — Post-deploy verification (pipeline-executed)

- [ ] 7.1 Poll the DEPLOY arm with `Monitor` (never a backgrounded loop) until it completes.
- [ ] 7.2 Confirm `/health` `build_sha == merge sha` — the DEPLOY arm's build, not the push arm's.
- [ ] 7.3 `bash plugins/soleur/skills/trigger-cron/scripts/trigger.sh --event cron/compound-promote.manual-trigger --config prd` — once.
- [ ] 7.4 Read the run's `SOLEUR_COMPOUND_PROMOTE_OUTCOME` row plus its `SOLEUR_CLAUDE_COST` row and `stop_reason` via the `betterstack-log-query.md` recipe. **`.run_id` must be in the `@tsv` projection** — it is the join key 7.5 consumes, and an earlier draft omitted it, leaving the join described but unreachable.
- [ ] 7.5 Assert AC10 with the join actually executed: `doppler run -p soleur -c prd -- bash scripts/sentry-issue.sh --search 'inngest.run_id:<id from 7.4>'`, confirming no event with message `Anthropic returned empty content` while that run's `SOLEUR_CLAUDE_COST` shows `output_tokens > 0`. `clusters_proposed` is recorded, not gated — the model may legitimately find nothing.
- [ ] 7.6 Paste the captured row into the PR body, then post it as a comment on #8281 (not an acceptance criterion — #8281 is graded by `scripts/followthroughs/compound-promote-outcome-8281.sh`, which requires `trigger == "cron"`).
