# ADR-086: Declarative skill context-injection via a lazy PostToolUse:Skill hook (pointer, not inline)

- **Status:** Accepted
- **Date:** 2026-07-05
- **Issue:** [#5989](https://github.com/jikig-ai/soleur/issues/5989) (gstack-adoption epic [#5983](https://github.com/jikig-ai/soleur/issues/5983), Wave 2 · FR6; unblocks [#5990](https://github.com/jikig-ai/soleur/issues/5990) taste-learning)
- **Relationship to ADR-070 (phase-surface hint):** reuses the `PostToolUse(Skill)` → `additionalContext` mechanism ADR-070 established (`.claude/hooks/phase-surface-hint.sh` + the web JS port `apps/web-platform/server/phase-surface-hook.ts`). This ADR adds a **sibling** hook with a **different trust model** — it emits committed-file *references*, where phase-surface emits map-derived constant text. The two are deliberately separate scripts.

## Context

gstack's `gbrain` loads context *declaratively* — a command/skill declares which knowledge files it needs and they load automatically. Soleur wanted the mechanism (FR6) in its committed-knowledge frame (no `~/.gstack` per-machine storage; AP-006), as the substrate the taste-learning feature (#5990) rides — its committed `taste-profile` is the first real consumer.

**OQ2 (the load-bearing decision): where does resolution happen?** Two candidates:
- **Eager** — extend the SessionStart loader `session-rules-loader.sh` to scan all ~90 skills' frontmatter at session start.
- **Lazy** — a new `PostToolUse(Skill)` hook resolves only the invoked skill's `context_queries`.

TR2 mandates: *a bad query must not fail-closed all ~90 skills.*

## Decision

**Lazy per-skill `PostToolUse(Skill)` hook** (`.claude/hooks/skill-context-queries.sh`), registered as a sibling `Skill` matcher block alongside phase-surface-hint.

**Headline invariant (pin this — a future refactor must never break it):** PostToolUse fires **after** the Skill tool has dispatched, so the hook physically **cannot** block, gate, or undo the skill. That post-dispatch timing + `set -e` off + `trap 'exit 0' ERR` + exit-0-on-every-path makes TR2's "fail-closed all ~90 skills" catastrophe impossible **by construction**, not by careful code. **Never move this to PreToolUse; never add a blocking or unbounded path.**

**Delivery is a POINTER, not inline content.** The hook resolves each `context_queries` entry to a committed `knowledge-base/` artifact and injects a **Read-directive** naming the paths — the agent loads them through its normal `Read` channel. Chosen over inlining content because: (a) the pilot artifact `brand-guide.md` is 36 KB — far over any sane `additionalContext` budget (CC caps it at 10,000 chars), so inline would always degrade to a pointer anyway; (b) a pointer routes content through the same trust channel as any repo file, dissolving the hook-injected-content prompt-injection surface and all byte-budget/truncation machinery. "auto-load into context" is satisfied when the declared artifact **reliably reaches the agent's context without the agent having to locate it** — a directed Read meets this.

**Security model.** `tool_input.skill` is MODEL-controlled and now flows into a *path* (a new trust boundary phase-surface-hint lacks): anchored `${SKILL#soleur:}` strip → `^[a-z0-9-]+$` gate → realpath containment under `plugins/soleur/skills/`. `context_queries` paths (config-trust, defense-in-depth): `knowledge-base/` prefix, reject `..`/absolute, realpath containment, symlink reject, and `git ls-files --error-unmatch` (committed-only; also does glob expansion so no pathspec is eval'd). Envelope via `jq -n --arg`. jq+bash only (no `yq`/python) — frontmatter parsed with the repo's awk `c==1` idiom.

## Consequences — standing constraints on ALL future `context_queries` consumers

These outlive #5990 and bind every later adopter (recorded here, not only in an issue thread):

- **content-trust ≠ path-trust.** The mechanism guarantees an artifact is committed and path-contained — NOT that its *content* is trustworthy. A skill pointing `context_queries` at agent-authored / agent-writable content (e.g. #5990's `taste-profile`, generated from user design feedback) auto-consumes untrusted content that can carry latent instructions. Such consumers MUST sanitize/validate their own content; this hook only fences provenance and enforces committed-only.
- **must-present = literal path, never glob.** An artifact that must reliably load is declared as an explicit literal path. Glob matches are sorted and capped (`MAX_GLOB`), so under the cap *which* files drop is order-dependent — a load-bearing artifact must not depend on glob inclusion.

## Surface scope (CLI-first, web parity deferred — feasible, tracked)

The hook is a CLI `.claude/` shell hook; web-agent Concierge sessions run `settingSources:[]` and are isolated from shell hooks (ADR-070). So the pilot auto-loads on the CLI surface but not the web Concierge — an **accepted, time-boxed capability gap**, not "no regression": the same design skill behaves differently across surfaces. **Verified CLI-first, not CLI-intrinsic:** web sessions *do* emit `PostToolUse(Skill)` and run an in-process port (`apps/web-platform/server/phase-surface-hook.ts`; note web emits *bare* skill names, CLI emits `soleur:`-prefixed), so a web port is buildable via that precedent. Deferred to a tracked follow-up so #5990 chooses the surface(s) its taste-profile needs.

## Composition fallback

Registered as a sibling `Skill` matcher block (independently enable/disable-able). CC runs all matching PostToolUse hooks; with a ~1-line pointer payload the shared 10,000-char `additionalContext` budget is not a practical concern. If a future CC version were found to last-writer-wins multiple `additionalContext` emitters, the fallback is a **new dedicated single-emitter hook** owning both concerns — NOT grafting content-referencing into phase-surface-hint (which would re-entangle the two trust models this ADR keeps separate).

## Alternatives considered

- **Eager SessionStart scan** — rejected. Loads every skill's artifacts every session (context bloat vs the repo's byte-budget discipline); entangles the compliance-critical `session-rules-loader.sh` (SOC2 evidence path — hard boundary per learning `2026-05-12-agents-md-trim-loader-class-fit-verification.md`); and makes TR2's "fail-closed all ~90 skills" the **default** failure mode rather than a structural impossibility.
- **Extend `phase-surface-hint.sh` in place** — rejected. SRP violation + trust-model mismatch (constant map text vs committed-file references).
- **Inline artifact content** — rejected for v1 (pilot is 36 KB > cap; adds byte-budget/truncation/fence machinery for a marginal "no extra Read" gain). Re-introduce bounded inline only if a consumer proves a directed Read is insufficient.

## Verification

- `.claude/hooks/skill-context-queries.test.sh` (git-init fixture repo): happy-path pointer, inline+block parse, glob determinism, traversal/symlink/untracked rejection, no-op fast-exit, adversarial-name no-exec, kill-switch, and a consistency check that the real pilot resolves ≥1 committed artifact.
- Upholds **AP-006** (committed-only, rejects `~/.gstack`), AP-010, AP-011.
