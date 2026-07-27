# Tasks — record the DC-2 and DC-3 operator decisions and close #7003

Plan: `knowledge-base/project/plans/2026-07-27-docs-record-dc2-dc3-operator-decisions-plan.md`
Issue: #7003 · Inherits into: #6982 · Amends: ADR-149

> **Do not re-litigate either decision.** Both are the operator's and are final. These tasks
> record them; they do not re-weigh them.

> **Do not create `decision-challenges.md` under this branch's spec dir.** `ship` Phase 2.5 would
> file a duplicate `action-required` issue about the recording of a resolved escalation. If a
> Taste or User-Challenge decision arises, put it in the PR body instead. (Plan R3, AC10.)

## Phase 1 — Record both decisions in `decision-challenges.md`

Target: `knowledge-base/project/specs/feat-one-shot-6977-git-data-birth-route/decision-challenges.md`

- [ ] 1.1 Re-read the file and confirm DC-1's heading form is still
      `### RESOLVED 2026-07-27 by the operator — <verdict>` (em dash). Do **not** use the
      `### RESOLVED — <date>:` form from the `feat-one-shot-6425-…` spec.
- [ ] 1.2 Insert the **DC-2** RESOLVED block verbatim from plan Phase 1.1, after DC-2's
      `**Plan's current disposition:**` paragraph and **before** the `---` separating DC-2 from DC-3.
- [ ] 1.3 Append the **DC-3** RESOLVED block verbatim from plan Phase 1.2 at end of file.
      Keep the `> Scope note` blockquote — it is the R2 mitigation and AC3 asserts it.
- [ ] 1.4 Verify **AC1**, **AC2**, **AC3**.

## Phase 2 — Propagate into ADR-149

Target: `knowledge-base/engineering/architecture/decisions/ADR-149-git-data-host-birth-route-and-readiness-interlock.md`

- [ ] 2.0 Re-read `### Interlock release checklist — #6982 inherits this` and confirm it is still a
      7-item numbered list of prose sentences with bolded lead phrases. Mirror that shape — no
      table, no checkboxes, no new heading level.
- [ ] 2.1 Append **item 8** (plan Phase 2.1) **immediately after item 7** and **before** the
      paragraph beginning `**The gate mechanically enforces only the THREADING half of item 1**`.
      Placement matters: after that paragraph breaks the list and AC4's count cannot tell them apart.
- [ ] 2.2 Extend **item 5** with DC-3's two mechanical constraints (plan Phase 2.2), preserving
      every existing word. State the #6415 precedent **accurately** — it routed
      `hcloud_server_network.registry` through a `local` that still holds the literal, so DC-3's
      mandate goes one step further by reading the resource attribute.
- [ ] 2.3 Amend the existing `Include \`doppler_secret.git_data_ssh_host\`` row in
      `## Alternatives considered`: dissent → **upheld by the operator on 2026-07-27**. Edit
      **inside the verdict cell** — text past the trailing `|` is discarded by GFM while still
      passing a grep. Do **not** add a new row for the interlock mechanism (item 8 is its home).
- [ ] 2.4 At content anchor `Items 2–7 are not machine-checked at all` (**en dash**, U+2013),
      replace the range with `The remaining items`. This is the third count-mirror and it lives in
      the file being edited.
- [ ] 2.5 Verify **AC4**, **AC5**, **AC9**.

## Phase 3 — Delete the gate's counts rather than increment them

Target: `tests/scripts/lib/git-data-birth-readiness-gate.sh` — **comments and message text only.**
Do not touch any branch, regex, or exit code.

- [ ] 3.1 Header block, anchor `RELEASE CONDITION — the checklist #6982 inherits`: append an 8th
      bullet (*"this gate's own mechanism is replaced by a direct assertion on the emitter resource,
      and this text sentinel is deleted (operator decision 2026-07-27, DC-2);"*), then change
      `It cannot check (2)-(7)` → `It cannot check the remaining items`.
- [ ] 3.2 RELEASED message, anchor `Items 2-7 (Doppler scope reachability` (**ASCII** hyphen here):
      replace the range with `The REMAINING checklist items`, keep the six-phrase enumeration, and
      extend it with `and this gate's own mandated replacement by a direct emitter-resource
      assertion (ADR-149 item 8)`.
- [ ] 3.3 Confirm the literal `NOT machine-checked` survives — it is the suite's only assertion on
      this text (`test-git-data-birth-readiness-gate.sh`, anchor
      `the RELEASE states what it did NOT check`).
- [ ] 3.4 Do **not** touch the HOLD message's abbreviated 1–4 list.
- [ ] 3.5 Verify **AC6**, **AC7**, and run **AC11**'s gate suite.

## Phase 4 — GitHub: comment, close, verify

Order is load-bearing. Write each body file in one Bash call; invoke `gh` in the **next** call.

- [ ] 4.1 Write the #7003 comment body to the session scratchpad: both RESOLVED blocks in full, a
      pointer to the canonical artifact, and a closing line naming ADR-149 items 8 and 5.
- [ ] 4.2 `gh issue comment 7003 --body-file <path>`.
- [ ] 4.3 `gh issue close 7003` (reason `completed`, the default — **not** `not-planned`).
- [ ] 4.4 Write the #6982 comment body — **self-contained**, so the implementer never needs to open
      a closed issue: the DC-2 mandate (assert the emitter resource, delete the sentinel,
      mandatory), the DC-3 single-source constraint (`hcloud_server_network.git_data.ip`, never a
      fresh `10.0.1.20` literal) plus the same-change `OPERATOR_APPLIED_EXCLUSIONS` requirement,
      and pointers to ADR-149 items 8 and 5.
- [ ] 4.5 `gh issue comment 6982 --body-file <path>`.
- [ ] 4.6 Verify **AC8**. Use `gh issue list --label` (List API), never `--search`. Compare the
      `index(7003)` result against the literal string `null` — it returns `0` today.

## Phase 5 — Artifacts, suites, commit

- [ ] 5.1 Run `bash tests/scripts/test-git-data-birth-readiness-gate.sh`; require exit 0, the
      output `, 0 failed ===` (leading comma — bare `0 failed` matches `10 failed`), and a live-file
      note still reading `HOLD`.
- [ ] 5.2 Run `python3 scripts/lint-infra-no-human-steps.py` over the ADR, the
      decision-challenges file, this plan, and this tasks file; require exit 0 **and**
      `4 scanned file(s)` in the output.
- [ ] 5.3 Verify **AC10** — no path under `apps/` in the diff, and no `decision-challenges.md`
      under this branch's spec dir.
- [ ] 5.4 Commit with a `docs(7003):` prefix. Push.
