---
title: "A reproduced symptom does not validate the mechanism you attached to it"
category: integration-issues
module: .claude/hooks / iac-plan-write-guard
date: 2026-07-15
related_issues: [6501]
related_pr: 6485
related_learnings:
  - knowledge-base/project/learnings/2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code.md
  - knowledge-base/project/learnings/2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md
tags: [hooks, debugging, root-cause, sigpipe, pipefail, confound, claude-code-tools]
description: "A confident, mechanism-level diagnosis of iac-plan-write-guard's broken ack bypass (SIGPIPE + pipefail) was reproduced, documented, and wrong. The real cause: the ack is file-scoped in the docs and hunk-scoped in the code. The recorded fix would have changed nothing."
type: best-practices
---

# A reproduced symptom does not validate the mechanism you attached to it

## Problem

`.claude/hooks/iac-plan-write-guard.sh` kept denying plan writes that already carried the documented opt-out:

```
<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
```

A prior session diagnosed it, wrote it into `session-state.md`, and moved on behind a workaround. The recorded diagnosis:

> the check is `echo "$content" | grep -qF '<ack>'` under `set -o pipefail` — `grep -q` exits at the first match and closes the pipe, so on content exceeding the pipe buffer `echo` takes SIGPIPE (141) and `pipefail` propagates it, making the `if` false and skipping the bypass. Net: the more thorough the plan, the less likely its acknowledged opt-out works.

This is a *good* diagnosis. It names a real bash hazard, the code really is `echo | grep -qF` really under `set -euo pipefail`, it explains the symptom, it explains the dose-response ("thorough plans are worse"), and it came with a reproduction: *48 KB plan + exact ack literal → denied; identical small doc → allowed.* It proposed a fix (`grep -qF … <<<"$content"`).

It is also wrong, and the fix would have changed nothing.

The crack was arithmetic: Linux pipe capacity is 64 KB, so a 48 KB write never blocks and never takes SIGPIPE. The blamed size sits *below* the threshold the mechanism requires.

Testing the mechanism directly:

```
size=1KB   ack=early -> BYPASS_OK
size=48KB  ack=early -> BYPASS_OK     <- the size the repro blamed
size=48KB  ack=late  -> BYPASS_OK
size=100KB ack=early -> BYPASS_OK
size=512KB ack=early -> BYPASS_OK
pipeline exit=0
```

The bypass works at every size, ack early or late. SIGPIPE never fires.

## Solution

The real cause is at line 68 — the hook never sees the file:

```bash
content="$(echo "$payload" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null)"
```

On `Edit`, `content` is `new_string` — the inserted **hunk**. The ack lives elsewhere in the plan and is invisible to the check at line 118. On `Write`, `content` is the whole document, ack included, so the bypass works.

**The ack's scope is the file; the check's scope is the hunk.** The hook's own deny message says "add the comment *to the plan*" — the docs describe a file-scoped ack that the code never implements.

Against the real hook:

| # | Call | Ack location | Verdict |
|---|------|--------------|---------|
| 1 | `Write` | in `content` | `allow` |
| 2 | `Edit` | in the FILE, not the hunk | **`deny`** ← the defect |
| 3 | `Edit` | pasted inside the hunk | `allow` (the accidental workaround) |
| 4 | `Write` 48KB | in `content` | `allow` |

Fix in [#6501](https://github.com/jikig-ai/soleur/issues/6501): consult the file on disk, not just the hunk.

**Both original observations were true; the variable between them was misread.** "48 KB plan → denied" and "small doc → allowed" differed in **tool** (`Edit` vs `Write`), not in **bytes**. Size was a confound, riding along because big plans get `Write`-ten once and `Edit`-ed many times. The dose-response that made the story convincing — *thorough plans fare worse* — is real, and has nothing to do with buffers: more refinement means more Edits, and every Edit is a fresh chance to be denied.

## Key Insight

**A reproduction confirms the symptom, not the story you told about it.** This diagnosis had every mark of a sound one — a real hazard, present in the code, explaining the symptom *and* its dose-response, with a repro and a fix. It survived because everything it claimed was checkable and nothing was checked: the SIGPIPE step was reasoned about, never executed.

The specific trap is **plausibility laundering**. `echo | grep -q` + `pipefail` is a genuine bash foot-gun; recognising it feels like recognising the bug. But a hazard being *present* is not it being *triggered*. The mechanism had a quantitative precondition — content must exceed the pipe buffer — and that precondition contradicted the repro's own 48 KB. The evidence to refute it was already sitting in the write-up.

Two cheap checks that would have caught it:

- **Check the mechanism's arithmetic against the repro's own numbers.** 48 KB < 64 KB. The story needed a bigger number than the evidence had.
- **Vary one thing.** The two repro cases differed in *both* size and tool. Any A/B that changes two variables can only tell you something changed.

Related in spirit to [vacuous RED](2026-05-04-vacuous-red-via-shared-fixture-and-toolchain-pinning.md): there, a test passes without the SUT firing; here, an explanation passes without the mechanism firing. Both are green-looking evidence that nothing actually exercised — and both are corollaries of [ad-hoc evidence perishing](2026-07-15-ad-hoc-verification-evidence-is-as-perishable-as-uncommitted-code.md). Written-down prose ages into fact; the crash-proof form of "I diagnosed this" is a failing test, not a paragraph.

## Prevention

- When recording a root cause in `session-state.md` or a learning, **mark the confidence and say what was executed**. "Reproduced the symptom; mechanism inferred, not tested" is honest and warns the next reader. An untested mechanism written in the indicative becomes fact on the next read.
- Before accepting a mechanism with a **quantitative precondition** (buffer size, timeout, row count, rate limit), check the repro's numbers actually clear it.
- A/B a **single variable**. If two cases differ in size *and* tool, the comparison names no cause.
- For hook defects specifically: **drive the real hook with a synthetic payload** (`jq -nc '{tool_name, tool_input}' | bash .claude/hooks/<hook>.sh`). It is seconds of work, exercises the actual code path, and is the difference between a fix and a guess.
- Any hook consuming `.tool_input.new_string` sees a **hunk, not a file**. Any check whose semantics are file-scoped (an ack, a header, a marker) is wrong on `Edit` by construction. Grep the other hooks for this shape.

## Session Errors

- **A confident, reproduced, documented root cause was wrong.** Recovery: falsified the SIGPIPE mechanism across 1KB–512KB, then drove the real hook with synthetic `Write`/`Edit` payloads to isolate the tool as the true variable; filed #6501 with the corrected diagnosis and a note that the recorded fix was a no-op. **Prevention:** this learning — test the mechanism, not just the symptom; check the mechanism's preconditions against the repro's own numbers.
- **The bad diagnosis propagated into `session-state.md`** and would have shipped as institutional knowledge, sending an implementer to apply a fix that changed nothing. **Prevention:** confidence-mark inferred mechanisms at the point of writing.
