"""
Waratah Telecom - Synthetic Dataset Generator
==============================================
Generates a realistic, referentially-consistent synthetic dataset for the
Subscriber Churn & ARPU Recovery Analysis project.

Design notes (these are deliberate, and are interview talking points):
  * SERVICE grain. A customer may hold more than one service. All revenue,
    usage, and churn logic lives at service level, not customer level.
  * Prepaid churn is NOT stored as a flag. It must be DERIVED from gaps
    between recharge dates (D1: 60 consecutive days with no recharge and no
    billable usage). This forces window-function SQL in Phase 4.
  * Revenue lives in TWO tables - recharges (prepaid) and invoices (postpaid).
    Blended ARPU therefore requires a UNION, not a single SUM.
  * All dates are TEXT in 'YYYY-MM-DD' format for SQLite compatibility.

Usage:
    python generate_data.py                    # 40 customers (default seed set)
    python generate_data.py --customers 5000   # scale up for Phase 5+
    python generate_data.py --customers 5000 --out ./data_large

Outputs:
    seed_data.sql   - INSERT statements, load after schema.sql
    data/*.csv      - one CSV per table, for pandas in Phases 5-8
"""

import argparse
import csv
import os
import random
from datetime import date, timedelta

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------
START_DATE = date(2024, 1, 1)
END_DATE = date(2025, 6, 30)
RANDOM_SEED = 42

STATES = [("NSW", 0.45), ("VIC", 0.33), ("QLD", 0.22)]
CITY_BY_STATE = {
    "NSW": ["Sydney", "Newcastle", "Wollongong", "Parramatta"],
    "VIC": ["Melbourne", "Geelong", "Ballarat", "Bendigo"],
    "QLD": ["Brisbane", "Gold Coast", "Townsville", "Cairns"],
}
POSTCODE_BY_STATE = {"NSW": (2000, 2799), "VIC": (3000, 3799), "QLD": (4000, 4799)}

FIRST_NAMES = [
    "Aisha", "Liam", "Priya", "Noah", "Chloe", "Jack", "Mia", "Ethan", "Ruby",
    "Oliver", "Sienna", "Hugo", "Isla", "Lachlan", "Zara", "Cooper", "Maya",
    "Xavier", "Amelia", "Finn", "Layla", "Angus", "Grace", "Riley", "Anika",
    "Declan", "Freya", "Tomas", "Harper", "Nikhil", "Willow", "Marcus",
    "Georgia", "Elias", "Tahlia", "Rohan", "Evie", "Blake", "Sofia", "Callum",
]
LAST_NAMES = [
    "Nguyen", "Smith", "Patel", "Brown", "Wilson", "Taylor", "Singh", "Lee",
    "Martin", "Thompson", "Walker", "Harris", "Chen", "Robinson", "Kelly",
    "Ryan", "Murphy", "Anderson", "Clarke", "Wright", "Baker", "Ali",
    "Campbell", "Mitchell", "Hughes", "Rossi", "Silva", "Okafor", "Kaur",
    "Reid", "Foster", "Hayes", "Barnes", "Ellis", "Grant", "Sharma",
    "OBrien", "Dixon", "Novak", "Webb",
]

ACQ_CHANNELS = ["Online", "Retail Store", "Telesales", "Partner Reseller", "Referral"]
CREDIT_BANDS = ["Low Risk", "Medium Risk", "High Risk"]

