"""Train XGBoost vs Extra Trees, evaluate, and write reports/figures."""

from __future__ import annotations

import argparse
import json
import os

os.environ.setdefault("MPLBACKEND", "Agg")

import joblib
import numpy as np
from sklearn.ensemble import ExtraTreesRegressor
from sklearn.model_selection import TimeSeriesSplit
from sklearn.pipeline import Pipeline
from xgboost import XGBRegressor

from src.config import (
    CV_FOLDS,
    ET_PARAMS,
    FIGURES_DIR,
    MODELS_DIR,
    RANDOM_STATE,
    REPORTS_DIR,
    TARGET,
    XGB_PARAMS,
)
from src.data_processing import accounting_identity, load_orders
from src.evaluate import mean_baseline, product_mean_baseline, regression_metrics
from src.explain import (
    save_actual_vs_predicted,
    save_model_comparison,
    save_permutation_importance,
    save_product_profitability,
    save_profit_distribution,
    save_residuals,
    save_shap_summary,
)
from src.features import chronological_masks, model_matrix, tree_preprocessor


def make_xgb(preprocessor, params: dict | None = None) -> Pipeline:
    cfg = {
        "objective": "reg:squarederror",
        "random_state": RANDOM_STATE,
        "n_jobs": -1,
        "tree_method": "hist",
        "verbosity": 0,
        "n_estimators": 300,
        "max_depth": 4,
        "learning_rate": 0.08,
        "subsample": 0.8,
        "colsample_bytree": 0.8,
        "min_child_weight": 2,
        "reg_lambda": 1.0,
    }
    if params:
        cfg.update(params)
    return Pipeline([("pre", preprocessor), ("model", XGBRegressor(**cfg))])


def make_et(preprocessor, params: dict | None = None) -> Pipeline:
    cfg = {
        "random_state": RANDOM_STATE,
        "n_jobs": -1,
        "n_estimators": 400,
        "min_samples_leaf": 2,
        "max_features": "sqrt",
    }
    if params:
        cfg.update(params)
    return Pipeline([("pre", preprocessor), ("model", ExtraTreesRegressor(**cfg))])


def cv_mae(estimator: Pipeline, X, y, cv) -> float:
    from sklearn.base import clone
    from sklearn.metrics import mean_absolute_error

    scores = []
    for tr, va in cv.split(X):
        est = clone(estimator)
        est.fit(X.iloc[tr], y.iloc[tr])
        pred = est.predict(X.iloc[va])
        scores.append(mean_absolute_error(y.iloc[va], pred))
    return float(np.mean(scores))


def tune(preprocessor, X_train, y_train, n_trials: int) -> tuple[dict, dict]:
    import optuna
    from optuna.samplers import TPESampler

    optuna.logging.set_verbosity(optuna.logging.WARNING)
    tscv = TimeSeriesSplit(n_splits=CV_FOLDS)

    def xgb_objective(trial: optuna.Trial) -> float:
        params = {
            "n_estimators": trial.suggest_int("n_estimators", 150, 500),
            "max_depth": trial.suggest_int("max_depth", 3, 8),
            "learning_rate": trial.suggest_float("learning_rate", 0.02, 0.2, log=True),
            "subsample": trial.suggest_float("subsample", 0.6, 1.0),
            "colsample_bytree": trial.suggest_float("colsample_bytree", 0.6, 1.0),
            "min_child_weight": trial.suggest_int("min_child_weight", 1, 10),
            "gamma": trial.suggest_float("gamma", 0.0, 2.0),
            "reg_alpha": trial.suggest_float("reg_alpha", 0.0, 1.0),
            "reg_lambda": trial.suggest_float("reg_lambda", 0.1, 5.0),
        }
        return cv_mae(make_xgb(preprocessor, params), X_train, y_train, tscv)

    def et_objective(trial: optuna.Trial) -> float:
        params = {
            "n_estimators": trial.suggest_int("n_estimators", 200, 600),
            "max_depth": trial.suggest_int("max_depth", 6, 24),
            "min_samples_leaf": trial.suggest_int("min_samples_leaf", 1, 8),
            "min_samples_split": trial.suggest_int("min_samples_split", 2, 12),
            "max_features": trial.suggest_categorical("max_features", ["sqrt", "log2", 0.5]),
        }
        return cv_mae(make_et(preprocessor, params), X_train, y_train, tscv)

    study_xgb = optuna.create_study(direction="minimize", sampler=TPESampler(seed=RANDOM_STATE))
    study_xgb.optimize(xgb_objective, n_trials=n_trials, show_progress_bar=False)
    study_et = optuna.create_study(direction="minimize", sampler=TPESampler(seed=RANDOM_STATE))
    study_et.optimize(et_objective, n_trials=n_trials, show_progress_bar=False)
    return study_xgb.best_params, study_et.best_params


