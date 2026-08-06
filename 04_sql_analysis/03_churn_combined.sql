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

SELECT
    substr(churn_date, 1, 7) AS churn_month,
    plan_type,
    COUNT(*) AS churned_services
FROM churn
GROUP BY churn_month, plan_type
ORDER BY churn_month, plan_type;

