import matplotlib.pyplot as plt
from matplotlib.dates import DateFormatter
import ruptures as rpt
import datetime
import itertools

def display(
    signal,
    true_chg_pts,
    xd,
    computed_chg_pts=None,
    computed_chg_pts_color="k",
    computed_chg_pts_linewidth=3,
    computed_chg_pts_linestyle="--",
    computed_chg_pts_alpha=1.0,
    **kwargs
):
    n_samples, n_features = signal.shape

    fig, axe = plt.subplots()
    for j in range(n_features):
        axe.plot(dates, [signal[i][j] for i in range(n_samples)], label=f"Value {j + 1}")
    plt.legend()

    ## Rotate date labels automatically
    fig.autofmt_xdate()

    if computed_chg_pts is not None:
        for bkp in computed_chg_pts:
            if bkp != 0 and bkp < n_samples:
                axe.axvline(
                    #x=bkp - 0.5,
                    x=dates[bkp],
                    color=computed_chg_pts_color,
                    linewidth=computed_chg_pts_linewidth,
                    linestyle=computed_chg_pts_linestyle,
                    alpha=computed_chg_pts_alpha,
                )

    return fig, axe

# generate signal
n_samples, dim, sigma = 100, 3, 4
n_bkps = 4  # number of breakpoints
signal, bkps = rpt.pw_constant(n_samples, dim, n_bkps, noise_std=sigma)

date_generator = (datetime.datetime.today() - datetime.timedelta(days=i) for i in itertools.count())
dates = list(itertools.islice(date_generator, 100))

# detection
algo = rpt.Pelt(model="rbf").fit(signal)
result = algo.predict(pen=1)

bkps=[]

display(signal, bkps, dates, result)
plt.savefig("ruptures_example_5.png", dpi=150, bbox_inches="tight")
