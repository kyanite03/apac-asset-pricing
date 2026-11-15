"""Extract Tencent financials from its annual reports into a tidy, sourced CSV.

    uv run --no-project --with pymupdf python scripts/extract_tencent.py

Reads data/raw/tencent/AR{2022..2025}.pdf (Tencent annual reports, see
data/raw/tencent/SOURCE.txt) and writes data/processed/tencent_financials.csv
with one row per (fiscal year, item, source report), including the page number,
so every figure can be traced. Each report shows the current and prior year, so
most years are extracted twice; check_tencent() in R/data_tencent.R compares them.

Figures are RMB millions unless the item name says otherwise.
"""
import csv
import re
from pathlib import Path

import pymupdf

RAW = Path("data/raw/tencent")
OUT = Path("data/processed/tencent_financials.csv")
NUM = r"\(?-?\d[\d,]*(?:\.\d+)?\)?|(?<=\s)[–-](?=\s)"   # 1,234 / (1,234) / 24.153 / lone dash = nil


def to_number(tok):
    tok = tok.strip()
    if tok in {"–", "-"}:
        return 0.0
    neg = tok.startswith("(") and tok.endswith(")")
    val = float(tok.strip("()").replace(",", ""))
    return -val if neg else val


def load_pages(path):
    doc = pymupdf.open(path)
    return {i + 1: re.sub(r"\s+", " ", p.get_text()) for i, p in enumerate(doc)}


def find_page(pages, *must):
    """First page containing every string in `must` (case-sensitive)."""
    for n, txt in pages.items():
        if all(m in txt for m in must):
            return n
    raise LookupError(f"no page with {must}")


NOTE_ANY = r"\d{1,2}(\([a-z]\))?"     # income statement / balance sheet note refs: "7", "12(a)"
NOTE_LETTER = r"\d{1,2}\([a-z]\)"      # cash-flow note refs always carry a letter: "19(b)", "43(a)"


def numbers_after(txt, label, k, note=NOTE_ANY, regex=False):
    """The k numbers that follow `label` on a page.

    `note` is a pattern for a note reference that may sit between the label and
    the figures and must be skipped (None = never skip). On the cash-flow page a
    bare small number is a genuine value (e.g. a RMB 6m refund), so callers pass
    NOTE_LETTER there."""
    m = re.search(label if regex else re.escape(label), txt)
    if not m:
        raise LookupError(label)
    rest = txt[m.end():].lstrip()
    first = rest.split(" ")[0] if rest else ""
    if note and re.fullmatch(note, first):
        rest = rest[len(first):]
    toks = re.findall(NUM, rest)
    return [to_number(t) for t in toks[:k]]


def nth_after(txt, label, occurrence, k):
    """Like numbers_after but for the n-th occurrence (e.g. current vs non-current borrowings)."""
    starts = [m.end() for m in re.finditer(re.escape(label), txt)]
    sub = txt[starts[occurrence - 1] - len(label):]
    return numbers_after(sub, label, k)


MISSING = []


