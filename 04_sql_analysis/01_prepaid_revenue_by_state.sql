-- ===========================================================================
-- 01 — Total prepaid revenue by state
-- ===========================================================================
-- Business question : Which states generate the most prepaid revenue?
-- Requirement       : BR-02 (segment by state), BR-04 (revenue by stream)
-- Decision applied  : D2 — prepaid reported separately from postpaid
-- Author            : Kurt
-- Dialect           : SQLite
-- ===========================================================================

SELECT
    c.state,
    ROUND(SUM(r.amount_aud), 2) AS total_prepaid_revenue_aud
FROM recharges r
JOIN services  s ON r.service_id  = s.service_id
JOIN customers c ON s.customer_id = c.customer_id
GROUP BY c.state
ORDER BY total_prepaid_revenue_aud DESC;

-- Result (40-customer seed dataset)
--   NSW   2630.00
--   QLD   2320.00
--   VIC   1030.00
--   Total 5980.00

-- ---------------------------------------------------------------------------
-- RECONCILIATION
-- ---------------------------------------------------------------------------
-- Any aggregate computed across joins must tie back to the source table.
-- If this total were HIGHER than the query above, a join has fanned out and
-- duplicated revenue. If LOWER, rows were dropped. Both are silent failures.

SELECT ROUND(SUM(amount_aud), 2) AS control_total_aud
FROM recharges;
-- Returns 5980.00 — matches. Joins neither duplicated nor dropped revenue.

-- ---------------------------------------------------------------------------
-- NOTES ON INTERPRETATION
-- ---------------------------------------------------------------------------
-- No filter on plan_type is applied because only prepaid services generate
-- recharge records. This was verified, but it relies on a property of the
-- data rather than one enforced by the schema. In a production repo this
-- query would carry an explicit `WHERE p.plan_type = 'Prepaid'` guard so an
-- upstream change could not silently corrupt the result.
--
-- CAUTION — do not read a story into the state ranking on the seed dataset.
-- Decomposing revenue into (services x recharges per service x amount) shows
-- the gap is driven mainly by the number of prepaid services per state:
-- NSW 8, QLD 6, VIC 4. With denominators that small, per-state differences in
-- average recharge and churn are sampling noise, not behaviour. Re-running the
-- same query at 5,000 customers gives near-identical revenue per service
-- across all three states (NSW $351.54, VIC $354.39, QLD $348.63), and the
-- revenue ranking collapses to base size alone.
--
-- Lesson: a technically correct query is not a finding. Always report the
-- denominator, and be able to name a mechanism before claiming a difference
-- is real.
