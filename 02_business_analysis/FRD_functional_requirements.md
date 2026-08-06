# Functional Requirements Document (FRD)

**Project:** Subscriber Churn & ARPU Recovery Analysis
**Companion to:** [BRD v1.0](./BRD_business_requirements.md)
**Version:** 1.0 — August 2026

---

## 1. Purpose

The BRD states what the business needs. This FRD states **what must be built** to meet it. Every functional requirement traces back to a business requirement (BR-xx); anything that cannot be traced does not belong in the build.

---

## 2. Data requirements

### 2.1 Source tables

| Table | Grain | Purpose | Required for |
|---|---|---|---|
| `customers` | One row per account holder | Demographics, geography, segment, acquisition | BR-02, BR-05 |
| `plans` | One row per product | Plan type, price, inclusions, contract term | BR-02, BR-04 |
| `services` | One row per SIM / service | Fact spine; activation, deactivation, status | All |
| `recharges` | One row per prepaid payment | Prepaid revenue; source of D1 churn derivation | BR-01, BR-04 |
| `invoices` | One row per postpaid bill | Postpaid revenue; payment behaviour | BR-04, BR-12 |
| `usage_monthly` | Service × month | Consumption; usage-decay signal | BR-03 |
| `support_tickets` | One row per ticket | Service experience; churn driver | BR-12 |
| `campaigns` | One row per campaign | Retention programme metadata and budget | BR-06 |
| `campaign_contacts` | Campaign × service | Contact, response and retention outcome | BR-06 |

Full field-level specification: [Data Dictionary](../03_data_model/data_dictionary.md).

### 2.2 Data quality rules

| ID | Rule | Action on failure |
|---|---|---|
| DQ-01 | Every `service_id` in a child table must exist in `services` | Reject row; log orphan |
| DQ-02 | `deactivation_date` must be ≥ `activation_date` | Flag for review |
| DQ-03 | `amount_aud` on recharges must be > 0 | Exclude from revenue; log |
| DQ-04 | `total_amount_aud` = `plan_charge_aud` + `excess_usage_aud` − `discount_aud` | Flag arithmetic breaks |
| DQ-05 | `state` must be one of NSW, VIC, QLD | Reject; enforced by CHECK constraint |
| DQ-06 | No duplicate `(service_id, billing_month)` in invoices | Deduplicate; log |
| DQ-07 | Dates must parse as ISO `YYYY-MM-DD` | Reject row |
| DQ-08 | `csat_score` must be 1–5 or NULL | Set to NULL; log |

---

## 3. Functional requirements

### 3.1 Churn measurement

| ID | Requirement | Traces to |
|---|---|---|
| FR-01 | The system shall derive prepaid churn as 60 consecutive days with no recharge **and** no billable usage, calculated from gaps between consecutive `recharge_date` values per service | BR-01 |
| FR-02 | The system shall derive postpaid churn from a non-null `deactivation_date` on the service record | BR-01 |
| FR-03 | The system shall compute monthly churn rate as churned services in month ÷ active services at month start | BR-01 |
| FR-04 | The system shall report prepaid, postpaid and blended churn separately in every output | BR-01, D2 |
| FR-05 | The system shall label the two most recent months of prepaid churn as provisional | BR-01, C1 |
| FR-06 | The system shall support sensitivity testing of the churn window at 30, 45, 60 and 90 days | R1 mitigation |

### 3.2 Segmentation and dimensions

| ID | Requirement | Traces to |
|---|---|---|
| FR-07 | The system shall allow every churn and revenue metric to be sliced by state, plan type, plan family, customer segment, tenure band and value decile | BR-02 |
| FR-08 | The system shall derive tenure in months as the difference between `activation_date` and the reporting month | BR-02 |
| FR-09 | The system shall assign each active service to a value decile based on trailing 6-month revenue | BR-05 |

### 3.3 Revenue and ARPU

| ID | Requirement | Traces to |
|---|---|---|
| FR-10 | The system shall compute prepaid revenue by month as the sum of `amount_aud` from recharges | BR-04 |
| FR-11 | The system shall compute postpaid revenue by month as the sum of `total_amount_aud` from invoices | BR-04 |
| FR-12 | The system shall compute blended revenue by unioning the two revenue streams to a common service-month grain | BR-04 |
| FR-13 | The system shall compute ARPU as total revenue in month ÷ distinct revenue-generating services in month | BR-04 |
| FR-14 | The system shall decompose ARPU change into mix shift, plan downgrade and discounting components | BR-04, Q10 |
| FR-15 | The system shall test every proposed initiative against the AUD 39.00 blended ARPU floor | BR-08, D3 |

