import random
from datetime import date, timedelta
from faker import Faker

fake = Faker()
random.seed(42)
Faker.seed(42)

OUTPUT_FILE = 'seed_data.sql'

# ── SCENARIO PARAMETERS ──────────────────────────────────────────────────
DATE_START              = date(2022, 1, 1)
DATE_END                = date(2024, 12, 31)
REP_TRANSFER_DATE       = date(2024, 3, 1)
HCP_TIER_UPGRADE_DATE   = date(2024, 1, 15)
COPROMO_SPLIT           = (0.60, 0.40)
QUOTA_MISS_REP_1_PCT    = 0.67   # Sarah Chen — effort problem (undercovering HCPs)
QUOTA_MISS_REP_2_PCT    = 0.71   # Marcus Williams — territory problem (good coverage)
RX_DROP_WEEK_START      = date(2023, 8, 6)   # week Dr. Okafor's volume drops
RX_DROP_WEEK_END        = date(2023, 9, 3)   # four weeks later
NUM_REPS                = 50
NUM_HCPS                = 500
# ────────────────────────────────────────────────────────────────────────

# ── FISCAL YEAR LOGIC ────────────────────────────────────────────────────
def get_fiscal_year(d):
    # FY starts August 1. FY2024 = Aug 2023 - Jul 2024
    return d.year + 1 if d.month >= 8 else d.year

def get_fiscal_quarter(d):
    m = d.month
    if m in (8, 9, 10):   return 1
    if m in (11, 12, 1):  return 2
    if m in (2, 3, 4):    return 3
    if m in (5, 6, 7):    return 4

def get_fiscal_quarter_name(d):
    return f'FQ{get_fiscal_quarter(d)} {get_fiscal_year(d)}'

def get_fiscal_period_name(d):
    return f'FY{get_fiscal_year(d)} Q{get_fiscal_quarter(d)}'

def get_fiscal_quarter_start(fy, fq):
    # Returns the first date of a fiscal quarter
    starts = {1: (fy - 1, 8), 2: (fy - 1, 11), 3: (fy, 2), 4: (fy, 5)}
    y, m = starts[fq]
    return date(y, m, 1)
# ────────────────────────────────────────────────────────────────────────

def esc(s):
    """Escape single quotes in strings for SQL."""
    if s is None:
        return 'NULL'
    return "'" + str(s).replace("'", "''") + "'"

def write(f, sql):
    f.write(sql + '\n')

# ── REFERENCE DATA ───────────────────────────────────────────────────────
TERRITORIES = [
    ('TER-NE-01', 'Northeast Boston',    'DIST-NE', 'Northeast District', 'REG-NE', 'Northeast Region', 'ZONE-E', 'East Zone'),
    ('TER-NE-02', 'Northeast New York',  'DIST-NE', 'Northeast District', 'REG-NE', 'Northeast Region', 'ZONE-E', 'East Zone'),
    ('TER-MA-01', 'Mid-Atlantic DC',     'DIST-MA', 'Mid-Atlantic District', 'REG-NE', 'Northeast Region', 'ZONE-E', 'East Zone'),
    ('TER-SE-01', 'Southeast Atlanta',   'DIST-SE', 'Southeast District', 'REG-SE', 'Southeast Region', 'ZONE-W', 'West Zone'),
    ('TER-SE-02', 'Southeast Miami',     'DIST-SE', 'Southeast District', 'REG-SE', 'Southeast Region', 'ZONE-W', 'West Zone'),
    ('TER-SW-01', 'Southwest Dallas',    'DIST-SW', 'Southwest District', 'REG-SE', 'Southeast Region', 'ZONE-W', 'West Zone'),
]

# territory_code -> territory_key (1-indexed)
TERRITORY_KEY = {t[0]: i + 1 for i, t in enumerate(TERRITORIES)}

PRODUCTS = [
    # (product_code, brand_name, generic_name, therapeutic_area, indication, drug_class,
    #  formulation, dosage_strength, route, market_status, launch_date, patent_expiry,
    #  effective_date, expiration_date, is_current)
    ('PRD-KTR-001', 'Keytruda', 'pembrolizumab',
     'Oncology', 'Non-small cell lung cancer (NSCLC)',
     'PD-1 inhibitor', 'injection', '100mg/4mL', 'intravenous',
     'launched', '2014-09-04', '2028-07-23',
     '2014-09-04', None, True),

    ('PRD-HUM-001', 'Humira', 'adalimumab',
     'Immunology', 'Rheumatoid arthritis',
     'TNF inhibitor', 'injection', '40mg/0.8mL', 'subcutaneous',
     'launched', '2002-12-31', '2023-01-31',
     '2002-12-31', '2023-11-01', False),   # original indication — expired

    ('PRD-HUM-002', 'Humira', 'adalimumab',
     'Immunology', 'Rheumatoid arthritis and plaque psoriasis',
     'TNF inhibitor', 'injection', '40mg/0.8mL', 'subcutaneous',
     'launched', '2002-12-31', '2023-01-31',
     '2023-11-01', None, True),            # expanded indication — current

    ('PRD-OZM-001', 'Ozempic', 'semaglutide',
     'Endocrinology', 'Type 2 diabetes management',
     'GLP-1 agonist', 'injection', '0.5mg/1.5mL', 'subcutaneous',
     'launched', '2017-12-05', '2032-06-01',
     '2017-12-05', None, True),
]

# product_code -> product_key (1-indexed)
PRODUCT_KEY = {p[0]: i + 1 for i, p in enumerate(PRODUCTS)}

SPECIALTIES = [
    'Oncology', 'Rheumatology', 'Endocrinology',
    'Internal Medicine', 'Family Practice', 'Immunology'
]

NOTE_TYPES = ['follow_up', 'objection', 'sample_request']

NOTE_TEMPLATES = {
    'follow_up':       'Discussed recent clinical trial results. Physician requested follow-up materials on {}. Scheduled next visit.',
    'objection':       'Physician raised concerns about {} side effect profile. Left literature addressing key objections. Will follow up.',
    'sample_request':  'Physician requested additional {} samples for new patients. Discussed proper dosing protocol.',
}

VISIT_TYPES  = ['in_person', 'virtual']
CALL_TYPES   = ['planned', 'unplanned']
ACCESS_TYPES = ['saw_physician', 'drop_off']
PROGRAM_TYPES = ['standard_call', 'lunch_program']

