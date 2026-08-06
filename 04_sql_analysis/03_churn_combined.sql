-- ===========================================================================
-- 03 — Combined churn list (prepaid + postpaid)
-- ===========================================================================
-- Business question : Which services have churned, across both product types?
-- Requirement       : BR-01, FR-01, FR-02, FR-04
-- Decisions applied : D1 (churn definition), D2 (both types, equal weight),
--                     D4 (prepaid churn dated at last activity — see below)
-- Author            : Kurt
-- Dialect           : SQLite
-- As-at date        : 2025-06-30
--
-- Churn is measured two different ways because the two products behave
-- differently. Postpaid cancellation is a contractual event with a recorded
-- date. Prepaid departure is silent and must be derived. This query unifies
-- both into a single list with a churn_method column so either population
-- can be audited separately.
-- ===========================================================================

WITH last_activity AS (
    -- One row per service: the last date it did ANYTHING (recharged or used).
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
),

churn AS (
    -- PREPAID — derived under D1.
    -- churn_date = last activity date (Decision D4), NOT last activity + 60.
    SELECT
        a.service_id,
        'Prepaid'                AS plan_type,
        a.last_activity_date     AS churn_date,
        'Derived (D1)'           AS churn_method
    FROM last_activity a
    JOIN services s ON a.service_id = s.service_id
    JOIN plans    p ON s.plan_id    = p.plan_id
    WHERE p.plan_type = 'Prepaid'
      AND julianday('2025-06-30') - julianday(a.last_activity_date) >= 60

    UNION ALL

    -- POSTPAID — recorded contractual event.
    SELECT
        s.service_id,
        'Postpaid'                 AS plan_type,
        s.deactivation_date        AS churn_date,
        'Recorded (deactivation)'  AS churn_method
    FROM services s
    JOIN plans p ON s.plan_id = p.plan_id
    WHERE p.plan_type = 'Postpaid'
      AND s.deactivation_date IS NOT NULL
)

SELECT *
FROM churn
ORDER BY churn_date;

-- Result (40-customer seed): 19 churned services — 12 postpaid, 7 prepaid.
--
-- By quarter:
--   2024-Q2   Postpaid 1
--   2024-Q3   Postpaid 4
--   2024-Q4   Postpaid 2   Prepaid 1
--   2025-Q1   Postpaid 3   Prepaid 4
--   2025-Q2   Postpaid 2   Prepaid 2

-- ===========================================================================
-- DECISION D4 — how a prepaid churn event is dated
-- ===========================================================================
-- The 60-day rule tells you a customer HAS left, but not WHEN. Two candidate
-- dates exist, and the choice materially changes the churn trend.
--
--   Option A (CHOSEN): date the churn at the LAST ACTIVITY date — the day
--       the customer actually went quiet.
--   Option B (rejected): date it at last activity + 60 days — the day the
--       rule was satisfied and the loss was confirmed.
--
-- Rationale for A. Postpaid churn is dated on the day the customer actually
-- left. Dating prepaid churn 60 days later would mean the two columns do not
-- mean the same thing, and every prepaid-vs-postpaid trend comparison would
-- be misaligned by two months — smearing seasonality and making prepaid churn
-- look like it started later than it did. Under Option B this dataset shows
-- no prepaid churn at all before February 2025, which is an artefact of the
-- dating rule, not a fact about the business. Decision D2 requires the two
-- product types to be reported side by side, and that is only meaningful if
-- both are measured on the same clock.
--
-- Cost accepted. Because a churn cannot be confirmed until 60 days have
-- elapsed, the most recent two months are structurally incomplete — a
-- customer who went quiet last month may yet return. Those months must be
-- labelled PROVISIONAL wherever prepaid churn is reported (BRD constraint C1).
--
-- Note on this dataset: no prepaid service currently sits in the 30-59 day
-- unresolved window, so the blind spot is empty here. That is a property of
-- this data extract, not of the method. The caveat still applies.
--
-- Option B is the more natural choice for a finance-driven base
-- reconciliation, where what matters is when a service was removed from the
-- billed base rather than when the customer stopped caring. If this analysis
-- were feeding a revenue forecast rather than a retention programme, the
-- decision could reasonably go the other way.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- CONTROL CHECKS
-- ---------------------------------------------------------------------------
-- 1. Total churned must equal prepaid churned + postpaid churned: 7 + 12 = 19.
-- 2. No service may appear twice — the two branches are mutually exclusive
--    by plan_type:
--      SELECT service_id, COUNT(*) FROM ( ...churn... )
--      GROUP BY service_id HAVING COUNT(*) > 1;   -- expect zero rows
-- 3. Churned services must not exceed the base: 19 of 51 total services.
-- 4. Every churn_date must fall inside the data window (2024-01-01 to
--    2025-06-30).
