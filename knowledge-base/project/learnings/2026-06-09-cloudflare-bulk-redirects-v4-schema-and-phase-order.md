# Learning: Cloudflare Bulk Redirects via Terraform v4 — string-enum fields, phase order, and the from_list dependency edge

## Problem

PR #5082 (GSC legal-page redirects) landed the repo's first account-level Cloudflare ruleset: a Bulk Redirects `cloudflare_list` (kind `"redirect"`) + `cloudflare_ruleset` (phase `http_request_redirect`) on the pinned `cloudflare/cloudflare` 4.52.7 (v4) provider. Three vendor-knowledge traps surfaced, none catchable by `terraform validate` alone, plus a resume-after-crash reconciliation gap.

## Solution

1. **v4 `cloudflare_list` redirect items use STRING enums, not booleans.** `include_subdomains`, `preserve_query_string`, `subpath_matching`, `preserve_path_suffix` are `type=string` with values `"enabled"`/`"disabled"` in v4 (v5 switched to booleans in attribute-set syntax). `terraform validate` silently coerces `true` → `"true"` — the failure surfaces only at apply, behind (in our case) a BLOCKING token-widen step that would have masked the diagnosis. The reliable pre-apply catch:

   ```bash
   mkdir -p /tmp/cf-schema-probe && cd /tmp/cf-schema-probe
   printf 'terraform {\n required_providers {\n  cloudflare = { source = "cloudflare/cloudflare", version = "4.52.7" }\n }\n}\n' > main.tf
   terraform init -input=false && terraform providers schema -json > schema.json
   # jq/python the resource path: resource_schemas.cloudflare_list.block.block_types.item...
   ```

   A scratch dir is REQUIRED: `terraform providers schema -json` inside the real infra dir demands full backend init (R2 creds), but a scratch config pinned to the exact version needs nothing. Registry `latest` docs and context7 show v5 syntax — do not copy them for a v4-pinned repo.

2. **Single Redirects evaluate BEFORE Bulk Redirects.** Cloudflare's execution order (rules/url-forwarding) is: Single Redirects (zone `http_request_dynamic_redirect`) → … → Bulk Redirects (account `http_request_redirect`); "the product executed first will apply". Two of ten review agents asserted the inverse from training priors and built hop-count conclusions on it; the plan's request-flow diagram had it inverted too. The behavioral consequences (which product wins on an overlapping source URL, hop counts for plain-HTTP entries behind an HTTPS-upgrade catch-all) flip with the order — always settle it against the live doc page, not agent consensus.

3. **`from_list` must bind via resource reference.** `action_parameters { from_list { name = "legal_redirects" } }` as a string literal gives Terraform NO graph edge between the ruleset and the list — first apply can create the ruleset before the list exists and the CF API rejects it (nondeterministic, self-heals on re-run, and would have masqueraded as the token-scope failure). One token fixes it: `name = cloudflare_list.legal_redirects.name`. The `$list_name` inside `expression` must stay literal. Four review agents independently flagged this.

4. **Bulk Redirects quota (verified 2026-06-09):** Free tier = 10,000 URL redirects across lists since the 2025-02-12 limits increase (was 20). Plan-era sources may quote the old number.

## Key Insight

For version-pinned Terraform providers, the provider's own schema dump (`terraform providers schema -json` from a scratch dir) is the only ground truth for field types — docs default to the latest major and `validate` coerces primitives silently. And when multiple review agents disagree about vendor evaluation order, the disagreement itself is the signal to fetch the vendor doc: training priors about product execution order are unreliable in both directions.

## Session Errors

1. **(forwarded) Nested Task agents unavailable inside the plan subagent** — Recovery: research done directly via greps/context7/Cloudflare-docs-MCP/WebFetch. **Prevention:** plan skill already documents the direct-research fallback; no change needed.
2. **(forwarded) `iac-plan-write-guard.sh` blocked plan Writes on a "Cloudflare dashboard" phrase** — Recovery: `<!-- iac-routing-ack -->` opt-out + rewording. **Prevention:** hook worked as designed; the ack path is the documented escape.
3. **v4 boolean-vs-string-enum drift in drafted HCL** — Recovery: provider-schema probe + `replace_all` fix across 10 items. **Prevention:** schema-probe step above; routed as a work-skill infra bullet.
4. **`terraform providers schema -json` requires backend init in the real infra dir** — Recovery: scratch-dir probe pinned to 4.52.7. **Prevention:** documented in Solution §1.
5. **`./node_modules/.bin/vitest` exit 127 at repo root** — Recovery: `plugins/soleur/test/*` run under `bun test` (see `scripts/test-all.sh` shard map). **Prevention:** check test-all.sh for the owning shard before picking a runner.
6. **`bun test <path>` from a drifted CWD treated the path as a filter** — Recovery: `cd <worktree-root> && bun test ./<path>`. **Prevention:** existing rule — chain `cd && cmd` in a single Bash call.
7. **Bash CWD silently reset to the bare repo root; a verification grep returned empty against stale bare-root copies** — Recovery: re-ran with absolute worktree path. **Prevention:** `hr-when-in-a-worktree-never-read-from-bare`; prefer absolute paths in verification greps.
8. **`git checkout -- <file>` during a RED-mutation check reverted an UNCOMMITTED sibling edit in the same file** — Recovery: re-applied the canonical-link edit and re-ran the suite. **Prevention:** before using `git checkout --` to undo a deliberate mutation, check `git status` for uncommitted work in the same file; if present, undo via targeted inverse edit (sed/Edit) instead. Routed as a review-skill Sharp Edge.
9. **Cloudflare docs MCP returned empty result sets for Terraform/execution-order queries** (operator + multiple agents) — Recovery: WebFetch of developers.cloudflare.com. **Prevention:** treat empty docs-MCP results as "not found", never "no such constraint"; fall back to WebFetch before concluding.
10. **Two review agents asserted the inverted CF redirect execution order** — Recovery: operator WebFetch settled it; comments and plan diagram corrected. **Prevention:** contested vendor-ordering claims get one doc fetch before any comment/code change (review skill already mandates verifying agent claims; this is the ordering-specific instance).
11. **Stale `/tmp/pr-body.md` from another session collided with Write** — Recovery: session-scoped filename (`pr-body-5082.md`). **Prevention:** suffix scratch files with the PR/issue number.

## Tags

category: integration-issues
module: web-platform-infra
