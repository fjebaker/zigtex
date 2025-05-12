const std = @import("std");
const ztex = @import("zigtex");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var render = try ztex.TexSvgRender.init(allocator, .{});
    defer render.deinit();

    const tex =
        \\\frac{\text{d}}{\text{d} t} \left( \frac{\partial L}{\partial \dot{q}} \right) = \frac{\partial L}{\partial q}.
    ;

    const output = try render.parseRender(allocator, tex, .{});
    defer allocator.free(output);

    var f = try std.fs.cwd().createFile("example.svg", .{});
    defer f.close();
    try f.writeAll(output);
}
