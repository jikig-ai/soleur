-- Dialect pin: Inngest server v1.45.1 schema.
-- Finished trace and log history only. In-flight rows stay. Redis is untouched.
-- soleur:statement
-- soleur:explain=spans
WITH doomed AS (
  SELECT s.ctid
  FROM spans s
  JOIN trace_runs tr ON tr.run_id = s.run_id
  WHERE tr.status IN (50, 300, 400, 500, 600)
    AND tr.ended_at IS NOT NULL
    AND tr.ended_at < ((floor(extract(epoch from clock_timestamp()) * 1000) - (:days)::bigint * 86400000)::bigint)
  LIMIT :batch
),
deleted AS (
  DELETE FROM spans WHERE ctid IN (SELECT ctid FROM doomed) RETURNING 1
)
SELECT count(*) FROM deleted;
-- soleur:statement
-- soleur:explain=traces
WITH doomed AS (
  SELECT t.ctid
  FROM traces t
  WHERE t.run_id IN (
    SELECT tr.run_id FROM trace_runs tr
    WHERE tr.status IN (50, 300, 400, 500, 600)
      AND tr.ended_at IS NOT NULL
      AND tr.ended_at < ((floor(extract(epoch from clock_timestamp()) * 1000) - (:days)::bigint * 86400000)::bigint)
  )
  LIMIT :batch
),
deleted AS (
  DELETE FROM traces WHERE ctid IN (SELECT ctid FROM doomed) RETURNING 1
)
SELECT count(*) FROM deleted;
-- soleur:statement
WITH doomed AS (
  SELECT eb.ctid
  FROM event_batches eb
  JOIN trace_runs tr ON tr.run_id = eb.run_id
  WHERE tr.status IN (50, 300, 400, 500, 600)
    AND tr.ended_at IS NOT NULL
    AND tr.ended_at < ((floor(extract(epoch from clock_timestamp()) * 1000) - (:days)::bigint * 86400000)::bigint)
  LIMIT :batch
),
deleted AS (
  DELETE FROM event_batches WHERE ctid IN (SELECT ctid FROM doomed) RETURNING 1
)
SELECT count(*) FROM deleted;
-- soleur:statement
WITH doomed AS (
  SELECT tr.ctid
  FROM trace_runs tr
  WHERE tr.status IN (50, 300, 400, 500, 600)
    AND tr.ended_at IS NOT NULL
    AND tr.ended_at < ((floor(extract(epoch from clock_timestamp()) * 1000) - (:days)::bigint * 86400000)::bigint)
  LIMIT :batch
),
deleted AS (
  DELETE FROM trace_runs WHERE ctid IN (SELECT ctid FROM doomed) RETURNING 1
)
SELECT count(*) FROM deleted;
-- soleur:statement
-- soleur:explain=history
WITH doomed AS (
  SELECT h.ctid
  FROM history h
  JOIN function_finishes ff ON ff.run_id = h.run_id
  WHERE ff.created_at < clock_timestamp() - make_interval(days => :days)
  LIMIT :batch
),
deleted AS (
  DELETE FROM history WHERE ctid IN (SELECT ctid FROM doomed) RETURNING 1
)
SELECT count(*) FROM deleted;
-- soleur:statement
WITH doomed AS (
  SELECT fr.ctid
  FROM function_runs fr
  JOIN function_finishes ff ON ff.run_id = fr.run_id
  WHERE ff.created_at < clock_timestamp() - make_interval(days => :days)
  LIMIT :batch
),
deleted AS (
  DELETE FROM function_runs WHERE ctid IN (SELECT ctid FROM doomed) RETURNING 1
)
SELECT count(*) FROM deleted;
-- soleur:statement
WITH doomed AS (
  SELECT ff.ctid
  FROM function_finishes ff
  WHERE ff.created_at < clock_timestamp() - make_interval(days => :days)
  LIMIT :batch
),
deleted AS (
  DELETE FROM function_finishes WHERE ctid IN (SELECT ctid FROM doomed) RETURNING 1
)
SELECT count(*) FROM deleted;
-- soleur:statement
-- soleur:explain=events
WITH doomed AS (
  SELECT e.ctid
  FROM events e
  WHERE e.received_at < clock_timestamp() - make_interval(days => :days)
    AND NOT EXISTS (
      SELECT 1 FROM function_runs fr
      LEFT JOIN function_finishes ff ON ff.run_id = fr.run_id
      WHERE fr.event_id = e.internal_id AND ff.run_id IS NULL
    )
  ORDER BY e.received_at
  LIMIT :batch
),
deleted AS (
  DELETE FROM events WHERE ctid IN (SELECT ctid FROM doomed) RETURNING 1
)
SELECT count(*) FROM deleted;
