import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import {
  watchForUpdate,
  postSkipWaiting,
  reloadOnControllerChange,
  watchUpdateAcceptance,
  UPDATE_ACCEPT_TIMEOUT_MS,
} from "@/lib/pwa/sw-update";

const reportSilentFallback = vi.hoisted(() => vi.fn());
vi.mock("@/lib/client-observability", async (importOriginal) => ({
  ...(await importOriginal<Record<string, unknown>>()),
  reportSilentFallback,
}));

// Minimal EventTarget-shaped mock with a settable state, matching the bits of
// ServiceWorker / ServiceWorkerRegistration the helpers touch.
function makeWorker(state = "installed") {
  const listeners: Record<string, Array<() => void>> = {};
  return {
    state,
    postMessage: vi.fn(),
    addEventListener: (type: string, cb: () => void) => {
      (listeners[type] ??= []).push(cb);
    },
    removeEventListener: (type: string, cb: () => void) => {
      listeners[type] = (listeners[type] ?? []).filter((x) => x !== cb);
    },
    fire: (type: string) => (listeners[type] ?? []).forEach((cb) => cb()),
    setState(next: string) {
      this.state = next;
    },
  };
}

function makeRegistration() {
  const listeners: Record<string, Array<() => void>> = {};
  return {
    waiting: null as ReturnType<typeof makeWorker> | null,
    installing: null as ReturnType<typeof makeWorker> | null,
    addEventListener: (type: string, cb: () => void) => {
      (listeners[type] ??= []).push(cb);
    },
    removeEventListener: (type: string, cb: () => void) => {
      listeners[type] = (listeners[type] ?? []).filter((x) => x !== cb);
    },
    fire: (type: string) => (listeners[type] ?? []).forEach((cb) => cb()),
  };
}

const originalNavigator = globalThis.navigator;

beforeEach(() => {
  Object.defineProperty(globalThis, "navigator", {
    value: { serviceWorker: { controller: {} } },
    configurable: true,
    writable: true,
  });
});

afterEach(() => {
  Object.defineProperty(globalThis, "navigator", {
    value: originalNavigator,
    configurable: true,
    writable: true,
  });
  vi.restoreAllMocks();
});

describe("watchForUpdate", () => {
  test("fires immediately when a worker is already waiting AND a controller exists", () => {
    const reg = makeRegistration();
    const waiting = makeWorker();
    reg.waiting = waiting as never;
    const onUpdate = vi.fn();

    watchForUpdate(reg as never, onUpdate);

    expect(onUpdate).toHaveBeenCalledTimes(1);
    expect(onUpdate).toHaveBeenCalledWith(waiting);
  });

  test("does NOT fire on a first install (no existing controller)", () => {
    // First install: the page is not yet controlled.
    (globalThis.navigator as { serviceWorker: { controller: unknown } }).serviceWorker.controller = null;
    const reg = makeRegistration();
    reg.waiting = makeWorker() as never;
    const onUpdate = vi.fn();

    watchForUpdate(reg as never, onUpdate);

    expect(onUpdate).not.toHaveBeenCalled();
  });

  test("fires on updatefound → installing reaches 'installed' with a controller present", () => {
    const reg = makeRegistration();
    const installing = makeWorker("installing");
    reg.installing = installing as never;
    const onUpdate = vi.fn();

    watchForUpdate(reg as never, onUpdate);
    // No waiting worker yet → not called on entry.
    expect(onUpdate).not.toHaveBeenCalled();

    reg.fire("updatefound");
    installing.setState("installed");
    reg.waiting = installing as never;
    installing.fire("statechange");

    expect(onUpdate).toHaveBeenCalledTimes(1);
  });

  test("unsubscribe removes the updatefound listener", () => {
    const reg = makeRegistration();
    reg.installing = makeWorker("installing") as never;
    const onUpdate = vi.fn();

    const unsub = watchForUpdate(reg as never, onUpdate);
    unsub();
    reg.fire("updatefound"); // no listener now → no statechange wiring

    expect(onUpdate).not.toHaveBeenCalled();
  });

  test("unsubscribe also detaches the statechange listener on the installing worker", () => {
    const reg = makeRegistration();
    const installing = makeWorker("installing");
    reg.installing = installing as never;
    const onUpdate = vi.fn();

    const unsub = watchForUpdate(reg as never, onUpdate);
    reg.fire("updatefound"); // wires the statechange listener
    unsub(); // must detach it
    installing.setState("installed");
    reg.waiting = installing as never;
    installing.fire("statechange"); // should be a no-op now

    expect(onUpdate).not.toHaveBeenCalled();
  });
});

describe("postSkipWaiting", () => {
  test("posts the SKIP_WAITING message to the worker", () => {
    const worker = makeWorker();
    postSkipWaiting(worker as never);
    expect(worker.postMessage).toHaveBeenCalledWith({ type: "SKIP_WAITING" });
  });
});

