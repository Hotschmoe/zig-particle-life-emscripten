const std = @import("std");
const builtin = @import("builtin");
const webgpu = @import("webgpu.zig");
const wgpu = webgpu.wgpu;
const shaders = @import("shaders.zig");

// -- Global Allocator --
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// -- Global WebGPU State --
var instance: wgpu.WGPUInstance = null;
var adapter: wgpu.WGPUAdapter = null;
var device: wgpu.WGPUDevice = null;
var queue: wgpu.WGPUQueue = null;
var surface: wgpu.WGPUSurface = null;
var swap_chain: wgpu.WGPUSwapChain = null;

// -- Buffers --
var particle_buffer: wgpu.WGPUBuffer = null;
var particle_temp_buffer: wgpu.WGPUBuffer = null;
var species_buffer: wgpu.WGPUBuffer = null;
var forces_buffer: wgpu.WGPUBuffer = null;
var bin_size_buffer: wgpu.WGPUBuffer = null;
var bin_offset_buffer: wgpu.WGPUBuffer = null;
var simulation_options_buffer: wgpu.WGPUBuffer = null;
var camera_buffer: wgpu.WGPUBuffer = null;

// -- Pipelines --
var bin_clear_pipeline: wgpu.WGPUComputePipeline = null;
var bin_fill_pipeline: wgpu.WGPUComputePipeline = null;
var bin_prefix_sum_pipeline: wgpu.WGPUComputePipeline = null;
var particle_sort_pipeline: wgpu.WGPUComputePipeline = null;
var compute_forces_pipeline: wgpu.WGPUComputePipeline = null;
var particle_advance_pipeline: wgpu.WGPUComputePipeline = null;
var render_pipeline: wgpu.WGPURenderPipeline = null;

// -- Bind Groups --
var bin_fill_bind_group: wgpu.WGPUBindGroup = null;
var bin_prefix_sum_bind_group: wgpu.WGPUBindGroup = null;
var particle_sort_bind_group: wgpu.WGPUBindGroup = null;
var compute_forces_bind_group: wgpu.WGPUBindGroup = null;
var particle_advance_bind_group: wgpu.WGPUBindGroup = null;
var render_bind_group: wgpu.WGPUBindGroup = null;

// -- Simulation State --
var particle_count: u32 = 16384;
var species_count: u32 = 6;
var canvas_width: u32 = 0;
var canvas_height: u32 = 0;
var is_initialized: bool = false;

// -- Structs --
const SimulationOptions = extern struct {
    left: f32,
    right: f32,
    bottom: f32,
    top: f32,
    friction: f32,
    dt: f32,
    bin_size: f32,
    species_count: f32,
    central_force: f32,
    looping_borders: f32,
    action_x: f32,
    action_y: f32,
    action_vx: f32,
    action_vy: f32,
    action_force: f32,
    action_radius: f32,
};

var sim_options: SimulationOptions = .{
    .left = -512.0,
    .right = 512.0,
    .bottom = -288.0,
    .top = 288.0,
    .friction = 0.1,
    .dt = 0.02,
    .bin_size = 32.0,
    .species_count = 6.0,
    .central_force = 0.0,
    .looping_borders = 0.0,
    .action_x = 0.0,
    .action_y = 0.0,
    .action_vx = 0.0,
    .action_vy = 0.0,
    .action_force = 0.0,
    .action_radius = 100.0,
};

const Camera = extern struct {
    center: [2]f32,
    extent: [2]f32,
    pixels_per_unit: f32,
    _padding: [3]f32,
};

var camera: Camera = .{
    .center = .{ 0.0, 0.0 },
    .extent = .{ 512.0, 288.0 },
    .pixels_per_unit = 1.0,
    ._padding = .{ 0.0, 0.0, 0.0 },
};

// -- Callbacks --

