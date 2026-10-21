export OMP_NUM_THREADS=1        # OpenMP threads (used by numpy, torch)
export MKL_NUM_THREADS=1        # Intel MKL threads (used by numpy, scipy)
export OPENBLAS_NUM_THREADS=1   # OpenBLAS threads
export NUMEXPR_NUM_THREADS=1    # numexpr threads
export VECLIB_MAXIMUM_THREADS=1 # macOS Accelerate framework
export TORCH_NUM_THREADS=1      # PyTorch threads (alternative to API)

python3 performance_test_buffalo_l_1.py
