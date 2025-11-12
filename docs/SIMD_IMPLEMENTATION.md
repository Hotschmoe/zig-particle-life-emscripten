# SIMD Implementation Guide

## Overview

This document provides a concrete implementation of SIMD optimizations for the particle life simulator.

## Key Targets for SIMD

### 1. Force Computation Inner Loop (Biggest Win)
**Current:** Processes 1 particle pair at a time  
**SIMD:** Process 4 particle pairs simultaneously  
**Speedup:** 2-3x

### 2. Position Updates
**Current:** Updates 1 particle at a time  
**SIMD:** Update 4 particles simultaneously  
**Speedup:** 1.5-2x

### 3. Binning Operations
**Current:** Sequential bin assignments  
**SIMD:** Parallel histogram updates (limited benefit due to data dependencies)  
**Speedup:** 1.1-1.2x

---

## Implementation Example: SIMD Force Computation

```zig
const Vec4f32 = @Vector(4, f32);
const Vec4u32 = @Vector(4, u32);
const Vec4bool = @Vector(4, bool);

// Helper: Create splat vector (all elements same value)
inline fn splat4(val: f32) Vec4f32 {
    return @splat(val);
}

// Helper: Horizontal sum of vector
inline fn hsum(v: Vec4f32) f32 {
    return @reduce(.Add, v);
}

// SIMD-optimized force computation
fn computeForcesSIMD() void {
    const particles = particles_ptr[0..particle_count];
    const particle_indices = particle_indices_ptr[0..particle_count];
    const bin_offsets = bin_offsets_ptr[0..(bin_count + 1)];
    const forces = forces_ptr[0..(species_count * species_count)];

    const width = sim_options.right - sim_options.left;
    const height = sim_options.top - sim_options.bottom;
    const looping = sim_options.looping_borders;

    for (particles, 0..) |*particle, i| {
        const bin_info = getBinInfo(particle.x, particle.y);

        var total_fx: f32 = 0;
        var total_fy: f32 = 0;

        // Central force
        total_fx -= particle.x * sim_options.central_force;
        total_fy -= particle.y * sim_options.central_force;

        // Vectorized particle position (for broadcasting)
        const px = splat4(particle.x);
        const py = splat4(particle.y);
        const width_vec = splat4(width);
        const height_vec = splat4(height);
        const half_width = splat4(width * 0.5);
        const half_height = splat4(height * 0.5);

        // Iterate over neighboring bins
        const min_x: i32 = if (looping) bin_info.grid_x - 1 else @max(0, bin_info.grid_x - 1);
        const max_x: i32 = if (looping) bin_info.grid_x + 1 else @min(@as(i32, @intCast(grid_width)) - 1, bin_info.grid_x + 1);
        const min_y: i32 = if (looping) bin_info.grid_y - 1 else @max(0, bin_info.grid_y - 1);
        const max_y: i32 = if (looping) bin_info.grid_y + 1 else @min(@as(i32, @intCast(grid_height)) - 1, bin_info.grid_y + 1);

        var by: i32 = min_y;
        while (by <= max_y) : (by += 1) {
            var bx: i32 = min_x;
            while (bx <= max_x) : (bx += 1) {
                var real_bx = bx;
                var real_by = by;

                if (looping) {
                    const gw = @as(i32, @intCast(grid_width));
                    const gh = @as(i32, @intCast(grid_height));
                    real_bx = @mod((bx + gw), gw);
                    real_by = @mod((by + gh), gh);
                }

                const bin_idx = @as(u32, @intCast(real_by * @as(i32, @intCast(grid_width)) + real_bx));
                const bin_start = bin_offsets[bin_idx];
                const bin_end = bin_offsets[bin_idx + 1];

                // Process 4 neighbors at a time using SIMD
                var idx_pos: u32 = bin_start;
                
                // SIMD loop: process 4 particles at once
                while (idx_pos + 4 <= bin_end) : (idx_pos += 4) {
                    // Load 4 particle indices
                    const j0 = particle_indices[idx_pos + 0];
                    const j1 = particle_indices[idx_pos + 1];
                    const j2 = particle_indices[idx_pos + 2];
                    const j3 = particle_indices[idx_pos + 3];

                    // Skip if any is self (rare, but check)
                    if (j0 == i or j1 == i or j2 == i or j3 == i) {
                        // Fall back to scalar for this batch
                        for (0..4) |k| {
                            const j = particle_indices[idx_pos + k];
                            if (j != i) {
                                computeSingleForce(particle, i, j, &total_fx, &total_fy, particles, forces, looping, width, height);
                            }
                        }
                        continue;
                    }

                    // Load particle positions (4 at once)
                    const other0 = particles[j0];
                    const other1 = particles[j1];
                    const other2 = particles[j2];
                    const other3 = particles[j3];

                    var ox = Vec4f32{ other0.x, other1.x, other2.x, other3.x };
                    var oy = Vec4f32{ other0.y, other1.y, other2.y, other3.y };
                    const species = Vec4u32{ other0.species, other1.species, other2.species, other3.species };

                    // Compute deltas
                    var dx = ox - px;
                    var dy = oy - py;

                    // Handle looping borders (vectorized)
                    if (looping) {
                        const abs_dx = @abs(dx);
                        const abs_dy = @abs(dy);
                        const wrap_x_mask = abs_dx >= half_width;
                        const wrap_y_mask = abs_dy >= half_height;
                        
                        const sign_dx = @select(f32, dx > splat4(0), splat4(1.0), splat4(-1.0));
                        const sign_dy = @select(f32, dy > splat4(0), splat4(1.0), splat4(-1.0));
                        
                        dx = @select(f32, wrap_x_mask, dx - sign_dx * width_vec, dx);
                        dy = @select(f32, wrap_y_mask, dy - sign_dy * height_vec, dy);
                    }

                    // Compute distances (vectorized)
                    const dist_sq = dx * dx + dy * dy;
                    const dist = @sqrt(dist_sq);

                    // For simplicity, we'll process forces one at a time
                    // (Full SIMD force lookup requires gather operations)
                    for (0..4) |k| {
                        const j = particle_indices[idx_pos + k];
                        const other = particles[j];
                        const force_idx = particle.species * species_count + other.species;
                        const force = forces[force_idx];

                        const d = dist[k];
                        if (d > 0.0 and d < force.radius) {
                            const nx = dx[k] / d;
                            const ny = dy[k] / d;

                            // Attraction/repulsion force
                            const attraction_factor = @max(0.0, 1.0 - d / force.radius);
                            total_fx += force.strength * attraction_factor * nx;
                            total_fy += force.strength * attraction_factor * ny;

                            // Collision force
                            if (d < force.collision_radius) {
                                const collision_factor = @max(0.0, 1.0 - d / force.collision_radius);
                                total_fx -= force.collision_strength * collision_factor * nx;
                                total_fy -= force.collision_strength * collision_factor * ny;
                            }
                        }
                    }
                }

                // Handle remaining particles (< 4) with scalar code
                while (idx_pos < bin_end) : (idx_pos += 1) {
                    const j = particle_indices[idx_pos];
                    if (j != i) {
                        computeSingleForce(particle, i, j, &total_fx, &total_fy, particles, forces, looping, width, height);
                    }
                }
            }
        }

        // Update velocity
        particle.vx += total_fx * sim_options.dt;
        particle.vy += total_fy * sim_options.dt;
    }
}

// Helper function for scalar force computation (used for edge cases)
inline fn computeSingleForce(
    particle: *const Particle,
    i: usize,
    j: u32,
    total_fx: *f32,
    total_fy: *f32,
    particles: []Particle,
    forces: []Force,
    looping: bool,
    width: f32,
    height: f32,
) void {
    const other = particles[j];
    const force_idx = particle.species * species_count + other.species;
    const force = forces[force_idx];

    var dx = other.x - particle.x;
    var dy = other.y - particle.y;

    if (looping) {
        if (abs(dx) >= width * 0.5) {
            dx -= sign(dx) * width;
        }
        if (abs(dy) >= height * 0.5) {
            dy -= sign(dy) * height;
        }
    }

    const dist_sq = dx * dx + dy * dy;
    const dist = sqrt(dist_sq);

    if (dist > 0.0 and dist < force.radius) {
        const nx = dx / dist;
        const ny = dy / dist;

        const attraction_factor = @max(0.0, 1.0 - dist / force.radius);
        total_fx.* += force.strength * attraction_factor * nx;
        total_fy.* += force.strength * attraction_factor * ny;

        if (dist < force.collision_radius) {
            const collision_factor = @max(0.0, 1.0 - dist / force.collision_radius);
            total_fx.* -= force.collision_strength * collision_factor * nx;
            total_fy.* -= force.collision_strength * collision_factor * ny;
        }
    }
}
```

