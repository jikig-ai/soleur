# Decision Challenges — feat-one-shot-discord-blog-channel-fallback

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Surfacing mechanism: marker-grep + `warnSilentFallback` in the cron step vs. forwarding all captured stderr vs. stderr-only | technical | pending - assumed: marker-grep + warn-level mirror. `spawnScriptCapture` discards stderr (`cron-content-publisher.ts:696-712`); a stderr-only warning is invisible in prod. Marker grep follows the `SOLEUR_CREDENTIAL_REFUSED` convention and keeps raw stderr (and any incidental content) out of Sentry. |
| `warnSilentFallback` vs `mirrorWarnWithDebounce` for the mirror | technical | pending - assumed: `warnSilentFallback` — once-daily cron cadence makes the 5-min debounce unnecessary; warn level (not `reportSilentFallback`) because the fallback is intended design, not an error. |
| Marker token `SOLEUR_PUBLISHER_FALLBACK` embedded in the human-readable warning line (vs. grepping the prose) | technical | pending - assumed: dedicated stable token — pinned identically by tests on both sides (Guard 1 row 4 catches drift). |
| Extend `run-publisher-script` step return with `discordBlogFallback: boolean` | technical | pending - assumed: include — cheap, deterministic (ADR-033 I5), and puts the flag in the Inngest run record. |
| Brand-survival threshold `none` while diff touches `apps/web-platform/server` (sensitive path) | technical | pending - assumed: none — emit sites are value-free fixed strings; no credential/user-data/tenancy surface altered (scope-out reason in plan's User-Brand Impact). |
| Prod `DISCORD_BLOG_WEBHOOK_URL` Doppler secret (`soleur/prd`) | operator (production-mutating authorization) | Handled outside this branch per the one-shot brief — dedicated webhook already minted on channel `1481578783000629329`; operator sets the Doppler secret separately. No plan action; the warning self-silences once it lands. |
| Second-posting-path fixes (social-distribute interactive skill's identical `${BLOG:-GENERAL}` fallback) | technical | pending - assumed: out of scope per brief ("fix only the content-publisher path"); it is an interactive skill whose output is operator-visible. Census recorded in the plan's Research Insights. |

## Not Yet Specified

- Whether a persistent fallback (marker still firing N days after the prd secret was expected) should escalate to an `action-required` issue — cut list entry in the plan says re-evaluate if the fallback persists.
