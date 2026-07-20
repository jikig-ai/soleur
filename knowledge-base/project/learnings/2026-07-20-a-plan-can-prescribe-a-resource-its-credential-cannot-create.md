# Learning: a plan can prescribe a resource its credential cannot create

## Problem

Fixing a GSC "Not found (404)" failed validation on
`https://soleur.ai/cdn-cgi/l/email-protection` (#6746). The remedy — a Cloudflare
Configuration Rule in the `http_config_settings` phase disabling Email
Obfuscation on the marketing hosts — was correct, and survived a 6-agent plan
review panel plus `/deepen-plan`, which even reversed the original remedy
(robots.txt `Disallow`) on strong evidence.

Nobody checked whether the credential could create it.

`cloudflare.rulesets` is bound to `var.cf_api_token_rulesets`, whose scope is
documented verbatim in `variables.tf`: Cache Rules + Zone WAF + Single Redirect
+ Transform Rules, plus account-level Bulk Redirects. No **Config Rules**. The
plan would have committed a resource, added it to the auto-apply `-target=`
allow-list, and then 403'd on apply — the exact silent-no-op class tracker #3379
already documents for a sibling rule on this same zone.

The ledger was accurate the whole time. It was simply never read against the
*new* phase.

## Solution

At `/work`, before writing the HCL, probe the API surface the resource targets:

```bash
TOK=$(doppler secrets get CF_API_TOKEN_RULESETS -p soleur -c prd_terraform --plain)
ZONE=$(doppler secrets get CF_ZONE_ID -p soleur -c prd_terraform --plain)
# the NEW phase
curl -sS -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOK" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE/rulesets/phases/http_config_settings/entrypoint"   # 403
# a KNOWN-GRANTED phase, as a control
curl -sS -o /dev/null -w '%{http_code}\n' -H "Authorization: Bearer $TOK" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE/rulesets/phases/http_request_dynamic_redirect/entrypoint"  # 200
```

The control probe is what makes the result trustworthy — a bare 403 could be a
bad token, a wrong zone, or a typo'd URL. 403-on-new + 200-on-known isolates the
cause to the permission.

The widen-vs-mint decision that followed was an architecture fork with two
contradictory in-repo precedents and no stated rule, so it routed to the `cto`
agent and became **ADR-130**.

## Key Insight

**`terraform plan` cannot tell you this, and that is why it is easy to miss.**
For a resource absent from state, `plan` reports `1 to add` without ever calling
the API — so a clean plan is fully compatible with an apply that 403s. The green
signal and the failure live on different sides of the same command.

Generalize past Terraform: whenever a change introduces a resource on an API
*surface* the codebase has not touched before — a new ruleset phase, a new
vendor endpoint family, a new bucket class, a new scope on an OAuth app — the
credential's coverage of that surface is a **precondition to probe, not a
property to assume**. The strongest tell that you are in this situation is a
scope ledger that enumerates permissions: if the new thing is not named in it,
that is a finding, not an omission.

Corollary from the same PR: a `kind = "zone"` ruleset OWNS its phase entrypoint
as a whole-list replacement, and `plan` cannot see dashboard-created rules
either. So the same blind spot has a second, destructive face — a first apply
can silently delete rules a human created in the UI. Enumerate the entrypoint
before the first apply of any new phase.

## Session Errors

**Plan prescribed a resource its credential could not create.** — Recovery:
live probe at /work; CTO ruling; ADR-130; widen tracked in #6755, PR held in
draft. — Prevention: at plan time, when a change targets a new API phase or
surface, probe the credential against it with a known-granted control probe.
Routed as a bullet to the `plan` skill.

**The scope guard I wrote constrained spelling, not scope.** The negative
assertion was `expect(expression).not.toContain(host)` for three forbidden
hostnames. Two review agents independently built passing mutants that name no
forbidden host yet widen the rule to the whole zone
(`or ends_with(http.host, ".soleur.ai")`, a `zone_name` disjunct, a tautology).
A third appended a SECOND rule — Cloudflare evaluates every rule, but the guard
inspected only the first `set_config` match. A fourth rebound the hosts to
`http.referer`, leaving the remedy completely inert while the suite reported
success. — Recovery: exact-equality against a canonical expression, cardinality
pinned to one rule, `/* */` stripping, YAML-comment stripping. — Prevention: for
a scope/allowlist invariant held in **committed source**, prefer exact equality
over a deny-list. There is no measurement variance to flake on, and forcing a
deliberate test edit alongside a scope edit is the feature.

**My own mutation battery was green and missed all five.** I ran 7 mutations
(M1–M7), all correctly RED, and concluded the guard was non-vacuous. It was
vacuous against every mutation I had not imagined. — Prevention: this is the
already-documented "a mutation battery only covers what you mutate" class
(2026-07-16), and it recurred anyway. The battery measures the mutations, not
the tests. Ask an adversarial reviewer to *name a mutation that satisfies the
assertions while violating the property* — that prompt is what produced all five.

**Doc comments asserted a post-merge state as accomplished fact.** Three agents
independently flagged `the token was WIDENED`, a scope ledger listing a
permission the token does not hold, and citations to an ADR that did not exist.
— Recovery: rewritten in pending tense naming #6755; ADR-130 written. —
Prevention: documented class (present-tense claims for post-merge state); the
cheap gate is to grep new prose for state verbs and ask "is this true at merge,
and true if the post-merge step never runs?"

**`/tmp` exhaustion produced a false-RED full suite.** `test-all.sh` reported
183/195 with `printf: No space left on device`; the shared 4 GB tmpfs was full
from a sibling session's concurrent `test-all.sh` plus my own logs. — Recovery:
removed only my own artifacts (never a sibling's), re-ran with `TMPDIR=/var/tmp`
→ 195/195, zero ENOSPC. — Prevention: the contention rule exists in `work`
already; what it under-specifies is that `mktemp` defaults to `/tmp`, so
"write large logs to /var/tmp" needs `mktemp -t` replaced with an explicit
`/var/tmp` path for anything suite-sized. Confirm a suspected suite failure in
isolation before diagnosing it.

**Browser transport unavailable — third occurrence of the class.** Playwright
MCP disconnected mid-session; `agent-browser` then failed three distinct ways
(`os error 11` daemon unresponsive → `os error 2` after cleanup → 100 s timeout)
with `DISPLAY` and `WAYLAND_DISPLAY` both set, so not a headless problem. —
Recovery: classified `attempted-blocked-on-tool` (NOT operator-only) per the
work skill, filed #6755 with attempt evidence + a resume recipe. — Prevention:
the capability gap is real and named in ADR-130 — there is no first-party skill
for Cloudflare token scope changes, because `soleur:provision-cloudflare` mints
*tenant* tokens via a resource requiring `User API Tokens:Edit`, which no Soleur
token holds. Third ad-hoc dashboard trip on record (#6657, #6649, #6755).

**Bad grep misread the failure list** (one-off). `grep -E 'FAIL|failed'` matched
`PASS: … FAILS` lines — tests whose *names* assert that something fails. —
Prevention: read the runner's own summary line, not a hand-rolled pattern.

**An explanatory comment made a literally-false claim** (one-off). "`git grep
cdn-cgi` matches nothing in committed source" — it matches a learning file and
the PR's own new files. — Recovery: scoped to `-- plugins/soleur/docs`. —
Prevention: run the command you put in a comment, especially in a file that
frames itself as "verified live, not assumed".

## Tags

category: integration-issues
module: infra/cloudflare
