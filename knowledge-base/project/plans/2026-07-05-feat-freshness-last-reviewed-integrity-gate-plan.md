---
title: "feat: freshness last_reviewed source-fix + audit tripwire"
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
tracks_issue: 5999
epic: 6003
branch: feat-freshness-convention
pr: 6017
last_updated: 2026-07-05
review_cadence: quarterly
deepened: 2026-07-05
---

# feat: Freshness `last_reviewed` — Source-Fix + Audit Tripwire

**Issue:** #5999 · **Epic:** #6003 · **PR:** #6017 · **Brainstorm:** `knowledge-base/project/brainstorms/2026-07-04-freshness-convention-brainstorm.md` · **Spec:** `knowledge-base/project/specs/feat-freshness-convention/spec.md`

## Deepen-Plan Findings (2026-07-05)

Five review agents (architecture, security, simplicity, observability, verify-the-negative) converged on **one spine correction**: the commit gate is a **detective/audit tripwire, not an integrity guarantee**, and the plan's v1 framing over-claimed. The real integrity comes from **fixing the automated writers at source** — and there are **two**, not one. Concrete changes folded in below:

1. **Premise wrong — two automated writers, not one.** Beyond brainstorm `SKILL.md:121`, `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts:108` instructs an agent to bump `last_reviewed` on `content-strategy.md`, auto-committed via `safeCommitAndPr` with no gate. (verify-pass + simplicity, confirmed.)
2. **Guarantee downgraded (security P0-1, simplicity).** The `Context-Reviewed:` trailer is **self-attestable** by the committing agent — an automated writer that knows the convention emits `Context-Reviewed: all` and passes. The gate is a speed-bump + audit chokepoint, not a wall. Wording changed from "trustworthy / blocks automated bumps / default-deny" → "attributable / auditable; forces a declaration and logs undeclared attempts."
3. **Gate hardened (security P0-2/P1-4/P1-5, obs P1).** `git commit -a`/`-am`/pathspec empirically bypasses `--cached` detection with **no incident** (the default agent commit path); canonical-spelling-only grep misses quoted/spaced/case variants and deletions; trailer extraction under-specified. Gate now unions working-tree delta for `-a`/pathspec, widens the match, mirrors the precedent's message extraction + `resolve_command_cwd`, and splits fail-open into benign (silent) vs error (emit incident).
4. **Loader over-strip guard (obs P1).** A greedy frontmatter-strip on the fail-closed-critical loader can silently eat rule body on malformed frontmatter — and the lint would read *lower* bytes and pass green. Added a positive integrity assert (sentinel rule-id survival + `TOTAL_RULES` pre==post; lint FAILS, not shrinks, if strip removes a `- [id:` line) + a malformed-frontmatter fixture.
5. **Helper cut (simplicity YAGNI).** `bump-frontmatter-updated.py` is redundant — neither writer would call it (`SKILL.md` is agent-prose; the cron is TypeScript), and the gate, not the helper, is the enforcement. −2 files, −1 AC.
6. **Non-vacuous discoverability test + run-time scan liveness (obs P1).** The old probe never staged a change and mis-asserted exit code; replaced with a two-case scratch-repo probe discriminating on `"permissionDecision":"deny"`. The `review-reminder.yml` extension gains a required-constitutional-path liveness assert (`::error::` if `AGENTS.core.md` is silently dropped).
7. **Gate scopes to *changed/removed*, not *added* (architecture P2).** A net-new doc legitimately *adds* `last_reviewed` for the first time; firing on every addition causes trailer-fatigue → rubber-stamping, and would self-trip on this plan's own `AGENTS.core.md` commit. The gate now fires only when a `last_reviewed` line is **removed or changed** (`^-.*last_reviewed` in the delta — the re-bump and deletion cases, the actual threat), exempting pure first-time additions.
8. **Loader strip must cover THREE raw read-sites (architecture P1), not one:** `session-rules-loader.sh:50` (core-only fallback), `:149` (main concat), `:162` (fail-safe re-walk). A single shared bash strip fn at all three, else frontmatter leaks into context on the error paths. All three AGENTS lints (`lint-agents-rule-budget.py`, `lint-rule-ids.py`, `lint-agents-enforcement-tags.py` per `lefthook.yml:63,80`) run post-Phase-3.

## Overview

