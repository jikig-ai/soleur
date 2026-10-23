# Config-only acquisition proposal — 2026-10-20

Status: accepted as a source-only design; see the independent acceptance record
below. This is documentation only. It grants no transport implementation,
preparation or execution authority. PR #9051 remains draft/disarmed and
customer-blocked.

## Scope and evidence

This addresses the next gate in [the CTO ruling](prebuild-acquisition-2026-10-16.md#reviewed-redirect-evidence-and-next-boundary--2026-10-20).
The [separately reviewed diagnostic](redirect-framing-manifest-review-7764f6c9-2026-10-20.md#approved-attempt-and-separate-evidence-review--pass)
observed a redirect, without contacting its destination. Its approval and marker
are spent. The discarded Location cannot be reconstructed from its hashes.

The proposal concerns only `docker.io/axllent/mailpit`, `linux/amd64`, with
retained platform bytes of length 864 and SHA-256
`168f762c218e167ba88ae7e48194126eb5ba5e99ef652063e3f14f9c4f0ee70f`.
Its Config descriptor is `application/vnd.oci.image.config.v1+json`, length
2646, digest
`sha256:3f56e44ddc1a5655b8f288a2aa812db567b2f5f0b8bc18ef3da63b94a95608d5`.
No tag resolution, manifest refresh/expansion or layer request is proposed.

Primary documentation consulted on 2026-10-20:

| Source | Established fact | Limit |
| --- | --- | --- |
| [Docker Desktop allowlist, Domain URLs to allow](https://docs.docker.com/desktop/enterprise/allow-list/#domain-urls-to-allow) | Docker explicitly lists both `registry-1.docker.io` and `production.cloudfront.docker.com` for Docker Pull/Push. | Vendor documentation of service use; not publisher identity, ownership attestation or authorization for a particular URL. |
| [OCI Distribution current source, Endpoints](https://github.com/opencontainers/distribution-spec/blob/main/spec.md#endpoints) | Redirects are supported; cross-host Authorization forwarding is forbidden absent explicit configuration. | Mutable documentation; this proposal forbids forwarding without an override. |
| [OCI Distribution v1.1.1, Pulling blobs](https://github.com/opencontainers/distribution-spec/blob/v1.1.1/spec.md#pulling-blobs) | Blob responses should be checked against the requested digest. | Digest agreement establishes content integrity relative to the retained descriptor. |
| [OCI Image v1.1.1, Config properties](https://github.com/opencontainers/image-spec/blob/v1.1.1/config.md#properties) and [Config schema](https://github.com/opencontainers/image-spec/blob/v1.1.1/schema/config-schema.json) | Define the image Config structure. | Neither schema nor digest validates effective runtime policy or publisher provenance. |

Inference proposed for independent acceptance: Docker's explicit exact-host
listing plus the reviewed registry observation justify considering **only**
`production.cloudfront.docker.com:443` for one fresh, pinned Config request.
They do not justify a suffix wildcard, another CDN or a permanent allowlist.
Recheck the primary listing before implementation review and actual-manifest
review; withdrawal or contradictory evidence stops that chain. The historical
path lacking the literal digest neither establishes a mismatch nor waives
the response's exact byte/digest checks.

## Proposed finite action

After separate authorization, one new action would contain at most three
ordered, bodyless HTTPS GETs. No request may start before the fresh one-use
gate is consumed and all local bindings pass. Every failure ends the action.

| Order | Fixed origin and purpose | Required result and permitted reading |
| --- | --- | --- |
| 1 | Existing anonymous `auth.docker.io` token endpoint, service `registry.docker.io`, scope `repository:axllent/mailpit:pull` | HTTP 200; bounded token JSON in memory only, with the reviewed token framing contract. No challenge discovery. |
| 2 | `registry-1.docker.io:443`, `/v2/axllent/mailpit/blobs/sha256:3f56e44ddc1a5655b8f288a2aa812db567b2f5f0b8bc18ef3da63b94a95608d5` | HTTP 307 and exactly one valid bounded Location; header-only reading, close without reading its response body, including on error. |
| 3 | Fresh Location from request 2, exact accepted host `production.cloudfront.docker.com:443` | HTTP 200 only; bounded Config reading and validation below. Every other status closes header-only, including another redirect or auth challenge. |

The manifest must pin the complete token/registry URLs, request order, methods,
headers, budgets and destination predicate. The fresh signed destination URL
is deliberately absent from the manifest; its in-memory derivation is bound
to request 2 and the exact-host predicate. There is no retry, HEAD probe,
Range/resume, reconnect, alternate host/address attempt, daemon contact,
Docker credential helper, cache or automatic follow-on. Registry HTTP 200
instead of the required 307 stops without reading a Config body.

## Credential and network isolation

Construct each request from a closed header allowlist; do not copy a prior
request object. The anonymous bearer goes only to request 2. Request 3 receives
only its exact Host, fixed Accept, `Accept-Encoding: identity` and
`Connection: close` headers. No Authorization, Proxy-Authorization, Cookie,
Referer, client certificate or ambient credentials are available to it.
Treat its query as a capability: preserve path/query bytes for the request,
but retain neither in argv, environment, logs, exceptions, files or receipts.

Require an absolute ASCII HTTPS Location no longer than 4096 bytes, a nonempty
absolute path, and an authority equal to the exact lowercase hostname with
port absent or literally `443`. Reject userinfo, fragment (even empty), control
characters, whitespace, backslashes, non-ASCII/IDNA host spellings, trailing
dot, percent-encoded authority, IP literals and alternate port spellings.
Reject malformed percent escapes; never decode/re-encode the signed path or
query. Parse and validate before any destination DNS lookup or connection.

Use direct numeric-address sockets, with no HTTP CONNECT/SOCKS/proxy discovery,
`.netrc`, Docker/account configuration or environment-selected CA substitution.
Apply address checks to **all three** exact origins. Resolve each name once
with a bounded resolver operation under the shrinking request deadline; cap
the returned address set at 16. Refuse an empty, malformed, over-budget or mixed
safe/unsafe set. Accept only AF_INET/AF_INET6 stream endpoints on port 443 with
globally reachable unicast addresses; explicitly reject private, loopback,
link-local, unspecified, multicast, reserved, scoped IPv6, IPv4-mapped IPv6
and transition/tunnel forms. Select one address deterministically from the
validated set; connect once to that numeric address, never resolve again or
try a fallback. Require `getpeername()` to equal that selected address/port
before TLS and before sending HTTP bytes. Bind the connection to that socket.

Python's [`ipaddress` reachability flags](https://docs.python.org/3.14/library/ipaddress.html#ipaddress.IPv4Address.is_global)
are version-sensitive and `is_private == false` alone is insufficient (shared
address space is a documented counterexample). Pin interpreter/version and
the complete address predicate; test explicit deny ranges. A worker that runs
an uncancellable resolver is insufficient: the proposed resolver helper must
be bounded, reaped and excluded from secret-bearing state. Its actual design
requires independent source review before preparation.

Create the TLS context exclusively from the hash-bound CA bytes. Require
certificate-chain and hostname verification, TLS >=1.2, and SNI equal to the
fixed origin hostname, irrespective of numeric peer/CNAME. No extra default
CA loading, proxy trust, disabled verification or exception-based fallback.
[`SSLContext.wrap_socket`](https://docs.python.org/3.14/library/ssl.html#ssl.SSLContext.wrap_socket)
documents SNI and ragged EOF behavior; require `suppress_ragged_eofs=False`.
DNS/peer checks constrain addressing; TLS authenticates the service hostname
to the pinned trust store. Neither authenticates the image publisher or
defeats a hostile host administrator/routing infrastructure.

## Config validation and non-admission

Proposed destination framing policy is deliberately narrower than the token
parser: HTTP/1.1, exactly one decimal Content-Length equal to 2646, no
Transfer-Encoding, and no Content-Encoding except absent or single `identity`.
Require one Content-Type of `application/octet-stream` or the pinned OCI
Config media type, without parameters. Reject ambiguous/duplicate framing,
interim responses, extensions and unsupported encodings before body reading.
Read precisely the framed 2646 bytes under a 2646-byte allocation ceiling,
then close; do not wait for EOF after framed completion or read beyond the
declared frame. This proves the selected frame's count, not absence of unseen
connection bytes. Short/truncated frames fail. A different framing shape
requires another source-only ruling, never an automatic compatibility retry.
This constrained policy follows [RFC 9112 framing](https://www.rfc-editor.org/rfc/rfc9112.html#section-6.3).

Hash the untouched entity bytes before JSON parsing. Require exact descriptor
length and SHA-256 above, independently of Content-Length and any server digest
header. A present Docker-Content-Digest must be unique and equal to the pinned
digest. Decode strict UTF-8 without BOM; reject duplicate keys at every depth,
non-finite numbers, trailing data, non-object root and nesting deeper than 32.
Never hash a normalized/re-serialized JSON substitute.

The normative OCI v1.1.1 Config prose takes precedence over its supplied JSON
schema: prose permits every optional field to be null, whereas the schema
rejects null for some optional fields. The schema is a structural reference,
not an unmodified conformance oracle. The local contract is
`oci-config-v1.1.1-normative-null-v1`: treat optional null as absent for typing,
preserve its distinction in memory, and require paired omitted/null/invalid-type
tests for each known optional field. Pin the complete local reference closure,
including schema definitions, with no remote `$ref` fetch or package install.
Require `os == linux`, `architecture == amd64`, a `rootfs` object with
`type == layers` and string `diff_ids` in digest syntax. Type-check known
execution/history fields; distinguish missing/null optional values from
observed values. Check `diff_ids` count against retained platform layer count,
without equating compressed layer digests with uncompressed DiffIDs or fetching
either. Unknown extension fields remain inert and do not grant authority;
bound their parsing with the same byte/depth limits. Preserve optional
absence/null, which OCI permits. The future local validator and reference
bytes must be pinned and reviewed; the current dict/platform check is not
full schema validation. Do not execute Env, labels, Entrypoint, Cmd or history.

An acquisition receipt would assert only byte/digest/schema observations under
the closed contract below. Config field values, names, presence/type maps,
labels, environment and history are unretained; actual field-value profiling
needs a separate proposal. Evidence review cannot reconstruct Config contents
from this receipt. Memory-only handling cannot promise physical zeroization
or defeat privileged process inspection; prohibit core dumps and secret-bearing
child processes, minimize lifetimes and discard buffers on every exit.
Publisher/issuer/ownership verification remains pending, and all profile,
runtime, recovery, hosted-auth and qualification authority remains false.

## Closed receipt contract

All fields are required, no additional keys at any depth. Integers exclude
booleans. A SHA-256 is exactly 64 lowercase hex characters. Construct each
object from constants and vetted scalar results; never merge untrusted JSON.
Null check results mean not measured, never passed. Reject an invalid receipt
before publication; keep the spent marker and report a fixed local failure.

| Field | Exact type and bounds |
| --- | --- |
| `schema` | Constant `config-acquisition-receipt-v1`. |
| `schema_contract` | Constant `oci-config-v1.1.1-normative-null-v1`. |
| `bindings` | Object with only `source_head` (40 lowercase hex), and SHA-256 fields `manifest_canonical`, `runner`, `operational`, `image_inputs`, `retained_manifest`, `ca`, `platform`, `schema_reference_closure`, `marker`. All equal the reviewed local bindings. |
| `expected_config` | Object with only `media_type` (pinned OCI media type), `size` (2646), `digest` (full pinned `sha256:` value above). Constants, never echoed from a response. |
| `output_identity` | Object with only `device`, `inode` (integers 0..2^64-1), `uid` (0..2^32-1), `mode` (constant `0700`); must equal the bound directory identity. |
| `status` | `complete` or `refused`. |
| `stage` | `preflight`, `token`, `registry`, `destination`, `validation`, `complete`. |
| `failure` | Null or one fixed code: `binding`, `output`, `replay`, `deadline`, `dns`, `peer`, `tls`, `headers`, `status`, `token`, `location`, `body`, `digest`, `schema`, `internal`. |
| `request_count` | Integer 0..3, incremented immediately before each attempted HTTP send. |
| `actions` | Exactly three objects in token/registry/destination order. Each has only `role` (the corresponding constant), `http_status` (null or integer 100..599), `peer_ok`, `tls_ok` (boolean or null). Unattempted stages may report peer/TLS outcomes but no HTTP status. |
| `config_checks` | Object with only `bytes_read` (integer 0..2646), `length_ok`, `digest_ok`, `schema_ok` (boolean or null). No observed wrong digest or schema details. |
| `authority` | Object with only `destination_ownership`, `publisher_verified`, `issuer_verified`, `profile_admitted`, `runtime_authorized`, `recovery_authorized`, `hosted_auth_cleared`, `qualified`; every value is constant false. |
| `review` | Constant `pending`; separate review never rewrites this receipt. |
| `receipt_sha256` | SHA-256 of canonical JSON of every other field, using sorted keys, ASCII encoding, compact separators, no NaN. Integrity checksum, not authentication. |

`complete` requires count 3, statuses 200/307/200, every peer/TLS check true,
bytes_read 2646, all Config checks true, stage complete and failure null.
`refused` requires a non-null failure and a non-complete stage; later stages
cannot report HTTP status after a refusal. Tests must cover contradictory
combinations, additional nested fields and secret canaries on every failure
path. No arbitrary strings, Config keys, unknown-field counts, JSON paths,
validation messages, addresses, header values or exception text are retained.
The manifest alone holds executable paths/versions and reference inventory;
their receipt binding is its canonical hash.

## Budgets, outputs and observability

Retain the 60-second absolute overall budget, ten seconds per request (including
resolution/connect/TLS/headers/body), and a separately approved 90-second outer timeout
with five-second kill grace. Limit each header block to 16,384 bytes and 100
fields; preserve the existing 16,384-byte token decoded-body ceiling. No phase
resets a deadline. Source tests must exercise stalled DNS as well as trickling
TLS/body reads. Preparation must remain file-only and cannot consume a marker.

Require fresh committed source/dependency references, operational/input/retained
manifest/platform/Config/CA bindings and descriptor-relative no-follow private
output checks. Record executable paths/versions with the attestation limits
explicit, rather than claiming unmeasured binary/shared-library integrity.
Use a fresh 0700 owner-controlled output directory and exclusive 0600 manifest,
marker and sanitized receipt. Failure after gate consumption is spent too.
Historical manifests, markers and receipts remain untouched.

## Observability

- Layer: local bounded CLI and private receipt, no production telemetry surface.
- Signal: the closed receipt's binding hashes, request count/status,
  exact byte/digest/schema results, peer-policy result and
  fixed failure category; authority flags false and review status pending.
- Failure coverage: URL/DNS/peer/TLS/header/body/schema refusal is reported by
  the local receipt layer, with sanitized partial stages and a spent marker;
  outer timeout may leave only the marker, which is incomplete, never success.
- Owner: coordinating agent obtains separate evidence review before any use;
  receipts exclude raw URLs, queries, headers, bearer, Config and exception text.
- Discoverability test: after separate implementation authorization, offline
  synthetic tests of the actual prepare/execute path under an explicit timeout;
  the exact test command is a prerequisite for source review, currently pending.
  No SSH, daemon, provider or acquisition request is part of that test gate.

## Acceptance chain and stop boundary

Worst target-user failure: a falsely cleared unrelated resource could later
cause unintended disclosure or modification. A sensitive Location/bearer
could also leak through exceptions or evidence. Keep the resulting receipt
inert, with no automatic profile admission, executable configuration or user
resource access.

1. Independent engineering/security review accepts or rejects this proposal,
   including the primary evidence, exact host, resolver/peer design, schema
   boundary and minimized receipt. Record the decision and dissent here.
2. Obtain authorization for source-only implementation and boundary tests.
   The proposal itself does not grant it. Write failing synthesized tests first:
   request ordering/count; no body on registry/errors; malformed/host-confused
   Locations; credential canaries; unsafe/mixed DNS and rebinding; mismatched
   peers; TLS/SNI/CA and proxy refusal; DNS/TLS/body deadlines; exact byte/digest
   failures; duplicate/deep/malformed JSON and schema null/extension cases;
   one-use/no-follow/output replacement; sanitized failures and cleanup.
   Mutation checks must demonstrate that removing each security guard fails
   its test. No test may contact a real origin.
3. Independently review new transport/security source and tests; then separately
   authorize file-only preparation of a fresh unused actual manifest. Review
   its exact bindings and fully expanded bounded command before presentation.
4. Obtain fresh exact-command execution approval. Execute once only; preserve
   success/failure evidence and obtain a separate independent evidence review.
5. Only a later explicit ruling can admit evidence or revise the remaining
   profile/recovery/qualification chain. Acquisition success alone releases none.

No new transport code, test implementation, action manifest, marker or receipt
is created by this proposal. Main resync/full CI, all build/Docker/SQL/provider/
browser/account operations, recovery, qualification, permitted Web/CLO matrices,
full branch review/QA/preflight, promotion and ship remain held. Hosted auth
is BLOCKED and alternate route PENDING. This record is live planning material;
archive with the other artifacts before any eventual PR-ready/merge action.

## Independent proposal acceptance — 2026-10-20

Reviewed design source: pushed `b7bd072a877279932df5e083cc06fb4c94774481`.
This section records subsequent review; it changes no design requirement.

Security independently verified the primary Docker listing and conditionally
accepted the exact destination for this one-shot boundary. Initial review at
`f6cd79cc03` found two medium design blockers: OCI optional-null/schema
precedence and an undefined receipt projection. Narrow re-review at
`b7bd072a87` passed both corrections, with no blocking contradiction found.
The closed contract deliberately excludes even Config field presence maps.

Ruled by CTO agent, 2026-10-20: accept the source-only design at
`b7bd072a87`, including exact `production.cloudfront.docker.com:443`, normative
OCI null handling, closed receipt and restrictive Content-Length-only policy.
Docker's primary listing and the reviewed registry observation support the
limited delivery-service inference; digest/schema checks remain separate from
publisher provenance. No implementation, preparation or execution authority
is granted. Rejected alternatives are wildcard/automatic redirects, credential
forwarding, ambient trust/proxy substitution, address/framing fallback and
historical approval replay. Dissent: actual CDN framing, Config compatibility
and resolver/transport enforcement remain unverified; a future attempt may
safely refuse, with no retry permission and no admission/qualification effect.

The next operator authorization action is permission to implement only transport
source and synthesized offline boundary/mutation tests. It excludes real-origin
requests, action manifests, markers and acquisition. Subsequent source review,
separately authorized preparation, actual-manifest review, exact-command approval
and separate evidence review remain mandatory and distinct.

These are scoped proposal reviews, not full branch review, QA or ship clearance.
Reviewers made no file changes or origin probes; they read source/documents and
consulted public primary documentation. This session changed Markdown only.
Whitespace and staged secret checks passed; local linked file targets exist.
The repository Markdown lint selector excludes these planning/learning paths,
so it performed no lint of their contents. Its user-Ruff adapter reported
not adopted; no adoption or source/test/build run was attempted for this prose
delta. The historical 329-test result is unchanged, not rerun by this session.
GitHub's push warning was checked against open Dependabot alerts: 270 and 273
both name the existing moderate `sprintf-js` advisory `GHSA-hp3w-g68c-fv3c`;
no dependency was changed. Full CI is not established and main remains
conflicting; resync is not performed by this proposal-only scope.
