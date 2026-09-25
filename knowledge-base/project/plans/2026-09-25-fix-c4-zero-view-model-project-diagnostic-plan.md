---
title: "fix(c4): explain a zero-view model on GET /api/kb/c4/project instead of an unexplained empty canvas"
type: fix
date: 2026-09-25
slug: fix-c4-zero-view-model-project-diagnostic
branch: feat-one-shot-8740-c4-zero-view-diagnostic
issue: 8740
closes: none (Ref #8740 — the issue closes on its re-evaluation criteria, not on merge)
priority: p2-medium
domain: product
brand_survival_threshold: none
lane: cross-domain
---

# fix(c4): explain a zero-view model on GET /api/kb/c4/project

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Overview

A committed `model.likec4.json` that holds elements but no views renders in the C4 workspace as
"View `index` not found in the model.", with nothing saying why. The server's re-render committed
such models before #8732 (ee9f2c9, merged 2026-09-24) pinned wasm layout (`--no-use-dot`) and
refused zero-view exports.

The 2026-09-25 read-only census (posted on #8740) found exactly one such model: an external tenant
repository, 40 elements, 0 views, opaque id `84dd700449ea`. No save has re-rendered it since the fix
deployed.

This plan makes the owner-scoped read route `GET /api/kb/c4/project` return one diagnostic when the
model it reads has elements but no views. The existing diagnostics strip above the canvas then says
what happened and how to fix it. The plan also records the decision **not** to write a re-render
into the affected external repository from this PR (see Re-render Decision), and it automates
#8740's evidence-based close.

## Research Reconciliation — Spec vs. Codebase

| Claim in the issue / brief | Reality on `origin/main` (d5a5887438) | Plan response |
|---|---|---|
| The tenant sees "a blank canvas". | Not blank. `C4Canvas` → `ViewCanvas` renders "View `<viewId>` not found in the model." when the view is absent (`components/kb/c4-shared.tsx`, `ViewCanvas`). The viewId comes from the markdown `likec4-view` block (`lib/c4-embed.ts` `parseLikeC4Embed`). | The diagnostic explains that line. The canvas is unchanged. |
| Suggested copy: "save the diagram to re-render it". | The user-direct Save (Code panel and `PUT /api/kb/c4/[...path]`) is behind `c4-edit` (`lib/c4-constants.ts` `C4_EDIT_FLAG`), default OFF for all roles. The Concierge's `edit_c4_diagram` is the only live writer, and every `.c4` write re-renders (`server/c4-writer.ts` `writeC4Diagram` → `rerenderAndCommit`, no content-equality skip). | The copy names a concrete Concierge edit and drops "save" (Phase 1, item 1). |
| After a fix, the page updates. | Nothing reloads the workspace after a Concierge write. `useC4Project` refetches only on mount, on a `dirPath` change, or through `reload()`, and the only `reload()` caller is the Code panel's `onSaved`, which `c4-edit` gates off. That wiring is open issue #8739. | The copy tells the user to reload. The clause is removed when #8739 ships (ship comments on #8739). |
| The route has a diagnostics channel. | Yes, but it has never carried an entry. `diagnostics: []` is hard-coded in the 200 body. Every consumer (`c4-workspace.tsx`, `c4-diagram.tsx`) passes it to `C4Diagnostics`, which prints each entry as `line {d.line}: {d.message}` under "Diagram warnings". | A model-level entry has no source line. The route uses `line: 0`, and the strip omits the `line N:` prefix when `line <= 0` (Phase 1, item 2). No type change. |
| The shared public link might need the diagnostic too. | `app/api/shared/[token]/c4/route.ts` returns only `{ dir, dump, viewIds }`, by design (data minimisation), and its recipients cannot edit. | Out of scope (Non-Goals). The owner's re-render fixes it for them too. |

## Research Insights

**Premise validation (Phase 0.6).**

- #8740 is OPEN (`type/bug`, `priority/p2-medium`, `domain/product`).
- #8696 is CLOSED by PR #8732. ee9f2c9 is on `origin/main`.
- Census comment `issuecomment-5830485520` (2026-09-25): 3 installations, 33 repos, 0 errors.
  - Internal: 12 repos, 1 model, 0 zero-view.
  - External: 21 repos, 1 model, 1 zero-view.
- Queue items #8739 and #8752 are OPEN. Neither is touched here.
- Every cited path exists on `origin/main`.
- ADR-050's 2026-09-24 amendment ("Wasm layout pinned; zero-view models refused") refuses zero-view exports at write time and names #8740. It rejects nothing about a read-side diagnostic.

**Property List (Phase 0.6b).**

- P1. When the committed model has at least one element and no views, the owner's C4 page says so and names an action that fixes it.
- P2. A model with views, or an empty model (no elements), shows no such message.
- P3. The operator can tell, without running the census, whether anyone still loads a zero-view model. This is the evidence for #8740's close.
- P4. Nothing is written to an external tenant repository without an explicit operator ack.

**Cut List (Phase 0.6b).**

- Server-triggered one-off re-render for the affected repo (P1/P4). Cut: it is an external-tenant write, which needs an operator ack a pipeline cannot give. The diagnostic plus the existing Concierge write path delivers P1.
- New "re-render without a source change" endpoint or Concierge tool (P1). Cut: `edit_c4_diagram` already re-renders on every `.c4` write.
- Committed census script (P3). Cut: the method is recorded on #8740 and needs prd App credentials.
- Follow-through keyed on the census (P3). Cut: it would wire `GITHUB_APP_PRIVATE_KEY` into the sweeper for one tenant. The follow-through here is keyed on the Sentry signal, whose read token the sweeper already holds.
- New `modelDiagnostic` response field or new banner element (P1). Cut: the existing `diagnostics` channel and strip carry it.

**Value-proposition measurement (0.6c).** Not applicable. No cost or performance saving is claimed.

**Relevant files.**

- `apps/web-platform/app/api/kb/c4/project/route.ts`: the GET handler. It parses `dump`, derives `viewIds` with plain-object semantics, and returns `diagnostics: []`.
- `apps/web-platform/server/c4-render.ts`: module-private `plainObjectSize` (used at 3 sites), plus the write-side gates `empty_model` and `layout_failed`/`zero-views`.
- `apps/web-platform/components/kb/c4-diagnostics.tsx`: `C4Diagnostics`, the red strip ("Diagram warnings" when `hasModel`, up to 8 entries).
- `apps/web-platform/components/kb/c4-shared.tsx`: the `Diagnostic` type (`{ message; line; sourceFsPath }`), and `useC4Project`, which normalises `diagnostics ?? []`.
- `apps/web-platform/server/observability.ts`: `mirrorWarnWithDebounce(err, ctx, key, errorClass)` (5-minute per-key dedup, then `warnSilentFallback`), and the errorClass registry doc comment.
- `apps/web-platform/test/c4-project-route.test.ts`: `setupGitHub(files)` mocks the Contents listing and the Blobs API. The `@/server/observability` mock is `importActual` plus a `reportSilentFallback` spy.
- `apps/web-platform/test/c4-shared.test.tsx`: renders the real `C4Diagnostics`.
- `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh`: the Sentry-probe template. Its `* = TRANSIENT` exit contract is older than the sweeper's current word map.
- `scripts/sweep-followthroughs.sh`: the exit-code map (`0` close, `1` FAIL, `2` NOT YET, `3` CANNOT ESTABLISH, `5` ACTION REQUIRED, other TRANSIENT), and the closed-issue reopen-on-exit-1 path (`CLOSED_LOOKBACK_DAYS=14`).

**Institutional learnings applied.**

- `2026-09-24-sandboxing-a-render-child-with-bwrap-no-writable-host-bind.md` and the ADR-050 amendment. Zero views is always a layout failure, never the user's source, so the copy must not blame the source.
- `2026-05-13-mirror-with-debounce-vs-report-silent-fallback-for-high-cardinality-surfaces.md`. A per-request emit on a GET floods Sentry, so the warning uses the debounced variant.
- #8629 (ADR-050 §Observability). Pass `err = null` so the tags survive, and use a fixed message so Sentry groups one issue.
- `2026-07-18-backlog-issue-with-merged-code-closes-on-deploy-gate-not-merge.md` and `2026-05-07-pr-title-closes-keyword-ignores-qualifiers-and-d4-silent-failure.md`. Say `Ref #8740`, never `Closes`.
- `integration-issues/2026-06-15-c4-read-from-github-source-of-truth-and-blobs-api-1mb-gotcha.md`. The route reads GitHub, so the diagnostic reflects committed truth.
- `cq-test-fixtures-synthesized-only`. Use synthetic 1-2 element fixtures, never the tenant's model.
- `cq-nextjs-route-files-http-only-exports`. The route's new constant stays non-exported.
- The follow-through convention (`knowledge-base/engineering/operations/runbooks/followthrough-convention.md`):
  - require a positive liveness marker before a zero-count PASS;
  - use `SENTRY_ACTIONS_RO_TOKEN` only;
  - no `${VAR:?}` gates;
  - paste the directive unfenced;
  - list the files to retire in a `RETIREMENT:` header.

**Related issues.** #8732 (the fix PR), #8696 and #8695 (closed), #8739 (Concierge edit → workspace reload; this plan's reload clause depends on it), #8752 (untouched), #8629 (Sentry tag drop).

**Functional overlap (1.5b).** No community registry artifact overlaps.

**Community discovery (1.5).** TypeScript/Next.js is covered. Skipped.

**External research (1.6).** Skipped. There is direct in-repo precedent for every piece, and no new dependency or external API.

## Re-render Decision

**Decision: this PR does not re-render, or write to, the affected external repository.**

- A re-render is a commit into a tenant repository the tenant did not ask for. Under `hr-menu-option-ack-not-prod-write-auth` that needs an explicit operator ack, which a headless pipeline cannot supply.
- After this PR the canvas explains itself and names the edit that fixes it. `edit_c4_diagram` re-renders on every `.c4` write and refuses zero-view exports.

**Operator choices** (persisted to `knowledge-base/project/specs/feat-one-shot-8740-c4-zero-view-diagnostic/decision-challenges.md`, DC-1):

- (a) **Default:** leave the repository alone. #8740 closes on evidence:
  - the follow-through sweeper closes it after 14 quiet days; or
  - a census re-run shows 0 zero-view models.
- (b) Authorise one re-render: a single `.c4` write through the existing writer, with the operator's explicit ack.
- (c) Contact the tenant through support. The CPO prefers (c) to (b), because it asks before writing. The trigger to move from (a) to (c) is Sentry's first-seen email for the `op:zero-view-model` issue, or a sweeper FAIL.

**#8740 stays OPEN.** The PR body says `Ref #8740`.

## Implementation Phases

### Phase 1: Tests first (RED), then code (GREEN)

1. **Shared shape helper (`apps/web-platform/lib/c4-model-shape.ts`, new).**
   - Export `plainObjectSize(v: unknown): number`, moved verbatim from `server/c4-render.ts`.
   - `c4-render.ts` deletes its local copy and imports this one at its 3 call sites. Read and write sides then share one definition by construction.
   - The module is pure (no imports) and client-safe, like `lib/c4-constants.ts`.
2. **Route (`apps/web-platform/app/api/kb/c4/project/route.ts`).**
   - Add a module-level, **non-exported** `const ZERO_VIEW_DIAGNOSTIC` with this final copy:
     > "This diagram has no views to draw because its saved layout is incomplete. Your diagram source is fine. To fix it, ask the Concierge to add a comment to this diagram's source, then reload the page."
   - Why each clause (CPO, CMO, DHH, UX and Step 4.5 findings, reconciled):
     - **"its saved layout is incomplete"** is true whoever wrote the model. DHH P1: "our renderer saved it incorrectly" is false for a model committed from a tenant's own likec4 run in a container without graphviz, which is the same `--use-dot` failure. It also avoids "renderer" jargon (CMO).
     - **"Your diagram source is fine."** The elements exist, so the source parsed. ADR-050 measured that a successful layout always emits at least `index`, even for a source with no `views {}` block, so zero views is a layout failure and never a source error. This is the CPO's non-blaming condition.
     - **"ask the Concierge to add a comment to this diagram's source".**
       - The user Save is gated OFF by `c4-edit` for all roles.
       - `edit_c4_diagram` shares `c4-visualizer` with the diagram itself, so every viewer on the default Claude Code engine has it. The tool is built only in `server/cc-dispatcher.ts`, and the Codex engine path (`codex-engine` flag, default OFF) has no C4 tool. The copy therefore assumes the default engine (DC-3).
       - Only a `.c4` write re-renders; a `.md` write does not. A comment is a harmless `.c4` edit (UX finding 3).
       - The re-render refuses zero views, so it cannot commit another zero-view model.
     - **"then reload the page".** Nothing reloads the workspace after a Concierge write until #8739 ships (UX finding 2). Ship comments on #8739 so the clause is removed with it.
   - The diagnostic is **permanent**, not #8740-scoped (DHH P1-3). Zero-view models written outside the server renderer can still appear.
   - After the existing `viewIds` derivation, which is **unchanged** (simplicity review):
     - `elementCount = plainObjectSize((dump as { elements?: unknown }).elements)`.
     - When `elementCount > 0 && viewIds.length === 0`:
       - `diagnostics = [{ message: ZERO_VIEW_DIAGNOSTIC, line: 0, sourceFsPath: C4_MODEL_JSON }]`;
       - emit the item 4 warning.
     - Otherwise `diagnostics = []`.
   - The 200 body uses `diagnostics` in place of the literal `[]`. The check runs only on the 200 path. The 404, 413, 502 and 503 arms are untouched.
   - Both owner surfaces show the diagnostic: the workspace (`c4-workspace.tsx`) and the inline embed (`c4-diagram.tsx`). Both call this route and pass `diagnostics` through unchanged. The copy works on both, because it names the diagram's source, not the page.
3. **Strip (`apps/web-platform/components/kb/c4-diagnostics.tsx`).**
   - Render the `line {d.line}:` prefix only when `d.line > 0`.
   - Add a comment at that line: `line <= 0` is **reserved** for model-level diagnostics that have no source line. A second producer or reader of the sentinel must move to a `kind` field instead.
   - Consumer census for the sentinel: `grep -rn "d\.line\|\.line\b" apps/web-platform/components/kb` finds one reader, `c4-diagnostics.tsx`. The other hit, `search-overlay.tsx`, is unrelated. No gutter, `line - 1` arithmetic, sort or jump-to-line code reads a `Diagnostic`.
   - Same element, same classes, same header logic: a copy-only change (see Domain Review).
4. **Observability.**
   - Call ``mirrorWarnWithDebounce(null, ctx, `${activeWorkspaceId}:${requestedDir}`, "c4-project-read:zero-view-model")``, where `ctx` is:
     - `feature: "c4-project-read"`;
     - `op: "zero-view-model"`;
     - `message: "c4 project read: committed model has elements but no views"`;
     - `tags: { detail_class: "zero-views" }`;
     - `extra: { ...userLog, dir: requestedDir, elementCount }`.
   - `err = null` keeps the tags (#8629). The fixed message gives one Sentry issue.
   - The dedup key is an in-process token that is never emitted. `userLog` is already hashed.
   - Add one line to the errorClass registry doc comment in `server/observability.ts`: `c4-project-read:zero-view-model`. It is permanent: after #8740 it is the read-side regression canary for ADR-050's zero-view write gate (CTO finding 5).
5. **Follow-through probe (`scripts/followthroughs/c4-zero-view-model-8740.sh` and `.test.sh`).** Its job is the **automated close** of #8740. The alert on first load is Sentry's first-seen email, not the probe.
   - **Template:** copy `reconcile-ff-only-sentry-4977.sh`:
     - the org-level `/api/0/organizations/jikigai-eu/events/` endpoint with explicit `field=` projections (the project endpoint ignores tag syntax, per `scripts/sentry-issue.sh`'s header);
     - `SENTRY_ACTIONS_RO_TOKEN` only;
     - the xtrace refusal block;
     - `if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]`, never `${VAR:?}`.
   - **Do not copy the template's exit contract.** Use the codes below. The template's contract predates the sweeper's word map.
   - **Checks, in this order:**
     1. **Signal.** Query `feature:c4-project-read op:zero-view-model environment:production` with `statsPeriod=14d&per_page=100&sort=-timestamp&field=timestamp`. If there is at least one event, **exit 1 (FAIL)** whatever the liveness checks would say, because a signal event itself proves the sink is live. Print the count (`>=100` when the page is full) and the newest timestamp, never the extras.
     2. **The fix is deployed** (positive control that the pre-change artifact cannot produce; followthrough convention, #7220):
        - `curl -sS -m 10 https://app.soleur.ai/health` and read `build_sha`. The endpoint is public; measured 2026-09-25, it returns `{"status":"ok","version":…,"build_sha":…}`.
        - Resolve the introducing commit with `git log --diff-filter=A --format=%H -1 -- scripts/followthroughs/c4-zero-view-model-8740.sh`. The sweeper checks out with `fetch-depth: 0`.
        - Require `git merge-base --is-ancestor "$INTRO" "$build_sha"`. If it fails, **exit 2 (NOT YET)**: production has not yet shipped the fix.
     3. **The sink is live.** Query `event_type:server-startup environment:production` over the same 14 days. If there is none, **exit 3 (CANNOT ESTABLISH)**.
     4. Otherwise, **exit 0 (PASS)**. The sweeper closes #8740.
   - **Also exit 3 (CANNOT ESTABLISH)** when the token is unset, on any non-200 response, or on an unparseable body. The probe cannot measure in those cases, and the sweeper renders 2 as "NOT YET", which would mislead. `lint-followthrough-varq-ban.sh` bans only the `${VAR:?}` form, not this code; confirm by running it.
   - **Header** must state:
     - the exit contract and the check order;
     - that the /health check proves the fix is live *now*, and liveness proves the sink was live at one restart in the window. That is enough at the daily deploy cadence;
     - that on FAIL, after choosing (b) or (c), removing the directive stops the daily sweeper comment, and re-adding it with a new `earliest=` re-arms it;
     - a `RETIREMENT:` line in order: remove the directive from #8740, then delete the script and its test, then remove the `scripts/test-all.sh` row.
   - **Executable bit.** `chmod +x` both new scripts and commit the mode (`git update-index --chmod=+x`). The sweeper refuses a non-executable probe (`sweep-followthroughs.sh`: "not executable — leaving issue open"), and no hook checks this on an issue *edit*.
   - **Test (`.test.sh`).** Stub `curl` and `git` on `PATH`. The `curl` stub routes on the URL: the /health host, versus each Sentry query by its encoded `query=`. Rows:
     - signal 0, fix deployed, liveness present → 0;
     - signal 1 → 1;
     - signal 1, liveness absent → 1 (signal wins);
     - signal 0, fix not deployed (`merge-base` returns 1) → 2;
     - signal 0, fix deployed, liveness absent → 3 (the vacuous-PASS guard);
     - HTTP 500 → 3;
     - token unset → 3;
     - both Sentry URLs contain `environment%3Aproduction`;
     - `apps/web-platform/app/api/kb/c4/project/route.ts` contains the exact `op: "zero-view-model"` and `feature: "c4-project-read"` literals the probe queries (drift guard).
   - Register the test in `scripts/test-all.sh` beside the other `scripts/followthroughs/*.test.sh` rows.

### Phase 2: Verify

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-project-route.test.ts test/c4-shared.test.tsx test/c4-render.test.ts test/c4-render-boundary.test.ts test/c4-workspace.test.tsx test/c4-diagram.test.tsx`.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- `bash scripts/followthroughs/c4-zero-view-model-8740.test.sh` and `bash scripts/lint-followthrough-varq-ban.sh`.

### Phase 3: Ship-time issue hygiene

- PR body: `Ref #8740` and a one-paragraph Re-render Decision summary. No closing keyword in the title or body.
- After the deploy, edit #8740's body:
  - append the follow-through directive, unfenced at column 0 (see Follow-Through Enrollment);
  - add the `follow-through` label, which exists.
- Post one comment on #8740 with:
  - what shipped;
  - options (a), (b) and (c);
  - the close rule;
  - how to stop the daily comments on FAIL.
- Post one comment on #8739: when it ships, drop "then reload the page" from the `ZERO_VIEW_DIAGNOSTIC` copy in `app/api/kb/c4/project/route.ts` and from its pinned test.

## Follow-Through Enrollment

CPO condition 5 makes #8740's close time-gated and evidence-based. Plan Phase 2.9.1 requires that close to be automated.

- **PASS (the sweeper closes #8740).** The production Sentry sink was live, and there were 0 production `op:zero-view-model` events in the trailing 14 days. Either the tenant never loaded the diagram (not affected in practice), or an edit re-rendered it.
- **Why the window is post-deploy.** `earliest=` is deploy + 14 days.
- **FAIL (the sweeper comments; #8740 stays open, or reopens if closed within 14 days).** The tenant is still loading a zero-view model.
- **Census arm.** A census re-run showing 0 zero-view models also closes #8740 by hand.
- **Directive.** Paste this verbatim into #8740's body at ship, unfenced and starting at column 0. The HTML-comment wrapper is what the sweeper parses; bullets enrol nothing. It is fenced here only so it renders:

  ```html
  <!-- soleur:followthrough
    script=scripts/followthroughs/c4-zero-view-model-8740.sh
    earliest=<deploy + 14 days, ISO-8601 UTC, e.g. 2026-10-10T18:00:00Z>
    secrets=SENTRY_ACTIONS_RO_TOKEN
  -->
  ```

- **Verify the enrolment.** Nothing checks a directive added by an issue *edit* (`follow-through-directive-gate.sh` fires only on `gh issue create`). After the edit:
  - run `gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true`;
  - confirm that its log names issue #8740, either the `earliest` skip or a `DRY_RUN` line.
- **New secrets.** None. `SENTRY_ACTIONS_RO_TOKEN` is already wired in `.github/workflows/scheduled-followthrough-sweeper.yml`.

## Files to Edit

- `apps/web-platform/app/api/kb/c4/project/route.ts`: zero-view detection, diagnostic, debounced warning.
- `apps/web-platform/server/c4-render.ts`: import `plainObjectSize` from `@/lib/c4-model-shape`, delete the local copy.
- `apps/web-platform/components/kb/c4-diagnostics.tsx`: omit the `line N:` prefix when `line <= 0`, plus the reservation comment.
- `apps/web-platform/server/observability.ts`: one errorClass registry doc-comment line.
- `apps/web-platform/test/c4-project-route.test.ts`: new rows. Add a `mockMirrorWarnWithDebounce` spy to the hoisted mocks and to the observability mock.
- `apps/web-platform/test/c4-shared.test.tsx`: strip rows.
- `scripts/test-all.sh`: one `run_suite` row.

## Files to Create

- `apps/web-platform/lib/c4-model-shape.ts`: the shared `plainObjectSize`.
- `scripts/followthroughs/c4-zero-view-model-8740.sh`: the probe.
- `scripts/followthroughs/c4-zero-view-model-8740.test.sh`: the probe's test.
- `knowledge-base/project/specs/feat-one-shot-8740-c4-zero-view-diagnostic/tasks.md`
- `knowledge-base/project/specs/feat-one-shot-8740-c4-zero-view-diagnostic/decision-challenges.md`

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` (81 issues) matched no body containing any of:

- `app/api/kb/c4/project/route.ts`
- `components/kb/c4-diagnostics.tsx`
- `c4-project-route.test`
- `c4-diagnostics`
- `c4-shared.tsx`
- `kb/c4/project`

## Non-Goals

- **Re-rendering the affected repository.** See Re-render Decision.
- **A diagnostic on the public shared route.** Recipients cannot act on it, and the route deliberately omits diagnostics.
- **Reloading the workspace after a Concierge edit.** That is #8739, the next queue item. Until then the copy tells the user to reload.
- **Suppressing the canvas's "View `index` not found in the model." line.** The strip's "no views to draw" explains it, and hiding it is a `C4Canvas` behaviour change.
- **Making the Concierge detect a zero-view model itself.** The Concierge does not read `/project`. That belongs with #8739's chat-to-workspace wiring.
- **An amber strip for this state.** It needs a new styled element and a wireframe (DC-4).
- **A JSON `null` or array model.** It already throws at the existing `views` read and returns a loud 503 with a Sentry report. That is not the #8740 state.
- **Items after #8739 in the queue:** #8752 and the render-slot residual.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Detect client-side in `C4Canvas` | The issue names the `/project` route. The server check is testable at the route boundary and feeds the Sentry signal (P3). |
| New `modelDiagnostic` field and an amber strip line | A new field, a new element and a real UI change, for one message the existing channel already carries. |
| `line: 1`, no component change | "line 1:" points at an unrelated source line. |
| Widen `Diagnostic.line` to optional | A type widening across the client boundary, with the same visible result as the sentinel. |
| Undebounced `warnSilentFallback` per GET | One Sentry event per page load. |
| Re-render from the route on read | A GET that writes to a tenant repository, with no ack. |
| Keep a local copy of `plainObjectSize` in the route | It duplicates the write-side gate's semantics by comment rather than by construction (DHH P2-4). |
| Probe owns FAIL alerting | Sentry's first-seen email already alerts on the first load. The probe owns the close. |

## User-Brand Impact

- **If this lands broken, the user experiences:** one of two things.
  - A false positive: a red "Diagram warnings" strip says the diagram has no views, on a diagram that renders fine.
  - A false negative: the page stays as it is today, with "View `index` not found in the model." and no explanation.
  - The probe could also close #8740 on a vacuous zero count, which the liveness and environment checks guard against.
- **If this leaks, the user's data is exposed via:** nothing new. The diagnostic text is a static constant. The Sentry warning carries `userIdHash`, the KB-relative `dir` (already sent by this route's other reports) and an integer.
- **Brand-survival threshold:** `none`.
- `threshold: none, reason: the change adds a static, read-only message to an existing owner-scoped GET response and one debounced warning; it writes nothing, widens no access, and emits no tenant content.`

## Observability

```yaml
liveness_signal:
  what: "Sentry warning issue 'c4 project read: committed model has elements but no views' (feature=c4-project-read, op=zero-view-model, detail_class=zero-views), at most once per workspace+dir per 5 minutes per process while a zero-view model is read; permanent read-side canary for ADR-050's zero-view write gate"
  cadence: "on read of a zero-view model; debounced 5 minutes per workspace+dir"
  alert_target: "Sentry-default first-seen route -> operator email (new issue); follow-through sweeper comment/close on #8740"
  configured_in: "apps/web-platform/app/api/kb/c4/project/route.ts (GET) and scripts/followthroughs/c4-zero-view-model-8740.sh"
error_reporting:
  destination: "Sentry web-platform project via warnSilentFallback(null, ...) -> captureMessage level=warning with tags preserved; DSN from the container env"
  fail_loud: "Sentry warning 'c4 project read: committed model has elements but no views' (feature=c4-project-read op=zero-view-model); pino warn line with the same message"
failure_modes:
  - mode: "false positive: diagnostic on a model that has views"
    detection: "route rows T2/T5 pre-merge; in production, distinct-user growth on the op=zero-view-model Sentry issue (layer 5) beyond the one census repository"
    alert_route: "Sentry-default first-seen route -> operator email"
  - mode: "false negative: a zero-view model served with no diagnostic"
    detection: "route rows T1/T4 pre-merge; post-merge, a census re-run (GET-only, method on #8740) reports a zero-view model while Sentry shows no op=zero-view-model event after that tenant's load"
    alert_route: "soleur:postmerge read of the Sentry issue; #8740 stays open"
  - mode: "follow-through closes #8740 vacuously (sink dead, dev-only events, or the route's op slug renamed)"
    detection: "probe exits 2 unless https://app.soleur.ai/health build_sha descends from the probe's introducing commit (fix live), exits 3 without an environment:production server-startup event in the window; both Sentry queries pin environment:production; its .test.sh greps route.ts for the exact feature/op literals it queries"
    alert_route: "sweeper NOT YET / CANNOT ESTABLISH comment on #8740"
  - mode: "new code throws on an odd model shape, turning a 200 into a 503"
    detection: "existing reportSilentFallback op=github-read-failed on the route's outer catch (layer 5); route row T5 pre-merge"
    alert_route: "Sentry-default first-seen route -> operator email"
logs:
  where: "container stdout (pino JSON) -> journald -> Vector (apps/web-platform/infra/vector.toml app_container_warn_filter: WARN+) -> Better Stack; Sentry for the warning event"
  retention: "Better Stack source retention for the web-platform source; Sentry event retention for the warning issue"
discoverability_test:
  command: "grep -c -e 'op: \"zero-view-model\"' apps/web-platform/app/api/kb/c4/project/route.ts"
  expected_output: "1"
```

The discoverability probe checks that the single emitter of the op slug, which is the Sentry search key, exists. It declares no `credentials_required`, so the preflight `BASELINE_DECLARED_PROBES` ratchet does not move. The production Sentry read belongs to `soleur:postmerge` and to the follow-through probe.

## Domain Review

**Domains relevant:** Product

The Engineering, Legal, Marketing, Operations, Sales, Finance and Support assessment questions do not match: this is a bug fix on an existing surface. Contacting the tenant through support is recorded as operator option (c).

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo, soleur:product:design:ux-design-lead (plan-review named panel), soleur:marketing:cmo (plan-review named panel)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface): copy-only exemption, see below

#### Findings

**CPO: approve with conditions.** All six conditions are applied.

1. Copy replaced and the Save clause dropped. The final wording was further reconciled with the DHH, CMO and UX findings; see Phase 1 item 2.
2. The unverified "re-render this diagram" wording was replaced with a concrete `.c4` edit.
3. S1 pins "Diagram warnings" and the absence of "Diagram has errors".
4. The exemption is kept, with its fallback.
5. The 14-day Sentry-evidence close is automated (Follow-Through Enrollment).
6. `Ref #8740`, and the choices are persisted (DC-1).

The amber colour note is DC-4.

**UX lead (plan-review): exemption agreed.**

- The missing reload loop (#8739) was fixed in the copy.
- The concrete `.c4` comment edit was adopted.
- The embed surface is declared in scope.
- The sentinel reservation comment was added.
- The dead-end "fix the source in the Code view" header for `hasModel=false` predates this PR and this path does not reach it. It is out of scope and noted for the `c4-edit` rollout (DC-3).
- The suggested PR screenshot of the zero-view workspace at 35% width is attached at QA.

**CMO (plan-review):**

- Adopted: drop "renderer" jargon; separate the saved layout from the source; make the action sentence concrete and active.
- Adjusted: "an earlier version of Soleur saved its layout" became "its saved layout is incomplete", per DHH's correctness point.

**Step 4.5 advisor consult:**

- Adopted: the sentinel consumer census, dropping the Save clause, and citing the Concierge path.
- Resolved differently: the hedge on the cause. The copy now asserts no cause at all, which satisfies both the advisor and the CPO.

**GDPR gate (Phase 2.7).** This is not legal review. The findings are heuristic; consult `soleur:legal:clo` and `soleur:legal:legal-compliance-auditor` before merging anything load-bearing.

- 0 findings. There is no schema, vendor or Art. 9 surface.
- The response adds a static string only (AP-01/AP-05).
- The ownership check is unchanged (AP-02).
- The new emit carries the same data kinds this route already sends to processors recorded in `compliance-posture.md`.

**Wireframe gate (`wg-ui-feature-requires-pen-wireframe`): exempt, copy-only.**

- The only UI change drops the `line N:` text prefix inside the existing `<li>` of the existing red strip. There is no new element, class, interaction or layout.
- `ui-surface-terms.md` §Excluded covers this.
- Precedent: the #8732 plan made the same exemption for this component.
- Surface design of record: `knowledge-base/product/design/kb-viewer/c4-viewer-no-code-panel-gated-edit.pen`, the C4 workspace with `c4-edit` OFF, which is this tenant's state.
- Named surface shipped without a new wireframe: the `C4Diagnostics` list-item text.
- The exemption lapses if a later change adds an element, colour or position for this message. `soleur:product:design:ux-design-lead` then produces a `c4-zero-view-diagnostic` Pencil file in the `kb-viewer` design folder first.

## Test Scenarios

Route (`test/c4-project-route.test.ts`). The fixtures are synthetic and built with `JSON.stringify`.

- **T1:** Given `{ elements: { a: {id:"a"}, b: {id:"b"} }, views: {} }`, then:
  - status 200 and `viewIds` `[]`;
  - `diagnostics` = `[{ message: <exact copy literal>, line: 0, sourceFsPath: "model.likec4.json" }]`;
  - `mockMirrorWarnWithDebounce` is called once, with `err === null`, `feature: "c4-project-read"`, `op: "zero-view-model"`, key `"ws-1:engineering/architecture/diagrams"` and errorClass `"c4-project-read:zero-view-model"`.
- **T2:** Elements plus `views: { index: {...} }` → `diagnostics` `[]`, no warn call.
- **T3:** `{ elements: {}, views: {} }` → `diagnostics` `[]`, no warn call (empty model, no false diagnostic).
- **T4 (`it.each`, same plain-object branch):**
  - elements with no `views` key → diagnostic;
  - elements with `views: []` → diagnostic;
  - `elements: ["x"]` with `views: {}` → no diagnostic;
  - `elements: "xy"` with `views: {}` → no diagnostic.
  - All four return 200.

Strip (`test/c4-shared.test.tsx`).

- **S1:** `diagnostics=[{ message: "M", line: 0, sourceFsPath: "model.likec4.json" }]`, `hasModel` →
  - "Diagram warnings" is shown;
  - `queryByText(/Diagram has errors/)` is null;
  - the list item's text is exactly `M`;
  - `queryByText(/line 0/)` is null.
- **S2:** `line: 3` → the item's text is exactly `line 3: bad ref`.

Follow-through probe (`scripts/followthroughs/c4-zero-view-model-8740.test.sh`): the nine rows in Phase 1 item 5.

Considered and declined (Kieran P1-2): a `useC4Project` hook row asserting that `diagnostics` pass through unchanged. The hook's `json.diagnostics ?? []` normalisation is not touched by this diff, and the route rows pin the payload the hook receives.

Regression: the existing `c4-render.test.ts` and `c4-render-boundary.test.ts` suites stay green after `plainObjectSize` moves.

## Plan Review Disposition

The reviewers were the eng panel (DHH, Kieran, code-simplicity) and the named panel (CPO in Phase 2.5; CTO, UX lead and CMO at review). Mechanical findings were applied. Taste findings are in `decision-challenges.md`.

| Source | Finding | Disposition |
|---|---|---|
| DHH P1 | The copy asserts a cause the route cannot know | Applied: "its saved layout is incomplete" |
| DHH P1 | Cut the probe | Declined. Plan Phase 2.9.1 requires the automated close, and CTO and code-simplicity both kept it, trimmed. Its FAIL-alert role is dropped in favour of Sentry's first-seen email. |
| DHH P1 | Nothing retires the diagnostic | Applied: the diagnostic and the warning are declared permanent (the read-side canary) |
| DHH P2 | Share `plainObjectSize` | Applied: new `lib/c4-model-shape.ts` |
| DHH / simplicity | Cut T6, T7, S3, the mutation ritual, and the registry and export ACs | Applied |
| DHH P2 | Make (c) the default | Taste: DC-1. The CPO's (a) is kept, with evidence-based escalation to (c) |
| Simplicity | Leave the `viewIds` derivation unchanged; fold T4/T5; word AC3 around the spy | Applied |
| Simplicity / CTO | Pin `environment:production` | Applied |
| CTO 1 / Kieran 6 | The template's exit codes mislabel sweeper comments | Applied: 0/1/2/3 map |
| CTO 3 / 4 | Daily FAIL comments; retirement order | Applied (probe header) |
| CTO 5 | Warning permanence | Applied |
| CTO 6 / Kieran 9 | Slug drift between probe and route | Applied: `.test.sh` drift row, plus a single-occurrence sharp edge |
| Kieran P1-1 | The liveness control is producible by the old artifact | Applied: /health `build_sha` ancestry check (exit 2) |
| Kieran P1-2 | S3 is unwritable against the mock | S3 cut; the hook row is declined (unchanged code) |
| Kieran P1-3 | Executable bit | Applied, plus AC6 |
| Kieran P1-4 | Directive wrapper and edit-time verification | Applied: verbatim block plus a dry-run check |
| Kieran P1-5 | The Codex engine has no C4 tool | Applied as a qualification, plus DC-3 |
| Kieran P2-7 | Check order, counting, sorting and stub routing | Applied |
| Kieran P2-10 | The spy is mandatory | Applied |
| UX 2 | No reload after a Concierge edit (#8739) | Applied: "then reload the page", plus a comment on #8739 |
| UX 3 | Concrete `.c4` edit | Applied: "add a comment to this diagram's source" |
| UX 4 | Embed surface | Applied: declared in scope. The extra `c4-diagram` row is declined, because it is an unchanged pass-through |
| UX 5 / CPO | Amber strip; dead-end `hasModel=false` header | DC-4 / noted for the `c4-edit` rollout |
| CMO | Jargon, the layout-vs-source split, an active action sentence | Applied |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled here.
- The route file may export only HTTP handlers. `ZERO_VIEW_DIAGNOSTIC` stays non-exported, and the tests pin the copy literally, as `c4-shared.test.tsx` already does for `SUPERSEDED`.
- The observability mock in `c4-project-route.test.ts` spreads `importActual`, so `mirrorWarnWithDebounce` **must** be an explicit spy. This is not optional.
  - Without the spy, the real debounce map dedupes a second test in the same worker.
  - `@sentry/nextjs` is mocked with only `captureException`, so the real `warnSilentFallback` would skip `captureMessage` silently. T2/T3's "not called" assertions would then prove nothing.
- The literal `op: "zero-view-model"` must appear exactly once in `route.ts`. The `discoverability_test` expects `1`, and the probe's drift row reads it, so do not quote it in a comment. The registry comment in `observability.ts` names only the errorClass.
- `mirrorWarnWithDebounce`'s argument order is `(err, ctx, key, errorClass)`. Assert "called once per zero-view request" on the spy, never a Sentry event count.
- Put no closing keyword for #8740 in the PR title or body.
- The probe uses `SENTRY_ACTIONS_RO_TOKEN` and never names the retired Sentry credential anywhere under `scripts/followthroughs/` (`lint-followthrough-varq-ban.sh` rule 2).
- A zero-event PASS is green-from-absence. The liveness query, the `environment:production` pins and the route-literal drift row are load-bearing, and each has a `.test.sh` row. Do not cut them as redundant.
- Do not copy the template's exit contract. The sweeper renders `2` as "NOT YET" and `3` as "CANNOT ESTABLISH", so use the codes in Phase 1 item 5.
- Paste the directive into #8740 unfenced, at column 0. A fenced directive enrols nothing.
- `discoverability_test.command` contains no `|`, `;`, `&`, `<`, `>`, `$` or backtick, which preflight Check 10 requires.
- Run `npx markdownlint-cli2` on this plan and `tasks.md` before committing.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `GET /api/kb/c4/project` returns exactly one diagnostic (`line: 0`, `sourceFsPath: "model.likec4.json"`, the Phase 1 copy) when `elements` is a non-empty plain object and `views` is absent, empty or not a plain object (T1, T4).
- [ ] AC2: It returns `diagnostics: []` for a model with at least one view, and for one with no elements or non-object `elements` (T2, T3, T4).
- [ ] AC3: `mirrorWarnWithDebounce` is called once per zero-view request with `err === null`, `feature: "c4-project-read"`, `op: "zero-view-model"` and errorClass `"c4-project-read:zero-view-model"`, and never on the no-diagnostic paths (T1-T3).
- [ ] AC4: `C4Diagnostics` omits the `line N:` prefix when `line <= 0`, keeps `line N: msg` for positive lines, and shows "Diagram warnings" (never "Diagram has errors") for a model-level diagnostic (S1, S2).
- [ ] AC5: `plainObjectSize` is defined once: `git grep -n "function plainObjectSize" -- apps/web-platform` prints exactly one line, in `lib/c4-model-shape.ts`. `c4-render.test.ts` and `c4-render-boundary.test.ts` pass.
- [ ] AC6: `bash scripts/followthroughs/c4-zero-view-model-8740.test.sh` passes all nine rows in Phase 1 item 5, and is registered in `scripts/test-all.sh`. `bash scripts/lint-followthrough-varq-ban.sh` passes. `test -x` succeeds on both new scripts, and `git ls-files -s` shows mode `100755` for both.
- [ ] AC7: The affected vitest suites pass (Phase 2), and `tsc --noEmit` is clean.
- [ ] AC8: The PR body says `Ref #8740`, and neither the title nor the body carries a closing keyword for #8740.
- [ ] AC9: No write to any tenant repository happens in this PR's lifecycle.

### Post-merge (automated by ship and the sweeper)

- [ ] AC10: #8740 is OPEN after merge and carries:
  - the unfenced `<!-- soleur:followthrough … -->` directive (`earliest` = deploy + 14 days, `secrets=SENTRY_ACTIONS_RO_TOKEN`), with a sweeper `dry_run=true` log that names #8740;
  - the `follow-through` label;
  - a disposition comment naming options (a), (b) and (c), the close rule, and how to stop FAIL comments.
- [ ] AC11: #8739 carries a comment naming the "then reload the page" clause to remove when it ships.