Make `last_reviewed` **attributable and auditable** — a cooperative freshness signal with tamper-evidence rather than tamper-resistance. Soleur already has the convention (`last_reviewed` + `review_cadence` on 40 KB files) and the surfacing (`review-reminder.yml` + Inngest crons file overdue-review issues). The gap: **automated flows silently bump `last_reviewed`** (two known sites do exactly that), so a staleness signal computed from it is false confidence.

**The integrity comes from the source fixes; the gate is the tripwire.** v1 ships:
1. **Source fixes (the real integrity)** — stop *both* known automated writers (`SKILL.md:121` + `cron-campaign-calendar.ts:108`) from bumping `last_reviewed`; they bump `last_updated` instead.
2. **A commit-time audit tripwire** — a hardened `PreToolUse(Bash)` gate that forces any `last_reviewed` change committed through an agent's Bash tool to carry an explicit `Context-Reviewed:` declaration, and logs undeclared attempts to the incident ledger. Detective, not preventive.
3. **Rule-layer coverage** — bring the always-loaded `AGENTS.core.md` under the review clock, funded by teaching the budget lint to strip frontmatter (matching the loader) — no hard-rule trim.
4. **ADR-085** documenting the boundary and the source-fix-first design.

**Premise Validation (corrected at deepen):** convention on 40 files; `review-reminder.yml:151` scans `find knowledge-base` **only** (repo-root `AGENTS.core.md` outside scope; slug builder `:97` degrades on non-`knowledge-base/` paths); **TWO** automated `last_reviewed` writers — `SKILL.md:121` AND `cron-campaign-calendar.ts:108` (all three crons *read* the field, but campaign-calendar *writes* it via an agent prompt); precedent gate `follow-through-directive-gate.sh` is a `PreToolUse(Bash)` hook (`.claude/settings.json:91`) using `strip_command_bodies` + `resolve_command_cwd` from `lib/incidents.sh`; `emit_incident` (`lib/incidents.sh:198`) appends to `.claude/.rule-incidents.jsonl` (local, gitignored, per-machine — queryable via `rule-metrics-aggregate.sh`, no ssh); loader (`session-rules-loader.sh:135,158`) injects `AGENTS.core.md` (strippable), `AGENTS.md` loads via CLAUDE.md `@AGENTS.md` harness import (unstrippable → frontmatter on `AGENTS.core.md` only); `TOTAL_RULES` (`:177`) greps `^- .*[id:` (frontmatter unaffected); `lint-agents-rule-budget.py:59` measures raw `read_bytes()`, B_ALWAYS=22976/23000; highest ADR ordinal 084 → provisional **ADR-085**.

## Research Reconciliation — Spec vs. Codebase

| Spec/original claim | Reality (verified) | Plan response |
|---|---|---|
| "The only automated `last_reviewed` writer is `SKILL.md:121`" | **Two** writers: `SKILL.md:121` + `cron-campaign-calendar.ts:108` (auto-commits `content-strategy.md`) | Phase 4 fixes **both**; premise corrected |
| Gate makes `last_reviewed` "trustworthy" / "blocks automated bumps" | Trailer is self-attestable; `-am`/pathspec/Warp/CI/cron all bypass | Reframed as attributable/auditable tripwire; hardened for the `-a` path; guarantee boundary stated in ADR |
| FR4: fields on `AGENTS.md` **and** `AGENTS.core.md` | `AGENTS.md` injects raw via harness `@`-import (unstrippable) | `AGENTS.core.md` only |
| Headroom to add frontmatter | B_ALWAYS headroom = 24 B | Fund via lint frontmatter-strip (measure loaded bytes), not a rule trim |
| `bump-frontmatter-updated.py` helper needed (FR2) | Neither writer calls it (prose + TS); gate is the enforcement | Helper **cut** |
| FR6: reuse existing cron (implies it scans the rule layer) | `review-reminder.yml` scans `find knowledge-base` only; can silently drop a repo-root path | Extend `find` + add run-time required-path liveness assert |

## Architecture Decision (ADR/C4)

