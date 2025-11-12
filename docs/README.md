# Documentation Index

This directory contains comprehensive documentation for the Zig Particle Life WebAssembly project.

## Quick Start

**Want to optimize performance?**  
Start with: [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)

**Want to understand the build system?**  
Read: [BUILD_OPTIMIZATION_GUIDE.md](BUILD_OPTIMIZATION_GUIDE.md)

---

## Document Overview

### Performance & Optimization

1. **[IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)** - START HERE
   - What was implemented (SIMD, build optimizations)
   - Why threading was NOT implemented
   - Performance analysis and benchmarks
   - Testing instructions

2. **[OPTIMIZATION_ANALYSIS.md](OPTIMIZATION_ANALYSIS.md)**
   - Zig vs JavaScript computation distribution
   - Size optimization opportunities
   - Performance improvement strategies
   - Code health assessment

3. **[SIMD_IMPLEMENTATION.md](SIMD_IMPLEMENTATION.md)**
   - Detailed SIMD code examples
   - How to vectorize force computation
   - Browser compatibility
   - Compile-time flags

4. **[BUILD_OPTIMIZATION_GUIDE.md](BUILD_OPTIMIZATION_GUIDE.md)**
   - Build commands for different scenarios
   - Optimization flags explained
   - Expected file sizes
   - Deployment checklist

### Implementation Details

5. **[WEBGPU_IMPLEMENTATION.md](WEBGPU_IMPLEMENTATION.md)**
   - WebGPU shader details
   - Rendering pipeline
   - HDR and tonemapping
   - Instanced rendering

6. **[BINNING_FIX.md](BINNING_FIX.md)**
   - Spatial partitioning implementation
   - Bug fixes and improvements
   - Performance impact of binning
   - Visual artifact fixes

7. **[BUGFIXES.md](BUGFIXES.md)**
   - List of bugs fixed
   - Root cause analysis
   - Solutions implemented

### Project Information

8. **[FEATURE_PARITY.md](FEATURE_PARITY.md)**
   - Features implemented vs original
   - Zig-specific improvements
   - Missing features (if any)

9. **[WEBGPU_PORT_SUMMARY.md](WEBGPU_PORT_SUMMARY.md)**
   - Project status and overview
   - Browser compatibility
   - Key features
   - Architecture decisions

10. **[BUILD_NOTES.md](BUILD_NOTES.md)**
    - Build system setup
    - Platform-specific notes
    - Troubleshooting

11. **[EMSDK_AUTO_SETUP.md](EMSDK_AUTO_SETUP.md)**
    - Automatic Emscripten SDK installation
    - Windows, Linux, macOS instructions
    - Manual setup fallback

---

## Common Tasks

### Building the Project

**Standard Build (SIMD Always Enabled):**
```bash
zig build -Dtarget=wasm32-emscripten
```

**For Smallest Size:**
```bash
# Edit build.zig to change preferred_optimize_mode from ReleaseFast to ReleaseSmall
zig build -Dtarget=wasm32-emscripten
```

Note: SIMD is always enabled for maximum performance. It automatically falls back to scalar code on older browsers.

See [BUILD_OPTIMIZATION_GUIDE.md](BUILD_OPTIMIZATION_GUIDE.md) for details.

### Understanding Performance

**Question:** How fast is it?
- **Answer:** 60 FPS with 16,384 particles (with SIMD: up to 32K particles)
- See: [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md#performance-improvements)

**Question:** Where is computation happening?
- **Zig/WASM:** Physics simulation (force computation, particle updates, binning)
- **JavaScript:** Event handling, camera controls, parameter management
- **WebGPU:** All rendering (shaders run on GPU)
- See: [OPTIMIZATION_ANALYSIS.md](OPTIMIZATION_ANALYSIS.md#current-computation-distribution)

**Question:** Should I use threads?
- **Answer:** No, SIMD is better for this use case
- See: [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md#threading--multithreading)

### Troubleshooting

**Build fails:**
- Check [BUILD_NOTES.md](BUILD_NOTES.md)
- Verify Emscripten SDK is installed: [EMSDK_AUTO_SETUP.md](EMSDK_AUTO_SETUP.md)

**Performance issues:**
- Verify SIMD is enabled: Check console for "WASM SIMD: ENABLED"
- See [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md#testing-instructions)

**Visual artifacts:**
- See [BINNING_FIX.md](BINNING_FIX.md) for spatial partitioning issues
- See [BUGFIXES.md](BUGFIXES.md) for other fixes

---

## Architecture Overview

```
User Input (Browser)
       |
       v
JavaScript Layer (shell.html)
  - Event handling
  - WebGPU initialization
  - Camera controls
  - Buffer management
       |
       v
WASM Module (main.zig) <-- SIMD optimized
  - Force computation
  - Particle updates
  - Spatial binning
  - Physics simulation
       |
       v
WebGPU Shaders (WGSL)
  - Instanced rendering
  - HDR + tonemapping
  - Glow effects
  - Dithering
       |
       v
Screen (60 FPS)
```

---

## File Sizes

### Current (with SIMD):
- WASM: ~109 KB
- JavaScript: ~156 KB
- Total: ~265 KB

### Potential (with size optimization):
- WASM: ~60 KB (ReleaseSmall, no SIMD)
- JavaScript: ~100 KB (closure compiler)
- Total: ~160 KB

See [OPTIMIZATION_ANALYSIS.md](OPTIMIZATION_ANALYSIS.md#wasm-size-reduction) for details.

---

## Browser Requirements

**For SIMD (recommended):**
- Chrome 91+ (May 2021)
- Firefox 89+ (June 2021)
- Safari 16.4+ (March 2023)
- Edge 91+ (May 2021)

**Coverage:** 95%+ of users

**For Basic Support:**
- Any browser with WebGPU support
- Automatic fallback to scalar code if SIMD unavailable

---

## Contributing

When adding new optimizations or features, please:

1. Update [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md) with what was changed
2. Add benchmarks to show performance impact
3. Document build flag changes in [BUILD_OPTIMIZATION_GUIDE.md](BUILD_OPTIMIZATION_GUIDE.md)
4. Update this README if adding new documentation files

---

## Performance Summary

| Metric | Value |
|--------|-------|
| Particles (baseline) | 16,384 at 60 FPS |
| Particles (with SIMD) | 24,000-32,000 at 60 FPS |
| WASM size | 109 KB |
| JavaScript size | 156 KB |
| Load time | <200ms |
| Force computation speedup | 2-3x with SIMD |
| Browser coverage | 95%+ |
| Spatial complexity | O(n) with grid |

---

## Credits

- **Original Implementation:** @lisyarus (https://lisyarus.github.io/blog)
- **WebGPU Port:** Zig + WebAssembly implementation
- **Optimizations:** SIMD vectorization, spatial binning, build system improvements

---

## License

See main project LICENSE file.

