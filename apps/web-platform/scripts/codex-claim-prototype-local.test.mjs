// Only the uniquely owned disposable PostgreSQL fixture may run this test.
import assert from 'node:assert/strict';
import postgres from '../node_modules/postgres/src/index.js';
import { createFixtureSocket } from './holder-evidence-test-docker-socket.mjs';

// Test-local only: the database transport is supplied by the disposable
// fixture below. Identities and commitments are synthetic caller assertions.
const valid = value => value && typeof value === 'object' &&
  ['run', 'turn', 'subject', 'workspace', 'conversation'].every(k =>
    typeof value[k] === 'string' && /^[a-z0-9-]{1,80}-synthetic$/.test(value[k])) &&
  Number.isSafeInteger(value.generation) && value.generation >= 0 &&
  Number.isSafeInteger(value.version) && value.version > 0 &&
  typeof value.commitment === 'string' && /^[a-f0-9]{64}$/.test(value.commitment);

async function installSyntheticClaims(db) {
  await db`CREATE TABLE public.synthetic_codex_claims (
    run_id text NOT NULL, turn_id text NOT NULL, subject_id text NOT NULL,
    workspace_id text NOT NULL, conversation_id text NOT NULL, generation bigint NOT NULL,
    commitment text NOT NULL, version integer NOT NULL,
    PRIMARY KEY (run_id, turn_id)
  )`;
}

async function claimSyntheticTurn(db, value) {
  if (!valid(value)) return 'unknown';
  const inserted = await db`INSERT INTO public.synthetic_codex_claims
    (run_id, turn_id, subject_id, workspace_id, conversation_id, generation, commitment, version)
    VALUES (${value.run}, ${value.turn}, ${value.subject}, ${value.workspace}, ${value.conversation},
      ${value.generation}, ${value.commitment}, ${value.version})
    ON CONFLICT (run_id, turn_id) DO NOTHING RETURNING run_id`;
  if (inserted.length === 1) return 'inserted_in_transaction';
  return await readSyntheticTurn(db, value) === 'accepted' ? 'existing_row' : 'unknown';
}

async function readSyntheticTurn(db, value) {
  if (!valid(value)) return 'unknown';
  const rows = await db`SELECT 1 FROM public.synthetic_codex_claims
    WHERE run_id = ${value.run} AND turn_id = ${value.turn} AND subject_id = ${value.subject}
      AND workspace_id = ${value.workspace} AND conversation_id = ${value.conversation}
      AND generation = ${value.generation} AND commitment = ${value.commitment} AND version = ${value.version}`;
  return rows.length === 1 ? 'accepted' : 'unknown';
}

assert.match(process.env.SYNTHETIC_DB ?? '', /^holder_evidence_test_[0-9]+$/);
assert.match(process.env.SYNTHETIC_PASSWORD ?? '', /^[a-f0-9]{48}$/);
const fixture = { id: process.env.SYNTHETIC_CONTAINER_ID, image: process.env.SYNTHETIC_CONTAINER_IMAGE,
  marker: process.env.SYNTHETIC_CONTAINER_MARKER, password: process.env.SYNTHETIC_PASSWORD };
const connect = () => postgres({ host: '127.0.0.1', port: 5432, socket: () => createFixtureSocket(fixture),
  database: process.env.SYNTHETIC_DB, username: 'postgres', password: process.env.SYNTHETIC_PASSWORD,
  max: 1, connect_timeout: 5 });
const first = connect(), second = connect(), restarted = connect();
const turn = { run: 'run-synthetic', turn: 'turn-synthetic', subject: 'subject-synthetic',
  workspace: 'workspace-synthetic', conversation: 'conversation-synthetic', generation: 1,
  commitment: 'a'.repeat(64), version: 1 };
