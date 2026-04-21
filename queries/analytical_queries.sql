-- ============================================================
-- Query N: [Business Question]
-- Tables: [which fact and dimension tables are used]
-- ============================================================


-- ============================================================
-- Query 1: Below-quota rep coverage analysis
-- Business question: When a rep misses quota, is it because they
--   aren't visiting enough physicians, or are they visiting the
--   wrong ones? This query identifies reps below 80% attainment
--   and checks whether their A-tier physicians — the highest
--   prescribing potential targets — are being visited or ignored.
--   Total visit volume is included alongside A-tier coverage to
--   distinguish effort problems from targeting problems.
-- Tables: fct_quota_attainment, fct_hcp_visit, fct_hcp_coverage_target,
--         dim_rep, dim_hcp, dim_product, dim_date
-- ============================================================

WITH below_quota_reps AS (
    SELECT
        qa.rep_key,
        r.rep_name,
        r.current_territory_name,
        r.district,
        qa.product_key,
        p.brand_name,
        qa.quota_units,
        qa.actual_units,
        qa.attainment_pct
    FROM fct_quota_attainment qa
    JOIN dim_rep r
        ON  qa.rep_key    = r.rep_key
        AND r.is_current  = TRUE
    JOIN dim_product p
        ON  qa.product_key   = p.product_key
        AND p.is_current     = TRUE
    WHERE qa.fiscal_quarter_key = '2023-08-01'
      AND qa.attainment_pct     < 80.0
),

total_visits AS (
    -- Total visits made by each below-quota rep during FQ1 FY2024
    -- regardless of HCP tier — answers "are they visiting enough"
    SELECT
        v.rep_key,
        COUNT(*)                        AS total_visits_in_quarter,
        COUNT(DISTINCT v.hcp_key)       AS unique_hcps_visited
    FROM fct_hcp_visit v
    JOIN dim_date d
        ON  v.date_key        = d.date_key
    WHERE d.fiscal_quarter    = 1
      AND d.fiscal_year       = 2024
    GROUP BY v.rep_key
),

coverage_targets AS (
    SELECT
        ct.rep_key,
        ct.hcp_key,
        ct.product_key,
        h.full_name     AS hcp_name,
        h.segment
    FROM fct_hcp_coverage_target ct
    JOIN dim_hcp h
        ON  ct.hcp_key   = h.hcp_key
        AND h.is_current = TRUE
    WHERE ct.fiscal_quarter_key = '2023-08-01'
      AND h.segment             = 'A'
),

actual_visits AS (
    SELECT
        v.rep_key,
        v.hcp_key,
        v.product_key,
        COUNT(*)        AS visit_count
    FROM fct_hcp_visit v
    JOIN dim_date d
        ON  v.date_key        = d.date_key
    WHERE d.fiscal_quarter    = 1
      AND d.fiscal_year       = 2024
    GROUP BY v.rep_key, v.hcp_key, v.product_key
)

SELECT
    bq.rep_name,
    bq.current_territory_name,
    bq.brand_name,
    bq.attainment_pct,
    -- Total effort metrics
    COALESCE(tv.total_visits_in_quarter, 0)     AS total_visits_in_quarter,
    COALESCE(tv.unique_hcps_visited, 0)         AS unique_hcps_visited,
    -- A-tier coverage metrics
    ct.hcp_name,
    ct.segment,
    COALESCE(av.visit_count, 0)                 AS visits_made,
    CASE
        WHEN COALESCE(av.visit_count, 0) = 0 THEN 'No visits'
        WHEN av.visit_count              < 2  THEN 'Undercovered'
        ELSE                                       'Adequately covered'
    END                                         AS coverage_status,
    ROUND(
        100.0 * SUM(CASE WHEN COALESCE(av.visit_count, 0) = 0 THEN 1 ELSE 0 END)
            OVER (PARTITION BY bq.rep_key, bq.product_key)
        / COUNT(*) OVER (PARTITION BY bq.rep_key, bq.product_key),
        1
    )                                           AS pct_a_tier_unvisited
FROM below_quota_reps bq
LEFT JOIN total_visits tv
    ON  bq.rep_key = tv.rep_key
JOIN coverage_targets ct
    ON  bq.rep_key     = ct.rep_key
    AND bq.product_key = ct.product_key
LEFT JOIN actual_visits av
    ON  ct.rep_key     = av.rep_key
    AND ct.hcp_key     = av.hcp_key
    AND ct.product_key = av.product_key
