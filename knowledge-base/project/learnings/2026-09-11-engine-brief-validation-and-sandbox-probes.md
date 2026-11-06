---
title: "Validate engine briefs with native interfaces and repository tooling"
date: 2026-09-11
category: workflow-patterns
tags: [codex, grok, architecture, validation]
---

# Engine brief validation

Plugin discovery is not hosted-runtime qualification. Grok's installed CLI help
exposes stdio and WebSocket agent modes; checking the local interface also led to
the existing web-runtime epic instead of inventing a new Grok integration track.
An architecture review identified a separate invariant: engine failure must not
silently transfer conversation context to another provider.

Session tooling corrections:

- Inspect `lefthook.yml` before selecting a Markdown command. Guessing
  `markdownlint-cli2` and `lint-markdown.sh` produced missing-file errors. The
  repository uses `bash scripts/markdown-lint.sh <paths>`.
- That invoker scopes through tracked files and `.markdownlintignore`. The project
  artifact directory is explicitly excluded even after staging; report that skip
  honestly and check document links and whitespace separately.
- Git metadata writes and GitHub access needed sandbox escalation. Treat cleanup
  lock failures and network errors as failed actions, not successful hygiene.
- Login-shell probes printed stream-fd warnings while reads succeeded. Repeating
  with `login: false` removed those warnings; no shared shell configuration changed.
- Lefthook reported hook-sync skipped because a shared `core.hooksPath` was set.
  The executable pre-commit hook was present and invoked Lefthook; the sync notice
  was not evidence that checks had been disabled.
- The commit guard resolved the hook's main-branch CWD despite the shell tool's
  feature-worktree `workdir`. Its documented resolver understands an explicit
  `cd <worktree> && git commit`; use that supported form so the guard checks the
  intended branch. The `cd` must be the first shell operation in a compound
  command; staging before it still trips the main-branch guard. Do not disable
  the guard.
- Two planned read-only research agents hit the current agent usage limit before
  returning findings. Recovery: continue with bounded local `rg`/`cat` research,
  record the fan-out as partial, and never interpret an agent-limit error as an
  empty research result.
- The first Pencil dependency check found the headless CLI but could not
  authenticate it. Loading `PENCIL_CLI_KEY` from Doppler and re-running the
  check unlocked the connected Pencil MCP; the committed wireframe was then
  authored, exported, saved, and layout-verified. A prose substitute would not
  satisfy the design gate.
- Pencil rejected a first `batch_design` block because frame borders use the
  object shape `{align, thickness, fill}`, not `stroke: string` plus
  `strokeWidth`. The adapter rolled back the block; re-read an existing `.pen`
  precedent and reran with the canonical shape.
- `lint-guard-contract.py` accepts plan paths as positional arguments; passing
  the literal `plan` made it look for a nonexistent file. Use the explicit plan
  path (or omit paths to scan the repository) and inspect non-zero output before
  continuing.

## Work-phase preflight addendum

- Reading the installed work skill in one call truncated its output. Use bounded
  section reads; the installed file includes long single-line learned rules.
- Agent definitions recurse: `ux-design-lead.md` lives under `agents/product/design/`.
  Discover with `rg --files` before reading an assumed flat path.
- The installed `cleanup-merged` cleaned one sibling, then treated the linked
  feature worktree as a non-bare root and checked it out to main. Both specialist
  agents detected absent artifacts before writing. `git reflog` confirmed the
  checkout, the feature ref was intact, and `git switch feat-pluggable-web-agent-engines`
  restored the clean feature tree. Its non-bare post-cleanup arm in
  `worktree-manager.sh` also contains a hard reset, so do not rerun it from a
  linked checkout. Verify branch and HEAD after cleanup before any task starts;
  run future cleanup from the actual common repository root.
- Two work-phase subagents hit the session usage limit after one produced a
  partial inventory artifact and the other produced no persistence changes.
  Preserve any files they wrote, inspect them against the worktree HEAD, and
  continue the failed slice sequentially; an errored agent notification is not
  evidence that its earlier writes were absent.
- Pencil export timed out waiting for its prompt after writing a complete PNG.
  Verify the file signature, dimensions, visual output, and `.pen` post-save size
  before retrying an export; a timeout notification alone does not establish a
  failed export.
