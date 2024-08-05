const std = @import("std");
const c = @import("c.zig");
const microtex = @import("root.zig");

const CLM_PATH = "./latinmodern-math.clm2";

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var svg_context = microtex.FontContext.init(allocator);
    defer svg_context.deinit();

    microtex.setRenderGlyphUsePath(true);

    var mtex = try microtex.MicroTeX.init(allocator, CLM_PATH, &svg_context);
    defer mtex.deinit();

    var render = try mtex.parseRender("x^2 = 4", .{});
    defer render.deinit();

    var data = render.getDrawingData(8, 8);
    while (data.next()) |cmd| {
        std.debug.print("-> {any}\n", .{cmd});
    }
}
