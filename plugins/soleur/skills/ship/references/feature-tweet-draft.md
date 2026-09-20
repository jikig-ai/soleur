# Feature-Tweet Draft (pre-merge bundle)

Loaded on demand by `soleur:ship` Phase 6, at the named step below. Extracted from the
skill body under ADR-229: this is a content-generation step, not a correctness gate, and it
runs only for a PR whose labels and title make it eligible — so carrying it in every ship
invocation costs every operator bytes for a step most PRs skip.

Generate any eligible feature-tweet draft NOW — after the semver/`app:*` labels
are applied (eligibility reads the PR labels + title) — and **commit it to the
feature branch** so it rides this PR into `main`, where `content-publisher.sh`
reads from. This replaces the old post-merge generation, which wrote the draft
into a worktree that `cleanup-merged` reaps before it ever reaches `main` (so
the cron never saw it). The draft is **inert** (`status: draft`, empty
`publish_date`) and never posts until the operator sets `publish_date` +
`status: scheduled` — their post-deploy confirmation gate — so bundling it
pre-merge does NOT weaken the "only tweet what actually deployed" property;
`soleur:postmerge` Phase 3.8 still verifies deploy health and warns before the
operator schedules.

1. **Eligibility (fail-closed):** `bash scripts/lib/tweet-eligibility.sh <PR_NUMBER>`.
   Ineligible (exit non-zero, `excluded: <reason>`) → **skip silently** (most PRs
   land here: fixes, infra, non-product). Do not surface the exclusion.
2. **Eligible →** invoke `skill: soleur:feature-tweet #<PR_NUMBER>` (writes +
   displays the draft for approval per its §Output contract).
3. **Commit + push the draft to the feature branch** so it lands on `main` with
   the squash merge (stage ONLY the draft file — never `git add -A`):

   ```bash
   git add knowledge-base/marketing/distribution-content/<draft-file>.md
   git commit -m "content: feature-tweet draft for #<PR_NUMBER> (inert — operator schedules post-deploy)"
   git push
   ```

   The draft is a NEW commit, so the Phase 6.4 Unpushed-Commits Gate re-checks
   clean before merge. Headless mode: same — generate + commit + push; never
   schedule (the inert draft + operator gate are the publish control).

If `soleur:ship` is hand-rolled and this step is skipped, the draft never reaches
`main`; `soleur:postmerge` Phase 3.8 detects the missing on-`main` draft and
runs the standalone catch-up (which then needs its own follow-up commit to land
on `main`).
