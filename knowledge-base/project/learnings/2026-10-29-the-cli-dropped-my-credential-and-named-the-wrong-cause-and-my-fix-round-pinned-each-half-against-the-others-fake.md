# Learning: a CLI that silently drops a credential names the wrong cause, and each half of a new wire was pinned against the other half's fake

## Problem

#11086: the Concierge showed the raw `Not logged in · Please run /login` line. Reproduced offline against the bundled
Claude CLI (SDK 0.3.284): a subscription-token value that is blank, contains an embedded space or tab, or starts with
`sk-` but is not `sk-ant-oat<NN>-<tail>` is **dropped, not sent**. The CLI then replies with the not-logged-in line. The
server stored the operator's token unvalidated and the lease preferred that row regardless of `authMode`, so one bad
paste was a total outage whose message pointed at nothing (the line says "log in", the cause was a malformed paste).

## Solution

- Write boundary: strict allowlist `^sk-ant-oat\d{2}-[A-Za-z0-9_-]+$` in `/api/keys` (400, value never echoed).
- Lease boundary: a NEGATIVE predicate over only the classes measured to be dropped (`api_key_shaped`,
  `embedded_whitespace`, `blank`); fail closed with `oauth_unusable`, no fallback to the API-key row.
- Friendly copy keyed on kind x scheme, the raw-text matcher kept running before any rewrite so the diagnostic stays
  sighted, and a `credentialScheme` field on the `error` frame so the client can offer "Update token".

## Key Insight

1. **An error line is a symptom label, not a diagnosis.** The CLI's "Not logged in" covered five different causes. Derive
   the validation from a measured table (drive the real binary with synthesized fakes), keep the lease predicate to the
   measured classes only (a wider net locks out a future valid shape), and re-derive the table on every SDK bump.
2. **A new wire between two halves is pinned only when each half is driven by the other's REAL output.** The dispatcher test
   hand-fed `{ authFailure: true }` and the runner test ignored the argument, so hard-wiring the flag to `false` in the
   real runner stayed green. The `auth-failed` close reason, the legacy "finished" nudge skip and a lease-record release
   were all unpinned the same way until seats ran the mutants. Ask per new wire: name the edit that reverts it, and say
   which test reds.
3. **A fix round's own change is the least-audited surface.** My reuse-branch `pendingAuthFrame = null` looked like hygiene
   and would have dropped the recovery frame for a message queued between the friendly reply and the `result`. The nine
   fix-round seats did not see it; the single verification pass did.

## Session Errors

- **A mutation helper restored the wrong file** (it read `$2` after `shift`, so every restore errored and mutants
  accumulated) — Recovery: restored all three files from the backup and verified with `sha256sum -c` — Prevention: bind
  arguments to named variables before any `shift`, and check `cmp file backup` after EACH mutant, not only at the end.
- **`markdownlint-cli2` from a drifted CWD reported "0 issues in 0 files"** (a relative path resolved to nothing) —
  Recovery: re-ran from the repo root and saw `Linting: 2 files` — Prevention: treat a lint summary with 0 files as not
  run; the Bash tool keeps CWD across calls, so use absolute paths or `cd <root> &&` in the same call.
- **A fix added a regression (the reuse-branch reset)** — Recovery: reverted it in a follow-up commit and recorded why in
  the code comment — Prevention: always run the single verification seat on the fix commit before emitting the trailer.
- **Semgrep exit 0 reported as clean without checking the rule count** — Recovery: disclosed it as unverified in the
  summary — Prevention: read the `Ran N rules on M files` line, because an invalid config also exits clean.
- **A turn ended on "QA runs next"** — Recovery: invoked `soleur:qa` immediately after the operator asked — Prevention:
  already hook-enforced (the stop hook); a pending phase is started in the same turn.
- **Forwarded from the pipeline:** the wireframe gate (`wg-ui-feature-requires-pen-wireframe`) was not mechanically
  satisfied because Pencil Desktop is absent; recorded as a challengeable pure-copy exclusion in `decision-challenges.md`.

## Tags

category: integration-issues
module: apps/web-platform/server (byok-lease, agent-auth, soleur-go-runner, cc-dispatcher)
