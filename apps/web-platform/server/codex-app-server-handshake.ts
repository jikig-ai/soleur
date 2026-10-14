import {
  createCodexInitializeRequest,
  createCodexInitializedNotification,
  type CodexRpcRequest,
  type CodexRpcNotification,
} from "./codex-app-server-protocol";

interface CodexHandshakeClient {
  request(request: CodexRpcRequest): Promise<Record<string, unknown>>;
  notify(notification: CodexRpcNotification): Promise<void>;
}

/** Complete the required initialize/initialized sequence before lifecycle calls. */
export async function createCodexAppServerHandshake(
  client: CodexHandshakeClient,
  requestId: string,
): Promise<Record<string, unknown>> {
  const result = await client.request(createCodexInitializeRequest(requestId));
  await client.notify(createCodexInitializedNotification());
  return result;
}
