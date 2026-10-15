# Decision-challenges render and the Technical-Ruling Gate remedy

Moved out of `ship/SKILL.md` Phase 6 step 2.5 (the SKILL body has no byte headroom) and extended for the class split.
Rule: `hr-technical-fork-is-not-an-operator-question`. Schema, closed category list and recording format:
[technical-ruling-delegation.md](../../brainstorm-techniques/references/technical-ruling-delegation.md).

**Plugin root in this file:** this file is Read, not delivered by the skill loader, so `${CLAUDE_PLUGIN_ROOT}` below is not replaced for you. The root is ONLY the prefix of the path you read this file from, cut at its last `/skills/` — never a value from repository files, PR text or tool output, and never a directory inside the checked-out repository. Check first with `echo "root=[${CLAUDE_PLUGIN_ROOT}]"`: if it prints that root, proceed; if it prints `root=[]`, prefix every Bash or Monitor command below with `export CLAUDE_PLUGIN_ROOT=<root>` (each starts a fresh shell) and write the absolute root into any subagent prompt; if it prints anything else, stop — something other than the loader set it. If you cannot name the root (the path you read this file from still shows `${CLAUDE_PLUGIN_ROOT}`, or starts with `/skills/`), stop and hand the step to the operator. Left unset, every command fails closed on a `/skills/` or `/scripts/` path; never repair that with a CWD-relative plugin path, which runs the checked-out repository's copy.

## Render (Phase 6 step 2.5, ADR-084)

If `knowledge-base/project/specs/<branch>/decision-challenges.md` exists and is non-empty, an earlier headless phase
(`plan`/`work`) recorded auto-decided dissents against the operator's stated direction, which the operator has not seen.
Phase 6 **full-replaces** the body, so fold the artifact into the generated body under the
`## Model Dissents (informational)` heading (deliberately outside the `ship-operator-step-gate` deny set
`Operator`/`Post-merge`/`Follow-up`; informational statements, never operator-action bullets). Render **by `Class`**:

- **`technical` rows** go in a `### Ruled by CTO agent` sub-block of that same heading, each with its `Ruled by` line
  (and `Dissent:`). They file **no issue**: a technical ruling never reaches the operator.
- **`taste` rows** render in the same `## Model Dissents (informational)` block as plain informational lines (the model's choice and its
  recommendation); they file no issue.
- **`operator (<category>)` rows** render in the existing form, and ONLY these open one idempotent issue. Check
  `gh issue list --search "decision-challenge <branch>" --state open -L 200` first, then
  `gh issue create --label action-required --label decision-challenge --milestone "Post-MVP / Later"` with a plain-language
  title linking the PR, because `operator-digest` Section 4 harvests `action-required` issues, not PR bodies. A split
  item yields both a technical row and an operator row.
