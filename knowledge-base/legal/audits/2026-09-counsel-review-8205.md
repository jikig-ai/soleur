---
title: "Counsel review audit — #8205 / PR #8214 (Devin hook-matcher dead window: PA-8 §(g) merge-conditioned clarification; PA-31 §(g) non-reach clarification; compliance-posture ledger row)"
type: counsel-review
date: 2026-09-16
issue: 8205
pr: 8214
status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)
signed_off_at: 2026-09-16
signed_off_by: "CLO agent (attestation authority for the Soleur-as-tenant-zero v1 posture; the operator retains an optional veto)"
disposition: "DISCHARGED subject to ONE in-PR text correction (C1, below) that the lead applies before merge. Two artifacts in scope: knowledge-base/legal/article-30-register.md (two dated clarification brackets — PA-8 §(g) and PA-31 §(g)) and knowledge-base/legal/compliance-posture.md (one IN-PROGRESS ledger row for #8205). The diff is additions-only (no deleted token inside either artifact); it touches no Status cell, no docs/legal/** or Eleventy mirror file. Every implementation claim was checked against the shipped bodies (.devin/config.json, .claude/settings.json, plugins/soleur/hooks/hooks.json, .claude/hooks/devin-dispositions.tsv, .claude/hooks/devin-matcher-parity.test.sh, .claude/hooks/lib/hook-tool-kind.sh, plugins/soleur/hooks/browser-snapshot-credential-guard.sh, the #8155 merge commit 6c1dbcbbc, envelope-capture.md §1–§8, ADR-213 addendum, ADR-223), not against the plan. One clause is FALSE against the git record: PA-8 §(g) claims post-merge Devin reach 'requires BOTH #8155's matcher widening (merged) AND this change's HOOK_TOOL_KIND body-gate normalization — the body previously self-gated tool_name == \"Bash\" and would have fired on exec and no-opped.' #8155 (6c1dbcbbc, merged 2026-09-16) shipped BOTH halves: the ^(Bash|exec)$ matcher AND a body gate admitting exec ('$TOOL == \"Bash\" || \"$TOOL\" == \"exec\"'). At this PR's base the guard already acts on exec envelopes; the kind normalization is a conformance refactor required by this PR's own parity contract (devin-matcher-parity.test.sh T9(d)), not a precondition for reach. The clause mis-dates the defect and mis-attributes the second half of the fix. Everything else in both artifacts holds. No Art. 33 and no Art. 34 duty arises: an absent preventive control on one harness is not an Art. 4(12) event — no personal-data object was destroyed, lost, altered, or disclosed."
blocking_findings: []
required_before_merge_DISCHARGED:
  - "C1 — PA-8 §(g) 2026-09-15 CLARIFICATION bracket: correct the two-halves dependency claim. #8155 restored both halves for this guard; this change's contribution is canonical-map normalization (T9 conformance), not the second required half (exact text under §Conditions)."
optional_precision_notes:
  - "O1 — The same misattribution rides in two non-attested records: ADR-213's 2026-09-15 addendum ('Two independent fixes are required ... neither alone is sufficient ... #8214 normalizes it to HOOK_TOOL_KIND') and plugins/soleur/devin/INSTRUCTIONS.md ('its in-body tool gate is kind-normalized so it acts on exec'). Both imply the normalization is what makes the guard act on exec; the pre-change '|| exec' disjunction already did. Flagged to the lead, not conditioned — engineering records outside this attestation."
  - "O2 — compliance-posture row: 'PA-8/PA-31 §(g) carry dated merge-conditioned clarifications' — PA-31's bracket is dated but NOT merge-conditioned (it is a scoping statement true now). Literally imprecise in the plural; the register cells themselves are correct. Non-blocking."
  - "O3 — The normalized gate adds a fail-soft path the disjunction did not have: if plugins/soleur/hooks/lib/hook-tool-kind.sh is absent (partial plugin install), hook_tool_kind degrades to an identity stub, exec fails the == 'Bash' check, and the guard is silently off under Devin (mitigated only by a stderr WARN — lib/hook-tool-kind.sh documents this as the deliberate lesser evil). The register cell need not recite it, but 'requires' is additionally wrong in the weak direction: the change introduces a degradation path, it does not close one."
  - "O4 — Probe chronology is self-consistent: envelope-capture probe date 2026-09-15 precedes #8155's merge (2026-09-16 15:01Z), so 'the registration was loaded but never dispatched' was true of the soleur plugin's then-current Bash matcher at probe time. The register's parenthetical '(#8155's matcher widening merged 2026-09-16)' inside a bracket dated 2026-09-15 is internally disclosed and needs nothing."
