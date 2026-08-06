# Business Requirements Document (BRD)

**Project:** Subscriber Churn & ARPU Recovery Analysis
**Client:** Waratah Telecom Pty Ltd
**Document owner:** Kurt (Business Analyst)
**Version:** 1.0 — August 2026
**Status:** Baselined

---

## 1. Document purpose

This BRD states **what the business needs and why**, in business language, without prescribing how it will be built. The technical "how" lives in the companion [FRD](./FRD_functional_requirements.md).

The distinction matters and is a common interview question: a **BRD is owned by the business and answers "what problem are we solving and what does success look like"**; an **FRD is owned by delivery and answers "what must the system do"**. A requirement that mentions a table name, a chart type or a tool belongs in the FRD, not here.

**Audience:** Chief Commercial Officer (approver), Head of Retention, Finance Business Partner, Data Engineering Lead.

---

## 2. Background and problem statement

Across FY25, Waratah Telecom's blended monthly churn rose from 1.6% to 2.6%, prepaid churn reached 3.1%, blended ARPU fell from AUD 44.20 to AUD 40.10, net adds turned negative and cost per acquisition rose 18%. Combined exposure is approximately **AUD 65 million in annualised revenue at risk**.

Leadership currently has visibility of the aggregate trend but cannot identify which customers are leaving, what precedes their departure, or which retention interventions actually work. Retention budget is consequently being deployed broadly rather than to the customers whose departure would cost the most.

Full context: [Phase 1 — Business Context](../01_business_context/business_context.md).

---

## 3. Business objectives

| ID | Objective | Success measure | Baseline | Target |
|---|---|---|---|---|
| BO1 | Reduce subscriber churn | Blended monthly churn rate | 2.6% | ≤ 2.0% |
| BO2 | Recover average revenue per user | Blended monthly ARPU | AUD 40.10 | ≥ AUD 43.00 |
| BO3 | Protect highest-value customers | Retention rate, top value decile | To be measured | ≥ 95% |
| BO4 | Improve retention spend efficiency | % of retention spend on modelled high-risk/high-value | Largely untargeted | ≥ 60% |

---

## 4. Scope

### 4.1 In scope

- Consumer and SMB mobile services in NSW, VIC and QLD
- Both prepaid and postpaid, analysed at equal weight (Decision D2)
- Historical data from 1 Jan 2024 to 30 Jun 2025
- Descriptive analysis (who and what), diagnostic analysis (why), and predictive risk scoring (who next)
- Retention campaign effectiveness and ROI measurement
- Recommendations with quantified financial impact

### 4.2 Out of scope

- Fixed broadband, NBN and non-mobile products
- Network coverage remediation — Waratah operates on wholesale access and cannot change the radio network
- Wholesale and carrier-partner channels
- Real-time or streaming churn scoring; this project delivers batch analysis
- Production deployment of any predictive model; the model is a decision aid, not a system
- Any use of personally identifying information beyond the analytical schema

### 4.3 Explicitly deferred

Real-time scoring and model productionisation are deferred to a follow-on initiative, contingent on this project demonstrating that the risk model outperforms current targeting.

---

## 5. Business requirements

