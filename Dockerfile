# Multi-stage build for NVIDIA Jetson DeepStream Docker Framework
# Fixed base image with explicit tag for CI compliance
ARG JETPACK_VERSION=r35.4.1

FROM nvcr.io/nvidia/l4t-jetpack:${JETPACK_VERSION} AS base

ARG OPENCV_VERSION=4.8.0
ARG CUDA_ARCH_BIN=7.2
ARG PYTORCH_VERSION=2.1.0a0+41361538.nv23.06
ARG TORCHVISION_VERSION=0.16.0a0+0631c26.nv23.06

# Labels for container metadata (OCI standards)
LABEL org.opencontainers.image.title="NVIDIA Jetson DeepStream Container"
LABEL org.opencontainers.image.description="Advanced containerized environment for Edge AI and Computer Vision on Jetson devices"
LABEL org.opencontainers.image.vendor="NVIDIA"
LABEL org.opencontainers.image.version="1.0"
LABEL org.opencontainers.image.url="https://github.com/Facadedevil/Nvidia-universal-docker"
LABEL org.opencontainers.image.maintainer="SAMIR Singh"

# Set environment variables
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    DEBIAN_FRONTEND=noninteractive \
    TZ=UTC

# Install system dependencies - organized by purpose
# Pin versions and consolidate RUN commands to reduce layers
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Build tools
    build-essential=12.8ubuntu1.1 \
    cmake=3.16.3-1ubuntu1 \
    pkg-config=0.29.1-0ubuntu4 \
    wget=1.20.3-1ubuntu2 \
    unzip=6.0-25ubuntu1.1 \
    yasm=1.3.0-2ubuntu1 \
    checkinstall=1.6.2+git20170426.0ae2d32-1 \
    git=1:2.25.1-1ubuntu3.11 \
    gfortran=4:9.3.0-1ubuntu2 \
    # Python
    python3-dev=3.8.2-0ubuntu2 \
    python3-pip=20.0.2-5ubuntu1.8 \
    python3-numpy=1:1.17.4-5ubuntu3 \
    python3-tk=3.8.2-0ubuntu2 \
    tk-dev=8.6.9+1 \
    python3-pil.imagetk=7.0.0-4ubuntu0.7 \
    # Libraries
    libopenmpi-dev=4.0.3-0ubuntu1 \
    libopenblas-base=0.3.8+ds-1ubuntu0.20.04.1 \
    libomp-dev=1:10.0-50~exp1 \
    libglib2.0-0=2.64.6-1~ubuntu20.04.4 \
    libsm6=2:1.2.3-1 \
    libxext6=2:1.3.4-0ubuntu1 \
    libxrender-dev=1:0.9.10-1 \
    libgl1-mesa-glx=21.2.6-0ubuntu0.1~20.04.2 \
    libreadline-dev=8.0-4 \
    libncurses5-dev=6.2-0ubuntu2 \
    libncursesw5-dev=6.2-0ubuntu2 \
    # X11 
    x11-apps=7.7+8 \
    xauth=1:1.1-0ubuntu1 \
    xterm=353-1ubuntu1.20.04.2 \
    # GStreamer
    libgstreamer1.0-dev=1.16.2-2 \
    libgstreamer-plugins-base1.0-dev=1.16.2-4ubuntu0.1 \
    libgstreamer-plugins-good1.0-dev=1.16.2-1ubuntu2.1 \
    libgstreamer-plugins-bad1.0-dev=1.16.2-2.1ubuntu1 \
    gstreamer1.0-plugins-base=1.16.2-4ubuntu0.1 \
    gstreamer1.0-plugins-good=1.16.2-1ubuntu2.1 \
    gstreamer1.0-plugins-bad=1.16.2-2.1ubuntu1 \
    gstreamer1.0-plugins-ugly=1.16.2-2 \
    gstreamer1.0-libav=1.16.2-2 \
    gstreamer1.0-tools=1.16.2-2 \
    libgstrtspserver-1.0-0=1.16.2-1 \
    # Video processing
    libavcodec-dev=7:4.2.4-1ubuntu0.1 \
    libavformat-dev=7:4.2.4-1ubuntu0.1 \
    libswscale-dev=7:4.2.4-1ubuntu0.1 \
    libv4l-dev=1.18.0-2build1 \
    libxvidcore-dev=2:1.3.7-1 \
    libx264-dev=2:0.155.2917+git0a84d98-2 \
    libjpeg-dev=8c-2ubuntu8 \
    libpng-dev=1.6.37-2 \
    libtiff-dev=4.1.0+git191117-2ubuntu0.20.04.8 \
    ffmpeg=7:4.2.4-1ubuntu0.1 \
    # Additional libraries
    libtbb-dev=2020.0-2 \
    libtbb2=2020.0-2 \
    libdc1394-22-dev=2.2.5-2.1 \
    libjansson4=2.12-1build1 \
    libjsoncpp-dev=1.7.4-3.1ubuntu2 \
    libssl-dev=1.1.1f-1ubuntu2.19 \
    libyaml-cpp-dev=0.6.2-4ubuntu1 \
    # Health monitoring tools
    htop=2.2.0-2build1 \
    pciutils=1:3.6.4-1 \
    lm-sensors=1:3.6.0-2ubuntu1 \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: Build OpenCV with CUDA
