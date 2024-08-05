const std = @import("std");
const ztex = @import("root.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var render = try ztex.TexSvgRender.init(allocator, .{});
    defer render.deinit();

    const tex =
        \\\begin{equation}
        \\    \tilde{F}(\nu) = \int_0^\infty e^{-i \pi t \nu} f(t) \text{d}t
        \\\end{equation}
    ;

    const output = try render.parseRender(allocator, tex, .{});
    defer allocator.free(output);

    var f = try std.fs.cwd().createFile("example.svg", .{});
    defer f.close();
    try f.writeAll(output);
}
