# -*- coding: utf-8 -*-
"""Clean raw sales orders into cleaned_sales_data.xlsx.

Accepts either original Turkish headers or English headers.
Output columns and category labels are always English.
"""
from __future__ import annotations

import json
import re
import sys
import unicodedata
from datetime import datetime
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

import numpy as np
import pandas as pd

ROOT = Path(__file__).parent
SRC_CANDIDATES = ("raw_sales_data.xlsx", "SatışVerisi.xlsx")
OUT_NAME = "cleaned_sales_data.xlsx"
LOG_NAME = "cleaning_summary.json"
OUT_XLSX = ROOT / "data" / OUT_NAME
OUT_LOG = ROOT / "data" / LOG_NAME

COLUMN_RENAME = {
    "Siparis_ID": "Order_ID",
    "Tarih": "Date",
    "Musteri_ID": "Customer_ID",
    "Sehir": "City",
    "Bolge": "Region",
    "Urun": "Product",
    "Kategori": "Category",
    "Satis_Kanali": "Sales_Channel",
    "Musteri_Tipi": "Customer_Type",
    "Odeme_Yontemi": "Payment_Method",
    "Miktar": "Quantity",
    "Birim_Fiyat_TL": "Unit_Price_TL",
    "Indirim_Orani": "Discount_Rate",
    "Birim_Maliyet_TL": "Unit_Cost_TL",
    "Net_Satis": "Net_Sales",
    "Toplam_Maliyet": "Total_Cost",
    "Kar": "Profit",
    "Kar_Marji": "Profit_Margin",
    "Gunler": "Day_Type",
}

CITY_MAP = {
    "istanbul": "Istanbul",
    "izmir": "Izmir",
    "ankara": "Ankara",
    "antalya": "Antalya",
    "bursa": "Bursa",
    "adana": "Adana",
    "konya": "Konya",
    "gaziantep": "Gaziantep",
    "samsun": "Samsun",
    "trabzon": "Trabzon",
}

REGION_MAP = {
    "marmara": "Marmara",
    "ege": "Aegean",
    "aegean": "Aegean",
    "akdeniz": "Mediterranean",
    "mediterranean": "Mediterranean",
    "ic anadolu": "Central Anatolia",
    "central anatolia": "Central Anatolia",
    "karadeniz": "Black Sea",
    "black sea": "Black Sea",
    "guneydogu anadolu": "Southeastern Anatolia",
    "southeastern anatolia": "Southeastern Anatolia",
    "dogu anadolu": "Eastern Anatolia",
}

CITY_REGION = {
    "Istanbul": "Marmara",
    "Bursa": "Marmara",
    "Izmir": "Aegean",
    "Ankara": "Central Anatolia",
    "Konya": "Central Anatolia",
    "Antalya": "Mediterranean",
    "Adana": "Mediterranean",
    "Samsun": "Black Sea",
    "Trabzon": "Black Sea",
    "Gaziantep": "Southeastern Anatolia",
}

PRODUCT_MAP = {
    "wireless mouse": "Wireless Mouse",
    "desk lamp": "Desk Lamp",
    "monitor 27": "Monitor 27",
    "monitor 24": "Monitor 24",
    "notebook set": "Notebook Set",
    "usb c hub": "USB-C Hub",
    "usb-c hub": "USB-C Hub",
    "office chair": "Office Chair",
    "backpack": "Backpack",
    "webcam": "Webcam",
    "mechanical keyboard": "Mechanical Keyboard",
    "laptop stand": "Laptop Stand",
    "pen set": "Pen Set",
}

CATEGORY_MAP = {
    "elektronik": "Electronics",
    "electronics": "Electronics",
    "ofis aksesuarlari": "Office Accessories",
    "office accessories": "Office Accessories",
    "kirtasiye": "Stationery",
    "stationery": "Stationery",
    "mobilya": "Furniture",
    "furniture": "Furniture",
    "aksesuar": "Accessories",
    "accessories": "Accessories",
}

