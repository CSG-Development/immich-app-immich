import numpy as np
import matplotlib.pylab as plt
import ruptures as rpt
from numpy.random import RandomState

# creation of data
signal = 2.0*np.ones((200)) 
signal2 = -3.0*np.ones((200)) 
signal3 = np.zeros((200)) 
signal4 = 1.0*np.ones((200)) 
signal = np.cumsum(np.concatenate((signal, signal2, signal3, signal4), axis = None))

# Add noise
rd = RandomState(123)
signal = signal + rd.normal(scale=20.0, size=800)

# Run ruptures algo
# 1. Choose Dynp to run the most accurate (and costly) algorythm
# 2. Choose the "clinear" cost model
algo = rpt.detection.Dynp(model="clinear",min_size=1, jump=1).fit(signal)
bkps = algo.predict(n_bkps=3)

figure, axs = rpt.display(signal, [200, 400, 600, 800], bkps)
figure.savefig("ruptures_example_4.png", dpi=150, bbox_inches="tight")

