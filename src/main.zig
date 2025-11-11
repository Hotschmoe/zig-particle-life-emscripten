// Particle Life Simulator - WebAssembly (Freestanding/Emscripten Compatible)
// Minimal std library usage to avoid emscripten compatibility issues

const builtin = @import("builtin");

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
    const grid_x = @as(i32, @intFromFloat(floor((x - sim_options.left) / sim_options.bin_size)));
    const grid_y = @as(i32, @intFromFloat(floor((y - sim_options.bottom) / sim_options.bin_size)));
    
    const clamped_x = @max(0, @min(@as(i32, @intCast(grid_width)) - 1, grid_x));
    const clamped_y = @max(0, @min(@as(i32, @intCast(grid_height)) - 1, grid_y));
    
    const bin_index = @as(u32, @intCast(clamped_y * @as(i32, @intCast(grid_width)) + clamped_x));
    
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
    
    // Generate random species colors
    for (species_colors) |*species| {
        const r = 0.25 + splitmix32() * 0.75;
        const g = 0.25 + splitmix32() * 0.75;
        const b = 0.25 + splitmix32() * 0.75;
        
        // Apply gamma correction
        species.r = pow(r, 2.2);
        species.g = pow(g, 2.2);
        species.b = pow(b, 2.2);
        species.a = 1.0;
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
    
    for (particles) |*particle| {
        particle.x = sim_options.left + splitmix32() * width;
        particle.y = sim_options.bottom + splitmix32() * height;
        particle.vx = initial_velocity * (-1.0 + splitmix32() * 2.0);
        particle.vy = initial_velocity * (-1.0 + splitmix32() * 2.0);
        
        // Assign species based on random distribution
        const species_pick = splitmix32() * @as(f32, @floatFromInt(species_count));
        particle.species = @intFromFloat(floor(species_pick));
        if (particle.species >= species_count) {
            particle.species = species_count - 1;
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
    const particle_temp = particle_temp_ptr[0..particle_count];
    const bin_offsets = bin_offsets_ptr[0..(bin_count + 1)];
    const bin_temp = bin_temp_ptr[0..(bin_count + 1)];
    
    // Clear bins
    memset(@ptrCast(bin_offsets.ptr), 0, (bin_count + 1) * @sizeOf(u32));
    
    // Count particles per bin
    for (particles) |particle| {
        const bin_info = getBinInfo(particle.x, particle.y);
        bin_offsets[bin_info.bin_index + 1] += 1;
    }
    
    // Prefix sum to get offsets
    var sum: u32 = 0;
    for (bin_offsets) |*offset| {
        const current = offset.*;
        offset.* = sum;
        sum += current;
    }
    
    // Sort particles into bins
    memset(@ptrCast(bin_temp.ptr), 0, (bin_count + 1) * @sizeOf(u32));
    for (particles) |particle| {
        const bin_info = getBinInfo(particle.x, particle.y);
        const offset = bin_offsets[bin_info.bin_index];
        const index = offset + bin_temp[bin_info.bin_index];
        particle_temp[index] = particle;
        bin_temp[bin_info.bin_index] += 1;
    }
    
    // Copy sorted particles back
    memcpy(@ptrCast(particles.ptr), @ptrCast(particle_temp.ptr), particle_count * @sizeOf(Particle));
}

// ============================================================================
// Force Computation
// ============================================================================

fn computeForces() void {
    const particles = particles_ptr[0..particle_count];
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
                
                var j: u32 = bin_start;
                while (j < bin_end) : (j += 1) {
                    if (j == i) continue;
                    
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
    
    // Compute forces and update velocities
    computeForces();
    
    // Update positions
    updateParticles(dt);
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

export fn setSimulationBounds(left: f32, right: f32, bottom: f32, top: f32) void {
    sim_options.left = left;
    sim_options.right = right;
    sim_options.bottom = bottom;
    sim_options.top = top;
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
// Entry Point (for native testing)
// ============================================================================

pub fn main() void {
    // This is only used for native builds, not for WASM
}
