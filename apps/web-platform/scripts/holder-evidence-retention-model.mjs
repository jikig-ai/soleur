// Pure synthetic decision model. It does not schedule, open, delete, inspect,
// persist or communicate with any real resource. All supplied facts are claims.
const DAY_MS = 24 * 60 * 60 * 1000;
const result = (state) => ({ scope: 'synthetic_model_only', state, independent_deletion_proven: false });
const id = (value) => typeof value === 'string' && /^[a-z0-9][a-z0-9._-]{0,79}$/.test(value);
const millis = (value) => Number.isSafeInteger(value) && value >= 0;
const exactIds = (value) => Array.isArray(value) && value.length > 0 && value.length <= 16 && value.every(id) && new Set(value).size === value.length;
const sameIds = (left, right) => exactIds(left) && exactIds(right) && left.length === right.length && left.every((value) => right.includes(value));
const identityKeys = ['operation_id', 'vault_id', 'owner_id', 'generation'];
const bound = (expected, record) => record && record.identity && identityKeys.every((key) => id(expected?.[key]) && expected[key] === record.identity[key]);
const freshAdmission = (time, start) => millis(time) && time <= start && start - time <= 60000;

export function simulateRetention(input) {
  try {
    if (!input || typeof input !== 'object' || typeof input.capture_started !== 'boolean' ||
        typeof input.collector_interrupted !== 'boolean' || !millis(input.capture_start_ms) ||
        !millis(input.deadline_ms) || !millis(input.now_ms) || input.clock_verified !== true ||
        input.deadline_ms <= input.capture_start_ms || input.deadline_ms - input.capture_start_ms > DAY_MS ||
        input.now_ms < input.capture_start_ms) return result('unknown');

    const workers = input.workers;
    const workerShape = Array.isArray(workers) && workers.length === 2 && workers.every((worker) =>
      worker && id(worker.id) && id(worker.domain) && id(worker.job_id) && bound(input.expected, worker) &&
      freshAdmission(worker.read_back_at_ms, input.capture_start_ms) && millis(worker.scheduled_at_ms) &&
      worker.scheduled_at_ms >= input.capture_start_ms && worker.scheduled_at_ms < input.deadline_ms &&
      worker.registered === true && worker.read_back === true);
    const independentWorkers = workerShape && id(input.collector_domain) && id(input.vault_domain) &&
      new Set([input.collector_domain, input.vault_domain, ...workers.map((worker) => worker.domain)]).size === 4 &&
      workers[0].id !== workers[1].id && workers[0].job_id !== workers[1].job_id;
    const verifier = input.verification;
    const verifierReady = independentWorkers && verifier && id(verifier.verifier_id) && id(verifier.domain) &&
      verifier.independent === true && verifier.admission_control_read_healthy === true && bound(input.expected, verifier) &&
      freshAdmission(verifier.read_back_at_ms, input.capture_start_ms) &&
      ['scheduler', 'credential', 'network'].every((key) => [workers[0], workers[1], verifier].every((item) => id(item[key])) &&
        new Set([workers[0][key], workers[1][key], verifier[key]]).size === 3) &&
      millis(verifier.ready_at_ms) && verifier.ready_at_ms <= input.capture_start_ms &&
      !workers.some((worker) => worker.id === verifier.verifier_id || worker.domain === verifier.domain) &&
      verifier.domain !== input.collector_domain && verifier.domain !== input.vault_domain;
    const armed = verifierReady && millis(input.armed_at_ms) && input.armed_at_ms <= input.capture_start_ms &&
      workers.every((worker) => worker.read_back_at_ms <= input.armed_at_ms) &&
      verifier.read_back_at_ms <= input.armed_at_ms && verifier.ready_at_ms <= input.armed_at_ms &&
      input.ledger_persisted === true && input.no_untracked_copies === true && exactIds(input.expected_copies);
    if (!armed) return result(!input.capture_started ? 'refused' : input.now_ms >= input.deadline_ms ? 'late' : 'unknown');

    if (!input.expected || !input.observed || !identityKeys.every((key) => id(input.expected[key]) && input.expected[key] === input.observed[key])) {
      return result(input.capture_started && input.now_ms >= input.deadline_ms ? 'late' : 'unknown');
    }
    if (!input.capture_started) return result(input.now_ms < input.deadline_ms ? 'model_armed' : 'refused');

    const cleanup = input.cleanup;
    const verify = input.verification;
    const completeShape = cleanup && verify && millis(cleanup.attempted_at_ms) && millis(verify.verified_at_ms) &&
      cleanup.attempted_at_ms >= input.capture_start_ms && verify.verified_at_ms >= cleanup.attempted_at_ms && verify.verified_at_ms <= input.now_ms;
    if (!completeShape) return result(input.now_ms >= input.deadline_ms ? 'late' : 'unknown');
    if (verify.verified_at_ms >= input.deadline_ms) return result('late');
    if (!bound(input.expected, cleanup) || !workers.some((worker) => worker.id === cleanup.delete_worker_id &&
        worker.scheduled_at_ms <= cleanup.attempted_at_ms) ||
        !['ok', 'lost'].includes(cleanup.response) || cleanup.sealed !== true || cleanup.handles_closed !== true ||
        cleanup.copies_accounted !== true || cleanup.interrupted !== false ||
        !id(verify.verifier_id) || !id(verify.domain) || verify.independent !== true ||
        verify.verifier_id === cleanup.delete_worker_id || workers.some((worker) => worker.id === verify.verifier_id || worker.domain === verify.domain) ||
        verify.domain === input.collector_domain || verify.domain === input.vault_domain ||
        verify.control_read_healthy !== true || verify.absence_confirmed !== true || !sameIds(input.expected_copies, verify.checked_copies)) {
      return result(input.now_ms >= input.deadline_ms ? 'late' : 'unknown');
    }
    return result('model_verified');
  } catch { return result('unknown'); }
}
