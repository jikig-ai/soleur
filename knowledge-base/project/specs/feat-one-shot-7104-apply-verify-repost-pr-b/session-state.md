# Session State — PR-B

## Inherited from PR-A

PR-A (#7509) merged 2026-08-13T14:10:51Z as `c723e4519`, deployed and verified live at 0.253.7;
postmerge green. It shipped `tasks.md` Phases 1–3 (the `DPF_REPLACED` discriminator, the saved-plan
apply, the frame-stability arm) and ADR-186. Full PR-A record:
`../feat-one-shot-7104-apply-verify-repost-recovery/session-state.md`.

`Closes #7104` attaches to **PR-B**, per the operator's UC2 disposition. PR-A referenced the issue
in prose only, and #7104 is still OPEN with `closedByPullRequestsReferences: []`.

## Plan Phase (PR-B)

- Plan file: `knowledge-base/project/plans/2026-08-12-fix-apply-verify-repost-recovery-plan.md`
  (shared across both halves; extended in place rather than duplicated). PR-B's authoritative
  section is `# R18 — PR-B` at the end.
- Task machine: `../feat-one-shot-7104-apply-verify-repost-recovery/tasks.md`, Phases 4–10.
- Status: complete.

### Decisions

- `infra_config_bounded_verify`, `infra_config_no_new_frame` and a `repush_once` *function* are all
  dead names from the pre-R16.2 design and must not be built. The one function PR-B adds is the pure
  predicate `infra_config_should_repush` (R18.1, R18.2).
- The re-push is an **inline latched block inside the widened poll loop**, not a function and not a
  duplicated block. A function invites `if ! repush_once`, which suspends `errexit` for a body
  containing a production `terraform apply`; a duplicated block defeats the call-site pin's `head -1`
  anchors (R18.2).
- Guard 1 is re-derived over the predicate; boundedness moves to Guard 2, the only guard that
  quantifies over the caller (R18.3).
- AC14 is withdrawn: after PR-A, a no-op dispatch passes pass 1, so it no longer exercises the
  recovery. Measured on run 31714143720. The recovery is not producible in production on demand, so
  the hermetic two-pass integration test is promoted to the primary acceptance criterion (R18.4).
- Sentry emission moves to its own step gated on a step output, which keeps escalation credentials
  out of the verdict step and dissolves R17.6 (R18.6).
- Task 9.3 is already discharged by #7526 and #7527; task 7.7 is cut and its property bought by
  construction; task 10.4 is satisfied by run 31714143720 under AC20 (R18.5, R18.7).

### Errors

- The `## Guard Contract`, `## Files to Edit`, `## Observability`, `## Risks` and `## Acceptance
  Criteria` sections still described the pre-R16.2 design at the start of this session, even though
  `tasks.md` task 1.3 (which was to reconcile Guard 1) is ticked. All were corrected in place rather
  than superseded by a second copy.
- `tasks.md` 10.1 named `scripts/run-registered-suites.sh`, which does not exist. Corrected to
  `scripts/lint-orphan-test-suites.sh` (R18.8 §2).
- `GATE_MIN_ASSERTIONS` is 106 on disk; the PR-A findings section records 95. Corrected (R18.8 §1).

## Collision Gate

- `#7104`: OPEN, `closedByPullRequestsReferences: []`. PR #7509 (PR-A) merged with
  `closingIssuesReferences: []` — the split held.
- ADR ordinal enumerated across all **67** `origin/*` refs: highest is ADR-186 (PR-A's), so PR-B is
  provisionally **ADR-187**, re-derived immediately before merge.

## Components Invoked

`soleur:plan`, `soleur:deepen-plan`; agents `Explore`, `learnings-researcher`,
`kieran-rails-reviewer`, `architecture-strategist`, `code-simplicity-reviewer`,
`spec-flow-analyzer`, `cto`, plus a Phase-4.5 strong-model consult and an execution-verified
refutation pass; gates `lint-guard-contract.py`, `lint-infra-no-human-steps.py`, deepen-plan
halts 4.5–4.11, kb-citation and rule-ID sweeps.

Disclosed shortfall: the generic "run every discovered agent" fan-out was **not** executed —
the escalated panel and the strong-model consult had converged (three agents independently
found the same P0), and the remaining budget went to fork adjudication and execution-verified
re-checking instead. Recorded in the plan's Enhancement Summary.

## Work Phase (PR-B) — 2026-08-13

Phases 4–9 are delivered across eight commits. The measured facts, so a resumed session
does not re-derive them:

- **Task 4.0 (was blocking):** the re-push plan replaces **exactly 1** managed resource,
  `terraform_data.deploy_pipeline_fix` (`delete,create`), `host_creates=0`. Measured against
  live prd state, read-only. Guard 3's literal is `1`. **Do not re-run the terraform plan.**
- **The extraction is byte-identical:** both sides sha256 `2a23f958…`, 19774 bytes, 240 lines.
  Note the plan's R22.2 quotes 19,710 — that figure is stale; 19,774 is measured.
- **AC20 holds across the extraction:** the `DPF_REPLACED == "false"` branch is byte-identical
  to `origin/main`'s, 7403 bytes both sides. This is what licenses citing run 31714143720.
- **R19.4 §4 confirmed:** five `success()`-gated steps downstream of the gate, not the plan's
  "six". Two close the founder's issues; one swaps the running container.
- Suites: `infra-config-gate.test.sh` 127/0, `infra-config-verify.test.sh` 23/0.

### Deviations from the plan, each deliberate and stated

- **Guard 2 (task 6.3) is a commit-time verification, not a standing assert.** R22.5's
  prescribed baseline is `git show origin/main:<workflow>`, which BECOMES the post-move
  revision at merge — the baseline flips. And commit 2 parameterises the script, so a
  permanent byte-identity assert would be RED by the end of this same PR. Hashes recorded in
  ADR-187 instead.
- **The F1 pin uses an explicit two-clause form rather than the precedent's
  reconstruct-the-single-file-view trick.** That precedent exists because ~120 of its
  assertions are anchored on YAML indentation; none of the gate suite's are (`$1=="done"` is
  field-based), so the reconstruction buys nothing here while the two-clause form proves both
  (i) production invokes the script and (ii) the script carries the wiring.
- **Task 4.0 was measured with the SINGULAR `-target` form that ships** (6.9/AC19), not this
  task's "same four targets" text, which mirrors the first apply.
- **AC17 re-read under the split.** The re-push is a workflow step now, so "the re-push stub
  was invoked exactly once" is unobservable in-script; boundedness is structural and pinned by
  Guard 3 + the backstop. AC17 here drives the real script through both passes instead.

### Still open

`4.3`, `8.1`, `8.2` — the **committed** Guard 1 / Guard 2 mutation rows. Every guard in this
PR has been mutation-proven in-session and the results are recorded in the commit messages,
but AC21 asks for the rows as committed artifacts, which is stronger. Plus Phase 10's ticks
and the `/review` → `/qa` → `/compound` → `/ship` tail.

### Environment note

`terraform init` cannot complete on this machine: `releases.hashicorp.com` answers 200 on its
root but resets over IPv6 and times out over IPv4 on the `hashicorp/tls` provider ZIP, and it
HANGS rather than failing. Worked around with a `filesystem_mirror` at `/var/tmp/tfmirror`
plus `TF_CLI_CONFIG_FILE=/var/tmp/tfcli.hcl`; the worktree's infra dir is already initialised.

## Next

- Commit the mutation rows (4.3, 8.1, 8.2), close Phase 10, then `/review` → `/qa` →
  `/compound` → `/ship`. PR #7546 must carry `Closes #7104`.
