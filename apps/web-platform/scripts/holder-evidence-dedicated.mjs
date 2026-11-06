// Offline lifecycle prototype. Adapters are injected; this module has no
// credentials, network client, executable entry point or persistence. A mock
// observer cannot prove ownership or that a real backend stopped.
const unknown = (operation = 'not_started', cancel = 'not_attempted', close = 'not_attempted') => ({
  operation, cancel, close, stop: 'unknown', evidence: 'adapter_report_only',
  ownership: 'unverified', writer_clearance: false,
});

async function bounded(action, deadline) {
  const remaining = Math.floor(deadline - performance.now());
  if (remaining < 1) return { state: 'timeout' };
  let timer;
  try {
    const task = Promise.resolve().then(() => {
      if (performance.now() >= deadline) return { state: 'timeout' };
      try {
        return Promise.resolve(action()).then(
          (value) => ({ state: 'completed', value }),
          () => ({ state: 'failed' }),
        );
      } catch { return { state: 'failed' }; }
    });
    const timeout = new Promise((resolve) => { timer = setTimeout(() => resolve({ state: 'timeout' }), remaining); });
    const result = await Promise.race([task, timeout]);
    return performance.now() >= deadline ? { state: 'timeout' } : result;
  } finally { clearTimeout(timer); }
}

function reportedStopped(value, phase) {
  return value !== null && typeof value === 'object' && value.status === 'stopped' &&
    value.phase === phase && value.scope === 'owned_operation';
}

export async function observeDedicatedLifecycle(adapter, limits) {
  if (!adapter || !limits || !['create', 'start', 'cancel', 'close', 'verify'].every((key) => typeof adapter[key] === 'function') ||
      !Number.isSafeInteger(limits.workMs) || limits.workMs < 1 || limits.workMs > 15000 ||
      !Number.isSafeInteger(limits.cleanupMs) || limits.cleanupMs < 1 || limits.cleanupMs > 15000) return unknown();
  let connection;
  try {
    connection = adapter.create();
    if (!connection || typeof connection !== 'object') return unknown();
    if (typeof connection.then === 'function') {
      // Async acquisition is unsupported; consume rejection without asserting
      // that a late-created resource was closed.
      Promise.resolve(connection).catch(() => {});
      return unknown();
    }
  } catch { return unknown(); }

  const controller = new AbortController();
  const workDeadline = performance.now() + limits.workMs;
  const task = Promise.resolve().then(() => {
    if (controller.signal.aborted || performance.now() >= workDeadline) throw new Error('deadline');
    return adapter.start(connection, controller.signal);
  }).then(() => ({ state: 'completed' }), () => ({ state: 'failed' }));
  const work = await bounded(() => task, workDeadline);
  const operation = work.state === 'completed' ? work.value.state : work.state;
  const cleanupDeadline = performance.now() + limits.cleanupMs;
  let cancel = 'not_attempted';

  if (operation === 'timeout') {
    controller.abort();
    const cancellation = await bounded(() => adapter.cancel(connection), cleanupDeadline);
    cancel = cancellation.state;
    // A pending cancellation may still target the held backend; do not release
    // it for reuse or claim success while that action is unresolved.
    if (cancel !== 'completed') return unknown(operation, cancel);
    const settled = await bounded(() => task, cleanupDeadline);
    if (settled.state !== 'completed') return unknown(operation, cancel);
  }

  const preclose = await bounded(() => adapter.verify(connection, 'preclose'), cleanupDeadline);
  if (preclose.state !== 'completed' || !reportedStopped(preclose.value, 'preclose')) return unknown(operation, cancel);
  const closed = await bounded(() => adapter.close(connection), cleanupDeadline);
  if (closed.state !== 'completed') return unknown(operation, cancel, closed.state);
  const postclose = await bounded(() => adapter.verify(connection, 'postclose'), cleanupDeadline);
  if (postclose.state !== 'completed' || !reportedStopped(postclose.value, 'postclose')) return unknown(operation, cancel, closed.state);
  return { ...unknown(operation, cancel, closed.state), stop: 'observer_reported_stopped' };
}