ORDER BY
    bq.rep_name,
    coverage_status,
    ct.hcp_name;

-- ============================================================
-- Query 2: Rolling 13-week prescription trend with week-over-week growth
-- Business question: How has each physician's prescription volume
--   trended over the past 13 weeks? Are they writing more or fewer
--   prescriptions than the week before? This is the primary report
--   a brand team uses to identify physicians whose engagement is
--   growing, plateauing, or dropping — and to flag anomalies worth
--   investigating.
-- Tables: fct_prescription_weekly, dim_hcp, dim_product, dim_date
-- Scenario: Dr. James Okafor (hcp_key=5) shows a visible drop in
--           weeks of 2023-08-06 through 2023-09-03 plus 13 weeks before it
-- ============================================================

WITH filtered_rx AS (
    -- Pull rows starting 13 weeks before the display window
    -- so the rolling average has the historical data it needs
    SELECT
        p.week_end_date_key,
        p.hcp_key,
        h.full_name             AS hcp_name,
        h.segment,
        h.decile_rank,
        pr.brand_name,
        p.product_key,
        p.total_rx_count
    FROM fct_prescription_weekly p
    JOIN dim_hcp h
        ON  p.hcp_key    = h.hcp_key
        AND h.is_current = TRUE
    JOIN dim_product pr
        ON  p.product_key   = pr.product_key
        AND pr.is_current   = TRUE
    -- Start 13 weeks before the display window opens
    -- This gives the rolling average its required lookback history
    WHERE p.week_end_date_key BETWEEN '2023-03-05' AND '2023-10-01'
      AND h.segment IN ('A', 'B')
),

trend_calc AS (
    SELECT
        week_end_date_key,
        hcp_key,
        product_key,
        hcp_name,
        segment,
        decile_rank,
        brand_name,
        total_rx_count,

        -- Rolling 13-week average
        ROUND(
            AVG(total_rx_count) OVER (
                PARTITION BY hcp_key, product_key
                ORDER BY week_end_date_key
                ROWS BETWEEN 12 PRECEDING AND CURRENT ROW
            ), 1
        )                       AS rolling_13wk_avg,

        -- Prior week volume using LAG
        LAG(total_rx_count, 1) OVER (
            PARTITION BY hcp_key, product_key
            ORDER BY week_end_date_key
        )                       AS prior_week_rx,

        -- Week-over-week change
        total_rx_count - LAG(total_rx_count, 1) OVER (
            PARTITION BY hcp_key, product_key
            ORDER BY week_end_date_key
        )                       AS wow_change,

        -- Week-over-week percent change
        ROUND(
            100.0 * (total_rx_count - LAG(total_rx_count, 1) OVER (
                PARTITION BY hcp_key, product_key
                ORDER BY week_end_date_key
            )) / NULLIF(LAG(total_rx_count, 1) OVER (
                PARTITION BY hcp_key, product_key
                ORDER BY week_end_date_key
            ), 0), 1
        )                       AS wow_pct_change
    FROM filtered_rx
)

-- Display window filter applied here — after window functions have run
-- Rows from March–May were needed for correct averages but are not shown
SELECT
    week_end_date_key,
    hcp_name,
    segment,
    decile_rank,
    brand_name,
    total_rx_count,
    rolling_13wk_avg,
    prior_week_rx,
    wow_change,
    wow_pct_change,
    CASE
        WHEN wow_pct_change < -30 THEN 'Significant drop'
        WHEN wow_pct_change < -10 THEN 'Moderate drop'
        WHEN wow_pct_change >  30 THEN 'Significant increase'
        ELSE                           'Stable'
    END                         AS trend_flag
FROM trend_calc
WHERE week_end_date_key BETWEEN '2023-06-01' AND '2023-10-01'
ORDER BY
    hcp_name,
    brand_name,
    week_end_date_key;

-- ============================================================
-- Query 3: Rep quota attainment ranking within district
-- Business question: How does each rep rank against their peers
--   in the same district? A district manager needs to see the
--   full leaderboard — not just who missed quota, but who is
--   first, second, last — so they know where to direct coaching
--   and where to celebrate wins.
-- Tables: fct_quota_attainment, dim_rep, dim_product, dim_date
-- Scenario: Sarah Chen and Marcus Williams appear in their
--           respective district rankings with their quota miss
-- ============================================================

