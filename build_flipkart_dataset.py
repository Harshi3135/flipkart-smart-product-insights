# Builds the warehouse bin dataset from the REAL Kaggle "Flipkart Products" file (PromptCloud).
# 1) Download flipkart_com-ecommerce_sample.csv from kaggle.com/datasets/PromptCloudHQ/flipkart-products
# 2) Put it in the same folder as this script, then run:  python build_flipkart_dataset.py
import pandas as pd, numpy as np, ast, datetime as dt, re, sys

SRC = "flipkart_com-ecommerce_sample.csv"
rng = np.random.default_rng(7)
df = pd.read_csv(SRC)

def top_cat(v):
    try:
        s = ast.literal_eval(v)[0]
    except Exception:
        s = str(v)
    return s.split(">>")[0].strip().strip('["')

df["Category"] = df["product_category_tree"].apply(top_cat)
df["Price"] = pd.to_numeric(df["discounted_price"], errors="coerce").fillna(
              pd.to_numeric(df["retail_price"], errors="coerce"))
df = df.dropna(subset=["Price", "product_name"])
df = df[df["Price"] > 0]
df["brand"] = df["brand"].fillna("Unbranded")

zones = df["Category"].value_counts().head(6).index.tolist()          # 6 biggest real categories -> Zones A-F
codes = "ABCDEF"
RACKS, BAYS, LEVELS, CAP = 4, 10, 5, 40
today = dt.date.today()
rows = []
for zc, cat in zip(codes, zones):
    pool = df[df["Category"] == cat].reset_index(drop=True)
    for r in range(1, RACKS + 1):
        for b in range(1, BAYS + 1):
            for l in range(1, LEVELS + 1):
                bid = f"{zc}-R{r:02d}-B{b:02d}-L{l}"
                x = rng.random()
                p = pool.iloc[rng.integers(len(pool))]
                if x < 0.07:
                    qty, status = 0, "Empty"
                else:
                    qty = int(rng.integers(2, CAP + 1))
                    status = "Blocked" if x < 0.11 else ("Low Stock" if qty <= 8 else ("Overstock" if qty >= 36 else "Optimal"))
                days = int(rng.integers(1, 121)) if qty else 0
                rows.append({
                    "Bin_ID": bid, "Zone": zc, "Zone_Name": cat, "Rack": r, "Bay": b, "Level": l,
                    "SKU": p["pid"] if qty else "", "Product_Name": p["product_name"][:60] if qty else "",
                    "Brand": p["brand"] if qty else "", "Category": cat if qty else "",
                    "Qty": qty, "Bin_Capacity": CAP, "Fill_Pct": round(qty / CAP * 100, 1), "Bin_Status": status,
                    "Unit_Price_INR": float(p["Price"]) if qty else 0, "Stock_Value_INR": float(p["Price"]) * qty if qty else 0,
                    "Velocity_Class": rng.choice(["A-Fast", "B-Medium", "C-Slow"], p=[.25, .4, .35]) if qty else "",
                    "Days_In_Storage": days,
                    "Inbound_Date": (today - dt.timedelta(days=days)).isoformat() if qty else "",
                })
out = pd.DataFrame(rows)
out.to_csv("Flipkart_Warehouse_Bins_REAL_SKUS.csv", index=False)
print("Zones:", dict(zip(codes, zones)))
print("Rows:", len(out))