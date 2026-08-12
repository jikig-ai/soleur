# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-12-fix-git-root-fallback-untrusted-anchor-plan.md`
- Draft PR: #7482
- Closes: #7450 (P0-critical, type/security)
- Status: complete
- Scope verified: `git diff <base>..HEAD --name-only` against base `325a1a5c0` listed only
  `knowledge-base/project/{plans,specs}/` files. No product code touched during planning.

### Collision gate (Step 0a.5 + post-plan re-probe)
- Typed refs checked: #6222 (OPEN), #7426 (MERGED PR — advisory), #7443 (MERGED PR — advisory),
  #7450 (OPEN, work target), #7453 (OPEN). No CLOSED issue refs; abort not triggered.
- #7450 body-probe hits #7443 and #6883 dispositioned by SCOPE intersection (the
  `closingIssuesReferences` discriminator is vacuous for body-probe hits): #6883 empty
  intersection; #7443 intersected only on `preflight/SKILL.md` + `review/SKILL.md`, while all
  five secret-gate anchors remained unmigrated on `main`. Verdict: **citation, not collision**.
- Post-plan re-probe: plan frontmatter `closes: 7450` — no divergence from the cleared target.
  Newly cited refs #5990/#6223/#7418 are CLOSED contextual citations; #7452 is an OPEN related
  follow-up, not a work target.

### Errors
- **4 of 7 review-panel agents failed during deepen-plan.** `security-sentinel` and
  `code-simplicity-reviewer` stalled on the 600s watchdog; `test-design-reviewer` and
  `spec-flow-analyzer` died on API connection errors. This leaves the **core security lens on a
  P0 security plan unreviewed**, plus YAGNI/AC-pruning, mutation-matrix adequacy, and flow /
  dead-end analysis. Recorded in the plan's coverage-gap table. **All four MUST be re-run at
  `/soleur:review` (Step 4) — this is the single most important carry-forward from planning.**
- Guard Contract lint initially failed (Guard 2 matrix missing the `**Mutation matrix**` field
  label the parser scopes to). Fixed; RC=0.
- Plan had an unterminated code fence, which fail-closes `lint-infra-no-human-steps.py`. Fixed.
- A `tasks.md` write was denied by the IaC write-guard on operator-action phrasing. Rephrased
  rather than using the ack opt-out (which would have asserted a review that never happened).
- Three self-authored ACs were mechanically broken and would have failed on `main` (AC1 used
  `git grep -c`, which is per-file not total; AC3 matched ADR-179's own documentation of the
  anti-pattern in `sync.md`; AC11's unscoped count is 2 because one occurrence is a
  must-survive quotation). All corrected.

### Decisions
- **Amend ADR-179; create no new ADR.** The anchor decision AC #1 asked for was already
  ratified — ADR-179 (accepted 2026-08-11) adopted the bare-anchor mechanism, rejected the
  alternatives, and its §R5 names these exact five sites as the subset that "goes first."
  The instrument is therefore *retiring a deferral*, not extending scope. The amendment must
  also replace ADR-179's Decision 2 code block, which ships the `test -d` shape its own
  §(a) Correction measured as bypassable.
- **Stale citation corrected:** the brief's "ADR-177" is wrong. ADR-177 is the test-runner
  result taxonomy; the bare-anchor ADR is **ADR-179**, renumbered from 177 inside commit
  `98ad03aa8`. #7453's GitHub title carries the same wrong ordinal.
- **Bare anchor + mandatory identity preflight with an `exit 2` else branch.** `sync.md` is the
  precedent, NOT `go.md` — `go.md`'s `else` branch does not exit, it continues degraded, and
  copying it onto a secret gate would port a fail-open arm onto the exact control this PR
  hardens. AC5c asserts the exit-2 dispatch, because grepping the condition alone would pass a
  fail-open copy.
- **AC #3 is already satisfied by #7426.** `worktree-manager.sh` now uses a three-level
  in-payload anchor (`$SCRIPT_DIR/../../../scripts/lib/session-state.sh`) to a file that exists
  in the payload. Independently confirmed against `main` before planning began. No work planned.
- **`compound` gets a NON-BLOCKING guard** — it authorises nothing, so fail-closed there is a
  pure operator regression; it stays in scope to preserve the corpus-wide-zero assertion.
