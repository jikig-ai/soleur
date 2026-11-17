# Learning: an empty `?probe=` is a run request — gate placement on SDK truthiness, not param presence

## Problem

While implementing placement-aware Inngest execution (#9137, PR #12554) the
exec-placement dispatcher classified incoming `serve()` calls. The Inngest SDK
distinguishes a *probe* request (`GET`/`?probe=<non-empty>` — connectivity
check) from a real *step call* (`POST`, or any request whose `probe` param is
absent **or empty**). The first cut tested probe-ness with a **presence** check
(`url.searchParams.has("probe")` semantics). An empty `?probe=` — a URL that
carries the key with no value — is a *run request* to the SDK
(`InngestCommHandler.cjs`: the probe test is `get("probe") || void 0`, i.e.
truthiness, and `""` is falsy). A presence gate would have routed a real step
call down the probe path — a P1 the sequential-fallback review caught and the
fix round (da48c9f973) closed.

## Solution

Mirror the SDK's own test exactly:

```ts
hasProbe: Boolean(url.searchParams.get("probe")),   // "" → false, "1" → true
```

and pin the subtle half in tests: `URLSearchParams.get()` returns the **first**
value for a duplicated key, so the executable matrix covers `probe=&probe=1`
(first-value-wins), percent-encoding, and case — each verified byte-for-byte
against the installed SDK handler rather than assumed.

## Key Insights

1. **Param parity means truthiness parity, not presence parity.** Whenever a
   dispatcher routes on a query/header the upstream SDK also reads, derive the
   condition from the SDK's evaluation (`get()` → falsy on `""`/`null`), never
   from key existence. `has()` and `Boolean(get())` differ on exactly one input
   — the empty value — which is the input nobody hand-types into a test.
2. **Grep test fixtures for poisoned sentinels before choosing a literal.** The
   plan wrote the receiver port as "e.g. 8444"; 8444 is the *deliberately
   wrong* sentinel in `apps/web-platform/infra/` firewall test fixtures — a
   shipped 8445+1 … the fixture assumes-as-invalid choice would have collided.
   Port 8445 was chosen after the fixture grep. Same class applies to IPs,
   hostnames, tokens: a literal that fixtures assert-as-bad must never be the
   shipped value.
3. **Leaf-extract unblocks re-classification.** To re-class an Inngest fn as
   `EXECUTION_PLACEMENT=portable`, extract the leaf dependency that anchored it
   to the exec host (`current-workspace-id.ts` leaf, `byok-resolver`
   re-point) — then `cfo-on-payment-failed` / `github-on-event` re-class cleanly
   and Guard-2 verifies no portable fn still touches host-affine state.
4. **Fail-closed placement.** `SOLEUR_HOST_PRIVATE_IP` unset/empty → HTTP 503
   refuse (never local-execute a pinned fn); a marked request (`x-soleur-exec-forward`)
   reaching a non-exec host is refused, never re-forwarded.

## Session Errors

Forwarded from `session-state.md` plus this ship/compound session:

1. **No `run_subagent` tool in the subagent harness** — plan-time agent spawns
   (CTO rulings ×2, CPO sign-off, condensed review panel) ran via the `claude`
   CLI instead; review ran `sequential-fallback 15/15` + fix-round 6/6.
   Recovery: `claude -p` spawns with `Reviewed-Coverage: sequential-fallback`
   disclosure. — **Prevention:** none at session level (harness constraint);
   the coverage trailer is the honest downstream surface. On a
   `single-user incident` plan that coverage blocks `gh pr ready` without an
   explicit operator acknowledgment — budget for it.
2. **First CTO ruling on T2 rested on a wrong premise** — `SOLEUR_PROXY_BIND`
   was assumed to carry the private IP; it is the literal `0.0.0.0` in the
   container (ci-deploy.sh:5798). Recovery: re-spawned the ruling with the
   corrected evidence; final ruling uses `SOLEUR_HOST_PRIVATE_IP`.
   — **Prevention:** `hr-verify-repo-capability-claim-before-assert` — pin the
   premise literal with `git grep` against the tree *before* spawning a ruling
   whose options depend on it.
3. **First `git commit` attempt blocked by main-branch guard via `workdir`** —
   succeeded with explicit `cd` inside the command. — **Prevention:** in
   worktrees prefer an in-command `cd` (or pass `workdir` per call); a bare
   workdir-parameter call landed in a context the guard read as main.
4. **`plan-sharp-edges.md` (~150 KB) not read in full** — highest-risk entries
   covered by guard-contract lint, panel review, and prior sharp edges.
   — **Prevention:** acceptable when a mechanical gate duplicates the coverage;
   record the substitution, don't claim a full read.
5. **Plan review ran as one condensed panel spawn** (not the full named-panel
   fan-out). — **Prevention:** same harness constraint as error 1; disclose via
   the coverage trailer and `Reviewed-Fix-Round` trailers.
6. **Bare-repo `git log` read from a one-shot exec without `workdir`** (this
   session) — the command ran in a context that answered "fatal: this
   operation must be run in a work tree" then showed *main's* history; re-ran
   with `workdir` set to the feature worktree. — **Prevention:**
   `hr-when-in-a-worktree-never-read-from-bare` — pass `workdir` (or `cd`) on
   every git call; a command that silently reads the main checkout reports the
   wrong branch's state.

## Recurring-vs-one-off triage

| item | recurring? | disposition |
|---|---|---|
| run_subagent absent → sequential review (1, 5) | recurring (harness) | covered by `sequential-fallback` convention; surfaced to operator via ship gate |
| stale premise literal in CTO ruling (2) | recurring class | covered by `hr-verify-repo-capability-claim-before-assert` |
| commit/exec cwd confusion (3, 6) | recurring | learning prevention line (workdir/cd discipline) |
| sharp-edges partial read (4) | one-off | recorded substitution |

## Tags

category: logic-errors
module: apps/web-platform/server/inngest (exec-placement), apps/web-platform/infra
pr: #12554
issue: #9137
