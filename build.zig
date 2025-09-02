const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const t = target.result;

    const enable_cli = b.option(bool, "enable_cli", "Build standalone CLI application") orelse false;
    const enable_shared = b.option(bool, "enable_shared", "Build shared library") orelse false;
    const enable_assembly = b.option(bool, "enable_assembly", "Enable use of assembly coded primitives") orelse true;
    const enable_interlaced = b.option(bool, "enable_interlaced", "Enable interlaced encoding") orelse true;
    const enable_gpl = b.option(bool, "enable_gpl", "Enable GPL") orelse true;
    const enable_thread = b.option(bool, "enable_thread", "Enable thread support") orelse true;
    const enable_opencl = b.option(bool, "enable_opencl", "Enable OpenCL support") orelse false;
    const enable_avs = b.option(bool, "enable_avs", "Enable avisynth support") orelse false;
    const enable_swscale = b.option(bool, "enable_swscale", "Enable swscale support") orelse true;
    const enable_lavf = b.option(bool, "enable_lavf", "Enable libavformat support") orelse false;
    const enable_ffms = b.option(bool, "enable_ffms", "Enable ffmpegsource support") orelse false;
    const enable_gpac = b.option(bool, "enable_gpac", "Enable gpac support") orelse false;
    const enable_lsmash = b.option(bool, "enable_lsmash", "Enable lsmash support") orelse false;

    const arch_config = detectArchitecture(t);

    const lib = if (enable_shared)
        b.addSharedLibrary(.{
            .name = "x264",
            .target = target,
            .optimize = optimize,
        })
    else
        b.addStaticLibrary(.{
            .name = "x264",
            .target = target,
            .optimize = optimize,
        });

    lib.linkLibC();
    lib.addIncludePath(b.path("."));

    const stack_alignment: u32 = if (arch_config.x86) @as(u32, 16) else @as(u32, 64);

    const config_h = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "config.h",
    }, .{
        .HAVE_MALLOC_H = t.os.tag == .linux,
        .HAVE_X86_INLINE_ASM = arch_config.x86 and enable_assembly,
        .HAVE_MMX = arch_config.x86 and enable_assembly,
        .ARCH_X86_64 = arch_config.x64,
        .SYS_LINUX = t.os.tag == .linux,
        .STACK_ALIGNMENT = stack_alignment,
        .HAVE_POSIXTHREAD = t.os.tag != .windows and enable_thread,
        .HAVE_CPU_COUNT = true,
        .HAVE_THREAD = enable_thread,
        .HAVE_LOG2F = true,
        .HAVE_STRTOK_R = t.os.tag != .windows,
        .HAVE_CLOCK_GETTIME = t.os.tag != .windows,
        .HAVE_GETAUXVAL = t.os.tag == .linux,
        .HAVE_SYSCONF = t.os.tag != .windows,
        .HAVE_MMAP = t.os.tag != .windows,
        .HAVE_THP = t.os.tag == .linux,
        .HAVE_VECTOREXT = (arch_config.x86 or arch_config.arm or arch_config.arm64) and enable_assembly,
        .HAVE_BITDEPTH8 = true,
        .HAVE_BITDEPTH10 = true,
        .HAVE_GPL = enable_gpl,
        .HAVE_INTERLACED = enable_interlaced,
        .HAVE_ALTIVEC = arch_config.ppc and arch_config.has_altivec,
        .HAVE_ALTIVEC_H = arch_config.ppc and arch_config.has_altivec,
        .HAVE_ARMV6 = arch_config.arm,
        .HAVE_ARMV6T2 = arch_config.arm,
        .HAVE_NEON = arch_config.has_neon,
        .HAVE_AARCH64 = arch_config.arm64,
        .HAVE_BEOSTHREAD = false,
        .HAVE_WIN32THREAD = t.os.tag == .windows and enable_thread,
        .HAVE_SWSCALE = enable_swscale,
        .HAVE_LAVF = enable_lavf,
        .HAVE_FFMS = enable_ffms,
        .HAVE_GPAC = enable_gpac,
        .HAVE_AVS = enable_avs,
        .HAVE_OPENCL = enable_opencl,
        .HAVE_LSMASH = enable_lsmash,
        .HAVE_AS_FUNC = false,
        .HAVE_INTEL_DISPATCHER = false,
        .HAVE_MSA = arch_config.mips and arch_config.has_msa,
        .HAVE_LSX = arch_config.loongarch and arch_config.has_lsx,
        .HAVE_WINRT = false,
        .HAVE_VSX = arch_config.ppc and arch_config.has_vsx,
        .HAVE_ARM_INLINE_ASM = arch_config.arm and enable_assembly,
        .HAVE_ELF_AUX_INFO = false,
        .HAVE_SYNC_FETCH_AND_ADD = false,
        .HAVE_DOTPROD = arch_config.has_dotprod,
        .HAVE_I8MM = arch_config.has_i8mm,
        .HAVE_SVE = arch_config.has_sve,
        .HAVE_SVE2 = arch_config.has_sve2,
        .HAVE_AS_ARCHEXT_DOTPROD_DIRECTIVE = arch_config.has_dotprod,
        .HAVE_AS_ARCHEXT_I8MM_DIRECTIVE = arch_config.has_i8mm,
        .HAVE_AS_ARCHEXT_SVE_DIRECTIVE = arch_config.has_sve,
        .HAVE_AS_ARCHEXT_SVE2_DIRECTIVE = arch_config.has_sve2,
    });
    lib.addConfigHeader(config_h);

    const x264_config_h = b.addConfigHeader(.{
        .style = .blank,
        .include_path = "x264_config.h",
    }, .{
        .X264_GPL = @as(u32, if (enable_gpl) 1 else 0),
        .X264_INTERLACED = @as(u32, if (enable_interlaced) 1 else 0),
        .X264_BIT_DEPTH = 0, // templated; both 8/10 built below
        .X264_CHROMA_FORMAT = 0,
        .X264_VERSION = "",
        .X264_POINTVER = "0.165.x",
    });
    lib.addConfigHeader(x264_config_h);
    lib.installConfigHeader(x264_config_h);

    var compile_flags = std.ArrayList([]const u8).init(b.allocator);
    defer compile_flags.deinit();

    compile_flags.appendSlice(&[_][]const u8{
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

    if (arch_config.x64) {
        compile_flags.appendSlice(&[_][]const u8{ "-m64", "-mstack-alignment=64" }) catch @panic("oom");
    }

    // Base sources (bit depth independent)
    const base_sources = [_][]const u8{
        "common/osdep.c",
        "common/base.c",
        "common/cpu.c",
        "common/tables.c",
        "encoder/api.c",
    };

    const common_sources = [_][]const u8{
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
    };

    const encoder_sources = [_][]const u8{
        "encoder/analyse.c",
        "encoder/me.c",
        "encoder/ratecontrol.c",
        "encoder/set.c",
        "encoder/macroblock.c",
        "encoder/cabac.c",
        "encoder/cavlc.c",
        "encoder/encoder.c",
        "encoder/lookahead.c",
    };

    const thread_sources = [_][]const u8{
        "common/threadpool.c",
    };

    lib.addCSourceFiles(.{ .files = &base_sources, .flags = compile_flags.items });

    var compile_flags_8 = std.ArrayList([]const u8).init(b.allocator);
    defer compile_flags_8.deinit();
    compile_flags_8.appendSlice(compile_flags.items) catch @panic("oom");
    compile_flags_8.appendSlice(&[_][]const u8{ "-DHIGH_BIT_DEPTH=0", "-DBIT_DEPTH=8" }) catch @panic("oom");

    var compile_flags_10 = std.ArrayList([]const u8).init(b.allocator);
    defer compile_flags_10.deinit();
    compile_flags_10.appendSlice(compile_flags.items) catch @panic("oom");
    compile_flags_10.appendSlice(&[_][]const u8{ "-DHIGH_BIT_DEPTH=1", "-DBIT_DEPTH=10" }) catch @panic("oom");

    for (common_sources) |src| {
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_8.items });
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_10.items });
    }

    for (encoder_sources) |src| {
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_8.items });
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_10.items });
    }

    for (thread_sources) |src| {
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_8.items });
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_10.items });
    }

    // Arch specific
    if (arch_config.x86) {
        addX86Sources(b, lib, &arch_config, t, optimize, enable_assembly, &compile_flags_8, &compile_flags_10);
    } else if (arch_config.arm) {
        addArmSources(b, lib, &arch_config, enable_assembly, &compile_flags_8, &compile_flags_10);
    } else if (arch_config.arm64) {
        addArm64Sources(b, lib, &arch_config, t, enable_assembly, &compile_flags_8, &compile_flags_10);
    } else if (arch_config.ppc) {
        addPpcSources(b, lib, &arch_config, &compile_flags_8, &compile_flags_10);
    } else if (arch_config.mips) {
        addMipsSources(b, lib, &arch_config, &compile_flags_8, &compile_flags_10);
    } else if (arch_config.loongarch) {
        addLoongarchSources(b, lib, &arch_config, &compile_flags_8, &compile_flags_10);
    }

    b.installArtifact(lib);

    if (enable_cli) {
        buildCli(b, lib, target, optimize, &arch_config, config_h, x264_config_h);
    }
}