WITH attainment_ranked AS (
    SELECT
        r.rep_name,
        r.district,
        r.current_territory_name,
        p.brand_name,
        qa.quota_units,
        qa.actual_units,
        qa.attainment_pct,

        -- Rank reps within district by attainment, highest first
        -- DENSE_RANK so tied reps share the same rank
        DENSE_RANK() OVER (
            PARTITION BY r.district, qa.product_key, qa.fiscal_quarter_key
            ORDER BY qa.attainment_pct DESC
        )                               AS district_rank,

        -- Total reps in district for context
        COUNT(*) OVER (
            PARTITION BY r.district, qa.product_key, qa.fiscal_quarter_key
        )                               AS reps_in_district,

        -- Percentile within district
        ROUND(
            100.0 * PERCENT_RANK() OVER (
                PARTITION BY r.district, qa.product_key, qa.fiscal_quarter_key
                ORDER BY qa.attainment_pct
            )::NUMERIC, 1
        )                               AS percentile_in_district,

        -- District average attainment for comparison
        ROUND(
            AVG(qa.attainment_pct) OVER (
                PARTITION BY r.district, qa.product_key, qa.fiscal_quarter_key
            )::NUMERIC, 1
        )                               AS district_avg_attainment,

        -- Difference from district average
        ROUND(
            qa.attainment_pct - AVG(qa.attainment_pct) OVER (
                PARTITION BY r.district, qa.product_key, qa.fiscal_quarter_key
            )::NUMERIC, 1
        )                               AS vs_district_avg

    FROM fct_quota_attainment qa
    JOIN dim_rep r
        ON  qa.rep_key    = r.rep_key
        AND r.is_current  = TRUE
    JOIN dim_product p
        ON  qa.product_key   = p.product_key
        AND p.is_current     = TRUE
    WHERE qa.fiscal_quarter_key = '2023-08-01'   -- FQ1 FY2024
)

SELECT
    district,
    district_rank,
    rep_name,
    current_territory_name,
    brand_name,
    quota_units,
    actual_units,
    attainment_pct,
    reps_in_district,
    percentile_in_district,
    district_avg_attainment,
    vs_district_avg,
    CASE
        WHEN attainment_pct >= 100 THEN 'At or above quota'
        WHEN attainment_pct >=  80 THEN 'Near quota'
        WHEN attainment_pct >=  60 THEN 'Below quota'
        ELSE                            'Significantly below quota'
    END                             AS attainment_status
FROM attainment_ranked
ORDER BY
    district,
    brand_name,
    district_rank;

-- ============================================================
-- Query 4: Territory transfer historical attribution
-- Business question: When a rep transfers territories mid-year,
--   how do we correctly attribute their visits and performance
--   to the right territory at the right time? This query shows
--   James Rivera's activity before and after his March 2024
--   transfer, proving that historical visits are attributed to
--   Northeast and post-transfer visits to Southwest — never mixed.
-- Tables: fct_hcp_visit, dim_rep, dim_hcp, dim_product, dim_date
-- Scenario: James Rivera (rep_durable_key=REP-DKEY-003) transfers
--           from Northeast Boston to Southwest Dallas on 2024-03-01
-- ============================================================

WITH rivera_all_versions AS (
    -- Pull all SCD rows for James Rivera using durable key
    SELECT
        r.rep_key,
        r.rep_name,
        r.territory_key,
        t.territory_name        AS assigned_territory,
        t.district_name,
        r.effective_date,
        r.expiration_date,
        r.is_current,
        r.current_territory_name
    FROM dim_rep r
    JOIN dim_territory t
        ON r.territory_key = t.territory_key
    WHERE r.rep_durable_key = 'REP-DKEY-003'
),

visit_attribution AS (
    -- Join visits to the rep row that was active at the time of the visit
    -- This is the as-was join — matching the surrogate key stamped at load time
    SELECT
        v.visit_key,
        v.date_key,
        r.rep_name,
        r.assigned_territory    AS territory_at_time_of_visit,
        r.district_name,
        r.is_current,
        r.current_territory_name,
        h.full_name             AS hcp_name,
        h.city,
        h.state,
        p.brand_name,
        v.samples_dropped,
        v.visit_duration_minutes,
        CASE
            WHEN v.date_key < '2024-03-01' THEN 'Pre-transfer'
            ELSE                                 'Post-transfer'
        END                     AS transfer_period
    FROM fct_hcp_visit v
    JOIN rivera_all_versions r
        ON v.rep_key = r.rep_key
    JOIN dim_hcp h
        ON  v.hcp_key    = h.hcp_key
        AND h.is_current = TRUE
    JOIN dim_product p
        ON  v.product_key   = p.product_key
        AND p.is_current    = TRUE
)

