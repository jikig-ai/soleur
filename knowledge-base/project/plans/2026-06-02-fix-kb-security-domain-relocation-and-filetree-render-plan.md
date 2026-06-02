---
title: "Relocate skill-overrides out of top-level security/, fix KB file-tree root-file render, add KB domain allowlist guard"
date: 2026-06-02
type: fix
branch: feat-one-shot-kb-domain-cleanup-filetree-fix
lane: cross-domain
status: draft
brand_survival_threshold: none
---

# fix: KB security-domain relocation + file-tree root-file render + domain allowlist guard

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Phase 4 (test design), Sharp Edges, Research Insights
**Research method:** direct code verification (Task subagent spawning unavailable in this environment; the load-bearing checks — gate compliance, verify-the-negative, render-claim verification — were run directly against the codebase).

### Key Improvements
1. Verified every load-bearing technical claim against the actual code: `aria-expanded` lives ONLY on the `TreeItem` directory button (`file-tree.tsx:200`), `FileNode` renders a `<Link>` (`:416`), and edit affordances gate on `isAttachment = node.extension !== ".md"` (`:356, :444`). The Part B fix and its test assertions are sound.
2. Corrected a factual detail: vitest's component project uses `happy-dom`, not jsdom (`vitest.config.ts:57`). Sharp Edge updated.
3. Surfaced a render nuance the test must account for: the three root files are NOT all `.md`. `INDEX.md` is the clean "no edit affordance" case; `kb-categories.txt` and `kb-tags.txt` are `isAttachment=true` (extension ≠ `.md`) and WILL render rename/delete buttons — still correctly as FILES (a `<Link>`, file icon, no chevron/upload), which is the actual bug being fixed. The test's "renders as file" assertion must key on the `<Link>` / absence-of-`aria-expanded`, NOT on absence-of-edit-buttons (that only holds for `.md`).

### Gate Results (deepen-plan Phases 4.4–4.8)
- 4.4 Precedent-diff / scheduled-work: N/A — no SQL `SECURITY DEFINER`/`INVOKER`, no locks, no atomic-write, no RPC, no new cron/Inngest function. Pattern is a mechanical path-rename + a render branch + an advisory hook modeled on the existing `no-memory-write.sh` precedent (cited in Phase 5).
- 4.45 Verify-the-negative: the plan's "no data surface touched" claim confirmed — `file-tree.tsx` is a client render component; no `process.env.NEXT_PUBLIC_*`, no write boundary. PASS.
- 4.6 User-Brand Impact: PRESENT, threshold `none` with scope-out reason. PASS.
- 4.7 Observability: PRESENT, all 5 fields non-placeholder, `discoverability_test.command` is ssh-free. PASS.
- 4.8 PAT-shape: no PAT-shaped variables/literals. PASS.

## Overview

Three related knowledge-base hygiene fixes in one PR, surfaced from GitHub screenshots:

- **Part A** — Relocate `knowledge-base/security/skill-overrides/` (currently only `.gitkeep`) to `knowledge-base/engineering/security/skill-overrides/`, removing the anomalous top-level `security/` domain. GitHub collapses the single-child path `security/` → `security/skill-overrides`, making it appear as a stray top-level entry. Update all 13 live wiring/doc references; preserve history with `git mv`.
- **Part B** — Fix the KB file-tree client render bug: the top-level `FileTree` map (`file-tree.tsx:60-69`) renders EVERY root node as a directory `<TreeItem>` with no `node.type` branch, so root-level files (`INDEX.md`, `kb-categories.txt`, `kb-tags.txt`) show as folders (chevron + upload affordance). The nested map (`:280`) already branches correctly. Mirror that branch at the top level.
- **Part C** — Add an advisory PreToolUse hook that warns when a NEW top-level dir is created under `knowledge-base/` outside the sanctioned set, with the allowlist documented in one extensible place.

