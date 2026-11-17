---
date: 2026-11-09
topic: agent-runtime-sandbox-eval
issue: 12517
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Agent runtime: keep bwrap + gateway, or move to a managed sandbox platform

Vocabulary: "sandbox" means the bwrap surface (glossary). A vendor product is a "managed sandbox platform". The "hop" is the egress path a session's outbound request takes (forwarder, then gateway). An "injector" is a proxy on that hop that terminates TLS and swaps a placeholder for the real credential.

## What We're Building

A decision, and the two measurements that back it. No product code ships from this brainstorm.

1. **Decision of record:** egress credential injection is a property of the hop, not of the runtime, so it is decided and built separately from the isolation substrate. The runtime stays on bwrap today and on the gVisor epic's path (#9842) tomorrow.
2. **Measurement 1 (primary):** a self-run TLS-terminating injector on today's hop, for GitHub hosts first, with go/no-go criteria fixed before the run.
3. **Measurement 2 (contingency):** a Cloudflare Sandbox trial on synthetic data, capped at USD 50 over 14 days, measuring the same criteria on a managed platform.
4. **Written flip facts** that would make a managed platform the primary path.

## Why This Approach

The operator's deciding criterion is: does one mechanism cover every HTTPS-credentialed tool (`gh`, `git`, any HTTPS-API CLI) without per-tool code on our side. Ranked on that criterion first:

