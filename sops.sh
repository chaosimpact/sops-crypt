#!/usr/bin/env zsh

# sops-crypt.plugin.zsh
# A ZSH plugin for SOPS that provides one-click encryption and decryption
# of files in the current directory and subdirectories.

# Check if sops is installed
if ! command -v sops &> /dev/null; then
  echo "Error: SOPS is not installed. Please install it first."
  echo "Visit: https://github.com/mozilla/sops"
  return 1
fi

# Default configuration variables
DEFAULT_SOPS_CRYPT_FILE_PATTERNS=("*.yaml" "*.yml" "*.json" "*.env" "*.txt")
DEFAULT_SOPS_CRYPT_SECRET_SUFFIX="-secret"
DEFAULT_SOPS_CRYPT_ENCRYPTED_INFIX=".enc"
DEFAULT_SOPS_CRYPT_IGNORE_PATTERNS=("node_modules" ".git" ".svn" ".hg")
DEFAULT_SOPS_CRYPT_SEARCH_TOOL="auto" # Options: "auto", "fd", "find"
DEFAULT_SOPS_CRYPT_FD_PARAMS="--type file --hidden -g --no-ignore" # fd params
DEFAULT_SOPS_CRYPT_FIND_PARAMS="-type f" # find params

# Load from environment variables if set, otherwise use defaults
# For array variables, check if the environment variable exists and is not empty
if [[ -n "${SOPS_CRYPT_FILE_PATTERNS+x}" && -n "$SOPS_CRYPT_FILE_PATTERNS" ]]; then
  IFS=' ' read -A SOPS_CRYPT_FILE_PATTERNS <<< "$SOPS_CRYPT_FILE_PATTERNS"
else
  SOPS_CRYPT_FILE_PATTERNS=("${DEFAULT_SOPS_CRYPT_FILE_PATTERNS[@]}")
fi

if [[ -n "${SOPS_CRYPT_IGNORE_PATTERNS+x}" && -n "$SOPS_CRYPT_IGNORE_PATTERNS" ]]; then
  IFS=' ' read -A SOPS_CRYPT_IGNORE_PATTERNS <<< "$SOPS_CRYPT_IGNORE_PATTERNS"
else
  SOPS_CRYPT_IGNORE_PATTERNS=("${DEFAULT_SOPS_CRYPT_IGNORE_PATTERNS[@]}")
fi

# For string variables
SOPS_CRYPT_SECRET_SUFFIX="${SOPS_CRYPT_SECRET_SUFFIX:-$DEFAULT_SOPS_CRYPT_SECRET_SUFFIX}"
SOPS_CRYPT_ENCRYPTED_INFIX="${SOPS_CRYPT_ENCRYPTED_INFIX:-$DEFAULT_SOPS_CRYPT_ENCRYPTED_INFIX}"
SOPS_CRYPT_SEARCH_TOOL="${SOPS_CRYPT_SEARCH_TOOL:-$DEFAULT_SOPS_CRYPT_SEARCH_TOOL}"
SOPS_CRYPT_FD_PARAMS="${SOPS_CRYPT_FD_PARAMS:-$DEFAULT_SOPS_CRYPT_FD_PARAMS}"
SOPS_CRYPT_FIND_PARAMS="${SOPS_CRYPT_FIND_PARAMS:-$DEFAULT_SOPS_CRYPT_FIND_PARAMS}"

# Helper function to check if a file is already encrypted
_sops_is_encrypted() {
  local file="$1"
  grep -q "sops:" "$file" 2>/dev/null || grep -q "ENC\[" "$file" 2>/dev/null
  return $?
}

# Helper function to check if encrypted file is up-to-date with source file
# Returns 0 if encryption is needed, 1 if not
_sops_needs_encrypt() {
  local source_file="$1"
  local encrypted_file="$2"
  
  if [[ ! -f "$encrypted_file" ]]; then
    return 0
  fi
  
  if [[ "$source_file" -nt "$encrypted_file" ]]; then
    return 0
  fi
  
  return 1
}

# Helper function to determine which search tool to use
_sops_get_search_tool() {
  if [[ "$SOPS_CRYPT_SEARCH_TOOL" == "find" ]]; then
    echo "find"
  elif [[ "$SOPS_CRYPT_SEARCH_TOOL" == "fd" ]]; then
    if command -v fd &> /dev/null; then
      echo "fd"
    else
      echo "find"
    fi
  else # auto or anything else
    if command -v fd &> /dev/null; then
      echo "fd"
    else
      echo "find"
    fi
  fi
}

