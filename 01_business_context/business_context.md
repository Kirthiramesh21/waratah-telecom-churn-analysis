# Phase 1 — Business Context

**Project:** Subscriber Churn & ARPU Recovery Analysis
**Client:** Waratah Telecom Pty Ltd (fictional)
**Analyst:** Kurt
**Date:** August 2026

---

## 1. Company profile

Waratah Telecom is a challenger mobile network operator headquartered in Sydney, NSW. It competes in the Australian retail mobile market against the three incumbent carriers, positioning on price and simplicity rather than network coverage.

| Attribute | Value |
|---|---|
| Headquarters | Sydney, NSW |
| Markets served | NSW, VIC, QLD |
| Total services in market | ~1.4 million |
| Product mix | ~62% postpaid / ~38% prepaid |
| FY25 revenue | ~AUD 695 million |
| Customer segments | Consumer, Small & Medium Business (SMB) |
| Network model | Wholesale access (MVNO-style), no owned RAN |

Waratah does not own its radio network. This matters analytically: it cannot compete on coverage, so its retention levers are commercial — pricing, plan value, service experience — not infrastructure. Every recommendation in this project must be executable through commercial levers.

---

## 2. Market context

The Australian retail mobile market has three structural features that shape this analysis:

1. **Near-saturation.** Mobile penetration exceeds 100% of population. Growth comes almost entirely from taking subscribers off competitors, not from new-to-market customers. This makes retention economically superior to acquisition.
2. **Low switching friction.** Mobile Number Portability lets a customer port out in minutes, and prepaid customers have no contract at all. There is no lock-in to lean on.
3. **Aggressive challenger pricing.** Sub-brands owned by the incumbents compete directly on the price-sensitive segment Waratah occupies, compressing ARPU across the board.

**Implication:** Waratah's base is inherently mobile, and its prepaid base especially so. A churn problem here is not an anomaly to be fixed once — it is a structural condition to be managed continuously.

---

## 3. The business problem

Over the four quarters of FY25, four metrics moved against Waratah simultaneously:

| Metric | Start of FY25 | End of FY25 | Movement |
|---|---|---|---|
| Blended monthly churn | 1.6% | 2.6% | +1.0 pp |
| Prepaid monthly churn | — | 3.1% | Worst-performing segment |
| Blended ARPU | AUD 44.20 | AUD 40.10 | −AUD 4.10 (−9.3%) |
| Net adds | Positive | Negative | Base now shrinking |
| Cost per acquisition | Baseline | +18% | Acquisition getting more expensive |

### Why these four together are worse than any one alone

This is the core of the business case, and it is worth stating precisely:

- Churn rising **and** ARPU falling means Waratah is losing both *volume* and *value per unit of volume*. The two losses multiply rather than add.
- Net adds turning negative means acquisition is no longer replacing the losses. The base is now in structural decline.
- CAC rising 18% means the obvious response — "just acquire more" — is getting more expensive at exactly the moment it is needed most.

**Quantified exposure:** approximately **AUD 65 million+ in annualised revenue at risk**.

Sanity check on that figure: 1.4M services × 1.0pp additional monthly churn × 12 months × ~AUD 40 ARPU ≈ AUD 67M of annualised revenue run-rate lost to the churn increase alone, before accounting for the ARPU decline. The AUD 65M figure is therefore a conservative, defensible order of magnitude.

### What leadership does not know

Leadership can see the aggregate metrics on a monthly dashboard. What they cannot answer:

1. **Who** is leaving? Which segments, states, plans, tenure bands and value deciles are driving the increase?
2. **Why** are they leaving? Which behavioural signals (usage decay, service complaints, billing disputes, payment stress) precede churn, and by how long?
3. **Which retention levers have the best ROI?** Retention spend is currently broad-based. Nobody has measured which campaigns actually saved customers who would otherwise have left.

Those three questions define the scope of this project.

---

## 4. Stakeholder map

