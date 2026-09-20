---
title: "fix(compound-promote): split diff-underivable by emit site and carry detail into the outcome marker"
date: 2026-09-20
slug: fix-compound-promote-diff-underivable-enum-split
branch: feat-one-shot-8427-diff-underivable-enum-split
issue: 8427
closes: 8427
type: fix
lane: cross-domain
priority: P2
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
---

## Enhancement Summary

**Deepened on:** 2026-09-20. **Reviewers:** DHH, Kieran, code-simplicity, CTO
(devex), security-sentinel, observability-coverage-reviewer, test-design-reviewer,
CLO (legal), learnings-researcher, functional-discovery, plus a full pass of the
plan-sharp-edges catalogue and a verify-the-negative grep sweep.

### What the deepen pass changed, and why it mattered

1. **Two acceptance criteria contradicted each other.** `:240`'s fixture is the
   **empty string**, not an unparsable diff — its `it(` title misleads. The draft
   updated it to `underivable-apply` while another AC required `""` to return
   `empty`. Worse, it is the *vacuity* row, so re-basing it silently removed the only
   exerciser of `underivable-empty-pathset`. AC5a now replaces that coverage with a
   **measured** fixture.
2. **The minimisation was defeated one function upstream — twice.** `safeDetail`
   truncates at 200 *before* the sink redacts, and `spawnGitCapture` already cuts
   stderr at ~4096 non-deterministically. A credential straddling either cut is
   halved and no pattern matches it.
3. **Two sibling sinks read `detail` bare**, and the ctx-logger one lands in the same
   Better Stack source as the marker — so widening the verdict's detail would have
   shipped an unredacted 64 KB-capable attacker string to the sink this plan exists
   to protect. The draft claimed those copies stayed "byte-identical".
4. **The row would have been silently dropped.** Vector slices at 10,000 characters;
   the widened worst-case row is ~9,046 before JSON escaping, and a sliced row
   decodes as a string that the runbook's own `select(type == "object")` guard drops
   — the exact #8281 blind spot this telemetry exists to close.
5. **The discoverability probe could not fail meaningfully.** Check 10's matcher is
   `tokens.some(...)`, so a six-token expectation PASSes on one surviving token; and
   the inline regex was single-line-only in a repo with **no formatter config**.
   Replaced by a committed script printing one token.
6. **The guard census was rewritten from regex to AST.** Every failure mode of the
   regex form is real in this file — line-oriented strippers that miss trailing and
   single-line comments, 100+ character returns that may wrap, and an ordinary
   `refuse()` hoist that would redden it with the property intact.
7. **An arm declared untestable is testable.** A PATH shim in front of bare
   `spawn("git", …)` reaches both `underivable-unparsable-record` sites with no mock
   and no signature change.
8. **The risk was framed backwards.** At two arms `detail` is a model-*chosen*
   string, so the exposure is a 200-character controlled **write** channel into a
   processor with no executed Art. 28(3) instrument — not incidental disclosure.
   D4.3 now classifies rather than relays.

### New considerations discovered

- Vector transport is **Source 3** (`app_container_journald`, pino `level >= 40`),
  not the Inngest-host source the draft cited.
- The emitter spreads `...outcome` **after** the discriminator every reader
  field-isolates on.
- `redactGithubSourcedText(undefined)` returns `""`, which would stamp "git said
  nothing" onto every non-diff refusal.
- `API_KEY_RE` is `\b`-anchored, so a naive straddle fixture fails against a
  *correct* implementation.
- The runbook's jq recipe ends in `@tsv`, which errors on a non-scalar — so
  "project `refusal_detail`" cannot be left to the implementer.

### Verified, not asserted

All 10 cited AGENTS rule IDs are active (none fabricated, none retired); all cited
ADRs exist; #7529, #7825, #8293 and #8427 were re-read live and are OPEN; 11 of 12
negative claims confirmed by grep, with the twelfth (`emitOutcomeMarker` call-site
count) corrected from six to seven.

## Overview

The weekly `cron-compound-promote` Inngest cron refuses a proposed diff through
`checkDiffPaths`, and six distinct refusal sites inside that function all report
the same `underivable` string. The refusal's `detail` — git's own diagnosis — is
computed at the call site and handed to the Inngest ctx logger and to Sentry, but
the structured `SOLEUR_COMPOUND_PROMOTE_OUTCOME` marker records only
`cluster_hash` and `reason`. A reader of the marker therefore cannot tell which
gate moved, and the one string that would say is not in the marker at all.

Measured, 2026-09-20T05:39:18Z, Inngest run `01M2YN6XP9WKTBWR653SXNCV9V`: the run
reached `status: completed`, read a 2,248-file / 1,214,087-byte corpus, proposed
two clusters, and refused both with `diff-underivable`. Recovering *why* required
joining the marker to a second sink. The detail, once recovered, read
`error: No valid patches in input (allow with "--allow-empty")` for both — the
`git apply --cached` arm. Measured against git 2.55.0, that one string is emitted
byte-identically for an empty string, a whitespace-only string, a markdown-fenced
diff block, and a `---`/`+++` header pair with no `@@` hunk. So even the recovered
detail leaves a four-way ambiguity.

This plan makes the refusal reason name its emit site, carries the bounded and
redacted `detail` into the marker's `refusal_detail[]`, records the observable
*shape* of the proposed diff (a length and three cheap booleans — never its body),
and gives an empty or whitespace-only diff a refusal reason of its own.

**How the four-way ambiguity is actually split, after the change.** Two of the four
cases stop reaching the apply arm at all: the new `empty` predicate intercepts the
empty and whitespace-only inputs before git runs, and they are reported as
`diff-empty`, with `len` separating the two. The residual ambiguity at
`diff-underivable-apply` is therefore **three**-way — fenced markdown, a header
pair with no hunk, and arbitrary prose — and `fenced` plus `headerPair` decide it.
The plan says this explicitly because an earlier draft claimed all four fields
resolved a four-way ambiguity at one arm, which the `empty` predicate had already
made false.

The `empty` arm earns its place on its own terms, not as telemetry: a no-op
proposal is a different upstream event from a malformed one, and classifying a
zero-byte string should not cost a `mkdtemp` plus three `git` subprocesses.

*Lane note:* no `spec.md` exists for this branch, so `lane:` defaulted to
`cross-domain` (TR2 fail-closed).

## Research Reconciliation — Spec vs. Codebase

| Claim in the work target | Reality on `main` @ `18887f8d5` | Plan response |
|---|---|---|
| Union declared at `:272`; six `underivable` returns at `:332/:338/:347/:363/:370/:375` | Confirmed. `DiffPathVerdict` declares `"structural-op" \| "underivable" \| "path-refused"`; the six returns are where stated. `:370` and `:375` share the literal `"unparsable diff-index record"`, so six sites collapse to five distinct causes. | Split into five values; two sites share `underivable-unparsable-record`. |
| Marker construction "around `:1271` / `:1304`" drops `detail` | Partly. `:1271`/`:1304` are the `refusal_detail:` arguments to the two `emitOutcomeMarker` calls; the field is actually dropped one level earlier, at the single `refusalDetail.push({ cluster_hash, reason })` accumulator in the handler body. | Edit the accumulator and widen `ClusterOutcome`; the two `emitOutcomeMarker` argument lines need no change. |
| `scripts/followthroughs/compound-promote-outcome-8281.sh` consumes the outcome marker and a downstream gate reads `reason` | **Stale in part.** The follow-through script decodes only `.trigger` and `.status` (`grep -n "reason\|refusal\|underivable"` over it returns zero lines). No production code, workflow, or gate anywhere in the repo reads a refusal `reason` value. The only consumers of the literals are the vitest rows and the runbook prose. | Prefix-stable naming chosen anyway (below); the follow-through script needs no edit. Recorded so a reviewer does not re-derive it. |
| The betterstack runbook consumes the marker | Confirmed, and it is the **load-bearing** consumer: it enumerates the exact refusal literals and asserts two things this change makes false — that `refusal_detail[]` is "enum-only — never a path or learning text", and that "Per-refusal git detail is NOT in Better Stack." | Update in the same PR. Both claims are rewritten, not merely extended. |
| `:989` bounds the diff from above only, so an empty proposal sails through | Confirmed, and the upstream schema does not close it either: `proposed_diff_unified: { type: "string" }` carries no `minLength`, and the file's own comment records that the API rejects numeric constraints. | Add the lower bound (placement decided in D2). |
| Existing coverage at `cron-compound-promote-allowlist.test.ts:140` asserts this reason | Confirmed, and there is a **second** one at `:240` the target did not name — but the two are **not** the same case. `:140` is `checkDiffPaths("not a diff at all\n")`, which reaches the apply arm. `:240` is `checkDiffPaths("", repoRoot)` — the empty string — and it is labelled `row 9 (dispatch)`, the **vacuity** row whose comment reads "an empty derived set must never read as 'no forbidden paths'". It buys that property only by driving `""` all the way through apply → diff-index → `fields.length === 0`. | `:140` becomes `underivable-apply`. `:240` is re-based to `empty` (the new predicate intercepts it at function entry), **and** a replacement exerciser is added for `underivable-empty-pathset` — otherwise that arm ships with zero coverage. See AC5a. |
| — (not in the work target) | `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-marker.test.ts` contains **zero** references to `refusal_detail` or `REFUSAL_DETAIL_CAP`. The new field would ship untested at the emitter. | New emitter-level rows, including a redaction row mirroring the existing `error_message` scrub row. |
| — (not in the work target) | `cron-compound-promote-outcome-census.test.ts` pins `'return { kind: "refused", reason: "diff-size-exceeded" };'` byte-for-byte as a mutation anchor, and `applyStepWindow()` requires the string `async (): Promise<ClusterOutcome> => {` to occur **exactly once**. | Neither may be reformatted. Recorded as a hard implementation constraint. |
| — (not in the work target) | `cron-compound-promote-allowlist.test.ts` pins the call-site text `"await checkDiffPaths(cluster.proposed_diff_unified"` and `/if \(!pathVerdict\.ok\)/` as source-text assertions. | The call site must not be reformatted. Recorded. |

## Research Insights

### Premise Validation (Phase 0.6)

`gh issue view 8427` returns `state: OPEN` with an empty
`closedByPullRequestsReferences` — the premise is live. Every file and symbol the
work target cites exists on `main` at `18887f8d5` and was read, not assumed. One
cited premise was measured **stale**: the follow-through script named as a
consumer of the enum reads only `.trigger` and `.status`, and the repo-wide grep
for a gate reading a refusal `reason` returns nothing outside tests and the
runbook. One premise was measured **understated**: the runbook does not merely
*mention* the enum, it makes two positive claims about `refusal_detail[]` that
this change falsifies.

The consumer claim in D1 is a universal negative, so the commands that produced
it are recorded here rather than asserted — re-run them to falsify it:

```bash
grep -rn 'diff-underivable' . | grep -v '^./.git/' | grep -v '^./.worktrees/'
grep -rn '\.reason === "' apps/web-platform/
grep -rn '?\.reason === "' apps/web-platform/
grep -rn '_exhaustive: never' apps/web-platform/server apps/web-platform/src
grep -rn 'verdict.reason\|pathVerdict.reason\|DiffPathVerdict' apps/web-platform/
grep -rln 'COMPOUND_PROMOTE_OUTCOME' .github/ scripts/ plugins/ apps/
grep -n 'reason\|refusal\|underivable' scripts/followthroughs/compound-promote-outcome-8281.sh
```

Measured results: `diff-underivable` appears only in
`knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`; the
optional-chained pattern returns zero; no `_exhaustive: never` rail covers
`DiffPathVerdict`; `verdict.reason` assertions live only in
`cron-compound-promote-allowlist.test.ts` (`:140, :157, :172, :185, :208, :218,
:232, :240, :263, :286`); `COMPOUND_PROMOTE_OUTCOME` appears in five files, of
which the follow-through script and its test read only `.trigger`/`.status` and
`plugins/soleur/test/preflight-discoverability-test.test.ts` mentions it only in
a comment justifying a credentials-waiver counter; and the last command returns
zero lines. A future consumer added outside this list is exactly what D1's
prefix stability protects.