### ADR
Create **ADR-085** `freshness-last-reviewed-source-fix-and-audit-tripwire` via `/soleur:architecture` (Phase 6). Records: (a) the `last_updated`-vs-`last_reviewed` boundary; (b) **source-fix-first** — integrity is delivered by fixing the known automated writers, the gate is a detective tripwire; (c) the **honest guarantee-boundary statement** (verbatim below); (d) reuse the KB-corpus consumer (`review-reminder.yml`) rather than add a scanner — **acknowledging the frontmatter is already parsed by three independent consumers** (`review-reminder.yml`, `scripts/strategy-review-check.sh`, `cron-strategy-review.ts`); this change creates no new parser but does not claim to collapse the existing three (`cq-union-widening-grep`); (e) the loader/lint frontmatter-strip single-sourcing + the loaded-vs-disk B_ALWAYS reinterpretation. Optionally register principle **AP-016** (the integrity boundary) in `principles-register.md`, sourced from ADR-085. Provisional ordinal — re-verify against `origin/main` at ship.

**Guarantee-boundary statement (into ADR-085 verbatim):** *"This gate is a speed-bump + audit chokepoint, not an integrity guarantee. The `Context-Reviewed:` trailer is self-attestable by the committing agent; the gate relocates the honor-system boundary to a single greppable, incident-logged point. It does not prove human review; it is bypassed by `git commit -a`/pathspec (mitigated here via working-tree detection), by commits outside the Claude Code Bash tool (Warp/IDE/CI/Inngest), and by non-canonical key spellings. `last_reviewed` remains a cooperative signal, now with tamper-evidence. The trust anchor is the convention + the source-level fixes to known automated writers; the gate is its tripwire."*

### C4 views
**No C4 impact.** Checked `model.c4`/`views.c4`/`spec.c4`. `platform.plugin.kb`/`platform.plugin.skills` already modeled (`model.c4:67-89`); a dev-workflow metadata convention adds no external actor, external system, container/datastore, or access-relationship. "None" cited against the enumeration per the completeness mandate.

## Implementation Phases

Phase order is **contract-before-consumer**: the frontmatter-strip (Phase 2) MUST land before `AGENTS.core.md` frontmatter (Phase 3), else the budget lint goes RED.

### Phase 0 — Preconditions (re-verify at /work start)
- Re-run B_ALWAYS: `a=$(wc -c<AGENTS.md); c=$(wc -c<AGENTS.core.md); echo $((a+c))` (~22976).
- Re-grep automated `last_reviewed` **writers** (not readers): `grep -rniE "last_reviewed" scripts/ plugins/soleur/skills/*/scripts/ plugins/soleur/skills/*/SKILL.md apps/web-platform/server/inngest/` and classify each hit read-vs-write. Confirm the writer set is exactly {`SKILL.md:121`, `cron-campaign-calendar.ts:108`}; if a third appears, add it to Phase 4.
- Read `.claude/hooks/follow-through-directive-gate.sh` + `lib/incidents.sh` for `strip_command_bodies`, `resolve_command_cwd`, `emit_incident` signatures (the gate mirrors these).

