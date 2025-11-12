const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .ReleaseFast, // Changed from ReleaseSmall for better performance
    });

    // Special WASM target configuration for Emscripten with SIMD enabled
    const wasm_target = b.resolveTargetQuery(.{
        .cpu_arch = .wasm32,
        .cpu_model = .{ .explicit = &std.Target.wasm.cpu.bleeding_edge }, // SIMD128 always enabled
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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
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
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_tests.step);
}

// Check if emsdk exists in project directory
fn checkEmsdkExists(allocator: std.mem.Allocator, project_root: []const u8) !bool {
    const emsdk_path = try std.fs.path.join(allocator, &.{ project_root, "emsdk" });
    defer allocator.free(emsdk_path);

    std.fs.accessAbsolute(emsdk_path, .{}) catch {
        return false;
    };

    return true;
}

// Download and install emsdk (Windows only for now)
fn setupEmsdk(allocator: std.mem.Allocator, project_root: []const u8) !void {
    // TODO: Add support for Linux and macOS
    if (builtin.os.tag != .windows) {
        std.debug.print("\nAutomatic emsdk setup is currently only supported on Windows.\n", .{});
        std.debug.print("Please install emsdk manually for your platform.\n\n", .{});
        return error.UnsupportedPlatform;
    }

    std.debug.print("\n========================================\n", .{});
    std.debug.print("Emscripten SDK not found!\n", .{});
    std.debug.print("========================================\n\n", .{});
    std.debug.print("Downloading and installing emsdk...\n", .{});
    std.debug.print("This may take a few minutes.\n\n", .{});

    const emsdk_path = try std.fs.path.join(allocator, &.{ project_root, "emsdk" });
    defer allocator.free(emsdk_path);

    // Step 1: Clone emsdk repository
    std.debug.print("[1/3] Cloning emsdk repository...\n", .{});
    {
        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{
                "git",
                "clone",
                "https://github.com/emscripten-core/emsdk.git",
                emsdk_path,
            },
            .cwd = project_root,
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            std.debug.print("Error cloning emsdk:\n{s}\n", .{result.stderr});
            return error.GitCloneFailed;
        }
    }

    // Step 2: Install latest emsdk
    std.debug.print("[2/3] Installing latest emsdk version...\n", .{});
    {
        const emsdk_bat = try std.fs.path.join(allocator, &.{ emsdk_path, "emsdk.bat" });
        defer allocator.free(emsdk_bat);

        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ emsdk_bat, "install", "latest" },
            .cwd = emsdk_path,
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            std.debug.print("Error installing emsdk:\n{s}\n", .{result.stderr});
            return error.EmsdkInstallFailed;
        }
    }

    // Step 3: Activate emsdk
    std.debug.print("[3/3] Activating emsdk...\n", .{});
    {
        const emsdk_bat = try std.fs.path.join(allocator, &.{ emsdk_path, "emsdk.bat" });
        defer allocator.free(emsdk_bat);

        const result = try std.process.Child.run(.{
            .allocator = allocator,
            .argv = &.{ emsdk_bat, "activate", "latest" },
            .cwd = emsdk_path,
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            std.debug.print("Error activating emsdk:\n{s}\n", .{result.stderr});
            return error.EmsdkActivateFailed;
        }
    }

    std.debug.print("\n✅ Emscripten SDK installed successfully!\n", .{});
    std.debug.print("Location: {s}\n\n", .{emsdk_path});
}

// Get emscripten path from local emsdk or system
fn getEmscriptenPath(b: *std.Build, allocator: std.mem.Allocator) ![]const u8 {
    // If sysroot is explicitly provided, use it
    if (b.sysroot) |sysroot| {
        return sysroot;
    }

    // Try to use local emsdk in project directory
    const project_root = b.build_root.path orelse ".";

    // Check if emsdk exists, if not try to set it up (Windows only)
    const emsdk_exists = try checkEmsdkExists(allocator, project_root);
    if (!emsdk_exists) {
        // TODO: Add support for Linux and macOS
        if (builtin.os.tag == .windows) {
            try setupEmsdk(allocator, project_root);
        } else {
            std.debug.print("\n", .{});
            std.debug.print("========================================\n", .{});
            std.debug.print("ERROR: Emscripten not found!\n", .{});
            std.debug.print("========================================\n", .{});
            std.debug.print("\n", .{});
            std.debug.print("Automatic emsdk setup is only supported on Windows.\n", .{});
            std.debug.print("Please install emsdk manually:\n", .{});
            std.debug.print("\n", .{});
            std.debug.print("1. Clone emsdk:\n", .{});
            std.debug.print("   git clone https://github.com/emscripten-core/emsdk.git\n", .{});
            std.debug.print("   cd emsdk\n", .{});
            std.debug.print("\n", .{});
            std.debug.print("2. Install and activate:\n", .{});
            std.debug.print("   ./emsdk install latest\n", .{});
            std.debug.print("   ./emsdk activate latest\n", .{});
            std.debug.print("\n", .{});
            std.debug.print("3. Then build with:\n", .{});
            std.debug.print("   zig build -Dtarget=wasm32-emscripten --sysroot ~/emsdk/upstream/emscripten\n", .{});
            std.debug.print("\n", .{});
            return error.EmsdkNotFound;
        }
    }

    // Return path to emscripten in local emsdk
    const emscripten_path = try std.fs.path.join(
        allocator,
        &.{ project_root, "emsdk", "upstream", "emscripten" },
    );

    // Verify the path exists
    std.fs.accessAbsolute(emscripten_path, .{}) catch {
        std.debug.print("\nError: Emscripten path not found: {s}\n", .{emscripten_path});
        std.debug.print("The emsdk installation may be incomplete.\n", .{});
        std.debug.print("Try deleting the 'emsdk' folder and running the build again.\n\n", .{});
        return error.EmscriptenNotFound;
    };

    return emscripten_path;
}

