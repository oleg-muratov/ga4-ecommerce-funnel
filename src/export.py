"""Write the CSV files the Tableau dashboard reads."""
from pathlib import Path

import db_dtypes  # noqa: F401  (lets pandas read the BigQuery date type)
import pandas as pd

from stats import (FIRST_WEEK, LAST_WEEK, dispersion,
                   week_over_week, adjust_pvalues, CART_TRACKED_FROM)

REPO = Path(__file__).resolve().parents[1]
VISITS_FILE = REPO / "data" / "cache" / "02_sessions.parquet"
OUT_DIR = REPO / "tableau"


def load_visits():
    """One row per visit, with a week column, full weeks only."""
    data_df = pd.read_parquet(VISITS_FILE, engine='pyarrow')
    data_df['visit_start_date'] = pd.to_datetime(data_df['visit_start_date'])
    data_df['week'] = data_df['visit_start_date'].dt.to_period("W-SUN").dt.start_time
    start_date = FIRST_WEEK
    end_date = LAST_WEEK + pd.Timedelta(days=6)
    filtered_df = data_df[data_df['visit_start_date'].between(start_date, end_date)]

    return filtered_df


def weekly_table(visits):
    """One row per week: visits, purchasing_visits, conversion."""
    weekly = visits.groupby('week').agg(
    visits=('user_pseudo_id', 'size'),
    purchasing_visits= ('has_purchase', 'sum')
    )
    weekly['conversion']= weekly['purchasing_visits'] / weekly['visits']
    return weekly



def export_weekly_metrics(weekly):
    """weekly_metrics.csv: week-over-week tests with BH-adjusted p-values."""
    phi_visits = dispersion(weekly['visits'])
    phi_purchasing_visits = dispersion(weekly['purchasing_visits'])
    results = week_over_week(weekly, phi_visits, phi_purchasing_visits)
    results['p_adj'] = adjust_pvalues(results['p'])
    results['flag'] = results['p_adj'] < 0.05
    results.to_csv(OUT_DIR / "weekly_metrics.csv", index=False)
    print(f"weekly_metrics.csv: {len(results)} rows, {results['flag'].sum()} flagged")

def export_funnel_by_device(visits):
    """funnel_by_device.csv: share of visits reaching each funnel step, by device.

    Only weeks from CART_TRACKED_FROM onwards, so the add_to_cart step is fully recorded.
    """
    filtered_visits = visits[visits['visit_start_date'] >= CART_TRACKED_FROM]
    funnel = filtered_visits.groupby('device_category').agg(
    n_view_item=('has_view_item', 'sum'),
    n_add_to_cart=('has_add_to_cart', 'sum'),
    n_begin_checkout=('has_begin_checkout', 'sum'),
    n_add_shipping_info=('has_add_shipping_info', 'sum'),
    n_add_payment_info=('has_add_payment_info', 'sum'),
    n_purchase=('has_purchase', 'sum'),
    visits = ('user_pseudo_id', 'size')
    )

    for step in ["view_item", "add_to_cart", "begin_checkout", "add_shipping_info", "add_payment_info", "purchase"]:
        funnel[f"share_{step}"] = funnel[f"n_{step}"] / funnel['visits']

    funnel = funnel.reset_index()
    funnel.to_csv(OUT_DIR / "funnel_by_device.csv", index=False)
    print(f"funnel_by_device.csv: {len(funnel)} rows, {funnel['device_category'].nunique()} device categories")

def export_channel_device(visits):
    """channel_device.csv: visits, purchasing visits and conversion for each channel group x device.

    Uses all full weeks (FIRST_WEEK to LAST_WEEK); add_to_cart is not involved.
    """
    medium_device_group = visits.groupby(['medium_group', 'device_category']).agg(
    visits=('user_pseudo_id', 'size'),
    purchasing_visits= ('has_purchase', 'sum')
    )
    medium_device_group['conversion']= medium_device_group['purchasing_visits'] / medium_device_group['visits']
    medium_device_group = medium_device_group.reset_index()
    medium_device_group.to_csv(OUT_DIR / "channel_device.csv", index=False)
    print(f"channel_device.csv: {len(medium_device_group)} rows, {medium_device_group['device_category'].nunique()} device categories")    


def main():
    visits = load_visits()
    weekly = weekly_table(visits)
    export_weekly_metrics(weekly)
    export_funnel_by_device(visits)
    export_channel_device(visits)


if __name__ == "__main__":
    main()