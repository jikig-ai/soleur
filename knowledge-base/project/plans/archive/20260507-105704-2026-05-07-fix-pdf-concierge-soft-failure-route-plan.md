---
type: bug-fix
status: ready
classification: user-facing-prompt-routing
requires_cpo_signoff: true
related_prs: [3384, 3338, 3294, 3293, 3287, 3263, 3253]
related_issues: [3346, 3342, 3343, 3344, 3345, 3332, 3243, 3376]
brand_survival_threshold: single-user-incident
deepened: 2026-05-07
---

# fix(cc-concierge): partition PDF soft-failure classes to gated Read path so SDK Read is attempted before refusal

## Enhancement Summary

**Deepened on:** 2026-05-07
**Sections enhanced:** Overview (SDK-runtime-semantics grounding), Hypotheses, Acceptance Criteria, Sharp Edges
**Verification gates passed:** Phase 4.5 (no SSH/network triggers — skipped), Phase 4.6 User-Brand Impact halt (heading present, body substantive, threshold = `single-user incident`), SDK-pin verification (claude-agent-sdk@0.2.85 `sdk-tools.d.ts` cited verbatim), live PR/issue citation gate (#3384 MERGED, #3338 MERGED, #3376 CLOSED — all confirmed via `gh pr view` / `gh issue view`).

### Key Improvements

1. **SDK-runtime-semantics claim now pinned to verbatim docstring.** The original plan asserted "Anthropic Files API runs a different pipeline" as a hypothesis. Deepened plan now cites the installed `@anthropic-ai/claude-agent-sdk@0.2.85` `sdk-tools.d.ts:184-200` verbatim, where `type: "pdf"` is a first-class tool-output variant carrying `filePath` + `base64` + `originalSize`, plus `sdk-tools.d.ts:381-383` where `FileReadInput.pages` is documented as "Only applicable to PDF files. Maximum 20 pages per request." This eliminates the Insight-#2-of-cascade-structural-fix risk class (paraphrased SDK semantics → load-bearing fix shipped wrong).
2. **Live citation verification logged.** All `#NNNN` numbers in frontmatter `related_prs` and prose were re-verified via `gh pr view` / `gh issue view` in the same deepen pass. Output captured in §"Research Insights — citation verification log".
3. **Brand-survival threshold escalation rationale added.** The original plan declared `single-user incident` correctly but did not enumerate which adjacent thresholds were considered and why they were rejected. Deepened plan adds a one-paragraph rationale so the user-impact-reviewer at PR time has the framing trail.
4. **Test-compat audit broadened.** Per learning `2026-05-05-defense-relaxation-must-name-new-ceiling.md`, when a routing semantic changes, every test that pinned the old semantic must be enumerated. Original plan named 3 test files; the deepened plan re-grepped `documentExtractError` across `apps/web-platform/test/` and confirmed 4 files reference it (the e2e file, the unreadable-directive file, `cc-dispatcher.test.ts:557`, `cc-dispatcher-concierge-context.test.ts`). The dispatcher tests pin "documentExtractError is forwarded through the runner" (producer-side, not router-side) and stay green under this change — pinned with explicit "no-edit-required" entry below.

### New Considerations Discovered

- The `sanitizePromptString` 256-cap is irrelevant to `PdfExtractErrorClass` literal members (max 24 chars), but the order of operations matters for U+2028 smuggling — pinned as a Sharp Edge with a unit-test recommendation.
- `unreadableCopyForClass` (the per-class copy switch at `soleur-go-runner.ts:185`) intentionally remains exhaustive over all 7 classes even though only 2 will reach the unreadable directive after this change. Deepened plan upgrades this from a buried Sharp Edge to an explicit "DO NOT prune" Acceptance Criterion — the soft-class branches are the safety net for any future caller bypass.

## Overview

PR #3384 introduced `buildPdfUnreadableDirective` to break the apt-get/pdftotext shell-cascade that #3338's structural fix had not fully closed. The directive's third sentence — *"do not propose installing dependencies, do not run shell commands, and do not attempt to discover or open the file via other tools"* — is load-bearing against the cascade, but it overcorrects on **soft** failure classes where the SDK Read tool's native PDF support (Anthropic Files API path) would in fact succeed.

Two user-reproduced PDFs (`Manning Book - Effective Platform Engineering.pdf`, `Au Chat Potan - Presentation Projet-10.pdf`) exhibit this exact regression: the in-process `pdfjs-dist` extractor returns a soft failure (`oversized_buffer` or `corrupted` shape — both PDFs are large and Manning's PDF is heavily linearized, which the legacy build of pdfjs-dist often rejects with parse-shaped errors), the runner picks `buildPdfUnreadableDirective`, the model dutifully refuses upfront with *"I can't read this specific PDF — it appears corrupted"*, and the user has to manually steer it to use Read — at which point the SDK Read tool succeeds via the Anthropic Files API path (which uses Anthropic's own PDF understanding pipeline, NOT pdfjs-dist).

The fix is to **partition `PdfExtractErrorClass`** into two routing buckets:

- **SDK-Read-may-still-help (soft failures, route to `buildPdfGatedDirective`):** `oversized_buffer`, `corrupted`, `parse_error`, `lazy_import_failed`, `read_failed`. These are pdfjs-dist-side limitations; Anthropic's Files API runs a different pipeline and frequently succeeds where pdfjs-dist fails (different parser, no in-process buffer cap, native handling of linearized/encrypted-aware PDFs). The gated directive's named-binary exclusion list still bounds the apt-get cascade — we keep that brake even on the soft-failure route.
- **SDK-Read-genuinely-cannot-help (hard failures, keep on `buildPdfUnreadableDirective`):** `encrypted` (Anthropic Files API also rejects password-protected PDFs without the password), `empty_text` (no text layer at all — a scanned/image-only PDF; the user must paste text, OCR is a separate feature, and Anthropic's PDF support is text-extraction-based). On these, the upfront refusal is the correct behavior and saves a wasted Read attempt.

The partition lives at `apps/web-platform/server/soleur-go-runner.ts:771` (the conditional that picks `buildPdfUnreadableDirective` over `buildPdfGatedDirective`). The directive constants and `unreadableCopyForClass` switch stay intact — only the **routing predicate** changes. The `PDF_GATED_DIRECTIVE_LEAD` vs `PDF_UNREADABLE_DIRECTIVE_LEAD` invariants (mutual-exclusion in test assertions) MUST hold without modification on each branch — this is the regression surface for #3384.

## User-Brand Impact

**If this lands broken, the user experiences:** a regression in either direction — (a) the apt-get/find/pdftotext cascade returns on a soft-failure PDF (`buildPdfGatedDirective` named-binary list mitigates but does not eliminate the cascade per the structural-fix learning), surfacing the Bash modal with shell strings to non-technical end users; or (b) the upfront refusal continues firing on PDFs the SDK Read tool could read, leaving the user with the same primary-feature dead-end that motivated this change.

**If this leaks, the user's workflow is exposed via:** the wrong directive landing in the system prompt is a prompt-engineering bug, not a credential leak. There is no PII or secret exposure surface — the failure modes are routing/UX regressions on a primary user-facing feature (PDF summarize is the headline KB Concierge capability).

**Brand-survival threshold:** `single-user incident`. PDF summarize is the primary value-prop of the KB Concierge sidebar. A user who watches their book PDF refuse upfront, manually steers, sees Read succeed, and concludes "the model is broken" is a single-user incident with brand-relevant blast radius (founders post these failure videos publicly). The two reproduction PDFs above are real user PDFs — the damage is already in flight on the `unreadable` route. Per `hr-weigh-every-decision-against-target-user-impact`, requires CPO sign-off at plan time and `user-impact-reviewer` invocation at PR review time.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality (verified) | Plan response |
|------------|---------------------|---------------|
| "Partition documentExtractError classes around line 771" | Confirmed: `soleur-go-runner.ts:771` is the `if (args.documentExtractError)` conditional inside the PDF branch of `buildSoleurGoSystemPrompt`. `kb-document-resolver.ts` is the only producer of `documentExtractError` (lines 205, 287). `cc-dispatcher.ts` forwards it through `DispatchArgs.documentExtractError` (lines 755, 800, 1042). | Edit confined to one branch in `soleur-go-runner.ts`; routing stays out of resolver/dispatcher. |
| "Keep PDF_GATED_DIRECTIVE_LEAD vs PDF_UNREADABLE_DIRECTIVE_LEAD invariants intact" | Confirmed: lead constants at `soleur-go-runner.ts:101` and `:138`. Tests in `pdf-unreadable-directive.test.ts` (5 cases) and `cc-concierge-pdf-summarize-e2e.test.ts` (Phase 4.1, 4.2) assert mutual exclusion via `toContain` / `not.toContain`. | The lead constants and `buildPdfUnreadableDirective` body are NOT modified. Only the routing predicate at `:771` changes. The mutual-exclusion property is preserved per error class on its assigned route. |
| "Soft failures: oversized_buffer, corrupted, parse_error, lazy_import_failed, read_failed should route to gated" | Confirmed: `PdfExtractErrorClass` defined at `pdf-text-extract.ts:57-70` lists exactly these 7 members: `oversized_buffer`, `lazy_import_failed`, `encrypted`, `corrupted`, `parse_error`, `empty_text`, `read_failed`. Soft set = 5 / hard set = 2. | Build a `SOFT_FAILURE_CLASSES: ReadonlySet<PdfExtractErrorClass>` (or equivalent typed predicate) at module scope in `soleur-go-runner.ts`. Switch on it in the `:771` conditional. |
| "tests to update: cc-concierge-pdf-summarize-e2e.test.ts and read-tool-pdf-capability.test.ts" | Partially confirmed: e2e test has Phase 4.2 asserting `read_failed` → `PDF_UNREADABLE_DIRECTIVE_LEAD`, which under this fix flips to `PDF_GATED_DIRECTIVE_LEAD`. read-tool-pdf-capability covers the inline + gated cases but does not yet cover the documentExtractError soft-route. The **canonical** test for this routing is `pdf-unreadable-directive.test.ts` (line 86–96 currently asserts `corrupted`/`parse_error` on the unreadable lead) — that file MUST flip too. | Update **three** test files: (1) `pdf-unreadable-directive.test.ts` — flip `corrupted`/`parse_error`/`oversized_buffer`/`lazy_import_failed`/`read_failed` to assert `PDF_GATED_DIRECTIVE_LEAD` and absence of `PDF_UNREADABLE_DIRECTIVE_LEAD`, keep `encrypted`/`empty_text` on the unreadable lead, **and** keep the no-cascade pin (`expectNoCascade`) on the soft-route assertions because the gated directive itself bounds the cascade via its named-binary list (Insight per #3294); (2) `cc-concierge-pdf-summarize-e2e.test.ts` Phase 4.2 — flip `read_failed` to assert gated lead; (3) `read-tool-pdf-capability.test.ts` — add explicit case-coverage for each `PdfExtractErrorClass` member as the description prescribes. |
| "Sentry events show ≥N hits over T days for these classes" | Skipped per learning `2026-05-05-trace-callgraph-from-entrypoint-when-placing-guards.md`: SDK errors land as wrapped titles; substring-on-class searches return zero. Two user-reproduced PDFs are the architectural-fact path that overrides empirical-zero. | Treat the two user-reproduced PDFs as ground truth. Filed scope-out: post-merge, run a 7-day Sentry sweep on `op:extractPdfText` breadcrumbs and confirm soft classes outnumber hard classes (informational; not a merge gate). |
| "agent-runner.ts (legacy leader) consumes documentExtractError" | **Refuted.** `agent-runner.ts:858` only calls `buildPdfGatedDirective` for PDFs with no error-class branching; the legacy leader path never sees `documentExtractError`. | Scope confined to `soleur-go-runner.ts` (Concierge router only). Legacy leader behavior is unaffected — no parity work needed. The lock-step parity invariant (Insight 4 of structural-fix learning) is preserved because `buildPdfGatedDirective` is unchanged. |

## Open Code-Review Overlap

`gh issue list --label code-review --state open` returned `[]` (no open code-review issues). None.

## Hypotheses

This is a routing-correction follow-up to #3384. The hypothesis is structural, not investigative:

1. **The SDK Read tool's PDF pipeline is structurally separate from `pdfjs-dist@5.4.296/legacy`.** Per `sdk-tools.d.ts:184-200` (cited verbatim in §"Research Insights"), the SDK ships a first-class `type: "pdf"` tool-output variant carrying base64-encoded PDF bytes, and `FileReadInput.pages` is documented as "Only applicable to PDF files. Maximum 20 pages per request." The Read tool is therefore PDF-aware end-to-end — different parser, no in-process buffer cap, native Anthropic PDF understanding. The user's manual-steer success on both repro PDFs is the empirical evidence that this path **may** succeed where `pdfjs-dist` fails. The plan's job is to stop blocking the model from trying that path on `pdfjs-dist`-side soft failures. Sharper-than-original claim: "Read may succeed where pdfjs-dist fails" (not "will succeed") — the 20-page-per-request cap means very long PDFs require multiple Read calls, which is a model-behavior orchestration question outside this plan's scope.
2. **The named-binary cascade is bounded by `buildPdfGatedDirective`'s exclusion list, not by the unreadable directive's `do not attempt to discover` clause.** Per learning Insight 1 (prompt iteration plateaus) and Insight 2 (SDK `disallowedTools` is the structural brake), the apt-get cascade is held back by (a) the named-binary list in the gated directive itself and (b) `disallowedTools: [Bash, Edit, Write]` in `cc-dispatcher.ts realSdkQueryFactory`. Routing soft failures to the gated path does NOT regress the cascade defense — it just lets Read fire.
3. **`encrypted` and `empty_text` are NOT cases where Read can recover.** Anthropic's PDF support is text-extraction-based; a password-protected PDF rejects without the password regardless of which extractor handles it, and a scanned/image-only PDF has no text layer at all (OCR is out of scope). On these, the upfront refusal is correct and saves a wasted Anthropic API round-trip plus the latency of a Read attempt.

No SSH/network triggers. Phase 1.4 skipped.

## Research Insights

### SDK-runtime-semantics grounding (verbatim from installed `@anthropic-ai/claude-agent-sdk@0.2.85`)

The original plan's hypothesis "Anthropic Files API runs a different pipeline than `pdfjs-dist@5.4.296/legacy`" needs SDK-side grounding to avoid the Insight-#2 misread that bit #3338. The installed SDK (pinned to `0.2.85` in `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/package.json`) ships these PDF-aware type definitions:

**`sdk-tools.d.ts:184-200` — PDF as a first-class tool-output variant:**

```ts
| {
    type: "pdf";
    file: {
      /**
       * The path to the PDF file
       */
      filePath: string;
      /**
       * Base64-encoded PDF data
       */
      base64: string;
      /**
       * Original file size in bytes
       */
      originalSize: number;
    };
  }
```

**`sdk-tools.d.ts:201-221` — `parts` variant for split-page handling:**

```ts
| {
    type: "parts";
    file: {
      /** The path to the PDF file */
      filePath: string;
      /** Original file size in bytes */
      originalSize: number;
      /** Number of pages extracted */
      count: number;
      /** Directory containing extracted page images */
      outputDir: string;
    };
  };
```

**`sdk-tools.d.ts:367-384` — Read tool's `FileReadInput` PDF awareness:**

```ts
file_path: string;
// ...
/**
 * Page range for PDF files (e.g., "1-5", "3", "10-20"). Only applicable to PDF files. Maximum 20 pages per request.
 */
pages?: string;
```

**Load-bearing claim grounded:** The Read tool is type-level aware of PDFs (`pages` parameter is "Only applicable to PDF files"), and the SDK's tool-output type system carries a dedicated `type: "pdf"` variant with base64-encoded PDF bytes — separate from the text-output path. This is the structural surface the soft-failure route exploits: when `pdfjs-dist` (the in-process extractor) rejects, routing the model to call Read on the absolute path lets the SDK's PDF pipeline take over. The SDK's `pages` parameter and `parts` variant indicate the runtime supports paginated PDF reads end-to-end.

**Note on the 20-page cap:** `pages` is capped at 20 pages per Read request. A fully-text-extracted PDF via Read is therefore not equivalent to the in-process extractor's `MAX_PAGES = 500` for arbitrarily long PDFs — the model may need to issue multiple Read calls with different `pages` ranges. This is a model-behavior question, not a partition-correctness question, but the plan should not promise "Read always succeeds where pdfjs-dist fails." Sharper claim: "Read **may** succeed where pdfjs-dist fails (different parser, no in-process buffer cap, native PDF pipeline) — the partition lets the model attempt Read instead of refusing upfront."

### Citation verification log (live `gh` queries, 2026-05-07)

Per the deepen-plan quality check on PR/issue numbers:

```
$ gh pr view 3384 --json state,title --jq '{state, title}'
{"state":"MERGED","title":"fix(cc-concierge): close gated-Read fallback path on workspace PDF summarize"}

$ gh pr view 3338 --json state,title --jq '{state, title}'
{"state":"MERGED","title":"WIP: feat-one-shot-concierge-pdf-summary-fix"}

$ gh issue view 3376 --json state,title --jq '{state, title}'
{"state":"CLOSED","title":"follow-through: re-run user's PDF reproduction post-#3353 deploy"}

$ git log --grep="#3384\|#3338" --oneline -10
a7b54c2f fix(cc-concierge): close gated-Read fallback path on workspace PDF summarize (#3384)
b5112203 fix(cc-concierge): align PDF extractor cap with upload cap and surface typed failure classes (#3353)
e2b032ca WIP: feat-one-shot-concierge-pdf-summary-fix (#3338)
```

All cited PRs MERGED; #3376 CLOSED (correctly — the 5th-iteration fix landed; this plan addresses a NEW post-#3384 routing surface, not a re-open of #3376). #3384 commit `a7b54c2f` confirms the cited line `:771` partition is on the `feat-one-shot-pdf-concierge-soft-failure-route` branch's HEAD (current).

### Test-compat audit — every reader of `documentExtractError` enumerated

Per learning `2026-05-05-defense-relaxation-must-name-new-ceiling.md` (when a semantic changes, sample-of-tests is insufficient):

```
$ rg "documentExtractError" apps/web-platform/test/ -l
apps/web-platform/test/cc-concierge-pdf-summarize-e2e.test.ts
apps/web-platform/test/cc-dispatcher.test.ts
apps/web-platform/test/cc-dispatcher-concierge-context.test.ts
apps/web-platform/test/pdf-unreadable-directive.test.ts
```

| File | Routing-pinned? | Required edit |
|------|-----------------|---------------|
| `pdf-unreadable-directive.test.ts` | YES (canonical) | Flip 5 soft-class assertions (Phase 3a). |
| `cc-concierge-pdf-summarize-e2e.test.ts` | YES (Phase 4.2 only) | Flip Phase 4.2 `read_failed` assertions (Phase 3b). |
| `cc-dispatcher.test.ts:557` | NO — pins **forwarding** through the runner contract (`{ documentExtractError: "empty_text" }` → spread into runner.dispatch). Producer-side, not router-side. | NO EDIT — `empty_text` is a hard class and would route to unreadable under the new partition either way; the test asserts the field forwards, not which directive fires. Stays green. |
| `cc-dispatcher-concierge-context.test.ts` | NO — pins **resolver→dispatcher** wire ("corrupted PDFs surface `documentExtractError=corrupted` with a Sentry mirror"). Resolver/dispatcher boundary, not runner-prompt boundary. | NO EDIT — the resolver still surfaces the typed class; only the runner's downstream routing changes. Stays green. |

This 4-file audit is the test-compat enumeration that the original plan's prose ("update read-tool-pdf-capability.test.ts") missed. The dispatcher tests stay green by construction; calling that out explicitly prevents a future maintainer from mistaking "forwarding behavior" for "routing behavior."

### Brand-survival threshold rationale (escalation trail)

Why `single-user incident` and not `aggregate pattern`:

- **Aggregate pattern** would imply "one user's failure is part of a slow-burn metric" — false here. The two reproduction PDFs are real user PDFs being summarized as the headline KB Concierge feature. A single user watching the model refuse and then succeed-on-steer concludes "this product is broken" in the same session — there is no aggregate-window saving grace.
- **`none` was rejected** because the diff routes into `apps/web-platform/server/soleur-go-runner.ts`, which matches the canonical sensitive-path regex (`^apps/web-platform/(server|...)`). A `threshold: none` decision would require a `threshold: none, reason: <one-sentence>` scope-out to pass preflight Check 6 — which would be incorrect framing because the threshold IS load-bearing here.
- **`single-user incident` is the correct framing** because the failure mode is per-user, per-PDF, observable in real time, and the brand-survival concern is the founder-posts-failure-video blast radius (single user → public artifact → reputational hit). CPO sign-off + `user-impact-reviewer` at PR time is the proportionate gate.

## Implementation Phases

### Phase 1 — Extract typed soft-failure predicate (RED → GREEN)

**Files to edit:**

- `apps/web-platform/server/soleur-go-runner.ts` (around line 771)

**Files to create:** none.

Add a module-scoped `ReadonlySet<PdfExtractErrorClass>` named `PDF_SOFT_FAILURE_CLASSES` containing exactly `["oversized_buffer", "corrupted", "parse_error", "lazy_import_failed", "read_failed"]`. The `Set` is typed against `PdfExtractErrorClass` so a future addition to the union forces an explicit decision (the existing `unreadableCopyForClass` exhaustive switch at line 188 still rails on `: never`, but the routing predicate is a separate exhaustiveness surface and needs its own rail).

Concretely, add **two** complementary typed sets so the union partition is total at compile time:

```ts
// apps/web-platform/server/soleur-go-runner.ts (above buildSoleurGoSystemPrompt)

/**
 * Soft pdfjs-dist failures where the Anthropic Files API path (SDK Read tool's
 * native PDF support) may still succeed. Routes to `buildPdfGatedDirective`
 * so the model attempts Read with the absolute workspace path before refusing.
 *
 * The cascade defense is preserved: `buildPdfGatedDirective` itself names the
 * forbidden binaries (pdftotext / pdfplumber / etc.) and `cc-dispatcher`'s
 * `extraDisallowedTools: [Bash, Edit, Write]` is the SDK-level hard brake.
 */
const PDF_SOFT_FAILURE_CLASSES: ReadonlySet<PdfExtractErrorClass> = new Set([
  "oversized_buffer",
  "corrupted",
  "parse_error",
  "lazy_import_failed",
  "read_failed",
]);

/**
 * Hard failures where SDK Read genuinely cannot help. Stays on
 * `buildPdfUnreadableDirective` — the upfront refusal is correct and saves
 * a wasted Read attempt + Files API round-trip.
 */
const PDF_HARD_FAILURE_CLASSES: ReadonlySet<PdfExtractErrorClass> = new Set([
  "encrypted",
  "empty_text",
]);

// Compile-time exhaustiveness rail on the partition. If `PdfExtractErrorClass`
// widens, this assertion fails until the new member lands in exactly one of
// the two sets above.
type _PartitionExhaustive =
  | (typeof PDF_SOFT_FAILURE_CLASSES extends ReadonlySet<infer T> ? T : never)
  | (typeof PDF_HARD_FAILURE_CLASSES extends ReadonlySet<infer T> ? T : never);
type _AssertPartitionTotal = PdfExtractErrorClass extends _PartitionExhaustive
  ? _PartitionExhaustive extends PdfExtractErrorClass
    ? true
    : never
  : never;
const _partitionExhaustive: _AssertPartitionTotal = true;
void _partitionExhaustive;

function isPdfSoftFailure(
  errorClass: PdfExtractErrorClass | string,
): errorClass is PdfExtractErrorClass {
  // Set#has on a typed set is a runtime predicate; the type-cast is safe
  // because the set's element type is the union itself.
  return PDF_SOFT_FAILURE_CLASSES.has(errorClass as PdfExtractErrorClass);
}
```

**Note on the cross-module-wire-compat case:** `documentExtractError` is typed as `PdfExtractErrorClass` end-to-end (resolver → dispatcher → runner), but `buildPdfUnreadableDirective` accepts `string` for forward-compat with serialized payloads. If a future caller threads an unknown string (off-union value), `isPdfSoftFailure` returns `false` and the value falls through to the unreadable path — safe-by-construction (we don't optimistically gate Read on a class we don't recognize).

### Phase 2 — Re-route soft failures at the routing predicate

**Files to edit:**

- `apps/web-platform/server/soleur-go-runner.ts` (lines 761–789, the PDF branch)

The current shape:

```ts
if (args.documentExtractError) {
  const safeErrorClass = sanitizePromptString(args.documentExtractError);
  artifactDirective = buildPdfUnreadableDirective(safeArtifactPath, NO_ASK, safeErrorClass);
} else if (pdfBody.length > 0 && pdfBody.length <= MAX_DOCUMENT_INLINE_BYTES) {
  artifactDirective = `... <document> wrapper ...`;
} else {
  artifactDirective = buildPdfGatedDirective(safeArtifactPath, absoluteReadPath, NO_ASK);
}
```

becomes:

```ts
if (args.documentExtractError) {
  const safeErrorClass = sanitizePromptString(args.documentExtractError);
  if (isPdfSoftFailure(safeErrorClass)) {
    // 2026-05-07: soft pdfjs-dist failures (oversized_buffer / corrupted /
    // parse_error / lazy_import_failed / read_failed) route to the gated
    // Read directive so the model attempts SDK Read with the absolute
    // workspace path before refusing. Anthropic Files API frequently
    // succeeds where pdfjs-dist fails (different parser, no in-process
    // buffer cap). Cascade defense preserved by the gated directive's
    // named-binary list + `disallowedTools: [Bash, Edit, Write]` in
    // cc-dispatcher. See plan 2026-05-07-fix-pdf-concierge-soft-failure-route.
    artifactDirective = buildPdfGatedDirective(safeArtifactPath, absoluteReadPath, NO_ASK);
  } else {
    // Hard failures (encrypted / empty_text) — SDK Read cannot recover
    // (password-protected PDFs reject without the password; image-only
    // PDFs have no text layer). Upfront refusal is correct.
    artifactDirective = buildPdfUnreadableDirective(safeArtifactPath, NO_ASK, safeErrorClass);
  }
} else if (pdfBody.length > 0 && pdfBody.length <= MAX_DOCUMENT_INLINE_BYTES) {
  artifactDirective = `... <document> wrapper ...`; // unchanged
} else {
  artifactDirective = buildPdfGatedDirective(safeArtifactPath, absoluteReadPath, NO_ASK); // unchanged
}
```

The inline-body branch (defense-in-depth: `documentExtractError` wins over a partial `documentContent` per the existing comment on line 761–770) keeps its precedence — `documentExtractError` is always checked first, then partitioned.

**Sanitizer-after-Set-membership ordering:** `sanitizePromptString` strips control chars + U+2028/U+2029 + 256-caps. The `PdfExtractErrorClass` literal members are all ASCII-clean lower_snake_case ≤24 chars, so the sanitizer is a no-op on canonical inputs. We Set-check the **sanitized** value (not the raw arg) so a future poisoned upstream that smuggles a U+2028 mid-class-name does not match `PDF_SOFT_FAILURE_CLASSES.has("oversized_buffer<U+2028>")` and the value falls through to the unreadable path — safe-by-construction (one of the three hazard classes already enumerated in the Sharp Edges of `cq-regex-unicode-separators-escape-only`).

### Phase 3 — Test updates (TDD per `cq-write-failing-tests-before`)

**Files to edit:**

- `apps/web-platform/test/pdf-unreadable-directive.test.ts` (canonical routing test — current authoritative source)
- `apps/web-platform/test/cc-concierge-pdf-summarize-e2e.test.ts` (e2e Phase 4.2)
- `apps/web-platform/test/read-tool-pdf-capability.test.ts` (capability + new routing case-coverage)

**Files to create:**

- `apps/web-platform/test/pdf-extract-error-routing.test.ts` (NEW — explicit case-coverage per `PdfExtractErrorClass` member, per the description's "Add explicit case-coverage for each PdfExtractErrorClass routing")

#### 3a. `pdf-unreadable-directive.test.ts` — flip soft-class assertions

Currently at line 86–96, the test asserts `corrupted` / `parse_error` produce `PDF_UNREADABLE_DIRECTIVE_LEAD` (via the absent-of-`PDF_GATED_DIRECTIVE_LEAD` pin). Flip:

- `oversized_buffer` (line 48–59): assert `prompt.toContain(PDF_GATED_DIRECTIVE_LEAD)`, assert `prompt.not.toContain(PDF_UNREADABLE_DIRECTIVE_LEAD)`, **keep** `expectNoCascade(prompt)` because the gated directive's named-binary list still bounds the cascade (cascade absence is the load-bearing invariant; lead-substring is the routing pin).
- `corrupted` / `parse_error` (line 86–96): same flip.
- `lazy_import_failed` (line 99–114): same flip.
- Add a new soft-class test for `read_failed` (currently uncovered in this file because it was added later for #3376; the e2e file covers it). Same flip pattern.
- `encrypted` (line 61–69): keep on unreadable lead. NO change.
- `empty_text` (line 72–84): keep on unreadable lead. NO change.
- "documentExtractError WITHOUT documentKind=pdf" (line 133–145): keep — checks the kind-gate, not the partition.
- "documentExtractError unset on documentKind=pdf preserves inline-or-gated" (line 147–158): keep — checks the inline-body branch, not the partition.
- "precedence: documentExtractError wins over partial documentContent" (line 160–176): currently uses `oversized_buffer`. **Flip the assertion:** under the new partition, `oversized_buffer` routes to gated, so the body still does NOT inline (the precedence invariant is "extract-error wins over partial content" — that holds regardless of which branch the extract-error routes to), but the lead substring flips from "too large" to `PDF_GATED_DIRECTIVE_LEAD`. **Also add a hard-class twin** of this test using `encrypted` to lock the unreadable-precedence half of the partition.
- "chat-affordance hint" (line 178–190): currently uses `encrypted`. KEEP — `encrypted` stays on unreadable, so the paste/paperclip hint is still asserted there.

The describe block name should also pivot from "buildPdfUnreadableDirective via buildSoleurGoSystemPrompt" to something like "PDF extract-error routing partition (soft → gated, hard → unreadable)". Optional rename — preserves git history if kept; can stay as-is since the file's scope is now partition-focused.

#### 3b. `cc-concierge-pdf-summarize-e2e.test.ts` — flip Phase 4.2

Phase 4.2 (line 120–161) currently asserts that a `read_failed` extract-error produces:
- `PDF_UNREADABLE_DIRECTIVE_LEAD` present
- `PDF_GATED_DIRECTIVE_LEAD` absent
- read_failed-specific copy `"I couldn't open this PDF on my end"` present
- "workspace boundary" / "outside the workspace" never appears in the system prompt (load-bearing user-facing leak guard)

Under the new partition, `read_failed` routes to gated. Flip:
- `PDF_GATED_DIRECTIVE_LEAD` present (was absent)
- `PDF_UNREADABLE_DIRECTIVE_LEAD` absent (was present)
- read_failed-specific copy `"I couldn't open this PDF on my end"` MUST NOT be in the prompt (that copy is part of the unreadable directive; the gated directive is generic across error classes — no per-class copy)
- "workspace boundary" / "outside the workspace" still NEVER appears (this guard is independent of the partition and must hold on BOTH directives — pin remains)

Phase 4.1 (successful extract → inline body, lead absences) is unaffected. Phase 4.3 / 4.3b (Bug A1 absolute-path injection) are unaffected.

#### 3c. `read-tool-pdf-capability.test.ts` — add per-class case coverage

The description explicitly says: *"Add explicit case-coverage for each PdfExtractErrorClass routing."* This file currently covers Scenarios 1–10 on the baseline + inline + gated paths but does NOT exhaustively walk `PdfExtractErrorClass` against the routing predicate. Add a new describe block:

```ts
describe("PdfExtractErrorClass routing partition", () => {
  const SOFT_CLASSES = ["oversized_buffer", "corrupted", "parse_error", "lazy_import_failed", "read_failed"] as const;
  const HARD_CLASSES = ["encrypted", "empty_text"] as const;

  for (const cls of SOFT_CLASSES) {
    it(`${cls}: routes to PDF_GATED_DIRECTIVE_LEAD (SDK Read may still help via Anthropic Files API)`, () => {
      const prompt = buildSoleurGoSystemPrompt({
        artifactPath: `knowledge-base/probe.pdf`,
        documentKind: "pdf",
        documentExtractError: cls,
      });
      expect(prompt).toContain(PDF_GATED_DIRECTIVE_LEAD);
      expect(prompt).not.toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
    });
  }

  for (const cls of HARD_CLASSES) {
    it(`${cls}: routes to PDF_UNREADABLE_DIRECTIVE_LEAD (SDK Read genuinely cannot help)`, () => {
      const prompt = buildSoleurGoSystemPrompt({
        artifactPath: `knowledge-base/probe.pdf`,
        documentKind: "pdf",
        documentExtractError: cls,
      });
      expect(prompt).toContain(PDF_UNREADABLE_DIRECTIVE_LEAD);
      expect(prompt).not.toContain(PDF_GATED_DIRECTIVE_LEAD);
    });
  }
});
```

This is the **partition surface lock**: a future addition to `PdfExtractErrorClass` that lands without a corresponding entry in `SOFT_CLASSES` or `HARD_CLASSES` (and without the type-level rail in Phase 1 catching it) will leave the new class untested at the routing layer. The for-loop is the test-time mirror of the compile-time `_AssertPartitionTotal` rail.

#### 3d. `pdf-extract-error-routing.test.ts` (NEW) — exhaustive partition lock

Optional but recommended per the Sharp Edge in `cq-union-widening-grep-three-patterns`: extract a dedicated test file that owns the routing partition exhaustively, importing the typed sets from a new exported surface. **If cost-of-extraction outweighs the lock, fold the test into 3c instead** and skip this file. Default to the in-3c form for minimum-diff; create the new file only if review feedback requests dedicated ownership.

### Phase 4 — Update existing comment on line 761–770

The comment currently says:

> 2026-05-06 follow-up: `documentExtractError` wins over inlining. ... if a future refactor lets a partial body slip past, the extractor's typed failure signal must still route to the unreadable directive — the gated Read path is the apt-get-cascade anchor and we cannot fall back to it on a known failure class.

That last clause is now wrong. Update to:

> 2026-05-07 follow-up to #3384: `documentExtractError` wins over inlining, but the routing within the extract-error branch is now partitioned — soft pdfjs-dist failures (oversized_buffer / corrupted / parse_error / lazy_import_failed / read_failed) flow to `buildPdfGatedDirective` so the SDK Read tool can attempt the Anthropic Files API path; hard failures (encrypted / empty_text) stay on `buildPdfUnreadableDirective` because Read genuinely cannot recover. The apt-get-cascade defense is preserved by the gated directive's named-binary list and `disallowedTools: [Bash, Edit, Write]` in cc-dispatcher. See plan 2026-05-07-fix-pdf-concierge-soft-failure-route.

### Phase 5 — Compound + ship

Per `wg-before-every-commit-run-compound-skill`, run `skill: soleur:compound` before commit. The session learning surface here: *"The original #3384 directive's `do not attempt to discover` clause was over-scoped — error classes carry sub-distinctions (in-process-extractor-side vs Anthropic-API-side capability), and a one-size routing decision regresses the user-facing primary feature even while it correctly bounds the cascade."* This is partition-design knowledge, not a hidden constraint — discoverable via the user-reproduced PDFs — so a learning file alone suffices per `wg-every-session-error-must-produce-either`'s discoverability exit. No AGENTS.md rule.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/server/soleur-go-runner.ts` exports `PDF_SOFT_FAILURE_CLASSES` and `PDF_HARD_FAILURE_CLASSES` as `ReadonlySet<PdfExtractErrorClass>`. The two sets are disjoint and their union equals `PdfExtractErrorClass`. Compile-time `_AssertPartitionTotal` rail in place.
- [ ] The routing predicate at `:771` partitions on `isPdfSoftFailure(safeErrorClass)`. Soft → `buildPdfGatedDirective`; hard → `buildPdfUnreadableDirective`.
- [ ] `pdf-unreadable-directive.test.ts` flipped: 5 soft-class tests assert `PDF_GATED_DIRECTIVE_LEAD` + absence of `PDF_UNREADABLE_DIRECTIVE_LEAD`, with `expectNoCascade` retained on each. 2 hard-class tests (`encrypted`, `empty_text`) keep their existing assertions. Precedence test updated to soft-class lead substring.
- [ ] `cc-concierge-pdf-summarize-e2e.test.ts` Phase 4.2 flipped: `read_failed` asserts gated lead present, unreadable lead absent, no `"workspace boundary"` substring leak (the user-facing-leak guard MUST hold on the gated path too — re-verify it does).
- [ ] `read-tool-pdf-capability.test.ts` adds a per-class describe block walking `SOFT_CLASSES` and `HARD_CLASSES` exhaustively (or a new `pdf-extract-error-routing.test.ts` if extraction is preferred).
- [ ] `bun run typecheck` + project test runner: 0 failures, 0 new errors. Existing baseline (3696 passed pre-#3384) holds modulo the flipped/added tests.
- [ ] No changes to `agent-runner.ts` (legacy leader path) — confirmed by `git diff --stat apps/web-platform/server/agent-runner.ts` returning empty.
- [ ] No changes to `buildPdfGatedDirective` or `buildPdfUnreadableDirective` factory bodies (lock-step parity invariant per Insight 4 of the cascade-structural-fix learning). `buildPdfGatedDirective`'s named-binary exclusion list MUST be byte-identical pre/post.
- [ ] No changes to `PDF_GATED_DIRECTIVE_LEAD` or `PDF_UNREADABLE_DIRECTIVE_LEAD` string constants.
- [ ] **`unreadableCopyForClass` switch at `soleur-go-runner.ts:185` remains exhaustive over all 7 `PdfExtractErrorClass` members.** Do NOT prune the soft-class branches (`oversized_buffer`, `corrupted`, `parse_error`, `lazy_import_failed`, `read_failed`) just because the new partition routes them away from `buildPdfUnreadableDirective` at the call site. The exhaustiveness rail (`: never`) and the per-class copy are defense-in-depth: if a future caller (e.g., a new code path that bypasses the routing predicate) lands a soft class on `buildPdfUnreadableDirective` directly, the user-facing copy still renders correctly. Verify by `git diff apps/web-platform/server/soleur-go-runner.ts` — `unreadableCopyForClass` body MUST be byte-identical pre/post except for any comment updates.
- [ ] PR body uses `Closes #<issue>` if a tracking issue is filed for this regression class; otherwise `Ref #3384` to backlink the originating PR.
- [ ] CPO sign-off recorded (per `requires_cpo_signoff: true`). `user-impact-reviewer` invoked at review time — finding either resolved inline or scoped-out with rationale.
- [ ] Multi-agent review pass per `rf-never-skip-qa-review-before-merging`. Specific reviewers to invoke: `architecture-strategist` (partition design), `agent-native-reviewer` (does the partition match the agent's capability surface?), `user-impact-reviewer` (single-user-incident threshold), `code-simplicity-reviewer` (typed sets vs inline literal — minimum-diff bar).

### Post-merge (operator)

- [ ] Manual reproduction on the two user PDFs (`Manning Book - Effective Platform Engineering.pdf`, `Au Chat Potan - Presentation Projet-10.pdf`) — verify Concierge no longer refuses upfront and Read fires + succeeds. Capture screenshots in the PR thread.
- [ ] 7-day Sentry sweep on `op:extractPdfText` breadcrumbs to confirm the soft-class hit rate aligns with the partition assumption (informational; not a merge gate).

## Test Strategy

Test runner: project default (`vitest run` per `package.json scripts.test`). Three test families:

1. **Unit / routing predicate** — `pdf-unreadable-directive.test.ts` + the new per-class case coverage in `read-tool-pdf-capability.test.ts`. Direct calls to `buildSoleurGoSystemPrompt` with each `PdfExtractErrorClass` value. No SDK / no LLM in the assertion path (per `cq-llm-sdk-security-tests-need-deterministic-invocation` — the routing decision is a deterministic prompt-shape property, not a model behavior).
2. **End-to-end / resolver→runner** — `cc-concierge-pdf-summarize-e2e.test.ts` Phase 4.2 flipped. Real tmp filesystem, real resolver, mocked extractor (per existing setup) — the resolver returns a `documentExtractError`, the runner picks the route. Asserts the user-facing-leak guard holds on the new route too.
3. **Type-level** — `tsc --noEmit` exercises the `_AssertPartitionTotal` rail. A future addition to `PdfExtractErrorClass` without a corresponding entry in either set fails the build before any test runs.

No new test framework. No new dependencies. No new fixtures (the existing tmp-filesystem fixture in the e2e test covers the routing surface).

## Domain Review

**Domains relevant:** Product (Concierge primary feature regression), Engineering (typed-partition refactor), CTO (architectural — extends partition design from the cascade-structural-fix learning).

### Engineering

**Status:** reviewed (carried forward from prior PR #3384 multi-agent review consensus).
**Assessment:** The partition is a minimum-diff surgical correction inside one `if` branch. No new modules, no new dependencies, no migration. Risk surface bounded to the routing predicate; factory bodies and lead constants frozen. Type-level rail catches future `PdfExtractErrorClass` widening at compile time.

### CTO (architectural)

**Status:** reviewed (advisory carry-forward).
**Assessment:** Extends Insight 1 of the cascade-structural-fix learning ("structural reframing — what infrastructure layer can make the wrong path *unreachable*"). The partition is a routing-layer recognition that `PdfExtractErrorClass` carries a sub-distinction the original directive did not respect: pdfjs-dist-side limitations vs Anthropic-API-side capability. The fix is structural in shape (typed set + compile-time rail) even though the diff is small. No new architectural surface — refines an existing one.

### Product/UX Gate

**Tier:** advisory (modifies prompt-shape only, no new UI; auto-accepted in pipeline mode).
**Decision:** auto-accepted (pipeline).
**Agents invoked:** none (no UI surface changed; copy on the unreadable path for `encrypted`/`empty_text` is unchanged from #3384).
**Skipped specialists:** none (no copywriter recommendation in scope).
**Pencil available:** N/A (no wireframes).

#### Findings

The user-facing copy partition is the load-bearing UX outcome:
- Soft-failure PDFs: the agent attempts Read silently. On Read success, the user sees a normal summary — the failure is invisible. On Read failure (e.g., Anthropic Files API also rejects), the agent falls through to whatever its baseline error handling produces, which is governed by the `READ_TOOL_PDF_CAPABILITY_DIRECTIVE` baseline + the model's tool-execution error semantics. This is not a regression vs. pre-#3384 behavior on the soft path — pre-#3384, the agent attempted Read too (on the gated route).
- Hard-failure PDFs (encrypted / empty_text): user sees the existing #3384 unreadable copy, including the paste/paperclip hint. No change.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Filled above with the single-user-incident threshold and concrete artifact/vector lines.
- The compile-time `_AssertPartitionTotal` rail uses `infer T` from `ReadonlySet<...>`. If the `Set` is constructed without an explicit `ReadonlySet<PdfExtractErrorClass>` annotation, TypeScript widens the element type to `string` and the rail collapses. Pin the annotation on both sets and verify by adding a temporary garbage member — `_AssertPartitionTotal` should fail to compile.
- `sanitizePromptString` ordering matters. Set-membership check MUST happen on the sanitized value, not the raw arg, so a poisoned upstream that smuggles U+2028 mid-class-name does not match a Set entry and the value falls through to the unreadable path (safe-by-construction). Pin via a unit test that asserts `isPdfSoftFailure("oversized_buffer ")` returns `false`.
- `buildPdfGatedDirective` and `buildPdfUnreadableDirective` are imported by both `soleur-go-runner.ts` (Concierge) and `agent-runner.ts` (legacy leader). The legacy leader does NOT branch on `documentExtractError` — agent-runner's PDF path always emits the gated directive. This plan does not touch agent-runner. If a future change extends extract-error routing to the leader path, re-export `isPdfSoftFailure` and call it there too — and grow the lock-step parity tests to walk both builders.
- The cascade defense is preserved by **two** layers: (a) the named-binary exclusion list in `buildPdfGatedDirective` itself (line 126–127), (b) `disallowedTools: [Bash, Edit, Write]` in `cc-dispatcher.realSdkQueryFactory`. Routing soft failures to the gated path does NOT remove either layer — confirm by reading the diff and checking that neither file is touched outside the routing predicate.
- The user-facing-leak guard ("workspace boundary" / "outside the workspace" never appears in the system prompt — Bug A2 of #3376) holds on BOTH directives. Verify by re-running the e2e test's `expect(systemPrompt.toLowerCase()).not.toContain("workspace boundary")` on the flipped route. If a future PR introduces sandbox-internal copy into `buildPdfGatedDirective`, this guard catches it.
- `read-tool-pdf-capability.test.ts` Scenario 8 ("BASELINE constant does not contain gated exclusion-list binaries") asserts the cascade list is scoped to the gated branch only. The new per-class describe block does NOT change which branch the cascade list lives in — only which extract-error classes route TO the gated branch. Scenario 8 stays green.
- Per learning `2026-05-06-cap-coupling-between-adjacent-prs.md`: when changing one branch of a routing predicate, grep ALL readers of `PdfExtractErrorClass` (not just the routing call site) to confirm no sibling reader assumes the prior partition. Verified pre-plan: only `unreadableCopyForClass` (the per-class copy switch) and `kb-document-resolver.ts` (producer) read the union. The copy switch is intentionally exhaustive — it stays exhaustive (still covers all 7 classes) even though only 2 classes will actually reach `buildPdfUnreadableDirective` after this change. Defense-in-depth: if a future caller routes a soft class through the unreadable directive bypassing this partition, the copy still renders. Do NOT prune the soft-class branches from `unreadableCopyForClass` — they are the safety net.

## Resume Prompt

```text
Resume prompt (copy-paste after /clear):
/soleur:work knowledge-base/project/plans/2026-05-07-fix-pdf-concierge-soft-failure-route-plan.md. Branch: feat-one-shot-pdf-concierge-soft-failure-route. Worktree: .worktrees/feat-one-shot-pdf-concierge-soft-failure-route/. Issue: TBD (file at work-skill time, link to PR #3384 as Ref). PR: TBD. Plan reviewed, implementation next.
```
