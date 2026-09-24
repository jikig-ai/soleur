import { StepError, serializeError } from "inngest";

/**
 * Drive an Inngest handler the way async-mode Inngest does at a STEP BOUNDARY
 * (#8726). An in-process mock (`step.run = (_, cb) => cb()`) hides three things
 * production shows a handler, and every one of them hid a shipped defect:
 *
 *   1. An error that exhausts a step's retries reaches the handler as the SDK's
 *      rebuilt `StepError` — `name === "Error"`, no custom class, no custom
 *      fields. `instanceof SomeCustomError` in the handler never matches.
 *   2. A NON-final step failure is never visible to handler code: the SDK ends
 *      the request and retries the step.
 *   3. After every new step the handler is re-entered from the top with memoized
 *      results, so a variable assigned inside a step callback does not survive
 *      to the next step.
 *
 * Error rebuilding delegates to the REAL `serializeError` + `StepError` from the
 * `inngest` package (pinned exactly in package.json), never to a hand model.
 *
 * Assumptions, stated because they are not all derivable from the SDK:
 *   - Async mode, one new step per request. `server/inngest/client.ts` enables no
 *     `checkpointing`; turning it on would change this model.
 *   - GUESSED: `attempt` resets to 0 after a step settles (success or exhausted
 *     failure). Inngest documents a per-step retry counter, which supports it,
 *     but the value the server sends is not in the SDK. No scenario in this repo
 *     asserts on it.
 *   - Handler-level retries are NOT modelled: a handler throw ends the run with
 *     outcome `threw`, a handler return ends it with outcome `returned`.
 */

export class HarnessError extends Error {
  constructor(message: string) {
    super(`[inngest-step-harness] ${message}`);
    this.name = "HarnessError";
  }
}

export type MemoEntry =
  | { ok: true; data: unknown }
  | { ok: false; error: StepError };

export type StepMemo = Map<string, MemoEntry>;

export interface HarnessStep {
  run<T>(id: string, cb: () => Promise<T>): Promise<T>;
}

export interface HarnessCtx {
  step: HarnessStep;
  attempt: number;
  maxAttempts: number;
}

export interface RunOutcome<R> {
  outcome: "returned" | "threw";
  value?: R;
  error?: unknown;
  invocations: number;
}

/** The error a handler sees after a step exhausts its retries, built by the SDK's own code. */
export function rebuildAsStepError(stepId: string, err: unknown): StepError {
  return new StepError(stepId, JSON.parse(JSON.stringify(serializeError(err))));
}

const NEVER = <T>(): Promise<T> => new Promise<T>(() => {});

function toJson(v: unknown): unknown {
  // The SDK memoizes `undefinedToNull(data)`; a bare JSON.stringify(undefined)
  // returns undefined and the parse would throw on every step returning nothing.
  return JSON.parse(JSON.stringify(v ?? null));
}

export async function runLikeInngest<R>(
  invoke: (ctx: HarnessCtx) => Promise<R>,
  opts: { maxAttempts: number; memo?: StepMemo; maxInvocations?: number },
): Promise<RunOutcome<R>> {
  const memo = opts.memo ?? new Map<string, MemoEntry>();
  const cap = opts.maxInvocations ?? 50;
  let attempt = 0;

  for (let invocation = 1; invocation <= cap; invocation++) {
    const seen = new Set<string>();
    let stop!: (reason: { harnessError?: HarnessError; nextAttempt: number }) => void;
    const interrupted = new Promise<{ harnessError?: HarnessError; nextAttempt: number }>(
      (res) => (stop = res),
    );
    const currentAttempt = attempt;

    const step: HarnessStep = {
      async run<T>(id: string, cb: () => Promise<T>): Promise<T> {
        // Counted PER INVOCATION: the SDK suffixes a repeated id as `id:1`
        // within one request, while every replay legitimately re-reads it.
        if (seen.has(id)) {
          stop({ harnessError: new HarnessError(`step id "${id}" used twice in one invocation`), nextAttempt: 0 });
          return NEVER<T>();
        }
        seen.add(id);

        const hit = memo.get(id);
        if (hit) {
          if (hit.ok) return toJson(hit.data) as T;
          throw hit.error;
        }

        let value: T;
        try {
          value = await cb();
        } catch (err) {
          if (currentAttempt < opts.maxAttempts - 1) {
            // Non-final: the SDK sends a retriable StepError op and ends the
            // request. Handler code after this await never runs in it.
            stop({ nextAttempt: currentAttempt + 1 });
            return NEVER<T>();
          }
          memo.set(id, { ok: false, error: rebuildAsStepError(id, err) });
          stop({ nextAttempt: 0 });
          return NEVER<T>();
        }

        let data: unknown;
        try {
          data = toJson(value);
        } catch (err) {
          stop({
            harnessError: new HarnessError(`step "${id}" returned a value that is not JSON-serializable: ${String(err)}`),
            nextAttempt: 0,
          });
          return NEVER<T>();
        }
        memo.set(id, { ok: true, data });
        stop({ nextAttempt: 0 });
        return NEVER<T>();
      },
    };

    const settled = invoke({ step, attempt: currentAttempt, maxAttempts: opts.maxAttempts }).then(
      (value) => ({ kind: "returned" as const, value }),
      (error: unknown) => ({ kind: "threw" as const, error }),
    );
    const first = await Promise.race([
      settled,
      interrupted.then((r) => ({ kind: "interrupted" as const, ...r })),
    ]);

    if (first.kind === "returned") return { outcome: "returned", value: first.value, invocations: invocation };
    if (first.kind === "threw") return { outcome: "threw", error: first.error, invocations: invocation };
    if (first.harnessError) throw first.harnessError;
    attempt = first.nextAttempt;
  }
  throw new HarnessError(`handler did not finish within ${cap} invocations`);
}