- **The two `preflight` git-root sites route to #7453**, but their falsified rationale comment
  is corrected here — leaving a committed argument against the ratified doctrine is rule-corpus
  contamination.
- **A circular-evidence claim was retracted:** `preflight`/`review` were asserted as independent
  skills-surface evidence for the bare anchor, but they landed in the same commit as ADR-179.
  The plan now pays the measurement ADR-179 deferred.
- **Highest-severity finding folded in:** the `linear-fetch` guard as first drafted would have
  converted a refusal into a *leak* — `one-shot` and `brainstorm` are contractually required to
  substitute `persist_safe_summary`, and with it absent they fall back to `agent_context`,
  which carries signed Linear bearer URLs. Both callers added to Files to Edit.

### Sweep result (pre-implementation)
- 6 `:-$(git rev-parse` occurrences: 5 in scope, 1 benign (`--git-common-dir`).
- 45 `SCRIPT_DIR` climbing chains: **zero defects** — 35 test harnesses, 8 in-payload, 2 harness.
- **New site class the brief did not name:** 2 unconditional git-root anchors in
  `preflight/SKILL.md` (routed to #7453).

### Components Invoked
`soleur:plan` · `soleur:deepen-plan` · `soleur:engineering:cto` · `learnings-researcher` ·
`architecture-strategist` · `user-impact-reviewer` · `git-history-analyzer` ·
`security-sentinel` (FAILED) · `code-simplicity-reviewer` (FAILED) ·
`test-design-reviewer` (FAILED) · `spec-flow-analyzer` (FAILED) ·
`lint-guard-contract.py` · `lint-infra-no-human-steps.py` · `probe-verb-gate.sh`

---

## Work Phase (appended 2026-08-12)

Phases 0-6 complete and committed. PR #7482 pushed with full body; `Closes #7450` in the body.

| Phase | Outcome |
| --- | --- |
| 0 Preconditions | All six verified. Two plan corrections: the `redact-*.sh` discovery glob also matches a `.test.sh` harness; Pattern B is 43/45 depending on predicate. |
| 1 MEASURE (halt gate) | **POSITIVE for the measured construction.** Loader substitutes the bare token at delivery; `:-` arrives unsubstituted. Dissolves F14. Direct SKILL.md arm not runnable (registry built at session start) — residual stated. Found that `commands/go.md` is circular evidence too, which the plan missed. |
| 2 RED Guard 2 | Decoy resolved onto the planted script byte-for-byte. 86 pass / 1 fail. |
| 3 RED Guard 1 | G2 enumerated exactly the 4 executable sites; G5 missing preflight. Also surfaced + fixed a pre-existing unterminated fence in `deepen-plan/SKILL.md`. |
| 4 GREEN | 5 sites migrated + preflights + linear-fetch's missing guard + caller halt contracts. Guard 2 89/0, Guard 1 16/16. |
| 5 ADRs | ADR-179 amended (Decision-2 block replaced, §R5 corrected in place), ADR-093 premise falsified inline. No new ADR. |
| 6 Comments | #7453 and #6222 both commented, both verified OPEN. |
| 7 Exit | Mutation matrices **10/10** (zero survivors). Full `test-all.sh` queued behind 3 sibling runs on the advisory lock. |

**All 17 ACs verified with their literal commands** (see PR body §Verification).

### If resuming
The only outstanding item is the full-suite result at `/var/tmp/soleur-7450-exitgate/{full.log,rc}`.
Read the **rc file**, not a completion notification, and read BOTH ends of the log: the preamble
carries the contention banners (3 sibling `test-all.sh` runs were active at launch, so a RED needs
three-way confirmation) and the epilogue states whether the infra runner was covered.
Then `/soleur:review` → `/soleur:compound` → `/soleur:ship`.

### Phase 7 exit gate — CLEAN
`bash scripts/test-all.sh` → **rc=0, 298/301, 0 FAIL, 0 KILLED**. The 3 non-passes are `[skip]`
declines (2 relevance, 1 `not_in_diff`). Both guards ran green inside the run.

Two failures from the prior complete run were run down rather than re-run away:
- `phase-16.test.sh` — MINE. compound Phase 1.6 has a hard 1200-byte budget and was at 1189/1200
  on main; the skip guard was descoped rather than the threshold raised. Region now 1166.
- `run-migrations-unmerged-gate.test.ts` — NOT mine. Confirmed three ways: diff touches neither
  the test nor its subject; 3/3 in isolation; and it did **not recur** on the clean run.

---

## Resume session 2026-08-12 (post-review-panel remediation)

**These entries record what LANDED, verified against the artifact — not intent.** Every
row below is committed and its suite was run. (The prior block's `### Decisions` entries
are intent and were treated as unverified on entry, per the resume rule.)

### Done — committed, green, mutation-proven

| # | Work | Evidence |
| --- | --- | --- |
| 0 | **Merged `origin/main`.** #7475 landed mid-flight and touched `plugin-root-anchoring.test.ts` (+287), ADR-179 (+127), `go.md`, `sync.md`, `review/SKILL.md` — the exact files this work rebuilds. Findings §F's "main moved one commit … introduces no new members" is STALE. | clean merge, no conflicts |
| 1 | **CTO ruling on the §E fork** — binding, recorded at `cto-ruling-adr179-fork.md`. Dissolves the deadlock: decision 1 governs PATHS, so a telemetry emission need not be a path. Three framing corrections, one scope-changing (C1). | `d863182fc`.. |
| 2 | **Guard 1 rebuilt** — A1, A2, A3, A5, A8, A9, A10, A11, A13 closed. Per-occurrence verdict, halt bound to the preflight's own statement, identity-set pin, 7 synthesized fixtures as positive control, symlink-tolerant discovery, axis widened to `redact-*.py` + `digest-scrub.sh`. | 25/25; 8-mutation battery all RED vs GREEN control |
| 3 | **Guard 2 hardened** — A4 (cross-file floor, Test 20), A6 (resolve-before-containment), A7 (bash-fence-scoped oracle, exactly one), A12 (18c positive control), C15 (`SENTINEL\|SCRUBBER`), 18b strengthened to assert dispatch, `mkdir` guarded, contributor text no longer bash-expanded. | 92/0; 6-mutation battery, M-D proven non-equivalent |
| 4 | **linear-fetch C1–C4** — pipe restored via quoted heredoc, `$PERSIST_SAFE` printed, redaction-HAPPENED check added, blob-independent guards moved to a new **Phase B.0 pre-fetch preflight** so the halt precedes `agent_context`. | 4/4 suites |
| 5 | **All FOUR linear-fetch suites were unregistered**, not one as §G recorded — `test-all.sh` globs `skills/*/test/*.test.sh` and linear-fetch was the only skill putting `.test.sh` in `scripts/`. Relocated via `git mv`. | now inside the glob, 4/4 |
| 6 | **B2 trigger-cron** — bare quoted anchor + identity preflight + presence guard. Zero `:-` left in the file. | Guard 1+2 green |
| 7 | **B4 settings.json** — dead auto-approve entry deleted (measured dead: all 22 sites emit the `:-` form). Not replaced; that belongs with #7453. | JSON still parses |
| 8 | **CTO C1 — three payload SCRIPTS** (`gdpr-gate.sh`, `net-issue-flow.sh`, `token-efficiency-report.sh`) no longer source incidents.sh from the git root. | telemetry preserved 828→832 rows |

### Measured correction to the CTO ruling

The ruling prescribed resolving the incidents lib via `CLAUDE_PROJECT_DIR` alone.
**Measured: that variable is unset in a plain Claude Code session and in git hooks**, and
`gdpr-gate.sh` runs from lefthook — so a single-arm fix would have silently retired the
telemetry at all three sites while looking like a security fix. Its cited precedent
(`git-commit-secret-scan.sh`) falls back to `git rev-parse`, the banned construct. Shipped
two-armed: `CLAUDE_PROJECT_DIR`, else the script's own location (layout-invariant per
ADR-178, not CWD-derived), never git-root.

