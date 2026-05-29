<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!--
  Phase 2.8 reviewed: this plan adds NO new infrastructure resource. The
  canonicalizer's substrate (www CNAME → jikig-ai.github.io, apex A-record set,
  both proxied) is ALREADY Terraform-managed in apps/web-platform/infra/dns.tf
  and is ALREADY drift-detected by scheduled-terraform-drift.yml. The www→apex
  301 itself is served by GitHub Pages (Fastly origin), enforced by the
  repo-tracked CNAME file plugins/soleur/docs/CNAME = "soleur.ai" — not by any
  Cloudflare rule. The fix is a drift-guard TEST over the already-managed
  surface + a code-doc'd contract, NOT a new cloudflare_ruleset. No SSH, no
  dashboard clicks, no operator terraform apply, no new vendor/secret/runtime.
-->
---
title: "Codify the www→apex canonicalizer drift-guard"
date: 2026-05-29
type: fix
classification: ops-only-prod-write
issue: "#4584"
ref: "#4577"
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# infra: codify the www→apex canonicalizer drift-guard (it is GitHub-Pages-owned, not unmanaged CF config) ♻️

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Overview (premise falsification), Phase 3 (exact CI wiring), Phase 1 (test idiom precedent), Acceptance Criteria, Research Insights.
**Research agents used:** inline verification (Task subagents unavailable in pipeline context) — live `curl` header probes, live `gh issue/pr view` resolution of all cited numbers, `grep -rlE` for CF-redirect resources, `grep`/`sed` against `infra-validation.yml` + `inngest.test.sh` + `dns.tf` + `seo-rulesets.tf` + the destroy-guard filter.

### Key Improvements (deepen pass)
1. **Premise falsification confirmed by headers, not just docs.** The www 301 response carries `via: 1.1 varnish` + `x-fastly-request-id` + `x-github-request-id` (GitHub Pages/Fastly origin), live-verified 2026-05-29. There is no `cloudflare_page_rule`/`cloudflare_list`/`http_request_redirect` anywhere in the repo (`grep -rlE` → only the comment at seo-rulesets.tf:61). The issue's "unmanaged CF dashboard config" premise is provably wrong.
2. **Exact CI wiring pinned.** `infra-validation.yml` job `deploy-script-tests` (lines 118-131) runs named infra tests via explicit `run: bash apps/web-platform/infra/<name>.test.sh` steps. The new test wires in as a 4th step there — NOT the per-app `main.test.sh` hook (line 108, which only auto-runs a file literally named `main.test.sh`). Phase 3 updated to this concrete instruction.
3. **Test idiom precedent located.** `inngest.test.sh` is the canonical co-located infra-test shape: `#!/usr/bin/env bash` + `set -euo pipefail` + `SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"` + a PASS/FAIL `assert()` helper + non-zero exit on `FAIL>0`. Phase 1 reuses it verbatim.
4. **All cited references resolved live (`gh`):** #4584 OPEN (issue), #4577 CLOSED, #4573 MERGED, #3297 CLOSED, #3296 MERGED, #3172 OPEN (`priority/p1-high`, "Pick canonical host apex vs www" — roadmap M48). No citation corrections needed.

### New Considerations Discovered
- The destroy-guard (`destroy-guard-filter-web-platform.jq`) counts `cloudflare_ruleset.*.rules` for delete actions. This plan touches NO ruleset rule, so the guard is not engaged — but it confirms that adding a CF redirect ruleset (the rejected approach) would have entangled with the destroy-guard surface.
- Gates 4.6 (User-Brand Impact), 4.7 (Observability 5-field, no-SSH discoverability), and 4.8 (PAT-shaped vars) all evaluated. 4.8 surfaced `var.cf_api_token` as a regex match — this is the pre-existing **Cloudflare** API token (not a GitHub PAT), referenced only descriptively to state no new vars are added; the gate's intent (GitHub-write PAT auth) does not apply. PASS on intent.

## Overview