| Option | One mechanism, no per-tool code | Isolation | EU posture | Cost and effort |
|---|---|---|---|---|
| A. Keep bwrap, add a self-run injector on the hop | Yes if measured (never measured over HTTPS on our carrier) | Unchanged | Unchanged | Lowest; no new vendor |
| C. gVisor per session (#9842) plus the same injector | Yes; A is this option's egress half delivered early | Best self-run | Unchanged | High; 13 open spikes |
| B. Cloudflare Sandbox (programmable outbound handler) | Yes per vendor docs, untested by us | Firecracker microVM, per-sandbox CA | US importer, no stated hard EU guarantee | Additive spend plus loop/tool remoting and legal rewrite |
| B'. Vercel Sandbox | Declarative injection; the programmable route forwards to our own proxy | Firecracker microVM, per-sandbox CA | DPA: primary processing in the US, backups globally replicated | As B |
| D. Kata plus OpenSandbox Credential Vault (S12) | Yes at README level | Hardware boundary | Unchanged | Needs a KVM node; does not work under gVisor |
| F. Daytona, E2B | Daytona: cloud only. E2B: yes, host-keyed only | Mixed | US importers | See rejections |
| E. Status quo plus per-verb tools (#12467) | No. A gated write tool touches about 41 files, a read tool about 14 | Unchanged | Unchanged | Linear per verb |

A, B, C and D tie on the first criterion; E fails it. The tiebreak falls to cost, residency and reversibility, where A wins: the runtime has no dedicated host today (it shares web-1, about USD 11 a month), there are zero external hosted users, only GitHub demand is evidenced, and A's work carries unchanged into C.

The operator chose scope "full re-open, ranked", ruled that the EU-only promise is negotiable for a clear gain, and chose approach A with the Cloudflare trial as the measured contingency.

## User-Brand Impact

- **Artifact:** the egress hop of a web-egress-entitled hosted session, once it can attach a tenant's real credential to outbound HTTPS.
- **Vector:** a tenant credential attached to a request the founder did not approve, or to another tenant's request, or readable inside the sandbox; and, for a managed platform, a third party holding decrypted tenant traffic and credentials.
- **Threshold:** single-user incident.

## Key Decisions

| # | Decision | Rationale | Decided by |
|---|---|---|---|
| 1 | Injection is a substrate-independent hop, specified against the provider-neutral contract | Session-to-tenant identity already exists at the hop (ADR-278 Decision 3); nothing in the criterion depends on bwrap versus gVisor | CTO agent, 2026-11-09 |
| 2 | Approach A: measure a self-run injector first; Cloudflare trial in parallel as contingency | Cheapest path to the criterion, no legal break, reusable under #9842 | Operator, 2026-11-09 |
| 3 | The EU-only promise is negotiable for a clear gain, not a hard constraint | Operator ruling. "Clear gain" is defined by the flip facts below | Operator, 2026-11-09 |
| 4 | ADR-311 Decision 4 stands unamended until the spike measures a hook | No network-layer vend ships before measurement | CTO agent, 2026-11-09 |
| 5 | Approval grain to measure: reads (GET/HEAD on a per-workspace path allowlist, repo-scoped token) vend without an approval row; every other request consumes one ADR-309 row | Matches the tiers already shipped: read tools auto-approve, write tools are gated | CTO agent; matches existing tool tiers |
| 6 | CA scope: one ephemeral CA per session, name-constrained to the inject hosts, key held outside the sandbox | A shared CA makes a binding bug or key leak reach every entitled session | CTO agent, 2026-11-09 |
| 7 | #12467 (per-verb GitHub write tools) is paused until the injector spike reports | If the spike passes the tools are unnecessary; if it fails they resume unchanged | Operator, 2026-11-09 |
| 8 | Cloudflare trial approved: USD 50 total, 14 days, synthetic data only | The only managed hook that is programmable per request, so the only one that could satisfy Decision 4 natively | Operator, 2026-11-09 |
| 9 | Fold into #9842, do not replace it: widen S3 (#9845) to generic per-host injection with approval attachment; widen S0 Arm D (#9859) from paperwork to the Cloudflare trial | Both spikes already own these questions and are unstarted | CTO agent, 2026-11-09 |
| 10 | No public or legal wording changes until a measured control exists | ADR-311 Decision 6; vendor documentation is not a measurement | CLO |
| 11 | Productize candidate: none | A one-off substrate decision, not a recurring work pattern | Brainstorm |

### Spike go/no-go criteria (fixed before the run)

1. The real credential is not observable inside the sandbox (environment, files, process list).
2. `git` over HTTPS (clone, fetch, push), `gh` (REST and GraphQL), Node `fetch`, `curl` and the `claude` CLI's streaming connection all work through the injector with the injected CA, on the production run tuple.
3. A mutating request with no unconsumed approval row is denied and creates a pending row; with a row it is consumed exactly once; with the `approval-queue` flag off it is denied.
4. An allowlisted read vends without a row.
5. Session A cannot obtain session B's credential (two-tenant probe).
6. ADR-278's controls do not regress (default deny, blocked targets unreachable) and no request body is logged.
7. Adding one new GitHub verb touches policy data only; the file count is recorded against the 41-file baseline.

### Cloudflare trial must measure

- Injection with the secret never inside the sandbox, on a pinned SDK version with HTTPS interception set explicitly.
- Whether the outbound handler can read method, path and body, call an external approval store synchronously, and how long it may hold a request.
- CA trust for Bun, `gh` and `git`; streaming through the interceptor.
- What the `eu` jurisdiction setting covers (container, Durable Object, snapshots, logs).
- Billed cost per session-hour, active-CPU fraction, idle billing, cold start and resume with a multi-GB workspace, log export, clean teardown.

### Flip facts: what "clear gain" means

A managed platform becomes the primary path when any one of these holds, the Cloudflare trial has passed, and the CLO's gates below are met:

- **F1.** The self-run injector fails criterion 2 or 5 on our carrier.
- **F2.** The loop and tools prove remotable (S4 #9846 passes) and gVisor fails its file-I/O gate (S1a #9843).
- **F3.** The hosted-concurrency trigger (roadmap row 4.6, "5+ concurrent users") fires before #9842 Stage 1 is ready.
- **F4.** A cross-tenant isolation incident, or a sandbox-escape vulnerability in bwrap or the SDK sandbox (ADR-315's first triggers).

CLO gates for any managed platform: a signed DPA that names the product; an EEA contracting entity or a transfer mechanism covering that product; an acceptable sub-processor list; a transfer impact assessment and DPIA; a successor to the T-1 location gate with fresh operator acknowledgement; published documents changed before any tenant data moves.

### Rejected or set aside

| Candidate | Disposition | Why |
|---|---|---|
| Daytona | Rejected | Repository archived (core moved private, June 2026); the Secrets feature postdates the last AGPL release, so injection is cloud-only |
| E2B | Rejected for now | Interception CA is generated per node, not per sandbox; an invalid secret reference fails open; DPA and sub-processor list are not public |
| Vercel Sandbox | Deferred | Programmable route forwards to our own proxy, so it mostly re-measures option A; trial only if the Cloudflare trial fails |
| Anthropic `mask` mode | Rejected on this carrier | Did not substitute behind our chained proxy (ADR-311); an upstream report of the same behaviour was closed "not planned"; covers sandboxed Bash only |
| Modal, Fly Sprites | Rejected | Modal's injection is experimental and cannot combine with a domain allowlist; Sprites is a reverse-proxy gateway, not transparent interception |
| Perplexity SPACE | Stays in S13 as evidence only | Root CA signing is AWS-only; three HTTP methods; no approval hook |
| OpenSandbox, OpenShell | Stay in S12 and S0 | Kata-only or whole-runtime adoption; neither runs under gVisor |
| iron-proxy | Lead candidate for the spike | Standalone, Apache-2.0, host/method/path rules, a gRPC hook that can call an approval store. Risks: shared CA by default, the hook is documented only in source, one dominant maintainer |

## Premise corrections to the issue

| Issue claim | Finding |
|---|---|
| "The only prior managed-runtime evaluation covered AX/Substrate" | Wrong. The #9842 spec (unmerged, PR #9832) records "Managed vendors: no (US vendors = new Art. 28 sub-processors, no Hetzner BYOC, exit cost)", and S0 Arm D names Vercel Sandbox fra1 or E2B EU. Cloudflare and Daytona were never evaluated |
| "Docs conflict on whether Cloudflare `interceptHttps` is on by default" | Resolved: default off. The live guide and the `cloudflare/containers` source agree; the conflicting text is a preview build |
| "Daytona repo is reported archived" | Confirmed |
| "E2B secrets are private beta" | Not confirmed; per-host transforms are documented as public beta |
| "Migration 2 to 4 engineer-months" | Not decomposed and not measured. It splits into remoting the loop, tools and approval callback (paid by self-run gVisor and by any vendor), vendor-only work (workspace persistence off LUKS, DPA, exit) and injector-only work (two egress files plus CA trust) |
| "Server-side tools scale linearly" | Two data points: about 41 files for a gated write tool, about 14 for a read tool |

## Limits that no option removes

- Injection covers HTTPS to known hosts only: not SSH git, not database connection strings, not credentials carried in a URL or body, not certificate-pinned clients.
- "No per-tool code" becomes per-host protocol classifiers once approvals attach: GraphQL carries reads and mutations in one POST, and git's read path is also a POST (general knowledge, to be confirmed in the spike).
- Confused deputy: an injected read token plus open-web egress is an exfiltration path for everything that token can read.
- File tools run outside the bwrap boundary whichever hop is used.
- An SDK auto-allow can pre-empt the approval prompt; a vendor sandbox does not fix permission-layer ordering.

## Non-Goals

- Choosing or changing the isolation runtime. That stays with #9842 and its decision record #9854.
- Injecting credentials for non-GitHub providers before the GitHub slice is measured and customer demand is evidenced (#11637, #11638 own the follow-on).
- Moving any tenant data or real credential to a vendor.
- Rewording any public or legal text.

## Open Questions

- Does decrypting agent traffic engage secrecy-of-correspondence or ePrivacy rules? Needs outside counsel; parked until the spike passes (CLO).
- The DPIA re-screen (trigger t3 in the 2026-10-05 screening) must complete before any TLS-terminating gateway merges. Owner: #9853.
- Which stored provider credentials do non-Jikigai workspaces actually hold? A data pull, parked until there is a second workspace (CPO).
- #12517 sits in "Post-MVP / Later" while its triggers are Phase 4, and neither it nor #9842 has a roadmap row. Parked for the plan.
- T-1: the CLO cites #5274 as the EU-location pin and CI gate; that issue's title is about workspace durability, so the mapping is unverified.
- Whether iron-proxy can scope a CA and secrets per tenant in one process, or needs one process per session. Spike question.
- Scale-tier "Dedicated infrastructure" wording. (out of scope; #9852)
- Hetzner dedicated-server provisioning for a Kata node. (out of scope; S11 #9866)

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

Marketing was omitted: operator-facing agent infrastructure with no user-facing surface or announcement. Sales, Finance and Support did not match their assessment questions.

### Engineering

**Summary:** The criterion is a property of the egress hop, so injection is decided separately from the runtime. Keep bwrap, measure a self-run injector as the early half of the gVisor design, fold the work into #9842's S3 and S0, and leave ADR-311 Decision 4 standing until a hook is measured.

### Legal

**Summary:** Any managed platform is a new or widened processing activity with a US importer and breaks the published "EU-only processing, no international data transfers" statement and the T-1 gate's premise. Even the self-run option needs the DPIA re-screen before merge, and nothing public may change before a measured control exists.

### Product

**Summary:** Only GitHub parity inside web-access sessions is evidenced, all of it from our own workspace; there are zero external hosted users. Success for a first increment is the full GitHub loop with no readable credential, every write founder-visible, and the next verb needing no new tool.

### Operations

**Summary:** The runtime has no dedicated host (about USD 11 a month on web-1), so a managed platform adds spend and retires none. Session length, concurrency and active-CPU data do not exist, so no break-even can be computed yet; the trial must produce them.

## Capability Gaps

| Gap | Domain | Evidence | Why needed |
|---|---|---|---|
| Nothing on the hop terminates TLS | Engineering | `grep -ci 'ssl_bump' apps/web-platform/infra/egress-gateway-squid.conf` returns 0; `grep -rl tlsTerminate apps/web-platform/server` returns 0; the forwarder pipes raw bytes (`client.pipe(gw)`) | Injection is impossible on a CONNECT-only path; squid as configured must be replaced on the injecting route |
| No session telemetry for cost modelling | Engineering | COO found no session-hours, peak concurrency or active-CPU fraction in `knowledge-base/finance/cost-model.md`, ADR-143 or server constants | The managed break-even formula has no inputs |
| No runtime test sends a non-CONNECT method | Engineering | `apps/web-platform/infra/egress-gateway.test.sh` asserts the config line by grep only | A replaced proxy needs behavioural, not textual, proof |

## Sources

Vendor facts were fetched on 2026-11-09 by research agents and are agent-sourced; re-verify before citing in an ADR.

- Cloudflare: changelog 2026-04-13 (outbound Workers TLS auth); Sandbox SDK outbound-traffic guide; Containers outbound-traffic, placement, limits and pricing pages; customer DPA v6.4; `github.com/cloudflare/containers`.
- Vercel: Sandbox firewall, concepts, regions and pricing docs; DPA effective 2026-03-31; the sub-processor page could not be fetched.
- Daytona: secrets and network-limits docs; `github.com/daytonaio/daytona` (archived).
- E2B: secrets and internet-access docs; `github.com/e2b-dev/runtime`.
- Injectors: `github.com/paradigmxyz/iron-proxy`, `github.com/opensandbox-group/OpenSandbox`, `github.com/NVIDIA/OpenShell`, `github.com/perplexityai/SPACE`, `github.com/anthropics/sandbox-runtime`, `code.claude.com/docs/en/agent-sdk/secure-deployment.md`.
- Repository: ADR-075, ADR-272, ADR-278, ADR-309, ADR-311, ADR-315; `knowledge-base/legal/audits/2026-10-05-dpia-screening-agent-web-egress.md`; `docs/legal/privacy-policy.md`; the #9842 spec on `origin/feat-tenant-executor-topology`.

## Next Steps

Use `skill: soleur:plan` to plan the injector spike, the Cloudflare trial and the decision record.
