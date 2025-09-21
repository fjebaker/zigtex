const std = @import("std");
pub const microtex = @import("tex.zig");
pub const svg = @import("svg.zig");

const DEFAULT_FONT = @embedFile("@DEFAULT_FONT@");

pub const TexSvgRender = struct {
    pub const Options = struct {
        font_data: []const u8 = DEFAULT_FONT,
    };

    context: microtex.FontContext,
    mtex: microtex.MicroTeX,

    pub fn init(
        allocator: std.mem.Allocator,
        opts: Options,
    ) !TexSvgRender {
        microtex.setRenderGlyphUsePath(true);
        var context = microtex.FontContext.init(allocator);
        errdefer context.deinit();

        const mtex = try microtex.MicroTeX.init(
            allocator,
            opts.font_data,
            &context,
        );
        errdefer mtex.deinit();
        return .{
            .context = context,
            .mtex = mtex,
        };
    }

    pub fn deinit(self: *TexSvgRender) void {
        self.mtex.deinit();
        self.context.deinit();
        self.* = undefined;
    }

    pub const RenderOptions = struct {
        size: usize = 20,
        spacing: usize = 6,
        style: ?enum { display, in_line } = null,
        x_pad: u32 = 3,
        y_pad: u32 = 3,
        full_header: bool = true,
        class: ?[]const u8 = null,
        /// RBGA
        default_color: []const u8 = "#3b3b3b",
    };

    pub fn parseRender(
        self: *TexSvgRender,
        allocator: std.mem.Allocator,
        tex: []const u8,
        opts: RenderOptions,
    ) ![]const u8 {
        const null_term = try allocator.dupeZ(u8, tex);
        defer allocator.free(null_term);

        const style: u32 = b: {
            if (opts.style) |s| {
                break :b switch (s) {
                    .display => 1,
                    .in_line => 0,
                };
            }
            break :b 0;
        };

        var r = try self.mtex.parseRender(null_term, .{
            .text_size = @floatFromInt(opts.size),
            .line_space = @floatFromInt(opts.spacing),
            .override_syle = opts.style == null,
            .style = style,
            .color = 0,
        });
        defer r.deinit();

        var data = r.getDrawingData(opts.x_pad, opts.y_pad);

        var s = svg.Svg.init(allocator);
        defer s.deinit();

        s.x_pad = @floatFromInt(opts.x_pad);
        s.y_pad = @floatFromInt(opts.y_pad);
        s.setColor(opts.default_color);

        var color: [9]u8 = undefined;
        while (data.next()) |cmd| {
            switch (cmd) {
                .set_color => |c| {
                    if (c == 0) {
                        s.setColor(opts.default_color);
                    } else {
                        s.setColor(try std.fmt.bufPrint(&color, "#{x:0>6}", .{c >> 8}));
                    }
                },
                .translate => |i| s.translate(i.x, i.y),
                .scale => |i| s.scale(i.x, i.y),
                .move_to => |i| try s.moveTo(i.x, i.y),
                .line_to => |i| try s.lineTo(i.x, i.y),
                .cubic_to => |i| try s.cubicTo(i.x1, i.y1, i.x2, i.y2, i.x3, i.y3),
                .begin_path => |id| try s.beginPath(@intCast(id)),
                .close_path => try s.closePath(),
                .fill_path => try s.fillPath(),
                .draw_line => |i| try s.drawLine(i.x1, i.y1, i.x2, i.y2),
                .set_stroke => |i| try s.setStroke(i.width),
                else => {
                    std.log.default.warn("Unhandled opcopde: {any}", .{cmd});
                },
            }
        }
        var buf = std.ArrayList(u8).empty;
        defer buf.deinit(allocator);
        var buf_writer = buf.writer(allocator).adaptToNewApi(&.{});
        try s.write(&buf_writer.new_interface, .{
            .full_header = opts.full_header,
            .svg_content = tex,
            .class = opts.class,
        });
        return buf.toOwnedSlice(allocator);
    }
};
