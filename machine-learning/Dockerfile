ARG DEVICE=cpu

# =========================
# BUILDER STAGES
# =========================

FROM dhi.io/python:3.11-debian13-dev AS builder-cpu

ARG DEVICE
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    VIRTUAL_ENV=/opt/venv

# Install system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        g++ \
        build-essential \
        && rm -rf /var/lib/apt/lists/*

# uv package
COPY --from=ghcr.io/astral-sh/uv:0.8.15@sha256:a5727064a0de127bdb7c9d3c1383f3a9ac307d9f2d8a391edc7896c54289ced0 /uv /uvx /bin/

# Python dependencies installation via uv
RUN --mount=type=cache,target=/root/.cache/uv \
    --mount=type=bind,source=uv.lock,target=uv.lock \
    --mount=type=bind,source=pyproject.toml,target=pyproject.toml \
    uv sync --frozen --extra ${DEVICE} --no-dev --no-editable \
        --no-install-project --compile-bytecode --no-progress \
        --active --link-mode copy

# -------------------------
# Optional builder stages
# -------------------------

FROM builder-cpu AS builder-openvino
FROM builder-cpu AS builder-cuda
FROM builder-cpu AS builder-armnn
FROM builder-cpu AS builder-rknn

# ROCm builder
FROM rocm/dev-ubuntu-22.04:6.4.3-complete AS builder-rocm

# =========================
# SELECT BUILDER
# =========================

FROM builder-${DEVICE} AS builder

# =========================
# RUNTIME STAGES
# =========================

# CPU runtime
FROM dhi.io/python:3.11-debian13-dev AS prod-cpu

# OpenVINO runtime
FROM dhi.io/python:3.11-debian13-dev AS prod-openvino

RUN apt-get update && \
    apt-get install --no-install-recommends -yqq \
        ocl-icd-libopencl1 wget && \
    rm -rf /var/lib/apt/lists/*

# CUDA runtime
FROM nvidia/cuda:12.2.2-runtime-ubuntu22.04 AS prod-cuda

RUN apt-get update && \
    apt-get install --no-install-recommends -yqq \
        libcudnn9-cuda-12 && \
    rm -rf /var/lib/apt/lists/*

# ROCm runtime
FROM rocm/dev-ubuntu-22.04:6.4.3-complete AS prod-rocm

# ARMNN runtime
FROM prod-cpu AS prod-armnn

ENV LD_LIBRARY_PATH=/opt/armnn

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ocl-icd-libopencl1 \
        mesa-opencl-icd \
        libgomp1 && \
    rm -rf /var/lib/apt/lists/*

COPY --from=builder-armnn /opt/armnn /opt/armnn

# RKNN runtime
FROM prod-cpu AS prod-rknn

# =========================
# FINAL STAGE
# =========================

FROM prod-${DEVICE} AS prod

ARG DEVICE

# Install system packages
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        tini \
        libmimalloc3 \
    && rm -rf /var/lib/apt/lists/*

# Fix mimalloc path
RUN ln -s "/usr/lib/$(arch)-linux-gnu/libmimalloc.so.3" /usr/lib/libmimalloc.so.3

# Preload mimalloc after installation
ENV LD_PRELOAD=/usr/lib/libmimalloc.so.3

# Environment variables
WORKDIR /usr/src
ENV TRANSFORMERS_CACHE=/cache \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONPATH=/usr/src \
    DEVICE=${DEVICE} \
    VIRTUAL_ENV=/opt/venv \
    MACHINE_LEARNING_CACHE_FOLDER=/cache

# Copy Python virtual environment
COPY --from=builder /opt/venv /opt/venv

# Copy code
COPY scripts/healthcheck.py .
COPY immich_ml immich_ml

# Install Python dependencies
RUN python -m ensurepip --upgrade && \
    python -m pip install -r immich_ml/search/requirements.txt

# Preload cache for model files
COPY cache/ /preload-cache

# Entry point
COPY scripts/entrypoint-wrapper.sh /usr/local/bin/entrypoint-wrapper.sh
RUN chmod +x /usr/local/bin/entrypoint-wrapper.sh

ENTRYPOINT ["tini", "--"]
CMD ["/usr/local/bin/entrypoint-wrapper.sh", "python", "-m", "immich_ml"]

HEALTHCHECK CMD python3 healthcheck.py
