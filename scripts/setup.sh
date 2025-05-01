#!/bin/bash
set -e

# Terminal colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration values
DEFAULT_DEEPSTREAM_PATH="/opt/nvidia/deepstream/deepstream-6.2"
DEFAULT_MODE="production"
DEFAULT_REGISTRY="ghcr.io"
DEFAULT_NAMESPACE="facadedevil"
DEFAULT_JETPACK="r35.4.1"

print_header() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}       NVIDIA Jetson DeepStream Docker Framework     ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo
}

print_help() {
    echo -e "${GREEN}Usage:${NC} ./setup.sh [OPTIONS]"
    echo
    echo -e "${GREEN}Options:${NC}"
    echo "  --deepstream-path=PATH  Path to DeepStream installation"
    echo "                         Default: ${DEFAULT_DEEPSTREAM_PATH}"
    echo "  --jetpack=VERSION      JetPack version (r35.3.1, r35.4.1, etc.)"
    echo "                         Default: ${DEFAULT_JETPACK}"
    echo "  --mode=MODE            Setup mode: production, development, debug"
    echo "                         Default: ${DEFAULT_MODE}"
    echo "  --registry=REGISTRY    Docker registry for the image"
    echo "                         Default: ${DEFAULT_REGISTRY}"
    echo "  --namespace=NAMESPACE  Docker image namespace"
    echo "                         Default: ${DEFAULT_NAMESPACE}"
    echo "  --tag=TAG              Docker image tag"
    echo "                         Default: latest"
    echo "  --no-cache             Build image without using cache"
    echo "  --skip-build           Skip Docker image build step"
    echo "  --help                 Show this help message"
    echo
    echo -e "${GREEN}Examples:${NC}"
    echo "  ./setup.sh --mode=development"
    echo "  ./setup.sh --deepstream-path=/opt/nvidia/deepstream/deepstream-6.3"
    echo "  ./setup.sh --jetpack=r35.3.1"
    echo
}

detect_jetson_device() {
    echo -e "${BLUE}[INFO]${NC} Detecting Jetson device..."
    
    # Check if running on a Jetson device
    if [ ! -f "/proc/device-tree/model" ]; then
        echo -e "${YELLOW}[WARN]${NC} Not running on a Jetson device or unable to detect model."
        echo -e "${YELLOW}[WARN]${NC} Will use default CUDA architecture settings."
        JETSON_MODEL="Unknown"
        CUDA_ARCH="7.2"
        return
    fi
    
    # Get Jetson model
    JETSON_MODEL=$(cat /proc/device-tree/model | tr '\0' ' ' | xargs)
    echo -e "${GREEN}[INFO]${NC} Detected Jetson device: ${JETSON_MODEL}"
    
    # Set CUDA architecture based on detected model
    if echo "$JETSON_MODEL" | grep -q "Orin"; then
        if echo "$JETSON_MODEL" | grep -q "NX"; then
            CUDA_ARCH="8.7"
            echo -e "${GREEN}[INFO]${NC} Detected Jetson Orin NX, setting CUDA_ARCH_BIN to ${CUDA_ARCH}"
        elif echo "$JETSON_MODEL" | grep -q "Nano"; then
            CUDA_ARCH="8.7"
            echo -e "${GREEN}[INFO]${NC} Detected Jetson Orin Nano, setting CUDA_ARCH_BIN to ${CUDA_ARCH}"
        elif echo "$JETSON_MODEL" | grep -q "Super"; then
            CUDA_ARCH="8.7"
            echo -e "${GREEN}[INFO]${NC} Detected Jetson Orin Super, setting CUDA_ARCH_BIN to ${CUDA_ARCH}"
        else
            CUDA_ARCH="8.7"
            echo -e "${GREEN}[INFO]${NC} Detected Jetson Orin, setting CUDA_ARCH_BIN to ${CUDA_ARCH}"
        fi
    elif echo "$JETSON_MODEL" | grep -q "Xavier"; then
        if echo "$JETSON_MODEL" | grep -q "AGX"; then
            CUDA_ARCH="7.2"
            echo -e "${GREEN}[INFO]${NC} Detected Jetson AGX Xavier, setting CUDA_ARCH_BIN to ${CUDA_ARCH}"
        else
            CUDA_ARCH="7.2"
            echo -e "${GREEN}[INFO]${NC} Detected Jetson Xavier, setting CUDA_ARCH_BIN to ${CUDA_ARCH}"
        fi
    elif echo "$JETSON_MODEL" | grep -q "Nano"; then
        CUDA_ARCH="5.3"
        echo -e "${GREEN}[INFO]${NC} Detected Jetson Nano, setting CUDA_ARCH_BIN to ${CUDA_ARCH}"
    elif echo "$JETSON_MODEL" | grep -q "TX"; then
        CUDA_ARCH="6.2"
        echo -e "${GREEN}[INFO]${NC} Detected Jetson TX2, setting CUDA_ARCH_BIN to ${CUDA_ARCH}"
    else
        CUDA_ARCH="7.2"
        echo -e "${YELLOW}[WARN]${NC} Unknown Jetson model, using default CUDA_ARCH_BIN=${CUDA_ARCH}"
    fi
}

