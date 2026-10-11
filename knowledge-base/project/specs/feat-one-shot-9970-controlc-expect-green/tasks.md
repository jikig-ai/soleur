# Tasks — fix: provisioner-parity mutation battery control-C to expect_green (#9970)

Plan: `knowledge-base/project/plans/2026-10-11-fix-controlc-mutation-row-expect-green-plan.md`
Issue: #9970 (Closes)

Scope guard: edit ONLY `apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh`.
Do NOT modify `apps/web-platform/infra/web-host-provisioner-parity.test.sh`. Do NOT address the
`cloud-init-inngest-bootstrap` pin drift (tracked separately).

## Phase 0 — Preconditions

- [x] 0.1 `gh issue view 9970 --json state` — confirm OPEN (this PR closes it).
- [x] 0.2 `git log --oneline origin/main -- apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh apps/web-platform/infra/web-host-provisioner-parity.test.sh | head -5` — re-read the control-C block and `_norm` if either file moved since planning.

## Phase 1 — Battery edits (one file)

- [x] 1.1 Rewrite the comment block above `expect_red "control-C …"` (the
  `Terraform identifiers legally contain uppercase and hyphens. … #9860.)` block) to describe
  post-normalization semantics: `_norm()` (lower + hyphen→underscore) at the classification
  boundary makes `Cosign-Trusted_Root` and `cosign_trusted_root` one identity — the row pins
  swept+justified transparency; deleting `_norm` re-breaks via `uncovered` + `stale`, narrowing
  the `([^"]+)` name capture to `[a-z_0-9]+` re-breaks via `stale` alone. Do not quote the retired
  anchor `Cosign-Trusted_Root@web-2` in the comment.
- [x] 1.2 Flip the row to `expect_green "control-C (uppercase/hyphen rename is swept by the
  classification)" server.tf '<same mutator>'` — three args, drop the expected-anchor; mutator
  verbatim.
- [x] 1.3 Insert sibling arm immediately after, with its own short comment (normalization must not
  swallow detection — a normalized-unique rename stays swept but loses its ONLY_JUSTIFIED key):

  ```bash
  expect_red "M4j (§1: a normalized-unique rename is uncovered+stale)" server.tf \
    "uncovered=['cosign_trusted_root_v2@web-2']" '
  old = "resource \"terraform_data\" \"cosign_trusted_root\" {"
  assert old in s
  s = s.replace(old, "resource \"terraform_data\" \"cosign_trusted_root_v2\" {", 1)
  '
  ```

- [x] 1.4 Update the `FLOOR` derivation comment — amended at review: `+1 net #9970:
  control-C moved to expect_green (-1), M4j+M4k added (+2), control-D is a green
  control (+0)`; `FLOOR` bumped 57→58 to keep the running tally consistent (still
  ~18 below the ~76 landed count).

## Phase 2 — Verification

- [x] 2.1 `bash -n apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` — syntax clean.
- [x] 2.2 `bash apps/web-platform/infra/web-host-provisioner-parity-mutation.test.sh` — suite green:
  `0 failed`, `[ok] control-C`, `[ok] M4j` present. (Full suite takes several minutes; do not
  background-poll — run it in the foreground per `hr-monitor-not-run-in-background-for-polling`.)
- [x] 2.3 AC sweep — every item in the plan's `## Acceptance Criteria`, including
  `git diff --quiet origin/main...HEAD -- apps/web-platform/infra/web-host-provisioner-parity.test.sh`
  (guard untouched) and `grep -n '^FLOOR='` = `FLOOR=58` (bumped per fix-round
  recommendation to keep the tally convention self-consistent).
- [x] 2.4 PR body: `Closes #9970` in body (not title) + `## Changelog` section.
