Ref #10479. Ref #10205.

## Worst case, and why we think it will not happen

Worst case: one of the Cloudflare tokens this tool uses can change how traffic reaches the product. If it ever leaked into a conversation transcript, someone who can read that transcript could downgrade encryption, redirect traffic or switch off protection on the sign-in and API-key routes. For customers that means exposed API keys or an outage. We think this will not happen because the tool can only send read requests to four fixed addresses, the token travels on a channel that never appears on screen, and every helper program it starts runs with an empty environment; 1019 tests, including 106 deliberate break-it checks, prove those properties. What we do not defend is the caller's own shell environment, which is the operator's own session. The CTO agent's own recommendation is to wait for read-only tokens; until then this PR is a bridge, so treat it as low-value-but-safe rather than essential.

This PR adds a GET-only Cloudflare read tool so the CTO agent can run the live-read checks for #10479 (zone SSL mode, config-rule entrypoint, legacy page rules, audit change history) without handing them back as tasks. It is a draft and unarmed. No live Cloudflare call, Doppler read, workflow dispatch or production write was made by this PR or by any test in it. The first live read happens after you merge, from a checkout where `git diff origin/main -- plugins/soleur/scripts/cloudflare-readonly.sh` is empty.

## Needs you

- Merge or arm this pull request, which also starts the two release workflows (`version-bump-and-release`, `web-platform-release`) because the diff touches `plugins/soleur/**`. (operator: production-mutating)
- Mint read-only Cloudflare tokens (#11857) and add the audit token to the provisioned Doppler config; this ends the write-token bridge below and lets the audit read work. (operator: production-mutating)

## What the agents already decided (nothing for you to do)

- Sign-offs: the CPO agent approved with conditions (both false-fact directions and the concrete leak outcomes are now in the plan; this paragraph is the plain worst case it asked for). The CLO agent ruled the audit read legal-ok: nothing printed is personal data, no register or policy change, no GDPR gate. Threshold: `single-user incident`.
- Write-capable tokens: three of the four reads use Terraform tokens that can also write, because no read-only equivalent exists. The CTO agent accepted this as a bridge that expires when the read-only mint (#11857) lands; the stricter alternative (keep those reads unverified until then) is recorded as a dissent. Open item owned by the CTO agent: confirm a revoke-and-rotate path for both tokens if a transcript is ever suspected to hold one (no runbook exists yet).
- Push-bar clause: the draft-push rule now reads `scripts/**` as any directory named `scripts` at any depth and exempts exactly two files, the wrapper and its test. Against the broad reading the net widening is zero; push eligibility of this branch does not depend on it, and it is dropped if your recorded text says otherwise.
- Expected results on the first live read (each valid and recorded, never worked around): the audit read is `no-credential` or refused until the token is in the provisioned config; the page-rules read may be `token-lacks-scope`; the audit read never becomes a `Checked:` line because a 7-day window cannot bound the exposure back to 2026-03-17.

## What the review found and fixed

Nine-seat panel plus a targeted fix-round review, coverage disclosed as degraded 9/12 (no database, hot-path or agent surface in the diff). Fixed: a planted `~/.jq` could print the token (jq and date now run with an empty environment); verdicts for the rule checks rest on counts and the adopted rule id, never on substring matching of text the tool does not print; the curl flag set is exact-argv equality; the projection test group is now break-it proven; the push-bar clause has one reading. Records mapping and rulings: `knowledge-base/project/specs/feat-one-shot-10479-cf-readonly-wrapper/decision-challenges.md` (D1 to D17).

## Verification (local, hermetic, stubbed curl, fake tokens)

- `plugins/soleur/test/cloudflare-readonly.test.sh`: 1019 passed, 0 failed; same under `CI=1` and `SOLEUR_SUBAGENT=1`; 106 mutation rows caught.
- `bun test plugins/soleur/test/components.test.ts`: 1571 pass, 0 fail (59 pin rows); item 4 and Credentials mutation drive: 22 mutants caught.
- Lints, ratchets, c4 parity, orphan lint, shellcheck, technical-ruling gate: green.
- The branch is behind `main` by a few commits and merges cleanly; it has not been synced.

Separately tracked: the dev key-rotate plan rehearsal ran green (recorded on #11294); the Cloudflare flip is not ready (no origin TLS listener yet, per the CTO read-only checks on #10479).

🤖 Generated with [Claude Code](https://claude.com/claude-code)