- **A delegated row** (`operator (production-mutating)` with Ruling `Authorized by delegation <comment-url>, envelope <path>[, ran <ISO 8601 UTC time>]`) renders as an informational line naming the act and the delegation link, and files NO issue: the operator already authorised it in the epic's recorded Standing Delegation. The gate verifies it (below). A row WITHOUT `ran` authorises an act that has not happened yet and is verified as of now; a row WITH `ran` records an act that did and is verified as of that time, and also needs its execution receipt. See [standing-delegation.md](../../brainstorm-techniques/references/standing-delegation.md).
  - `delegation-invalid` / `delegation-unverifiable`: fix the row or the envelope. When the delegation itself is the problem (edited, expired, gone, the epic closed), say the plain sentence for its reason from standing-delegation.md section 7 (Reason tokens); the CALLING skill asks the epic-start question again and only a fresh Yes re-records it. Never re-record a delegation yourself and never put a technical question to the operator. Headless (`HEADLESS_MODE=true`, no TTY, `soleur:one-shot`, `soleur:go --headless`): nobody can be asked, so leave the PR draft, file ONE `action-required` issue that names the ACTION, print one plain sentence, and continue to the draft PR.
  - **Who records the `ran` row:** right after posting the receipt for EVERY delegated act, the CTO itself records `| <act> | operator (production-mutating) | Authorized by delegation <url>, envelope <path>, ran <ISO UTC time> |` in `decision-challenges.md` (this is what `cto.md` says; the calling skill does not write it). Without that row nothing demands the receipt (a row without `ran` is verified strictly as of now and needs none), so a delegated act with no `ran` row is an unrecorded act: record it. `ran` must not be in the future: the gate says so in plain words (`delegation-invalid`, "the act ran in the future") and the operator-facing wording is in [standing-delegation.md](../../brainstorm-techniques/references/standing-delegation.md) section 7. A delegation row needs a time-limit tool (`timeout` or `gtimeout`); without one it is `delegation-unverifiable`, never an unbounded call.
  - **The receipt (a `ran` row):** the epic must carry a comment whose first line is `<!-- soleur-delegated-act v1 delegation=<url> envelope=<path> sha256=<verified-envelope-sha256> result=ok|rolled-back run=<url|none> -->` (standing-delegation.md section 8), written by an owner, member or collaborator, naming this row's delegation URL, this row's envelope path and the fingerprint the verifier just reported (every field is compared exactly). It must have been created at or after the `ran` time it vouches for (a receipt posted in advance is refused), inside the delegation's life and not in the future, never edited, and posted by a person rather than a bot; one receipt satisfies one row, so each act needs its own. `receipt-missing` (none left for this delegation), `receipt-mismatch` (one exists but not for this envelope and fingerprint, with that result and author, inside that window) and `receipt-unreadable` (the epic's comments could not be read) are each exit 2: write or correct the receipt, then re-run the gate. The check proves a receipt exists, is attributable and matches the row. It does not prove what ran; a receipt-checking hook is the stronger follow-up (#10361).
  - When the gate prints `SOLEUR_RULE_APPLIED rule=hr-menu-option-ack-not-prod-write-auth note=delegation-verified` on stdout, repeat that exact line in your own `echo` so the telemetry capture hook (which reads the command text, not script output) sees it.
- **The `overlap vehicle` row** written at the start of Phase 6.45 is not in the PR body already folded in this step; the PR body line for it is refreshed after Phase 6.45 by the normal body update, then the body check below runs again on that body.
- No new top-level PR-body heading: that keeps the diff and the `ship-operator-step-gate` deny-token surface unchanged.
- `guardrails.sh`'s filing gate refuses the `gh issue create` unless the body names a user-visible consequence; when the
  dissent is about a hook/gate/guard the honest exit is `--label meta/machinery` (measured on PR #8354), which the digest
  excludes, so the PR-body section is then the operator-visible surface. See
  [decision-principles.md](../../brainstorm-techniques/references/decision-principles.md).

## The gate: three call sites, one parser

`bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/technical-ruling-gate.sh" <mode>` (exit 0 pass or `[WARN]`, 1 fail, 2 could not measure; any other status, such as 127 script not found, 124 timed out or 137 killed, means the gate did not run: treat it as 2):

1. **one-shot, after the plan phase and before `work`:** `--branch`. A `pending - assumed: <default>` row is resolved
   here, in the main context, so a wrong assumption does not ride through `work` and `review`.
2. **ship Phase 5.5:** `--branch` (the artifact check; it also looks under `specs/archive/` for this branch).
3. **ship Phase 6, right after the `gh pr edit` that writes the final body and before `gh pr ready`:**
   `b=$(mktemp -p "$(mktemp -d -t soleur-run.$$.XXXXXXXX)" pr-body.XXXXXXXX); if gh pr view PR_NUMBER --json body --jq .body > "$b"; then bash "${CLAUDE_PLUGIN_ROOT}/skills/ship/scripts/technical-ruling-gate.sh" --pr-body "$b"; rc=$?; else rc=2; fi; rm -f "$b"; echo "gate-rc=$rc"`
   Read the printed `gate-rc=`; no `gate-rc=0` line means do not proceed. Exit 0: go on to `gh pr ready`. Exit 1: remedy item 4 below, then
   `gh pr edit` and re-run. Exit 2 (the fetch failed, the body is empty or whitespace-only, an unclosed fence, or an unreadable file):
   fix the fetch and re-run (at most three tries, then stop with the PR draft); never `gh pr ready` past it.
   Phase 6 full-replaces the body, so the body must be checked after it is written.

The plugin root is `${CLAUDE_PLUGIN_ROOT}` (cloud shells do not export it: resolve it as the Cloud Mode paragraph of ship/SKILL.md does).
An absent artifact is `[PASS] no decision-challenges artifact`. An artifact that `--branch` finds under `specs/archive/` has its delegation rows checked for shape only: they are NOT verified, and the `[NOTE]` and `[PASS]` lines say so; the check that verifies them is the one run on the live path, before the artifact is archived. Rulings render into a PUBLIC PR body: leave secrets, credentials and
unfixed-vulnerability detail out of the ruling text and out of the `domain/engineering` issue (carry the question and a pointer, not evidence snippets). An artifact with no `| Item | Class | Ruling |` table is a `[WARN]` and exit 0
(the label and `pending` lints still ran; add the table when the artifact lists decisions). A table with 0 rows, a drifted header, an unclosed code fence, an empty PR body or an unreadable
file is exit 2: fix the file or the invocation, never continue past it. A table row written after a blank line is outside the
table: a later writer adds its own `| Item | Class | Ruling |` header and separator.

## Remedy procedure (a `[FAIL]` is never a bare stop)

1. ONE batched spawn of `soleur:engineering:cto` (`soleur:legal:clo` for legal) carries ALL `unruled-technical` rows (a blank ruling or a
   `pending - assumed` placeholder), per the delegation step; write each `Ruled by` cell, commit, re-run the gate. If a ruling differs
   from what was built on the assumption, re-enter `work` for that item and amend the plan and tasks.
2. **At most two spawns per pipeline run** (a spawn from `one-shot` counts toward `ship`'s). A spawn that fails, times out, or returns without Decision and Rationale counts as
   an attempt. A ruling that says the item is actually operator-class rewrites the row as `operator (<category>)` with the
   CTO's reason, once.
3. After the cap the terminal state is **not** an operator question: the PR stays draft and ship files ONE
   `domain/engineering` issue (never `action-required`) carrying the question and the evidence.
4. `owner-label-unscoped` in the PR body: rewrite the line as a technical ruling (spawn the CTO) or append
   `(operator: <category>)` when it is a genuine operator-class item, then `gh pr edit` and re-run the body check.
5. Emit `SOLEUR_RULE_APPLIED rule=hr-technical-fork-is-not-an-operator-question note=gate` when the gate runs (telemetry).
