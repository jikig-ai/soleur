## File Scopes

| Agent | Files |
|---|---|
| Code | `scripts/codex-qualification/controller_transports.py` |
| Tests | `scripts/codex-qualification/test_controller_transports.py` |

The coordinator owns operational component census, synthetic census fixtures,
offline wrapper registration, documentation and Git integration. Code waits for
the coordinator's RED receipt before implementation. Neither agent commits or
accesses real sockets, Docker, SQL, credentials, providers, browsers, accounts or
shared resources. Shell reads substitute for filesystem tools; only the
coordinator runs synthetic tests. No full battery or operational command runs.

## Public Interfaces

Ruled by CTO agent, 2026-10-14: implement one explicit Unix JSON HTTP transport
for the namespace adapter. The user explicitly authorized source implementation
and independent review with synthetic tests only. This supersedes the injected-
only source restriction for this slice; all execution holds remain. Builder,
persistent SQL and retained-resource transports remain pending. Actual executable
role profiles require immutable image Config observations and independent review;
no fixture image or supplied JSON fills that gap. Worst target-user failure is
false operational clearance or ambiguous resource creation. No application/schema
integration or production write is introduced; projected production WAL impact
is zero. Keep draft/disarmed/default-off/customer-blocked. Consumed build approval
and the withdrawn command remain unavailable.

`UnixJsonTransport(contract: dict, endpoint: str, *, clock=time.monotonic)` copies
and validates the operational contract through `controller_inputs.checked_inputs`
and requires its executing module digest in `source_references`. The endpoint is
explicit, absolute, ASCII, at most 100 bytes, with no NUL, control, dot/dot-dot,
duplicate slash or abstract socket form. There is no default endpoint, discovery,
CLI, application wiring, credential read or approval mechanism. Construction
reads local source fingerprints only; it performs no endpoint/socket/daemon I/O.
`snapshot() -> dict` includes the pairing and operational hashes; all execution,
profile, authentication, ownership and quiescence authority fields remain false,
issuer verification and independent review remain pending, and runtime evidence
is `pending-synthetic-transport-tests-only`. Do not return endpoint or peer content.

`request(method: str, path: str, payload: bytes, *, timeout: float) -> tuple[int, dict]`
implements the namespace adapter's existing callable transport interface. It
accepts only GET/POST/DELETE, bounded ASCII origin-form paths (1..8192 bytes)
without control/space/fragment/backslash, and exact bytes payload up to 16 MiB.
GET/DELETE require empty payload; nonempty POST payload must be strict UTF-8 JSON
object data (reject duplicate keys and nonfinite numbers). This client is a
framing boundary, not Policy admission: the namespace adapter still owns exact
method/path/body rewriting, identity, registration and cleanup. Do not weaken it.

Emit HTTP/1.1 with fixed Host localhost, Connection close, Content-Type
application/json and exact Content-Length. Never inherit headers, authenticate,
redirect, use shell/subprocess, open TCP, retry or negotiate an upgrade. Each
request opens one AF_UNIX stream in nonblocking mode and always closes it.
Use one finite, positive timeout (at most BUDGET.work_seconds) and one absolute
monotonic deadline across validation, connect, send, header/body reads and EOF.
Every readiness wait uses only remaining time. Reject backward/nonfinite clocks,
expired budgets and late completion. Bounded parsing has before/after deadline
checks; this is socket deadline enforcement, not Python parser preemption or
daemon/resource/network admission.

Responses require HTTP/1.1 final status 200..599, CRLF framing, at most 32 KiB of
headers, bounded header count and token-shaped field names. Reject duplicate
headers, folded/control-bearing fields, interim/upgrade status, upgrades, ambiguous
or absent nonempty framing, Content-Length plus Transfer-Encoding, unsupported
transfer/content encoding and contradictory bodyless statuses. Accept either
one canonical decimal Content-Length or exactly chunked transfer encoding.
Chunk sizes are bounded hexadecimal without extensions; bound chunk count and
line size; require exact CRLF after each chunk and an empty terminal trailer.
Total decoded body is at most 16 MiB. Status 204/304 requires empty framing and
empty body. Empty body returns `{}`; nonempty body requires application/json
(optional charset=utf-8), strict UTF-8 object JSON with no duplicate keys or
nonfinite numbers. Require EOF after the framed response, refusing trailing or
pipelined bytes. Do not normalize an array to an object or emit error body data.
Malformed/oversized/EOF/socket/clock failures raise `prepare.Refused` with fixed,
content-free messages and suppressed raw exception context. Return non-2xx
receipts unchanged for the adapter to refuse; never infer successful admission.

RED tests precede source implementation. Tests use synthesized temporary Unix
peers and deterministic socket/clock mocks only. Cover exact request bytes,
fragmentation, fixed/chunked/empty/non-2xx positive controls, malformed and
ambiguous framing, duplicate/nonfinite/deep/invalid JSON, contamination, bounded
headers/body/chunks, connect/send/header/body/EOF stalls and trickle deadlines,
zero/boolean/nonfinite/backward clocks, constructor I/O absence, closed sockets
after every result, one connection/no retry, source substitution and pending
authority fields. Peer threads are bounded, joined and checked for unexpected
errors. Include a meaningful guard-removal control with a behavioral assertion
failure, not an import/setup error. Synthetic socket evidence authenticates no
real daemon, profile, namespace, ownership, quiescence or image.
