#!/usr/bin/env bash

set -e

MAPPINGS_DIR="./mappings"
FILES_DIR="./__files"
MAX_RETRIES=${MAX_RETRIES:-30}
RETRY_INTERVAL=${RETRY_INTERVAL:-10}
INCLUDE_DIRS="${INCLUDE_DIRS:-}"

# Parse CLI arguments (--include takes precedence over env var)
while [[ $# -gt 0 ]]; do
  case $1 in
    --include)
      INCLUDE_DIRS="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --include <dirs>  Comma-separated list of subdirectories to include"
      echo "                    (e.g., --include cui or --include cui,other)"
      echo "  --help, -h        Show this help message"
      echo ""
      echo "Environment variables:"
      echo "  WIREMOCK_URL      (required) URL of the WireMock server"
      echo "  INCLUDE_DIRS      Comma-separated subdirs to include (CLI takes precedence)"
      echo "  MAX_RETRIES       Max retries waiting for WireMock (default: 30)"
      echo "  RETRY_INTERVAL    Seconds between retries (default: 10)"
      echo ""
      echo "By default, only root-level mappings are loaded. Use --include to add subdirectories."
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

if [ -z "$WIREMOCK_URL" ]; then
  echo "Error: WIREMOCK_URL environment variable is not set"
  exit 1
fi

if [ ! -d "$MAPPINGS_DIR" ]; then
  echo "Mappings folder not found: $MAPPINGS_DIR"
  exit 1
fi

echo "Loading mappings into WireMock at $WIREMOCK_URL"

# Wait for WireMock to be ready
echo "Waiting for WireMock to be ready..."
attempt=1
while [ $attempt -le $MAX_RETRIES ]; do
  response=$(curl -sk -o /dev/null -w "%{http_code}" "$WIREMOCK_URL/__admin/mappings" 2>/dev/null || echo "000")

  if [ "$response" = "200" ]; then
    echo "WireMock is ready"
    break
  fi

  if [ $attempt -eq $MAX_RETRIES ]; then
    echo "Error: WireMock not ready after $MAX_RETRIES attempts"
    exit 1
  fi

  echo "WireMock not ready (HTTP $response), attempt $attempt/$MAX_RETRIES, retrying in ${RETRY_INTERVAL}s..."
  sleep $RETRY_INTERVAL
  attempt=$((attempt + 1))
done

# Reset all existing mappings first to avoid duplicates
echo "Resetting existing WireMock mappings..."
RESET_RESPONSE=$(curl -sk -o /dev/null -w "%{http_code}" -X DELETE "$WIREMOCK_URL/__admin/mappings")
if [ "$RESET_RESPONSE" == "200" ]; then
  echo "Existing mappings cleared successfully"
else
  echo "Warning: Failed to clear existing mappings (HTTP $RESET_RESPONSE)"
fi

# Function to resolve bodyFileName path relative to the mapping file's directory
resolve_body_file_path() {
  local mapping_file="$1"
  local body_file_name="$2"
  local mapping_dir
  mapping_dir=$(dirname "$mapping_file")
  
  # Get the relative path from MAPPINGS_DIR to the mapping file's directory
  local rel_path="${mapping_dir#$MAPPINGS_DIR}"
  rel_path="${rel_path#/}"
  
  # Try paths in order of preference:
  # 1. Same relative path under __files (e.g., __files/cui/subdir/file.json)
  # 2. Direct path under __files (e.g., __files/file.json)
  if [[ -n "$rel_path" ]] && [[ -f "$FILES_DIR/$rel_path/$body_file_name" ]]; then
    echo "$FILES_DIR/$rel_path/$body_file_name"
  elif [[ -f "$FILES_DIR/$body_file_name" ]]; then
    echo "$FILES_DIR/$body_file_name"
  else
    echo ""
  fi
}

# Function to inline body file content into a stub JSON
inline_body_file() {
  local stub_json="$1"
  local body_file_path="$2"
  local tmp_json
  tmp_json=$(mktemp)
  
  if [[ "$body_file_path" == *.pdf ]]; then
    echo "Inlining PDF as base64"
    local tmp_base64
    tmp_base64=$(mktemp)
    if [[ "$OSTYPE" == "darwin"* ]]; then
      base64 -i "$body_file_path" | tr -d '\n' > "$tmp_base64"
    else
      base64 -w 0 "$body_file_path" > "$tmp_base64"
    fi
    echo "$stub_json" | jq --rawfile base64_content "$tmp_base64" '
      del(.response.bodyFileName) |
      .response.base64Body = $base64_content
    ' > "$tmp_json"
    rm "$tmp_base64"
  else
    echo "Inlining JSON/text body from: $body_file_path"
    echo "$stub_json" | jq --rawfile body "$body_file_path" '
      del(.response.bodyFileName) |
      .response.body = $body
    ' > "$tmp_json"
  fi
  
  cat "$tmp_json"
  rm "$tmp_json"
}

# Function to post a single stub to WireMock
post_stub() {
  local stub_json="$1"
  local source_file="$2"
  local stub_index="$3"
  
  local body_file_name
  body_file_name=$(echo "$stub_json" | jq -r '.response.bodyFileName // empty')
  
  local final_json="$stub_json"
  
  if [[ -n "$body_file_name" ]]; then
    local body_file_path
    body_file_path=$(resolve_body_file_path "$source_file" "$body_file_name")
    
    if [[ -z "$body_file_path" ]]; then
      echo "  Warning: Missing body file '$body_file_name' for stub $stub_index in $source_file - skipping"
      return 1
    fi
    
    final_json=$(inline_body_file "$stub_json" "$body_file_path")
  fi
  
  local tmp_post
  tmp_post=$(mktemp)
  echo "$final_json" > "$tmp_post"
  
  local response
  response=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$WIREMOCK_URL/__admin/mappings" \
    -H "Content-Type: application/json" \
    --data-binary "@$tmp_post")
  
  rm "$tmp_post"
  
  if [ "$response" == "201" ]; then
    return 0
  else
    echo "  Failed to load stub $stub_index (HTTP $response)"
    return 1
  fi
}

# Process JSON files based on INCLUDE_DIRS setting
loaded_count=0
failed_count=0

# Function to find mapping files based on configuration
find_mapping_files() {
  # Always include root-level mappings
  find "$MAPPINGS_DIR" -maxdepth 1 -name "*.json" -type f -print0
  
  # Include specified subdirectories if INCLUDE_DIRS is set
  if [[ -n "$INCLUDE_DIRS" ]]; then
    IFS=',' read -ra DIRS <<< "$INCLUDE_DIRS"
    for dir in "${DIRS[@]}"; do
      dir="${dir#"${dir%%[![:space:]]*}"}"  # trim leading whitespace
      dir="${dir%"${dir##*[![:space:]]}"}"  # trim trailing whitespace
      if [[ -d "$MAPPINGS_DIR/$dir" ]]; then
        find "$MAPPINGS_DIR/$dir" -name "*.json" -type f -print0
      else
        echo "Warning: Directory '$MAPPINGS_DIR/$dir' not found — skipping" >&2
      fi
    done
  fi
}

if [[ -n "$INCLUDE_DIRS" ]]; then
  echo "Including subdirectories: $INCLUDE_DIRS"
else
  echo "Loading root-level mappings only (use --include to add subdirectories)"
fi

while IFS= read -r -d '' file; do
  echo "Processing: $file"
  
  # Check if file contains a mappings array (multi-mapping format)
  if jq -e '.mappings' "$file" > /dev/null 2>&1; then
    # Multi-mapping format: iterate through each stub in the array
    stub_count=$(jq '.mappings | length' "$file")
    echo "  Found $stub_count stubs in mappings array"
    
    for i in $(seq 0 $((stub_count - 1))); do
      stub_json=$(jq -c ".mappings[$i]" "$file")
      if post_stub "$stub_json" "$file" "$((i + 1))"; then
        loaded_count=$((loaded_count + 1))
      else
        failed_count=$((failed_count + 1))
      fi
    done
  else
    # Single stub format: process directly
    stub_json=$(jq -c '.' "$file")
    if post_stub "$stub_json" "$file" "1"; then
      loaded_count=$((loaded_count + 1))
    else
      failed_count=$((failed_count + 1))
    fi
  fi
done < <(find_mapping_files)

echo ""
echo "All mappings processed: $loaded_count loaded, $failed_count failed."

# Generate and load the documentation page — failure here is non-fatal
echo ""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$SCRIPT_DIR/generate-docs.sh" ]; then
  echo "Warning: generate-docs.sh not found in $SCRIPT_DIR — skipping documentation generation"
else
  echo "Generating documentation page..."
  if MAPPINGS_DIR="$MAPPINGS_DIR" INCLUDE_DIRS="$INCLUDE_DIRS" bash "$SCRIPT_DIR/generate-docs.sh"; then
    : # success message already printed by generate-docs.sh
  else
    echo "Warning: Documentation page generation failed — WireMock mappings are still loaded"
  fi
fi
