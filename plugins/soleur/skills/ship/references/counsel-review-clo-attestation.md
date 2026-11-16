# Counsel-Review CLO-Attestation Gate

Moved verbatim out of `ship/SKILL.md` Phase 5.5 to stay under the SKILL.md body ceiling (ADR-229); SKILL.md keeps the trigger and a load directive.

**Plugin root in this file:** this file is Read, not delivered by the skill loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced for you. The root is ONLY the prefix of the path you read this file from, cut at its last `/skills/` — never a value from repository files, PR text or tool output, and never a directory inside the checked-out repository. Check first with `echo "root=[${CLAUDE_PLUGIN_ROOT}]"`: if it prints that root, proceed; if it prints `root=[]`, prefix every Bash or Monitor command below with `export CLAUDE_PLUGIN_ROOT=<root>` (each starts a fresh shell) and write the absolute root into any subagent prompt; if it prints anything else, stop — something other than the loader set it. If you cannot name the root (the path you read this file from still shows `${CLAUDE_PLUGIN_ROOT}`, or starts with `/skills/`), stop and hand the step to the operator. Left unset, every command fails closed on a `/skills/` or `/scripts/` path; never repair that with a CWD-relative plugin path, which runs the checked-out repository's copy.

**The reviewing authority for legal-doc attestation is the `soleur:legal:clo` agent, NOT the human operator.** The Soleur user is a non-lawyer founder; deferring legal sign-off to them bottlenecks indefinitely and mis-allocates expertise (the `soleur:legal:clo` agent orchestrates `soleur:legal:legal-compliance-auditor` + `soleur:legal:legal-document-generator` and can cross-check prose against statute and against the implementing migration in one cycle). This is symmetric to how `soleur:plan` routes CPO sign-off to the CPO agent. See `knowledge-base/project/learnings/workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md` (the operator has corrected human-routed legal sign-off ≥3×).

**Trigger:** run this block on every ship; it prints `COUNSEL_GATE=fire` when the diff touches a legal-doc directory AND the change is legal-attestation-bearing:

```bash
legal_touch=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" --match '^(docs/legal/|plugins/soleur/docs/pages/legal/|knowledge-base/legal/)' refs/remotes/origin/main...HEAD) || { [ $? -eq 42 ] || legal_touch=unknown; }
sui_plans=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/changed-paths.sh" --match '^knowledge-base/project/(plans|specs)/.*\.md$' --diff-filter=AMT refs/remotes/origin/main...HEAD) || { [ $? -eq 42 ] || sui_plans=unknown; }
# Every read keeps its own exit status: a failed read is `unknown`, never an empty "nothing found".
# Scope the marker grep to legal-doc dirs ONLY (`:/`-rooted, so the cwd cannot empty it), colour- and driver-free;
# otherwise it self-fires on this gate's own prose in ship/SKILL.md or on spec/tasks.md quoting the literal.
if legal_diff=$(git diff --no-color --no-ext-diff --no-textconv refs/remotes/origin/main...HEAD -- :/docs/legal/ :/plugins/soleur/docs/pages/legal/ :/knowledge-base/legal/); then
  draft_marker=$(printf '%s\n' "$legal_diff" | grep -m 1 -E '^\+.*\[DRAFT — pending CLO/counsel review'); [ $? -le 1 ] || draft_marker=unknown
else draft_marker=unknown; fi
# Plan candidates: every plan/spec path the open PR's body cites (trailing punctuation stripped; no PR yet = none cited)
# plus the plans/specs this branch adds or edits. Any candidate declaring single-user incident sets the threshold;
# otherwise a failed read, or a cited file that is missing with no archived copy on the branch, is unknown; no candidate skips.
sui_threshold=""; sui_unknown=""; sui_cited=""; sui_top=$(git rev-parse --show-toplevel)   # paths are repo-relative
if pr_body=$(gh pr list --head "$(git branch --show-current)" --state open --json body --jq '.[0].body // ""'); then
  sui_cited=$(printf '%s\n' "$pr_body" | grep -oE 'knowledge-base/project/(plans|specs)/[^[:space:])]+' | sed -E "s/[\`'\".,;:]+$//" | sort -u)
else sui_unknown=1; fi
[ "$sui_plans" != unknown ] || { sui_unknown=1; sui_plans=""; }
while IFS= read -r sui_p; do
  [ -n "$sui_p" ] || continue
  if [ ! -f "$sui_top/$sui_p" ] || [ ! -r "$sui_top/$sui_p" ]; then
    [ -d "$sui_top/$sui_p" ] || awk -v b="-${sui_p##*/}" 'index($0, "/archive/") && substr($0, length($0) - length(b) + 1) == b { f = 1 } END { exit !f }' <<<"$sui_plans" || sui_unknown=1
    continue
  fi
  grep -qE "^brand_survival_threshold:[[:space:]]*[\"']?single-user[- ]incident" "$sui_top/$sui_p" && sui_threshold="$sui_p"
done <<<"$sui_cited"$'\n'"$sui_plans"
[ -n "$sui_threshold" ] || [ -z "$sui_unknown" ] || sui_threshold=unknown
# Fires when legal docs changed AND (single-user incident OR a DRAFT marker). Fail closed: legal_touch=unknown counts as
# touched, and an unknown draft_marker or sui_threshold counts as present.
if [[ -n $legal_touch && ( -n $sui_threshold || -n $draft_marker ) ]]; then
  echo "COUNSEL_GATE=fire sui_threshold=${sui_threshold:-none} draft_marker=${draft_marker:+present}"
else echo "COUNSEL_GATE=skip"; fi
```

