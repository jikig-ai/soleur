# Tasks — ADR-194 Cloudflare Pages migration, PR4 (DNS cutover) + PR5 (retire GitHub Pages)

Plan: `knowledge-base/project/plans/archive/20260903-221104-2026-08-20-chore-migrate-docs-site-to-cloudflare-pages-plan.md`
Issue: #7640 (OPEN — closed by **PR4b**, not earlier)
Branch: `feat-one-shot-7640-pr4-dns-cutover-pr5-retire-gh-pages` (PR4a; reaped by
`cleanup-merged` once PR4a squash-merged) -> `feat-one-shot-7640-pr4b-apex-cname-flip` (PR4b).
This spec dir stays put: it is the canonical PR4+PR5 task list and PR5 still runs from it.
Lane: `cross-domain` (spec.md absent → fail-closed default, TR2)

**The cutover ships as TWO merges** (plan §D5). Terraform core supplies the ordering; there is
no pre-pass, no plan-JSON gate and no between-assert. Do not re-derive that decision — its
rejected alternatives are in the Cut List with the measurement that killed each.

## Phase 0 — Pre-flight (blocking, before any `.tf` edit)

- [x] 0.1 Re-run `bash apps/web-platform/infra/apex-origin-probe.sh` (PF-Z2). Expect
      `SERVING-FROM-GITHUB-PAGES`, rc 0. `UNREACHABLE` blocks; a Cloudflare verdict means STOP.
- [x] 0.2 Re-run R8 (PF-R8b): apex = 4 proxied `A` + MX/TXT, **no** `CNAME`; `www` = 1 proxied
      `CNAME` at `jikig-ai.github.io`.
- [x] 0.3 PF-SYM: on a scratch zone name, create a `CNAME`, attempt an `A`, record the error
      code, delete. Measure `81053` in the direction a mistaken revert would hit.
- [x] 0.4 PF-TARGET: confirm **both** `-target=cloudflare_record.github_pages` and
      `-target=cloudflare_record.pages_apex` are in `apply-web-platform-infra.yml`'s allow-list,
      line-anchored. A `moved` block with one endpoint untargeted **hard-errors** the apply.
- [x] 0.5 PF-DEFER: `gh issue view <N>` the deferred-cleanup issue, or file it (AC52).
      **DONE 2026-09-03 — it did not exist across two sessions, so PR4b FILED it: #7799.**
      The plan's `## Encryption Posture` `tracking_issue:` now cites it by number rather
      than as a description. It carries the `ssl = "full"` removal conditions, both of
      which must hold.
- [x] 0.6 PF-SSL: `seo-config-rules.tf` carries exactly one `ssl = "full"`. **Do not touch it**;
      PR #7753 owns its guard.

## Phase 1 — PR4a: shrink the apex to one `A` record

- [x] 1.1 Write Guard 2 `apps/web-platform/infra/apex-single-node-replace.test.sh` **from the
      mutation matrix first** (plan §Guard Contract → Guard 2). Rows M1-M9, harness H1-H3.
- [x] 1.2 Register it in `.github/workflows/infra-validation.yml` beside the
      `www-apex-canonicalizer` invocations. Anchor the AC on the **invocation** line (AC65).
- [x] 1.3 Verify H3: the guard is green on the PR4a shape, or it blocks its own PR and every
      unrelated infra PR in the two-merge window.
- [x] 1.4 `dns.tf`: `cloudflare_record.github_pages`'s `for_each` → `toset(["185.199.108.153"])`.
      Leave `www` and `github_pages_challenge` byte-unchanged (AC63).
- [x] 1.5 Extend the cutover runbook with the two-merge procedure **and the `git revert`
      prohibition** — before the first destructive merge, not after.
- [x] 1.6 PF9a: plan shows 3 deletes, 0 creates, `destroy_count = 3`, nothing else touched.
- [x] 1.7 Merge with `[ack-destroy]` on its own line. Then AC60: verify it landed in the squash
      body (`git log -1 --format=%B`).
