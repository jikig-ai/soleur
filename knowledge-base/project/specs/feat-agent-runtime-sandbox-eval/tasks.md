# Tasks: agent runtime sandbox evaluation (injector first)

Plan: `knowledge-base/project/plans/2026-11-09-feat-agent-runtime-sandbox-eval-injector-first-plan.md`. CTO rulings: `decision-challenges.md` in this directory (binding).

## Phase 0: Hold the dependent work

- [x] 0.1 Move #12517 to milestone "Phase 4: Validate + Scale".
- [x] 0.2 Add blocked-by edges: #12467 and #11637 blocked by #12517.
- [x] 0.3 Comment on #12467: paused for the spike, review date 2026-11-30.
- [ ] 0.4 Arm the 2026-11-30 issue-comment reminder on #12467 via the schedule-reminder endpoint, only after the operator's typed go naming the exact command (`## Operator Holds`).

## Phase 0.5: Tracer (local docker, before anything else is built)

- [x] 0.5.1 Pin iron-proxy by digest; start it with one stub host and a throwaway logging hook, under `env -i`, a throwaway `HOME`, `GIT_CONFIG_GLOBAL=/dev/null` and an internal docker network with no route to real GitHub.
- [x] 0.5.2 Answer the eight tracer items (upstream chaining, selective termination, hook body access incl. gzip and chunked receive-pack, upstream trust, whole-header replacement in configuration only incl. absent and duplicate headers, dead-hook fail-closed, inbound Proxy-Authorization, gRPC over a unix socket with per-call metadata) and the sandbox-to-injector binding mechanism.
- [x] 0.5.3 Record the answers in `iron-proxy-image.provenance.md`; any "no" configuration cannot fix goes to the CTO before Phase 1. (Items 2 and 8 no; CTO R24–R27; add-ons 2b, 7b, 9b yes.)

## Phase 1: Hermetic tests, then the harness

