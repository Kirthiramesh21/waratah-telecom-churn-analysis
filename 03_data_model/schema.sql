-- ===========================================================================
-- Waratah Telecom - Subscriber Churn & ARPU Recovery Analysis
-- Analytical schema (SQLite dialect)
-- ===========================================================================
-- Grain            : SERVICE (a customer may hold multiple services)
-- Date storage     : TEXT in ISO 'YYYY-MM-DD' format (SQLite has no DATE type)
-- Coverage         : 2024-01-01 to 2025-06-30 (FY25 + 6 months lead-in)
-- Load order       : run this file first, then seed_data.sql
--
-- DELIBERATE DESIGN CHOICES (interview talking points):
--   1. There is NO churn flag on prepaid services. Prepaid churn must be
--      DERIVED from gaps between recharge dates per Decision D1
--      (60 consecutive days with no recharge and no billable usage).
--      Real prepaid systems work exactly this way - nobody tells you a
--      prepaid customer left, they just stop showing up.
--   2. Revenue is split across TWO tables: recharges (prepaid) and
--      invoices (postpaid). Blended ARPU requires a UNION ALL, which mirrors
--      the real-world problem of unifying two billing stacks.
--   3. Postpaid churn IS explicit - deactivation_date on the service record -
--      because a postpaid cancellation is a contractual event.
-- ===========================================================================

PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS campaign_contacts;
DROP TABLE IF EXISTS campaigns;
DROP TABLE IF EXISTS support_tickets;
DROP TABLE IF EXISTS usage_monthly;
DROP TABLE IF EXISTS invoices;
DROP TABLE IF EXISTS recharges;
DROP TABLE IF EXISTS services;
DROP TABLE IF EXISTS plans;
DROP TABLE IF EXISTS customers;

-- ---------------------------------------------------------------------------
-- 1. customers - one row per billing account holder
-- ---------------------------------------------------------------------------
CREATE TABLE customers (
    customer_id          INTEGER PRIMARY KEY,
    first_name           TEXT    NOT NULL,
    last_name            TEXT    NOT NULL,
    date_of_birth        TEXT,                       -- 'YYYY-MM-DD'
    state                TEXT    NOT NULL,           -- NSW | VIC | QLD
    city                 TEXT,
    postcode             TEXT,
    customer_segment     TEXT    NOT NULL,           -- Consumer | SMB
    acquisition_channel  TEXT,                       -- Online, Retail Store, ...
    acquisition_date     TEXT    NOT NULL,           -- 'YYYY-MM-DD'
    credit_risk_band     TEXT,                       -- Low | Medium | High Risk
    CHECK (state IN ('NSW','VIC','QLD')),
    CHECK (customer_segment IN ('Consumer','SMB'))
);

-- ---------------------------------------------------------------------------
-- 2. plans - product catalogue (slowly changing in reality; static here)
-- ---------------------------------------------------------------------------
CREATE TABLE plans (
    plan_id             INTEGER PRIMARY KEY,
    plan_name           TEXT    NOT NULL,
    plan_type           TEXT    NOT NULL,            -- Prepaid | Postpaid
    monthly_price_aud   REAL    NOT NULL,
    included_data_gb    REAL,
    contract_months     INTEGER NOT NULL DEFAULT 0,  -- 0 = no lock-in (prepaid)
    plan_family         TEXT,
    is_active           INTEGER NOT NULL DEFAULT 1,  -- 0/1 boolean
    CHECK (plan_type IN ('Prepaid','Postpaid'))
);

-- ---------------------------------------------------------------------------
-- 3. services - THE FACT SPINE. One row per mobile service (SIM).
--    deactivation_date is populated for POSTPAID cancellations only.
--    Prepaid churn is derived downstream - see Decision D1.
-- ---------------------------------------------------------------------------
CREATE TABLE services (
    service_id          INTEGER PRIMARY KEY,
    customer_id         INTEGER NOT NULL,
    plan_id             INTEGER NOT NULL,
    msisdn              TEXT,                        -- mobile number
    activation_date     TEXT    NOT NULL,
    deactivation_date   TEXT,                        -- NULL unless postpaid churn
    service_status      TEXT    NOT NULL,            -- Active | Deactivated | Suspended
    device_type         TEXT,
    is_byo              INTEGER NOT NULL DEFAULT 0,
    port_in_flag        INTEGER NOT NULL DEFAULT 0,  -- came from another carrier
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    FOREIGN KEY (plan_id)     REFERENCES plans(plan_id),
    CHECK (service_status IN ('Active','Deactivated','Suspended'))
);

-- ---------------------------------------------------------------------------
-- 4. recharges - PREPAID revenue events. Irregular, event-driven.
--    The gap between consecutive recharge_date values is the raw material
--    for the D1 churn rule. Window functions (LAG / LEAD) live here.
-- ---------------------------------------------------------------------------
CREATE TABLE recharges (
    recharge_id         INTEGER PRIMARY KEY,
    service_id          INTEGER NOT NULL,
    recharge_date       TEXT    NOT NULL,
    amount_aud          REAL    NOT NULL,
    recharge_channel    TEXT,                        -- App, Website, Retail...
    recharge_type       TEXT,                        -- Auto | Manual
    FOREIGN KEY (service_id) REFERENCES services(service_id)
);

