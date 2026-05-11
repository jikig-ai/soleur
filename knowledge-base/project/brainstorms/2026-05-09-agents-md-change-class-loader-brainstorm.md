---
date: 2026-05-09
topic: change-class-aware AGENTS.md loader
issue: "#3493"
parent_brainstorms:
  - 2026-04-21-agents-md-rule-threshold-brainstorm.md
  - 2026-04-23-agents-md-budget-revisit-brainstorm.md
status: ready-for-plan
---

# Change-Class-Aware AGENTS.md Loader

## What We're Building

A sidecar pointer architecture for AGENTS.md plus a SessionStart hook + PreToolUse pivot detector that injects only the partitions relevant to the current session's change class.

- `AGENTS.md` becomes a thin pointer index (~3k bytes). Every rule keeps its `[id: ...]` line and a one-line summary; full bodies relocate to class-tagged sidecars.
- Sidecars: `AGENTS.core.md` (always loaded), `AGENTS.docs.md`, `AGENTS.code.md`, `AGENTS.infra.md`.
- `core` always loads regardless of class: all `## Hard Rules` (24), `[compliance-tier]`-tagged prompt-only rules (5), all `pdr-*` passive domain routing (2), all `cm-*` communication (3) ≈ 34 rules / ~10–13k bytes.
- `SessionStart` hook reads `git diff --name-only origin/main...HEAD ∪ git status --porcelain`, classifies the union, returns `additionalContext` containing the matching sidecar(s).
- `PreToolUse` hook on `Edit`/`Write`/`Bash` re-classifies the targeted file path; if outside the loaded partition, injects the missing sidecar via `additionalContext` and emits a one-line warn. `/reload-rules` is the operator escape hatch.
- Default class for ambiguous/empty diff = `mixed` → full load (fail-closed).
- Per-session `session-rules-manifest.json` is written under `.claude/.session-manifests/<timestamp>.json` capturing: change-class decision, partition list, rule IDs loaded, AGENTS.md content hash, tool-call drift events. Provides SOC 2 evidence and post-incident reconstruction.
- Loader output is stamped at session start: one-line `loaded: core+docs (34+12 of 69 rules, partition: docs-only)`. Operator audits before any destructive command.

Big-bang migration in a single PR: rule relocation + linter extension + loader + manifest writer + tests + measurement gate. Reviewable as a unit; mechanical move; atomically revertable.

## Why This Approach

The competing options were rejected for the following reasons:

- **CLAUDE.md per-session rewrite:** Worktree dirty-tree footgun. Conflicts with branch-safety hooks.
- **PreSessionStart prompt injection only:** Bypasses every-turn `@AGENTS.md` reload mechanism that the ETH Zurich data depends on (10–22% reasoning-token overhead is per-turn — injection-once doesn't replicate it).
- **In-place classifier on `AGENTS.md`:** Cannot literally remove rule bodies because `scripts/lint-rule-ids.py` hard-fails any `[id]` removal. Pointer pattern is the only `lint-rule-ids.py`-compatible mechanism.
- **Wedge-only (docs partition first):** Picked against. Rule relocation is the mechanical bulk of the work and amortizes once across all classes; landing it incrementally multiplies review cycles without de-risking the linter migration.
- **Conservative core (Workflow Gates always loaded):** Saves only ~20% on docs sessions. The recommended scope yields ~47% docs / ~31% code reduction while keeping the brand-survival floor at full strength via the `[compliance-tier]` tag.

The recommended core scope keeps every Hard Rule and every compliance rule always-on. A misclassified session loses Code-Quality or Workflow-Gate context (recoverable), never credential or auth context (catastrophic). This inverts the failure asymmetry CTO flagged: false-negative loss falls on Code-Quality, where artifact-level enforcement (CI, hooks) backstops most rules.

PreToolUse pivot detection in v1 closes the docs-pivots-to-credentials hole. Without it, a "fix typo" session that pivots into `apps/web-platform/server/session-sync.ts` runs without `hr-never-git-add-a-in-user-repo-agents` in context — the exact #2887/#2905-class shape AGENTS.md exists to prevent.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Mechanism | Sidecar pointer index + SessionStart `additionalContext` | Only `lint-rule-ids.py`-compatible path; SessionStart is unused today; canonical Claude Code primitive |
| Core scope | Hard Rules + `[compliance-tier]` + pdr + cm | ~34 rules, ~10–13k bytes; full brand-survival floor preserved |
| New tag | `[compliance-tier]` on 5 prompt-only rules: `hr-never-paste-secrets-via-bang-prefix`, `hr-menu-option-ack-not-prod-write-auth`, `hr-never-git-add-a-in-user-repo-agents`, `cq-pg-security-definer-search-path-pin-pg-temp`, `hr-exhaust-all-automated-options-before` | CLO-flagged: prompt-only compliance rules whose loss = silent compliance bypass with no artifact-level enforcement |
| Class taxonomy | `core` (always), `docs-only`, `code`, `infra`. Default ambiguous = `mixed` → full load | Reuses review-skill seed taxonomy at `plugins/soleur/skills/review/SKILL.md:65-96`, extended for `docs-only` + `infra` |
| Pivot policy v1 | PreToolUse re-classifier on `Edit`/`Write`/`Bash`; injects missing sidecar + warns | Closes mid-session silent-drop hole; latency cost accepted for safety |
| Stamp | One-line load summary at session start | Operator transparency; mirror to `cq-silent-fallback-must-mirror-to-sentry` posture |
| Audit artifact | `.claude/.session-manifests/<timestamp>.json` | SOC 2 evidence; post-incident attribution; loader regression detection signal |
| Migration | Big-bang one PR | Mechanical move + linter migration is atomic; revert is single commit |
| Measurement | N=10–20 representative recent sessions, classifier applied retrospectively, `wc -c` actual savings before plan-time savings claim | Per learning `2026-04-23-agents-md-governance-measure-before-asserting.md` — two prior governance brainstorms shipped wrong byte-savings claims |
| Failure mode | Fail-closed to full AGENTS.md load on classifier error or malformed sidecar | Aligns with CPO operator-expectation; matches `cq-agents-md-tier-gate` posture |

## User-Brand Impact

- **Artifact:** Change-class-aware AGENTS.md loader (SessionStart hook + PreToolUse pivot detector + sidecar pointer architecture).
- **Vector:** Misclassification or missing PreToolUse pivot detection causes a credential/auth/data-isolation rule to be absent from prompt-time context for a session pivot into sensitive code paths. Operator ships a change that the absent rule was written to prevent (e.g., committing a `.claude/settings.json` wipe via `git add -A` in a connected-repo agent path; pasting a Doppler secret via the `! ` prefix; running an unauthorized `terraform apply`).
- **Threshold:** `single-user incident`. The #2887 dev/prd Doppler-config collapse is the precedent the brand-survival framing names directly. A loader that drops `hr-dev-prd-distinct-supabase-projects` from a session that goes on to mutate Doppler is a re-creation of that exact incident shape.
- **Mitigations baked into the design:**
  1. `[compliance-tier]` tag forces 5 prompt-only compliance rules into `core` regardless of classifier output.
  2. Default class for ambiguous diff = `mixed` → full load (fail-closed).
  3. PreToolUse pivot detector injects missing partition before the destructive edit lands.
  4. `session-rules-manifest.json` enables post-incident attribution; loader regression signal cross-references manifest against `emit_incident` JSONL.
  5. Stamped load output gives operator a chance to read what's missing before `terraform apply` / `doppler secrets set` / `git push`.
  6. Plan-time `user-impact-reviewer` sign-off mandatory per `hr-weigh-every-decision-against-target-user-impact`.

## Open Questions

1. **Workflow Gates section placement.** Most `wg-*` rules are session-universal (commit, session-start, PR-merge polling). Plan must decide: in core, or in a fifth `workflow` sidecar with `always-load` flag. Recommend core for v1; revisit if core grows past ~15k.
2. **Tagging accuracy validation.** Some rules are cross-cutting (e.g., `cq-test-fixtures-synthesized-only` triggers in code AND docs sessions when fixtures are markdown-formatted). Plan needs a "tag in 2+ classes" pattern.
3. **Telemetry blind spot.** 78% of rules are prompt-only and don't emit `applied`/`bypass` events. Loader regression detection has no signal for those. Plan should consider: (a) extend `emit_incident` calls into more skills/agents that consult AGENTS.md; (b) accept post-mortem-only attribution for v1.
4. **Linter migration cost.** `scripts/lint-rule-ids.py` currently scans only `AGENTS.md` for `[id]`. Extending to `AGENTS.*.md` is straightforward but `scripts/retired-rule-ids.txt` semantics need to remain valid across all sidecars.
5. **Compaction re-entrancy.** SessionStart hook fires on `compact`/`clear` matchers per learning `2026-03-04-sessionstart-hook-api-contract.md`. Loader must be idempotent; plan should include a test that confirms rule set is identical across 3 successive compactions.
6. **Operator escape hatch.** `/reload-rules` slash command form vs. a Bash sidecar invocation vs. a hook-driven re-stamp. Plan to pick smallest surface.
7. **Plugin-loader visibility.** AGENTS.md sidecars must NOT be discovered as plugin components by the Soleur plugin loader. Plan should verify file-name conventions don't trip plugin discovery (per `plugins/soleur/AGENTS.md` directory-structure rules).

## Domain Assessments

**Assessed:** Engineering, Product, Legal (mandatory CTO+CPO+CLO trio for `USER_BRAND_CRITICAL=true`). Marketing, Operations, Sales, Finance, Support not relevant to internal CLI infrastructure.

### Engineering (CTO)

**Summary:** Sidecar pointer is the only `lint-rule-ids.py`-compatible mechanism. Mid-session pivot is the brand-killer; PreToolUse re-classifier is load-bearing safety. False-negative cost asymmetry mandates fail-closed default and `mixed` class for ambiguous diff. Reframe target as safety-weighted ("X% reduction with zero credential drops") not raw 60–70%. SessionStart hook with `additionalContext` is the canonical primitive; `CLAUDE.md` rewrite and prompt-injection-only options rejected. Always-core: every Hard Rule + credential/auth/payment-tagged + pdr routing. Telemetry: bytes-saved per session AND post-session loaded-vs-fired audit.

### Product (CPO)

**Summary:** Operator UX requires a load stamp at session start (silent partitioning is the same failure shape as silent fallback per `cq-silent-fallback-must-mirror-to-sentry`). Mid-session pivot is the load-bearing decision: PreToolUse warn + `/reload-rules` escape hatch, never auto-magic and never "restart your session" hostility. Multi-operator portability scoped to Soleur repo only in v1 (operator-specific keying off rule-tag conventions). Failure mode = fail-closed to full AGENTS.md load. Wedge concern overruled in favor of big-bang because rule relocation is the mechanical bulk and amortizes across classes.

### Legal (CLO)

**Summary:** The `[compliance-tier]` tag is the single most important addition; without it, 5 prompt-only compliance rules can be silently dropped (catastrophic blast radius for `hr-never-paste-secrets-via-bang-prefix` — secret enters transcript + API logs + on-disk artifact, irreversible). Audit-trail gap is independent of token-efficiency motivation: `session-rules-manifest.json` is the SOC 2 CC6.1 / CC7.2 evidence artifact and must ship in v1, not deferred. Compliance rules are NOT cleanly partition-able by change class — always-on tier is the only defensible posture. If a future Trust Center page exists, it must describe the loader honestly ("always-on compliance tier + change-scoped tiers + per-session manifest"); never claim "all rules always loaded."

## Capability Gaps

None. The loader composes existing primitives:

- **Hooks:** `SessionStart` and `PreToolUse` are first-class Claude Code hook events (verified: `.claude/hooks/README.md` documents the JSON envelope; `.claude/hooks/pre-merge-rebase.sh:192-194` provides the closest pattern for `additionalContext` injection).
- **Classifier seed:** `plugins/soleur/skills/review/SKILL.md:65-96` already classifies code vs. non-code with file-extension lists; reusable.
- **Telemetry plumbing:** `.claude/hooks/lib/incidents.sh:67-112` (`emit_incident`) provides the JSONL writer; `scripts/lib/rule-metrics-constants.sh` provides schema versioning. Manifest writer can reuse this lib.
- **Linter:** `scripts/lint-rule-ids.py` exists; extension to scan `AGENTS.*.md` is mechanical (verified by reading the linter's path-glob in the existing implementation).
- **Existing pointer pattern:** Per learning `2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`, the pointer migration is byte-neutral on small rules but enables architectural separation; the loader generalizes this pattern across all rules.
