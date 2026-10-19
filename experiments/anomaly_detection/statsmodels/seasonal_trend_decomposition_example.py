#
# Seasonal-Trend decomposition using LOESS Example
# Source: https://blog.jetbrains.com/pycharm/2025/01/anomaly-detection-in-time-series/
#

import pandas as pd
from statsmodels.tsa.seasonal import STL
import matplotlib.pyplot as plt

df = pd.read_csv("hive_17.csv", sep=";")
df = df.dropna()

stl = STL(df["T17"], period=24, robust=True) 
result = stl.fit()

result.plot()
plt.savefig("hive_17_stl.png", dpi=150, bbox_inches="tight")
plt.clf()

result.resid.plot.hist()
plt.savefig("hive_17_hist.png", dpi=150, bbox_inches="tight")
plt.clf()

threshold = 5
anomalies_filter = result.resid.apply(lambda x: True if abs(x) > threshold else False)
anomalies = df["T17"][anomalies_filter]

plt.figure(figsize=(14, 8))
plt.scatter(x=anomalies.index, y=anomalies, color="red", label="Anomalies")
plt.plot(df.index, df['T17'], color='blue')
plt.title('Temperatures in Hive 17')
plt.xlabel('Hours')
plt.ylabel('Temperature')
plt.legend()

plt.savefig("hive_17_anomalies.png", dpi=150, bbox_inches="tight")
