---
title: "fix(c4): explain a zero-view model on GET /api/kb/c4/project instead of an unexplained empty canvas"
type: fix
date: 2026-09-25
deepened: 2026-09-25
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

## Enhancement Summary

**Deepened on:** 2026-09-25.

**Inputs:**

- Plan-review panel: DHH, Kieran, code-simplicity, CTO, UX lead, CMO. Dispositions are in the Plan Review Disposition table.
- Deepen round: security-sentinel, observability-coverage-reviewer, test-design-reviewer, architecture-strategist, agent-native-reviewer, and a verify-the-negative and attribution pass. Dispositions are in the Deepen Findings Disposition table.

**Key changes from the reviewed plan:**

1. **Pre-existing `dir` traversal fixed in the same route (security, folded in).**
   - `?dir=%252e%252e/src` passes today's guard, because `searchParams` decodes the value once to `%2e%2e`. The URL parser then resolves `%2e%2e` as `..`.
   - The result: any active-workspace member can read `.c4`, `README.md` and `model.likec4.json` from any folder of the workspace repo, not only the KB.
   - The new warning's dedup key and `extra` would also have carried this uncanonical value, so the fix is folded in: a per-segment allowlist, plus the dedup key built from GitHub's canonical `modelEntry.path`.
2. **No Sentry email fires for a new warning-level issue.** The only unfiltered issue-stream rule triggers on `new_high_priority_issue`. The plan no longer claims a first-seen email. The follow-through sweeper's FAIL comment is the push signal for option (c).
3. **Concierge parity (agent-native).**
   - One sentence is added to `C4_PROMPT_ADDENDUM`. It tells the Concierge that a model with elements and no views has an incomplete layout, not a broken source; that it should not add `views` blocks; and that it should write a comment to a `.c4` file, because an `.md` write does not re-render.
   - The route names the Concierge fix only for the canonical diagrams folder, the only folder `edit_c4_diagram` can write.
4. **A second live producer of zero-view models found and filed as #8861.** The plugin writers `render-c4-model.sh` and `generate-c4-from-components.ts` still run `likec4 export json` with no `--no-use-dot` and no views gate. As a result:
   - the read-side warning is a detector for any writer, not a canary for ADR-050's gate alone;
   - an ADR-050 addendum records the gap.
5. **The follow-through probe was hardened.**
   - It validates the untrusted `/health` `build_sha` (it can be the literal `dev`) and the introducing commit before calling `git merge-base`.
   - Exit codes: rc 1 → 2 (NOT YET), rc ≥128 or an unparseable/non-200 response → 3 (CANNOT ESTABLISH).
   - Every exit-3 row asserts its reason line.
   - The `curl` and `git` stubs record their argv and fail loudly on anything they do not route.
   - The drift row reads the probe's own constants.
   - Output rules suit a public repository.
6. **Shared model shape.** `lib/c4-model-shape.ts` exports `c4ModelCounts`, which the render gates and the route both use, plus the `Diagnostic` type and a `MODEL_LEVEL_LINE` constant. Producer and consumer are now checked against one type.

**New considerations discovered:**

- Share-link loads of a zero-view model are not counted (Non-Goals). "No events" therefore means "no owner or member loads".
- Sentry signals can be forged with the semi-public DSN. That can only change #8740's state. The residual risk is recorded in the probe header.
- #8739's fix must drop "then reload the page" in **three** places: the two route copies and the addendum sentence.

## Overview

