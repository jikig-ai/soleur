# Session State

Two sessions have run against this spec. Newest LAST; the PR4a section is history
and its perishable measurements are explicitly stale — see the staleness note there.

---

## Session 1 — PR4a planning (2026-09-03, branch `…-pr4-dns-cutover-pr5-retire-gh-pages`)

### Plan Phase
- Plan file: knowledge-base/project/plans/archive/20260903-221104-2026-08-20-chore-migrate-docs-site-to-cloudflare-pages-plan.md
- Status: complete (with one coordinator-applied repair, below)

#### Errors
- **Planning subagent splice defect — found by the coordinator, not self-reported.** The
  deepen-plan commit (`a6c648604`) spliced the CORRECTED ADR-amendment items 5-7 to the TOP of
  the plan file instead of into their section, leaving 18 orphaned lines above the YAML
  frontmatter (so the file no longer began with `---`) while the in-place copy at the amendment
  section still prescribed the SUPERSEDED two-pass design. The subagent's own duplicate-heading
  sweep could not see this: the stranded text carries no headings. Left unrepaired, `/work`
  would have been instructed to build the dead mechanism. Repaired by relocating lines 1-17 over
  the stale items and restoring the frontmatter to line 1. Verified: `two-pass ordered apply on
  the merge path` now appears 0 times, `single-address replace ordered by` exactly once, no
  duplicate headings, frontmatter parses.
- Subagent self-reported and recovered: an earlier `s.index()` splice duplicated ~1,150 lines.
- **Unresolved, carried not hidden:** the deferred-cleanup issue cited by AC24 could not be
  found by number. Carried as AC52 (PF-DEFER) — PR4 must verify or file it.

#### Perishable measurements — RE-PROBED FRESH 2026-09-03 by the coordinator, not inherited
- Hypothesis Z still FALSE: `apex-origin-probe.sh` -> `SERVING-FROM-GITHUB-PAGES`, rc 0.
- R8 clean: apex = exactly 4 proxied A at 185.199.108-111.153, plus 2 MX + 4 TXT (all unproxied,
  outside the blast radius); www = exactly 1 proxied CNAME at `jikig-ai.github.io`.
- PF-TARGET already satisfied: both `-target=cloudflare_record.github_pages` (line 601) and
  `-target=cloudflare_record.pages_apex` (line 607) are in the apply allow-list; `pages_apex`
  was pre-added by PR3 precisely to close this gap.

#### Decisions
- **Shrink-then-flip replaces the two-pass pre-pass.** Ordering comes from Terraform core at a
  single resource address via a `moved` block. Precedent: `placement-group.tf:23-41`. The
  pre-pass died because `git revert` of the cutover PR deletes the pre-pass along with the DNS
  hunk (`on: push` runs from the merged ref), so rollback would run unordered on a failing apex.
- **PF9's shape is superseded** — not one merge at `destroy_count = 4`, but PR4a
  (`destroy_count = 3`) then PR4b (`resource_deletes: 1`, measured through the real
  destroy-guard filter at provider 4.52.7).
- **`git revert` is FORBIDDEN for PR4b.** PF8' becomes a generated reverse-`moved` rollback PR.
  This RESOLVES PF8's previously-unmet pre-opened revert rather than deferring it, and preserves
  the required two-step revert shape in substance.
- **PF-ORDER relocated, not dropped** — a static `dns.tf` assertion that `create_before_destroy`
  is not set, which is what stops P10 being structurally-satisfied-but-unasserted.
- Binding constraints held: www stays a CNAME (Camp B, now measured — `type` is ForceNew);
  `ssl = "full"` untouched and PR #7753's work not co-located; plan not archived until PR5;
  only PR4b closes #7640.

#### Components Invoked
- soleur:plan, soleur:deepen-plan
- architecture-strategist (spawned then resumed to measure against the live provider),
  spec-flow-analyzer, kieran-rails-reviewer, a scoped advisor consult
