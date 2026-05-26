# 💘 Crush service

## About

This service runs [crush](https://github.com/charmbracelet/crush), an AI-powered terminal assistant built by Charmbracelet. It provides a fully configured NetBSD microvm with crush pre-installed and ready to use.

## Prerequisites

- A `crush.json` configuration file (an example is included in this repository, or see [crush docs](https://github.com/charmbracelet/crush))
- At least 512MB of memory recommended

## Usage

### 🔨 Build the image

```sh
$ ./smoler.sh build -y smolerfiles/Dockerfile.crush
```

**Or** pull the pre-built image:

Linux:
```sh
$ ./smoler.sh pull crush-amd64:latest
```

Mac or any `arm64` machine:
```sh
$ ./smoler.sh pull crush-evbarm-aarch64:latest
```

### ⚡ Quick start (config via command line)

Linux:
```sh
$ ./smoler.sh run crush-amd64:latest -m 1024 -E crush=/path/to/crush.json -w /path/to/project
```

Mac or any `arm64` machine:
```sh
$ ./smoler.sh run crush-evbarm-aarch64:latest -m 1024 -E crush=/path/to/crush.json -w /path/to/project
```

Passes the config file from the host directly to the guest with `-E`, and the path for the project file you want `crush` to work on, it will be mounted in the microvm `/mnt` directory.  
You can also create a `crush.json` file in the project directory instead of passing it with `-E`.

### 📋 Flags

| Flag | Description |
|------|-------------|
| `-m <mb>` | Memory to allocate (default: 512) |
| `-E crush=<path>` | Pass a config file directly to the guest |
| `-w <path>` | Mount a directory at `/mnt` inside the microvm |


## Exiting

When shutting down the microvm, use **Ctrl-A Ctrl-X** to exit.
