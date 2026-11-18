// Offline observation helper only. An injected database and inspection are not
// authenticated, and transaction settlement does not prove backend shutdown,
// vault fencing, durable quarantine, or authority to collect or release.
// For asynchronous inspection, the start gate closes only when this helper
// observes the returned Promise; it is not an independently enforced fence.
import { types } from 'node:util';
const outcome = state => Object.freeze({ state, backend_stop: 'unknown', writer_clearance: false });
const STATES = new Set(['complete', 'partial', 'failed']);
const then = Promise.prototype.then;
const trackedDatabases = new WeakMap();
function projectInspection(value) {
  try {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return outcome('failed');
    const state = value.state;
    if (STATES.has(state)) return outcome(state);
    const roles = value.roles;
    const roleState = roles?.state;
    if (STATES.has(roleState)) {
      return Object.freeze({ roles: Object.freeze({ state: roleState }), backend_stop: 'unknown', writer_clearance: false });
    }
  } catch { /* Untrusted projections never emit errors or raw fields. */ }
  return outcome('failed');
}

export function trackInspectionTransaction(database, inspect) {
  let begin;
  try { begin = database?.begin; } catch { throw new Error('tracker_configuration'); }
  if (typeof begin !== 'function' || typeof inspect !== 'function') throw new Error('tracker_configuration');
  let started = false;
  let closed = false;
  let resolveSettlement;
  const settlement = new Promise(resolve => { resolveSettlement = resolve; });
  const tracked = Object.freeze({ begin(...args) {
    if (closed || started) throw new Error('transaction_unavailable');
    started = true;
    let raw;
    try { raw = Reflect.apply(begin, database, args); }
    catch { resolveSettlement(outcome('unknown')); throw new Error('transaction_unavailable'); }
    const transaction = new Promise((resolve, reject) => {
      try { then.call(raw, resolve, reject); }
      catch { resolveSettlement(outcome('unknown')); reject(new Error('transaction_unavailable')); }
    });
    then.call(transaction, () => resolveSettlement(outcome('fulfilled')), () => resolveSettlement(outcome('rejected')));
    return transaction;
  } });
  const closeInspection = () => {
    closed = true;
    if (!started) resolveSettlement(outcome('not_started'));
  };
  const inspection = new Promise(resolve => {
    queueMicrotask(() => {
      let value;
      try { value = inspect(tracked); }
      catch { closeInspection(); resolve(outcome('failed')); return; }
      if (!types.isPromise(value)) {
        closeInspection();
        resolve(projectInspection(value));
        return;
      }
      try {
        then.call(value,
          result => { closeInspection(); resolve(projectInspection(result)); },
          () => { closeInspection(); resolve(outcome('failed')); });
      } catch { closeInspection(); resolve(outcome('failed')); }
    });
  });
  const handle = Object.freeze({ inspection, settlement });
  trackedDatabases.set(handle, database);
  return handle;
}

export function isTrackedInspectionTransaction(value, database) {
  return value !== null && typeof value === 'object' && trackedDatabases.get(value) === database;
}
