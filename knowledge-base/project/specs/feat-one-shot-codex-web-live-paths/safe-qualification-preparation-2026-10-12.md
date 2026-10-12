---
title: "Current-source local-auth candidate and full-schema preparation"
date: 2026-10-12
pr: 9051
source_sha: 09bf6a4f68053db6405d75174d22f53a0d818d1b
status: offline-prepared-operational-orchestration-and-independent-review-pending
---

# Safe qualification preparation

The [active plan](../../plans/2026-09-27-feat-codex-web-live-handler-wiring-plan.md)
continues within the operator's execution restrictions. Main through
`0dc19ef389e9a8f064fa5837bfecc911cc7c941c` merged cleanly at the source above.
Its thirteen-path change contains infrastructure and evidence, with no runtime
application or lockfile change. The static Inngest contract suite passed 451/451
and the fake-log rehearsal-capture suite passed 36/36. No infrastructure dispatch
or C.9 runtime ran. The newly prepared code is outside the production runtime.

## Paired candidate and schema contract

[Preparation source](../../../../scripts/codex-qualification/README.md)
is committed and reproducible; it replaces ignored preparation-only scratch as
the source of the new boundary components. It does not import the withdrawn
runner, reuse a consumed marker, or expose an execution command.

At the source above, the offline preview admitted **5,035** complete tracked
production/plugin inputs and **187** complete forward migrations. Counts are
derived by `prepare.py` from `git ls-tree -r -z <source>`, with forward migrations
defined as all SQL bodies under the migration directory except paired `.down.sql`
files. Git blob, SHA-256 and byte count are bound for every input. There is no
handwritten migration closure, pre-marking, SQL substitution or production-guard
relaxation. An unchanged canonical migration runner is required for a future
forward-only retained-schema replacement.

| Bound input | SHA-256 |
|---|---|
| Full runtime input manifest | `efbfac64fc69e523f47bebf9a4f27d3ec66ea5c0afc4cbabb16877aba9ae40cc` |
| All forward migration bodies | `f9ee94557aebc5f0fe83f894c84b3814891873871d0c363a2afe0963a524f219` |
| Local browser-auth contract | `f29752e9e93512ca5fa2e9c0107b9898dbaee580a8ed431017b8cf1d693c8c93` |
| Original production Dockerfile | `da6105549a2b1cb94fedab8257e4c4f0e325d9c15e1e08a9982febf8c6696ca0` |
| Dockerfile with four compiler network controls | `ec0475961448d6b24ea32cd6d8476359fcd66b05ce2d9e1b35597b7d5070723c` |
| Source/schema/auth pairing | `ad8d7ecacccf48afb8c562661edf2dd1942cf2beeb8ef6003786d33f2d7fc992` |

These are preparation fingerprints, not built image or execution evidence.
The pairing includes the exact source SHA; subsequent source commits require a
fresh preview even when production input hashes stay identical.

