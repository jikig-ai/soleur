#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2015  # `A && B || C` is the row idiom; the anchors live in the embedded table and are LITERAL text, never expanded
# Guard 1 of the #4672 plan (durable, action-bound approval requests), mutation half (plan "Guard Contract", Guard 1
# mutation matrix and "Harness rows"; ADR-307): anchor-asserted textual mutants of the approval consume gate, of the
# gated branch of `createCanUseTool`, of the execution-grant side channel and of the decide boundary, applied to a COPY of
# the app tree, each judged by ONE targeted vitest file (never the full battery). The mutant table is embedded below
# (MUTANT TABLE); it follows test/destroy-ask-mutation.test.sh.
#
# PROPERTY. A slice-1 tool call is allowed only if it consumes, exactly once, an approved and unexpired request whose hash
# equals the (keyed) hash of the full input about to run, in the same conversation, decided by a workspace Owner who is
# still an Owner and requested by a member who still is one; the executed action is the approved one (the execution grant
# pins the pushed commit and the workspace). For each edit of the gate's chokepoints and narrowing predicates, the designed
# test turns RED on the case that is meant to catch it, and is GREEN on the unedited copy first.
#
# JUDGE (review round, test-design P2-6/P2-7; round 2, FD-5). Every row names the EXACT failing test(s) that must kill it:
# `kill` is a list of substrings of the full test name (describe path + title) and EVERY entry must be among the failed
# tests of the single targeted file, which vitest reports in a JSON file (never a substring of the whole log, which a crash,
# a describe title or the "N failed" summary line could satisfy). The control run proves each named test exists and is green
# before any mutant runs. Attribution is by EXACT COUNT: a named substring must match as many FAILED tests as it matches
# control-PASSED tests (a title shared by several it.each cases is credited only when all of its cases fail, so one case
# going quiet reads MISATTRIBUTED, not KILLED). A must-kill row with an empty `kill` list is MISATTRIBUTED (any failing test
# would credit it). The blast radius is bounded: failed/total above the row's bound (default 0.5; `blast=` on a row whose
# designed detector is legitimately spread over most of the file) is UNRESOLVED, because a crash that fails the whole file
# is not a kill by its named test. Verdicts, from the JSON report only:
#     KILLED        the named test(s) failed (exit 1), all cases of each named title, inside the blast bound
#     SURVIVED      nothing failed (exit 0)
#     MISATTRIBUTED something failed but not (all of) the named test(s), or the row names none: a finding
#     BROKEN        the suite did not collect (syntax error / unresolved import): killed by the parser, not by the row
#     UNRESOLVED    anything else: no report, a timeout, a signal, a non-zero exit with no failed test, failed tests with
#                   exit 0. A crash is never a kill (exit 3).
#
# ASSEMBLY. copy -> content-anchored edit (exact occurrence count, never a line number) -> landing proof (cmp differs from
# the pristine copy; a recursive diff names that file and no other) -> one vitest file -> verdict read from the JSON report.
# Every mutant is restored from the pristine copy with cp, never with git, and the restore is proved. The working tree is
# never edited: its tracked-file status is compared before and after. `--check-anchors` applies every edit to the pristine
# copy only (no test run) and reports each anchor mismatch at once, for repairing a stale table in seconds.
#
# Plan harness rows. (a) The real-SDK probe (scripts/dev-probe-approval-gate.ts) needs a model, Doppler and the network, so
#   it cannot run inside this battery. HONEST SCOPE: the probe's SEMANTIC behaviour (that a gated tool really reaches
#   canUseTool under the production options and that a deny stops the handler) is measured ONLY by the manual real-SDK run
#   recorded in knowledge-base/project/specs/archive/20261029-164429-feat-hitl-approval-queue/phase-0-measurements.md. What this battery can do is
#   pin that the probe's own verdict logic still exists in executable code: `probe-static` strips comments and string-
#   adjacent noise first (an anchor that survives only inside a comment does not count; row P7 proves it), then requires ten
#   anchors (the BYPASS verdict, the honoured-deny requirement, the failing exit code, the handlerRan / invoked / behaviour /
#   tier recorders, the Reject approver). It is a text pin, not a behavioural test, and an equivalent rewrite of the probe
#   will need these anchors updated. The probe is outside this PR; extracting its verdict function for a canned-input test
#   is the follow-up that would make it behavioural. (b) The must-PASS case that is not the canonical (same arguments,
#   different key order, must hash equal and consume) is a test in test/approval/gate-flow.test.ts ("harness row b") and in
#   test/approval/canonical.test.ts; the control run proves it is present and green, and C1 proves it can go RED.
#   The generic harness rows: a mutant whose anchor is missing FAILS the harness (never skips); the judge is driven with a
#   canned green, canned reds, a canned parse error, a canned timeout and a missing report; a no-op edit reads as "not
#   landed"; the control (unedited) runs first and a red or short control voids the battery (printf + exit 1, ADR-193).
#
# EQUIVALENT SURVIVORS (each must SURVIVE; the reason is printed on every run):
#   G1-R4  the `default:` arm of the verdict switch in gate-flow.ts (since round 2 an exhaustiveness `never` check plus a
#          fail-closed deny) is unreachable. Input shapes surveyed: the wait returns decided|timeout|aborted; `decided`
#          carries only approved|rejected|expired|consumed (waitForDecision filters null and "pending"); timeout and
#          aborted have their own arms or are handled before the switch (`selection === null || "aborted" || aborted()`);
#          a string from a stubbed `hold` is not a real source (hold is holdForUser around the wait, typed WaitSelection
#          | null by the cast); a hold that returns an unknown string is the only way in and no production hold does.
#          The arm is the runtime backstop for the untyped `hold` seam.
#   G1-W6  the post-race abort check in waiters.ts is redundant. Input shapes surveyed: abort before the loop (checked at
#          the top), abort during a read (the next top-of-loop check), abort during the sleep (the `aborted` racer resolves,
#          the post-race check is skipped, the next iteration returns aborted before any read), abort after the wake
#          (same). Every path ends with the same `aborted` result and the same read count. (Round 2 added `lastReadError` to
#          the result; the two returns still carry the same fields.)
#   G1-GD24 the `COMMIT_SHA_RE` check on `git rev-parse HEAD` in gate.ts is defence in depth. Input shapes surveyed: a
#          normal repository (one 40-hex id), a sha-256 repository (64-hex, the regex admits it), an empty repository (no
#          commit: git exits 128, execFile throws before the check), a non-repository directory (exit 128), a detached
#          HEAD (one id). None reaches the check with a non-sha; the throw tests in gate-deps.test.ts hold the exit paths.
# RESIDUAL GAPS (NOT equivalent: real behaviour the test suite does not see; each must SURVIVE and is reported, so a
# future fix that kills one turns the battery red until the row is moved to the must-kill table):
#   G1-DB3  a tool builder that assembles the RPC name at run time (`decide_${"approval"}`) is not seen by the sentinel's
#           name grep; only the import-graph conjuncts and review stand between that and a self-decide. Input shapes
#           surveyed: a template literal with an interpolated fragment (this row), string concatenation (`"decide_" +
#           "approval"`), an array join, a computed property on an object of names, a name read from a constant in another
#           module. The grep sees none of them; a builder that reaches the RPC at all must import a client, which the
#           import-graph conjuncts (no decide module, no hub value import) do not stop either. Closing it needs a
#           data-flow check, not a grep; the property is held by the absence of any decide import and by review.
#   G1-F5   `=== true` -> `!== false` on the flag read lets a non-boolean truthy/undefined flag value turn the flow on.
#           Input shapes surveyed: `getRuntimeFlag` is typed `Promise<boolean>` (a lookup into the per-flag snapshot, lib/feature-flags/server.ts;
#           the snapshot values are not re-checked at run time), the gate's seam is typed `Promise<boolean>`, tests inject booleans and a rejected promise (both pinned), and a
#           mutated seam returning `undefined` / `"yes"` / `1` is not constructible from the typed seam. The dev impact is
#           nil; the fail-closed contract for an odd value is unpinned and a typed-seam change would be the trigger.
#
# NOT COVERED OFFLINE (honest gaps, not rows): mutations whose only detector is the database-gated behavioural suite
#   (test/server/approval-request.tenant-isolation.test.ts, runs in tenant-integration.yml against a DEV database) and the
#   real-SDK probe itself; for example dropping `OR v_closed` from decide_approval's pending path leaves the offline
#   tokenized assertions that do not name it green. The SQL rows below are the tokenized backstop, not the behaviour.
#   Round 2 pinned offline (tokenized, test/approval/migration-180-approval-request.test.ts, not rows here because the
#   migration file is not edited by this battery): consume's `IF v_id IS NOT NULL ... 'consumed', true` and the single
#   `'consumed', false` failure return (N1/N2), get_approval_status reading the row's own status (N3), and both inbox-settle
#   branches scoped by `workspace_id = p_workspace_id` (N4/N5), and both `WHERE id = p_id` row reads, get_approval_status and
#   the consume reason lookup (N6/N7; rows G1-N6/G1-N7 mutate the real SQL). The reason lookup's CASE order is pinned (G1-3g).
#
# ROW GROUPS (round 2 added sections 11-14): 11 the production gate-deps factory gate.ts (grants identity, consume, readStatus,
#   flag default, viewer role, repo, HEAD, recipient; test/approval/gate-deps.test.ts builds the REAL factory); 12 sticky
#   enforcement for every tool, grants-required builders (an AST pin), push grant without a commit, grant-refused and
#   key-unavailable ops, the not_approved mapping and the consume-reject settle frame; 13 requestedByUserId / expiresAt payload
#   wiring (test/approval/gate-flow-payload.test.ts); 14 the Art. 17 erasure emitters' literal null first argument.
#
# Usage: bash apps/web-platform/test/approval-guard1-mutation.test.sh [--only <ERE over mutant ids>] [--list] [--check-anchors]
# Exit: 0 all verdicts as designed; 1 a finding; 2 setup failure; 3 inconclusive (a mutant could not be judged).
# Time: one targeted vitest file per mutant (~3-12 s each, ~25 min for the full table); the budget below is a WARN, never a verdict.
set -uo pipefail

WALL_BUDGET_S=3000
APP="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ONLY=""
LIST=0
CHECK_ANCHORS=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="${2:-}"; shift 2 ;;
    --list) LIST=1; shift ;;
    --check-anchors) CHECK_ANCHORS=1; shift ;;
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
# M(id, file, edits, test_file, kill=[exact failing test-name substrings], equivalent=<reason>|None, residual=<reason>|None)
# ---------------------------------------------------------------------------------------------------------------------
MUTANTS="$SB/mutants.json"
python3 - "$MUTANTS" <<'PYTBL'
import json, sys

def E(a, r, count=1, nth=None):
    return {"anchor": a, "replace": r, "count": count, "nth": nth}

TABLE = []
def M(id, file, edits, test, kill=None, equivalent=None, residual=None, blast=None):
    # blast = the largest failed/total fraction the row may legitimately cause (default 0.5, see the judge): a crash that
    # fails a whole file is never a kill, and a row whose designed detector is spread over most of the file says so here.
    TABLE.append({"id": id, "file": file, "edits": edits if isinstance(edits, list) else [edits],
                  "test": test, "kill": kill or [], "equivalent": equivalent, "residual": residual, "blast": blast})

GF = "server/approval/gate-flow.ts"
CANON = "server/approval/canonical.ts"
SVC = "server/approval/service.ts"
WAIT = "server/approval/waiters.ts"
TOOLS = "server/approval/tools.ts"
GRANTS = "server/approval/grants.ts"
DECIDE = "server/approval/decide.ts"
REATT = "server/approval/reattach.ts"
FLAG = "server/approval/flag.ts"
SQL = "supabase/migrations/180_approval_request.sql"
PC = "server/permission-callback.ts"
WSH = "server/ws-handler.ts"
GHT = "server/github-tools.ts"
PUSH = "server/push-branch.ts"
PROBE = "scripts/dev-probe-approval-gate.ts"
GD = "server/approval/gate.ts"
KBS = "server/kb-share-tools.ts"
WSET = "server/workspace-settings-tools.ts"
ACC = "server/account-delete.ts"

T_GF = "test/approval/gate-flow.test.ts"
T_RES = "test/approval/gate-flow-resolver-snapshot.test.ts"
T_CAN = "test/approval/canonical.test.ts"
T_WAIT = "test/approval/waiters.test.ts"
T_SVC = "test/approval/service.test.ts"
T_MIG = "test/approval/migration-180-approval-request.test.ts"
T_TC = "test/approval/tools-census.test.ts"
T_RC = "test/approval/runner-census.test.ts"
T_FLAG = "test/approval/flag.test.ts"
T_DB = "test/approval/decide-boundary.test.ts"
T_REND = "test/approval/render.test.ts"
T_GRANTS = "test/approval/grants.test.ts"
T_WS = "test/server/ws-handler-approval.test.ts"
T_BA = "test/build-allowed-tools-census.test.ts"
T_CLOSED = "test/approval/migration-180-decide-closed.test.ts"
T_DENYP = "test/approval/gate-flow-grant-deny-paths.test.ts"
T_PUSHG = "test/github-tools-push-grant.test.ts"
T_PINNED = "test/push-branch-pinned.test.ts"
T_EXG = "test/approval/execution-grant-handlers.test.ts"
T_GD = "test/approval/gate-deps.test.ts"
T_SINK = "test/approval/approval-ops-real-sink.test.ts"
T_OPSINK = "test/approval/ops-sink.test.ts"
T_PAY = "test/approval/gate-flow-payload.test.ts"
T_BGR = "test/approval/builder-grants-required.test.ts"
T_PCGB = "test/approval/permission-callback-gated-branch.test.ts"
T_AD = "test/account-delete.test.ts"
STATIC = "static:probe"

# Test-name fragments reused by several rows.
K_CONS = "the single atomic UPDATE has EXACTLY the expected conjunct set and SET clause, no OR, no bare true"
K_REASON = "the reason lookup reports the principal-change codes after expiry and before the bind mismatches"
K_DECIDE_CLEAN = "is tokenized-clean: Owner check before the row lock with one error for missing and non-owner, expiry above the decided blocks, closed on the pending path only"
K_REVOKE = "revokes an approved row through the deny decision and records who and when"
K_MACHINE = "encodes exactly the TypeScript status machine"
KEYUNAV = ["the hash key is a fail-closed dependency an unset pepper denies with the unavailable text, reports its OWN approval-key-unavailable op with the code, and creates nothing"]
K_CAPS = "caps pending requests (5 per conversation AP429, 20 per workspace AP430) only for a new request, before the INSERT"

# ---- 1. SQL consume predicate and decide_approval (tokenized offline backstop; S1-S10 representatives) ----------------
CONS = ("  UPDATE public.approval_request\n     SET status = 'consumed', consumed_at = now()\n   WHERE id = p_id\n     AND status = 'approved'\n"
        "     AND expires_at > now()\n     AND action_sha256 = p_hash\n     AND conversation_id = p_conversation\n"
        "     AND public.is_workspace_owner(workspace_id, decided_by)\n     AND public.is_workspace_member(workspace_id, requested_by_user_id)\n"
        "  RETURNING id INTO v_id;")