`lane: cross-domain` (no spec.md on this branch with a `lane:` field; defaulted to cross-domain per TR2 fail-closed — touches engineering tooling, legal compliance doc, and web-platform UI).

This is a tooling/hygiene change against already-provisioned surfaces. No new infrastructure, no schema/migration, no regulated-data processing surface, no new user-facing page.

## Premise Validation

- **Directory state:** `knowledge-base/security/skill-overrides/.gitkeep` is the ONLY tracked content under `security/` (`git ls-files knowledge-base/security/` → single `.gitkeep`). Confirmed: it is a placeholder; there are no override artifacts to migrate. Honor the documented retention policy (`compliance-posture.md:103`: "retention = repo lifetime") — do not delete; carry the `.gitkeep` via `git mv`.
- **Reference sites:** `grep -rln "security/skill-overrides" . --exclude-dir=.git` returns 18 files. 5 are point-in-time historical artifacts (do NOT rewrite — see Research Reconciliation); 13 are live wiring + living docs (rewrite). The arguments listed 13 known sites; the grep confirms exactly those plus one additional learning file requiring a disposition decision (see Research Reconciliation).
- **file-tree.tsx:** confirmed `:60-69` maps `tree.children` unconditionally to `<TreeItem>`; `:280` branches `child.type === "directory" ? <TreeItem> : <FileNode>`. Server `server/kb-reader.ts:238-239` tags root files `type: "file" as const` — render bug only.
- **#3524 / feat-skill-security-scan:** the override mechanism was added by that feature; brainstorm/plan/spec/tasks artifacts are dated records under `knowledge-base/project/{brainstorms,plans,specs}/` and are NOT rewritten.
- No external GitHub-issue premises to validate (no `#N` cited as blocker).

## Research Reconciliation — Spec vs. Codebase

| Claim (from ARGUMENTS) | Reality (verified) | Plan response |
|---|---|---|
| 13 known reference sites | `grep -rln` returns 18; 13 live + 5 historical. One *additional* live-ish reference NOT in the known list: `knowledge-base/project/learnings/2026-05-20-skill-md-shell-active-prose-calibration-carve-out.md:69`. | The 2026-05-20 file is a DATED learning record (point-in-time), same class as brainstorms/plans/specs. Per the "do NOT rewrite historical artifacts" directive (which named brainstorms/plans/specs explicitly), treat dated learnings the same way: **do NOT rewrite**. It documents what the path WAS at that date. Add it to the historical-exclusion list. |
| Workflow `paths:` filters may gate on `security/skill-overrides` | Neither `skill-security-scan-postmerge.yml` nor `skill-security-scan-pr-trailer.yml` has a `paths:` filter on the override dir; the references are in `printf`/`echo ::error` message bodies and a header comment. | No workflow trigger changes needed. Update only the message-body / comment literals. |
| `parse-override.sh` path is a "regex" at ~line 5, 31 | `:5` is a comment (literal regex shown); `:31` is the active `path_re='^knowledge-base/security/skill-overrides/...'`. Both must change. The regex is anchored `^knowledge-base/...` (repo-root-relative). | Update both. New: `^knowledge-base/engineering/security/skill-overrides/...`. |
| `skill-security-scan.sh` ~line 46 | Active `grep -q '^knowledge-base/security/skill-overrides/'` at `:46` (anchored `^`). | Update the anchored grep literal. |
| `skill-security-scan-write.sh` ~lines 49, 120 | `:49` is a `case` glob `*knowledge-base/security/skill-overrides/*.md)` (substring, leading `*` — safe either way but update for correctness); `:120` is the deny-reason message string. | Update both. |

No "Gap callouts" that change phase shape — the work is mechanical path-rewrite + one client-render branch + one new advisory hook.

## User-Brand Impact

