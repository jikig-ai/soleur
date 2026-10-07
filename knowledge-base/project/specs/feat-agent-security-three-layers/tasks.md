# Tasks: agent security hardening — slice 1

Plan: `knowledge-base/project/plans/2026-10-06-feat-agent-security-hardening-slice-1-plan.md`. Epic #9601. Three PRs, in order: PR 1 (W1) on this branch, PR 2 (W2) and PR 3 (W3) on their own branches cut after PR 1 merges. PR bodies use `Ref #9601`.

## PR 1 — W1 credential deny (hosted sandbox)

### 1. Phase 0 measurements (gate for PR 1)

- 1.1 Build the throwaway query with `sandbox.credentials.envVars` deny entries for both auth variables; set sentinel probe values in the child env.
  - 1.1.1 Run `printenv` for each variable, a credentials-file read and a workspace `.env` read inside the sandbox; confirm the CLI turn still completes.
  - 1.1.2 Capture the bwrap argv; record whether the deny appears as `--unsetenv` in it.
- 1.2 Run the customer hook-decision matrix with a stub hook answering `ask`: interactive, `claude -p`, `bypassPermissions`, subagent, and the hosted SDK with `canUseTool` (non-gating for PR 1, gating for PR 2).
- 1.3 Write results and the exact commands to `knowledge-base/project/specs/feat-agent-security-three-layers/phase-0-measurements.md`.

### 2. Implementation

