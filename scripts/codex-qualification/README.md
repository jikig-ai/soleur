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

Operational completion remains pending: TLS/namespace orchestration, strict
per-role container environment/command review, source-bound full-schema SQL
scenario review, immutable built-image/filesystem/auth evidence, independent
review, and fresh exact-command approval. Keep the schema replacement forward
only, with no migration pre-marking or weakened production migration guard.
No claim of a complete or independently reviewed rehearsal is made here.
Hosted App Server authentication remains BLOCKED in both modes. A different
API-funded route remains PENDING. Default-off, draft/disarmed, customer-content,
credential, account/shared-write, deployment and cohort restrictions persist.
