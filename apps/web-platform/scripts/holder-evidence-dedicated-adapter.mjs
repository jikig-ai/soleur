import { observeDedicatedLifecycle } from './holder-evidence-dedicated.mjs';
import { trackInspectionTransaction } from './holder-evidence-transaction-tracker.mjs';

// A closed, in-memory simulation only. It has no injected transport, database
// driver, credentials, PID or executable entry point. Its atomic ownership
// check is a property of this model, not a PostgreSQL capability or proof.
const SCENARIOS = new Set(['complete', 'cancel', 'reuse_before_cancel', 'reuse_generation_only', 'reuse_owner_only', 'shared', 'ambiguous',
  'observer_missing', 'observer_shared', 'preclose_unknown', 'postclose_unknown']);

export function createSyntheticDedicatedAdapter(scenario) {
  if (!SCENARIOS.has(scenario)) throw new Error('synthetic_scenario');
  let finishTransaction;
  const connection = Object.freeze({ begin: () => new Promise((resolve) => { finishTransaction = resolve; }) });
  const observer = scenario === 'observer_shared' ? connection : Object.freeze({});
  const expectedGeneration = 1;
  let current = { owner: connection, generation: expectedGeneration, state: 'ready' };
  let issued = false;
  let started = false;
  let precloseVerified = false;
  let inspect;
  let starts = 0;
  let cancellationAttempts = 0;
  let cancellations = 0;
  let closes = 0;

  const ownsHeldRecord = (candidate) => candidate === connection && current !== null &&
    current.owner === connection && current.generation === expectedGeneration;
  const observerIndependent = () => observer !== connection && scenario !== 'observer_missing';
  const refuse = () => { throw new Error('synthetic_unknown'); };

  const adapter = {
    create() {
      if (issued || scenario === 'shared' || scenario === 'ambiguous') refuse();
      issued = true;
      return connection;
    },
    start(candidate, signal) {
      if (signal.aborted || started || !observerIndependent() || !ownsHeldRecord(candidate) || current.state !== 'ready') refuse();
      started = true;
      starts++;
      const operation = trackInspectionTransaction(candidate, (db) => {
        db.begin('read only', () => undefined);
        return new Promise((resolve) => { inspect = resolve; });
      });
      if (scenario === 'cancel' || scenario.startsWith('reuse_')) {
        current.state = 'running';
        return operation;
      }
      current.state = 'stopped';
      queueMicrotask(() => {
        inspect({ state: 'complete' });
        finishTransaction();
      });
      return operation;
    },
    async cancel(candidate) {
      cancellationAttempts++;
      if (scenario === 'reuse_before_cancel') current = { owner: Object.freeze({}), generation: 2, state: 'running' };
      if (scenario === 'reuse_generation_only') current = { owner: connection, generation: 2, state: 'running' };
      if (scenario === 'reuse_owner_only') current = { owner: Object.freeze({}), generation: expectedGeneration, state: 'running' };
      // Synthetic registry performs comparison and cancellation as one atomic
      // in-process operation. A pre-cancel observation alone cannot ensure this.
      if (!observerIndependent() || !ownsHeldRecord(candidate) || current.state !== 'running' || !finishTransaction) refuse();
      cancellations++;
      current.state = 'stopped';
      inspect({ state: 'failed' });
      finishTransaction();
    },
    async verify(candidate, phase) {
      if (!observerIndependent() || candidate !== connection) refuse();
      if (phase === 'preclose') {
        if (scenario === 'preclose_unknown' || !ownsHeldRecord(candidate) || current.state !== 'stopped') refuse();
        precloseVerified = true;
      } else if (phase === 'postclose') {
        if (!precloseVerified || current !== null || scenario === 'postclose_unknown') refuse();
      } else refuse();
      return { status: 'stopped', phase, scope: 'owned_operation' };
    },
    async close(candidate) {
      if (!precloseVerified || !ownsHeldRecord(candidate) || current.state !== 'stopped') refuse();
      closes++;
      current = null;
    },
  };

  return {
    async run(limits) {
      const simulated = await observeDedicatedLifecycle(adapter, limits);
      // A mock observation can never establish real backend state or ownership.
      return { ...simulated, model_stop: simulated.stop, stop: 'unknown', evidence: 'synthetic_only', ownership: 'unverified' };
    },
    stats: () => ({ starts, cancellation_attempts: cancellationAttempts, cancellations, closes }),
  };
}
