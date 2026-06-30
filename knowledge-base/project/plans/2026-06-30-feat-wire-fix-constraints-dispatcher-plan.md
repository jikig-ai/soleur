---
feature: wire-fix-constraints-dispatcher
date: 2026-06-30
type: feature
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
parent_issue: 5765
closes: [5791]
adr: ADR-071 (amend — no new ADR)
spec: feat-constraint-gates-v2-buildable (branch) — FR1–FR6, TR1–TR4 (the #5791 subset)
brainstorm: knowledge-base/project/brainstorms/2026-06-30-constraint-gates-v2-buildable-brainstorm.md (on feat-constraint-gates-v2-buildable)
---

# Plan: Wire the `/soleur fix constraints` recovery comment-dispatcher (#5791)

## Overview

The shipped L1 constraint-gates suite (PR #5770, ADR-071) tells a stranded non-technical
founder to comment **`/soleur fix constraints`** to recover a tripped gate — but **no
`issue_comment` handler exists**. The only `issue_comment` workflows on main are
`cla.yml` / `cla-evidence.yml` / `merge-queue-cla-synthetics.yml` (all CLA). Commenting
`/soleur fix constraints` invokes nothing. The wording is currently — honestly — marked
"PLANNED (#5791), not yet wired" across the `.cjs` config, the shared runner, both
`constraint-gates.yml` copies, the three `constraint-scaffold` reference **templates**, the
skill `SKILL.md`, and ADR-071.

This plan builds the dispatcher and flips that wording to reflect that it now exists. **Scope
is #5791 only.** The sibling transitive-leak follow-up (#5777) and the deferred
body-validation gate (#5774) are separate later PRs — not built here (spec NG4: two separate
PRs by design).

**Deliverables:**

1. A new **repo-root** `.github/workflows/fix-constraints.yml` — the executable dispatcher
   (GitHub Actions only runs workflows under the repo-root `.github/workflows/`).
2. A new **emitter template** `fix-constraints-workflow.template` + `constraint-scaffold.sh`
   wiring, so a freshly-scaffolded **tenant** repo also gets the dispatcher. This is
   **load-bearing for honesty**, not gold-plating: flipping the wording in the
   `references/*.template` files (what tenants receive) to "dispatcher exists" **without
   emitting one** would re-commit the exact false-capability bug `#5791` exists to fix
   (`hr-verify-repo-capability-claim-before-assert`).
3. A wording sweep flipping "planned (#5791), not yet wired" → "wired" across all dogfooding
   artifacts, templates, the skill, and ADR-071; and "promotion blocked on #5791 and #5778"
   → "blocked on #5778" (promotion stays deferred — NG1).
4. Correct the **ADR-070 → ADR-071** mis-citation in issue #5791's body (post-merge `gh issue
   edit`). ADR-070 is a real, unrelated ADR (L3 phase-tool-scoping); the mis-citation is
   **only in the issue body** — do NOT touch the legitimate ADR-070 references in the repo.

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality (verified) | Plan response |
|---|---|---|
| FR6: "update any artifact that cites ADR-070 → ADR-071" | The only ADR-070 mis-citation pointing at the constraint-gates ADR is **issue #5791's body**. Repo `ADR-070` refs (`.claude/hooks/phase-surface-hint.sh`, ADR-070 file, two learnings, two plans/specs) are the **legit** L3 phase-tool-scoping ADR. | Correct only the issue body (post-merge `gh issue edit`). Explicitly exclude legit ADR-070 refs from any sweep. |
| "update the .cjs / shared runner / workflow templates / ADR-071 wording" | The wording lives in **two layers**: (a) the emitted dogfooding copies under `apps/web-platform/` + repo-root `.github/workflows/constraint-gates.yml`; (b) the **source templates** `plugins/soleur/skills/constraint-scaffold/references/{shared-runner,depcruise-config,constraint-gates-workflow}.template`. My first wording grep missed (b) because templates use the `.template` extension. | Sweep BOTH layers + `SKILL.md` + ADR-071. The template layer drives the tenant-emission requirement (deliverable 2). |
| "reuse cla.yml's wiring pattern" | `cla.yml` uses `contributor-assistant/github-action` under **`pull_request_target`** + `issue_comment` — NOT `claude-code-action`. The reusable bit is only the `issue_comment` + `if: github.event.issue.pull_request` **gating shape**. The `claude-code-action` wiring precedent is `.github/workflows/claude-code-review.yml`. | Reuse cla.yml's `issue_comment` gating shape + claude-code-review.yml's claude-code-action wiring (pinned SHA, `anthropic-preflight` gate, API-key, model pin, API-spend capture). Do NOT copy cla.yml's `pull_request_target` (TR1 forbids it). |
| TR2: `permissions: contents: write, pull-requests: write` **only** | **RESOLVED (deepen-plan):** BOTH in-repo claude-code-action users carry `id-token: write` — `claude-code-review.yml` (`id-token: write`) and `test-pretooluse-hooks.yml` (`contents: write` + `id-token: write`). It is the established convention. | Include `id-token: write` on the fix job. Documented rationale: OIDC **identity** federation, NOT repo-mutation scope — consistent with TR2's intent (TR2 bounds repo-write to contents+PR; id-token grants neither). AC1 allows it explicitly. |
| Dispatcher exists for the dogfooding repo once the repo-root workflow lands | `apps/web-platform/.github/workflows/constraint-gates.yml` is **non-executed** (GitHub runs only repo-root workflows); its error text reaches Soleur CI via the **executed** repo-root workflow running `apps/web-platform/scripts/constraint-gates.sh`. | Dogfooding wording flip is honest the moment the repo-root `fix-constraints.yml` exists. Tenant honesty needs deliverable 2. |

## User-Brand Impact

**If this lands broken, the user experiences:** a non-technical founder hits a tripped
constraint-gate, follows the CI error's instruction to comment `/soleur fix constraints`, and
— if the dispatcher is mis-wired (wrong `if`-guard, silent auth-fail, push to the wrong ref) —
either nothing happens (the original founder-deadlock persists) or, worse, the workflow pushes
to the wrong branch / runs on a fork it cannot push to and leaves a confusing failure.

**If this leaks, the user's workflow / repo write-access is exposed via:** a mis-scoped
`issue_comment` workflow that checks out and executes PR-head code with a write token is the
classic ACE (arbitrary-code-execution) exploit — a malicious comment or fork PR could push to
a protected branch or exfiltrate `secrets.ANTHROPIC_API_KEY` / `GITHUB_TOKEN`. The whole
security model (TR1 no `pull_request_target`, author-association gate, head==base guard,
exact-match command, env-passed strings) exists to close this vector.

**Brand-survival threshold:** single-user incident (founder-deadlock + ACE surface).

> CPO sign-off required at plan time before `/work` begins (carry forward from the brainstorm's
> `USER_BRAND_CRITICAL` framing — CPO/CLO/CTO weighed in at brainstorm). `user-impact-reviewer`
> and `security-sentinel` will be invoked at review time (review skill conditional-agent block).

## Canonical workflow design — `.github/workflows/fix-constraints.yml`

The reference shape the implementer encodes (every PR-derived string via `env:`, never inline
`${{ }}` in `run:` — TR4):

```yaml
name: fix-constraints (recovery dispatcher)

# issue_comment-triggered recovery for the L1 constraint-gates suite (ADR-071, #5791).
# SECURITY: plain issue_comment + explicit `gh pr checkout` — NOT pull_request_target.
# (write-token + PR-head checkout under pull_request_target is the classic ACE exploit, TR1.)

on:
  issue_comment:
    types: [created]

# NO top-level permissions block. Job-level `permissions:` REPLACES (not merges with) top-level
# in GitHub Actions (SEC-F6), so each job declares its own minimal set: preflight=contents:read,
# fix=contents:write+pull-requests:write+id-token:write, notify=pull-requests:write.

concurrency:
  group: fix-constraints-${{ github.event.issue.number }}
  cancel-in-progress: false               # TR3

jobs:
  preflight:
    # exact-match command (NOT contains), PR-comment-only, author-association gate
    if: >-
      github.event.issue.pull_request &&
      github.event.comment.body == '/soleur fix constraints' &&
      contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association)
    runs-on: ubuntu-latest
    timeout-minutes: 5
    permissions: { contents: read }
    outputs: { ok: ${{ steps.check.outputs.ok }} }
    steps:
      - uses: actions/checkout@<pin>          # default branch — NOT PR code (safe under issue_comment)
      - id: check
        # NOTE (SEC-F1): anthropic-preflight EXITS 1 (red) when ANTHROPIC_API_KEY is absent; it
        # only emits ok=false for billing-cap/credit-low/5xx/transient. Key-absent is NOT a clean
        # skip. The notify job (below) gives the founder feedback on every non-success path.
        uses: ./.github/actions/anthropic-preflight
        with: { anthropic-api-key: ${{ secrets.ANTHROPIC_API_KEY }} }

  fix:
    needs: preflight
    if: needs.preflight.outputs.ok == 'true'
    runs-on: ubuntu-latest
    timeout-minutes: 30                        # ~20 turns; comfortably above the 0.75 min/turn peer ratio
    permissions: { contents: write, pull-requests: write, id-token: write }   # SEC-F6: id-token lives HERE
    steps:
      - uses: actions/checkout@<pin>
        with:
          fetch-depth: 0
          persist-credentials: false        # SEC-P1: do NOT leave a push-capable token in git config
                                            # while the agent step runs untrusted-influenced PR content.
      - name: Verify commenter has write/admin permission   # SEC-P2: author_association ≠ push right
        id: perm
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          ACTOR: ${{ github.event.comment.user.login }}
        run: |
          set -euo pipefail
          p=$(gh api "repos/${GITHUB_REPOSITORY}/collaborators/${ACTOR}/permission" -q .permission)
          case "$p" in admin|write) echo "ok=true" >> "$GITHUB_OUTPUT" ;; *) echo "ok=false" >> "$GITHUB_OUTPUT" ;; esac
      - name: Resolve PR metadata + head==base guard   # FR3
        if: steps.perm.outputs.ok == 'true'
        id: pr
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          PR_NUMBER: ${{ github.event.issue.number }}
        run: |
          set -euo pipefail
          cross=$(gh pr view "$PR_NUMBER" --json isCrossRepository -q .isCrossRepository)
          headref=$(gh pr view "$PR_NUMBER" --json headRefName -q .headRefName)
          echo "cross=$cross" >> "$GITHUB_OUTPUT"
          echo "headref=$headref" >> "$GITHUB_OUTPUT"
      - name: Skip-and-explain on fork PR
        if: steps.pr.outputs.cross == 'true'
        env: { GH_TOKEN: ..., PR_NUMBER: ... }
        run: |
          gh pr comment "$PR_NUMBER" --body "Fork PRs can't be auto-fixed (GITHUB_TOKEN is read-only on fork heads). A maintainer must run \`constraint-scaffold\` locally and push."
          # exit 0 — not a failure
      - name: git identity                       # claude-code-action does NOT auto-config; sibling scheduled-*.yml precedent
        if: steps.pr.outputs.cross != 'true'
        run: git config user.name "soleur-ai[bot]"; git config user.email "<bot-noreply>"
      - name: Checkout the PR's OWN head ref      # FR4 — never base, never a side branch
        if: steps.pr.outputs.cross != 'true'
        env: { GH_TOKEN: ..., PR_NUMBER: ... }
        run: gh pr checkout "$PR_NUMBER"
      - name: Dispatch agent to fix the gate      # FR4 — fix the import OR --refresh-baseline
        if: steps.pr.outputs.cross != 'true'
        id: agent
        uses: anthropics/claude-code-action@ab8b1e6471c519c585ba17e8ecaccc9d83043541 # v1.0.101 (match sibling)
        with:
          anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}
          # model pin matches claude-code-review.yml / test-pretooluse-hooks.yml (do NOT drift).
          # allowedTools + max-turns mirror test-pretooluse-hooks.yml (the agentic-write precedent).
          claude_args: '--model claude-sonnet-4-6 --max-turns 20 --allowedTools Bash,Read,Write,Edit,Glob,Grep'
          prompt: |
            A constraint-gate tripped on this PR. Run apps/web-platform/scripts/constraint-gates.sh,
            read the failure, and recover per the agent-owns-gates model (constraint-scaffold SKILL.md):
            fix the offending import if it is a real client→server-secret leak, OR run
            constraint-scaffold.sh --refresh-baseline if it is a legitimate new cross-boundary import.
            Make the file edits. Do NOT push — the workflow owns commit+push.
      - name: Capture API spend                   # parity with claude-code-review.yml (hr-autonomous-loop-skill-api-budget-disclosure)
        if: steps.agent.outputs.execution_file != ''
        continue-on-error: true
        ...: bash scripts/extract-api-spend.sh ...
      - name: Re-run the gate to VERIFY the fix     # SEC-F3: assert the invariant, not "agent exited 0"
        if: steps.pr.outputs.cross != 'true'
        id: verify
        run: |
          set +e
          bash apps/web-platform/scripts/constraint-gates.sh
          echo "rc=$?" >> "$GITHUB_OUTPUT"
          # also record whether the agent produced any diff (F4: no-change ≠ fixed)
          if git diff --quiet && git diff --cached --quiet; then echo "changed=false" >> "$GITHUB_OUTPUT"; else echo "changed=true" >> "$GITHUB_OUTPUT"; fi
      - name: Commit + push to the head ref         # explicit; workflow owns the push target (FR4)
        if: steps.pr.outputs.cross != 'true' && steps.verify.outputs.changed == 'true' && steps.verify.outputs.rc == '0'
        id: push
        env:
          HEAD_REF: ${{ steps.pr.outputs.headref }}
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        run: |
          set -euo pipefail
          git add -A
          git commit -m "fix(constraint-gates): auto-recover tripped gate via /soleur fix constraints (#5791)"
          # SEC-P1: persist-credentials:false → push with an explicit, scoped credential, env-passed
          git push "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}" "HEAD:$HEAD_REF"
          echo "sha=$(git rev-parse HEAD)" >> "$GITHUB_OUTPUT"
      - name: Outcome comment (success/no-change/still-red)   # FR5 — deterministic from step outputs
        if: always() && steps.pr.outputs.cross != 'true' && steps.perm.outputs.ok == 'true'
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
          PR_NUMBER: ${{ github.event.issue.number }}
          CHANGED: ${{ steps.verify.outputs.changed }}
          RC: ${{ steps.verify.outputs.rc }}
          PUSHED_SHA: ${{ steps.push.outputs.sha }}
        run: |
          set -euo pipefail
          if   [ "$CHANGED" = 'true' ] && [ "$RC" = '0' ]; then body="Recovered: gate green, pushed $PUSHED_SHA."
          elif [ "$CHANGED" = 'false' ]; then body="Ran, but made no edits — the gate may be un-auto-fixable. See the failing rule in the run logs; a maintainer may need to act."
          else body="Attempted a fix but the gate is STILL red after re-running — not pushed. See run logs."; fi
          gh pr comment "$PR_NUMBER" --body "$body"

  # SEC-F2/F9: every non-success path that is NOT the intended-silent unauthorized/non-PR case
  # must still give the founder feedback — otherwise a billing-cap / key-absent / transient window
  # re-creates the exact #5791 deadlock. This always() job is the catch-all.
  notify-on-skip:
    needs: [preflight, fix]
    if: >-
      always() &&
      github.event.issue.pull_request &&
      github.event.comment.body == '/soleur fix constraints' &&
      contains(fromJSON('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association) &&
      needs.fix.result != 'success'
    runs-on: ubuntu-latest
    permissions: { pull-requests: write }
    steps:
      - name: Fallback feedback comment
        env: { GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}, PR_NUMBER: ${{ github.event.issue.number }} }
        run: gh pr comment "$PR_NUMBER" --body "Auto-recovery is temporarily unavailable (API billing/transient, missing key, fork PR, or insufficient permission). Re-comment later, or a maintainer can run \`constraint-scaffold\` locally. See the workflow run for detail."
```

Notes: the `notify-on-skip` `if` re-checks the PR/command/author gate so it stays **silent** for the
intended-silent paths (unauthorized commenter, non-PR comment, non-matching command) — it fires only
when an **authorized** founder's valid command did not reach a successful fix.

Design notes the implementer must honor:
- **Three-job split (preflight / fix / notify-on-skip).** The preflight `anthropic-preflight` does
  NOT no-op on a missing key — it **exits 1 (red)** (SEC-F1); it only emits `ok=false` for
  billing-cap / credit-low / 5xx / transient. So `fix` is skipped on every non-ok preflight, and
  the `always()` **notify-on-skip** job (SEC-F2) is what gives the founder feedback on every
  non-success path — otherwise a key/billing/transient window silently re-creates the #5791
  deadlock. notify-on-skip re-checks the PR+command+author gate so it stays silent for the
  intended-silent paths only.
- **Verify the invariant, not the proxy (SEC-F3).** claude-code-action exits 0 even when the agent
  gives up. After the agent edits, RE-RUN `constraint-gates.sh`; push + report "recovered" ONLY when
  the gate is actually green AND a diff exists. No-change (F4) and still-red get distinct, honest
  outcome comments — never a false "succeeded."
- **Credential isolation (SEC-P1).** `actions/checkout` with `persist-credentials: false` so the
  agent step has no ambient push token while it runs attacker-influenceable PR-head content; the
  dedicated push step uses an explicit env-passed `x-access-token` credential. Push target is the PR
  head ref and nothing else (FR4); rely on branch protection for `main`.
- **Permission gate, not relationship gate (SEC-P2).** `author_association` is a relationship, not a
  push right — a read-only COLLABORATOR/MEMBER satisfies it. Add a `gh api …/collaborators/$ACTOR/permission`
  check (must be `admin`/`write`) before the fix proceeds.
- **No bot-comment loop:** triple-protected — `GITHUB_TOKEN`-authored comments don't recursively
  trigger workflows; the outcome body never equals the exact trigger string; the bot's
  `author_association` also fails the gate. Verified non-loop (Test Scenarios).
- **Model pin is mirrored, not chosen:** `claude-sonnet-4-6` + action SHA `ab8b1e6…` copied verbatim
  from in-repo `claude-code-review.yml` (CI-validated). Pin freshness is owned by
  `model-launch-review`, not this PR — do NOT substitute a model id from memory.
- **F5 — display the recovery command WITHOUT backticks.** The CI error messages must render the
  exact command as a bare, copy-pasteable line (`To recover, comment: /soleur fix constraints`), NOT
  inside backticks — a founder copying `` `/soleur fix constraints` `` sends a non-matching string and
  hits a silent skip (the #5791 deadlock again). Apply during the Phase 3 wording sweep.

## Implementation Phases

### Phase 0 — Preconditions (verify, no code)
0.1 RESOLVED at deepen-plan: include `id-token: write` (both in-repo claude-code-action users carry
it; OIDC identity, not repo-write — TR2-intent consistent). No further verification needed; confirm
the action still accepts API-key mode at /work (it does in both sibling workflows).
0.2 Confirm `.github/actions/anthropic-preflight/action.yml` output contract (`ok`) and
`scripts/extract-api-spend.sh` arg shape (already confirmed present).
0.3 Re-confirm no `.github/workflows/fix-constraints.yml` or `references/fix-constraints*.template`
exists (clean create).

### Phase 1 — The dispatcher (repo-root, dogfooding)
1.1 Create `.github/workflows/fix-constraints.yml` per the canonical design above.
1.2 Lint: `actionlint` on the YAML; `bash -c '<extracted run: snippets>'` for embedded shell
(NOT `bash -n` on the .yml — parses the YAML header as bash; see Sharp Edges).

### Phase 2 — Tenant emission (skill template + emitter)
2.1 Add `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-workflow.template`
(the same design, `__TARGET_DIR__`-parameterized for the runner path).
2.2 Wire `constraint-scaffold.sh`: define `FIXWORKFLOW="$TARGET/.github/workflows/fix-constraints.yml"`,
add it to the non-destructive refuse-if-exists loop, `sed __TARGET_DIR__` emit, extend the `log:`
line and the worktree-copy path (line ~108).
2.3 Add a self-test (`test/`) asserting the emitter writes `fix-constraints.yml` and refuses to
overwrite an existing one (mirror the existing `boundary.test.sh` non-destructive assertions).

### Phase 3 — Wording sweep (flip "planned/not yet wired" → "wired"; "blocked on #5791 and #5778" → "blocked on #5778")
Edit every site enumerated in **Files to Edit** below. Keep the gate's "informational /
non-blocking" framing — promotion stays deferred (NG1; still blocked on #5778). EXCLUDE the
historical learnings file (point-in-time record).

### Phase 4 — ADR-071 amend + C4 confirm
4.1 Amend ADR-071 lines 34–40: dispatcher is now **wired** (`.github/workflows/fix-constraints.yml`,
#5791); promotion-to-required now gated on **#5778 only**.
4.2 C4: read all three `.c4` files and confirm no model change (enumeration in
`## Architecture Decision`); fix any falsified description; no `.c4` edit expected.

### Phase 5 — Post-merge (operator/automatable)
5.1 `gh issue edit 5791 --body <corrected>` — flip ADR-070 → ADR-071 in the issue body (FR6).
Automatable via `gh` CLI — fold into `/ship` post-merge or a /work step; NOT operator-manual.
5.2 Do NOT promote the gate to a required check (NG1; #5778 still open).

## Files to Create

- `.github/workflows/fix-constraints.yml` — the executable dispatcher (repo-root).
- `plugins/soleur/skills/constraint-scaffold/references/fix-constraints-workflow.template` — tenant template.
- `plugins/soleur/skills/constraint-scaffold/test/<fix-constraints-emit>.test.sh` — emitter self-test.

## Files to Edit

**Dispatcher emission (skill):**
- `plugins/soleur/skills/constraint-scaffold/scripts/constraint-scaffold.sh` — emit + refuse-if-exists + worktree-copy + log.

**Wording sweep — emitted dogfooding copies:**
- `apps/web-platform/scripts/constraint-gates.sh` — header (L9–10) + 5 `::error::` messages (L38, 42, 79, 86, 88).
- `apps/web-platform/.dependency-cruiser.cjs` — header (L7–8).
- `apps/web-platform/.github/workflows/constraint-gates.yml` — comment (L9) [non-executed reference copy].
- `.github/workflows/constraint-gates.yml` — header comment (L10–11, L18).

**Wording sweep — source templates (what tenants receive):**
- `plugins/soleur/skills/constraint-scaffold/references/shared-runner.template` — header (L9–10) + 5 `::error::` (L38, 42, 79, 86, 88).
- `plugins/soleur/skills/constraint-scaffold/references/depcruise-config.template` — header (L7–8).
- `plugins/soleur/skills/constraint-scaffold/references/constraint-gates-workflow.template` — comment (L9).

**Wording sweep — skill + ADR:**
- `plugins/soleur/skills/constraint-scaffold/SKILL.md` — recovery model (L35–40), "What it emits" table (L68; add a fix-constraints.yml row).
- `knowledge-base/engineering/architecture/decisions/ADR-071-l1-constraint-gates.md` — Decision (L34–40).

**Explicitly EXCLUDED (historical record — do NOT edit):**
- `knowledge-base/project/learnings/2026-06-30-constraint-scaffold-verify-every-assumed-capability-at-brand-survival-threshold.md`
- Legit `ADR-070` refs (`.claude/hooks/phase-surface-hint.sh`, `ADR-070-*.md`, the two plans/specs, two learnings) — unrelated L3 ADR.

## Acceptance Criteria

### Pre-merge (PR)
- **AC1** `.github/workflows/fix-constraints.yml` exists; `actionlint` passes; `on: issue_comment: [created]`; the fix job's `permissions:` is exactly `contents: write` + `pull-requests: write` + `id-token: write` (id-token = OIDC identity per TR2 reconciliation; no other repo-write scope). The preflight job's `permissions:` is `contents: read`.
- **AC2** Job `if` is the exact conjunction: `github.event.issue.pull_request` AND `github.event.comment.body == '/soleur fix constraints'` (exact `==`, not `contains`) AND `author_association` ∈ {OWNER,MEMBER,COLLABORATOR}. Grep-assert the literal `== '/soleur fix constraints'` and the `fromJSON('["OWNER","MEMBER","COLLABORATOR"]')` membership.
- **AC3** `grep -c 'pull_request_target' .github/workflows/fix-constraints.yml` returns **0** (TR1).
- **AC4** `concurrency.group == fix-constraints-${{ github.event.issue.number }}` and `cancel-in-progress: false` (TR3).
- **AC5** Every PR-derived value used inside a `run:` block is referenced via `env:` (no inline `${{ github.event.* }}` in any `run:`) — TR4. (Grep `run:` blocks for `${{` → only `${{ steps.* }}`/`${{ secrets.* }}` outputs allowed, no `github.event`.)
- **AC6** Head==base guard present: a `gh pr view … isCrossRepository` check that skips the push path and posts an explanatory comment when `true` (FR3).
- **AC7** Push target is the PR head ref (`git push origin HEAD:$HEAD_REF` with `HEAD_REF` from `gh pr view … headRefName` via env); no `git push` to base/any other ref anywhere in the file (FR4).
- **AC8** claude-code-action pinned to `ab8b1e6471c519c585ba17e8ecaccc9d83043541` with `claude_args` containing `--model claude-sonnet-4-6` — `diff` the pin+model against `claude-code-review.yml` (must match; no drift).
- **AC8b (SEC-P1)** `actions/checkout` sets `persist-credentials: false`; the push step uses an explicit env-passed credential (`x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}`); grep confirms no other `git push` target and no persisted-credential push.
- **AC8c (SEC-P2)** a commenter-permission step gates the fix on `gh api repos/.../collaborators/$ACTOR/permission` ∈ {admin,write} (actor via `env:`), in addition to the `author_association` if-guard.
- **AC8d (SEC-F3/F4)** the gate is RE-RUN (`constraint-gates.sh`) after the agent edit; the push + "recovered" outcome fire ONLY when the re-run rc==0 AND a diff exists; no-change and still-red each post a distinct, honest outcome comment (no false "succeeded").
- **AC8e (SEC-F2)** a `notify-on-skip` `always()` job (depends on preflight+fix) posts a fallback feedback comment when `needs.fix.result != 'success'` AND the PR+command+author gate passes; it stays SILENT for the intended-silent paths (unauthorized commenter / non-PR / non-matching command) — assert the gate is re-checked in its `if`.
- **AC8f (SEC-F5)** every recovery error message that names the command renders it as a bare, copy-pasteable line (e.g. `comment: /soleur fix constraints`), NOT inside backticks, across the swept runner/templates/workflows.
- **AC9** New `references/fix-constraints-workflow.template` exists; `constraint-scaffold.sh` emits it (refuse-if-exists), and the emitter self-test passes (`bash plugins/soleur/skills/constraint-scaffold/test/<emit>.test.sh`).
- **AC10** Wording flip complete: `grep -rn "not yet wired\|planned (#5791" <swept files>` returns **0** across all Files-to-Edit (emitted copies + templates + SKILL.md + ADR-071), AND the historical learnings file is **untouched** (`git diff --name-only` excludes it).
- **AC11** Promotion-blocker flip: `grep -rn "blocked on #5791" <swept files>` returns 0; remaining promotion-blocker references say `#5778` only.
- **AC12** No legit ADR-070 ref changed: `git diff` touches none of `.claude/hooks/phase-surface-hint.sh`, `ADR-070-*.md`, the two ADR-070 plans/specs.
- **AC13** ADR-071 Decision section states the dispatcher is wired (`.github/workflows/fix-constraints.yml`) and promotion gated on #5778 only.
- **AC14** `bash plugins/soleur/test/components.test.ts` (or the repo's test runner per `package.json scripts.test`) green; constraint-scaffold self-tests green.
- **AC15** PR body uses `Ref #5791` NOT `Closes #5791` (the ADR-070→ADR-071 issue-body correction is a post-merge step; `Closes` would auto-close before it runs). Issue closes in Phase 5.1 after the body edit.

### Post-merge (operator/automatable)
- **AC16** `gh issue edit 5791` applied: issue body cites ADR-071 (not ADR-070). Then `gh issue close 5791` (or it closes via the ship flow). Automatable via `gh` — not operator-manual.
- **AC17** Gate NOT promoted to a required branch-protection check (NG1 — still blocked on #5778). No branch-protection change in this PR.
- **AC18 (SEC-F8 — functional smoke; the workflow cannot run from the feature branch — `issue_comment` executes only the default-branch copy, so first real execution is post-merge).** On a scratch PR that trips the gate, comment the exact `/soleur fix constraints` → confirm the agent fix lands, the gate goes green, and a "recovered" outcome comment posts. Then confirm: (a) a near-miss/backticked command produces a notify-or-no-op as designed, (b) an unauthorized commenter is silently skipped, (c) a non-success path (e.g. un-fixable gate) posts the notify-on-skip fallback. Automatable via `gh pr create` + `gh pr comment` + `gh run watch`. Do NOT close #5791 until this smoke passes.

## Observability

```yaml
liveness_signal:
  what: every AUTHORIZED dispatch posts a PR comment — the fix job's outcome comment on the
        recovered/no-change/still-red paths, OR the notify-on-skip fallback on every non-success
        path (billing/transient/key-absent/fork/insufficient-permission). Intended-silent paths
        (unauthorized / non-PR / non-matching command) post nothing by design.
  cadence: event-driven (issue_comment) — no cron; an authorized dispatch that produced no PR comment is the failure signal.
  alert_target: GitHub Actions run list (Actions tab) + the PR thread.
  configured_in: .github/workflows/fix-constraints.yml (fix-job Outcome step + notify-on-skip job, both gated).
error_reporting:
  destination: GitHub Actions ::error:: annotations + reddened run + the FR5 PR comment on failure.
  fail_loud: true (the fix job reddens on push failure / agent non-zero; the outcome comment names the failure).
failure_modes:
  - { mode: agent could not auto-fix, detection: claude-code-action non-zero / no file changes, alert_route: outcome comment "failed — see logs" + red run }
  - { mode: push rejected (branch protection / race), detection: git push non-zero, alert_route: red run + outcome comment }
  - { mode: fork PR (head != base), detection: isCrossRepository == true, alert_route: explanatory comment, run exits 0 (by design) }
  - { mode: unauthorized commenter, detection: author_association if-guard, alert_route: job skipped silently (no leak that the command exists — intentional) }
logs:
  where: GitHub Actions run logs (per-run); API-spend artifact (90-day retention, parity with claude-code-review.yml).
  retention: Actions default; api-spend artifact 90 days.
discoverability_test:
  command: gh run list --workflow=fix-constraints.yml --limit 5    # NO ssh
  expected_output: the dispatch run with conclusion success/failure; the PR thread shows the outcome comment.
```

## Architecture Decision (ADR/C4)

**ADR:** No new ADR. This plan **implements** the recovery dispatcher ADR-071 already named as
"planned." ADR-071 is **amended** (Decision §, L34–40): the dispatcher is now wired; promotion
gated on #5778 only. The amend is part of the wording sweep (Phase 4.1), not a deferred issue.

**C4 views:** No `.c4` edit expected — confirmed by enumerating all three model files
(`model.c4`, `views.c4`, `spec.c4`):
- **External human actor** = the founder/commenter → `founder` actor already modeled (`model.c4:8`).
- **External system** = GitHub (the `issue_comment` event + `gh` API) → `github` already modeled
  (`model.c4:200`), with the `engine -> github "Git operations and CI"` edge (`model.c4:240`).
- **External system** = the Claude LLM (claude-code-action) → `anthropic` already modeled
  (`model.c4:196`), `engine -> anthropic` edge (`model.c4:239`); the same edge `claude-code-review.yml`
  already exercises. The `constraint-scaffold` component is modeled (`model.c4:138`).
- **Container / data-store touched:** none new. **Access relationship changed:** none.

No new actor, system, container, or access edge → "no C4 impact" is supported by the
enumeration above. (Phase 4.2 still reads all three files to fix any description the change
falsifies, then runs the C4 syntax/render tests.)

## Domain Review

**Domains relevant:** Engineering (carried forward from brainstorm `## Domain Assessments`).

### Engineering

**Status:** reviewed (brainstorm carry-forward — platform-strategist).
**Assessment:** Confirmed the build/defer ranking (#5791 → #5777 → defer #5774) and the
`issue_comment` security model (author_association gate, head==base guard, no
`pull_request_target`, push to PR head). This plan adds the tenant-emission honesty requirement
the brainstorm did not enumerate. CTO concerns reflected in Risks + Sharp Edges + the TR2/id-token
reconciliation. Re-review at PR time via `security-sentinel` + `user-impact-reviewer`
(single-user-incident threshold).

### Product/UX Gate

Not applicable. Files-to-Create/Edit contain no UI-surface paths (`.yml`, `.sh`, `.cjs`, `.md`,
`.template`); the mechanical UI-surface override does not fire. Product = NONE.

## GDPR / Compliance Gate

Assessed, skipped. No regulated-data surface (no schema/migration/auth/API-route/`.sql`). The
agent processes the founder's **own repo source code** via the **already-sanctioned** Anthropic
API edge (`claude-code-review.yml` precedent) — no new processing activity on third-party
personal data, no new sub-processor, no new data-distribution surface. Trigger (b) (single-user
threshold) noted; no Art. 30 / lawful-basis change. (Re-confirm at `/work` Phase 2.7 if the
diff drifts.)

## Infrastructure (IaC)

Skipped — no new infrastructure. Reuses the existing `secrets.ANTHROPIC_API_KEY` (already used
by `claude-code-review.yml`) and the ambient `GITHUB_TOKEN`. No new server, secret, vendor, DNS,
or persistent runtime process. The new file is CI workflow config, not provisioned infra.

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` returns no issue whose body references
`constraint-gates` / `fix-constraints` / `constraint-scaffold` / `5791`.

## Test Scenarios

- **T1 (auth gate):** comment `/soleur fix constraints` from a non-collaborator (`author_association`
  = NONE/CONTRIBUTOR) → job skipped, no run side-effects. (Cannot fully e2e in CI pre-merge; assert
  via the `if`-guard grep + `actionlint`.)
- **T2 (exact match):** comment `please /soleur fix constraints now` (substring) → does NOT trigger
  (exact `==`, not `contains`). Assert the literal `== '/soleur fix constraints'`.
- **T3 (non-loop):** the FR5 outcome comment body ≠ the trigger string → the `issue_comment` it
  fires fails the `if`-guard. Verified-non-loop note in the plan; assert outcome-comment body is not
  the exact command.
- **T4 (fork guard):** `isCrossRepository == true` → push path skipped, explanatory comment posted,
  run exits 0.
- **T5 (emitter):** `constraint-scaffold.sh` against a fixture target writes `fix-constraints.yml`
  and refuses to overwrite an existing one (self-test, mirrors `boundary.test.sh`).
- **T6 (wording residual-zero):** `grep -rn "not yet wired\|planned (#5791\|blocked on #5791"` over
  the swept set returns 0; the learnings file is untouched.

## Sharp Edges

- **Tenant-emission honesty is load-bearing.** Flipping the `references/*.template` wording to
  "dispatcher exists" without the skill emitting a `fix-constraints.yml` re-creates the exact
  false-capability bug #5791 fixes, for every future tenant scaffold. Phase 2 is not optional. The
  minimal alternative (keep template wording tenant-honest, no emitter change) is documented but
  NOT the chosen path — it leaves the recovery model ADR-071 describes incomplete for tenants.
- **ADR-070 is a real, unrelated ADR.** Do NOT blanket-replace `ADR-070` → `ADR-071`. The only
  mis-citation is **issue #5791's body**. Repo `ADR-070` references are the legit L3
  phase-tool-scoping ADR (AC12 guards this).
- **`bash -n` cannot lint a workflow YAML** — it parses the YAML header as bash. Use `actionlint`
  for the YAML and `bash -c '<extracted run: snippet>'` for embedded shell.
- **`id-token: write` vs TR2.** TR2 says "contents+pull-requests only," but the claude-code-action
  precedent carries `id-token: write`. Resolve in Phase 0.1: it is OIDC identity (not repo-write),
  so adding it (if required) honors TR2's intent; document the rationale inline.
- **Model pin is mirrored, not chosen.** `claude-sonnet-4-6` + SHA `ab8b1e6…` are copied verbatim
  from `claude-code-review.yml`. Do NOT substitute a model id from memory; pin freshness is
  `model-launch-review`'s job. If `claude_args` max-turns is ever raised, bump `timeout-minutes` to
  keep the ~0.75 min/turn peer ratio.
- **Agent edits, workflow pushes.** Do not let claude-code-action push — keep `git push` in our own
  step so the push target is provably the PR head ref and nothing else (FR4 / ACE-avoidance).
- **Exact-match command is whitespace-brittle by design.** `body == '/soleur fix constraints'`
  rejects a trailing space/newline. This is the deliberate security trade-off (spec FR1 chose exact
  over `contains`). The CI error messages already show the exact command in backticks; keep them so.
- **A `## User-Brand Impact` section that is empty/placeholder fails `deepen-plan` Phase 4.6** — it
  is filled above.

## Research Insights (deepen-plan, 2026-06-30)

**Precedent-Diff (Phase 4.4 — pattern-bound `claude-code-action` + `issue_comment` dispatcher):**

- **`issue_comment` gating shape** — precedent `cla.yml` (`if: github.event_name == 'issue_comment' && github.event.issue.pull_request`). Adopted; this plan adds the exact-match command + author-association + head==base guards on top. Diverges deliberately: cla.yml uses `pull_request_target` (TR1 forbids here).
- **`claude-code-action` wiring** — precedent `.github/workflows/claude-code-review.yml` + `.github/workflows/test-pretooluse-hooks.yml`. Adopted verbatim: action SHA `ab8b1e6471c519c585ba17e8ecaccc9d83043541` (# v1.0.101), `anthropic_api_key: ${{ secrets.ANTHROPIC_API_KEY }}`, the `anthropic-preflight` ok-gate, the API-spend capture step. `claude_args` mirrors test-pretooluse-hooks.yml's agentic-write form (`--model claude-sonnet-4-6 --max-turns 20 --allowedTools Bash,Read,Write,Edit,Glob,Grep`).
- **git identity** — precedent: the scheduled-*.yml family runs an explicit `git config user.name/email` before pushing (claude-code-action does NOT auto-config). Adopted (Phase 1 step).
- **NOT a scheduled job** — the Inngest-vs-GH-Actions-cron precedent check (ADR-033) does NOT apply: this is an event-triggered `issue_comment` workflow, not a recurring cron.

**Live-verified SHAs (Phase 4 quality gate — resolved this pass, not from memory):**

```
$ git grep -hE 'uses: anthropics/claude-code-action@|uses: actions/checkout@' -- '.github/workflows/*.yml' \
    | grep -oE '@[0-9a-f]+' | tr -d '@' | sort -u | awk '{print length": "$0}'
40: 34e114876b0b11c390a56381ad16ebd13914f8d5   # actions/checkout v4.3.1
40: ab8b1e6471c519c585ba17e8ecaccc9d83043541   # anthropics/claude-code-action v1.0.101
```
Both pins are 40-char and in active in-repo use. Mirror exactly; do NOT truncate or substitute.

**TR2 / id-token resolution:** both in-repo claude-code-action users carry `id-token: write`
(`claude-code-review.yml`, `test-pretooluse-hooks.yml`). Include it on the fix job — OIDC identity,
not repo-mutation, consistent with TR2's intent.

## Review Findings Folded In (deepen-plan agents)

Two agents reviewed the workflow design at the single-user-incident / ACE threshold; load-bearing
findings folded into the canonical design + ACs above:

**security-sentinel:**
- **P1** persisted checkout credential gave the agent step ambient push capability → `persist-credentials: false` + explicit env-passed push credential (AC8b). Sound on TR1/TR4/token-scope/FR5-loop.
- **P2** `author_association` is a relationship, not a push right → added `gh api …/permission` ∈ {admin,write} gate (AC8c).

**spec-flow-analyzer (feedback-completeness was the dominant gap):**
- **F1** `anthropic-preflight` exits 1 (red) on key-absent — NOT a clean no-op; claim corrected.
- **F2** FR5 outcome comment lived inside the conditionally-skipped fix job → every preflight-skip path left the founder silent (re-creating #5791) → added `always()` notify-on-skip job (AC8e).
- **F3/F4** "fixed" was asserted from `agent exited 0`, a proxy → re-run the gate, report honestly (AC8d).
- **F5** CI error showed the command in backticks → founder copy-pastes a non-matching string → silent skip → render the command as a bare copy-pasteable line (AC8f).
- **F6** job-level `permissions:` REPLACES top-level → id-token moved onto the fix job's own block.
- **F7** push-rejection handling (protected/diverged head) → distinct failure comment via notify-on-skip.
- **F8** the dispatcher cannot run from the feature branch (issue_comment runs only the default-branch copy) → added post-merge functional smoke AC18; no runtime AC is provable pre-merge beyond actionlint+grep.

## Risks & Mitigations

- **R1 — ACE via mis-scoped issue_comment.** Mitigated by TR1 (no `pull_request_target`),
  author-association gate, head==base guard, exact-match command, env-passed strings, and keeping
  commit+push in the workflow (not the agent). `security-sentinel` re-reviews at PR time.
- **R2 — push to a protected/wrong branch.** Mitigated by `git push origin HEAD:$HEAD_REF` with
  `HEAD_REF` from `gh pr view headRefName`; AC7 asserts no other push target exists.
- **R3 — TR2/id-token unresolved at /work.** Phase 0.1 verifies before authoring `permissions:`.
- **R4 — claude-code-action commit-mode unknown.** Phase 0/1 verify the action does not auto-push;
  prompt instructs "do not push." If it auto-commits, our push step still controls the target.
```
