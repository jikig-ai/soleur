# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-10-07-fix-vendored-sdk-bwrap-argv-reorder-plan.md
- Status: complete

### Errors
None blocking. Non-blocking notes: (a) an early candidate-plan selector returned exit 2 while scanning (resolved by deriving a fresh plan path); (b) several searches on the minified/native SDK artifact produced no text match — resolved via `strings`-level inspection of the binary's embedded builder.

### Decisions
- **Central finding (changes the issue's premise):** the vendored CLI 2.1.284 binary (`node_modules/@anthropic-ai/claude-agent-sdk-linux-x64/claude`, spawned by `@anthropic-ai/claude-agent-sdk@0.3.284`) already implements deny-then-restore ordering — its embedded builder emits `--tmpfs <deny landing>` then rw `--bind` restores of covered `allowWrite` paths (`Re-bound write path wiped by denyRead tmpfs`) and ro restores of `allowWithinDeny` (`allowRead`) paths. Issue scope item 1 (dependency-patch mechanism) is therefore descoped with justification, contingent on the Phase-3 in-image capture audit.
- **Mechanism:** revert `buildAgentSandboxConfig` to broad `denyRead: [workspacesRoot(), c4StagingRoot, "/proc", ...denyReadExtra]` — the parent tmpfs masks present *and future* siblings, closing the TOCTOU structurally — plus `allowRead: [workspacePath]` for the `readOnly` support persona (which a broad deny would otherwise blind).
- **Dispatch vs. issue reconciliation:** the dispatch's literal "move sibling deny mounts before the workspace bind" cannot close the TOCTOU under continued enumeration; the plan implements the property-level reading (covering deny tmpfs precedes the workspace's surviving rw bind) and corrects the "token-order-only" fixture-diff expectation to the additive shape (new `--tmpfs` on the deterministic capture root + restore bind + literal `prepDirs` entry).
- **Brand-survival threshold:** `single-user incident` (cross-tenant read); `requires_cpo_signoff: true`. Guard Contract shipped for a new committed-fixture ordering pin; all deepen-plan halts (4.6–4.12) passed, including `lint-guard-contract.py` green and mechanical Scope-Check verification.
- **Contingency documented, not planned:** if the capture audit falsifies the vendor ordering (or shows ws-internal mounts — `/dev/null` masks, `.claude` self-binds — shadowed by the restore bind), the fallback is argv rewriting in the production bwrap shim — flagged as a materially different diff requiring re-planning.

### Components Invoked
- `soleur:plan` (run inline per the skill's harness instructions — no direct skill tool) — full phase sequence: skeleton, premise validation, property/cut lists, research (source + vendored binary + fixture + ADRs), code-review overlap check (88 issues, zero file overlaps), Scope Check, Domain Review, User-Brand Impact, GDPR inline advisory, Observability (with blind-surface probes), ADR-075 amendment deliverable + C4 no-impact enumeration, Guard Contract, SpecFlow-style pass, sharp-edges verification, plan review + `decision-challenges.md`, `tasks.md`, commit + push (commits `a3d1553995`, `dce008a9ca` on `feat-one-shot-5862-bwrap-argv-reorder`).
- `soleur:deepen-plan` (run inline on the plan path) — mechanical gates verified (User-Brand Impact, Observability, PAT sweep, Scope Check, Guard Contract lint, PAT/label/citation checks, legal-register status-flip sweep); conditional gates (network-outage, downtime, UI wireframe, encryption) correctly unfired; Enhancement Summary + audit broadening applied and propagated to `tasks.md`.

## Work Phase (tally: seats=87→84 used=3; ci_cycles=1 local; agent_rounds=2)
- **T1 RED**: rewrote `agent-runner-helpers.test.ts` to the constant-deny contract; renamed `agent-sandbox-sibling-deny.test.ts` → `agent-sandbox-tenant-deny.test.ts` and rewrote it; added the committed-fixture ordering pin + 5-row mutation matrix to `sandbox-canary.test.ts`; added the live TOCTOU regression + `spawnSandboxed`/`waitForFile` helper. First run: 16 failures — all the intended RED reasons (enumerated deny shape, exported enumerator, missing `allowRead`, fixture pin pending re-capture); one assertion-scoping bug in the TOCTOU test (`cat` error text contains the sibling name — scoped `ls` output at the `__CAT__` marker) fixed and re-run green.
- **T2 GREEN**: `buildAgentSandboxConfig` emits the constant parent deny + `allowRead` restore arm; `enumerateSiblingDenyPaths`/`safeRealpath`/`degraded` deleted; log `op:"tenant-deny"`; header + `cc-dispatcher.ts`/`sandbox-canary.mjs` comment sweeps. Config-shape suites green; ordering pin stayed RED pre-capture as designed.
- **T3 in-image**: `SANDBOX_CANARY_MODE=capture` on `node:22-slim` → `captured` (tokenCount 120, SDK 0.3.284); audit confirmed covering `--tmpfs /tmp/soleur-sandbox-canary` at argv[21] with restores at 23/26 and all `/dev/null` masks + `.cc-writes` bind post-restore; `--verify` → `verify_ok`.
- **T4**: ADR-075 amended `accepted-with-residual` → `accepted` (addendum 2026-10-07).
- **T5**: 6 touched suites green (189 pass, 3 skip); `tsc --noEmit` clean.
- **Phase-2 exit**: GDPR gate — zero canonical-regex hits, no mandatory-check triggers. Affected-test gate queued behind 3 sibling `test-all` runs (advisory lock position 3) at commit time; pending.
- Commit `466e162f98`; pushed; PR #9709 body finalized (still draft pending gate + review).