# ── DIM_DATE ─────────────────────────────────────────────────────────────
def generate_dim_date(f):
    write(f, '\n-- ── dim_date ───────────────────────────────────────────────────────────')
    write(f, 'INSERT INTO dim_date (date_key, day_of_week_num, day_of_week_name, day_of_month,')
    write(f, '    week_number, month_num, month_name, calendar_quarter, calendar_year,')
    write(f, '    fiscal_quarter, fiscal_year, fiscal_quarter_name, fiscal_period_name,')
    write(f, '    is_weekend, is_holiday, holiday_name) VALUES')

    us_holidays = {
        date(2022, 1, 1), date(2022, 7, 4), date(2022, 11, 24), date(2022, 12, 25),
        date(2023, 1, 1), date(2023, 7, 4), date(2023, 11, 23), date(2023, 12, 25),
        date(2024, 1, 1), date(2024, 7, 4), date(2024, 11, 28), date(2024, 12, 25),
    }
    holiday_names = {
        date(2022, 1, 1): "New Year's Day", date(2022, 7, 4): 'Independence Day',
        date(2022, 11, 24): 'Thanksgiving',  date(2022, 12, 25): 'Christmas',
        date(2023, 1, 1): "New Year's Day", date(2023, 7, 4): 'Independence Day',
        date(2023, 11, 23): 'Thanksgiving',  date(2023, 12, 25): 'Christmas',
        date(2024, 1, 1): "New Year's Day", date(2024, 7, 4): 'Independence Day',
        date(2024, 11, 28): 'Thanksgiving',  date(2024, 12, 25): 'Christmas',
    }
    day_names    = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']
    month_names  = ['','January','February','March','April','May','June',
                    'July','August','September','October','November','December']

    rows = []
    d = DATE_START
    while d <= DATE_END:
        dow      = d.isoweekday() % 7          # 0=Sun isoweekday, make 1=Sun
        dow_num  = dow + 1 if dow > 0 else 1
        is_wknd  = d.weekday() >= 5
        is_hol   = d in us_holidays
        hol_name = holiday_names.get(d)
        cal_q    = (d.month - 1) // 3 + 1
        fq       = get_fiscal_quarter(d)
        fy       = get_fiscal_year(d)

        rows.append(
            f"  ({esc(d)}, {dow_num}, {esc(day_names[d.weekday()+1 if d.weekday()<6 else 0])}, "
            f"{d.day}, {d.isocalendar()[1]}, {d.month}, {esc(month_names[d.month])}, "
            f"{cal_q}, {d.year}, {fq}, {fy}, "
            f"{esc(get_fiscal_quarter_name(d))}, {esc(get_fiscal_period_name(d))}, "
            f"{'TRUE' if is_wknd else 'FALSE'}, {'TRUE' if is_hol else 'FALSE'}, "
            f"{esc(hol_name)})"
        )
        d += timedelta(days=1)

    write(f, ',\n'.join(rows) + ';')

# ── DIM_MONTH ────────────────────────────────────────────────────────────
def generate_dim_month(f):
    write(f, '\n-- ── dim_month ──────────────────────────────────────────────────────────')
    write(f, 'INSERT INTO dim_month (month_key, month_name, month_num, calendar_quarter,')
    write(f, '    calendar_year, fiscal_quarter, fiscal_year, fiscal_period_name) VALUES')

    month_names = ['','January','February','March','April','May','June',
                   'July','August','September','October','November','December']
    rows = []
    y, m = DATE_START.year, DATE_START.month
    end_y, end_m = DATE_END.year, DATE_END.month
    while (y, m) <= (end_y, end_m):
        d    = date(y, m, 1)
        cal_q = (m - 1) // 3 + 1
        rows.append(
            f"  ({esc(d)}, {esc(month_names[m])}, {m}, {cal_q}, {y}, "
            f"{get_fiscal_quarter(d)}, {get_fiscal_year(d)}, "
            f"{esc(get_fiscal_period_name(d))})"
        )
        m += 1
        if m > 12:
            m = 1
            y += 1

    write(f, ',\n'.join(rows) + ';')

# ── DIM_TERRITORY ────────────────────────────────────────────────────────
def generate_dim_territory(f):
    write(f, '\n-- ── dim_territory ──────────────────────────────────────────────────────')
    write(f, 'INSERT INTO dim_territory (territory_code, territory_name, district_code,')
    write(f, '    district_name, region_code, region_name, zone_code, zone_name, national) VALUES')
    rows = []
    for t in TERRITORIES:
        rows.append(
            f"  ({esc(t[0])}, {esc(t[1])}, {esc(t[2])}, {esc(t[3])}, "
            f"{esc(t[4])}, {esc(t[5])}, {esc(t[6])}, {esc(t[7])}, 'US')"
        )
    write(f, ',\n'.join(rows) + ';')

# ── DIM_TERRITORY_ROLLUP ─────────────────────────────────────────────────
def generate_dim_territory_rollup(f):
    write(f, '\n-- ── dim_territory_rollup ───────────────────────────────────────────────')
    write(f, 'INSERT INTO dim_territory_rollup (territory_key, territory_name, district, region) VALUES')
    rows = []
    for i, t in enumerate(TERRITORIES):
        rows.append(f"  ({i+1}, {esc(t[1])}, {esc(t[3])}, {esc(t[5])})")
    write(f, ',\n'.join(rows) + ';')

# ── DIM_PRODUCT ───────────────────────────────────────────────────────────
def generate_dim_product(f):
    write(f, '\n-- ── dim_product ────────────────────────────────────────────────────────')
    write(f, 'INSERT INTO dim_product (product_code, brand_name, generic_name, therapeutic_area,')
    write(f, '    indication, drug_class, formulation, dosage_strength, route_of_admin,')
    write(f, '    market_status, launch_date, patent_expiry_date, effective_date,')
    write(f, '    expiration_date, is_current) VALUES')
    rows = []
    for p in PRODUCTS:
        rows.append(
            f"  ({esc(p[0])}, {esc(p[1])}, {esc(p[2])}, {esc(p[3])}, {esc(p[4])}, "
            f"{esc(p[5])}, {esc(p[6])}, {esc(p[7])}, {esc(p[8])}, {esc(p[9])}, "
            f"{esc(p[10])}, {esc(p[11])}, {esc(p[12])}, {esc(p[13])}, "
            f"{'TRUE' if p[14] else 'FALSE'})"
        )
    write(f, ',\n'.join(rows) + ';')

