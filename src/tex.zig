const std = @import("std");
pub const c = @cImport({
    @cDefine("HAVE_CWRAPPER", "");
    @cInclude("stdbool.h");
    @cInclude("wrapper/cwrapper.h");
});

pub const FontDescription = struct {
    f: *c.FontDesc,
};

pub const TextLayoutBounds = struct {
    b: *c.TextLayoutBounds,

    pub fn setBounds(
        self: TextLayoutBounds,
        width: f32,
        height: f32,
        ascent: f32,
    ) void {
        c.microtex_setTextLayoutBounds(
            self.b,
            width,
            height,
            ascent,
        );
    }
};

pub const MicroTeX = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    clm_data: []const u8,
    font_meta: c.FontMetaPtr,

    var ctx: *anyopaque = undefined;

    pub fn initPath(
        allocator: std.mem.Allocator,
        clm_path: []const u8,
        context: anytype,
    ) !Self {
        const stat = try std.fs.cwd().statFile(clm_path);
        const content = try std.fs.cwd().readFileAlloc(
            allocator,
            clm_path,
            stat.size,
        );
        defer allocator.free(content);
        return try init(allocator, content, context);
    }

    pub fn init(allocator: std.mem.Allocator, clm_data: []const u8, context: anytype) !Self {
        if (c.microtex_isInited()) {
            return error.MicroTeXAlreadyInitialized;
        }

        const Ctx = @typeInfo(@TypeOf(context)).pointer.child;
        ctx = context;

        const CallbackWrapper = struct {
            fn createTextLayout(
                text: [*c]const u8,
                f: [*c]c.FontDesc,
            ) callconv(.c) c_uint {
                const slice = std.mem.span(text);
                const id: usize =
                    Ctx.createTextLayout(
                        @ptrCast(@alignCast(ctx)),
                        slice,
                        FontDescription{ .f = f },
                    ) catch |err| {
                        std.log.default.err("createTextLayout: {t}", .{err});
                        return 0;
                    };
                return @intCast(id);
            }
            fn getTextLayoutBounds(
                id: c_uint,
                b: [*c]c.TextLayoutBounds,
            ) callconv(.c) void {
                Ctx.getTextLayoutBounds(
                    @ptrCast(@alignCast(ctx)),
                    @as(usize, @intCast(id)),
                    TextLayoutBounds{ .b = b },
                ) catch |err| {
                    std.log.default.err("getTextlayoutBounds: {t}", .{err});
                    return 0;
                };
            }
            fn releaseTextLayout(id: c_uint) callconv(.c) void {
                Ctx.releaseTextLayout(
                    @ptrCast(@alignCast(ctx)),
                    @as(usize, @intCast(id)),
                );
            }
            fn isPathExists(id: c_uint) callconv(.c) bool {
                return Ctx.isPathExists(
                    @ptrCast(@alignCast(ctx)),
                    @as(usize, @intCast(id)),
                );
            }
        };

        // register the callback functions
        c.microtex_registerCallbacks(
            CallbackWrapper.createTextLayout,
            CallbackWrapper.getTextLayoutBounds,
            CallbackWrapper.releaseTextLayout,
            CallbackWrapper.isPathExists,
        );

        const content = try allocator.dupe(u8, clm_data);
        const font_meta = c.microtex_init(content.len, content.ptr);

        const name = c.microtex_getFontName(font_meta);
        c.microtex_setDefaultMainFont(name);
        c.microtex_setDefaultMathFont(name);

        return .{
            .allocator = allocator,
            .clm_data = content,
            .font_meta = font_meta,
        };
    }

    pub fn deinit(self: *Self) void {
        c.microtex_release();
        self.allocator.free(self.clm_data);
        self.* = undefined;
    }

    pub const ParseOptions = struct {
        width: u32 = 0,
        text_size: f32 = 20,
        line_space: f32 = 20 / 3,
        /// 0xAARRGGBB
        color: u32,
        fill_width: bool = false,
        override_syle: bool = true,
        style: u32 = 0,
    };

    pub fn parseRender(
        self: *const Self,
        tex: [:0]const u8,
        opts: ParseOptions,
    ) !Render {
        _ = self;
        const ptr = c.microtex_parseRender(
            tex.ptr,
            @intCast(opts.width),
            opts.text_size,
            opts.line_space,
            @intCast(opts.color),
            opts.fill_width,
            opts.override_syle,
            @intCast(opts.style),
        );
        if (ptr == null) return error.FailedToRender;
        return .{ .ptr = ptr };
    }
};

fn getRawDrawingData(
    data: c.DrawingData,
    offset: usize,
    size: usize,
) []const u8 {
    const ptr: [*]const u8 = @ptrCast(@alignCast(data.?));
    return ptr[offset .. offset + size];
}

fn getRawDrawingDataT(
    data: c.DrawingData,
    offset: usize,
    comptime T: type,
) T {
    const slice = getRawDrawingData(data, offset, @sizeOf(T));
    return std.mem.bytesToValue(T, slice);
}

