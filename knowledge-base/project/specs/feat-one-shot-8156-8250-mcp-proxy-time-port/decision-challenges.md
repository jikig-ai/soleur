# Decision Challenges — feat-one-shot-8156-8250-mcp-proxy-time-port (#8156)

Headless-pipeline record; render at ship stage per
`plugins/soleur/skills/plan/decision-challenges.md` convention.

## User-Challenge findings

None. The plan resolves the register-vs-auto-wrap choice WITHIN the
operator-specified option set in #8156 ("ship a `playwright` MCP server …
**or** automatically wrap a customer's existing `playwright` registration");
choosing the registration arm inside the stated option set is not a
user-challenge per `cm-challenge-reasoning-instead-of`.

## Taste findings / deferred adjudication

1. **CTO-decision reservation satisfied by recorded rationale, not live sign-off.**
   #8156 frames the register-vs-wrap choice as "a CTO decision at spec time."
   This headless pipeline could not spawn a CTO Task agent; the decision was
   made on the record (Alternative table row B: no implementable, consented
   auto-wrap mechanism exists — the only form is an unconsented
   `.mcp.json`/`.claude.json` mutation that also fails P7 in the session it
   lands). Ship-stage renders this as the decided-by-plan item; escalate only
   if the CTO disputes the "no consented mechanism" premise.
2. **CPO sign-off pending (required before `/work`).** Threshold is
   `single-user incident`. The sign-off question is narrow: the fix ships a
   stdio MCP server spawning `python3`+`npx` on every customer session, with a
   persistent browser profile under the user cache dir, and degrades
   gracefully on non-Claude-Code harnesses.
3. **Option C deferred rather than decided.** The hook-net alternative was
   deferred (not rejected) with re-evaluation criteria — transcript-only
   coverage, cannot close disk sinks. Deepen-pass verified upstream #47859 /
   #24788 / #54161 CLOSED, so the deferral is coverage economics, not
   mechanism viability; the deferral issue (AC9) records that.
4. **`engines` floor contingency.** If Phase-0 probe fails `>=2.1.139`, the
   floor bumps in `plugin.json` — an install-bar change the plan flags for
   CPO rather than taking silently.
