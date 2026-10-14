# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-16-fix-dependabot-dual-lockfile-drain-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- `learnings-researcher` ran ~106 min and returned after the plan was committed; it was reported as
  failed in an interim summary, which was premature. Its result was reviewed and folded in as commit
  `8c9ea452a`. One finding was materially new (see Decisions, sharp bump / `--omit=dev` post-mortem).
- One self-inflicted verification error, caught and corrected during deepen: the "Dockerfile contains
  no bun" claim was probed with an unbounded `grep -ci` and returned CONTRADICTED at 6 hits — all
  `bun` inside `bundle`. True under `grep -ciowE` (0 hits). Both this and the C4 `model.c4` claim now
  cite the word-bounded command actually run.

### Decisions
- Chose **direction 2** — the npm lockfile becomes the single lockfile of record — extended to both
  dual-lockfile directories. Direction 3 fails the stated acceptance bar (PR stays red, still needs a
  human regeneration) and would ship RED on day one against drift that already exists. Decisive
  rationale: Dependabot security-scans only the npm lockfile, so dropping `bun.lock` costs zero
  coverage while dropping `package-lock.json` would eliminate it. Converting the root as well
  *removed* mechanism: it dissolves a JSONC parser, a two-key-shape extractor, an allowlist, and the
  surgical `bun.lock` resync that Part 2 would otherwise require.
- Reversed the service-worker CodeQL alert from fix to **dismiss**. `ServiceWorker.postMessage()` has
  no `targetOrigin`; only same-origin in-scope clients reach the handler; worst case equals the app's
  own Reload button. A wrong origin check would silently lock every user out of app updates with no
  feedback, and `event.origin` is not uniformly populated across browsers. Dismissal carries a
  recorded reason plus a handler-scope regression assertion.
- Cut the scheduled follow-through probe in favour of in-session verification. Three findings
  converged: `GITHUB_TOKEN` cannot read the Dependabot alerts API, no `permissions:` key grants it,
  and a failing probe self-erases after 30 business days without reaching a human.
- Install-site inventory corrected twice under review: 15 → 14 → 16 converting sites plus 4
  pre-existing. The last correction matters most — `web-platform-build` already runs bare `npm ci` on
  fork PRs, so the install-script execution the plan framed as a *new* risk is live today, turning a
  defensive flag into an actual remediation.
- Folded in a production post-mortem closing a regeneration hazard: a prior Dependabot `sharp` bump
  across the `^0.34.x` → `^0.35.x` boundary made npm re-resolve the top-level copy as dev-only;
  `npm ci --omit=dev` in the Docker runner stage then installed none and production deploys were
  skipped 3h+. Fix is on `main` (`dependencies.sharp: ^0.35.0`, lockfile `dev: false, optional:
  false`), but this plan regenerates that lockfile across eleven bumps and nothing asserted the
  classification survives. `tsc`, vitest, and the deps-stage build are all blind to it; only the
  `--omit=dev` runner stage reveals it. Added AC13b, T21b, a risk row, and two sharp edges.

### Components Invoked
- Skills: `soleur:plan`, `soleur:deepen-plan`
- Agents: `Explore` (x2 — CI install-path map, C4 model enumeration), `repo-research-analyst`,
  `learnings-researcher`, `framework-docs-researcher`, `general-purpose` (dependency feasibility),
  `functional-discovery`, `soleur:engineering:cto`, `soleur:product:cpo`, `kieran-rails-reviewer`,
  `code-simplicity-reviewer`, `architecture-strategist`, `spec-flow-analyzer`, scoped `model: fable`
  advisor consult (ADR-083 Step 4.5)
- Gates run: `lint-guard-contract.py` (2 guard entries, exit 0), `lint-infra-no-human-steps.py` (OK),
  deepen-plan halts 4.5, 4.6, 4.7, 4.8, 4.9, 4.10, 4.11, 4.55
- Live APIs queried: `gh api dependabot/alerts`, `gh api code-scanning/alerts`, `gh pr list`,
  `gh issue view`, `gh label list`, `gh api actions/runs/.../jobs`

## Collision Gate (Step 0a.5)
- `#7084` OPEN, `closed_by: []`, no `linked:issue` PRs.
- Body probe surfaced merged PR #7082 (2026-07-30). Path intersection non-empty but over-matched by
  construction (any lockfile PR touches those paths). #7082 `closes: []` and its body states the
  defect is "a standing defect, not a property of these four bumps... Tracked in #7084" — it applied
  the manual workaround, not the fix. 39 live alerts confirm the fix never landed. Disposition:
  citation, continue.
- Post-planning re-probe: plan frontmatter `closes: 7084` — no new refs beyond those already cleared.
