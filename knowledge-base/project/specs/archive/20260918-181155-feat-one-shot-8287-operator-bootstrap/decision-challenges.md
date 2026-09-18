# Decision Challenges — feat-one-shot-8287-operator-bootstrap

Recorded per ADR-084 / `decision-principles.md`. Each entry is a point where the session's
judgement and a domain leader agreed that the operator's **stated direction** in issue #8287
should change. Nothing here was applied silently: the run is headless, so each is persisted for
`ship` Phase 6 to render into the PR body and file as one `action-required` issue.

The operator's stated direction remains the default. Each entry names the one-line reversal.

---

## DC-1 — Skill renamed `operator-explain` → `operator-rephrase`

**Operator's stated direction.** The "Naming + integration contract" table in #8287 names the
replacement skill `operator-explain`.

**What changed and why.** The contract itself delegates this: *"If the implementing plan finds a
better name inside the shipped convention, take it."* The CPO assessment argued that the shipped
`operator-*` family is `<audience>-<artifact>` (`operator-digest`'s second token names the
artifact), that `explain` under-describes the trigger — the founder did not fail to receive an
explanation, the message did not land — and that "explain" invites a lecture where "rephrase"
invites the same content in a different register. Both names satisfy the `<noun|domain>-<verb>`
convention the contract mandates, so this is a semantic improvement inside the authorised space,
not a departure from it. `operator-bootstrap` is unchanged.

**Cost of reversal.** One directory rename plus three citations (help.md, operator-digest's
back-reference, the NOTICE entry). Under five minutes.

---

## DC-2 — ASD-STE100 narrowed from a conformance claim to an influence citation

**Operator's stated direction.** #8287 G5 specifies the skill re-pitches "in ASD-STE100 Simplified
Technical English".

**What changed and why.** `grep -rn "ASD-STE100\|Simplified Technical English\|controlled English"
plugins/ knowledge-base/` returns zero. There is no controlled vocabulary in the repo to bind the
standard to, and no gate that could check conformance, so a seven-line skill *claiming* conformance
to a controlled-language standard asserts something nothing can verify. The CPO assessment
recommended dropping the reference entirely; this plan takes the middle position instead — the
skill names ASD-STE100 as its influence and states the parts that are checkable (short sentences,
one idea per sentence, active voice, no jargon, no file paths, no issue numbers).

**Cost of reversal.** One sentence in `operator-rephrase/SKILL.md`. Note that restoring a bare
conformance claim restores the unverifiable assertion.

---

## DC-3 — The four-script refactor reduced to one proving consumer

**Operator's stated direction.** #8287 measures the Fix-Size as including a "refactor of 4 provision
scripts totalling 1041L", and the G1 scope says to refactor all four onto the shared library.

**What changed and why.** Two domain assessments independently recommended splitting this issue
into multiple PRs, and both named the same piece as the risk. Measured facts behind that:

- The four scripts have **zero** dedicated tests today.
- The DPA gate runs *before* the `--dry-run` branch in all four, and the live tenant register is
  empty, so every script exits 3 on any slug — a characterization harness needs a fixture register
  before any baseline can be captured at all.
- `provision-github.sh --dry-run` is **not** offline: four network calls execute before the dry-run
  branch, so the largest script currently has no capturable baseline.
- `scripts/lint-shell-trace-credential-refusal.py`'s scope predicate is name-shaped, so a careless
  rename during extraction drops `provision-doppler.sh` out of scope and turns the linter green over
  a file that just lost its MITM protection.

This plan therefore keeps characterization tests for **all four** (the safety net, and independently
valuable given zero coverage today), refactors **`provision-hetzner.sh` only** as the proving
consumer that keeps the library from shipping inert, and files one issue for the remaining three in
ascending order of blast radius with the full sequencing note.

**Cost of reversal.** Re-scoping the deferred issue back into this PR. The characterization suites
land either way, so the reversal cost is the refactor work itself, not rework.

---

## DC-4 — The generated script SOURCES the library; the inlined "immutable region above `STAGES`" is cut

**Operator's stated direction.** #8287 G1 says the peer architecture "is the point": an immutable
library above a `STAGES` marker, with the skill authoring only the stages below it, and "never
hand-edit the library" as the invariant that makes every wizard consistent.

**What changed and why.** The plan as drafted specified **both** modes at once and they are mutually
exclusive. A sourced library's first line is `# shellcheck shell=bash` with no shebang; an inlined
one must open with a shebang, `set -euo pipefail`, and the xtrace prologue above any command. The two
regions differ in their first five lines by construction, so no byte-identity guard can hold over
both. Four reviewers reached the contradiction independently, and the plan's own observability block
contained the tell: its `SOLEUR_BOOTSTRAP_LIB_MISSING` failure mode is unreachable for an inlined
library and meaningful only for a sourced one.

Sourced was chosen because the consistency invariant survives it — the library is still one file, the
skill still authors only stages, and "never hand-edit it" still holds — while the drift class the
marker existed to police disappears entirely rather than being policed by a guard whose population is
gitignored and therefore invisible to CI. It also removes three mutually contradictory rules from the
contract a future wizard author must obey.

**Cost of reversal.** Substantial, and it brings back a guard that cannot see what it guards: the
generated artifact lives in a gitignored directory, so no CI check can observe drift in it. If the
inlined shape is wanted for portability (handing a script to someone without the plugin), that is a
different requirement than the one the issue states, and it should be scoped as one.

## DC-5 — `## Merge Danger` ships with two fields, not three; `Door:` is cut and the merge hold is deferred

**Operator's stated direction.** #8287 B9 specifies `**Door:** one-way | two-way` plus
`**Blast Radius:** <one word>`.

**What changed and why.** `Door` is a derived field — the plan's own reasoning is that it cannot be
written without `Undo`, which is the definition of derivation — and it maps onto neither clause of
the property it was meant to buy. Cutting it dissolved two separate P0 findings instead of requiring
them to be fixed: the agent that produces the undo line runs only on PRs touching production data or
migrations, so on a plugin-only PR (including this one) it never runs, which left `Door` either
unconstrained — reopening the exact ADR-119 defect the field was added to close — or forced to
`one-way` on every docs-only PR.

The **hold** is deferred for a separate reason: as specified it had no interactive, cloud or headless
arm and no override token, against a cited precedent that defines all three; it was placed one phase
before the field it reads is written; and its key is a free-choice string with no derivation or test,
which is the shape the ship skill deliberately rejected when it moved review coverage into a
script-emitted git trailer. In a repo whose premise is that verified work ships without asking, that
is a wedge. The deferred issue carries an activation criterion — a measured firing rate plus the three
arms and an override — rather than a promise to revisit.

**Cost of reversal.** Restoring `Door:` re-opens the unanswerable-default problem unless the undo
source is widened first. Restoring the hold requires specifying its three arms and an override token.

## Applied without challenge

For completeness, these deviations from the issue text are **not** challenges — the issue body or an
existing rule authorised them, and they are listed so the operator sees the full delta:

- No `/go` routing row for either skill. The contract explicitly permits a not-routable disposition
  with a named invoker, and the measured cost of a row is a widened enum, two reddened pinned
  literals, a golden task, a regenerated projection and ≈144 API calls.
- The capability map extends `help.md` rather than adding a second map to `go.md`; the
  phase-boundary tree lands as an AGENTS rule. Both follow from the measured finding that `help.md`
  already maps agents and only dumps skills flat.
- `Door:` became a three-field undo-first block rather than a one-word verdict, because ADR-119
  records a one-way-door label that was wrong and says stating it that way *"will make an operator
  refuse a rollback they should take."*
