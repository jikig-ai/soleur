# Tasks: agent runtime sandbox evaluation (injector first)

Plan: `knowledge-base/project/plans/2026-11-09-feat-agent-runtime-sandbox-eval-injector-first-plan.md`. CTO rulings: `decision-challenges.md` in this directory (binding).

## Phase 0: Hold the dependent work

- [ ] 0.1 Move #12517 to milestone "Phase 4: Validate + Scale".
- [ ] 0.2 Add blocked-by edges: #12467 and #11637 blocked by #12517.
- [ ] 0.3 Comment on #12467: paused for the spike, review date 2026-11-30.
- [ ] 0.4 Arm the 2026-11-30 issue-comment reminder on #12467 via the schedule-reminder endpoint, only after the operator's typed go naming the exact command (`## Operator Holds`).

## Phase 0.5: Tracer (local docker, before anything else is built)

- [ ] 0.5.1 Pin iron-proxy by digest; start it with one stub host and a throwaway logging hook.
- [ ] 0.5.2 Answer the seven tracer items (upstream chaining, selective termination, hook body access incl. gzip and chunked receive-pack, upstream trust, whole-header replacement, dead-hook fail-closed, inbound Proxy-Authorization) and the sandbox-to-injector binding mechanism.
- [ ] 0.5.3 Record the answers in `iron-proxy-image.provenance.md`; any "no" configuration cannot fix goes to the CTO before Phase 1.

## Phase 1: Hermetic tests, then the harness

- [ ] 1.1 Write the three Guard Contract matrices before code.
- [ ] 1.2 Write `apps/web-platform/test/egress-injector-policy.test.ts` (failing first) over `policy.mjs`'s normalized request struct.
- [ ] 1.3 Add exactly pinned devDependencies `graphql` and `@grpc/grpc-js@1.14.6` to `apps/web-platform` (package.json and lockfile together).
- [ ] 1.4 Implement `policy.mjs` (closed write policy, protocol-classified reads, normalized hash recipe) until 1.2 is green.
- [ ] 1.5 Write `policy.yaml`, `policy.add-verb.yaml` and `iron-proxy.config.tmpl.yaml`.
- [ ] 1.6 Implement `approval-hook.mjs` (one process, per-session masked sockets with nonce and conversation binding, loopback-and-`supabase status` guard, create-then-consume, `get_approval_status` for rejected/expired, 5 s self-deadline, markers, no body or header logging).
- [ ] 1.7 Implement `stub-github/server.mjs` (four hosts, REST, GraphQL, `git http-backend` on a synthetic repo, records `Authorization` class) and the stub Anthropic SSE with scripted `Read`/`WebFetch` tool calls.
- [ ] 1.8 Implement `probes/sandbox-probe.sh` and `injector-spike-docker.test.sh` under `apps/web-platform/test/infra/egress-injector-spike/` (run tuple, real squid conf, local Supabase stack, inline CHECK widening, per-session CA function, forwarder plus injector per session, arms A and B, production deny list derived from code, criteria 1–9, outcome floor, never-skip).
- [ ] 1.9 Implement `print-verdict.sh`.
- [ ] 1.10 Add the `egress-injector-spike` job to `.github/workflows/infra-validation.yml` (pull_request and workflow_dispatch, `if: github.event_name != 'push'`, own path check, 30-minute timeout, per-PR concurrency without cancel-in-progress, artifact upload).
- [ ] 1.11 Run `.github/scripts/test/test-infra-suite-registration.sh` and any `SOLEUR_*` marker census; fix registration before the first push.

## Phase 2: Run and record

- [ ] 2.1 Read the job's run on the PR; re-run by branch dispatch only if needed.
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
- [ ] 4.4 Ship: the PR body's first line states that merging mutates no production surface; issue lines are derived from the committed verdict; on-merge dispositions per the plan's Post-merge criteria.
