"""Metrics, baselines, and comparison tables."""

from __future__ import annotations

import numpy as np
import pandas as pd
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score


def regression_metrics(y_true, y_pred) -> dict:
    y_true = np.asarray(y_true, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float)
    mae = float(mean_absolute_error(y_true, y_pred))
    mse = float(mean_squared_error(y_true, y_pred))
    rmse = float(np.sqrt(mse))
    r2 = float(r2_score(y_true, y_pred))
    medae = float(np.median(np.abs(y_true - y_pred)))
    denom = np.abs(y_true) + np.abs(y_pred)
    denom = np.where(denom == 0.0, 1.0, denom)
    smape = float(100.0 * np.mean(2.0 * np.abs(y_pred - y_true) / denom))
    mape_mask = np.abs(y_true) > 1.0
    mape = (
        float(np.mean(np.abs((y_true[mape_mask] - y_pred[mape_mask]) / y_true[mape_mask])) * 100.0)
        if mape_mask.any()
        else np.nan
    )
    return {
        "MAE": mae,
        "MSE": mse,
        "RMSE": rmse,
        "R2": r2,
        "MedianAE": medae,
        "sMAPE": smape,
        "MAPE_gt1": mape,
    }


def product_mean_baseline(y_train: pd.Series, product_train: pd.Series, product_test: pd.Series) -> np.ndarray:
    means = y_train.groupby(product_train).mean()
    global_mean = float(y_train.mean())
    return product_test.map(means).fillna(global_mean).to_numpy(dtype=float)


def mean_baseline(y_train: pd.Series, n_test: int) -> np.ndarray:
    return np.full(n_test, float(y_train.mean()), dtype=float)


def metrics_frame(named: dict[str, dict]) -> pd.DataFrame:
    return pd.DataFrame(named).T.round(4)
