# Phase 3 — Data Model

Nine tables at service grain, plus the code that generates the data.

| File | Contents |
|---|---|
| [data_dictionary.md](./data_dictionary.md) | Field-level specification, analytical notes and design rationale |
| [er_diagram.md](./er_diagram.md) | Mermaid ER diagram and the join paths used most |
| [schema.sql](./schema.sql) | DDL with constraints and indexes (SQLite) |
| [seed_data.sql](./seed_data.sql) | 40-customer seed dataset as INSERT statements |
| [generate_data.py](./generate_data.py) | Generator — reproducible, scalable |
| [data/](./data) | CSV extract per table, for pandas in Phases 5–8 |

## Load order

1. `schema.sql`
2. `seed_data.sql`

## Verify the load

```sql
SELECT 'customers' AS t, COUNT(*) FROM customers
UNION ALL SELECT 'plans', COUNT(*) FROM plans
UNION ALL SELECT 'services', COUNT(*) FROM services
UNION ALL SELECT 'recharges', COUNT(*) FROM recharges
UNION ALL SELECT 'invoices', COUNT(*) FROM invoices
UNION ALL SELECT 'usage_monthly', COUNT(*) FROM usage_monthly
UNION ALL SELECT 'support_tickets', COUNT(*) FROM support_tickets
UNION ALL SELECT 'campaigns', COUNT(*) FROM campaigns
UNION ALL SELECT 'campaign_contacts', COUNT(*) FROM campaign_contacts;
```

Expected: 40, 10, 51, 250, 472, 735, 40, 6, 71.

## Scale up

```bash
python generate_data.py --customers 5000
```

The generator is calibrated to reproduce the FY25 business case — 62/38 service
mix, ARPU declining from ~AUD 44 to ~AUD 40, prepaid churning harder than
postpaid. Verify any regeneration against those figures rather than assuming.
