

## Running JABAWS on Apple Silicon (M1/M2/M4 Macs)

This project includes a working **AMD64** Docker image that runs on Apple Silicon Macs (e.g. M4) using Docker Desktop’s built-in emulation (Rosetta or QEMU).

### ✅ Tested Working On:
- **macOS (Apple Silicon)** with Docker Desktop
- **Tomcat 8.5** with Java 8
- Precompiled **T-Coffee** binary (AMD64)

---

### 🔧 How to Build and Run the AMD64 Image

```bash
# Build the container using AMD64 architecture
docker build --platform=linux/amd64 -t jabaws-amd64 .

# Run it, mapping container port 8080 to localhost:8080
docker run --platform=linux/amd64 -p 8080:8080 jabaws-amd64
```

> **Note:** Docker Desktop may show a warning ("⚠️ amd64") — this is expected. The container still works correctly under emulation.