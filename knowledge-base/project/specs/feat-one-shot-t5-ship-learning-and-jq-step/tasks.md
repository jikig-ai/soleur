# Tasks — feat-one-shot-t5-ship-learning-and-jq-step

Derived from
[`knowledge-base/project/plans/2026-08-19-chore-t5-ship-learning-and-jq-step-plan.md`](../../plans/2026-08-19-chore-t5-ship-learning-and-jq-step-plan.md).

**Two deviations from the brief, both review-driven and both filed as challenges — do not silently
revert them, and do not silently widen further:**

- **§D1** — deliverable A is re-scoped: the `/compound` obligation was already discharged inside
  `45ea9f7e9`. The learning file's subject is the **CI package-install-hang class**, not a T5 restatement.
- **§D2/§D3** — deliverable B **replaces** the step (rather than deleting it) at **three** sites
  (rather than one). The brief pre-authorized widening *"unless the review phase argues otherwise."*

**No issue is closed by this PR.** 7572, 7574 and 7613 are context and must stay open.

---

## Phase 0 — Preconditions (re-derive; inherit no number from the plan)

- [x] 0.1 `git fetch origin main` — a stale fetch moves the three-dot merge base used by AC2/AC4/AC9.
- [x] 0.2 `git show --name-only --format='' 45ea9f7e9 | grep -c 'project/learnings/'` → `2`.
- [x] 0.3 Confirm 7572 / 7574 / 7613 still `OPEN`. **If any closed: do not halt** — record the new
      state in the PR body and continue. Only §D1's context framing changes, neither deliverable does.
- [x] 0.4 Re-anchor targets by content, not line number:
      `grep -n 'apt-get install -y -qq jq' .github/workflows/skill-security-scan-*.yml` → **3 hits**
      (pr-trailer, corpus, postmerge).
- [x] 0.5 Re-measure the preinstalled-jq evidence **excluding `gh api --jq` sites** (gh embeds gojq
      and proves nothing about the `jq` binary). Record the write-time figure.
- [x] 0.6 `command -v actionlint` — confirm present before relying on it in 1.4/AC3.

## Phase 1 — Deliverable B: replace the step at three sites

Replacement block (identical at each site):

```yaml
      - name: Assert jq present (runner-image dependency — no install, no network)
        run: jq --version
```

- [x] 1.1 `.github/workflows/skill-security-scan-pr-trailer.yml` — replace the `Install jq` step.
- [x] 1.2 `.github/workflows/skill-security-scan-corpus.yml` — same replacement.
- [x] 1.3 `.github/workflows/skill-security-scan-postmerge.yml` — same replacement.
- [x] 1.4 **Grep after each write to confirm the edit landed.** `.github/workflows/*.yml` edits have
      been silently rejected by a PreToolUse hook before, returning reminder text without applying.
      Do not trust the Edit tool's return value.
- [x] 1.5 `actionlint` on all three files → **no new finding** (amended, same reason as AC3: `origin/main`
      already exits 1 on 11 pre-existing shellcheck findings in untouched scan steps, so "exit 0" was
      unsatisfiable). Measured base 11 = head 11, `diff` empty, none citing the assertion step.
- [x] 1.6 Confirm untouched in pr-trailer: the six `jq` call sites, both `set -euo pipefail` anchors in
      the jq-consuming steps, and the `name: skill-security-scan PR gate` line (DO-NOT-RENAME).

## Phase 2 — Deliverable A: the learning file

- [x] 2.1 Create
      `knowledge-base/project/learnings/2026-08-19-the-install-step-that-hung-was-installing-something-already-there.md`.
      **Slug is pinned** — it feeds `ship` Phase 2's compound-detection glob; an unpinned slug risks
      ship auto-invoking `compound` and writing a *second* learning file, breaking AC8.
- [x] 2.2 Subject: the CI package-install-hang class only. **Do not bundle** the
      stale-obligation meta-finding — that goes to `decision-challenges.md` and the PR body.
- [x] 2.3 Cross-reference (do not restate): the two T5 learning files by filename, `ADR-188`, and
      `knowledge-base/project/specs/archive/20260816-203421-feat-one-shot-7291-t5-mutation-network-flake/tasks.md` §5.4.
- [x] 2.4 Assert no closing keyword for 7572 / 7574 / 7613 — **including in commit messages**.
- [x] 2.5 Append the §D1 and §D2/§D3 challenges to
      `knowledge-base/project/specs/feat-one-shot-t5-ship-learning-and-jq-step/decision-challenges.md`.
      Note: `ship` Phase 6 renders this into the PR body **and files an `action-required` issue** —
      an intended, declared side effect.

## Phase 3 — Verification (all pre-merge)