FROM base AS opencv-builder

ARG OPENCV_VERSION
ARG CUDA_ARCH_BIN

WORKDIR /opt

# Clone and build OpenCV with CUDA support
RUN git clone --depth 1 --branch "${OPENCV_VERSION}" https://github.com/opencv/opencv.git && \
    git clone --depth 1 --branch "${OPENCV_VERSION}" https://github.com/opencv/opencv_contrib.git

WORKDIR /opt/opencv/build

RUN cmake \
      -D CMAKE_BUILD_TYPE=RELEASE \
      -D CMAKE_INSTALL_PREFIX=/usr/local \
      -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/modules \
      -D PYTHON3_EXECUTABLE=/usr/bin/python3 \
      -D WITH_CUDA=ON \
      -D WITH_CUDNN=ON \
      -D OPENCV_DNN_CUDA=ON \
      -D WITH_NVCUVID=ON \
      -D WITH_NVENC=ON \
      -D CUDA_ARCH_BIN="${CUDA_ARCH_BIN}" \
      -D ENABLE_FAST_MATH=1 \
      -D CUDA_FAST_MATH=1 \
      -D WITH_CUBLAS=1 \
      -D WITH_TBB=ON \
      -D WITH_GSTREAMER=ON \
      -D WITH_LIBV4L=ON \
      -D BUILD_opencv_python3=ON \
      -D BUILD_opencv_python2=OFF \
      -D BUILD_TESTS=OFF \
      -D BUILD_PERF_TESTS=OFF \
      -D BUILD_EXAMPLES=OFF \
      -D OPENCV_ENABLE_NONFREE=ON \
      .. && \
    make -j"$(nproc)" && \
    make install && \
    ldconfig

# Stage 3: Build FFmpeg with CUDA and NVENC support
FROM base AS ffmpeg-builder

WORKDIR /opt

# Install FFmpeg build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    nasm=2.14.02-1 \
    libx264-dev=2:0.155.2917+git0a84d98-2 \
    libx265-dev=3.2.1-1build1 \
    libnuma-dev=2.0.12-1 \
    libvpx-dev=1.8.2-1build1 \
    libfdk-aac-dev=2.0.1-1 \
    libmp3lame-dev=3.100-3 \
    libopus-dev=1.3.1-0ubuntu1 \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git

WORKDIR /opt/ffmpeg

RUN ./configure \
      --enable-nonfree \
      --enable-gpl \
      --enable-libx264 \
      --enable-libx265 \
      --enable-cuda \
      --enable-cuvid \
      --enable-nvenc \
      --enable-libnpp \
      --extra-cflags="-I/usr/local/cuda/include" \
      --extra-ldflags="-L/usr/local/cuda/lib64" \
      --prefix=/usr/local && \
    make -j"$(nproc)" && \
    make install

# Stage 4: Final image
FROM base AS final

ARG PYTORCH_VERSION
ARG TORCHVISION_VERSION

# Copy OpenCV from builder stage
COPY --from=opencv-builder /usr/local/lib /usr/local/lib
COPY --from=opencv-builder /usr/local/include /usr/local/include
COPY --from=opencv-builder /usr/local/bin /usr/local/bin
COPY --from=opencv-builder /usr/local/share/opencv4 /usr/local/share/opencv4

