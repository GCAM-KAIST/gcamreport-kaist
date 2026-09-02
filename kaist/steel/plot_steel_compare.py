# -*- coding: utf-8 -*-
"""Presentation charts comparing steel results across GCAM scenarios.
Reads KMIP2026_steel_compare.xlsx (+ steel_intermediates_{tag}.xlsx for
production by tech) from the data folder and writes PNGs to charts/ (Korean
titles) or charts/en/ (--en, IAMC variable names).

Usage (from the repo root):
  python -X utf8 kaist/steel/plot_steel_compare.py \
      --dir kmip/KMIP25_6Scenarios_output/iron_report [--en]
Running inside the data folder without --dir still works."""
import argparse
import os
import pandas as pd
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib import font_manager

# Korean-capable font if present
for f in ("Malgun Gothic", "NanumGothic", "Apple SD Gothic Neo"):
    if any(f == x.name for x in font_manager.fontManager.ttflist):
        plt.rcParams["font.family"] = f
        break
plt.rcParams["axes.unicode_minus"] = False

# (sheet in KMIP2026_steel_compare.xlsx, intermediates tag, panel title)
SCEN = [("ref_con", "ref_con", "R_con (GCAM7)"),
        ("S1", "S1", "S1 (GCAM7)"),
        ("kaist9", "kaist9_nz", "NZ (KAIST9)")]
# validated categorical palette, fixed slot order (dataviz reference palette)
PAL = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#4a3aa7", "#e34948"]
INK, MUTED, GRID, SURF = "#0b0b0b", "#898781", "#e1e0d9", "#fcfcfb"
ap = argparse.ArgumentParser()
ap.add_argument("--dir", default=".", help="data folder (default: current folder)")
ap.add_argument("--en", action="store_true", help="English titles -> charts/en/")
args = ap.parse_args()
if not os.path.isdir(args.dir):
    raise SystemExit(f"--dir not found: {args.dir}")
os.chdir(args.dir)

LANG = "en" if args.en else "ko"
OUT = "charts/en" if LANG == "en" else "charts"
os.makedirs(OUT, exist_ok=True)
E = "Emissions|CO2|Energy|Demand|Industry|Iron and Steel"
P = "Emissions|GHGs|Non-Energy|Industrial Process|Iron and Steel"
C = "Carbon Sequestration|CCS|Energy|Demand|Industry|Iron and Steel"
S = "Production|Iron and Steel|Steel"
# titles: ko = presentation wording, en = IAMC variable names as-is
T = {
 "emis": ("철강 CO2 배출량: 에너지 / 공정 / CCS 포집",
          "Iron and Steel: Emissions|CO2|Energy|Demand + Emissions|GHGs|Non-Energy|Industrial Process  (Carbon Sequestration|CCS shown below zero)"),
 "fe":   ("철강 최종에너지 소비: 연료별", "Final Energy|Industry|Iron and Steel|{fuel}"),
 "ff":   ("연료탄 / 원료탄(환원제) / 수소 환원제", "Final Energy|Industry|Iron and Steel|{Coal|Fuel, Coal|Feedstock, Hydrogen|Feedstock}"),
 "tech": ("조강 생산량: 기술별", "Production|Iron and Steel|Steel by GCAM technology"),
 "co2":  ("철강 총 CO2 배출 (에너지 + 공정)", "Emissions|CO2|Energy|Demand + GHGs|Non-Energy|Industrial Process"),
 "steel":("조강 생산량", "Production|Iron and Steel|Steel"),
}
def t(k): return T[k][1] if LANG == "en" else T[k][0]
def L(ko, en): return en if LANG == "en" else ko

V = "Final Energy|Industry|Iron and Steel"
cmp = {s: pd.read_excel("KMIP2026_steel_compare.xlsx", s).set_index("variable") for s, _, _ in SCEN}


def years(sheet):
    return [c for c in cmp[sheet].columns if isinstance(c, int)]


def series(sheet, var):
    return cmp[sheet].loc[var, years(sheet)].astype(float).fillna(0).values


def style(ax, ylabel, title):
    ax.set_facecolor(SURF)
    for s in ("top", "right"):
        ax.spines[s].set_visible(False)
    ax.spines["left"].set_color(GRID); ax.spines["bottom"].set_color("#c3c2b7")
    ax.yaxis.grid(True, color=GRID, lw=0.8); ax.set_axisbelow(True)
    ax.tick_params(colors=MUTED, labelsize=9)
    ax.set_title(title, fontsize=11, color=INK, loc="left")
    if ylabel: ax.set_ylabel(ylabel, color=MUTED, fontsize=9)


def stacked_panels(specs, ylabel, suptitle, fname, neg=None):
    """specs: list of (label, color, var) stacked; neg: (label,color,var) drawn below zero."""
    fig, axes = plt.subplots(1, 3, figsize=(13, 4.2), sharey=True, facecolor=SURF)
    for ax, (sheet, tag, name) in zip(axes, SCEN):
        yrs = years(sheet); x = range(len(yrs)); bottom = [0.0] * len(yrs)
        for lab, col, var in specs:
            v = series(sheet, var)
            ax.bar(x, v, bottom=bottom, color=col, width=0.7, edgecolor=SURF, linewidth=1.5, label=lab)
            bottom = [b + a for b, a in zip(bottom, v)]
        if neg:
            lab, col, var = neg
            ax.bar(x, -series(sheet, var), color=col, width=0.7, edgecolor=SURF, linewidth=1.5, label=lab)
            ax.axhline(0, color="#c3c2b7", lw=1)
        ax.set_xticks(list(x)); ax.set_xticklabels(yrs)
        style(ax, ylabel if ax is axes[0] else None, name)
    h, l = axes[0].get_legend_handles_labels()
    fig.legend(h, l, loc="upper left", ncol=min(len(l), 8), frameon=False, fontsize=9, bbox_to_anchor=(0.01, 0.95))
    fig.suptitle(suptitle, x=0.01, ha="left", fontsize=13 if LANG=="ko" else 10.5, color=INK, fontweight="bold")
    fig.tight_layout(rect=(0, 0, 1, 0.87))
    fig.savefig(f"{OUT}/{fname}", dpi=200, facecolor=SURF); plt.close(fig)