| Stakeholder | Role | What they care about | What they need from this analysis |
|---|---|---|---|
| Chief Commercial Officer | Executive sponsor | Revenue, margin, board narrative | Size of the problem, ROI of the fix, one-page decision |
| Head of Retention | Primary user | Campaign effectiveness, save rate | Ranked target list, which levers work on which segment |
| Head of Consumer Marketing | Contributor | Acquisition, brand, offer design | Which offers to build; ARPU guardrail compliance |
| Finance Business Partner | Reviewer / gatekeeper | Forecast accuracy, defensible numbers | Reproducible metric definitions, auditable methodology |
| Data Engineering Lead | Enabler | Data availability, pipeline load | Clear source-table requirements, query cost |
| Customer Service Operations | Contributor | Ticket volume, CSAT, handling time | Whether service issues drive churn, where to intervene |

### Stakeholder tensions to manage

Two conflicts are predictable and should be named up front rather than discovered late:

- **Retention vs. Finance.** Retention wants generous save offers; Finance protects ARPU. Decision D3 resolves this in advance with an explicit ARPU floor.
- **Marketing vs. Retention.** Marketing is measured on gross adds; Retention on saves. Both draw from the same commercial budget. Quantifying that retention is cheaper than acquisition (CAC +18%) reframes this from a turf dispute into an allocation decision.

---

## 5. Strategic objectives

These are the success criteria the analysis is accountable to.

| # | Objective | Target | Baseline |
|---|---|---|---|
| SO1 | Reduce blended monthly churn | ≤ 2.0% | 2.6% |
| SO2 | Recover blended ARPU | ≥ AUD 43.00 | AUD 40.10 |
| SO3 | Retain top-value customers | ≥ 95% retention in top value decile | Unknown — to be measured |
| SO4 | Target retention spend | ≥ 60% of spend on modelled high-risk / high-value | Largely untargeted |

SO3 is deliberately phrased as "unknown — to be measured." Declaring a baseline you have not measured is one of the fastest ways to lose credibility with a Finance stakeholder.

---

## 6. Locked analytical decisions

D1–D3 were made before analysis began and are held fixed for the remainder of the project. D4 was made during Phase 4, when building the combined churn list exposed a question the earlier decisions had not settled — which is normal, and the reason this section is a living log rather than a one-off. Documenting a decision *and its rationale* at the point it is made is what separates an analyst from a report generator.

### D1 — Churn definition

> **Prepaid:** a service is churned when it records **60 consecutive days with no recharge AND no billable usage**.
> **Postpaid:** a service is churned on its **cancellation / port-out deactivation date**.

**Rationale.** Prepaid customers never announce their departure — there is no contract to cancel, so churn must be inferred from silence. Prepaid recharge cycles run roughly 28–35 days, so a 60-day window represents **two consecutive missed cycles**. That is long enough to exclude temporary "sleepers" (a customer travelling, or between pay cycles) but short enough to preserve a commercially useful win-back window. Postpaid churn requires no inference because cancellation is a contractual event with a system-recorded date.

**Trade-off accepted.** A 60-day rule means churn is only confirmable 60 days in arrears. The most recent two months of any churn series are therefore provisional. This is stated explicitly wherever recent-period churn is reported.

**Alternatives rejected:** 30 days (over-counts sleepers, inflates churn); 90 days (accurate but the win-back window has closed by the time you know).

### D2 — Scope

> Analyse **both prepaid and postpaid with equal weight**, reported side-by-side and segmented in every analysis.

**Rationale.** Postpaid is the revenue engine (higher ARPU, contracted); prepaid is where the churn spike is concentrated (3.1% vs. blended 2.6%). Analysing only postpaid would miss the volume risk; analysing only prepaid would miss the revenue risk. Because the two have structurally different churn mechanics (inferred vs. contractual) and different revenue tables, a blended-only view would average away the very signal the project exists to find.

**Cost accepted:** roughly double the analytical work, and every metric needs
