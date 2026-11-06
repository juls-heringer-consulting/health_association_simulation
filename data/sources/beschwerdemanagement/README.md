# Beschwerdemanagement (patient complaints)

| | |
|---|---|
| Simulated origin | Complaints mailbox: online form, e-mail, scanned letters and telephone notes, saved as text files at intake |
| Owner (in the KV) | Beschwerdemanagement (data protection: confidential) |
| Update frequency | continuous |
| Loaded into | `stg.beschwerden_txt` → `core.dokument` (type BESCHWERDE) + `core.dokument_bezug` |

## Files

`beschwerde_2025_001.txt` … - one file per complaint:

```
Eingangsdatum: 12.03.2025
Eingangskanal: Online-Formular
Kategorie: WARTEZEIT
Bezug-BSNR: 731234567
Betreff: Lange Wartezeit trotz Termin
Beschwerdeführende Person: (anonymisiert)

<free text>
```

## Known quirks

- Metadata only as `Key: value` header lines (parsed with `core.fn_text_field`).
- `Bezug-BSNR` is added by the intake team; patients themselves only name the practice.
- The person who complains is **anonymised** - complaints are personal data (DSGVO).
