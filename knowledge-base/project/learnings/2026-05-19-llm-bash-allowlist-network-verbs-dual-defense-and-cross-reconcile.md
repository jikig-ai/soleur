---
date: 2026-05-19
category: best-practices
topic: LLM Bash allowlist with network verbs (curl/dig); cross-reconcile single-agent HIGH
trigger_prs:
  - "#4062 (PR-2: scheduled-follow-through → Inngest cron)"
related_prs:
  - "#3985 (PR-1: scheduled-daily-triage → Inngest cron, the substrate template)"
related_issues:
  - "#4068 (deferred-scope-out: Set.has() SSRF allowlist hardening)"
  - "#3948 (umbrella: TR9 group-(c) agent-loop crons → Inngest)"
related_learnings:
  - "2026-05-07-claude-code-action-boundaries-and-once-schedule-bundle.md (auto-close keyword markdown-blindness)"
  - "2026-05-12-multi-agent-review-cross-reconcile-catches-false-positive-high-findings.md"
  - "2026-03-20-open-redirect-allowlist-validation.md (Set.has() exact-match)"
---

# LLM Bash allowlist with network verbs: dual defense-in-depth + cross-reconcile gate

When an Inngest cron-*.ts function (or any LLM-driven agent) needs to invoke network-egress shell verbs (`curl`, `dig`, `wget`) inside `--allowedTools`, the security posture is a tier-2 substrate decision binding all future cron-* migrations in the TR9 umbrella. PR-2 (#4062) was the first instance — PR-1's (`cron-daily-triage`) allowlist had zero network verbs. The right design is:

## The dual-defense-in-depth pattern (load-bearing)

**Layer 1 — In-prompt URL guard (LLM-policed).** The agent prompt forbids targets matching attacker-reachable identifiers. Minimum coverage for the prompt body:
- HTTPS-only mandate
- IPv4 RFC1918: `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `169.254.0.0/16`
- IPv6 unaddressed today (gap surfaced in PR-2 review; deferred to #4068): `::1`, `fe80::/10`, `fc00::/7`, `::ffff:127.0.0.1`
- Cloud metadata hostname form (gap deferred): `metadata.google.internal`
- URL userinfo bypass: `https://internal@evil.example.com`, `https://evil.example.com@internal` (gap deferred)
- DNS rebinding: no prompt-level mitigation possible (gap deferred to Layer 3)
- URL parser inconsistencies: percent-encoded, numeric IP forms (gap deferred)

**Layer 2 — Spawn-env allowlist (mechanical).** `buildSpawnEnv()` pattern from PR-1: only `PATH`, `HOME`, `NODE_ENV`, `ANTHROPIC_API_KEY`, `GH_TOKEN` reach the subprocess. Caps SSRF exfil blast radius — but does NOT prevent exfil of those 5 envs themselves. `ANTHROPIC_API_KEY` and `GH_TOKEN` are both valuable; GH_TOKEN's scope MUST be minimized at the operator level (least-privilege fine-grained PAT, repo-scoped only).

**Layer 3 — Set.has() exact-match server-side validation (mechanical, deferred).** Pre-validate predicate URLs at the handler entry point BEFORE invoking the agent. Parse YAML predicates from open issues; resolve hostnames via `node:net.isIPv4/isIPv6` + `ipaddr.js`; reject non-public; pass the validated set into the prompt as a closed list. Then drop `Bash(curl:*)` / `Bash(dig:*)` from the allowlist entirely — the agent no longer needs network verbs because the validated URLs are pre-bound in the prompt. **This is the only defense robust against prompt injection.** Deferred from PR-2 to #4068 to keep the substrate migration a clean carry-forward.

**`fn-concurrency=1` is NOT SSRF defense.** It bounds invocation RATE (one in-flight at a time), not invocation CONTENTS. The PR-2 plan v1 initially labeled defense-in-depth as "triple"; the 4-agent plan-review reclassified to DUAL (security-sentinel architectural finding F1) with Set.has() as the deferred third leg.

## Auto-close keyword markdown-blindness (load-bearing for comment-writer agents)

GitHub's auto-close regex is `(close[ds]?|fix(e[ds])?|resolve[ds]?)\s+#?\d` — fires anywhere in a comment body (code blocks, blockquotes, prose). For any comment-writer cron-* agent, the prompt MUST forbid all 9 keyword variants:
- imperative: `close #`, `fix #`, `resolve #`
- present tense: `closes #`, `fixes #`, `resolves #`
- past tense: `closed #`, `fixed #`, `resolved #`

Plus the cross-repo form (`closes owner/repo#N`) and URL form (`closes https://github.com/.../issues/N`).

PR-2's initial implementation had 6 of 9 — review caught it. Closing MUST happen via `gh issue close` API call; close-keyword in any comment body is a documented user-incident vector (auto-closes the wrong issue).

## Comment-before-close ordering (load-bearing for auto-close transitions)

For state transitions that BOTH post a comment AND close an issue (Guard A in PR-2: "Verified" comment + close; Guard C: "Maximum polling" comment + close), the prompt directive MUST mandate POST comment FIRST, then close. If close fires before comment and the comment then fails (network, rate-limit, 5xx), the issue is closed without provenance and `--state open` filters subsequent ticks exclude it permanently. Torn-write recovery: when state is "closed" but no provenance comment exists, post the comment now (the close succeeded but comment was lost).

## Cross-reconcile gate: single-agent HIGH vs multi-agent silent

PR-2's review surfaced one P1 from security-sentinel that no other agent (user-impact, data-integrity, pattern-recognition, code-quality) corroborated: "promote Set.has() from deferred to ship-blocker." Cross-reconcile per the SKILL.md sharp edge:

> "When a single agent rates a finding P1/HIGH but no orthogonal agent independently surfaces the same harm, downgrade to advisory or skip."

In PR-2's case:
- security-sentinel: P1 ship-block on SSRF
- user-impact-reviewer: "Accept as v1; confirm #4068 has SLA before merge"
- data-integrity-guardian: "P3, defer to existing #4068"
- pattern-recognition + code-quality: silent on SSRF (focus was structural patterns)

→ 1-of-5 P1 vs 4-of-5 deferral → downgrade. Filed the specific gap list (IPv6, userinfo, rebinding, parser inconsistency, dig unboundedness, GH_TOKEN exfil via curl) into the #4068 issue body so the eventual implementer has the full attack surface enumerated.

**Additional context the agent missed:** the GHA workflow PR-2 REPLACED used bare `Bash` (everything allowed including curl/dig). PR-2's `Bash(gh issue list:*),Bash(gh issue view:*),...,Bash(curl:*),Bash(dig:*),Read,Glob,Grep` is strictly MORE restrictive than GHA baseline. The "widens attack surface from zero network egress" framing was materially wrong. **Always cross-check single-agent HIGH framings against the baseline they're comparing to.**

## `gh label create` exit-code handling (load-bearing for opt-out semantics)

PR-2's `ensure-labels` step.run originally swallowed all exit codes (`child.on("exit", () => resolve())` + `child.on("error", () => resolve())`). Three review agents independently surfaced this (security-sentinel P2, data-integrity-guardian P1, pattern-recognition P2) — strong cross-reconcile signal.

The correct pattern:
1. Capture stderr via `stdio: ["ignore", "ignore", "pipe"]` + `child.stderr?.on("data", ...)`.
2. On non-zero exit, check stderr for `/already exists/i` — that's the steady-state case (idempotent label creation).
3. Any other failure (auth missing, gh binary missing, 5xx) routes through `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry`.

Why this matters: if `silence-followthrough` label create fails silently, the @-mention opt-out branch in the prompt finds no label → user receives unwanted @-mention → irreversibility violation (GDPR Art. 21 right-to-object adjacent).

## Pattern Boundaries for PR-3..N (carry-forward hazards)

PR-2 ships several decisions that are workflow-specific and MUST NOT be copied verbatim to PR-3..N:

- `MAX_TURN_DURATION_MS = 15min` — bound by predicate-bounded wallclock; re-derive per workflow
- `--max-turns 30` — bound by follow-through corpus size; re-derive
- 3 idempotency guards (A/B/C) — bound by 3 state transitions; re-count per workflow
- `Bash(curl:*),Bash(dig:*)` — bound by HTTP/DNS predicates; **OMIT entirely** if no network-verb need
- `cron: "0 9 * * 1-5"` — bound by follow-through SLA semantic; re-derive

Encoded as in-file DO-NOT-COPY block at `cron-follow-through-monitor.ts:57-63` AND plan §Pattern Boundaries.

## Implementation pointers (file:line at PR-2 merge)

- Dual defense Layer 1: `cron-follow-through-monitor.ts:121-128` (in-prompt RFC1918 guard)
- Dual defense Layer 2: `cron-follow-through-monitor.ts:230-238` (`buildSpawnEnv` allowlist)
- Close-keyword forbidden list: `cron-follow-through-monitor.ts:171-186`
- silence-followthrough opt-out + before/after example: `cron-follow-through-monitor.ts:187-202`
- ensure-labels with stderr-aware exit-code handling: `cron-follow-through-monitor.ts:270-365`
- Comment-before-close ordering: Guard A `cron-follow-through-monitor.ts:135-148`, Guard C `cron-follow-through-monitor.ts:159-171`

## Re-evaluation criteria for #4068 (Layer 3)

Promote Set.has() server-side validation from deferred to ship-blocker if ANY of:
1. Prompt-injection attempt observed in production Sentry logs against cron-follow-through-monitor (or any future curl/dig cron-*).
2. Follow-through corpus grows beyond ~10 active issues (broader attack surface).
3. A sibling cron migration (PR-3..N) needs network verbs in its allowlist — Set.has() becomes the shared primitive; PR-2's in-prompt-only path becomes the outlier.
