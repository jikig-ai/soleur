import { describe, it, expect } from "vitest";
import { StepError } from "inngest";
import {
  HarnessError,
  runLikeInngest,
  type HarnessCtx,
  type StepMemo,
} from "./inngest-step-harness";

// Self-test for the step-boundary harness (#8726, plan Guard 1). Every row
// asserts FIXED facts about what production shows a handler, never a
// comparison with the harness's own rebuild — a harness that re-threw the raw
// error would otherwise agree with itself.

class ProbeCustomError extends Error {
  readonly leaseAgeMs = 1234;
  constructor() {
    super("[probe] deploy in progress (lease age 1234ms)");
    this.name = "ProbeCustomError";
  }
}

describe("runLikeInngest — step-boundary facts", () => {
  it("row 1: an exhausted step reaches the handler as the SDK's rebuilt StepError, not the thrown class", async () => {
    const out = await runLikeInngest(
      async ({ step }: HarnessCtx) => {
        try {
          await step.run("setup", async () => {
            throw new ProbeCustomError();
          });
          return { caught: null as unknown };
        } catch (err) {
          return { caught: err };
        }
      },
      { maxAttempts: 2 },
    );
    expect(out.outcome).toBe("returned");
    const caught = out.value!.caught as Error & { leaseAgeMs?: number };
    expect(caught).toBeInstanceOf(StepError);
    expect(caught).not.toBeInstanceOf(ProbeCustomError);
    expect(caught.name).toBe("Error");
    expect(caught.leaseAgeMs).toBeUndefined();
    expect(caught.message).toBe("[probe] deploy in progress (lease age 1234ms)");
  });

  it("row 2: a non-final step failure is never visible to handler code", async () => {
    let callbackRuns = 0;
    const caughtErrors: unknown[] = [];
    await runLikeInngest(
      async ({ step }: HarnessCtx) => {
        try {
          await step.run("flaky", async () => {
            callbackRuns++;
            throw new ProbeCustomError();
          });
        } catch (err) {
          caughtErrors.push(err);
        }
        return "done";
      },
      { maxAttempts: 2 },
    );
    expect(callbackRuns).toBe(2);
    expect(caughtErrors).toHaveLength(1);
    expect(caughtErrors[0]).toBeInstanceOf(StepError);
  });

  it("row 3: a variable assigned inside a step callback does not survive to the next step", async () => {
    const flagSeenByB: boolean[] = [];
    await runLikeInngest(
      async ({ step }: HarnessCtx) => {
        let flag = false;
        await step.run("a", async () => {
          flag = true;
        });
        await step.run("b", async () => {
          flagSeenByB.push(flag);
        });
        return null;
      },
      { maxAttempts: 2 },
    );
    expect(flagSeenByB).toEqual([false]);
  });

  it("row 4: the driver keeps re-entering until the handler finishes (a second step runs)", async () => {
    const ran: string[] = [];
    const out = await runLikeInngest(
      async ({ step }: HarnessCtx) => {
        await step.run("a", async () => void ran.push("a"));
        await step.run("b", async () => void ran.push("b"));
        return "end";
      },
      { maxAttempts: 2 },
    );
    expect(ran).toEqual(["a", "b"]);
    expect(out).toMatchObject({ outcome: "returned", value: "end", invocations: 3 });
  });

  it("row 5: a step returning undefined is memoized as null, like the SDK's undefinedToNull", async () => {
    const memo: StepMemo = new Map();
    const out = await runLikeInngest(
      async ({ step }: HarnessCtx) => {
        const v = await step.run("nothing", async () => undefined);
        return v;
      },
      { maxAttempts: 2, memo },
    );
    expect(out).toMatchObject({ outcome: "returned", value: null });
    expect(memo.get("nothing")).toEqual({ ok: true, data: null });
  });

  it("row 6a: a step id used twice in ONE invocation is a HarnessError", async () => {
    await expect(
      runLikeInngest(
        async ({ step }: HarnessCtx) => {
          await step.run("dup", async () => 1);
          await step.run("dup", async () => 2);
          return null;
        },
        { maxAttempts: 2 },
      ),
    ).rejects.toBeInstanceOf(HarnessError);
  });

  it("row 6b: replaying the same step ids across invocations is NOT a duplicate", async () => {
    const out = await runLikeInngest(
      async ({ step }: HarnessCtx) => {
        const a = await step.run("a", async () => 1);
        const b = await step.run("b", async () => 2);
        return a + b;
      },
      { maxAttempts: 2 },
    );
    expect(out).toMatchObject({ outcome: "returned", value: 3 });
  });

  it("row 6c: a handler that never finishes hits the invocation cap with a HarnessError", async () => {
    await expect(
      runLikeInngest(
        async ({ step }: HarnessCtx) => {
          for (let i = 0; ; i++) await step.run(`s${i}`, async () => i);
        },
        { maxAttempts: 2, maxInvocations: 5 },
      ),
    ).rejects.toThrow(/did not finish within 5 invocations/);
  });

  it("row 6d: a step output that cannot cross JSON is a HarnessError, not a handler-visible error", async () => {
    let handlerCaught = false;
    await expect(
      runLikeInngest(
        async ({ step }: HarnessCtx) => {
          try {
            await step.run("big", async () => BigInt(1) as unknown as number);
          } catch {
            handlerCaught = true;
          }
          return null;
        },
        { maxAttempts: 2 },
      ),
    ).rejects.toBeInstanceOf(HarnessError);
    expect(handlerCaught).toBe(false);
  });

  it("must-PASS: first step fails once then succeeds, second step exhausts → exactly one StepError, for the second step", async () => {
    const memo: StepMemo = new Map();
    let aCalls = 0;
    await runLikeInngest(
      async ({ step }: HarnessCtx) => {
        const a = await step.run("a", async () => {
          aCalls++;
          if (aCalls === 1) throw new Error("transient");
          return { value: 42 };
        });
        try {
          await step.run("b", async () => {
            throw new ProbeCustomError();
          });
        } catch {
          // swallowed: the memo is what this row reads
        }
        return a;
      },
      { maxAttempts: 2, memo },
    );
    expect(aCalls).toBe(2);
    expect(memo.get("a")).toEqual({ ok: true, data: { value: 42 } });
    const failures = [...memo.entries()].filter(([, e]) => !e.ok);
    expect(failures.map(([id]) => id)).toEqual(["b"]);
    expect((failures[0][1] as { error: StepError }).error).toBeInstanceOf(StepError);
  });

  it("negative control: a naive inline step driver MISSES what the harness sees", async () => {
    // The shape the cron suites used before #8726: the callback runs inline, so
    // the raw error propagates in-process and closure assignments survive.
    const naiveStep = { run: <T,>(_id: string, cb: () => Promise<T>) => cb() };
    let caught: unknown;
    try {
      await naiveStep.run("setup", async () => {
        throw new ProbeCustomError();
      });
    } catch (err) {
      caught = err;
    }
    expect(caught).toBeInstanceOf(ProbeCustomError);

    let flag = false;
    await naiveStep.run("a", async () => {
      flag = true;
    });
    const seen = await naiveStep.run("b", async () => flag);
    expect(seen).toBe(true);
  });
});
