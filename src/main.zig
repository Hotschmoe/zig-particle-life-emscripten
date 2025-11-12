// Particle Life Simulator - WebAssembly (Freestanding/Emscripten Compatible)
// Minimal std library usage to avoid emscripten compatibility issues

const std = @import("std");
const builtin = @import("builtin");

// SIMD Configuration - Check if SIMD128 is available at compile time
const wasm_features = std.Target.wasm.Feature;
const use_simd = builtin.cpu.arch == .wasm32 and
    builtin.target.cpu.features.isEnabled(@intFromEnum(wasm_features.simd128));
const Vec4f32 = @Vector(4, f32);
const Vec4bool = @Vector(4, bool);

// ============================================================================
// Math Helpers (avoiding std.math for emscripten compatibility)
// ============================================================================

inline fn sqrt(x: f32) f32 {
    return @sqrt(x);
}

inline fn abs(x: f32) f32 {
    return @abs(x);
}

inline fn floor(x: f32) f32 {
    return @floor(x);
}

inline fn ceil(x: f32) f32 {
    return @ceil(x);
}

inline fn pow(x: f32, y: f32) f32 {
    // Simple power for gamma correction (y = 2.2)
    if (y == 2.2) {
        const x2 = x * x;
        const x4 = x2 * x2;
        return x2 * sqrt(x4 * x);
    }
    var result = x;
    var i: u32 = 1;
    while (i < @as(u32, @intFromFloat(y))) : (i += 1) {
        result *= x;
    }
    return result;
}

inline fn exp(x: f32) f32 {
    // Taylor series approximation for exp(x)
    if (x > 10.0) return 22026.4;
    if (x < -10.0) return 0.0;

    var result: f32 = 1.0;
    var term: f32 = 1.0;
    var i: u32 = 1;
    while (i < 20) : (i += 1) {
        term *= x / @as(f32, @floatFromInt(i));
        result += term;
        if (abs(term) < 0.0001) break;
    }
    return result;
}

inline fn sign(x: f32) f32 {
    if (x > 0) return 1.0;
    if (x < 0) return -1.0;
    return 0.0;
}

// ============================================================================
// SIMD Helper Functions
// ============================================================================

inline fn splat4(val: f32) Vec4f32 {
    return @splat(val);
}

inline fn hsum(v: Vec4f32) f32 {
    return @reduce(.Add, v);
}

inline fn sign_vec(v: Vec4f32) Vec4f32 {
    const zero = splat4(0.0);
    const one = splat4(1.0);
    const neg_one = splat4(-1.0);
    const is_pos = v > zero;
    const is_neg = v < zero;
    return @select(f32, is_pos, one, @select(f32, is_neg, neg_one, zero));
}

// ============================================================================
// Simple Bump Allocator (freestanding-compatible)
// ============================================================================

const HEAP_SIZE = 64 * 1024 * 1024; // 64MB
var heap_memory: [HEAP_SIZE]u8 align(16) = undefined;
var heap_offset: usize = 0;

fn allocBytes(size: usize, alignment: usize) ?[*]u8 {
    const aligned_offset = (heap_offset + alignment - 1) & ~(alignment - 1);
    const new_offset = aligned_offset + size;

    if (new_offset > HEAP_SIZE) return null;

    const ptr: [*]u8 = @ptrCast(&heap_memory[aligned_offset]);
    heap_offset = new_offset;
    return ptr;
}

fn resetHeap() void {
    heap_offset = 0;
}

// ============================================================================
// Type Definitions
// ============================================================================

const Particle = struct {
    x: f32,
    y: f32,
    vx: f32,
    vy: f32,
    species: u32,
};

const Species = struct {
    r: f32,
    g: f32,
    b: f32,
    a: f32,
    spawn_weight: f32,
};

const Force = struct {
    strength: f32, // positive = attraction, negative = repulsion
    radius: f32,
    collision_strength: f32,
    collision_radius: f32,
};

