# ejections corroboration + queue oracle — live smoke (bounded: --commits 20, ~35 gh api reads)

command: python3 -I scripts/ci-pr-affected-replay.py ejections --out /var/tmp/s4-corrob-smoke --commits 20 --base origin/main
rc: 0

stdout:
replay ejections: wrote 8 units to /var/tmp/s4-corrob-smoke/units-ejections.jsonl (window 2026-11-08T09:45:18Z..2026-11-08T21:33:22Z, 29 merge_group runs, 7 failed)
replay ejections: conclusions {"failure": 7, "success": 22}
replay ejections: corroborated commits=20 merge_group_on_landed=20 missing=0 refused=0 read_failures=0
replay ejections: queue_oracle {"added": 24, "distinct_branches": 29, "prs": 21, "read_failures": 0, "removed": 23, "shortfall": 1} expected_units=8

ejections-window.json blocks:
{"corroborated":{"commits":20,"merge_group_on_landed":20,"missing_ids":[],"missing_refused":0,"read_failures":0},"queue_oracle":{"added":24,"distinct_branches":29,"prs":21,"read_failures":0,"removed":23,"shortfall":1},"expected_units":8}

per-unit sha / cls / reason / runs_via:
{"sha":"aea4fdd1a1a69ef6ba46df0bbc521c9e797b577f","cls":"not-evaluable","reason":"failed-job-without-fail-line","runs_via":null}
{"sha":"ad04b67151aa5e84458442a191d122d15a3fe482","cls":"not-evaluable","reason":"failed-job-without-fail-line","runs_via":null}
{"sha":"db4a4d3b5c0dde63c2c41811828a61d72536e136","cls":"not-evaluable","reason":"failed-job-without-fail-line","runs_via":null}
{"sha":"434cf710d0f663746e9c40ea19b72b5c9f3f63d7","cls":"not-evaluable","reason":"failed-job-without-fail-line","runs_via":null}
{"sha":"a13ade1b52c082ee5534fe79bbfaf02d6c0243b4","cls":"not-evaluable","reason":"failed-job-without-fail-line","runs_via":null}
{"sha":"1ef8a6d90e4d1ee1b2aba3d7e981f8498848e765","cls":"not-evaluable","reason":"failed-job-without-fail-line","runs_via":null}
{"sha":"f8102d6cffb13c5ddcec6756c2d9be92bb88e885","cls":"rule-irrelevant","reason":"","runs_via":null}
{"sha":"queue-oracle:pr-12410-1","cls":"not-evaluable","reason":"queue-oracle-shortfall: pr-12410 added=2 branches=1","runs_via":null}

command: python3 -I scripts/ci-pr-affected-replay.py aggregate /var/tmp/s4-corrob-smoke
rc: 0
  routes={}
population=commits+ejections n=8 classes={"not-evaluable": 7, "rule-irrelevant": 1}
  routes={"not-evaluable:failed-job-without-fail-line": 6, "not-evaluable:queue-oracle-shortfall: pr-12410 added=2 branches=1": 1, "rule-irrelevant:-": 1}

note: the window found zero index-dropped runs (merge_group_on_landed=20 == listing membership here) and ONE real queue-oracle shortfall — pr-12410 added twice to the queue but only one distinct gh-readonly-queue head_branch was observed in-window. Both are now counted units instead of an uncounted population hole.
