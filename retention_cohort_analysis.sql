-- This query calculates Rolling (Cumulative) Retention for Uniswap V3.
-- This is the stable version of the query, using only the raw activation_month date object
-- to ensure compatibility with all SQL engines, despite producing unformatted labels.

-- 1. IDENTIFY USER ACTIVATION MONTH (The Cohort)
WITH user_activation AS (
    SELECT
        tx_from AS user_address,
        MIN(DATE_TRUNC('month', block_time)) AS activation_month
    FROM
        dex.trades
    WHERE
        project = 'uniswap'
        AND version = '3'
    GROUP BY 1
),

-- 2. DETERMINE MONTHLY ACTIVITY
monthly_activity AS (
    SELECT
        tx_from AS user_address,
        DATE_TRUNC('month', block_time) AS activity_month
    FROM
        dex.trades
    WHERE
        project = 'uniswap'
        AND version = '3'
    GROUP BY 1, 2
),

-- 3. JOIN AND CALCULATE THE TIME DIFFERENCE (Retention Period)
retention_data AS (
    SELECT
        a.user_address,
        a.activation_month,
        -- Calculate the difference in months between activity and activation
        EXTRACT(YEAR FROM m.activity_month) * 12 + EXTRACT(MONTH FROM m.activity_month)
        - (EXTRACT(YEAR FROM a.activation_month) * 12 + EXTRACT(MONTH FROM a.activation_month)) AS cohort_period
    FROM
        user_activation a
    INNER JOIN
        monthly_activity m ON a.user_address = m.user_address
    WHERE
        m.activity_month >= a.activation_month
),

-- 4. CREATE ACTIVITY FLAGS (A wide table to check cumulative retention)
user_activity_flags AS (
    SELECT
        a.activation_month,
        a.user_address,
        -- Flag if the user was active in period N (1 if yes, 0 if no)
        MAX(CASE WHEN r.cohort_period = 1 THEN 1 ELSE 0 END) AS active_m1,
        MAX(CASE WHEN r.cohort_period = 2 THEN 1 ELSE 0 END) AS active_m2,
        MAX(CASE WHEN r.cohort_period = 3 THEN 1 ELSE 0 END) AS active_m3,
        MAX(CASE WHEN r.cohort_period = 4 THEN 1 ELSE 0 END) AS active_m4,
        MAX(CASE WHEN r.cohort_period = 5 THEN 1 ELSE 0 END) AS active_m5,
        MAX(CASE WHEN r.cohort_period = 6 THEN 1 ELSE 0 END) AS active_m6
    FROM
        user_activation a
    -- LEFT JOIN is essential: we must keep all initial cohort users (from M0)
    LEFT JOIN
        retention_data r ON a.user_address = r.user_address AND a.activation_month = r.activation_month AND r.cohort_period > 0
    GROUP BY 1, 2
),

-- 5. PIVOT AND COUNT (Calculating Rolling Retention Count)
final_pivot AS (
    SELECT
        activation_month,
        -- M0 is the fixed denominator: the count of all users in the cohort
        COUNT(user_address) AS "M0_Active",

        -- M1 Rolling: Active in M1
        COUNT(CASE WHEN active_m1 = 1 THEN user_address END) AS "M1_Active",

        -- M2 Rolling: Active in M1 AND M2
        COUNT(CASE WHEN active_m1 = 1 AND active_m2 = 1 THEN user_address END) AS "M2_Active",

        -- M3 Rolling: Active in M1 AND M2 AND M3
        COUNT(CASE WHEN active_m1 = 1 AND active_m2 = 1 AND active_m3 = 1 THEN user_address END) AS "M3_Active",

        -- M4 Rolling: Active in M1 AND M2 AND M3 AND M4
        COUNT(CASE WHEN active_m1 = 1 AND active_m2 = 1 AND active_m3 = 1 AND active_m4 = 1 THEN user_address END) AS "M4_Active",

        -- M5 Rolling: Active in M1 AND M2 AND M3 AND M4 AND M5
        COUNT(CASE WHEN active_m1 = 1 AND active_m2 = 1 AND active_m3 = 1 AND active_m4 = 1 AND active_m5 = 1 THEN user_address END) AS "M5_Active",

        -- M6 Rolling: Active in M1 AND M2 AND M3 AND M4 AND M5 AND M6
        COUNT(CASE WHEN active_m1 = 1 AND active_m2 = 1 AND active_m3 = 1 AND active_m4 = 1 AND active_m5 = 1 AND active_m6 = 1 THEN user_address END) AS "M6_Active"
    FROM
        user_activity_flags
    WHERE
        -- Filter out tiny cohorts for M0 denominator
        activation_month IN (SELECT activation_month FROM user_activity_flags GROUP BY 1 HAVING COUNT(user_address) > 500)
    GROUP BY 1
),

-- 6. CALCULATE PERCENTAGE RETENTION (Intermediate Wide Format for Percentage)
cohort_data AS (
    SELECT
        activation_month,
        "M0_Active" AS initial_cohort_size,
        ROUND("M0_Active" * 100.0 / "M0_Active", 2) AS "M0_Retention_pct", -- 100.00
        ROUND("M1_Active" * 100.0 / "M0_Active", 2) AS "M1_Retention_pct",
        ROUND("M2_Active" * 100.0 / "M0_Active", 2) AS "M2_Retention_pct",
        ROUND("M3_Active" * 100.0 / "M0_Active", 2) AS "M3_Retention_pct",
        ROUND("M4_Active" * 100.0 / "M0_Active", 2) AS "M4_Retention_pct",
        ROUND("M5_Active" * 100.0 / "M0_Active", 2) AS "M5_Retention_pct",
        ROUND("M6_Active" * 100.0 / "M0_Active", 2) AS "M6_Retention_pct"
    FROM
        final_pivot
),

-- 7. UNPIVOT THE DATA (LONG FORMAT)
unpivoted_retention AS (
    SELECT activation_month, 0 AS retention_month_index, 'M0' AS retention_label, "M0_Retention_pct" AS retention_pct FROM cohort_data
    UNION ALL
    SELECT activation_month, 1 AS retention_month_index, 'M1' AS retention_label, "M1_Retention_pct" AS retention_pct FROM cohort_data
    UNION ALL
    SELECT activation_month, 2 AS retention_month_index, 'M2' AS retention_label, "M2_Retention_pct" AS retention_pct FROM cohort_data
    UNION ALL
    SELECT activation_month, 3 AS retention_month_index, 'M3' AS retention_label, "M3_Retention_pct" AS retention_pct FROM cohort_data
    UNION ALL
    SELECT activation_month, 4 AS retention_month_index, 'M4' AS retention_label, "M4_Retention_pct" AS retention_pct FROM cohort_data
    UNION ALL
    SELECT activation_month, 5 AS retention_month_index, 'M5' AS retention_label, "M5_Retention_pct" AS retention_pct FROM cohort_data
    UNION ALL
    SELECT activation_month, 6 AS retention_month_index, 'M6' AS retention_label, "M6_Retention_pct" AS retention_pct FROM cohort_data
)

-- 8. FINAL SELECT: The required long-format for the chart.
SELECT
    activation_month,
    retention_month_index,
    retention_label,
    retention_pct
FROM
    unpivoted_retention
WHERE
    retention_pct IS NOT NULL
    AND retention_month_index > 0
ORDER BY
    activation_month,
    retention_month_index;
