# Zig Particle Life Simulator (WebAssembly + WebGPU)

A WebAssembly-based particle life simulator written in Zig 0.15, compiled with Emscripten. This project uses WebGPU for GPU-accelerated rendering, with all simulation logic written in Zig for optimal performance.

## Overview

Particle Life is an emergent behavior simulation where different particle species interact based on attraction/repulsion forces. This implementation uses Zig targeting WebAssembly via Emscripten to run in the browser.

## Features

- **GPU-Accelerated Rendering**: WebGPU-powered instanced rendering for high performance
- **Multiple particle species** with configurable interaction forces
- **Spatial partitioning** using a grid-based binning system for efficient collision detection
- **Zig-powered simulation**: All physics and force calculations run in optimized Zig/WASM
- **Configurable simulation parameters**:
  - Particle count and species count (up to 16,384+ particles)
  - Friction and central forces
  - Looping vs bouncing borders
  - Symmetric or asymmetric force rules
- **Interactive controls**:
  - Mouse/touch interaction to apply forces
  - Pan and zoom camera
  - Pause/resume simulation
- **Optimized for size** using ReleaseSmall mode (~100KB gzipped WASM)

## Prerequisites

- **Zig 0.15** or later - [Download here](https://ziglang.org/download/)
- **Git** (for automatic emsdk download on Windows)
- **Python 3** for local testing server
- **Emscripten SDK** - Auto-installed on Windows, manual install on Linux/macOS (see below)

## Building

This project uses Zig to compile to WebAssembly, then Emscripten to link and generate the final web assets.

### Build Approach

We use a **two-step build process**:
1. Zig compiles the code to a static library (`.a` file)
2. Emscripten's `emcc` links it into WebAssembly and generates the HTML/JS glue code

This approach avoids compatibility issues with Zig's standard library on the `wasm32-emscripten` target.

### Quick Start (Windows) - Automatic Setup! 🎉

On Windows, the build script will **automatically download and install Emscripten** for you:

```bash
# Just run this - no manual setup needed!
zig build -Dtarget=wasm32-emscripten

# Or with size optimization (recommended)
zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseSmall
```

The first build will:
1. Clone the emsdk repository into your project directory
2. Install the latest Emscripten SDK
3. Activate it automatically
4. Build your project

**Note:** The `emsdk/` directory is added to `.gitignore` and won't be committed.

### Manual Setup (Linux/macOS)

For Linux and macOS, manual Emscripten installation is currently required:

```bash
# Clone emsdk
git clone https://github.com/emscripten-core/emsdk.git
cd emsdk

# Install and activate
./emsdk install latest
./emsdk activate latest

# Build with explicit sysroot
zig build -Dtarget=wasm32-emscripten --sysroot ~/emsdk/upstream/emscripten

# With optimization
zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseSmall --sysroot ~/emsdk/upstream/emscripten
```

> 💡 **TODO:** Automatic setup for Linux/macOS will be added in a future update.

### Build Output

The build will generate:
- `web/particle-life.html` - Main HTML page with WebGPU rendering
- `web/particle-life.wasm` - WebAssembly binary  
- `web/particle-life.js` - JavaScript glue code
- `web/index.html` - Entry point (redirects to particle-life.html)

## Running Locally

Start a local HTTP server to test the application:

```bash
# From the project root, using Python 3
python -m http.server 8000 --directory web

# Or using Python 2
cd web && python -m SimpleHTTPServer 8000
```

Then open your browser to:
```
http://localhost:8000/
```

**Note:** You must use an HTTP server. Opening the HTML file directly (`file://`) won't work due to CORS restrictions on WebAssembly modules.

### Browser Requirements

This simulator requires a browser with WebGPU support:
- **Chrome/Edge**: Version 113 or later ✅
- **Firefox**: Experimental support (enable `dom.webgpu.enabled` in `about:config`) 🧪
- **Safari**: Technology Preview with WebGPU enabled 🧪

If your browser doesn't support WebGPU, you'll see an error message with instructions.

## Architecture

### Separation of Concerns

This implementation cleanly separates simulation logic from rendering:

**Zig/WASM (Simulation Engine)**:
- Particle physics calculations
- Force computations (attraction/repulsion)
- Spatial hash grid for O(n) neighbor finding
- Collision detection and resolution
- Boundary handling (looping/bouncing)
- User interaction (mouse forces)

**JavaScript/WebGPU (Rendering Engine)**:
- GPU buffer management
- Instanced particle rendering (16,384+ particles in 1 draw call)
- WGSL shader compilation and execution
- View-projection matrix calculations
- Camera controls (zoom/pan)

### Data Flow

```
1. Initialization
   ↓
   Zig allocates particle arrays in WASM linear memory
   
2. Each Frame
   ↓
   Zig: Update particle positions/velocities (physics simulation)
   ↓
   JavaScript: Read particle data from WASM memory (zero-copy via typed arrays)
   ↓
   WebGPU: Upload data to GPU buffers (device.queue.writeBuffer)
   ↓
   WebGPU: Execute WGSL shaders with instanced rendering
```

### Why This Approach?

- **Performance**: Zig optimizes simulation, WebGPU parallelizes rendering
- **Maintainability**: Clear separation between physics and graphics
- **Scalability**: Can handle 16,384+ particles at 60 FPS
- **Modern**: Leverages cutting-edge WebGPU API

See [`WEBGPU_IMPLEMENTATION.md`](WEBGPU_IMPLEMENTATION.md) for detailed technical documentation.

## Project Structure

```
.
├── build.zig              # Build configuration with WebGPU
├── build.zig.zon          # Package dependencies
├── src/
│   ├── main.zig          # Main particle simulator (Zig/WASM)
│   └── root.zig          # Library exports
└── web/                   # Web assets and deployed WASM
    ├── index.html        # Entry point (redirect)
    ├── shell.html        # WebGPU shell template with WGSL shaders
    ├── blue-noise.png    # Dithering texture
    ├── favicon.ico
    └── nikita_demo/      # Original WebGPU reference implementation
```

## Simulation Architecture

### Particle Structure
Each particle has:
- Position (x, y)
- Velocity (vx, vy)
- Species ID

### Force Calculation
Forces between particles are computed based on:
- **Attraction/Repulsion strength**: Can be positive (attraction) or negative (repulsion)
- **Interaction radius**: Maximum distance for force application
- **Collision force**: Strong short-range repulsion to prevent overlap

### Spatial Optimization
The simulation uses a spatial hash grid (binning) to avoid O(n²) particle comparisons:
1. Divide space into grid cells
2. Assign each particle to a cell
3. Only check interactions with particles in neighboring cells

### Integration
Uses semi-implicit Euler integration:
1. Compute forces on all particles
2. Update velocities: v += (F/m) * dt + friction
3. Update positions: x += v * dt
4. Handle boundary conditions (wrap or bounce)

## Performance

The WASM binary is optimized for size using:
- `-Doptimize=ReleaseSmall` flag
- Minimal external dependencies
- Efficient memory layout (custom bump allocator)
- Freestanding approach (no std library overhead)

### Benchmark Results
- **Particle Count**: 16,384 (configurable up to 65,536)
- **Frame Rate**: 50-60 FPS on modern hardware
- **WASM Binary**: ~100KB gzipped
- **Draw Calls**: 1 per frame (instanced rendering)
- **Memory Usage**: 128MB initial (64MB heap + runtime)

### Optimization Techniques
1. **Zig Simulation**: Fast native-speed physics in WASM
2. **Spatial Binning**: O(n) collision detection (not O(n²))
3. **Instanced Rendering**: All particles in single GPU draw call
4. **Storage Buffers**: Direct GPU memory access
5. **Additive Blending**: No depth sorting required

## Configuration

The simulator can be configured via URL parameters or UI controls:

- `particleCount`: Number of particles (default: 16384)
- `speciesCount`: Number of particle species (default: 6)
- `friction`: Velocity damping (default: 10.0)
- `centralForce`: Force pulling toward center (default: 0.0)
- `symmetricForces`: Mirror forces between species (default: false)
- `loopingBorders`: Wrap vs bounce at edges (default: false)
- `seed`: Random seed for force generation
- `width`, `height`: Simulation area size

## Controls

### Keyboard
- `Space`: Pause/Resume simulation
- `C`: Center view
- `S`: Show/Hide settings panel
- `D`: Show/Hide debug panel (if available)

### Mouse
- `Left Click + Drag`: Apply force to particles
- `Right Click + Drag`: Pan camera
- `Scroll Wheel`: Zoom in/out

### Touch
- `Single Touch`: Pan camera
- `Double Tap + Drag`: Apply force to particles
- `Two-Finger Pinch`: Zoom
- `Three-Finger Tap`: Toggle settings panel

## Development

### Running Tests

```bash
zig build test
```

### Build Options

All builds require the `--sysroot` flag pointing to your Emscripten installation:

```bash
# Debug build (larger, with debug symbols)
zig build -Dtarget=wasm32-emscripten -Doptimize=Debug --sysroot [path-to-emsdk]/upstream/emscripten

# Release with safety checks
zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseSafe --sysroot [path-to-emsdk]/upstream/emscripten

# Maximum performance (larger binary)
zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseFast --sysroot [path-to-emsdk]/upstream/emscripten

# Minimum size (recommended)
zig build -Dtarget=wasm32-emscripten -Doptimize=ReleaseSmall --sysroot [path-to-emsdk]/upstream/emscripten
```

### Native Build (for testing Zig code without WASM)

You can also build and run natively for quick iteration:

```bash
# Build and run natively
zig build run

# Run tests
zig build test
```

## Technical Highlights

### WebGPU Rendering Pipeline

This simulator showcases modern web graphics techniques:

| Component              | Technology         | Purpose                          |
|------------------------|--------------------|----------------------------------|
| **Simulation**         | Zig/WASM          | Physics calculations             |
| **Rendering**          | WebGPU            | GPU-accelerated drawing          |
| **Shaders**            | WGSL              | Vertex/fragment programs         |
| **Geometry**           | Instanced Quads   | Efficient particle rendering     |
| **Blending**           | Additive          | Glow effects                     |
| **Buffers**            | Storage + Uniform | Direct GPU data access           |

**Key Features**:
- Zero-copy data transfer from WASM to WebGPU via typed arrays
- Single instanced draw call renders all 16,384 particles
- Soft particle rendering with distance fields
- Real-time simulation at 60 FPS

## Documentation

- [`WEBGPU_IMPLEMENTATION.md`](WEBGPU_IMPLEMENTATION.md) - Detailed WebGPU technical guide
- [`WEBGPU_PORT_SUMMARY.md`](WEBGPU_PORT_SUMMARY.md) - Port summary and results
- [`BUILD_NOTES.md`](BUILD_NOTES.md) - Build system notes

## Credits

- Original WebGPU implementation by [@lisyarus](https://lisyarus.github.io/blog)
- Zig implementation: Optimized recreation using Zig + Emscripten
- WebGPU port: GPU-accelerated rendering with Zig simulation

## License

MIT License - See original implementation for attribution requirements.

## References

- [Particle Life phenomenon](https://www.youtube.com/watch?v=p4YirERTVF0)
- [Zig Programming Language](https://ziglang.org)
- [Emscripten](https://emscripten.org)
- [WebAssembly](https://webassembly.org)
- [WebGPU Specification](https://www.w3.org/TR/webgpu/)

