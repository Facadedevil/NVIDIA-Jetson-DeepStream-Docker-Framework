#!/bin/bash
set -e

# Terminal colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default configuration values
DEFAULT_MODE="production"
DEFAULT_COMPOSE_PROJECT="nvidia-jetson"

print_header() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${BLUE}       NVIDIA Jetson DeepStream Docker Framework     ${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    echo
}

print_help() {
    echo -e "${GREEN}Usage:${NC} ./run.sh [OPTIONS] [COMMAND]"
    echo
    echo -e "${GREEN}Options:${NC}"
    echo "  --mode=MODE           Runtime mode: production, development"
    echo "                        Default: ${DEFAULT_MODE}"
    echo "  --project=NAME        Docker Compose project name"
    echo "                        Default: ${DEFAULT_COMPOSE_PROJECT}"
    echo "  --detached            Run container in detached mode (background)"
    echo "  --pull                Pull latest image before starting"
    echo "  --monitor             Start with monitoring services enabled"
    echo "  --help                Show this help message"
    echo
    echo -e "${GREEN}Commands:${NC}"
    echo "  start                 Start the container (default)"
    echo "  stop                  Stop the container"
    echo "  restart               Restart the container"
    echo "  status                Show container status"
    echo "  logs                  Show container logs"
    echo "  exec                  Execute a command in the container"
    echo "  bash                  Open a bash shell in the container"
    echo "  update                Update the container image to latest version"
    echo "  export                Export the container configuration for distribution"
    echo "  info                  Display information about the detected Jetson device"
    echo
    echo -e "${GREEN}Examples:${NC}"
    echo "  ./run.sh                       # Start in production mode"
    echo "  ./run.sh --mode=development    # Start in development mode"
    echo "  ./run.sh --detached start      # Start in background"
    echo "  ./run.sh --monitor start       # Start with monitoring services"
    echo "  ./run.sh stop                  # Stop the container"
    echo "  ./run.sh logs                  # Show logs"
    echo "  ./run.sh exec python3 -c 'print(\"Hello\")'  # Run Python command"
    echo "  ./run.sh bash                  # Open bash shell"
    echo "  ./run.sh info                  # Show Jetson device information"
    echo "  ./run.sh export client_distribution  # Export for client"
    echo
}

check_dependencies() {
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
    
    # Check if environment file exists
    if [ ! -f ".env" ]; then
        # Check if we're running from scripts directory
        if [ -f "../.env" ]; then
            cd ..
        else
            echo -e "${RED}[ERROR]${NC} Environment file (.env) not found. Please run setup.sh first."
            exit 1
        fi
    fi
}

detect_jetson_device() {
    echo -e "${BLUE}[INFO]${NC} Detecting Jetson device..."
    
    # Check if running on a Jetson device
    if [ ! -f "/proc/device-tree/model" ]; then
        echo -e "${YELLOW}[WARN]${NC} Not running on a Jetson device or unable to detect model."
        return 1
    fi
    
    # Get Jetson model
    JETSON_MODEL=$(cat /proc/device-tree/model | tr '\0' ' ' | xargs)
    echo -e "${GREEN}[INFO]${NC} Detected Jetson device: ${JETSON_MODEL}"
    
    # Get GPU load if available
    if [ -f "/sys/devices/gpu.0/load" ]; then
        GPU_LOAD=$(cat /sys/devices/gpu.0/load)
        echo -e "${GREEN}[INFO]${NC} Current GPU Load: ${GPU_LOAD}"
    fi
    
    # Get CPU information
    CPU_INFO=$(lscpu | grep "Model name" | cut -d ':' -f 2 | xargs)
    echo -e "${GREEN}[INFO]${NC} CPU: ${CPU_INFO}"
    
    # Get memory information
    MEM_TOTAL=$(free -h | grep "Mem" | awk '{print $2}')
    MEM_USED=$(free -h | grep "Mem" | awk '{print $3}')
    echo -e "${GREEN}[INFO]${NC} Memory: ${MEM_USED} used of ${MEM_TOTAL} total"
    
    # Get JetPack version if available
    if [ -f "/etc/nv_tegra_release" ]; then
        JETPACK_VERSION=$(cat /etc/nv_tegra_release | grep "R" | awk '{print $2}')
        echo -e "${GREEN}[INFO]${NC} JetPack Version: ${JETPACK_VERSION}"
    fi
    
    return 0
}

