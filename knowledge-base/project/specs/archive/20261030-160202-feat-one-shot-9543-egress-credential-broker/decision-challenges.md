# Decision challenges (plan phase, 2026-10-30)

Headless plan run for #9543. The CTO ruled the technical forks; the rulings narrow what this PR delivers against the issue as written, so the narrowing is persisted here for `ship` to render and for the operator to rule on. The operator's direction was "Implement #9543"; the plan follows the CTO ruling because it is the stricter option under the brief's own constraint (no public security claim ahead of a measured control). Nothing is applied silently.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Broker mechanism: SDK `mask` + `tlsTerminate` (A), bespoke vending or mediating endpoint (B), or the gated server-side push tool (C) | technical | Ruled by CTO agent, 2026-10-30: this PR builds no credential-bearing surface and no new tool; it measures A and B in a spike and records the result in a new ADR - the sandbox's localhost is not the container loopback (ADR-278 measurement 1), `mask` on the env-proxy path is unmeasured, and C is a build in the cc path (github tools and ExecutionGrants exist only in the legacy runner), so the stricter option is to add nothing until measured. |
| Smallest honest dark slice | technical | Ruled by CTO agent, 2026-10-30: spike plus ADR with no runtime behavior change, referenced as `Ref #9543` and not `Closes #9543`; four follow-up issues are filed (cc approval gate and grants, cc push tool, broker mechanism per spike result, BYOK for entitled sessions) - it is the only slice whose every claim is measured. |
| Approval binding for a vend or push in the cc path | technical | Ruled by CTO agent, 2026-10-30: wiring the ADR-309 gate and ExecutionGrants into cc-dispatcher is a prerequisite issue and not part of this PR; the later broker needs a matching unconsumed action-bound approval row per vend - otherwise a non-tool-call path would bypass the gated tier (ADR-305 invariant). |
| Audit of vends | technical | Ruled by CTO agent, 2026-10-30: vend audit must be durable (approval row plus a new `credential-vend` WorkspaceAction line, tenant from the registry binding for the conversation); nothing vends in this PR so nothing is added now - `emitWorkspaceActionContext` is log-only. |
| Spike scope | technical | Ruled by CTO agent, 2026-10-30: the spike stays in this PR with three probes against the pinned SDK 0.3.284 in the real netns topology - (a) `mask` with `injectHosts` on the env-proxy path with and without `tlsTerminate`, (b) a sandboxed request through the proxy chain to a virtual host on the forwarder, (c) whether `tlsTerminate` is settable from the headless settings path - each mutation-checked as an open-world census; it makes no production runtime change. |
| ADR shape | technical | Ruled by CTO agent, 2026-10-30: one new ADR (ordinal checked at plan time, provisional) that records the spike results and mechanism choice and cross-references ADR-278 Decision 5 and the ADR-272 `mask` deferral; ADR-278 and ADR-272 are not rewritten. |
| Public claims (toggle copy, privacy policy, data-protection disclosure, Art. 30 register, DPA item 18) | technical | Ruled by CTO agent, 2026-10-30: no edits in this PR - the Phase-A statement that entitled sessions cannot push stays true while nothing ships, and copy may later say only what the spike measured. |
| The broker build named in the issue is deferred to a follow-up (issue deliverable narrowed) | operator (scope) | Awaiting the operator: confirm the narrowing of #9543 to spike plus ADR; the broker itself, per-request scoping, vend audit and revocation binding move to the follow-up that depends on the cc approval wiring. |
| Priority and order of the cc approval wiring and the cc push tool | operator (priority) | Awaiting the operator: these two follow-ups are the quickest route to "entitled sessions can push" and are independent of the broker. |
| Creating or flipping any feature flag and any production enablement of the later broker or push tool | operator (production-mutating) | Stays with the operator, as the brief states; this PR creates no flag. |
| Legal wording sign-off for the privacy policy, data-protection disclosure, Art. 30 register and DPA item 18 once a broker is measured and enabled | operator (legal-risk) | Stays with the operator; the CLO prepares the wording at the time of flag-on. |

