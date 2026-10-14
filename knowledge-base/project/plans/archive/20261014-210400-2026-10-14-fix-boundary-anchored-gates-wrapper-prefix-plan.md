---
title: "fix: boundary-anchored gates tolerate command-wrapper prefixes (rtk) — shared (prefix)* fragment"
type: fix
date: 2026-10-14
slug: fix-boundary-anchored-gates-wrapper-prefix
branch: fix-10248-boundary-wrapper-prefix
issue: 10248
closes: 10248
priority: p2-medium
domain: engineering
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
lane: cross-domain
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

<!-- Phase 2.8 was reviewed: this plan provisions no infrastructure; the doppler-secrets tokens below appear only as names of gated commands inside detection regexes, never as steps to run. -->

# fix: boundary-anchored gates tolerate command-wrapper prefixes (rtk) — shared (prefix)* fragment

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). (No `specs/<branch>/spec.md` exists on this fix- branch; there is no `lane:` to carry forward.)

## Enhancement Summary

**Deepened on:** 2026-10-14 (headless `deepen-plan` — sequential inline pass; `Reviewed-Coverage: sequential-fallback`. No agent-spawn capability in the planning subagent, so the fan-out was replaced by direct execution of the skill's mechanical gates + the plan sharp-edges catalogue + targeted greps).
**Sections enhanced:** Observability (probe command), Guard Contract (scan mechanics), Scope Check (attribution), Proposed Solution (source-hygiene + source idiom), Acceptance Criteria (input-class scoping), Dependencies & Risks (precedent diff).

### Key Improvements

1. `discoverability_test.command` swapped from the suite form (hits Check 10's 15 s-cap suite-shape reject) to a minimal `grep -m1` probe with a literal `expected_output`.
2. Source idiom pinned to `incidents.sh`'s own two nested-source precedents (`:18-19`, `:57-63`) with `headless_or_stderr warn` as the WARN router — replaces a stale `hook-tool-kind.sh` WARN citation.
3. Census guard hardened per sharp edges: comment-stripped scan (`grep-rewrite.test.sh:295` + `grep-q-pipe-guard.test.sh` `_strip_comments`), count-form verdicts (never `! grep -q`), exemption registry with justifications.
4. Source-hygiene clause added: `unset` the exported names before sourcing so an inherited env value cannot masquerade as the loaded fragment; `SOLEUR_BOUNDARY_PFX_LOADED` sentinel for suites.
5. Scope Check row 6 re-attributed: the both-directions contract is user direction, not issue text — verbatim issue quote retained for the gate-coverage claim.

### New Considerations Discovered

- `incidents.sh` already sources `plugins/soleur/scripts/lib/session-state.sh` across the `.claude`→`plugins` tree boundary — the exact idiom this change reuses, not a novel mechanism.
- The base branch already plants `#10248` breadcrumb comments at `pre-merge-rebase.sh:121-122` and `precommit-guard.sh:49-50` ("do NOT extend per-site") — the shared-fragment mandate is pre-agreed in-tree.
- `prod-write-defer-gate.sh`'s three rows include a `\\(` (subshell-open) boundary alternation — the same insertion point covers it; the doppler row already carries a partial env-asn prefix.
- `rtk` string-payload escalation (`unparsed-wrapper` ask) and launcher arg-grammars recorded in `decision-challenges.md` as technical rows, deferred.

### Halt gates resolved

- 4.6 User-Brand Impact: present, `aggregate pattern` — PASS.
- 4.7 Observability: present; probe verb `grep` allowlisted, no SSH, sub-15 s, literal expected output — PASS.
- 4.8 PAT sweep: zero hits — PASS.
- 4.9 UI wireframe: no UI-surface files — N/A.
- 4.10 Encryption posture: no store/connection — N/A.
- 4.11 Guard Contract: `scripts/lint-guard-contract.py` green, 3 guard entries, assemblies structural — PASS.
- 4.12 Scope Check: single unfenced section, all rows mapped/provenanced — PASS.
- 4.5 Network-outage deep-dive: trigger words present only as filename/token literals (`ship-runbook-ssh-gate.sh`, `timeout 5`), no connectivity claim — N/A.
- 4.55 Downtime & Cutover: no infra/deploy/DB-lock surface — N/A.
- 4.4 Precedent-diff: applied — see "Dependencies & Risks".

## Overview

Boundary-anchored command gates in `.claude/hooks/` and `plugins/soleur/scripts/` match a gated command
(`gh pr merge`, `gh pr ready`, `gh issue create`, `git commit`, `git stash`, `git push origin main`,
`terraform|tofu apply`, `doppler secrets set/delete`) immediately after a shell-chain boundary
`(^|&&|\|\||;|\s--\s|…)`: the boundary is what keeps `echo "gh pr merge"` and commit-message text out of the
match set. A command-wrapper prefix between the boundary and the gated command defeats the anchor —
`rtk gh pr merge` merges without the review evidence `.claude/hooks/pre-merge-rebase.sh` exists to demand,
and `rtk git commit` bypasses the commit-on-main refusal in `guardrails.sh` and in the canonical check it
delegates to, `plugins/soleur/scripts/precommit-guard.sh`. The parent work (#10230 / PR #10227, already on
this branch's base) closed the same `rtk` bypass for the **argv[0]-unwrap** mechanism class; this plan closes
it for the **boundary-anchor** class, per #10248.

The fix lands ONE shared regex fragment — "the words that may legitimately sit between a boundary and a
gated command" (env-assignments, classic launchers, and the `rtk` grammar) — defined once in
`plugins/soleur/scripts/lib/`, consumed by every boundary-anchored gate, and pinned to the canonical grammar
table `plugins/soleur/scripts/lib/ext-filter-grammar.tsv` by extending the existing parity-by-extraction
suite. Prefix-tolerant but anchor-faithful: `rtk gh pr merge` and `rtk git commit` match; `echo "gh pr merge"`,
`rtk run -c 'gh pr merge'`, and `rtk summary 'git commit'` do not.

**Base-branch note:** this worktree is based on `feat-fcc-token-optimizations` (PR #10227), not
`origin/main` — deliberately, because the canonical TSV and the parity-suite pattern land there. After #10227
merges, this branch rebases `--onto origin/main`. Nothing in this plan depends on redesigning around that.

## Research Reconciliation — Spec vs. Codebase

| Issue claim | Reality on this branch (2026-10-14) | Plan response |
|---|---|---|
| `pre-merge-rebase.sh:121,127` | The trigger grep is at `:123`, the `_merge_args` extractor at `:129` (line numbers drifted ~2 under the base). | Sites cited by content anchor, not line number. |
| `guardrails.sh:143`, `precommit-guard.sh:49` | `:145` and `:51` on this base. | Same. |
| "~9 remaining sites / ~12 total" | **18 gated-command regexes across 11 production files** plus 2 test-fixture restatements; ~8 more sites share the anchor shape but already match `rtk`-prefixed commands via a bare-`[[:space:]]` boundary arm and need NO change. | The full Site Inventory table below replaces the estimate; a census guard makes the next site self-disclosing. |
| Fragment home "a `.claude/hooks/lib/` constant or `strip_command_bodies`-style helper in `lib/incidents.sh`" | `precommit-guard.sh` is self-contained **by design** — its header forbids `.claude/hooks/lib` vendoring because the script also runs from the **plugin install cache**, where `.claude/` does not exist. | Fragment homes in `plugins/soleur/scripts/lib/` (ships with the plugin, sits beside `precommit-guard.sh` in the cache); `lib/incidents.sh` gains one nested source line and becomes the hook-side carrier — every affected hook already sources it. Same intent, one canonical copy, cache-reachable. |
| "the two copies cannot diverge" | Runtime TSV-derivation is possible but adds fork+awk cost and a missing-TSV failure mode to every gated command check; the parent established **parity-by-extraction** as this repo's drift contract (TSV header: sites "restate or extract"). | Static restatement in ONE lib file + set-equality arms in `rtk-grammar-parity.test.sh`; TSV gains machine-readable flag rows only where extraction needs them. |

## Research Insights

**Premise Validation (Phase 0.6).** Issue #10248 OPEN (title fetched for slug); #10230 OPEN issue (parent
tracker); PR #10227 OPEN (`feat-fcc-token-optimizations` → `main`, the base); PR #10288 OPEN draft on this
branch (`WIP: fix-10248-boundary-wrapper-prefix`). All cited files verified present on the base:
`plugins/soleur/scripts/lib/ext-filter-grammar.tsv` (canonical, version-pinned, verified against rtk lib.rs),
`plugins/soleur/test/rtk-grammar-parity.test.sh` (6 extraction arms, currently 11/11 green),
`.claude/hooks/pre-merge-rebase.sh`, `.claude/hooks/guardrails.sh`,
`plugins/soleur/scripts/precommit-guard.sh`, `.claude/hooks/lib/incidents.sh` (`strip_command_bodies` at
`:372`). ADR corpus grep (`wrapper`, `boundary`, `argv`, `rtk`, `grammar`): no ADR adopts or rejects a
shared boundary-prefix mechanism — ADR-277 (destructive-command-guard) is the argv[0] sibling and does not
reach this class. The plugin cache copy of `precommit-guard.sh` exists at the devin cache path, confirming
the cache-context sourcing constraint is real, not hypothetical.

**Property List (Phase 0.6b).**

1. An `rtk`-prefixed spelling of a gated command reaches every boundary-anchored gate with the same
   verdict the bare spelling gets (deny, ask, evidence extraction, or gate body — unchanged).
2. Exactly one file defines the inter-boundary prefix grammar; every site interpolates it — no per-site
   prefix lists.
3. The fragment's `rtk` grammar cannot drift from `ext-filter-grammar.tsv` (mechanical set-equality pin,
   not convention).
4. Anchor fidelity is preserved in both directions: quoted strings, embedded text, `rtk`-glued words
   (`rtk-foo`, `artk`), non-grammar args (`rtk unknown gh`), and opaque string payloads
   (`rtk run -c '…'`, `rtk summary '…'`) still do not match.

**Cut List (Phase 0.6b).** Mechanisms the ask named or the design invited, checked against the base:

- *Reusing the argv[0]-unwrap table for boundary sites* → cut: the issue's Mandated-By line splits the
  classes deliberately; an unwrap pass over `$SCAN` re-parses text the boundary already delimits and
  would give `rtk summary 'git commit'` an exec verdict the boundary class correctly does not take.
- *Runtime regex generation from the TSV at source time* → cut: adds a fork+awk and a missing-file failure
  mode to every gated check for zero benefit over the sanctioned restate-and-pin pattern.
- *Consolidating pkill's `PFX` into the shared fragment* → cut: `PFX` has a different atom grammar (it
  allows arg words after the wrapper — correct for `ps` detection, wrong for gated-command adjacency) and
  is the parent's just-landed code; widening this PR into it doubles the regression surface.
- *Adding launcher arg-grammars (`sudo -u`, `env -C`, `timeout 5`) to the fragment* → cut: pre-existing gap
  predating `rtk`, outside the issue's contract; the atom shape admits them later without redesign
  (candidate follow-up issue, see Non-Goals).
- *A new `scripts/lint-*.py` for the consumption census* → cut: a `plugins/soleur/test/*.test.sh` suite is
  auto-discovered by `scripts/test-all.sh` and matches the parity suite's idiom; no new lint surface.

**Repo conventions applied.** `strip_command_bodies` (#5192) is already the quote/heredoc stripper every
SCAN-based gate uses — quoted occurrences of a gated command are already invisible there; the fragment only
needs to behave on raw-`$COMMAND` sites (`guardrails.sh:145` and `:395` deliberately, `precommit-guard.sh` always) where
the boundary alternation likewise excludes quote-adjacent words. `emit_incident` is the telemetry path;
`test-helpers.sh` `assert_eq`/`print_results` is the suite idiom; `tmp-classify.sh`'s header documents the
dual repo/plugin-cache `source` pattern `precommit-guard.sh` needs.

**Institutional learnings applied.**

- `2026-10-08-a-fix-that-covers-the-instance…` (PR #9653): fix the class, not the instance — the shared
  fragment IS the class fix; the census guard is the "grep every consumer of the same input" step.
- `2026-10-13-vendor-cli-grammar-verify-source-not-docs.md`: the fragment's `rtk` atoms are pinned to the
  TSV that was verified against rtk `lib.rs`, not re-derived from docs.
- `2026-05-12-cross-session-lock-lease-bash-primitives.md` SE1 (the issue's own precedent cite): an
  argv-prefix spelling (`with_lock`, here `rtk`) is a real bypass of boundary detection.
- `#5192` (in-code comments): trigger greps run on `$SCAN`, extraction greps stay on `$CMD` where quoted
  payloads must be read.

**Functional overlap / community discovery.** No external stack signatures apply (internal bash
tooling); no community artifact provides this — checked, skipped silently.

**External research decision (Phase 1.6).** Skipped: the mechanism is fully determined by the issue
contract + the parent's shipped precedent on this same base; the grammar is already source-verified in the
TSV. External research adds nothing.

**Skill description budget (Phase 1.8).** No `SKILL.md` `description:` edit is a candidate — skipped.

## Problem Statement / Motivation

Each boundary-anchored gate exists because a bare substring match would fire on quoted text, commit-message
bodies, and documentation. The boundary alternation is the price of that precision — and it is also the
blind spot: any real command word that is not immediately adjacent to the boundary is invisible. `rtk`'s
auto-rewrite (and hand-typed `rtk …` spellings) puts a real command word in exactly that position.

Concretely, on this base today:

- `rtk gh pr merge 5` passes `pre-merge-rebase.sh`'s early-exit grep → merges without the review-evidence
  sync/deny the gate exists to demand (issue severity #1). The same `gh pr merge` trigger shape is restated
  in `pre-merge-auto-close-scan.sh`, `cla-signed-author-gate.sh`, `ship-unpushed-commits-gate.sh`,
  `ship-net-issue-flow-gate.sh`, `ship-operator-step-gate.sh`, `ship-runbook-ssh-gate.sh`, and
  `ship-soak-followthrough-gate.sh` — all bypassed the same way.
- `rtk git commit` fails both commit-on-main detectors (`guardrails.sh:145`,
  `precommit-guard.sh`'s `COMMIT_RE`) → commit to `main` with no refusal (severity #2).
- The same shape leaves `git stash`, `gh issue create`, `git push origin main`, `terraform apply`, and
  `doppler secrets set/delete` gates blind to the `rtk`-prefixed spelling (severity #3, the "~9 remaining").

## Proposed Solution

One new lib file — **`plugins/soleur/scripts/lib/wrapper-boundary.sh`** (name provisional on work-phase
review) — exporting the fragment as sourceable constants:

```bash
# Canonical inter-boundary prefix grammar (#10248). Restatement pinned to
# lib/ext-filter-grammar.tsv by test/rtk-grammar-parity.test.sh — edit together.
SOLEUR_ENV_ASN_RE='[A-Za-z_][A-Za-z_0-9]*=[^[:space:]]+'
SOLEUR_LAUNCHER_RE='(sudo|command|nice|env|xargs)'
SOLEUR_RTK_RE='rtk([[:space:]]+(-(v|vv|vvv)|--verbose|--skip-env|run|err|test|proxy|bypass|summary))*'
SOLEUR_BOUNDARY_PFX="(${SOLEUR_ENV_ASN_RE}|${SOLEUR_LAUNCHER_RE}|${SOLEUR_RTK_RE})"
# Consumption idiom: (<boundary-alternation>)[[:space:]]*(${SOLEUR_BOUNDARY_PFX}[[:space:]]+)*<gated-cmd>
```

Semantics that make it anchor-faithful:

- Every atom requires trailing whitespace (`[[:space:]]+`) at the consumption site, so `rtk-foo`, `artk`,
  `sudox`, `FOO` (no `=`) can never partially consume — the wrapper word must be a whole word between the
  boundary and the gated command.
- The `rtk` atom admits only inert grammar words (counted-verbose globals, `--skip-env`, exec subcommands).
  A string-payload flag (`-c|--command|--shell`) is NOT an atom — `rtk run -c 'gh pr merge'` stops the
  prefix at `run`, `-c` ≠ `gh`, no match (the opaque payload joins the pre-existing `bash -c '…'` lexical
  limit these gates already declare).
- Composition falls out free: `sudo rtk gh pr merge`, `X=1 rtk git commit`, `xargs rtk git commit` all match
  because each interposed word is a legal atom.

Consumption paths:

- **`.claude/hooks` side:** `lib/incidents.sh` gains one nested `source` resolving
  `../../../plugins/soleur/scripts/lib/wrapper-boundary.sh` relative to itself, in the exact idiom
  `incidents.sh` already uses twice: `[[ -f "$_lib" ]] && source "$_lib" 2>/dev/null || true`
  (`incidents.sh:18-19` sources `plugins/soleur/scripts/lib/session-state.sh` across the same tree boundary;
  `:57-63` sources `lib/log-rotation.sh`); a load failure routes through `headless_or_stderr warn`
  (`incidents.sh:20-21, 254` — the canonical WARN router that keeps hook stderr out of Claude Code's
  verdict capture). Every affected hook already sources `incidents.sh`, so each
  site change is regex-only: insert `(${SOLEUR_BOUNDARY_PFX:-}[[:space:]]+)*` between the boundary group and
  the gated command. The `:-` default is load-bearing — several hooks run `set -u`; an unset fragment
  degrades to pre-fix matching (status quo), never a hard error and never a new hole.
- **Source hygiene (sharp-edge: a presence check after `source` is satisfied by the environment).** The
  nested source block `unset`s the exported names BEFORE sourcing (an inherited `SOLEUR_BOUNDARY_PFX` from
  the process environment must not survive a failed source and masquerade as the loaded fragment), keeps the
  lib's stderr, and the lib sets a `SOLEUR_BOUNDARY_PFX_LOADED=1` sentinel that suites assert — never
  `source lib; [[ -n "$VAR" ]]`, which an inherited value satisfies.
- **`plugins/soleur/scripts` side:** `precommit-guard.sh` sources `$(dirname …)/lib/wrapper-boundary.sh`
  with the same fail-soft default — same-dir resolution is correct in the repo AND the plugin install
  cache. Its "Self-contained by design" header is amended to name the one same-dir lib dependency (the
  cache-context reason the header gives — `.claude/hooks/lib` being unreachable — does not apply to a
  sibling file that ships beside it).

### Site Inventory & Dispositions (the re-enumeration the issue mandates)

Grepped the boundary-anchor pattern itself (`(^|…` + gated-command literals) across `.claude/hooks/` and
`plugins/soleur/scripts/`. **Consume the fragment:**

| # | File:line | Gate | Pattern today |
|---|---|---|---|
| 1 | `.claude/hooks/pre-merge-rebase.sh:123` | `gh pr merge` evidence gate — trigger | `(^\|&&\|\\|\\|\|;\|\s--\s)\s*gh\s+pr\s+merge` |
| 2 | `.claude/hooks/pre-merge-rebase.sh:129` | `_merge_args` arg extractor | same anchor; **sed strip also updated** — see Design Note A |
| 3 | `.claude/hooks/pre-merge-auto-close-scan.sh:96` | `gh pr merge` auto-close scan | `(^\|&&\|\\|\\|\|;\|\s--\s)\s*gh\s+pr\s+merge` |
| 4 | `.claude/hooks/cla-signed-author-gate.sh:75` | `gh pr (ready\|merge)` CLA gate | `(^\|&&\|\\|\\|\|;)\s*gh\s+pr\s+(ready\|merge)` |
| 5 | `.claude/hooks/ship-unpushed-commits-gate.sh:85` | `gh pr merge` unpushed gate | `(^\|&&\|\\|\\|\|;)\s*gh\s+pr\s+merge` |
| 6 | `.claude/hooks/ship-net-issue-flow-gate.sh:97` | `gh pr (ready\|merge)` flow gate | `(^\|&&\|\\|\\|\|;)\s*gh\s+pr\s+(ready\|merge)` |
| 7 | `.claude/hooks/ship-operator-step-gate.sh:83` | `gh pr ready / merge --auto` | `(^\|&&\|\\|\\|\|;)\s*gh\s+pr\s+(ready\|merge\s+.*--auto)` |
| 8 | `.claude/hooks/ship-runbook-ssh-gate.sh:63` | same shape | identical alternation |
| 9 | `.claude/hooks/ship-soak-followthrough-gate.sh:75` | same shape | identical alternation |
| 10 | `.claude/hooks/follow-through-directive-gate.sh:81` | `gh issue create` follow-through | `(^\|&&\|\\|\\|\|;)\s*gh\s+issue\s+create` |
| 11 | `.claude/hooks/guardrails.sh:145` | commit-on-main trigger (raw `$COMMAND`) | env-asn + launcher alternation → replaced by fragment |
| 12 | `.claude/hooks/guardrails.sh:395` | `git commit`/`--continue` conflict-marker gate | `(^\|&&\|\\|\\|\|;)\s*git\s+(-C…)?(commit\|…)` |
| 13 | `.claude/hooks/guardrails.sh:478` | `git stash` deny | `(^\|&&\|\\|\\|\|;)\s*git\s+stash` |
| 14 | `.claude/hooks/guardrails.sh:570–571` | `gh issue create` floor trigger + count | two greps, must move in lockstep |
| 15 | `plugins/soleur/scripts/precommit-guard.sh:51` | canonical `COMMIT_RE` | `^\s*(env)*(launcher)?(env)*git…commit` → fragment |
| 16–18 | `.claude/hooks/prod-write-defer-gate.sh:179,180,182` | `git push origin main`, `terraform\|tofu apply`, `doppler secrets set/delete` | three ERE rows in the defer table |

**Test-fixture restatements (consume the fragment so the fixture cannot drift):**

| File:line | Restatement |
|---|---|
| `.claude/hooks/ship-operator-step-gate.test.sh:30` | `CMD_RE` copy of the sibling-gate pattern |
| `.claude/hooks/ship-runbook-ssh-gate.test.sh:21` | `CMD_RE` copy of the sibling-gate pattern |

**Enumerated, dispositioned NO-CHANGE (verified on this base):**

| Site | Why no change |
|---|---|
| `.claude/hooks/lib/incidents.sh:282–298` `detect_bypass` | Boundary includes bare `[[:space:]]` — `rtk git … --no-verify` already matches via ` git `. |
| `.claude/hooks/git-commit-secret-scan.sh:113` | Boundary includes `[[:space:]]` and `$(` — already matches. |
| `.claude/hooks/guardrails.sh:228` (`rm -rf`), `:323` (`gh pr merge.*--delete-branch`), `:574`+ (`gh api`) | Bare-space / unanchored scans — already match. |
| `.claude/hooks/background-poll-prefer-monitor.sh:130–142` | Bare-space boundary — `rtk sleep` already matches. |
| `.claude/hooks/context-reviewed-gate.sh:84`, `:181` | `\bgit\b` word-boundary / flag extractor — already match. |
| `.claude/hooks/doppler-secrets-delete-redirect.sh:46` | Unanchored `doppler secrets` scan — already matches. |
| `.claude/hooks/iac-plan-write-guard.sh:157`, `brand-hex-commit-gate.sh:141`, `pre-merge-auto-close-scan.sh:187–201` | Content/flag scans, not command-boundary gates. |
| `.claude/hooks/pre-merge-rebase.sh:410` `(cd\|pushd)` tracking | `rtk cd` does not cd the parent shell — not tracking it is *correct*. |
| `.claude/hooks/pkill-self-match-guard.sh` | Parent landed `rtk` in `PFX` already. |
| `plugins/soleur/hooks/` (all), `plugins/soleur/scripts/lib/` (others) | No boundary-anchored gated-command regex — verified by grep. |
| `plugins/soleur/scripts/resolve-regenerable-conflicts.test.sh:719` | Source-scan `_PUSH_RE`, `[^-[:alnum:]]` boundary — matches already. |

### Design Note A — the `_merge_args` sed must move with the fragment

`pre-merge-rebase.sh`'s extractor strips the boundary via `sed -E 's/^[^g]*gh…merge//'`. That works only
because today's pre-`gh` text is pure separators (no `g`). With env-assignments in the prefix grammar,
`X=g rtk gh pr merge 5` would leave `^[^g]*` stranded at the `g` in `X=g` and emit the whole unstripped line —
a gate that fires but extracts no args. The sed must consume the same
`boundary? + (PFX space)* + gh pr merge` shape as the grep (or split the strip into "drop prefix atoms" then
"drop gated command"). A test row (`X=g rtk gh pr merge 5` → extracted args `" 5"`) pins this.

### Design Note B — string-payload and `summary` adjacency

- `rtk summary 'git commit'` — quoted payload; on `$SCAN` the string is already blanked, on raw input the
  `'`-glued word fails the word-boundary. No match, correct: with no `--shell`, the positional is a task
  name; and where `--shell` IS present, the payload is an opaque shell string — the `bash -c '…'` class the
  gates already declare out of scope.
- `rtk run -c 'gh pr merge'` — same opaque-payload class. The fragment must NOT include
  `-c|--command|--shell` in the `rtk` atom; a test row pins the non-match so a future "be more tolerant"
  edit goes red.
- `rtk run git commit` / `rtk test git commit` DO exec the command — they match, correctly.

## Alternative Approaches Considered

| Approach | Verdict |
|---|---|
| Per-site `rtk` added to each boundary alternation | Rejected — exactly the "~12 per-site prefix lists recreate the silent-drift class" the issue forbids. |
| Reuse the argv[0]-unwrap pass on `$SCAN` before matching | Rejected — different mechanism class (the Mandated-By line splits them); re-parses stripped text and gives string-payload forms a wrong verdict. |
| Fragment in `.claude/hooks/lib/` (issue's example) | Rejected as *home* — unreachable from `precommit-guard.sh` in plugin-cache context; satisfied in spirit by `incidents.sh` carrying the one nested source. |
| Generate the regex from the TSV at source time | Rejected — fork+awk on every gated check plus a missing-TSV failure mode; the TSV itself sanctions restate-and-pin. |
| Extend TSV with machine-readable flag rows (`flag-global`, `flag-string` classes) so parity extracts globals+string-flags, not just exec-subs | **Adopted** — additive rows only (`class` column values `exec` are untouched, so all six existing extraction arms are unaffected); pins the fragment's globals set AND documents the excluded string-flags set. |
| Escalate `rtk run -c '…'` to an `unparsed-wrapper` ask at boundary sites | Rejected for this PR — new verdict machinery beyond the issue's fix requirements; the payload is the declared `bash -c` lexical-limit class. Recorded as a technical decision. |

## Test Matrix (both directions — the issue's design-risk contract)

**Must match** (each row asserted per consuming site class, and at fragment level):

| Input | Why |
|---|---|
| `rtk gh pr merge 5` | base case, severity-1 gate |
| `rtk run gh pr merge 5` | exec subcommand transparent |
| `rtk -v run gh pr merge 5`, `rtk run --skip-env gh pr merge 5` | globals either side of subcommand |
| `sudo rtk gh pr merge 5`, `X=1 rtk git commit`, `xargs rtk git commit` | composition of atoms |
| `foo && rtk gh pr merge 5`, `x; rtk gh pr merge`, `foo -- rtk gh pr merge` | every boundary spelling incl. `\s--\s` |
| `rtk git commit`, `rtk git stash`, `rtk gh issue create`, `rtk gh pr ready`, `rtk git push origin main`, `rtk terraform apply`, `rtk doppler secrets set x --config prd` | the remaining gated commands |
| `X=g rtk gh pr merge 5` → extracted args `" 5"` | Design Note A |
| `rtk test git commit`, `rtk err git stash` | `test`/`err` are exec subcommands |

**Must NOT match:**

| Input | Why |
|---|---|
| `echo "gh pr merge"` (and commit-message bodies on `$SCAN`) | anchor fidelity — quoted/embedded |
| `rtk run -c 'gh pr merge'` | string payload — opaque, `bash -c` class |
| `rtk summary 'git commit'` | quoted task-name payload |
| `rtk unknown gh pr merge` | `gh` is an ARG of `unknown`, not the command word |
| `rtk-foo gh pr merge`, `artk gh pr merge`, `sudox git commit` | glued/non-word prefixes — trailing-`[[:space:]]+` enforcement |
| `FOO=1` alone, `rtk` alone, `rtk run` alone | prefix without gated command |
| `rtk --help`, `rtk run --help` | rtk-internal, not gated |

## Technical Considerations

- **Performance:** hooks are latency-sensitive (`incidents.sh`'s own source is deliberately lazy at ~19 ms).
  The fragment is a bounded literal-word alternation — no nested quantifiers over open classes, no
  catastrophic backtracking; interpolation adds zero forks (a sourced variable). AC: no per-site runtime
  regression beyond a single extra alternation in an already-executed grep.
- **Portability:** fragment uses `[[:space:]]` only (POSIX ERE + bash `=~`); no `\s`, no `\b` inside the
  fragment itself. GNU `\s` at call sites is pre-existing and untouched.
- **`set -u` safety:** several hooks run `set -uo pipefail` — all interpolation is `${SOLEUR_BOUNDARY_PFX:-}`.
- **Fail-soft semantics:** missing lib (corrupt plugin cache, fork without plugins/) → empty fragment →
  exactly pre-#10248 behavior + one WARN to stderr. Never a hard failure, never a wider match.
- **Security:** see Attack Surface Enumeration below.

### Attack Surface Enumeration

All the ways a gated command can be spelled into these gates, and which are checked:

- **Checked after this fix:** bare spelling; `rtk` + all inert-grammar spellings; classic launchers;
  env-assignments; compositions (`sudo rtk`, `X=1 rtk`, `xargs rtk`); every chain boundary incl. `--`.
- **Already checked (unchanged):** bare-space boundary sites (`detect_bypass`, secret-scan, `rm -rf`,
  poll-monitor); word-boundary sites (`context-reviewed`); unanchored scans (`doppler-redirect`, `gh api`).
- **Unchecked — declared lexical limits (pre-existing, unchanged by this fix):** opaque string payloads
  (`bash -c '…'`, `rtk run -c '…'`, `rtk summary --shell '…'`), `$( )`/`eval` indirection, `ssh host git
  commit` (remote execution — a different machine's hooks problem). `rtk` string-payload spellings join this
  declared class; they are not a new hole.
- **Unchecked — NEW gap this fix does not close (pre-existing):** launcher arg-grammars (`sudo -u root git
  commit`, `env -C dir git commit`, `timeout 5 git commit`) — predates `rtk`; candidate follow-up issue
  (Non-Goals).

## User-Brand Impact

- **If this lands broken, the user experiences:** (a) under-match → `rtk`-prefixed commands keep bypassing
  evidence gates (status quo, invisible); (b) over-match → an `rtk`-using session's legitimate commands are
  denied or asked spuriously — every `rtk`-prefixed call in a dogfood session trips a gate that did not trip
  before; (c) the arg-extraction defect (Design Note A) → the merge gate fires but reads no args, denying
  `gh pr merge` as if flags were missing.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the gates are evidence surfaces —
  merge review evidence, commit-on-main refusal, prod-write deferrals. A bypass leaves merges and prod
  writes without the recorded evidence these hooks mint; a `plugins/soleur` ship also carries the fixed
  `precommit-guard.sh` to end users running `rtk` in their own repos.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** no single instance exposes one user's data/workflow/money — the
  harm is systemic integrity of the repo's guard substrate and cumulative unrecorded merges, which only
  matters as a pattern; one level down (`none`) understates a security-evidence surface, one up
  (`single-user incident`) would claim a per-incident blast radius this tooling does not have.

## Observability

```yaml
liveness_signal:
  what: "boundary-prefix parity + consumption census assertions in scripts/test-all.sh (plugins group) and the .claude/hooks suite"
  cadence: "per-PR CI and on every test-all run"
  alert_target: "red PR check"
  configured_in: "plugins/soleur/test/rtk-grammar-parity.test.sh + plugins/soleur/test/boundary-prefix.test.sh (new)"
error_reporting:
  destination: "hook stderr WARN line (missing lib); suite FAIL: lines (drift/census); emit_incident telemetry for gate verdicts (unchanged)"
  fail_loud: "FAIL: <assertion> from the parity/census suite; 'WARN: wrapper-boundary lib missing' on hook stderr"
failure_modes:
  - mode: "shared lib absent (corrupt plugin cache / fork without plugins/)"
    detection: "WARN to hook stderr at source time; suites assert the file exists"
    alert_route: "hook stderr → session transcript; CI red via assert_file_exists"
  - mode: "rtk grammar drift (upstream adds a subcommand/flag; one side edited)"
    detection: "rtk-grammar-parity.test.sh set-equality arms"
    alert_route: "red PR check"
  - mode: "new boundary-anchored gate added without the fragment (or fragment dropped at one site)"
    detection: "consumption-census arm in boundary-prefix.test.sh + site-count floor"
    alert_route: "red PR check"
logs:
  where: "incident log via lib/incidents.sh emit_incident (gate verdicts); suite output in CI logs"
  retention: "CI log retention; incident log rotation via lib/log-rotation.sh"
discoverability_test:
  command: "grep -m1 SOLEUR_BOUNDARY_PFX plugins/soleur/scripts/lib/wrapper-boundary.sh"
  expected_output: "SOLEUR_BOUNDARY_PFX"
```

<!-- deepen-note: the suite form `bash plugins/soleur/test/rtk-grammar-parity.test.sh` completes in <1 s
locally (measured this session: 11/11 green) but matches the Check 10 15 s-cap's suite-shape reject
regex (`.test.` path); the minimal probe above prints the same "substrate present" signal. The suites
remain the full verification — this field only feeds the discoverability probe. -->

## Architecture Decision (ADR/C4)

**No ADR and no C4 change — reasoning recorded per Phase 2.10.**

- No ownership/tenancy boundary, no new substrate, no trust boundary move: this extends the canonical-grammar and
  parity-by-extraction mechanism the parent (#10230/PR #10227) already established and shipped without an
  ADR. A future engineer is not misled by the ADR corpus: the contract lives where the pattern lives — the
  TSV header, the lib header comment, and the parity suite.
- C4 completeness check: read of the feature's actor/system surface — the only external actor is the
  `rtk` CLI binary on a developer machine (not a modeled system boundary); no new vendor integration, data
  store, credential, or access relationship; consumers are repo-internal hooks. The `.c4` models cover the
  product system, not dogfood hook internals. Conclusion: no C4 impact (checked: external actors — rtk CLI;
  external systems — none; containers/data stores — none; access relationships — none).

## Guard Contract

### Guard 1 — fragment↔TSV parity (extension of `rtk-grammar-parity.test.sh`)

**Property.** The shared fragment's `rtk` restatement — exec-subcommand set and global-flag set — is
set-equal to the canonical TSV rows; drift on either side reds the suite.

**Assembly.** Every rtk-grammar restatement site: the new lib file's `SOLEUR_RTK_RE` alternation (extracted,
like the existing six arms, between non-member delimiters) and the TSV's `exec`/`flag-global`/`flag-string`
rows. Chokepoint: the parity suite is the single consumer asserting equality; the TSV is the single
authority.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Append `\|scan` to `SOLEUR_RTK_RE`'s subcommand alternation (site-side drift, second member after compliant first) | RED |
| 2 | Remove `run` from the TSV's exec rows (canonical-side drift; also the guard's own-dispatch direction — an arm that extracts nothing must fail, not vacuously pass) | RED |
| 3 | Add a `flag-global` row `--config` to the TSV without adding it to the fragment | RED |
| 4 | Change the extraction anchor so the arm matches no text (harness row — guard reporting "0 checked" exits non-green) | RED |
| 5 | Reorder the alternation (`test\|run\|err\|…`) — legal restatement spelling | PASS |

### Guard 2 — consumption census (new `boundary-prefix.test.sh` arm)

**Property.** Every boundary-anchored gated-command regex in `.claude/hooks/*.sh` +
`plugins/soleur/scripts/*.sh` interpolates `${SOLEUR_BOUNDARY_PFX` — or sits in the suite's
justified-exemption registry with a reason.

**Assembly.** Not a member list: the suite *derives* the site set by grepping the two dirs for
chain-boundary-anchored gated-command literals (`(gh\s+pr|git\s+|terraform|tofu|doppler\s+secrets)` after a
`(^|…` alternation), then asserts each hit carries the fragment var or an exemption entry. Chokepoint: there
is exactly one definition of the fragment, so "consumes it" is a literal substring check; the exemption
registry is the second chokepoint and each entry requires a justification comment. Two mechanics the
sharp-edges catalogue forces on the scan: comment lines are stripped before scanning
(`awk '!/^[[:space:]]*#'` — the `.claude/hooks/grep-rewrite.test.sh:295` precedent, and the
`_strip_comments` helper idiom in `.claude/hooks/grep-q-pipe-guard.test.sh:205` — so a comment reproducing
the gated pattern cannot false-hit or fake a match), and verdict reads use count comparisons (`grep -c` /
`[[ rc -eq 1 ]]`), never `! grep -q` — a negated grep folds a pattern-compile rc 2 into "no match" and
silences the typo the census exists to catch.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `${SOLEUR_BOUNDARY_PFX` from one consuming site (e.g. `guardrails.sh:478`) | RED |
| 2 | Add a new boundary-anchored gate file with a gated-command literal and no fragment (second member after compliant first) | RED |
| 3 | Neuter the census's own site scan so it finds 0 candidates (own-dispatch/vacuity) — floor on site count must red | RED |
| 4 | Exemption-registry entry whose file no longer exists (harness row — stale exemption must not silently pass) | RED |
| 5 | A justified exemption-site regex (bare-space boundary) present with its registry entry | PASS |

### Guard 3 — fragment semantics (the behavioral matrix in `boundary-prefix.test.sh`)

**Property.** `boundary + (atom space)* + gated-cmd` matches iff every interposed word is a legal prefix atom
and the final word is the gated command — the must-match/must-not-match table above is the contract.

**Assembly.** The fragment definition in `wrapper-boundary.sh`, plus one per-site smoke row in each affected
hook's own `*.test.sh` proving the interpolation actually happened (the fragment-level suite alone cannot
see a site that forgot to interpolate — Guard 2 covers presence, this covers behavior).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Remove `rtk` from `SOLEUR_RTK_RE` | RED (all `rtk …` must-match rows) |
| 2 | Make the atom's trailing `[[:space:]]+` optional at a call site | RED (`rtk-foo gh pr merge` false-matches) |
| 3 | Add `-c\|--command\|--shell` to the `rtk` atom (the "more tolerant" regression — string payloads start matching; second-member-after-compliant-first for the grammar) | RED |
| 4 | Replace the suite's `t()` verdict helper with one that always reports match (harness row) | RED |
| 5 | `sudo rtk gh pr merge`, `X=1 rtk git commit`, `foo -- rtk gh pr merge` — non-canonical but contract-permitted spellings | PASS |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "`rtk gh pr merge` misses the boundary anchor → merge without the evidence the gate exists to demand. Highest severity." [issue #10248] | Site rows 1–9 (the `gh pr merge`/`gh pr ready` family) + Phase 1 | mapped |
| 2 | "the `git commit` launcher alternation `((sudo\|command\|nice\|env\|xargs)[[:space:]]+)?`. `rtk git commit` bypasses. NOTE: precommit-guard.sh lives outside .claude/hooks/" [issue #10248] | Site rows 11, 15 + plugin-lib home + `SCRIPT_DIR` sourcing | mapped |
| 3 | "Remaining ~9 boundary-anchored sites — re-enumerate by grepping the boundary-anchor pattern itself … across `.claude/hooks/` + `plugins/soleur/scripts/`, never from a remembered list" [issue #10248] | Site Inventory table (grep-derived, 18 sites) + census guard | mapped |
| 4 | "land a shared wrapper-boundary fragment … consumed by every boundary-anchored gate" [issue #10248] | `wrapper-boundary.sh` + `${SOLEUR_BOUNDARY_PFX}` interpolation at all 18 sites + Guard 2 | mapped |
| 5 | "The shared fragment MUST reference the canonical grammar table … so the two copies cannot diverge" [issue #10248] | Guard 1 parity arms (+ optional TSV flag rows) | mapped |
| 6 | "users running rtk's auto-rewrite (or typing `rtk`-prefixed commands) can bypass the `gh pr merge` evidence gate and the `git commit` guard" [issue #10248, User-Impact line]; plus the user direction "Test both directions: Positive: `rtk gh pr merge`, `rtk git commit`. Negative: `echo "gh pr merge"`, `rtk run -c 'gh pr merge'`, `rtk summary 'git commit'`" [pipeline prompt] | Test Matrix section + Guard 3 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `plugins/soleur/scripts/lib/wrapper-boundary.sh` (new) | "a `.claude/hooks/lib/` constant or `strip_command_bodies`-style helper" | asked (home relocated per cache-context constraint — see Research Reconciliation) |
| `incidents.sh` nested source | — | inferred — justification: every affected hook already sources it; the alternative is a new source line in 11 files and `incidents.sh` is the sanctioned shared-helper home the issue names |
| `ext-filter-grammar.tsv` flag rows | "The shared fragment MUST reference the canonical grammar table" | asked (mechanism choice — additive `flag-global`/`flag-string` rows are the extraction surface for globals parity) |
| `boundary-prefix.test.sh` (new) | "Enumerate both directions in the plan's test matrix" + "consumed by every boundary-anchored gate" | asked |
| `rtk-grammar-parity.test.sh` new arms | "the parity-test pattern … the pattern to reuse for the boundary-fragment parity check" [parent-prompt RELATED CONTEXT] | asked |
| Per-hook `*.test.sh` rtk rows | — | inferred — justification: per-site behavioral proof the interpolation happened (Guard 3 assembly); fragment-level rows cannot see a site that forgot to interpolate |
| `ship-*.test.sh` CMD_RE fixture updates | — | inferred — justification: test fixtures restating the gated pattern would drift from production the moment the fragment lands |

### Split Assessment

- Subsystems touched: 2 — `.claude` (hooks) and `plugins/soleur` (scripts/test)
- Planned files: 20 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Open Code-Review Overlap

- `.claude/hooks/cla-signed-author-gate.sh` → **#7218** ("cla-signed-author-gate only detects one hardcoded
  unsigned identity"). **Acknowledge** — different concern (identity detection vs. command-trigger anchor);
  this plan touches only the `:75` trigger regex. Scope-out remains open.

## Files to Create

- `plugins/soleur/scripts/lib/wrapper-boundary.sh` — the shared fragment (name provisional)
- `plugins/soleur/test/boundary-prefix.test.sh` — behavioral matrix + consumption census (name provisional)

## Files to Edit

- `plugins/soleur/scripts/lib/ext-filter-grammar.tsv` — additive `flag-global`/`flag-string` rows (parity extraction surface for globals; documents the excluded string-flags set)
- `plugins/soleur/test/rtk-grammar-parity.test.sh` — new arms: fragment exec-sub set, fragment globals set, TSV flag classes
- `plugins/soleur/scripts/precommit-guard.sh` — source the lib, `COMMIT_RE` uses the fragment, header amended
- `.claude/hooks/lib/incidents.sh` — one nested source of the plugin lib (fail-soft + WARN)
- `.claude/hooks/pre-merge-rebase.sh` — `:123` trigger, `:129` extractor grep + sed (Design Note A)
- `.claude/hooks/pre-merge-auto-close-scan.sh` — `:96`
- `.claude/hooks/cla-signed-author-gate.sh` — `:75`
- `.claude/hooks/ship-unpushed-commits-gate.sh` — `:85`
- `.claude/hooks/ship-net-issue-flow-gate.sh` — `:97`
- `.claude/hooks/ship-operator-step-gate.sh` — `:83`
- `.claude/hooks/ship-runbook-ssh-gate.sh` — `:63`
- `.claude/hooks/ship-soak-followthrough-gate.sh` — `:75`
- `.claude/hooks/follow-through-directive-gate.sh` — `:81`
- `.claude/hooks/guardrails.sh` — `:145`, `:395`, `:478`, `:570–571`
- `.claude/hooks/prod-write-defer-gate.sh` — `:179`, `:180`, `:182`
- `.claude/hooks/ship-operator-step-gate.test.sh` — `CMD_RE` consumes fragment
- `.claude/hooks/ship-runbook-ssh-gate.test.sh` — `CMD_RE` consumes fragment
- Per-hook test files gain `rtk`-spelling rows: `guardrails.test.sh`, `pre-merge-rebase.test.sh` (+`-headless`, `-parity` as their harnesses admit), `pre-merge-auto-close-scan.test.sh`, `cla-signed-author-gate.test.sh`, `ship-net-issue-flow-gate.test.sh`, `ship-operator-step-gate.test.sh`, `ship-runbook-ssh-gate.test.sh`, `ship-soak-followthrough-gate.test.sh`, `ship-unpushed-commits-gate.test.sh`, `follow-through-directive-gate.test.sh`, `prod-write-defer-gate.test.sh`

## Implementation Phases

### Phase 1: Shared fragment + parity pin

- Create `wrapper-boundary.sh` with the atom constants + consumption idiom comment.
- Extend `rtk-grammar-parity.test.sh`; add TSV flag rows if the globals arm needs a parseable surface
  (verify all six existing arms still green after the additive rows).
- Create `boundary-prefix.test.sh`: the both-directions matrix + census (derive sites by grep; exemption
  registry with justifications; site-count floor).
- RED state: fragment exists but no site consumes it → behavioral rows fail at site level; census fails.

### Phase 2: Carrier + canonical check

- `incidents.sh` nested source (fail-soft + WARN).
- `precommit-guard.sh`: `SCRIPT_DIR` source, `COMMIT_RE` → fragment, header amendment.
- Verify `rtk git commit` refuses and `precommit-guard.sh` still runs from a copied-to-tmp location
  (cache-context simulation: script + lib sibling present, `.claude` absent).

### Phase 3: Site consumption sweep

- Interpolate `${SOLEUR_BOUNDARY_PFX:-}` at all 18 sites in the inventory order (severity 1 → 2 → 3).
- `_merge_args` grep+sed per Design Note A.
- Per-hook test rows.

### Phase 4: Verify + docs

- Full hook suite + `scripts/test-all.sh` scripts group green.
- `#10248` disclosure comments (already planted by the base in the three named files) updated to past tense
  where the fix landed; same callout style added at the newly-fixed sites.
- `known-external-tools.md` gains a line noting the boundary class is covered (doc parity, if the parent's
  doc names the deferred class).

## Acceptance Criteria

- [ ] `rtk gh pr merge 5` (and `rtk run`, `rtk -v run`, `rtk run --skip-env`, `sudo rtk`, `X=1 rtk`, chained and `--`-bounded spellings) reaches the `gh pr merge` evidence gate and the `gh pr ready|merge` family gates identically to the bare spelling — verified by hook-level test rows in `pre-merge-rebase.test.sh`, `pre-merge-auto-close-scan.test.sh`, `cla-signed-author-gate.test.sh`, `ship-unpushed-commits-gate.test.sh`, `ship-net-issue-flow-gate.test.sh`, `ship-operator-step-gate.test.sh`, `ship-runbook-ssh-gate.test.sh`, `ship-soak-followthrough-gate.test.sh`.
- [ ] `rtk git commit` is refused by the commit-on-main gate in `guardrails.sh` AND by `bash plugins/soleur/scripts/precommit-guard.sh 'rtk git commit'` (exit 1) — including from a plugin-cache-shaped location (script + lib sibling, no `.claude` tree).
- [ ] All 18 production regex sites + 2 test-fixture restatements interpolate `${SOLEUR_BOUNDARY_PFX:-}` — census arm asserts zero un-exempted boundary-anchored gated-command regexes in the two dirs, with a site-count floor.
- [ ] `rtk-grammar-parity.test.sh` asserts set-equality between `SOLEUR_RTK_RE`'s exec-subcommand set, its global-flag set, and the canonical TSV — drift on either side reds.
- [ ] Must-NOT-match rows hold at fragment AND site level (per each site's own input class — `$SCAN` or raw `$COMMAND`): `echo "gh pr merge"`, commit-body text on `$SCAN`, `rtk run -c 'gh pr merge'`, `rtk summary 'git commit'`, `rtk unknown gh pr merge`, `rtk-foo gh pr merge`, `artk gh pr merge`. (A boundary INSIDE quoted text — `echo "; rtk gh pr merge"` — remains the pre-existing raw-`$COMMAND` limitation, unchanged by this fix.)
- [ ] `_merge_args` returns `" 5"` for `X=g rtk gh pr merge 5` (Design Note A) and identical output to today for bare/`&&`-chained spellings.
- [ ] Missing/corrupt lib → `${SOLEUR_BOUNDARY_PFX:-}` empty → identical pre-fix matching + one stderr WARN; `set -u` hooks unaffected.
- [ ] All pre-existing hook/plugin suites pass unmodified except fixtures intentionally updated for the fragment.
- [ ] No per-site prefix lists: the census arm (Guard 2) is green — it is the AC's own invocation, not a hand-enumerated reconstruction; `rtk` literals legitimately remain in the parent's argv[0]-class files (`pkill-self-match-guard.sh` `PFX`, `destructive-command-guard.sh`, `proc.sh`), the TSV, the shared lib, tests, and comments — the census asserts consumption, not absence.

## Test Scenarios

- Given `rtk run gh pr merge 5` on a branch, when `pre-merge-rebase.sh` receives it as Bash input, then the
  evidence gate engages exactly as for `gh pr merge 5` (unit → hook suite row).
- Given `rtk git commit -m x` on `main`, when `precommit-guard.sh --cwd <repo>` receives it, then exit 1 with
  the refusal reason (integration — script execution).
- Given `rtk run -c 'gh pr merge 5'`, when any boundary gate scans it, then no gate fires and no new verdict
  machinery engages (unit — the declared lexical-limit class).
- Given `X=g rtk gh pr merge 5`, when `_merge_args` extracts, then the result is `" 5"` — no prefix residue
  (unit — Design Note A row).
- Given a copy of `precommit-guard.sh` + `lib/` in a tmpdir without `.claude/`, when invoked with `rtk git
  commit`, then refusal — plugin-cache context (integration).
- Given a new file in `.claude/hooks/` containing `(^|&&)\s*gh\s+pr\s+merge` without the fragment, when the
  census arm runs, then it fails naming the file (unit — Guard 2 mutation row 2).
- Given `SOLEUR_BOUNDARY_PFX` unset (lib absent), when a `set -u` hook interpolates it, then pre-fix matching
  and one WARN, no error (unit — fail-soft row).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Product/UX gate mechanical override
checked: no `components/**/*.tsx`, `app/**/page.tsx`, or `app/**/layout.tsx` in Files to Create/Edit — the
override does not fire; tier NONE.

## Success Metrics

- Every must-match matrix row fires its gate; every must-not-match row does not (the matrix IS the metric).
- Zero boundary-anchored gated-command regexes outside the shared-fragment consumption set (census arm).
- Parity suite green and non-vacuous (assertion count floor preserved).

## Dependencies & Risks

- **Dependency:** PR #10227 (`feat-fcc-token-optimizations`) — the canonical TSV + parity harness. Already on
  this base; after it merges, this branch rebases `--onto origin/main`. Draft PR #10288 exists on this branch.
- **Risk — enumeration completeness:** a site missed by the two-dir grep stays bypassed. Mitigation: the
  issue's grep was re-run three ways (`(^|` alternations, gated-command literals, `=~` forms) and the census
  guard turns any future miss into a red check instead of a silent hole.
- **Risk — regex over-match:** the fragment is wider than today's alternations (arbitrary atom ordering).
  Mitigated by the trailing-`[[:space:]]+` invariant + the must-not-match suite; every atom is a real
  prefix-position word.
- **Risk — behavioral drift between trigger and extractor greps** (e.g. `guardrails.sh:570/571`,
  `pre-merge-rebase.sh:123/129`): mitigated by the lockstep rows + Design Note A's dedicated AC.
- **Risk — performance:** one extra alternation in already-executed greps; no new forks, no quantifier
  nesting over open classes. The hook suites' existing timing guards cover regressions.
- **Risk — base rebase:** #10227 merging first may move cited line numbers; all plan citations use content
  anchors.
- **Precedent diff (deepen 4.4).** Three pattern-bound behaviors, all with sibling precedents verified this
  pass: (a) nested-source of a plugin-scripts lib from `incidents.sh` — precedent `incidents.sh:18-19`
  (`session-state.sh`, same tree boundary, `2>/dev/null || true`) and `:57-63` (`log-rotation.sh`,
  `[[ -f ]]` guard + `shellcheck source=/dev/null`); the new block copies this shape verbatim plus the
  `unset`-before-source hygiene the catalogued `#8846`/PR #8873 sharp edge adds on top. (b) parity-by-extraction —
  precedent `rtk-grammar-parity.test.sh` (parent's own suite, extended, not paralleled). (c) grep-census
  guard — precedents `.claude/hooks/grep-rewrite.test.sh:295` (`awk '!/^[[:space:]]*#'` comment strip)
  and `grep-q-pipe-guard.test.sh:205` (`_strip_comments` helper + positive-control decoy). Deviation from
  precedent: none intentional — the census is the same scan shape over a different pattern set.

## Non-Goals

- argv[0]-unwrap mechanisms (parent's class — `destructive-command-guard.sh`, `pkill-self-match-guard.sh`
  `PFX`, `proc.sh`): already tolerant; `PFX` consolidation is a separate, deliberately-unwidened surface.
- Opaque string-payload escalation (`rtk run -c`, `rtk summary --shell`) to `unparsed-wrapper` ask-verdicts:
  the `bash -c` lexical-limit class; recorded as a decision-challenge row.
- Launcher arg-grammars (`sudo -u`, `env -C`, `timeout N`, `nice -n N`): pre-existing gap, predates `rtk`;
  atom shape admits them later. Candidate follow-up issue if not already tracked.
- `plugins/soleur/hooks/` (none have boundary-anchored gated-command regexes — verified) and
  bare-space/word-boundary sites (already match).
- `pre-merge-rebase.sh:410` `cd|pushd` tracking: `rtk cd` is semantically not a cd.

## References & Research

- Issue: #10248 (contract), #10230 (parent tracker), PR #10227 (base), PR #10288 (draft on this branch)
- Canonical grammar: `plugins/soleur/scripts/lib/ext-filter-grammar.tsv` (rtk lib.rs-verified)
- Parity pattern: `plugins/soleur/test/rtk-grammar-parity.test.sh`
- Precedent: `knowledge-base/project/learnings/2026-05-12-cross-session-lock-lease-bash-primitives.md` SE1;
  `knowledge-base/project/learnings/2026-10-08-a-fix-that-covers-the-instance-and-a-cap-that-asks-about-what-it-never-expands.md`
- Consumption-pattern precedent: `.claude/hooks/pkill-self-match-guard.sh:225` `PFX` (file-local);
  `.claude/hooks/lib/incidents.sh:372` `strip_command_bodies` (shared-helper precedent);
  `plugins/soleur/scripts/lib/tmp-classify.sh` header (dual repo/cache `source` idiom)
- Cache-context constraint: `plugins/soleur/scripts/precommit-guard.sh` header, "Self-contained by design";
  verified against the devin plugin install cache.
