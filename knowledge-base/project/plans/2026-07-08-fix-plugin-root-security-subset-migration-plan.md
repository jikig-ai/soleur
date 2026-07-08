---
title: "fix(security): migrate security-critical residual ${CLAUDE_PLUGIN_ROOT} families (subset of #6154)"
date: 2026-07-08
type: fix
branch: feat-one-shot-6156-plugin-root-security-subset
lane: single-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
closes: [6156]
relates: [6154, 6121, 6152]
adr: [ADR-093, ADR-095]
---

# fix(security): migrate the security-critical residual `${CLAUDE_PLUGIN_ROOT}` families deferred out of Slice C

## Overview

Slice C (PR #6152, merged 2026-07-07, ADR-093) migrated the 14 agent-run `${CLAUDE_PLUGIN_ROOT}`
families enumerated in #6121 to the deployment-anchored form, closing an untrusted-code-execution
hole on the Concierge server. It deliberately deferred a set of **genuinely-distinct** families to
the still-open P1 follow-up **#6154**, and surfaced that deferral as decision-challenge **#6156**
(ADR-084, headless auto-decision surfaced for async review).

The operator confirmed on #6156 that the **security-critical subset** should be pulled forward now,
while the low-stakes families remain in #6154. This plan migrates exactly that confirmed subset:

1. `legal-generate` — runs the git-root secret-**redaction gate** `redact-sentinel.sh`.
2. `incident` — invokes the same `redact-sentinel.sh` (owning skill).
3. `trigger-cron` — the prod-cron POST helper `trigger.sh`.

It does **not** touch the low-stakes families (`skill-creator`, `plan`, `compound-capture`,
`kb-search`, `harvest-debt`, `seo-aeo`, etc.), which stay tracked in **#6154** (left OPEN, scope
honestly narrowed in the PR body).

### The vulnerability class (unchanged from Slice C / ADR-093)

On the Concierge server (autonomous bash default-on; `permission-callback.ts` autonomous-bypass),
a CWD-relative `bash ./plugins/soleur/.../<script>.sh` executes the **connected repo's UNTRUSTED
committed copy** of that script, **outside the bwrap sandbox**, with the dispatch process's
privileges. The connected repo is operator/customer-controlled (Soleur dogfoods on `jikig-ai/soleur`
itself; any customer who forks or points at soleur inherits the same exposure). ADR-093's decision:
**always resolve plugin-owned scripts from the platform-deployed root, never the workspace copy.**

**Fix pattern (identical to Slice C):** rewrite each sandbox-executed invocation to the
deployment-anchored `${CLAUDE_PLUGIN_ROOT:-<preserved-existing-anchor>}/...` form. `CLAUDE_PLUGIN_ROOT`
is exported by the SDK to the platform-deployed root; the `:-` fallback preserves each site's existing
anchor so CLI/worktree use is unchanged. The git-root fallback precedent already ships in Slice C at
`plugins/soleur/skills/compound/SKILL.md:289`:
`bash "${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/compound/scripts/token-efficiency-report.sh"`.

> **Lane note:** No `spec.md` exists for this branch (one-shot entered directly from a decision-challenge,
> no brainstorm). `lane:` authored directly as `single-domain` — this is a single engineering/security
> tooling concern across three sibling SKILL.md files, not a cross-domain change.

## Premise Validation (Phase 0.6)

Every cited reference was verified against live state before planning:

| Reference | Check | Result |
|---|---|---|
| #6156 (decision-challenge) | `gh issue view 6156` | **OPEN**, informational ("no action required for PR to merge"); operator-confirm gate for pulling forward the redaction-gate + prod-cron subset. Premise holds. |
| #6154 (residual tracker) | `gh issue view 6154` | **OPEN**. Must stay open with narrowed scope. Premise holds. |
| PR #6152 (Slice C) | `gh pr view 6152` | **MERGED** 2026-07-07; introduced `EXACT_LITERAL_SAFE_COMMANDS`, the `plugin-root-list-carveout-coupling.test.ts` drift guard, and the `${CLAUDE_PLUGIN_ROOT:-…}` migration form. Premise holds. |
| ADR-093 | read decision | **Accepted** 2026-07-06; models the untrusted-workspace-copy trust boundary and the deployed-root rule this plan applies. Premise holds. |
| ADR-095 | read | Fail-closed redaction-engine contract (`redact-sentinel.sh` shim, exit 0/1/2). The migration preserves this CLI contract exactly (only the resolved path changes). Premise holds. |