# Plans: plan_id, name, type, price, data_gb, contract_months, family
PLANS = [
    (1,  "Waratah Starter 10",   "Prepaid",  10.00,   3.0,  0, "Starter"),
    (2,  "Waratah Value 20",     "Prepaid",  20.00,  15.0,  0, "Value"),
    (3,  "Waratah Value 30",     "Prepaid",  30.00,  35.0,  0, "Value"),
    (4,  "Waratah Max 40",       "Prepaid",  40.00,  60.0,  0, "Max"),
    (5,  "Waratah Max 50",       "Prepaid",  50.00, 100.0,  0, "Max"),
    (6,  "Waratah Essential 39", "Postpaid", 39.00,  20.0, 12, "Essential"),
    (7,  "Waratah Everyday 49",  "Postpaid", 49.00,  50.0, 12, "Everyday"),
    (8,  "Waratah Everyday 59",  "Postpaid", 59.00,  80.0, 24, "Everyday"),
    (9,  "Waratah Premium 79",   "Postpaid", 79.00, 150.0, 24, "Premium"),
    (10, "Waratah Business 99",  "Postpaid", 99.00, 250.0, 24, "Business"),
]

PLAN_BY_ID = {p[0]: p for p in PLANS}

# Plan-mix weights. Calibrated so postpaid ARPU lands near AUD 50 and prepaid
# near AUD 26, giving a blended ARPU in the AUD 40-44 band described in the
# FY25 business case. Most subscribers sit on entry/mid plans, not premium.
PREPAID_PLAN_WEIGHTS = [(1, 0.18), (2, 0.30), (3, 0.28), (4, 0.15), (5, 0.09)]
POSTPAID_PLAN_WEIGHTS = [(6, 0.42), (7, 0.32), (8, 0.16), (9, 0.08), (10, 0.02)]
POSTPAID_PLAN_WEIGHTS_SMB = [(6, 0.18), (7, 0.28), (8, 0.26), (9, 0.18), (10, 0.10)]

# Target share of services on postpaid, matching the FY25 base mix (62/38).
TARGET_POSTPAID_SHARE = 0.62
# Total ARPU erosion across the window, reproducing the AUD 44.20 -> 40.10
# decline in the business case (~9% fall). Applied as a time-linear drift.
ARPU_DRIFT = 0.10

RECHARGE_CHANNELS = ["App", "Website", "Retail Store", "Auto-Recharge", "Third Party"]
ISSUE_CATEGORIES = [
    "Billing Dispute", "Network Coverage", "Data Speed", "Plan Change",
    "Device/SIM Fault", "Porting Request", "Credit/Refund",
]
TICKET_CHANNELS = ["Phone", "Chat", "Email", "Retail Store", "Social"]

CAMPAIGNS = [
    (1, "Q1 FY25 Prepaid Winback",      "Winback",   "2024-08-01", "2024-09-30",
     "Prepaid Lapsed",        "Bonus Credit", 15.00, 120000.00),
    (2, "Loyalty Data Boost",           "Retention", "2024-10-01", "2024-12-31",
     "Postpaid Tenure 12m+",  "Data Bonus",    8.00,  95000.00),
    (3, "High Value Save Desk",         "Retention", "2024-11-01", "2025-06-30",
     "Top Value Decile",      "Bill Credit",  45.00, 210000.00),
    (4, "Prepaid Auto-Recharge Push",   "Retention", "2025-01-15", "2025-04-30",
     "Prepaid Manual Payers", "Bonus Credit", 10.00,  70000.00),
    (5, "SMB Contract Renewal Drive",   "Upsell",    "2025-02-01", "2025-06-30",
     "SMB Postpaid",          "Plan Upgrade", 20.00, 140000.00),
    (6, "Network Complaint Save Offer", "Retention", "2025-03-01", "2025-06-30",
     "Complaint Raisers",     "Bill Credit",  25.00,  60000.00),
]


# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
def weighted_choice(pairs):
    r = random.random()
    cum = 0.0
    for value, weight in pairs:
        cum += weight
        if r <= cum:
            return value
    return pairs[-1][0]


def rand_date(start, end):
    delta = (end - start).days
    return start + timedelta(days=random.randint(0, max(delta, 0)))


def month_starts(start, end):
    out = []
    y, m = start.year, start.month
    while date(y, m, 1) <= end:
        out.append(date(y, m, 1))
        m += 1
        if m > 12:
            m = 1
            y += 1
    return out


