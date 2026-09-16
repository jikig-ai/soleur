---
title: "feat: Audit .claude/settings.json tool-name matchers — dead under Devin CLI"
type: feat
date: 2026-09-15
slug: feat-settings-matcher-devin-audit
branch: feat-settings-matcher-devin-audit
issue: 8205
closes: 8205
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# feat: Audit .claude/settings.json tool-name matchers — dead under Devin CLI

## Overview

Devin CLI loads `.claude/settings.json` hooks by default (`read_config_from.claude`), but its shell tool_name is `exec`, not `Bash` — so the repo's 22 `Bash` matcher objects (23 hook registrations) are loaded-but-dead under Devin, and ~16 in-body `tool_name` gates would still no-op even where a matcher fires. Meanwhile the coincidental Grok twins (`write`, `ask_user_question`) already fire under Devin and `.devin/config.json` binds `guardrails.sh` again — a live cross-registry double-fire. This plan produces a checked-in per-hook disposition ledger, an expanded `.devin/config.json`, a single tool-kind canonicalization point in `hook-input.sh`, an executable parity contract test, and the doc/legal corrections — per the brainstorm's chosen approach (per-harness registries, approach B).

## Problem Statement

Three-layer silent-not-run model: (1) the registry must load, (2) the matcher regex must match `tool_name`, (3) the hook body must not gate itself out. Under Devin today: layer 1 holds (settings.json is auto-loaded), layer 2 fails for every CamelCase matcher, and layer 3 fails independently for the ~16 hooks that re-check `tool_name == "Bash"`/`"Write"`/`"Edit"` in their bodies. The safety-relevant consequence: `devin/INSTRUCTIONS.md:91` asserts the credential guard works on Devin; it does not. `browser-snapshot-credential-guard.sh:90` is the canonical fires-then-noops case PR #8155 half-fixes. `permissions.allow`/`deny` use the same dead tool-name vocabulary (`Bash(...)`, `Read(...)`).

## Proposed Solution

Per-harness registries: `.claude/settings.json` stays Claude-canonical (its `Bash` matchers are *not* widened — that was rejected approach A); `.devin/config.json` expands to the triaged Devin subset with anchored matchers. A checked-in disposition ledger (`.claude/hooks/devin-dispositions.tsv`) records every hook's per-harness disposition; a parity contract test asserts ledger↔registry agreement. In-body gates are normalized through one canonical tool-kind map (`lib/hook-tool-kind.sh` → `HOOK_TOOL_KIND`), never by hand-editing N `== "Bash"` comparisons.

## Technical Approach

### Architecture

