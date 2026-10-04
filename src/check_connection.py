"""Check BigQuery access: credentials, project, and one cheap query.

Run from the repo root:  python src/check_connection.py
Expected: your project ID, a dry-run estimate of about 40 MB, and days = 92.
"""
import os
from pathlib import Path

from google.cloud import bigquery

SQL = """
SELECT COUNT(DISTINCT event_date) AS days
FROM `bigquery-public-data.ga4_obfuscated_sample_ecommerce.events_*`
"""


def load_env(path: Path = Path(__file__).resolve().parents[1] / ".env") -> None:
    """Read KEY=VALUE lines from .env into the environment (no extra package needed)."""
    if not path.exists():
        return
    for line in path.read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            os.environ.setdefault(key.strip(), value.strip())


def main() -> None:
    load_env()
    client = bigquery.Client()
    print("project:", client.project)
    dry = client.query(SQL, job_config=bigquery.QueryJobConfig(dry_run=True))
    print(f"would scan {dry.total_bytes_processed / 1e6:.1f} MB")
    print(client.query(SQL).to_dataframe())


if __name__ == "__main__":
    main()