-- ---------------------------------------------------------------------------
-- 5. invoices - POSTPAID revenue. Regular monthly cadence.
--    total_amount_aud = plan_charge_aud + excess_usage_aud - discount_aud
-- ---------------------------------------------------------------------------
CREATE TABLE invoices (
    invoice_id          INTEGER PRIMARY KEY,
    service_id          INTEGER NOT NULL,
    billing_month       TEXT    NOT NULL,            -- first day of month
    invoice_date        TEXT    NOT NULL,
    plan_charge_aud     REAL    NOT NULL,
    excess_usage_aud    REAL    NOT NULL DEFAULT 0,
    discount_aud        REAL    NOT NULL DEFAULT 0,
    total_amount_aud    REAL    NOT NULL,
    payment_status      TEXT,                        -- Paid | Late | Unpaid
    days_late           INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (service_id) REFERENCES services(service_id)
);

-- ---------------------------------------------------------------------------
-- 6. usage_monthly - monthly consumption per service.
--    Feeds the "no billable usage" half of the D1 churn rule, and provides
--    the usage-decay early-warning signal used in Phase 8.
-- ---------------------------------------------------------------------------
CREATE TABLE usage_monthly (
    usage_id            INTEGER PRIMARY KEY,
    service_id          INTEGER NOT NULL,
    usage_month         TEXT    NOT NULL,            -- first day of month
    data_gb             REAL    NOT NULL DEFAULT 0,
    voice_minutes       INTEGER NOT NULL DEFAULT 0,
    sms_count           INTEGER NOT NULL DEFAULT 0,
    roaming_gb          REAL    NOT NULL DEFAULT 0,
    days_active         INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (service_id) REFERENCES services(service_id)
);

-- ---------------------------------------------------------------------------
-- 7. support_tickets - service experience. A churn driver, not just a metric.
-- ---------------------------------------------------------------------------
CREATE TABLE support_tickets (
    ticket_id           INTEGER PRIMARY KEY,
    service_id          INTEGER NOT NULL,
    customer_id         INTEGER NOT NULL,
    created_date        TEXT    NOT NULL,
    resolved_date       TEXT,                        -- NULL = still open
    issue_category      TEXT,
    priority            TEXT,                        -- Low | Medium | High | Critical
    contact_channel     TEXT,
    resolution_hours    REAL,
    csat_score          INTEGER,                     -- 1-5
    FOREIGN KEY (service_id)  REFERENCES services(service_id),
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CHECK (csat_score BETWEEN 1 AND 5)
);

-- ---------------------------------------------------------------------------
-- 8. campaigns - retention / winback / upsell programmes and their budgets.
-- ---------------------------------------------------------------------------
CREATE TABLE campaigns (
    campaign_id         INTEGER PRIMARY KEY,
    campaign_name       TEXT    NOT NULL,
    campaign_type       TEXT,                        -- Retention | Winback | Upsell
    start_date          TEXT    NOT NULL,
    end_date            TEXT    NOT NULL,
    target_segment      TEXT,
    offer_type          TEXT,
    offer_value_aud     REAL,
    budget_aud          REAL
);

-- ---------------------------------------------------------------------------
-- 9. campaign_contacts - who was contacted, did they respond, did they stay.
--    This is the retention-ROI table: cost in, retention out.
-- ---------------------------------------------------------------------------
CREATE TABLE campaign_contacts (
    contact_id          INTEGER PRIMARY KEY,
    campaign_id         INTEGER NOT NULL,
    service_id          INTEGER NOT NULL,
    contact_date        TEXT    NOT NULL,
    contact_channel     TEXT,                        -- SMS | Email | Call | App Push
    response_flag       INTEGER NOT NULL DEFAULT 0,
    retained_30d_flag   INTEGER NOT NULL DEFAULT 0,
    contact_cost_aud    REAL    NOT NULL DEFAULT 0,
    FOREIGN KEY (campaign_id) REFERENCES campaigns(campaign_id),
    FOREIGN KEY (service_id)  REFERENCES services(service_id)
);

-- ---------------------------------------------------------------------------
-- Indexes - the joins and window partitions this project leans on.
-- ---------------------------------------------------------------------------
CREATE INDEX idx_services_customer     ON services(customer_id);
CREATE INDEX idx_services_plan         ON services(plan_id);
CREATE INDEX idx_recharges_service     ON recharges(service_id, recharge_date);
CREATE INDEX idx_invoices_service      ON invoices(service_id, billing_month);
CREATE INDEX idx_usage_service         ON usage_monthly(service_id, usage_month);
CREATE INDEX idx_tickets_service       ON support_tickets(service_id, created_date);
CREATE INDEX idx_contacts_campaign     ON campaign_contacts(campaign_id);
CREATE INDEX idx_contacts_service      ON campaign_contacts(service_id);
