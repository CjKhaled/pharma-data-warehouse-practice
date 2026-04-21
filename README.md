# Pharma Sales Force Analytics — Data Warehouse

**A dimensional data warehouse modeling the core analytics operations of a pharmaceutical sales organization, built to demonstrate production-grade SQL, dimensional modeling, and query optimization techniques.**

**This is just a practice project- not indicitive of a real organization or company in anyway.**

**All data is generated- none of it is real.**

Sources
- [Building a healthcare data warehouse: considerations, opportunities, and challenges](https://pmc.ncbi.nlm.nih.gov/articles/PMC12748234/)
- [The Key To Commercial Success In Pharma](https://www.iqvia.com/-/media/iqvia/pdfs/library/white-papers/information-management-the-key-to-commercial-success-in-pharma.pdf)
- [Powering biopharma launches with a strong commercial data foundation](https://www.pmsa.org/webinars/webinar-archive/item/powering-biopharma-launches-with-a-strong-commercial-data-foundation?category_id=3)

---

## Background

Pharmaceutical companies operate one of the most data-intensive sales models in any industry. Unlike consumer or B2B sales, a pharma sales force cannot directly sell to its end customer. A Territory Business Manager cannot hand a prescription pad to a physician and close a deal. Instead, the entire commercial operation runs on influence: reps visit physicians, physicians — called Healthcare Providers, or HCPs — develop familiarity with a drug, and that familiarity eventually translates into prescriptions written for patients.

This model generates data at every step. Reps log visits in a CRM. Prescription volume arrives weekly from third-party data vendors like IQVIA or Symphony Health, who aggregate dispensing records from pharmacies nationwide. Quota targets live in an incentive compensation system configured by Finance. Market assessment, promotional activity, sample distribution, and patient enrollment each produce their own data streams. The result, for most pharma organizations, is not a shortage of data — it is an excess of it. Data that is too complex, too expensive, too disparate, and too rarely comparable to generate reliable insight on its own.

A data warehouse is the infrastructure that resolves this. By integrating, standardizing, and centralizing these sources into a single analytical environment, it gives commercial teams the consistent, integrated view of the market that fragmented source systems cannot provide. Without it, organizations end up with multiple conflicting views of the same reality — and no principled way to decide which one to act on.

The stakeholders who depend on this infrastructure span the entire organization:

**Clinicians and medical affairs teams** need timely access to HCP engagement data and outcome information to support evidence-based conversations and track the impact of medical education programs.

**Commercial sales teams** — the field force and the district managers overseeing them — need daily visibility into visit activity, prescription trends, and quota attainment by territory to coach their reps and identify where to focus.

**Brand and marketing teams** need market share data, patient segment analysis, and promotional response metrics to assess whether their commercial strategy is working and where to reallocate spend.

**Finance and commercial operations** need quota attainment data tied to a fiscal calendar, territory alignment history, and incentive compensation inputs that are accurate and auditable.

**Senior leadership** needs a single source of truth — not four teams reporting four different numbers for the same metric — to make resourcing decisions and communicate performance to the board.

The challenge these stakeholders share is not access to raw data. It is the absence of infrastructure that makes the data useful. A commercial data warehouse is the answer to that absence. This project is that warehouse, modeled from the ground up.

---

## Warehouse Diagram

![ER Diagram](/docs/er_diagram.png)

---

## Query Results

### Below-quota rep coverage analysis
13 reps fell below 80% quota in FQ1 FY2024. Two reps (Sarah Chen, Marcus Williams) made zero
field visits — a complete disengagement problem. The other 11 were active but called on the
wrong physicians, skipping all their A-tier targets. These are two distinct issues requiring
different management responses.

### Rolling 13-week prescription trend
Across 223 A/B-tier physicians (June–October 2023), weekly prescription trends were volatile
but stable at the population level — no systemic growth or decline across Keytruda, Humira,
or Ozempic. Useful as a baseline to spot outlier physicians.

### Rep quota attainment ranking within district
The Mid-Atlantic District had the widest performance gap (48 points between first and last).
The Northeast was the most competitive, with even bottom-ranked reps posting strong numbers.
Marcus Williams and Sarah Chen ranked last in their respective districts across all three
products, well below district averages.

### Territory transfer historical attribution
James Rivera's transfer from Northeast Boston to Southwest Dallas (March 1, 2024) was correctly
handled — visits are attributed to whichever territory was active at the time, while a separate
column always reflects his current assignment. Both historical and current views come from the
same dimension.

### Co-promotion credit split
Dr. Robert Kim is shared by Sarah Chen (60%) and James Rivera (40%) for Keytruda. Without the
bridge table, both reps would claim full credit, doubling the prescription count. With it,
credit is correctly split: ~4,621 prescriptions to Chen and ~3,081 to Rivera.

### HCP segment tier upgrade impact
Dr. Patricia Moore's reclassification from B-tier to A-tier (January 15, 2024) was justified
for Humira (weekly volume nearly doubled, +91.6%) but not for Keytruda (−53.7%) or Ozempic
(−51.3%), where volume roughly halved post-upgrade.

### Year-over-year quota attainment comparison
Performance was mixed across all four districts — no uniform trend up or down. Ozempic showed
the strongest growth overall. Humira and Keytruda varied sharply within the same districts,
pointing to territory-level factors. Sarah Chen and Marcus Williams posted the steepest
year-over-year declines in their districts, compounding on already-weak current performance.

### HCP decile ranking writeback validation
892 of 1,005 physician-product combinations are flagged as mismatched. The stored rankings are
completely inverted relative to actual prescription volume because they were randomly seeded
with no connection to real data. Every physician in the dataset needs a refresh.

### Product indication expansion impact
Humira's FDA approval for a second indication (November 1, 2023) should have enabled a
before/after comparison, but pre-expansion prescription rows were not loaded against the correct
product key. Only post-expansion data is present. The fix requires re-pointing pre-November
Humira prescriptions to the correct product record.

### Data quality audit — superseded batch investigation
A vendor error inflated IQVIA unit counts for the week ending March 3, 2024. 697 rows across
all products and physicians were affected, with some inflation reaching thousands of percent
(e.g., 7,859% for one Keytruda row). Errors ran in both directions — some rows were undercounted
in the original. Without the audit dimension's superseded batch flag, both corrupt and corrected
data would be indistinguishable in the warehouse.

---

## Optimization Summary

### Below-quota rep coverage analysis
Execution time: 1.432ms, all data served from cache. The plan uses sequential scans on
visit and quota tables, with index lookups on products, HCPs, and reps. Flagged as acceptable.

### Rolling 13-week prescription trend
Execution time: 58.902ms — the slowest acceptable query. Two window function passes handle
the rolling average and LAG calculations. A bitmap index on (week_end_date_key, hcp_key,
product_key) pre-filters 21,961 prescription rows before joining to HCP and product
dimensions. Flagged as acceptable.

### Rep quota attainment ranking within district
Execution time: 0.946ms. Three window function passes compute DENSE_RANK, PERCENT_RANK,
and AVG. Incremental sorts reuse pre-sorted keys to avoid redundant work. Flagged as
acceptable.

### Territory transfer historical attribution
Execution time: 0.760ms. Two window function passes handle visit counts by period. A full
scan of 4,743 visit rows is filtered down to a single rep via dim_rep, with small dimension
tables for territory and product. Flagged as acceptable.

### Co-promotion credit split
Execution time: 7.889ms, but structurally problematic. A sequential scan removes 110,283
rows to return 219 — a 99.8% rejection rate. At current data size this is cheap, but would
degrade severely at scale. Flagged as needing an index.

### HCP segment tier upgrade impact
Execution time: 1.931ms. Two SCD rows for the target physician drive two bitmap heap scan
loops totaling 146 rows. A memoized product lookup avoids repeated scans of the small
product table. Flagged as acceptable.

### Year-over-year quota attainment comparison
Execution time: 0.564ms — the fastest query. Incremental sorts reuse presorted district
keys. A window function computes the cumulative YoY growth running total. Flagged as
acceptable.

### Data quality audit — superseded batch investigation
Execution time: 4.055ms. A bitmap index scan isolates the 697 affected rows for the
March 3, 2024 batch. A chain of four nested loops joins those rows to the audit, product,
corrected batch, and HCP dimensions. The audit dimension is almost entirely memoized
(696 of 697 hits). Flagged as acceptable.

### Market share trend by territory
Execution time: 1.653ms. A small 648-row aggregate fact table drives the plan. Two window
function passes handle LAG for prior-month share and the rolling 3-month average, with a
third for territory ranking within district. Flagged as acceptable.

### HCP decile ranking writeback validation
Execution time: 21.499ms. A full scan of all 110,502 prescription rows is required to
accurately compute NTILE(10) decile rankings across the entire physician population. 892
of 1,005 physician-product combinations are flagged as mismatched. Flagged as correct and
expected behavior.

### Product indication expansion impact
Execution time: 36.946ms. A pre-aggregation step before the HCP join reduced the sort
buffer from 3,800kB to 72kB, eliminating a disk spill. 111,300 prescription rows are
scanned; 75,073 are removed to isolate 36,227 Humira rows. Flagged as acceptable.

### Key findings

**Query 5** is the only structural concern. The full scan of 110,283 rows to return 219 is
invisible at current data size but will degrade badly at scale. An index on
(hcp_key, week_end_date_key) is the fix.

**Query 10** intentionally scans all rows — this is correct behavior for a population-level
decile ranking calculation.

**Index test results:** Adding the index on fct_prescription_weekly in the correct column
order (hcp_key first, then week_end_date_key) reduced Query 5 execution from 7.889ms to
1.663ms — a 4.7x improvement — and cut pages read from 272 to 5. The wrong column order
(date first) produced only a marginal improvement (7.461ms) because the planner couldn't
use the HCP equality condition as an access predicate.