# ── DIM_VISIT_FLAGS ───────────────────────────────────────────────────────
def generate_dim_visit_flags(f):
    write(f, '\n-- ── dim_visit_flags ────────────────────────────────────────────────────')
    write(f, 'INSERT INTO dim_visit_flags (visit_type, call_type, access_type, program_type) VALUES')
    rows = []
    for vt in VISIT_TYPES:
        for ct in CALL_TYPES:
            for at in ACCESS_TYPES:
                for pt in PROGRAM_TYPES:
                    rows.append(f"  ({esc(vt)}, {esc(ct)}, {esc(at)}, {esc(pt)})")
    write(f, ',\n'.join(rows) + ';')

# ── DIM_AUDIT ─────────────────────────────────────────────────────────────
def generate_dim_audit(f):
    write(f, '\n-- ── dim_audit ──────────────────────────────────────────────────────────')
    write(f, 'INSERT INTO dim_audit (batch_id, batch_start_time, batch_end_time, batch_status,')
    write(f, '    source_system, source_file_name, source_row_count, loaded_row_count,')
    write(f, '    dq_flag, dq_notes, transform_version, loaded_by) VALUES')

    batches = [
        ('BATCH-001', '2024-01-01 02:00:00', '2024-01-01 02:14:22', 'completed',
         'veeva_crm',     'veeva_visits_20240101.csv',      4821, 4821, 'clean',      None,           'v1.0.0', 'etl_pipeline'),
        ('BATCH-002', '2024-01-07 03:00:00', '2024-01-07 03:22:11', 'completed',
         'iqvia',         'iqvia_rx_week_20240107.csv',    48200, 48200, 'clean',     None,           'v1.0.0', 'etl_pipeline'),
        ('BATCH-003', '2024-01-14 03:00:00', '2024-01-14 03:21:45', 'completed',
         'iqvia',         'iqvia_rx_week_20240114.csv',    48150, 48150, 'clean',     None,           'v1.0.0', 'etl_pipeline'),
        ('BATCH-004', '2024-02-01 02:00:00', '2024-02-01 02:15:30', 'completed',
         'veeva_crm',     'veeva_visits_20240201.csv',      4932, 4932, 'clean',      None,           'v1.0.0', 'etl_pipeline'),
        ('BATCH-005', '2024-03-03 03:00:00', '2024-03-03 03:19:55', 'completed',
         'iqvia',         'iqvia_rx_week_20240303.csv',    47800, 47800, 'corrected', 'Unit counts inflated by vendor — corrected file received 2024-03-10', 'v1.0.0', 'etl_pipeline'),
        ('BATCH-006', '2024-03-10 03:00:00', '2024-03-10 03:20:12', 'completed',
         'iqvia',         'iqvia_rx_week_20240303_corrected.csv', 47800, 47800, 'clean', None,        'v1.0.1', 'etl_pipeline'),
        ('BATCH-007', '2024-03-01 02:00:00', '2024-03-01 02:13:44', 'completed',
         'veeva_crm',     'veeva_visits_20240301.csv',      5011, 5011, 'clean',      None,           'v1.0.1', 'etl_pipeline'),
        ('BATCH-008', '2024-04-01 04:00:00', '2024-04-01 04:31:02', 'completed',
         'incentive_comp','quota_q3_fy2024.csv',             150,  150, 'clean',      None,           'v1.0.1', 'etl_pipeline'),
        ('BATCH-009', '2023-08-01 04:00:00', '2023-08-01 04:28:55', 'completed',
         'incentive_comp','quota_q1_fy2024.csv',             150,  150, 'clean',      None,           'v1.0.0', 'etl_pipeline'),
        ('BATCH-010', '2023-11-01 04:00:00', '2023-11-01 04:29:33', 'completed',
         'incentive_comp','quota_q2_fy2024.csv',             150,  150, 'clean',      None,           'v1.0.0', 'etl_pipeline'),
    ]

    rows = []
    for b in batches:
        rows.append(
            f"  ({esc(b[0])}, '{b[1]}', '{b[2]}', {esc(b[3])}, "
            f"{esc(b[4])}, {esc(b[5])}, {b[6]}, {b[7]}, "
            f"{esc(b[8])}, {esc(b[9])}, {esc(b[10])}, {esc(b[11])})"
        )
    write(f, ',\n'.join(rows) + ';')

# ── AUDIT KEY LOOKUP ──────────────────────────────────────────────────────
# Maps source system to audit_key (1-indexed position in batches list above)
AUDIT_KEY = {
    'veeva_crm':     1,   # BATCH-001
    'iqvia':         2,   # BATCH-002
    'incentive_comp': 8,  # BATCH-008
}

