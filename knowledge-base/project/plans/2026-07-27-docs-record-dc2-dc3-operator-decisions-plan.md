---
title: "Record the DC-2 and DC-3 operator decisions and close #7003"
type: docs
date: 2026-07-27
issue: 7003
related_issues: [6977, 6982, 6989]
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# 📚 docs: record the DC-2 and DC-3 operator decisions, propagate the DC-2 mandate into ADR-149, close #7003

> Spec lacks a valid `lane:` (no `spec.md` exists for this branch) — defaulted to `cross-domain`
> (TR2 fail-closed).

## Enhancement Summary

**Deepened:** 2026-07-27 · **Reviewers:** kieran-rails-reviewer, code-simplicity-reviewer,
architecture-strategist, spec-flow-analyzer.

Four findings changed the plan's shape. All were verified against live state before applying; none
touches a word of either operator decision.

1. **ADR-149 states its checklist size in *three* places, not one** (its own prose uses an **en
   dash**, the gate uses ASCII). Adding an item without touching the others ships the exact drift
   this change exists to prevent. Fixed by making all three **universally quantified** — "every
   other item" — which cannot go stale at item 9 either. **R1.**
2. **The new mandate is a dispatch *precondition*, so it cannot sit after "clear the
   DO-NOT-DISPATCH banner."** The runbook says the banner clears only when every item is done, so
   appending after item 7 makes the list unexecutable in order. The mandate becomes **item 7**;
   banner-clearing moves to **item 8**, where it is genuinely terminal. **R2.**
3. **#7003's body still says "still open" twice and poses the exact question DC-2 answers**, and
   **#6982's body is a 7-checkbox list that never names ADR-149.** Commenting alone leaves both
   artifacts internally false. Both bodies get edited — #7003 following the DC-1 precedent already
   in its own body. **Phase 4.**
4. **Phase 4's GitHub effects are irreversible and were sequenced before the merge.** An abandoned
   PR would leave #7003 closed with nothing recorded on `main`, and R5 shows automation cannot
   recover it. Phase 4 now runs **post-merge**, and the PR body uses `Ref #7003`, not `Closes`.

---

## Overview

