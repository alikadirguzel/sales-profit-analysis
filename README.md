# Sales Profit Analysis

End-to-end analysis of transactional sales orders: **clean the table**, test whether profit differs by category, then **predict order profit** from information that would be known at quote time.

The scientifically valid ML problem is **not** reconstructing `Kar` from cost and revenue. That accounting identity has MAE ≈ 0.002 TL (rounding only). After those columns are removed, the remaining task is a genuine regression problem.

Everything runs **offline**. There are no API keys, tokens, environment variables, or cloud calls.

## Results at a glance

| Item | Value |
|------|--------|
| Dataset | 958 orders, 18 raw columns, 2026-01-01 to 2026-06-30 |
| Target | `Kar` (order profit, TL) |
| Train / test | Chronological: 743 / 215, cutoff 2026-05-26 |
| Selected model | **XGBoost** (Optuna-tuned) |
| Test MAE | **291.67 TL** |
| Extra Trees test MAE | 323.35 TL |
| Product-mean baseline MAE | 1026.12 TL |
| Mean baseline MAE | 1281.71 TL |
| Test R² (XGBoost) | 0.753 |
| Strongest statistical factor | `Urun` (η² ≈ 0.27); `Sehir` / `Bolge` not significant after FDR |

Lift vs product-mean baseline: about **735 TL MAE per order** on the held-out period.

## What this repo contains

```
.
├── README.md
├── requirements.txt
├── sales_ml_analysis.ipynb          # ML notebook with executed outputs
├── model_results_snapshot.json      # compact metrics written by the notebook
├── Temizlenmis_SatisVerisi_Gunler.xlsx
├── Temizlenmis_SatisVerisi.xlsx
├── temizle_satis_verisi.py          # cleaning (Python)
├── temizle_satis_verisi.m           # cleaning (MATLAB, same rules)
└── matlab/                          # inference pipeline + saved results
    ├── kategorik_kar_analizi.m      # entry script
    ├── analyzeCategoricalFeature.m
    ├── ... helper .m files ...
    ├── Temizlenmis_SatisVerisi.xlsx
    └── results/                     # report, Excel tables, figures
```

All data and script references are **relative filenames in this folder**. Clone, install, run — no local disk paths to edit.

## Dataset

Cleaned tables are included. Each row is one order.

| Column | Role |
|--------|------|
| `Siparis_ID` | Identifier (dropped from models) |
| `Tarih` | Order date (calendar features extracted, then dropped) |
| `Sehir`, `Bolge` | Location (`Bolge` is a function of `Sehir`) |
| `Urun`, `Kategori` | Product (`Kategori` is a function of `Urun`) |
| `Satis_Kanali`, `Musteri_Tipi`, `Odeme_Yontemi` | Commercial attributes |
| `Miktar`, `Birim_Fiyat_TL`, `Indirim_Orani` | Quote-time numbers |
| `Birim_Maliyet_TL` | Unit cost — **leakage for profit prediction** |
| `Net_Satis`, `Toplam_Maliyet`, `Kar`, `Kar_Marji` | Derived after the sale |

**ML leakage drop list:** `Siparis_ID`, `Net_Satis`, `Toplam_Maliyet`, `Kar_Marji`, `Birim_Maliyet_TL`.

Raw `SatışVerisi.xlsx` is **not** in the repo. Cleaning scripts look for it in the **same folder as the script** if you want to rebuild the cleaned tables.

## 1. Machine learning (`sales_ml_analysis.ipynb`)

### Problem

Estimate `Kar` from quote-time attributes (product, city, channel, quantity, list price, discount, calendar). Use case: expected profit when cost accounting is delayed. Do **not** use the model as an accounting subledger; if unit cost is known, use the identity.

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

The notebook already contains executed figures and the final report. The dataset file must sit next to the notebook: `Temizlenmis_SatisVerisi_Gunler.xlsx`.

### Model comparison (test set)