# Helper function to filter files for encryption/decryption
_sops_filter_files() {
  local dir="$1"
  local mode="$2"  # "encrypt" or "decrypt"
  local result=()
  local search_tool=$(_sops_get_search_tool)
  local exclude_params=""
  local find_exclude_params=""
  
  for ignore_pattern in "${SOPS_CRYPT_IGNORE_PATTERNS[@]}"; do
    if [[ "$search_tool" == "fd" ]]; then
      exclude_params+=" -E $ignore_pattern"
    else
      find_exclude_params+=" -not -path '*$ignore_pattern*'"
    fi
  done
  
  for pattern in "${SOPS_CRYPT_FILE_PATTERNS[@]}"; do
    local ext="${pattern#*.}"
    
    if [[ "$mode" == "encrypt" ]]; then
      if [[ "$search_tool" == "fd" ]]; then
        result+=($(fd ${=SOPS_CRYPT_FD_PARAMS} ${=exclude_params} "*${SOPS_CRYPT_SECRET_SUFFIX}.$ext" "$dir" 2>/dev/null))
      else
        result+=($(find "$dir" ${=SOPS_CRYPT_FIND_PARAMS} ${=find_exclude_params} -name "*${SOPS_CRYPT_SECRET_SUFFIX}.$ext" 2>/dev/null))
      fi
    else
      if [[ "$search_tool" == "fd" ]]; then
        result+=($(fd ${=SOPS_CRYPT_FD_PARAMS} ${=exclude_params} "*${SOPS_CRYPT_ENCRYPTED_INFIX}.$ext" "$dir" 2>/dev/null))
      else
        result+=($(find "$dir" ${=SOPS_CRYPT_FIND_PARAMS} ${=find_exclude_params} -name "*${SOPS_CRYPT_ENCRYPTED_INFIX}.$ext" 2>/dev/null))
      fi
    fi
  done
  
  echo "${result[@]}"
}

# Function to encrypt all unencrypted files in current directory and subdirectories
sops-encrypt-all() {
  local dir="."
  local force=0
  
  # Parse arguments: handle both positional and flag arguments
  for arg in "$@"; do
    if [[ "$arg" == "--force" || "$arg" == "-f" ]]; then
      force=1
    elif [[ -d "$arg" ]]; then
      dir="$arg"
    fi
  done
  
  local count=0
  local skipped=0
  local files=($(_sops_filter_files "$dir" "encrypt"))

  echo "🔍 Scanning for secret files to encrypt in $dir and subdirectories..."
  
  if [[ "$force" -eq 1 ]]; then
    echo "🔥 Force mode enabled - All files will be re-encrypted regardless of timestamps"
  fi
  
  for file in "${files[@]}"; do
    local ext=".${file##*.}"
    local base="${file%$ext}"
    local output_file="${base}${SOPS_CRYPT_ENCRYPTED_INFIX}${ext}"
    
    # Check if encryption is needed, skip the check if force is enabled
    if [[ "$force" -eq 0 ]] && ! _sops_needs_encrypt "$file" "$output_file"; then
      echo "⏭️  Skipping: $file (encrypted file is up-to-date)"
      ((skipped++))
      continue
    fi
    
    echo "🔒 Encrypting: $file"
    
    if sops --encrypt "$file" > "$output_file"; then
      ((count++))
    else
      echo "❌ Failed to encrypt: $file"
    fi
  done

  if [[ $count -eq 0 && $skipped -eq 0 ]]; then
    echo "✅ No secret files found to encrypt."
  elif [[ $count -eq 0 && $skipped -gt 0 ]]; then
    echo "✅ No files encrypted, $skipped files already up-to-date."
  elif [[ $skipped -gt 0 ]]; then
    echo "✅ Encrypted $count files successfully, skipped $skipped up-to-date files."
  else
    echo "✅ Encrypted $count files successfully."
  fi
}

# Function to decrypt all encrypted files in current directory and subdirectories
sops-decrypt-all() {
  local dir="${1:-.}"
  local count=0
  local files=($(_sops_filter_files "$dir" "decrypt"))

  echo "🔍 Scanning for encrypted files to decrypt in $dir and subdirectories..."
  
  for file in "${files[@]}"; do
    echo "🔓 Decrypting: $file"
    
    local ext=".${file##*.}"
    local base="${file%$ext}"
    base="${base%$SOPS_CRYPT_ENCRYPTED_INFIX}"
    if [[ "$base" != *"${SOPS_CRYPT_SECRET_SUFFIX}" ]]; then
      base="${base}${SOPS_CRYPT_SECRET_SUFFIX}"
    fi
    local output_file="${base}${ext}"
    
    if sops --decrypt "$file" > "$output_file"; then
      ((count++))
    else
      echo "❌ Failed to decrypt: $file"
    fi
  done

  if [[ $count -eq 0 ]]; then
    echo "✅ No encrypted files found to decrypt."
  else
    echo "✅ Decrypted $count files successfully."
  fi
}