- A shell probe was accidentally issued as JavaScript (`const x=1`), producing a
  predictable `command not found`; keep JavaScript orchestration inside
  `functions.exec` and pass only valid shell syntax to `exec_command`.
- `apply_patch` resolves paths from the session root, so edits to a linked
  worktree must use the `.worktrees/<name>/...` path when invoked from the root.
- The pre-commit full gate ran for more than 90 minutes and completed with 397/404
  suites passed and two failures while several sibling gates were active; an
  isolated web-platform rerun then queued behind the same shared lock and was
  stopped. The commit was created only after the targeted registry test was green;
  the full-gate failures remain an open validation issue to resolve before merge.

## Addendum — 2026-10-27, recovery writer-window preparation

- Cleanup lock writes and two `gh workflow ... --help` mise probes were refused
  by the sandbox. Approved escalation completed the cleanup without reaping
  entries and verified both help commands. Do not count the refused attempts
  as success or widen shared-operation authority because local tools ran.
  The local checkpoint commit also required approved escalation for its Git
  index lock; this saved only local documentation and did not push.
- A speculative `.soleur/*window*` glob and an app-relative mutex path produced
  missing-path errors. Enumerating files and reading `scripts/dev-suite-mutex.sh`
  resolved them. Discover paths before reading; do not infer absence from a
  failing shell glob or a guessed directory.
- Multi-file skill reads and the initial first-page run census were truncated.
  Re-read required sections separately. A first page or single-status query
  remains partial observation; it cannot establish an empty writer census.
  The recovery proposal records this limitation and blocks window activation.
- Session-start cleanup's first sandboxed run could not acquire locks under
  `/home/jean/.local/state/soleur` and the shared Git metadata path; the approved
  retry later reported lock contention and GitHub lookup failures on gone
  upstreams. Preserve the reported skips and inspect the cleanup's final
  summary; never infer that cleanup completed every candidate. When login-shell
  startup fails because mise cannot install a missing tool read-only, retry the
  already-installed CLI with login initialization disabled, then record its
  measured result rather than treating startup failure as an API result.
- The installed Markdown invoker returned success after explicitly excluding
  the untracked project-spec path. That is a skip, not lint evidence; check the
  new document's links and whitespace separately, and report the excluded
  scope without calling it green.
- A companion branch has no `origin/<branch>` ref in the recovery worktree;
  asking `git rev-parse` there for the absent ref returns an ambiguity error.
  Verify the companion's own worktree `HEAD` and status, then use a remote
  query only if remote state is required. Do not translate a missing local
  tracking ref into evidence that the branch was pushed or deleted.
- `nl | head` can terminate `nl` early and report `Broken pipe` under the
  session's exit-status policy. Use a bounded reader such as `sed -n` when a
  small line range is known, rather than closing a producer's pipe early.
- A resumed session guessed the holder-evidence document at the worktree root;
  it is under the feature spec directory. Locate the named file with scoped
  `rg --files` before reading it. A full session-state read and the go command
  also exceeded output limits; read the relevant sections in bounded ranges.
  A patch failed to match its expected ending and applied nothing; re-read the
  exact ending and use a smaller, matching hunk.

## Addendum — synthetic stream cancellation

- A synthetic stream test expected the underlying `cancel` callback after
  the stream had already closed due to eager pulling. Keeping the test stream
  open until cancellation made the assertion exercise the intended path; the
  corrected test passes. A completed stream is not evidence that cancellation
  of an active transport was exercised.
- The changing-total mutation initially survived: the test's two-page scenario
  was rejected by a different count check, and a later three-page fixture used
  an undefined helper whose exception the collector converted to `failed`.
  A valid helper and a transient three-page count change now isolate the guard;
  deleting that guard makes the test fail. A fail-closed catch can otherwise
  make a broken test fixture look like evidence of a working guard.
- An admission identity mutant initially survived because the mismatch fixture
  also changed the workflow path, so the path guard rejected it independently.
  A second fixture changes only the numeric ID; identity, path and state mutants
  are now each detected.
- A synthetic admission transport ignored its abort signal and returned after
  the evidence deadline. The surrounding task then started the run query
  despite having already returned a timeout result. Added abort checks at
  phase transitions and before invoking the injected run transport; the
  regression verifies no subsequent request begins after late resolution.
  A mutation of the first check alone survived because the transport check is
  redundant; removing both checks made the regression fail.

