---
title: "feat: Devin Cloud session parity — Soleur Cloud Mode (honest degradation)"
type: feat
date: 2026-09-14
slug: feat-devin-cloud-session-parity
branch: feat-devin-cloud-session-parity
issue: 8159
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
priority: p2
---

## Overview

Implement "Soleur Cloud Mode" per spec `knowledge-base/project/specs/feat-devin-cloud-session-parity/spec.md`: detect Devin Cloud sessions, disclose absent enforcement surfaces (plugin subagents, plugin hooks), generalize the shipped sequential-fallback contract, gate secrets/prod-touching skills behind an explicit cloud acknowledgement, restore critical guardrails as skill-invoked scripts, add `requiredPlugins` to `.devin/config.json`, ship an honest capability matrix plus CLO-required legal disclosures, and empirically resolve the platform open questions in a real cloud session.

## Research Insights

### Premise Validation (Phase 0.6)

- Cited refs all verified live: #8159/#8160/#8161/#8162 OPEN; PR #8155 OPEN draft. All cited paths exist on `origin/main`.
- **Stale premise found:** `plugins/soleur/hooks/devin-session-start.sh` writes **no sentinel** today — it only emits `additionalContext`. FR1's "sentinel written by devin-session-start.sh" is proposed behavior; the write is new work (scope-guarded per `welcome-hook.sh:18-24` precedent).
- **Docs drift (bigger):** current `docs.devin.ai` documents plugin `hooks.json` `command` hooks as running **in cloud sessions** for every event except `SessionStart`/`SessionEnd` (`PreToolUse`, `Stop`, `PostToolUse`, etc.); `prompt`-type hooks are CLI-only. The brainstorm/spec premise "plugin hooks do not load in cloud" is partially stale — plugin `command` hooks (credential guard, DONE stop-gate) are now documented as working in cloud. Repo-level hooks (`.devin/config.json`, `.claude/settings.json`) remain **undocumented** — the surviving pivotal unknown.
- ADR corpus check: no rejected-mechanism collision. Governing ADRs: **ADR-089** (cross-harness state = gitignored runtime file resolved repo-root-relative — sentinel is the same class), **ADR-093** (plugin source is platform-deployed root; workspace copy untrusted — sentinel must land in repo `.devin/`, not the plugin install cache), **ADR-178/179** (shared bash primitives ship in `plugins/soleur/scripts/lib/`; markdown references use bare `${CLAUDE_PLUGIN_ROOT}` anchors).

### Property List (Phase 0.6b)

- **P1** Distinguish cloud from local sessions. **P2** In-band disclosure of absent surfaces. **P3** Fan-out skills complete without plugin subagents. **P4** Informed consent before secrets/prod mutation on a third-party VM. **P5** Critical guardrails enforce without relying on hook execution. **P6** Plugin auto-loads in fresh cloud clones. **P7** Honest capability record for users + legal. **P8** Platform unknowns resolved by measurement.

### Cut List (Phase 0.6b)

- No spec mechanism duplicates existing machinery. `emit-review-trailer.sh`, `prod-write-defer-gate.sh`, `welcome-hook.sh` sentinel pattern, and the `INSTRUCTIONS.md:83-85` sequential contract are **extended**, not replaced. Degradation ledger (brainstorm D4) folds into the trailer/disclosure strings — no separate artifact.

### Research Findings

**Detection:** `detectCloudSession()` is a *capability-surface modifier* on the `"devin"` Harness arm (learning `2026-09-11-meta-harness-is-not-a-third-harness-union-member.md`), not a new union member — it slots after `detectHarness()` at `harness.ts:~115` (fs-aware sibling `agent-registry.ts` is the precedent for fs access in lib). Sentinel: `.devin/soleur-local-session` written by `devin-session-start.sh` on SessionStart — absent in cloud because SessionStart never fires there at plugin level (documented) or repo level (if repo hooks fire at all, SessionStart is the excluded event anyway). `.devin/*` is gitignored — the sentinel can never commit and become a false "local" marker in a cloud clone. Test discipline per `2026-09-02-i-built-a-host-discriminator-out-of-an-absence`: fixture BOTH arms; assert the never-value (banner emitted while sentinel present).

**Banner:** once-per-session sentinel (`.devin/soleur-cloud-bannered`, `welcome-hook.sh` shape), emitted via shared include `devin/references/cloud-mode.md` + `scripts/cloud-banner.sh`, stderr/out-of-band — never stdout JSON. Naming absent surfaces explicitly (learning: silence is the bug).

**Fallback:** extend `INSTRUCTIONS.md:83-85` contract + `emit-review-trailer.sh` semantics to all 22 spawn-site SKILL.mds; machine-readable `Reviewed-Coverage: inline-fallback` trailer; `/ship` treats inline-fallback on `single-user incident` as blocking per `2026-08-03-the-degraded-review-labelled-itself`.

**Ack gate:** build on `prod-write-defer-gate.sh` machinery (fail-closed defer envelope, `approvals.jsonl`, bypass protocol); session-scoped ack only — never a persisted ack file (replay-hole class, `2026-07-06-body-hashing-guardrail-gate-fail-open-classes`); honest exit required (`2026-09-11-a-filer-with-no-honest-exit`).

**Guardrail extraction:** hooks become thin wrappers over `plugins/soleur/scripts/` entrypoints (ADR-178); extraction must preserve `guardrails.sh` ordering semantics (freeze-lock early-exit) and its `.claude/hooks/lib/` dependencies (`resolve_command_cwd`, `emit_incident`).

**Legal (FR8):** three-doc lockstep + SHA repins (`legal-doc-shas.ts`) + Eleventy mirrors + two independent mirror gates (`check-tc-document-sha.sh` AND `legal-doc-consistency.test.ts`); Art. 30 edits are **appended brackets, never edits**; no Cognition processor-table row (no DPA — per 2026-09-13 attestation); temporal qualifiers for not-yet-true claims; CLO routes the wording (SC5).

**Cloud-probe posture:** repo-level hooks treated as absent for design, probed empirically first (probe gates fallback scope). Cloud Routines incident (`2026-04-21-cloud-routine-subagent-auth-inheritance-H6`): vendor cloud sub-agent surfaces lose auth/capability silently — probe `run_subagent` artifact output, not just invocation success.

### Open Code-Review Overlap

Queried 65 open `code-review` issues against the planned file set (Phase 1.7.5). Four body-matches, all directory-level tangents — dispositions:

- **#7942** (`*.mutation.sh` batteries un-gated in `plugins/soleur/test/`): **acknowledge** — this plan adds a `bun:test` suite, not a mutation battery; different concern, needs its own cycle.
- **#4133** (Observability-block schema parity test): **acknowledge** — schema-test follow-through, not a file conflict.
- **#3531** (marketing-content-drift flake) and **#3216** (old review findings): **acknowledge** — unrelated files.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Codebase reality | Plan response |
|---|---|---|
| "plugin subagents and plugin hooks do not [load in cloud]" | Plugin `command` hooks are **now documented** as running in cloud for all events except `SessionStart`/`SessionEnd` (docs.devin.ai plugins-overview + plugin-ecosystem, post-2026-09-14 revision). Subagents remain local-only. Repo-level hooks still undocumented. | FR5's motive narrows to SessionStart-class + unverified repo hooks; the cloud probe (Phase 0) empirically confirms command-hook execution before FR5's extraction scope is frozen. Capability matrix rows state per-event granularity, not a binary "hooks absent." |
| "the local-session sentinel written by devin-session-start.sh" | `devin-session-start.sh` writes **no sentinel** — it only emits `additionalContext` (9 lines). | Sentinel write is net-new Phase-1 work — content-bearing (`{host, ts, hook_source}`), unconditional under Devin env, `|| true`-guarded after the JSON emit. |
| "~15 prod/Doppler skills" | 21 enumerated skills exist, and the spec-flow review found ≥9 more secrets/prod sites the enumeration missed (`work`/`preflight`/`one-shot`/`plan`/`brainstorm`/`schedule`/`community`/`pencil-setup`/`rclone`). | The ack-gate set is **grep-derived at implementation time**, not enumerated — SC3 verifies the invariant, not the list. |
| 22 spawn-site SKILL.mds (repo inventory) | The inventory missed ≥5 confirmed spawn sites (`compound`, `code-to-prd`, `frontend-design`, `product-roadmap`, `spec-templates`). | Spawn-site set is **grep-derived**; AC4/SC2 verify "every SKILL.md that spawns", not a frozen list. |
| "credential guard" in guardrails.sh | The credential guard is `plugins/soleur/hooks/browser-snapshot-credential-guard.sh`, not inside `guardrails.sh`. | FR5 extraction covers the commit-on-main block (`guardrails.sh:129-155`) + DONE-marker check (`stop-hook.sh:149-160`); the credential guard stays a hook (documented as cloud-functional) unless the probe refutes. |
| Cloud probe is a verification tail | Probe results reshape FR5 scope (repo hooks firing in cloud restores guardrails for free). | Probe promoted to **Phase 0** — run before design freeze, not after. |

## Problem Statement

Devin Cloud sessions load Soleur's skills, plugin `AGENTS.md` rules, MCP servers, and repo `requiredPlugins` — but plugin subagents are documented local-only, `SessionStart`/`SessionEnd` hooks never fire in cloud, and repo-level hooks are undocumented. Soleur's orchestration depends on agent fan-out (22 spawn-site SKILL.mds) and on SessionStart injection for the entire `AGENTS.rules.md` corpus + Devin tool-mapping contract. A `/soleur:*` pipeline run in cloud silently produces weaker output — undisclosed degradation, this repo's worst failure shape (learning `2026-08-03-the-degraded-review-labelled-itself`).

## Proposed Solution

"Soleur Cloud Mode": plugin-carried detection + honest degradation on the surfaces guaranteed to load in cloud (skills + plugin `AGENTS.md`). Sentinel-based detection (never env-sniffing an undocumented marker), a once-per-session capability banner, generalized sequential-fallback with machine-readable disclosure, a session-scoped cloud-ack gate on 21 secrets/prod skills, skill-invoked guardrail scripts for the hook backstops that cannot run, `requiredPlugins` for cloud auto-install, an honest capability matrix, CLO-required legal disclosures, and an empirical probe that resolves the undocumented surfaces before design freeze.

## Technical Approach

### Architecture

