---
title: "The fixture outlived the thing it modelled, and four green rows were asserting a capability production lost eight weeks ago"
date: 2026-09-23
category: test-failures
tags: [testing, fixtures, vacuous-green, registry, ci-deploy, retirement, observability]
issue: 8036
---

## The shape

`#8036` item 1c retired the host-side GHCR read path from `ci-deploy.sh`: the prelude
`docker login ghcr.io`, the Doppler re-fetch/relogin helper, and the auth-denied leg of the pull
helper. The credential all three depended on — the GHCR read PAT — has been **revoked since
2026-07-29** (`GET api.github.com/user` → 401, token mint → DENIED, `GHCR_MINTER_DISABLED=true`).

Deleting 250 lines of code that cannot succeed should have been a small change. It moved **38 of
346 rows** in `ci-deploy.test.sh`. Almost none of them were testing the deleted code.

## What actually happened

The suite's `docker` mock serves **every** GHCR pull unconditionally. So inside the test harness,
GHCR had been a working fallback the entire time it was dead in production. That one fact
propagated:

- The suite's **default mode was zot-dark**, because it did not need zot: a zot-dark deploy fell
  through to GHCR, the mock served it, and "a deploy ran" was expressible without a registry
  anyone had configured. After 1c a zot-dark deploy is terminal, so every row that merely needed
  a deploy to *reach its subject* was suddenly asserting against the failure path — canary
  ordering, rollback, Doppler env resolution, cosign invocation shape, the local-cache tier.
- **`T-7095-6` pinned a capability that no longer existed.** Its contract: "a network-shaped
  Doppler read failure must still COMPLETE the deploy, on the baked GHCR creds." Completing on
  the baked GHCR creds requires those creds to work. Since 2026-07-29 the live fleet takes
  `image_pull_failed` down that path. The row was green for eight weeks while the property it
  named was false in production.
- **`T-1a-3`'s positive control silently inverted.** It seeded a `ghcr.io` credential canary into
  the deploy docker config to prove that canary is *not* visible to the anonymous verifier-image
  pull. 1c added a sweep that deletes exactly that key on every deploy — so the fixture scrubbed
  itself before the measurement, and "the canary is not visible" became true for the wrong reason.
- **`AC3` started passing on a comment.** It anchored on the retired call shape
  `_pull_result_is_auth_denied "$(tail -c 400 "$perr"`. I deleted the call and wrote a comment
  explaining the deletion — which quoted the call shape verbatim. The assertion matched the prose.
  Same class as `cq-assert-anchor-not-bare-token`, committed by the person fixing that class, in
  the same hour.

## The generalisable rule

**A fixture that supplies a capability production has lost is not a stub — it is a false premise,
and every row downstream of it inherits it.** The rows are not wrong about their own subject; they
are answering a question in a world that no longer exists. Nothing goes red, because the fixture is
consistent with itself.

Two checks, both cheap:

1. **When a credential, endpoint or dependency is measured DEAD in production, grep the test
   harness for the mock that still serves it, and date it.** `MOCK_GHCR_PULL_*` had served
   unconditionally since long before the revocation. A one-line comment on the mock
   (*"GHCR pulls have failed on the fleet since 2026-07-29; this mock does not model that"*)
   would have made all four instances visible on the day the PAT died, not on the day the code
   was deleted.
2. **When a retirement makes a fallback unreachable, the harness's DEFAULT mode is part of the
   diff.** Ask what the default models. If the default is the path being retired, the retirement
   is not a deletion — it is a change of the system's normal case, and the row count will say so.

## What we did

- Armed zot by default in the harness, with `MOCK_ZOT_DARK=1` as the explicit opt-out for the rows
  that are *about* the dark gate. The default now models the only registry that exists.
- Re-pointed rows whose property survived (the bounded transient retry is registry-neutral; token
  hygiene lives in the shared `_docker_login_capture`; the per-secret Doppler cred-fail markers
  still have SENTRY_* subjects), and **deleted** rows whose subject was the GHCR credential itself.
  The distinction is the whole judgement: re-pointing a row whose subject is gone produces a row
  that passes while asserting nothing.
- Wrote every deletion down *in place*, with why — `§1A`, `#6400 AC1/AC2/AC4/AC13/AC14`,
  `#6497 T-5B-17/T-5B-18` — rather than removing them silently, because "this row used to assert
  X and X is now impossible" is the only thing that stops the next reader re-adding it.
- Replaced two `*_BODY=$(awk '/^<deleted-function>/,/^}/' ...)` extractions rather than leaving
  them: over a function that no longer exists the awk range yields an **empty string**, and every
  `! printf '%s' "$BODY" | grep -q …` negative over it is then vacuously true.

## The other half: a pure-absence close criterion

The operator's stated close criterion for 1c was *"`stage=relogin_failed` absent on the first
post-apply deploy"*. A host that is down, that never ran the new script, or whose log channel is
dark also emits no `relogin_failed`. The probe grades a **conjunction** instead, and the version
discriminator is a token the pre-1c script **cannot emit** (`swept=`) rather than the obvious
`deploy_ghcr_auth=none` — because `docker login ghcr.io` currently *fails*, a failed login writes
no auths entry, and a freshly provisioned **pre**-1c host therefore reads `none` on its first
deploy and would sail straight through.

**Generalisable:** when grading "did the new code reach this host", pick a token whose *presence*
is impossible in the old version. A token whose *value* differs is not enough if the old version
can produce the passing value for an unrelated reason.

## Related

- `knowledge-base/project/learnings/best-practices/2026-07-03-pass-is-not-proof-three-vacuous-green-traps-in-infra-verification.md`
- `knowledge-base/project/learnings/2026-07-15-silent-fallback-masked-a-dead-primary-for-14-days.md` — the inverse:
  there, a working fallback hid a dead primary; here, a fake fallback hid that the primary's
  replacement was already the only one.
- ADR-169 Named residual 3 (the `ghcr-fallback` emitter, dark → deleted) and ADR-096 task 5.3a.
