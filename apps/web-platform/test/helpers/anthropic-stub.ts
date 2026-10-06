// A scripted stand-in for the Anthropic Messages API, for tests that must drive
// the REAL Agent SDK / CLI through one tool call without a model, a credential
// or the network. EVERY request that carries tools and no tool_result answers
// with one `Bash` tool_use (the stub keeps no state, so keep the command
// side-effect free: `true`); every other request answers with plain text.
//
// Point the CLI at it with ANTHROPIC_BASE_URL. The model is out of the
// assertion path (the sharp-edge rule for LLM-mediated security tests): what a
// test observes is the SDK's own behaviour, never the model's compliance.

import http from "node:http";

export interface AnthropicStub {
  port: number;
  requests: () => number;
  close: () => Promise<void>;
}

export async function startAnthropicStub(command: string): Promise<AnthropicStub> {
  let requests = 0;
  const server = http.createServer((req, res) => {
    let body = "";
    req.on("data", (chunk) => (body += chunk));
    req.on("end", () => {
      requests += 1;
      let parsed: {
        stream?: boolean;
        model?: string;
        max_tokens?: number;
        tools?: unknown[];
        messages?: unknown;
      } = {};
      try {
        parsed = JSON.parse(body || "{}");
      } catch {
        // an unparseable body gets the plain-text answer
      }
      const hasResult = JSON.stringify(parsed.messages ?? []).includes('"tool_result"');
      const tiny = typeof parsed.max_tokens === "number" && parsed.max_tokens <= 1;
      const toolTurn =
        !hasResult && !tiny && Array.isArray(parsed.tools) && parsed.tools.length > 0;
      const model = parsed.model ?? "claude-haiku-4-5-20251001";
      const stop = toolTurn ? "tool_use" : "end_turn";
      const text = tiny ? "ok" : "done";

      if (!parsed.stream) {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(
          JSON.stringify({
            id: "msg_stub",
            type: "message",
            role: "assistant",
            model,
            content: toolTurn
              ? [{ type: "tool_use", id: "toolu_stub1", name: "Bash", input: { command } }]
              : [{ type: "text", text }],
            stop_reason: stop,
            stop_sequence: null,
            usage: { input_tokens: 5, output_tokens: 5 },
          }),
        );
        return;
      }

      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache" });
      const send = (event: string, data: unknown) =>
        res.write(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`);
      send("message_start", {
        type: "message_start",
        message: {
          id: "msg_stub",
          type: "message",
          role: "assistant",
          model,
          content: [],
          stop_reason: null,
          stop_sequence: null,
          usage: { input_tokens: 5, output_tokens: 1 },
        },
      });
      if (toolTurn) {
        send("content_block_start", {
          type: "content_block_start",
          index: 0,
          content_block: { type: "tool_use", id: "toolu_stub1", name: "Bash", input: {} },
        });
        send("content_block_delta", {
          type: "content_block_delta",
          index: 0,
          delta: { type: "input_json_delta", partial_json: JSON.stringify({ command }) },
        });
      } else {
        send("content_block_start", {
          type: "content_block_start",
          index: 0,
          content_block: { type: "text", text: "" },
        });
        send("content_block_delta", {
          type: "content_block_delta",
          index: 0,
          delta: { type: "text_delta", text },
        });
      }
      send("content_block_stop", { type: "content_block_stop", index: 0 });
      send("message_delta", {
        type: "message_delta",
        delta: { stop_reason: stop, stop_sequence: null },
        usage: { output_tokens: 5 },
      });
      send("message_stop", { type: "message_stop" });
      res.end();
    });
  });

  const port = await new Promise<number>((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", () => {
      const address = server.address();
      if (address && typeof address === "object") resolve(address.port);
      else reject(new Error("anthropic-stub: no port"));
    });
  });

  return {
    port,
    requests: () => requests,
    close: () =>
      new Promise<void>((resolve) => {
        server.close(() => resolve());
        server.closeAllConnections?.();
      }),
  };
}
