## Below-quota rep coverage analysis

The query returned 13 reps below 80% quota attainment in FQ1 FY2024
with unvisited A-tier physicians. The results split into two
structurally different problems.

Two reps — Sarah Chen at 66.99% and Marcus Williams at 70.79% —
show zero total visits and zero unique HCPs contacted during the
quarter. These are not targeting problems. Both reps made no field
activity whatsoever, and their quota misses reflect complete
disengagement rather than misdirected effort.

The remaining 11 below-quota reps made between 3 and 11 visits
during the quarter but directed none of those visits toward their
assigned A-tier physicians — the highest prescribing-potential
targets in their coverage plans. Arthur James made 3 visits across
2 unique physicians, none of them A-tier. Amber Perez made 11 visits
across 11 unique physicians with the same result. These reps were
active in the field but not calling on the right people.

The warehouse answers the business question with precision: quota
underperformance in this cohort is split between effort failure and
targeting failure — two problems that require different managerial
responses. A rep with zero visits needs a performance conversation.
A rep visiting 11 physicians but missing all their A-tier targets
needs coaching on territory prioritization.

## Rolling 13-week prescription trend with week-over-week growth

Across 223 A and B-tier physicians tracked over the June through
October 2023 display window, weekly prescription trends distribute
consistently across all three products. For Keytruda, 772 physician-
week observations were stable, 485 showed significant week-over-week
increases, 464 showed moderate drops, and 331 showed significant drops
across 163 unique physicians. Humira and Ozempic show nearly identical
distributions.

The consistency across products indicates no systemic trend in either
direction — the portfolio is volatile week to week but not declining or
growing at a population level. A brand team would use this distribution
as a baseline to identify outliers: physicians whose personal trend
pattern deviates significantly from the population norm.

## Rep quota attainment ranking within district

The Mid-Atlantic District has the widest performance spread of any
district. David Park leads at 114.89% for Humira while Sarah Chen
ranks last at 66.85% — a 48 percentage point gap between first and
last in a district of 7 reps. Sarah Chen ranks last for all three
products with attainment between 66.85% and 66.99%, sitting 25 to
29 points below her district average across the board.

The Northeast District is the most competitive. With 16 reps and a
district average above 94% for all three products, even the bottom
of the leaderboard shows strong numbers — Lindsey Roman ranks 16th
for Humira at 77.96%, a number that would rank mid-table in other
districts. The PERCENT_RANK column makes this context visible: the
same attainment percentage carries a different meaning depending on
the competitive level of the district.

The Southeast and Southwest Districts follow similar patterns. Marcus
Williams ranks last in the Southeast for all three products with
attainment between 70.79% and 70.89%, 25 to 27 points below a
district average sitting above 96%. The Southwest District is the
strongest overall — district averages range from 92.3% to 99.6% —
with Crystal Whitehead leading for both Humira and Ozempic above
122%.

## Territory transfer historical attribution

James Rivera transferred from Northeast Boston to Southwest Dallas
on March 1 2024. The query returns 8 visits — 4 pre-transfer and
4 post-transfer — with each visit correctly attributed to the
territory that was active at the time it occurred.

The pre-transfer rows show `territory_at_time_of_visit` as Northeast
Boston for all four visits in January and February 2024. The
post-transfer rows show Southwest Dallas for all four visits in March
and April 2024. The `current_territory_name` column reads Southwest
Dallas on every row — both pre and post-transfer — because the Type 6
overlay always reflects where Rivera is today regardless of which
historical row is being viewed.

This is the as-was versus as-is distinction in action. A report asking
which territory these visits belong to historically gets Northeast
Boston for January and February. A report asking where Rivera is
assigned right now gets Southwest Dallas from every row. Both answers
come from the same dimension without any additional filtering or
joining logic.

## Co-promotion credit split

Dr. Robert Kim is co-promoted by Sarah Chen and James Rivera with a
60/40 credit split. He wrote 7,702 total Keytruda prescriptions
across the dataset representing 455,978 units.

Without the bridge table, both reps would receive full credit —
7,702 prescriptions each — producing a combined total of 15,404
prescriptions for a physician who wrote 7,702. The warehouse would
overstate sales force performance by exactly 7,702 prescriptions
and 455,978 units.

With the bridge table weight applied, Sarah Chen receives 60% —
4,621.2 attributed prescriptions and 273,584 units. James Rivera
receives 40% — 3,080.8 attributed prescriptions and 182,394 units.

## HCP segment tier upgrade impact

Dr. Patricia Moore was reclassified from B-tier to A-tier on January
15 2024. The query uses the SCD Type 2 history on dim_hcp to split
her prescription volume into pre and post-upgrade periods and compare
average weekly volume between them.

The results are mixed across products — the upgrade is justified for
Humira but not for Keytruda or Ozempic.

For Humira, average weekly prescriptions nearly doubled after the
upgrade — from 28.5 per week in the B-tier period to 54.6 in the
A-tier period, a 91.6% increase. Peak weekly volume also rose from
42 to 82. The reclassification decision was validated by the data.

For Keytruda and Ozempic the picture reverses. Keytruda average
weekly volume fell from 59.8 to 27.7 — a 53.7% decline. Ozempic
fell from 49.1 to 23.9 — a 51.3% decline. Both products show the
post-upgrade period performing at roughly half the rate of the
B-tier baseline.