The operator made two calls on 2026-07-27 on the decision challenges surfaced by PR #6989
(issue **#7003**, labelled `action-required` + `decision-challenge`). Both are still recorded as
open. This change records them faithfully, propagates the one mandate a downstream issue must
inherit, and closes the escalation.

This is a **recording** task, not a design task. Both decisions are the operator's and are
**final**. Nothing here re-opens, re-weighs, or softens either one.

| | Decision | The thing that must not get lost |
|---|---|---|
| **DC-2** | Replace the sentinel with a **direct emitter check** when #6982 lands. | The falsification recorded under DC-2 does **not** apply to this decision. Accepted cost: #6982 inherits a *mandated* interlock rewrite. |
| **DC-3** | The cut stands. `doppler_secret.git_data_ssh_host` lands in **#6982**. | It MUST single-source from `hcloud_server_network.git_data.ip`, and the `OPERATOR_APPLIED_EXCLUSIONS` entry MUST land in the same change. |

**Scope shape:** three file edits + five GitHub API calls. No product code, no infra resources, no
schema, no runtime behaviour. The only executable file touched is a shell gate, and only its
**comment block and its human-readable messages** — no branch, no regex, no exit code.

---

## Premise Validation (Phase 0.6)

Every reference the brief cites was probed against live state. All held; the ones that changed the
plan are listed first.

| Premise | Probe | Result |
|---|---|---|
| ADR-149's checklist is a **7-item numbered list** | Read the ADR | **HOLDS** — and the ADR restates the size again in prose at anchor `Items 2–7 are not machine-checked at all` (**en dash**, U+2013), which the gate's ASCII `2-7` form does not match. Third mirror. |
| Item 7 is `Clear the DO-NOT-DISPATCH banner in git-data-birth.md.` | Read the ADR + runbook | **HOLDS**, and the runbook banner says *"Clear this banner only when every item is done"* — so an item appended after 7 is unexecutable in list order. |
| #7003's body describes DC-2/DC-3 as unresolved | `gh issue view 7003 --json body` | **HOLDS** — `## DC-2 — recorded judgement call, still open`, `## DC-3 — … still open`, and `**Open question for the operator:** whether the sentinel remains the right mechanism … or whether a direct check of the emitter resource replaces it.` DC-1's heading was already edited in place to `## DC-1 — RESOLVED by the operator on 2026-07-27` — the precedent for the fix is inside the same body. |
| #6982 is the right inheritor | `gh issue view 6982 --json body,state` | **HOLDS** — OPEN, *"git-data: pre-birth hardening + observability (blocks the first birth)"*. Its body is a 7-checkbox `## Items` list plus a `## Re-eval trigger`, and it **never names ADR-149**. |
| DC-1's RESOLVED heading form | Read `decision-challenges.md` | **HOLDS** — `### RESOLVED 2026-07-27 by the operator — ship the route now, interlocked`. A second, different precedent exists at `specs/feat-one-shot-6425-…`; the brief mandates DC-1's. |
| The emitter has **no** Terraform resource today | The gate suite's non-asserting live-file probe | **HOLDS** — reports `HOLD`. Nothing exists for a resource assertion to bind to, which is why DC-2 is future-dated. |
| `hcloud_server_network.git_data.ip` is referenceable | Read `apps/web-platform/infra/network.tf` | **HOLDS** — `resource "hcloud_server_network" "git_data" { … ip = "10.0.1.20" }`. |
| `heartbeat-manifest.ts` declares git-data's feeder `kind: "timer"` | `grep -n git-data plugins/soleur/lib/heartbeat-manifest.ts` | **HOLDS** — `name: "git_data_prd"`, `feeder: { kind: "timer", … }`. The falsified proposal really would release immediately. |
| `doppler_secret.git_data_ssh_host` is absent | `grep -rn git_data_ssh_host apps/web-platform/infra/` | **HOLDS** — zero hits in `infra/`; only consumer-side references in `apps/web-platform/server/git-data-replication.ts`. |
| `OPERATOR_APPLIED_EXCLUSIONS` is where the exclusion lands | `grep -n OPERATOR_APPLIED_EXCLUSIONS plugins/soleur/test/terraform-target-parity.test.ts` | **HOLDS**, and the file **already names DC-3**: the `doppler_config.git_data_prd` comment says *"killed the `doppler_secret.git_data_ssh_host` proposal (DC-3)"*. |
| The gate suite is green, anchors outside the edited regions | `bash tests/scripts/test-git-data-birth-readiness-gate.sh` | **HOLDS** — `21 passed, 0 failed`; mutations anchor on `strip_comments=`, `sentinel_re=`, `if [[ "$hits" -eq 0 ]]`, `if [[ ! -f "$cloud_init" ]]`, none in the header block, the HOLD heredoc, or the RELEASED `echo`. |
| No PAT-shaped variable; no UI surface; no new store | Phase 4.8 / 4.9 / 4.10 greps | **PASS** — all three deepen-plan halts skip. |

**Out-of-scope observation, recorded so the next reader knows it was seen:** #6977 is still `OPEN`
despite PR #6989 having merged. It is the `Ref` target of #7003 and the stated dependency of #6982.
Not touched here — closing it is a separate judgement about whether #6977's own ACs are met.

### Network-Outage Deep-Dive determination (Phase 4.5)

The trigger substrings (`ssh`, `unreachable`, `timeout`) appear in this plan **only** inside a
resource identifier (`doppler_secret.git_data_ssh_host`) and inside quoted rationale about a
**pre-existing** condition. The plan proposes no SSH operation, no firewall or allowlist change, no
DNS/routing change, and no diagnosis of a connectivity symptom. L3 firewall, L3 DNS/routing, L7
TLS/proxy and L7 application therefore have nothing to verify — the checklist is not applicable
rather than unverified. Recorded per `hr-ssh-diagnosis-verify-firewall` so the skip is auditable.

---

## Research Reconciliation — brief vs. codebase

| Claim | Reality on disk | Plan response |
|---|---|---|
| DC-3's rationale: *"unreachable today, because `doppler_secret.git_remove_ssh_private_key` is absent from state."* | **True today.** ADR-149 `Residual 2` corrects that claim's **scope**: *"'Unreachable today' was true; 'unreachable once this route is used' was not"* — the false alarm becomes **unconditional after any birth**, which is why item 5 requires `GIT_DATA_SSH_HOST` before the first dispatch. `Residual 2` names *"the DC-3 disposition"* as the reasoning that hid it. | Record the operator's sentence **verbatim**, add an in-line scope marker so the bolded "accepted" is not read unqualified, and follow it with a blockquote cross-referencing `Residual 2`. Add the **reciprocal** pointer in the ADR (Phase 2.3) — otherwise the cross-reference only points inward. **R3.** |
| Brief: *"a 25th copy of the `10.0.1.20` literal"* | The literal appears **30×** across `apps/ tests/ plugins/ scripts/ .github/`; 68× repo-wide. | Record the operator's phrase as written — rhetorical, not a count assertion. Introduce **no** count into any artifact; assert only the mechanical constraint. |
| Brief: propagate DC-2 into *"the ADR-149 release checklist"* | The size is mirrored **three** times, with two different dash characters, and none is compared to the list by any test. | Add the item **and** make all three sites universally quantified. **Phase 2(d), Phase 3, R1.** |
| #6415 is the precedent for single-sourcing | **Partially.** `network.tf` routes `hcloud_server_network.registry` through `ip = local.registry_private_ip`, and `zot-registry.tf` defines `registry_private_ip = "10.0.1.30"` — so #6415 removed a *duplicate* literal but the literal still lives in a `local`. It does **not** demonstrate reading the resource attribute, which is what DC-3 mandates. | Cite #6415 **accurately** in ADR item 5 as the nearest precedent for refusing a duplicated literal, and state that DC-3 goes one step further. Keep it out of the RESOLVED block, so that block carries only the operator's words. |
| ADR-149 item 3 says to register a new address in *"all three"* of the `-target` set, the gate's `def allow:`, and `GIT_DATA_BIRTH_TARGET_BASES` | There is a **fourth** registry — `OPERATOR_APPLIED_EXCLUSIONS` — which already holds `hcloud_server.git_data`, `hcloud_server_network.git_data`, and both git-transport secrets, and which the runbook's references line calls the home of *"every git-data address."* The two are branches of one routing rule (per-PR target set **xor** operator exclusion list), not four parallel slots, so item 3 is not wrong — but an implementer following it for `doppler_secret.git_data_ssh_host` would reproduce the wedge DC-3 exists to prevent. | **Do not amend item 3** — that is a distinct question the operator did not decide. State the either/or routing rule in the #6982 comment alongside DC-3's constraint, where it is exactly the guidance the implementer needs. Recorded here so the finding is not lost. |
| Editing `decision-challenges.md` after `ship` ran will be clobbered | **False.** `ship` full-replaces the **PR body**, not the artifact; its Phase 2.5 reads `specs/<current-branch>/decision-challenges.md`. This branch is `feat-one-shot-7003-…`; the edited file is under `specs/feat-one-shot-6977-…`. | Proceed. **But** do not create a `decision-challenges.md` under *this* branch's spec dir. **R4.** |
| Also checked, nothing to do | No test/lint/workflow reads `decision-challenges.md` **content**; `adr-frontmatter-ordinal-guard.test.ts` checks frontmatter only and ADR-149 has none (it uses a bullet header); `scripts/lint-infra-no-human-steps.py` **does** scan the ADR + specs + plans dirs (AC11); the runbook banner defers to ADR-149 rather than restating it, so it stays true; and item 3's parity is genuinely machine-checked by `terraform-target-parity.test.ts` — the gate's `NOT machine-checked **here**` is scoped and accurate. Do not "fix" it. | — |

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — no runtime surface changes. The
realistic failure is downstream and delayed: if the DC-2 mandate reaches neither ADR-149's checklist
nor #6982's own item list, #6982 ships the emitter and leaves in place a text-grep interlock that
three reviewers already called unsound — re-introducing the *"a green apply and a dark host are
indistinguishable"* exposure ADR-149 exists to close, on the host that will hold every connected
user's source code. The second failure is **R5**: an escalation channel discharged with nothing
recorded, which no automation can re-surface.

**If this leaks, the user's data / workflow / money is exposed via:** nothing. No secret,
credential, or PII is introduced. The `10.0.1.20` private-network address already appears 30× in the
tracked tree; DC-3's whole constraint is to *stop* copying it.

**Brand-survival threshold:** `none`. *Reason:* the change writes markdown and shell comments and
calls five GitHub endpoints; it touches no sensitive path (no schema, migration, auth flow, API
route, or `.sql`), has no execution path a user can reach, and no data-handling surface. Its only
failure modes are documentation drift and a partially-applied GitHub state, caught by AC1–AC12.

---

## Files to Edit

| File | Change |
|---|---|
| `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md` | **(a)** add a status line under the header (which currently says *"These are NOT applied … require an operator decision"* — false once three are resolved); **(b)** add a `(see RESOLVED below)` pointer after DC-2's falsification claim; **(c)** append the DC-2 RESOLVED block; **(d)** append the DC-3 RESOLVED block. |
| `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md` | **(a)** insert the DC-2 mandate as **item 7**, renumbering banner-clearing to **item 8**; **(b)** extend **item 5** with DC-3's two constraints; **(c)** update the existing `Include doppler_secret.git_data_ssh_host` Alternatives row (dissent → upheld) and add the artifact path + `#6989`; **(d)** make the prose at anchor `Items 2–7 are not machine-checked at all` universally quantified; **(e)** mark the sentinel **interim** in `### The birth-readiness interlock`, which still calls the choice load-bearing with no expiry; **(f)** add `#7003` provenance to the header bullets. |
| `tests/scripts/lib/git-data-birth-readiness-gate.sh` | **Comments and message text only.** Header `RELEASE CONDITION` list gains the new condition and `It cannot check (2)-(7)` becomes count-free; the **HOLD** message gains a 5th item; the **RELEASED** message becomes universally quantified. |

## Files to Create

| File | Purpose |
|---|---|
| `knowledge-base/project/plans/2026-07-27-docs-record-dc2-dc3-operator-decisions-plan.md` | This plan (untracked until committed). |
| `knowledge-base/project/specs/feat-one-shot-7003-dc2-dc3-operator-decisions/tasks.md` | Task breakdown. |
| `knowledge-base/project/specs/feat-one-shot-7003-dc2-dc3-operator-decisions/session-state.md` | Written by `/work` alongside `tasks.md`; named so AC12 does not false-fail. |
| *(transient, not committed)* four bodies under the session scratchpad — two issue comments, two issue bodies — passed to `--body-file`. | Multi-paragraph bodies with backticks and `${…}` are hostile to inline `--body`. Write in one Bash call, invoke `gh` in the **next**. |

**Explicitly NOT created:** `…/specs/feat-one-shot-7003-dc2-dc3-operator-decisions/decision-challenges.md`. See **R4**.

**Explicitly NOT edited:** `knowledge-base/engineering/operations/runbooks/git-data-birth.md` — its
banner defers to ADR-149's list rather than restating it, and the item renumbering keeps
banner-clearing terminal, so it stays true. Checked; recorded so the next reader knows it was
checked rather than missed.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200 --json number,title,body`
filtered with a standalone `jq --arg` for each of `decision-challenges.md`, `ADR-149`, and
`git-data-birth-readiness-gate.sh` returned zero matches.

---

## Implementation Phases

### Phase 1 — Record both decisions in `decision-challenges.md`

Mirror DC-1's shape exactly: `### RESOLVED 2026-07-27 by the operator — <verdict>`, a bolded
`**Decision: …**` lead, the rationale, then the accepted cost stated plainly. Do **not** use the
`### RESOLVED — <date>:` form from the `feat-one-shot-6425-…` spec.

**1.1 — Header status line.** The file's header asserts *"**These are NOT applied** — they challenge
the operator's stated direction and require an operator decision."* That is the cold reader's first
sentence and it is false once all three carry RESOLVED blocks. Append immediately after it:

```markdown
**Status (2026-07-27): all three resolved by the operator.** DC-1 and DC-2 in favour of the plan's
disposition, DC-3 upholding the cut. The two mandates that outlive this PR are recorded as items 5
and 7 of ADR-149's release checklist, which #6982 inherits. Issue #7003 is closed.
```

**1.2 — Scope the falsification claim.** DC-2's `**That recommendation is falsified by
measurement.**` reads as a verdict on the *idea*; what was falsified is one implementation of it,
and the RESOLVED block that says so is ~15 lines further down. Append `(scope: that implementation
only — see RESOLVED below)` to that sentence. This adds no claim and removes the misread the whole
DC-2 block turns on.

**1.3 — DC-2 RESOLVED block.** Insert after DC-2's `**Plan's current disposition:**` paragraph and
**before** the `---` separating DC-2 from DC-3 (that separator exists; verified).

```markdown
### RESOLVED 2026-07-27 by the operator — replace the sentinel with a direct emitter check when #6982 lands

**Decision: the `${sentry_dsn}` sentinel is an interim mechanism with a fixed expiry.** It stays
exactly as shipped for as long as the emitter does not exist. Once #6982 defines the git-data
emitter as a **real Terraform resource**, the birth-readiness interlock must assert **that
resource**, and the cloud-init text sentinel must be **deleted** rather than kept alongside it.

**Why this rather than any of the five reviewer positions.** It answers `dhh-rails-reviewer`'s
*"prose with a `grep` wrapper"* and `architecture-strategist`'s structural objection **at the
root** instead of wrapping them. Both complaints reduce to the same thing: the interlock reads
TEXT in order to infer a FACT. A resource assertion reads the fact. The only reason that cannot
be done today is timing, not taste — the resource does not exist until #6982 creates it.

**The falsification recorded above does NOT apply to this decision, and that distinction is the
whole decision.** What measurement killed was the proposal to read
`plugins/soleur/lib/heartbeat-manifest.ts`: that file already declares git-data's feeder as
`kind: "timer"`, so a sentinel reading it would release the interlock **immediately**. It says
nothing about reading the **emitter's own resource**, which does not exist until #6982 creates
it and therefore cannot release anything early. One is a declaration that is already true; the
other is a resource whose creation *is* the release condition.

**Accepted cost: #6982 inherits a mandated interlock rewrite** — not an optional cleanup. It is a
**precondition of the first dispatch**, not a post-release cleanup, because it changes the gate
that guards the dispatch: recorded as **item 7 of ADR-149's release checklist**, ahead of the
banner-clearing item, and mirrored into the gate's own HOLD and RELEASED messages so it is carried
mechanically rather than by memory.
```

**1.4 — DC-3 RESOLVED block.** Append at end of file (DC-3 is last; no trailing `---`). This block
carries **only the operator's own rationale** plus one scope marker and one cross-reference — the
#6415 precedent belongs in ADR item 5, where it can be stated with the precision it needs.

```markdown
### RESOLVED 2026-07-27 by the operator — the cut stands; it lands in #6982

**Decision: retain the cut.** `doppler_secret.git_data_ssh_host` stays out of #6977 and lands in
**#6982**, where the emitter work already touches `git-data.tf` and the
`OPERATOR_APPLIED_EXCLUSIONS` entry can land in the **same change**. When it lands it **MUST**
single-source the address from `hcloud_server_network.git_data.ip` — never a fresh copy of the
`10.0.1.20` literal.

**The residual false-"Art. 17 erasure failed" alarm window is accepted** — for the pre-birth
window, which is the window this decision governs — because it is unreachable today:
`doppler_secret.git_remove_ssh_private_key` is itself absent from state, so the arming switch is
unarmed.

> **Scope, and why it matters.** ADR-149 `Residual 2` records the correction that the false alarm
> becomes **unconditional after any birth** — it names *"the DC-3 disposition"* as the reasoning
> that hid this. That is why release-checklist **item 5** requires `GIT_DATA_SSH_HOST` to be
> produced **before the first dispatch**. The two documents agree on the action: produce it in
> #6982, before any birth. "Accepted" above scopes the *pre-birth* window only; it is not an
> acceptance of the post-birth state, which item 5 makes a precondition.

**Why not add it now anyway.** Adding the resource today would still drag `hcloud_server.git_data`
into the per-merge plan via **transitive upstream closure** and **wedge every merge to `main`** —
the ADR-145 web-2 wedge, reproduced for git-data from a one-line edit. A capability that cannot
be merged is not a capability.

**`spec-flow-analyzer`'s 30-second-hang finding is noted but not decisive.** It was one of the
reasons the cut was defensible; it is not a reason the cut is *permanent*. That hang occurs only
*while the host is unreachable* — and #6982's birth is precisely what ends that condition. It is
an argument about the ordering of two things that now ship together, not about whether to ship
them.
```

### Phase 2 — Propagate into ADR-149

**Verify before editing** (the brief mandates this): re-read
`### Interlock release checklist — #6982 inherits this` and confirm it is still a 7-item numbered
list of prose sentences with bolded lead phrases, several carrying inline back-references
(`— see *Alternatives*`). **Mirror that shape** — no table, no checkboxes, no new heading level.

**2.1 — Insert the mandate as item 7; renumber banner-clearing to item 8.**

Items 1–6 are **preconditions** for a safe first dispatch. Item 7 today is *"Clear the
DO-NOT-DISPATCH banner in `git-data-birth.md`"* — the terminal act, and the runbook says the banner
clears *"only when every item is done."* Appending the mandate as a new item 8 would therefore make
the list unexecutable in order: clear the banner, then do more work the banner was gating. The
mandate is itself a precondition — it rewrites the gate that guards the dispatch — so it takes
**position 7**, and banner-clearing becomes **item 8**.

Renumbering is safe: nothing outside the ADR references items 7 or 8 by number, and `Residual 2`'s
`"it is item 5 of the release checklist below"` is unaffected — verified.

```markdown
7. **Replace this interlock's mechanism with a direct assertion on the emitter resource, and
   delete the cloud-init text sentinel.** Operator decision, 2026-07-27 (DC-2). Once this issue
   defines the emitter as a real Terraform resource,
   `tests/scripts/lib/git-data-birth-readiness-gate.sh` must assert **that resource** rather than
   grep template text, and the `${sentry_dsn}` sentinel must be **removed**, not kept alongside
   it. This answers `dhh-rails-reviewer`'s *"prose with a `grep` wrapper"* and
   `architecture-strategist`'s structural objection at the root rather than by wrapping them. The
   falsification recorded under DC-2 does **not** license skipping this: what it killed was
   reading `heartbeat-manifest.ts`'s already-true `kind: "timer"` declaration — not reading the
   emitter's own resource, which cannot exist before this issue creates it. Until then the
   `${sentry_dsn}`-pinned sentinel stays exactly as shipped. **Accepted cost: a mandated interlock
   rewrite, not an optional cleanup.** Note that completing this retires the only mechanical check
   on item 1's threading — the replacement asserts a different fact — so item 1 is **absorbed**
   here, not left unenforced.
8. Clear the DO-NOT-DISPATCH banner in `git-data-birth.md`. *(Terminal: the runbook clears it only
   when every item above is done.)*
```

**2.2 — Extend item 5 with DC-3's mechanical constraints**, preserving every existing word. They
attach to item 5 because item 5 *is* the obligation they constrain.

```markdown
   **Operator decision, 2026-07-27 (DC-3): the cut stands, and this is where it lands.** Two
   mechanical constraints ride with it. First, it MUST single-source the address from
   `hcloud_server_network.git_data.ip` — never a fresh copy of the `10.0.1.20` literal. (The
   nearest precedent is #6415, which removed exactly such a duplicate on the sibling
   `hcloud_server_network.registry`; note it routed that resource through a `local` that still
   holds the string, so this mandate goes one step further and reads the resource attribute
   itself.) Second, its `OPERATOR_APPLIED_EXCLUSIONS` entry MUST land in the **same change**,
   because it is the absence of that entry that makes `terraform-target-parity.test.ts` red on
   landing and drives the remedy that wedges `main`.
```

**2.3 — Update one `## Alternatives considered` row.** The existing
`Include \`doppler_secret.git_data_ssh_host\`` row ends *"the dissent is recorded in the PR's
decision-challenges."* Amend that row's verdict to record that the operator **upheld** the cut on
2026-07-27, and give the dissent a resolvable address — the full artifact path
(`knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md`) and
`#6989`. This is the **reciprocal pointer**: without it the scope note added in Phase 1.4 points
only inward, and #6982's implementer reads the ADR, not a merged branch's spec dir.

**Do not add a new row for the interlock mechanism** — item 7 is its canonical home, and the
Alternatives table records *rejected* alternatives, not accepted mandates.

> **Table-edit foot-gun** (`work/SKILL.md`, anchor `never append to a markdown table row past its
> closing pipe`): text appended after a row's trailing `|` creates a cell beyond the header count and
> GFM **discards** it — the text survives in raw markdown, passes any grep-based AC, and renders as
> though the edit never happened. Edit *inside* the verdict cell; verify with **AC10**.

**2.4 — Make the ADR's own count-mirror universally quantified.** At anchor
`Items 2–7 are not machine-checked at all` (**en dash**), replace the range with `The remaining
items`. This is the third mirror and it is in the file Phase 2 is already editing.

**2.5 — Mark the sentinel interim where the architecture is described.**
`### The birth-readiness interlock` still reads *"**Mechanism:** … whose sentinel is the terraform
interpolation `${sentry_dsn}` … **That choice is load-bearing** … wiring the sentinel *is* the
work."* — with no hint of an expiry, three headings above an item mandating its deletion. Append one
clause: *"This mechanism is **interim**; checklist item 7 mandates its replacement by a direct
assertion on the emitter resource once #6982 defines one."* A reader learns what the architecture
*is* from the Decision section, not from the checklist.

**2.6 — Add provenance.** The header bullets carry `- **Issue:** #6977`. Add
`- **Amended by:** #7003 (operator decisions DC-2, DC-3 — 2026-07-27)` so the file's #7003-sourced
mandates have a traceable origin. ADR-149 has no YAML frontmatter (it uses a bullet list), so
`adr-frontmatter-ordinal-guard.test.ts` is unaffected — verified.

### Phase 3 — The gate: add the mandate where it is actionable, and stop stating counts

`tests/scripts/lib/git-data-birth-readiness-gate.sh`. **Comments and message text only** — no
branch, regex, or exit code.

**3.1 — Header `RELEASE CONDITION` list** (anchor `RELEASE CONDITION — the checklist #6982
inherits`): insert the new condition as item 7 and renumber banner-clearing to 8, matching the ADR.
Then change `It cannot check (2)-(7)` to `It cannot check the remaining items`.

**3.2 — HOLD message** (anchor `TO RELEASE THIS INTERLOCK`): add a 5th item —
*"Replace this gate's own mechanism with a direct assertion on the emitter resource and delete this
sentinel (ADR-149 release-checklist item 7; operator decision 2026-07-27, DC-2)."*

> This reverses the first draft, which put the mandate only in the RELEASED message on the grounds
> that it *"fires at release, not at hold."* That is right about the gate's state machine and wrong
> about the audience. `spec-flow-analyzer` established it: at **HOLD** the reader is the #6982
> implementer *starting* the work — the runbook confirms a dispatch today yields *"a clean refusal
> in about ten seconds."* At **RELEASE** they have already shipped the emitter, i.e. after the
> moment the rewrite decision had to be made. Delivering a mandate strictly after it is actionable
> is not delivering it. It is a `<<'HOLD'` quoted heredoc, so there is no interpolation risk.

**3.3 — RELEASED message** (anchor `Items 2-7 (Doppler scope reachability` — **ASCII** hyphen here,
unlike the ADR): replace the range **and its six-phrase enumeration** with a universally-quantified
statement:

> `… satisfies it. EVERY OTHER item on the ADR-149 release checklist — including this gate's own
> mandated replacement by a direct assertion on the emitter resource (operator decision 2026-07-27,
> DC-2) — is NOT machine-checked here.`

Three properties, each deliberate: it stays true at item 9 without an edit; it names the one item a
reader of *this file* most needs to know about; and it introduces **no ordinal reference** from an
executable file into the ADR's numbering. ADR-149's rationale is *"a gate believed to cover more
than it does is worse than one whose scope is written down"* — a universal quantifier writes the
scope down more precisely than an enumeration that can silently under-list. The header list 100
lines above still carries the per-item detail.

**Note for the editor:** 3.3 edits inside a double-quoted `echo`, unlike the HOLD heredoc. The
proposed text contains no `$`, backtick, or unescaped `"` — keep it that way.

**The literal `NOT machine-checked` must survive** — `test-git-data-birth-readiness-gate.sh` asserts
that exact substring on the RELEASED path (anchor `the RELEASE states what it did NOT check`). It is
the suite's only assertion on this text.

### Phase 4 — GitHub: **post-merge**, agent-executed

**Sequencing is the finding, not a detail.** These five calls are irreversible and the local change
is not. If they ran pre-merge and the PR were abandoned, force-pushed away, or closed unmerged,
#7003 would be CLOSED while nothing was recorded on `main`, and #6982 would carry a comment citing an
ADR item and a file path that do not exist. **R5** shows automation cannot recover that: the ADR-138
SLA cron's auto-close is vetoed by a human touch, so a wrongly-closed #7003 can never be re-surfaced.

Therefore: the PR body uses **`Ref #7003`**, never `Closes #7003` (which would auto-close at merge,
before any of this runs), and Phase 4 executes **after the merge lands**, in the same session, by the
agent. Nothing here is an operator step.

Write each body to the scratchpad in one Bash call and pass it to `gh` in a **separate** call — a
tool that consumes a file by path must not be batched with the tool that writes it. Before each
comment, **pre-check for its marker string** and skip if already present; a retried call that
actually landed must not double-post.

**4.1 — `gh issue edit 7003 --body-file`.** Rewrite the two stale headings to DC-1's in-body form
(`## DC-2 — RESOLVED by the operator on 2026-07-27`, same for DC-3) and replace the
`**Open question for the operator:**` paragraph with the decision plus the ADR-149 item pointers.
The precedent is DC-1, already edited this way in the same body. Without this the issue closes while
its own text says both are *"still open"* — the artifact the operator lands on would contradict its
own state.

**4.2 — `gh issue comment 7003 --body-file`.** Both RESOLVED blocks in full (identical text to
Phase 1), a pointer to the canonical artifact, and a closing line naming ADR-149 items 7 and 5. Note
explicitly that DC-3's question was *whether to reverse the cut* — the body poses no explicit DC-3
question, so "the cut stands" would otherwise answer something unstated.

**4.3 — `gh issue close 7003`.** Reason `completed` (the default); **not** `not-planned`.

**4.4 — `gh issue edit 6982 --body-file`.** Its `## Items` list is the seven checkboxes the
implementer actually works, and it **never names ADR-149**. Append two checkboxes — the DC-2
interlock replacement, and `doppler_secret.git_data_ssh_host` single-sourced from
`hcloud_server_network.git_data.ip` with its `OPERATOR_APPLIED_EXCLUSIONS` entry in the same change —
and add one line to `## Re-eval trigger` pointing at ADR-149's release checklist. The plan's own
Alternatives table rejects *"record only in the comments"*; that logic applies to an open issue's
comment versus its body too.

**4.5 — `gh issue comment 6982 --body-file`.** **Self-contained** — the implementer must never need
to open a closed issue. It carries: the DC-2 mandate (assert the emitter resource, delete the
sentinel, mandatory, ADR-149 item 7); the DC-3 single-source constraint plus the same-change
exclusion requirement (item 5); and the **routing rule** surfaced during research — a git-data
address goes in `OPERATOR_APPLIED_EXCLUSIONS` **or** in the per-PR `-target` set, never neither
(ADR-103). Item 3's *"all three"* enumeration covers only the target branch, and following it for a
resource that belongs on the exclusion branch reproduces the wedge DC-3 exists to prevent.

**4.6 — Verify (AC14).** Use `gh issue list --label` (List API), never `--search`, which silently
returns empty under App-installation tokens.

### Phase 5 — Artifacts, suites, commit

Write `tasks.md` and `session-state.md` under
`knowledge-base/project/specs/feat-one-shot-7003-dc2-dc3-operator-decisions/`. Run the readiness-gate
suite and the infra lint. Commit with a `docs(7003):` prefix, matching the repo's docs-only
convention (`docs(6969):`, `docs(adr-114):`). PR body: **`Ref #7003`**.

**If a Taste or User-Challenge decision arises during this work, record it in the PR body — do NOT
write `decision-challenges.md` under this branch's spec dir.** `/work`'s headless arm writes that
file automatically, and `ship` Phase 2.5 would then file a *new* `action-required` issue about the
recording of a resolved escalation. **AC12** is the after-the-fact catch; this is the prevention.

---

## Acceptance Criteria

Each command is scoped to a named file — a repo-wide grep would self-match this plan. Throughout:
`<dc>` = `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md`,
`<adr>` = `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md`,
`<gate>` = `tests/scripts/lib/git-data-birth-readiness-gate.sh`. Run from the worktree root.

### Pre-merge (PR)

- **AC1** — `grep -c '^### RESOLVED 2026-07-27 by the operator — ' <dc>` returns **3**. The em dash
  is part of the anchor, so the sibling `### RESOLVED — <date>:` form fails this. *(Returns 1 today.)*
- **AC2** — Placement: the line of `RESOLVED 2026-07-27 by the operator — replace the sentinel` lies
  between those of `^## DC-2 —` and `^## DC-3 —`; the line of
  `RESOLVED 2026-07-27 by the operator — the cut stands` is after `^## DC-3 —`. All three section
  anchors are single hits — verified.
- **AC3** — The header no longer misdescribes the file:
  `grep -c 'Status (2026-07-27): all three resolved by the operator' <dc>` = **1**.
- **AC4** — The two sentences most at risk of being trimmed survive **in both files**:
  `grep -c 'does NOT apply to this decision' <dc>` ≥ 1 (DC-2's carve-out),
  `grep -c 'does \*\*not\*\* license skipping' <adr>` ≥ 1 (the ADR copy — the one #6982's
  implementer reads), and `grep -c 'Residual 2' <dc>` ≥ 1 (the scope note, this plan's addition and
  the likeliest casualty).
- **AC5** — ADR-149's checklist has **8** items and the mandate is **item 7**, ahead of
  banner-clearing:
  `awk '/^### Interlock release checklist/{f=1;next} /^### /{f=0} /^## /{f=0} f' <adr> | grep -cE '^[0-9]+\. '`
  returns **8**; the same extraction piped to `grep -A2 '^7\. ' | grep -c 'emitter resource'`
  returns ≥ 1; and `grep -c '^8\. Clear the DO-NOT-DISPATCH banner'` returns 1.
  *(Returns 7 today. The awk window ends at `### Requirement arm split by entailment` and contains
  no other numbered list, which is why the line-anchored count is safe.)*
- **AC6** — Item 5 carries DC-3's constraints: the same awk extraction piped to
  `grep -c 'hcloud_server_network.git_data.ip'` returns ≥ 1.
- **AC7 — the count-free invariant, which is the whole of R1.**
  `grep -c 'Items 2-7\|Items 2–7\|(2)-(7)\|Items 2-8\|Items 2–8\|(2)-(8)' <adr> <gate>` returns
  **0 for both files**. Both dash forms are in the pattern deliberately: the ADR uses U+2013 and the
  gate uses ASCII, and a check written for one silently misses the other.
- **AC8 — the sentinel is marked interim where the architecture is described:**
  `grep -c 'This mechanism is \*\*interim\*\*' <adr>` = **1**, and it appears **before** the
  `### Interlock release checklist` heading (i.e. inside `### The birth-readiness interlock`).
- **AC9 — Phase 3 landed in all three gate locations:**
  `grep -c 'It cannot check the remaining items' <gate>` = **1** (header),
  `grep -c 'replace THIS GATE.s own' <gate>` = **1** (HOLD),

  > **AC9b amended at review time (2026-07-27), explicitly rather than silently.** The original
  > literal was `Replace this gate.s own mechanism`, which pinned the mandate as **item 5 of HOLD's
  > numbered `TO RELEASE THIS INTERLOCK` list**. Review rejected that placement on two grounds: a
  > release list whose item instructs the reader to *delete the interlock* is incoherent (completing
  > it does not release the gate, it removes it), and HOLD items 1–4 aligned 1:1 with ADR items 1–4,
  > so a new "5." reads as ADR item 5 (`GIT_DATA_SSH_HOST`) which it is not. The mandate stays in
  > HOLD — that audience argument was and remains correct — but as a note **after** the numbered
  > list. The AC is re-pinned to the new text rather than relaxed; it still asserts the mandate is
  > present in the HOLD message.
  `grep -c 'EVERY OTHER item on the ADR-149 release checklist' <gate>` = **1** (RELEASED), and
  `grep -c 'NOT machine-checked' <gate>` ≥ 1 (the substring the suite asserts on).
- **AC10 — the edited Alternatives row still renders.** `awk '{n=gsub(/\|/,"|"); print NR, n}' <adr>`
  shows the amended row's pipe count equal to a sibling row's, and
  `grep -c 'feat-one-shot-6977-git-data-birth-route/decision-challenges.md' <adr>` ≥ 1 (the
  reciprocal pointer). A grep alone cannot catch the pipe defect — GFM discards a cell past the
  header count while the raw text still matches.
- **AC11 — suites and lints.**
  - `bash tests/scripts/test-git-data-birth-readiness-gate.sh` exits **0** and prints
    `, 0 failed ===` (anchor on the leading comma — bare `0 failed` is a substring of `10 failed`).
    Its non-asserting live-file note must still read `HOLD`; a `RELEASED` note means something
    unrelated to this change moved.
  - `python3 scripts/lint-infra-no-human-steps.py <adr> <dc> knowledge-base/project/plans/2026-07-27-docs-record-dc2-dc3-operator-decisions-plan.md knowledge-base/project/specs/feat-one-shot-7003-dc2-dc3-operator-decisions/tasks.md`
    exits **0** **and its output names `4 scanned file(s)`**. The count assertion is load-bearing:
    the script drops non-existent paths silently and still exits 0, so a typo'd or not-yet-created
    path yields a green run over zero files. If it fires, wrap the offending region in
    `<!-- lint-infra-ignore start -->` / `<!-- lint-infra-ignore end -->` as ADR-149 already does —
    do **not** weaken the lint.
- **AC12 — diff scope.** `git diff --name-only origin/main...HEAD` contains **no** path under
  `apps/`, and `…/specs/feat-one-shot-7003-dc2-dc3-operator-decisions/decision-challenges.md` does
  **not** exist. Stated as an exclusion, not an allow-list: the plan file and `session-state.md` are
  legitimately in the diff.
- **AC13 — the PR body says `Ref #7003`, not `Closes #7003`.**
  `gh pr view --json body -q .body | grep -c 'Closes #7003'` returns **0**. Auto-closing at merge
  would discharge the escalation before Phase 4 runs.

### Post-merge (agent-executed, same session — **not** operator steps)

- **AC14 — GitHub state, asserted rather than assumed** (`hr-before-asserting-github-issue-status`):
  - `gh issue view 7003 --json state -q .state` returns `CLOSED`.
  - `gh issue view 7003 --json body -q .body | grep -c 'still open'` returns **0**, and the same body
    contains no `Open question for the operator`.
  - `gh issue view 7003 --json comments -q '[.comments[].body] | map(select(contains("RESOLVED 2026-07-27"))) | length'` returns exactly **1** — `>= 1` would pass a double-post from a retried call.
  - `gh issue list --label action-required --state open --limit 200 --json number -q '[.[].number] | index(7003)'`
    returns the literal string `null`. **Compare with `[[ "$out" == "null" ]]`** — today it returns
    `0` (7003 is the first element), so `-z` and `-eq 0` both invert the check. This is the
    mechanical form of *"the `action-required` label no longer applies"*: `operator-digest` and the
    ADR-138 SLA cron both filter on `--state open`. The label itself is **not** removed — see R6.
  - `gh issue view 6982 --json body -q .body` contains **both** `ADR-149` and
    `hcloud_server_network.git_data.ip`.
  - `gh issue view 6982 --json comments -q '[.comments[].body] | map(select(contains("hcloud_server_network.git_data.ip") and contains("emitter resource"))) | length'`
    returns exactly **1** — asserting **both** halves, so a trimmed body that drops the DC-2 mandate
    cannot pass.
- **AC15 — the merged tree still satisfies the file ACs.** Re-run AC1, AC5, AC7, AC9, AC11 against
  merged `main`. This is what makes the post-merge sequencing safe rather than merely late.
- **Abandonment path:** if the PR closes unmerged, Phase 4 simply never runs and #7003 stays open —
  which is the correct state. No compensating action is needed, and that is the point of the
  sequencing.

### Post-merge (operator)

**None.** Every step is agent-executed via file edits and `gh`. No vendor dashboard, no credential
mint, no infra apply, no human gate.

---

## Risks & Mitigations

**R1 — ADR-149 states its checklist size in three places, and the obvious edit fixes one.** The
ADR's own prose (`Items 2–7`, en dash), the gate's header (`(2)-(7)`), and the gate's RELEASED
message (`Items 2-7 (…)`) all go stale at 8 items, and nothing in CI compares any of them to the
list. *Both plan reviewers found this independently; the first draft had it.*
*Mitigation:* Phases 2.4 and 3 make all three **universally quantified** rather than incremented, so
item 9 never re-opens the question, and no new ordinal reference is introduced from an executable
file into the ADR's numbering. **AC7** asserts zero range forms with both dash characters.

**R2 — An item appended after "clear the banner" makes the checklist unexecutable in order.** The
runbook clears the DO-NOT-DISPATCH banner *"only when every item is done"*, so a mandate below
banner-clearing is a cycle. It is also a category error: items 1–6 are dispatch preconditions and the
mandate rewrites the gate that guards the dispatch, so it is one too.
*Mitigation:* the mandate takes **position 7**; banner-clearing moves to **8** and is marked
terminal. Verified that nothing outside the ADR references items 7 or 8 by number, and that
`Residual 2`'s `item 5` reference is unaffected. **AC5** asserts both the count and the ordering.

**R3 — Recording DC-3's rationale verbatim reads as contradicting ADR-149 `Residual 2`.** DC-3 says
the residual is *"accepted … unreachable today"*; `Residual 2` names *"the DC-3 disposition"* as the
reasoning that hid an unconditional post-birth false-alarm. A bolded, unqualified "accepted" above
the correction is a landmine — with, as this plan's own reviewers put it, a coin-flip chance of a
reader picking the reading that lets a birth ship without `GIT_DATA_SSH_HOST`.
*Mitigation:* three layers, none of which rewords the decision — an in-line scope marker inside the
operator's own sentence, the adjacent blockquote naming `Residual 2` and item 5, and the
**reciprocal** pointer added to the ADR in Phase 2.3 so the cross-reference is navigable from the
side #6982's implementer actually reads. **AC4** asserts the scope note.

**R4 — `ship` files a duplicate `action-required` issue.** `ship` Phase 2.5 opens an idempotent
`action-required` + `decision-challenge` issue whenever `specs/<current-branch>/decision-challenges.md`
exists and is non-empty, and `/work`'s headless arm creates that file automatically for any Taste or
User-Challenge decision. Escalating *the recording of a resolved escalation* is the failure.
*Mitigation:* the standing instruction in Phase 5 (prevention) plus **AC12** (catch).

**R5 — Irreversible GitHub effects ahead of a reversible merge.** Closing #7003 and commenting on
#6982 pre-merge means an abandoned PR leaves the escalation discharged with nothing on `main`, and
#6982 carrying a comment that cites an ADR item and a path that do not exist. ADR-138's cron cannot
recover it — its auto-close is vetoed by a human touch, and it does not reopen.
*Mitigation:* Phase 4 moves **post-merge**; the PR body uses `Ref #7003` so the merge itself cannot
auto-close it (**AC13**); **AC15** re-verifies the file ACs against merged `main`; and the
abandonment path is a no-op by construction.

**R6 — Stripping the `action-required` label instead of verifying closure.** *Considered and
rejected.* The deliverable says **confirm** the label no longer applies — a verification verb. Its
only live consumers filter on `--state open`, so closure alone discharges it; and ADR-138's own
root-cause work measured the channel's **resolution rate**, which requires closed issues to *retain*
the label. Removing it would destroy that signal. The `decision-challenge` label likewise stays — it
is the taxonomy record.

**R7 — Double-posting on a retry.** A `gh issue comment` that times out after the comment actually
landed, or a resumed session re-running Phase 4, posts twice; `gh issue close` on a closed issue
warns rather than fails.
*Mitigation:* pre-check for each comment's marker string before posting, and **AC14** asserts
`== 1`, not `>= 1`.

**R8 — Re-litigation creep.** The DC texts contain contestable claims (the 30-second hang, the
"unreachable today" scope, the interlock's soundness). The temptation while drafting is to argue.
*Mitigation:* the RESOLVED blocks state the decision, the operator's rationale, and the accepted cost
— nothing else. Every addition is a scope marker or a cross-reference to an existing paragraph, never
a new argument. One genuinely new finding (ADR-149 item 3's *"all three"* versus the fourth
`OPERATOR_APPLIED_EXCLUSIONS` registry) is routed to the **#6982 comment** rather than edited into
the ADR, precisely because it is a question the operator did not decide.

---

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| Increment the three counts (`2-7` → `2-8`) | **Rejected.** Correct once, wrong again at item 9, across two files with two dash characters and no test comparing them. |
| Add a CI test asserting *gate enumeration count == ADR item count* | **Rejected as gold-plating for this PR** (`architecture-strategist` proposed it; `code-simplicity-reviewer` would reject it). The universal-quantifier rewrite makes the compared value unnecessary rather than merely uncompared — there is no count left to drift. |
| Append the mandate as item 8, after banner-clearing | **Rejected.** Creates a cycle against the runbook's *"only when every item is done"* rule. See R2. |
| Amend ADR-149 **item 1** in place instead of adding an item | **Rejected.** Item 1's *"THREADING half"* language is load-bearing in the RELEASED message, and the mandate becomes discoverable only by reading item 1 to its end. |
| A separate `### Interlock replacement mandate` sub-section | **Rejected.** Leaves the numbered list at 7, so an implementer walking it stops before the mandate — the by-memory failure the brief names. |
| Add a new `## Alternatives considered` row for the mechanism | **Rejected.** That table records *rejected* alternatives; item 7 is an *accepted mandate* with a canonical home three headings up. |
| Put the mandate only in the gate's **RELEASED** message | **Rejected on the audience argument.** At RELEASE the implementer has already shipped the emitter — after the moment the rewrite decision had to be made. It goes in **HOLD**, which is what a dispatch today actually prints. |
| Delete the gate header's 7-item list outright | **Deferred, not rejected.** Probably the right end state — it duplicates a checklist it defers to — but a gate silent about its own mandated rewrite is worse. Noted as a follow-up for whoever executes item 7. |
| Comment on #6982 without editing its body | **Rejected.** Its `## Items` list is what the implementer works, and it never names ADR-149. The plan's own logic against "comments only" applies to an open issue's comment versus its body. |
| Close #7003 without editing its body | **Rejected.** The body says *"still open"* twice and poses the exact question DC-2 answers. DC-1's heading in the same body is the precedent for the fix. |
| Amend ADR-149 item 3 to name `OPERATOR_APPLIED_EXCLUSIONS` as a fourth site | **Rejected as out of scope** — a distinct question the operator did not decide, and item 3 is not wrong (the two are branches of one either/or rule). Routed to the #6982 comment, where it is exactly the guidance the implementer needs. |
| Run Phase 4 pre-merge | **Rejected.** See R5. |
| Remove the `action-required` label from #7003 | **Rejected.** See R6. |
| Edit the runbook `git-data-birth.md` | **Rejected — checked, no change needed.** Its banner defers to ADR-149's list, and the renumbering keeps banner-clearing terminal. |
| Fold `doppler_secret.git_data_ssh_host` into this PR | **Out of scope and contrary to the decision.** DC-3's entire content is that it lands in #6982. |

---

## Domain Review

**Domains relevant:** none

No cross-domain implications — a documentation + issue-hygiene change. No product surface, no
revenue / legal / marketing / support surface, no user-facing copy. The Product/UX gate does not
fire: the mechanical UI-surface override scans *Files to Create / Edit* for UI paths and finds none
(three `.md`, one `.sh`, plus `tasks.md` / `session-state.md`).

---

## Architecture Decision (ADR/C4)

**No new architectural decision.** This plan **records** two decisions the operator already made and
amends an existing ADR to carry them.

### ADR

`ADR-149-git-data-host-birth-route-and-readiness-interlock.md` — **amended, not superseded**
(Phase 2). No new ordinal is claimed, so `/ship`'s ADR-Ordinal Collision Gate has nothing to
re-derive and no renumber sweep is possible. Status stays `Accepted`. The amendment does change one
architectural *fact* the ADR asserts — that the `${sentry_dsn}` sentinel choice is load-bearing —
from permanent to interim, which is why Phase 2.5 lands a clause in the Decision section itself and
not only in the checklist.

### C4 views

**No C4 impact.** Checked against all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` by enumerating the
change's participants rather than grepping for its noun:

- **External human actors:** none added or changed. The only human is the operator, already modelled
  as the `founder` actor.
- **External systems / vendors:** none added. GitHub Issues is the only external surface touched and
  the agent→GitHub-issues relationship is already modelled (ADR-138 reaches the same conclusion for
  the SLA cron). Hetzner, Doppler and Sentry are *named in prose* but no relationship to them is
  created, removed, or re-pointed.
- **Containers / data stores:** none. No store is read or written.
- **Actor↔surface access relationships:** unchanged. No ownership, tenancy, or sharing boundary moves.

A future engineer reading only the existing ADRs and C4 would not be misled after this ships — the
one architectural fact it adds (the interlock's mandated replacement) lands *inside* ADR-149, which
is where such a reader already looks.

### Sequencing

None. Both decisions are recorded now; only their *execution* is future-dated, and that execution
belongs to #6982, tracked by ADR-149 items 5 and 7.

---

## Observability

The plan edits an executable file (`tests/scripts/lib/*.sh`), so this section is declared rather than
skipped — even though the edits are confined to comments and human-readable messages.

```yaml
liveness_signal:
  what: the birth-readiness gate's verdict line (HOLD / RELEASED / ABORT) on every
        apply_target=git-data-host-create dispatch, and on every CI run of
        tests/scripts/test-git-data-birth-readiness-gate.sh
  cadence: on dispatch (operator-initiated) and on every push that runs the shell suite
  alert_target: the dispatch job fails closed — a HOLD returns 1 and aborts the workflow run before
        any provider is contacted, surfacing as a red GitHub Actions run
  configured_in: tests/scripts/lib/git-data-birth-readiness-gate.sh (verdict text);
        .github/workflows/apply-web-platform-infra.yml (the job that sources it)
error_reporting:
  destination: GitHub Actions run status and job log. This change adds no runtime code path, so no
        Sentry surface is added or removed; the gate's ABORT and HOLD messages are the entire error
        surface and they already exist.
  fail_loud: yes, unchanged — the gate returns 1 on ABORT and on HOLD. Phase 3 edits only message
        text and comments, never a return value or a branch.
failure_modes:
  - mode: the RELEASED rewrite drops the literal "NOT machine-checked"
    detection: tests/scripts/test-git-data-birth-readiness-gate.sh, assertion
              "the RELEASE states what it did NOT check"
    alert_route: red shell-suite check on the PR, blocking merge
  - mode: an edit strays outside the comment/message regions and neuters a guard
    detection: the same suite's four mutation checks, which fail when an anchored guard stops
              changing behaviour under neutering
    alert_route: red shell-suite check on the PR
  - mode: ADR-149 gains an item while a count-mirror still states a range (the R1 drift)
    detection: AC7 — grep for both dash forms of the range across the ADR and the gate, expecting 0
    alert_route: pre-merge AC verification. There is deliberately no CI checker; the remedy is to
              remove the counts so there is nothing left to drift
  - mode: Phase 4 partially completes — commented but not closed, or body edited but not commented
    detection: AC14's six assertions, each naming a distinct artifact and state
    alert_route: post-merge AC verification in the same session. The ADR-138 SLA cron cannot recover
              this case, because a human touch vetoes its auto-close
  - mode: a retried gh call double-posts a comment
    detection: AC14 asserts comment counts == 1, not >= 1
    alert_route: post-merge AC verification
logs:
  where: GitHub Actions job logs for the dispatch workflow and for the PR's shell-suite job
  retention: GitHub's default workflow-log retention (90 days). No new log sink is created.
discoverability_test:
  command: bash tests/scripts/test-git-data-birth-readiness-gate.sh
  expected_output: "=== 21 passed, 0 failed ===" plus the non-asserting note
        "live cloud-init-git-data.yml: HOLD (no emitter yet — expected until #6982)"
```

No soak or time-gated close criterion is declared, so §2.9.1 Follow-Through Enrollment does not fire
— #7003 closes on the merge of this change, not after a soak window.

## Encryption Posture

**Skipped.** Phase 2.11 fires on `*.tf`, `supabase/migrations/*.sql`, `cloud-init*.ya?ml`, or
`docker-compose*.ya?ml`, or on prose introducing a persistent store or a new cross-component
connection. This plan introduces neither: no volume, bucket, table, queue, cache, backup target, or
log sink, and no new connection between components. The GitHub calls run over the existing `gh`
client against an already-established, already-disclosed integration.

---

## Sharp Edges

- **A checklist's size is stated in more places than the checklist.** ADR-149 states it three times
  across two files with two different dash characters, and nothing in CI compares them. Before adding
  an item to *any* numbered contract, grep for both range forms — `N-M` **and** `N–M` — across every
  file that names the artifact. This cost the first draft a P0.
- **An item's position in a checklist is a semantic claim.** Appending after a terminal item
  ("clear the banner", "flip the flag", "close the issue") creates a cycle whenever an external
  document says the terminal item happens last. Read the consumers before choosing a position.
- **A mandate delivered after it is actionable is not delivered.** The gate's HOLD message is what a
  dispatch prints today, so it is what the implementer reads *before* the work; RELEASED is what they
  see *after*. Put the handoff where the reader still has a decision to make.
- **Closing an issue does not edit its body.** #7003's body says *"still open"* twice and poses a
  question the decision answers; closing it without an edit leaves the artifact contradicting its own
  state. AC14 greps the body, not just the state.
- **Irreversible remote effects belong after the reversible local merge.** Use `Ref #N`, never
  `Closes #N`, when the closure is executed by a post-merge step — otherwise the merge discharges the
  issue before the work that justifies it has run.
- **The DC-2 carve-out is the most fragile sentence in the change.** A reader who meets *"DC-2's
  recommended alternative was falsified by measurement"* and *"DC-2 resolved: do the thing"* without
  the carve-out concludes the operator overruled a measurement. It must state *what* was falsified
  (reading `heartbeat-manifest.ts`, whose `kind: "timer"` is already true) and *why it does not
  reach* the emitter resource. AC4 asserts it **in both files** — the ADR copy is the one #6982's
  implementer reads.
- **Never use `awk '/start/,/end/'` to extract the ADR checklist.** The range self-matches its own
  start line and returns the heading only, so a verifier built on it passes against an **empty** body.
  AC5 uses the flag-based form deliberately.
- **Editing a markdown table row: stay inside the cell.** Text past the trailing `|` is discarded by
  GFM, survives in raw markdown, and passes any grep-based AC. AC10 is the pipe-count gate.
- **`lint-infra-no-human-steps.py` exits 0 over zero files.** Non-existent paths are dropped silently.
  Assert the `N scanned file(s)` count, not just the exit status (AC11).
- **`gh issue list … index(N)` returns `0`, not empty, when N is first.** Compare against the literal
  string `null`; `-z` and `-eq 0` both invert the check (AC14).
- **Assert comment counts as `== 1`.** `>= 1` passes a double-post from a retried call that had
  already landed.
- **Grepping the repo for this plan's own literals self-matches.** Every AC is scoped to a named
  file. If one is widened, exclude `knowledge-base/project/{plans,specs}/**`.
- **Do not "fix" the gate's `NOT machine-checked here`.** Checklist item 3 *is* machine-checked — by
  `terraform-target-parity.test.ts`, not by the gate. The word `here` is doing real work, and that
  exact substring is the suite's only assertion on this text.
