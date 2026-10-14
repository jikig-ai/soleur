const CRM_LEAD_MODE_PATH = /^crm-lead\/[^/]+\.mode$/;

/** Per-conversation mode sentinel. Unique so the context_path index does not collapse threads. */
export function crmLeadModePath(conversationId: string): string {
  return `crm-lead/${conversationId}.mode`;
}

/** True only for a server-stamped crm-lead mode path, not a KB document. */
export function isCrmLeadModePath(path: string | null | undefined): boolean {
  return typeof path === "string" && CRM_LEAD_MODE_PATH.test(path);
}
