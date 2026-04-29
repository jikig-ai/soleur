---
date: 2026-04-28
tags: [supabase, auth, ci, secrets, build-time-inlining, dual-source-of-truth, jwt, recurrence]
status: applied
issue: 3006
pr: 3007
predecessor: 2975
---

# Sign-in fully broken in prod — test-fixture anon-key JWT leaked into the production JS bundle via `secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY`

## What happened

Every sign-in attempt on `https://app.soleur.ai/login` redirected to `/login?error=auth_failed` ("Sign-in failed. If you have an existing account, try signing in with email instead."). All four OAuth providers (Google, Apple, GitHub, Microsoft), email-OTP, and email/password were affected.

Sentry events (mirrored to Sentry by PR #2994 hours earlier) showed:

```
op: exchangeCodeForSession
message: "Invalid API key AuthApiError"
errorCode: <empty>  errorName: <empty>  errorStatus: <empty>
```

Forensics:

- The deployed JS bundle had `NEXT_PUBLIC_SUPABASE_ANON_KEY` baked in with `ref=test` (test fixture JWT) instead of the canonical prd anon key with `ref=ifsccnjhymdmidffkzhl`.
- Supabase's auth API rejected every request as "Invalid API key" because the JWT issuer ref didn't match the routed project.
- Hot-fix at 2026-04-28T16:56:28Z: rotated the GitHub repo secret `NEXT_PUBLIC_SUPABASE_ANON_KEY` to the canonical Doppler value and triggered a fresh release.

This is the **second incident in the same class within 24 hours** — predecessor (PR #2975) shipped guardrails for `NEXT_PUBLIC_SUPABASE_URL` after the same operator-paste-during-rotation surface broke OAuth on 2026-04-27. The fix was URL-only; the symmetric anon-key surface was left undefended.

## Why it happened

`apps/web-platform`'s production image is built by `.github/workflows/reusable-release.yml`. The build step consumes `${{ secrets.NEXT_PUBLIC_SUPABASE_ANON_KEY }}` via Docker `build-args`. Next.js inlines `process.env.NEXT_PUBLIC_*` references into client chunks at build time via Webpack `DefinePlugin`. Once a chunk is built, the value is **immutable**; runtime env changes do not flow through.

`apps/web-platform/test/*` uses placeholder-shaped JWTs in 4 files (`byok.integration.test.ts`, `agent-env.test.ts`, `fixtures/qa-auth.ts`, `server/health-supabase.test.ts`). The most plausible operational origin is operator copy-paste during the same credentials-rotation window that produced the URL incident — pasting a test-fixture JWT into the GitHub repo secret slot.

PR #2975's URL gates did NOT cover the anon-key surface because:

- `reusable-release.yml`'s Validate step only checked `NEXT_PUBLIC_SUPABASE_URL`.
- `verify-required-secrets.sh`'s `SUPABASE_URL_RE` was URL-only.
- `validate-url.ts` is hostname-regex-shaped — fundamentally different shape contract from a JWT (regex vs. base64url claims). Extending it would have been wrong.
- Preflight Check 5 only grepped for Supabase hostnames, not for inlined JWTs.

Each `NEXT_PUBLIC_*` build-arg is its own structural surface. The URL fix was correct for URLs but structurally insufficient as a class fix.

## Fix

PR #3007 ships the symmetric guardrail set, mirroring PR #2975's four-layer defense for the anon-key surface:

1. **Pre-build CI assertion** (`.github/workflows/reusable-release.yml`): a step `Validate NEXT_PUBLIC_SUPABASE_ANON_KEY build-arg` runs after the URL Validate step and before `docker/build-push-action`. It decodes the JWT payload (base64url middle segment), parses claims via `jq`, and asserts:
   - `iss === "supabase"` (catches cross-vendor JWT paste — Auth0, Clerk, Stripe)
   - `role === "anon"` (load-bearing for security: rejects service-role-key paste, which would grant admin RLS bypass to every browser visitor)
   - `ref` matches `^[a-z0-9]{20}$` (canonical project-ref shape)
   - `ref` not in placeholder set (`test*`, `placeholder*`, `example*`, `service*`, `local*`, `dev*`, `stub*`)
   - `ref` matches the canonical first label of `secrets.NEXT_PUBLIC_SUPABASE_URL` (resolved via `dig +short CNAME` for `api.soleur.ai`)
2. **Runtime JWT-claims guard** (`apps/web-platform/lib/supabase/validate-anon-key.ts`): a sibling to `validate-url.ts` that exports `assertProdSupabaseAnonKey(rawKey, rawUrl)`. Same claims assertions as the CI step. **Gated on `process.env.NODE_ENV === "production"`** so the 4 anon-key-fixture test files are unaffected. `client.ts` calls it at module load alongside `assertProdSupabaseUrl`.
3. **Doppler-side shape check** (`apps/web-platform/scripts/verify-required-secrets.sh`): a new JWT-claims block after the URL shape check, asserting the same four claims so a placeholder-shaped value entered into Doppler `prd` also fails the secret-verification job.
4. **Preflight Check 5 Step 5.4** (`plugins/soleur/skills/preflight/SKILL.md`): extends the existing chunk-fetch (no new HTTP request) to grep the inlined `eyJ…` JWT in the deployed login chunk, decode the payload, and assert the same claims.

## Lesson

**The recurrence pattern matters.** When a class of incident produces a fix scoped to one variable in the class, the remaining variables must be tracked and prioritized — not deferred indefinitely. Issue #2980 (generalize to all 5 `NEXT_PUBLIC_*` build-args) was open at the time of the URL fix; the anon-key portion of #2980 should have been folded into PR #2975. Two separate brand-survival incidents in 24 hours instead of one.

**`role` claim distinction is load-bearing for security, not just correctness.** A Supabase service-role JWT is structurally identical to an anon JWT (same algorithm, same claim set, same length envelope). The only distinguishing field is `"role": "service_role"` vs `"role": "anon"`. If an operator pastes the **service-role key** into the `_ANON_KEY` slot, every browser session loads a JWT that bypasses Row-Level Security — silent data exfiltration class. The auth-break failure mode (test fixture) is self-evident and pages immediately; the role-confusion failure mode is silent and pages only when an attacker notices. The `role == "anon"` assertion in all four gates is the load-bearing defense for the worse failure mode.

**JWT shape gates ≠ JWT signature verification.** The validators do NOT verify the JWT signature. Anon keys are public; the signature check would require either embedding the project's signing secret (impossible) or a network call (defeats fail-fast at build time). Runtime auth is Supabase's responsibility; the gates are shape gates.

**Templatize, don't generalize.** Each `NEXT_PUBLIC_*` build-arg has a different shape contract (URL = hostname regex; anon key = JWT claims; Sentry DSN = URL with embedded project key; VAPID public key = base64url 65-byte EC point; GitHub App slug = lowercase-alpha string). A "generic NEXT_PUBLIC validator" is the wrong abstraction. The pattern this PR establishes — sibling validator module + CI step + verify-script block + preflight step + learning file — should be replicated per build-arg in #2980.

## Recurrence prevention

- **#2980** (generalize to remaining 4 `NEXT_PUBLIC_*` build-args) — re-prioritize. The pattern is now templated; folding in `SENTRY_DSN`, `VAPID_PUBLIC_KEY`, `GITHUB_APP_SLUG`, and `AGENT_COUNT` is mechanical work.
- **#2981** (Doppler-only build-args migration, Option B) — would eliminate the dual-source-of-truth class entirely (the underlying root cause of both #2979 and #3006). Defense-in-depth is a complement, not a substitute, for structural simplification.
- **PR #2994** (typed Sentry mirror for OAuth errors) — already landed. Reduced diagnosis time from "hours" to "minutes" by surfacing the exact Sentry breadcrumbs.

## Operator runbook (post-incident)

If the inlined anon-key JWT regresses to a placeholder/test-fixture value:

1. Decode the Doppler `prd` value to confirm the canonical key is still present:
   ```bash
   doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain \
     | cut -d. -f2 | { read p; pad=$(( (4 - ${#p} % 4) % 4 )); \
       printf '%s' "$p$(printf '=%.0s' $(seq 1 $pad))" | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r '"iss=\(.iss) role=\(.role) ref=\(.ref)"'; }
   # Expected: iss=supabase role=anon ref=ifsccnjhymdmidffkzhl
   ```
2. If Doppler is correct, rotate the GitHub repo secret from Doppler:
   ```bash
   doppler secrets get NEXT_PUBLIC_SUPABASE_ANON_KEY -p soleur -c prd --plain \
     | tr -d '\r\n' \
     | gh secret set NEXT_PUBLIC_SUPABASE_ANON_KEY
   # `--body` omitted on purpose: gh reads from stdin when --body is not specified.
   # `--body -` would set the secret to the literal '-'; inline `--body "$(...)"`
   # would expose the JWT on the process command line (`ps`, /proc/<pid>/cmdline).
   # Verified: gh secret set --help (gh 2.92.0, 2026-04-29).
   ```
3. Trigger a fresh release workflow run. The new CI Validate step now runs before any Docker work — confirm it passes.
4. Re-probe the deployed bundle:
   ```bash
   curl -fsSL https://app.soleur.ai/login \
     | grep -oE '/_next/static/chunks/app/\(auth\)/login/page-[a-f0-9]+\.js' | head -1 \
     | xargs -I{} curl -fsSL "https://app.soleur.ai{}" \
     | grep -oE 'eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+' | head -1 \
     | cut -d. -f2 \
     | { read p; pad=$(( (4 - ${#p} % 4) % 4 )); printf '%s' "$p$(printf '=%.0s' $(seq 1 $pad))" | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r '"iss=\(.iss) role=\(.role) ref=\(.ref)"'; }
   # Expected: iss=supabase role=anon ref=ifsccnjhymdmidffkzhl
   ```
5. Browser smoke test: navigate to `https://app.soleur.ai/login`, click "Sign in with Google", verify the Supabase auth screen loads (no `Invalid API key` error). Repeat for "Sign in with email", verify the OTP code form accepts a code.

## Audit trail

- Diagnosis Sentry event id: `c5affdf737e34110be747ce3a6463407` (timestamp `2026-04-28T16:53:25Z`)
- Hot-fix secret rotation: `2026-04-28T16:56:28Z`
- PR #3007 (this PR): four-layer guardrail set landed.

## Session Errors

These were caught during the PR session (mostly by multi-agent review) and resolved inline before merge. Each is paired with a prevention proposal so the workflow tightens on the next iteration of this class.

1. **Plan prescribed `dig +short CNAME` without a timeout.** Recovery: pinned `+time=3 +tries=2` (max ~6s) in `reusable-release.yml`. Prevention: add a Sharp Edge to `plan` skill (or `deepen-plan` Phase 4) — when prescribing `dig` in CI, always pin `+time` and `+tries` to bound runner wall-clock.

2. **Validator placeholder-prefix `startsWith` had false-positive risk on legit project refs.** A real Supabase ref starting with `dev`/`test`/`stub` would be rejected. Recovery: documented the tradeoff inline; prefix list still in place because (a) canonical prd ref doesn't collide, (b) collision is loud and one-line-fixable. Prevention: add a Sharp Edge to `plan` — when a deny-list of identifier-prefixes is prescribed, audit the actual identifier shape (Supabase refs are random alphanumeric, so any short prefix has non-zero collision probability) and document the tradeoff in the proposing plan.

3. **Preflight Check 5 Step 5.4 fail-open on chunk-fetch error.** SKIP semantics on a security gate is fail-open. Recovery: distinguished "host found but no JWT" (FAIL — bundle inconsistency) from "no host, no JWT" (SKIP — chunked elsewhere). Prevention: AGENTS.md already covers `cq-silent-fallback-must-mirror-to-sentry` for runtime; consider a complementary rule for security-gate semantics: "preflight checks on security-critical surfaces MUST fail-closed when input is partially observed; only fail-open when ALL signals are absent (truly indeterminate)." Domain-scoped to preflight skill; record there.

4. **Three-site policy drift on custom-domain semantics.** Runtime validator skipped cross-check for `api.soleur.ai`; CI did `dig` deref; preflight had no cross-check. Three policies for one case. Recovery: documented the asymmetry in validator JSDoc + verify-script comment; CI is load-bearing. Prevention: reinforce `pattern-recognition-specialist` + `architecture-strategist` in review pipeline (they caught it). No new rule warranted.

5. **`verify-required-secrets.sh` lacked URL/ref cross-check.** Doppler-side gate was strictly weaker than CI gate. Recovery: added cross-check for canonical hostnames (custom-domain still trusts JWT ref + CI dig). Prevention: when implementing a multi-layer defense, make a checklist of which assertions belong at each layer and run a coverage matrix in plan deepen pass. Add to `deepen-plan` Phase 4 sharp-edges.

6. **Workflow `::error::` echo lacked log-injection sanitization.** A crafted JWT with `\n` in claims could spoof success annotations. Recovery: sanitize via `${var//[$'\n\r']/}` before echo. Prevention: add a Sharp Edge to `plan` and `review`/security-sentinel — when echoing untrusted JSON-decoded values into GitHub Actions annotations (`::error::`, `::notice::`), strip CR/LF first.

7. **Dead `try/catch` on `Buffer.from(s, "base64url")`.** Node returns a partial buffer rather than throwing. Recovery: removed the dead branch; charset regex precheck is the real gate. Prevention: when adopting a Node-specific decoder in TS, verify the Node API's failure mode (some throw, some silently produce partial output) before wrapping in try/catch. Domain-scoped — record in the validate-anon-key.ts header comment, no AGENTS.md rule.

8. **`validate-url.ts` edit-together comment not updated when adding the sibling validator.** Recovery: updated the comment block to list all 4 mirrored sites. Prevention: when adding a sibling module that consumes another module's exported behavior, audit the source module's "edit-together" comment in the same commit. Domain-scoped — could add a `cq-edit-together-bidirectional` Sharp Edge to `plan` skill (when proposing a sibling module, include both directions of the comment update in the file change list).

9. **PreToolUse security_reminder_hook false-positives blocked Write of validator + Edit of workflow.** Hook flagged on doc-word "fail-fast" and on `${{ secrets.X }}` pattern despite proper `env:` block usage. Recovery: retried; succeeded on second attempt. Prevention: tighten `security_reminder_hook.py` regex precision OR exempt files in the `.github/workflows/` path that already use `env:`. Domain-scoped to the hook itself; track separately.

10. **CR-test name mismatch with assertion** (named "rejects" but asserted `.not.toThrow()`). Recovery: renamed to "strips trailing CR before parsing" + added LF parallel test. Prevention: when writing tests for input-sanitization behavior, the test name MUST match the assertion direction (`rejects X` ↔ `toThrow`; `accepts X` / `strips Y` ↔ `not.toThrow`). Add to `test-design-reviewer`'s checklist; no new rule warranted (caught by review).

11. **Bash CWD drift in worktree pipeline.** `bash -n apps/web-platform/scripts/...` failed because pwd had drifted into `apps/web-platform`. Recovery: chained `cd /worktree-abs && bash ...` in single Bash call. Prevention: already covered by AGENTS.md / constitution — the Bash tool does NOT persist CWD between calls (well-documented in `work` skill Phase 2.5). No new rule needed.

12. **`git add -p` heredoc input did not work as expected.** Recovery: fell back to plain `git add <files>`. Prevention: `git add -p` requires interactive TTY; the Bash tool's non-interactive shell breaks it. Default to `git add <explicit files>` when staging from agent shells. Workflow-level — already implied by AGENTS.md non-interactive rule; no new rule needed.
