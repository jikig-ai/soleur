---
module: System
date: 2026-09-19
problem_type: workflow_issue
component: development_workflow
symptoms:
  - "23 Terraform-generated redirect items could be silently dropped by deleting one flatten arm while every guard stayed green"
  - "A >2000-byte layout-wrapped meta-refresh page escaped the size-gated zero-stub predicate"
  - "A fifth stub template (pages/articles.njk) existed outside the plan's enumerated deletion list, serving a live 200 with no edge coverage"
  - "Deleted template's artifact survived a rebuild — Eleventy does not prune removed inputs from _site"
root_cause: missing_validation
resolution_type: workflow_improvement
severity: medium
status: open
tags: [seo, meta-refresh, cloudflare-bulk-redirects, eleventy, guard-design, structural-enumeration]
---

# Troubleshooting: Pin the generation mechanism, not just the emitted content — meta-refresh stub deletion (#3328 PR-B)

## Problem

Migrating docs-site redirects from build-time meta-refresh pages to Cloudflare edge 301s required deleting the stub machinery. The deepened plan enumerated 4 files to delete and prescribed content-pinning guards — but the guard window had holes the plan did not name, and a fifth stub existed outside the enumeration.

## Environment

- Module: docs site (Eleventy) + `apps/web-platform/infra/seo-bulk-redirects.tf` (Cloudflare Bulk Redirects)
- Affected Component: `scripts/validate-blog-links.sh`, `plugins/soleur/test/seo-aeo-drift-guard.test.ts`, `marketing-content-drift.test.ts`, `validate-seo.test.ts`
- Date: 2026-09-19
- PR: #8358 (PR-B of #3328; PR-A #8331 merged the edge 301s first)

## Symptoms

- `local.blog_redirect_items` flattens 3 URL shapes per blog post through a `dynamic "item"` block — removing one arm or the whole block would kill up to 69 redirects with every existing guard green (guards pinned *values*, not the *mechanism*).
- The zero-stub test used a `<2000` byte predicate; a meta refresh inside a full layout escapes it. Any-size fence required.
- `pages/articles.njk` — a hand-maintained stub predating the machinery — was not in the plan's file list; found only by grepping `_site` for `http-equiv="refresh"` after the "final" residual sweep.
- `_site` kept serving the deleted template's output until `rm -rf _site` — incremental Eleventy builds never prune.
- A per-item `item {}` parser written naively matched a literal `item {` inside a *comment* in the same `.tf` file (line ~47) — phantom block.

## What Didn't Work

**Plan's enumerated file list as the deletion boundary.** Found `articles.njk` only by running the semantic grep (`grep -rl 'http-equiv="refresh"' _site`) over built output, not the source-tree file list.

**Size-gated stub predicate.** `<2000` bytes was inherited from the old test's intent ("tiny stub page"), but a redirect can ride inside a full-layout page — size is not the invariant, the meta tag is.

**File-wide `grep -F source_url`/`target_url` pairing.** Two sibling items sharing a target could mask a missing/wrong target; pairing must be scoped per `item {}` block.

**Incremental rebuild as stub-deletion evidence.** `_site/articles/index.html` persisted after `articles.njk` was deleted.

## Session Errors

**`gh issue create` rejected twice by filing-gate hooks** (missing `--milestone`, then missing user-impact/`meta/machinery` classification).

