# Import the necessary modules
import numpy as np
import matplotlib.pyplot as plt
from sklearn.datasets import load_iris
from sklearn import svm

df = load_iris(as_frame=True).frame
X = df[["sepal length (cm)","sepal width (cm)"]]

# Define the model and set the nu parameter
model = svm.OneClassSVM(nu=0.05)

# Fit the model to the data
model.fit(X)

# Calculate the outlier scores for each point
scores = model.decision_function(X)

# Identify the points with the highest outlier scores
outliers = np.argwhere(scores < np.percentile(scores, 5))

# Plot anomly
colors=["green","red"]

for i in range(len(X)):
    if i not in outliers:
        plt.scatter(X.iloc[i,0], X.iloc[i,1], color=colors[0]) # Not Anomly
    else:
        plt.scatter(X.iloc[i,0], X.iloc[i,1], color=colors[1]) # Anomly
plt.xlabel("sepal length (cm)", fontsize=13)
plt.ylabel("sepal width (cm)", fontsize=13)
plt.title("Anomly by One-class Support Vector Machines", fontsize=16)

plt.savefig("one_class_svm_anomaly_detection.png", dpi=150, bbox_inches="tight")

