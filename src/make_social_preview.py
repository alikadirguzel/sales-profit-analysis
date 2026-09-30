"""Build a 1280x640 GitHub social-preview banner. Run from repo root."""

from __future__ import annotations

from pathlib import Path

import matplotlib.pyplot as plt
import matplotlib.image as mpimg
from matplotlib.patches import FancyBboxPatch

ROOT = Path(__file__).resolve().parent.parent
FIG = ROOT / "reports" / "figures"
OUT = FIG / "social_preview.png"

PRIMARY = "#1B3A4B"
GOLD = "#E8EEF2"
ACCENT = "#3D8B6E"
MUTED = "#9BB0BF"


def main() -> None:
    fig = plt.figure(figsize=(12.80, 6.40), dpi=100, facecolor=PRIMARY)
    gs = fig.add_gridspec(1, 2, width_ratios=[1.05, 1.15], wspace=0.04)

    ax_l = fig.add_subplot(gs[0, 0])
    ax_l.set_xlim(0, 1)
    ax_l.set_ylim(0, 1)
    ax_l.axis("off")
    ax_l.set_facecolor(PRIMARY)

    ax_l.text(0.08, 0.82, "SALES PROFIT ANALYSIS", fontsize=11, color=MUTED, fontweight="bold")
    ax_l.text(0.08, 0.68, "Quote-time profit\nprediction", fontsize=22, color="white", fontweight="bold", va="top")
    ax_l.text(0.08, 0.42, "XGBoost  ·  Extra Trees  ·  SHAP", fontsize=11, color=MUTED)

    cards = [
        (0.08, "279 TL", "test MAE"),
        (0.38, "0.77", "test R²"),
        (0.68, "747 TL", "lift / order"),
    ]
    for x, value, label in cards:
        box = FancyBboxPatch(
            (x, 0.10),
            0.26,
            0.24,
            boxstyle="round,pad=0.02,rounding_size=0.03",
            linewidth=0,
            facecolor="#24485C",
        )
        ax_l.add_patch(box)
        ax_l.text(x + 0.13, 0.24, value, ha="center", va="center", color=ACCENT, fontsize=14, fontweight="bold")
        ax_l.text(x + 0.13, 0.15, label, ha="center", va="center", color=MUTED, fontsize=8)

    ax_r = fig.add_subplot(gs[0, 1])
    img = mpimg.imread(FIG / "actual_vs_predicted.png")
    ax_r.imshow(img)
    ax_r.axis("off")
    ax_r.set_title("Actual vs predicted (test)", color=GOLD, fontsize=11, pad=8)

    fig.subplots_adjust(left=0.01, right=0.99, top=0.94, bottom=0.04)
    fig.savefig(OUT, dpi=100, facecolor=PRIMARY)
    plt.close(fig)
    print("Wrote reports/figures/social_preview.png")


if __name__ == "__main__":
    main()
