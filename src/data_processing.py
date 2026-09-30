"""Load and validate the synthetic sales table."""

from __future__ import annotations

from pathlib import Path

import pandas as pd

from src.config import DATA_FILE, TARGET


def load_orders(path: Path | None = None) -> pd.DataFrame:
    data_path = Path(path) if path is not None else DATA_FILE
    if not data_path.exists():
        raise FileNotFoundError(
            f"Dataset not found: {data_path.name} (expected under data/)"
        )
    df = pd.read_excel(data_path)
    df["Date"] = pd.to_datetime(df["Date"], dayfirst=True, errors="coerce")
    if TARGET not in df.columns:
        raise ValueError(f"Missing target column: {TARGET}")
    if df[TARGET].isna().any():
        raise ValueError("Target contains missing values")
    return df


def accounting_identity(df: pd.DataFrame) -> pd.Series:
    """Profit reconstructed from cost and revenue (not a learning target)."""
    return df["Quantity"] * (
        df["Unit_Price_TL"] * (1.0 - df["Discount_Rate"]) - df["Unit_Cost_TL"]
    )