def cons(f):
    out = f(CONS)
    assert out != CONS
    return E(CONS, out)
def drop(line):
    return lambda s: s.replace(line, "")

M("G1-1a-sql-drop-hash-conjunct", SQL, cons(drop("     AND action_sha256 = p_hash\n")), T_MIG, [K_CONS])
M("G1-1b-sql-drop-conversation-conjunct", SQL, cons(drop("     AND conversation_id = p_conversation\n")), T_MIG, [K_CONS])
M("G1-2a-sql-consume-accepts-expired", SQL, cons(drop("     AND expires_at > now()\n")), T_MIG, [K_CONS])
M("G1-3a-sql-consume-not-single-use", SQL, cons(lambda s: s.replace("SET status = 'consumed', consumed_at = now()", "SET consumed_at = now()")), T_MIG, [K_CONS])
M("G1-3b-sql-consume-without-approved-conjunct", SQL, cons(drop("     AND status = 'approved'\n")), T_MIG, [K_CONS])
M("G1-3e-sql-consume-without-decider-owner-recheck", SQL, cons(drop("     AND public.is_workspace_owner(workspace_id, decided_by)\n")), T_MIG, [K_CONS])
M("G1-3f-sql-consume-without-requester-member-recheck", SQL, cons(drop("     AND public.is_workspace_member(workspace_id, requested_by_user_id)\n")), T_MIG, [K_CONS])
M("G1-S1-sql-hash-or-true", SQL, cons(lambda s: s.replace("AND action_sha256 = p_hash", "AND (action_sha256 = p_hash OR true)")), T_MIG, [K_CONS])
M("G1-S2-sql-status-or-pending", SQL, cons(lambda s: s.replace("     AND status = 'approved'\n", "     AND status = 'approved' OR status = 'pending'\n")), T_MIG, [K_CONS])
M("G1-S3-sql-expiry-window-widened", SQL, cons(lambda s: s.replace("expires_at > now()", "expires_at > now() - interval '1000 years'")), T_MIG, [K_CONS])
M("G1-S4-sql-hash-conjunct-commented-out", SQL, cons(lambda s: s.replace("     AND action_sha256 = p_hash\n", "     AND true -- action_sha256 = p_hash\n")), T_MIG, [K_CONS])
M("G1-S4b-sql-conversation-conjunct-block-commented", SQL, cons(lambda s: s.replace("     AND conversation_id = p_conversation\n", "     AND true /* conversation_id = p_conversation */\n")), T_MIG, [K_CONS])
M("G1-S10-sql-where-id-or-true", SQL, cons(lambda s: s.replace("WHERE id = p_id", "WHERE (id = p_id OR true)")), T_MIG, [K_CONS])
M("G1-3g-sql-reason-drops-decider-arm", SQL, E("    WHEN NOT COALESCE(public.is_workspace_owner(v_row.workspace_id, v_row.decided_by), false) THEN 'decider_not_owner'\n", ""), T_MIG, [K_REASON])
M("G1-N6-sql-status-read-widened", SQL, E("SELECT * INTO v_row FROM public.approval_request WHERE id = p_id;\n  IF NOT FOUND THEN\n    RETURN NULL;", "SELECT * INTO v_row FROM public.approval_request WHERE (id = p_id OR true);\n  IF NOT FOUND THEN\n    RETURN NULL;"), T_MIG, ["get_approval_status reports the row's own status, never a literal"])
M("G1-N7-sql-consume-reason-lookup-widened", SQL, E("SELECT * INTO v_row FROM public.approval_request WHERE id = p_id;\n  v_reason := CASE", "SELECT * INTO v_row FROM public.approval_request WHERE (id = p_id OR true);\n  v_reason := CASE"), T_MIG, ["consume releases ONLY on the matched UPDATE (IF v_id IS NOT NULL ... 'consumed', true) and every other path ends in 'consumed', false"])
M("G1-2b-sql-decide-accepts-overdue", SQL, E("  IF v_row.status IN ('pending', 'approved') AND v_row.expires_at <= now() THEN", "  IF FALSE THEN"), T_MIG, [K_DECIDE_CLEAN])
M("G1-2c-sql-create-keeps-overdue-live-row", SQL, E("       AND status IN ('pending', 'approved')\n       AND expires_at <= now()\n    RETURNING id, workspace_id", "       AND status IN ('pending', 'approved')\n    RETURNING id, workspace_id"), T_MIG, ["expires an overdue live row for the same action before inserting"])
M("G1-3c-sql-hash-column-not-write-once", SQL, E("     OR NEW.action_sha256 IS DISTINCT FROM OLD.action_sha256\n", ""), T_MIG, ["makes the identity, decision and revoke columns write-once"])
M("G1-3d-sql-status-machine-reopens-consumed", SQL, E("       ('approved', 'consumed'),\n", "       ('approved', 'consumed'),\n       ('consumed', 'approved'),\n"), T_MIG, [K_MACHINE])
M("G1-4-sql-decide-without-owner-check", SQL, E("  v_ok := FOUND AND COALESCE(public.is_workspace_owner(v_ws, auth.uid()), false);", "  v_ok := FOUND;"), T_MIG, [K_DECIDE_CLEAN])
M("G1-4b-sql-decide-owner-polarity-inverted", SQL, E("  v_ok := FOUND AND COALESCE(public.is_workspace_owner(v_ws, auth.uid()), false);", "  v_ok := FOUND AND NOT COALESCE(public.is_workspace_owner(v_ws, auth.uid()), false);"), T_MIG, [K_DECIDE_CLEAN])
K_CLOSED = "reads the archived state of the request's own conversation and refuses a missing or archived one before any pending write"
M("G1-9-sql-decide-ignores-archived-conversation", SQL, E("  SELECT (c.archived_at IS NOT NULL) INTO v_closed", "  SELECT false INTO v_closed"), T_CLOSED, [K_CLOSED], blast=0.6)
M("G1-9b-sql-decide-closed-flag-never-refuses", SQL, E("  IF NOT FOUND OR v_closed THEN", "  IF NOT FOUND THEN"), T_CLOSED, [K_CLOSED])
# Revoke (CTO ruling 2): the approved -> rejected edge in the trigger, the decide deny branch, and the TypeScript machine.
M("G1-RV1-sql-trigger-drops-the-revoke-edge", SQL, E("       ('approved', 'expired'),\n       ('approved', 'rejected')\n", "       ('approved', 'expired')\n"), T_MIG, [K_MACHINE])
M("G1-RV2-sql-decide-deny-no-longer-revokes", SQL, E("       SET status = 'rejected', revoked_at = now(), revoked_by = auth.uid()\n", "       SET status = 'approved', revoked_at = now(), revoked_by = auth.uid()\n"), T_MIG, [K_REVOKE])
M("G1-RV3-ts-machine-drops-the-revoke-edge", SVC, E('  ["approved", "rejected"],\n', ""), T_SVC, ["allows exactly pending->approved|rejected|expired, approved->consumed|expired and the Owner revoke approved->rejected"])
M("G1-RV4-decide-outcome-revoked-unknown", DECIDE, E('"conflict", "revoked", "expired"', '"conflict", "expired"'), T_SVC, ["maps every outcome and keeps the not-authorised error distinct"])
# Pending caps (CTO ruling 4)
M("G1-CAP1-sql-conversation-cap-dropped", SQL, E("""    IF (SELECT count(*) FROM public.approval_request
         WHERE conversation_id = p_conversation_id AND status = 'pending' AND expires_at > now()) >= 5 THEN
      RAISE EXCEPTION 'approval: too many pending requests' USING ERRCODE = 'AP429';
    END IF;
""", ""), T_MIG, [K_CAPS])
M("G1-CAP2-sql-workspace-cap-dropped", SQL, E("""    IF (SELECT count(*) FROM public.approval_request
         WHERE workspace_id = p_workspace_id AND status = 'pending' AND expires_at > now()) >= 20 THEN
      RAISE EXCEPTION 'approval: too many pending requests' USING ERRCODE = 'AP430';
    END IF;
""", ""), T_MIG, [K_CAPS])
M("G1-CAP3-service-cap-code-not-mapped", SVC, E('if (code === "AP429" || code === "AP430") throw new ApprovalCapReachedError("create_approval_request", code);\n', ""), T_SVC, ["maps the pending-cap SQLSTATEs to a typed ApprovalCapReachedError (AP429 conversation, AP430 workspace)"])
M("G1-CAP4-gate-cap-reached-allows", GF, E('a.logDecision(a.toolName, "deny", "too many pending approval requests");\n        return deny(APPROVAL_TOO_MANY_PENDING_DENY);', 'a.logDecision(a.toolName, "deny", "too many pending approval requests");\n        return a.allow(snapshot);'), T_GF, ["pending caps AP429 -> static too-many-pending deny", "pending caps AP430 -> static too-many-pending deny"])

# ---- 2. Canonical object and keyed hash (the hashed bytes are the executed bytes) ----------------------------------------
M("G1-C1-canonicalize-without-sorting", CANON, E("for (const k of Object.keys(value as object).sort())", "for (const k of Object.keys(value as object))"), T_CAN, ["sorts keys recursively and is stable across key order"])
M("G1-C2-hash-drops-tool-name", CANON, E("    tool_name: input.toolName,\n", ""), T_CAN, ["hashes a real canonicalised action to the externally computed HMAC, and NOT to the unkeyed sha256"])
M("G1-C3-hash-drops-conversation", CANON, E("    conversation_id: input.conversationId,\n", ""), T_CAN, ["binds the tool name, the workspace and the conversation into the hash"])
M("G1-C4-hash-drops-workspace", CANON, E("    workspace_id: input.workspaceId,\n", ""), T_CAN, ["binds the tool name, the workspace and the conversation into the hash"])
M("G1-C5-strings-are-trimmed", CANON, E('    case "string":\n    case "boolean":\n      return value;', '    case "string":\n      return value.trim();\n    case "boolean":\n      return value;'), T_CAN, ["does not trim: surrounding whitespace is part of the action and of the hash"])
M("G1-C6-default-not-applied", CANON, E('force: z.boolean().default(false)', 'force: z.boolean().optional()'), T_CAN, ["github_push_branch treats a zod default and its omission as the same action", "handlerArgsKey (execution-grant key a tool handler can recompute) applies the same zod defaults as the gate"])
M("G1-C7-server-derived-optional", CANON, E('if (!parsedServer.success) throw new ApprovalCanonicalError("invalid_server_derived");', 'if (!parsedServer.success) server = {};\n    else'), T_CAN, ["refuses to canonicalize without every server-derived field"])
M("G1-C8-hash-accepts-non-uuid-binding", CANON, E("if (!isUuid(input.workspaceId) || !isUuid(input.conversationId)) {", "if (false) {"), T_CAN, ["rejects ids that are not UUID-shaped"])
M("G1-C9-non-finite-number-hashed", CANON, E('if (!Number.isFinite(value)) throw new ApprovalCanonicalError("not_canonical");\n      return value;', "return value;"), T_CAN, ["rejects values that have no canonical form instead of coercing them"])
M("G1-C10-reply-recipient-unbound", CANON, E("server: z.object({ recipient: nonEmpty }),", "server: null,"), T_CAN, ["email_reply binds the server-derived recipient that is absent from the model input"])
M("G1-C11-pushed-commit-unbound", CANON, E("server: z.object({ repo: nonEmpty, headSha: sha }),", "server: z.object({ repo: nonEmpty }),"), T_CAN, ["github_push_branch is versioned and carries every input and server-derived field"])
M("G1-C12-reply-to-field-stripped", CANON, E("      replyTo: z.string().optional(),\n", ""), T_CAN, ["email_send is versioned and carries every input and server-derived field"])
M("G1-C13-hash-ignores-action-tool-mismatch", CANON, E("if (input.toolName !== input.action.tool || !APPROVAL_REQUIRED_TOOLS", "if (!APPROVAL_REQUIRED_TOOLS"), T_CAN, ["rejects a tool name that is not the action's tool"])
# Keyed hash (CTO ruling 5): the fail-closed key dependency.
M("G1-K1-unset-pepper-falls-back-to-unkeyed-hash", CANON, [
    E('import { createHmac, hkdfSync } from "node:crypto";', 'import { createHash, createHmac, hkdfSync } from "node:crypto";'),
    E('  return createHmac("sha256", deriveApprovalHashKey(pepper)).update(text, "utf8").digest("hex");',
      '  if (!(pepper ?? process.env.SENTRY_USERID_PEPPER)) return createHash("sha256").update(text, "utf8").digest("hex");\n  return createHmac("sha256", deriveApprovalHashKey(pepper)).update(text, "utf8").digest("hex");')],
  T_CAN, ["FAILS CLOSED when the pepper is unset or empty: key_unavailable, never an unkeyed hash"])
M("G1-K2-key-unavailable-not-raised", CANON, E('if (!pepper) throw new ApprovalCanonicalError("key_unavailable");', 'if (!pepper) pepper = "unset";'), T_CAN, ["FAILS CLOSED when the pepper is unset or empty: key_unavailable, never an unkeyed hash"])
M("G1-K3-hash-is-the-unkeyed-sha256", CANON, [
    E('import { createHmac, hkdfSync } from "node:crypto";', 'import { createHash, createHmac, hkdfSync } from "node:crypto";'),
    E('  return createHmac("sha256", deriveApprovalHashKey(pepper)).update(text, "utf8").digest("hex");', '  void createHmac;\n  return createHash("sha256").update(text, "utf8").digest("hex");')],
  T_CAN, ["hashes a real canonicalised action to the externally computed HMAC, and NOT to the unkeyed sha256"])
M("G1-K4-key-domain-separation-changed", CANON, E('const HASH_KEY_INFO = "soleur:approval-request:action-sha256:v1";', 'const HASH_KEY_INFO = "soleur:approval-request:action-sha256:v2";'), T_CAN, ["derives the key by HKDF-SHA256 from the pepper (known answer)"])
M("G1-K5-gate-key-failure-is-not-a-deny", GF, E('      a.logDecision(a.toolName, "deny", "approval bind failed");\n      return deny(APPROVAL_UNAVAILABLE_DENY);\n    }\n    if (aborted()) return denyAborted();', '      a.logDecision(a.toolName, "deny", "approval bind failed");\n      return a.allow(snapshot);\n    }\n    if (aborted()) return denyAborted();'), T_GF, KEYUNAV)
M("G1-K6-hkdf-derivation-skipped-pepper-used-as-the-key", CANON, E('return Buffer.from(hkdfSync("sha256", Buffer.from(pepper, "utf8"), Buffer.alloc(0), HASH_KEY_INFO, 32));', 'void hkdfSync;\n  return Buffer.from(pepper, "utf8");'), T_CAN, ["derives the key by HKDF-SHA256 from the pepper (known answer)"])
M("G1-K7-hkdf-unset-pepper-derives-an-empty-key", CANON, E('if (!pepper) throw new ApprovalCanonicalError("key_unavailable");', 'if (!pepper) return Buffer.alloc(0);'), T_CAN, ["FAILS CLOSED when the pepper is unset or empty: key_unavailable, never an unkeyed hash"])
M("G1-K8-key-unavailable-reported-under-the-shared-gate-failure-op", GF, E('reportApprovalOp("keyUnavailable", null, { ...op, extra: { code } });', 'reportApprovalOp("gateFailed", null, { ...op, extra: { code } });'), T_GF, KEYUNAV)