describe("reloadOnControllerChange", () => {
  function makeContainer(controller: unknown = {}) {
    const listeners: Record<string, Array<() => void>> = {};
    return {
      controller,
      addEventListener: (t: string, cb: () => void) => {
        (listeners[t] ??= []).push(cb);
      },
      removeEventListener: (t: string, cb: () => void) => {
        listeners[t] = (listeners[t] ?? []).filter((x) => x !== cb);
      },
      fire: (t: string) => (listeners[t] ?? []).forEach((cb) => cb()),
    };
  }

  test("reloads exactly once on an UPDATE (a controller already existed) even if controllerchange fires multiple times", () => {
    const container = makeContainer({}); // a controller was present → genuine update
    const reload = vi.fn();

    reloadOnControllerChange(container as never, reload);
    container.fire("controllerchange");
    container.fire("controllerchange");
    container.fire("controllerchange");

    expect(reload).toHaveBeenCalledTimes(1);
  });

  test("does NOT reload on a FIRST visit (no controller at start; the initial clients.claim() must not trigger a reload)", () => {
    const container = makeContainer(null); // uncontrolled first visit
    const reload = vi.fn();

    reloadOnControllerChange(container as never, reload);
    container.fire("controllerchange"); // this is the initial claim, not an update

    expect(reload).not.toHaveBeenCalled();
  });

  test("unsubscribe detaches the handler so no reload fires", () => {
    const container = makeContainer({});
    const reload = vi.fn();

    const unsub = reloadOnControllerChange(container as never, reload);
    unsub();
    container.fire("controllerchange");

    expect(reload).not.toHaveBeenCalled();
  });
});

describe("watchUpdateAcceptance (#7084 — the update path was previously unobservable)", () => {
  function makeContainer(controller: unknown = {}) {
    const listeners: Record<string, Array<() => void>> = {};
    return {
      controller,
      addEventListener: (t: string, cb: () => void) => {
        (listeners[t] ??= []).push(cb);
      },
      removeEventListener: (t: string, cb: () => void) => {
        listeners[t] = (listeners[t] ?? []).filter((x) => x !== cb);
      },
      fire: (t: string) => (listeners[t] ?? []).forEach((cb) => cb()),
      listenerCount: (t: string) => (listeners[t] ?? []).length,
    };
  }

  // Controllable fake timer, so both arms are driven deterministically rather than by
  // a real clock. Firing is explicit: nothing happens unless the test says so.
  function makeTimer() {
    let pending: (() => void) | null = null;
    let cleared = false;
    return {
      set: (fn: () => void) => {
        pending = fn;
        return 1;
      },
      clear: () => {
        cleared = true;
        pending = null;
      },
      fire: () => pending?.(),
      get cleared() {
        return cleared;
      },
      get armed() {
        return pending !== null;
      },
    };
  }

  beforeEach(() => reportSilentFallback.mockClear());

  test("reports to Sentry when an accepted update produces no controllerchange in the window", () => {
    const container = makeContainer({});
    const timer = makeTimer();
    watchUpdateAcceptance(container as never, UPDATE_ACCEPT_TIMEOUT_MS, timer.set, timer.clear);

    expect(reportSilentFallback).not.toHaveBeenCalled(); // not yet — nothing has timed out
    timer.fire();

    expect(reportSilentFallback).toHaveBeenCalledTimes(1);
    const [err, opts] = reportSilentFallback.mock.calls[0];
    expect(err).toBeInstanceOf(Error);
    expect(opts.feature).toBe("pwa-update");
    expect(opts.op).toBe("accept-timeout");
    expect(opts.extra.timeoutMs).toBe(UPDATE_ACCEPT_TIMEOUT_MS);
  });

  // The must-PASS arm. Without it, a watchdog that reported unconditionally would pass
  // the test above and page the operator on every successful update.
  test("stays SILENT when the update lands", () => {
    const container = makeContainer({});
    const timer = makeTimer();
    watchUpdateAcceptance(container as never, UPDATE_ACCEPT_TIMEOUT_MS, timer.set, timer.clear);

    container.fire("controllerchange");

    expect(reportSilentFallback).not.toHaveBeenCalled();
    expect(timer.cleared).toBe(true);
    expect(container.listenerCount("controllerchange")).toBe(0);
  });

  test("a late timer fire after success cannot resurrect the report", () => {
    const container = makeContainer({});
    const timer = makeTimer();
    watchUpdateAcceptance(container as never, UPDATE_ACCEPT_TIMEOUT_MS, timer.set, timer.clear);

    container.fire("controllerchange");
    timer.fire(); // a browser that fires a cleared timer anyway

    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  test("unsubscribing cancels the watchdog (unmount before either outcome)", () => {
    const container = makeContainer({});
    const timer = makeTimer();
    const stop = watchUpdateAcceptance(container as never, UPDATE_ACCEPT_TIMEOUT_MS, timer.set, timer.clear);

    stop();
    timer.fire();

    expect(reportSilentFallback).not.toHaveBeenCalled();
    expect(container.listenerCount("controllerchange")).toBe(0);
  });
});
