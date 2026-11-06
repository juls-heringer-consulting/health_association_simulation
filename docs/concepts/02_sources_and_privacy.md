# 02 Sources, synthetic data and data protection

*Phase 1 (sources). Code: `python/kvsim/`, data: `data/sources/`.*

## One truth, many sources

The generator first builds **one consistent world** in memory (doctors, practices, cases,
payments ...), then exports slices of it in different formats - just like real systems
that each hold part of the same reality. That is why the warehouse can later reconcile the
sources: the Honorarbescheid (XML) must agree with the billing lines (CSV), the
Versorgungsgrad (Excel) with the register (CSV).

## Reproducibility

`random.Random(seed)` and `Faker.seed_instance(seed)` make every run identical. Change the
seed in `config/settings.toml` and you get a different but equally consistent world.
`tests/test_generator.py` proves it.

## Formats you will meet at a KV

| Format | Example here | What to watch |
|---|---|---|
| CSV | billing, register | delimiter `;`, encoding, decimal comma, header yes/no |
| fixed width | prescriptions | positions, padding, control totals in a trailer |
| XML | EBM, Bescheide, procedures | encoding declaration, optional elements, attributes vs. elements |
| JSON | TSS API, CRM | nesting, `null`, paging, ISO timestamps with offset |
| Excel | Bedarfsplanung | header not in row 1, merged cells, % formats, lists in cells |
| Text / Markdown | complaints, minutes | key-value headers, front matter, references inside the text |

**Encodings**: UTF-8 (with or without BOM) and Windows-1252 ("ANSI") look identical until
an umlaut appears. `männlich` read with the wrong encoding becomes `mÃ¤nnlich`.

## Data protection (DSGVO / SGB V)

A KV is **not** a treating doctor. It has no medical records (no anamnesis, findings,
letters). It receives billing data, which is still health data and therefore a special
category of personal data under Art. 9 GDPR.

Principles applied in this project:

| Principle | Implementation |
|---|---|
| **Pseudonymisation** | `patient_pseudonym = SHA-256(secret salt + insurance number)`. Same patient → same pseudonym, so you can count patients across practices, but you cannot get back to the person without the salt. |
| **Data minimisation** | Only the year of birth arrives, and the core load turns it into an age group and drops it. TSS requests only carry Kreis and age. |
| **Purpose limitation** | Roles see only the data of their task (see [security.md](../security.md)). |
| **Anonymisation of text** | Complaints contain no name of the person who complained. |

Why a **salt**? Insurance numbers have a known structure; without a secret salt someone
could hash all possible numbers and reverse the pseudonyms ("dictionary attack").

The real legal situation is more detailed (see [assumptions.md](../assumptions.md) A-40):
for billing, KVs do process identifying data. The *analytics* layer should not need it.

## Try it

```sql
-- the same patient at several practices in one quarter (counting without knowing who it is)
SELECT TOP 10 patient_pseudonym, quartal_code, COUNT(*) AS praxen
FROM core.abrechnungsfall
GROUP BY patient_pseudonym, quartal_code
ORDER BY praxen DESC;
```
