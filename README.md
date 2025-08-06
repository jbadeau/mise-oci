# `mise-oci`

`mise-oci` is a backend plugin for [Mise](https://github.com/jdx/mise) that allows you to install
tools using [OCI](https://opencontainers.org/).

---

## Why `mise-oci`?


## Prerequisites

Before you get started, make sure you have:

* **[Mise](https://github.com/jdx/mise)**
* **[Oras](https://oras.land/)**

## Installation

Install the plugin:

```sh
mise plugin install oci https://github.com/jbadeau/mise-oci.git
```

---

## Usage

### List Available Versions

```sh
mise ls-remote oci:docker.io/jbadeau/azul-zulu
```

### Install a Specific Version

```sh
mise install oci:docker.io/jbadeau/azul-zulu@17.60.17
```

Install the latest version:

```sh
mise install oci:docker.io/jbadeau/azul-zulu
```

### Use in a Project

```sh
mise use oci:docker.io/jbadeau/azul-zulu
```

### Run the Tool

```sh
mise exec oci:docker.io/jbadeau/azul-zulu -- java --version
```