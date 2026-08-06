# Tasks — recut-runbook `user_data` precondition

Plan: `knowledge-base/project/plans/2026-08-06-fix-registry-userdata-budget-measures-unstripped-render-plan.md`
Branch: `feat-one-shot-7247-zot-crash-loop-recovery` · PR #7303 · Ref #7247 #7287 #7299 #7309 #7310

> **DESCOPED TWICE 2026-08-06.**
>
> 1. The `registry-userdata-budget.sh` fix this branch originally carried duplicated PR #7300,
>    which was already open for the same defect with its implementation complete and its agent
>    review pass applied. (Precisely: #7300 is an OPEN **draft** with `reviews: []` — not GitHub-
>    approved. Duplicating it was wasteful because the work was done, not because it was
>    merge-ready.) Reverted out; see the plan's DESCOPED banner for how the collision was missed.
> 2. The `lint-diagnosis-claims.sh` widening then turned out to be **coupled to #7300 merging**:
>    once it works, it correctly flags `registry-userdata-budget.sh:131` — the message #7300
>    deletes — taking the census to 2 against a baseline of 1 on a BLOCKING check. Split to
>    **#7310** with the measurements attached.
>
> What remains is the recut runbook alone. This PR closes no issue — #7299 belongs to #7300.

---

## Phase 0 — Measurement (done; this is the evidence the rest rests on)

- [x] **0.1** Reproduce the gate's verdict on `main`: `registry-userdata-budget.sh --json` →
      `{"stored_bytes":36404,"headroom":-3636}`, rc=1, message *"#7280's registry_rationale_strip
      is the fix"*.
- [x] **0.2** Confirm the corroborating gate disagrees:
      `bun test plugins/soleur/test/cloud-init-user-data-size.test.ts` → 38 pass / 0 fail. Two
      views of one invariant, opposite verdicts.
- [x] **0.3** Establish the true figure: rendering the expression `zot-registry.tf:451-494`
      actually uses — `base64gzip(replace(templatefile(...), local.registry_rationale_strip, ""))`
      — stores **9,404 B** against a 32,768 B cap (**23,364 B headroom**). The strip was already
      applied; the gate omitted the wrapper.

## Phase 1 — Recut runbook (shipped)

`knowledge-base/engineering/operations/runbooks/registry-luks-recut-6929.md`, §*"And check the
`user_data` budget FIRST"*.

- [x] **1.1** Replace the hard-coded *"36,404 B stored, −3,636 B headroom — OVER CAP"* with the
      command plus a verdict shape and a re-run instruction. The retracted figure survives ONLY
      inside the "superseded measurement" caution, never as a live instruction. The replacement
      states the corrected size as **~9.4 kB**, deliberately imprecise — review measured 9,408 B
      where this session measured 9,404 B on a different terraform build, which is itself the
      argument against quoting one.
- [x] **1.2** Remove the falsified sentence *"#7299 owns the fix (`registry_rationale_strip`, the
      same mechanism #7280 used…)"*. The strip was already applied.
- [x] **1.3** Fix the boundary: the gate fails at `stored_bytes -ge cap`, so `headroom` must be
      **> 0**. The section said `≥ 0`, i.e. exactly `0` would have read as clear and failed.
- [x] **1.4** State the `terraform` prerequisite, and document the **SKIP trap**: with terraform
      absent the script prints `SKIP` and exits **0**, which is indistinguishable from "under cap"
      if the operator reads only `$?`. Verified against both the current script and PR #7300's
      (which hard-fails only when `CI` is set — this runbook is a *local* procedure).
- [x] **1.5** Keep the retracted measurement as an explicit caution, and point at #7299 / PR #7300
      for the gate fix without asserting it has landed.
