---
title: "fix(pencil): guard against open_document .pen wipe via snapshot + commit-after-save"
issue: 3274
type: bug
priority: p1-high
domain: engineering
lane: procedural
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-06-03
branch: feat-one-shot-pencil-open-document-wipe-3274
---

# 🐛 fix(pencil): guard against `open_document` .pen wipe (snapshot-verify + commit-after-save)

## Overview

`mcp__pencil__open_document` overwrote a 133KB `.pen` file with empty document
state (41 bytes: `{"version": "2.11", "children": []}`) while returning a success
string. No error surfaced. Founder-approved design source was silently destroyed
between iteration cycles; only PNG exports survived (reinterpretation, not
iteration). See issue #3274.

**Pencil is an external MCP server, not vendored in this repo.** The cleanest fix
— mitigation (1), the adapter refusing to write empty state over a non-empty
source — lives in the Pencil codebase and **cannot be made here**. This plan
implements the two mitigations that ARE controllable in this repo:

- **Mitigation (2):** Teach the `ux-design-lead` agent to snapshot the `.pen`
  file (size + sha256) **before** `open_document` and to verify **after** open
  that the size has not collapsed. A collapse is treated as a parse-failure wipe
  (halt + surface verbatim), not a legitimate open.
- **Mitigation (3):** Teach the brand-workshop / brainstorm flow to **commit the
  `.pen` file to the worktree branch immediately after first save**, so a
  subsequent wipe is recoverable from git.

This is a **docs / agent-instruction change** (markdown edits to one agent + one
skill reference) plus two sibling `.test.sh` regression guards. No application
code, no migration, no infrastructure.

### Why the existing post-save gate is insufficient

`ux-design-lead.md` Step 3 item 2 already has a "Post-save size verification
(HARD GATE)" — but it only asserts `> 0 bytes`. The wipe in #3274 produced a
**41-byte** file, which passes `> 0`. A 41-byte document is non-empty by the
byte test yet is a total data loss against a 133KB source. The gap is the
**absence of a before/after comparison**: only a pre-open snapshot makes the
collapse detectable.

## Research Reconciliation — Spec vs. Codebase

| Premise (from issue / arguments) | Reality (verified) | Plan response |
|---|---|---|
| `ux-design-lead` agent exists and uses `open_document` at "Step 2 item 3" | Confirmed: `plugins/soleur/agents/product/design/ux-design-lead.md:47` ("Use `open_document` to create a new .pen file or open an existing one") | Insert pre-open snapshot + post-open collapse gate around this step |
| Existing post-save gate only checks `> 0 bytes` | Confirmed: line 57, "assert the result is > 0 bytes" | Strengthen with explicit cross-reference to the new collapse gate; keep the >0 check |
| Brand-workshop commits the `.pen` after first save | **FALSE.** Step 5 commits **only** `knowledge-base/marketing/brand-guide.md` (`brainstorm-brand-workshop.md:88-92`). The `.pen` is never committed by the workshop. | Add a commit-after-first-save step in the ux-design-lead handoff (4.5.a) AND a worktree-commit instruction so the `.pen` lands in git before iteration |
| Line-57 cites `AGENTS.md:cq-pencil-mcp-silent-drop-diagnosis-checklist` | **STALE.** That rule was retired; it now lives as Sharp Edge `ex-cq-pencil-mcp-silent-drop-diagnosis-checklist` in `plugins/soleur/skills/pencil-setup/SKILL.md:185` + learning `knowledge-base/project/learnings/bug-fixes/2026-04-19-ux-design-lead-headless-stub-fabrication.md`. `grep -c cq-pencil` over `AGENTS.{core,rest,docs}.md` = 0. | **Fold in:** repoint the dangling citation to the live Sharp Edge + learning file (one-line edit in the same file we are already editing) |
| Wiped file was at `apps/web-platform/design/theme-toggle.pen` | Confirmed from issue body. This is a path the agent's output-path guard (line 21) is supposed to override to `knowledge-base/product/design/`, AND it is app-tree-gitignored, so it was never committed. | Reinforces mitigation (3): commit-after-save must target the canonical KB path; note in the agent body that an un-committed `.pen` under an app tree is doubly at risk (gitignored + wipeable) |

