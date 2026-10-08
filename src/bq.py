import pandas as pd
from pathlib import Path
import sys
from google.cloud import bigquery
from check_connection import load_env
REPO = Path(__file__).resolve().parents[1]

def main(path , max_gb = 5) -> pd.DataFrame:
    load_env()
    SQL = Path(path).read_text()
    to_path = REPO / "data" / "cache" / (Path(path).stem + ".parquet")
    if to_path.exists():
        print(f"Load from cache at {to_path}")
        return pd.read_parquet(to_path)
    client = bigquery.Client()
    dry = client.query(SQL, job_config=bigquery.QueryJobConfig(dry_run=True))
    print(f"would scan {dry.total_bytes_processed / 1e6:.1f} MB")
    if dry.total_bytes_processed > max_gb * 1e9:
        raise ValueError(f"The query would scan too much data, the limit is {max_gb} GB.")
    result = client.query(SQL).to_dataframe()
    to_path.parent.mkdir(parents=True, exist_ok=True)
    result.to_parquet(to_path, index=False)
    return result


if __name__ == "__main__":
    df = main(sys.argv[1])
    print(df.shape)
