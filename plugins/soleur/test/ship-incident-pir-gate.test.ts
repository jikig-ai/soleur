// #6813 — the /ship Phase 5.5 Incident-PIR signal scan.
//
// The gate fired on essentially every plan declaring
// `brand_survival_threshold: single-user incident`, because its outage regex
// matched the threshold LABEL (bare `incident`), matched inside `incidental`,
// and read a `## User-Brand Impact` section's hypothetical framing as an outage
// report. A gate that cries wolf on every such plan trains the operator to
// dismiss it — the erosion this fix exists to stop.
//
// Per plan-review M13 the executable gate lives in a real script
// (`scripts/ship-incident-pir-gate.sh`) that OWNS the regexes; this test invokes
// the SHIPPED script directly against fixtures, so a drift between the tested
// gate and the shipped gate is structurally impossible (a stronger form of
// AC19's "must not re-declare the regex" than scraping literals out of Markdown).
import { describe, test, expect } from "bun:test";
import { resolve } from "path";
import { spawnSync } from "child_process";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const GATE = resolve(REPO_ROOT, "scripts/ship-incident-pir-gate.sh");
const FIX = resolve(REPO_ROOT, "plugins/soleur/test/fixtures/ship-incident-pir-gate");

/** Run the shipped gate against a fixture; returns true iff it signalled. */
function signals(fixture: string): boolean {
  const res = spawnSync("bash", [GATE], {
    input: require("fs").readFileSync(resolve(FIX, fixture), "utf8"),
    encoding: "utf8",
  });
  // The gate MUST distinguish "no signal" (exit 1) from an infrastructure error
  // (any other non-zero, or a crash). A no-signal run is exit 1 with no stdout;
  // a signal run is exit 0 with "INCIDENT-SIGNAL: yes".
  if (res.status === 0) {
    expect(res.stdout).toContain("INCIDENT-SIGNAL: yes");
    return true;
  }
  expect(res.status).toBe(1); // clean no-signal, not a harness failure
  return false;
}

describe("ship Incident-PIR gate (#6813)", () => {
  // AC20: the real #6782-shaped preventive-hardening `single-user incident` plan
  // (with all four tripping lines) produces NO signal.
  test("a preventive-hardening single-user-incident plan does NOT signal", () => {
    expect(signals("preventive-hardening-single-user-incident.md")).toBe(false);
  });

  // AC23: `incidental` does not match.
  test("a line whose only outage-shaped token is `incidental` does NOT signal", () => {
    expect(signals("incidental-word.md")).toBe(false);
  });

  // AC22: genuine past production incidents DO still signal (both directions
  // pinned so the regex cannot silently loosen).
  test("the chat-RLS outage postmortem DOES signal", () => {
    expect(signals("chat-rls-outage.md")).toBe(true);
  });

  test("a second real production incident DOES signal", () => {
    expect(signals("second-known-incident.md")).toBe(true);
  });

  // The gate must own its own exit semantics: a no-signal run exits 1 cleanly,
  // never crashes, so a `set -euo pipefail` caller cannot misread it as an
  // infrastructure failure (the foot-gun the old inline `A && B && echo` chain had).
  test("a no-signal run exits 1 cleanly with no stdout", () => {
    const res = spawnSync("bash", [GATE], { input: "nothing to see here\n", encoding: "utf8" });
    expect(res.status).toBe(1);
    expect(res.stdout.trim()).toBe("");
  });
});
