/**
 * Run a task after the HTTP response (#12011 PR-D). Used by the decide route for the flush-then-ack step.
 *
 * `after()` from next/server is used when it is available: under the custom server (`next(...).getRequestHandler()`) the
 * callback runs once the response has closed, so the founder's answer never waits on it. `after()` throws outside a
 * request scope (unit tests, any non-Next caller); the task is then run as a caught fire-and-forget promise, so it is
 * never silently dropped. The task is expected to report its own failures and never throw; a rejection is swallowed here.
 */

import { after } from "next/server";

export function runOffRequestPath(task: () => Promise<void>): void {
  const safe = async (): Promise<void> => {
    try {
      await task();
    } catch {
      // The task reports its own failures; nothing here may reach a response.
    }
  };
  try {
    after(safe);
  } catch {
    void safe();
  }
}