**If this lands broken, the user experiences:** (A) skill-security HIGH-RISK override artifacts can no longer be written/validated (the PreToolUse gate or CI gate looks at the wrong path), silently disabling an advisory security gate; OR (B) the KB file-tree continues to show root files as folders (cosmetic, already-shipped state — no regression).
**If this leaks, the user's data is exposed via:** N/A — no data surface touched. The override mechanism is an evidence-record location (currently empty); relocation does not move any user data.
**Brand-survival threshold:** none

`threshold: none` and the diff does not touch a sensitive path (no schema/migration/auth/API route; `apps/web-platform/components/kb/file-tree.tsx` is a client component render fix, not a write boundary). The skill-security wiring is a security-gate path but the change is a path-rename with parity tests, not a relaxation. No scope-out bullet required, but recorded here for preflight Check 6 clarity: `threshold: none, reason: tooling path-rename with parity tests + cosmetic client render fix; no data, schema, auth, or API surface touched.`

## Implementation Phases

Phases are ordered so the contract-defining move (Part A directory + regex) lands before its consumers are re-verified, and the independent Parts B and C can land in any order after.

### Phase 0 — Preconditions (verify before editing)

0.1. Confirm working tree clean on branch `feat-one-shot-kb-domain-cleanup-filetree-fix`.
0.2. `git ls-files knowledge-base/security/` → exactly `knowledge-base/security/skill-overrides/.gitkeep`. If any other tracked file exists, STOP and re-scope (there may be a real override artifact to migrate under retention policy).
0.3. `ls knowledge-base/engineering/security 2>/dev/null` → must NOT exist yet (target is a fresh nested path). If it exists, reconcile before `git mv`.
0.4. Re-run `grep -rln "security/skill-overrides" . --exclude-dir=.git` and snapshot the 18-file list into the PR body for the verification diff.

### Phase 1 — Part A: relocate the directory (history-preserving)

1.1. `mkdir -p knowledge-base/engineering/security` (parent for the moved child).
1.2. `git mv knowledge-base/security/skill-overrides knowledge-base/engineering/security/skill-overrides` (moves the dir + the tracked `.gitkeep`, preserving history).
1.3. Confirm the now-empty `knowledge-base/security/` is gone: `git` removes the leaf on `mv`; if an empty `knowledge-base/security/` dir remains on disk, `rmdir knowledge-base/security` (git does not track empty dirs, so no `git rm` needed). Verify `ls knowledge-base/ | grep -x security` returns nothing.
1.4. Verify `git status` shows the rename as `R` (rename) for `.gitkeep`, not delete+add.

### Phase 2 — Part A: update live wiring (path literals + regexes)

Edit each of these 13 live sites, replacing `knowledge-base/security/skill-overrides` → `knowledge-base/engineering/security/skill-overrides`. NOTE the regex-anchored sites need the `^knowledge-base/` prefix kept and only the middle segment changed.

- `.claude/hooks/skill-security-scan.sh:46` — anchored grep: `'^knowledge-base/security/skill-overrides/'` → `'^knowledge-base/engineering/security/skill-overrides/'`.
- `.claude/hooks/skill-security-scan-write.sh:49` — case glob `*knowledge-base/security/skill-overrides/*.md)` → `*knowledge-base/engineering/security/skill-overrides/*.md)`.
- `.claude/hooks/skill-security-scan-write.sh:120` — deny-reason string (`Required: knowledge-base/security/skill-overrides/YYYY-MM-DD-...`).
- `.github/workflows/skill-security-scan-postmerge.yml:69` — `printf` message body literal.
- `.github/workflows/skill-security-scan-pr-trailer.yml:8` — header comment.
- `.github/workflows/skill-security-scan-pr-trailer.yml:136` — `echo "::error ..."` message literal.
- `plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh:5` — comment showing the regex.
- `plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh:31` — active `path_re='^knowledge-base/engineering/security/skill-overrides/[0-9]{4}-[0-9]{2}-[0-9]{2}-[a-z][a-z0-9-]*\.md$'`.
- `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh:77` — advisory message literal (backtick-wrapped path).
- `plugins/soleur/skills/skill-security-scan/SKILL.md:79` — example path.
- `plugins/soleur/skills/skill-security-scan/references/override-mechanism.md:5,16,59` — prose + example `cat >` heredoc target.
- `plugins/soleur/skills/skill-security-scan/references/override-artifact-schema.json:5` — `description` field literal.
- `plugins/soleur/skills/skill-creator/SKILL.md:223` — prose reference.
- `plugins/soleur/agents/engineering/discovery/agent-finder.md:149` — prose reference.
- `knowledge-base/legal/compliance-posture.md:103` — living compliance doc (Active Items table row). Update the inline path; do NOT alter the retention-policy wording.