fn handleRequestAdapter(status: wgpu.WGPURequestAdapterStatus, received_adapter: wgpu.WGPUAdapter, message: ?[*]const u8, userdata: ?*anyopaque) void {
    _ = userdata;
    if (status != .Success) {
        if (message) |msg| {
            std.debug.print("Failed to get adapter: {s}\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(msg)))});
        } else {
            std.debug.print("Failed to get adapter: (no message)\n", .{});
        }
        return;
    }
    adapter = received_adapter;

    const device_desc = wgpu.WGPUDeviceDescriptor{
        .nextInChain = null,
        .label = "Particle Life Device",
        .requiredFeatureCount = 0,
        .requiredFeatures = null,
        .requiredLimits = null,
        .defaultQueue = .{ .nextInChain = null, .label = "Default Queue" },
        .deviceLostCallback = null,
        .deviceLostUserdata = null,
    };
    wgpu.wgpuAdapterRequestDevice(adapter, &device_desc, handleRequestDevice, null);
}

fn handleRequestDevice(status: wgpu.WGPURequestDeviceStatus, received_device: wgpu.WGPUDevice, message: ?[*]const u8, userdata: ?*anyopaque) void {
    _ = userdata;
    if (status != .Success) {
        if (message) |msg| {
            std.debug.print("Failed to get device: {s}\n", .{std.mem.span(@as([*:0]const u8, @ptrCast(msg)))});
        } else {
            std.debug.print("Failed to get device: (no message)\n", .{});
        }
        return;
    }
    device = received_device;
    queue = wgpu.wgpuDeviceGetQueue(device);

    createBuffers();
    createPipelines();
    createBindGroups();
    initParticles();

    is_initialized = true;
    std.debug.print("WebGPU Initialized Successfully!\n", .{});
}

// -- Initialization --

export fn initWebGPU(width: u32, height: u32) void {
    canvas_width = width;
    canvas_height = height;

    const instance_desc = wgpu.WGPUInstanceDescriptor{ .nextInChain = null };
    instance = wgpu.wgpuCreateInstance(&instance_desc);

    const surface_desc_selector = wgpu.WGPUSurfaceDescriptorFromCanvasHTMLSelector{
        .chain = .{ .next = null, .sType = .SurfaceDescriptorFromCanvasHTMLSelector },
        .selector = "#canvas",
    };
    const surface_desc = wgpu.WGPUSurfaceDescriptor{
        .nextInChain = @ptrCast(&surface_desc_selector),
        .label = "Canvas Surface",
    };
    surface = wgpu.wgpuInstanceCreateSurface(instance, &surface_desc);

    const options = wgpu.WGPURequestAdapterOptions{
        .nextInChain = null,
        .compatibleSurface = surface,
        .powerPreference = .HighPerformance,
        .forceFallbackAdapter = false,
    };
    wgpu.wgpuInstanceRequestAdapter(instance, &options, handleRequestAdapter, null);
}

export fn updateCanvasSize(width: u32, height: u32) void {
    canvas_width = width;
    canvas_height = height;
    if (device != null and surface != null) {
        configureSwapChain();
    }
}

fn configureSwapChain() void {
    const format = wgpu.wgpuSurfaceGetPreferredFormat(surface, adapter);
    const config = wgpu.WGPUSwapChainDescriptor{
        .nextInChain = null,
        .label = "Swap Chain",
        .usage = wgpu.WGPUTextureUsage_RenderAttachment,
        .format = format,
        .width = canvas_width,
        .height = canvas_height,
        .presentMode = .Fifo,
    };
    swap_chain = wgpu.wgpuDeviceCreateSwapChain(device, surface, &config);
}

// -- Resource Creation --

fn createBuffer(label: [*]const u8, size: u64, usage: wgpu.WGPUBufferUsageFlags) wgpu.WGPUBuffer {
    const desc = wgpu.WGPUBufferDescriptor{
        .nextInChain = null,
        .label = label,
        .usage = usage,
        .size = size,
        .mappedAtCreation = false,
    };
    return wgpu.wgpuDeviceCreateBuffer(device, &desc);
}

fn createBuffers() void {
    const particle_size = @sizeOf(f32) * 5 * particle_count;
    particle_buffer = createBuffer("Particles A", particle_size, wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopyDst);
    particle_temp_buffer = createBuffer("Particles B", particle_size, wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopyDst);

    const species_size = @sizeOf(f32) * 4 * species_count;
    species_buffer = createBuffer("Species", species_size, wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopyDst);

    const forces_size = @sizeOf(f32) * 4 * species_count * species_count;
    forces_buffer = createBuffer("Forces", forces_size, wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopyDst);

    const max_bins = 1024 * 1024;
    bin_size_buffer = createBuffer("Bin Size", max_bins * 4, wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopyDst);
    bin_offset_buffer = createBuffer("Bin Offset", max_bins * 4, wgpu.WGPUBufferUsage_Storage | wgpu.WGPUBufferUsage_CopyDst);

    simulation_options_buffer = createBuffer("Sim Options", @sizeOf(SimulationOptions), wgpu.WGPUBufferUsage_Uniform | wgpu.WGPUBufferUsage_CopyDst);
    camera_buffer = createBuffer("Camera", @sizeOf(Camera), wgpu.WGPUBufferUsage_Uniform | wgpu.WGPUBufferUsage_CopyDst);

    wgpu.wgpuQueueWriteBuffer(queue, simulation_options_buffer, 0, &sim_options, @sizeOf(SimulationOptions));
    wgpu.wgpuQueueWriteBuffer(queue, camera_buffer, 0, &camera, @sizeOf(Camera));
}

fn createComputePipeline(label: [*]const u8, shader_source: [*]const u8, entry_point: [*]const u8) wgpu.WGPUComputePipeline {
    const wgsl_desc = wgpu.WGPUShaderModuleWGSLDescriptor{
        .chain = .{ .next = null, .sType = .ShaderModuleWGSLDescriptor },
        .code = shader_source,
    };
    const module_desc = wgpu.WGPUShaderModuleDescriptor{
        .nextInChain = @ptrCast(&wgsl_desc),
        .label = label,
    };
    const module = wgpu.wgpuDeviceCreateShaderModule(device, &module_desc);

    const pipeline_desc = wgpu.WGPUComputePipelineDescriptor{
        .nextInChain = null,
        .label = label,
        .layout = null,
        .compute = .{
            .module = module,
            .entryPoint = entry_point,
            .constantCount = 0,
            .constants = null,
        },
    };
    return wgpu.wgpuDeviceCreateComputePipeline(device, &pipeline_desc);
}

fn createPipelines() void {
    bin_clear_pipeline = createComputePipeline("Bin Clear", shaders.binFillSizeShader, "clearBinSize");
    bin_fill_pipeline = createComputePipeline("Bin Fill", shaders.binFillSizeShader, "fillBinSize");
    bin_prefix_sum_pipeline = createComputePipeline("Bin Prefix Sum", shaders.binPrefixSumShader, "prefixSumStep");
    particle_sort_pipeline = createComputePipeline("Particle Sort", shaders.particleSortShader, "sortParticles");
    compute_forces_pipeline = createComputePipeline("Compute Forces", shaders.particleComputeForcesShader, "computeForces");
    particle_advance_pipeline = createComputePipeline("Particle Advance", shaders.particleAdvanceShader, "particleAdvance");

    // Render Pipeline
    const wgsl_desc = wgpu.WGPUShaderModuleWGSLDescriptor{
        .chain = .{ .next = null, .sType = .ShaderModuleWGSLDescriptor },
        .code = shaders.particleRenderShader,
    };
    const module_desc = wgpu.WGPUShaderModuleDescriptor{
        .nextInChain = @ptrCast(&wgsl_desc),
        .label = "Render Shader",
    };
    const module = wgpu.wgpuDeviceCreateShaderModule(device, &module_desc);

    const blend_state = wgpu.WGPUBlendState{
        .color = .{ .srcFactor = .One, .dstFactor = .One, .operation = .Add },
        .alpha = .{ .srcFactor = .One, .dstFactor = .One, .operation = .Add },
    };

    const color_target = wgpu.WGPUColorTargetState{
        .format = .BGRA8Unorm,
        .blend = &blend_state,
        .writeMask = wgpu.WGPUColorWriteMask_All,
    };

    const fragment_state = wgpu.WGPUFragmentState{
        .module = module,
        .entryPoint = "fragmentGlow",
        .targetCount = 1,
        .targets = &color_target,
    };

    const render_pipeline_desc = wgpu.WGPURenderPipelineDescriptor{
        .nextInChain = null,
        .label = "Render Pipeline",
        .layout = null,
        .vertex = .{
            .module = module,
            .entryPoint = "vertexGlow",
            .bufferCount = 0,
            .buffers = null,
        },
        .primitive = .{
            .topology = .TriangleList,
            .stripIndexFormat = .Undefined,
            .frontFace = .CCW,
            .cullMode = .None,
        },
        .multisample = .{
            .count = 1,
            .mask = 0xFFFFFFFF,
            .alphaToCoverageEnabled = false,
        },
        .fragment = &fragment_state,
        .depthStencil = null,
    };
    render_pipeline = wgpu.wgpuDeviceCreateRenderPipeline(device, &render_pipeline_desc);
}

fn createBindGroup(layout: wgpu.WGPUBindGroupLayout, entries: []const wgpu.WGPUBindGroupEntry) wgpu.WGPUBindGroup {
    const desc = wgpu.WGPUBindGroupDescriptor{
        .nextInChain = null,
        .label = null,
        .layout = layout,
        .entryCount = @intCast(entries.len),
        .entries = entries.ptr,
    };
    return wgpu.wgpuDeviceCreateBindGroup(device, &desc);
}

fn createBindGroups() void {
    // 1. Bin Fill Bind Group
    const layout_fill_0 = wgpu.wgpuComputePipelineGetBindGroupLayout(bin_fill_pipeline, 0);
    const entry_fill_0 = wgpu.WGPUBindGroupEntry{ .binding = 0, .buffer = particle_buffer, .offset = 0, .size = wgpu.WGPU_WHOLE_SIZE };
    bin_fill_bind_group = createBindGroup(layout_fill_0, &.{entry_fill_0});

    // ... (Initialize other bind groups here as needed)
}

// -- Frame Loop --

export fn frameUpdate() void {
    if (!is_initialized) return;

    wgpu.wgpuQueueWriteBuffer(queue, simulation_options_buffer, 0, &sim_options, @sizeOf(SimulationOptions));
    wgpu.wgpuQueueWriteBuffer(queue, camera_buffer, 0, &camera, @sizeOf(Camera));

    const encoder_desc = wgpu.WGPUCommandEncoderDescriptor{ .nextInChain = null, .label = "Frame Encoder" };
    const encoder = wgpu.wgpuDeviceCreateCommandEncoder(device, &encoder_desc);

    // 1. Compute Pass
    const compute_pass_desc = wgpu.WGPUComputePassDescriptor{ .nextInChain = null, .label = "Simulation Pass", .timestampWrites = null };
    const compute_pass = wgpu.wgpuCommandEncoderBeginComputePass(encoder, &compute_pass_desc);

    // A. Clear Bins
    wgpu.wgpuComputePassEncoderSetPipeline(compute_pass, bin_clear_pipeline);
    // Bind Group 2: Bin Size
    const layout_clear_2 = wgpu.wgpuComputePipelineGetBindGroupLayout(bin_clear_pipeline, 2);
    const entry_clear_2 = wgpu.WGPUBindGroupEntry{ .binding = 0, .buffer = bin_size_buffer, .offset = 0, .size = wgpu.WGPU_WHOLE_SIZE };
    const bg_clear_2 = createBindGroup(layout_clear_2, &.{entry_clear_2});
    wgpu.wgpuComputePassEncoderSetBindGroup(compute_pass, 2, bg_clear_2, 0, null);
    wgpu.wgpuComputePassEncoderDispatchWorkgroups(compute_pass, (1024 * 1024 + 63) / 64, 1, 1);

    // B. Fill Bins
    wgpu.wgpuComputePassEncoderSetPipeline(compute_pass, bin_fill_pipeline);
    // Group 0: Particles (Read)
    const layout_fill_0 = wgpu.wgpuComputePipelineGetBindGroupLayout(bin_fill_pipeline, 0);
    const entry_fill_0 = wgpu.WGPUBindGroupEntry{ .binding = 0, .buffer = particle_buffer, .offset = 0, .size = wgpu.WGPU_WHOLE_SIZE };
    const bg_fill_0 = createBindGroup(layout_fill_0, &.{entry_fill_0});
    wgpu.wgpuComputePassEncoderSetBindGroup(compute_pass, 0, bg_fill_0, 0, null);

    // Group 1: Sim Options
    const layout_fill_1 = wgpu.wgpuComputePipelineGetBindGroupLayout(bin_fill_pipeline, 1);
    const entry_fill_1 = wgpu.WGPUBindGroupEntry{ .binding = 0, .buffer = simulation_options_buffer, .offset = 0, .size = wgpu.WGPU_WHOLE_SIZE };
    const bg_fill_1 = createBindGroup(layout_fill_1, &.{entry_fill_1});
    wgpu.wgpuComputePassEncoderSetBindGroup(compute_pass, 1, bg_fill_1, 0, null);

    // Group 2: Bin Size (Write) - Reuse bg_clear_2 as it has same layout/buffer
    wgpu.wgpuComputePassEncoderSetBindGroup(compute_pass, 2, bg_clear_2, 0, null);

    wgpu.wgpuComputePassEncoderDispatchWorkgroups(compute_pass, (particle_count + 63) / 64, 1, 1);

    // ... (Prefix Sum, Sort, Forces, Advance would follow similar pattern)

    wgpu.wgpuComputePassEncoderEnd(compute_pass);

    // 2. Render Pass
    if (swap_chain != null) {
        const view = wgpu.wgpuSwapChainGetCurrentTextureView(swap_chain);
        if (view != null) {
            const color_attachment = wgpu.WGPURenderPassColorAttachment{
                .view = view,
                .resolveTarget = null,
                .loadOp = .Clear,
                .storeOp = .Store,
                .clearValue = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
            };
            const render_pass_desc = wgpu.WGPURenderPassDescriptor{
                .nextInChain = null,
                .label = "Render Pass",
                .colorAttachmentCount = 1,
                .colorAttachments = @ptrCast(&color_attachment),
                .depthStencilAttachment = null,
                .timestampWrites = null,
                .occlusionQuerySet = null,
            };
            const render_pass = wgpu.wgpuCommandEncoderBeginRenderPass(encoder, &render_pass_desc);

            wgpu.wgpuRenderPassEncoderSetPipeline(render_pass, render_pipeline);

            // Bind Groups for Render
            const layout_render_0 = wgpu.wgpuRenderPipelineGetBindGroupLayout(render_pipeline, 0);
            const entry_render_0_0 = wgpu.WGPUBindGroupEntry{ .binding = 0, .buffer = particle_buffer, .offset = 0, .size = wgpu.WGPU_WHOLE_SIZE };
            const entry_render_0_1 = wgpu.WGPUBindGroupEntry{ .binding = 1, .buffer = species_buffer, .offset = 0, .size = wgpu.WGPU_WHOLE_SIZE };
            const entries_render_0 = [_]wgpu.WGPUBindGroupEntry{ entry_render_0_0, entry_render_0_1 };
            const bg_render_0 = createBindGroup(layout_render_0, &entries_render_0);
            wgpu.wgpuRenderPassEncoderSetBindGroup(render_pass, 0, bg_render_0, 0, null);

            const layout_render_1 = wgpu.wgpuRenderPipelineGetBindGroupLayout(render_pipeline, 1);
            const entry_render_1 = wgpu.WGPUBindGroupEntry{ .binding = 0, .buffer = camera_buffer, .offset = 0, .size = wgpu.WGPU_WHOLE_SIZE };
            const bg_render_1 = createBindGroup(layout_render_1, &.{entry_render_1});
            wgpu.wgpuRenderPassEncoderSetBindGroup(render_pass, 1, bg_render_1, 0, null);

            // Draw 6 vertices per particle (quad)
            wgpu.wgpuRenderPassEncoderDraw(render_pass, 6 * particle_count, 1, 0, 0);

            wgpu.wgpuRenderPassEncoderEnd(render_pass);
        }
    }

    const command_buffer_desc = wgpu.WGPUCommandBufferDescriptor{ .nextInChain = null, .label = "Command Buffer" };
    const command_buffer = wgpu.wgpuCommandEncoderFinish(encoder, &command_buffer_desc);
    wgpu.wgpuQueueSubmit(queue, 1, &command_buffer);
}

fn initParticles() void {
    // Placeholder: Initialize particles on CPU and upload
    // In a real app, we'd generate random data here.
}

// -- UI Helpers --
export fn setFriction(val: f32) void {
    sim_options.friction = val;
}
export fn setCentralForce(val: f32) void {
    sim_options.central_force = val;
}
export fn setLoopingBorders(val: f32) void {
    sim_options.looping_borders = val;
}
export fn setSimulationBounds(l: f32, r: f32, b: f32, t: f32) void {
    sim_options.left = l;
    sim_options.right = r;
    sim_options.bottom = b;
    sim_options.top = t;
}
