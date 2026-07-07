# Learning: verification gates that look green but are silently wrong (Supabase 201, `${VAR:?}` exit code, `\b`-after-digit regex)

**Date:** 2026-07-07
**Context:** PR #6164 — migration 123 tames autovacuum thrash on three tiny public hot-update tables (residual Supabase Disk IO drain, lineage #3358 → #5736 → this). The migration itself was clean; the *verification substrate* (a shape test + a soak follow-through script) carried three independent "looks-green-but-lies" defects, all caught pre-merge (two by running the script live, three by multi-agent review).

## Problem

Three defects in verification code that pass every naive check yet fail in the exact case they exist to catch:

1. **Supabase Management API returns HTTP 201, not 200.** A follow-through probe querying `https://api.supabase.com/v1/projects/<ref>/database/query` with a strict `if [[ "$HTTP_STATUS" != "200" ]]; then exit TRANSIENT` would return TRANSIENT on *every* successful run → the tracker issue never closes (silent never-close). The rows come back fine; only the status literal is off by one.

2. **`: "${VAR:?msg}"` exits 1, not the fail-safe code you wrote next to it.** In the follow-through sweeper contract, exit 1 = FAIL (comments "still failing", leaves open) and exit 2 = TRANSIENT (retry). The guard `: "${SUPABASE_ACCESS_TOKEN:?...}" 2>/dev/null || { echo TRANSIENT; exit 2; }` looks fail-safe, but under a non-interactive shell the `${VAR:?}` word-expansion aborts the shell *during expansion* with status **1** — the `|| { exit 2; }` is dead code. An unprovisioned GitHub secret resolves to `""` in the sweeper's `env -i` sandbox, tripping this into a misleading FAIL comment.

3. **`\b` after a `0` matches `0.2`.** A migration shape test asserting `autovacuum_vacuum_scale_factor = 0` with `/scale_factor\s*=\s*0\b/i` also matches `= 0.2` — because `\b` sits at the `0`↔`.` word/non-word boundary. `scale_factor = 0` is the whole point of the migration (it turns autovacuum into a deterministic absolute dead-tuple trigger); a future edit reintroducing the thrash-causing default `0.2` would pass the test green.

## Solution

1. Accept the 2xx the API actually returns: `if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "201" ]]; then`. (Verified live: the query endpoint returns 201.)
2. Never use `${VAR:?}` when a specific non-1 exit code is contractually required. Use an explicit check that also treats empty as unset: `if [[ -z "${VAR:-}" ]]; then echo "TRANSIENT: ..." >&2; exit 2; fi`.
3. Anchor numeric-literal regexes against a trailing decimal/digit: `/scale_factor\s*=\s*0(?![.\d])/i`. `\b` is not "end of number" — it is "word/non-word boundary", and `.` is non-word.

## Key Insight

**Verification code is the highest-leverage place for a silent false-green, because nothing downstream verifies the verifier.** Three distinct mechanisms produced the same failure shape here: an off-by-one HTTP status, a shell builtin whose exit code you didn't write, and a regex boundary that means something other than "end of value". The cheap, reliable catch for all three was **execute the gate against real inputs before trusting it** — running the follow-through script live surfaced #1 immediately (201) and confirmed #2's exit code (`SUPABASE_ACCESS_TOKEN="" bash script` → observe the actual exit), and a `node -e` one-liner falsified the regex in #3 (`re.test("= 0.2") === true`). Multi-agent review converged on #2 (3 agents) and #3 (2 agents), but a live-run would have caught them solo. For any new gate/probe/shape-test: run it, and run it against the *failing* input, not just the passing one.

## Session Errors

1. **Shell CWD persisted into an investigated worktree.** A read-only `cd .worktrees/feat-5739-...` during diagnosis persisted across Bash calls (the tool keeps CWD), so one-shot Step 0b's `git branch --show-current` reported `feat-5739-auth-wal-reduction` instead of `main`. **Recovery:** `cd` back to the bare root explicitly before worktree creation. **Prevention:** during read-only investigation, prefer `git -C <path>` or absolute paths over a bare `cd` into a sibling worktree; or `cd` back before any branch-sensitive step.
2. **Heredoc body + hook-gated `gh issue create` in one Bash call.** The missing-`--milestone` PreToolUse denial rejected the *entire* call, so the `cat > /tmp/body.md <<EOF` never ran; the retry failed `no such file`. **Recovery:** write the body with the Write tool, then `gh issue create --body-file` as its own call. **Prevention:** already documented (`2026-06-01-best-effort-cron-monitor...` §heredoc) and milestone-hook-enforced — this was a re-trip, not a new class.
3. **Supabase Management API 201 vs 200** — see Problem #1. **Prevention:** captured here; accept 2xx.
4. **`${VAR:?}` exit-code trap** — see Problem #2. **Prevention:** captured here; explicit empty-check for contractual exit codes.
5. **`\b`-after-digit vacuous regex** — see Problem #3. **Prevention:** captured here; `(?![.\d])`.

## Tags
category: best-practices
module: supabase, follow-through, bash, test-authoring
related: [[2026-05-06-supabase-disk-io-structural-overhead-dominates-at-low-scale]]
