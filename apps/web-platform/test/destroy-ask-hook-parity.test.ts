/**
 * #9776 — hook parity: the hosted must-ask classifier is a SUPERSET of the plugin destructive-command hook's D1
 * set (ADR-277). The real hook (kill switch unset) is run over every corpus row; the corpus's `hookAsks` field is
 * therefore verified, not trusted, and a weakening of the corpus alone cannot pass.
 *
 *  - every row the hook asks on must also be a classifier ask (superset), unless it carries an explicit
 *    `parityExempt` reason (the hook asks on every unparseable command; the lane only when push/destroy appears);
 *  - every ask row the hook does NOT ask on must carry a `hostedOnly` note (--mirror, unknown-default, raw-scan, gh);
 *  - `hookAsks` must equal what the hook actually did.
 *
 * Tooling: the hook needs bash, perl and jq. A missing tool is a HARD failure, never a skip (a skipped parity
 * suite would read as a pass).
 */
import { describe, test, expect } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, resolve } from "node:path";
import { classifyDestroyFamily } from "../server/destroy-ask-classifier";

interface Row {
  cmd: string;
  expect: "ask" | "pass";
  rule: string | null;
  protected?: string[];
  authoritative?: boolean;
  hookAsks: boolean;
  note?: string;
  parityExempt?: string;
}
const corpus = JSON.parse(readFileSync(join(__dirname, "fixtures", "destroy-ask-corpus.json"), "utf8")) as { rows: Row[] };
const HOOK = resolve(__dirname, "../../..", "plugins/soleur/hooks/destructive-command-guard.sh");

function tool(name: string): string {
  const r = spawnSync("bash", ["-c", `command -v ${name}`], { encoding: "utf8" });
  const p = r.stdout.trim();
  if (r.status !== 0 || !p) throw new Error(`hook parity needs '${name}' on PATH and it is missing: refusing to skip (a skipped parity suite reads as a pass)`);
  return p;
}

describe("hook parity (real hook, kill switch unset)", () => {
  test("tooling and hook script are present", () => {
    tool("bash");
    tool("perl");
    tool("jq");
    expect(readFileSync(HOOK, "utf8")).toContain("destructive-command guard");
    expect(process.env.SOLEUR_DISABLE_DESTRUCTIVE_GUARD).not.toBe("1");
  });

  test("the classifier asks wherever the hook asks, and the corpus declares the hook's behaviour truthfully", async () => {
    const work = mkdtempSync(join(tmpdir(), "destroy-ask-parity-"));
    try {
      const MIN_HOOK_ASK_ROWS = 90;
      let hookAskCount = 0;
      const failures: string[] = [];
      for (const row of corpus.rows) {
        const env = { PATH: process.env.PATH ?? "", HOME: work } as unknown as NodeJS.ProcessEnv;
        const r = spawnSync("bash", [HOOK], {
          cwd: work,
          env,
          encoding: "utf8",
          input: JSON.stringify({ tool_name: "Bash", tool_input: { command: row.cmd }, cwd: work, session_id: "parity", hook_event_name: "PreToolUse" }),
        });
        let decision = "none";
        try {
          decision = JSON.parse(r.stdout).hookSpecificOutput.permissionDecision;
        } catch {
          /* no output = no decision */
        }
        const hookAsked = decision === "ask" || decision === "deny";
        if (hookAsked) hookAskCount += 1;
        const label = JSON.stringify(row.cmd);
        if (hookAsked !== row.hookAsks) failures.push(`${label}: corpus says hookAsks=${row.hookAsks}, the hook said ${decision}`);
        const m = await classifyDestroyFamily(row.cmd, async () => ({
          names: new Set((row.protected ?? ["main", "master"]).map((s) => s.toLowerCase())),
          authoritative: row.authoritative !== false,
        }));
        if (hookAsked && !m && !row.parityExempt) failures.push(`${label}: the hook asks, the classifier does not, and no parityExempt reason`);
        if (row.expect === "ask" && !hookAsked && !(row.note ?? "").includes("hostedOnly")) failures.push(`${label}: classifier-only ask without a hostedOnly note`);
      }
      if (hookAskCount < MIN_HOOK_ASK_ROWS) {
        throw new Error(`only ${hookAskCount} corpus rows were asked by the hook, floor ${MIN_HOOK_ASK_ROWS}: the parity run is vacuous`);
      }
      expect(failures).toEqual([]);
    } finally {
      rmSync(work, { recursive: true, force: true });
    }
  }, 240_000);

  test("an empty corpus cannot pass (floor row)", () => {
    expect(corpus.rows.length).toBeGreaterThan(200);
  });
});