const SimulationOptions = struct {
    left: f32,
    right: f32,
    bottom: f32,
    top: f32,
    friction: f32,
    dt: f32,
    bin_size: f32,
    species_count: u32,
    central_force: f32,
    looping_borders: bool,
    action_x: f32,
    action_y: f32,
    action_vx: f32,
    action_vy: f32,
    action_force: f32,
    action_radius: f32,
};

// ============================================================================
// Global State
// ============================================================================

var particles_ptr: [*]Particle = undefined;
var particle_temp_ptr: [*]Particle = undefined;
var particle_indices_ptr: [*]u32 = undefined; // NEW: Indirect index array
var species_colors_ptr: [*]Species = undefined;
var forces_ptr: [*]Force = undefined;
var bin_offsets_ptr: [*]u32 = undefined;
var bin_temp_ptr: [*]u32 = undefined;

var particle_count: u32 = 0;
var species_count: u32 = 0;
var grid_width: u32 = 0;
var grid_height: u32 = 0;
var bin_count: u32 = 0;

var sim_options: SimulationOptions = .{
    .left = -512,
    .right = 512,
    .bottom = -288,
    .top = 288,
    .friction = 10.0,
    .dt = 0.016,
    .bin_size = 32.0,
    .species_count = 6,
    .central_force = 0.0,
    .looping_borders = false,
    .action_x = 0,
    .action_y = 0,
    .action_vx = 0,
    .action_vy = 0,
    .action_force = 0,
    .action_radius = 32,
};

// ============================================================================
// Frame Timing and Camera State (moved from JavaScript)
// ============================================================================

var last_frame_time: f64 = 0.0;
var frame_count: u32 = 0;
var fps_update_time: f64 = 0.0;
var current_fps: u32 = 60;
var is_paused: bool = false;

// Camera state
var camera_x: f32 = 0.0;
var camera_y: f32 = 0.0;
var camera_extent_x: f32 = 512.0;
var camera_extent_y: f32 = 288.0;
var camera_extent_x_target: f32 = 512.0;

// Mouse/action state (updated from JS)
var has_action_point: bool = false;
var action_screen_x: f32 = 0.0;
var action_screen_y: f32 = 0.0;
var action_drag_x: f32 = 0.0;
var action_drag_y: f32 = 0.0;

// Screen dimensions (updated from JS)
var canvas_width: f32 = 1920.0;
var canvas_height: f32 = 1080.0;

// ============================================================================
// Random Number Generator (SplitMix32)
// ============================================================================

var rng_state: u32 = 0;

fn splitmix32() f32 {
    rng_state +%= 0x9e3779b9;
    var z = rng_state;
    z = (z ^ (z >> 16)) *% 0x21f0aaad;
    z = (z ^ (z >> 15)) *% 0x735a2d97;
    z = z ^ (z >> 15);
    return @as(f32, @floatFromInt(z)) / 4294967296.0;
}

fn setSeed(seed: u32) void {
    rng_state = seed;
}

// ============================================================================
// Spatial Binning Utilities
// ============================================================================

const BinInfo = struct {
    grid_x: i32,
    grid_y: i32,
    bin_index: u32,
};

fn getBinInfo(x: f32, y: f32) BinInfo {
    // Calculate bin ID using floor, matching reference implementation exactly
    const fx = (x - sim_options.left) / sim_options.bin_size;
    const fy = (y - sim_options.bottom) / sim_options.bin_size;

    // Convert to int after floor
    const grid_x_raw = @as(i32, @intFromFloat(floor(fx)));
    const grid_y_raw = @as(i32, @intFromFloat(floor(fy)));

    // Clamp to valid range [0, grid_size - 1]
    const grid_x_max = @as(i32, @intCast(grid_width)) - 1;
    const grid_y_max = @as(i32, @intCast(grid_height)) - 1;

    const clamped_x = @max(0, @min(grid_x_max, grid_x_raw));
    const clamped_y = @max(0, @min(grid_y_max, grid_y_raw));

    // Calculate bin index: row-major order (y * width + x)
    const bin_index = @as(u32, @intCast(clamped_y)) * grid_width + @as(u32, @intCast(clamped_x));

    return .{
        .grid_x = clamped_x,
        .grid_y = clamped_y,
        .bin_index = bin_index,
    };
}

