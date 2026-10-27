# Writer-window preparation — 2026-10-27

## Disposition and authority

**Preparation only; activation unavailable.** Pausing the known GitHub Actions
mutators is one part of exclusion. Direct credential holders and persistent
consumers remain unaccounted for. No writer clearance is established.

This document proposes exact control-plane commands for review. None has been
executed or approved. PR #9051 remains draft with auto-merge off; both recovery
and companion branches remain unpushed. The successful October 27 catalog
capture consumed its approval. There is no capture retry, reconciliation,
shared database operation, provider request or customer-processing authority.

Bindings checked in this continuation:

| Input | Identity |
|---|---|
| Recovery source before this preparation | `6e9f1b0da12226768d7b8c8a489b2b8cc3c604e3` |
| Companion grant precursor | `4f0c8407aba51fdd9c846c252e8d1edceb1cb3d1` |
| Fetched main | `2e9874cdf65e9ca5fd086f3728fd0c2105d0cae5` |
| PR #9051 remote head | `4225c68a3eb1e9bdb917f899ae85618848b2c691` |

Read together with [the capture record](recovery-capture-2026-10-27.md) and
the companion worktree's `slice-a-grants-2026-10-27.md`. This preparation does
not supersede their independent readiness holds.

## Known control-plane targets

Read-only workflow API calls in this continuation observed all three active.
These are dated observations, not state reservations or a complete run census.

| Workflow | GitHub workflow ID | Observed state |
|---|---:|---|
| `tenant-integration.yml` | 277913850 | active |
| `scheduled-integration-suites.yml` | 380964769 | active |
| `dev-ledger-reconcile.yml` | 365691492 | active |

The tenant and scheduled workflows invoke `scripts/dev-suite-mutex.sh`, whose
failure policy explicitly proceeds on contention or unavailable inputs. Its
mutex cannot establish exclusion. Per-ref concurrency does not cover all refs.
Reconciliation's ledger relation lock does not fence unrelated relation/API
writes. Workflow inventory is not an inventory of actual credential holders.

The initial repository-wide run-list query returned only its first 100 rows
from a 40,000-count result. It is not a complete census. A later tenant-only
`in_progress` query returned zero; it says nothing about queued, pending,
requested, waiting or other-workflow runs. Neither observation clears writers.

## Proposed commands and order — not authorized

Before any disable, obtain explicit approval naming each command below and
its conditional restoration command. Use GitHub App authentication, as required
for infrastructure/CI writes; existing read-only CLI access does not establish
App write authority. Do not widen credentials or change repository permissions.
Re-read each workflow by numeric ID and require the exact expected path and
`active` state. A different initial state requires a revised proposal.

Execute sequentially, checking exit status and reading back
`disabled_manually` after each successful command:

```bash
gh workflow disable 277913850 --repo jikig-ai/soleur
gh workflow disable 380964769 --repo jikig-ai/soleur
gh workflow disable 365691492 --repo jikig-ai/soleur
```

Keep an operation journal containing initial state, attempted command, time,
exit status and readback. Record an attempt before issuing it: a lost HTTP
response can follow a successful state change. On any failure or ambiguous
response, stop further disabling, resolve that target by readback, and restore
the targets changed by this operation. Do not assume a failed CLI exit proves
that no remote change happened. Concurrent administrative state changes make
ownership ambiguous and require resolution rather than unconditional enable.

These commands change repository-wide workflow admission. They can delay
other PR checks and scheduled tests. They do not stop existing runs or revoke
cached credentials. No run cancellation, force cancellation, dispatch, rerun,
workflow edit, push, ready or merge command belongs to this proposal.

## Drain and bounded observation

Proposed time bound: start an absolute 30-minute window immediately before
the first disable. Allocate at most its first 15 minutes to natural draining.
At that deadline, any remaining nonterminal run or unknown read result means
abort and restore. A 70-minute scheduled-suite job may outlast this budget;
the outcome then is abort, not cancellation or an extended window.

The execution controller must enumerate all three workflows across every ref
and event for `in_progress`, `queued`, `pending`, `requested` and `waiting`.
Read every page; retain observed run IDs across samples until each has an
individually confirmed `completed` state. An API error, missing run, unknown
status or pagination/search-limit ambiguity is UNKNOWN, never zero writers.
Require a second empty census and unchanged disabled states before reporting
the CI-only pause. Continue bounded probes throughout any later approved
operation. No database action is included in this observation phase.

Natural draining avoids interrupting migration/test execution. The migration
runner couples each normal migration body and its ledger insertion in one
transaction, but a complete run spans transactions and tests/fixture writes
are separate. Cancellation cannot undo earlier commits. No rollback of
application data or schema is proposed here.

Codex maps Monitor to bounded shell probes resumed in-session. It has no
equivalent scheduled wakeup or remote trigger. Before activation, prepare and
rehearse an owned execution/restoration controller, including lost responses,
partial disable, authentication loss and interruption. A shell trap alone
cannot guarantee restoration after process/host loss. Establish an independent
restoration mechanism and its exact authorization before starting; this
document is not such a controller and no restoration watchdog has been armed.

## Restoration — proposed conditional commands

Restore in reverse order, only for targets this operation changed from the
freshly recorded `active` state. Re-read state first; an already active target
requires no enable. Any incompatible state or competing administrator action
is unresolved. Never enable a workflow that was disabled before this operation.

