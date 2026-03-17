# Nexus Example

Install tools from a local Nexus OCI registry using the mise-oci plugin.

## Prerequisites

Start Nexus and publish the Java artifact using the [mise-tool-artifact-specification examples](https://github.com/jbadeau/mise-tool-artifact-specification/tree/main/examples):

```sh
mise run dev
mise run publish
```

## Usage

Copy `mise.toml` from this directory into your project, then:

```sh
mise install
mise exec -- java -version
```

## Configuration

| Variable | Value | Description |
|----------|-------|-------------|
| `MISE_OCI_REGISTRY` | `localhost:5000` | Nexus Docker registry port |
| `MISE_OCI_REPOSITORY` | `tools` | Repository path in registry |
| `MISE_OCI_INSECURE` | `true` | Use HTTP instead of HTTPS |