PRODUCT_CATEGORY = {
    "Wireless Mouse": "Electronics",
    "USB-C Hub": "Electronics",
    "Webcam": "Electronics",
    "Monitor 24": "Electronics",
    "Monitor 27": "Electronics",
    "Mechanical Keyboard": "Electronics",
    "Desk Lamp": "Office Accessories",
    "Laptop Stand": "Office Accessories",
    "Office Chair": "Furniture",
    "Notebook Set": "Stationery",
    "Pen Set": "Stationery",
    "Backpack": "Accessories",
}

SALES_CHANNEL_MAP = {
    "online": "Online",
    "magaza": "Store",
    "store": "Store",
    "bayi": "Dealer",
    "dealer": "Dealer",
}

CUSTOMER_TYPE_MAP = {
    "bireysel": "Individual",
    "individual": "Individual",
    "kobi": "SME",
    "sme": "SME",
    "kurumsal": "Corporate",
    "corporate": "Corporate",
}

PAYMENT_MAP = {
    "kredi karti": "Credit Card",
    "credit card": "Credit Card",
    "havale/eft": "Bank Transfer",
    "havale eft": "Bank Transfer",
    "bank transfer": "Bank Transfer",
    "nakit": "Cash",
    "cash": "Cash",
}


def fold_key(value) -> str:
    """ASCII fold for Turkish comparison (I/İ/ı -> i)."""
    if value is None or (isinstance(value, float) and np.isnan(value)):
        return ""
    s = unicodedata.normalize("NFKC", str(value).strip())
    s = s.replace("İ", "i").replace("I", "i").replace("ı", "i")
    s = s.replace("Ç", "c").replace("Ğ", "g").replace("Ö", "o").replace("Ş", "s").replace("Ü", "u")
    s = s.replace("ç", "c").replace("ğ", "g").replace("ö", "o").replace("ş", "s").replace("ü", "u")
    s = s.lower()
    s = re.sub(r"[\s_\-]+", " ", s).strip()
    return s


def is_empty(series: pd.Series) -> pd.Series:
    s = series.astype("string").str.strip()
    return (
        series.isna()
        | s.isna()
        | s.eq("")
        | s.str.lower().isin(["nan", "nat", "none", "null", "<undefined>", "-", "na"])
    )


def map_series(series: pd.Series, mapping: dict) -> pd.Series:
    keys = series.map(fold_key)
    mapped = keys.map(mapping)
    return mapped.where(keys.ne(""), pd.NA)


def parse_date(val):
    if pd.isna(val):
        return pd.NaT
    if isinstance(val, datetime) or isinstance(val, pd.Timestamp):
        ts = pd.Timestamp(val)
        if ts.year < 2000 or ts.year > 2035:
            return pd.NaT
        return ts.normalize()
    s = str(val).strip().strip("'\"{} ")
    if fold_key(s) in {"", "nan", "nat", "none", "null"}:
        return pd.NaT
    s = re.sub(r"\s+", "", s)
    for fmt in ("%Y-%m-%d", "%d/%m/%Y", "%d.%m.%Y", "%Y/%m/%d", "%d-%m-%Y", "%Y.%m.%d"):
        try:
            dt = datetime.strptime(s, fmt)
            if dt.year < 2000 or dt.year > 2035:
                return pd.NaT
            return pd.Timestamp(dt).normalize()
        except ValueError:
            continue
    return pd.NaT


def apply_map(data: pd.DataFrame, col: str, mapping: dict) -> pd.DataFrame:
    data[col] = map_series(data[col], mapping)
    return data


def drop(data: pd.DataFrame, mask: pd.Series, reason: str, log: list) -> pd.DataFrame:
    n = int(mask.sum())
    log.append({"step": reason, "dropped": n, "remaining": int((~mask).sum())})
    return data.loc[~mask].copy()


def resolve_source() -> Path:
    for name in SRC_CANDIDATES:
        path = ROOT / name
        if path.exists():
            return path
    raise FileNotFoundError(
        "Raw file not found: raw_sales_data.xlsx (place it in the same folder as this script)"
    )


