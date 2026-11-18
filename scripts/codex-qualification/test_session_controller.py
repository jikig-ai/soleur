"""Injected race observations only: no operational adapter or real sessions."""
import ast
from dataclasses import replace
from pathlib import Path
import unittest
from unittest.mock import patch

from prepare import Refused, sha
from session_controller import RaceController, SessionIdentity, bind_scenarios

SOURCE = 'd' * 40
NAMES = ('40_race_holder.sql', '41_race_waiter.sql',
         '42_race_observe.sql', '43_race_assert.sql')


class FakeClock:
    def __init__(self):
        self.now = 100.0

    def __call__(self):
        return self.now


class SessionControllerTests(unittest.TestCase):
    def setUp(self):
        self.clock = FakeClock()
        self.bodies = {name: (Path(__file__).parent / 'scenarios' / name).read_bytes()
                       for name in NAMES}
        self.hashes = {name: sha(body) for name, body in self.bodies.items()}
        self.binding = bind_scenarios(SOURCE, self.bodies, SOURCE, self.hashes)
        self.c = RaceController('synthetic-attempt', 'synthetic-db', self.binding, self.clock)
        self.holder = SessionIdentity('synthetic-attempt', 'synthetic-db', 101,
                                      'backend-birth-1', 201, 'process-birth-1', 'session-1')
        self.waiter = SessionIdentity('synthetic-attempt', 'synthetic-db', 102,
                                      'backend-birth-2', 202, 'process-birth-2', 'session-2')

    def register(self):
        self.c.register_holder(self.holder, self.hashes[NAMES[0]])
        self.c.register_waiter(self.waiter, self.hashes[NAMES[1]])

    def observe(self, **changes):
        data = dict(holder=self.holder, waiter=self.waiter, blockers=(self.holder,),
                    holder_state='idle in transaction', waiter_event_type='Lock',
                    observer_exit_code=0, scenario_sha256=self.hashes[NAMES[2]])
        data.update(changes)
        return self.c.observe_blocking(**data)

    def committed(self):
        self.register()
        self.observe()
        self.c.commit_recipe()
        self.c.observe_holder_commit(self.holder, 'COMMIT', 0)

    def assert_disabled(self):
        self.assertFalse(self.c.commit_permitted)
        self.assertFalse(self.c.succeeded)
        with self.assertRaises(Refused):
            self.c.commit_recipe()

    def test_positive_control_requires_explicit_commit_and_zero_waiter_then_assertion(self):
        self.register()
        self.assertFalse(self.c.commit_permitted)
        self.assertTrue(self.observe())
        self.assertTrue(self.c.commit_permitted)
        recipe = self.c.commit_recipe()
        self.assertEqual(recipe['session'], self.holder)
        self.assertEqual(recipe['sql'], 'COMMIT;')
        self.assertFalse(recipe['reopen_stdin'])
        self.assertFalse(recipe['execute_available'])
        self.assertFalse(self.c.commit_permitted)
        self.assertFalse(self.c.succeeded)
        self.c.observe_holder_commit(self.holder, 'COMMIT', 0)
        self.c.observe_waiter_exit(self.waiter, 0)
        self.assertFalse(self.c.succeeded)
        self.c.observe_assertion(self.hashes[NAMES[3]], 0)
        self.assertTrue(self.c.succeeded)
        self.assertEqual(self.c.snapshot()['runtime_evidence'], 'pending-injected-observations-only')
        self.assertEqual(set(self.c.snapshot()['operations'].values()), {0})

    def test_order_violations_are_terminal(self):
        for event in ('waiter-first', 'blocking-first', 'commit-first', 'commit-observation-first',
                      'waiter-exit-first', 'assertion-first'):
            with self.subTest(event=event):
                self.setUp()
                actions = {
                    'waiter-first': lambda: self.c.register_waiter(self.waiter, self.hashes[NAMES[1]]),
                    'blocking-first': self.observe,
                    'commit-first': self.c.commit_recipe,
                    'commit-observation-first': lambda: self.c.observe_holder_commit(self.holder, 'COMMIT', 0),
                    'waiter-exit-first': lambda: self.c.observe_waiter_exit(self.waiter, 0),
                    'assertion-first': lambda: self.c.observe_assertion(self.hashes[NAMES[3]], 0),
                }
                with self.assertRaises(Refused):
                    actions[event]()
                self.assert_disabled()

    def test_no_dependency_is_pending_not_success_until_deadline(self):
        self.register()
        self.assertFalse(self.observe(blockers=(), observer_exit_code=1))
        self.assertFalse(self.c.commit_permitted)
        self.clock.now += 30
        with self.assertRaisesRegex(Refused, 'deadline'):
            self.c.check_deadline()
        self.assert_disabled()

    def test_wrong_or_multiple_blocker_cannot_release_holder(self):
        for blockers in ((self.waiter,), (self.holder, self.waiter)):
            with self.subTest(blockers=blockers):
                self.setUp()
                self.register()
                with self.assertRaises(Refused):
                    self.observe(blockers=blockers)
                self.assert_disabled()

    def test_application_name_is_not_accepted_as_identity(self):
        with self.assertRaises(Refused):
            self.c.register_holder({'application_name': 'codex9051-rehearsal-holder'}, self.hashes[NAMES[0]])
        self.assertEqual(self.c.cleanup_recipes(), ())

    def test_foreign_attempt_database_missing_birth_and_pid_reuse_are_refused(self):
        changes = ({'attempt': 'foreign'}, {'database': 'foreign'}, {'backend_birth': ''},
                   {'process_birth': ''}, {'session_id': ''}, {'backend_pid': True})
        for change in changes:
            with self.subTest(change=change):
                self.setUp()
                with self.assertRaises(Refused):
                    self.c.register_holder(replace(self.holder, **change), self.hashes[NAMES[0]])
                self.assertEqual(self.c.cleanup_recipes(), ())
        for change in ({'backend_birth': 'reused-pid'}, {'process_birth': 'reused-pid'},
                       {'session_id': 'foreign-session'}, {'database': 'foreign'}):
            with self.subTest(observation=change):
                self.setUp()
                self.register()
                changed = replace(self.holder, **change)
                with self.assertRaises(Refused):
                    self.observe(holder=changed, blockers=(changed,))
                self.assert_disabled()

    def test_waiter_must_be_a_distinct_backend_and_process(self):
        for change in ({'backend_pid': self.holder.backend_pid},
                       {'process_pid': self.holder.process_pid}, {'session_id': self.holder.session_id}):
            with self.subTest(change=change):
                self.setUp()
                self.c.register_holder(self.holder, self.hashes[NAMES[0]])
                with self.assertRaises(Refused):
                    self.c.register_waiter(replace(self.waiter, **change), self.hashes[NAMES[1]])
                self.assertEqual(len(self.c.cleanup_recipes()), 1)

    def test_exact_lock_states_and_observer_zero_are_required(self):
        for change in ({'holder_state': 'active'}, {'waiter_event_type': 'IO'},
                       {'observer_exit_code': 1}, {'observer_exit_code': False}):
            with self.subTest(change=change):
                self.setUp()
                self.register()
                with self.assertRaises(Refused):
                    self.observe(**change)
                self.assert_disabled()

    def test_commit_recipe_cannot_be_repeated_or_followed_by_early_waiter_exit(self):
        self.register()
        self.observe()
        self.c.commit_recipe()
        with self.assertRaises(Refused):
            self.c.observe_waiter_exit(self.waiter, 0)
        self.assert_disabled()

    def test_commit_observation_must_be_exact_holder_success_and_commit_tag(self):
        for identity, tag, code in ((replace(self.holder, backend_birth='reuse'), 'COMMIT', 0),
                                    (self.holder, 'ROLLBACK', 0), (self.holder, 'COMMIT', 1)):
            with self.subTest(tag=tag, code=code):
                self.setUp()
                self.register()
                self.observe()
                self.c.commit_recipe()
                with self.assertRaises(Refused):
                    self.c.observe_holder_commit(identity, tag, code)
                self.assert_disabled()

    def test_waiter_failure_or_wrong_identity_disables_assertion(self):
        for identity, code in ((self.waiter, 1), (replace(self.waiter, process_birth='reuse'), 0)):
            with self.subTest(code=code):
                self.setUp()
                self.committed()
                with self.assertRaises(Refused):
                    self.c.observe_waiter_exit(identity, code)
                with self.assertRaises(Refused):
                    self.c.observe_assertion(self.hashes[NAMES[3]], 0)
                self.assert_disabled()

    def test_failed_assertion_is_not_success(self):
        self.committed()
        self.c.observe_waiter_exit(self.waiter, 0)
        with self.assertRaises(Refused):
            self.c.observe_assertion(self.hashes[NAMES[3]], 1)
        self.assert_disabled()

    def test_eof_triggers_owned_rollback_close_without_reopening_stdin(self):
        self.register()
        with self.assertRaisesRegex(Refused, 'EOF'):
            self.c.observe_eof(self.holder)
        recipes = self.c.cleanup_recipes()
        self.assertEqual({r['session'] for r in recipes}, {self.holder, self.waiter})
        for recipe in recipes:
            self.assertEqual(recipe['actions'], ('ROLLBACK;', 'close-existing-session'))
            self.assertFalse(recipe['reopen_stdin'])
            self.assertFalse(recipe['execute_available'])
        self.assert_disabled()

    def test_cleanup_preserves_primary_failure_and_never_restores_commit(self):
        self.register()
        with self.assertRaisesRegex(Refused, 'EOF'):
            self.c.observe_eof(self.waiter)
        original = self.c.primary_failure
        with self.assertRaises(Refused):
            self.c.observe_closed(replace(self.waiter, backend_birth='foreign'))
        self.assertEqual(self.c.primary_failure, original)
        self.c.observe_closed(self.waiter)
        self.c.observe_closed(self.holder)
        self.assertEqual(self.c.snapshot()['cleanup_status'], 'complete')
        self.assertEqual(self.c.primary_failure, original)
        self.assert_disabled()

    def test_cleanup_deadline_is_exactly_300_seconds_and_preserves_primary_failure(self):
        self.register()
        with self.assertRaises(Refused):
            self.c.observe_eof(self.waiter)
        original = self.c.primary_failure
        self.clock.now += 299
        self.assertEqual(self.c.snapshot()['cleanup_status'], 'pending')
        self.clock.now += 1
        self.assertEqual(self.c.snapshot()['cleanup_status'], 'expired')
        self.assertEqual(self.c.cleanup_recipes(), ())
        self.assertEqual(self.c.primary_failure, original)
        with self.assertRaises(Refused):
            self.c.observe_closed(self.holder)
        self.assert_disabled()

    def test_cleanup_expiration_cannot_be_reopened_by_a_regressing_clock(self):
        self.register()
        with self.assertRaises(Refused):
            self.c.observe_eof(self.waiter)
        self.clock.now += 300
        self.assertEqual(self.c.snapshot()['cleanup_status'], 'expired')
        self.clock.now -= 100
        self.assertEqual(self.c.snapshot()['cleanup_status'], 'expired')
        self.assertEqual(self.c.cleanup_recipes(), ())
        with self.assertRaises(Refused):
            self.c.observe_closed(self.holder)

    def test_pending_samples_have_a_fixed_observation_budget(self):
        self.register()
        with self.assertRaisesRegex(Refused, 'budget'):
            for _ in range(300):
                self.observe(blockers=(), observer_exit_code=1)
        self.assert_disabled()

    def test_repeat_commit_recipe_is_terminal(self):
        self.register()
        self.observe()
        self.c.commit_recipe()
        with self.assertRaises(Refused):
            self.c.commit_recipe()
        self.assert_disabled()

    def test_deadline_removes_permission_even_after_observed_blocking(self):
        self.register()
        self.observe()
        self.clock.now += 30
        self.assertFalse(self.c.commit_permitted)
        self.assert_disabled()

    def test_clock_backwards_and_nonfinite_are_terminal(self):
        for instant in (99, float('nan'), float('inf'), 10 ** 400):
            with self.subTest(instant=instant):
                self.setUp()
                self.register()
                self.clock.now = instant
                with self.assertRaises(Refused):
                    self.c.check_deadline()
                self.assertFalse(self.c.succeeded)

    def test_failed_clock_and_metadata_separators_cannot_leave_commit_enabled(self):
        self.register()
        self.observe()
        def broken_clock():
            raise ValueError('synthetic clock fault')
        self.c._clock = broken_clock
        self.assertFalse(self.c.commit_permitted)
        self.assertFalse(self.c.succeeded)
        self.assertEqual(self.c.cleanup_recipes(), ())
        for invalid in ('bad\u2028metadata', 'bad\u2029metadata'):
            with self.subTest(metadata=invalid):
                self.setUp()
                with self.assertRaises(Refused):
                    self.c.register_holder(replace(self.holder, backend_birth=invalid), self.hashes[NAMES[0]])
                self.assert_disabled()

    def test_each_phase_checks_source_bound_scenario_hash(self):
        for phase in range(4):
            with self.subTest(phase=phase):
                self.setUp()
                with self.assertRaises(Refused):
                    if phase == 0:
                        self.c.register_holder(self.holder, '0' * 64)
                    elif phase == 1:
                        self.c.register_holder(self.holder, self.hashes[NAMES[0]])
                        self.c.register_waiter(self.waiter, '0' * 64)
                    elif phase == 2:
                        self.register()
                        self.observe(scenario_sha256='0' * 64)
                    else:
                        self.committed()
                        self.c.observe_waiter_exit(self.waiter, 0)
                        self.c.observe_assertion('0' * 64, 0)
                self.assert_disabled()

    def test_source_recipe_binding_refuses_changed_bytes_source_or_hash_census(self):
        mutations = ((SOURCE, dict(self.bodies, **{NAMES[0]: b'changed'}), self.hashes),
                     ('e' * 40, self.bodies, self.hashes),
                     (SOURCE, self.bodies, {name: value for name, value in self.hashes.items() if name != NAMES[2]}))
        for source, bodies, hashes in mutations:
            with self.subTest(source=source):
                with self.assertRaises(Refused):
                    bind_scenarios(source, bodies, SOURCE, hashes)
        self.bodies[NAMES[0]] = b'mutated after binding'
        self.hashes[NAMES[0]] = '0' * 64
        self.assertNotEqual(self.binding.scenario_hash(NAMES[0]), '0' * 64)

    def test_no_operational_imports_or_execution_entrypoint(self):
        tree = ast.parse((Path(__file__).parent / 'session_controller.py').read_text())
        imports = {node.module for node in ast.walk(tree) if isinstance(node, ast.ImportFrom)}
        imports.update(alias.name for node in ast.walk(tree) if isinstance(node, ast.Import)
                       for alias in node.names)
        self.assertLessEqual(imports, {'dataclasses', 'math', 're', 'prepare'})
        self.assertNotIn('main', {node.name for node in ast.walk(tree)
                                  if isinstance(node, ast.FunctionDef)})

    def test_guard_removal_discriminators(self):
        source = (Path(__file__).parent / 'session_controller.py').read_text()
        guards = {
            'Race observation order differs': 'test_order_violations_are_terminal',
            'Exact sole holder/waiter blocking dependency absent': 'test_wrong_or_multiple_blocker_cannot_release_holder',
            'Foreign or reused PID session refused': 'test_foreign_attempt_database_missing_birth_and_pid_reuse_are_refused',
            'Race deadline expired': 'test_deadline_removes_permission_even_after_observed_blocking',
            'Owned waiter zero exit required': 'test_waiter_failure_or_wrong_identity_disables_assertion',
            'Explicit holder COMMIT success required': 'test_commit_observation_must_be_exact_holder_success_and_commit_tag',
        }
        for message, test_name in guards.items():
            with self.subTest(guard=message):
                tree = ast.parse(source)
                matches = [node for node in ast.walk(tree) if isinstance(node, ast.Call) and
                           isinstance(node.func, ast.Attribute) and node.func.attr == '_check' and
                           len(node.args) == 2 and isinstance(node.args[1], ast.Constant) and
                           node.args[1].value == message]
                self.assertEqual(len(matches), 1)
                matches[0].args[0] = ast.Constant(value=True)
                namespace = {'__name__': 'session_controller'}
                exec(compile(ast.fix_missing_locations(tree), '<offline-guard-mutant>', 'exec'), namespace)
                # Retain canonical dataclass types so only the selected guard
                # changes, not identity/binding type admission.
                namespace['SessionIdentity'] = SessionIdentity
                namespace['ScenarioBinding'] = type(self.binding)
                result = unittest.TestResult()
                with patch(__name__ + '.RaceController', namespace['RaceController']):
                    SessionControllerTests(test_name).run(result)
                self.assertTrue(result.failures, 'Guard deletion did not fail its behavioral test')


if __name__ == '__main__':
    unittest.main()