attests:
  - "knowledge-base/legal/article-30-register.md — the two 2026-09-15 CLARIFICATION brackets added by PR #8214 ONLY (PA-8 §(g) harness-scope bracket; PA-31 §(g) Claude-CLI-scope bracket)"
  - "knowledge-base/legal/compliance-posture.md — the new IN-PROGRESS row 'Devin hook-matcher dead window' (#8205 / PR #8214)"
does_not_attest:
  - "knowledge-base/engineering/architecture/decisions/ADR-213-*.md and ADR-223-*.md, plugins/soleur/devin/INSTRUCTIONS.md, .claude/hooks/README.md (engineering records; see O1)"
  - "knowledge-base/project/specs/feat-settings-matcher-devin-audit/envelope-capture.md (evidence file, relied upon)"
  - "The hook bodies, registries, ledger and parity test themselves (technical controls; counsel attests the register's statements about them, not their correctness)"
art_33_triggered: false
art_34_triggered: false
re_evaluation_triggers: "The post-merge runtime trace (ledger AC12 / 'runtime trace pending'): if it shows the guard does NOT deny an unrouted agent-browser snapshot under Devin, PA-8 §(g)'s 'coverage claimed for the mechanism only' must be re-opened and the dead window re-measured forward from #8155's merge. Also: any change to plugins/soleur/hooks/lib/hook-tool-kind.sh's fail-soft sourcing (O3's silent-off path); Devin shipping multi_edit/notebook_edit/apply_patch (speculative passthrough arms in the kind map, per its own header); #8205 closing moves the posture row to Completed. Standing external-counsel triggers unchanged."
---

# Counsel review audit — #8205 / PR #8214 (Devin hook-matcher dead window)

This file is the load-bearing evidence for the ship Phase 5.5 Counsel-Review CLO-Attestation Gate on
PR #8214 (issue #8205). Two legal artifacts are in scope: the Article 30 register and the compliance
posture ledger. The CLO agent is the v1 attestation authority; the operator holds an optional veto.

## Scope and limit check

- **Additions only.** Both hunks in `article-30-register.md` are bracket insertions (`[2026-09-15
  CLARIFICATION (#8205) …]` appended to PA-8 §(g) and PA-31 §(g)); `compliance-posture.md` gains one
  row. No deleted token inside either artifact; no Status cell touched; no `docs/legal/**` or
  Eleventy mirror file engaged.
- **Merge-conditioning is stated, not smuggled.** PA-8's bracket is headed "merge-conditioned on
  #8214 (#8155's matcher widening merged 2026-09-16)" — the register does not claim live Devin
  coverage; it claims the mechanism only, pending a post-merge runtime trace. That hedge matches the
  ledger's own `runtime trace pending (AC12)` evidence column.
- **No `[DRAFT — pending CLO/counsel review` markers** anywhere in the PR diff (`git diff
  origin/main...HEAD | grep DRAFT` → exit 1).

## Drift table

