# Decision Challenges — feat-one-shot-7946-7947-sentry-org-token-and-snapshot-redaction

Persisted headless per ADR-084. Each entry is a challenge to the operator's stated direction,
surfaced rather than applied. `ship` Phase 6 renders these into the PR body and files an
`action-required` issue.

---

## DC-1 — Split #7946 and #7947 into two PRs, shipping #7946 first

**Class:** user-challenge (challenges the operator's stated direction — the pipeline brief scopes
both issues to one one-shot run against draft PR #7975).

**Raised by:** three of the five review lenses independently — the Step 4.5 scoped strong-model
consult, the CTO domain advisory's second risk, and the architecture-strategist review, which
supplied the measured evidence below.

**The operator's direction (the default, and what the plan implements):** implement and ship #7946
and #7947 together in one PR.

**Measured evidence that the coupling claim is false** (verified in this worktree, not asserted):

- Thirteen of the sixteen followthrough files carry the ADR-202 xtrace refusal with
  `[ -n "${SENTRY_AUTH_TOKEN:+x}" ]` in the predicate, so the rename is a two-guard edit per file,
  not a rename.
- `scripts/lint-shell-trace-credential-refusal-d.baseline.txt` carries 21 `scripts/followthroughs/`
  entries and states that `--changed` bypasses it. CI runs the lint that way, so touching those
  files obliges a Rule D remediation across all of them. **This is the single largest cost in the
  #7946 half and it exists only because of the rename.**
- The cutover mutates state `git revert` does not touch: GitHub issue-body directives, a live
  `gh secret set`, and a live Sentry integration.

**What the challenge says:** the plan claims the two halves are safely coupled because "the
credential commits are ordered contiguously and the revocation is excluded, so the #7946 half is
independently revertable". That claim holds only for tracked files, and only under a merge-commit
or rebase strategy — **a squash merge collapses it entirely**. It is never true for the
out-of-repo state #7946 mutates: the minted Sentry Internal Integration, the new GitHub repo
secret, and the rewritten `secrets=` directives in open `follow-through` tracker issues. Reverting
the PR because the new PreToolUse hook misfires on a legitimate `agent-browser snapshot` would
drag the credential cutover back with it, leaving the sweeper pointed at a secret whose migration
has been reverted in code but not in GitHub.

**What the plan does instead, and why it is defensible:** the two halves are coupled in the other
direction as well, and that coupling is the argument for keeping them together. Phase 3.1's
Playwright mint of the Sentry integration **is a browser login**, which is precisely the #7947
hazard, performed inside the same run. The plan now requires the mint to be executed under
the #7947 discipline — screenshots not snapshots, shell-expanded credentials, token captured to a file
and shredded — which makes the mint a live rehearsal of the guard rather than a violation of it.
Splitting would either perform the mint before the guard exists, or delay #7946 behind #7947.

**If the operator takes the challenge:** ship #7946 first (it is the smaller blast radius and the
one with the standing exposure), land #7947 against a second PR, and move the mint after #7947 so
the rehearsal argument is preserved in the other order.

**Residual risk if the challenge is declined:** a revert of either half drags the other, and the
out-of-repo state does not revert with it. Mitigated but not removed by: the one-cycle
compatibility shim in the sweeper env, and the exclusion of the personal-token revocation from
this PR.

---

## DC-2 — A stateless input-side deny on MCP fill tools would close an adjacent hazard this plan leaves open

**Class:** taste (a scope-addition proposal, not a correction to what the plan does).

**Raised by:** the Step 4.5 scoped strong-model consult.

**The proposal:** rather than trying to gate `mcp__playwright__browser_snapshot` (which takes no
arguments, so its predicate must be reconstructed from side-channel state), gate the **input**
side. `browser_type` and `browser_fill_form` do take arguments. A PreToolUse deny on those when
the target element is password-typed, or when the supplied text equals a loaded secret environment
value, needs no session state at all.

**Why it is not folded in:** it addresses a **different hazard**. #7947's mechanism is a value the
agent never supplied — a browser password manager's autofill. An input-side deny cannot see that
value and does not touch it. What the input-side deny would close is the adjacent problem the
consult surfaced separately: an agent-typed credential is already in the transcript as the
tool-call argument, before any snapshot happens, and no snapshot redaction can help it. That is
real, it is arguably higher severity, and it is genuinely out of #7947's recorded scope.

**Plan response:** Phase 0.1 measures the `browser_type` echo as its own row with its own verdict,
and the plan directs that a reproduction be filed as its own issue rather than widening this one.
This entry records the proposed mechanism so the issue that gets filed inherits it.

---

## DC-3 — Mint a fourth Sentry integration, or reuse the existing read-only one

**Class:** taste (two senior engineering lenses reached opposite conclusions on the same measured
facts; neither is a correctness error).

**Raised by:** the architecture-strategist review, against the CTO domain advisory's ruling.

