# Entity Relationship Diagram

GitHub renders Mermaid natively, so this diagram displays directly in the repository with no image file to keep in sync.

---

## Full model

```mermaid
erDiagram
    CUSTOMERS ||--o{ SERVICES : "holds"
    CUSTOMERS ||--o{ SUPPORT_TICKETS : "raises"
    PLANS ||--o{ SERVICES : "defines"
    SERVICES ||--o{ RECHARGES : "prepaid revenue"
    SERVICES ||--o{ INVOICES : "postpaid revenue"
    SERVICES ||--o{ USAGE_MONTHLY : "consumes"
    SERVICES ||--o{ SUPPORT_TICKETS : "generates"
    SERVICES ||--o{ CAMPAIGN_CONTACTS : "targeted by"
    CAMPAIGNS ||--o{ CAMPAIGN_CONTACTS : "delivers"

    CUSTOMERS {
        int customer_id PK
        text first_name
        text last_name
        text date_of_birth
        text state
        text city
        text postcode
        text customer_segment
        text acquisition_channel
        text acquisition_date
        text credit_risk_band
    }

    PLANS {
        int plan_id PK
        text plan_name
        text plan_type
        real monthly_price_aud
        real included_data_gb
        int contract_months
        text plan_family
        int is_active
    }

    SERVICES {
        int service_id PK
        int customer_id FK
        int plan_id FK
        text msisdn
        text activation_date
        text deactivation_date
        text service_status
        text device_type
        int is_byo
        int port_in_flag
    }

    RECHARGES {
        int recharge_id PK
        int service_id FK
        text recharge_date
        real amount_aud
        text recharge_channel
        text recharge_type
    }

    INVOICES {
        int invoice_id PK
        int service_id FK
        text billing_month
        text invoice_date
        real plan_charge_aud
        real excess_usage_aud
        real discount_aud
        real total_amount_aud
        text payment_status
        int days_late
    }

    USAGE_MONTHLY {
        int usage_id PK
        int service_id FK
        text usage_month
        real data_gb
        int voice_minutes
        int sms_count
        real roaming_gb
        int days_active
    }

    SUPPORT_TICKETS {
        int ticket_id PK
        int service_id FK
        int customer_id FK
        text created_date
        text resolved_date
        text issue_category
        text priority
        text contact_channel
        real resolution_hours
        int csat_score
    }

    CAMPAIGNS {
        int campaign_id PK
        text campaign_name
        text campaign_type
        text start_date
        text end_date
        text target_segment
        text offer_type
        real offer_value_aud
        real budget_aud
    }

    CAMPAIGN_CONTACTS {
        int contact_id PK
        int campaign_id FK
        int service_id FK
        text contact_date
        text contact_channel
        int response_flag
        int retained_30d_flag
        real contact_cost_aud
    }
```

---

## How to read this model

**`SERVICES` is the hub.** Six of the nine tables join to it. Any question about churn, revenue or behaviour resolves to a service, and almost every query in this project starts or passes through this table.

**Revenue is deliberately split.** `RECHARGES` holds prepaid revenue as irregular events; `INVOICES` holds postpaid revenue as regular monthly bills. There is no single revenue table, because in reality there is no single billing system. Any blended revenue or ARPU figure requires a `UNION ALL` of the two.

**Churn is asymmetric.** Postpaid churn is a stored fact — `SERVICES.deactivation_date`. Prepaid churn is not stored anywhere; it must be derived from gaps in `RECHARGES.recharge_date` under Decision D1. This asymmetry drives most of the SQL difficulty in Phase 4, and it is intentional.

---

## The join paths you will use most

```mermaid
flowchart LR
    A[recharges] -->|service_id| B[services]
    B -->|customer_id| C[customers]
    B -->|plan_id| D[plans]
    E[invoices] -->|service_id| B
    F[usage_monthly] -->|service_id| B
    G[support_tickets] -->|service_id| B
    H[campaign_contacts] -->|service_id| B
    H -->|campaign_id| I[campaigns]
```

| Question | Path |
|---|---|
| Prepaid revenue by state | recharges → services → customers |
| Postpaid revenue by plan family | invoices → services → plans |
| Blended ARPU | (recharges ∪ invoices) → services |
| Churn by segment | services → customers (+ derived churn from recharges) |
| Usage decay before churn | usage_monthly → services |
| Campaign ROI | campaign_contacts → campaigns, and → services for revenue |

Note that a question phrased in **business** terms ("revenue by state") maps to a **three-table** join, because revenue and geography sit at opposite ends of the model. Recognising that translation quickly is most of what SQL fluency actually is.