// ============================================================================
// Particle System Initialization
// ============================================================================

export fn initParticleSystem(p_count: u32, s_count: u32, seed: u32) bool {
    setSeed(seed);

    // Reset heap for fresh allocation
    resetHeap();

    // Allocate particles
    const particles_size = p_count * @sizeOf(Particle);
    particles_ptr = @ptrCast(@alignCast(allocBytes(particles_size, @alignOf(Particle)) orelse return false));
    particle_temp_ptr = @ptrCast(@alignCast(allocBytes(particles_size, @alignOf(Particle)) orelse return false));

    // Allocate particle index array for indirect binning
    const indices_size = p_count * @sizeOf(u32);
    particle_indices_ptr = @ptrCast(@alignCast(allocBytes(indices_size, @alignOf(u32)) orelse return false));

    // Initialize particle indices to prevent stale data issues
    const particle_indices = particle_indices_ptr[0..p_count];
    for (particle_indices) |*idx| {
        idx.* = 0;
    }

    // Allocate species
    const species_size = s_count * @sizeOf(Species);
    species_colors_ptr = @ptrCast(@alignCast(allocBytes(species_size, @alignOf(Species)) orelse return false));

    // Allocate forces (species_count x species_count matrix)
    const forces_size = s_count * s_count * @sizeOf(Force);
    forces_ptr = @ptrCast(@alignCast(allocBytes(forces_size, @alignOf(Force)) orelse return false));

    // Calculate grid dimensions
    const width = sim_options.right - sim_options.left;
    const height = sim_options.top - sim_options.bottom;
    grid_width = @intFromFloat(ceil(width / sim_options.bin_size));
    grid_height = @intFromFloat(ceil(height / sim_options.bin_size));
    bin_count = grid_width * grid_height;

    // Allocate bins (with +1 for prefix sum)
    const bins_size = (bin_count + 1) * @sizeOf(u32);
    bin_offsets_ptr = @ptrCast(@alignCast(allocBytes(bins_size, @alignOf(u32)) orelse return false));
    bin_temp_ptr = @ptrCast(@alignCast(allocBytes(bins_size, @alignOf(u32)) orelse return false));

    // Initialize bin arrays to prevent stale data
    const bin_offsets = bin_offsets_ptr[0..(bin_count + 1)];
    const bin_temp = bin_temp_ptr[0..(bin_count + 1)];
    for (bin_offsets) |*offset| {
        offset.* = 0;
    }
    for (bin_temp) |*temp| {
        temp.* = 0;
    }

    particle_count = p_count;
    species_count = s_count;
    sim_options.species_count = s_count;

    return true;
}

// ============================================================================
// System Generation
// ============================================================================

