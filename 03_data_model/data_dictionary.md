# Data Dictionary

**Database:** `waratah_telecom` · **Dialect:** SQLite · **Grain:** Service
**Coverage:** 2024-01-01 to 2025-06-30 (FY25 plus 6 months lead-in)

---

## Why the lead-in period exists

The dataset starts six months before FY25 deliberately. The D1 churn rule requires 60 days of prior history to evaluate, and cohort retention curves need a look-back window. Starting the data exactly at the reporting period would make the first two months of every churn series unreliable — a mistake that is easy to make and hard to explain afterwards.

---

## Table overview

| # | Table | Grain | Rows (seed) | Role |
|---|---|---|---|---|
| 1 | `customers` | Account holder | 40 | Dimension |
| 2 | `plans` | Product | 10 | Dimension |
| 3 | `services` | SIM / service | 51 | **Fact spine** |
| 4 | `recharges` | Payment event | 250 | Fact — prepaid revenue |
| 5 | `invoices` | Monthly bill | 472 | Fact — postpaid revenue |
| 6 | `usage_monthly` | Service × month | 735 | Fact — consumption |
| 7 | `support_tickets` | Ticket | 40 | Fact — service experience |
| 8 | `campaigns` | Campaign | 6 | Dimension |
| 9 | `campaign_contacts` | Campaign × service | 71 | Fact — retention activity |

Row counts are for the 40-customer seed dataset. Use `generate_data.py --customers N` to scale.

---

## 1. customers

One row per billing account holder.

| Column | Type | Null | Description | Values / notes |
|---|---|---|---|---|
| `customer_id` | INTEGER | No | Primary key | |
| `first_name` | TEXT | No | Given name | Synthetic |
| `last_name` | TEXT | No | Family name | Synthetic |
| `date_of_birth` | TEXT | Yes | ISO date | Used for age banding |
| `state` | TEXT | No | Australian state | NSW, VIC, QLD (CHECK enforced) |
| `city` | TEXT | Yes | Metro or regional centre | |
| `postcode` | TEXT | Yes | Australian postcode | Stored as TEXT — leading zeros matter |
| `customer_segment` | TEXT | No | Commercial segment | Consumer, SMB (CHECK enforced) |
| `acquisition_channel` | TEXT | Yes | How they were acquired | Online, Retail Store, Telesales, Partner Reseller, Referral |
| `acquisition_date` | TEXT | No | First relationship date | ISO date |
| `credit_risk_band` | TEXT | Yes | Credit assessment | Low / Medium / High Risk |

**Note:** `postcode` is TEXT, not INTEGER. Australian postcodes have leading zeros (NT starts 08xx); storing them as integers silently corrupts them. Not relevant to NSW/VIC/QLD, but the habit is the point.

---

## 2. plans

Product catalogue.

| Column | Type | Null | Description | Values / notes |
|---|---|---|---|---|
| `plan_id` | INTEGER | No | Primary key | |
| `plan_name` | TEXT | No | Customer-facing name | |
| `plan_type` | TEXT | No | Billing model | Prepaid, Postpaid (CHECK enforced) |
| `monthly_price_aud` | REAL | No | List price | AUD 10–99 |
| `included_data_gb` | REAL | Yes | Monthly data allowance | |
| `contract_months` | INTEGER | No | Lock-in term | 0 = no lock-in (all prepaid) |
| `plan_family` | TEXT | Yes | Marketing grouping | Starter, Value, Max, Essential, Everyday, Premium, Business |
| `is_active` | INTEGER | No | Currently sold | 0/1 |

**Simplification:** in production this would be a slowly-changing dimension with effective dates, because plan prices change and you need the price that applied *at the time*. Here it is static. Worth stating in an interview — it shows you know what was simplified and why.

---

## 3. services — the fact spine

One row per mobile service (SIM). **All churn and revenue analysis happens at this grain.**

| Column | Type | Null | Description | Values / notes |
|---|---|---|---|---|
| `service_id` | INTEGER | No | Primary key | |
| `customer_id` | INTEGER | No | FK → customers | A customer may hold several services |
| `plan_id` | INTEGER | No | FK → plans | |
| `msisdn` | TEXT | Yes | Mobile number | Synthetic |
| `activation_date` | TEXT | No | Service start | ISO date |
| `deactivation_date` | TEXT | **Yes** | Service end | **Postpaid churn only.** NULL for all prepaid |
| `service_status` | TEXT | No | Current status | Active, Deactivated, Suspended |
| `device_type` | TEXT | Yes | Device arrangement | Handset - Subsidised / Outright, BYO Device, Mobile Broadband |
| `is_byo` | INTEGER | No | Bring-your-own device | 0/1 |
| `port_in_flag` | INTEGER | No | Ported from another carrier | 0/1 |

