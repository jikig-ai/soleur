# Review Seat — git-history-analyzer

PR #11780 (closes #11772) — worktree `feat-one-shot-11772-next-dev-server-crash`.
Diff basis: `git diff origin/main...HEAD` (three-dot; merge-base `5e9c73502b`). Fetched `origin/main` first. Report-only; no writes to tracked files. (Intended location `$(git rev-parse --git-dir)/review-seat-git-history.md` was blocked by the worktree guard; placed at worktree root instead.)

## Method

For every prose claim in the diff (commit messages, ADR amendment, code comments, plan/tasks/session-state/decision-challenges) that asserts a fact about git history or the pre-change tree, verified against `git show origin/main:<path>`, `git log`, and `gh` where git cannot see state.

## Verified TRUE claims

| Claim in diff prose | Verification |
|---|---|
| "bisected out of the merged 2026-10-31 critical/high Dependabot batch (PR #11691, merged 2026-11-01)" (plan L20-21; drain-guard comment) | `075b1889ad` squash on origin/main, commit 2026-11-01 05:32Z; `gh pr view 11691` → MERGED 2026-11-01T06:09:53Z (exact timestamp in plan L144 matches) |
| "e2e failed deterministically 3x / deterministic dev-server crash" (plan L115; guard comment) | #11691 squash body: "The e2e required check failed 3x on this branch (uncaughtException: Error aborted / ECONNRESET, then connection-refused)" |
| "the eight rows of the 2026-10-31 batch" / MIN_ROWS "prior 27 + eight" (guard comment) | `git show 075b1889ad^` → MIN_ROWS/MIN_RESOLVED = 27; `075b1889ad` diff adds exactly 8 REQUIRED rows (+3 FLOOR_ANCHORS) → 35 |
| ADR-062 fatal contract "capture → close(2000) → exit(1)" (plan, ADR amendment) | `origin/main:crash-handlers.ts` `reportFatalAndExit` matches verbatim shape; `Sentry.close(FATAL_FLUSH_MS)` present |
| `warnSilentFallback` = pino warn + `Sentry.captureException(level:"warning")` + `redactErrorForEmit` + `hashExtraUserId` + shimmed-SDK no-op, at `observability.ts:287-334` (decision-challenges) | Exact. `export function warnSilentFallback` at L287; all claimed behaviors present in body |
| `installCrashHandlers()` unconditional at `server/index.ts:83`, both bundles (decision-challenges row 2) | `server/index.ts:83` — unconditional call; import at L43 |
| `e2e/mock-supabase.ts:219` catch-all 404 | `res.writeHead(404)` is exactly line 219 |
| `NextResponse.next({ request: { headers } })` clone path in middleware; `proxyClientMaxBodySize` 25MB (plan L136) | middleware.ts L212/256/261/311/580; next.config.ts:113 `25 * 1024 * 1024` |
| #11783 deferral tracker filed | `gh issue view 11783` → OPEN, correct title (upstream body-streams watch, vercel/next.js #49587) |
| "#9167/#7591/#8450 closed, #5417/#2591 open" (plan L79-80) | gh: 9167 CLOSED, 8450 CLOSED, 7591 CLOSED, 5417 OPEN, 2591 OPEN — all match |
| Rule-id citations resolve live (plan L77-78) | `wg-architecture-decision-is-a-plan-deliverable` in `scripts/migrated-rule-ids.txt:76`; `cq-silent-fallback-must-mirror-to-sentry`, `hr-ssh-diagnosis-verify-firewall`, `hr-observability-as-plan-quality-gate`, `wg-use-closes-n-in-pr-body-not-title-to` all live |
| `e2e-webserver: exited rc=` marker exists (plan cites #9167) | `e2e/web-server.sh:37` emits exactly that marker |
| Drain-guard arithmetic: MIN_ROWS/MIN_RESOLVED 35→36 (+1 REQUIRED row), MIN_ASSERTIONS 33→34 (+1 spec arm `next:16:16.4.1`), FLOOR_ANCHOR `("next",16):"16.4.1"` | All consistent; lockfile resolves `next` 16.4.3 satisfying `~16.4.1` and the 16.4.1 floor |
| Egress pin re-measure basis: prior batch measured x-forwarded-* on 16.4.3 (from #11691 squash bullets) | Branch re-pins `/^16\.3\./`→`/^16\.4\./`; lock lands on 16.4.3 — same version the prior batch measured |
| `Closes #11772` in commit `c4fd6bf114` | Present; #11772 OPEN with matching title |

## FINDINGS

### P2-1 — "Verified" abort-producer count is wrong (35 claimed; 48 actual)

Prose in three files claims a verified count that does not match the tree, on
either HEAD or `origin/main` (the file is untouched by this PR):

- `knowledge-base/project/plans/2026-11-01-fix-next-16-4-1-e2e-dev-server-crash-plan.md` L70-72:
  "`server/dsar-export.ts` throws `new Error("aborted")` at 35 sites … plus 4 in
  `server/dsar-export-co-uploader.ts` — CTO-verified 2026-11-01."
- `knowledge-base/project/specs/feat-one-shot-11772-next-dev-server-crash/decision-challenges.md`
  row 1: "`dsar-export.ts` 35 sites, `dsar-export-co-uploader.ts` 4 sites — verified".
- `knowledge-base/project/specs/feat-one-shot-11772-next-dev-server-crash/session-state.md`:
  "Plan count corrected to CTO-verified 35+4 `Error("aborted")` sites".
- Commit `594af75330` message: "… + verified abort-producer counts".

Actual: `grep -c 'new Error("aborted")' dsar-export.ts` = **48** (46 inline
`if (signal.aborted) throw` arms plus two braced-block throws at L1917, L1946);
co-uploader = 4 (this part is correct). No plausible recount yields 35.

Impact assessment: **limited**. The load-bearing proposition — every in-repo
`Error("aborted")` producer carries NO `.code`, so all still exit under the
exact-pair predicate — remains true: the only `.code` token in dsar-export.ts
is a `code === "ELOOP"` *read* at L1850, and every one of the 48 sites is a
bare `throw new Error("aborted")`. The classifier ruling is unaffected. The
defect is a "verified" label on a wrong number, propagated across four
artifacts including a commit message.

### P3-1 — Off-by-one line citation for team-names 500

`decision-challenges.md` row 5 cites `app/api/team-names/route.ts:33` as the
handled `NextResponse.json({status:500})` return. Actual: the return is at
**line 34**; line 33 is the `if (namesResult.error) {` guard. Substance (the
500 is a handled response that cannot reach the crash path) is correct.

### P3-2 — Plan/AC cite an ADR-062 section that does not exist

Plan L296, tasks.md 5.2, and AC7 prescribe recording rejected options under
ADR-062 "`## Alternatives Considered`". ADR-062 has no such section (headings:
Context / Decision A–C / Sentry alert / Scope / Consequences). The amendment
instead folds "Rejected alternatives: …" into the Deliverable C carve-out
paragraph — a reasonable adaptation, and the content is present. The plan/AC
prose references a nonexistent anchor; AC7's literal wording is not met even
though its intent is.

### P3-3 — `warnSilentFallback` plan citation "line ~265" is 22 lines off

Plan L175 cites `server/observability.ts` "(line ~265)"; the function is at
L287. Mitigated by the `~` marker and by decision-challenges' accurate
`287-334` citation.

## Settled rulings — all consistent, none contradicted

- Exact-pair classifier scope: shipped `isBenignClientAbort` is exactly `Error`
  + `message === "aborted"` + `code === "ECONNRESET"`; near-miss test arms
  (no-code aborted, wrong-message ECONNRESET, non-Error) all assert exit. ✅
- Prod-wide application: no environment gate; applies in both `process.on`
  handlers unconditionally. ✅
- `warnSilentFallback` sink: used verbatim with `feature:"crash-handlers"`,
  `op:"client-abort"`. ✅
- team_names mock deferral: no mock route added; deferral recorded in
  tasks.md 5.4 and decision-challenges row 5; the 500 is confirmed a handled
  `NextResponse` (route.ts:34), non-causal. ✅
- Keep-as-defense-in-depth: ADR-062 amendment records re-evaluation deferred
  to #11783; no auto-revert. ✅

## Prior-batch claims (#11691)

The drain-guard comment's rewrite ("the crash was the benign inbound-abort
signature hitting the ADR-062 fatal contract — classified non-fatal … and the
bump re-applied here in the same PR") accurately supersedes the old "lands in
its own PR" line and is consistent with #11691's own squash body (deterministic
3x e2e failure, `uncaughtException: Error aborted / ECONNRESET`, next reverted
to ~16.3.8). No contradiction.

Note (informational, not a finding against this PR): #11691's squash body lists
a bullet "arm the manifest-presence check …; floor 34" while merged
`MIN_ASSERTIONS` is 33 — likely an intermediate-commit message superseded
later in that PR. This branch's 33→34 ratchet matches the actual tree.

## Verdict

FINDINGS — 0 P1, 1 P2, 3 P3. History-critical claims (PR #11691 merge, batch
arithmetic, ADR-062 contract, issue states, rule ids) are all true to git
history. The sole substantive defect is a wrong "verified" producer count
(P2-1) whose safety conclusion happens to remain correct.
