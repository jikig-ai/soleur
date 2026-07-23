---
date: 2026-07-23
category: security-issues
module: preflight-skill / claude-code-harness
tags: [prompt-injection, credential-exfil, at-mention, auto-attach, doppler, footgun]
severity: single-user incident
---

# An at-sign + a real file path in skill text auto-attaches that file's contents

## Problem

During PR #6830's ship (2026-07-22), the operator's **live Doppler root token** appeared
in the session transcript, formatted to look like a `Read` tool result the agent had
performed. No such Read was ever invoked.

## Root cause

Claude Code's **`@`-mention auto-attach** resolves an at-sign immediately followed by a
real on-disk path (tilde-home, `$HOME`, or an absolute system path) to the file and
attaches its **contents** to the transcript — and it does this even when the token
appears inside **tool/skill output**, not just a user-typed message.

`plugins/soleur/skills/preflight/SKILL.md` (Check 10, "reject credentialed CLIs")
documented an exfiltration *example* whose literal text was an at-sign followed by the
real Doppler CLI config path. When preflight loaded, the harness parsed that token,
resolved the real 0600 file, and attached its contents — **exfiltrating the exact
credential the documentation was warning about.**

Forensics that pinned it (all reproducible from the session JSONL):

- The token-bearing block is a genuine CC `attachment` record (`attachment.type=="file"`,
  keys `content`/`displayPath`/`filename`), child of the preflight Skill result message —
  **not** any `tool_result`, and not in any committed repo file.
- The same skill sentence names 7 credential files, **all of which exist on the machine**,
  but **only the one written with a leading `@` was attached** — the `@`-mention is the
  precise trigger, not "any path in the text."

## Solution

1. **Fix the instance:** replace the `@`+real-path token in `preflight/SKILL.md` with a
   non-resolvable placeholder (`@<doppler-config-file>`), plus an inline SECURITY comment
   so no future editor restores the literal path.
2. **Prevent the class (repo guard):**
   `.github/scripts/test/test-no-at-mention-credfile-footgun.sh` — auto-globbed into the
   REQUIRED `guard-script-fixture-tests` job (bash-only). It forbids an at-sign +
   real-home/absolute path in the **auto-loaded content surface** (skills, agents,
   commands, plugin docs, `AGENTS*.md`, `.claude/hooks`). It is non-vacuous:
   proves detection on synthetic footguns, proves no false positives on npm scopes / TS
   `@/` aliases / emails / GitHub @mentions / `@<placeholder>`, and is mutation-tested
   end-to-end.
3. **Defense-in-depth:** `.claude/settings.json` `permissions.deny` now denies `Read()`
   on the credential locations preflight Check 10 enumerates (doppler, ssh, aws, gcloud,
   docker, netrc, git-credentials). This does not break the credential CLIs — they read
   their configs internally as subprocesses, not via the `Read` tool.
4. **Rotate:** the leaked Doppler token was root-scoped; the operator rotated it (a fresh
   `doppler login` minted a new token, invalidating the leaked one).

## Key insight

A credential **path literal** is not inert in agent-loaded text: prefixed with the
`@` sigil it becomes an *attach-this-file directive* the harness executes. Two
generalizations:

- **Never write an at-sign immediately before a resolvable home/absolute path** in any
  content that loads into agent context — describe it, placeholder it, or break the sigil
  from the path. The repo guard now enforces this.
- **The vector generalizes beyond documentation.** Any untrusted text entering the
  context (a fetched web page in a research flow, a third-party repo file, an issue body)
  that contains `@`+a-real-path can trigger the same attach. The harness-level fix is
  Anthropic's; the `permissions.deny` credential-read denylist is the operator-side
  backstop, and treating research/WebFetch against untrusted content as a credential-exfil
  surface is the standing posture.

## Related

- Incident observed during PR #6830 (the `/soleur:go 6827` one-shot run).
- `hr-never-paste-secrets-via-bang-prefix` (sibling secret-handling rule).
- Lower-risk sibling instance (out of guard scope, transient `/tmp` path):
  `knowledge-base/project/plans/2026-05-17-feat-r2-lock-rules-gdpr-override-plan.md:75`.
