const std = @import("std");

pub const Svg = struct {
    pub const State = enum {
        none,
        in_path,
        path_done,
    };
    buffer: std.ArrayList(u8),
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
            .buffer = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Svg) void {
        self.buffer.deinit();
        self.* = undefined;
    }

    fn xfmX(self: *const Svg, x: f32) f32 {
        return self.tx + (x * self.sx) + 5;
    }
    fn xfmY(self: *const Svg, y: f32) f32 {
        return self.ty + (y * self.sy) + 20;
    }

    pub fn moveTo(self: *Svg, x: f32, y: f32) !void {
        try self.buffer.writer().print("M{d} {d} ", .{
            self.xfmX(x),
            self.xfmY(y),
        });
    }

    pub fn lineTo(self: *Svg, x: f32, y: f32) !void {
        try self.buffer.writer().print("L{d} {d} ", .{
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
        try self.buffer.writer().print("C{d} {d}, {d} {d}, {d} {d} ", .{
            self.xfmX(dx1),
            self.xfmY(dy1),
            self.xfmX(dx2),
            self.xfmY(dy2),
            self.xfmX(x),
            self.xfmY(y),
        });
    }

    pub fn beginPath(self: *Svg) !void {
        switch (self.state) {
            .none => {
                try self.buffer.appendSlice("<path d=\"");
                self.state = .in_path;
            },
            .path_done => {
                try self.buffer.appendSlice("/>\n<path d=\"");
                self.state = .in_path;
            },
            else => unreachable,
        }
    }

    pub fn closePath(self: *Svg) !void {
        switch (self.state) {
            .path_done, .in_path => {
                try self.buffer.appendSlice("Z ");
                self.state = .path_done;
            },
            else => {},
        }
    }

    pub fn fillPath(self: *Svg) !void {
        switch (self.state) {
            .path_done => {
                try self.buffer.appendSlice("\" fill=\"black\"");
            },
            else => unreachable,
        }
    }

    pub fn translate(self: *Svg, x: f32, y: f32) void {
        self.tx = x * self.sx;
        self.ty = y * self.sy;
    }

    pub fn scale(self: *Svg, x: f32, y: f32) void {
        self.sx *= x;
        self.sy *= y;
    }

    pub fn writeHeader(self: *Svg) !void {
        try self.buffer.appendSlice(
            \\<?xml version="1.0" encoding="UTF-8"?>
            \\<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">
            \\<svg xmlns="http://www.w3.org/2000/svg" width="600" height="200" viewBox="0 0 600 200">
        );
    }

    pub fn writeFooter(self: *Svg) !void {
        try self.buffer.appendSlice("/>\n</svg>\n");
    }
};
