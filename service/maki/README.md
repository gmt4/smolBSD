# 🍣 Maki service

## About

This service runs [maki](https://github.com/tontinton/maki), a Rust-based terminal coding agent. There is no NetBSD binary in the maki releases, so the image builds it from source (a ~600-crate cargo build, following the FreeBSD port). maki runs inside `tmux` under a PTY console, ready to work on the project directory you mount.

## Prerequisites

- [smolBSD](https://github.com/NetBSDfr/smolBSD): `git clone https://github.com/NetBSDfr/smolBSD`
- A maki `init.lua` configuration file (see [maki docs](https://github.com/tontinton/maki))
- At least 1GB of memory recommended at runtime

## Usage

### 🔨 Build the image

The cargo build is heavy (30 tree-sitter grammars, luau JIT, static curl/openssl). Build with plenty of memory:

```sh
$ ./smoler.sh build -y BUILDMEM=8192 BUILDCPUS=4 smolerfiles/SMOLerfile.maki
```

Pin a specific maki version if needed:

```sh
$ ./smoler.sh build -y --build-arg MAKI_VERSION=0.5.3 BUILDMEM=8192 BUILDCPUS=4 smolerfiles/SMOLerfile.maki
```

**Or** pull the pre-built image (built by CI for both architectures):

Linux:
```sh
$ ./smoler.sh pull maki-amd64:latest
```

Mac or any `arm64` machine:
```sh
$ ./smoler.sh pull maki-evbarm-aarch64:latest
```

### ⚡ Quick start (config from the project directory)

Linux:
```sh
$ ./smoler.sh run maki-amd64:latest -m 2048 -w /path/to/project
```

Mac or any `arm64` machine:
```sh
$ ./smoler.sh run maki-evbarm-aarch64:latest -m 2048 -w /path/to/project
```

`/path/to/project` is mounted in the microvm at `/mnt`. There are three ways to get a maki config into the VM, in order of precedence:

1. Drop an `init.lua` in the shared directory (copied from `/mnt/init.lua` or `/mnt/.maki/init.lua`)
2. Pass a config file from the host with `-E makiconf=/path/to/init.lua` (delivered via QEMU fw_cfg)
3. Put a `.maki/init.lua` in the project directory itself (picked up by maki directly)

No config is found at boot: the VM drops to a `ksh` shell with a hint about the options above.

### 📋 Flags

| Flag | Description |
|------|-------------|
| `-m <mb>` | Memory to allocate (default: 512) |
| `-E makiconf=<path>` | Pass a config file directly to the guest |
| `-w <path>` | Mount a directory at `/mnt` inside the microvm |

### ⚙️ Extra config files

If the shared directory contains a `share/maki/` subdirectory, its contents are copied into maki's config dir (`~/.config/maki/`) at first launch, alongside `init.lua`, useful for keeping additional config files (e.g. `own.toml`) in the project.

### ⌨️ Session flow

On a fresh launch with a valid config, the console shows:

```
🪟 maki runs inside tmux with prefix ^b

⌨️  Press enter to start the session
```

Press **enter**: maki starts in a new tmux session (prefix `^b`, vi mode keys, bash as default shell).

## Exiting

When shutting down the microvm, use **Ctrl-A Ctrl-X** to exit.
