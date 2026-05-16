# Type widening cascades to consumer obligations; write-boundary sentinels must cover every write call site

**Date:** 2026-05-12
**Branch:** worktree-feat-cc-soleur-go-transcript-hardening-pr-a2-3603
**Issue:** #3603 (PR-A2 of 4-PR sequence)
**Predecessor:** PR #3602 (PR-A1, W2+W8)

## Problem

Two separate-but-related defects survived a 3-reviewer plan-time pass (legal-compliance-auditor + code-simplicity-reviewer + architecture-strategist) and were only caught by an 8-agent implementation-time review:

### Defect A — type widening produces silent NaN at consumer sites

PR-A2 narrowed `messages.usage` jsonb to `{ cost_usd }` on cc-router complete turns (Art. 5(1)(c) data minimization) and accordingly widened `Message.usage`'s TypeScript shape: `input_tokens` / `output_tokens` / `completed_actions` became optional. The doc-comment was updated to require readers branch on field presence.

But the writer-side change cascaded silently to consumer code that wasn't part of the plan's "Files to edit" list:

- `apps/web-platform/lib/ws-client.ts` hydration mapper unconditionally read `m.usage.input_tokens`, `m.usage.output_tokens`, `m.usage.completed_actions` and assigned them to a typed `AbortMarkerUsage` slot whose fields were still declared as `number`.
- `apps/web-platform/components/chat/message-bubble.tsx:327` computed `usage.input_tokens + usage.output_tokens` to render the abort-marker "tokens" chip.

Both sites compile cleanly because the mapper's `undefined` coerces through `any`-typed JSON. The first time a cc-router turn aborts with the flag flipped on, the UI renders `NaN tokens · $0.0042` — a corrupt persistent value that survives page reload.

TypeScript could not enforce the new branching obligation because the producer's widening went through a jsonb column whose payload type isn't validated at the boundary.

### Defect B — write-boundary sentinel at only one of two write sites

The W1 plan introduced `assertWriteScope(userId, conversationId)` as the cross-tenant write-boundary sentinel, with rationale: "cc-dispatcher uses the service-role Supabase client (RLS-bypass on writes), so a misrouted dispatch persisting User A's content into User B's conversation would be undetected by RLS."

The plan and implementation both put the sentinel at the top of `saveAssistantMessage` (which writes assistant rows). What both missed: the **user-message row** is also INSERT'd from cc-dispatcher (since #3254 for `message_attachments.message_id` FK durability), through the same service-role client at `cc-dispatcher.ts:1008-1023`. Same cross-tenant surface, same Art. 33/34 exposure — but no sentinel call.

A reviewer agent caught it during implementation-time review: "user-row INSERT bypasses assertWriteScope — same cross-tenant risk surface."

## Root cause

### Defect A
Type widening was correctly performed on the producer side (Message.usage), with a doc-comment instructing readers to branch on field presence. **The doc-comment is documentation; it does not produce a compile error at the consumer site.** When the legacy shape is the only one the type system models as required, downstream readers wrote `usage.input_tokens + usage.output_tokens` and the TS check passed. The compiler did not — could not — enforce the new contract on existing consumers whose definitions live elsewhere.

### Defect B
The W1 plan framed the sentinel in terms of "the assistant-row write path" because that's what the user-brand failure mode story called out (assistant content cross-tenant leak). The user-message write site existed before W4 work, in code that wasn't being changed in this PR. The plan's "Files to edit" list anchored review attention to the changed regions, not to ALL service-role write call sites in the file.

Both defects share a class: **a plan-time invariant that names a *property* of a system (here: "the dispatcher must scope-check before service-role writes" / "consumers must field-presence-branch the usage type") requires a sweep over every site that the property applies to — not just the sites touched by the diff.**

## Solution (applied)

### Defect A fix

Widen `AbortMarkerUsage` to match `Message.usage` optionality:

```ts
// components/chat/message-bubble.tsx
export interface AbortMarkerUsage {
  input_tokens?: number;
  output_tokens?: number;
  cost_usd?: number | null;
  completed_actions?: Array<{...}>;
}
```

Branch on field presence in `renderAbortedAssistant`:

```ts
const totalTokens =
  usage &&
  typeof usage.input_tokens === "number" &&
  typeof usage.output_tokens === "number"
    ? usage.input_tokens + usage.output_tokens
    : null;
// totalTokens === null hides the tokens chip; the cost chip still renders.
```

Spread-conditional in the hydration mapper so undefined doesn't coerce:

```ts
// lib/ws-client.ts
usage:
  m.status === "aborted" && m.usage
    ? {
        ...(typeof m.usage.input_tokens === "number"
          ? { input_tokens: m.usage.input_tokens }
          : {}),
        ...(typeof m.usage.output_tokens === "number"
          ? { output_tokens: m.usage.output_tokens }
          : {}),
        cost_usd: m.usage.cost_usd ?? null,
        ...(m.usage.completed_actions
          ? { completed_actions: m.usage.completed_actions }
          : {}),
      }
    : null,
```

### Defect B fix

Add `assertWriteScope` call before the user-row INSERT in cc-dispatcher.ts. Throw (not return) because the function is awaited and the existing insertErr path already throws:

```ts
if (!assertWriteScope(userId, conversationId)) {
  throw new Error("cc-dispatcher: assertWriteScope halted user-message persistence");
}
const { error: insertErr } = await supabase().from("messages").insert({...});
```

Update `T-W1-invariant-7` from a 2-call-site spy assertion to a 3-call-site call-counting spy that passes the user-INSERT (so dispatch proceeds) and halts both assistant call sites:

```ts
let scopeCallCount = 0;
const scopeSpy = vi.fn(() => {
  scopeCallCount += 1;
  return scopeCallCount === 1; // user-INSERT passes, assistant calls halt
});
// Assert exactly 3 spy invocations: user + complete + abort.
```

## Key Insight

**A type-widening that loosens a producer-side invariant creates a debt on every downstream consumer — even consumers in files the plan doesn't list as "edited." The compiler cannot enforce this debt for jsonb / unknown / any payloads; doc-comments cannot either.** Before merging a widening, grep every consumer of the widened field and verify the new contract is honored at each. The grep is the only mechanical defense.

**A write-boundary sentinel that protects a property of a system (e.g., "cross-tenant write integrity") must be applied at every site the property applies to. The plan's "Files to edit" list and the test's call-site assertions anchor attention to the diff, not to the property's full surface. Run a `git grep '.from\("messages"\).insert' apps/web-platform/server/` (or equivalent) and confirm every match is sentinel-gated.**

Both defects were caught by parallel review agents (data-integrity-guardian and security-sentinel) reading the *file*, not the *diff*. The 3-reviewer plan-time pass operated on the proposed contract and missed both surfaces. **Implementation-time multi-agent review is not redundant with plan-time review — it inspects load-bearing properties against the actual full file, including code the plan didn't touch.**

## Prevention

1. **Type-widening checklist (add to `cq-union-widening-grep-three-patterns` rule):** Before merging a producer-side widening of a shared type, grep all consumers and verify each respects the new optionality. For `Message.usage`-class changes, the grep is `git grep -nE '\busage\.(input_tokens|output_tokens|completed_actions)' apps/`.

2. **Write-boundary sentinel sweep (add to plan checkpoint for security-property PRs):** When a plan adds a guard that asserts a property at a write site, the plan's Phase-0 grep audit must enumerate ALL sites where the property applies, not just sites in the diff. For PR-A2 this would be `git grep -nE '\.from\("messages"\)\.insert' apps/web-platform/server/`.

3. **Run plan-prescribed skills inline (`hr-gdpr-gate-on-regulated-data-surfaces`):** When a plan checkpoint calls a named skill explicitly (e.g., `/soleur:gdpr-gate` at Phase 2.5), invoke it during /work execution rather than deferring to "operator at PR time." Hard rule already exists.

4. **Multi-agent review is mandatory for GDPR/security-property PRs:** The 3-reviewer plan pass + the 8-agent implementation pass are non-redundant. The plan pass catches contract gaps; the implementation pass catches consumer-side cascade defects.

## Session Errors

- **`npx vitest` fetched a stale rolldown binary** crashing with `Cannot find module '@rolldown/binding-linux-x64-gnu'`. **Recovery:** switched to `./node_modules/.bin/vitest`. **Prevention:** all future `vitest` calls in this repo use the local binary, not `npx vitest`. Worth a `.claude/settings.json` permission scope or a SessionStart hook nudge.

