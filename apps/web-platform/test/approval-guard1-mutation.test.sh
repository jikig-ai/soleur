#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015  # `A && B || C` is the row idiom; the anchors live in the embedded table and are LITERAL text, never expanded
# Guard 1 of the #4672 plan (durable, action-bound approval requests), mutation half (plan "Guard Contract", Guard 1
# mutation matrix and "Harness rows"; ADR-307): anchor-asserted textual mutants of the approval consume gate and of the
# gated branch of `createCanUseTool`, applied to a COPY of the app tree, each judged by ONE targeted vitest file (never the
# full battery). The mutant table is embedded below (MUTANT TABLE); it follows test/destroy-ask-mutation.test.sh.
#
# PROPERTY. A slice-1 tool call is allowed only if it consumes, exactly once, an approved and unexpired request whose hash
# equals the hash of the full input about to run, in the same conversation, decided by a workspace Owner. For each edit of
# the gate's chokepoints and narrowing predicates (the SQL consume predicate and decide_approval, the hash and canonical
# object, the wait loop, the fail-closed branches, the flag read, the snapshot and the allow() input, the tool census, the
# decide boundary), the designed test turns RED on the case that is meant to catch it, and is GREEN on the unedited copy
# first. A mutant that is not killed, did not land, no longer parses, or was killed by something other than its designed
# detector is a finding. A mutant listed `equivalent` must SURVIVE (its reason is printed); if it is killed the table is wrong.
#
# ASSEMBLY. copy -> content-anchored edit (exact occurrence count, never a line number) -> landing proof (cmp differs from
# the pristine copy; a recursive diff names that file and no other) -> one vitest file -> verdict read from ANSI-stripped
# output. Every mutant is restored from the pristine copy with cp, never with git, and the restore is proved. The working
# tree is never edited: its tracked-file status is compared before and after.
#
# Plan harness rows. (a) The real-SDK probe (scripts/dev-probe-approval-gate.ts) needs a model, Doppler and the network, so
#   it cannot run inside this battery. Its verdict assertions are therefore pinned by a static checker (`probe-static`): the
#   P-rows remove "canUseTool was invoked" (the BYPASS verdict), the honoured-deny requirement and the exit-1 on a bypass
#   from a COPY of the probe, and the checker must go RED on each. (b) The must-PASS case that is not the canonical (same
#   arguments, different key order, must hash equal and consume) is a test in test/approval/gate-flow.test.ts ("harness row b")
#   and in test/approval/canonical.test.ts; the control run proves it is present and green, and C1 proves it can go RED.
#   The generic harness rows: a mutant whose anchor is missing FAILS the harness (never skips); the judge is driven with a
#   canned green, a canned red and a canned unparseable log; a no-op edit reads as "not landed"; the control (unedited) runs
#   first and a red or short control voids the battery (printf + exit 1, ADR-193).
#
# EQUIVALENT SURVIVORS (documented, each must SURVIVE; see the table, field `equivalent`):
#   G1-R4  the `default:` arm of the verdict switch in gate-flow.ts is unreachable (the wait returns only decided statuses,
#          timeout or aborted; every status it can return has its own arm, null/aborted are handled before the switch).
#   G1-R9  the initial value `"member"` of `viewerRole` in gate-flow.ts is dead: the try assigns the awaited role and the
#          catch assigns "member" explicitly, so the declaration default is never read.
#   G1-W6  the post-race abort check in waiters.ts is redundant: the next iteration starts with the signal check, before
#          any read, so removing it adds one no-op iteration and the same `aborted` result.
#   The reasons are printed on every run.
#
# NOT COVERED OFFLINE (honest gaps, not rows): mutations whose only detector is the database-gated integration test
#   (test/approval/approval-request.integration.test.ts, APPROVAL_DB_URL) and the real-SDK probe itself; for example
#   dropping `OR v_closed` from decide_approval leaves every offline text assertion green.
#
# Usage: bash apps/web-platform/test/approval-guard1-mutation.test.sh [--only <ERE over mutant ids>] [--list]
# Exit: 0 all verdicts as designed; 1 a finding; 2 setup failure; 3 inconclusive (a mutant could not be judged).
# Time: one targeted vitest file per mutant (~3-12 s each); the budget below is a WARN, never a verdict.
set -uo pipefail

WALL_BUDGET_S=900
APP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ONLY=""
LIST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --list) LIST=1; shift ;;
    *) printf 'unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

for t in python3 jq tar cmp diff timeout; do
  command -v "$t" >/dev/null 2>&1 || { printf 'HALT: required tool missing: %s (a skipped mutation battery reads as a pass)\n' "$t"; exit 2; }
done
VITEST="$APP/node_modules/.bin/vitest"
[ -x "$VITEST" ] || { printf 'HALT: %s is missing; run npm ci in apps/web-platform first\n' "$VITEST"; exit 2; }

