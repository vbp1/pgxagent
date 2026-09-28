Objective:
Perform a comprehensive proactive health check of the PostgreSQL database to identify potential issues before they become critical.

Step 1: Check Index Health

1a. Find invalid indexes (failed CREATE INDEX CONCURRENTLY):
Use executeReadOnlyQuery:

```sql
SELECT schemaname AS schema, t.relname AS table_name, ix.relname AS index_name,
       pg_get_indexdef(i.indexrelid) AS definition
FROM pg_index i
JOIN pg_class t ON t.oid = i.indrelid
JOIN pg_class ix ON ix.oid = i.indexrelid
LEFT JOIN pg_stat_user_indexes ui ON ui.indexrelid = i.indexrelid
WHERE schemaname IS NOT NULL AND NOT indisvalid
ORDER BY schemaname, t.relname
```

→ Action: REINDEX INDEX CONCURRENTLY schema.index_name

1b. Find unused indexes (idx_scan = 0 or very low):
Use executeReadOnlyQuery:

```sql
SELECT schemaname AS schema, relname AS table_name, indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(i.indexrelid)) AS size,
       idx_scan AS scans
FROM pg_stat_user_indexes ui
JOIN pg_index i ON ui.indexrelid = i.indexrelid
WHERE NOT indisunique AND NOT indisprimary AND idx_scan < 50
ORDER BY pg_relation_size(i.indexrelid) DESC
LIMIT 20
```

→ Action: DROP INDEX schema.index_name (after verification)
→ Caveat: Stats are cumulative since last reset, check pg_stat_reset timestamp

1c. Find duplicate indexes (one index covers another):
Use executeReadOnlyQuery:

```sql
WITH index_cols AS (
  SELECT
    i.schemaname,
    i.tablename,
    i.indexname,
    regexp_replace(i.indexdef, '^[^(]*\(([^)]*)\).*$', '\1') AS columns,
    pg_relation_size(s.indexrelid) AS size
  FROM pg_indexes i
  JOIN pg_stat_user_indexes s
    ON s.schemaname = i.schemaname
    AND s.indexrelname = i.indexname
  WHERE i.schemaname NOT IN ('pg_catalog', 'information_schema')
)
SELECT a.schemaname, a.tablename, a.indexname AS redundant_index,
       b.indexname AS covering_index, a.columns,
       pg_size_pretty(a.size) AS wasted_size
FROM index_cols a
JOIN index_cols b
  ON a.schemaname = b.schemaname
  AND a.tablename = b.tablename
  AND a.indexname != b.indexname
  AND b.columns LIKE a.columns || ',%'
ORDER BY a.size DESC
LIMIT 10
```

→ Action: DROP INDEX schema.redundant_index

Step 2: Check Connection Health

Use getConnectionsGroups for overview: its summary is the total, its data the breakdown by group.

Additionally, check idle-in-transaction connections:
Use executeReadOnlyQuery:

```sql
SELECT pid, usename, application_name, client_addr, state,
       now() - xact_start AS transaction_duration,
       now() - state_change AS idle_duration,
       LEFT(query, 100) AS query_preview
FROM pg_stat_activity
WHERE state = 'idle in transaction'
  AND now() - state_change > interval '5 minutes'
ORDER BY state_change
```

→ Warning if count > 10 or duration > 30 minutes
→ Action: Investigate application, consider idle_in_transaction_session_timeout

Step 3: Check Vacuum Health (XID Wraparound Risk)

Use getVacuumStats for general vacuum status.

Check tables approaching XID wraparound:
Use executeReadOnlyQuery:

```sql
SELECT n.nspname AS schema, c.relname AS table_name,
       age(c.relfrozenxid) AS xid_age,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS size,
       2147483647 - age(c.relfrozenxid) AS transactions_left
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND age(c.relfrozenxid) > 100000000
ORDER BY age(c.relfrozenxid) DESC
LIMIT 20
```

→ CRITICAL if transactions_left < 10M
→ Action: VACUUM FREEZE schema.table_name

Step 4: Check Sequence Exhaustion Risk

Use executeReadOnlyQuery to find all sequences:

```sql
SELECT n.nspname AS schema, c.relname AS table_name, a.attname AS column,
       format_type(a.atttypid, a.atttypmod) AS column_type,
       pg_get_expr(d.adbin, d.adrelid) AS default_value
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attrdef d ON (a.attrelid, a.attnum) = (d.adrelid, d.adnum)
WHERE NOT a.attisdropped AND a.attnum > 0
  AND pg_get_expr(d.adbin, d.adrelid) LIKE 'nextval%'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
```

