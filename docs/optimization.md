# Baseline

## Query 1: Below-quota rep coverage analysis

### EXPLAIN ANALYZE

- **Execution Time:** 1.432 ms
- **Planning Time:** 2.074 ms
- **Buffers:** shared hit=348 (all data served from cache, no disk reads)

#### Plan summary

| Node | Detail |
|---|---|
| Top-level Sort | By rep_name, coverage_status, hcp_name — quicksort, 26kB |
| WindowAgg | Computes pct_a_tier_unvisited window function |
| Nested Loop | Joins coverage targets to quota attainment |
| Hash Right Join | Matches actual visits to coverage targets |
| HashAggregate | Groups fct_hcp_visit by rep/hcp/product to count visits |
| Seq Scan — fct_hcp_visit | 4,743 rows scanned |
| Seq Scan — dim_date | 1,096 rows scanned, 1,004 removed by filter |
| Seq Scan — fct_hcp_coverage_target | 796 rows scanned, filtered to fiscal quarter |
| Seq Scan — fct_quota_attainment | 457 rows scanned, 439 removed by filter → 18 rows |
| Index Scan — dim_product_pkey | Memoized — 78 cache hits, 3 misses |
| Index Scan — dim_hcp_pkey | 81 loops, filters on is_current and segment = 'A' |
| Index Scan — dim_rep_pkey | 14 loops, filters on is_current |

---

## Query 2: Rolling 13-week prescription trend with week-over-week growth

### EXPLAIN ANALYZE

- **Execution Time:** 58.902 ms
- **Planning Time:** 2.528 ms
- **Buffers:** shared hit=1,272 (all cache, no disk reads)

#### Plan summary

| Node | Detail |
|---|---|
| Top-level Sort | By hcp_name, brand_name, week_end_date_key — quicksort, 729kB |
| Subquery Scan on trend_calc | 9,786 rows computed, 4,089 removed by display filter → 5,697 returned |
| WindowAgg (x2) | Two passes — one for rolling avg, one for LAG calculations |
| Sort | By hcp_key, product_key, week_end_date_key — quicksort, 1,078kB |
| Hash Join — product | Joins filtered rows to dim_product |
| Hash Join — hcp | Joins filtered rows to dim_hcp |
| Bitmap Heap Scan — fct_prescription_weekly | 21,961 rows scanned (date range pre-filter) |
| Bitmap Index Scan | Uses existing index on (week_end_date_key, hcp_key, product_key) |
| Seq Scan — dim_hcp | 501 rows scanned, 278 removed by segment filter → 223 rows |
| Seq Scan — dim_product | 4 rows scanned, 1 removed by is_current → 3 rows |

---

## Query 3: Rep quota attainment ranking within district

### EXPLAIN ANALYZE

- **Execution Time:** 0.946 ms
- **Planning Time:** 0.359 ms
- **Buffers:** shared hit=14 (all cache, no disk reads)

#### Plan summary

| Node | Detail |
|---|---|
| Incremental Sort (top) | By district, brand_name, district_rank — uses presorted district key |
| Subquery Scan on attainment_ranked | 150 rows passed through |
| WindowAgg (x3) | Three passes for DENSE_RANK, PERCENT_RANK, and AVG window functions |
| Incremental Sort (inner) | By district, product_key, attainment_pct — presorted on first two keys |
| Sort | By district, product_key, attainment_pct DESC — quicksort, 41kB |
| Hash Join | Joins fct_quota_attainment to dim_rep on rep_key |
| Nested Loop | Joins quota attainment to dim_product |
| Seq Scan — fct_quota_attainment | 457 rows scanned, 304 removed by quarter filter → 153 rows |
| Memoize — dim_product | 150 hits, 3 misses — only 3 unique products |
| Seq Scan — dim_rep | 51 rows scanned, 1 removed by is_current filter → 50 rows |

---

## Query 4: Territory transfer historical attribution

### EXPLAIN ANALYZE

- **Execution Time:** 0.760 ms
- **Planning Time:** 0.320 ms
- **Buffers:** shared hit=64 (all cache, no disk reads)

#### Plan summary

