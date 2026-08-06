-- ===========================================================================
-- 02 — Prepaid churn, derived under Decision D1
-- ===========================================================================
-- Business question : Which prepaid services have churned?
-- Requirement       : BR-01 (single reproducible churn definition), FR-01
-- Decision applied  : D1 — prepaid churn = 60 consecutive days with no
--                     recharge AND no billable usage
-- Author            : Kurt
-- Dialect           : SQLite
-- As-at date        : 2025-06-30 (last day of the data window)
--
-- WHY THIS QUERY IS NECESSARY
-- ---------------------------------------------------------------------------
-- Prepaid services carry no churn flag. A churned prepaid service still shows
-- service_status = 'Active' with a NULL deactivation_date, because there is no
-- contract to cancel — the customer simply stops showing up. Churn must
-- therefore be DERIVED from behaviour, not read from a column.
-- ===========================================================================

WITH last_activity AS (
    -- Stack recharges and usage into one list of "things this service did",
    -- then take the most recent. Both streams matter: D1 requires 60 days
    -- with no recharge AND no billable usage.
    SELECT service_id, MAX(activity_date) AS last_activity_date
    FROM (
        SELECT service_id, recharge_date AS activity_date
        FROM recharges

        UNION ALL

        SELECT service_id, usage_month
        FROM usage_monthly
        WHERE data_gb > 0 OR voice_minutes > 0
    )
    GROUP BY service_id
)
SELECT
    a.service_id,
    a.last_activity_date,
    CAST(julianday('2025-06-30') - julianday(a.last_activity_date) AS INT)
        AS days_inactive
FROM last_activity a
JOIN services s ON a.service_id = s.service_id
JOIN plans    p ON s.plan_id    = p.plan_id
WHERE p.plan_type = 'Prepaid'
  AND julianday('2025-06-30') - julianday(a.last_activity_date) >= 60
ORDER BY days_inactive DESC;

-- Result (40-customer seed): 7 churned prepaid services of 18 total
--   service_id  last_activity  days_inactive
--   16          2024-12-14     198
--   6           2025-01-03     178
--   24          2025-02-01     149
--   13          2025-03-05     117
--   41          2025-03-21     101
--   10          2025-04-01      90
--   50          2025-04-01      90

-- ===========================================================================
-- TWO WRONG APPROACHES, AND WHY THEY FAIL
-- ===========================================================================
-- Both of these were written and tested before arriving at the query above.
-- They are recorded because the failures explain the design.
--
-- WRONG 1 — "60 days since last RECHARGE", ignoring usage entirely.
--
--     SELECT service_id, MAX(recharge_date)
--     FROM recharges GROUP BY service_id
--     HAVING julianday('2025-06-30') - julianday(MAX(recharge_date)) >= 60;
--
--   Returns 7 here by coincidence, but is unsafe. It cannot distinguish a
--   leaver from a SLEEPER — a customer who pauses recharging for 60+ days
--   while still using the service, then returns. This dataset contains 3
--   such services (25, 34, 40); service 34 went 64 days between top-ups
--   while using 8.91 GB and 184 voice minutes, then resumed. Applied at any
--   point mid-window, this rule writes off ~1 in 6 prepaid services who
--   never left, and triggers win-back spend on active customers.
--
-- WRONG 2 — "60 days since last recharge AND no usage at all afterwards".
--
--   Returns only 5. It drops services 24 and 50, which recorded a final
--   month of usage AFTER their last top-up (service 24: 2.75 GB in Feb
--   2025) and then went permanently silent. These are genuine leavers
--   burning off prepaid credit on the way out — the most normal exit
--   pattern there is. The rule was too strict because it asked "was there
--   ever usage after the last recharge" rather than "have 60 consecutive
--   days passed with neither".
--
-- CORRECT — measure 60 days from the last date the service did ANYTHING.
--   This treats recharge and usage as two signals of the same underlying
--   thing (is this customer still here), which is what D1 actually says.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- CONTROL CHECKS
-- ---------------------------------------------------------------------------
-- 1. Sleepers must NOT appear in the result. Services 25, 34 and 40 each
--    have a 60+ day recharge gap but continued billable usage through it,
--    and later resumed recharging. None of them is churned.
--    Confirm 25, 34 and 40 are absent from the 7 rows returned.
--
--    (Do not confuse service 40 with service 50. Service 50 IS churned —
--     last activity 2025-04-01, 90 days inactive.)
--
-- 2. Churned count must not exceed the prepaid base.
--    SELECT COUNT(DISTINCT s.service_id) FROM services s
--    JOIN plans p ON s.plan_id = p.plan_id WHERE p.plan_type = 'Prepaid';
--    Returns 18. Churned = 7, i.e. 38.9% cumulative over the 18-month window.
--    Consistent with the FY25 prepaid monthly churn rate of ~3.1%.

-- ---------------------------------------------------------------------------
-- LIMITATIONS TO DISCLOSE
-- ---------------------------------------------------------------------------
-- * 60-day arrears. Churn cannot be confirmed until 60 days have passed, so
--   the final two months of any prepaid churn series are provisional and must
--   be labelled as such (BRD constraint C1).
-- * usage_monthly is monthly, not daily. Last activity is therefore accurate
--   to the month, not the day, which can shift a churn date by up to ~30 days.
--   Acceptable for monthly reporting; would need daily CDR data for anything
--   finer.
-- * n = 18 prepaid services in the seed dataset. Percentages here are
--   illustrative. Re-run against the 5,000-customer dataset before quoting
--   any rate as a finding.