Issue #4584 (spun out of #4577) asserts: "the live www→apex 301 (host- and path-preserving) is **unmanaged CF dashboard config**, not in `apps/web-platform/infra/` Terraform, so `scheduled-terraform-drift.yml` cannot detect drift," and proposes codifying it as a `cloudflare_ruleset` (likely via the `http_request_redirect` phase + account-scoped Bulk Redirects / `cloudflare_list`).

**Live investigation (2026-05-29) falsifies the premise.** The www→apex 301 is **not** a Cloudflare Redirect Rule or Page Rule. It is served by **GitHub Pages** (Fastly origin), enforced by the repo-tracked custom-domain file `plugins/soleur/docs/CNAME = "soleur.ai"`. GitHub Pages auto-301s every non-primary alias (here, `www.soleur.ai`) to the configured primary custom domain, host- and path-preserving — which is exactly the observed behavior. The DNS topology that routes www traffic to GitHub Pages is **already Terraform-managed** (`cloudflare_record.www` CNAME→`jikig-ai.github.io` proxied; the apex A-record set proxied), and `scheduled-terraform-drift.yml` **already** covers `apps/web-platform/infra`, so the substrate IS drift-detected today.

Evidence (all live-verified 2026-05-29, see Research Reconciliation for commands):

```
GET https://www.soleur.ai/                  → 301  location: https://soleur.ai/
GET https://www.soleur.ai/agents/           → 301  location: https://soleur.ai/agents/
GET https://www.soleur.ai/zzz-nonexistent   → 301  location: https://soleur.ai/zzz-nonexistent   (path-preserving, even for 404 paths)
GET https://soleur.ai/                       → 200
```

The www 301 response carries `server: cloudflare` **AND** `via: 1.1 varnish`, `x-github-request-id: …`, `x-served-by: cache-fra…`, `x-fastly-request-id: …`. The Fastly + GitHub headers prove the 301 originates at the **GitHub Pages origin behind Cloudflare's proxy**, not at the Cloudflare edge. `deploy-docs.yml:80` already documents this in prose: *"www 301s → apex at the edge (GitHub Pages enforces the CNAME)."*

**The real gap is narrow and different from what #4584 states.** There is no Cloudflare canonicalizer to codify (adding one would be wrong — see Alternative Approaches). What is genuinely missing is a **drift-guard that asserts the three managed facts whose combination causes GitHub Pages to perform the redirect**, so a future change to any one of them surfaces in CI rather than silently breaking the contract:

1. `plugins/soleur/docs/CNAME` contains exactly `soleur.ai` (the apex, not www) — if this flips to www, GitHub Pages would 301 apex→www and invert the canonical direction.
2. `cloudflare_record.www` is a proxied CNAME → `jikig-ai.github.io` (so www traffic reaches GitHub Pages at all).
3. The apex `cloudflare_record` A-record set points at GitHub Pages IPs, proxied.