# ── DIM_REP ───────────────────────────────────────────────────────────────
def generate_dim_rep(f):
    write(f, '\n-- ── dim_rep ─────────────────────────────────────────────────────────────')
    write(f, '-- Note: James Rivera (rep_durable_key=REP-DKEY-003) has two rows — territory transfer scenario')
    write(f, '-- Note: Sarah Chen (REP-DKEY-001) and Marcus Williams (REP-DKEY-002) are quota miss scenarios')
    write(f, 'INSERT INTO dim_rep (rep_id, rep_durable_key, rep_name, title, hire_date,')
    write(f, '    employment_status, manager_name, manager_id, territory_key,')
    write(f, '    current_territory_key, current_territory_name, specialty_focus,')
    write(f, '    district, region, effective_date, expiration_date, is_current) VALUES')

    titles = ['Territory Business Manager', 'Senior Territory Business Manager',
              'Medical Science Liaison', 'Key Account Manager']
    managers = [
        ('Patricia Holloway', 'MGR-001'),
        ('David Brennan',     'MGR-002'),
        ('Susan Alcott',      'MGR-003'),
    ]

    rows = []

    # Scenario reps first — fixed, named, specific
    # Rep 1: Sarah Chen — Mid-Atlantic, below quota, effort problem
    rows.append(
        f"  ('REP-001', 'REP-DKEY-001', 'Sarah Chen', 'Territory Business Manager', "
        f"'2021-03-15', 'active', 'Patricia Holloway', 'MGR-001', "
        f"{TERRITORY_KEY['TER-MA-01']}, {TERRITORY_KEY['TER-MA-01']}, "
        f"'Mid-Atlantic DC', 'Oncology', 'Mid-Atlantic District', 'Northeast Region', "
        f"'2021-03-15', NULL, TRUE)"
    )

    # Rep 2: Marcus Williams — Southeast, below quota, territory problem
    rows.append(
        f"  ('REP-002', 'REP-DKEY-002', 'Marcus Williams', 'Territory Business Manager', "
        f"'2020-07-01', 'active', 'David Brennan', 'MGR-002', "
        f"{TERRITORY_KEY['TER-SE-01']}, {TERRITORY_KEY['TER-SE-01']}, "
        f"'Southeast Atlanta', 'Oncology', 'Southeast District', 'Southeast Region', "
        f"'2020-07-01', NULL, TRUE)"
    )

    # Rep 3: James Rivera — territory transfer, old row (Northeast)
    rows.append(
        f"  ('REP-003', 'REP-DKEY-003', 'James Rivera', 'Territory Business Manager', "
        f"'2019-05-20', 'active', 'Patricia Holloway', 'MGR-001', "
        f"{TERRITORY_KEY['TER-NE-01']}, {TERRITORY_KEY['TER-SW-01']}, "
        f"'Southwest Dallas', 'Oncology', 'Northeast District', 'Northeast Region', "
        f"'2019-05-20', '2024-02-29', FALSE)"
    )

    # Rep 3: James Rivera — territory transfer, new row (Southwest) — current
    rows.append(
        f"  ('REP-003', 'REP-DKEY-003', 'James Rivera', 'Senior Territory Business Manager', "
        f"'2019-05-20', 'active', 'Susan Alcott', 'MGR-003', "
        f"{TERRITORY_KEY['TER-SW-01']}, {TERRITORY_KEY['TER-SW-01']}, "
        f"'Southwest Dallas', 'Oncology', 'Southwest District', 'Southeast Region', "
        f"'2024-03-01', NULL, TRUE)"
    )

    # Rep 4: David Park — co-promotion partner with Sarah Chen
    rows.append(
        f"  ('REP-004', 'REP-DKEY-004', 'David Park', 'Territory Business Manager', "
        f"'2022-01-10', 'active', 'Patricia Holloway', 'MGR-001', "
        f"{TERRITORY_KEY['TER-MA-01']}, {TERRITORY_KEY['TER-MA-01']}, "
        f"'Mid-Atlantic DC', 'Immunology', 'Mid-Atlantic District', 'Northeast Region', "
        f"'2022-01-10', NULL, TRUE)"
    )

    # Rep 5: Lisa Nguyen — flat quota across three quarters
    rows.append(
        f"  ('REP-005', 'REP-DKEY-005', 'Lisa Nguyen', 'Territory Business Manager', "
        f"'2020-11-30', 'active', 'David Brennan', 'MGR-002', "
        f"{TERRITORY_KEY['TER-SE-02']}, {TERRITORY_KEY['TER-SE-02']}, "
        f"'Southeast Miami', 'Endocrinology', 'Southeast District', 'Southeast Region', "
        f"'2020-11-30', NULL, TRUE)"
    )

    # Remaining 44 reps — generated
    ter_codes = [t[0] for t in TERRITORIES]
    for i in range(6, NUM_REPS + 1):
        rep_id       = f'REP-{i:03d}'
        durable_key  = f'REP-DKEY-{i:03d}'
        name         = fake.name()
        title        = random.choice(titles)
        hire_date    = fake.date_between(start_date=date(2015, 1, 1), end_date=date(2022, 12, 31))
        ter_code     = random.choice(ter_codes)
        ter_key      = TERRITORY_KEY[ter_code]
        ter_name     = next(t[1] for t in TERRITORIES if t[0] == ter_code)
        district     = next(t[3] for t in TERRITORIES if t[0] == ter_code)
        region       = next(t[5] for t in TERRITORIES if t[0] == ter_code)
        mgr_name, mgr_id = random.choice(managers)
        specialty    = random.choice(['Oncology', 'Immunology', 'Endocrinology'])

        rows.append(
            f"  ({esc(rep_id)}, {esc(durable_key)}, {esc(name)}, {esc(title)}, "
            f"{esc(hire_date)}, 'active', {esc(mgr_name)}, {esc(mgr_id)}, "
            f"{ter_key}, {ter_key}, {esc(ter_name)}, {esc(specialty)}, "
            f"{esc(district)}, {esc(region)}, "
            f"{esc(hire_date)}, NULL, TRUE)"
        )

    write(f, ',\n'.join(rows) + ';')

    # Build rep lookup for use in fact table generation
    # Returns list of (rep_key, rep_id, durable_key, territory_key, is_current)
    # rep_key is 1-indexed position in rows inserted
    return rows

