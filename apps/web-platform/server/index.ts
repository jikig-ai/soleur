// MUST be first import — before next, ws, or any app code.
// instrumentation.ts register() is NOT called by Next.js with custom servers.
import "../sentry.server.config";

import { createServer } from "http";
import next from "next";
import { parse } from "url";
import { setupWebSocket } from "./ws-handler";
import { cleanupOrphanedConversations, startInactivityTimer } from "./agent-runner";
import { handleConversationMessages } from "./api-messages";
import { createChildLogger } from "./logger";

const log = createChildLogger("startup");

const port = parseInt(process.env.PORT || "3000", 10);
const dev = process.env.NODE_ENV !== "production";
const app = next({ dev });
const handle = app.getRequestHandler();

async function checkSupabase(): Promise<boolean> {
  try {
    const response = await fetch(
      `${process.env.NEXT_PUBLIC_SUPABASE_URL}/rest/v1/`,
      {
        headers: { apikey: process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY! },
        signal: AbortSignal.timeout(2000),
      },
    );
    return response.ok;
  } catch {
    return false;
  }
}

app.prepare().then(() => {
  const server = createServer(async (req, res) => {
    const parsedUrl = parse(req.url!, true);

    // Health check for deployment
    if (parsedUrl.pathname === "/health") {
      const supabaseOk = await checkSupabase();
      const healthy = supabaseOk;
      res.writeHead(healthy ? 200 : 503, { "Content-Type": "application/json" });
      res.end(JSON.stringify({
        status: healthy ? "ok" : "degraded",
        version: process.env.BUILD_VERSION || "dev",
        supabase: supabaseOk ? "connected" : "error",
        uptime: Math.floor(process.uptime()),
        memory: Math.floor(process.memoryUsage().rss / 1024 / 1024),
      }));
      return;
    }

    // REST API: conversation message history
    const messagesMatch = parsedUrl.pathname?.match(
      /^\/api\/conversations\/([^/]+)\/messages$/,
    );
    if (messagesMatch && req.method === "GET") {
      handleConversationMessages(req, res, messagesMatch[1]);
      return;
    }

    handle(req, res, parsedUrl);
  });

  setupWebSocket(server);

  // Clean up conversations left in active/waiting_for_user from before restart
  cleanupOrphanedConversations().catch((err) => {
    log.error({ err }, "Failed to clean up orphaned conversations");
  });

  // Start periodic inactivity check (24h timeout, hourly checks)
  startInactivityTimer();

  server.listen(port, () => {
    log.info({ port, env: dev ? "development" : "production" }, "Server ready");
  });
});
