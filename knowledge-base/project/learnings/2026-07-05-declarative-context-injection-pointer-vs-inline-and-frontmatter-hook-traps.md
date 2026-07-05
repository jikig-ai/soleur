# Learning: pointer-vs-inline delivery, and the frontmatter-hook trap set (context_queries #5989)

## Problem
Building FR6 declarative context-injection (#5989): a `PostToolUse:Skill` hook that resolves a skill's SKILL.md `context_queries` frontmatter to committed `knowledge-base/` artifacts and injects them into agent context. A 6-agent plan-review and a 2-agent implementation review surfaced a cluster of reusable traps.

## Key Insights

### 1. When a design hinges on size-sensitive delivery, measure the REAL consumer artifact
The v1 plan inlined artifact *content* into `additionalContext`. The forcing fact (found by spec-flow at plan-review): the pilot artifact `brand-guide.md` is **36 KB** — ~4.5× the 10,000-char `additionalContext` cap — so the only real consumer would *always* degrade to a pointer. The inline happy-path AC even had an "…or a fixture" escape hatch that passed on a synthetic small fixture while the real consumer never exercised the primary path. **Lesson:** for any size-sensitive delivery choice (inline vs pointer, truncate vs stream, embed vs link), `wc -c` the real consumer artifact at plan/review time; reject an AC whose fixture-escape-hatch lets the primary path go unexercised. The fix (**pointer, not inline** — name the paths, let the agent Read them through its normal trust channel) also deleted ~40% of the mechanism (byte budget, truncation, provenance fence, bounded reads).

### 2. content-trust ≠ path-trust; a pointer routes content through the normal Read trust channel
Injecting file *content* via a hook gives it elevated hook-authority framing — a prompt-injection surface for agent-authored artifacts (e.g. a `taste-profile`). A pointer ("Read X") re-enters the content through the agent's ordinary Read, same trust as any repo file. Either way, the *consumer* that points at agent-authored content must sanitize it — recorded as a standing ADR consequence, not just in the feature issue.

### 3. Reuse the existing frontmatter parser; a stricter hand-rolled subset silently parses inline YAML to empty
A block-only awk parser silently returns **zero** entries for the valid inline form `context_queries: [a, b]` — no error, just a silent no-load the author never sees. Reuse the full repo idiom (`scripts/generate-kb-index.sh` `c==1`, handles inline + block + quote-strip) rather than a subset.

### 4. A fast-path key-grep must be frontmatter-scoped
`grep -q '^context_queries:' SKILL.md` matches the **body** too — e.g. a SKILL.md that *documents* the `context_queries` feature — producing a spurious "declared but 0 resolved" note on every invocation of that skill. Scope the fast-path to the frontmatter block: `awk 'FNR==1{c=0} /^---$/{c++;next} c==1' file | grep -q '^context_queries:'`.

### 5. Fail-open observability notes must not echo the rejected untrusted input
The hook's skip-note initially echoed the raw rejected query — which for a traversal attempt (`knowledge-base/../../../etc/passwd`) leaked the crafted out-of-tree path back into agent context. A fail-open/skip note should name *that* an input was rejected and a generic reason, never the raw untrusted string. (Same spirit as `phase-surface-hint.sh` never echoing the model-controlled skill name.)

### 6. PostToolUse-after-dispatch is the structural reason a fail-open hook can't fail-closed
For "lazy per-skill hook vs eager SessionStart loader" (TR2: a bad query must not fail-closed all ~90 skills): the load-bearing reason lazy wins is not per-skill isolation — it's that **PostToolUse fires *after* the tool has dispatched, so the hook physically cannot block/gate the skill**. Pin that invariant in the ADR; never move such a hook to PreToolUse.

### 7. Two hook surfaces — CLI shell vs web in-process — decide CLI-first vs CLI-intrinsic by probing the web surface
`.claude/` shell hooks reach only the CLI plugin; web-agent Concierge sessions run `settingSources:[]` and register in-process `options.hooks` (ADR-070). Before framing a shell-hook feature as "CLI-first (web parity deferred)", grep `apps/web-platform/server/` for the in-process registration: web *does* emit `PostToolUse(Skill)` and has a JS port (`phase-surface-hook.ts`, note it emits *bare* skill names vs the CLI's `soleur:`-prefixed), so a web port is buildable — CLI-first, not CLI-intrinsic.

## Session Errors
- **Fail-open note echoed rejected traversal path** — Recovery: emit `<out-of-tree query> (rejected)` instead of the raw string (`.claude/hooks/skill-context-queries.sh`). Prevention: insight #5 above; a hook test asserts `/etc/passwd` never appears in output.
- **Ran `plugins/soleur/test/components.test.ts` under `vitest` (exit 127)** — Recovery: `bun test` (plugin tests are bun; `apps/web-platform` is vitest). Prevention: already covered by existing test-runner learnings.
- **`git ls-files <ref> -- <pattern>` invalid syntax** — Recovery: `git ls-tree -r <ref> --name-only`. Prevention: one-off.
- **Scratchpad dir absent → early bash redirects failed** — Recovery: `mktemp`/plain paths. Prevention: one-off (env quirk).

## Tags
category: integration-issues
module: claude-code-hooks / context-injection
issue: 5989
adr: ADR-086