export fn generateRandomSystem(symmetric_forces: bool) void {
    const particles = particles_ptr[0..particle_count];
    const species_colors = species_colors_ptr[0..species_count];
    const forces = forces_ptr[0..(species_count * species_count)];

    // Generate random species colors and spawn weights
    for (species_colors) |*species| {
        const r = 0.25 + splitmix32() * 0.75;
        const g = 0.25 + splitmix32() * 0.75;
        const b = 0.25 + splitmix32() * 0.75;

        // Apply gamma correction
        species.r = pow(r, 2.2);
        species.g = pow(g, 2.2);
        species.b = pow(b, 2.2);
        species.a = 1.0;
        species.spawn_weight = splitmix32(); // Random spawn weight
    }

    // Generate random forces
    const max_force_radius: f32 = 32.0;
    const max_force_strength: f32 = 100.0;

    for (0..species_count) |i| {
        for (0..species_count) |j| {
            const idx = i * species_count + j;

            const sign_val: f32 = if (splitmix32() < 0.5) -1.0 else 1.0;
            const strength = sign_val * max_force_strength * (0.25 + 0.75 * splitmix32());
            const radius = 2.0 + splitmix32() * (max_force_radius - 2.0);
            const collision_strength = (5.0 + 15.0 * splitmix32()) * abs(strength);
            const collision_radius = splitmix32() * 0.5 * radius;

            forces[idx] = .{
                .strength = strength,
                .radius = radius,
                .collision_strength = collision_strength,
                .collision_radius = collision_radius,
            };
        }
    }

    // Symmetrize forces if requested
    if (symmetric_forces) {
        for (0..species_count) |i| {
            for (i + 1..species_count) |j| {
                const idx_ij = i * species_count + j;
                const idx_ji = j * species_count + i;

                const strength = (forces[idx_ij].strength + forces[idx_ji].strength) / 2.0;
                const radius = (forces[idx_ij].radius + forces[idx_ji].radius) / 2.0;
                const collision_strength = (forces[idx_ij].collision_strength + forces[idx_ji].collision_strength) / 2.0;
                const collision_radius = (forces[idx_ij].collision_radius + forces[idx_ji].collision_radius) / 2.0;

                forces[idx_ij].strength = strength;
                forces[idx_ji].strength = strength;
                forces[idx_ij].radius = radius;
                forces[idx_ji].radius = radius;
                forces[idx_ij].collision_strength = collision_strength;
                forces[idx_ji].collision_strength = collision_strength;
                forces[idx_ij].collision_radius = collision_radius;
                forces[idx_ji].collision_radius = collision_radius;
            }
        }
    }

    // Initialize particle positions and velocities
    const initial_velocity: f32 = 10.0;
    const width = sim_options.right - sim_options.left;
    const height = sim_options.top - sim_options.bottom;

    // Calculate total spawn weight
    var total_spawn_weight: f32 = 0.0;
    for (species_colors) |species| {
        total_spawn_weight += species.spawn_weight;
    }

    for (particles) |*particle| {
        particle.x = sim_options.left + splitmix32() * width;
        particle.y = sim_options.bottom + splitmix32() * height;
        particle.vx = initial_velocity * (-1.0 + splitmix32() * 2.0);
        particle.vy = initial_velocity * (-1.0 + splitmix32() * 2.0);

        // Assign species based on weighted random distribution
        var species_pick = splitmix32() * total_spawn_weight;
        particle.species = species_count - 1;
        for (species_colors, 0..) |species, idx| {
            if (species_pick < species.spawn_weight) {
                particle.species = @intCast(idx);
                break;
            }
            species_pick -= species.spawn_weight;
        }
    }
}

// ============================================================================
// Memory Helpers
// ============================================================================

fn memset(ptr: [*]u8, value: u8, size: usize) void {
    var i: usize = 0;
    while (i < size) : (i += 1) {
        ptr[i] = value;
    }
}

fn memcpy(dest: [*]u8, src: [*]const u8, size: usize) void {
    var i: usize = 0;
    while (i < size) : (i += 1) {
        dest[i] = src[i];
    }
}

// ============================================================================
// Spatial Partitioning (Binning)
// ============================================================================

fn binParticles() void {
    const particles = particles_ptr[0..particle_count];
    const particle_indices = particle_indices_ptr[0..particle_count];
    const bin_offsets = bin_offsets_ptr[0..(bin_count + 1)];
    const bin_temp = bin_temp_ptr[0..(bin_count + 1)];

    // Step 1: Clear bin counters
    for (bin_offsets) |*offset| {
        offset.* = 0;
    }

    // Step 2: Count particles per bin (histogram)
    // Note: We count into bin_offsets[bin_index + 1] for the prefix sum
    for (particles) |particle| {
        const bin_info = getBinInfo(particle.x, particle.y);
        // Safety check to prevent out-of-bounds
        if (bin_info.bin_index < bin_count) {
            bin_offsets[bin_info.bin_index + 1] += 1;
        }
    }

    // Step 3: Exclusive prefix sum to convert counts to offsets
    // After this, bin_offsets[i] contains the starting index for bin i
    var accumulated: u32 = 0;
    for (bin_offsets) |*offset| {
        const current_count = offset.*;
        offset.* = accumulated;
        accumulated += current_count;
    }
    // Now bin_offsets[bin_count] contains total particle count (should == particle_count)

    // Step 4: Sort INDICES into bins (not particles themselves!)
    // This way particles stay in place and we can safely check i == j
    // bin_temp tracks how many indices we've placed in each bin so far
    for (bin_temp) |*temp| {
        temp.* = 0;
    }

    for (particles, 0..) |particle, i| {
        const bin_info = getBinInfo(particle.x, particle.y);
        if (bin_info.bin_index < bin_count) {
            const bin_start = bin_offsets[bin_info.bin_index];
            const local_offset = bin_temp[bin_info.bin_index];
            const target_index = bin_start + local_offset;

            // Safety check
            if (target_index < particle_count) {
                particle_indices[target_index] = @intCast(i); // Store particle index, not particle
                bin_temp[bin_info.bin_index] += 1;
            }
        }
    }
    // Now particle_indices[] contains particle indices sorted by bin
}

