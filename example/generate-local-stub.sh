#!/usr/bin/env bash
set -euo pipefail

# Generate a mise tool stub TOML file for local binaries

usage() {
  cat <<EOF
Usage: $0 <tool-name> <version> [OPTIONS] --platform-file <platform:path>...

Generate a mise tool stub TOML file for local binaries.

Arguments:
  <tool-name>    Name of the tool
  <version>      Version of the tool

Options:
  --platform-file <platform:path>   Platform and local file path (can be repeated)
                                    Platforms: linux-x64, linux-arm64, darwin-x64, darwin-arm64, windows-x64, windows-arm64
  --bin <path>                      Default binary path within archive (default: bin/<tool-name>)
  --platform-bin <platform:path>    Platform-specific binary path (can be repeated)
  --output <file>                   Output file (default: stdout)
  -h, --help                        Show this help message

Examples:
  $0 my-tool 1.0.0 \\
    --platform-file linux-x64:./build/my-tool-linux-x64.tar.gz \\
    --platform-file darwin-arm64:./build/my-tool-darwin-arm64.tar.gz \\
    --bin bin/my-tool

  $0 my-tool 1.0.0 \\
    --platform-file linux-x64:./build/my-tool-linux.tar.gz \\
    --platform-file windows-x64:./build/my-tool-windows.zip \\
    --platform-bin windows-x64:my-tool.exe \\
    --output my-tool-1.0.0.toml
EOF
  exit 1
}

check_dependencies() {
  if ! command -v b3sum >/dev/null; then
    echo "Error: 'b3sum' is required but not installed." >&2
    echo "Install with: cargo install b3sum" >&2
    exit 1
  fi
}

main() {
  check_dependencies

  if [[ $# -lt 2 ]]; then
    usage
  fi

  local tool_name="$1"
  local version="$2"
  shift 2

  local default_bin="bin/$tool_name"
  local output=""
  declare -A platform_files
  declare -A platform_bins

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --platform-file)
        if [[ $# -lt 2 ]]; then
          echo "Error: --platform-file requires an argument" >&2
          exit 1
        fi
        local platform="${2%%:*}"
        local filepath="${2#*:}"
        platform_files["$platform"]="$filepath"
        shift 2
        ;;
      --bin)
        if [[ $# -lt 2 ]]; then
          echo "Error: --bin requires an argument" >&2
          exit 1
        fi
        default_bin="$2"
        shift 2
        ;;
      --platform-bin)
        if [[ $# -lt 2 ]]; then
          echo "Error: --platform-bin requires an argument" >&2
          exit 1
        fi
        local platform="${2%%:*}"
        local binpath="${2#*:}"
        platform_bins["$platform"]="$binpath"
        shift 2
        ;;
      --output)
        if [[ $# -lt 2 ]]; then
          echo "Error: --output requires an argument" >&2
          exit 1
        fi
        output="$2"
        shift 2
        ;;
      -h|--help)
        usage
        ;;
      *)
        echo "Error: Unknown option: $1" >&2
        usage
        ;;
    esac
  done

  if [[ ${#platform_files[@]} -eq 0 ]]; then
    echo "Error: At least one --platform-file is required" >&2
    usage
  fi

  # Generate TOML
  generate_toml "$tool_name" "$version" "$default_bin"
}

generate_toml() {
  local tool_name="$1"
  local version="$2"
  local default_bin="$3"

  local toml_content=""
  toml_content+="#!/usr/bin/env -S mise tool-stub"$'\n'
  toml_content+=""$'\n'
  toml_content+="tool = \"$tool_name\""$'\n'
  toml_content+="version = \"$version\""$'\n'

  # Sort platforms for consistent output
  local sorted_platforms
  sorted_platforms=$(printf '%s\n' "${!platform_files[@]}" | sort)

  for platform in $sorted_platforms; do
    local filepath="${platform_files[$platform]}"

    # Validate file exists
    if [[ ! -f "$filepath" ]]; then
      echo "Error: File not found: $filepath" >&2
      exit 1
    fi

    # Get absolute path
    local abs_path
    if command -v realpath &>/dev/null; then
      abs_path=$(realpath "$filepath")
    else
      abs_path="$(cd "$(dirname "$filepath")" && pwd)/$(basename "$filepath")"
    fi

    # Compute blake3 checksum
    local checksum
    checksum=$(b3sum "$filepath" | awk '{print $1}')

    # Get file size
    local size
    size=$(stat -c%s "$filepath" 2>/dev/null || stat -f%z "$filepath" 2>/dev/null)

    # Get binary path (platform-specific or default)
    local bin_path="$default_bin"
    if [[ -n "${platform_bins[$platform]:-}" ]]; then
      bin_path="${platform_bins[$platform]}"
    fi

    # Format size with human-readable comment
    local size_comment
    size_comment=$(format_size "$size")

    toml_content+=""$'\n'
    toml_content+="[platforms.$platform]"$'\n'
    toml_content+="url = \"file://$abs_path\""$'\n'
    toml_content+="checksum = \"blake3:$checksum\""$'\n'
    toml_content+="size = $size # $size_comment"$'\n'
    toml_content+="bin = \"$bin_path\""$'\n'
  done

  # Output
  if [[ -n "$output" ]]; then
    echo -n "$toml_content" > "$output"
    echo "Generated: $output" >&2
  else
    echo -n "$toml_content"
  fi
}

format_size() {
  local bytes=$1
  if [[ $bytes -ge 1073741824 ]]; then
    printf "%.2f GiB" "$(echo "scale=2; $bytes / 1073741824" | bc)"
  elif [[ $bytes -ge 1048576 ]]; then
    printf "%.2f MiB" "$(echo "scale=2; $bytes / 1048576" | bc)"
  elif [[ $bytes -ge 1024 ]]; then
    printf "%.2f KiB" "$(echo "scale=2; $bytes / 1024" | bc)"
  else
    printf "%d B" "$bytes"
  fi
}

main "$@"
