# Tasks — feat-one-shot-7387-legal-corpus-write-time-gates

Derived from [the plan](../../plans/2026-08-10-feat-legal-corpus-write-time-gates-plan.md)
**after** the five-agent panel + CLO review, then **rewritten after the ten-agent
post-implementation review**, which found ~55 findings — 2 CRITICAL, 1 BLOCKER, ~15 HIGH —
every one of which passed the 85 green assertions the first implementation shipped with.

Revision IDs (R1–R31) refer to the plan's `## Plan Review Revisions` log. Closes #7387.

> **CLO status: amendments applied.** Amendments 1–5 and 11–12 were non-waivable and are
> discharged: gate 1 is respecified on referent (A1–A5), and both gates state in their PASS
> and FAIL messages that they do not adjudicate scope correctness (A11–A12).
>
> **Operator scope decisions, 2026-08-10:** **D-A** gate 3 deferred to #7392. **D-B** #7349
> raised to `priority/p1-high` with a **2026-09-30** target, cited in gate 2 and enforced by
> an expiry check. **D-C** fix every review finding in this PR rather than splitting.

---

## Phase 0 — Preconditions (no code)

- [x] 0.1 Per-pair drift re-measured: **220 lines / 9 pairs** (aup 18, cookie 4, corporate-cla
      12, dpd 56, disclaimer 2, gdpr 63, individual-cla 7, privacy 58, t&c 0). Note the gate
      counts NON-BLANK lines (189); the 220 figure includes the 31 blanks.
- [x] 0.2 Markers re-measured: **`app.soleur.ai` = 140** (not 202), **`Web Platform` = 555**,
      `acts as Controller` / `Cloud Execution` / `server-side monitoring` = 2 each.
- [x] 0.3 `lint-orphan-test-suites.sh` → exit 0 before any change.
- [x] 0.4 `check-tc-document-sha.sh` → exit 0 before any change.
- [x] 0.5 Section-resolution hazards re-derived as content anchors. **Corrected at review:** at
      **three** of the four canonical locality-assertion sites the only marker in the enclosing
      section is on the block's own cross-reference line; the fourth (`privacy-policy.md:269`)
      has **no marker in its section at all**. The own-line exclusion is still right — mutating
      the gate to scan the own line reds 3 of 4 — but the original claim was wrong at 25% of its
      evidence base.
- [x] 0.6 No AC depends on local ref `2dd397542`.
- [x] 0.7 `LC_ALL=C` pinned. CRLF needs no handling: 0 files in either surface contain a CR.
      Review confirmed the pin is a real behavioural change, not a no-op (an H1 beginning `É`
      is stripped under UTF-8 and survives under C) — currently unexercised, correctly pinned.
- [x] 0.8 No `ALLOWED_PATHS` construct in `scripts/*.sh`; ADR-139 intersection does not arise.

## Phase 1 — Shared normaliser extraction *(contract change — ships before its consumers)*

- [x] 1.1 `scripts/lib/legal-normalise.sh`; three functions verbatim; `LC_ALL=C` pinned.
- [x] 1.2 Double-source guard + direct-execution guard (exit 64).
- [x] 1.3 `check-tc-document-sha.sh` sources it `BASH_SOURCE`-relative, not CWD.
- [x] 1.4 `^EXPECTED_COUNT=9` preserved at line-start (a vitest guard parses this file as text).
- [x] 1.5 Behaviour preservation proven byte-for-byte, and **independently re-derived at
      review** from the functions as they existed at `cdc42a5df^`: all 18 corpus hashes
      reproduced, T&C body SHA still `bae2422886453166`.
- [x] 1.6 `scripts/lib/legal-normalise.test.sh` — **20/0**, auto-globbed, `MIN_ASSERTIONS` floor.
- [x] 1.7 `legal-doc-shas-guard.test.ts` sandbox stages `scripts/lib`.
- [x] 1.8 **BLOCKER fixed.** The parity baseline pinned live corpus CONTENT, so any legal edit
      red-lined the required `test` context with `parity: canonical <doc> changed` — an
      extraction-failure message for a corpus edit, with no remediation and no bypass. Replaced
      with a synthesized fixture pair under `scripts/lib/fixtures/legal-normalise/` exercising
      every collapse rule. Non-vacuity proven in-suite: weakening `collapse()` moves the hash.
      Verified a legal-doc edit no longer reds the suite.
