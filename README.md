# `mise-oci`

`mise-oci` is a backend plugin for [Mise](https://github.com/jdx/mise) that allows you to install and manage tools using [OCI](https://opencontainers.org/) (Open Container Initiative) registries.

> **⚠️ Development Status**: This plugin and the MTA specification are under heavy development and subject to breaking changes until v1.0. Use with caution in production environments.

## Why use this plugin?

- **Universal tool distribution**: Install tools from any OCI-compatible registry
- **Multi-platform support**: Automatically selects the correct platform-specific binary
- **Registry flexibility**: Works with Docker Hub, GitHub Container Registry, and private registries
- **Efficient downloads**: Only downloads the specific layer for your platform
- **Standards-based**: Implements the [Mise Tool Artifact (MTA) specification](example/SPECIFICATION.md) for consistent tool packaging

## Prerequisites

* **[Mise](https://github.com/jdx/mise)** v2025.1.0+
* **[Oras](https://oras.land/)** CLI tool for OCI registry operations

## Installation

```sh
mise plugin install oci https://github.com/jbadeau/mise-oci.git
```

## Quick Start

```sh
# Install a specific version
mise install oci:docker.io/jbadeau/azul-zulu@17.60.17
mise exec oci:docker.io/jbadeau/azul-zulu@17.60.17 -- java --version

# Install latest version
mise install oci:docker.io/jbadeau/azul-zulu
mise use oci:docker.io/jbadeau/azul-zulu

# List available versions
mise ls-remote oci:docker.io/jbadeau/azul-zulu
```

## Usage Patterns

### 1. Docker Hub Packages

Install tools from Docker Hub:

```sh
mise install oci:docker.io/jbadeau/azul-zulu@17.60.17     # Specific version
mise install oci:docker.io/jbadeau/azul-zulu@latest      # Latest tag
mise install oci:docker.io/jbadeau/azul-zulu             # Latest available
```

### 2. GitHub Container Registry

Install from GitHub Container Registry:

```sh
mise install oci:ghcr.io/owner/tool@v1.2.3
mise install oci:ghcr.io/owner/tool@main
```

### 3. Private Registries

Access private or enterprise registries:

```sh
mise install oci:registry.company.com/tools/custom-tool@v1.0.0
```

### 4. Use in Projects

Add to your `.mise.toml`:

```toml
[tools]
"oci:docker.io/jbadeau/azul-zulu" = "17.60.17"
```

## Platform Support

The plugin automatically detects your platform and downloads the appropriate binary:

| Platform | OCI Manifest Pattern |
|----------|---------------------|
| macOS ARM64 | `macosx_aarch64` |
| macOS Intel | `macosx_x64` |
| Linux ARM64 | `linux_aarch64` |
| Linux x64 | `linux_x64` |
| Windows ARM64 | `win_aarch64` |
| Windows x64 | `win_x64` |

## Authentication

For private registries, authenticate with `oras`:

```sh
# Docker Hub
oras login docker.io

# GitHub Container Registry
echo $GITHUB_TOKEN | oras login ghcr.io -u username --password-stdin

# Private registry
oras login registry.company.com -u user -p password
```

## Mise Tool Artifact (MTA) Specification

This plugin implements the [Mise Tool Artifact (MTA) specification](example/SPECIFICATION.md), a standardized format for distributing development tools via OCI registries.

### Key Features of MTA

- **Multi-platform binaries** with automatic platform detection
- **Checksum validation** using BLAKE3 and SHA256
- **Rich metadata** including licenses, documentation links, and build info
- **Tool-agnostic** format that can be used by any package manager
- **Registry-native** leveraging OCI standards for portability

### MTA Manifest Structure

Tools are packaged as OCI artifacts with platform-specific layers:

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": {
    "mediaType": "application/vnd.mise.tool.v1+json"
  },
  "layers": [
    {
      "mediaType": "application/vnd.mise.tool.layer.v1.tar+gzip",
      "digest": "sha256:...",
      "annotations": {
        "org.opencontainers.image.title": "tool-macosx_aarch64.tar.gz",
        "org.mise.tool.executable": "bin/tool",
        "org.mise.tool.checksum.blake3": "blake3:..."
      }
    }
  ]
}
```

For the complete specification, see [example/SPECIFICATION.md](example/SPECIFICATION.md).

## Environment Variables

**Required:**
```sh
export MISE_OCI_REGISTRY="registry.company.com"
export MISE_OCI_REPOSITORY="myorg/tools"
```

**Optional (for private registries):**
```sh
export MISE_OCI_USERNAME="user"
export MISE_OCI_PASSWORD="pass"
```

Tools are resolved as: `$MISE_OCI_REGISTRY/$MISE_OCI_REPOSITORY/<tool>`

Example: `registry.company.com/myorg/tools/helm:4.1.0`

## Troubleshooting

**"Tool not found"**: Verify the OCI reference exists in the registry

**"No layer found for platform"**: Ensure the tool includes a layer for your platform

**"Authentication required"**: Use `oras login` to authenticate with the registry

**"Failed to pull layer"**: Check network connectivity and registry permissions

**"Extraction failed"**: Verify the tool archive format is supported (tar.gz, zip, tar.xz)

## Supported Archive Formats

- **tar.gz** (gzip compressed tar)
- **tar.xz** (XZ compressed tar)  
- **zip** (ZIP archives)

Archives should contain binaries in a `bin/` directory structure.

## Publishing Tools

The `example/` directory contains tool stubs that can be published to OCI registries. See the [example README](example/README.md) for detailed instructions.

### Available Example Tools

| Tool | Version | Description |
|------|---------|-------------|
| `helm` | 4.1.0 | Kubernetes package manager |
| `helmfile` | 1.2.3 | Declarative spec for deploying helm charts |
| `node` | 24.13.0 | Node.js JavaScript runtime |
| `pnpm` | 10.28.2 | Fast, disk space efficient package manager |
| `azul-zulu` | 21.48.15 | Azul Zulu JDK 21 |
| `maven` | 3.9.12 | Apache Maven build tool |
| `jib-cli` | 0.13.0 | Build container images for Java applications |

### Quick Publish

To publish all example tools to your registry:

```sh
cd example

# Publish individual tools
./publish.sh helm-4.1.0.toml docker.io/yournamespace
./publish.sh helmfile-1.2.3.toml docker.io/yournamespace
./publish.sh node-24.13.0.toml docker.io/yournamespace
./publish.sh pnpm-10.28.2.toml docker.io/yournamespace
./publish.sh azul-zulu-21.48.15.toml docker.io/yournamespace
./publish.sh maven-3.9.12.toml docker.io/yournamespace
./publish.sh jib-cli-0.13.0.toml docker.io/yournamespace
```

Or publish all at once:

```sh
cd example
for stub in helm-4.1.0.toml helmfile-1.2.3.toml node-24.13.0.toml pnpm-10.28.2.toml azul-zulu-21.48.15.toml maven-3.9.12.toml jib-cli-0.13.0.toml; do
  ./publish.sh "$stub" docker.io/yournamespace
done
```

### Prerequisites for Publishing

- **[oras](https://oras.land/)** - OCI registry client
- **[tomlq](https://github.com/kislyuk/yq)** - TOML query tool (`pip install yq`)
- **[b3sum](https://github.com/BLAKE3-team/BLAKE3)** - BLAKE3 checksum tool
- **[jq](https://jqlang.github.io/jq/)** - JSON processor
- **[curl](https://curl.se/)** - URL transfer tool

### Creating New Tool Stubs

See [example/SPECIFICATION.md](example/SPECIFICATION.md) for the full tool stub format.

Basic structure:

```toml
tool = "mytool"
version = "1.0.0"

[platforms.linux-x64]
url = "https://example.com/mytool-linux-amd64.tar.gz"
checksum = "blake3:abc123..."
size = 12345678
bin = "mytool"

[platforms.darwin-arm64]
url = "https://example.com/mytool-darwin-arm64.tar.gz"
checksum = "blake3:def456..."
size = 12345678
bin = "mytool"
```

## Development

```sh
# Test the plugin
mise plugin link oci $PWD --force
mise install oci:docker.io/jbadeau/azul-zulu@17.60.17
mise exec oci:docker.io/jbadeau/azul-zulu@17.60.17 -- java --version
```

The plugin hooks are implemented in Lua and use mise's backend plugin API for platform detection and tool management.