# Learning: CF redirect-rule host-match must account for phase-ordering vs an out-of-band canonicalizer

category: integration-issues
module: apps/web-platform/infra (Cloudflare rulesets)
date: 2026-05-29
issue: "#4577"
pr: "#4578"

## Problem

Reconciling the `seo_page_redirects` Cloudflare ruleset to apex-canonical (#4577) after PR #4573 flipped the docs site canonical host www → bare apex. The plan prescribed flipping each of the 9 legacy `/pages/*.html` redirect-rule expressions from `http.host eq "www.soleur.ai"` to **apex-only** `http.host eq "soleur.ai"`.

But the plan was **internally self-contradictory**: its Phase 1 (apex-only expression) conflicted with its own Phase 4a verification AC + User-Brand Impact, which both required www legacy paths to reach the clean apex URL **in one hop** (`location: https://soleur.ai/<slug>/`).

## Root cause

The dominant legacy traffic arrives on **www** (Google indexed the www URLs). There are TWO redirect layers at the edge:
1. The `seo_page_redirects` ruleset (phase `http_request_dynamic_redirect`) — path canonicalization `/pages/X.html → /X/`.
2. An **unmanaged, out-of-band** www→apex canonicalizer (dashboard-created Redirect Rule / Page Rule, NOT in this repo's Terraform — flagged as deferred #4584).

A live hop-chain probe (`curl -sIL https://www.soleur.ai/pages/agents.html`) showed the SEO ruleset fires **first** on the www request (hop 1 → `www/agents/`, host preserved), beating the canonicalizer. With an **apex-only** expression, `www/pages/X.html` would stop matching the SEO rule → fall through to the canonicalizer → `apex/pages/X.html` (path-preserving — also verified live) → then the apex SEO rule → `apex/X/` = **2 hops**, and the first-hop `location:` would be `https://soleur.ai/pages/agents.html`, FAILING Phase 4a.

## Solution

Match **both hosts** in each rule's expression: `http.host in {"soleur.ai" "www.soleur.ai"}` with the apex target `https://soleur.ai/<slug>/`. Because the SEO rule already wins on the www request (observed), this collapses `www/pages/X.html → apex/X/` to **one hop**, satisfies Phase 4a + User-Brand Impact, AND fixes apex `/pages/*.html` (previously stale 200s) — with no redirect loop (targets are hardcoded apex literals; targets never re-enter a `/pages/*.html` match).

The RSS X-Robots-Tag response-header rule stays **apex-only** (`http.host eq "soleur.ai"`) — asymmetric on purpose: the noindex header only matters on the host that serves the feed *body* (apex 200); www 301s away with no indexable body.

Empirical `terraform plan` against live prd state confirmed `0 to add, 2 to change, 0 to destroy`, both rulesets in-place (`~`), rules count 10→10 — destroy-guard not tripped, no `[ack-destroy]`. Rule 10 (HTTPS catch-all + ACME carve-out) verified byte-identical (host-preserving target, untouched).

## Key Insight

When a redirect-rule's host-match interacts with a separate host-canonicalization layer (Bulk Redirect / Page Rule / out-of-band rule), the correct expression host-set depends on **which layer fires first on the incoming request** — determine it empirically with a `curl -sIL` hop-chain against the live edge, not from the plan's prose. Prefer matching **all hosts the legacy traffic can arrive on** so the path-canon rule collapses the chain to one hop, rather than delegating host-canon to a downstream layer and eating an extra redirect. A plan's behavioral verification AC (Phase 4a curl expectations) is a stronger signal of true intent than its imperative implementation step when the two conflict.

## Session Errors

1. **`git stash list` blocked by `hr-never-git-stash-in-worktrees` hook during /work Phase 0.5.** — Recovery: re-ran the preflight checks without `git stash list`. — Prevention: /work Phase 0.5 check #4 prescribes `git stash list`, but the repo hook bans every `git stash` subcommand including read-only `list`; the skill should drop that check or note it is hook-blocked in this repo.
2. **IaC plan-write-guard (`iac-plan-write-guard.sh`) denied a plan Edit** whose `new_string` contained "out-of-band" (manual-infra pattern b) without the ack comment in that new_string. — Recovery: re-applied with `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` embedded in the new_string. — Prevention: the hook scans the Edit's `new_string` in isolation, NOT the whole file; when editing plan/spec prose that legitimately uses trigger words (out-of-band / operator / manually), include the ack literal inside that specific edit's new_string.
3. **`code-quality-analyst` review agent returned "API Error: Internal server error" (0 tokens).** — Recovery: covered its dimension inline (stale-prose sweep, `terraform fmt -check`, plan/tasks consistency) per the Rate-Limit Fallback gate. — Prevention: already covered; partial agent coverage with inline fallback is the documented mitigation.
4. **Chained `sleep 45 && tail` blocked by the harness.** — Recovery: used a `Monitor` until-loop watching for the test-suite exit marker. — Prevention: use Monitor or Read-on-background-output-file for waits; never chain sleeps.

## Tags
category: integration-issues
module: cloudflare-rulesets
related: "[[2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan]]"