- [x] 1.8 PF-APEX: apex still resolves and serves 200 across 3 samples.

## Phase 2 — PR4b: flip the survivor to a `CNAME`

- [x] 2.1 `dns.tf`: add the `moved` block (`from` = the key PR4a left behind, **byte-identical**;
      `to = cloudflare_record.pages_apex`); declare `pages_apex` with `name = "soleur.ai"`
      (never `@`), `type = "CNAME"`, `content = cloudflare_pages_project.docs.subdomain`,
      `proxied = true`, `ttl = 1`; retarget `www`'s `content`; keep `www` a **CNAME** (Camp B).
- [x] 2.2 Rewrite the contract comment **in dot-notation** — a comment quoting the declaration
      verbatim false-fails AC43's absence grep.
- [x] 2.3 Build `apps/web-platform/infra/generate-apex-rollback-pr.sh` + its `.test.sh`. Its
      strongest test: the generated `dns.tf` is **byte-identical to `dns.tf` as PR4a left it**.
- [x] 2.4 Add the cache-buster to `apps/web-platform/infra/apex-origin-probe.sh`; keep all three
      verdicts and both AP-021 `UNREACHABLE` arms (AC61).
- [x] 2.5 Build `apps/web-platform/infra/cutover-verify.sh` (CUT0′-CUT9 runner) and commit
      `cutover-mx-txt-baseline.txt` as a sorted, normalised fixture for CUT9 (AC62).
- [x] 2.6 Flip the `## Observability` `discoverability_test.expected_output` to
      `SERVING-FROM-CLOUDFLARE-PAGES` in this hunk (AC59).
- [x] 2.7 Amend ADR-194: Z falsified, single-address replace ordered by Terraform core, the
      `git revert` finding, the rejected alternatives. **Amendment — no new ordinal** (AC51).
- [x] 2.8 Runbook: the `git revert` prohibition at the rollback **step** in the imperative
      (AC71); the two-step rollback; PF8′; the mid-replace recovery line; the concurrency-queue
      cost against T+20 (AC50).
- [x] 2.9 PF9b: one address, actions `["delete","create"]`, `(moved from …)` annotation, plus the
      in-place `www` update; through `destroy-guard-filter-web-platform.jq`:
      `resource_deletes: 1, nested_deletes: 0, reboot_updates: 0, host_creates: 0`.
- [x] 2.10 Re-run PF-Z2 / PF-R8b within the hour before merging (AC49).
- [x] 2.11 Merge with `[ack-destroy]`. AC60 again on the squash body.

## Phase 3 — Post-merge verification (automated; no operator action)

- [x] 3.1 **PF8′ immediately:** run the generator, push, `gh pr create` the reverse-`moved`
      rollback PR with `[ack-destroy]` for its own squash message. **NOT `git revert`.**
      Assert the ack by reading the branch commit body, not `gh pr view --json` (AC53).
- [x] 3.2 Wait 5 min, then run the CUT0′-CUT9 runner: **3 consecutive clean samples
      at 60 s.** Do not invoke it bare — it needs `CUTOVER_SINCE` (so CUT8 grades
      only post-cutover checks) and a Doppler wrapper (so CUT8 can reach Sentry and
      BetterStack at all). The exact block, including how `PF_SHA` must be derived,
      is in `knowledge-base/engineering/operations/runbooks/cloudflare-pages-cutover.md`
      §"Verifying the cutover". Invoked bare it reports five unverifiable monitors
      and exit 2, and the only guidance for exit 2 is "re-run".
      **CUT0′ compares against PF-DOCS's recorded SHA, cache-busted — not the merge SHA**
      (`deploy-docs.yml` deliberately does not fire on `dns.tf`).
