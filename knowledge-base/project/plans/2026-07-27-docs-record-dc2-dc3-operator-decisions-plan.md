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

## Overview

The operator made two calls on 2026-07-27 on the decision challenges surfaced by PR #6989
(issue **#7003**, labelled `action-required` + `decision-challenge`). Both are still recorded as
open — in `decision-challenges.md` and in the issue body. This change records them faithfully,
propagates the one mandate a downstream issue must inherit, and closes the escalation.

This is a **recording** task, not a design task. Both decisions are the operator's and are
**final**. Nothing here re-opens, re-weighs, or softens either one.

| | Decision | The thing that must not get lost |
|---|---|---|
| **DC-2** | Replace the sentinel with a **direct emitter check** when #6982 lands. | The falsification recorded under DC-2 does **not** apply to this decision. Accepted cost: #6982 inherits a *mandated* interlock rewrite. |
| **DC-3** | The cut stands. `doppler_secret.git_data_ssh_host` lands in **#6982**. | It MUST single-source from `hcloud_server_network.git_data.ip`, and the `OPERATOR_APPLIED_EXCLUSIONS` entry MUST land in the same change. |

**Scope shape:** three markdown/shell-comment edits + three GitHub API calls. No product code, no
infra resources, no schema, no runtime behaviour. The only executable file touched is a shell
gate, and only its **comment block and its human-readable success message** — no branch, no regex,
no exit code.

**The one non-obvious hazard, found by both plan reviewers and confirmed by measurement:** ADR-149
states its checklist size in **three** places, not one. Adding an 8th item without touching the
other two ships the exact drift this change exists to prevent, *inside the file being edited*.
Phase 2(d) and Phase 3 fix that by **deleting the counts** rather than by incrementing them, so a
9th item never re-opens the question. See **R1**.

---

## Premise Validation (Phase 0.6)

Every reference the brief cites was probed against live state. All ten held; the four that gate a
decision are listed first.

| Premise | Probe | Result |
|---|---|---|
| ADR-149's checklist is a **7-item numbered list** under `### Interlock release checklist — #6982 inherits this` | Read the ADR | **HOLDS** — and the ADR restates the count again in prose at content anchor `Items 2–7 are not machine-checked at all` (**en dash**, U+2013), which the gate's ASCII `2-7` form does *not* match. Third mirror. |
| DC-1's RESOLVED heading form | Read `decision-challenges.md` | **HOLDS** — `### RESOLVED 2026-07-27 by the operator — ship the route now, interlocked`. |
| The emitter has **no** Terraform resource today | The gate suite's non-asserting live-file probe | **HOLDS** — reports `HOLD`. Nothing exists for a resource assertion to bind to yet, which is why DC-2 is future-dated. |
| `hcloud_server_network.git_data.ip` is a real, referenceable attribute | Read `apps/web-platform/infra/network.tf` | **HOLDS** — `resource "hcloud_server_network" "git_data" { … ip = "10.0.1.20" }`. |
| #7003 open, `action-required` + `decision-challenge` | `gh issue view 7003 --json state,labels` | **HOLDS.** |
| #6982 open, and is the right inheritor | `gh issue view 6982 --json state,title` | **HOLDS** — *"git-data: pre-birth hardening + observability (blocks the first birth)"*. |
| `heartbeat-manifest.ts` declares git-data's feeder `kind: "timer"` | `grep -n git-data plugins/soleur/lib/heartbeat-manifest.ts` | **HOLDS** — row `name: "git_data_prd"`, `feeder: { kind: "timer", … }`. The falsified proposal really would release immediately. |
| `doppler_secret.git_data_ssh_host` is absent | `grep -rn git_data_ssh_host apps/web-platform/infra/` | **HOLDS** — zero hits in `infra/`; only consumer-side references in `apps/web-platform/server/git-data-replication.ts`. |
| `OPERATOR_APPLIED_EXCLUSIONS` is where the exclusion entry lands | `grep -n OPERATOR_APPLIED_EXCLUSIONS plugins/soleur/test/terraform-target-parity.test.ts` | **HOLDS**, and the file **already names DC-3**: the `doppler_config.git_data_prd` comment says *"killed the `doppler_secret.git_data_ssh_host` proposal (DC-3)"*. |
| The gate suite is green and its anchors are outside the edited regions | `bash tests/scripts/test-git-data-birth-readiness-gate.sh` | **HOLDS** — `21 passed, 0 failed`; mutations anchor on `strip_comments=`, `sentinel_re=`, `if [[ "$hits" -eq 0 ]]`, `if [[ ! -f "$cloud_init" ]]`, none in the header block or the RELEASED `echo`. |

---

## Research Reconciliation — brief vs. codebase

| Claim | Reality on disk | Plan response |
|---|---|---|
| DC-3's rationale: *"unreachable today, because `doppler_secret.git_remove_ssh_private_key` is absent from state."* | **True today.** ADR-149 `Residual 2` records a correction to that claim's **scope**: *"'Unreachable today' was true; 'unreachable once this route is used' was not"* — the false alarm becomes **unconditional after any birth**, which is why checklist item 5 requires `GIT_DATA_SSH_HOST` before the first dispatch. | Record the operator's rationale **verbatim** (correct for the pre-birth window it governs) and add **one cross-reference line** to ADR-149 Residual 2 so the two documents do not read as contradicting each other. Both reach the same action. **See R2.** |
| Brief: *"a 25th copy of the `10.0.1.20` literal"* | The literal appears **30×** across `apps/ tests/ plugins/ scripts/ .github/`; 68× repo-wide including docs. | Record the operator's phrase as written — it is rhetorical, not a count assertion. Introduce **no** count into any artifact; assert only the mechanical constraint. |
| Brief: propagate DC-2 into *"the ADR-149 release checklist"* | The checklist's size is mirrored in **three** places: ADR-149's own prose (`Items 2–7`, en dash), the gate's header (`It cannot check (2)-(7)`), and the gate's RELEASED message (`Items 2-7 (…six phrases…)`). | Add item 8 **and** make all three sites count-free in the same change. **See Phase 2(d), Phase 3, R1.** |
| #6415 is the precedent for single-sourcing the address | **Partially.** `apps/web-platform/infra/network.tf` routes `hcloud_server_network.registry` through `ip = local.registry_private_ip`, and `apps/web-platform/infra/zot-registry.tf` defines `registry_private_ip = "10.0.1.30"`. So #6415 removed a *duplicate* literal but the literal still lives in a `local` — it does **not** demonstrate reading the resource attribute, which is what DC-3 mandates. | Cite #6415 **accurately** as the nearest precedent for refusing a duplicated literal, and state that DC-3's mandate goes one step further. Keep the citation out of the RESOLVED block entirely, so that block carries only the operator's own words. |
| Editing `decision-challenges.md` after `ship` ran will be clobbered | **False.** `ship` full-replaces the **PR body**, not the artifact; its Phase 2.5 reads `specs/<current-branch>/decision-challenges.md`. This branch is `feat-one-shot-7003-…`; the edited file is under `specs/feat-one-shot-6977-…`. | Proceed. **But** do not create a `decision-challenges.md` under *this* branch's spec dir, or `ship` Phase 2.5 files a duplicate `action-required` issue. **See R3.** |
| Also checked, nothing to do | No test/lint/workflow reads `decision-challenges.md` **content**; `adr-frontmatter-ordinal-guard.test.ts` checks ADR frontmatter only; `scripts/lint-infra-no-human-steps.py` **does** scan the ADR + specs + plans dirs (so AC7 applies); and checklist item 3 *is* machine-checked by `terraform-target-parity.test.ts` — the gate's `NOT machine-checked **here**` is scoped and therefore accurate. Do not "fix" it. | — |

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — no runtime surface changes. The
realistic failure is downstream and delayed: if the DC-2 mandate is recorded only in a closed
issue's comment and not in ADR-149's checklist, #6982 satisfies all seven listed items, ships the
emitter, and leaves in place a text-grep interlock that three reviewers already called unsound —
re-introducing the *"a green apply and a dark host are indistinguishable"* exposure ADR-149 exists
to close, on the host that will hold every connected user's source code.

**If this leaks, the user's data / workflow / money is exposed via:** nothing. No secret,
credential, or PII is introduced. The `10.0.1.20` private-network address already appears 30× in
the tracked tree; DC-3's whole constraint is to *stop* copying it.

**Brand-survival threshold:** `none`. *Reason:* the change writes markdown and shell comments and
calls three GitHub endpoints; it touches no sensitive path (no schema, migration, auth flow, API
route, or `.sql`), has no execution path a user can reach, and no data-handling surface. Its only
failure mode is documentation drift, which AC1–AC10 catch.

---

## Files to Edit

| File | Change |
|---|---|
| `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md` | Append a `### RESOLVED 2026-07-27 by the operator — …` block under **DC-2** (before its `---`) and one under **DC-3** (end of file). |
| `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md` | **(a)** append **item 8** to the release checklist; **(b)** extend **item 5** with DC-3's two mechanical constraints; **(c)** update the existing `Include doppler_secret.git_data_ssh_host` row in `## Alternatives considered` (dissent → upheld); **(d)** make the prose at content anchor `Items 2–7 are not machine-checked at all` **count-free**. |
| `tests/scripts/lib/git-data-birth-readiness-gate.sh` | **Comment + message text only.** Header `RELEASE CONDITION` list gains an 8th bullet; `It cannot check (2)-(7)` and the RELEASED message's `Items 2-7 (…)` both become count-free. |

## Files to Create

| File | Purpose |
|---|---|
| `knowledge-base/project/plans/2026-07-27-docs-record-dc2-dc3-operator-decisions-plan.md` | This plan (currently untracked; committed by `/work`). |
| `knowledge-base/project/specs/feat-one-shot-7003-dc2-dc3-operator-decisions/tasks.md` | Task breakdown. |
| `knowledge-base/project/specs/feat-one-shot-7003-dc2-dc3-operator-decisions/session-state.md` | Written by `/work` alongside `tasks.md`; named here so AC10 does not false-fail. |
| *(transient, not committed)* two comment bodies under the session scratchpad, passed to `gh issue comment --body-file`. | Avoids the shell-quoting hazard of a multi-paragraph `--body`. Write in one Bash call, invoke `gh` in the **next** one. |

**Explicitly NOT created:** `…/specs/feat-one-shot-7003-dc2-dc3-operator-decisions/decision-challenges.md`. See **R3**.

**Explicitly NOT edited:** `knowledge-base/engineering/operations/runbooks/git-data-birth.md`. Its
banner defers to ADR-149's list rather than restating it (*"The full release checklist is in
ADR-149. Clear this banner only when every item is done"*), so it stays true at 8 items. Checked,
no change required — recorded so the next reader knows it was checked rather than missed.

## Open Code-Review Overlap

**None.** `gh issue list --label code-review --state open --limit 200 --json number,title,body`
filtered with a standalone `jq --arg` for each of `decision-challenges.md`, `ADR-149`, and
`git-data-birth-readiness-gate.sh` returned zero matches.

---

## Implementation Phases

### Phase 1 — Record both decisions in `decision-challenges.md`

Mirror DC-1's shape exactly: `### RESOLVED 2026-07-27 by the operator — <verdict>`, a bolded
`**Decision: …**` lead, the rationale, then the accepted cost stated plainly.

> A second precedent exists at `specs/feat-one-shot-6425-web2-tunnel-depool-host-id/decision-challenges.md`
> using `### RESOLVED — <date>: <verdict>`. **Do not use it.** The brief mandates DC-1's form, and
> DC-1 is in the same file.

**1.1 — DC-2 block.** Insert after DC-2's `**Plan's current disposition:**` paragraph and
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

**Accepted cost: #6982 inherits a mandated interlock rewrite** — not an optional cleanup.
Recorded as **item 8 of ADR-149's release checklist**, and mirrored into the gate's own header
and success message, so it is carried mechanically rather than by memory.
```

**1.2 — DC-3 block.** Append at end of file (DC-3 is last; no trailing `---`). Note this block
carries **only the operator's own rationale** plus one cross-reference — the #6415 precedent
citation belongs in ADR-149 item 5, where it can be stated with the precision it needs.

```markdown
### RESOLVED 2026-07-27 by the operator — the cut stands; it lands in #6982

**Decision: retain the cut.** `doppler_secret.git_data_ssh_host` stays out of #6977 and lands in
**#6982**, where the emitter work already touches `git-data.tf` and the
`OPERATOR_APPLIED_EXCLUSIONS` entry can land in the **same change**. When it lands it **MUST**
single-source the address from `hcloud_server_network.git_data.ip` — never a fresh copy of the
`10.0.1.20` literal.

**The residual false-"Art. 17 erasure failed" alarm window is accepted**, because it is
unreachable today: `doppler_secret.git_remove_ssh_private_key` is itself absent from state, so
the arming switch is unarmed.

> Scope note, for the reader arriving here from ADR-149: *"unreachable today"* is a statement
> about the **pre-birth** window, which is the window this decision governs. ADR-149 `Residual 2`
> records the correction that the false alarm becomes **unconditional after any birth** — which
> is why release-checklist **item 5** requires `GIT_DATA_SSH_HOST` to be produced **before the
> first dispatch**. The two documents agree on the action: produce it in #6982, before any birth.

**Why not add it now anyway.** Adding the resource today would still drag `hcloud_server.git_data`
into the per-merge plan via **transitive upstream closure** and **wedge every merge to `main`** —
the ADR-145 web-2 wedge, reproduced for git-data from a one-line edit. A capability that cannot
be merged is not a capability.

**`spec-flow-analyzer`'s 30-second-hang finding is noted but not decisive.** That hang occurs only
*while the host is unreachable* — and #6982's birth is precisely what ends that condition. It is
an argument about the ordering of two things that now ship together, not about whether to ship
them.
```

### Phase 2 — Propagate into ADR-149

**Verify before editing** (the brief mandates this): re-read
`### Interlock release checklist — #6982 inherits this` and confirm it is still a 7-item numbered
list of prose sentences with bolded lead phrases, several carrying inline back-references
(`— see *Alternatives*`). **Mirror that shape** — no table, no checkboxes, no new heading level.

**2.1 — Append item 8.** Placement is not "somewhere after the list": insert it **immediately
after item 7** (`7. Clear the DO-NOT-DISPATCH banner in git-data-birth.md.`) and **before** the
paragraph beginning `**The gate mechanically enforces only the THREADING half of item 1**`.
Placing it after that paragraph breaks the ordered list and puts the mandate outside the scope
statement — and AC5's item count cannot tell the two apart.

```markdown
8. **Replace this interlock's mechanism with a direct assertion on the emitter resource, and
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
   rewrite, not an optional cleanup.**
```

**2.2 — Extend item 5 with DC-3's mechanical constraints**, preserving every word already there.
DC-3's constraints are appended to item 5 because item 5 *is* the obligation they constrain.

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

**2.3 — Update one row of `## Alternatives considered`.** The existing
`Include \`doppler_secret.git_data_ssh_host\`` row ends *"the dissent is recorded in the PR's
decision-challenges."* Amend that row's verdict to note the operator **upheld** the cut on
2026-07-27. **Do not add a new row for the interlock mechanism** — item 8 is its canonical home,
and a second entry would be a third copy of DC-2 inside one file.

> **Table-edit foot-gun (`work/SKILL.md`, anchor `never append to a markdown table row past its
> closing pipe`):** text appended after a row's trailing `|` creates a cell beyond the header
> count, and GFM **discards** it — the text survives in raw markdown, passes any grep-based AC, and
> renders as though the edit never happened. Edit *inside* the verdict cell, and verify with the
> pipe-count check in **AC9**.

**2.4 — Make the ADR's own count-mirror count-free.** At content anchor
`Items 2–7 are not machine-checked at all` (**en dash**), replace the range with `The remaining
items`. This is the third mirror; it is in the file Phase 2 is already editing, and no test
compares it to anything.

### Phase 3 — Delete the gate's counts rather than increment them

`tests/scripts/lib/git-data-birth-readiness-gate.sh` states the checklist size twice. Incrementing
both works once; deleting the counts works forever, and removes the need to re-do this for item 9.

**3.1** — Header block, content anchor `RELEASE CONDITION — the checklist #6982 inherits`: append
an 8th bullet — *"this gate's own mechanism is replaced by a direct assertion on the emitter
resource, and this text sentinel is deleted (operator decision 2026-07-27, DC-2);"* — and change
the sentence that follows from `It cannot check (2)-(7)` to `It cannot check the remaining items`.

> Recorded dissent: `code-simplicity-reviewer` argued for **deleting** the gate header's 7-item
> list outright, since it duplicates a checklist it explicitly defers to, and called growing it the
> wrong direction. That is probably the right end state, but the gate is the artifact item 8
> mandates rewriting — a gate silent about its own mandated replacement is the worse failure. The
> bullet stays; the de-duplication is noted as a follow-up for whoever executes item 8.

**3.2** — RELEASED message, content anchor `Items 2-7 (Doppler scope reachability` (**ASCII**
hyphen here, unlike the ADR): replace the range with `The REMAINING checklist items`, keep the
six-phrase enumeration (it is the gate's scope-honesty statement, which ADR-149 calls load-bearing),
and extend it with `and this gate's own mandated replacement by a direct emitter-resource
assertion (ADR-149 item 8)`.

**The literal `NOT machine-checked` must survive both edits** — `test-git-data-birth-readiness-gate.sh`
asserts that exact substring on the RELEASED path (content anchor
`the RELEASE states what it did NOT check`). It is the only assertion in the suite that touches
this text.

**Do not touch** the HOLD message's abbreviated 1–4 list. It has always been an explicit subset
deferring to ADR-149, so an 8th item does not make it false — and DC-2's mandate fires at
**release**, not at hold.

### Phase 4 — Post to #7003 and #6982, then close #7003

Order is load-bearing: **comment, close, verify.** Write each body to the scratchpad in one Bash
call and pass it to `gh` in a **separate** call — a tool that consumes a file by path must not be
batched with the tool that writes it.

**4.1** — `gh issue comment 7003 --body-file <path>`. Body carries **both** RESOLVED blocks in full
(identical text to Phase 1), a pointer to the canonical artifact
(`knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md`),
and a closing line stating that DC-2's mandate is now ADR-149 checklist **item 8** and DC-3's
constraints are on **item 5**. The issue then closes against its **body** — which describes both as
still open — rather than against a looser grouping.

**4.2** — `gh issue close 7003`. Reason `completed` (the default); **not** `not-planned`.

**4.3** — `gh issue comment 6982 --body-file <path>`. **Self-contained** — the implementer must
never need to open a closed issue. It carries: the DC-2 mandate (assert the emitter resource,
delete the sentinel, mandatory not optional); the DC-3 single-source constraint
(`hcloud_server_network.git_data.ip`, never a fresh `10.0.1.20` literal) plus the same-change
`OPERATOR_APPLIED_EXCLUSIONS` requirement; and pointers to ADR-149 items 8 and 5.

**4.4** — Verify (**AC8**). Use `gh issue list --label` (List API) + a client-side `jq` filter,
never `gh issue list --search`, which silently returns empty under App-installation tokens.

### Phase 5 — Artifacts, suite, commit

Write `tasks.md` (and `session-state.md`) under
`knowledge-base/project/specs/feat-one-shot-7003-dc2-dc3-operator-decisions/`. Run the
readiness-gate suite and the infra lint. Commit with a `docs(7003):` prefix, matching the repo's
docs-only convention (`docs(6969):`, `docs(adr-114):`).

**If a Taste or User-Challenge decision arises during this work, record it in the PR body — do NOT
write `decision-challenges.md` under this branch's spec dir.** `/work`'s headless arm writes that
file automatically, and `ship` Phase 2.5 would then file a *new* `action-required` issue about the
recording of a resolved escalation. **AC10** asserts the file's absence, but that is a
after-the-fact catch; this instruction is the prevention.

---

## Acceptance Criteria

Each command is scoped to a single named file — a repo-wide grep would self-match this plan.
Throughout: `<dc>` = `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md`,
`<adr>` = `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md`,
`<gate>` = `tests/scripts/lib/git-data-birth-readiness-gate.sh`. Run from the worktree root.

### Pre-merge (PR)

- **AC1** — `grep -c '^### RESOLVED 2026-07-27 by the operator — ' <dc>` returns **3** (DC-1's
  original plus the two new). The em dash is part of the anchor, so the sibling
  `### RESOLVED — <date>:` form fails this. *(Returns 1 today — verified.)*
- **AC2** — Each block is in the right section: the line number of
  `RESOLVED 2026-07-27 by the operator — replace the sentinel` lies between those of `^## DC-2 —`
  and `^## DC-3 —`; the line of `RESOLVED 2026-07-27 by the operator — the cut stands` is after
  `^## DC-3 —`. All three section anchors are single hits — verified.
- **AC3** — The two sentences most at risk of being trimmed for brevity are present:
  `grep -c 'does NOT apply to this decision' <dc>` ≥ 1 (DC-2's carve-out) and
  `grep -c 'Residual 2' <dc>` ≥ 1 (DC-3's ADR cross-reference, which is this plan's addition and
  therefore the likeliest casualty).
- **AC4** — ADR-149's checklist has **8** items:
  `awk '/^### Interlock release checklist/{f=1;next} /^### /{f=0} /^## /{f=0} f' <adr> | grep -cE '^[0-9]+\. '`
  returns **8**. *(Returns 7 today — verified; the window ends at `### Requirement arm split by
  entailment` and contains no other numbered list, which is why the line-anchored count is safe.)*
- **AC5** — Item 5 carries DC-3's constraints: the same awk extraction piped to
  `grep -c 'hcloud_server_network.git_data.ip'` returns ≥ 1.
- **AC6 — the count-free invariant, which is the whole of R1.**
  `grep -c 'Items 2-7\|Items 2–7\|(2)-(7)\|Items 2–8\|Items 2-8\|(2)-(8)' <adr> <gate>` returns
  **0 for both files**. Both dash forms are in the pattern deliberately: the ADR uses U+2013 and
  the gate uses ASCII, and a check written for one silently misses the other.
- **AC7 — Phase 3 actually landed:** `grep -c 'direct assertion on the emitter resource' <gate>`
  ≥ 1 (header bullet 8), `grep -c 'It cannot check the remaining items' <gate>` = 1, and
  `grep -c 'NOT machine-checked' <gate>` ≥ 1 (the substring the suite asserts on must survive).
- **AC8 — GitHub state, asserted rather than assumed** (`hr-before-asserting-github-issue-status`):
  - `gh issue view 7003 --json state -q .state` returns `CLOSED`.
  - `gh issue view 7003 --json comments -q '[.comments[].body] | map(select(contains("RESOLVED 2026-07-27"))) | length'` returns ≥ 1.
  - `gh issue list --label action-required --state open --limit 200 --json number -q '[.[].number] | index(7003)'` returns the literal string `null`. **Compare with `[[ "$out" == "null" ]]`** — today it returns `0` (7003 is the first element), so `-z` or `-eq 0` inverts the check. This is the mechanical form of *"the `action-required` label no longer applies"*: `operator-digest` and the ADR-138 SLA cron both filter on `--state open`.
  - `gh issue view 6982 --json comments -q '[.comments[].body] | map(select(contains("hcloud_server_network.git_data.ip"))) | length'` returns ≥ 1.
- **AC9 — the edited `Alternatives considered` row still renders.** `awk '{n=gsub(/\|/,"|"); print NR, n}' <adr>`
  shows the amended row's pipe count equal to a sibling row's. A grep alone cannot catch this —
  GFM discards a cell past the header count while the raw text still matches.
- **AC10 — diff scope.** `git diff --name-only origin/main...HEAD` contains **no** path under
  `apps/`, and
  `knowledge-base/project/specs/feat-one-shot-7003-dc2-dc3-operator-decisions/decision-challenges.md`
  does **not** exist. (Stated as an exclusion, not an allow-list: the plan file and
  `session-state.md` are legitimately in the diff.)
- **AC11 — suites and lints.**
  - `bash tests/scripts/test-git-data-birth-readiness-gate.sh` exits **0** and prints `, 0 failed ===`
    (anchor on the leading comma — bare `0 failed` is a substring of `10 failed`). Its
    non-asserting live-file note must still read `HOLD`; a `RELEASED` note means something
    unrelated to this change moved.
  - `python3 scripts/lint-infra-no-human-steps.py <adr> <dc> knowledge-base/project/plans/2026-07-27-docs-record-dc2-dc3-operator-decisions-plan.md knowledge-base/project/specs/feat-one-shot-7003-dc2-dc3-operator-decisions/tasks.md`
    exits **0** **and its output names `4 scanned file(s)`**. The count assertion is load-bearing:
    the script drops non-existent paths silently and still exits 0, so a typo'd or not-yet-created
    path yields a green run over zero files. If it fires, wrap the offending region in
    `<!-- lint-infra-ignore start -->` / `<!-- lint-infra-ignore end -->` exactly as ADR-149
    already does for its historical-laptop-apply paragraph — do **not** weaken the lint.

### Post-merge (operator)

**None.** Every step is executed by the agent in-session via file edits and `gh`. There is no
vendor dashboard, no credential mint, no infra apply, and no human gate anywhere in this change.

---

## Risks & Mitigations

**R1 — ADR-149 states its checklist size in three places, and the obvious edit fixes one.** The
ADR's own prose (`Items 2–7`, en dash), the gate's header (`(2)-(7)`), and the gate's RELEASED
message (`Items 2-7 (…)`) all go stale at 8 items. Nothing in CI compares any of them to the list.
An edit that adds item 8 and stops has shipped the exact drift this change exists to prevent, in
the file it just edited. *Both plan reviewers found this independently; the first draft of this
plan had it.*
*Mitigation:* Phase 2.4 and Phase 3 make all three sites **count-free** rather than incrementing
them, so item 9 never re-opens the question. **AC6** asserts zero occurrences of either range form
in either file, with both dash characters in the pattern.

**R2 — Recording DC-3's rationale verbatim reads as contradicting ADR-149 `Residual 2`.** DC-3 says
the false alarm is *"unreachable today"*; `Residual 2` explicitly corrects an earlier draft that
reasoned the same way, and states it becomes **unconditional after any birth**. Side by side
without comment, a later reader concludes one supersedes the other — with a 50 % chance of picking
the one that lets a birth ship without `GIT_DATA_SSH_HOST`.
*Mitigation:* the scope note in Phase 1.2, asserted by **AC3**. It is a cross-reference to an
existing ADR paragraph, **not** a re-weighing of the operator's call — both reach the same action.

**R3 — `ship` files a duplicate `action-required` issue.** `ship` Phase 2.5 opens an idempotent
`action-required` + `decision-challenge` issue whenever `specs/<current-branch>/decision-challenges.md`
exists and is non-empty, and `/work`'s headless arm creates that file automatically for any Taste
or User-Challenge decision. Escalating *the recording of a resolved escalation* is the failure.
*Mitigation:* the standing instruction in Phase 5 (prevention) plus **AC10** (catch).

**R4 — The SLA cron's human-engagement veto strands #7003 open forever.** ADR-138 makes
`decision-challenge` an expirable class, but expiry is vetoed by a non-bot assignee or a recent
non-bot touch — so an operator touch makes the cron structurally unable to close it.
Comment-without-close would leave the escalation live indefinitely.
*Mitigation:* Phase 4 closes explicitly in the same run as the comment; **AC8** asserts `CLOSED`
rather than inferring it from an exit code.

**R5 — Stripping the `action-required` label instead of verifying closure.** *Considered and
rejected.* The deliverable says **confirm** the label no longer applies — a verification verb. Its
only live consumers filter on `--state open`, so closure alone discharges it; and ADR-138's own
root-cause work measured the channel's **resolution rate**, which requires closed issues to
*retain* the label. Removing it would destroy that signal. The `decision-challenge` label likewise
stays — it is the taxonomy record.

**R6 — Re-litigation creep.** The DC texts contain genuinely contestable claims (the 30-second
hang, the "unreachable today" scope, the interlock's soundness). The temptation while drafting is
to argue with them.
*Mitigation:* the RESOLVED blocks state the decision, the operator's rationale, and the accepted
cost — nothing else. The only added material is the R2 cross-reference, which points at an existing
ADR paragraph rather than introducing a new argument.

---

## Alternatives Considered

| Alternative | Verdict |
|---|---|
| Increment the three counts (`2-7` → `2-8`) instead of deleting them | **Rejected.** Correct once, then wrong again at item 9, in three files with two different dash characters and no test comparing them. Deleting the count removes the failure mode. |
| Amend ADR-149 **item 1** in place instead of adding item 8 | **Rejected.** Keeps the count at 7, but item 1's *"THREADING half"* language is load-bearing in the RELEASED message, and the mandate becomes discoverable only by reading item 1 to its end. A numbered item is what "carried mechanically" means. |
| A separate `### Interlock replacement mandate` sub-section after the checklist | **Rejected.** Leaves the numbered list at 7, so an implementer walking the checklist stops before reaching the mandate — the by-memory failure the brief names. |
| Add a new `## Alternatives considered` row for the interlock mechanism | **Rejected** (`code-simplicity-reviewer`). That table records *rejected* alternatives; item 8 is an *accepted mandate* with a canonical home three headings up. It would be a third copy of DC-2 in one file. |
| Delete the gate header's 7-item list outright | **Deferred, not rejected.** Probably the right end state — it duplicates a checklist it explicitly defers to — but a gate silent about its own mandated rewrite is worse. Noted as a follow-up for whoever executes item 8. See Phase 3.1's recorded dissent. |
| Also add the mandate to the gate's **HOLD** message | **Rejected.** The HOLD list is an explicit subset deferring to ADR-149, so 8 items does not make it false; and DC-2's mandate fires at release, not at hold. |
| Edit the runbook `git-data-birth.md` | **Rejected — checked, no change needed.** Its banner defers to ADR-149's list rather than restating it. |
| Remove the `action-required` label from #7003 | **Rejected.** See R5. |
| Record DC-2/DC-3 only in the GitHub comments, skip the ADR | **Rejected.** That is the by-memory failure the brief exists to close; a closed issue's comment is not an artifact #6982's implementer reads. |
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

**No new architectural decision.** This plan **records** two decisions the operator already made,
and amends an existing ADR's checklist to carry one of them.

### ADR

`ADR-149-git-data-host-birth-route-and-readiness-interlock.md` — **amended, not superseded**
(Phase 2). No new ordinal is claimed, so `/ship`'s ADR-Ordinal Collision Gate has nothing to
re-derive and no renumber sweep is possible. Status stays `Accepted`.

### C4 views

**No C4 impact.** Checked against all three of
`knowledge-base/engineering/architecture/diagrams/{model.c4,views.c4,spec.c4}` by enumerating the
change's participants rather than grepping for its noun:

- **External human actors:** none added or changed. The only human is the operator, already
  modelled as the `founder` actor.
- **External systems / vendors:** none added. GitHub Issues is the only external surface touched,
  and the agent→GitHub-issues relationship is already modelled (ADR-138 reaches the same conclusion
  for the SLA cron). Hetzner, Doppler and Sentry are *named in prose* but no relationship to them
  is created, removed, or re-pointed.
- **Containers / data stores:** none. No store is read or written.
- **Actor↔surface access relationships:** unchanged. No ownership, tenancy, or sharing boundary
  moves.

A future engineer reading only the existing ADRs and C4 would not be misled after this ships — the
one architectural fact it adds (the interlock's mandated future replacement) lands *inside*
ADR-149, which is where such a reader already looks.

### Sequencing

None. Both decisions are recorded now; only their *execution* is future-dated, and that execution
belongs to #6982, tracked by ADR-149 items 5 and 8.

---

## Observability

**Skipped, with the reason recorded** (deepen-plan Phase 4.7 checks the section exists or that the
skip is justified). Phase 2.9 fires on Files-to-Edit under `apps/*/server/`, `apps/*/src/`,
`apps/*/infra/`, `plugins/*/scripts/`, or on any new infrastructure surface. This plan's
Files-to-Edit are two `knowledge-base/**.md` files and a comment/message-text-only edit under
`tests/scripts/lib/`. No path matches; no new error path, log call, or failure mode is introduced;
no execution surface changes — the gate's branches, regexes and exit codes are explicitly untouched
(Phase 3). There is nothing to make discoverable.

**No soak / time-gated close criterion** is declared, so §2.9.1 Follow-Through Enrollment does not
fire — #7003 closes on the merge of this change, not after a soak window.

## Encryption Posture

**Skipped.** Phase 2.11 fires on `*.tf`, `supabase/migrations/*.sql`, `cloud-init*.ya?ml`, or
`docker-compose*.ya?ml`, or on prose introducing a persistent store or a new cross-component
connection. This plan introduces neither: no volume, bucket, table, queue, cache, backup target, or
log sink, and no new connection between components. The GitHub calls run over the existing `gh`
client against an already-established, already-disclosed integration.

---

## Sharp Edges

- **A checklist's size is stated in more places than the checklist.** ADR-149 states it three
  times across two files with two different dash characters, and nothing in CI compares them. Before
  adding an item to *any* numbered contract, `grep` for the range forms — both `N-M` and `N–M` —
  across every file that names the artifact. This one cost the first draft of this plan a P0.
- **The DC-2 carve-out is the most fragile sentence in the change.** A reader who meets *"DC-2's
  recommended alternative was falsified by measurement"* and *"DC-2 resolved: do the thing"* in the
  same section, without the carve-out, concludes the operator overruled a measurement. It must state
  *what* was falsified (reading `heartbeat-manifest.ts`, whose `kind: "timer"` is already true) and
  *why it does not reach* the emitter resource (which does not exist yet). AC3 asserts it; do not
  trim it.
- **Never use `awk '/start/,/end/'` to extract the ADR checklist.** The range self-matches its own
  start line and returns the heading only, so a verifier built on it passes against an **empty**
  body. AC4 uses the flag-based form deliberately.
- **Editing a markdown table row: stay inside the cell.** Text past the trailing `|` is discarded by
  GFM, survives in raw markdown, and passes any grep-based AC — it renders as though the edit never
  happened. AC9 is the pipe-count gate for Phase 2.3.
- **`lint-infra-no-human-steps.py` exits 0 over zero files.** Non-existent paths are dropped
  silently. Always assert the `N scanned file(s)` count, not just the exit status (AC11).
- **`gh issue list … index(N)` returns `0`, not empty, when N is first.** Compare against the literal
  string `null`; `-z` and `-eq 0` both invert the check (AC8).
- **Grepping the repo for this plan's own literals self-matches.** Every AC is scoped to a named
  file. If one is ever widened, exclude `knowledge-base/project/{plans,specs}/**` — point-in-time
  records must quote the strings they verify.
- **Do not "fix" the gate's `NOT machine-checked here`.** Checklist item 3 *is* machine-checked — by
  `terraform-target-parity.test.ts`, not by the gate. The word `here` is doing real work. That exact
  substring is also the suite's only assertion on this text, so it must survive Phase 3.