- [x] 1.9 The library header no longer implies the WORM consent ledger is downstream of it.
      `TC_DOCUMENT_SHA` is a **raw-file** digest; no normaliser change can move a persisted
      evidence hash. The normaliser's blast radius is exactly two comparisons.

## Phase 2 — Gate 1: scope-block placement *(respecified on REFERENT — R1)*

- [x] 2.0 Waiver ack-ledger **not built**. The original rationale ("zero false positives, so
      nothing to waive") was **refuted** by review, which found two false-fire modes. Both are
      now fixed at source rather than waived; gate 2 carries the break-glass for the case that
      genuinely needs one (a revert). Revisit if a real false positive appears.
- [x] 2.1 RED verified before the gate existed; all fixtures synthesized.
- [x] 2.2 Added-line extraction rebuilt. `git diff` is its own command with its status checked
      (**CRITICAL**: `| awk … || true` turned any git failure into a clean pass — measured with
      `chmod 000`). Hunk `+start,count` taken by FIELD POSITION (**CRITICAL**: a greedy strip to
      the last `+` corrupted `start` to 0 and collapsed `count` to 1 whenever the funcname
      context contained a `+`; the corpus has 88 such lines, two already anchors). `+++`
      honoured only in header position (a content line beginning `++ ` dropped the rest of the
      file). Indent measured in COLUMNS in awk (a tab measured as 1 column, so arm (b) was off
      for tab-indented documents).
- [x] 2.3 Classifier = locality assertion **+** referent. Delimiter excluded, so deleting a
      disclaimer cannot blind the gate.
- [x] 2.4 Vocabulary rebuilt on the plan's R2 family, discriminated by **verb**: a scope block
      claims something about the TEXT, a product statement about the software. A verb-free
      family matched 18 lines of ordinary prose; the narrow original missed six realistic
      phrasings. Unclassified locality assertions are now REPORTED, never silently dropped.
- [x] 2.5 Arm (a) scans the WHOLE enclosing section including the heading (markers below the
      block were invisible; 46 h2/h3 headings carry one), excludes the block's own line, and
      skips fenced code. Fires on a section referent regardless of any paragraph mention (eight
      words used to disarm it — already live at `privacy-policy.md:269`). The referent must be
      in SUBJECT position, or a cross-reference ("see the Section 4.3") red-lines a correctly
      narrowed block — a false positive introduced while fixing the laundering path and caught
      before commit.
- [x] 2.6 Arm (b): attachment must match referent, threshold ≥ 2 columns.
- [x] 2.7 Arm (c) requires a discharging clause (negative delimiter **OR** cross-reference), and
      says plainly that the check is line-local. 3 of 4 blocks on main carry no delimiter.
- [x] 2.8 Section resolution `max(last_h2, last_h3)`; preamble handled; fence-aware.
- [x] 2.9 Marker calibration: per-marker ≥ 1 **and** a cardinality assertion, so "simplify the
      marker list" cannot pass silently.
- [x] 2.10 Per-surface corpus floor. The original conjunction meant a half-moved mirror left the
      gate scanning zero mirror lines while printing `0 violations` — the only fail-open path in
      the corpus toolchain.
- [x] 2.11 All applicable arms reported in one run; report capped at 120 lines with a tail
      count; `::error file=,line=` annotations so findings land inline on the PR diff.
- [x] 2.12 PASS and FAIL messages name what was not checked, cite the CLO, state the resolved
      base, and carry a reproduce command. The NOT-CHECKED list now also names DELETIONS and
      marker-ADDITION, neither of which the gate can see.
- [x] 2.13 Mutation battery rebuilt on real axes (regex, field-parse, stream transform), each
      row asserting the EXPECTED ARM. **65/0**, `MIN_ASSERTIONS` floor verified to bite. One
      survivor recorded as EQUIVALENT rather than fixed.

## Phase 3 — Gate 2: mirror drift ratchet

- [x] 3.1 RED verified before the gate existed.
- [x] 3.2 Drift primitive **keeps** the `<`/`>` surface marker. Stripping it meant a PR that
      deleted a clause from the canonical record and published it only on the mirror produced a
      byte-identical sequence and passed — the inversion of the posture the gate's Art. 83(2)
      argument rests on. `---` is dropped only as diff's own hunk separator.
- [x] 3.3 Ratchet: `driftseq(HEAD) ⊆ driftseq(base)`, order preserved. Reduction always passes.
- [x] 3.4–3.6 Base resolution moved to the shared `scripts/lib/legal-base-ref.sh`, so gate 1 and
      gate 2 cannot disagree about what "added" means; fetch is conditional (it was ~98% of both
      gates' measured wall time and CI already checks out at `fetch-depth: 0`).
- [x] 3.7 Pair lifecycle unchanged; `core.quotePath=false` on both git calls; enumeration
      anchored to direct children so a subdirectory doc cannot collide onto its top-level twin.
- [x] 3.8 `EXPECTED_COUNT` parsed with the vitest guard's `\b` anchor; a parse failure warns
      instead of silently skipping the cross-check.
- [x] 3.9 Verdict DERIVED from the evidence (REORDERED / GREW / CONTENT CHANGED), each with its
      own remediation. Report survives large drift (`awk NR<=12`, not `head`, which took SIGPIPE
      and aborted the gate at rc=141 with zero output) and shows real lines, not the blanks
      `sort` floats to the top.
- [x] 3.10 Header and PASS message state **verified** omissions only: collected-data categories,
      lawful bases, the Art. 15/20 export route. The "named third-country recipient (Anthropic,
      US)" claim is **WITHDRAWN** — the mirror discloses it at `gdpr-policy.md:206`. Two more
      were narrower than stated. Corrected on #7349 too. The suite asserts it cannot return.
- [x] 3.11 Zero-line-normalisation floor (a doc with fewer than two `---` normalises to zero
      bytes, so two unrelated surfaces compared equal). Violations reported before the
      "nothing evaluated" guard.
- [x] 3.12 Break-glass `SOLEUR_LEGAL_DRIFT_ACCEPT='<reason>'`, because a revert of a merged
      drift-reducing PR was otherwise impossible past a required context.
- [x] 3.13 The 2026-09-30 date is one constant feeding the header, the PASS message and an
      expiry warning. **38/0**, `MIN_ASSERTIONS` floor, real-axis mutations.

## Phase 4 — Gate 3: obligation-checklist — **DEFERRED to #7392 (D-A)**

Not built here. Design preserved in the plan and carried in full on #7392, which builds it
against #7349 so it lands with a live consumer and a real input.

## Phase 5 — Registration

- [x] 5.1 Four `run_suite` lines: unit + live for each gate.
- [x] 5.2 Both **live** gate scripts in `REQUIRED_RUNNERS`.
- [x] 5.3 **No `.github/workflows/ci.yml` edit** (R11) — verified end-to-end at review:
      `test-scripts` runs `test-all.sh scripts` at `fetch-depth: 0` into the required `test`
      context.
- [x] 5.4 `lint-orphan-test-suites.sh` → exit 0.
- [x] 5.5 Mutation-proven, all four: dropping any of the four lines makes the orphan lint
      exit 1, re-verified after the check-tc line was removed.
- [x] 5.6 The `check-tc-document-sha` live line was added and then **REMOVED**. It reintroduced
      #5780 (its `TC_VERSION` bypass needs step-scoped env `test-scripts` does not carry, so a
      legitimate version-bump PR would go green on one required context and red on the other),
      and its stated rationale was measured false — weakening `collapse()` leaves that script
      green because it detects only asymmetric damage. The fixture engine pin is the detector.

## Phase 6 — Exit gate

- [x] 6.1 `bash scripts/test-all.sh scripts` → rc=0, `=== 273/273 suites passed ===` (pre-review
      tree). Re-run post-review before ship.
- [x] 6.2 Legal-related webplat suites green: 5 files / 39 tests. `tsc --noEmit` clean.
- [x] 6.3 Every AC checked individually against real output; never bulk-toggled.
- [ ] 6.4 PR body: attribution for SHIPPED scope (**2 of 10** — P1-4, P1-5, both via gate 1; the
      4-of-10 figure counts gate 3's two, deferred to #7392), the gate-3 deferral, the review
      findings, and the #7372 interaction re-derived per R5.
- [ ] 6.5 `decision-challenges.md` rendered into the PR body — all three decisions are
      **decided**, so they are reported as applied decisions rather than filed as
      `action-required`.
- [ ] 6.6 Discoverability: an `AGENTS.rules.md` gate keyed on `docs/legal/**`, and the three
      gates named in `plugins/soleur/skills/legal-generate/SKILL.md` — which writes canonical
      only and declares the mirror out of scope, so it trips gate 2's unpaired branch by design.
