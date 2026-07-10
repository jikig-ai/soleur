#!/usr/bin/env bash
# Bootstrap: GitHub epic + child issues, worktree, commit, push, PR for Grok fidelity Phase A+B.
# Usage: bash scripts/grok-fidelity-bootstrap.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI required" >&2
  exit 1
fi

if ! command -v bun >/dev/null 2>&1; then
  echo "error: bun required for harness tests" >&2
  exit 1
fi

EPIC_BODY='Grok Build (#6314) loads the Soleur plugin, but `/go` sessions still diverge from Claude fidelity: wrong slash-command namespace, Skill/Task vs slash/spawn_subagent mismatch, and improvised workflows instead of registered routes.

## 7-layer fidelity model

Each layer closes a class of harness drift. Lower layers are prerequisites for higher layers.

1. **Onboarding** — plugin enable/trust, command-naming docs, valid `.grok/config.toml` (Phase A)
2. **Harness adapter** — `lib/harness.ts` maps Skill/Task to slash/spawn_subagent (Phase B)
3. **Routing contract** — `go.md` hardening + eval-harness Grok arm; never improvise (Phase C)
4. **Model tier map** — ADR-110 semantic tiers for both harnesses (Phase D / #6316)
5. **Agent discoverability** — 68 agents visible/spawnable in `grok inspect` (Phase E)
6. **Inspect CI** — `grok inspect` contract test in CI (Phase F)
7. **Golden-path eval** — end-to-end `/go` routing eval under Grok (Phase F)

## Children (recommended sequencing)

- **Phase A** — Grok onboarding: plugin enable/trust, command naming docs (`/go` not `/soleur:go`), CONTRIBUTING.md Grok section, `.grok/config.toml` drift fix per #6314 review
- **Phase B** — Harness adapter: `plugins/soleur/lib/harness.ts` + tests; `go.md` Step 2 harness section
- **Phase C** — `go.md` hardening + eval-harness Grok arm
- **Phase D** — ADR-110 implementation → #6316 (existing; do not duplicate)
- **Phase E** — 68 agents discoverable/spawnable in Grok (`grok inspect` shows 1 agent today)
- **Phase F** — Fidelity CI: `grok inspect` contract test + golden-path eval

## References

- #6314 — Grok Build project config (merged)
- #6316 — Harness semantic model-tier map (ADR-110)
- `knowledge-base/engineering/grok-onboarding.md`
- `plugins/soleur/lib/harness.ts`'

create_issue() {
  local title="$1"
  local body="$2"
  gh issue create \
    --repo jikig-ai/soleur \
    --title "$title" \
    --body "$body" \
    --label "tracking,type/feature,domain/engineering,priority/p2-medium"
}

echo "==> Creating epic..."
EPIC_URL=$(gh issue create \
  --repo jikig-ai/soleur \
  --title "epic: Grok Build fidelity — /go routes to Soleur workflows without improvisation" \
  --body "$EPIC_BODY" \
  --label "tracking,type/feature,domain/engineering,priority/p2-medium")
EPIC_NUM="${EPIC_URL##*/}"
echo "Epic: $EPIC_URL (#$EPIC_NUM)"

PHASE_A_BODY="Child of epic #$EPIC_NUM.

## Deliverables

- [ ] Fix \`.grok/config.toml\` — project config supports \`[plugins]\`, \`[mcp_servers]\`, \`[permission]\` only (no \`permission_mode\`, no \`[compat.claude]\` per #6314 review)
- [ ] CONTRIBUTING.md — Grok section with \`grok --trust\`, command naming (\`/go\` not \`/soleur:go\`)
- [ ] \`plugins/soleur/commands/help.md\` — harness-aware command listing
- [ ] \`knowledge-base/engineering/grok-onboarding.md\` — contributor brief

## Acceptance

- \`grok inspect\` from repo root lists soleur plugin
- Docs consistently use \`/go\` for Grok and \`/soleur:go\` for Claude"

PHASE_B_BODY="Child of epic #$EPIC_NUM.

## Deliverables

- [ ] \`plugins/soleur/lib/harness.ts\` — \`detectHarness()\`, \`formatSkillInvocation()\`, \`formatAgentSpawn()\`, \`invokeSkill()\`, \`spawnAgent()\`, \`routingInstructions()\`
- [ ] \`plugins/soleur/test/harness.test.ts\` — bun tests for claude + grok fixtures
- [ ] \`plugins/soleur/commands/go.md\` Step 2 — harness adapter section referencing lib/harness.ts

## Acceptance

- \`cd plugins/soleur && bun test test/harness.test.ts\` passes
- No vendor \`if (grok)\` branches outside harness.ts"

PHASE_C_BODY="Child of epic #$EPIC_NUM.

## Deliverables

- [ ] \`go.md\` routing hardening — eval-gate blocks, never-improvise enforcement
- [ ] eval-harness skill — Grok arm for golden routing assertions

## Acceptance

- Eval gate covers Grok slash-command routing semantics
- Regression test for \`/go\` → \`/one-shot\` style routes under Grok fixture"

PHASE_E_BODY="Child of epic #$EPIC_NUM.

## Problem

\`grok inspect\` today shows ~1 agent while Claude discovers 68 across domain directories.

## Deliverables

- [ ] Agent manifest / compat scan fixes so all \`plugins/soleur/agents/**\` definitions appear in Grok
- [ ] spawn_subagent can target domain agents (\`soleur:engineering:review:security-sentinel\`, etc.)

## Acceptance

- \`grok inspect\` agent count matches Claude plugin manifest count (±0)"

PHASE_F_BODY="Child of epic #$EPIC_NUM.

## Deliverables

- [ ] CI contract test — \`grok inspect\` output includes soleur plugin, skills, agents thresholds
- [ ] Golden-path eval — \`/go fix …\` routes to \`/one-shot\` under Grok harness fixture

## Acceptance

- Required check fails when inspect regresses
- Golden eval runs in plugins/soleur test suite"

echo "==> Creating child issues..."
A_URL=$(create_issue "feat(grok): Phase A — Grok onboarding docs + config.toml fidelity" "$PHASE_A_BODY")
B_URL=$(create_issue "feat(grok): Phase B — harness adapter (Skill/Task → slash/spawn_subagent)" "$PHASE_B_BODY")
C_URL=$(create_issue "feat(grok): Phase C — go.md hardening + eval-harness Grok arm" "$PHASE_C_BODY")
E_URL=$(create_issue "feat(grok): Phase E — 68 agents discoverable in grok inspect" "$PHASE_E_BODY")
F_URL=$(create_issue "feat(grok): Phase F — fidelity CI (grok inspect contract + golden eval)" "$PHASE_F_BODY")

A_NUM="${A_URL##*/}"
B_NUM="${B_URL##*/}"
C_NUM="${C_URL##*/}"
E_NUM="${E_URL##*/}"
F_NUM="${F_URL##*/}"

echo "Phase A: $A_URL"
echo "Phase B: $B_URL"
echo "Phase C: $C_URL"
echo "Phase D: #6316 (existing)"
echo "Phase E: $E_URL"
echo "Phase F: $F_URL"

# Link children in epic body
UPDATED_EPIC_BODY="${EPIC_BODY}

## Tracking

- $A_URL — Phase A
- $B_URL — Phase B
- $C_URL — Phase C
- https://github.com/jikig-ai/soleur/issues/6316 — Phase D (ADR-110)
- $E_URL — Phase E
- $F_URL — Phase F"

gh issue edit "$EPIC_NUM" --repo jikig-ai/soleur --body "$UPDATED_EPIC_BODY"

echo "==> Running harness tests..."
cd "$REPO_ROOT/plugins/soleur"
bun test test/harness.test.ts

echo "==> Creating worktree feat-grok-fidelity-ab..."
cd "$REPO_ROOT"
bash plugins/soleur/skills/git-worktree/scripts/worktree-manager.sh create feat-grok-fidelity-ab --yes

WT="$REPO_ROOT/.worktrees/feat-grok-fidelity-ab"
FILES=(
  .grok/config.toml
  CONTRIBUTING.md
  knowledge-base/engineering/grok-onboarding.md
  plugins/soleur/lib/harness.ts
  plugins/soleur/test/harness.test.ts
  plugins/soleur/commands/go.md
  plugins/soleur/commands/help.md
  scripts/grok-fidelity-bootstrap.sh
)

for f in "${FILES[@]}"; do
  if [[ -f "$REPO_ROOT/$f" ]]; then
    mkdir -p "$(dirname "$WT/$f")"
    cp "$REPO_ROOT/$f" "$WT/$f"
  fi
done

cd "$WT"
git add "${FILES[@]}"
git status

if git diff --cached --quiet; then
  echo "warn: no staged changes — files may already match worktree" >&2
else
  git commit -m "feat: Grok fidelity Phase A+B — onboarding docs + harness adapter"
fi

git push -u origin feat-grok-fidelity-ab

PR_URL=$(gh pr create \
  --repo jikig-ai/soleur \
  --head feat-grok-fidelity-ab \
  --title "feat: Grok fidelity Phase A+B — onboarding + harness adapter" \
  --body "## Changelog

- Added \`plugins/soleur/lib/harness.ts\` — maps Claude Skill/Task invocations to Grok slash commands + spawn_subagent
- Added harness unit tests (\`plugins/soleur/test/harness.test.ts\`)
- Expanded CONTRIBUTING.md and new \`knowledge-base/engineering/grok-onboarding.md\` — Grok uses \`/go\` not \`/soleur:go\`
- Updated \`help.md\` and \`go.md\` with harness-aware routing (never improvise)

Closes #$A_NUM
Closes #$B_NUM" \
  --label "semver:minor")

gh pr edit "${PR_URL##*/}" --repo jikig-ai/soleur --add-label "semver:minor" 2>/dev/null || true

echo ""
echo "=== Summary ==="
echo "Epic:     $EPIC_URL"
echo "Phase A:  $A_URL"
echo "Phase B:  $B_URL"
echo "Phase C:  $C_URL"
echo "Phase D:  https://github.com/jikig-ai/soleur/issues/6316"
echo "Phase E:  $E_URL"
echo "Phase F:  $F_URL"
echo "PR:       $PR_URL"
echo "Worktree: $WT"