# Decision challenges: feat-one-shot-12757-cron-gitconfig-containment

Issue #12757 (Ref #9601). Plan: `knowledge-base/project/plans/2026-11-16-fix-cron-gitconfig-containment-plan.md`.

The binding scope came from the CTO agent before planning (Ruled by CTO agent, 2026-11-16). The rows below are
the technical forks the plan found while planning. Each was put to `soleur:engineering:cto` with the evidence, and
the operator was not asked.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| F-A Pin placement: literal keys at each site, or one shared constant | technical | Ruled by CTO agent, 2026-11-16: one frozen constant `CRON_GIT_CONFIG_PIN = { GIT_CONFIG_GLOBAL: AGENT_GIT_GLOBAL_CONFIG, GIT_CONFIG_NOSYSTEM: "1" }`, spread LAST in every cron env literal. It is applied again after the `buildSpawnEnv` spread in `spawnClaudeEval`, in `spawnSimple` (`{ ...(opts.env ?? process.env), ...CRON_GIT_CONFIG_PIN }`), and in each local `spawnGit` helper. Sites already pinned to `/dev/null` keep `/dev/null` - a pin applied at the chokepoint cannot be dropped by one cron, and the census checks one symbol. |
| F-B Population: only the `HOME:` literals, or also git spawns that pass no env | technical | Ruled by CTO agent, 2026-11-16: include the git spawns that pass no env: the `spawnSimple` default env (substrate clone and set-url; event-ship-merge), `cron-strategy-review.ts` clone, and the `spawnGit` helpers in compound-promote, content-publisher, rule-prune and weekly-analytics - these are the server-side clones whose URL carries the token, which a `url.insteadOf` planted in run N would redirect in run N+1. |
| F-C Census test shape | technical | Ruled by CTO agent, 2026-11-16: (1) a behavioural `spawnClaudeEval` row, including a `buildSpawnEnv` that sets a different `GIT_CONFIG_GLOBAL` (the pin wins); (2) a static census of the `HOME:` literals with a floor of 27 sites and a fixed set of 23 files; (3) a behavioural `spawnSimple` row with no env, an env without the pin, and an env that overrides it; (4) a static sweep of every git spawn site in `server/inngest/**`, with a floor and a fixed file set - a census keyed only on `HOME:` cannot see a site that passes no env. |
| F-D Normalisation semantics in `gitVerbReason` | technical | Ruled by CTO agent, 2026-11-16: SUPERSEDED by A1 below. Originally: check the raw tokens and the normalised split and deny if either denies. Raw runs first, so its reason wins when both deny. The verb also comes from the normalised view. Over-denying commit messages (`-m "use -a flag"`) is accepted - the normalised-only form would reopen `git push --repo "origin evil"`. A wrong deny fails closed and the agent can reword; a missed deny cannot be recovered. |
| F-E `gh api` dot-segment check reads raw `tokens[1]` | technical | Ruled by CTO agent, 2026-11-16: SUPERSEDED by A1 below. Originally: fold it in. Take the verb and subcommand from the normalised view, and scan both views for dot segments - the allowlist matches the normalised text, and the only thing stopping this today is cobra's parser. `hasDotSegment` already splits on whitespace, so this adds no false deny. |
| F-F ADR placement | technical | Ruled by CTO agent, 2026-11-16: add a dated amendment to ADR-033 (invariant: every cron child-process env carries `CRON_GIT_CONFIG_PIN` or a stricter `/dev/null` pin, at the chokepoints, enforced by the census; and I7(a) Write/Edit self-protection now covers `.gitconfig` and `.config/git`). Do not amend ADR-287 - ADR-033 is the spawn ADR. The #9600 invariant covers only agent sessions. |
| F-G Where the constant lives | technical | Ruled by CTO agent, 2026-11-16: `server/host-git.ts`, beside `AGENT_GIT_GLOBAL_CONFIG` - host-git is a deliberate leaf, every spawn site can import it without pulling in `_cron-shared.ts`'s Octokit graph, and the path is never retyped. |
| F-H `filingShape` reads raw positionals | technical | Ruled by CTO agent, 2026-11-16: SUPERSEDED by A1 below. Originally: fold it in. Compute `filingShape` on both views. If they differ, deny with an irregular-whitespace reason. Otherwise run `filingJustificationReason` once, on the raw tokens - running the justification on the split view would cut a quoted `--body` down to its first word and deny honest filings. A shape mismatch only happens for a command gh rejects anyway. |
| F-D detail: which reason is reported when both views deny | technical | Ruled by CTO agent, 2026-11-16: SUPERSEDED by A1 below (one rule, one reason). Originally: raw first, stop at the first deny, and pin the order with one test row - existing reason-text assertions stay stable. |
| `content-vendor-drift` `spawnGit` spreads caller env after its `/dev/null` keys | technical | Ruled by CTO agent, 2026-11-16: spread the `/dev/null` keys last - small extra hardening (ruling F-A note). No caller passes an env today, so behaviour is unchanged. |
| Census count correction (26, not 27) | technical | Ruled by CTO agent, 2026-11-16: assert exactly 26 sites and an identical 23-file set, not a floor of 27 - the 27 in the brief was a miscount (`git grep -n "HOME: process.env.HOME" -- apps/web-platform/server` gives 26 in 23 files), and an exact count with set identity is the stricter gate because a floor would let a new unpinned literal pass. (R1) |
| CPO condition "trigger one cron after merge" vs standing constraint "no prod writes" | operator (production-mutating) | Action: a manual post-merge cron trigger. Not authorised and not requested: the standing constraint wins, and the condition is met by reading the next scheduled agent-git run (plan AC14). |
| Brand-survival threshold | technical | Ruled by CTO agent, 2026-11-16: keep `single-user incident` - a persisted agent-planted `~/.gitconfig` gives code execution and can redirect a token-bearing clone across runs, the same class as the #9601 host-side git hardening; it has no multi-tenant fan-out path, so it does not go to a wider tier. (R2) |
| A1 Advisor: replace the both-views design with a command-word shape rule | technical | Ruled by CTO agent, 2026-11-16: accept, and amend binding IN item 4 - when the normalised first word is `git`/`gh`, require raw git `tokens[0..1]`, or gh `tokens[0..2]` (`tokens[0..1]` for `gh api`), to match `^[A-Za-z0-9-]+$`, with `tokens[0]` exactly the verb, else deny. Existing raw-token rules then run unchanged. This supersedes F-D, F-E and F-H. Every git/gh allowlist line is a plain `git <sub>`/`gh <group> <verb>`/`gh api <path>`, so the two views agree; `--repo "origin evil"` stays denied, and the `-m "use -a flag"` over-deny goes away. |
| A2 Advisor: drop the per-literal spreads, keep only the chokepoints | technical | Ruled by CTO agent, 2026-11-16: reject - keep both. The 8 Class B envs and follow-through-monitor's direct `gh` calls never reach a chokepoint, and some run git (the vendor-drift classifier's `git merge-base`); the chokepoints only stop a cron from dropping the pin. |
| A3 Advisor: protect the trust root the pin points at | technical | Ruled by CTO agent, 2026-11-16: option (a) - add `(^\|\/)usr\/local\/share\/soleur(\/\|$)` to `WRITE_PROTECTED_PATTERNS`, plus a test row that imports `AGENT_GIT_GLOBAL_CONFIG` and asserts the pattern matches it. Root 0644 ownership is today's protection, but a later `chown -R` would remove it silently; the hook cannot import the constant, so the test is the drift guard. |
| R3 cidr-refresh `runProc("git", …)` sites missed by the row 4 matcher | technical | Ruled by CTO agent, 2026-11-16: add `cron-github-cidr-refresh.ts:123` and `:204` to Class C with a call-site pin, widen row 4 to any callee (`\b[A-Za-z_$][\w$]*\(\s*"git"\s*,`, an exact set of 15 pairs), and add a guard that fails on any `"git"` literal outside the matched set - `runProc` spreads `opts` with no env default, and a callee-specific matcher cannot see it. |
| G1 ADR-287 K2 text made false by A1 | technical | Ruled by CTO agent, 2026-11-16: add a one-line dated cross-reference in ADR-287 addendum item 2 ("now denied by containment (#12757); framing them is redundant but harmless") and fix the framing-test K2 comment; do not change ADR-287's decisions - F-F meant no decision or numbering change, and a false statement in the ADR the hook author reads is worse than a pointer. |
| G2 Missing or unreadable identity file is silent | technical | Ruled by CTO agent, 2026-11-16: add a once-per-process `accessSync(AGENT_GIT_GLOBAL_CONFIG, R_OK)` probe used at both chokepoints, non-blocking, reported through `reportSilentFallback` (op `cron-git-config-pin`), with a test row - git treats a missing global as empty, and the agent's recovery paths are denied. The plan keeps `host-git.ts` a leaf: the probe returns a boolean, and the substrate, which already imports `@/server/observability`, reports it. |
| G3 XDG `ignore`/`attributes` not covered by the pin | technical | Ruled by CTO agent, 2026-11-16: correct the "inert" text, record the residual in ADR-033, and add a real-git row that asserts Guard 1 denies the write; reject an `XDG_CONFIG_HOME` pin - it could break `gh`/`claude` XDG config, and those two files cannot execute commands. Revisit when the Dockerfile is in scope. |
| G4 Founder-workspace git spawns outside `server/inngest/` | technical | Ruled by CTO agent, 2026-11-16: correct the plan sentence, record the residual in ADR-033, and have the work/ship phase file one follow-up issue under #9601 (re-evaluation criterion, milestone, link to #12757); do not pull it into this PR - it is a different trust surface with no harness here, and the PR is capped at one. |
| G5 Invariant scope and gh/bash spawns | technical | Ruled by CTO agent, 2026-11-16: scope the invariant to git-capable children (git, gh, bash, claude), name the node self-test probes as excluded, and extend census row 4c to `gh`/`bash` first-argument literals requiring an explicit pinned env - an invariant that is false on day one is worse than a narrower true one. |
| G6 Census implementation | technical | Ruled by CTO agent, 2026-11-16: use the TypeScript compiler API over `server/inngest/**` and a per-file count map with diff-style messages; reject a global count plus a file set - regex plus brace matching gives false negatives on a security gate, and a per-file map names the file that drifted. |
| G7 Verb rows on both allowlists | technical | Ruled by CTO agent, 2026-11-16: keep five verbs × 4 forms × 2 allowlists, and run the other rows once on roadmap-review - ask 4 names both allowlists verbatim; the rows are cheap and guard a future allowlist-aware rule. |

