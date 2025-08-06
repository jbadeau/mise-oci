
# Mise Tool Artifact (MTA) Specification v1.0

## Overview

The **Mise Tool Artifact (MTA)** specification defines a standardized, multi-platform format for distributing development tools and binaries using [OCI-compatible](https://github.com/opencontainers/image-spec) registries. It extends the tool stub format used by [mise](https://mise.jdx.dev/), but is **tool-agnostic** and can be integrated into any tool version manager, package manager, or provisioning system.

## Goals

- ✅ **Multi-platform**: Distribute binaries for Linux, macOS, Windows
- ✅ **Registry-native**: Fully OCI-compliant and portable
- ✅ **Tool-agnostic**: Can be used with mise, nix, brew, etc.
- ✅ **Secure**: Checksum and signature validation support
- ✅ **Composable**: Extendable with metadata and annotations

## Specification

### Media Types

| Component | Media Type |
|----------|-------------|
| Manifest | `application/vnd.oci.image.manifest.v1+json` |
| Config   | `application/vnd.mise.tool.v1+json` |
| Linux/Mac Layer | `application/vnd.mise.tool.layer.v1.tar+gzip` |
| Windows Layer | `application/vnd.mise.tool.layer.v1.zip` |

## Artifact Layout

An MTA artifact uses a standard OCI image manifest with:

- A **config object** for metadata
- One or more **binary layers**
- OCI **annotations** for indexing, tooling, and integrity

### Manifest Structure

```json
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": {
    "mediaType": "application/vnd.mise.tool.v1+json",
    "digest": "sha256:...",
    "size": 1234
  },
  "layers": [
    {
      "mediaType": "application/vnd.mise.tool.layer.v1.tar+gzip",
      "digest": "sha256:...",
      "size": 12345678,
      "platform": {
        "architecture": "amd64",
        "os": "linux",
        "os.version": ">=3.10"
      },
      "annotations": {
        "org.mise.tool.filename": "tool-linux-amd64.tar.gz",
        "org.mise.tool.executable": "bin/tool",
        "org.mise.tool.checksum.blake3": "blake3:...",
        "org.mise.tool.checksum.sha256": "sha256:...",
        "org.mise.download.url": "https://cdn.example.com/tool.tar.gz",
        "org.mise.download.size": "12345678"
      }
    }
  ],
  "annotations": {
    "org.mise.tool.name": "azul-zulu",
    "org.mise.tool.version": "17.60.17",
    "org.mise.tool.description": "Azul Zulu OpenJDK distribution",
    "org.mise.tool.homepage": "https://azul.com/zulu",
    "org.mise.tool.documentation": "https://docs.azul.com/core/zulu-openjdk",
    "org.mise.tool.source": "https://github.com/zulu-openjdk/zulu-openjdk",
    "org.mise.tool.license": "GPL-2.0-with-classpath-exception",
    "org.mise.tool.vendor": "Azul Systems",
    "org.mise.tool.backends": "http,asdf",
    "org.opencontainers.image.created": "2025-08-06T05:08:34Z",
    "org.opencontainers.image.authors": "Azul Systems <support@azul.com>"
  }
}
```

## Config Object (`application/vnd.mise.tool.v1+json`)

This defines installation behavior, metadata, and platform-specific binaries.

```json
{
  "mtaSpecVersion": "1.0",
  "tool": "azul-zulu",
  "version": "17.60.17",
  "bin": "bin/java",
  "description": "Azul Zulu OpenJDK distribution",
  "homepage": "https://azul.com/zulu",
  "license": "GPL-2.0-with-classpath-exception",
  "category": "runtime",
  "platforms": {
    "linux-x64": {
      "url": "https://cdn.azul.com/.../linux_x64.tar.gz",
      "checksum": "blake3:abc123...",
      "size": 198700362,
      "bin": "bin/java"
    }
  },
  "env": {
    "JAVA_HOME": "{{ install_path }}",
    "PATH": "{{ install_path }}/bin:{{ PATH }}"
  },
  "post_install": [
    "chmod +x {{ install_path }}/bin/*"
  ],
  "validation": {
    "command": "java -version",
    "expected_output_regex": "openjdk version \"17\.0\.16.*\""
  },
  "metadata": {
    "backends": ["http", "asdf"],
    "source": "https://github.com/zulu-openjdk/zulu-openjdk",
    "maintainers": [
      {
        "name": "Azul Systems",
        "email": "support@azul.com"
      }
    ],
    "build_info": {
      "build_date": "2025-08-06T05:08:34Z",
      "build_system": "mise-mta",
      "build_version": "1.0.0"
    }
  }
}
```

## Annotations

All annotations use the `org.mise.*` namespace.

### Required Manifest Annotations

| Annotation | Description |
|------------|-------------|
| `org.mise.tool.name` | Tool ID |
| `org.mise.tool.version` | Tool version |
| `org.mise.tool.description` | Description of the tool |

### Recommended Manifest Annotations

| Annotation | Description |
|------------|-------------|
| `org.mise.tool.homepage` | Homepage URL |
| `org.mise.tool.documentation` | Documentation URL |
| `org.mise.tool.source` | Source code URL |
| `org.mise.tool.license` | SPDX license |
| `org.mise.tool.vendor` | Vendor name |

### Layer-Level Annotations

| Annotation | Description |
|------------|-------------|
| `org.mise.tool.filename` | Name of archive |
| `org.mise.tool.executable` | Path to main binary |
| `org.mise.tool.checksum.blake3` | BLAKE3 hash |
| `org.mise.tool.checksum.sha256` | SHA256 hash |
| `org.mise.download.url` | Source download URL |
| `org.mise.download.size` | File size |

## Inspirations

The **Mise Tool Artifact (MTA)** format is heavily inspired by prior work in the ecosystem, notably:

- [**Helm**](https://helm.sh): for pioneering the use of OCI registries as general-purpose distribution systems via charts with manifests, layers, and custom metadata.