The fresh browser design uses an anonymous JWT signed with generated public
fixture material for an owned local Supabase stack. It passes the **actual
unchanged production URL and anonymous-key validators**. The previous loopback
URL and build-only placeholder key fail those same guards. Only key fingerprints
and synthetic claims enter preview output; no account key or signing value is
retained in this record. The [pinned CLI auth configuration](https://github.com/supabase/cli/blob/v2.84.2/pkg/config/auth.go)
and [service launcher](https://github.com/supabase/cli/blob/v2.84.2/internal/start/start.go)
support the local configuration fields used by this design. A canonical-shaped
fixture hostname must resolve exclusively to an owned local TLS proxy in private
renderer/browser namespaces, with no external route and only task-scoped CA trust.
TLS/namespace orchestration remains unimplemented and unexecuted. No global DNS
or trust mutation is proposed. Fixture expiry is October 19, 2026.

## Boundary repairs and verification

Container names remain reservations; operations resolve registered IDs returned
by successful creation. Networks now follow the same ID rule. Volumes require
an observed absence before their first creation and a successful owned receipt.
Removal rechecks live volume provenance and network identity/isolation. A failed
attempt can enter a controller-only cleanup phase without reopening execution.
Unknown container host privilege fields, duplicated query fields, absolute API
paths, provider/loader environment overrides and elevated exec requests are
refused. This does not isolate resources against a Docker-host administrator.

The registered offline wrapper passed: 18 creation-policy checks, 51 ownership/
exec checks, nine resource-policy tests, 12 foreign-name collision checks, seven
HTTP upgrade checks, seven resource-transport tests and six preparation tests.
It uses only synthesized inputs, source Git reads, leaf Node validators and
temporary fake Unix backends. No Docker daemon, application, database, browser
login, account credential or provider was contacted. The actual validator test
used host Node 26.11.1 and does not attest production Node/dependency parity.

New ownership/transport tests first failed against the inherited prototype.
Five syntax-valid mutants then failed the actual suites after removing volume
removal ownership, network ownership, host-field admission, volume receipt
comparison or source/schema/auth image pairing. Source pairing, actual validator
and later cleanup checks were not all authored test-first; no universal TDD or
independent-review claim is made.

The fixture ratchets passed 62/62 and 71/71. Shell capture/credential refusal
lints and whitespace checks passed. Required SAST remains VOID; Ref #10082 was
verified OPEN. Ref #9791 was verified OPEN/unverified; no current-source C.9
rerun or root-cause clearance is asserted.

## Review and remaining execution gates

The candidate specialist hit the harness usage limit. A second delegated task
remained pending initialization and was interrupted before doing work. Root
performed sequential source/security/test-design examination and corrected
socket cleanup plus a fake HTTP 204 body that caused a thread-side BrokenPipe.
Thread failures are now recorded and asserted by the transport fixtures. No
independent assessment, new CTO ruling, full panel or review completion occurred.

The preparation contract is intentionally **not an approval-ready runtime
command**. A runnable auth-capable production candidate and fully reviewed
full-schema orchestration remain incomplete. Required work includes the owned
TLS/namespace implementation, per-role container command/environment admission,
current-source scenario SQL review, immutable image/filesystem/local-auth receipt
and independent review. Only then may a fresh exact build/rehearsal action be
presented for explicit authorization. No authorization was requested or consumed
here. The withdrawn command remains unavailable.

The [October 12 CLO supplement](../../../legal/audits/2026-10-12-codex-web-hosted-auth-restriction.md)
still blocks planned hosted App Server authentication in both modes; a separately
specified API-funded alternative remains PENDING. Local synthetic Supabase
browser preparation does not authorize provider authentication. No eligible
routine exists. Current-source recovery → authenticated screenshots → eligible
routine → permitted Web/CLO matrices → full review/promotion remains open.
Keep draft, auto-merge off, Codex default-off and customer content blocked.
Credential/provider/browser-auth, account/shared-write, deployment and flag/cohort
restrictions persist. Project sharing, retention/inheritance and configured
regions remain unresolved. Fresh pushed-head CI and description guards are owed.

## Subsequent main sync and component binding

The previous fingerprints are historical. During preparation, main advanced
nine commits to `6a01e728cf416a9bb5f90eb150270ec3a7ec4fd3`, merged at
`0691158c2016928f802d699d3d3efb7664e0c24b`. The sole conflict was the affected
test index; the resolution preserves both main's mint/audit declarations and
the qualification declaration. The diff against main contains only the added
qualification declaration at that site. This main delta includes application,
redaction, teardown and forward-schema changes; previous runtime hashes do not
qualify it. The fresh preview derives **5,039** runtime inputs and **188** forward
migrations, with source SHA and content fingerprints changed accordingly. Its
schema fingerprint is `baeb4ee9428e8187d98743d6fe84dd84a20c98162a5440f140df9891edc9f172`.
The owned browser contract and both Dockerfile hashes are unchanged.

The preparation suite passed again on this merged source after repairing an
empty HTTP 204 write and ensuring fixture cleanup precedes thread-error
assertions. The registration census passed: 669 tracked suites covered, zero
orphans. A preview with an incorrect supplied SHA refused before manifests;
it was repeated with the full SHA read from Git. The contract now also binds
all committed preparation components and the pinned CLI executable digest;
dirty preparation components refuse CLI preview. Fresh final-head fingerprints
are generated after commit. No operational command, image or independent review
was supplied by this sync. Hooks remain disabled at `/dev/null`; no hook pass is
claimed. The application matrix/full panel and all earlier execution restrictions
remain incomplete.

## Focused independent review and corrections

After the capacity reset, the security-sentinel independently reviewed pushed
head `030275281d747227338cfd2e5fd71e1219914979` and returned five dormant
preparation findings. Test-design independently reported three concrete fixture
issues before its final turn failed on model capacity; no complete score or
full test-design verdict is attributed to that turn. These are focused component
reviews, not the full PR panel or operational rehearsal approval.

Reserved-volume mounting now requires a successful receipt and reinspection.
Containers require a registered network, attach by its returned ID and recheck
isolation before creation. Arbitrary daemon logging overrides are rejected and
local log output is bounded. Duplicate query names with blank values are refused.
Image receipts must match the known inherited entrypoint, not just `Cmd`.
New policy tests failed five cases against the old bytes; the entrypoint test
also failed before correction. The fake transport now exercises successful mount
plus stale-volume and changed-network denial before creation.

The wrapper ignores Python environment settings and disables bytecode output;
each module has a 120-second ceiling. Collision fixtures check every proxy's
thread-error inventory. Marker reads now reject early EOF and oversized output,
with three pure helper tests. The corrected wrapper passed with inherited
`PYTHONOPTIMIZE=1`: 18 creation-policy, 51 ownership/exec, **14** resource-policy,
12 collision, **three** receive-helper, seven upgrade, **ten** resource-transport
and six preparation checks. Only task-owned fake Unix backends were used; no
Docker daemon, application/database, provider, SQL or authentication operation ran.

Head `030275281d` settled with 68 passes, 11 skips, zero pending/cancelled and
two reds in [CI 38267759335](https://github.com/jikig-ai/soleur/actions/runs/38267759335).
The `lint-bot-statuses` log identified three negative token-name fixtures as
un-pinned Supabase Management API callers. The existing dated non-caller allowlist
now records those exact pure-policy/fixture files; no host call is waived or
fake host pin inserted. The guard passed afterward: 44 files enumerated, zero
violations. It retains its census note, 25 versus the 24 baseline, and three
historical deprecation waivers; this is not provider/security clearance.
The executed aggregate log confirms the required `test` red comes from draft-
skipped Web and both scripts legs (`draft: full battery owed at ready`).
Superseded guard cancellations disappeared when replacement jobs settled.
The ensuing fix push requires fresh exact-head and final-description checks.
All runtime/qualification/promotion and consumed-authorization limits persist.

Security-sentinel independently verified the focused fixes at pushed source
`6428d58575376cddd49de8a37ce1527e8c8cf76c`, repeated the pure policy/helper
and entrypoint checks, and found no remaining concrete issue in that fix scope.
This is a focused fix verdict; full PR review and runtime qualification remain
incomplete. The fresh source-bound preview retains 5,039 runtime inputs and all
188 migrations, with preparation-component fingerprint
`6c0d88a3e4a626591b1237e738066dbc6d349986456b97af23f252bbbf95a7b5`
and pairing fingerprint
`10452f442db92d943c3772eb96e050a398e477ad31ea21a2f07a252d442be460`.
[CI 38270626162](https://github.com/jikig-ai/soleur/actions/runs/38270626162)
covers that fix source and is separately watched; the following evidence-only
commit still needs final-head checks. No operational execution or new approval
is inferred from either review or preview.

The later evidence head `a4f05882791a71f3f7aa3840646491e10497a5fd` settled
69 passes / 11 skips / no pending or cancelled checks; only the draft `test`
aggregate remained red. Main's subsequent sandbox-parity commit
`c7ab8838f3fd41b3b0a0558e92723a0d523fdd35` merged cleanly at
`3705a84b4ff1db3843ea68c927655ad5e20fb336`. The qualification code, browser
validators and migration bodies are unchanged; incoming comments, tuple fixtures
and test helpers require a fresh full-production input fingerprint. The offline
wrapper passed again and preview derives **5,046** inputs / **188** migrations.
The component and schema fingerprints above remain unchanged. This source has
runtime manifest fingerprint `4f192983f84df76bdd1464cc001af8087870beb8df6cae690621100610d40416`
and pairing fingerprint `326a174e3b621e50cf57c5c93ef38cbe555e72612eff87e615554eef9a4738e6`.
Final documentation-only source binding and CI remain separate from this preview.
No incoming Docker runtime test, production candidate/recovery command or
authentication action was executed locally.
