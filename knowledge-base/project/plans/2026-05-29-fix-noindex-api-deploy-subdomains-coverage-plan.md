<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: the only .tf edit in this plan is comment-only and
     auto-applies via apply-web-platform-infra.yml on merge (push→main,
     paths: apps/web-platform/infra/**). There is NO operator SSH, no dashboard
     click, no manual provisioning step. The word "operator" elsewhere in this
     plan refers to `gh issue close` / a bounded curl in /soleur:ship
     (CLI-automatable), not infrastructure provisioning. -->
---
title: "SEO: noindex api.soleur.ai / deploy.soleur.ai — reconcile #4575 against already-shipped edge rules"
issue: 4575
branch: feat-one-shot-noindex-api-deploy-subdomains
type: chore
lane: single-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
date: 2026-05-29
---

# 🐛 SEO: stop `api.soleur.ai` (404) & `deploy.soleur.ai` (403) leaking into `sc-domain:soleur.ai` coverage

## Enhancement Summary

**Deepened on:** 2026-05-29
**Sections enhanced:** Test Strategy (runner pinned + precedent), Risks & Mitigations (precedent diff added), citations verified live.

### Key Improvements
1. **Test runner pinned to `vitest`** (was hedged) — confirmed `package.json:15` + `bunfig.toml` blocks `bun test`. Cited the exact mirror precedent `apps/web-platform/test/github-app-manifest-parity.test.ts` (`readFileSync` of `infra/*.tf` + vitest parity asserts).
2. **Precedent-diff gate (4.4) satisfied** — guard pattern is non-novel; documented side-by-side against the manifest-parity test and the complementary tfplan-fixture infra tests.
3. **All `#N` citations verified live** via `gh`: #4575 OPEN, #3379 OPEN (owns the `api.` half), #3297 CLOSED, #3296 + #4573 MERGED. Roles match the prose.

### New Considerations Discovered
- The issue's proposed fix is **already shipped** for `deploy.` (live `x-robots-tag` confirmed) and **structurally impossible** for `api.` via a soleur.ai-zone rule (DNS-only CNAME bypasses the edge) — the latter is already owned by OPEN #3379. The deliverable is therefore a CI regression guard + reconciliation + close-as-superseded, not new edge rules.
- Hard gates 4.6 (User-Brand Impact), 4.7 (Observability 5-field), 4.8 (PAT-shaped halt) all PASS.

## Overview

Issue #4575 asks us to add `X-Robots-Tag: noindex` (Cloudflare Transform Rule / Worker) at the `api.` and `deploy.` subdomain edges — or serve `Disallow: /` robots.txt — so Google stops surfacing them in the `sc-domain:soleur.ai` coverage report. It was deferred from the 2026-05-29 GSC coverage fix (PR #4573) as a Cloudflare/DNS-edge concern.

**Live re-probe (2026-05-29) shows the proposed fix is substantially already shipped.** The Transform Rules the issue asks for already exist in `apps/web-platform/infra/seo-rulesets.tf` (`cloudflare_ruleset.seo_response_headers`, shipped by PR #3296 / closed issue #3297):

```
$ curl -sI -X GET --max-time 15 https://deploy.soleur.ai/
HTTP/2 403
server: cloudflare
x-robots-tag: noindex, nofollow      ← rule FIRES LIVE; deploy.soleur.ai is solved

$ curl -sI -X GET --max-time 15 https://api.soleur.ai/
HTTP/2 404
server: cloudflare                    ← Supabase's CF edge, NOT soleur.ai's zone edge
cf-ray: a034c0d0082e0261-CDG
(no x-robots-tag)                      ← soleur.ai-zone Transform Rule is DORMANT here
```

So the issue is best treated as a **reconciliation + regression-hardening** task, not a "build new rules" task:

1. **`deploy.soleur.ai`** — proxied (`cloudflare_record.deploy` is `proxied = true`), the existing rule fires, `x-robots-tag: noindex, nofollow` is live. **Nothing to build.**
2. **`api.soleur.ai`** — a DNS-only CNAME (`cloudflare_record.api` is `proxied = false`) to `ifsccnjhymdmidffkzhl.supabase.co`. Cloudflare Transform Rules on the `soleur.ai` zone only fire on traffic transiting soleur.ai's edge; DNS-only records bypass it. The rule is intentionally retained but dormant. **This exact no-op is already tracked by OPEN issue #3379** with documented re-evaluation criteria.

The robots.txt alternative also fails for `api.`: Supabase serves that host, and `https://api.soleur.ai/robots.txt` returns `{"error":"requested path is invalid"}` — we do not control that origin to serve `Disallow: /`.

This plan therefore: (a) records the reconciliation, (b) adds a regression-guard test that locks in the two already-shipped Transform Rules so a future `seo-rulesets.tf` refactor cannot silently drop the live `deploy.` noindex (the brand-relevant risk), (c) refreshes the in-file comments to cross-link #4575 ↔ #3379, and (d) closes #4575 as superseded by #3379 — which already owns the only genuinely open sub-question (proxy `api.` or accept the no-op). No new Cloudflare resource is created; the dormant `api.` rule stays as documented defense-in-depth.

**Why not just close #4575 with no PR?** The live `deploy.soleur.ai` noindex is currently protected by *nothing in CI* — a refactor of `seo-rulesets.tf` (e.g., a future Bulk-Redirects consolidation, already foreshadowed in the file's comments) could drop the `rewrite` rule and silently re-expose `deploy.` to indexing. A cheap source-level regression guard converts an undefended live behavior into a defended one. That is the net-positive deliverable; the close is bookkeeping.

## Research Reconciliation — Spec vs. Codebase

The issue body was written from the GSC CSV snapshot (deployed state at deferral time) and the parent plan's Non-Goals, neither of which checked whether the Transform Rules already existed.

| Issue #4575 claim | Codebase / live reality (verified 2026-05-29) | Plan response |
|---|---|---|
| "Add `X-Robots-Tag: noindex` at the `api.` and `deploy.` edges" | **Already present.** Both rules exist in `apps/web-platform/infra/seo-rulesets.tf:319-351` (`cloudflare_ruleset.seo_response_headers`), shipped by PR #3296. | No new rule. Add a regression guard asserting both rules exist in source. |
| "`deploy.soleur.ai` (403) leaks into coverage" | **Solved live.** `curl -sI` → `x-robots-tag: noindex, nofollow`. The rule fires because `cloudflare_record.deploy` is `proxied = true` (dns.tf:12-19). | Lock it in with a guard; no infra change. |
| "`api.soleur.ai` (404) leaks into coverage" | **Confirmed open BUT already tracked.** No `x-robots-tag`; rule is dormant because `cloudflare_record.api` is `proxied = false` (dns.tf:97-103, DNS-only CNAME → Supabase). soleur.ai-zone Transform Rules cannot fire on it. Owned by OPEN issue #3379. | Do not duplicate #3379. Cross-link comments; weigh proxy-vs-accept in Alternatives; recommend keep-dormant. Close #4575 → #3379. |
| "OR serve a `Disallow: /` robots.txt at those subdomains" | **Infeasible for `api.`** Supabase owns the `api.soleur.ai` origin; `GET /robots.txt` → `{"error":"requested path is invalid"}`. We cannot inject a robots.txt without proxying. For `deploy.`, `X-Robots-Tag` already covers it (and is strictly stronger than robots.txt — see Research Insights). | robots.txt is not pursued; `X-Robots-Tag` is the authoritative control already in place. |
| "no code surface in this repo" | **Partially false.** `apps/web-platform/infra/seo-rulesets.tf` IS the code surface, and it auto-applies on merge via `apply-web-platform-infra.yml` (push to main, `paths: apps/web-platform/infra/**`). | Edits land as IaC, auto-applied; no manual infra step. |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — `api.`/`deploy.` are non-public infra subdomains. The *brand* impact of the status quo is an aggregate SEO signal: an internal Access-gated surface (`deploy.`) or a DB REST root (`api.`) surfacing in `sc-domain:soleur.ai` coverage. `deploy.` is already noindexed live; the residual `api.` 404 has no indexable body (Supabase returns a JSON error, not crawlable content). A broken *regression guard* would falsely fail CI but cannot re-expose anything.

**If this leaks, the user's data / workflow / money is exposed via:** N/A — this change adds a source-level test + comment edits + an issue close. It touches no auth, no personal data, no money surface, and no live header behavior (the headers are already as-shipped).

**Brand-survival threshold:** `aggregate pattern` — search-index hygiene is a slow aggregate signal, not a single-user incident. No per-PR CPO sign-off required; section present per gate. (Note: the diff does NOT touch a Check-6 sensitive path — `infra/*.tf` comment-only + a `*.test.ts` — so the `threshold: none` scope-out bullet is not required.)

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Both subdomain Transform Rules still present in source.** A regression-guard test asserts `apps/web-platform/infra/seo-rulesets.tf` contains, inside `cloudflare_ruleset.seo_response_headers`, a `rewrite` rule whose `expression` matches `http.host eq "deploy.soleur.ai"` AND one matching `http.host eq "api.soleur.ai"`, each setting header `X-Robots-Tag` to a value containing `noindex`. Verify: the new test passes via the package's actual runner (see Test Strategy — confirm runner from `package.json scripts.test` / `bunfig.toml` before hardcoding).
- [x] **AC2 — `deploy.` rule asserts `noindex, nofollow` value.** The guard pins the `deploy.soleur.ai` rule's header value to the live string `noindex, nofollow` (not just substring `noindex`), so a value regression is caught. Verify: test fails if the value is mutated to e.g. `noindex` only.
- [x] **AC3 — Cross-link comments updated.** The `api.soleur.ai` no-op comment block in `seo-rulesets.tf` references both #3379 (existing) and #4575 (this issue, as superseded-by). Verify: `grep -nE '#3379|#4575' apps/web-platform/infra/seo-rulesets.tf` returns both numbers within the `seo_response_headers` comment region.
- [x] **AC4 — No new Cloudflare resource, no header-behavior change.** `terraform plan` (or the infra-validation workflow's `terraform validate`) shows zero resource adds/changes/destroys attributable to this PR — the only diffs are comments + a test file. Verify: PR diff contains no new `resource "cloudflare_*"` block and no edit to any `expression`/`headers` body inside `seo_response_headers`.
- [x] **AC5 — Alternatives recorded with deferral tracking.** The "proxy `api.soleur.ai`" option is documented in Alternatives with an explicit disposition pointing at #3379 as the owning tracker. No NEW tracking issue is filed (would double-count #3379). Verify: Alternatives table names #3379 as the owner.

### Post-merge (automation)

- [ ] **AC6 — Auto-apply is a no-op-safe pass.** On merge, `apply-web-platform-infra.yml` runs `terraform apply` for `apps/web-platform/infra/**`. Because the only `.tf` change is comments, the apply is a clean no-op. Automation: handled by the existing workflow (push to main); no manual action. Verify post-merge via the workflow run log showing `0 to add, 0 to change, 0 to destroy` for the `seo_response_headers` resource.
- [ ] **AC7 — Live headers unchanged (regression confirm).** `curl -sI -X GET --max-time 15 https://deploy.soleur.ai/` still returns `x-robots-tag: noindex, nofollow`. Automation: a single bounded curl in `/soleur:ship` post-merge verification (NOT dashboard-watching). `api.soleur.ai` remains 404 with no header (expected per #3379).
- [ ] **AC8 — Close #4575 as superseded.** After merge + AC7, `gh issue close 4575` with a comment: "`deploy.` already noindexed live (verified); `api.` no-op is owned by #3379. Regression guard added in PR #<N>." Use `Ref #4575` in the PR body (NOT `Closes`) so the issue closes post-merge after verification, not at merge — this is the ops-remediation `Ref`-not-`Closes` pattern. Automation: `gh issue close` via Bash.

## Domain Review

**Domains relevant:** Engineering (CTO) — infrastructure/SEO-edge config. No Product/UX surface (no user-facing page or flow), no Legal/Finance/Sales/Support/Marketing implications beyond the aggregate SEO signal already framed in User-Brand Impact.

Single-domain (Engineering) infrastructure/tooling change. The CTO lens is satisfied inline by the IaC section below (auto-apply path, no-op-safe, no new resource). No blocking cross-domain review required.

## Infrastructure (IaC)

### Terraform changes
- **File:** `apps/web-platform/infra/seo-rulesets.tf` — **comment-only** edits inside the `cloudflare_ruleset.seo_response_headers` block (cross-link #4575 ↔ #3379). No resource/expression/header body change.
- **Providers:** no change. Rules already declared on the `cloudflare.rulesets` provider alias (`main.tf`, bound to `var.cf_api_token_rulesets`).
- **Sensitive variables:** none added. (`cf_api_token_rulesets`, `cf_zone_id` already provisioned in `prd_terraform` Doppler config.)

### Apply path
- **(b) auto-apply on merge** via `.github/workflows/apply-web-platform-infra.yml` (`on: push: branches: [main], paths: ["apps/web-platform/infra/**"]`). Because the `.tf` edit is comments-only, the apply is a **clean no-op** (`0 to add, 0 to change, 0 to destroy`). No SSH, no dashboard click, no manual provisioning. Blast radius: zero (no state mutation).

### Distinctness / drift safeguards
- This is a `prd`-only zone; no `dev`/`prd` confusion (single soleur.ai zone). The dormant `api.` rule is the documented "keep but inert" pattern — retained so a future proxy flip activates it without code change (#3379 rationale). No `terraform.tfstate` secret exposure (comments carry no values).

### Vendor-tier reality check
- Cloudflare Transform Rules (`http_response_headers_transform`) are available on the soleur.ai zone's current tier — already in use live for `deploy.` and the RSS feed rule. No tier gate. (Note for Alternatives: proxying `api.` would require a Supabase Origin Certificate at the edge, a separate TLS terminator — the cost #3379 weighs, not a CF-tier limit.)

## Observability

```yaml
liveness_signal:
  what: "x-robots-tag header on https://deploy.soleur.ai/ GET response"
  cadence: "on-demand (post-merge ship verification) + Googlebot recrawl cycle (~2-4 weeks reflected in GSC coverage)"
  alert_target: "PR ship-phase curl assertion (AC7); no standing alert needed (aggregate-pattern threshold)"
  configured_in: "/soleur:ship post-merge verification step; AC7 curl"
error_reporting:
  destination: "CI: the AC1-AC4 regression-guard test failure surfaces in the PR check run + infra-validation.yml terraform validate. No runtime app code, so no Sentry path."
  fail_loud: "yes — guard test failure blocks the PR check; terraform validate failure blocks apply-web-platform-infra.yml"
failure_modes:
  - mode: "Future seo-rulesets.tf refactor drops the deploy. rewrite rule"
    detection: "AC1/AC2 regression-guard test fails in CI"
    alert_route: "PR check run (red) — blocks merge"
  - mode: "deploy.soleur.ai header silently disappears live (CF dashboard out-of-band edit / token drift)"
    detection: "AC7 curl in ship verification; scheduled-terraform-drift.yml detects state drift on the ruleset"
    alert_route: "drift workflow auto-files an issue; ship-phase curl fails loud"
  - mode: "api.soleur.ai begins serving 200 real content (no longer a benign 404)"
    detection: "re-evaluation trigger on #3379 (Supabase custom-domain content change)"
    alert_route: "manual re-open of #3379 per its documented criteria"
logs:
  where: "GitHub Actions run logs for apply-web-platform-infra.yml + infra-validation.yml (terraform plan/validate output)"
  retention: "GitHub Actions default (90 days)"
discoverability_test:
  command: "curl -sI -X GET --max-time 15 https://deploy.soleur.ai/ | grep -i x-robots-tag"
  expected_output: "x-robots-tag: noindex, nofollow"
```

## Test Strategy

- **Runner: `vitest`** — confirmed via `apps/web-platform/package.json:15` (`"test": "vitest"`, `"test:ci": "vitest run"`, vitest `^3.1.0` at :81). `apps/web-platform/bunfig.toml` carries `[test]` discovery-blocking (defense-in-depth per #1469), so `bun test` would report "filter did not match" — **do NOT use `bun test`**. Run the guard with `./node_modules/.bin/vitest run test/seo-rulesets-noindex.test.ts` (or `npm run test:ci -- test/seo-rulesets-noindex.test.ts`) from `apps/web-platform/`.
- **Precedent (mirror this exactly):** `apps/web-platform/test/github-app-manifest-parity.test.ts` is the canonical source-text-assertion test in this repo — it `readFileSync`s a committed `infra/*.tf`/`.json` file from `REPO_ROOT = path.resolve(__dirname, "../../..")` and asserts symbol parity with `describe/test/expect` from `vitest`. The new guard adopts the same shape: import `{ describe, test, expect }` from `vitest` + `{ readFileSync }` from `node:fs`, read `apps/web-platform/infra/seo-rulesets.tf` as a string, regex/substring-assert the two rules. No HCL parser is added (none exists in the toolchain; source-text assertion is the dependency-free correct shape).
- **No live-network test in CI** (would couple CI to Cloudflare uptime + add unbounded latency). The live `curl` is a post-merge ship verification (AC7), bounded with `--max-time 15`.
- **RED before GREEN:** write the guard so it fails if either rule's `http.host` expression or `noindex` header value is removed, then confirm it passes against the current file.

### Risks & Mitigations — precedent diff

The guard pattern is **not novel**; it directly mirrors `github-app-manifest-parity.test.ts` (vitest + `readFileSync(REPO_ROOT/infra/*.tf)` + parity asserts, `Ref #4115`). Side-by-side: both read a committed `apps/web-platform/infra/*` artifact as text, both anchor `REPO_ROOT` via `path.resolve(__dirname, "../../..")`, both assert presence of load-bearing literals rather than parsing the format. The only delta is the artifact (`seo-rulesets.tf` vs `github-app-manifest.json`/`github-app.tf`) and the asserted literals (`http.host eq "deploy.soleur.ai"` + `noindex, nofollow`). Reviewers should scrutinize the regex anchoring only (see Sharp Edge), not the overall approach.

There is **also** existing tfplan-fixture infra-test infrastructure (`tests/scripts/fixtures/tfplan-cf-ruleset-rule-addition.json`, `tfplan-web-platform-real-baseline.json` + `destroy-guard-filter-web-platform.jq`) that asserts CF-ruleset *plan* shapes. The new guard is complementary: those fixtures gate plan-time *changes*; this guard gates source-time *presence* of the noindex rules. No overlap, no consolidation needed.

## Files to Edit
- `apps/web-platform/infra/seo-rulesets.tf` — comment-only: cross-link #4575 ↔ #3379 in the `seo_response_headers` no-op block (AC3). No resource-body change.

## Files to Create
- `apps/web-platform/test/seo-rulesets-noindex.test.ts` — vitest regression guard for AC1/AC2 (mirrors `github-app-manifest-parity.test.ts`; runner confirmed vitest, see Test Strategy).

## Open Code-Review Overlap

None. (No open `code-review`-labeled issue references `seo-rulesets.tf`, `seo_response_headers`, or the api/deploy subdomain rules. The only related open issue is #3379, which is `infra`/tracker-class, not `code-review`, and is explicitly the owning tracker for the `api.` no-op — handled in AC5/Alternatives, not folded.)

## Alternative Approaches Considered

| Approach | Verdict | Disposition / Owner |
|---|---|---|
| **Add a NEW `X-Robots-Tag` Transform Rule for `deploy.`** | Rejected — already exists and fires live. Would be a duplicate resource (and CF allows only one user ruleset per zone+phase). | N/A |
| **Proxy `api.soleur.ai` through soleur.ai's edge so the dormant rule fires** | Deferred. Heavy: requires a Supabase Origin Certificate at the CF edge + accepting a second TLS terminator on the DB REST path. Risk to live app traffic (every Soleur user hits `api.soleur.ai` for Supabase REST/Auth) outweighs the SEO benefit of noindexing a 404 with no indexable body. | **Owned by OPEN #3379** (re-evaluate if Supabase adds header injection OR operator opts to proxy). No new issue filed — would double-count. |
| **Serve `Disallow: /` robots.txt at `api.`** | Infeasible — Supabase owns the origin; `GET /robots.txt` → `{"error":"requested path is invalid"}`. We cannot inject without proxying (collapses to the row above). Also strictly weaker than `X-Robots-Tag` (robots.txt blocks crawl but Google can still index a URL it discovers via CT logs without a snippet). | Not pursued. |
| **Cloudflare Worker on `api.`** | Same blocker as the Transform Rule — a Worker route only binds to traffic transiting the soleur.ai edge; DNS-only `api.` bypasses it. Requires proxying first → row 2. | Not pursued. |
| **Remove the dormant `api.` rule entirely** | Rejected — #3379 documents that keeping it means a future proxy flip activates noindex automatically; removing it creates a silent re-exposure window. | Keep as-is. |
| **Close #4575 with no PR** | Rejected — leaves the live `deploy.` noindex undefended by CI (refactor could silently drop it). The regression guard is the net-positive deliverable. | This plan. |

## Non-Goals / Out of Scope
- **Activating noindex on `api.soleur.ai`** — owned by #3379; requires proxying (see Alternatives). Not in scope.
- **Any change to live header behavior** — `deploy.` is already correct; this PR only adds a guard + comments.
- **GSC "Validate Fix" / coverage-report automation** — no public GSC write API; operator-only and already covered by the parent plan's AC14. Not re-litigated here.
- **Touching `app.soleur.ai` / docs robots/canonical** — resolved by PR #4573 (the parent). Out of scope.

## Research Insights

**Live verification (2026-05-29, `curl --max-time 15`):**
- `deploy.soleur.ai` GET → `HTTP/2 403`, `x-robots-tag: noindex, nofollow` present (rule fires; `proxied = true`).
- `api.soleur.ai` GET → `HTTP/2 404`, `server: cloudflare` + `cf-ray` (Supabase's own CF edge), no `x-robots-tag` (soleur.ai-zone rule dormant; `proxied = false`).
- `api.soleur.ai/robots.txt` → `{"error":"requested path is invalid"}` (Supabase origin; we don't control it).

**Source-of-truth files:**
- `apps/web-platform/infra/seo-rulesets.tf:279-366` — `cloudflare_ruleset.seo_response_headers` with the `api.` (319-337), `deploy.` (339-351), and RSS (353-365) rules; the `api.` no-op is documented at lines 287-318 linking #3379.
- `apps/web-platform/infra/dns.tf:12-19` (`deploy`, `proxied = true`) and `:97-103` (`api`, `proxied = false`).
- `.github/workflows/apply-web-platform-infra.yml:58-67` — auto-apply on push to main for `apps/web-platform/infra/**`.

**Authoritative SEO control rationale:** `X-Robots-Tag: noindex` is stronger than `robots.txt Disallow: /`. `robots.txt` blocks *crawling* but a URL discovered out-of-band (e.g., Certificate Transparency log enumeration — how Googlebot found these subdomains per #3297) can still be *indexed* without a snippet. `X-Robots-Tag` is the authoritative *indexing* control. This is why the existing infra chose headers, and why the robots.txt alternative in #4575 is the weaker option even where feasible. (Source: Google Search Central — "Robots meta tag, data-nosnippet, and X-Robots-Tag specifications"; corroborated by the in-file comment at `seo-rulesets.tf:264-267`.)

**Related learnings:**
- `knowledge-base/project/learnings/2026-04-18-cloudflare-default-bypasses-dynamic-paths.md` — Cloudflare edge does not act on traffic it doesn't see; foundational to the `api.` no-op diagnosis.
- `knowledge-base/project/learnings/2026-05-05-gsc-indexing-triage-patterns.md` — the GSC triage that originally surfaced these subdomains.
- `knowledge-base/project/learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md` — verifying a Transform Rule fires on a CF-Access challenge response (relevant to why `deploy.`'s rule fires despite the 403).

**Trackers / provenance (verified via `gh issue view`):**
- #4575 (OPEN, this issue) — `priority/p3-low`, `type/chore`, `domain/engineering`, milestone "Post-MVP / Later".
- #3379 (OPEN) — "infra: Re-evaluate api.soleur.ai X-Robots-Tag no-op (proxy or remove)" — the owning tracker for the `api.` half.
- #3297 (CLOSED) — "feat(seo): fix GSC critical indexing issues" — shipped the original rules via PR #3296.
- #4573 (parent PR) — flipped docs canonical host www→apex; deferred the api/deploy subdomains here.

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. (This plan's section is complete: threshold = `aggregate pattern`.)
- **Do not file a new tracking issue for the `api.` proxy decision** — #3379 already owns it. A new issue double-counts the backlog (the exact anti-pattern the code-review-overlap gate guards against).
- **Confirm the test runner before hardcoding** — `apps/web-platform` has historically been vitest, and `bunfig.toml` may carry `[test] pathIgnorePatterns = ["**"]` that makes `bun test <file>` report "filter did not match". Read `package.json scripts.test` first.
- **The guard must read the `.tf` as source text, not parse HCL** — there is no HCL parser in the toolchain; a regex/substring assertion against the file string is the correct, dependency-free shape. Anchor on `http.host eq "deploy.soleur.ai"` + `X-Robots-Tag` + `noindex, nofollow` so a value-only regression (e.g., dropping `nofollow`) is caught (AC2).
- **`Ref #4575`, not `Closes #4575`, in the PR body** — the issue close is a post-merge step (after AC7 live verification), per the ops-remediation `Ref`-not-`Closes` pattern; `Closes` would auto-close at merge before the live curl confirms behavior held.