| Node | Detail |
|---|---|
| Top-level Sort | By date_key and transfer_period — quicksort, 26kB |
| WindowAgg (x2) | Two passes for visits_in_period and visit_num_in_period |
| Hash Join — territory | Joins rep rows to dim_territory on territory_key |
| Hash Join — hcp | Joins dim_hcp to visit rows on hcp_key |
| Seq Scan — dim_hcp | 501 rows scanned, 1 removed by is_current filter |
| Nested Loop | Joins fct_hcp_visit to dim_rep filtered to REP-DKEY-003 |
| Seq Scan — fct_hcp_visit | Full scan of 4,743 rows |
| Seq Scan — dim_rep | 51 rows scanned, 49 removed by rep_durable_key filter → 2 rows |
| Memoize — dim_product | 7 hits, 1 miss — only 1 unique product in results |
| Seq Scan — dim_territory | 6 rows scanned (small table) |

---

## Query 5: Co-promotion credit split

### EXPLAIN ANALYZE

- **Execution Time:** 7.889 ms
- **Planning Time:** 0.427 ms
- **Buffers:** shared hit=2020 (all cache, no disk reads)

#### Plan summary

| Node | Detail |
|---|---|
| GroupAggregate | Groups by rep_name, hcp_name, brand_name, credit_split_weight |
| Sort | By group key — quicksort, 55kB |
| Nested Loop | Joins bridge alignment rows to dim_rep — 21,462 rows removed by join filter |
| Seq Scan — dim_rep | 51 rows scanned, 1 removed by is_current |
| Materialize | Caches inner side of nested loop — re-used 50 times |
| Index Scan — bridge_hcp_rep_alignment | group_key = 1 → 2 rows, filtered by is_current |
| Nested Loop (inner) | Joins prescription rows to dim_hcp and dim_product |
| Seq Scan — fct_prescription_weekly | **110,283 rows removed by filter** to find 219 matching hcp_key=4 and group_key=1 |
| Index Scan — dim_hcp_pkey | 219 loops, 1 row each — efficient primary key lookup |
| Seq Scan — dim_product | 219 loops, tiny table |

---

## Query 6: HCP segment tier upgrade impact

### EXPLAIN ANALYZE

- **Execution Time:** 1.931 ms
- **Planning Time:** 0.330 ms
- **Buffers:** shared hit=423 (all cache, no disk reads)

#### Plan summary

| Node | Detail |
|---|---|
| WindowAgg | Computes avg_rx_change_vs_prior_period using LAG |
| Sort | By brand_name, tier_effective_date — quicksort, 25kB |
| GroupAggregate | Groups by tier_period, brand_name, segment, effective/expiration dates |
| Sort (inner) | By tier_period, brand_name, segment, dates — quicksort, 35kB |
| Nested Loop | Joins prescription rows to dim_hcp then dim_product |
| Seq Scan — dim_hcp | 501 rows scanned, 499 removed by hcp_durable_key filter → 2 SCD rows |
| Bitmap Heap Scan — fct_prescription_weekly | 73 rows per loop × 2 loops = 146 rows total |
| Bitmap Index Scan | Uses existing index on (week_end_date_key, hcp_key) — range + equality |
| Memoize — dim_product | 143 hits, 3 misses |

---

## Query 7: Year-over-year quota attainment comparison

### EXPLAIN ANALYZE

- **Execution Time:** 0.564 ms
- **Planning Time:** 0.222 ms
- **Buffers:** shared hit=14 (all cache, no disk reads)

#### Plan summary

| Node | Detail |
|---|---|
| Incremental Sort | By district, brand_name, yoy_growth_pct DESC — presorted on district |
| WindowAgg | Computes district_cumulative_yoy_growth running total |
| Sort | By district, product_key, attainment_pct DESC — quicksort, 41kB |
| Hash Join | Joins fct_quota_attainment to dim_rep on rep_key |
| Nested Loop | Joins quota rows to dim_product |
| Seq Scan — fct_quota_attainment | 457 rows scanned, 304 removed by quarter filter → 153 rows |
| Memoize — dim_product | 150 hits, 3 misses |
| Seq Scan — dim_rep | 51 rows scanned, 1 removed by is_current |

---

## Query 8: Flat quota identification

### EXPLAIN ANALYZE

- **Execution Time:** 1.870 ms
- **Planning Time:** 0.384 ms
- **Buffers:** shared hit=14 (all cache, no disk reads)

#### Plan summary

