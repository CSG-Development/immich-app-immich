import matplotlib.pyplot as plt
import ruptures as rpt

# generate signal
n_samples, dim, sigma = 100, 3, 4
n_bkps = 4  # number of breakpoints
signal, bkps = rpt.pw_constant(n_samples, dim, n_bkps, noise_std=sigma)

# detection
algo = rpt.Pelt(model="rbf").fit(signal)
result = algo.predict(pen=1)

# display
rpt.display(signal, bkps, result)
plt.savefig("ruptures_example_1.png", dpi=150, bbox_inches="tight")