### The most important thing in this schema

**There is no churn flag for prepaid services.** A churned prepaid service still shows `service_status = 'Active'` and `deactivation_date = NULL`.

This is not an oversight — it is how prepaid actually works. There is no contract to cancel, so the customer simply stops recharging. Nobody tells the billing system they have gone. The analyst must **derive** churn from the gap between recharge dates, per Decision D1.

Consequences you should be able to articulate:
- `SELECT COUNT(*) FROM services WHERE service_status = 'Active'` **overstates the live base**, because it includes dormant prepaid services.
- Prepaid churn requires window functions (`LAG` / `LEAD` over `recharge_date`), not a simple `WHERE` clause.
- Postpaid churn is straightforward by comparison — `deactivation_date IS NOT NULL` — because cancellation is a contractual event.

This asymmetry is the analytical heart of the project.

---

## 4. recharges — prepaid revenue

One row per prepaid payment. **Irregular and event-driven**, not monthly.

| Column | Type | Null | Description | Values / notes |
|---|---|---|---|---|
| `recharge_id` | INTEGER | No | Primary key | |
| `service_id` | INTEGER | No | FK → services | Prepaid services only |
| `recharge_date` | TEXT | No | Payment date | ISO date |
| `amount_aud` | REAL | No | Amount paid | Denominations 10/20/30/40/50 |
| `recharge_channel` | TEXT | Yes | Where paid | App, Website, Retail Store, Auto-Recharge, Third Party |
| `recharge_type` | TEXT | Yes | Payment mode | Auto, Manual |

**Analytical notes**
- Typical cadence is 26–38 days. The gap between consecutive recharges is the raw material for D1.
- **Sleepers exist in this data, deliberately.** Roughly 11% of prepaid services take a single 60–88 day recharge break and then resume, while continuing to consume data throughout. Under D1 they are **not** churned, because the rule requires no recharge *and* no billable usage. A churn query written on recharge gaps alone will classify all of them as churned and overstate prepaid churn by around a sixth. Handling this correctly is the main technical test of Phase 4.
- Recharge amounts drift **downward** across the window, reproducing the competitive repricing pressure behind the ARPU decline.
- `recharge_type = 'Auto'` is a retention signal in its own right: auto-recharge customers churn less because leaving requires an active decision.
- Only prepaid services appear here. `SUM(amount_aud)` is therefore total prepaid revenue with no plan-type filter needed — but relying on that without checking is exactly the assumption that breaks when the data changes.

---

## 5. invoices — postpaid revenue

One row per monthly bill. **Regular monthly cadence.**

| Column | Type | Null | Description | Values / notes |
|---|---|---|---|---|
| `invoice_id` | INTEGER | No | Primary key | |
| `service_id` | INTEGER | No | FK → services | Postpaid services only |
| `billing_month` | TEXT | No | Month billed | First day of month |
| `invoice_date` | TEXT | No | Issue date | Usually 4th of month |
| `plan_charge_aud` | REAL | No | Base plan charge | |
| `excess_usage_aud` | REAL | No | Out-of-bundle charges | Default 0 |
| `discount_aud` | REAL | No | Discounts applied | Grows over the window |
| `total_amount_aud` | REAL | No | Amount billed | = plan + excess − discount |
| `payment_status` | TEXT | Yes | Payment outcome | Paid, Late, Unpaid |
| `days_late` | INTEGER | No | Days past due | 0 if paid on time |

**Analytical notes**
- `payment_status` and `days_late` are churn predictors — payment stress often precedes voluntary departure and always precedes involuntary disconnection.
- Rising `discount_aud` across the window is a direct driver of the ARPU decline, and a candidate root cause worth separating from mix shift.

---

## 6. usage_monthly

Consumption per service per month.

| Column | Type | Null | Description |
|---|---|---|---|
| `usage_id` | INTEGER | No | Primary key |
| `service_id` | INTEGER | No | FK → services |
| `usage_month` | TEXT | No | First day of month |
| `data_gb` | REAL | No | Data consumed |
| `voice_minutes` | INTEGER | No | Voice minutes |
| `sms_count` | INTEGER | No | SMS sent |
| `roaming_gb` | REAL | No | Roaming data |
| `days_active` | INTEGER | No | Days with any activity |

**Analytical notes**
- Usage **decays in the three months before churn**. This is the strongest leading indicator in the dataset and the basis of the usage decay index.
- `days_active` supports the "no billable usage" half of the D1 rule.
- Index each service against its own baseline, not against the population average — see the KPI definitions.

---

## 7. support_tickets