**Own-capability claims verified (not asserted from memory):**
- The three in-scope sites' current forms were re-grepped at exact line numbers (see §In-Scope Sites).
- `safe-bash.ts` `EXACT_LITERAL_SAFE_COMMANDS` currently holds only the `worktree-manager.sh` list form
  (`safe-bash.ts:168`). `trigger.sh` is a POST helper carrying args — it is **not** a read-only
  `list`/`ls`-class verb, so no carve-out entry is warranted (guardrail satisfied; see §Guardrails).
- `trigger-cron-allowlist-parity.test.ts` references `trigger.sh` as a **file path it `execFileSync`s
  directly** (`SCRIPT = resolve(REPO_ROOT, "plugins/soleur/skills/trigger-cron/scripts/trigger.sh")`),
  NOT as an assertion over SKILL.md prose — so migrating the SKILL.md doc invocations does **not** break it.

## Research Reconciliation — Spec vs. Codebase

No spec.md exists (direct one-shot). Reconciliation instead confirms the feature-description's site
claims against `origin/main`/worktree state:

| Feature-description claim | Codebase reality (grep-verified) | Plan response |
|---|---|---|
| `legal-generate` ~line 60 runs `redact-sentinel.sh` with git-root anchor | `legal-generate/SKILL.md:60`: `SENTINEL="$(git rev-parse --show-toplevel)/plugins/soleur/skills/incident/scripts/redact-sentinel.sh"` — exact match | Migrate, preserve git-root fallback verbatim |
| `incident` invokes the same `redact-sentinel.sh` | `incident/SKILL.md:217`: `Run \`bash scripts/redact-sentinel.sh <draft-tmpfile>\`` — a **bare CWD-relative** `scripts/…` (no explicit repo anchor). `dry-run.sh:31` uses self-locating `${SKILL_DIR}/…` (not agent-run — out of scope) | Migrate line 217 only; **fallback-anchor decision** flagged below (no existing explicit anchor to preserve) |
| `trigger-cron` ~lines 40,43,47 fire `trigger.sh` | `trigger-cron/SKILL.md:40,43,47`: bare `plugins/soleur/skills/trigger-cron/scripts/trigger.sh …` (no `bash` prefix, no explicit anchor) | Migrate all three, preserve bare `plugins/soleur` anchor and no-`bash`-prefix form |

**Fallback-anchor decision (the one genuine judgment call — flag for deepen-plan/review):** the
`incident:217` site has **no existing explicit anchor** to "preserve" (it is bare `scripts/…`, implicitly
CWD-relative). The chosen fallback is the **git-root form** —
`${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/incident/scripts/redact-sentinel.sh`
— because (a) it matches the sibling `legal-generate` site that resolves the **identical** script, and
(b) it matches the shipped Slice C precedent (`compound/SKILL.md:289`). A bare `scripts/…` CWD anchor
would remain fragile from the Concierge sandbox (CWD = connected-repo root, where `scripts/redact-sentinel.sh`
does not exist), so keeping the bare form as a fallback is rejected.

## User-Brand Impact

**If this lands broken, the user experiences:** on the Concierge server, either (a) a redaction gate
that resolves to the connected repo's **untrusted** `redact-sentinel.sh` copy — a maliciously-neutered
copy could pass a draft containing a secret straight into the operator transcript / onto disk; or (b)
a prod-cron `trigger.sh` copy that alters the POST target/body of a live cron fire. This is precisely
the hole ADR-093 closes; the residual subset is its highest-stakes remainder.

**If this leaks, the user's data / secrets are exposed via:** an un-redacted API key / PII in a legal
draft or PIR crossing the transcript write boundary (the redaction gate is the sole barrier there), or
a spoofed/redirected prod-cron POST.

**Brand-survival threshold:** `single-user incident`. A single Concierge user's untrusted-copy execution
of a neutered redaction gate is a secret-leak incident. → `requires_cpo_signoff: true`;
`user-impact-reviewer` runs at review time.

> Note on the change's own failure mode: `redact-sentinel.sh` is **fail-closed** (exit 2 halts). A
> *mis-resolved* path (unreadable) therefore degrades to a halt, not a silent leak — but the whole point
> is to guarantee the **trusted** gate runs at all, so the threshold reflects the vulnerability being
> closed, not merely the migration's regression surface.

## In-Scope Sites — exact before/after

### Site 1 — `plugins/soleur/skills/legal-generate/SKILL.md:60`

```diff
- SENTINEL="$(git rev-parse --show-toplevel)/plugins/soleur/skills/incident/scripts/redact-sentinel.sh"
+ SENTINEL="${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/incident/scripts/redact-sentinel.sh"
```

