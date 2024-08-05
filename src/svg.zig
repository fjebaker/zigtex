const std = @import("std");

pub const Svg = struct {
    const AttrMap = std.StringHashMap([]const u8);

    pub const Tag = struct {
        name: []const u8,
        id: usize,
        attr: AttrMap,
        path: std.ArrayList(u8),

        pub fn write(self: *const Tag, writer: anytype) !void {
            try writer.print("<{s}", .{self.name});
            if (self.path.items.len > 0) {
                try writer.print(" d=\"{s}\"", .{self.path.items});
            }
            var itt = self.attr.iterator();
            while (itt.next()) |item| {
                try writer.print(
                    " {s}=\"{s}\"",
                    .{ item.key_ptr.*, item.value_ptr.* },
                );
            }
            try writer.writeAll("/>");
        }

        pub fn appendPath(
            self: *Tag,
            comptime fmt: []const u8,
            args: anytype,
        ) !void {
            if (self.path.items.len > 0) {
                try self.path.append(' ');
            }
            try self.path.writer().print(fmt, args);
        }
    };

    pub const State = enum {
        none,
        in_path,
        path_done,
    };

    arena: std.heap.ArenaAllocator,
    tags: std.ArrayList(Tag),

    state: State = .none,
    color: u32 = 0x3b3b3bff,
    // translation
    tx: f32 = 0,
    ty: f32 = 0,
    // scaling
    sx: f32 = 1,
    sy: f32 = 1,

    x_min: f32 = std.math.floatMax(f32),
    y_min: f32 = std.math.floatMax(f32),
    x_max: f32 = std.math.floatMin(f32),
    y_max: f32 = std.math.floatMin(f32),

    x_pad: f32 = 0,
    y_pad: f32 = 0,

    pub fn init(allocator: std.mem.Allocator) Svg {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .tags = std.ArrayList(Tag).init(allocator),
        };
    }

    fn newTag(self: *Svg, name: []const u8, id: usize) !*Tag {
        const ptr = try self.tags.addOne();
        ptr.name = name;
        ptr.id = id;
        ptr.attr = AttrMap.init(self.arena.allocator());
        ptr.path = std.ArrayList(u8).init(self.arena.allocator());
        return ptr;
    }

    pub fn deinit(self: *Svg) void {
        self.tags.deinit();
        self.arena.deinit();
        self.* = undefined;
    }

    inline fn current(self: *const Svg) *Tag {
        std.debug.assert(self.tags.items.len > 0);
        return &self.tags.items[self.tags.items.len - 1];
    }
    inline fn xfmXNoSave(self: *const Svg, x: f32) f32 {
        return x * self.sx + self.tx;
    }
    inline fn xfmYNoSave(self: *const Svg, y: f32) f32 {
        return y * self.sy + self.ty;
    }
    inline fn xfmX(self: *Svg, x: f32) f32 {
        const new_x = self.xfmXNoSave(x);
        self.x_min = @min(new_x, self.x_min);
        self.x_max = @max(new_x, self.x_max);
        return new_x;
    }
    inline fn xfmY(self: *Svg, y: f32) f32 {
        const new_y = self.xfmYNoSave(y);
        self.y_min = @min(new_y, self.y_min);
        self.y_max = @max(new_y, self.y_max);
        return new_y;
    }

    pub fn setColor(self: *Svg, r: u8, g: u8, b: u8, alpha: u8) void {
        const color =
            (@as(u32, @intCast(r)) << 24) +
            (@as(u32, @intCast(g)) << 16) +
            (@as(u32, @intCast(b)) << 8) +
            (alpha);
        self.color = color;
    }

    pub fn moveTo(self: *Svg, x: f32, y: f32) !void {
        try self.current().appendPath("M{d} {d}", .{
            self.xfmX(x),
            self.xfmY(y),
        });
    }

    pub fn lineTo(self: *Svg, x: f32, y: f32) !void {
        try self.current().appendPath("L{d} {d}", .{
            self.xfmX(x),
            self.xfmY(y),
        });
    }

    pub fn cubicTo(
        self: *Svg,
        dx1: f32,
        dy1: f32,
        dx2: f32,
        dy2: f32,
        x: f32,
        y: f32,
    ) !void {
        try self.current().appendPath("C{d} {d}, {d} {d}, {d} {d}", .{
            self.xfmX(dx1),
            self.xfmY(dy1),
            self.xfmX(dx2),
            self.xfmY(dy2),
            self.xfmX(x),
            self.xfmY(y),
        });
    }

    pub fn beginPath(self: *Svg, id: usize) !void {
        _ = try self.newTag("path", id);
    }

    pub fn closePath(self: *Svg) !void {
        try self.current().appendPath("Z", .{});
    }

    pub fn fillPath(self: *Svg) !void {
        const color = try std.fmt.allocPrint(
            self.arena.allocator(),
            "#{x:0>8}",
            .{self.color},
        );
        try self.current().attr.put("fill", color);
    }

    pub fn translate(self: *Svg, x: f32, y: f32) void {
        self.tx = x * self.sx;
        self.ty = y * self.sy;
    }

    pub fn scale(self: *Svg, x: f32, y: f32) void {
        self.sx *= x;
        self.sy *= y;
    }

    pub const WriteOptions = struct {
        svg_content: ?[]const u8 = null,
    };

    pub fn write(self: *const Svg, writer: anytype, opts: WriteOptions) !void {
        try self.writeHeader(writer);
        try writer.writeByte('\n');

        const indent: usize = 1;
        for (self.tags.items) |tag| {
            try writer.writeByteNTimes(' ', indent * 2);
            try tag.write(writer);
            try writer.writeByte('\n');
        }

        try self.writeFooter(writer, opts.svg_content);
    }

    fn writeHeader(self: *const Svg, writer: anytype) !void {
        if (self.x_min >= self.x_max) return error.BadViewbox;
        if (self.y_min >= self.y_max) return error.BadViewbox;
        try writer.print(
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\  <!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
            \\  <svg xmlns="http://www.w3.org/2000/svg" viewBox="{d} {d} {d} {d}">
        , .{
            self.x_min - self.x_pad,
            self.y_min - self.x_pad,
            self.x_max + 2 * self.x_pad,
            self.y_max + 2 * self.y_pad,
        });
    }

    fn writeFooter(_: *const Svg, writer: anytype, content: ?[]const u8) !void {
        if (content) |c| {
            try writer.print("  {s}\n</svg>", .{c});
        } else {
            try writer.writeAll("</svg>");
        }
    }
};