- **Recovery:** added `--milestone "Post-MVP / Later"` + `--label deferred-scope-out --label meta/machinery` (→ #8364).
- **Prevention:** hooks already enforce — read the reject reason and supply all gate fields on retry; the filing recipe is in review/SKILL.md §5.

**Stale `_site` artifact after template deletion.**

- **Recovery:** `rm -rf _site && bunx @11ty/eleventy` clean rebuild.
- **Prevention:** verify deletions of build inputs on a *clean* output dir; incremental builders don't prune.

**`terraform validate` errored on a fresh worktree** (`.terraform` absent — init errors, not diff errors).

- **Recovery:** `terraform init -backend=false` then `validate`.
- **Prevention:** in a fresh worktree always `init -backend=false` before `validate`; distinguish "module not initialized" noise from real diagnostics.

**`git stash` attempted in a worktree — hook denied.**

- **Recovery:** used `git status`-inspection instead; nothing needed stashing.
- **Prevention:** `hr-never-git-stash-in-worktrees` is already hook-enforced — deny confirms enforcement worked.

**First commit attempt exited with no commit created** — output truncation hid `COMMIT_RC=1` from `plugin-component-test` (obsolete CaaS stub assertion).

- **Recovery:** re-ran capturing full output; repointed the obsolete assertion at the `.tf` source.
- **Prevention:** when a commit "passes hooks" but no commit lands, re-run with output capture before assuming hook failure — a deleted mechanism strands assertions *outside* the enumerated guard list; grep test names for deleted paths before committing deletions.

**`test-all.sh` lock contention** — pre-commit queued behind sibling full-gate runs (~45 min path).

- **Recovery:** verified prerequisites (`HEAD..origin/main` empty, pushed head's CI green) then used the sanctioned `LEFTHOOK_EXCLUDE=bun-test`; killed the orphaned queued process.
- **Prevention:** check lock queue depth before committing in a shared worktree host; the exclude-flag escape requires the two prerequisites.

**Push rejected — remote branch had been rebased** (duplicate bookkeeping commits upstream).

- **Recovery:** `git reset --hard @{u}` then cherry-pick the single feature commit — cleaner than rebasing, which replayed junk duplicates.
- **Prevention:** when the remote moved and local work is one commit, reset+cherry-pick beats rebase; `git range-diff` / merge-base check first.

**`sed '1,/^---$/'` frontmatter-range bug** in a parity-script draft — the range ends at line 1 (the opening `---`), so a `permalink:` on line 2+ would never be seen.

- **Recovery:** rewrote with `awk '/^---$/{c++} c==1 && /permalink:/'`.
- **Prevention:** test frontmatter-range patterns against a file whose target key sits below the closing `---`; `sed '1,/x/'` includes `x` on line 1.

**Edit `old_string` mismatch** — transcribed the wrong tail of a describe block.

- **Recovery:** re-read exact lines, retried.
- **Prevention:** re-read the target hunk immediately before editing when the block was read >50 lines ago.

**Tool noise (one-offs, no action):** todo-write rename false-positives; display-layer message garbling — all outputs verified correct on read-back.

- **Recovery:** re-read the artifact each time; every output was correct.
- **Prevention:** treat tool-layer warnings as noise to verify, not failures to fix — read the file, don't re-edit.

**Forwarded (pre-compaction, session-state.md):** `gh issue create` filing-gate fields (→ #8332); two plan claims self-corrected in deepen (`include_subdomains` enumeration; #3379 status).

- **Recovery:** supplied the gate fields; corrected the claims in the deepen pass.
- **Prevention:** plan claims are preconditions to re-run, not facts — same class as the work skill's stale-number rule.

## Solution

1. **Sequence: additive edge redirects → live-verify → delete stubs.** 19/19 legacy `pageRedirects.js` `from` paths re-verified 301 live before any deletion (PR-A's apply is PR-B's merge precondition).
2. **Bidirectional parity guard** (`validate-blog-links.sh`): date-prefixed blog files ↔ Terraform `blog_redirect_pairs` keys, both directions, anti-vacuity floor ≥1 dated file, `permalink:` override refusal, `blog.json` permalink-template pin — all hoisted *above* unrelated early exits so the guard can't be skipped by a missing content dir.
3. **Mechanism pins, not just value pins:** the 3 generated source-shape arms and the `dynamic "item"` block are asserted as literal strings in both the bash guard and the Bun test — removing the flatten kills the guard.
4. **Any-size/any-delay meta-refresh fence** over all built HTML; `_redirects`/`_headers` absence asserted (unwatched redirect channel).
5. **Per-item `item {}` parsing** with quote-aware comment stripping (`test/lib/bulk-redirect-pairs.ts`) — kills the phantom-block hazard and the shared-target masking.
6. **Order-agnostic edge-301 flag pins** (`status_code`, `include_subdomains`, `preserve_query_string`) via shared `missingEdge301Flags()`.
7. **`articles.njk` folded into the migration** rather than stranded: 3 `/articles/` shapes added to the same bulk list, template deleted — same treatment as every other stub.
8. **Clean rebuild** as the deletion oracle: `rm -rf _site` then `grep -rl 'http-equiv="refresh"' _site` → empty.

## Why This Works

The failure class is *guard-window mismatch*: guards asserted properties of emitted values while the hazard lived in the machinery that produces them. A `for` loop over `blog_redirect_pairs` + a `dynamic` block is a *generator*; pinning its outputs one-by-one leaves the generator itself unguarded. Pinning the generator's literal shape (each flatten arm, the dynamic block, the permalink template that derives target URLs) makes the guard co-extensive with the hazard. Likewise, "the build no longer emits stubs" is only provable against a clean output tree — incremental state is a cache, not evidence.

## Prevention

- When a guard pins generated content, enumerate the *generation path* (locals → flatten arms → dynamic block → emitted resource) and pin each stage; content pins alone leave generator-deletion invisible.
- When deleting build inputs, verify on `rm -rf <out>` — Eleventy (and most incremental builders) do not prune.
- Never derive a "stub-ness" predicate from size; a redirect tag inside a full layout is still a redirect.
- Parser-over-config hazard: strip comments *before* structural matching, respecting quoted strings — config files routinely contain literal block syntax inside explanatory comments.
- A deletion sweep bounded by a plan's file list misses stragglers; the oracle is a semantic grep over built output (and over the source tree) for the mechanism's signature.

## Related Issues

- See also: `2026-09-18-every-defect-was-in-my-verification-not-the-feature.md` (deletion rounds leaving stale records — sibling class)
- See also: `2026-09-18-every-instrument-i-built-to-check-the-guards-needed-checking.md` (instrument verification)
- Similar to: `2026-09-07-my-instruments-reported-green-while-measuring-nothing.md` (residual-zero counts certifying the wrong corpus)
- Tracker: #8364 (deferred guard-completeness scope-outs), #3328, #8332 (GSC re-verification)