const ArchConfig = struct {
    x86: bool = false,
    x64: bool = false,
    arm: bool = false,
    arm64: bool = false,
    ppc: bool = false,
    ppc64: bool = false,
    mips: bool = false,
    loongarch: bool = false,
    has_neon: bool = false,
    has_dotprod: bool = false,
    has_i8mm: bool = false,
    has_sve: bool = false,
    has_sve2: bool = false,
    has_altivec: bool = false,
    has_vsx: bool = false,
    has_msa: bool = false,
    has_lsx: bool = false,
};

fn detectArchitecture(t: std.Target) ArchConfig {
    var config = ArchConfig{};

    if (t.cpu.arch.isX86()) {
        config.x86 = true;
        if (t.cpu.arch == .x86_64) {
            config.x64 = true;
        }
    } else if (t.cpu.arch == .arm or t.cpu.arch == .armeb) {
        config.arm = true;
        config.has_neon = std.Target.arm.featureSetHas(t.cpu.features, .neon);
    } else if (t.cpu.arch.isAARCH64()) {
        config.arm64 = true;
        config.has_neon = std.Target.aarch64.featureSetHas(t.cpu.features, .neon);
        config.has_dotprod = std.Target.aarch64.featureSetHas(t.cpu.features, .dotprod);
        config.has_i8mm = std.Target.aarch64.featureSetHas(t.cpu.features, .i8mm);
        config.has_sve = std.Target.aarch64.featureSetHas(t.cpu.features, .sve);
        config.has_sve2 = std.Target.aarch64.featureSetHas(t.cpu.features, .sve2);
    } else if (t.cpu.arch == .powerpc or t.cpu.arch == .powerpcle or t.cpu.arch == .powerpc64 or t.cpu.arch == .powerpc64le) {
        config.ppc = true;
        if (t.cpu.arch == .powerpc64 or t.cpu.arch == .powerpc64le) {
            config.ppc64 = true;
        }
        // TODO: detect altivec/vsx
    } else if (t.cpu.arch == .mips or t.cpu.arch == .mipsel or t.cpu.arch == .mips64 or t.cpu.arch == .mips64el) {
        config.mips = true;
        // TODO: detect MSA
    } else if (t.cpu.arch == .loongarch64) {
        config.loongarch = true;
        // TODO: detect LSX
    }

    return config;
}

