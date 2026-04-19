CREATE TABLE dim_date (
    date_key            DATE            PRIMARY KEY,

    -- Calendar attributes
    day_of_week_num     SMALLINT        NOT NULL,  -- 1=Sunday, 7=Saturday
    day_of_week_name    VARCHAR(10)     NOT NULL,
    day_of_month        SMALLINT        NOT NULL,
    week_number         SMALLINT        NOT NULL,  -- ISO week number
    month_num           SMALLINT        NOT NULL,
    month_name          VARCHAR(10)     NOT NULL,
    calendar_quarter    SMALLINT        NOT NULL,  -- 1-4
    calendar_year       SMALLINT        NOT NULL,

    -- Fiscal attributes (July fiscal year)
    -- FY2024 = August 2023 through July 2024
    -- This is required because we are assuming pharma companies measure quarters
    -- starting in July instead of January. Without, we'd have to manually calculate
    -- in every query.
    fiscal_quarter      SMALLINT        NOT NULL,  -- 1-4
    fiscal_year         SMALLINT        NOT NULL,  -- e.g. 2024
    fiscal_quarter_name VARCHAR(10)     NOT NULL,  -- e.g. 'FQ1 2024'
    fiscal_period_name  VARCHAR(20)     NOT NULL,  -- e.g. 'FY2024 Q1'

    -- Flags
    is_weekend          BOOLEAN         NOT NULL DEFAULT FALSE,
    is_holiday          BOOLEAN         NOT NULL DEFAULT FALSE,
    holiday_name        VARCHAR(50)     NULL       -- NULL if not a holiday
);

CREATE TABLE dim_territory (
    -- Primary Key
    territory_key       SERIAL          PRIMARY KEY,

    -- Natural Key
    territory_code      VARCHAR(20)     NOT NULL UNIQUE,

    -- Fixed-depth hierarchy (territory rolls up to national)
    territory_name      VARCHAR(100)    NOT NULL,
    district_code       VARCHAR(20)     NOT NULL,
    district_name       VARCHAR(100)    NOT NULL,
    region_code         VARCHAR(20)     NOT NULL,
    region_name         VARCHAR(100)    NOT NULL,
    zone_code           VARCHAR(20)     NOT NULL,
    zone_name           VARCHAR(100)    NOT NULL,
    national            VARCHAR(50)     NOT NULL DEFAULT 'US'
);

CREATE TABLE dim_rep (
    -- Primary Key
    rep_key             SERIAL          PRIMARY KEY,

    -- Natural and Durable Keys
    rep_id              VARCHAR(20)     NOT NULL,  -- HR system ID, natural key
    rep_durable_key     VARCHAR(20)     NOT NULL,  -- stable across all SCD versions

    -- Rep attributes
    rep_name            VARCHAR(100)    NOT NULL,
    title               VARCHAR(100)    NOT NULL,
    hire_date           DATE            NOT NULL,
    employment_status   VARCHAR(20)     NOT NULL,  -- active, terminated, leave

    -- Manager attributes (Type 2 — manager changes are versioned)
    manager_name        VARCHAR(100)    NOT NULL,
    manager_id          VARCHAR(20)     NOT NULL,

    -- Territory assignment (Type 6)
    territory_key       INTEGER         NOT NULL REFERENCES dim_territory(territory_key),

    -- Type 1 overlay — always reflects current territory regardless of row version
    current_territory_key   INTEGER     NOT NULL REFERENCES dim_territory(territory_key),
    current_territory_name  VARCHAR(100) NOT NULL,

    -- Specialty focus
    specialty_focus     VARCHAR(100)    NOT NULL,
    district            VARCHAR(100)    NOT NULL,
    region              VARCHAR(100)    NOT NULL,

    -- SCD Type 2 versioning columns
    effective_date      DATE            NOT NULL,
    expiration_date     DATE            NULL,       -- NULL means current row
    is_current          BOOLEAN         NOT NULL DEFAULT TRUE
);