# ---- 3. The gated flow: allow() input, snapshot, card source, binding ------------------------------------------------------
GRANT_PUT = "putGrant(a.approval.grants, a.toolName, snapshot, { workspaceId: a.approval.workspaceId, headSha: derived?.headSha });"
M("G1-8a-allow-live-input-on-reproposal", GF, E("return allowWithGrant();", "return (" + GRANT_PUT.rstrip(";") + ", a.allow(a.toolInput));", count=2, nth=1), T_GF, ["the re-proposal release also hands allow() the snapshot, never the live object"])
M("G1-8b-allow-live-input-on-live-wait", GF, E("return allowWithGrant();", "return (" + GRANT_PUT.rstrip(";") + ", a.allow(a.toolInput));", count=2, nth=2), T_GF, ["the allowed input is a deep clone of what was hashed, never the live object (mutation row 8)"])
M("G1-8c-snapshot-is-an-alias", GF, E("snapshot = structuredClone(a.toolInput);", "snapshot = a.toolInput;"), T_GF, ["the allowed input is a deep clone of what was hashed, never the live object (mutation row 8)"])
M("G1-8d-unbound-input-not-denied", GF, E("if (!isCoveredByCanonical(snapshot, action.fields)) {", "if (false) {"), T_GF, ["an input with a field the canonical action does not cover is denied (unbound input), nothing is requested"])
M("G1-8e-resolver-gets-the-live-input", GF, E("derived = await a.approval.resolveServerDerived(a.toolName, snapshot);", "derived = await a.approval.resolveServerDerived(a.toolName, a.toolInput);"), T_RES, ["resolveServerDerived receives the snapshot, not the live input", "the resolver's argument is also detached from the live object for a nested mutation"], blast=1.0)  # the file IS the detector: 3 tests, all about this argument
M("G1-6-card-built-from-tool-input", GF, E("view: renderApprovalView(action),", "view: renderApprovalView({ ...action, fields: snapshot as never }),"), T_GF, ["the card frame is built from the canonical object and carries no option strings"])
M("G1-1c-consume-binds-a-different-hash", GF, E("const c = await a.approval.consume({ id: approvalId, hash, conversationId: a.conversationId });", 'const c = await a.approval.consume({ id: approvalId, hash: "0".repeat(64), conversationId: a.conversationId });'), T_GF, ["approve in window -> exactly one consume with the independently computed hash -> allow"])
M("G1-5a-allow-on-wait-timeout", GF, E('a.logDecision(a.toolName, "deny", "approval wait ended undecided");\n          return deny(APPROVAL_PENDING_DENY);', 'a.logDecision(a.toolName, "deny", "approval wait ended undecided");\n          return a.allow(snapshot);'), T_GF, ["timeout denies with the 'saved, do not retry now' text, leaves the row pending and mirrors one op with the approval id"])
M("G1-5b-allow-on-abort", GF, E('if (selection === null || selection === "aborted" || aborted()) return denyAborted();', 'if (selection === null || selection === "aborted" || aborted()) return a.allow(snapshot);'), T_GF, ["abort during the wait denies, leaves the row pending, and an approval that arrives afterwards is never honoured"])
M("G1-5c-allow-when-the-wait-throws", GF, E('if (selection === null || selection === "aborted" || aborted()) return denyAborted();', 'if (selection === null) return a.allow(snapshot);\n      if (selection === "aborted" || aborted()) return denyAborted();'), T_GF, ["abort during the wait denies, leaves the row pending, and an approval that arrives afterwards is never honoured"])
M("G1-5d-no-abort-check-after-consume", GF, E('          if (wasAborted) {\n            reportApprovalOp("consumedAborted", null, { ...ctx, extra: { path: "live" } });\n            return denyAborted(true);\n          }\n', ""), T_GF, ["a session that dies while the consume is in flight is a deny (the approval is spent for nothing)"])
M("G1-5e-allow-on-unexpected-throw", GF, E('a.logDecision(a.toolName, "deny", "approval flow failed");\n    return deny(APPROVAL_UNAVAILABLE_DENY);', 'a.logDecision(a.toolName, "deny", "approval flow failed");\n    return a.allow(a.toolInput);'), T_GF, ["a fault anywhere else in the flow (here: the decision logger, after the consume) denies and reports, never allows"])
M("G1-5f-allow-when-consume-throws", GF, E('} catch (err) {\n            consumed = false;\n            reason = "rpc_error";\n            consumeError = err;\n          }', '} catch (err) {\n            consumed = true;\n            reason = "rpc_error";\n            consumeError = err;\n          }'), T_GF, ["a consume that rejects at the dependency boundary (not just inside the service) is a deny"])
M("G1-5g-truthy-consume-is-an-allow", GF, E("consumed = c.consumed === true;", "consumed = Boolean(c.consumed);"), T_GF, ["only a boolean true from consume is an allow (a truthy string is not)"])
M("G1-5h-no-abort-check-before-submit", GF, E("    if (aborted()) return denyAborted();\n\n    // 3. Create-or-find", "\n    // 3. Create-or-find"), T_GF, ["an abort that lands while the server-derived fields resolve creates no request"])
M("G1-5i-no-abort-check-at-entry", GF, E("    if (aborted()) return denyAborted();\n\n    // 1. The fields", "\n    // 1. The fields"), T_GF, ["an already-aborted call performs no database read and cannot allow"])
M("G1-R1-allow-on-owner-rejection", GF, E('a.logDecision(a.toolName, "deny", "approval rejected by the owner");\n          return deny(APPROVAL_REJECTED_DENY);', 'a.logDecision(a.toolName, "deny", "approval rejected by the owner");\n          return a.allow(snapshot);'), T_GF, ["a rejected request denies with the static text and never consumes"])
M("G1-R2-allow-on-expired", GF, E('a.logDecision(a.toolName, "deny", "approval expired");\n          return deny(APPROVAL_EXPIRED_DENY);', 'a.logDecision(a.toolName, "deny", "approval expired");\n          return a.allow(snapshot);'), T_GF, ["a request that expires while the agent waits denies with the expiry text and never consumes"])
M("G1-R3-allow-on-already-consumed", GF, E('a.logDecision(a.toolName, "deny", "approval already consumed");\n          return deny(APPROVAL_CONSUME_REJECTED_DENY);', 'a.logDecision(a.toolName, "deny", "approval already consumed");\n          return a.allow(snapshot);'), T_GF, ["a request that another identical call already consumed denies and never consumes again"])
M("G1-R4-allow-on-unknown-outcome", GF, E('a.logDecision(a.toolName, "deny", "approval outcome unknown");\n          return deny(APPROVAL_UNAVAILABLE_DENY);', 'a.logDecision(a.toolName, "deny", "approval outcome unknown");\n          return a.allow(snapshot);'), T_GF, equivalent="the default arm of the verdict switch is unreachable: the wait returns only decided|timeout|aborted, waitForDecision never returns 'pending' or null as decided, every decided status it can return has its own arm, and aborted/null are handled before the switch; the arm is defence in depth and no input shape reaches it")
M("G1-R5-allow-on-rejected-reproposal-consume", GF, E('a.logDecision(a.toolName, "deny", "approval consume rejected");\n        return deny(consumeRejectedDeny(shown));', 'a.logDecision(a.toolName, "deny", "approval consume rejected");\n        return a.allow(snapshot);'), T_GF, ["a late approval whose consume is rejected on re-proposal denies and reports the rejection"])
M("G1-R6-allow-on-not-waitable", GF, E('a.logDecision(a.toolName, "deny", "approval request not waitable");\n        return deny(APPROVAL_UNAVAILABLE_DENY);', 'a.logDecision(a.toolName, "deny", "approval request not waitable");\n        return a.allow(snapshot);'), T_GF, ["a request that is neither pending nor approved is not waitable: deny"])
M("G1-R7-allow-when-request-not-created", GF, E('a.logDecision(a.toolName, "deny", "approval request not created");\n      return deny(APPROVAL_UNAVAILABLE_DENY);', 'a.logDecision(a.toolName, "deny", "approval request not created");\n      return a.allow(snapshot);'), T_GF, ["the request cannot be created: deny, approval-create-failed, no card, no hold, static text only"])
M("G1-R8-allow-when-bind-fails", GF, E('a.logDecision(a.toolName, "deny", "approval bind failed");\n      return deny(APPROVAL_UNAVAILABLE_DENY);\n    }\n\n    // 2.', 'a.logDecision(a.toolName, "deny", "approval bind failed");\n      return a.allow(snapshot);\n    }\n\n    // 2.'), T_GF, ["server-derived fields that cannot be resolved: deny, approval-bind-failed, nothing requested"])
M("G1-R9-card-viewer-falls-back-to-owner", GF, E('viewerRole = "member"; // read-only card is the safe default', 'viewerRole = "owner"; // read-only card is the safe default'), T_GF, ["a viewer-role read failure is reported once and the card falls back to the read-only member view"])
# Principal re-check text mapping (CTO ruling 3)
M("G1-PR1-decider-not-owner-has-no-own-text", GF, E('    case "decider_not_owner":\n    case "requester_not_member":\n      return APPROVAL_PRINCIPAL_CHANGED_DENY;\n', '    case "requester_not_member":\n      return APPROVAL_PRINCIPAL_CHANGED_DENY;\n'), T_GF, ["consume reasons map to their own static text decider_not_owner", "a live consume rejected because the decider is no longer an Owner denies with the principal-changed text"])
M("G1-PR2-requester-not-member-has-no-own-text", GF, E('    case "decider_not_owner":\n    case "requester_not_member":\n      return APPROVAL_PRINCIPAL_CHANGED_DENY;\n', '    case "decider_not_owner":\n      return APPROVAL_PRINCIPAL_CHANGED_DENY;\n'), T_GF, ["consume reasons map to their own static text requester_not_member"])
# Execution grants (CTO ruling 1)
M("G1-X1-grant-write-dropped-before-allow", GF, E("      putGrant(a.approval.grants, a.toolName, snapshot, { workspaceId: a.approval.workspaceId, headSha: derived?.headSha });\n", ""), T_GF, ["the grant is written BEFORE allow(): if writing it fails the call is a deny, never an allow without a grant", "live approved path: the grant carries the approved headSha and workspace, keyed by the handler args, and is in place when allow() runs", "released (re-proposal) path: the same grant is written"])
M("G1-X2-enforcing-never-set", GF, E("  a.approval.grants.enforcing = true;\n", ""), T_GF, ["the flag turning on marks the session enforcing; a flag-off call leaves it untouched"])
M("G1-X3-grant-drops-the-approved-commit", GF, E("headSha: derived?.headSha });", "headSha: undefined });"), T_GF, ["live approved path: the grant carries the approved headSha and workspace, keyed by the handler args, and is in place when allow() runs"])
M("G1-X5-grant-written-on-a-reproposal-consume-rejection", GF, E('a.logDecision(a.toolName, "deny", "approval consume rejected");\n        return deny(consumeRejectedDeny(shown));', 'a.logDecision(a.toolName, "deny", "approval consume rejected");\n        putGrant(a.approval.grants, a.toolName, snapshot, { workspaceId: a.approval.workspaceId });\n        return deny(consumeRejectedDeny(shown));'), T_DENYP, ["a deny writes no execution grant (every deny path of the gate) re-proposal consume rejected (submit answers consume_rejected): deny, no allow(), no grant, session enforcing"])
M("G1-X5b-grant-written-on-a-live-consume-rejection", GF, E('a.logDecision(a.toolName, "deny", "approval consume rejected");\n            return deny(consumeRejectedDeny(shown));', 'a.logDecision(a.toolName, "deny", "approval consume rejected");\n            putGrant(a.approval.grants, a.toolName, snapshot, { workspaceId: a.approval.workspaceId });\n            return deny(consumeRejectedDeny(shown));'), T_GF, ["a consume rejection, a cap and an aborted call never write a grant"])
M("G1-X5c-grant-written-on-an-owner-rejection", GF, E('a.logDecision(a.toolName, "deny", "approval rejected by the owner");\n          return deny(APPROVAL_REJECTED_DENY);', 'a.logDecision(a.toolName, "deny", "approval rejected by the owner");\n          putGrant(a.approval.grants, a.toolName, snapshot, { workspaceId: a.approval.workspaceId });\n          return deny(APPROVAL_REJECTED_DENY);'), T_DENYP, ["Owner rejected while the agent waited: deny, no allow(), no grant, session enforcing"])
M("G1-X5d-grant-written-on-a-wait-timeout", GF, E('a.logDecision(a.toolName, "deny", "approval wait ended undecided");\n          return deny(APPROVAL_PENDING_DENY);', 'a.logDecision(a.toolName, "deny", "approval wait ended undecided");\n          putGrant(a.approval.grants, a.toolName, snapshot, { workspaceId: a.approval.workspaceId });\n          return deny(APPROVAL_PENDING_DENY);'), T_DENYP, ["nobody decided before the wait deadline: deny, no allow(), no grant, session enforcing"])
M("G1-X6-push-handler-ignores-the-grant-commit", GHT, E('commitSha: grant.kind === "granted" ? grant.binding.headSha : undefined,', "commitSha: undefined,"), T_PUSHG, ["a grant pins the approved commit: pushBranch gets commitSha = the approved headSha"])
M("G1-X7-push-handler-runs-without-a-grant", GHT, E('if (grant.kind === "refuse") return grantRefusalResponse("grant_missing");', 'if (false) return grantRefusalResponse("grant_missing");'), T_PUSHG, ["enforcing and no grant: refuses with the grant-missing text and pushes nothing"])
M("G1-X8-push-ignores-the-pinned-commit", PUSH, E('`${commitSha ?? "HEAD"}:refs/heads/${branch}`', '`HEAD:refs/heads/${branch}`'), T_PINNED, ["approve at A, HEAD moves to B: the remote branch ends at A, not B"])
M("G1-X9-push-pinned-commit-not-verified", PUSH, E('execFileSync("git", ["cat-file", "-e", `${commitSha}^{commit}`], { cwd: workspacePath, stdio: "pipe" });', "void 0;"), T_PINNED, ["a sha that is absent from the repository throws and the remote branch is not created"])
M("G1-X10-check-grant-does-not-refuse-when-enforcing", GRANTS, E('if (!grants.enforcing) return { kind: "legacy" };', 'return { kind: "legacy" };'), T_GRANTS, ["checkGrant enforcing and no grant: refuse (the sticky flag fails closed)"])
M("G1-X11-grant-is-not-one-shot", GRANTS, E("    if (!e) return null;\n    this.entries.delete(id);\n", "    if (!e) return null;\n"), T_GRANTS, ["ExecutionGrants take is one-shot"])
M("G1-X12-grant-never-expires", GRANTS, E("return e.expiresAt > this.now() ? e.binding : null;", "return e.binding;"), T_GRANTS, ["ExecutionGrants a grant expires after 120 s and the expired read still consumes it"])
M("G1-X13-grant-map-unbounded", GRANTS, E("while (this.entries.size > GRANT_MAX_ENTRIES) {", "while (false) {"), T_GRANTS, ["ExecutionGrants the map is capped at 64 entries and the oldest is dropped"])
M("G1-X14-kb-share-ignores-a-changed-workspace", "server/kb-share-tools.ts", E('if (grant.kind === "granted" && grant.binding.workspaceId !== workspaceId) {', "if (false) {"), T_EXG, ["kb_share_create the active workspace changed after approval: refused with workspace_changed, createShare never called"])
M("G1-X15-autonomous-ignores-a-changed-workspace", "server/workspace-settings-tools.ts", E("if (current !== grant.binding.workspaceId) {", "if (false) {"), T_EXG, ["workspace_set_autonomous approved on W1 but the active workspace is W2: refused with workspace_changed, setBashAutonomous never called"])

