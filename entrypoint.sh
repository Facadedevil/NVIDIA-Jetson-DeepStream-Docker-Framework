#!/bin/bash
set -euo pipefail

# Terminal colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        INFO)
            echo -e "${GREEN}[INFO]${NC} ${timestamp} - $message"
            ;;
        WARN)
            echo -e "${YELLOW}[WARN]${NC} ${timestamp} - $message"
            ;;
        ERROR)
            echo -e "${RED}[ERROR]${NC} ${timestamp} - $message"
            ;;
        *)
            echo -e "${BLUE}[$level]${NC} ${timestamp} - $message"
            ;;
    esac
}

check_gpu() {
    log "INFO" "Checking Jetson GPU status..."
    
    # For Jetson, check if the tegra_stats file exists
    if [ ! -f "/sys/devices/gpu.0/load" ]; then
        log "ERROR" "Jetson GPU is not accessible. Please check your device mappings."
        return 1
    fi
    
    # Get GPU information the Jetson way
    local soc_family
    local jetson_model
    soc_family=$(cat /proc/device-tree/compatible 2>/dev/null | tr '\0' '\n' | grep -m 1 "nvidia," || echo "Unknown")
    jetson_model=$(cat /proc/device-tree/model 2>/dev/null | tr '\0' ' ' || echo "Unknown")
    log "INFO" "Jetson Device: ${jetson_model} (${soc_family})"
    
    # Detect CUDA architecture based on Jetson model
    # Default CUDA arch
    local cuda_arch="7.2"
    
    # Check for specific Jetson models
    if echo "$jetson_model" | grep -q "Orin"; then
        if echo "$jetson_model" | grep -q "NX"; then
            # Orin NX uses CUDA architecture 8.7
            cuda_arch="8.7"
            log "INFO" "Detected Jetson Orin NX device, setting CUDA_ARCH_BIN to ${cuda_arch}"
        elif echo "$jetson_model" | grep -q "Nano"; then
            # Orin Nano also uses CUDA architecture 8.7
            cuda_arch="8.7"
            log "INFO" "Detected Jetson Orin Nano device, setting CUDA_ARCH_BIN to ${cuda_arch}"
        elif echo "$jetson_model" | grep -q "Super"; then
            # Orin Super also uses CUDA architecture 8.7
            cuda_arch="8.7"
            log "INFO" "Detected Jetson Orin Super device, setting CUDA_ARCH_BIN to ${cuda_arch}"
        else
            # Other Orin variants use CUDA architecture 8.7
            cuda_arch="8.7"
            log "INFO" "Detected Jetson Orin device, setting CUDA_ARCH_BIN to ${cuda_arch}"
        fi
    elif echo "$jetson_model" | grep -q "AGX Xavier"; then
        # AGX Xavier uses CUDA architecture 7.2
        cuda_arch="7.2"
        log "INFO" "Detected Jetson AGX Xavier device, setting CUDA_ARCH_BIN to ${cuda_arch}"
    elif echo "$jetson_model" | grep -q "Xavier"; then
        # Xavier NX uses CUDA architecture 7.2
        cuda_arch="7.2"
        log "INFO" "Detected Jetson Xavier device, setting CUDA_ARCH_BIN to ${cuda_arch}"
    elif echo "$jetson_model" | grep -q "Nano"; then
        # Nano family uses CUDA architecture 5.3
        cuda_arch="5.3"
        log "INFO" "Detected Jetson Nano device, setting CUDA_ARCH_BIN to ${cuda_arch}"
    elif echo "$jetson_model" | grep -q "TX"; then
        # TX2 family uses CUDA architecture 6.2
        cuda_arch="6.2"
        log "INFO" "Detected Jetson TX2 device, setting CUDA_ARCH_BIN to ${cuda_arch}"
    else
        # Default arch if unable to determine
        log "WARN" "Could not determine specific Jetson model, using default CUDA_ARCH_BIN=${cuda_arch}"
    fi
    
    # Export the detected architecture for use in the container
    export CUDA_ARCH_BIN="$cuda_arch"
    export JETSON_MODEL="$jetson_model"
    
    return 0
}

