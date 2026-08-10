# Tasks — feat-one-shot-7387-legal-corpus-write-time-gates

Derived from [the plan](../../plans/2026-08-10-feat-legal-corpus-write-time-gates-plan.md)
**after** the five-agent panel + CLO review. Revision IDs (R1–R31) refer to the plan's
`## Plan Review Revisions` log. Closes #7387.

> **CLO status: BLOCKED pending amendments.** Amendments 1–5 and 11–12 are non-waivable. Phase 2
> must not begin until 1.6 is complete.

---

## Phase 0 — Preconditions (no code)

- [ ] 0.1 Re-measure per-pair drift with the real normalisers; record as diagnostics only (no literal enters any gate).
- [ ] 0.2 Re-measure every claim marker. Confirm `app.soleur.ai` = **140** (not 202) and `Web Platform` = 555 (R21).
- [ ] 0.3 Baseline `bash scripts/lint-orphan-test-suites.sh` → exit 0 **before** any change.
- [ ] 0.4 Baseline `bash apps/web-platform/scripts/check-tc-document-sha.sh` → exit 0.
- [ ] 0.5 Re-derive the four section-resolution hazard sites; record as **content anchors**, never line numbers (R21).
- [ ] 0.6 Push `2dd397542` to a durable remote ref, **or** confirm no AC depends on it (R22 / Kieran P0-4).
- [ ] 0.7 Settle `LC_ALL=C` + CRLF policy **before** Phase 1.1 — both change the drift hash (R28).
- [ ] 0.8 Record the ADR-139 `ALLOWED_PATHS ∩ SCAN_DIRS` derivation; confirm sound-by-unreachability (R29).

## Phase 1 — Shared normaliser extraction *(contract change — ships before its consumers)*

- [ ] 1.1 Create `scripts/lib/legal-normalise.sh`; three functions byte-identical; `LC_ALL=C` pinned.
- [ ] 1.2 Add a double-source guard **and** a direct-execution guard (`${BASH_SOURCE[0]} != $0`).
- [ ] 1.3 Refactor `check-tc-document-sha.sh` to source it via `BASH_SOURCE`-relative resolution, not CWD.
- [ ] 1.4 Preserve `^EXPECTED_COUNT=9` at line-start — a vitest guard parses this file's text (AC14b).
- [ ] 1.5 Prove behaviour preservation: T&C body SHA still `bae24228…`; guard still exits 0.
- [ ] 1.6 `scripts/lib/legal-normalise.test.sh` (auto-globbed by `test-all.sh`, **not** by the orphan lint — R5/P2-4).

## Phase 2 — Gate 1: scope-block placement *(respecified on REFERENT — R1)*

**Blocked on 2.0.** The escape hatch changes the parser, so it is not a bolt-on (R23).

- [ ] 2.0 Design the waiver as an **out-of-band ack ledger**, NOT an inline pragma (D1 —
      supersedes the earlier dual-surface plan). Create `.claude/legal-scope-block-acks.txt`:
      `<doc-path>#<anchor>|<sha256-of-normalised-block>|<date>|#NNNN|<ruling-doc-path>|<expires_on>|<reason>`.
      Rationale, all measured: the SHA pin is over the RAW file (`check-tc-document-sha.sh:234`), so
      any in-document comment forces a `LEGAL_DOC_SHAS` re-pin; `TC_DOCUMENT_SHA` is written to the
      WORM consent ledger (`accept-terms/route.ts:96`); `cla-evidence.yml:126` hashes
      `individual-cla.md` into R2 Object-Lock evidence; and CODEOWNERS owns **files, not line
      ranges**, so an in-document pragma is authored by the very engineer it is meant to constrain.
- [ ] 2.0b Content binding + replay protection from `lint-rule-bodies.py`: key on
      `sha256(normalised block)`; require the ack to be **newly added in this diff**
      (`head_acks - base_acks`, base via `git show <merge-base>:<ackfile>`).
