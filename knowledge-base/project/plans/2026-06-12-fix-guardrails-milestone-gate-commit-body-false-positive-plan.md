---
title: "fix: guardrails require-milestone gate false-matches gh issue create in commit-message bodies"
issue: 5192
branch: feat-one-shot-guardrails-milestone-gate-5192
type: bug
lane: procedural
brand_survival_threshold: none
date: 2026-06-12
---

# 🐛 fix: guardrails `require-milestone` gate false-matches `gh issue create` in commit-message bodies

## Enhancement Summary

**Deepened on:** 2026-06-12
**Passes run:** halt gates 4.6/4.7/4.8/4.9 (all pass), precedent-diff (4.4), verify-the-negative (4.45), code-reviewer + code-simplifier review agents.

### Key improvements from deepen
1. **D-P0-A (fail-open trap):** `ship-operator-step-gate.sh` soft-sources `incidents.sh` (`2>/dev/null || true`); a direct `strip_command_bodies` call under `set -e` would abort + fail-OPEN. Added the `command -v` guard + raw-`$CMD` fallback (AC8 + Phase 3 step 1).
2. **D-P1-A (false-passing test):** `follow-through-directive-gate.sh:54` has a second early-exit requiring `--label follow-through`; its FP fixture must carry that label or the test exits early and never exercises the strip (AC7 + Phase 3 step 2).
3. **D-CI (silent-skip test):** `scripts/test-all.sh:177` globs `.claude/hooks/*.test.sh` but NOT `.claude/hooks/lib/*.test.sh`. Unit tests go in the existing globbed `.claude/hooks/incidents.test.sh`, not a new `lib/incidents.test.sh` (corrects the original "Files to Create: None" / wrong-path error).
4. **D-simplify:** lightened the fail-toward-firing test to a fallback-clause grep (AC9, was a brittle perl-absent execution test); cut the full-header-rewrite mandate to a one-line repoint comment per changed grep (AC11); dropped the LARP `Closes #5192` AC (it is workflow-gate `wg-use-closes-n-in-pr-body`, true of every PR).

### Verified-correct (no change needed)
- The trigger-on-`$SCAN` / `--repo`+`--milestone`-on-`$COMMAND` asymmetry in require-milestone is correct: on a commit-body FP the strip removes the trigger so the `--milestone` check (line 151) is never reached; on a real create the `--repo`/`--milestone` flags live outside quotes and survive the strip.
- `block-commit-on-main` / `block-conflict-markers` are NOT FP-reachable (they gate the real `git commit`); leaving them on raw `$COMMAND` is correct.
- The perl strip cannot blank a real chained `&& gh issue create` (it blanks only quote/heredoc spans; the heredoc sub preserves the terminator + everything after).

## Overview

The `require-milestone` guard in `.claude/hooks/guardrails.sh:121` detects `gh issue create` with a line-anchored regex `(^|&&|\|\||;)\s*gh\s+issue\s+create`. Because `grep` matches per line and `^` matches the start of **any** line in a multi-line `$COMMAND`, a `git commit -m "…body…"` whose message body wraps the literal `gh issue create` onto its own line trips the gate — even though the command being run is `git commit`, not an issue creation. The whole Bash tool call (often `git add … && git commit …`) is denied.