// ============================================================================
// Force Computation
// ============================================================================

// Helper function for scalar force computation (used for edge cases and fallback)
inline fn computeSingleForce(
    particle: *const Particle,
    i: u32,
    j: u32,
    total_fx: *f32,
    total_fy: *f32,
    particles: []Particle,
    forces: []Force,
    looping: bool,
    width: f32,
    height: f32,
) void {
    if (j == i) return; // Skip self

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

        // Vectorized constants
        const px = splat4(particle.x);
        const py = splat4(particle.y);
        const half_width = splat4(width * 0.5);
        const half_height = splat4(height * 0.5);
        const width_vec = splat4(width);
        const height_vec = splat4(height);

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

                var idx_pos: u32 = bin_start;

                // SIMD loop: process 4 particles at once
                while (idx_pos + 4 <= bin_end) : (idx_pos += 4) {
                    const j0 = particle_indices[idx_pos + 0];
                    const j1 = particle_indices[idx_pos + 1];
                    const j2 = particle_indices[idx_pos + 2];
                    const j3 = particle_indices[idx_pos + 3];

                    // Quick check if any is self (uncommon case)
                    const i_u32 = @as(u32, @intCast(i));
                    if (j0 == i_u32 or j1 == i_u32 or j2 == i_u32 or j3 == i_u32) {
                        // Fall back to scalar for this batch
                        computeSingleForce(particle, i_u32, j0, &total_fx, &total_fy, particles, forces, looping, width, height);
                        computeSingleForce(particle, i_u32, j1, &total_fx, &total_fy, particles, forces, looping, width, height);
                        computeSingleForce(particle, i_u32, j2, &total_fx, &total_fy, particles, forces, looping, width, height);
                        computeSingleForce(particle, i_u32, j3, &total_fx, &total_fy, particles, forces, looping, width, height);
                        continue;
                    }

                    // Load 4 particle positions simultaneously
                    const other0 = particles[j0];
                    const other1 = particles[j1];
                    const other2 = particles[j2];
                    const other3 = particles[j3];

                    const ox = Vec4f32{ other0.x, other1.x, other2.x, other3.x };
                    const oy = Vec4f32{ other0.y, other1.y, other2.y, other3.y };

                    // Compute deltas (4 at once)
                    var dx = ox - px;
                    var dy = oy - py;

                    // Handle looping borders (vectorized)
                    if (looping) {
                        const abs_dx = @abs(dx);
                        const abs_dy = @abs(dy);
                        const wrap_x = abs_dx >= half_width;
                        const wrap_y = abs_dy >= half_height;

                        const sign_dx = sign_vec(dx);
                        const sign_dy = sign_vec(dy);

                        dx = @select(f32, wrap_x, dx - sign_dx * width_vec, dx);
                        dy = @select(f32, wrap_y, dy - sign_dy * height_vec, dy);
                    }

                    // Compute distances (vectorized)
                    const dist_sq = dx * dx + dy * dy;
                    const dist = @sqrt(dist_sq);

                    // Process each force (force matrix lookup can't be easily vectorized)
                    // But distance calculations are now 4x faster!
                    for (0..4) |k| {
                        const j = particle_indices[idx_pos + @as(u32, @intCast(k))];
                        const other = particles[j];
                        const force_idx = particle.species * species_count + other.species;
                        const force = forces[force_idx];

                        const d = dist[k];
                        if (d > 0.0 and d < force.radius) {
                            const nx = dx[k] / d;
                            const ny = dy[k] / d;

                            const attraction_factor = @max(0.0, 1.0 - d / force.radius);
                            total_fx += force.strength * attraction_factor * nx;
                            total_fy += force.strength * attraction_factor * ny;

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
                    computeSingleForce(particle, @as(u32, @intCast(i)), j, &total_fx, &total_fy, particles, forces, looping, width, height);
                }
            }
        }

        // Update velocity
        particle.vx += total_fx * sim_options.dt;
        particle.vy += total_fy * sim_options.dt;
    }
}