// Web build using Emscripten
fn buildWeb(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) !void {
    // Use build allocator for path strings (cleaned up automatically)
    const allocator = b.allocator;

    // Get emscripten path (auto-download if needed on Windows)
    const emscripten_path = try getEmscriptenPath(b, allocator);

    std.debug.print("Using Emscripten from: {s}\n", .{emscripten_path});

    // Build as object file for WASM (to be linked with emcc)
    const lib = b.addObject(.{
        .name = "particle-life",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Link with Emscripten libc
    lib.linkLibC();

    // Ensure sysroot includes are available
    const sysroot_include = b.pathJoin(&.{ emscripten_path, "cache", "sysroot", "include" });
    lib.addIncludePath(.{ .cwd_relative = sysroot_include });

    // Determine emcc executable name based on platform
    // TODO: Add support for Linux and macOS (.sh extension or no extension)
    const emcc_exe = switch (builtin.os.tag) {
        .windows => "emcc.bat",
        else => "emcc",
    };

    const emcc_path = b.pathJoin(&.{ emscripten_path, emcc_exe });

    // Create emcc link command (WebGPU version)
    const emcc_command = b.addSystemCommand(&[_][]const u8{emcc_path});
    emcc_command.addArgs(&[_][]const u8{
        "-o",
        "web/particle-life.html",
        "-sEXPORTED_FUNCTIONS=_initParticleSystem,_generateRandomSystem,_simulationStep,_getParticleCount,_getParticleData,_getSpeciesData,_getForcesData,_getSpeciesCount,_setSimulationBounds,_setFriction,_setCentralForce,_setLoopingBorders,_setActionPoint,_clearActionPoint,_isSIMDEnabled,_frameUpdate,_getCameraData,_updateCanvasSize,_updateCameraZoom,_panCamera,_centerCamera,_setPaused,_isPausedState,_getCurrentFPS,_setActionState",
        "-sEXPORTED_RUNTIME_METHODS=ccall,cwrap,HEAPU8,HEAP8,HEAPU32,HEAP32,HEAPF32,HEAPF64",
        "-sALLOW_MEMORY_GROWTH=1",
        "-sINITIAL_MEMORY=134217728", // 128MB (64MB heap + code + stack + runtime)
        "-sSTACK_SIZE=5242880", // 5MB
        "-sENVIRONMENT=web",
        "--shell-file",
    });
    emcc_command.addFileArg(b.path("web/shell.html"));
    emcc_command.addFileArg(lib.getEmittedBin());
    emcc_command.step.dependOn(&lib.step);

    // Add optimization flags based on build mode
    switch (optimize) {
        .Debug => emcc_command.addArg("-O0"),
        .ReleaseSafe => emcc_command.addArg("-O2"),
        .ReleaseFast => {
            emcc_command.addArgs(&[_][]const u8{ "-O3", "-flto" }); // Link-time optimization
        },
        .ReleaseSmall => {
            emcc_command.addArgs(&[_][]const u8{ "-Oz", "--closure", "1" });
        },
    }

    // SIMD is always enabled
    emcc_command.addArgs(&[_][]const u8{
        "-msimd128",           // Enable WASM SIMD
        "-msse",               // Additional SIMD hints
        "-msse2",
    });
    std.debug.print("SIMD optimizations: ENABLED (requires Chrome 91+, Firefox 89+, Safari 16.4+)\n", .{});

    // Additional optimization flags
    emcc_command.addArgs(&[_][]const u8{
        "-ffast-math",            // Aggressive math optimizations
        "-fno-exceptions",        // No C++ exceptions
        "-fno-rtti",              // No runtime type info
    });

    // Install to default step
    b.getInstallStep().dependOn(&emcc_command.step);

    // Deploy step explicitly copies to web directory
    const deploy_step = b.step("deploy", "Build and deploy WASM to web directory");
    deploy_step.dependOn(&emcc_command.step);
}
