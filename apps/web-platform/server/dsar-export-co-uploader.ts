import { createServiceClient } from "@/lib/supabase/service";
import { pseudonymiseUserId } from "./dsar-export";
import { hashUserId } from "./observability";
import { createChildLogger } from "./logger";

const log = createChildLogger("dsar-export");

const IN_BATCH_SIZE = 500;

interface CoUploaderManifestEntry {
  path: string;
  included: false;
  redacted: true;
  redaction_reason: "art-15-co-uploader";
  uploader_pseudonym: string;
  article: "15";
  bytes: number;
}

export async function enumerateCoUploaderAttachments(
  expectedUserId: string,
  pseudonymSalt: Buffer,
  signal: AbortSignal,
): Promise<CoUploaderManifestEntry[]> {
  const service = createServiceClient();
  const entries: CoUploaderManifestEntry[] = [];

  const { data: memberRows } = await service
    .from("workspace_members")
    .select("workspace_id")
    .eq("user_id", expectedUserId);
  if (signal.aborted) throw new Error("aborted");

  const workspaceIds = (memberRows ?? [])
    .map((r) => r.workspace_id)
    .filter(Boolean);
  if (workspaceIds.length === 0) return entries;

  let allConvIds: string[] = [];
  for (let i = 0; i < workspaceIds.length; i += IN_BATCH_SIZE) {
    const batch = workspaceIds.slice(i, i + IN_BATCH_SIZE);
    // visibility-sweep-audit: co-uploader DSAR — workspace-scoped by design (finds other users' conversations)
    const { data: convRows } = await service
      .from("conversations")
      .select("id")
      .in("workspace_id", batch)
      .neq("user_id", expectedUserId);
    if (signal.aborted) throw new Error("aborted");
    allConvIds = allConvIds.concat(
      (convRows ?? []).map((r) => r.id).filter(Boolean),
    );
  }
  if (allConvIds.length === 0) return entries;

  const msgUserIdMap = new Map<string, string>();
  for (let i = 0; i < allConvIds.length; i += IN_BATCH_SIZE) {
    const batch = allConvIds.slice(i, i + IN_BATCH_SIZE);
    const { data: msgRows } = await service
      .from("messages")
      .select("id, user_id")
      .in("conversation_id", batch)
      .limit(10000);
    if (signal.aborted) throw new Error("aborted");
    for (const row of msgRows ?? []) {
      if (row.user_id && row.user_id !== expectedUserId) {
        msgUserIdMap.set(row.id, row.user_id);
      }
    }
  }
  const coUploaderMsgIds = [...msgUserIdMap.keys()];
  if (coUploaderMsgIds.length === 0) return entries;

  let allAttachments: Array<{
    message_id: string;
    storage_path: string;
    size_bytes: number;
    filename: string;
    content_type: string;
  }> = [];
  for (let i = 0; i < coUploaderMsgIds.length; i += IN_BATCH_SIZE) {
    const batch = coUploaderMsgIds.slice(i, i + IN_BATCH_SIZE);
    const { data: attachRows } = await service
      .from("message_attachments")
      .select("message_id, storage_path, size_bytes, filename, content_type")
      .in("message_id", batch)
      .limit(10000);
    if (signal.aborted) throw new Error("aborted");
    allAttachments = allAttachments.concat(attachRows ?? []);
  }

  for (const att of allAttachments) {
    const uploaderUserId = msgUserIdMap.get(att.message_id);
    if (!uploaderUserId) continue;
    const rawPath = att.storage_path || att.filename;
    if (!rawPath) continue;
    const pseudonym = pseudonymiseUserId(uploaderUserId, pseudonymSalt);
    const pathParts = rawPath.split("/");
    if (pathParts.length >= 2) {
      pathParts[0] = pseudonym;
    }
    entries.push({
      path: `attachments/co-uploader/${pathParts.join("/")}`,
      included: false,
      redacted: true,
      redaction_reason: "art-15-co-uploader",
      uploader_pseudonym: pseudonym,
      article: "15",
      bytes: att.size_bytes ?? 0,
    });
  }

  log.info(
    {
      feature: "dsar-export",
      op: "co-uploader-enumerate",
      userIdHash: hashUserId(expectedUserId),
      count: entries.length,
    },
    "enumerated co-uploader attachments",
  );

  return entries;
}
