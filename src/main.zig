const std = @import("std");
const builtin = @import("builtin");
const image = @import("image");

pub const Image = image.Image;
const ASCII_CHARS = [_]u8{ ' ', '.', ':', 'c', 'o', '?', 'P', 'O', '#', '@' };

const Error = error{
    INVALID_ARG,
    SAMPLE_ERROR,
} || Image.Error || std.mem.Allocator.Error;

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

pub fn img2ascii(im: *Image, ascii_height: u32, allocator: std.mem.Allocator) Error![]u8 {
    try im.convert_grayscale();
    defer im.deinit();
    var sample: u32 = 1;
    if ((im.height) > ascii_height) {
        sample = 2;
    }
    while ((im.height / sample) > ascii_height) {
        sample += 2;
    }
    std.debug.print("sample rate {d}\n", .{sample});
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
            const pixel_value = try sample_pixel(im, i, j, sample);
            var ascii_char_index: usize = @as(usize, @intFromFloat(pixel_value * @as(f32, @floatFromInt(ASCII_CHARS.len))));
            ascii_char_index = if (ascii_char_index >= ASCII_CHARS.len) ASCII_CHARS.len - 1 else ascii_char_index;
            ascii_pixels[ascii_index] = ASCII_CHARS[ascii_char_index];
            ascii_index += 1;
        }
        j = 0;
        ascii_pixels[ascii_index] = '\n';
        ascii_index += 1;
    }

    return ascii_pixels;
}

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    try stdout.print("\x1B[91m", .{});
    try bw.flush();
    var allocator: std.mem.Allocator = undefined;
    if (builtin.os.tag != .emscripten) {
        const gpa = std.heap.GeneralPurposeAllocator(.{}){};
        allocator = gpa.allocator();
    } else {
        allocator = std.heap.c_allocator;
    }
    const argsv = if (builtin.os.tag != .emscripten) try std.process.argsAlloc(allocator) else &[_][]const u8{
        "img2ascii",
        "tests/jpeg/cat.jpg",
    };
    var ascii_image: []u8 = undefined;
    var ascii_height: u32 = 100;
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
                const extension = argsv[1][argsv[1].len - 3 ..];
                if (std.mem.eql(u8, extension, "jpg")) {
                    var im = try Image.init_load(allocator, argsv[1], .JPEG);
                    ascii_image = try img2ascii(&im, ascii_height, allocator);
                } else if (std.mem.eql(u8, extension, "bmp")) {
                    var im = try Image.init_load(allocator, argsv[1], .BMP);
                    ascii_image = try img2ascii(&im, ascii_height, allocator);
                } else if (std.mem.eql(u8, extension, "png")) {
                    var im = try Image.init_load(allocator, argsv[1], .PNG);
                    ascii_image = try img2ascii(&im, ascii_height, allocator);
                } else {
                    try stdout.print("Image must be .jpg/.png/.bmp\n", .{});
                    try bw.flush();
                }
            }
        } else {
            try stdout.print("Usage: {s} image_file ascii_height\n", .{argsv[0]});
            try bw.flush();
        }
    } else {
        var im = try Image.init_load(allocator, "tests/png/shield.png", .PNG);
        ascii_image = try img2ascii(&im, ascii_height, allocator);
    }
    try stdout.print("{s}\n", .{ascii_image});
    try bw.flush(); // don't forget to flush!
    var ascii_file: std.fs.File = undefined;
    if (argsv.len > 1) {
        var output_string = std.ArrayList(u8).init(allocator);
        try output_string.writer().print("{s}txt", .{argsv[1][0 .. argsv[1].len - 3]});
        ascii_file = try std.fs.cwd().createFile(output_string.items, .{});
        std.ArrayList(u8).deinit(output_string);
    } else {
        ascii_file = try std.fs.cwd().createFile("shield.txt", .{});
    }

    try ascii_file.writeAll(ascii_image);
    ascii_file.close();
    allocator.free(ascii_image);
    try stdout.print("\x1B[0m", .{});
    try bw.flush();

    if (builtin.os.tag != .emscripten) std.process.argsFree(allocator, argsv);
}
