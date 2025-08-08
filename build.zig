const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const t = target.result;

    const lib = b.addStaticLibrary(.{
        .name = "x264",
        .target = target,
        .optimize = optimize,
    });
    lib.linkLibC();
    lib.addIncludePath(b.path("."));

    const is_linux = t.os.tag == .linux;
    const is_windows = t.os.tag == .windows;
    const is_arm = t.cpu.arch == .arm;
    const is_aarch64 = t.cpu.arch == .aarch64;

    const stack_alignment: u32 = if (t.cpu.arch.isX86()) @as(u32, 16) else @as(u32, 64);

    const config_h = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "config.h",
    }, .{
        .HAVE_MALLOC_H = true,
        .HAVE_X86_INLINE_ASM = t.cpu.arch.isX86(),
        .HAVE_MMX = t.cpu.arch.isX86(),
        .ARCH_X86_64 = t.cpu.arch == .x86_64,
        .SYS_LINUX = is_linux,
        .STACK_ALIGNMENT = stack_alignment,
        .HAVE_POSIXTHREAD = !is_windows,
        .HAVE_CPU_COUNT = true,
        .HAVE_THREAD = true,
        .HAVE_LOG2F = true,
        .HAVE_STRTOK_R = !is_windows,
        .HAVE_CLOCK_GETTIME = !is_windows,
        .HAVE_GETAUXVAL = is_linux,
        .HAVE_SYSCONF = !is_windows,
        .HAVE_MMAP = !is_windows,
        .HAVE_THP = is_linux,
        .HAVE_VECTOREXT = t.cpu.arch.isX86() or is_arm or is_aarch64,
        .HAVE_BITDEPTH8 = true,
        .HAVE_BITDEPTH10 = true,
        .HAVE_GPL = true,
        .HAVE_INTERLACED = true,
        .HAVE_ALTIVEC = false,
        .HAVE_ALTIVEC_H = false,
        .HAVE_ARMV6 = is_arm,
        .HAVE_ARMV6T2 = false,
        .HAVE_NEON = is_arm or is_aarch64,
        .HAVE_AARCH64 = is_aarch64,
        .HAVE_BEOSTHREAD = false,
        .HAVE_WIN32THREAD = is_windows,
        .HAVE_SWSCALE = false,
        .HAVE_LAVF = false,
        .HAVE_FFMS = false,
        .HAVE_GPAC = false,
        .HAVE_AVS = false,
        .HAVE_OPENCL = false,
        .HAVE_LSMASH = false,
        .HAVE_AS_FUNC = false,
        .HAVE_INTEL_DISPATCHER = false,
        .HAVE_MSA = false,
        .HAVE_LSX = false,
        .HAVE_WINRT = false,
        .HAVE_VSX = false,
        .HAVE_ARM_INLINE_ASM = is_arm,
        .HAVE_ELF_AUX_INFO = false,
        .HAVE_SYNC_FETCH_AND_ADD = false,
        .HAVE_DOTPROD = false,
        .HAVE_I8MM = false,
        .HAVE_SVE = false,
        .HAVE_SVE2 = false,
        .HAVE_AS_ARCHEXT_DOTPROD_DIRECTIVE = false,
        .HAVE_AS_ARCHEXT_I8MM_DIRECTIVE = false,
        .HAVE_AS_ARCHEXT_SVE_DIRECTIVE = false,
        .HAVE_AS_ARCHEXT_SVE2_DIRECTIVE = false,
    });
    lib.addConfigHeader(config_h);

    const x264_config_h = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "x264_config.h",
    }, .{
        .X264_GPL = 1,
        .X264_INTERLACED = 1,
        .X264_BIT_DEPTH = 0, // templated; both 8/10 built below
        .X264_CHROMA_FORMAT = 0,
        .X264_VERSION = "",
        .X264_POINTVER = "0.165.x",
    });
    lib.addConfigHeader(x264_config_h);
    lib.installConfigHeader(x264_config_h);

    var cflags = std.ArrayList([]const u8).init(b.allocator);
    defer cflags.deinit();
    cflags.appendSlice(&[_][]const u8{
        "-std=gnu99",
        "-Wshadow",
        "-O3",
        "-ffast-math",
        "-Wall",
        "-I.",
        "-D_GNU_SOURCE",
        "-fomit-frame-pointer",
        "-fno-tree-vectorize",
        "-fvisibility=hidden",
    }) catch @panic("oom");
    if (t.cpu.arch == .x86_64) {
        cflags.appendSlice(&[_][]const u8{ "-m64", "-mstack-alignment=64" }) catch @panic("oom");
    }

    const srclist_base = [_][]const u8{
        "common/osdep.c",
        "common/base.c",
        "common/cpu.c",
        "common/tables.c",
        "encoder/api.c",
    };

    var srclist_x = std.ArrayList([]const u8).init(b.allocator);
    defer srclist_x.deinit();
    srclist_x.appendSlice(&[_][]const u8{
        "common/mc.c",
        "common/predict.c",
        "common/pixel.c",
        "common/macroblock.c",
        "common/frame.c",
        "common/dct.c",
        "common/cabac.c",
        "common/common.c",
        "common/rectangle.c",
        "common/set.c",
        "common/quant.c",
        "common/deblock.c",
        "common/vlc.c",
        "common/mvpred.c",
        "common/bitstream.c",
        "encoder/analyse.c",
        "encoder/me.c",
        "encoder/ratecontrol.c",
        "encoder/set.c",
        "encoder/macroblock.c",
        "encoder/cabac.c",
        "encoder/cavlc.c",
        "encoder/encoder.c",
        "encoder/lookahead.c",
        "common/threadpool.c",
    }) catch @panic("oom");

    if (t.cpu.arch == .x86 or t.cpu.arch == .x86_64) {
        srclist_x.appendSlice(&[_][]const u8{
            "common/x86/mc-c.c",
            "common/x86/predict-c.c",
        }) catch @panic("oom");
    } else if (t.cpu.arch == .arm) {
        srclist_x.appendSlice(&[_][]const u8{
            "common/arm/mc-c.c",
            "common/arm/predict-c.c",
        }) catch @panic("oom");
    } else if (t.cpu.arch == .aarch64) {
        srclist_x.appendSlice(&[_][]const u8{
            "common/aarch64/mc-c.c",
            "common/aarch64/predict-c.c",
        }) catch @panic("oom");
    }

    lib.addCSourceFiles(.{ .files = &srclist_base, .flags = cflags.items });

    var cflags_8 = std.ArrayList([]const u8).init(b.allocator);
    defer cflags_8.deinit();
    cflags_8.appendSlice(cflags.items) catch @panic("oom");
    cflags_8.appendSlice(&[_][]const u8{ "-DHIGH_BIT_DEPTH=0", "-DBIT_DEPTH=8" }) catch @panic("oom");
    lib.addCSourceFiles(.{ .files = srclist_x.items, .flags = cflags_8.items });

    var cflags_10 = std.ArrayList([]const u8).init(b.allocator);
    defer cflags_10.deinit();
    cflags_10.appendSlice(cflags.items) catch @panic("oom");
    cflags_10.appendSlice(&[_][]const u8{ "-DHIGH_BIT_DEPTH=1", "-DBIT_DEPTH=10" }) catch @panic("oom");
    lib.addCSourceFiles(.{ .files = srclist_x.items, .flags = cflags_10.items });

    switch (t.cpu.arch) {
        .x86, .x86_64 => {
            const nasm_dep = b.dependency("nasm", .{ .optimize = .ReleaseFast });
            const nasm_exe = nasm_dep.artifact("nasm");

            const run = b.addRunArtifact(nasm_exe);
            var args = std.ArrayList([]const u8).init(b.allocator);
            defer args.deinit();
            args.appendSlice(&.{ "-f", if (t.os.tag == .windows) "win64" else "elf64", "-g", "-F", "dwarf", "-I./", "-Icommon/x86/" }) catch @panic("oom");
            if (t.cpu.arch == .x86_64) {
                args.appendSlice(&.{"-DARCH_X86_64=1"}) catch @panic("oom");
            } else {
                args.appendSlice(&.{"-DARCH_X86=1"}) catch @panic("oom");
            }
            args.appendSlice(&.{"-o"}) catch @panic("oom");
            run.addArgs(args.items);
            lib.addObjectFile(run.addOutputFileArg("cpu-a.o"));
            run.addFileArg(b.path("common/x86/cpu-a.asm"));

            const asm_files = [_][]const u8{
                "common/x86/bitstream-a.asm",
                "common/x86/const-a.asm",
                "common/x86/cabac-a.asm",
                "common/x86/dct-a.asm",
                "common/x86/deblock-a.asm",
                "common/x86/mc-a.asm",
                "common/x86/mc-a2.asm",
                "common/x86/pixel-a.asm",
                "common/x86/predict-a.asm",
                "common/x86/quant-a.asm",
            };
            const asm_x86_only = [_][]const u8{ "common/x86/dct-32.asm", "common/x86/pixel-32.asm" };
            const asm_x86_64_only = [_][]const u8{ "common/x86/dct-64.asm", "common/x86/trellis-64.asm" };

            for (asm_files) |p| {
                addNasmObject(b, nasm_exe, lib, p, true, t.os.tag == .windows, t.cpu.arch == .x86_64);
                addNasmObject(b, nasm_exe, lib, p, false, t.os.tag == .windows, t.cpu.arch == .x86_64);
            }
            if (t.cpu.arch == .x86) {
                for (asm_x86_only) |p| addNasmObject(b, nasm_exe, lib, p, true, t.os.tag == .windows, false);
            } else {
                for (asm_x86_64_only) |p| addNasmObject(b, nasm_exe, lib, p, true, t.os.tag == .windows, true);
            }
            addNasmObject(b, nasm_exe, lib, "common/x86/sad-a.asm", true, t.os.tag == .windows, t.cpu.arch == .x86_64);
            addNasmObject(b, nasm_exe, lib, "common/x86/sad16-a.asm", false, t.os.tag == .windows, t.cpu.arch == .x86_64);
        },
        .arm => {
            const arm_S = [_][]const u8{
                "common/arm/bitstream-a.S",
                "common/arm/dct-a.S",
                "common/arm/deblock-a.S",
                "common/arm/mc-a.S",
                "common/arm/pixel-a.S",
                "common/arm/predict-a.S",
                "common/arm/quant-a.S",
            };
            for (arm_S) |f| lib.addCSourceFiles(.{ .files = &.{f}, .flags = &.{ "-DHIGH_BIT_DEPTH=0", "-DBIT_DEPTH=8" } });
            for (arm_S) |f| lib.addCSourceFiles(.{ .files = &.{f}, .flags = &.{ "-DHIGH_BIT_DEPTH=1", "-DBIT_DEPTH=10" } });
        },
        .aarch64 => {
            const a64_S = [_][]const u8{
                "common/aarch64/bitstream-a.S",
                "common/aarch64/cabac-a.S",
                "common/aarch64/dct-a.S",
                "common/aarch64/deblock-a.S",
                "common/aarch64/mc-a.S",
                "common/aarch64/pixel-a.S",
                "common/aarch64/predict-a.S",
                "common/aarch64/quant-a.S",
                "common/aarch64/dct-a-sve.S",
                "common/aarch64/deblock-a-sve.S",
                "common/aarch64/mc-a-sve.S",
                "common/aarch64/pixel-a-sve.S",
                "common/aarch64/dct-a-sve2.S",
            };
            for (a64_S) |f| lib.addCSourceFiles(.{ .files = &.{f}, .flags = &.{ "-DHIGH_BIT_DEPTH=0", "-DBIT_DEPTH=8" } });
            for (a64_S) |f| lib.addCSourceFiles(.{ .files = &.{f}, .flags = &.{ "-DHIGH_BIT_DEPTH=1", "-DBIT_DEPTH=10" } });
            lib.addCSourceFile(.{ .file = b.path("common/aarch64/asm-offsets.c"), .flags = cflags.items });
        },
        else => {},
    }

    b.installArtifact(lib);
}

