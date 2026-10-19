import numpy as np
import pandas as pd
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler

# Load the data
data = pd.read_csv("standard_scaler_with_isolation_forest_example_logs_2.csv")

# Normalize the feature data
scaler = StandardScaler()
data_scaled = scaler.fit_transform(data)

# Train the model
model = IsolationForest(contamination=0.07)  # The contamination parameter is used to control the proportion of outliers in the dataset
model.fit(data_scaled)

# Predict the anomalies in the data
anomalies = model.predict(data_scaled)

data["Normality"] = ["True" if a == 1 else "False" for a in anomalies]
data.to_csv("standard_scaler_with_isolation_forest_example_processed_logs_2.csv", index=False)
