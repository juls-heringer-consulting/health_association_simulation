"""Reads config/settings.toml and exposes typed settings and project paths."""
from __future__ import annotations

import tomllib
from dataclasses import dataclass
from datetime import date
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
SOURCES_DIR = PROJECT_ROOT / "data" / "sources"
DOCS_DIR = PROJECT_ROOT / "docs"
SETTINGS_FILE = PROJECT_ROOT / "config" / "settings.toml"


@dataclass(frozen=True)
class Settings:
    server: str
    database: str
    driver: str
    trust_server_certificate: bool
    seed: int
    year: int
    export_date: date
    patient_pool_size: int
    cases_per_fte_quarter: float
    tss_requests: int
    member_enquiries: int
    complaints: int
    pseudonym_salt: str
    inject_dq_issues: bool

    def connection_string(self, database: str | None = None) -> str:
        parts = [
            f"DRIVER={{{self.driver}}}",
            f"SERVER={self.server}",
            f"DATABASE={database or self.database}",
            "Trusted_Connection=yes",  # Windows authentication
        ]
        if self.trust_server_certificate:
            parts.append("TrustServerCertificate=yes")
        return ";".join(parts) + ";"


def load_settings(path: Path = SETTINGS_FILE) -> Settings:
    with path.open("rb") as fh:
        raw = tomllib.load(fh)
    db, gen = raw["database"], raw["generation"]
    return Settings(
        server=db["server"],
        database=db["database"],
        driver=db["driver"],
        trust_server_certificate=bool(db.get("trust_server_certificate", False)),
        seed=int(gen["seed"]),
        year=int(gen["year"]),
        export_date=date.fromisoformat(gen["export_date"]),
        patient_pool_size=int(gen["patient_pool_size"]),
        cases_per_fte_quarter=float(gen["cases_per_fte_quarter"]),
        tss_requests=int(gen["tss_requests"]),
        member_enquiries=int(gen["member_enquiries"]),
        complaints=int(gen["complaints"]),
        pseudonym_salt=str(gen["pseudonym_salt"]),
        inject_dq_issues=bool(gen.get("inject_dq_issues", False)),
    )