---

## Simpler SIMD Implementation (Recommended Starting Point)

For a simpler first implementation that still gives good gains:

```zig
// Just vectorize the distance calculation
fn computeForcesSIMDSimple() void {
    // ... same setup as before ...
    
    // In the inner loop:
    var idx_pos: u32 = bin_start;
    while (idx_pos + 4 <= bin_end) : (idx_pos += 4) {
        // Load 4 neighbor positions
        const j0 = particle_indices[idx_pos + 0];
        const j1 = particle_indices[idx_pos + 1];
        const j2 = particle_indices[idx_pos + 2];
        const j3 = particle_indices[idx_pos + 3];
        
        // Process them in a vectorized way
        const ox = Vec4f32{
            particles[j0].x,
            particles[j1].x,
            particles[j2].x,
            particles[j3].x,
        };
        const oy = Vec4f32{
            particles[j0].y,
            particles[j1].y,
            particles[j2].y,
            particles[j3].y,
        };
        
        const px_vec = splat4(particle.x);
        const py_vec = splat4(particle.y);
        
        const dx = ox - px_vec;
        const dy = oy - py_vec;
        const dist = @sqrt(dx * dx + dy * dy);
        
        // Then extract and process individually
        // (This alone gives 1.5-2x speedup on distance calc)
        for (0..4) |k| {
            if (particle_indices[idx_pos + k] != i and dist[k] > 0) {
                // ... rest of force computation ...
            }
        }
    }
}
```