- **`apps/web-platform/node_modules` empty at session start.** **Recovery:** `bun install`. **Prevention:** matches the plan's Phase 0.3 baseline check (and learning `2026-03-18-bun-test-segfault-missing-deps.md`). A `wg-at-session-start` hook to detect missing node_modules in active worktree would close this.

- **Bash CWD persistence confusion** — `cd apps/web-platform` from worktree root persisted but printed an error, then 3 subsequent commands ran from inside `apps/web-platform` while I expected worktree root. **Recovery:** absolute paths. **Prevention:** never rely on prior-Bash-call CWD; the agent CLAUDE.md note already says this — I drifted.

- **`bun run lint` interactive prompt** — `next lint` deprecated and prompts for ESLint setup. **Recovery:** deferred to CI. **Prevention:** repo should migrate off `next lint`; until then, `bun run lint` is non-functional and should be skipped or replaced with `biome check` / explicit eslint invocation.

- **Python regex for plan checkbox-sync missed bolded items** — matched `\*\*1\.1\.[1-6]\*\*` instead of `\*\*1\.1\.[1-6]` (bold spans the full label, not just the number). **Recovery:** re-read the file, adjusted regex. **Prevention:** for batch markdown edits with regex, dry-run against one line and verify match count > 0 before applying.

- **T-W1-invariant-7 first design used `vi.spyOn` on a module namespace** — ESM internal calls aren't intercepted. **Recovery:** introduced `__setAssertWriteScopeForTests` test seam. **Prevention:** for testing internal helper calls in ESM modules, default to a `__setXForTests` test seam.

- **First single-reviewer agent made a false-positive claim** about accumulator-clear ordering. **Recovery:** re-read code line-by-line before committing. **Prevention:** review-agent claims about flow ordering must be verified against the code, not the agent's summary.

- **T-W1-invariant-7 broke after adding user-INSERT sentinel.** **Recovery:** switched to call-counting spy pattern. **Prevention:** when adding a new sentinel call site, scan existing sentinel tests for call-count assumptions.

- **T-W4-race vacuous-pass claim** — initial test fired events sequentially per turn; reviewer flagged. **Recovery:** reframed to exercise a LATE stale `onResult` between turns. **Prevention:** before claiming a test exercises a "race," trace the SDK callback model — synchronous emitters don't admit microtask races.

- **`/soleur:gdpr-gate` not invoked inline** despite plan Phase 2.5 calling for it. **Recovery:** deferred to operator at PR time and noted in tasks.md. **Prevention:** when a plan checkpoint calls a named skill explicitly, invoke it (or fail-closed and surface the inability). `hr-gdpr-gate-on-regulated-data-surfaces` already covers this — I drifted.

## Cross-references

- Plan: `knowledge-base/project/plans/2026-05-12-feat-cc-soleur-go-transcript-hardening-pr-a2-plan.md` (rev-2)
- Tasks: `knowledge-base/project/specs/feat-cc-soleur-go-transcript-hardening-pr-a2-3603/tasks.md`
- Predecessor PR: #3602 (W2+W8, merged 2026-05-12)
- Issue umbrella: #3603 (stays open until PR-B + PR-C ship)
- Follow-up issues filed: #3638-#3642 (review-finding deferrals)
- Related learning: `2026-05-12-pr-a1-implementation-and-multi-reviewer-convergence.md` (carry-forward)
- Related learning: `2026-05-11-plan-research-reconciliation-must-grep-full-render-tree.md` (the "grep full render tree" insight applied here too)
- Related learning: `2026-05-04-telemetry-join-format-mismatch-caught-by-orphan-counter.md` (explicit-null contract)
- Related rule: `cq-union-widening-grep-three-patterns` — this learning extends it to type-widening with jsonb crossings.

## Tags

```yaml
category: integration-issues
module: cc-dispatcher
class: type-widening-cascade + write-boundary-sentinel-coverage
gdpr-relevance: Art. 33/34 (cross-tenant), Art. 5(1)(c) (data minimization), Art. 13(3) (new-category disclosure)
load-bearing: yes
discovered-by: 8-agent implementation-time multi-reviewer pass
escaped-from: 3-reviewer plan-time pass
```
