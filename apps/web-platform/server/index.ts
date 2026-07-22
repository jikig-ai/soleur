// MUST be first import — before next, ws, or any app code.
// instrumentation.ts register() is NOT called by Next.js with custom servers.
import "../sentry.server.config";

import * as Sentry from "@sentry/nextjs";
import { createServer } from "http";
import next from "next";
import { parse } from "url";
import { WebSocket } from "ws";
import { setupWebSocket, attachProxiedSession } from "./ws-handler";
import { createProxyServer } from "./session-proxy";
import { logProxyCertExpiryAtStartup } from "./proxy-tls";
import { streamReplayBuffer } from "./stream-replay-buffer";
import { WS_CLOSE_CODES } from "@/lib/types";
import {
  abortAllSessions,
  cleanupOrphanedConversations,
  startInactivityTimer,
  startStuckActiveReaper,
} from "./agent-runner";
import {
  drainCcQueriesForShutdown,
  startCcIdleReaper,
} from "./cc-dispatcher";
import { handleConversationMessages } from "./api-messages";
import { releaseAllHeldLeases } from "./worktree-write-lease";
import { createChildLogger } from "./logger";
import { installCrashHandlers } from "./crash-handlers";
import { verifyPluginMountOnce } from "./plugin-mount-check";
import { assertSingleReplicaInvariant } from "./single-replica-assertion";
import { emitTeamWorkspaceInviteBootBreadcrumb } from "./team-workspace-boot";
import {
  buildHealthResponse,
  buildInternalMetricsResponse,
} from "./health";
import {
  handleReadyzRequest,
  verifyWorkspacesMountOnce,
} from "./readiness";
import { isLoopbackHost } from "./loopback";
// NOTE: do NOT statically import "@/server/inngest/client" here — it throws at
// module-load when INNGEST_SIGNING_KEY is unset (client.ts), which would crash
// the server at startup in environments without Inngest configured (e2e CI,
// local dev). The self-arm below dynamic-imports it inside an INNGEST_SIGNING_KEY
// guard so the client only loads where Inngest is actually configured.
import { sendInngestWithRetry } from "@/server/inngest/send-with-retry";
import { reportSilentFallback } from "@/server/observability";

// isLoopbackHost (the /internal/metrics + /internal/readyz Host-header gate)
// lives in ./loopback — a leaf module shared with readiness.ts so the loopback
// logic has a single source of truth. See ./loopback for the CF-tunnel rationale.

const log = createChildLogger("startup");

// #5417 — attribute crash-driven restarts. Installed at module scope (before any
// async server setup that could itself throw) so a fatal at any point is
// captured to Sentry and turned into a clean process.exit(1) restart instead of
// an un-attributable churn. sentry.server.config.ts disables Sentry's auto
// OnUncaughtException/OnUnhandledRejection integrations so these report once.
installCrashHandlers();

const port = parseInt(process.env.PORT || "3000", 10);
const dev = process.env.NODE_ENV !== "production";
const app = next({ dev });
const handle = app.getRequestHandler();

