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

/**
 * Same status contract as `signals()`, against in-memory text. Some properties
 * are not expressible as a file fixture: the PR/plan concatenation seam is a
 * TWO-document property, and the template anti-rot check has to read the
 * template at runtime rather than snapshot it.
 */
function signalsText(text: string): boolean {
  const res = spawnSync("bash", [GATE], { input: text, encoding: "utf8" });
  if (res.status === 0) {
    expect(res.stdout).toContain("INCIDENT-SIGNAL: yes");
    return true;
  }
  expect(res.status).toBe(1);
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

  // ── #7801 — the hypothetical-paragraph strip ───────────────────────────────
  //
  // #6813 stripped the hypothetical FRAMING LINE but not the sentences that
  // follow it in the SAME `## User-Brand Impact` paragraph, so a plan that
  // merely CITES a past, closed incident as design precedent still read as an
  // outage report. The strip is now paragraph-scoped: bounded by a blank line,
  // a heading, or a new list item, and re-opened by an actuality idiom.
  //
  // Both directions are pinned on purpose. F2-F8 assert a real outage claim
  // STILL signals — trading this false positive for a false negative is the
  // worse outcome for a gate whose posture is fire-when-uncertain, and those
  // seven already passed before the fix precisely so the widening cannot
  // overshoot without reddening something.

  // F1 — the reported bug.
  test("a precedent citation inside the hypothetical paragraph does NOT signal", () => {
    expect(signals("precedent-citation-inside-hypothetical-paragraph.md")).toBe(false);
  });

  // F2 — the re-admit: once a paragraph says the event HAPPENED, the remainder
  // of it is an incident report. Its production token deliberately sits in
  // `## Overview`, OUTSIDE the stripped paragraph — PROD_RE matches the whole
  // haystack, so a fixture whose only prod token sat inside would read `no`
  // under both scripts and make this assertion vacuous.
  test("an actuality idiom inside the paragraph re-admits the outage claim", () => {
    expect(signals("real-outage-claimed-inside-hypothetical-paragraph.md")).toBe(true);
  });

  // F3 — a blank line is a boundary.
  test("a real outage after the hypothetical paragraph DOES signal", () => {
    expect(signals("real-outage-after-hypothetical-paragraph.md")).toBe(true);
  });

  // F4 — a new list item is a new markdown block.
  test("a real outage in a sibling bullet DOES signal", () => {
    expect(signals("real-outage-in-sibling-bullet.md")).toBe(true);
  });

  // F5 — a heading is a boundary even with no blank line before it.
  test("a real outage after a heading boundary DOES signal", () => {
    expect(signals("real-outage-after-heading-boundary.md")).toBe(true);
  });

  // F6 — a nested sub-bullet resets too. Deliberate, and the fail-toward-fire
  // direction.
  test("a real outage in a nested sub-bullet DOES signal", () => {
    expect(signals("real-outage-in-nested-sub-bullet.md")).toBe(true);
  });

  // F7 — the fence strip must leave a block boundary behind. Without it a fenced
  // block abutting the paragraph merges the paragraph with whatever follows the
  // fence, and the claim after it goes dark.
  test("a real outage after a fence abutting the paragraph DOES signal", () => {
    expect(signals("real-outage-after-fenced-block-abutting-paragraph.md")).toBe(true);
  });

  // F8 — the trigger is ANCHORED. Unanchored, a single subordinate clause
  // ("safe even if this lands out of order") would silence the rest of an
  // arbitrary paragraph.
  test("a mid-sentence conditional does not open a stripped paragraph", () => {
    expect(signals("midsentence-conditional-does-not-open-a-paragraph.md")).toBe(true);
  });

  // F9 — pins the tightened hash rule. A bare /^[[:space:]]*#/ boundary treats a
  // `#6691` continuation line as a heading, which reopens the window and lets the
  // outage claim through — defeating this fix on a REFLOW of its own target class.
  test("a reflowed citation whose continuation starts with an issue ref does NOT signal", () => {
    expect(signals("reflowed-citation-with-issue-ref-continuation.md")).toBe(false);
  });

  // F10 — the DOCUMENTED RESIDUAL, pinned as a characterization test rather than
  // left as an undocumented hole. Precedent-citation and self-report are lexically
  // undecidable inside the paragraph, so a real past-tense outage report phrased
  // without an actuality idiom is swallowed. If a future change closes this hole,
  // this expectation flips — deliberately, and visibly.
  test("a real outage inside the paragraph without an actuality idiom is swallowed (residual)", () => {
    expect(signals("real-outage-inside-paragraph-without-actuality-idiom.md")).toBe(false);
  });

  // F11 — the plan template emits a BULLETED label (`- **If this lands broken…`), and until the
  // #7801 review no fixture used that shape: every one wrote the unbulleted form. So the
  // production input shape was the untested one. The trigger regex admits an optional list
  // marker, which is what consumes it.
  test("the template's own BULLETED label is consumed by the trigger", () => {
    expect(signals("bulleted-label-consumed-by-trigger.md")).toBe(false);
  });

  // F12 — `already occurred` is the measured winner's own inflection. It is kept for the
  // fail-safe direction and pinned here, rather than carried on the assertion that it is a
  // plausible near-miss: the header sets the bar at "a corpus hit AND a fixture".
  test("the `already occurred` inflection also re-admits", () => {
    expect(signals("actuality-occurred-inflection.md")).toBe(true);
  });

  // F13 — the re-admit OUTRANKS the line-scoped drop rules. As two pipeline stages the line
  // filter ran after the paragraph strip and deleted lines the re-admit had restored, so one
  // trailing conditional clause silenced a stated actuality. Merging both into one awk, with the
  // re-admit above the drop rules, is what fixes it; this fixture is what pins it.
  test("an actuality claim outranks a conditional clause in the same sentence", () => {
    expect(signals("actuality-outranks-conditional-clause.md")).toBe(true);
  });

  // The documented residual is OBSERVABLE, not merely fixtured. `exit 1` is byte-identical
  // whether the gate found nothing or suppressed an outage line inside a stripped paragraph, and
  // ship/SKILL.md now tells the reader this note exists — so the claim needs something behind it.
  test("suppressing an outage line inside the paragraph emits a stderr note", () => {
    const res = spawnSync("bash", [GATE], {
      input: require("fs").readFileSync(
        resolve(FIX, "real-outage-inside-paragraph-without-actuality-idiom.md"), "utf8"),
      encoding: "utf8",
    });
    expect(res.status).toBe(1);                       // still a no-signal
    expect(res.stderr).toContain("PIR-STRIP-SUPPRESSED");
    expect(res.stdout.trim()).toBe("");               // and the note never reaches stdout
  });

  // Template anti-rot. The trigger is anchored on the wording the plan template
  // actually emits, so if that wording or its `- **` prefix drifts the anchor
  // stops matching and the gate silently reverts to firing on every plan. Reading
  // the template at runtime is the only mechanism that catches that drift.
  test("the anchored trigger matches the plan template's own wording", () => {
    const tpl = require("fs").readFileSync(
      resolve(REPO_ROOT, "plugins/soleur/skills/plan/references/plan-issue-templates.md"),
      "utf8",
    );
    const triggers = tpl
      .split("\n")
      .filter((l: string) => /^- \*\*If this (lands broken|leaks)/.test(l))
      .slice(0, 2);
    expect(triggers.length).toBe(2); // the template still emits both trigger lines
    const body = triggers
      .map((t: string) => `${t}\n  The 2026-08-16 apex outage took the production site down.`)
      .join("\n");
    expect(signalsText(`# p\n\n## User-Brand Impact\n\n${body}\n`)).toBe(false);
  });

  // Fail-toward-PIR. On a customer's unpinned awk a failed strip stage otherwise
  // empties the haystack -> exit 1 -> byte-identical to a clean no-signal, on a
  // surface (the customer's own CLI, observability layer 7) where no CI is
  // present to notice. Probing by emptying PATH would fail for the wrong reason:
  // `env PATH=/nonexistent bash` cannot find bash at all.
  test("a failing strip stage fails TOWARD a PIR rather than silently", () => {
    const fs = require("fs");
    const dir = fs.mkdtempSync(resolve(require("os").tmpdir(), "pir-gate-awk-"));
    const stub = resolve(dir, "awk");
    fs.writeFileSync(stub, "#!/bin/sh\nexit 2\n");
    fs.chmodSync(stub, 0o755);
    const res = spawnSync("bash", [GATE], {
      input: "nothing to see here\n",
      encoding: "utf8",
      env: { ...process.env, PATH: `${dir}:${process.env.PATH}` },
    });
    expect(res.status).toBe(0);
    expect(res.stdout).toContain("INCIDENT-SIGNAL: yes");
  });

  // The guard above must distinguish a BROKEN pipeline from an EMPTY one. The
  // terminal `grep -v` exits 1 when it selects no lines, which is the ordinary
  // outcome for a PR with an empty body or one whose every line is filtered — so
  // a bare `if ! haystack=...` guard reports an incident for a PR with no text at
  // all. That is the fail-open direction the guard was added to close, inverted
  // into a false positive on the most ordinary input there is. Measured against
  // the bare guard: `empty` and `every line filtered` both signal (those two are
  // the discriminators), while `whitespace only` passes either way — its blank
  // lines are lines `grep -v` selects, so grep exits 0. It is kept as a boundary
  // case, not counted as proof.
  test.each([
    ["empty", ""],
    ["whitespace only", "\n\n"],
    ["every line filtered", "If this lands broken\n"],
  ])("a %s haystack is a clean no-signal, not a pipeline failure", (_label, input) => {
    const res = spawnSync("bash", [GATE], { input, encoding: "utf8" });
    expect(res.status).toBe(1);
    expect(res.stdout.trim()).toBe("");
  });

  // The seam ship itself creates: `printf '%s\n%s' "$PR_TEXT" "$PLAN_TEXT"` joins
  // the two documents with a SINGLE newline, so the PR body's last line and the
  // plan's first line become adjacent with no blank line between them. No file
  // fixture can observe this — every fixture is one document.
  test("the PR/plan concatenation seam does not swallow the plan", () => {
    const prText = "fix: apex\n\n**If this lands broken, the user experiences:** an error page.";
    const planText =
      "# fix: apex\n\n## Overview\n\nThe 2026-08-16 apex outage took the production site down.";
    expect(signalsText(`${prText}\n${planText}`)).toBe(true);
  });
});
