"""Permutation importance, SHAP, and report figures."""

from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import seaborn as sns
from sklearn.inspection import permutation_importance
from sklearn.pipeline import Pipeline

from src.config import ACCENT, PRIMARY, SECOND
from src.evaluate import metrics_frame

sns.set_theme(style="whitegrid", context="notebook")
plt.rcParams.update(
    {
        "figure.dpi": 120,
        "savefig.dpi": 140,
        "font.size": 10,
        "axes.titlesize": 12,
        "axes.labelsize": 10,
        "axes.unicode_minus": False,
        "font.family": "DejaVu Sans",
    }
)


def encoded_matrix(pipeline: Pipeline, X: pd.DataFrame) -> pd.DataFrame:
    pre = pipeline.named_steps["pre"]
    names = pre.get_feature_names_out()
    return pd.DataFrame(pre.transform(X), columns=names, index=X.index)


def tree_shap(pipeline: Pipeline, X: pd.DataFrame) -> tuple[np.ndarray, float, pd.DataFrame]:
    """SHAP values on the encoded test matrix (TreeSHAP / XGBoost contribs)."""
    import shap
    import xgboost as xgb

    X_enc = encoded_matrix(pipeline, X)
    model = pipeline.named_steps["model"]
    if isinstance(model, xgb.XGBRegressor):
        dmat = xgb.DMatrix(X_enc)
        contrib = model.get_booster().predict(dmat, pred_contribs=True)
        return contrib[:, :-1], float(contrib[0, -1]), X_enc
    explainer = shap.TreeExplainer(model)
    values = np.asarray(explainer.shap_values(X_enc))
    expected = float(np.asarray(explainer.expected_value).reshape(-1)[0])
    return values, expected, X_enc


def _bar_color(name: str) -> str:
    if "XGBoost" in name:
        return SECOND
    if "Extra" in name:
        return PRIMARY
    return "#7F8C8D"


def save_profit_distribution(df: pd.DataFrame, target: str, path: Path) -> None:
    fig, axes = plt.subplots(1, 2, figsize=(10.5, 4.0))
    sns.histplot(df[target], bins=40, color=PRIMARY, ax=axes[0], kde=True)
    axes[0].set_title("Profit distribution")
    axes[0].set_xlabel("Profit (TL)")
    sns.boxplot(x=df[target], color=PRIMARY, ax=axes[1])
    axes[1].set_title("Profit boxplot")
    axes[1].set_xlabel("Profit (TL)")
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def save_product_profitability(df: pd.DataFrame, target: str, path: Path) -> None:
    stats = df.groupby("Product")[target].mean().sort_values()
    fig, ax = plt.subplots(figsize=(8.5, 5.2))
    ax.barh(stats.index.astype(str), stats.values, color=PRIMARY)
    ax.set_xlabel("Mean profit (TL)")
    ax.set_title("Mean profit by product")
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def save_model_comparison(metrics: dict[str, dict], path: Path) -> None:
    table = metrics_frame(metrics)
    fig, ax = plt.subplots(figsize=(8.8, 4.4))
    colors = [_bar_color(str(name)) for name in table.index]
    table["MAE"].plot(kind="bar", ax=ax, color=colors, rot=18)
    ax.set_ylabel("Test MAE (TL)")
    ax.set_title("Model comparison (test MAE)")
    ax.set_xlabel("")
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def save_actual_vs_predicted(y_true, y_pred, path: Path) -> None:
    y_true = np.asarray(y_true, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float)
    fig, ax = plt.subplots(figsize=(6.2, 6.0))
    ax.scatter(y_true, y_pred, s=18, alpha=0.45, color=PRIMARY)
    lo = min(y_true.min(), y_pred.min())
    hi = max(y_true.max(), y_pred.max())
    ax.plot([lo, hi], [lo, hi], color=ACCENT, lw=1.4)
    ax.set_xlabel("Actual profit (TL)")
    ax.set_ylabel("Predicted profit (TL)")
    ax.set_title("Actual vs predicted (test)")
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def save_residuals(y_true, y_pred, path: Path) -> None:
    y_true = np.asarray(y_true, dtype=float)
    y_pred = np.asarray(y_pred, dtype=float)
    resid = y_true - y_pred
    fig, ax = plt.subplots(figsize=(7.2, 4.6))
    ax.scatter(y_pred, resid, s=18, alpha=0.45, color=PRIMARY)
    ax.axhline(0, color=ACCENT, lw=1.2)
    ax.set_xlabel("Predicted profit (TL)")
    ax.set_ylabel("Residual (actual − predicted)")
    ax.set_title("Residuals vs predicted (test)")
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


def save_permutation_importance(pipeline: Pipeline, X, y, path: Path, n_repeats: int = 10) -> pd.Series:
    result = permutation_importance(
        pipeline,
        X,
        y,
        n_repeats=n_repeats,
        random_state=42,
        scoring="neg_mean_absolute_error",
    )
    series = pd.Series(result.importances_mean, index=X.columns).sort_values()
    fig, ax = plt.subplots(figsize=(8.0, 5.4))
    ax.barh(series.index.astype(str), series.values, color=PRIMARY)
    ax.set_xlabel("Increase in MAE when shuffled (TL)")
    ax.set_title("Permutation importance (test)")
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)
    return series.sort_values(ascending=False)


def save_shap_summary(pipeline: Pipeline, X: pd.DataFrame, bar_path: Path, beeswarm_path: Path) -> pd.Series:
    import shap

    values, _, X_enc = tree_shap(pipeline, X)
    plt.figure(figsize=(8.0, 5.6))
    shap.summary_plot(values, X_enc, plot_type="bar", show=False, max_display=15)
    plt.tight_layout()
    plt.savefig(bar_path, bbox_inches="tight")
    plt.close()
    plt.figure(figsize=(8.0, 5.6))
    shap.summary_plot(values, X_enc, show=False, max_display=15)
    plt.tight_layout()
    plt.savefig(beeswarm_path, bbox_inches="tight")
    plt.close()
    return pd.Series(np.abs(values).mean(axis=0), index=X_enc.columns).sort_values(ascending=False)