## Addendum — local PostgreSQL catalog tests

- `initdb` was not on PATH and the guessed `/usr/lib/postgresql` directory was
  absent. The existing local PostgreSQL 17 container was identified separately;
  a loopback connection failed inside the sandbox and succeeded after the
  approved escalation. Tests used uniquely named disposable databases and
  verified their deletion, not the shared-development database.
- `SET ROLE` initially failed with SQLSTATE 42501; granting the synthetic role
  fixed switching but did not reproduce another login's restricted statistics.
  A separate synthetic login and peer connection exposed a real coverage bug:
  filtering `pg_stat_activity.backend_type` discarded rows with hidden fields.
  Remove that filter and assert the hidden peer remains as an unknown state.
- Terminating the local psql client during `pg_sleep` did not immediately end
  its backend, causing `DROP DATABASE` to fail with 55006. The orphaned unique
  database was identified, checked for zero connections and deleted; the fixture
  now waits for its bounded peer query before dropping the database and role.
- The direct ACL query's `column` alias produced SQLSTATE 42601 because the
  alias conflicted with SQL syntax; `column_name` fixed it. Once ACL rows were
  added, the existing table-result test also needed a role-name discriminator
  to avoid treating an ACL row as an effective-privilege row. Synthetic
  PostgreSQL tests and targeted mutations passed after both corrections.
- Adding a synthetic schema CREATE grant to an inherited parent changed the
  child's effective privilege, so an earlier assertion expecting false became
  invalid. The corrected fixture checks the inheriting child receives CREATE
  and a non-inheriting role does not; the database test then passes.
- A generic 10,000-row result limit would have accepted the session query's
  257-row overflow sentinel as complete. Session results now validate their
  summary and treat the 256-session cap and restricted visibility as partial;
  targeted mutations detect removal of each check. A generic cap cannot replace
  a source-specific completeness contract.
- PostgreSQL serializes an `oid` field to JSON as a string, so a runner that
  validates numeric identifiers failed against the real local database despite
  passing synthetic unit tests. Casting the OID to `bigint` in the query fixed
  the mismatch and the disposable PostgreSQL integration passed.
- An arm timeout could fire slightly before the overall deadline, letting a
  later arm start during the remaining fractional time. The set now stops all
  subsequent supplied arms after any timeout; ten full-suite timing repeats
  passed. This does not cancel an uncooperative operation already in flight.

## Addendum — synthetic deadlines and test selection

- An adapter can block the JavaScript event loop past a timer and resolve before
  its callback runs. Monotonic elapsed-time checks at phase boundaries prevent
  such a result from being reported as timely; they cannot preempt synchronous
  code or establish that an in-flight operation stopped.
- A broad Node test glob included the local PostgreSQL integration helper
  directly, without the disposable database name that its Python harness sets.
  It failed its safety assertion before connecting. The offline suite excludes
  that helper; its integration must run through its dedicated Python harness.
  A later broad glob repeated this selection mistake; the same assertion failed
  before connecting and the explicitly filtered nineteen-file suite passed.
- Full reads of the long session-state and learning files exceeded output limits;
  use bounded section reads and inspect the exact edit context before appending.

## Addendum — interrupted independent review

- A follow-up privacy-review agent stopped on a model usage limit without a
  result. Its earlier preliminary assessment remains evidence only for that
  earlier scope; the failed follow-up and final legal clearance remain open.
  Do not infer a completed review from an agent termination notification.

## Addendum — package resolution scope

- Resolving `esbuild` from the worktree root failed because it is an app-level
  dependency. The same Node resolution from `apps/web-platform` succeeded;
  run app dependency probes from the app directory rather than treating the
  root-level miss as evidence that the package is absent.

## Addendum — synthetic PostgreSQL fixture diagnostics

- One local runner fixture failed without exposing which Node assertion failed;
  five subsequent executions passed, so its cause remains unconfirmed. The
  harness now reports only the fixture line number on failure rather than
  dumping arbitrary database errors. An attempted diagnostic wrapper could
  not reach loopback in the sandbox, while the specifically approved fixture
  command could; use that fixture command rather than inferring a database
  outage from a differently sandboxed wrapper.
