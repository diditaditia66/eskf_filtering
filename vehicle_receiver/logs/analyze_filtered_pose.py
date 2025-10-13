import pandas as pd
import numpy as np

df = pd.read_csv("filtered_pose.csv")
print("Rows:", len(df))
print(df.tail())

# Basic stats
if "latency_ms" in df.columns:
    print("\nLatency (ms): min/avg/p95/max =",
          np.min(df["latency_ms"]),
          np.mean(df["latency_ms"]),
          np.percentile(df["latency_ms"], 95),
          np.max(df["latency_ms"]))

# Heading continuity (cek loncatan besar)
hdg = df["heading_deg"].to_numpy()
jump = np.abs(np.diff(hdg))
print("Heading jumps > 45° count:", np.sum(jump > 45))

# (Optional) Simpel plot jika ada matplotlib
try:
    import matplotlib.pyplot as plt
    plt.figure(); plt.plot(df["lon"], df["lat"], marker='.', linestyle='-')
    plt.title("Filtered path"); plt.xlabel("lon"); plt.ylabel("lat"); plt.axis('equal')
    plt.figure(); plt.plot(df["heading_deg"])
    plt.title("Heading (deg)")
    if "latency_ms" in df.columns:
        plt.figure(); plt.plot(df["latency_ms"])
        plt.title("Latency (ms)")
    plt.show()
except Exception as e:
    print("Skip plotting:", e)
