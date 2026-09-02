# Second-caller sweep — who actually calls `analytics/endpoints/logs.all`?

Supabase's 2026-08-26 notice asserts *"you are calling this endpoint directly via scripts,
integrations, or tools."* This file records what each candidate surface was checked with and
what the check returned. Measured 2026-08-26.

| Surface | Caller? | How that was established |
|---|---|---|
| Committed scripts / workflows / Terraform / app code | **No** | `git grep 'logs\.all'` over the tree returns hits in knowledge-base prose only — one endpoint reference, in an evidence record. Zero executable callers. |
| Self-hosted systemd units / cloud-init | **No** | No `*.service`, `*.timer` or `cloud-init-*.yml` contains `api.supabase.com`. Every host-literal match is a workflow, a Terraform file, the egress allowlist, a test assertion, or `inngest-rls/anon-probe.sh`. |
| Vector → Better Stack ingestion | **No** | `vector.toml`'s sources are all `journald`/`host_metrics`; its sink URI is `betterstackdata.com`. It never egresses to `api.supabase.com`. Direction is also wrong: Vector *writes* logs out, it does not query them back. |
| GitHub Actions holding the PAT | **No** | Six workflows carry `SUPABASE_ACCESS_TOKEN`. Their Management API calls are `database/query`, `config/auth` and `advisors/security` — no analytics path in any of them. |
| Doppler-stored PAT used by a non-repo caller | **UNKNOWN — and not closable from here** | See below. This is the one honest gap. |

## The remaining gap, stated plainly

A repository grep cannot exclude a caller that does not live in the repository. The obvious
next probe — ask Supabase which caller hit `logs.all` — **is not available**: the live
Management API spec contains no path matching `audit`, and the two usage endpoints report the
project's own API traffic (PostgREST / auth / storage) rather than Management API calls by
path (`usage.api-counts?interval=1day` → `{"result":[],"error":null}`).

So attribution needs a vendor support ticket, or it is accepted as unknown. It is recorded as
an open item rather than as a discharged one.

## What the evidence actually supports

The most probable caller is an **agent issuing the request ad hoc** with the `soleur/prd` PAT
during a retained-log investigation, reading the request shape out of
`gate-g-escalate-evidence.md`. That is a documented event: the 2026-06-29 GDPR reachability
work did exactly this, and the record of it is the only `logs.all` reference in the tree.

That reading is consistent with every row above and is why the deliverable is a committed,
tested helper rather than a string substitution — a hand-rolled curl reconstructed from prose
is not a caller any guard can see, and it is the one that breaks on 2026-09-23.

It is a hypothesis, not a measurement. The vendor holds the only dispositive evidence.
