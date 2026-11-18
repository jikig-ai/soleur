import { test } from 'node:test';
import assert from 'node:assert/strict';
import { projectOrganizationMembers } from './holder-evidence-supabase-members.mjs';

const encode = (value) => new TextEncoder().encode(JSON.stringify(value));
const limits = { maxBytes: 8192, maxRows: 4 };
const id = '00000000-0000-4000-8000-000000000001';

test('projects only reviewed identity and role classes, leaving coverage unknown', () => {
  const result = projectOrganizationMembers(encode([{ user_id: id, role_name: 'Owner', email: 'private@example.com', user_name: 'private-name', api_key: 'private-key' }]), limits);
  assert.equal(result.state, 'partial');
  assert.deepEqual(result.members, [{ user_id: id, role: 'owner' }]);
  assert.equal(result.project_access, 'unknown');
  assert.equal(result.holder_coverage, 'unknown');
  assert.equal(result.writer_clearance, false);
  assert.doesNotMatch(JSON.stringify(result), /private/);
});

test('unrecognized roles stay unknown without persisting the input', () => {
  const result = projectOrganizationMembers(encode([{ user_id: id, role_name: 'private-role' }]), limits);
  assert.deepEqual(result.members, [{ user_id: id, role: 'unknown' }]);
  assert.doesNotMatch(JSON.stringify(result), /private-role/);
});

test('malformed, oversized and duplicate inputs fail without output', () => {
  const member = { user_id: id, role_name: 'Owner' };
  for (const input of [encode([member, member]), encode([{ ...member, user_id: 'private@example.com' }]),
    encode({ members: [member] }), new Uint8Array([0xff]), encode([member, member, member, member, member])]) {
    const result = projectOrganizationMembers(input, limits);
    assert.equal(result.state, 'failed');
    assert.deepEqual(result.members, []);
    assert.equal(result.writer_clearance, false);
  }
  assert.equal(projectOrganizationMembers(encode([member]), { ...limits, maxBytes: 1 }).state, 'failed');
  assert.equal(projectOrganizationMembers(encode([member]), { ...limits, maxRows: 0 }).state, 'failed');
});

test('actual byte length cannot be hidden by a shadow property', () => {
  const input = new TextEncoder().encode(' '.repeat(128) + '[]');
  Object.defineProperty(input, 'byteLength', { value: 1 });
  assert.equal(projectOrganizationMembers(input, { maxBytes: 8, maxRows: 1 }).state, 'failed');
});
