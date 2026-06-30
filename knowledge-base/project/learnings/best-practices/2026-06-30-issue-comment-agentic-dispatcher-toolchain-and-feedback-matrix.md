# Learning: `issue_comment` agentic-recovery dispatcher — install the gate's toolchain, and make the feedback matrix exhaustive

category: best-practices
module: .github/workflows, constraint-scaffold

## Problem

PR #5803/#5804 wired `.github/workflows/fix-constraints.yml` (#5791): an `issue_comment`-triggered
GitHub Actions workflow that, on an authorized PR comment `/soleur fix constraints`, dispatches
claude-code-action to fix a tripped constraint-gate and push to the PR head. The first cut passed
actionlint + all static ACs and looked complete, but multi-agent review surfaced two classes of
defect that green CI + the author's own reasoning both missed:

1. **The verify step's gate could never run.** The `fix` job did `gh pr checkout` → dispatch agent →
   re-run `apps/web-platform/scripts/constraint-gates.sh` (verify-before-push) → push. But the job
   had **no `Setup Bun` + `bun install`** step, and the gate's runner fails closed (`exit 1`) when
   `node_modules/.bin/depcruise` is absent. On a stock `ubuntu-latest` runner there is no `bun` and
   no `node_modules`, so the verify step always returned rc=1 → the push (gated on `rc==0`) never
   fired → the feature's primary happy path ("Recovered: pushed") was **structurally unreachable**.

2. **Two authorized-founder paths silently re-created the very deadlock the feature exists to kill.**
   The plan's `## User-Brand Impact` promised "every authorized dispatch posts a comment," but:
   - A **read-only collaborator** (passes `author_association ∈ {OWNER,MEMBER,COLLABORATOR}` but fails
     the `admin|write` check) hit a silent path: every fix step gates on `perm.ok=='true'`, so they
     all skip, the fix job completes **`success`**, and `notify-on-skip` (gated `result != 'success'`)
     therefore does **not** fire. Zero feedback.
   - A **near-miss command** (`/soleur fix constraints ` + trailing space, `/Soleur…`, trailing
     period) failed the exact-match preflight gate — AND the notify safety-net used the *same* exact
     string, so the fat-fingering founder got total silence.
   - A **rejected push** posted a false "Recovered … pushed ()" because the outcome comment keyed off
     the pre-push `verify` outputs, not the push result.

## Solution

**Toolchain:** an `issue_comment` (or any event-triggered) workflow that **re-runs a repo-local gate
whose runner depends on installed dependencies** MUST install that toolchain itself — do not assume
the runner image has it, and do not depend on the dispatched agent provisioning it. Mirror the gate's
own workflow: here, `Setup Bun (oven-sh/setup-bun, bun-version-file)` + `bun install --frozen-lockfile`
after `gh pr checkout`, before the agent step (the agent needs depcruise to see the failure too).

**Feedback matrix:** design it as **exactly one comment per case**, and enumerate every case before
trusting it. The trap is that GitHub Actions job `result` collapses three distinct outcomes:
- a job whose steps all **skipped** (e.g. a permission gate failing mid-job) is `success`, not skipped;
- a job **skipped by its `needs`/`if`** (preflight gated it out) is `skipped`;
- a hard step error is `failure`.

So `notify-on-skip` gated on `result != 'success'` both (a) misses the perm-skip-leaves-`success`
silent path and (b) would double-post on a `failure` the in-job outcome comment already handled. The
matrix that yields one honest comment per case:
- in-job **dedicated comments** for the cases the job is responsible for: insufficient-permission
  (gated `always() && steps.perm.outputs.ok == 'false'`), fork-PR, and the outcome comment;
- outcome comment gated on `steps.verify.outcome == 'success'` (only when the gate actually re-ran),
  with a **distinct "push rejected" arm** requiring a non-empty pushed SHA (never a false success);
- a `failure() && steps.verify.outcome != 'success'` **catch-all** for hard errors before verify ran;
- `notify-on-skip` gated on `needs.fix.result == 'skipped'` (NOT `!= 'success'`) so it fires only for
  the preflight-gated-out + near-miss cases and never double-posts.

**Near-miss without leaking:** keep the strict exact-match `==` on the **privileged** preflight/fix
path (security trade-off), but loosen the **notify-on-skip** command condition to
`contains(github.event.comment.body, '<command>')`. Because notify-on-skip is already gated on
`author_association`, a fuzzy match there gives an authorized fat-fingerer a "use the exact command"
nudge **without** leaking command existence to unauthorized commenters.