setup_x11() {
    # Create X11 authentication file if it doesn't exist
    if [ ! -f "/tmp/.docker.xauth" ]; then
        echo -e "${BLUE}[INFO]${NC} Setting up X11 authentication..."
        touch /tmp/.docker.xauth
        xauth nlist $DISPLAY | sed -e 's/^..../ffff/' | xauth -f /tmp/.docker.xauth nmerge -
        echo -e "${GREEN}[OK]${NC} X11 authentication set up."
    fi
    
    # Allow X server connections if not already allowed
    xhost +local:docker &>/dev/null
}

get_container_name() {
    # Get container name from environment file
    if [ -f ".env" ]; then
        source .env
        echo ${CONTAINER_NAME:-nvidia-jetson-app}
    else
        echo "nvidia-jetson-app"
    fi
}

start_container() {
    echo -e "${BLUE}[INFO]${NC} Starting container in ${MODE} mode..."
    
    # Pull latest image if requested
    if [ "$PULL_IMAGE" = true ]; then
        echo -e "${BLUE}[INFO]${NC} Pulling latest image..."
        docker compose --env-file .env -p "$PROJECT_NAME" pull
    fi
    
    # Set appropriate command based on mode and monitoring
    local compose_command="docker compose --env-file .env -p \"$PROJECT_NAME\""
    
    if [ "$MODE" = "development" ]; then
        compose_command+=" --profile dev"
    fi
    
    if [ "$MONITOR" = true ]; then
        compose_command+=" --profile monitoring"
    fi
    
    if [ "$DETACHED" = true ]; then
        eval "$compose_command up -d"
    else
        eval "$compose_command up"
    fi
    
    if [ "$DETACHED" = true ]; then
        echo -e "${GREEN}[OK]${NC} Container started in background."
        echo -e "Use '${BLUE}./run.sh logs${NC}' to view logs or '${BLUE}./run.sh bash${NC}' to get a shell."
    fi
}

stop_container() {
    echo -e "${BLUE}[INFO]${NC} Stopping container..."
    docker compose --env-file .env -p "$PROJECT_NAME" down
    echo -e "${GREEN}[OK]${NC} Container stopped."
}

restart_container() {
    echo -e "${BLUE}[INFO]${NC} Restarting container..."
    docker compose --env-file .env -p "$PROJECT_NAME" restart
    echo -e "${GREEN}[OK]${NC} Container restarted."
}

show_container_status() {
    echo -e "${BLUE}[INFO]${NC} Container status:"
    docker compose --env-file .env -p "$PROJECT_NAME" ps
    
    # Show container health if running
    CONTAINER_NAME=$(get_container_name)
    if docker ps -q -f name="$CONTAINER_NAME" &>/dev/null; then
        echo
        echo -e "${BLUE}[INFO]${NC} Container health check status:"
        docker inspect --format "{{.State.Health.Status}}" "$CONTAINER_NAME"
        
        echo
        echo -e "${BLUE}[INFO]${NC} Resource usage:"
        docker stats --no-stream "$CONTAINER_NAME"
    fi
}

show_container_logs() {
    echo -e "${BLUE}[INFO]${NC} Container logs:"
    if [ -n "$LOG_LINES" ]; then
        docker compose --env-file .env -p "$PROJECT_NAME" logs --tail="$LOG_LINES" -f
    else
        docker compose --env-file .env -p "$PROJECT_NAME" logs -f
    fi
}

exec_in_container() {
    CONTAINER_NAME=$(get_container_name)
    if ! docker ps -q -f name="$CONTAINER_NAME" &>/dev/null; then
        echo -e "${YELLOW}[WARN]${NC} Container is not running. Starting it now..."
        start_container
    fi
    
    echo -e "${BLUE}[INFO]${NC} Executing command in container: $EXEC_COMMAND"
    docker exec -it "$CONTAINER_NAME" $EXEC_COMMAND
}

bash_in_container() {
    CONTAINER_NAME=$(get_container_name)
    if ! docker ps -q -f name="$CONTAINER_NAME" &>/dev/null; then
        echo -e "${YELLOW}[WARN]${NC} Container is not running. Starting it now..."
        start_container
    fi
    
    echo -e "${BLUE}[INFO]${NC} Opening bash shell in container..."
    docker exec -it "$CONTAINER_NAME" bash
}