fn addX86Sources(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    arch_config: *const ArchConfig,
    t: std.Target,
    o: std.builtin.OptimizeMode,
    enable_assembly: bool,
    compile_flags_8: *const std.ArrayList([]const u8),
    compile_flags_10: *const std.ArrayList([]const u8),
) void {
    const x86_c_sources = [_][]const u8{
        "common/x86/mc-c.c",
        "common/x86/predict-c.c",
    };

    for (x86_c_sources) |src| {
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_8.items });
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_10.items });
    }

    if (enable_assembly) {
        const nasm_dep = b.dependency("nasm", .{ .optimize = .ReleaseFast });
        const nasm_exe = nasm_dep.artifact("nasm");

        const run = b.addRunArtifact(nasm_exe);
        var args = std.ArrayList([]const u8).init(b.allocator);
        defer args.deinit();
        args.appendSlice(&.{ "-f", if (t.os.tag == .windows) "win64" else "elf64", "-I./", "-Icommon/x86/" }) catch @panic("oom");
        if (o == .Debug) {
            if (t.os.tag != .windows and t.os.tag != .linux) @panic("Debug symbols only supported on windows and linux");
            const debug_format: []const u8 = switch (t.os.tag) {
                .macos => "macho",
                .linux => "dwarf",
                .windows => "cv8",
                else => unreachable,
            };
            args.appendSlice(&.{ "-g", "-F", debug_format }) catch @panic("oom");
        }
        if (arch_config.x64) {
            args.appendSlice(&.{"-DARCH_X86_64=1"}) catch @panic("oom");
        } else {
            args.appendSlice(&.{"-DARCH_X86=1"}) catch @panic("oom");
        }
        args.appendSlice(&.{"-o"}) catch @panic("oom");
        run.addArgs(args.items);
        lib.addObjectFile(run.addOutputFileArg("cpu-a.o"));
        run.addFileArg(b.path("common/x86/cpu-a.asm"));

        // Assembly files for both bit depths
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
            addNasmObject(b, t, o, nasm_exe, lib, p, true, t.os.tag == .windows, arch_config.x64);
            addNasmObject(b, t, o, nasm_exe, lib, p, false, t.os.tag == .windows, arch_config.x64);
        }

        if (!arch_config.x64) {
            for (asm_x86_only) |p| {
                addNasmObject(b, t, o, nasm_exe, lib, p, true, t.os.tag == .windows, false);
            }
        } else {
            for (asm_x86_64_only) |p| {
                addNasmObject(b, t, o, nasm_exe, lib, p, true, t.os.tag == .windows, true);
                addNasmObject(b, t, o, nasm_exe, lib, p, false, t.os.tag == .windows, true);
            }
        }

        addNasmObject(b, t, o, nasm_exe, lib, "common/x86/sad-a.asm", true, t.os.tag == .windows, arch_config.x64);
        addNasmObject(b, t, o, nasm_exe, lib, "common/x86/sad16-a.asm", false, t.os.tag == .windows, arch_config.x64);
    }
}

