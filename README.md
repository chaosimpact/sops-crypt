# SOPS Crypt ZSH Plugin

A ZSH plugin for Mozilla SOPS that provides one-click encryption and decryption of files in the current directory and subdirectories.

## Requirements

- [SOPS](https://github.com/mozilla/sops) must be installed and configured
- [fd](https://github.com/sharkdp/fd) optional but recommended for faster file searching.

## Features

- Automatically detect and encrypt/decrypt files using standardized naming patterns
- One-click encryption/decryption for all matching files in a directory and subdirectories
- Single file encryption/decryption with validation
- File naming convention: `config-secret.yaml` → `config-secret.enc.yaml` 
- Flexible file search using either `find` or `fd` command
- Environment variable configuration for easy customization

## Installation

### Manual Installation

```zsh
# Clone repository
git clone https://github.com/yourusername/sops-crypt ~/.oh-my-zsh/custom/plugins/sops-crypt

# Add to plugins list in .zshrc
plugins=(... sops-crypt)
```

### Using a ZSH Plugin Manager

#### Oh My Zsh

Add to your `.zshrc`:

```zsh
plugins=(... sops-crypt)
```

#### Antigen

```zsh
antigen bundle yourusername/sops-crypt
```

## Usage

The plugin provides the following commands:

- `sops-encrypt-all [directory]` - Encrypt all matching files in directory and subdirectories
- `sops-decrypt-all [directory]` - Decrypt all encrypted files in directory and subdirectories
- `sops-encrypt <file>` - Encrypt a single file
- `sops-decrypt <file>` - Decrypt a single file
- `sops-crypt-config` - Show current configuration

### File Naming Convention

The plugin uses a specific naming convention:
- Secret files: `config-secret.yaml`
- Encrypted files: `config-secret.enc.yaml`

Only files that follow these naming patterns will be automatically detected for encryption/decryption.

### Examples

```zsh
# Create a new secret file
echo "password: mysecret123" > config-secret.yaml

# Encrypt all matching files in current directory and subdirectories
sops-encrypt-all

# Encrypt all matching files in specific directory
sops-encrypt-all ./configs

# Decrypt all encrypted files in current directory and subdirectories
sops-decrypt-all

# Encrypt a single file
sops-encrypt secrets-secret.yaml

# Decrypt a single file
sops-decrypt secrets-secret.enc.yaml
```

## Configuration

### Default Configuration

The plugin comes with the following default settings:

| Parameter | Default Value | Description |
|-----------|---------------|-------------|
| `SOPS_CRYPT_FILE_PATTERNS` | `*.yaml *.yml *.json *.env *.txt` | File patterns to match |
| `SOPS_CRYPT_SECRET_SUFFIX` | `-secret` | Suffix for files to be encrypted |
| `SOPS_CRYPT_ENCRYPTED_INFIX` | `.enc` | Infix for encrypted files |
| `SOPS_CRYPT_IGNORE_PATTERNS` | `node_modules .git .svn .hg` | Patterns to ignore |
| `SOPS_CRYPT_SEARCH_TOOL` | `auto` | Search tool to use (`auto`, `fd`, or `find`) |
| `SOPS_CRYPT_FD_PARAMS` | `--type file --hidden -g` | Parameters for `fd` command |
| `SOPS_CRYPT_FIND_PARAMS` | `-type f` | Parameters for `find` command |

### Environment Variable Configuration

You can override the default settings by using environment variables with the same names as the parameters in the table above. The environment variables will take precedence over the default settings when the plugin is loaded.

We recommend using [direnv](https://direnv.net/) to manage project-specific environment variables. With direnv, you can create a `.envrc` file in your project directory:

```zsh
# Example .envrc file
export SOPS_CRYPT_FILE_PATTERNS="*.yaml *.json *.env"
export SOPS_CRYPT_SECRET_SUFFIX="-mysecret"
export SOPS_CRYPT_IGNORE_PATTERNS="node_modules .git dist build"
export SOPS_CRYPT_SEARCH_TOOL="fd"
```

This approach allows you to have different settings for different projects, and direnv automatically loads and unloads these environment variables when you enter and exit the project directory.

### Search Tool Configuration

The plugin supports two search tools:
- `fd`: A modern and faster alternative to `find`
- `find`: The traditional Unix find command

By default, the plugin will use `fd` if available, and fall back to `find` otherwise. You can control this behavior with the following settings:

- `auto`: Automatically use `fd` if available, otherwise fall back to `find` (default)
- `fd`: Use `fd` exclusively (will fall back to `find` if `fd` is not installed)
- `find`: Always use `find`

## View Current Configuration

To check your current configuration:

```zsh
sops-crypt-config
```

This will show:
- Current file patterns
- Secret suffix setting
- Encrypted infix setting
- Ignore patterns
- Example file naming
- How to override with environment variables

## License

MIT
