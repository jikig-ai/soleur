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

  // #6665: `network-outage` is the NAME of the plan-skill Phase 1.4 gate, and
  // EVERY plan that documents it firing writes the phrase — so the bare `outage`
  // alternative matched a gate name rather than an event, demanding a PIR on a
  // CI-perf PR with no production incident. Same class as #6813 (matching a
  // label instead of a claim), second instance.
  test("a plan documenting the Phase 1.4 network-outage GATE does NOT signal", () => {
    expect(signals("network-outage-gate-name.md")).toBe(false);
  });

  // AC22: genuine past production incidents DO still signal (both directions
  // pinned so the regex cannot silently loosen).
  test("the chat-RLS outage postmortem DOES signal", () => {
    expect(signals("chat-rls-outage.md")).toBe(true);
  });

  test("a second real production incident DOES signal", () => {
    expect(signals("second-known-incident.md")).toBe(true);
  });

  // Pins the PROD_RE conjunct (review): outage vocabulary with NO production
  // token must NOT signal — else deleting `&& grep PROD_RE` stays green while
  // the gate fires on any local/dev outage postmortem.
  test("outage vocabulary with no production token does NOT signal", () => {
    expect(signals("outage-no-prod-token.md")).toBe(false);
  });

  // Pins the hypothetical strip (review): outage tokens living only inside a
  // hypothetical `If this lands broken:` line must NOT signal — else removing
  // the strip stays green while a plan's User-Brand-Impact section trips the gate.
  test("outage tokens confined to a hypothetical line do NOT signal", () => {
    expect(signals("hypothetical-only-outage.md")).toBe(false);
  });

  // #7003: `### Network-Outage Deep-Dive determination` is a deepen-plan Phase 4.5
  // TEMPLATE heading (recorded per `hr-ssh-diagnosis-verify-firewall` so an N/A
  // skip stays auditable). Matching `Outage` inside it made the gate fire on any
  // plan that recorded the determination, since nearly every plan carries a prod
  // token — the #6813 structural-artifact class, recurring in a new spot.
  test("the Network-Outage Deep-Dive determination heading alone does NOT signal", () => {
    expect(signals("network-outage-determination-heading.md")).toBe(false);
  });

  // Both directions pinned: only the HEADING line is stripped, so a real outage
  // claim written INSIDE that section must still signal. Without this, widening
  // the strip to swallow the section body would stay green while blinding the gate.
  test("a real outage claim inside that section DOES still signal", () => {
    expect(signals("network-outage-determination-with-real-outage.md")).toBe(true);
  });

  // #7242: a DELIVERY outage — releases blocked, production pinned N versions
  // behind — is a production incident that owes a PIR, but it is described with
  // none of the user-facing verbs. The gate returned "no incident signal" on the
  // PR fixing a four-hour release blockage, i.e. it missed the exact event class
  // it exists to catch. Both directions pinned below.
  test("a delivery outage (releases blocked / prod N releases behind) DOES signal", () => {
    expect(signals("delivery-outage-releases-behind.md")).toBe(true);
  });

  // The negative half. A greenfield release-tooling plan is dense with `release`,
  // `deploy`, `production` and `live` but describes no event. Widening the new
  // alternation to a bare `release`/`blocked` would stay green without this —
  // the #6813 false-positive class, re-entered through the fix for its opposite.
  test("a greenfield release-tooling plan does NOT signal", () => {
    expect(signals("release-tooling-plan-no-delivery-outage.md")).toBe(false);
  });

  // The `prod` substring class. Bare `prod` in PROD_RE matched `producer`,
  // `produced`, `product` and `reproduced` — all four are ordinary plan
  // vocabulary, so the production conjunct was satisfied by essentially every
  // plan and the gate reduced to its outage half alone. Measured on the PR that
  // found it: 14 `prod` hits in the haystack, ZERO of them the word. A
  // `post-mortem` reference to a LOCAL test-runner retrospective then demanded a
  // PIR for an event that never happened — the #6813 label-not-claim class,
  // recurring on the other conjunct.
  test("a post-mortem whose only prod tokens are `produce*` substrings does NOT signal", () => {
    expect(signals("postmortem-word-with-only-produce-substrings.md")).toBe(false);
  });

  // The other direction, so the boundary guard cannot be widened into a deletion
  // of the alternative. `production` is exercised by every positive fixture
  // above; this one pins the standalone word `prod`, which no other fixture uses
  // and which a careless `prod(uction)` (no `?`) would silently drop.
  test("a real production incident using the bare word `prod` DOES signal", () => {
    expect(signals("postmortem-with-real-prod-word.md")).toBe(true);
  });

  // The `live` substring class — the same defect one token over in the same
  // alternation. Unguarded, `live` matches `lives` on the right and
  // `delivery`/`delivered`/`deliverables` on the left, all of which are ordinary
  // prose in this repo ("the gate lives in a real script"). Fixing only `prod`
  // would have been the soundness-for-completeness swap this gate keeps
  // re-learning: the class named, one instance closed, the twin left open.
  test("a post-mortem whose only live tokens are substrings does NOT signal", () => {
    expect(signals("postmortem-word-with-only-live-substrings.md")).toBe(false);
  });

  test("a real production incident using the bare word `live` DOES signal", () => {
    expect(signals("postmortem-with-real-live-word.md")).toBe(true);
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