### NOT done — exact resume points

1. **B3 — the 20 markdown `source` sites + the capture hook.** The CTO's decision-9
   inversion: replace each `source … && emit_incident` with an inert `printf` marker, and
   add a monorepo-only **PostToolUse/`Bash`** hook that parses the marker and emits.
   **These must land TOGETHER** — markers without a consumer is the measurement blackout
   the ruling explicitly rejected. The hook MUST validate the rule id against a closed
   corpus and sanitize the note (the markdown that prompts the marker is
   contributor-writable on the review path). Use the two-arm resolver already shipped in
   item 8 for the hook's own lib resolution, NOT `CLAUDE_PROJECT_DIR` alone.
2. **B1 — root-outside-worktree assertion at all three gates.** Design tension to settle
   first, and it is real: on a plain (non-bare) clone the plugin root IS inside the working
   tree, so the naive assertion breaks dogfooding. It passes on THIS machine only because
   the install is the bare root while review happens in `.worktrees/`. Needs an explicit
   escape, or the CTO's §R1 framing applied (remove trust from CWD-resident operands rather
   than authenticate the tree).
3. **Records.** ADR-179 amendment carrying the ruling's decisions 8/9/10 verbatim + the
   §R1 replacement text + the option-(e) scoping (C5); ADR-093 paragraph restored
   BYTE-IDENTICAL with AC11's needle rescoped (C8); the 2026-07-08 plugin-root-migration
   learning superseded (D1 — highest-value one-liner); Pattern A count 6→5 with Pattern B's
   command published (C11); `tasks.md` 48 boxes (D5); C5, C6, C7, C9, C10, C12, C13, C14;
   D3, D4, D7.