check_cuda_opencv() {
    # Check if OpenCV was built with CUDA support
    log "INFO" "Checking if OpenCV has CUDA support..."
    
    # Try to import OpenCV and check CUDA availability
    if python3 -c "import cv2; print('CUDA available:', cv2.cuda.getCudaEnabledDeviceCount() > 0)" 2>/dev/null | grep -q "CUDA available: True"; then
        log "INFO" "OpenCV CUDA support verified."
        # Create a flag file to indicate CUDA support is available
        touch /opt/.opencv_cuda_enabled
        return 0
    else
        log "WARN" "OpenCV does not have CUDA support enabled."
        return 1
    fi
}

build_opencv_on_device() {
    local opencv_version="4.8.0"
    local build_flag_file="/opt/.opencv_building"
    local built_flag_file="/opt/.opencv_built"
    local cuda_arch="${CUDA_ARCH_BIN}"
    
    # Check if we've already built OpenCV
    if [ -f "$built_flag_file" ]; then
        log "INFO" "OpenCV with CUDA support already built on this device."
        return 0
    fi
    
    # Check if another process is already building OpenCV
    if [ -f "$build_flag_file" ]; then
        log "INFO" "OpenCV build is already in progress in another container."
        return 0
    fi
    
    # Create a flag file to indicate we're building OpenCV
    touch "$build_flag_file"
    
    log "INFO" "Building OpenCV with CUDA support for Jetson ${JETSON_MODEL}..."
    log "INFO" "This may take 30-60 minutes depending on your device..."
    
    # Create a swap file to prevent memory issues
    log "INFO" "Setting up swap space for the build..."
    mkdir -p /var/cache/swap/
    dd if=/dev/zero of=/var/cache/swap/swapfile bs=1M count=4096
    chmod 0600 /var/cache/swap/swapfile
    mkswap /var/cache/swap/swapfile
    swapon /var/cache/swap/swapfile
    
    # Move to a temporary build directory
    mkdir -p /tmp/opencv_build
    cd /tmp/opencv_build || { log "ERROR" "Failed to change to build directory"; return 1; }
    
    # Clone OpenCV repositories
    log "INFO" "Cloning OpenCV repositories..."
    git clone --depth 1 --branch "${opencv_version}" https://github.com/opencv/opencv.git
    git clone --depth 1 --branch "${opencv_version}" https://github.com/opencv/opencv_contrib.git
    
    # Configure and build
    log "INFO" "Configuring OpenCV build..."
    mkdir -p opencv/build
    cd opencv/build || { log "ERROR" "Failed to change to OpenCV build directory"; return 1; }
    
    # Run CMake with appropriate Jetson-specific options
    # shellcheck disable=SC2086
    cmake \
        -D CMAKE_BUILD_TYPE=RELEASE \
        -D CMAKE_INSTALL_PREFIX=/usr/local \
        -D OPENCV_EXTRA_MODULES_PATH=../../opencv_contrib/modules \
        -D PYTHON3_EXECUTABLE=/usr/bin/python3 \
        -D WITH_CUDA=ON \
        -D WITH_CUDNN=ON \
        -D OPENCV_DNN_CUDA=ON \
        -D WITH_NVCUVID=ON \
        -D WITH_NVENC=ON \
        -D CUDA_ARCH_BIN="${cuda_arch}" \
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
        -D BUILD_opencv_world=OFF \
        -D BUILD_opencv_objdetect=OFF \
        ..
    
    # Compile with reduced parallelism to avoid memory issues
    log "INFO" "Building OpenCV (this will take a while)..."
    # Use half the available cores, but at least 1 and at most 4
    local cores
    cores=$(( $(nproc) / 2 ))
    cores=$(( cores > 0 ? cores : 1 ))
    cores=$(( cores < 4 ? cores : 4 ))
    make -j"${cores}"
    
    log "INFO" "Installing OpenCV..."
    make install
    ldconfig
    
    # Clean up
    log "INFO" "Cleaning up build files..."
    cd / || { log "ERROR" "Failed to change directory"; return 1; }
    rm -rf /tmp/opencv_build
    
    # Remove swap file
    log "INFO" "Removing swap file..."
    swapoff /var/cache/swap/swapfile
    rm -f /var/cache/swap/swapfile
    
    # Create a flag file to indicate we've built OpenCV
    touch "$built_flag_file"
    # Remove the building flag
    rm -f "$build_flag_file"
    
    log "INFO" "OpenCV with CUDA support has been built and installed successfully."
    return 0
}

