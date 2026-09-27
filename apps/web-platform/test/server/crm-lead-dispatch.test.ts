import { describe, expect, it } from "vitest";
import { soleurPlatformToolsForTests } from "@/server/cc-dispatcher";

const CRM_TOOL_NAMES = [
  "crm_contact_list",
  "crm_contact_get",
  "crm_note_list",
  "crm_stage_transitions_list",
  "crm_contact_upsert",
  "crm_note_append",
  "crm_contact_set_stage",
] as const;

const FORBIDDEN_SCHEMA_KEYS = ["userId", "user_id", "p_user_id"] as const;

function toolNames(crmLead: boolean): string[] {
  return soleurPlatformToolsForTests({ userId: "u", crmLead }).map((tool) => tool.name);
}

// crm-tools.test.ts reads `.schema` off the SDK tool() stub. The real SDK
// stores the same raw shape on `.inputSchema`. Skip when neither is present.
function assertNoUserIdentitySchemaKey(tools: readonly { name: string }[]) {
  for (const tool of tools) {
    const record = tool as { schema?: unknown; inputSchema?: unknown };
    const schema = record.schema ?? record.inputSchema;
    if (!schema || typeof schema !== "object") continue;
    const keys = Object.keys(schema as Record<string, unknown>);
    for (const key of FORBIDDEN_SCHEMA_KEYS) {
      expect(keys).not.toContain(key);
    }
  }
}

describe("soleurPlatformToolsForTests — crmLead", () => {
  it("includes the seven crm tools only when crmLead is true", () => {
    const on = soleurPlatformToolsForTests({ userId: "u", crmLead: true });
    const onNames = on.map((tool) => tool.name);
    const offNames = toolNames(false);

    for (const name of CRM_TOOL_NAMES) {
      expect(onNames).toContain(name);
      expect(offNames).not.toContain(name);
    }
    assertNoUserIdentitySchemaKey(on);
  });
});