def time_fraction(d):
    """0.0 at the start of the window, 1.0 at the end. Drives ARPU drift."""
    span = (END_DATE - START_DATE).days
    return min(1.0, max(0.0, (d - START_DATE).days / span))


def sql_str(v):
    if v is None:
        return "NULL"
    if isinstance(v, (int, float)):
        return str(v)
    return "'" + str(v).replace("'", "''") + "'"


# --------------------------------------------------------------------------
# Generation
# --------------------------------------------------------------------------
def generate(n_customers):
    random.seed(RANDOM_SEED)
    months = month_starts(START_DATE, END_DATE)

    customers, services, recharges, invoices = [], [], [], []
    usage, tickets, contacts = [], [], []

    svc_id = rch_id = inv_id = usg_id = tkt_id = con_id = 0
    postpaid_count = 0

    for cid in range(1, n_customers + 1):
        state = weighted_choice(STATES)
        city = random.choice(CITY_BY_STATE[state])
        pc_lo, pc_hi = POSTCODE_BY_STATE[state]
        segment = "SMB" if random.random() < 0.18 else "Consumer"
        acq_date = rand_date(date(2019, 1, 1), date(2025, 3, 31))
        birth_year = random.randint(1960, 2005)

        customers.append({
            "customer_id": cid,
            "first_name": FIRST_NAMES[(cid - 1) % len(FIRST_NAMES)],
            "last_name": LAST_NAMES[(cid * 7 - 1) % len(LAST_NAMES)],
            "date_of_birth": date(birth_year, random.randint(1, 12),
                                  random.randint(1, 28)).isoformat(),
            "state": state,
            "city": city,
            "postcode": str(random.randint(pc_lo, pc_hi)),
            "customer_segment": segment,
            "acquisition_channel": random.choice(ACQ_CHANNELS),
            "acquisition_date": acq_date.isoformat(),
            "credit_risk_band": weighted_choice(
                [("Low Risk", 0.6), ("Medium Risk", 0.3), ("High Risk", 0.1)]),
        })

        if segment == "SMB":
            n_services = random.choices([1, 2, 3], weights=[0.4, 0.4, 0.2])[0]
        else:
            n_services = random.choices([1, 2], weights=[0.85, 0.15])[0]

        for _ in range(n_services):
            svc_id += 1
            # Calibration note: SMB customers hold more services AND skew
            # postpaid, so a flat 62% probability over-weights postpaid at the
            # SERVICE grain. We start from a segment-specific rate, then apply
            # a self-correcting nudge toward the 62/38 target so that small
            # datasets (n=40) don't drift far off the stated base mix.
            base_rate = 0.80 if segment == "SMB" else 0.55
            running = (postpaid_count / (svc_id - 1)) if svc_id > 1 else TARGET_POSTPAID_SHARE
            rate = base_rate + (TARGET_POSTPAID_SHARE - running) * 0.9
            is_postpaid = random.random() < min(0.95, max(0.05, rate))
            if is_postpaid:
                postpaid_count += 1

            if is_postpaid:
                plan_id = weighted_choice(POSTPAID_PLAN_WEIGHTS_SMB if segment == "SMB"
                                          else POSTPAID_PLAN_WEIGHTS)
            else:
                plan_id = weighted_choice(PREPAID_PLAN_WEIGHTS)
            plan = PLAN_BY_ID[plan_id]
            plan_id, _, plan_type, price, data_gb, contract_m, _ = plan

            act_date = max(acq_date, START_DATE - timedelta(days=random.randint(0, 900)))
            if act_date > END_DATE:
                act_date = rand_date(START_DATE, date(2025, 3, 31))

            # ---- Churn assignment --------------------------------------
            # Prepaid churns harder than postpaid, matching the FY25 story.
            # Cumulative churn over the 18-month window implied by the FY25
            # monthly rates: prepaid 3.1%/mo -> ~43% cumulative,
            # postpaid ~2.2%/mo -> ~33% cumulative.
            churn_prob = 0.42 if plan_type == "Prepaid" else 0.30
            churns = random.random() < churn_prob
            churn_day = None
            if churns:
                # Churn dates skew LATER in the window, reproducing the rising
                # churn trend (1.6% -> 2.6%) that triggered this project.
                # A service cannot churn before it was activated, and we
                # require at least 60 days of life so there is behaviour to
                # analyse. Services activated too late simply do not churn
                # inside the window.
                c_start = max(date(2024, 6, 1), act_date + timedelta(days=60))
                c_end = date(2025, 4, 30)
                if c_start > c_end:
                    churns = False
                else:
                    span = (c_end - c_start).days
                    churn_day = c_start + timedelta(
                        days=int(span * (random.random() ** 0.6)))

            deactivation_date = None
            status = "Active"
            if churns and plan_type == "Postpaid":
                deactivation_date = churn_day.isoformat()
                status = "Deactivated"
            # NOTE: churned prepaid services stay 'Active' in the source
            # system. There is deliberately NO churn flag - the analyst must
            # derive it from the recharge gap (Decision D1).

            services.append({
                "service_id": svc_id,
                "customer_id": cid,
                "plan_id": plan_id,
                "msisdn": "04" + str(10000000 + svc_id * 137 % 89999999),
                "activation_date": act_date.isoformat(),
                "deactivation_date": deactivation_date,
                "service_status": status,
                "device_type": random.choice(
                    ["Handset - Subsidised", "Handset - Outright", "BYO Device",
                     "Mobile Broadband"]),
                "is_byo": 1 if random.random() < 0.45 else 0,
                "port_in_flag": 1 if random.random() < 0.28 else 0,
            })

            last_active_day = churn_day if churn_day else END_DATE

            # ---- Revenue -------------------------------------------------
            if plan_type == "Prepaid":
                denominations = [10.0, 20.0, 30.0, 40.0, 50.0]
                # SLEEPERS. A minority of surviving prepaid services take one
                # long break from recharging (60-88 days) and then come back -
                # travel, a spare SIM, or living off rollover balance. They
                # keep generating usage throughout.
                #
                # This is the whole reason Decision D1 says "no recharge AND no
                # billable usage". A rule based on recharge gaps alone would
                # wrongly mark every one of these services as churned. The
                # usage condition is what separates a sleeper from a leaver,
                # and this data deliberately contains both.
                is_sleeper = (not churns) and random.random() < 0.22
                sleep_used = False
                cur = max(act_date, START_DATE)
                while cur <= min(last_active_day, END_DATE):
                    amt = price if random.random() < 0.75 else \
                        random.choice(denominations)
                    # ARPU erosion: as the window progresses, subscribers
                    # increasingly step DOWN a recharge denomination
                    # (competitive repricing pressure).
                    if random.random() < 0.45 * time_fraction(cur):
                        idx = denominations.index(amt) if amt in denominations else 0
                        amt = denominations[max(0, idx - 1)]
                    rch_id += 1
                    recharges.append({
                        "recharge_id": rch_id,
                        "service_id": svc_id,
                        "recharge_date": cur.isoformat(),
                        "amount_aud": round(amt, 2),
                        "recharge_channel": random.choice(RECHARGE_CHANNELS),
                        "recharge_type": "Auto" if random.random() < 0.3 else "Manual",
                    })
                    # Normal cycle is 26-38 days. A sleeper takes exactly one
                    # extended break, placed mid-series so it is a true gap
                    # rather than trailing dormancy.
                    if is_sleeper and not sleep_used and \
                            date(2024, 5, 1) <= cur <= date(2025, 2, 28):
                        cur += timedelta(days=random.randint(62, 88))
                        sleep_used = True
                    else:
                        cur += timedelta(days=random.randint(26, 38))
            else:
                for ms in months:
                    if ms < date(act_date.year, act_date.month, 1):
                        continue
                    if churn_day and ms > date(churn_day.year, churn_day.month, 1):
                        continue
                    excess = round(random.choice([0, 0, 0, 5, 10, 15]) * random.random(), 2)
                    # ARPU erosion: retention discounting deepens over the
                    # window as the base comes under competitive pressure.
                    disc_rate = random.choice([0, 0, 0, 0.10, 0.15]) \
                        + ARPU_DRIFT * time_fraction(ms)
                    disc = round(price * min(disc_rate, 0.35), 2)
                    total = round(price + excess - disc, 2)
                    inv_id += 1
                    invoices.append({
                        "invoice_id": inv_id,
                        "service_id": svc_id,
                        "billing_month": ms.isoformat(),
                        "invoice_date": (ms + timedelta(days=4)).isoformat(),
                        "plan_charge_aud": round(price, 2),
                        "excess_usage_aud": excess,
                        "discount_aud": disc,
                        "total_amount_aud": total,
                        "payment_status": weighted_choice(
                            [("Paid", 0.88), ("Late", 0.09), ("Unpaid", 0.03)]),
                        "days_late": random.choice([0, 0, 0, 0, 3, 8, 17, 31]),
                    })

            # ---- Usage ---------------------------------------------------
            for ms in months:
                if ms < date(act_date.year, act_date.month, 1):
                    continue
                if churn_day and ms > date(churn_day.year, churn_day.month, 1):
                    continue
                decay = 1.0
                if churn_day:
                    m_to_churn = (churn_day.year - ms.year) * 12 + (churn_day.month - ms.month)
                    if 0 <= m_to_churn <= 3:
                        decay = 0.25 + 0.25 * m_to_churn
                usg_id += 1
                usage.append({
                    "usage_id": usg_id,
                    "service_id": svc_id,
                    "usage_month": ms.isoformat(),
                    "data_gb": round(max(0.0, random.gauss(data_gb * 0.55, data_gb * 0.2)) * decay, 2),
                    "voice_minutes": int(max(0, random.gauss(180, 90)) * decay),
                    "sms_count": int(max(0, random.gauss(40, 30)) * decay),
                    "roaming_gb": round(random.choice([0, 0, 0, 0, 0.4, 1.2]) * decay, 2),
                    "days_active": int(min(30, max(1, random.gauss(28, 4)) * decay)),
                })

            # ---- Support tickets -----------------------------------------
            if churns:
                n_tickets = random.choices([0, 1, 2, 3, 4],
                                           weights=[0.30, 0.28, 0.20, 0.14, 0.08])[0]
            else:
                n_tickets = random.choices([0, 1, 2], weights=[0.62, 0.28, 0.10])[0]

            for _ in range(n_tickets):
                created = rand_date(max(act_date, START_DATE),
                                    min(last_active_day, END_DATE))
                res_hours = round(abs(random.gauss(20, 26)) + 0.5, 1)
                resolved = created + timedelta(days=int(res_hours // 24))
                tkt_id += 1
                tickets.append({
                    "ticket_id": tkt_id,
                    "service_id": svc_id,
                    "customer_id": cid,
                    "created_date": created.isoformat(),
                    "resolved_date": resolved.isoformat() if random.random() < 0.92 else None,
                    "issue_category": random.choice(ISSUE_CATEGORIES),
                    "priority": weighted_choice(
                        [("Low", 0.3), ("Medium", 0.4), ("High", 0.22), ("Critical", 0.08)]),
                    "contact_channel": random.choice(TICKET_CHANNELS),
                    "resolution_hours": res_hours,
                    "csat_score": random.choices([1, 2, 3, 4, 5],
                                                 weights=[0.12, 0.13, 0.20, 0.30, 0.25])[0],
                })

            # ---- Campaign contacts ----------------------------------------
            for camp in CAMPAIGNS:
                camp_id = camp[0]
                cs = date.fromisoformat(camp[3])
                ce = date.fromisoformat(camp[4])
                if random.random() > 0.22:
                    continue
                if act_date > ce:
                    continue
                contact_day = rand_date(max(cs, act_date), ce)
                responded = 1 if random.random() < 0.31 else 0
                retained = 1 if (responded and random.random() < 0.74) or \
                                (not responded and random.random() < 0.41) else 0
                con_id += 1
                contacts.append({
                    "contact_id": con_id,
                    "campaign_id": camp_id,
                    "service_id": svc_id,
                    "contact_date": contact_day.isoformat(),
                    "contact_channel": random.choice(
                        ["SMS", "Email", "Outbound Call", "App Push"]),
                    "response_flag": responded,
                    "retained_30d_flag": retained,
                    "contact_cost_aud": round(random.choice([0.08, 0.15, 3.50, 0.05]), 2),
                })

    plans = [{
        "plan_id": p[0], "plan_name": p[1], "plan_type": p[2],
        "monthly_price_aud": p[3], "included_data_gb": p[4],
        "contract_months": p[5], "plan_family": p[6], "is_active": 1,
    } for p in PLANS]

    campaigns = [{
        "campaign_id": c[0], "campaign_name": c[1], "campaign_type": c[2],
        "start_date": c[3], "end_date": c[4], "target_segment": c[5],
        "offer_type": c[6], "offer_value_aud": c[7], "budget_aud": c[8],
    } for c in CAMPAIGNS]

    return {
        "customers": customers,
        "plans": plans,
        "services": services,
        "recharges": recharges,
        "invoices": invoices,
        "usage_monthly": usage,
        "support_tickets": tickets,
        "campaigns": campaigns,
        "campaign_contacts": contacts,
    }


TABLE_ORDER = [
    "customers", "plans", "services", "recharges", "invoices",
    "usage_monthly", "support_tickets", "campaigns", "campaign_contacts",
]


def write_sql(data, path):
    with open(path, "w", encoding="utf-8") as f:
        f.write("-- Waratah Telecom - seed data\n")
        f.write("-- Generated by generate_data.py. Load AFTER schema.sql.\n")
        f.write("-- Dialect: SQLite. Dates stored as TEXT 'YYYY-MM-DD'.\n\n")
        f.write("BEGIN TRANSACTION;\n\n")
        for table in TABLE_ORDER:
            rows = data[table]
            if not rows:
                continue
            cols = list(rows[0].keys())
            f.write("-- {}: {} rows\n".format(table, len(rows)))
            for i in range(0, len(rows), 200):
                chunk = rows[i:i + 200]
                f.write("INSERT INTO {} ({}) VALUES\n".format(table, ", ".join(cols)))
                vals = ["  (" + ", ".join(sql_str(r[c]) for c in cols) + ")"
                        for r in chunk]
                f.write(",\n".join(vals) + ";\n")
            f.write("\n")
        f.write("COMMIT;\n")


def write_csvs(data, outdir):
    os.makedirs(outdir, exist_ok=True)
    for table in TABLE_ORDER:
        rows = data[table]
        if not rows:
            continue
        with open(os.path.join(outdir, table + ".csv"), "w",
                  newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--customers", type=int, default=40)
    ap.add_argument("--out", default=os.path.dirname(os.path.abspath(__file__)))
    args = ap.parse_args()

    data = generate(args.customers)
    write_sql(data, os.path.join(args.out, "seed_data.sql"))
    write_csvs(data, os.path.join(args.out, "data"))

    print("Generated dataset for {} customers:".format(args.customers))
    for t in TABLE_ORDER:
        print("  {:<20} {:>7,} rows".format(t, len(data[t])))


if __name__ == "__main__":
    main()
