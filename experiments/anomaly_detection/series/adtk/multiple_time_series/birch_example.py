import numpy as np
import pandas as pd
from numpy import sqrt
import matplotlib.pyplot as plt
from sklearn.cluster import DBSCAN
from adtk.detector import MinClusterDetector
from sklearn.cluster import Birch
from adtk.visualization import plot

df = pd.read_csv("sample_data/birch.csv")
df.head()

df["_time"] = pd.to_datetime(df["_time"].astype(str))
df = df.drop(columns=["result", "table"])
df = df.set_index("_time")
df.head()

from adtk.detector import MinClusterDetector
from sklearn.cluster import Birch
from adtk.visualization import plot
min_cluster_detector = MinClusterDetector(Birch(n_clusters=10))
anomalies = min_cluster_detector.fit_detect(df)


print(df)
print(anomalies)

#plot(df, anomaly=anomalies, ts_linewidth=1, ts_markersize=3, anomaly_color='red', anomaly_alpha=0.3, curve_group='all')

#plot(df[520:600], anomaly=anomalies[520:600], ts_linewidth=1, ts_markersize=3, anomaly_color='red', anomaly_alpha=0.3, curve_group='all')