# Function to encrypt a single file
sops-encrypt() {
  local file=""
  local force=0
  
  # Parse arguments
  for arg in "$@"; do
    if [[ "$arg" == "--force" || "$arg" == "-f" ]]; then
      force=1
    elif [[ -f "$arg" ]]; then
      file="$arg"
    fi
  done
  
  if [[ -z "$file" ]]; then
    echo "❌ No valid file provided"
    echo "Usage: sops-encrypt [--force|-f] <file>"
    return 1
  fi
  
  if _sops_is_encrypted "$file"; then
    echo "⚠️ File is already encrypted: $file"
    return 0
  fi
  
  # Check if file follows the naming convention
  if [[ "$file" != *"${SOPS_CRYPT_SECRET_SUFFIX}"* ]]; then
    echo "⚠️ Warning: File doesn't follow the *${SOPS_CRYPT_SECRET_SUFFIX}.* naming convention"
    echo "   Files intended for encryption should be named like: config${SOPS_CRYPT_SECRET_SUFFIX}.yaml"
  fi
  
  local ext=".${file##*.}"
  local base="${file%$ext}"
  local output_file="${base}${SOPS_CRYPT_ENCRYPTED_INFIX}${ext}"
  
  if [[ "$force" -eq 1 ]]; then
    echo "🔥 Force mode enabled - File will be re-encrypted regardless of timestamps"
  fi
  
  # Check if encryption is needed (file changed), skip the check if force is enabled
  if [[ "$force" -eq 0 ]] && ! _sops_needs_encrypt "$file" "$output_file"; then
    echo "⏭️  Skipping: $file (encrypted file is up-to-date)"
    return 0
  fi
  
  echo "🔒 Encrypting: $file"
  
  if sops --encrypt "$file" > "$output_file"; then
    echo "✅ Encrypted successfully: $output_file"
  else
    echo "❌ Failed to encrypt: $file"
    return 1
  fi
}

# Function to decrypt a single file
sops-decrypt() {
  local file="$1"
  
  if [[ ! -f "$file" ]]; then
    echo "❌ File not found: $file"
    return 1
  fi
  
  if ! _sops_is_encrypted "$file"; then
    echo "⚠️ File is not encrypted: $file"
    return 0
  fi
  
  # Check if file follows the naming convention
  if [[ "$file" != *"${SOPS_CRYPT_ENCRYPTED_INFIX}"* ]]; then
    echo "⚠️ Warning: File doesn't follow the *${SOPS_CRYPT_ENCRYPTED_INFIX}.* naming convention"
    echo "   Encrypted files should be named like: config${SOPS_CRYPT_ENCRYPTED_INFIX}.yaml"
  fi
  
  echo "🔓 Decrypting: $file"
  
  local ext=".${file##*.}"
  local base="${file%$ext}"
  if [[ "$base" == *"${SOPS_CRYPT_ENCRYPTED_INFIX}" ]]; then
    base="${base%$SOPS_CRYPT_ENCRYPTED_INFIX}"
    if [[ "$base" != *"${SOPS_CRYPT_SECRET_SUFFIX}" ]]; then
      base="${base}${SOPS_CRYPT_SECRET_SUFFIX}"
    fi
    output_file="${base}${ext}"
  else
    output_file="${file}.dec"
  fi
  
  if sops --decrypt "$file" > "$output_file"; then
    echo "✅ Decrypted successfully: $output_file"
  else
    echo "❌ Failed to decrypt: $file"
    return 1
  fi
}

# Function to configure the plugin
sops-crypt-config() {
  echo "👀 Current SOPS Crypt configuration:"
  echo "File patterns: ${SOPS_CRYPT_FILE_PATTERNS[*]}"
  echo "Secret suffix: ${SOPS_CRYPT_SECRET_SUFFIX}"
  echo "Encrypted infix: ${SOPS_CRYPT_ENCRYPTED_INFIX}"
  echo "Ignore patterns: ${SOPS_CRYPT_IGNORE_PATTERNS[*]}"
  echo "Search tool: ${SOPS_CRYPT_SEARCH_TOOL}"
  echo "FD parameters: ${SOPS_CRYPT_FD_PARAMS}"
  echo "Find parameters: ${SOPS_CRYPT_FIND_PARAMS}"
  
  echo "\nℹ️ File naming examples:"
  echo "  Secret file:     config${SOPS_CRYPT_SECRET_SUFFIX}.yaml"
  echo "  Encrypted file:  config${SOPS_CRYPT_SECRET_SUFFIX}${SOPS_CRYPT_ENCRYPTED_INFIX}.yaml"
  
  echo "\n🔄 Available commands and options:"
  echo "  sops-encrypt-all [--force|-f] [directory]  - Encrypt all secret files (optionally forcing re-encryption)"
  echo "  sops-encrypt [--force|-f] <file>           - Encrypt a single file (optionally forcing re-encryption)"
  echo "  sops-decrypt-all [directory]               - Decrypt all encrypted files"
  echo "  sops-decrypt <file>                        - Decrypt a single file"
  
  echo "\n📑 Override configuration with environment variables:"
  echo "  export SOPS_CRYPT_FILE_PATTERNS=\"*.yaml *.json *.env\""
  echo "  export SOPS_CRYPT_SECRET_SUFFIX=\"-mysecret\""
  echo "  export SOPS_CRYPT_ENCRYPTED_INFIX=\".encrypted\""
  echo "  export SOPS_CRYPT_IGNORE_PATTERNS=\"node_modules .git dist\""
  echo "  export SOPS_CRYPT_SEARCH_TOOL=\"fd\"  # Options: auto, fd, find"
  echo "  export SOPS_CRYPT_FD_PARAMS=\"--type file --hidden --no-ignore\""
  echo "  export SOPS_CRYPT_FIND_PARAMS=\"-type f\""
  
  echo "\nTo modify the default configuration, edit the variables at the top of the plugin file."
}