4. **D6** — `phase-1-measurement.md` Arm 3's inference is logically void. Either run the
   deferred arm via headless `claude -p` (it builds its own skill registry, so the recorded
   "requires a fresh session" blocker is wrong) or drop the leg and rest on the two
   independent precedents.
5. **Re-route §R1's second half** — a review session opened inside a contributor-checked-out
   worktree executes that tree's `.claude/hooks/*.sh` on every tool call. Strictly larger
   than any path anchor, not an anchoring defect. File as a separate P0; it must NOT hold
   #7450 open.
6. **Full-suite exit gate has NOT been run this session.** Run it on a clean tree, detached
   (`setsid nohup`), and read the rc file plus the epilogue's infra-coverage line — not the
   task notification.
7. Then `/soleur:review` (min: security-sentinel, test-design-reviewer, structural-enumeration
   seat against the rebuilt guard) → `/soleur:compound` → `/soleur:ship`.

**Do NOT close #7450 until the ADR-179 §R1 replacement text is committed.**

---

## Resume session 2026-08-12, part 2 (post-CTO-ruling implementation)

Appended after the part-1 block. Same contract: every row is what LANDED, with its
evidence. Intent goes in the NOT-DONE table, never here.

### Landed since part 1

| # | Work | Evidence |
| --- | --- | --- |
| 9 | **B3 — the §E blocker, CLOSED.** All 20 `source` sites inverted to inert markers (ADR-179 decision 9) + a validating monorepo-only PostToolUse capture hook. Zero `source "$(git rev-parse …)/…/incidents.sh"` remain under `plugins/`. | capture hook 10/10; marker→hook and direct `emit_incident` produce BYTE-IDENTICAL rows |
| 10 | **ADR-179 decisions 8, 9, 10** recorded verbatim from the ruling, with rejected alternatives. **§R1 SETTLED** and scoped; its larger half (a review session executing the checked-out tree's `.claude/hooks/*.sh`) re-routed so it cannot hold #7450 open. | ADR-179 amendment, second half |
| 11 | **D1** — the falsified learning REVERSED. `synced_to: [work, plan]`, so it is agent-retrievable, and it named these three gates explicitly. | banner + frontmatter `superseded_by` + 3 inline markers |
| 12 | **C8** — ADR-093's premise restored BYTE-IDENTICAL (md5 vs `origin/main`); **AC11 inverted** to assert the record is retained AND marked, since the old AC was satisfiable only by deleting the evidence. | AC11's literal commands run: 1 / 1 |
| 13 | **C6** — ADR-179 no longer claims `compound` "correctly received" a skip guard that `7840b2a42` descoped. | corrected in place |
| 14 | **C7** — §(a)'s "command **or skill** file" scoped to SECRET-GATE skill files, matching G5's pinned population. | clause and guard now agree |
| 15 | **C14** — owning traps at BOTH gates (plan named only `incident`). | `trap 'rm -f "$DRAFT"' EXIT INT TERM HUP` |
| 16 | **D5** — tasks.md reconciled: 35 checked against evidence, 13 annotated rather than ticked. | addendum table |
| 17 | Four guard/lint failures the full suite surfaced, all self-inflicted, all fixed AT the guard. | see below |

### The four self-inflicted failures — recorded because the pattern matters

All four were introduced by this session's own changes and NONE was visible from the
touched-file loop:

1. `lint-shell-capture-exit-live` — the baseline is keyed by PATH, so `git mv` made 4
   pre-existing S1s read as NEW. Fixed, not re-baselined; dead baseline rows pruned.
2. `lint-trap-tempfile-ownership` — 3 relocated suites allocated tempfiles with no owning
   trap. Real leaks, invisible while the files sat where no path-scoped lint reached them.
3. `ship-undeferred-operator-step-gate.test.ts` — asserted the PRE-inversion
   `emit_incident` shape. Re-keyed to the marker, plus a negative pinning that the retired
   construct did not survive.
4. `scratch-path-collision.test.ts` — a waiver at the pre-`git mv` path. Its own assertion
   is "a stale waiver cannot absolve a future offender"; it caught this exactly.

### Findings re-measured against the merged tree

- **C7 — I first called this MOOT and was WRONG.** I checked Decision 2 ("per command
  file") and stopped; the clause the finding names is in §(a). It was live and is now fixed.
  Check the location a finding names, not the one that sounds like it.
- **C13 — genuine non-finding.** `sync.md`'s `exit 1` conflicts with no clause the ADR
  actually states. Recorded as measured, so nobody hunts for an edit that should not exist.
- **Findings §F is STALE in general.** It was measured before #7475 merged, and #7475
  touched `plugin-root-anchoring.test.ts` (+287), ADR-179 (+127), `go.md`, `sync.md` and
  `review/SKILL.md`. Re-measure any §F claim before relying on it.

### Correction to the CTO ruling, measured

The ruling prescribed resolving the incidents lib via `CLAUDE_PROJECT_DIR` alone.
**Measured: unset in a plain Claude Code Bash call and in git hooks** — and `gdpr-gate.sh`
runs from lefthook — so a single-arm fix would have silently retired the telemetry while
looking like a security fix. The cited precedent (`git-commit-secret-scan.sh`) itself falls
back to `git rev-parse`, the banned construct. Shipped two-armed. **The hook may rely on
`CLAUDE_PROJECT_DIR`** (the harness sets it for hook processes); **a payload script may
not.** That distinction is recorded in the ADR.

### NOT done — exact resume points

1. **B1 — root-outside-worktree at all three gates.** Design tension UNRESOLVED and real:
   on a plain (non-bare) clone the plugin root IS inside the working tree, so the naive
   assertion breaks dogfooding. It passes on this machine only because the install is the
   bare root while review runs in `.worktrees/`. Settle it against the CTO's §R1 framing
   (remove trust from CWD-resident operands rather than authenticate the tree) before
   implementing — do not just add the `case` from the findings.
2. **C9** self-contradictory halt messages, **C10** `SOLEUR_*` telemetry markers on the
   three new halts, **C12** AC5d (no test asserts `[ -n "$PERSIST_SAFE" ]`).
3. **D3** ADR-093 still asserts the pre-fix state as current; **D4** ADR-179
   §Relationship/§Consequences/frontmatter; **D7** the negative branch's blast radius.
4. **D6** — `phase-1-measurement.md` Arm 3's inference is logically void. Run the deferred
   arm via headless `claude -p` (it builds its own registry, so the recorded "requires a
   fresh session" blocker is wrong) or drop the leg and rest on the two precedents.
5. **File the re-routed §R1 P0** — review sessions must not load hooks from a
   contributor-checked-out tree.
6. `/soleur:review` (min: security-sentinel, test-design-reviewer, structural-enumeration
   seat against the REBUILT guard) → `/soleur:compound` → `/soleur:ship`.

**§R1 is now fully discharged:** the ADR text is committed AND the re-route is filed as
**#7502** and named in the ADR. #7450 is no longer blocked on §R1.

---

## Resume session 2026-08-12, part 3 (B1 settled by measurement; records closed)

Same contract as part 2: every row is what LANDED, with evidence. Intent lives in the
NOT-DONE list only.

### Merged `origin/main` FIRST, before any edit

The branch was **2** behind, not 1: `#7473` (plugin delivery / keyless manifests) and
`#7458` (git-data template strip) had both landed. Clean merge, no conflicts. Re-checked
afterwards: neither touches `go.md`, `sync.md`, `plugin-root-anchoring.test.ts`, ADR-179 or
ADR-093, so no premise of this work moved. `review/SKILL.md` gained 2 lines, unrelated to
anchoring.

### Landed

| # | Work | Evidence |
| --- | --- | --- |
| 18 | **D6 discharged by EXECUTING the deferred arm, not dropping it.** Headless `claude -p --plugin-dir` with a synthetic plugin. The recorded "requires a fresh session" blocker was wrong — it builds its own registry. | `phase-1-measurement.md` Arm 4 |
| 19 | **B1 SETTLED — not implemented, and that is the finding.** The panel's `case` guards an operand the adversary cannot reach, breaks dogfooding on every plain clone, and re-adds `git rev-parse` to the three gates this PR de-git-roots. | `b1-disposition.md` |
| 20 | **The B1 invariant is PINNED** (Test 21), fence-scoped so prose explaining the ban is not flagged as violating it. | Guard 2 95/0 |
| 21 | **C9** halt messages no longer tell the operator to re-run the skill they are inside; each prints the resolved root and discriminates empty-root from wrong-root. | 3 gates |
| 22 | **C10** all 11 fail-closed halts emit `SOLEUR_*_HALT reason=` on **stdout**; Test 22 asserts the marker is not redirected to stderr. | Guard 2 Test 22 |
| 23 | **C12/AC5d** now test-enforced — deleting `[ -n "$PERSIST_SAFE" ]` reddens, and so does neutering its halt arm. | Guard 2 Test 23 |
| 24 | **D3, D4, D7** closed across ADR-093 and ADR-179, plus ADR-179 decisions 10 and 11. | commit `e4f4fd2ed` |
| 25 | **Battery 3**: GREEN control, **6/6 RED**, incl. a harness mutation. | `battery-3-mutations.sh`, `mutation-matrices.md` |

### The measurement, because it is the load-bearing result of this session

One session, one environment, with `CLAUDE_PLUGIN_ROOT=/tmp/DECOY-EVIL-ROOT` set ambiently:

| Form in a `SKILL.md` bash fence | Result |
| --- | --- |
| bare `${CLAUDE_PLUGIN_ROOT}` | **substituted at delivery** with the real install root — decoy ignored |
| `${CLAUDE_PLUGIN_ROOT:-…}` | literal, then expanded at runtime to **`/tmp/DECOY-EVIL-ROOT/…`** |
| control: decoy inside the executing Bash subprocess | present, `ENV_GREP=[1]` |

The control is the part that matters. Without it, "ambient ignored" and "ambient never
propagated" predict identical bytes, and the first reads as safety. With it: at a bare-anchored
site the token is **not a shell variable at execution time**, and the pre-fix form is a
**reproduced** exploit rather than a modelled one.

### Two findings re-measured, both corrections to this session's own first answer

- **Test 21 initially reddened on my own prose.** The B1 rationale I had just written names
  `git rev-parse` while explaining its removal, and an unscoped grep flagged the documentation
  of a ban as a violation of it. Fixed by scoping to `bash` fences — and an anti-vacuity control
  was added at the same time, because a scoping bug that yields an empty stream would make the
  assertion pass unconditionally (the A12 false-PASS shape). M-B proves the control is live.
- **Battery 3's M-F failed to APPLY on its first run** (a quoting error) and was reported
  `NOT APPLIED — row VOID`, not as a survivor. Recorded rather than quietly re-run, because the
  natural response to a "survivor" is to weaken the assertion — a battery whose own bugs push
  toward deleting real coverage.

### Not from the panel — found while verifying the surface map

`agent-env.ts`'s security comments named the `:-` form as what the injection protects and cited
`redact-sentinel.sh` and `trigger.sh` as its examples. This PR migrated both. Corrected without
weakening the invariant: the injection still carries the ~105 unmigrated sites, so it stays
fail-closed, and the comment now says so to stop a later reader "simplifying" it.

### NOT done — exact resume points

1. **Grok Build residual.** Whether a bare `${CLAUDE_PLUGIN_ROOT}` is substituted on that
   harness is UNMEASURED; no handling exists in `lib/harness.ts` or `.grok/`. Stated in
   `b1-disposition.md` and ADR-179 decision 11, not closed. This is the one condition that
   would reopen B1.
2. Full-suite exit gate, PR body, then `/soleur:review` → `/soleur:compound` → `/soleur:ship`.

**#7450 may close at ship** — §R1 is fully discharged (ADR text committed AND re-routed as
#7502, which the ADR names).
