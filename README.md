# Sales Profit Analysis

End-to-end analysis of transactional sales orders: **clean the table**, test whether profit differs by category, then **predict order profit** from information that would be known at quote time.

The scientifically valid ML problem is **not** reconstructing `Profit` from cost and revenue. That accounting identity has MAE ≈ 0.002 TL (rounding only). After those columns are removed, the remaining task is a genuine regression problem.

Everything runs **offline**. There are no API keys, tokens, environment variables, or cloud calls.

## Results at a glance

| Item | Value |
|------|--------|
| Dataset | 958 orders, 18 raw columns, 2026-01-01 to 2026-06-30 |
| Target | `Profit` (order profit, TL) |
| Train / test | Chronological: 743 / 215, cutoff 2026-05-26 |
| Selected model | **XGBoost** (Optuna-tuned) |
| Test MAE | **279.14 TL** |
| Extra Trees test MAE | 322.78 TL |
| Product-mean baseline MAE | 1026.12 TL |
| Mean baseline MAE | 1281.71 TL |
| Test R² (XGBoost) | 0.753 |
| Strongest statistical factor | `Product` (η² ≈ 0.27); `City` / `Region` not significant after FDR |

Lift vs product-mean baseline: about **747 TL MAE per order** on the held-out period.

## What this repo contains

```
.
├── README.md
├── requirements.txt
├── sales_ml_analysis.ipynb          # ML notebook with executed outputs
├── model_results_snapshot.json      # compact metrics written by the notebook
├── cleaned_sales_data_with_days.xlsx
├── cleaned_sales_data.xlsx
├── clean_sales_data.py          # cleaning (Python)
├── clean_sales_data.m           # cleaning (MATLAB, same rules)
└── matlab/                          # inference pipeline + saved results
    ├── categorical_profit_analysis.m      # entry script
    ├── analyzeCategoricalFeature.m
    ├── ... helper .m files ...
    ├── cleaned_sales_data.xlsx
    └── results/                     # report, Excel tables, figures
```

All data and script references are **relative filenames in this folder**. Clone, install, run — no local disk paths to edit.

## Dataset

Cleaned tables are included. Each row is one order.

| Column | Role |
|--------|------|
| `Order_ID` | Identifier (dropped from models) |
| `Date` | Order date (calendar features extracted, then dropped) |
| `City`, `Region` | Location (`Region` is a function of `City`) |
| `Product`, `Category` | Product (`Category` is a function of `Product`) |
| `Sales_Channel`, `Customer_Type`, `Payment_Method` | Commercial attributes |
| `Quantity`, `Unit_Price_TL`, `Discount_Rate` | Quote-time numbers |
| `Unit_Cost_TL` | Unit cost — **leakage for profit prediction** |
| `Net_Sales`, `Total_Cost`, `Profit`, `Profit_Margin` | Derived after the sale |

**ML leakage drop list:** `Order_ID`, `Net_Sales`, `Total_Cost`, `Profit_Margin`, `Unit_Cost_TL`.

Raw `raw_sales_data.xlsx` is **not** in the repo. Cleaning scripts look for it in the **same folder as the script** if you want to rebuild the cleaned tables.

## 1. Machine learning (`sales_ml_analysis.ipynb`)

### Problem

Estimate `Profit` from quote-time attributes (product, city, channel, quantity, list price, discount, calendar). Use case: expected profit when cost accounting is delayed. Do **not** use the model as an accounting subledger; if unit cost is known, use the identity.

### Design

| Topic | Choice |
|-------|--------|
| Task | Supervised regression |
| Primary metric | MAE (TL) — profit is right-skewed and can be negative |
| Secondary | RMSE, R², Median AE, sMAPE |
| Split | Chronological (past → train, future → test). Random split would leak the future |
| CV | `TimeSeriesSplit(5)` on train only |
| Encoding | One-hot inside `ColumnTransformer` (`handle_unknown="ignore"`) |
| Scaling / PCA | Not used in tree pipelines (PCA is a diagnostic only) |
| Models | XGBoost vs Extra Trees, Optuna on train CV MAE (20 trials) |
| Explainability | Permutation importance + SHAP |
| Seed | `RANDOM_STATE = 42` |

Row-wise features include `net_unit_price`, `list_revenue`, `discount_value_unit`, and calendar flags. No target encoding. No test-set information in preprocessing.

### How to run

From the repository root (this folder):

```bash
python -m pip install -r requirements.txt
jupyter notebook sales_ml_analysis.ipynb
```

Headless re-run (optional, ~30 min):

```bash
python -m jupyter nbconvert --to notebook --execute sales_ml_analysis.ipynb --output sales_ml_analysis.ipynb --ExecutePreprocessor.timeout=1800
```

