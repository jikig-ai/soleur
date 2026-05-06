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
import {
  abortAllSessions,
  cleanupOrphanedConversations,
  startInactivityTimer,
  startStuckActiveReaper,
} from "./agent-runner";
import { handleConversationMessages } from "./api-messages";
import { createChildLogger } from "./logger";
import { verifyPluginMountOnce } from "./plugin-mount-check";
import {
  buildHealthResponse,
  buildInternalMetricsResponse,
} from "./health";

// Accept loopback hostnames only. resource-monitor.sh runs on the same host
// and curls http://127.0.0.1:3000/internal/metrics; external callers (via CF
// tunnel) arrive with the public Host header. This is defense-in-depth: a
// sophisticated attacker could try to spoof the Host via the tunnel, but CF
// normalizes Host for origin routing so a spoofed 127.0.0.1 header doesn't
// reach here. Port suffix is optional so e2e tests that hit a non-3000 port
// still match.
function isLoopbackHost(hostHeader: string | undefined): boolean {
  if (!hostHeader) return false;
  const host = hostHeader.split(":")[0];
  return host === "127.0.0.1" || host === "localhost" || host === "::1";
}

const log = createChildLogger("startup");

const port = parseInt(process.env.PORT || "3000", 10);
const dev = process.env.NODE_ENV !== "production";
const app = next({ dev });
const handle = app.getRequestHandler();

app.prepare().then(() => {
  verifyPluginMountOnce();

  const server = createServer(async (req, res) => {
    const parsedUrl = parse(req.url!, true);

    // Health check for deployment
    if (parsedUrl.pathname === "/health") {
      // Always return 200 for load balancer probes.
      // CI deploy verification (web-platform-release.yml) reads the response body
      // to gate on version match and supabase connectivity.
      const health = await buildHealthResponse();
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(health));
      return;
    }

    // Internal metrics — host CPU/RAM + concurrent-session counts (#1052).
    // Gated to loopback Host to avoid exposing capacity signals to the public
    // (DoS-tuning feedback loop) or per-user counts (competitive scraping).
    // resource-monitor.sh curls http://127.0.0.1:3000/internal/metrics.
    if (parsedUrl.pathname === "/internal/metrics") {
      if (!isLoopbackHost(req.headers.host)) {
        res.writeHead(403, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "forbidden" }));
        return;
      }
      const metrics = await buildInternalMetricsResponse();
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify(metrics));
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

  // Start periodic stuck-active reaper (60s cadence, 120s slot-heartbeat
  // staleness threshold). Defense-in-depth against the AC1 try/catch wrap:
  // catches process-killed-mid-stream + future regressions that strand
  // conversations at status='active'. See agent-runner.ts for the full
  // contract. Capture the timer so SIGTERM can stop it explicitly —
  // .unref() already prevents shutdown blocking, but explicit cleanup
  // avoids in-flight releaseSlot calls during shutdown.
  const stuckActiveReaperTimer = startStuckActiveReaper();

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

  // Must be less than Docker stop --time (12s) to allow graceful drain before SIGKILL
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

    // Stop the stuck-active reaper before aborting sessions — otherwise an
    // in-flight reaper tick could issue releaseSlot writes during shutdown.
    clearInterval(stuckActiveReaperTimer);

    // Abort all active agent sessions first — stops API credit consumption
    // and triggers the catch block which updates conversation status to "failed".
    abortAllSessions();

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
