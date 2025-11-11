# Zig Particle Life Simulator (WebAssembly + Emscripten + WebGPU)

A WebAssembly-based particle life simulator written in Zig 0.15, compiled with Emscripten. This project features both Canvas 2D and WebGPU rendering backends, with all simulation logic written in Zig for optimal performance.

## Overview

Particle Life is an emergent behavior simulation where different particle species interact based on attraction/repulsion forces. This implementation uses Zig targeting WebAssembly via Emscripten to run in the browser.

## Features

- **Dual Rendering Backends**:
  - **WebGPU**: Modern GPU-accelerated rendering with instanced drawing
  - **Canvas 2D**: Classic CPU rendering for maximum browser compatibility
- **Multiple particle species** with configurable interaction forces
- **Spatial partitioning** using a grid-based binning system for efficient collision detection
- **Zig-powered simulation**: All physics and force calculations run in optimized Zig/WASM
- **Configurable simulation parameters**:
  - Particle count and species count
  - Friction and central forces
  - Looping vs bouncing borders
  - Symmetric or asymmetric force rules
- **Interactive controls**:
  - Mouse/touch interaction to apply forces
  - Pan and zoom camera
  - Pause/resume simulation
- **Optimized for size** using ReleaseSmall mode

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

The build will generate two versions:

**Canvas 2D Version:**
- `web/particle-life.html` - Canvas 2D HTML page
- `web/particle-life.wasm` - WebAssembly binary  
- `web/particle-life.js` - JavaScript glue code

**WebGPU Version:**
- `web/particle-life-webgpu.html` - WebGPU HTML page
- `web/particle-life-webgpu.wasm` - WebAssembly binary
- `web/particle-life-webgpu.js` - JavaScript glue code

**Entry Point:**
- `web/index.html` - Landing page to choose between versions

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
http://localhost:8000/index.html          # Landing page (choose version)
http://localhost:8000/particle-life-webgpu.html  # WebGPU version (recommended)
http://localhost:8000/particle-life.html         # Canvas 2D version (compatible)
```

**Note:** You must use an HTTP server. Opening the HTML file directly (`file://`) won't work due to CORS restrictions on WebAssembly modules.

### WebGPU Requirements

The WebGPU version requires a browser with WebGPU support:
- **Chrome/Edge**: Version 113 or later
- **Firefox**: Experimental support (enable `dom.webgpu.enabled` in `about:config`)
- **Safari**: Technology Preview with WebGPU enabled

If WebGPU is not available, use the Canvas 2D fallback version.

## Architecture

### Separation of Concerns

This implementation cleanly separates simulation logic from rendering:

**Zig/WASM (Simulation)**:
- Particle physics calculations
- Force computations (attraction/repulsion)
- Spatial hash grid for neighbor finding
- Collision detection and resolution
- Boundary handling (looping/bouncing)
- User interaction (mouse forces)

**JavaScript (Rendering)**:
- **Canvas 2D**: CPU-based 2D drawing for maximum compatibility
- **WebGPU**: GPU-accelerated instanced rendering with WGSL shaders
- GPU buffer management (WebGPU only)
- View-projection matrix calculations
- Camera controls (zoom/pan)

### Data Flow (WebGPU Version)

1. **Initialization**: Zig allocates particle arrays in WASM memory
2. **Simulation Step**: Zig updates particle positions/velocities
3. **Buffer Transfer**: JavaScript reads particle data from WASM memory using typed arrays
4. **GPU Upload**: Data is written to GPU storage buffers via `device.queue.writeBuffer()`
5. **Rendering**: WebGPU executes WGSL shaders with instanced rendering (16,384+ particles in 1 draw call)

This design keeps the heavy computational work in optimized Zig code while leveraging the GPU for parallel rendering.

### Why This Approach?

- **Performance**: Zig is faster than JavaScript for simulation, GPU is faster for rendering
- **Portability**: Same Zig code works for both rendering backends
- **Maintainability**: Clear separation of concerns
- **Optimization**: Each component uses the best tool for the job

See [`WEBGPU_IMPLEMENTATION.md`](WEBGPU_IMPLEMENTATION.md) for detailed technical documentation.

## Project Structure

```
.
├── build.zig              # Build configuration with deploy step
├── build.zig.zon          # Package dependencies
├── src/
│   ├── main.zig          # Main particle simulator implementation
│   └── root.zig          # Library exports (if any)
└── web/                   # Web assets and deployed WASM
    ├── index.html        # Landing page (choose renderer)
    ├── shell.html        # Canvas 2D shell template
    ├── shell-webgpu.html # WebGPU shell template
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

### Canvas 2D Performance
- 16,384 particles @ 30-40 FPS on modern hardware
- ~100KB WASM binary size (gzipped)
- Works on all modern browsers
- CPU-based rendering

### WebGPU Performance
- 16,384 particles @ 50-60 FPS on modern hardware
- ~100KB WASM binary size (gzipped)
- Requires WebGPU support (Chrome 113+)
- GPU-accelerated rendering with instancing
- Single draw call per frame

**Memory Usage (Both Versions)**:
- 128MB initial memory (64MB heap + code + stack + runtime)

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

## Choosing a Version

### Canvas 2D vs WebGPU - Which Should You Use?

| Feature                | Canvas 2D         | WebGPU            |
|------------------------|-------------------|-------------------|
| **Browser Support**    | ✅ All modern     | ⚠️ Chrome 113+    |
| **Performance**        | Good (30-40 FPS)  | Excellent (50-60 FPS) |
| **Visual Quality**     | Good              | Excellent (GPU effects) |
| **Fallback**           | N/A               | Use Canvas 2D     |
| **Best For**           | Compatibility     | Best experience   |

**Recommendation**: 
- Use **WebGPU** if you have Chrome 113+ or Edge 113+ for the best experience
- Use **Canvas 2D** if you need maximum browser compatibility
- The landing page (`index.html`) automatically detects WebGPU support

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

