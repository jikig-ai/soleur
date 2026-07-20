# Decision Challenges — feat-one-shot-6147-recreate-pin-gate-component-filter

Headless-mode surfaced challenges to the operator's stated direction. `/soleur:ship` renders these
into the PR body and files an `action-required` issue for operator review.

## User-Challenge: pure `/health` resolution adopted over "filter by component"

**Operator's stated direction (issue #6147):** "Filter the pin-gate read by component … **Preferred**
— smallest, keeps the safety property." (option 1)

**What the plan does instead:** resolves web-1's running tag from `app.<domain>/health` `.version`
and **drops the deploy-status `.tag` read entirely** (ADR-079 amendment #5955's already-adopted
pattern). It does NOT filter the deploy-status slot by component — it stops reading that slot.

**Why the plan deviated (plan-review convergence, not a solo call):**
- The deploy-status slot is a **single last-write-wins object**. When a non-web writer (inngest
  restart, git-lock sweep) owns it, there is **no web frame to select** — a pure component filter
  cannot produce a tag, so a `/health` fallback is required regardless. Once `/health` is the
  mandatory fallback, the retained deploy-status read is a second, *less-correct* source: `.tag` is
  the state file's **last-ATTEMPT** tag (#5955), while `/health .version` is the **actually-running**
  container's `BUILD_VERSION`.
- Independent plan-review agents **DHH** and **code-simplicity** both recommended promoting pure
  `/health` (Alternative 2) to primary; **SpecFlow** found the hybrid introduced flow gaps (undefined
  web-frame outcome, in-flight masking, a tri-state contract the resolver can't express) that all
  **evaporate** under pure `/health`. **Kieran** confirmed all correctness facts.
- Pure `/health` is the pattern the sibling `apply-deploy-pipeline-fix.yml` already uses for the
  identical "`.tag`=latest wedge" — so it is *more* aligned with the codebase's own adopted
  decisions (ADR-079 #5955) than the component-filter approach.
- The operator's "filter by component" was a **means** to the end (unblock the recreate without
  trusting the contaminated slot); pure `/health` serves that end more simply and more correctly.

**Host-targeting note (why `/health` is safe here):** `app.soleur.ai` is a single A record hard-
pinned to web-1 (`dns.tf:13`); multi-host round-robin is deferred to #5274. If that rewire lands,
the resolver must switch to a web-1-pinned health path (callsite comment + AC track this).

**Operator decision needed:** confirm the pure-`/health` approach, OR direct a return to the
component-filter + `/health`-fallback hybrid (documented as Alternative 1 in the plan).