### Phase 1 — Reviewed-audit gate (the tripwire)
- **Create** `.claude/hooks/context-reviewed-gate.sh` — `PreToolUse(Bash)` hook:
  - Fire only on `git commit` (word-boundary match on `strip_command_bodies "$CMD"`).
  - Resolve the target repo with `resolve_command_cwd` (handles `git -C X` / `cd X && git commit`) — not bare `.cwd` (**security P1-3**).
  - Compute the `last_reviewed` delta as the **union** of staged (`git diff --cached -U0 -- '*.md'`) AND, when the command is `-a`/`-am`/`--all`/`-o`/explicit-pathspec, the working-tree delta (`git diff -U0 -- '*.md'`) — closes the `-am` default-path bypass (**security P0-2**).
  - Fire only on a **removed or changed** reviewed line — match `^-.*[Ll]ast_[Rr]eviewed\s*["']?\s*:` in the delta (widened for quoting/space/case, **security P1-4**). A re-bump shows as `-old/+new`; a deletion shows as `-old`; a **net-new adoption shows only `+new` with no `-`** and is exempt (prevents trailer-fatigue + the plan's own `AGENTS.core.md` self-trip, **architecture P2**).
  - Extract the commit message from ALL sources — every `-m`/`--message`/`--message=`, concatenated multi-`-m`, `-am`, `-F/--file <path>` (`cat` at hook time, read-fail → error fail-open), heredoc — mirroring the precedent's body extraction (**security P1-5**).
  - Trailer present (`Context-Reviewed:\s*(all|<path>)`) → allow. Absent → **deny** (`permissionDecision:"deny"`, exit 0) + `emit_incident … deny`.
  - **Fail-open split (obs P1):** *benign* (not a commit / no `*.md` / no `last_reviewed` delta) → silent `exit 0`. *Error* (jq/perl parse failure, `-F` file unreadable, cwd unresolvable on a real commit) → `emit_incident … warn … hook_self_fault` then `exit 0`. *Silent-bypass advisory:* if the delta is present but only because a non-`--cached` path was used and the tool cannot fully verify, emit `warn` even when allowing.
- **Create** `.claude/hooks/context-reviewed-gate.test.sh` (TR1) — cases: staged bump no-trailer → deny; **`-am` bump no-trailer → deny** (regression for P0-2); trailer → allow; multi-`-m` with trailer in 2nd → allow (P1-5); quoted/spaced/case-variant key → deny (P1-4); `last_reviewed` line **deletion** no-trailer → deny; `last_updated`-only change → allow; non-commit → silent fail-open; `-F` unreadable → error fail-open + incident; `git -C /other` → resolves correct repo.
- **Edit** `.claude/settings.json` — register under `PreToolUse`→`Bash` (mirror `:91`).

### Phase 2 — Frontmatter-strip (loader + lint) — enables Phase 3
- **Create** `scripts/lib/frontmatter-strip` **single source** of the strip contract — a documented canonical regex/spec + a tiny shared test fixture set. The bash loader and the python lint each implement it, and a **cross-check test** feeds the same fixtures to both and asserts identical output (replaces "keep two regexes identical by hand" — **simplicity**).
- **Edit** `.claude/hooks/session-rules-loader.sh` — add a single shared bash strip fn and call it at **all THREE** raw read-sites: `:50` (`emit_core_only_fallback`), `:149` (main concat), `:162` (fail-safe re-walk) — else frontmatter leaks into context on the error paths (**architecture P1**). Preserve the fail-closed missing-file path + ≤200-byte header (TR3). **Over-strip guard (obs P1):** after strip, assert each sidecar still contains a per-sidecar sentinel rule-id (e.g. `hr-never-git-stash-in-worktrees` in core) and `TOTAL_RULES` post-strip == pre-strip; on mismatch, fail-closed loudly (do NOT inject a mangled sidecar).
- **Edit** `scripts/lint-agents-rule-budget.py` — strip `AGENTS.core.md` frontmatter before the byte count (matches loader). **Fail-hard, not shrink:** if the strip would remove any `- [id:` rule line (i.e. it consumed body, not frontmatter), the lint ERRORS instead of reporting a lower B_ALWAYS.
- **Edit** `scripts/lint-agents-rule-budget.test.sh` — assert `AGENTS.core.md` frontmatter excluded from B_ALWAYS; assert a malformed-frontmatter (unterminated `---`) fixture makes the lint ERROR, not silently shrink.
- **Loader test** — injected sidecar context contains rule text but NOT `last_reviewed:`; malformed-frontmatter fixture asserts the strip does NOT consume rule body (over-strip regression).

### Phase 3 — Bring `AGENTS.core.md` under the clock
- **Edit** `AGENTS.core.md` — add frontmatter `last_reviewed: 2026-07-05`, `review_cadence: monthly`, `owner:`. Budget-safe (Phase 2 lint-strip excludes it).

### Phase 4 — Source-fix BOTH automated writers (the real integrity)
- **Edit** `plugins/soleur/skills/brainstorm/SKILL.md:121` — "Update `last_updated` **only** (a reconcile is an automated write; never bump `last_reviewed` — ADR-085)."
- **Edit** `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts:108` — change the agent-prompt instruction from bumping `last_reviewed` → bumping `last_updated` on `content-strategy.md`. (Server-side surface — the gate cannot see this commit, so it MUST be fixed at source.)
- Re-grep for any third writer (Phase 0 output); fix in kind.

### Phase 5 — Extend the overdue-review scan
- **Edit** `.github/workflows/review-reminder.yml` — extend the `find knowledge-base` feed (`:151`) to also emit repo-root `AGENTS.core.md`. The slug builder (`:97`) degrades gracefully on the non-`knowledge-base/` path (`AGENTS.core` → title "Review Reminder: AGENTS.core") — an optional slug branch is polish, not correctness. **Run-time liveness assert (obs P1 / architecture P2):** track a required-constitutional-path set; emit `::error::` and fail the run if `AGENTS.core.md` was not evaluated in the loop (guards the silent empty-cadence/`head != ---`/`continue` drop — which also fires if Phase 3 frontmatter is ever removed). Do NOT add a second scanner.

### Phase 6 — ADR + C4 note
- **Create** `knowledge-base/engineering/architecture/decisions/ADR-085-freshness-last-reviewed-source-fix-and-audit-tripwire.md` via `/soleur:architecture` (content per §Architecture Decision, incl. the verbatim guarantee-boundary statement + C4-none enumeration).

### Phase 7 — Verify
- Run `package.json scripts.test`; each new `.test.sh`; both lints; the strip cross-check test; walk AC1–AC10.

## Files to Create
- `.claude/hooks/context-reviewed-gate.sh` + `.claude/hooks/context-reviewed-gate.test.sh`
- `scripts/lib/frontmatter-strip` (shared strip contract + fixtures) + its cross-check test
- `knowledge-base/engineering/architecture/decisions/ADR-085-freshness-last-reviewed-source-fix-and-audit-tripwire.md`

## Files to Edit
- `.claude/settings.json` — register the gate hook
- `.claude/hooks/session-rules-loader.sh` — sidecar frontmatter-strip + over-strip guard
- `scripts/lint-agents-rule-budget.py` + `.test.sh` — strip `AGENTS.core.md` frontmatter; fail-hard on body consumption
- `AGENTS.core.md` — freshness frontmatter
- `plugins/soleur/skills/brainstorm/SKILL.md:121` — `last_updated`-only
- `apps/web-platform/server/inngest/functions/cron-campaign-calendar.ts:108` — `last_updated`-only
- `.github/workflows/review-reminder.yml` — extend scan + required-path liveness assert

## Open Code-Review Overlap
None. (`gh issue list --label code-review --state open` cross-checked against the Files lists.)

## User-Brand Impact
- **If this lands broken, the user experiences:** the reviewed-clock signal keeps reading "fresh" while a hard rule silently ages (an automated writer bumps `last_reviewed` undetected), so an agent trusts a stale rule and makes a wrong high-blast-radius decision. **New (deepen):** OR the loader frontmatter over-strip silently drops hard rules from every session's context — a governance blackout.
- **If this mis-fires:** a self-attested `Context-Reviewed:` gives false confidence of human review. Mitigated by naming the boundary honestly and fixing the writers at source.
- **Brand-survival threshold:** single-user incident (auto, per #5175).

CPO sign-off: satisfied by operator-in-loop (internal dev-tooling, no user-facing surface). `user-impact-reviewer` runs at PR review.

## Observability
```yaml
liveness_signal:
  what: review-reminder cron files an overdue-review issue when a constitutional file passes its cadence; run fails loud (::error::) if a required constitutional path is silently dropped from the scan
  cadence: existing review-reminder.yml schedule
  alert_target: GitHub issue (existing channel) + workflow-run failure
  configured_in: .github/workflows/review-reminder.yml
error_reporting:
  destination: emit_incident (.claude/hooks/lib/incidents.sh → .claude/.rule-incidents.jsonl, local/per-machine) on gate deny AND on hook_self_fault error-fail-open; commit-time permissionDecisionReason on deny
  fail_loud: true
failure_modes:
  - mode: agent commits a last_reviewed change without the Context-Reviewed trailer
    detection: gate deny + emit_incident deny row; synchronous permissionDecisionReason
    alert_route: stderr at commit time + local incident ledger
  - mode: gate fails open on a genuine parse/cwd/-F-read error (never bricks commits)
    detection: emit_incident warn hook_self_fault (NOT silent) — distinct from benign fail-open
    alert_route: local incident ledger
  - mode: loader frontmatter-strip over-consumes rule body on malformed frontmatter
    detection: post-strip sentinel-rule-id survival + TOTAL_RULES pre==post assert → fail-closed loud
    alert_route: SessionStart hook error surface
  - mode: AGENTS.core.md silently dropped from the review-reminder scan (empty-cadence/continue)
    detection: run-time required-constitutional-path liveness assert → ::error:: fails the run
    alert_route: GitHub Actions run failure
logs:
  where: .claude/.rule-incidents.jsonl (local, best-effort, per-machine — NOT cross-machine) + commit-time stderr + Actions run log
  retention: per existing incidents convention
discoverability_test:
  command: "in a scratch git repo, stage a .md adding a '+...last_reviewed:' line and commit WITHOUT the trailer through the gate; assert stdout contains '\"permissionDecision\":\"deny\"'; repeat WITH a Context-Reviewed trailer and assert NO deny JSON"
  expected_output: case-1 stdout matches permissionDecision:deny; case-2 no deny JSON. Discriminate on the JSON, NOT exit code (PreToolUse deny exits 0).
```

## Acceptance Criteria

### Pre-merge (PR)
- **AC1.** Staged `last_reviewed:` change, no trailer → gate denies (`"permissionDecision":"deny"` on stdout). Test asserts on the JSON, not exit code.
- **AC2.** `git commit -am` bump with no trailer → gate denies (P0-2 regression — working-tree detection).
- **AC3.** Quoted / space-before-colon / case-variant `last_reviewed` **change**, and a `last_reviewed` line **deletion**, each without trailer → deny (P1-4). A **net-new** doc adding `last_reviewed` for the first time (only `+`, no `-`) → **allow** without trailer (architecture P2 — no trailer-fatigue).
- **AC4.** Commit message with the trailer in a 2nd `-m` paragraph, and via `-F file` → allow (P1-5 extraction).
- **AC5.** Genuine error path (`-F` unreadable) → fail-open (allows) AND emits a `warn` incident (obs P1 — not silent).
- **AC6.** Post-loader injected context for a frontmatter-bearing `AGENTS.core.md` contains the rule text but NOT `last_reviewed:` — asserted on BOTH the main-concat path AND the core-only fallback path (`:50`); a malformed-frontmatter fixture does NOT lose any `- [id:` rule line (over-strip guard).
- **AC7.** All THREE AGENTS lints (`lint-agents-rule-budget.py`, `lint-rule-ids.py`, `lint-agents-enforcement-tags.py`) pass with `AGENTS.core.md` frontmatter present; budget lint ERRORS (not shrinks) on the over-strip fixture; strip cross-check test proves loader and lint strip identically.
- **AC8.** Neither `brainstorm/SKILL.md:121` nor `cron-campaign-calendar.ts:108` instructs bumping `last_reviewed` (`grep` both) — both write `last_updated`.
- **AC9.** `review-reminder.yml` includes `AGENTS.core.md` in the scan AND fails the run (`::error::`) if that path is not evaluated (liveness assert).
- **AC10.** ADR-085 exists with the mechanism + boundary + the verbatim guarantee-boundary statement + reuse rationale + C4-none enumeration.

### Post-merge (operator)
- None. All steps are code + CI; nothing operator-only.

## Risks & Sharp Edges
- **Honest scope:** the gate only sees local Claude-Code Bash-tool commits — Warp/IDE/CI/Inngest commits bypass it entirely. This is why Phase 4 fixes the writers at source; the gate is a tripwire for *future/unknown* local-agent bumps, not a guarantee. Never describe it as preventing automated bumps.
- **Budget coupling:** Phase 2 (strip) MUST land with/before Phase 3 (frontmatter) — atomic; the single-sourced strip + cross-check test replaces hand-maintained regex parity.
- **Loader is fail-closed-critical:** the over-strip guard is load-bearing — a mangled sidecar is a governance blackout (single-user incident). Keep the strip aligned with the ≤200-byte header test.
- **PR-split option (simplicity):** if PR review finds the loader/lint blast radius too coupled to the gate, split — PR1 = gate + source fixes + ADR (the guarantee), PR2 = `AGENTS.core.md` under the clock. Default is one PR (operator chose to include the rule layer); the split is a de-risking lever.
- **Empty `## User-Brand Impact` fails deepen-plan Phase 4.6** — section is filled.

## Alternative Approaches Considered
| Approach | Verdict | Rationale |
|---|---|---|
| Frame the gate as a preventive "integrity guarantee" | Rejected (deepen) | Trailer self-attestable; `-am`/CI/Warp bypass. Honest frame: source-fix + audit tripwire. |
| A–F GPA grade surfaced every session | Rejected | Duplicates the overdue-issue channel; ambient noise; wrong surface. |
| `bump-frontmatter-updated.py` helper | Cut (deepen) | Neither writer calls it; the gate is the enforcement. |
| Separate threshold/registry file | Rejected | Second source of truth; reuse in-file `review_cadence` + one scanner. |
| Fund frontmatter via hard-rule body trim | Superseded | Trims loaded rule content for bytes the loader strips; lint-strip measures loaded bytes correctly. |
| Frontmatter on `AGENTS.md` index | Rejected | Raw YAML via harness `@`-import every session (unstrippable). |