## Year-over-year quota attainment comparison

Across all four districts in FQ1 FY2024, year-over-year performance
is mixed — the sales force is neither uniformly improving nor
declining. Growth and decline coexist within every district and
every product.

Ozempic shows the strongest year-over-year growth overall. In the
Northeast District, David Caldwell grew 46.9% and Alec Hickman grew
45.8%. In the Southeast, Joshua Blair grew 75% and Gabrielle Davis
grew 52.9%. The Southwest shows Crystal Whitehead up 29% and Margaret
Hawkins up 23.6%. Ozempic is the one product where growth outweighs
decline across most districts.

Humira and Keytruda tell a more divided story. In the Mid-Atlantic
District, Daniel Hahn grew Humira 43.9% year over year while Arthur
James declined 32.3% on the same product in the same district. In
the Northeast, Paula Moreno grew Keytruda 45.2% while Cristian Santos
declined 27.6% for the same product in the same district. These
intra-district contrasts suggest territory-level factors rather than
product-level trends are driving the divergence.

Sarah Chen and Marcus Williams both show year-over-year declines
across all three products. Sarah Chen's Keytruda declined 32.2% —
from 715 actual units last year to 485 this year. Marcus Williams'
Ozempic declined 40.2% — from 729 to 436. Both are the steepest
declines in their respective districts and both are compounding on
already-below-quota current performance.

## HCP decile ranking writeback validation

The query recalculates physician prescribing rankings from scratch
using actual lifetime prescription data and compares them to the
rankings stored in dim_hcp. If a physician's stored rank no longer
matches what the data says, they need a refresh.

892 of 1,005 physician-product combinations are flagged. The
mismatch is not subtle — physicians with the highest actual
prescription volumes have stored rankings of 10 (bottom tier)
when the data says they should be ranked 1 (top tier). The
pattern is completely inverted across the board.

The reason is straightforward. The stored decile_rank values in
dim_hcp were generated randomly during seeding with no connection
to actual volume. The recalculated rankings are based on real
prescription totals — so the two sets of numbers have nothing to
do with each other.

In practice, this is exactly the problem the query is designed to
catch. Decile rankings in a real warehouse would be recomputed
periodically from fresh Rx data and written back into the
dimension. This query is the check that tells you when that
refresh is overdue — and here it flags every physician in the
dataset.

## Product indication expansion impact

Humira received FDA approval for a second indication — expanding
from rheumatoid arthritis only to rheumatoid arthritis and plaque
psoriasis — on November 1 2023. The query uses the Type 2 SCD
history on dim_product to split prescriptions into pre and
post-expansion periods and compare average weekly volume per
physician between them.

The results only show the post-expansion period. The pre-expansion
rows are missing from the output entirely, which means the LAG
comparison columns are blank — there is nothing to compare against.

The reason is a seed data gap. The pre-expansion product row
(PRD-HUM-001) has an expiration date of November 1 2023 in
dim_product, but the prescription rows in fct_prescription_weekly
were not split across both product keys. All Humira prescriptions
appear to have been loaded against the current product row only,
leaving the pre-expansion period empty.

What the post-expansion data does show is consistent average
weekly prescribing across all six specialties — ranging from 41.1
prescriptions per physician per week in Internal Medicine to 46.9
in Family Practice. Oncology has the highest total volume at
299,993 prescriptions from 62 unique prescribers. The distribution
across specialties is what you would expect from a drug that now
covers both rheumatological and dermatological indications — broad
specialty reach rather than concentration in one area.

The before/after comparison the query was designed to produce
requires fixing the seed data so that pre-November 2023 Humira
prescriptions reference PRD-HUM-001 and post-November prescriptions
reference PRD-HUM-002. With that correction in place the LAG
comparison would show whether average weekly volume changed after
the indication expansion.

## Data quality audit — superseded batch investigation

The week ending March 3 2024 contained a vendor error — IQVIA's
unit counts were inflated across the board and a corrected file
arrived the following week. The query surfaces every affected
physician-product combination, compares the two batches, and
quantifies the discrepancy.

697 rows were affected spanning all three products and physicians
across every segment tier. The errors were not uniformly distributed
— some rows were dramatically inflated while others were
undercounted, and a small number showed the corrected file
reporting higher values than the original.

The most severe inflation cases involved percentage discrepancies
in the thousands. Dr. Vanessa Fernandez's Keytruda row showed
superseded units of 6,208 against corrected units of 78 — a
7,859% inflation. Dr. Fernando Donovan's Keytruda row showed
5,613 superseded against 84 corrected — a 6,582% inflation. Dr.
Karen Benjamin's Keytruda row showed the largest absolute
discrepancy at 12,731 units overstated.

Not all errors were inflations. 23 rows show negative
`units_discrepancy` values — meaning the corrected file reported
higher units than the original. Dr. Patrick Cook's Humira row
shows corrected units of 7,221 against superseded units of 291,
a net correction of 6,930 units upward. These bidirectional errors
confirm the vendor error was not a systematic multiplier applied
uniformly but a data processing failure that corrupted values
in both directions.

Without the audit dimension and the superseded batch flag, both
versions of this data would coexist in the warehouse with no way
to distinguish which was authoritative. The `dq_flag` on each
row makes the correction traceable — analysts querying
prescription data for the week of March 3 2024 can explicitly
exclude superseded rows and work only from the corrected batch.
