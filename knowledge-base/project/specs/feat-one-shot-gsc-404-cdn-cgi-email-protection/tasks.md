# Tasks — fix GSC "Not found (404)" `/cdn-cgi/l/email-protection`

Derived from
`knowledge-base/project/plans/2026-07-20-fix-gsc-404-cdn-cgi-email-protection-plan.md`
(post-plan-review + post-deepen-plan).

**Read the plan's Decision and Sharp Edges before starting.** The decision was **reversed
at deepen-plan**: the remedy is a host-scoped Cloudflare Configuration Rule, **not** a
`Disallow: /cdn-cgi/` in robots.txt. Google explicitly advises against robots-blocking
404s, and this repo already has a learning about the trap that creates.

**Do NOT**, under any circumstances:

- add `Disallow: /cdn-cgi/` to `plugins/soleur/docs/robots.txt` (rejected — Option B);
- disable Email Obfuscation zone-wide via `cloudflare_zone_settings_override` (rejected — Option A);
- add a `/cdn-cgi/` check to `plugins/soleur/skills/seo-aeo/scripts/validate-seo.sh`
  (distributed plugin skill; would break consumer sites and the green 21-test suite);
- add a `scripts/followthroughs/` probe for `api.soleur.ai` (would auto-close #3379).

---

## Phase 0 — Preconditions

- [x] 0.1 Confirm branch: `git branch --show-current` →
      `feat-one-shot-gsc-404-cdn-cgi-email-protection`
- [x] 0.2 Capture the **baseline census** so AC9 has a before/after. Expected today:
      `/`=0, `/getting-started/`=2, `/pricing/`=1, `/legal/privacy-policy/`=20,
      `/legal/terms-and-conditions/`=7.
      ```bash
      UA="Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)"
      for p in "" "getting-started/" "pricing/" "legal/privacy-policy/" "legal/terms-and-conditions/"; do
        n=$(curl -sS -A "$UA" "https://soleur.ai/$p" | grep -o 'cdn-cgi/l/email-protection' | wc -l | tr -d ' ')
        echo "/$p -> $n"
      done
      ```
      Use `grep -o … | wc -l`, never `grep -c` (counts lines, undercounts on minified HTML).
- [x] 0.3 Confirm baseline suite green: `cd apps/web-platform && npm run test:ci`
- [x] 0.4 Read `apps/web-platform/infra/seo-rulesets.tf` (comment density + `cloudflare.rulesets`
      provider alias) and `apps/web-platform/test/seo-rulesets-noindex.test.ts`
      (brace-counting text-parse approach to mirror). Per `hr-always-read-a-file-before-editing-it`.
- [x] 0.5 Confirm the provider alias name and `var.cf_zone_id` in
      `apps/web-platform/infra/main.tf` / `variables.tf`.

## Phase 1 — RED: source guard

- [x] 1.1 Create `apps/web-platform/test/seo-config-rules.test.ts` (**vitest**;
      `apps/web-platform/vitest.config.ts` `unit` project includes `test/**/*.test.ts`).
      Mirror the sibling `seo-rulesets-noindex.test.ts` text-parse approach — `readFileSync`
      + brace-counting, **not** an HCL parser.
- [x] 1.2 Assert `apps/web-platform/infra/seo-config-rules.tf` declares a `cloudflare_ruleset`
      with `phase = "http_config_settings"` and `kind = "zone"`.
- [x] 1.3 Assert a rule with `action = "set_config"` and `email_obfuscation = false`,
      `enabled = true`.
- [x] 1.4 **Blast-radius assertions (load-bearing — both directions).**
      Positive: expression contains `soleur.ai` AND `www.soleur.ai`.
      Negative: expression contains **none** of `app.soleur.ai`, `deploy.soleur.ai`,
      `api.soleur.ai`. The bounded scope is the property that distinguishes this from the
      rejected zone-wide Option A — assert it explicitly.
- [x] 1.5 Assert the new resource address appears in the `-target=` allow-list in
      `.github/workflows/apply-web-platform-infra.yml`. Without this the rule is committed
      but never applied — the silent-no-op class #3379 already documents.
- [x] 1.6 Confirm RED:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/seo-config-rules.test.ts`

## Phase 2 — GREEN: the Terraform rule

- [x] 2.1 Create `apps/web-platform/infra/seo-config-rules.tf` per plan §Phase 2 step 4.
      **Verify every attribute name against the pinned provider (4.52.7) before writing** —
      do not copy the plan's illustrative block blindly.
- [x] 2.2 Carry a comment block explaining why: the GSC 404, the 30 hrefs, why not
      robots.txt (Google's "don't block 404s" + the `2026-06-14` learning), why host-scoped
      not zone-wide. Match the comment density of `seo-rulesets.tf`.
- [x] 2.3 Add the resource to the `-target=` allow-list in `apply-web-platform-infra.yml`.
- [x] 2.4 **Sweep every guard suite** asserting on that list — orphan suites are the ones
      plans reliably miss:
      `git grep -ln 'cloudflare_ruleset\|\-target=' scripts/ apps/web-platform/infra/*.test.sh`
      Update every hit.
- [x] 2.5 Confirm GREEN:
      `cd apps/web-platform && ./node_modules/.bin/vitest run test/seo-config-rules.test.ts`
- [x] 2.6 Confirm the gate can FAIL (AC2): flip `email_obfuscation` to `true` → test fails;
      add `app.soleur.ai` to the expression → test fails; restore → passes. Do not skip.
- [x] 2.7 Full suite green: `cd apps/web-platform && npm run test:ci` — especially the 3
      existing `api.soleur.ai` tests in `seo-rulesets-noindex.test.ts`.
- [x] 2.8 `terraform fmt -check` + `terraform validate` in `apps/web-platform/infra/`.
      Use the canonical Doppler triplet (raw `AWS_*` exports for the R2 backend, then
      `--name-transformer tf-var`) — see
      `knowledge-base/project/learnings/2026-05-09-drift-runbook-canonical-tf-invocation-and-fresh-plan.md`.
      Without `tf-var`, ~13 required variables fail to resolve.

## Phase 2.9 — PREREQUISITE: token scope widen (BLOCKING, discovered at /work)

**The plan and its review panel missed this.** The `cloudflare.rulesets` alias token
(`var.cf_api_token_rulesets`) did not carry the Configuration-Rules permission that the
`http_config_settings` phase requires, so the resource as planned would commit, enter the
auto-apply `-target=` list, and then **403 on apply** — the silent-no-op class #3379 already
documents on this zone.

Verified by live probe against Doppler `soleur/prd_terraform`:

| Probe | Result |
|---|---|
| `http_config_settings` entrypoint | **403** `request is not authorized` |
| `http_request_dynamic_redirect` entrypoint (control) | **200** |

Every other CF token in `prd_terraform` was probed against `http_config_settings` — all 403.
No token holds `User API Tokens:Edit` (all 403 on `GET /user/tokens`) and there is no Global
API Key, so the widen requires the Cloudflare dashboard.

Routed to the `soleur:engineering:cto` agent per the architectural-fork rule (two competing
in-repo precedents: widen-existing per #5092 vs. mint-narrow-alias per `cf_api_token_r2`).
**Ruling: widen the existing token** — same API family and zone; widening moves no secret
material, so it adds no no-default root variable, whose absence would fail the WHOLE
merge-triggered apply rather than just this resource.

- [x] 2.9.1 Update the `cf_api_token_rulesets` description in `variables.tf` (it IS the
      scope ledger) and the `cloudflare.rulesets` consumer list + decision rule in `main.tf`.
- [x] 2.9.2 **DONE 2026-07-20** — appended `Config Rules:Edit` (zone, soleur.ai) to
      `terraform-soleur-ai-rulesets` via the Cloudflare dashboard. Browser transport
      (Playwright MCP) worked on re-attempt this session, so #6755's premise no longer
      holds — this was NOT operator-only. Two notes for any future re-scope:
      - The UI labels the permission **`Config Rules`**, not "Configuration Rules".
        ADR-130's "probe, never trust the permission label" warning is why this was
        found by enumerating the option list rather than by typing a guessed name.
      - The dashboard edit form **prefills all existing permission rows** and exposes an
        `Add more` button, so this path is an APPEND, not a replace. Verified by reading
        the form's DOM values before submit and by the pre-submit summary page, which
        listed all 6 originals plus the new one.
- [x] 2.9.3 Retained-scope probe set — **4/4 PASS** (2026-07-20, post-widen):
      | probe | before | after |
      |---|---|---|
      | `zones/$ZONE/rulesets/phases/http_config_settings/entrypoint` | 403 | **200** |
      | `zones/$ZONE/rulesets/phases/http_request_dynamic_redirect/entrypoint` | 200 | 200 |
      | `zones/$ZONE/rulesets/phases/http_request_cache_settings/entrypoint` | 200 | 200 |
      | `accounts/$ACCT/rulesets` | 200 | 200 |
      The widen took effect and nothing was lost — no scope replaced.
- [x] 2.9.3b **Entrypoint-enumeration probe — FAILED CLOSED, then RESOLVED by adoption.**
      The probe did exactly what it was added to do. `http_config_settings` returned
      **200, not 404**: the entrypoint already exists (`a21ac79d368f425a95c895c43a090d57`,
      `kind=zone`, version 1, last updated 2026-03-17) and **carries one live
      dashboard-created rule Terraform has no knowledge of**:

      ```
      description: "Flexible SSL for web platform"
      expression:  (http.host eq "app.soleur.ai")
      action:      set_config { ssl: "flexible" }
      enabled:     true
      ref:         dcb85b75bc3c4f4aa2a8c13a080bf854
      ```

      `cloudflare_ruleset.seo_config_settings` is `kind = "zone"` on this same phase, so
      it OWNS the entrypoint as a whole-list replacement, and it declares exactly one
      `rules` block. A first apply would therefore **silently delete the Flexible SSL
      rule**, dropping `app.soleur.ai` to the zone-level SSL mode. If that mode is
      Full/Strict and the origin has no valid cert, the web platform goes down. This is
      an outage-class risk, not a lint.

      `terraform plan` still reports "1 to add" and cannot see any of this — the exact
      gap recorded in `knowledge-base/project/learnings/
      2026-07-20-a-plan-can-prescribe-a-resource-its-credential-cannot-create.md`.

      **RESOLVED 2026-07-20 by adoption** (operator chose inline over a separate PR):
      - the rule is reproduced verbatim as the FIRST `rules` block, and
      - a declarative `import` block (needs **TF >= 1.7** — `for_each` on an import
        block landed in 1.7.0; `main.tf` said `>= 1.6` and was corrected at review —
        so no manual CLI step and no operator action,
        `hr-never-label-any-step-as-manual-without`) adopts ruleset
        `a21ac79d368f425a95c895c43a090d57` via **`zone/<zone_id>/<ruleset_id>`**
        (SINGULAR — the plural `zones/` form below is the v5 syntax that fails).
      `name`/`description` now mirror the live entrypoint (`"default"` / empty) so the
      plan is one legible `+1 rule` change, not a real change mixed with cosmetic churn.
      Tests 7 → 11: exactly-one-rule became exactly-two, plus pins on the adopted rule
      (expression, `ssl = "flexible"`, and `ref`), on each rule's action_parameters KEY
      SET, and on the import block being REACHABLE — not merely present. The first
      version of those import pins was vacuous: three reviewers independently mutated
      `for_each` to `toset([])`, inverted the ternary, deleted `provider =`, and swapped
      `zone/`→`zones/`, and all four survived 10/10 green. Each is now a caught mutant.
      Scope assertions now select by action parameter, not position — the adopted rule
      legitimately targets `app.soleur.ai`, which is in `OUT_OF_SCOPE_HOSTS`, so the old
      iterate-every-rule form would have failed on the rule it is not about.
      **Mutation-verified capable of failing** (not merely green): deleting the adopted
      rule fails 2 tests, `flexible`→`full` fails 1, deleting the import block fails 1.
      `terraform validate` and `terraform fmt -check` both pass. Generalisation — every
      other `kind = "zone"` ruleset in the repo has the same unaudited exposure —
      remains open in #6767.
- [x] 2.9.4 Paste the four status codes into the PR body, then mark ready.
      Codes are pasted (PR body → Blocker §1). Task 3.1 was re-run against the SHIPPED
      config (with the `for_each` gate and the `ref` pin) and reports
      `Plan: 1 to import, 0 to add, 1 to change, 0 to destroy` — see 3.1.

**Do not mark PR #6746 ready until 2.9.2–2.9.4 are green.**

## Phase 3 — Plan review of the apply

- [x] 3.1 ~~`terraform plan` → confirm **1 to add, 0 to change, 0 to destroy** (AC4).~~
      **SUPERSEDED by 2.9.3b, re-run 2026-07-20 against live state:**

      ```
      Plan: 1 to import, 0 to add, 1 to change, 0 to destroy.
      ```

      The single change is `+1 rule`; the adopted Flexible SSL rule appears in the diff
      with action, description, enabled, expression and `ssl = "flexible"` all unchanged
      (its `id`/`ref` show `-> (known after apply)` — the v4 provider writes a ruleset as
      one whole-list PUT, so Cloudflare reassigns rule IDs; atomic, effect preserved).
      **A plan reporting "1 to add" means the import block was dropped.**

      Running this is what caught two defects that would have failed the apply — the
      import block as first written could not have worked:
      - **Import ID was v5 syntax.** `zones/<zone_id>/<ruleset_id>` is what the provider's
        `main`-branch docs show; we are pinned to **4.52.7**, which wants singular
        `zone/<zone_id>/<ruleset_id>`. v4 does not reject the unknown prefix — it falls
        through to the account path and issues `GET /accounts/<zone_id>/rulesets/<id>`,
        a zone ID in an accounts URL, surfacing as `Authentication error (10000)`. That
        error names authentication, so it reads as token scope and sends you back to
        re-probe a credential that was already correct.
      Same lesson as task 2.1's "verify against the pinned provider, do not copy the
      illustrative block" — this time for the import ID rather than an attribute name.

      **Correction (review, 2026-07-20).** This task originally listed a SECOND defect:
      "`provider` is not inherited by an import block". **That was wrong** — an import
      block DOES inherit its target resource's provider. Measured both directions: with
      `provider =` removed and the DEFAULT provider's token replaced by garbage, the plan
      still reported `1 to import`; and with the `rulesets` alias pointed at an invalid
      host, the import read failed on *that* host. The `zones/`→`zone/` ID fix alone
      resolved the original failure. The evidence was already visible at the time — adding
      `provider` produced a byte-identical error — and was not read. `provider =` is kept
      for legibility and is now pinned by a test, but it is not required. Two changes were
      in flight, one was load-bearing, and the write-up credited both.
- [x] 3.2 Confirm no excluded resource (`hcloud_server.web`, `hcloud_volume.workspaces`,
      volume attachments, SSH keys) appears — `-target` is transitive on dependencies.

## Phase 4 — Follow-ups (do not fold into the diff)

- [x] 4.1 File the **28-day GSC re-check** issue (AC12), due merge+28d → **#6788**,
      filed at ship time rather than post-merge (a promise to file after merge is exactly
      the rot the follow-through substrate exists to prevent).
      Enrolled in the sweeper: `scripts/followthroughs/gsc-404-cdn-cgi-census-6746.sh`,
      `earliest=2026-08-17T09:00:00Z` (merge + 28d). The task note that "the AC9 census
      **is** automatable" was acted on rather than left conditional — the script re-runs
      the 5-path Googlebot census and passes only at 0, so the mechanical gate is the
      census, not a dashboard eyeball (`hr-no-dashboard-eyeball-pull-data-yourself`).
      Dry-run at filing time returned FAIL with the exact baseline 0/2/1/20/7 = 30,
      proving it discriminates rather than certifying silence. GSC coverage-**validation**
      state has no API and stays human, but it is strictly downstream: zero hrefs ⇒ the
      404s stop on Google's next crawl.
- [ ] 4.2 Optionally file the "Book intro" CTA → booking-link conversion follow-up
      (`decision-challenges.md` §Also noted). Low priority, separate concern.

## Phase 5 — Ship

- [x] 5.1 AC6: `git diff --name-only origin/main...HEAD` contains **no**
      `plugins/soleur/docs/robots.txt` — the rejected Option B must not leak back in.
- [x] 5.2 PR body uses **`Ref #3379`**, not `Closes`. Verified 2026-07-20: body line 86 is
      `Ref #3379`; no `Closes`/`Fixes`/`Resolves` anywhere in the body.
- [ ] 5.3 Ensure `/ship` surfaces `decision-challenges.md` into the PR body and files the
      `action-required` issue.
- [ ] 5.4 Post-merge operator steps are AC8–AC12. **AC9 is load-bearing** — it is the only
      proof Cloudflare honours the rule; source assertions cannot establish it. AC11 (GSC
      "Validate Fix") is genuinely human-only (no API); justification is inline in the plan.

---

## Acceptance criteria mapping

| AC | Task |
|---|---|
| AC1 (rule assertions incl. scope) | 1.2, 1.3, 1.4 |
| AC2 (gate can fail) | 2.6 |
| AC3 (full suite green) | 0.3, 2.7 |
| AC4 (clean 1-add plan) | 3.1, 3.2 |
| AC5 (-target + guard sweep) | 2.3, 2.4, 1.5 |
| AC6 (no robots.txt in diff) | 5.1 |
| AC7 (`Ref #3379`) | 5.2 |
| AC8–AC12 (post-merge operator) | 0.2 baseline, 5.4 |