SB="$(mktemp -d "${TMPDIR:-/var/tmp}/approval-g1-mut.XXXXXXXX")" || exit 2
# Canonical assert_fixture_dir — byte-identical copy (fixture-scan.py requires the verbatim body).
assert_fixture_dir() {
  case "${1-}" in
    "") printf 'FATAL: fixture dir is EMPTY; git -C "" would operate on %s\n' "$PWD" >&2; exit 2 ;;
    */../*|*/..) printf 'FATAL: fixture dir %s contains ..; refusing\n' "$1" >&2; exit 2 ;;
    /proc/*|/sys/*|/dev/*) printf 'FATAL: fixture dir %s is a synthetic-fs path; refusing\n' "$1" >&2; exit 2 ;;
    /|//|/.) printf 'FATAL: fixture dir resolves to the filesystem root; refusing\n' >&2; exit 2 ;;
    /*) : ;;
    *)  printf 'FATAL: fixture dir %s is RELATIVE; refusing\n' "$1" >&2; exit 2 ;;
  esac
}
assert_fixture_dir "$SB"
cleanup() { assert_fixture_dir "$SB"; rm -rf "$SB"; }
trap cleanup EXIT

# ---------------------------------------------------------------------------------------------------------------------
# MUTANT TABLE (python; dumped to JSON). edit = E(anchor, replace, count=<exact occurrences>, nth=<replace only the nth>)
# ---------------------------------------------------------------------------------------------------------------------
MUTANTS="$SB/mutants.json"
python3 - "$MUTANTS" <<'PYTBL'
import json, sys

def E(a, r, count=1, nth=None):
    return {"anchor": a, "replace": r, "count": count, "nth": nth}

TABLE = []
def M(id, file, edits, test, detect="", equivalent=None):
    TABLE.append({"id": id, "file": file, "edits": edits if isinstance(edits, list) else [edits],
                  "test": test, "detect": detect, "equivalent": equivalent})

GF = "server/approval/gate-flow.ts"
CANON = "server/approval/canonical.ts"
SVC = "server/approval/service.ts"
WAIT = "server/approval/waiters.ts"
TOOLS = "server/approval/tools.ts"
SQL = "supabase/migrations/180_approval_request.sql"
PC = "server/permission-callback.ts"
PROBE = "scripts/dev-probe-approval-gate.ts"

T_GF = "test/approval/gate-flow.test.ts"
T_CAN = "test/approval/canonical.test.ts"
T_WAIT = "test/approval/waiters.test.ts"
T_SVC = "test/approval/service.test.ts"
T_MIG = "test/approval/migration-180-approval-request.test.ts"
T_TC = "test/approval/tools-census.test.ts"
T_RC = "test/approval/runner-census.test.ts"
T_FLAG = "test/approval/flag.test.ts"
T_DB = "test/approval/decide-boundary.test.ts"
T_REND = "test/approval/render.test.ts"
T_WS = "test/server/ws-handler-approval.test.ts"
T_BA = "test/build-allowed-tools-census.test.ts"
STATIC = "static:probe"

# ---- 1. SQL consume predicate and decide_approval (Guard 1 matrix rows 1, 2, 3, 4, 9) -------------------------------
M("G1-1a-sql-drop-hash-conjunct", SQL, E("     AND action_sha256 = p_hash\n     AND conversation_id = p_conversation\n  RETURNING id INTO v_id;", "     AND conversation_id = p_conversation\n  RETURNING id INTO v_id;"), T_MIG, "carries every conjunct")
M("G1-1b-sql-drop-conversation-conjunct", SQL, E("     AND conversation_id = p_conversation\n  RETURNING id INTO v_id;", "  RETURNING id INTO v_id;"), T_MIG, "carries every conjunct")
M("G1-2a-sql-consume-accepts-expired", SQL, E("     AND status = 'approved'\n     AND expires_at > now()\n     AND action_sha256 = p_hash", "     AND status = 'approved'\n     AND action_sha256 = p_hash"), T_MIG, "carries every conjunct")
M("G1-2b-sql-decide-accepts-overdue", SQL, E("  IF v_row.expires_at <= now() THEN\n    UPDATE", "  IF FALSE THEN\n    UPDATE"), T_MIG, "enforces expiry inline")
M("G1-2c-sql-create-keeps-overdue-live-row", SQL, E("       AND status IN ('pending', 'approved')\n       AND expires_at <= now()\n    RETURNING id", "       AND status IN ('pending', 'approved')\n    RETURNING id"), T_MIG, "expires an overdue live row")
M("G1-3a-sql-consume-not-single-use", SQL, E("     SET status = 'consumed', consumed_at = now()\n   WHERE id = p_id", "     SET consumed_at = now()\n   WHERE id = p_id"), T_MIG, "carries every conjunct")
M("G1-3b-sql-consume-without-approved-conjunct", SQL, E("   WHERE id = p_id\n     AND status = 'approved'\n     AND expires_at > now()", "   WHERE id = p_id\n     AND expires_at > now()"), T_MIG, "carries every conjunct")
M("G1-3c-sql-hash-column-not-write-once", SQL, E("     OR NEW.action_sha256 IS DISTINCT FROM OLD.action_sha256\n", ""), T_MIG, "identity and decision columns write-once")
M("G1-3d-sql-status-machine-reopens-consumed", SQL, E("       ('approved', 'consumed'),\n       ('approved', 'expired')", "       ('approved', 'consumed'),\n       ('consumed', 'approved'),\n       ('approved', 'expired')"), T_MIG, "encodes exactly the TypeScript status machine")
M("G1-4-sql-decide-without-owner-check", SQL, E("  IF NOT FOUND OR NOT public.is_workspace_owner(v_row.workspace_id, auth.uid()) THEN", "  IF NOT FOUND THEN"), T_MIG, "re-checks the Owner role")
M("G1-9-sql-decide-ignores-archived-conversation", SQL, E("  SELECT (c.archived_at IS NOT NULL) INTO v_closed", "  SELECT false INTO v_closed"), T_MIG, "refuses a closed conversation")

# ---- 2. Canonical object and hash (the hashed bytes are the executed bytes) -----------------------------------------
M("G1-C1-canonicalize-without-sorting", CANON, E("for (const k of Object.keys(value as object).sort())", "for (const k of Object.keys(value as object))"), T_CAN, "key order")
M("G1-C2-hash-drops-tool-name", CANON, E("    tool_name: input.toolName,\n", ""), T_CAN, "64-char lowercase hex")
M("G1-C3-hash-drops-conversation", CANON, E("    conversation_id: input.conversationId,\n", ""), T_CAN, "binds the tool name, the workspace and the conversation")
M("G1-C4-hash-drops-workspace", CANON, E("    workspace_id: input.workspaceId,\n", ""), T_CAN, "binds the tool name, the workspace and the conversation")
M("G1-C5-strings-are-trimmed", CANON, E('    case "string":\n    case "boolean":\n      return value;', '    case "string":\n      return value.trim();\n    case "boolean":\n      return value;'), T_CAN, "does not trim")
M("G1-C6-default-not-applied", CANON, E('force: z.boolean().default(false)', 'force: z.boolean().optional()'), T_CAN, "zod default")
M("G1-C7-server-derived-optional", CANON, E('if (!parsedServer.success) throw new ApprovalCanonicalError("invalid_server_derived");', 'if (!parsedServer.success) server = {};\n    else'), T_CAN, "every server-derived field")
M("G1-C8-hash-accepts-non-uuid-binding", CANON, E("if (!UUID_RE.test(input.workspaceId) || !UUID_RE.test(input.conversationId)) {", "if (false) {"), T_CAN, "not UUID-shaped")
M("G1-C9-non-finite-number-hashed", CANON, E('if (!Number.isFinite(value)) throw new ApprovalCanonicalError("not_canonical");\n      return value;', "return value;"), T_CAN, "no canonical form")
M("G1-C10-reply-recipient-unbound", CANON, E("server: z.object({ recipient: nonEmpty }),", "server: null,"), T_CAN, "carries every input and server-derived field")
M("G1-C11-pushed-commit-unbound", CANON, E("server: z.object({ repo: nonEmpty, headSha: sha }),", "server: z.object({ repo: nonEmpty }),"), T_CAN, "carries every input and server-derived field")
M("G1-C12-reply-to-field-stripped", CANON, E("      replyTo: z.string().optional(),\n", ""), T_CAN, "carries every input and server-derived field")
M("G1-C13-hash-ignores-action-tool-mismatch", CANON, E("if (input.toolName !== input.action.tool || !APPROVAL_REQUIRED_TOOLS", "if (!APPROVAL_REQUIRED_TOOLS"), T_CAN, "not the action's tool")

# ---- 3. The gated flow: allow() input, snapshot, card source, binding ------------------------------------------------
M("G1-8a-allow-live-input-on-reproposal", GF, E("return a.allow(snapshot);", "return a.allow(a.toolInput);", count=2, nth=1), T_GF, "re-proposal release")
M("G1-8b-allow-live-input-on-live-wait", GF, E("return a.allow(snapshot);", "return a.allow(a.toolInput);", count=2, nth=2), T_GF, "deep clone")
M("G1-8c-snapshot-is-an-alias", GF, E("snapshot = structuredClone(a.toolInput);", "snapshot = a.toolInput;"), T_GF, "snapshot")
M("G1-8d-unbound-input-not-denied", GF, E("if (!isCoveredByCanonical(snapshot, action.fields)) {", "if (false) {"), T_GF, "canonical action does not cover")
M("G1-6-card-built-from-tool-input", GF, E("view: renderApprovalView(action),", "view: renderApprovalView({ ...action, fields: snapshot as never }),"), T_GF, "canonical object")
M("G1-1c-consume-binds-a-different-hash", GF, E("const c = await a.approval.consume({ id: approvalId, hash, conversationId: a.conversationId });", 'const c = await a.approval.consume({ id: approvalId, hash: "0".repeat(64), conversationId: a.conversationId });'), T_GF, "independently computed hash")
M("G1-5a-allow-on-wait-timeout", GF, E('a.logDecision(a.toolName, "deny", "approval wait ended undecided");\n          return deny(APPROVAL_PENDING_DENY);', 'a.logDecision(a.toolName, "deny", "approval wait ended undecided");\n          return a.allow(snapshot);'), T_GF, "timeout denies")
M("G1-5b-allow-on-abort", GF, E('if (selection === null || selection === "aborted" || aborted()) return denyAborted();', 'if (selection === null || selection === "aborted" || aborted()) return a.allow(snapshot);'), T_GF, "abort")
M("G1-5c-allow-when-the-wait-throws", GF, E('if (selection === null || selection === "aborted" || aborted()) return denyAborted();', 'if (selection === null) return a.allow(snapshot);\n      if (selection === "aborted" || aborted()) return denyAborted();'), T_GF, "abort during the wait")
M("G1-5d-no-abort-check-after-consume", GF, E('emitStatus("consumed", false);\n          if (aborted()) return denyAborted();\n', 'emitStatus("consumed", false);\n'), T_GF, "consume is in flight")
M("G1-5e-allow-on-unexpected-throw", GF, E('a.logDecision(a.toolName, "deny", "approval flow failed");\n    return deny(APPROVAL_UNAVAILABLE_DENY);', 'a.logDecision(a.toolName, "deny", "approval flow failed");\n    return a.allow(a.toolInput);'), T_GF, "a fault anywhere else")
M("G1-5f-allow-when-consume-throws", GF, E('} catch {\n            consumed = false;\n            reason = "rpc_error";\n          }', '} catch {\n            consumed = true;\n            reason = "rpc_error";\n          }'), T_GF, "rejects at the dependency boundary")
M("G1-5g-truthy-consume-is-an-allow", GF, E("consumed = c.consumed === true;", "consumed = Boolean(c.consumed);"), T_GF, "boolean true")
M("G1-5h-no-abort-check-before-submit", GF, E("    if (aborted()) return denyAborted();\n\n    // 3. Create-or-find", "\n    // 3. Create-or-find"), T_GF, "server-derived fields resolve")
M("G1-5i-no-abort-check-at-entry", GF, E("    if (aborted()) return denyAborted();\n\n    // 1. The fields", "\n    // 1. The fields"), T_GF, "already-aborted call")
M("G1-R1-allow-on-owner-rejection", GF, E("return deny(APPROVAL_REJECTED_DENY);", "return a.allow(snapshot);"), T_GF, "rejected request")
M("G1-R2-allow-on-expired", GF, E('a.logDecision(a.toolName, "deny", "approval expired");\n          return deny(APPROVAL_EXPIRED_DENY);', 'a.logDecision(a.toolName, "deny", "approval expired");\n          return a.allow(snapshot);'), T_GF, "expires while the agent waits")
M("G1-R3-allow-on-already-consumed", GF, E('a.logDecision(a.toolName, "deny", "approval already consumed");\n          return deny(APPROVAL_CONSUME_REJECTED_DENY);', 'a.logDecision(a.toolName, "deny", "approval already consumed");\n          return a.allow(snapshot);'), T_GF, "already consumed")
M("G1-R4-allow-on-unknown-outcome", GF, E('a.logDecision(a.toolName, "deny", "approval outcome unknown");\n          return deny(APPROVAL_UNAVAILABLE_DENY);', 'a.logDecision(a.toolName, "deny", "approval outcome unknown");\n          return a.allow(snapshot);'), T_GF, equivalent="the default arm of the verdict switch is unreachable: the wait returns only decided|timeout|aborted, the switch names every decided status the loop can return (waitForDecision never returns 'pending' as decided), and aborted/null are handled before the switch; the arm is defence in depth and no input reaches it")
M("G1-R5-allow-on-rejected-reproposal-consume", GF, E('a.logDecision(a.toolName, "deny", "approval consume rejected");\n        return deny(APPROVAL_CONSUME_REJECTED_DENY);', 'a.logDecision(a.toolName, "deny", "approval consume rejected");\n        return a.allow(snapshot);'), T_GF, "late approval whose consume is rejected")
M("G1-R6-allow-on-not-waitable", GF, E('a.logDecision(a.toolName, "deny", "approval request not waitable");\n        return deny(APPROVAL_UNAVAILABLE_DENY);', 'a.logDecision(a.toolName, "deny", "approval request not waitable");\n        return a.allow(snapshot);'), T_GF, "not waitable")
M("G1-R7-allow-when-request-not-created", GF, E('a.logDecision(a.toolName, "deny", "approval request not created");\n      return deny(APPROVAL_UNAVAILABLE_DENY);', 'a.logDecision(a.toolName, "deny", "approval request not created");\n      return a.allow(snapshot);'), T_GF, "cannot be created")
M("G1-R8-allow-when-bind-fails", GF, E('a.logDecision(a.toolName, "deny", "approval bind failed");\n      return deny(APPROVAL_UNAVAILABLE_DENY);\n    }\n\n    // 2.', 'a.logDecision(a.toolName, "deny", "approval bind failed");\n      return a.allow(snapshot);\n    }\n\n    // 2.'), T_GF, "cannot be resolved")
M("G1-R9-card-viewer-defaults-to-owner", GF, E('let viewerRole: "owner" | "member" = "member";', 'let viewerRole: "owner" | "member" = "owner";'), T_GF, equivalent="the initial value of viewerRole is dead: the try assigns the awaited role and the catch assigns 'member' explicitly, so the declaration default is never read")

# ---- 4. Flag-off fail-closed ------------------------------------------------------------------------------------------
M("G1-F1-flag-read-error-turns-flow-on", GF, E("} catch {\n    enabled = false;\n  }", "} catch {\n    enabled = true;\n  }"), T_GF, "throwing flag read")
M("G1-F2-flag-off-still-runs-the-flow", GF, E("if (!enabled) return null;", ""), T_GF, "flag")
M("G1-F3-flag-module-fails-open", "server/approval/flag.ts", E("  } catch {\n    return false;\n  }", "  } catch {\n    return true;\n  }"), T_FLAG, "fails closed")
M("G1-F4-flag-wrong-name", "server/approval/flag.ts", E('getRuntimeFlag("approval-queue"', 'getRuntimeFlag("approval-queu"'), T_FLAG, "reads the approval-queue flag")

# ---- 5. The permission-callback gated branch --------------------------------------------------------------------------
M("G1-PC1-gated-branch-never-calls-the-gate", PC, E("if (deps.approval && isApprovalRequiredTool(toolName)) {", "if (false && deps.approval && isApprovalRequiredTool(toolName)) {"), T_GF, "flag is read once per gate")
M("G1-PC2-gate-verdict-discarded", PC, E("if (approvalVerdict !== null) return approvalVerdict;", ""), T_GF, "independently computed hash")

# ---- 6. Service wrappers (consume contract, re-proposal consume: matrix row 11) ---------------------------------------
M("G1-11a-approved-row-not-consumed-on-create", SVC, E('if (r.approval.status === "approved") {', 'if (false && r.approval.status === "approved") {'), T_SVC, "consumed immediately")
M("G1-11b-approved-row-returned-to-the-wait-loop", SVC, [E('if (r.approval.status === "approved") {', 'if (false && r.approval.status === "approved") {'), E('if (r.approval.status === "pending") {', 'if (r.approval.status === "pending" || r.approval.status === "approved") {')], T_GF, "already approved")
M("G1-1d-consume-rpc-drops-conversation", SVC, E("p_conversation: p.conversationId", "p_conversation: p.id"), T_SVC, "passes id, hash and conversation")
M("G1-1e-consume-rpc-drops-hash", SVC, E("p_hash: p.hash,", "p_hash: p.id,"), T_SVC, "passes id, hash and conversation")
M("G1-5j-allow-when-consume-rpc-errors", SVC, E('if (res.error) return { consumed: false, reason: "rpc_error" };', "if (res.error) return { consumed: true };"), T_SVC, "fails closed")
M("G1-5k-allow-when-consume-rpc-throws", SVC, E('} catch {\n    return { consumed: false, reason: "rpc_error" };\n  }\n  if (res.error)', '} catch {\n    return { consumed: true };\n  }\n  if (res.error)'), T_GF, "consume that throws")
M("G1-5l-truthy-rpc-payload-consumes", SVC, E("if (isObj(d) && d.consumed === true) return { consumed: true };", "if (isObj(d) && d.consumed) return { consumed: true };"), T_SVC, "unknown shape")
M("G1-1f-malformed-hash-reaches-the-database", SVC, E('if (!HASH_RE.test(p.hash)) return { consumed: false, reason: "bad_request" };', ""), T_SVC, "never consume on a malformed bind")

# ---- 7. The wait loop ---------------------------------------------------------------------------------------------------
M("G1-W1-transient-read-error-decides-approved", WAIT, E("} catch {\n          // Transient read error: keep waiting until the deadline. Never an allow.\n        }", '} catch {\n          return { kind: "decided", status: "approved" };\n        }'), T_WAIT, "transient read error")
M("G1-W2-abort-not-checked-first", WAIT, E('      if (deps.signal.aborted) return { kind: "aborted" };\n\n      if (reads < MAX_POLL_READS)', "      if (reads < MAX_POLL_READS)"), T_WAIT, "checks the signal first")
M("G1-W3-timeout-reads-as-approved", WAIT, E('if (remaining <= 0 || reads >= MAX_POLL_READS) return { kind: "timeout" };', 'if (remaining <= 0 || reads >= MAX_POLL_READS) return { kind: "decided", status: "approved" };'), T_WAIT, "times out undecided")
M("G1-W4-wake-is-a-verdict", WAIT, E('if (r === "woken") wake = undefined;', 'if (r === "woken") return { kind: "decided", status: "approved" };'), T_WAIT, "wake")
M("G1-W5-pending-read-counts-as-decided", WAIT, E('if (s && s !== "pending") return { kind: "decided", status: s };', 'if (s) return { kind: "decided", status: s as never };'), T_WAIT, "as soon as a read shows it")
M("G1-W6-abort-during-sleep-not-honoured", WAIT, E('if (r === "aborted" || deps.signal.aborted) return { kind: "aborted" };', 'if (false) return { kind: "aborted" };'), T_WAIT, "abort during the sleep", equivalent="the next loop iteration begins with the signal check before any read, so dropping the post-race abort check only adds one no-op iteration; the observable outcome is the same aborted result with no extra read")

# ---- 8. Tool set and census (matrix row 7; Guard 2 rows) ---------------------------------------------------------------
M("G1-7a-slice1-tool-removed-from-required-set", TOOLS, E("  `${P}workspace_set_autonomous`,\n] as const;", "] as const;"), T_TC, "exactly the eight tools")
M("G1-7b-nothing-is-approval-required", TOOLS, E("return REQUIRED.has(toolName);", "return false;"), T_TC, "exactly the eight tools")
M("G1-7c-gated-tool-listed-in-allowed-tools", "server/tool-tiers.ts", E('return getToolTier(fqn) === "auto-approve";', 'return getToolTier(fqn) !== "blocked";'), T_BA, "gated ones are not")
M("G1-7d-runner-loses-the-approval-wiring", "server/agent-runner.ts", E("approval: createApprovalGateDeps({", "approvalOff: createApprovalGateDeps({"), T_RC, "wires the approval dependency")
M("G1-12a-census-vacuity-check-removed", TOOLS, E("if (gated.length === 0 || required.length === 0) {", "if (false) {"), T_TC, "vacuous")
M("G1-12b-census-vacuity-needs-both-empty", TOOLS, E("if (gated.length === 0 || required.length === 0) {", "if (gated.length === 0 && required.length === 0) {"), T_TC, "row 2b")
M("G2-1-unclassified-gated-tool-not-reported", TOOLS, E("unclassified: gated.filter((t) => !req.has(t) && !Object.hasOwn(exempt, t)),", "unclassified: [],"), T_TC, "row 1")
M("G2-4-blank-exempt-reason-accepted", TOOLS, E("exempt[t].trim().length === 0", "exempt[t].length === 0"), T_TC, "row 4")

# ---- 9. Decide boundary (the agent cannot approve its own request) and cross-kind guard ------------------------------
M("G1-D1-decision-enum-widened", "server/approval/decide.ts", E('export const APPROVAL_DECISIONS = ["approve", "deny"] as const;', 'export const APPROVAL_DECISIONS = ["approve", "deny", "approve_all"] as const;'), T_SVC, "rejects an unknown decision")
M("G1-D2-service-reexports-decide", SVC, E("export const APPROVAL_STATUSES =", 'export { decideApproval } from "./decide";\nexport const APPROVAL_STATUSES ='), T_DB, "cannot reach decide.ts")
M("G1-D3-review-answer-can-resolve-an-approval", "server/ws-handler.ts", E('if (typeof msg.gateId === "string" && hasApprovalWaiter(msg.gateId)) {', "if (false) {"), T_WS, "cross-kind")
M("G1-D4-reattach-skips-hash-verification", "server/approval/reattach.ts", E("}) === approval.action_sha256;", "}) !== '';"), T_WS, "does not hash to the bound value")
M("G1-D5-card-truncates-the-body", "server/approval/render.ts", E('row("BODY", str(f.body), "block"),', 'row("BODY", str(f.body).slice(0, 40), "block"),', count=2), T_REND, "rendered in full")

# ---- 10. Harness row (a): the real-SDK probe assertions (static checker) ----------------------------------------------
M("P1-probe-no-invoked-assertion", PROBE, E('} else if (!r.invoked) verdict = "BYPASS";', "} else if (false) verdict = \"BYPASS\";"), STATIC, "invoked")
M("P2-probe-deny-not-required-to-be-honoured", PROBE, E('verdict = denyHonoured && r.tier === "gated" ? "ok" : "FAIL";', 'verdict = r.tier === "gated" ? "ok" : "FAIL";'), STATIC, "denyHonoured")
M("P3-probe-bypass-does-not-fail-the-run", PROBE, E('if (verdict === "BYPASS" || verdict === "FAIL" || verdict === "CANARY-NOT-BYPASSING") failed = true;', 'if (verdict === "FAIL" || verdict === "CANARY-NOT-BYPASSING") failed = true;'), STATIC, "failed")

json.dump(TABLE, open(sys.argv[1], "w"))
PYTBL
rc=$?
[ "$rc" = 0 ] && [ -s "$MUTANTS" ] || { printf 'HALT: mutant table could not be built (rc=%s)\n' "$rc"; exit 2; }

if [ "$LIST" = 1 ]; then jq -r '.[] | "\(.id)\t\(.test)\t\(if .equivalent then "equivalent" else "must-kill" end)"' "$MUTANTS"; exit 0; fi

START=$(date +%s)
CHECKED=0 PASS=0 FAIL=0
ok()  { PASS=$((PASS + 1)); printf '[ok]   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); printf '[FAIL] %s\n' "$1"; }
check() { # check <label> <command...>: CHECKED moves at the call site, never in ok/bad
  local label="$1"; shift
  CHECKED=$((CHECKED + 1))
  if "$@"; then ok "$label"; else bad "$label"; fi
}

# Instrument self-test: drive both helpers once and require every observable to have moved.
p0=$PASS f0=$FAIL
ok "instrument self-test (pass path)" >/dev/null
bad "instrument self-test (fail path, expected)" >/dev/null
if [ $((PASS - p0)) -ne 1 ] || [ $((FAIL - f0)) -ne 1 ]; then printf 'HALT: the pass/fail helpers did not both move\n'; exit 1; fi
PASS=$p0 FAIL=$f0

PRISTINE="$SB/.pristine"
REPO="$(cd "$APP/../.." && pwd)"
APPCOPY="$SB/apps/web-platform"
mkdir -p "$PRISTINE" "$APPCOPY" || exit 2
# vitest.config.ts and its global setup reach ../../../plugins/soleur/test/lib/*: mirror that layout (read-only symlink; no mutant edits plugins/).
ln -s "$REPO/plugins" "$SB/plugins" || exit 2
# Some suites read knowledge-base (read-only symlink as well).
[ -d "$REPO/knowledge-base" ] && { ln -s "$REPO/knowledge-base" "$SB/knowledge-base" || exit 2; }

# Tracked-file status of the WHOLE app tree before and after: the battery must leave no mutated source behind.
git_status() { git -C "$APP" status --porcelain -- . 2>/dev/null | sort; }
STATUS_BEFORE="$(git_status)"
assert_fixture_dir "$SB"

tar -C "$APP" --exclude=./node_modules --exclude=./.next --exclude=./e2e --exclude=./public --exclude=./docs -cf - . | tar -C "$APPCOPY" -xf -
rc=$?; [ "$rc" = 0 ] || { printf 'HALT: could not copy the app tree (rc=%s)\n' "$rc"; exit 2; }
ln -s "$APP/node_modules" "$APPCOPY/node_modules" || exit 2
# Pristine copies of every file any mutant edits.
while IFS= read -r f; do
  mkdir -p "$PRISTINE/$(dirname "$f")" && cp "$APP/$f" "$PRISTINE/$f" || { printf 'HALT: cannot snapshot %s\n' "$f"; exit 2; }
done < <(jq -r '.[].file' "$MUTANTS" | sort -u)

strip_ansi() { sed -r 's/\x1B\[[0-9;]*[mGKHF]//g' "$1"; }

# vitest summary readers (from ANSI-stripped text). A missing "Tests" line reads as "no summary", never as zero failures.
summary_line() { grep -E '^ *Tests ' "$1.clean" | tail -1; }
count_of() { # count_of <log> <word>
  summary_line "$1" | grep -oE "[0-9]+ $2" | head -1 | grep -oE '[0-9]+'
}

run_test() { # run_test <testfile> <log> -> exit status in $RUN_RC
  ( cd "$APPCOPY" && timeout -k 5 180 "$VITEST" run "$1" ) > "$2" 2>&1
  RUN_RC=$?
  strip_ansi "$2" > "$2.clean"
}

# Static checker for the real-SDK probe (harness row a): the three assertions that make the probe able to fail. Prints the
# name of every missing assertion; exit 1 if any is missing, 0 if all are present. It runs against a COPY of the probe.
probe_static() { # probe_static <probe.ts> <log>
  python3 - "$1" > "$2" 2>&1 <<'PYCHK'
import re, sys
s = open(sys.argv[1], encoding="utf-8").read()
need = {
    "invoked: a case where canUseTool was never invoked is the BYPASS verdict": r'else if \(!r\.invoked\) verdict = "BYPASS"',
    "denyHonoured: ok requires the deny to be honoured and the tier gated": r'verdict = denyHonoured && r\.tier === "gated" \? "ok" : "FAIL"',
    "denyHonoured: defined as invoked, handler not run, every behaviour deny": r'const denyHonoured = r\.invoked && !r\.handlerRan && r\.behaviors\.length > 0 && r\.behaviors\.every\(\(b\) => b === "deny"\)',
    "failed: a BYPASS, FAIL or non-bypassing canary fails the run": r'if \(verdict === "BYPASS" \|\| verdict === "FAIL" \|\| verdict === "CANARY-NOT-BYPASSING"\) failed = true',
}
missing = [k for k, rx in need.items() if not re.search(rx, s)]
for k in missing:
    print("MISSING " + k)
sys.exit(1 if missing else 0)
PYCHK
  RUN_RC=$?
  cp "$2" "$2.clean"
  # Mirror vitest's contract for the judge: a "Tests" line with the failed count.
  if [ "$RUN_RC" = 1 ]; then printf ' Tests  %s failed | 0 passed\n' "$(grep -c '^MISSING' "$2")" >> "$2.clean"; else printf ' Tests  4 passed (4)\n' >> "$2.clean"; fi
}

# Judge: prints one of KILLED, SURVIVED, BROKEN, UNRESOLVED. BROKEN = the mutant does not parse or collect (killed by
# the parser, not by the designed row); UNRESOLVED = no readable summary.
judge() { # judge <log> <rc>
  local log="$1" rc="$2" failed
  failed="$(count_of "$log" failed)"
  if grep -qE 'SyntaxError|Transform failed|Failed to parse|Unexpected token|Cannot find module|Failed to resolve import|is not defined' "$log.clean" && [ -z "$(summary_line "$log")" ]; then echo BROKEN; return; fi
  if [ -z "$(summary_line "$log")" ]; then echo UNRESOLVED; return; fi
  if [ "$rc" = 1 ] && [ -n "$failed" ] && [ "$failed" -ge 1 ]; then echo KILLED; return; fi
  if [ "$rc" = 0 ] && [ -z "$failed" ]; then echo SURVIVED; return; fi
  echo UNRESOLVED
}

# --- Harness row (b-judge): the judge itself, driven with canned logs.
canned() { printf '%s\n' "$2" > "$1"; cp "$1" "$1.clean"; }
canned "$SB/c-green" " Tests  40 passed (40)"
canned "$SB/c-red"   " Tests  2 failed | 38 passed (40)"
canned "$SB/c-parse" " Error: Transform failed with 1 error
SyntaxError: Unexpected token"
check "judge: canned green reads SURVIVED" test "$(judge "$SB/c-green" 0)" = SURVIVED
check "judge: canned red reads KILLED" test "$(judge "$SB/c-red" 1)" = KILLED
check "judge: canned unparseable log reads BROKEN, never KILLED" test "$(judge "$SB/c-parse" 1)" = BROKEN
check "judge: a red log with exit 0 is UNRESOLVED" test "$(judge "$SB/c-red" 0)" = UNRESOLVED

# --- Edit driver (python): applies every edit of one mutant: exact occurrence count, optional nth occurrence.
apply_mutant() { # apply_mutant <index> -> 0 landed, 3 anchor mismatch
  python3 - "$MUTANTS" "$1" "$APPCOPY" <<'PY'
import json, sys
mutants, idx, root = sys.argv[1], int(sys.argv[2]), sys.argv[3]
m = json.load(open(mutants))[idx]
path = root + "/" + m["file"]
s = open(path, encoding="utf-8").read()
for e in m["edits"]:
    n = s.count(e["anchor"])
    if n != e["count"]:
        print("ANCHOR MISMATCH for %s: found %d, expected %d" % (m["id"], n, e["count"]))
        sys.exit(3)
    nth = e.get("nth")
    if nth is None:
        s = s.replace(e["anchor"], e["replace"])
    else:
        parts = s.split(e["anchor"])
        out = parts[0]
        for i, p in enumerate(parts[1:], start=1):
            out += (e["replace"] if i == nth else e["anchor"]) + p
        s = out
open(path, "w", encoding="utf-8").write(s)
PY
}

assert_fixture_dir "$SB"
MIN_MUTANTS=70
TOTAL="$(jq 'length' "$MUTANTS")"
if [ "$TOTAL" -lt "$MIN_MUTANTS" ]; then printf 'HALT: mutant table has %s rows, floor %s: a truncated table is vacuous\n' "$TOTAL" "$MIN_MUTANTS"; exit 1; fi

# --- Harness row (a-anchor): a missing anchor must fail the apply step.
BOGUS="$SB/bogus.json"
jq -n '[{id:"bogus",file:"server/approval/gate-flow.ts",edits:[{anchor:"@@no such anchor@@",replace:"x",count:1,nth:null}],test:"x",detect:"x",equivalent:null}]' > "$BOGUS"
python3 - "$BOGUS" 0 "$APPCOPY" > /dev/null 2>&1 <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))[0]
s = open(sys.argv[3] + "/" + m["file"], encoding="utf-8").read()
e = m["edits"][0]
sys.exit(0 if s.count(e["anchor"]) == e["count"] else 3)
PY
rc=$?
check "harness row (a-anchor): a mutant whose anchor is missing fails the apply step (rc 3, never a skip)" test "$rc" = 3

# --- Control: the unedited copy, on every distinct test file, must be GREEN with a literal floor of tests.
declare -A FLOOR=(
  ["test/approval/gate-flow.test.ts"]=64
  ["test/approval/canonical.test.ts"]=75
  ["test/approval/waiters.test.ts"]=15
  ["test/approval/service.test.ts"]=21
  ["test/approval/migration-180-approval-request.test.ts"]=54
  ["test/approval/tools-census.test.ts"]=10
  ["test/approval/runner-census.test.ts"]=3
  ["test/approval/flag.test.ts"]=3
  ["test/approval/decide-boundary.test.ts"]=15
  ["test/approval/render.test.ts"]=30
  ["test/server/ws-handler-approval.test.ts"]=21
  ["test/build-allowed-tools-census.test.ts"]=47
)
for tf in $(jq -r '.[].test' "$MUTANTS" | sort -u); do
  if [ "$tf" = "static:probe" ]; then
    # Control for the static checker: the pristine probe passes it, and it has all four assertions to check.
    probe_static "$APPCOPY/scripts/dev-probe-approval-gate.ts" "$SB/control.probe.log"
    CHECKED=$((CHECKED + 1))
    if [ "$RUN_RC" != 0 ]; then printf 'HALT: the CONTROL probe checker is not green (the probe lost an assertion):\n'; cat "$SB/control.probe.log"; exit 1; fi
    ok "control: the real-SDK probe carries its 4 verdict assertions"
    continue
  fi
  floor="${FLOOR[$tf]:-}"
  [ -n "$floor" ] || { printf 'HALT: no control floor for test file %s\n' "$tf"; exit 1; }
  run_test "$tf" "$SB/control.$(basename "$tf").log"
  passed="$(count_of "$SB/control.$(basename "$tf").log" passed)"
  failed="$(count_of "$SB/control.$(basename "$tf").log" failed)"
  if [ "$RUN_RC" != 0 ] || [ -n "$failed" ] || [ -z "$passed" ] || [ "$passed" -lt "$floor" ]; then
    printf 'HALT: the CONTROL run of %s is not green with at least %s tests (rc=%s, passed=%s, failed=%s): the battery is void\n' "$tf" "$floor" "$RUN_RC" "${passed:-?}" "${failed:-0}"
    tail -30 "$SB/control.$(basename "$tf").log.clean"
    exit 1
  fi
  CHECKED=$((CHECKED + 1))
  ok "control: $tf is green ($passed tests)"
done

# Presence of the plan's must-PASS case (harness row b): the control is only meaningful if it is there.
CHECKED=$((CHECKED + 1))
if grep -q 'harness row b' "$APPCOPY/test/approval/gate-flow.test.ts"; then
  ok "harness row (b): the must-PASS non-canonical case (same arguments, different key order) is present in gate-flow.test.ts and the file is green in the control"
else
  bad "harness row (b): the must-PASS non-canonical case is missing from gate-flow.test.ts"
fi

# --- Mutants.
KILLED=0 SURVIVED_EQ=0 UNRESOLVED=0 SELECTED=0
for ((i = 0; i < TOTAL; i++)); do
  id="$(jq -r ".[$i].id" "$MUTANTS")"
  if [ -n "$ONLY" ] && ! [[ "$id" =~ $ONLY ]]; then continue; fi
  SELECTED=$((SELECTED + 1))
  file="$(jq -r ".[$i].file" "$MUTANTS")"
  tf="$(jq -r ".[$i].test" "$MUTANTS")"
  detect="$(jq -r ".[$i].detect // empty" "$MUTANTS")"
  equiv="$(jq -r ".[$i].equivalent // empty" "$MUTANTS")"

  apply_mutant "$i" > "$SB/apply.log" 2>&1
  arc=$?
  if [ "$arc" != 0 ]; then CHECKED=$((CHECKED + 1)); bad "$id: the edit did not apply (rc=$arc): $(cat "$SB/apply.log")"; cp "$PRISTINE/$file" "$APPCOPY/$file"; continue; fi

  # Landing proof: the edited file differs from the pristine copy, and it is the ONLY file that differs from the tree.
  if cmp -s "$APPCOPY/$file" "$PRISTINE/$file"; then CHECKED=$((CHECKED + 1)); bad "$id: the mutation did NOT land (file identical to pristine)"; continue; fi
  differing="$(diff -rq "$APP/$(dirname "$file")" "$APPCOPY/$(dirname "$file")" 2>/dev/null | grep -c 'differ')"
  if [ "$differing" != 1 ]; then CHECKED=$((CHECKED + 1)); bad "$id: expected exactly one differing file in $(dirname "$file"), found $differing"; cp "$PRISTINE/$file" "$APPCOPY/$file"; continue; fi

  if [ "$tf" = "static:probe" ]; then
    probe_static "$APPCOPY/$file" "$SB/mut.$i.log"
  else
    run_test "$tf" "$SB/mut.$i.log"
  fi
  verdict="$(judge "$SB/mut.$i.log" "$RUN_RC")"
  cp "$PRISTINE/$file" "$APPCOPY/$file"
  if ! cmp -s "$APPCOPY/$file" "$PRISTINE/$file"; then printf 'HALT: restore of %s failed\n' "$file"; exit 2; fi

  CHECKED=$((CHECKED + 1))
  if [ -n "$equiv" ]; then
    if [ "$verdict" = SURVIVED ]; then ok "$id: equivalent, survives as documented ($equiv)"; SURVIVED_EQ=$((SURVIVED_EQ + 1)); else bad "$id: listed equivalent but the verdict is $verdict"; fi
    continue
  fi
  case "$verdict" in
    KILLED)
      escaped="$(jq -rn --arg d "$detect" '$d | @json | .[1:-1]')"
      if [ -n "$detect" ] && ! grep -qiF -e "$detect" -e "$escaped" "$SB/mut.$i.log.clean"; then
        bad "$id: killed, but not by its designed detector ('$detect' is absent from the failure output)"
      else
        first="$(grep -m1 -E '(FAIL|×|MISSING) ' "$SB/mut.$i.log.clean" | sed -r 's/^ +//' | cut -c1-150)"
        ok "$id: killed by '${detect:-any}' [${first}]"; KILLED=$((KILLED + 1))
      fi ;;
    SURVIVED) bad "$id: SURVIVED: the tests do not exercise this property (fix the tests, not the guard)" ;;
    BROKEN)   bad "$id: BROKEN: the mutant does not parse or collect, so it was killed by the parser, not by its row" ;;
    *)        UNRESOLVED=$((UNRESOLVED + 1)); bad "$id: UNRESOLVED: no readable verdict" ;;
  esac
done

# --- Harness row (c): a no-op edit reads as "not landed".
NOOP="$SB/noop.json"
jq -n '[{id:"noop",file:"server/approval/gate-flow.ts",edits:[{anchor:"export const APPROVAL_PENDING_DENY",replace:"export const APPROVAL_PENDING_DENY",count:1,nth:null}],test:"x",detect:"x",equivalent:null}]' > "$NOOP"
python3 - "$NOOP" 0 "$APPCOPY" <<'PY' > /dev/null 2>&1
import json, sys
m = json.load(open(sys.argv[1]))[0]
p = sys.argv[3] + "/" + m["file"]
s = open(p, encoding="utf-8").read()
e = m["edits"][0]
open(p, "w", encoding="utf-8").write(s.replace(e["anchor"], e["replace"]))
PY
check "harness row (c): a no-op edit reads as not landed" cmp -s "$APPCOPY/server/approval/gate-flow.ts" "$PRISTINE/server/approval/gate-flow.ts"

# --- The working tree was never edited.
STATUS_AFTER="$(git_status)"
check "the app tree's tracked-file status is unchanged by the battery (no mutated source left behind)" test "$STATUS_BEFORE" = "$STATUS_AFTER"

ELAPSED=$(( $(date +%s) - START ))
[ "$ELAPSED" -le "$WALL_BUDGET_S" ] || printf '[WARN] wall time %ss exceeds the %ss budget (a slow runner is not a defect)\n' "$ELAPSED" "$WALL_BUDGET_S"
printf '\nmutants selected=%s killed=%s equivalent-survivors=%s unresolved=%s; checks=%s pass=%s fail=%s; %ss\n' "$SELECTED" "$KILLED" "$SURVIVED_EQ" "$UNRESOLVED" "$CHECKED" "$PASS" "$FAIL" "$ELAPSED"

# A --only run is a partial battery: it has its own verdict and never reaches the full-run floor below.
if [ -n "$ONLY" ]; then
  if [ "$UNRESOLVED" -gt 0 ]; then exit 3; fi
  if [ "$FAIL" -gt 0 ]; then exit 1; fi
  exit 0
fi

# Anti-vacuity: the floor is a literal directly above its `if`, and reported by printf + exit, never through ok/bad.
MIN_CHECKS=80
if [ "$CHECKED" -lt "$MIN_CHECKS" ]; then
  printf '[FATAL] assertion floor: only %s assertions ran, floor %s: the battery is vacuous\n' "$CHECKED" "$MIN_CHECKS" >&2
  exit 1
fi
if [ $((PASS + FAIL)) -lt "$CHECKED" ]; then printf 'HALT: pass+fail (%s) is below the checks counted (%s)\n' "$((PASS + FAIL))" "$CHECKED"; exit 1; fi
if [ "$UNRESOLVED" -gt 0 ]; then exit 3; fi
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