// Original scalar force computation (fallback)
fn computeForces() void {
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

        // Iterate over neighboring bins
        const min_x: i32 = if (looping) bin_info.grid_x - 1 else @max(0, bin_info.grid_x - 1);
        const max_x: i32 = if (looping) bin_info.grid_x + 1 else @min(@as(i32, @intCast(grid_width)) - 1, bin_info.grid_x + 1);
        const min_y: i32 = if (looping) bin_info.grid_y - 1 else @max(0, bin_info.grid_y - 1);
        const max_y: i32 = if (looping) bin_info.grid_y + 1 else @min(@as(i32, @intCast(grid_height)) - 1, bin_info.grid_y + 1);

        var by: i32 = min_y;
        while (by <= max_y) : (by += 1) {
            var bx: i32 = min_x;
            while (bx <= max_x) : (bx += 1) {
                // Handle wrapping for looping borders
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

                var idx_pos: u32 = bin_start;
                while (idx_pos < bin_end) : (idx_pos += 1) {
                    const j = particle_indices[idx_pos]; // Get actual particle index
                    if (j == i) continue; // Skip self-interaction

                    const other = particles[j];
                    const force_idx = particle.species * species_count + other.species;
                    const force = forces[force_idx];

                    var dx = other.x - particle.x;
                    var dy = other.y - particle.y;

                    // Handle wrapping for looping borders
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

                        // Attraction/repulsion force
                        const attraction_factor = @max(0.0, 1.0 - dist / force.radius);
                        total_fx += force.strength * attraction_factor * nx;
                        total_fy += force.strength * attraction_factor * ny;

                        // Collision force
                        if (dist < force.collision_radius) {
                            const collision_factor = @max(0.0, 1.0 - dist / force.collision_radius);
                            total_fx -= force.collision_strength * collision_factor * nx;
                            total_fy -= force.collision_strength * collision_factor * ny;
                        }
                    }
                }
            }
        }

        // Update velocity (F = ma, assume m = 1)
        particle.vx += total_fx * sim_options.dt;
        particle.vy += total_fy * sim_options.dt;
    }
}

// ============================================================================
// Particle Update
// ============================================================================

fn updateParticles(dt: f32) void {
    const particles = particles_ptr[0..particle_count];
    const width = sim_options.right - sim_options.left;
    const height = sim_options.top - sim_options.bottom;
    const friction_factor = exp(-dt * sim_options.friction);

    for (particles) |*particle| {
        // Apply action force (user interaction)
        if (sim_options.action_force > 0.0) {
            var action_dx = particle.x - sim_options.action_x;
            var action_dy = particle.y - sim_options.action_y;

            if (sim_options.looping_borders) {
                if (abs(action_dx) >= width * 0.5) {
                    action_dx -= sign(action_dx) * width;
                }
                if (abs(action_dy) >= height * 0.5) {
                    action_dy -= sign(action_dy) * height;
                }
            }

            const action_dist_sq = action_dx * action_dx + action_dy * action_dy;
            const action_radius_sq = sim_options.action_radius * sim_options.action_radius;
            const action_factor = sim_options.action_force * exp(-action_dist_sq / action_radius_sq);

            particle.vx += sim_options.action_vx * action_factor;
            particle.vy += sim_options.action_vy * action_factor;
        }

        // Apply friction
        particle.vx *= friction_factor;
        particle.vy *= friction_factor;

        // Update position
        particle.x += particle.vx * dt;
        particle.y += particle.vy * dt;

        // Handle boundaries
        if (sim_options.looping_borders) {
            // Wrap around
            if (particle.x < sim_options.left) particle.x += width;
            if (particle.x > sim_options.right) particle.x -= width;
            if (particle.y < sim_options.bottom) particle.y += height;
            if (particle.y > sim_options.top) particle.y -= height;
        } else {
            // Bounce
            if (particle.x < sim_options.left) {
                particle.x = sim_options.left;
                particle.vx *= -1.0;
            }
            if (particle.x > sim_options.right) {
                particle.x = sim_options.right;
                particle.vx *= -1.0;
            }
            if (particle.y < sim_options.bottom) {
                particle.y = sim_options.bottom;
                particle.vy *= -1.0;
            }
            if (particle.y > sim_options.top) {
                particle.y = sim_options.top;
                particle.vy *= -1.0;
            }
        }
    }
}