ADR corpus grep for the proposed mechanism (`ls knowledge-base/engineering/architecture/decisions/ | grep -iE "log|redact|marker|observab|telemetry"`)
surfaces ADR-108 (marker form), ADR-095 (fail-closed redaction engine contract),
ADR-197 (a zero from a log surface is not evidence of absence) and
ADR-211 (redaction at the producer *and* the sink). None rejects per-site refusal
granularity or bounded detail in a marker; ADR-211's producer-and-sink posture is
the one this plan follows (`safeDetail` at the producer, `redactGithubSourcedText`
at the sink).

### Property List (Phase 0.6b)

- **P1.** A reader of one `SOLEUR_COMPOUND_PROMOTE_OUTCOME` row can tell which of
  the six refusal sites in `checkDiffPaths` fired.
- **P2.** That reader gets git's own diagnosis for the refusal from that same row,
  without joining to a second sink.
- **P3.** For an apply-arm refusal, that reader can distinguish a fenced markdown
  block, a `---`/`+++` pair with no `@@` hunk, and neither. (Stated three-way, not
  four-way: P4's predicate intercepts the empty and whitespace-only inputs before
  `git apply` runs, so they are `diff-empty` rows and never reach this arm. The
  shape fields are emitted on `diff-empty` rows too, which is how a real no-op is
  told apart from an over-eager predicate.)
- **P4.** A proposal whose diff is empty or whitespace-only is reported as a
  no-op, not as a path-derivation failure.

### Cut List (Phase 0.6b)

| Mechanism considered | Property it would buy | Why cut |
|---|---|---|
| A `const _exhaustive: never` rail over the split union | "a future value cannot be silently dropped" | The three-pattern consumer grep (`_exhaustive: never`, `.reason === "`, `?.reason === "`) returns **zero** production consumers of `DiffPathVerdict["reason"]` — the only readers are the vitest rows. A rail would quantify over an empty set. |
| A dedicated top-level marker field for the diff shape | P3 | `refusal_detail[]` is already the per-cluster structure and is already capped and already emitted on both markers. A second array would need its own cap, its own ordering guarantee, and its own join key. Folded into the existing entry. |
| A second empty-diff check at the handler call site, in addition to one inside `checkDiffPaths` | P4 | `checkDiffPaths` has exactly one caller. Two chokepoints for one property is the duplication that later drifts. One site, chosen in D2. |
| A new unified-diff parser to derive shape | P3 | Measured (functional-overlap sweep): no diff-shape helper exists anywhere under `apps/web-platform/` or `plugins/`, so nothing is being duplicated — but a *parser* is not needed either. Three regex tests and a `.length` answer P3; a parser would answer questions nobody asked. |

### Value proposition (Phase 0.6c)

No cost or performance saving is claimed, so nothing is quantified here. The
measured saving is diagnostic: the 2026-09-20 run required correlating the
Better Stack marker with a Sentry event to learn which gate fired, and even then
landed on a four-way ambiguity. This change makes both answerable from one row.

### Applicable institutional learnings

- `knowledge-base/project/learnings/2026-05-29-canonical-constant-flip-must-grep-consumers-that-assert-old-value.md`
  — split the grep into emission sites and **asserting** consumers. Done: emission
  sites are the six returns; asserting consumers are `allowlist.test.ts:140,240`
  and the runbook enum list.
- `knowledge-base/project/learnings/2026-04-18-discriminated-union-widening-if-ladders-and-config-map-parity.md`
  and `knowledge-base/project/learnings/integration-issues/discriminated-union-exhaustive-switch-miss-20260410.md`
  — a widening audit that only looks at `switch` misses if-ladders and config-map
  pairs. The three-pattern grep in the Cut List is that audit; it came back empty.
- `knowledge-base/project/learnings/2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md`
  — adding an optional field leaves consumers that read the old shape untouched.
  Here the optionality is deliberate (`detail?`), and the one reader is the
  emitter's `.slice(0, REFUSAL_DETAIL_CAP)`, which is shape-agnostic.
- `knowledge-base/project/learnings/2026-06-15-id-shape-guard-test-fixture-blast-radius-and-syntactic-sast.md`
  — a new shape guard has outsized fixture blast radius. The empty-diff guard is
  scoped to one function with one caller and one test file; the blast radius was
  measured (zero other fixtures construct an empty `proposed_diff_unified`).
- `knowledge-base/project/learnings/best-practices/2026-07-03-parity-guard-unmodeled-input-must-fail-loud-not-skip.md`
  — test an early-exit guard with the target case **and** boundary variants, and
  prove the test reddens when the guard is removed. Encoded as Guard 2's matrix.
- `knowledge-base/project/learnings/2026-05-20-manifest-as-iac-with-shared-diff-script-contract.md`
  — a doc comment promising a contract survives unchanged while code drifts. The
  `refusal_detail[]` doc comment currently promises "enum ONLY — never learning
  text or paths"; this plan rewrites it *and* pins the new promise with an
  emitter test, rather than leaving prose to carry it.
- `knowledge-base/project/learnings/2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`
  — every RED fixture being a mutation of one canonical, with the canonical as the
  only must-PASS input, makes a guard satisfiable by a stub. Encoded as the
  harness rows in the Guard Contract.
- `knowledge-base/project/learnings/2026-07-20-the-fix-for-an-evidence-discarding-gate-discarded-its-evidence.md`
  — a fix for an evidence-discarding path can discard evidence itself. Watched
  for here: `safeDetail` already truncates to 200 bytes, and the new shape fields
  must be computed from the **untruncated** diff, not from a scrubbed copy.

### Repository conventions that bind this change

- `AGENTS.rules.md` `cq-union-widening-grep-three-patterns` — the three-pattern
  consumer grep. Run; result in the Cut List.
- `AGENTS.rules.md` `hr-type-widening-cross-consumer-grep` — every consumer of a
  widened producer-side type verified before merge.
- `AGENTS.rules.md` `cq-silent-fallback-must-mirror-to-sentry` — the refusal path
  already mirrors to Sentry via `reportSilentFallback`; the new arm must too.
- `AGENTS.rules.md` `cq-assert-anchor-not-bare-token` — every new source-text
  assertion anchors on a call-form a comment cannot produce.
- `AGENTS.rules.md` `cq-cite-content-anchor-not-line-number` — new code comments
  cite `<file> › <symbol>()`, never `<file>:NNN`.
- `AGENTS.rules.md` `hr-observability-as-plan-quality-gate` and
  `hr-observability-layer-citation` — the `## Observability` block below.
- `scripts/lint-guard-contract.py` is a **repo-global ratchet** (a `run_suite` row
  with no path argument), so it lints this plan's Guard Contract section on every
  full run, whether or not the diff touches it.

### Test-selection mechanics (measured, not quoted)

The single suite that owns `checkDiffPaths` is registered in the `repo-wide`
vitest project (`apps/web-platform/test/repo-wide-suites.ts`), not `unit`:

```bash
cd apps/web-platform && ./node_modules/.bin/vitest run --project repo-wide \
  test/server/inngest/cron-compound-promote-allowlist.test.ts
```

