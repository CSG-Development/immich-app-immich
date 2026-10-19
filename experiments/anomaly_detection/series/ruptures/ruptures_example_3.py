import matplotlib.pyplot as plt  # for display purposes
from numpy.random import RandomState
import numpy as np
import ruptures as rpt

# Create dummy piecewise linear signal with discontinuity at change points 
x = np.arange(1000)
signal = 1.0 + 1.0*x
signal2 = -2.0 + 8.0*x
signal3 = -4.0 - 2.0*x
signal4 = 2.0*np.ones((1000)) 
signal[200:400] = signal2[200:400]
signal[400:600] = signal3[400:600]
signal[600:] = signal4[600:]

# Add noise
rd = RandomState(1234567890)
signal = signal + rd.normal(scale=200.0, size=1000)

# Run ruptures algo
# 1. Choose Dynp to run the most accurate (and costly) algorythm
# 2. Choose the "linear" cost model
# 3. Stack `signal` with `x`, `CostLinear` needs it to run the linear regressions
algo = rpt.detection.Dynp(model="linear",min_size=1, jump=1).fit(np.column_stack((signal.reshape(-1, 1), x)))
bkps = algo.predict(n_bkps=3)

# Display
figure, axs = rpt.display(signal, [200, 400, 600, 1000], bkps)
figure.savefig("ruptures_example_3.png", dpi=150, bbox_inches="tight")