```bash
gh workflow enable 365691492 --repo jikig-ai/soleur
gh workflow enable 380964769 --repo jikig-ai/soleur
gh workflow enable 277913850 --repo jikig-ai/soleur
```

Attempt restoration on abort, normal exit and the absolute deadline, using
the explicitly approved restoration scope. Verify each original path/ID and
`active` state afterward, then recheck PR draft/head/auto-merge. Enabling
restores workflow admission; it does not recreate missed events. Do not
silently dispatch replacement runs. If restoration is unavailable, report
the exact remaining target and last confirmed state immediately; do not claim
the window ended or retry indefinitely. Recovery actions beyond the approved
commands require their own authorization.

## Missing exclusion evidence and next preparation

| Holder path | Source evidence | Remaining evidence |
|---|---|---|
| Tenant CI mutator | Main binding above, `.github/workflows/tenant-integration.yml` › `Acquire dev-suite mutex` | Complete admission/drain observations under approved control |
| Scheduled integration mutator | Same main, `.github/workflows/scheduled-integration-suites.yml` › `Acquire dev-suite mutex`, `Seed bot fixtures (pre-migration)`, `Apply migrations to dev` | Live runs and API consumers |
| Reconciliation mutator | Same main, `.github/workflows/dev-ledger-reconcile.yml` › `Reconcile` | Current dispatched and close-triggered runs |
| Local CLI and agent access | Capture record proves restricted-environment local Doppler authentication succeeded | Actual authorized principals, token scope/access holders and cached credentials |
| Direct database connections | Same main, `apps/web-platform/scripts/run-migrations.sh` › `run_sql()` and `scripts/dev-suite-mutex.sh` › `usage()` | Effective roles, inherited privileges, sessions and fencing coverage |
| Service-role API and seed tools | Same main, scheduled integration's `Seed bot fixtures (pre-migration)` invokes `plugins/soleur/skills/ux-audit/scripts/bot-fixture.ts seed`; subsequent suites receive dev secrets | Consumers holding service keys and their enforceable stop/fence |
| Persistent dev applications/workers and dashboard/admin access | Not established by the workflow census | Deployed consumers, administrative access and bypass paths |

Repository source identifies possible paths; it cannot certify current holders
or effective access. Prepare a separate, names/metadata-only evidence proposal
covering current principals, memberships, effective permissions, sessions,
token scope/access holders and persistent consumers, with minimization,
private retention, exact commands/bindings and independent review. The previous
collector lacks role inheritance, column ACLs and effective privileges. Its
approval cannot authorize this new collection. No credential values or
application rows should be included in that future proposal.

Once evidence identifies every relevant bypass path, define and review its
enforced fence and restoration separately. Role/ACL changes, credential
rotation, connection termination or other shared writes need exact approval;
they are not implicit in workflow-pause approval. Any later ledger operation
still needs actual mutex acquisition, transactional ledger locking, fresh
tuple/schema verification, CAS and its own exact-action authorization. Keep
activation unavailable until exclusion and restoration prerequisites are met.

## Observability

- **Signal:** workflow state/path readback, complete nonterminal run census,
  operation journal, restoration controller result and PR state. Coverage is
  the GitHub control plane; it does not cover direct database/API writers.
- **Owner:** executing agent owns observation and restoration; the independent
  controller must cover agent/process loss before activation is available.
- **Failure modes:** command/API/authentication failure or ambiguous response,
  incomplete census, deadline, state drift and interruption abort the pause;
  unresolved direct-holder coverage blocks activation before any command.
- **Discoverability test command:**
  `gh api repos/jikig-ai/soleur/actions/workflows/277913850 --jq '{id,path,state}'`
  is a no-SSH readback for one target; repeat against the other two IDs. It is
  not a writer-clearance test.
- **Retention:** keep minimized control-plane receipts and command identities
  with the recovery evidence; exclude credentials, application rows and raw
  private catalog content from committed artifacts.

## Verification and tool observations

The command forms were verified using installed `gh workflow disable --help`
and `gh workflow enable --help`. Offline comparison verified all six exact
command identities/order, and `bash -n` accepted both blocks without executing
them. No live transition or restoration was tested.
`git diff --check` passed. The canonical Markdown invoker excluded all three
changed project artifacts; its successful skip is not a lint measurement.
GitHub documents the [disable and enable state transitions](https://docs.github.com/en/rest/actions/workflows#disable-a-workflow)
and [workflow-run statuses and search limits](https://docs.github.com/en/rest/actions/workflow-runs#list-workflow-runs-for-a-workflow).

Ruled by CTO agent, 2026-10-27: accept this document and its session-state
append as preparation only, with no blocking finding in the scoped text review.
Activation stays unavailable until direct-holder fencing and an independently
restorable controller are reviewed and explicitly authorized. The controller
must be rehearsed with API stubs covering partial disable, lost responses,
authentication loss and interruption. Dissent: none. This is a local preparation
review, not formal exact-head PR review, operational approval or CLO clearance.

Tooling failures and their resolutions are recorded in the October 27 addendum
to [the engine-brief tooling learning](../../learnings/2026-09-11-engine-brief-validation-and-sandbox-probes.md).
