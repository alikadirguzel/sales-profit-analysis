from src.features import add_rowwise_features, chronological_masks, model_matrix
from src.config import LEAKAGE_DROP, TARGET
from src.data_processing import accounting_identity, load_orders
from src.evaluate import regression_metrics


def test_load_and_target():
    df = load_orders()
    assert len(df) == 958
    assert TARGET in df.columns
    assert df[TARGET].notna().all()


def test_leakage_columns_dropped_from_model_matrix():
    df = load_orders()
    X, y = model_matrix(df)
    for col in LEAKAGE_DROP:
        assert col not in X.columns
    assert TARGET not in X.columns
    assert len(X) == len(y) == len(df)


def test_accounting_identity_is_almost_exact():
    df = load_orders()
    mae = regression_metrics(df[TARGET], accounting_identity(df))["MAE"]
    assert mae < 0.01


def test_chronological_split_is_ordered():
    df = load_orders()
    train_mask, test_mask, cutoff = chronological_masks(df["Date"])
    assert train_mask.sum() > 0 and test_mask.sum() > 0
    assert df.loc[train_mask, "Date"].max() < cutoff
    assert df.loc[test_mask, "Date"].min() >= cutoff
    assert not (train_mask & test_mask).any()


def test_rowwise_features_are_quote_time():
    df = load_orders().head(20)
    out = add_rowwise_features(df)
    assert {"list_revenue", "net_unit_price", "discount_value_unit", "is_weekend"} <= set(out.columns)
    assert (out["list_revenue"] == out["Quantity"] * out["Unit_Price_TL"]).all()