A committed `model.likec4.json` that holds elements but no views renders in the C4 workspace as
"View `index` not found in the model.", with nothing saying why. The server's re-render committed
such models before #8732 (ee9f2c9, merged 2026-09-24) pinned wasm layout (`--no-use-dot`) and
refused zero-view exports. The plugin writers can still commit them (#8861).

The 2026-09-25 read-only census (posted on #8740) found exactly one such model: an external tenant
repository, 40 elements, 0 views, opaque id `84dd700449ea`. The model sits in the canonical folder
`knowledge-base/engineering/architecture/diagrams/`, and no save has re-rendered it since the fix
deployed.

This plan makes the read route `GET /api/kb/c4/project`, which is scoped to active-workspace
members, return one diagnostic when the model it reads has elements but no views. The existing
diagnostics strip above the canvas then says what happened and how to fix it.

The plan also:

- gives the Concierge the same understanding;
- closes a pre-existing `dir` traversal in the same route;
- records the decision **not** to write a re-render into the affected external repository (see Re-render Decision);
- automates #8740's evidence-based close.

## Research Reconciliation — Spec vs. Codebase

| Claim in the issue / brief | Reality on `origin/main` (d5a5887438) | Plan response |
|---|---|---|
| The tenant sees "a blank canvas". | Not blank. `C4Canvas` → `ViewCanvas` renders "View `<viewId>` not found in the model." when the view is absent (`components/kb/c4-shared.tsx`, `ViewCanvas`). The viewId comes from the markdown `likec4-view` block (`lib/c4-embed.ts` `parseLikeC4Embed`). | The diagnostic explains that line. The canvas is unchanged. |
| Suggested copy: "save the diagram to re-render it". | The user-direct Save (Code panel and `PUT /api/kb/c4/[...path]`) is behind `c4-edit` (`lib/c4-constants.ts` `C4_EDIT_FLAG`), default OFF for all roles. The Concierge's `edit_c4_diagram` (built in `server/c4-concierge-tools.ts` `buildC4ConciergeTools`, registered only by `server/cc-dispatcher.ts`) is the only live writer. Every `.c4` write re-renders (`server/c4-writer.ts` `writeC4Diagram` → `rerenderAndCommit`, no content-equality skip); a `.md` write does not. | The copy names a concrete `.c4` Concierge edit and drops "save" (Phase 1, item 3). |
| After a fix, the page updates. | Nothing reloads the workspace after a Concierge write. `useC4Project` refetches only when its endpoint changes (`dirPath` or `url`) or through `reload()`. The only `reload()` callers are the Code panel `onSaved` handlers in `c4-workspace.tsx` and `c4-diagram.tsx`, which `c4-edit` gates off. That wiring is open issue #8739. | The copy and the addendum tell the user to reload. Both clauses are removed when #8739 ships (ship comments on #8739). |
| The route has a diagnostics channel. | Yes, but it has never carried an entry. `diagnostics: []` is hard-coded in the 200 body. Every consumer passes it to `C4Diagnostics`, which prints `line {d.line}: {d.message}` under "Diagram warnings" (`hasModel={!!data.dump}` at both call sites). | Model-level entries use `MODEL_LEVEL_LINE = 0`, and the strip omits the `line N:` prefix when `line <= 0` (Phase 1, item 4). |
| The fix was deployed, so zero-view models are a legacy artefact. | Only the server writer is fixed. `plugins/soleur/scripts/render-c4-model.sh` and `generate-c4-from-components.ts` run `likec4 export json` with no `--no-use-dot` and no views gate (verified by grep). | Filed as #8861. The diagnostic is permanent and names no specific writer. |
| `dir` is a KB-relative folder. | The guard rejects the literal `..` only. `%252e%252e` decodes once to `%2e%2e`, and the GitHub URL parser resolves that as `..` (security-sentinel, verified in Node). | Per-segment allowlist, length cap, and per-segment `encodeURIComponent` (Phase 1, item 2). |
| The shared public link might need the diagnostic too. | `app/api/shared/[token]/c4/route.ts` returns only `{ dir, dump, viewIds }` (data minimisation). Its recipients cannot edit. | Out of scope (Non-Goals). |

## Research Insights

**Premise validation (Phase 0.6).**

- #8740 is OPEN (`type/bug`, `priority/p2-medium`, `domain/product`).
- #8696 and #8695 are CLOSED by PR #8732. ee9f2c9 is on `origin/main`.
- Census comment `issuecomment-5830485520` (2026-09-25):
  - 3 installations, 33 repos, 0 errors;
  - internal: 12 repos, 1 model, 0 zero-view;
  - external: 21 repos, 1 model, 1 zero-view.
- Production `/health` reports `build_sha` 6169164d7c. It descends from ee9f2c9, so the #8732 fix is live (measured 2026-09-25).
- Queue items #8739 and #8752 are OPEN. Neither is touched here.
- ADR-050's 2026-09-24 amendment refuses zero-view exports on the server writer. It rejects nothing about a read-side diagnostic.

**Property List (Phase 0.6b).**

- P1. When the committed model has at least one element and no views, the member's C4 page says so and names an action that fixes it. The Concierge understands the same state.
- P2. A model with views, or an empty model (no elements), shows no such message.
- P3. The operator can tell, without running the census, whether anyone still loads a zero-view model. This is the evidence for #8740's close.
- P4. Nothing is written to an external tenant repository without an explicit operator ack.

**Cut List (Phase 0.6b).**

- Server-triggered one-off re-render for the affected repo (P1/P4). Cut: it is an external-tenant write, which needs an operator ack.
- New "re-render without a source change" endpoint or Concierge tool (P1). Cut: a `.c4` comment write already re-renders.
- Committed census script, or a follow-through keyed on the census (P3). Cut: both need prd App credentials, and the Sentry-keyed follow-through covers P3.
- New `modelDiagnostic` response field, or a new banner element (P1). Cut: the existing `diagnostics` channel and strip carry it.
- New Sentry `sentry_alert` rule for `op:zero-view-model` (P3). Cut: it would be an IaC change (`issue-alerts.tf`, frequency dedup, op-contract test) for one tenant. The sweeper's FAIL comment is the push signal (see Observability).

**Relevant files.**

- `apps/web-platform/app/api/kb/c4/project/route.ts`: the GET handler. It holds the `dir` guard, the Contents listing (`modelEntry.path` is the canonical path), the `viewIds` derivation and `diagnostics: []`.
- `apps/web-platform/server/c4-render.ts`: module-private `plainObjectSize` (3 call sites) and the `empty_model` and `layout_failed`/`zero-views` gates.
- `apps/web-platform/components/kb/c4-diagnostics.tsx` and `c4-shared.tsx`: the strip and the `Diagnostic` type. The type is declared in a client component today.
- `apps/web-platform/server/c4-concierge-tools.ts`: `C4_PROMPT_ADDENDUM`, pinned by two tests:
  - `test/c4-concierge-copy.test.ts`: on both surfaces, exactly one `will update` and no `shortly`;
  - `test/c4-prompt-addendum-honesty.test.ts`: a list of banned phrases.
- `apps/web-platform/server/observability.ts`: `mirrorWarnWithDebounce(err, ctx, key, errorClass)` and the errorClass registry comment. `warnSilentFallback(null, …)` calls `captureMessage` at level warning with the tags, plus a pino `warn` line that passes Vector's `app_container_warn_filter` (level ≥ 40).
- `apps/web-platform/server/health.ts`: `/health` returns `build_sha: process.env.BUILD_SHA || "dev"`.
- `apps/web-platform/infra/sentry/issue-alerts.tf`: no rule matches `c4-project-read`. The unfiltered rule triggers on high-priority issues only.
- `scripts/sweep-followthroughs.sh` exit-code map: `0` close, `1` FAIL (and reopen within `CLOSED_LOOKBACK_DAYS=14`), `2` NOT YET, `3` CANNOT ESTABLISH, `5` ACTION REQUIRED, anything else TRANSIENT.
- `scripts/followthroughs/reconcile-ff-only-sentry-4977.sh`: the Sentry-query template. Do not copy its exit contract.
- `scripts/followthroughs/ccla-representative-icla-7922.sh`: precedent for SHA validation before git.
- `scripts/followthroughs/ship-merge-mergebase-verdict-8151.test.sh`: precedent for an instrument self-test.

**Institutional learnings applied.**

- `2026-09-24-sandboxing-a-render-child-with-bwrap-no-writable-host-bind.md` and the ADR-050 amendment. Zero views is a layout failure, never the user's source.
- `2026-05-13-mirror-with-debounce-vs-report-silent-fallback-for-high-cardinality-surfaces.md`. Use the debounced warn helper.
- #8629. Pass `err = null` so the tags survive, and use a fixed message.
- `2026-07-18-backlog-issue-with-merged-code-closes-on-deploy-gate-not-merge.md` and `2026-05-07-pr-title-closes-keyword-ignores-qualifiers-and-d4-silent-failure.md`. Say `Ref #8740`, never `Closes`.
- `integration-issues/2026-06-15-c4-read-from-github-source-of-truth-and-blobs-api-1mb-gotcha.md`. The route reads GitHub.
- `cq-test-fixtures-synthesized-only`, `cq-nextjs-route-files-http-only-exports`, `cq-regex-unicode-separators-escape-only` and `cq-assert-anchor-not-bare-token`.
- The follow-through convention (`knowledge-base/engineering/operations/runbooks/followthrough-convention.md`):
  - the positive control must be impossible for the old artifact (#7220);
  - require a liveness marker before a zero-count PASS;
  - use `SENTRY_ACTIONS_RO_TOKEN` only, with no `${VAR:?}`;
  - paste the directive unfenced;
  - list the `RETIREMENT:` order.

**Related issues.**

- #8732: the fix PR.
- #8696, #8695: closed.
- #8739: Concierge edit → workspace reload.
- #8752: untouched.
- #8629: Sentry tag drop.
- #8861: plugin writers, filed by this plan.

**Functional overlap (1.5b), community discovery (1.5), external research (1.6).** None, skipped and skipped. There is direct in-repo precedent for every piece.

## Re-render Decision

**Decision: this PR does not re-render, or write to, the affected external repository.**

- A re-render is a commit into a tenant repository the tenant did not ask for. Under `hr-menu-option-ack-not-prod-write-auth` it needs an explicit operator ack.
- After this PR, the canvas and the Concierge both explain the state and name the edit that fixes it.

**Operator choices** (persisted to `knowledge-base/project/specs/feat-one-shot-8740-c4-zero-view-diagnostic/decision-challenges.md`, DC-1):

- (a) **Default:** leave the repository alone. #8740 closes on evidence:
  - the follow-through sweeper closes it after 14 quiet days, once the fix is live; or
  - a census re-run shows 0 zero-view models.
- (b) Authorise one re-render: a single `.c4` write through the existing writer, with an explicit ack.
- (c) Contact the tenant through support. The CPO prefers (c) to (b).
  - The trigger to move from (a) to (c) is a sweeper FAIL comment on #8740: production zero-view loads in the window.
  - Sentry sends no email for this warning-level issue (see Observability).

**#8740 stays OPEN.** The PR body says `Ref #8740`.

## Implementation Phases

### Phase 1: Tests first (RED), then code (GREEN)

1. **Shared model shape (`apps/web-platform/lib/c4-model-shape.ts`, new; pure, no imports, client-safe).**
   - `export function c4ModelCounts(model: unknown): { elements: number; views: number }`. Use the plain-object semantics of today's `plainObjectSize`, which moves here as a private helper. A non-object `model` gives `{ elements: 0, views: 0 }`.
   - `export type Diagnostic = { message: string; line: number; sourceFsPath: string }`. It moves here from `components/kb/c4-shared.tsx`, which re-exports it, so every import site keeps working.
   - `export const MODEL_LEVEL_LINE = 0`: the reserved `line` value for a diagnostic that has no source line. `sourceFsPath` is then a bare filename.
   - `server/c4-render.ts` deletes `plainObjectSize` and uses `c4ModelCounts` in the `empty_model` and `layout_failed` gates, and in the boot self-probe's view count.
   - Placement notes:
     - Not `lib/c4-canonical.mjs`: it must stay byte-identical to the plugin copy (`c4-canonical-mirror.test.ts`).
     - Not `lib/c4-constants.ts`: that file holds constants only.
     - `c4-render-boundary.test.ts` needs no change.
2. **`dir` hardening (`route.ts`, pre-existing gap folded in).** Replace the substring guard with a single validation:
   - length ≤ 256;
   - reject any control character, and U+2028/U+2029, using the escape-only form `/[\x00-\x1f\x7f  ]/`;
   - split on `/`, and require every segment to match `/^[A-Za-z0-9_-][A-Za-z0-9._-]*$/`. That rejects empty, `.` and `..` segments, `%`, `?`, `#`, `\` and a leading `/`;
   - build `githubDir` by joining `encodeURIComponent(segment)` values after `knowledge-base/`.
   - A failure returns `400 Invalid dir`, as today.
3. **Route diagnostic (`route.ts`).**
   - Two module-level, **non-exported** copies:
     - `ZERO_VIEW_DIAGNOSTIC`, for `requestedDir === C4_DIAGRAMS_DIR`:
       > "This diagram has no views to draw because its saved layout is incomplete. Your diagram source is fine. To fix it, ask the Concierge to add a comment to this diagram's source, then reload the page."
     - `ZERO_VIEW_DIAGNOSTIC_OTHER_DIR`, for any other folder, which `edit_c4_diagram` cannot write:
       > "This diagram has no views to draw because its saved layout is incomplete. Your diagram source is fine. To fix it, re-run the diagram export for this folder in your repository, then reload the page."
   - Why the wording:
     - "saved layout is incomplete" is true whoever wrote the model, including the #8861 writers. It also avoids jargon (DHH, CMO).
     - "source is fine" holds because the elements parsed, and ADR-050 measured that a successful layout always emits at least `index` (CPO).
     - A `.c4` comment is the harmless edit that re-renders; a `.md` write does not (UX).
     - The reload clause is needed until #8739 ships (UX).
   - The Concierge clause assumes the default Claude Code engine. The `codex-engine` path, default OFF, has no C4 tool (DC-3).
   - After the existing `viewIds` derivation, which is unchanged:
     - `const counts = c4ModelCounts(dump)`.
     - When `counts.elements > 0 && counts.views === 0`:
       - `diagnostics = [{ message, line: MODEL_LEVEL_LINE, sourceFsPath: C4_MODEL_JSON }]`, typed `Diagnostic[]`;
       - emit the item 5 warning.
     - Otherwise `diagnostics = []`.
   - The check runs only on the 200 path. The 404, 413, 502 and 503 arms are untouched. The diagnostic is permanent: it detects a zero-view model from any writer.
   - Both member surfaces show it: the workspace (`c4-workspace.tsx`) and the inline embed (`c4-diagram.tsx`).
4. **Strip (`apps/web-platform/components/kb/c4-diagnostics.tsx`).**
   - Render the `line {d.line}:` prefix only when `d.line > MODEL_LEVEL_LINE`.
   - Add a comment: `line <= 0` is reserved for model-level diagnostics. A second producer or reader moves to a `kind` field instead.
   - Consumer census: the only `.line` reader in `components/kb` is `c4-diagnostics.tsx`. The other hit, `search-overlay.tsx`, is unrelated.
   - Same element, same classes, same header logic.
5. **Observability (`route.ts`, `server/observability.ts`).**
   - Call:

     ```ts
     mirrorWarnWithDebounce(
       null,
       {
         feature: "c4-project-read",
         op: "zero-view-model",
         message: "c4 project read: committed model has elements but no views",
         extra: { ...userLog, dir: requestedDir, modelPath: modelEntry.path, elementCount: counts.elements },
       },
       `${activeWorkspaceId}:${modelEntry.path}`,
       "c4-project-read:zero-view-model",
     );
     ```

   - Rationale:
     - The key uses GitHub's canonical `modelEntry.path`, so `./x`-style variants cannot bypass the debounce (security).
     - No `detail_class` tag: `feature` and `op` already distinguish it from the write-side `zero-views` class (architecture).
     - `err = null` keeps the tags (#8629).
   - The literal `op: "zero-view-model"` appears exactly once in `route.ts`.
   - Add one line to the errorClass registry comment: `c4-project-read:zero-view-model`, the permanent read-side zero-view detector for any writer (#8740, #8861).
6. **Concierge parity (`apps/web-platform/server/c4-concierge-tools.ts`).** Append one sentence to `C4_PROMPT_ADDENDUM` only (not the tool description):
   > "If the user reports a blank diagram or the page says the diagram has no views to draw, read `model.likec4.json` in that diagram's folder: a model with elements but an empty `views` means its saved layout is incomplete, not that the source is wrong, so do not add or change `views` blocks. Instead, after the user confirms, add a `//` comment line to one `.c4` file in that folder with this tool (saving the `.md` page does not re-render), then tell the user to reload the page."
   - Check the sentence against both copy suites before committing:
     - `c4-concierge-copy.test.ts` pins the `will update` count and forbids `shortly`;
     - `c4-prompt-addendum-honesty.test.ts` holds a list of banned phrases.
   - The proposed wording contains none of them.
7. **ADR-050 addendum** (`knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md`). Add a short "Addendum — 2026-09-25 (#8740)" paragraph with three points:
   - `GET /api/kb/c4/project` now detects a zero-view model on read, returns a model-level diagnostic, and emits a debounced Sentry warning (`feature=c4-project-read`, `op=zero-view-model`);
   - the 2026-09-24 "zero-view models refused" wording covers the server writer only; the plugin writers are #8861;
   - the census tenant and the follow-through.

   Put it on its own lines. Do not edit the test-pinned `Failure classes:` line (`c4-render-boundary.test.ts` pins it to `DETAIL_CLASSES`). No C4 model change is needed: `model.c4` already has `webapp -> sentry "Exceptions + debounced warns…"`, and there is no new element or edge.
8. **Follow-through probe (`scripts/followthroughs/c4-zero-view-model-8740.sh` and `.test.sh`).** Its job is the automated close of #8740, and its FAIL comment is the push signal for option (c).
   - **Sentry calls:** the org-level `/api/0/organizations/jikigai-eu/events/` endpoint with `field=` projections (the project endpoint ignores tag syntax, per `scripts/sentry-issue.sh`).
     - `SENTRY_ACTIONS_RO_TOKEN` only, sent as `-H @-` from a `printf` pipe, never on argv.
     - `curl --disable --noproxy '*' -m 20 -sS -w '\nHTTP_STATUS:%{http_code}'`.
     - Pin both queries to the web-platform project and `environment:production`.
   - **`/health` call:** `curl --disable --noproxy '*' --proto '=https' --max-redirs 0 -m 10 --max-filesize 65536 -sS -w '\nHTTP_STATUS:%{http_code}' https://app.soleur.ai/health`. Never send an `Authorization` header here.
   - Copy the template's xtrace refusal block verbatim. Check the token with `if [[ -z "${SENTRY_ACTIONS_RO_TOKEN:-}" ]]`.
   - **Checks, in this order.** Every exit prints one fixed reason line.
     1. **Token set?** If not, exit 3 (`CANNOT ESTABLISH: token unset`).
     2. **Signal.** Query `feature:c4-project-read op:zero-view-model environment:production`, `statsPeriod=14d&per_page=100&sort=-timestamp&field=timestamp`.
        - Non-200, or `.data | type != "array"` → exit 3 (`CANNOT ESTABLISH: signal query <status>`).
        - Count ≥ 1 → **exit 1**, whatever checks 3 and 4 would say. Print `FAIL: <N> production zero-view loads in 14d, newest <ts>` (`>=100` when the page is full).
     3. **Fix deployed** (a positive control the old artifact cannot produce, #7220):
        - Take `build_sha` from `/health`. Non-200, non-JSON, or not matching `^[0-9a-f]{40}$` (for example `dev`) → exit 3.
        - Take `INTRO` from `git log --diff-filter=A --format=%H -1 -- scripts/followthroughs/c4-zero-view-model-8740.sh`. If it does not match `^[0-9a-f]{40}$` → exit 3.
        - If `git cat-file -e "$build_sha^{commit}"` fails → exit 3.
        - Run `git merge-base --is-ancestor "$INTRO" "$build_sha"`: rc 0 continues; rc 1 → **exit 2** (`NOT YET: fix not live`); any other rc → exit 3.
     4. **Sink live.** Count `event_type:server-startup environment:production` over 14 days. Non-200 or non-array → 3. Zero → **exit 3** (`CANNOT ESTABLISH: no production server-startup in window`).
     5. Otherwise **exit 0**: `PASS: 0 production zero-view loads in 14d (proof by absence; fix live at <build_sha short>)`.
   - **Output rules (the repo is public):**
     - never print response bodies, `dir`, `modelPath`, `userIdHash` or `elementCount`;
     - on a non-200, print the status only;
     - print `build_sha` only after validation.
   - **Header** states:
     - the exit contract and check order;
     - that the /health check proves the fix is live now, and liveness proves the sink was live at one restart in the window;
     - how to stop the daily FAIL comments: after choosing (b) or (c), remove the directive; re-adding it with a new `earliest=` re-arms it;
     - the residual risk: both Sentry signals can be forged with the semi-public DSN, which affects only #8740's state;
     - `RETIREMENT:` in order: remove the directive from #8740, then delete the script and its test, then remove the `scripts/test-all.sh` row.
   - `chmod +x` both new scripts and commit the mode. The sweeper refuses a non-executable probe.
   - **Test (`.test.sh`)** uses its own `pass`/`fail` counters plus an instrument self-test, as in `ship-merge-mergebase-verdict-8151.test.sh`. Do not source `plugins/soleur/test/test-helpers.sh`.
     - Stubs: `curl` and `git` only, in a stub directory added to `PATH` for the probe run alone, never exported. Each stub:
       - records its argv to a call log;
       - routes `curl` on the URL (the `/health` host versus each `/organizations/jikigai-eu/events/` query, by encoded `query=`) and honours the `-w` status trailer;
       - answers only `git log --diff-filter=A …`, `git cat-file -e …` and `git merge-base --is-ancestor …`;
       - exits 99 and logs anything it does not route. It never passes a call through to real git or the network.
     - Find `route.ts` through `BASH_SOURCE`, never `git rev-parse`. Keep `jq` real.
     - Rows. Each asserts the exit code **and** the reason line, and that the call log is non-empty:
       1. all green (signal 0, deployed, liveness 3 events, extra fields in the bodies) → 0;
       2. signal 1, fix not deployed, liveness absent → 1 (signal wins over both);
       3. signal 0, not deployed (`merge-base` rc 1) → 2;
       4. signal 0, deployed, liveness 0 → 3 (the vacuous-PASS guard);
       5. HTTP 500 on the signal query → 3;
       6. HTTP 500 on `/health` → 3;
       7. HTTP 500 on the liveness query → 3;
       8. signal body not JSON → 3;
       9. signal body `{}` → 3;
       10. `build_sha` values `dev`, `HEAD`, `-h`, empty and a 7-character sha → 3 each;
       11. empty `INTRO` → 3;
       12. `merge-base` rc 128 → 3;
       13. token unset → 3, with no network call logged;
       14. in row 1, each of the two Sentry URLs contains `environment%3Aproduction`, and `merge-base` was called with `--is-ancestor <INTRO> <build_sha>` in that order;
       15. drift: the probe's own `feature` and `op` constants, read from the script, are what the route emits. `op: "zero-view-model"` occurs exactly once in `route.ts`, and `feature: "c4-project-read"` occurs in the same `mirrorWarnWithDebounce` block.
   - Register the test in `scripts/test-all.sh` next to the other `scripts/followthroughs/*.test.sh` rows. Four open PRs touch that file, so expect a small rebase.

### Phase 2: Verify

- `cd apps/web-platform && ./node_modules/.bin/vitest run test/c4-project-route.test.ts test/c4-shared.test.tsx test/c4-render.test.ts test/c4-render-boundary.test.ts test/c4-workspace.test.tsx test/c4-diagram.test.tsx test/c4-concierge-copy.test.ts test/c4-prompt-addendum-honesty.test.ts`.
- `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.
- `bash scripts/followthroughs/c4-zero-view-model-8740.test.sh` and `bash scripts/lint-followthrough-varq-ban.sh`.

### Phase 3: Ship-time issue hygiene

- PR body: `Ref #8740`, `Ref #8861`, and a one-paragraph Re-render Decision summary. No closing keyword in the title or body.
- After the deploy, edit #8740's body:
  - add the follow-through directive, verbatim and unfenced (see Follow-Through Enrollment);
  - add the `follow-through` label;
  - run `gh workflow run scheduled-followthrough-sweeper.yml -f dry_run=true` and confirm its log names #8740.
- Post one comment on #8740 with:
  - what shipped;
  - options (a), (b) and (c);
  - the close rule;
  - how to stop the FAIL comments.
- Post one comment on #8739: when it ships, remove "then reload the page" from both diagnostic copies in `app/api/kb/c4/project/route.ts` and from the addendum sentence in `server/c4-concierge-tools.ts`, plus their pinned tests.

## Follow-Through Enrollment

CPO condition 5 makes #8740's close time-gated and evidence-based. Plan Phase 2.9.1 requires that close to be automated.

- **PASS** (the sweeper closes #8740). The fix is live in production, the production Sentry sink was live, and there were 0 production `op:zero-view-model` events in the trailing 14 days. That is proof by absence: members either never loaded the model or re-rendered it. `earliest=` is deploy + 14 days, so the window is post-deploy.
- **FAIL** (the sweeper comments daily; #8740 stays open, or reopens if it was closed within 14 days). There were production zero-view loads from any workspace. This is the push signal to take option (c). If loads come from repos other than the census one, raise #8861's priority.
- **NOT YET / CANNOT ESTABLISH.** A comment with the probe's reason line.
- **Census arm.** A census re-run showing 0 zero-view models also closes #8740 by hand.
- **Directive.** Paste this verbatim into #8740's body, unfenced at column 0 (it is fenced here only so it renders). The HTML-comment wrapper is what the sweeper parses:

  ```html
  <!-- soleur:followthrough
    script=scripts/followthroughs/c4-zero-view-model-8740.sh
    earliest=<deploy + 14 days, ISO-8601 UTC, e.g. 2026-10-10T18:00:00Z>
    secrets=SENTRY_ACTIONS_RO_TOKEN
  -->
  ```

- **Verify enrolment.** `follow-through-directive-gate.sh` fires only on `gh issue create`, so after the edit run the sweeper with `dry_run=true` and confirm #8740 is parsed.
- **New secrets.** None. `SENTRY_ACTIONS_RO_TOKEN` is already wired in `.github/workflows/scheduled-followthrough-sweeper.yml`, which checks out with `fetch-depth: 0`.

## Guard Contract

There are two guards. Phase 1 item 8 is the follow-through probe: an issue-closing gate with an anti-vacuity control. Its `.test.sh` also carries a drift check. The route diagnostic and the `dir` validation are product behaviour; their tests are in Test Scenarios.

### Guard 1 — follow-through close gate (`c4-zero-view-model-8740.sh`)

**Property.** The probe exits 0, and so closes #8740, only when all three of these hold together:

- the fixed code is live in production;
- the production Sentry sink was live in the window;
- no production zero-view load was recorded in the trailing 14 days.

Every other state exits non-zero, with a reason line.

**Assembly.** The chokepoint is the probe's single `exit 0` statement. Every path must reach it through checks 1 to 4, in order:

1. token;
2. signal query (response validated as an array);
3. /health `build_sha` validation, the introducing commit, `cat-file`, and `merge-base --is-ancestor`;
4. liveness query.

Every other exit path is enumerated by position:

- token unset → 3, before any network call;
- each non-200 or non-array response → 3, after that call;
- signal ≥ 1 → 1;
- invalid `build_sha` or introducing commit, or a `cat-file` failure → 3;
- `merge-base` rc 1 → 2, rc ≥ 128 → 3;
- liveness 0 → 3.

The two Sentry query strings are the second chokepoint. Both must carry `environment:production` and the project pin, and the signal query must carry the route's exact `feature`/`op` literals.

**Mutation matrix:**

| # | Mutation (probe) | Expected |
|---|---|---|
| 1 | Delete the liveness query, or treat 0 startup events as live | RED (row 4) |
| 2 | Delete the /health ancestry check (the old artifact then satisfies liveness) | RED (row 3) |
| 3 | Run the /health or liveness check before the signal check | RED (row 2) |
| 4 | Drop `environment:production` from either query | RED (row 14, which checks each URL) |
| 5 | Map a non-200 or non-array body to "0 events" | RED (rows 5, 7, 8, 9) |
| 6 | Drop `--is-ancestor`, or swap its arguments | RED (row 14 argv assertion) |
| 7 | Accept `build_sha=dev`, or pass it to git unvalidated | RED (row 10) |
| 8 | Rename the route's `op` slug without updating the probe | RED (row 15) |

**Harness rows:**

- The instrument self-test proves `pass` and `fail` both move their counters.
- Every row asserts that the stub call log is non-empty and that no exit-99 "unrouted" entry exists. A stub that answers every URL identically reddens row 2.
- Must-PASS input that is not the canonical fixture: row 1 uses 3 liveness events and bodies with extra fields.

**Anchor.** The introducing commit is derived with `git log --diff-filter=A` on the checked-out `main`, not stored in the script, and `build_sha` comes from the live production endpoint. An edit to the probe cannot move either one.

### Guard 2 — probe/route literal drift row

**Property.** The `feature` and `op` literals the probe queries equal the literals the route's `mirrorWarnWithDebounce` call emits.

**Assembly.** There are two sources: the probe's signal-query constants, and the `mirrorWarnWithDebounce` call in `apps/web-platform/app/api/kb/c4/project/route.ts`. The row reads both files and never a copied literal.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Change the route's `op` literal | RED |
| 2 | Change the probe's `feature` constant | RED |
| 3 | Add a second `op: "zero-view-model"` occurrence to `route.ts` (for example in a comment) after the compliant first one | RED: the row asserts the count is exactly 1, not at least 1 |
| 4 | The row greps a hard-coded copy of the literal instead of the probe's constant | RED: mutation 2 must redden it |

## Files to Edit

- `apps/web-platform/app/api/kb/c4/project/route.ts`: `dir` hardening, zero-view detection, diagnostic, debounced warning.
- `apps/web-platform/server/c4-render.ts`: use `c4ModelCounts` and delete `plainObjectSize`.
- `apps/web-platform/components/kb/c4-shared.tsx`: re-export `Diagnostic` from `@/lib/c4-model-shape`.
- `apps/web-platform/components/kb/c4-diagnostics.tsx`: omit the `line N:` prefix for model-level diagnostics.
- `apps/web-platform/server/c4-concierge-tools.ts`: one addendum sentence.
- `apps/web-platform/server/observability.ts`: one errorClass registry doc-comment line.
- `apps/web-platform/test/c4-project-route.test.ts`: new rows, plus a mandatory `mockMirrorWarnWithDebounce` spy.
- `apps/web-platform/test/c4-shared.test.tsx`: strip rows.
- `apps/web-platform/test/c4-concierge-copy.test.ts`: one addendum-only `it`.
- `knowledge-base/engineering/architecture/decisions/ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md`: addendum paragraph.
- `scripts/test-all.sh`: one `run_suite` row.

## Files to Create

- `apps/web-platform/lib/c4-model-shape.ts`
- `scripts/followthroughs/c4-zero-view-model-8740.sh` (mode 100755)
- `scripts/followthroughs/c4-zero-view-model-8740.test.sh` (mode 100755)
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
- **Fixing the plugin writers.** Tracked in #8861.
- **Share-link loads.** The public share route (`app/api/shared/[token]/c4/route.ts`) gets no diagnostic, because recipients cannot act on it. It also gets no warning, so the follow-through counts member loads only; share-link loads of a zero-view model are not counted.
- **Reloading the workspace after a Concierge edit.** That is #8739. Until then, the copy tells the user to reload.
- **Suppressing the canvas's "View `index` not found in the model." line.** The strip explains it.
- **An amber strip, or a new Sentry alert rule.** See DC-4 and the Cut List.
- **A JSON `null` or array model.** It already throws at the existing `views` read and returns a loud 503.
- **Queue items #8752 and the render-slot residual.**

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Detect client-side in `C4Canvas` | The issue names the route, and the server check feeds the Sentry signal (P3). |
| New `modelDiagnostic` field and an amber strip | A new field, a new element and a real UI change, for one message the existing channel carries. |
| `line: 1`, no component change | It points at an unrelated source line. |
| Widen `Diagnostic.line` to optional | A client-boundary type widening with the same visible result. |
| Undebounced `warnSilentFallback` per GET | One event per page load. |
| Debounce key on the raw `dir` | Trivially bypassed with `./` variants (security finding 2). |
| Re-render from the route on read | A GET that writes to a tenant repository. |
| Keep a local copy of `plainObjectSize` | Semantics shared by comment, not by construction. |
| Add a `sentry_alert` for `op:zero-view-model` | An IaC change for one tenant. The sweeper FAIL comment carries the push signal. |
| Probe owns no liveness or deployment control | A zero-count PASS from a dead sink, or from undeployed code, would close #8740 falsely. |

## User-Brand Impact

- **If this lands broken, the user experiences:** one of these.
  - A false positive: a red "Diagram warnings" strip says the diagram has no views, on a diagram that renders fine.
  - A false negative: the page stays as today, "View `index` not found in the model." with no explanation.
  - A too-strict `dir` guard returns 400 on a legitimate folder name, so the diagram does not load. The allowlist covers `[A-Za-z0-9._-]` segments; KB folder names are kebab-case.
  - The Concierge, following the addendum, writes a comment to the wrong file.
- **If this leaks, the user's data is exposed via:** nothing new. This PR **closes** a pre-existing read of non-KB folders through `dir` dot-segments. The diagnostic text is static. The warning carries `userIdHash`, the validated `dir` and `modelPath` (the KB path GitHub returns) and an integer, the same data kinds this route already reports.
- **Brand-survival threshold:** `none`.
- `threshold: none, reason: the change adds a static, read-only message to an existing member-scoped GET response, tightens that route's input validation, and emits one debounced warning; it writes nothing and emits no tenant content.`

## Observability

```yaml
liveness_signal:
  what: "Sentry warning issue 'c4 project read: committed model has elements but no views' (feature=c4-project-read, op=zero-view-model), at most once per workspace+modelPath per 5 minutes per process while a zero-view model is read; permanent read-side detector for a zero-view model from any writer (#8740, #8861)"
  cadence: "on read of a zero-view model; debounced 5 minutes per workspace+modelPath"
  alert_target: "follow-through sweeper comment on #8740 (FAIL, daily after earliest); no Sentry email (the only unfiltered issue-stream rule is high-priority-only)"
  configured_in: "apps/web-platform/app/api/kb/c4/project/route.ts (GET) and scripts/followthroughs/c4-zero-view-model-8740.sh"
error_reporting:
  destination: "Sentry web-platform project via warnSilentFallback(null, ...) -> captureMessage level=warning with feature/op tags; pino warn -> Vector app_container_warn_filter -> Better Stack"
  fail_loud: "Sentry warning 'c4 project read: committed model has elements but no views' (feature=c4-project-read op=zero-view-model); pino warn line with the same msg"
failure_modes:
  - mode: "false positive: diagnostic on a model that has views"
    detection: "route rows T2/T4 pre-merge; post-merge, the number of distinct userIdHash/modelPath values on the op=zero-view-model events (read with scripts/sentry-issue.sh) exceeds what a census re-run finds (Sentry layer 4 issue stream, pino layer 2 -> Vector/Better Stack layer 3)"
    alert_route: "follow-through FAIL comment on #8740; the census re-run is the comparison"
  - mode: "false negative: a zero-view model served with no diagnostic (probe would PASS by absence)"
    detection: "route rows T1/T4 pin every views shape the census counts as zero ({} and []); post-merge, a census re-run finding a zero-view model while Sentry shows no event on a release at or after the fix (release tag, layer 5)"
    alert_route: "soleur:postmerge Sentry read; #8740 stays open until reconciled"
  - mode: "follow-through closes #8740 vacuously (sink dead, fix not live, or op slug renamed)"
    detection: "probe exits 2 unless /health build_sha descends from the probe's introducing commit, exits 3 without an environment:production server-startup event in the window; its .test.sh drift row reads both files (workflow run log of scheduled-followthrough-sweeper.yml + issue comment, layer 6)"
    alert_route: "sweeper NOT YET / CANNOT ESTABLISH comment on #8740"
  - mode: "new code throws on an odd model shape or dir, turning a 200 into a 503"
    detection: "existing reportSilentFallback op=github-read-failed on the route's outer catch plus logger.error (pino layer 2 -> Better Stack layer 3; Sentry error-level issue); route rows T4/T6 pre-merge"
    alert_route: "Sentry high-priority rule (error-level new issue) -> email, filed under op=github-read-failed"
logs:
  where: "container stdout (pino JSON) -> journald -> Vector (apps/web-platform/infra/vector.toml app_container_warn_filter: WARN+) -> Better Stack; Sentry for the warning event"
  retention: "Better Stack source retention for the web-platform source (90 days); Sentry event retention for the warning issue"
discoverability_test:
  command: "grep -c 'op: .zero-view-model.' apps/web-platform/app/api/kb/c4/project/route.ts"
  expected_output: "1"
```

The discoverability probe checks that the single emitter of the op slug, which is the Sentry search key, exists.

- The pattern uses `.` for the quote characters, so it needs no escaped quotes. It still prints `1` after implementation, because the errorClass `c4-project-read:zero-view-model` has no `op:` prefix followed by a space. Today it prints `0`, since the emitter is not written yet.
- It declares no `credentials_required`, so the preflight `BASELINE_DECLARED_PROBES` ratchet does not move.

## Domain Review

**Domains relevant:** Product

The Engineering, Legal, Marketing, Operations, Sales, Finance and Support assessment questions do not match: this is a bug fix on an existing surface. The CTO and CMO reviewed the plan as part of the plan-review named panel.

### Product/UX Gate

**Tier:** advisory
**Decision:** reviewed
**Agents invoked:** soleur:product:cpo, soleur:product:design:ux-design-lead (plan-review named panel), soleur:marketing:cmo (plan-review named panel)
**Skipped specialists:** none
**Pencil available:** N/A (no UI surface): copy-only exemption, see below

#### Findings

**CPO: approve with conditions.** All six are applied:

1. The copy is replaced and the Save clause dropped.
2. The unverified "re-render" wording is replaced with a concrete `.c4` edit.
3. S1 pins "Diagram warnings" and the absence of "Diagram has errors".
4. The exemption is kept, with its fallback.
5. The 14-day evidence close is automated.
6. `Ref #8740`, and the choices are persisted (DC-1).

The CPO also asked for **first-person fault ownership** ("our renderer"). That was replaced by the writer-neutral "saved layout is incomplete" (DC-2).

**UX lead: exemption agreed.** The reload clause and the concrete edit were adopted, and the embed surface is in scope. The screenshot of the zero-view state at 35% panel width is attached at QA.

**CMO:** the jargon and the layout-versus-source split were fixed.

**Step 4.5 consult:** the sentinel census was run and the Save clause dropped. The cause hedge was resolved by asserting no cause at all.

**GDPR gate (Phase 2.7).** This is not legal review. The findings are heuristic; consult `soleur:legal:clo` and `soleur:legal:legal-compliance-auditor` before merging anything load-bearing.

- 0 findings. There is no schema, vendor or Art. 9 surface.
- The response adds a static string (AP-01/AP-05).
- The ownership check is unchanged (AP-02).
- The input validation is tightened.
- The new emit carries data kinds this route already sends to processors recorded in `compliance-posture.md`.

**Wireframe gate (`wg-ui-feature-requires-pen-wireframe`): exempt, copy-only.**

- The only UI change drops the `line N:` text prefix inside the existing `<li>` of the existing red strip. There is no new element, class, interaction or layout.
- `ui-surface-terms.md` §Excluded covers this, and the #8732 plan is precedent.
- Surface design of record: `knowledge-base/product/design/kb-viewer/c4-viewer-no-code-panel-gated-edit.pen`.
- The exemption lapses if a later change adds an element, colour or position for this message. `soleur:product:design:ux-design-lead` then produces a `c4-zero-view-diagnostic` Pencil file in the `kb-viewer` design folder first.

## Test Scenarios

Route (`test/c4-project-route.test.ts`). The fixtures are synthetic and built with `JSON.stringify`. The `mockMirrorWarnWithDebounce` spy is mandatory.

- **T1:** Given `{ elements: { a: {id:"a"}, b: {id:"b"} }, views: {} }` in the canonical dir, then:
  - status 200, `viewIds` `[]`;
  - `diagnostics` = `[{ message: <canonical copy>, line: 0, sourceFsPath: "model.likec4.json" }]`;
  - the spy is called once, with:
    - `calls[0][0]` `null`;
    - a ctx containing `feature: "c4-project-read"`, `op: "zero-view-model"` and the fixed `message`, with no `tags`;
    - key `"ws-1:knowledge-base/engineering/architecture/diagrams/model.likec4.json"` (the listing's `path`);
    - errorClass `"c4-project-read:zero-view-model"`.
- **T2:** elements plus `views: { index: {...} }` → `diagnostics` `[]`, spy not called.
- **T3:** `{ elements: {}, views: {} }` → `[]`, spy not called.
- **T4 (`it.each`):** all return 200.
  - absent `views` → diagnostic;
  - `views: []` → diagnostic;
  - `elements: ["x"]` → none;
  - `elements: "xy"` → none.
- **T5:** the T1 model under a non-canonical dir (`product/diagrams`, a fixture listing) → the `…OTHER_DIR` copy. It contains no "Concierge".
- **T6 (`dir` hardening, `it.each`):** each of `%2e%2e/x`, `./x`, `a//b`, `a/`, `a%2Fb`, `x y`, `x\u0001y`, and a 257-character dir → 400 and **zero** `githubApiGet` calls. Also `engineering/architecture/diagrams` → 200 (must-pass).
- **T7:** two GETs, `dir=engineering/architecture/diagrams` and then the same model served for a sibling request, pass the **same** key argument to the spy (canonical `modelEntry.path`).

Strip (`test/c4-shared.test.tsx`).

- **S1:** `diagnostics=[{ message: "M", line: 0, … }]`, `hasModel` →
  - "Diagram warnings" is shown and "Diagram has errors" is absent;
  - the item's text is exactly `M`;
  - no `/line 0/`;
  - the same for `line: -1`.
- **S2:** `line: 3` → the item's text is exactly `line 3: bad ref`.

Concierge copy (`test/c4-concierge-copy.test.ts`).

- **C1:** one `it` outside the `describe.each` asserts that `C4_PROMPT_ADDENDUM` contains the new sentence's anchor phrases:
  - `"saved layout is incomplete"`;
  - `"do not add or change \`views\` blocks"`;
  - `"saving the \`.md\` page does not re-render"`.
- The existing both-surface assertions stay green.

Follow-through probe (`scripts/followthroughs/c4-zero-view-model-8740.test.sh`): rows 1-15 in Phase 1 item 8.

Regression: `c4-render.test.ts` and `c4-render-boundary.test.ts` stay green after `c4ModelCounts` replaces `plainObjectSize`.

## Plan Review Disposition

The reviewers were the eng panel (DHH, Kieran, code-simplicity) and the named panel (CPO in Phase 2.5; CTO, UX lead and CMO at review). Mechanical findings were applied. Taste findings are in `decision-challenges.md`.

| Source | Finding | Disposition |
|---|---|---|
| DHH P1 | The copy asserts a cause the route cannot know | Applied |
| DHH P1 | Cut the probe | Declined: Phase 2.9.1 requires the automated close, and CTO and code-simplicity kept it |
| DHH P1 | Nothing retires the diagnostic | Applied: permanent, a detector for any writer |
| DHH P2 / architecture 3 | Share the shape logic | Applied: `c4ModelCounts`, `Diagnostic`, `MODEL_LEVEL_LINE` |
| DHH / simplicity | Cut the old T6/T7/S3 rows, the mutation ritual, and the registry and export ACs | Applied |
| DHH P2 | Make (c) the default | Taste: DC-1 |
| Simplicity / CTO | `environment:production`; `viewIds` unchanged; fold rows | Applied |
| CTO 1 / Kieran 6 | Exit codes mislabelled in sweeper comments | Applied |
| CTO 3 / 4 / 5 / 6 | Daily FAIL comments, retirement order, warning permanence, slug drift | Applied |
| Kieran P1-1 | Liveness producible by the old artifact | Applied: /health ancestry check |
| Kieran P1-2 | S3 unwritable against the mock | S3 cut |
| Kieran P1-3 / P1-4 / P1-5 | Executable bit; directive wrapper and dry-run check; Codex engine | Applied |
| Kieran P2-7 / P2-10 | Check order and counting; mandatory spy | Applied |
| UX 2 / 3 / 4 | Reload clause; concrete `.c4` edit; embed in scope | Applied |
| UX 5 / CPO | Amber strip; dead-end `hasModel=false` header | DC-4 |
| CMO | Jargon, layout-versus-source split, active action sentence | Applied |

## Deepen Findings Disposition

| Source | Finding | Disposition |
|---|---|---|
| Security 1 | `dir` dot-segment traversal (pre-existing) | Folded in: Phase 1 item 2, T6 |
| Security 2 | Debounce key bypass through a raw `dir` | Applied: key on `modelEntry.path`, T7 |
| Security 3 | Control characters and U+2028/2029 in `dir` reach the logs | Applied: item 2 |
| Security 4 / test-design 2 / observability 7 | Unvalidated `build_sha` and `INTRO`; rc 1 versus 128 | Applied: check 3, rows 10-12 |
| Security 5 / 6 | curl flags, token off argv, public-repo output | Applied |
| Security 7 | Forgeable Sentry signals | Residual risk stated in the probe header; project pin |
| Security wording | "Owner-scoped" | Corrected to member-scoped |
| Observability 1 | No first-seen email for a warning-level issue | Applied: claim removed; the sweeper FAIL is the push signal; a new alert rule is cut |
| Observability 2 / 3 / 4 / 5 / 8 | Unreadable detections, layer citations, stale T5 references | Applied (Observability block) |
| Observability 6 | Escaped quotes in the discoverability command | Applied: `.` pattern |
| Test-design 1 / 3 / 4 / 5 / 7 / 8 / 9 | Per-URL 500s, non-JSON and `{}` bodies, reason-line assertions, loud stubs, argv logging, pinned check order, per-URL environment filter, drift read from the probe, fuller T1 ctx, status trailer on /health | Applied |
| Test-design 6 | `d.line` variants survive S1 | Applied: `line: -1` case |
| Test-design 10 | Tripwire interaction | Confirmed safe; stub rules adopted |
| Architecture 1 | Plugin writers still produce zero-view models | Filed #8861; ADR-050 addendum; neutral wording |
| Architecture 2 | Boundary-safe; test-all.sh conflict risk | Noted |
| Architecture 4 / 7 / 8 | Named sentinel; `detail_class` reuse; FAIL blames one tenant | Applied |
| Architecture 5 | Share route uncounted | Non-Goal stated |
| Architecture 6 | ADR-050 wording overstated | Applied: addendum (item 7) |
| Agent-native 1 / 2 | The Concierge misreads the state; `.md` false success | Applied: addendum sentence, C1 |
| Agent-native 3 | Concierge fix offered outside the writable folder | Applied: canonical-dir condition, T5 |
| Agent-native 4 | #8739 comment must name both places | Applied |
| Verify pass | `edit_c4_diagram` is built in `c4-concierge-tools.ts`, not `cc-dispatcher.ts` | Corrected |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. It is filled here.
- The route file may export only HTTP handlers. Both copy constants stay non-exported, and the tests pin the copy literally.
- The observability mock in `c4-project-route.test.ts` spreads `importActual`, so `mirrorWarnWithDebounce` **must** be an explicit spy.
  - Without it, the real debounce map dedupes across tests.
  - Without it, the `@sentry/nextjs` mock (with only `captureException`) makes `warnSilentFallback` skip `captureMessage` silently.
- `mirrorWarnWithDebounce`'s argument order is `(err, ctx, key, errorClass)`. Assert on the spy, never on Sentry event counts.
- The literal `op: "zero-view-model"` must appear exactly once in `route.ts`. The discoverability test and the drift row both depend on it.
- The `dir` regex for control characters uses escapes only (`cq-regex-unicode-separators-escape-only`). Never put a raw U+2028 in source.
- Run the addendum sentence past both Concierge copy suites; they pin forbidden phrases and counts.
- Do not copy the template probe's exit contract, its unbounded `curl`, or its body echo.
- Paste the directive into #8740 unfenced, at column 0.
- Put no closing keyword for #8740 in the PR title or body.
- The probe uses `SENTRY_ACTIONS_RO_TOKEN` and never names the retired Sentry credential anywhere under `scripts/followthroughs/`.
- Run `npx markdownlint-cli2` on this plan and `tasks.md` before committing.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `GET /api/kb/c4/project` returns exactly one diagnostic (`line: 0`, `sourceFsPath: "model.likec4.json"`) when `elements` is a non-empty plain object and `views` is absent, empty or not a plain object. The copy is the canonical-dir text in the diagrams folder and the other-dir text elsewhere (T1, T4, T5).
- [ ] AC2: It returns `diagnostics: []` for a model with at least one view, and for one with no elements or non-object `elements` (T2, T3, T4).
- [ ] AC3: `mirrorWarnWithDebounce` is called once per zero-view request, with `err === null`, the fixed message, `feature`/`op`, the `modelEntry.path`-based key, and errorClass `c4-project-read:zero-view-model`. It is never called on the no-diagnostic paths (T1-T3, T7).
- [ ] AC4: Every malformed `dir` in T6 returns 400 with zero GitHub calls, and the canonical dir returns 200.
- [ ] AC5: `C4Diagnostics` omits the `line N:` prefix when `line <= 0`, keeps `line N: msg` for positive lines, and shows "Diagram warnings", never "Diagram has errors", for a model-level diagnostic (S1, S2).
- [ ] AC6: `git grep -n "function plainObjectSize" -- apps/web-platform` prints one line, in `lib/c4-model-shape.ts`. `c4-render.test.ts` and `c4-render-boundary.test.ts` pass.
- [ ] AC7: `C4_PROMPT_ADDENDUM` contains the new sentence (C1), and `c4-concierge-copy.test.ts` and `c4-prompt-addendum-honesty.test.ts` pass.
- [ ] AC8: `bash scripts/followthroughs/c4-zero-view-model-8740.test.sh` passes rows 1-15 and the instrument self-test.
  - It is registered in `scripts/test-all.sh`.
  - `bash scripts/lint-followthrough-varq-ban.sh` passes.
  - `git ls-files -s` shows mode `100755` for both new scripts.
- [ ] AC9: The ADR-050 addendum names the read-side detector and #8861. The `Failure classes:` line is unchanged: `git diff origin/main...HEAD` on the ADR shows no removed line containing `Failure classes:`.
- [ ] AC10: The Phase 2 vitest suites pass, and `tsc --noEmit` is clean.
- [ ] AC11: The PR body says `Ref #8740`, and neither the title nor the body carries a closing keyword for #8740.
- [ ] AC12: No write to any tenant repository happens in this PR's lifecycle.

### Post-merge (automated by ship and the sweeper)

- [ ] AC13: #8740 is OPEN after merge and carries:
  - the unfenced `<!-- soleur:followthrough … -->` directive (`earliest` = deploy + 14 days, `secrets=SENTRY_ACTIONS_RO_TOKEN`), with a sweeper `dry_run=true` log that names #8740;
  - the `follow-through` label;
  - a disposition comment naming options (a), (b) and (c), the close rule, and how to stop FAIL comments.
- [ ] AC14: #8739 carries a comment naming the three "then reload the page" clauses to remove when it ships: the two route copies and the addendum.