- 2.1 Export `AGENT_AUTH_ENV_VARS` (frozen `as const` tuple) from the dependency-free `apps/web-platform/server/agent-auth-env-vars.ts`; `agent-env.ts` imports the two names. (Shipped there, not in `agent-env.ts`, so the sandbox config does not pull `agent-env`'s graph.)
- 2.2 Add the typed `credentials` field to `AgentSandboxConfig` and the deny block to `buildAgentSandboxConfig` in `agent-runner-sandbox-config.ts`, with the comment naming why service tokens and `GH_TOKEN` are not denied.
- 2.3 Add a separate `## Credentials` directive (`CREDENTIALS_PROMPT_DIRECTIVE`, exported from `soleur-go-runner.ts`) to BOTH hosted prompt builders (legacy `agent-runner.ts` and the Concierge baseline): the agent must not ask the user for the session credential. Behavioural only; it names no mechanism.
- 2.4 Tests (write first, per `cq-write-failing-tests-before`):
  - 2.4.1 `apps/web-platform/test/agent-sandbox-credential-deny.test.ts`: both names `deny`; the injected set DERIVED from `buildAgentEnv`'s output by value flow (sentinel credential, every scheme and option shape) equals the denied set; service tokens and `GH_TOKEN` not denied. Plus the production wire in `agent-runner-query-options.test.ts` (the sandbox object `query()` receives carries the deny).
  - 2.4.2 Superseded: the drift guard shipped as the derived-set test (2.4.1) plus the wire test in `agent-runner-query-options.test.ts` (every combination of the inputs production varies) and the two call-site assertions; `agent-env-allowlist` was not touched.
  - 2.4.3 Superseded: the scheme cases are the exhaustive `SCHEME_REGISTRY` in 2.4.1; BYOK-missing and neither-set belong to `buildAgentEnv`'s own suites, unchanged here.
- 2.5 Canary fixture: NOT re-captured. It is stale (SDK 0.3.197 against the 0.3.284 pin) and cannot be re-captured while the canary projection refuses `--tmpfs <HOME>/.claude/bridge-spawn` (#9614). The deny is guarded at the argv level by `test/sandbox-credential-deny-argv.test.ts` instead (task 2.5.1).
  - 2.5.1 Task 1.1.2 showed the deny in the argv; it is asserted in `test/sandbox-credential-deny-argv.test.ts` (real SDK, bwrap shim) and, for behaviour, in `test/sandbox-credential-deny-runtime.test.ts` (real bubblewrap, decoy key, control arm). `agent-auth-env-vars.ts` joined the capture-gate triggers (`ci.yml`, `sdk-bump-sandbox-gate.sh`, T13c).
  - 2.5.2 Not done: no live probe was added to the creds-gated `sdk-bump-sandbox-gate.sh` path, because that path cannot give a verdict while the fixture is stale (#9614).
- 2.6 Create `scripts/verify-agent-security-slice1.sh` with the W1 check only; it prints `slice1-security: ok`, compares with `grep -c`, and has no shell-active characters in its command line.

### 3. Architecture, legal, docs

- 3.1 Write ADR-272 (W1 only): decision, rejected scrub, `mask` deferral, Phase 0 measurements, residuals, out-of-scope spawn table; re-verify the ordinal against fresh `origin/main` before merge.
- 3.2 Add the pointer to ADR-272 as an addendum in ADR-075 (shipped as an addendum, not an Alternatives-table row).
- 3.3 C4: read `model.c4`, `views.c4`, `spec.c4` in full; edit the `engine -> anthropic` edge description; run `c4-code-syntax.test.ts`, `c4-render.test.ts`, `c4-count-parity.test.sh`.
- 3.4 Add the measured-control TOM entry to `knowledge-base/legal/article-30-register.md`; add no public claim.
- 3.5 Done: comment posted on #9543 with the `mask` finding and its constraints.

### 4. PR 1 close-out

- 4.1 Run the plan's own lints, `markdownlint`, and the orphan-suite census. (The planned "live-probe line" in the creds-gated CI path was dropped with 2.5.2; the real-sandbox test runs in `test-webplat` instead.)
- 4.2 PR body: first line states whether merging alone mutates production (it ships a sandbox config change to all hosted tenants); `Ref #9601`.

## PR 2 — W2 destructive-command guard (customer plugin)

The items below are the slice-1 sketch and were superseded by the W2 plan, which is the source of truth for PR 2 (the vendored lexer replaced the lifted `tokenize()`, the matcher is `^Bash$`, a missing `jq` scans the raw envelope): `knowledge-base/project/plans/2026-10-06-feat-plugin-destructive-command-guard-w2-plan.md`; this branch's own task list is `knowledge-base/project/specs/feat-one-shot-9601-w2-plugin-destructive-command-guard/tasks.md`.

### 5. Preconditions

- 5.1 Record CPO sign-off on the final W2 decision set in the PR body before implementation.
- 5.2 Apply the Phase 0 hook-decision matrix result to the hosted posture.

### 6. Implementation

- 6.1 Read `tokenize()` in `operator-stage-approval.sh` and run it over the grammar rows; adopt it (lifted to `plugins/soleur/hooks/lib/tokenize.sh`) or port the segmenter from `guardrails.sh`; record which in the hook header.
- 6.2 Write the suite first: `plugins/soleur/test/destructive-command-guard-hook.test.sh` with every mutation-matrix row, grammar rows 9-11, both harness rows, a case-count floor, and oracle values taken from a real shell run; borrow the false-positive corpus from `cc-safety-net`.
- 6.3 Create `plugins/soleur/hooks/destructive-command-guard.sh`:
  - 6.3.1 stdin parse with `jq`; unparseable envelope answers `ask`; missing `jq` exits 0 with one notice.
  - 6.3.2 narrow decision set (deny `rm` of `/`, `~`, `$HOME`; ask for the rest of the plan's list); default branch via `git symbolic-ref refs/remotes/origin/HEAD`.
  - 6.3.3 reason text names the next step; header states scope limits and the portability list; no bash-4 features, no GNU-only binaries.
- 6.4 Register in `plugins/soleur/hooks/hooks.json` (matcher `^(Bash|exec)$`).
- 6.5 Registry rows: both `devin-dispositions.tsv` rows, `.claude/hooks/README.md` (including the kill-switch row), `.claude/settings.json` if required, `scripts/guard-vacuity-floor.test.sh`, `plugins/soleur/test/devin-plugin.test.ts`, `hook-input-classification-mutation.test.sh`; run `devin-matcher-parity.test.sh` and `hook-input-contract.test.sh`.
- 6.6 Add `SOLEUR_DISABLE_DESTRUCTIVE_GUARD: "1"` to `AGENT_ENV_OVERRIDES` in `agent-env.ts` with its test (hosted default off).
- 6.7 Extend `scripts/verify-agent-security-slice1.sh` with the guard-registered check.

### 7. Architecture and close-out

- 7.1 ADR-093 amendment (hook disabled in hosted sessions; W2 protects customer-machine users, not hosted founders) and ADR-223 amendment (new rows).
- 7.2 C4: add `destructiveGuard` next to `snapshotGuard`, include it in a view in `views.c4`; run the three C4 suites.
- 7.3 Comment on #9601 recording the hosted-enablement follow-up.
- 7.4 Run the lints, `markdownlint` and the orphan-suite census.

## PR 3 — W3 image CVE scan (release workflow)

### 8. Preconditions

- 8.1 Verify (3.0a) that the host refuses an image whose cosign signature does not verify (`ci-deploy.sh`) and record the evidence; if any consumer pulls an unsigned tag, restructure to scan before tags are promoted.
- 8.2 Run the pinned Trivy locally against the current released image; it must exit zero before the gate is enabled (otherwise bump the base-image digest first).
- 8.3 Verify the vendored claims (3.0c): the pinned action's `action.yml` inputs and Trivy's ignore-file schema; paste the evidence in the PR body.

### 9. Implementation

- 9.1 Write the static workflow test first under `.github/scripts/test/` with every matrix row; register it in `.github/scripts/test/run-all.sh`.
- 9.2 Add the scan step (own id, `if:` guard, digest target, SHA-pinned action, pinned Trivy version, `severity: CRITICAL`, `ignore-unfixed: true`, `exit-code: 1`, `trivyignores`); retry the database fetch; summary distinguishes scanner error from findings.
- 9.3 Add the dispatch-only override input with a required reason and the `::warning::` plus marker line; document the recovery sequence in the workflow header.
- 9.4 Create `.github/trivy/ignore.yaml` with Trivy-native `expired_at` and `statement`.
- 9.5 Confirm the `always()` notifiers and the degraded-mirror emitters tolerate a scan failure; confirm no `pull_request` or `merge_group` trigger exists on `web-platform-release.yml`.
- 9.6 Local proof of failure: pinned Trivy, the step's exact flags, a known-vulnerable image (non-zero) and the current image (zero); paste commands and exit codes in the PR body.
- 9.7 Extend `scripts/verify-agent-security-slice1.sh` with the scan-step check.

### 10. Architecture and close-out

- 10.1 ADR-096 addendum (new gate, deploy-refuses-unsigned evidence, recovery sequence).
- 10.2 C4: add the scan to the `github -> ghcr` build edge description; run the three C4 suites.
- 10.3 Add the measured-control TOM entry to the Art. 30 register.
- 10.4 After merge, `soleur:postmerge` confirms the first release run shows the scan step green and `verify-agent-security-slice1.sh` prints `slice1-security: ok` on `main`.
