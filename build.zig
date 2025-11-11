const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseSmall,
    });

    // Special WASM target configuration for Emscripten
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .cpu_model = .{ .explicit = &std.Target.wasm.cpu.mvp },
        .os_tag = .emscripten,
    });

    const is_wasm = target.result.cpu.arch == .wasm32;
    const actual_target = if (is_wasm) wasm_target else target;

    if (is_wasm) {
        buildWeb(b, actual_target, optimize) catch |err| {
            std.debug.print("Web build failed: {}\n", .{err});
            return;
        };
    } else {
        buildNative(b, target, optimize);
    }
}

// Native build (for testing/development)
fn buildNative(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) void {
    const exe = b.addExecutable(.{
        .name = "particle-life",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}

// Web build using Emscripten
fn buildWeb(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    if (b.sysroot == null) {
        std.debug.print("\n", .{});
        std.debug.print("========================================\n", .{});
        std.debug.print("ERROR: Emscripten sysroot not specified!\n", .{});
        std.debug.print("========================================\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("Please build with:\n", .{});
        std.debug.print("  zig build -Dtarget=wasm32-emscripten --sysroot [path/to/emsdk]/upstream/emscripten\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("Windows example:\n", .{});
        std.debug.print("  zig build -Dtarget=wasm32-emscripten --sysroot C:/emsdk/upstream/emscripten\n", .{});
        std.debug.print("\n", .{});
        std.debug.print("Linux/Mac example:\n", .{});
        std.debug.print("  zig build -Dtarget=wasm32-emscripten --sysroot ~/emsdk/upstream/emscripten\n", .{});
        std.debug.print("\n", .{});
        return error.SysrootNotSpecified;
    }

    // Build as static library for WASM
    const lib = b.addStaticLibrary(.{
        .name = "particle-life",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link with Emscripten libc
    lib.linkLibC();

    // Ensure sysroot includes are available
    const sysroot_include = b.pathJoin(&.{ b.sysroot.?, "cache", "sysroot", "include" });
    lib.addIncludePath(.{ .cwd_relative = sysroot_include });

    // Determine emcc executable name based on platform
    const emcc_exe = switch (builtin.os.tag) {
        .windows => "emcc.bat",
        else => "emcc",
    };

    const emcc_path = b.pathJoin(&.{ b.sysroot.?, emcc_exe });

    // Create emcc link command
    const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_path});
    emcc_command.addArgs(&[_][]const u8{
        "-o",
        "web/particle-life.html",
        "-sEXPORTED_FUNCTIONS=_initParticleSystem,_generateRandomSystem,_simulationStep,_getParticleCount,_getParticleData,_getSpeciesData,_setSimulationBounds,_setFriction,_setCentralForce,_setLoopingBorders,_setActionPoint,_clearActionPoint",
        "-sEXPORTED_RUNTIME_METHODS=ccall,cwrap",
        "-sALLOW_MEMORY_GROWTH=1",
        "-sINITIAL_MEMORY=67108864", // 64MB
        "-sSTACK_SIZE=5242880", // 5MB
        "-sUSE_OFFSET_CONVERTER=1", // Required for @returnAddress
        "-sENVIRONMENT=web",
        "-sMODULARIZE=1",
        "-sEXPORT_NAME=createParticleLifeModule",
        "--shell-file",
    });
    emcc_command.addFileArg(b.path("web/shell.html"));
    emcc_command.addFileArg(lib.getEmittedBin());
    emcc_command.step.dependOn(&lib.step);

    // Add optimization flags based on build mode
    switch (optimize) {
        .Debug => emcc_command.addArg("-O0"),
        .ReleaseSafe => emcc_command.addArg("-O2"),
        .ReleaseFast => emcc_command.addArg("-O3"),
        .ReleaseSmall => {
            emcc_command.addArgs(&[_][]const u8{ "-Oz", "--closure", "1" });
        },
    }

    // Install to default step
    b.getInstallStep().dependOn(&emcc_command.step);

    // Deploy step explicitly copies to web directory
    const deploy_step = b.step("deploy", "Build and deploy WASM to web directory");
    deploy_step.dependOn(&emcc_command.step);
}
