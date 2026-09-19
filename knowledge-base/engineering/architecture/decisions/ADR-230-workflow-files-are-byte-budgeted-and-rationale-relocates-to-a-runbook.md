# ADR-230: Workflow files are byte-budgeted at 490,000 bytes, and job rationale relocates to a runbook

- **Date:** 2026-09-19

## Status

Accepted.

## Context

GitHub does not start a run for a workflow file above its per-file limit, and
it does so with no message (zero jobs; "This run likely failed because of a
workflow file issue"). PR #8312 (`f64b0ebc2`, 2026-09-19) pushed
`.github/workflows/apply-web-platform-infra.yml` over it by adding ~3 KB of
comment prose; every run after it — including the operator-authorized
`inngest-host-replace` dispatch for #8294 — was a zero-job failure (#8361).
The measured bracket that pins the limit at 512,000 bytes lives in the gate's
own header, `plugins/soleur/test/workflow-file-size.test.ts`.

The file is this repository's canonical apply boundary
(`hr-all-infrastructure-provisioning-servers`) and had grown ~1.5 KB per commit
over its previous 12 commits, almost all of it job-header rationale: 246,482 of
its 513,306 bytes were comment lines.

ADR-152 faced the same shape on `cloud-init` payloads (Hetzner's 32,768-byte
`user_data` cap) and chose strip-at-render, explicitly REJECTING relocation of
line-adjacent rationale ("comment-freeze") because it divorces a comment from
the line it explains. That option is unavailable here: GitHub reads the
committed file, so there is no render step to strip at.

## Decision

1. **Every `.github/workflows/*.yml` / `*.yaml` file is gated at 490,000
   bytes** by `plugins/soleur/test/workflow-file-size.test.ts`, which runs in
   the always-on `test-bun` shard and therefore in the required `test` context
   on every PR. The gate constant is pinned at least 20,000 bytes under a
   `GITHUB_WORKFLOW_FILE_LIMIT_BYTES = 512_000` constant, so weakening it is a
   two-constant edit. The walk is checked for totality against `git ls-files`,
   so a narrowed or truncated enumeration reds rather than passing vacuously.

2. **Job-header rationale that no test anchors on relocates to
   `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`**,
   whose preamble is the format contract (one section per job id, first line
   plus test-anchored lines plus a `# Rationale: <runbook> §<job_id>` pointer kept in
   the workflow).

3. **Relocation is the interim; the structural fix is a split.** The
   per-target dispatch jobs (host replaces, recuts, migrations) belong in
   dedicated workflows, as `workspaces-luks-cutover.yml` already is. That is
   tracked separately (see the deferral issue filed from PR #8362) and is the
   remedy the next time the gate trips, not another relocation round.

## Consequences

- A comment-only PR can no longer take the apply boundary offline: the gate
  names the file, the size, the overage and the precedent runbook.
- Readers of the workflow see a first line and a pointer where they used to
  see the essay; the essay is one hop away and greppable by job id. This is the
  cost ADR-152 declined to pay for payloads that are read on-host under
  incident conditions; for a workflow read in an editor with the runbook in
  the same repo, it is the cheaper trade.
- Test-anchored comment lines now exist twice (workflow and runbook). Nothing
  enforces they stay equal; the anchoring suites protect the workflow copy, and
  the runbook copy is documentation.
- The gate's live assertions can only be pinned by review, not by the suite
  itself (no test guards its own presence); the `test-bun` shard runs the file
  by directory glob, so removal is a visible diff.

## Alternatives considered

- **Split the workflow now** — the correct end state, but a multi-workflow
  refactor of a production apply path with its own gates and reviewer
  environments, while main's apply was dead and an authorized cutover was
  blocked. Deferred, not rejected.
- **Strip comments at render (ADR-152)** — no render step exists for
  `.github/workflows/`.
- **Gate in a repo-root `scripts/lint-*.py` ratchet** — those are merge-base
  ratchets needing a full checkout; this is an absolute platform cap, whose
  sibling precedent is `plugins/soleur/test/cloud-init-user-data-size.test.ts`
  (ADR-080/ADR-152), a bun:test with a cap constant and a headroom assertion.
- **A lower gate (e.g. 400,000)** — would force the split immediately for no
  safety gain. The runway that matters is file-to-gate: ~13,000 bytes today,
  roughly 8–9 commits of the growth class that caused #8361 — enough to do the
  split as planned work, which is why the deferral's trigger is a byte counter
  on this file rather than a date.

## References

- #8361 (measured bracket, runs 35431644262 / 35431689935 / 35431766054), #8312, #8294
- ADR-152 (strip-at-render; the rejected comment-freeze option), ADR-116 (content anchors), ADR-080
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-job-rationale.md`
- `knowledge-base/engineering/operations/runbooks/apply-web-platform-infra-red-run.md` (zero-jobs diagnosis)
