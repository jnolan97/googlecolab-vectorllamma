# PXE Server Setup

A comprehensive, automated PXE (Preboot Execution Environment) server setup with modular configuration, environment variable support, and extensive testing capabilities.

## 🚀 Features

- **Complete PXE Server Stack**: DHCP, TFTP, and NFS services
- **Environment Variable Configuration**: Flexible configuration through environment variables
- **Modular Architecture**: Separate scripts for setup, configuration, and management
- **Comprehensive Testing**: Automated tests for configuration, network, services, and integration
- **CI/CD Pipeline**: GitHub Actions workflow for automated testing and validation
- **Security Focused**: Built with security best practices and validation
- **Multi-Distribution Support**: Compatible with Ubuntu, CentOS, and other major Linux distributions

## 📋 Table of Contents

- [Quick Start](#quick-start)
- [Architecture](#architecture)
- [Installation](#installation)
- [Configuration](#configuration)
- [Usage](#usage)
- [Testing](#testing)
- [CI/CD Pipeline](#cicd-pipeline)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)

## 🚀 Quick Start

1. **Clone the repository**:
   ```bash
   git clone https://github.com/jnolan97/googlecolab-vectorllamma.git
   cd googlecolab-vectorllamma
   ```

2. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your network configuration
   ```

3. **Run setup**:
   ```bash
   sudo src/scripts/setup-pxe.sh
   ```

4. **Verify installation**:
   ```bash
   src/scripts/validate-env.sh
   src/scripts/manage-services.sh status
   ```

## 🏗 Architecture

### Directory Structure

```
├── src/
│   ├── config/                 # Configuration templates
│   │   ├── dhcpd.conf.template       # DHCP server configuration
│   │   ├── tftpd.conf.template       # TFTP server configuration
│   │   ├── exports.template          # NFS exports configuration
│   │   └── pxelinux.cfg.template     # PXE boot menu configuration
│   └── scripts/               # Setup and management scripts
│       ├── setup-pxe.sh              # Main setup script
│       ├── generate-configs.sh       # Configuration generator
│       ├── manage-services.sh        # Service management
│       └── validate-env.sh           # Environment validation
├── tests/                     # Test suite
│   ├── test-configs.sh               # Configuration tests
│   ├── test-network.sh               # Network connectivity tests
│   ├── test-services.sh              # Service status tests
│   └── test-integration.sh           # Integration tests
├── .github/workflows/         # CI/CD pipeline
│   └── pxe-server.yml               # GitHub Actions workflow
├── .env.example              # Environment variable template
└── README.md                 # This file
```

### Components

1. **DHCP Server**: Assigns IP addresses and provides PXE boot information
2. **TFTP Server**: Serves boot files and kernel images
3. **NFS Server**: Provides root filesystem for network booting
4. **PXE Boot Menu**: Interactive boot menu for client selection

## 📦 Installation

### Prerequisites

- Linux system (Ubuntu 18.04+, CentOS 7+, or compatible)
- Root access
- Network interface configured
- Internet connection for package installation

### Automatic Installation

```bash
# Clone and run setup
git clone https://github.com/jnolan97/googlecolab-vectorllamma.git
cd googlecolab-vectorllamma
sudo src/scripts/setup-pxe.sh
```

### Manual Installation

1. **Install required packages**:
   ```bash
   # Ubuntu/Debian
   sudo apt-get install isc-dhcp-server tftpd-hpa nfs-kernel-server syslinux-common pxelinux
   
   # CentOS/RHEL
   sudo yum install dhcp-server tftp-server nfs-utils syslinux
   ```

2. **Configure environment**:
   ```bash
   cp .env.example .env
   # Edit .env with your settings
   ```

3. **Generate configurations**:
   ```bash
   src/scripts/generate-configs.sh
   ```

4. **Start services**:
   ```bash
   src/scripts/manage-services.sh start
   ```

## ⚙️ Configuration

### Environment Variables

Copy `.env.example` to `.env` and customize:

```bash
# Network Configuration
DHCP_SUBNET=192.168.1.0
DHCP_NETMASK=255.255.255.0
DHCP_RANGE_START=192.168.1.100
DHCP_RANGE_END=192.168.1.200
DHCP_GATEWAY=192.168.1.1
DHCP_DNS=8.8.8.8,8.8.4.4

# PXE Server Configuration
PXE_SERVER_IP=192.168.1.10
TFTP_ROOT=/var/lib/tftpboot
NFS_ROOT=/var/lib/nfs
DHCP_LEASE_TIME=7200

# Service Configuration
DHCP_INTERFACE=eth0
TFTP_PORT=69
NFS_PORT=2049

# Security Configuration
SECURE_TFTP=false
NFS_SECURITY=sys
```

### Configuration Templates

Templates use environment variable substitution:

- `src/config/dhcpd.conf.template` - DHCP server configuration
- `src/config/tftpd.conf.template` - TFTP server configuration
- `src/config/exports.template` - NFS exports configuration
- `src/config/pxelinux.cfg.template` - PXE boot menu

## 🔧 Usage

### Basic Operations

```bash
# Start all services
src/scripts/manage-services.sh start

# Stop all services
src/scripts/manage-services.sh stop

# Restart all services
src/scripts/manage-services.sh restart

# Check service status
src/scripts/manage-services.sh status

# View service logs
src/scripts/manage-services.sh logs
```

### Configuration Management

```bash
# Validate environment
src/scripts/validate-env.sh

# Generate configurations
src/scripts/generate-configs.sh

# Validate specific components
src/scripts/validate-env.sh network
src/scripts/validate-env.sh packages
```

### Adding Boot Images

1. Place boot images in appropriate TFTP directories:
   ```bash
   # Example for Ubuntu
   mkdir -p $TFTP_ROOT/ubuntu
   cp vmlinuz initrd.img $TFTP_ROOT/ubuntu/
   ```

2. Update NFS exports for root filesystems:
   ```bash
   # Extract root filesystem
   mkdir -p $NFS_ROOT/ubuntu
   # Mount or extract your root filesystem here
   ```

3. Update PXE menu configuration and regenerate:
   ```bash
   # Edit src/config/pxelinux.cfg.template
   src/scripts/generate-configs.sh
   ```

## 🧪 Testing

### Running Tests

```bash
# Run all tests
tests/test-integration.sh

# Run specific test suites
tests/test-configs.sh      # Configuration tests
tests/test-network.sh      # Network tests
tests/test-services.sh     # Service tests
```

### Test Categories

1. **Configuration Tests**: Validate generated configuration files
2. **Network Tests**: Check network connectivity and port availability
3. **Service Tests**: Verify service status and functionality
4. **Integration Tests**: End-to-end workflow validation

## 🔄 CI/CD Pipeline

### GitHub Actions Workflow

The project includes a comprehensive CI/CD pipeline that:

- **Lints** all shell scripts with ShellCheck
- **Validates** configuration templates and environment files
- **Tests** all components in isolated environments
- **Performs** security scans for hardcoded secrets
- **Generates** documentation and artifacts

### Triggering Workflows

```bash
# Automatic triggers
git push origin main        # Full pipeline
git push origin develop     # Full pipeline

# Manual trigger with custom test suite
# Use GitHub Actions UI with workflow_dispatch
```

### Workflow Jobs

1. **Lint and Validate**: Code quality and template validation
2. **Configuration Tests**: Template processing and syntax validation
3. **Network Tests**: Network connectivity and configuration
4. **Service Tests**: Service availability and status
5. **Integration Tests**: End-to-end functionality
6. **Security Scan**: Security vulnerability assessment
7. **Documentation**: Automated documentation generation

## 🔒 Security

### Security Features

- **Input validation** for all environment variables
- **Configuration file backup** before modifications
- **Service isolation** with proper user permissions
- **Network access controls** through firewall configuration
- **Audit logging** for all configuration changes

### Security Best Practices

1. **Firewall Configuration**:
   ```bash
   # Allow required ports only
   sudo ufw allow 67/udp    # DHCP
   sudo ufw allow 69/udp    # TFTP
   sudo ufw allow 2049/tcp  # NFS
   ```

2. **File Permissions**:
   ```bash
   # Secure configuration directories
   sudo chmod 750 /var/lib/tftpboot
   sudo chown -R tftp:tftp /var/lib/tftpboot
   ```

3. **Network Isolation**:
   - Use dedicated network segments for PXE clients
   - Implement VLAN isolation where possible
   - Configure access controls on network equipment

## 🔍 Troubleshooting

### Common Issues

1. **DHCP Service Won't Start**:
   ```bash
   # Check configuration syntax
   sudo dhcpd -t -cf /etc/dhcp/dhcpd.conf
   
   # Check interface binding
   src/scripts/validate-env.sh network
   ```

2. **TFTP Files Not Accessible**:
   ```bash
   # Check permissions
   ls -la $TFTP_ROOT
   
   # Test TFTP access
   tftp localhost -c get pxelinux.0
   ```

3. **PXE Boot Fails**:
   ```bash
   # Check service status
   src/scripts/manage-services.sh status
   
   # Review logs
   src/scripts/manage-services.sh logs
   ```

### Log Locations

- DHCP: `journalctl -u isc-dhcp-server` or `/var/log/dhcp.log`
- TFTP: `journalctl -u tftpd-hpa` or `/var/log/syslog`
- NFS: `journalctl -u nfs-kernel-server`
- PXE Setup: `/var/log/pxe-server.log`

### Diagnostic Commands

```bash
# Network diagnostics
ip addr show
netstat -ulpn | grep -E "(67|69|2049)"

# Service diagnostics
systemctl status isc-dhcp-server tftpd-hpa nfs-kernel-server

# Configuration diagnostics
src/scripts/validate-env.sh all
```

## 🤝 Contributing

### Development Setup

1. Fork the repository
2. Create a feature branch
3. Make changes following the coding standards
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

### Coding Standards

- Use ShellCheck for script linting
- Follow bash best practices (set -euo pipefail)
- Include comprehensive error handling
- Add logging for all operations
- Document functions and complex logic

### Testing Requirements

- All new features must include tests
- Maintain or improve test coverage
- Ensure all existing tests pass
- Add integration tests for end-to-end scenarios

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/jnolan97/googlecolab-vectorllamma/issues)
- **Discussions**: [GitHub Discussions](https://github.com/jnolan97/googlecolab-vectorllamma/discussions)
- **Wiki**: [Project Wiki](https://github.com/jnolan97/googlecolab-vectorllamma/wiki)

## 🙏 Acknowledgments

- PXE and network boot community
- Open source contributors
- Testing framework inspirations
- CI/CD best practices guides

---

**Note**: This PXE server setup is designed for educational and development purposes. For production environments, additional security hardening and monitoring should be implemented.
