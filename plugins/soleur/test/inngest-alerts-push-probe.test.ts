// #11068: the discoverability probe behind the plan's ADR-175 Check 10 command.
// Two arms, both driven through the real script: the REAL root must print PUSH_ARMED (rc 0),
// and a synthesized root with one resource's push reverted to false must print
// PUSH_MISSING <resource> (rc 1). The second arm is what makes the first one evidence —
// without it a probe that always prints PUSH_ARMED passes the plan's expected_output forever
// (the inngest-luks-alert-armed-probe.test.ts precedent).
import { describe, expect, it } from "bun:test";
import { mkdtempSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const REPO = join(import.meta.dir, "..", "..", "..");
const SCRIPT = join(REPO, "plugins/soleur/scripts/inngest-alerts-push-probe.ts");
const REAL = join(REPO, "apps/web-platform/infra");

function run(args: string[]) {
  const r = Bun.spawnSync(["bun", SCRIPT, ...args], { cwd: REPO, stdout: "pipe", stderr: "pipe" });
  return { rc: r.exitCode, out: r.stdout.toString().trim() };
}

describe("inngest-alerts-push-probe", () => {
  it("prints PUSH_ARMED with rc 0 against the real root", () => {
    expect(run([])).toEqual({ rc: 0, out: "PUSH_ARMED" });
  });

  it("prints PUSH_MISSING with rc 1 when one resource's push reverts (positive control)", () => {
    const dir = mkdtempSync(join(tmpdir(), "push-probe-"));
    for (const f of readdirSync(REAL).filter((n) => n.endsWith(".tf"))) {
      let body = readFileSync(join(REAL, f), "utf8");
      if (f === "uptime-alerts.tf") {
        const before = body;
        body = body.replace(
          /(resource "betteruptime_heartbeat" "inngest_server_probe" \{[\s\S]*?)push\s*=\s*true/,
          "$1push      = false",
        );
        expect(body).not.toBe(before); // the mutation must land, or this arm proves nothing
      }
      writeFileSync(join(dir, f), body);
    }
    expect(run([dir])).toEqual({
      rc: 1,
      out: "PUSH_MISSING betteruptime_heartbeat.inngest_server_probe",
    });
  });
});