## C1. The core deliverable of #9543 does not ship in this PR

- **Operator direction:** "Implement #9543 (egress credential broker, Phase B of open-web egress)" and "ship the broker dark/flag-off".
- **CTO finding:** on `main`, `github_push_branch` is registered only in the legacy runner and ExecutionGrants exist only there, while web-egress-entitled sessions run in the cc dispatcher; a bespoke endpoint has no verified caller-authentication path from inside the sandbox; the SDK `mask` path is unmeasured on our env-proxy carrier.
- **Plan response:** follows the CTO. Ships the measurement spike, the ADR and four tracked follow-ups; no flag is needed because no runtime surface is added.
- **Cost of each choice:** follow = no new capability for entitled sessions this PR, but no unmeasured credential path in prd and a measured basis for the broker; override = build a vend endpoint or a cc push tool now, which would add a credential-bearing surface before the approval gate exists in that path.
- **Ruling needed from:** operator, at the merge-approval step (the PR body states `Ref #9543`).

## Plan-review challenges (DHH, Kieran, code-simplicity; 2026-10-30)

Mechanical findings were applied to the plan (harness topology and hostnames, probe (c) two settings arms and run-first order, plain-HTTP arm, `allowManagedDomainsOnly` arm, model-pin check, pure-function extraction for the RED rows, Guard 1 property and anchor fixed, doc-parity assertion cut, TLS echo helper inlined, addenda reduced to one line, command-verifiable acceptance criteria). The items below argue the stated shape and are not applied; the plan keeps its default.

## C2. Spike as a permanent test file in default CI vs a one-off run

- **Plan default:** one real-bubblewrap test file that skips locally without a sandbox and fails in CI where `C4_BWRAP_REQUIRED` is set; it asserts the control arm and vacuity only, and records (does not assert) probe outcomes.
- **Reviewer finding (DHH P1, simplicity P2):** a perishable measurement does not belong in default CI; run it as a gated one-off, commit the raw output in the ADR, and let F3 ship the permanent guard for the mechanism it builds.
- **Cost of each choice:** keep = one more bwrap-required CI job and a standing harness to re-run on an SDK bump; switch = about 100 fewer lines, no CI job, and the re-measure trigger depends on review discipline.
- **Ruling needed from:** operator, optional (the switch is a one-line `skipIf` change).

## C3. Reduce probe (b) to reachability only

- **Plan default:** probe (b) records reachability, how the forwarder identifies the session, and whether the sandbox can derive the proxy-hop credential.
- **Reviewer finding (DHH P2):** any in-sandbox caller shares uid and mount namespace with the agent, so a bearer credential there is never secret from the agent; the real identity signals are network position and the approval gate. Reduce (b) to whether a non-CONNECT virtual-host request reaches the forwarder.
- **Cost of each choice:** keep = the CTO-ruled pass/fail criteria are measured, plus about 40 lines; reduce = a smaller probe that departs from the ruled criteria.
- **Ruling needed from:** operator, optional; a CTO re-ruling would be needed to change the criteria.

## C4. Two follow-up issues instead of four

- **Plan default:** four issues as the CTO ruled (F1 cc approval gate, F2 cc push tool, F3 broker, F4 BYOK).
- **Reviewer finding (DHH P3 user-challenge, simplicity P2):** F4 answers no ask and has no spike dependency (fold into F3); F1 and F2 are untestable alone (file as one issue with two phases).
- **Cost of each choice:** keep = more tracking and one more blocked-by edge; switch = fewer issues, less independent scheduling for the push capability.
- **Ruling needed from:** operator, optional.

## C5. Merge the measurements file into the ADR

- **Plan default:** a separate `phase-0-measurements.md` that the ADR links to (the ADR-272 precedent).
- **Reviewer finding (DHH P2):** one ADR with a raw-output appendix is enough.
- **Cost of each choice:** keep = one extra file following the repo precedent; merge = a longer ADR.
- **Ruling needed from:** operator, optional.
