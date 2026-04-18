# Dimensional Model — Pharma Sales Force Analytics Data Warehouse

## 1. Business Process Selection

A business process is a specific, measurable event that the business actually cares about
tracking. Each business process maps to a separate fact table. We apply Kimball's test:
can we point to a single moment in time when this event occurred, and did it produce a row
of data when it happened?

### In Scope

| # | Business Process | Description |
|---|---|---|
| 1 | HCP Visit Activity | A sales rep visits a physician and logs the interaction |
| 2 | Prescription Volume | A physician writes a prescription for a drug product |
| 3 | Quota Attainment | A fiscal quarter closes and actual volume is compared against target |

### Scoped Out

The following business processes were identified but excluded because this is a practice project.
Each would justify its own fact table in a real implementation.

| Business Process | Reason for Exclusion |
|---|---|
| Sample distribution | Sample tracking lives inside fct_hcp_visit as a measure (samples_dropped). A dedicated sample fact table would be warranted if sample compliance reporting were a primary use case |
| Patient enrollment | Requires patient-level data not modeled here — patient, specialty pharmacy, and program dimensions would all need to be built from scratch |
| Market assessment / claims | Pre-launch sizing exercise requiring external claims data outside the scope of this warehouse |
| Promotional activity | Speaker programs and marketing campaigns require a separate campaign dimension and response metrics not present in this dataset |

---

## 2. Grain Declarations

The grain is the single most important sentence written for each fact table. It defines
exactly what one row represents. All grains are declared at the most atomic level the
business captures.

### Grain Types Used

| Type | Behavior |
|---|---|
| Transaction | One row per discrete event. Row is inserted once and never changes |
| Periodic snapshot | One row per entity per time period, regardless of whether anything happened |
| Consolidated | Two or more related measures stored at the same grain on the same row |
| Factless | No numeric measures — the relationship between keys is the data |

### Fact Table Grains

| Fact Table | Type | Grain |
|---|---|---|
| `fct_hcp_visit` | Transaction | One row per sales rep visit to one HCP on one date |
| `fct_prescription_weekly` | Periodic snapshot | One row per HCP per product per week |
| `fct_quota_attainment` | Consolidated | One row per rep per product per fiscal quarter |
| `fct_hcp_coverage_target` | Factless | One row per rep-HCP-product coverage assignment per quarter |
| `fct_prescription_territory_monthly` | Aggregate | One row per territory per product per calendar month |

---

## 3. Fact Table Design Decisions

### fct_quota_attainment — Consolidated Pattern
Stores `actual_units` and `quota_units` at the same grain on the same row. This eliminates
the need to join two separate fact tables every time an attainment vs. quota comparison is
needed, which is the most common query this table serves.

### fct_quota_attainment — Timespan Tracking
Quota targets for a given rep-product combination frequently remain unchanged across multiple
consecutive quarters. Rather than inserting an identical row every quarter under a pure
periodic snapshot design, this table uses `effective_date` and `expiration_date` columns.
A new row is only inserted when the quota value actually changes. This eliminates redundant
storage while preserving full history.

### fct_prescription_territory_monthly — Aggregate Fact Table
A pre-computed territory-month rollup of `fct_prescription_weekly`. Built purely as a
performance layer — district manager trend queries run against this table instead of
scanning the full atomic table. Never loaded independently from source systems; rebuilt
nightly from the atomic table to prevent drift.

### fct_hcp_coverage_target — Factless Fact Table
Records which physicians each rep is assigned to visit each quarter. Contains no numeric
measures — the relationship itself is the data. Its analytical value comes from combining
it with `fct_hcp_visit` via a LEFT JOIN to surface targeted physicians who received zero
visits. This "what didn't happen" analysis is called coverage analysis and is one of the
primary reports a district manager uses to evaluate rep performance.

---

## 4. Dimension Table Design

### dim_date
Stores one row per calendar date with attributes for filtering and grouping.

| Attribute | SCD Type | Rationale |
|---|---|---|
| All date attributes | Type 0 | Dates never change |
| Fiscal quarter / fiscal year | Type 0 | Required — pharma runs on a July fiscal year. FY2024 begins July 2023 |

### dim_rep
Contains all descriptive attributes about a sales rep.