# ---- 4. Flag-off fail-closed ------------------------------------------------------------------------------------------------
M("G1-F1-flag-read-error-turns-flow-on", GF, E("} catch {\n    enabled = false;\n  }", "} catch {\n    enabled = true;\n  }"), T_GF, ["absent, disabled and a throwing flag read behave identically"])
M("G1-F2-flag-off-still-runs-the-flow", GF, E("if (!enabled) {", "if (false) {"), T_GF, ["absent, disabled and a throwing flag read behave identically"])
M("G1-F3-flag-module-fails-open", FLAG, E("    return false;\n  }\n}", "    return true;\n  }\n}"), T_FLAG, ["isApprovalQueueEnabled fails closed when the flag read throws"])
M("G1-F4-flag-wrong-name", FLAG, E('getRuntimeFlag("approval-queue"', 'getRuntimeFlag("approval-queu"'), T_FLAG, ["isApprovalQueueEnabled reads the approval-queue flag with the workspace as the segment identity"])
M("G1-F5-flag-truthy-is-on", GF, E("enabled = (await a.approval.isEnabled()) === true;", "enabled = (await a.approval.isEnabled()) !== false;"), T_GF, residual="the flag client returns booleans; a non-boolean flag value turning the flow on is unpinned (the throwing and false reads are pinned by F1/F2)")
M("G1-F6-reattach-reads-flag-without-workspace", REATT, E("isApprovalQueueEnabled({ userId: a.userId, workspaceId: w })", "isApprovalQueueEnabled({ userId: a.userId, workspaceId: null as never })"), T_WS, ["reattach re-send attach site: resume_stream a workspace-scoped cohort: the card is re-sent for the cohort's workspace and the flag was read WITH a workspace"])

# ---- 5. The permission-callback gated branch ---------------------------------------------------------------------------------
# PC1/PC2 sit on the chokepoint every createCanUseTool-driven gate test passes through, so gate-flow.test.ts goes red wholesale (a crash-shaped signal, not an
# attribution). Their detector is the small permission-callback-gated-branch.test.ts: exactly ONE of its three tests goes red on either edit.
M("G1-PC1-gated-branch-never-calls-the-gate", PC, E("if (deps.approval && isApprovalRequiredTool(toolName)) {", "if (false && deps.approval && isApprovalRequiredTool(toolName)) {"), T_PCGB, ["the gated branch of createCanUseTool an approval-required tool with the flag on is handed to the approval gate and returns the gate's verdict"])
M("G1-PC2-gate-verdict-discarded", PC, E("if (approvalVerdict !== null) return approvalVerdict;", ""), T_PCGB, ["the gated branch of createCanUseTool an approval-required tool with the flag on is handed to the approval gate and returns the gate's verdict"])

# ---- 6. Service wrappers (consume contract, re-proposal consume: matrix row 11) ------------------------------------------------
M("G1-11a-approved-row-not-consumed-on-create", SVC, E('if (r.approval.status === "approved") {', 'if (false && r.approval.status === "approved") {'), T_SVC, ["an approved live row is consumed immediately, with no card and no wait"])
M("G1-11b-approved-row-returned-to-the-wait-loop", SVC, [E('if (r.approval.status === "approved") {', 'if (false && r.approval.status === "approved") {'), E('if (r.approval.status === "pending") {', 'if (r.approval.status === "pending" || r.approval.status === "approved") {')], T_GF, ["row 11: a live row that is already approved is consumed at once, with no card and no wait"])
M("G1-1d-consume-rpc-drops-conversation", SVC, E("p_conversation: p.conversationId }", "p_conversation: p.id }"), T_SVC, ["passes id, hash and conversation and reports consumed once"])
M("G1-1e-consume-rpc-drops-hash", SVC, E("p_hash: p.hash,", "p_hash: p.id,"), T_SVC, ["passes id, hash and conversation and reports consumed once"])
M("G1-5j-allow-when-consume-rpc-errors", SVC, E('if (res.error) return { consumed: false, reason: "rpc_error", ...(res.error.code ? { code: res.error.code } : {}) };', "if (res.error) return { consumed: true };"), T_SVC, ["fails closed: an rpc error, a null payload or an unknown shape is a rejection, never a consume"])
M("G1-5k-allow-when-consume-rpc-throws", SVC, E('} catch (e) {\n    return { consumed: false, reason: "rpc_error", ...(e instanceof Error && e.name ? { code: e.name } : {}) };\n  }', '} catch (e) {\n    return { consumed: true };\n  }'), T_GF, ["a consume that throws, or answers with anything but boolean true, is a deny"])
M("G1-5l-truthy-rpc-payload-consumes", SVC, E("if (isObj(d) && d.consumed === true) return { consumed: true };", "if (isObj(d) && d.consumed) return { consumed: true };"), T_SVC, ["fails closed: an rpc error, a null payload or an unknown shape is a rejection, never a consume"])
M("G1-1f-malformed-hash-reaches-the-database", SVC, E('if (!HASH_RE.test(p.hash)) return { consumed: false, reason: "bad_request" };', ""), T_SVC, ["refuses to call the rpc with a hash that is not 64 lowercase hex (never consume on a malformed bind)"])

# ---- 7. The wait loop -----------------------------------------------------------------------------------------------------------
M("G1-W1-transient-read-error-decides-approved", WAIT, E("          readErrors += 1;\n          lastReadError = err;\n        }", '          return { kind: "decided", status: "approved" };\n        }'), T_WAIT, ["waitForDecision a transient read error continues until the deadline and never allows"])
M("G1-W2-abort-not-checked-first", WAIT, E('      if (deps.signal.aborted) return { kind: "aborted", readErrors, lastReadError };\n\n      if (reads < MAX_POLL_READS)', "      if (reads < MAX_POLL_READS)"), T_WAIT, ["waitForDecision checks the signal first: an already aborted signal does not read at all"])
M("G1-W3-timeout-reads-as-approved", WAIT, E('if (remaining <= 0 || reads >= MAX_POLL_READS) return { kind: "timeout", readErrors, lastReadError };', 'if (remaining <= 0 || reads >= MAX_POLL_READS) return { kind: "decided", status: "approved" };'), T_WAIT, ["waitForDecision times out undecided after the deadline and leaves the verdict to the caller (row stays pending)"])
M("G1-W4-wake-is-a-verdict", WAIT, E('if (r === "woken") wake = undefined;', 'if (r === "woken") return { kind: "decided", status: "approved" };'), T_WAIT, ["waitForDecision an in-memory wake on this host short-circuits the sleep and is confirmed by one database read"])
M("G1-W5-pending-read-counts-as-decided", WAIT, E('if (s && s !== "pending") return { kind: "decided", status: s };', 'if (s) return { kind: "decided", status: s as never };'), T_WAIT, ["waitForDecision times out undecided after the deadline and leaves the verdict to the caller (row stays pending)", "waitForDecision the wake is a hint only: a woken 'approved' with a database row still pending is not an allow"])
M("G1-W6-abort-during-sleep-not-honoured", WAIT, E('if (r === "aborted" || deps.signal.aborted) return { kind: "aborted", readErrors, lastReadError };', 'if (false) return { kind: "aborted", readErrors, lastReadError };'), T_WAIT, equivalent="the next loop iteration begins with the signal check before any read, so dropping the post-race abort check only adds one no-op iteration; surveyed abort points: before the loop, during a read, during the sleep, after the wake; each ends in the same aborted result with no extra read")

# ---- 8. Tool set and census (matrix row 7; Guard 2 rows) --------------------------------------------------------------------------
M("G1-7a-slice1-tool-removed-from-required-set", TOOLS, E("  `${P}workspace_set_autonomous`,\n] as const;", "] as const;"), T_TC, ["slice-1 tool set is exactly the eight tools of the spec (fully qualified names)"])
M("G1-7b-nothing-is-approval-required", TOOLS, E("return REQUIRED.has(toolName);", "return false;"), T_TC, ["slice-1 tool set is exactly the eight tools of the spec (fully qualified names)"])
M("G1-7c-gated-tool-listed-in-allowed-tools", "server/tool-tiers.ts", E('return getToolTier(fqn) === "auto-approve";', 'return getToolTier(fqn) !== "blocked";'), T_BA, ["unit census every hand-listed gated entry is absent even when handed to the filter explicitly", "unit census the booted universe is exactly the registered tools; each is in the table; auto-approve ones are pre-approved and gated ones are not"])
M("G1-7d-runner-loses-the-approval-wiring", "server/agent-runner.ts", E("approval: createApprovalGateDeps({", "approvalOff: createApprovalGateDeps({"), T_RC, ["runner registration census the legacy runner wires the approval dependency into its canUseTool deps"])
M("G1-7e-runner-grants-not-shared-with-a-builder", "server/agent-runner.ts", E("const workspaceSettingsTools = buildWorkspaceSettingsTools({ userId, grants: approvalGrants });", "const workspaceSettingsTools = buildWorkspaceSettingsTools({ userId });"), T_RC, ["runner registration census the legacy runner creates ONE per-session ExecutionGrants and hands the same object to the gate and the three grant-reading builders (ADR-307 ExecutionGrants)"])
M("G1-12a-census-vacuity-check-removed", TOOLS, E("if (gated.length === 0 || required.length === 0) {", "if (false) {"), T_TC, ["Guard 2 census: every gated tool is required or exempt-with-a-reason row 2: an empty census is reported as vacuous"])
M("G1-12b-census-vacuity-needs-both-empty", TOOLS, E("if (gated.length === 0 || required.length === 0) {", "if (gated.length === 0 && required.length === 0) {"), T_TC, ["Guard 2 census: every gated tool is required or exempt-with-a-reason row 2b: a census with gated tools but no required tool, or required tools but no gated tool, is vacuous"])
M("G2-1-unclassified-gated-tool-not-reported", TOOLS, E("unclassified: gated.filter((t) => !req.has(t) && !Object.hasOwn(exempt, t)),", "unclassified: [],"), T_TC, ["Guard 2 census: every gated tool is required or exempt-with-a-reason row 1: a new gated tool added to the map without classification is reported"])
M("G2-4-blank-exempt-reason-accepted", TOOLS, E("exempt[t].trim().length === 0", "exempt[t].length === 0"), T_TC, ["Guard 2 census: every gated tool is required or exempt-with-a-reason row 4: an exempt tool with an empty or blank reason is reported"])

# ---- 9. Decide boundary: the agent cannot approve its own request; WS decision pass-through; reattach attach sites ----------------------
M("G1-D1-decision-enum-widened", DECIDE, E('export const APPROVAL_DECISIONS = ["approve", "deny"] as const;', 'export const APPROVAL_DECISIONS = ["approve", "deny", "approve_all"] as const;'), T_SVC, ["decideApproval (user-JWT client only; the actor is auth.uid() inside the rpc, never a parameter) rejects an unknown decision before calling the database (no 'approve all', no free text)"])
M("G1-D2a-service-reexports-decide-by-name", SVC, E("export const APPROVAL_STATUSES =", 'export { decideApproval } from "./decide";\nexport const APPROVAL_STATUSES ='), T_DB, ["canUseTool, the gate flow and the service wrappers cannot reach decide.ts"])
M("G1-D2b-service-star-reexports-decide", SVC, E("export const APPROVAL_STATUSES =", 'export * from "./decide";\nexport const APPROVAL_STATUSES ='), T_DB, ["canUseTool, the gate flow and the service wrappers cannot reach decide.ts"])
M("G1-D2c-stray-decide-rpc-name-single-quoted-in-a-gate-module", TOOLS, E('const P = "mcp__soleur_platform__";', 'const P = "mcp__soleur_platform__";\nexport const STRAY = \'decide_approval\';'), T_DB, ["the decide_approval RPC name appears, in code and in any quote style, in exactly one source module"])
M("G1-D2d-stray-decide-rpc-call-in-a-tool-builder", GHT, E('import { checkGrant, grantRefusalResponse, reportGrantRefused, type ExecutionGrants } from "./approval/grants";', 'import { checkGrant, grantRefusalResponse, reportGrantRefused, type ExecutionGrants } from "./approval/grants";\nexport const STRAY_RPC = (c: { rpc: (n: string) => unknown }) => c.rpc("decide_approval");'), T_DB, ["the decide_approval RPC name appears, in code and in any quote style, in exactly one source module"])
M("G1-D2e-tool-builder-imports-handleMessage-from-the-hub", "server/kb-share-tools.ts", E('import { tool } from "@anthropic-ai/claude-agent-sdk";', 'import { tool } from "@anthropic-ai/claude-agent-sdk";\nimport { handleMessage } from "./ws-handler";\nexport const STRAY_HUB = handleMessage;'), T_DB, ["the hub (ws-handler) is not a back door no gate-side, approval or MCP-builder module value-imports ws-handler at all"])
M("G1-D2f-gate-module-imports-handleMessage-by-alias", TOOLS, E('const P = "mcp__soleur_platform__";', 'import { handleMessage as hm } from "../ws-handler";\nexport const STRAY_HUB = hm;\nconst P = "mcp__soleur_platform__";'), T_DB, ["the hub (ws-handler) is not a back door nothing outside tests imports handleMessage (the entry that mints a tenant client and routes approval_decide)"])
M("G1-D2g-gate-module-imports-decide-directly", TOOLS, E('const P = "mcp__soleur_platform__";', 'import { decideApproval } from "./decide";\nexport const STRAY_DECIDE = decideApproval;\nconst P = "mcp__soleur_platform__";'), T_DB, ["the decide path is unreachable from anything the agent can reach canUseTool, the gate flow and the service wrappers cannot reach decide.ts"])
M("G1-DB3-template-built-rpc-name-in-a-tool-builder", GHT, E('import { checkGrant, grantRefusalResponse, reportGrantRefused, type ExecutionGrants } from "./approval/grants";', 'import { checkGrant, grantRefusalResponse, reportGrantRefused, type ExecutionGrants } from "./approval/grants";\nexport const STRAY_RPC = (c: { rpc: (n: string) => unknown }) => c.rpc(`decide_${"approval"}`);'), T_DB, residual="a run-time assembled RPC name is invisible to the name grep (the import-graph conjuncts still hold because the builder imports no decide module)")
M("G1-D3-review-answer-can-resolve-an-approval", WSH, E('if (typeof msg.gateId === "string" && hasApprovalWaiter(msg.gateId)) {', "if (false) {"), T_WS, ["cross-kind resolution bypass: a review gate and an approval can never resolve each other review_gate_response carrying an approval's id does not wake the waiter, does not decide, and is refused"])
M("G1-D4-reattach-skips-hash-verification", REATT, E("}) === approval.action_sha256;", "}) !== '';"), T_WS, ["a row whose stored action does not hash to the bound value is never rendered (the card cannot disagree with the hash)"])
M("G1-D5-card-truncates-the-body", "server/approval/render.ts", E('row("BODY", str(f.body), "block"),', 'row("BODY", str(f.body).slice(0, 40), "block"),', count=2), T_REND, ["a 100 KB body is rendered in full (no ellipsis, no +N more)"])
M("G1-WS1-ws-decision-hard-coded-to-approve", WSH, E("          id: msg.approvalId,\n          decision: msg.decision,\n", '          id: msg.approvalId,\n          decision: "approve",\n'), T_WS, ["a DENY decision sends p_decision 'deny' to the RPC, reports the rejected row and wakes the waiter with 'rejected'"])
M("G1-WS2-ws-decision-hard-coded-to-deny", WSH, E("          id: msg.approvalId,\n          decision: msg.decision,\n", '          id: msg.approvalId,\n          decision: "deny",\n'), T_WS, ["approval_decide decides through the tenant client of the SOCKET user, with no actor parameter, and reports the outcome"])
M("G1-WS3-ws-wakes-the-waiter-on-pending", WSH, E('if (row.status !== "pending") wakeApprovalWaiter(row.id, row.status);', "wakeApprovalWaiter(row.id, row.status);"), T_WS, ["approval_decide a closed conversation (still pending) does not wake the waiter"])
M("G1-RA1-reattach-call-deleted-at-resume_stream", WSH, E("    reattachApprovals(userId, verifiedConvId, { tenant });\n", ""), T_WS, ["reattach re-send attach site: resume_stream flag on: the live card is re-sent"])
M("G1-RA2-reattach-call-deleted-at-context_path", WSH, E("            reattachApprovals(userId, row.id, { tenant: tenantResume });\n", ""), T_WS, ["reattach re-send attach site: start_session with resumeByContextPath (context_path) flag on: the live card is re-sent"])
M("G1-RA3-reattach-call-deleted-at-resume_session", WSH, E("        reattachApprovals(userId, msg.conversationId, { workspaceId: resumeWorkspaceId });\n", ""), T_WS, ["reattach re-send attach site: resume_session flag on: the live card is re-sent"])

