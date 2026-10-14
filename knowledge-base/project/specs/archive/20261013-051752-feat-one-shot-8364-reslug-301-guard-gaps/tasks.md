# Tasks — feat-one-shot-8364-reslug-301-guard-gaps

Plan: `knowledge-base/project/plans/2026-09-20-feat-seo-redirect-coverage-guard-gaps-plan.md`
Issue: #8364 — feat(seo): close residual redirect-coverage guard gaps
(reslug tombstones, runtime 301 monitor, zone-ruleset source pin).

Guard-contract note: every guard below ships with its mutation battery in
the same commit — a guard that has never gone red is not evidence.

## Phase 0 — Verify premises (all commands already live-run at plan time; re-run)

- [x] `git cat-file -e 35259f264` (baseline = PR-B squash merge exists)
- [x] Re-probe the three monitor URLs: `curl -s -o /dev/null --max-time 15
      -w '%{http_code} -> %{redirect_url}\n'` for
      `https://soleur.ai/pages/agents.html`,
      `https://soleur.ai/pages/legal/privacy-policy.html`,
      `https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/` —
      expect `301` on all three.
- [x] Run the all-history enumerator
      `git log --diff-filter=RD -M --name-status -- plugins/soleur/docs/`
      (28 events at plan time) — capture output; it is the seed-audit input.
- [x] Read the latest `SOLEUR_HEARTBEAT_RECONCILE_INVENTORY` marker count
      (Better Stack free-tier object headroom before adding 3 monitors).

## Phase 1 — Parser contract first (G5a; G1 precondition)

- [x] `plugins/soleur/test/lib/bulk-redirect-pairs.ts`: duplicate
      `source_url` throws `Error` naming both occurrences (kill Map.set
      last-wins masking). Add expansion of a new
      `local.tombstone_redirect_pairs` map (3 source shapes per pair, same
      as `blog_redirect_pairs`).
- [x] Update consumers as needed:
      `plugins/soleur/test/seo-aeo-drift-guard.test.ts`,
      `plugins/soleur/test/marketing-content-drift.test.ts` (verified via
      `git grep` — `validate-seo.test.ts` is NOT a consumer).
- [x] Mutation row: inject a duplicate `source_url` into a copied tf →
      parse throws (asserted in the new tombstone suite or a parser test).

## Phase 2 — Tombstone gate (G1 + G6)

- [x] New `plugins/soleur/test/redirect-tombstones.test.ts` (bun:test):
      - History anchor `HISTORY_ANCHOR = "35259f264…"` (named in review);
        `git cat-file -e` + `--is-shallow-repository` preflight fails loudly
        (never skips).
      - Enumerate `git log --diff-filter=RD -M --name-status
        <baseline>..HEAD -- plugins/soleur/docs/`; derive per-event URL
        sets per the plan's derivation rules (dated post → 6 shapes;
        undated post → 3; pages → `permalink:` from baseline blob;
        `R` with changed derivation → old URL set; `-G'permalink:'`
        removals on surviving files).
      - Census: every event classifies covered-or-exempt;
        `TOMBSTONE_EXEMPT` entries carry an issue ref; unclassified = FAIL.
        RED output prints the derived URL set + a copy-paste-ready
        `tombstone_redirect_pairs` entry (actionable failure, spec-flow
        lens).
      - Coverage set from the extended parser (items ∪ blog pairs ∪
        tombstone pairs ∪ zone-ruleset path literals).
      - Mutation battery over synthesized git repos (mkdtemp + git init):
        uncovered D → red; covered D → green; date-only R → requires
        dated-family coverage; permalink removal → red unless covered;
        `_data/` D → ignored; missing baseline → red.
- [x] `apps/web-platform/infra/seo-bulk-redirects.tf`: add
      `local.tombstone_redirect_pairs`, rename list-feeding local to
      `redirect_items = concat(<dated>, <tombstone>)`, keep
      `dynamic "item"` shape; `# tombstone:` comment per entry.
- [x] Seed audit: run enumerator with baseline overridden to repo root;
      seed `tombstone_redirect_pairs` (known:
      `blog/ai-agents-cron-without-exfiltrating-secrets →
      https://soleur.ai/blog/`) and exemptions.
- [x] `seo-aeo-drift-guard.test.ts` (G6): tombstone expansion pins; every
      bulk-list source path absent from the suite's mkdtemp Eleventy build
      (`tmpSite`); every `target_url` resolves to a built page; extend
      expected map with seeded tombstone source_urls; update
      `for_each = local\.blog_redirect_items` pin → `redirect_items`.