// ============================================================================
// Simulation Step
// ============================================================================

export fn simulationStep(dt: f32) void {
    sim_options.dt = dt;

    // Bin particles for efficient neighbor search
    binParticles();

    // Compute forces and update velocities (use SIMD if available)
    if (use_simd) {
        computeForcesSIMD();
    } else {
        computeForces();
    }

    // Update positions
    updateParticles(dt);
}

// Export function to check if SIMD is enabled (for JavaScript logging)
export fn isSIMDEnabled() bool {
    return use_simd;
}

// ============================================================================
// Data Access Functions (for JavaScript)
// ============================================================================

export fn getParticleCount() u32 {
    return particle_count;
}

export fn getParticleData() [*]const Particle {
    return particles_ptr;
}

export fn getSpeciesData() [*]const Species {
    return species_colors_ptr;
}

export fn getForcesData() [*]const Force {
    return forces_ptr;
}

export fn getSpeciesCount() u32 {
    return species_count;
}

export fn setSimulationBounds(left: f32, right: f32, bottom: f32, top: f32) void {
    sim_options.left = left;
    sim_options.right = right;
    sim_options.bottom = bottom;
    sim_options.top = top;

    // NOTE: Grid dimensions should NOT be recalculated here!
    // The grid is allocated at initialization and cannot be resized.
    // If you need different bounds, call initParticleSystem again.
}

export fn setFriction(friction: f32) void {
    sim_options.friction = friction;
}

export fn setCentralForce(force: f32) void {
    sim_options.central_force = force;
}

export fn setLoopingBorders(looping: bool) void {
    sim_options.looping_borders = looping;
}

export fn setActionPoint(x: f32, y: f32, vx: f32, vy: f32, force: f32, radius: f32) void {
    sim_options.action_x = x;
    sim_options.action_y = y;
    sim_options.action_vx = vx;
    sim_options.action_vy = vy;
    sim_options.action_force = force;
    sim_options.action_radius = radius;
}

export fn clearActionPoint() void {
    sim_options.action_force = 0.0;
}

// ============================================================================
// Camera and Screen Updates (moved from JavaScript)
// ============================================================================

export fn updateCanvasSize(width: f32, height: f32) void {
    canvas_width = width;
    canvas_height = height;

    // Update camera aspect ratio
    const aspect_ratio = width / height;
    camera_extent_y = camera_extent_x / aspect_ratio;
}

export fn updateCameraZoom(factor: f32, anchor_x: f32, anchor_y: f32) void {
    _ = anchor_x; // TODO: Implement zoom anchoring in future optimization
    _ = anchor_y;
    camera_extent_x_target *= factor;
    camera_extent_x_target = @max(10.0, @min(10000.0, camera_extent_x_target));
}

export fn panCamera(dx: f32, dy: f32) void {
    camera_x -= dx / canvas_width * 2.0 * camera_extent_x;
    camera_y += dy / canvas_height * 2.0 * camera_extent_y;
}

