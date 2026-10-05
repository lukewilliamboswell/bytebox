const std = @import("std");
const bytebox = @import("bytebox");
const Val = bytebox.Val;
const inputs = @import("inputs");

pub const std_options: std.Options = .{
    .log_level = .info,
};

const Benchmark = struct {
    name: []const u8,
    filename: []const u8,
    param: i32,
};

fn lapTimerMs(io: std.Io, start: *std.Io.Timestamp) f64 {
    const end = std.Io.Clock.awake.now(io);
    const ns_elapsed: f64 = @floatFromInt(start.durationTo(end).toNanoseconds());
    const ms_elapsed = ns_elapsed / 1000000.0;
    start.* = end;
    return ms_elapsed;
}

fn run(io: std.Io, allocator: std.mem.Allocator, benchmark: Benchmark) !void {
    const wasm_data: []u8 = try std.Io.Dir.cwd().readFileAlloc(io, benchmark.filename, allocator, .limited(1024 * 1024));
    defer allocator.free(wasm_data);

    var timer = std.Io.Clock.awake.now(io);

    var module_def = try bytebox.createModuleDefinition(allocator, .{});
    defer module_def.destroy();
    try module_def.decode(wasm_data);
    const ms_elapsed_decode: f64 = lapTimerMs(io, &timer);

    var module_instance = try bytebox.createModuleInstance(.Stack, module_def, allocator);
    defer module_instance.destroy();
    try module_instance.instantiate(.{});
    const ms_elapsed_instantiate: f64 = lapTimerMs(io, &timer);

    const handle = try module_instance.getFunctionHandle("run");
    var input = [1]Val{.{ .I32 = benchmark.param }};
    var output = [1]Val{.{ .I32 = 0 }};
    try module_instance.invoke(handle, &input, &output, .{});

    const ms_elapsed_invoke: f64 = lapTimerMs(io, &timer);
    std.log.info("{s}\n\tdecode: {d}ms\n\tinstantiate: {d}ms\n\trun took {d}ms\n", .{
        benchmark.name,
        ms_elapsed_decode,
        ms_elapsed_instantiate,
        ms_elapsed_invoke,
    });
}

pub fn main(process_init: std.process.Init) !void {
    const allocator = process_init.gpa;

    const benchmarks = [_]Benchmark{
        .{
            // minimum decode+instantiate overhead
            .name = "add-one",
            .filename = inputs.add_one,
            .param = 123456789,
        },
        .{
            // small code size execution with a few instructions
            .name = "fibonacci",
            .filename = inputs.fibonacci,
            .param = 39,
        },
        .{
            // basic memory ops
            .name = "mandelbrot",
            .filename = inputs.mandelbrot,
            .param = 512,
        },
        .{
            // generates a json document, parses it, then hashes the in-memory contents using stdlib
            .name = "json",
            .filename = inputs.json,
            .param = 8192,
        },
    };

    for (benchmarks) |benchmark| {
        run(process_init.io, allocator, benchmark) catch |e| {
            std.log.err("{s} 'run' invocation failed with error: {}\n", .{ benchmark.name, e });
            return e;
        };
    }
}
