# WebGPU Implementation Guide

## Overview

This document describes the WebGPU rendering implementation for the Zig Particle Life Simulator. The WebGPU version provides GPU-accelerated rendering while keeping all simulation logic in Zig/WASM for optimal performance.

## Architecture

### Division of Labor

**Zig/WASM (Simulation Engine)**
- Particle physics calculations
- Force computations (attraction/repulsion)
- Spatial hash grid for efficient neighbor finding
- Collision detection and resolution
- Boundary handling (looping/bouncing)
- User interaction (mouse force application)

**JavaScript/WebGPU (Rendering Engine)**
- GPU buffer management
- Instanced particle rendering (16,384 particles in a single draw call)
- View-projection matrix calculations
- Camera controls (zoom/pan)
- WGSL shader compilation and execution

### Data Flow

```
1. Initialization:
   Zig allocates particle arrays in WASM linear memory
   ↓
2. Simulation Step:
   Zig updates particle positions/velocities
   ↓
3. Buffer Transfer:
   JavaScript reads particle data from WASM memory using typed arrays
   ↓
4. GPU Upload:
   device.queue.writeBuffer() transfers data to GPU buffers
   ↓
5. Rendering:
   WebGPU executes vertex/fragment shaders for all particles
```

## Implementation Details

### WGSL Shaders

The particle rendering uses a single shader module with:

**Vertex Shader (`vertexMain`)**:
- Receives instance ID for each particle
- Generates quad geometry (6 vertices = 2 triangles per particle)
- Transforms particle world position to clip space using view-projection matrix
- Passes color and UV coordinates to fragment shader

**Fragment Shader (`fragmentMain`)**:
- Renders circular particles with soft edges using distance fields
- Applies glow effect using `smoothstep` for alpha blending
- Brightness falloff toward edges for depth perception

### GPU Buffers

Three buffers are created and updated each frame:

1. **Particle Buffer** (Storage Buffer)
   - Size: `particleCount × 20 bytes`
   - Layout: `[x, y, vx, vy, species]` (5 × f32)
   - Usage: Read by vertex shader to position particles
   - Updated: Every frame from WASM memory

2. **Species Buffer** (Storage Buffer)
   - Size: `speciesCount × 16 bytes`
   - Layout: `[r, g, b, a]` (4 × f32)
   - Usage: Read by vertex shader to color particles
   - Updated: Every frame from WASM memory

3. **Uniform Buffer** (Uniform Buffer)
   - Size: `96 bytes` (required for alignment)
   - Layout: `mat4x4<f32>` (64 bytes) + `vec4<f32>` (16 bytes + padding)
   - Usage: View-projection matrix and particle size
   - Updated: Every frame based on camera state

### Uniform Buffer Alignment

**Important:** WebGPU has strict alignment requirements for uniform buffers. The uniform buffer must be at least 96 bytes due to struct alignment rules:

```javascript
// Correct: 96 bytes (24 floats)
const uniformData = new Float32Array(24);
uniformData.set(matrix, 0);      // 16 floats (mat4x4)
uniformData[16] = particleSize;  // 1 float
// uniformData[17-23] are padding
```

### Render Pipeline

The render pipeline uses:
- **Topology**: `triangle-list` (6 vertices per particle)
- **Instancing**: 1 instance per particle (16,384 instances)
- **Blending**: Additive blending for particle glow effects
  - Color: `src-alpha` + `one` = additive with transparency
  - Alpha: `one` + `one` = accumulate alpha

### View-Projection Matrix

Orthographic projection is used for 2D particle rendering:

```javascript
const matrix = new Float32Array(16);
matrix[0] = 2 / (right - left);
matrix[5] = 2 / (top - bottom);
matrix[10] = -2 / (far - near);
matrix[12] = -(right + left) / (right - left);
matrix[13] = -(top + bottom) / (top - bottom);
matrix[14] = -(far + near) / (far - near);
matrix[15] = 1;
```

This matrix includes camera zoom and pan transformations.

## Performance Characteristics

### Benchmark Results

- **Particle Count**: 16,384
- **Frame Rate**: ~12-15 FPS (in testing)
- **Draw Calls**: 1 per frame (instanced rendering)
- **Species Count**: 6

### Optimization Techniques

1. **Instanced Rendering**: All particles rendered in a single draw call
2. **Storage Buffers**: Direct GPU memory access for particle data
3. **Additive Blending**: No depth sorting required
4. **Spatial Binning**: O(n) collision detection in Zig (not O(n²))
5. **WASM Memory**: Zero-copy particle data access using typed arrays

## Browser Compatibility

### Supported Browsers

- **Chrome/Edge**: Version 113+ (full support)
- **Firefox**: Experimental (enable `dom.webgpu.enabled` in `about:config`)
- **Safari**: Technology Preview with WebGPU enabled

### Feature Detection

The application automatically detects WebGPU support:

```javascript
if (!navigator.gpu) {
    // Show error message, suggest Canvas 2D fallback
}
```

## Building

The build system automatically generates both Canvas 2D and WebGPU versions:

```bash
# Build both versions
zig build -Dtarget=wasm32-emscripten

# Output files:
# - web/particle-life.html (Canvas 2D)
# - web/particle-life-webgpu.html (WebGPU)
# - web/index.html (Landing page)
```

## Testing

To test the WebGPU version:

1. Start a local HTTP server:
   ```bash
   python -m http.server 8000 --directory web
   ```

2. Open in a WebGPU-enabled browser:
   ```
   http://localhost:8000/particle-life-webgpu.html
   ```

3. Check the browser console for any warnings/errors

## Troubleshooting

### Common Issues

**1. Black Screen (No Particles)**
- **Cause**: Uniform buffer size mismatch
- **Solution**: Ensure uniform buffer is 96 bytes (not 80)

**2. Validation Errors**
- **Cause**: Buffer size or alignment issues
- **Solution**: Check console for WebGPU validation messages

**3. Low FPS**
- **Cause**: Too many particles or slow GPU
- **Solution**: Reduce particle count using slider

**4. WebGPU Not Supported**
- **Cause**: Browser doesn't support WebGPU
- **Solution**: Use Canvas 2D fallback version

## Future Enhancements

Potential improvements for the WebGPU version:

1. **Compute Shaders**: Move force calculations to GPU
2. **Indirect Drawing**: GPU-driven particle culling
3. **Bloom Post-Processing**: GPU-based glow effects
4. **Particle Trails**: GPU-computed motion blur
5. **Spatial Hashing on GPU**: Binning in compute shader

## Code Structure

```
web/
├── shell-webgpu.html         # WebGPU implementation
│   ├── WGSL Shaders          # Embedded vertex/fragment shaders
│   ├── WebGPU Initialization # Device, pipeline, buffer setup
│   ├── Buffer Management     # WASM → GPU data transfer
│   ├── Render Loop          # Animation frame callback
│   └── Event Handlers       # Mouse, keyboard, UI controls
└── index.html               # Landing page with version selection
```

## References

- [WebGPU Specification](https://www.w3.org/TR/webgpu/)
- [WGSL Specification](https://www.w3.org/TR/WGSL/)
- [WebGPU Samples](https://webgpu.github.io/webgpu-samples/)
- [Zig Language Reference](https://ziglang.org/documentation/master/)

## Credits

- Original WebGPU concept: [@lisyarus](https://lisyarus.github.io/blog)
- Zig implementation: Optimized recreation using Zig + WebAssembly
- WebGPU port: GPU-accelerated rendering while keeping Zig simulation

## License

MIT License - See main README for details