- **Disposition ledger** `.claude/hooks/devin-dispositions.tsv`: `registry<TAB>hook_path<TAB>event<TAB>matcher_or_tool<TAB>disposition<TAB>reason<TAB>evidence`. Dispositions: `bind` (register in `.devin/config.json`), `covered-by-twin` (a settings.json lowercase matcher already fires — no `.devin` re-registration), `covered-by-plugin` (the shipped `hooks.json` matcher covers the Devin name — e.g., `^(Bash|exec)$` post-#8155), `already-fires` (name-stable matchers like `mcp__pencil__open_document` and hooks.json's own `devin-session-start.sh`), `n/a` (matcher-less `Stop` entries and SessionStart event-name matchers — non-tool surfaces asserted by a separate test arm, not the tool-name regex-eval arm), `skip` (`reason=no-tool|no-analog|unverified-payload`). The `registry` column disambiguates rows for hooks registered in more than one source (`browser-snapshot-credential-guard.sh` is in settings.json AND hooks.json). This file is both the FR1 matrix and the FR5 test's data source — one artifact, no drift between doc and test.
- **Canonical kind map** `.claude/hooks/lib/hook-tool-kind.sh`: one `hook_tool_kind()` mapping — `exec→Bash`, `write→Write`, `edit→Edit`, `multi_edit→MultiEdit`, `notebook_edit→NotebookEdit`, `apply_patch→Write`, `ask_user_question→AskUserQuestion`, `run_subagent→Agent`, `skill→Skill`; unmapped names pass through unchanged. The map targets the *internal* name bodies compare against (`agent-token-tee.sh` gates on `!= "Agent"` — the wire name — even though its matcher is `Task`), so `run_subagent→Agent` is correct-by-construction. `hook-input.sh` sources it and exports `HOOK_TOOL_KIND` as a *sibling* of `HOOK_TOOL_NAME` (A17 pins byte-exact `HOOK_TOOL_NAME`; a derived global is the only safe shape). Own-jq hooks source the lib file directly. `security_reminder_hook.py` gets an equivalent inline dict — pinned to the bash map by a drift-guard test (repo convention: duplicated logic gets a parity pin, per the AGENTS.md workflow-script rule). **Kind implies payload parity is NOT assumed** (advisor finding): a `bind`/kind-mapped gate is only valid where Phase 0 measured the Devin payload's field names matching the Claude schema for that kind; otherwise the disposition is `skip reason=unverified-payload`.
- **`.devin/config.json` expansion**: `^exec$` gains every portable `Bash`-matcher hook **except** `browser-snapshot-credential-guard.sh` (whose `hooks.json` `^(Bash|exec)$` matcher — post-#8155 — already covers `exec`; adding it to `.devin` would be the exact cross-registry double-fire this PR exists to kill → `covered-by-plugin`); write-class matcher becomes `^(edit|multi_edit|notebook_edit|apply_patch)$` (drops `write` — covered by the settings twin *only if Phase 0 confirms `$CLAUDE_PROJECT_DIR` resolves for settings-dispatched hooks*; adds `apply_patch` — real Devin tool with zero coverage today); PostToolUse gains `^exec$` (rule-incident-marker-capture + post-dispatch-watch-gate dispatch arm) **and** `^(edit|multi_edit|notebook_edit|apply_patch)$` for `docs-cli-verification.sh` (`edit` has no PostToolUse coverage anywhere today). `ask_user_question` is NOT added (twin covers it). SessionStart resolved per the Phase-0 measurement (see below).
- **Twin anchoring**: `write` → `^write$`, `ask_user_question` → `^ask_user_question$` in settings.json — stops `todo_write` over-binding while preserving Grok coverage (regex still matches Grok's `write`). Guard 2 in `workflow-fidelity.test.ts` updated to regex-evaluate matchers instead of `allMatchers.includes("write")` string-compare.
- **Non-portable skips** (documented `reason=no-tool`): `monitor-supersede-guard.sh` (no Monitor), `monitor-arm-recorder.sh` (no Monitor/TaskStop), `durable-reminder-prefer-inngest.sh` (no CronCreate), `agent-token-tee.sh` (no verified run_subagent telemetry shape), `post-dispatch-watch-gate.sh` Monitor-arm (no arm primitive — its `exec` dispatch-detection arm still ports).

### Implementation Phases

#### Phase 0: Empirical semantics probe (TR1 — prerequisite for ALL dispositions that execute under Devin)

Four measurements, each load-bearing; a null on any of them changes the design, not just a row:

- **Matcher semantics (highest blast radius, cheapest check).** Register capture stubs on three syntaxes — literal `exec`, anchored `^exec$`, wildcard `.*` — and observe which fire. If Devin matchers are not regex-evaluated, the entire anchored-matcher design is dead config. (Advisor P0.)
- **Envelope capture.** Stubs write raw stdin + `env | grep -E 'CLAUDE|DEVIN|PROJECT|PLUGIN'` to capture files. Register stubs in **all three Devin-loaded registry shapes** — a scratch repo's `.claude/settings.json`, its `.devin/config.json`, and an installed-plugin `hooks.json` — because the env question is per-source: does `CLAUDE_PROJECT_DIR` reach *settings-dispatched* hooks, and does `CLAUDE_PLUGIN_ROOT` reach *plugin-manifest* hooks (this session's learning measured it unset in the shell context)? Drive `exec`, `write`, `edit`, `ask_user_question`, `skill`, `run_subagent`, `todo_write` in a fresh child Devin session; record `.tool_input` field names per tool.
- **Response contract.** Envelope capture alone is input-side. The stub must also *emit* a `hookSpecificOutput.permissionDecision:"deny"` and an `updatedInput` rewrite on a sentinel call, and the driver observes whether the tool call was blocked / the input rewritten. If Devin dispatches hooks but ignores the decision contract, every `bind` produces fires-then-no-ops one layer deeper — the class this PR exists to kill. Unverified response contract → the affected hooks downgrade to `skip reason=unverified-payload`.
- **Cross-source dedup (3 sources, not 2).** Scratch repo must carry all three registries populated: settings.json SessionStart + `.devin/config.json` SessionStart + plugin `hooks.json` SessionStart (`devin-session-start.sh` is registered in BOTH hooks.json and `.devin/config.json` today — a live double-fire independent of `session-rules-loader.sh`). Observe which SessionStart commands fire and whether identical commands dedupe.

Deliverable: `knowledge-base/project/specs/feat-settings-matcher-devin-audit/envelope-capture.md` with a date-stamped measured-shape header per the 2026-05-10 convention. **Every disposition that executes under Devin** — `bind`, `covered-by-twin`, `covered-by-plugin` — must cite measured evidence for the fields its hook reads; a divergent Devin payload under a `covered-by-twin` row is fires-then-misparses, not coverage. Gate on "at least one stub fired" before writing any ledger rows.

**Named Phase-0 branches the plan commits to now:** (a) `CLAUDE_PROJECT_DIR` unset → `covered-by-twin` is void for every hook whose settings.json command interpolates it (all 58 do): those hooks move to `.devin` binds spelled with `$(git rev-parse --show-toplevel)`, and `write` STAYS in the `.devin` write-class matcher. (b) Devin does not fire settings.json SessionStart → add the other three SessionStart commands to `.devin/config.json`; it does → remove the duplicated `session-rules-loader.sh` there and resolve the `devin-session-start.sh` double-registration per the measured dedup behavior.

#### Phase 1: Canonical tool-kind mapping + in-body gate normalization

- Create `.claude/hooks/lib/hook-tool-kind.sh` (`hook_tool_kind()` + map). Wire `hook-input.sh` to source it and export `HOOK_TOOL_KIND`.
- Normalize each gate site to consume the kind: lib consumers switch `HOOK_TOOL_NAME` → `HOOK_TOOL_KIND` at the gate comparison only (telemetry keeps the raw name). Own-jq hooks source `hook-tool-kind.sh`. `kb-domain-allowlist-guard.sh:105` IS_BASH discriminator: kind-mapped `exec→Bash` restores the Bash-write-verb arm (today `exec` falls to the file-class path and over-fires `ask`). `security_reminder_hook.py`: inline dict. `prod-write-defer-gate.sh:150` ledger literal stays `"Bash"` (cosmetic — ledger vocabulary is Claude-canonical; note in matrix).
- Each gate's own test extended with a Devin-name fixture (`tool_name:"exec"` behaves as `Bash`, etc.).

#### Phase 2: Disposition ledger + registry changes

- Write `.claude/hooks/devin-dispositions.tsv` covering every settings.json + hooks.json + `.devin/config.json` registration and every `permissions` entry. `.codex/config.toml` and `.openhands/hooks.json` entries get `n/a reason=this-pr-devin-scope` rows — they are enumerated (so the ledger is complete over "every registry," per spec) but carry no Devin assertion; the ADR names the scoping.
- Expand `.devin/config.json` per measured envelopes; anchor the settings.json twins; resolve the `guardrails.sh`/`write` double-fire by narrowing the `.devin` write-class matcher; resolve SessionStart per Phase-0 finding (either remove the duplicated `session-rules-loader.sh` from `.devin/config.json`, or add the other three SessionStart commands if Devin doesn't fire settings blocks).
- Permissions: if Phase 0 finds a Devin repo-level permission analog, rewrite `Bash(...)`/`Read(...)` under it; else `reason=no-analog` rows in the ledger + a documented gap.

#### Phase 3: Parity contract test + coupled-gate updates

- New `.claude/hooks/devin-matcher-parity.test.sh` (auto-discovered by `test-all.sh` via `.claude/hooks/*.test.sh`). Assertions: every registry entry has a ledger disposition; every `bind` row has a `.devin/config.json` entry whose matcher regex-**evaluates** true against the Devin tool name (jq `test($m)` — the `kb-index-merge-driver-registration.test.sh:242` precedent, not string equality); no Devin tool name is bound for the same hook in two registries; twins are anchored; every `.devin`-registered command resolves to a tracked `100755` executable; unmodeled registry entries fail loud (2026-07-03). **Command-spelling canonicalization is mandatory** (SpecFlow P0-3): the three registries spell one file three ways — `"$CLAUDE_PROJECT_DIR"/.claude/hooks/x.sh`, `bash "$(git rev-parse --show-toplevel)/.claude/hooks/x.sh"`, `${CLAUDE_PLUGIN_ROOT}/hooks/x.sh` — so the test canonicalizes to repo-relative path before comparing; naive string-compare is a false green on the flagship double-fire assertion (the `hookeventname-coverage.test.sh:183-191` documented trap). A separate non-tool arm asserts SessionStart/Stop dedup (event-name matchers have no tool operand — the 3-source `devin-session-start.sh` double-registration is permanently unguarded without it).
- Update `workflow-fidelity.test.ts` Guard 2 to regex-evaluate: replace the `toContain(name)` standalone-matcher check with `test($m)`-style evaluation so anchored twins (`^write$`, `^ask_user_question$`) still satisfy "standalone matcher for the unaliased Grok name." Anchoring enforcement itself lives in the parity test's row-5 check — Guard 2 verifies Grok coverage, parity test verifies anchoring. **Grok-side regex semantics:** matchers on Grok are regexes per the alias mechanism (union-matching `run_terminal_command` under `Bash` is only expressible as regex/pattern matching — cite the 2026-09-11 learning's measured behavior as evidence); accepted risk noted in Dependencies — no Grok binary exists in CI, so coverage is asserted at the regex level, not the Grok-dispatch level.
- Verify the other coupled gates stay green *without* edits: `hookeventname-coverage.test.sh` (`select(.matcher=="Bash")` + `n_bash>=15` unaffected — `Bash` matchers stay), `hook-input-contract` A9 (`split("|")` unaffected — no `|` added to settings matchers; `^write$` is a single consistent token on both `needed` and `covered` sides), `ship-unpushed-commits-gate` T11 (Bash list order unchanged), `settings-hook-exec-bit` (cardinality unchanged). **Reconciliation:** the spec's "four coupled gates updated in the same PR" was predicated on rejected approach A (in-place widening); under approach B only Guard 2 changes. If /work finds any of them red anyway, update deliberately — never work around.
- `browser-snapshot-credential-guard.test.sh:241` asserts `matcher=="Bash"` in shipped `hooks.json` — unaffected by this PR (that matcher change is #8155's); the Phase-1 body-gate normalization makes #8155's widened matcher actually work when it lands.

#### Phase 4: Docs, legal, ADR, C4

- `plugins/soleur/devin/INSTRUCTIONS.md:91` — correct the credential-guard claim to state the real post-merge coverage.
- `ADR-213` addendum — state Devin coverage plainly ("an unstated gap is the failure mode, not the gap itself").
- PA-8 §(g) / PA-31 §(g) — dated scope clarification conditioned on this PR's merge; `compliance-posture.md` — dead-window inventory note.
- New ADR (provisional ADR-223 — collided with #8155's Cloud Mode ADR-221 at merge time, renumbered) recording the per-harness hook-registry strategy: Claude-canonical settings.json, per-harness registries for Devin/Codex/OpenHands, Grok shares the Claude registry, ledger + parity test as the drift guard.
- C4: add `devin` system element to `model.c4` (mirroring `codex`/`grokBuild` shape — external system, `founder -> devin`, `devin -> platform.plugin` edges, `#external` tag, view `include` lines in `views.c4` context + containers views); update Hook Engine description's "TWO HARNESSES" enumeration to name all registry surfaces (`.claude`, `.openhands`, `.devin`, `.codex`, `.grok`-shares-Claude). Keep new edge prose free of derived cardinalities; `c4-count-parity.test.sh` green at plan time.

## Alternative Approaches Considered

- **A. Dual-bind in settings.json (Grok FR6 wholesale):** rejected — Devin loads `.devin/config.json` too, so in-place dual-binding reproduces the Grok double-fire class cross-source; doesn't scale to a fourth harness.
- **B. Per-harness registries (CHOSEN):** matches OpenHands/Codex precedent; one triage artifact; needs the parity test to prevent drift.
- **C. Generated SSOT manifest → per-harness outputs:** rejected as over-built for ~60 entries; generation-drift risk exceeds payoff.

## User-Brand Impact

- **If this lands broken, the user experiences:** the PreToolUse guardrail corpus registered in `.claude/settings.json` + `plugins/soleur/hooks/hooks.json` + `.devin/config.json` (credential guards, secret scans, prod-write deferral — the controls cited in PA-8 §(g)/PA-31 §(g) and ADR-213) silently not running on an advertised supported harness.
- **If this leaks, the user's [data / workflow / money] is exposed via:** a guardrail that is registered but never fires under Devin — the operator believes credentials are protected on `exec` while nothing runs; worst case is credential exfiltration through a snapshot/exec path on a surface whose docs claim coverage.
- **Brand-survival threshold:** `single-user incident`

CPO sign-off: covered by brainstorm carry-forward — CPO assessed this feature in `knowledge-base/project/brainstorms/2026-09-15-settings-matcher-devin-audit-brainstorm.md` §Domain Assessments. `user-impact-reviewer` runs at review time per the lifecycle staging.

## Observability

```yaml
liveness_signal:
  what: "devin-matcher-parity.test.sh contract test (registry↔ledger agreement)"
  cadence: "per-PR via test-all.sh / CI"
  alert_target: "CI failure on the PR"
  configured_in: ".claude/hooks/devin-matcher-parity.test.sh + scripts/test-all.sh SUITE_GLOBS"
error_reporting:
  destination: "CI test output"
  fail_loud: "non-zero exit + named failing assertion (unbound bind-disposition hook / double-fire / unmodeled entry)"
failure_modes:
  - mode: "new hook added to settings.json without a disposition row"
    detection: "parity test fails loud on unmodeled entry"
    alert_route: "PR-blocking CI failure"
  - mode: ".devin/config.json binding removed while ledger still says bind"
    detection: "regex-eval assertion reds"
    alert_route: "PR-blocking CI failure"
  - mode: "settings twin re-registered in .devin/config.json (double-fire)"
    detection: "cross-registry assertion reds"
    alert_route: "PR-blocking CI failure"
logs:
  where: "CI job logs"
  retention: "GitHub Actions default"
discoverability_test:
  command: "bash .claude/hooks/devin-matcher-parity.test.sh"
  expected_output: "PASS=9 FAIL=0"
```

## Guard Contract

### Guard 1 — devin-matcher-parity.test.sh

**Property.** Every tool-name-matcher hook registration across the three registries and every `permissions` entry carries a declared Devin disposition, and every `bind` disposition is backed by a registry entry whose matcher regex-evaluates true on the Devin tool name with no cross-registry double-fire.

**Assembly.** Three registry chokepoints — `.claude/settings.json` `.hooks`, `plugins/soleur/hooks/hooks.json` `.hooks`, `.devin/config.json` `.hooks` — enumerated by jq (not by a hardcoded file list), plus `.permissions.allow|deny` and the `.claude/hooks/devin-dispositions.tsv` ledger the assertions quantify over.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete one `^exec$`-bound command from `.devin/config.json` while its ledger row still says `bind` | RED |
| 2 | Empty the settings.json `.hooks` enumeration (guard derives zero entries) | RED — "0 checked" is vacuous, not green |
| 3 | Add a second hook command under an existing `Bash` matcher with no ledger row | RED — second-member after compliant first |
| 4 | Add `guardrails.sh` to `.devin/config.json` on `^write$` while the settings `^write$` twin also binds it | RED — cross-registry double-fire |
| 5 | Unanchor a twin (`^write$` → `write`) | RED — over-bind check |
| 6 | Break the suite's own TSV parser (wrong delimiter expectation) | RED — harness row |
| 7 | Ledger row `skip reason=no-tool` for `monitor-supersede-guard.sh` (non-canonical, explicitly permitted) | PASS — must-PASS control proving the guard doesn't reject everything |
| 8 | Ledger + registries both edited to drop a hook consistently | PASS — guard proves consistency, not content |

**Anchor.** Row 8 is the known weakness: a diff can edit both ledger and registry. Mitigations: (a) the test hard-codes a spot-check set of ≥5 canonical hooks (guardrails on `exec`, credential guard, pre-merge-rebase) asserted independent of the ledger; (b) the spot-check list lives in the test, reviewed in the same diff — a merge-base diff is the integrity anchor.

## Architecture Decision (ADR/C4)

### ADR

New ADR (**ADR-223** (the provisional ADR-221 collided with #8155's Cloud Mode ADR at rebase — the #5990 double-collision precedent, exercised)) via `/soleur:architecture`: per-harness hook registries — Claude-canonical `settings.json`; per-harness registries for Devin (`.devin/config.json`), Codex (`.codex/config.toml`), OpenHands (`.openhands/hooks.json`); Grok shares the Claude registry (twins + alias-union semantics); the disposition ledger + parity test is the drift guard. Anchors: ADR-089 third-harness clause, ADR-110 one-resolver-map, ADR-165 OpenHands protocol divergence, ADR-215 Codex minimal-subset.

### C4 views

Read all three model files. Findings: `model.c4` models `codex` and `platform.grokBuild` as harness systems but has **no `devin` element**; the `platform.engine.hooks` Hook Engine description enumerates "TWO HARNESSES" (`.claude` + `.openhands`) and predates `.devin`/`.codex`. In-scope `.c4` edits (this PR): add `devin` system element + `founder -> devin` / `devin -> platform.plugin` edges + `#external` tag + `include` lines in `views.c4` context and containers views; rewrite the Hook Engine harness enumeration. Checked actors/systems/relationships: founder (modeled), platform.plugin (modeled), Devin CLI (NOT modeled — the change). New prose carries no derived cardinalities. `c4-count-parity.test.sh` verified green at plan time (2026-09-15).

### Sequencing

ADR authored in this PR describing the target state directly (no soak-gated slice).

## Domain Review

**Domains relevant:** Engineering, Legal, Product (carried forward from brainstorm `## Domain Assessments`)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Three-plus registries with no SSOT; defect is two-layered (matcher + body). Per-harness registries with a `hook-input.sh` normalizer and a checked-in triage ledger asserted by a contract test. Flagged `permissions.allow/deny` as same-class scope, the settings.json↔`.devin/config.json` double-fire risk; recommended the per-harness-registry ADR (delivered as Phase 4).

### Legal (CLO)

**Status:** reviewed
**Assessment:** A shipped doc asserts a control that does not exist — #6588 Art. 32 TOM retraction class. Actions folded into Phase 4: INSTRUCTIONS.md correction, ADR-213 addendum, PA-8/PA-31 dated clarifications conditioned on merge, compliance-posture.md dead-window note. Devin→Cognition transcript measurement deferred to #8217.

### Product/UX Gate

**Tier:** none
**Decision:** reviewed
**Agents invoked:** none — mechanical UI-surface scan of Files to Create/Edit: no `*.tsx`, `app/**/page.tsx`, or UI-surface paths; the plan implements hook/config/test machinery only.
**Pencil available:** N/A (no UI surface)

**Brainstorm-recommended specialists:** none.

## Open Code-Review Overlap

None. Queried `gh issue list --label code-review --state open` (200 issues) against every planned file path (`.claude/settings.json`, `.devin/config.json`, `hook-input.sh`, `guardrails.sh`, `kb-domain-allowlist-guard`, `devin-matcher-parity`, `workflow-fidelity.test.ts`) — zero matches.

## Research Reconciliation — Spec vs. Codebase

| Spec claim | Reality | Plan response |
|---|---|---|
| "~10 in-body `tool_name` gates" | 16 gate sites enumerated | Phase 1 covers all 16; matrix is the authority |
| "four coupled gates updated in the same PR" | Under approach B only Guard 2 changes; `hookeventname-coverage`/`A9`/`T11`/`exec-bit` stay green because settings.json `Bash` matchers are untouched | Phase 3 verifies green-without-edit; updates only if actually red |
| TR4 cites "ADR-089's third-harness clause" for bind-by-default | ADR-089's clause is about freeze-lock's shared location; the doctrine is Grok FR6/Guard-2 | Cite correctly in ADR + plan |
| `multi_edit` in `.devin/config.json` | Not in Devin's documented tool vocabulary — harmless dead token | Keep (harmless) but note in ledger |
| Advisor dissent: make the ledger generative (emit `.devin/config.json` + expected-matcher list from the TSV) | Brainstorm approach C was explicitly rejected as over-built for ~60 entries; the advisor's narrower variant is the same mechanism | Kept TSV+test (recorded brainstorm decision); the parity test's spot-check anchor row is the compensating control for the both-editable weakness — revisitable if the ledger grows |
| `apply_patch` coverage | Plan-time assumption "real Devin write-class tool" was falsified by Phase 0 — absent from the measured tool vocabulary (EC§7) | NOT added to the write-class matcher; kind-map arm kept as speculative passthrough (annotated in `hook-tool-kind.sh`) |
| FR1 "matrix" as a doc | Ledger TSV serves as the matrix AND the test's data source | Single artifact, no doc/test drift |

## Files to Create

- `.claude/hooks/lib/hook-tool-kind.sh` — canonical tool-kind map
- `.claude/hooks/devin-dispositions.tsv` — the disposition ledger/matrix
- `.claude/hooks/devin-matcher-parity.test.sh` — the parity contract test
- `knowledge-base/project/specs/feat-settings-matcher-devin-audit/envelope-capture.md` — Phase-0 measurements
- `knowledge-base/engineering/architecture/decisions/ADR-223-per-harness-hook-registries-with-a-disposition-ledger.md` (renumbered from provisional 221 at rebase)

## Files to Edit

- `.devin/config.json` — expanded bindings (anchored matchers)
- `.claude/settings.json` — anchor twins only (`write`→`^write$`, `ask_user_question`→`^ask_user_question$`); SessionStart dedup per Phase 0
- `.claude/hooks/lib/hook-input.sh` — source kind lib, export `HOOK_TOOL_KIND`
- In-body gate sites (16): `git-commit-secret-scan.sh`, `brand-hex-commit-gate.sh`, `doppler-secrets-delete-redirect.sh`, `background-poll-prefer-monitor.sh`, `grep-rewrite.sh`, `kb-domain-allowlist-guard.sh`, `iac-plan-write-guard.sh`, `pre-ask-technical-fork-gate.sh`, `pkill-self-match-guard.sh`, `post-dispatch-watch-gate.sh`, `monitor-supersede-guard.sh`, `monitor-arm-recorder.sh`, `agent-token-tee.sh`, `skill-security-scan-write.sh`, `new-scheduled-cron-prefer-inngest.sh`, `durable-reminder-prefer-inngest.sh`, `security_reminder_hook.py`, `plugins/soleur/hooks/browser-snapshot-credential-guard.sh` (skip-disposition sites get `SOLEUR_HOOK_SKIP`-style markers where the Grok convention applies)
- `plugins/soleur/test/workflow-fidelity.test.ts` — Guard 2 regex-evaluation
- Each touched hook's own `*.test.sh` — Devin-name fixture rows
- `plugins/soleur/devin/INSTRUCTIONS.md` — :91 credential-guard claim correction
- `knowledge-base/engineering/architecture/decisions/ADR-213-*.md` — Devin-coverage addendum
- `knowledge-base/legal/` PA-8/PA-31 registers (dated scope clarification, conditioned on merge) + `compliance-posture.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` + `views.c4`

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: `bash .claude/hooks/devin-matcher-parity.test.sh` exits 0 on the final tree and is auto-discovered by `scripts/test-all.sh` (appears in its suite list).
- [x] AC2: `.claude/hooks/devin-dispositions.tsv` contains a disposition row for every hook command registered in `.claude/settings.json`, `plugins/soleur/hooks/hooks.json`, and `.devin/config.json`, plus every `permissions.allow`/`deny` entry — verified by the parity test's coverage assertion failing when a row is deleted (mutation-row 3 equivalent, exercised locally).
- [x] AC3: For every ledger `bind` row, jq `test()` evaluation of the corresponding `.devin/config.json` matcher returns true for the named Devin tool — the test *evaluates* regexes (`kb-index-merge-driver-registration.test.sh` precedent), never string-compares.
- [x] AC4: No Devin tool name is bound to the same hook command in both registries — `guardrails.sh` on `write` is the fixed instance; the cross-registry assertion generalizes it.
- [x] AC5: `write` and `ask_user_question` settings.json matchers are anchored (`^write$`, `^ask_user_question$`); `workflow-fidelity.test.ts` Guard 2 passes with regex-evaluation (not string-compare) and a `todo_write` probe evaluates false against `^write$`.
- [x] AC6: `HOOK_TOOL_KIND` is exported by `hook-input.sh`; `hook-input-contract.test.sh` A17 (byte-exact `HOOK_TOOL_NAME`) stays green. Gate-site accounting (SpecFlow P2-14 reconcile — 19 enumerated sites): **14 normalized** to `HOOK_TOOL_KIND` (git-commit-secret-scan, brand-hex-commit-gate, doppler-secrets-delete-redirect, background-poll-prefer-monitor, grep-rewrite, kb-domain-allowlist-guard, iac-plan-write-guard, pre-ask-technical-fork-gate, pkill-self-match-guard, post-dispatch-watch-gate, skill-security-scan-write, new-scheduled-cron-prefer-inngest, security_reminder_hook.py, browser-snapshot-credential-guard), **4 marked skip-disposition** (`SOLEUR_HOOK_SKIP`-style markers: monitor-supersede-guard, monitor-arm-recorder, durable-reminder-prefer-inngest, agent-token-tee), **1 documented-only** (prod-write-defer-gate — its `"Bash"` is a Claude-canonical string written into an approvals ledger, not a dispatch gate; keep raw `HOOK_TOOL_NAME`, document in the ledger). Each normalized site has a Devin-name test fixture proving `exec`/`write`/`edit` reach the gated logic.
- [x] AC7: `envelope-capture.md` records: (a) matcher-semantics verdict (literal `exec` vs `^exec$` vs `.*` — which fired); (b) measured `.tool_input` shapes for `exec`/`write`/`edit`/`ask_user_question` (+ `skill`/`run_subagent`/`apply_patch` if probed); (c) per-source env — `CLAUDE_PROJECT_DIR` for settings-dispatched hooks, `CLAUDE_PLUGIN_ROOT` for plugin-manifest hooks; (d) response contract — whether a stub's `permissionDecision:"deny"` actually blocked the call and `updatedInput` actually rewrote; (e) SessionStart cross-source behavior across all 3 registries including the `devin-session-start.sh` double-registration; (f) permissions-analog verdict. Every disposition that executes under Devin (`bind`, `covered-by-twin`, `covered-by-plugin`) cites a measured row for the fields its hook reads.
- [x] AC8: `INSTRUCTIONS.md` no longer asserts the credential guard works on Devin prior to this PR's merge state; ADR-213 carries the dated Devin-coverage addendum; PA-8/PA-31 clarifications are dated and conditioned on merge.
- [x] AC9: ADR (provisional 221) exists documenting per-harness hook registries; `model.c4` carries a `devin` element with edges + `views.c4` includes it; `c4-code-syntax`/`c4-render`/`c4-count-parity` tests green.
- [ ] AC10: Full hook suite green: `bash scripts/test-all.sh` (or the touched-shard set per work Phase 2) with zero regressions on Claude-side semantics — `hookeventname-coverage`, `hook-input-contract`, `ship-unpushed-commits-gate`, `settings-hook-exec-bit`, `browser-snapshot-credential-guard` all green.
- [x] AC11: Diff-scope: the PR touches only the Files-to-Create/Edit list plus pipeline artifacts (`knowledge-base/INDEX.md`, spec-dir session state).

### Post-merge / sequencing

- [ ] AC12: PR #8214 remains draft until #8155 merges (TR3); rebase + absorb the `.devin/config.json` conflict; the hooks.json `^(Bash|exec)$` matcher + this PR's body-gate normalization together make the credential guard actually fire on Devin — verify by tracing once both are on main. **Failure branch:** if the trace reds (plugin hooks not loaded under Devin, `CLAUDE_PLUGIN_ROOT` unset in hook env, response contract ignored), the conditioned INSTRUCTIONS.md wording states the measured gap instead, and a follow-up issue is filed — the doc never asserts coverage the trace refuted.
- [ ] AC13: PA-8/PA-31 scope clarifications take effect at merge (the dates written in Phase 4 must be the merge-date-conditioned wording, not absolute claims).

## Test Scenarios

- Given a `.devin/config.json` missing a `bind`-disposition binding, when the parity test runs, then it exits non-zero naming the hook.
- Given a hook added under a settings.json matcher with no ledger row, when the parity test runs, then it fails loud (unmodeled entry).
- Given `tool_name:"exec"` stdin to each normalized gate hook, when the hook runs, then it behaves as `Bash` (deny/allow/rewrite path reached, not early-exit).
- Given `tool_name:"todo_write"`, when `^write$`-bound hooks dispatch, then no matcher matches (over-bind eliminated).
- Given a fresh Devin child session (Phase 0 stub), when `exec` fires, then the captured envelope shows `.tool_input.command` — or the dispositions downgrade to `unverified-payload`.
- Given both this PR and #8155 merged, when Devin runs the snapshot flow, then `browser-snapshot-credential-guard.sh` fires AND passes its body gate.

## Success Metrics

- Zero dead matchers under Devin for any hook with a `bind` disposition (test-asserted).
- Zero cross-registry double-fires (test-asserted).
- `INSTRUCTIONS.md` claims match measured behavior (legal surface closed).

## Dependencies & Risks

- **PR #8155 ordering:** this PR is draft-blocked on it (TR3). The `.devin/config.json` conflict is small and expected.
- **Phase 0 is the load-bearing uncertainty:** if Devin's `exec` envelope lacks `.tool_input.command`, every `bind` disposition's payload-reading assumption changes — the phase is sequenced first precisely so wrong assumptions die before the ledger is written.
- **Devin SessionStart dedup unknown:** whether Devin fires settings.json SessionStart blocks decides between removing a `.devin` duplicate and adding three missing commands — measured, not assumed.
- **Grok twin anchoring:** `^write$`/`^ask_user_question$` assume Grok regex-evaluates matchers. Evidence is the measured alias mechanism itself (2026-09-11 learning: union-matching `run_terminal_command` under `Bash` is only expressible as pattern matching), but no Grok binary exists in CI — coverage is asserted at the regex level via Guard 2's updated evaluation, and Grok-dispatch-level verification is an accepted residual risk (worst case: twin coverage silently dies under Grok; mitigations: anchors are additive-narrowing only, Grok behavior unchanged for unanchored names).
- **Response contract unverified until Phase 0:** if Devin ignores `permissionDecision`/`updatedInput`, affected `bind` rows downgrade to `skip` and the plan's safety-hook count shrinks — the measurement runs before any ledger row is written precisely so this branch is cheap.
- **`permissions` analog may not exist** under Devin → `reason=no-analog` rows + documented gap rather than a rewrite; if a follow-up syntax exists it may defer to its own issue (spec already flags this).

## References & Research

- Spec: `knowledge-base/project/specs/feat-settings-matcher-devin-audit/spec.md`
- Brainstorm: `knowledge-base/project/brainstorms/2026-09-15-settings-matcher-devin-audit-brainstorm.md`
- Learning (this session): `knowledge-base/project/learnings/2026-09-15-devin-dual-hook-registries-dead-matchers-fires-then-noops.md`
- Grok alias learning: `knowledge-base/project/learnings/2026-09-11-grok-hook-aliases-keep-original-names-so-twins-double-fire.md`
- Envelope method: `knowledge-base/project/learnings/2026-05-10-empirical-hook-input-shape-prevents-silent-zero-emission.md`
- Related: issue #8205, #8159, #8172, #8217; PR #8155, #8214
- Prior art: gemini-cli `hooks migrate --from-claude` TOOL_NAME_MAPPING (borrow shape); rtk-ai/rtk PR #3144 (Devin `^exec$` + permissions reference)
