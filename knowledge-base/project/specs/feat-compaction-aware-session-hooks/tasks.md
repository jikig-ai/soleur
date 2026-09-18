---
feature: compaction-aware-session-hooks
lane: cross-domain
branch: feat-compaction-aware-session-hooks
issue: 8323
plan: knowledge-base/project/plans/2026-09-18-feat-compaction-aware-session-hooks-plan.md
---

# Tasks: Compaction-Aware Session Hooks

Derived from the plan **after** its six-agent review. Four mechanisms were deleted at review (checkpoint writer → #8328, token-ratio clause, phase derivation, the `one-shot` Step 8 edit); they are absent here by design, not by omission.

## Phase 0 — Payload probe (blocking) — **DONE 2026-09-18**

Run without an operator step: a scratch project under `/var/tmp` with its own `.claude/settings.json`,
driven by headless `claude -p --continue "/compact"`. Nothing was bound into this repo, so 0.5 is vacuous.
Full results: the plan's `## Addendum — 2026-09-18 (Phase 0 payload probe: measured results)`.

- [x] 0.1 Bind a throwaway marker hook to `PreCompact` and `SessionStart` (also `PostCompact`), logging: timestamp, `hook_event_name`, `source`/`trigger`, sorted top-level stdin keys, `transcript_path`, the `compact_boundary` count read from that path, and the last boundary's `trigger`. — 12 events captured.
- [x] 0.2 Force one `/compact`; then a second after re-growing context. — 3 `PreCompact` fires, 2 real boundaries.
- [x] 0.3 Record dated findings: `source` is literally `compact`; `transcript_path` is **stable** across the compaction; `--fork-session` starts a new session id + new transcript (no `SessionStart` hook fired at all); **the observed count EXCLUDES the compaction that just fired — off by exactly one, measured twice.**
- [x] 0.4 Count excludes the current compaction ⇒ the pre-authorized `TMPDIR` fallback ships, **corrected to pending-then-commit**: a plain append-per-`PreCompact` over-counts, because `PreCompact` fires on no-op compactions (measured 3:2). `PreCompact` overwrites one `pending` slot; `SessionStart:compact` commits it as one line and counts; `SessionStart:startup|resume|clear` truncates the ledger (this is TR2's window scoping, exactly rather than approximately).
- [x] 0.5 Probe and its scratch project deleted; no `.claude/settings.local.json` entry was ever created.

## Phase 1 — `compaction-state.sh` read path (FR1, FR2) — **DONE**

- [x] 1.1 **RED:** `plugins/soleur/test/compaction-state-hook.test.sh` written first — 70 failing cases, subject-invocation floor at 0, against the absent script.
- [x] 1.2 `plugins/soleur/hooks/compaction-state.sh`: dispatch on `hook_event_name`; `SOLEUR_DISABLE_COMPACTION_HOOKS=1` short-circuit; `set -uo pipefail`; `trap 'exit 0' ERR EXIT`. The EXIT arm is load-bearing and now **measured**, not asserted: on bash 5.3.15 an ERR-only trap lets a `set -u` fault exit **127**, the EXIT arm returns 0.
- [x] 1.3 **TR1 scope guard:** walks up from the envelope's `cwd` for a directory carrying `plugins/soleur` **and** a `knowledge-base/project/{plans,specs}` artifact. Both conjuncts mutation-proven (M9, M10).
- [x] 1.4 `count_auto` derived from the per-session ledger, not the transcript — Phase 0 measured that the transcript cannot answer at this point. Window scoping is the reset arm, so it is exact rather than approximated.
- [x] 1.5 Rule: `trigger == "auto" AND count_auto >= ${SOLEUR_COMPACTION_COUNT_THRESHOLD:-2}`. Both operands mutation-proven (M3, M4, M5); a non-numeric threshold falls back to 2 rather than making `(( ))` silently evaluate false.
- [x] 1.6 Envelope built with `jq -n --arg`; markers and the CLI version live **inside `additionalContext`**; stdout carries JSON only (M12); truncated at 8,000 chars.
- [x] 1.7 Static `printf`'d JSON literal for the `jq`-unavailable path (M17), with no interpolation and therefore nothing to escape.
- [x] 1.8 **GREEN:** 95/95 cases, 99 subject invocations.

## Phase 2 — `PreCompact` summary shaping (FR3) — **DONE**

- [x] 2.1 Static plain-text stdout naming branch, worktree, PR #, issue #, plan path, active skill/phase, unchecked acceptance criteria, Operator Holds and every file path. Not JSON (M18). Exit 0 always; never exit 2.
- [x] 2.2 Same TR1 scope guard, asserted for `PreCompact` specifically — this is the path that would otherwise reach a stranger's summarizer.
- [x] 2.3 Scenario 12 passes, including the negative: it never asks the summarizer to reproduce file contents.

## Phase 3 — Prose retirement + docs (FR5, FR6) — **DONE**

- [x] 3.1 `plan/SKILL.md`: both `/clear` **recommendations** are now conditional on a `SOLEUR_COMPACTION_DIRECTIVE` marker with `recommend=true`. The two `**Resume prompt (MANDATORY…)**` blocks verified **byte-identical** to `origin/main` by diff (AC15).
- [x] 3.2 `work/SKILL.md`: the unconditional `Tip: After shipping, run /clear…` is replaced by an **unconditional** end-of-work resume prompt plus a conditional nudge. The three silent states — never compacted, kill-switched, non-Claude harness — are named at the site, so the retirement leaves no dead end.
- [x] 3.3 `plugins/soleur/README.md`: new `## Compaction-Aware Session Hooks` section with all three env vars and a 4-row harness table (Claude supported; Codex, Devin and Grok degrade to silence, never to a false claim).
- [x] 3.4 `devin/INSTRUCTIONS.md` and `codex/INSTRUCTIONS.md` each carry the Claude-only degradation. The Devin note sits **outside** the "Measured hook semantics (envelope capture: …)" list — that capture does not cover this claim, and filing it as a bullet there would have attributed it to a measurement that never took place.
- [x] 3.5 `hooks.json`: `PreCompact` (`manual|auto`) + `SessionStart` (`startup|resume|clear|compact`); no `PostCompact` key. Asserted by scenario 16 and mutation-proven (M20).

## Phase 4 — Drift canary (FR7) — **DONE, with a corrected registration**

- [x] 4.1 `scripts/followthroughs/compaction-format-drift-8323.sh`, keeping the sweeper's 0/1/2 exit contract. All four arms driven: PASS on the operator's real transcripts (9 boundaries / 40 files), FAIL on a boundary-less corpus, FAIL on a **renamed** `subtype` (the drift it exists for), TRANSIENT on a missing directory — plus a positive control proving it can still pass.
- [x] 4.2 **Registered locally, not as a `soleur:schedule` GitHub Actions cron.** Measured: the canary reads `~/.claude/projects/**/*.jsonl`, a GitHub runner has none, and the canary correctly reports TRANSIENT when it cannot measure — so that registration yields a probe that can never PASS and never FAIL. It is bound instead to the repo-side `SessionStart` surface via `.claude/hooks/compaction-drift-canary.sh`, stamp-gated to once per 7 days, always exit 0, reporting a `SOLEUR_COMPACTION_DRIFT` marker on stderr. **AC17 and AC21 are amended accordingly** — see the plan addendum.
  - The wrapper shipped a real bug caught by driving its arms rather than reading it: `out="$(…)"` is a simple command, so a non-zero canary status fired the `ERR` trap and the wrapper exited 0 having printed nothing. `|| rc=$?` puts it in a tested context. The same exemption is what makes `compaction-state.sh`'s `[[ -n "$PLAN" ]] && …` lines safe, which scenario 21 now pins.

## Phase 5 — ADR + C4 + register — **DONE**

- [x] 5.1 **`ADR-227`**, not 228. The plan's ordinal was provisional and was stale: a scan of all **96** `origin/*` refs found `ADR-228-generated-operator-scripts-are-non-interactive-by-default.md` already claimed by `feat-one-shot-8287-operator-bootstrap`, and 225/226 taken too. 227 is free everywhere. Renumbered across all 4 citing files, verified by grepping the **old** number to 0 residual. The ADR records all alternatives (a)–(k), including the deleted checkpoint writer with both its P0s for #8328, the deleted ratio clause and phase derivation, and the rejected GH-Actions canary registration — and records that this is the first customer-shipped consumer of the transcript format, with the retracted "the fixtures pin the parsed shape" answer named as retracted.
- [x] 5.2 `model.c4`: all **three** falsified relationships amended — the `hooks` container's **`technology`** line (the string the plan's earlier AC targeted wrongly), the surface-split sentence in its description (now scoped to resource control, with the shipped surface named as a compaction-lifecycle consumer), and the `claude -> hooks` edge (the envelope is also a **pointer**; technology is now `stdin JSON + transcript file read`). `model.likec4.json` regenerated; `c4-count-parity.test.sh` green.
- [x] 5.3 `principles-register.md`: **AP-020 widened** in-row (the AP-020 precedent is that an ADR-only note leaves the register silently contradicted). Recorded as a scope **widening**, not a carve-out — no violation is accepted — with the two consequences the envelope-only scoping did not reach: nothing read from the pointed-at file may be echoed into `additionalContext`, and an unreadable pointer is a normal state (measured at `SessionStart:startup`, where the file does not yet exist). Table pipe count verified unchanged at 6, matching the sibling row.
- [x] 5.4 `spec.md` reconciled in place with a second revision note; the plan's `## Overview` carries a superseded-in-part marker pointing at the addendum, rather than being rewritten.
- [x] 5.5 (added) The brainstorm learning `2026-09-18-compaction-state-lives-in-the-transcript-not-a-counter-file.md` is **superseded by append**, never rewritten: its title, `## Solution` and `## Key Insight` assert the falsified claim. The addendum records what the probe measured, notes that §Problem's two rejected premises are still correct, corrects the Key Insight's second clause (*persisted* and *readable when you need it* are different properties), and its `**Prevention:**` line prescribes the probe rather than the conclusion.

## Phase 6 — Verification

- [x] 6.1 All acceptance criteria checked against real command output, **one at a time** — never a bulk checkbox toggle. 21 of 22 pass (AC1–AC19, AC21, AC22); each AC in the suite's scope is mapped to the named case that asserts it, and the mapping printed `ok` for all 13. AC17's text is amended in place rather than ticked against a criterion that no longer describes what shipped.
- [ ] 6.2 `TEST_GROUP=all bash scripts/test-all.sh` — **rc=4, REFUSED, nothing ran.** A sibling worktree held a full-gate run (measured, #7553). Not a pass and not a fail; overriding with `SOLEUR_ALLOW_FULL_GATE=1` would put two full gates on one box, which is what the refusal prevents. Substitute set derived from the diff's new `SOLEUR_COMPACTION_*` vocabulary and from consumers of the changed artifacts (20 suites + 4 vitest c4 files) all green — see the plan's AC20 note for the roster. The battery runs at the `/ship` Phase 4 checkpoint, its sanctioned position (ADR-183).
- [x] 6.3 `c4-count-parity.test.sh` green; `c4-model-freshness.test.sh` green after regenerating `model.likec4.json`; 4 vitest `c4-*` suites, 36 tests, green run CI-equivalent (no Doppler).
- [ ] 6.4 `/soleur:review`, then `/soleur:compound`, then `/soleur:ship`.
