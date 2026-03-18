import { createServer } from "http";
import next from "next";
import { parse } from "url";
import { setupWebSocket } from "./ws-handler";

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

    handle(req, res, parsedUrl);
  });

  setupWebSocket(server);

  server.listen(port, () => {
    console.log(`> Ready on http://localhost:${port}`);
    console.log(`> WebSocket server attached`);
    console.log(`> Environment: ${dev ? "development" : "production"}`);
  });
});
