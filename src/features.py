"""Row-wise features, leakage drops, chronological split, preprocessor."""

from __future__ import annotations

import math

import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.preprocessing import OneHotEncoder

from src.config import (
    CAT_FEATURES,
    LEAKAGE_DROP,
    REDUNDANT_DROP,
    TARGET,
    TEST_SIZE,
)


def add_rowwise_features(frame: pd.DataFrame) -> pd.DataFrame:
    out = frame.copy()
    ts = pd.to_datetime(out["Date"])
    out["year"] = ts.dt.year.astype(int)
    out["month"] = ts.dt.month.astype(int)
    out["day"] = ts.dt.day.astype(int)
    out["day_of_week"] = ts.dt.dayofweek.astype(int)
    out["week_of_year"] = ts.dt.isocalendar().week.astype(int)
    out["quarter"] = ts.dt.quarter.astype(int)
    out["is_weekend"] = (ts.dt.dayofweek >= 5).astype(int)
    out["is_month_start"] = ts.dt.is_month_start.astype(int)
    out["is_month_end"] = ts.dt.is_month_end.astype(int)
    out["net_unit_price"] = out["Unit_Price_TL"] * (1.0 - out["Discount_Rate"])
    out["list_revenue"] = out["Quantity"] * out["Unit_Price_TL"]
    out["discount_value_unit"] = out["Unit_Price_TL"] * out["Discount_Rate"]
    return out


def chronological_masks(dates: pd.Series, test_size: float = TEST_SIZE):
    unique_dates = pd.to_datetime(dates).sort_values().unique()
    n_test = max(1, int(math.ceil(len(unique_dates) * test_size)))
    cutoff = pd.Timestamp(unique_dates[-n_test])
    parsed = pd.to_datetime(dates)
    train_mask = parsed < cutoff
    test_mask = ~train_mask
    return train_mask, test_mask, cutoff


def model_matrix(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.Series]:
    featured = add_rowwise_features(df)
    drop_cols = [c for c in LEAKAGE_DROP + REDUNDANT_DROP if c in featured.columns]
    model_df = featured.drop(columns=drop_cols)
    X = model_df.drop(columns=[TARGET])
    y = model_df[TARGET]
    return X, y


def numeric_features(X: pd.DataFrame) -> list[str]:
    return [c for c in X.columns if c not in CAT_FEATURES]


def tree_preprocessor(X: pd.DataFrame) -> ColumnTransformer:
    return ColumnTransformer(
        transformers=[
            ("num", "passthrough", numeric_features(X)),
            (
                "cat",
                OneHotEncoder(handle_unknown="ignore", sparse_output=False),
                CAT_FEATURES,
            ),
        ],
        remainder="drop",
        verbose_feature_names_out=False,
    )
