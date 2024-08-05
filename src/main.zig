const std = @import("std");
const microtex = @import("root.zig");
const svg = @import("svg.zig");

const CLM_DATA = @embedFile("@DEFAULT_FONT@");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var svg_context = microtex.FontContext.init(allocator);
    defer svg_context.deinit();

    microtex.setRenderGlyphUsePath(true);

    var mtex = try microtex.MicroTeX.init(allocator, CLM_DATA, &svg_context);
    defer mtex.deinit();

    // var render = try mtex.parseRender("\\int_0^\\infty e^{i \\pi t \\nu} f(t) \\text{d}\\nu", .{});
    var render = try mtex.parseRender(
        \\\begin{equation}
        \\    \int_0^\infty e^{i \pi t \nu} f(t) \text{d}\nu
        \\\end{equation}
    , .{});
    defer render.deinit();

    var data = render.getDrawingData(10, 10);

    var s = svg.Svg.init(allocator);
    defer s.deinit();

    try s.writeHeader();

    while (data.next()) |cmd| {
        switch (cmd) {
            .set_color => |c| {
                const C = packed struct {
                    x1: u8,
                    x2: u8,
                    x3: u8,
                    x4: u8,
                };
                const a: C = @bitCast(c);
                s.color =
                    (@as(u32, @intCast(a.x2)) << 24) +
                    (@as(u32, @intCast(a.x3)) << 16) +
                    (@as(u32, @intCast(a.x4)) << 8) +
                    (a.x1);
            },
            .translate => |i| s.translate(i.x, i.y),
            .scale => |i| s.scale(i.x, i.y),
            .move_to => |i| try s.moveTo(i.x, i.y),
            .line_to => |i| try s.lineTo(i.x, i.y),
            .cubic_to => |i| try s.cubicTo(i.x1, i.y1, i.x2, i.y2, i.x3, i.y3),
            .begin_path => try s.beginPath(),
            .close_path => try s.closePath(),
            .fill_path => try s.fillPath(),
            else => {
                std.log.default.warn("Unhandled opcopde: {any}", .{cmd});
            },
        }
    }

    try s.writeFooter();

    var f = try std.fs.cwd().createFile("example.svg", .{});
    defer f.close();

    try f.writeAll(s.buffer.items);
}
