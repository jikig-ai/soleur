---
title: "feat: agent security hardening epic (three-layer review) — slice 1"
date: 2026-10-06
slug: agent-security-hardening-slice-1
branch: feat-agent-security-three-layers
issue: 9601
type: feat
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# Agent security hardening — slice 1

Ref #9601 (epic stays open; slices 2-3 follow). Brainstorm: `knowledge-base/project/brainstorms/2026-10-06-agent-security-three-layers-brainstorm.md`. Spec: `knowledge-base/project/specs/feat-agent-security-three-layers/spec.md`. Draft PR #9599.

## Overview

Three small changes that need no new infrastructure, one per exposure the article review confirmed:

1. **W1 — Credential deny.** Remove the customer's Anthropic credential (`ANTHROPIC_API_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`) from the environment of sandboxed Bash commands in hosted agent sessions, using the SDK's `sandbox.credentials.envVars` deny entries. Service tokens stay (Connected Services depends on them).
2. **W2 — Plugin destructive-command guard.** Ship a narrow PreToolUse hook in the customer plugin that asks (or denies) before an unambiguous infra-destroy, force-push-to-default-branch, or root/home delete.
3. **W3 — Image CVE scan.** Scan the web-platform runtime image in the release workflow between build and sign/mirror/deploy; block on CRITICAL vulnerabilities with an available fix.

## Research Reconciliation — Spec vs. Codebase

