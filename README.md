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

```sh
# Custom registry configuration
export MISE_OCI_DEFAULT_REGISTRY="registry.company.com"

# Authentication credentials (if not using oras login)
export MISE_OCI_USERNAME="user"
export MISE_OCI_PASSWORD="pass"
```

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

## Development

```sh
# Test the plugin
mise plugin link oci $PWD --force
mise install oci:docker.io/jbadeau/azul-zulu@17.60.17
mise exec oci:docker.io/jbadeau/azul-zulu@17.60.17 -- java --version
```

The plugin hooks are implemented in Lua and use mise's backend plugin API for platform detection and tool management.