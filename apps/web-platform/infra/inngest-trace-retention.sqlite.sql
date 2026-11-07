-- Dialect pin: Inngest server v1.45.1 schema.
-- Finished trace and log history only. In-flight rows stay. Redis is untouched.
-- soleur:statement
-- soleur:explain=spans
WITH doomed AS (
  SELECT s.rowid AS rid
  FROM spans s
  JOIN trace_runs tr ON tr.run_id = s.run_id
  WHERE tr.status IN (50, 300, 400, 500, 600)
    AND tr.ended_at IS NOT NULL
    AND tr.ended_at < (CAST(strftime('%s','now') AS INTEGER) * 1000 - :days * 86400000)
  LIMIT :batch
)
DELETE FROM spans WHERE rowid IN (SELECT rid FROM doomed);
-- soleur:statement
-- soleur:explain=traces
WITH doomed AS (
  SELECT t.rowid AS rid
  FROM traces t
  WHERE t.run_id IN (
    SELECT tr.run_id FROM trace_runs tr
    WHERE tr.status IN (50, 300, 400, 500, 600)
      AND tr.ended_at IS NOT NULL
      AND tr.ended_at < (CAST(strftime('%s','now') AS INTEGER) * 1000 - :days * 86400000)
  )
  LIMIT :batch
)
DELETE FROM traces WHERE rowid IN (SELECT rid FROM doomed);
-- soleur:statement
WITH doomed AS (
  SELECT eb.rowid AS rid
  FROM event_batches eb
  JOIN trace_runs tr ON tr.run_id = eb.run_id
  WHERE tr.status IN (50, 300, 400, 500, 600)
    AND tr.ended_at IS NOT NULL
    AND tr.ended_at < (CAST(strftime('%s','now') AS INTEGER) * 1000 - :days * 86400000)
  LIMIT :batch
)
DELETE FROM event_batches WHERE rowid IN (SELECT rid FROM doomed);
-- soleur:statement
WITH doomed AS (
  SELECT tr.rowid AS rid
  FROM trace_runs tr
  WHERE tr.status IN (50, 300, 400, 500, 600)
    AND tr.ended_at IS NOT NULL
    AND tr.ended_at < (CAST(strftime('%s','now') AS INTEGER) * 1000 - :days * 86400000)
  LIMIT :batch
)
DELETE FROM trace_runs WHERE rowid IN (SELECT rid FROM doomed);
-- soleur:statement
-- soleur:explain=history
WITH doomed AS (
  SELECT h.rowid AS rid
  FROM history h
  JOIN function_finishes ff ON ff.run_id = h.run_id
  WHERE ff.created_at < datetime('now', '-' || :days || ' days')
  LIMIT :batch
)
DELETE FROM history WHERE rowid IN (SELECT rid FROM doomed);
-- soleur:statement
WITH doomed AS (
  SELECT fr.rowid AS rid
  FROM function_runs fr
  JOIN function_finishes ff ON ff.run_id = fr.run_id
  WHERE ff.created_at < datetime('now', '-' || :days || ' days')
  LIMIT :batch
)
DELETE FROM function_runs WHERE rowid IN (SELECT rid FROM doomed);
-- soleur:statement
WITH doomed AS (
  SELECT ff.rowid AS rid
  FROM function_finishes ff
  WHERE ff.created_at < datetime('now', '-' || :days || ' days')
  LIMIT :batch
)
DELETE FROM function_finishes WHERE rowid IN (SELECT rid FROM doomed);
-- soleur:statement
-- soleur:explain=events
WITH doomed AS (
  SELECT e.rowid AS rid
  FROM events e
  WHERE e.received_at < datetime('now', '-' || :days || ' days')
    AND NOT EXISTS (
      SELECT 1 FROM function_runs fr
      LEFT JOIN function_finishes ff ON ff.run_id = fr.run_id
      WHERE fr.event_id = e.internal_id AND ff.run_id IS NULL
    )
  ORDER BY e.received_at
  LIMIT :batch
)
DELETE FROM events WHERE rowid IN (SELECT rid FROM doomed);