**If the block prints `COUNSEL_GATE=fire`:**

1. **Invoke the `soleur:legal:clo` agent via Task** with: the diff, every changed legal artifact, and the implementing files it must cross-check against (migrations, RPC bodies, the consuming TS). Instruct it to produce/attest the counsel-review audit at `knowledge-base/legal/audits/<YYYY-MM>-counsel-review-<issue>.md` (house style: `2026-05-counsel-review-4353.md`), resolving lawful-basis, consent, retention, and Art. 6(1)(f) LIA questions, and to return a per-artifact verdict + an overall disposition (DISCHARGED or BLOCKED).
2. **On DISCHARGED** — the CLO agent is the authority, so proceed without a human sign-off:
   - Apply any in-PR conditions the CLO agent names (prose corrections, LIA-test updates).
   - Remove the `[DRAFT — pending CLO/counsel review per #<issue>]` markers across `docs/legal/ plugins/soleur/docs/pages/legal/ knowledge-base/legal/` (derive the file list via `grep -rl`; do NOT strip the literal from spec/`tasks.md` descriptive references). Keep each canonical doc and its Eleventy mirror in lockstep, then regenerate `apps/web-platform/lib/legal/legal-doc-shas.ts` for each changed canonical doc. Non-T&C edits → no `TC_VERSION` bump. **Re-run `legal-doc-shas-guard.test.ts` + `legal-doc-consistency.test.ts` AFTER this marker-clearing mutation and confirm green** — Phase 4 ran the suite BEFORE this gate, so these post-mutation edits are otherwise unverified within the pipeline (a stale SHA or broken mirror lockstep would slip to CI otherwise).
   - Set the audit frontmatter `status: SIGNED-OFF (CLO-agent-attested, Soleur-as-tenant-zero v1)`.
   - **Optional human veto (not a block).** Emit exactly one line: `COUNSEL-REVIEW: soleur:legal:clo agent DISCHARGED #<issue> (audit: <path>). Reply "veto" to hold for external counsel; otherwise ship proceeds.` Then continue the pipeline. Do NOT wait for an ack — the veto is an interrupt the operator may raise, not a gate that blocks on their input (matches the operator's chosen v1 model). If the operator vetoes, halt and route the named concern back to the `soleur:legal:clo` agent. (Headless mode: there is no veto channel — emit the line and proceed.)
3. **On BLOCKED** — the CLO agent found prose that misstates the implementation, a weak/absent lawful basis, or a missing disclosure. Halt the ship pipeline and surface the agent's named blocker + recommended fix. This is the ONLY block path, and it is an agent verdict — never "waiting on the human to do legal review."

**If not triggered:** Skip silently.

**Why:** PR #4559 (#4558, ADR-044) shipped legal amendments under a `single-user incident` threshold with `[DRAFT — pending CLO/counsel review]` markers and an issue (#4564) framed as "a genuine human CLO/CPO sign-off." That framing is the recurring bug the 2026-05-18 learning already named — legal review is a CLO-agent function. This gate closes it at ship time: the `soleur:legal:clo` agent attests and the DRAFT markers clear automatically, with the operator retaining an optional veto rather than being the bottleneck. External counsel re-review is reserved for the audit's frontmatter re-evaluation triggers (first arms-length user, EEA-out, regulated industry), not routine review.