fn addNasmObject(
    b: *std.Build,
    nasm_exe: *std.Build.Step.Compile,
    lib: *std.Build.Step.Compile,
    input: []const u8,
    depth8: bool,
    is_windows: bool,
    is_x86_64: bool,
) void {
    const run = b.addRunArtifact(nasm_exe);
    run.addArgs(&.{ "-f", if (is_windows) "win64" else "elf64" });
    run.addArgs(&.{ "-g", "-F", "dwarf", "-I./", "-Icommon/x86/" });
    if (is_x86_64) {
        run.addArgs(&.{"-DARCH_X86_64=1"});
    } else {
        run.addArgs(&.{"-DARCH_X86=1"});
    }
    if (depth8) {
        run.addArgs(&.{ "-DBIT_DEPTH=8", "-Dprivate_prefix=x264_8" });
    } else {
        run.addArgs(&.{ "-DBIT_DEPTH=10", "-Dprivate_prefix=x264_10" });
    }
    const base = std.fs.path.basename(input);
    const dot = std.mem.lastIndexOfScalar(u8, base, '.') orelse base.len;
    const stem = base[0..dot];
    const out_name = b.fmt("{s}{s}", .{ stem, if (depth8) "-8.o" else "-10.o" });
    run.addArgs(&.{"-o"});
    lib.addObjectFile(run.addOutputFileArg(out_name));
    run.addFileArg(b.path(input));
}
