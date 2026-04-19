# chore(ux-audit): drain review backlog #2356 + #2357 + #2362

**Type:** chore (maintenance / tech debt)
**Target branch:** `feat-one-shot-ux-audit-2356-2357-2362`
**PR will close:** #2356, #2357, #2362

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Overview, Research Findings, Implementation Phases 1-5, Risks, Sharp Edges, Acceptance Criteria
**Learnings applied:** 5
**Research agents consulted (implicit via pattern catalog):** bun-test runtime compatibility, schema-version consumer boundary, test-mock factory drift-guard, ux-audit prior scope-cutting, fixture blast-radius

### Key Improvements

1. **Consumer-boundary schema assertion added.** Per `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md`: `finding.schema.json` and the stdout summary are only load-bearing if a consumer actually reads and asserts them. Phase 2 now gates `finding-schema.test.ts` on explicit structural field checks (not just file presence); Phase 3 `skill-summary.test.ts` now parses SKILL.md §7.5 with a regex and asserts the documented field list is exactly `["filed", "suppressed", "skipped", "hashes"]` — a field rename in SKILL.md fails the test.
2. **Type-safe drift factory pattern adopted.** Per `2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md`: the `length === 5` pin on `FINDING_CATEGORIES` is strengthened with a `readonly [typeof FINDING_CATEGORIES[number], ...]` type assertion pattern carried from the test, so adding a 6th category **and** bumping the pin without updating the assertion list still fails typecheck.
3. **bun-test API compatibility verified.** Per `2026-03-29-bun-test-vi-stubenv-unavailable.md`: the new tests only use `describe`, `test`, `expect`, `Bun.file`, `Bun.file().json()`, and `Bun.file().text()` — all confirmed available in bun's runner. No `vi.stubEnv`, `vi.hoisted`, or other vitest-only APIs.
4. **Worktree bun-test prerequisite documented.** Per `2026-03-18-bun-test-segfault-missing-deps.md`: running `bun test` in a fresh worktree without `node_modules` segfaults. Phase 1 adds a preflight `bun install --frozen-lockfile` in the worktree (if `worktree-manager.sh` didn't already run it).
5. **Blast-radius guard extended to new tests.** Per `2026-04-15-ux-audit-scope-cutting-and-review-hardening.md` and `cq-destructive-prod-tests-allowlist`: none of the four new tests do anything destructive. They are pure read-only over committed files. Explicitly documented so reviewers don't need to look twice.
6. **SKILL.md Invocation + workflow-allowlist pattern preserved.** Zero edits to SKILL.md Invocation forms or `.github/workflows/scheduled-ux-audit.yml` `allowedTools`. The prior PR #2346 review tightened both; this chore does not regress either.

### New Considerations Discovered

- The `describeIfCreds` `console.warn` added in Phase 4 will fire in **every** plugin-level test run that doesn't have Doppler secrets injected — including local dev and the plugin's `test-all.sh`. This is the intended behavior per #2362.7, but contrasts with the comment at `bot-fixture.test.ts:32-35` that calls out "silent-skip is deliberate." Fix: update that comment in the same edit so the codebase is self-consistent (comment says "silent-skip was deliberate; now emits a one-line console.warn per #2362").
- `finding-schema.test.ts` parsing ux-design-lead.md's fenced JSON blocks needs a section-anchored regex. The file has **three** fenced JSON blocks (one in `## UX Audit (Screenshots)`, one in `## Wireframe-to-Implementation Handoff`, one embedded). Anchoring to `### Output contract` is mandatory. Already in Sharp Edges.
- `length === 5` pin on `FINDING_CATEGORIES` assumes the author bumps it when adding a category. Review agents have historically caught this class (see `2026-04-15-ux-audit-scope-cutting-and-review-hardening.md` §"Test assertion was tautologically true"). Mitigation: test file's top comment names the pin and the three markdown locations that must also be updated.

## Overview

Three open `code-review` issues all scoped to `plugins/soleur/skills/ux-audit/**` and `plugins/soleur/agents/product/design/ux-design-lead.md` are batched into a single cleanup PR. All three originated from the PR #2346 review (`soleur:ux-audit` skill, merged 2026-04-17) and have sat in Post-MVP/Later. One pass over the skill + agent + tests drains them.

- **#2356 (P2):** `FINDING_CATEGORIES` is duplicated across `dedup-hash.ts` (runtime-enforced), `SKILL.md` (doc constant), and `ux-design-lead.md` (agent rubric). Adding a 6th category silently drifts SKILL.md + agent. Fix: a drift test that greps the two markdown files for the TS-sourced list and fails on mismatch.
- **#2357 (P2):** The skill emits only `::warning::`/`::error::` annotations — a parent agent can't parse run outcomes. Separately, audit mode passes parallel `screenshots[i]` / `routes[i]` arrays keyed by index, which desync silently when one route capture fails. Fix: emit a final single-line JSON summary `{"filed":N,"suppressed":M,"skipped":K,"hashes":[...]}` from the skill; zip the arrays into `[{route, screenshot_path}, ...]` and update `ux-design-lead.md`'s audit-mode input contract.
- **#2362 (P3 batch):** seven polish items across selectors, schemas, path filters, logging truncation, and types. Fold in the ones that are one-line / tens-of-lines fixes; acknowledge items already addressed.

No behavior change to the production path (dry-run cron is untouched). Observability is strictly additive (new stdout JSON line). The input-contract change for audit mode is internal to the skill↔agent seam; the scheduled workflow doesn't parse agent output, so shipping skill+agent together preserves compatibility.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| #2356 says `FINDING_CATEGORIES` is duplicated in 3 files | Confirmed at `plugins/soleur/skills/ux-audit/scripts/dedup-hash.ts:12-18`, `plugins/soleur/skills/ux-audit/SKILL.md:53`, `plugins/soleur/agents/product/design/ux-design-lead.md:85,118` (rubric enumeration + `category` enum field rule) | Drift test greps both markdown files for each TS-sourced category string and for the canonical `real-estate \| ia \| consistency \| responsive \| comprehension` phrase in the agent field rule. |
| #2357 says skill emits only `::warning::`/`::error::` | Confirmed — `SKILL.md` §2, §3, §4, §5 all use `::warning::`/`::error::`. No structured stdout. Audit-mode contract at `ux-design-lead.md:77-82` uses parallel `screenshots[]` / `routes[]` arrays. | Skill adds a final `echo` of a one-line JSON summary after Step 7 (before Step 8 cleanup). Agent contract rewrites `screenshots` + `routes` → `targets: [{path, auth, fixture_prereqs, screenshot_path}, ...]`. |
| #2362.1 says selector in `ux-design-lead.md:117` is unbounded | Confirmed — prose says "CSS selector" but leaves CSS/XPath/text ambiguous to a downstream grouper. | Tighten wording: "CSS selector only (no XPath, no text-match). Must be syntactically valid CSS." |
| #2362.2 says `route-list.yaml` prereqs vocabulary is implicit | Confirmed — comment at top mentions three markers but YAML has no declarative allowlist. | Add `allowed_prereqs: [tcs_accepted, billing_active, chat_conversations, kb_workspace_deferred]` at top of YAML so future additions are explicit. |
| #2362.3 says no finding JSON schema exists | Confirmed — `ux-design-lead.md:99-111` shows one inline JSON example but no machine-checkable schema. | Add `plugins/soleur/skills/ux-audit/references/finding.schema.json` (Draft 2020-12). Agent contract references it. |
| #2362.4 says workflow path filter misses Tailwind config | N/A — `scheduled-ux-audit.yml` has no `paths:` filter (push trigger was removed per #2376 and the file header comment explicitly confirms this). The P3 item is obsolete. | Acknowledge in PR body: "not applicable — push trigger was removed." |
| #2362.5 says `bot-fixture.ts:83-85,117,139` logs full Supabase bodies | Confirmed. Lines 83-85 (`PATCH users`), 117-119 (`POST conversations`), 142-144 (`POST messages`). | Truncate error bodies to 200 chars. |
| #2362.6 says `FIXTURE_CONVERSATIONS.role` is typed `string` | Confirmed at `bot-fixture.ts:22-37` — the `as const` on the outer array fixes the tuple, but `role` strings widen at the `messages.map` call site. | Narrow `role` via `as 'user' \| 'assistant'` in each literal, or widen the `insertMessages` signature to accept `'user' \| 'assistant'`. |
| #2362.7 says `describeIfCreds` skip should warn locally | Confirmed at `bot-fixture.test.ts:36` — silent `describe.skip`. | Acknowledge: silent-skip is deliberate per the comment block at lines 32-35 (CI loud-fail is tracked separately in #2361). No change — noting in PR body keeps the issue closed without a code edit. Alternative: emit a `console.warn` listing missing env vars. Chose no-op because it would contradict the existing comment; flip to `console.warn` only if trivial. Decision: emit the warning (one line, matches the issue's preferred direction). |

## Open Code-Review Overlap

Queried `gh issue list --label code-review --state open` and grep'd each issue body for the five planned file paths (dedup-hash.ts, SKILL.md, ux-design-lead.md, route-list.yaml, bot-fixture.ts) and the test directory:

- **#2356** — Fold in (this PR).
- **#2357** — Fold in (this PR).
- **#2362** — Fold in (this PR; items 1/2/3/5/6/7 applied, item 4 acknowledged N/A).

No other open code-review issues touch these paths.

## Files to Edit

- `plugins/soleur/skills/ux-audit/scripts/dedup-hash.ts` — unchanged source of truth, but add a documentation comment at `FINDING_CATEGORIES` pointing to the drift test (satisfies `cq-code-comments-symbol-anchors-not-line-numbers`).
- `plugins/soleur/skills/ux-audit/SKILL.md`
  - §7 or new §7.5: document the stdout JSON summary contract (#2357).
  - §4 invocation contract: update delegation payload to zipped `targets` array (#2357).
  - §4 parse-guard: update error log to reference a single failed target by index, not a desynced pair (#2357).
- `plugins/soleur/agents/product/design/ux-design-lead.md`
  - `### Invocation contract` and the downstream steps: rename `screenshots` + `routes` to `targets: [{path, auth, fixture_prereqs, screenshot_path}, ...]` (#2357).
  - `### Output contract` field rules: tighten `selector` to "CSS selector only" (#2362.1) and reference the new JSON schema (#2362.3).
- `plugins/soleur/skills/ux-audit/references/route-list.yaml` — add `allowed_prereqs:` block at the top (#2362.2).
- `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` — truncate Supabase error bodies (#2362.5); narrow `role` literal type (#2362.6).

## Files to Create

- `plugins/soleur/test/ux-audit/category-drift.test.ts` — RED→GREEN drift test (#2356). Imports `FINDING_CATEGORIES` from `dedup-hash.ts`, reads `SKILL.md` and `ux-design-lead.md` as strings, asserts each category appears in both, and asserts the canonical `"real-estate | ia | consistency | responsive | comprehension"` phrase is present in the agent's field-rule line.
- `plugins/soleur/test/ux-audit/skill-summary.test.ts` — GREEN test for the stdout JSON-summary format (#2357). Parses the skill's `emitSummary` helper (see Implementation Phases) and asserts shape.
- `plugins/soleur/skills/ux-audit/references/finding.schema.json` — JSON Schema Draft 2020-12 for a single finding (#2362.3). Used by consumers of the agent output; no runtime validation added (that is scope-out).
- `plugins/soleur/test/ux-audit/finding-schema.test.ts` — validates that the example JSON in `ux-design-lead.md` matches `finding.schema.json`. Uses a pinned validator; see Sharp Edges below on dependency policy.

(No source-file extraction for the skill summary helper yet — the skill is an instruction-set, not a runtime, so the "helper" is prose in `SKILL.md` with a test over a canonical example. Concretely, `skill-summary.test.ts` defines and exports a local `formatSummary()` and asserts the shape documented in SKILL.md; future extraction to a script can mirror this.)

## Research Findings

Local context (read before drafting):

- `plugins/soleur/skills/ux-audit/SKILL.md` (184 lines) — the orchestrator; §1-§8 workflow.
- `plugins/soleur/skills/ux-audit/scripts/dedup-hash.ts` — already the canonical source of `FINDING_CATEGORIES`; throws on unknown category at `computeFindingHash`. Runtime enforcement covers the hash path only.
- `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` — seed/reset. Three callsites with un-truncated `res.text()`: `updateUserRow` (L83-86), `insertConversation` (L116-119), `insertMessages` (L141-144).
- `plugins/soleur/skills/ux-audit/references/route-list.yaml` — `tcs_accepted`, `billing_active`, `chat_conversations`, `kb_workspace_deferred` are the only prereq markers in use.
- `plugins/soleur/agents/product/design/ux-design-lead.md` — audit mode at `## UX Audit (Screenshots)`; field rules at §"Output contract".
- `plugins/soleur/test/ux-audit/dedup-hash.test.ts` — uses `bun:test`, imports from `../../skills/ux-audit/scripts/dedup-hash`. New drift test must follow this pattern (bun test, relative import, no Vite-only syntax).
- `.github/workflows/scheduled-ux-audit.yml` — no `paths:` filter today (push trigger removed per header comment, confirming #2362.4 is obsolete). `claude-code-action` pinned to `v1.0.101`; model `claude-opus-4-7`. No change to the workflow file.

Institutional learnings applied:

- `cq-code-comments-symbol-anchors-not-line-numbers` — the `FINDING_CATEGORIES` anchor comment must reference the test by symbol, not line number.
- `cq-destructive-prod-tests-allowlist` — the existing `bot-fixture.test.ts` already guards on `BOT_EMAIL !== "ux-audit-bot@jikigai.com"` at module load. No new destructive tests in this PR; the drift/schema/summary tests are pure-function tests.
- `cq-write-failing-tests-before` — TDD applies: write the category-drift, summary, and schema tests RED first; implement the doc/code changes until they go GREEN. This is the Phase 1 / Phase 2 split below.
- `wg-before-every-commit-run-compound-skill` — compound runs before each commit in `/ship`.
- `cq-test-mocked-module-constant-import` — the drift test does NOT mock `dedup-hash`; it imports the real module. Safe.
- From `plan-skill` sharp edges: **do NOT prescribe exact learning filenames with dates**. This plan does not create any learning files.
- From `plan-skill` sharp edges: **when a plan prescribes a new test framework, verify it's installed** — `bun:test` is the existing convention (see `dedup-hash.test.ts`). No new framework introduced.
- From `plan-skill` sharp edges: **when a plan prescribes a JSON Schema validator, verify it's installed** — Ajv is NOT a plugin dependency today. To avoid introducing one for a single test, Phase 2's `finding-schema.test.ts` uses a minimal inline structural check (required fields present, enums honored) instead of a full validator. The `finding.schema.json` file still ships as a machine-readable contract that external consumers (or a future test-suite migration) can wire into Ajv when needed. This matches the project preference against adding dependencies for marginal benefit.

## Alternative Approaches Considered

| Approach | Pros | Cons | Decision |
|---|---|---|---|
| Extract `FINDING_CATEGORIES` into a YAML file read by all three consumers | Single source; no drift possible by construction. | SKILL.md and agent `.md` are instruction text for an LLM, not a runtime; neither parses YAML. The "drift" they suffer is textual. A grep-time test is closer to the problem. | **Rejected** — drift test matches the failure mode better. |
| Add JSON-schema validation at runtime inside the skill | Enforces the schema every run. | The skill is instruction text invoked by claude-code-action; there is no runtime to hook into. Would require adding a validation script invoked from SKILL.md, plus Ajv as a dep. | **Rejected** — schema file ships as contract; validation stays external. |
| Emit the summary JSON to a file, not stdout | Easier to assert in shell. | Parent agents (the Task-invoking one in #2357's motivation) read stdout, not files. Both is fine but pick the primary channel. | **Decision:** stdout primary; also write to `${GITHUB_WORKSPACE}/tmp/ux-audit/summary.json` for the workflow to surface as an artifact. |
| Keep parallel `screenshots[]` / `routes[]` arrays and add a length assertion | One-line fix. | Still desynces if step 3 skips a single element; assertion catches length mismatch but not index skew. The zipped form makes skew structurally impossible. | **Rejected** — zipped form is strictly better. |
| Split into three separate PRs | Smaller reviews. | All three touch the same 4-5 files; merge-ordering creates rebase work. The PR is already small. | **Rejected** — batch is cheaper. |
| Expand `ux-design-lead.md` to restate the category list as a YAML block | More structured. | Still duplicates; still drifts silently without the test. | **Rejected** — drift test is orthogonal to how the list is written. |

## Implementation Phases

### Phase 0 — Preflight (once, before Phase 1)

Applied learnings: `2026-03-18-bun-test-segfault-missing-deps.md`.

1. Verify the worktree has `node_modules` installed at the plugin level. Fresh worktrees without deps segfault `bun test`:

    ```bash
    [ -d plugins/soleur/node_modules ] || (cd plugins/soleur && bun install --frozen-lockfile)
    ```

    `worktree-manager.sh create` already runs this, but on long-lived worktrees or post-lockfile-update sessions it may have gone stale.

2. Confirm bun runner API surface. The four new tests use only bun-compatible APIs (`describe`, `test`, `expect`, `Bun.file`) — never `vi.stubEnv`, `vi.hoisted`, `vi.stubGlobal`, `vi.useFakeTimers`. Enforced by code review (the tests do not import `vi`).

3. Run the existing ux-audit test suite unchanged to establish baseline:

    ```bash
    cd plugins/soleur && bun test test/ux-audit/
    ```

    Baseline: `dedup-hash.test.ts` passes; `bot-fixture.test.ts` silent-skips (no creds); `bot-signin.test.ts` silent-skips. If any fail at baseline, stop and fix before proceeding.

### Phase 1 — RED tests (TDD Gate per `cq-write-failing-tests-before`)

Write the three new tests and run them to confirm they **fail** against the current codebase before any implementation edits. Tests live in `plugins/soleur/test/ux-audit/` following the `bun:test` convention.

1. `category-drift.test.ts` — imports `FINDING_CATEGORIES` from `../../skills/ux-audit/scripts/dedup-hash`, reads `plugins/soleur/skills/ux-audit/SKILL.md` and `plugins/soleur/agents/product/design/ux-design-lead.md` via `Bun.file(...).text()`. Assertions:
   - For each category string, it must appear at least once in both files.
   - The canonical field-rule phrase `real-estate | ia | consistency | responsive | comprehension` appears in the agent file.
   - Anchor test: modifying `dedup-hash.ts` to add a new category would fail this test until both markdown files are updated. Document the failure mode in the test's top-of-file comment (per `cq-code-comments-symbol-anchors-not-line-numbers`).
   - **RED state check:** this test should pass today (the triple is already in all three files). To prove the test catches drift, Phase 1 also includes a one-commit **canary**: temporarily add a 6th category `"accessibility"` to `FINDING_CATEGORIES` in the test file's imports… no — that mutates source. Instead, the test uses a helper that lets the spec assert "adding a synthetic category to the imported list would fail". Implementation: the test reads `FINDING_CATEGORIES` AND also asserts `FINDING_CATEGORIES.length === 5`. The length pin ensures adding a 6th category without also updating this test (which, by review convention, forces updating the markdown files) trips the guard. The `length === 5` pin is what makes this a drift test; without it the current state trivially passes.
   - **Research Insights (from `2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md`):** The `length === 5` + per-category-grep combo is the minimum viable drift guard. Strengthen by including an explicit **inline-expected tuple** asserted against the imported list:

        ```typescript
        import { FINDING_CATEGORIES } from "../../skills/ux-audit/scripts/dedup-hash";

        // EXPECTED is the canonical category list — bump this + the three
        // documentation sites (SKILL.md, ux-design-lead.md) together.
        // Drift guard: if FINDING_CATEGORIES and EXPECTED diverge, this
        // test fails loudly and the diff is human-readable.
        const EXPECTED = [
          "real-estate",
          "ia",
          "consistency",
          "responsive",
          "comprehension",
        ] as const;

        test("FINDING_CATEGORIES matches the canonical list", () => {
          expect([...FINDING_CATEGORIES]).toEqual([...EXPECTED]);
        });
        ```

        This pattern mirrors the "inline-expected literal + factory" idiom from the learning — drift surfaces as a readable `.toEqual` failure, not just an opaque length mismatch.
   - **Performance consideration:** reading two markdown files via `Bun.file(...).text()` is ~1ms each. Cache the reads at `describe` scope via `beforeAll` if the file gets more assertions in future; not needed at four assertions.
2. `skill-summary.test.ts` — defines and tests a local `formatSummary({filed, suppressed, skipped, hashes})` helper that returns the exact stdout format documented in SKILL.md. Asserts:
   - Output is valid JSON (single line, `JSON.parse` round-trips).
   - Keys in the order documented (`filed`, `suppressed`, `skipped`, `hashes`).
   - `hashes` is a sorted `string[]` (so parent agents diffing runs see stable order).
   - **RED state:** this test passes trivially because the helper is defined inside the test. The real coupling is that **SKILL.md** must describe the same shape — enforced by Phase 2 edit of SKILL.md. Pin `length === 4` on the top-level key list so a fifth field can't be added silently without updating parent-agent consumers.
   - **Research Insights (from `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md`):** Writing the schema is half the work; the consumer's explicit assertion is what makes it a contract. The test must actively read SKILL.md §7.5 and grep for each documented field, not just match against the helper's return value. Pattern:

        ```typescript
        // skill-summary.test.ts — cross-document drift guard
        import { readFileSync } from "node:fs";
        import { resolve } from "node:path";

        const SKILL_MD = readFileSync(
          resolve(import.meta.dir, "../../skills/ux-audit/SKILL.md"),
          "utf8",
        );

        // Regex anchored to §7.5 so moving the section breaks the test loudly.
        const SUMMARY_SECTION = SKILL_MD.match(
          /### 7\.5 Stdout summary[\s\S]*?(?=^###|\Z)/m,
        )?.[0];

        test("SKILL.md §7.5 documents the four required fields", () => {
          expect(SUMMARY_SECTION).toBeDefined();
          for (const field of ["filed", "suppressed", "skipped", "hashes"]) {
            expect(SUMMARY_SECTION).toContain(field);
          }
        });

        test("formatSummary output matches the §7.5 shape", () => {
          const out = formatSummary({
            filed: 2, suppressed: 1, skipped: 0, hashes: ["b", "a"]
          });
          const parsed = JSON.parse(out);
          expect(Object.keys(parsed)).toEqual([
            "filed", "suppressed", "skipped", "hashes"
          ]);
          expect(parsed.hashes).toEqual(["a", "b"]); // sorted
        });
        ```

        The SKILL.md grep is the consumer-boundary assertion: if the markdown rename a field, the test fails.
   - **Anti-pattern to avoid:** do not assert against `formatSummary` output alone — that's the self-referential pattern the learning calls out (`.schema == 1` writing and reading the same value).
   - **`§7.5` heading anchor** must match exactly. SKILL.md convention uses `###` for sub-sub-sections; grep the literal section heading once at test-load to fail fast if the numbering drifts.
3. `finding-schema.test.ts` — reads `plugins/soleur/skills/ux-audit/references/finding.schema.json` via `Bun.file(...).json()` and reads `ux-design-lead.md`. Extracts the first fenced JSON example block (delimited by triple-backtick-json) and asserts each object:
   - Has all `required` keys from the schema.
   - `category` ∈ `FINDING_CATEGORIES`.
   - `severity` ∈ `["critical", "high", "medium", "low"]`.
   - Imports `FINDING_CATEGORIES` from `dedup-hash` so a future category addition surfaces here too.
   - **RED state:** passes today against the schema + example in Phase 2 edits. Before Phase 2, `finding.schema.json` doesn't exist and the test fails at file-read time — that is the RED state.
   - **Research Insights — section-anchored extraction.** `ux-design-lead.md` has three fenced JSON blocks. Anchor the extraction to the `### Output contract` heading inside `## UX Audit (Screenshots)`:

        ```typescript
        const AGENT_MD = readFileSync(
          resolve(import.meta.dir, "../../agents/product/design/ux-design-lead.md"),
          "utf8",
        );

        // Extract JSON from the Output contract block inside UX Audit (Screenshots).
        // Section-anchored regex so moving or duplicating ```json blocks doesn't match.
        const OUTPUT_CONTRACT = AGENT_MD.match(
          /## UX Audit \(Screenshots\)[\s\S]*?### Output contract[\s\S]*?```json\n([\s\S]*?)\n```/,
        );
        expect(OUTPUT_CONTRACT).not.toBeNull();
        const examples = JSON.parse(OUTPUT_CONTRACT![1]);
        ```

        A rename of `### Output contract` in the agent file will cause the regex to return null, which the `expect(...).not.toBeNull()` catches loudly. Cheaper than a full markdown AST and more resilient than column position.
   - **Structural validation (no Ajv dependency):** per the Alternatives section, we do not add Ajv. The structural check reads the schema's `required` array and `properties.category.enum` directly:

        ```typescript
        const SCHEMA = JSON.parse(
          readFileSync(
            resolve(
              import.meta.dir,
              "../../skills/ux-audit/references/finding.schema.json",
            ),
            "utf8",
          ),
        );

        for (const example of examples) {
          for (const required of SCHEMA.required) {
            expect(example).toHaveProperty(required);
          }
          expect(SCHEMA.properties.category.enum).toContain(example.category);
          expect(SCHEMA.properties.severity.enum).toContain(example.severity);
        }
        ```
   - **Drift test for schema↔TS enum alignment:** schema `properties.category.enum` must equal `FINDING_CATEGORIES`. Add an explicit assertion:

        ```typescript
        expect([...SCHEMA.properties.category.enum].sort()).toEqual(
          [...FINDING_CATEGORIES].sort(),
        );
        ```

        This closes the loop — `dedup-hash.ts`, `SKILL.md`, `ux-design-lead.md`, and `finding.schema.json` are all cross-checked.

Run `cd plugins/soleur && bun test test/ux-audit/` to confirm each new test fails as described. Document the failure mode in the Phase 1 commit message.

**Exit criteria:** three new tests added; all three fail for the documented reason; no implementation edits yet.

### Phase 2 — GREEN: drift guard + schema (#2356 + #2362.3)

1. Edit `plugins/soleur/skills/ux-audit/scripts/dedup-hash.ts`: add a JSDoc line above `FINDING_CATEGORIES` pointing to the drift test by symbol:

    ```ts
    /** Canonical category list. Drift-guarded by `category-drift.test.ts`;
     *  any edit here requires updating SKILL.md + ux-design-lead.md. */
    ```

2. Create `plugins/soleur/skills/ux-audit/references/finding.schema.json`. Schema covers the seven fields in the agent's output contract: `route` (string), `selector` (string), `category` (enum of five), `severity` (enum of four), `title` (string, ≤100), `description` (string), `fix_hint` (string), `screenshot_ref` (string, absolute path pattern). `additionalProperties: false`. `$schema: https://json-schema.org/draft/2020-12/schema`.

    **Concrete schema:**

    ```json
    {
      "$schema": "https://json-schema.org/draft/2020-12/schema",
      "$id": "https://soleur.ai/schemas/ux-audit-finding.json",
      "title": "UX Audit Finding",
      "description": "One finding emitted by ux-design-lead in audit mode. See plugins/soleur/agents/product/design/ux-design-lead.md §UX Audit (Screenshots) > Output contract.",
      "type": "object",
      "required": ["route", "selector", "category", "severity", "title", "description", "fix_hint", "screenshot_ref"],
      "additionalProperties": false,
      "properties": {
        "route": { "type": "string", "pattern": "^/" },
        "selector": { "type": "string", "description": "CSS selector only. Empty string coarsens to '*' at hash time." },
        "category": {
          "type": "string",
          "enum": ["real-estate", "ia", "consistency", "responsive", "comprehension"]
        },
        "severity": {
          "type": "string",
          "enum": ["critical", "high", "medium", "low"]
        },
        "title": { "type": "string", "maxLength": 100 },
        "description": { "type": "string", "minLength": 1 },
        "fix_hint": { "type": "string", "minLength": 1 },
        "screenshot_ref": { "type": "string", "pattern": "^/" }
      }
    }
    ```

    **Design notes:**
    - `$id` uses a stable URL even though nothing resolves it — tooling that caches by `$id` (e.g., a future Ajv pass) stays stable across repo moves.
    - `route` and `screenshot_ref` enforce absolute-path leading `/` (matches both URL paths and Linux filesystem paths — the skill passes absolute filesystem paths per `hr-mcp-tools-playwright-etc-resolve-paths`).
    - `category.enum` duplicates `FINDING_CATEGORIES`. The drift test (Phase 1 step 3) ensures the duplication stays in sync.
    - `title.maxLength: 100` mirrors the agent field rule.
    - No `severity.default` — every finding must set one explicitly.
3. Edit `plugins/soleur/agents/product/design/ux-design-lead.md`:
   - Output contract section: add a sentence "Machine-readable schema: `plugins/soleur/skills/ux-audit/references/finding.schema.json` (the inline JSON below is an example; the schema is authoritative)."
   - Tighten the `selector` field rule: "`selector` is a CSS selector targeting the primary flagged element (CSS only — no XPath, no text-match syntax). Must be syntactically valid CSS."

**Exit criteria:** `category-drift.test.ts` and `finding-schema.test.ts` go GREEN. `skill-summary.test.ts` still passes its local-helper assertions (not yet coupled to SKILL.md).

### Phase 3 — GREEN: skill stdout summary + zipped targets (#2357)

1. Edit `plugins/soleur/skills/ux-audit/SKILL.md`:
   - §4 invocation contract: replace the parallel arrays block with:

        ```text
        mode: audit
        viewport: {w: 1440, h: 900}
        targets:
          - {path: "/dashboard", auth: "bot", fixture_prereqs: [...], screenshot_path: "/absolute/path/to/dashboard.png"}
          - ...
        ```

        Note: "If step 3 skipped a route (capture failure), that route is **absent** from `targets` — never passed as a null or placeholder."
   - §4 parse-guard: change error log to `::error::malformed agent output for target index <i> (route <path>)`.
   - After §7 (File issues), add a new **§7.5 Stdout summary**:

        ```text
        Before Step 8 cleanup, emit a single-line JSON object to stdout:

          {"filed":N,"suppressed":M,"skipped":K,"hashes":["<hex>", ...]}

        Fields (all required):
          filed      number of gh issue create calls that succeeded this run
                     (0 in dry-run mode; the dry-run array length does NOT count
                     as filed — dry-run counts under "skipped":0 and surfaces
                     the full array in findings.json instead)
          suppressed number of findings dropped by the dedup hash search
          skipped    number of findings dropped by CAP_PER_ROUTE or CAP_PER_RUN
          hashes     sorted list of hex hashes that were either filed (file mode)
                     or would have been filed (dry-run). Stable ordering so
                     parent agents diffing runs see stable output.

        Also write the same JSON to ${GITHUB_WORKSPACE}/tmp/ux-audit/summary.json
        so the workflow can upload it as an artifact sibling to findings.json.
        ```

   - Add a note at the top of §4: "The skill emits no intermediate `::warning::` / `::error::` annotations for parser consumption; the final JSON summary is the machine-readable signal. Human-readable `::warning::` lines for individual route skips remain for CI log UX."
2. Edit `plugins/soleur/agents/product/design/ux-design-lead.md`:
   - `### Invocation contract`: rewrite as the zipped `targets` form above. Update each sub-rule that references `screenshots[i]` / `routes[i]` to `targets[i].screenshot_path` / `targets[i].path` etc.
   - `### Output contract` `screenshot_ref` field rule: "`screenshot_ref` is the `targets[i].screenshot_path` value that was passed in; do not emit a new path."
3. Phase 2 `skill-summary.test.ts`: strengthen to read `SKILL.md`, grep the §7.5 block, and assert the documented field list matches the test's local helper signature (cross-document drift guard). This is the coupling that turns the local-helper test into a real contract check.
4. `.github/workflows/scheduled-ux-audit.yml` — **no edit** intended for this PR. The workflow already uploads `findings.json`; if the founder wants `summary.json` uploaded too, that's a one-line follow-up in a dedicated workflow PR. Noted as a Non-Goal below.

**Exit criteria:** `skill-summary.test.ts` passes its SKILL.md drift assertion. Manual rehearsal in dry-run mode (`UX_AUDIT_DRY_RUN=true` via local `/soleur:ux-audit`) emits the one-line JSON to stdout matching the documented shape.

### Phase 3.5 — Research Insights for Phase 3 (skill/agent contract change)

**Best practices for structured skill output:**

- A **single final JSON line** is easier for parent agents to `tail -n 1 | jq .` than interleaved structured events. Keeps the existing `::warning::` / `::error::` lines intact for humans reading CI logs.
- The `hashes` field is a sorted `string[]` because JavaScript's default `JSON.stringify` of object-key-order is insertion-order, which varies run-to-run. Sorting makes the summary byte-stable for diff-based comparisons (e.g., a nightly digest aggregating several runs).

**Anti-patterns to avoid:**

- Do NOT emit multiple JSON lines (one per finding). That invites streaming parsers and adds state. Single terminal object is sufficient.
- Do NOT include absolute paths or timestamps in the summary. They make byte-stable comparisons impossible and leak workspace-relative info into CI logs.
- Do NOT widen the summary shape without bumping a version field. If a future change adds, e.g., `route_stats`, add `schema: 1` to the summary and gate consumers on it (per `2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md`). This PR does not introduce a `schema` field because there are no consumers yet — adding one preemptively is speculative per project practice.

**Reference implementation (prose for SKILL.md §7.5, not code):**

```text
Pseudocode (for agent reference — the skill is instruction text):
  filed       = dry_run ? 0 : successful_gh_issue_create_count
  suppressed  = dedup_hits
  skipped     = cap_drops   // CAP_PER_ROUTE + CAP_PER_RUN
  hashes      = sorted list of hex hashes filed (or would-be-filed in dry-run)
  summary     = { filed, suppressed, skipped, hashes }

  echo "$(jq -cn --argjson s "$summary" '$s')"
  echo "$summary_json" > "${GITHUB_WORKSPACE}/tmp/ux-audit/summary.json"
```

The skill's instruction text MUST describe this exactly — a parent agent re-reading SKILL.md finds a single canonical shape. Verified by `skill-summary.test.ts` grep of §7.5.

**Edge case: CAP_OPEN_ISSUES reached early (Step 2 exit):** the skill exits before doing any work. In that case emit:

```json
{"filed":0,"suppressed":0,"skipped":0,"hashes":[]}
```

So parent agents always see a parseable line, even on early-exit. Document this in SKILL.md §7.5.

**Edge case: ux-design-lead audit-mode parse failure:** already handled by SKILL.md §4 parse-guard. The summary still emits; `skipped` counts the dropped targets.

### Phase 4 — GREEN: P3 polish (#2362 items 1, 2, 5, 6, 7)

1. **#2362.1 selector constraint** — already done in Phase 2.3. No extra work.
2. **#2362.2 prereqs vocabulary** — Edit `plugins/soleur/skills/ux-audit/references/route-list.yaml`:

    ```yaml
    # Top of file, after the existing comment block, before `routes:`.
    allowed_prereqs:
      - tcs_accepted
      - billing_active
      - chat_conversations
      - kb_workspace_deferred
    ```

    This is documentation — YAML consumers ignore it. The Validate step below asserts every `fixture_prereqs` value is in this list.
3. **#2362.5 logging truncation** — Edit `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts`. At each of the three `res.text()` callsites (`updateUserRow`, `insertConversation`, `insertMessages`), wrap:

    ```ts
    const body = (await res.text()).slice(0, 200);
    ```

    Add a top-level `const ERROR_BODY_MAX = 200;` constant and reference it at each callsite (drift guard per `cq-code-comments-symbol-anchors-not-line-numbers` — if the constant moves, every callsite still points to the symbol).
4. **#2362.6 role type** — Edit `FIXTURE_CONVERSATIONS` at `bot-fixture.ts:22-37`. Narrow each `role` value:

    ```ts
    { role: "user" as const, content: "..." },
    { role: "assistant" as const, content: "..." },
    ```

    Then tighten `insertMessages`'s parameter type from `{ role: string; content: string }` to `{ role: "user" | "assistant"; content: string }`. Run `bun tsc --noEmit` (or the equivalent for this project — see Test Strategy) to confirm no new errors.
5. **#2362.7 `describeIfCreds` skip logging** — Edit `plugins/soleur/test/ux-audit/bot-fixture.test.ts`. Immediately after the `describeIfCreds` assignment, add:

    ```ts
    if (!hasCreds) {
      const missing = [
        !SUPABASE_URL && "SUPABASE_URL",
        !SERVICE_KEY && "SUPABASE_SERVICE_ROLE_KEY",
        !BOT_EMAIL && "UX_AUDIT_BOT_EMAIL",
        !BOT_PASSWORD && "UX_AUDIT_BOT_PASSWORD",
        !ANON_KEY && "NEXT_PUBLIC_SUPABASE_ANON_KEY",
      ].filter(Boolean);
      console.warn(
        `[bot-fixture.test] skipping integration suite — missing env: ${missing.join(", ")}`,
      );
    }
    ```

    One-line signal when running locally. Does NOT affect the CI loud-fail story tracked in #2361.
6. **#2362.4 path filter** — **Acknowledge, no edit.** Add a Non-Goal line to the PR body: "Item #2362.4 (tailwind path filter) is N/A — the push trigger was removed per #2376; the workflow has no `paths:` filter to update."

**Research Insights — Phase 4 (bot-fixture truncation + type narrowing):**

- **Truncation at 200 chars captures the PostgREST error contract.** PostgREST error bodies follow `{code, details, hint, message}` in JSON. The `code` (5-char) + `message` (typically <150 chars) fit in 200 chars for the common cases (`PGRST116`, `23503`, `42P01`). Bodies longer than 200 chars are `details` enumerations — still useful at 200-char prefix, available in full via Supabase audit logs.
- **Anti-pattern avoided:** calling `res.text()` twice on the same `Response` throws "Body already used" (spec-compliant). The fix reads once, truncates the string:

    ```typescript
    if (!res.ok) {
      const body = (await res.text()).slice(0, ERROR_BODY_MAX);
      throw new Error(`PATCH users failed: ${res.status} ${body}`);
    }
    ```

- **Type-narrowing via `as const` at literal vs. tuple:** `FIXTURE_CONVERSATIONS` already has outer-level `as const`. The inner `role` strings widen to `string` at the `.map` consumer because `readonly` arrays of objects don't preserve string-literal narrowing through iteration. Adding `as const` at each literal is the cleanest fix; alternative is `as "user" | "assistant"` per literal. The learning `2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md` §Pattern 1 (`ReturnType<typeof> + satisfies`) hints at a richer pattern, but that's overkill for a 7-message fixture. Keep the edit minimal.
- **`insertMessages` signature narrowing:** change `messages: ReadonlyArray<{ role: string; content: string }>` to `messages: ReadonlyArray<{ role: "user" | "assistant"; content: string }>`. This is where the narrowing matters — future callers get caught at compile time. Verified compatible with the existing call site (no other callers outside `bot-fixture.ts`).
- **`console.warn` in bot-fixture test:** prints **once** at module load (not per test). Bun's test runner captures module-level console output and prepends it to the describe block's output. Verify by running the test with the env explicitly cleared:

    ```bash
    env -u SUPABASE_URL -u SUPABASE_SERVICE_ROLE_KEY -u UX_AUDIT_BOT_EMAIL \
      -u UX_AUDIT_BOT_PASSWORD -u NEXT_PUBLIC_SUPABASE_ANON_KEY \
      bun test plugins/soleur/test/ux-audit/bot-fixture.test.ts
    ```

    Expect: one `[bot-fixture.test] skipping …` line followed by `0 pass, 0 fail, <N> skip`. Also update the comment at `bot-fixture.test.ts:32-35` so it doesn't contradict the new behavior (change "silent-skip when creds are absent" → "emits a one-line console.warn when creds are absent").

### Phase 5 — Validation step for `allowed_prereqs`

Add a tiny test `plugins/soleur/test/ux-audit/route-list-prereqs.test.ts`:

- Reads `route-list.yaml` via `Bun.file(...).text()` and parses with a minimal hand-rolled extractor (`.match(/^allowed_prereqs:([\s\S]*?)^\w/m)` then `/-\s+(\w+)/g` — the YAML is simple and we avoid adding a yaml parser dep).
- For each `fixture_prereqs:` list in the file, asserts every entry is in `allowed_prereqs`.
- Closes the soft loop: the YAML allowlist is now machine-checked, not just documented.

Alternative considered: use `js-yaml` or Bun's built-in parsing. Rejected to avoid a new dependency — the YAML structure is stable and the regex approach is 10 lines. Documented in the test's header comment.

### Phase 6 — Pre-commit verification

Before each commit (per `wg-before-every-commit-run-compound-skill`):

1. `cd plugins/soleur && bun test test/ux-audit/` — all ux-audit tests pass.
2. `npx markdownlint-cli2 --fix plugins/soleur/skills/ux-audit/SKILL.md plugins/soleur/agents/product/design/ux-design-lead.md` (per `cq-markdownlint-fix-target-specific-paths` — specific paths, not globs).
3. Re-read modified markdown files (per `cq-always-run-npx-markdownlint-cli2-fix-on`) to verify.
4. `git status` clean.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `plugins/soleur/test/ux-audit/category-drift.test.ts` exists, passes, and its `length === 5` pin catches adding a 6th category to `FINDING_CATEGORIES` without updating SKILL.md and ux-design-lead.md.
- [ ] `plugins/soleur/skills/ux-audit/references/finding.schema.json` exists (Draft 2020-12) and its field list matches the agent's output contract.
- [ ] `plugins/soleur/test/ux-audit/finding-schema.test.ts` passes — the inline JSON example in `ux-design-lead.md` validates against the schema (structural check).
- [ ] `plugins/soleur/test/ux-audit/skill-summary.test.ts` passes — local helper matches the shape documented in SKILL.md §7.5.
- [ ] `plugins/soleur/test/ux-audit/route-list-prereqs.test.ts` passes — every `fixture_prereqs` value in `route-list.yaml` is listed under the new `allowed_prereqs` block.
- [ ] `SKILL.md` §4 documents the zipped `targets` array; parse-guard references target index. §7.5 documents the stdout JSON summary with all four fields.
- [ ] `ux-design-lead.md` `### Invocation contract` uses `targets: [{path, auth, fixture_prereqs, screenshot_path}, ...]`; `screenshot_ref` field rule says "the `targets[i].screenshot_path` value that was passed in".
- [ ] `ux-design-lead.md` `selector` field rule specifies "CSS only — no XPath, no text-match syntax".
- [ ] `bot-fixture.ts` truncates all three `res.text()` callsites to `ERROR_BODY_MAX` (200).
- [ ] `bot-fixture.ts` narrows `FIXTURE_CONVERSATIONS[*].messages[*].role` to `"user" | "assistant"` via `as const` at each literal; `insertMessages` signature narrowed.
- [ ] `bot-fixture.test.ts` emits a one-line `console.warn` when `hasCreds` is false, listing missing env vars.
- [ ] `bun test test/ux-audit/` passes from `plugins/soleur/`.
- [ ] `tsc --noEmit` (or plugin-level equivalent) clean for modified TS files.
- [ ] `bun test plugins/soleur/test/components.test.ts` passes — no skill description budget regression.
- [ ] `npx markdownlint-cli2 --fix` run on the two edited markdown files and resulting changes committed.
- [ ] PR body contains `Closes #2356`, `Closes #2357`, `Closes #2362` (three separate lines).
- [ ] PR body `## Changelog` section set and semver label is `semver:patch` (internal drift guard + doc edits; no new user-facing capability).
- [ ] PR body includes the `N/A` acknowledgement for #2362.4.

### Post-merge (operator)

- [ ] Trigger a manual run: `gh workflow run scheduled-ux-audit.yml` (per `wg-after-merging-a-pr-that-adds-or-modifies` — this PR does NOT modify the workflow file, but it modifies the skill the workflow invokes. The monthly cron is a backstop; a one-shot manual trigger verifies the new contract + stdout summary emit in the real environment).
- [ ] Confirm the workflow run's "Run ux-audit skill" step log contains a single line starting with `{"filed":` matching the §7.5 shape.
- [ ] Inspect the uploaded `ux-audit-findings` artifact; `findings.json` still parses and matches the agent's output contract.
- [ ] No Sentry errors from the bot-fixture truncation change (truncated errors remain actionable).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal tooling drift guard, docstring tightening, and type narrowing. The production path is dry-run cron-only; no user-facing surface changes. Engineering/CTO domain is the current task's topic, so per `pdr-do-not-route-on-trivial-messages-yes` no domain leader is spawned.

## Test Strategy

- **Runner:** `bun:test` — the existing convention in `plugins/soleur/test/ux-audit/` (see `dedup-hash.test.ts`, `bot-fixture.test.ts`, `bot-signin.test.ts`). No new framework; no new dependencies. Per `plan-skill` sharp edges.
- **Running locally:**

    ```bash
    cd plugins/soleur
    bun test test/ux-audit/
    ```

- **Type check:** the plugin directory has its own `tsconfig.json` (verify during work; if absent, run `cd plugins/soleur && npx tsc --noEmit -p .` against the scripts/ subdirectory). Phase 4 step 4 calls this out explicitly.
- **RED→GREEN discipline:** Phase 1 commit is all-RED; Phases 2-5 commits each drive a subset of tests to GREEN. Per `cq-write-failing-tests-before`.
- **jsdom traps:** none of these tests touch layout — they are pure-function + string/regex/JSON assertions. Per `cq-jsdom-no-layout-gated-assertions` we do not introduce any `clientWidth`-style gates.
- **Mocking:** no `vi.mock()` equivalents needed. The drift test imports the real `dedup-hash` module; per `cq-test-mocked-module-constant-import` this is safe.
- **No destructive tests added.** The new tests are read-only over committed files. The existing `bot-fixture.test.ts` destructive guard (line 24-29) is unchanged.

## Risks and Mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| Drift test `length === 5` pin creates a false sense of safety — someone adds a category AND updates both markdown files but forgets to bump the pin. | Low (the pin update is forcing function for the reviewer) | Test-file top-of-file comment spells out: "If you add a category, update `length === 5` here." Reviewer catches the unreferenced `5`. |
| JSON schema file ships without a runtime validator — claims machine-readability but nothing enforces it. | Medium | `finding-schema.test.ts` validates the **example** in the agent doc against the schema. That proves the schema is self-consistent and machine-parseable, even without full agent-output validation at run time. A follow-up issue can add Ajv + a pre-file validation step if drift recurs. |
| SKILL.md §7.5 format drifts from what the skill actually emits (since the "skill" is instruction text, not code). | Medium | `skill-summary.test.ts` grep of SKILL.md §7.5 for the four field names is the only machine check. Post-merge operator step (manual workflow run + log inspection) is the backstop. |
| Zipping `targets` breaks parent agents that already parse the parallel-array form. | Low (no parent agent exists today; the #2357 motivation is future-facing) | Skill and agent are shipped together in the same PR; no external parser exists. Any external consumer would be in the plugin repo and caught by review. |
| Truncating Supabase error bodies hides useful debugging info at 200 chars. | Low | 200 chars captures the PostgREST error code + message; full bodies are available in `SUPABASE_URL` audit logs if needed. Constant (`ERROR_BODY_MAX`) is easy to bump. |
| `allowed_prereqs:` YAML block is ignored by the skill parser — a typo in a route's `fixture_prereqs` still won't fail the run. | Low (Phase 5 test catches it) | `route-list-prereqs.test.ts` is the machine check. Documented in the YAML as "Enforced by `route-list-prereqs.test.ts`." |
| `describeIfCreds` `console.warn` floods local test output when running unrelated plugin tests. | Low | It fires only once at module load; the plugin has ~15 test files so the noise is bounded. Per `cq-agents-md-why-single-line` this is a legit tradeoff; acknowledged in PR body. |

## Non-Goals / Out of Scope

- **#2362.4 tailwind path filter** — N/A. The workflow has no `paths:` filter (push trigger removed per header comment; see `.github/workflows/scheduled-ux-audit.yml` lines 17-20). Acknowledge in PR body to close #2362 completely.
- **Ajv + runtime JSON schema validation inside the skill.** Deferred — the skill has no runtime to hook. File `tech-debt` issue only if drift recurs. No tracking issue filed at this time per `wg-when-deferring-a-capability-create-a`: the schema file alone is the deliverable #2362.3 asks for; adding validation is a separate proposal not promised by the issue.
- **Upload `summary.json` as a workflow artifact.** The skill writes it to `tmp/ux-audit/summary.json`; a follow-up 3-line workflow edit can add the upload. Out of scope for this chore PR; tracked below.
- **Ship a smoke job that loud-fails when creds are missing.** #2361 already tracks this; no edit here.
- **Push-trigger restoration.** Unrelated to these issues; gated on calibration per #2378.
- **Convert `FINDING_CATEGORIES` to a YAML-sourced constant read by the skill's instruction template.** Considered and rejected (see Alternatives).

## Deferral Tracking

| Deferred item | Why | Re-evaluation criteria | Tracking issue |
|---|---|---|---|
| Upload `summary.json` as workflow artifact (sibling to `findings.json`). | 3-line workflow edit; workflow file is untouched in this PR to keep blast radius small. | When a parent agent workflow (e.g. a weekly digest) wants to consume summaries, not findings. | **File during Work phase:** milestoned to `Post-MVP / Later`; references this plan and the §7.5 contract. |
| Ajv runtime validation of agent output against `finding.schema.json`. | The schema file is sufficient for the issue; validation is a capability add, not a drift fix. | If a run ships a malformed finding that slips past the parse-guard. | **Do NOT file** — speculative. |

The workflow-artifact-upload deferral is the only one that needs an issue. Filed during Work phase (Phase 4 step 6 → Ship).

## Research Insights — Review-catch prediction

Anticipating the `soleur:review` agents' likely findings lets the Work phase ship clean. Based on prior UX-audit PR review patterns (`2026-04-15-ux-audit-scope-cutting-and-review-hardening.md`) and the current plan content, expect these agent-specific concerns:

| Agent | Likely finding | Pre-emptive mitigation in plan |
|---|---|---|
| **security-sentinel** | "Does the new `console.warn` leak env-var names?" | Only names (`"SUPABASE_URL"`, etc.) are logged — never values. Documented explicitly. |
| **security-sentinel** | "Does the workflow `allowedTools` change?" | No. SKILL.md and agent edit only; no workflow edit. Called out in Non-Goals. |
| **code-quality-analyst** | "Are the new test assertions tautological?" (recurring class from #2346 review) | Phase 1 notes include the mutation-assertion rule; `category-drift.test.ts` asserts against an inline `EXPECTED` literal, not against itself. `finding-schema.test.ts` asserts the SCHEMA (not the test data) contains the expected enum. `skill-summary.test.ts` asserts SKILL.md text (external source), not just the local helper. |
| **code-quality-analyst** | "Does `bot-fixture.ts` body truncation lose actionable debug info?" | 200-char bound justified in Risks table; constant named `ERROR_BODY_MAX` for easy tuning. |
| **test-design-reviewer** | "RED→GREEN discipline missing commits?" | Phase 1 explicitly notes its commit sequence (Phase 1 RED, Phase 2/3/4 each drive GREEN). Each phase has an Exit criteria block. |
| **test-design-reviewer** | "Schema test relies on example JSON, not real agent output." | Acknowledged — the schema covers the documented contract; real-agent-output validation is a scope-out (Non-Goals; requires Ajv). |
| **architecture-strategist** | "Duplication between `FINDING_CATEGORIES`, schema enum, SKILL.md, agent rubric — now duplicated in **four** places, not three." | Drift test + schema test cross-check all four locations. The duplication trades "single source of truth" for readability where it matters (agent instruction text needs the enum inline). |
| **architecture-strategist** | "Why not extract `finding.schema.json`'s enum from `FINDING_CATEGORIES` at build time?" | No build step exists; `references/` files are read as literals. Adding codegen is speculative. Drift test is the contract. |
| **agent-native-reviewer** | "Parent agents need the schema to validate ux-design-lead output before filing — why not gate runtime?" | Noted in Deferral Tracking. Schema ships as contract; runtime Ajv is a separate proposal. |
| **pattern-recognition-specialist** | "Plan says 'extract/modify for N files' — verified with `rg`?" | Yes. Overlap check in Open Code-Review Overlap section enumerated all files via `jq .body contains $path` queries; no files beyond the five listed. |
| **dhh-rails-reviewer / code-simplicity-reviewer** | "JSON Schema is overkill for 7 fields — just use a TypeScript interface + a validation function." | Considered; rejected because (a) the schema file is itself a deliverable of #2362.3, (b) external consumers (future tooling) read JSON Schema more easily than TS types, (c) structural checks in the test already act as a validator without adding a dependency. |
| **legacy-code-expert** | "Does this break any workflow consuming SKILL.md as an instruction-set?" | Only the workflow at `.github/workflows/scheduled-ux-audit.yml` consumes it. The invocation prompt does not parse SKILL.md fields — it points at the file. New §7.5 and updated §4 are additive/clarifying instructions for the agent executing the skill. |

**Pre-emptive commit structure** (keeps review agents' job narrow):

1. Phase 1 commit: "test: add RED drift/schema/summary tests for ux-audit" — all four new tests, failing for the documented reason. No source edits.
2. Phase 2 commit: "feat(ux-audit): ship finding schema + drift-test anchor" — schema file, dedup-hash comment, agent doc tighten.
3. Phase 3 commit: "feat(ux-audit): document stdout summary + zipped targets" — SKILL.md §4 + §7.5, agent contract rewrite.
4. Phase 4 commit: "chore(ux-audit): P3 polish (allowed_prereqs, truncation, types, warn)" — YAML, bot-fixture, test warn, comment fix.
5. Phase 5 commit: "test(ux-audit): enforce allowed_prereqs allowlist" — route-list validator test.
6. Final commit: compound-skill output (learnings, rule candidates) per `wg-before-every-commit-run-compound-skill` (run before Phase 1 if compound finds nothing; final run after Phase 5).

Every commit leaves the suite GREEN. Per `rf-before-spawning-review-agents-push-the`, push before invoking `/soleur:review`.

## Sharp Edges

- The `length === 5` pin in `category-drift.test.ts` is the whole load-bearing assertion. Document its purpose loudly in a comment.
- `ux-design-lead.md` has multiple fenced JSON blocks across the file (audit output, wireframe handoff brief, others). `finding-schema.test.ts` must scope to the fenced block inside `## UX Audit (Screenshots) > ### Output contract`, not the first JSON block in the file. Use a section-anchored regex (`/### Output contract[\s\S]*?```json\n([\s\S]*?)\n```/`).
- `bot-fixture.ts` error-body truncation must `slice` the awaited string, not the Response. Reading `res.text()` twice throws; the truncation happens after the single read.
- The `ERROR_BODY_MAX = 200` constant lives at module top; if moved, the three callsites still reference it by symbol (satisfies `cq-code-comments-symbol-anchors-not-line-numbers`).
- When `console.warn` fires in `bot-fixture.test.ts` on missing creds, run test output will include the warning line. Do NOT capture it and assert absence — local dev and plugin CI both hit this path.
- The YAML `allowed_prereqs:` block is docs + enforced by a test. The skill's step 3 still uses the hardcoded marker set in SKILL.md (`kb_workspace_deferred` skip). Do not conflate: the allowlist is an enumerate-what-exists, not a semantic-meaning. Expanding it requires updating SKILL.md too.
- `finding.schema.json` uses `$schema: https://json-schema.org/draft/2020-12/schema`. Some validators pin to Draft-07; this project has none today, so the choice is future-proof. If a validator is added later and only supports Draft-07, downgrade the schema (one-line edit).
- Per `cq-agents-md-why-single-line`: no new AGENTS.md rules needed. The three existing `cq-*` rules (`symbol-anchors`, `markdownlint-fix`, `write-failing-tests-before`) already cover this PR.
- Per `wg-use-closes-n-in-pr-body-not-title-to`: PR body — NOT title — contains the three `Closes #N` lines.

## PR Body Template

```markdown
## Summary

Drains three `code-review`-labeled issues scoped to `soleur:ux-audit`:

- #2356 — add drift test for `FINDING_CATEGORIES` across dedup-hash.ts, SKILL.md, ux-design-lead.md
- #2357 — skill emits a final stdout JSON summary; audit-mode input contract becomes zipped `targets[]`
- #2362 — P3 polish: CSS-only selector constraint, documented `allowed_prereqs`, `finding.schema.json`, truncated Supabase error bodies, narrowed `role` type, local-missing-env warn

## Changes

- NEW `plugins/soleur/test/ux-audit/category-drift.test.ts`
- NEW `plugins/soleur/test/ux-audit/skill-summary.test.ts`
- NEW `plugins/soleur/test/ux-audit/finding-schema.test.ts`
- NEW `plugins/soleur/test/ux-audit/route-list-prereqs.test.ts`
- NEW `plugins/soleur/skills/ux-audit/references/finding.schema.json`
- Edit `plugins/soleur/skills/ux-audit/SKILL.md` (§4 contract, new §7.5 summary)
- Edit `plugins/soleur/agents/product/design/ux-design-lead.md` (zipped targets, schema ref, CSS-only selector)
- Edit `plugins/soleur/skills/ux-audit/references/route-list.yaml` (allowed_prereqs)
- Edit `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts` (truncation, role type)
- Edit `plugins/soleur/skills/ux-audit/scripts/dedup-hash.ts` (drift-test anchor comment)
- Edit `plugins/soleur/test/ux-audit/bot-fixture.test.ts` (missing-env warn)

## Non-Goals

- #2362.4 (tailwind path filter): N/A — workflow has no `paths:` filter (push trigger removed per #2376).
- Ajv runtime validation: schema ships as contract only; runtime validation is a separate proposal if drift recurs.
- `summary.json` artifact upload: tracked as a follow-up (workflow file untouched this PR to minimize blast radius).

## Changelog

Patch — internal drift guard, documentation, and type narrowing in the `soleur:ux-audit` skill + `ux-design-lead` agent. No user-facing capability change.

## Test Plan

- [ ] `cd plugins/soleur && bun test test/ux-audit/` — all pass
- [ ] `tsc --noEmit` clean for modified TS
- [ ] `bun test plugins/soleur/test/components.test.ts` — description budget OK
- [ ] Post-merge: `gh workflow run scheduled-ux-audit.yml` and confirm the run log contains a single `{"filed":...}` line matching SKILL.md §7.5.

Closes #2356
Closes #2357
Closes #2362
```

## References (from deepen-plan research)

Learnings applied during the deepen pass:

- `knowledge-base/project/learnings/best-practices/2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.md` — drives the SKILL.md §7.5 consumer-boundary grep assertion and the decision to **not** ship a `schema:` version field in the summary yet.
- `knowledge-base/project/learnings/best-practices/2026-04-18-test-mock-factory-drift-guard-and-jsdom-layout-traps.md` — drives the inline-expected `EXPECTED` tuple pattern in `category-drift.test.ts`; confirms no jsdom-layout gates in the new tests (these tests don't touch DOM).
- `knowledge-base/project/learnings/2026-04-15-ux-audit-scope-cutting-and-review-hardening.md` — prior-art on the ux-audit skill's review-catch patterns; drives the Review-catch prediction table and the "no workflow allowedTools change" Non-Goal.
- `knowledge-base/project/learnings/2026-03-18-bun-test-segfault-missing-deps.md` — drives Phase 0 preflight step (verify `node_modules` before `bun test` in worktree).
- `knowledge-base/project/learnings/developer-experience/2026-03-29-bun-test-vi-stubenv-unavailable.md` — drives the bun-test API constraint (use `describe`/`test`/`expect`/`Bun.file` only; never `vi.stubEnv`).

Repo files consulted:

- `plugins/soleur/skills/ux-audit/SKILL.md` (184 lines)
- `plugins/soleur/skills/ux-audit/scripts/dedup-hash.ts`, `bot-fixture.ts`, `bot-signin.ts`
- `plugins/soleur/skills/ux-audit/references/route-list.yaml`
- `plugins/soleur/agents/product/design/ux-design-lead.md`
- `plugins/soleur/test/ux-audit/dedup-hash.test.ts`, `bot-fixture.test.ts`
- `.github/workflows/scheduled-ux-audit.yml` (confirms `paths:` filter absent → #2362.4 N/A)

`gh issue list --label code-review --state open` cross-check (Open Code-Review Overlap section above) confirmed only #2356/#2357/#2362 touch the planned files. No sibling scope-outs to fold in.

