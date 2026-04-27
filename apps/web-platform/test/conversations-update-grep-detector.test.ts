import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from "node:fs";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";

// Verifies the CI detector script `scripts/lint-conversations-update-callsites.sh`
// catches the bug class it exists to prevent (id-only direct
// `.from("conversations").update(...)` calls), tolerates broken-across-lines
// chains, accepts allowlist markers, and accepts wrapper calls.
//
// Per `cq-mutation-assertions-pin-exact-post-state`: assert exit code is
// EXACTLY 1 for fail cases and EXACTLY 0 for pass cases — not `>= 1` or
// truthy — so a future change that swallows a real violation fails the test.

const REPO_ROOT = join(__dirname, "..", "..", "..");
const SCRIPT = join(REPO_ROOT, "scripts", "lint-conversations-update-callsites.sh");

function runDetectorAgainst(fixtureFile: string): {
  status: number;
  stdout: string;
  stderr: string;
} {
  const tmpRoot = mkdtempSync(join(tmpdir(), "conv-detector-"));
  try {
    const serverDir = join(tmpRoot, "apps", "web-platform", "server");
    mkdirSync(serverDir, { recursive: true });

    // The script requires conversation-writer.ts to exist at the wrapper
    // path; create a stub so the precondition passes.
    writeFileSync(
      join(serverDir, "conversation-writer.ts"),
      "// stub for detector self-test\n",
    );

    writeFileSync(join(serverDir, "fixture.ts"), fixtureFile);

    const result = spawnSync("bash", [SCRIPT], {
      cwd: tmpRoot,
      encoding: "utf8",
    });

    return {
      status: result.status ?? -1,
      stdout: result.stdout ?? "",
      stderr: result.stderr ?? "",
    };
  } finally {
    rmSync(tmpRoot, { recursive: true, force: true });
  }
}

describe("lint-conversations-update-callsites.sh", () => {
  // T5 — single-line direct update is rejected
  it("FAILS on a single-line direct .from(\"conversations\").update(...)", () => {
    const fixture = `
import { supabase } from "./somewhere";
async function f() {
  await supabase.from("conversations").update({ status: "completed" }).eq("id", "x");
}
`;
    const { status, stdout } = runDetectorAgainst(fixture);
    expect(status).toBe(1);
    expect(stdout).toContain("FAIL");
    expect(stdout).toContain("fixture.ts");
  });

  // T10 — multi-line direct update is rejected (the regression-class case)
  it("FAILS on a multi-line broken chain (the bug-class regression case)", () => {
    const fixture = `
import { supabase } from "./somewhere";
async function f() {
  supabase
    .from("conversations")
    .update({ status: "completed" })
    .eq("id", "x");
}
`;
    const { status, stdout } = runDetectorAgainst(fixture);
    expect(status).toBe(1);
    expect(stdout).toContain("FAIL");
  });

  // T6 — allowlisted bulk-update is accepted
  it("PASSES when the matching block is preceded by allow-direct-conversation-update:", () => {
    const fixture = `
import { supabase } from "./somewhere";
async function f() {
  // allow-direct-conversation-update: bulk timeout sweep — no per-user composite key
  const { data, error } = await supabase
    .from("conversations")
    .update({ status: "completed" })
    .in("status", ["waiting_for_user"]);
}
`;
    const { status, stdout } = runDetectorAgainst(fixture);
    expect(status).toBe(0);
    expect(stdout).toContain("OK");
  });

  // Wrapper-call shape is invisible to the detector (no `.from("conversations")`)
  it("PASSES when the file uses updateConversationFor() instead", () => {
    const fixture = `
import { updateConversationFor } from "./conversation-writer";
async function f() {
  await updateConversationFor("u1", "c1", { status: "completed" });
}
`;
    const { status, stdout } = runDetectorAgainst(fixture);
    expect(status).toBe(0);
    expect(stdout).toContain("OK");
  });

  // Mixing allowlisted + non-allowlisted in the same file fails on the
  // non-allowlisted one only.
  it("FAILS when one block is allowlisted but a sibling block is not", () => {
    const fixture = `
import { supabase } from "./somewhere";
async function bulk() {
  // allow-direct-conversation-update: bulk sweep
  await supabase.from("conversations").update({ status: "failed" }).in("status", ["x"]);
}
async function leak() {
  await supabase.from("conversations").update({ status: "completed" }).eq("id", "x");
}
`;
    const { status, stdout } = runDetectorAgainst(fixture);
    expect(status).toBe(1);
    expect(stdout).toContain("FAIL");
    // The non-allowlisted line should appear by its content; the allowlisted
    // bulk one should NOT appear in the failure output.
    expect(stdout).toContain('status: "completed"');
    expect(stdout).not.toContain('status: "failed"');
  });
});
