export interface HealthState {
  cliProcess: unknown | null;
  cliState: string;
  messageQueue: { length: number };
  startTime: number;
  messagesProcessed: number;
}

export function createHealthServer(port: number, state: HealthState) {
  return Bun.serve({
    port,
    hostname: "127.0.0.1",
    fetch(req) {
      const url = new URL(req.url);
      if (url.pathname === "/health" && req.method === "GET") {
        const healthy = state.cliProcess !== null && state.cliState === "ready";
        return Response.json(
          {
            status: healthy ? "ok" : "degraded",
            cli: state.cliState,
            bot: "running",
            queue: state.messageQueue.length,
            uptime: Math.floor((Date.now() - state.startTime) / 1000),
            messagesProcessed: state.messagesProcessed,
          },
          { status: healthy ? 200 : 503 },
        );
      }
      return new Response("Not found", { status: 404 });
    },
  });
}