## User-Brand Impact

**If this lands broken, the user experiences:** a founder-approved `.pen` design
source silently wiped to 41 bytes during a routine iteration ("change this
tooltip label"), with the only recovery being reinterpretation from a PNG
screenshot — i.e., the design is gone and must be rebuilt by guesswork.

**If this leaks, the user's workflow is exposed via:** N/A — no data leaves the
machine; this is a local-file-destruction failure, not an exfiltration vector.
The exposure is **loss**, not leak: irreversible destruction of the founder's
design artifact between iteration cycles.

**Brand-survival threshold:** single-user incident — one founder losing one
approved design to a silent wipe is a trust-breaking event for the design
workflow Soleur positions as the founder's standard surface.

> **Sharp edge:** a plan whose `## User-Brand Impact` section is empty, contains
> only TBD/TODO/placeholder text, or omits the threshold will fail `deepen-plan`
> Phase 4.6. This section is filled.

**CPO sign-off** is required at plan time before `/work` begins (threshold =
single-user incident → `requires_cpo_signoff: true`). `user-impact-reviewer`
will be invoked at review-time. (See Domain Review below for how CPO is covered.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Pre-open snapshot instruction present.** `ux-design-lead.md` Step 2
  (the `open_document` step) instructs the agent, when opening an **existing**
  `.pen`, to record `stat -c %s <path>` and `sha256sum <path>` **before** calling
  `open_document`. Verifiable: `grep -qiE "before .*open_document|snapshot.*(size|sha256|checksum)" plugins/soleur/agents/product/design/ux-design-lead.md`.
- [ ] **AC2 — Post-open collapse gate present.** The agent is instructed to
  re-`stat` after `open_document` and **halt** (surfacing the pre/post sizes
  verbatim) if the post-open size has collapsed below a stated fraction of the
  pre-open size, treating it as a parse-failure wipe (not a legitimate open).
  Verifiable: `grep -qiE "collapse|post-open .*size|fraction|parse failure" plugins/soleur/agents/product/design/ux-design-lead.md`.
- [ ] **AC3 — Collapse threshold is concrete, not vague.** The instruction names a
  specific, testable trip condition (e.g., "post-open size < 50% of pre-open size
  OR post-open size ≤ 64 bytes"). The 41-byte / 133KB case from #3274 must trip
  it. Verifiable by inspection + the regex in AC2.
- [ ] **AC4 — `open_document` on a *new* file is exempt.** The instruction makes
  clear the collapse gate applies only when opening a **pre-existing non-empty**
  `.pen` (creating a brand-new document legitimately starts empty). Verifiable by
  inspection (the snapshot is guarded on "existing file").
- [ ] **AC5 — Commit-after-first-save instruction present in brand-workshop.**
  `brainstorm-brand-workshop.md` step 4.5 (the ux-design-lead handoff) instructs
  that immediately after the `.pen` is first saved under
  `knowledge-base/product/design/`, it is `git add`ed + committed to the worktree
  branch (before any iteration loop), so a later wipe is git-recoverable.
  Verifiable: `grep -qiE "git add.*\.pen|commit.*\.pen|commit the .pen" plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md`.
- [ ] **AC6 — Canonical-path reinforcement.** The commit-after-save instruction
  explicitly requires the committed `.pen` be under `knowledge-base/product/design/`
  (not an app tree like `apps/web-platform/design/`, which is gitignored and was
  the #3274 loss path). Verifiable by inspection.
- [ ] **AC7 — Dangling citation repointed (fold-in).** The stale
  `AGENTS.md:cq-pencil-mcp-silent-drop-diagnosis-checklist` reference at
  `ux-design-lead.md:57` is replaced with a live pointer to
  `plugins/soleur/skills/pencil-setup/SKILL.md` Sharp Edges
  (`ex-cq-pencil-mcp-silent-drop-diagnosis-checklist`) and/or the learning
  `knowledge-base/project/learnings/bug-fixes/2026-04-19-ux-design-lead-headless-stub-fabrication.md`.
  Verifiable: `! grep -q "AGENTS.md:cq-pencil-mcp-silent-drop-diagnosis-checklist" plugins/soleur/agents/product/design/ux-design-lead.md` (zero matches) AND the new pointer resolves to a real file.
- [ ] **AC8 — New regression test: snapshot/collapse guard.** A new sibling test
  `plugins/soleur/test/ux-design-lead-open-document-snapshot-guard.test.sh`
  (modeled on `ux-design-lead-output-path-guard.test.sh`) asserts the agent body
  contains the pre-open snapshot instruction, the post-open collapse gate, and the
  exemption for new files. Test exits 0. Verifiable: `bash plugins/soleur/test/ux-design-lead-open-document-snapshot-guard.test.sh`.
- [ ] **AC9 — New regression test: commit-after-save guard.** A new sibling test
  `plugins/soleur/test/brand-workshop-pen-commit-after-save.test.sh` asserts
  `brainstorm-brand-workshop.md` contains the commit-after-first-save instruction
  for the `.pen` file. Test exits 0.
- [ ] **AC10 — No dangling-citation regression.** Either AC8's test or AC9's test
  (whichever edits `ux-design-lead.md`) also asserts the retired
  `cq-pencil-mcp-silent-drop-diagnosis-checklist` string is absent and the
  canonical KB path is still referenced (mirrors the existing
  `ux-design-lead-output-path-guard.test.sh` assertions so the fold-in cannot
  silently regress).
- [ ] **AC11 — Full suite green.** `bash scripts/test-all.sh` passes; the two new
  `.test.sh` files are auto-discovered by the `plugins/soleur/test/*.test.sh` glob
  at `scripts/test-all.sh:176` (no runner-registration edit needed — verified).

### Post-merge (operator)

- [ ] **AC12 — Close issue #3274.** PR body uses `Closes #3274`. (Pure docs/test
  change, no post-merge apply step — `Closes` is correct here, not `Ref`.)

## Implementation Phases

> Phase order is load-bearing: edit the **agent** (mitigation 2) and **skill**
> (mitigation 3) first, then write the tests that assert those edits. Writing
> tests first would RED against instructions that don't exist yet — acceptable
> for TDD, but here the "contract" is prose in markdown, so author the prose, then
> the grep-guard. (Tests are grep-over-markdown, not behavioral.)

### Phase 1 — ux-design-lead snapshot + collapse gate (mitigation 2)

**File:** `plugins/soleur/agents/product/design/ux-design-lead.md`

1. **Step 2, item 3 (line ~47, the `open_document` step).** Replace the single
   line with a snapshot-aware block. Prose to add (final wording is the
   implementer's, but must satisfy AC1–AC4):
   - When `open_document` targets an **existing** `.pen` (iteration, not new
     creation), FIRST record a pre-open snapshot: `stat -c %s <path>` (bytes) and
     `sha256sum <path>` (checksum). Note the values.
   - Call `open_document`.
   - Immediately re-`stat -c %s <path>`. **Collapse gate (HARD):** if post-open
     size `< 50%` of pre-open size **OR** post-open size `≤ 64 bytes` while
     pre-open was larger, treat the open as a **destructive wipe / parse failure**
     — do NOT proceed with iteration. Halt, surface the pre-open vs post-open
     sizes and the checksum verbatim, and (because the `.pen` source may now be
     destroyed on disk) recover from git if the file was committed
     (mitigation 3) before any further Pencil op.
   - This gate is the open-time analogue of the existing post-**save** size gate
     at item 2 (Step 3). Cross-reference the two.
   - **New-file exemption:** when `open_document` creates a brand-new document,
     there is no pre-open snapshot and the collapse gate does not apply (a new doc
     legitimately starts at ~41 bytes).
2. **Step 3, item 2 (line 57).** Keep the `> 0 bytes` assertion. **Fold in the
   dangling-citation fix (AC7):** replace
   `See \`AGENTS.md:cq-pencil-mcp-silent-drop-diagnosis-checklist\`.` with a
   pointer to the live Sharp Edge in `plugins/soleur/skills/pencil-setup/SKILL.md`
   ("Silent-drop diagnosis", `ex-cq-pencil-mcp-silent-drop-diagnosis-checklist`)
   and the learning file
   `knowledge-base/project/learnings/bug-fixes/2026-04-19-ux-design-lead-headless-stub-fabrication.md`.
3. **Important Guidelines (bottom of file).** Add a one-line note: an un-committed
   `.pen` under an app source tree (e.g., `apps/web-platform/design/`) is doubly
   at risk — it is gitignored by app rules (so not recoverable from git) AND
   wipeable by a destructive `open_document`; always save+commit under
   `knowledge-base/product/design/`.

### Phase 2 — brand-workshop commit-after-first-save (mitigation 3)

**File:** `plugins/soleur/skills/brainstorm/references/brainstorm-brand-workshop.md`

1. **Step 4.5.a (the ux-design-lead handoff Task prompt).** Append an instruction
   that, immediately after the agent's first `save()` produces the `.pen` under
   `knowledge-base/product/design/brand/<topic>-<YYYY-MM-DD>/`, the workshop
   `git add`s + commits that `.pen` to the worktree branch **before** the
   review/iteration loop (step 4.5.b onward) — so an iteration-cycle wipe is
   recoverable via `git checkout -- <path>`. The commit message should name the
   `.pen` path (e.g., `docs: commit design source <topic>.pen (recover-from-wipe safety)`).
2. **Reinforce canonical path (AC6).** State the committed `.pen` MUST be under
   `knowledge-base/product/design/` — never an app tree (gitignored, the #3274
   loss path).
3. **Step 5 (existing commit).** Leave as-is; it commits `brand-guide.md`. The
   new 4.5.a commit is additive and earlier in the flow (the whole point is the
   `.pen` is safe in git *before* iteration, not only at workshop end).

### Phase 3 — regression guards (sibling `.test.sh`)

**Model:** `plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` (sources
`test-helpers.sh`, uses `assert_file_exists` / `assert_eq` / grep-over-markdown).

1. **`plugins/soleur/test/ux-design-lead-open-document-snapshot-guard.test.sh`**
   (AC8, AC10):
   - `assert_file_exists` the agent.
   - Assert pre-open snapshot instruction present (grep for `before`+`open_document`
     and `sha256`/`stat`/`checksum`).
   - Assert post-open collapse gate present (grep for `collapse`/`post-open`/`fraction`/`parse failure`).
   - Assert new-file exemption present.
   - Assert the retired `cq-pencil-mcp-silent-drop-diagnosis-checklist` string is
     ABSENT (fold-in regression guard) and canonical `knowledge-base/product/design/`
     still present.
2. **`plugins/soleur/test/brand-workshop-pen-commit-after-save.test.sh`** (AC9):
   - `assert_file_exists` the brand-workshop reference.
   - Assert commit-after-save instruction for the `.pen` present (grep for
     `git add`/`commit` near `.pen`).
   - Assert canonical KB path reinforced.
3. Both files `chmod +x`. No runner edit needed — `scripts/test-all.sh:176` globs
   `plugins/soleur/test/*.test.sh`.

### Phase 4 — verify

1. `bash plugins/soleur/test/ux-design-lead-open-document-snapshot-guard.test.sh`
2. `bash plugins/soleur/test/brand-workshop-pen-commit-after-save.test.sh`
3. `bash plugins/soleur/test/ux-design-lead-output-path-guard.test.sh` (existing —
   must still pass; the fold-in must not regress it)
4. `bash scripts/test-all.sh` (full suite green, AC11)

## Observability

This plan edits agent/skill markdown and adds `.test.sh` guards. It introduces no
runtime code, no server path, no infra surface (no Files-to-Edit under
`apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or `plugins/*/scripts/`). Per
Phase 2.9 skip condition (pure-docs + test-only), the 5-field observability schema
does not apply. The behavioral signal that the guard works is the **agent halting
and surfacing the wipe** (the #3274 telemetry already demonstrated agent
`a4c23b28e3a696f34` correctly surfacing the wipe via the silent-drop checklist —
this plan makes that the documented default, detectable pre-emptively).

## Alternative Approaches Considered

| Approach | Why not chosen |
|---|---|
| Fix the adapter to refuse writing empty state over non-empty source (mitigation 1) | Pencil MCP is external, not vendored — not editable in this repo. Out of scope by construction. File upstream if a channel exists; track as a deferred non-goal (see below). |
| Wrap `open_document` in a repo-side guard script the agent must call | The agent invokes `mcp__pencil__open_document` directly via MCP; there is no repo-side shim layer to interpose. A prose HARD GATE instructing snapshot+verify is the available control surface (same pattern as the existing post-save gate). |
| Commit the `.pen` only at workshop end (step 5) | Too late — the wipe happens *during* the iteration loop (between save and re-open). The commit must land before iteration to be recoverable. |
| Block `open_document` on existing files entirely | Over-broad — re-opening an existing `.pen` to iterate is the documented, desired workflow. The fix is detect-and-halt-on-collapse, not prohibit re-open. |

**Non-Goal / Deferred:** Mitigation (1) — adapter-side empty-state refusal — is
not implementable in this repo. **Deferral tracking:** file a GitHub issue
"upstream Pencil: open_document must refuse to overwrite non-empty .pen with empty
state" labeled `blocked` (re-eval criterion: Pencil exposes a contributor channel
or vendors the adapter), referencing #3274. Without a tracking issue the deferral
is invisible.

## Domain Review

**Domains relevant:** Product (Pencil/ux-design-lead is the founder design surface;
brand-workshop is a product flow)

### Product/UX Gate

**Tier:** none (mechanical UI-surface override does NOT fire — Files to Edit are
`plugins/soleur/agents/.../*.md`, `plugins/soleur/skills/.../*.md`, and
`plugins/soleur/test/*.test.sh`; none match the `components/**/*.tsx`,
`app/**/page.tsx`, `app/**/layout.tsx`, or UI-surface-term globs. This plan changes
agent *instructions about* design tooling — it implements no user-facing UI.)
**Decision:** auto-accepted (pipeline) — NONE tier, no wireframe producer needed.
**Agents invoked:** none (Task sub-agent spawning unavailable in this planning
environment; see Errors). CPO assessment performed inline by the planner.
**Skipped specialists:** none — `ux-design-lead` is N/A here (no UI surface is
being designed; the agent is the *subject* of the edit, not a producer).
**Pencil available:** N/A (no UI surface).

#### Findings

The plan hardens the founder's design workflow against silent data loss. Product
lens: this directly protects the "Pencil is the founder's standard design surface"
positioning (brand-workshop step 4.5.a) — a silent wipe undermines that claim.
**CPO sign-off** (required by the single-user-incident threshold): the approach
(detect-and-halt + commit-for-recovery) is the correct product posture — preserve
the iteration workflow while making destruction recoverable and visible. No flow
gap or positioning concern. Sign-off recorded inline at plan time; confirm CPO
review before `/work`.

## Infrastructure (IaC)

None. No server, service, cron, secret, DNS, cert, or firewall rule introduced.
Pure docs + test change against already-provisioned tooling. (Phase 2.8 skip
condition met.)

## GDPR / Compliance

No regulated-data surface touched (no schema, migration, auth flow, API route,
`.sql`, LLM-on-session-data processing, cross-controller data movement, or new
distribution surface). Brand-survival threshold is `single-user incident`, which
triggers a consideration check — but the failure class is **local file
destruction**, not personal-data processing or exposure. No DPA, lawful-basis, or
Art. 30 implication. Gate skipped (advisory).

## Test Scenarios

1. **Wipe is caught:** Given an existing 133KB `.pen`, when `open_document` returns
   a 41-byte result, the agent halts and surfaces pre=133KB / post=41B verbatim
   (does not proceed to iterate). (Documented behavior; asserted via the
   instruction-presence test.)
2. **Legitimate open passes:** Given an existing 133KB `.pen`, when `open_document`
   returns 133KB (or a normal small delta), the agent proceeds. (No false trip:
   threshold is <50% OR ≤64 bytes.)
3. **New-file creation passes:** Given no pre-existing file, `open_document` creates
   a ~41-byte new doc; the collapse gate does not apply (exemption).
4. **Recovery path documented:** After a caught wipe, the committed `.pen`
   (mitigation 3) is recoverable via `git checkout -- <path>`.
5. **Fold-in does not regress:** The existing
   `ux-design-lead-output-path-guard.test.sh` still passes after the line-57
   citation repoint.
6. **Suite discovery:** Both new `.test.sh` files run under `bash scripts/test-all.sh`
   without a runner edit.