## Key Insight

An event-triggered agentic workflow has two contracts that static lint + a single happy-path mental
model do not exercise: (1) it must **provision the toolchain its own verify/gate step depends on**
(the runner is bare), and (2) its **feedback matrix must be exhaustive over the GitHub-Actions
job-result trichotomy (`success`/`skipped`/`failure`)** — a `result != 'success'` notify gate silently
misses the all-steps-skipped-but-job-`success` path, which for a recovery dispatcher *is* the deadlock
it exists to remove. Enumerate the case × job-result matrix and assert one comment per case; let
`user-impact-reviewer` (single-user-incident threshold) and `architecture-strategist` walk it — they
catch both classes where the author and green CI do not.

## Critical security finding — the multi-agent review MISSED the structural untrusted-checkout class (held PR #5804 → redesign #5814)

The bigger lesson: **an `issue_comment` (or `pull_request_target` / `workflow_run`) workflow that checks out PR-head code AND executes it (`bun install` postinstall, the PR's own scripts, an agent operating on PR files) inside a job holding secrets + a write token is a CRITICAL `actions/untrusted-checkout-toctou` pattern — and author-association / collaborator-permission / head==base gates do NOT clear it.** Those gates bound *who* triggers it; CodeQL fires on the *structural sink* (privileged trigger → untrusted-derived code runs with secrets present).

CodeQL caught it (3× `actions/untrusted-checkout-toctou/critical`); the 6-agent LLM review did NOT — security-sentinel verified the fork-push block + the perm gate + credential isolation, but never asked "is running untrusted PR code with secrets in a privileged trigger itself the vuln?" **When reviewing any workflow on a secret-bearing privileged trigger that checks out + runs PR-derived code, the security-review spawn prompt MUST name the `untrusted-checkout-toctou` / untrusted-code-execution-with-secrets class explicitly** — and treat CodeQL's `actions/*` queries as the deterministic backstop (run/anticipate them; don't let the LLM review stand alone for this class).

Targeted hardening does NOT clear the rule (SHA-pin closes the TOCTOU race but not the execution-with-secrets; `--ignore-scripts` kills postinstall but the agent must still run the PR's gate script). The fix is architectural: a two-stage `pull_request` (untrusted, no write token) → `workflow_run` (privileged, `git apply`s a validated patch artifact — data, not code execution) split, bot-branch + follow-up PR recovery (never push to the contributor head), and a capped/rotatable per-tenant API key as the one unavoidable secret in the untrusted stage. Full redesign: #5814.

Process corollary: a critical CodeQL `actions/*` finding can be **masked** by a separate repo misconfiguration. Here CodeQL "default setup" was enabled alongside the committed advanced `codeql.yml`, so every SARIF upload was rejected repo-wide ("analyses from advanced configurations cannot be processed when the default setup is enabled") — main's CodeQL was red too. Disabling default setup (operator-authorized) both unblocked the repo AND let the real 3 critical alerts surface. A green-because-the-uploader-is-broken CodeQL is worse than a red one.

## Session Errors

1. **AC `grep -c 'pull_request_target' == 0` false-matched the workflow's own security comments.** The
   workflow legitimately names `pull_request_target` in comments explaining why it is avoided; the
   literal-count AC tripped on the prose. **Recovery:** reworded prose to the hyphenated
   `pull-request-target` (reads identically, doesn't match the underscore trigger-keyword grep).
   **Prevention:** known class — anchor forbidden-literal greps on the syntactic construct, or reword
   the explanatory comment to drop the literal. See `2026-06-18-in-code-comment-rewrites-self-citations-and-forbidden-literal-quotes-are-fragile.md`
   and `2026-06-17-...ac4-grep-matches-cutover-comments.md`. One-off here; rule already exists.
2. **parity.test.sh #5 caught two wording drifts** between the repo-root dispatcher and the tenant
   template (agent-prompt phrasing, a `(#5791)` in the commit message). This was the drift guard
   working as designed. **Recovery:** harmonized the repo-root copy to the generic template wording.
   **Prevention:** when authoring two intentionally-divergent copies (dogfood vs tenant), write the
   shared body once and diff early; the parity gate is the backstop, not the first line.

## Tags

category: best-practices
module: github-actions, constraint-scaffold, agentic-workflows
related: [[2026-06-18-in-code-comment-rewrites-self-citations-and-forbidden-literal-quotes-are-fragile]], [[2026-05-07-comment-coupled-workflow-invariants-need-runtime-assertion]]
