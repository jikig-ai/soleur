# Tasks — feat-one-shot-6578-sibling-guard-reachability

Derived from `knowledge-base/project/plans/2026-07-17-fix-sibling-guard-pipefail-reachability-measurement-plan.md` (v2, post 6-agent review + advisor consult).
Closes #6578.

**lane:** cross-domain (no spec.md — TR2 fail-closed default)

---

## Phase 0 — Preconditions (verify; do not assume)

- [ ] 0.1 Confirm #6578 is OPEN (`gh issue view 6578 --json state`); confirm `2b381815f` on `main`.
- [ ] 0.2 **Pin the grep implementation.** Record `command -v grep`, `type grep`,
      `/bin/grep --version`. The probe must **assert GNU grep and exit non-zero otherwise** — a
      ugrep/BusyBox host reads 0/N everywhere and yields a false all-clear. This is the highest-value
      precondition in the plan; do not downgrade it to a warning.
- [ ] 0.3 Read `apps/web-platform/infra/supabase-advisor/scan-workflow-mutation.test.sh` in full.
      It owns the sandbox (`cp "$GUARD" "$PRISTINE"` into `mktemp -d`, `:59/:139/:244`), the
      landing-verified `mutate()` (`:180-201`), and `count_false_negatives piped` (`:89-99`).
      Lift; do not re-author.
- [ ] 0.4 Read `scan-workflow.test.sh:138-142` as a **block** — two seds (`:138` folds
      continuations, `:141` folds multi-line pipes). Reproduce the order: fold continuations →
      strip comments → strip strings → fold pipe-newlines → match.
- [ ] 0.5 `shellcheck --version` — one-time author check only; shellcheck is enforced nowhere in
      this repo. Do not add a CI step claiming otherwise.
- [ ] 0.6 Note the CI budget: `deploy-script-tests` is `timeout-minutes: 8` with ~12s slack.
      Measure the probe's runtime; if >~10s, register as its own job, not a step.
- [ ] 0.7 C4 completeness check — read all three of
      `knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}`; confirm no
      external actor / external system / container / access-relationship changes. Record the
      enumeration; do not expand scope on a pre-existing gap.

## Phase 1 — The decidable splits (static, cheap)

- [ ] 1.1 Create `apps/web-platform/infra/scripts/sigpipe-triage-feasibility.sh`.
      Contract: `[--pathspec <git-pathspec>]`, default `apps/web-platform/infra/`. Asserts GNU grep
      (0.2) and exits non-zero otherwise. FATALs on an empty enumeration.
- [ ] 1.2 Normalisation: strip comments, double-quoted strings, **and heredocs**, plus the two folds
      from 0.4. Heredoc bodies survive all other normalisations and are tracked text `git grep`
      enumerates — the probe lives inside its own default pathspec
      (`infra/scripts/gen-github-egress-cidr.test.sh:62` carries a live instance, so the directory
      cannot be excluded wholesale). #6573 hit the self-match trap twice; do not open a third door.
- [ ] 1.3 Emit, each **beside the command that produced it** (a number without its command is not
      emitted): corpus size; PF (`pipefail`) split; `set -e` split → `symptom` mix
      (`inverts` | `aborts`); producer-kind mix; **production vs `*.test.sh` partition**.
- [ ] 1.4 Pin `LC_ALL=C` on every `sort`/`comm`/`uniq`.
- [ ] 1.5 Name the predicate conditions **PF / RC / WIN** — `R1`/`R2`/`N1` are already taken by
      `scan-workflow-mutation.test.sh:27-31` with different meanings.

## Phase 2 — The number that decides the arm

- [ ] 2.1 For each **production** var-fed site, resolve the var's assignment: literal/fixed-width →
      bounded; command-substitution of an unbounded producer → unbounded; unresolvable → undecided.
- [ ] 2.2 Emit **B** = bounded / var-fed (production denominator).
      **A site counts as bounded only when its *assignment* resolves to a bound.** "Feeds a var ⇒
      bounded" is the inference that produced the 194 figure — it is the antecedent under test.
- [ ] 2.3 Do **not** emit a per-site REACHABLE/INCAPABLE class. That ledger is majority-UNDECIDED
      by construction (see plan Alternatives).

