const std = @import("std");
const c = @import("c.zig");

fn checkReturn(code: c_uint) !void {
    switch (code) {
        c.TVG_RESULT_SUCCESS => {},
        c.TVG_RESULT_UNKNOWN => return error.ThorvgUnknown,
        c.TVG_RESULT_NOT_SUPPORTED => return error.ThorvgNotSupported,
        else => {
            std.log.default.err("thorvg error: {d}", .{code});
            return error.ThorvgError;
        },
    }
}

pub fn init() !void {
    const ret = c.tvg_engine_init(c.TVG_ENGINE_SW, 0);
    try checkReturn(ret);
}

pub fn deinit() void {
    _ = c.tvg_engine_term(c.TVG_ENGINE_SW);
}

pub const Canvas = struct {
    pub const Options = struct {};

    ptr: ?*c.Tvg_Canvas,

    pub fn init(opts: Options) Canvas {
        _ = opts;
        return .{
            .ptr = c.tvg_swcanvas_create(),
        };
    }

    pub fn deinit(self: *Canvas) void {
        c.tvg_canvas_destroy(self.ptr);
    }

    pub fn sync(self: Canvas) !void {
        try checkReturn(c.tvg_canvas_sync(self.ptr));
    }

    pub fn draw(self: Canvas) !void {
        try checkReturn(c.tvg_canvas_draw(self.ptr));
    }

    pub fn push(self: Canvas, obj: anytype) !void {
        if (!@hasDecl(@TypeOf(obj), "_Push") or !@TypeOf(obj)._Push) {
            @compileError("Cannot save object of such type");
        }
        try checkReturn(c.tvg_canvas_push(self.ptr, obj.ptr));
    }
};

pub const Scene = struct {
    const _Save = true;
    ptr: ?*c.Tvg_Paint,

    pub fn init() Scene {
        return .{ .ptr = c.tvg_scene_new() };
    }

    pub fn push(self: Scene, obj: anytype) !void {
        if (!@hasDecl(@TypeOf(obj), "_Push") or !@TypeOf(obj)._Push) {
            @compileError("Cannot save object of such type");
        }
        try checkReturn(c.tvg_scene_push(self.ptr, obj.ptr));
    }
};

pub const Shape = struct {
    const _Push = true;
    const _Save = true;

    ptr: ?*c.Tvg_Paint,

    pub fn init() Shape {
        return .{ .ptr = c.tvg_shape_new() };
    }

    pub fn close(self: Shape) !void {
        try checkReturn(c.tvg_shape_close(self.ptr));
    }

    pub fn move_to(self: Shape, x: f32, y: f32) !void {
        try checkReturn(c.tvg_shape_move_to(self.ptr, x, y));
    }

    pub fn line_to(self: Shape, x: f32, y: f32) !void {
        try checkReturn(c.tvg_shape_move_to(self.ptr, x, y));
    }
};

pub const Saver = struct {
    ptr: ?*c.Tvg_Saver,

    pub fn init() Saver {
        return .{ .ptr = c.tvg_saver_new() };
    }

    pub fn deinit(self: *Saver) void {
        _ = c.tvg_saver_del(self.ptr);
    }

    pub fn save(self: Saver, obj: anytype, name: [:0]const u8) !void {
        if (!@hasDecl(@TypeOf(obj), "_Save") or !@TypeOf(obj)._Save) {
            @compileError("Cannot save object of such type");
        }
        try checkReturn(c.tvg_saver_save(self.ptr, obj.ptr, name.ptr, 100));
    }
};
