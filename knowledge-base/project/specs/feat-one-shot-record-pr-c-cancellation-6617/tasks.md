# Tasks: Record the operator's cancellation of PR C

Plan: `knowledge-base/project/plans/2026-07-20-docs-record-pr-c-cancellation-inngest-liveness-marker-plan.md`
Issue: #6617 (`Ref`, **never** a closing keyword — the tracking issue must stay OPEN for its
follow-through sweeper)

Docs-only. One PR. No code, workflow, script, or Terraform.

> ## READ THIS FIRST — two spec directories differ only by suffix
>
> - **EDIT TARGET:** `knowledge-base/project/specs/feat-one-shot-6617-inngest-liveness-marker-registry-probe/`
> - **THIS FILE lives in:** `knowledge-base/project/specs/feat-one-shot-record-pr-c-cancellation-6617/`
>
> Both end in `6617`. Writing the cancellation banner into *this* directory produces a
> correct-looking diff that records nothing. **AC4 is the only check that catches it.**

---

## Phase 0: Preconditions

- [x] 0.1 Confirm branch is `feat-one-shot-record-pr-c-cancellation-6617` (**not** `main`).
- [x] 0.2 Read all four target files in full before editing
      (`hr-always-read-a-file-before-editing-it`).
- [x] 0.3 Re-measure the PR C checkbox baseline — must still be **46**:
      `sed -n '/^## PR C/,$p' <target>/tasks.md | grep -cE '^\s*- \[[ x~]\]'`
      If it differs, the file changed under the plan — stop and reconcile.
- [x] 0.4 Confirm #6617 is OPEN and must remain OPEN.
- [x] 0.5 Confirm ADR-100 still contains none of `sdk_url` / `backend_is_prod` / `registry_count`
      (AC4's premise — ADR-100 must end up untouched).

## Phase 1: `tasks.md` (the target spec)

- [x] 1.1 Cancellation banner immediately after `## PR C` — must contain `CANCELLED`, `2026-07-20`,
      `operator`; attribute the decision to the operator; point to `decision-challenges.md`.
      **No checkbox in the banner** (AC3 counts checkboxes to EOF).
- [x] 1.2 Append `— CANCELLED (2026-07-20)` to each of the seven headings `### Phase C0:` … `C6:`.
- [x] 1.3 Delete or reword **no** phase body. The bodies are the design record.
- [x] 1.4 Close out `B4.2` and `B4.2.b` → `[x]`; record `op=doublefire-probe` returned **ZERO runs**
      in run `29748606817`.
- [x] 1.5 Reconcile `B4.3` — its body ends *"The doublefire verdict remains unrecorded pending
      B4.2.b."*, which 1.4 falsifies. Record that the verdict is now in, and that B4.3's discipline
      (never record a verdict ahead of the read) was **honoured** — the read came first.

## Phase 2: `session-state.md`

- [x] 2.1 Append a closing entry: the cancellation, the operator as its author, the date, the four
      measures, the CANCEL-vs-HOLD argument, the `sdk_url` note, the four carry-forwards.
- [x] 2.2 State that the registry-alone caveat is **discharged** by run `29748606817`; record the
      verbatim annotation and that the read was taken from `main` (sha `898de92e4`) after #6748
      merged — i.e. against the shipped fix, which is what makes it a valid answer to B4.2.b.
- [x] 2.3 Refer to the merged work as **"PR A + PR B, merged together as #6748"** (commit
      `1d4208f44`). Never "PR A and PR B were merged" — there is only one merge commit.
- [x] 2.4 Add a supersede pointer under `### Outstanding`. **Insert only — delete nothing.**
- [x] 2.5 Record that cancelling PR C dissolves the #6348 stranding risk.
- [x] 2.6 Use the `apply_target=inngest-host-replace` form. Do not rewrite the pre-existing
      `apply_target=inngest-host` at `:50`; just do not propagate it.

## Phase 3: `decision-challenges.md`

- [x] 3.1 **Append** a follow-on ruling under the existing `## Operator Ruling — 2026-07-20`.
- [x] 3.2 Do not rewrite, reword, or reorder the original ruling. Diff must be pure-append.
- [x] 3.3 State the reversal plainly: the original said *"PR C: HELD, not cancelled."* — the
      follow-on supersedes it to **CANCELLED**, and says why the earlier condition (read PR B's
      probe output first) is now satisfied.
- [x] 3.4 Record that the standing #6348 risk the original ruling carried is **dissolved**.

## Phase 4: the original plan file

- [x] 4.1 Status line under `# PR C — marker discriminators + delivery` (`:331`) marking it
      CANCELLED (2026-07-20, operator), pointing to `decision-challenges.md`.
- [x] 4.2 Correct the **three-line** `# Post-C contract` comment so it no longer reads as a pending
      instruction to promote the contract "when C ships".
- [x] 4.3 Do not otherwise modify PR C's design body.

## Phase 5: Verification

- [x] 5.1 Run AC1–AC9.
- [x] 5.2 `git diff --name-only main...HEAD | sort` — confirm the exact seven-path set (AC4).
- [x] 5.3 Confirm zero GitHub issues were filed and zero issue states altered.
- [x] 5.4 Confirm no closing keyword is bound to #6617 in the commit message or PR body, and that
      `Closes #6295` is not quoted verbatim into the PR body (#6295 is already closed by #6748).

## Phase 6: Post-merge

- [ ] 6.1 `gh issue view 6617 --json state` → **OPEN** (AC10).