Git-root fallback preserved verbatim. **Prose touch-up (lines 55–57):** the surrounding paragraph
explains "Resolve the path from the repo root — NOT a bare `../incident/...` relative path". Update it
to describe the deployed-root-first resolution (deployed `${CLAUDE_PLUGIN_ROOT}`, git-root fallback for
CLI/worktree) so the explanation stays honest. The `[[ -r "$SENTINEL" ]] || … exit 2` fail-closed guard
(line 61) and the `bash "$SENTINEL"` invocation (line 62) are unchanged.

### Site 2 — `plugins/soleur/skills/incident/SKILL.md:217`

```diff
- Run `bash scripts/redact-sentinel.sh <draft-tmpfile>` against the unwritten draft.
+ Run `bash ${CLAUDE_PLUGIN_ROOT:-$(git rev-parse --show-toplevel)/plugins/soleur}/skills/incident/scripts/redact-sentinel.sh <draft-tmpfile>` against the unwritten draft.
```

Only the agent-executed invocation at line 217 is migrated. `dry-run.sh:31` (`${SKILL_DIR}/…`,
self-locating from `$0`) and the markdown reference-link at line 24 (`[scripts/redact-sentinel.sh](./scripts/redact-sentinel.sh)`)
are **not** invocations and stay as-is.

### Site 3 — `plugins/soleur/skills/trigger-cron/SKILL.md:40,43,47`

```diff
- plugins/soleur/skills/trigger-cron/scripts/trigger.sh --list
+ ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/trigger-cron/scripts/trigger.sh --list

- plugins/soleur/skills/trigger-cron/scripts/trigger.sh \
+ ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/trigger-cron/scripts/trigger.sh \
    --event cron/bug-fixer.manual-trigger --data '{"issue_number":4383}' --dry-run

- plugins/soleur/skills/trigger-cron/scripts/trigger.sh \
+ ${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/trigger-cron/scripts/trigger.sh \
    --event cron/workspace-sync-health.manual-trigger
```

Bare `plugins/soleur` anchor and no-`bash`-prefix form preserved exactly. The markdown reference-link
at line 36 (`[scripts/trigger.sh](./scripts/trigger.sh)`) is a doc link, not an invocation — leave it.
The Sharp Edge at line 63 ("run from a worktree, never the bare-repo root") stays valid: `trigger.sh`
locates `cron-manifest.ts` from **CWD** (must be a worktree) independently of where the script binary is
resolved from — so the deployed-anchor form and the worktree-CWD requirement are orthogonal and both hold.

## Files to Edit

- `plugins/soleur/skills/legal-generate/SKILL.md` — Site 1 + prose touch-up (lines 55–57, 60)
- `plugins/soleur/skills/incident/SKILL.md` — Site 2 (line 217)
- `plugins/soleur/skills/trigger-cron/SKILL.md` — Site 3 (lines 40, 43, 47)

## Files to Create

- None. (Plan + tasks artifacts only.)

## Guardrails (verified — no code-side change required)

- **`safe-bash.ts`:** NO change. The migrations emit **no new read-only `list`/`ls`-class verb** —
  `redact-sentinel.sh` takes a draft-file argument; `trigger.sh` takes `--list`/`--event`/`--data`/
  `--dry-run` and is a POST helper. Neither belongs in `EXACT_LITERAL_SAFE_COMMANDS`. (Had a new list/ls
  emission appeared, the deployed-form literal would be added via `security-sentinel` and the
  `plugin-root-list-carveout-coupling.test.ts` drift guard would cover it — not applicable here.)
- **`plugin-root-list-carveout-coupling.test.ts`:** unchanged and still green — it is a directory walk
  scoped to `worktree-manager.sh (list|ls)` emissions; our sites emit none.
- **`trigger-cron-allowlist-parity.test.ts`:** unchanged and still green — executes `trigger.sh` by
  resolved file path, does not read SKILL.md prose.
- **`redact-sentinel.test.sh` Test 11a/11b/11c:** still green — 11b greps `redact-sentinel\.sh` (still
  present in `legal-generate/SKILL.md`), 11c asserts the gate precedes `## Phase 3` (line ordering
  unchanged).

## Non-Goals / Out of Scope (stays in #6154, left OPEN)

The low-stakes agent-run families remain deferred and tracked in **#6154**:
`skill-creator`, `plan`, `compound-capture`, `kb-search`, `harvest-debt`, `seo-aeo`, and any other
family enumerated there that is not one of the three security-critical sites above. The PR body MUST
note the subset carved out so #6154's scope is honestly narrowed (do NOT close #6154).