update_container() {
    echo -e "${BLUE}[INFO]${NC} Updating container image..."
    
    # Pull latest image
    docker compose --env-file .env -p "$PROJECT_NAME" pull
    
    # Check if container is running
    CONTAINER_NAME=$(get_container_name)
    if docker ps -q -f name="$CONTAINER_NAME" &>/dev/null; then
        echo -e "${BLUE}[INFO]${NC} Container is running. Stopping and restarting..."
        docker compose --env-file .env -p "$PROJECT_NAME" down
        docker compose --env-file .env -p "$PROJECT_NAME" up -d
        echo -e "${GREEN}[OK]${NC} Container updated and restarted."
    else
        echo -e "${GREEN}[OK]${NC} Container image updated. Use './run.sh start' to start the container."
    fi
}

show_device_info() {
    echo -e "${BLUE}[INFO]${NC} Jetson Device Information"
    echo -e "${BLUE}----------------------------------------------------${NC}"
    
    # Check if running on a Jetson device
    if ! detect_jetson_device; then
        echo -e "${YELLOW}[WARN]${NC} Not running on a Jetson device or unable to detect model."
        return 1
    fi
    
    # Display CUDA information
    if [ -f ".env" ]; then
        source .env
        echo -e "${GREEN}CUDA Architecture:${NC} ${CUDA_ARCH_BIN:-Not specified in .env}"
    fi
    
    # Display container configuration
    echo -e "\n${BLUE}[INFO]${NC} Container Configuration"
    echo -e "${BLUE}----------------------------------------------------${NC}"
    echo -e "${GREEN}DeepStream Path:${NC} ${DEEPSTREAM_PATH:-Not specified in .env}"
    echo -e "${GREEN}Docker Image:${NC} ${REGISTRY:-ghcr.io}/${NAMESPACE:-facadedevil}/nvidia-jetson:${TAG:-latest}"
    
    # Check if tegrastats is available
    if command -v tegrastats &> /dev/null; then
        echo -e "\n${BLUE}[INFO]${NC} Current Jetson Performance Stats (Press Ctrl+C to exit)"
        echo -e "${BLUE}----------------------------------------------------${NC}"
        tegrastats --interval 2000
    fi
}

