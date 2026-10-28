import { describe, expect, it } from "vitest";
import { canonicalizeAction } from "@/server/approval/canonical";
import { APPROVAL_COPY, renderApprovalView } from "@/server/approval/render";
import { FIELD_LISTS, SAMPLES, TOOLS, mutateField } from "./fixtures";

const view = (tool: string, s = SAMPLES[tool]) => renderApprovalView(canonicalizeAction(tool, s.input, s.server));
const flat = (v: ReturnType<typeof view>) => v.fields.map((f) => `${f.label}\u0000${f.value}`).join("\n");

describe("renderApprovalView: the card is built from the SAME canonical object that is hashed", () => {
  for (const tool of Object.keys(FIELD_LISTS)) {
    it(`${tool}: every bound field value appears in the view, untruncated`, () => {
      const v = view(tool);
      const text = flat(v);
      const sample = SAMPLES[tool];
      const values = [...Object.entries(sample.input), ...Object.entries(sample.server)]
        // zod defaults that equal the model's explicit value and booleans are rendered as words, checked separately
        .filter(([, val]) => typeof val === "string");
      for (const [k, val] of values) {
        if (k === "jurisdiction") continue;
        expect(text, `field ${k}`).toContain(String(val));
      }
    });

    it(`${tool}: changing any bound field changes the rendered view (view cannot disagree with the hash)`, () => {
      const base = JSON.stringify(view(tool));
      for (const field of [...FIELD_LISTS[tool].input, ...FIELD_LISTS[tool].server]) {
        const changed = JSON.stringify(renderApprovalView(canonicalizeAction(tool, mutateField(tool, field).input, mutateField(tool, field).server)));
        expect(changed, `field ${field} is hashed but not shown`).not.toBe(base);
      }
    });

    it(`${tool}: fixed Approve label, title and consequence from fixed per-tool phrases`, () => {
      const v = view(tool);
      expect(v.approveLabel).toBe("Approve");
      expect(v.denyLabel).toBe("Deny");
      expect(v.title).toMatch(/^Your agent wants to /);
      expect(v.consequence).toContain("once, if you ask it to try again");
      expect(v.consequence).toContain("Valid in this conversation only.");
      expect(v.singleUse).toMatch(/^One-time · this exact /);
    });
  }

  it("a 100 KB body is rendered in full (no ellipsis, no +N more)", () => {
    const s = SAMPLES[TOOLS.emailSend];
    const big = "word ".repeat(20_000);
    const v = renderApprovalView(canonicalizeAction(TOOLS.emailSend, { ...s.input, body: big }, {}));
    const row = v.fields.find((f) => f.label === "BODY");
    expect(row?.value).toBe(big);
  });

  it("shows the server-derived reply recipient and the force flag that the old preview omitted", () => {
    expect(flat(view(TOOLS.emailReply))).toContain("sender@example.test");
    const s = SAMPLES[TOOLS.pushBranch];
    const forced = { ...s, input: { ...s.input, force: true } };
    expect(flat(view(TOOLS.pushBranch, forced))).not.toBe(flat(view(TOOLS.pushBranch, s)));
  });

  it("workspace_set_autonomous renders as the danger variant and states the direction of the change", () => {
    const on = view(TOOLS.setAutonomous);
    const off = view(TOOLS.setAutonomous, { input: { value: false }, server: {} });
    expect(on.danger).toBe(true);
    expect(flat(on)).not.toBe(flat(off));
    expect(view(TOOLS.emailSend).danger).toBe(false);
  });

  it("the view is a pure function of the canonical object (no tool input reaches it)", () => {
    const a = canonicalizeAction(TOOLS.createPr, SAMPLES[TOOLS.createPr].input, SAMPLES[TOOLS.createPr].server);
    expect(renderApprovalView(a)).toEqual(renderApprovalView(structuredClone(a)));
    expect(renderApprovalView.length).toBe(1);
  });
});

describe("copy deck constants (AC14): no outcome is ever claimed", () => {
  const strings = (): string[] => {
    const out: string[] = [];
    const walk = (v: unknown) => {
      if (typeof v === "string") out.push(v);
      else if (v && typeof v === "object") Object.values(v).forEach(walk);
    };
    walk(APPROVAL_COPY);
    for (const tool of Object.keys(FIELD_LISTS)) {
      const v = view(tool);
      out.push(v.title, v.consequence, v.singleUse, v.approveLabel, v.denyLabel);
    }
    return out;
  };

  it("contains none of the outcome words sent, ran, executed, delivered", () => {
    for (const s of strings()) expect(s).not.toMatch(/\b(sent|ran|executed|delivered)\b/i);
  });

  it("carries the approved 'Released to your agent' wording and the honest consequence line", () => {
    expect(JSON.stringify(APPROVAL_COPY)).toContain("Released to your agent");
    expect(view(TOOLS.emailSend).consequence).toBe(
      "Your agent can send this email once, if you ask it to try again. Valid in this conversation only.",
    );
  });
});
