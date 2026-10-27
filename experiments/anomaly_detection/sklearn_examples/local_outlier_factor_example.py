# Import the necessary modules
import numpy as np
import matplotlib.pyplot as plt
from sklearn.datasets import load_iris
from sklearn.neighbors import LocalOutlierFactor

# Load the datasets
df = load_iris(as_frame=True).frame
X = df[["sepal length (cm)","sepal width (cm)"]]

# Define the model and set the number of neighbors
lof = LocalOutlierFactor(n_neighbors=5)

# Fit the model to the data
lof.fit(X)

# Calculate the outlier scores for each point
scores = lof.negative_outlier_factor_

# Identify the points with the highest outlier scores
outliers = np.argwhere(scores > np.percentile(scores, 95))

# Plot anomly
colors=["green","red"]

for i in range(len(X)):
    if i not in outliers:
        plt.scatter(X.iloc[i,0], X.iloc[i,1], color=colors[0]) # Not Anomly
    else:
        plt.scatter(X.iloc[i,0], X.iloc[i,1], color=colors[1]) # Anomly
plt.xlabel("sepal length (cm)", fontsize=13)
plt.ylabel("sepal width (cm)", fontsize=13)
plt.title("Anomly by Local Outlier Factor", fontsize=16)

plt.savefig("local_outlier_factor_anomaly_detection.png", dpi=150, bbox_inches="tight")
