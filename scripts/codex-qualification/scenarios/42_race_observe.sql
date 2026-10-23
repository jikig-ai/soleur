\set ON_ERROR_STOP on
SET statement_timeout='5s';
-- Controller polls this bounded observation in its owned DB observer session.
-- A nonzero result is NOT success: it must keep the holder open, and fail by
-- deadline if the required wait never appears. No sleep-based race claim.
SELECT codex_rehearsal.assert((
 SELECT count(*)=1 FROM pg_stat_activity waiter JOIN pg_stat_activity holder
 ON holder.pid=ANY(pg_blocking_pids(waiter.pid))
 WHERE waiter.application_name='codex9051-rehearsal-waiter'
 AND holder.application_name='codex9051-rehearsal-holder'
 AND waiter.datname=current_database() AND holder.datname=current_database()
 AND waiter.wait_event_type = 'Lock' AND holder.state='idle in transaction'
),'observed exact holder/waiter lock dependency');