export_distribution() {
    EXPORT_DIR=${1:-"client_distribution"}
    
    echo -e "${BLUE}[INFO]${NC} Exporting container configuration for client distribution..."
    
    # Create export directory
    mkdir -p "$EXPORT_DIR"
    
    # Copy docker-compose.yml (the main file for clients)
    cp docker-compose.yml "$EXPORT_DIR/"
    
    # Create minimal .env file for clients
    cat > "$EXPORT_DIR/.env" << EOF
# NVIDIA Jetson DeepStream Docker configuration
# Generated on $(date)

# DeepStream path on your system (change this to match your installation)
DEEPSTREAM_PATH=/opt/nvidia/deepstream/deepstream-6.2

# Container name
CONTAINER_NAME=nvidia-jetson-app

# Docker image reference
REGISTRY=${REGISTRY:-ghcr.io}
NAMESPACE=${NAMESPACE:-facadedevil}
TAG=${TAG:-latest}

# Device mappings
VIDEO_DEVICE=/dev/video0

# Directory mappings (relative paths, customize as needed)
CONFIG_DIR=./config
MODELS_DIR=./models
LOGS_DIR=./logs
CUSTOM_DIR=./custom

# This configuration will automatically detect your Jetson device
# and configure the appropriate hardware settings
EOF
    
    # Copy config directory
    if [ -d "config" ]; then
        mkdir -p "$EXPORT_DIR/config"
        cp -r config/* "$EXPORT_DIR/config/"
    fi
    
    # Create sample custom directory
    mkdir -p "$EXPORT_DIR/custom"
    cp -r custom/* "$EXPORT_DIR/custom/"
    
    # Create empty directories for models and logs
    mkdir -p "$EXPORT_DIR/models"
    mkdir -p "$EXPORT_DIR/logs"
    
    # Copy run script
    mkdir -p "$EXPORT_DIR/scripts"
    cp "$(dirname "$0")/run.sh" "$EXPORT_DIR/scripts/"
    chmod +x "$EXPORT_DIR/scripts/run.sh"
    
    # Create a README.md for clients
    cat > "$EXPORT_DIR/README.md" << 'EOF'
# NVIDIA Jetson DeepStream Application

This package contains a pre-configured Docker environment for running DeepStream applications on NVIDIA Jetson devices.

## Prerequisites

- NVIDIA Jetson device (Orin, Xavier, Nano, or TX2 series) with JetPack 5.1.1 or later
- DeepStream SDK 6.2 or later installed on the host
- Docker and Docker Compose

## Quick Start

1. Edit the `.env` file to set your DeepStream path and other configuration options

2. Start the container:
   ```bash
   ./scripts/run.sh
   ```

3. View logs:
   ```bash
   ./scripts/run.sh logs
   ```

4. Stop the container:
   ```bash
   ./scripts/run.sh stop
   ```

## Device Compatibility

This Docker configuration automatically detects and optimizes for:
- Jetson Orin series (Orin, Orin NX, Orin Nano, Orin Super)
- Jetson Xavier series (AGX Xavier, Xavier NX)
- Jetson Nano
- Jetson TX2

## Configuration

- `config/config.yaml`: Main application configuration
- `config/roi_config.json`: Region of interest configuration
- `custom/`: Directory for custom extensions and initializations

## Customization

You can customize the application by:

1. Modifying the configuration files in `config/`
2. Adding custom initialization scripts in `custom/init.sh`
3. Adding custom Python dependencies in `custom/requirements.txt`
4. Mounting additional volumes in `docker-compose.yml`

## Device Information

To see information about your Jetson device:
```bash
./scripts/run.sh info
```

## Monitoring

To start with system monitoring:
```bash
./scripts/run.sh --monitor start
```

## Troubleshooting

If you encounter issues:

1. Check container status: `./scripts/run.sh status`
2. View container logs: `./scripts/run.sh logs`
3. Access container shell: `./scripts/run.sh bash`
EOF
    
    # Create zip archive
    if command -v zip &> /dev/null; then
        echo -e "${BLUE}[INFO]${NC} Creating zip archive..."
        (cd "$EXPORT_DIR" && zip -r "../${EXPORT_DIR}.zip" .)
        echo -e "${GREEN}[OK]${NC} Zip archive created: ${EXPORT_DIR}.zip"
    fi
    
    echo -e "${GREEN}[OK]${NC} Distribution exported to ${EXPORT_DIR}/"
    echo -e "Share the following with clients:"
    echo -e "  - ${EXPORT_DIR}/ directory or"
    echo -e "  - ${EXPORT_DIR}.zip (if created)"
}

# Parse command line arguments
MODE=$DEFAULT_MODE
PROJECT_NAME=$DEFAULT_COMPOSE_PROJECT
DETACHED=false
PULL_IMAGE=false
MONITOR=false
COMMAND="start"
EXEC_COMMAND=""
LOG_LINES=""
EXPORT_DIR=""

# Parse options
while [[ $# -gt 0 ]]; do
    case $1 in
        --mode=*)
            MODE="${1#*=}"
            shift
            ;;
        --project=*)
            PROJECT_NAME="${1#*=}"
            shift
            ;;
        --detached)
            DETACHED=true
            shift
            ;;
        --pull)
            PULL_IMAGE=true
            shift
            ;;
        --monitor)
            MONITOR=true
            shift
            ;;
        --lines=*)
            LOG_LINES="${1#*=}"
            shift
            ;;
        --help)
            print_header
            print_help
            exit 0
            ;;
        -*)
            echo -e "${RED}[ERROR]${NC} Unknown option: $1"
            echo "Use --help for usage information."
            exit 1
            ;;
        *)
            # If it's not an option, it's a command
            COMMAND="$1"
            shift
            
            # Collect remaining args for exec command or export directory
            if [ "$COMMAND" = "exec" ]; then
                EXEC_COMMAND="$*"
                break
            elif [ "$COMMAND" = "export" ] && [ $# -gt 0 ]; then
                EXPORT_DIR="$1"
                shift
            fi
            ;;
    esac
done

# Main execution
print_header
check_dependencies
setup_x11

# Execute the appropriate command
case $COMMAND in
    start)
        start_container
        ;;
    stop)
        stop_container
        ;;
    restart)
        restart_container
        ;;
    status)
        show_container_status
        ;;
    logs)
        show_container_logs
        ;;
    exec)
        if [ -z "$EXEC_COMMAND" ]; then
            echo -e "${RED}[ERROR]${NC} No command specified for exec."
            echo "Usage: ./run.sh exec COMMAND"
            exit 1
        fi
        exec_in_container
        ;;
    bash)
        bash_in_container
        ;;
    update)
        update_container
        ;;
    info)
        show_device_info
        ;;
    export)
        export_distribution "$EXPORT_DIR"
        ;;
    *)
        echo -e "${RED}[ERROR]${NC} Unknown command: $COMMAND"
        print_help
        exit 1
        ;;
esac