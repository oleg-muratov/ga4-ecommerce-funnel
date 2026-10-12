"""Week-over-week tests and the coverage guard for the GA4 e-commerce funnel.

Counts (visits, purchasing visits) are compared with a quasi-Poisson test and
conversion with a two-proportion z-test; p-values are adjusted with
Benjamini-Hochberg. The coverage guard refuses comparisons the data cannot support.
"""
import pandas as pd
import scipy.stats
from statsmodels.stats.multitest import multipletests

FIRST_WEEK = pd.Timestamp("2020-11-02")         # first full week (Monday)
LAST_WEEK = pd.Timestamp("2021-01-25")          # last full week (Monday)
CART_TRACKED_FROM = pd.Timestamp("2020-11-30")  # first full week (Monday) with add_to_cart tracked again


def count_change_test(last_week_count, this_week_count, phi = 1):
    """
    Test whether a count changed between two weeks (normal approximation).

    Under the null both weeks share one rate, so Var(this - last) = phi * (this + last).
    phi = 1 is the plain Poisson test; phi > 1 is the quasi-Poisson version, where
    phi is the dispersion factor (how much more counts vary than Poisson assumes).

    Returns:
    (z, p): z-statistic and two-sided p-value. Two zero counts give (0.0, 1.0).
    """
    lwc = last_week_count
    twc = this_week_count
    if lwc == 0 and twc == 0:
        return 0.0, 1.0
    z = (twc - lwc) / ((phi * (twc + lwc)) ** 0.5)
    p = 2 * scipy.stats.norm.sf(abs(z))
    return float(z), float(p)


def two_proportion_test(last_week_purchases, last_week_visits, this_week_purchases, this_week_visits):
    """
    Test whether conversion (purchases / visits) changed between two weeks.

    Pooled two-proportion z-test: under the null both weeks share one rate,
    estimated as (all purchases) / (all visits).

    Returns:
    (z, p): z-statistic and two-sided p-value. A week with no visits, or a pooled
    rate of 0 or 1, gives (0.0, 1.0): there is nothing to test.
    """
    lwp = last_week_purchases
    twp = this_week_purchases
    lv = last_week_visits
    tv = this_week_visits
    if lv == 0 or tv == 0:
        return 0.0, 1.0
    pr = (lwp+twp)/(lv+tv)
    if pr == 0 or pr == 1:
        return 0.0, 1.0

    z = (twp/tv - lwp/lv)/ ((pr*(1-pr)*(1/tv + 1/lv))**0.5)
    p = 2 * scipy.stats.norm.sf(abs(z))
    return float(z), float(p)


def coverage_guard(timestamp, uses_cart = False):
    """
    Refuse a week the data cannot support; return nothing if the week is fine.

    timestamp: the Monday that starts the week.
    uses_cart: True if the metric uses add_to_cart (not fully tracked before CART_TRACKED_FROM).


    Raises:
    ValueError if the day is not a Monday, the week is not a full week inside the data
    (FIRST_WEEK to LAST_WEEK), or the metric uses add_to_cart before CART_TRACKED_FROM.


    """
    if timestamp.dayofweek !=0:
        raise ValueError(f"{timestamp.date()}: The day is not Monday")
    elif timestamp < FIRST_WEEK or timestamp > LAST_WEEK:
        raise ValueError(f"{timestamp.date()}: The whole week is not inside the data")
    elif uses_cart and timestamp < CART_TRACKED_FROM:


        raise ValueError(f"{timestamp.date()}: add_to_cart is not fully tracked before {CART_TRACKED_FROM.date()}")


def adjust_pvalues(pvals):
    """
    Adjust p-values for multiple testing using the Benjamini-Hochberg method.

    Parameters:
    pvals (list or array-like): List of p-values to adjust.

    Returns:
    list: Adjusted p-values.
    """
    if len(pvals) == 0:
        return []

    _, adj_pvals, _, _ = multipletests(pvals, method='fdr_bh')

    return adj_pvals.tolist()


def week_over_week(weekly, phi_visits, phi_purchases):
    """
    Compare each week with the week before, for visits, purchasing visits and conversion.

    weekly: one row per consecutive week (index = the week's Monday), with columns
            visits, purchasing_visits and conversion.
    phi_visits, phi_purchases: dispersion factors for the two count tests.

    Returns:
    DataFrame with one row per week and metric: week, metric, last, this, z, p.
    p-values are not adjusted here; apply adjust_pvalues once to all tests combined.

    Raises:
    ValueError if two neighbouring rows are not consecutive weeks, or if
    coverage_guard refuses a week.
    """
    rows = []
    for i in range(1, len(weekly)):
        lw = weekly.iloc[i-1]
        tw = weekly.iloc[i]
        label = weekly.index[i]
        if (label - weekly.index[i-1]).days != 7:
            raise ValueError(f"{weekly.index[i-1].date()} -> {label.date()}: the weeks are not consecutive")
        coverage_guard(label, uses_cart=False)
        coverage_guard(weekly.index[i-1], uses_cart=False)

        z, p = count_change_test(lw['visits'], tw['visits'], phi=phi_visits)
        visits_dict = {"week": label, "metric": "visits", "last": lw['visits'], "this": tw['visits'], "z": z, "p": p}
        rows.append(visits_dict)
        z, p = count_change_test(lw['purchasing_visits'], tw['purchasing_visits'], phi=phi_purchases)
        purchasing_visits_dict = {"week": label, "metric": "purchasing_visits", "last": lw['purchasing_visits'], "this": tw['purchasing_visits'], "z": z, "p": p}
        rows.append(purchasing_visits_dict)

        z, p = two_proportion_test(lw['purchasing_visits'], lw['visits'], tw['purchasing_visits'], tw['visits'])
        conversion_dict = {"week": label, "metric": "conversion", "last": lw['conversion'], "this": tw['conversion'], "z": z, "p": p}
        rows.append(conversion_dict)
    return pd.DataFrame(rows)
