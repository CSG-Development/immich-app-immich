import pandas as pd
import matplotlib.pyplot as plt

#s = pd.read_csv("sample_data/sample_data.csv")
s = pd.read_csv("sample_data/sin.csv")

#s.drop(["label"], axis=1, inplace=True)
s["timestamp"] = pd.to_datetime(s["timestamp"], unit="s")
s = s.set_index("timestamp")
s.head()

#s.plot()

from adtk.data import validate_series
# This functoin will check some common critical issues of time series that may cause problems if anomaly detection is performed without fixing them. The function will automatically fix some of them and raise errors for the others.
s = validate_series(s)

from adtk.detector import SeasonalAD
from adtk.visualization import plot
seasonal_ad = SeasonalAD(c=3.0, side="both")
anomalies = seasonal_ad.fit_detect(s)

anomalies.to_csv("seasonal_anomaly_detection.csv")
#plot(s, anomalies, ts_markersize=1, anomaly_color="red", anomaly_tag="marker", anomaly_markersize=2);