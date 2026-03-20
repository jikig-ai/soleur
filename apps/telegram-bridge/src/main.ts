/**
 * Telegram Bridge entrypoint — starts the health server before heavy imports.
 *
 * The health HTTP listener binds within milliseconds of container start,
 * returning 503 ("degraded") while grammY and the rest of the app load.
 * This avoids the CI health check timeout caused by >120s module resolution.
 */

import { createHealthServer, type HealthState } from "./health";

const HEALTH_PORT = 8080;

const healthState: HealthState = {
  cliProcess: null,
  cliState: "connecting",
  messageQueue: { length: 0 },
  startTime: Date.now(),
  messagesProcessed: 0,
};

const healthServer = createHealthServer(HEALTH_PORT, healthState);
console.log(`Health endpoint listening on http://127.0.0.1:${HEALTH_PORT}/health`);

// Dynamically import the application to defer heavy dependency resolution
// (grammY, @grammyjs/parse-mode, etc.).
// try/catch keeps the health server alive if the app fails to load --
// Docker HEALTHCHECK will eventually mark unhealthy and restart.
try {
  const app = await import("./index");
  app.boot(healthState, healthServer);
} catch (err) {
  console.error("FATAL: Failed to load application:", err);
}
