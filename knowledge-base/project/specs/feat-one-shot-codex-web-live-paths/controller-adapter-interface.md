## File Scopes

| Agent | Files |
|---|---|
| Code | `scripts/codex-qualification/controller_adapters.py` |
| Tests | `scripts/codex-qualification/test_controller_adapters.py` |

The coordinator owns component-census, exporter, fixture, wrapper and documentation integration. Neither agent commits, constructs real transports, discovers credentials, calls Docker/SQL/providers, opens account directories, or changes production admission. Read-only shell commands substitute for Codex filesystem reads; shell mutation and operational commands are prohibited for both agents. The code agent waits for the coordinator's RED receipt before writing implementation.

## Public Interfaces

Ruled by CTO agent, 2026-10-13: implement callable adapters over injected transports, with production wiring and execution admission absent. The operator's renewed authorization covers implementation and synthetic verification only. Existing execution approvals stay consumed; the withdrawn command remains unavailable. Worst target-user failure: false operational clearance for the wrong source/resource/writer inventory. Production writes and projected WAL impact are zero.

All classes copy inputs; constructors call no transport. They bind the executing `controller_adapters.py` bytes through the operational source-reference census, validated by `checked_inputs`. They accept a monotonic `clock: Callable[[], float]`; every transport operation receives `timeout` no greater than remaining `BUDGET.work_seconds`, and late/backward/nonfinite clocks terminate progress. Transports must enforce timeouts; post-call checks alone cannot preempt a blocked dependency. A failed/ambiguous operation is terminal, with no implicit retry. Cleanup uses the exact successful registrations or existing handles, has its own 300-second deadline, preserves primary failure, and stops all calls after expiry.

Every `snapshot() -> dict` returns `execute_authorized=False`, `profile_admissible=False`, `authentication_established=False`, `ownership_verified=False`, `quiescence_verified=False`, `issuer_verification='pending'`, `independent_review='pending'`, `runtime_evidence='pending-injected-observations-only'`, plus `state`, `primary_failure` and injected-call counters. Callable code and matching fake responses confer no runtime permission. No CLI, built-in real transport, approval-consumption mechanism, permissive approved/reviewed boolean, arbitrary command/SQL entry point or credential discovery is added.

`BuilderAdapter(contract, spec, observation, *, reviewed, transport, clock)`:

- `build(export_fd: int) -> dict`: one attempt only. Bind candidate identity/pairing, export manifest, controlled Dockerfile, exact argv/environment hashes, replaced environment and `builder_spec` to the operational contract. Validate complete exported bytes/modes/links before transport invocation. Use `candidate.verify_exports`; the coordinator resolves the three generated metadata leaves without weakening default inventory checks.
- Transport: `build(recipe: dict, *, timeout: float) -> dict` receives a copied exact recipe, never a shell string or inherited environment. Exact response fields: `image_id` (immutable sha256 ID), `exit_code` (integer zero), `log_sha256` (digest), `log_bytes` (integer 0..16 MiB). Validate before returning progress; no raw log/content output.

`NamespaceAdapter(contract, attempt, network, scratch, images, profiles, *, reviewed_profiles, transport, clock)`:

- Own one internal `Policy`; never accept caller-mutated policy state or an externally populated inventory. Validate each complete profile against the separately reviewed profile and observed/reobserved image Config before creation.
- `create_network() -> dict`, `create_volume(name: str) -> dict`, `create_role(name: str) -> dict`, `start_role(name: str) -> dict`, `namespace() -> dict`, `cleanup() -> dict`, `snapshot() -> dict`.
- Transport: `request(method: str, path: str, payload: bytes, *, timeout: float) -> tuple[int, dict]`; all requests pass through `Policy.admit` and transport receives its rewritten path/body. Validate response status, size, fields and resource identity before registration. Reject duplicate IDs across network/containers/execs before registration. Creation reservations are single-use before the call; ambiguous results grant no ownership and cannot be adopted by name/label.
- Volumes: filtered `/volumes` census proves supplied absence before first create, complete successful receipt is registered and reobserved before attachment. Network and container dependent reads use registered IDs. Reobserve exact container name, attempt/project labels, network membership and image identity before start/cleanup; derive Kong subnet/upstream with `namespace_recipe`.
- Ordering: network and both registered volumes before db/auth/inbucket/rest/storage; those five services before Kong; Kong before TLS/resolver; both before renderer/browser. Migration roles require db; replacement renderer additionally requires first renderer. Preserve every `Policy`/`RoleProfiles` privilege, mount, environment, route and stdin restriction; refuse conflicting recipes.