- [x] **1.6** Do **not** edit `zot-registry.tf` or `cloud-init-registry.yml`. The reasons differ,
      and the original wording here conflated them: `cloud-init-registry.yml` **is** the rendered
      payload, so any byte change there moves `user_data`, which is ForceNew with no
      `ignore_changes` — a destroy/create on a host whose server type is currently unorderable in
      its own datacenter (#7309). A comment in `zot-registry.tf` OUTSIDE the templatefile var map
      does **not** enter `user_data` and arms nothing (demonstrated by #7300, whose `.tf` diff is
      comment-only and whose Terraform Plan check is green). The reason to leave `zot-registry.tf`
      alone is plan R3's: editing that comment block is the most likely trigger for a permissive
      hole in the applied-ness check.

## Phase 2 — ADR-166 diagnosis-claims lint (measured here, SPLIT to #7310)

- [x] **2.1** Add `apps/web-platform/infra` to `DIRS` in `scripts/lint-diagnosis-claims.sh`.
      **Measured: zero new hits**, so the highwater ratchet did not have to be raised.
- [x] **2.2** Prove the widening is live: a fixture message under
      `apps/web-platform/infra/` is flagged (`probe.sh:2`), where before it was not scanned at all.
- [x] **2.3** **Measured falsification of the plan's own AC.** With the scope widened, the verbatim
      offending message was *still* not flagged — "X **is the fix**" asserts a cause by prescribing
      its remedy and matched no `CLAIM` alternative. Added `\bis the (fix|cause)\b`; re-measured at
      zero new hits on the real tree, and the fixture now trips.
- [x] **2.4** `scripts/lint-diagnosis-claims.test.sh` → 11 passed, 0 failed; ratchet unchanged at 1.
- [x] **2.5** **Reverted from this PR.** With both changes in and the gate fix descoped to #7300,
      the lint correctly flags the still-present `registry-userdata-budget.sh:131` — census 2 vs
      baseline 1 — and the lint is BLOCKING via `test-all.sh`'s `scripts` shard into the required
      `test` job. Shipping it before #7300 would red `main`. Split to **#7310**, gated on #7300,
      carrying every measurement above so it is a small job later.

## Phase 3 — Correct the derived claims on the issue tracker (shipped)

- [x] **3.1** `gh issue edit 7287` — precondition (c) said *"currently BREACHED and is a hard
      blocker"* with figures (34,800 / 36,072) no runbook grep covers. Corrected in place with the
      re-measurement, and added *"(c) clearing does not clear #7278 or Hetzner stock."*
- [x] **3.2** Marked the #7277 and #7280 rows of #7287's blocking table **CLEARED** (verified:
      #7277 closed by PR #7290; #7280 merged).
- [x] **3.3** Posted the measurement as a comment on #7287 for the audit trail.
- [x] **3.4** Correct that comment — it describes `strip_applied` / `exit 3`, which belonged to the
      implementation dropped in the descope, not to #7300's.

## Phase 4 — Follow-up filing (net +2, CONCUR-gated)

- [x] **4.1** Filed as **#7309** — the `cpx22` repin decision for `hel1-dc2`. `zot-registry.tf:438-440` records the
      live probe `hel1-dc2 cx23 ✗ cpx22 ✓` — the registry's pinned type is unorderable in its own
      datacenter, so every recreate path fails at the Hetzner API regardless of any other gate.
      Currently documented in #7287's blocking table as *"not closable by any issue"* and owned by
      none. `code-simplicity-reviewer` CONCURRED: 9–11 files / 150–250 lines by the #6967 and
      #6974 precedents, and **+€14.00/mo (3.55×)** — a cost decision, not a rider.

- [x] **4.2** Filed **#7310** — the ADR-166 lint scope widening, gated on #7300 (see 2.5).

## Not filed from this branch

The other four follow-ups the plan proposed (budget-coverage enumerator, `modules/registry-userdata/`
extraction, registry runcmd rehearsal, ADR-096 single-delivery-path amendment) all attach to the
gate work now owned by **#7300**. Filing them from a PR that no longer does that work would inflate
net issue flow against the wrong change. They belong with #7300.