check_dependencies() {
    echo -e "${BLUE}[INFO]${NC} Checking system dependencies..."
    
    # Check Docker and Docker Compose
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    # Check Docker Compose
    if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
        echo -e "${RED}[ERROR]${NC} Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Modified GPU check for Jetson devices
    if [ -f "/sys/devices/gpu.0/load" ]; then
        echo -e "${GREEN}[INFO]${NC} Jetson GPU detected."
    elif command -v nvidia-smi &> /dev/null; then
        echo -e "${GREEN}[INFO]${NC} NVIDIA GPU detected via nvidia-smi."
    else
        echo -e "${RED}[ERROR]${NC} NVIDIA GPU not detected. Please check your device."
        exit 1
    fi
    
    # Check if DeepStream exists
    if [ ! -d "$DEEPSTREAM_PATH" ]; then
        echo -e "${RED}[ERROR]${NC} DeepStream not found at $DEEPSTREAM_PATH"
        echo -e "Please install DeepStream or specify the correct path with --deepstream-path"
        exit 1
    fi
    
    echo -e "${GREEN}[OK]${NC} All dependencies are satisfied."
}

setup_x11() {
    echo -e "${BLUE}[INFO]${NC} Setting up X11 authentication..."
    
    # Create X11 authentication file
    touch /tmp/.docker.xauth
    xauth nlist $DISPLAY | sed -e 's/^..../ffff/' | xauth -f /tmp/.docker.xauth nmerge -
    
    # Allow X server connections
    xhost +local:docker
    
    echo -e "${GREEN}[OK]${NC} X11 authentication set up successfully."
}

create_directories() {
    echo -e "${BLUE}[INFO]${NC} Creating necessary directories..."
    
    # Create required directories
    mkdir -p models config logs src
    mkdir -p custom # Directory for custom extensions
    
    # Create empty files if they don't exist to avoid Docker volume mount issues
    touch models/.gitkeep
    touch config/.gitkeep
    touch logs/.gitkeep
    touch custom/.gitkeep
    
    echo -e "${GREEN}[OK]${NC} Directories created successfully."
}

create_env_file() {
    echo -e "${BLUE}[INFO]${NC} Creating environment configuration..."
    
    # Create .env file for docker-compose
    cat > .env << EOF
# Generated by setup.sh on $(date)
# Docker configuration

# Registry and image settings
REGISTRY=${REGISTRY}
NAMESPACE=${NAMESPACE}
TAG=${TAG}
CONTAINER_NAME=nvidia-jetson-app

# Base image settings
JETPACK_BASE=nvcr.io/nvidia/l4t-jetpack:${JETPACK}
CUDA_ARCH_BIN=${CUDA_ARCH}

# Runtime settings
DEEPSTREAM_PATH=${DEEPSTREAM_PATH}
DISPLAY=${DISPLAY:-:0}
CUDA_VISIBLE_DEVICES=0
NVIDIA_VISIBLE_DEVICES=all
NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics,video

# Directory mappings
SRC_DIR=./src
MODELS_DIR=./models
CONFIG_DIR=./config
LOGS_DIR=./logs
CUSTOM_DIR=./custom
VIDEO_DEVICE=/dev/video0

# Jetson device info
JETSON_MODEL="${JETSON_MODEL}"
EOF
    
    echo -e "${GREEN}[OK]${NC} Environment configuration created successfully."
}

create_sample_custom_extension() {
    echo -e "${BLUE}[INFO]${NC} Creating sample custom extension..."
    
    # Create custom init script
    cat > custom/init.sh << 'EOF'
#!/bin/bash
# Custom initialization script
# This runs during container startup

echo "Custom initialization starting..."

# Add your custom initialization steps here
# For example:
# - Download models
# - Set up additional environment variables
# - Configure system parameters

echo "Custom initialization completed."
EOF
    chmod +x custom/init.sh
    
    # Create custom requirements file
    cat > custom/requirements.txt << 'EOF'
# Add your custom Python dependencies here
# Example:
# streamlit>=1.22.0
# fastapi>=0.95.1
# uvicorn>=0.22.0
EOF
    
    echo -e "${GREEN}[OK]${NC} Sample custom extension created."
}