- [ ] 2.0c Fail-closed parse (short/reasonless line is DROPPED, not honoured); anchored
      `^#[0-9]+$` issue regex; `expires_on` with offline date arithmetic + `--today` test override;
      fail CLOSED if `<ruling-doc-path>` does not resolve.
- [ ] 2.0d `.github/CODEOWNERS` entry pointing the ack path at the CLO — **this is the line that
      satisfies the authority requirement**; everything else is bookkeeping. Add WORM header.
- [ ] 2.0e AC: a waiver leaves every `docs/legal/*.md` byte-identical (no `LEGAL_DOC_SHAS` re-pin,
      no mirror edit, no consent/CLA evidence change) — the property the pragma design lacked.
- [ ] 2.1 **RED first** — fixtures for every arm, all synthesized (`cq-test-fixtures-synthesized-only`).
- [ ] 2.2 Added-lines extraction. Pin the hunk contract for **all four** shapes incl. count-omitted
      `@@ -2,0 +3 @@`; skip `+c,0`; key path off `+++ b/` (renames); skip `+++ /dev/null`;
      exclude `R`-status paths; `-c core.quotePath=false` (R22, R9).
- [ ] 2.3 Classifier (arm 0): locality assertion **+ referent token**. Delimiter is **not** a classifier (R2).
- [ ] 2.4 Broaden the delimiter to a pattern family; re-measure main-branch hits; report in PR body (R20).
- [ ] 2.5 Arm (a): fire only on `This section` referent in a marker-bearing section. Case-insensitive
      `web[ -]platform`. Verify **2 hits / 0 false positives** on the ruled-final tree (R1).
- [ ] 2.6 Arm (b): attachment must match referent — section→flush-left, limb→indented is legitimate (R3).
- [ ] 2.7 Arm (c): a classified block lacking a negative delimiter fails (R2).
- [ ] 2.8 Section resolution: `max(last_h2, last_h3)`; handle the null/preamble section; no `\d+\.\d+` assumption.
- [ ] 2.9 Marker calibration as a **floor (≥1)**, never equality (AC6).
- [ ] 2.10 Corpus-files-readable floor — **never** a floor on added lines (R30).
- [ ] 2.11 Failure message: numbered `Remediation:` block, modelled on `check-tc-document-sha.sh`.
- [ ] 2.12 **PASS message names what was not checked** and cites the CLO as authority (R25).
- [ ] 2.13 Mutation battery — neuter each arm independently; prove each mutation landed before trusting a verdict.

## Phase 3 — Gate 2: mirror drift ratchet

- [ ] 3.1 **RED first.**
- [ ] 3.2 Drift primitive: `^[<>]`-stripped **ordered sequence**; strip `NcN`/`NaN`/`NdN` + `---` (R6).
      Reuse `lint-shell-capture-exit.py`'s `fingerprint()` shape (path + class + whitespace-normalised
      text, deliberately NOT line-numbered) — an independent derivation of the same decision (D2).
- [ ] 3.3 Assertion is a **ratchet**: `driftset(HEAD) ⊆ driftset(base)`, order preserved. Reduction passes (R7).
- [ ] 3.4 Base = `git merge-base HEAD "$base_ref"`, **not** a tip ref; `merge_group` uses the ancestor SHA (R8).
- [ ] 3.5 `git fetch --no-tags --quiet origin <ref>` before resolving; `rev-parse --verify` or exit 2.
      **Fail CLOSED** — the repo is split (`lint-infra-no-human-steps.py` closed vs
      `lint-trap-tempfile-ownership.py` open); a blocking gate takes closed (D2).