CREATE TABLE dim_hcp (
    -- Primary Key
    hcp_key             SERIAL          PRIMARY KEY,

    -- Natural and Durable Keys
    npi_number          VARCHAR(10)     NOT NULL,  -- national provider identifier
    hcp_durable_key     VARCHAR(20)     NOT NULL,  -- stable across all SCD versions
    vendor_hcp_id       VARCHAR(50)     NULL,      -- IQVIA or Symphony assigned ID

    -- HCP attributes
    first_name          VARCHAR(100)    NOT NULL,
    last_name           VARCHAR(100)    NOT NULL,
    full_name           VARCHAR(200)    NOT NULL,
    specialty           VARCHAR(100)    NOT NULL,
    sub_specialty       VARCHAR(100)    NULL,
    practice_name       VARCHAR(200)    NULL,

    -- Address (SCD Type 1 — overwritten on change)
    address_line_1      VARCHAR(200)    NOT NULL,
    address_line_2      VARCHAR(200)    NULL,
    city                VARCHAR(100)    NOT NULL,
    state               CHAR(2)        NOT NULL,
    zip                 VARCHAR(10)     NOT NULL,

    -- Banding attributes (pre-calculated during ETL)
    segment             CHAR(1)         NOT NULL,  -- A, B, C, D tier
    decile_rank         SMALLINT        NOT NULL,  -- 1-10 prescribing volume decile

    -- SCD Type 2 versioning columns (for segment tier changes)
    effective_date      DATE            NOT NULL,
    expiration_date     DATE            NULL,      -- NULL means current row
    is_current          BOOLEAN         NOT NULL DEFAULT TRUE
);

CREATE TABLE dim_product (
    -- Primary Key
    product_key         SERIAL          PRIMARY KEY,

    -- Natural Key
    product_code        VARCHAR(20)     NOT NULL UNIQUE,

    -- Brand and generic identity
    brand_name          VARCHAR(100)    NOT NULL,
    generic_name        VARCHAR(200)    NOT NULL,

    -- Classification
    therapeutic_area    VARCHAR(100)    NOT NULL,  -- e.g. Oncology, Immunology
    indication          VARCHAR(200)    NOT NULL,  -- FDA approved use
    drug_class          VARCHAR(100)    NOT NULL,  -- e.g. PD-1 inhibitor, GLP-1 agonist

    -- Formulation
    formulation         VARCHAR(100)    NOT NULL,  -- e.g. injection, tablet, capsule
    dosage_strength     VARCHAR(50)     NOT NULL,  -- e.g. 100mg/10mL
    route_of_admin      VARCHAR(50)     NOT NULL,  -- e.g. subcutaneous, oral, IV

    -- Market attributes (SCD Type 1)
    market_status       VARCHAR(20)     NOT NULL,  -- launched, withdrawn, pipeline

    -- Origin attributes (SCD Type 0 — never overwritten)
    launch_date         DATE            NOT NULL,
    patent_expiry_date  DATE            NULL,      -- NULL if not yet determined

    -- SCD Type 2 versioning columns (for indication expansions)
    effective_date      DATE            NOT NULL,
    expiration_date     DATE            NULL,      -- NULL means current row
    is_current          BOOLEAN         NOT NULL DEFAULT TRUE
);

CREATE TABLE dim_visit_flags (
    -- Primary Key
    visit_flags_key     SERIAL          PRIMARY KEY,

    -- Visit type flags
    visit_type          VARCHAR(20)     NOT NULL,  -- in_person, virtual
    call_type           VARCHAR(20)     NOT NULL,  -- planned, unplanned
    access_type         VARCHAR(20)     NOT NULL,  -- saw_physician, drop_off
    program_type        VARCHAR(20)     NOT NULL,   -- standard_call, lunch_program

    -- Enforce no duplicate flag combinations
    UNIQUE (visit_type, call_type, access_type, program_type)
);

CREATE TABLE dim_call_notes (
    -- Primary Key
    call_notes_key      SERIAL          PRIMARY KEY,

    -- Note content
    note_text           TEXT            NOT NULL,
    note_length         SMALLINT        NOT NULL,  -- character count, for filtering

    -- Note metadata
    note_type           VARCHAR(50)     NOT NULL,  -- follow_up, objection, sample_request
    note_created_at     TIMESTAMP       NOT NULL,
    note_created_by     VARCHAR(100)    NOT NULL   -- rep name who authored the note
);

CREATE TABLE dim_audit (
    -- Primary Key
    audit_key           SERIAL          PRIMARY KEY,

    -- ETL batch metadata
    batch_id            VARCHAR(50)     NOT NULL,  -- unique identifier for each ETL run
    batch_start_time    TIMESTAMP       NOT NULL,
    batch_end_time      TIMESTAMP       NULL,      -- NULL if batch still running
    batch_status        VARCHAR(20)     NOT NULL,  -- running, completed, failed

    -- Source metadata
    source_system       VARCHAR(50)     NOT NULL,  -- veeva_crm, iqvia, incentive_comp
    source_file_name    VARCHAR(200)    NULL,      -- NULL for API-sourced data
    source_row_count    INTEGER         NOT NULL,  -- rows received from source
    loaded_row_count    INTEGER         NOT NULL,  -- rows successfully loaded

    -- Data quality
    dq_flag             VARCHAR(20)     NOT NULL,  -- clean, corrected, superseded
    dq_notes            TEXT            NULL,      -- NULL if no quality issues

    -- Transformation metadata
    transform_version   VARCHAR(20)     NOT NULL,  -- e.g. v1.2.0
    loaded_by           VARCHAR(100)    NOT NULL   -- process or user that ran the ETL
);

