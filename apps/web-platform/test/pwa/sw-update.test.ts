import { describe, test, expect, vi, beforeEach, afterEach } from "vitest";
import {
  watchForUpdate,
  postSkipWaiting,
  reloadOnControllerChange,
} from "@/lib/pwa/sw-update";

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
});

describe("postSkipWaiting", () => {
  test("posts the SKIP_WAITING message to the worker", () => {
    const worker = makeWorker();
    postSkipWaiting(worker as never);
    expect(worker.postMessage).toHaveBeenCalledWith({ type: "SKIP_WAITING" });
  });
});

describe("reloadOnControllerChange", () => {
  function makeContainer() {
    const listeners: Record<string, Array<() => void>> = {};
    return {
      addEventListener: (t: string, cb: () => void) => {
        (listeners[t] ??= []).push(cb);
      },
      removeEventListener: (t: string, cb: () => void) => {
        listeners[t] = (listeners[t] ?? []).filter((x) => x !== cb);
      },
      fire: (t: string) => (listeners[t] ?? []).forEach((cb) => cb()),
    };
  }

  test("reloads exactly once even if controllerchange fires multiple times", () => {
    const container = makeContainer();
    const reload = vi.fn();

    reloadOnControllerChange(container as never, reload);
    container.fire("controllerchange");
    container.fire("controllerchange");
    container.fire("controllerchange");

    expect(reload).toHaveBeenCalledTimes(1);
  });

  test("unsubscribe detaches the handler so no reload fires", () => {
    const container = makeContainer();
    const reload = vi.fn();

    const unsub = reloadOnControllerChange(container as never, reload);
    unsub();
    container.fire("controllerchange");

    expect(reload).not.toHaveBeenCalled();
  });
});
