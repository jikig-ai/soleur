// MUST be first import — before next, ws, or any app code.
// instrumentation.ts register() is NOT called by Next.js with custom servers.
import "../sentry.server.config";

import * as Sentry from "@sentry/nextjs";
import { createServer } from "http";
import next from "next";
import { parse } from "url";
import { WebSocket } from "ws";
import { setupWebSocket } from "./ws-handler";
import { WS_CLOSE_CODES } from "@/lib/types";
import { cleanupOrphanedConversations, startInactivityTimer } from "./agent-runner";
import { handleConversationMessages } from "./api-messages";
import { createChildLogger } from "./logger";
import { buildHealthResponse } from "./health";

const log = createChildLogger("startup");

const port = parseInt(process.env.PORT || "3000", 10);
const dev = process.env.NODE_ENV !== "production";
const app = next({ dev });
const handle = app.getRequestHandler();

app.prepare().then(() => {
  const server = createServer(async (req, res) => {
    const parsedUrl = parse(req.url!, true);

    // Health check for deployment
    if (parsedUrl.pathname === "/health") {
      // Always return 200 — the server is running and serving traffic.
      // Supabase/Sentry status is informational; a degraded dependency should not
      // cause deploy verification or load balancer health checks to fail.
      const health = await buildHealthResponse();
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(health));
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

  const wss = setupWebSocket(server);

  // Clean up conversations left in active/waiting_for_user from before restart
  cleanupOrphanedConversations().catch((err) => {
    log.error({ err }, "Failed to clean up orphaned conversations");
  });

  // Start periodic inactivity check (24h timeout, hourly checks)
  startInactivityTimer();

  server.listen(port, () => {
    log.info({ port, env: dev ? "development" : "production" }, "Server ready");
    log.info({
      sentryConfigured: !!process.env.SENTRY_DSN,
      sentryEnvironment: process.env.NODE_ENV,
    }, "Sentry status");

    if (process.env.SENTRY_DSN) {
      Sentry.captureMessage(
        `Server startup v${process.env.BUILD_VERSION || "dev"}`,
        "info",
      );
    }
  });

  const SHUTDOWN_TIMEOUT_MS = 8_000;
  let shuttingDown = false;

  process.on("SIGTERM", async () => {
    if (shuttingDown) return;
    shuttingDown = true;

    log.info("SIGTERM received, starting graceful shutdown...");

    const forceExit = setTimeout(() => {
      log.warn("Shutdown timeout reached, forcing exit");
      server.closeAllConnections();
      process.exit(1);
    }, SHUTDOWN_TIMEOUT_MS);
    forceExit.unref();

    server.close();
    server.closeIdleConnections();

    for (const client of wss.clients) {
      if (client.readyState === WebSocket.OPEN) {
        client.close(WS_CLOSE_CODES.SERVER_GOING_AWAY, "Server shutting down");
      }
    }

    await Sentry.flush(2_000);

    log.info("Graceful shutdown complete");
    process.exit(0);
  });
});