### 3.4 Churn drivers

| ID | Requirement | Traces to |
|---|---|---|
| FR-16 | The system shall compute average monthly data usage for the 1, 2 and 3 months preceding churn, indexed against each service's own prior baseline | BR-03 |
| FR-17 | The system shall compute churn rate by support ticket count, issue category, resolution hours and CSAT band | BR-12 |
| FR-18 | The system shall compute churn rate by payment status and days late for postpaid | BR-03 |
| FR-19 | The system shall compare churn rates for ported-in vs. organically acquired services | Q8 |
| FR-20 | The system shall express each driver as lift versus the base churn rate, with the supporting denominator shown | BR-03 |

### 3.5 Campaign effectiveness

| ID | Requirement | Traces to |
|---|---|---|
| FR-21 | The system shall compute contact count, response rate, 30-day retention rate and total cost per campaign | BR-06 |
| FR-22 | The system shall compute campaign ROI as (net revenue retained − campaign cost) ÷ campaign cost | BR-06 |
| FR-23 | The system shall compare retention of contacted vs. comparable non-contacted services to estimate incremental effect | BR-06 |

FR-23 is the one that separates a real campaign evaluation from a vanity metric. A campaign that reports 74% retention among responders has proven nothing if responders were the customers least likely to leave in the first place. **Selection bias must be addressed, and where it cannot be eliminated it must be disclosed.**

### 3.6 Predictive and segmentation

| ID | Requirement | Traces to |
|---|---|---|
| FR-24 | The system shall produce a churn probability score per active service | BR-09 |
| FR-25 | The system shall report model performance using precision, recall, F1 and AUC on a held-out test set | BR-09 |
| FR-26 | The system shall rank feature importance in business-interpretable terms | BR-09 |
| FR-27 | The system shall exclude any feature unavailable at prediction time (no target leakage) | BR-09 |
| FR-28 | The system shall group services into behavioural segments with distinct, named retention strategies | BR-10 |

FR-27 is a deliberate guard against the most common and most embarrassing modelling error. If a "days since last recharge" feature is computed *after* the churn event, the model achieves near-perfect accuracy and is entirely worthless.

### 3.7 Reporting and dashboards

| ID | Requirement | Primary user | Traces to |
|---|---|---|---|
| FR-29 | Executive dashboard: churn, ARPU, net adds, revenue at risk vs. target | Chief Commercial Officer | BR-11 |
| FR-30 | Operational dashboard: churn by segment/state/plan, driver breakdown, campaign performance | Head of Retention | BR-11 |
| FR-31 | Customer dashboard: service-level risk score, value decile, recommended action | Retention agent | BR-11 |
| FR-32 | Every dashboard shall state its data-as-at date and flag provisional periods | BR-11, C1 |

---

## 4. Non-functional requirements

| ID | Category | Requirement |
|---|---|---|
| NFR-01 | Reproducibility | Any result must be regenerable from committed code and seed data with no manual steps |
| NFR-02 | Portability | SQL shall run on SQLite without modification; date logic shall not depend on vendor-specific types |
| NFR-03 | Auditability | Every reported metric shall trace to a named, documented query or script |
| NFR-04 | Performance | Analytical queries shall complete in under 30 seconds on the full dataset |
| NFR-05 | Documentation | Every non-obvious analytical decision shall be recorded with its rationale |
| NFR-06 | Privacy | No output shall expose individual customer identity beyond internal identifiers |
| NFR-07 | Version control | All artefacts shall be committed to Git with meaningful history |

---

## 5. Traceability matrix

| FR | BR | Phase |
|---|---|---|
| FR-01 – FR-06 | BR-01 | 4 |
| FR-07 – FR-09 | BR-02, BR-05 | 4 |
| FR-10 – FR-15 | BR-04, BR-08 | 4, 6 |
| FR-16 – FR-20 | BR-03, BR-12 | 4, 6 |
| FR-21 – FR-23 | BR-06 | 4 |
| FR-24 – FR-28 | BR-09, BR-10 | 8 |
| FR-29 – FR-32 | BR-11 | 7 |

---

## 6. Out of scope (functional)

- Real-time or event-driven scoring (batch only)
- Write-back to operational or billing systems
- Automated offer delivery or campaign execution
- Model retraining pipelines and monitoring
- Row-level security or multi-tenant access control