def extract(year):
    pages = load_pages(RAW / f"AR{year}.pdf")
    rows = []

    def add(item, vals, page, cols=(year, year - 1)):
        for fy, v in zip(cols, vals):
            rows.append({"fy": fy, "item": item, "value": v, "source": f"AR{year}", "page": page})

    # Consolidated income statement (current, prior)
    p = find_page(pages, "Consolidated Income Statement", "Cost of revenues", "Earnings per share")
    t = pages[p]
    adv = "Marketing Services" if "Marketing Services" in t else "Online Advertising"
    for item, label in [("rev_vas", "Value-added Services"), ("rev_marketing", adv),
                        ("rev_fintech_business", "FinTech and Business Services"), ("rev_others", "Others"),
                        ("cost_of_revenues", "Cost of revenues"), ("gross_profit", "Gross profit"),
                        ("selling_marketing", "Selling and marketing expenses"),
                        ("general_admin", "General and administrative expenses"),
                        ("other_gains", "Other gains/(losses), net"), ("operating_profit", "Operating profit"),
                        ("finance_costs", r"Finance costs(, net)?"),
                        ("share_of_associates", "Share of profit/(loss) of associates and joint ventures, net"),
                        ("profit_before_tax", "Profit before income tax"), ("income_tax", "Income tax expense"),
                        ("profit_for_year", "Profit for the year"),
                        ("profit_attrib", "Equity holders of the Company"),
                        ("profit_nci", "Non-controlling interests")]:
        try:
            add(item, numbers_after(t, label, 2, regex=(item == "finance_costs")), p)
        except LookupError:
            MISSING.append((f"AR{year}", item, label))
    # total revenue = the number right after "Others x y <note>"
    m = re.search(r"Others ([\d,]+) ([\d,]+) \d+ ([\d,]+) ([\d,]+)", t)
    add("revenue", [to_number(m.group(3)), to_number(m.group(4))], p)

    # Non-IFRS / EBITDA reconciliation table: columns Q4, Q3, Q4 prior, FY, FY prior
    p = find_page(pages, "reconciles our operating profit to our EBITDA")
    t = pages[p]
    for item, label in [("dep_ppe", "Depreciation of property, plant and equipment and investment properties"),
                        ("dep_rou", "Depreciation of right-of-use assets"),
                        ("amort_intangibles", "Amortisation of intangible assets and land use rights"),
                        ("ebitda", r"(?<!Adjusted )EBITDA(?= \(?\d)"), ("sbc_equity", "Equity-settled share-based compensation"),
                        ("adj_ebitda", r"Adjusted EBITDA(?= \(?\d)")]:
        try:
            add(item, numbers_after(t, label, 5, note=None, regex=item in ("ebitda", "adj_ebitda"))[3:5], p)
        except LookupError:
            MISSING.append((f"AR{year}", item, label))

    # "Other financial information": net cash and capex (FY columns are 4th and 5th)
    p = find_page(pages, "OTHER FINANCIAL INFORMATION", "Capital expenditures")
    t = pages[p]
    for lab in ("Net cash (c)", "Net cash/(debt) (c)", "Net (debt)/cash (c)"):   # label changed over time
        if lab in t:
            add("net_cash", numbers_after(t, lab, 5, note=None)[3:5], p)
            break
    else:
        raise LookupError("net cash row")
    add("capex_reported", numbers_after(t, "Capital expenditures (d)", 5, note=None)[3:5], p)

    # Cash flow statement
    p = find_page(pages, "Consolidated Statement of Cash Flows", "Net cash flows generated from operating activities")
    t = pages[p]
    for item, label in [("cfo", "Net cash flows generated from operating activities"),
                        ("income_tax_paid", "Income tax paid"),
                        ("capex_ppe_paid", "Purchase of/prepayments for property, plant and equipment, construction in progress and investment properties"),
                        ("intangibles_paid", "Purchase of/prepayments for intangible assets"),
                        ("land_use_rights_paid", "land use rights"),
                        ("capex_ppe_paid", "Purchase of property, plant and equipment, construction in progress and investment properties"),
                        ("interest_received", "Interest received"), ("dividends_received", "Dividends received")]:
        if item == "capex_ppe_paid" and any(r["item"] == item for r in rows):
            continue                              # newer label already matched; older wording is the fallback
        try:
            add(item, numbers_after(t, label, 2, note=NOTE_LETTER), p)
        except LookupError:
            MISSING.append((f"AR{year}", item, label))
    p = find_page(pages, "Consolidated Statement of Cash Flows", "Cash flows from financing activities")
    t = pages[p]
    for item, label in [("lease_principal_paid", "Principal elements of lease payments"),
                        ("buybacks_paid", "Payments for repurchase of shares"),
                        ("dividends_paid", "Dividends paid to the Company’s shareholders"),
                        ("interest_paid", "Interest paid")]:
        try:
            add(item, numbers_after(t, label, 2, note=NOTE_LETTER), p)
        except LookupError:
            MISSING.append((f"AR{year}", item, label))

    # Balance sheet: equity and liabilities pages
    p = find_page(pages, "Consolidated Statement of Financial Position", "Non-controlling interests", "Non-current liabilities")
    t = pages[p]
    add("nci_equity", numbers_after(t, "Non-controlling interests", 2), p)
    add("equity_attrib", numbers_after(t, "Retained earnings", 3)[2:3] + [None], p)
    add("borrowings_noncurrent", numbers_after(t, "Borrowings", 2), p)
    add("notes_noncurrent", numbers_after(t, "Notes payable", 2), p)
    add("lease_liab_noncurrent", numbers_after(t, "Lease liabilities", 2), p)
    p2 = find_page(pages, "Consolidated Statement of Financial Position", "Current liabilities", "Total equity and liabilities")
    t2 = pages[p2]
    add("borrowings_current", numbers_after(t2, "Borrowings", 2), p2)
    add("notes_current", numbers_after(t2, "Notes payable", 2), p2)
    add("lease_liab_current", numbers_after(t2, "Lease liabilities", 2), p2)

    # Liquidity table: cash and term deposits at year end (current, prior quarter-end -> take first only)
    p = find_page(pages, "LIQUIDITY AND FINANCIAL RESOURCES", "Term deposits and others")
    t = pages[p]
    add("cash", numbers_after(t, "Cash and cash equivalents", 1, note=None), p, cols=(year,))
    add("term_deposits_others", numbers_after(t, "Term deposits and others", 1, note=None), p, cols=(year,))

    # Investment portfolio (MD&A). Units vary by year (RMB million or billion); stored in RMB billion.
    p = find_page(pages, "listed investee companies (excluding subsidiaries) amounted to")
    t = pages[p]
    amt = r"RMB([\d,.]+) ?(billion|million)"
    def bn(v, unit):
        x = float(v.replace(",", ""))
        return x / 1000 if unit == "million" else x
    for item, kind in [("listed_investments_fv_bn", "listed"), ("unlisted_investments_bv_bn", "unlisted")]:
        pat = (rf"(?<![a-z]){kind} investee companies \(excluding subsidiaries\) amounted to {amt} "
               rf"as at 31 December \d{{4}} \(31 December \d{{4}}: {amt}\)")
        m = re.search(pat, t)
        if m:
            add(item, [bn(m.group(1), m.group(2)), bn(m.group(3), m.group(4))], p)
        elif kind == "listed":
            raise LookupError("listed investments sentence")

    # Diluted share count (million shares), weighted average for the year
    p = find_page(pages, "Weighted average number of ordinary shares for the calculation of diluted EPS")
    t = pages[p]
    add("shares_diluted_wavg_m", numbers_after(t, "Weighted average number of ordinary shares for the calculation of diluted EPS (million shares)", 2, note=None), p)
    return rows


