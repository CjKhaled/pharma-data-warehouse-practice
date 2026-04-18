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
