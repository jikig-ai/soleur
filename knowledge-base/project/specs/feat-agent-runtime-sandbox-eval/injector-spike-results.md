# Egress injector spike: results

The injector works: on the production run tuple, an agent's git, gh, curl and Node clients reached GitHub with the real credential while the sandbox and the agent's file tools never saw it, and every write waited for an owner's approval and spent it once. All nine criteria passed, so the verdict is **GO**. The mechanism needs production changes before it can carry real traffic, each owned by #11637 or by #12585, and they are listed below.

## Run

| Field | Value | Label |
|---|---|---|
| Verdict | GO (criteria 1 to 9 pass) | measured |
| Run | [42823659776](https://github.com/jikig-ai/soleur/actions/runs/42823659776), workflow `egress-injector-spike.yml` | measured |
| Commit | head `3396c158474bbf425397e10c4b6adc28d9b3a304`, merge ref `25893fbe7ffc298921e4d3324f5f2fb4cf80a11f` | measured |
| Date | 2026-11-10T13:31:53Z | measured |
| Machine | GitHub-hosted `ubuntu-latest`, Linux 7.0.0-1017-azure x86_64, 4 CPUs, AppArmor profile `soleur-bwrap` loaded | measured |
| App image | `node:22-slim@sha256:4b150b48b4116e2a22f2c39cc27025fbf4f153e2078fd3b14d159fdb5c7279da` plus the runner stage's packages, claude-code 2.1.311, gh 2.103.3 (Dockerfile pins 2.96.0, no longer in the rolling repo; the image falls back to the newest, as production's build does), bubblewrap 0.8.0, prod tuple posture from `lib/docker-run-tuple.py` | measured |
| Agent SDK | `@anthropic-ai/claude-agent-sdk` 0.3.311 | measured |
| iron-proxy | `docker.io/ironsh/iron-proxy@sha256:727da0cc35a6d73ed2913a38d56c4b9b4476c075149492e4fbf75552e83361ff` (v0.56.0) | measured |
| Raw results | `injector-spike-results.json` beside this note (`print-verdict.sh` prints `verdict=GO`, exit 0) | measured |

An earlier GO (run 42816918299) is superseded: it predates the fix for the hash defect in "Defects found and fixed" below.

## Per-criterion verdicts

