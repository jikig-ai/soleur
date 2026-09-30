import { withUserRateLimit } from "@/server/with-user-rate-limit";
import { inboxBulkArchiveHandler } from "@/server/inbox-bulk-archive-handler";

export const dynamic = "force-dynamic";

export const POST = withUserRateLimit(inboxBulkArchiveHandler, {
  perMinute: 20,
  feature: "inbox.bulk-archive",
});
