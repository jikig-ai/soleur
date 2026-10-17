import type { CodexConversationDispatchOptions } from "./codex-conversation-dispatch";
import type { EngineDataClass } from "./agent-engine-contract";

/** Server-owned composition. Qualification, egress disposition, and the
 * approved App Server launcher have not been installed for live Web traffic.
 * Keeping these absent makes a persisted Codex binding fail closed.
 */
export function codexConversationRuntime(userId: string): Pick<CodexConversationDispatchOptions, "runtime" | "evidence" | "registry"> & { dataClass: EngineDataClass } {
  return {
    runtime: { userId },
    dataClass: "customer",
    evidence: {
      endpoint: "https://api.openai.com/v1",
      allowedHosts: ["api.openai.com"],
      acceptedDataClasses: [],
      vendorDpaStatus: "unverified",
      transferGeography: "unknown",
      deletionSupport: "unknown",
      approvalRequired: true,
    },
  };
}