`grep -c` exits **1** when the count is 0 — wrap every zero-expecting check as
`test "$(… | grep -c … || true)" -eq 0`.

- [x] 3.1 **AC1** — no `apt-get` remains at any of the three sites.
- [x] 3.2 **AC2** — `git diff --numstat origin/main...HEAD -- <pr-trailer>` → `2	2	<path>`;
      `test "$(grep -c 'jq' <pr-trailer>)" -eq 8` (six call sites + the assertion step's two lines).
- [x] 3.3 **AC3 (amended at /work)** — `actionlint` adds **no new finding**: its finding set at HEAD
      is byte-identical to the same command against `git show origin/main:<path>`. The original
      "exits 0" wording was unsatisfiable — `origin/main` already exits 1 with 11 pre-existing
      shellcheck findings in untouched scan steps. Measured 11 = 11, `diff` empty, none cite the
      assertion step. See the plan's AC3 amendment note.
- [x] 3.4 **AC4** — `git diff --name-only origin/main...HEAD -- .github/workflows/` returns exactly
      the three intended files. *Anti-widening gate: changing scope means editing this AC.*
- [x] 3.5 **AC5** — both jq-consuming steps still open with `set -euo pipefail` (assert the anchors,
      not a bare count; the file carries three occurrences total).
- [ ] 3.6 **AC6 (scope corrected at review)** — the `skill-security-scan PR gate` run on this PR's
      head shows `Assert jq present` with conclusion `success` and `jq --version` output in the log.
      **This is the real proof** — the pre-existing jq steps are `if:`-guarded on
      `no_new_skills == 'false'` and never run on this PR.
      **Covers 1 of the 3 edited workflows, not 3.** The structural-enumeration seat resolved the
      triggers: only `pr-trailer` runs here (`pull_request`, no `paths:`). `corpus` carries a
      6-pattern `paths:` filter matching none of this PR's 8 files, and `postmerge` has no PR
      trigger at all (`push: branches: [main]`). Their assertions inherit this evidence only via the
      separate premise that all three `runs-on: ubuntu-latest` jobs draw the same image. AC7 closes
      `postmerge` post-merge; `corpus` is first exercised by its own `push:main` arm.
- [ ] 3.7 **AC7** — post-merge, the `push:main` `skill-security-scan-postmerge.yml` run shows its
      `Assert jq present` step succeeding (`wg-after-merging-a-pr-that-adds-or-modifies` honoured;
      `gh workflow run` is inoperable on pr-trailer — no `workflow_dispatch`).
- [x] 3.8 **AC8** — exactly one new top-level learning file, pinned slug, carrying all four cross-references.
- [x] 3.9 **AC9** — `bash plugins/soleur/skills/ship/scripts/auto-close-scan.sh <body-file>` clean for
      7572/7574/7613, **and** the same scan over `git log origin/main..HEAD --format=%B`. Commit
      messages are load-bearing: this repo squash-merges and the parser is negation-blind.
- [ ] 3.10 **AC10** — PR body records the seven-site inventory, the §D2/§D3 deviations, and the §D4
      tracking issues.

## Phase 4 — Tracking (file, do not fix)

- [x] 4.1 **NOT FILED — `code-simplicity-reviewer` DISSENTed, and the dissent is right.** The factual
      claim was confirmed (`ship` Phase 2 probes with a `git log --since="1 week ago"` over
      `learnings/` and persists nothing; no `obligation` token exists in `ship/SKILL.md` or
      `compound/SKILL.md`). But the proposed tracker is a mechanism whose requirement is already met:
      the obligation is derivable from git at any time via one command, and a ledger started today
      could not answer for merges that predate it — a deferral target that cannot reach the defect.
      What failed was inferring the state instead of probing it. Resolved **inline** as a section in
      the learning file (§"the brief asserted an obligation instead of probing for one"), ~25 lines
      in a file already in the diff: 0 new files, no workflow files touched, AC4 preserved.
- [x] 4.2 **FILED as #7629** (CONCUR). Two **pre-existing P1 fail-open swallows** in
      `skill-security-scan-pr-trailer.yml` — out of scope here, each needs its own cycle:
      - `:73-74` — `git diff … || true` conflates "git diff failed" with "nothing added" → both scan
        steps skip → green with zero coverage.
      - `:138` — a scanner failure collapses to `verdict=UNKNOWN`, compared against nothing, so
        `fail=0` and the gate passes. Compounded by `run-scan.sh:8` claiming *"Exit code: 0 always
        (advisory)"* while `:10` sets `set -euo pipefail` — the comment is false.
- [x] 4.3 Confirm 7572, 7574, 7613 are still OPEN and that neither new issue closes them.
