const std = @import("std");

pub const wgpu = struct {
    // -- Handles --
    pub const WGPUInstance = ?*anyopaque;
    pub const WGPUAdapter = ?*anyopaque;
    pub const WGPUDevice = ?*anyopaque;
    pub const WGPUQueue = ?*anyopaque;
    pub const WGPUSurface = ?*anyopaque;
    pub const WGPUSwapChain = ?*anyopaque;
    pub const WGPUBuffer = ?*anyopaque;
    pub const WGPUBindGroup = ?*anyopaque;
    pub const WGPUBindGroupLayout = ?*anyopaque;
    pub const WGPUPipelineLayout = ?*anyopaque;
    pub const WGPUShaderModule = ?*anyopaque;
    pub const WGPUComputePipeline = ?*anyopaque;
    pub const WGPURenderPipeline = ?*anyopaque;
    pub const WGPUCommandEncoder = ?*anyopaque;
    pub const WGPUComputePassEncoder = ?*anyopaque;
    pub const WGPURenderPassEncoder = ?*anyopaque;
    pub const WGPUCommandBuffer = ?*anyopaque;
    pub const WGPUTexture = ?*anyopaque;
    pub const WGPUTextureView = ?*anyopaque;
    pub const WGPUSampler = ?*anyopaque;

    // -- Enums & Flags --
    pub const WGPURequestAdapterStatus = enum(c_int) {
        Success = 0,
        Unavailable = 1,
        Error = 2,
        Unknown = 3,
    };

    pub const WGPURequestDeviceStatus = enum(c_int) {
        Success = 0,
        Error = 1,
        Unknown = 2,
    };

    pub const WGPUSType = enum(c_int) {
        Invalid = 0,
        SurfaceDescriptorFromCanvasHTMLSelector = 1,
        ShaderModuleWGSLDescriptor = 2,
        // Add others as needed
    };

    pub const WGPUPowerPreference = enum(c_int) {
        Undefined = 0,
        LowPower = 1,
        HighPerformance = 2,
    };

    pub const WGPUTextureUsageFlags = u32;
    pub const WGPUTextureUsage_CopySrc: u32 = 0x01;
    pub const WGPUTextureUsage_CopyDst: u32 = 0x02;
    pub const WGPUTextureUsage_TextureBinding: u32 = 0x04;
    pub const WGPUTextureUsage_StorageBinding: u32 = 0x08;
    pub const WGPUTextureUsage_RenderAttachment: u32 = 0x10;

    pub const WGPUTextureFormat = enum(c_int) {
        Undefined = 0,
        R8Unorm = 1,
        BGRA8Unorm = 2,
        RGBA8Unorm = 3,
        // ...
    };

    pub const WGPUPresentMode = enum(c_int) {
        Fifo = 0,
        FifoRelaxed = 1,
        Immediate = 2,
        Mailbox = 3,
    };

    pub const WGPUBufferUsageFlags = u32;
    pub const WGPUBufferUsage_MapRead: u32 = 0x0001;
    pub const WGPUBufferUsage_MapWrite: u32 = 0x0002;
    pub const WGPUBufferUsage_CopySrc: u32 = 0x0004;
    pub const WGPUBufferUsage_CopyDst: u32 = 0x0008;
    pub const WGPUBufferUsage_Index: u32 = 0x0010;
    pub const WGPUBufferUsage_Vertex: u32 = 0x0020;
    pub const WGPUBufferUsage_Uniform: u32 = 0x0040;
    pub const WGPUBufferUsage_Storage: u32 = 0x0080;
    pub const WGPUBufferUsage_Indirect: u32 = 0x0100;
    pub const WGPUBufferUsage_QueryResolve: u32 = 0x0200;

    pub const WGPU_WHOLE_SIZE: u64 = 0xffffffffffffffff; // UINT64_MAX

    pub const WGPULoadOp = enum(c_int) {
        Undefined = 0,
        Clear = 1,
        Load = 2,
    };

    pub const WGPUStoreOp = enum(c_int) {
        Undefined = 0,
        Store = 1,
        Discard = 2,
    };

    pub const WGPUPrimitiveTopology = enum(c_int) {
        PointList = 0,
        LineList = 1,
        LineStrip = 2,
        TriangleList = 3,
        TriangleStrip = 4,
    };

    pub const WGPUIndexFormat = enum(c_int) {
        Undefined = 0,
        Uint16 = 1,
        Uint32 = 2,
    };

    pub const WGPUFrontFace = enum(c_int) {
        CCW = 0,
        CW = 1,
    };

    pub const WGPUCullMode = enum(c_int) {
        None = 0,
        Front = 1,
        Back = 2,
    };

    pub const WGPUBlendFactor = enum(c_int) {
        Zero = 0,
        One = 1,
        Src = 2,
        OneMinusSrc = 3,
        SrcAlpha = 4,
        OneMinusSrcAlpha = 5,
        Dst = 6,
        OneMinusDst = 7,
        DstAlpha = 8,
        OneMinusDstAlpha = 9,
        SrcAlphaSaturated = 10,
        Constant = 11,
        OneMinusConstant = 12,
    };

    pub const WGPUBlendOperation = enum(c_int) {
        Add = 0,
        Subtract = 1,
        ReverseSubtract = 2,
        Min = 3,
        Max = 4,
    };

    pub const WGPUColorWriteMaskFlags = u32;
    pub const WGPUColorWriteMask_Red: u32 = 0x1;
    pub const WGPUColorWriteMask_Green: u32 = 0x2;
    pub const WGPUColorWriteMask_Blue: u32 = 0x4;
    pub const WGPUColorWriteMask_Alpha: u32 = 0x8;
    pub const WGPUColorWriteMask_All: u32 = 0xF;

    // -- Structs --
    pub const WGPUChainedStruct = extern struct {
        next: ?*const WGPUChainedStruct,
        sType: WGPUSType,
    };

    pub const WGPUInstanceDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
    };

    pub const WGPUSurfaceDescriptorFromCanvasHTMLSelector = extern struct {
        chain: WGPUChainedStruct,
        selector: [*]const u8,
    };

    pub const WGPUSurfaceDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
    };

    pub const WGPURequestAdapterOptions = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        compatibleSurface: WGPUSurface,
        powerPreference: WGPUPowerPreference,
        forceFallbackAdapter: bool,
    };

    pub const WGPURequiredLimits = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        limits: extern struct {
            maxTextureDimension1D: u32,
            maxTextureDimension2D: u32,
            maxTextureDimension3D: u32,
            maxTextureArrayLayers: u32,
            maxBindGroups: u32,
            maxBindingsPerBindGroup: u32,
            maxDynamicUniformBuffersPerPipelineLayout: u32,
            maxDynamicStorageBuffersPerPipelineLayout: u32,
            maxSampledTexturesPerShaderStage: u32,
            maxSamplersPerShaderStage: u32,
            maxStorageBuffersPerShaderStage: u32,
            maxStorageTexturesPerShaderStage: u32,
            maxUniformBuffersPerShaderStage: u32,
            maxUniformBufferBindingSize: u64,
            maxStorageBufferBindingSize: u64,
            minUniformBufferOffsetAlignment: u32,
            minStorageBufferOffsetAlignment: u32,
            maxVertexBuffers: u32,
            maxBufferSize: u64,
            maxVertexAttributes: u32,
            maxVertexBufferArrayStride: u32,
            maxInterStageShaderComponents: u32,
            maxInterStageShaderVariables: u32,
            maxColorAttachments: u32,
            maxColorAttachmentBytesPerSample: u32,
            maxComputeWorkgroupStorageSize: u32,
            maxComputeInvocationsPerWorkgroup: u32,
            maxComputeWorkgroupSizeX: u32,
            maxComputeWorkgroupSizeY: u32,
            maxComputeWorkgroupSizeZ: u32,
            maxComputeWorkgroupsPerDimension: u32,
        },
    };

    pub const WGPUQueueDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
    };

    pub const WGPUDeviceDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
        requiredFeatureCount: u32,
        requiredFeatures: ?[*]const u32, // Enum WGPUFeatureName
        requiredLimits: ?*const WGPURequiredLimits,
        defaultQueue: WGPUQueueDescriptor,
        deviceLostCallback: ?*const fn (reason: c_int, message: [*]const u8, userdata: ?*anyopaque) void,
        deviceLostUserdata: ?*anyopaque,
    };

    pub const WGPUSwapChainDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
        usage: WGPUTextureUsageFlags,
        format: WGPUTextureFormat,
        width: u32,
        height: u32,
        presentMode: WGPUPresentMode,
    };

    pub const WGPUBufferDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
        usage: WGPUBufferUsageFlags,
        size: u64,
        mappedAtCreation: bool,
    };

    pub const WGPUShaderModuleWGSLDescriptor = extern struct {
        chain: WGPUChainedStruct,
        code: [*]const u8,
    };

    pub const WGPUShaderModuleDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
        // hints count and hints omitted for brevity
    };

    pub const WGPUComputePipelineDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
        layout: WGPUPipelineLayout,
        compute: extern struct {
            module: WGPUShaderModule,
            entryPoint: [*]const u8,
            constantCount: u32,
            constants: ?*anyopaque, // Named constants
        },
    };

    pub const WGPUBindGroupEntry = extern struct {
        nextInChain: ?*const WGPUChainedStruct = null,
        binding: u32,
        buffer: WGPUBuffer,
        offset: u64,
        size: u64,
        sampler: WGPUSampler = null,
        textureView: WGPUTextureView = null,
    };

    pub const WGPUBindGroupDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
        layout: WGPUBindGroupLayout,
        entryCount: u32,
        entries: [*]const WGPUBindGroupEntry,
    };

    pub const WGPUCommandEncoderDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
    };

    pub const WGPUComputePassDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
        timestampWrites: ?*anyopaque,
    };

    pub const WGPUCommandBufferDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
    };

    pub const WGPUColor = extern struct {
        r: f64,
        g: f64,
        b: f64,
        a: f64,
    };

    pub const WGPURenderPassColorAttachment = extern struct {
        nextInChain: ?*const WGPUChainedStruct = null,
        view: WGPUTextureView,
        resolveTarget: WGPUTextureView,
        loadOp: WGPULoadOp,
        storeOp: WGPUStoreOp,
        clearValue: WGPUColor,
    };

    pub const WGPURenderPassDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
        colorAttachmentCount: u32,
        colorAttachments: [*]const WGPURenderPassColorAttachment,
        depthStencilAttachment: ?*anyopaque,
        timestampWrites: ?*anyopaque,
        occlusionQuerySet: ?*anyopaque,
    };

    pub const WGPUBlendComponent = extern struct {
        operation: WGPUBlendOperation,
        srcFactor: WGPUBlendFactor,
        dstFactor: WGPUBlendFactor,
    };

    pub const WGPUBlendState = extern struct {
        color: WGPUBlendComponent,
        alpha: WGPUBlendComponent,
    };

    pub const WGPUColorTargetState = extern struct {
        nextInChain: ?*const WGPUChainedStruct = null,
        format: WGPUTextureFormat,
        blend: ?*const WGPUBlendState,
        writeMask: WGPUColorWriteMaskFlags,
    };

    pub const WGPUFragmentState = extern struct {
        nextInChain: ?*const WGPUChainedStruct = null,
        module: WGPUShaderModule,
        entryPoint: [*]const u8,
        constantCount: u32 = 0,
        constants: ?*anyopaque = null,
        targetCount: u32,
        targets: [*]const WGPUColorTargetState,
    };

    pub const WGPUVertexState = extern struct {
        nextInChain: ?*const WGPUChainedStruct = null,
        module: WGPUShaderModule,
        entryPoint: [*]const u8,
        constantCount: u32 = 0,
        constants: ?*anyopaque = null,
        bufferCount: u32,
        buffers: ?*const anyopaque, // VertexBufferLayout
    };

    pub const WGPUPrimitiveState = extern struct {
        nextInChain: ?*const WGPUChainedStruct = null,
        topology: WGPUPrimitiveTopology,
        stripIndexFormat: WGPUIndexFormat,
        frontFace: WGPUFrontFace,
        cullMode: WGPUCullMode,
    };

    pub const WGPUMultisampleState = extern struct {
        nextInChain: ?*const WGPUChainedStruct = null,
        count: u32,
        mask: u32,
        alphaToCoverageEnabled: bool,
    };

    pub const WGPURenderPipelineDescriptor = extern struct {
        nextInChain: ?*const WGPUChainedStruct,
        label: ?[*]const u8,
        layout: WGPUPipelineLayout,
        vertex: WGPUVertexState,
        primitive: WGPUPrimitiveState,
        depthStencil: ?*anyopaque,
        multisample: WGPUMultisampleState,
        fragment: ?*const WGPUFragmentState,
    };

    // -- Functions --
    pub extern fn wgpuCreateInstance(descriptor: ?*const WGPUInstanceDescriptor) WGPUInstance;
    pub extern fn wgpuInstanceCreateSurface(instance: WGPUInstance, descriptor: ?*const WGPUSurfaceDescriptor) WGPUSurface;
    pub extern fn wgpuInstanceRequestAdapter(instance: WGPUInstance, options: ?*const WGPURequestAdapterOptions, callback: ?*const fn (status: WGPURequestAdapterStatus, adapter: WGPUAdapter, message: ?[*]const u8, userdata: ?*anyopaque) void, userdata: ?*anyopaque) void;
    pub extern fn wgpuAdapterRequestDevice(adapter: WGPUAdapter, descriptor: ?*const WGPUDeviceDescriptor, callback: ?*const fn (status: WGPURequestDeviceStatus, device: WGPUDevice, message: ?[*]const u8, userdata: ?*anyopaque) void, userdata: ?*anyopaque) void;
    pub extern fn wgpuDeviceGetQueue(device: WGPUDevice) WGPUQueue;
    pub extern fn wgpuSurfaceGetPreferredFormat(surface: WGPUSurface, adapter: WGPUAdapter) WGPUTextureFormat;
    pub extern fn wgpuDeviceCreateSwapChain(device: WGPUDevice, surface: WGPUSurface, descriptor: ?*const WGPUSwapChainDescriptor) WGPUSwapChain;
    pub extern fn wgpuDeviceCreateBuffer(device: WGPUDevice, descriptor: ?*const WGPUBufferDescriptor) WGPUBuffer;
    pub extern fn wgpuQueueWriteBuffer(queue: WGPUQueue, buffer: WGPUBuffer, bufferOffset: u64, data: ?*const anyopaque, size: usize) void;
    pub extern fn wgpuDeviceCreateShaderModule(device: WGPUDevice, descriptor: ?*const WGPUShaderModuleDescriptor) WGPUShaderModule;
    pub extern fn wgpuDeviceCreateComputePipeline(device: WGPUDevice, descriptor: ?*const WGPUComputePipelineDescriptor) WGPUComputePipeline;
    pub extern fn wgpuDeviceCreateRenderPipeline(device: WGPUDevice, descriptor: ?*const WGPURenderPipelineDescriptor) WGPURenderPipeline;
    pub extern fn wgpuComputePipelineGetBindGroupLayout(pipeline: WGPUComputePipeline, groupIndex: u32) WGPUBindGroupLayout;
    pub extern fn wgpuRenderPipelineGetBindGroupLayout(pipeline: WGPURenderPipeline, groupIndex: u32) WGPUBindGroupLayout;
    pub extern fn wgpuDeviceCreateBindGroup(device: WGPUDevice, descriptor: ?*const WGPUBindGroupDescriptor) WGPUBindGroup;
    pub extern fn wgpuDeviceCreateCommandEncoder(device: WGPUDevice, descriptor: ?*const WGPUCommandEncoderDescriptor) WGPUCommandEncoder;
    pub extern fn wgpuCommandEncoderBeginComputePass(encoder: WGPUCommandEncoder, descriptor: ?*const WGPUComputePassDescriptor) WGPUComputePassEncoder;
    pub extern fn wgpuComputePassEncoderSetPipeline(computePassEncoder: WGPUComputePassEncoder, pipeline: WGPUComputePipeline) void;
    pub extern fn wgpuComputePassEncoderSetBindGroup(computePassEncoder: WGPUComputePassEncoder, groupIndex: u32, group: WGPUBindGroup, dynamicOffsetCount: u32, dynamicOffsets: ?*const u32) void;
    pub extern fn wgpuComputePassEncoderDispatchWorkgroups(computePassEncoder: WGPUComputePassEncoder, workgroupCountX: u32, workgroupCountY: u32, workgroupCountZ: u32) void;
    pub extern fn wgpuComputePassEncoderEnd(computePassEncoder: WGPUComputePassEncoder) void;
    pub extern fn wgpuSwapChainGetCurrentTextureView(swapChain: WGPUSwapChain) WGPUTextureView;
    pub extern fn wgpuCommandEncoderBeginRenderPass(encoder: WGPUCommandEncoder, descriptor: ?*const WGPURenderPassDescriptor) WGPURenderPassEncoder;
    pub extern fn wgpuRenderPassEncoderSetPipeline(renderPassEncoder: WGPURenderPassEncoder, pipeline: WGPURenderPipeline) void;
    pub extern fn wgpuRenderPassEncoderSetBindGroup(renderPassEncoder: WGPURenderPassEncoder, groupIndex: u32, group: WGPUBindGroup, dynamicOffsetCount: u32, dynamicOffsets: ?*const u32) void;
    pub extern fn wgpuRenderPassEncoderDraw(renderPassEncoder: WGPURenderPassEncoder, vertexCount: u32, instanceCount: u32, firstVertex: u32, firstInstance: u32) void;
    pub extern fn wgpuRenderPassEncoderEnd(renderPassEncoder: WGPURenderPassEncoder) void;
    pub extern fn wgpuCommandEncoderFinish(encoder: WGPUCommandEncoder, descriptor: ?*const WGPUCommandBufferDescriptor) WGPUCommandBuffer;
    pub extern fn wgpuQueueSubmit(queue: WGPUQueue, commandCount: u32, commands: ?*const WGPUCommandBuffer) void;
};