## Plan review (2026-11-16, headless)

The panel was dhh-rails-reviewer, kieran-rails-reviewer, code-simplicity-reviewer, architecture-strategist,
spec-flow-analyzer, and the CTO with a devex lens. Mechanical findings were applied to the plan, including these:
- Kieran's P0: NBSP-led `git` is trimmed by `splitSegments`, so those rows were replaced with between-word NBSP forms.
- The position-2 gh row.
- The per-segment anti-vacuity check.
- Counts reconciled to 15 pairs and 22 lines.
- A `.ts`-only sweep.
- Path normalisation.
- `opts.env` removed from the helper types.
- The vendor-drift parameter dropped.
- `buildPublisherEnv` folded into one literal.
- Row 5 moved to a deterministic alias/identity fixture.
- Deny-reason position, escaping and the `gh api` hint.
- AC14 made falsifiable.
- A partial revert path.
- Symbol anchors.

Technical forks went to the CTO (G1-G7 above). These rows record the classification:

| Item | Class | Ruling |
|------|-------|--------|
| DHH: plan length (about 1,000 lines for about 150 production lines) is ceremony | taste | Kept. The `single-user incident` threshold and the Guard Contract gate require the mutation matrices and provenance. The zero-width row, the count assertions, the census exceptions and the hand-checked assertions were cut as mechanical simplifications. |