`SessionAdapter(contract, attempt, database, binding, handles, *, transport, clock)`:

- `binding` is `ScenarioBinding`; `handles` maps holder/waiter to their immutable `SessionIdentity`. Require exact source and scenario hashes, attempt/database, distinct PIDs and process/backend births.
- `begin() -> None`, `observe() -> bool`, `complete() -> dict`, `cleanup() -> dict`, `snapshot() -> dict` wrap `RaceController`. No transport call on a premature complete. Observe only within the existing 256-observation/30-second race bound.
- Transport: `identity(handle, *, timeout) -> SessionIdentity`; `start(handle, sql: bytes, *, timeout) -> dict` returns exact `identity`, `scenario_sha256`, `exit_code` (integer zero); `observe(holder, waiter, sql: bytes, *, timeout) -> dict` returns the existing `RaceController.observe_blocking` fields; `commit(holder, *, timeout) -> dict` returns exact `identity`, `command_tag`, `exit_code`; `wait(waiter, *, timeout) -> dict` returns exact `identity`, `exit_code`; `assertion(sql: bytes, *, timeout) -> dict` returns exact `scenario_sha256`, `exit_code`; `rollback(handle, *, timeout)`, `close(handle, *, timeout)` return exact `identity`, `exit_code`.
- Reobserve identity before each handle operation. Send only bound 40/41/42/43 scenario bytes; commit/rollback are explicit transport methods. Commit once only after observed exact lock dependency; accept explicit COMMIT receipt, waiter completion, then bound assertion. No stdin reopening or replacement session. Track handles touched before calls so ambiguous starts can be rolled back/closed using only the same preexisting handles.

`RetainedAdapter(contract, attempt, owner, database, resource, writers, *, transport, clock, observation_clock)`:

- Resource is the separately supplied stable `retained_files.BINDING_FIELDS - {'quiescence_id'}` reference; writers use `writer_census`. Observation clock supplies epoch integers for `retention_spec`; operation deadlines use the separate monotonic clock.
- `collect(phase: str, expected_paths: list[str]) -> dict`, `compare(erased_paths=()) -> dict`, `snapshot() -> dict`; exact once-only ordered before/after phases. Collection never opens arbitrary paths or changes retained data.
- Transport: `resource(reference, *, timeout) -> dict` returns exact `resource`, `owner_id`, `database_id`, `writers`; `quiesce(reference, writers, phase, *, timeout) -> dict` returns exact `binding`, `writers`, `quiescent_writers`, `quiescence_start`; `open_root(reference, *, timeout) -> int` transfers one owned descriptor; `finish_collection(reference, writers, phase, collection_start, collection_end, *, timeout) -> dict` returns the complete observation accepted by `retention_spec`; `release(reference, writers, quiescence_id, *, timeout)` releases only that quiescence attempt.
- Reobserve resource/writers before and after collection; compare descriptor device/inode to registered root. Use `retained_files.snapshot`, close only the returned owned descriptor, require returned times to enclose actual observation-clock collection times, and release quiescence even on collection failure within the cleanup bound. Compare both manifests with `retention_spec`. Supplied empty writers authenticate no absence.

Acceptance scenarios use synthetic Git trees, files, images and transport doubles only. Include positive controls, pre-call guard assertions, malformed/foreign/duplicate receipts, Config changes, exact rewrite verification, changed input/transport mutation, ambiguous failure/no retry, backward/expired clocks, bounded pending observations, premature commit/PID reuse, cleanup failure/expiry, descriptor substitution, writer change and out-of-window collection. Representative guard-removal controls must produce intended assertion failures, separately from fixture/setup errors.