def five_year_summary(year):
    """The 'Financial Summary' page: five years of headline income items."""
    pages = load_pages(RAW / f"AR{year}.pdf")
    p = find_page(pages, "Financial Summary", "CONDENSED CONSOLIDATED STATEMENTS OF COMPREHENSIVE INCOME")
    t = pages[p]
    years = list(range(year - 4, year + 1))
    rows = []
    for item, label in [("revenue", "Revenues"), ("gross_profit", "Gross profit"),
                        ("operating_profit", "Operating profit"), ("profit_before_tax", "Profit before income tax"),
                        ("profit_for_year", "Profit for the year"),
                        ("profit_attrib", "Profit attributable to equity holders of the Company"),
                        ("nonifrs_operating_profit", "Non-IFRS operating profit"),
                        ("nonifrs_profit_attrib", "Non-IFRS profit attributable to equity holders of the Company")]:
        try:
            vals = numbers_after(t, label, 5, note=None)
        except LookupError:
            MISSING.append((f"AR{year} summary", item, label))
            continue
        rows += [{"fy": fy, "item": item, "value": v, "source": f"AR{year} summary", "page": p}
                 for fy, v in zip(years, vals)]
    return rows


def interim_2026():
    """Latest balance sheet (30 June 2026) and share count from the 2026 Interim Report.

    These anchor the valuation date. Rows use fy = "2026H1"."""
    pages = load_pages(RAW / "IR2026.pdf")
    rows = []

    def add(item, v, page):
        rows.append({"fy": "2026H1", "item": item, "value": v, "source": "IR2026", "page": page})

    p = find_page(pages, "LIQUIDITY AND FINANCIAL RESOURCES", "Term deposits and others")
    t = pages[p]
    for item, label in [("cash", "Cash and cash equivalents"), ("term_deposits_others", "Term deposits and others"),
                        ("borrowings_total", "Borrowings"), ("notes_total", "Notes payable"), ("net_cash", "Net cash")]:
        add(item, numbers_after(t, label, 1, note=None)[0], p)

    p = find_page(pages, "listed investee companies (excluding subsidiaries) amounted to")
    t = pages[p]
    for item, kind in [("listed_investments_fv_bn", "listed"), ("unlisted_investments_bv_bn", "unlisted")]:
        m = re.search(rf"(?<![a-z]){kind} investee companies \(excluding subsidiaries\) amounted to RMB([\d.]+) billion", t)
        add(item, float(m.group(1)), p)

    p = find_page(pages, "Non-controlling interests", "Non-current liabilities", "Lease liabilities")
    t = pages[p]
    add("nci_equity", numbers_after(t, "Non-controlling interests", 1)[0], p)
    add("lease_liab_noncurrent", numbers_after(t, "Lease liabilities", 1)[0], p)
    p = find_page(pages, "Current liabilities", "Total equity and liabilities", "Lease liabilities")
    add("lease_liab_current", numbers_after(pages[p], "Lease liabilities", 1)[0], p)

    p = find_page(pages, "Number of ordinary shares, issued and fully paid")
    t = pages[p]
    add("shares_issued_m", numbers_after(t, "At end of period", 1, note=None)[0] / 1e6, p)
    m = re.search(r"included ([\d,]+) shares \(31 December \d{4}: [\d,]+ shares\) held for the share award scheme", t)
    add("shares_award_scheme_m", to_number(m.group(1)) / 1e6, p)

    # Six-month income statement: columns are Q2 2026, Q2 2025, H1 2026, H1 2025
    p = find_page(pages, "Condensed Consolidated Income Statement", "Cost of revenues")
    t = pages[p]
    for item, label in [("rev_vas", "Value-added Services"), ("rev_marketing", "Marketing Services"),
                        ("rev_fintech_business", "FinTech and Business Services"),
                        ("operating_profit", "Operating profit"), ("share_of_associates", "Share of profit/(loss) of associates and joint ventures, net")]:
        v = numbers_after(t, label, 4)
        add(item + "_h1", v[2], p)
        rows.append({"fy": "2025H1", "item": item + "_h1", "value": v[3], "source": "IR2026", "page": p})
    m = re.search(r"Others ([\d,]+) ([\d,]+) ([\d,]+) ([\d,]+) \d+ ([\d,]+) ([\d,]+) ([\d,]+) ([\d,]+)", t)
    add("revenue_h1", to_number(m.group(7)), p)
    rows.append({"fy": "2025H1", "item": "revenue_h1", "value": to_number(m.group(8)), "source": "IR2026", "page": p})
    p = find_page(pages, "Capital expenditures (d)", "EBITDA")
    v = numbers_after(pages[p], "Capital expenditures (d)", 5, note=None)
    add("capex_reported_h1", v[3], p)
    ve = numbers_after(pages[p], r"(?<!Adjusted )EBITDA (\(a\) )?(?=\(?\d)", 5, note=None, regex=True)
    add("ebitda_h1", ve[3], p)
    rows.append({"fy": "2025H1", "item": "ebitda_h1", "value": ve[4], "source": "IR2026", "page": p})
    rows.append({"fy": "2025H1", "item": "capex_reported_h1", "value": v[4], "source": "IR2026", "page": p})

    p = find_page(pages, "Weighted average number of ordinary shares for the calculation of diluted EPS")
    t = pages[p]
    add("shares_diluted_wavg_q2_m", numbers_after(t, "Weighted average number of ordinary shares for the calculation of diluted EPS (million shares)", 1, note=None)[0], p)
    return rows


if __name__ == "__main__":
    rows = []
    for y in (2022, 2023, 2024, 2025):
        rows += extract(y)
        rows += five_year_summary(y)
    rows += interim_2026()
    rows = [r for r in rows if r["value"] is not None]
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with OUT.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["fy", "item", "value", "source", "page"])
        w.writeheader()
        w.writerows(sorted(rows, key=lambda r: (r["item"], str(r["fy"]), r["source"])))
    print(f"wrote {len(rows)} rows to {OUT}")
    found = {(r["source"], r["item"]) for r in rows}
    for m in MISSING:
        if (m[0], m[1]) not in found:            # ignore labels rescued by a fallback wording
            print("MISSING:", *m)