| Column | Type | Null | Description | Values / notes |
|---|---|---|---|---|
| `ticket_id` | INTEGER | No | Primary key | |
| `service_id` | INTEGER | No | FK → services | |
| `customer_id` | INTEGER | No | FK → customers | Denormalised for convenience |
| `created_date` | TEXT | No | Raised date | |
| `resolved_date` | TEXT | **Yes** | Closed date | NULL = still open |
| `issue_category` | TEXT | Yes | Issue type | Billing Dispute, Network Coverage, Data Speed, Plan Change, Device/SIM Fault, Porting Request, Credit/Refund |
| `priority` | TEXT | Yes | Severity | Low, Medium, High, Critical |
| `contact_channel` | TEXT | Yes | How raised | Phone, Chat, Email, Retail Store, Social |
| `resolution_hours` | REAL | Yes | Time to resolve | |
| `csat_score` | INTEGER | Yes | Satisfaction 1–5 | CHECK enforced |

**Analytical caution:** churners raise more tickets in this dataset. That is a **correlation**. Tickets plausibly do not cause churn — underlying dissatisfaction plausibly causes both. Reporting "support tickets cause churn" is the fastest way to be wrong in front of a senior stakeholder. Reporting "services raising 3+ tickets churn at 2.4× the base rate" is defensible.

`resolved_date` is deliberately NULL for ~8% of tickets. Any join or duration calculation must handle it.

---

## 8. campaigns

| Column | Type | Null | Description |
|---|---|---|---|
| `campaign_id` | INTEGER | No | Primary key |
| `campaign_name` | TEXT | No | Campaign name |
| `campaign_type` | TEXT | Yes | Retention, Winback, Upsell |
| `start_date` | TEXT | No | Start |
| `end_date` | TEXT | No | End |
| `target_segment` | TEXT | Yes | Intended audience |
| `offer_type` | TEXT | Yes | Bonus Credit, Data Bonus, Bill Credit, Plan Upgrade |
| `offer_value_aud` | REAL | Yes | Offer value per contact |
| `budget_aud` | REAL | Yes | Allocated budget |

Six campaigns span the window, covering all three types, so campaign-type effectiveness is comparable.

---

## 9. campaign_contacts

The retention-ROI table: cost in, retention out.

| Column | Type | Null | Description |
|---|---|---|---|
| `contact_id` | INTEGER | No | Primary key |
| `campaign_id` | INTEGER | No | FK → campaigns |
| `service_id` | INTEGER | No | FK → services |
| `contact_date` | TEXT | No | Contact date |
| `contact_channel` | TEXT | Yes | SMS, Email, Outbound Call, App Push |
| `response_flag` | INTEGER | No | Responded 0/1 |
| `retained_30d_flag` | INTEGER | No | Still active 30 days later 0/1 |
| `contact_cost_aud` | REAL | No | Cost of the contact |

**Analytical caution:** responders retain far better than non-responders in this data. Do not report that as campaign effectiveness. Customers who engage with a retention offer are already more engaged with the brand — the campaign may be measuring the disposition rather than creating it. Estimating the *incremental* effect requires a comparable non-contacted group (FR-23), and where that comparison is imperfect, say so.

---

## Relationships

| Parent | Child | Cardinality | Key |
|---|---|---|---|
| customers | services | 1 : many | customer_id |
| plans | services | 1 : many | plan_id |
| services | recharges | 1 : many | service_id — prepaid only |
| services | invoices | 1 : many | service_id — postpaid only |
| services | usage_monthly | 1 : many | service_id |
| services | support_tickets | 1 : many | service_id |
| customers | support_tickets | 1 : many | customer_id |
| campaigns | campaign_contacts | 1 : many | campaign_id |
| services | campaign_contacts | 1 : many | service_id |

---

## Design decisions worth defending

| Decision | Rationale |
|---|---|
| Service grain, not customer grain | A customer with three SIMs can churn one and keep two. Customer-grain churn cannot represent that. |
| No stored prepaid churn flag | Mirrors reality and forces the window-function derivation that the analysis depends on. |
| Two separate revenue tables | Prepaid and postpaid genuinely have different billing mechanics. Unifying them requires a UNION, which mirrors the real problem of reconciling two billing stacks. |
| Dates as TEXT in ISO format | SQLite has no native DATE type. ISO format sorts and compares correctly as text, and `julianday()` handles arithmetic. |
| `customer_id` denormalised onto tickets | Convenience for customer-level ticket analysis without a three-table join. A pragmatic, documented denormalisation. |
| 18-month window | Long enough for cohort curves and the 60-day rule; short enough to stay relevant. |

---

## Known limitations

1. Plans are static — no price-change history.
2. No explicit churn-reason codes; reasons must be inferred from behaviour. This is realistic but limits causal claims.
3. Campaign contacts have no true randomised control group, so incremental lift is estimated, not measured.
4. Synthetic data has cleaner relationships than production data ever does; the methodology transfers, the absolute numbers do not.