| # | Criterion | Verdict | Raw outcome (from the results JSON) |
|---|---|---|---|
| 1 | Real credential not observable in the sandbox or by the same-uid file tools | pass | The sandbox scan (env, `ps`, `/proc/self`, every file under HOME, the workspace and `/tmp`) found the planted control and no session secret. Read and WebFetch of the decoy, CA key, hook socket, hook client key, rendered config and the injector's and forwarder's `/proc` files were all refused (file-tool containment, or the Read tool's own `/proc` refusal); a planted workspace file read back. The harness, as the same uid outside the sandbox, read 239 bytes of the injector's `/proc` environ (the outside control). Sandboxed `connect()` on the hook socket failed. |
| 2 | Clients through the injector on the production run tuple | pass | Arm B: git clone and fetch, gh REST and GraphQL, Node fetch with `NODE_USE_ENV_PROXY=1`, and curl each carried the real decoy to the stub (`Basic` for git, `token` for the API). The open-web SSE streamed 50 of 50 events on the router's forwarder branch with the stub's own certificate. A sandboxed push with no row was refused pending (one new row); after the owner approved, the same push vended and the row moved approved to consumed. The CLI's own streaming received 50 of 50 deltas on a direct route (below). |
| 3 | Listed writes gated; consumed once; flag off denies | pass | Git push lifecycle: refused pending with one row and no receive-pack request at the stub; a retry kept one row; owner deny reported `rejected` then a new pending row; approve vended and consumed once; a new commit needed a new row. REST: a row approved for body X gave no real token to body Y, another path or another repository; X was consumed once with `Idempotency-Key` stripped. Flag off: refused, no row. Expiry: pending at about 50 s, then refused `expired`. Every request the hook saw carried no `Authorization` header (`client_auth=0`). |
| 4 | Allowlisted reads vend without a row | pass | REST read, git clone and GraphQL query vended with no row; a read outside the allowlist and every read with the flag off were refused. |
| 5 | Session A cannot obtain session B's credential | pass | B's token carried by A was replaced with A's own; B's proxy credential at A's router, A's credential at B's router and A's router credential at B's injector were each refused 407; A's CA did not verify B's injector; A's hook client certificate on B's socket was refused (client identity), B's own was accepted, and one from another root failed TLS. The stub recorded no B token during A's probes. |
| 6 | ADR-278 controls; no secret or body logged | pass | Deny-CIDR, localhost and link-local targets refused at squid; port 80 refused on both router branches; the forwarder refused a bad token (407). An unentitled session had no route (every probe ended in a sandbox deny; nothing at router, squid or stub). The entitled sandbox reached no container loopback address, directly or through the SDK proxy. iron-proxy's four listeners were reachable from container loopback (recorded) and yielded no vend or credential: 407 on `tunnel_listen` without the router credential, the tunnel guard on `http_listen` and `https_listen`. No log carried a secret or the body canary. |
| 7 | One new verb touches policy data only | pass | `approval-hook.mjs` and `policy.mjs` were byte-identical across passes. Pass 1 refused `POST /repos/spike/beta/issues` not-allowlisted with no row; pass 2 (overlay) gated it, consumed it once and vended. A row approved for "create pull request" did not authorize "create issue" with the same body. |
| 8 | Failure is visible and closed | pass | Stalled hook (RPC blocked): writes exited in about 5.1 s, `hook-timeout` emitted 3 times, no real token. Frozen hook: no real token, the SSE uninterrupted; the client's wait (15 s, ended by `timeout -k`) is recorded, not scored (R27). Killed hook: every client exited within 0.04 s, and iron-proxy's audit named the failed call 4 times. Killed router: all of that session's egress failed. Killed iron-proxy: inject-host clients exited within 0.04 s, the forwarder branch still streamed, and the CLI's own streaming received 50 of 50 deltas. |
| 9 | CA scope | pass | Clients link curl/OpenSSL 3.0.22, git/GnuTLS (`libgnutls.so.30`) and Node/OpenSSL 3.5.9. Each rejected session-CA leaves for a non-inject name, an IP literal and another session's CA, and accepted `api.github.com` and `gist.github.com`. A common-name-only leaf for a non-inject name was rejected, so the constraints cover the CN fallback. The two sessions' CAs were distinct, and the CA key was gone after the session ended. Recorded: git (GnuTLS) accepted a mixed-case inject name; every client accepted a CN-only leaf for an inject host (within the permitted names, R31). |

## Defects found and fixed during the measurement

Each was found by the suite or while preparing this note, fixed with a hermetic test that failed first, and re-measured.

- The REST canonical action dropped the literal path segments, so `POST /repos/o/r/pulls` and `POST /repos/o/r/issues` with the same body shared an approval hash: a row approved for one verb would have authorized the other. Fixed in `policy.mjs`; criterion 7 now probes it.
- iron-proxy sends the request target in origin form (`/path?query`) with the host in a separate field; the hook expected an absolute URL and refused every request. Fixed in `fromTransformRequest`.
- A request sent straight to iron-proxy's `http_listen` (absolute form, no tunnel) was vended. The hook now refuses any request whose tunnel context is not its own host on 443 (CTO R28).
- The hook could not rebind its socket after a restart, so it now removes a stale socket file first.

## Findings for #11637 (production changes the mechanism needs)

Each is labelled; "production change" means this PR measured it with the change applied in the harness only.

- **NO_PROXY carriage (measured; production change).** In arm A, which uses the exact `buildAgentEnv` output, every sandboxed GitHub client went direct with no credential (401 at the stub), because production `NO_PROXY` lists `github.com` and `*.github.com`. Arm B removes the four inject hosts from `NO_PROXY` (CTO R11).
- **SandboxNetworkAccess (measured; production change, filed as #12585).** The SDK sends a `SandboxNetworkAccess` permission request for every host outside the sandbox's `allowedDomains`. Production's `createCanUseTool` has no arm for that request and denies it as an unknown tool, so entitled sandboxed egress is refused today, and the no-egress guarantee for unentitled sessions rests on that branch. The driver answers as the #11637 change must: deny for an unentitled session; for an entitled one, deny hosts that `NO_PROXY` matches and allow the rest (CTO R34).
- **gh carriage (measured; production change).** `gh` refuses to call the API without some token, and `GH_TOKEN` is in the web-egress credential deny list, so the runs set `GH_TOKEN=spike-placeholder` inline in the command; the injector replaced the placeholder with the real value. A production session needs a sanctioned placeholder name, or `gh` configured to send none.
- **Node fetch (measured; production change).** Node's fetch ignores `HTTPS_PROXY` (`EAI_AGAIN` in both arms), which today's open-web forwarder suffers from too. With `NODE_USE_ENV_PROXY=1` it carried the real decoy (CTO R29).
- **The CLI's own traffic goes direct (measured).** With `api.anthropic.com` in `NO_PROXY`, the CLI's Messages API, settings and policy-limit calls all arrived at the stub directly from the app container, never through the router. A dead injector therefore cannot stop `claude` streaming (R17 answered). The `agent-env.ts` comment that "the SDK's API path still transits the proxy" does not hold for SDK 0.3.311 (CTO R33).
- **File-tool boundary (measured).** The SDK sandbox's `denyRead` does not govern the Read tool. Production's boundary is `canUseTool`'s file-tool containment, which the driver reuses, and a bare `allowedTools` entry bypasses `canUseTool` entirely (the SDK warns `CLAUDE_SDK_CAN_USE_TOOL_SHADOWED`).
- **iron-proxy behaviour (measured).** It refuses to dial a loopback upstream by default (the suite renders `upstream_deny_cidrs` from `egress-deny-cidrs.txt` minus the loopback ranges, since iron-proxy dials only the forwarder). It uses a `type: file` secret verbatim, so a trailing newline breaks the header. It passes an HTTP/1.1 upstream's hop-by-hop headers to its client, which breaks HTTP/2 clients. It fails closed (502) while reconnecting to a restarted hook. A frozen hook meets no deadline of its own (R27), so a hook watchdog is a precondition.
- **Hook key custody (read from code).** One hook process holds the service-role and HMAC keys for every session, as the dispatcher does; that is part of the blast radius.
- **CHECK change (measured; #11637 owns the migration).** The suite widened `approval_request`'s `tool_name` CHECK in the throwaway database to `(<existing expression>) OR tool_name = 'egress_injector_spike__credential_vend'`, looking the constraint up in `pg_constraint`; production needs a migration that adds the vend tool name.
- **Confused-deputy residual (inferred from the design).** Reads on the allowlist vend with no row, so an agent can read any allowlisted repository it was granted without a human seeing each read; only writes are gated.

## Pending-approval message (recorded only, CTO R15)

| Client | What the agent saw when a write was refused pending |
|---|---|
| git | `The requested URL returned error: 403`, then `send-pack: unexpected disconnect while reading sideband packet` and `fatal: the remote end hung up unexpectedly`; the hook's message naming the pending approval did not reach the agent |
| curl, gh | HTTP 403 (measured; the probes recorded the status, not the body). The refusal body is the hook's JSON `egress_vend_refused` with reason `pending` and the approval id (read from `approval-hook.mjs`); whether a given client shows it to the agent was not measured |
| claude | not applicable: the CLI's own traffic does not pass the injector |

## What an approval card could show (`canonical_action` per write class)

Generated by `policy.mjs` on synthetic requests; the hook stores exactly these fields and hashes them with HMAC-SHA-256.

| Class | `canonical_action` |
|---|---|
| git push | `{"kind":"git-push","host":"github.com","repository":"spike/alpha","updates":[{"old":"<sha>","new":"<sha>","ref":"refs/heads/main"}]}` |
| REST create pull request | `{"kind":"rest","method":"POST","host":"api.github.com","repository":"spike/alpha","path":"/repos/spike/alpha/pulls","query":[],"body_sha256":"<hex>"}` |
| REST issue comment | same shape, `path` `/repos/spike/alpha/issues/1/comments` |
| REST create issue (overlay) | same shape, `path` `/repos/spike/alpha/issues` |
| GraphQL mutation | host, operation name, operation type and the sha256 of the normalised document and variables (rule `graphql-mutation`) |

A REST card can show the verb and repository but not the body, which is hashed; showing what the write will do needs the body itself, decided under #11637.

## Criterion 7 comparison

Adding the verb took one data file, `policy.add-verb.yaml` (6 data lines, 11 with its comments; measured). #12188, which added one approval-gated verb (`github_push_branch`) the per-verb way, changed 36 files, 9 of them source rather than tests or documents: 8 under `apps/web-platform/server/` and one dev probe script (measured with `gh pr view 12188 --json files`). The overlay leaves out the tests and the approval-card text, and the claim holds only for REST verbs that fit the generic recipe (CTO R4).

## Guard Contract rows run by hand (task 2.2)

The hermetic rows run on every push in `egress-injector-policy.test.ts` and `egress-injector-router.test.ts` (93 tests). The rows below each ran once, as a single mutation on a throwaway branch (since removed) dispatched through the spike workflow; a row counts as caught only when the suite failed with the expected message.

| Row | Mutation | Run | Outcome |
|---|---|---|---|
| Guard 1 row 1 | the decoy reaches iron-proxy through its environment | [42820773980](https://github.com/jikig-ai/soleur/actions/runs/42820773980) | survived, equivalent: bwrap mounts no `/proc` and the Read tool refuses `/proc` files, so no agent surface can read that environment (the harness, as the same uid outside the sandbox, can; that is criterion 1's positive control) |
| Guard 1 row 2 | the sandbox scanner returns no surfaces | [42820787315](https://github.com/jikig-ai/soleur/actions/runs/42820787315) | caught: criterion 1 fails "the sandbox scan is live (planted control found in the scanned file)" |
| Guard 1 row 3 | a decoy copy in a second file under HOME, after a clean first file | [42820800719](https://github.com/jikig-ai/soleur/actions/runs/42820800719), then [42823671481](https://github.com/jikig-ai/soleur/actions/runs/42823671481) | first run survived: the copy held session E's decoy, which was not declared. After declaring every session, caught: criterion 1 fails "no session secret in anything the sandbox or the tools returned" |
| Guard 1 row 4 | the CA key copied out of the masked directory | [42820813762](https://github.com/jikig-ai/soleur/actions/runs/42820813762) | caught: criterion 1 fails "no session secret …" (a session CA key in the scan) |
| Guard 1 row 5 | the positive control reads a path that does not exist | [42820827574](https://github.com/jikig-ai/soleur/actions/runs/42820827574) | caught: criterion 1 fails "control: the same uid outside the sandbox reads the injector's /proc environ" |
| Guard 2 row 2 | `decide` vends without calling `consume_approval` | [42820839761](https://github.com/jikig-ai/soleur/actions/runs/42820839761) | caught: criteria 2, 3 and 7 fail on approved to consumed |
| Guard 2 row 6 | the push ref advertisement requires a row | [42820852167](https://github.com/jikig-ai/soleur/actions/runs/42820852167) | caught: criteria 2 and 3 fail on the gated push |
| Guard 2 row 8 | header replacement ordered before the hook | [42820864911](https://github.com/jikig-ai/soleur/actions/runs/42820864911), then [42823683823](https://github.com/jikig-ai/soleur/actions/runs/42823683823) | first run survived: the hook still refused, so nothing reached the stub. After adding the hook's `client_auth` count, caught: criterion 3 fails "the hook ran before header replacement (client_auth=0 on every request)" |
| Guard 3 row 4 | docker unavailable | local run, 2026-11-10 | caught: `FAIL DOCKER_UNAVAILABLE`, exit 1, INCONCLUSIVE, never a skip |

## Re-measure trigger

These results describe the pinned versions above. Re-measure when any of these changes: the Agent SDK version, the claude-code CLI version, the iron-proxy digest, `buildAgentSandboxConfig` or `buildAgentEnv`, `egress-forwarder.mjs` or `egress-gateway-squid.conf`, the approval RPCs (`create_approval_request`, `decide_approval`, `consume_approval`, `get_approval_status`), or the hook and policy files. The results also go stale when this PR merges, until #11637 owns the job (ADR-324).
