# -*- coding: utf-8 -*-
"""
Sales data cleaning.

Column headers (first row) are not renamed.
Output: Temizlenmiş_SatışVerisi.xlsx (same folder as this script).
Raw input, if present: SatışVerisi.xlsx
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
SRC_NAME = "SatışVerisi.xlsx"
OUT_NAME = "Temizlenmiş_SatışVerisi.xlsx"
LOG_NAME = "temizleme_ozeti.json"
SRC = ROOT / SRC_NAME
OUT_XLSX = ROOT / OUT_NAME
OUT_LOG = ROOT / LOG_NAME


# ---------------------------------------------------------------------------
# Türkçe metin yardımcıları
# ---------------------------------------------------------------------------
_TR_LOWER = str.maketrans(
    {
        "I": "ı",
        "İ": "i",
        "Ç": "ç",
        "Ğ": "ğ",
        "Ö": "ö",
        "Ş": "ş",
        "Ü": "ü",
    }
)
_TR_UPPER_FIRST = {
    "i": "İ",
    "ı": "I",
    "ç": "Ç",
    "ğ": "Ğ",
    "ö": "Ö",
    "ş": "Ş",
    "ü": "Ü",
}


def fold_key(value) -> str:
    """Karşılaştırma anahtarı: I/İ/ı -> i, diğer Türkçe harfler korunur."""
    if value is None or (isinstance(value, float) and np.isnan(value)):
        return ""
    s = str(value).strip()
    s = unicodedata.normalize("NFKC", s)
    s = s.replace("İ", "i").replace("I", "i").replace("ı", "i")
    s = s.replace("Ç", "ç").replace("Ğ", "ğ").replace("Ö", "ö").replace("Ş", "ş").replace("Ü", "ü")
    s = s.lower()
    s = s.replace("i̇", "i")
    s = re.sub(r"[\s_\-]+", " ", s).strip()
    return s


def tr_title(value: str) -> str:
    parts = str(value).strip().split()
    out = []
    for part in parts:
        low = part.translate(_TR_LOWER).lower()
        if not low:
            continue
        first = _TR_UPPER_FIRST.get(low[0], low[0].upper())
        out.append(first + low[1:])
    return " ".join(out)


def is_empty(series: pd.Series) -> pd.Series:
    s = series.astype("string").str.strip()
    return (
        series.isna()
        | s.isna()
        | s.eq("")
        | s.str.lower().isin(["nan", "nat", "none", "null", "<undefined>", "-", "na"])
    )


# ---------------------------------------------------------------------------
# Standart sözlükler
# ---------------------------------------------------------------------------
SEHIR_MAP = {
    "istanbul": "İstanbul",
    "izmir": "İzmir",
    "ankara": "Ankara",
    "antalya": "Antalya",
    "bursa": "Bursa",
    "adana": "Adana",
    "konya": "Konya",
    "gaziantep": "Gaziantep",
    "samsun": "Samsun",
    "trabzon": "Trabzon",
}

BOLGE_MAP = {
    "marmara": "Marmara",
    "ege": "Ege",
    "akdeniz": "Akdeniz",
    "ic anadolu": "İç Anadolu",
    "iç anadolu": "İç Anadolu",
    "karadeniz": "Karadeniz",
    "guneydogu anadolu": "Güneydoğu Anadolu",
    "güneydoğu anadolu": "Güneydoğu Anadolu",
    "dogu anadolu": "Doğu Anadolu",
    "doğu anadolu": "Doğu Anadolu",
}

SEHIR_BOLGE = {
    "İstanbul": "Marmara",
    "Bursa": "Marmara",
    "İzmir": "Ege",
    "Ankara": "İç Anadolu",
    "Konya": "İç Anadolu",
    "Antalya": "Akdeniz",
    "Adana": "Akdeniz",
    "Samsun": "Karadeniz",
    "Trabzon": "Karadeniz",
    "Gaziantep": "Güneydoğu Anadolu",
}

URUN_MAP = {
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

KATEGORI_MAP = {
    "elektronik": "Elektronik",
    "ofis aksesuarlari": "Ofis Aksesuarları",
    "ofis aksesuarları": "Ofis Aksesuarları",
    "kirtasiye": "Kırtasiye",
    "kırtasiye": "Kırtasiye",
    "mobilya": "Mobilya",
    "aksesuar": "Aksesuar",
}

URUN_KATEGORI = {
    "Wireless Mouse": "Elektronik",
    "USB-C Hub": "Elektronik",
    "Webcam": "Elektronik",
    "Monitor 24": "Elektronik",
    "Monitor 27": "Elektronik",
    "Mechanical Keyboard": "Elektronik",
    "Desk Lamp": "Ofis Aksesuarları",
    "Laptop Stand": "Ofis Aksesuarları",
    "Office Chair": "Mobilya",
    "Notebook Set": "Kırtasiye",
    "Pen Set": "Kırtasiye",
    "Backpack": "Aksesuar",
}

SATIS_KANALI_MAP = {
    "online": "Online",
    "magaza": "Mağaza",
    "mağaza": "Mağaza",
    "bayi": "Bayi",
}

MUSTERI_TIPI_MAP = {
    "bireysel": "Bireysel",
    "kobi": "KOBI",
    "kurumsal": "Kurumsal",
}

ODEME_MAP = {
    "kredi karti": "Kredi Kartı",
    "kredi kartı": "Kredi Kartı",
    "havale/eft": "Havale/EFT",
    "havale eft": "Havale/EFT",
    "nakit": "Nakit",
}


def map_series(series: pd.Series, mapping: dict, fallback_title: bool = False) -> pd.Series:
    keys = series.map(fold_key)
    mapped = keys.map(mapping)
    if fallback_title:
        still = mapped.isna() & keys.ne("")
        mapped = mapped.where(~still, series[still].map(lambda x: tr_title(str(x))))
    mapped = mapped.where(keys.ne(""), pd.NA)
    return mapped


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
    log.append({"adim": reason, "silinen": n, "kalan": int((~mask).sum())})
    return data.loc[~mask].copy()


def main():
    if not SRC.exists():
        raise FileNotFoundError(
            f"Raw file not found: {SRC_NAME} (place it in the same folder as this script)"
        )

    log = []
    data = pd.read_excel(SRC, dtype={"Siparis_ID": "string", "Tarih": "string"})
    n_raw = len(data)
    ham_kolonlar = list(data.columns)
    log.append({"adim": "Ham veri", "silinen": 0, "kalan": n_raw})

    # 1) Musteri_ID sil (ister: dikkate alınmayacak / silinebilir)
    if "Musteri_ID" in data.columns:
        data = data.drop(columns=["Musteri_ID"])

    # 2) Siparis_ID tekrarları
    data = drop(data, data.duplicated("Siparis_ID", keep="first"), "Tekrar eden Siparis_ID", log)

    # 3) Tarih: parse et, geçersizleri sil, Gün.Ay.Yıl
    parsed = data["Tarih"].map(parse_date)
    data = drop(data, parsed.isna(), "Geçersiz / boş / anlamsız Tarih", log)
    parsed = parsed.loc[data.index]
    data["Tarih"] = parsed.dt.strftime("%d.%m.%Y")

    # 4) Metin standartlaştırma (başlıklar aynı kalır)
    data = apply_map(data, "Sehir", SEHIR_MAP)
    data = apply_map(data, "Bolge", BOLGE_MAP)
    data = apply_map(data, "Urun", URUN_MAP)
    data = apply_map(data, "Kategori", KATEGORI_MAP)
    data = apply_map(data, "Satis_Kanali", SATIS_KANALI_MAP)
    data = apply_map(data, "Musteri_Tipi", MUSTERI_TIPI_MAP)
    data = apply_map(data, "Odeme_Yontemi", ODEME_MAP)

    # 5) Şehir, bilinen iller içinde mi? Bölge ile uyumlu mu?
    unknown_city = data["Sehir"].notna() & ~data["Sehir"].isin(SEHIR_BOLGE)
    data = drop(data, unknown_city, "Tanımsız şehir adı", log)

    beklenen = data["Sehir"].map(SEHIR_BOLGE)
    mismatch = data["Sehir"].notna() & data["Bolge"].notna() & (data["Bolge"] != beklenen)
    data = drop(data, mismatch, "Şehir-Bölge uyumsuzluğu", log)

    # 6) Ürün-kategori çapraz kontrol
    beklenen_kat = data["Urun"].map(URUN_KATEGORI)
    kat_mismatch = data["Urun"].notna() & data["Kategori"].notna() & beklenen_kat.notna() & (
        data["Kategori"] != beklenen_kat
    )
    data = drop(data, kat_mismatch, "Ürün-Kategori uyumsuzluğu", log)

    # 7) Eksik değerler → satır sil
    missing = data.isna() | data.apply(is_empty)
    data = drop(data, missing.any(axis=1), "Eksik değer içeren satır", log)

    # Sayısal kolonları sayısala çevir
    for col in ["Miktar", "Birim_Fiyat_TL", "Indirim_Orani", "Birim_Maliyet_TL"]:
        data[col] = pd.to_numeric(data[col], errors="coerce")
    data = drop(data, data[["Miktar", "Birim_Fiyat_TL", "Indirim_Orani", "Birim_Maliyet_TL"]].isna().any(axis=1),
                "Sayısal alana dönüştürülemeyen değer", log)

    # 8) Mantıksal uç değerler
    data = drop(data, data["Miktar"] < 1, "Miktar < 1 (mantıksal uç)", log)
    # Gözlemsel uç: 150 gibi aşırı miktar (Q3+5*IQR ~ 25 üstü)
    q1, q3 = data["Miktar"].quantile(0.25), data["Miktar"].quantile(0.75)
    iqr = q3 - q1
    miktar_ust = q3 + 5 * iqr
    data = drop(data, data["Miktar"] > miktar_ust, f"Miktar gözlemsel uç (>{miktar_ust:.0f})", log)

    data = drop(
        data,
        (data["Indirim_Orani"] < 0) | (data["Indirim_Orani"] > 1),
        "Indirim_Orani [0, 1] dışında",
        log,
    )
    # Gözlemsel uç: veri setinde indirimler 0–0.25 kümesinde; 0.75 tekil aşırı
    data = drop(data, data["Indirim_Orani"] > 0.50, "Indirim_Orani gözlemsel uç (>0.50)", log)

    data = drop(
        data,
        (data["Birim_Fiyat_TL"] <= 0) | (data["Birim_Maliyet_TL"] <= 0),
        "Fiyat veya maliyet <= 0",
        log,
    )

    # Ürün bazında fiyat uçları: medyanın 5 katı üstü / 0.3 katı altı
    med_fiyat = data.groupby("Urun")["Birim_Fiyat_TL"].transform("median")
    fiyat_uc = (data["Birim_Fiyat_TL"] > 5 * med_fiyat) | (data["Birim_Fiyat_TL"] < 0.3 * med_fiyat)
    data = drop(data, fiyat_uc, "Birim_Fiyat_TL ürün medyanına göre uç", log)

    med_maliyet = data.groupby("Urun")["Birim_Maliyet_TL"].transform("median")
    mal_uc = (data["Birim_Maliyet_TL"] > 5 * med_maliyet) | (data["Birim_Maliyet_TL"] < 0.3 * med_maliyet)
    data = drop(data, mal_uc, "Birim_Maliyet_TL ürün medyanına göre uç", log)

    # 9) Çapraz kontrol: maliyet < fiyat, maliyet/fiyat oranı makul
    data = drop(data, data["Birim_Maliyet_TL"] >= data["Birim_Fiyat_TL"], "Maliyet >= Fiyat", log)
    oran = data["Birim_Maliyet_TL"] / data["Birim_Fiyat_TL"]
    data = drop(data, (oran < 0.20) | (oran > 0.95), "Maliyet/Fiyat oranı mantık dışı", log)

    # 10) Hesaplanan kolonlar (başlıklar İngilizce/orijinal kalır)
    data["Net_Satis"] = data["Miktar"] * data["Birim_Fiyat_TL"] * (1 - data["Indirim_Orani"])
    data["Toplam_Maliyet"] = data["Miktar"] * data["Birim_Maliyet_TL"]
    data["Kar"] = data["Net_Satis"] - data["Toplam_Maliyet"]
    data["Kar_Marji"] = np.where(data["Net_Satis"] > 0, data["Kar"] / data["Net_Satis"], np.nan)

    data["Net_Satis"] = data["Net_Satis"].round(2)
    data["Toplam_Maliyet"] = data["Toplam_Maliyet"].round(2)
    data["Kar"] = data["Kar"].round(2)
    data["Kar_Marji"] = data["Kar_Marji"].round(6)

    data = drop(data, (data["Net_Satis"] <= 0) | data["Kar_Marji"].isna() | ~np.isfinite(data["Kar_Marji"]),
                "Net_Satis <= 0 veya tanımsız Kar_Marji", log)

    # Kar marjı uç: |marj| > 0.95 neredeyse imkânsız (fiyat~maliyet veya bedava satış)
    data = drop(data, data["Kar_Marji"].abs() > 0.95, "Kar_Marji uç (|m| > 0.95)", log)

    # Sıra: orijinal Siparis_ID sırası
    data = data.sort_values("Siparis_ID", kind="mergesort").reset_index(drop=True)

    # Tipler
    data["Miktar"] = data["Miktar"].astype(int)
    for col in ["Sehir", "Bolge", "Urun", "Kategori", "Satis_Kanali", "Musteri_Tipi", "Odeme_Yontemi"]:
        data[col] = data[col].astype(str)

    kolonlar = list(data.columns)
    assert kolonlar[0] == "Siparis_ID"
    assert "Musteri_ID" not in kolonlar
    for c in ham_kolonlar:
        if c != "Musteri_ID":
            assert c in kolonlar, f"Başlık kayboldu: {c}"

    data.to_excel(OUT_XLSX, index=False)

    ozet = {
        "ham_satir": n_raw,
        "temiz_satir": int(len(data)),
        "silinen_toplam": int(n_raw - len(data)),
        "adimlar": log,
        "kolonlar": kolonlar,
        "sehirler": sorted(data["Sehir"].unique().tolist()),
        "bolgeler": sorted(data["Bolge"].unique().tolist()),
        "urunler": sorted(data["Urun"].unique().tolist()),
        "kategoriler": sorted(data["Kategori"].unique().tolist()),
        "satis_kanali": sorted(data["Satis_Kanali"].unique().tolist()),
        "musteri_tipi": sorted(data["Musteri_Tipi"].unique().tolist()),
        "odeme": sorted(data["Odeme_Yontemi"].unique().tolist()),
        "miktar_min_max": [int(data["Miktar"].min()), int(data["Miktar"].max())],
        "indirim_min_max": [float(data["Indirim_Orani"].min()), float(data["Indirim_Orani"].max())],
        "fiyat_min_max": [float(data["Birim_Fiyat_TL"].min()), float(data["Birim_Fiyat_TL"].max())],
        "kar_marji_min_max": [float(data["Kar_Marji"].min()), float(data["Kar_Marji"].max())],
        "net_satis_toplam": float(data["Net_Satis"].sum()),
        "kar_toplam": float(data["Kar"].sum()),
        "cikti": OUT_NAME,
    }
    OUT_LOG.write_text(json.dumps(ozet, ensure_ascii=False, indent=2), encoding="utf-8")

    print("=" * 72)
    print("TEMİZLEME ÖZETİ")
    print("=" * 72)
    for step in log:
        print(f"  {step['adim']:<48} silinen={step['silinen']:>4}  kalan={step['kalan']:>4}")
    print("-" * 72)
    print(f"Ham: {n_raw}  →  Temiz: {len(data)}  (silinen {n_raw - len(data)})")
    print("Kolonlar:", kolonlar)
    print("Şehir:", ozet["sehirler"])
    print("Bölge:", ozet["bolgeler"])
    print("Kategori:", ozet["kategoriler"])
    print("Ürün:", ozet["urunler"])
    print("Kanal:", ozet["satis_kanali"])
    print("Müşteri tipi:", ozet["musteri_tipi"])
    print("Ödeme:", ozet["odeme"])
    print("Kayıt:", OUT_NAME)
    return data, ozet


if __name__ == "__main__":
    main()
