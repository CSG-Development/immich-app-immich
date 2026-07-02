import time

_start = time.perf_counter()


def reset_timer() -> None:
    global _start
    _start = time.perf_counter()


def elapsed_ms() -> float:
    return (time.perf_counter() - _start) * 1000
