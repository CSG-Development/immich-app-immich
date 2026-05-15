ARG DEVICE=cpu

FROM dhi.io/python:3.11-debian13-dev AS builder-cpu

FROM builder-cpu AS builder-openvino

FROM builder-cpu AS builder-cuda

FROM builder-cpu AS builder-armnn

# renovate: datasource=github-releases depName=ARM-software/armnn
ARG ARMNN_VERSION="v24.05"

ENV ARMNN_PATH=/opt/armnn
COPY ann /opt/ann
RUN mkdir -p /opt/armnn && \
    curl -SL "https://github.com/ARM-software/armnn/releases/download/${ARMNN_VERSION}/ArmNN-linux-aarch64.tar.gz" | tar -zx -C /opt/armnn && \
    cd /opt/ann && \
    sh build.sh

FROM builder-cpu AS builder-rknn

# Warning: 25GiB+ disk space required to pull this image
# TODO: find a way to reduce the image size
FROM rocm/dev-ubuntu-22.04:6.4.3-complete@sha256:1f7e92ca7e3a3785680473329ed1091fc99db3e90fcb3a1688f2933e870ed76b AS builder-rocm

# renovate: datasource=github-releases depName=Microsoft/onnxruntime
ARG ONNXRUNTIME_VERSION="v1.20.1"
WORKDIR /code

RUN apt-get update && apt-get install -y --no-install-recommends wget git python3.10-venv

RUN wget -nv https://github.com/Kitware/CMake/releases/download/v3.30.1/cmake-3.30.1-linux-x86_64.sh && \
    chmod +x cmake-3.30.1-linux-x86_64.sh && \
    mkdir -p /code/cmake && \
    ./cmake-3.30.1-linux-x86_64.sh --skip-license --prefix=/code/cmake && \
    rm cmake-3.30.1-linux-x86_64.sh

ENV PATH=/code/cmake/bin:${PATH}

RUN git clone --single-branch --branch "${ONNXRUNTIME_VERSION}" --recursive \
    https://github.com/Microsoft/onnxruntime onnxruntime

WORKDIR /code/onnxruntime

