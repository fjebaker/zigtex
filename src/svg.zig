const std = @import("std");

pub const Svg = struct {
    pub const State = enum {
        none,
        in_path,
        path_done,
    };
    buffer: std.ArrayList(u8),
    path: std.ArrayList(u8),
    arena: std.heap.ArenaAllocator,
    attr: std.StringHashMap([]const u8),

    color: u32 = 0,
    state: State = .none,
    // translation
    tx: f32 = 0,
    ty: f32 = 0,
    // scaling
    sx: f32 = 2,
    sy: f32 = 2,

    pub fn init(allocator: std.mem.Allocator) Svg {
        return .{
            .arena = std.heap.ArenaAllocator.init(allocator),
            .attr = std.StringHashMap([]const u8).init(allocator),
            .buffer = std.ArrayList(u8).init(allocator),
            .path = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Svg) void {
        self.buffer.deinit();
        self.path.deinit();
        self.attr.deinit();
        self.arena.deinit();
        self.* = undefined;
    }

    fn xfmX(self: *const Svg, x: f32) f32 {
        return self.tx + (x * self.sx) + 5;
    }
    fn xfmY(self: *const Svg, y: f32) f32 {
        return (self.ty + y) * self.sy + 20;
    }

    pub fn moveTo(self: *Svg, x: f32, y: f32) !void {
        try self.path.writer().print("M{d} {d} ", .{
            x,
            y,
        });
    }

    pub fn lineTo(self: *Svg, x: f32, y: f32) !void {
        try self.path.writer().print("L{d} {d} ", .{
            x,
            y,
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
        try self.path.writer().print("C{d} {d}, {d} {d}, {d} {d} ", .{
            dx1,
            dy1,
            dx2,
            dy2,
            x,
            y,
        });
    }

    fn writeAttr(self: *Svg) !void {
        const writer = self.buffer.writer();
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

        self.path.clearRetainingCapacity();
        self.attr.clearRetainingCapacity();
    }

    pub fn beginPath(self: *Svg) !void {
        switch (self.state) {
            .none => {
                try self.buffer.appendSlice("<path");
                self.state = .in_path;
            },
            .path_done => {
                try self.writeAttr();
                try self.buffer.appendSlice("/>\n<path");
                self.state = .in_path;
            },
            else => unreachable,
        }
    }

    pub fn closePath(self: *Svg) !void {
        switch (self.state) {
            .path_done, .in_path => {
                try self.path.appendSlice("Z ");
                self.state = .path_done;
            },
            else => {},
        }
    }

    pub fn fillPath(self: *Svg) !void {
        switch (self.state) {
            .path_done => {
                try self.attr.put("fill", "black");
            },
            else => unreachable,
        }
    }

    fn modAttr(
        self: *Svg,
        name: []const u8,
        comptime fmt: []const u8,
        args: anytype,
    ) !void {
        std.debug.print("name: {s} ++ {s}\n", .{ name, fmt });
        const s = try std.fmt.allocPrint(
            self.arena.allocator(),
            fmt,
            args,
        );
        if (self.attr.contains(name)) {
            const ptr = self.attr.getPtr(name).?;
            ptr.* = try std.mem.join(
                self.arena.allocator(),
                " ",
                &.{ ptr.*, s },
            );
        } else {
            try self.attr.put(name, s);
        }
    }

    pub fn translate(self: *Svg, x: f32, y: f32) !void {
        try self.modAttr("transform", "translate({d} {d})", .{ x, y });
    }

    pub fn scale(self: *Svg, x: f32, y: f32) !void {
        try self.modAttr("transform", "scale({d} {d})", .{ x, y });
    }

    pub fn writeHeader(self: *Svg) !void {
        try self.buffer.appendSlice(
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
            \\<svg xmlns="http://www.w3.org/2000/svg" width="600" height="200" viewBox="0 0 600 200">
        );
    }

    pub fn writeFooter(self: *Svg) !void {
        try self.writeAttr();
        try self.buffer.appendSlice("/>\n</svg>\n");
    }
};