Observed twice while committing the operator-digest feature (#5085), whose commit message documented that a workflow allowlist deliberately omits the issue-create capability.

**Fix:** strip `git commit -m/-F` message bodies and heredocs from the scanned command string **before** the command-detection grep, mirroring the canonical strip that `.claude/hooks/pre-merge-rebase.sh:64-65` already does for the same self-interception class. The strip is extracted into a **shared `lib/incidents.sh` helper** so the milestone gate, the same-file `git stash` gate, and every sibling `gh pr ready|merge` gate get the fix in one place (and `pre-merge-rebase.sh`'s inline copy is replaced by the helper to remove duplication).

This is a `.claude/hooks/` tooling/workflow change. No product, UI, infra, or regulated-data surface is touched.

## Research Reconciliation — Spec (issue body) vs. Codebase

| Issue-body claim | Codebase reality (verified) | Plan response |
|---|---|---|
| Bug at `.claude/hooks/guardrails.sh:121` | Confirmed — line 121 is the `require-milestone` detection grep. | Fix this gate via the shared strip. |
| `pre-merge-rebase.sh` already strips commit bodies/heredocs | Confirmed — `pre-merge-rebase.sh:64-65` inlines a `perl -0777` strip into a `SCAN` var; it is the **only** hook today with a true pre-detection strip. | Extract that exact perl one-liner into `lib/incidents.sh` and have `pre-merge-rebase.sh` consume the helper (no behavior change there). |
| "Sweep: audit every sibling hook with the same `(^|&&|\|\||;)` line-anchor" | 6 non-test hooks use the anchor: `guardrails.sh`, `cla-signed-author-gate.sh`, `follow-through-directive-gate.sh`, `ship-runbook-ssh-gate.sh`, `ship-operator-step-gate.sh`, `ship-unpushed-commits-gate.sh`. See Sweep Audit table. | Fix all gates whose trigger literal is a *phrase that can appear in a commit body*; leave true-commit gates alone (see table). |
| Learning `2026-06-12-milestone-gate-false-matches-gh-issue-create-in-commit-body.md` exists | Confirmed present. | Cite as provenance; do not re-author. |
| Prior learning `2026-05-29-command-detection-hook-self-interception-and-heredoc-fp.md` exists | Confirmed present — documents the bare-`-F - <<EOF` heredoc-no-quotes gap that `test-design-reviewer` caught on #4600. | Carry forward: the helper MUST handle BOTH heredoc-no-quotes and quoted shapes; tests MUST cover the bare-heredoc shape. |

## Sweep Audit — which line-anchored gates are FP-reachable in a commit body

The defect fires only when the gate's **trigger literal is a phrase** that can plausibly sit at a line-start inside a `git commit` message body while the actual command is `git commit`. Gates that trigger on `git commit` itself are NOT false positives — a commit that mentions "git commit" in its body still *is* a commit, and the gate correctly evaluates branch/conflict state.

| Hook : gate | Trigger literal | FP-reachable in commit body? | Action |
|---|---|---|---|
| `guardrails.sh` : require-milestone | `gh issue create` | **YES** (the reported bug) | Strip before detect |
| `guardrails.sh` : block-stash-in-worktrees | `git stash` | **YES** — denies *unconditionally* on match; a commit body documenting "never git stash" is blocked | Strip before detect |
| `guardrails.sh` : block-commit-on-main | `git commit` | NO — gates the real commit | No change |
| `guardrails.sh` : block-conflict-markers | `git commit` / `git merge --continue` | NO — gates the real commit | No change |
| `cla-signed-author-gate.sh` | `gh pr ready\|merge` | **YES** — proceeds past early-exit and may deny the commit | Strip before detect |
| `ship-unpushed-commits-gate.sh` | `gh pr merge` | **YES** | Strip before detect |
| `ship-operator-step-gate.sh` | `gh pr ready\|merge --auto` | **YES** | Strip before detect |
| `ship-runbook-ssh-gate.sh` | `gh pr ready\|merge --auto` | **YES** | Strip before detect |
| `follow-through-directive-gate.sh` | `gh issue create` | **YES** | Strip before detect |
| `pre-merge-rebase.sh` | `gh pr merge` | already fixed (#4600) | Consume shared helper (dedup only) |

Note: `follow-through-directive-gate.sh` matched the initial sweep grep because it uses a `perl -0777` regex for **body extraction** (`--body "…"`), NOT for pre-detection stripping. Its line-47 trigger grep runs against raw `$CMD` and is therefore FP-reachable — include it.

### Research Insights — Precedent-Diff Gate (deepen Phase 4.4)

The strip is a **pattern-bound behavior with exactly one in-repo precedent**: `pre-merge-rebase.sh:64-65` (the only hook today with a true pre-detection strip). The helper body MUST be this verbatim (do NOT re-derive — the regex encodes heredoc-marker preservation + escape-aware quote-strip validated on #4600):

```bash
SCAN=$(printf '%s' "$CMD" | perl -0777 -pe \
  's/(<<-?\s*["'\'']?)(\w+)(["'\'']?)(.*?)(\n[ \t]*\2\b)/$1$2$3$5/gs; s/"(?:[^"\\]|\\.)*"/ /gs; s/'\''(?:[^'\''\\]|\\.)*'\''/ /gs;' 2>/dev/null || printf '%s' "$CMD")
```

The heredoc sub preserves `$5` (closing-delimiter + everything after), so a real chained `&& gh pr merge` / `&& gh issue create` AFTER the terminator still fires — this is what makes the strip safe (T8 in `pre-merge-rebase.test.sh`). `follow-through-directive-gate.sh:73`'s `perl -0777` is a DIFFERENT primitive (extracts `--body` for directive validation) and stays unchanged. No other strip precedent exists; the pattern is otherwise novel, hence the dedup-into-helper.

## User-Brand Impact

**If this lands broken, the user experiences:** a legitimate `git add && git commit` is denied mid-session because the commit message merely *documents* `gh issue create` / `gh pr merge` / `git stash`, forcing the operator to reword prose around a security-boundary commit (the exact #5085 foot-gun).

**If this leaks, the user's data/workflow/money is exposed via:** N/A — this is a developer-tooling PreToolUse hook with no user-data surface. The only failure mode of concern is the *opposite* of a leak: the fix must NOT weaken the gates so a real bare `gh issue create` (no `--milestone`) or unreviewed `gh pr merge` slips through.

**Brand-survival threshold:** none. Reason: `.claude/hooks/` developer-tooling change; no user-facing artifact, no regulated-data surface, no production write path.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — milestone gate FP fixed (allow):** a `git commit -m "<body>"` whose body contains a line beginning `gh issue create` (no `--milestone`) is NOT blocked. New `guardrails.test.sh` fixture asserts `<none>`.
- [x] **AC2 — real bare create still gated (deny):** `gh issue create --title x --body y` (our repo, no `--milestone`) STILL denies. Existing `guardrails.test.sh` cases stay green (run the file; `Fail: 0`).
- [x] **AC3 — stash gate FP fixed (allow):** a `git commit -m "<body>"` whose body contains a line beginning `git stash` is NOT blocked; a real `git stash` chained/standalone STILL denies (two fixtures: one allow, one deny).
- [x] **AC4 — heredoc-no-quotes shape covered:** a `git commit -F - <<EOF … gh issue create … EOF` (bare heredoc body) is NOT blocked, AND a real `gh pr merge` *after* the closing `EOF` STILL fires (mirrors `pre-merge-rebase.test.sh` T-FP4 + T8). Add to `guardrails.test.sh`.
- [x] **AC5 — shared helper extracted + unit-tested:** `lib/incidents.sh` exposes `strip_command_bodies` (name TBD at /work; verify no collision via `grep -n 'strip_command_bodies' .claude/hooks/lib/incidents.sh` — confirmed zero at plan time). Unit tests added to the **existing globbed** `.claude/hooks/incidents.test.sh` (NOT a new `lib/incidents.test.sh` — see Files to Create rationale) assert: (a) quoted `-m "…"` body blanked, (b) bare heredoc body blanked, (c) content AFTER a heredoc terminator preserved (real chained command still visible), (d) a command with no quotes/heredoc passes through unchanged.
- [x] **AC6 — pre-merge-rebase.sh consumes the helper, no behavior change:** `pre-merge-rebase.sh` sources the helper and replaces its inline perl `SCAN=` line; `bash .claude/hooks/pre-merge-rebase.test.sh` stays green (`Fail: 0`), including T-FP4 + T8.
- [x] **AC7 — sibling gh-pr gates fixed:** `cla-signed-author-gate.sh`, `ship-unpushed-commits-gate.sh`, `ship-operator-step-gate.sh`, `ship-runbook-ssh-gate.sh`, `follow-through-directive-gate.sh` strip via the helper before their trigger grep. For each, add one commit-body-FP `allow` fixture to its `.test.sh` AND confirm its existing real-trigger `deny`/early-exit cases stay green. **`ship-runbook-ssh-gate.sh` must add `source .../lib/incidents.sh`** (currently unsourced — confirmed). **`follow-through-directive-gate.sh`'s FP fixture MUST include `--label follow-through` in the commit-body line** — the hook has a SECOND early-exit at `:54` requiring that label, so a body containing only `gh issue create` exits early at `:54` (a `<none>` that masks the strip path, not exercises it). See deepen finding D-P1-A.
- [x] **AC8 — soft-source hooks hardened (fail-open guard):** `ship-operator-step-gate.sh:35` sources `incidents.sh` with `2>/dev/null || true` (soft-fail). Adding a hard `strip_command_bodies` call under `set -e` would abort + fail-OPEN the gate if the lib fails to load. Each soft-source consumer MUST guard the call: `if command -v strip_command_bodies >/dev/null 2>&1; then SCAN=$(strip_command_bodies "$CMD"); else SCAN="$CMD"; fi` (fall back to raw `$CMD` = fail-toward-firing). Verify with `grep -n '2>/dev/null || true' .claude/hooks/*.sh` at Phase 0 and harden every match that gains a helper call.
- [x] **AC9 — fail-toward-firing helper fallback (presence-asserted):** the helper ends in `|| printf '%s' "$1"` (verbatim from `pre-merge-rebase.sh:65`) so a perl error returns the raw command (over-detect), never a silent bypass. Assert via a grep that the fallback clause is present in the helper (`grep -F '|| printf' .claude/hooks/lib/incidents.sh`) — do NOT engineer a brittle perl-absent PATH-shadow execution test (the one-liner is already shipped + proven on #4600).
- [x] **AC10 — full hook suite green:** `for f in .claude/hooks/*.test.sh .claude/hooks/lib/*.test.sh; do bash "$f"; done` all pass. (These run in CI via `scripts/test-all.sh:177`.)
- [x] **AC11 — repoint comment at each changed grep:** at every grep changed to scan `$SCAN`, add a one-line `# scans $SCAN (commit bodies/heredocs stripped — see lib/incidents.sh)` comment so the next reader knows why detection runs on `$SCAN`. (Do NOT rewrite each hook's full header block — load-bearing comment only.)

## Implementation Phases

### Phase 0 — Preconditions (verify, do not assume)
1. `grep -n 'strip_command_bodies' .claude/hooks/lib/incidents.sh` → confirm no name collision (verified zero at plan time; pick the final helper name).
2. Re-read `pre-merge-rebase.sh:64-65` and copy the perl one-liner **verbatim** as the helper body — do NOT re-derive the regex (it already encodes the heredoc-marker-preserving + quote-strip semantics validated on #4600).
3. Confirm `perl` is available in CI (`command -v perl` — present locally at `/usr/bin/perl` v5.40).
4. Confirm `ship-runbook-ssh-gate.sh` does NOT currently source `lib/incidents.sh` (it doesn't; also has no `emit_incident` call, so the source is safe to add purely for the helper) — Phase 3 adds the source line.
5. **Identify soft-source consumers:** `grep -n '2>/dev/null || true' .claude/hooks/*.sh` → `ship-operator-step-gate.sh:35` is soft-fail. Every soft-source hook that gains a `strip_command_bodies` call needs the `command -v` guard (AC8). Hard-source hooks (`guardrails.sh:19`, `cla-signed-author-gate.sh`, `ship-unpushed-commits-gate.sh`, `follow-through-directive-gate.sh`, `pre-merge-rebase.sh`) can call the helper directly.
6. Confirm `scripts/test-all.sh:177` globs `.claude/hooks/*.test.sh` but NOT `.claude/hooks/lib/*.test.sh` → put the new unit tests in the existing globbed `.claude/hooks/incidents.test.sh`, not a new `lib/incidents.test.sh` (which CI would silently skip).

### Phase 1 — Shared helper (TDD: test first)
1. Write failing unit tests in the existing `.claude/hooks/incidents.test.sh` for `strip_command_bodies` covering AC5 (a)-(d) + the AC9 fallback-clause grep.
2. Add `strip_command_bodies` to `lib/incidents.sh`: takes the command on stdin or `$1`, returns the SCAN string. Body = the `pre-merge-rebase.sh:64-65` perl pipeline verbatim, with `|| printf '%s' "$CMD"` fail-toward-firing fallback.
3. Green the unit tests.

### Phase 2 — guardrails.sh (the reported bug + stash FP)
1. Derive `SCAN=$(strip_command_bodies "$COMMAND")` once, after `COMMAND` is set (line 26-30) and before the require-milestone gate (line 121). One perl fork per Bash PreToolUse invocation is acceptable overhead — the hook already forks `jq` + several greps; do NOT derive per-gate. (Resolves deepen finding D-P2-A: the single top-of-file derivation is the chosen model; the Sharp-Edges "runs inside each gate's if" wording is superseded by this.)
2. Change the **require-milestone** detection grep (line 121) and the **block-stash** detection grep (line 168) to scan `$SCAN`.
3. Leave block-commit-on-main (43), block-conflict-markers (101) scanning `$COMMAND` — they gate real commits (per Sweep Audit). Add a one-line comment at each explaining why they intentionally do NOT use `$SCAN`.
4. Add `guardrails.test.sh` fixtures: AC1 (commit-body `gh issue create` → allow), AC3 (commit-body `git stash` → allow; real `git stash` → deny), AC4 (bare-heredoc → allow; chained-after-heredoc → deny). Keep all existing cases green.

### Phase 3 — sibling gh-pr / follow-through gates
1. For each of `cla-signed-author-gate.sh`, `ship-unpushed-commits-gate.sh`, `ship-operator-step-gate.sh`, `ship-runbook-ssh-gate.sh`, `follow-through-directive-gate.sh`: ensure the helper is reachable (add `source .../lib/incidents.sh` to `ship-runbook-ssh-gate.sh`), derive `SCAN`, point the trigger grep at `$SCAN`.
   - **Soft-source guard (AC8):** for `ship-operator-step-gate.sh` (sources with `2>/dev/null || true`), use `if command -v strip_command_bodies >/dev/null 2>&1; then SCAN=$(strip_command_bodies "$CMD"); else SCAN="$CMD"; fi` so a failed lib load falls back to raw `$CMD` (fail-toward-firing) instead of `set -e`-aborting + failing OPEN. Hard-source hooks call the helper directly.
2. Add one commit-body-FP `allow` fixture per `.test.sh`; keep existing trigger cases green.
   - **`follow-through-directive-gate.sh` fixture (AC7):** the fixture command MUST carry `--label follow-through` on the stripped line (e.g. `git commit -m $'note\ngh issue create --label follow-through ...\n'`) so the test reaches the strip path, not the unrelated `:54` label early-exit. A bare `gh issue create` in the body exits at `:54` and false-passes.

### Phase 4 — pre-merge-rebase.sh dedup
1. Replace the inline `SCAN=$(printf … perl -0777 …)` at line 64-65 with `SCAN=$(strip_command_bodies "$CMD")`.
2. `bash .claude/hooks/pre-merge-rebase.test.sh` → `Fail: 0` (esp. T-FP4 bare-heredoc, T8 merge-after-heredoc).

### Phase 5 — comments + full suite
1. Add the one-line `# scans $SCAN …` repoint comment at each changed grep (AC11). Do NOT rewrite full header blocks.
2. Run AC10 full-suite loop; all green.

## Test Scenarios

| ID | Input (`tool_input.command`) | Hook | Expect |
|---|---|---|---|
| T1 | `git add . && git commit -m $'fix\ngh issue create must include --milestone\n'` | guardrails | allow (`<none>`) |
| T2 | `gh issue create --title x --body y` | guardrails | deny |
| T3 | `git commit -m $'doc\ngit stash is banned\n'` | guardrails | allow |
| T4 | `git stash` | guardrails | deny |
| T5 | `git commit -F - <<EOF`…`gh issue create`…`EOF` | guardrails | allow |
| T6 | `git commit -F - <<EOF`…`EOF`<br>`&& gh pr merge 7` | ship-unpushed / pre-merge | deny (real merge after terminator still fires) |
| T7 | `git commit -m $'note\ngh pr ready\n'` | cla / ship-operator | allow |
| T8 | unit: `strip_command_bodies` on quoted + bare-heredoc + no-quote inputs | lib | blanked / blanked / unchanged |

## Open Code-Review Overlap

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
```
Files to edit: `.claude/hooks/{guardrails,cla-signed-author-gate,ship-unpushed-commits-gate,ship-operator-step-gate,ship-runbook-ssh-gate,follow-through-directive-gate,pre-merge-rebase}.sh`, `.claude/hooks/lib/incidents.sh`, and the matching `*.test.sh`. Run the per-path `jq` overlap check in Phase 0; record matches + disposition (fold-in / acknowledge / defer) here, or **None** if zero.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — `.claude/hooks/` developer-tooling change. No Product/UI surface (no files under `components/**`, `app/**/page.tsx`, etc.), no finance/legal/sales/marketing/support implications.

## Observability

Skipped — pure developer-tooling change under `.claude/hooks/` with no `apps/*/server/`, `apps/*/src/`, `apps/*/infra/`, or new-infrastructure surface. Hook deny/allow decisions already emit incidents via `emit_incident` (unchanged). The new fixtures + unit tests ARE the observability for this change (CI-gated via `scripts/test-all.sh`).

## Infrastructure (IaC)

Skipped — no server, service, cron, secret, DNS, cert, or vendor account introduced. Pure edits to existing `.claude/hooks/` shell + test files.

## Files to Edit

- `.claude/hooks/lib/incidents.sh` — add `strip_command_bodies` helper (perl one-liner verbatim from `pre-merge-rebase.sh:64-65` + fail-toward-firing fallback).
- `.claude/hooks/guardrails.sh` — `SCAN` derivation; point require-milestone (121) + block-stash (168) at `$SCAN`; comment why block-commit/conflict stay on `$COMMAND`; add the AC11 repoint comment at each changed grep.
- `.claude/hooks/guardrails.test.sh` — add AC1/AC3/AC4 fixtures.
- `.claude/hooks/cla-signed-author-gate.sh` + `.test.sh` — strip before detect; FP fixture.
- `.claude/hooks/ship-unpushed-commits-gate.sh` + `.test.sh` — strip before detect; FP fixture.
- `.claude/hooks/ship-operator-step-gate.sh` + `.test.sh` — strip before detect with the **`command -v` soft-source guard** (AC8); FP fixture.
- `.claude/hooks/ship-runbook-ssh-gate.sh` + `.test.sh` — **add** `source lib/incidents.sh`; strip before detect; FP fixture.
- `.claude/hooks/follow-through-directive-gate.sh` + `.test.sh` — strip before detect (trigger grep only; body-extraction perl unchanged); FP fixture **must carry `--label follow-through`** (AC7).
- `.claude/hooks/pre-merge-rebase.sh` — replace inline `SCAN=` perl with helper call (dedup, no behavior change).

## Files to Create

None. **Test-placement decision (deepen finding D-CI):** the `strip_command_bodies` unit tests land in the **existing** `.claude/hooks/incidents.test.sh` (the hooks-root file that already tests `lib/incidents.sh`'s rotation/bypass paths), NOT a new `.claude/hooks/lib/incidents.test.sh`. Reason: `scripts/test-all.sh:177` globs `.claude/hooks/*.test.sh` but **NOT** `.claude/hooks/lib/*.test.sh` — a new `lib/incidents.test.sh` would be a silent CI no-op (the same pre-existing gap that leaves `lib/session-state.test.sh` uncovered). Appending to the globbed root file is the zero-risk path. (Out of scope: wiring `.claude/hooks/lib/*.test.sh` into the glob to cover `session-state.test.sh` — note it for a follow-up, do not fold here.)

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty or omits the threshold fails `deepen-plan` Phase 4.6. It is filled above (threshold: none, with reason).
- **Develop the hook through committed fixtures only.** Per `2026-05-29-command-detection-hook-self-interception-and-heredoc-fp.md`: a command-detection hook is *live against the agent's own shell*. Never put an unquoted trigger literal (`gh issue create`, `gh pr merge`, `git stash`) in an ad-hoc Bash tool call while editing these hooks — it self-intercepts. Drive every trigger-literal test input through the `*.test.sh` files run via plain `bash …test.sh`.
- **Copy the perl regex verbatim; do not re-derive.** The `pre-merge-rebase.sh:64-65` one-liner already encodes the heredoc-marker-preserving + escape-aware quote-strip semantics validated on #4600. The bare-heredoc-no-quotes shape (`-F - <<EOF`) is the gap the first #4600 implementation missed; the verbatim copy already handles it.
- **Do not strip for `git commit` / `git merge --continue` gates.** block-commit-on-main and block-conflict-markers correctly gate the *real* commit; stripping their detection would be a no-op at best and risks confusion. Only phrase-detecting gates (`gh issue create`, `gh pr ready|merge`, `git stash`) need the strip.
- **Fail toward firing.** If perl is absent or errors, the helper must return the raw command so a real bare `gh issue create` / unreviewed `gh pr merge` is still detected. Mirror `|| printf '%s' "$CMD"`.
- `lib/incidents.sh` is sourced on every Bash PreToolUse invocation — keep `strip_command_bodies` a single perl fork. Derive `SCAN` **once per hook** at the top (after `COMMAND`/`CMD` is set, before any trigger grep), NOT per-gate — one perl fork per invocation, acceptable alongside the existing `jq` + grep overhead. (This supersedes any "run inside the gate's `if`" framing — guardrails.sh has two phrase-detecting gates that share the single top-of-file `SCAN`.)
- **Soft-source fail-open trap:** `ship-operator-step-gate.sh` sources `incidents.sh` with `2>/dev/null || true`. Calling `strip_command_bodies` directly there under `set -e` aborts the hook (fail-OPEN) if the lib didn't load. Guard with `command -v strip_command_bodies` + raw-`$CMD` fallback (AC8). Grep `2>/dev/null || true` across all hooks before wiring the call.
- **`follow-through-directive-gate.sh` has a second early-exit (`:54`, requires `--label follow-through`).** Its FP fixture must carry that label on the stripped line, else the test exits at `:54` and false-passes without exercising the strip (AC7).
- **CI glob gap:** `scripts/test-all.sh:177` globs `.claude/hooks/*.test.sh` but not `.claude/hooks/lib/*.test.sh`. Put the helper's unit tests in the existing globbed `.claude/hooks/incidents.test.sh`, not a new `lib/incidents.test.sh` (which CI would silently skip).

## Plan Review

After writing this plan, run `/plan_review` (DHH + Kieran + code-simplicity) — they will stress the scope decision (shared helper vs. minimal per-gate strip) and the "leave git-commit gates alone" call. The most likely contested point: whether to fix ALL sibling gh-pr gates now (issue Acceptance is milestone-specific; the Sweep clause is an explicit audit-and-fix instruction, so folding them in is in-scope and net-positive — closes the latent FP class in one PR rather than re-discovering it per gate).
