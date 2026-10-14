# Offline Codex qualification preparation

This directory prepares a paired production-image and full-schema rehearsal
contract. It has no build, download, Docker, application-start, SQL, browser-login
or provider-execution command. The production runtime stays closed. The withdrawn
October 11 runner is never imported or invoked.

`prepare.py --repo <worktree> --source-sha <full-HEAD-SHA> --preview` reads only
committed Git blobs and prints content-free preparation metadata. It binds the
full production input set, original and controlled Dockerfiles, every complete
forward migration, committed preparation components, pinned CLI executable
digest, and a matching local synthetic browser-auth contract. A dirty preparation
package refuses preview until its bytes are committed.
Compilation receives four network-disabled directives; production URL/JWT
validators are preserved. The image receipt validator rejects missing or
mismatched source, schema, browser configuration, image ID, default user,
entrypoint or local synthetic authentication evidence. A receipt check alone
does not authorize execution or authenticate a receipt's issuer.

The generated browser key is deterministic public fixture material, signed for
a future owned local Supabase stack. Preview includes its fingerprint and claims,
never its token or signing material. Its canonical-shaped synthetic hostname
requires private namespace resolution to an owned TLS proxy and task-scoped CA
trust in both renderer and browser. No host DNS or global trust change is
permitted. External routing must be absent before this hostname or key is used.
The [pinned CLI authentication configuration](https://github.com/supabase/cli/blob/v2.84.2/pkg/config/auth.go)
defines local `jwt_secret`, `anon_key` and `service_role_key` fields;
the [pinned service launcher](https://github.com/supabase/cli/blob/v2.84.2/internal/start/start.go)
composes that local configuration. This source evidence does not establish an
executed stack, a TLS proxy, or successful login. Fixture material expires on
October 19, 2026; a later attempt requires a freshly reviewed contract.

The API policy and Unix proxy are testable boundary components. Resource names
are reservations. Container and network operations resolve successfully returned
IDs. Volumes require an observed 404 before creation and a successful local
creation receipt; cleanup rechecks labels, driver, scope, timestamp and mountpoint.
Network cleanup rechecks its ID, labels and isolation. Failed attempts enter a
controller-only cleanup phase that permits registered inspection/deletion for
five minutes, while refusing new execution. Unknown host privilege fields,
ambiguous paths, duplicate query fields, provider/loader overrides and elevated
exec requests are refused. A Docker-host administrator can still race or alter
resources; these components do not establish host-admin isolation.

Focused review additionally requires a registered network before container
creation, rewrites attachments to its returned ID, and revalidates network and
volume receipts immediately before attachment/mounting. Reserved volumes cannot
be mounted. Logging is forced to a bounded local json-file configuration;
daemon-side remote logging overrides are refused. Blank duplicate query values
are retained and refused. Image receipts must include the inherited pinned-base
`docker-entrypoint.sh` entrypoint as well as the application command.

`bash scripts/lib/codex-qualification.test.sh` runs source pairing, actual
production browser-validator, ownership, collision, privilege, failure-cleanup
and HTTP upgrade fixtures. The transport fixtures contact only temporary fake
Unix backends. The wrapper is covered by the existing `scripts/lib/*.test.sh`
suite declaration. Python and Node with TypeScript stripping are required;
missing tools fail the suite instead of silently skipping it.

The wrapper uses `python3 -E -B` so inherited optimization/module variables cannot
erase fixture assertions or redirect imports, and bounds each module to 120
seconds. Transport marker reads fail on early EOF, deadline or oversized output.
All fake backend/proxy thread-error inventories are checked during cleanup.

The new `local_tls.py` and `namespace.py` provide callable TLS/DNS boundaries
and namespace recipes. Synthetic TLS sockets test real CA/SAN/SNI/Host refusal;
they do not establish container DNS/route isolation or browser authentication.
TLS and DNS use non-root roles with only the exact namespace low-port sysctl.
Browser trust recipes scope NSS to a separate owned HOME and browser profile.
No component changes host DNS or global trust.

`role_profiles.py` requires exact controller-owned role profiles before creation
or exec. The proxy rechecks the complete inherited immutable image Config and
materialized volume mounts before creation. Missing profiles, role/image/name
confusion, changed command/environment/user/directory, aliases, ports, DNS,
mounts and unknown top-level fields refuse. Exec admits exact recipes and no
stdin, including upgrade streams; SQL/script inputs need read-only mounted,
source-bound files. `fixture_roles.py` contains synthetic test profiles only;
these must never be used as production service profiles. The seven upgrade
checks now exercise output-only exec. Historical bidirectional fixtures no
longer describe the current execution admission.

`rehearsal.py --repo <worktree> --source-sha <full-HEAD-SHA> --preview` binds
all committed complete forward SQL bodies, the canonical runner, production
guard and eleven scenario artifacts (ten committed plus the derived ledger
census). A fresh-schema defect in the canonical runner was fixed: ledger column
availability is checked after each body inside its atomic transaction, so
pre-054 rows stay unhashed and subsequent rows carry their original blob hash.
No migration body or production guard changes. SQL remains unexecuted; the
prepared race requires observed holder/waiter blocking, not elapsed time.

Operational completion remains pending: actual role image/config profiles,
TLS/namespace orchestration and observations, retained storage/workspace file
byte manifests, session race controller, immutable built-image/filesystem/auth
evidence, independent review, and fresh exact-command approval. Keep the schema replacement forward
only, with no migration pre-marking or weakened production migration guard.
No claim of a complete or independently reviewed rehearsal is made here.
Hosted App Server authentication remains BLOCKED in both modes. A different
API-funded route remains PENDING. Default-off, draft/disarmed, customer-content,
credential, account/shared-write, deployment and cohort restrictions persist.

`candidate.py --repo <worktree> --source-sha <full-HEAD-SHA> --directory <fresh-task-directory> --assemble`
exports the exact committed full-production context and complete vendored plugin
using no-follow descriptor-relative writes. It preserves the original Dockerfile
and writes the controlled one separately. Every exported byte/mode/link and the
file inventory are checked before a preparation receipt. `--preview` writes
nothing and prints metadata only. Both modes bind the executing preparation
source; existing or escaping destinations refuse. No Docker or builder command
is executed. The saved recipe contains only public synthetic browser build
values and proposes a clean HOME/Docker configuration. It remains explicitly
unreviewed for builder/daemon, dependency network and resource admission, and
grants no build/rehearsal authorization. It is an exported candidate context,
not a built or authenticated production candidate.

`operational.py` prepares source-bound builder, role, namespace, retained-file,
session and evidence requirements. Builder/daemon identities, dependency-route
enforcement and concrete executable role profiles remain pending. Service names
or fixture images cannot fill those slots. Supplied build/image/filesystem/
namespace/auth JSON is checked for consistency and expiry, with issuer verification
and runtime authority explicitly pending. No operational adapter or execute CLI
is added.

`retained_files.py` measures complete synthetic file and directory inventories
from an already opened descriptor, binding root device/inode and rejecting links,
special files, mount escapes, unstable reads and count/byte overruns. Comparison
requires exact retained path/type/mode/size/digest entries or an exact erased-path
set. The future adapter must establish registered root/resource ownership and
writer quiescence; this helper cannot authenticate supplied bindings. Tests read
only fresh synthetic scratch files and emit no content bytes.

`session_controller.py` sequences injected holder/waiter observations by attempt,
database, backend/process PIDs and birth identities. The exact blocking dependency
precedes a single commit recipe, explicit commit observation, waiter zero exit
and source-bound assertion. Failure/EOF/deadline prevents success and commit;
rollback/close recipes expire permanently after five minutes. Recipes grant no
execution authority and never reopen exec stdin. A persistent owned SQL adapter
and real observations remain pending. See the
[operational preparation record](../../knowledge-base/project/specs/feat-one-shot-codex-web-live-paths/operational-controller-preparation-2026-10-13.md).

`controller_inputs.py` checks source-bound profile specifications against separate
supplied review and complete image Config/reobservation references. All eleven
roles use exact attempt reservations. Effective recipes must include all inherited
environment keys and complete create/host fields. Builder specifications bind the
candidate recipe, argv, replaced environment, exact dependency-route digest census
and resource limits. Adapter requirements describe builder, namespace, persistent
session and retained-file interfaces without constructing a transport. Retention
checks join separate registered resource/root, owner/database and writer references
to ordered quiescence windows covering complete before/after manifests. These
supplied references establish consistency only; executable profiles, adapter
runtime wiring, ownership/quiescence verification, issuer authentication and
approval remain pending. Results contain fingerprints and pending status, with
no returned executable profile recipes. See the
[controller-input preparation record](../../knowledge-base/project/specs/feat-one-shot-codex-web-live-paths/controller-input-preparation-2026-10-13.md).

`controller_adapters.py` adds callable builder, namespace, persistent-session and
retained-file adapters after the operator expanded implementation scope. All
transports are injected; no production transport, CLI or approval mechanism is
provided. Constructors call no transport and copy reviewed inputs. Every request
and response is checked around bounded callback deadlines. Matching references
and fake responses establish consistency only; returned summaries retain false
execution/profile/authentication/ownership/quiescence authority and pending
issuer verification and independent review.

The builder validates the export descriptor against the reviewed recipe directory
and checks the exact source-plus-metadata leaf inventory, including the empty
Docker config at mode `0600`, before one injected attempt. Namespace operations
preserve `Policy` rewrites and successful-registration ownership, reobserve
resources/configurations, reject duplicate IDs, and require running prerequisites.
Session calls use only source-bound scenario bytes and existing identity-bound
handles, with explicit lock observation before commit and a 30-second deadline.
Retained collection owns only returned descriptors and matching quiescence leases;
it reobserves root/writers, encloses collection in supplied observation windows,
and compares full inventories for retention or scoped erasure. Cleanup is bounded,
preserves the primary error and does not retry ambiguous deletes or session closes.

Runtime admission remains absent. Filtered volume absence and supplied writer
censuses do not prove global absence or completeness; concrete transports must
obtain independently reviewable observations. Export identity checks do not lock
context writers. Passing remaining timeouts and refusing late responses cannot
preempt a blocking callback or enforce daemon/network/resource limits. Those
controls, actual immutable Config observations/reobservations, authenticated
provenance, concrete profile/transport review and fresh exact execution approval
remain prerequisites. No build, SQL, login, provider or recovery operation ran.
See the [implementation record](../../knowledge-base/project/specs/feat-one-shot-codex-web-live-paths/controller-adapter-implementation-2026-10-13.md).

`controller_transports.py` supplies a dormant Unix JSON HTTP client after the
October 14 source-only authorization. Its endpoint is explicit, construction
opens no socket, and no CLI, discovery or production activation is provided.
One nonblocking connection uses an absolute deadline for validation, connect,
send, headers, framed body and EOF; framing, JSON, nesting and chunk counts are
bounded. Failures close the socket without retries and expose fixed messages.
Python parsing has bounded inputs and before/after deadline checks; it is not
preempted. The namespace adapter continues to own Policy admission and resource
registration. Socket deadlines establish no daemon/network/resource enforcement,
profile, image, ownership, quiescence, issuer authentication or execution approval.
Synthetic peers and deterministic mocks supply the test evidence only.
`image_observations.py` adds a finite one-pass collector for explicitly supplied
immutable role image IDs. It deduplicates exact `GET /images/<id>/json` requests,
checks complete bounded inherited Configs, shares one shrinking deadline, and
keeps profile admission, issuer verification, ownership and execution false.
Its exclusive mode-0600 manifest writer creates only the exact GET request list;
it never runs those requests. No real image was observed. Builder, SQL-session
and retained-resource transports, actual image Configs/profiles, independent
review and fresh exact-action approval remain pending. See the
[transport record](../../knowledge-base/project/specs/feat-one-shot-codex-web-live-paths/namespace-transport-implementation-2026-10-14.md).
