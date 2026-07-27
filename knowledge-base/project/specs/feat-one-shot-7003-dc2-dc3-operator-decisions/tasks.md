# Tasks — record the DC-2 and DC-3 operator decisions and close #7003

Plan: `knowledge-base/project/plans/2026-07-27-docs-record-dc2-dc3-operator-decisions-plan.md`
Issue: #7003 · Inherits into: #6982 · Amends: ADR-149

> **Do not re-litigate either decision.** Both are the operator's and are final. These tasks record
> them; they do not re-weigh them.

> **The DC-2 mandate is ADR-149 release-checklist item 7, not item 8.** It is a dispatch
> precondition, so it goes *ahead* of the banner-clearing item, which becomes item 8. Appending
> after banner-clearing creates a cycle against the runbook's "clear only when every item is done".

> **Do not create `decision-challenges.md` under this branch's spec dir.** `ship` Phase 2.5 would
> file a duplicate `action-required` issue about the recording of a resolved escalation. If a Taste
> or User-Challenge decision arises, put it in the PR body instead. (Plan R4, AC12.)

## Phase 1 — Record both decisions in `decision-challenges.md`

Target: `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md`

- [ ] 1.0 Re-read the file. Confirm DC-1's heading form is still
      `### RESOLVED 2026-07-27 by the operator — <verdict>` (em dash). Do **not** use the
      `### RESOLVED — <date>:` form from the `feat-one-shot-6425-…` spec.
- [ ] 1.1 Append the header status line (plan Phase 1.1) immediately after the existing
      *"**These are NOT applied** …"* sentence, which is false once all three are resolved.
- [ ] 1.2 Append `(scope: that implementation only — see RESOLVED below)` to DC-2's
      `**That recommendation is falsified by measurement.**` sentence.
- [ ] 1.3 Insert the **DC-2** RESOLVED block verbatim from plan Phase 1.3, after DC-2's
      `**Plan's current disposition:**` paragraph and **before** the `---` separating DC-2 from DC-3.
