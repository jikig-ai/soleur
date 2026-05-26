---
issue: "#3493"
brainstorm: knowledge-base/project/brainstorms/2026-05-09-agents-md-change-class-loader-brainstorm.md
spec: knowledge-base/project/specs/feat-agents-md-change-class-loader/spec.md
branch: feat-agents-md-change-class-loader
worktree: .worktrees/feat-agents-md-change-class-loader/
pr: "#3496"
classification: feature
type: cross-cutting-infra
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
domain: engineering
milestone: "Phase 4: Validate + Scale"
labels:
  - enhancement
  - domain/engineering
  - priority/p2-medium
revision: v2-post-plan-review
---

# Plan: change-class-aware AGENTS.md loader (v2)

> **v2 note (2026-05-09 post-plan-review):** Simplified per converging DHH + code-simplicity feedback. Cut: PreToolUse pivot detector, multi-class `[classes:]` hint, 9-field manifest (→ 3 fields), shared `classify-changes.sh`/`manifest-writer.sh` libs (→ inline), separate Phase 0 measurement script (→ folded into `classify-rules.sh`), `AGENTS.workflow.md` (decided: no — `wg-*` go to core). Fixed Kieran P0-1 (worktree-from-bare-repo path resolution), P0-2 (race moot after pivot drop), P0-3 (empirically: core lands ~10.5k, not 14.4k — under 15k budget). 6 phases (was 12), 7 net-new files (was 17), ~11 test cases (was 30+).

## Overview

Restructure `AGENTS.md` from a single 24,618-byte every-turn-loaded rule sheet into a sidecar pointer architecture where bodies live in three change-class–scoped files (`AGENTS.core.md`, `AGENTS.docs.md`, `AGENTS.rest.md`). Add a `SessionStart` hook that injects `AGENTS.core.md` always plus the matching change-class sidecar. Add a `[compliance-tier]` always-on tag for five prompt-only compliance rules. Add a slim per-session manifest (3 fields) for SOC 2 evidence. Migrate `scripts/lint-rule-ids.py` to scan the union of `AGENTS*.md` files. Migrate `compound` skill step 8 to count always-loaded payload (index + core).

**Mid-session pivot safety** is delivered by the fail-closed `mixed` default (any non-empty multi-class diff loads everything) plus a SessionStart stamp that tells the operator how to force-reload (`LOADER_FAIL_CLOSED=1`). The originally-planned PreToolUse pivot detector was cut at plan-review (DHH + simplicity convergence): ~250 LOC + 50–200ms × 100 tool-calls/session latency tax for safety already covered one tier up by fail-closed defaults + operator stamp. CTO/CPO/CLO brainstorm consensus is reaffirmed at the plan-time CPO sign-off comment.

Single-PR big-bang migration. Rule-relocation is mechanical bulk; landing it incrementally would multiply review cycles without de-risking the linter migration.

## User-Brand Impact

- **If this lands broken, the user experiences:** a misclassified session (e.g., a pure-docs diff that pivots mid-session into credential code) with the credential-class rules absent from prompt-time context. With the pivot detector cut, the load-bearing question becomes: does the operator notice the SessionStart stamp ("loaded: core+docs-only") and remember to run `LOADER_FAIL_CLOSED=1 bash .claude/hooks/session-rules-loader.sh < <(echo '{}')` when scope shifts? If they don't, the agent could ship a `git add -A` connected-repo write (the #2887/#2905 shape `hr-never-git-add-a-in-user-repo-agents` exists to prevent) because the rule's text isn't in the prompt.
- **If this leaks, the user's data / workflow / money is exposed via:** silent compliance bypass on the five prompt-only compliance rules — `hr-never-paste-secrets-via-bang-prefix` (irreversible transcript leak), `hr-menu-option-ack-not-prod-write-auth` (unauthorized prod mutation), `hr-never-git-add-a-in-user-repo-agents` (cross-tenant settings.json wipe), `cq-pg-security-definer-search-path-pin-pg-temp` (privilege escalation), `hr-exhaust-all-automated-options-before` (operator credential prompt when Doppler holds the secret).
- **Brand-survival threshold:** `single-user incident`. `requires_cpo_signoff: true` (frontmatter). `user-impact-reviewer` invocation mandatory at PR-time review.

Mitigations baked into v2, ranked:

1. `[compliance-tier]` tag forces 5 prompt-only compliance rules into `AGENTS.core.md` regardless of classifier output. **Always loaded.**
2. Default class for ambiguous / multi-class / empty diff = `mixed` → all sidecars loaded (fail-closed).
3. **SessionStart stamp explicitly names the loaded class set** + a one-line operator hint: `[rules-loader] loaded: core+docs-only (N rules). If scope shifts, run: LOADER_FAIL_CLOSED=1 bash .claude/hooks/session-rules-loader.sh < <(echo '{}')`. Operator-side discipline is the load-bearing mid-session safety affordance in v2.
4. Slim manifest (3 fields) at `.claude/.session-manifests/<session-id>.json` enables post-incident attribution.
5. Plan-time CPO sign-off + review-time `user-impact-reviewer` close the loop. The pivot-detector-drop decision is itself part of CPO sign-off — confirming that fail-closed + stamp + operator discipline meet the `single-user incident` threshold without per-tool-call latency.

## Research Reconciliation — Spec vs. Codebase