- [ ] 3.6 Event-aware resolution incl. **push-to-main** — do not exit 2 on a legitimately absent base (arch P0-1).
- [ ] 3.7 Pair lifecycle: union of base+HEAD globs; new pair → drift must be 0; one-sided delete → fail;
      unpaired → exit 2 (R9). Copy `lint-rule-bodies.py`'s union-of-scopes anti-hack. **Decide the
      SE-1 rename question explicitly (D2):** when the base predates a rename, `git show <base>:<path>`
      is empty and a head-side rename reads as a *shrink*, silently hiding drift. Either add a
      git-history-free second oracle for the deletion direction, or justify `EXPECTED_COUNT` as one.
- [ ] 3.8 Enumerate pairs from the glob, not the literal 9; cross-check `EXPECTED_COUNT`.
- [ ] 3.9 Message: per drifting doc, both paths, direction, and a diff of the **drift sets** — not of the documents.
- [ ] 3.10 Header states what is frozen (published mirror under-discloses; name the Anthropic-US transfer
      and the Art. 15/20 export route) and cites #7349's date (R14, R15).
- [ ] 3.11 Mutation battery incl. the reorder case **and** a lockstep-shift no-fire case (R6).

## Phase 4 — Gate 3: obligation-checklist *(see UC-1 — operator decision pending)*

- [ ] 4.1 **RED first.** Input is a **sourced shell DSL**, not YAML — no `yq` exists (R18).
- [ ] 4.2 Verbs `obligation` / `deletion` / `preserve`; surface loop over `$C`/`$M`; `expect=0` refused.
- [ ] 4.3 Survivor assertions on **line numbers**; support both real shapes (line-set exclusion **and**
      inequality-against-a-heading) (R18).
- [ ] 4.4 Pre-edit validation against the merge-base tree; obligations must FAIL there.
- [ ] 4.5 Lifecycle: scope discovery to the branch spec dir; archive on merge, or the checklist reds
      every later PR (R19).
- [ ] 4.6 `anchor_covers` as a **measured identity** — anchored vs over-broad superset count, both
      declared, silent inequality exits 1 on the live corpus every run (R16).
- [ ] 4.7 Ruling-hash mismatch → **exit 1**, routed to the CLO (R27).
- [ ] 4.8 **PASS message reads necessary-not-sufficient**; names the other two discharge conjuncts and
      the CLO as attestation authority (R26).
- [ ] 4.9 If shipping here: declared home, named producer skill, glob-driven CI step, absence-detection
      predicate, and ≥1 **real committed** checklist executed (R24). Else drop the "live" line and say
      so in Non-Goals.
- [ ] 4.10 Mutation battery incl. the row-21 anchor-coverage shape.

## Phase 5 — Registration *(same commit as the code it registers)*

- [ ] 5.1 `run_suite` lines: unit + live per gate, **plus** `check-tc-document-sha.sh` (R12).
- [ ] 5.2 Add the three **live** gate scripts to `REQUIRED_RUNNERS` in `lint-orphan-test-suites.sh` (R10).
- [ ] 5.3 **No `.github/workflows/ci.yml` edit** — the gates already ride required `test` (R11).
- [ ] 5.4 `bash scripts/lint-orphan-test-suites.sh` → exit 0.
- [ ] 5.5 Confirm each suite appears **by name** in the CI run log, via numeric job ID +
      `grep -oE … | sort -u | wc -l` (R22).

## Phase 6 — Exit gate

- [ ] 6.1 `bash scripts/test-all.sh scripts` green.
- [ ] 6.2 `check-tc-document-sha.sh` green; `vitest run test/legal-doc-shas-guard.test.ts` green
      (grep the log for `FAIL`/`× ` — a background runner has reported exit 0 on a real failure).
- [ ] 6.3 Every AC checked individually against real output — **never** bulk-toggled.
- [ ] 6.4 PR body: corrected attribution (**4 of 10**, R13), the gate-3-detects-nothing caveat, and the
      #7372 interaction re-derived per R5.
- [ ] 6.5 `decision-challenges.md` rendered into the PR body and filed as `action-required` (UC-1, UC-2).