**The fork.** If Phase 0.2 shows all four measured endpoints return 200 under `inline-read-prd`'s
`[event:read, org:read]`, the minimum-scope credential already exists.

**The CTO lens (what the plan follows):** mint the dedicated `followthroughs-read-prd` anyway. The
deciding factor is the store and the independence of the rotation domain, not the permission list.
ADR-031 places `SENTRY_ISSUE_RO_TOKEN` in Doppler `soleur/prd` with a stated reason — it is consumed
by an inline CLI under `doppler run` — while the sweeper is a GitHub Actions workflow needing a repo
secret. Reuse means copying that token into GitHub secrets, contradicting a reasoned ADR amendment,
doubling blast radius, and coupling two rotation domains so a CI compromise darkens no-SSH agent
issue debugging and vice versa.

**The architecture lens:** mint nothing. A fourth credential class whose scope set is identical to a
third permanently widens the rotation surface this PR exists to narrow, and the store objection is
answerable by storing the same integration's token in both places.

**Plan response.** Phase 3.1 follows the CTO lens and names explicitly what would flip it: if the
ADR-031 amendment concludes the two consumers should share one rotation domain, reuse and store the
existing token. The dissent is recorded here so the fork is decided by argument rather than by sunk
effort at implementation time.

---

## DC-1 — RESOLUTION: challenge ACCEPTED (pipeline runner, 2026-09-09)

**Decided by:** the one-shot pipeline runner, as a technical fork
(`hr-technical-fork-is-not-an-operator-question`). The "one PR" direction DC-1 challenges
originated in the routing brief the runner itself constructed, not in the operator's request —
the operator named three issues and set no PR structure — so revising it needs no operator gate.

**Decision:** split. **#7947 ships first**, in PR #7975 (this worktree). #7946 follows in its own
worktree and PR.

**Reasoning, in the order it was decisive:**

1. **#7946 Phase 3 is gated on the operator; #7947 must not be.** Phase 3.1 mints a live Sentry
   Internal Integration, sets a live GitHub repo secret, and rewrites directives in open tracker
   issues. Those are prod writes requiring explicit per-command authorization
   (`hr-menu-option-ack-not-prod-write-auth`). Coupled, the #7947 guard cannot merge until that
   authorization arrives. #7947 protects every Soleur operator on their own machine against a
   credential rendered into their transcript; parking it behind a vendor-console gate is the
   worse failure. This argument is independent of DC-1's own and is the deciding one.
2. **The revert-independence claim is false here.** `gh repo view` confirms
   `squashMergeAllowed: true`. DC-1 concedes the contiguous-commit defense "collapses entirely"
   under squash. It never covered the out-of-repo state at all.
3. **The rehearsal argument survives the split — strengthened.** Its point is that the Phase 3.1
   mint is itself a browser login and so a live exercise of the #7947 guard. Shipping #7947
   first puts that guard in `main` BEFORE the mint runs, rather than merely in the same PR.
   DC-1's own "if taken" branch proposed #7946-first plus moving the mint after #7947; ordering
   #7947 first reaches the same end state without moving anything, because the plan's phase
   order already places #7947 ahead.

**Cost, stated honestly:** the pipeline tail (work → review → QA → compound → ship) now runs
twice rather than once. That is a real increase in the operator's Anthropic spend, accepted for
the unblocking in (1) and the revert-safety in (2).

**What this does NOT change:** the plan, its phases, its guard contract, and DC-2/DC-3 all stand
as written. The split is a delivery-boundary change, not a re-plan. `closes:` for PR #7975
narrows to `[7947]`; #7946 carries its own `closes: [7946]` on the follow-on PR.

## DC-3 — RESOLUTION: decided by measurement (2026-09-11, #7946 / #7993)

**Reading:** `inline-read-prd`'s `[event:read, org:read]` returns **403** on the cron check-in
endpoint three followthroughs call (`/api/0/organizations/{org}/monitors/{slug}/checkins/`),
with a known-granted control at 200 on the same URL; the scope class is confirmed from Sentry's
`MonitorEndpoint` permission source and the public reference. The reuse arm's premise ("all
four endpoints 200 under the two-scope set") is false, so there is nothing to reuse without
widening a shared credential — which both lenses agreed is never done.

**Decision:** mint the dedicated Internal Integration `actions-read-prd` at
`[event:read, org:read, project:read]` (minted 2026-09-11; scopes read back exactly). The
architecture lens's residual ("identical scope set") dissolves with its premise: `project:read`
is the delta, and the boot-trail's project-events endpoint needs the same delta. The full
record, the rejected IaC-token-under-new-name shape, and the store discriminator are in
`ADR-031-sentry-as-iac.md` (2026-09-11 amendment). Measurement table:
`knowledge-base/project/specs/feat-one-shot-7946-sentry-org-token-retire/phase-0-scope-probe.md`.
Closes the open limb of #7993.