# ── DIM_HCP ───────────────────────────────────────────────────────────────
def generate_dim_hcp(f):
    write(f, '\n-- ── dim_hcp ─────────────────────────────────────────────────────────────')
    write(f, '-- Note: Dr. Patricia Moore (hcp_durable_key=HCP-DKEY-002) has two rows — tier upgrade scenario')
    write(f, '-- Note: Dr. Robert Kim (hcp_durable_key=HCP-DKEY-003) is the co-promoted physician')
    write(f, '-- Note: Dr. James Okafor (hcp_durable_key=HCP-DKEY-004) is the prescription drop scenario')
    write(f, 'INSERT INTO dim_hcp (npi_number, hcp_durable_key, vendor_hcp_id, first_name,')
    write(f, '    last_name, full_name, specialty, sub_specialty, practice_name,')
    write(f, '    address_line_1, address_line_2, city, state, zip,')
    write(f, '    segment, decile_rank, effective_date, expiration_date, is_current) VALUES')

    rows = []

    # HCP 1: Standard A-tier physician
    rows.append(
        f"  ('1234567890', 'HCP-DKEY-001', 'IQVIA-HCP-001', 'Michael', 'Chen', "
        f"'Dr. Michael Chen', 'Oncology', 'Thoracic Oncology', 'Georgetown University Hospital', "
        f"'3800 Reservoir Rd NW', NULL, 'Washington', 'DC', '20007', "
        f"'A', 9, '2022-01-01', NULL, TRUE)"
    )

    # HCP 2: Dr. Patricia Moore — B-tier original row
    rows.append(
        f"  ('2345678901', 'HCP-DKEY-002', 'IQVIA-HCP-002', 'Patricia', 'Moore', "
        f"'Dr. Patricia Moore', 'Rheumatology', NULL, 'Washington Rheumatology Associates', "
        f"'2141 K St NW', 'Suite 408', 'Washington', 'DC', '20037', "
        f"'B', 5, '2022-01-01', '2024-01-14', FALSE)"
    )

    # HCP 2: Dr. Patricia Moore — A-tier upgraded row (current)
    rows.append(
        f"  ('2345678901', 'HCP-DKEY-002', 'IQVIA-HCP-002', 'Patricia', 'Moore', "
        f"'Dr. Patricia Moore', 'Rheumatology', NULL, 'Washington Rheumatology Associates', "
        f"'2141 K St NW', 'Suite 408', 'Washington', 'DC', '20037', "
        f"'A', 8, '2024-01-15', NULL, TRUE)"
    )

    # HCP 3: Dr. Robert Kim — co-promoted physician
    rows.append(
        f"  ('3456789012', 'HCP-DKEY-003', 'IQVIA-HCP-003', 'Robert', 'Kim', "
        f"'Dr. Robert Kim', 'Immunology', 'Clinical Immunology', 'MedStar Washington Hospital', "
        f"'110 Irving St NW', NULL, 'Washington', 'DC', '20010', "
        f"'A', 10, '2022-01-01', NULL, TRUE)"
    )

    # HCP 4: Dr. James Okafor — prescription drop scenario
    rows.append(
        f"  ('4567890123', 'HCP-DKEY-004', 'IQVIA-HCP-004', 'James', 'Okafor', "
        f"'Dr. James Okafor', 'Oncology', 'Medical Oncology', 'Johns Hopkins Oncology Center', "
        f"'401 N Broadway', NULL, 'Baltimore', 'MD', '21231', "
        f"'A', 9, '2022-01-01', NULL, TRUE)"
    )

    # Remaining 496 HCPs — generated
    # Track used NPI numbers to avoid duplicates
    used_npis = {'1234567890', '2345678901', '3456789012', '4567890123'}
    segments_weighted = ['A'] * 10 + ['B'] * 30 + ['C'] * 40 + ['D'] * 20

    for i in range(5, NUM_HCPS + 1):
        while True:
            npi = str(random.randint(1000000000, 9999999999))
            if npi not in used_npis:
                used_npis.add(npi)
                break

        durable_key  = f'HCP-DKEY-{i:03d}'
        vendor_id    = f'IQVIA-HCP-{i:03d}'
        first        = fake.first_name()
        last         = fake.last_name()
        full         = f'Dr. {first} {last}'
        specialty    = random.choice(SPECIALTIES)
        practice     = fake.company() + ' Medical Group'
        addr1        = fake.street_address()
        city         = fake.city()
        state        = fake.state_abbr()
        zip_code     = fake.zipcode()
        segment      = random.choice(segments_weighted)
        decile       = random.randint(1, 10)
        eff_date     = '2022-01-01'

        rows.append(
            f"  ({esc(npi)}, {esc(durable_key)}, {esc(vendor_id)}, {esc(first)}, "
            f"{esc(last)}, {esc(full)}, {esc(specialty)}, NULL, {esc(practice)}, "
            f"{esc(addr1)}, NULL, {esc(city)}, {esc(state)}, {esc(zip_code)}, "
            f"{esc(segment)}, {decile}, {esc(eff_date)}, NULL, TRUE)"
        )

    write(f, ',\n'.join(rows) + ';')

# ── DIM_CALL_NOTES ────────────────────────────────────────────────────────
# Pre-generate a pool of call notes to reference from visit rows
def generate_call_notes_pool(num_notes):
    """Returns list of (note_text, note_length, note_type, created_at, created_by)"""
    pool = []
    brand_names = ['Keytruda', 'Humira', 'Ozempic']
    rep_names   = ['Sarah Chen', 'Marcus Williams', 'James Rivera', 'David Park', 'Lisa Nguyen']
    base_ts     = date(2022, 1, 1)
    for i in range(num_notes):
        note_type = random.choice(NOTE_TYPES)
        brand     = random.choice(brand_names)
        text      = NOTE_TEMPLATES[note_type].format(brand)
        length    = len(text)
        days_offset = random.randint(0, (DATE_END - DATE_START).days)
        created_at  = base_ts + timedelta(days=days_offset)
        created_by  = random.choice(rep_names)
        pool.append((text, length, note_type, created_at, created_by))
    return pool

def generate_dim_call_notes(f, pool):
    write(f, '\n-- ── dim_call_notes ─────────────────────────────────────────────────────')
    write(f, 'INSERT INTO dim_call_notes (note_text, note_length, note_type,')
    write(f, '    note_created_at, note_created_by) VALUES')
    rows = []
    for note in pool:
        rows.append(
            f"  ({esc(note[0])}, {note[1]}, {esc(note[2])}, "
            f"'{note[3]} 09:00:00', {esc(note[4])})"
        )
    write(f, ',\n'.join(rows) + ';')

# ── BRIDGE_HCP_REP_ALIGNMENT ──────────────────────────────────────────────
def generate_bridge(f):
    write(f, '\n-- ── bridge_hcp_rep_alignment ───────────────────────────────────────────')
    write(f, '-- Dr. Robert Kim (hcp_key=4) co-promoted by Sarah Chen (rep_key=1) and David Park (rep_key=4)')
    write(f, '-- Credit split: 60% Sarah Chen, 40% David Park')
    write(f, 'INSERT INTO bridge_hcp_rep_alignment (group_key, hcp_key, rep_key, product_key,')
    write(f, '    credit_split_weight, effective_date, expiration_date, is_current) VALUES')

    # hcp_key=4 is Dr. Robert Kim (4th row inserted in dim_hcp)
    # rep_key=1 is Sarah Chen, rep_key=4 is David Park
    # product_key=2 is Humira original, product_key=3 is Humira expanded
    # We use product_key=3 (current Humira indication)
    rows = [
        f"  (1, 4, 1, 3, 0.600, '2022-01-01', NULL, TRUE)",   # Sarah Chen 60%
        f"  (1, 4, 4, 3, 0.400, '2022-01-01', NULL, TRUE)",   # David Park 40%
    ]
    write(f, ',\n'.join(rows) + ';')