| Node | Detail |
|---|---|
| Sort | By quarters_at_this_quota DESC, district, rep_name — quicksort, 88kB |
| Hash Join | Joins fct_quota_attainment to dim_rep on rep_key |
| Nested Loop | Joins quota rows to dim_product |
| Seq Scan — fct_quota_attainment | Full scan of 457 rows — filter is a computed expression using AGE() |
| Memoize — dim_product | 454 hits, 3 misses |
| Seq Scan — dim_rep | 51 rows scanned, 1 removed by is_current |

---

## Query 9: Data quality audit — superseded batch investigation

### EXPLAIN ANALYZE

- **Execution Time:** 4.055 ms
- **Planning Time:** 1.279 ms
- **Buffers:** shared hit=6,985 (all cache, no disk reads)

#### Plan summary

| Node | Detail |
|---|---|
| Sort | By abs(units discrepancy) DESC — quicksort, 146kB |
| Nested Loop (x4) | Chain of nested loops joining prescription rows to audit, product, corrected batch, and hcp |
| Bitmap Heap Scan — fct_prescription_weekly (BATCH-005) | week_end_date_key = '2024-03-03' → 697 rows |
| Bitmap Index Scan | Uses existing index on (week_end_date_key, hcp_key, product_key) |
| Memoize — dim_audit | 696 hits, 1 miss — only 1 unique audit_key in BATCH-005 rows |
| Index Scan — fct_prescription_weekly (BATCH-006) | Looks up corrected row by week_end_date_key='2024-03-10', hcp_key, product_key, territory_key — 697 loops |
| Index Scan — dim_audit_pkey | Filters BATCH-006 rows — 697 loops, 1 row each |
| Index Scan — dim_hcp_pkey | 697 loops, 1 row each |

---

## Query 10: Market share trend by territory

### EXPLAIN ANALYZE

- **Execution Time:** 1.653 ms
- **Planning Time:** 0.341 ms
- **Buffers:** shared hit=872 (all cache, no disk reads)

#### Plan summary

| Node | Detail |
|---|---|
| Sort | By brand_name, district, territory_name, month_key — quicksort, 61kB |
| WindowAgg | Computes DENSE_RANK for territory rank within district |
| Sort (inner) | By district, brand_name, month_key, market_share_pct DESC |
| WindowAgg (x2) | LAG for prior month share and rolling 3-month average |
| Sort | By territory_name, brand_name, month_key |
| Nested Loop | Joins monthly fact to dim_product then dim_territory_rollup |
| Hash Join | Joins fct_prescription_territory_monthly to dim_month |
| Seq Scan — fct_prescription_territory_monthly | 648 rows scanned — small aggregate table |
| Seq Scan — dim_month | 36 rows scanned, 24 removed by fiscal_year filter → 12 rows |
| Index Scan — dim_product_pkey | 216 loops, 1 row each |
| Index Scan — dim_territory_rollup_pkey | 216 loops, 1 row each |

---

## Query 11: HCP decile ranking writeback validation

### EXPLAIN ANALYZE

- **Execution Time:** 21.499 ms
- **Planning Time:** 0.206 ms
- **Buffers:** shared hit=1155 (all cache, no disk reads)

#### Plan summary

| Node | Detail |
|---|---|
| Sort | By decile drift DESC, lifetime_rx_count DESC — quicksort, 120kB |
| Subquery Scan on hcp_deciles | 1,005 rows computed, 113 removed by mismatch filter → 892 returned |
| WindowAgg | NTILE(10) to compute calculated_decile |
| Sort | By product_key, lifetime_rx_count DESC — quicksort, 107kB |
| Hash Join — hcp | Joins aggregated totals to dim_hcp |
| Hash Join — product | Joins to dim_product |
| HashAggregate | Aggregates fct_prescription_weekly by hcp_key, product_key — 110,502 → 1,006 groups |
| Seq Scan — fct_prescription_weekly | Full scan of 110,502 rows — required to sum lifetime Rx |
| Seq Scan — dim_hcp | 501 rows scanned, 1 removed by is_current |
| Seq Scan — dim_product | 4 rows scanned, 1 removed by is_current |

---

## Query 12: Product indication expansion impact

### EXPLAIN ANALYZE

- **Execution Time:** 81.112 ms
- **Planning Time:** 0.300 ms
- **Buffers:** shared hit=1155 + **temp read=475, written=476** (spilled to disk)

#### Plan summary

