const std = @import("std");
const builtin = @import("builtin");
const image = @import("image");

pub const Image = image.Image;
const ASCII_CHARS = [_]u8{ ' ', '.', ':', 'c', 'o', '?', 'P', 'O', '#', '@' };

const Error = error{
    INVALID_ARG,
    SAMPLE_ERROR,
} || Image.Error || std.mem.Allocator.Error;

var allocator: std.mem.Allocator = undefined;
var ascii_height: u32 = 100;

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
    var ascii_image: []u8 = undefined;
    const name_slice: []const u8 = name[0..len];
    const extension: []const u8 = name_slice[len - 3 ..];

    if (std.mem.eql(u8, extension, "jpg")) {
        var im = Image.init_load(allocator, name_slice, .JPEG) catch {
            return 1;
        };
        ascii_image = img2ascii(&im) catch {
            return 1;
        };
    } else if (std.mem.eql(u8, extension, "bmp")) {
        var im = Image.init_load(allocator, name_slice, .BMP) catch {
            return 1;
        };
        ascii_image = img2ascii(&im) catch {
            return 1;
        };
    } else if (std.mem.eql(u8, extension, "png")) {
        var im = Image.init_load(allocator, name_slice, .PNG) catch {
            return 1;
        };
        ascii_image = img2ascii(&im) catch {
            return 1;
        };
    } else {
        std.debug.print("Image must be .jpg/.png/.bmp\n", .{});
    }
    std.debug.print("Generated ascii_image len {d}\n {s}\n", .{ ascii_image.len, ascii_image });
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();
    stdout.print("{s}\n", .{ascii_image}) catch {
        return 1;
    };
    bw.flush() catch {
        return 1;
    };

    var output_string = std.ArrayList(u8).init(allocator);
    output_string.writer().print("{s}txt", .{name_slice[0 .. len - 3]}) catch {
        return 1;
    };
    var ascii_file = std.fs.cwd().createFile(output_string.items, .{}) catch {
        return 1;
    };
    std.ArrayList(u8).deinit(output_string);
    ascii_file.writeAll(ascii_image) catch {
        return 1;
    };
    ascii_file.close();
    allocator.free(ascii_image);
    return 0;
}

pub fn img2ascii(im: *Image) Error![]u8 {
    try im.convert_grayscale();
    //try im.scale(600, 400);
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
    if (builtin.os.tag != .emscripten) {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        allocator = gpa.allocator();
    } else {
        allocator = std.heap.c_allocator;
    }
    if (builtin.os.tag != .emscripten) {
        const argsv = try std.process.argsAlloc(allocator);
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