build_image() {
    if [ "$SKIP_BUILD" = true ]; then
        echo -e "${YELLOW}[SKIP]${NC} Skipping Docker image build as requested."
        return 0
    fi
    
    echo -e "${BLUE}[INFO]${NC} Building Docker image..."
    
    # Build arguments
    local build_args=""
    if [ "$NO_CACHE" = true ]; then
        build_args="--no-cache"
    fi
    
    # Select the appropriate profile based on mode
    if [ "$MODE" = "production" ]; then
        docker compose --env-file .env build $build_args
    else
        docker compose --env-file .env --profile dev build $build_args
    fi
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}[OK]${NC} Docker image built successfully."
    else
        echo -e "${RED}[ERROR]${NC} Failed to build Docker image."
        exit 1
    fi
}

print_success() {
    echo
    echo -e "${GREEN}=====================================================${NC}"
    echo -e "${GREEN}       Setup completed successfully!                 ${NC}"
    echo -e "${GREEN}=====================================================${NC}"
    echo
    echo -e "Your NVIDIA Jetson DeepStream Docker environment is ready."
    echo -e "To start the container, run: ${BLUE}./scripts/run.sh${NC}"
    echo
    echo -e "Development mode: ${BLUE}./scripts/run.sh --mode=development${NC}"
    echo -e "Debug mode: ${BLUE}./scripts/run.sh --mode=debug${NC}"
    echo
    echo -e "For more options, run: ${BLUE}./scripts/run.sh --help${NC}"
    echo
    echo -e "${YELLOW}Note:${NC} To distribute to clients, share only:"
    echo -e "  - docker-compose.yml (the main file for clients)"
    echo -e "  - config/ directory (for application configuration)"
    echo -e "  - custom/ directory (for customization examples)"
    echo -e "  - scripts/run.sh (for easy container management)"
    echo
}

copy_sample_configs() {
    echo -e "${BLUE}[INFO]${NC} Copying sample configuration files..."
    
    # Copy sample config files to config directory
    if [ -f "config/config.yaml" ]; then
        echo -e "${YELLOW}[SKIP]${NC} config.yaml already exists."
    else
        cp -n "$(dirname "$0")/../config/config.yaml" config/config.yaml 2>/dev/null || \
        echo -e "${YELLOW}[WARN]${NC} Could not copy sample config.yaml."
    fi
    
    if [ -f "config/roi_config.json" ]; then
        echo -e "${YELLOW}[SKIP]${NC} roi_config.json already exists."
    else
        cp -n "$(dirname "$0")/../config/roi_config.json" config/roi_config.json 2>/dev/null || \
        echo -e "${YELLOW}[WARN]${NC} Could not copy sample roi_config.json."
    fi
    
    echo -e "${GREEN}[OK]${NC} Sample configuration files prepared."
}

# Parse command line arguments
DEEPSTREAM_PATH=$DEFAULT_DEEPSTREAM_PATH
MODE=$DEFAULT_MODE
REGISTRY=$DEFAULT_REGISTRY
NAMESPACE=$DEFAULT_NAMESPACE
JETPACK=$DEFAULT_JETPACK
TAG="latest"
NO_CACHE=false
SKIP_BUILD=false
CUDA_ARCH="7.2"  # Default CUDA architecture
JETSON_MODEL="Unknown"

while [[ $# -gt 0 ]]; do
    case $1 in
        --deepstream-path=*)
            DEEPSTREAM_PATH="${1#*=}"
            shift
            ;;
        --jetpack=*)
            JETPACK="${1#*=}"
            shift
            ;;
        --mode=*)
            MODE="${1#*=}"
            shift
            ;;
        --registry=*)
            REGISTRY="${1#*=}"
            shift
            ;;
        --namespace=*)
            NAMESPACE="${1#*=}"
            shift
            ;;
        --tag=*)
            TAG="${1#*=}"
            shift
            ;;
        --cuda-arch=*)
            CUDA_ARCH="${1#*=}"
            shift
            ;;
        --no-cache)
            NO_CACHE=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --help)
            print_header
            print_help
            exit 0
            ;;
        *)
            echo -e "${RED}[ERROR]${NC} Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
    esac
done

# Main execution
print_header
echo -e "${BLUE}[INFO]${NC} Setting up NVIDIA Jetson DeepStream Docker Framework..."
echo -e "${BLUE}[INFO]${NC} Mode: ${MODE}"
echo -e "${BLUE}[INFO]${NC} DeepStream Path: ${DEEPSTREAM_PATH}"
echo -e "${BLUE}[INFO]${NC} JetPack Version: ${JETPACK}"
echo -e "${BLUE}[INFO]${NC} Docker Image: ${REGISTRY}/${NAMESPACE}/nvidia-jetson:${TAG}"
echo

# Detect Jetson device (determines CUDA_ARCH)
detect_jetson_device

# Check system dependencies
check_dependencies

# Set up X11 authentication
setup_x11

# Create necessary directories
create_directories

# Create .env file for docker-compose
create_env_file

# Copy sample configuration files
copy_sample_configs

# Create sample custom extension
create_sample_custom_extension

# Build Docker image
build_image

# Print success message
print_success