app.prepare().then(() => {
  assertSingleReplicaInvariant();
  verifyPluginMountOnce();
  // #5966 — one-shot boot-time deep-readiness mirror. verifyPluginMountOnce
  // above checks the PLUGIN mount, not /workspaces; this covers the host-local
  // workspace volume so a mis-mounted/read-only web-1 surfaces a Sentry event
  // at boot instead of only when a live request hits an empty /workspaces.
  verifyWorkspacesMountOnce();
  emitTeamWorkspaceInviteBootBreadcrumb();

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

    // Deep-readiness (#5966, ADR-068 Sharp Edge C1). Unlike /health (liveness:
    // status:"ok" + shared-Supabase probe), this answers "can THIS host serve?"
    // — /workspaces writable + populated. Gated to the loopback transport peer
    // and returns 503 when the host cannot serve locally. All gating + the
    // fail-closed try/catch live in handleReadyzRequest (server/readiness.ts).
    if (parsedUrl.pathname === "/internal/readyz") {
      handleReadyzRequest(req, res);
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

  // #5274 Phase 3 Sub-PR 3.D (ADR-068 b2) — the OWNER host's private-net TLS
  // proxy listener. A session that lands on a non-owning web host is relayed
  // here (session-proxy.ts) and attached as a PRE-AUTHENTICATED native session
  // via `attachProxiedSession`. `createProxyServer` returns null in dev/
  // single-host (no PROXY_TLS material, or SOLEUR_PROXY_BIND unset) — entirely
  // inert, no throw. Log the long-lived cert's expiry once at startup (the only
  // expiry signal besides the Better Stack monitor).
  logProxyCertExpiryAtStartup();
  const proxyServer = createProxyServer({
    onProxiedSession: (proxiedWs, ctx) => {
      attachProxiedSession(proxiedWs, ctx).catch((err) => {
        reportSilentFallback(err, {
          feature: "control_plane_route",
          op: "proxied-attach",
          extra: { userId: ctx.userId, workspaceId: ctx.workspaceId },
        });
      });
    },
  });

  // Clean up conversations left in active/waiting_for_user from before restart
  cleanupOrphanedConversations().catch((err) => {
    log.error({ err }, "Failed to clean up orphaned conversations");
  });

  // Start periodic inactivity check (24h timeout, hourly checks)
  startInactivityTimer();

  // Start periodic stuck-active reaper (300s poll cadence, 240s slot-heartbeat
  // staleness threshold — SLOT_STALENESS_THRESHOLD_SECONDS, mig 133).
  // Defense-in-depth against the AC1 try/catch wrap:
  // catches process-killed-mid-stream + future regressions that strand
  // conversations at status='active'. See agent-runner.ts for the full
  // contract. Capture the timer so SIGTERM can stop it explicitly —
  // .unref() already prevents shutdown blocking, but explicit cleanup
  // avoids in-flight releaseSlot calls during shutdown.
  const stuckActiveReaperTimer = startStuckActiveReaper();

  // #5371 — start the cc-soleur-go idle reaper. `reapIdle()` existed on the
  // runner but nothing wired it at runtime, so idle cc queries persisted in
  // `activeQueries` until container restart (memory leak + a second
  // disconnect-class gap: a tab abandoned WITHOUT a socket close never fires
  // the ws-handler grace timer). Capture the timer so SIGTERM can stop it;
  // .unref() already prevents shutdown blocking (see startCcIdleReaper).
  const ccIdleReaperTimer = startCcIdleReaper();

  // Self-arm the one-time #4650 monitor-close oneshot (#4654). boot == deploy
  // (web-platform-release.yml restarts the container on every apps/web-platform/**
  // merge), so this re-fires each deploy; the stable event `id` dedups within
  // Inngest's window, and the handler's already-closed check is the cross-boot
  // idempotency guarantee. Future-`ts` delivery is the supported primitive; the
  // late-merge (past-`ts`) edge degrades gracefully (#4650 self-recovers via the
  // watchdog backstop). Guarded IIFE so even a synchronous throw routes to Sentry
  // rather than escaping as an unhandledRejection — under ADR-033 this oneshot
  // has NO Sentry monitor, so this catch is the only signal for a lost arm.
  // Only arm where Inngest is configured (prod). Absent the signing key (e2e CI,
  // local dev), skip entirely — there is no Inngest server to arm against, and
  // loading the client would throw at module-load.
  if (process.env.INNGEST_SIGNING_KEY) {
    void (async () => {
      try {
        const { inngest } = await import("@/server/inngest/client");
        await sendInngestWithRetry(
          () =>
            inngest.send({
              name: "oneshot/monitor-close-4650.fire",
              id: "oneshot-4650-close-2026-05-31-v1",
              ts: new Date("2026-05-31T09:00:00Z").getTime(),
              data: {
                issue: 4650,
                expected_date: "2026-05-31",
                actor: "platform" as const,
              },
            }),
          { feature: "oneshot-4650-arm", eventId: "oneshot-4650-close-2026-05-31-v1" },
        );
      } catch (err) {
        reportSilentFallback(err, {
          feature: "oneshot-4650-arm",
          op: "self-arm-send",
          message: "failed to arm oneshot-4650-monitor-close at boot",
        });
      }
    })();

    // Self-arm the one-time watchdog-recovery verifier (PR #4881 follow-up).
    // Fires at 2026-06-04 09:45 UTC (15 min after the daily 09:30 heartbeat) to
    // confirm the legal-audit/strategy-review false positives do NOT re-fire and
    // report community-monitor's genuine recovery to #2714. Same deploy-and-forget
    // contract as the 4650 arm above: stable event `id` dedups across re-deploys,
    // future-`ts` is the supported delivery primitive, and the oneshot has NO
    // Sentry monitor so this catch is the only signal for a lost arm.
    void (async () => {
      try {
        const { inngest } = await import("@/server/inngest/client");
        await sendInngestWithRetry(
          () =>
            inngest.send({
              name: "oneshot/heartbeat-recovery-verify.fire",
              id: "oneshot-heartbeat-recovery-verify-2026-06-04-v1",
              ts: new Date("2026-06-04T09:45:00Z").getTime(),
              data: {
                expected_date: "2026-06-04",
                actor: "platform" as const,
              },
            }),
          {
            feature: "oneshot-heartbeat-recovery-verify-arm",
            eventId: "oneshot-heartbeat-recovery-verify-2026-06-04-v1",
          },
        );
      } catch (err) {
        reportSilentFallback(err, {
          feature: "oneshot-heartbeat-recovery-verify-arm",
          op: "self-arm-send",
          message: "failed to arm oneshot-heartbeat-recovery-verify at boot",
        });
      }
    })();
  }

  server.listen(port, () => {
    log.info({ port, env: dev ? "development" : "production" }, "Server ready");
    log.info({
      sentryConfigured: !!process.env.SENTRY_DSN,
      sentryEnvironment: process.env.NODE_ENV,
    }, "Sentry status");

    if (process.env.SENTRY_DSN) {
      // #5417 — tag the startup event so the restart-rate signal (the Sentry
      // "Server startup" issue) can be filtered/queried precisely: the
      // container-restart-monitor is the authoritative host-side rate alarm,
      // and AC12 reads this issue's stats API to verify the post-fix rate drop.
      Sentry.captureMessage(
        `Server startup v${process.env.BUILD_VERSION || "dev"}`,
        { level: "info", tags: { event_type: "server-startup" } },
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
    // #5371 — stop the cc idle reaper before draining for the same reason.
    clearInterval(ccIdleReaperTimer);

    // Abort all active agent sessions first — stops API credit consumption
    // and triggers the catch block which updates conversation status to "failed".
    abortAllSessions();
    // #5371 — drain in-flight cc-soleur-go queries on shutdown. Aborts
    // WITHOUT checkpoint (legacy abortAllSessions parity); the disconnect
    // grace-abort terminal (#5362) is what preserves uncommitted work. Log
    // the count so a stuck deploy can tell "drain ran, closed N" from "drain
    // never reached" without SSH.
    const drained = drainCcQueriesForShutdown();
    log.info({ drained }, "cc drain on shutdown");
    // feat-stream-since-disconnect (#5273) — drain the in-memory replay buffer
    // on shutdown (process-local; nothing to persist). See ADR-059.
    streamReplayBuffer.clearAll();

    // #5274 PR B — gracefully release every worktree write-lease this host
    // holds so a surviving host reclaims immediately rather than waiting out the
    // 240s heartbeat expiry. Best-effort + bounded (allSettled, never throws);
    // a lease that fails to release simply expires. Inert when the lease path is
    // gated off (the registry is empty) — no git-data dependency at flag-off.
    await releaseAllHeldLeases();

    server.close();
    server.closeIdleConnections();

    // #5274 3.D — stop accepting new proxied sessions from peer hosts. Inert
    // (null) in dev/single-host. In-flight proxied sessions drain via the wss
    // client-close loop below, same as native ones.
    if (proxyServer) proxyServer.close();

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
