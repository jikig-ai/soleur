---
title: The credential move was sound; the guard's reach and the token's scope were both inherited, not measured
date: 2026-10-01
category: security-issues
module: ci-credentials
tags: [adr-241, github-app, least-privilege, census, guard-scope, stale-claims]
issues: ["#8209", "#9360", "#9361", "#9362"]
---

# Learning: the credential move was sound; the guard's reach and the token's scope were inherited

## Problem

#8209 O10 replaced the soleur-ai App key in Doppler `soleur/prd_terraform` with the
`EVICTED_SEE_ADR_241` sentinel. `apply-github-infra.yml` still fetched that key for its post-apply
verify, so every ruleset apply failed. PR #9360 moved the verify to the Tier-B soleur-infra App via
the shared mint composite, moved `entrypoint_audit` to `github.token`, and tightened census row G4e.
The workflow change was correct. A 10-seat review then found that the *surrounding* claims were
inherited rather than measured:

1. **Token scope from the plan's sentence, not GitHub's table.** The plan said "rulesets'
   `bypass_actors` are hidden from read tokens", so it minted `administration:write` on both
   `soleur` and `soleur-marketplace`. GitHub's App-permission table says
   `GET /repos/{o}/{r}/rulesets/{id}` needs **Metadata: read**; `bypass_actors` is returned only to
   a writer, and only the *marketplace* probe reads it. Correct scope: write on
   `soleur-marketplace` only, `github.token` for the two `soleur` probes.
2. **A guard named for a property, assembled for a token.** G4e claimed "the key is read from
   Doppler by exactly one step, none in a Tier-B job". It matched only
   `doppler secrets get GITHUB_APP_PRIVATE_KEY` in one spelling, counted steps rather than reads,
   treated composites as never-Tier-B (a composite runs in its caller's job), read an unresolvable
   `environment:` expression as safe, and compared names case-sensitively. Each was a clean
   bypass with zero census rows red.
3. **The identity change credited to the wrong event.** The README, `model.c4` and #9361 said
   "#9360 moves the CI apply to soleur-infra". Terraform had run as soleur-infra through the
   loader since O3 (run 36539258756); #9360 moved only the verify. A reader would conclude
   reverting #9360 restores manifest writes. It would not.
4. **A file-indexed stale-claim sweep.** `infra/github/README.md` Phase 0 still told an operator
   to verify `GITHUB_APP_PRIVATE_KEY` in `prd_terraform` is non-empty (the 19-byte sentinel
   passes) and to "mirror from prd" if not — re-creating the branch-readable copy #8209 exists to
   delete. Three seats found it; the author's sweep had stopped at the files the diff opened.

## Solution

- Mint scope measured against `docs.github.com/.../permissions-required-for-github-apps`, then
  narrowed; a check before the mint refuses a loader on its legacy arm or with a different
  installation id; the revoke warns on a non-204; the apply step names the known gap (#9361) as an
  `::error::` instead of an unexplained 409.
- G4e: one walker; a matcher for global/flag-first/quoted spellings; reads counted; a tier
  predicate over every `environment:` form (unresolvable = maybe Tier B, the refusing direction);
  composites take their callers' environments; unparsed workflows red the row; the row states that
  `doppler run` injection is out of scope (it delivers the sentinel inertly). Nine rows, each
  asserting its CAUSE on the detail line; each new piece mutation-proven in a detached worktree.
- A shape suite for the composite's third consumer (its two siblings had one; this one had none).
- Superseded banners on every live false claim, and the identity change re-credited to O3.

## Key Insight

When a PR *moves* a credential, the move is the part everyone checks. The defects live in the
three things carried along with it, each copied from the plan's prose: the token's **scope**
(re-derive it per endpoint from the vendor's permission table), the guard's **reach** (enumerate
every path to the sink, then compare to the row's name), and the **attribution** of what changed
(read the run log that shows when the identity actually changed). A plan sentence explaining
*why* a scope is needed is a claim about an API — measure it before it becomes a `with:` value.

## Session Errors

1. **Forwarded: `GET /user/installations/166065653/repositories` returned 403; lefthook not on
   PATH.** Recovery: coverage inferred from a Tier-B run; commits relied on CI.
   **Prevention:** the mint step now asserts coverage at run time; no local action needed.
2. **The issue-filing hook rejected the follow-up 3 times** (a `User-Impact:` naming no taxonomy
   surface; a non-numeric `Fix-Size: ~12`; a `sed` fix chained with `gh issue create` evaluated
   before the edit). Recovery: read `.claude/hooks/lib/user-surface-taxonomy.txt`, wrote a numeric
   size, ran the edit and the filing as separate calls. **Prevention:** before filing, grep the
   taxonomy for a surface noun; never chain a body edit with the filing in one Bash call.
3. **A scripted splice duplicated ~1,000 lines of the census** — the end anchor
   `# ── Guard 2 ──` occurs twice and `s.index()` returned the earlier one, before the start
   anchor. Recovery: `git restore --source=HEAD --staged --worktree`, then one script asserting
   every anchor unique AND `end > start`. **Prevention:** a splice asserts `count == 1` for both
   anchors and `start < end` before writing; `str.replace` assertions do not cover `index()`.
4. **An equivalent mutant** — the env-leak row added a second key to a step that already holds the
   token, so the holder set did not change. Recovery: targeted a third step.
   **Prevention:** for a set-membership pin, a mutant must add a NEW member, not a duplicate.
5. **A mutation run outside a git checkout** — the census derives its corpus from
   `git ls-files`, so the copy failed on everything. Recovery: `git worktree add --detach` sandbox.
   **Prevention:** sandbox repo-deriving suites in a detached worktree, never a bare copy.
6. **A `/proc` kill loop matched its own shell** (exit 144), because the loop's own cmdline
   contained `test-all.sh`. Recovery: none needed. **Prevention:** exclude `$$` and its ancestors,
   or use `proc.sh kill_mine`.
7. **The affected gate was queued, then refused (rc=4)** — editing `scripts/test-all.sh` degrades
   `--affected` to full, and two sibling full runs were in flight. Recovery: the operator chose CI.
   **Prevention:** when a diff registers a suite in the runner, expect the degraded-full refusal
   and plan on `TEST_GROUP=affected` or CI from the start.
8. **`workflow-file-size.test.ts` red** — deleting the inline mint removed the only
   `§legacy-app-key-evicted` rationale pointer. Recovery: re-anchored the pointer on the new token
   comment. **Prevention:** before deleting a block, grep it for `# Rationale:` pointers.
9. **An inherited framing ("#9360 moves the apply to soleur-infra") written into 3 artifacts.**
   Recovery: re-credited to O3 from run 36539258756. **Prevention:** for an identity/attribution
   claim, cite the run log that shows the change.
10. **A file-indexed sweep missed live false claims** (README Phase 0/§1/§5c, ADR-032).
    Recovery: superseded banners. **Prevention:** sweep by the claim's subject repo-wide.
11. **A guard named broader than its assembly (G4e).** Recovery: as above.
    **Prevention:** the structural-enumeration seat, before the panel, on any guard-shaped diff.
12. **A token scope copied from the plan's rationale.** Recovery: measured against GitHub's
    permission table and narrowed. **Prevention:** routed to plan-sharp-edges (below).

## Tags

category: security-issues
module: ci-credentials
