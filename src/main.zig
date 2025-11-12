const std = @import("std");
const builtin = @import("builtin");
const image = @import("image");

pub const Image = image.Image;
pub const std_options: std.Options = .{
    .log_level = .err,
    .logFn = myLogFn,
    .log_scope_levels = &[_]std.log.ScopeLevel{
        .{ .scope = .img2ascii, .level = .err },
    },
};

pub fn myLogFn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.enum_literal),
    comptime format: []const u8,
    args: anytype,
) void {
    const prefix = "[" ++ comptime level.asText() ++ "] (" ++ @tagName(scope) ++ "): ";
    // Print the message to stderr, silently ignoring any errors
    std.debug.lockStdErr();
    defer std.debug.unlockStdErr();
    const stderr = std.io.getStdErr().writer();
    nosuspend stderr.print(prefix ++ format, args) catch return;
}

const IMG2ASCII_LOG = std.log.scoped(.img2ascii);

const ASCII_CHARS = [_]u8{ ' ', '.', ':', 'c', 'o', '?', 'P', 'O', '#', '@' };

const Error = error{
    INVALID_ARG,
    SAMPLE_ERROR,
} || Image.Error || std.mem.Allocator.Error;

var allocator: std.mem.Allocator = undefined;
var ascii_height: u32 = 200;

pub fn sample_pixel(im: *Image, i: usize, j: usize, num_samples: u32) Error!f32 {
    if (num_samples % 2 != 0 and num_samples != 1) {
        return Error.SAMPLE_ERROR;
    }
    //TODO improve sample method
    var sample: f32 = (@as(f32, @floatFromInt(im.get(j, i).get_r())) / 255.0);
    if (num_samples > 1) {
        for (1..(num_samples / 2) + 1) |k| {
            sample += if (j + k >= im.width) 0 else (@as(f32, @floatFromInt(im.get(j + k, i).get_r())) / 255.0);
            sample += if (i + k >= im.height) 0 else (@as(f32, @floatFromInt(im.get(j, i + k).get_r())) / 255.0);
        }
        sample /= @as(f32, @floatFromInt(num_samples)) + 1;
    }
    return sample;
}

export fn asciify(name: [*:0]const u8, len: usize) usize {
    const name_slice: []const u8 = name[0..len];
    var ret: usize = 0;
    std.debug.print("asciifying {s}\n", .{name});
    img2ascii(name_slice) catch |err| {
        std.debug.print("Error occured: {any}\n", .{err});
        ret = 1;
    };

    return ret;
}

pub fn img2ascii(name: []const u8) Error!void {
    var im: Image = undefined;
    const extension: []const u8 = name[name.len - 3 ..];
    std.debug.print("Loading image\n", .{});
    if (std.mem.eql(u8, extension, "jpg") or std.mem.eql(u8, name[name.len - 4 ..], "jpeg")) {
        std.debug.print("Loading jpeg\n", .{});
        im = try Image.init_load(allocator, name, .JPEG);
        std.debug.print("jpeg loaded\n", .{});
    } else if (std.mem.eql(u8, extension, "bmp")) {
        im = try Image.init_load(allocator, name, .BMP);
    } else if (std.mem.eql(u8, extension, "png")) {
        im = try Image.init_load(allocator, name, .PNG);
    } else {
        IMG2ASCII_LOG.err("Image must be .jpg/.png/.bmp\n", .{});
    }
    std.debug.print("Converting to grayscale\n", .{});
    try im.convert_grayscale();
    std.debug.print("Scaling\n", .{});
    try im.scale(600, 400, .BICUBIC);
    defer im.deinit();
    var sample: u32 = 1;
    if ((im.height) > ascii_height) {
        sample = 2;
    }
    while ((im.height / sample) > ascii_height) {
        sample += 2;
    }
    const SCALE = 1.0 / @as(f32, @floatFromInt(sample));
    var ascii_pixels: []u8 = try allocator.alloc(u8, im.height + @as(usize, @intFromFloat(@ceil(@as(f32, @floatFromInt(im.width)) * @as(f32, @floatFromInt(im.height)) * SCALE))));
    for (ascii_pixels) |*pix| {
        pix.* = ' ';
    }
    var ascii_index: usize = 0;
    var i: usize = 0;
    var j: usize = 0;
    while (i < im.height) : (i += sample) {
        while (j < im.width) : (j += sample) {
            const pixel_value = try sample_pixel(&im, i, j, sample);
            var ascii_char_index: usize = @as(usize, @intFromFloat(pixel_value * @as(f32, @floatFromInt(ASCII_CHARS.len))));
            ascii_char_index = if (ascii_char_index >= ASCII_CHARS.len) ASCII_CHARS.len - 1 else ascii_char_index;
            ascii_pixels[ascii_index] = ASCII_CHARS[ascii_char_index];
            ascii_index += 1;
        }
        j = 0;
        ascii_pixels[ascii_index] = '\n';
        ascii_index += 1;
    }

    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("{s}\n", .{ascii_pixels});
    try bw.flush();

    var output_string = std.ArrayList(u8).init(allocator);
    try output_string.writer().print("{s}txt", .{name[0 .. name.len - 3]});
    var ascii_file = try std.fs.cwd().createFile(output_string.items, .{});
    std.ArrayList(u8).deinit(output_string);
    try ascii_file.writeAll(ascii_pixels);
    ascii_file.close();
    allocator.free(ascii_pixels);
}

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    if (builtin.os.tag != .emscripten) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        allocator = gpa.allocator();
    } else {
        allocator = std.heap.c_allocator;
    }
    if (builtin.os.tag != .emscripten) {
        const argsv = try std.process.argsAlloc(allocator);
        //std.debug.print("args {s} {s} {s}", .{ argsv[0], argsv[1], argsv[2] });
        if (argsv.len > 1) {
            if (argsv.len == 3) {
                ascii_height = try std.fmt.parseInt(u32, argsv[2], 10);
            }
            if (argsv.len >= 2) {
                if (argsv[1].len < 3) {
                    try stdout.print("Image must be .jpg/.png/.bmp\n", .{});
                    try bw.flush();
                    return;
                } else {
                    const dupe = try allocator.dupeZ(u8, argsv[1]);
                    defer allocator.free(dupe);
                    _ = asciify(dupe, argsv[1].len);
                }
            } else {
                try stdout.print("Usage: {s} image_file ascii_height\n", .{argsv[0]});
                try bw.flush();
            }
        } else {
            const def = "tests/png/shield.png";
            const dupe = try allocator.dupeZ(u8, def);
            defer allocator.free(dupe);
            _ = asciify(dupe, def.len);
        }
        std.process.argsFree(allocator, argsv);
    }
}