fn addArmSources(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    arch_config: *const ArchConfig,
    enable_assembly: bool,
    compile_flags_8: *const std.ArrayList([]const u8),
    compile_flags_10: *const std.ArrayList([]const u8),
) void {
    const arm_c_sources = [_][]const u8{
        "common/arm/mc-c.c",
        "common/arm/predict-c.c",
    };

    for (arm_c_sources) |src| {
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_8.items });
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_10.items });
    }

    if (enable_assembly and arch_config.has_neon) {
        const arm_asm_sources = [_][]const u8{
            "common/arm/bitstream-a.S",
            "common/arm/dct-a.S",
            "common/arm/deblock-a.S",
            "common/arm/mc-a.S",
            "common/arm/pixel-a.S",
            "common/arm/predict-a.S",
            "common/arm/quant-a.S",
        };

        for (arm_asm_sources) |src| {
            lib.addCSourceFiles(.{ .files = &.{src}, .flags = &.{ "-DHIGH_BIT_DEPTH=0", "-DBIT_DEPTH=8" } });
            lib.addCSourceFiles(.{ .files = &.{src}, .flags = &.{ "-DHIGH_BIT_DEPTH=1", "-DBIT_DEPTH=10" } });
        }
    }
}

fn addArm64Sources(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    arch_config: *const ArchConfig,
    t: std.Target,
    enable_assembly: bool,
    compile_flags_8: *const std.ArrayList([]const u8),
    compile_flags_10: *const std.ArrayList([]const u8),
) void {
    const arm64_c_sources = [_][]const u8{
        "common/aarch64/mc-c.c",
        "common/aarch64/predict-c.c",
    };

    for (arm64_c_sources) |src| {
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_8.items });
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_10.items });
    }

    if (enable_assembly) {
        // Basic NEON assembly
        const arm64_asm_sources = [_][]const u8{
            "common/aarch64/bitstream-a.S",
            "common/aarch64/cabac-a.S",
            "common/aarch64/dct-a.S",
            "common/aarch64/deblock-a.S",
            "common/aarch64/mc-a.S",
            "common/aarch64/pixel-a.S",
            "common/aarch64/predict-a.S",
            "common/aarch64/quant-a.S",
        };

        // SVE assembly (if supported)
        const sve_asm_sources = [_][]const u8{
            "common/aarch64/dct-a-sve.S",
            "common/aarch64/deblock-a-sve.S",
            "common/aarch64/mc-a-sve.S",
            "common/aarch64/pixel-a-sve.S",
        };

        // SVE2 assembly (if supported)
        const sve2_asm_sources = [_][]const u8{
            "common/aarch64/dct-a-sve2.S",
        };

        // Determine architecture level for assembly
        const as_arch_level = if (t.os.tag == .macos) "armv8.2-a+crc" else "armv8-a";

        // Create assembly flags with PREFIX for macOS
        var asm_flags_8 = std.ArrayList([]const u8).init(b.allocator);
        defer asm_flags_8.deinit();
        asm_flags_8.appendSlice(&.{ "-DHIGH_BIT_DEPTH=0", "-DBIT_DEPTH=8", b.fmt("-DAS_ARCH_LEVEL={s}", .{as_arch_level}) }) catch @panic("oom");
        if (t.os.tag == .macos) {
            asm_flags_8.append("-DPREFIX") catch @panic("oom");
        }

        var asm_flags_10 = std.ArrayList([]const u8).init(b.allocator);
        defer asm_flags_10.deinit();
        asm_flags_10.appendSlice(&.{ "-DHIGH_BIT_DEPTH=1", "-DBIT_DEPTH=10", b.fmt("-DAS_ARCH_LEVEL={s}", .{as_arch_level}) }) catch @panic("oom");
        if (t.os.tag == .macos) {
            asm_flags_10.append("-DPREFIX") catch @panic("oom");
        }

        // Add basic NEON assembly
        for (arm64_asm_sources) |src| {
            lib.addCSourceFiles(.{ .files = &.{src}, .flags = asm_flags_8.items });
            lib.addCSourceFiles(.{ .files = &.{src}, .flags = asm_flags_10.items });
        }

        // Add SVE assembly if supported
        if (arch_config.has_sve) {
            for (sve_asm_sources) |src| {
                lib.addCSourceFiles(.{ .files = &.{src}, .flags = asm_flags_8.items });
                lib.addCSourceFiles(.{ .files = &.{src}, .flags = asm_flags_10.items });
            }
        }

        // Add SVE2 assembly if supported
        if (arch_config.has_sve2) {
            for (sve2_asm_sources) |src| {
                lib.addCSourceFiles(.{ .files = &.{src}, .flags = asm_flags_8.items });
                lib.addCSourceFiles(.{ .files = &.{src}, .flags = asm_flags_10.items });
            }
        }

        // Add asm-offsets.c
        lib.addCSourceFile(.{ .file = b.path("common/aarch64/asm-offsets.c"), .flags = compile_flags_8.items });
    }
}