# ── FCT_HCP_VISIT ─────────────────────────────────────────────────────────
def generate_fct_hcp_visit(f, notes_pool_size):
    write(f, '\n-- ── fct_hcp_visit ──────────────────────────────────────────────────────')
    write(f, 'INSERT INTO fct_hcp_visit (visit_id, date_key, rep_key, hcp_key, product_key,')
    write(f, '    visit_flags_key, call_notes_key, audit_key, samples_dropped,')
    write(f, '    visit_duration_minutes) VALUES')

    # visit_flags_key mapping — all 16 combinations were inserted in order
    # We will just use random 1-16
    rows       = []
    visit_num  = 1

    # ── Scenario visits: Sarah Chen (rep_key=1) visiting her assigned HCPs ──
    # She covers hcp_keys 1-12 (Mid-Atlantic assignment)
    # Deliberately undercovering hcp_keys 9-12 (zero visits — coverage gap)
    sarah_hcps_visited    = list(range(5, 13))    # hcp_keys 5-12, visits some
    sarah_hcps_not_visited = list(range(13, 17))  # hcp_keys 13-16, zero visits

    visit_dates_sarah = [
        date(2024, 8, 5), date(2024, 8, 19), date(2024, 9, 3),
        date(2024, 9, 17), date(2024, 10, 1), date(2024, 10, 14),
        date(2024, 8, 7), date(2024, 9, 9),
    ]
    for idx, hcp_k in enumerate(sarah_hcps_visited):
        visit_date  = visit_dates_sarah[idx % len(visit_dates_sarah)]
        flags_key   = random.randint(1, 8)   # in_person visits
        notes_key   = random.randint(1, notes_pool_size)
        samples     = random.randint(0, 6)
        duration    = random.randint(15, 45)
        vid         = f'VIS-{visit_num:05d}'
        rows.append(
            f"  ({esc(vid)}, {esc(visit_date)}, 1, {hcp_k}, 1, "
            f"{flags_key}, {notes_key}, 1, {samples}, {duration})"
        )
        visit_num += 1

    # ── Scenario visits: Marcus Williams (rep_key=2) — good coverage ──
    # He visits all 12 assigned HCPs at least twice
    marcus_hcps = list(range(17, 29))   # hcp_keys 17-28
    marcus_visit_dates = [
        date(2024, 8, 6), date(2024, 8, 20), date(2024, 9, 4),
        date(2024, 9, 18), date(2024, 10, 2), date(2024, 10, 15),
    ]
    for hcp_k in marcus_hcps:
        for visit_date in random.sample(marcus_visit_dates, 2):
            flags_key = random.randint(1, 8)
            notes_key = random.randint(1, notes_pool_size)
            samples   = random.randint(0, 4)
            duration  = random.randint(20, 50)
            vid       = f'VIS-{visit_num:05d}'
            rows.append(
                f"  ({esc(vid)}, {esc(visit_date)}, 2, {hcp_k}, 1, "
                f"{flags_key}, {notes_key}, 1, {samples}, {duration})"
            )
            visit_num += 1

    # ── Scenario visits: James Rivera (rep_key=3 pre-transfer, rep_key=4 post) ──
    # Before transfer: visits in Northeast territory
    # After transfer: visits in Southwest territory
    rivera_pre_dates  = [date(2024, 1, 10), date(2024, 1, 24), date(2024, 2, 7), date(2024, 2, 21)]
    rivera_post_dates = [date(2024, 3, 5),  date(2024, 3, 19), date(2024, 4, 2), date(2024, 4, 16)]

    for visit_date in rivera_pre_dates:
        hcp_k     = random.randint(29, 40)
        flags_key = random.randint(1, 8)
        notes_key = random.randint(1, notes_pool_size)
        vid       = f'VIS-{visit_num:05d}'
        rows.append(
            f"  ({esc(vid)}, {esc(visit_date)}, 3, {hcp_k}, 1, "
            f"{flags_key}, {notes_key}, 1, {random.randint(0,4)}, {random.randint(20,45)})"
        )
        visit_num += 1

    # rep_key=4 is James Rivera post-transfer (4th row in dim_rep)
    for visit_date in rivera_post_dates:
        hcp_k     = random.randint(41, 52)
        flags_key = random.randint(1, 8)
        notes_key = random.randint(1, notes_pool_size)
        vid       = f'VIS-{visit_num:05d}'
        rows.append(
            f"  ({esc(vid)}, {esc(visit_date)}, 4, {hcp_k}, 1, "
            f"{flags_key}, {notes_key}, 4, {random.randint(0,4)}, {random.randint(20,45)})"
        )
        visit_num += 1

    # ── Bulk visits: remaining reps (rep_keys 5-51) ──
    weekdays = [d for d in (DATE_START + timedelta(n) for n in range((DATE_END - DATE_START).days))
                if d.weekday() < 5]

    for rep_key in range(5, NUM_REPS + 2):  # +2 because Rivera adds an extra row
        num_visits = random.randint(80, 120)
        visit_dates_bulk = random.sample(weekdays, min(num_visits, len(weekdays)))
        for visit_date in visit_dates_bulk:
            hcp_k     = random.randint(1, NUM_HCPS)
            prod_k    = random.randint(1, 3)
            flags_key = random.randint(1, 16)
            notes_key = random.randint(1, notes_pool_size)
            samples   = random.randint(0, 6)
            duration  = random.randint(10, 60)
            vid       = f'VIS-{visit_num:05d}'
            rows.append(
                f"  ({esc(vid)}, {esc(visit_date)}, {rep_key}, {hcp_k}, {prod_k}, "
                f"{flags_key}, {notes_key}, 1, {samples}, {duration})"
            )
            visit_num += 1

    write(f, ',\n'.join(rows) + ';')
    return visit_num - 1   # total visits inserted

