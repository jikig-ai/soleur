<!-- Inspired by alirezarezvani/claude-skills methodology (MIT, Copyright (c) 2025 Alireza Rezvani) -->

# Peer Plugin Audit — Sub-Mode Procedure

Sub-mode of `soleur:competitive-analysis`. Given a GitHub repository URL, produce a 4-section markdown audit (inventory / high-value gaps / overlap / architectural patterns + recommendations) and seed it into the "Skill Library Tier" section of `knowledge-base/product/competitive-intelligence.md`.

**Invocation:** `skill: soleur:competitive-analysis peer-plugin-audit <repo-url>` (routed from `SKILL.md` Step 1).

**Session-caching note.** `WebFetch` results are cached for the current session. If you are re-running an audit against the same repo in the same session, expect stale content; start a new session for fresh data.

## Step 1 — Input validation

1. Parse the repo URL. Must match `https://github.com/<owner>/<name>` (strip trailing `.git` or `/`). If the host is not `github.com`, abort with a clear error.
2. Run `gh repo view <owner>/<name> --json url,licenseInfo,description,isFork,parent 2>&1 | head -n 50`. This follows 301 redirects and normalizes the URL.
3. If the command exits non-zero:
   - HTTP 404 → abort: `repo not found or not public`.
   - HTTP 401 → abort: `authentication required — run gh auth status`.
   - Other errors → abort with the gh message.
4. Classify license from `licenseInfo.spdxId`:
   - `MIT`, `Apache-2.0`, `BSD-*`, `ISC`, `MPL-2.0` → permissive. Ports may adapt SKILL.md prose.
   - `GPL-*`, `AGPL-*`, `LGPL-*` → copyleft. Ports must be clean re-implementations (methodology only, no text copy).
   - `null` / missing → default all recommendations to "inspire only". Note "LICENSE not detected — ports limited to methodology" in the report Inventory Summary.
5. If `isFork` is true, record the `parent` repo name in Inventory Summary; proceed (thin forks may still be worth auditing, but the attribution belongs to the parent).

## Step 2 — Inventory enumeration

Enumerate every SKILL.md path in the repo via the Git tree API:

```bash
gh api "repos/<owner>/<name>/git/trees/HEAD?recursive=1" \
  --jq '.tree[].path | select(endswith("SKILL.md"))' 2>&1 | head -n 500
```

Also enumerate `agents/**/*.md` and any `commands/` or `personas/` folders with the same approach (one `gh api` call per folder pattern, each piped through `| head -n 500`).

Record counts per category (top-level directory). Record total SKILL.md count.

## Step 3 — Depth-assessment sampling

**If total SKILL.md count ≤ 50:** fetch all of them. Otherwise, use stratified sampling to keep the audit deterministic and bounded.

**Stratified sampling procedure (when count > 50):**

1. Bucket the SKILL.md paths by their top-level directory:

   ```bash
   gh api "repos/<owner>/<name>/git/trees/HEAD?recursive=1" \
     --jq '.tree[].path | select(endswith("SKILL.md"))' \
     | awk -F/ '{print $1}' | sort -u | head -n 500
   ```

2. For each bucket, pick the **alphabetically first 2-3 SKILL.md paths** (deterministic, reproducible, no randomness).
3. Fetch each picked file via `WebFetch` on `https://raw.githubusercontent.com/<owner>/<name>/<default-branch>/<path>`. If `WebFetch` rate-limits, fall back to `gh api repos/<owner>/<name>/contents/<path> --jq '.content' | base64 -d | head -n 500`.

Record a **depth assessment** for each fetched file:

- **Thin wrapper** — SKILL.md under ~50 lines, no substantive procedure.
- **Substantive** — 100-250 lines, multi-step workflow, clear instructions.
- **Heavy tooling** — 300+ lines, references `scripts/` or deep frameworks.

Summarize distribution as a percentage across fetched samples. If sampled, note "sampled N of M" in the report.

## Step 4 — Soleur catalog enumeration (at-invocation)

Enumerate Soleur's current catalog so the mapping target is always fresh:

```bash
ls plugins/soleur/skills/ | head -n 500
find plugins/soleur/agents -name "*.md" -type f | head -n 500
ls plugins/soleur/commands/ | head -n 500
```

Use the raw output as the mapping target. Do not assume prior catalog counts — they drift.

## Step 5 — Semantic mapping via Task delegation

Spawn the `competitive-intelligence` agent with the extended prompt template below. The skill (not the agent) invokes Task directly — one hop.

### Task prompt template

