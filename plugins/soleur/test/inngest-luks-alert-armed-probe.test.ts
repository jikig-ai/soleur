// #8296 PR-1: the discoverability probe behind the plan's ADR-175 Check 10 command.
// Two arms, both driven through the real script: the REAL root must print ARMED (rc 0), and a
// synthesized root with the declared default flipped to false must print EXEMPT (rc 1). The
// second arm is what makes the first one evidence — without it a probe that always prints
// ARMED passes the plan's expected_output forever.
import { describe, expect, it } from "bun:test";
import { mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const REPO = join(import.meta.dir, "..", "..", "..");
const SCRIPT = join(REPO, "plugins/soleur/scripts/inngest-luks-alert-armed-probe.ts");
const REAL = join(REPO, "apps/web-platform/infra");

function run(args: string[]) {
  const r = Bun.spawnSync(["bun", SCRIPT, ...args], { cwd: REPO, stdout: "pipe", stderr: "pipe" });
  return { rc: r.exitCode, out: r.stdout.toString().trim() };
}

describe("inngest-luks-alert-armed-probe", () => {
  it("prints ARMED with rc 0 against the real root", () => {
    expect(run([])).toEqual({ rc: 0, out: "ARMED" });
  });

  it("prints EXEMPT with rc 1 when the declared default is flipped to false (positive control)", () => {
    const dir = mkdtempSync(join(tmpdir(), "luks-probe-"));
    for (const f of readdirSync(REAL).filter((n) => n.endsWith(".tf"))) {
      let body = readFileSync(join(REAL, f), "utf8");
      if (f === "variables.tf") {
        const before = body;
        body = body.replace(
          /(variable "inngest_luks_cutover_complete" \{[\s\S]*?default\s*=\s*)true/,
          "$1false",
        );
        expect(body).not.toBe(before); // the mutation must land, or this arm proves nothing
      }
      writeFileSync(join(dir, f), body);
    }
    expect(run([dir])).toEqual({ rc: 1, out: "EXEMPT" });
  });
});
