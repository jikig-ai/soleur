import { createServer } from "http";
import next from "next";
import { parse } from "url";
import { setupWebSocket } from "./ws-handler";
import { cleanupOrphanedConversations, startInactivityTimer } from "./agent-runner";
import { handleConversationMessages } from "./api-messages";

const port = parseInt(process.env.PORT || "3000", 10);
const dev = process.env.NODE_ENV !== "production";
const app = next({ dev });
const handle = app.getRequestHandler();

app.prepare().then(() => {
  const server = createServer((req, res) => {
    const parsedUrl = parse(req.url!, true);

    // Health check for deployment
    if (parsedUrl.pathname === "/health") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ status: "ok" }));
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
    console.error("[startup] Failed to clean up orphaned conversations:", err);
  });

  // Start periodic inactivity check (24h timeout, hourly checks)
  startInactivityTimer();

  server.listen(port, () => {
    console.log(`> Ready on http://localhost:${port}`);
    console.log(`> WebSocket server attached`);
    console.log(`> Environment: ${dev ? "development" : "production"}`);
  });
});