# ---- 10. Harness row (a): the real-SDK probe assertions (static checker over COMMENT-STRIPPED source) ---------------------------------
M("P1-probe-no-invoked-assertion", PROBE, E('} else if (!r.invoked) verdict = "BYPASS";', "} else if (false) verdict = \"BYPASS\";"), STATIC, ["probe: a case where canUseTool was never invoked is the BYPASS verdict"])
M("P2-probe-deny-not-required-to-be-honoured", PROBE, E('verdict = denyHonoured && r.tier === "gated" ? "ok" : "FAIL";', 'verdict = r.tier === "gated" ? "ok" : "FAIL";'), STATIC, ["probe: ok requires the deny to be honoured and the tier gated"])
M("P3-probe-bypass-does-not-fail-the-run", PROBE, E('if (verdict === "BYPASS" || verdict === "FAIL" || verdict === "CANARY-NOT-BYPASSING") failed = true;', 'if (verdict === "FAIL" || verdict === "CANARY-NOT-BYPASSING") failed = true;'), STATIC, ["probe: a BYPASS, FAIL or non-bypassing canary fails the run"])
M("P4-probe-exit-code-ignores-failure", PROBE, E("process.exit(failed ? 1 : cantRun ? 3 : diagnostic ? 4 : 0);", "process.exit(cantRun ? 3 : diagnostic ? 4 : 0);"), STATIC, ["probe: the exit code is 1 when a case failed"])
M("P5-probe-never-records-that-the-stub-ran", PROBE, E("if (s.name === c.tool) handlerRan = true;", "void 0;"), STATIC, ["probe: the stub body records that it ran (handlerRan)"])
M("P6-probe-invoked-hard-coded", PROBE, E("return { attempted, invoked: seen.includes(target), tier,", "return { attempted, invoked: true, tier,"), STATIC, ["probe: invoked comes from the names production canUseTool saw"])
M("P7-probe-anchor-survives-only-in-a-comment", PROBE, E('} else if (!r.invoked) verdict = "BYPASS";', '} else if (false) verdict = "BYPASS"; /* } else if (!r.invoked) verdict = "BYPASS"; */'), STATIC, ["probe: a case where canUseTool was never invoked is the BYPASS verdict"])
M("P8-probe-behaviour-hard-coded-to-deny", PROBE, E("behaviors.push(String(r?.behavior));", 'behaviors.push("deny");'), STATIC, ["probe: the decision recorded is the one production canUseTool returned"])
M("P9-probe-approver-says-approve", PROBE, E('return "Reject"; },', 'return "Approve"; },'), STATIC, ["probe: the probe approver answers Reject, so a bypass would be the only way the stub runs"])
M("P10-probe-tier-hard-coded-gated", PROBE, E("if (toolName === target) tier = getToolTier(toolName);", 'if (toolName === target) tier = "gated";'), STATIC, ["probe: the tier is read from the production tier map"])
M("P11-probe-never-records-the-tool-call", PROBE, E("      seen.push(toolName);\n", ""), STATIC, ["probe: invoked comes from the names production canUseTool saw"])

# ---- 11. The production gate-deps factory (gate.ts): the "injected seam" class (round-2 FD-1) ------------------------------------
K_GD_GRANTS = ["createApprovalGateDeps: the grants object exposes the SAME ExecutionGrants object it was given",
               "createApprovalGateDeps: the grants object a gate run through the factory's deps turns THAT object enforcing"]
M("G1-GD1-factory-builds-a-private-grants-object", GD, [E('import type { ExecutionGrants } from "./grants";', 'import { ExecutionGrants } from "./grants";'), E("    grants: args.grants,", "    grants: new ExecutionGrants(),")], T_GD, K_GD_GRANTS + ["composed: factory deps -> gate -> the real kb_share_create handler, over one shared grants object approved in W1 but the active workspace moved to W2"])
M("G1-GD2-factory-consume-always-releases", GD, E("    consume: (p) => consumeApproval(svc(), p),", "    consume: async () => ({ consumed: true }),"), T_GD, ["createApprovalGateDeps: RPC forwarding consume forwards consume_approval with the id, the hash and the conversation"])
M("G1-GD3-factory-readstatus-always-approved", GD, E("      return row ? row.status : null;", '      return row ? "approved" : null;'), T_GD, ["readStatus forwards get_approval_status with the id and returns the row's own status"])
M("G1-GD4-factory-flag-defaults-on", GD, E("isEnabled: args.isEnabled ?? (() => isApprovalQueueEnabled({ userId: args.userId, workspaceId: args.workspaceId })),", "isEnabled: args.isEnabled ?? (async () => true),"), T_GD, ["the default isEnabled reads the REAL approval-queue flag with the user and the workspace", "the default is OFF when the flag is off or unreadable (never on by default)"])
M("G1-GD5-factory-flag-read-without-the-workspace", GD, E("isApprovalQueueEnabled({ userId: args.userId, workspaceId: args.workspaceId })", "isApprovalQueueEnabled({ userId: args.userId, workspaceId: args.userId })"), T_GD, ["the default isEnabled reads the REAL approval-queue flag with the user and the workspace"])
M("G1-GD6-factory-workspace-id-is-not-the-sessions", GD, E("    workspaceId: args.workspaceId,\n    grants: args.grants,", "    workspaceId: args.userId,\n    grants: args.grants,"), T_GD, ["exposes the SAME ExecutionGrants object it was given"])
M("G1-GD7-factory-viewer-always-owner", GD, E('return data === true ? "owner" : "member";', 'return "owner";'), T_GD, ["is 'member' for false, null and any non-true answer"])
M("G1-GD8-factory-viewer-read-error-ignored", GD, E('if (error) throw new Error("viewer role read failed");', ""), T_GD, ["a read error is thrown (the gate reports it and shows the read-only card); it is never an owner"])
M("G1-GD9-factory-viewer-asks-about-another-user", GD, E("p_user_id: args.userId }", "p_user_id: args.workspaceId }"), T_GD, ["is 'owner' only for a clean `true`, asked of is_workspace_owner for THIS workspace and user"])
M("G1-GD10-factory-require-repo-deleted", GD, E('if (!args.repoSlug) throw new Error("no connected repository to bind");', ""), T_GD, ["push / PR / trigger with NO connected repository throw (nothing to bind)"])
M("G1-GD11-factory-pr-and-trigger-repo-constant", GD, E('case "mcp__soleur_platform__github_trigger_workflow":\n          return { repo: requireRepo() };', 'case "mcp__soleur_platform__github_trigger_workflow":\n          return { repo: "example/constant" };'), T_GD, ["PR and workflow trigger: the connected repository only"])
M("G1-GD12-factory-push-head-is-a-constant", GD, E("headSha: await headSha(args.workspacePath) }", 'headSha: "0".repeat(40) }'), T_GD, ["push: the connected repository and the workspace HEAD resolved FROM THE WORKSPACE PATH"])
M("G1-GD13-factory-push-head-read-from-the-wrong-path", GD, E("await headSha(args.workspacePath)", 'await headSha(".")'), T_GD, ["push: the connected repository and the workspace HEAD resolved FROM THE WORKSPACE PATH"])
M("G1-GD14-factory-push-repo-is-a-constant", GD, E("return { repo: requireRepo(), headSha:", 'return { repo: "example/constant", headSha:'), T_GD, ["push: the connected repository and the workspace HEAD resolved FROM THE WORKSPACE PATH"])
M("G1-GD15-factory-reply-recipient-is-a-constant", GD, E("return { recipient: sender };", 'return { recipient: "constant@example.test" };'), T_GD, ["email_reply: the STORED sender of the owner-scoped inbound item"])
M("G1-GD16-factory-reply-reads-another-row", GD, E('.select("id, sender").eq("id", messageId)', '.select("id, sender").eq("id", args.userId)'), T_GD, ["email_reply: the STORED sender of the owner-scoped inbound item"])
M("G1-GD17-factory-reply-empty-sender-accepted", GD, E('typeof sender !== "string" || sender.length === 0', 'typeof sender !== "string"'), T_GD, ["email_reply: no message id, a read error, or an empty / non-string sender throws"])
M("G1-GD18-factory-reply-read-error-ignored", GD, E("if (error || typeof sender !==", "if (typeof sender !=="), T_GD, ["email_reply: no message id, a read error, or an empty / non-string sender throws"])
M("G1-GD19-factory-pushes-again-on-a-re-ask", GD, E("if (!created || !notify) return;", "if (!notify) return;"), T_GD, ["pushes only for a NEW request the database said to notify about"])
M("G1-GD20-factory-undelivered-push-is-silent", GD, E('if (!delivered) throw new Error("approval notification not delivered");', ""), T_GD, ["a dispatch that reaches nobody throws, so the gate reports approval-notify-failed"])
M("G1-GD21-factory-service-client-not-memoised", GD, E("(service ??= (args.serviceClient", "(service = (args.serviceClient"), T_GD, ["the service client is created once and reused across calls"])
M("G1-GD22-factory-head-read-in-the-process-cwd", GD, E("{ cwd: workspacePath, timeout: 10_000 }", "{ cwd: process.cwd(), timeout: 10_000 }"), T_GD, ["push binds the HEAD of THE WORKSPACE PATH (not the process cwd's repository), as a bare commit sha"])
M("G1-GD23-factory-head-not-trimmed", GD, E("const sha = stdout.trim();", "const sha = stdout;"), T_GD, ["push binds the HEAD of THE WORKSPACE PATH (not the process cwd's repository), as a bare commit sha"])
M("G1-GD25-factory-default-tenant-client-is-built-for-the-workspace", GD, E("getFreshTenantClient(args.userId)", "getFreshTenantClient(args.workspaceId)"), T_GD, ["the default tenant client is getFreshTenantClient(userId): the USER id, never the workspace id"])
M("G1-GD26-factory-default-service-client-is-not-createServiceClient", GD, E("createServiceClient() as unknown as ApprovalRpcClient", "({}) as unknown as ApprovalRpcClient"), T_GD, ["the default service client is createServiceClient (service role), never the tenant client"])
M("G1-GD27-factory-default-notifier-gets-the-user-not-the-workspace", GD, E("(args.notifyRequested ?? notifyApprovalRequested)(approvalId, args.workspaceId, expiresAt)", "(args.notifyRequested ?? notifyApprovalRequested)(approvalId, args.userId, expiresAt)"), T_GD, ["the default notifier forwards a newly created request to the real notify path with the approval id, the workspace id and the expiry"])
M("G1-GD28-factory-default-notifier-is-not-the-real-notify-path", GD, E("args.notifyRequested ?? notifyApprovalRequested", "args.notifyRequested ?? (async () => true)"), T_GD, ["the default notifier forwards a newly created request to the real notify path with the approval id, the workspace id and the expiry"])
M("G1-GD24-factory-head-shape-unchecked", GD, E('if (!COMMIT_SHA_RE.test(sha)) throw new Error("workspace HEAD is not a commit sha");', ""), T_GD, equivalent="`git rev-parse HEAD` that exits 0 prints exactly one full object id (40 or 64 hex) and an unborn or missing HEAD exits non-zero, which execFile already turns into a throw; surveyed input shapes: a normal repo, an empty repo (no commit), a non-repository directory, a repository with a detached HEAD; none reaches the shape check with a non-sha. Defence in depth for a future change of the git command.")