- scripts/lint-guard-contract.py (EXIT 0), scripts/lint-infra-no-human-steps.py
  (EXIT 0 in CI's `--changed` form; the repo-wide 532 is a pre-existing backlog CI does not gate)

> **STALENESS — the "Perishable measurements" above are superseded.** They record the
> apex as *"exactly 4 proxied A at 185.199.108-111.153"*. PR4a (`428e1ec78`, merged
> 2026-09-03) shrank that to ONE proxied A at `185.199.108.153`. Re-probe; do not
> inherit. Hypothesis Z (`SERVING-FROM-GITHUB-PAGES`) and PF-TARGET are also
> re-verification targets for PR4b under task 2.10, not settled facts.

> **CARRIED FORWARD, STILL OPEN — AC52 / PF-DEFER.** Session 1 recorded the
> deferred-cleanup issue as unfindable by number. Re-checked 2026-09-03 in session 2:
> it still does not exist. PR4b must FILE it and wire the number into the plan's
> `tracking_issue:` field, which today holds only a prose description — and the plan
> says in terms that "a tracking_issue named only as a description is not a tracking
> issue." Task 0.5 is therefore NOT done and is un-ticked.

---

## Session 2 — PR4b implementation (2026-09-03, branch `…-pr4b-apex-cname-flip`)

### Plan Phase
- Plan file: `knowledge-base/project/plans/archive/20260903-221104-2026-08-20-chore-migrate-docs-site-to-cloudflare-pages-plan.md`
- Status: **recovered from on-disk plan** (not re-planned)
- Plan artifact: complete (selector=branch, after frontmatter retarget)
- Branch: `feat-one-shot-7640-pr4b-apex-cname-flip` (PR4b) — draft PR #7793

#### Why recovery, not a fresh plan+deepen

The plan is 2689 lines and already fully deepened: `## Research Insights`,
`## Research Reconciliation`, Design Decisions D1-D5, `## Guard Contract`,
`## Acceptance Criteria`, `## Test Scenarios`, `## Observability`,
`## Files to Edit` / `## Files to Create`. It carries the
`## Acceptance Criteria` heading that `one-shot`'s plan-artifact-recovery block
uses as its completeness predicate, and **four PRs have already shipped from
it** (PR1 #7649, PR2 #7751, PR3 #7771, PR4a #7780). All twenty ACs that
`tasks.md` Phase 2-4 cite resolve in it (AC23, AC33, AC34, AC43, AC49-AC53,
AC55-AC63, AC65, AC71).

`tasks.md` states in its own header that the two-merge decision must not be
re-derived — "its rejected alternatives are in the Cut List with the measurement
that killed each" — so a fresh planning pass would have re-litigated a settled
D5 at full restatement cost, which `one-shot`'s token-discipline section names
as the largest single cost driver.

#### Errors
None.

#### Decisions

- **Recovered the on-disk plan** under the anti-bypass carve-out ("unless Step 1
  recovered an on-disk plan and Step 3 (`/work`) is next"). Skipped
  `plan`/`deepen-plan`; did NOT skip any implementation, review, QA or ship step.
- **Retargeted the plan's `branch:` frontmatter** to
  `feat-one-shot-7640-pr4b-apex-cname-flip` and pushed the PR4a branch into
  `prior_branches:`, so the plan's own branch-keyed selector resolves here. The
  PR4a branch was reaped by `cleanup-merged` at session start (PR4a had merged).
- **Added AC72 — the one genuine planning delta.** `tasks.md`'s standing
  constraints require PF9b to be *mechanized*, citing it only as "(AC-new)".
  Confirmed it was absent: `previous_address` appeared nowhere in the plan, and
  PF9b existed only as a manual pre-flight table row (plan line 1451) plus test
  scenario T23. AC72 now specifies the
  `destroy-guard-filter-web-platform.jq` clause asserting the `pages_apex`
  change's `previous_address` equals
  `cloudflare_record.github_pages["185.199.108.153"]` — the only state-rather-
  than-text check in the system. `tasks.md` now cites AC72, not "AC-new".
- **Ticked Phase 0 and Phase 1** (14 boxes) as landed with PR4a `428e1ec78`;
  verified `428e1ec78` is an ancestor of this branch. 22 boxes remain.
- **Kept the spec dir at its PR4a name.** It is the canonical PR4+PR5 task list,
  PR5 still runs from it, and only the plan and the file itself referenced the
  path — so `session-state.md` sits beside the `tasks.md` it describes rather
  than splitting artifacts across sibling dirs.

#### Collision gate (Step 0a.5) — cleared mechanically

`#7640` is OPEN, `closedByPullRequestsReferences` empty, no linked PRs. The
body-text probe surfaced four MERGED PRs (#7780, #7771, #7751, #7649) — all
ordered predecessors of this same migration, referencing #7640 via prose
`Ref #7640`. Rather than escalate, settled it on state: `main`'s `dns.tf` still
declares `cloudflare_record.github_pages` (one A at `185.199.108.153`) and
`www` CNAME'd at `jikig-ai.github.io`, with **no** `pages_apex` and **no**
`moved` block. PR4b's scope has not landed. `tasks.md` independently records
`#7640 (OPEN — closed by PR4b, not earlier)`.

Step 0a note: `ADR-194` trips the Linear `[A-Z]{2,}-[0-9]+` shape but resolves
in-repo to
`knowledge-base/engineering/architecture/decisions/ADR-194-migrate-marketing-docs-site-off-github-pages-to-cloudflare-pages.md`.
Soleur's Linear prefix is `SOL`; `linear-fetch`'s own SKILL.md documents this
false-positive class. No fetch spent.

#### Inherited claims to RE-VERIFY in `/work` (do not trust on resume)

Per token-discipline rule 4's resume inversion — an inherited verification claim
describes a tree that may no longer exist:

- **PF-Z2 / PF-R8b must be re-run within the hour before merging** (task 2.10),
  not read off PR4a's records.
- **PF9b must be re-measured** against this branch's real `terraform plan`.
- The apex-is-one-address premise was re-confirmed from `main`'s `dns.tf` above,
  but AC72 exists precisely because repo text is not state — the mechanized
  `previous_address` clause is what closes that gap.

#### The window is open and bounded

PR4a merged 2026-09-03. Until PR4b merges, the apex holds ONE origin address, so
Cloudflare has no origin-pull retry target on an HSTS-preloaded name, backed only
by a 180 s email-only monitor. If PR4b does not merge this session, revert PR4a
(3 creates / 0 destroys, applies unattended). `git revert` is forbidden for
**PR4b** specifically — its rollback is the generated reverse-`moved` PR.

#### Components Invoked
- `worktree-manager.sh create` / `draft-pr` (draft PR #7793)
- Plan recovery + amendment (AC72), `tasks.md` reconciliation
- `gh issue view` / `gh pr list` collision probes, `git merge-base --is-ancestor`
- Next: `soleur:work`

---

## Session 2 — Work phase complete (2026-09-03)

Phase 2 tasks 2.1-2.10 are implemented and committed on
`feat-one-shot-7640-pr4b-apex-cname-flip` (draft PR #7793, 6 commits pushed).
2.11 is the merge itself.

### Measured, so a resume does not re-derive them

- **PF9b (real state, real filter):** `resource_deletes: 1, nested_deletes: 0,
  reboot_updates: 0, host_creates: 0, apex_move_orphans: 0`. One address,
  `cloudflare_record.pages_apex`, actions `["delete","create"]`, carrying
  `previous_address = cloudflare_record.github_pages["185.199.108.153"]`, plus
  the in-place `www` update. Only those two resources change.
- **PF-R8b (Cloudflare API, not a resolver):** apex = 1 A, 0 CNAME, 2 MX, 4 TXT;
  www = exactly one proxied CNAME. This also proves **PR4a converged**.
- **PF-Z2:** `SERVING-FROM-GITHUB-PAGES`, and CUT2 FAILs pre-cutover on
  `x-proxy-cache: MISS`, which is the positive control for CUT2's discriminator.
  **Corrected 2026-09-03 (review):** this line originally offered that marker as
  the control for the PROBE's verdict. It was not — the probe knew only three of
  the six markers and `x-proxy-cache` was one of the three it did not know, which
  is precisely the divergence the review found. Both now source
  `apex-origin-markers.sh`.
- **AC48:** `seo-config-rules.tf` still carries exactly one `ssl = "full"` and is
  untouched by this branch.

**These are perishable.** Task 2.10 requires PF-Z2 / PF-R8b re-run within the
hour before merging; do not inherit the readings above if the merge slips.

### Filed this session

- **#7797** — I printed two live bearer tokens (Sentry, BetterStack) into the
  agent transcript by running `cutover-verify.sh` under `bash -x`. **Both must be
  rotated.** The Sentry token cannot rotate itself (`/api/0/api-tokens/` → 403),
  so it is a dashboard action.
- **#7798** — `sentry_uptime_monitor.soleur_www` records its own asserted 301 as
  a failure; the www redirect has no working alarm. Remediation is a dispatch of
  `apply-sentry-infra.yml`, then re-capture the CUT8 baseline.
- **#7799** — the ADR-194 deferred-cleanup tracker (AC52), now cited by number in
  the plan's `tracking_issue:` field.

### Deviations from the plan, each recorded where it was made

- **AC70 clarified** — byte-identity to PR4a's `dns.tf` MODULO the reverse
  `moved` block, because PR4a's file has no such block and the rollback cannot
  work without one. Mechanized via `--emit-tf-stripped` + an additions-only row.
- **AC72 added** — the plan cited it only as "(AC-new)"; `previous_address`
  appeared nowhere in the plan.
- **CUT8 judges REGRESSION** against `cutover-monitor-baseline.txt` rather than
  absolute green, because #7798 makes absolute unsatisfiable and the T+20 rule
  would then roll back a healthy cutover.
- **CUT7 derives its pairs** from `seo-bulk-redirects.tf`; the identity mapping
  assumed by the plan's prose is wrong (`terms-of-service` consolidates into
  `terms-and-conditions` — ten sources, nine targets).

### Next

`/review` → resolve findings → `/qa` → `/compound` → `/ship`. Then Phase 3
(PF8' immediately, `cutover-verify.sh` at T+5, decision at T+20) and only then
Phase 4 (PR5).