**Do NOT edit (historical / dated records):**
- `knowledge-base/project/brainstorms/2026-05-10-skill-security-scan-brainstorm.md`
- `knowledge-base/project/plans/2026-05-10-feat-skill-security-scan-plan.md`
- `knowledge-base/project/specs/feat-skill-security-scan/spec.md`
- `knowledge-base/project/specs/feat-skill-security-scan/tasks.md`
- `knowledge-base/project/learnings/2026-05-20-skill-md-shell-active-prose-calibration-carve-out.md` (dated learning record — see Research Reconciliation)

### Phase 3 — Part A: verify wiring parity

3.1. `grep -rn "security/skill-overrides" . --exclude-dir=.git` — every remaining match MUST be either (a) an `engineering/security/skill-overrides` path, or (b) one of the 5 historical artifacts above. Zero bare `knowledge-base/security/skill-overrides` in live wiring.
3.2. Run skill-security-scan self-tests if present: `bash plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh --help` (smoke) and any `*.test.sh` for the scan scripts (`ls plugins/soleur/skills/skill-security-scan/ -R | grep -i test`). Run `bash .claude/hooks/skill-security-scan-write.sh` against a synthesized override-path payload to confirm the new `case` glob still classifies `file_kind=override`.
3.3. Run the hook test suite that exercises these hooks if present (`ls .claude/hooks/*skill-security*test*`); if no dedicated test exists, do a manual stdin-payload smoke per the hook's own header docs.

### Phase 4 — Part B: file-tree root-file render fix (TDD)

