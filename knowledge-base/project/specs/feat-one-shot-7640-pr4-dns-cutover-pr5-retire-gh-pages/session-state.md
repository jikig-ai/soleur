# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-08-20-chore-migrate-docs-site-to-cloudflare-pages-plan.md
- Status: complete (with one coordinator-applied repair, below)

### Errors
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

### Perishable measurements — RE-PROBED FRESH 2026-09-03 by the coordinator, not inherited
- Hypothesis Z still FALSE: `apex-origin-probe.sh` -> `SERVING-FROM-GITHUB-PAGES`, rc 0.
- R8 clean: apex = exactly 4 proxied A at 185.199.108-111.153, plus 2 MX + 4 TXT (all unproxied,
  outside the blast radius); www = exactly 1 proxied CNAME at `jikig-ai.github.io`.
- PF-TARGET already satisfied: both `-target=cloudflare_record.github_pages` (line 601) and
  `-target=cloudflare_record.pages_apex` (line 607) are in the apply allow-list; `pages_apex`
  was pre-added by PR3 precisely to close this gap.

### Decisions
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

### Components Invoked
- soleur:plan, soleur:deepen-plan
- architecture-strategist (spawned then resumed to measure against the live provider),
  spec-flow-analyzer, kieran-rails-reviewer, a scoped advisor consult
- scripts/lint-guard-contract.py (EXIT 0), scripts/lint-infra-no-human-steps.py
  (EXIT 0 in CI's `--changed` form; the repo-wide 532 is a pre-existing backlog CI does not gate)
