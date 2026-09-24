---
name: kb-search
description: "This skill should be used when searching the knowledge base for files matching keywords or YAML frontmatter facets (tag, category) across domains."
---

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# KB Search

Search the knowledge base across all domains. Returns learnings-scoped title matches first (tier 1, cap 8), then learnings-content matches (tier 2, cap 12). Optional `--tag` and `--category` flags filter `knowledge-base/project/learnings/` by YAML frontmatter before grep runs, cutting result-set noise during cross-referencing.

## Arguments

<search_query> #$ARGUMENTS </search_query>

Accepted forms:

- `soleur:kb-search <keyword>` — existing behavior, unchanged.
- `soleur:kb-search --tag <value>` — filter learnings by frontmatter `tags:`.
- `soleur:kb-search --category <value>` — filter learnings by frontmatter `category:`.
- `soleur:kb-search --tag <value> --category <value> <keyword>` — combine (AND).
- `soleur:kb-search --no-paraphrase <keyword>` — sensitive-query manual override; skips Phase 2.5 entirely. Use when the query carries a secret, customer name, or in-flight incident reference (anything you would not want forwarded to a paraphrase generator).
- `soleur:kb-search --clear-cache` — remove `.soleur/cache/kb-search/query-paraphrases.ndjson`. The cache regenerates lazily on the next non-`--no-paraphrase` invocation.

If `$ARGUMENTS` is empty, ask: "What would you like to search for in the knowledge base?"

### Flag Semantics

- Values are matched **case-insensitively** and **as literals** (fixed-string, not regex). `--tag n+1` matches the literal tag `n+1`.
- Duplicate flags (`--tag a --tag b`) error with usage hint.
- Unknown flags (`--taag`) error with usage hint listing supported flags.
- Faceted queries scope to `knowledge-base/project/learnings/` only; other KB subtrees are skipped for facet lookups.
- Tag-only or category-only queries emit `title + path` per file (no content snippet). Combined with a keyword, snippets come from the keyword match.

## Privacy & Cost

- Runtime paraphrase is inline; no countable spend. If Option B is ever adopted, caps land with it.
- Operator queries MAY be sent to the Anthropic API (Haiku) by [scripts/learning-retrieval-bench.sh](../../../../scripts/learning-retrieval-bench.sh) only when the operator runs the bench-rerun gate (explicit opt-in via the existing `--confirm` flag). No runtime invocation forwards queries outside the executing agent's existing context.
- Use `--no-paraphrase` for queries containing secrets, customer PII, or in-flight incident details. The skill auto-refuses paraphrase when the query matches the sensitive-shape regex (value-shape blobs + vendor key prefixes for Anthropic, OpenAI, GitHub, AWS, Stripe, Slack, JWT — see Phase 2.5 for the full byte-exact regex); `--no-paraphrase` is the manual override for queries that are sensitive but don't trip the regex (e.g., a customer name as a bare topic keyword).
- Cache location: `.soleur/cache/kb-search/query-paraphrases.ndjson` (gitignored per `.soleur/` convention; refuses to write outside `.soleur/cache/`). File mode 0600, directory mode 0700 (re-applied on every append so a pre-existing looser-mode directory is hardened). The cache row stores `{sha256, query, variants, cached_at}` — `query` is stored in plaintext to enable manual inspection / debugging; rely on the directory + file modes (and `--clear-cache`) for confidentiality. TTL: 14 days.

## Execution

### Phase 0: Parse Arguments

Parse `$ARGUMENTS` into `$TAG`, `$CATEGORY`, and `$KEYWORD`. Track whether each flag was already seen to detect duplicates. On duplicate or unknown flag, emit:

```text
Usage: soleur:kb-search [--tag VALUE] [--category VALUE] [KEYWORD]
```

Then exit without searching.

### Phase 1: Facet Validation (only if `--tag` or `--category` supplied)

**Regenerate first — the facet files are untracked caches (ADR-235), so they are routinely absent in a fresh clone and routinely stale on a branch that just added a learning.** This call is the fix for the #8177 class, where a search reported "no prior art" for a file written minutes earlier. It is silent and costs ~60 ms when the index is already fresh; it only regenerates (~3 s) when something eligible changed.

```bash
[ -f scripts/ensure-kb-index.sh ] && bash scripts/ensure-kb-index.sh --soft || true
```

Then validate. **A missing artifact is NOT an error here** — `--soft` cannot regenerate in a repo that has no generator, which is every self-hosted install, and exiting 1 there would make `--tag` unusable with a Soleur-only remediation the user cannot run. Fall back to reading the frontmatter directly:

The two arms below are ONE `if/else`, not two blocks (#8384 review). An earlier draft ended the
fallback with the comment "skip the artifact check" and then ran the artifact check
unconditionally anyway — so on a fresh checkout the fallback passed, the artifact grep failed
on the absent file, and the user was told `Valid values: knowledge-base/kb-tags.txt`, naming a
file that did not exist. That is the exact Soleur-only remediation ADR-235 says this change
removes. The earlier draft also grepped `^tags:` only, so a `--category`-only query (where
`$TAG` is empty) degenerated to "any line starting with `tags:`" and ALWAYS hit.

```bash
tag_lc=$(printf '%s' "${TAG:-}" | tr '[:upper:]' '[:lower:]')
cat_lc=$(printf '%s' "${CATEGORY:-}" | tr '[:upper:]' '[:lower:]')
if [ ! -f knowledge-base/kb-tags.txt ] || [ ! -f knowledge-base/kb-categories.txt ]; then
  # No facet cache and no way to build one: validate each supplied value against the corpus
  # itself. Whole-word, case-insensitive, over its OWN frontmatter line only -- one branch per
  # flag, each guarded on the flag being set, so an empty value can never degenerate the regex.
  if [ -n "$TAG" ] \
     && ! git grep -ilE "^tags:.*\\b${TAG}\\b" -- 'knowledge-base/**/*.md' >/dev/null 2>&1; then
    echo "No matches for --tag ${TAG}."
    exit 0
  fi
  if [ -n "$CATEGORY" ] \
     && ! git grep -ilE "^category:[[:space:]]*${CATEGORY}[[:space:]]*$" -- 'knowledge-base/**/*.md' >/dev/null 2>&1; then
    echo "No matches for --category ${CATEGORY}."
    exit 0
  fi
  # Every supplied value is real. Continue to Phase 2 -- the artifact checks in the else-arm
  # are NOT reached.
else
  # Facet caches present: validate each supplied value against its artifact (case-insensitive,
  # fixed-string, whole-line). On miss, emit and exit.
  if [ -n "$TAG" ] && ! grep -Fxq "$tag_lc" knowledge-base/kb-tags.txt; then
    echo "No matches. Valid values: knowledge-base/kb-tags.txt"
    exit 0
  fi
  if [ -n "$CATEGORY" ] && ! grep -Fxq "$cat_lc" knowledge-base/kb-categories.txt; then
    echo "No matches. Valid values: knowledge-base/kb-categories.txt"
    exit 0
  fi
fi
```

### Phase 2: Filter Learnings by Frontmatter (only if `--tag` or `--category` supplied)

Walk `knowledge-base/project/learnings/*.md`. For each file, parse YAML frontmatter with the same awk idiom the index generator uses:

```awk
/^---$/ { c++; next }
c != 1 { next }
# then match on ^tags: or ^category:
```

Accept both inline (`tags: [a, b]`) and block (`tags:\n  - a`) forms. Compare values case-insensitively. Collect the surviving file paths.

If both flags are supplied, a file must match BOTH to survive (AND).

### Phase 2.5: Paraphrase Pre-Pass (Stage 2, #4176)

<!-- stage-2-paraphrase-union-v1 -->

Stage 2 (#4176) adaptive pre-pass — runs after Phase 3 has produced a baseline two-tier grep result for `$KEYWORD`, and only when that result is sparse. The agent paraphrases inline within its own context (Option C runtime); no runtime API call is generated by this skill.

**Trigger condition (ALL must hold):**

1. `$KEYWORD` is non-empty (facet-only queries skip).
2. Phase 3's two-tier grep returned **< 5 unique paths** (combined tier-1 + tier-2 dedupe-by-path count).
3. `--no-paraphrase` was NOT passed.
4. `$KEYWORD` does NOT match the sensitive-shape regex below (case-insensitive). The regex blends value-shape anchoring (assignment-blobs, postgres dsn=) and vendor-prefix anchoring (Anthropic, OpenAI, GitHub, AWS, Stripe, Slack, JWT triple-blob) — prefix anchors avoid blocking topic-keyword queries like `"JWT token refresh"` or `"keypress event"` while still catching credential paste-throughs. Source of truth is `SENSITIVE_QUERY_REGEX` in [scripts/learning-retrieval-bench.sh](../../../../scripts/learning-retrieval-bench.sh); [plugins/soleur/test/kb-search-lockstep.test.sh](../../../test/kb-search-lockstep.test.sh) asserts byte-equality across both files.

   ```text
   ((=|:)[[:space:]]*[a-zA-Z0-9+/]{16,}|sk-(ant-)?[a-zA-Z0-9_-]{20,}|sk_live_[a-zA-Z0-9]{20,}|pk_live_[a-zA-Z0-9]{20,}|rk_live_[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{36}|gho_[a-zA-Z0-9]{36}|ghs_[a-zA-Z0-9]{36}|github_pat_[a-zA-Z0-9_]{40,}|AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|xox[abprs]-[a-zA-Z0-9-]{10,}|eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_.+/=-]{15,}|dsn=)
   ```

If any condition fails, skip Phase 2.5 and return Phase 3's result unchanged.

**Sensitive-query guard (manual override = `--no-paraphrase`):** when condition 4 fails, emit and exit:

```text
kb-search: refusing to paraphrase query containing sensitive value-shape token. Pass --no-paraphrase to explicitly bypass.
```

**Cache lookup:**

```bash
variants=$(bash "${CLAUDE_PLUGIN_ROOT}/skills/kb-search/scripts/kb-search-cache.sh" lookup "$KEYWORD")
```

On hit (newline-separated variants, < 14 days old) skip variant generation and go straight to union execution. On miss (empty output) proceed.

**Variant generation (Option C agent-inline):**

> Generate exactly 3 paraphrase variants of `$KEYWORD`. Each variant should use different vocabulary while preserving semantic intent (swap verbs for nouns where natural, substitute domain-canonical synonyms). Output one variant per line, no preamble.

**Cache write:**

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/kb-search/scripts/kb-search-cache.sh" append "$KEYWORD" "$v1" "$v2" "$v3"
```

**Union execution:** for each of the 4 strings (original `$KEYWORD` + 3 variants), run Phase 3's two-tier grep under its own per-tier 8+12 caps. The 4 per-variant ranked lists are then merged into a single flat hit-count rerank capped at 20 — per-tier identity does not survive the union (by design — union-by-hit-count is the new ranking signal), and 20 is the absolute ceiling on what kb-search returns.

**Fallback policy:** paraphrase failure (rate limit, network, model refusal, all variants empty) → emit to stderr and fall back to Phase 3's baseline result:

```text
kb-search: WARN — paraphrase generation failed: <cause> — falling back to baseline grep
```

Per-session cap breach (executing agent has generated more paraphrase calls than is sane in one session) → emit `kb-search: WARN — paraphrase cap reached — falling back to baseline grep` and use the baseline result.

### Phase 3: Keyword Search

- **Facet-only (no keyword):** Emit one line per surviving file in `- [Title](path)` form (title read from frontmatter or first `# heading`).
- **Keyword-only (no facets):** Run the two-tier search with per-tier caps so tier-1 noise titles cannot starve tier-2 content matches (see #4119):
  1. **Tier 1 (cap 8):** Run `[ -f scripts/ensure-kb-index.sh ] && bash scripts/ensure-kb-index.sh --soft || true` first (untracked cache — see Phase 1; the call is idempotent, so a second one after Phase 1 costs only the ~60 ms probe), then grep `knowledge-base/INDEX.md` for the keyword, then restrict to lines whose link target is rooted under `knowledge-base/project/learnings/`. Anchor the filter so future paths like `sessions/learnings-retrospective/` cannot leak.
  2. **Tier 2 (cap 12):** Grep `knowledge-base/project/learnings/**/*.md` content for the keyword. Exclude `archive/`.
- Output tier-1 first, then tier-2, deduped by path. Maximum 20 total; each tier self-caps.
- **Facets + keyword:** Apply keyword grep **only** to the facet-filtered file list (not the whole KB). Use `grep -F` (fixed-string).

Missing `INDEX.md` after the ensure call → the repo has no generator (a self-hosted install). Note it and continue with the Tier-2 content grep only; never exit non-zero on this, and never print a remediation naming a script the user does not have.

### Phase 4: Display Results

Title matches come first, then content matches. Cap total at 20; if truncated, append:

```text
Showing top 20 of N matches. Narrow the query for more specific results.
```

Zero results → suggest:

- Check spelling
- Try broader or alternative keywords
- For `--tag`/`--category` misses, inspect `knowledge-base/kb-tags.txt` or `kb-categories.txt`
- Run `bash scripts/ensure-kb-index.sh` to refresh the untracked caches (Soleur repo only; it is a no-op when they are already fresh)

## Examples

### Tag filter with keyword

```text
soleur:kb-search --tag eager-loading rails
```

Returns learnings tagged `eager-loading` whose content matches `rails`.

### Category filter alone

```text
soleur:kb-search --category performance-issues
```

Returns all learnings with `category: performance-issues` as title+path.

### Combined facets

```text
soleur:kb-search --tag n+1 --category performance-issues
```

Returns learnings tagged `n+1` AND categorized as `performance-issues`.

### Miss with hint

```text
soleur:kb-search --tag nonexistent-tag
# Output:
# No matches. Valid values: knowledge-base/kb-tags.txt
```

The agent can read the artifact in a follow-up round-trip to self-correct.

## Output Format

```text
## Title Matches

1. [Title](knowledge-base/path) — title match
2. [Title](knowledge-base/path) — title match

## Content Matches

3. [Title](knowledge-base/path) — content match (line N: "...snippet...")
```

Tag-only or category-only output uses the `## Title Matches` block only, without snippets.