| Spec / brief claim | Reality (command or file) | Plan response |
|---|---|---|
| "SDK subprocess env scrub" (FR1) | `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` strips every credential-shaped var (by name OR value) from Bash, hook and stdio-MCP subprocess envs, leaving only GitHub tokens, proxy and `GIT_CONFIG_*` (code.claude.com env-vars, "What the subprocess environment scrub removes"). `agent-runner.ts` injects a `## Connected Services` prompt block telling the agent Stripe/Cloudflare/Hetzner/Doppler/etc. are available, and `buildAgentEnv` injects those tokens by name from `PROVIDER_CONFIG` | **Cut the scrub.** It would break Connected Services. Use the targeted per-variable deny (next row). |
| "least-privilege token injection" (FR1) | Per-skill token scoping needs a broker; the SDK `mask` mode (sentinel in the sandbox, real value injected at the proxy) is the in-SDK candidate, and needs per-service `injectHosts` | **Descope to slice 2** (#9543). Comment the `mask` finding on #9543. |
| Brainstorm: "BYOK key reachable via env, regex is the only barrier" | `apps/web-platform/node_modules/@anthropic-ai/claude-agent-sdk/sdk.d.ts:8617-8672` (v0.3.284, same version pinned in the `Dockerfile` as `claude-code@2.1.284`): `sandbox.credentials.envVars[{name, mode:'deny'\|'mask'}]`; `deny` "unsets the variable for sandboxed commands". Applies to sandboxed Bash only; `allowUnsandboxedCommands: false` is already set in `agent-runner-sandbox-config.ts` so every Bash command is sandboxed | **W1 uses it.** |
| Repo-research: "the guard detects customer vs hosted by `CLAUDE_PLUGIN_ROOT`" | False: `browser-snapshot-credential-guard.sh:43` uses `SOLEUR_DISABLE_SNAPSHOT_GUARD`; the plugin hooks.json also loads into hosted sessions (ADR-093) and hosted sessions neutralize operator hooks through `AGENT_ENV_OVERRIDES` (`agent-env.ts`) | W2 follows the `SOLEUR_DISABLE_*` override convention. |
| Repo-research: "bwrap already blocks ps/pgrep/kill" | Conflated with the scrub's PID-namespace side effect. `agent-runner-sandbox-config.ts` denies read of `/proc` and skips `--proc /proc` | Not relied on. |
| Learnings agent: "generic destructive regex guard is not useful (ADR-162)" | ADR-162 is about PreToolUse input *rewriting* and regex cost models, not destructive guards. The valid constraints are ADR-157 (a hook that cannot parse its input asks) and the 2026-02-24 false-positive learning (single anchored patterns, not ANDed greps) | W2 keeps a narrow set and asks on an unparseable envelope. |
| Learnings agent: "a blocking image scan ejects merge-queue entries" | `web-platform-release.yml` triggers on `push: branches:[main]` and `workflow_dispatch` only, never on `merge_group`/`pull_request` | W3 adds no required check; an AC pins it. |
| Canary fixture "tracks the SDK pin" (implicit in the ADR-079 flow) | `jq -r .sdkVersion apps/web-platform/infra/sandbox-canary-argv.json` prints `0.3.197`; the pinned SDK is `0.3.284`. The fixture is already 87 patch versions stale | Phase 1.4 captures a **baseline at 0.3.284 first** in its own commit, so the deny's argv diff is isolated and any unrelated drift is visible and reviewed separately. |
| "Only one place hands the Anthropic credential to a subprocess" | `git grep -lE "ANTHROPIC_API_KEY\|CLAUDE_CODE_OAUTH_TOKEN" apps/web-platform/server apps/web-platform/scripts` lists ~30 files. Customer BYOK reaches the CLI only through `agent-runner.ts` → `buildAgentQueryOptions` → `buildAgentEnv`; the `server/inngest/functions/cron-*.ts` files use the **operator's** key, and `_cron-claude-eval-substrate.ts` runs with `sandbox.enabled:false` behind an allowlist hook | W1's property is scoped to customer BYOK in hosted sessions. The cron/operator-key spawns, `c4-render.ts` and `codex-app-server-launcher.ts` are recorded in ADR-272 as explicit out-of-scope rows with their env source. |

## Research Insights

**Premise Validation (Phase 0.6).** Cited issues verified live: #9601, #9602, #9603, #9604 OPEN; #9534 OPEN (Phase 4) with draft PR #9529; #9543, #9545, #4671, #4672 OPEN Post-MVP. Cited files exist on this branch: `agent-env.ts` (287 lines), `agent-runner-sandbox-config.ts`, `plugins/soleur/hooks/hooks.json` (93 lines), `reusable-release.yml`. ADR corpus grepped for the proposed mechanisms (env scrub, image scan): zero hits, so nothing was rejected earlier; ADR-093, ADR-096, ADR-157, ADR-162, ADR-213, ADR-223 and ADR-264 govern the surfaces touched.

**Property List (Phase 0.6b).**

- P1: A prompt-injected hosted agent cannot read the owner's Anthropic credential from its Bash environment.
- P2: A customer running the plugin on their own machine gets a human confirmation (or a block) before an agent runs an unambiguous destructive command.
- P3: A fixable CRITICAL vulnerability in the runtime image is caught before a release is signed and deployed.

**Cut List.**

- Env scrub (`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB`) → buys P1, but also strips the service tokens that Connected Services needs; the targeted deny buys P1 alone.
- Per-skill least-privilege service-token injection → buys a narrower service-token blast radius, not P1; needs a broker; covered by slice 2 (#9543).
- A scheduled image scan plus issue filing → buys P3 too late (after deploy) and is the "advisory, never promoted" shape (#6517 precedent); the release-time gate covers it.

**Existing primitives reused (found by plan review).** `.claude/hooks/guardrails.sh` `guardrails:block-recursive-delete` already implements the hardened root/`$HOME`/ancestor proof for `rm -rf`; `plugins/soleur/hooks/operator-stage-approval.sh` already carries a bash `tokenize()` and ships in the plugin; `.claude/hooks/lib/filing-shape.pl` is the repo's shell lexer (ADR-256). W2 reuses or ports these rather than writing a third tokenizer.

**Functional overlap (Phase 1.5b).** No community artifact is worth installing. `aquasecurity/trivy-action` (Apache-2.0) supplies exactly the inputs W3 needs: adopt, SHA-pinned. `cc-safety-net` (MIT) is a general destructive-command guard: borrow its false-positive test corpus for W2's must-PASS rows; its design (no ask/deny split, no ADR-157 fail-to-ask) does not fit.

**Learning constraints carried in.** ADR-157: a hook that cannot parse its stdin asks. 2026-02-24 guardrails false positive: independent greps ANDed together match comment text; use one anchored pattern per case. ADR-079: the canary fixture is a pure function of (SDK version, sandbox config). ADR-223: every plugin hook has a per-harness registry row and a disposition entry. ADR-270 / merge-queue PIR: a required check that does not post on `merge_group` deadlocks the queue (not applicable; pinned by an AC). #6517: gates born advisory were never promoted.

**Value measurement (Phase 0.6c).** Not a cost-saving justification; skipped.

## User-Brand Impact

**If this lands broken, the user experiences:** (W1) every hosted agent session failing to start because the sandbox rejects the new `credentials` block, or a Bash step losing a variable it needs; (W2) their own legitimate `rm`/`git push`/infra command blocked or nagged by a false positive; (W3) a release wedged by a CVE finding or a scanner outage.

**If this leaks, the user's data / money is exposed via:** their Anthropic API key or OAuth token read out of the agent's Bash environment by a prompt-injected instruction (`env`, `printenv`, `$ANTHROPIC_API_KEY`), spent or exfiltrated; and, for W2, an agent running `terraform destroy` or a force-push against their own production resources.

**Brand-survival threshold:** single-user incident

CPO sign-off: the brainstorm's CPO assessment is carried forward; explicit sign-off on the **final W2 decision set** is recorded in PR 2's body before PR 2 starts (acceptance criterion below). `soleur:engineering:review:user-impact-reviewer` runs at review time.

## Implementation Phases

Three independent workstreams ship as **three PRs** (see Scope Check): W1 first, then W2, then W3. Phase 0 measurements gate W1; their results are recorded in `phase-0-measurements.md` and summarized in ADR-272.

### Phase 0 — Measurements (before any code)

- 0.1 **One live probe answers both "is the deny honoured inline" and "where does it land".** Build a throwaway query with `sandbox: { …, credentials: { envVars: [{ name: "ANTHROPIC_API_KEY", mode: "deny" }, { name: "CLAUDE_CODE_OAUTH_TOKEN", mode: "deny" }] } }` using the real SDK and CLI 2.1.284 from `apps/web-platform/node_modules`; set both variables to sentinel probe values in the child env; run Bash steps `printenv ANTHROPIC_API_KEY; echo rc=$?`, the same for the OAuth variable, **`cat "$HOME/.claude/.credentials.json" 2>&1 | head -c 200`** and **`ls -a "$PWD" | head`** with a workspace `.env` present (the OAuth scheme may keep a credentials file, and a workspace `.env` is readable by design). Expected: both env reads empty with `rc=1`, and the CLI turn still completes. Record the result for the file and `.env` reads as a residual in ADR-272 whatever it shows. Then capture the bwrap argv and record whether the SDK implements the deny as `--unsetenv <NAME>` in the argv (the replay canary then proves it) or outside the argv (the live probe becomes the CI-gated proof). One paid Haiku turn; run once with a throwaway key per ADR-079's capture path.
- 0.2 **Customer hook-decision matrix for W2** (non-gating for PR 1, gating for PR 2): with a stub hook that answers `ask`, run `claude -p`, an interactive session, a `bypassPermissions` session and a subagent turn, and record what each does with the answer (prompt shown, auto-denied, ignored, hung). Also run it under the hosted SDK with `canUseTool` set (`permission-callback.ts`) to settle the hosted posture.
- 0.3 Record the results in `knowledge-base/project/specs/feat-agent-security-three-layers/phase-0-measurements.md`, citing the exact command for each.

### Phase 1 — W1 credential deny (PR 1)

- 1.1 In `agent-env.ts`, export `AGENT_AUTH_ENV_VARS = Object.freeze([API_KEY_ENV_VAR, OAUTH_ENV_VAR] as const)` and use it where the two auth branches inject, so the deny list and the injection set cannot drift.
- 1.2 In `agent-runner-sandbox-config.ts`, add `credentials: { envVars: AGENT_AUTH_ENV_VARS.map((name) => ({ name, mode: "deny" as const })) }` to the returned object and add the typed field `credentials: { envVars: { name: string; mode: "deny" }[] }` to the `AgentSandboxConfig` type (today a closed object plus an index signature, so an untyped key would compile and the test would assert against `unknown`). Comment the property (P1) and why service tokens and `GH_TOKEN`/`GIT_INSTALLATION_TOKEN` are deliberately not denied (Connected Services; the short-lived App installation token that `gh`/`git` need).
- 1.3 Extend `apps/web-platform/test/agent-runner-sandbox-config.test.ts` **and** the drift guard in `apps/web-platform/test/agent-runner-helpers.test.ts`: both names present with `mode: "deny"`; set equality between the denied names and the auth vars `buildAgentEnv` can inject for each scheme; `STRIPE_SECRET_KEY` and `GH_TOKEN` are NOT denied; cases for BYOK missing, both schemes set, neither set, and a service token absent.
- 1.4 **Canary fixture, baseline first.** Re-capture `apps/web-platform/infra/sandbox-canary-argv.json` at the pinned SDK 0.3.284 through the in-image `--verify` flow **before** the deny lands, as its own commit with a message explaining that the fixture was captured at 0.3.197; review and record any unrelated argv drift. Then land the deny and re-capture again so the second diff is only the deny. If Phase 0.1 shows the deny in the argv, add the assertion to `sandbox-canary-regression.test.sh`.
- 1.5 If Phase 0.1 shows the deny is not in the argv, add the live probe to the creds-gated CI path that already runs the SDK (`sdk-bump-sandbox-gate.sh`), so the property is exercised on every SDK bump. That gate falls back to a `sdk-bump-verified:` acknowledgement and blocks only on `argv_drift`; record that the probe inherits this posture and decide in the PR whether the probe blocks on the acknowledgement path.
- 1.6 In the `## Connected Services` prompt block of `agent-runner.ts`, add one line: the Anthropic credential is withheld from shell commands by design and must never be requested from the user (an agent that finds the key empty may otherwise ask the user to paste it into chat).
- 1.7 ADR-272 (W1 only): the decision, the rejected scrub, the `mask` deferral, the Phase 0 measurements, the residuals (hooks and in-process MCP tools run outside the sandbox with the full env but the agent cannot author them; the `.env`/credentials-file reads; service tokens and `GH_TOKEN` still readable until #9543), and the explicit out-of-scope spawn table from Research Reconciliation. Extend ADR-075's Alternatives-Considered table with a pointer. Add a measured-controls TOM entry to `knowledge-base/legal/article-30-register.md` (no public claim).
- 1.8 C4 for W1: see Architecture Decision section.

### Phase 2 — W2 destructive-command guard (PR 2)

- 2.0 **Measure before reuse.** Read `tokenize()` in `operator-stage-approval.sh` and run it over the grammar rows listed under Guard 2: it was written to accept ONE simple command (no pipe, `;`, trailing `&&`, redirect or substitution), so it may not segment a list. Adopt it only if it handles the rows; otherwise port the segmenter from `guardrails.sh` and say so in the hook header. The segmenter splits at nesting depth 0 after dropping redirect operators (`2>&1`, `&>`, `>&2`, `<&0`, `>|`), treats `;`/`|` inside `$(...)` or backticks as part of the substitution, does not treat a mid-word `#` as a comment, runs in one process (no fork per segment), and does not anchor a flag signal to whitespace (`\-f`, `$E-f` reach the tool as `-f`).
- 2.1 Create `plugins/soleur/hooks/destructive-command-guard.sh`, modelled on `browser-snapshot-credential-guard.sh`: read the stdin envelope with `jq`; an unparseable envelope answers `ask` (ADR-157); non-Bash tools pass through; honour `SOLEUR_DISABLE_DESTRUCTIVE_GUARD`. **Portability:** the hook ships to customer machines, so list every external binary it calls and keep it to `jq`, `git` and POSIX utilities; no `readlink -f`, `sed -i`, `date -d`, `stat -c` or bare `timeout`; no bash-4 features (`declare -A`, `mapfile`, `${x,,}`), because `/usr/bin/env bash` on stock macOS is 3.2. Resolve paths with `cd … && pwd -P`.
<!-- lint-infra-ignore start: describes what the hook says to the human at its own decision point; prescribes no infrastructure step -->
- 2.2 Tokenize with the plugin's existing `tokenize()` from `operator-stage-approval.sh` (lift it to `plugins/soleur/hooks/lib/` rather than copying); evaluate each simple command of `&&`/`||`/`;`/`|`/newline lists and unwrap `bash|sh -c`; match only in command position, never inside quoted arguments, comments or heredoc bodies. Port the `block-recursive-delete` root/`$HOME`/ancestor proof from `guardrails.sh` instead of writing a new one, and state in the hook header what it deliberately does not cover (obfuscation, a script written then run, MCP delete tools; Bash only).
- 2.3 Decision set (narrow, unambiguous): **deny** `rm` with recursive+force whose target resolves to `/`, `~` or `$HOME`; **ask** `terraform|tofu destroy`, `terraform apply -destroy`, `git push --force|-f|--force-with-lease` to the default branch, a recursive-force `rm` of `.`, `..` or an ancestor of the working directory, and `drop database` through `psql|mysql`. The default branch is resolved with `git symbolic-ref refs/remotes/origin/HEAD`; when it cannot be resolved, `main` and `master` are treated as default and the hook asks. Any pattern that cannot be stated as one anchored case is dropped, not widened. The deny/ask reason text names the next step: run it yourself outside the agent, or set `SOLEUR_DISABLE_DESTRUCTIVE_GUARD` in your own shell; the agent must stop and ask the human, not work around the block.
- 2.4 A missing `jq` is a dependency problem, not an unparseable envelope: the hook exits 0 with a one-time notice instead of asking on every Bash call. Record this as the one deliberate narrowing of ADR-157 in the hook header.
<!-- lint-infra-ignore end -->
- 2.5 Register in `plugins/soleur/hooks/hooks.json` (PreToolUse, matcher `^(Bash|exec)$`) and in every registry ADR-223 names. The sibling guard appears in `.claude/hooks/devin-dispositions.tsv` on **two** rows (`claude-settings` and `soleur-plugin`), in `.claude/settings.json`, in `.claude/hooks/README.md`, in `scripts/guard-vacuity-floor.test.sh` (PROMOTED_FILES regex), and in `plugins/soleur/test/devin-plugin.test.ts`; decide for each whether the new guard belongs there and add a parallel assertion where the existing test hard-codes the sibling's name. Also run `devin-matcher-parity.test.sh` and `hook-input-contract.test.sh`. Add a kill-switch row to `.claude/hooks/README.md` (the env var needs a session restart).
- 2.6 Hosted posture from Phase 0.2: default is `SOLEUR_DISABLE_DESTRUCTIVE_GUARD: "1"` in `AGENT_ENV_OVERRIDES` (hosted Bash is already sandboxed and gated by `permission-callback.ts`), recorded in an ADR-093 amendment line as a deliberate decision. State plainly in that amendment and in the #9601 comment that W2 protects customer-machine plugin users, not hosted founders; hosted founders rely on the sandbox and the review gate. Enabling it in hosted sessions is a tracked follow-up unless Phase 0.2 shows `ask` routes cleanly to the review gate.
- 2.7 Test `plugins/soleur/test/destructive-command-guard-hook.test.sh` per the Guard Contract matrix, borrowing `cc-safety-net`'s false-positive corpus for the must-PASS rows; add the hook to the mutation harness in `hook-input-classification-mutation.test.sh`. The suite lives under `plugins/soleur/test/`, which `scripts/test-all.sh` already globs.
- 2.8 ADR-223 amendment line for the new registry rows; C4: see Architecture Decision section.

### Phase 3 — W3 image CVE scan (PR 3)

- 3.0 **Verify before editing the workflow:** (a) `docker_build` uses `push: true` with the version, SHA and `latest` tags, so the image is published before it is scanned; confirm that the host pulls `${ref}:${TAG}` and refuses anything whose cosign signature does not verify (`ci-deploy.sh`), so an unsigned scanned-and-failed image cannot deploy, and record the evidence in the ADR amendment; if any consumer pulls an unsigned tag, restructure to scan before the tags are promoted. (b) Run the scan once against the **current released image**; it must pass before the gate is enabled, otherwise the PR bumps the base-image digest first.
- 3.0c **Verify the vendored claims against the pinned action and Trivy version, not memory:** read the pinned `trivy-action`'s `action.yml` for the input names `trivyignores`, `ignore-unfixed`, `exit-code`, `severity` and the Trivy version input, and the pinned Trivy's ignore-file documentation for the YAML schema (`vulnerabilities:` entries with `id`, `statement`, `expired_at`); record `<tool> --help` or the doc URL in the PR body. Also check that the registry login already present supplies the scan's pull access and what the vulnerability-database download uses for auth and rate limits.
- 3.1 In `.github/workflows/reusable-release.yml`, add a scan step with its own step id immediately after `docker_build` and before the cosign/mirror steps, guarded by `if: steps.docker_build.outcome == 'success'`, scanning `${{ inputs.docker_image }}@${{ steps.docker_build.outputs.digest }}` (the registry login step runs earlier). Use the Trivy action pinned by commit SHA with the Trivy version pinned: `severity: CRITICAL`, `ignore-unfixed: true`, `exit-code: 1`, `trivyignores: .github/trivy/ignore.yaml`. Retry the vulnerability-database fetch, and make the step summary distinguish **scanner error** (database fetch failed, fails closed) from **findings** (CVE ids, package, fixed version).
- 3.2 Escape hatch: a dispatch-only input carrying a required reason, mirroring the zot-gate escape hatch; the reusable workflow re-checks `github.event_name`, so a push can never carry it. An override emits a `::warning::` annotation and a `SOLEUR_IMAGE_CVE_SCAN_OVERRIDE reason=…` marker line in the summary. Document the recovery sequence in the workflow header and the ADR: (1) a blocked push leaves `main` ahead of what is deployed; (2) for a CVE with no available fix the scan already passes (`ignore-unfixed`); (3) for a fixable CRITICAL, bump the base-image digest, or add a dated ignore entry through a PR that the next push re-scans; (4) for a scanner being unavailable, re-run the failed job (a re-run keeps the original inputs; a fresh dispatch recomputes the version, per the warning in `reusable-release.yml`), or dispatch with the override and a reason.
- 3.3 Ignore file `.github/trivy/ignore.yaml` uses Trivy's native `expired_at` and `statement` fields, so Trivy itself rejects an expired entry; no custom expiry test is written.
- 3.4 Static workflow test under `.github/scripts/test/` (register it in `.github/scripts/test/run-all.sh`, the consumer that selects suites there, and confirm the CI job that runs `run-all.sh` fires on a change to `reusable-release.yml`): scan step exists with its own id, is ordered after `docker_build` and before the cosign/mirror steps, carries the `if:` guard, `exit-code: 1`, `ignore-unfixed: true`, CRITICAL in severity, action pinned to a 40-hex SHA, the `always()` notifiers and the degraded-mirror emitters tolerate a scan failure (they read `mirror_verified`, which defaults to `'false'`), and no `pull_request`/`merge_group` trigger exists on `web-platform-release.yml`.
- 3.5 Proof the scan can fail, **without dispatching the release workflow** (a dispatch of `web-platform-release.yml` builds, pushes and deploys): run the pinned Trivy version locally in its container image with the exact flags the step uses against a pinned known-vulnerable public image (expect a non-zero exit) and against the current released image (expect zero), and paste both commands and exit codes in the PR body. The first post-merge release run is the CI-side proof. No permanent workflow input.
- 3.6 ADR-096 (mirror gate) addendum for the new gate; measured-controls TOM entry in `knowledge-base/legal/article-30-register.md`.

### Phase 4 — slice 2/3 hand-off (docs only)

- 4.1 Comment on #9543: the SDK `sandbox.credentials` `mask` mode is the in-SDK candidate for the broker, with its constraints (per-service `injectHosts`, proxy-side substitution, requires `network.allowedDomains` entries).

## Files to Edit

**PR 1 (W1)**

- `apps/web-platform/server/agent-env.ts` — export `AGENT_AUTH_ENV_VARS` (ask 1).
- `apps/web-platform/server/agent-runner-sandbox-config.ts` — type field and credentials deny block (ask 1).
- `apps/web-platform/server/agent-runner.ts` — one prompt line (inferred: a withheld key invites a request for it).
- `apps/web-platform/test/agent-runner-sandbox-config.test.ts`, `apps/web-platform/test/agent-runner-helpers.test.ts`, `apps/web-platform/test/server/agent-env-allowlist.test.ts` — assertions (ask 1).
- `apps/web-platform/infra/sandbox-canary-argv.json`, `apps/web-platform/scripts/sandbox-canary-regression.test.sh` — baseline then deny re-capture (ask 1; contract: ADR-079).
- `knowledge-base/engineering/architecture/diagrams/model.c4` (+ `views.c4`) — see Architecture Decision (inferred).
- `knowledge-base/engineering/architecture/decisions/ADR-075-*.md` — pointer (inferred).
- `knowledge-base/legal/article-30-register.md` — TOM entry, measured controls only (inferred).

**PR 2 (W2)**

- `apps/web-platform/server/agent-env.ts` — `SOLEUR_DISABLE_DESTRUCTIVE_GUARD` override; `apps/web-platform/test/server/agent-env-allowlist.test.ts` (asks 2, inferred: plugin hooks load into hosted sessions).
- `plugins/soleur/hooks/hooks.json`, `plugins/soleur/hooks/operator-stage-approval.sh` (lift `tokenize()` to a lib) (ask 2).
- `.claude/hooks/devin-dispositions.tsv` (two rows), `.claude/hooks/README.md`, `.claude/settings.json` (if the registry requires it), `scripts/guard-vacuity-floor.test.sh`, `plugins/soleur/test/devin-plugin.test.ts`, `plugins/soleur/test/hook-input-classification-mutation.test.sh` (inferred: ADR-223 parity tests).
- `knowledge-base/engineering/architecture/decisions/ADR-093-*.md`, `ADR-223-*.md` — amendment lines (inferred).
- `knowledge-base/engineering/architecture/diagrams/model.c4` + `views.c4` — `destructiveGuard` component included in a view (inferred; keeps `c4-render` from flagging an orphan).

**PR 3 (W3)**

- `.github/workflows/reusable-release.yml`, `.github/workflows/web-platform-release.yml` — scan step, dispatch override input, header runbook (ask 3).
- `.github/scripts/test/run-all.sh` — register the static workflow test (inferred: the suite's selection consumer).
- `scripts/verify-agent-security-slice1.sh` — extended with the PR 2 and PR 3 checks (see Files to Create).
- `knowledge-base/engineering/architecture/decisions/ADR-096-*.md` — addendum (inferred).
- `knowledge-base/legal/article-30-register.md` — TOM entry (inferred).

## Files to Create

- `plugins/soleur/hooks/destructive-command-guard.sh`, `plugins/soleur/hooks/lib/tokenize.sh`, `plugins/soleur/test/destructive-command-guard-hook.test.sh` (ask 2).
- `knowledge-base/engineering/architecture/decisions/ADR-272-agent-credential-isolation-via-sandbox-credentials-deny.md` — ordinal provisional; `soleur:ship` re-verifies against fresh `origin/main` (inferred: the plan skill's ADR rule).
- `knowledge-base/project/specs/feat-agent-security-three-layers/phase-0-measurements.md` (asks 1, 2).
- `.github/trivy/ignore.yaml` and the static workflow test under `.github/scripts/test/` (ask 3).
- `scripts/verify-agent-security-slice1.sh` — a thin probe the observability gate runs locally under its 15-second cap (inferred). It is **created in PR 1 with the W1 check only** (credentials deny present in the config source) and extended by PR 2 (guard registered in `hooks.json`) and PR 3 (scan step present in the workflow), so each PR's `discoverability_test` names a command that exists in that PR's tree. It prints `slice1-security: ok` when every check present so far holds, compares with `grep -c` counts and never with a negated grep (a pattern typo must not read as success), and its text has no `|`, `;`, `&`, `<`, `>`, `$` in the command line the gate sees.

## Open Code-Review Overlap

None. Checked the 87 open `code-review` issues against every file above (`agent-runner-sandbox-config.ts`, `agent-env.ts`, `hooks.json`, `reusable-release.yml`, `model.c4`, `sandbox-canary.mjs`, `devin-dispositions.tsv`): zero matches.

## Guard Contract

### Guard 1 — Anthropic credential deny (hosted sandbox)

**Property.** No sandboxed Bash command in a hosted agent session can read `ANTHROPIC_API_KEY` or `CLAUDE_CODE_OAUTH_TOKEN` from its environment, while the CLI process still authenticates and service tokens still reach Bash.

**Assembly.** The chokepoint is the single object returned by `buildAgentSandboxConfig` and passed as `options.sandbox` by `buildAgentQueryOptions` (`agent-runner-query-options.ts`); `agent-runner.ts` and `cc-dispatcher.ts` (support and c4 paths) both reach it. The injection side is `buildAgentEnv` (both auth branches), which is the only path that carries customer BYOK to the CLI. Enumerated now with `git grep -lE "ANTHROPIC_API_KEY|CLAUDE_CODE_OAUTH_TOKEN" apps/web-platform/server apps/web-platform/scripts`: the `server/inngest/functions/cron-*.ts` files use the operator's key, `_cron-claude-eval-substrate.ts` runs with `sandbox.enabled:false` behind an allowlist hook, and `c4-render.ts` and `codex-app-server-launcher.ts` spawn children; each is recorded in ADR-272 as out of scope with its env source. The deny list and the injected set share one exported constant so a third auth variable cannot be added to one side only.

**Mutation matrix.**

| # | Edit that MUST turn the guard RED | Detected by |
|---|---|---|
| 1 | Remove either entry (first, or only the second after a compliant first) | sandbox-config unit test: set equality |
| 2 | Change `mode: "deny"` to `"mask"`, or delete the `credentials` key while keeping the constant | same test: asserts the returned object, not the constant |
| 3 | Add a third auth var to `buildAgentEnv` without adding it to `AGENT_AUTH_ENV_VARS` | the set-equality test computes injected auth vars by calling `buildAgentEnv` per scheme |
| 4 | Guard's own dispatch: the test iterates zero schemes (empty list) | the test asserts the scheme count is at least 2 before comparing sets |
| 5 | Stale canary fixture after a config edit | canary `--verify` byte-diff fails in the creds-gated CI path |

**Harness rows.** (a) Mutate the suite: delete the `GH_TOKEN`-not-denied assertion; the suite must still fail its case-count floor. (b) Must-PASS non-canonical inputs: a connected-service token (`STRIPE_SECRET_KEY`) and `GH_TOKEN` remain un-denied, differing from the canonical two-name case in a way the contract permits.

**Anchor.** The value lives in code, not a stored hash; the independent anchor is the creds-gated live probe (Phase 0.1 / 1.5) that executes the real SDK and reads the real Bash environment, plus the merge-base fixture diff in the SDK-bump gate.

### Guard 2 — destructive-command hook

**Property.** A Bash tool call whose command, after tokenization and wrapper unwrapping, runs a command in the destructive set receives `ask` or `deny`, never an implicit allow; an envelope the hook cannot parse receives `ask`.

**Assembly.** Every route by which a command string reaches execution inside one Bash call, within the stated scope: simple command, `&&`/`||`/`;`/`|`/newline lists and `bash|sh -c`; the tool names the matcher covers (`Bash`, `exec`). Out of scope and stated in the hook header: obfuscation, a script written and then run, MCP delete tools. The registration side: the hook file is referenced by `hooks.json` with a matcher that matches `Bash`, and every ADR-223 registry names it.

**Mutation matrix.**

| # | Edit that MUST turn the guard RED | Detected by |
|---|---|---|
| 1 | Stop scanning the second command of an `&&` list | case: `ls && terraform destroy` expects ask |
| 2 | Remove `bash -c` unwrapping | case: `bash -c 'terraform destroy'` expects ask |
| 3 | Guard's own dispatch: garbled or empty stdin exits 0 silently | case: garbage stdin expects `ask` (ADR-157) |
| 4 | Check only the first command after a benign one | case: `terraform plan; rm -rf ~` expects deny |
| 5 | Match inside quoted text | must-PASS: `echo "terraform destroy"` and `git commit -m "rm -rf /"` produce no decision |
| 6 | Remove the `hooks.json` registration | registration test: file referenced with a Bash-matching matcher |
| 7 | Hook ignores `SOLEUR_DISABLE_DESTRUCTIVE_GUARD` | case: override set expects exit 0 with no output |
| 8 | Missing `jq` asks on every call | case: PATH without `jq` expects exit 0 plus a single notice |
| 9 | Segmenter splits on a character the shell reads as part of one command | grammar rows: `terraform plan 2>&1 \| tee log` (no decision), `ls &> out; terraform destroy` (ask), `echo $(terraform plan; true)` (no decision), `ls #x; terraform destroy` where `#` is mid-word vs a comment, `cmd >\| f` |
| 10 | An `rm` option cluster spelling escapes the match | grammar rows: `rm -rf ~`, `rm -fr ~`, `rm -r -f ~`, `rm --recursive --force ~`, `rm -Rf $HOME`, `rm -rf -- ~`, `\rm -rf ~`, `"rm" -rf ~` |
| 11 | A quoting or heredoc context hides or fakes a command | grammar rows: a heredoc body containing `terraform destroy` (no decision), a heredoc whose terminator line is followed by a real command, a backslash-continued line, `'git push --force origin main'` as a quoted argument (no decision) |

**Grammar fixture and oracle.** The suite is built from the shell grammar, not from the decision set's use cases: every blank class, every quoting context, every construct that opens its own quote scope, every option cluster that consumes a value. Rows 9-11 are the floor, not the list. The expected value of each row is derived from the command and a real `bash -n`/`bash -c 'echo …'` run, never from what the hook returned, so the oracle cannot read the system under test.

**Harness rows.** (a) Delete one expected-ask case from the suite; the suite must fail its case-count floor. (b) Must-PASS non-canonical inputs: `rm -rf node_modules`, `terraform plan`, `git push origin feature-branch`, `git push --force-with-lease origin feature-branch` (not the default branch).

**Anchor.** Registration parity tests (ADR-223) read the committed registries; a weakening that edits the hook and the suite together still has to keep the registry rows and the case-count floor, which a reviewer sees in the diff.

### Guard 3 — image CVE scan gate

**Property.** A release whose image carries a CRITICAL vulnerability with an available fix does not reach signing, mirroring or deploy, and no override exists on a push.

**Assembly.** Every path from `docker build` to a deployable artifact: `reusable-release.yml`'s `docker_build` step, the cosign/mirror steps after it, and the callers (`web-platform-release.yml` and any other workflow calling the reusable one; enumerate with `git grep -n "reusable-release.yml" .github/workflows` and `git grep -n "docker/build-push-action" .github/workflows`, and record any other image-producing workflow as covered or out of scope). The image is pushed before it is scanned, so the property holds because the host verifies the cosign signature of what it pulls (Phase 3.0 records the evidence); the guard therefore covers the sign step, not the registry contents.

**Mutation matrix.**

| # | Edit that MUST turn the guard RED | Detected by |
|---|---|---|
| 1 | Move the scan after the mirror/sign steps | static workflow test: step ordering |
| 2 | `exit-code: 1` becomes `0` | static test |
| 3 | `ignore-unfixed: true` removed or severity drops CRITICAL | static test |
| 4 | Action reference changed from a 40-hex SHA to a tag | static test |
| 5 | Override honoured when `github.event_name == 'push'` | static test on the override condition |
| 6 | Guard's own dispatch: the `if: steps.docker_build.outcome == 'success'` condition removed | static test asserts the guard on the step |
| 7 | A `pull_request` or `merge_group` trigger added to `web-platform-release.yml` | static test (merge-queue deadlock class) |
| 8 | A scan failure leaves a downstream emitter reporting a verified mirror | static test on the emitters' handling of a failed scan |

**Harness rows.** (a) Delete one assertion from the static test; its case-count floor fails. (b) Must-PASS non-canonical input: a reasoned dispatch override passes; an ignore entry with a future `expired_at` and a statement passes.

**Anchor.** The ignore file is the stored allowance; Trivy's native `expired_at` makes an expired entry fail the scan itself, so a permanent exemption needs a visibly far-future date a reviewer can see in the diff, and the local run in Phase 3.5 shows the scan failing on a known-vulnerable image and passing on the current one.

## Observability

```yaml
liveness_signal:
  what: Phase 3 scan step result in each web-platform release run (step summary line `SOLEUR_IMAGE_CVE_SCAN critical_fixable=<n>` or `scanner_error`), and for W1 the existing agent-sandbox Sentry tag (`feature=agent-sandbox`) on sandbox startup failure
  cadence: every release run (push to main touching apps/web-platform or plugins/soleur)
  alert_target: a failing release workflow is visible in the existing release-failure notification path (the release notifier steps in reusable-release.yml); sandbox startup failures reach Sentry
  configured_in: .github/workflows/reusable-release.yml; apps/web-platform/server/agent-runner-sandbox-config.ts
error_reporting:
  destination: GitHub Actions run status (W3); Sentry feature=agent-sandbox (W1); hook output to the harness transcript (W2)
  fail_loud: yes — scan failure and scanner error both fail the release job; sandbox config rejection throws under failIfUnavailable; an unparseable hook envelope answers ask rather than allow
failure_modes:
  - mode: SDK rejects or ignores the credentials block
    detection: creds-gated live probe in CI and canary fixture byte-diff; startup failure reaches Sentry via failIfUnavailable
    alert_route: Sentry feature=agent-sandbox; CI red on the SDK-bump gate
  - mode: guard hook silently not registered
    detection: registration parity tests (ADR-223) and the static probe script
    alert_route: CI red
  - mode: scan step skipped or reordered by an edit
    detection: static workflow test on ordering, guard condition and exit code
    alert_route: CI red
  - mode: scanner being unavailable mistaken for a CVE finding
    detection: step summary prints scanner_error separately from findings
    alert_route: release workflow failure notification
logs:
  where: Actions run logs and step summary (W3); Sentry (W1); Claude Code transcript (W2)
  retention: GitHub default run-log retention; Sentry project retention
discoverability_test:
  command: bash scripts/verify-agent-security-slice1.sh
  expected_output: slice1-security: ok
```

Blind-surface note (2.9.2): the hosted sandbox is a surface the operator cannot inspect directly. The in-surface probe is the creds-gated live check that runs the real SDK and reads the real Bash environment (one event discriminates "key present", "key absent", and "sandbox failed to start"); it runs in CI on every SDK bump, not only once.

## Architecture Decision (ADR/C4)

### ADR

- ADR-272 (ordinal provisional; `soleur:ship` re-verifies against fresh `origin/main`): **W1 only** — *agent credential isolation uses `sandbox.credentials` deny entries scoped to the Anthropic auth variables; `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` is rejected because it strips Connected Services tokens; `mask` is the slice-2 candidate for service tokens.* Records the Phase 0 measurements, the residuals and the out-of-scope spawn table. Status: adopting until the first post-merge release proves the live probe.
- W2 is recorded as amendments, not a new ADR: ADR-093 (which hooks run in hosted sessions, and that this one is disabled there) and ADR-223 (the new registry rows).
- W3 is recorded as an ADR-096 addendum (it is a sibling of the mirror gate), including the Phase 3.0 evidence that deploy refuses an unsigned image and the recovery sequence.

### C4 views

All three model files (`model.c4`, `views.c4`, `spec.c4`) must be read in full at work time. Checked so far against `model.c4` by search: the `hooks` container (Hook Engine, line ~135) already says it guards tool calls; `snapshotGuard` (line ~235) is the sibling component pattern; `github` (line ~322), `ghcr` (line ~379) and `anthropic` (line ~318) exist; the Node dispatch process outside the bwrap sandbox is already described (lines ~447, ~566). Required edits: (a) a new plugin component `destructiveGuard` next to `snapshotGuard` with its relationship to `hooks`, included in a view in `views.c4`; (b) the `engine -> anthropic` edge description gains "credential withheld from sandboxed Bash"; (c) the `github -> ghcr` build edge gains the scan step; (d) any element description these falsify. External actors checked: founder (already modeled, unchanged), GitHub Actions (inside `github`), the Trivy vulnerability database (a build-time fetch, described on the edge, not a new system). After editing, run `apps/web-platform/test/c4-code-syntax.test.ts`, `c4-render.test.ts` and `plugins/soleur/test/c4-count-parity.test.sh` (that test asserts workflow, monitor and Resend counts; none changes here, but a green run is the evidence).

### Sequencing

ADR-272 and the W1 C4 edits ship in PR 1; the W2 and W3 amendments and components ship in PR 2 and PR 3; none is deferred to a follow-up issue.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (carried forward from the brainstorm's `## Domain Assessments`; no fresh sweep).

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Layers 1 and 3 enforced for the web runtime; credential-in-env and the near-empty customer plugin guard are the real gaps. Increments in this slice match its top two. The scrub variant was refined to a targeted deny after the connected-services dependency surfaced. Plan review added: reuse the existing lexers, make the scan born blocking only after the current image passes.

### Product (CPO)

**Status:** reviewed
**Assessment:** About 80% of the work already filed; slice 1 is invisible hardening plus one founder-visible ask on destructive commands. Friction handled by a narrow decision set, `ask` where intent is ambiguous, and explicit statements that W1 is not full credential isolation and W2 does not cover hosted founders.

### Legal (CLO)

**Status:** reviewed
**Assessment:** Claims follow measured controls; slice 1 adds only measured TOM entries to the Art. 30 register and no public claim. No new processing step, no new sub-processor (Trivy runs in CI against our own image; the vulnerability database fetch carries no tenant data). `soleur:gdpr-gate` run at plan time (brand-survival trigger; the path regex matched no file): no findings.

### Product/UX Gate

**Tier:** none
**Decision:** no user-facing page or component in the Files lists; the mechanical UI-surface override did not fire.
**Pencil available:** N/A (no UI surface)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "SDK subprocess env scrub + least-privilege token injection" [brief] | Phase 1 (W1), reshaped to a targeted deny; scrub cut and injection scoping moved to slice 2 | mapped — deviation recorded in Research Reconciliation |
| 2 | "minimal destructive-command PreToolUse guard in plugins/soleur/hooks/hooks.json" [brief] | Phase 2 (W2) | mapped |
| 3 | "image CVE scan in CI" [brief] | Phase 3 (W3) | mapped |
| 4 | "slices 2-3 as sequenced follow-ups" [brief] | Phase 4 hand-off comment on #9543; slices stay tracked on #9601, #9602, #9603 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Phase 0 measurements | — | inferred — justification: W1 and W2 rest on SDK and hook behavior no repo file proves; a wrong assumption ships a broken hosted runtime (ADR-079 class) |
| `AGENT_AUTH_ENV_VARS` constant | asks 1 | asked |
| Credentials deny block, type field, sandbox-config and drift tests | "SDK subprocess env scrub + least-privilege token injection" | asked |
| Prompt line in `agent-runner.ts` | — | inferred — justification: a withheld key invites the agent to ask the user to paste it into chat |
| Canary fixture baseline and re-capture | — | inferred — justification: the fixture is a function of the sandbox config (ADR-079) and is already stale at 0.3.197; without it the SDK-bump gate fails |
| `destructive-command-guard.sh`, lifted `tokenize.sh`, and the suite | "minimal destructive-command PreToolUse guard in plugins/soleur/hooks/hooks.json" | asked |
| Registry rows (devin-dispositions, README, parity tests, settings) | — | inferred — justification: ADR-223 parity tests fail on an unregistered hook |
| `SOLEUR_DISABLE_DESTRUCTIVE_GUARD` override | — | inferred — justification: plugin hooks load into hosted sessions (ADR-093) and every operator hook is neutralized there by the same mechanism |
| Scan step, ignore file, static workflow test | "image CVE scan in CI" | asked |
| Dispatch-only override input | — | inferred — justification: a blocking gate with no escape hatch can wedge a security hotfix deploy; mirrors the zot gate |
| ADR-272, ADR-075 pointer, ADR-093/096/223 amendments, C4 edits | — | inferred — justification: the plan skill makes the ADR and C4 update a deliverable of the plan that changes the architecture |
| Art. 30 TOM entries | — | inferred — justification: CLO ratchet; a shipped control must be recorded in the register in the same PR |
| `verify-agent-security-slice1.sh` | — | inferred — justification: the observability gate requires a local one-command discoverability probe under 15 seconds; the test suites cannot meet that cap |
| Comment on #9543 | "slices 2-3 as sequenced follow-ups" | asked |

### Split Assessment

- Subsystems touched: 5 — `apps/web-platform`, `plugins/soleur`, `.github`, `.claude`, `knowledge-base`
- Planned files: ~28 across three PRs | Estimated changed lines: ~800
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: split — three PRs along the workstream seams (W1 hosted runtime, W2 customer plugin hook, W3 release workflow). The seam is real: the three have different blast radii (all hosted tenants; every plugin user; every release) and different rollbacks, so a defect in one must not hold the others. One plan, one `tasks.md` grouped by PR; W1 ships on this branch (PR #9599), W2 and W3 on their own branches cut after W1 merges.

## Acceptance Criteria

### Pre-merge (PR 1 — W1)

- [x] Phase 0 measurements recorded in `phase-0-measurements.md`; results confirmed the mechanism and changed two things (OAuth token is already withheld by the CLI; the fixture cannot be re-captured, #9614).
- [x] `buildAgentSandboxConfig` returns typed `credentials.envVars` denying exactly the auth variables `buildAgentEnv` can inject; `agent-sandbox-credential-deny.test.ts` green (set equality, deny mode, service tokens and `GH_TOKEN` not denied, read-only config too), mutation battery 7/7. Absent/both/neither cases ride the existing `agent-env*.test.ts` scheme tests.
- [x] Live probe shows the Anthropic key absent in sandboxed Bash with the CLI turn completing (`phase-0-measurements.md`), and `sandbox-credential-deny-argv.test.ts` asserts the real SDK argv carries both `--unsetenv` pairs on every CI run; mutation battery 5/5.
- [x] **Amended:** the committed canary fixture is not re-captured (SDK 0.3.284's `--tmpfs <HOME>/.claude/bridge-spawn` cannot be projected; tracked in #9614). `sandbox-canary-regression.test.sh` (11/11) and `sandbox-canary.test.ts` are green.
- [x] ADR-272 written, ADR-075 addendum added, C4 edge edited and `model.likec4.json` regenerated, `c4-code-syntax`, `c4-render`, `c4-count-parity` and `c4-model-freshness` green. The `adr-ordinals` check against fresh `origin/main` is re-run at ship.
- [x] Art. 30 register TOM entry added for the measured control only; no public legal document gains a security claim.

### Pre-merge (PR 2 — W2)

- [ ] CPO sign-off on the final W2 decision set recorded in the PR body before implementation starts.
- [ ] Guard hook, lifted tokenizer, registrations and every ADR-223 registry row in (both `devin-dispositions.tsv` rows, README kill-switch row); `destructive-command-guard-hook.test.sh` green including every mutation-matrix row and both harness rows.
- [ ] Hosted posture recorded per Phase 0.2 in an ADR-093 amendment, stating that hosted founders are not covered by W2.
- [ ] No false positive on `rm -rf node_modules`, `terraform plan`, `git push origin <feature>`, quoted text containing a destructive string; a missing `jq` produces exit 0 and one notice; the grammar rows 9-11 pass with oracle values derived from a real shell run.
- [ ] The hook uses no bash-4 feature and no GNU-only binary (the portability list in Phase 2.1 is in the hook header); the suite is run once under a bash-3.2-compatible check or the absence of those constructs is asserted by grep count.
- [ ] The new suite is picked up by `scripts/test-all.sh` and by the orphan-suite census.

### Pre-merge (PR 3 — W3)

- [ ] The scan passes on the current released image before the gate is enabled.
- [ ] Scan step ordered after build and before sign/mirror; static workflow test green on every matrix row; no `pull_request` or `merge_group` trigger added anywhere; the recovery sequence is in the workflow header and the ADR-096 addendum.
- [ ] The local run of the pinned Trivy with the step's exact flags exits non-zero on a known-vulnerable image and zero on the current released image; both commands and exit codes are in the PR body (no workflow dispatch pre-merge, since dispatching the release workflow would deploy).
- [ ] The new static test is registered in `.github/scripts/test/run-all.sh` and the orphan-suite census (`lint-orphan-test-suites.sh`) reports it as run.

### Post-merge (agent-verified, no operator steps)

- [ ] The first release run after PR 3 merges shows the scan step green, verified by `soleur:postmerge`.
- [ ] `bash scripts/verify-agent-security-slice1.sh` prints `slice1-security: ok` on `main`.
- [ ] The creds-gated canary path runs the new fixture without a manual step (confirmed in the PR 1 CI run), and the CI log carries a line stating the live probe executed (a skipped probe exits 0, so the run must assert that it ran, not only that it passed).

PR bodies use `Ref #9601`, never `Closes` (the epic stays open for slices 2-3).

## Test Scenarios

- Hosted session, API-key scheme: Bash `printenv ANTHROPIC_API_KEY` → empty; Bash `printenv STRIPE_SECRET_KEY` (service connected) → value; CLI turn completes.
- Hosted session, OAuth scheme: same with `CLAUDE_CODE_OAUTH_TOKEN`; BYOK missing; both schemes set; neither set; service token absent.
- Hook: `terraform destroy` → ask; `ls && terraform destroy` → ask; `bash -c 'rm -rf ~'` → deny; `echo "terraform destroy"` → no decision; garbage stdin → ask; `SOLEUR_DISABLE_DESTRUCTIVE_GUARD=1` → no decision; no `jq` on PATH → exit 0 plus one notice; interactive, `claude -p`, `bypassPermissions` and subagent turns per the Phase 0.2 matrix.
- Release workflow: build → scan (green) → sign → mirror → deploy; build → scan (CRITICAL fixable) → stops before sign; scanner database unavailable → `scanner_error`, job fails closed, re-run keeps inputs; dispatch override with a reason → warning annotation and marker line.

## Risks and Sharp Edges

- **The deny applies to sandboxed Bash only.** Hooks and stdio MCP servers run outside the sandbox with the full env; the agent cannot start those, but the residual is recorded in ADR-272. `settingSources: []` keeps workspace settings out of the session, so a connected repo cannot loosen the config, and a `deny` entry only ever narrows access.
- **Inline `options.sandbox.credentials` honoured?** Phase 0.1 measures it; if not honoured inline, the fallback is settings delivered through the SDK `settings` option, decided at that point.
- **Service tokens and `GH_TOKEN` remain readable by a prompt-injected agent.** Deliberate for slice 1; slice 2 (#9543, `mask`) is the fix. The ADR states this plainly so nobody reads W1 as complete credential isolation.
- **Hook false positives and bypasses.** The 2026-02-24 learning is the failure class; the narrow set plus must-PASS rows is the control. The hook is a seatbelt, not a boundary: obfuscation, a script written then run, and MCP delete tools are out of scope and stated in its header.
- **Canary fixture is 87 patch versions stale.** The baseline-first commit isolates unrelated argv drift; if the replay canary fails on the baseline, that is a pre-existing defect to fix or file before W1 lands.
- **Canary fixture capture needs Anthropic credentials** (a paid Haiku turn); it runs through the existing creds-gated path, not on a developer machine by default.
- **Scan posture.** Born blocking (precedent #6517) but scoped to CRITICAL with a fix available, enabled only after the current image passes. A newly disclosed base-image CVE can block an unrelated push; the recovery sequence and dispatch override are the escape, and a re-run keeps the original inputs.
- A plan whose `## User-Brand Impact` is empty fails `deepen-plan` Phase 4.6; this one is filled.

## Implementation Notes — PR 1 (W1)

Deviations from the plan as written, each with its reason:

- **The shared constant lives in `server/agent-auth-env-vars.ts`, not in `agent-env.ts`.** `agent-runner-helpers.test.ts` mocks `@/server/agent-env` wholesale, so importing the constant from there into the sandbox config would break that suite, and the canary imports the sandbox config lazily so its graph must stay small.
- **Phase 0 used a scripted API stand-in, not a paid turn.** No Anthropic credential was available in the shell or the dev Doppler config, and the stand-in is the better instrument anyway: it removes the model from the assertion path and puts no real key in the sandbox. Its source is `test/helpers/anthropic-stub.ts`.
- **The canary fixture is not re-captured** (see the amended acceptance criterion and #9614). The argv-level guard is a new CI test that drives the canary's own capture function, so the property is checked on every run without the fixture.
- **The drift test lives in `agent-sandbox-credential-deny.test.ts`**, not `agent-runner-sandbox-config.test.ts` (that file covers Sentry tagging) or `agent-runner-helpers.test.ts` (it mocks the module the new test needs real).
- **Prompt line:** one unconditional `## Credentials` block in `agent-runner.ts`, with its test in `agent-runner-tools.test.ts`. The cc-soleur-go prompt path has no Connected Services block and is unchanged.

- **The affected gate was stopped, not completed, locally.** `bash scripts/test-all.sh --affected` (167 selected suites) ran for about two hours under sibling-worktree contention and was stopped before its epilogue: 747 suite results had passed and exactly one had failed, the `apps/web-platform [unit]` project, whose single red was `oauth-token-injection-site.test.ts` (the new names module is a second module naming the OAuth variable). That guard was sharpened (it now also pins who may reference the shared identifiers and that the names module never touches the environment; mutation-checked 4/4), and the 12 related suites, `tsc` and the canary regression suite were re-run green. The required `test` context in CI runs the full battery on the PR head and is the merge gate.

## Non-Goals / Deferrals

Tracked on the epic and its children: credential broker and `mask` for service tokens (#9543, slice 2); egress sequencing decision (#9601, operator); per-session containers and Landlock ADRs (#9602); security/control page (#9603); filing-gate refusal hint (#9604); unwrapped Playwright-MCP registrations (#8286); enabling the guard in hosted sessions (follow-up on #9601). No new deferral issues are created by this plan.