# ---- 12. Sticky enforcement, grants refused / key unavailable ops, push without a commit, consume-reject frames (round-2 Q3/Q5/Q6/Q8) --
K_STICKY = [": flag on, then off, on ONE ExecutionGrants object -> terminal unavailable deny, no review card, no request"]
M("G1-ST1-flag-off-after-enforcing-falls-back-to-the-legacy-card", GF, E("    if (a.approval.grants.enforcing) {\n      a.logDecision", "    if (false) {\n      a.logDecision"), T_GF, K_STICKY, blast=0.3)
M("G1-ST2-flag-off-after-enforcing-allows", GF, E('a.logDecision(a.toolName, "deny", "approval flow unavailable after it ran in this session");\n      return deny(APPROVAL_UNAVAILABLE_DENY);', 'a.logDecision(a.toolName, "deny", "approval flow unavailable after it ran in this session");\n      return a.allow(a.toolInput);'), T_GF, K_STICKY, blast=0.3)
M("G1-ST3-flag-off-always-denies-even-before-the-flow-ran", GF, E("    if (a.approval.grants.enforcing) {\n      a.logDecision", "    if (true) {\n      a.logDecision"), T_GF, ["a session the flow NEVER ran in still falls back to the legacy gate when the flag is off"], blast=0.3)
M("G1-ST4-grants-required-grants-optional-github", GHT, E("\n  grants: ExecutionGrants;", "\n  grants?: ExecutionGrants;"), T_BGR, ["'buildGithubTools': the options interface 'BuildGithubToolsOpts' has a non-optional"])
M("G1-ST5-grants-required-grants-optional-kb-share", KBS, E("\n  grants: ExecutionGrants;", "\n  grants?: ExecutionGrants;"), T_BGR, ["'buildKbShareTools': the options interface 'BuildKbShareToolsOpts' has a non-optional"])
M("G1-ST6-grants-required-grants-optional-settings", WSET, E("\n  grants: ExecutionGrants;", "\n  grants?: ExecutionGrants;"), T_BGR, ["'buildWorkspaceSettingsTools': the options interface 'BuildWorkspaceSettingsToolsOpts' has a non-optional"])
M("G1-ST7-grants-required-builder-takes-another-type", GHT, E("export function buildGithubTools(opts: BuildGithubToolsOpts)", "export function buildGithubTools(opts: Partial<BuildGithubToolsOpts>)"), T_BGR, ["'buildGithubTools' takes its options as 'BuildGithubToolsOpts'"])
M("G1-PG1-push-grant-without-a-commit-pushes-head", GHT, E('if (grant.kind === "granted" && !grant.binding.headSha) {', "if (false) {"), T_PUSHG, ["a grant that carries no headSha REFUSES (never pushes HEAD) and is reported as commit_mismatch"])
M("G1-PG2-push-grant-without-a-commit-refuses-unreported", GHT, E('reportGrantRefused(toolName, "commit_mismatch");', ""), T_SINK, ["commit_mismatch: a push grant that carries no headSha refuses (never pushes HEAD)"])
M("G1-PG3-approved-commit-unavailable-refuses-unreported", GHT, E('reportGrantRefused(toolName, "commit_unavailable");', ""), T_SINK, ["commit_unavailable: the approved commit cannot be pushed"])
M("G1-GR1-checkgrant-refusal-not-reported", GRANTS, E('reportGrantRefused(tool, threw ? "grant_error" : "grant_missing", threw ? cause : null);', "void 0;"), T_SINK, ["grant_missing: an enforcing session, no grant", "grant_error: args that cannot be keyed"])
M("G1-GR2-keying-failure-reported-as-missing", GRANTS, E('threw ? "grant_error" : "grant_missing"', '"grant_missing"'), T_SINK, ["grant_error: args that cannot be keyed"])
M("G1-GR3-grant-refused-op-drops-the-reason", GRANTS, E('reportApprovalOp("grantRefused", cause, { toolName: tool, extra: { reason } });', 'reportApprovalOp("grantRefused", cause, { toolName: tool });'), T_SINK, ["grant_missing: an enforcing session, no grant"])
M("G1-GR4-kb-share-workspace-change-not-reported", KBS, E('reportGrantRefused(toolName, "workspace_changed");', ""), T_SINK, ["workspace_changed: approved in W1, active workspace W2"])
M("G1-GR5-settings-workspace-change-not-reported", WSET, E('reportGrantRefused(toolName, "workspace_changed");', ""), T_SINK, ["workspace_changed: approved in W1, active workspace W2"])
M("G1-GR6-refusal-code-differs-between-tools", GRANTS, E('workspace_changed: { error: WORKSPACE_CHANGED_MESSAGE, code: "workspace_changed", status: 409 }', 'workspace_changed: { error: WORKSPACE_CHANGED_MESSAGE, code: "workspace-changed", status: 409 }'), T_EXG, ["kb_share_create the active workspace changed after approval: refused with workspace_changed, createShare never called", "workspace_set_autonomous approved on W1 but the active workspace is W2: refused with workspace_changed, setBashAutonomous never called"])
M("G1-GR7-workspace-changed-text-is-the-generic-grant-missing-text", GRANTS, E('"The active workspace changed after the approval was granted, so the action was NOT performed.', '"The approval for this action could not be applied to this call, so the action was NOT performed.'), T_GRANTS, ["the terminal refusal texts say what actually happened (one per cause, never the generic grant-missing text) the texts themselves"])
M("G1-GR8-commit-unavailable-text-is-the-generic-grant-missing-text", GRANTS, E('"The commit the Owner approved is not available in the workspace, so the push was NOT performed.', '"The approval for this action could not be applied to this call, so the push was NOT performed.'), T_GRANTS, ["the terminal refusal texts say what actually happened (one per cause, never the generic grant-missing text) the texts themselves"])
M("G1-GR9-commit-unavailable-reason-answers-grant-missing", GRANTS, E("commit_unavailable: { error: APPROVED_COMMIT_UNAVAILABLE_MESSAGE,", "commit_unavailable: { error: GRANT_MISSING_MESSAGE,"), T_GRANTS, ["each refusal reason answers with its own text, code and status"])
M("G1-BGR1-content-census-loses-a-grant-reading-builder", KBS, E('import { checkGrant, grantRefusalResponse, reportGrantRefused, type ExecutionGrants } from "./approval/grants";', 'import { grantRefusalResponse, reportGrantRefused, type ExecutionGrants } from "./approval/grants";'), T_BGR, ["grant-reading builders and the three known ones among them"])
M("G1-7f-runner-hands-a-builder-a-different-grants-object", "server/agent-runner.ts", E("buildWorkspaceSettingsTools({ userId, grants: approvalGrants })", "buildWorkspaceSettingsTools({ userId, grants: approvalGrantsB })"), T_RC, ["runner registration census the legacy runner creates ONE per-session ExecutionGrants and hands the same object to the gate and the three grant-reading builders (ADR-307 ExecutionGrants)"])
M("G1-KU1-error-level-ops-downgraded-to-warn", "server/approval/ops.ts", E('if (def.level === "error") reportSilentFallback(null, options);', 'if (false) reportSilentFallback(null, options);'), T_SINK, ["the gate denies with the unavailable text and reaches Sentry as its own error event (literal-null path, code in extra)"])
M("G1-KU1b-error-level-ops-hand-the-error-to-the-helper", "server/approval/ops.ts", E('if (def.level === "error") reportSilentFallback(null, options);', 'if (def.level === "error") reportSilentFallback(err, options);'), T_OPSINK, [": captureMessage with feature/op tags, the static message, error level and the approval id", ": the pino mirror line carries feature/op and no err object (nothing for the pino integration to capture)"], blast=0.45)  # 15/37 measured: every error-level op case of two it.each tests
M("G1-KU2-reattach-key-unavailable-not-reported", REATT, E('reportApprovalOp("keyUnavailable", null, {', 'reportApprovalOp("reattachFailed", null, {'), T_SINK, ["reattach reports the same op, tagged with the approval id, and shows no card"])
M("G1-KU3-flag-read-failure-latches-after-the-first-report", FLAG, E("lastReadFailureReportedAt === null || now - lastReadFailureReportedAt >= FLAG_READ_FAILURE_REPORT_TTL_MS", "lastReadFailureReportedAt === null"), T_SINK, ["reports once per window, stays quiet inside it, and reports again after the TTL"])
M("G1-NA1-not-approved-has-no-own-deny-text", GF, E('    case "not_approved":\n      // The consume lost to a revoke: the Owner denied it, so the honest text is the denial, not "arguments changed".\n      return APPROVAL_REJECTED_DENY;\n', ""), T_GF, ["consume reasons map to their own static text not_approved"])
M("G1-NA2-not-approved-card-keeps-claiming-approved", GF, E('    case "not_approved":\n      return "rejected";\n', ""), T_GF, ["live path, reason not_approved -> approval_status rejected with agentWaiting=false"])
M("G1-CF1-live-consume-reject-sends-no-settle-frame", GF, E("            emitStatus(approvalId, consumeRejectedCardStatus(shown), false, consumeRejectedIsUnusable(shown));\n", ""), T_GF, ["live path, reason "], blast=0.3)
M("G1-CF2-live-consume-reject-says-the-agent-still-waits", GF, E("emitStatus(approvalId, consumeRejectedCardStatus(shown), false, consumeRejectedIsUnusable(shown));", "emitStatus(approvalId, consumeRejectedCardStatus(shown), true, consumeRejectedIsUnusable(shown));"), T_GF, ["live path, reason "], blast=0.3)
M("G1-CF3-reproposal-consume-reject-sends-no-settle-frame", GF, E("        emitStatus(submitted.approvalId, consumeRejectedCardStatus(shown), false, consumeRejectedIsUnusable(shown));\n", ""), T_GF, ["re-proposal path (consume rejected inside submit) emits the same settle frame"])
M("G1-CF4-expired-reject-card-keeps-claiming-approved", GF, E('    case "expired":\n      return "expired";\n    case "not_approved":', '    case "not_approved":'), T_GF, ["live path, reason expired -> approval_status expired with agentWaiting=false"])
# Round 3: not_approved is told apart from expired by ONE best-effort read; an unusable approval is flagged on the status frame.
M("G1-NA3-not-approved-expired-row-reported-as-denied", GF, E('return (await a.approval.readStatus(approvalId)) === "expired" ? "expired" : reason;', "return reason;"), T_GF, ["a row that expired meanwhile maps to the expired deny text and the expired card status, not 'Owner denied'"])
M("G1-NA4-not-approved-read-failure-changes-the-deny", GF, E('    } catch {\n      return reason;\n    }\n  };', '    } catch {\n      return "rpc_error";\n    }\n  };'), T_GF, ["a failed or empty read keeps the safe default (the denial), and the deny stays static"])
M("G1-UN1-unusable-flag-never-sent", GF, E("        ...(unusable ? { unusable: true } : {}),\n", ""), T_GF, ["leaves the row approved but flags the status frame unusable", "the re-proposal path flags an unusable approval the same way"])
M("G1-UN2-requester-not-member-not-flagged-unusable", GF, E('return reason === "decider_not_owner" || reason === "requester_not_member";', 'return reason === "decider_not_owner";'), T_GF, ["reason requester_not_member leaves the row approved but flags the status frame unusable"])

# ---- 13. Payload wiring of the gate flow (round-2 FD-6) -------------------------------------------------------------------------
K_PAY_SUBMIT = ["gate-flow payload wiring the submitted request carries the REQUESTING user"]
M("G1-PL1-requester-is-the-conversation", GF, E("requestedByUserId: a.userId,", "requestedByUserId: a.conversationId,"), T_PAY, K_PAY_SUBMIT)
M("G1-PL2-submit-binds-the-user-as-the-conversation", GF, E("        conversationId: a.conversationId,\n        requestedByUserId: a.userId,", "        conversationId: a.userId,\n        requestedByUserId: a.userId,"), T_PAY, K_PAY_SUBMIT)
M("G1-PL3-submit-carries-an-empty-canonical-action", GF, E("        canonicalAction: action,\n", "        canonicalAction: { ...action, fields: {} },\n"), T_PAY, K_PAY_SUBMIT)
M("G1-PL4-card-expiry-is-blank", GF, E("          expiresAt: submitted.approval.expires_at,\n          requestCount", '          expiresAt: "",\n          requestCount'), T_PAY, ["the approval_request card carries the row's own expires_at"])
M("G1-PL5-card-request-count-is-constant", GF, E("          requestCount: submitted.requestCount,\n          viewerRole,", "          requestCount: 1,\n          viewerRole,"), T_PAY, ["the approval_request card carries the row's own expires_at, the request count"])
M("G1-PL6-dispatch-gets-the-cards-expiry", GF, E("                expiresAt: submitted.expiresAt,\n", "                expiresAt: submitted.approval.expires_at,\n"), T_PAY, ["the onRequested dispatch gets the approval id, the created and notify verdicts and the DATABASE's expiresAt (not the card's)"])

# ---- 14. Art. 17 erasure emitters: a literal null first argument (round-2 Q2) ---------------------------------------------------
M("G1-ER1-erasure-rpc-error-hands-the-error-to-the-helper", ACC, E('reportSilentFallback(null, {\n        feature: "account-delete",\n        op: "anonymise-approval-request",', 'reportSilentFallback(anonApprovalErr, {\n        feature: "account-delete",\n        op: "anonymise-approval-request",'), T_AD, ["anonymise_approval_request failure aborts cascade BEFORE auth-delete"])
M("G1-ER2-erasure-throw-hands-the-error-to-the-helper", ACC, E('reportSilentFallback(null, {\n      feature: "account-delete",\n      op: "anonymise-approval-request",', 'reportSilentFallback(err, {\n      feature: "account-delete",\n      op: "anonymise-approval-request",'), T_AD, ["anonymise_approval_request throwing aborts cascade BEFORE auth-delete"])

json.dump(TABLE, open(sys.argv[1], "w"))
PYTBL
rc=$?
[ "$rc" = 0 ] && [ -s "$MUTANTS" ] || { printf 'HALT: mutant table could not be built (rc=%s)\n' "$rc"; exit 2; }

if [ "$LIST" = 1 ]; then jq -r '.[] | "\(.id)\t\(.test)\t\(if .equivalent then "equivalent" elif .residual then "residual" else "must-kill" end)"' "$MUTANTS"; exit 0; fi

# ---------------------------------------------------------------------------------------------------------------------
# Edit driver (python): applies every edit of one mutant to <root>: exact occurrence count, optional nth occurrence.
# ---------------------------------------------------------------------------------------------------------------------
APPLY_PY="$SB/apply.py"
cat > "$APPLY_PY" <<'PY'
import json, sys
mutants, idx, root = sys.argv[1], sys.argv[2], sys.argv[3]
table = json.load(open(mutants))
targets = range(len(table)) if idx == "all" else [int(idx)]
bad = 0
for i in targets:
    m = table[i]
    path = root + "/" + m["file"]
    try:
        s = open(path, encoding="utf-8").read()
    except OSError as e:
        print("MISSING FILE for %s: %s" % (m["id"], m["file"])); bad += 1; continue
    ok = True
    for e in m["edits"]:
        n = s.count(e["anchor"])
        if n != e["count"]:
            print("ANCHOR MISMATCH for %s: found %d, expected %d (anchor starts %r)" % (m["id"], n, e["count"], e["anchor"][:70])); ok = False; bad += 1; break
        nth = e.get("nth")
        if nth is None:
            s = s.replace(e["anchor"], e["replace"])
        else:
            parts = s.split(e["anchor"])
            out = parts[0]
            for k, p in enumerate(parts[1:], start=1):
                out += (e["replace"] if k == nth else e["anchor"]) + p
            s = out
    if ok and idx != "all":
        open(path, "w", encoding="utf-8").write(s)
