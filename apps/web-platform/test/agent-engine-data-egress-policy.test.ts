import { describe, expect, it } from "vitest";
import {
  authorizeEngineDataEgress,
  type EngineDataEgressEvidence,
} from "@/server/agent-engine-data-egress-policy";
import type { EngineSelection } from "@/server/agent-engine-contract";

const selection: EngineSelection = {
  engineId: "codex",
  authMode: "managed",
  operation: "new-run",
  workflow: "interactive",
  dataClass: "synthetic",
  requiredCapabilities: [],
  now: 1_800_000_000_000,
};

const qualifiedEvidence: EngineDataEgressEvidence = {
  endpoint: "https://api.openai.com/v1",
  allowedHosts: ["api.openai.com"],
  acceptedDataClasses: ["synthetic"],
  vendorDpaStatus: "verified",
  transferGeography: "eea",
  deletionSupport: "verified",
  approvalRequired: false,
};

describe("engine data-egress policy", () => {
  it("authorizes a qualified synthetic dispatch and returns auditable metadata", () => {
    expect(authorizeEngineDataEgress(selection, qualifiedEvidence)).toEqual({
      endpoint: "https://api.openai.com/v1",
      engineId: "codex",
      authMode: "managed",
      dataClass: "synthetic",
      vendorDpaStatus: "verified",
      transferGeography: "eea",
      deletionSupport: "verified",
      approvalRequired: false,
    });
  });

  it("fails closed when evidence is missing", () => {
    expect(() => authorizeEngineDataEgress(selection, undefined)).toThrowError(
      expect.objectContaining({ code: "engine_egress_denied" }),
    );
  });

  it.each([
    ["unverified DPA", { ...qualifiedEvidence, vendorDpaStatus: "unverified" }],
    ["unaccepted data class", { ...qualifiedEvidence, acceptedDataClasses: [] }],
    ["unknown endpoint host", { ...qualifiedEvidence, endpoint: "https://evil.example.test/v1" }],
  ] as const)("fails closed for %s", (_label, evidence) => {
    expect(() => authorizeEngineDataEgress(selection, evidence)).toThrowError(
      expect.objectContaining({ code: "engine_egress_denied" }),
    );
  });

  it("requires verified deletion support before customer data can leave the platform", () => {
    const evidence = { ...qualifiedEvidence, acceptedDataClasses: ["customer"] as const, deletionSupport: "unsupported" as const };
    expect(() => authorizeEngineDataEgress({ ...selection, dataClass: "customer" }, evidence)).toThrowError(
      expect.objectContaining({ code: "engine_egress_denied" }),
    );
  });

  it("allows synthetic qualification when provider erasure evidence is unavailable", () => {
    const decision = authorizeEngineDataEgress(selection, { ...qualifiedEvidence, deletionSupport: "unknown" });
    expect(decision.deletionSupport).toBe("unknown");
  });

  it("refuses a policy that requires approval when no approval is supplied", () => {
    expect(() => authorizeEngineDataEgress(selection, { ...qualifiedEvidence, approvalRequired: true })).toThrowError(
      expect.objectContaining({ code: "engine_egress_approval_required" }),
    );
  });

  it("does not expose credential or payload fields in the decision", () => {
    const decision = authorizeEngineDataEgress(selection, qualifiedEvidence);
    expect(decision).not.toHaveProperty("accessToken");
    expect(decision).not.toHaveProperty("text");
  });
});