| Spec / Brainstorm Claim | Codebase Reality | Plan Response |
|---|---|---|
| Spec FR3: SessionStart hook reads `git diff --name-only origin/main...HEAD ∪ git status --porcelain` | Confirmed. `--ignore-submodules=all` recommended to avoid submodule noise. | Used in Phase 4 hook with explicit ignore flag. |
| Spec FR4: PreToolUse pivot detector | **Cut in v2.** | n/a — see Alternative Approaches. |
| Spec TR1: `[id]` tag continues to live in `AGENTS.md` (the index) | Confirmed. Linter `lint-rule-ids.py` line 27-28 hardcodes `SECTIONS = {Hard Rules, Workflow Gates, Code Quality, Review & Feedback, Passive Domain Routing, Communication}`. | Phase 3: extend SECTIONS with `Compliance Tier`. Sidecars use the same headings as their content (e.g., `AGENTS.docs.md` uses `## Code Quality`). |
| **Kieran P0-1: Hook from bare-repo root** | Confirmed gotcha. `git rev-parse --show-toplevel` from `$CLAUDE_PROJECT_DIR` (bare root) returns empty. Existing precedent: `worktree-write-guard.sh:25` uses `git rev-parse --git-common-dir` + path inspection. | Phase 4 hook uses `--git-common-dir` and inspects `cwd` field from envelope. Test case verifies bare-repo invocation. |
| Spec TR7: Linter cross-file pointer↔body 1:1 mapping | New code path needed. Linter's `lint(path, retired_ids)` is per-file today. | Phase 3 introduces `--index-file <path>` flag + cross-file ID-set + pointer↔body validation. Backward-compatible single-file mode kept. |
| Brainstorm: classifier seed at `plugins/soleur/skills/review/SKILL.md:65-96` | Actually lines 63-70 (binary code/non-code, no granularity). | Plan introduces 3-class taxonomy (`docs-only`, `code`, `infra`) inline in the loader hook. Review-skill classifier unchanged. |
| Brainstorm: 5 compliance rules tagged `[compliance-tier]` | All 5 rule IDs verified in current AGENTS.md. | Phase 1 adds tag verbatim. |
| **P0-3 (Kieran): core arithmetic infeasible** | **Empirically false.** Measured: 26 Hard Rules totalling 8,991 bytes (avg 346B, not the 600B cap). Plus 2 pdr + 3 cm + section overhead ≈ 10,500 bytes total. Comfortably under 15k. | 15k budget retained. Phase 1.7 self-consistency check still validates empirically before commit. |
| Spec TR8: Compound bytes-cap | `compound/SKILL.md` step 8 lines 196-216 hardcodes single-file `B = wc -c AGENTS.md`. | Phase 5 reframes thresholds to **always-loaded payload** (`B_ALWAYS = wc -c AGENTS.md AGENTS.core.md`). Registry total informational only. |
| Brainstorm: SessionStart fires on `startup`/`resume`/`clear`/`compact` | Confirmed via learning `2026-03-04-sessionstart-hook-api-contract.md`. NO SessionStart hook registered today. | Phase 4 first SessionStart registration. No conflict. |
| Spec FR6: 9-field manifest | **Slimmed in v2 to 3 fields:** `{timestamp, change_class, rule_ids_loaded}`. SOC 2 CC6.1/CC7.2 only need to demonstrate which rules were loaded. SHA hashes + session_id + pivot_events deferred. | Phase 4 inline jq write. |
| Plugin-loader visibility test | `plugins/soleur/test/components.test.ts` exists. Sidecars at repo root are out of scope (loader scans `plugins/soleur/{commands,skills,agents}/`). | Phase 2 includes regression run. |

No spec→codebase divergence requires plan pivot.

## Hypotheses

N/A — not a network-outage / SSH / handshake class plan.

## Files to Edit