- [x] 3.3 Decision point at T+20: on any failure merge the generated rollback PR; then re-probe
      and revert PR3 **only if** still `SERVING-FROM-CLOUDFLARE-PAGES`. Never debug forward.
- [ ] 3.4 AC23: dispatch `deploy-docs.yml`; satisfied by the **per-leg table**, not the run
      **UN-TICKED 2026-09-03 by PR5's review — the tick was not supported.** AC23 requires
      "an explicitly dispatched run, not … an unrelated future commit"
      (`cq-ac-must-not-depend-on-concurrent-sessions`). Measured: `gh run list
      --workflow=deploy-docs.yml --limit 100` shows exactly ONE `workflow_dispatch`, on
      2026-08-19, two weeks BEFORE the cutover. Both post-cutover runs were `push` /
      `workflow_run` — precisely the unrelated-future-commit shape the AC forbids. The
      per-leg table WAS green on those runs, so the underlying property holds; what is
      missing is the dispatch AC23 names. Discharge post-PR5-merge with an explicit
      `gh workflow run deploy-docs.yml` and record the run id here.
      conclusion — the GitHub Pages leg is red by construction until PR5.
- [x] 3.5 #7640 closes via `Closes #7640` in PR4b's body.

## Phase 4 — PR5: retire the GitHub Pages publish leg

- [x] 4.1 `deploy-docs.yml`: delete the three Pages actions, `environment: github-pages`, and
      `pages:`/`id-token: write`; remove the verdict step's GitHub-Pages arm. **Probe B
      survives.** Use the exit-safe guarded count form (AC33).
- [x] 4.2 `model.c4`: flip the two genuinely anticipatory phrasings only — *"until the #7640
      cutover"* and *"From the cutover…"*. **Leave the `cloudflare` element's "from
      #7640/ADR-194"**; it is a provenance citation, not tense (AC55).
- [x] 4.3 Runbook + deferred-cleanup issue: PR5 **narrows the rollback** to three acts (AC56).
- [ ] 4.4 `Ref #7640` in the body, not `Closes` (AC57). — completes when the PR body is written.
- [ ] 4.5 Merge only after CUT0′-CUT9 hold, same session as PR4b (AC34). — the PRECONDITION
      is satisfied (CUT held 19:26-19:28Z, same session); the tick completes at merge, and
      AC34's second clause — PR5's own `deploy-docs.yml` merge run green with Probe B MATCH
      — is verifiable only from that run.
- [x] 4.6 Archive the plan with `archive-kb.sh` — **PR5 only** (AC58). Done: the plan and
      BOTH #7640 spec dirs are archived, and the six live citations of the old plan path
      (gh-pages-cert-renewal, principles-register AP-019, ADR-125, ADR-194 x2, domains.md)
      were repointed in the same edit cycle. The cutover runbook now cites the archived
      path, per AC58's second clause. `archive-kb.sh` needed TWO invocations with two
      slugs: it globs plans by `*<slug>*` and specs by `feat-<slug>`, and this plan's
      filename is topic-based, so no branch-derived slug reaches it.


## Completion record (2026-09-03)

