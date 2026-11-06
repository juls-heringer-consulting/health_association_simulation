"""Tests for the synthetic world: reproducibility and built-in consistency rules."""
import hashlib
from dataclasses import replace

import pytest

from kvsim import ids
from kvsim.config import load_settings
from kvsim.generator import OPEN_END, build_world


@pytest.fixture(scope="module")
def world():
    return build_world(load_settings())


def fingerprint(w) -> str:
    parts = [a.lanr for a in w.aerzte]
    parts += [f"{f.fallnummer}:{f.patient.pseudonym}:{len(f.leistungen)}" for f in w.faelle]
    parts += [f"{h.nr}:{h.brutto}" for h in w.honorar]
    return hashlib.sha256("|".join(parts).encode()).hexdigest()


def test_same_seed_gives_same_world(world):
    assert fingerprint(world) == fingerprint(build_world(load_settings()))


def test_different_seed_gives_different_world(world):
    other = build_world(replace(load_settings(), seed=42))
    assert fingerprint(world) != fingerprint(other)


def test_all_lanr_valid_and_unique(world):
    lanrs = [a.lanr for a in world.aerzte]
    assert len(lanrs) == len(set(lanrs))
    assert all(ids.lanr_is_valid(x) for x in lanrs)
    assert all(a.lanr.endswith(a.fachgruppe) for a in world.aerzte)


def test_one_teilnahme_at_a_time(world):
    for a in world.aerzte:
        periods = sorted((t.von, t.bis) for t in a.teilnahmen)
        for (_, end1), (start2, _) in zip(periods, periods[1:]):
            assert end1 <= start2, a.lanr


def test_status_history_is_gapless(world):
    for t in world.teilnahmen:
        assert t.status[0].von == t.von
        for p1, p2 in zip(t.status, t.status[1:]):
            assert p1.bis == p2.von
        assert t.status[-1].bis == OPEN_END


def test_services_only_on_active_days(world):
    for f in world.faelle:
        for l in f.leistungen:
            assert any(t.praxis is f.praxis and t.active_on(l.datum) for t in l.arzt.teilnahmen)


def test_behandlungsfall_is_unique_per_patient_practice_quarter(world):
    keys = [(f.praxis.bsnr, f.quartal, f.patient.pseudonym) for f in world.faelle]
    assert len(keys) == len(set(keys))


def test_tss_appointment_after_request(world):
    assert all(a.termin > a.eingang for a in world.tss if a.termin is not None)
