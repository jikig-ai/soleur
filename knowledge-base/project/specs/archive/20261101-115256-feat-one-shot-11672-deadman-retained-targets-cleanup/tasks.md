# Tasks: remove retained dead-man destroy targets (#11672 row 1)

- [x] 1.1 Remove the four `-target` lines from `apply-web-platform-infra.yml`
- [x] 1.2 Remove the four `INTENDED_DESTROYS` rows from the census
- [x] 2.1 Flip `logs-alert-query-period-ceiling.test.sh` (checks and rows M5, M5b, M18, M29)
- [x] 2.2 Flip `deadman-heartbeat-feeder.test.sh` (count 4 to 0)
- [x] 2.3 Update the comment in `betterstack-alert-structure.test.sh`
- [ ] 3.1 Run the four suites; review; ship with `Ref #11672`