Requirements are prioritised **MoSCoW** (Must / Should / Could / Won't). Each carries the business objective it serves, so that any requirement can be traced to a reason for existing.

### 5.1 Must have

| ID | Requirement | Serves | Acceptance criteria |
|---|---|---|---|
| BR-01 | The business must have a single, documented, reproducible definition of churn for prepaid and postpaid | BO1 | Definition matches Decision D1; produces identical results on re-run; signed off by Finance |
| BR-02 | The business must be able to see churn broken down by state, plan type, plan family, customer segment, tenure band and value decile | BO1, BO3 | Every churn figure is reportable across all six dimensions, prepaid and postpaid side-by-side |
| BR-03 | The business must know which behavioural signals precede churn, and how far in advance | BO1 | At least three leading indicators identified with quantified lead time and lift vs. base rate |
| BR-04 | The business must have blended, prepaid and postpaid ARPU tracked monthly on a consistent basis | BO2 | ARPU reconciles to total revenue within 1%; blending rule documented |
| BR-05 | The business must be able to rank customers by value so retention effort can be prioritised | BO3, BO4 | Value decile assigned to every active service; method documented and reproducible |
| BR-06 | The business must know the retention rate and ROI of each past retention campaign | BO4 | Cost, response rate, retention rate and net revenue retained reported per campaign |
| BR-07 | Recommendations must carry a quantified financial impact and an implementation owner | BO1–BO4 | Each recommendation states expected churn/ARPU impact, cost, and accountable function |
| BR-08 | No recommendation may push blended ARPU below AUD 39.00 | BO2 | ARPU guardrail (Decision D3) tested for every proposed initiative |

### 5.2 Should have

| ID | Requirement | Serves | Acceptance criteria |
|---|---|---|---|
| BR-09 | The business should have a forward-looking churn risk score per active service | BO1, BO4 | Model documented with performance metrics and honest limitations |
| BR-10 | The business should have customers grouped into behavioural segments with distinct retention strategies | BO4 | Segments are materially distinct, named in business language, and actionable |
| BR-11 | The business should have self-service dashboards for executive, operational and customer-level views | BO1–BO4 | Three dashboards, each with a named primary user and a stated decision it supports |
| BR-12 | The business should understand the relationship between service experience and churn | BO1 | Churn rate quantified by ticket volume, issue category, resolution time and CSAT |

### 5.3 Could have

| ID | Requirement | Serves |
|---|---|---|
| BR-13 | Cohort-based retention curves by acquisition month and channel | BO1 |
| BR-14 | Estimated customer lifetime value by segment | BO3 |
| BR-15 | Win-back opportunity sizing for recently churned prepaid services | BO1, BO2 |

### 5.4 Won't have (this release)

| ID | Requirement | Reason |
|---|---|---|
| BR-16 | Real-time churn scoring | Requires streaming infrastructure not in scope |
| BR-17 | Automated campaign execution / offer delivery | Owned by the martech platform, separate initiative |
| BR-18 | Network quality root-cause analysis | Waratah does not own the radio network |

---

## 6. Key business questions

These are the questions stakeholders will actually ask. Every one must be answerable at project close.

**Who is leaving?**
1. What is monthly churn by prepaid vs. postpaid, and how has each trended?
2. Which states, plan families and customer segments have the highest churn?
3. Does churn concentrate in particular tenure bands — is this a new-customer or a long-tenure problem?
4. What proportion of churned revenue comes from the top value decile?

**Why are they leaving?**
5. Does data usage decline before churn, and by how much and how far in advance?
6. Are customers who raise support tickets more likely to churn? Which issue categories are worst?
7. Does late or failed payment predict churn?
8. Do customers who ported in churn faster than organically acquired ones?

**What is it costing?**
9. What is the revenue impact of churn by segment?
10. How has ARPU moved, and is the decline driven by mix shift, plan downgrades or discounting?

**What should we do?**
11. Which retention campaigns delivered positive ROI, and which did not?
12. Which customers should be targeted first for the largest return?
13. What is the expected impact of each recommended initiative on churn and ARPU?

---

## 7. Assumptions

| ID | Assumption | Risk if false |
|---|---|---|
| A1 | Recharge and invoice records are complete and authoritative for revenue | ARPU and revenue-at-risk figures understate reality |
| A2 | The Jan 2024 – Jun 2025 window is representative of current market conditions | Findings may not generalise forward |
| A3 | A service, not a customer, is the correct unit of churn analysis | Multi-service customers are mis-measured |
| A4 | 60 days of prepaid silence reliably indicates departure | Churn is over- or under-counted; mitigated by sensitivity testing at 30/45/90 days |
| A5 | Support tickets are logged consistently across channels | Service-experience findings are biased toward well-logged channels |

---

## 8. Constraints

| ID | Constraint | Impact |
|---|---|---|
| C1 | Churn is only confirmable 60 days in arrears for prepaid | The two most recent months of any churn series are provisional and must be labelled as such |
| C2 | No owned radio network | Network-based retention levers are unavailable |
| C3 | Retention budget is fixed for the current financial year | Recommendations must reallocate existing spend, not request new spend |
| C4 | Analysis uses a synthetic dataset modelled on Waratah's real base | Absolute figures are illustrative; the methodology is the transferable deliverable |

---

## 9. Risks

| ID | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Stakeholders dispute the churn definition after results are published | Medium | High | D1 signed off by Finance *before* analysis; sensitivity tested at 30/45/90 days |
| R2 | Retention discounting to hit BO1 breaches the ARPU floor | Medium | High | D3 guardrail tested per initiative (BR-08) |
| R3 | Predictive model is treated as fact rather than a decision aid | Medium | Medium | Limitations documented; model presented as prioritisation input, not truth |
| R4 | Findings are correlational and get reported as causal | High | High | Causal language reserved for tested relationships; correlations labelled as such |
| R5 | Recommendations are not actionable by any existing function | Low | High | Every recommendation carries a named accountable owner (BR-07) |

R4 is the one that most often damages an analyst's credibility: "customers who raise tickets churn more" does not establish that tickets *cause* churn — dissatisfaction plausibly causes both.

---

## 10. Requirements traceability

| Business objective | Requirements | Delivered in phase |
|---|---|---|
| BO1 — Reduce churn | BR-01, BR-02, BR-03, BR-09, BR-12, BR-13 | 4, 6, 8 |
| BO2 — Recover ARPU | BR-04, BR-08 | 4, 6, 9 |
| BO3 — Protect high value | BR-02, BR-05, BR-14 | 4, 8 |
| BO4 — Spend efficiency | BR-05, BR-06, BR-09, BR-10 | 4, 8, 9 |
| All | BR-07, BR-11 | 7, 9, 10 |

---

## 11. Approval

| Role | Name | Decision | Date |
|---|---|---|---|
| Executive sponsor | Chief Commercial Officer | Approved | Aug 2026 |
| Business owner | Head of Retention | Approved | Aug 2026 |
| Finance reviewer | Finance Business Partner | Approved — conditional on D1 sign-off | Aug 2026 |
| Data owner | Data Engineering Lead | Approved | Aug 2026 |

*This is a portfolio project; approvals are illustrative and demonstrate the governance step a real BRD requires.*