sys.exit(3 if bad else 0)
PY

# --check-anchors: every edit against the PRISTINE app tree (read-only), no test run.
if [ "$CHECK_ANCHORS" = 1 ]; then
  python3 "$APPLY_PY" "$MUTANTS" all "$APP"
  rc=$?
  if [ "$rc" = 0 ]; then printf 'anchors: all %s rows apply\n' "$(jq 'length' "$MUTANTS")"; exit 0; fi
  printf 'anchors: STALE (rc=%s)\n' "$rc"; exit 1
fi

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
  [ "$f" = "null" ] && continue
  mkdir -p "$PRISTINE/$(dirname "$f")" && cp "$APP/$f" "$PRISTINE/$f" || { printf 'HALT: cannot snapshot %s\n' "$f"; exit 2; }
done < <(jq -r '.[].file' "$MUTANTS" | sort -u)

# ---------------------------------------------------------------------------------------------------------------------
# Judge (python), driven by the vitest JSON report. Prints "<VERDICT>\t<detail>".
# ---------------------------------------------------------------------------------------------------------------------
JUDGE_PY="$SB/judge.py"
cat > "$JUDGE_PY" <<'PY'
import json, os, re, sys
report, rc, kills = sys.argv[1], int(sys.argv[2]), json.loads(sys.argv[3])
names_path, blast = sys.argv[4], float(sys.argv[5])
# The control run's PASSED full names: attribution is by EXACT COUNT against them (see below).
ctrl = open(names_path, encoding="utf-8").read().split("\n") if os.path.isfile(names_path) else []
PARSE = re.compile(r"SyntaxError|Transform failed|Failed to parse|Unexpected token|Cannot find module|Failed to resolve import|is not defined|Expected|ParseError", re.I)
def out(v, d=""):
    print("%s\t%s" % (v, d)); sys.exit(0)
if rc in (124, 137, 143) or rc > 128:
    out("UNRESOLVED", "timeout or signal (rc=%d)" % rc)
if not os.path.isfile(report) or os.path.getsize(report) == 0:
    out("UNRESOLVED", "no report (rc=%d)" % rc)
try:
    d = json.load(open(report, encoding="utf-8"))
except ValueError:
    out("UNRESOLVED", "unreadable report")
suites = d.get("testResults") or []
if not suites:
    out("UNRESOLVED", "report has no test file")
dead = [s for s in suites if s.get("status") == "failed" and not s.get("assertionResults")]
if dead:
    msg = " ".join(str(s.get("message", "")) for s in dead)
    out("BROKEN" if PARSE.search(msg) else "UNRESOLVED", "suite did not run: " + msg.strip().replace("\n", " ")[:120])
if int(d.get("numTotalTests", 0)) == 0:
    out("UNRESOLVED", "no tests ran")
failed = [a.get("fullName", "") for s in suites for a in s.get("assertionResults", []) if a.get("status") == "failed"]
if not failed:
    out("SURVIVED" if rc == 0 else "UNRESOLVED", "no failed test" if rc == 0 else "non-zero exit (rc=%d) with no failed test" % rc)
if rc == 0:
    out("UNRESOLVED", "failed tests with exit 0")
total = int(d.get("numTotalTests", 0))
shown = "; ".join(n[:90] for n in failed[:12])
# A row with no named detector cannot be attributed: any failing test would credit it (review FD-5).
if not kills:
    out("MISATTRIBUTED", "the row names no detector test; %d failed: %s" % (len(failed), shown))
# EXACT-COUNT attribution. Every named substring must match the SAME NUMBER of failed tests as it matches control-passed
# tests: a title shared by several it.each cases is credited only when ALL of its cases fail, so a future narrower
# regression in one case cannot read KILLED, and a substring that is a prefix of an unrelated test does not widen it.
for k in kills:
    n_ctrl = sum(1 for n in ctrl if k in n)
    n_fail = sum(1 for n in failed if k in n)
    if n_ctrl == 0:
        out("UNRESOLVED", "named detector [%s] matches no control-passed test" % k[:90])
    if n_fail != n_ctrl:
        out("MISATTRIBUTED", "[%s] matches %d control-passed test(s) but %d failed; failed: %s" % (k[:80], n_ctrl, n_fail, shown))
# Blast radius: a crash or a global breakage that fails (nearly) the whole file is not a kill by its named test.
if total and len(failed) / total > blast:
    out("UNRESOLVED", "blast radius %d/%d failed exceeds the row's bound %.2f (a crash that fails the file is not a kill)" % (len(failed), total, blast))
out("KILLED", "%d/%d failed; named tests failed: %s" % (len(failed), total, "; ".join(k[:60] for k in kills)))
PY
judge() { # judge <report.json> <rc> <kills-json> <control-passed-names-file> [blast-bound] -> "<VERDICT>\t<detail>"
  python3 "$JUDGE_PY" "$1" "$2" "$3" "$4" "${5:-0.5}"
}
verdict_of() { printf '%s' "${1%%$'\t'*}"; }

# Control reader (python): <report> -> "<passed> <failed> <suite-failures>" and the passed full names, one per line, in <names>.
CTRL_PY="$SB/ctrl.py"
cat > "$CTRL_PY" <<'PY'
import json, sys
report, names = sys.argv[1], sys.argv[2]
try:
    d = json.load(open(report, encoding="utf-8"))
except (OSError, ValueError):
    print("? ? ?"); sys.exit(0)
suites = d.get("testResults") or []
passed = [a.get("fullName", "") for s in suites for a in s.get("assertionResults", []) if a.get("status") == "passed"]
failed = [a for s in suites for a in s.get("assertionResults", []) if a.get("status") == "failed"]
dead = [s for s in suites if s.get("status") == "failed" and not s.get("assertionResults")]
open(names, "w", encoding="utf-8").write("\n".join(passed))
print("%d %d %d" % (len(passed), len(failed), len(dead)))
PY

run_test() { # run_test <testfile> <log> -> exit status in $RUN_RC; JSON report at <log>.json
  rm -f "$2.json"
  ( cd "$APPCOPY" && timeout -k 5 240 "$VITEST" run "$1" --reporter=default --reporter=json --outputFile.json="$2.json" ) > "$2" 2>&1
  RUN_RC=$?
}

# ---------------------------------------------------------------------------------------------------------------------
# Static checker for the real-SDK probe (harness row a). Strips comments FIRST, then requires every anchor. Emits the same
# JSON shape as vitest so the judge is shared: one "assertion" per anchor, failed when the anchor is absent from the code.
# It runs against a COPY of the probe. A TEXT PIN, not a behavioural test (see the header).
# ---------------------------------------------------------------------------------------------------------------------
PROBE_PY="$SB/probe_static.py"
cat > "$PROBE_PY" <<'PY'
import json, re, sys

def strip_comments(s):
    out, i, n = [], 0, len(s)
    while i < n:
        c, d = s[i], s[i + 1] if i + 1 < n else ""
        if c == "/" and d == "/":
            while i < n and s[i] != "\n": i += 1
        elif c == "/" and d == "*":
            i += 2
            while i < n and not (s[i] == "*" and i + 1 < n and s[i + 1] == "/"):
                if s[i] == "\n": out.append("\n")
                i += 1
            i += 2
        elif c in "\"'`":
            q = c; out.append(c); i += 1
            while i < n and s[i] != q:
                if s[i] == "\\" and i + 1 < n: out.append(s[i]); i += 1
                out.append(s[i]); i += 1
            out.append(q); i += 1
        else:
            out.append(c); i += 1
    return "".join(out)

NEED = [
    ("probe: a case where canUseTool was never invoked is the BYPASS verdict", r'\} else if \(!r\.invoked\) verdict = "BYPASS";'),
    ("probe: ok requires the deny to be honoured and the tier gated", r'verdict = denyHonoured && r\.tier === "gated" \? "ok" : "FAIL";'),
    ("probe: denyHonoured is invoked, handler not run, every decision deny", r'const denyHonoured = r\.invoked && !r\.handlerRan && r\.behaviors\.length > 0 && r\.behaviors\.every\(\(b\) => b === "deny"\);'),
    ("probe: a BYPASS, FAIL or non-bypassing canary fails the run", r'if \(verdict === "BYPASS" \|\| verdict === "FAIL" \|\| verdict === "CANARY-NOT-BYPASSING"\) failed = true;'),
    ("probe: the exit code is 1 when a case failed", r'process\.exit\(failed \? 1 :'),
    ("probe: the stub body records that it ran (handlerRan)", r'if \(s\.name === c\.tool\) handlerRan = true;'),
    ("probe: invoked comes from the names production canUseTool saw", r'seen\.push\(toolName\);[\s\S]*invoked: seen\.includes\(target\)'),
    ("probe: the decision recorded is the one production canUseTool returned", r'behaviors\.push\(String\(r\?\.behavior\)\);'),
    ("probe: the tier is read from the production tier map", r'if \(toolName === target\) tier = getToolTier\(toolName\);'),
    ("probe: the probe approver answers Reject, so a bypass would be the only way the stub runs", r'abortableReviewGate: async \(\) => \{ gateCalls \+= 1; return "Reject"; \},'),
]
src = open(sys.argv[1], encoding="utf-8").read()
code = strip_comments(src)
results = []
for name, rx in NEED:
    results.append({"fullName": name, "status": "passed" if re.search(rx, code) else "failed"})
nfail = sum(1 for r in results if r["status"] == "failed")
json.dump({"numTotalTests": len(results), "numFailedTests": nfail, "numPassedTests": len(results) - nfail,
           "testResults": [{"name": sys.argv[1], "status": "failed" if nfail else "passed", "assertionResults": results}]},
          open(sys.argv[2], "w"))
for r in results:
    if r["status"] == "failed": print("MISSING " + r["fullName"])
sys.exit(1 if nfail else 0)
PY
probe_static() { # probe_static <probe.ts> <log> -> RUN_RC, JSON at <log>.json
  rm -f "$2.json"
  python3 "$PROBE_PY" "$1" "$2.json" > "$2" 2>&1
  RUN_RC=$?
}

# --- Harness row (b-judge): the judge itself, driven with canned reports.
CAN="$SB/canned"; mkdir -p "$CAN"
jq -n '{numTotalTests:3,testResults:[{status:"passed",assertionResults:[{fullName:"a one",status:"passed"},{fullName:"a two",status:"passed"},{fullName:"a three",status:"passed"}]}]}' > "$CAN/green.json"
jq -n '{numTotalTests:3,testResults:[{status:"failed",assertionResults:[{fullName:"a one",status:"failed"},{fullName:"a two",status:"passed"},{fullName:"a three",status:"passed"}]}]}' > "$CAN/red-designed.json"
jq -n '{numTotalTests:3,testResults:[{status:"failed",assertionResults:[{fullName:"a one",status:"passed"},{fullName:"a two",status:"failed"},{fullName:"a three",status:"passed"}]}]}' > "$CAN/red-other.json"
jq -n '{numTotalTests:0,testResults:[{status:"failed",message:"Error: Transform failed with 1 error: SyntaxError: Unexpected token",assertionResults:[]}]}' > "$CAN/parse.json"
jq -n '{numTotalTests:0,testResults:[{status:"failed",message:"Error: Test timed out in a hook",assertionResults:[]}]}' > "$CAN/dead.json"
printf 'not json' > "$CAN/garbage.json"
printf 'a one\na two\na three' > "$CAN/names.txt"
# Three it.each cases that share a title, plus an unrelated test.
printf 't case 1\nt case 2\nt case 3\nother' > "$CAN/names-shared.txt"
jq -n '{numTotalTests:4,testResults:[{status:"failed",assertionResults:[{fullName:"t case 1",status:"failed"},{fullName:"t case 2",status:"passed"},{fullName:"t case 3",status:"passed"},{fullName:"other",status:"passed"}]}]}' > "$CAN/shared-one.json"
jq -n '{numTotalTests:4,testResults:[{status:"failed",assertionResults:[{fullName:"t case 1",status:"failed"},{fullName:"t case 2",status:"failed"},{fullName:"t case 3",status:"failed"},{fullName:"other",status:"passed"}]}]}' > "$CAN/shared-all.json"
jq -n '{numTotalTests:4,testResults:[{status:"failed",assertionResults:[{fullName:"t case 1",status:"failed"},{fullName:"t case 2",status:"failed"},{fullName:"t case 3",status:"failed"},{fullName:"other",status:"failed"}]}]}' > "$CAN/crash-all.json"
check "judge: canned green reads SURVIVED" test "$(verdict_of "$(judge "$CAN/green.json" 0 '["a one"]' "$CAN/names.txt")")" = SURVIVED
check "judge: a failure of the NAMED test reads KILLED" test "$(verdict_of "$(judge "$CAN/red-designed.json" 1 '["a one"]' "$CAN/names.txt")")" = KILLED
check "judge: a failure of a DIFFERENT test reads MISATTRIBUTED, never KILLED (a describe-title substring cannot credit the row)" test "$(verdict_of "$(judge "$CAN/red-other.json" 1 '["a one"]' "$CAN/names.txt")")" = MISATTRIBUTED
check "judge: a parse error reads BROKEN, never KILLED" test "$(verdict_of "$(judge "$CAN/parse.json" 1 '["a one"]' "$CAN/names.txt")")" = BROKEN
check "judge: a suite that died without a parse error reads UNRESOLVED" test "$(verdict_of "$(judge "$CAN/dead.json" 1 '["a one"]' "$CAN/names.txt")")" = UNRESOLVED
check "judge: a verdict-less non-zero exit (no report) reads UNRESOLVED, never KILLED" test "$(verdict_of "$(judge "$CAN/missing.json" 1 '["a one"]' "$CAN/names.txt")")" = UNRESOLVED
check "judge: an unreadable report reads UNRESOLVED" test "$(verdict_of "$(judge "$CAN/garbage.json" 1 '["a one"]' "$CAN/names.txt")")" = UNRESOLVED
check "judge: a timeout (rc 124) reads UNRESOLVED even when the report shows a red" test "$(verdict_of "$(judge "$CAN/red-designed.json" 124 '["a one"]' "$CAN/names.txt")")" = UNRESOLVED
check "judge: a red report with exit 0 reads UNRESOLVED" test "$(verdict_of "$(judge "$CAN/red-designed.json" 0 '["a one"]' "$CAN/names.txt")")" = UNRESOLVED
check "judge: a green report with a non-zero exit reads UNRESOLVED (a crash after the tests is not a survivor)" test "$(verdict_of "$(judge "$CAN/green.json" 1 '["a one"]' "$CAN/names.txt")")" = UNRESOLVED
check "judge: every named test must fail (one of two missing is MISATTRIBUTED)" test "$(verdict_of "$(judge "$CAN/red-designed.json" 1 '["a one","a three"]' "$CAN/names.txt")")" = MISATTRIBUTED
check "judge: a shared title is credited only when ALL its cases fail (one of three failing is MISATTRIBUTED, never KILLED)" test "$(verdict_of "$(judge "$CAN/shared-one.json" 1 '["t case"]' "$CAN/names-shared.txt" 0.9)")" = MISATTRIBUTED
check "judge: all cases of a shared title failing reads KILLED when the row declares the blast radius it needs" test "$(verdict_of "$(judge "$CAN/shared-all.json" 1 '["t case"]' "$CAN/names-shared.txt" 0.9)")" = KILLED
check "judge: the same failures beyond the default blast bound read UNRESOLVED, never KILLED" test "$(verdict_of "$(judge "$CAN/shared-all.json" 1 '["t case"]' "$CAN/names-shared.txt")")" = UNRESOLVED
check "judge: a crash that fails the whole file reads UNRESOLVED even when it fails the named test" test "$(verdict_of "$(judge "$CAN/crash-all.json" 1 '["t case"]' "$CAN/names-shared.txt" 0.9)")" = UNRESOLVED
check "judge: a must-kill row that names no detector never reads KILLED (any failing test would credit it)" test "$(verdict_of "$(judge "$CAN/red-designed.json" 1 '[]' "$CAN/names.txt")")" = MISATTRIBUTED
check "judge: a named detector that is not a control-passed test reads UNRESOLVED" test "$(verdict_of "$(judge "$CAN/red-designed.json" 1 '["no such test"]' "$CAN/names.txt")")" = UNRESOLVED