CREATE TABLE dim_month (
    -- Primary Key
    month_key           DATE            PRIMARY KEY,  -- first day of month, e.g. 2024-01-01

    -- Calendar attributes
    month_name          VARCHAR(10)     NOT NULL,  -- e.g. January
    month_num           SMALLINT        NOT NULL,  -- 1-12
    calendar_quarter    SMALLINT        NOT NULL,  -- 1-4
    calendar_year       SMALLINT        NOT NULL,

    -- Fiscal attributes
    fiscal_quarter      SMALLINT        NOT NULL,
    fiscal_year         SMALLINT        NOT NULL,
    fiscal_period_name  VARCHAR(20)     NOT NULL   -- e.g. 'FY2024 Q1'
);

CREATE TABLE dim_territory_rollup (
    -- Primary Key
    territory_rollup_key    SERIAL          PRIMARY KEY,

    -- Foreign key to full dimension
    territory_key           INTEGER         NOT NULL REFERENCES dim_territory(territory_key),

    -- Retained hierarchy levels
    territory_name          VARCHAR(100)    NOT NULL,
    district                VARCHAR(100)    NOT NULL,
    region                  VARCHAR(100)    NOT NULL
);

CREATE TABLE bridge_hcp_rep_alignment (
    -- Primary Key
    alignment_key           SERIAL          PRIMARY KEY,

    -- Group Key (ties co-promoting reps together)
    group_key               INTEGER         NOT NULL,

    -- Foreign Keys
    hcp_key                 INTEGER         NOT NULL REFERENCES dim_hcp(hcp_key),
    rep_key                 INTEGER         NOT NULL REFERENCES dim_rep(rep_key),
    product_key             INTEGER         NOT NULL REFERENCES dim_product(product_key),

    -- Credit split
    credit_split_weight     NUMERIC(4,3)    NOT NULL,  -- e.g. 0.600, 0.400, ETL must validate sum across rows.

    -- Alignment period
    effective_date          DATE            NOT NULL,
    expiration_date         DATE            NULL,      -- NULL means currently active
    is_current              BOOLEAN         NOT NULL DEFAULT TRUE,

    -- Grain enforcement
    UNIQUE (group_key, rep_key, product_key, effective_date),

    -- Weight validation
    CONSTRAINT valid_weight CHECK (credit_split_weight > 0 AND credit_split_weight <= 1)
);

CREATE TABLE fct_hcp_visit (
    -- Primary Key
    visit_key               SERIAL          PRIMARY KEY,

    -- Degenerate Dimension
    visit_id                VARCHAR(50)     NOT NULL UNIQUE,  -- CRM system visit ID

    -- Foreign Keys
    date_key                DATE            NOT NULL REFERENCES dim_date(date_key),
    rep_key                 INTEGER         NOT NULL REFERENCES dim_rep(rep_key),
    hcp_key                 INTEGER         NOT NULL REFERENCES dim_hcp(hcp_key),
    product_key             INTEGER         NOT NULL REFERENCES dim_product(product_key),
    visit_flags_key         INTEGER         NOT NULL REFERENCES dim_visit_flags(visit_flags_key),
    call_notes_key          INTEGER         NOT NULL REFERENCES dim_call_notes(call_notes_key),
    audit_key               INTEGER         NOT NULL REFERENCES dim_audit(audit_key),

    -- Fully Additive Facts
    samples_dropped         SMALLINT        NOT NULL DEFAULT 0,
    visit_duration_minutes  SMALLINT        NOT NULL
);

