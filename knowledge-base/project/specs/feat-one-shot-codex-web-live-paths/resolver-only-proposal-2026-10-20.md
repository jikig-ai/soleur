# Resolver-only diagnostic proposal — 2026-10-20

Status: prose design accepted by independent engineering and security review;
source/offline-test authorization pending.
PR #9051 remains OPEN/draft/disarmed. No implementation or operational authority
is granted by this document.

## Explicit scope change

The operator answered **“Authorize proposal-only planning”** to:

> Do you explicitly authorize a scope change superseding STOP solely to draft a
> bounded proposal for independent engineering/security review? Preparation,
> diagnostics, execution, retries, resync and shipping would remain held.

This supersedes STOP for local proposal drafting and independent proposal review
only. It does not authorize source changes, tests, running the existing resolver,
importing/executing operational entry points, operational binding refresh,
manifests, markers, receipts, DNS, network or acquisition. Documentation commits,
pushes and observation of automatic draft checks publish this proposal; they
grant no operational clearance. All earlier approvals and markers remain spent.

## Evidence and limits

Baseline: `6379012d7362f79f3580ac6aa7e2846334d5347a`. The
[spent Config attempt and separate evidence review](config-acquisition-source-review-2026-10-20.md#approved-config-attempt-and-separate-evidence-review--2026-10-20)
record `status=refused`, `stage=token`, `failure=dns`, zero HTTP requests and zero
Config bytes. DNS activity may have occurred; the exact historical cause remains
unknown. Recorded receipt SHA-256:
`0280a557343c5fb00cf87007c27638f7f93db188aca5aa44163fad5f28262dc0`;
marker SHA-256:
`9824d6f4657a21933708e2be693ad71f5026c95dc64cb42e9a8c7ac197bf75c6`.
No new operational evidence verification is claimed here.

Local source explains the ambiguity without diagnosing the spent attempt:

- `scripts/codex-qualification/config_https.py` › `resolve_addresses()` groups
  helper startup, nonzero exit, output parsing and address admission under `dns`.
- `scripts/codex-qualification/config_resolver.py` › `main()` uses one refusal
  exit for resolution exceptions and several result-shape/bound failures.
- `config_https.py` › `selected_address()` rejects the whole answer set before
  selecting a numeric peer. None of these predicates may be weakened.

No source defect, resolver outage or corrective retry is established. A future
result would describe a new invocation; it cannot recover the old cause.

## Options and recommended boundary

| Option | Assessment |
| --- | --- |
| Repeat Config acquisition unchanged | Reject: can repeat the ambiguous refusal and can reach token/registry/CDN HTTP. |
| General DNS/connectivity investigation | Reject: expands tools, hosts and observations beyond this boundary. |
| Separate one-use resolver-only diagnostic | Recommend for independent proposal acceptance; can classify a new bounded invocation without HTTP/TLS/acquisition. |

The engineering advisory recommends the third option. This is a separate action
design, not a retry of the consumed Config action. Worst target-user impact if
this proposed boundary fails: unintended outbound traffic or disclosure of local
network state. No customer content is an input. Require strict host/output limits
and terminal refusal; customer execution remains blocked.

## Proposed finite action — not authorized

After separate source, preparation and execution permissions, a dormant dedicated
diagnostic would allow at most **one fresh helper launch and one
`socket.getaddrinfo()` invocation**, for **`auth.docker.io` only**, service port
443. No registry/CDN resolution is included. OS/NSS resolution may consult caches,
local configuration, resolver daemons, search suffixes or network services and
emit multiple DNS queries. This is not a one-packet guarantee, an exact DNS
wire-name guarantee or a claim that all resolver activity uses port 443.

No application connection to a resolved address, TLS handshake, HTTP request,
token request, response body or Config access is permitted. There is no
tool-directed alternate resolver/hostname attempt, address connection attempt,
reconnect, retry, Docker daemon contact or acquisition continuation.
Resolver-related system communication is the sole proposed network exposure.
Do not call the acquisition or HTTPS request entry points.

Preserve the existing isolation and admission limits: a fresh isolated interpreter,
empty environment, closed inherited descriptors, null stdin, discarded stderr,
fixed working directory, at most 16 answer rows, at most 4096 output bytes and
unchanged complete-set address validation. No raw answer may be retained.
Use a separate diagnostic helper/protocol if finer classification requires it;
leave existing acquisition/resolver behavior and historical evidence unchanged.
This must remain a small fixed action, not a general troubleshooting framework.

Proposed budget: ten seconds for the diagnostic body and its owned processes,
including private gate/receipt work and cancellation/reaping. Reserve at least
250 ms for child cancellation/reaping and stop earlier if time is insufficient.
Bind a separate outer supervisor with a twelve-second timeout and one-second
kill grace, covering both coordinator and helper. The new helper must remain in
that supervisor's termination scope; do not copy the existing helper launcher’s
detached-session behavior. Parent death must not leave an owned helper running.
Prove termination scope and child lifecycle with synthesized processes during
source review. The outer timeout is a backstop, not a successful cleanup or
receipt guarantee. This budget does not guarantee that system resolver services
emit no later packets after client cancellation. Final exact expanded command
and runtime behavior require separate source and actual-manifest review. Failure
to reap within the body budget is terminal uncertainty.

## New evidence contract

Use a distinct diagnostic action identity, new mode-0700 directory, mode-0600
manifest/marker/receipt, fresh current-source bindings and an exclusive one-use
marker consumed before helper launch. Never reuse or alter an old directory,
manifest, marker or receipt. Hashes provide integrity, not operator consent.

A separate closed receipt schema must bind action/version, source/runtime/helper
and address-policy bytes, exact fixed host, budgets, manifest and output identity.
It records a terminal outcome, observed stage, helper launch count (0 or 1),
cleanup certainty and self-integrity hash. Host and policy acceptance are not
publisher provenance, image admission or qualification. Acquisition/profile/
runtime authority fields remain false and independent evidence review pending.
Unknown fields, outcomes, contradictory combinations or invalid hashes fail closed.

Minimum proposed terminal categories:

| Category | Claim and limit |
| --- | --- |
| `local_refusal` | A bound local prerequisite failed before a helper launch; does not identify a runtime resolver cause. |
| `launch_refusal` | The helper could not be launched successfully; no raw OS error is retained. |
| `resolution_refusal` | A running helper reported failure at its single resolution call; no errno, resolver answer or network-health inference. |
| `answer_refusal` | Helper result shape/count/serialization limits failed; not a resolution-service diagnosis. |
| `protocol_refusal` | Parent rejected bounded helper output/exit consistency; not a claim about DNS contents. |
| `address_refusal` | The complete returned set failed the unchanged address policy; retain no offending address. |
| `deadline_refusal` | A monotonic deadline expired; cleanup certainty is a separate required field. |
| `cleanup_uncertain` | Child termination/reaping could not be established within the budget. |
| `admitted` | This new invocation completed, its bounded answers passed policy and its child was reaped; no connection or HTTP follows. |
| `internal_refusal` | Unclassified failure; never guess a narrower cause. |

Each category must correspond to a directly observed boundary. If finer causes
cannot be separated truthfully, use the broader category. Define category/stage/
launch/cleanup consistency in source review, before any operational preparation.

Before marker consumption, emit only a fixed sanitized refusal stage; do not
fabricate an action receipt. Marker-publication failure does not prove marker
absence. After consumption, preserve the marker even if receipt publication
fails. A receipt-write failure yields only a fixed sanitized publication failure;
it grants no retry and must not overwrite a foreign file. A refusal, timeout,
missing receipt or successful `admitted` result all terminate the action.

Retain no raw exceptions/stderr, DNS answers/IPs, resolver configuration, search
suffixes, interface data, credentials, signed URLs or Config fields. Treat
`helper_launches=1` as permitting DNS/system resolver activity even when output
is absent; a refusal cannot prove no DNS traffic. Memory-only handling makes no
physical-zeroization or hostile-host guarantee.

## Acceptance and separate future gates

1. Independent engineering and security acceptance of this exact prose boundary,
   truthful categories, DNS exposure, deadlines, output minimization and holds.
2. **Separate operator authorization for source and synthesized offline tests
   only.** No real helper/resolver, operational preparation or network execution.
3. Failing synthesized tests before source implementation; independent source
   review before preparation. Cover every category and invalid combination,
   secret canaries, malformed/mixed/over-bound answers, shrinking deadlines,
   kill/reap schedules, parent-death/outer-timeout helper termination, marker
   replay, owned publication/rollback and receipt integrity. Prove acquisition/
   TLS/HTTP continuation is unreachable, including success. Tests must never
   resolve a real host or invoke the production helper.
4. Separate permission for file-only binding refresh and one fresh unused
   diagnostic manifest, followed by actual-manifest and exact-command review.
5. Fresh explicit approval for the fully expanded, one-time DNS-capable command.
6. Execute once, preserve evidence and stop. Separately review evidence and obtain
   a new technical ruling before considering any later acquisition proposal.

No automatic follow-on is permitted, including after success. A later acquisition
would need its own current-source review, new bindings/manifest, actual-command
review and fresh execution approval. A new failure does not authorize corrective
source changes or a second diagnostic. Historical cause remains unknown.

Stop on an unexpected helper hostname argument, extra helper/invocation, attempted application
connection/TLS/HTTP, stale binding, marker collision, invalid output, failed
address policy, deadline/cleanup uncertainty or publication failure.

## Continuing holds

Preparation, diagnostics, execution, retries, main resync/full CI, full branch
review, QA, preflight, build/recovery, qualification, promotion and ship remain
held. These scoped proposal reviews do not satisfy full PR review. Hosted auth
stays BLOCKED; the alternate route stays PENDING. Historical operational bindings
remain unrefreshed. Archive live planning artifacts before eventual ready/merge.

## Independent proposal review

Both seats reviewed pushed `d63d82a43306d4d04134bd02e8a571616d6c3678` using local
document/source reads only. No test, probe, resolver or operational action ran.

- Security initially blocked `cf695fc1fb` on outer-timeout coverage of the helper
  and ambiguous OS/NSS exposure. The concrete correction requires coordinator/
  helper termination containment and parent-death/outer-timeout tests, discloses
  resolver daemons/search suffixes and later system-service traffic, and narrows
  the prohibited alternatives to tool-directed choices and Docker daemon access.
  Security re-review **PASS** at `d63d82a433` with no remaining proposal blocker.
- Engineering re-review **PASS** at the same version. **Ruled by CTO agent:**
  after security PASS, request separate operator authorization for source changes
  and synthesized offline tests only. Proposal acceptance grants no such authority.

Containment, cleanup, truthful category consistency and unreachable transport
continuation remain requirements to prove during source review, not established
runtime capabilities. No acquisition or historical-cause inference follows.
The next authorization has not been granted. All continuing holds above stand.
