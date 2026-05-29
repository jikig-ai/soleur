# Learning: verify redirect/edge ownership before codifying it in Terraform

## Problem

Issue #4584 (spun out of #4577) asserted that the live `www.soleur.ai → 301 →
soleur.ai` canonicalizer was **unmanaged Cloudflare dashboard config** (a
Redirect Rule / Page Rule) and proposed codifying it as a `cloudflare_ruleset`
— routed through the `http_request_redirect` phase + account-scoped Bulk
Redirects to dodge the one-ruleset-per-zone+phase limit and the Free-tier
10-rules/phase cap.

Implementing that as written would have shipped a redundant, harmful resource:
a second redirect layer sitting *in front of* the real redirect, risking a
double-301 / shadowing hazard and consuming a rule slot for zero behavioral
benefit.

## Solution

Falsify the premise with live evidence before writing any resource:

1. **Read the 301 response headers, not just the status code.** The www 301
   carried `via: 1.1 varnish`, `x-fastly-request-id`, and `x-github-request-id`
   alongside `server: cloudflare`. The Fastly + GitHub headers prove the
   redirect originates at the **GitHub Pages origin behind** Cloudflare's proxy
   — not at the Cloudflare edge. `server: cloudflare` alone is necessary but
   not sufficient (every proxied response carries it).
2. **Grep the repo for the claimed resource type.**
   `grep -rlE 'cloudflare_page_rule|cloudflare_list\b|http_request_redirect|cloudflare_bulk' apps/web-platform/infra`
   returned only a *comment* — no actual redirect resource anywhere.
3. **Find the real mechanism.** GitHub Pages auto-301s every non-primary alias
   to the primary custom domain configured by the repo-tracked file
   `plugins/soleur/docs/CNAME = "soleur.ai"`. The DNS substrate (www CNAME →
   `jikig-ai.github.io` proxied; apex A-records proxied) was *already*
   Terraform-managed and drift-detected.

The real gap was narrower than the issue stated: TF resource-drift sees the DNS
records but neither the `CNAME` file (not a TF resource) nor the *semantic*
canonical-host contract. The fix is a config-invariant test
(`apps/web-platform/infra/www-apex-canonicalizer.test.sh`, wired into
`infra-validation.yml`) asserting the three managed facts together — plus
comment corrections — NOT a new redirect resource.

## Key Insight

**An issue's proposed fix is a hypothesis about the mechanism, not a
specification.** When a ticket says "behavior X is unmanaged/dashboard config,
codify it as resource Y," verify *what actually produces X* first — response
headers (`via`/`x-fastly`/`x-*-request-id` reveal the true origin behind a
proxy) plus a repo grep for the claimed resource type. A redirect that a free
platform (GitHub Pages, Vercel, Netlify) performs for you should be guarded by
an invariant test over its substrate, never duplicated as a paid/edge resource.

## Session Errors

1. **IaC-routing hook blocked a plan-checkbox Edit.** Marking pre-merge ACs
   `[x]` tripped the `hr-all-infrastructure-provisioning-servers` PreToolUse
   gate on the edit hunk (matched "manual"-class framing) even though the plan
   already carried `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` at line
   1. — Recovery: skipped the cosmetic checkbox edit; deliverables were
   unaffected. — Prevention: the ack opt-out is evaluated against trigger words
   present in the *edited hunk*; an Edit whose `new_string` contains
   manual-framing words re-trips the gate on an already-acked file. Keep
   bookkeeping/checkbox edits free of "manual"/"operator" framing, or expect
   the block. Same root cause as the plan-phase tasks.md false "manual-infra"
   flag and the deepen-plan PAT-gate false-positive on `var.cf_api_token`.
2. **`dns.tf` first Edit rejected — "File has not been read yet."** I had
   inspected it via Bash `cat -n`, not the Read tool. — Recovery: Read tool,
   then Edit. — Prevention: the Edit tool's read-before-edit guard only counts
   a prior **Read-tool** call; `cat`/`sed`/`grep` via Bash do not satisfy it.
3. **shellcheck SC2034/SC2016 on the initial drift-guard test.** The
   `eval`-based deferred-condition `assert()` idiom hid variable usage from
   shellcheck (SC2034 "unused" on `WWW_BLOCK`/`APEX_BLOCK`/`CNAME_FILE`) and
   flagged the single-quoted condition strings (SC2016) — even though the
   precedent `inngest.test.sh` passes shellcheck clean. — Recovery: refactored
   to direct `if` conditionals with `pass`/`fail` helpers (also clearer; prints
   offending values). — Prevention: prefer direct conditionals over
   eval-string indirection in bash tests, and run `shellcheck` before
   considering a `*.test.sh` complete — the CI step runs the test but not
   shellcheck, so a red shellcheck would otherwise surface only later.

## Tags

category: integration-issues
module: apps/web-platform/infra
related: "#4584, #4577, #3296, #3172"
