# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-26-fix-cloud-init-doppler-download-error-channel-plan.md
- Status: complete
- Scope verified: `git diff <base-sha>..HEAD --name-only` lists only `knowledge-base/project/{plans,specs}/` paths. No source, workflow, or doc files touched by the planning subagent.

### Errors
- PreToolUse hook block (resolved): an edit was blocked for `manual-infrastructure` framing — the text had proposed a serial-console read as a diagnostic fallback, which would have violated `hr-no-ssh-fallback-in-runbooks`. Reworded to name the residual honestly; `iac-routing-ack` marker added since an `## Infrastructure (IaC)` section was already present.
- Three dangling cross-references (R16, R17, RK8) from an earlier revision, found by an integrity sweep and repointed to live anchors.
- Four of the plan's own premises falsified by deepen verification passes; each design decision survived but on corrected grounds.
- One `sleep`-based wait blocked by the shell guard; switched to a backgrounded until-loop.

### Decisions
- Fix the shared baked emitter, not the one call site. `soleur-boot-emit` has no detail channel at all, so the change lands in `soleur-host-bootstrap.sh` (0 `user_data` bytes) rather than inline in `cloud-init.yml` — decisive given a measured 516 gzipped bytes of `user_data` headroom and ~0.46 gzipped bytes per raw byte of novel shell.
- `tail -c 180` after dropping the CLI preamble, not `head -c 200`: the first 173 bytes of Doppler's stderr are `Using DOPPLER_*` preamble, so the issue's literal wording would truncate away the cause. Plus `timeout 45` with `rc=124` recorded — the failing call is the only unbounded Doppler invocation in the file (11 bounded siblings), so a hang currently emits nothing at all.
- Per-stage detail files (`/run/soleur-stage-detail.d/<stage>`) over a wire-format protocol — dissolves a delimiter collision with existing content, a legacy migration, and a stale-read hazard at once. The helper must write a `doppler_download`-scoped summary before returning non-zero, which is what keeps the fatal's detail non-empty.
- Message literals and alert-filtered stage names are frozen, and string-prefixing them is forbidden: `"stage=doppler_download_attempt".includes("stage=doppler_download")` is `true`, which would make the op-contract anti-rename test vacuous. Attempts use `doppler_retry` instead. The alert group is perpetually hot, so a stray `warning` on a filtered stage would page the operator on a healthy boot.
- The retry is retained but recorded as a User-Challenge rather than silently applied. The simplicity reviewer and both cited learnings argue for cutting it; the plan keeps it because the issue scopes it, marks Phase 2 as the designated descope target, and persists the challenge to `decision-challenges.md`.

### Components Invoked
- Skills: `soleur:plan`, `soleur:deepen-plan`
- Agents: `repo-research-analyst`, `learnings-researcher`, `soleur:engineering:cto`, `architecture-strategist`, `spec-flow-analyzer`, `code-simplicity-reviewer`, `kieran-rails-reviewer`, `framework-docs-researcher`, plus a `general-purpose` verify-the-negative pass
- deepen-plan gates 4.4 / 4.5 (fired, telemetry emitted) / 4.55 / 4.6 / 4.7 / 4.8 / 4.9 / 4.10
- Live probes: Doppler CLI v3.75.3 error-channel measurement, `user_data` byte-budget model, dash/bash `set -e` semantics, `grep -c` exit semantics, green test baselines, ADR ordinal against freshly-fetched `origin/main`