| # | Claim added | Checked against (file / anchor) | Verdict |
|---|---|---|---|
| D1 | PA-8 §(g): the guard is a `PreToolUse` deny registered on the Claude tool name `Bash`; under Devin the registration was loaded but never dispatched, measured dead (envelope-capture §1) | `.claude/settings.json` PreToolUse `"matcher": "Bash"` → `browser-snapshot-credential-guard.sh`; envelope-capture §1 (`Bash` never fired under `.devin` + `.claude`; "TitleCase tool names are dead in every registry"); probe date 2026-09-15 precedes #8155's merge, so the plugin matcher under test was still `Bash` | **Holds** |
| D2 | PA-8 §(g): post-merge Devin reach requires BOTH #8155's `^(Bash\|exec)$` widening AND this change's `HOOK_TOOL_KIND` normalization; "the body previously self-gated `tool_name == "Bash"` and would have fired on `exec` and no-opped" | `git show 6c1dbcbbc` (#8155, merged 2026-09-16): matcher `"Bash"` → `"^(Bash\|exec)$"` AND body `[[ "$TOOL" == "Bash" ]]` → `[[ "$TOOL" == "Bash" \|\| "$TOOL" == "exec" ]]` in the same commit; `git show origin/main:…/browser-snapshot-credential-guard.sh` line 93 already admits `exec`; this PR's diff only swaps the disjunction for `hook_tool_kind` (T9(d) of the new parity test flags the old raw-name form) | **FALSE — #8155 shipped both halves; normalization is T9-conformance, not a required half → C1** |
| D3 | PA-8 §(g): the disposition row is `covered-by-plugin`; Claude `Bash` reach unchanged; no breach-register row | `.claude/hooks/devin-dispositions.tsv` rows 57 and 114 (`covered-by-plugin`, "runtime trace pending (AC12)"); `hooks.json` `^(Bash\|exec)$` is Devin-live per T9(b); Claude-side registration untouched by the diff | **Holds** (the hedge is correct; the dependency it sits on is C1) |
| D4 | PA-31 §(g): the fleet spawns `claude --print`; Devin hook semantics do not reach it; the `.devin` corpus is not this Activity's containment and the cell claims nothing from it | `_cron-claude-eval-substrate.ts` spawn path (pre-existing); `.devin/config.json` binds repo-local session hooks only; ledger scopes every row to repo/plugin registries | **Holds** — a non-reach statement, correctly claims nothing |
| D5 | Posture row: `.claude/settings.json` `Bash`/`Write\|Edit`/SessionStart source matchers, plugin `hooks.json` `Bash`, and `.claude` permissions were all dead under Devin, measured in envelope-capture.md | EC§1 (`Bash`/`Write`/`AskUserQuestion` never fired), EC§3 (all non-empty SessionStart matchers dead in all three registries), EC§6 (`.claude` `permissions.{allow,deny}` NOT imported — measured bypass under `smart`/`dangerous`) | **Holds** (plugin `Bash`-dead is the pre-#8155 window; §1's conclusion generalizes to every registry) |
| D6 | Posture row: `devin/INSTRUCTIONS.md` asserted the PA-8 §(g) credential guard was supported there | Diff removes "Devin supports the bundled Bash credential guard and Stop hooks" | **Holds** |
| D7 | Posture row: remediated by per-harness registries (ADR-223), `HOOK_TOOL_KIND` normalization, dispositions ledger + parity test | ADR-223 exists and matches; `.claude/hooks/lib/hook-tool-kind.sh` + `hook-input.sh` export `HOOK_TOOL_KIND`; `devin-dispositions.tsv` (172 lines, per-registration rows) + `devin-matcher-parity.test.sh` (T1–T9) exist; the suite is auto-discovered by `scripts/test-all.sh` `.claude/hooks/*.test.sh` glob | **Holds** |
| D8 | Posture row: "The guard's Devin dispatch additionally required #8155's `^(Bash\|exec)$` widening (merged)" | As D2 | **Holds** — the posture row attributes dispatch to #8155 only; it does not repeat the register's error |
| D9 | Posture row: "No Art. 33/34 duty, no breach-register row: an absent control on one harness is not an Art. 4(12) event" | Art. 4(12) requires destruction/loss/alteration/unauthorised disclosure of personal data; the dead window is an absent preventive control with no personal-data object implicated | **Holds** — legally sound |

## Findings

- **F1 (C1).** The dependency claim. PA-8 §(g)'s bracket asserts the guard's Devin reach "requires
  BOTH #8155's matcher widening (merged) AND this change's `HOOK_TOOL_KIND` body-gate normalization,"
  justified by "the body previously self-gated `tool_name == \"Bash\"` and would have fired on `exec`
  and no-opped." `git show 6c1dbcbbc` shows #8155 changed both lines in one commit: the hooks.json
  matcher to `^(Bash|exec)$` and the body gate to admit `exec`. At this PR's merge-base the guard
  already acts on `exec` envelopes (matcher dispatches, body passes, deny contract measured honored
  at EC§5). What this PR contributes is replacing the ad-hoc two-name disjunction with the canonical
  kind map — which is required by this PR's *own* parity test (T9(d) flags a raw `HOOK_TOOL_NAME`/
  `TOOL`-vs-kind gate in any Devin-bound hook), not by the guard's reach. The sentence mis-dates the
  fire-then-no-op defect (true pre-#8155, false at base) and mis-attributes the second half of the
  fix to this PR. Direction of error: it understates the control's existing reach window (dead
  window ended at #8155's merge, not at #8214's), so it is not an over-claim of protection — but it
  is a false statement of fact inside a statutory register's dated clarification, which this
  register's own discipline does not permit. Ruled a correction rather than a block, per the #8189
  precedent: the fix edits only text this PR inserts.
- **F2.** The posture row does not inherit the error. Its attribution ("dispatch additionally
  required #8155's widening (merged)") is correct, and its "mechanism only until the post-merge
  trace" hedge matches the ledger. The only imprecision is the plural "merge-conditioned
  clarifications" covering PA-31, whose bracket is unconditional — O2.
- **F3.** No Art. 33/34 analysis needed beyond the row's own: an undocumented-or-absent TOM on one
  harness is an Art. 30 accuracy defect (here being corrected) and an Art. 5(2) accountability
  record, not an Art. 4(12) breach. No personal-data object was exposed by the matcher being dead.
- **F4.** `skip`/`n/a` ledger rows are not over-claimed anywhere in the legal prose: the posture row
  claims the *remediation mechanism* (per-harness registries + ledger + parity test), not blanket
  coverage, and the register claims "the mechanism only" for the one hook it names. Hooks the
  ledger marks `skip`/`n/a` (background-poll-prefer-monitor, memory-backstop, welcome-hook, codex
  surface, agent-token-tee, durable-reminder, monitor-* rows) are not asserted as covered in either
  artifact. UNMEASURED items in EC§6 (`ask`, `defer`, `~`-expansion, `Exec()` prefix semantics,
  PermissionRequest) are claimed by neither artifact.

## Conditions

One correction, to text this PR inserts. File: `knowledge-base/legal/article-30-register.md`,
PA-8 §(g), the `[2026-09-15 CLARIFICATION (#8205) …]` bracket.

**C1.** Replace:

> Post-merge Devin reach requires BOTH #8155's `^(Bash\|exec)$` matcher widening (merged) AND this change's `HOOK_TOOL_KIND` body-gate normalization — the body previously self-gated `tool_name == "Bash"` and would have fired on `exec` and no-opped.

with:

> Post-merge Devin reach rests on #8155, which shipped BOTH halves for this guard in one commit (merged 2026-09-16): the plugin matcher `Bash` → `^(Bash\|exec)$` AND the in-body gate widened to admit `exec` (`tool_name == "Bash" || "exec"`). Before #8155 the body self-gated `tool_name == "Bash"`, which is the fire-then-no-op defect class — matcher widened, body not — but at this change's base the guard already acts on `exec` envelopes. This change's contribution is replacing the ad-hoc disjunction with the canonical `HOOK_TOOL_KIND` map (`exec` → `Bash`, `lib/hook-tool-kind.sh`) — a conformance requirement of this change's own parity contract (`devin-matcher-parity.test.sh` T9), and a consistency fix for the hook corpus, not a precondition for this guard's reach.

No other text change is required. O1–O4 are non-blocking.

## Verification commands (re-runnable from the worktree)

- `git show 6c1dbcbbc -- plugins/soleur/hooks/hooks.json plugins/soleur/hooks/browser-snapshot-credential-guard.sh | grep -n 'matcher\|TOOL'` → `^(Bash|exec)$` and `== "Bash" || == "exec"` added in the same commit (C1).
- `git show -s --format='%ci' 6c1dbcbbc` → 2026-09-16 (D2; bracket's parenthetical date is exact).
- `git show origin/main:plugins/soleur/hooks/browser-snapshot-credential-guard.sh | grep -n '"exec"'` → line 93, the `exec`-admitting gate already on main (C1).
- `grep -n 'browser-snapshot' .claude/settings.json plugins/soleur/hooks/hooks.json .claude/hooks/devin-dispositions.tsv` → settings `Bash` registration, plugin `^(Bash|exec)$`, ledger rows 57/114 `covered-by-plugin` (D1, D3).
- `grep -n 'HOOK_TOOL_KIND' .claude/hooks/lib/hook-input.sh` → exported at line 397 (D7).
- `grep -rn 'UNVERIFIED\|UNMEASURED' knowledge-base/project/specs/feat-settings-matcher-devin-audit/envelope-capture.md` → §6 `ask`/`defer`/`~`/`Exec()`/PermissionRequest; confirm neither legal artifact claims them (F4).
- `git diff origin/main...HEAD | grep -c 'DRAFT'` → 0.

## Lead application record

Applied 2026-09-16 by the ship-phase lead. **C1 applied verbatim** to
`knowledge-base/legal/article-30-register.md` PA-8 §(g). **O1 applied** — the
same misattribution corrected in `ADR-213`'s addendum (the "two independent
fixes / neither alone is sufficient" paragraph now records that #8155 shipped
both halves) and in `plugins/soleur/devin/INSTRUCTIONS.md` (the
kind-normalization clause no longer implies this change is what makes the gate
act on `exec`). **O2 applied** — the compliance-posture row's
"merge-conditioned clarifications" plural reduced to "dated clarifications"
(PA-31's bracket is dated, not merge-conditioned). **O3** noted, no change —
the fail-soft stub is deliberate and WARNed to stderr per the
`lib/hook-tool-kind.sh` header. **O4** noted, no change — probe chronology is
self-consistent as recorded (probe 2026-09-15 precedes the #8155 merge
2026-09-16). Waivers added: `scripts/lint-legal-registers.sh`
`NOT_TRANSCRIBED` and the `breach-register.md` waiver table, per the
#8043/#8189 precedent.