def main(argv: list[str] | None = None) -> dict:
    parser = argparse.ArgumentParser(description="Train sales profit models and write reports.")
    parser.add_argument("--tune", action="store_true", help="Run Optuna on train TimeSeriesSplit MAE")
    parser.add_argument("--trials", type=int, default=20)
    args = parser.parse_args(argv)

    FIGURES_DIR.mkdir(parents=True, exist_ok=True)
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    REPORTS_DIR.mkdir(parents=True, exist_ok=True)

    df = load_orders()
    X, y = model_matrix(df)
    train_mask, test_mask, cutoff = chronological_masks(df["Date"])
    X_train, X_test = X.loc[train_mask], X.loc[test_mask]
    y_train, y_test = y.loc[train_mask], y.loc[test_mask]
    preprocessor = tree_preprocessor(X)

    xgb_params, et_params = XGB_PARAMS, ET_PARAMS
    if args.tune:
        xgb_params, et_params = tune(preprocessor, X_train, y_train, args.trials)

    tscv = TimeSeriesSplit(n_splits=CV_FOLDS)
    xgb_pipe = make_xgb(tree_preprocessor(X), xgb_params)
    et_pipe = make_et(tree_preprocessor(X), et_params)
    xgb_cv = cv_mae(make_xgb(tree_preprocessor(X), xgb_params), X_train, y_train, tscv)
    et_cv = cv_mae(make_et(tree_preprocessor(X), et_params), X_train, y_train, tscv)

    xgb_pipe.fit(X_train, y_train)
    et_pipe.fit(X_train, y_train)
    xgb_pred = xgb_pipe.predict(X_test)
    et_pred = et_pipe.predict(X_test)

    mean_pred = mean_baseline(y_train, len(y_test))
    product_pred = product_mean_baseline(
        y_train, df.loc[train_mask, "Product"], df.loc[test_mask, "Product"]
    )
    oracle = regression_metrics(df[TARGET], accounting_identity(df))

    comparison = {
        "Mean baseline": regression_metrics(y_test, mean_pred),
        "Product-mean baseline": regression_metrics(y_test, product_pred),
        "Extra Trees": regression_metrics(y_test, et_pred),
        "XGBoost": regression_metrics(y_test, xgb_pred),
    }
    selected = "XGBoost" if comparison["XGBoost"]["MAE"] <= comparison["Extra Trees"]["MAE"] else "Extra Trees"
    final_pipe = xgb_pipe if selected == "XGBoost" else et_pipe
    final_pred = xgb_pred if selected == "XGBoost" else et_pred

    joblib.dump(final_pipe, MODELS_DIR / "profit_model.joblib")

    save_profit_distribution(df, TARGET, FIGURES_DIR / "profit_distribution.png")
    save_product_profitability(df, TARGET, FIGURES_DIR / "product_profitability.png")
    save_model_comparison(comparison, FIGURES_DIR / "model_comparison.png")
    save_actual_vs_predicted(y_test, final_pred, FIGURES_DIR / "actual_vs_predicted.png")
    save_residuals(y_test, final_pred, FIGURES_DIR / "residuals.png")
    perm = save_permutation_importance(
        final_pipe, X_test, y_test, FIGURES_DIR / "feature_importance.png"
    )
    shap_rank = save_shap_summary(
        final_pipe,
        X_test,
        FIGURES_DIR / "shap_importance.png",
        FIGURES_DIR / "shap_summary.png",
    )

    payload = {
        "dataset": "synthetic retail orders for portfolio / methodology demonstration",
        "n_rows": int(len(df)),
        "cutoff": str(cutoff.date()),
        "n_train": int(len(X_train)),
        "n_test": int(len(X_test)),
        "selected_model": selected,
        "xgb_cv_mae": xgb_cv,
        "et_cv_mae": et_cv,
        "xgb_params": xgb_params,
        "et_params": et_params,
        "oracle_identity": oracle,
        "test_metrics": comparison,
        "permutation_top": perm.head(8).to_dict(),
        "shap_top": shap_rank.head(10).to_dict(),
        "mae_lift_vs_product_mean": comparison["Product-mean baseline"]["MAE"] - comparison[selected]["MAE"],
    }
    (REPORTS_DIR / "metrics.json").write_text(
        json.dumps(payload, indent=2, default=str), encoding="utf-8"
    )
    print(f"Selected model: {selected}")
    print(f"Test MAE: {comparison[selected]['MAE']:.2f} TL")
    print("Wrote figures to reports/figures")
    return payload


if __name__ == "__main__":
    main()