def main():
    src = resolve_source()
    log = []
    data = pd.read_excel(src, dtype={"Siparis_ID": "string", "Order_ID": "string", "Tarih": "string", "Date": "string"})
    data = data.rename(columns={c: COLUMN_RENAME[c] for c in data.columns if c in COLUMN_RENAME})
    n_raw = len(data)
    raw_columns = list(data.columns)
    log.append({"step": "Raw data", "dropped": 0, "remaining": n_raw})

    if "Customer_ID" in data.columns:
        data = data.drop(columns=["Customer_ID"])

    data = drop(data, data.duplicated("Order_ID", keep="first"), "Duplicate Order_ID", log)

    parsed = data["Date"].map(parse_date)
    data = drop(data, parsed.isna(), "Invalid / empty Date", log)
    parsed = parsed.loc[data.index]
    data["Date"] = parsed.dt.strftime("%d.%m.%Y")

    data = apply_map(data, "City", CITY_MAP)
    data = apply_map(data, "Region", REGION_MAP)
    data = apply_map(data, "Product", PRODUCT_MAP)
    data = apply_map(data, "Category", CATEGORY_MAP)
    data = apply_map(data, "Sales_Channel", SALES_CHANNEL_MAP)
    data = apply_map(data, "Customer_Type", CUSTOMER_TYPE_MAP)
    data = apply_map(data, "Payment_Method", PAYMENT_MAP)

    unknown_city = data["City"].notna() & ~data["City"].isin(CITY_REGION)
    data = drop(data, unknown_city, "Unknown city name", log)

    expected_region = data["City"].map(CITY_REGION)
    mismatch = data["City"].notna() & data["Region"].notna() & (data["Region"] != expected_region)
    data = drop(data, mismatch, "City-Region mismatch", log)

    expected_cat = data["Product"].map(PRODUCT_CATEGORY)
    cat_mismatch = (
        data["Product"].notna()
        & data["Category"].notna()
        & expected_cat.notna()
        & (data["Category"] != expected_cat)
    )
    data = drop(data, cat_mismatch, "Product-Category mismatch", log)

    missing = data.isna() | data.apply(is_empty)
    data = drop(data, missing.any(axis=1), "Row with missing values", log)

    numeric_cols = ["Quantity", "Unit_Price_TL", "Discount_Rate", "Unit_Cost_TL"]
    for col in numeric_cols:
        data[col] = pd.to_numeric(data[col], errors="coerce")
    data = drop(data, data[numeric_cols].isna().any(axis=1), "Non-numeric quantity/price/cost", log)

    data = drop(data, data["Quantity"] < 1, "Quantity < 1", log)
    q1, q3 = data["Quantity"].quantile(0.25), data["Quantity"].quantile(0.75)
    qty_cap = q3 + 5 * (q3 - q1)
    data = drop(data, data["Quantity"] > qty_cap, f"Quantity outlier (>{qty_cap:.0f})", log)

    data = drop(
        data,
        (data["Discount_Rate"] < 0) | (data["Discount_Rate"] > 1),
        "Discount_Rate outside [0, 1]",
        log,
    )
    data = drop(data, data["Discount_Rate"] > 0.50, "Discount_Rate outlier (>0.50)", log)
    data = drop(
        data,
        (data["Unit_Price_TL"] <= 0) | (data["Unit_Cost_TL"] <= 0),
        "Price or cost <= 0",
        log,
    )

    med_price = data.groupby("Product")["Unit_Price_TL"].transform("median")
    price_out = (data["Unit_Price_TL"] > 5 * med_price) | (data["Unit_Price_TL"] < 0.3 * med_price)
    data = drop(data, price_out, "Unit_Price_TL outlier vs product median", log)

    med_cost = data.groupby("Product")["Unit_Cost_TL"].transform("median")
    cost_out = (data["Unit_Cost_TL"] > 5 * med_cost) | (data["Unit_Cost_TL"] < 0.3 * med_cost)
    data = drop(data, cost_out, "Unit_Cost_TL outlier vs product median", log)

    data = drop(data, data["Unit_Cost_TL"] >= data["Unit_Price_TL"], "Cost >= price", log)
    ratio = data["Unit_Cost_TL"] / data["Unit_Price_TL"]
    data = drop(data, (ratio < 0.20) | (ratio > 0.95), "Implausible cost/price ratio", log)

    data["Net_Sales"] = data["Quantity"] * data["Unit_Price_TL"] * (1 - data["Discount_Rate"])
    data["Total_Cost"] = data["Quantity"] * data["Unit_Cost_TL"]
    data["Profit"] = data["Net_Sales"] - data["Total_Cost"]
    data["Profit_Margin"] = np.where(data["Net_Sales"] > 0, data["Profit"] / data["Net_Sales"], np.nan)

    data["Net_Sales"] = data["Net_Sales"].round(2)
    data["Total_Cost"] = data["Total_Cost"].round(2)
    data["Profit"] = data["Profit"].round(2)
    data["Profit_Margin"] = data["Profit_Margin"].round(6)

    data = drop(
        data,
        (data["Net_Sales"] <= 0) | data["Profit_Margin"].isna() | ~np.isfinite(data["Profit_Margin"]),
        "Net_Sales <= 0 or undefined Profit_Margin",
        log,
    )
    data = drop(data, data["Profit_Margin"].abs() > 0.95, "Profit_Margin outlier (|m| > 0.95)", log)

    data = data.sort_values("Order_ID", kind="mergesort").reset_index(drop=True)
    data["Quantity"] = data["Quantity"].astype(int)
    for col in ["City", "Region", "Product", "Category", "Sales_Channel", "Customer_Type", "Payment_Method"]:
        data[col] = data[col].astype(str)

    columns = list(data.columns)
    assert columns[0] == "Order_ID"
    assert "Customer_ID" not in columns

    OUT_XLSX.parent.mkdir(parents=True, exist_ok=True)
    data.to_excel(OUT_XLSX, index=False)

    summary = {
        "raw_rows": n_raw,
        "clean_rows": int(len(data)),
        "dropped_total": int(n_raw - len(data)),
        "steps": log,
        "columns": columns,
        "cities": sorted(data["City"].unique().tolist()),
        "regions": sorted(data["Region"].unique().tolist()),
        "products": sorted(data["Product"].unique().tolist()),
        "categories": sorted(data["Category"].unique().tolist()),
        "sales_channel": sorted(data["Sales_Channel"].unique().tolist()),
        "customer_type": sorted(data["Customer_Type"].unique().tolist()),
        "payment": sorted(data["Payment_Method"].unique().tolist()),
        "quantity_min_max": [int(data["Quantity"].min()), int(data["Quantity"].max())],
        "discount_min_max": [float(data["Discount_Rate"].min()), float(data["Discount_Rate"].max())],
        "price_min_max": [float(data["Unit_Price_TL"].min()), float(data["Unit_Price_TL"].max())],
        "profit_margin_min_max": [float(data["Profit_Margin"].min()), float(data["Profit_Margin"].max())],
        "net_sales_total": float(data["Net_Sales"].sum()),
        "profit_total": float(data["Profit"].sum()),
        "output": OUT_NAME,
        "source": src.name,
        "raw_columns": raw_columns,
    }
    OUT_LOG.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")

    print("=" * 72)
    print("CLEANING SUMMARY")
    print("=" * 72)
    for step in log:
        print(f"  {step['step']:<48} dropped={step['dropped']:>4}  remaining={step['remaining']:>4}")
    print("-" * 72)
    print(f"Raw: {n_raw}  ->  Clean: {len(data)}  (dropped {n_raw - len(data)})")
    print("Columns:", columns)
    print("Saved:", OUT_NAME)
    return data, summary


if __name__ == "__main__":
    main()
