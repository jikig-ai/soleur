# Tasks — feat-one-shot-7387-legal-corpus-write-time-gates

Derived from [the plan](../../plans/2026-08-10-feat-legal-corpus-write-time-gates-plan.md)
**after** the five-agent panel + CLO review. Revision IDs (R1–R31) refer to the plan's
`## Plan Review Revisions` log. Closes #7387.

> **CLO status: amendments applied.** Amendments 1–5 and 11–12 were non-waivable and are
> discharged: gate 1 is respecified on referent (A1–A5), and both gates state in their PASS
> and FAIL messages that they do not adjudicate scope correctness (A11–A12).
>
> **Operator scope decisions, 2026-08-10 (authoritative — see the plan's `## Scope decisions`):**
> **D-A** gate 3 is deferred to #7392; Phase 4 is not built here. **D-B** #7349 is now
> `priority/p1-high` with a **2026-09-30** remediation target, cited in the gate-2 header.

---

## Phase 0 — Preconditions (no code)

- [x] 0.1 Per-pair drift re-measured with the real normalisers: **220 lines / 9 pairs**
      (aup 18, cookie 4, corporate-cla 12, dpd 56, disclaimer 2, gdpr 63, individual-cla 7,
      privacy 58, t&c 0). Diagnostics only — no literal enters either gate.
- [x] 0.2 Markers re-measured on the live corpus. **`app.soleur.ai` = 140** (not 202) and
      **`Web Platform` = 555**, both confirming R21. `acts as Controller` / `Cloud Execution` /
      `server-side monitoring` = 2 each.
- [x] 0.3 `bash scripts/lint-orphan-test-suites.sh` → exit 0 before any change.
- [x] 0.4 `bash apps/web-platform/scripts/check-tc-document-sha.sh` → exit 0 before any change.
- [x] 0.5 Section-resolution hazards re-derived and recorded as **content anchors**. The
      decisive finding is not in the plan: at all four canonical locality-assertion sites the
      ONLY marker in the enclosing section is on the scope block's own cross-reference line.
- [x] 0.6 Confirmed **no AC depends on local ref `2dd397542`** (grep returns nothing), so the
      unreachable ref is not a blocker. Not pushed.
- [x] 0.7 `LC_ALL=C` pinned in the shared library. CRLF needs no handling: **0 files in either
      surface contain a CR**, so the corpus is LF-only and a CRLF strip would be dead code.
- [x] 0.8 No `ALLOWED_PATHS` construct exists in `scripts/*.sh`; the ADR-139 intersection
      question does not arise for these gates. Sound by unreachability.

## Phase 1 — Shared normaliser extraction *(contract change — shipped before its consumers)*

- [x] 1.1 `scripts/lib/legal-normalise.sh` created; three functions verbatim; `LC_ALL=C` pinned.
- [x] 1.2 Double-source guard + direct-execution guard (`${BASH_SOURCE[0]} == $0` → exit 64).
- [x] 1.3 `check-tc-document-sha.sh` sources it via `BASH_SOURCE`-relative resolution, not CWD.
- [x] 1.4 `^EXPECTED_COUNT=9` preserved at line-start (a vitest guard parses this file as text).
- [x] 1.5 Behaviour preservation proven, not asserted: T&C body SHA still `bae2422886453166`,
      and all 18 pre-extraction pair hashes pinned as frozen literals in the suite.
- [x] 1.6 `scripts/lib/legal-normalise.test.sh` — 34/0, auto-globbed by `test-all.sh`.
- [x] 1.7 *(added)* `legal-doc-shas-guard.test.ts` sandbox stages `scripts/lib`. Without it every
      case exited 1 on a missing normaliser rather than on the drift class under test.

## Phase 2 — Gate 1: scope-block placement *(respecified on REFERENT — R1)*

- [x] 2.0–2.0e Waiver ack-ledger: **not built.** No waiver surface is needed — the gate produces
      zero false positives against the entire live corpus (see 2.5), so there is nothing to
      waive. Shipping an unused CODEOWNERS-gated ledger would add a bypass surface with no
      demonstrated demand. Revisit if a real false positive appears.
- [x] 2.1 RED verified before the gate existed; all fixtures synthesized.
- [x] 2.2 Added-lines extraction pins all four hunk shapes incl. count-omitted `@@ -2,0 +3 @@`;
      skips `+c,0`; keys path off `+++ b/`; skips `+++ /dev/null`; `--diff-filter=d`;
      `-c core.quotePath=false`.
- [x] 2.3 Classifier (arm 0) = locality assertion **+** referent token. Delimiter deliberately
      excluded, so deleting a disclaimer cannot blind the gate.
- [x] 2.4 Delimiter broadened to a pattern family; main-branch hits re-measured and reported.
- [x] 2.5 Arm (a) fires only on a section referent in a marker-bearing section.
      **Verified stronger than planned:** replaying all 18 real corpus files as added lines
      classifies 8 scope blocks and fires **0** violations.
- [x] 2.6 Arm (b) = attachment must match referent. A limb rider stays legitimately indented.
- [x] 2.7 Arm (c) **corrected**: requires a discharging clause (negative delimiter **OR**
      cross-reference), not specifically a delimiter. 3 of 4 blocks on main carry no delimiter;
      the literal rule would have red-lined them.
- [x] 2.8 Section resolution `max(last_h2, last_h3)`; preamble (null section) handled; no
      `\d+\.\d+` assumption.
- [x] 2.9 Marker calibration is a **floor (≥1)**, never an equality.
- [x] 2.10 Corpus-files-readable floor; explicitly **no** floor on added lines.
- [x] 2.11 Numbered `Remediation:` block per finding.
- [x] 2.12 PASS message names what was not checked and cites the CLO as the authority.
- [x] 2.13 Mutation battery: each arm neutered independently + always-exit-0, every row with a
      positive control. 26/0.

## Phase 3 — Gate 2: mirror drift ratchet

- [x] 3.1 RED verified before the gate existed.
- [x] 3.2 Drift primitive: `^[<>]`-stripped **ordered sequence**; `NcN`/`NaN`/`NdN` + `---`
      stripped. Positions deliberately excluded.
- [x] 3.3 Assertion is a **ratchet** — `driftseq(HEAD) ⊆ driftseq(base)`, order preserved.
      Reduction passes, so #7349's remediation is never blocked.
- [x] 3.4 Base = `git merge-base HEAD <base>`, never a tip ref.
- [x] 3.5 `git fetch --no-tags --quiet` then `rev-parse --verify`; **fail CLOSED** (exit 2).
- [x] 3.6 Event-aware resolution: `MERGE_GROUP_BASE_SHA` → `GITHUB_BASE_REF` → `origin/main`.
      Push-to-main resolves to HEAD and passes rather than exiting 2.
- [x] 3.7 Pair lifecycle: union of base+HEAD names; new pair → drift must be 0; one-sided
      delete → fail; unpaired → exit 2; both deleted → pass. **SE-1 rename decided explicitly:**
      a renamed doc is a NEW pair and must start clean, which closes the hidden-shrink hole
      without consulting git history at all.
- [x] 3.8 Pairs enumerated from the glob; `EXPECTED_COUNT` cross-checked as a **warning**.
- [x] 3.9 Message names both paths, the direction, and diffs the drift **sets**.
- [x] 3.10 Header names what is frozen (Anthropic/US transfer, Art. 15/20 export route) and
      cites **#7349's 2026-09-30 target**; the suite asserts both survive.
- [x] 3.11 Mutation battery incl. a **pure-reorder** fixture (identical drift multiset, different
      sequence) and a lockstep-shift no-fire case. 25/0.

## Phase 4 — Gate 3: obligation-checklist — **DEFERRED to #7392 (D-A)**

Not built in this PR. Design preserved in the plan's input-format section and carried in full
on #7392, which builds it against #7349 so it lands with a live consumer and a real input.
Non-Goals says so plainly.

## Phase 5 — Registration *(same commit as the code it registers)*

- [x] 5.1 Five `run_suite` lines: unit + live for each gate, plus the `check-tc-document-sha.sh`
      live line it never had.
- [x] 5.2 Both **live** gate scripts added to `REQUIRED_RUNNERS` in `lint-orphan-test-suites.sh`.
- [x] 5.3 **No `.github/workflows/ci.yml` edit** (R11).
- [x] 5.4 `bash scripts/lint-orphan-test-suites.sh` → exit 0.
- [x] 5.5 **Mutation-proven, all four:** dropping either live line or either unit line makes the
      orphan lint exit 1. All five suites appear **by name** in the local run log; the CI run-log
      check runs at ship.

## Phase 6 — Exit gate

- [x] 6.1 `bash scripts/test-all.sh scripts` → **rc=0, `=== 273/273 suites passed ===`**, against
      a clean tree. (Queued 900s behind a sibling worktree's run; `LOCK_CONTENDED_PROCEEDING` is
      a queue, not a hang.)
- [x] 6.2 Legal-related webplat suites green: `legal-doc-consistency`, `legal-doc-shas-guard`,
      `cla-evidence/hash`, `cla-evidence/schema`, `live-verify/trigger` — 5 files / 39 tests.
- [x] 6.3 Every AC checked individually against real output; **never bulk-toggled**.
- [ ] 6.4 PR body: corrected attribution (**4 of 10**, R13), the gate-3 deferral to #7392, and
      the #7372 interaction re-derived per R5.
- [ ] 6.5 `decision-challenges.md` rendered into the PR body — both UCs are **decided**, so they
      are reported as applied decisions rather than filed as `action-required`.