| Attribute | SCD Type | Rationale |
|---|---|---|
| Territory assignment | Type 6 | Territory reassignments are versioned (Type 2) with a current_territory column always overwritten (Type 1 overlay) to support both as-was and as-is reporting from the same dimension |
| Manager, title, district | Type 2 | Changes are meaningful business events worth preserving |

Carries a `territory_surrogate_key` as an outrigger foreign key pointing to `dim_territory`.
This prevents duplicating the full territory hierarchy inside `dim_rep`.

### dim_hcp
Contains all descriptive attributes about a physician.

| Attribute | SCD Type | Rationale |
|---|---|---|
| Segment tier (A/B/C/D) | Type 2 | Moving tiers is a meaningful business event — prescription response after reclassification must be measurable |
| Address | Type 1 | Historical address is not analytically meaningful |
| All other attributes | Type 1 | Corrections only, no versioning needed |

The NPI number is stored as the durable key. Every US physician carries a permanent NPI
that follows them across practice changes, ensuring the same physician resolves to the same
record across the CRM, Rx vendor files, and any other source system.

Banding is applied to `segment` and `decile_rank` — both are pre-calculated during ETL and
stored directly as attributes so business users can filter on prescribing tier without
performing inline aggregation.

### dim_product
Contains all descriptive attributes about a drug product.

| Attribute | SCD Type | Rationale |
|---|---|---|
| Launch date, patent expiry | Type 0 | Origin attributes — never overwritten even if entered incorrectly. Corrections documented separately |
| Market status (launched / withdrawn / pipeline) | Type 1 | Current status should always reflect current reality |
| Indication | Type 2 | FDA approval for a new indication is a significant commercial event that changes targeting and detailing strategy |

### dim_territory
Contains the fixed-depth geographic sales hierarchy.

| Level | Column |
|---|---|
| 1 | territory |
| 2 | district |
| 3 | region |
| 4 | zone |
| 5 | national |

SCD Type 0. Territory boundaries are treated as stable for this project. Each level is
stored as its own column rather than a recursive parent-child structure, making every
level directly queryable without a recursive CTE.

### dim_visit_flags — Junk Dimension
Bundles low-cardinality visit flags into a single dimension: planned vs. unplanned,
in-person vs. virtual, physician available vs. drop-off, standard call vs. lunch program.

Each unique combination of flag values occupies one row. The fact table carries a single
foreign key to this dimension instead of four separate flag columns. SCD Type 0 — new
visit types are handled by adding rows, not altering structure.

---

## 5. Dimension Table Strategies

### dim_call_notes — Text Handling
Rep call notes are recorded after every physician visit. Text is never stored in a fact
table. Since notes are unique per visit (1:1 with the transaction), a dedicated
`dim_call_notes` dimension holds the note text. `fct_hcp_visit` carries a `call_notes_key`
foreign key.

### dim_audit — Audit Dimension
Every row loaded into the three core fact tables carries an `audit_key` pointing to
`dim_audit`, which stores:

- ETL batch ID
- Load timestamp
- Source file name
- Data quality flag
- Transformation version

The data quality flag is particularly valuable for prescription data — when the Rx vendor
sends a corrected file, original rows are marked as superseded without deletion, and the
audit dimension records exactly which batch introduced the correction.

### Role-Playing Dimensions — dim_date
`fct_quota_attainment` references `dim_date` twice:

| Foreign Key | View | Role |
|---|---|---|
| `fiscal_quarter_key` | `vw_fiscal_quarter_date` | The quarter being measured |
| `prior_year_quarter_key` | `vw_prior_year_date` | The same quarter one year prior |

Each foreign key points to a separate view of `dim_date` with uniquely renamed columns.
This allows both date contexts to coexist in the same query without ambiguity.

### Conformed Dimensions — Drill-Across
The following dimensions are shared across multiple fact tables with identical keys and
domain values, enabling drill-across queries:

| Dimension | fct_hcp_visit | fct_prescription_weekly | fct_quota_attainment |
|---|---|---|---|
| `dim_hcp` | ✓ | ✓ | |
| `dim_product` | ✓ | ✓ | ✓ |
| `dim_date` | ✓ | ✓ | ✓ |
| `dim_territory` | | ✓ | ✓ |
| `dim_rep` | ✓ | | ✓ |

