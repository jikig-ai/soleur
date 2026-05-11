# Feature: change-class-aware AGENTS.md loader

**Issue:** #3493 (parent token-efficiency catalog; Option 1 of 4)
**Brainstorm:** [2026-05-09-agents-md-change-class-loader-brainstorm.md](../../brainstorms/2026-05-09-agents-md-change-class-loader-brainstorm.md)
**Branch:** `feat-agents-md-change-class-loader`
**Draft PR:** #3496
**Brand-survival threshold:** `single-user incident` (USER_BRAND_CRITICAL=true)

## Problem Statement

`AGENTS.md` (24,618 bytes, 69 rules) is loaded into context on every turn via `@AGENTS.md` in `CLAUDE.md`. Per ETH Zurich data captured in learning `2026-02-25-lean-agents-md-gotchas-only.md`, this carries a 10–22% per-turn reasoning-token overhead. ~78% of rules (54 of 69) are prompt-only — they have no `[hook-enforced:]` / `[skill-enforced:]` / `[scanner-enforced:]` tag and rely on operator/agent reading the AGENTS.md text to apply.

Most sessions do not exercise most rules. A docs-only PR (e.g., #3491 — 7 markdown files) loads infra, code-quality, payment, Postgres, and React rules that have zero relevance to the change. The growth rate (4.7 rules/day per learning `2026-04-23-agents-md-governance-measure-before-asserting.md`) means this overhead compounds.

`scripts/lint-rule-ids.py` blocks any `[id]` removal from AGENTS.md, so the loader cannot literally subtract rules; it must change *how* rules are loaded without changing *which* rules exist.

## Goals

- Reduce median per-turn AGENTS.md bytes injected by ≥30% on single-class sessions while keeping zero credential / auth / payment / data-isolation rules dropped.
- Preserve full `AGENTS.md` registry (no rule deletions; `lint-rule-ids.py` immutability contract intact).
- Add a `[compliance-tier]` always-on tag for prompt-only compliance rules whose loss would cause silent compliance bypass.
- Ship a per-session `session-rules-manifest.json` audit artifact for SOC 2 evidence and post-incident attribution.
- Detect and remediate mid-session class drift (operator pivots from docs to credential code) before the destructive edit lands.

## Non-Goals

- Tackling the other three optimizations from #3493 (review docs-only tier, plan/deepen-plan elision, preflight Phase 0 early-bail). Each is a separate PR per #3493 scope-out justification.
- Generalizing the loader to arbitrary repos / non-Soleur AGENTS.md files. v1 is operator-specific to this repo's tag conventions.
- Replacing or modifying the existing `rule-metrics-aggregate.yml` telemetry pipeline. The loader emits new manifest artifacts but does not alter `emit_incident` semantics.
- Cross-machine portability beyond Linux + Claude Code CLI. Windows operators are out-of-scope for v1.
- An interactive `/reload-rules` slash command (deferred until Bash-driven invocation is validated in real sessions).

## Functional Requirements

### FR1: Sidecar pointer architecture

`AGENTS.md` becomes a thin pointer index. Every rule retains its `[id: ...]` tag and a one-line summary. Full bodies relocate into class-tagged sidecar files at the repo root:

- `AGENTS.core.md` — always loaded
- `AGENTS.docs.md` — loaded for `docs-only` sessions
- `AGENTS.code.md` — loaded for `code` sessions
- `AGENTS.infra.md` — loaded for `infra` sessions

A rule may appear in more than one sidecar if it spans classes (e.g., `cq-test-fixtures-synthesized-only` triggers in both code and docs sessions).

### FR2: Always-loaded `core` partition

`AGENTS.core.md` contains:

- All `## Hard Rules` (currently 24)
- All rules tagged `[compliance-tier]` (5 prompt-only at v1: `hr-never-paste-secrets-via-bang-prefix`, `hr-menu-option-ack-not-prod-write-auth`, `hr-never-git-add-a-in-user-repo-agents`, `cq-pg-security-definer-search-path-pin-pg-temp`, `hr-exhaust-all-automated-options-before`)
- All `pdr-*` passive domain routing rules (currently 2)
- All `cm-*` communication rules (currently 3)

Total: ~34 rules / target ≤13k bytes for v1.

### FR3: SessionStart classifier hook

A new `.claude/hooks/session-rules-loader.sh` registered for `SessionStart` matchers `startup`, `resume`, `clear`, `compact`. It:

1. Computes the change set as `git diff --name-only origin/main...HEAD ∪ git status --porcelain | awk '{print $2}'`.
2. Classifies each path against the file-pattern lists derived from `plugins/soleur/skills/review/SKILL.md:65-96`, extended for `docs-only` (markdown + YAML + image extensions) and `infra` (`apps/*/infra/**`, `**/terraform/**`, `*.tf`, `.github/workflows/**`, `Doppler*`, etc.).
3. Returns `hookSpecificOutput.additionalContext` containing the concatenated content of `AGENTS.core.md` plus the matching class sidecar(s).
4. Writes `session-rules-manifest.json` (FR6).
5. Stamps a one-line summary into `additionalContext` header: `loaded: core+<class> (<rule-count> of <total> rules, partition: <class>)`.

### FR4: PreToolUse mid-session pivot detector

A new `.claude/hooks/session-rules-pivot.sh` registered for `PreToolUse` matchers `Edit`, `Write`, `Bash`. It:

1. Reads the last-written `session-rules-manifest.json` to learn the loaded class set.
2. For `Edit`/`Write`, classifies the targeted file path. For `Bash`, scans the command for path arguments (`terraform`, `doppler`, `gh secret`, `psql`, etc.).
3. If the targeted path matches a class NOT in the loaded set, injects the missing class sidecar via `additionalContext` and emits a one-line warn. Manifest is updated to reflect the augmented load.
4. Never blocks the tool call. The injection is additive, not substitutive.

### FR5: Default class for ambiguous diff

When the change set is empty (fresh worktree, on `main`, no uncommitted changes) or contains paths that match `mixed` (≥2 distinct classes), the loader returns `core + docs + code + infra` (full load). This is the fail-closed default.

### FR6: Session-rules-manifest

`.claude/.session-manifests/<ISO-timestamp>.json`:

```json
{
  "session_id": "...",
  "timestamp": "2026-05-09T14:32:11Z",
  "change_class": "docs-only" | "code" | "infra" | "mixed",
  "partitions_loaded": ["core", "docs"],
  "rule_ids_loaded": ["hr-...", "cq-...", ...],
  "agents_md_index_hash": "sha256:...",
  "sidecar_hashes": {"core": "sha256:...", "docs": "sha256:..."},
  "pivot_events": [
    {"timestamp": "...", "tool": "Edit", "path": "apps/web-platform/server/session-sync.ts", "from_class": "docs-only", "to_class": "code"}
  ]
}
```

The manifest is appended-to on PreToolUse pivot events (FR4). It is .gitignored at the repo level but referenced from PR descriptions for SOC 2 evidence.

### FR7: Operator-facing transparency

The SessionStart stamp (FR3) is the primary transparency surface. Stamp format:

```
[rules-loader] loaded: core+docs-only (34+12 of 69 rules)
[rules-loader] manifest: .claude/.session-manifests/2026-05-09T14-32-11Z.json
```

A pivot warn (FR4) is the secondary surface:

```
[rules-loader] PIVOT: Edit apps/.../session-sync.ts is in class 'code' but loaded class is 'docs-only'. Injecting AGENTS.code.md (15 additional rules).
```

## Technical Requirements

### TR1: AGENTS.md immutability contract

`scripts/lint-rule-ids.py` must extend to recognize `AGENTS.*.md` (sidecars) as part of the rule-ID universe. A rule's `[id]` tag must continue to live in `AGENTS.md` (the index) — sidecars hold the rule's body, but the index is canonical for `[id]` discovery and `retired-rule-ids.txt` integrity. Removing an `[id]` from the index still requires retirement-allowlist semantics.

### TR2: Hook registration in `.claude/settings.json`

Add `SessionStart` and `PreToolUse` registrations:

```json
{
  "hooks": {
    "SessionStart": [{ "matcher": "startup|resume|clear|compact", "hooks": [{ "command": ".claude/hooks/session-rules-loader.sh" }] }],
    "PreToolUse": [{ "matcher": "Edit|Write|Bash", "hooks": [{ "command": ".claude/hooks/session-rules-pivot.sh" }] }]
  }
}
```

PreToolUse pivot hook MUST run AFTER existing guards (`worktree-write-guard.sh`, `guardrails.sh`) per learning `2026-03-28-pretooluse-hook-guard-ordering-matters.md`. Hook ordering documented in `.claude/hooks/README.md`.

### TR3: Plugin-loader visibility

`AGENTS.*.md` sidecars must NOT be discovered as plugin components. Soleur plugin loader scans `plugins/soleur/{commands,skills,agents}/`; sidecars at repo root are out of scope. Verify by running `bun test plugins/soleur/test/components.test.ts` after refactor.

### TR4: Compaction re-entrancy

`SessionStart` hook fires on `compact` and `clear` matchers per learning `2026-03-04-sessionstart-hook-api-contract.md`. Loader must be idempotent: re-running on the same diff state must produce the identical `additionalContext`. A test must confirm rule set parity across 3 successive compactions.

### TR5: Measurement gate before plan-time savings claim

Per learning `2026-04-23-agents-md-governance-measure-before-asserting.md`, plan-time numerical claims for byte savings MUST be measured, not estimated:

1. Sample N=10–20 recent merged PRs across `docs-only`, `code`, `infra`, `mixed` classes.
2. Apply the classifier retrospectively to each PR's diff.
3. `wc -c` the resulting partition load vs. current full AGENTS.md.
4. Plan reports actual median bytes saved per class, not estimates.

### TR6: Rule-tag taxonomy migration

The Code Quality, Workflow Gates, Review & Feedback, Communication, and Passive Domain Routing sections of `AGENTS.md` need per-rule class assignment. A `tools/migration/classify-rules.sh` script reads each rule, prints a proposed class assignment based on tag heuristics + content keywords, and writes the result to `tools/migration/rule-classification.tsv` for human review before rules are physically moved.

### TR7: Linter migration

`scripts/lint-rule-ids.py` must:

1. Scan `AGENTS.md` (index) and all `AGENTS.*.md` (sidecars) for `[id: ...]` tags.
2. Verify every `[id]` in a sidecar has a matching pointer line in the index.
3. Verify every pointer line in the index resolves to exactly one sidecar location.
4. Continue to enforce `retired-rule-ids.txt` semantics across the union.

### TR8: Compound skill bytes-cap migration

`plugins/soleur/skills/compound/SKILL.md` step 8 currently warns at 37k / critical at 40k for `AGENTS.md`. Migrate to a sum check across `AGENTS.md` + all `AGENTS.*.md` (total registry size) AND a per-tier check (`AGENTS.core.md` ≤15k as the safety-weighted always-on floor).

### TR9: Telemetry blind-spot acknowledgment

54 of 69 rules are prompt-only and do not call `emit_incident`. Loader regression detection has no signal for those rules. v1 explicitly accepts this gap. v2 considerations (out of scope): (a) extend `emit_incident` calls into more skills/agents that consult AGENTS.md; (b) post-mortem-only attribution via manifest cross-referencing.

### TR10: Fail-closed posture

Any error in classifier, hook, or sidecar loading must result in full `AGENTS.md`-equivalent context (i.e., `additionalContext` = concatenation of all sidecars). Stderr warning is emitted but session does not block. Aligns with `cq-agents-md-tier-gate` posture.

### TR11: Audit trail .gitignore

`.claude/.session-manifests/` is `.gitignore`d at the repo level. Manifest paths are referenced from PR descriptions for SOC 2 evidence; CI/agents that need to upload manifests for audit purposes do so via explicit `gh issue comment` / `gh pr comment` attachments, not git commits.

## Acceptance Criteria

- [ ] `AGENTS.md` reduced to pointer-index form; every rule's body lives in exactly one of `AGENTS.{core,docs,code,infra}.md`. Optionally a rule appears in 2+ sidecars when cross-cutting.
- [ ] `core` partition contains: all `## Hard Rules`, all `[compliance-tier]`-tagged rules, all `pdr-*`, all `cm-*`. Total ≤15k bytes.
- [ ] 5 prompt-only compliance rules tagged `[compliance-tier]`.
- [ ] `.claude/hooks/session-rules-loader.sh` registered for SessionStart and writes manifests.
- [ ] `.claude/hooks/session-rules-pivot.sh` registered for PreToolUse Edit/Write/Bash and injects missing partitions.
- [ ] `scripts/lint-rule-ids.py` extended to scan all `AGENTS.*.md` files; existing retirement allowlist semantics preserved.
- [ ] Compaction re-entrancy test: classifier produces identical output across 3 successive `compact` events.
- [ ] Measurement run: N=10–20 sampled PRs, retrospective classifier applied, actual median bytes saved reported in PR description.
- [ ] Plugin-loader visibility test (`bun test plugins/soleur/test/components.test.ts`) passes — sidecars not discovered as plugin components.
- [ ] `cq-agents-md-why-single-line` rule + compound skill step 8 updated to count across all `AGENTS.*.md`.
- [ ] `user-impact-reviewer` sign-off on PR per `hr-weigh-every-decision-against-target-user-impact` (USER_BRAND_CRITICAL=true).
- [ ] `roadmap.md` updated to reflect un-deferred status; `deferred-scope-out` label removed from #3493; milestone changed from `Post-MVP / Later` to current active phase.
- [ ] Learning file added to `knowledge-base/project/learnings/` documenting measured savings + classifier accuracy.
