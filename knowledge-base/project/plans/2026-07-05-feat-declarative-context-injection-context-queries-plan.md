---
title: "feat: declarative context-injection — skill-frontmatter context_queries"
issue: 5989
epic: 5983
unblocks: 5990
branch: feat-5989-context-queries
pr: 6035
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
spec: knowledge-base/project/specs/feat-gstack-capability-adoption/spec.md
brainstorm: knowledge-base/project/brainstorms/2026-07-04-gstack-capability-adoption-brainstorm.md
adr: ADR-086 (provisional — re-verify next-free ordinal at ship)
date: 2026-07-05
plan_review: 6-agent panel applied (DHH, Kieran, code-simplicity, architecture-strategist, spec-flow, CTO-devex) → pointer-only
---

# ✨ feat: Declarative context-injection — skill-frontmatter `context_queries`

Wave 2 · FR6 of epic #5983 (gstack capability adoption). Adapts gstack `gbrain`'s
*declarative* context-loading pattern into Soleur's committed-knowledge frame —
**without** its per-machine `~/.gstack` storage (upholds AP-006). Unblocks FR7
(#5990 taste-learning), the first real `context_queries` consumer.

## Overview

Skills declare a `context_queries` list in their `SKILL.md` frontmatter naming
committed `knowledge-base/` artifacts. When a skill is invoked, a lazy
`PostToolUse:Skill` hook resolves + containment-checks those paths and injects a
**Read-directive** ("Read these committed artifacts before proceeding: …") via
`hookSpecificOutput.additionalContext`. The agent then loads them through its
normal `Read` channel.

**Resolved OQ2: lazy per-skill hook, not the eager SessionStart loader.** Modeled on
the live `.claude/hooks/phase-surface-hint.sh` (PostToolUse:Skill → additionalContext;
`set -e` off + `trap 'exit 0' ERR`; `jq --arg` sanitization). The headline invariant
(→ ADR-086): **PostToolUse fires *after* the Skill tool has dispatched, so the hook
physically cannot block, gate, or undo the skill** — that timing (not merely per-skill
isolation) is what makes TR2's "fail-closed all ~90 skills" impossible *by
construction*. Eager was rejected: it bloats every session, entangles the compliance-
critical `session-rules-loader.sh` (SOC2 evidence path — hard boundary per learning
`2026-05-12-agents-md-trim-loader-class-fit-verification.md`), and makes TR2's
catastrophe the *default* failure mode. Extending `phase-surface-hint.sh` in place was
also rejected (SRP + trust-model: it emits map-constant text, never file references).

### Pointer, not inline (6-agent plan-review decision)

The plan-review panel (DHH + code-simplicity: cut; spec-flow: *forcing fact*) converged
on **emitting a Read-pointer, not inlining artifact content**:
- The pilot artifact `brand-guide.md` is **36,254 bytes** — ~4.5× any sane inline
  budget, so an inline pilot would *always* fall back to a pointer anyway; inlining is
  machinery for a case that never fires here.
- A pointer routes content through the agent's **normal `Read` trust channel** — the
  same trust as any repo file — dissolving the hook-injected-content prompt-injection
  surface (no provenance-fence needed) and the byte-budget/truncation machinery.
- **"loads" is pinned:** the issue's "auto-load committed artifacts into agent context"
  is satisfied when the declared artifact **reliably reaches the agent's context without
  the agent having to *locate* it** — a directed Read meets this. Inline (guaranteed-
  presence-with-no-Read-step) is deferred to #5990 *if it proves it needs it*.

This deletes ~40% of the original mechanism (inline path, byte budget, provenance fence,
`head -c`/`MAX_FILES`/`timeout`, sentinel mirror, fleet CI lint). The **security core is
untouched**: name sanitization, `knowledge-base/` containment, committed-only, fail-open.

### Pilot

`frontend-design` → `knowledge-base/marketing/brand-guide.md`. Chosen because #5990
extends **exactly** `frontend-design`/`ux-design-lead`, so the pilot is the seam #5990
rides (its `taste-profile` becomes a second `context_queries` entry). Runtime behaviour:
the hook emits a Read-directive naming brand-guide.md (honest — no fixture escape hatch).

### Surface-parity: a known, tracked capability gap (not "no regression")

The C4 model (`model.c4:41`, ADR-070) documents **two** hook surfaces: the CLI `.claude/`
shell Hook Engine (where this hook lives) and the web-agent **in-process** `options.hooks`
registry (web sessions run `settingSources:[]`, isolated from shell hooks). A shell hook
reaches only the CLI plugin. **FR6 ships CLI-only.** Per architecture-strategist + CTO-
devex, this is *not* "no regression" — it is a **known surface-scoped capability gap**:
after ship, `frontend-design` auto-loads the brand guide in the CLI but not in the web
Concierge (same skill, two silent behaviours on a design-critical skill; #5990's
taste-profile would "not stick" in web). Owned, not buried:
- **Phase 0 verifies whether web-agent sessions even emit `PostToolUse:Skill`.** If not,
  `context_queries` is CLI-*intrinsic*, not CLI-*first* — which changes what #5990 must
  build. The deferral issue records which.
- A web-parity tracking issue is filed **now** (not "when #5990 decides"), stating the
  user-facing symptom. The ADR names the split as an **accepted, time-boxed** cost.

## Research Reconciliation — Spec vs. Codebase

| Claim | Reality (verified) | Plan response |
|---|---|---|
| "context-injection is the SessionStart loader" (brainstorm CTO) | `phase-surface-hint.sh` proves PostToolUse:Skill additionalContext works (ADR-070) | Lazy PostToolUse:Skill |
| Parse YAML frontmatter in-hook | `yq` NOT installed; python not guaranteed in GHA/headless | Reuse the full `scripts/generate-kb-index.sh` awk idiom (jq+bash only) |
| Inline content, ~50KB budget (v1 draft) | CC caps additionalContext at 10,000 chars; pilot artifact is 36KB | **Pointer-only** — no inline, no budget |
| Block-only frontmatter grammar (v1) | The existing idiom already parses inline `[a,b]` + block; a stricter subset **silently parses valid YAML to zero queries** (parse-to-empty trap) | Reuse the FULL idiom (inline+block); a present-but-unparseable declaration emits a skip note, never silent |
| `tool_input.skill` value | `soleur:`-prefixed at runtime (`phase-surface-map.json` keys) | `${SKILL#soleur:}` anchored strip → `^[a-z0-9-]+$` |
| in-band note is "operator-visible" (v1) | `additionalContext` is delivered to the **model** as a `<system-reminder>`, NOT rendered to the operator | Reword: model/transcript-visible; phrase note as an instruction the agent must surface |
| Hook Engine C4 | only `hooks -> claude "Guards tool calls"`; no `hooks -> kb` | Add `hooks -> kb`; correct description (already-falsified pre-existing debt) |
| brand-guide auto-loads for the operator | only on the CLI surface; web Concierge unaffected | Known capability gap; web-parity issue filed now |

### Scoped advisor consult (ADR-083, `fable`) — applied
Consult flagged pointer-only + a multi-hook-composition spike + a misconfig lint; the
6-agent panel then confirmed pointer-only and refined the rest. All folded in below.

## User-Brand Impact

**If this lands broken, the user experiences:** a skill they invoke is silently missing
the brand/taste context it should have surfaced → off-brand or context-blind output the
non-technical operator cannot diagnose. (Applies on the CLI surface; the web surface is a
**known capability gap** above, not a regression.)

**If this leaks, the user's data/workflow is exposed via:** a path-traversal or symlink
escape in the resolver reading a file *outside* `knowledge-base/` (e.g. `.env`, secrets)
and naming it to an agent whose context reaches the model.

**Two additional failure modes (user-impact-reviewer, both mitigated):**
- *Suppressing the existing phase-surface hint fleet-wide* — adding a second
  `PostToolUse:Skill` hook could clobber `phase-surface-hint.sh`'s output if CC
  didn't concatenate. **Mitigated/confirmed:** CC delivers *all* `additionalContext`
  values (official docs) — no suppression. See tasks.md 0.1 / ADR-086 §Composition.
- *Silent drift is model-invisible to the operator* — a renamed/moved artifact makes
  every design call emit "declared but 0 resolved" to the model only. **Mitigated:**
  the skip note now instructs the agent to *tell the user* which artifacts were
  skipped (so a non-technical operator gets a visible signal), and the pilot
  consistency test (AC14) catches drift for the pilot at every CI run.

**Brand-survival threshold:** single-user incident. → `requires_cpo_signoff: true` (CPO
reviewed the brainstorm framing — carry-forward); `user-impact-reviewer` at PR review;
deepen-plan invoked (ultrathink).

> An empty/`TBD` `## User-Brand Impact` fails deepen-plan Phase 4.6. Filled.

## Implementation Phases

### Phase 0 — Preconditions (verify against installed state)
- **0.1 (composition spike — FIRST, blocks topology):** register a throwaway second
  `PostToolUse:Skill` hook (the **exact `settings.json` shape** to ship — a sibling
  matcher block) emitting a sentinel, invoke a skill, and verify (a) both the sentinel
  **and** phase-surface's hint reach the model (concat vs last-writer-wins), and (b)
  whether the 10,000-char cap is **per-hook or aggregate**. Concat → sibling block (the
  planned topology). Last-writer-wins → ship a **new dedicated single-emitter hook** that
  owns both concerns (do **not** graft content-referencing into `phase-surface-hint.sh` —
  that re-entangles the trust models the design keeps separate); record the tradeoff in
  the ADR. (Under pointer-only the payload is ~1 line/artifact, so the cap-collision is
  largely moot; the concat-vs-clobber delivery question is the real unknown.)
- **0.2** Confirm `brand-guide.md` is git-tracked (it is; 36 KB — pointer path).
- **0.3 (surface probe)** Determine whether web-agent Concierge sessions emit
  `PostToolUse:Skill` at all (grep `apps/web-platform/server/` Agent-SDK `options.hooks`
  registration + ADR-070). Records CLI-first vs CLI-intrinsic for the deferral issue.
- **0.4** Read the templates: `phase-surface-hint.sh` (+`.test.sh`),
  `pencil-collapse-guard.sh:42-59` (path containment), `scripts/generate-kb-index.sh`
  frontmatter idiom (`c==1` at :138-141, block-start at :176, continuation at :144).

### Phase 1 — The hook (`.claude/hooks/skill-context-queries.sh`)
jq + bash only. Structure mirrors `phase-surface-hint.sh`:
- `set -uo pipefail`; **`set -e` OFF** + `trap 'exit 0' ERR`; **exit 0 on every path**
  (non-zero SILENTLY DROPS additionalContext). Kill-switch `SOLEUR_DISABLE_CONTEXT_QUERIES=1`;
  test seam `CONTEXT_QUERIES_REPO_ROOT`.
- **Fast-path:** immediately `grep -q '^context_queries:' "$SKILLMD"` and **exit 0
  emitting nothing** if absent — the ~89 no-op skills must pay no jq/canonicalize/git/glob
  cost. (Requires resolving `$SKILLMD` first — cheap: sanitize name, stat the file.)
- Read `tool_input.skill` via `jq -r` (never interpolate — P1-2). Strip prefix with the
  **anchored** `${SKILL#soleur:}` (not `sed`/mid-string). Reject residual not matching
  `^[a-z0-9-]+$` (rejects other-plugin `:`-namespaced + metacharacters) → exit 0.
- Resolve `plugins/soleur/skills/<name>/SKILL.md`; `realpath` must stay within
  `plugins/soleur/skills/` and be a regular non-symlink file → else exit 0. (Model-
  controlled name → path is a NEW trust boundary phase-surface-hint lacks.)
- **Parse `context_queries` by reusing the FULL `generate-kb-index.sh` idiom** (inline
  `[a,b]` + block sequence + quote-strip) — NOT a stricter block-only subset (that
  silently parses valid inline YAML to zero = the parse-to-empty trap). Prefer extracting
  a shared `parse_frontmatter_list` helper into `.claude/hooks/lib/` used by both callers;
  else copy the idiom faithfully. If `context_queries:` is **present but parses to zero /
  is unparseable**, emit a skip note (`declared but unparseable`) — never silent.
- **Containment (primary = git-tracked):** per query require `knowledge-base/` prefix,
  reject `..`/absolute; `realpath` each match, confirm under `knowledge-base/` (trailing-
  sep guard), reject symlinks (`[[ -L ]]`), then `git -C "$repo_root" ls-files
  --error-unmatch "$rel"` (rejects symlink-escape AND untracked in one gate). Use a
  **stable repo root** (envelope/`--git-common-dir`), not ambient CWD. Any failure →
  **skip that query, continue** (guarded so it never aborts).
- **Globs:** expand with nullglob; **sort matches (deterministic)**; cap at `MAX_GLOB`
  (flood guard). Invariant recorded in ADR: **a must-present artifact is declared as an
  explicit literal path, never relied on through a glob** (glob eviction under the cap is
  order-dependent and would break #5990's guaranteed-presence need).
- **Emit** a Read-directive naming each resolved artifact + a note:
  `[context_queries] Read these committed artifacts before proceeding: <p1>, <p2>. (skipped: <q> — <reason>)`
  — emit the **skipped** part only when ≥1 declared query failed; emit nothing at all when
  **zero queries were declared** (the fast-path already exited). Envelope via `jq -n --arg`.

### Phase 2 — Register the hook
Add to `.claude/settings.json` as the topology 0.1 selected (default: a **sibling `Skill`
PostToolUse matcher block** — independently enable/disable-able from phase-surface).

### Phase 3 — Pilot frontmatter
Add to `plugins/soleur/skills/frontend-design/SKILL.md` frontmatter:
```yaml
context_queries:
  - knowledge-base/marketing/brand-guide.md
```

### Phase 4 — Tests (`.claude/hooks/skill-context-queries.test.sh`)
Crafted-envelope tests mirroring `phase-surface-hint.test.sh` (behavior + consistency +
negative). **Fixture discipline:** run from a **throwaway `git init` tmp repo with
committed fixtures** (the `git ls-files` gate requires tracked files; ambient-CWD/non-git
tmp would make the happy path unpassable — reconciles Kieran §1 with the CWD-isolation
learning). One consistency test: the real pilot `frontend-design` SKILL.md parses to ≥1
query that resolves to a git-tracked file. See Test Scenarios.

### Phase 5 — ADR-086 + C4
Author `ADR-086` via `/soleur:architecture`; edit `model.c4` (add `hooks -> kb`; correct
Hook-Engine description). Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

### Phase 6 — Verify
Hook test green; `components.test.ts` green; C4 tests green; `skill-security-scan` on the
new hook (TR5); route PR review through `security-sentinel` + `observability-coverage-reviewer`.

## Files to Create
- `.claude/hooks/skill-context-queries.sh`
- `.claude/hooks/skill-context-queries.test.sh`
- `.claude/hooks/lib/parse-frontmatter-list.sh` *(if the shared-helper extraction is clean; else fold into the hook)*
- `knowledge-base/engineering/architecture/decisions/ADR-086-declarative-skill-context-injection.md`

## Files to Edit
- `.claude/settings.json` — register the hook under a `Skill` PostToolUse matcher.
- `plugins/soleur/skills/frontend-design/SKILL.md` — add `context_queries` (pilot).
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `hooks -> kb` edge + Hook-Engine description.
- *(optional)* `scripts/generate-kb-index.sh` — if the parser is extracted to the shared helper, point this caller at it too.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **AC1** `skill-context-queries.sh` exists; `bash -n` clean; `set -e` off + `trap 'exit 0' ERR`; exits 0 on every crafted input.
- [ ] **AC2 (TR2 — fail-open)** malformed frontmatter, unparseable/empty `context_queries`, missing artifact, traversal query, untracked file, and metacharacter skill name **each** → exit 0, skill unaffected (never blocked); a bad query in skill A never affects skill B.
- [ ] **AC3 (real pilot, pointer)** envelope `{tool_input:{skill:"soleur:frontend-design"}}` → additionalContext contains a **Read-directive naming `knowledge-base/marketing/brand-guide.md`** (no fixture escape hatch; asserts the real pilot's runtime behaviour).
- [ ] **AC4 (containment)** a query resolving outside `knowledge-base/` (traversal or symlink) is rejected + skipped; no out-of-tree path emitted.
- [ ] **AC5 (committed-only)** an on-disk-but-untracked file is not emitted (`git ls-files` gate).
- [ ] **AC6 (no-op fast-exit)** a skill with **no `context_queries` key** → exit 0, **no additionalContext**, and runs **no** jq/git/glob/realpath work (verified via the fast-path).
- [ ] **AC7 (namespace reject)** `commit-commands:commit` / other-plugin names → exit 0, nothing emitted.
- [ ] **AC8 (pilot frontmatter safe)** `frontend-design/SKILL.md` carries `context_queries`; `components.test.ts` passes (no unknown-key rejection; description untouched).
- [ ] **AC9 (composition, conditional on 0.1)** per the 0.1-selected topology, the registered hook delivers its additionalContext **without suppressing** phase-surface's (asserted against the live spike outcome, not per-hook isolation).
- [ ] **AC10 (ADR)** ADR-086 records the timing invariant (headline), rejected alternatives, the security model, the `## Consequences` consumer constraints (content-trust≠path-trust; must-present=literal-path), and the CLI-first surface split.
- [ ] **AC11 (C4)** `model.c4` has `hooks -> kb` + corrected description; `c4-code-syntax.test.ts` + `c4-render.test.ts` pass.
- [ ] **AC12 (security scan)** `skill-security-scan` on the hook → LOW-RISK or REVIEW (TR5).
- [ ] **AC13 (kill-switch)** `SOLEUR_DISABLE_CONTEXT_QUERIES=1` → exit 0, no emission.
- [ ] **AC14 (pilot consistency)** the real `frontend-design` `context_queries` parses to ≥1 query resolving to a git-tracked KB file.

### Post-merge (operator)
- None. Fully automatable in-session.

## Domain Review

**Domains relevant:** Engineering. (Product/UX: NONE — no UI-surface file. Legal/GDPR: load-only, no egress — see note.)

### Engineering (CTO — Phase 2.5 + devex plan-review)
**Status:** reviewed. Endorsed lazy-per-skill (headline = post-dispatch timing). Surfaced
the two HIGH risks that drove the pointer-only flip's original inline concerns; devex pass
added: fast-path for the ~89 no-op skills, reuse the full parser (parse-to-empty trap),
"operator-visible" is an overclaim (`additionalContext` is model-facing), and the CLI/web
split is a real operator-facing inconsistency to own now. No capability gaps.

### Plan-review panel (6 agents) — consolidated
- **DHH + code-simplicity (simplification):** cut inline → **pointer-only**; drop sentinel + fleet lint. *(applied)*
- **spec-flow (flow):** forcing fact (36KB pilot ⇒ pointer); no-op-path AC; scope zero-resolve note to N>0; parse-to-empty silent path; AC3 real-pilot honesty; combined-cap. *(applied)*
- **Kieran (correctness):** `soleur:` runtime prefix + `${SKILL#soleur:}`; git-init fixture repo (gate needs tracked files); AC8 conditional; `timeout`-on-a-function is illusory (moot under pointer-only); citation ranges. *(applied)*
- **architecture-strategist (structural):** C4 edge correct+complete (description already-falsified pre-existing debt); sorted globs + must-present=literal-path invariant; content-trust≠path-trust as ADR `## Consequences`; verify web emits PostToolUse:Skill; AP-006 upheld. *(applied)*

### Product/UX Gate
Not applicable — no `components/**/*.tsx`, `app/**/page.tsx|layout.tsx`; no user-facing surface. Tier: NONE.

## GDPR / Compliance note (Phase 2.7)
Load-only: reads **committed, curated** `knowledge-base/` artifacts and *names* them to the
agent (which reads them via its normal channel). No new egress, no new sub-processor, no
regulated-data schema/route/migration. The egress-precedence CLO gate (redaction #5987
precedes egress) is satisfied — this is not an egress feature. Agent-authored PII payloads
(`taste-profile`, #5990) are that issue's concern. `gdpr-gate` invoked on the single-user
trigger; expected: no critical findings.

## Architecture Decision (ADR/C4)

### ADR
**ADR-086 — Declarative skill context-injection via a lazy PostToolUse:Skill hook**
(provisional ordinal; 085 is current max — re-verify next-free at ship). Records:
- **Headline invariant:** PostToolUse fires post-dispatch → the hook cannot block a skill →
  TR2's "fail-closed all ~90 skills" is impossible by construction. Never move to PreToolUse.
- **Decision + `## Alternatives Considered`:** lazy hook chosen; eager SessionStart rejected
  (bloat, compliance-loader entanglement, TR2-default); extend-phase-surface rejected (SRP/trust).
- **Delivery = pointer, not inline** (content re-enters via the agent's normal Read trust channel).
- **`## Consequences` — standing constraints on ALL future `context_queries` consumers** (outlives #5990):
  - **content-trust ≠ path-trust:** the mechanism guarantees committed + path-contained, NOT
    that the *content* is trustworthy. A skill pointing `context_queries` at agent-authored /
    agent-writable content (e.g. #5990 `taste-profile`) must handle content-trust itself.
  - **must-present = literal path:** an artifact that must reliably load is declared as an
    explicit path, never via a glob (glob eviction under `MAX_GLOB` is order-dependent).
- **Surface split:** CLI-only accepted as a **time-boxed** cost; web-parity tracked (0.3 records CLI-first vs CLI-intrinsic).
- **0.1 fallback tradeoff** (single-emitter re-entangles trust models) if last-writer-wins.
- Upholds **AP-006** (committed-only, rejects `~/.gstack`), AP-010, AP-011.

### C4 views
Read all three `.c4` files. Enumeration: no new external actor/system/store; the only
change is the `Hook Engine` (`hooks`) now **reads** the `Knowledge Base` (`kb`) — an edge
`model.c4` lacks (it has only `hooks -> claude`, `skills -> kb`, `agents -> kb`).
**Edit:** add `hooks -> kb "Reads context_queries artifacts (skill-scoped injection)"`;
correct the Hook-Engine `description` (guard-only text is **already** falsified today by
phase-surface + pencil-collapse — pre-existing debt this PR fixes; the ADR must not imply
guard-only was ever accurate). `hooks` + `kb` already in the container + component views —
edge renders without a new `include`. `model.c4:41` (web `api` in-process hooks) left
unedited **on purpose** — it correctly encodes "CLI reads kb, web does not (yet)". Run c4 tests.

### Sequencing
Decision true at merge. ADR authored in-PR (AP-011), not deferred.

## Observability

```yaml
liveness_signal:
  what: N/A (synchronous per-invocation hook; no background process)
  configured_in: .claude/settings.json (PostToolUse:Skill)
error_reporting:
  destination: in-band additionalContext note ("[context_queries] Read …; skipped: <q> (<reason>)"), emitted whenever ≥1 DECLARED query fails (scoped to N>0 — a no-declaration skill emits nothing)
  fail_loud: false by design (fail-OPEN, TR2)
  visibility: MODEL-visible (delivered as a <system-reminder>), NOT rendered to the operator's terminal. The note is phrased as an instruction the agent must surface; the operator sees it only if the agent relays it. Layer cited: in-band → model/transcript (hr-observability-layer-citation). True operator-facing discoverability of author-time misconfig = commit-time (the pilot consistency test AC14) + the consuming skill echoing its loaded-context status in user-facing output.
failure_modes:
  - {mode: unparseable/empty context_queries, detection: in-band "declared but unparseable" note, alert_route: in-band}
  - {mode: missing/untracked/out-of-tree query, detection: in-band "skipped: <q> (<reason>)", alert_route: in-band}
  - {mode: metacharacter/traversal skill name, detection: rejected by ${SKILL#soleur:}+^[a-z0-9-]+$; exit 0 no injection no exec, alert_route: asserted by test}
logs:
  where: none persisted (stateless hook); the additionalContext IS the record
discoverability_test:
  command: "bash .claude/hooks/skill-context-queries.test.sh   # crafted envelopes, git-init fixture repo, NO ssh — developer-facing"
  expected_output: "all cases exit 0; skip/unparseable notes present; real pilot emits a Read-directive naming brand-guide.md"
```

## Test Scenarios
Run from a throwaway `git init` fixture repo (committed fixtures) via `CONTEXT_QUERIES_REPO_ROOT`.
1. Real pilot `soleur:frontend-design` → Read-directive names brand-guide.md (AC3).
2. Malformed frontmatter → exit 0, no crash (AC2).
3. **Present-but-unparseable `context_queries`** (flow-form the parser can't read, if not reused) → skip note, not silent (AC2). *(If the full idiom is reused, inline `[a,b]` resolves normally — test both.)*
4. Traversal query `../../etc/passwd` → rejected, skipped (AC4).
5. Symlink under `knowledge-base/` → outside → realpath+`-L` reject (AC4).
6. Query matches nothing → skip note (AC2).
7. On-disk-but-untracked file → not emitted (AC5).
8. Metacharacter/adversarial name (`soleur:work";injected$(touch /tmp/pwn)`) → sanitized, exit 0, no exec, no leak (AC2).
9. **No `context_queries` key** → exit 0, no emission, no git/glob work (AC6, fast-path).
10. `SOLEUR_DISABLE_CONTEXT_QUERIES=1` → exit 0, no emission (AC13).
11. Other-plugin namespaced skill → exit 0, nothing (AC7).
12. Glob query → sorted, `MAX_GLOB`-capped, deterministic order (globs).
13. Duplicate query paths → deduped (no double-emit).
14. Blast-radius isolation: skill A bad query does not affect skill B (AC2).

## Risks & Mitigations
- **R1 content prompt-injection (residual, consumer-owned).** Pointer-only removes the
  hook-injected-content surface, but a Read of an agent-authored `taste-profile` (#5990)
  still lands untrusted content in context. **content-trust ≠ path-trust** → an ADR
  `## Consequences` constraint; #5990 sanitizes its own content; PR review via `security-sentinel`.
- **R2 path traversal / secret exfil** (single-user vector). `knowledge-base/` prefix +
  realpath trailing-sep + symlink `-L` reject + `git ls-files --error-unmatch` primary gate;
  reject `..`/absolute; tests (AC4/AC5); `skill-security-scan` (AC12). Precedent `pencil-collapse-guard.sh:42-59`.
- **R3 model-controlled skill name → path.** `${SKILL#soleur:}` anchored strip + `^[a-z0-9-]+$`
  + realpath-contain under `plugins/soleur/skills/` + `jq --arg` (P1-1/2/3).
- **R4 fail-closed regression.** `trap 'exit 0' ERR` + exit-0-every-path; PostToolUse post-dispatch
  timing → cannot block; guard every `jq`/`git` with a fallback (no abort under `set -uo pipefail`).
- **R5 parse-to-empty silent no-load.** Reuse the FULL parser (inline+block); a present-but-
  unparseable declaration emits a skip note; AC14 asserts the pilot parses ≥1.
- **R6 glob nondeterminism vs guaranteed presence.** Sorted globs + must-present=literal-path invariant (ADR).
- **R7 two-hook composition / shared 10K cap.** Phase 0.1 spike (concat vs clobber; per-hook vs
  aggregate cap). Pointer payload is tiny so cap-collision is largely moot; sibling matcher block.
- **R8 surface capability gap (CLI vs web).** Known, tracked; web-parity issue filed now with the
  user-facing symptom; 0.3 records CLI-first vs CLI-intrinsic; ADR names it time-boxed.
- **R9 fast-path tax.** Every Skill call runs a 2nd hook; `grep -q '^context_queries:'` early-exit
  keeps the ~89 no-op skills near-free.

## Deferrals (tracking issues to file at ship)
- **Web-platform in-process parity** (mirror `context_queries` into the web-agent Agent-SDK
  `options.hooks`, alongside `phase-surface`) — file NOW with the user-facing symptom; records the
  0.3 finding (CLI-first vs CLI-intrinsic). #5990 gates on this if `taste-profile` is web-relevant.
- **Inline "guaranteed-presence" delivery** — only if a consumer (#5990) proves a directed Read is
  insufficient; then re-introduce bounded inline. YAGNI until demonstrated.
- **Facet/query language** (tag/category kb-search-style) — literal paths + globs suffice today.

## Open Code-Review Overlap
**None.** Queried all 61 open `code-review` issues (2026-07-05) for `skill-context-queries`,
`settings.json`, `frontend-design`, `model.c4`, `context_quer`, `phase-surface` — zero hits.

## Sharp Edges
- **No `yq`/python in the hook** — reuse the full `generate-kb-index.sh` awk idiom (`c==1` @:138-141,
  block-start @:176, continuation @:144); handle inline `[a,b]` + block, not a stricter subset.
- **exit code = fail-open contract:** any non-zero exit SILENTLY DROPS additionalContext. `set -e` OFF; `trap 'exit 0'`; guard every `jq`/`git`.
- **`${SKILL#soleur:}` anchored strip**, never `sed`/mid-string (a crafted `x-soleur:y` would be mishandled).
- **`git ls-files` needs `git -C "$repo_root"`** + tracked fixtures → tests run in a `git init` fixture repo, resolved from a stable repo root (not ambient CWD).
- **`git ls-files` is the primary containment gate** (rejects symlink-escape AND untracked); realpath+`-L` are belt-and-braces.
- **No `timeout`-on-a-shell-function** (it needs an external cmd; would be illusory) — pointer-only has no read loop, so `MAX_GLOB` is the only bound needed.
- **`additionalContext` is model-visible, not operator-visible** — never claim otherwise.
- **HARD BOUNDARY — do NOT touch `session-rules-loader.sh`** (SOC2 compliance loader).
- **ADR ordinal provisional** — ship re-verifies next-free vs `origin/main`.

## Institutional Learnings Applied
- `2026-06-30-posttooluse-skill-additionalcontext-is-the-autonomous-safe-phase-injection-vehicle.md` — PostToolUse:Skill fires in interactive + one-shot + subagents.
- `2026-03-04-sessionstart-hook-api-contract.md` / hooks `README.md` — additionalContext envelope + exit-code semantics.
- `2026-03-20-cwe22-path-traversal-canusertool-sandbox.md` + `2026-04-07-symlink-escape-recursive-directory-traversal.md` — resolve+trailing-sep+empty-string guard; skip symlinks.
- `2026-03-18-stop-hook-jq-invalid-json-guard.md` — guard every jq.
- `2026-06-12-hook-test-passes-on-worktree-fails-on-main-cwd.md` — controlled test CWD.
- `2026-05-12-agents-md-trim-loader-class-fit-verification.md` — do not entangle the compliance loader.
