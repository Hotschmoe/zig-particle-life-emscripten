# Bug Fixes - November 12, 2025

## Issues Found and Fixed

### 1. Mouse Click Way Too Intense (FIXED ✓)
**Problem**: Action force was 50x stronger than the reference implementation.

**Root Cause**: In `shell.html`, the worldDx/worldDy velocities were being multiplied by 50 before passing to `setActionPoint()`.

**Fix**: Removed the `* 50` multiplier to match reference implementation (line ~1025 in shell.html).

**Reference**: Lines 793-794 in nikita_demo/index.html show no additional scaling.

---

### 2. Vertical Banding of Particles (FIXED ✓)
**Problem**: Particles arranged themselves in vertical bands instead of moving freely.

**Root Cause**: Changing simulation width/height sliders updated `sim_options` bounds but did NOT recalculate the spatial binning grid. This caused particles to be binned incorrectly, creating the banding pattern.

**Fix**: Made width/height/particle count/species count sliders call `initSimulation()` immediately to reinitialize the entire system including the binning grid.

**Reference**: Lines 2180-2188 in nikita_demo/index.html show that `updateSimulationSize()` calls `loadSystem()` which reinitializes everything.

**Changed in shell.html**:
- `particleCount` slider → calls `initSimulation()` on input
- `speciesCount` slider → calls `initSimulation()` with new random seed on input  
- `simulationWidth` slider → calls `initSimulation()` on input
- `simulationHeight` slider → calls `initSimulation()` on input

---

### 3. Camera Zoom Smoothing Formula (FIXED ✓)
**Problem**: Minor difference in zoom smoothing calculation.

**Root Cause**: Used `(1 - Math.exp(-20 * dt))` instead of `(-Math.expm1(-20 * dt))`.

**Fix**: Changed to use `-Math.expm1(-20 * dt)` like the reference for mathematical accuracy.

**Note**: `Math.expm1(x) = Math.exp(x) - 1`, so `-Math.expm1(-x) = -(Math.exp(-x) - 1) = 1 - Math.exp(-x)`. They're equivalent, but using expm1 is more numerically stable for small values.

---

### 4. Seed Display (ADDED ✓)
**Enhancement**: Added seed display to stats panel so users can compare identical systems between implementations.

**Added**:
- Seed stat row in stats panel
- Updates when simulation initializes or randomizes

---

## Testing Instructions

### To Verify Fixes:

1. **Mouse Interaction Test**:
   - Open both implementations
   - Left-click and drag on particles
   - Force should feel similar in both versions
   - Should be gentle pushing, not explosive

2. **Vertical Banding Test**:
   - Start fresh simulation
   - Observe particle distribution
   - Should be roughly uniform, not vertical lines
   - Change width/height sliders - should reinitialize cleanly

3. **Particle Disappearing Test**:
   - Watch simulation for 30+ seconds
   - Particle count should remain constant
   - No particles should vanish or appear
   - Check with different simulation sizes

4. **Seed Comparison Test**:
   - Note seed value in stats panel
   - Copy URL (includes seed)
   - Open in reference implementation
   - Visual behavior should match

---

## Implementation Notes

### Spatial Binning

The simulation uses spatial binning for efficient O(N×M) force computation instead of O(N²):

1. **Grid Setup**: World is divided into bins of size 32.0 units (maxForceRadius)
2. **Bin Assignment**: Each particle is assigned to a bin based on its position
3. **Prefix Sum**: Bin offsets calculated for fast lookup
4. **Sorted Storage**: Particles stored in memory ordered by bin
5. **Force Computation**: Only check particles in neighboring bins (3×3 grid)

**Critical**: When simulation bounds change, the grid MUST be recalculated. This requires:
- Reallocating bin buffers
- Recalculating grid dimensions
- Re-binning all particles

This is why changing width/height now triggers full reinitialization.

---

### Comparison with Reference

| Feature | Reference (GPU) | Our Implementation (CPU) | Status |
|---------|----------------|--------------------------|---------|
| Simulation | WebGPU Compute | Zig WASM | Different |
| Binning | GPU Atomic Ops | CPU Sequential | Different |
| Rendering | WebGPU | WebGPU | ✓ Same |
| HDR Pipeline | Yes | Yes | ✓ Same |
| Blue Noise | Yes | Yes | ✓ Same |
| Tonemapping | ACES | ACES | ✓ Same |
| Mouse Action | Yes | Yes | ✓ Fixed |
| UI Controls | All | All | ✓ Same |
| Save/Load | Yes | Yes | ✓ Same |
| URL Sharing | Yes | Yes | ✓ Same |

---

## Remaining Differences

### Expected (Architectural):
- **Performance**: CPU vs GPU simulation will have different performance characteristics
- **Precision**: Floating-point operations may differ slightly between implementations
- **Order**: Particle processing order differs (sequential vs parallel)

### Behavioral:
- **Determinism**: Same seed should produce visually similar but not bit-identical results
- **Timing**: Frame timing differences may cause slight divergence over time

---

## Benchmarking Guidelines

Now that bugs are fixed, fair performance comparison is possible:

### Standard Test Case:
```
Particles: 16,384 (2^14)
Species: 6
Width: 1024
Height: 576
Friction: 10
Central Force: 0
Symmetric Forces: false
Looping Borders: false
Seed: (same for both)
```

### Metrics to Compare:
1. **FPS** - Frames per second (higher is better)
2. **Frame Time** - Milliseconds per frame (lower is better)
3. **Responsiveness** - UI interaction smoothness
4. **Load Time** - Time to first frame
5. **Memory** - Browser memory usage

### Test at Different Scales:
- Small: 4,096 particles (2^12)
- Medium: 16,384 particles (2^14)
- Large: 65,536 particles (2^16)
- Many Species: 20 species
- Large World: 3200×1800 simulation

### Expected Results:
- **Low particle counts**: CPU (Zig) should be competitive or faster
- **High particle counts**: GPU should pull ahead due to parallelism
- **Crossover point**: Likely around 32K-64K particles
- **Memory**: Zig+WASM may use less memory (no duplicate GPU buffers)

---

## Build and Run

```bash
# Build optimized
zig build -Doptimize=ReleaseFast

# Serve locally
cd web
python -m http.server 8000

# Open browser
# http://localhost:8000/particle-life.html (Zig+WASM)
# http://localhost:8000/nikita_demo/index.html (Reference)
```

---

## Credits

**Original Implementation**: Nikita Lisitsa (@lisyarus)  
Blog: https://lisyarus.github.io/blog/posts/particle-life-simulation-in-browser-using-webgpu.html

**Zig Port**: Feature-complete port with bug fixes applied  
Maintains visual parity while using CPU-based simulation for performance comparison.