# ── FCT_PRESCRIPTION_WEEKLY ───────────────────────────────────────────────
def generate_fct_prescription_weekly(f):
    write(f, '\n-- ── fct_prescription_weekly ────────────────────────────────────────────')
    write(f, '-- Note: Dr. James Okafor (hcp_key=5) has a visible Rx drop weeks of 2023-08-06 to 2023-09-03')
    write(f, '-- Note: BATCH-005 rows for week 2024-03-03 have inflated units (35% vendor error)')
    write(f, '-- Note: BATCH-006 rows for week 2024-03-10 are the corrected replacements')
    write(f, '-- Note: week 2024-03-10 is reserved exclusively for corrected rows')
    write(f, 'INSERT INTO fct_prescription_weekly (week_end_date_key, hcp_key, product_key,')
    write(f, '    territory_key, group_key, audit_key, new_rx_count, total_rx_count,')
    write(f, '    total_units, brand_units, total_market_units, market_share_pct) VALUES')

    week_ends = []
    d = DATE_START
    while d <= DATE_END:
        if d.weekday() == 6:
            week_ends.append(d)
        d += timedelta(days=1)

    rows       = []
    seen_grain = set()

    active_products = [1, 3, 4]
    RESERVED_CORRECTION_WEEK = date(2024, 3, 10)

    for hcp_key in range(1, NUM_HCPS + 2):
        ter_key   = ((hcp_key - 1) % 6) + 1
        group_key = 1 if hcp_key == 4 else None

        num_products = random.randint(1, 3)
        hcp_products = random.sample(active_products, min(num_products, len(active_products)))

        for prod_key in hcp_products:
            base_new_rx    = random.randint(2, 60)
            base_total_rx  = int(base_new_rx * random.uniform(1.1, 1.8))
            base_units     = base_total_rx * random.randint(28, 90)
            base_mkt_units = int(base_units / random.uniform(0.05, 0.60))

            for week_end in week_ends:
                # Skip the reserved correction week — belongs to BATCH-006 only
                if week_end == RESERVED_CORRECTION_WEEK:
                    continue

                if random.random() < 0.30:
                    continue

                grain = (week_end, hcp_key, prod_key, ter_key)
                if grain in seen_grain:
                    continue
                seen_grain.add(grain)

                # ── Scenario: Dr. Okafor Rx drop ──
                if hcp_key == 5 and prod_key == 1:
                    if RX_DROP_WEEK_START <= week_end <= RX_DROP_WEEK_END:
                        new_rx = random.randint(1, 8)
                    else:
                        new_rx = random.randint(35, 55)
                else:
                    new_rx = max(0, int(base_new_rx * random.uniform(0.7, 1.3)))

                total_rx = max(new_rx, int(new_rx * random.uniform(1.1, 1.8)))

                # ── Scenario: superseded batch week ──
                if week_end == date(2024, 3, 3):
                    audit_key = 5   # BATCH-005 — superseded, inflated units
                    units     = int(total_rx * random.randint(28, 90) * 1.35)
                else:
                    audit_key = 2   # BATCH-002 — standard iqvia batch
                    units     = total_rx * random.randint(28, 90)

                mkt_units = int(units / random.uniform(0.05, 0.60))
                mkt_share = round(units / mkt_units * 100, 2) if mkt_units > 0 else None
                gk        = group_key if group_key else 'NULL'

                rows.append(
                    f"  ({esc(week_end)}, {hcp_key}, {prod_key}, {ter_key}, "
                    f"{gk}, {audit_key}, {new_rx}, {total_rx}, "
                    f"{units}, {units}, {mkt_units}, "
                    f"{'NULL' if mkt_share is None else mkt_share})"
                )

    # ── Corrected rows for BATCH-006 ──
    # Mirror the exact HCP-product-territory combinations from the superseded
    # week (2024-03-03) so Query 9 joins correctly on shared keys.
    # Week 2024-03-10 is reserved exclusively for these corrected rows.
    for (week_end, hcp_key, prod_key, ter_key) in seen_grain:
        if week_end != date(2024, 3, 3):
            continue

        group_key = 1 if hcp_key == 4 else None
        gk        = group_key if group_key else 'NULL'

        new_rx    = random.randint(2, 60)
        total_rx  = max(new_rx, int(new_rx * random.uniform(1.1, 1.8)))
        units     = total_rx * random.randint(28, 90)   # no inflation
        mkt_units = int(units / random.uniform(0.05, 0.60))
        mkt_share = round(units / mkt_units * 100, 2) if mkt_units > 0 else None

        rows.append(
            f"  ({esc(RESERVED_CORRECTION_WEEK)}, {hcp_key}, {prod_key}, {ter_key}, "
            f"{gk}, 6, {new_rx}, {total_rx}, "
            f"{units}, {units}, {mkt_units}, "
            f"{'NULL' if mkt_share is None else mkt_share})"
        )

    write(f, ',\n'.join(rows) + ';')

# ── FCT_QUOTA_ATTAINMENT ──────────────────────────────────────────────────
def generate_fct_quota_attainment(f):
    write(f, '\n-- ── fct_quota_attainment ───────────────────────────────────────────────')
    write(f, '-- Note: Sarah Chen (rep_key=1) at 67% attainment FQ1 FY2024')
    write(f, '-- Note: Marcus Williams (rep_key=2) at 71% attainment FQ1 FY2024')
    write(f, '-- Note: Lisa Nguyen (rep_key=5) has flat quota across FQ1/FQ2/FQ3 FY2024 (timespan tracking)')
    write(f, 'INSERT INTO fct_quota_attainment (fiscal_quarter_key, prior_year_quarter_key,')
    write(f, '    rep_key, product_key, territory_key, audit_key, quota_units,')
    write(f, '    actual_units, prior_year_actual_units, attainment_pct,')
    write(f, '    effective_date, expiration_date, is_current) VALUES')

    rows = []

    # Fiscal quarters to generate: FQ1/FQ2/FQ3 FY2024
    # FQ1 FY2024 = Aug 1 2023 (quarter start date used as key)
    # FQ2 FY2024 = Nov 1 2023
    # FQ3 FY2024 = Feb 1 2024
    fiscal_quarters = [
        (date(2023, 8, 1),  date(2022, 8, 1),  1),   # FQ1 FY2024, prior = FQ1 FY2023
        (date(2023, 11, 1), date(2022, 11, 1), 2),   # FQ2 FY2024, prior = FQ2 FY2023
        (date(2024, 2, 1),  date(2023, 2, 1),  3),   # FQ3 FY2024, prior = FQ3 FY2023
    ]

    # product_keys: 1=Keytruda, 3=Humira, 4=Ozempic
    product_keys  = [1, 3, 4]
    ter_key_by_rep = {
        1: TERRITORY_KEY['TER-MA-01'],
        2: TERRITORY_KEY['TER-SE-01'],
        3: TERRITORY_KEY['TER-NE-01'],
        4: TERRITORY_KEY['TER-MA-01'],
        5: TERRITORY_KEY['TER-SE-02'],
    }

    for rep_key in range(1, NUM_REPS + 2):
        ter_key = ter_key_by_rep.get(rep_key, ((rep_key - 1) % 6) + 1)

        for prod_key in product_keys:
            base_quota = random.randint(400, 800)

            for fq_key, prior_key, fq_num in fiscal_quarters:

                # ── Scenario: Lisa Nguyen flat quota ──
                if rep_key == 5 and prod_key == 4:   # Ozempic
                    quota = 500
                else:
                    quota = base_quota + random.randint(-50, 50)

                # ── Scenario: Sarah Chen quota miss ──
                if rep_key == 1 and fq_num == 1:
                    actual = int(quota * QUOTA_MISS_REP_1_PCT)
                # ── Scenario: Marcus Williams quota miss ──
                elif rep_key == 2 and fq_num == 1:
                    actual = int(quota * QUOTA_MISS_REP_2_PCT)
                else:
                    actual = int(quota * random.uniform(0.75, 1.25))

                prior_actual  = int(quota * random.uniform(0.70, 1.20))
                attainment    = round(actual / quota * 100, 2) if quota > 0 else None

                # Timespan tracking for Lisa Nguyen Ozempic:
                # Only insert one row spanning all three quarters
                if rep_key == 5 and prod_key == 4:
                    if fq_num == 1:
                        eff_date = date(2023, 8, 1)
                        exp_date = None
                        is_curr  = True
                    else:
                        continue   # skip FQ2 and FQ3 — same quota, no new row needed
                else:
                    eff_date = fq_key
                    exp_date = None
                    is_curr  = True

                rows.append(
                    f"  ({esc(fq_key)}, {esc(prior_key)}, {rep_key}, {prod_key}, "
                    f"{ter_key}, 8, {quota}, {actual}, {prior_actual}, "
                    f"{'NULL' if attainment is None else attainment}, "
                    f"{esc(eff_date)}, {'NULL' if exp_date is None else esc(exp_date)}, "
                    f"{'TRUE' if is_curr else 'FALSE'})"
                )

    write(f, ',\n'.join(rows) + ';')

