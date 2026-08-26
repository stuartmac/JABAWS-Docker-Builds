# JABAWS Docker Build

> TL;DR: Run `./quick-build.sh` to build locally, or  
> `./multi-platform-build.sh --tag youruser/jabaws:latest` to build and push a cross-platform image.

A comprehensive, multi-architecture Docker build system for JABAWS (Java Bioinformatics Analysis Web Services).

---

## 🚀 Quick Start

### Recommended:
```bash
./quick-build.sh
```

### Alternatives:
```bash
./build.sh --tag jabaws:latest                              # Full control
./dev-build.sh --fast --run                                 # Dev workflow
./multi-platform-build.sh --tag myregistry/jabaws:latest    # Multi-platform
```

---

## 🛠️ Build Scripts Overview

### `quick-build.sh`
One-command build with sensible defaults.

### `build.sh`
Full-featured build with options:
```bash
./build.sh [OPTIONS]
  -p, --platform <arch>   Target platform (e.g., linux/amd64)
  -t, --tag <tag>         Image tag (default: jabaws:latest)
  -c, --clean             Clean build (re-download dependencies)
  -n, --no-cache          Build without cache
  -d, --deps-only         Prepare dependencies only
  -v, --verbose           Verbose output
      --skip-deps         Skip dependency steps
      --push              Push image after build
      --multi-platform    Build for both AMD64 and ARM64
```

### `dev-build.sh`
Fast iteration and dev support:

```bash
./dev-build.sh [OPTIONS]
  -f, --fast     Use cache, skip checks
  -r, --run      Run after build
  -s, --stop     Stop running container
      --logs     Show container logs
```

### `multi-platform-build.sh`
Cross-architecture builds for registries:

```bash
./multi-platform-build.sh [OPTIONS]
  -t, --tag TAG          Image tag (required for registry)
  -c, --clean            Clean build
  -n, --no-cache         No cache
  -v, --verbose          Verbose output
      --registry REG     Registry prefix
      --check-only       Check prerequisites only
```

---

## 🧪 Example Commands

```bash
./quick-build.sh                               # Default quick build
./build.sh --clean --tag jabaws:v2.2           # Clean build with custom tag
./build.sh --platform linux/arm64              # ARM64 build
./dev-build.sh --fast --run                    # Dev: build & run
./dev-build.sh --logs                          # Show logs

# Multi-platform builds (requires registry push)
./multi-platform-build.sh --tag myuser/jabaws:latest
./build.sh --multi-platform --push --tag myuser/jabaws:v2.2
```

---

## 🌐 Multi-Platform Builds

Build Docker images that work on both Intel/AMD and Apple Silicon architectures:

### Prerequisites for Multi-Platform Builds:
- Docker with Buildx support (included in Docker Desktop)
- Access to a Docker registry (Docker Hub, GitHub Container Registry, etc.)
- Registry authentication (`docker login`)

### Quick Multi-Platform Build:
```bash
# Check prerequisites
./multi-platform-build.sh --check-only

# Build and push to Docker Hub
docker login
./multi-platform-build.sh --tag yourusername/jabaws:latest

# Build and push to GitHub Container Registry  
docker login ghcr.io
./multi-platform-build.sh --tag ghcr.io/yourusername/jabaws:latest
```

### Using the Main Build Script:
```bash
# Multi-platform build (requires --push)
./build.sh --multi-platform --push --tag yourusername/jabaws:latest
```

### Benefits:
- **Universal compatibility**: Single image tag works on both architectures
- **Automatic selection**: Docker automatically pulls the correct architecture
- **Performance optimized**: Native compilation for each platform
- **Simple deployment**: Same `docker run` command works everywhere

---

## 🖥️ Platform Support

| Platform        | Default Target     | Notes                              |
|----------------|--------------------|------------------------------------|
| Apple Silicon  | `linux/arm64`      | Native ARM64 for optimal performance |
| Intel/AMD      | `linux/amd64`      | Native                            |
| Multi-Platform | `amd64` + `arm64`  | Universal image (requires registry) |
| Override       | Any supported arch | Use `--platform` option            |

> Performance: Native ARM64 builds on Apple Silicon provide significantly better performance than emulated AMD64.

---

## ▶️ Running the Container

```bash
docker run -p 8080:8080 jabaws:latest                      # Standard
docker run -d --name jabaws-dev -p 8080:8080 jabaws:latest # Named
open http://localhost:8080/jabaws                         # Access
```

---

## 🔧 Build Architecture

Multi-stage Docker approach:
1. **tool-builder** – compiles native bioinformatics tools
2. **war-patcher** – injects binaries into the WAR file
3. **runtime** – Tomcat 9.0.107 with Java 8 (JABAWS compatibility)

Ensures cross-platform builds and clean runtimes.

---

## 🧰 Container Engine

The scripts run under either Podman or Docker, preferring Podman when both are
present. Override with `CONTAINER_ENGINE=docker ./build.sh`. The one exception is
`multi-platform-build.sh`, which needs Docker Buildx to assemble a multi-arch
manifest; a host building for itself doesn't need it.

To build and deploy on a server — proxies, short-name resolution, systemd — see
[deploy/README.md](deploy/README.md).

## ✅ Verified On
- macOS (Apple Silicon) via Docker Desktop
- RHEL 9 (x86_64) with rootless Podman 5.8
- Tomcat 9.0.107 with Java 8 (JABAWS compatibility)
- Included tools compiled per platform