# --- Harness row (probe-comment): an anchor that survives only inside a comment does not satisfy the static checker.
printf '%s\n' '// } else if (!r.invoked) verdict = "BYPASS";' 'const x = 1; /* process.exit(failed ? 1 : 0) */' > "$CAN/commented.ts"
python3 "$PROBE_PY" "$CAN/commented.ts" "$CAN/commented.json" > "$CAN/commented.log" 2>&1
check "harness row (probe-comment): anchors that exist only in comments are reported MISSING by the static probe checker" grep -q 'MISSING probe: a case where canUseTool was never invoked is the BYPASS verdict' "$CAN/commented.log"

assert_fixture_dir "$SB"
# 228 rows today (round 3); at most ONE may be deleted silently. The verdict classes are pinned too (below, full run only).
MIN_MUTANTS=227
TOTAL="$(jq 'length' "$MUTANTS")"
if [ "$TOTAL" -lt "$MIN_MUTANTS" ]; then printf 'HALT: mutant table has %s rows, floor %s: a truncated table is vacuous\n' "$TOTAL" "$MIN_MUTANTS"; exit 1; fi

# --- Harness row (a-anchor): a missing anchor must fail the apply step.
BOGUS="$SB/bogus.json"
jq -n '[{id:"bogus",file:"server/approval/gate-flow.ts",edits:[{anchor:"@@no such anchor@@",replace:"x",count:1,nth:null}],test:"x",kill:[],equivalent:null,residual:null}]' > "$BOGUS"
python3 "$APPLY_PY" "$BOGUS" 0 "$APPCOPY" > /dev/null 2>&1
rc=$?
check "harness row (a-anchor): a mutant whose anchor is missing fails the apply step (rc 3, never a skip)" test "$rc" = 3

# --- Control: the unedited copy, on every distinct test file, must be GREEN with a literal floor of tests, and every test
# name a row relies on must be among the PASSED tests (so a typo or a renamed test is a harness failure, not a silent no-op).
declare -A FLOOR=(
  ["test/approval/gate-flow.test.ts"]=130
  ["test/approval/gate-flow-resolver-snapshot.test.ts"]=3
  ["test/approval/canonical.test.ts"]=81
  ["test/approval/waiters.test.ts"]=19
  ["test/approval/service.test.ts"]=26
  ["test/approval/migration-180-approval-request.test.ts"]=91
  ["test/approval/tools-census.test.ts"]=18
  ["test/approval/runner-census.test.ts"]=10
  ["test/approval/flag.test.ts"]=5
  ["test/approval/decide-boundary.test.ts"]=52
  ["test/approval/render.test.ts"]=44
  ["test/approval/grants.test.ts"]=13
  ["test/approval/migration-180-decide-closed.test.ts"]=9
  ["test/approval/gate-flow-grant-deny-paths.test.ts"]=9
  ["test/approval/execution-grant-handlers.test.ts"]=10
  ["test/server/ws-handler-approval.test.ts"]=37
  ["test/build-allowed-tools-census.test.ts"]=47
  ["test/github-tools-push-grant.test.ts"]=7
  ["test/push-branch-pinned.test.ts"]=4
  ["test/approval/gate-deps.test.ts"]=29
  ["test/approval/approval-ops-real-sink.test.ts"]=13
  ["test/approval/ops-sink.test.ts"]=37
  ["test/approval/gate-flow-payload.test.ts"]=4
  ["test/approval/builder-grants-required.test.ts"]=9
  ["test/account-delete.test.ts"]=55
  ["test/approval/permission-callback-gated-branch.test.ts"]=3
)
for tf in $(jq -r '.[].test' "$MUTANTS" | sort -u); do
  if [ "$tf" = "static:probe" ]; then
    # Control for the static checker: the pristine probe passes it, and it has all ten anchors to check.
    probe_static "$APPCOPY/scripts/dev-probe-approval-gate.ts" "$SB/control.probe.log"
    CHECKED=$((CHECKED + 1))
    if [ "$RUN_RC" != 0 ]; then printf 'HALT: the CONTROL probe checker is not green (the probe lost an assertion, or an anchor now lives only in a comment):\n'; cat "$SB/control.probe.log"; exit 1; fi
    cp "$SB/control.probe.log.json" "$SB/control.probe.json"
    python3 "$CTRL_PY" "$SB/control.probe.log.json" "$SB/names.probe" > /dev/null
    ok "control: the real-SDK probe carries its 10 verdict anchors in code (comments stripped)"
    continue
  fi
  floor="${FLOOR[$tf]:-}"
  [ -n "$floor" ] || { printf 'HALT: no control floor for test file %s\n' "$tf"; exit 1; }
  base="$(basename "$tf")"
  run_test "$tf" "$SB/control.$base.log"
  read -r passed failed dead < <(python3 "$CTRL_PY" "$SB/control.$base.log.json" "$SB/names.$base")
  if [ "$RUN_RC" != 0 ] || [ "$failed" != 0 ] || [ "$dead" != 0 ] || [ "$passed" = "?" ] || [ "$passed" -lt "$floor" ]; then
    printf 'HALT: the CONTROL run of %s is not green with at least %s tests (rc=%s, passed=%s, failed=%s, dead suites=%s): the battery is void\n' "$tf" "$floor" "$RUN_RC" "$passed" "$failed" "$dead"
    tail -30 "$SB/control.$base.log"
    exit 1
  fi
  CHECKED=$((CHECKED + 1))
  ok "control: $tf is green ($passed tests)"
done

# Every `kill` entry of every row must be a PASSED test of its file's control run.
while IFS=$'\t' read -r rid rtf rkill; do
  [ -n "$rkill" ] || continue
  if [ "$rtf" = "static:probe" ]; then names="$SB/names.probe"; else names="$SB/names.$(basename "$rtf")"; fi
  CHECKED=$((CHECKED + 1))
  if python3 - "$names" "$rkill" <<'PYK'
import json, sys
names = open(sys.argv[1], encoding="utf-8").read().split("\n")
sys.exit(0 if all(any(k in n for n in names) for k in json.loads(sys.argv[2])) else 1)
PYK
  then ok "control: $rid: every named detector test exists and is green"; else bad "control: $rid: a named detector test is not among the passed tests of $rtf (renamed or deleted?)"; fi
done < <(jq -r '.[] | select((.kill | length) > 0) | [.id, .test, (.kill | tojson)] | @tsv' "$MUTANTS")

# Presence of the plan's must-PASS case (harness row b): the control is only meaningful if it is there.
CHECKED=$((CHECKED + 1))
if grep -q 'harness row b' "$APPCOPY/test/approval/gate-flow.test.ts"; then
  ok "harness row (b): the must-PASS non-canonical case (same arguments, different key order) is present in gate-flow.test.ts and the file is green in the control"
else
  bad "harness row (b): the must-PASS non-canonical case is missing from gate-flow.test.ts"
fi

# --- Mutants.
KILLED=0 SURVIVED_EQ=0 SURVIVED_RES=0 UNRESOLVED=0 SELECTED=0
for ((i = 0; i < TOTAL; i++)); do
  id="$(jq -r ".[$i].id" "$MUTANTS")"
  if [ -n "$ONLY" ] && ! [[ "$id" =~ $ONLY ]]; then continue; fi
  SELECTED=$((SELECTED + 1))
  file="$(jq -r ".[$i].file" "$MUTANTS")"
  tf="$(jq -r ".[$i].test" "$MUTANTS")"
  kills="$(jq -c ".[$i].kill" "$MUTANTS")"
  equiv="$(jq -r ".[$i].equivalent // empty" "$MUTANTS")"
  resid="$(jq -r ".[$i].residual // empty" "$MUTANTS")"
  blast="$(jq -r ".[$i].blast // 0.5" "$MUTANTS")"

  python3 "$APPLY_PY" "$MUTANTS" "$i" "$APPCOPY" > "$SB/apply.log" 2>&1
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
  if [ "$tf" = "static:probe" ]; then cnames="$SB/names.probe"; else cnames="$SB/names.$(basename "$tf")"; fi
  res="$(judge "$SB/mut.$i.log.json" "$RUN_RC" "$kills" "$cnames" "$blast")"
  verdict="$(verdict_of "$res")"; detail="${res#*$'\t'}"
  cp "$PRISTINE/$file" "$APPCOPY/$file"
  if ! cmp -s "$APPCOPY/$file" "$PRISTINE/$file"; then printf 'HALT: restore of %s failed\n' "$file"; exit 2; fi

  CHECKED=$((CHECKED + 1))
  if [ -n "$equiv" ]; then
    if [ "$verdict" = SURVIVED ]; then ok "$id: equivalent, survives as documented ($equiv)"; SURVIVED_EQ=$((SURVIVED_EQ + 1)); else bad "$id: listed equivalent but the verdict is $verdict ($detail)"; fi
    [ "$verdict" = UNRESOLVED ] && UNRESOLVED=$((UNRESOLVED + 1))
    continue
  fi
  if [ -n "$resid" ]; then
    if [ "$verdict" = SURVIVED ]; then ok "$id: RESIDUAL GAP, survives and is reported ($resid)"; SURVIVED_RES=$((SURVIVED_RES + 1)); else bad "$id: listed as a residual gap but the verdict is $verdict ($detail): move the row to the must-kill table"; fi
    [ "$verdict" = UNRESOLVED ] && UNRESOLVED=$((UNRESOLVED + 1))
    continue
  fi
  case "$verdict" in
    KILLED)       ok "$id: killed [$detail]"; KILLED=$((KILLED + 1)) ;;
    SURVIVED)     bad "$id: SURVIVED: the tests do not exercise this property (fix the tests, not the guard)" ;;
    MISATTRIBUTED) bad "$id: MISATTRIBUTED: killed, but not by its designed detector ($detail)" ;;
    BROKEN)       bad "$id: BROKEN: the mutant does not parse or collect, so it was killed by the parser, not by its row ($detail)" ;;
    *)            UNRESOLVED=$((UNRESOLVED + 1)); bad "$id: UNRESOLVED: no readable verdict ($detail)" ;;
  esac
done

# --- Harness row (c): a no-op edit reads as "not landed".
NOOP="$SB/noop.json"
jq -n '[{id:"noop",file:"server/approval/gate-flow.ts",edits:[{anchor:"export const APPROVAL_PENDING_DENY",replace:"export const APPROVAL_PENDING_DENY",count:1,nth:null}],test:"x",kill:[],equivalent:null,residual:null}]' > "$NOOP"
python3 "$APPLY_PY" "$NOOP" 0 "$APPCOPY" > /dev/null 2>&1
check "harness row (c): a no-op edit reads as not landed" cmp -s "$APPCOPY/server/approval/gate-flow.ts" "$PRISTINE/server/approval/gate-flow.ts"

# --- The working tree was never edited.
STATUS_AFTER="$(git_status)"
check "the app tree's tracked-file status is unchanged by the battery (no mutated source left behind)" test "$STATUS_BEFORE" = "$STATUS_AFTER"

ELAPSED=$(( $(date +%s) - START ))
[ "$ELAPSED" -le "$WALL_BUDGET_S" ] || printf '[WARN] wall time %ss exceeds the %ss budget (a slow runner is not a defect)\n' "$ELAPSED" "$WALL_BUDGET_S"
printf '\nmutants selected=%s killed=%s equivalent-survivors=%s residual-gaps=%s unresolved=%s; checks=%s pass=%s fail=%s; %ss\n' "$SELECTED" "$KILLED" "$SURVIVED_EQ" "$SURVIVED_RES" "$UNRESOLVED" "$CHECKED" "$PASS" "$FAIL" "$ELAPSED"

# A --only run is a partial battery: it has its own verdict and never reaches the full-run floor below.
if [ -n "$ONLY" ]; then
  if [ "$UNRESOLVED" -gt 0 ]; then exit 3; fi
  if [ "$FAIL" -gt 0 ]; then exit 1; fi
  exit 0
fi

# Verdict classes of a full run: exactly the documented survivors (3 equivalent: G1-R4, G1-W6, G1-GD24; 2 residual gaps:
# G1-F5, G1-DB3) and at least MIN_KILLED must-kill rows killed. A deleted or reclassified row moves one of these literals.
EXPECT_EQUIV=3
EXPECT_RESID=2
MIN_KILLED=222
if [ "$SURVIVED_EQ" != "$EXPECT_EQUIV" ] || [ "$SURVIVED_RES" != "$EXPECT_RESID" ] || [ "$KILLED" -lt "$MIN_KILLED" ]; then
  printf '[FATAL] verdict classes: killed=%s (floor %s) equivalent=%s (expected %s) residual=%s (expected %s)\n' "$KILLED" "$MIN_KILLED" "$SURVIVED_EQ" "$EXPECT_EQUIV" "$SURVIVED_RES" "$EXPECT_RESID" >&2
  exit 1
fi

# Anti-vacuity: the floor is a literal directly above its `if`, and reported by printf + exit, never through ok/bad.
MIN_CHECKS=499
if [ "$CHECKED" -lt "$MIN_CHECKS" ]; then
  printf '[FATAL] assertion floor: only %s assertions ran, floor %s: the battery is vacuous\n' "$CHECKED" "$MIN_CHECKS" >&2
  exit 1
fi
if [ $((PASS + FAIL)) -lt "$CHECKED" ]; then printf 'HALT: pass+fail (%s) is below the checks counted (%s)\n' "$((PASS + FAIL))" "$CHECKED"; exit 1; fi
if [ "$UNRESOLVED" -gt 0 ]; then exit 3; fi
if [ "$FAIL" -gt 0 ]; then exit 1; fi
exit 0