export fn centerCamera() void {
    camera_x = 0.0;
    camera_y = 0.0;

    const W = sim_options.right - sim_options.left;
    const H = sim_options.top - sim_options.bottom;
    const aspect_ratio = canvas_width / canvas_height;

    if (W / H > aspect_ratio) {
        camera_extent_x_target = W * 0.5;
    } else {
        camera_extent_x_target = H * 0.5 * aspect_ratio;
    }
}

export fn getCameraData() [*]const f32 {
    // Return pointer to camera data array for GPU uniform updates
    // Format: [center_x, center_y, extent_x, extent_y, pixels_per_unit]
    const camera_data = struct {
        var data: [5]f32 = undefined;
    };

    camera_data.data[0] = camera_x;
    camera_data.data[1] = camera_y;
    camera_data.data[2] = camera_extent_x;
    camera_data.data[3] = camera_extent_y;
    camera_data.data[4] = canvas_width / (2.0 * camera_extent_x); // pixels_per_unit

    return &camera_data.data;
}

export fn setPaused(paused: bool) void {
    is_paused = paused;
}

export fn isPausedState() bool {
    return is_paused;
}

export fn getCurrentFPS() u32 {
    return current_fps;
}

// ============================================================================
// Unified Frame Update (KEY OPTIMIZATION)
// ============================================================================

// This is the main optimization: a SINGLE function call per frame that does
// everything in Zig, minimizing JS/WASM boundary crossings.
//
// JS only needs to call this once per frame, then copy GPU buffers.
export fn frameUpdate(current_time: f64) void {
    // Calculate delta time (capped at 50ms to prevent spiral of death)
    var dt: f32 = 0.016;
    if (last_frame_time > 0.0) {
        dt = @min(@as(f32, @floatCast(current_time - last_frame_time)), 0.05);
    }
    last_frame_time = current_time;

    // Update FPS counter
    frame_count += 1;
    if (current_time - fps_update_time > 1.0) {
        current_fps = frame_count;
        frame_count = 0;
        fps_update_time = current_time;
    }

    // Update camera zoom (smooth interpolation)
    const camera_extent_x_delta = (camera_extent_x_target - camera_extent_x) * (-expm1(-20.0 * dt));
    camera_extent_x += camera_extent_x_delta;

    // Update camera aspect ratio
    const aspect_ratio = canvas_width / canvas_height;
    camera_extent_y = camera_extent_x / aspect_ratio;

    // Skip simulation if paused
    if (is_paused) {
        return;
    }

    // Handle mouse action (convert screen coords to world coords)
    if (has_action_point) {
        const center_x = canvas_width * 0.5;
        const center_y = canvas_height * 0.5;

        const world_x = camera_x + (action_screen_x - center_x) / canvas_width * 2.0 * camera_extent_x;
        const world_y = camera_y - (action_screen_y - center_y) / canvas_height * 2.0 * camera_extent_y;
        const world_dx = action_drag_x / canvas_width * 2.0 * camera_extent_x;
        const world_dy = -action_drag_y / canvas_height * 2.0 * camera_extent_y;

        sim_options.action_x = world_x;
        sim_options.action_y = world_y;
        sim_options.action_vx = world_dx;
        sim_options.action_vy = world_dy;
        sim_options.action_force = 20.0;
        sim_options.action_radius = camera_extent_x / 16.0;
    } else {
        sim_options.action_force = 0.0;
    }

    // Run simulation step
    sim_options.dt = dt;
    binParticles();

    if (use_simd) {
        computeForcesSIMD();
    } else {
        computeForces();
    }

    updateParticles(dt);
}

// Helper for smooth camera zoom (matches reference implementation)
inline fn expm1(x: f32) f32 {
    // exp(x) - 1, using Taylor series for better numerical stability near 0
    if (abs(x) < 0.001) return x;
    return exp(x) - 1.0;
}

// ============================================================================
// Mouse/Action State Updates (called from JavaScript)
// ============================================================================

export fn setActionState(active: bool, screen_x: f32, screen_y: f32, drag_x: f32, drag_y: f32) void {
    has_action_point = active;
    action_screen_x = screen_x;
    action_screen_y = screen_y;
    action_drag_x = drag_x;
    action_drag_y = drag_y;
}

// No main() function needed - this is a WASM library, not an executable