- [ ] 1.4 Append the **DC-3** RESOLVED block verbatim from plan Phase 1.4 at end of file. Keep both
      the in-line scope marker (*"— for the pre-birth window, which is the window this decision
      governs —"*) and the `> Scope, and why it matters` blockquote. Together they are the R3
      mitigation and AC4 asserts the blockquote.
- [ ] 1.5 Verify **AC1**, **AC2**, **AC3**, and AC4's `<dc>` clauses.

## Phase 2 — Propagate into ADR-149

Target: `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md`

- [ ] 2.0 Re-read `### Interlock release checklist — #6982 inherits this` and confirm it is still a
      7-item numbered list of prose sentences with bolded lead phrases. Mirror that shape — no table,
      no checkboxes, no new heading level.
- [ ] 2.1 Insert the DC-2 mandate as **item 7** (plan Phase 2.1) and renumber the existing
      *"Clear the DO-NOT-DISPATCH banner"* item to **8**, adding its terminal note. Confirm first
      that nothing outside the ADR references items 7 or 8 by number and that `Residual 2`'s
      `item 5` reference is unaffected.
- [ ] 2.2 Extend **item 5** with DC-3's two mechanical constraints (plan Phase 2.2), preserving every
      existing word. State the #6415 precedent **accurately** — it routed
      `hcloud_server_network.registry` through a `local` that still holds the literal, so DC-3's
      mandate goes one step further by reading the resource attribute.
- [ ] 2.3 Amend the existing `Include \`doppler_secret.git_data_ssh_host\`` row in
      `## Alternatives considered`: dissent → **upheld by the operator on 2026-07-27**, and add the
      full artifact path plus `#6989` so the dissent is resolvable from the ADR side. Edit **inside
      the verdict cell** — text past the trailing `|` is discarded by GFM while still passing a
      grep. Do **not** add a new row for the interlock mechanism (item 7 is its home).
- [ ] 2.4 At anchor `Items 2–7 are not machine-checked at all` (**en dash**, U+2013), replace the
      range with `The remaining items`. Third count-mirror, in the file already being edited.
- [ ] 2.5 In `### The birth-readiness interlock`, append the interim clause (plan Phase 2.5) after
      the *"That choice is load-bearing"* passage. Without it the Decision section still presents the
      sentinel as permanent three headings above an item mandating its deletion.
- [ ] 2.6 Add `- **Amended by:** #7003 (operator decisions DC-2, DC-3 — 2026-07-27)` to the header
      bullets. ADR-149 has no YAML frontmatter, so the ordinal guard is unaffected.
- [ ] 2.7 Verify **AC5**, **AC6**, **AC8**, **AC10**, and AC4's `<adr>` clause.

## Phase 3 — The gate: add the mandate where it is actionable, stop stating counts

Target: `tests/scripts/lib/git-data-birth-readiness-gate.sh` — **comments and message text only.**
No branch, regex, or exit code.

- [ ] 3.1 Header block, anchor `RELEASE CONDITION — the checklist #6982 inherits`: insert the new
      condition as item 7 and renumber banner-clearing to 8 (matching the ADR), then change
      `It cannot check (2)-(7)` → `It cannot check the remaining items`.
- [ ] 3.2 **HOLD** message, anchor `TO RELEASE THIS INTERLOCK`: add a 5th item — *"Replace this
      gate's own mechanism with a direct assertion on the emitter resource and delete this sentinel
      (ADR-149 release-checklist item 7; operator decision 2026-07-27, DC-2)."* This is a
      `<<'HOLD'` quoted heredoc, so there is no interpolation risk. HOLD is what a dispatch prints
      today — it is where the #6982 implementer reads it *before* doing the work.
- [ ] 3.3 **RELEASED** message, anchor `Items 2-7 (Doppler scope reachability` (**ASCII** hyphen
      here): replace the range **and its six-phrase enumeration** with the universally-quantified
      sentence from plan Phase 3.3. This edit is inside a double-quoted `echo` — the replacement text
      must contain no `$`, backtick, or unescaped `"`.
- [ ] 3.4 Confirm the literal `NOT machine-checked` survives — it is the suite's only assertion on
      this text (`test-git-data-birth-readiness-gate.sh`, anchor
      `the RELEASE states what it did NOT check`).
- [ ] 3.5 Verify **AC7**, **AC9**, and run AC11's gate suite.

## Phase 4 — GitHub: **post-merge**, agent-executed

**Do not run any of Phase 4 before the PR merges.** These five calls are irreversible and the local
change is not; an abandoned PR would leave #7003 closed with nothing on `main`, and ADR-138's SLA
cron cannot reopen it (a human touch vetoes its auto-close). The abandonment path must be a no-op.

Write each body file in one Bash call; invoke `gh` in the **next** call. Before each comment,
pre-check for its marker string and skip if present — a retried call that landed must not double-post.

- [ ] 4.1 `gh issue edit 7003 --body-file <path>` — rewrite `## DC-2 — … still open` and
      `## DC-3 — … still open` to DC-1's in-body form (`## DC-N — RESOLVED by the operator on
      2026-07-27`) and replace the `**Open question for the operator:**` paragraph with the decision
      plus the ADR-149 item pointers (items 7 and 5).
- [ ] 4.2 `gh issue comment 7003 --body-file <path>` — both RESOLVED blocks in full, a pointer to the
      canonical artifact, and a closing line naming ADR-149 items 7 and 5. State explicitly that
      DC-3's question was *whether to reverse the cut*, since the body poses no explicit DC-3
      question.
- [ ] 4.3 `gh issue close 7003` — reason `completed` (the default), **not** `not-planned`.
- [ ] 4.4 `gh issue edit 6982 --body-file <path>` — append two checkboxes to `## Items` (the DC-2
      interlock replacement; `doppler_secret.git_data_ssh_host` single-sourced from
      `hcloud_server_network.git_data.ip` with its `OPERATOR_APPLIED_EXCLUSIONS` entry in the same
      change) and one line in `## Re-eval trigger` pointing at ADR-149's release checklist. The body
      currently never names ADR-149.
- [ ] 4.5 `gh issue comment 6982 --body-file <path>` — **self-contained.** Carries the DC-2 mandate
      (item 7), the DC-3 constraints (item 5), and the routing rule surfaced during research: a
      git-data address goes in `OPERATOR_APPLIED_EXCLUSIONS` **or** in the per-PR `-target` set,
      never neither (ADR-103). Item 3's *"all three"* enumeration covers only the target branch, and
      following it for a resource on the exclusion branch reproduces the wedge DC-3 prevents.
- [ ] 4.6 Verify **AC14**. Use `gh issue list --label` (List API), never `--search`. Compare the
      `index(7003)` result against the literal string `null` — it returns `0` today.
- [ ] 4.7 Verify **AC15** — re-run AC1, AC5, AC7, AC9, AC11 against merged `main`.

## Phase 5 — Artifacts, suites, commit (runs BEFORE Phase 4)

- [ ] 5.1 Run `bash tests/scripts/test-git-data-birth-readiness-gate.sh`; require exit 0, the output
      `, 0 failed ===` (leading comma — bare `0 failed` matches `10 failed`), and a live-file note
      still reading `HOLD`.
- [ ] 5.2 Run `python3 scripts/lint-infra-no-human-steps.py` over the ADR, the decision-challenges
      file, this plan, and this tasks file; require exit 0 **and** `4 scanned file(s)` in the output.
- [ ] 5.3 Verify **AC12** — no path under `apps/` in the diff, and no `decision-challenges.md` under
      this branch's spec dir.
- [ ] 5.4 Commit with a `docs(7003):` prefix. PR body uses **`Ref #7003`**, never `Closes #7003`
      (**AC13**) — auto-closing at merge would discharge the escalation before Phase 4 runs.
- [ ] 5.5 Merge, then execute Phase 4.