COPY ./patches/* /tmp/
RUN git apply /tmp/*.patch

RUN /bin/sh ./dockerfiles/scripts/install_common_deps.sh

RUN ./build.sh --allow_running_as_root \
    --config Release \
    --build_wheel \
    --update --build \
    --parallel 17 \
    --skip_tests \
    --use_rocm \
    --rocm_home=/opt/rocm

RUN mv /code/onnxruntime/build/Linux/Release/dist/*.whl /opt/

# =========================================================
# FIX: OpenVINO GPU SAFE BASE (IMPORTANT CHANGE HERE)
# =========================================================

FROM dhi.io/python:3.11-debian13-dev AS prod-openvino

SHELL ["/bin/bash", "-euxo", "pipefail", "-c"]

ENV DEBIAN_FRONTEND=noninteractive

# =========================================================
# Minimal deps (NO X11, NO legacy GPU stack)
# =========================================================

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        wget \
        ocl-icd-libopencl1 \
        libglib2.0-0 \
        libuuid1 \
        libstdc++6 \
        libgcc-s1 && \
    rm -rf /var/lib/apt/lists/*

# =========================================================
# MODERN Intel GPU stack (Level Zero ONLY - FIX)
# =========================================================

RUN mkdir -p /tmp/gpu && cd /tmp/gpu && \
    curl -fLO https://github.com/intel/compute-runtime/releases/download/24.48.31907.7/intel-opencl-icd_24.48.31907.7_amd64.deb && \
    curl -fLO https://github.com/intel/compute-runtime/releases/download/24.48.31907.7/intel-level-zero-gpu_1.6.31907.7_amd64.deb && \
    curl -fLO https://github.com/intel/compute-runtime/releases/download/24.48.31907.7/libigdgmm12_22.5.4_amd64.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        ./libigdgmm12_22.5.4_amd64.deb \
        ./intel-level-zero-gpu_1.6.31907.7_amd64.deb \
        ./intel-opencl-icd_24.48.31907.7_amd64.deb && \
    rm -rf /tmp/gpu /var/lib/apt/lists/*

# =========================================================
# CPU prod base
# =========================================================

FROM dhi.io/python:3.11-debian13-dev AS prod-cpu

ENV LD_PRELOAD=/usr/lib/libmimalloc.so.3

# =========================================================
# CUDA / ROCM untouched (no changes needed)
# =========================================================

FROM nvidia/cuda:12.2.2-runtime-ubuntu22.04@sha256:94c1577b2cd9dd6c0312dc04dff9cb2fdce2b268018abc3d7c2dbcacf1155000 AS prod-cuda

ENV LD_PRELOAD=/usr/lib/libmimalloc.so.3

RUN apt-get update && \
    apt-get install --no-install-recommends -yqq libcudnn9-cuda-12 && \
    rm -rf /var/lib/apt/lists/*

FROM rocm/dev-ubuntu-22.04:6.4.3-complete@sha256:1f7e92ca7e3a3785680473329ed1091fc99db3e90fcb3a1688f2933e870ed76b AS prod-rocm

# =========================================================
# ARMNN (unchanged except safer mkdir)
# =========================================================

FROM prod-cpu AS prod-armnn

ENV LD_LIBRARY_PATH=/opt/armnn \
    LD_PRELOAD=/usr/lib/libmimalloc.so.3

RUN apt-get update && apt-get install -y --no-install-recommends \
    ocl-icd-libopencl1 mesa-opencl-icd libgomp1 && \
    rm -rf /var/lib/apt/lists/* && \
    mkdir -p /etc/OpenCL/vendors && \
    echo "/usr/lib/libmali.so" > /etc/OpenCL/vendors/mali.icd

COPY --from=builder-armnn \
    /opt/armnn/libarmnn.so.?? \
    /opt/armnn/libarmnnOnnxParser.so.?? \
    /opt/armnn/libarmnnDeserializer.so.?? \
    /opt/armnn/libarmnnTfLiteParser.so.?? \
    /opt/armnn/libprotobuf.so.?.??.?.? \
    /opt/ann/libann.s[o] \
    /opt/ann/build.sh \
    /opt/armnn/

# =========================================================
# RKNN (unchanged)
# =========================================================

FROM prod-cpu AS prod-rknn

ARG RKNN_TOOLKIT_VERSION="v2.3.0"

ENV LD_PRELOAD=/usr/lib/libmimalloc.so.3

ADD --checksum=sha256:73993ed4b440460825f21611731564503cc1d5a0c123746477da6cd574f34885 \
    "https://github.com/airockchip/rknn-toolkit2/raw/refs/tags/${RKNN_TOOLKIT_VERSION}/rknpu2/runtime/Linux/librknn_api/aarch64/librknnrt.so" \
    /usr/lib/

# =========================================================
# FINAL IMAGE
# =========================================================

ARG DEVICE
FROM prod-${DEVICE} AS prod

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        tini \
        $(if ! [ "$DEVICE" = "openvino" ] && ! [ "$DEVICE" = "rocm" ]; then echo "libmimalloc3"; fi) && \
    rm -rf /var/lib/apt/lists/*

RUN ln -sf "/usr/lib/$(arch)-linux-gnu/libmimalloc.so.3" /usr/lib/libmimalloc.so.3

WORKDIR /usr/src

ENV TRANSFORMERS_CACHE=/cache \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    PYTHONPATH=/usr/src \
    DEVICE=${DEVICE} \
    VIRTUAL_ENV=/opt/venv \
    MACHINE_LEARNING_CACHE_FOLDER=/cache

# prevent core dumps
RUN echo "hard core 0" >> /etc/security/limits.conf && \
    echo "fs.suid_dumpable 0" >> /etc/sysctl.conf && \
    echo 'ulimit -S -c 0 > /dev/null 2>&1' >> /etc/profile

COPY --from=builder /opt/venv /opt/venv
COPY scripts/healthcheck.py .
COPY immich_ml immich_ml

RUN python -m ensurepip --upgrade
RUN python -m pip install -r immich_ml/search/requirements.txt

# --- Ensure preloaded model cache persists across runtime ---
# Store a safe copy of preloaded model files
COPY cache/ /cache

ARG BUILD_ID
ARG BUILD_IMAGE
ARG BUILD_SOURCE_REF
ARG BUILD_SOURCE_COMMIT

ENV IMMICH_BUILD=${BUILD_ID}
ENV IMMICH_BUILD_URL=https://github.com/immich-app/immich/actions/runs/${BUILD_ID}
ENV IMMICH_BUILD_IMAGE=${BUILD_IMAGE}
ENV IMMICH_BUILD_IMAGE_URL=https://github.com/immich-app/immich/pkgs/container/immich-machine-learning
ENV IMMICH_REPOSITORY=immich-app/immich
ENV IMMICH_REPOSITORY_URL=https://github.com/immich-app/immich
ENV IMMICH_SOURCE_REF=${BUILD_SOURCE_REF}
ENV IMMICH_SOURCE_COMMIT=${BUILD_SOURCE_COMMIT}
ENV IMMICH_SOURCE_URL=https://github.com/immich-app/immich/commit/${BUILD_SOURCE_COMMIT}

ENTRYPOINT ["tini", "--"]
CMD ["python", "-m", "immich_ml"]

HEALTHCHECK CMD python3 healthcheck.py
