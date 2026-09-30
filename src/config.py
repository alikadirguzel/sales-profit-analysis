"""Shared constants for the sales profit pipeline."""

from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = REPO_ROOT / "data"
MODELS_DIR = REPO_ROOT / "models"
REPORTS_DIR = REPO_ROOT / "reports"
FIGURES_DIR = REPORTS_DIR / "figures"

DATA_FILE = DATA_DIR / "cleaned_sales_data_with_days.xlsx"
TARGET = "Profit"
RANDOM_STATE = 42
TEST_SIZE = 0.20
CV_FOLDS = 5

LEAKAGE_DROP = ["Order_ID", "Net_Sales", "Total_Cost", "Profit_Margin", "Unit_Cost_TL"]
REDUNDANT_DROP = ["Region", "Category", "Day_Type", "Date", "year"]
CAT_FEATURES = ["City", "Product", "Sales_Channel", "Customer_Type", "Payment_Method"]

XGB_PARAMS = {
    "n_estimators": 243,
    "max_depth": 5,
    "learning_rate": 0.05544514534944357,
    "subsample": 0.7020471136043668,
    "colsample_bytree": 0.991594186044385,
    "min_child_weight": 3,
    "gamma": 1.736881261874429,
    "reg_alpha": 0.726775165034454,
    "reg_lambda": 0.5496358312083061,
}

ET_PARAMS = {
    "max_depth": 20,
    "n_estimators": 476,
    "min_samples_leaf": 2,
    "min_samples_split": 5,
    "max_features": 0.5,
}

PRIMARY = "#2F5D8A"
ACCENT = "#C0392B"
SECOND = "#1E8449"
MUTED = "#7F8C8D"