SELECT
    transfer_period,
    territory_at_time_of_visit,
    current_territory_name,
    rep_name,
    date_key,
    hcp_name,
    city,
    state,
    brand_name,
    samples_dropped,
    visit_duration_minutes,
    -- Summary counts per period
    COUNT(*) OVER (
        PARTITION BY transfer_period
    )                           AS visits_in_period,
    -- Running visit count within each period
    ROW_NUMBER() OVER (
        PARTITION BY transfer_period
        ORDER BY date_key
    )                           AS visit_num_in_period
FROM visit_attribution
ORDER BY
    date_key,
    transfer_period;


-- ============================================================
-- Query 5: Co-promotion credit split
-- Business question: When two reps share responsibility for the
--   same physician, how do we divide prescription credit between
--   them without double-counting? This query applies the bridge
--   table weight to distribute Dr. Robert Kim's prescriptions
--   60% to Sarah Chen and 40% to David Park, then shows what
--   the numbers would look like without the split — proving
--   the double-counting problem the bridge table solves.
-- Tables: fct_prescription_weekly, bridge_hcp_rep_alignment,
--         dim_rep, dim_hcp, dim_product
-- Scenario: Dr. Robert Kim (hcp_key=4) co-promoted by Sarah Chen
--           (rep_key=1, 60%) and David Park (rep_key=4, 40%)
-- ============================================================

WITH kim_prescriptions AS (
    -- Total prescriptions written by Dr. Robert Kim for Humira
    SELECT
        p.week_end_date_key,
        p.hcp_key,
        h.full_name         AS hcp_name,
        p.product_key,
        pr.brand_name,
        p.total_rx_count,
        p.total_units,
        p.group_key
    FROM fct_prescription_weekly p
    JOIN dim_hcp h
        ON  p.hcp_key    = h.hcp_key
        AND h.is_current = TRUE
    JOIN dim_product pr
        ON  p.product_key   = pr.product_key
        AND pr.is_current   = TRUE
    WHERE p.hcp_key   = 4   -- Dr. Robert Kim
      AND p.group_key = 1   -- co-promotion group
),

credit_split AS (
    -- Apply bridge table weights to distribute credit
    SELECT
        kp.week_end_date_key,
        kp.hcp_name,
        kp.brand_name,
        r.rep_name,
        b.credit_split_weight,
        kp.total_rx_count,
        kp.total_units,
        -- Weighted credit
        ROUND(kp.total_rx_count * b.credit_split_weight, 1)    AS attributed_rx,
        ROUND(kp.total_units    * b.credit_split_weight, 0)    AS attributed_units,
        -- What it would look like without the split (double-counting)
        kp.total_rx_count                                       AS unweighted_rx,
        kp.total_units                                          AS unweighted_units
    FROM kim_prescriptions kp
    JOIN bridge_hcp_rep_alignment b
        ON  kp.group_key   = b.group_key
        AND b.is_current   = TRUE
    JOIN dim_rep r
        ON  b.rep_key    = r.rep_key
        AND r.is_current = TRUE
)

SELECT
    rep_name,
    hcp_name,
    brand_name,
    credit_split_weight,
    SUM(attributed_rx)      AS total_attributed_rx,
    SUM(attributed_units)   AS total_attributed_units,
    SUM(unweighted_rx)      AS total_unweighted_rx,
    SUM(unweighted_units)   AS total_unweighted_units,
    -- Show the overcount that would result without the bridge
    SUM(unweighted_rx) - SUM(attributed_rx)     AS rx_overcount_without_bridge,
    SUM(unweighted_units) - SUM(attributed_units) AS units_overcount_without_bridge
FROM credit_split
GROUP BY
    rep_name,
    hcp_name,
    brand_name,
    credit_split_weight
ORDER BY
    rep_name;


-- ============================================================
-- Query 6: HCP segment tier upgrade impact
-- Business question: When a physician gets reclassified from a
--   lower tier to a higher tier, did their prescription volume
--   actually justify the upgrade? This query compares Dr. Patricia
--   Moore's prescription volume before and after her B-to-A tier
--   reclassification in January 2024, using the SCD Type 2 history
--   to correctly label each period.
-- Tables: fct_prescription_weekly, dim_hcp, dim_product, dim_date
-- Scenario: Dr. Patricia Moore (hcp_durable_key=HCP-DKEY-002)
--           upgraded from B-tier to A-tier on 2024-01-15
-- ============================================================

