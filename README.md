# NVIDIA Jetson DeepStream Docker Framework

A comprehensive Docker framework for deploying DeepStream applications on all NVIDIA Jetson devices with automatic hardware detection and optimization. Compatible with JetPack 5.1.1-5.1.3.

## 🔑 Key Features

- **Universal Jetson Compatibility**: Automatically detects and optimizes for Orin, Xavier, Nano and TX2 families
- **Dynamic Hardware Adaptation**: Configures CUDA architecture and performance settings based on device capabilities
- **Hardware Acceleration**: Full access to NVIDIA hardware including DLA, NVENC, NVDEC, PVA and Tensor Cores
- **Modern Docker Practices**: Multiple runtime profiles, health monitoring, container lifecycle management
- **AI Framework Support**: TensorFlow, PyTorch, ONNX with GPU acceleration
- **Advanced Monitoring**: Built-in Jetson-specific performance monitoring tools
- **Easy Extensibility**: Allows clients to extend your base image with custom functionality

## 🖥️ Supported Devices

- **Orin Family**: Orin, Orin NX, Orin Nano, Orin Super
- **Xavier Family**: AGX Xavier, Xavier NX
- **Nano Family**: Jetson Nano
- **TX2 Family**: Jetson TX2

## 📋 Prerequisites

- Any NVIDIA Jetson device with JetPack 5.1.1-5.1.3
- DeepStream SDK 6.2+ installed on the host
- Docker and Docker Compose

## 🚀 Quick Start for Development

### Initial Setup

```bash
# Clone the repository
git clone https://github.com/Facadedevil/NVIDIA-Jetson-DeepStream-Docker-Framework.git
cd NVIDIA-Jetson-DeepStream-Docker-Framework

# Run the setup script (automatically detects your Jetson device)
./scripts/setup.sh --deepstream-path=/opt/nvidia/deepstream/deepstream-6.2
```

### Run the Container

```bash
# Start in production mode
./scripts/run.sh

# Start with device monitoring
./scripts/run.sh --monitor start

# View Jetson device information
./scripts/run.sh info

# Access shell in the container
./scripts/run.sh bash
```

## 📦 Distribution to Clients

The framework is designed for easy distribution to clients, allowing them to use your pre-built Docker image and extend it with their own customizations.

```bash
# Export the client distribution
./scripts/run.sh export client_distribution

# This creates a distributable package with:
# - docker-compose.yml (the main file)
# - Configuration files
# - Sample custom extensions
# - Run script
```

Clients can then use the docker-compose.yml to pull your image and extend it with their own configurations without needing to build the base image themselves. The container will automatically adapt to the client's specific Jetson hardware.

## 🔧 Configuration

### Environment Variables

Key environment variables that can be configured in `.env` or at runtime:

| Variable | Description | Default |
|----------|-------------|---------|
| `DEEPSTREAM_PATH` | Path to DeepStream installation | `/opt/nvidia/deepstream/deepstream-6.2` |
| `REGISTRY` | Docker registry | `ghcr.io` |
| `NAMESPACE` | Docker image namespace | `facadedevil` |
| `TAG` | Docker image tag | `latest` |
| `VIDEO_DEVICE` | Video device path | `/dev/video0` |
| `CUDA_ARCH_BIN` | CUDA architecture (auto-detected) | Varies by device |

### Directory Structure

```
nvidia-jetson-docker/
├── docker/                 # Docker files (internal use)
├── config/                 # Application configuration
├── models/                 # AI models directory
├── src/                    # Source code (optional)
├── custom/                 # Custom extensions
├── logs/                   # Log files
├── scripts/                # Management scripts
├── docker-compose.yml      # Main Docker Compose file (for distribution)
└── README.md               # Documentation
```

## 🛠️ Customization

### For Clients

Clients can extend your base image without rebuilding it:

1. **Configuration**: Edit files in `config/` directory
2. **Custom Initialization**: Add startup scripts to `custom/init.sh`
3. **Dependencies**: Add Python packages to `custom/requirements.txt`
4. **Volume Mounts**: Add custom volume mounts in `docker-compose.yml`

Example custom initialization script:

```bash
#!/bin/bash
# Download models at startup
mkdir -p /workspace/models
wget -O /workspace/models/model.onnx https://example.com/models/detector.onnx
```

## 📊 Monitoring and Maintenance

```bash
# Check container status
./scripts/run.sh status

# View logs
./scripts/run.sh logs

# Start with performance monitoring
./scripts/run.sh --monitor start

# Show device information and real-time performance
./scripts/run.sh info

# Update to latest version
./scripts/run.sh update
```

## 📚 Technical Details

### Hardware-Specific Optimizations

The framework automatically applies hardware-specific optimizations:

| Device Family | CUDA Architecture | Performance Settings |
|---------------|-------------------|----------------------|
| Orin          | 8.7               | Tensor Cores, MAXN power mode |
| Orin Nano     | 8.7               | Conservative power settings |
| Xavier        | 7.2               | Enhanced memory allocation |
| Nano          | 5.3               | Conservative thermal management |
| TX2           | 6.2               | Balanced performance profile |

### Included AI Frameworks

- PyTorch (optimized for Jetson)
- TensorFlow
- ONNX Runtime with GPU acceleration
- TensorRT

### Hardware Acceleration

The container has access to all available hardware accelerators:
- CUDA cores
- Tensor cores (Orin and Xavier)
- Deep Learning Accelerator (DLA)
- Programmable Vision Accelerator (PVA) on Orin
- NVENC/NVDEC hardware codecs

## 📄 License

This project is licensed under the GNU General Public License v3.0

## 🤝 Contributing

Contributions are welcome! Please feel free to submit pull requests.

## 📧 Contact

**Maintained by SAMIR Singh** - [Facadedevil](https://github.com/Facadedevil)