pub const Render = struct {
    pub const Command = union(enum(u8)) {
        set_color: u32,
        set_stroke: struct { width: f32, miter_limit: f32, cap: u32, join: u32 },
        set_dash: bool,
        set_font: []const u8,
        set_font_size: struct { size: f32 },
        translate: struct { x: f32, y: f32 },
        scale: struct { x: f32, y: f32 },
        rotate: struct { x: f32, y: f32, angle: f32 },
        reset: void,
        draw_glyph: struct { a1: u16, x: f32, y: f32 },
        // returns the id
        begin_path: i32,
        move_to: struct { x: f32, y: f32 },
        line_to: struct { x: f32, y: f32 },
        cubic_to: struct { x1: f32, y1: f32, x2: f32, y2: f32, x3: f32, y3: f32 },
        quad_to: struct { x1: f32, y1: f32, x2: f32, y2: f32 },
        close_path: void,
        // returns the id
        fill_path: i32,
        draw_line: struct { x1: f32, y1: f32, x2: f32, y2: f32 },
        draw_rect: struct { x: f32, y: f32, width: f32, height: f32 },
        fill_rect: struct { x: f32, y: f32, width: f32, height: f32 },
        draw_round_rect: struct {
            x: f32,
            y: f32,
            width: f32,
            height: f32,
            a1: f32,
            a2: f32,
        },
        fill_round_rect: struct {
            x: f32,
            y: f32,
            width: f32,
            height: f32,
            a1: f32,
            a2: f32,
        },
        drawTextLayout: struct { id: u32, x: f32, y: f32 },
    };

    pub const DrawingData = struct {
        // offset is already advanced because we read in the length
        offset: usize = @sizeOf(u32),
        data: []const u8,
        ptr: c.DrawingData,

        fn init(ptr: c.DrawingData) DrawingData {
            const len = getRawDrawingDataT(ptr, 0, u32);
            return .{
                .ptr = ptr,
                .data = getRawDrawingData(ptr, 0, len),
            };
        }

        fn getSlice(self: *DrawingData, size: usize) ?[]const u8 {
            if (self.offset + size > self.data.len) {
                return null;
            }
            const s = self.data[self.offset .. self.offset + size];
            self.offset += size;
            return s;
        }

        fn getT(self: *DrawingData, comptime T: type) ?T {
            const data = self.getSlice(@sizeOf(T)) orelse
                return null;
            return std.mem.bytesToValue(T, data);
        }

        fn readOp(
            self: *DrawingData,
            comptime op: std.meta.Tag(Command),
        ) Command {
            const name = @tagName(op);
            const info = @typeInfo(Command).@"union";
            const T = comptime b: {
                for (info.fields) |field| {
                    if (std.mem.eql(u8, field.name, name)) {
                        break :b field.type;
                    }
                }
                @compileError("This should be unreachable");
            };

            var cmd: T = undefined;
            switch (@typeInfo(T)) {
                .@"struct" => {
                    inline for (@typeInfo(T).@"struct".fields) |field| {
                        @field(cmd, field.name) = self.getT(field.type).?;
                    }
                },
                .int, .float => {
                    cmd = self.getT(T).?;
                },
                else => {},
            }
            return @unionInit(Command, name, cmd);
        }

        pub fn next(self: *DrawingData) ?Command {
            const opcode = self.getT(u8) orelse
                return null;
            switch (opcode) {
                inline 0...22 => |i| {
                    const op: std.meta.Tag(Command) = @enumFromInt(i);
                    return self.readOp(op);
                },
                else => {
                    std.log.default.warn("Unhandled opcode: {d}\n", .{opcode});
                },
            }
            return null;
        }
    };

    ptr: c.RenderPtr,
    drawing_data: ?DrawingData = null,

    pub fn deinit(self: *Render) void {
        if (self.drawing_data) |d| {
            c.microtex_freeDrawingData(d.ptr);
        }
        c.microtex_deleteRender(self.ptr);
        self.* = undefined;
    }

    pub fn getDrawingData(self: *Render, x: u32, y: u32) DrawingData {
        return self.drawing_data orelse {
            const ptr = c.microtex_getDrawingData(
                self.ptr,
                @intCast(x),
                @intCast(y),
            );
            self.drawing_data = DrawingData.init(ptr);
            return self.drawing_data.?;
        };
    }
};

pub const FontContext = struct {
    const FontText = struct {
        font: FontDescription,
        text: []const u8,
    };
    const FontMap = std.AutoHashMap(usize, FontText);

    id: usize = 0,
    fontmap: FontMap,

    fn createTextLayout(
        self: *FontContext,
        text: []const u8,
        font: FontDescription,
    ) !usize {
        const id = self.id;
        self.id += 1;

        try self.fontmap.put(id, .{ .text = text, .font = font });
        return id;
    }

    fn getTextLayoutBounds(
        self: *FontContext,
        id: usize,
        bounds: TextLayoutBounds,
    ) !void {
        const value = self.fontmap.get(id).?;
        _ = value;
        // TODO: would need a way of measuring how big this is going to be
        bounds.setBounds(200, 100, 10);
    }

    fn releaseTextLayout(self: *FontContext, id: usize) void {
        if (!self.fontmap.remove(id)) {
            std.log.default.debug("Failed to remove text layout: {d}", .{id});
        }
    }

    fn isPathExists(self: *FontContext, id: usize) bool {
        _ = self;
        _ = id;
        return false;
    }

    pub fn init(allocator: std.mem.Allocator) FontContext {
        const map = FontMap.init(allocator);
        return .{ .fontmap = map };
    }

    pub fn deinit(self: *FontContext) void {
        self.fontmap.deinit();
        self.* = undefined;
    }
};

pub fn setRenderGlyphUsePath(use: bool) void {
    c.microtex_setRenderGlyphUsePath(use);
}
