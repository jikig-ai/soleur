/**
 * #4672: the closed-conversation refusal of `decide_approval` (migration 180), pinned offline.
 *
 * Gap found by the Guard 1 mutation battery after the review round: `SELECT false INTO v_closed` (the archived-conversation
 * read replaced by a constant) survived every assertion in migration-180-approval-request.test.ts, because that file pins
 * the position of `IF NOT FOUND OR v_closed` but not what `v_closed` is assigned from. A decision on a pending request of an
 * archived conversation must record nothing and answer `closed`. The behavioural proof is the database-gated
 * test/server/approval-request.tenant-isolation.test.ts; this is the cheap backstop. Comments are stripped before matching,
 * so a conjunct that survives only in a comment does not count (the self-checks at the bottom prove that).
 */
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, it } from "vitest";

const SQL_PATH = join(__dirname, "../../supabase/migrations/180_approval_request.sql");

/** Remove `--` and block comments but not a marker inside a string literal. */
function stripSqlComments(src: string): string {
  let out = "";
  let i = 0;
  while (i < src.length) {
    const two = src.slice(i, i + 2);
    if (two === "--") {
      while (i < src.length && src[i] !== "\n") i++;
    } else if (two === "/*") {
      const end = src.indexOf("*/", i + 2);
      i = end < 0 ? src.length : end + 2;
      out += " ";
    } else if (src[i] === "'") {
      let j = i + 1;
      while (j < src.length) {
        if (src[j] === "'") {
          if (src[j + 1] === "'") {
            j += 2;
            continue;
          }
          break;
        }
        j++;
      }
      out += src.slice(i, j + 1);
      i = j + 1;
    } else {
      out += src[i];
      i++;
    }
  }
  return out;
}

const norm = (s: string) => s.replace(/\s+/g, " ").trim();

function decideBody(raw: string): string {
  const code = stripSqlComments(raw);
  const start = code.indexOf("FUNCTION public.decide_approval(");
  if (start < 0) return "";
  const open = code.indexOf("$$", start);
  const close = code.indexOf("$$", open + 2);
  return open < 0 || close < 0 ? "" : norm(code.slice(open + 2, close));
}

const READ = /SELECT \(c\.archived_at IS NOT NULL\) INTO v_closed FROM public\.conversations c WHERE c\.id = v_row\.conversation_id;/;
const REFUSE = /IF NOT FOUND OR v_closed THEN RETURN jsonb_build_object\('outcome', 'closed', 'approval', to_jsonb\(v_row\) - 'canonical_action'\); END IF;/;

/** Every issue with the closed-conversation guard in one decide_approval body (empty = clean). */
function closedIssues(body: string): string[] {
  const issues: string[] = [];
  if (!body) return ["decide_approval body not found"];
  if (!READ.test(body)) issues.push("v_closed is not read from conversations.archived_at of the request's conversation");
  if (!REFUSE.test(body)) issues.push("a missing or archived conversation does not return the closed outcome");
  const read = body.search(READ);
  const refuse = body.search(REFUSE);
  const pendingUpdate = body.indexOf("AND status = 'pending'");
  const approvedBlock = body.indexOf("IF v_row.status = 'approved' THEN");
  if (read >= 0 && approvedBlock >= 0 && read < approvedBlock) issues.push("the closed read sits above the approved (revoke) block: a revoke in an archived conversation would be refused");
  if (refuse >= 0 && pendingUpdate >= 0 && refuse > pendingUpdate) issues.push("the closed refusal sits after the pending update");
  return issues;
}

describe("decide_approval: the closed-conversation refusal", () => {
  const raw = readFileSync(SQL_PATH, "utf8");

  it("reads the archived state of the request's own conversation and refuses a missing or archived one before any pending write", () => {
    expect(closedIssues(decideBody(raw))).toEqual([]);
  });

  it("applies to the pending path only: a revoke (deny on an approved row) still works in an archived conversation", () => {
    const body = decideBody(raw);
    expect(body.indexOf("IF v_row.status = 'approved' THEN")).toBeGreaterThan(-1);
    expect(body.search(READ)).toBeGreaterThan(body.indexOf("IF v_row.status = 'approved' THEN"));
  });

  describe("self-checks: the checker goes red on each mutant of the guard", () => {
    const mutants: Array<[string, (s: string) => string]> = [
      ["constant false instead of the archived read", (s) => s.replace("SELECT (c.archived_at IS NOT NULL) INTO v_closed", "SELECT false INTO v_closed")],
      ["constant false with a comment that still names the read", (s) => s.replace("SELECT (c.archived_at IS NOT NULL) INTO v_closed", "SELECT false /* (c.archived_at IS NOT NULL) */ INTO v_closed")],
      ["the closed read targets another conversation", (s) => s.replace("WHERE c.id = v_row.conversation_id;", "WHERE true;")],
      ["only a missing conversation is refused", (s) => s.replace("IF NOT FOUND OR v_closed THEN", "IF NOT FOUND THEN")],
      ["the refusal condition is commented out", (s) => s.replace("IF NOT FOUND OR v_closed THEN", "IF NOT FOUND -- OR v_closed\n THEN")],
      ["the outcome is not 'closed'", (s) => s.replace("'outcome', 'closed'", "'outcome', 'decided'")],
    ];
    it("the unmutated migration is clean", () => {
      expect(closedIssues(decideBody(raw))).toEqual([]);
    });
    it.each(mutants)("%s is detected", (_name, mutate) => {
      const mutated = mutate(raw);
      expect(mutated).not.toBe(raw); // the mutation landed
      expect(closedIssues(decideBody(mutated)).length).toBeGreaterThan(0);
    });
  });
});
