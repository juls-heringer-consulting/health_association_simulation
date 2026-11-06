"""Unit tests for identifier helpers (check digits, formats, pseudonyms)."""
import random

from kvsim import ids


def test_lanr_check_digit_known_example():
    # 123456: 1*4 + 2*9 + 3*4 + 4*9 + 5*4 + 6*9 = 144 -> 10 - 4 = 6
    assert ids.lanr_check_digit("123456") == 6
    assert ids.make_lanr(123456, "01") == "123456601"


def test_lanr_check_digit_zero_case():
    # a sum that is a multiple of 10 must give 0, not 10
    six = next(f"{n:06d}" for n in range(100000, 999999)
               if sum(int(d) * w for d, w in zip(f"{n:06d}", ids.LANR_WEIGHTS)) % 10 == 0)
    assert ids.lanr_check_digit(six) == 0


def test_generated_lanr_is_valid():
    assert ids.lanr_is_valid(ids.make_lanr(654321, "68"))
    assert not ids.lanr_is_valid("654321968")   # wrong check digit


def test_bsnr_starts_with_kv_code():
    assert ids.make_bsnr("73", 1234567) == "731234567"


def test_efn_luhn():
    efn = ids.make_efn(random.Random(1))
    assert len(efn) == 15 and efn.startswith("276")
    assert ids.luhn_check_digit(efn[:-1]) == int(efn[-1])


def test_pseudonym_is_stable_and_salted():
    a = ids.pseudonymize("A123456789", "salt-1")
    assert a == ids.pseudonymize("A123456789", "salt-1")
    assert a != ids.pseudonymize("A123456789", "salt-2")
    assert len(a) == 64
