import pytest
from stats import count_change_test, two_proportion_test, coverage_guard, adjust_pvalues
import pandas as pd

def test_count_change_plain_poisson():
    z, p = count_change_test(772, 549)
    assert z == pytest.approx(-6.1355, abs=0.001)

def test_count_change_quasi_poisson():
    z, p = count_change_test(772, 549, phi=26.05)
    assert z == pytest.approx(-1.202, abs=0.001)

def test_two_proportion_known_answer():
    z, p = two_proportion_test(772, 38729, 549, 33411)
    assert z == pytest.approx(-3.498, abs=0.001)

def test_bh_known_answer():
    pvals = adjust_pvalues([0.001, 0.04, 0.5])
    assert pvals == pytest.approx([0.003, 0.06, 0.5], abs=0.001)

def test_zero_cases():
    z1, p1 = count_change_test(0, 0) 
    z2, p2 = two_proportion_test(0, 0, 5, 100)
    assert (z1, p1)== (0.0, 1.0)
    assert (z2, p2) == (0.0, 1.0)

def test_guard_refuses_tuesday():
    with pytest.raises(ValueError):
        coverage_guard(pd.Timestamp("2020-12-08"))