check_deepstream() {
    # Get DeepStream path from environment or use default
    DEEPSTREAM_DIR=${DEEPSTREAM_PATH:-/opt/nvidia/deepstream/deepstream-6.2}
    
    log "INFO" "Checking DeepStream installation at $DEEPSTREAM_DIR..."
    if [ ! -d "$DEEPSTREAM_DIR" ]; then
        log "ERROR" "DeepStream installation not found at $DEEPSTREAM_DIR"
        log "ERROR" "Make sure you've mounted the correct DeepStream path from the host"
        return 1
    fi
    
    # Check for critical DeepStream components
    if [ ! -d "$DEEPSTREAM_DIR/lib" ] || [ ! -d "$DEEPSTREAM_DIR/sources" ]; then
        log "ERROR" "DeepStream installation appears incomplete. Missing crucial directories."
        return 1
    fi
    
    # Verify DeepStream version
    if [ -f "$DEEPSTREAM_DIR/version" ]; then
        local ds_version
        ds_version=$(cat "$DEEPSTREAM_DIR/version")
        log "INFO" "DeepStream Version: $ds_version"
    else
        log "WARN" "Could not determine DeepStream version."
    fi
    
    return 0
}

check_dependencies() {
    log "INFO" "Checking dependencies..."

    # Device-specific dependency checks
    local jetson_model="$JETSON_MODEL"
    
    # Check for device-specific libraries based on Jetson model
    if echo "$jetson_model" | grep -q "Orin"; then
        # Check for Orin-specific dependencies
        if [ ! -f "/usr/lib/aarch64-linux-gnu/tegra/libnvbufsurface.so" ]; then
            log "WARN" "Orin-specific libnvbufsurface not found in expected location."
            # Try to find it elsewhere
            local lib_path
            lib_path=$(find /usr/lib -name "libnvbufsurface.so" | head -1 || echo "")
            if [ -n "$lib_path" ]; then
                log "INFO" "Found libnvbufsurface at $lib_path. Creating symbolic link."
                ln -sf "$lib_path" "$DEEPSTREAM_DIR/lib/" || true
            else
                log "ERROR" "Could not find libnvbufsurface library."
            fi
        else
            log "INFO" "Orin-specific libraries found."
            ln -sf /usr/lib/aarch64-linux-gnu/tegra/libnvbufsurface.so "$DEEPSTREAM_DIR/lib/" || true
            ln -sf /usr/lib/aarch64-linux-gnu/tegra/libnvbufsurftransform.so "$DEEPSTREAM_DIR/lib/" || true
        fi
    elif echo "$jetson_model" | grep -q "Xavier"; then
        # Check for Xavier-specific libraries
        if [ ! -f "/usr/lib/aarch64-linux-gnu/tegra/libnvbufsurface.so" ]; then
            log "WARN" "Xavier-specific libnvbufsurface not found in expected location."
            local lib_path
            lib_path=$(find /usr/lib -name "libnvbufsurface.so" | head -1 || echo "")
            if [ -n "$lib_path" ]; then
                log "INFO" "Found libnvbufsurface at $lib_path. Creating symbolic link."
                ln -sf "$lib_path" "$DEEPSTREAM_DIR/lib/" || true
            fi
        else
            log "INFO" "Xavier-specific libraries found."
            ln -sf /usr/lib/aarch64-linux-gnu/tegra/libnvbufsurface.so "$DEEPSTREAM_DIR/lib/" || true
        fi
    elif echo "$jetson_model" | grep -q "Nano"; then
        # Nano-specific checks
        if [ ! -f "/usr/lib/aarch64-linux-gnu/tegra/libnvbufsurface.so" ]; then
            log "WARN" "Nano-specific libraries not found in expected location."
            # For Nano, the library might be in a slightly different location
            local lib_path
            lib_path=$(find /usr/lib -name "libnvbufsurface.so" | head -1 || echo "")
            if [ -n "$lib_path" ]; then
                log "INFO" "Found libnvbufsurface at $lib_path. Creating symbolic link."
                ln -sf "$lib_path" "$DEEPSTREAM_DIR/lib/" || true
            fi
        else
            log "INFO" "Nano-specific libraries found."
            ln -sf /usr/lib/aarch64-linux-gnu/tegra/libnvbufsurface.so "$DEEPSTREAM_DIR/lib/" || true
        fi
    else
        # Generic check for libnvbufsurface
        if ! ldconfig -p | grep -q libnvbufsurface; then
            log "WARN" "libnvbufsurface not found in library path."
            # Try to find it
            local lib_path
            lib_path=$(find /usr/lib -name "libnvbufsurface.so" | head -1 || echo "")
            if [ -n "$lib_path" ]; then
                log "INFO" "Found libnvbufsurface at $lib_path. Creating symbolic link."
                ln -sf "$lib_path" "$DEEPSTREAM_DIR/lib/" || true
            fi
        fi
    fi
    
    # Check TensorRT installation - Jetson specific
    if [ -f "/usr/lib/aarch64-linux-gnu/libnvinfer.so" ]; then
        local tensorrt_version
        tensorrt_version=$(readlink -f /usr/lib/aarch64-linux-gnu/libnvinfer.so 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "Unknown")
        log "INFO" "TensorRT Version: $tensorrt_version"
    else
        log "WARN" "Could not determine TensorRT version."
    fi
    
    return 0
}