For integer sequences, check usage with this pattern (replace SEQUENCE_NAME):

```sql
SELECT last_value,
       2147483647 AS max_value,
       round(100.0 * last_value / 2147483647, 2) AS percent_used
FROM SEQUENCE_NAME
```

→ Warning if percent_used > 50% for integer sequences
→ Action: ALTER TABLE ... ALTER COLUMN ... TYPE bigint

Step 5: Check Replication Health

First, check if this is a replica:
Use executeReadOnlyQuery:

```sql
SELECT pg_is_in_recovery() AS is_replica
```

If PRIMARY, check connected replicas:

```sql
SELECT pid, application_name, client_addr, state, sync_state,
       write_lag, flush_lag, replay_lag,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication
```

Check replication slots (inactive slots cause WAL bloat):

```sql
SELECT slot_name, slot_type, database, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots
WHERE NOT active
```

→ Warning if inactive slots exist
→ Action: SELECT pg_drop_replication_slot('slot_name') if safe to drop

Step 6: Check Buffer Cache Efficiency

Use executeReadOnlyQuery:

```sql
SELECT
  'index' AS type,
  round(100.0 * sum(idx_blks_hit) / nullif(sum(idx_blks_hit + idx_blks_read), 0), 2) AS hit_rate_pct
FROM pg_statio_user_indexes
UNION ALL
SELECT
  'table' AS type,
  round(100.0 * sum(heap_blks_hit) / nullif(sum(heap_blks_hit + heap_blks_read), 0), 2) AS hit_rate_pct
FROM pg_statio_user_tables
```

Interpretation rules:

- pg_statio hit rate measures hits in shared_buffers ONLY, not OS page cache.
  With small shared_buffers (< 1 GB), low hit rates are EXPECTED and do not necessarily
  indicate poor performance - the OS file cache handles most reads.
- Before recommending shared_buffers changes, cross-reference with findings from
  Step 1 (Index Health): large unused indexes inflate the working set and reduce
  effective cache utilization. Dropping unused indexes should be prioritized over
  increasing shared_buffers.

→ Warning if hit_rate < 95% AND shared_buffers > 10% of estimated RAM
→ Info (not warning) if hit_rate < 95% AND shared_buffers < 1 GB - note that low hit rate
is expected with small shared_buffers
→ Action: If unused indexes were found in Step 1, recommend removing them FIRST
as primary action to improve cache efficiency
→ Action: If shared_buffers is disproportionately small relative to database size,
recommend increasing it. Note: shared_buffers requires a PostgreSQL RESTART
(context = 'postmaster'). Do NOT suggest pg_reload_conf().
→ Use getPerformanceAndVacuumSettings to check current shared_buffers value and its
context field before making recommendations
→ Before recommending a shared_buffers value, you MUST call computeRecommendedSettings
→ If recommending a specific shared_buffers value, use checkSettingsSafety tool
to verify memory safety

Step 7: Check Invalid Constraints

Use executeReadOnlyQuery:

```sql
SELECT nsp.nspname AS schema, rel.relname AS table_name, con.conname AS constraint_name,
       con.contype AS type,
       fnsp.nspname AS ref_schema, frel.relname AS ref_table
FROM pg_constraint con
JOIN pg_class rel ON rel.oid = con.conrelid
LEFT JOIN pg_class frel ON frel.oid = con.confrelid
LEFT JOIN pg_namespace nsp ON nsp.oid = con.connamespace
LEFT JOIN pg_namespace fnsp ON fnsp.oid = frel.relnamespace
WHERE NOT con.convalidated
ORDER BY nsp.nspname, rel.relname
```

→ Action: ALTER TABLE schema.table VALIDATE CONSTRAINT constraint_name

Step 8: Generate Health Report

After completing all checks, present a summary report and show

**Overall Status:** HEALTHY / NEEDS ATTENTION / CRITICAL

Step 9: Generate Action Items

## Action Items

**CRITICAL (act immediately):**

- [ ] Item 1 with exact SQL command
- [ ] Item 2 with exact SQL command

**WARNING (schedule maintenance):**

- [ ] Item 1 with exact SQL command
- [ ] Item 2 with exact SQL command

**INFO (monitor):**

- [ ] Item 1
- [ ] Item 2

IMPORTANT:

- Always provide exact SQL commands for remediation
- For DROP INDEX: warn about potential query performance impact
- For VACUUM FREEZE: warn about potential lock contention on large tables
- Include estimated sizes and counts in the summary