The notebook already contains executed figures and the final report. The dataset file must sit next to the notebook: `cleaned_sales_data_with_days.xlsx`.

### Model comparison (test set)

| Model | CV MAE | Train MAE | Test MAE | Test RMSE | Test R² | Test Median AE | Test sMAPE |
|-------|-------:|----------:|---------:|----------:|--------:|---------------:|-----------:|
| Mean baseline | — | — | 1281.71 | 1837.78 | −0.004 | 1016.58 | 92.53 |
| Product-mean baseline | — | — | 1026.12 | 1620.73 | 0.219 | 587.41 | 74.15 |
| Extra Trees (tuned) | 396.74 | 101.33 | 322.78 | 913.11 | 0.752 | 83.35 | 22.58 |
| **XGBoost (tuned)** | **305.41** | 58.89 | **279.14** | 871.22 | 0.774 | 68.87 | 22.17 |

XGBoost wins on test MAE, RMSE and R². Production pick: **XGBoost**.

Train MAE is much lower than test MAE on both trees (58.9 vs 279.1 for XGBoost). That gap is expected with a heavy-tailed target and a six-month window; learning curves and residual plots are in the notebook.

SHAP / permutation: commercial size (`list_revenue`, quantity, prices, discount) and product identity dominate. Calendar flags are secondary.

### Limitations (stated in the notebook)

- Unit cost is not an input; a sudden cost shock is invisible until retraining.
- Six months, one year — no Q3/Q4, no prior year.
- One-hot cannot generalise to a **new** product name.
- Order-level profit, not a daily demand forecast.

## 2. Statistical inference (`matlab/`)

Question: do `City`, `Region`, `Product`, `Category`, `Sales_Channel`, `Customer_Type` differ in `Profit`?

Per factor: descriptives → IQR / z outliers (**detected, never deleted**) → Anderson–Darling + Lilliefors → Levene → classical ANOVA → η² → permutation ANOVA (10,000, `rng(42)`) → Kruskal–Wallis → Tukey / Dunn if the overall test is significant → Bonferroni and Benjamini–Hochberg across the six features.

### How to run

In MATLAB, set the current folder to `matlab/`, then run `categorical_profit_analysis.m`. Needs Statistics and Machine Learning Toolbox.

Outputs (already committed):

- `matlab/results/command_window_report.txt`
- `matlab/results/statistical_summary.xlsx`
- `matlab/results/group_statistics.xlsx`
- `matlab/results/posthoc_results.xlsx`
- `matlab/results/<Feature>/*.png`

### Main inference

| Feature | Groups | ANOVA p | Permutation p | FDR (BH) | η² | Decision |
|---------|-------:|--------:|--------------:|---------:|---:|----------|
| `Product` | 12 | ~10⁻⁵⁸ | 0.0001 | 0.0002 | 0.27 | significant |
| `Category` | 5 | ~10⁻⁵⁰ | 0.0001 | 0.0002 | 0.22 | significant |
| `Customer_Type` | 3 | 5.4×10⁻⁵ | 0.0001 | 0.0002 | 0.02 | significant |
| `Sales_Channel` | 3 | 0.046 | 0.049 | 0.073 | 0.006 | not after FDR |
| `Region` | 6 | 0.226 | 0.220 | 0.265 | 0.007 | not significant |
| `City` | 10 | 0.329 | 0.323 | 0.323 | 0.011 | not significant |

Profit differences are driven by **product mix**, not geography. That agrees with the ML explanation (product + commercial size, not city).

## 3. Cleaning

Rebuild from raw data only if you have `raw_sales_data.xlsx` in this folder:

```bash
python clean_sales_data.py
```

or MATLAB `clean_sales_data.m`.

Rules: drop `Customer_ID`; unique `Order_ID`; parse dates; standardise city / region / product / category / channel / customer type / payment into English labels; drop city–region and product–category mismatches; drop missing rows; quantity / price / discount / cost sanity checks; recompute `Net_Sales`, `Total_Cost`, `Profit`, `Profit_Margin`. Column names in the cleaned files are English.

The cleaned files used by later stages are already in the repo. You do **not** need the raw file to run the notebook or the MATLAB analysis.

## Reproducibility

| Setting | Value |
|---------|--------|
| Python seed | 42 |
| MATLAB seed | `rng(42)` |
| Optuna trials | 20 (TPE) |
| Permutations | 10,000 |
| α | 0.05 |

No secrets, no `.env`, no absolute paths in source or logs.

## Requirements

Python packages: `requirements.txt`.

MATLAB: R2021b or later recommended, Statistics and Machine Learning Toolbox.