## Implementation Phases

**Phase 1 — Migrate the three sites (contract order: redaction gate first).**
1. `legal-generate/SKILL.md` — Site 1 line 60 + prose 55–57.
2. `incident/SKILL.md` — Site 2 line 217.
3. `trigger-cron/SKILL.md` — Site 3 lines 40/43/47.

**Phase 2 — Verify guardrails untouched.**
- `git diff --stat` shows only the three SKILL.md files changed (no `safe-bash.ts`, no test files).
- Run the four guardrail suites (see Acceptance Criteria / Test Scenarios).

**Phase 3 — Dual-resolution proof (per site).**
- For each migrated invocation, prove expansion under both regimes (see Test Scenarios 4).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `grep -n 'CLAUDE_PLUGIN_ROOT' plugins/soleur/skills/legal-generate/SKILL.md` shows the Site 1
      SENTINEL line with the git-root fallback preserved verbatim; the `$(git rev-parse --show-toplevel)/plugins/soleur`
      substring is intact inside the `:-` default.
- [ ] `grep -c 'bash scripts/redact-sentinel.sh' plugins/soleur/skills/incident/SKILL.md` returns `0`
      (the bare CWD-relative form is gone) AND `grep -c 'CLAUDE_PLUGIN_ROOT.*skills/incident/scripts/redact-sentinel.sh' plugins/soleur/skills/incident/SKILL.md` returns `1`.
- [ ] `grep -cE '^\s*plugins/soleur/skills/trigger-cron/scripts/trigger\.sh' plugins/soleur/skills/trigger-cron/SKILL.md`
      returns `0` (no un-anchored invocation lines) AND `grep -c '${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/skills/trigger-cron/scripts/trigger.sh' plugins/soleur/skills/trigger-cron/SKILL.md`
      returns `3`. (The line-36 markdown reference-link `[scripts/trigger.sh](./scripts/trigger.sh)` is
      excluded by the `^\s*plugins/…` anchor.)
- [ ] `git diff --name-only origin/main...HEAD -- apps/web-platform/server/safe-bash.ts` is empty
      (guardrail: no safe-bash change).
- [ ] `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh` passes (Tests 11a/11b/11c green).
- [ ] `./node_modules/.bin/vitest run apps/web-platform/test/plugin-root-list-carveout-coupling.test.ts`
      passes (verify runner via `apps/web-platform/package.json`; drift guard unaffected).
- [ ] `trigger-cron-allowlist-parity.test.ts` passes (run via the package's configured runner —
      `bun:test` import; confirm `bun test plugins/soleur/test/trigger-cron-allowlist-parity.test.ts`
      per repo convention, or the plugin test entrypoint).
- [ ] Dual-resolution proof recorded for all three sites (Test Scenario 4) — both `CLAUDE_PLUGIN_ROOT`
      set and unset expand to a readable, correct path.
- [ ] PR body uses `Closes #6156` and a "Scope carved out of #6154" note that leaves #6154 OPEN.

### Post-merge (operator / automated)

- [ ] `#6156` auto-closes on merge (via `Closes #6156`). `#6154` remains OPEN — verify with
      `gh issue view 6154 --json state` (automatable via `gh` in `/ship` post-merge; not operator-manual).
- [ ] No operator SSH / dashboard step required (pure plugin-doc change; deployed via the standard
      image-rebuild plugin deploy path per ADR-080 — not in scope to trigger here).

## Test Scenarios

1. **Redaction-gate contract intact (legal-generate + incident).** `bash plugins/soleur/skills/incident/test/redact-sentinel.test.sh`
   — Test 11a (secret trips exit 1), 11b (legal wires `redact-sentinel.sh`), 11c (gate precedes Phase 3).
2. **safe-bash carve-out unchanged.** `plugin-root-list-carveout-coupling.test.ts` green; `git diff` shows no `safe-bash.ts`.
3. **trigger-cron parity intact.** `trigger-cron-allowlist-parity.test.ts` green (executes `trigger.sh` directly).
4. **Dual-resolution probe (per site).** For each migrated invocation, from a worktree:
   - **Unset** (`unset CLAUDE_PLUGIN_ROOT; echo "<expanded>"`) → resolves to the git-root/`plugins/soleur`
     fallback path, and `[[ -r <path> ]]` is true.
   - **Set** (`CLAUDE_PLUGIN_ROOT=/app/shared/plugins/soleur; echo "<expanded>"`) → resolves to
     `/app/shared/plugins/soleur/skills/.../<script>.sh` (the deployed/trusted copy).
   - Confirms the `:-` default expansion is well-formed at each site.