# 1. Emissions: energy + process stacked, CCS below zero
stacked_panels(
    [(L("Energy CO2", "Emissions|CO2|Energy|Demand"), PAL[0], E),
     (L("Process (IPPU)", "Emissions|GHGs|Non-Energy|Industrial Process"), PAL[1], P)],
    "Mt CO2/yr", t("emis"), "1_emissions.png",
    neg=(L("CCS captured", "Carbon Sequestration|CCS (captured)"), PAL[2], C))

# 2. Final energy by fuel
stacked_panels(
    [("Coal", PAL[0], f"{V}|Coal"), ("Oil", PAL[1], f"{V}|Oil"), ("Gas", PAL[2], f"{V}|Gas"),
     ("Electricity", PAL[3], f"{V}|Electricity"), ("Biomass", PAL[4], f"{V}|Biomass"),
     ("Hydrogen", PAL[5], f"{V}|Hydrogen")],
    "ktoe/yr", t("fe"), "2_final_energy_by_fuel.png")

# 3. Fuel vs feedstock
stacked_panels(
    [("Coal|Fuel", PAL[0], f"{V}|Coal|Fuel"), ("Coal|Feedstock", PAL[1], f"{V}|Coal|Feedstock"),
     ("Hydrogen|Feedstock", PAL[2], f"{V}|Hydrogen|Feedstock")],
    "ktoe/yr", t("ff"), "3_fuel_feedstock.png")

# 4. Production by technology (fixed tech->slot mapping across scenarios)
TECH = [("BLASTFUR", PAL[0]), ("BLASTFUR CCS", PAL[1]), ("BLASTFUR with hydrogen", PAL[2]),
        ("Biomass-based", PAL[3]), ("EAF with DRI", PAL[4]), ("EAF with DRI CCS", PAL[5]),
        ("Hydrogen-based DRI", PAL[6]), ("EAF with scrap", PAL[7])]
fig, axes = plt.subplots(1, 3, figsize=(13, 4.2), sharey=True, facecolor=SURF)
for ax, (sheet, tag, name) in zip(axes, SCEN):
    p = pd.read_excel(f"steel_intermediates_{tag}.xlsx", "production_by_tech_Mt").set_index("technology")
    yrs = [c for c in p.columns if isinstance(c, int)]; x = range(len(yrs)); bottom = [0.0] * len(yrs)
    for tech, col in TECH:
        v = p.loc[tech, yrs].astype(float).values if tech in p.index else [0.0] * len(yrs)
        ax.bar(x, v, bottom=bottom, color=col, width=0.7, edgecolor=SURF, linewidth=1.5, label=tech)
        bottom = [b + a for b, a in zip(bottom, v)]
    ax.set_xticks(list(x)); ax.set_xticklabels(yrs)
    style(ax, "Mt/yr" if ax is axes[0] else None, name)
h, l = axes[0].get_legend_handles_labels()
fig.legend(h, l, loc="upper left", ncol=4, frameon=False, fontsize=8.5, bbox_to_anchor=(0.01, 0.95))
fig.suptitle(t("tech"), x=0.01, ha="left", fontsize=13, color=INK, fontweight="bold")
fig.tight_layout(rect=(0, 0, 1, 0.85)); fig.savefig(f"{OUT}/4_production_by_tech.png", dpi=200, facecolor=SURF); plt.close(fig)

# 5. Line comparison: total CO2 (energy+process, net of nothing) and steel production
fig, axes = plt.subplots(1, 2, figsize=(11, 4), facecolor=SURF)
for (sheet, tag, name), col, mk in zip(SCEN, PAL[:3], ("o", "s", "^")):
    yrs = years(sheet)
    tot = series(sheet, E) + series(sheet, P)
    axes[0].plot(yrs, tot, color=col, marker=mk, ms=6, lw=2, label=name)
    axes[0].annotate(f"{tot[-1]:.0f}", (yrs[-1], tot[-1]), xytext=(5, 0), textcoords="offset points", fontsize=8, color=INK, va="center")
    st = series(sheet, S)
    axes[1].plot(yrs, st, color=col, marker=mk, ms=6, lw=2, label=name)
    axes[1].annotate(f"{st[-1]:.0f}", (yrs[-1], st[-1]), xytext=(5, 0), textcoords="offset points", fontsize=8, color=INK, va="center")
style(axes[0], "Mt CO2/yr", t("co2")); style(axes[1], "Mt/yr", t("steel"))
for ax in axes: ax.set_ylim(bottom=0); ax.legend(frameon=False, fontsize=9)
fig.tight_layout(); fig.savefig(f"{OUT}/5_lines_total.png", dpi=200, facecolor=SURF); plt.close(fig)
print("charts written to", OUT)
