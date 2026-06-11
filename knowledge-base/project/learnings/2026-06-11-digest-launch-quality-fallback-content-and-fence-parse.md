# Learning: a degraded-mode renderer is a product surface — verify ITS output quality, not just that it posts

## Problem

The weekly release digest's launch post was "a list of version numbers" (operator
report). Two stacked causes: (1) claude-sonnet-4-6 wraps JSON in markdown fences
despite ONLY-JSON prompting, so `JSON.parse` threw and EVERY run silently used the
deterministic fallback; (2) the fallback rendered release NAMES verbatim, and
plugin releases are named by their tag — so the "digest" was `• v3.148.0` bullets.
All 33 unit tests were green: the fallback tests asserted titles posted, with
fixtures whose names were real titles ("feat: csv export") — never the
name-equals-tag shape production actually has.

## Solution

- `extractModelJson` (leaf module `server/model-json.ts`): strip one outer fence,
  any language tag/case; wired into all three Messages-API parse sites (digest,
  compound-promote, domain-router). PR #5162.
- Fallback title derivation: when a release name is version-shaped
  (`/^[a-z-]*v?\d[\w.-]*$/i`), use the first changelog line (the squashed PR
  title), PII-stripped BEFORE truncation; security-sensitive bodies are never
  mined. PR #5166.
- The lame launch message was deleted via the webhook DELETE endpoint and replaced
  by a re-fired curated digest.

## Key Insights

1. **Fixture realism beats fixture convenience.** The fallback tests used
   human-readable names because they were convenient to assert on; production
   names are version strings. One fixture mirroring the live `gh release list`
   shape (`name == tag`) would have caught the bare-version output pre-merge.
2. **A fallback that posts unacceptable content is worse than no fallback** — it
   converts an invisible API failure into a visible brand-quality failure. Treat
   the degraded path's OUTPUT as a product surface with its own quality bar, not
   just a liveness mechanism.
3. **Verification fires must include a content-quality check, not just a
   posted/monitor-green check.** The post-merge verification asserted "a digest
   message exists" + "Sentry ok" — both true while the content was garbage. The
   operator was the quality gate; a one-line "bullet text must not match the
   version regex" assertion on the verification read closes that.
4. **Webhook messages are deletable with the webhook token**
   (`DELETE /webhooks/{id}/{token}/messages/{message_id}`) — a bad automated
   public post is recoverable; delete-and-refire beats apologizing around it.

## Session Errors

1. **Verification trigger initially fired against a mid-restart container**
   (502s right after deploy) and the retry loop's worktree was deleted by a
   sibling cleanup mid-run. Recovery: re-fire after health 200. **Prevention:**
   gate verification fires on /health 200, not just workflow conclusion.

## Tags

category: bug-fixes
module: release-digest, inngest, llm-output-parsing
