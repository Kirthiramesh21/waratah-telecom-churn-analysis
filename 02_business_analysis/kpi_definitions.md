# KPI Definitions

**Purpose:** a single authoritative definition for every metric in this project. If two people compute the same KPI and get different answers, this document is the tie-breaker.

Ambiguous KPI definitions are the most common cause of an analyst losing an argument they were factually right about. Each definition below states the formula, the grain, the inclusions and exclusions, and the trap.

---

## 1. Churn rate

**Business meaning:** the share of the active base that left during a month.

**Formula**

```
Monthly churn rate = churned services in month M
                     -------------------------------
                     active services at start of M
```

| Property | Specification |
|---|---|
| Grain | Service × month |
| Numerator | Services meeting the D1 churn definition with a churn date in month M |
| Denominator | Services with status Active on the first day of month M |
| Prepaid churn date | The 60th day of the silent window (recharge gap ≥ 60 days) |
| Postpaid churn date | `deactivation_date` |
| Excludes | Services activated during month M (not exposed for the full period) |
| Reported as | Prepaid, postpaid and blended, always side-by-side (D2) |

**Traps**
- Using *end-of-month* active services as the denominator understates churn, because churners have already been removed.
- Blended churn is a weighted average of two different mechanics — always show the components.
- The two most recent months are **provisional** for prepaid: the 60-day rule cannot yet have elapsed.

**Baseline 2.6% · Target ≤ 2.0%**

---

## 2. ARPU (Average Revenue Per User)

**Business meaning:** average monthly revenue generated per revenue-generating service.

**Formula**

```
ARPU = total revenue in month M
       -------------------------------------------
       distinct revenue-generating services in M
```

| Property | Specification |
|---|---|
| Grain | Service × month |
| Prepaid revenue | `SUM(recharges.amount_aud)` where `recharge_date` falls in M |
| Postpaid revenue | `SUM(invoices.total_amount_aud)` where `billing_month` = M |
| Blended revenue | UNION ALL of the two streams to a common service-month grain |
| Denominator | Count of DISTINCT `service_id` with revenue in M |
| Excludes | Deactivated services with no revenue in M |

**Traps**
- The two revenue streams live in **separate tables**. A single `SUM` over one of them silently reports only half the business. This is the single most likely error in this project.
- Prepaid recharges are irregular — a customer on a 35-day cycle contributes to some months and not others. Denominator choice materially changes the answer; document which you used.
- "Per user" is a misnomer: this is per **service**. A customer with three SIMs counts three times.

**Baseline AUD 40.10 · Target ≥ AUD 43.00 · Floor AUD 39.00 (D3)**

---

## 3. Net adds

**Formula**

```
Net adds in M = gross activations in M − churned services in M
```

Positive means the base is growing. Waratah's is currently negative — the reason this project exists.

---

## 4. Customer value decile

**Business meaning:** which tenth of the base a service sits in by revenue contribution.

**Method:** rank active services by trailing 6-month total revenue (prepaid recharges + postpaid invoices), then split into ten equal-sized groups. Decile 1 = highest value.

**Traps**
- Rank on **trailing revenue**, not current plan price — plan price is what they were sold, revenue is what they actually pay.
- Services younger than 6 months have an incomplete trailing window; either annualise or exclude, but state which.
- Deciles must be recomputed each reporting period; a decile is a relative position, not a permanent label.

**Target: ≥ 95% retention in decile 1 (BO3).**

---

## 5. Campaign retention rate and ROI

**Formula**

```
Response rate    = responded contacts / total contacts
Retention rate   = retained-at-30-days contacts / total contacts
Campaign ROI     = (net revenue retained − campaign cost) / campaign cost
Net revenue retained = retained services × their monthly ARPU × months retained
```

**Traps**
- **Selection bias is the whole game.** If a campaign targeted customers who were never going to leave, a 74% retention rate proves nothing. Compare against a comparable non-contacted group, and where no clean control exists, say so explicitly.
- Cost must include offer value given *and* contact cost, not just media spend.
- A 30-day retention window is short. It measures deferral as much as salvation; deferred churn is not prevented churn.

---

## 6. Tenure

```
Tenure (months) = months between activation_date and the reporting month
```

Reported in bands: 0–3, 4–6, 7–12, 13–24, 25+ months. Early-tenure churn and long-tenure churn have entirely different causes and entirely different fixes, which is why banding matters more than the raw number.

---

## 7. Usage decay index

**Business meaning:** how far a service's recent consumption has fallen below its own normal level. A leading churn indicator (FR-16).

```
Usage decay index = avg data_gb in last 3 months
                    ---------------------------------
                    avg data_gb in the 6 months prior
```

An index below 1.0 means declining consumption. Indexing each service against **its own** baseline matters: a heavy user dropping from 80 GB to 30 GB is a stronger churn signal than a light user steady at 2 GB, even though the light user consumes far less in absolute terms.

---

## 8. Revenue at risk

```
Annualised revenue at risk = services at elevated churn risk × blended ARPU × 12
```

Always state the assumptions — which risk threshold, which ARPU, and whether the figure is gross revenue or contribution margin. Finance will ask, and "gross revenue" quietly overstates the business impact.

---

## Definition governance

| Rule | Reason |
|---|---|
| No metric is reported without a definition in this document | Prevents two versions of the truth |
| Any change to a definition is versioned, dated and re-baselined | Historical comparisons stay valid |
| Finance signs off churn and ARPU definitions before analysis | Prevents post-hoc methodology disputes (Risk R1) |
| Every dashboard figure links to its definition | Makes numbers auditable |
