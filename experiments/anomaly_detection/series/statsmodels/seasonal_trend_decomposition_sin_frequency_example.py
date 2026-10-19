#
# Seasonal-Trend decomposition using LOESS Example
#

from math import sin
import pandas as pd
from statsmodels.tsa.seasonal import STL
import matplotlib.pyplot as plt

tv1 = [t for t in range(0,360 * 20, 1)]
vv1 = [sin(3.14159265 / 180.0 * t) for t in tv1]
tv2 = [t for t in range(360 * 20, 360 * 22, 1)]
vv2 = [sin(2.0 * 3.14159265 / 180.0 * t) for t in tv2]
tv3 = [t for t in range(360 * 22, 360 * 25, 1)]
vv3 = [sin(3.14159265 / 180.0 * t) for t in tv3]

tv = tv1 + tv2 + tv3
vv = vv1 + vv2 + vv3
df = pd.DataFrame({"timestamp": tv, "value": vv})

stl = STL(df["value"], period=12, robust=True) 
result = stl.fit()

result.plot()
plt.savefig("sin_frequency_stl.png", dpi=150, bbox_inches="tight")
plt.clf()

result.resid.plot.hist()
plt.savefig("sin_frequency_hist.png", dpi=150, bbox_inches="tight")
plt.clf()

threshold = 0.2
anomalies_filter = result.resid.apply(lambda x: True if abs(x) > threshold else False)
anomalies = df["value"][anomalies_filter]

plt.figure(figsize=(14, 8))
plt.scatter(x=anomalies.index, y=anomalies, color="red", label="Anomalies")
plt.plot(df.index, df['value'], color='blue')
plt.title('Temperature')
plt.xlabel('Timestamp')
plt.ylabel('Value')
plt.legend()

plt.savefig("sin_frequency_anomalies.png", dpi=150, bbox_inches="tight")