| Model | CV MAE | Train MAE | Test MAE | Test RMSE | Test R² | Test Median AE | Test sMAPE |
|-------|-------:|----------:|---------:|----------:|--------:|---------------:|-----------:|
| Mean baseline | — | — | 1281.71 | 1837.78 | −0.004 | 1016.58 | 92.53 |
| Product-mean baseline | — | — | 1026.12 | 1620.73 | 0.219 | 587.41 | 74.15 |
| Extra Trees (tuned) | 397.59 | 101.85 | 323.35 | 909.68 | 0.754 | 85.42 | 22.72 |
| **XGBoost (tuned)** | **306.82** | 48.63 | **291.67** | 912.06 | 0.753 | 78.07 | 25.58 |

XGBoost wins on test MAE (primary). Extra Trees is slightly better on RMSE / R². Production pick: **XGBoost**.

Train MAE is much lower than test MAE on both trees (48.6 vs 291.7 for XGBoost). That gap is expected with a heavy-tailed target and a six-month window; learning curves and residual plots are in the notebook.

SHAP / permutation: commercial size (`list_revenue`, quantity, prices, discount) and product identity dominate. Calendar flags are secondary.

### Limitations (stated in the notebook)

- Unit cost is not an input; a sudden cost shock is invisible until retraining.
- Six months, one year — no Q3/Q4, no prior year.
- One-hot cannot generalise to a **new** product name.
- Order-level profit, not a daily demand forecast.

## 2. Statistical inference (`matlab/`)

Question: do `Sehir`, `Bolge`, `Urun`, `Kategori`, `Satis_Kanali`, `Musteri_Tipi` differ in `Kar`?

Per factor: descriptives → IQR / z outliers (**detected, never deleted**) → Anderson–Darling + Lilliefors → Levene → classical ANOVA → η² → permutation ANOVA (10,000, `rng(42)`) → Kruskal–Wallis → Tukey / Dunn if the overall test is significant → Bonferroni and Benjamini–Hochberg across the six features.

### How to run

In MATLAB, set the current folder to `matlab/`, then run `kategorik_kar_analizi.m`. Needs Statistics and Machine Learning Toolbox.

Outputs (already committed):

- `matlab/results/command_window_report.txt`
- `matlab/results/statistical_summary.xlsx`
- `matlab/results/group_statistics.xlsx`
- `matlab/results/posthoc_results.xlsx`
- `matlab/results/<Feature>/*.png`

### Main inference

| Feature | Groups | ANOVA p | Permutation p | FDR (BH) | η² | Decision |
|---------|-------:|--------:|--------------:|---------:|---:|----------|
| `Urun` | 12 | ~10⁻⁵⁸ | 0.0001 | 0.0002 | 0.27 | significant |
| `Kategori` | 5 | ~10⁻⁵⁰ | 0.0001 | 0.0002 | 0.22 | significant |
| `Musteri_Tipi` | 3 | 5.4×10⁻⁵ | 0.0001 | 0.0002 | 0.02 | significant |
| `Satis_Kanali` | 3 | 0.046 | 0.049 | 0.073 | 0.006 | not after FDR |
| `Bolge` | 6 | 0.226 | 0.220 | 0.265 | 0.007 | not significant |
| `Sehir` | 10 | 0.329 | 0.323 | 0.323 | 0.011 | not significant |

Profit differences are driven by **product mix**, not geography. That agrees with the ML explanation (product + commercial size, not city).

## 3. Cleaning

Rebuild from raw data only if you have `SatışVerisi.xlsx` in this folder:

```bash
python temizle_satis_verisi.py
```

or MATLAB `temizle_satis_verisi.m`.

Rules (headers unchanged): drop `Musteri_ID`; unique `Siparis_ID`; parse dates; standardise city / region / product / category / channel / customer type / payment; drop city–region and product–category mismatches; drop missing rows; quantity / price / discount / cost sanity checks; recompute `Net_Satis`, `Toplam_Maliyet`, `Kar`, `Kar_Marji`.

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