fn addPpcSources(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    arch_config: *const ArchConfig,
    compile_flags_8: *const std.ArrayList([]const u8),
    compile_flags_10: *const std.ArrayList([]const u8),
) void {
    _ = arch_config;

    const ppc_c_sources = [_][]const u8{
        "common/ppc/mc-c.c",
        "common/ppc/predict-c.c",
    };

    for (ppc_c_sources) |src| {
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_8.items });
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_10.items });
    }
}

fn addMipsSources(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    arch_config: *const ArchConfig,
    compile_flags_8: *const std.ArrayList([]const u8),
    compile_flags_10: *const std.ArrayList([]const u8),
) void {
    _ = arch_config;

    const mips_c_sources = [_][]const u8{
        "common/mips/mc-c.c",
        "common/mips/predict-c.c",
    };

    for (mips_c_sources) |src| {
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_8.items });
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_10.items });
    }
}

fn addLoongarchSources(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    arch_config: *const ArchConfig,
    compile_flags_8: *const std.ArrayList([]const u8),
    compile_flags_10: *const std.ArrayList([]const u8),
) void {
    _ = arch_config;

    const loongarch_c_sources = [_][]const u8{
        "common/loongarch/mc-c.c",
        "common/loongarch/predict-c.c",
    };

    for (loongarch_c_sources) |src| {
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_8.items });
        lib.addCSourceFile(.{ .file = b.path(src), .flags = compile_flags_10.items });
    }
}

