# JABAWS Docker Build

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

---

## 🧪 Example Commands

```bash
./quick-build.sh                               # Default quick build
./build.sh --clean --tag jabaws:v2.2           # Clean build with custom tag
./build.sh --platform linux/arm64              # ARM64 build
./dev-build.sh --fast --run                    # Dev: build & run
./dev-build.sh --logs                          # Show logs
```

---

## 🖥️ Platform Support

| Platform        | Default Target     | Notes                              |
|----------------|--------------------|------------------------------------|
| Apple Silicon  | `linux/arm64`      | Native ARM64 for optimal performance |
| Intel/AMD      | `linux/amd64`      | Native                            |
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
3. **runtime** – slim Tomcat with patched WAR

Ensures cross-platform builds and clean runtimes.

---

## ✅ Verified On
- macOS (Apple Silicon) via Docker Desktop
- Tomcat 8.5 with Java 8
- Included tools compiled per platform