- **Detection:** `plugins/soleur/scripts/cloud-detect.sh` is the ONE classifier — `local` or `not-local:<reason>` (`sentinel-absent | foreign-host | non-plugin-source | malformed | no-devin-env`), fail-closed. **No `detectCloudSession()` in `harness.ts`** — verified: `harness.ts` functions are consumed only by `go-routing.ts`, which is called only by tests; the TS file is a canonical spec, not runtime code (spec FR1's "(or a sibling lib)" reading = `scripts/cloud-detect.sh`; a spec note records the amendment). The Devin arm of `spawnAgent`/`routingInstructions` needs no detection branch — INSTRUCTIONS.md:83-85 already carries the *unconditional* "if subagents are unavailable" contract. `devin-session-start.sh` writes `.devin/soleur-local-session` **unconditionally** on SessionStart under Devin env — NO `plugins/soleur/` dir guard (a vendored-checkout guard inverts detection in user repos, the primary `requiredPlugins` audience). The sentinel is **content-bearing JSON** `{host, ts, hook_source}` — `host` = `hostname`, `hook_source` = which registration fired (repo `.devin/config.json` vs plugin `hooks.json`). Classification: `local` = sentinel present AND `host` matches AND `hook_source` = plugin registration (plugin SessionStart is documented-absent in cloud → a plugin-sourced sentinel is proof-of-local; a **repo-sourced** matching-host sentinel — the arm where repo SessionStart fires in cloud — classifies `not-local`, closing the false-local hole); `not-local` otherwise. Content-bearing design survives a sentinel committed in a user repo (host mismatch) and repo-level SessionStart firing in cloud (`hook_source` mismatch); `/handoff` copying the worktree is retired as a transport — measured 2026-09-17 (#8172 residual arms): it carries committed content only, uncommitted/untracked/gitignored files do not arrive. `hook_source` doubles as probe data. Sentinel lives in the repo `.devin/` (gitignored — ADR-093: never write the plugin root; ADR-089: repo-root gitignored runtime state).
- **Banner/contract:** the canonical cloud-mode contract text lives in **`devin/INSTRUCTIONS.md` §Cloud Mode** — already loaded on every `go`-routed Devin session via the `devin/skills/go/SKILL.md` shim — plus a section in **`plugins/soleur/AGENTS.md`**, the guaranteed-load surface the spec names (G4/TR2). `scripts/cloud-banner.sh` emits the banner **per invocation** — stateless, no second sentinel, disclosure can't be missed (a `--banner` flag on `cloud-detect.sh` is an acceptable merge). Session-boundary/compaction: the **documented cloud-capable `PostCompaction` hook** is the structural fix for context loss + ack re-priming — its use requires a spec NG5 revision (escalate at implementation, not inherit). Caller precondition: the contract gates on positive Devin identity *first*, then consults detection — a Claude Code session must never see cloud banners or acks. Per-skill reach: **one composite `<!-- soleur-cloud-mode:start/end -->` pointer block** per SKILL.md in the grep-derived union set (single drift-pin, satisfies SC2) — routed sessions already get the contract via INSTRUCTIONS.md; the blocks cover direct `/soleur:<skill>` invocations and the spec's grep-verified sets.
- **Fallback:** every SKILL.md that spawns agents gains the degrade path — the set is **re-derived by grep** (spawn-site signals: `run_subagent`, `Task spawn`, `Agent tool`, `fan out`, `IN PARALLEL`), not the 22-item repo-inventory list, which missed `compound` (:16,118-139 — canonical stage of `one-shot`), `code-to-prd` (:28), `frontend-design` (:56), `product-roadmap` (:148-150), `spec-templates` (:245), and borderline `gdpr-gate`/`skill-creator`. The fallback trigger is a **static branch on detection** — plugin subagents are documented-absent in cloud, so `not-local → run roles inline + disclose`; no runtime artifact-probing machinery for a case that cannot succeed (if the probe reveals `run_subagent` can somehow load plugin agents, the check is added then — probe-conditional like FR5). Degrade path: execute the role definition sequentially inline + emit the disclosure string + the `emit-review-trailer.sh` coverage flag (`Reviewed-Coverage: sequential-fallback` — a bare flag; no N/M numerator to define and validate). `/ship` treats `sequential-fallback` coverage on `single-user incident` as blocking (`2026-08-03` learning — this feature's own threshold).
- **Ack gate:** a shared cloud-ack block sourced by the secrets/prod skills (set re-derived by grep, not enumerated — see Phase 2) — session-scoped acknowledgement, honest exit (decline = documented alternative or explicit abort, never refusal-only), never a persisted ack file (replay-hole class; session-scope = in-context memory for the session, re-ask after compaction — fail-safe direction). **Mechanism is probe-frozen:** cloud sessions run under permission modes that may auto-answer prompts — if the probe shows `ask_user_question` auto-approves or stalls, the gate is a hard-defer ("secrets/prod steps require an attended session"), not an interactive ask. Reuses `prod-write-defer-gate.sh`'s *posture and ledger conventions* (not the `permissionDecision: defer` envelope — that's a hook return shape skills can't emit); the ledger writes under `.devin/` (the sentinel dir the plan already requires) — user repos lack `.claude/`, and the audit record matters most exactly there.
- **Guardrail extraction:** `plugins/soleur/scripts/precommit-guard.sh` (new) exec'd directly by `work`/`ship`/`one-shot` — **self-contained** (~40 lines: `git rev-parse --abbrev-ref` + command grep for the commit-on-main check). **No vendored lib** — `.claude/hooks/lib/incidents.sh` resolves repo root via `BASH_SOURCE`-relative paths that land in the plugin install cache when vendored (a drift-prone fork — the exact duplication ADR-178 avoids); `emit_incident` degrades gracefully in user repos. **No DONE-marker arm** — that check reads hook-stdin transcript data a script cannot see; it stays prose + plugin Stop hook (structural where it runs, pending probe). Hook scripts remain thin wrappers (ADR-178 location, ADR-179 bare-root anchors); `guardrails.sh` ordering semantics preserved.
- **Delivery:** `"requiredPlugins": ["jikig-ai/soleur#plugins/soleur"]` in `.devin/config.json` (documented honored "from each cloned repository" in cloud). (**Superseded 2026-09-17** — the shorthand was never the shipped form, and the full-URL string form that did ship (#8234) 404s through the cloud git-manager proxy; the measured-required form is the `git-subdir` object — spec FR6 / `cloud-probe.md` §Item 5.)
- **Probe:** Phase 0 — `/handoff` or web-app cloud session on this repo, results in `specs/feat-devin-cloud-session-parity/cloud-probe.md`: Q1 repo-level hooks, Q2 `run_subagent` built-in profiles, Q3 detection signals, Q4 `.claude/settings.json`, plus confirmation plugin `command` hooks actually execute (docs say yes — verify, don't assume).
- **Legal:** cloud mode creates a third configuration the two-category taxonomy (plugin-local / operator-assisted) does not name: third-party machine + user credential + user purpose. **Floor (non-negotiable):** correct the affirmatively-false statements — DPD §3.1(a) "executes entirely within the User's local CLI environment", §2.1(c) "exclusively on the User's local filesystem" — and name the third configuration where the taxonomy is asserted (DPD §2.1c classification table gains a fifth row). **Ceiling at CLO's discretion:** definition-level three-configuration taxonomy applied corpus-wide (~148 boilerplate sites + mirrors — GDPR gate recommendation; plan-review favors the floor). Art. 30: **per-entry audit**, not blanket "local sessions" rescope — the register's PreToolUse TOMs (PA-31 §(g)) are ephemeral-CI-workspace measures, not local-session ones; the amendment instead records the *absence* of plugin-hook controls on third-party-hosted sessions, keyed by where each measure executes, wording probe-informed. Probe-conditional: if the probe names the inference path/provider, the three-doc update carries a **named Cognition entry** (provider named, Jikigai-processor denial stated), not only a scope row. `compliance-posture.md` gets a Completed-Work row + the D10 prohibition recorded; flag the TC_VERSION tier question to CLO. Eleventy mirrors + `legal-doc-shas.ts` repins in lockstep; no Cognition processor row (no DPA — 2026-09-13 attestation); temporal qualifiers on not-yet-true claims; CLO routes wording (SC5).

### Implementation Phases

#### Phase 0: Empirical cloud probe (FR9) — operator-gated dependency, not an implementer task

Phase 0 requires an operator-credentialed cloud session (TR7) — an implementer cannot run it, and cloud sessions may be access-limited. **Sequencing rule:** Phases 1–2 may implement against the documented-absence default (the honest conservative scope); Phase 3's extraction scope, Phase 4's matrix rows, Phase 5's Art. 30 wording, and merge-readiness are frozen on the probe result OR an explicit deferral (`wg-block-pr-ready-on-undeferred-operator-steps` applies — the probe is an operator step).

**Pre-probe gate (GDPR):** before the session runs, record a written determination: whose Devin account, whose billing entity, whose API keys are reachable in-session. If ANY limb is Jikigai's (Jikigai-provisioned seat, Jikigai `ANTHROPIC_API_KEY`, Jikigai Doppler creds reachable), escalate to CLO *before* the probe — D10 is pre-emptive, not post-hoc. The probe satisfies the Art. 30 register's purpose limb (Jikigai engineering purpose, PA-35 precedent) — record either a new PA-37 register entry (appended, per register convention) or a written out-of-scope determination. `cloud-probe.md` gets a one-paragraph DPIA-screening note (systematic description, necessity, risk to third-party data subjects in repo content — git authorship, committed digests — compensating measures).

- Run one `/handoff` or web-app Devin cloud session on this repo (operator-credentialed test scope only — TR7; minimize `cloud-probe.md`'s env-signal capture to non-identifying signals).
- Probe checklist (record each with evidence):
  - **Q1 split per-event:** does a repo-level `.devin/config.json` `SessionStart` hook specifically fire in cloud? (Plugin SessionStart is documented-absent; repo-level is the unknown — the answer decides whether a cloud session could write a *cloud-host* sentinel, which the content-bearing detector already handles.) Also test repo-level `PostToolUse`/`Stop` command hooks with a marker file.
  - **`ask_user_question` in an unattended cloud session:** the FR4 mechanism hinges on this — does an ask auto-approve (fail-open catastrophic), block indefinitely (stall), or return a distinguishable unanswered/timeout state (design works)? The ack mechanism choice (interactive ask vs. hard-defer) is frozen on this answer.
  - **Per-hook, per-matcher binding:** "plugin command hooks run in cloud" ≠ *our* hooks fire — `hooks.json` registers `matcher: "Bash"` while Devin's shell tool is `exec`. Verify per-hook whether the matcher translates; a matcher that never matches is a silent no-op (the failure class this feature exists to kill). Check each registered plugin hook individually, not just hook-infra liveness.
  - **Repo-level `requiredPlugins`:** does `.devin/config.json` `requiredPlugins` actually install the plugin in a fresh-repo cloud session (the probe's own environment can test it), and does an unknown key break local hook registration? FR6's placement is unverified — the docs anchor exists for plugin manifests, not repo config.
  - **`/handoff` worktree sync:** does handoff carry gitignored `.devin/` files to the cloud VM? (Determines whether a local sentinel can arrive foreign — host compare covers it, but record the behavior.) — **measured 2026-09-17: NO** (cloud-probe.md residual Item 6).
  - **Q2 `run_subagent`:** do built-in profiles (`subagent_explore`/`subagent_general`) exist and produce artifacts in cloud — artifact output, not just invocation success (Cloud Routines lesson)?
  - **Q3 env/session signals:** what `DEVIN*`/env markers exist in cloud AND do they propagate to `exec` tool shells? Is a session-id env var available in exec context (the banner's session-boundary oracle)?
  - **Q4 `.claude/settings.json`:** do repo-level Claude-format hooks fire?
  - **`PostCompaction` hooks:** documented cloud-capable — confirm; a PostCompaction hook re-emitting cloud-mode context would structurally solve banner loss + ack re-priming across compaction (requires spec NG5 revision — escalate, don't inherit).
  - **Plugin command hooks:** confirm actual execution (docs say yes — verify, don't assume); record `hook_source` from any sentinel written.
- Success: all checklist items answered with evidence; FR4 mechanism choice, FR5 extraction scope, capability-matrix rows, Art. 30 amendment wording, and the banner session-boundary mechanism finalized from measured data.
- Effort: hours.

#### Phase 1: Detection + sentinel + requiredPlugins (FR1, FR6, TR1)

- `devin-session-start.sh`: add the **unconditional** (Devin-env-only guard) content-bearing sentinel write `{host, ts, hook_source}` to `.devin/soleur-local-session` — `|| true`-guarded and ordered AFTER the `additionalContext` JSON emit, so a write failure can never kill the hook or its context injection (`set -euo pipefail` is in effect). `hook_source` distinguishes repo-config vs plugin registration. The write needs git-root resolution + `mkdir -p .devin` — user repos (the `requiredPlugins` audience) may lack `.devin/`; a silent write-fail there is permanent false-cloud on their local sessions.
- `scripts/cloud-detect.sh`: the ONE classifier emitting `local` or `not-local:<reason>`; single `hostname` source on both write and compare sides; **no `jq` dependency** — parse defensively, fail closed to `not-local` on any tool absence or malformed state. No `detectCloudSession()` in `harness.ts` (test-only surface — spec note records the "sibling lib" reading); no spawn-surface edits (INSTRUCTIONS.md:83-85 already carries the unconditional fallback contract).
- `test/devin-cloud-mode.test.ts` (bun:test subprocess-driving the bash script, `devin-plugin.test.ts` fixture pattern): all arms — `local` (sentinel + matching host + `hook_source=plugin`), each `not-local` reason (absent / foreign-host / repo-sourced / malformed / no-env); never-value: banner emitted under a valid local sentinel = fail.
- `.devin/config.json`: `"requiredPlugins": ["jikig-ai/soleur#plugins/soleur"]` (**superseded 2026-09-17**: `git-subdir` object form required — spec FR6) — **validate before merge** that an unknown key doesn't break local hook registration (parse-fail would silently kill SessionStart/PreToolUse registration repo-wide locally); probe confirms cloud install behavior.
- Success: `bun test plugins/soleur/test/` green; foreign-host and repo-sourced sentinels classify `not-local`; unknown-config-key tolerance verified.

#### Phase 2: Contract surfaces + one wiring pass (FR2, FR3, FR4, TR2, TR3)

The canonical contract lives on the two guaranteed-load surfaces; per-skill reach is one composite pointer.

- `devin/INSTRUCTIONS.md` §Cloud Mode: the canonical contract text (banner disclosure + sequential-fallback degrade path + cloud-ack posture + absent-guardrail disclosure) — loaded on every `go`-routed Devin session via the existing `devin/skills/go/SKILL.md` shim.
- `plugins/soleur/AGENTS.md`: the cloud-mode rules section (guaranteed-load plugin surface, spec G4/TR2 — `[id:]` convention for new rules).
- `scripts/cloud-banner.sh`: per-invocation banner emit (stateless, no dedup sentinel), delegates detection to `cloud-detect.sh`.
- Grep-derive the union set in one pass: spawn-sites (`run_subagent`, `Task spawn`, `Agent tool`, `fan out`, `IN PARALLEL` — must include compound, code-to-prd, frontend-design, product-roadmap, spec-templates; verify gdpr-gate/skill-creator mechanism) ∪ secrets/prod (`doppler secrets`, `terraform apply`, `gh api -X POST/PUT/DELETE/PATCH`, `--plain`, prd endpoints — must include work, preflight, one-shot, brainstorm, plan, schedule, community, pencil-setup, rclone) ∪ directly-invocable pipeline skills.
- Wire **one composite `<!-- soleur-cloud-mode:start/end -->` pointer block** per SKILL.md in the union set — single marker, single drift-pin (SC2 grep-verifiable).
- `emit-review-trailer.sh`: `Reviewed-Coverage: sequential-fallback` flag (the script already supports `--mode inline-fallback` — enum widen, ~1 line) in deliverables + PR trailers.
- `ship` gate: `sequential-fallback` coverage on a `single-user incident` plan = blocking unless acknowledged.
- Success: contract text on both guaranteed-load surfaces; every union-set member carries the composite marker (grep-verified); `not-local` shows reason-aware copy; a secrets/prod action in cloud defers when unanswered (SC3-shape).

#### Phase 3: Skill-internal guardrails (FR5)

- `scripts/precommit-guard.sh`: self-contained commit-on-main check (`git rev-parse --abbrev-ref` + command grep, ~40 lines), exec'd by `work`/`ship`/`one-shot` directly; `emit_incident`-class logging degrades gracefully where `.claude/` is absent. NO vendored lib, NO DONE-marker arm (a script can't interpose turn-end — that check stays prose + plugin Stop hook, structural where it runs, pending probe).
- `.claude/hooks/guardrails.sh`: delegate its commit-on-main block to `precommit-guard.sh` (plugin = canonical source; repo reaches in — the `incidents.sh`/`session-state.sh` precedent) so the hook path and skill path enforce identically.
- The capability matrix must enumerate which repo guardrails are **not** restored in cloud (prod-write-defer-gate, worktree-write-guard, secret-scan, freeze-lock, ~30 total) — honest partial coverage, not implied parity.
- Success: the commit-on-main check fires without hook execution in a repo lacking `.claude/`; ordering semantics preserved.

#### Phase 4: Capability matrix + upstream requests (FR7, FR10)

- `devin/INSTRUCTIONS.md`: cloud-vs-local surface matrix (skills / AGENTS.md rules / MCP / subagents / plugin command hooks per event / repo hooks per probe), extended fallback contract, MCP-auth-via-web-app note, upstream request register (#8160).
- `README.md` + `plugins/soleur/README.md` Devin sections link the matrix.
- Success: every matrix row cites a doc anchor or probe result; "undocumented" rows marked probe items.

#### Phase 5: Legal disclosures (FR8, TR6)

- **Floor = targeted corrections** (non-negotiable): correct the affirmatively-false statements (DPD §3.1(a), §2.1(c)), name the third configuration (third-party machine + user credential + user purpose) where the taxonomy is asserted, DPD §2.1c fifth table row. **CLO sizes the diff beyond the floor** — the GDPR gate recommends the definition-level three-configuration taxonomy corpus-wide; plan-review favors targeted corrections. The floor is honest either way; CLO decides the ceiling.
- Art. 30 **per-entry audit** (no blanket "local sessions" rescope — PA-31 §(g) TOMs are ephemeral-CI, not local-session); record plugin-hook control absence on third-party-hosted sessions, keyed by where each measure executes, wording probe-informed.
- Register the probe outcome: PA-37 entry or written out-of-scope determination (from Phase 0's pre-probe gate).
- Probe-conditional named Cognition disclosure if the probe names the inference path; `compliance-posture.md` Completed-Work row + recorded D10 prohibition; TC_VERSION tier question flagged to CLO.
- Eleventy mirrors; `legal-doc-shas.ts` repins; CLO attestation record (SC5 — CLO routes the wording, `2026-08-09-legal-decisions-route-to-clo-not-operator`).
- Success: `legal-doc-consistency.test.ts` + `check-tc-document-sha.sh` green; zero remaining "own machine" predicate statements that exclude the cloud configuration while describing plugin behavior; CLO sign-off recorded.

#### Phase 6: ADR + C4 + verification session

- ADR (new, provisional ordinal — re-derive against `origin/*` at write time and re-verify before merge): "Soleur Cloud Mode — sentinel-based surface detection and honest-degradation contract."
- C4: add `devin` external system (Devin CLI + Devin Cloud) with `founder` and `platform.plugin` edges — the plugin executes on a Cognition-managed VM, a new external boundary; include in `views.c4` context + containers views; keep `c4-count-parity` green.
- Schedule the second post-implementation cloud session (SC1/SC3/SC4 verification — the Phase-0 probe runs pre-implementation and cannot verify banner/fallback/ack).

## Alternative Approaches Considered

| Approach | Why rejected |
|---|---|
| B — Verify-first, repo-config leveraged | Doesn't help Soleur users' repos; hooks are fail-open; folded into Phase 0 probe instead |
| C — Docs + upstream request only | Leaves undisclosed in-band degradation — our worst failure shape; vendor-owned timeline |
| Env-var detection (`DEVIN_CLOUD`-style marker) | No documented cloud marker exists (probe confirms/denies in Phase 0); invented env sniffing is exactly what D3 rejected |
| Persistent ack file for the cloud-ack gate | Replay-hole class — a stale ack satisfies a new weakening; ack is session-scoped only |
| New `Harness` union member (`"devin-cloud"`) | Same invocation surface, different capabilities — a modifier on `"devin"`, not a fifth member (2026-09-11 learning) |

## Files to Create

- `plugins/soleur/scripts/cloud-detect.sh` — the ONE classifier (`local` / `not-local:<reason>`)
- `plugins/soleur/scripts/cloud-banner.sh` — per-invocation banner emit (or a `--banner` flag on cloud-detect)
- `plugins/soleur/scripts/precommit-guard.sh` — self-contained skill-invoked commit-on-main check
- `plugins/soleur/test/devin-cloud-mode.test.ts` — all detection arms + never-value coverage
- `knowledge-base/project/specs/feat-devin-cloud-session-parity/cloud-probe.md` — probe results + DPIA-screening note
- `knowledge-base/engineering/architecture/decisions/ADR-<provisional>-soleur-cloud-mode-*.md` — new ADR (Phase 6)

## Files to Edit

- `plugins/soleur/hooks/devin-session-start.sh` — unconditional content-bearing sentinel write (git-root + `mkdir -p`, `|| true`-guarded post-emit)
- `plugins/soleur/devin/INSTRUCTIONS.md` — §Cloud Mode canonical contract + capability matrix + extended fallback contract + unrestored-guard enumeration
- `plugins/soleur/AGENTS.md` — cloud-mode rules section (spec G4/TR2, `[id:]` convention)
- `.devin/config.json` — `requiredPlugins` (pre-merge unknown-key tolerance validation)
- `README.md`, `plugins/soleur/README.md` — matrix pointer
- Union-set `plugins/soleur/skills/*/SKILL.md` — one composite `<!-- soleur-cloud-mode -->` pointer block each (grep-derived: spawn-sites ∪ secrets/prod ∪ directly-invocable pipeline skills)
- `plugins/soleur/scripts/emit-review-trailer.sh` — `sequential-fallback` enum widen (~1 line)
- `plugins/soleur/skills/ship/SKILL.md` — `sequential-fallback` blocking gate on `single-user incident`
- `.claude/hooks/guardrails.sh` — commit-on-main block delegates to `precommit-guard.sh`
- `docs/legal/{data-protection-disclosure,privacy-policy,gdpr-policy}.md` + `plugins/soleur/docs/pages/legal/{same}` — floor corrections + third-configuration naming + mirrors (ceiling at CLO's call)
- `knowledge-base/legal/article-30-register.md` — per-entry audit amendments + probe PA-37/out-of-scope determination
- `knowledge-base/legal/compliance-posture.md` — Completed-Work row + recorded D10 prohibition
- `apps/web-platform/lib/legal/legal-doc-shas.ts` — SHA repins
- `knowledge-base/engineering/architecture/diagrams/{model,views}.c4` — `devin` external system
- `knowledge-base/project/specs/feat-devin-cloud-session-parity/spec.md` — spec notes: FR1 "sibling lib" reading (`scripts/cloud-detect.sh`); NG5 revision for `PostCompaction` hook use (probe-conditional)

## User-Brand Impact

- **If this lands broken, the user experiences:** a cloud `/soleur:one-shot` or review pipeline that ran with zero agents and no SessionStart-injected rules — unreviewed work shipping under a "Soleur ran it" assumption (the #7146 class: degraded review self-labelled but still nearly shipped).
- **If this leaks, the user's data / workflow / money is exposed via:** prod secrets pulled onto a Cognition-managed VM with credential-context guards absent — least-attended runtime (CLO D6); or a Jikigai-credentialed cloud session carrying personal data before Cognition is a contracted processor (D10 prohibition).
- **Brand-survival threshold:** `single-user incident`

CPO sign-off: covered by brainstorm Phase 0.5 carry-forward (CPO assessment on record, `## Domain Assessments`); `user-impact-reviewer` runs at review time.

## Observability

```yaml
liveness_signal:
  what: "capability banner emit + devin-cloud-mode.test.ts suite (plugin dev-surface, not prod runtime)"
  cadence: "per-session emit / per-CI-run"
  alert_target: "operator session output + CI failure"
  configured_in: "plugins/soleur/scripts/cloud-banner.sh; plugins/soleur/test/devin-cloud-mode.test.ts"

error_reporting:
  destination: "stderr banner + skill-deliverable disclosure strings (no Sentry — plugin dev tooling)"
  fail_loud: "cloud-detected pipeline run with NO banner = detection regression, caught by test suite never-value arm"

failure_modes:
  - mode: "sentinel committed to git → false 'local' in cloud clones"
    detection: "test asserting .devin/* gitignore coverage + sentinel-absent arm"
    alert_route: "CI failure on plugins/soleur/test/"
  - mode: "docs drift — Cognition changes cloud hook behavior post-merge"
    detection: "capability matrix 'verified on <date>' stamps + cloud-probe.md re-run checklist"
    alert_route: "operator re-probe per matrix instructions"

logs:
  where: "session output (banner), ack ledger under `.devin/` (prod-write-defer-gate.sh conventions)"
  retention: "session lifetime / repo-local; on a cloud VM retention is governed by the operator's own Cognition agreement"

discoverability_test:
  command: "bash plugins/soleur/scripts/cloud-detect.sh"
  expected_output: "prints `local` or `not-local:<reason>`; exit 0"
```

## Guard Contract

### Guard 1 — Cloud-session detection (`cloud-detect.sh` / `detectCloudSession` + content-bearing sentinel)

**Property.** No Devin session is classified `local` without positive *this-host, plugin-sourced* local-session evidence (sentinel present AND `host` matches AND `hook_source` = plugin); every other case is `not-local(reason)`, which fails closed at every consumer.

**Assembly.** `cloud-detect.sh` (the single canonical classifier — `detectCloudSession()` in `harness.ts` execs it, no TS copy) + the sentinel write site in `devin-session-start.sh` + every SKILL.md block branching on the result. Chokepoint: `cloud-detect.sh` — SKILL.mds never re-implement detection (TR1).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete the sentinel-write line from `devin-session-start.sh` → local session classified not-local (banner in local session) | RED |
| 2 | Drop the host compare — existence-only check accepts a foreign-host sentinel (user-repo-committed; handoff-copy retired as transport 2026-09-17, stays as forward-defense) → false local | RED |
| 3 | Drop the `hook_source` compare — a repo-level SessionStart firing in cloud writes a matching-host sentinel → false local | RED |
| 4 | Sentinel write unguarded or ordered before the `additionalContext` emit → a write failure kills the hook under `set -euo pipefail` and loses context injection | RED |
| 5 | Any consumer treats `not-local` as permissive (skip banner / skip ack / skip fallback) | RED |
| 6 | Must-PASS (non-canonical): `DEVIN` set + sentinel present + matching `host` + `hook_source=plugin` → `local`, no banner | PASS |

### Guard 2 — Skill-invoked precommit guard (`precommit-guard.sh`)

**Property.** A `git commit` on `main`/`master` invoked through `work`/`ship`/`one-shot` is refused even when no PreToolUse hook executes. (The DONE-marker check is **not** extracted — it reads hook-stdin transcript data a script cannot see; it stays prose + the plugin Stop hook, structural where it runs, pending probe.)

**Assembly.** The commit-on-main block (`guardrails.sh:129-155` semantics) as a self-contained script invoked from `work`/`ship`/`one-shot` directly; `guardrails.sh` delegates to it so hook path and skill path enforce identically (plugin = canonical source, repo reaches in). Chokepoints: (a) the script; (b) the hook wrapper. Identical enforcement, no duplicated logic.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop the `main\|master` branch check → commit on main proceeds | RED |
| 2 | Script exits 0 unconditionally on empty input → "0 checked" vacuity | RED |
| 3 | Check only the first command segment → `git commit` after `;`/`&&` bypasses (the hr-skill class) | RED |
| 4 | Hook wrapper keeps its own inline copy instead of delegating → drift fork | RED |
| 5 | Must-PASS (non-canonical): commit on a `feat-*` branch → allowed | PASS |

### Guard 3 — Cloud acknowledgement gate

**Property.** No secrets read or prod mutation runs in a detected cloud session without a session-scoped explicit operator acknowledgement.

**Assembly.** The grep-derived secrets/prod SKILL.mds' ack block, the shared include text, and `ask_user_question` at each skill's first secrets/prod action. Chokepoint: the shared include — per-skill divergence is the defect class (TR1).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Skip the ack when detection returns cloud → secret read proceeds silently | RED |
| 2 | Gate checks a persisted ack file → stale ack replays across sessions | RED |
| 3 | Gate fires on the second secrets call instead of the first → first call unguarded | RED |
| 4 | Test-side: stub detection to `local` in the cloud arm → gate never exercised | RED |
| 5 | Must-PASS (non-canonical): operator declines → skill aborts with documented-exit message, no secret touched | PASS |

## Architecture Decision (ADR/C4)

This plan makes an architectural decision: a capability-detection substrate layered on the harness taxonomy (a cross-cutting invariant every pipeline skill relies on) plus a new credential-boundary control (cloud-ack gate).

### ADR

New ADR — "Soleur Cloud Mode: sentinel-based surface detection and the honest-degradation contract" (provisional ordinal — re-derive the next-free ordinal across `origin/*` at write time; `/ship` re-verifies before merge). Authored via `/soleur:architecture` as a Phase 9 implementation task, status `accepted` at merge.

### C4 views

**Enumeration performed** (all three `.c4` files read): external human actors — none new (operator is `founder`); external systems — **Cognition/Devin Cloud is NOT modeled** (grep: zero `devin` in model/views/spec); containers/data-stores — plugin internals unchanged; access relationships — plugin executing on a third-party VM under user credentials is a new boundary the model lacks.

**Task:** add `devin = system "Devin (CLI + Cloud)"` `#external` to `model.c4` — description recording that cloud sessions run plugin skills + AGENTS.md rules on a Cognition-managed VM with subagents absent and hook coverage per the capability matrix — plus `founder -> devin` and `devin -> platform.plugin` edges; add `devin` to `views.c4` `context` and `containers` includes. Derived cardinalities: none affected (new element, no count-bearing prose); `c4-count-parity` green pre-change (10/10), re-run after.

### Sequencing

ADR authored in Phase 9 describing the shipped target state; C4 edit lands in the same PR — not deferred.

## Domain Review

**Domains relevant:** Product, Legal, Engineering (carried forward from brainstorm `## Domain Assessments`)

### Legal

**Status:** reviewed
**Assessment:** PERMITTED-WITH-GUARDRAILS + one prohibition (no Jikigai-credentialed cloud session carrying user personal data until Cognition is a contracted processor). Documenting cloud use fires the 2026-09-13 attestation re-evaluation trigger → FR8's three-doc disclosure + Art. 30 rescoping is required scope, CLO routes wording (SC5).

### Engineering

**Status:** reviewed
**Assessment:** Real absences: SessionStart hooks + subagents (plugin command hooks documented working post-doc-drift; probe confirms). Architecture ordering: requiredPlugins → sentinel detection → AGENTS.md/preamble carry → generalized fallback → skill-internal gates → cloud-ack.

### Product/UX Gate

**Tier:** none — plan implements orchestration/scripts/docs only; Files-to-Create/Edit contain no UI-surface paths (mechanical override checked against ui-surface-terms: zero matches).
**Decision:** reviewed

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `cloud-detect.sh` the single classifier; `bun test plugins/soleur/test/` green including `devin-cloud-mode.test.ts` covering `local` + every `not-local` reason + the never-value assertion (AC1)
- [ ] `devin-session-start.sh` writes content-bearing `.devin/soleur-local-session` unconditionally under Devin env (git-root + `mkdir -p`, `|| true`-guarded post-emit); sentinel gitignored here (`git check-ignore`); foreign-host AND repo-sourced (`hook_source` mismatch) sentinels classify `not-local` (AC2)
- [ ] Contract text on both guaranteed-load surfaces (INSTRUCTIONS.md §Cloud Mode + plugin `AGENTS.md`); every grep-derived union-set SKILL.md carries the composite `<!-- soleur-cloud-mode -->` marker; `not-local` shows reason-aware copy (AC3)
- [ ] Fallback is a static branch on detection; `Reviewed-Coverage: sequential-fallback` flag emitted in deliverables + PR trailers; `ship` blocks it on `single-user incident` plans (AC4)
- [ ] Cloud-ack contract on every secrets/prod SKILL.md; session-scoped, honest-exit, no persisted ack, unanswered-in-headless defers (mechanism per probe: interactive ask OR hard-defer) (AC5)
- [ ] `precommit-guard.sh` self-contained, exec'd by `work`/`ship`/`one-shot`, refuses commit-on-main without hook execution in a repo lacking `.claude/`; `guardrails.sh` delegates to it (AC6)
- [x] `.devin/config.json` carries a repo-level `requiredPlugins` entry for Soleur — landed as the `git-subdir` object form; the string form this AC named was superseded after #8172 residual arms measured it 404ing through the cloud git-manager proxy (AC7)
- [ ] `devin/INSTRUCTIONS.md` matrix rows each cite a doc anchor or probe result; unrestored repo guardrails enumerated; README pointers live (AC8)
- [ ] Legal floor landed (false-statement corrections + third-configuration named + §2.1c fifth row) + mirrors + SHA repins in the same PR; `legal-doc-consistency.test.ts` + `check-tc-document-sha.sh` green; Art. 30 amendments are appended brackets + per-entry accurate; corpus-wide taxonomy expansion only at CLO's direction (AC9)
- [ ] ADR authored + `devin` element in `model.c4`/`views.c4`; `c4-count-parity` green (AC10)
- [ ] `npx markdownlint-cli2` clean on touched `.md`; Guard Contract lint (`lint-guard-contract.py`) passes (AC11)

### Post-merge / probe-dependent

- [ ] Pre-probe credential determination recorded BEFORE the session runs (whose account / billing / reachable keys); Jikigai-limb positive → CLO escalation first; PA-37 register entry or written out-of-scope determination + DPIA-screening note in `cloud-probe.md` (AC12a)
- [ ] `cloud-probe.md` records Q1–Q4 + handoff-sync + exec-shell env propagation + plugin command-hook execution, each with evidence; matrix "verified on" stamps updated (AC12b)
- [ ] A second post-implementation cloud session (scheduled as a Phase-9/ship-time task — the probe runs pre-implementation and cannot verify banner/fallback): `/soleur:go` emits the banner and completes a pipeline stage with disclosed sequential fallback (SC1) (AC13)
- [ ] A secrets/prod action in cloud halts at the ack gate when unanswered (SC3) (AC14)
- [ ] Fresh cloud session on a repo lacking personal-manifest sync loads skills via `requiredPlugins` (SC4) (AC15)
- [ ] CLO sign-off recorded on the disclosure update + Art. 30 amendments + probe credential determination (SC5) (AC16)

## Test Scenarios

- Given `DEVIN` set + sentinel absent, when detection runs, then `not-local:sentinel-absent`; banner emits once per session (ts-scoped sentinel suppresses a second emit in-session, re-emits next session).
- Given `DEVIN` set + sentinel present + matching `host` + `hook_source=plugin`, when detection runs, then `local`; no banner (never-value).
- Given `DEVIN` set + foreign-host sentinel (user-repo-committed — handoff-copy retired as transport 2026-09-17), when detection runs, then `not-local:foreign-host`.
- Given `DEVIN` set + repo-sourced sentinel (`hook_source=repo`, the repo-SessionStart-in-cloud arm), when detection runs, then `not-local:non-plugin-source`.
- Given malformed sentinel JSON or no Devin env (untrusted-hooks local user), when detection runs, then `not-local:<reason>`; banner shows reason-aware copy; ack gate treats as cloud.
- Given a `not-local` session, when a spawn-site skill reaches fan-out, then the role executes sequentially inline (static branch — no spawn attempt) and the deliverable carries the disclosure string + `Reviewed-Coverage: sequential-fallback` flag.
- Given `ship` on a `single-user incident` plan with `sequential-fallback` coverage, when the gate evaluates, then it blocks pending acknowledgement.
- Given a declined OR unanswered (headless) cloud-ack, when a secrets/prod action is reached, then the step defers/aborts with the documented-exit message and touches no secret.
- Given `git commit` on `main` with no hook execution in a repo lacking `.claude/`, when `work`/`ship` invokes `precommit-guard.sh`, then the commit is refused.

## Success Metrics

- Zero cloud pipeline runs complete without the banner (never-value test).
- 100% spawn-site and secrets-skill coverage (grep-verified, SC2).
- Every matrix row backed by doc anchor or probe evidence.
- CLO sign-off on disclosures (SC5).

## Dependencies & Risks

- **Docs drift risk:** Cognition's docs moved once during scoping (plugin hooks → cloud). Mitigation: probe-first ordering, "verified on" stamps, matrix rows marked undocumented-vs-verified.
- **Probe dependency:** Phase 0 requires a real cloud session (operator-credentialed, TR7). If Q1 shows repo hooks fire in cloud, FR5 scope shrinks — recorded as plan flexibility, not failure.
- **False-local risk:** a committed sentinel would mark cloud clones "local" — mitigated by host compare (user repos may not gitignore `.devin/`; the untracked sentinel artifact is documented in the matrix, P3-15).
- **`requiredPlugins` blast radius:** an unrecognized key in `.devin/config.json` could break local hook registration — validated pre-merge (Phase 1).
- **`ask_user_question` mechanism risk:** auto-approve permission modes would fail the gate open — FR4's mechanism is probe-frozen; hard-defer is the designed fallback outcome, not a discovered one.
- **Enforcement is prose-in-skill** where hooks can't backstop — disclosed honestly in the matrix (no claim of protection parity, CLO D9); DONE-marker script check is advisory (a script can't interpose turn-end), the plugin Stop hook is structural where it runs.
- **Rollback:** changes are additive except the `requiredPlugins` key and legal SHA repins; rollback = revert PR + re-pin SHAs. `closes:` intentionally omitted — SC1/SC3-5 are operator-gated post-merge; ship files follow-up issues for the post-merge ACs so #8159's verification loop doesn't strand.
- Sharp-edge note: a plan whose `## User-Brand Impact` section is empty/placeholder fails deepen-plan 4.6 — filled above.

## Plan Review Record

Four reviews ran against this plan; material findings were folded in before task generation.

| Gate | Verdict | Key changes adopted |
|---|---|---|
| spec-flow-analyzer | 4 P0, 9 P1 | Scope-guarded sentinel inverted detection in user repos → unconditional write; both enumerated skill sets incomplete → grep-derived union sets; bash/TS split-brain → single canonical bash classifier; `.claude/hooks/lib/` deps absent in user repos → self-contained guard |
| Scoped advisor (ADR-083) | 2 structural | Content-bearing sentinel `{host, ts, hook_source}` survives user-repo commits, handoff-class transports, and either probe outcome; `hook_source` = free probe data |
| GDPR gate | PASS-WITH-FINDINGS (0 Critical, 4 Important, 3 Suggestion) | Pre-probe credential/Art.30/DPIA determinations; definition-level taxonomy flagged (set to CLO-sized floor/ceiling); named-disclosure probe-conditional |
| Plan-review (DHH/Kieran/simplicity) | 1 P0, 15+ P1/P2 | `hook_source` in classification (P0 false-local hole); binary + reason over tri-state; static fallback branch; one composite marker block; phases consolidated 10→6; `ask_user_question` + matcher-binding + `requiredPlugins` probe items; `PostCompaction` NG5 revision flagged; `harness.ts` is test-only surface → no TS detector; DONE-marker not extractable → prose + plugin Stop hook |

## References & Research

- Spec: `knowledge-base/project/specs/feat-devin-cloud-session-parity/spec.md` (FR1–FR10, TR1–TR7, SC1–SC5)
- Brainstorm: `knowledge-base/project/brainstorms/2026-09-14-devin-cloud-session-parity-brainstorm.md` (D1–D11, Q1–Q4)
- Surface-matrix learning: `knowledge-base/project/learnings/documentation-gaps/devin-cloud-plugin-surface-matrix-SoleurPlugin-20260914.md`
- Key learnings: `2026-08-03-the-degraded-review-labelled-itself`, `2026-09-02-i-built-a-host-discriminator-out-of-an-absence`, `2026-09-11-meta-harness-is-not-a-third-harness-union-member`, `2026-05-29-skill-local-gates-escape-compressed-pipelines`, `2026-04-21-cloud-routine-subagent-auth-inheritance-H6`, `2026-07-06-body-hashing-guardrail-gate-fail-open-classes`, `2026-09-11-a-filer-with-no-honest-exit`
- ADRs: ADR-089 (cross-harness state), ADR-093 (platform-deployed plugin root), ADR-178/179 (shared primitives + bare-root anchors)
- Devin docs: `docs.devin.ai/cli/extensibility/plugins/overview`, `.../hooks/overview`, `.../lifecycle-hooks`, `/cli/handoff` (post-2026-09-14 revision: plugin command hooks run in cloud except SessionStart/SessionEnd)
- Issues: #8159 (primary), #8160–#8162 (deferred), PR #8155