fn buildCli(
    b: *std.Build,
    lib: *std.Build.Step.Compile,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    arch_config: *const ArchConfig,
    config_h: *std.Build.Step.ConfigHeader,
    x264_config_h: *std.Build.Step.ConfigHeader,
) void {
    _ = arch_config;

    const exe = b.addExecutable(.{
        .name = "x264",
        .target = target,
        .optimize = optimize,
    });

    exe.linkLibC();
    exe.addIncludePath(b.path("."));
    exe.addConfigHeader(config_h);
    exe.addConfigHeader(x264_config_h);

    const cli_core_sources = [_][]const u8{
        "x264.c",
        "input/input.c",
        "input/timecode.c",
        "input/raw.c",
        "input/y4m.c",
        "output/raw.c",
        "output/matroska.c",
        "output/matroska_ebml.c",
        "output/flv.c",
        "output/flv_bytestream.c",
        "filters/filters.c",
        "filters/video/video.c",
        "filters/video/source.c",
        "filters/video/internal.c",
        "filters/video/resize.c",
        "filters/video/cache.c",
        "filters/video/fix_vfr_pts.c",
        "filters/video/select_every.c",
        "filters/video/crop.c",
        "filters/video/depth.c",
        "input/thread.c",
        "autocomplete.c",
    };

    const cli_flags_8 = &[_][]const u8{
        "-std=gnu99",
        "-Wshadow",
        "-O3",
        "-ffast-math",
        "-Wall",
        "-I.",
        "-D_GNU_SOURCE",
        "-DHIGH_BIT_DEPTH=0",
        "-DBIT_DEPTH=8",
    };

    const cli_flags_10 = &[_][]const u8{
        "-std=gnu99",
        "-Wshadow",
        "-O3",
        "-ffast-math",
        "-Wall",
        "-I.",
        "-D_GNU_SOURCE",
        "-DHIGH_BIT_DEPTH=1",
        "-DBIT_DEPTH=10",
    };

    const cli_bitdepth_sources = [_][]const u8{
        "filters/video/cache.c",
        "filters/video/depth.c",
        "input/thread.c",
    };

    for (cli_core_sources) |src| {
        var is_bitdepth_source = false;
        for (cli_bitdepth_sources) |bd_src| {
            if (std.mem.eql(u8, src, bd_src)) {
                is_bitdepth_source = true;
                break;
            }
        }

        if (!is_bitdepth_source) {
            exe.addCSourceFile(.{ .file = b.path(src), .flags = cli_flags_8 });
        }
    }

    // bit depth dependent
    for (cli_bitdepth_sources) |src| {
        exe.addCSourceFile(.{ .file = b.path(src), .flags = cli_flags_8 });
        exe.addCSourceFile(.{ .file = b.path(src), .flags = cli_flags_10 });
    }

    exe.linkLibrary(lib);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run x264");
    run_step.dependOn(&run_cmd.step);
}

fn addNasmObject(
    b: *std.Build,
    t: std.Target,
    o: std.builtin.OptimizeMode,
    nasm_exe: *std.Build.Step.Compile,
    lib: *std.Build.Step.Compile,
    input: []const u8,
    depth8: bool,
    is_windows: bool,
    is_x86_64: bool,
) void {
    const run = b.addRunArtifact(nasm_exe);
    run.addArgs(&.{ "-f", if (is_windows) "win64" else "elf64" });
    if (o == .Debug) {
        if (t.os.tag != .windows and t.os.tag != .linux) @panic("Debug symbols only supported on windows and linux");
        const debug_format: []const u8 = switch (t.os.tag) {
            .macos => "macho",
            .linux => "dwarf",
            .windows => "cv8",
            else => unreachable,
        };
        run.addArgs(&.{ "-g", "-F", debug_format });
    }
    run.addArgs(&.{ "-I./", "-Icommon/x86/" });
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
