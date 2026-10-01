---
title: Audit .claude/settings.json tool-name matchers — dead under Devin CLI
date: 2026-09-15
issue: 8205
branch: feat-settings-matcher-devin-audit
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
---

# Brainstorm: Audit `.claude/settings.json` tool-name matchers — dead under Devin CLI

Source: GitHub issue #8205 (surfaced by the 2026-09-15 Devin Cloud probe, `cloud-probe.md` item 4; part of #8159; found by #8172's web-app arm).

## What We're Building

A per-hook disposition audit and binding pass for every tool-name matcher in the repo's hook registries, so that each hook either fires under Devin CLI or carries a deliberate, documented Claude-only disposition. The deliverable is a disposition matrix (hook × matcher × in-body gate × per-harness disposition), an expanded `.devin/config.json` registry, in-body `tool_name` gate normalization, reconciled coincidental bindings, and an executable parity test that keeps the matrix honest going forward.

## User-Brand Impact

- **Artifact:** the PreToolUse guardrail corpus registered in `.claude/settings.json` + `plugins/soleur/hooks/hooks.json` + `.devin/config.json` (credential guards, secret scans, prod-write deferral — the controls cited in PA-8 §(g)/PA-31 §(g) and ADR-213).
- **Vector:** a guardrail that is registered but never fires under an advertised supported harness is a silent no-op — the operator believes credentials are protected on `exec` while nothing runs; worst case is credential exfiltration through a snapshot/exec path on a surface whose docs claim coverage.
- **Threshold:** single-user incident.