```text
You are running a peer-plugin audit for the Soleur plugin. Produce a markdown
report using the 4-section template in
plugins/soleur/skills/competitive-analysis/references/peer-plugin-audit.md.

# Repo under audit
- URL: <normalized URL>
- License: <SPDX id or "not detected">
- isFork: <true/false> (parent: <name or n/a>)
- Description: <from gh repo view>
- Stars / forks: <optional; fetch via gh repo view --json stargazerCount,forkCount>

# Their inventory
- Total SKILL.md files: <N>
- Buckets: <top-level dir → count>
- Sampled SKILL.md files for depth: <list of paths>
- Depth distribution across samples: <thin% / substantive% / heavy%>

# Soleur catalog (authoritative mapping target)
Skills (<N>): <ls output>
Agents (<M>): <find output>
Commands (<K>): <ls output>

# Discipline
- SEMANTIC MATCHING, not name matching. Examples:
  - Their senior-architect → Soleur architecture-strategist + ddd-architect + cto
  - Their financial-analyst → Soleur revenue-analyst + financial-reporter
  - Their content-creator → Soleur copywriter + content-writer
  Report these as overlap, not as gaps.
- CPO gate: every port recommendation MUST name the specific founder outcome
  it unblocks. If unspecified, the recommendation auto-converts to
  "inspire only" (do not copy; use pattern only).
- CMO framing: in the Recommendations section, group ports by ICP-expansion
  narrative (e.g., "regulatory compliance" or "observability"), not as
  individual skill-add announcements.
- Attribution: if license allows porting, the Soleur-side target file must
  include an attribution comment referencing the specific source path.

# Output format
Use the inline report template in peer-plugin-audit.md. Produce ≤ 500 lines
of report body. Wrap every #NNNN GitHub reference in backticks so CommonMark
does not parse it as a heading.

# Output destination
Write the report under a new entry in the "Skill Library Tier: Portable Skill
Collections" section of knowledge-base/product/competitive-intelligence.md,
or update the existing entry if one already exists for this repo. Do not
create parallel files in research/.
```

### Output-size guard

The agent must produce ≤ 500 lines of report body. The prompt enforces this; verify at read-back.

## Report template (inline)

Use this structure verbatim. All `#NNNN` PR/issue references MUST be wrapped in backticks per `cq-prose-issue-ref-line-start`.

```markdown
### <Competitor name>

**Repo:** [<owner>/<name>](https://github.com/<owner>/<name>)
**License:** <SPDX id or "not detected">
**Commit SHA at audit:** <from gh repo view, or "HEAD@<date>">
**Audit date:** <YYYY-MM-DD>
**Auditor:** soleur:competitive-analysis peer-plugin-audit
**Soleur catalog snapshot:** <skills count> skills / <agents count> agents / <commands count> commands
**Fork note (if applicable):** fork of `<parent>`

#### 1. Inventory Summary

- Total SKILL.md: <N> (sampled <K> of <N> if stratified)
- Category buckets: <bucket: count, ...>
- Depth distribution (across samples): <thin%% / substantive%% / heavy%%>
- Notable tooling: <scripts/ language, references/ conventions>
- License / ports note: <permissive | copyleft | not detected → inspire-only>

#### 2. High-Value Gaps

| Their skill | Path | Purpose | Why-not-duplicated-in-Soleur | Effort-to-adapt | Founder outcome unblocked (CPO gate) |
|---|---|---|---|---|---|
| <name> | <path> | <1 line> | <1 line semantic-overlap-absent justification> | low/medium/high | <one sentence OR "inspire only — no concrete outcome named"> |

#### 3. Overlap Table

| Their skill | Closest Soleur equivalent(s) | Which looks deeper | Notes |
|---|---|---|---|
| <name> | <soleur skill/agent list> | their | ours | <1 line> |

#### 4. Architectural Patterns + Recommendations

##### Patterns worth examining

| Pattern | Mechanism (1 line) | Soleur fit | Recommendation |
|---|---|---|---|
| <name> | <how it works> | <which existing Soleur skill/agent is closest> | extract | port | inspire only | reject |

##### Recommendations (ICP-expansion framing per CMO)

- **<ICP-expansion narrative, e.g., "Regulatory compliance">** — bundles gaps #<row-ref> + #<row-ref>. Founder outcome: <one sentence>. Suggested landing PR: "<draft title>".
- **<Next narrative>** — …

If fewer than 2 recommendations exist, output a single "Recommendations" paragraph and skip the bundle framing.

##### Attribution

When porting concrete SKILL.md text, the Soleur target file MUST include:

`<!-- Inspired by <owner>/<name>/<path> (<license>, Copyright (c) <year> <author>). -->`

#### Convergence risk

- **Low / Medium / High** — <1-2 sentence justification>
- **Watch items** — <bulleted list of signals that would raise the risk>
```

## Output routing

- Write the report **as a new entry** in the `## Skill Library Tier: Portable Skill Collections` section of `knowledge-base/product/competitive-intelligence.md` (append before any trailing `### Tier Analysis` subsection, so the tier analysis always summarizes the full entry set).
- If an entry for the same repo already exists, **update it in place** — do not duplicate.
- Update the file's frontmatter: `last_updated: <today>`, `last_reviewed: <today>`. If `tiers_scanned` is a frontmatter list, append `"skill-library"` if not present.
- Do NOT write a parallel file under `knowledge-base/product/research/peer-plugin-audits/`. Single destination prevents stale copies.

## Non-audit outcome

If Step 2 returns **zero SKILL.md files**, the repo is not a skill library. Write a short advisory entry (or log-only note) to the tier explaining "category mismatch; no audit produced", and do not add an Overlap Matrix row. This prevents the tier from collecting non-skill-library repos.

## Error branches (reference)

- **WebFetch rate-limit** → fall back to `gh api repos/<o>/<r>/contents/<path>` for individual file fetches.
- **401 / auth required** → abort with message pointing to `gh auth status`.
- **Same-session cached results** → note at report top: "results may reflect session cache".