WITH moore_rx AS (
    -- Pull all prescription rows for Dr. Patricia Moore
    -- Join to dim_hcp using durable key to get both SCD versions
    SELECT
        p.week_end_date_key,
        h.hcp_durable_key,
        h.full_name,
        h.segment,
        h.effective_date        AS tier_effective_date,
        h.expiration_date       AS tier_expiration_date,
        pr.brand_name,
        p.total_rx_count,
        p.new_rx_count,
        p.total_units,
        CASE
            WHEN h.segment = 'B' THEN 'Pre-upgrade (B-tier)'
            WHEN h.segment = 'A' THEN 'Post-upgrade (A-tier)'
        END                     AS tier_period
    FROM fct_prescription_weekly p
    JOIN dim_hcp h
        ON  p.hcp_key = h.hcp_key
    JOIN dim_product pr
        ON  p.product_key   = pr.product_key
        AND pr.is_current   = TRUE
    WHERE h.hcp_durable_key = 'HCP-DKEY-002'
      AND p.week_end_date_key BETWEEN '2023-07-01' AND '2024-06-30'
),

period_summary AS (
    SELECT
        tier_period,
        brand_name,
        segment,
        tier_effective_date,
        tier_expiration_date,
        COUNT(DISTINCT week_end_date_key)   AS weeks_in_period,
        SUM(total_rx_count)                 AS total_rx,
        ROUND(AVG(total_rx_count), 1)       AS avg_weekly_rx,
        MAX(total_rx_count)                 AS peak_weekly_rx,
        MIN(total_rx_count)                 AS floor_weekly_rx,
        SUM(total_units)                    AS total_units
    FROM moore_rx
    GROUP BY
        tier_period,
        brand_name,
        segment,
        tier_effective_date,
        tier_expiration_date
)

SELECT
    tier_period,
    brand_name,
    segment,
    tier_effective_date,
    tier_expiration_date,
    weeks_in_period,
    total_rx,
    avg_weekly_rx,
    peak_weekly_rx,
    floor_weekly_rx,
    total_units,
    -- Compare avg weekly Rx to the other period using LAG
    ROUND(
        avg_weekly_rx - LAG(avg_weekly_rx) OVER (
            PARTITION BY brand_name
            ORDER BY tier_effective_date
        ), 1
    )                           AS avg_rx_change_vs_prior_period,
    ROUND(
        100.0 * (avg_weekly_rx - LAG(avg_weekly_rx) OVER (
            PARTITION BY brand_name
            ORDER BY tier_effective_date
        )) / NULLIF(LAG(avg_weekly_rx) OVER (
            PARTITION BY brand_name
            ORDER BY tier_effective_date
        ), 0), 1
    )                           AS avg_rx_pct_change
FROM period_summary
ORDER BY
    brand_name,
    tier_effective_date;


-- ============================================================
-- Query 7: Year-over-year quota attainment comparison
-- Business question: How is each rep performing this fiscal year
--   compared to the same quarter last year? Is the sales force
--   improving, holding steady, or declining year over year?
--   This query uses the prior_year_actual_units stored directly
--   on the fact table to avoid a self-join.
-- Tables: fct_quota_attainment, dim_rep, dim_product
-- Scenario: General attainment data across all reps and products
-- ============================================================

SELECT
    r.rep_name,
    r.district,
    r.current_territory_name,
    p.brand_name,
    qa.fiscal_quarter_key,
    qa.quota_units,
    qa.actual_units,
    qa.attainment_pct,
    qa.prior_year_actual_units,

    -- Year-over-year growth in absolute units
    qa.actual_units - qa.prior_year_actual_units            AS yoy_unit_growth,

    -- Year-over-year growth as a percentage
    ROUND(
        100.0 * (qa.actual_units - qa.prior_year_actual_units)
        / NULLIF(qa.prior_year_actual_units, 0), 1
    )                                                       AS yoy_growth_pct,

    -- Flag reps growing vs declining vs flat
    CASE
        WHEN qa.actual_units > qa.prior_year_actual_units * 1.10 THEN 'Growing (>10%)'
        WHEN qa.actual_units > qa.prior_year_actual_units        THEN 'Growing (<10%)'
        WHEN qa.actual_units = qa.prior_year_actual_units        THEN 'Flat'
        WHEN qa.actual_units > qa.prior_year_actual_units * 0.90 THEN 'Declining (<10%)'
        ELSE                                                          'Declining (>10%)'
    END                                                     AS yoy_trend,

    -- Running total of YoY growth across the district
    SUM(qa.actual_units - qa.prior_year_actual_units) OVER (
        PARTITION BY r.district, qa.product_key, qa.fiscal_quarter_key
        ORDER BY qa.attainment_pct DESC
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )                                                       AS district_cumulative_yoy_growth