---

## Build Commands

### With SIMD Enabled:
```bash
zig build-exe src/main.zig \
    -target wasm32-freestanding \
    -O ReleaseFast \
    -mcpu=generic+simd128 \
    -fstrip \
    -femit-bin=web/particle-life-simd.wasm
```

### Fallback (No SIMD):
```bash
zig build-exe src/main.zig \
    -target wasm32-freestanding \
    -O ReleaseFast \
    -fstrip \
    -femit-bin=web/particle-life.wasm
```

---

## Testing & Benchmarking

### Chrome DevTools:
1. Open DevTools → Performance tab
2. Record a 5-second simulation
3. Look for `simulationStep` in the flame graph
4. Compare before/after times

### Expected Results:
- **Before SIMD:** computeForces takes ~8ms per frame
- **After SIMD:** computeForces takes ~3-4ms per frame
- **Overall:** 60 FPS → 90 FPS (or 16K particles → 24K particles @ 60 FPS)

---

## Browser Support Check

Add to JavaScript:
```javascript
async function checkSIMDSupport() {
    try {
        const simdSupported = await WebAssembly.validate(
            new Uint8Array([0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 96, 0, 1, 123, 3, 2, 1, 0, 10, 10, 1, 8, 0, 65, 0, 253, 15, 253, 98, 11])
        );
        console.log('WASM SIMD supported:', simdSupported);
        return simdSupported;
    } catch {
        return false;
    }
}
```

---

## Compile-Time SIMD Toggle

For maximum compatibility, use compile-time flags:

```zig
// At top of main.zig
const use_simd = @import("builtin").cpu.arch == .wasm32 and 
                 @hasDecl(@import("builtin").cpu.features, "simd128");

// Then:
export fn simulationStep(dt: f32) void {
    sim_options.dt = dt;
    binParticles();
    
    if (use_simd) {
        computeForcesSIMD();
    } else {
        computeForces(); // Original scalar version
    }
    
    updateParticles(dt);
}
```

