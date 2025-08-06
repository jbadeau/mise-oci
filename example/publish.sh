#!/usr/bin/env bash
set -euo pipefail

main() {
  check_dependencies
  parse_args "$@"

  absolute_mise_stub_file=$(get_absolute_path "$mise_stub_file_arg")
  parse_image_name_and_tag "$absolute_mise_stub_file"
  image_name="$registry/$namespace/$image_name_base"

  parse_global_annotations "$absolute_mise_stub_file"

  work_dir=$(mktemp -d)
  trap "rm -rf '$work_dir'" EXIT
  cd "$work_dir"

  process_platforms "$absolute_mise_stub_file" "$image_name" "$tag"
  echo "✅ Published OCI artifact: $image_name:$tag"
}

check_dependencies() {
  for cmd in tomlq oras curl b3sum; do
    if ! command -v "$cmd" >/dev/null; then
      echo "❌ '$cmd' is required but not installed."
      echo "   Install tomlq with: pip install yq"
      exit 1
    fi
  done
}

parse_args() {
  if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <mise_stub_file> <registry/namespace>" >&2
    echo "Example: $0 tool.toml docker.io/username" >&2
    exit 1
  fi

  mise_stub_file_arg="$1"
  registry_namespace="$2"
  
  # Split registry/namespace - require both parts
  if [[ "$registry_namespace" == *"/"* ]]; then
    registry="${registry_namespace%%/*}"
    namespace="${registry_namespace#*/}"
  else
    echo "❌ Registry/namespace must be in format 'registry/namespace'" >&2
    echo "Example: docker.io/username" >&2
    exit 1
  fi

  if [[ ! -f "$mise_stub_file_arg" ]]; then
    echo "❌ File not found: $mise_stub_file_arg" >&2
    exit 1
  fi
}

get_absolute_path() {
  local file_path="$1"
  if command -v realpath &>/dev/null; then
    realpath "$file_path"
  else
    cd "$(dirname "$file_path")" && echo "$(pwd)/$(basename "$file_path")"
  fi
}

parse_image_name_and_tag() {
  image_name_base=$(tomlq -r '.tool' "$1")
  tag=$(tomlq -r '.version // "latest"' "$1")
  if [[ -z "$image_name_base" ]]; then
    echo "❌ Missing 'tool' in mise stub manifest"
    exit 1
  fi
}

parse_global_annotations() {
  local file="$1"
  title=$(tomlq -r '.tool // empty' "$file")
  description="Mise tool: $(tomlq -r '.tool // empty' "$file")"
  version=$(tomlq -r '.version // "latest"' "$file")
  authors=""
  license=""
  source=""
  documentation=""
  url=""
  vendor="mise"
  created=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
}

normalize_platform() {
  case "$1" in 
    macos|darwin) os="darwin" ;; 
    *) os="$1" ;; 
  esac
  case "$2" in 
    x86_64|amd64) arch="amd64" ;; 
    aarch64) arch="arm64" ;; 
    x64) arch="amd64" ;;
    *) arch="$2" ;; 
  esac
}

process_platforms() {
  local mise_stub_file="$1" image_name="$2" tag="$3"
  local platform_files=()
  local platform_annotations=()

  # Get platform keys from TOML
  while IFS= read -r platform_key; do
    platform_key=$(echo "$platform_key" | sed 's/"//g')  # Remove quotes
    
    # Extract platform data from TOML
    local url expected_checksum format bin_path
    url=$(tomlq -r ".platforms.\"$platform_key\".url" "$mise_stub_file")
    expected_checksum=$(tomlq -r ".platforms.\"$platform_key\".checksum // empty" "$mise_stub_file")
    bin_path=$(tomlq -r ".platforms.\"$platform_key\".bin // \"bin/java\"" "$mise_stub_file")
    
    # Skip if no URL
    if [[ "$url" == "null" || -z "$url" ]]; then
      continue
    fi
    
    # Handle blake3: prefix in checksum
    if [[ "$expected_checksum" =~ ^blake3: ]]; then
      expected_checksum="${expected_checksum#blake3:}"
    fi

    normalize_platform "$(echo "$platform_key" | cut -d'-' -f1)" "$(echo "$platform_key" | cut -d'-' -f2)"

    filename=$(basename "$url")
    
    echo "📦 Downloading $filename for $os/$arch"
    curl -fsSL -o "$filename" "$url"

    # Only verify checksum if provided
    if [[ -n "$expected_checksum" && "$expected_checksum" != "empty" ]]; then
      actual_digest=$(b3sum "$filename" | awk '{print $1}')
      if [[ "$actual_digest" != "$expected_checksum" ]]; then
        echo "❌ BLAKE3 digest mismatch for $filename"
        echo "Expected: $expected_checksum"
        echo "Actual:   $actual_digest"
        exit 1
      fi
      echo "✅ Verified BLAKE3 digest"
    else
      echo "⚠️  No checksum provided, skipping verification"
    fi

    # Detect format from filename
    case "$filename" in
      *.tar.gz)   media_type="application/vnd.oci.image.layer.v1.tar+gzip" ;;
      *.tar.xz)   media_type="application/vnd.oci.image.layer.v1.tar+xz" ;;
      *.tar.zst)  media_type="application/vnd.oci.image.layer.v1.tar+zstd" ;;
      *.zip)      media_type="application/zip" ;;
      *.vsix)     media_type="application/vnd.microsoft.vscode.vsix" ;;
      *)          media_type="application/octet-stream" ;;
    esac

    # Add platform-specific annotations to the file
    platform_files+=("$filename:$media_type")
    platform_annotations+=(
      "--annotation" "$filename:org.opencontainers.image.title=$filename"
      "--annotation" "$filename:org.opencontainers.image.platform=$os/$arch"
      "--annotation" "$filename:org.opencontainers.image.download=$url"
    )

  done < <(tomlq -r '.platforms | keys[]' "$mise_stub_file")

  # Create single OCI artifact with all platform files as layers
  local final_ref="${image_name}:${tag}"
  echo "📦 Creating OCI artifact: $final_ref"
  
  echo "{\"architecture\":\"multi\",\"os\":\"multi\"}" > config.json
  config_media_type="application/vnd.oci.image.config.v1+json"

  oras push "$final_ref" \
    --config "config.json:$config_media_type" \
    "${platform_files[@]}" \
    "${platform_annotations[@]}" \
    --annotation "org.opencontainers.image.description=$description" \
    --annotation "org.opencontainers.image.version=$version" \
    --annotation "org.opencontainers.image.authors=$authors" \
    --annotation "org.opencontainers.image.licenses=$license" \
    --annotation "org.opencontainers.image.source=$source" \
    --annotation "org.opencontainers.image.documentation=$documentation" \
    --annotation "org.opencontainers.image.vendor=$vendor" \
    --annotation "org.opencontainers.image.created=$created" \
    --annotation "org.opencontainers.image.ref.name=$tag"
}


main "$@"