Drill-across example: *For reps below 80% quota attainment, are they also below average
on visits to their top-decile HCPs?* — requires joining `fct_quota_attainment` and
`fct_hcp_visit` through the shared `dim_rep` and `dim_hcp` dimensions.

### bridge_hcp_rep_alignment — Bridge Table
Sits between `fct_prescription_weekly` and `dim_rep` to handle co-promoted physicians —
cases where two reps share responsibility for the same HCP.

| Column | Purpose |
|---|---|
| `group_key` | Identifies the co-promotion group |
| `rep_surrogate_key` | Points to individual rep in dim_rep |
| `credit_split_weight` | 0.0–1.0, weights must sum to 1.0 per group |

Without the weight column, a 60/40 co-promoted physician would give both reps full
prescription credit, overstating total sales force performance.

### Shrunken Rollup Dimensions — Aggregate Fact Table
`fct_prescription_territory_monthly` operates at the territory-month grain. Two shrunken
dimensions support it:

**dim_territory_rollup** — strips dim_territory down to columns meaningful at the
territory summary level: `territory_key`, `territory_name`, `district`, `region`.

**dim_month** — strips dim_date down to columns meaningful at the monthly grain:
`month_key`, `month_name`, `quarter`, `fiscal_quarter`, `fiscal_year`.

### Error Event Schema — Scoped Out
An error event schema — containing an error event fact table at the grain of one row per
error event and an error event detail fact table at the grain of one row per column per
table — was identified as a production extension. It is scoped out here because the
project uses static seed data rather than a live ETL pipeline. Implementing it without
real data flowing through would produce an empty schema with no diagnostic value.

---

## 6. Bus Matrix

The bus matrix shows which dimensions each fact table shares. Shared dimensions are what
make drill-across queries possible.

| Dimension | `fct_hcp_visit` | `fct_prescription_weekly` | `fct_quota_attainment` | `fct_hcp_coverage_target` | `fct_prescription_territory_monthly` |
|---|---|---|---|---|---|
| `dim_date` | ✓ | ✓ | ✓ | ✓ | |
| `dim_rep` | ✓ | | ✓ | ✓ | |
| `dim_hcp` | ✓ | ✓ | | ✓ | |
| `dim_product` | ✓ | ✓ | ✓ | ✓ | |
| `dim_territory` | | ✓ | ✓ | | |
| `dim_visit_flags` | ✓ | | | | |
| `dim_call_notes` | ✓ | | | | |
| `dim_audit` | ✓ | ✓ | ✓ | | |
| `dim_month` | | | | | ✓ |
| `dim_territory_rollup` | | | | | ✓ |

---

## 7. Star Schema

*Diagram to be generated from schema.sql in Phase 2 and inserted here as er_diagram.png*

---

## 8. Design Decisions Log

A record of every meaningful design choice made and the alternative that was rejected.

| Decision | Choice Made | Alternative Rejected | Reason |
|---|---|---|---|
| Rep territory history | SCD Type 6 | Pure Type 2 | Type 6 supports both as-was and as-is reporting from one dimension without filtering to current row on every query |
| Physician identifier | NPI as durable key | Vendor-assigned ID | NPI is permanent and follows the physician across systems; vendor IDs differ across CRM, Rx files, and incentive comp |
| Prescription grain | HCP-product-week | HCP-product-day | Rx data is sold at the weekly grain by vendors — daily grain would fabricate precision the source data does not contain |
| Co-promotion credit | Bridge table with weight | Multiple rep foreign keys | Number of co-promoting reps per physician is unpredictable; bridge table scales to any number without schema changes |
| Call notes | Separate dim_call_notes | Text column in fact table | Text in fact tables bloats row size, complicates indexing, and violates the principle that fact tables store only keys and measures |
| Quota history | Timespan tracking | Pure periodic snapshot | Quota targets are stable across multiple quarters; pure periodic snapshot would insert identical rows every quarter |
| Low-cardinality flags | Junk dimension | Individual flag columns | Four flag columns in the fact table would clutter the schema with Y/N codes; junk dimension reduces to one foreign key |
| Territory hierarchy | Fixed-depth columns | Recursive parent-child | Fixed-depth makes every level directly queryable; recursive structure requires CTEs for every hierarchy traversal |
| Aggregate fact table | Territory-month rollup | Index only | Pre-aggregated table eliminates full table scans for district-level trend queries entirely, not just speeds them up |