- **Phase 2 + Phase 3** shipped as **PR4b** (`99eeebfef`, #7793). `[ack-destroy]`
  verified on its own line in the SQUASH body via `git log -1 --format=%B`; the
  apply succeeded and the apex is a single proxied `CNAME` to
  `soleur-docs.pages.dev` with zero `A` records. CUT0'-CUT9 held across three
  consecutive clean samples (19:26:02Z / 19:27:10Z / 19:28:17Z), 10 passed / 0
  failed / 0 unreachable each — 11 minutes inside the T+20 deadline. #7640 closed
  at 19:17:30Z. The PF8' rollback PR (#7802) was generated within two minutes of
  the merge and closed unused; regeneration is one command.
- Two CUT anomalies, both diagnosed and neither the apex: CUT0' failed its first
  sample on a **stale pin** (this PR was not `dns.tf`-only — the compound commit
  matched `deploy-docs.yml`'s `plugins/soleur/skills/**` push filter, so the merge
  published a newer docs build), and CUT8 read UNREACHABLE because
  `soleur-ai-changelog-deep` runs at `interval_seconds = 600` and the first sample
  ran 52 s before any post-`CUTOVER_SINCE` check could exist.
- **Phase 4** is this PR. 4.4-4.5 complete at PR-body-write and merge; 4.6 landed here.
- **A prediction in this plan was FALSIFIED, and PR5's review caught it.** Task 3.4
  and the plan both said the GitHub Pages leg would be "red by construction" after the
  PR4b apply, because GitHub's custom-domain DNS check fails once the apex `A` records
  are gone. Measured: every post-apply `deploy-docs.yml` run reported `Deploy to GitHub
  Pages: success` — `gh api repos/{owner}/{repo}/pages` returns `build_type: workflow`,
  and a workflow-source deployment does not gate on that check. The correction is
  load-bearing rather than cosmetic: because `deploy-pages` succeeds while DNS points at
  Cloudflare, act 2 of the three-act rollback is executable BEFORE act 3, which is what
  makes the documented ordering valid at all.

## Standing constraints

- `ssl = "full"` **stays**. Do not remove it; do not co-locate PR #7753's work here.
- **PR4b must NOT remove the `ssl = "full"` rule, and this is the sharpest trap
  in the whole migration.** `ssl-full-mitigation.test.sh` resolves its stage from
  a three-way OR over `dns.tf` — apex GitHub-Pages IPs present, `www` still
  CNAME'd at `jikig-ai.github.io`, or the `github_pages` block still declared.
  PR4b drives all three to zero in ONE commit, flipping the guard to
  `post-cutover`, where all nine mitigation assertions become unconditional
  passes and the rule reads as deletable. It is not: if PR4b is then rolled back,
  the stage returns to `pre-cutover` with the rule gone and the apex at HTTP 526
  against an origin certificate that expired 2026-08-16.
- **Reverting PR4a AFTER PR4b has merged is unsafe in a way git will not show
  you.** PR4b deletes the `github_pages` block, so a revert of PR4a conflicts on
  `dns.tf` — but NOT on `apex-single-node-replace.test.sh`, its battery,
  `infra-validation.yml`, or `guard-vacuity-floor.test.sh`. Resolving that
  conflict with "keep PR4b's `dns.tf`" lands a tree with the flip in place and
  the guard plus its registration silently deleted.
- **PF9b must be mechanized in PR4b, not read by eye (AC72).** The guard is
  static, so it cannot see repo-vs-STATE drift: a consistent rename of the pin
  and the `dns.tf` key passes 11/11 while state still holds the old key, and a
  PR4a that merges without converging (`[skip-web-platform-apply]`, or a failed
  apply) leaves state holding four instances while the repo says one. In both
  cases PR4b's `moved` no-ops and the hazard returns silently — and
  `[ack-destroy]` cannot discriminate, because `destroy_count` is 1 in the
  correct plan and 1 in the broken one. The apply job already pipes plan JSON
  through `destroy-guard-filter-web-platform.jq`; one clause asserting the
  `pages_apex` change carries
  `previous_address == cloudflare_record.github_pages["185.199.108.153"]` is the
  only check in the system that is about state rather than about text.
- **Bound the PR4a->PR4b window explicitly.** Between the merges the apex has one
  origin address instead of four, so Cloudflare has no retry target on an
  origin-pull failure — on an HSTS-preloaded apex, with a 180 s email-only
  monitor as the automated backstop. If PR4b has not merged by the end of the
  session, revert PR4a: it plans 3 creates / 0 destroys and applies unattended.
- `www` stays a **CNAME**. `type` is ForceNew at provider 4.52.7 (measured).
- Do not archive the plan until PR5.
- `git revert` is **forbidden** for PR4b.