try {
  await installSyntheticClaims(first);
  assert.equal(await readSyntheticTurn(first, turn), 'unknown');
  const pair = await Promise.all([claimSyntheticTurn(first, turn), claimSyntheticTurn(second, turn)]);
  assert.deepEqual(pair.sort(), ['existing_row', 'inserted_in_transaction']);
  assert.equal(await readSyntheticTurn(second, turn), 'accepted');
  for (const field of ['subject', 'workspace', 'conversation', 'commitment', 'generation', 'version']) {
    const replacement = typeof turn[field] === 'number' ? 2 : field === 'commitment' ? 'b'.repeat(64) : `other-${turn[field]}`;
    const changed = { ...turn, [field]: replacement };
    assert.equal(await claimSyntheticTurn(first, changed), 'unknown');
    assert.equal(await readSyntheticTurn(second, changed), 'unknown');
  }
  const competing = { ...turn, turn: 'competing-synthetic' };
  const collision = await Promise.all([claimSyntheticTurn(first, competing),
    claimSyntheticTurn(second, { ...competing, commitment: 'b'.repeat(64) })]);
  assert.deepEqual(collision.sort(), ['inserted_in_transaction', 'unknown']);
  const delayed = { ...turn, turn: 'delayed-synthetic' };
  let notifyInserted, release;
  const inserted = new Promise(resolve => { notifyInserted = resolve; });
  const hold = new Promise(resolve => { release = resolve; });
  const transaction = first.begin(async tx => {
    assert.equal(await claimSyntheticTurn(tx, delayed), 'inserted_in_transaction');
    notifyInserted();
    await hold;
  });
  try {
    await inserted;
    assert.equal(await readSyntheticTurn(second, delayed), 'unknown');
    const [{ pid }] = await second`SELECT pg_backend_pid() AS pid`;
    const competingClaim = claimSyntheticTurn(second, delayed);
    const deadline = Date.now() + 5000;
    let blocked = false;
    while (Date.now() < deadline) {
      const rows = await restarted`SELECT wait_event_type FROM pg_catalog.pg_stat_activity WHERE pid = ${pid}`;
      if (rows[0]?.wait_event_type === 'Lock') { blocked = true; break; }
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    assert.equal(blocked, true, 'competing insert did not reach a database lock wait');
    release();
    await transaction;
    assert.equal(await competingClaim, 'existing_row');
  } finally { release(); }
  const rolledBack = { ...turn, turn: 'rolled-back-synthetic' };
  let rollbackInserted, releaseRollback;
  const rollbackReady = new Promise(resolve => { rollbackInserted = resolve; });
  const rollbackGate = new Promise(resolve => { releaseRollback = resolve; });
  const rollback = first.begin(async tx => {
    assert.equal(await claimSyntheticTurn(tx, rolledBack), 'inserted_in_transaction');
    rollbackInserted();
    await rollbackGate;
    throw new Error('synthetic rollback');
  });
  const rollbackResult = assert.rejects(rollback, /synthetic rollback/);
  try {
    await rollbackReady;
    assert.equal(await readSyntheticTurn(second, rolledBack), 'unknown');
    const [{ pid }] = await second`SELECT pg_backend_pid() AS pid`;
    const waiter = claimSyntheticTurn(second, rolledBack);
    const deadline = Date.now() + 5000;
    let blocked = false;
    while (Date.now() < deadline) {
      const rows = await restarted`SELECT wait_event_type FROM pg_catalog.pg_stat_activity WHERE pid = ${pid}`;
      if (rows[0]?.wait_event_type === 'Lock') { blocked = true; break; }
      await new Promise(resolve => setTimeout(resolve, 10));
    }
    assert.equal(blocked, true, 'rollback competitor did not reach a database lock wait');
    releaseRollback();
    await rollbackResult;
    assert.equal(await waiter, 'inserted_in_transaction');
    assert.equal(await readSyntheticTurn(restarted, rolledBack), 'accepted');
  } finally { releaseRollback(); }
  const laterRead = { ...turn, turn: 'later-read-synthetic' };
  assert.equal(await claimSyntheticTurn(first, laterRead), 'inserted_in_transaction');
  await first.end({ timeout: 2 });
  assert.equal(await readSyntheticTurn(second, laterRead), 'accepted');
  assert.equal(await readSyntheticTurn(restarted, laterRead), 'accepted');
  assert.equal(await claimSyntheticTurn(restarted, laterRead), 'existing_row');
  console.log('synthetic claim prototype passed');
} finally {
  await first.end({ timeout: 2 });
  await second.end({ timeout: 2 });
  await restarted.end({ timeout: 2 });
}