# Copy FFmpeg with NVIDIA capabilities
COPY --from=ffmpeg-builder /usr/local/bin /usr/local/bin
COPY --from=ffmpeg-builder /usr/local/lib /usr/local/lib
COPY --from=ffmpeg-builder /usr/local/include /usr/local/include
COPY --from=ffmpeg-builder /usr/local/share/ffmpeg /usr/local/share/ffmpeg

# Set CUDA and DeepStream environment variables
ENV CUDA_HOME=/usr/local/cuda \
    PATH=/usr/local/cuda/bin:/usr/local/bin:$PATH \
    LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/lib/aarch64-linux-gnu:/usr/lib/aarch64-linux-gnu/tegra:/usr/local/lib:$LD_LIBRARY_PATH \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics,video \
    TENSORRT_ROOT=/usr/lib/aarch64-linux-gnu \
    TENSORRT_INCLUDE_DIR=/usr/include/aarch64-linux-gnu \
    PYTHONPATH=/usr/local/lib/python3.8/dist-packages:$PYTHONPATH \
    # Additional environment variables for adaptable hardware configuration
    CUDA_ARCH_PTX=compute_53,compute_62,compute_72,compute_87 \
    # Allow fallback to lower precision when needed for performance
    TRT_FP16_ENABLED=true \
    # Jetson-specific variables
    JETSON_MULTITHREADING=true

# Install Python packages
COPY requirements.txt /tmp/requirements.txt
RUN python3 -m pip install --upgrade pip==23.0.1 setuptools==67.6.1 wheel==0.40.0 && \
    # Install PyTorch and torchvision for Jetson
    python3 -m pip install --no-cache-dir \
        --extra-index-url https://developer.download.nvidia.com/compute/redist/jp/v511 \
        nvidia-pyindex==1.0.9 \
        "torch==${PYTORCH_VERSION}" \
        "torchvision==${TORCHVISION_VERSION}" && \
    # Install TensorFlow with GPU support for Jetson
    python3 -m pip install --no-cache-dir \
        --extra-index-url https://developer.download.nvidia.com/compute/redist/jp/v511 \
        tensorflow==2.11.0+nv23.01 && \
    # Install ONNX Runtime with GPU support
    python3 -m pip install --no-cache-dir onnxruntime-gpu==1.15.1 && \
    # Install TensorFlow Lite with GPU support
    python3 -m pip install --no-cache-dir tflite-runtime==2.14.0 && \
    # Install other Python packages from requirements.txt
    python3 -m pip install --no-cache-dir -r /tmp/requirements.txt && \
    # Install additional ML dependencies with CUDA support
    python3 -m pip install --no-cache-dir \
        cupy-cuda11x==11.6.0 \
        numba==0.56.4 \
        pycuda==2023.1 \
        ultralytics==8.0.196 && \
    # Cleanup to reduce image size
    rm -rf /tmp/requirements.txt

# Set up display environment variables
ENV DISPLAY=:0 \
    QT_X11_NO_MITSHM=1 \
    XDG_RUNTIME_DIR=/tmp/runtime-user

# Create a non-root user
RUN useradd -m -s /bin/bash user && \
    mkdir -p /workspace && \
    chown -R user:user /workspace

# Create directories for mounting
RUN mkdir -p /opt/nvidia/deepstream /workspace/src /workspace/models /workspace/config /workspace/logs /workspace/custom && \
    chown -R user:user /workspace

# Setup symbolic links for DeepStream that will be mounted from host
RUN mkdir -p /opt/nvidia/deepstream/deepstream-6.2/lib && \
    touch /opt/nvidia/deepstream/deepstream-6.2/lib/libnvbufsurface.so && \
    touch /opt/nvidia/deepstream/deepstream-6.2/lib/libnvbufsurftransform.so

# Create cache cleanup script using printf instead of echo
RUN printf '#!/bin/bash\napt-get clean\nrm -rf /var/lib/apt/lists/*\nfind /tmp -type f -delete\nfind /var/tmp -type f -delete\nrm -rf ~/.cache/pip\n' > /usr/local/bin/cleanup-cache && \
    chmod +x /usr/local/bin/cleanup-cache

# Set working directory
WORKDIR /workspace

# Docker health check for Jetson devices
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD test -f /sys/devices/gpu.0/load || exit 1

# Add entrypoint script
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Cleanup to reduce image size
RUN ldconfig && \
    /usr/local/bin/cleanup-cache

ENTRYPOINT ["/entrypoint.sh"]
CMD ["/bin/bash"]