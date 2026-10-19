import pandas as pd
from adtk.detector import MinClusterDetector
from sklearn.cluster import KMeans
from adtk.visualization import plot

df = pd.read_csv("sample_data/kmeans.csv")
df.head()

df["_time"] = pd.to_datetime(df["_time"].astype(str))
df = df.drop(columns=["result", "table"])
df = df.set_index("_time")
df.head()

min_cluster_detector = MinClusterDetector(KMeans(n_clusters=12))
anomalies = min_cluster_detector.fit_detect(df)
print(anomalies)
#plot(df, anomaly=anomalies, ts_linewidth=1, ts_markersize=3, anomaly_color='red', anomaly_alpha=0.3, curve_group='all');