Facts 2–3 are already in Terraform and already drift-detected at the *resource* level; what they lack is an *invariant assertion* that ties them to the canonical-host contract (e.g., nothing today fails if someone repoints `www` away from `jikig-ai.github.io`, or flips the CNAME file). Runtime drift of the redirect itself is **already** guarded by `sentry_uptime_monitor.soleur_www` (`equals 301` assertion, post-#4577).

**The fix:** add a co-located static test (`apps/web-platform/infra/www-apex-canonicalizer.test.sh`, following the existing `*.test.sh` infra-test convention) that asserts the three invariants above against the tracked files, plus a code-comment contract block in `dns.tf` (and a one-line pointer in `seo-rulesets.tf` correcting its stale "out-of-band CF config" comments) documenting that the canonicalizer is GitHub-Pages-owned and which managed surfaces back it. Close #4584 by reframing it (the proposed `cloudflare_ruleset` is rejected with rationale; the drift gap it worried about is closed by the invariant test, not by a new redirect resource).

## Research Reconciliation — Spec vs. Codebase

| Issue #4584 claim | Reality (verified 2026-05-29) | Plan response |
|---|---|---|
| "live www→apex 301 is **unmanaged CF dashboard config** (Redirect Rule / Page Rule)" | **FALSE.** No `cloudflare_page_rule`, `cloudflare_list`, or `http_request_redirect` ruleset exists anywhere in the repo (`grep -rlE 'cloudflare_page_rule\|cloudflare_list\b\|http_request_redirect\|cloudflare_bulk' apps/web-platform/infra` → only the *comment* in seo-rulesets.tf:61). The 301 is served by **GitHub Pages/Fastly** (headers `via: 1.1 varnish` + `x-fastly-request-id` + `x-github-request-id` on the www 301 response), enforced by `plugins/soleur/docs/CNAME = "soleur.ai"`. | Reject the `cloudflare_ruleset` approach; document the real (GitHub-Pages-owned) mechanism in code. |
| "not in `apps/web-platform/infra/` Terraform" | **PARTLY FALSE.** The *substrate* IS managed: `cloudflare_record.www` (CNAME→`jikig-ai.github.io`, proxied, `dns.tf:` last record) + apex A-record set (proxied). The *redirect behavior* is GitHub Pages', which is driven by the tracked `CNAME` file. | The DNS is managed; add an invariant test tying the managed surfaces to the canonical-host contract. |
| "`scheduled-terraform-drift.yml` cannot detect drift" | **PARTLY FALSE.** The workflow covers `apps/web-platform/infra` (matrix entry line ~33) and DOES drift-detect the www CNAME + apex A records at resource level. What it does NOT detect: a flip of the tracked `CNAME` file (not a TF resource), or a semantic inversion of canonical direction. | The new test closes the file-level + semantic-invariant gap that TF resource-drift cannot. |
| "phase `http_request_dynamic_redirect` is already owned by `seo_page_redirects` … needs `http_request_redirect` phase via account-scoped Bulk Redirects" | TRUE *as a constraint* (CF allows ONE user ruleset per zone+phase; `seo_page_redirects` owns `http_request_dynamic_redirect`). But moot — no CF redirect is needed at all. | Document the constraint as the reason a CF-ruleset approach would be awkward AND redundant. |
| "Free-tier 10-rules/phase cap (seo-rulesets.tf:47)" | TRUE — `seo_page_redirects` is at the 10-rule cap. A new dynamic-redirect rule cannot be added without a Bulk-Redirects refactor. | Reinforces rejecting the CF approach: it would force the Bulk-Redirects refactor for zero benefit (GitHub Pages already does the redirect for free). |
| "Bulk-Redirects-via-`cloudflare_list` refactor noted at seo-rulesets.tf:58" | TRUE — comment exists. That refactor is about the **9 deferred `/pages/legal/*.html` redirects**, NOT host canonicalization. | Out of scope; not conflated with this issue. |
| (implicit) "runtime drift of the 301 is unguarded" | FALSE — `sentry_uptime_monitor.soleur_www` asserts `equals 301` (uptime-monitors.tf:99, post-#4577). | Note in Observability; the new test guards *config* drift, the monitor guards *runtime* drift. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing at runtime — this PR adds a test + comments only; it changes no live infrastructure, DNS, or redirect behavior. The *failure mode the test guards against* is: a future change flips `plugins/soleur/docs/CNAME` to `www.soleur.ai` or repoints `cloudflare_record.www` away from GitHub Pages, silently inverting or breaking the www→apex canonical direction. That would degrade Google Search Console coverage across the docs corpus over days/weeks (the original #3296 GSC-indexing failure mode) and split SEO signals (roadmap M48 / #3172). The test makes such a change fail CI loudly instead of decaying silently.

**If this leaks, the user's data is exposed via:** N/A — no PII, no auth, no regulated-data surface. This is an indexing/redirect-hygiene drift-guard over public DNS + a public CNAME file. No secrets are read or written.

**Brand-survival threshold:** aggregate pattern — a regressed canonical direction degrades GSC coverage across the corpus over time, not a single-user incident. (Matches #4577's threshold for the same surface.)

## Files to Edit

1. **`apps/web-platform/infra/dns.tf`** — add a contract-comment block above the `www` CNAME record (and the apex A-record resource) stating: the www→apex 301 is **GitHub-Pages-owned** (enforced by `plugins/soleur/docs/CNAME = "soleur.ai"`), this CNAME + the apex A-records are the managed substrate that routes www traffic to GitHub Pages, and `www-apex-canonicalizer.test.sh` asserts the invariant. No resource change — comment only. (Read the exact current `www` + apex record blocks before editing per `hr-always-read-a-file-before-editing-it`.)
2. **`apps/web-platform/infra/seo-rulesets.tf`** — correct the stale comments that describe the canonicalizer as "out-of-band CF config" / "(out-of-band, dashboard-created) www→apex canonicalizer" (lines ~16-20, ~248, ~371-374). They were written under the (now-falsified) assumption it was a CF rule. Replace with: "GitHub-Pages-owned 301 (enforced by docs/CNAME = apex); see dns.tf contract block + www-apex-canonicalizer.test.sh." No rule change.

## Files to Create

1. **`apps/web-platform/infra/www-apex-canonicalizer.test.sh`** — static drift-guard test (bash, executable, follows the co-located `*.test.sh` convention used by `inngest.test.sh`, `ci-deploy.test.sh`, etc.). Asserts, against tracked files only (no network, no terraform, no SSH):
   - A1: `plugins/soleur/docs/CNAME` content is exactly `soleur.ai` (apex), trimmed of trailing newline. Fails if it is `www.soleur.ai` or anything else (catches canonical-direction inversion).
   - A2: `dns.tf` declares a `cloudflare_record` named `www` whose `content` is `"jikig-ai.github.io"` and `proxied = true` (catches www being repointed off GitHub Pages, or going DNS-only which would bypass the proxy).
   - A3: `dns.tf` declares the apex `cloudflare_record` (name `soleur.ai`) as `type = "A"` and `proxied = true` (catches apex being repointed off GitHub Pages).
   - A4: the contract-comment block exists in `dns.tf` (a `grep -q` sentinel on a stable phrase, e.g. `GitHub-Pages-owned`) so the doc cannot silently rot away from the test.
   Each assertion prints PASS/FAIL with the offending value; the script exits non-zero on any failure (per `hr-when-a-command-exits-non-zero-or-prints`).

## Implementation Phases

### Phase 0 — Preconditions (read-only, no prod write)

0.1. Re-run the live probes to confirm the GitHub-Pages-owned 301 still holds at implementation time:
```bash
curl -sS -o /dev/null -w "www root: %{http_code} -> %{redirect_url}\n" --max-time 15 "https://www.soleur.ai/"
curl -sS -o /dev/null -w "www path: %{http_code} -> %{redirect_url}\n" --max-time 15 "https://www.soleur.ai/agents/"
curl -sI --max-time 15 "https://www.soleur.ai/" | grep -iE '^(server|via|x-fastly-request-id|x-github-request-id):'
```
Expected: both `301`, redirect_url host-preserving to apex; headers include `via: 1.1 varnish` + `x-fastly-request-id` (GitHub Pages origin). If the headers no longer show Fastly/GitHub (e.g., a real CF rule was added out-of-band since), STOP and re-triage — the mechanism would have changed.

0.2. Confirm no CF redirect resource has appeared since the investigation:
```bash
grep -rlE 'cloudflare_page_rule|cloudflare_list\b|http_request_redirect|cloudflare_bulk' apps/web-platform/infra || echo "CONFIRMED: none"
```

0.3. Read the current `www` + apex record blocks in `dns.tf` and the stale comments in `seo-rulesets.tf` (lines ~16-20, ~248, ~371-374) so the comment edits are exact and surgical.

### Phase 1 — Write the failing test first (RED)

Per `cq-write-failing-tests-before`: scaffold `www-apex-canonicalizer.test.sh` with assertions A1-A4 BEFORE adding the dns.tf contract comment. A4 (the `grep -q 'GitHub-Pages-owned'` sentinel) will FAIL initially (comment not yet present) — that is the RED state. Verify A1-A3 already PASS against current tracked state (the topology is correct today).

**Reuse the canonical infra-test idiom verbatim** (verified against `apps/web-platform/infra/inngest.test.sh` 2026-05-29 — plain bash, NO test framework):

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"   # apps/web-platform/infra → repo root
DNS_TF="$SCRIPT_DIR/dns.tf"
CNAME_FILE="$REPO_ROOT/plugins/soleur/docs/CNAME"
PASS=0; FAIL=0; TOTAL=0
assert() { local d="$1" c="$2"; TOTAL=$((TOTAL+1)); if eval "$c"; then PASS=$((PASS+1)); echo "  PASS: $d"; else FAIL=$((FAIL+1)); echo "  FAIL: $d"; echo "        condition: $c"; fi; }
# A1: CNAME file is the apex (catches canonical-direction inversion)
assert "docs/CNAME is soleur.ai (apex, not www)" '[[ "$(tr -d "[:space:]" < "$CNAME_FILE")" == "soleur.ai" ]]'
# A2: www CNAME → jikig-ai.github.io, proxied
assert "dns.tf www record targets jikig-ai.github.io" 'grep -q "content = \"jikig-ai.github.io\"" "$DNS_TF"'
# A3: apex A record proxied (and A4 sentinel) — see Files to Create for the full set
# ...
[[ "$FAIL" -eq 0 ]] || { echo "FAILED: $FAIL/$TOTAL"; exit 1; }
echo "OK: $PASS/$TOTAL"
```

The `REPO_ROOT` resolution is load-bearing: `CNAME` lives at `plugins/soleur/docs/CNAME`, three levels up from the infra dir — derive it from `SCRIPT_DIR`, never a relative `../../../` from cwd (per `hr-when-a-plan-specifies-relative-paths-e-g`, tests run from varying cwd in CI).

### Phase 2 — Add the dns.tf contract block + correct seo-rulesets.tf comments (GREEN)

Add the contract-comment block to `dns.tf` (Files to Edit #1) — A4 now PASSES. Correct the stale `seo-rulesets.tf` comments (Files to Edit #2). Re-run the test: all of A1-A4 PASS, exit 0.

### Phase 3 — Wire the test into CI (so drift actually fails the build)

**Verified target (2026-05-29):** `.github/workflows/infra-validation.yml` job `deploy-script-tests` (lines 118-131) runs co-located infra tests via explicit named steps:

```yaml
      - name: Run canary-bundle-claim-check.sh tests
        run: bash apps/web-platform/infra/canary-bundle-claim-check.test.sh
```

Add a 4th step in the same job, matching that shape exactly:

```yaml
      - name: Run www-apex-canonicalizer drift-guard
        run: bash apps/web-platform/infra/www-apex-canonicalizer.test.sh
```

Do NOT use the per-app `main.test.sh` hook (infra-validation.yml:108) — that only auto-runs a file literally named `main.test.sh` in each matrix directory; our test has a distinct name. Do NOT create a new workflow. Re-confirm the line numbers at /work time (`grep -n 'canary-bundle-claim-check.test.sh' .github/workflows/infra-validation.yml`) before editing, since they may have shifted, and record the final step location in the PR body.

### Phase 4 — Close #4584 with the reframing

The reframing (CF-ruleset rejected; gap closed by invariant test) is the substantive resolution. PR body uses `Closes #4584` (this is a code change merged via normal CI — NOT an ops-only post-merge apply, so `Closes` is correct here, unlike #4577's Sentry-apply case). Include the live-probe evidence + the `grep -rlE … → none` output in the PR body so a reviewer can independently confirm the premise correction.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/infra/www-apex-canonicalizer.test.sh` exists, is executable (`test -x`), and exits 0 against current tracked state: `bash apps/web-platform/infra/www-apex-canonicalizer.test.sh; echo $?` → `0`.
- [ ] Test asserts A1: tampering check — temporarily set `plugins/soleur/docs/CNAME` to `www.soleur.ai`, run the test, confirm it exits non-zero, then restore. (Construct-and-revert validation that the guard actually catches the inversion it claims to.)
- [ ] Test asserts A2/A3 against `dns.tf`: `grep -qE 'content = "jikig-ai.github.io"' apps/web-platform/infra/dns.tf` returns 0 (www target present) AND the www record is `proxied = true`.
- [ ] `dns.tf` contains the contract-comment block — `grep -c 'GitHub-Pages-owned' apps/web-platform/infra/dns.tf` returns ≥ 1.
- [ ] `seo-rulesets.tf` stale "out-of-band … canonicalizer" comments corrected — `grep -ci 'out-of-band.*canonicalizer\|dashboard-created.*www' apps/web-platform/infra/seo-rulesets.tf` returns 0.
- [ ] `terraform validate` passes in `apps/web-platform/infra/` (comment-only edits must not break HCL): `Success! The configuration is valid`. (No `cloudflare_record` resource changed — `terraform plan` shows `0 to add, 0 to change, 0 to destroy` for `cloudflare_record.*`.)
- [ ] The test is invoked by an existing CI job (Phase 3); the invocation pattern is recorded in the PR body. `Automation: feasible — static bash test wired into existing infra-test invocation.`
- [ ] PR body includes the falsification evidence (live www 301 headers showing Fastly/GitHub origin + `grep -rlE … → none`) so the reviewer can confirm the reframing.

### Post-merge (CI)

- [ ] CI run on the merge commit is green (the new test passes in CI, not just locally). `Automation: CI on merge.`
- [ ] `gh issue close 4584` with a comment summarizing the reframing (canonicalizer is GitHub-Pages-owned; drift-guard added; CF-ruleset rejected). `Closes #4584` in the PR body handles auto-close; the comment is the audit trail. `Automation: gh CLI.`

## Domain Review

**Domains relevant:** Engineering (CTO) — infrastructure/IaC + CI-test change only.

No Product/UX (no user-facing surface; test + comments), Marketing, Legal, Finance, Security (no auth/PII/regulated surface; reads public DNS + a public CNAME file), or Data implications. The SEO/indexing concern is engineering-hygiene (GSC coverage / canonical-host integrity), in the #3297 / #4577 / roadmap-M48 (#3172) lineage. No domain-leader Task spawn warranted for a drift-guard test + comment correction. (Domain leaders not spawned in pipeline subagent context; assessment is the single-pass sweep above.)

## Infrastructure (IaC)

### Terraform changes

- **No resource changes.** `dns.tf` gets a contract-comment block (no HCL semantics change); `seo-rulesets.tf` gets corrected comments. The canonicalizer's substrate (`cloudflare_record.www` + apex A-record set) is already managed by the `cloudflare/cloudflare ~> 4.0` provider (currently 4.52.7) via the default `var.cf_api_token`. No new providers, no new variables, no new secrets.

### Apply path

- **No apply.** Comment-only TF edits + a new bash test. Nothing reaches `terraform apply`. `scheduled-terraform-drift.yml` continues to cover the (unchanged) DNS resources; the new test runs on PR/merge CI. This is the rare correct case where the IaC routing gate resolves to "no new infra" — the work is closing a *drift-detection gap* over already-managed surface, not provisioning anything.

### Distinctness / drift safeguards

- The new test is the drift safeguard: it ties the file-level `CNAME` content + the resource-level www/apex records to the canonical-host contract, closing the gap that pure TF resource-drift (which sees the records but not their semantic role, and never sees the `CNAME` file) leaves open.
- `sentry_uptime_monitor.soleur_www` (`equals 301`) remains the runtime-drift guard; the new test is the config-drift guard. The two are complementary, named in Observability.
- No `dev`/`prd` collision — this is prd-only public docs DNS.

### Vendor-tier reality check

- No new CF rule, so the Free-tier 10-rules/phase cap (`seo-rulesets.tf:47`) is **not approached** — which is itself a reason the `cloudflare_ruleset` approach is rejected (it would force the Bulk-Redirects refactor to make room, for zero benefit over the free GitHub-Pages redirect).
- No new Sentry/Better Stack resource; no paid-tier gate.

### Research Insights (deepen pass)

**Precedent-diff — co-located infra test (`*.test.sh`):** The repo has an established pattern; this is NOT novel. Precedent: `apps/web-platform/infra/inngest.test.sh`, `ci-deploy.test.sh`, `ci-deploy-wrapper.test.sh`, `canary-bundle-claim-check.test.sh` — all plain bash, `set -euo pipefail`, `SCRIPT_DIR` self-locate, PASS/FAIL `assert()` helper, non-zero exit on failure. Two CI-invocation mechanisms exist: (a) explicit named steps in `infra-validation.yml` job `deploy-script-tests` (the right one here — content-invariant tests with distinct names), and (b) the per-app `main.test.sh` auto-hook in the `terraform-validate` matrix job (used by `apps/cla-evidence/infra/main.test.sh` for content invariants `terraform validate` can't see). The new test follows pattern (a) verbatim.

**Provider version cross-check:** `cloudflare/cloudflare` is pinned `~> 4.0` (lock: 4.52.7). The plan adds no provider-version-dependent resource attribute — it asserts existing `cloudflare_record` HCL via grep, not via any v4-vs-v5 attribute. The known v4→v5 rename risk (`cloudflare_record` → `cloudflare_dns_record`, per `2026-03-20-cloudflare-terraform-v4-v5-resource-names.md`) is NOT triggered: the test greps `dns.tf` source for `content = "jikig-ai.github.io"` and `proxied = true`, which are stable across the rename's attribute set. If a future v5 bump renames the resource type, A2/A3's resource-name grep would need updating — note this in the test comment so the bump PR catches it.

**Runtime vs config drift — both layers covered:** `sentry_uptime_monitor.soleur_www` (uptime-monitors.tf:99) asserts `equals 301` at 300s cadence (runtime drift). This test asserts the config substrate at CI time (config drift). Neither subsumes the other: the monitor pages after a live regression; the test blocks the regressing PR before merge.

## Observability

```yaml
liveness_signal:
  what: "sentry_uptime_monitor.soleur_www asserts www returns exactly 301 (canonical-direction runtime health); www-apex-canonicalizer.test.sh asserts the config substrate (CNAME file + DNS records) on every CI run"
  cadence: "Sentry monitor: 300s; CI test: every PR + every push to main"
  alert_target: "Sentry uptime alert policy (monitor); CI red build (test)"
  configured_in: "apps/web-platform/infra/sentry/uptime-monitors.tf (monitor); apps/web-platform/infra/www-apex-canonicalizer.test.sh + the CI job that invokes it (test)"
error_reporting:
  destination: "CI build failure (config drift) + Sentry issue (runtime drift)"
  fail_loud: "true - the test exits non-zero and fails the build on any of A1-A4; the monitor pages on any non-301 from www"
failure_modes:
  - mode: "docs/CNAME flipped to www (canonical direction inverted)"
    detection: "www-apex-canonicalizer.test.sh A1"
    alert_route: "CI red build on the offending PR"
  - mode: "cloudflare_record.www repointed off jikig-ai.github.io or set DNS-only"
    detection: "www-apex-canonicalizer.test.sh A2 (config); scheduled-terraform-drift.yml (resource drift)"
    alert_route: "CI red build / drift-detection issue"
  - mode: "www→apex 301 stops at runtime (GitHub Pages misconfig, cache poisoning, real CF rule shadowing it)"
    detection: "sentry_uptime_monitor.soleur_www equals-301 assertion"
    alert_route: "Sentry uptime alert policy"
logs:
  where: "GitHub Actions CI logs (test invocation); Sentry monitor history; R2 terraform state history"
  retention: "GitHub Actions default (90d); Sentry monitor retention; R2 state versioning"
discoverability_test:
  command: bash apps/web-platform/infra/www-apex-canonicalizer.test.sh
  expected_output: "all of A1-A4 PASS, exit 0 (config substrate intact); no SSH"
  note: "Static file-state assertion runnable locally and in CI. Runtime 301 health is the separate Sentry monitor; a no-SSH runtime probe is `curl -sS -o /dev/null -w '%{http_code}' --max-time 15 https://www.soleur.ai/` → 301."
```

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open` matched against `dns.tf`, `seo-rulesets.tf`, and `www-apex-canonicalizer.test.sh` returned zero relevant entries (checked 2026-05-29). Issue #4584 itself is labeled `priority/p3-low` + `domain/engineering`, not `code-review`.

## Alternative Approaches Considered

| Approach | Verdict | Rationale |
|---|---|---|
| Add a `cloudflare_ruleset` (the issue's proposed fix) in the `http_request_redirect` phase via account-scoped Bulk Redirects / `cloudflare_list` | **Rejected** | The premise is falsified — the 301 is GitHub-Pages-owned, not CF. Adding a CF redirect would (a) be **redundant** with the free GitHub-Pages redirect, (b) sit in *front* of it creating a potential double-redirect / shadowing hazard, (c) require widening `var.cf_api_token_rulesets` or a new account-scoped token + the Bulk-Redirects-via-`cloudflare_list` refactor to dodge the 10-rules/phase cap and the one-ruleset-per-zone+phase limit — significant new surface for zero behavioral benefit. The drift-detection goal is met by the invariant test instead. |
| Add a `cloudflare_ruleset` in `http_request_dynamic_redirect` | **Rejected** | That phase is already owned by `seo_page_redirects` (CF allows ONE user ruleset per zone+phase); can't add a second, and the existing one is at the 10-rule Free-tier cap. |
| Do nothing — rely on `sentry_uptime_monitor.soleur_www` (`equals 301`) alone | **Rejected** | The monitor catches *runtime* drift after it's live (and pages the operator), but does not prevent a config change from shipping. The config test fails the PR *before* merge — cheaper and earlier. They are complementary, not redundant. |
| Convert the apex A-records / www CNAME to track GitHub Pages IPs via a data source | **Rejected (out of scope)** | The records are already correct and managed; this issue is about drift-*detection* of the canonical contract, not re-architecting DNS. The IP set is GitHub's published Pages range — pinning it as literals (current state) is fine and the test asserts the www→`jikig-ai.github.io` CNAME which is the stable indirection. |

### Deferred items — tracking issues required

None. This plan closes #4584 by reframing it; there is no deferred capability. (The #4577 Deferred Q1 that *created* #4584 is resolved by this PR's reframing — the "codify the canonicalizer" framing is answered with "the substrate is already codified; here is the drift-guard that was actually missing.")

## Sharp Edges

- **The issue's premise is wrong — lead with the evidence.** A reviewer (or a future reader) will expect a `cloudflare_ruleset`. The PR body MUST front-load the falsification: the www 301 carries `via: 1.1 varnish` + `x-fastly-request-id` + `x-github-request-id` (GitHub Pages origin) and there is no `cloudflare_page_rule`/`cloudflare_list`/`http_request_redirect` anywhere in the repo. Without that evidence the PR looks like it ignored the issue's instructions.
- **`docs/CNAME` is a plain file, not a TF resource — that is exactly why the test is needed.** TF drift-detection sees the www/apex DNS records but never sees the `CNAME` file. A flip of `CNAME` to `www.soleur.ai` would invert the canonical direction with zero TF drift and zero CI failure today. A1 is the load-bearing assertion.
- **Do NOT add a CF redirect "to be safe."** A second redirect layer in front of GitHub Pages' own redirect risks a double-301 chain (`www` → CF rule → apex → GitHub Pages serves) or shadowing that breaks path-preservation. The free GitHub-Pages redirect is correct and host+path-preserving (verified on a 404 path); leave it as the sole canonicalizer.
- **`terraform validate` only — no apply.** Comment-only edits to `dns.tf`/`seo-rulesets.tf` must not change any resource. Confirm `terraform plan` shows `0 to change` for `cloudflare_record.*` and the two rulesets; if it shows a change, a comment edit accidentally touched HCL.
- **Verify the infra-test invocation pattern before wiring (Phase 3).** This repo runs co-located `*.test.sh` infra tests via an existing mechanism; grep `.github/workflows/` and match it. Do not create a new workflow for one test, and do not assume a framework (these are plain bash scripts, not bun/vitest).
- **`Closes #4584` is correct here (not `Ref`).** Unlike #4577 (ops-only post-merge Sentry apply, which used `Ref` to avoid false-close-at-merge), this PR's resolution IS the merged code (test + comments); there is no post-merge prod-apply step. The only post-merge action is the audit-trail `gh issue close` comment.
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (Filled above: threshold `aggregate pattern`.)
