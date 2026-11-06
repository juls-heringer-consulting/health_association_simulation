"""Identifier helpers: LANR, BSNR, EFN, IK, KVNR and patient pseudonyms.

All numbers produced here are SYNTHETIC. They follow the public structure of the
real identifiers so that format and check-digit validation can be practised.
"""
from __future__ import annotations

import hashlib
import random
import string

# --- LANR (Lebenslange Arztnummer) -------------------------------------------------
# 9 digits = 6-digit doctor id + 1 check digit + 2-digit Fachgruppe code.
# The first 7 digits stay with the doctor for life; the last 2 depend on the specialty.
# Check digit: digits 1-6 weighted alternately 4 and 9, sum mod 10, then 10 minus that
# (a result of 10 becomes 0).
LANR_WEIGHTS = (4, 9, 4, 9, 4, 9)


def lanr_check_digit(first_six: str) -> int:
    if len(first_six) != 6 or not first_six.isdigit():
        raise ValueError(f"expected 6 digits, got {first_six!r}")
    total = sum(int(d) * w for d, w in zip(first_six, LANR_WEIGHTS))
    return (10 - total % 10) % 10


def make_lanr(doctor_id: int, fachgruppe_code: str) -> str:
    six = f"{doctor_id:06d}"
    return f"{six}{lanr_check_digit(six)}{fachgruppe_code}"


def lanr_is_valid(lanr: str) -> bool:
    return (
        len(lanr) == 9
        and lanr.isdigit()
        and lanr_check_digit(lanr[:6]) == int(lanr[6])
    )


# --- BSNR (Betriebsstaettennummer) -------------------------------------------------
# 9 digits; the first two identify the KV region (73 = Saarland in this project).
def make_bsnr(kv_code: str, serial: int) -> str:
    return f"{kv_code}{serial:07d}"


# --- EFN (Einheitliche Fortbildungsnummer of the Aerztekammern) ----------------------
# 15 digits starting with 276 (country code Germany); last digit = Luhn check digit.
def luhn_check_digit(number: str) -> int:
    total = 0
    for i, ch in enumerate(reversed(number)):
        d = int(ch)
        if i % 2 == 0:  # positions that get doubled when the check digit is appended
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return (10 - total % 10) % 10


def make_efn(rng: random.Random) -> str:
    body = "276" + "".join(rng.choice(string.digits) for _ in range(11))
    return body + str(luhn_check_digit(body))


# --- IK (Institutionskennzeichen) --------------------------------------------------
# 9 digits. Real IKs of the named Krankenkassen are NOT used; these are synthetic.
def make_ik(rng: random.Random) -> str:
    return "10" + "".join(rng.choice(string.digits) for _ in range(7))


# --- KVNR (Krankenversichertennummer) and pseudonym ----------------------------------
# The KVNR never leaves the generator: only its salted SHA-256 hash is exported.
def make_kvnr(rng: random.Random) -> str:
    return rng.choice(string.ascii_uppercase) + "".join(rng.choice(string.digits) for _ in range(9))


def pseudonymize(kvnr: str, salt: str) -> str:
    return hashlib.sha256((salt + kvnr).encode("utf-8")).hexdigest().upper()


# --- TSS Vermittlungscode ----------------------------------------------------------
_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O, 1/I to avoid confusion


def make_vermittlungscode(rng: random.Random) -> str:
    blocks = ["".join(rng.choice(_CODE_ALPHABET) for _ in range(4)) for _ in range(3)]
    return "-".join(blocks)