- A later failure identified the immediate post-cancel `pg_stat_activity`
  assertion: the client had received cancellation while the server still
  reported the query active. The fixture now waits a bounded interval and
  explicitly requires the server-side active count to clear. The earlier
  uninstrumented failure cannot be attributed to this same race.
- A session-state patch used stale surrounding text and was rejected without
  changing the file. Re-reading the exact nearby lines allowed a scoped retry.
- The local fixture's mocked custom-socket refusal initially left a driver query
  pending; that run was interrupted. Throwing synchronously from the socket
  factory makes postgres.js reject the query, and the bounded regression passes.
- A first isolated fixture attempt could not find the PostgreSQL image on the
  daemon actually used by the fixture; a separately approved image pull fixed
  that setup. A later tool call failed to print its returned session ID, so its
  completion could not be read. After confirming that process and labeled
  container had exited, the fixture was rerun with the complete tool result
  retained. Always capture the session ID when a command may yield.
- A later independent review stopped at its model usage limit before returning
  findings. Treat it as an incomplete review and retry or use another reviewer;
  the error does not establish clearance.

## Addendum — typed-array boundary probes

- A probe shadowing a Buffer's `length` to a smaller value caused `Buffer.from`
  to throw `RangeError`; it did not demonstrate an oversized copy. A separate
  `byteLength` shadow left the copied length unchanged and exposed the query
  limit bypass. Check actual typed-array slots with intrinsic getters, and
  distinguish a failed probe from evidence of the hypothesized behavior.

## Addendum — isolated vault test setup

- An isolated mutation probe lost literal quote characters through shell
  quoting and failed its setup assertion before editing the temporary copy.
  Constructing the quoted marker inside Python fixed the probe; the corrected
  run detected removal of the orphan-fixture guard.
- A process-lock test using Python's default forkserver could not bind its
  local socket in the sandbox. The disposable POSIX test uses the explicit
  `fork` context and passed; this is not a network or host-loss rehearsal.
- A combined test run overlapped a collaborator's RED test edit in the shared
  worktree. The new assertion was expected to fail until the implementation
  landed; the run cannot certify a stable tree. Wait for writers to freeze the
  affected files before running a combined verification.
- A public GitHub source probe through the sandboxed `gh` shim failed when mise
  tried to install a CLI into a read-only location. The approved escalated
  read succeeded; the failure was not evidence that the public source or
  provider capability was absent.
- The offline npm metadata update failed with `ENOTCACHED`; the sandboxed Bun
  lockfile update also failed on a read-only temporary directory. Approved
  escalated retries regenerated the app's npm and Bun lockfiles. The existing
  transitive package alone was not used as a substitute for a direct dependency.
- A sandboxed Node cross-language test stalled when spawning Python; a minimal
  Node spawn probe reported `EPERM`. The approved unsandboxed test completed.
  This was a harness restriction, not evidence of a contract mismatch.
- A direct read of an assumed `holder-evidence-db-roster-core.test.mjs` path
  failed because the existing tests are named `holder-evidence-db-roster.test.mjs`.
  The actual file was read before edits; discover adjacent test names with
  `rg --files` rather than inferring them from the implementation filename.
- A later batched SQL read repeated the same mistake with an assumed
  `holder-evidence-db-sequences.sql`; sequence and materialized-view queries
  actually share `holder-evidence-db-objects.sql`. The subsequent `rg --files`
  confirmed the paths before changing the collector.
- Removing names from the shared function SQL would have broken its existing
  synthetic catalog consumers, which identify test fixtures by name. A later
  cross-consumer search caught this before shipping; restore the shared query
  and use a separately bound name-free query for the new bundle. Search all
  SQL consumers before changing an existing query's output schema.
- A session-state read at the worktree root failed because this feature keeps
  it under its knowledge-base spec directory. Locate it with `rg --files`
  rather than assuming the session-state path. A follow-up patch initially
  used an inexact context line; rereading the file supplied the exact context.
- A synthetic backend-identity assertion failed when a timestamp parameter was
  cast to `timestamptz`: the pinned postgres.js driver serializes that type via
  JavaScript Date, losing sub-millisecond precision. Exact fixed UTC text
  comparisons passed. The failed probe also showed that a sleeping synthetic
  backend can outlive its client and obstruct fixture teardown; force-drop only
  the uniquely created database inside the verified disposable test server.
