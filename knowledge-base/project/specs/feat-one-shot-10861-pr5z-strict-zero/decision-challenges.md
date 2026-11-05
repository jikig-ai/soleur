# Decision log: feat-one-shot-10861-pr5z-strict-zero (S4 index completion PR5z, strict zero, Ref #10861, Ref #10448)

Planned 2026-11-05 on worktree HEAD `196a6b38ed` (init commit on `f06b595420`, the PR5d merge). No Agent tool in this run — every technical row is `pending - assumed` per the technical-ruling-delegation rule; a reviewer with the Agent tool may settle or escalate each to `soleur:engineering:cto`.

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| Reason token for the re-added-baseline verdict | technical | pending - assumed: `baseline-reintroduced` — fits the closed `baseline-*` token grammar (`baseline-deleted`, `baseline-dup`, `baseline-order`); ADR-276 item 5(d) fixes the semantics (exit 1 unconditionally), the token name is the implementer's inside that grammar |
| Keep or retire the present/present `--baseline` machinery (`stale-line`, `baseline-dup`, `baseline-order`, `grown`) and their suite rows | technical | pending - assumed: KEEP — task 4.4's own recommendation ("the cheaper call"); the arms stay reachable whenever a HEAD baseline exists against a base that has one (custom `--baseline`, an old `--base`, the merge window before this PR lands); retiring them shrinks `--baseline` coverage for zero gain |
| Placement of the new arm in `ratchet_run`'s findings order | technical | pending - assumed: standalone `if head_text is not None and base_text is None:` immediately BEFORE the `if new and head_text is None and base_text is not None:` block — marker names `baseline-reintroduced`, `elif new:` still prints new-pair detail, `stale-line`/dup/order may co-fire on a malformed re-add |
| How `ratchet-adoption-refused` (:4889, widens `grown`'s guard to fire on base-absent) stays killed | technical | pending - assumed: the reintroduced row also asserts `! grep -q '^grown' <<<"$ROUT"` — the marker alone cannot see the mutant (reintroduced precedes grown in findings order) |
| #12128 coordination while `origin/main` is red (`stale-accept live=3`, #12110) | technical | pending - assumed: never duplicate the in-flight repin — MERGED → rebase; OPEN/progressing → sequence after it, or absorb only the residual it does not cover (delete stale rows + classify the 3 `components.test.ts` drift pairs as mention-class accepts) recorded in `receipts/drift-disposition.tsv` per the runbook's repair-owner rule |
| `s4-drain` label release ordering | technical | pending - assumed: release post-merge only — releasing pre-merge un-claims mid-slice; post-merge the probe floor falls back to sentinel #11226, the conservative direction (longer window) |
| Same-commit set for the deletion | technical | pending - assumed: `git rm` + the arm + the test rework + `.gitattributes` + the 42 orphaned accept rows in ONE commit — the task couples arm and deletion, and the rows go stale (`path-untracked`) the instant the path is untracked |
| `ci.yml` step name `Ratchet the audit against the committed baseline` | technical | pending - assumed: untouched — the observation probe keys on the literal (`STEP=` at `ratchet-observation-window-10865.sh:88`); renaming it breaks the probe |
| Brand threshold | taste | `none` — CI-check script + fixtures + docs only; no user-facing or regulated surface (scope-out reason recorded in the plan) |
