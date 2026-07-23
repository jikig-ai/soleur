---
title: "chore: frontmatter-strip TS twin + rule-metrics denominator investigation (#6794)"
issue: 6794
type: chore
lane: cross-domain
brand_survival_threshold: none
adr: ADR-094 (amend)
created: 2026-07-22
---

# chore: frontmatter-strip TS twin + rule-metrics denominator investigation (#6794) ♻️

> Note: no `spec.md` exists for this branch — `lane:` defaulted to `cross-domain` (fail-closed per the plan skill's Save-Tasks rule).

## Enhancement Summary

**Deepened on:** 2026-07-22
**Gates run:** Phase 4.4 precedent-diff, 4.6 user-brand (pass: threshold `none` + scope-out for sensitive `apps/web-platform/server/` path), 4.7 observability (pass: 5 fields, no-ssh), 4.8 PAT (n/a), 4.9 UI-wireframe (n/a). Reviewers: architecture-strategist, code-simplicity-reviewer, spec-flow-analyzer. Learnings-researcher.

### Key corrections applied
1. **Build path corrected (mechanical):** the cron body is compiled by **`next build` / webpack** via `app/api/inngest/route.ts` (`serve({functions})`), NOT esbuild `build:server` (which never imports function bodies). The import-boundary lever is `experimental.externalDir` (webpack), not `outputFileTracingIncludes` (dead under `output: undefined`). Hard gate = `tsc --noEmit` + `next build`.
2. **Executable invariant added (spec-flow #1/#2, mechanical):** extract `measureAlwaysLoadedBytes` helper + unit tests asserting promoter total == `byteLength(index)+byteLength(strip(core))` and the over-strip RAW fallback — every prior AC was a proxy (existence/shape), none asserted the actual "measurement is exact" invariant.
3. **Sync-guard diagnostic: all THREE skew sites** enumerated (spec-flow #4), not two.
4. **Re-eval breadcrumb** dropped in `rule-metrics-aggregate.sh` so closing #6794 doesn't de-surface the "may be telemetry-absence" caution (spec-flow #5).
5. **Shell over-strip guard dropped** (simplicity) — kept only in the runtime contract; `compound-promote.sh` gets just the 2-line basis change.
6. **Inline-vs-import surfaced as a User-Challenge** (`decision-challenges.md`) — plan defaults to #6794's literal "use strip.ts in the cron."

## Overview

Issue #6794 is an OPEN `type/chore` / `priority/p3-low` / `domain/engineering` tracker of two deliberately-deferred follow-ups from #6461 (the rule-budget single-source-of-truth work). It has two independent items on the same subsystem, delivered in ONE PR:

1. **Item 1 (bounded investigation + decision).** Establish whether `.claude/.rule-incidents.jsonl` telemetry is being recorded at a meaningful rate before treating `rules_unused_over_8w: 98` as a pruning mandate. Produce a durable finding and a decision; do **not** scope or run a pruning campaign (explicitly deferred; re-eval trigger = "before any PR that retires rules in bulk").

2. **Item 2 (engineering deliverable).** Add `scripts/lib/frontmatter-strip/strip.ts` as a third byte-identical implementation under the existing SPEC contract, extend the parity test to cover it, USE it in `cron-compound-promote.ts` and (via the existing `strip.sh`) in `scripts/compound-promote.sh` so the always-loaded byte-budget comparison is done on the **frontmatter-stripped** basis instead of raw file length, then tighten `lint-agents-compound-sync.sh`'s unit diagnostic once the promoters are unit-exact.

**Only #6794 is a work target.** Every other issue number in the body (#6461, #6138, #4622, #6464, #6751, #5999) is a contextual citation, not a work item.

The change is measurement-basis-only: it makes the two promoters compare on the same basis the commit-gate linter (`lint-agents-rule-budget.py`) already uses. Today the promoters measure RAW bytes and the linter measures FRONTMATTER-STRIPPED bytes; the ~73 B skew is the frontmatter block on `AGENTS.core.md` (the only always-loaded file that carries frontmatter — `AGENTS.md` does not). The skew is currently in the fail-safe direction (raw ≥ stripped → the promoter refuses no later than the gate); this PR removes it so the comparison is exact and the sync guard can assert true parity.

## Research Reconciliation — Spec vs Codebase

| Issue-body claim | Codebase reality (verified) | Plan response |
| --- | --- | --- |
| "the denominator is the **101 tagged** rules, not the 202-rule registry" | `AGENTS.md` index carries exactly **101** `[id:]` pointers; the sidecar bodies sum to **101** (`AGENTS.core.md`=53, `AGENTS.rest.md`=42, `AGENTS.docs.md`=6). `lint-rule-ids.py` couples pointer↔body 1:1. So `202` = **2 × 101** id-*occurrences* (one index pointer + one body per rule), NOT 101 tagged + 101 untagged. There is no separate population of "untagged" rules. | Item-1 finding candidate: the "101 of 202" framing double-counts. The aggregate parses only `AGENTS.md` (101 pointers) and correctly uses **101** as the denominator. Record this in the investigation note. |
| "`strip.py`, `strip.sh` … mechanical parity enforcement via `scripts/lib/frontmatter-strip.test.sh`" | The parity test **exists** but is **orphaned** — it is NOT invoked by `ci.yml`, `scripts/test-all.sh`, `lefthook.yml`, or any Makefile. `strip.py` is exercised only *indirectly* by `lint-agents-rule-budget.test.sh` case T8 (registered in `test-all.sh` as `scripts/lint-agents-rule-budget-unit`). The strip.sh↔strip.py parity assertion runs nowhere in CI today. | "Extend parity enforcement" is toothless unless the test runs in CI. Plan folds in **registering** the parity test in `test-all.sh`'s `want_bun` block (discovered-gap fold-in). |
| "Add `strip.ts` … use it in `cron-compound-promote.ts`" (implies a clean import) | **Deepen-plan Phase 4.4 (architecture-reviewer, corrected):** the cron body runs inside a **Next.js App Router route handler** — `apps/web-platform/app/api/inngest/route.ts` imports every `cron*` function and registers them in `serve({ functions: [...] })`; that file is compiled by **`next build` (webpack)**. The esbuild `build:server` entry (`server/index.ts`) never imports the function bodies (it only `.send()`s events + delegates HTTP to Next via `app.getRequestHandler()`), so esbuild is NOT the cron's bundler. `next.config.ts` `output: undefined` → no standalone tracer; the Dockerfile ships full `.next` + `node_modules`. Webpack DOES enforce a cross-root import boundary; `experimental.externalDir` is currently **unset**. **Zero** existing web-platform files import cross-app-boundary (`grep`). | The real gate is `tsc --noEmit` + **`next build` (webpack)** succeeding. If webpack rejects the cross-root path, the lever is `experimental.externalDir: true` in `next.config.ts` (a webpack concept). `outputFileTracingIncludes` is **dead** under `output: undefined` — do not use it. See Risks R1 + the surfaced inline-alternative challenge. |
| Promoters "measure **raw** file length" and porting the strip makes it "unit-exact" | Confirmed. Cron: `(await readFile(agentsPath)).length` + `(await readFile(agentsCorePath)).length` (raw buffer bytes). Shell: `wc -c < "$AGENTS_INDEX"` + `wc -c < "$AGENTS_CORE"`. Linter authority: `b_index = file_bytes(index)` (raw, no frontmatter) + `b_core = len(strip_frontmatter(core_text).encode("utf-8"))` (stripped, byte count). | Cron must measure `Buffer.byteLength(stripFrontmatter(text), "utf8")`; shell must `strip_frontmatter < file | wc -c`. Strip is a **no-op on `AGENTS.md`** (no leading `---\n`), so applying it to both files matches the authority exactly. |
| (implicit) stripping is safe | The malformed/over-strip case consumes the WHOLE file → **empty** output → a much *smaller* byte count → could FALSELY PASS the cap (allow an oversized promotion). This is the DANGEROUS direction. The linter guards it via a rule-line-count invariant (ERROR if the strip drops `[id:]` lines). | The cron + shell consumers MUST adopt the same over-strip guard: if stripping removes any `[id:]` rule line, fall back to RAW measurement (fail-safe) + emit a distinct in-surface signal. New FR. |

## User-Brand Impact

**If this lands broken, the user experiences:** the weekly `cron-compound-promote` self-healing loop either false-reverts a valid AGENTS.core.md/skill promotion (headroom lost, no user-visible artifact) or, in the over-strip failure mode, false-*passes* an oversized always-loaded payload into a draft PR — which is still gated by mandatory human review before merge (`mergeMode: "none"`, draft PR).

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this change touches only internal governance-automation byte measurement. It reads `AGENTS.md`/`AGENTS.core.md` (repo-committed governance text, no PII), adds no new external egress, and processes no operator-session or customer data.

**Brand-survival threshold:** none.
- `threshold: none, reason: the change is measurement-basis-only on operator-internal governance automation whose output is a draft PR behind a mandatory human-review gate; no customer-facing surface, data, or money path is touched.`

## Premise Validation

- **#6794** — `gh issue view 6794`: state `OPEN`, `type/chore`, `priority/p3-low`, `domain/engineering`, milestone "Post-MVP / Later". Premise holds; this is a real open work target.
- **Cited artifacts all exist on disk (verified):** `scripts/lib/frontmatter-strip/{SPEC.md,strip.py,strip.sh,fixtures/}`, `scripts/lib/frontmatter-strip.test.sh`, `apps/web-platform/server/inngest/functions/cron-compound-promote.ts`, `scripts/compound-promote.sh`, `scripts/lint-agents-compound-sync.sh`, `scripts/rule-metrics-aggregate.sh`, `knowledge-base/project/rule-metrics.json`, `ADR-094`.
- **Mechanism vs ADR corpus:** adding a third byte-identical impl EXTENDS the ADR-094 / #5999 frontmatter-strip contract (SPEC.md §"Two byte-identical implementations"). It is not a rejected alternative — the SPEC's whole design is "keep implementations byte-identical via mechanical parity." Using it in the promoters closes the skew the sync guard already documents. No rejected-alternative collision.
- **rule-metrics.json** currently reports `total_rules_tagged: 101, rules_unused_over_8w: 98, rules_bypassed_over_baseline: 0`, `generated_at: 2026-07-20`. `.claude/.rule-incidents.jsonl` is **absent** in this worktree (confirms the machine-local / aggregator-no-op behavior #6042 / ADR-091 describe).

## Implementation Phases

### Phase 0 — Preconditions (verify before writing)

0.1. Confirm only `AGENTS.core.md` carries leading frontmatter (`head -c 4 AGENTS.md` ≠ `---\n`; `head -4 AGENTS.core.md` shows the `---` block). Strip on `AGENTS.md` must be a no-op.

0.2. Confirm the linter's byte basis: `b_core = len(strip_frontmatter(core_text).encode("utf-8"))`, `b_index = file_bytes(index)` (raw). The TS/shell consumers must replicate exactly (UTF-8 byte count of stripped text).

0.3. Confirm the parity test's current shard reality: `grep frontmatter-strip scripts/test-all.sh` → empty (orphaned); scripts CI shard has NO `bun` and stock `node` (cannot run `.ts` directly — verified `node <file.ts>` throws `ERR_UNKNOWN_FILE_EXTENSION`). The bun shard (`bash scripts/test-all.sh bun`, `want_bun`) DOES have `bun` 1.3.14.

0.4. Confirm the cron import boundary: `grep -rE "from ['\"]\.\./\.\./\.\./\.\./\.\./" apps/web-platform/server/` → empty (no precedent). Read `apps/web-platform/next.config.ts` for `experimental`/`outputFileTracing*` keys.

### Phase 1 — Add `strip.ts` at the SPEC location

1.1. Create `scripts/lib/frontmatter-strip/strip.ts`: a pure, zero-dependency ESM module exporting `stripFrontmatter(text: string): string`, byte-identical in behavior to `strip.py`/`strip.sh` (SPEC.md §Contract). Port `strip.py`'s algorithm line-for-line:
   - if not `text.startsWith("---\n")` → return `text`;
   - split on `"\n"`; from index 1, first line exactly `"---"` → return `lines.slice(i+1).join("\n")`;
   - no close → return `""` (malformed/over-strip signal).
   Add a stdin→stdout filter main-guard so it runs as `bun run strip.ts < file`. **Use node-compatible APIs only** — a `process.argv[1]`-based main-guard reading `process.stdin` / writing `process.stdout`, NOT `import.meta.main` or the `Bun` global. The module is imported by `cron-compound-promote.ts` and MUST typecheck clean under `apps/web-platform/tsconfig.json`, which has no `Bun` types (learning: `2026-05-07-pdfjs-dist-bundling-reorder-breaks-node-init.md` §Session-Errors-2). Header docstring cites SPEC.md, #5999/ADR-094, and #6794.

1.2. Amend `scripts/lib/frontmatter-strip/SPEC.md`: add `strip.ts` to the "byte-identical implementations" list with its consumer (`cron-compound-promote.ts`, and `compound-promote.sh` via `strip.sh`); note the parity test now covers three impls.

### Phase 2 — Extend + register the parity test

2.1. Extend `scripts/lib/frontmatter-strip.test.sh`: add a `command -v bun >/dev/null 2>&1 || { echo "SKIP: bun missing"; exit 0; }` gate (mirroring the existing perl/python3 skip-gates); for every fixture, compute `ts_out=$(bun run "$DIR/strip.ts" < "$f"; printf 'x')` and assert byte-identity `sh_out == py_out == ts_out` (three-way parity, sentinel-`x` preserves trailing newlines). Keep the existing semantic assertions.

2.2. Register the (currently orphaned) parity test in `scripts/test-all.sh` under the `want_bun` block: `run_suite "scripts/frontmatter-strip-parity" bash scripts/lib/frontmatter-strip.test.sh`. The bun CI job already runs `bash scripts/test-all.sh bun` (ci.yml:518), so no `ci.yml` edit is needed. Placing it in `want_bun` guarantees `bun` is present for the `.ts` filter.

### Phase 3 — Wire the strip into the two promoters (riskiest)

3.1. **`cron-compound-promote.ts`.** Import `stripFrontmatter` from `scripts/lib/frontmatter-strip/strip.ts` (relative depth resolves to `../../../../../scripts/lib/frontmatter-strip/strip`; confirm at /work). **Extract a testable helper** (spec-flow #1/#2) — `export function measureAlwaysLoadedBytes(indexText: string, coreText: string): number` — that computes `Buffer.byteLength(stripFrontmatter(indexText),"utf8") + Buffer.byteLength(stripFrontmatter(coreText),"utf8")` with the over-strip guard inside it, so a unit test can assert the invariant without invoking the Inngest handler. Call it at BOTH measurement sites:
   - the prompt-size read (`alwaysLoadedNow`, ~L455-457);
   - the post-apply cap read (`postBytes`, ~L607-609).
   **Over-strip guard (inside the helper):** before trusting the stripped byte count on `AGENTS.core.md`, assert the rule-line count is invariant across the strip using the **anchored** regex `^- .*\[id: ` (NOT a bare `[id:` substring — architecture-reviewer precision note; must match `lint-agents-rule-budget.py` `_rule_line_count` line 61, which counts 53 lines today). If it dropped, use the RAW byte length for that file (fail-safe) and `reportSilentFallback(err, { op: "frontmatter-overstrip-fallback", ... })`. Update the "UNIT SKEW" comment block (~L70-77) to the stripped-basis (unit-exact) wording; keep `MAX_ALWAYS_LOADED_BYTES` / `PROPOSE_ALWAYS_LOADED_BUDGET` literals unchanged (sync-guard SITES).
   - **Build/import verification gate (hard):** `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` MUST pass, AND `cd apps/web-platform && npm run build` (`next build` — the **webpack** compiler that actually bundles the cron route via `app/api/inngest/route.ts`) MUST succeed with the cross-root import resolved. Do NOT declare the phase done on `tsc` alone (webpack, not tsc, enforces the app-root boundary). If `next build` rejects the cross-root path, the lever is `experimental.externalDir: true` in `next.config.ts` (NOT `outputFileTracingIncludes` — dead under `output: undefined`; NOT esbuild). An in-app re-export shim does NOT help (it still crosses the webpack boundary).

3.2. **`scripts/compound-promote.sh`.** `source "$REPO_ROOT/scripts/lib/frontmatter-strip/strip.sh"` (defines `strip_frontmatter`). Replace the two `wc -c < "$FILE"` reads (L157-158) with `strip_frontmatter < "$FILE" | wc -c` (the 2-line basis change the issue asks for). Update the "UNIT SKEW (deliberate, fail-safe)" comment (L164-168) to unit-exact wording. Keep `ALWAYS_LOADED_CAP` / `PROPOSE_ALWAYS_LOADED_BUDGET` literals unchanged (sync-guard SITES). **Do NOT add the over-strip guard here** (simplicity-reviewer, accepted): this script's own header (L3) marks it operator-local hand-testing only; its byte output is advisory prompt/annotation text, not a gate, and the over-strip failure mode on this path is not brand-relevant. The guard lives only in the runtime contract (`cron-compound-promote.ts`).

### Phase 4 — Tighten the sync guard + ADR

4.1. **`scripts/lint-agents-compound-sync.sh`.** The guard asserts CONSTANT equality (unchanged). Tighten the DIAGNOSTIC at **all THREE** skew-asserting sites (spec-flow #4 — the enumeration must be complete or the guard keeps asserting a false basis, "worse than no guard" per its own header): (i) the top-of-file "UNIT (load-bearing…)" comment (~L26-32), (ii) the mid-file comment block "*some consumers (the cron, compound-promote.sh) measure RAW file length*" (~L146-152), and (iii) the `UNIT_NOTE` variable (~L153). Rewrite all three to state that all measurement consumers now measure on the frontmatter-stripped basis → unit-exact with the authority; the diagnostic no longer hedges about a skew. Verify no OTHER measurement consumer still measures raw (the SITES are literal-restatement sites, not measurement sites).

4.2. **ADR-094 amendment** (`## Decision` + a dated amendment note): record that the frontmatter-strip contract now has a THIRD byte-identical implementation (`strip.ts`), that `cron-compound-promote.ts` and `compound-promote.sh` measure the always-loaded budget on the stripped basis (closing the documented raw-vs-stripped skew from #6461), and that the parity test is now CI-enforced. (Extension of the existing decision, not a new ADR — see Architecture Decision section.)

4.3. If `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` contains prose describing the raw-vs-stripped skew, update it to the unit-exact wording. Do NOT touch its `B_ALWAYS >= … warn` / `reject above …` literals (sync-guard SITES).

### Phase 5 — Item 1: telemetry denominator investigation + decision (independent)

5.1. **Locate the incidents log(s) on the operator machine.** The aggregate reads `$REPO_ROOT/.claude/.rule-incidents.jsonl`. Sessions run in worktrees, each with its own `.claude/`. Enumerate `.claude/.rule-incidents.jsonl` + rotated archives `.claude/.rule-incidents-*.jsonl.gz` across the active worktrees (NOT the bare mirror at `/home/jean/git-repositories/jikig-ai/soleur` — `hr-when-in-a-worktree-never-read-from-bare`). Count valid rule-carrying lines and the timestamp span.

5.2. **Measure the write rate.** Compute events/week over the observed span (total valid `rule_id` rows ÷ weeks). Classify: `~0` ⇒ telemetry barely recorded ⇒ `98/101 unused` is a **telemetry-absence artifact**, NOT a dead-weight signal; meaningful ⇒ the unused count is credible.

5.3. **Resolve the denominator framing — two independent methods.** Per learning `2026-07-20-an-advisory-gate-is-not-a-weak-gate...` (re-derive BOTH numerator and denominator two ways before building on a ratio): confirm `202` = 2 × 101 id-occurrences (index pointer + sidecar body), not 101 tagged + 101 untagged. Method A: `grep -cE '^\- \[id: ' AGENTS.md` (=101 pointers) and `grep -cE '\[id: ' AGENTS.core.md AGENTS.docs.md AGENTS.rest.md` (=53+42+6=101 bodies). Method B: `rule-metrics.json .summary.total_rules_tagged` (=101). The aggregate's denominator (101) is correct; there is no untagged population.

5.4. **Record the decision** in a durable learning note (`knowledge-base/project/learnings/<topic>.md` — directory + topic only, date chosen at write time per Sharp Edges; suggested topic `rule-metrics-denominator-investigation`). Content: the write-rate finding, the 202-double-count clarification, and the explicit decision **do not scope or run a pruning campaign now** (re-eval trigger = before any bulk-prune PR).

5.5. **Breadcrumb at the consumption surface (spec-flow #5).** Closing #6794 removes the tracker that carried the re-eval trigger, so a future pruner reading `rules_unused_over_8w: 98` in `rule-metrics.json` would have no pointer to the finding. Add a one-line comment in `scripts/rule-metrics-aggregate.sh` near the `rules_unused_over_8w` summary field pointing to the learning note (e.g. `# NB: a high unused rate may be telemetry-absence, not dead weight — see knowledge-base/project/learnings/<topic>.md before any bulk prune (#6794).`). This keeps the caution visible at the exact decision surface after the issue closes. Then `Closes #6794` in the PR body with all four checkboxes ticked.

## Files to Create

- `scripts/lib/frontmatter-strip/strip.ts` — third byte-identical impl + bun filter main-guard.
- `knowledge-base/project/learnings/<rule-metrics-denominator-investigation-topic>.md` — item-1 decision record (date at write time).
- `knowledge-base/project/specs/feat-one-shot-6794-.../decision-challenges.md` — surfaced inline-vs-import User-Challenge (already written; `ship` renders it into the PR body + files an `action-required` issue).
- `knowledge-base/project/plans/2026-07-22-chore-frontmatter-strip-ts-and-rule-metrics-denominator-plan.md` — this plan.

## Files to Edit

- `scripts/lib/frontmatter-strip/SPEC.md` — add `strip.ts` + consumers to the impl list.
- `scripts/lib/frontmatter-strip.test.sh` — three-way parity + `bun` skip-gate.
- `scripts/test-all.sh` — register the parity test in `want_bun`.
- `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` — extract `measureAlwaysLoadedBytes` helper (strip + over-strip guard), call at both measurement sites, unit comment.
- `apps/web-platform/test/server/inngest/cron-compound-promote.test.ts` — **new cases (spec-flow #1/#2)**: (a) `measureAlwaysLoadedBytes` on a fixture (no-frontmatter index + frontmatter core) equals `byteLength(index)+byteLength(strip(core))`; (b) over-strip fixture (unterminated core `---`) falls back to RAW and flags `frontmatter-overstrip-fallback`.
- `apps/web-platform/next.config.ts` — **only if** `next build` (webpack) rejects the cross-root import: add `experimental.externalDir: true`. NOT `outputFileTracingIncludes` (dead under `output: undefined`).
- `scripts/compound-promote.sh` — source `strip.sh`, strip both `wc -c` reads, unit comment (NO over-strip guard here).
- `scripts/lint-agents-compound-sync.sh` — tighten the diagnostic at all THREE skew-asserting sites (top comment, mid-file block ~L146-152, `UNIT_NOTE`); constants unchanged.
- `scripts/rule-metrics-aggregate.sh` — one-line breadcrumb comment near `rules_unused_over_8w` → the item-1 learning note (spec-flow #5).
- `knowledge-base/engineering/architecture/decisions/ADR-094-freshness-last-reviewed-source-fix-and-audit-tripwire.md` — amendment.
- `knowledge-base/engineering/operations/runbooks/compound-promote-runbook.md` — skew prose → unit-exact (only if such prose exists; literals unchanged).

## Observability

```yaml
liveness_signal:
  what: existing Sentry heartbeat "scheduled-compound-promote" (unchanged) fired at end of each cron run
  cadence: weekly (cron "0 0 * * 0") + on manual-trigger event
  alert_target: Sentry cron monitor scheduled-compound-promote
  configured_in: apps/web-platform/server/inngest/functions/cron-compound-promote.ts (postSentryHeartbeat)
error_reporting:
  destination: Sentry via reportSilentFallback (@/server/observability); shell via ::warning::/::error:: annotations
  fail_loud: true
failure_modes:
  - mode: frontmatter over-strip on AGENTS.core.md (malformed/unterminated `---` consumes body → falsely-small byte count → could falsely PASS the always-loaded cap)
    detection: in-cron over-strip guard asserts [id:] rule-line-count invariant across the strip; on drop, falls back to RAW measurement and emits reportSilentFallback op="frontmatter-overstrip-fallback" (in-surface signal, discriminates over-strip from a genuine budget overflow)
    alert_route: Sentry (op="frontmatter-overstrip-fallback")
  - mode: strip.ts drifts from strip.py/strip.sh (three impls diverge)
    detection: CI parity test scripts/frontmatter-strip.test.sh (newly registered in test-all.sh want_bun) fails the build
    alert_route: CI red on PR
  - mode: post-apply always-loaded budget exceeded
    detection: existing reportSilentFallback op="byte-budget-overflow" (now on the stripped basis)
    alert_route: Sentry (op="byte-budget-overflow")
logs:
  where: Sentry + Inngest structured logger (logger.warn/info from within the cron step)
  retention: Sentry project default
discoverability_test:
  command: bash scripts/lint-agents-compound-sync.sh
  expected_output: "OK"
  # Single runnable probe (no ssh, no creds, no chaining — the contract is ONE
  # local command). The sync guard asserts the measurement-basis agreement this
  # change delivers. Fuller local verification (three-way parity + tsc + next
  # build) is documented in Acceptance Criteria; those are multi-command and not
  # the discoverability single-probe.
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-094** (the frontmatter-strip contract's governing ADR — SPEC.md cites #5999/ADR-094). Add a dated amendment recording: (a) a third byte-identical implementation `strip.ts` joins `strip.py`/`strip.sh`; (b) the two always-loaded-budget measurement consumers (`cron-compound-promote.ts`, `compound-promote.sh`) now measure on the frontmatter-stripped basis, closing the documented raw-vs-stripped skew #6461 accepted knowingly; (c) the parity test is now CI-enforced (`test-all.sh` `want_bun`). This is an EXTENSION of ADR-094's existing "keep implementations byte-identical" decision, not a new decision — no new ADR ordinal.

### C4 views
**No C4 impact.** All three model files were read (`model.c4`, `views.c4`, `spec.c4`) and grepped (`compound-promote|frontmatter|rule-metrics|cron` → zero hits). Enumeration per the completeness mandate:
- **External human actors:** none added/changed — no correspondent/reviewer/recipient enters or leaves.
- **External systems / vendors:** none — the cron's existing GitHub + Anthropic edges are unchanged; no new webhook/API/store.
- **Containers / data stores:** none — no new persistence; only the byte-measurement basis of an existing in-memory read changes.
- **Access relationships:** none — no owner/tenant/sharing change.
The touched surfaces (`cron-compound-promote`, the rule-metrics aggregator, the AGENTS governance layer, the frontmatter-strip lib) are not modeled as C4 elements today, so there is no view/element/edge to add or correct.

### Sequencing
No soak/staged truth — the decision is true at merge. ADR amendment ships in THIS PR.

## Domain Review

**Domains relevant:** Engineering (CTO) only.

This is an internal tooling / CI / governance-automation change with no user-facing surface. Mechanical UI-surface override: `## Files to Create`/`## Files to Edit` contain no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` path → Product **NONE**, Product/UX Gate skipped. No finance/legal/marketing/sales/support/product implications. CTO concerns (import boundary, CI shard, production write path) are captured in Risks & the build-verification gate.

## Open Code-Review Overlap

**None.** 61 open `code-review` issues scanned (`gh issue list --label code-review --state open`); zero reference `frontmatter-strip`, `cron-compound-promote`, `compound-promote.sh`, `lint-agents-compound-sync`, `rule-metrics`, or `strip.ts`.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] `scripts/lib/frontmatter-strip/strip.ts` exists, exports `stripFrontmatter`, and runs as a `bun run strip.ts < file` filter.
- [ ] `bash scripts/lib/frontmatter-strip.test.sh` reports `Fail: 0` and asserts three-way byte-identity (`strip.sh` == `strip.py` == `strip.ts`) across all 4 fixtures; the test SKIPs cleanly (exit 0) when `bun` is absent.
- [ ] `grep -n frontmatter-strip.test scripts/test-all.sh` shows the parity test registered inside the `want_bun` block.
- [ ] `cron-compound-promote.ts` measures both files through the extracted `measureAlwaysLoadedBytes` helper (strip + over-strip guard); an over-strip on `AGENTS.core.md` falls back to RAW + emits `op="frontmatter-overstrip-fallback"`.
- [ ] **(invariant, was Test Scenario 3 — spec-flow #1)** A unit test asserts `measureAlwaysLoadedBytes(indexText, coreText)` on a fixture equals `Buffer.byteLength(indexText,"utf8") + Buffer.byteLength(stripFrontmatter(coreText),"utf8")`, and a cross-language sanity case confirms the stripped-core byte count matches `python3 scripts/lib/frontmatter-strip/strip.py < core | wc -c`. A promoter that sums the wrong files / double-counts fails this, not just a shape check.
- [ ] **(over-strip guard test — spec-flow #2)** A test feeds an unterminated-`---` core and asserts the helper returns the RAW byte count (not the empty-strip count) and signals the fallback.
- [ ] `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` passes AND `cd apps/web-platform && npm run build` (`next build`/webpack) succeeds with the cross-root import resolved (add `experimental.externalDir: true` only if webpack rejects it).
- [ ] `scripts/compound-promote.sh` sources `strip.sh` and measures both files via `strip_frontmatter < file | wc -c`, with the same over-strip fallback.
- [ ] `bash scripts/lint-agents-compound-sync.sh` prints `OK`; its `UNIT_NOTE`/top comment no longer claims a raw-vs-stripped skew for the two measurement consumers.
- [ ] The `MAX_ALWAYS_LOADED_BYTES` / `PROPOSE_ALWAYS_LOADED_BUDGET` / `ALWAYS_LOADED_CAP` literals are UNCHANGED (still equal the authority) — verified by the green sync guard.
- [ ] ADR-094 amendment present (third impl + promoter unit-exactness + CI-enforced parity).
- [ ] Item-1 decision recorded in a `knowledge-base/project/learnings/` note (write-rate finding + 202-double-count clarification + "do not prune now" decision + re-eval trigger).
- [ ] `bash scripts/test-all.sh scripts` and `bash scripts/test-all.sh bun` pass; `bash scripts/lint-agents-rule-budget.test.sh` (T8) still passes.
- [ ] PR body uses `Closes #6794` and ticks all four issue checkboxes (3 code + the item-1 decision).

### Post-merge (operator)
- [ ] None. Deploy of `apps/web-platform/**` restarts the Hetzner container automatically (`web-platform-release.yml`); the next weekly `cron-compound-promote` fire exercises the new measurement. No manual operator step.

## Risks & Mitigations

### Precedent-Diff (deepen-plan Phase 4.4)

- **Cross-app-boundary import into web-platform:** no precedent (`grep -rnE "from ['\"](\.\./){3,}" apps/web-platform/{server,lib,app}` excluding in-app relatives → empty). Webpack (`next build`) enforces this boundary — a real constraint, not just convention.
- **Runtime bundler (architecture-reviewer, corrected):** the cron body compiles via `apps/web-platform/app/api/inngest/route.ts` (`serve({ functions: [cronCompoundPromote, …] })`) under **`next build` / webpack**. The esbuild `build:server` (`server/index.ts`) does NOT import function bodies — it only `.send()`s events and delegates HTTP to Next. So esbuild is irrelevant to `strip.ts`.
- **Scheduled-work pattern:** `cron-compound-promote.ts` is ALREADY an Inngest `createFunction` (ADR-033 canonical) — no new scheduled-job mechanism introduced; the plan only changes byte measurement inside it.
- **Frontmatter parity fixtures:** the empty-frontmatter-block case (`---\n---`) is the known cross-dialect divergence point (learning `2026-07-05-commit-audit-gate-delta-scoping-and-cross-lang-strip-parity.md`); fixture `empty-frontmatter-body.in` already exists and MUST be in the three-way parity assertion.

- **R1 — Cross-root webpack import (moderate).** The cron route is webpack-compiled (`next build` via `app/api/inngest/route.ts`); webpack enforces an app-root import boundary and `experimental.externalDir` is currently unset, so importing repo-root `strip.ts` MAY require enabling it. **Mitigation:** hard gate = `tsc --noEmit` AND `next build` succeeding before the phase is done; if webpack rejects the cross-root path, add `experimental.externalDir: true` to `next.config.ts` (a repo-wide build-config flag — call it out in the PR body). `outputFileTracingIncludes` is dead here (`output: undefined`). An in-app re-export shim does NOT avoid the boundary. **See the surfaced inline-alternative challenge** (`decision-challenges.md`): the simplicity-reviewer argues for inlining the 5-line strip in the cron (contract-pinned to SPEC.md) to eliminate this import entirely — recorded as a User-Challenge because it diverges from #6794's explicit "use `strip.ts` in `cron-compound-promote.ts`"; plan defaults to the issue's direction.
- **R2 — TS runtime absent in the scripts CI shard.** Running `strip.ts` needs `bun`/TS; the scripts shard has neither. **Mitigation:** register the parity test in the `want_bun` block (bun 1.3.14 present); the `.test.sh` skip-gates on `command -v bun` so local scripts-only runs still exit 0.
- **R3 — Over-strip is the DANGEROUS direction for the cron cap.** A malformed `AGENTS.core.md` strips to empty → smaller byte count → could falsely PASS the cap. **Mitigation:** rule-line-count invariant guard with RAW fallback + `op="frontmatter-overstrip-fallback"` (mirrors the linter's own guard). This is the affected-surface in-surface probe (Phase 2.9.2).
- **R4 — Byte vs char miscount.** `stripFrontmatter` returns a string; measuring `.length` counts UTF-16 code units, not bytes. **Mitigation:** always `Buffer.byteLength(…, "utf8")` in TS and `| wc -c` in shell — matches the linter's `len(stripped.encode("utf-8"))`.
- **R5 — Item-1 log location under a bare+worktree setup.** The primary checkout is a BARE repo; incident logs live in worktrees' `.claude/`. **Mitigation:** enumerate across worktrees + archives, never read the bare mirror (`hr-when-in-a-worktree-never-read-from-bare`); if the log is genuinely near-empty everywhere, THAT is the finding (telemetry-absence), which is exactly the decision item-1 asks for.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan fills it (threshold `none` + reason bullet).
- `AGENTS.md` has NO frontmatter — the strip is a no-op there; only `AGENTS.core.md` is affected. Do not "fix" the no-op away; applying the identity strip to both files is what matches the authority's semantics.
- Do not change the `MAX_ALWAYS_LOADED_BYTES` / `ALWAYS_LOADED_CAP` / `PROPOSE_ALWAYS_LOADED_BUDGET` literals — they are sync-guard SITES asserting CONSTANT equality with the linter. This PR changes the measurement BASIS, not the thresholds.
- The parity test is orphaned today; "extend parity enforcement" is meaningless without also registering it in CI — the registration is a required deliverable, not optional polish.

## Test Scenarios

1. **Three-way parity** — every fixture (`with-frontmatter`, `no-frontmatter`, `malformed-unterminated`, `empty-frontmatter-body`) yields byte-identical output from `strip.sh`, `strip.py`, `strip.ts`.
2. **No-op on AGENTS.md** — `stripFrontmatter(readFile AGENTS.md)` === input (no leading `---\n`).
3. **Stripped basis equals authority** — for a fixture AGENTS tree, the cron's `postBytes` and the shell's `ALWAYS_LOADED_NOW` equal `lint-agents-rule-budget.py`'s reported `B_ALWAYS` (extends T8's assertion to the promoters).
4. **Over-strip fallback** — an `AGENTS.core.md` with an unterminated `---` (rule-line count would drop): cron uses RAW and emits `op="frontmatter-overstrip-fallback"`; shell uses RAW and emits `::warning::`.
5. **Sync guard green + tightened diagnostic** — `lint-agents-compound-sync.sh` prints `OK`; grep confirms the `UNIT_NOTE` no longer asserts a skew.
6. **Item-1 decision durability** — the learning note exists and states the write-rate finding + "do not prune now" + re-eval trigger.