FROM fct_quota_attainment qa
JOIN dim_rep r
    ON  qa.rep_key    = r.rep_key
    AND r.is_current  = TRUE
JOIN dim_product p
    ON  qa.product_key   = p.product_key
    AND p.is_current     = TRUE
WHERE qa.fiscal_quarter_key = '2023-08-01'   -- FQ1 FY2024
ORDER BY
    r.district,
    p.brand_name,
    yoy_growth_pct DESC;


-- ============================================================
-- Query 8: Data quality audit — superseded batch investigation
-- Business question: When the Rx vendor sends a corrected file,
--   which rows were affected, what changed, and can we quantify
--   the magnitude of the vendor error? This query uses the audit
--   dimension to surface the superseded batch, compare it to
--   the corrected batch, and calculate the discrepancy.
-- Tables: fct_prescription_weekly, dim_audit, dim_hcp, dim_product
-- Scenario: BATCH-005 (week 2024-03-03) had inflated unit counts.
--           BATCH-006 is the corrected replacement.
-- ============================================================

WITH superseded_rows AS (
    -- Pull all rows loaded by the bad batch
    SELECT
        p.prescription_key,
        p.week_end_date_key,
        p.hcp_key,
        p.product_key,
        p.territory_key,
        p.total_rx_count        AS superseded_rx,
        p.total_units           AS superseded_units,
        a.batch_id              AS superseded_batch,
        a.dq_flag,
        a.dq_notes
    FROM fct_prescription_weekly p
    JOIN dim_audit a
        ON p.audit_key = a.audit_key
    WHERE a.batch_id = 'BATCH-005' AND p.week_end_date_key = '2024-03-03'
),

corrected_rows AS (
    -- Pull the corrected replacement rows for the same week
    SELECT
        p.hcp_key,
        p.product_key,
        p.territory_key,
        p.total_rx_count        AS corrected_rx,
        p.total_units           AS corrected_units,
        a.batch_id              AS corrected_batch
    FROM fct_prescription_weekly p
    JOIN dim_audit a
        ON p.audit_key = a.audit_key
    WHERE a.batch_id = 'BATCH-006' AND p.week_end_date_key = '2024-03-10'
)

SELECT
    s.week_end_date_key,
    h.full_name                 AS hcp_name,
    h.segment,
    pr.brand_name,
    s.superseded_batch,
    c.corrected_batch,
    s.dq_notes,
    s.superseded_rx,
    c.corrected_rx,
    c.corrected_rx - s.superseded_rx            AS rx_discrepancy,
    s.superseded_units,
    c.corrected_units,
    c.corrected_units - s.superseded_units      AS units_discrepancy,
    -- Magnitude of error as a percentage
    ROUND(
        100.0 * (s.superseded_units - c.corrected_units)
        / NULLIF(c.corrected_units, 0), 1
    )                                           AS pct_inflation
FROM superseded_rows s
JOIN corrected_rows c
    ON  s.hcp_key       = c.hcp_key
    AND s.product_key   = c.product_key
    AND s.territory_key = c.territory_key
JOIN dim_hcp h
    ON  s.hcp_key    = h.hcp_key
    AND h.is_current = TRUE
JOIN dim_product pr
    ON  s.product_key   = pr.product_key
    AND pr.is_current   = TRUE
ORDER BY
    ABS(c.corrected_units - s.superseded_units) DESC;


-- ============================================================
-- Query 9: Market share trend by territory
-- Business question: How is our brand's market share moving
--   month over month across territories? Which territories are
--   gaining share and which are losing it? This query uses the
--   aggregate fact table for performance — avoiding a full scan
--   of the atomic prescription table for a district-level summary.
-- Tables: fct_prescription_territory_monthly, dim_territory_rollup,
--         dim_product, dim_month
-- Scenario: General market share data across all territories
-- ============================================================