- [x] `scripts/validate-blog-links.sh`: update the `dynamic "item"` grep if
      the pin text changed.

## Phase 3 — Zone-ruleset source pin (G3)

- [x] New `apps/web-platform/test/seo-page-redirects-ruleset.test.ts`
      (vitest; `test/**/*.test.ts` glob confirmed):
      `kind="zone"`, `phase="http_request_dynamic_redirect"`, exactly 10
      `rules {}` blocks; per-rule path/301/target pins for the 8 page rules
      (agents, skills, vision, community, getting-started, legal, pricing,
      changelog) + ToS rename; Rule 10 asserted LAST with `not ssl` +
      ACME carve-out + host-preserving `concat()` target; host set
      `{ "soleur.ai" "www.soleur.ai" }` present.
- [x] Create shared `apps/web-platform/test/lib/terraform-hcl-blocks.ts`
      (`extractResourceBody`, `extractRuleBlocks` — deepen-verified: the
      helpers are file-local and already duplicated across
      `seo-rulesets-noindex.test.ts` and `seo-config-rules.test.ts`); migrate
      both existing suites to the import; the new suite consumes it too.
- [x] Mutation battery: drop a rules block; reorder Rule 10; 301→302;
      remove ACME carve-out; change a target.

## Phase 4 — Runtime monitors (G2)

- [x] `apps/web-platform/infra/uptime-alerts.tf`: three STATIC
      `betteruptime_monitor` resources (NO `for_each` — `parseMonitorBlocks`
      throws on it; NO `count` — probes must be unconditional):
      `seo_redirect_zone_ruleset` → `https://soleur.ai/pages/agents.html`;
      `seo_redirect_bulk_item` → `https://soleur.ai/pages/legal/privacy-policy.html`;
      `seo_redirect_blog_pair` → `https://soleur.ai/blog/2026-03-16-soleur-vs-anthropic-cowork/`.
      Clone `soleur_www_redirect` attrs; distinct `pronounceable_name` each.
- [x] `.github/workflows/apply-web-platform-infra.yml`: three `-target=`
      lines beside existing `betteruptime_monitor.*` (~line 706-710). No
      comments inside the backslash-continued list (SC2215).
- [x] `apps/web-platform/infra/www-apex-canonicalizer.test.sh`: `sib_n`
      pin '3'→'6' + comment; check `…-mutation.test.sh` for the same pin.
- [x] New `apps/web-platform/infra/seo-redirect-monitors.test.sh`:
      per-monitor attribute pins; probe-URL ⊆ declared redirect source set
      (cross-file parse); the three `-target=` lines present.
      (Auto-registered via `run-registered-suites.sh` `git ls-files` glob —
      the file MUST be `git add`ed.)
- [x] `uptime-alerts.tf` header + ADR-204: second amendment — sampled
      deep-URL probes are capability-grounded like `soleur_www_redirect`;
      #7883 target-assertion stays open but its detection precondition is
      now met.
- [x] New runbook
      `knowledge-base/engineering/operations/runbooks/seo-redirect-alarm.md`
      (model on `www-redirect-alarm.md`; canonical doppler triplet verbatim).
- [x] `model.c4` betterstack element description refresh; run
      `bash scripts/regenerate-c4-model.sh` (freshness suite guards it).

## Phase 5 — Destroy-guard clause + glob fix (G4, G5b)

- [x] `tests/scripts/lib/destroy-guard-filter-web-platform.jq`:
      `cf_list_item_count($side)` + `select(.type=="cloudflare_list")`
      clause in `nested_deletes`.
- [x] `tests/scripts/test-destroy-guard-counter-web-platform.sh`: header
      5→6 surfaces; synthesized fixture
      `tests/scripts/fixtures/tfplan-cf-list-item-removal.json`; shrink arm
      (reds) + growth arm (stays 0).
- [x] `scripts/validate-blog-links.sh:57`: non-recursive glob →
      `find "$BLOG_DIR" -type f -name '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*.md'`.

## Phase 6 — Verify + ship

- [x] `bash scripts/test-all.sh scripts` and `bun` groups (or diff-scoped
      shards per /work Phase 2 exit) — incl. orphan-suite lint.
- [x] AC sweep (plan §Acceptance Criteria); post-merge ACs recorded for
      /ship (apply run green; reconcile shows 3 matched monitors).
- [x] PR body: `Closes #8364`; `Ref #7883` (stays open).
