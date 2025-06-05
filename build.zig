const std = @import("std");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    // Standard target options allows the person running `zig build` to choose
    // what target to build for. Here we do not override the defaults, which
    // means any target is allowed, and the default is native. Other options
    // for restricting supported target set are available.


    const target = b.standardTargetOptions(.{ .default_target = .{ .abi = .msvc } });

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    // We will also create a module for our other entry point, 'main.zig'.
    const exe_mod = b.createModule(.{
        // `root_source_file` is the Zig "entry point" of the module. If a module
        // only contains e.g. external object files, you can make this `null`.
        // In this case the main source file is merely a path, however, in more
        // complicated build scripts, this could be a generated file.
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const zigwin32_dep = b.dependency("zigwin32", .{});

    const win32_mod = zigwin32_dep.module("win32");

    exe_mod.addImport("win32", win32_mod);

    const lib = b.addStaticLibrary(.{
        .name = "NamiZigLib",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib.addIncludePath(b.path("src"));
    lib.linkSystemLibrary("ole32");
    lib.linkSystemLibrary("oleaut32");
    lib.linkSystemLibrary("c");
    lib.addIncludePath(b.path("webview/include"));
    lib.addLibraryPath(b.path("webview/x64"));
    lib.addIncludePath(b.path("wil/include/wil"));
    lib.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/um" });
    lib.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/winrt" });
    lib.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/shared" });
    lib.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/cppwinrt" });

    lib.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.43.34808/include" });
    lib.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/ucrt" });

    lib.root_module.addImport("win32", win32_mod);

    lib.addCSourceFile(.{
        .file  = .{ .cwd_relative = "src/webview_wrapper.cpp" },
        .flags = &.{ "-std=c++17", "-Wno-unused-command-line-argument"},
    });

    // This creates another `std.Build.Step.Compile`, but this one builds an executable
    // rather than a static library.
    const exe = b.addExecutable(.{
        .name = "NamiZig",
        .root_source_file   = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.verbose_cc = true;

    exe.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.43.34808/include" });
    exe.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/um" });
    exe.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/winrt" });
    exe.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/shared" });
    exe.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/cppwinrt" });
    exe.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/ucrt" });

    exe.addIncludePath(b.path("src"));
    exe.addIncludePath(b.path("webview/include"));
    exe.addIncludePath(b.path("wil/include/wil"));

    exe.addLibraryPath(.{ .cwd_relative = "C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Tools/MSVC/14.43.34808/lib/x64" });
    exe.addLibraryPath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Lib/10.0.22621.0/um/x64" });
    exe.addLibraryPath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Lib/10.0.22621.0/ucrt/x64" });
    


    exe.linkSystemLibrary("ole32");
    exe.linkSystemLibrary("oleaut32");
    exe.linkSystemLibrary("uuid");
    exe.linkSystemLibrary("propsys"); 
    exe.linkLibrary(lib);
    exe.addObjectFile(b.path("webview/x64/WebView2Loader.dll.lib"));

    exe.root_module.addImport("win32", win32_mod);

    // This declares intent for the executable to be installed into the
    // standard location when the user invokes the "install" step (the default
    // step when running `zig build`).

    exe.linkSystemLibrary("c");

    b.installArtifact(exe);
    // This *creates* a Run step in the build graph, to be executed when another
    // step is evaluated that depends on it. The next line below will establish
    // such a dependency.
    const run_cmd = b.addRunArtifact(exe);

    // By making the run step depend on the install step, it will be run from the
    // installation directory rather than directly from within the cache directory.
    // This is not necessary, however, if the application depends on other installed
    // files, this ensures they will be present and in the expected location.
    run_cmd.step.dependOn(b.getInstallStep());

    // This allows the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // This creates a build step. It will be visible in the `zig build --help` menu,
    // and can be selected like this: `zig build run`
    // This will evaluate the `run` step rather than the default, which is "install".
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/um" });
    exe_unit_tests.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/winrt" });
    exe_unit_tests.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/shared" });
    exe_unit_tests.addSystemIncludePath(.{ .cwd_relative = "C:/Program Files (x86)/Windows Kits/10/Include/10.0.22621.0/cppwinrt" });

    exe_unit_tests.root_module.addImport("win32", win32_mod);

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