WITH monthly_share AS (
    SELECT
        m.month_name,
        m.fiscal_quarter,
        m.fiscal_year,
        t.territory_name,
        t.district,
        t.region,
        p.brand_name,
        f.new_rx_count,
        f.total_rx_count,
        f.brand_units,
        f.total_market_units,
        -- Recalculate market share from additive components
        ROUND(
            100.0 * f.brand_units / NULLIF(f.total_market_units, 0), 2
        )                       AS market_share_pct,
        f.month_key
    FROM fct_prescription_territory_monthly f
    JOIN dim_territory_rollup t
        ON f.territory_rollup_key = t.territory_rollup_key
    JOIN dim_product p
        ON  f.product_key   = p.product_key
        AND p.is_current    = TRUE
    JOIN dim_month m
        ON f.month_key = m.month_key
    WHERE m.fiscal_year = 2024
),

share_with_trend AS (
    SELECT
        month_name,
        fiscal_quarter,
        fiscal_year,
        territory_name,
        district,
        region,
        brand_name,
        total_rx_count,
        brand_units,
        total_market_units,
        market_share_pct,
        month_key,

        -- Prior month share using LAG
        LAG(market_share_pct) OVER (
            PARTITION BY territory_name, brand_name
            ORDER BY month_key
        )                       AS prior_month_share,

        -- Month-over-month share change
        market_share_pct - LAG(market_share_pct) OVER (
            PARTITION BY territory_name, brand_name
            ORDER BY month_key
        )                       AS mom_share_change,

        -- 3-month rolling average share
        ROUND(
            AVG(market_share_pct) OVER (
                PARTITION BY territory_name, brand_name
                ORDER BY month_key
                ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
            ), 2
        )                       AS rolling_3mo_avg_share
    FROM monthly_share
)

SELECT
    fiscal_year,
    fiscal_quarter,
    month_name,
    territory_name,
    district,
    region,
    brand_name,
    total_rx_count,
    brand_units,
    total_market_units,
    market_share_pct,
    prior_month_share,
    mom_share_change,
    rolling_3mo_avg_share,
    CASE
        WHEN mom_share_change >  1.0 THEN 'Gaining share'
        WHEN mom_share_change < -1.0 THEN 'Losing share'
        ELSE                              'Holding share'
    END                         AS share_trend,
    -- Rank territories by market share within district this month
    DENSE_RANK() OVER (
        PARTITION BY district, brand_name, month_key
        ORDER BY market_share_pct DESC
    )                           AS territory_rank_in_district
FROM share_with_trend
ORDER BY
    brand_name,
    district,
    territory_name,
    month_key;


-- ============================================================
-- Query 10: HCP decile ranking writeback validation
-- Business question: Are the decile rankings stored in dim_hcp
--   actually consistent with observed prescription volume? This
--   query recalculates decile rankings from actual Rx data using
--   NTILE(10) and compares them to the stored decile_rank attribute,
--   surfacing any HCPs whose stored rank no longer reflects their
--   actual prescribing behavior.
-- Tables: fct_prescription_weekly, dim_hcp, dim_product
-- Scenario: General HCP data — validates the banding strategy
-- ============================================================

WITH hcp_total_rx AS (
    -- Aggregate total prescriptions per HCP per product over the full dataset
    SELECT
        p.hcp_key,
        p.product_key,
        SUM(p.total_rx_count)   AS lifetime_rx_count
    FROM fct_prescription_weekly p
    GROUP BY p.hcp_key, p.product_key
),

hcp_deciles AS (
    SELECT
        h.hcp_key,
        h.full_name,
        h.specialty,
        h.segment,
        h.decile_rank           AS stored_decile,
        pr.brand_name,
        t.lifetime_rx_count,
        -- Recalculate decile from actual data
        NTILE(10) OVER (
            PARTITION BY t.product_key
            ORDER BY t.lifetime_rx_count DESC
        )                       AS calculated_decile
    FROM hcp_total_rx t
    JOIN dim_hcp h
        ON  t.hcp_key    = h.hcp_key
        AND h.is_current = TRUE
    JOIN dim_product pr
        ON  t.product_key   = pr.product_key
        AND pr.is_current   = TRUE
)

