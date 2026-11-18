// Ordered in-memory experiment only. No real mutex, persistence, identity,
// executor exclusivity, filesystem control, restoration or authorization.
// Barrier request closes the modeled queue; seal waits for the sole active
// mutation and its handles. Ordering is assumed, not provided by a real lock.
export function createDrainFixture({operation, generation, epoch}) {
  if (![operation, generation].every(v => typeof v === 'string' && /^[0-9a-f]{32}$/.test(v)) ||
      typeof epoch !== 'string' || !/^(0|[1-9][0-9]{0,19})$/.test(epoch) || BigInt(epoch) > 18446744073709551615n) throw Error('fixture_identity');
  const mutations = new Map();
  let state = 'open', command = null, seal = false, uncertain = false, inspecting = false;
  const unknown = () => ({state:'unknown'});
  const pending = () => ({state:'pending_unverified'});
  const validId = id => typeof id === 'string' && /^[a-z0-9]{1,32}$/.test(id);
  return Object.freeze({
    admit(id) {
      if (inspecting || state !== 'open' || !validId(id) || mutations.has(id) || mutations.size >= 128 ||
          [...mutations.values()].some(value => value !== 'complete')) return unknown();
      mutations.set(id, 'active');
      return {state:'admitted_unverified'};
    },
    beginBarrier(id) {
      if (inspecting || typeof id !== 'string' || !/^[0-9a-f]{32}$/.test(id) || state === 'restart' || (command !== null && command !== id)) return unknown();
      state = 'closed'; command = id;
      return pending();
    },
    confirmSeal(id) {
      if (inspecting || state !== 'closed' || id !== command || uncertain ||
          [...mutations.values()].some(value => value !== 'complete')) return unknown();
      seal = true;
      return pending();
    },
    complete(id, result) {
      if (inspecting || state === 'restart' || mutations.get(id) !== 'active') return unknown();
      let handlesClosed;
      inspecting = true;
      try {
        if (!result || typeof result !== 'object' || Array.isArray(result)) throw Error();
        const descriptors = Object.getOwnPropertyDescriptors(result);
        const keys = Reflect.ownKeys(descriptors);
        if (keys.length !== 2 || !keys.includes('synced') || !keys.includes('handlesClosed') ||
            !Object.hasOwn(descriptors.synced, 'value') || !Object.hasOwn(descriptors.handlesClosed, 'value') ||
            descriptors.synced.value !== true || typeof descriptors.handlesClosed.value !== 'boolean') throw Error();
        handlesClosed = descriptors.handlesClosed.value;
      } catch {
        mutations.set(id, 'uncertain'); uncertain = true;
        return unknown();
      } finally { inspecting = false; }
      mutations.set(id, handlesClosed ? 'complete' : 'handles');
      return handlesClosed ? {state:'completed_unverified'} : unknown();
    },
    closeHandles(id) {
      if (inspecting || state === 'restart' || mutations.get(id) !== 'handles') return unknown();
      mutations.set(id, 'complete');
      return {state:'completed_unverified'};
    },
    acknowledge(id) {
      if (inspecting || state !== 'closed' || id !== command || !seal || uncertain ||
          [...mutations.values()].some(value => value !== 'complete')) return unknown();
      return {state:'drained_unverified', operation, generation, epoch, barrier:command};
    },
    restart() { if (inspecting) return unknown(); state = 'restart'; seal = false; uncertain = true; return unknown(); },
  });
}