| Node | Detail |
|---|---|
| WindowAgg | LAG for avg_rx_change_vs_prior_period |
| Sort | By specialty, indication_effective_date |
| GroupAggregate | Groups by indication_period, indication, specialty |
| Sort | By tier_period, brand_name, specialty, hcp_key — **external merge, 3800kB spilled to disk** |
| Hash Join — hcp | Joins prescription rows to dim_hcp |
| Hash Join — product | Filters to Humira rows only (2 product versions) |
| Seq Scan — fct_prescription_weekly | Full scan of 110,502 rows |
| Seq Scan — dim_product | 4 rows scanned, 2 removed → 2 Humira versions |
| Seq Scan — dim_hcp | 501 rows scanned, 1 removed by is_current |

# Baseline Summary

| Query | Execution Time | Disk I/O | Status |
|---|---|---|---|
| Q1 — Coverage analysis | 1.432 ms | None | Acceptable |
| Q2 — Rolling Rx trend | 58.902 ms | None | Acceptable |
| Q3 — Attainment ranking | 0.946 ms | None | Acceptable |
| Q4 — Territory transfer | 0.760 ms | None | Acceptable |
| Q5 — Co-promotion credit | 7.889 ms | None | **Needs index** |
| Q6 — Tier upgrade impact | 1.931 ms | None | Acceptable |
| Q7 — YoY comparison | 0.564 ms | None | Acceptable |
| Q8 — Flat quota | 1.870 ms | None | Acceptable |
| Q9 — Audit investigation | 4.055 ms | None | Acceptable |
| Q10 — Market share trend | 1.653 ms | None | Acceptable |
| Q11 — Decile validation | 21.499 ms | None | Intentional full scan |
| Q12 — Indication expansion | 81.112 ms | **Disk spill** | **Needs index** |

## Key Findings

Query 2 and Query 12 are the only queries with execution times above 50ms.
They trace back to different root causes.

Query 2 originally took 100ms because the date filter was placed in the final
SELECT, after the window functions had already run across the full dataset.
Refactoring the query to pre-filter rows before the window functions reduced
execution time by 41%, eliminated parallel workers, and cut sort memory by
62%. The pre-filter window starts 13 weeks before the display window opens to
preserve correct rolling average history.

Query 12 takes 81ms and is the only query in the set that spills to disk. The
sort of 38,251 rows for the GroupAggregate exceeded PostgreSQL's `work_mem`
allocation and wrote 3.8MB of temporary files to disk. The full table scan
feeds all Humira rows — across both product versions — into the sort before
any aggregation occurs. An index on `(product_key)` would reduce the rows
entering the sort from 110,502 to only the Humira rows, potentially
eliminating the spill entirely.

Query 5 executes in 7.889ms which looks acceptable, but the plan reveals it
scans 110,283 rows to return 219. That is a 99.8% rejection rate. At this data
size the full scan is cheap because everything fits in shared buffers. At ten
times the data size — one million prescription rows, which is realistic for
a real pharma company — this query would scan one million rows to return
roughly 2,000. The same index on `(hcp_key, week_end_date_key)` that fixes
Query 2 will fix this structural problem before it becomes observable.

Query 11 runs in 21.499ms and scans all 110,502 prescription rows. This is
correct and expected. The query computes NTILE(10) rankings across the entire
physician population — it needs every row to produce accurate decile
assignments.

## Index 1: Concatenated index on fct_prescription_weekly

**Definition:** `CREATE INDEX idx_rx_weekly_hcp_date ON fct_prescription_weekly (hcp_key, week_end_date_key)`

### Query 5 — Co-promotion credit split

| Configuration | Execution Time | Pages Read | Plan Node |
|---|---|---|---|
| No index | 7.889 ms | ~2,020 buffer hits | Seq Scan — 110,283 rows removed by filter |
| Wrong order — date first | 7.461 ms | 272 pages | Bitmap Index Scan on idx_rx_weekly_date_hcp_wrong |
| Correct order — hcp_key first | 1.663 ms | 5 pages | Index Scan on idx_rx_weekly_hcp_date |

**Result: 4.7x improvement. Hypothesis confirmed for Query 5.**

The correct index reduced pages read from 272 to 5 — a 54x reduction. The
planner navigated the B-tree directly to the 112 rows matching `hcp_key = 4`
and retrieved them with 5 page reads. The wrong-order index had to scan the
full date range across all physicians first, then filter for physician 4 —
turning the HCP equality condition into a filter predicate instead of an
access predicate. The result: 272 pages read to return the same 112 rows.

---