setup_environment() {
    log "INFO" "Setting up environment variables..."
    
    # DeepStream environment variables for Jetson
    export DEEPSTREAM_DIR="${DEEPSTREAM_PATH:-/opt/nvidia/deepstream/deepstream-6.2}"
    export LD_LIBRARY_PATH="$DEEPSTREAM_DIR/lib:/usr/lib/aarch64-linux-gnu/tegra:$LD_LIBRARY_PATH"
    export PATH="$DEEPSTREAM_DIR/bin:$PATH"
    
    # Jetson specific GStreamer settings
    export GST_PLUGIN_PATH="$DEEPSTREAM_DIR/lib/gst-plugins:/usr/lib/aarch64-linux-gnu/gstreamer-1.0:$GST_PLUGIN_PATH"
    export GST_PLUGIN_SYSTEM_PATH="$GST_PLUGIN_PATH"
    
    # Ensure Python can find DeepStream libraries
    export PYTHONPATH="$DEEPSTREAM_DIR/lib:$PYTHONPATH"
    
    # Jetson specific CUDA paths
    export CUDA_HOME=/usr/local/cuda
    export PATH="$CUDA_HOME/bin:$PATH"
    export LD_LIBRARY_PATH="$CUDA_HOME/lib64:$LD_LIBRARY_PATH"
    
    # Apply the detected CUDA architecture if available
    if [ -n "$CUDA_ARCH_BIN" ]; then
        log "INFO" "Using detected CUDA architecture: $CUDA_ARCH_BIN"
    else
        # Use the default from environment or fallback to 7.2
        CUDA_ARCH_BIN=${CUDA_ARCH_BIN:-7.2}
        log "INFO" "Using default CUDA architecture: $CUDA_ARCH_BIN"
    fi
    export CUDA_ARCH_BIN
    
    # Set up Jetson-specific optimizations based on detected device
    local jetson_model="$JETSON_MODEL"
    
    # Enable unified memory by default on all Jetson devices
    export CUDA_UNIFIED_MEMORY=1
    
    # Device-specific optimizations
    if echo "$jetson_model" | grep -q "Orin"; then
        if echo "$jetson_model" | grep -q "Nano"; then
            # Orin Nano - use more conservative settings
            export JETSON_CLOCKS=0  # Don't max out clocks by default
            export MAXN_MODE=0
            # Set memory allocation appropriate for Orin Nano
            export MALLOC_ARENA_MAX=2
        else
            # Other Orin variants - higher clock speed and power
            export JETSON_CLOCKS=1
            export MAXN_MODE=1
            # Enable tensor cores on Orin
            export CUDA_TENSOR_CORES=1
            # Set larger memory allocation for ML workloads
            export MALLOC_ARENA_MAX=4
        fi
    elif echo "$jetson_model" | grep -q "Xavier"; then
        # Xavier-specific optimizations
        export JETSON_CLOCKS=1
        export MAXN_MODE=1
        # Xavier has more memory, can handle larger batches
        export MALLOC_ARENA_MAX=2
    elif echo "$jetson_model" | grep -q "Nano"; then
        # Nano-specific optimizations - more conservative
        export JETSON_CLOCKS=0
        # Smaller memory footprint for Nano
        export MALLOC_ARENA_MAX=1
    fi
    
    # Set TensorRT optimization level based on device capability
    if echo "$jetson_model" | grep -q "Orin" || echo "$jetson_model" | grep -q "Xavier"; then
        # Higher optimization level for more powerful devices
        export TRT_PRECISION_MODE=FP16
    else
        # More conservative setting for lower-end devices
        export TRT_PRECISION_MODE=FP32
    fi
        
    log "INFO" "Environment variables set successfully."
}