CREATE TABLE fct_prescription_weekly (
    -- Primary Key
    prescription_key        SERIAL          PRIMARY KEY,

    -- Foreign Keys
    week_end_date_key       DATE            NOT NULL REFERENCES dim_date(date_key), -- venders report on week ending dates
    hcp_key                 INTEGER         NOT NULL REFERENCES dim_hcp(hcp_key),
    product_key             INTEGER         NOT NULL REFERENCES dim_product(product_key),
    territory_key           INTEGER         NOT NULL REFERENCES dim_territory(territory_key),
    group_key               INTEGER         NULL, -- joins to bridge_hcp_rep_alignment.group_key, ETL must handle fk constraint
    audit_key               INTEGER         NOT NULL REFERENCES dim_audit(audit_key),

    -- Fully Additive Facts
    new_rx_count            SMALLINT        NOT NULL DEFAULT 0,  -- new prescriptions written
    total_rx_count          SMALLINT        NOT NULL DEFAULT 0,  -- new + refill prescriptions
    total_units             INTEGER         NOT NULL DEFAULT 0,  -- units dispensed

    -- Market Share Components (fully additive — never sum market_share_pct directly)
    brand_units             INTEGER         NOT NULL DEFAULT 0,  -- numerator
    total_market_units      INTEGER         NOT NULL DEFAULT 0,  -- denominator

    -- Non-Additive Fact (stored for reference only)
    market_share_pct        NUMERIC(5,2)    NULL,  -- calculated in reporting layer

    -- Grain enforcement
    UNIQUE (week_end_date_key, hcp_key, product_key, territory_key)
);

CREATE TABLE fct_quota_attainment (
    -- Primary Key
    quota_key               SERIAL          PRIMARY KEY,

    -- Foreign Keys
    fiscal_quarter_key      DATE            NOT NULL REFERENCES dim_date(date_key),
    prior_year_quarter_key  DATE            NOT NULL REFERENCES dim_date(date_key),
    rep_key                 INTEGER         NOT NULL REFERENCES dim_rep(rep_key),
    product_key             INTEGER         NOT NULL REFERENCES dim_product(product_key),
    territory_key           INTEGER         NOT NULL REFERENCES dim_territory(territory_key),
    audit_key               INTEGER         NOT NULL REFERENCES dim_audit(audit_key),

    -- Consolidated Facts — quota plan vs actual
    quota_units             INTEGER         NOT NULL,  -- assigned target
    actual_units            INTEGER         NOT NULL,  -- what was actually sold

    -- Prior year actual (fully additive — avoids self join for YoY comparison)
    prior_year_actual_units INTEGER         NOT NULL DEFAULT 0,

    -- Non-Additive Fact (calculated in reporting layer)
    attainment_pct          NUMERIC(5,2)    NULL,

    -- Timespan tracking (only insert new row when quota actually changes)
    effective_date          DATE            NOT NULL,
    expiration_date         DATE            NULL,      -- NULL means currently active
    is_current              BOOLEAN         NOT NULL DEFAULT TRUE,

    -- Grain enforcement
    UNIQUE (rep_key, product_key, fiscal_quarter_key)
);

CREATE TABLE fct_hcp_coverage_target (
    -- Primary Key
    coverage_key            SERIAL          PRIMARY KEY,

    -- Foreign Keys
    fiscal_quarter_key      DATE            NOT NULL REFERENCES dim_date(date_key),
    rep_key                 INTEGER         NOT NULL REFERENCES dim_rep(rep_key),
    hcp_key                 INTEGER         NOT NULL REFERENCES dim_hcp(hcp_key),
    product_key             INTEGER         NOT NULL REFERENCES dim_product(product_key),

    -- No numeric measures -- the relationship itself is the data

    -- Grain enforcement
    UNIQUE (fiscal_quarter_key, rep_key, hcp_key, product_key)
);

CREATE TABLE fct_prescription_territory_monthly (
    -- Primary Key
    territory_monthly_key   SERIAL          PRIMARY KEY,

    -- Foreign Keys
    month_key               DATE            NOT NULL REFERENCES dim_month(month_key),
    territory_rollup_key    INTEGER         NOT NULL REFERENCES dim_territory_rollup(territory_rollup_key),
    product_key             INTEGER         NOT NULL REFERENCES dim_product(product_key),

    -- Rolled Up Facts
    new_rx_count            INTEGER         NOT NULL DEFAULT 0,
    total_rx_count          INTEGER         NOT NULL DEFAULT 0,
    total_units             INTEGER         NOT NULL DEFAULT 0,
    brand_units             INTEGER         NOT NULL DEFAULT 0,
    total_market_units      INTEGER         NOT NULL DEFAULT 0,

    -- Non-Additive Fact (calculated in reporting layer)
    market_share_pct        NUMERIC(5,2)    NULL,

    -- Aggregate metadata
    source_row_count        INTEGER         NOT NULL,  -- how many weekly rows were rolled up
    last_rebuilt_at         TIMESTAMP       NOT NULL,  -- when this row was last recomputed

    -- Grain enforcement
    UNIQUE (month_key, territory_rollup_key, product_key)
);