4.1. **RED** — Add `apps/web-platform/test/file-tree-root-files.test.tsx` (top-level `test/` dir so vitest's component project glob `test/**/*.test.tsx` collects it — confirmed `vitest.config.ts:60`). Mirror the mock scaffold from `test/file-tree-delete.test.tsx` (`vi.hoisted` mockUseKb, `vi.mock("next/navigation")`, `vi.mock("@/components/kb/kb-context")`, `vi.mock("@/server/kb-reader")`). Build a tree whose `children` include a root-level `type: "file"` node (e.g. `{ name: "INDEX.md", type: "file", path: "INDEX.md", extension: ".md", modifiedAt }`) AND a root-level `type: "directory"` node. Assert:
  - the file node renders as a file: a `<Link>` to `/dashboard/kb/INDEX.md` (the `FileNode` shape) — query by role `link` with the href, AND assert absence of the directory affordances (no `aria-expanded` element, no "Upload file to ..." button). Verified: `aria-expanded` is set ONLY on the `TreeItem` directory button (`file-tree.tsx:200`); `FileNode` never sets it — so `queryByRole("button", { expanded: ... })` / `container.querySelector("[aria-expanded]")` is a clean discriminator.
  - the directory node still renders as a directory (`aria-expanded` present, FolderIcon).
  - **Render nuance (key on the right signal):** the three real root files are `INDEX.md`, `kb-categories.txt`, `kb-tags.txt`. Only `INDEX.md` is `.md` → `isAttachment=false` → no rename/delete buttons. The two `.txt` files are `isAttachment=true` (extension ≠ `.md`, `file-tree.tsx:356`) and DO render rename/delete affordances — but still as FILES (a `<Link>`, file icon, no chevron/upload). Therefore the "renders as file" assertion MUST key on the `<Link>`/absence-of-`aria-expanded`, NOT on absence-of-edit-buttons. Use `INDEX.md` for the strict no-affordance case and (optionally) a `.txt` node to assert it renders as a `<Link>` (file), not a `TreeItem` (folder).
  Run `cd apps/web-platform && npm run test:ci -- file-tree-root-files` → expect RED (current code renders the file as a `<TreeItem>` directory → no `<Link>`, has `aria-expanded`).
4.2. **GREEN** — In `file-tree.tsx`, change the top-level `FileTree` map (`:60-69`) to branch on `node.type` identically to `:280`:
  ```tsx
  {tree.children.map((node) =>
    node.type === "directory" ? (
      <TreeItem key={node.name} node={node} depth={0} parentPath="" expanded={expanded} onToggle={toggleExpanded} />
    ) : (
      <FileNode key={node.name} node={node} depth={0} />
    ),
  )}
  ```
  Note: `FileNode` at `depth={0}` renders fine — its rename/delete buttons gate on `isAttachment` (non-`.md`), so root `.md`/`.txt` files render as a clean `<Link>` with the default file icon and no edit affordances. Re-run → expect GREEN.
4.3. **REGRESSION** — Run the existing file-tree suites to confirm no break: `npm run test:ci -- file-tree` (covers `file-tree-rename`, `file-tree-upload`, `file-tree-delete` + the new test).

### Phase 5 — Part C: KB top-level domain allowlist guard (TDD)

5.1. **Design** — Add `.claude/hooks/kb-domain-allowlist-guard.sh`, a PreToolUse hook matching `Write|Edit|MultiEdit|NotebookEdit` (and optionally `Bash` for `mkdir`/`mv` redirects, mirroring `no-memory-write.sh`'s Bash coverage). It extracts the target path (same jq pattern as `no-memory-write.sh:32-39`: `.tool_input.file_path // .tool_input.notebook_path // .tool_input.command`), and:
  - Fail-open on malformed JSON (exit 0).
  - Detect when the path introduces a NEW top-level entry directly under `knowledge-base/` (i.e. matches `(^|/)knowledge-base/<segment>(/|$)` where `<segment>` is the first path component under `knowledge-base/`).
  - If `<segment>` is NOT in the sanctioned set, emit an **advisory** decision. Decision tier MUST match sibling guards: `no-memory-write.sh` uses `permissionDecision: deny`; the KB allowlist is advisory per ARGUMENTS, so use `permissionDecision: ask` (operator-acknowledged) — NOT silent `allow`, NOT hard `deny`. Rationale: a new domain is a legitimate-but-rare operation (`plugins/soleur/AGENTS.md` "Adding a New Domain" documents the multi-step process); blocking outright would break that flow, while silent allow defeats the guard. `ask` surfaces it for one operator confirmation.
  - Only fire on NEW top-level entries: if the segment already exists on disk under `knowledge-base/`, exit 0 (writing into an existing sanctioned domain is always fine, and avoids false positives on every KB write).
5.2. **Sanctioned set (single source of truth)** — Define the allowlist as a single array in the hook AND document it in a co-located comment block. After Part A:
  - dirs: `engineering finance legal marketing operations product project sales support`
  - files: `INDEX.md kb-categories.txt kb-tags.txt`
  - **`security` is intentionally EXCLUDED** (removed by Part A). Add an inline comment: `# security/ intentionally NOT sanctioned — relocated to engineering/security/ (PR <this>). Do not re-add.`
  Document the same list in the hook's header comment as the canonical extension point ("To sanction a new top-level domain, add it here AND follow plugins/soleur/AGENTS.md 'Adding a New Domain'."). Cross-reference from `plugins/soleur/AGENTS.md` "Adding a New Domain" step list so the two stay linked.
5.3. **RED→GREEN test** — Add `.claude/hooks/kb-domain-allowlist-guard.test.sh` following the `no-memory-write.test.sh` harness shape (PASS/FAIL counters, `invoke_write` helper). Auto-discovered by `scripts/test-all.sh:176` (`.claude/hooks/*.test.sh` glob). Cases:
  - New unsanctioned top-level dir write (`knowledge-base/observability/foo.md`) → `permissionDecision: ask`.
  - Re-introducing `security/` (`knowledge-base/security/skill-overrides/x.md`) → `ask` (regression guard for Part A — this is the exact anomaly being removed).
  - Write into existing sanctioned domain (`knowledge-base/engineering/security/skill-overrides/2026-...md`) → `allow`/exit 0 (the relocated path must NOT trip the guard).
  - Write to sanctioned top-level file (`knowledge-base/INDEX.md`) → exit 0.
  - Malformed JSON → exit 0 (fail-open).
  - Non-KB path → exit 0.
5.4. **Wire into settings.json** — Add a PreToolUse entry mirroring `no-memory-write.sh` wiring (`matcher: "Write|Edit|MultiEdit|NotebookEdit"`, command `"$CLAUDE_PROJECT_DIR"/.claude/hooks/kb-domain-allowlist-guard.sh`). If Bash coverage is included, add a second `matcher: "Bash"` entry. `chmod +x` the hook.
5.5. Run `bash .claude/hooks/kb-domain-allowlist-guard.test.sh` → all green.

### Phase 6 — Full verification

6.1. `grep -rn "security/skill-overrides" . --exclude-dir=.git` → only engineering-path refs + the 5 historical artifacts.
6.2. `cd apps/web-platform && npm run test:ci -- file-tree` → green (Part B + regression).
6.3. `bash .claude/hooks/kb-domain-allowlist-guard.test.sh` and any skill-security-scan hook tests → green.
6.4. `tsc --noEmit` (web-platform) → no new errors from the file-tree edit.
6.5. Verify no broken KB citations introduced: `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <edited-files> | xargs -I{} bash -c '[[ -f "{}" ]] || echo BROKEN: {}'`.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `git ls-files knowledge-base/engineering/security/skill-overrides/` returns `.gitkeep`; `git ls-files knowledge-base/security/` returns nothing; `ls knowledge-base/ | grep -x security` is empty.
- [ ] `git log --follow --oneline -- knowledge-base/engineering/security/skill-overrides/.gitkeep` shows history predating this PR (history preserved via `git mv`).
- [ ] `grep -rn "knowledge-base/security/skill-overrides" . --exclude-dir=.git` returns ONLY the 5 named historical artifacts (zero live-wiring matches).
- [ ] `parse-override.sh` `path_re` is `^knowledge-base/engineering/security/skill-overrides/...`; a synthesized override at the new path validates (parser exit 0, artifact in `.matched`); a synthesized override at the OLD path is ignored.
- [ ] `skill-security-scan-write.sh` classifies a new-path override write as `file_kind=override` → `permissionDecision: ask`.
- [ ] `file-tree.tsx` top-level map branches on `node.type` (matches `:280` shape).
- [ ] `apps/web-platform/test/file-tree-root-files.test.tsx` exists and is collected by vitest (`.test.tsx` under `test/`); it asserts a root `type:"file"` node renders as a `FileNode` (`<Link>`, no `aria-expanded`, no upload button) and a root `type:"directory"` node still renders as a `TreeItem`.
- [ ] `cd apps/web-platform && npm run test:ci -- file-tree` is green.
- [ ] `.claude/hooks/kb-domain-allowlist-guard.sh` exists, is executable, is wired in `.claude/settings.json` PreToolUse, and the sanctioned set excludes `security`.
- [ ] `.claude/hooks/kb-domain-allowlist-guard.test.sh` is green and covers: unsanctioned-new-dir → `ask`, re-adding `security/` → `ask`, write-into-existing-sanctioned → exit 0, sanctioned top-level file → exit 0, malformed JSON → exit 0.
- [ ] `tsc --noEmit` (web-platform) shows no new errors.
- [ ] No dated artifact under `knowledge-base/project/{brainstorms,plans,specs}/` and the `2026-05-20` learning are modified.
- [ ] PR body includes a `## Changelog` section and a `semver:` label (`semver:patch` — bug fix + advisory tooling; the new hook is repo infra, not a plugin component).

## Domain Review

**Domains relevant:** Legal (compliance-posture.md is a living legal doc), Engineering (skill tooling + web-platform UI).

This is primarily an infrastructure/tooling + cosmetic-UI change. The only cross-domain artifact is the one-line path update in `knowledge-base/legal/compliance-posture.md:103` (an Active Items table row). The update is a mechanical path rename within an existing row; it does NOT change the compliance posture, the retention policy, the GDPR Art. 32 evidence semantics, or any obligation — the override location is the same evidence record, nested one level deeper. No CLO re-review required for a path-string update that preserves all wording. Engineering: covered by the parity tests in Phases 3 and 4.

No Product/UX gate: Part B is a one-line client render branch fixing an existing cosmetic bug on an existing surface (no new page, no new component file — `FileNode` already exists). Tier: NONE.

### Product/UX Gate

**Tier:** none — modifies render branching in an existing component; no new user-facing surface, no new `.tsx` file under `components/**` or `app/**/page.tsx`.

## Observability

This plan's Files-to-Edit includes code-class files under `apps/web-platform/components/`, `.claude/hooks/`, and `plugins/soleur/`. Observability schema:

```yaml
liveness_signal:
  what: skill-security-scan PreToolUse + CI gates continue to fire on skill/agent writes after the path move
  cadence: on every Write to SKILL.md/agent files (PreToolUse) + on every PR/merge (CI workflows)
  alert_target: existing skill-security-scan-postmerge.yml auto-files compliance/critical issue on bypass
  configured_in: .claude/hooks/skill-security-scan-write.sh + .github/workflows/skill-security-scan-postmerge.yml (unchanged behavior, new path)
error_reporting:
  destination: hook emit_incident telemetry (lib/incidents.sh) — unchanged; new kb-domain-allowlist-guard emits its own incident on advisory fire
  fail_loud: yes — guards exit 0 with JSON decision (deny/ask), surfaced to operator in-session; malformed-input fails open (documented)
failure_modes:
  - mode: path-move misses a regex anchor (override gate looks at wrong path)
    detection: Phase 3 parity test (synthesized override at new path validates; old path ignored) + CI skill-security-scan gate on this very PR
    alert_route: PR CI red
  - mode: new allowlist guard false-positives on existing-domain writes
    detection: kb-domain-allowlist-guard.test.sh "write-into-existing-sanctioned → exit 0" case
    alert_route: test-all.sh exit gate (CI)
  - mode: file-tree branch regresses directory rendering
    detection: existing file-tree-* vitest suites + new root-files test
    alert_route: vitest CI shard
logs:
  where: hook stderr advisory lines + emit_incident sink (existing convention); vitest output in CI
  retention: CI log retention (GitHub Actions default)
discoverability_test:
  command: "grep -rn 'security/skill-overrides' . --exclude-dir=.git && bash .claude/hooks/kb-domain-allowlist-guard.test.sh && cd apps/web-platform && npm run test:ci -- file-tree"
  expected_output: "only engineering-path + 5 historical refs; hook tests green; file-tree suite green — all without ssh"
```

## Files to Edit

- `.claude/hooks/skill-security-scan.sh` (anchored grep, :46)
- `.claude/hooks/skill-security-scan-write.sh` (case glob :49, deny message :120)
- `.claude/settings.json` (wire new PreToolUse hook)
- `.github/workflows/skill-security-scan-postmerge.yml` (:69 message)
- `.github/workflows/skill-security-scan-pr-trailer.yml` (:8 comment, :136 message)
- `plugins/soleur/skills/skill-security-scan/scripts/parse-override.sh` (:5 comment, :31 path_re)
- `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh` (:77 message)
- `plugins/soleur/skills/skill-security-scan/SKILL.md` (:79)
- `plugins/soleur/skills/skill-security-scan/references/override-mechanism.md` (:5,16,59)
- `plugins/soleur/skills/skill-security-scan/references/override-artifact-schema.json` (:5)
- `plugins/soleur/skills/skill-creator/SKILL.md` (:223)
- `plugins/soleur/agents/engineering/discovery/agent-finder.md` (:149)
- `plugins/soleur/AGENTS.md` ("Adding a New Domain" — cross-reference the allowlist guard)
- `knowledge-base/legal/compliance-posture.md` (:103 path only)
- `apps/web-platform/components/kb/file-tree.tsx` (:60-69 branch)

## Files to Create

- `apps/web-platform/test/file-tree-root-files.test.tsx`
- `.claude/hooks/kb-domain-allowlist-guard.sh`
- `.claude/hooks/kb-domain-allowlist-guard.test.sh`

## Files to Move (git mv)

- `knowledge-base/security/skill-overrides/` → `knowledge-base/engineering/security/skill-overrides/` (carries `.gitkeep`)

## Open Code-Review Overlap

None — no open code-review issues were checked against these paths in this planning session (run `gh issue list --label code-review --state open` at /work time if desired; this is a low-overlap tooling change).

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only TBD/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. The section above is filled with threshold `none` + reason.
- `parse-override.sh:31` and `skill-security-scan.sh:46` are `^`-ANCHORED (repo-root-relative) regexes; `skill-security-scan-write.sh:49` is a `*`-prefixed case glob (substring, may receive absolute paths). Keep the anchor/glob shape; change only the middle path segment. A naive sed that strips the leading `^knowledge-base/` would break the anchor.
- The 2026-05-20 learning file references the OLD path by design (point-in-time record). Do NOT rewrite it; the verification grep in Phase 6 must explicitly allowlist it alongside the 4 brainstorm/plan/spec artifacts, or it will read as a missed reference.
- The new allowlist guard must exit 0 (allow) for writes INTO an existing sanctioned domain — otherwise every KB write under `engineering/` etc. trips `ask`. Gate strictly on NEW-top-level-segment-not-on-disk.
- Test FILE extension is load-bearing: vitest's component project collects `test/**/*.test.tsx` and runs them under `happy-dom` (`vitest.config.ts:57,60`). A `.test.ts` falls into the `node` project (`test/**/*.test.ts`) with no DOM environment and RTL `render` would fail. Use `.test.tsx`.
- `FileNode` "renders as file" must be asserted via the `<Link>` / absence-of-`aria-expanded`, NOT via absence-of-edit-buttons: `.txt` root files are `isAttachment=true` and legitimately show rename/delete buttons while still rendering as files. Only `.md` files have no edit affordances.
- `git mv` of a directory containing only `.gitkeep` preserves history; do NOT `rm -rf` + re-create (loses history, and `rm -rf` on a KB subtree risks the guardrails hook).

## Test Scenarios

1. Override artifact written at `knowledge-base/engineering/security/skill-overrides/2026-06-02-foo.md` validates (parser `.matched`), old-path artifact ignored.
2. Root-level `INDEX.md` (type:file) renders as a link, not a folder.
3. Root-level directory still renders as expandable TreeItem.
4. Creating `knowledge-base/observability/x.md` → guard returns `ask`.
5. Re-creating `knowledge-base/security/y.md` → guard returns `ask` (Part A regression guard).
6. Writing `knowledge-base/engineering/security/skill-overrides/z.md` → guard exits 0.
7. Full `grep -rn security/skill-overrides` → engineering paths + 5 historical only.