- [x] 1.1 Write the three Guard Contract matrices before code.
- [x] 1.2 Write `apps/web-platform/test/egress-injector-policy.test.ts` (failing first) over `policy.mjs`'s normalized request struct, `decide()` with a fake RPC client (every reason code, canonical-path rows) and `verdict.mjs`'s outcome floor on fixture JSON.
- [x] 1.3 Add exactly pinned devDependencies `graphql` and `@grpc/grpc-js@1.14.6` to `apps/web-platform` (package.json and lockfile together).
- [x] 1.4 Implement `policy.mjs` (closed write policy, protocol-classified reads, normalized hash recipe) until 1.2 is green.
- [x] 1.5 Write `policy.yaml`, `policy.add-verb.yaml` and `iron-proxy.config.tmpl.yaml`.
- [x] 1.6 Implement `approval-hook.mjs` (one process, per-session masked sockets with mutual-TLS client identity (CN = conversation, R25), loopback-and-`supabase status` guard, create-then-consume, `get_approval_status` for rejected/expired, 5 s self-deadline, markers, no body or header logging).
- [x] 1.6b Write `apps/web-platform/test/egress-injector-router.test.ts` (failing first), then implement `connect-router.mjs` (R24, R26: exact four-host match on 443, inbound 407, router-only credential to iron-proxy, everything else to the forwarder).
- [x] 1.7 Implement `stub-github/server.mjs` (four hosts, REST, GraphQL, `git http-backend` on a synthetic repo, records `Authorization` class; HTTP/2 with HTTP/1.1 fallback; `api.anthropic.com` serves WebFetch's preflight and a 50-delta `/v1/messages` stream and records the peer, R33; open-web SSE at `sse.open-web.spike.test`) and the scripted `Read`/`WebFetch`/`Bash` Anthropic stub (in-process in `probes/sdk-egress-driver.mts`).
- [x] 1.8 Suite bring-up and all nine arms (`lib/bringup.sh`, `lib/arms.sh`, `probes/session-up.sh`, `probes/sdk-egress-driver.mts`, `probes/hook-client.mjs`; CTO R28 to R35 applied). Measured GO on CI run 42816918299 (commit 8b0d247411): criteria 1 to 9 pass. Deviation: the sandbox probes run through `probes/sdk-egress-driver.mts` (the real `buildAgentSandboxConfig` and `buildAgentEnv` under tsx), so `probes/sandbox-probe.sh` was not needed.
- [x] 1.9 Implement `verdict.mjs` and `print-verdict.sh` (exit 0 on GO or NO-GO, 1 otherwise).
- [x] 1.10 Create `.github/workflows/egress-injector-spike.yml` (pull_request paths plus workflow_dispatch, 30-minute timeout, per-PR concurrency with cancel-in-progress false, `permissions: contents: read`, `persist-credentials: false`, no secrets, `::error::` per failing criterion, artifact upload) and its `scripts/pr-fanout-ledger.txt` row.
- [ ] 1.11 Run `.github/scripts/test/test-infra-suite-registration.sh`, `plugins/soleur/test/pr-fanout-ledger.test.sh` and any `SOLEUR_*` marker census; fix them before the first push.

### Phase 1 notes for the suite (2026-11-10, measured or read; carry into 1.7, 1.8 and 1.10)

- Done: commits `4b2adccbfa` (policy, hook `decide()`, router, verdict, 78 hermetic tests, deps) and `8dfec181ee` (GitHub stub, iron-proxy config template, Idempotency-Key strip; 80 tests). Guard 2 rows 1, 2, 4, 11, Guard 3 row 3 and the flag-off rule were mutation-checked against the hermetic tests (every mutant reddened). tsc clean.
- Deviation, recorded: `@grpc/proto-loader@0.8.1` is also pinned exactly as a devDependency (already transitive in the lockfile); the hook loads the vendored `transform.proto` (v0.56.0, commit 3d96ce8) with it.
- Deviation, recorded: the classifier adds subreason `write-outside-allowlist` (a listed write to a repository outside the session allowlist, refused with no row), and `consume-failed` carries the RPC's own reason (`already_consumed`, `decider_not_owner`, `requester_not_member`, `not_found`, `not_approved`, `wrong_conversation`, `hash_mismatch`, `unknown`). The plan's subreason list is a subset.
- Read from source: iron-proxy v0.56.0 has no header-strip transform (`headerallowlist` only), so the hook drops the client's `Idempotency-Key` through `modified_request` on CONTINUE (it runs before `secrets`, so no token passes through it).
- Measured: the rendered template loads on the pinned digest with pipeline `approval-hook -> allowlist -> secrets` and http/https/metrics on 127.0.0.1. iron-proxy's default `upstream_deny_cidrs` includes `127.0.0.0/8` and `::1/128`, so the forwarder it chains to must not be a loopback address as iron-proxy sees it (or the suite sets `upstream_deny_cidrs` explicitly and records why).
- Harness design: the unchanged `egress-deny-cidrs.txt` denies every RFC1918, CGNAT and documentation range, so the stubs must sit on an `--internal` docker network with a public-but-unrouted subnet and be reached by docker DNS aliases (`github.com`, `api.github.com`, `uploads.github.com`, `codeload.github.com`, `api.anthropic.com`); squid resolves through the embedded resolver `127.0.0.11`.
- Harness design: the sandbox CA bundle must be system roots + the test upstream root (standing in for a public CA, so the non-inject SSE verifies) + the session CA.
- Harness design: the synthetic bare repository needs `git symbolic-ref HEAD refs/heads/main` and `http.receivepack true`.
- The router config takes credential FILES holding `user:password`; the hook config takes the service-role key, HMAC key (hex), router credential, client root and per-session server cert and key as files, plus a `supabase status -o env` capture for the R21 guard.

### Phase 1 measured findings (2026-11-10, local docker with AppArmor override, then CI)

- iron-proxy sends the request target in origin form; it refuses to dial a loopback upstream by default (`upstream_deny_cidrs`, now rendered from `egress-deny-cidrs.txt` minus loopback); `type: file` secrets are used verbatim (no trailing newline); it passes an HTTP/1.1 upstream's hop-by-hop headers to its client (HTTP/2 clients then fail); it fails closed (502) while reconnecting to a restarted hook.
- `TransformContext.tunnel` is filled for requests on `tunnel_listen` and empty for `http_listen` and `https_listen`; before the R28 guard an absolute-form GET sent to `http_listen` was vended.
- Inside bwrap the proxy env is the SDK's own `localhost:3128` proxy; the router credential never reaches the sandbox.
- Arm A (production `NO_PROXY`): sandboxed GitHub traffic goes direct with no credential. Arm B: git, gh (inline placeholder token) and curl carry the real decoy through the injector. Node fetch ignores `HTTPS_PROXY` (EAI_AGAIN) unless `NODE_USE_ENV_PROXY=1`.
- The CLI's own Messages API, settings and policy-limit calls go direct under production `NO_PROXY`; the `agent-env.ts` caveat does not hold for SDK 0.3.311 (R33).
- The SDK sandbox's `denyRead` does not govern the Read tool; production's boundary is `canUseTool`'s file-tool containment, which the driver reuses. Bare `allowedTools` entries shadow `canUseTool`.
- Name constraints hold for curl (OpenSSL), git (GnuTLS) and Node; a CN-only leaf for an inject host is accepted and one for a non-inject name rejected (R31).
- The SDK raises a `SandboxNetworkAccess` permission request for every host outside the sandbox's `allowedDomains`; production's `createCanUseTool` has no arm for it and denies it as an unknown tool, entitled sessions included (filed as #12585, Phase 4, blocking #11637; CTO R34, R35). The driver answers it as the #11637 change must.
- `gh=2.96.0` is no longer in the rolling apt repo; the image falls back to the newest, as production does (2.103.3 recorded).

## Phase 2: Run and record

- [x] 2.1 Read the job's run (42816918299, GO); the raw results are committed as `injector-spike-results.json`.
- [ ] 2.2 Run each Guard mutation row once by hand and record which reddened the suite, with run URLs.
- [ ] 2.3 Write `injector-spike-results.md` (three plain opening sentences, per-criterion verdicts and raw outcomes, labels, re-measure trigger, `canonical_action` per write class, per-client pending-message record, NO_PROXY arm A finding, `gh` carriage finding, confused-deputy residual, CHECK change for #11637) and commit `injector-spike-results.json`.

## Phase 3: Decision record and dispositions

- [ ] 3.1 Write ADR-324 via `soleur:architecture` and append `## Measured outcome — injector`; run `soleur:architecture assess` for the NFR register.
- [ ] 3.2 GO: append the merge-conditioned ADR-311 addendum. NO-GO: add the ADR-311 see-also.
- [ ] 3.3 Edit #9845 (linked section) and #9859 (Arm D widened with the Phase 4 trial requirements).
- [ ] 3.4 File the demand-side session telemetry issue (Phase 4 milestone).
- [ ] 3.5 Edit `spec.md`: FR3 to the sibling PR, criteria mapping 7 to 1–9, TR1 and TR2 wording, the 36/42 baseline, the verdict set.
- [ ] 3.6 Leave the roadmap handoff note (row 4.6 citing #9842; #12517 and the telemetry issue unplaced; stale Current State) for the next `soleur:product-roadmap` workshop.

## Phase 4: Verification and ship

- [ ] 4.1 Confirm the diff touches none of `egress-forwarder.mjs`, `egress-gateway-squid.conf`, `agent-env.ts`, `supabase/migrations/`, `server/` or any `.tf` file.
- [ ] 4.2 Confirm no GitHub-token-format string in the committed results.
- [ ] 4.3 Run the C4 tests, `lint-guard-contract.py`, `technical-ruling-gate.sh --branch` and markdownlint.
- [ ] 4.4 Ship: the PR body's first line states that merging redeploys unchanged runtime code via `web-platform-release.yml` and changes no infrastructure; issue lines are derived from the committed verdict; on-merge dispositions per the plan's Post-merge criteria.