- `AGENTS.md` — convert from full rule registry to thin pointer index. ~69 rules → one-line pointer per rule (`- <one-sentence-summary> [id: <slug>] [<enforcement-tag>] → AGENTS.<class>.md`). Section headings preserved verbatim. Each pointer ≤ 200 bytes. Target: ≤ 5,000 bytes.
- `scripts/lint-rule-ids.py` — add `--index-file <path>` flag (excluded from positional sidecar list when present). Add `Compliance Tier` to `SECTIONS`. Add cross-file mode: global ID set, pointer↔body 1:1 validation, removed-id diff aware of sibling sidecars. Backward-compat single-file mode preserved.
- `lefthook.yml` line 51-54 — extend `glob:` to include sidecar paths; update command to pass all sidecars.
- `.claude/settings.json` — add SessionStart registration with matchers `startup|resume|clear|compact`.
- `.claude/hooks/README.md` — document the new hook + operator commands.
- `.gitignore` — add `.claude/.session-manifests/`.
- `plugins/soleur/skills/compound/SKILL.md` step 8 (lines 196-216) — migrate to always-loaded-payload thresholds (`B_ALWAYS = wc -c AGENTS.md AGENTS.core.md`); fix shellcheck bug (Kieran P1-5: `grep -hc` doesn't sum across files; use `grep -h '^- ' ... | wc -l`).
- `plugins/soleur/AGENTS.md` — note sidecar architecture in directory-structure section.

## Files to Create

- `AGENTS.core.md` — always-loaded sidecar. Contains: all 26 `## Hard Rules`, all 5 `[compliance-tier]`-tagged rules (HR overlap), all 2 `pdr-*`, all 3 `cm-*`, **plus all `wg-*`** (workflow gates are session-universal — compound-before-commit, version-files, auto-merge-poll, session-start). Section headings: `## Hard Rules`, `## Workflow Gates`, `## Compliance Tier` (NEW), `## Passive Domain Routing`, `## Communication`. Target: ≤ 18,000 bytes (raised from 15k to accommodate `wg-*`; empirically ~10.5k base + ~5k workflow gates).
- `AGENTS.docs.md` — loaded for `docs-only` sessions. Contains rules whose violation only happens when editing markdown / Eleventy templates: `cq-eleventy-critical-css-screenshot-gate`, `cq-agents-md-tier-gate`, `cq-agents-md-why-single-line`. Estimated ~3-5 rules / ≤ 3,000 bytes.
- `AGENTS.rest.md` — loaded for `code` OR `infra` sessions. Contains all remaining Code Quality + Review & Feedback rules (TS/runtime/Postgres/test fixtures/regex/PR mechanics). Estimated ~12-15 rules / ≤ 7,000 bytes. **Cross-cutting rules duplicate body** (e.g., `cq-test-fixtures-synthesized-only` may appear in both `AGENTS.rest.md` and `AGENTS.docs.md` if it triggers in both contexts; tolerable ~150 bytes duplication).
- `tools/migration/classify-rules.sh` — one-shot script run during Phase 1. Prints proposed class assignments per rule + per-class byte sums + spot-check measurement (samples 5 recent merged PRs via `gh pr list --state merged --limit 30`, classifies each, reports per-class median bytes saved). Output written to `tools/migration/rule-classification.tsv` for reviewer audit. Also embeds the spot-check savings table into the PR description (no separate measurement script).
- `tools/migration/rule-classification.tsv` — TSV with columns `rule_id | section | proposed_class | rationale | byte_count | rule_text_first_50_chars`. Reviewer-facing artifact.
- `.claude/hooks/session-rules-loader.sh` — single SessionStart hook script. Inlined classifier regex (no shared lib). Inlined 3-line jq manifest write (no manifest-writer lib). Worktree-aware path resolution via `git rev-parse --git-common-dir` + envelope `cwd` (Kieran P0-1 fix).
- `.claude/hooks/session-rules-loader.test.sh` — bash test suite. ~11 test cases: 3 classifier (docs / code / infra / mixed), 1 idempotency (3-compaction parity), 1 worktree path resolution from bare-repo, 1 fail-closed on classifier error, 1 manifest 3-field schema, 4 linter cross-file (orphan pointer, orphan body, dup ID, legacy mode + removed-id diff sibling-aware). Linter tests can live alongside in `scripts/lint-rule-ids.test.sh`.

## Implementation Phases

### Phase 0 — Pre-flight

0.1. Run `gh issue view 3493 --json state` to confirm OPEN. Verify branch `feat-agents-md-change-class-loader` and worktree path.

0.2. Confirm `requires_cpo_signoff: true`. Record CPO sign-off comment on PR #3496 BEFORE `/work` Phase 1 begins, explicitly acknowledging the v2 simplification (pivot detector cut) still meets the `single-user incident` threshold via fail-closed + stamp + operator-side discipline.

0.3. Baseline measurement: `wc -c AGENTS.md` → 24,618. Capture in PR description.

(No separate `tools/measurement/sample-recent-prs.sh` — Phase 1 `classify-rules.sh` does the spot-check.)

### Phase 1 — Tag + classify + measure

1.1. Verify `[compliance-tier]` token doesn't already exist: `grep '\[compliance-tier\]' AGENTS*.md` should return 0 lines BEFORE this phase. Then add the tag to 5 rules. Use `grep -n '\[id: <slug>\]' AGENTS.md` per rule to find current line number (line numbers may have shifted since plan).

| Rule ID | Tag insertion |
|---|---|
| `hr-never-paste-secrets-via-bang-prefix` | After `[id: hr-never-paste-secrets-via-bang-prefix]` |
| `hr-menu-option-ack-not-prod-write-auth` | After `[id: hr-menu-option-ack-not-prod-write-auth]` |
| `hr-never-git-add-a-in-user-repo-agents` | After `[id: hr-never-git-add-a-in-user-repo-agents]` |
| `cq-pg-security-definer-search-path-pin-pg-temp` | After `[id: cq-pg-security-definer-search-path-pin-pg-temp]` |
| `hr-exhaust-all-automated-options-before` | After `[id: hr-exhaust-all-automated-options-before]` |

Tag form: `[compliance-tier]` (presence-only, no value).

1.2. Implement `tools/migration/classify-rules.sh`. Embedded class heuristics (single source of truth):

```bash
# Class taxonomy:
# - core:      Hard Rules + Workflow Gates + [compliance-tier] + pdr-* + cm-*
# - docs-only: Code Quality rules whose body matches eleventy/agents-md/markdown
# - rest:      everything else (CQ runtime/TS/React/Postgres + Review & Feedback)
```

For each rule (under one of the 6 SECTIONS), output: `rule_id | section | proposed_class | rationale | byte_count | first_50_chars` to TSV.

Plus a spot-check section: sample 5 recent merged PRs via `gh pr list --base main --state merged --limit 30 --json number,files`, classify each, report per-class predicted load size.

Embed the TSV's per-class byte sum + spot-check median in the PR description so a reviewer can audit.

1.3. **Self-consistency gate.** From the TSV, verify:
- `sum(core_bytes) ≤ 18000`
- `sum(docs_bytes) + sum(rest_bytes) ≤ 12000`
- `sum(all_bytes) ∈ [22000, 28000]` (within 5% of original 24,618 ± rule overhead from new pointer lines)

If `core > 18k`, redistribute. Default first cut: demote `wg-when-a-test-runner-crashes-segfault-oom` and `wg-when-tests-fail-and-are-confirmed-pre` from core to `rest` (they're code/test session-specific).

1.4. Verify globs against repo state per `hr-when-a-plan-specifies-relative-paths-e-g`:

```bash
git ls-files | grep -E '\.tf$' | head -3                  # must return ≥1
git ls-files | grep -E '^apps/[^/]+/infra/' | head -3     # must return ≥1
git ls-files | grep -E '\.github/workflows/' | head -3    # must return ≥1
```

### Phase 2 — Sidecar split + index rewrite

2.1. Create `AGENTS.core.md` with section headings `## Hard Rules`, `## Workflow Gates`, `## Compliance Tier`, `## Passive Domain Routing`, `## Communication`. Copy bodies verbatim from current `AGENTS.md`.

2.2. Create `AGENTS.docs.md` and `AGENTS.rest.md`. Section headings: subset of the linter's SECTIONS (typically `## Code Quality` and `## Review & Feedback`).

2.3. **Cross-cutting rules:** if a rule applies to multiple classes, **duplicate the body in each relevant sidecar**. The pointer in the index points to ONE canonical sidecar (lexicographic order: docs < rest). The duplicate body is byte-budget tax (~150 bytes per duplicate); v1 accepts up to ~500 bytes total duplication. Future PR can introduce a `[classes:]` linter-enforced multi-location form if needed.

2.4. Rewrite `AGENTS.md` as the thin pointer index. Each rule:

```
- <one-sentence summary> [id: <slug>] [<enforcement-tags-preserved>] → AGENTS.<class>.md
```

Top-of-file paragraph (≤ 500 bytes):

> This file is a thin pointer index. Each rule's full body lives in a class-tagged sidecar (`AGENTS.core.md` always-loaded; `AGENTS.docs.md` for docs-only sessions; `AGENTS.rest.md` for code/infra sessions). The `SessionStart` hook at `.claude/hooks/session-rules-loader.sh` injects the relevant sidecars per session change-class. Default for ambiguous/multi-class diff = `mixed` → all sidecars loaded (fail-closed). See `knowledge-base/project/specs/feat-agents-md-change-class-loader/spec.md`.

2.5. **Plugin-loader visibility regression test.** Run `bun test plugins/soleur/test/components.test.ts` BEFORE and AFTER sidecar creation. Both must pass.

### Phase 3 — Linter migration

3.1. Extend `scripts/lint-rule-ids.py`:

- Add `--index-file <path>` argparse flag. When present, the file is excluded from positional sidecar list (or merged sensibly if duplicated — fix Kieran P1-1 explicitly: dedupe by realpath).
- Add `Compliance Tier` to `SECTIONS`.
- Refactor `lint(path, retired_ids)` → `lint_union(paths, index_path, retired_ids)`. New behavior:
  - Build `ids_by_path: dict[str, list[Path]]` across all paths.
  - For each ID, assert exactly one body location (in some sidecar) — duplicate bodies require a `[duplicate-of: <slug>]` tag on every duplicate (v1 enforcement: simply allow duplicates if their `[id]` matches and section headings match across files; the SessionStart hook concatenates sidecars so the agent sees one body — multiple is OK in prompt-space).
  - For each pointer in the index file, assert a matching body in some sidecar.
  - Removed-id diff aware of siblings: an ID present in `git show HEAD:AGENTS.md` is NOT "removed" if found in any working-copy `AGENTS*.md`.

3.2. Update `lefthook.yml`:

```yaml
glob:
  - "AGENTS.md"
  - "AGENTS.*.md"
  - "scripts/retired-rule-ids.txt"
run: python3 scripts/lint-rule-ids.py --retired-file scripts/retired-rule-ids.txt --index-file AGENTS.md AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md
```

3.3. Linter unit tests (in `scripts/lint-rule-ids.test.sh` if absent — verify path: `find . -name 'lint-rule-ids.test.*'` at /work):

- Pointer in index without matching body → fail.
- Body in sidecar without pointer in index → fail.
- ID duplicated across two sidecars (without explicit duplicate marker) → pass at v1 (tolerant — body duplication is acceptable cross-cutting strategy).
- Removed-id false-positive: HEAD has rule in AGENTS.md; working copy moved to AGENTS.core.md → pass.
- Legacy single-file mode: `python3 scripts/lint-rule-ids.py AGENTS.md` (no `--index-file`) still works for the index-only case.

### Phase 4 — SessionStart hook (the core feature)

4.1. Implement `.claude/hooks/session-rules-loader.sh`:

```bash
#!/usr/bin/env bash
# SessionStart hook (matchers: startup|resume|clear|compact).
# Classifies the session's change set; injects matching AGENTS.*.md sidecars
# via hookSpecificOutput.additionalContext.
#
# Source: AGENTS.md compliance-tier rules, spec FR3-FR6, learning
# 2026-03-04-sessionstart-hook-api-contract.md.
set -euo pipefail

# Worktree-aware path resolution (fixes Kieran P0-1).
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')

# When invoked from $CLAUDE_PROJECT_DIR (bare repo root), --show-toplevel fails.
# Use --git-common-dir + envelope.cwd like worktree-write-guard.sh.
if [[ -n "$CWD" && -d "$CWD" ]]; then
  REPO_ROOT="$CWD"
elif command -v git >/dev/null 2>&1; then
  COMMON_DIR=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || echo "")
  REPO_ROOT="${COMMON_DIR%/.git}"
fi
REPO_ROOT="${REPO_ROOT:-$(pwd)}"

# Compute change set (committed-on-branch ∪ working-tree).
CHANGES=$(
  {
    git -C "$REPO_ROOT" diff --name-only origin/main...HEAD --ignore-submodules=all 2>/dev/null || true
    git -C "$REPO_ROOT" status --porcelain --ignore-submodules=all 2>/dev/null | awk '{ print $2 }' || true
  } | sort -u
)

# Classify (inline regex — no shared library).
CLASSES="core"
DOCS_RE='\.(md|markdown|txt|njk|html)$|^\.github/.*\.md$'
CODE_RE='\.(ts|tsx|js|jsx|py|go|rs|swift|kt|java|c|cpp|cs|php|sh|bash|zsh|rb)$'
INFRA_RE='\.tf$|^apps/[^/]+/infra/|\.github/workflows/|/?Dockerfile|/migrations/.*\.sql$'

HAS_DOCS=0; HAS_CODE=0; HAS_INFRA=0
while IFS= read -r path; do
  [[ -z "$path" ]] && continue
  [[ "$path" =~ $DOCS_RE  ]] && HAS_DOCS=1
  [[ "$path" =~ $CODE_RE  ]] && HAS_CODE=1
  [[ "$path" =~ $INFRA_RE ]] && HAS_INFRA=1
done <<< "$CHANGES"

# Empty diff → mixed (fail-closed).
if [[ -z "$CHANGES" ]]; then
  CLASSES="core docs-only rest"
elif [[ "${LOADER_FAIL_CLOSED:-}" == "1" ]]; then
  CLASSES="core docs-only rest"
elif (( HAS_CODE + HAS_INFRA + HAS_DOCS > 1 )); then
  CLASSES="core docs-only rest"  # mixed
elif (( HAS_DOCS == 1 )); then
  CLASSES="core docs-only"
elif (( HAS_CODE == 1 || HAS_INFRA == 1 )); then
  CLASSES="core rest"
fi

# Concatenate sidecars.
CONTEXT=""
for class in $CLASSES; do
  case "$class" in
    core)      sidecar="$REPO_ROOT/AGENTS.core.md" ;;
    docs-only) sidecar="$REPO_ROOT/AGENTS.docs.md" ;;
    rest)      sidecar="$REPO_ROOT/AGENTS.rest.md" ;;
    *)         continue ;;
  esac
  if [[ -f "$sidecar" ]]; then
    CONTEXT+=$'\n\n---\n\n'
    CONTEXT+="$(<"$sidecar")"
  else
    # Fail-closed: missing sidecar means load everything.
    CONTEXT=""
    for sc in "$REPO_ROOT"/AGENTS.*.md; do
      [[ -f "$sc" ]] && CONTEXT+=$'\n\n---\n\n'$(<"$sc")
    done
    CLASSES="core docs-only rest (fail-safe: sidecar missing)"
    break
  fi
done

# Compose stamp.
RULE_COUNT=$(printf '%s' "$CONTEXT" | grep -cE '^- .*\[id: ' || true)
TOTAL_RULES=$(grep -hcE '^- .*\[id: ' "$REPO_ROOT"/AGENTS*.md 2>/dev/null | paste -sd+ | bc 2>/dev/null || echo 0)
STAMP="[rules-loader] loaded: ${CLASSES// /+} ($RULE_COUNT of $TOTAL_RULES rules)"
HINT="[rules-loader] If scope shifts mid-session, run: LOADER_FAIL_CLOSED=1 bash .claude/hooks/session-rules-loader.sh < <(echo '{\"cwd\":\"$REPO_ROOT\"}')"

# Slim manifest (3 fields). Use session_id when available; fallback to timestamp.
MANIFEST_DIR="$REPO_ROOT/.claude/.session-manifests"
mkdir -p "$MANIFEST_DIR"
TS=$(date -u +%Y-%m-%dT%H-%M-%SZ)
KEY="${SESSION_ID:-$TS}"
MANIFEST="$MANIFEST_DIR/${KEY}.json"
RULE_IDS=$(printf '%s' "$CONTEXT" | grep -oE '\[id: [a-z0-9-]+\]' | sort -u | sed 's/\[id: //;s/\]//' | jq -Rsc 'split("\n") | map(select(length > 0))')
jq -nc --arg ts "$TS" --arg cls "$CLASSES" --argjson ids "$RULE_IDS" '{
  timestamp: $ts,
  change_class: $cls,
  rule_ids_loaded: $ids
}' > "$MANIFEST"

# Emit additionalContext.
jq -nc --arg out "$STAMP"$'\n'"$HINT"$'\n'"[rules-loader] manifest: $MANIFEST"$'\n'"$CONTEXT" \
  '{ hookSpecificOutput: { additionalContext: $out } }'
exit 0
```

4.2. Register in `.claude/settings.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup|resume|clear|compact",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-rules-loader.sh"
          }
        ]
      }
    ]
  }
}
```

4.3. **Idempotency test (compaction re-entrancy)** — `session-rules-loader.test.sh` invokes the hook 3× with identical input; assert `rule_ids_loaded` parity across 3 manifest files.

4.4. **Bare-repo path resolution test** — invoke hook with `cwd` field set to a worktree path AND with `git rev-parse --show-toplevel` failing (simulate bare repo via `GIT_DIR` env trick); assert classifier still produces a non-`mixed` class. Validates Kieran P0-1 fix.

4.5. **Stamp ≤ 200 bytes test** — assert stamp + hint lines fit a single console line each.

### Phase 5 — Compound bytes-cap migration

5.1. Edit `plugins/soleur/skills/compound/SKILL.md` step 8. Replace:

```bash
B=$(wc -c < AGENTS.md)
A=$(grep -c '^- ' AGENTS.md)
L=$(grep '^- ' AGENTS.md | awk '{print length}' | sort -n | tail -1)
```

with (Kieran P1-5 shellcheck fix applied):

```bash
B_INDEX=$(wc -c < AGENTS.md)
B_CORE=$(wc -c < AGENTS.core.md 2>/dev/null || echo 0)
B_ALWAYS=$((B_INDEX + B_CORE))
B_TOTAL=$(cat AGENTS.md AGENTS.core.md AGENTS.docs.md AGENTS.rest.md 2>/dev/null | wc -c)
A=$(grep -h '^- ' AGENTS*.md 2>/dev/null | wc -l)
L=$(grep -h '^- ' AGENTS*.md 2>/dev/null | awk '{print length}' | sort -n | tail -1)
```

Output:
```
Rule budget:
  index (always-loaded):    B_INDEX bytes
  core (always-loaded):     B_CORE bytes
  always-loaded total:      B_ALWAYS bytes (target ≤18000 warn / ≤22000 critical)
  registry total:           B_TOTAL bytes / A rules (longest rule: L bytes)
  constitution.md:          C rules
```

Warnings (Kieran P1-4: thresholds apply to always-loaded payload, not registry total):
- `B_ALWAYS > 18000` → WARNING
- `B_ALWAYS > 22000` → CRITICAL (harness performance degradation)
- `L > 600` → WARNING per `cq-agents-md-why-single-line`

Registry total info-only.

5.2. Update rule body of `cq-agents-md-why-single-line` in `AGENTS.core.md`:

> AGENTS registry rules cap at ~600 bytes; `**Why:**` is one sentence → PR/learning [id: cq-agents-md-why-single-line] [skill-enforced: compound step 8]. The registry loads via SessionStart class-aware loader (`AGENTS.core.md` + index always; sidecars per change-class). Targets: always-loaded payload ≤18k warn / ≤22k critical. Rule count advisory. To retire: see `cq-rule-ids-are-immutable`.

### Phase 6 — Tests + docs + validation

6.1. Implement test suite (~11 cases):
- 4 classifier (`docs-only`, `code`, `infra`, `mixed`)
- 1 idempotency (3-compaction parity)
- 1 worktree path resolution from bare-repo (Kieran P0-1)
- 1 fail-closed on missing sidecar
- 1 manifest 3-field schema
- 4 linter cross-file (orphan pointer, orphan body, removed-id sibling-aware, legacy single-file mode)

All tests are `.test.sh` per `bash scripts/test-all.sh` convention.

6.2. Update `.claude/hooks/README.md`:

```markdown
## Change-class loader (#3493)

The `session-rules-loader.sh` SessionStart hook implements change-class-aware
AGENTS.md loading. See spec at
`knowledge-base/project/specs/feat-agents-md-change-class-loader/spec.md`.

### Operator commands

- View what's loaded for the active session:
  `cat .claude/.session-manifests/$(ls -t .claude/.session-manifests/ | head -1)`
- Force full re-load (e.g., when scope shifts mid-session):
  `LOADER_FAIL_CLOSED=1 bash .claude/hooks/session-rules-loader.sh < <(echo '{"cwd":"'"$PWD"'"}')`

### Default class

Empty diff (fresh worktree, on main, no uncommitted) → mixed → all sidecars
loaded (fail-closed). Multi-class diff → mixed → all sidecars loaded.
```

6.3. Update `plugins/soleur/AGENTS.md` directory-structure section to note sidecar files at repo root are not plugin components.

6.4. Re-run measurement spot-check from Phase 1 against the SHIPPED loader. Confirm Phase 1 baseline holds. Capture in PR description final.

6.5. **Compaction re-entrancy live test:** in this PR's review session, deliberately trigger 3 compactions (`/compact` 3×). Compare 3 manifest files' `rule_ids_loaded` arrays — must be identical sets.

6.6. Add learning at `knowledge-base/project/learnings/<implementation-date>-agents-md-change-class-loader-measured-savings.md` (filename derived at write-time per AGENTS.md sharp edge — DO NOT prescribe specific date in tasks.md):
- Per-class savings measured against Phase 1 baseline.
- Classifier accuracy on the 5-PR spot-check.
- Edge cases hit during implementation.
- Telemetry blind-spot acknowledgment (54 prompt-only rules don't self-report; manifest cross-reference is post-mortem-only).
- Pivot detector cut rationale + observed mid-session pivot frequency during this PR's own sessions (operator-side discipline validation).

6.7. PR description final updates: measured savings table, manifest reference `<details>` block, CPO sign-off recorded, `Closes #3493` on its own line, semver label `semver:minor`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **`AGENTS.md` reduced to pointer-index form** — `wc -c AGENTS.md ≤ 5000`. Each rule one pointer line ≤ 200 bytes.
- [ ] **`AGENTS.core.md` always-loaded budget** — `wc -c AGENTS.core.md ≤ 18000`. Contains all 26 Hard Rules + 5 `[compliance-tier]` + 2 `pdr-*` + 3 `cm-*` + all `wg-*`.
- [ ] **`AGENTS.docs.md` and `AGENTS.rest.md` exist** with rules from non-core sections.
- [ ] **5 prompt-only compliance rules tagged** — `grep -c '\[compliance-tier\]' AGENTS.core.md` = 5.
- [ ] **`scripts/lint-rule-ids.py --index-file AGENTS.md AGENTS*.md` passes** with `--retired-file scripts/retired-rule-ids.txt`.
- [ ] **lefthook updated** — `glob:` includes sidecar paths; commit triggers union scan.
- [ ] **`.claude/settings.json` registers SessionStart** with matchers `startup|resume|clear|compact`.
- [ ] **`.claude/hooks/session-rules-loader.sh` exists, executable, shellcheck-clean** (or shellcheck issues documented).
- [ ] **`.gitignore` includes `.claude/.session-manifests/`**.
- [ ] **All hook + linter tests pass** — `bash .claude/hooks/session-rules-loader.test.sh`, `bash scripts/lint-rule-ids.test.sh`.
- [ ] **`bun test plugins/soleur/test/components.test.ts` passes** — sidecars not discovered as plugin components.
- [ ] **`bash scripts/test-all.sh` passes** end-to-end.
- [ ] **Compound skill step 8 migrated** — `B_ALWAYS = wc -c AGENTS.md AGENTS.core.md`; thresholds 18k warn / 22k critical applied to always-loaded payload only.
- [ ] **`cq-agents-md-why-single-line` body updated** (in `AGENTS.core.md`) to reflect new architecture.
- [ ] **Compaction idempotency test passes** — 3 successive `compact` invocations produce identical `rule_ids_loaded`.
- [ ] **Bare-repo path resolution test passes** (Kieran P0-1).
- [ ] **Always-loaded payload shrank** — `wc -c AGENTS.md AGENTS.core.md | tail -1` < 24,618 (current single-file size).
- [ ] **Multi-agent review (`/soleur:review`) all-green** including conditional `user-impact-reviewer`.
- [ ] **CPO sign-off comment recorded on PR #3496** — explicitly acknowledging pivot-detector cut still meets `single-user incident` threshold.
- [ ] **PR description includes `Closes #3493`** on its own line.
- [ ] **Semver label set:** `semver:minor`.

### Post-merge (operator)

- [ ] **SessionStart hook fires in next fresh session** — `ls -la .claude/.session-manifests/` shows new manifest within 30 seconds of session start.
- [ ] **Stamp visible** in next session's console output: `[rules-loader] loaded: core+...` line present.
- [ ] **Operator escape hatch verified** — `LOADER_FAIL_CLOSED=1 bash .claude/hooks/session-rules-loader.sh < <(echo '{"cwd":"'"$PWD"'"}')` produces a manifest with `change_class = "core docs-only rest"`.
- [ ] **`gh pr view 3493 --json state` shows CLOSED**, milestone `Phase 4: Validate + Scale`, no `deferred-scope-out` label.
- [ ] **Roadmap.md `Current State` Phase 4 row updated** per `wg-when-moving-github-issues-between` (open count -1).
- [ ] **Learning file added** at `knowledge-base/project/learnings/<date>-agents-md-change-class-loader-measured-savings.md`.
- [ ] **Lefthook still triggers linter** — modify a sidecar rule body, attempt commit, confirm linter runs.

## Test Strategy

Per AGENTS.md sharp edge: bash `.test.sh` convention verified at `.claude/hooks/security_reminder_hook.test.sh`. Runner `bash scripts/test-all.sh` discovers tests by directory walk. Python linter tests use bash that invokes `python3 scripts/lint-rule-ids.py` with fixture dirs.

~11 test cases total:
- Phase 4 (loader): 7 cases — 4 classifier, 1 idempotency, 1 bare-repo path, 1 manifest schema
- Phase 3 (linter): 4 cases — orphan pointer, orphan body, removed-id sibling-aware, legacy mode

TDD gate per `cq-write-failing-tests-before`: write tests BEFORE implementation in Phase 4 and Phase 3. Phase 5 (compound markdown edit) is config-only → exempt.

## Risks

1. **Worktree path resolution edge cases** (Kieran P0-1). Hook envelope `cwd` may be missing or malformed; fallback to `git rev-parse --git-common-dir` may also fail in unusual setups. **Mitigation:** Phase 4.4 test exercises the bare-repo case directly. Last-resort fallback to `pwd` keeps the hook from crashing.

2. **Mid-session pivot relies on operator vigilance** — pivot detector cut. Operator must read the SessionStart stamp and remember to run `LOADER_FAIL_CLOSED=1 bash ...` if scope shifts. **Mitigation:** stamp explicitly names the loaded class set + hint line + escape command. Phase 6.6 learning records observed pivot frequency in this PR's own sessions; if the operator's discipline-based safety story doesn't hold, follow-up PR adds a lightweight PostToolUse warn (cheaper than the dropped PreToolUse pivot detector).

3. **`mixed` sessions zero out savings.** Per Phase 1 spot-check; if >50% of sessions are `mixed` (cross-class), savings are minimal but safety floor holds (full load = current behavior). **Mitigation:** Phase 1.2 spot-check measurement detects this BEFORE merge; if ratio is unfavorable, PR description adjusts the savings story (still ships for the safety/audit-trail benefit).

4. **Linter cross-file logic introduces new failure modes.** Orphan pointer, orphan body, removed-id false-positive. **Mitigation:** Phase 3.3 unit tests cover each. Backward-compat single-file mode preserved.

5. **`SessionStart` is new in this repo.** Contract per learning `2026-03-04-sessionstart-hook-api-contract.md`; if the hook contract has drifted, fall back to `UserPromptSubmit` matcher (also accepts `additionalContext`). **Mitigation:** Phase 4.1 manual verification in a fresh session.

6. **PreToolUse hook ordering remains stable.** Pivot detector cut means no new ordering. Existing hooks (`worktree-write-guard.sh`, `guardrails.sh`) untouched.

7. **Cross-cutting rule body duplication budget tax.** Up to ~500 bytes total. **Mitigation:** Phase 1.3 self-consistency check verifies sum stays within ±5% of original 24,618. If a rule is genuinely cross-cutting at 3+ sidecars, raise budget OR move to core.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty fails `deepen-plan` Phase 4.6 / `preflight` Check 6. Filled, threshold = `single-user incident`.
- `[compliance-tier]` is a NEW token. Phase 1.1 verifies non-collision via `grep '\[compliance-tier\]' AGENTS*.md` returns 0 lines BEFORE adding tags.
- Linter `SECTIONS` extension (`Compliance Tier`) is a Python source edit. Document inline.
- `.claude/.session-manifests/` is gitignored. Manifests reference operator-specific paths; check-in would pollute history.
- Operator escape hatch `LOADER_FAIL_CLOSED=1` accidentally exported in shell rc → every session full-loads. Document in README.
- The plan's globs (`apps/[^/]+/infra/`, `\.github/workflows/`, `\.tf$`) — Phase 1.4 verifies each matches ≥1 real file.
- Per AGENTS.md sharp edge "When a plan adds a new AGENTS.md rule": new tag `[compliance-tier]` adds zero rules / zero new IDs. Body edit to `cq-agents-md-why-single-line` adds ≤100 bytes. Total registry size after migration: roughly equivalent (rule bodies redistributed, ~few hundred bytes overhead from pointer lines + new section headings).
- Per AGENTS.md sharp edge "When a plan adds a validator, guard, linter that rejects a pattern": current pointer-form rules in AGENTS.md = 0. Post-migration: 69 pointer lines. Linter `--index-file` flag enables both forms.
- Per AGENTS.md sharp edge "When a plan changes a `MAX_*_SIZE`": this plan changes bytes-cap from `B = wc -c AGENTS.md` to `B_ALWAYS = wc -c AGENTS.md AGENTS.core.md`. Reader-side cap audit: `grep -rn "37000\|40000" plugins/soleur/skills/` returns hits in `compound/SKILL.md` only. No other readers.
- Per AGENTS.md sharp edge "When a plan splits a feature into a foundations PR + downstream wiring PR(s)": this plan is single-PR big-bang. All contract-declaring surfaces (sidecars, hook, linter, manifest) ship together. No split.
- Per AGENTS.md sharp edge "When a plan prescribes a `SCHEMA_VERSION` constant": v1 manifest is 3 fields. Schema versioning deferred until v2 needs it. Documented in Phase 4.1 inline.

## Open Code-Review Overlap

4 weak substring matches in `gh issue list --label code-review --state open` from initial scan:
- **#3392** (PR-B JWT/auth deferrals): substring match on "AGENTS.md" — different concern. **ACKNOWLEDGE.**
- **#3373** (SLOT_TRIGGER_INTEGRATION_TEST): substring match on "AGENTS.md" — different concern. **ACKNOWLEDGE.**
- **#3372** (tryLedgerDivergenceRecovery): substring match on "AGENTS.md" — different concern. **ACKNOWLEDGE.**
- **#3322** (extend lint-fixture-content.mjs glob): substring match on "lefthook.yml" — different lefthook entry (lint-fixture-content, not lint-rule-ids). **ACKNOWLEDGE.**

None to fold in. Recorded.

## Domain Review

**Domains relevant:** Engineering, Product, Legal (mandatory CPO+CLO+CTO trio carried forward from brainstorm `USER_BRAND_CRITICAL=true`). Marketing, Operations, Sales, Finance, Support not relevant.

### Engineering (CTO)

**Status:** reviewed (carry-forward from brainstorm Phase 0.5)

**Assessment:** Sidecar pointer is the only `lint-rule-ids.py`-compatible mechanism. Always-core: every Hard Rule + credential/auth/payment-tagged + pdr routing.

**v2 delta:** PreToolUse pivot detector cut at plan-review. CTO brainstorm assessment had it as load-bearing safety. Fail-closed `mixed` default + SessionStart stamp + operator-side `LOADER_FAIL_CLOSED=1` escape hatch are the v2 substitute. CTO sign-off requested at PR-time.

### Product (CPO)

**Status:** reviewed (carry-forward from brainstorm Phase 0.5)

**Assessment:** Operator UX requires load stamp. Fail-closed default is the safety floor.

**v2 delta:** CPO brainstorm assessment recommended PreToolUse pivot detector as "the load-bearing decision." v2 ships without it. **`requires_cpo_signoff: true`** — plan-time CPO comment on PR #3496 must explicitly acknowledge that operator-side discipline + stamp + escape hatch meet the `single-user incident` threshold without the pivot detector.

### Legal (CLO)

**Status:** reviewed (carry-forward from brainstorm Phase 0.5)

**Assessment:** `[compliance-tier]` tag is the single most important addition. Per-session manifest is SOC 2 CC6.1/CC7.2 evidence and must ship in v1.

**v2 delta:** manifest slimmed to 3 fields (`timestamp`, `change_class`, `rule_ids_loaded`). SOC 2 CC6.1/CC7.2 require demonstrating which rules were in context for a session — 3 fields suffice. SHA hashes + session_id + pivot_events deferred. CLO concerns met.

### Product/UX Gate

**Tier:** none

**Reasoning:** Internal CLI infrastructure. No new `components/*.tsx`, no `app/**/page.tsx`, no `app/**/layout.tsx`. Mechanical-escalation grep returns no UI-component matches. Tier `none`; gate skipped.

**Brainstorm-recommended specialists:** none.

## Alternative Approaches Considered

| Approach | Rejected Because | Tracking Issue |
|---|---|---|
| **PreToolUse pivot detector (v1 spec FR4 + previous plan v1)** | DHH + simplicity-reviewer convergence at plan-review: ~250 LOC + 50–200ms × 100 tool-calls/session latency tax for safety already covered by fail-closed `mixed` default + SessionStart stamp + operator-side `LOADER_FAIL_CLOSED=1` escape hatch. CTO/CPO/CLO brainstorm consensus to be re-acknowledged at plan-time CPO sign-off comment. | None — explicit plan-review decision. Re-evaluate post-v1 if observed pivot frequency warrants. |
| 5 sidecars (core/docs/code/infra/workflow) | YAGNI: 3 sidecars (core/docs/rest = code∪infra) yield same docs-only savings (the highest-frequency case). Code/infra rarely exist alone (most code PRs touch CI; most infra PRs touch docs). | None — explicit plan-review decision. |
| `[classes: a,b]` multi-class hint with linter enforcement | n=1 actual cross-cutting rule (`cq-test-fixtures-synthesized-only`). Body duplication (~150 bytes) is cheaper than linter syntax. | None. |
| `AGENTS.workflow.md` 5th sidecar | Self-consistency check shows core ≤18k holds with all `wg-*` in core (empirical: ~10.5k Hard Rules + ~5k workflow gates ≈ 15.5k). | None — decided in plan. |
| Per-session manifest with 9 fields (SHA hashes, session_id, sidecar_hashes, pivot_events, schema_version) | SOC 2 CC6.1/CC7.2 only need `{timestamp, change_class, rule_ids_loaded}`. v2 ships 3 fields. | TBD post-v1 if SOC 2 audit demands more. |
| Shared `classify-changes.sh` + `manifest-writer.sh` libraries | Single caller (loader hook only after pivot detector cut). Inline regex + 3-line jq is simpler. | None. |
| Separate `tools/measurement/sample-recent-prs.sh` script | Folded into `tools/migration/classify-rules.sh`. One script, one TSV. | None. |
| `/reload-rules` slash command operator escape hatch | Requires plugin/skill loading changes. Bash form `LOADER_FAIL_CLOSED=1 bash .claude/hooks/session-rules-loader.sh < <(echo ...)` is sufficient v1. | TBD if operator usage data shows demand. |
| Wedge-only (docs-only sidecar first) | Rule-relocation amortizes once. Operator confirmed big-bang at brainstorm. v2 simpler than v1, so big-bang remains correct shape. | None. |
| CLAUDE.md per-session rewrite | Worktree dirty-tree footgun. Conflicts with branch-safety hooks. | None — design rejected at brainstorm. |
| In-place classifier on AGENTS.md (no sidecars) | `lint-rule-ids.py` blocks `[id]` removal. Pointer pattern is the only compatible mechanism. | None — codebase constraint. |
| Telemetry expansion to make 78% prompt-only rules self-report | Out of scope v1 per spec TR9. | TBD post-v1. |

## References

- Issue #3493 — token-efficiency catalog (parent)
- Draft PR #3496 — implementation tracking
- Brainstorm: [knowledge-base/project/brainstorms/2026-05-09-agents-md-change-class-loader-brainstorm.md](../brainstorms/2026-05-09-agents-md-change-class-loader-brainstorm.md)
- Spec: [knowledge-base/project/specs/feat-agents-md-change-class-loader/spec.md](../specs/feat-agents-md-change-class-loader/spec.md)
- Compound learning: [knowledge-base/project/learnings/2026-05-09-brainstorm-skill-heuristics-substring-match-roadmap-skip-cmo-scope.md](../learnings/2026-05-09-brainstorm-skill-heuristics-substring-match-roadmap-skip-cmo-scope.md)
- Adjacent learnings:
  - `2026-04-23-agents-md-governance-measure-before-asserting.md`
  - `2026-04-21-agents-md-rule-retirement-deprecation-pattern.md`
  - `2026-04-18-agents-md-byte-budget-and-why-compression.md`
  - `2026-03-04-sessionstart-hook-api-contract.md`
  - `2026-03-28-pretooluse-hook-guard-ordering-matters.md`
  - `2026-02-25-lean-agents-md-gotchas-only.md`
- Linter source: `scripts/lint-rule-ids.py`
- Compound skill: `plugins/soleur/skills/compound/SKILL.md` lines 196-216
- Worktree-from-bare-repo precedent: `.claude/hooks/worktree-write-guard.sh:25` (P0-1 fix template)
- Plan-review convergence learning (this session): records DHH + simplicity feedback that drove v1→v2 cuts; will land in Phase 6.6 learning file.