`--project` is load-bearing; without it all three projects load. Repo-global
ratchets are invisible to diff-derived suite selection, so both halves are run by
hand before committing — see Phase 5. Note for the implementer:
`plugins/soleur/skills/work/SKILL.md` states "221 rows … prefix filter returns
19". Measured in this worktree today the first number is **224**
(`grep -cE 'run_suite "[^"]+" (bash|python3|bun|npx) [^ ]+$' scripts/test-all.sh`).
The second is not reproducible as stated — every suite name is `scripts/`-prefixed,
so a literal `lint-*-live` prefix filter returns **0**, and the
`scripts/lint-…-live` reading returns **13**. Run the greps; do not carry any of
these three numbers forward as a constant.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --limit 200` returned 65
open issues; a `jq --arg path … | contains($path)` sweep over every body for each
of the seven planned paths returned zero matches. Nothing to fold in, acknowledge,
or defer.

## User-Brand Impact

**If this lands broken, the user experiences:** the weekly self-healing cron stops
promoting learnings into the rule corpus while the marker reports a confident new
reason — a stall that *looks* explained. The first-draft version of this section
named an over-eager `trim()` refusing a BOM-prefixed but well-formed patch; that is
**unreachable**, and was measured so: a byte-order mark followed by a real hunk
does not trim to the empty string, because `trim` removes U+FEFF only when the
whole string is whitespace. The reachable shape is the opposite one: `diff-empty`
becomes the dominant refusal because the *proposer* has stopped emitting diffs at
all, and the new reason makes an upstream failure read as a handled
classification. The user sees a compounding loop that has quietly stopped
compounding.

**If this leaks, the user's workflow is exposed via:** `refusal_detail[].detail` in
Better Stack Logs source 2457081. The string is git stderr produced while applying
a model-authored diff, so it is attacker-influenced text on its way to a
third-party processor with 90-day retention and no executed Art. 28(3) instrument.
The realistic exposure is a repository path — and, for a diff targeting the
learnings corpus, a filename slug that is operator-authored prose and can name an
incident or a person.

**Brand-survival threshold:** aggregate pattern

One refused cluster's bounded git stderr in a log sink is not a user incident; the
harm shape is a pattern of steadily widening what an already-noisy channel carries
into that processor. Because the threshold is `aggregate pattern`, no per-PR CPO
sign-off is added (`requires_cpo_signoff: false`), but the minimisation controls in
D4 are acceptance criteria, not advice.

## Design Decisions

### D1 — Keep the `diff-` prefix stable for the split; `diff-empty` is a reclassification.

The emitted reason is built as `` `diff-${pathVerdict.reason}` ``, so the **five split
values** keep both the `diff-` prefix and the `diff-underivable` prefix
(`diff-underivable-apply`, `diff-underivable-read-tree`, …). A consumer doing a
prefix or substring match on either string keeps matching those five.

**`diff-empty` deliberately does not carry the `diff-underivable` prefix, and that
is a behaviour change, not a compatibility guarantee.** Today an empty or
whitespace-only proposal emits `diff-underivable`; after this change it emits
`diff-empty`. A saved Better Stack query filtering on `diff-underivable` therefore
stops matching precisely the rows whose classification this PR changes — which is
the intent, since they were never derivation failures. Calling that
"prefix-stable" would be a compatibility claim dressed over a reclassification.
The runbook edit must state it in the same PR, and the PR body must not describe
the split as wholly backward-compatible.

This was chosen over renaming wholesale, and the choice is cheap because the
consumer sweep came back nearly empty:
`scripts/followthroughs/compound-promote-outcome-8281.sh` decodes only `.trigger`
and `.status`; no workflow, script, or production module anywhere in the repo reads
a refusal `reason` value. The only literal consumers are two vitest rows and the
runbook prose, and both are edited in this PR.

**The PR body must state this choice explicitly**, per the work target.

### D2 — The empty-diff refusal lives INSIDE `checkDiffPaths`, not at the call site.

The work target proposed placing it at the handler, beside the existing
`length > MAX_DIFF_BYTES` check, for symmetry of bounds. Placing it inside
`checkDiffPaths` is chosen instead, for three measured reasons:

1. **Testability.** `checkDiffPaths` is exported and directly driven by the
   allowlist suite with real fixtures. The handler body is reachable only by
   source-text assertions — that file already greps the handler for the refused
   return form precisely because the behaviour is otherwise unobservable. A guard
   placed there could only be *asserted about*, not *exercised*.
2. **One chokepoint.** `checkDiffPaths` has exactly one caller; the property "an
   empty diff never reaches path derivation" is a property of the derivation's
   entry, and putting it there makes the guard true for any future caller.
3. **Anchor safety.** The outcome-census suite pins the exact text
   `'return { kind: "refused", reason: "diff-size-exceeded" };'` as a mutation
   anchor. Adding a sibling refusal immediately beside it invites reformatting it.

The emitted reason is still `diff-empty`, because the call site's
`` `diff-${pathVerdict.reason}` `` template does the prefixing.

### D3 — Diff shape travels in the memoized `ClusterOutcome`, not a handler-scope array.

The outcome-census suite's Guard 3 exists because an earlier revision pushed into a
handler-scope array from inside the memoized step callback and emitted
`refusals: []` on every real run. The shape fields must therefore be computed
**inside** the step callback and returned on the `ClusterOutcome`, with the
`refusalDetail.push(...)` staying **outside** it, exactly as `reason` does today.

Two source-text constraints follow and are non-negotiable:

- `applyStepWindow()` requires the literal step-callback signature
  (`async (): Promise<ClusterOutcome> => {`) to occur **exactly once**. Widening
  `ClusterOutcome` with optional fields leaves that text byte-identical; changing
  how the callback's signature renders would make it throw.
- The allowlist suite pins the `await checkDiffPaths(cluster.proposed_diff_unified`
  call text and the `if (!pathVerdict.ok)` guard text. The call site must not be
  reformatted.

### D4 — Minimisation at the sink: strip, redact, classify, then cap.

From the Legal advisory and the security review (Domain Review below). The rules are
enforced in `emitOutcomeMarker()` — the sink — per ADR-211's producer-and-sink
posture. An earlier draft of this section was wrong in three measured ways; each
correction is recorded inline so the reasoning is auditable rather than merely
replaced.

**D4.0 — The two sibling sinks must be fixed in the same PR.** The refusal branch
already hands `pathVerdict.detail` to two other destinations, both **bare**:

```ts
logger.warn({ fn: "cron-compound-promote", hash: clusterHash, reason, detail: pathVerdict.detail }, "diff-path-refused");
reportSilentFallback(new Error(`diff refused: ${pathVerdict.reason}`), {
  ..., extra: { cluster_hash: clusterHash, reason, detail: pathVerdict.detail },
});
```

Neither wraps the value. Today that is harmless because `verdict.detail` *is* the
200-character capped form. The moment D4.1 widens `verdict.detail`, both copies
widen with it — and the `logger` here is the Inngest ctx `ProxyLogger`, which goes
to journald → Vector → **Better Stack source 2457081**, the same sink the marker
uses. An earlier draft claimed the split "keeps the Sentry and ctx-logger copies
byte-identical to today". That was false, and it would have shipped an unredacted,
unclassified, 64 KB-capable attacker-influenced string to the exact sink this
section exists to protect.

So: **drop `detail` from the ctx-logger line entirely** — the marker now carries it,
which is the whole point of this PR — and pass `safeDetail(pathVerdict.detail)` to
the Sentry `extra`. Both call sites are in `## Files to Edit`, and a guard row
asserts the bare form `detail: pathVerdict.detail` occurs zero times in the handler.

**D4.1 — `detail` passes through `redactGithubSourcedText`**, exactly as
`error_message` already does. For that to mean anything, nothing upstream may cut
the string mid-credential:

- `safeDetail` is `stripControl(s).slice(0, 200)` today in effect — a control-char
  strip **and** a 200-character truncation — and it runs *before* the sink's
  redaction. A token straddling character 200 is halved upstream and no pattern
  matches the fragment.
- The binding cut is in fact **further upstream still**: `spawnGitCapture` already
  accumulates stderr under `if (stderr.length < 4096) stderr += chunk;`. That both
  truncates at ~4096 *and* does so non-deterministically — the guard tests the
  length *before* appending, so the final string overshoots by up to one chunk. A
  first draft of this plan proposed adding a second 4096 bound in `stripControl` and
  justified it as "far above any credential shape, so nothing relevant can straddle
  it". Both halves were wrong: the cut already existed, and
  `redaction-allowlist.ts` carries several unbounded runs (`JWT_RE`'s three `{10,}`
  segments, `AUTHORIZATION_HEADER_RE`'s `\S+`, `ENV_CRED_ASSIGN_RE`'s `[^\s'"]+`,
  `github_pat_…{59,}`) that a claims-heavy token exceeds.

  The fix is to make `redactGithubSourcedText`'s own `MAX_INPUT_LEN` (64,000, which
  appends an explicit `[…]` marker and is designed to be the truncation point) the
  **only** cut before redaction: raise `spawnGitCapture`'s stderr bound to `64_000`
  and make it deterministic — `stderr = (stderr + chunk).slice(0, 64_000)` — so a
  straddle row can actually pin it. `spawnGitCapture` is module-local, so the blast
  radius is this file.

  `stripControl(s)` therefore strips control characters and does **not** truncate;
  `safeDetail = (s) => stripControl(s).slice(0, 200)` is kept for the Sentry copy.
  `DiffPathVerdict["detail"]` carries the `stripControl` form.

- **The strip class must include C1.** Today it is
  `/[\u0000-\u001f\u007f\u2028\u2029]/g`, which omits U+0080–U+009F. U+0085 (NEL) is
  a line terminator for Python's `str.splitlines()`, for Java, and for Unicode-aware
  `(?m)` engines — exactly the derived-pipeline and log-viewer readers U+2028/U+2029
  were added for — and `JSON.stringify` escapes only C0, so it reaches the NDJSON row
  raw. No legitimate git stderr contains C1, so widening is free:
  `/[\u0000-\u001f\u007f-\u009f\u2028\u2029]/g`, written with escape sequences only
  per `cq-regex-unicode-separators-escape-only`.

**D4.2 — The 200-character cap is applied last, after redaction and classification.**
`redactGithubSourcedText` substitutes `[redacted-…]` markers longer than some shapes
they replace, so a cap applied first can be exceeded by the time the row is written.
*Characters, not bytes* — the slice counts UTF-16 code units, so a "200-byte"
assertion over it is untrue for any non-ASCII detail. The cap must also be
**surrogate-safe**: `.slice(0, 200)` can leave a lone high surrogate, so use
`Array.from(s).slice(0, 200).join("")` or trim a trailing unpaired surrogate. Note
the producer/sink asymmetry this creates — `error_message` is capped at the producer
while `detail` is capped at the sink; AC15 requires the doc comment to say so.

**D4.3 — Classify the path, do not pass it through.** This supersedes the earlier
"elide the learnings slug" rule, which two reviewers correctly attacked as firing
only on its own stated exception, and which the security review then showed was
aimed at the wrong risk entirely.

The risk is not incidental disclosure of repository content. At two arms `detail` is
not git's diagnosis at all but a **verbatim model-chosen string**: `checkDiffPaths`
returns `detail: safeDetail(bad)` at the `path-refused` arm and
`` safeDetail(`${status} ${path}`) `` at the `structural-op` arms, where the path is
whatever the model wrote into its diff. A prompt-injected proposer therefore gets a
200-character **controlled write channel** into a third-party processor with no
executed Art. 28(3) instrument, weekly, on every refused cluster. That is a write
channel, not a leak, and eliding one directory's slugs does nothing to it.

So the transform classifies rather than relays. For any path-shaped token in
`detail`: match it against `TARGET_ALLOW_RE` and a short fixed prefix set
(`AGENTS.rules.md`, `plugins/soleur/skills/*/SKILL.md`,
`knowledge-base/project/learnings/`, `.github/workflows/`), emit
`<matched-prefix>/[elided]`, and fall back to the literal `[unclassified-path]` when
nothing matches. That collapses the channel from 200 free characters to a few bits,
preserves the diagnostic the marker actually owes — *which corpus was targeted* —
and lands the basename-or-first-segment form the Legal advisory asked for, which an
earlier draft recorded as a declined divergence. The full untruncated path remains
in the Sentry copy via `safeDetail`.

Two implementation constraints on the replacement itself:

- Use a **function replacement** (`s.replace(RE, () => "…")`), never a string one.
  A string replacement containing `$&`, `` $` `` or `$'` makes attacker input live;
  a function replacement makes those sequences inert by construction.
- Non-path stderr (`error: corrupt patch at line 3`) passes through unchanged. The
  classification applies to path-shaped tokens, not to the whole string.

**D4.4 — The emitter must rebuild entries, not spread them.** `emitOutcomeMarker`
currently places `SOLEUR_COMPOUND_PROMOTE_OUTCOME: true` and `fn:` *before*
`...outcome`, so a widened or dynamically-assembled outcome can shadow the
discriminator the marker's whole machine-readability rests on. TypeScript's
excess-property check fires only on fresh object literals and does not protect this.
Two changes, both in the same PR because this PR is what widens the shape:

- Move `SOLEUR_COMPOUND_PROMOTE_OUTCOME: true` and `fn:` to **after** the spread.
- Rebuild each `refusal_detail` entry by **destructuring the known fields**, never
  `{...entry, detail: t(entry.detail)}` — a spread relays every future field around
  the transform, and an allowlist that decides which entries pass is not an allowlist
  of what they carry.

### D5 — Shape is computed from the untruncated diff, by a small bounded helper.

The functional-overlap sweep confirmed no unified-diff shape helper exists anywhere
under `apps/web-platform/` or `plugins/`, so one is written: a pure exported
`diffShape(diff: string)` returning `{ len, fenced, headerPair, hunk }`. It is
exported so it is unit-testable without driving the cron. `len` is computed from the
**untruncated** `proposed_diff_unified` — computing it from a capped copy would be
the evidence-discarding class that
`2026-07-20-the-fix-for-an-evidence-discarding-gate-discarded-its-evidence.md`
records. It never returns any substring of the diff.

**The three predicates run on a bounded head, and their regex forms are prescribed.**
D5 places `diffShape()` at the handler's refusal branch so it can later cover
refusals that never enter `checkDiffPaths` — and the one such refusal today is
`diff-size-exceeded`, whose diff is *by construction* larger than `MAX_DIFF_BYTES`
and bounded only by the Anthropic response. So "the input is at most 16384 bytes" is
not a premise the helper may rely on. First statement:
`const head = diff.slice(0, MAX_DIFF_BYTES);` — predicates read `head`, `len` reads
`diff`. That bounds every regex unconditionally while preserving the one field that
needs the whole string.

The safe forms, with the catastrophic shapes named so they are not written:

| Field | Do not write | Why | Write |
|---|---|---|---|
| `fenced` | ``/^(\s\|\n)*```/`` | `\n` is inside `\s`, so the alternation is ambiguous under one quantifier — exponential on a long newline run with no backtick | no regex: ``head.trimStart().startsWith("```")`` |
| `headerPair` | `/^---[ \t]+.*[ \t]*$\r?\n^\+\+\+ /m` | adjacent ambiguous quantifiers, quadratic per start, restarted at every line by `m` | `/^--- .*\r?\n\+\+\+ /m` — one unambiguous `.*`, explicit newline, no `$` |
| `hunk` | `/^@@[\s\S]*@@/m` | greedy dot-all multiplied by `m` restarts | `/^@@ -\d{1,10}(?:,\d{1,10})? \+\d{1,10}(?:,\d{1,10})? @@/m` — every quantifier bounded, none nested |

**Field set: all four are kept, and the reason is scope, not conviction.** Three
reviewers independently proposed shrinking this — cut `len` and `headerPair` and keep
`fenced` + `hunk`; or collapse all four into one `kind` enum with five values. Both
are defensible and both are *better* designs on the merits. Both also drop or
restructure scope the work target named explicitly ("its length, plus cheap booleans
for a leading code fence, presence of a `--- `/`+++ ` header pair, and presence of an
`@@` hunk"), which makes them a User-Challenge rather than a mechanical
simplification: they are recorded in
`knowledge-base/project/specs/feat-one-shot-8427-diff-underivable-enum-split/decision-challenges.md`
for the operator to decide, and the plan implements the four fields as specified.
What is **not** deferred is the false claim the draft attached to them: `len` and
`hunk` do not discriminate anything at the apply arm (see the Overview), and the plan
no longer says they do.

**Placement: `diffShape()` stays a separate exported helper rather than folding into
`checkDiffPaths`.** Folding it in was proposed and is declined: shape is attached at
the handler's refusal branch so it can cover refusals that never enter
`checkDiffPaths`, and the pinned call-site text must not gain an argument.

## Files to Edit

Paths are cited with **content anchors** — an `it(` title, a fixture literal, a
symbol — rather than line numbers, because this PR itself moves every line in the
suites it edits (`cq-cite-content-anchor-not-line-number`).

| Path | Change |
|---|---|
| `apps/web-platform/server/inngest/functions/cron-compound-promote.ts` | Split `DiffPathVerdict["reason"]`; add the `empty` arm as the first check in `checkDiffPaths`; decompose `safeDetail` into `stripControl` plus the capped wrapper and return the `stripControl` form as `verdict.detail`; add and export `diffShape()`; widen `ClusterOutcome`'s refused variant; compute shape inside the step callback; carry `detail` and the four shape fields into `refusalDetail.push(...)`. Add the co-moving-artifact comment required by Phase 2 step 4. |
| `apps/web-platform/server/compound-promote-marker.ts` | Widen `refusal_detail[]`'s element type to the flat shape; rewrite its now-false doc comment, including the producer/sink cap asymmetry; add the redact → elide → cap transform inside `emitOutcomeMarker()`, applied to every entry. |
| `apps/web-platform/test/server/inngest/cron-compound-promote-allowlist.test.ts` | Update the row titled *"row 2: a diff with no `+++` header at all is REFUSED"* (fixture `"not a diff at all"`) to `underivable-apply`. **Re-base** the row titled *"row 9 (dispatch): a diff git cannot parse is REFUSED"* — its fixture is the empty string, which the new predicate intercepts, so it becomes an `empty` row and its title is amended. **Add** a replacement exerciser for `underivable-empty-pathset` (AC5a). Add the remaining per-value rows, the whitespace rows, the `diffShape()` rows, and the Guard 3 body-leak row. Leave the row asserting the refused path equals `OUTSIDE` unchanged. |
| `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-census.test.ts` | Host the Guard 1 set-equality census here, reusing `censusTerminalReturns()`'s comment-stripping and exactly-once window machinery rather than writing a parallel helper in the allowlist suite. |
| `apps/web-platform/test/server/inngest/cron-compound-promote-outcome-marker.test.ts` | Add the Guard 3 rows: `detail` redaction, cap-after-redaction with a computed straddle fixture, slug elision, the producer-truncation straddle row, per-entry totality, and the `REFUSAL_DETAIL_CAP` interaction — none of which the file asserts today. |
| `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md` | Rewrite the two now-false claims; extend the refusal-enum paragraph with the five split values and `diff-empty`, calling out that `diff-empty` does **not** carry the `diff-underivable` prefix; document the shape fields; and **amend the `SOLEUR_COMPOUND_PROMOTE_OUTCOME` jq recipe so it projects `refusal_detail`** — without that, the fields this PR adds never reach the operator's copy-paste command. |
| `knowledge-base/legal/article-30-register.md` | Amend Processing Activity 8's `(c) Categories of personal data` cell to name `refusal_detail[].detail` and the diff-shape fields. Tier 1, in-cell; no `docs/legal/**` edit, so the five legal CI gates are not engaged. |

## Files to Create

| Path | Why |
|---|---|
| `scripts/checks/compound-promote-reason-sites.sh` | The `## Observability` `discoverability_test` probe. It derives the emitted reason set from the `checkDiffPaths` window, compares it for **exact set identity** against the declared union, and prints the single token `COMPOUND_PROMOTE_REASON_SITES_OK` only on a match. It exists because Check 10's matcher is `tokens.some(...)` — any one surviving token PASSes a multi-token expectation — so a one-token output is the only expectation shape that cannot be satisfied by a partial revert. |

Nothing else. Every other deliverable extends a file that already exists —
deliberately, per the Cut List.

## Implementation Phases

### Phase 1 — Tests first (RED)

Write every row of the three mutation matrices before touching the implementation,
per `cq-write-failing-tests-before` and the Guard Contract Gate's "write the matrix
BEFORE the guard". The matrices are derived from the design in D1–D5, not from the
code as it ends up shaped.

### Phase 2 — `checkDiffPaths`: the empty arm, the split enum, the detail split

1. Widen `DiffPathVerdict["reason"]` to
   `"structural-op" | "empty" | "underivable-read-tree" | "underivable-apply" | "underivable-diff-index" | "underivable-empty-pathset" | "underivable-unparsable-record" | "path-refused"`.
2. Add the emptiness check as the **first** statement in the function body.
3. Replace each of the six `reason: "underivable"` literals with its site's value.
   The two "unparsable diff-index record" sites share
   `underivable-unparsable-record`; the census compares sets, so the repeat needs
   no special-casing.
4. Decompose `safeDetail` per D4.1 and add one comment above `DiffPathVerdict`,
   `cq-cite-content-anchor-not-line-number`-compliant, naming every artifact that
   must move together to add or remove a reason: the union, the emit site, the
   behavioural row, the census, the runbook enum paragraph, this plan's
   `failure_modes`, and the PA-8 categories cell. The Anchor paragraphs already
   enumerate them; this turns a seven-way scavenger hunt into a read.

### Phase 3 — `diffShape()` and the `ClusterOutcome` widening

1. Add and export `diffShape()`.
2. Widen `ClusterOutcome`'s refused variant with `detail?: string` and the four
   flat shape fields.
3. At the `!pathVerdict.ok` branch, return `detail` and the shape fields alongside
   the existing `reason`, **without reformatting** the pinned call-site text.
4. Extend `refusalDetail.push(...)` — which stays outside the memoized callback —
   to carry them.

### Phase 4 — The marker boundary

1. Widen the `refusal_detail[]` element type (flat).
2. Rewrite the doc comment so it states the new contract and the cap asymmetry.
3. In `emitOutcomeMarker()`, map **every** entry through redact → elide → cap, in
   that order, leaving `cluster_hash`, `reason` and the shape values untouched.

### Phase 5 — Docs, register, and the two-halves test run

1. Rewrite the runbook's two false claims, extend its enum list, and amend its jq
   recipe to project `refusal_detail`.
2. Amend PA-8 `(c)`.
3. Run the targeted suite, then **both halves of the ratchet set** — every
   `scripts/test-all.sh` `run_suite` row carrying no path argument
   (`grep -nE 'run_suite "[^"]+" (bash|python3|bun|npx) [^ ]+$' scripts/test-all.sh`,
   measured 224 rows today), **and** the suites registered by the `SUITE_GLOBS`
   array (`bash scripts/test-all.sh --print-suite-globs`, then `eval ls <glob>`),
   which have no `run_suite` line for the first grep to find.
   `scripts/lint-guard-contract.py` is in the first half and lints this plan's own
   Guard Contract section. When a ratchet fires, re-measure the others: the edit
   that satisfies one can move another. Paste both verdicts into the PR body.

## Guard Contract

### Guard 1 — Emit-site attribution of a `checkDiffPaths` refusal

**Property.** Every `ok: false` return inside `checkDiffPaths` names its own emit
site: the multiset of `reason` literals those returns carry, keyed by site, matches
the declared `DiffPathVerdict["reason"]` union exactly, and every site that git input
can drive is exercised by its own behavioural row asserting its own value.

**Assembly.** Two layers, because neither alone buys the property.

The primary layer is **behavioural**: one must-REFUSE row per site, driving the
exported `checkDiffPaths` against real git and real fixtures. Collapsing two sites
onto one literal reddens the row for the site that lost its value — something `tsc`
cannot see, since both literals remain declared members. All seven sites are
reachable; the seam for the two that real git cannot drive is given below.

The secondary layer is an **AST census**, hosted in
`cron-compound-promote-outcome-census.test.ts`. It uses the `typescript` package
already present in `apps/web-platform/node_modules`: `ts.createSourceFile(...)`, then
a walk that collects (a) the string-literal members of `DiffPathVerdict`'s `reason`
property type and (b) the `reason` property initializer of every `ok: false` object
literal returned inside the `checkDiffPaths` declaration. Both sides come from the
parse tree.

A regex census over comment-stripped text was the first design and is **rejected**,
because every one of its failure modes is a real one in this file: the reused
`censusTerminalReturns()` stripper is line-oriented
(`^\s*//` and `^\s*\*`), so it does not strip a single-line `/* … */`, a `/**`
opener, or a **trailing** `// …` after code; the file carries 97 block-comment lines
and narrates its own literals in them; the two `underivable-unparsable-record`
returns exceed 100 characters and there is **no formatter config in this repo**, so
whether they are one line or three is an implementer's choice; and hoisting the
refusals behind an ordinary `const refuse = (reason, detail) => ({ ok: false, reason, detail })`
would remove every `reason: "` literal from the window with the property fully
intact. The AST census is immune to all four by construction.

**Comparison is by site-keyed multiset, not by set.** A plain set tolerates the two
sites that share `underivable-unparsable-record` — and that tolerance is a hole:
changing *one* of them to another declared literal leaves the set unchanged and the
census green while the property is false. Keying by site position closes it, and the
two shared-literal sites additionally carry behavioural rows (below), so the mutant
is caught twice.

**The seam for the two unparsable sites.** `spawnGitCapture` copies `process.env`
minus `GIT_*` — PATH included — and calls bare `spawn("git", …)`. Prepending a shim
directory to `process.env.PATH` inside one `it()` (restored in `finally`) puts a fake
`git` in front. The shim `exec`s real git for `read-tree` and `apply` and fabricates
only the `diff-index` stdout: `printf 'notacolon\0x.txt\0'` drives the
`!meta.startsWith(":")` site and `printf ':100644 100644 aaa bbb\0x.txt\0'` drives
the five-field site. No mock, no spy on the module-local `spawnGitCapture`, no
production signature change — real git still decides everything else.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Revert **each** site's literal to a shared value — six separate mutants, run as a loop over the axis, not one row standing in for six | the behavioural row for the site that lost its value observes the other site's literal. Rows 1a–1f, because "one row, six instances" is how a surviving mutant hides |
| 2 | Add a value to the union that no site emits | the census's declared-but-unemitted direction; a one-way census is satisfied by a union that grows without emitters |
| 3 (dispatch) | Make the AST walk find zero `ok: false` returns | the census must throw, not report clean — a census finding nothing must never read as pass |
| 4 (site-keyed) | Change **one** of the two `underivable-unparsable-record` sites to another declared literal | the multiset changes even though the set does not, and the behavioural row driven by the PATH shim for that site reddens |
| 5 (precondition holds, property fails) | Rename the read-tree site's literal to `underivable-apply` | every emitted literal is still a declared member — the precondition holds — yet two structurally different causes share one reason |
| 6 (comment) | Insert the text `reason: "underivable-apply"` as (a) an asterisk-continuation line, (b) a single-line `/* … */`, and (c) a **trailing** `// …` after a statement | the census result must be unchanged for all three spellings. The third is stripped by neither line-oriented stripper in this repo, which is why this is a three-spelling loop rather than one insertion |
| 7 (refactor-tolerance) | Hoist the returns behind a local `refuse()` helper without changing any literal | the census must stay GREEN — the property is unchanged. A census that reddens here is pinning formatting, not behaviour |

**Harness rows.** (a) A SUITE edit that replaces the census's derived declared-side
read with a hard-coded array of today's values must drive a harness-integrity row
RED — the census asserts its declared side came from the union's AST node, not from a
literal in the test. (b) A must-PASS non-canonical input: the same source with one
refusal return split across three lines, literals unchanged, must still PASS. Under
the AST census this is satisfied by construction, which is the point.

**Anchor.** The union and its emit sites live in one file, so a single diff can move
both and the census would prove consistency rather than integrity. Two artifacts
outside that file must also move for a weakening to land: the refusal-enum paragraph
in `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`, and
Processing Activity 8's categories cell in `knowledge-base/legal/article-30-register.md`
— both reviewed under lenses that are not this file's. Deliberately **not** an
`EXPECTED_DIFF_REASONS` constant in the test: a hand-written member list is exactly
what harness row (a) exists to redden. The census asserts multiset identity, not a
`>= N` floor, because a floor survives any substitution that preserves the count.

### Guard 2 — An empty or whitespace-only diff is refused as a no-op

**Property.** A `proposed_diff_unified` that is empty or contains only whitespace is
refused with `reason: "empty"` (emitted `diff-empty`), decided at the entry of
`checkDiffPaths` from the string alone.

**Assembly.** The chokepoint is the entry of `checkDiffPaths`; its single caller
passes `cluster.proposed_diff_unified` through it, and the predicate sits ahead of
the binary-patch test and ahead of every `spawnGitCapture` call. Every row is a
return-value assertion on the exported function — this suite drives real git against
real fixtures and contains no mocks (verified: zero `vi.mock` / `vi.fn` / `jest.mock`
in the file), and this guard introduces none.

An earlier draft demanded an in-window observation that no git process ran and no
scratch directory was created. Dropped, for two measured reasons. The rationale was
wrong: moving the predicate below `git apply --cached` makes `""` return
`underivable-apply`, not `empty`, so the plain value row catches the reorder. And the
mechanism was unavailable: `spawnGitCapture` is module-local and non-exported, and
counting `compound-idx-` directories in the shared OS tmpdir races with concurrent
vitest workers in both directions, which would measure the machine rather than the
diff (`cq-ac-must-not-depend-on-concurrent-sessions`).

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Delete the emptiness predicate | `""` falls through to `git apply --cached` and returns `underivable-apply` — the misreport this guard exists to end |
| 2 (reorder) | Move the predicate below the `git apply --cached` call | `""` then returns `underivable-apply`; the value row for `""` reddens. The ordering property is observable from the return value alone, which is why no in-window spy is needed |
| 3 (dispatch) | Weaken the predicate to one that is never true (`diff.length < 0`) | the guard runs and decides nothing; every must-REFUSE row reddens rather than the suite reporting a clean pass over an unenforced predicate |
| 4 (second member) | Narrow the predicate from `trim()` to `=== ""` | the empty string still refuses — a compliant first member — while a tab-and-newline string does not; the second member is where a stop-at-first check fails |
| 5 (precondition holds, property fails) | Accept a two-newline string as a derivable diff | it is non-empty and under `MAX_DIFF_BYTES`, so both existing bounds are satisfied, and it must still refuse as `empty` |

**Harness rows.** (a) A SUITE edit that collapses every emptiness fixture to `""`
must drive a harness-integrity row RED: the suite asserts its own fixture set
contains at least one non-empty whitespace-only string, because row 4's mutant
survives a battery made only of `""`. (b) A must-PASS non-canonical input: a diff
with two leading blank lines followed by a real `@@` hunk must pass the predicate
**and proceed to derivation** — measured, that patch applies at rc 0 and yields a
real `diff-index` record. (An earlier draft quoted a byte-order-mark measurement
beside this row; that is a different input with a different fate — a BOM-prefixed
patch lands at `underivable-apply`, so it does not demonstrate "proceeds to
derivation". The BOM note belongs in `## User-Brand Impact`, where it now lives.)

**Anchor.** This guard compares no stored value, so there is no manifest that could
certify itself. What makes a weakening visible outside the commit is that removing
`diff-empty` also requires editing the refusal-enum paragraph in the Better Stack
runbook and the `failure_modes` entry in this plan's `## Observability` block, both
reviewed separately from the predicate.

### Guard 3 — The marker's `detail` boundary

**Property.** No text written into `refusal_detail[].detail` on an emitted marker row
is a control character (C0, C1, DEL, or a Unicode line/paragraph separator), exceeds
200 characters, matches a credential / email / phone / UUID shape, or relays a
model-chosen path verbatim — and none of those holds only for the first entry of the
array, and no failure of the transform may suppress the marker itself.

**Assembly.** The chokepoint is `emitOutcomeMarker()` in
`apps/web-platform/server/compound-promote-marker.ts` — the single function every
marker row passes through. It has seven call sites in the handler, of which exactly
two carry `refusal_detail`. The transform runs at the sink, per ADR-211's
producer-and-sink posture, and the producer is decomposed so that nothing truncates
the marker-bound copy before redaction sees it (D4.1). The property quantifies over
**every** entry, over the array as the emitter slices it to `REFUSAL_DETAIL_CAP`, and
over the emitted row's total serialized size, because Vector slices the row at 10,000
characters downstream.

**Mutation matrix.**

| # | Edit | Must go RED because |
|---|---|---|
| 1 | Drop the `redactGithubSourcedText` call on `detail` | an email or token shape injected into a fixture detail survives into the emitted row |
| 2 (order) | Apply the 200-character cap before redaction instead of after | redaction lengthens; a fixture computed to sit under the cap before and over it after must exceed the cap in the emitted row |
| 3 (dispatch) | Replace the transform with an identity passthrough that still executes | the guard runs and enforces nothing; every redaction row reddens rather than the suite reporting a clean pass over an unenforced boundary |
| 4 (second member) | Transform only `refusal_detail[0]` | a two-entry fixture whose *second* entry carries the offending shape must redden |
| 5 (classification) | Relay a model-chosen path verbatim instead of classifying it | a detail carrying an unrecognised path must emit `[unclassified-path]`, not the path — this is the controlled-write channel D4.3 closes |
| 6 (straddle) | Restore a producer-side truncation on the marker-bound copy | the fixture leaks real token characters into the row. **The fixture must place a non-word character immediately before the token**: `API_KEY_RE` is `\b`-anchored, so a token glued to preceding word characters is not redacted even untruncated, and a row built that way fails against the *correct* implementation and invites weakening the assertion. Start the token at character 180, not 195, so the mutant leaks a measured 16 characters rather than 5 |
| 7 (C1) | Narrow the strip class back to C0 plus the two separators | a detail containing U+0085 (NEL) reaches the NDJSON row raw — `JSON.stringify` escapes only C0 — and splits the row for every Unicode-aware reader |
| 8 (fail-open) | Move the entry transform inside the emitter's `try` | a throw in the transform is swallowed by the bare fail-open `catch` and suppresses the **entire** marker; a row asserting a marker is still emitted when one entry is malformed reddens |
| 9 (spread) | Rebuild entries with `{...entry, detail: t(entry.detail)}` instead of destructuring the known fields | an entry carrying an extra unmodelled key relays around the transform and appears in the emitted row |
| 10 (size) | Remove the serialized-size budget | a 20-entry worst-case fixture serializes past 10,000 characters, Vector slices it, the row decodes as a string, and every field-isolated reader drops it silently |

**Harness rows.** (a) A SUITE edit that changes the injected fixture to something
that is not actually an email (`not-an-email`) must drive a harness-integrity row
RED: the suite asserts the *unredacted* fixture does contain the shape before
asserting the emitted row does not. (b) A must-PASS non-canonical input: a plain git
stderr detail with no PII and no path (`error: corrupt patch at line 3`) must arrive
byte-identical, proving the transform is not "redact everything". (c) Row 2's
straddle fixture is **computed at test time, never hard-coded** — assert
`before.length <= 200` and `redact(before).length > 200` as their own expectations
first. Measured constructible: twelve short addresses `a0@b.co … a11@b.co` joined by
single spaces is 97 characters before and 203 after, because `[redacted-email]` is 16
characters replacing 7. Shortening that marker by three characters breaks the
precondition, which is exactly the silent disarm this row exists to catch.

**Anchor.** `REFUSAL_DETAIL_CAP`, the 200-character bound and the serialized-size
budget are stored values in the same files as the emitter. What must move outside
those files for a widening to land is Processing Activity 8's `(c) Categories of
personal data` cell in `knowledge-base/legal/article-30-register.md` — a separately
reviewed legal register — and the Better Stack runbook's description of the field. A
widening that edits the code and the test but not the register is visible as an
unamended register cell.

## Observability

```yaml
liveness_signal:
  what: >-
    One SOLEUR_COMPOUND_PROMOTE_OUTCOME WARN row per terminal exit of
    cron-compound-promote, carrying status, trigger, run_id, clusters_proposed,
    clusters_opened, refusals[], refusals_total and refusal_detail[] — whose element
    after this change is the FLAT shape
    {cluster_hash, reason, detail?, len?, fenced?, headerPair?, hunk?}. Flat, not
    nested: Better Stack field isolation and the runbook's jq recipe both project
    leaf fields, and a nested object would have to be unwrapped in every query.
  cadence: weekly, cron "0 0 * * 0", plus the cron/compound-promote.manual-trigger event
  alert_target: >-
    Sentry cron monitor SENTRY_MONITOR_SLUG (postSentryHeartbeat, liveness only) and
    Better Stack Logs source 2457081 (the work signal).
  configured_in: >-
    apps/web-platform/server/compound-promote-marker.ts (emitter, dedicated pino
    instance at WARN); apps/web-platform/infra/sentry/ (monitor, Sentry-as-IaC per
    ADR-031). Transport is Vector SOURCE 3, not source 1: this handler runs in the
    APP CONTAINER, so the row enters at [sources.app_container_journald]
    (include_matches.CONTAINER_NAME = soleur-web-platform) and passes
    [transforms.app_container_warn_filter], which filters on the parsed pino level
    >= 40 rather than on journald PRIORITY — which is what makes "the emitter must
    stay at WARN" load-bearing — then pii_scrub_* and [sinks.betterstack]. An
    earlier draft cited [sources.inngest_journald] (inngest-server.service); that is
    a different source block and an operator following it reads the wrong one.
error_reporting:
  destination: >-
    Sentry via reportSilentFallback(feature "cron-compound-promote", op
    "diff-path-refused"), correlated to the Inngest run by observability layer 1
    (server/inngest/middleware/sentry-correlation.ts, tags inngest.run_id). Phase 3
    widens that call's extra with the four shape fields so the discriminating
    evidence has TWO transports rather than one.
  fail_loud: >-
    The marker emitter is deliberately fail-open and never throws, so it is not the
    loud path. Every refusal additionally raises a Sentry event through
    reportSilentFallback, which is, and both carry the same run_id.
failure_modes:
  - mode: A cluster is refused and the marker cannot say which checkDiffPaths site fired.
    detection: >-
      refusal_detail[].reason carries the emit site, and refusals[] carries the same
      string, so the runbook's existing jq recipe surfaces it without amendment.
      In-surface: produced inside the cron worker and returned on the memoized
      ClusterOutcome, so it survives an Inngest replay. Double-covered — the same
      string reaches Sentry in the reportSilentFallback error message.
    alert_route: >-
      Observability layer 3 (Vector app_container_warn_filter, pino level >= 40) to
      Better Stack Logs source 2457081, AND layer 1 for the Sentry copy. Layer 2 does
      NOT cover the marker row — the marker uses its own pino instance, deliberately
      not server/logger.ts, so the breadcrumb mirror is not in its path.
  - mode: The apply arm fires and the remaining inputs are indistinguishable.
    detection: >-
      fenced and headerPair on the same refusal_detail entry separate the three cases
      that can still reach this arm; len separates empty from whitespace-only on
      diff-empty rows; detail discriminates the other apply failures (context
      mismatch, corrupt patch) that reach the same arm. These fields reach the
      operator through refusal_detail[], which the runbook's jq recipe does not
      project today — AC16a amends it with a pinned flatten expression.
    alert_route: >-
      Observability layer 3 (marker row) AND layer 1 (Sentry extra, widened in
      Phase 3) — two transports, because findings below show one can vanish.
  - mode: A no-op proposal is misreported as a path-derivation failure.
    detection: refusal_detail[].reason reads diff-empty rather than diff-underivable-apply.
    alert_route: Observability layer 3, same row.
  - mode: >-
      The widened row exceeds Vector's 10,000-character slice, decodes as a string
      rather than an object, and is dropped by every field-isolated reader.
    detection: >-
      apps/web-platform/infra/vector.toml [transforms.pii_scrub_string] does
      "if length(msg) > 10000 { msg = slice!(msg, 0, 10000) }". A sliced row is
      invalid JSON, Better Stack stores .message as a STRING, and the runbook's own
      select(type == "object") guard then drops it silently — the #8281 blind-spot
      class, reintroduced by this PR's own payload. Measured worst case at
      REFUSAL_DETAIL_CAP = 20 with a 64-hex cluster_hash and a 200-char detail is
      ~9,046 characters against a ~3,406 baseline, i.e. 90% of budget BEFORE JSON
      escaping of real git stderr. Detection in production: refusals_total present
      with refusal_detail absent, or the row missing entirely while the Sentry
      heartbeat fired for the same run_id.
    alert_route: Observability layer 3 joined to layer 1 on run_id.
  - mode: The new sink transform throws and the fail-open catch suppresses the ENTIRE marker.
    detection: >-
      emitOutcomeMarker wraps its whole body in try/catch with a bare fail-open
      catch. Phase 4 therefore builds the transformed array BEFORE the try, and
      degrades a single bad entry to {cluster_hash, reason} rather than losing the
      row. Production detection: the Sentry cron monitor heartbeat fired for run_id
      X but no SOLEUR_COMPOUND_PROMOTE_OUTCOME row exists for it.
    alert_route: Observability layer 1 (heartbeat) joined to layer 3 by run_id.
  - mode: The proposer stops emitting diffs and diff-empty makes the stall look handled.
    detection: >-
      clusters_opened stays 0 while refusals[] is dominated by diff-empty — a shape
      that did not previously exist, and one the runbook now names as the signature
      of an upstream proposer failure rather than of a quiet corpus. len on the same
      entries separates a truly empty proposal from a whitespace-only one.
    alert_route: >-
      Observability layer 3. Per ADR-197 a zero from a log surface is not evidence of
      absence, so the runbook's existing control — confirm SOLEUR_CLAUDE_COST rows in
      the same window before grading an absence — applies unchanged.
  - mode: >-
      A saved Better Stack query or alert filtering diff-underivable silently stops
      matching the rows this PR reclassifies to diff-empty.
    detection: >-
      D1 concedes a saved query outside the repo is invisible to any grep, so the
      repo-side sweep is a universal negative. On the first post-deploy run,
      refusals[] carries diff-empty while a diff-underivable filter returns zero;
      per ADR-197 confirm the run emitted at all by run_id before grading that zero
      as healthy.
    alert_route: Observability layer 3, source 2457081.
  - mode: The detail field carries a credential, a control character, or a model-chosen string into the sink.
    detection: >-
      Guard 3's rows at the emitter — including the straddle row for a producer-side
      truncation splitting a credential before redaction sees it, the C1 row, and the
      path-classification rows that collapse the controlled-write channel D4.3
      describes.
    alert_route: >-
      Layer 1 for the Sentry copy; layer 3 for the marker row. The control is
      preventive at the sink, so the detection is the guard suite rather than a
      production alert.
logs:
  where: >-
    journald on the Hetzner host (the app container's stdout via Docker's journald
    driver), then Better Stack Logs source 2457081 via Vector, and Sentry for the
    reportSilentFallback events.
  retention: >-
    Better Stack 90 days (Vendor / Sub-Processor Mapping in the Art. 30 register);
    Sentry 90 days; journald on the host bounded by its own SystemMaxUse /
    MaxRetentionSec rather than by either, which is a third retention and is recorded
    in the Encryption Posture block.
discoverability_test:
  command: bash scripts/checks/compound-promote-reason-sites.sh
  expected_output: "COMPOUND_PROMOTE_REASON_SITES_OK"
```

**Why the probe is a committed script and not a grep pipeline.** The first draft
declared a six-token comma-separated `expected_output` against an inline `grep`.
Measured against Check 10's own matcher — `matchExpected` in
`plugins/soleur/test/lib/discoverability-test-parser.ts`, which is
`tokens.some((tok) => normalized.includes(tok))` — **any one** surviving token makes
the probe PASS, so five of the six emit sites could be reverted and the probe would
stay green. A second defect: the inline regex matched only single-line returns, and
the two `underivable-unparsable-record` returns grow past 100 characters, so a
formatter wrapping them removes their literal from stdout with no effect on the
verdict.

`scripts/checks/compound-promote-reason-sites.sh` is committed in the same PR. It
derives the emitted set from the `checkDiffPaths` window (tolerating multi-line
returns), compares it for **exact set identity** against the declared union, and
prints the single token `COMPOUND_PROMOTE_REASON_SITES_OK` only on a match — so a
one-token matcher and an exact-identity check coincide. First token `bash` is on
Check 10's `PROBE_VERB_ALLOWLIST`; it is a small script, not a suite, and finishes
far inside the 15-second cap. No SSH, no network, no credentials — so no
`credentials_required` waiver is claimed and `BASELINE_DECLARED_PROBES` in
`plugins/soleur/test/preflight-discoverability-test.test.ts` is unchanged. A
`vitest -t`-filtered behavioural probe was considered and declined: it risks the
15-second cap, where a timeout reports identically to a down endpoint.

## Architecture Decision (ADR/C4)

No architectural decision is made and no C4 view changes. The enumeration behind
that conclusion, per the C4 completeness mandate — all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` were
read, not grepped for the feature's own noun:

- **External human actors:** none added or changed. The change has no user-facing
  surface and no new correspondent.
- **External systems / vendors:** Better Stack (`betterstack = system "Better Stack"`)
  and Sentry (`sentry = system "Sentry"`) are both already modeled, and the transport
  edge this change's payload rides — `hetzner -> betterstack "Ships journald +
  host_metrics via Vector …"` — already exists. No new vendor, no new edge.
- **Containers / data stores:** none. The change adds fields to an existing log row;
  it creates no store and touches no schema.
- **Actor ↔ surface access relationships:** unchanged. Nobody gains or loses access
  to anything; the row's reader set is the existing on-call/CLO set recorded in
  PA-8's TOMs limb.
- **Derived cardinalities embedded in edge prose:** `bash plugins/soleur/test/c4-count-parity.test.sh`
  run in this worktree — 10 passed, 0 failed. This change adds no cron monitor, no
  workflow and no heartbeat slug, so none of the counts on the `github -> sentry`
  or `github -> resend` edges move.

The legal-register amendment in `## Files to Edit` is a *record* update required by
the Legal advisory, not an architectural decision; it records an unchanged
architecture more precisely.

## Encryption Posture

This change introduces **no new persistent store and no new cross-component
connection**. The Phase 2.11 path triggers (`*.tf`, `supabase/migrations/*.sql`,
`cloud-init*.yaml`, `docker-compose*.yaml`) match none of the Files to Edit. The
gate is answered anyway, fail-closed, because the change **widens what an existing
connection carries into an existing log sink**, and the deepen-plan trigger fires on
that store-class prose. Declaring the inherited posture is the honest response;
"not applicable" would hide the one axis this change actually moves.

```yaml
at_rest:
  - store: Better Stack Logs source 2457081 (the SOLEUR_COMPOUND_PROMOTE_OUTCOME rows)
    mechanism: vendor-managed-unattested
    evidence: >-
      Better Stack s.r.o., establishment CZ, vendor EU region eu-fsn-3 (Hetzner
      Falkenstein), pinned in apps/web-platform/infra/vector.toml at the
      [sinks.betterstack] uri and verified 2026-05-22 by an authenticated POST probe
      (eu-fsn-3 -> HTTP 202, eu-nbg-2 -> HTTP 401, confirming token cluster-binding).
      The Vendor / Sub-Processor Mapping in knowledge-base/legal/article-30-register.md
      records "NOT EXECUTED — no Art. 28(3) instrument recorded" for this processor,
      so there is NO named at-rest attestation to cite. Stated as unattested rather
      than as "encrypted by default", which is the absence of a posture.
    defends_against: >-
      Nothing this change adds. The sink's confidentiality rests entirely on vendor
      access control and on the 90-day retention ceiling recorded in the register.
    does_not_defend: >-
      A vendor-side compromise, a vendor sub-processor, lawful access to the vendor,
      or an over-broad Better Stack team member. None of those is mitigated by
      anything in this PR. It also does not defend against the marker carrying more
      than it should — that is what Guard 3 exists for, and it is an access-scope
      control, not an encryption one.
    disclosed_as: >-
      Processing Activity 8 in knowledge-base/legal/article-30-register.md, whose
      (c) categories cell this PR amends to name refusal_detail[].detail and the
      diff-shape fields.
    live_verification: >-
      The authenticated POST probe above pins the ingesting region; retention and
      recipient are read from the register's Vendor / Sub-Processor Mapping. No
      at-rest cryptographic property is independently verifiable by us, which is
      precisely what "unattested" records.
in_transit:
  - connection: Vector on the Inngest host -> Better Stack Logs ingest
    tls: >-
      Yes — https, at apps/web-platform/infra/vector.toml [sinks.betterstack]
      uri = "https://s2457081.eu-fsn-3.betterstackdata.com/", with the source token
      carried as a Bearer header rather than in the URL.
    cert_verification: on
    does_not_defend: >-
      An attacker who holds BETTERSTACK_LOGS_TOKEN can read nothing (the token is
      write-only to the source) but can inject rows, which would poison exactly the
      signal this PR adds. TLS also does not defend against the payload being
      over-broad at the producer — that is D4 and Guard 3.
    disclosed_as: >-
      Processing Activity 8, recipients limb, and the #4293 Art. 44 transfer record
      that pins the ingesting host.
```

**One gap this gate surfaced, recorded rather than silently fixed.**
`cert_verification: on` is true by Vector's HTTP-sink default (`verify_certificate`
and `verify_hostname` default to true), not by an explicit pin: there is no
`[sinks.betterstack.tls]` block in `vector.toml`. A default is a weaker guarantee
than a pin — a future Vector upgrade or a config edit could flip it with no diff
that reads like a security change. Adding the explicit block is **out of scope for
this PR** (it is an infra change to a file this plan does not otherwise touch, and
mixing it in would put a `*.tf`-class edit into a telemetry fix), but it is worth a
follow-up. No `exception` block is declared, because `cert_verification` is `on` and
`mechanism` is not `plaintext-exception`.

**On the unattested at-rest posture:** it is pre-existing, it is already tracked as
`compliance/critical` at #7529 (Vendor DPA unexecuted) and #7825 (Art. 28(3)
instrument plus a written EEA location attestation), and this PR neither widens nor
closes it. Both issues were verified `OPEN` during this pass. The plan's own
minimisation controls (D4) exist because that gap is open: they are what keeps the
incremental payload proportionate while the instrument is unexecuted.

## Network-Outage Gate — determination

Phase 4.5's keyword scan matches this plan four times, and all four are false
positives, recorded here rather than skipped silently:

| Match | Where | Why it is not a network symptom |
|---|---|---|
| `unreachable` | User-Brand Impact | Describes a *code path* that cannot be reached (the BOM/`trim()` failure mode), not a host |
| `SSH` | Observability | The probe declaring "No SSH, no network, no credentials" — the gate's own desired property |
| `timeout` (×2) | Observability, Alternatives | preflight Check 10's 15-second cap, and why a `vitest`-based probe was declined |

No resource in this plan carries a `provisioner "file"`, `provisioner "remote-exec"`
or `connection { type = "ssh" }` block — the plan touches no Terraform at all — so
the resource-shape trigger does not fire either. There is no connectivity hypothesis
to deep-dive, and no `## Hypotheses` section is owed.

## Acceptance Criteria

Rows in the suites are named by their `it(` title or fixture literal, never by line
number: this PR moves every line in the files it edits
(`cq-cite-content-anchor-not-line-number`).

1. `DiffPathVerdict["reason"]` declares eight values, and the site-keyed multiset of
   `reason` literals carried by `ok: false` returns inside `checkDiffPaths` matches
   that union exactly — asserted by the Guard 1 **AST** census, with both sides read
   from the parse tree rather than from any hand-written list.
2. The six former `underivable` return sites emit five distinct values; only the two
   "unparsable diff-index record" sites share one, and because the comparison is
   site-keyed rather than set-based, changing one of those two alone reddens.
3. `checkDiffPaths("")`, a spaces-only string, a two-newline string and a
   tab-space-CRLF string each return `{ ok: false, reason: "empty" }`. (No assertion
   about processes spawned or scratch directories created: the only observable is a
   directory in the shared OS tmpdir, whose count races with concurrent vitest
   workers — `cq-ac-must-not-depend-on-concurrent-sessions`. The ordering property is
   covered by Guard 2 row 2, observable from the return value alone.)
4. A diff with two leading blank lines followed by a real `@@` hunk is not refused as
   `empty`, applies at rc 0, and yields a real `diff-index` record.
5. The row titled *"row 2: a diff with no `+++` header at all is REFUSED"* — fixture
   `"not a diff at all"` — asserts `underivable-apply`. The row titled
   *"row 9 (dispatch): a diff git cannot parse is REFUSED"* — fixture the **empty
   string** — asserts `empty`, and its title is amended. Neither row is deleted.
5a. The `underivable-empty-pathset` arm keeps a behavioural exerciser, using the
   **measured** fixture below (verified against git 2.55.0 in a repo whose
   `AGENTS.rules.md` is `"rules\nsecond line\n"`: `git apply --cached` exits 0 with
   empty stderr and `git diff-index --cached -z HEAD` emits zero bytes, because the
   two records apply sequentially to the same index entry and the net result equals
   HEAD's blob):

   ```diff
   --- a/AGENTS.rules.md
   +++ b/AGENTS.rules.md
   @@ -1,2 +1,2 @@
   -rules
   +rules edited
    second line
   --- a/AGENTS.rules.md
   +++ b/AGENTS.rules.md
   @@ -1,2 +1,2 @@
   -rules edited
   +rules
    second line
   ```

   The row asserts `ok === false` **and** `reason === "underivable-empty-pathset"`,
   and carries a positive control in the same row — the first half of the same patch
   alone yields `ok: true, paths: ["AGENTS.rules.md"]` — so a mutant that refuses
   everything cannot pass it. (A create-then-delete pair does **not** work: measured,
   it leaves an `A` record.)
5b. The two `underivable-unparsable-record` sites each keep a behavioural row, driven
   by the PATH-shim seam in Guard 1's Assembly — a shim `git` that `exec`s real git
   for `read-tree` and `apply` and fabricates only the `diff-index` stdout. No mock
   and no production signature change.
6. `checkDiffPaths` with a fixture repo that has **no commit** (`git init -q`, so
   `read-tree HEAD` fails with `fatal: Not a valid object name HEAD`) returns
   `underivable-read-tree`.
7. `diffShape()` is exported, pure, returns `{ len, fenced, headerPair, hunk }`,
   computes `len` from the untruncated diff and the three predicates from
   `diff.slice(0, MAX_DIFF_BYTES)`, and returns no substring of its input. The three
   predicates use the non-catastrophic forms prescribed in D5; a row feeds a 1 MB
   input and asserts bounded completion.
8. `refusalDetail.push(...)` carries `detail` and the four shape fields as **flat**
   keys, remains **outside** the memoized step callback, and the outcome-census
   suite's Guard 3 (`refusals.push(`, `refusalDetail.push(`, `clustersOpened++`
   absent from `applyStepWindow(src)`) stays green.
9. `applyStepWindow()`'s step-callback opener still occurs exactly once, and the three
   pinned source texts — the callback signature, the
   `await checkDiffPaths(cluster.proposed_diff_unified` call, and
   `'return { kind: "refused", reason: "diff-size-exceeded" };'` — are byte-unchanged.
10. The two sibling sinks are fixed in the same PR: `detail` is removed from the
    `diff-path-refused` ctx-logger line, and the Sentry `extra` passes
    `safeDetail(pathVerdict.detail)`. A row asserts the bare form
    `detail: pathVerdict.detail` occurs zero times in the handler.
11. `spawnGitCapture`'s stderr accumulator is raised to 64,000 and made deterministic
    (`stderr = (stderr + chunk).slice(0, 64_000)`), so the only cut before redaction
    is `redactGithubSourcedText`'s own documented `MAX_INPUT_LEN`.
12. The control-character strip class includes C1: a detail containing U+0085 does
    not reach the emitted row raw.
13. In `emitOutcomeMarker()`, `detail` passes through `redactGithubSourcedText`, and a
    row proves it — with a companion row proving the unredacted fixture contained the
    shape, so the negative assertion cannot pass vacuously.
14. The 200-character bound holds **after** redaction, is **surrogate-safe**, and its
    straddle fixture is computed at test time (twelve short addresses: 97 characters
    before, 203 after). A second row restores a producer-side truncation and asserts
    real token characters leak — with the token preceded by a **non-word character**
    and starting at character 180, because `API_KEY_RE` is `\b`-anchored and a token
    glued to word characters is not redacted even untruncated.
15. A path-shaped token in `detail` is **classified, not relayed**: matched against
    `TARGET_ALLOW_RE` and the fixed prefix set it emits `<matched-prefix>/[elided]`,
    and otherwise the literal `[unclassified-path]`. The replacement is a **function
    replacement**, so `$&`-class sequences in attacker input are inert.
16. The transform applies to **every** `refusal_detail[]` entry, is built by
    **destructuring** the known fields rather than spreading, runs **before** the
    emitter's `try` so a throw cannot suppress the whole marker, and leaves `detail`
    **absent** (not `""`) on entries that never had one — `redactGithubSourcedText(undefined)`
    returns `""`, which would stamp "git said nothing" onto every non-diff refusal.
17. `SOLEUR_COMPOUND_PROMOTE_OUTCOME: true` and `fn:` are placed **after** the
    `...outcome` spread, so a widened outcome cannot shadow the discriminator. A row
    asserts an entry carrying an unmodelled extra key does not reach the emitted row.
18. The emitted row's serialized size stays under Vector's 10,000-character slice: a
    20-entry worst-case fixture (64-hex `cluster_hash`, 200-character `detail`, all
    shape fields) asserts `JSON.stringify(row).length < 10000`, with deterministic
    degradation — drop `detail` from tail entries first — and a flag recording that
    degradation occurred. Without this the row decodes as a string and every
    field-isolated reader drops it silently.
19. A plain git stderr detail with no PII and no path (`error: corrupt patch at line 3`)
    reaches the emitted row byte-identical.
20. No line of a proposed diff body can reach `detail`, asserted **behaviourally**: a
    fixture diff whose body carries a distinctive 40-character marker line, asserting
    `verdict.detail` shares no 20-character substring with it.
21. The marker module's `refusal_detail[]` doc comment states the new contract, the
    transform order, and the producer/sink cap asymmetry with `error_message`.
22. The runbook's `refusal_detail[]` paragraph states what `detail` carries and names
    the sink transform, lists the five split values and `diff-empty`, and says
    explicitly that `diff-empty` does **not** carry the `diff-underivable` prefix.
    Asserted by the presence of the replacement text, not the absence of the old.
22a. The runbook's `SOLEUR_COMPOUND_PROMOTE_OUTCOME` jq recipe projects
    `refusal_detail` through a **pinned flatten expression** — the existing recipe
    ends in `@tsv`, which errors on a non-scalar, so this cannot be left to the
    implementer. Ship it as one `@tsv` column, e.g.
    `[(.refusal_detail//[])[] | "\(.reason)@\(.cluster_hash[0:8]) len=\(.len//"-") f=\(.fenced//"-") h=\(.headerPair//"-") \(.detail//"-")"] | join(" ; ")`,
    with one worked sample output line. A docs-suite row asserts the fenced
    `SOLEUR_COMPOUND_PROMOTE_OUTCOME` block contains `refusal_detail`, so a revert of
    the recipe reddens a suite rather than a reviewer.
23. Phase 3 widens the existing `reportSilentFallback` `extra` at the
    `!pathVerdict.ok` branch with the four shape fields, so the discriminating
    evidence has two transports rather than one.
24. Processing Activity 8's `(c) Categories of personal data` cell names
    `refusal_detail[].detail` and the diff-shape fields, and the retention limb
    records journald on the host as a third at-rest copy with its own bound.
25. `scripts/checks/compound-promote-reason-sites.sh` exists, is multi-line tolerant,
    compares for exact set identity, and prints exactly
    `COMPOUND_PROMOTE_REASON_SITES_OK` on a match and nothing resembling it otherwise.
26. `python3 scripts/lint-guard-contract.py` exits 0 with three `### Guard` entries
    parsed from this plan file, and the PR body carries the two-halves ratchet run as
    a **pasted terminal verdict**. "Was run by hand" is ambient session state and
    cannot itself be an acceptance criterion
    (`cq-ac-must-not-depend-on-concurrent-sessions`).
27. The PR body uses `Closes #8427` (not the title), states the D1 compatibility
    choice — prefix-stable for the five split values, `diff-empty` a deliberate
    reclassification a saved `diff-underivable` query will stop matching — and records
    the consumer sweep that justified it.

## Domain Review

**Domains relevant:** Legal

### Legal

**Status:** reviewed
**Assessment:** The CLO assessed the change as **ADVISORY — no DPIA, no new
processing activity**. It falls inside already-recorded Processing Activity 8
("Operational Telemetry & Breach-Detection Logs", `knowledge-base/legal/article-30-register.md`):
same processor, same source, same purpose, no new recipient, no new transfer, no
new category of data — the test applied in
`knowledge-base/legal/audits/2026-09-04-betterstack-source-split-7772.md`. Art. 35
is not engaged: no systematic monitoring, no large scale, no Art. 9 data.

Three conditions attach, and all three are acceptance criteria above:

1. **PA-8 §(c) amendment.** The nearest precedent —
   `knowledge-base/legal/audits/2026-09-08-clo-attestation-7500-zot-last-err-redaction.md`
   (`zot_last_err`) — was the same shape, a bounded free-text error field on an
   existing PA-8 emitter, and required an in-cell categories-limb amendment rather
   than a new activity. AC17.
2. **Redaction is precedent, not coverage.** The register warns that
   `redactGithubSourcedText` "strips credentials, emails, UUIDs and IPs but NOT
   usernames, handles or free text". That `error_message` already rides the same
   redactor establishes the pattern, not the sufficiency — hence the additional
   slug elision in D4. AC9–AC11.
3. **Art. 5(1)(c) on the path.** Better Stack has **no executed Art. 28(3)
   instrument** (Vendor/Sub-Processor Mapping reads `NOT EXECUTED`; escalations are
   #7529 and #7825) and a 90-day retention, so incremental payload into that sink
   is weighed on necessity. The advisory asked for basename-or-first-segment for
   all paths; D4 narrows that to learnings slugs only, because for
   `diff-path-refused` the offending path is the answer and eliding it reinstates
   the defect being fixed. This narrowing is a deliberate, recorded divergence from
   the advisory, not an omission.

The change does not widen reliance on Better Stack; it is bounded, redacted, and
90-day-retained on an existing edge.

**Phase 2.7 note:** the GDPR/compliance gate's canonical regex (schemas, migrations,
auth flows, API routes, `.sql`) matches none of this plan's Files to Edit, and none
of the four expansion triggers fires — no new LLM/external-API processing (the
corpus already goes to Anthropic and this change adds none of it), threshold is
`aggregate pattern` rather than `single-user incident`, no new cron reads the
learnings corpus, and no new artifact-distribution surface. The Art. 30 / DPIA
determination above was produced by the CLO domain leader rather than a separate
gate invocation, and is recorded here in full rather than by reference.

### Product/UX Gate

Not applicable, and the mechanical override was checked rather than assumed: the
`## Files to Create` list is empty and the `## Files to Edit` list contains no path
matching `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`, or any term
in `plugins/soleur/skills/brainstorm/references/ui-surface-terms.md`. Product is
**NONE** — this is server-side cron telemetry with no user-facing surface, so no
`.pen` wireframe is owed under `wg-ui-feature-requires-pen-wireframe`.

### Other domains

Finance, Sales, Marketing, Operations, Support and Product were assessed against
their Assessment Questions and none is relevant: the change alters no pricing, no
pipeline, no messaging, no vendor relationship or spend, no customer-facing support
surface, and no product capability. It changes how one internal cron explains its
own refusals.

**Functional overlap (Phase 1.5b):** NO OVERLAP. No Soleur skill or agent owns
compound-promote refusal telemetry (`grep -rIl "compound-promote" plugins/` returns
only prose mentions in three SKILL.md files and two fixtures), no unified-diff shape
helper exists anywhere under `apps/web-platform/` or `plugins/`, and the two external
registries queried returned nothing related. The reusable structures the plan extends
rather than reimplements are the existing `refusalDetail` accumulator and its single
push site.

## Test Scenarios

Every fixture below is either measured against git 2.55.0 in this worktree, or
explicitly marked as owed a measurement. None is guessed.

| # | Given | When | Then |
|---|---|---|---|
| 1 | `checkDiffPaths` with a fixture repo | called with `""` | `{ ok: false, reason: "empty" }`; this is the re-based `row 9 (dispatch)` |
| 2 | same | called with a spaces/tab/CRLF-only string | `{ ok: false, reason: "empty" }` — the non-empty whitespace case Guard 2 row 4 needs |
| 3 | same | called with `"not a diff at all"` | `reason: "underivable-apply"` (the updated `row 2`) |
| 4 | same | called with a markdown-fenced diff block | `reason: "underivable-apply"`; `fenced: true`, `headerPair: false` |
| 5 | same | called with a `---`/`+++` pair and no `@@` hunk | `reason: "underivable-apply"`; `headerPair: true`, `fenced: false` |
| 6 | a fixture repo created by `git init -q` with **no commit** | called with any diff | `reason: "underivable-read-tree"` — measured: `read-tree HEAD` exits non-zero with `fatal: Not a valid object name HEAD`. Three lines, no mocks |
| 7a | the PATH shim fabricating `diff-index` stdout `notacolon\0x.txt\0` | called | `reason: "underivable-unparsable-record"` via the `!meta.startsWith(":")` site |
| 7b | the PATH shim fabricating `:100644 100644 aaa bbb\0x.txt\0` | called | `reason: "underivable-unparsable-record"` via the five-field site. 7a and 7b are separate rows because the two sites share a literal and a set comparison cannot tell them apart |
| 8 | the measured edit-then-revert double patch in AC5a | called | `reason: "underivable-empty-pathset"`, **and** the first half alone yields `ok: true, paths: ["AGENTS.rules.md"]` as the positive control |
| 9 | a diff with two leading blank lines then a real hunk | called | not refused as `empty`; applies at rc 0; yields a real `diff-index` record |
| 10 | a 1 MB input | `diffShape()` called | returns in bounded time; `len` reflects the full input, the three predicates read only the first `MAX_DIFF_BYTES` |
| 11 | `emitOutcomeMarker` with a detail containing an email | emitted | no `@` in the row's detail; a companion row asserts the fixture did contain one |
| 12 | twelve short addresses (97 chars before, 203 after redaction), both preconditions asserted | emitted | the row's detail is at most 200 characters |
| 13 | a token preceded by a non-word character, starting at character 180 | emitted | fully redacted; with a producer-side truncation restored, 16 real token characters leak — RED |
| 14 | a detail containing U+0085 | emitted | the character does not reach the row raw |
| 15 | a detail naming an unrecognised path | emitted | `[unclassified-path]`, not the path |
| 16 | a detail naming a learnings file | emitted | `knowledge-base/project/learnings/[elided]` |
| 17 | a detail naming `plugins/soleur/skills/plan/SKILL.md` | emitted | the matched prefix plus `[elided]` |
| 18 | `error: corrupt patch at line 3` | emitted | byte-identical in the row |
| 19 | two refusal entries, the second carrying an email | emitted | both entries transformed |
| 20 | a refusal entry that never had a `detail` | emitted | no `detail` key at all — not `""` |
| 21 | an entry carrying an extra unmodelled key | emitted | the extra key is absent from the row |
| 22 | one malformed entry among several | emitted | the marker is still emitted; that entry degrades to `{cluster_hash, reason}` |
| 23 | a 20-entry worst-case fixture | emitted | `JSON.stringify(row).length < 10000`, with the degradation flag set if trimming occurred |
| 24 | a fixture diff whose body carries a distinctive 40-character marker line | `checkDiffPaths` called | `verdict.detail` shares no 20-character substring with the diff |
| 25 | the handler source | censused | `applyStepWindow(src)` contains none of `refusals.push(`, `refusalDetail.push(`, `clustersOpened++`; and `detail: pathVerdict.detail` (bare) occurs zero times |
| 26 | the refusals hoisted behind a local `refuse()` helper, literals unchanged | AST census run | still GREEN — the census pins behaviour, not formatting |
| 27 | the text `reason: "underivable-apply"` inserted as an asterisk-continuation, a single-line `/* */`, and a trailing `//` | AST census run | result unchanged for all three spellings |
| 28 | the plan file | `python3 scripts/lint-guard-contract.py` | exits 0 with three guard entries |
| 29 | the committed probe script | `bash scripts/checks/compound-promote-reason-sites.sh` | prints exactly `COMPOUND_PROMOTE_REASON_SITES_OK`; with any one emit site reverted, prints something else |

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Rename the enum wholesale (drop the `diff-` prefix) | Possible — the consumer sweep is nearly empty — but prefix stability costs nothing for the five split values. `diff-empty` is the deliberate exception (D1). |
| Put the empty-diff check at the handler call site | Symmetric to read, but the guard would be exercisable only by source-text assertion, and it sits beside a byte-pinned mutation anchor. Rejected in D2. |
| Log the proposed diff body alongside the refusal | Answers the ambiguity directly and is the one thing `PII_REGEX` exists to prevent. The shape fields answer it with no body. |
| Emit a second marker row per refusal instead of widening `refusal_detail[]` | Doubles the row count on an already-capped sink and needs its own join key and ordering guarantee. Cut in Phase 0.6b. |
| Add a `const _exhaustive: never` rail over the split union | Would quantify over an empty consumer set. Cut in Phase 0.6b. |
| A **regex** census over comment-stripped source for Guard 1 | The first design, rejected on measurement: the repo's line-oriented strippers miss single-line, JSDoc-opener and trailing comments; the two long returns may wrap and there is no formatter config to fix their shape; and an ordinary `refuse()` hoist would redden it with the property intact. Replaced by an AST census using the already-installed `typescript` package. |
| An in-window "no git process spawned" assertion for Guard 2 | The reorder it targets is already caught by a return-value row, `spawnGitCapture` is module-local and unspyable, and the only other observable races with concurrent vitest workers. Cut. |
| Declaring `underivable-unparsable-record` behaviourally untestable | The first draft's position. A PATH shim in front of bare `spawn("git", …)` reaches both sites with no mock and no signature change, so the arm is covered rather than excused. |
| Eliding only `knowledge-base/project/learnings/` slugs in `detail` | Fired only on its own stated exception, and aimed at disclosure when the real risk is a 200-character controlled **write** channel. Replaced by classification (D4.3). |
| Cut `len` and `headerPair`, or collapse the four shape fields into one `kind` enum | Better designs on the merits, proposed by three reviewers. Both restructure scope the work target named explicitly, so they are User-Challenges recorded in `decision-challenges.md`, not applied here. |
| A `vitest -t`-filtered behavioural `discoverability_test` | Stronger than a grep, but risks preflight Check 10's 15-second cap, where a timeout reports identically to a down endpoint. |
| An inline `grep` pipeline as the `discoverability_test` | Check 10's matcher is `tokens.some(...)`, so a six-token expectation PASSes on one surviving token; and the inline regex was single-line-only in a repo with no formatter. Replaced by a committed script printing one token. |

## Non-Goals

- Changing what `checkDiffPaths` refuses. Apart from the new `empty` arm — which
  refuses inputs that were already refused, under a truer name — the verdicts are
  identical; only their names and the telemetry beside them change.
- Changing the `structural-op` or `path-refused` reasons themselves.
- Relaxing `TARGET_ALLOW_RE`, the binary-patch refusal, or the creation refusal
  (creation is Phase 2, #8293).
- Making the cron propose better diffs. This plan makes a refusal explain itself.
- Rewriting the existing source-text-anchor machinery. Three of the four pinned
  anchors pre-date this PR; the class is real and correctly deferred. What this PR
  owes is not *adding* to the pile — which is why AC20 is behavioural and Guard 1 is
  an AST census rather than a second regex parser.
- Adding an explicit `[sinks.betterstack.tls]` block to `vector.toml`. Recorded as a
  gap in `## Encryption Posture`; it is an infra edit outside this change's surface.
- Executing an Art. 28(3) instrument with Better Stack. Pre-existing, tracked at
  #7529 / #7825, neither widened nor closed here.

## Sharp Edges

- **The `row 9 (dispatch)` fixture is the empty string, not an unparsable diff.** Its
  title says "a diff git cannot parse", which is why a first reading — and the work
  target — took it for an apply-arm row. It is the **vacuity** row, and the new
  predicate intercepts it. Re-base it *and* replace the `underivable-empty-pathset`
  coverage it was silently providing (AC5a), or that arm ships with none.
- **Three truncations sit between git and the sink, and only the last one is
  allowed.** `spawnGitCapture` cuts at ~4096 (non-deterministically, testing length
  before appending), `safeDetail` cuts at 200, and `redactGithubSourcedText` cuts at
  64,000. Any cut before redaction can halve a credential so no pattern matches.
- **`detail` reaches two other sinks bare.** The `diff-path-refused` ctx-logger line
  and the Sentry `extra` both read `pathVerdict.detail` unwrapped. Widening the
  verdict's detail widens both — and the ctx logger lands in the *same* Better Stack
  source as the marker.
- **`emitOutcomeMarker` spreads `...outcome` after the discriminator.** A widened
  outcome can shadow `SOLEUR_COMPOUND_PROMOTE_OUTCOME: true`, which every reader
  field-isolates on.
- **Vector slices the row at 10,000 characters** and a sliced row is invalid JSON,
  which the runbook's own `select(type == "object")` guard then drops silently. The
  worst-case widened row is ~9,046 characters before JSON escaping.
- **The transform must be built before the emitter's `try`.** Its `catch` is a bare
  fail-open, so a throw inside it suppresses the entire marker, not just `detail`.
- **`redactGithubSourcedText(undefined)` returns `""`.** An unguarded map stamps
  `detail: ""` onto every non-diff refusal, which reads as "git said nothing".
- **`API_KEY_RE` is `\b`-anchored.** A straddle fixture that glues the token to
  preceding word characters is not redacted even untruncated, so the row fails
  against a *correct* implementation and invites weakening the assertion.
- `applyStepWindow()` throws unless the step-callback signature occurs exactly once.
  Optional fields are safe; changing how that signature renders is not.
- The outcome-census suite pins
  `'return { kind: "refused", reason: "diff-size-exceeded" };'` byte-for-byte, and the
  allowlist suite pins the `await checkDiffPaths(cluster.proposed_diff_unified` call
  text. Do not reformat either.
- **There is no formatter config in this repo**, so whether a 108-character return is
  one line or three is an implementer's choice. Any check that depends on that shape
  is a check that depends on taste — which is why Guard 1 is an AST census and the
  probe is a committed multi-line-tolerant script.
- **Check 10's `expected_output` matcher is `tokens.some(...)`.** A multi-token
  expectation PASSes on one surviving token. Single-token outputs only.
- The marker's pino instance is deliberately not `server/logger.ts`, so layer 2 does
  not cover the marker row; and the transport is Vector **Source 3**
  (`app_container_journald`, filtered on pino `level >= 40`), not the Inngest-host
  source — which is what makes "the emitter must stay at WARN" load-bearing.
- **The runbook's jq recipe is a separate artifact from its prose**, and it ends in
  `@tsv`, which errors on a non-scalar. Pin the flatten expression; do not leave it to
  the implementer.
- When editing these documents, match section headings on **whole lines**, not by
  substring: this plan discusses `## Guard Contract` in prose above the section of
  that name, and a naive first-index splice cut the file at the prose mention.
- Writing a literal `\0`-style escape sequence through a JSON-encoded tool
  argument can decode it into a real control character. Both this plan and the code
  it describes handle such sequences; write them so they survive the round trip.
- The two-halves ratchet run is not optional and not diff-derivable.
  `scripts/lint-guard-contract.py` lints this plan's own Guard Contract section.
- Do not carry the ratchet counts forward as constants. Run the greps.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/
  placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.