## Domain Review

**Domains relevant:** none

Pure engineering / security-tooling change (three sibling SKILL.md doc migrations). No Product/UI
surface (`## Files to Edit` contains no `components/**`, `app/**/page.tsx|layout.tsx` — the mechanical
UI-surface override does not fire; Product = NONE, no wireframes). No finance/legal/marketing/sales/
ops/support implications — `legal-generate` is *touched* but the edit hardens its script-resolution
anchor, not any legal content or contract. The security lens is the change itself and is covered at
review time by `security-sentinel` + `user-impact-reviewer` (single-user-incident threshold).

## Observability

**Skipped (pure-docs).** `## Files to Edit` are `plugins/soleur/skills/*/SKILL.md` prose files — none
under the code-class trigger paths (`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, `plugins/*/scripts/`)
and no new infrastructure surface. The Phase 2.9 gate skips silently for pure-docs changes. (The runtime
behavior being hardened already emits through the existing redaction-gate exit-code contract and the
Concierge dispatch path; this change adds no new failure mode.)

## Architecture Decision (ADR/C4)

**No new architectural decision — applies existing ADR-093.** This plan is the documentation-side
application of ADR-093's already-Accepted decision ("always resolve plugin-owned scripts from the
platform-deployed root; the workspace copy is untrusted") to the operator-confirmed security subset.
No decision is created, reversed, or extended.

**C4:** No impact. The untrusted-connected-repo-workspace trust boundary and the external actors/systems
involved (the connected-repo author as an untrusted principal; the Concierge SDK dispatch context) are
**already modeled** by ADR-093 and ADR-074 (`model.c4`, the `contributor`/untrusted-PR-author boundary
first introduced there). This change adds no external human actor, no external system/vendor, no new
data store, and no new actor↔surface access relationship — it moves three existing script-resolution
sites onto the already-modeled deployed-root path. Verified by reading the ADR-093 "Relationship to
prior ADRs" section (cites ADR-074's C4 trust-boundary model) rather than a noun-grep.

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` bodies contain no reference to the three edited
SKILL.md paths — this migration is itself the pull-forward of the #6156/#6154 deferral, not overlapping
an independent scope-out.)

## GDPR / Compliance Gate

**Skipped.** No regulated-data surface touched (no schema, migration, auth flow, API route, `.sql`).
The redaction gate's data-handling contract (what it scans, its fail-closed exit codes) is **unchanged**
— only the path from which the trusted script binary is resolved changes. None of the (a)–(d) expansion
triggers fire (no new LLM processing of session data, no new cron reading learnings/specs, no new
distribution surface; the single-user-incident threshold is declared but the change introduces no new
processing activity — it hardens an existing barrier).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails
  `deepen-plan` Phase 4.6. It is filled above (threshold `single-user incident`).
- **incident fallback-anchor is a judgment call, not a preserved anchor.** The `incident:217` site had
  no explicit anchor; the git-root fallback is chosen to match the sibling `legal-generate` site and the
  `compound:289` precedent. Surface this at deepen-plan/review rather than treating it as mechanical.
- **`trigger.sh` worktree-CWD requirement is orthogonal to the anchor migration.** The Sharp Edge at
  `trigger-cron/SKILL.md:63` ("run from a worktree, never bare-repo root") stays valid — `trigger.sh`
  locates `cron-manifest.ts` from CWD, independent of where its binary resolves. Do NOT delete or weaken
  that Sharp Edge when migrating the invocation lines.
- **Preserve each site's fallback form exactly:** `legal-generate` keeps `$(git rev-parse --show-toplevel)/plugins/soleur`;
  `trigger-cron` keeps bare `plugins/soleur` (no `./`, no `bash ` prefix). Do not "normalize" toward the
  `./plugins/soleur` variant seen in other Slice C sites — the drift-guard rationale in
  `plugin-root-list-carveout-coupling.test.ts` explicitly calls a different fallback anchor a drift.
- **Leave #6154 OPEN.** `Closes #6156` only; #6154 is narrowed, not closed. A stray `Closes #6154`
  would false-resolve the low-stakes remainder.

## PR-body reminders

- `Closes #6156` in the body (not the title) per `wg-use-closes-n-in-pr-body-not-title-to`.
- A "Scope carved out of #6154" paragraph naming the three pulled-forward families and confirming the
  low-stakes remainder stays tracked in the still-open #6154.
- `## Changelog` section (plugin CI reads the semver label). Suggested label: `semver:patch`
  (security hardening of existing skill docs; no new component).
- `type/security` label (matches #6154's classification).
