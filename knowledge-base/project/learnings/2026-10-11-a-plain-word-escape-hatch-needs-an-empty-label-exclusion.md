# Learning: a plain-word escape hatch needs an empty-label exclusion and its negative rows in the FINAL sentence

## Problem
The unkept-promise Stop hook made the model write literal `<stop>OPERATOR-GATE: ...</stop>` tags to end a turn legitimately; users read the raw markup as a defect. Replacing it with a plain sentence-initial `Paused:` / `Blocked:` label removes the markup, but the old tag was rare and deliberate while these are ordinary status words.

## Solution
- Marker is anchored to the start of the FINAL sentence, needs the colon, closed vocabulary (`Paused|Blocked`), and an empty or negative label (`Blocked: none.`, `Paused: n/a`) does not count (`STOP_NOOP_RE`).
- The block reason teaches no angle-bracket text at all, including placeholders: `<what you are waiting on>` was itself markup a model could echo. Asserted on both the promise and parked reasons.
- The legacy `<stop>` tag is not honoured. The web strip stays only as a cleaner for persisted rows; ADR-093's removal trigger now also requires no persisted row to contain the tag, because the Sentry op fires only on the live runner path.

## Key Insight
When an escape hatch moves from a rare token to common prose, the guard's weakness shifts from forgery to accident, so the closed vocabulary, the anchor, the colon and a content check each need a must-BLOCK row. Those rows are vacuous unless the non-label text is the FINAL sentence, because only the final sentence is read: a row whose earlier sentence carries "Blocked PRs" and whose final sentence is the promise blocks whatever the regex says.

## Session Errors
1. **Reason placeholder `<what you are waiting on>` taught angle-bracket text** — caught by the new no-markup assertion. Prevention: assert the reason carries no `<[a-z!/]`, on every reason the hook can emit.
2. **Bold label `**Paused:**` failed** — the sentence prep's bullet strip eats one `*` of `**`. Prevention: tolerate leading `*` in the anchor and keep bold-form rows.
3. **Colon and vocabulary rows were vacuous** (test-design seat) — non-label text sat in an earlier sentence, so the promise blocked regardless. Prevention: put the discriminating text in the final sentence; mutate the regex to confirm the row reds.
4. **A mutation sed did not land** (`-E` parentheses) — Prevention: `cmp` against the backup after each mutation.
5. **Worktree had no node_modules** — `npm ci` in apps/web-platform before vitest.
6. **Shell cwd drifted into apps/web-platform** after `npx vitest` — Prevention: absolute paths or a subshell for app-scoped commands.
7. **Installed plugin hook is still the old version mid-session**, so Stop blocks quoted the legacy tag and I had to use it to pause legitimately — expected until the plugin updates; not a defect.

## Tags
category: logic-errors
module: plugins/soleur/hooks/unkept-promise-hook.sh