SELECT
    full_name,
    specialty,
    segment,
    brand_name,
    lifetime_rx_count,
    stored_decile,
    calculated_decile,
    stored_decile - calculated_decile       AS decile_drift,
    CASE
        WHEN stored_decile = calculated_decile          THEN 'Accurate'
        WHEN ABS(stored_decile - calculated_decile) = 1 THEN 'Minor drift'
        ELSE                                                 'Needs refresh'
    END                                     AS decile_status
FROM hcp_deciles
WHERE stored_decile != calculated_decile   -- only show mismatches
ORDER BY
    ABS(stored_decile - calculated_decile) DESC,
    lifetime_rx_count DESC;


-- ============================================================
-- Query 11: Product indication expansion impact
-- Business question: After Humira received FDA approval for a
--   second indication, did prescription volume increase? This
--   query uses the Type 2 SCD history on dim_product to split
--   Humira prescriptions into pre-expansion and post-expansion
--   periods and compares average weekly volume between them.
-- Tables: fct_prescription_weekly, dim_product, dim_hcp, dim_date
-- Scenario: Humira indication expansion on 2023-11-01
--           (product_key=2 original, product_key=3 expanded)
-- ============================================================

WITH humira_keys AS (
    SELECT
        product_key,
        product_code,
        indication,
        effective_date          AS indication_effective_date
    FROM dim_product
    WHERE brand_name = 'Humira'
      AND is_current = TRUE
),

-- Aggregate on integer keys only -- no strings enter the sort
pre_agg AS (
    SELECT
        p.hcp_key,
        p.product_key,
        SUM(p.total_rx_count)                   AS total_rx,
        SUM(p.new_rx_count)                     AS total_new_rx,
        COUNT(DISTINCT p.week_end_date_key)      AS weeks_of_data,
        -- Carry the per-hcp weekly average forward so the summary
        -- level AVG is taken over HCPs, not over raw weekly rows
        SUM(p.total_rx_count) * 1.0
            / NULLIF(COUNT(DISTINCT p.week_end_date_key), 0)
                                                AS avg_weekly_rx
    FROM fct_prescription_weekly p
    WHERE p.product_key IN (SELECT product_key FROM humira_keys)
    GROUP BY p.hcp_key, p.product_key
),

period_summary AS (
    SELECT
        CASE
            WHEN k.product_code = 'PRD-HUM-001' THEN 'Pre-expansion'
            WHEN k.product_code = 'PRD-HUM-002' THEN 'Post-expansion'
        END                                     AS indication_period,
        k.indication,
        k.indication_effective_date,
        h.specialty,
        COUNT(DISTINCT a.hcp_key)               AS unique_prescribers,
        -- SUM is correct here: each hcp/product row already holds
        -- that HCP's week count, so summing gives total across HCPs
        SUM(a.weeks_of_data)                    AS weeks_of_data,
        SUM(a.total_rx)                         AS total_rx,
        SUM(a.total_new_rx)                     AS total_new_rx,
        -- Average of per-HCP weekly averages -- semantically equivalent
        -- to the original avg_weekly_rx_per_hcp
        ROUND(AVG(a.avg_weekly_rx), 1)          AS avg_weekly_rx_per_hcp
    FROM pre_agg a
    JOIN humira_keys k  ON  a.product_key   = k.product_key
    JOIN dim_hcp h      ON  a.hcp_key       = h.hcp_key
                        AND h.is_current    = TRUE
    GROUP BY
        indication_period,
        k.indication,
        k.indication_effective_date,
        h.specialty
)

SELECT
    indication_period,
    indication,
    indication_effective_date,
    specialty,
    unique_prescribers,
    weeks_of_data,
    total_rx,
    avg_weekly_rx_per_hcp,
    total_new_rx,
    ROUND(
        avg_weekly_rx_per_hcp - LAG(avg_weekly_rx_per_hcp) OVER (
            PARTITION BY specialty
            ORDER BY indication_effective_date
        ), 1
    )                                           AS avg_rx_change_vs_prior,
    ROUND(
        100.0 * (avg_weekly_rx_per_hcp - LAG(avg_weekly_rx_per_hcp) OVER (
            PARTITION BY specialty
            ORDER BY indication_effective_date
        )) / NULLIF(LAG(avg_weekly_rx_per_hcp) OVER (
            PARTITION BY specialty
            ORDER BY indication_effective_date
        ), 0), 1
    )                                           AS avg_rx_pct_change
FROM period_summary
ORDER BY
    specialty,
    indication_effective_date;
