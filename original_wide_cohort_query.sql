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
        m.activity_month,
        EXTRACT(YEAR FROM m.activity_month) * 12 + EXTRACT(MONTH FROM m.activity_month)
        - (EXTRACT(YEAR FROM a.activation_month) * 12 + EXTRACT(MONTH FROM a.activation_month)) AS cohort_period
    FROM
        user_activation a
    INNER JOIN
        monthly_activity m ON a.user_address = m.user_address
    WHERE
        m.activity_month >= a.activation_month
),

-- 4. PIVOT AND COUNT (The Final Step)
final_pivot AS (
    SELECT
        activation_month,
        -- Total users in the starting cohort (Period 0)
        COUNT(DISTINCT user_address) AS total_users_start,
        -- Count how many of the starting users were active in each subsequent period (M0, M1, M2...)
        COUNT(DISTINCT CASE WHEN cohort_period = 0 THEN user_address ELSE NULL END) AS "M0_Active",
        COUNT(DISTINCT CASE WHEN cohort_period = 1 THEN user_address ELSE NULL END) AS "M1_Active",
        COUNT(DISTINCT CASE WHEN cohort_period = 2 THEN user_address ELSE NULL END) AS "M2_Active",
        COUNT(DISTINCT CASE WHEN cohort_period = 3 THEN user_address ELSE NULL END) AS "M3_Active",
        COUNT(DISTINCT CASE WHEN cohort_period = 4 THEN user_address ELSE NULL END) AS "M4_Active",
        COUNT(DISTINCT CASE WHEN cohort_period = 5 THEN user_address ELSE NULL END) AS "M5_Active",
        COUNT(DISTINCT CASE WHEN cohort_period = 6 THEN user_address ELSE NULL END) AS "M6_Active"
    FROM
        retention_data
    GROUP BY 1
    ORDER BY 1 DESC
)

-- 5. CALCULATE PERCENTAGE RETENTION (The Output)
SELECT
    activation_month,
    total_users_start,
    -- Retention Rate for each month (M0/M0, M1/M0, M2/M0, etc.)
    ROUND("M0_Active" * 100.0 / total_users_start, 2) AS "M0_Retention_pct", -- Renamed to 'pct' instead of '%' for cleaner use later
    ROUND("M1_Active" * 100.0 / total_users_start, 2) AS "M1_Retention_pct",
    ROUND("M2_Active" * 100.0 / total_users_start, 2) AS "M2_Retention_pct",
    ROUND("M3_Active" * 100.0 / total_users_start, 2) AS "M3_Retention_pct",
    ROUND("M4_Active" * 100.0 / total_users_start, 2) AS "M4_Retention_pct",
    ROUND("M5_Active" * 100.0 / total_users_start, 2) AS "M5_Retention_pct",
    ROUND("M6_Active" * 100.0 / total_users_start, 2) AS "M6_Retention_pct"
FROM
    final_pivot
LIMIT 100