## Phase 3 — Findings note + disposition

- [ ] 3.1 Write `knowledge-base/engineering/audits/2026-07-17-sigpipe-guard-triage-feasibility.md`:
      numbers + their commands, the grep-implementation caveat, `B`, the verdict.
- [ ] 3.2 **Counts, classes, and commands only — no ranked per-site index of live-vacuous
      security rungs.** The repo is PUBLIC; such an index is a targeting artifact for the seams it
      declines to close. Site detail for security rungs → tracking issue only.
- [ ] 3.3 Apply the disposition rule over the **production denominator** (46/11 measured today):
      convert iff `P ≤ 50 across ≤12 files`; else track. Test-harness subset (238): always track,
      never convert here.
- [ ] 3.4 **Security-rung auto-forfeit:** if the convert arm would touch an RLS / auth / exfil-seam /
      credential-pinning rung, do NOT convert — forfeit to the track arm and file an
      `action-required` issue with the site detail. Keeps `/work` headless (ADR-084: persist, never
      pause); v1's "CPO sign-off before /work" demanded time travel.
- [ ] 3.5 Tracking issue(s): close-condition must be **mechanical and satisfiable** —
      `sigpipe-triage-feasibility.sh` reports 0 early-exit-pipe sites over pathspec X. **Run it at
      file time to confirm it can fail today.**

## Phase 4 — Conversion (production arm only, if it fires)

- [ ] 4.1 Transform is `-q<flags>` → `-<flags>` + `>/dev/null`, **or** capture-once + here-string per
      the operator's #6573 direction. NOT a naive `sed` appending `-F` (yields `-qE`→`-EF`,
      conflicting flags).
- [ ] 4.2 Rule out unbounded producers before dropping `-q` — without `-q`, grep reads to EOF; on an
      unbounded producer that hangs.
- [ ] 4.3 Any converted match⇒fail assertion over a capture ships **both** the non-empty guard
      (diagnostic) **and** a paired non-vacuity rung (the part that actually fails loudly) — FR4.

## Phase 5 — FR4 pinning rung (independent of the arm)

- [ ] 5.1 Add **E1/E2 to `scan-workflow-mutation.test.sh`** — not a new harness. It already owns the
      sandbox; a second one would violate the plan's own "do not invent a second fold".
- [ ] 5.2 E1: empty capture at the `.lints[]?` match⇒fail site exits non-zero.
- [ ] 5.3 E2 (vacuity of E1): with `:291`'s pairing rung mutated out of the **sandbox copy**, the
      same empty capture passes — proving E1 pins the pairing, not something incidental.
- [ ] 5.4 Verify `scan-workflow.test.sh` passes **unchanged** (sandbox copy only → AC7 +
      `cq-test-fixtures-synthesized-only` both hold).

## Phase 6 — Wire it

- [ ] 6.1 Register the probe in `.github/workflows/infra-validation.yml` (nothing auto-discovers).
- [ ] 6.2 Registration asserted by **`scan-workflow.test.sh`** — a **cross-file** assertion,
      mirroring how `:95` asserts the mutation harness. A self-assertion is vacuous: an unregistered
      script never runs.
- [ ] 6.3 State `deploy-script-tests` as **advisory** (confirmed against the live ruleset) — do not
      claim a blocking gate.

## Phase 7 — Acceptance + close

- [ ] 7.1 AC1: probe exits 0 on a GNU-grep host and **non-zero** under a ugrep/BusyBox shim on
      `PATH`. The negative arm is the load-bearing one.
- [ ] 7.2 AC2: re-run every command in the note; outputs match.
- [ ] 7.3 AC5: no prior unmeasured figure restated in the **output artifacts** (note, probe, issue,
      PR body) — the plan is excluded; it must name the figures it retracts.
- [ ] 7.4 AC6/AC7: mutation harness passes with E1/E2; `scan-workflow.test.sh` unchanged and green.
- [ ] 7.5 AC11: `decision-challenges.md` records UC-1, UC-2, UC-3.
- [ ] 7.6 Post-merge (automated by `/ship`, not the operator): `gh issue close 6578` citing the
      findings note.
</content>