# ── FCT_HCP_COVERAGE_TARGET ───────────────────────────────────────────────
def generate_fct_hcp_coverage_target(f):
    write(f, '\n-- ── fct_hcp_coverage_target ────────────────────────────────────────────')
    write(f, '-- Sarah Chen (rep_key=1): assigned hcp_keys 1-16, visits only 1-12 (gap: 13-16)')
    write(f, '-- Marcus Williams (rep_key=2): assigned hcp_keys 17-28, visits all of them')
    write(f, 'INSERT INTO fct_hcp_coverage_target (fiscal_quarter_key, rep_key, hcp_key, product_key) VALUES')

    fq1_key  = date(2023, 8, 1)
    rows     = []
    seen     = set()

    # ── Scenario reps ──
    # Sarah Chen: 16 assigned HCPs for Keytruda (hcp_keys 1-16)
    for hcp_k in range(1, 17):
        grain = (fq1_key, 1, hcp_k, 1)
        if grain not in seen:
            seen.add(grain)
            rows.append(f"  ({esc(fq1_key)}, 1, {hcp_k}, 1)")

    # Marcus Williams: 12 assigned HCPs for Keytruda (hcp_keys 17-28)
    for hcp_k in range(17, 29):
        grain = (fq1_key, 2, hcp_k, 1)
        if grain not in seen:
            seen.add(grain)
            rows.append(f"  ({esc(fq1_key)}, 2, {hcp_k}, 1)")

    # ── Bulk coverage assignments for remaining reps ──
    product_keys = [1, 3, 4]
    for rep_key in range(3, NUM_REPS + 2):
        num_hcps_assigned = random.randint(10, 20)
        assigned_hcps     = random.sample(range(1, NUM_HCPS + 2), num_hcps_assigned)
        for hcp_k in assigned_hcps:
            prod_k = random.choice(product_keys)
            grain  = (fq1_key, rep_key, hcp_k, prod_k)
            if grain not in seen:
                seen.add(grain)
                rows.append(f"  ({esc(fq1_key)}, {rep_key}, {hcp_k}, {prod_k})")

    write(f, ',\n'.join(rows) + ';')

# ── FCT_PRESCRIPTION_TERRITORY_MONTHLY ───────────────────────────────────
def generate_fct_prescription_territory_monthly(f):
    write(f, '\n-- ── fct_prescription_territory_monthly ─────────────────────────────────')
    write(f, '-- Pre-aggregated rollup of fct_prescription_weekly at territory-month grain')
    write(f, '-- Rebuilt nightly from atomic table — never loaded independently')
    write(f, 'INSERT INTO fct_prescription_territory_monthly (month_key, territory_rollup_key,')
    write(f, '    product_key, new_rx_count, total_rx_count, total_units,')
    write(f, '    brand_units, total_market_units, market_share_pct,')
    write(f, '    source_row_count, last_rebuilt_at) VALUES')

    rows        = []
    product_keys = [1, 3, 4]
    months       = []
    y, m = DATE_START.year, DATE_START.month
    while (y, m) <= (DATE_END.year, DATE_END.month):
        months.append(date(y, m, 1))
        m += 1
        if m > 12:
            m = 1
            y += 1

    seen = set()
    for month_key in months:
        for ter_rollup_key in range(1, len(TERRITORIES) + 1):
            for prod_key in product_keys:
                grain = (month_key, ter_rollup_key, prod_key)
                if grain in seen:
                    continue
                seen.add(grain)

                new_rx      = random.randint(200, 2000)
                total_rx    = int(new_rx * random.uniform(1.1, 1.8))
                units       = total_rx * random.randint(28, 90)
                mkt_units   = int(units / random.uniform(0.05, 0.60))
                mkt_share   = round(units / mkt_units * 100, 2) if mkt_units > 0 else None
                src_rows    = random.randint(80, 200)

                rows.append(
                    f"  ({esc(month_key)}, {ter_rollup_key}, {prod_key}, "
                    f"{new_rx}, {total_rx}, {units}, {units}, {mkt_units}, "
                    f"{'NULL' if mkt_share is None else mkt_share}, "
                    f"{src_rows}, '2024-12-31 03:00:00')"
                )

    write(f, ',\n'.join(rows) + ';')

# ── MAIN ──────────────────────────────────────────────────────────────────
def main():
    print('Generating seed data...')
    with open(OUTPUT_FILE, 'w') as f:
        write(f, '-- ============================================================')
        write(f, '-- seed_data.sql')
        write(f, '-- Generated by scripts/generate_seed_data.py')
        write(f, '-- Do not edit manually — regenerate from the script instead')
        write(f, '-- ============================================================')
        write(f, '')
        write(f, 'BEGIN;')

        generate_dim_date(f)
        generate_dim_month(f)
        generate_dim_territory(f)
        generate_dim_territory_rollup(f)
        generate_dim_product(f)
        generate_dim_visit_flags(f)
        generate_dim_audit(f)

        notes_pool = generate_call_notes_pool(5000)
        generate_dim_call_notes(f, notes_pool)

        generate_dim_rep(f)
        generate_dim_hcp(f)
        generate_bridge(f)
        generate_fct_hcp_visit(f, len(notes_pool))
        generate_fct_prescription_weekly(f)
        generate_fct_quota_attainment(f)
        generate_fct_hcp_coverage_target(f)
        generate_fct_prescription_territory_monthly(f)

        write(f, '')
        write(f, 'COMMIT;')

    print(f'Done. Output written to {OUTPUT_FILE}')

if __name__ == '__main__':
    main()