Tagged **user-brand-critical** (auto, per #5175).

## Verified Findings (premise check + research)

1. **Premise confirmed.** Devin CLI loads `.claude/settings.json` hooks by default (`read_config_from.claude`, on by default — Devin docs `extensibility/hooks/overview.mdx` "Where Hooks Live"). The 22 `Bash` matcher objects are *dead*, not unloaded: the matcher is a regex over `tool_name`, and Devin's shell tool is `exec`. No Devin-side alias maps `Bash`→`exec` (probe-measured, `cloud-probe.md:157-159`).
2. **PR #8155's fix is necessary but insufficient.** `hooks.json` matcher → `^(Bash|exec)$` + regex-evaluating test, but `browser-snapshot-credential-guard.sh:90` still runs `[[ "$TOOL" == "Bash" ]] || exit 0` — under Devin the hook fires then silently exits. ~10 scripts carry in-body `tool_name` gates (`pkill-self-match-guard.sh:51`, `post-dispatch-watch-gate.sh:59,64`, `pre-ask-technical-fork-gate.sh:66`, `skill-security-scan-write.sh:39`, `iac-plan-write-guard.sh:90-93`, `new-scheduled-cron-prefer-inngest.sh:62-65`, `security_reminder_hook.py:197`, `durable-reminder-prefer-inngest.sh:75`, `doppler-secrets-delete-redirect.sh:35`, `background-poll-prefer-monitor.sh:108`).
3. **Double-fire is already live, not hypothetical.** `.devin/config.json` binds `guardrails.sh` on `^exec$` and `^(write|edit|multi_edit|notebook_edit)$`; `settings.json` also binds it on `write` and `ask_user_question` (twins added for Grok in #8061 — same names as Devin's tools, coincidence). Devin loads both files; nothing dedupes cross-source.
4. **The coincidental `write` twins over-bind.** Unanchored `write` also substring-matches `todo_write` — dispatch overhead (and for `skill-security-scan-write.sh`/`iac-plan-write-guard.sh`/`new-scheduled-cron-prefer-inngest.sh`, a fire-then-exit path) on a tool never intended.
5. **Full cohort is wider than `Bash`.** `Write|Edit`, `Write|Edit|MultiEdit|NotebookEdit`, `Write`, `Edit`, `AskUserQuestion`, `Skill`, `Monitor`, `Monitor|TaskStop`, `Task`, `CronCreate` matchers are all dead under Devin; `permissions.allow` `Bash(...)` ×5 and `permissions.deny` `Read(...)` ×10 use the same dead vocabulary. Repo-wide `Bash`-matcher bindings: 25 (22 settings.json + hooks.json + `.codex/config.toml`).
6. **Cloud is out of scope.** The 2026-09-15 probe measured NO repo-level hooks dispatching in Devin Cloud (both registries inert, both arms). #8205 is a local-CLI defect class.
7. **Legal surface.** `devin/INSTRUCTIONS.md:91` asserts "Devin supports the bundled Bash credential guard" — currently false; correction required regardless of approach. PA-8 §(g)/PA-31 §(g) register claims need a dated scope clarification conditioned on the fixing PR's merge. No breach-register row is owed absent evidence of actual exposure; the unmeasured Devin→Cognition transcript path is the pending #8119 re-attestation trigger. `ccla-register.md` has no Cognition/Devin bot entry.
8. **Env-var risk.** All 58 settings.json hook commands interpolate `$CLAUDE_PROJECT_DIR`; `.devin/config.json` deliberately uses `$(git rev-parse --show-toplevel)`. Whether Devin sets `CLAUDE_PROJECT_DIR` for repo-settings hooks is unverified.
9. **Coupled gates that will go red on naive edits:** `hookeventname-coverage.test.sh` (`select(.matcher=="Bash")`, `n_bash ≥ 15` floor), `hook-input-contract.test.sh` A9 (splits matcher on `|` — `^(Bash|exec)$` produces pseudo-tokens `^(Bash`/`exec)$`), `ship-unpushed-commits-gate.test.sh:362`, `settings-hook-exec-bit.test.sh` (entry counts), `workflow-fidelity.test.ts` Guard 2 (forbids `|` matchers containing Grok names — `exec` is permitted).
10. **Envelope unknowns (measure, don't assume):** does Devin's `exec`/`write` envelope carry `.tool_input.command`/`.tool_input.file_path`? Does it set `CLAUDE_PROJECT_DIR`? Empirical capture per the 2026-05-10 hook-input-shape learning is a task-level prerequisite.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Registry strategy | **Per-harness registries** | `.claude/settings.json` stays Claude-canonical; `.devin/config.json` expands to the triaged Devin subset (OpenHands `.openhands/hooks.json` precedent, ADR-215 Codex minimal-subset precedent). Coincidental `write`/`ask_user_question` settings.json twins stay (Grok-required) but get anchored (`^write$`) to stop `todo_write` over-binding. |
| Scope | **Full matcher matrix** | Cohort boundary is the mechanism (Claude-only tool names), not the literal `Bash` string — includes Write-family matchers, in-body `tool_name` gates, `permissions.allow/deny` rules, and the over-binding fix. (Per `fix-one-instance-then-audit-the-whole-cohort` learning.) |
| Disposition convention | **Bind-or-documented-skip per hook** | Grok FR6 / Property 5 format: safety hooks that can fire on Devin-named tools do fire; tools Devin lacks (`Monitor`, `Skill`, `CronCreate`, `Task`, `TaskStop`) get documented skips (`reason=no-tool`), never fake matchers. Per-hook reasons, not a blanket disclaimer (`.claude/hooks/README.md` disposition-registry precedent). |
| In-body gates | **Normalize via `hook-input.sh`** | One auditable tool-kind mapping (canonical `HOOK_TOOL_KIND`: exec→shell-class, write/edit→file-class) rather than N hand-edited `== "Bash"` checks; per ADR-110 one-map precedent. Each gate's widening verified per hook. |
| Enforcement | **Executable parity test, not prose** | Extend the Guard-2 family: a checked-in triage ledger (hook → per-harness disposition) asserted by a contract test with non-vacuity controls; matcher assertions evaluate the regex against candidate tool names (the #8155 `test($m)` pattern), not string equality. Update the four coupled gates in the same PR. |
| Sequencing | **Separate PR after #8155** | Independent branch off main; flag the credential-guard body gap to #8155 via PR comment; absorb the small `.devin/config.json` conflict at merge. |
| Docs/legal | **Correct regardless of binding outcome** | `INSTRUCTIONS.md:91` claim conditioned on reality; ADR-213 addendum stating Devin coverage plainly (per its "unstated gap is the failure mode" doctrine); PA-8/PA-31 dated scope clarification conditioned on merge; `compliance-posture.md` dead-window inventory note. |
| Productize candidate | `hook-harness-disposition` lint | Every new hook must declare a per-harness disposition at authoring time; the parity test is the productized artifact — no separate skill needed. |

## Approaches Considered

- **A. Dual-bind in settings.json (Grok FR6 wholesale):** widen matchers in place (`Bash|exec` style). Rejected — Devin loads `.devin/config.json` too, so in-place dual-binding while `.devin/config.json` retains its own bindings reproduces the Grok double-fire class cross-source; also doesn't scale to a fourth harness.
- **B. Per-harness registries (CHOSEN):** matches the repo's established shape (OpenHands, Codex minimal set); one triage artifact; needs the cross-registry parity test to prevent drift.
- **C. Generated SSOT manifest → per-harness outputs:** true single source; rejected as over-built for ~40 entries — generation-drift risk exceeds the payoff at this size.

## Open Questions

- Does Devin's `write`/`edit` envelope carry `.tool_input.file_path` (snake_case) so shape-driven hooks work when they dispatch? Measure via stub-hook capture before binding decisions are finalized per hook.
- Is `CLAUDE_PROJECT_DIR` populated under Devin? If not, bound hooks must use the `git rev-parse` pattern (`.devin/config.json` precedent).
- Should the four structurally-unbindable hooks (`Monitor`, `Skill`, `CronCreate`, `Task`-family) get Devin-side equivalents (`get_output`, `run_subagent`) or `reason=no-tool` skips? Default: documented skip per Grok Property 5.
- Cloud sessions: no hooks dispatch (measured) — does the capability matrix/banner need to name this explicitly as an accepted gap, or does a follow-up issue track cloud hook support?

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Product (CPO)

**Summary:** A dead guardrail on an advertised supported harness is a trust/brand surface — the Devin parity plan's own User-Brand Impact names this failure class. This is a solved problem class (Grok FR6 is the template); scope is days not weeks. Recommended adopting the bind-or-skip framework, plus correcting `INSTRUCTIONS.md:91` regardless. Flagged the support-tier question (supported vs compatible) and registry-location question, both resolved by the decisions above.

### Legal (CLO)

**Summary:** A shipped doc asserts a control that does not exist — same defect class as the #6588 Art. 32 TOM retraction. Recommended actions: verify #8155's body-check widening (P1, verified absent on the branch), correct the INSTRUCTIONS.md claim, append dated scope clarifications to PA-8/PA-31 conditioned on merge, record the dead-window in compliance-posture.md, and measure the Devin→Cognition transcript path (the #8119 re-attestation trigger). No breach-register row owed absent actual exposure. Open CLA question: no Cognition/Devin bot entry in `ccla-register.md`.

### Engineering (CTO)

**Summary:** Three-plus registries with no SSOT; defect is two-layered (matcher + body). Recommended per-harness registries (chosen) with a `hook-input.sh` normalizer and a checked-in triage ledger asserted by a contract test. Flagged `permissions.allow/deny` as same-class scope, the settings.json↔`.devin/config.json` double-fire risk, and recommended an ADR for the per-harness hook-registry strategy.

## Session Errors

None.

## Deferred Items

- Measure the Devin cloud session→Cognition transcript path (#8119 re-attestation trigger) — legal/infra follow-up, not this PR.
- `permissions.allow/deny` rules are in scope for audit documentation; if Devin's permission system needs its own rule syntax, the rewrite may defer to a follow-up.
- Cloud hook support (no registry dispatches in cloud sessions, measured) — accepted gap for #8159's capability matrix or a follow-up issue.