check_workspace() {
    log "INFO" "Setting up workspace..."
    
    # Create necessary directories
    mkdir -p /workspace/logs /workspace/models
    
    # Create a heartbeat file
    mkdir -p /workspace/logs/heartbeat
    touch "/workspace/logs/heartbeat/container_started_$(date +%s)"
}

process_custom_extensions() {
    # Check for custom extension directory
    if [ -d "/workspace/custom" ]; then
        log "INFO" "Processing custom extensions..."
        
        # Check for custom initialization script
        if [ -f "/workspace/custom/init.sh" ]; then
            log "INFO" "Running custom initialization script..."
            chmod +x /workspace/custom/init.sh
            /workspace/custom/init.sh
        fi
        
        # Check for custom Python requirements
        if [ -f "/workspace/custom/requirements.txt" ]; then
            log "INFO" "Installing custom Python requirements..."
            pip3 install -r /workspace/custom/requirements.txt
        fi
    fi
}

print_system_info() {
    log "INFO" "Collecting system information..."
    
    # Create system info header
    echo -e "${BLUE}======= NVIDIA Jetson DeepStream Container =======${NC}"
    echo -e "${BLUE}=============== System Information ===============${NC}"
    
    # Jetson specific GPU information
    local jetson_model="$JETSON_MODEL"
    echo -e "${GREEN}Device Model:${NC} $jetson_model"
    
    # Jetpack version
    local jetpack_version
    jetpack_version=$(dpkg -l nvidia-jetpack 2>/dev/null | grep nvidia-jetpack | awk '{print $3}' || echo "Unknown")
    echo -e "${GREEN}JetPack Version:${NC} $jetpack_version"
    
    # CUDA information for Jetson
    local cuda_version
    cuda_version=$(nvcc --version 2>/dev/null | grep release | awk '{print $6}' | cut -c2- || echo "Unknown")
    echo -e "${GREEN}CUDA Version:${NC} $cuda_version"
    echo -e "${GREEN}CUDA Architecture:${NC} $CUDA_ARCH_BIN"
    
    # Python information
    local python_version
    python_version=$(python3 --version 2>&1)
    echo -e "${GREEN}Python Version:${NC} $python_version"
    
    # DeepStream information
    local ds_version
    ds_version=$(cat "$DEEPSTREAM_DIR/version" 2>/dev/null || echo "Unknown")
    echo -e "${GREEN}DeepStream Version:${NC} $ds_version"
    
    # TensorRT information for Jetson
    local tensorrt_version
    tensorrt_version=$(readlink -f /usr/lib/aarch64-linux-gnu/libnvinfer.so 2>/dev/null | grep -oP '\d+\.\d+\.\d+' || echo "Unknown")
    echo -e "${GREEN}TensorRT Version:${NC} $tensorrt_version"
    
    # OpenCV CUDA support
    if [ -f "/opt/.opencv_cuda_enabled" ]; then
        echo -e "${GREEN}OpenCV CUDA:${NC} Enabled"
    elif [ -f "/opt/.opencv_built" ]; then
        echo -e "${GREEN}OpenCV CUDA:${NC} Built on this device"
    elif [ -f "/opt/.opencv_building" ]; then
        echo -e "${GREEN}OpenCV CUDA:${NC} Currently building"
    else
        echo -e "${GREEN}OpenCV CUDA:${NC} Not enabled (using system version)"
    fi
    
    # PyTorch information
    local pytorch_version
    pytorch_version=$(python3 -c "import torch; print(torch.__version__)" 2>/dev/null || echo "Not installed")
    echo -e "${GREEN}PyTorch Version:${NC} $pytorch_version"
    
    # TensorFlow information
    local tf_version
    tf_version=$(python3 -c "import tensorflow as tf; print(tf.__version__)" 2>/dev/null || echo "Not installed")
    echo -e "${GREEN}TensorFlow Version:${NC} $tf_version"
    
    # Jetson specific info
    local memory_info
    memory_info=$(free -h | grep Mem | awk '{print $2}')
    echo -e "${GREEN}Memory:${NC} $memory_info"
    echo -e "${GREEN}CPUs:${NC} $(nproc)"
    
    # Power mode information for Jetson
    if [ -f "/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor" ]; then
        local power_mode
        power_mode=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)
        echo -e "${GREEN}Power Mode:${NC} $power_mode"
    fi
    
    # GPU load for Jetson
    if [ -f "/sys/devices/gpu.0/load" ]; then
        local gpu_load
        gpu_load=$(cat /sys/devices/gpu.0/load")
        echo -e "${GREEN}GPU Load:${NC} $gpu_load"
    fi
    
    # Container information
    echo -e "${GREEN}Container ID:${NC} $(hostname)"
    echo -e "${GREEN}Started at:${NC} $(date)"
    
    echo -e "${BLUE}==================================================${NC}"
}

prompt_for_opencv_build() {
    echo -e "${YELLOW}=====================================================${NC}"
    echo -e "${YELLOW}  OpenCV without CUDA support detected                ${NC}"
    echo -e "${YELLOW}=====================================================${NC}"
    echo -e "This container is running on actual Jetson hardware ($JETSON_MODEL),"
    echo -e "but OpenCV is not built with CUDA support, which will limit performance."
    echo -e ""
    echo -e "Would you like to build OpenCV with CUDA support now?"
    echo -e "(This will take 30-60 minutes, but only needs to be done once)"
    echo -e ""
    echo -e "Options:"
    echo -e "  [y] Yes - Build OpenCV with CUDA support now"
    echo -e "  [n] No - Continue without CUDA-accelerated OpenCV"
    echo -e "  [s] Skip - Don't ask again on this device"
    echo -e ""
    echo -e "This prompt will timeout in 30 seconds and continue without building."
    echo -e "${YELLOW}=====================================================${NC}"
    
    # Set a timeout for the read command
    local choice
    read -t 30 -r -p "Your choice [y/n/s]: " choice
    
    case "$choice" in
        y|Y)
            log "INFO" "Building OpenCV with CUDA support..."
            build_opencv_on_device
            return 0
            ;;
        s|S)
            log "INFO" "Skipping OpenCV build and won't ask again."
            touch /opt/.opencv_skip_build
            return 1
            ;;
        *)
            log "INFO" "Continuing without CUDA-accelerated OpenCV."
            return 1
            ;;
    esac
}

# Main execution
log "INFO" "Starting NVIDIA Jetson DeepStream container initialization..."

# Exit immediately if GPU is not accessible
check_gpu || exit 1

# Exit immediately if DeepStream is not properly mounted
check_deepstream || exit 1

# Set up environment variables
setup_environment

# Check dependencies
check_dependencies

# Set up workspace directories
check_workspace

# Check if OpenCV has CUDA support and offer to build if not
if [ -t 0 ] && [ -t 1 ]; then  # Only prompt if running in interactive mode
    if [ ! -f "/opt/.opencv_cuda_enabled" ] && [ ! -f "/opt/.opencv_built" ] && [ ! -f "/opt/.opencv_building" ] && [ ! -f "/opt/.opencv_skip_build" ]; then
        if ! check_cuda_opencv; then
            prompt_for_opencv_build
        fi
    fi
else
    # Non-interactive mode
    log "INFO" "Running in non-interactive mode, skipping OpenCV CUDA check."
fi

# Process any custom extensions
process_custom_extensions

# Print system information
print_system_info

# Log container startup
log "INFO" "Container initialization complete. Starting application..."

# Execute the command passed to docker run
exec "$@"