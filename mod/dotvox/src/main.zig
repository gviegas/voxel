const std = @import("std");
const io = std.io;
const fs = std.fs;
const mem = std.mem;
const Allocator = mem.Allocator;
const FormatOptions = std.fmt.FormatOptions;
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;

const FourCc = packed struct {
    @"0": u8,
    @"1": u8,
    @"2": u8,
    @"3": u8,

    fn fromLiteral(str: *const [4:0]u8) @This() {
        return .{
            .@"0" = str[0],
            .@"1" = str[1],
            .@"2" = str[2],
            .@"3" = str[3],
        };
    }

    fn fromChunkKind(kind: ChunkKind) ?@This() {
        switch (kind) {
            .main => return fromLiteral("MAIN"),
            .pack => return fromLiteral("PACK"),
            .size => return fromLiteral("SIZE"),
            .xyzi => return fromLiteral("XYZI"),
            .rgba => return fromLiteral("RGBA"),
            // TODO: Extensions
            else => return null,
        }
    }

    fn asChunkKind(self: @This()) ?ChunkKind {
        const fourcc: *const [4]u8 = @ptrCast(&self);
        if (mem.eql(u8, fourcc, "MAIN")) return .main;
        if (mem.eql(u8, fourcc, "PACK")) return .pack;
        if (mem.eql(u8, fourcc, "SIZE")) return .size;
        if (mem.eql(u8, fourcc, "XYZI")) return .xyzi;
        if (mem.eql(u8, fourcc, "RGBA")) return .rgba;
        // TODO: Extensions
        return null;
    }

    pub fn format(self: @This(), comptime _: []const u8, _: FormatOptions, writer: anytype) !void {
        return std.fmt.format(
            writer,
            "'{c}{c}{c}{c}'",
            .{ self.@"0", self.@"1", self.@"2", self.@"3" },
        );
    }
};

const Header = packed struct {
    magic: FourCc,
    version: i32,

    const size_no_padding: u32 = 8;

    fn read(self: *@This(), reader: anytype) !void {
        const data: *[size_no_padding]u8 = @ptrCast(self);
        try reader.readNoEof(data);
        self.toNativeEndian();
    }

    fn write(self: *@This(), writer: anytype) !void {
        self.toLittleEndian();
        defer self.toNativeEndian();
        const data: *[size_no_padding]u8 = @ptrCast(self);
        try writer.writeAll(data);
    }

    fn toNativeEndian(self: *@This()) void {
        self.version = mem.littleToNative(i32, self.version);
    }

    fn toLittleEndian(self: *@This()) void {
        self.version = mem.nativeToLittle(i32, self.version);
    }
};

const Chunk = packed struct {
    id: FourCc,
    length_n: i32,
    length_m: i32,

    const size_no_padding: u32 = 12;

    fn read(self: *@This(), reader: anytype) !void {
        const data: *[size_no_padding]u8 = @ptrCast(self);
        try reader.readNoEof(data);
        self.toNativeEndian();
    }

    fn write(self: *@This(), writer: anytype) !void {
        self.toLittleEndian();
        defer self.toNativeEndian();
        const data: *[size_no_padding]u8 = @ptrCast(self);
        try writer.writeAll(data);
    }

    fn toNativeEndian(self: *@This()) void {
        self.length_n = mem.littleToNative(i32, self.length_n);
        self.length_m = mem.littleToNative(i32, self.length_m);
    }

    fn toLittleEndian(self: *@This()) void {
        self.length_n = mem.nativeToLittle(i32, self.length_n);
        self.length_m = mem.nativeToLittle(i32, self.length_m);
    }

    fn assertContents(
        self: @This(),
        chunk_kind: ChunkKind,
        length_n_bounds: [2]i32,
        length_m_bounds: [2]i32,
    ) void {
        assert(self.id.asChunkKind().? == chunk_kind);
        assert(self.length_n >= length_n_bounds[0] and self.length_n <= length_n_bounds[1]);
        assert(self.length_m >= length_m_bounds[0] and self.length_m <= length_m_bounds[1]);
    }
};

const ChunkKind = enum {
    main,
    pack,
    size,
    xyzi,
    rgba,

    // Extensions
    ntrn,
    ngrp,
    nshp,
    matl,
    layr,
    robj,
    rcam,
    note,
    imap,
};

const Payload = union(ChunkKind) {
    main: void,
    pack: PackPayload,
    size: SizePayload,
    xyzi: XyziPayload,
    rgba: RgbaPayload,

    // TODO
    ntrn: void,
    ngrp: void,
    nshp: void,
    matl: void,
    layr: void,
    robj: void,
    rcam: void,
    note: void,
    imap: void,
};

const PackPayload = packed struct {
    model_count: i32, // size+xyzi pairs

    const size_no_padding: u32 = 4;

    fn fromReader(chunk: Chunk, reader: anytype) !PackPayload {
        chunk.assertContents(.pack, .{ 4, 4 }, .{ 0, 0 });
        return .{ .model_count = try reader.readIntLittle(i32) };
    }

    fn write(self: *@This(), writer: anytype) !void {
        try writer.writeIntLittle(i32, self.model_count);
    }
};

const SizePayload = packed struct {
    x: i32,
    y: i32,
    z: i32,

    const size_no_padding: u32 = 12;

    fn fromReader(chunk: Chunk, reader: anytype) !SizePayload {
        chunk.assertContents(.size, .{ 12, 12 }, .{ 0, 0 });
        var self: @This() = undefined;
        const data: *[size_no_padding]u8 = @ptrCast(&self);
        try reader.readNoEof(data);
        self.toNativeEndian();
        return self;
    }

    fn write(self: *@This(), writer: anytype) !void {
        self.toLittleEndian();
        defer self.toNativeEndian();
        const data: *[size_no_padding]u8 = @ptrCast(self);
        try writer.writeAll(data);
    }

    fn toNativeEndian(self: *@This()) void {
        self.x = mem.littleToNative(i32, self.x);
        self.y = mem.littleToNative(i32, self.y);
        self.z = mem.littleToNative(i32, self.z);
    }

    fn toLittleEndian(self: *@This()) void {
        self.x = mem.nativeToLittle(i32, self.x);
        self.y = mem.nativeToLittle(i32, self.y);
        self.z = mem.nativeToLittle(i32, self.z);
    }
};

const XyziPayload = struct {
    voxel_count: i32,
    voxels: []i32,

    const max_voxels: i32 = 256 * 256 * 256;

    fn fromReader(chunk: Chunk, reader: anytype, allocator: Allocator) !XyziPayload {
        chunk.assertContents(.xyzi, .{ 4, max_voxels * 4 + 4 }, .{ 0, 0 });
        var self: @This() = undefined;
        self.voxel_count = try reader.readIntLittle(i32);
        const byte_count = switch (self.voxel_count) {
            0...max_voxels => @as(usize, @intCast(self.voxel_count)) * 4,
            else => return error.BadStream,
        };
        self.voxels = try allocator.alloc(i32, byte_count / 4);
        errdefer allocator.free(self.voxels);
        const data = @as([*]u8, @ptrCast(self.voxels.ptr))[0..byte_count];
        try reader.readNoEof(data);
        self.voxel_count = mem.nativeToLittle(i32, self.voxel_count);
        self.toNativeEndian();
        return self;
    }

    fn write(self: *@This(), writer: anytype) !void {
        if (self.voxel_count != self.voxels.len) return error.InvalidData;
        const byte_count = switch (self.voxel_count) {
            0...max_voxels => @as(usize, @intCast(self.voxel_count)) * 4,
            else => return error.InvalidData,
        };
        try writer.writeIntLittle(i32, self.voxel_count);
        self.toLittleEndian();
        defer self.toNativeEndian();
        const data = @as([*]u8, @ptrCast(self.voxels.ptr))[0..byte_count];
        try writer.writeAll(data);
    }

    fn toNativeEndian(self: *@This()) void {
        self.voxel_count = mem.littleToNative(i32, self.voxel_count);
        for (self.voxels) |*voxel| {
            voxel.* = mem.littleToNative(i32, voxel.*);
        }
    }

    fn toLittleEndian(self: *@This()) void {
        self.voxel_count = mem.nativeToLittle(i32, self.voxel_count);
        for (self.voxels) |*voxel| {
            voxel.* = mem.nativeToLittle(i32, voxel.*);
        }
    }

    fn size(self: @This()) !i32 {
        const n = 4 + self.voxels.len * 4;
        if (n > 0x7fffffff) return error.Overflow;
        return @intCast(n);
    }
};

const RgbaPayload = struct {
    palette: [256]i32, // [0] unused?

    const size_no_padding: u32 = 1024;

    fn fromReader(chunk: Chunk, reader: anytype) !RgbaPayload {
        chunk.assertContents(.rgba, .{ size_no_padding, size_no_padding }, .{ 0, 0 });
        var self: @This() = undefined;
        const data: *[size_no_padding]u8 = @ptrCast(&self.palette);
        try reader.readNoEof(data);
        self.toNativeEndian();
        return self;
    }

    fn write(self: *@This(), writer: anytype) !void {
        self.toLittleEndian();
        defer self.toNativeEndian();
        const data: *[size_no_padding]u8 = @ptrCast(&self.palette);
        try writer.writeAll(data);
    }

    fn toNativeEndian(self: *@This()) void {
        for (&self.palette) |*rgba| {
            rgba.* = mem.littleToNative(i32, rgba.*);
        }
    }

    fn toLittleEndian(self: *@This()) void {
        for (&self.palette) |*rgba| {
            rgba.* = mem.nativeToLittle(i32, rgba.*);
        }
    }
};

fn Decoder(comptime ReaderType: type) type {
    return struct {
        context: ?ChunkKind,
        reader: ReaderType,
        allocator: Allocator,

        fn init(reader: anytype, allocator: Allocator) Decoder(@TypeOf(reader)) {
            return .{
                .context = null,
                .reader = reader,
                .allocator = allocator,
            };
        }

        fn decodeHeader(self: *@This(), header: *Header) !void {
            if (self.context != null) return error.BadContext;
            try header.read(self.reader);
            self.context = .main;
        }

        // NOTE: This method does not check if the chunks are correctly ordered
        // relative to each other.
        fn decodeChunk(self: *@This(), chunk: *Chunk, payload: *Payload) !void {
            if (self.context == null) return error.BadContext;
            try chunk.read(self.reader);

            // TODO: Maybe move this to Chunk type
            const skip = (struct {
                fn impl(dec: @TypeOf(self), chnk: Chunk) !void {
                    std.log.warn("skipping chunk {}", .{chnk.id});
                    const n = @max(chnk.length_n + chnk.length_m, 0);
                    try dec.reader.skipBytes(n, .{});
                }
            }).impl;

            if (chunk.id.asChunkKind()) |kind| {
                payload.* = switch (kind) {
                    .main => .{ .main = {} },
                    .pack => .{ .pack = try PackPayload.fromReader(chunk.*, self.reader) },
                    .size => .{ .size = try SizePayload.fromReader(chunk.*, self.reader) },
                    .xyzi => .{ .xyzi = try XyziPayload.fromReader(chunk.*, self.reader, self.allocator) },
                    .rgba => .{ .rgba = try RgbaPayload.fromReader(chunk.*, self.reader) },
                    // TODO
                    .ntrn, .ngrp, .nshp, .matl, .layr, .robj, .rcam, .note, .imap => {
                        try skip(self, chunk.*);
                        return error.UnknownChunk;
                    },
                };
            } else {
                try skip(self, chunk.*);
                return error.UnknownChunk;
            }
        }
    };
}

fn Encoder(comptime WriterType: type) type {
    return struct {
        context: ?ChunkKind,
        writer: WriterType,

        fn init(writer: anytype) Encoder(@TypeOf(writer)) {
            return .{
                .context = null,
                .writer = writer,
            };
        }

        fn encodeHeader(self: *@This(), header: *Header) !void {
            if (self.context != null) return error.BadContext;
            try header.write(self.writer);
            self.context = .main;
        }

        // NOTE: This method does not check if the chunks are correctly ordered
        // relative to each other.
        fn encodeChunk(self: *@This(), chunk: *Chunk, payload: *Payload) !void {
            if (self.context == null) return error.BadContext;
            switch (payload.*) {
                .main => try chunk.write(self.writer),
                .pack => |*pack| {
                    try chunk.write(self.writer);
                    try pack.write(self.writer);
                },
                .size => |*size| {
                    try chunk.write(self.writer);
                    try size.write(self.writer);
                },
                .xyzi => |*xyzi| {
                    try chunk.write(self.writer);
                    try xyzi.write(self.writer);
                },
                .rgba => |*rgba| {
                    try chunk.write(self.writer);
                    try rgba.write(self.writer);
                },
                .ntrn, .ngrp, .nshp, .matl, .layr, .robj, .rcam, .note, .imap => {
                    // TODO
                    return error.ChunkNotSupported;
                },
            }
        }
    };
}

// TODO: Provide a way to convert this data into a format-agnostic
// voxel representation (which should be defined elsewhere)
pub const Data = struct {
    allocator: Allocator,
    models: []Model,
    palette: RgbaPayload = .{ .palette = [_]i32{0} ** 256 }, // TODO
    // TODO: Other data

    const Model = struct {
        size: SizePayload,
        xyzi: XyziPayload,
    };

    fn init(allocator: Allocator) !@This() {
        return @This(){
            .allocator = allocator,
            .models = try allocator.alloc(Model, 1),
        };
    }

    pub fn deinit(self: *@This()) void {
        if (self.models.len < 1) return;
        for (self.models) |model| {
            self.allocator.free(model.xyzi.voxels);
        }
        self.allocator.free(self.models);
        self.models = &.{};
    }

    pub fn encode(self: *const @This(), writer: anytype) !void {
        if (self.models.len == 0) return error.NoModels;

        var encoder = Encoder(@TypeOf(writer)).init(writer);

        var header = Header{
            .magic = FourCc.fromLiteral("VOX "),
            .version = 150,
        };
        try encoder.encodeHeader(&header);

        var chunk: Chunk = undefined;
        var payload: Payload = undefined;

        // 'MAIN' contains everything but the header
        chunk = .{
            .id = FourCc.fromLiteral("MAIN"),
            .length_n = 0,
            .length_m = blk: {
                const chnk_len = @as(usize, Chunk.size_no_padding);
                var m = chnk_len + PackPayload.size_no_padding;
                m += (chnk_len + SizePayload.size_no_padding) * self.models.len;
                for (self.models) |model| {
                    m += chnk_len + @as(usize, @intCast(try model.xyzi.size()));
                }
                m += chnk_len + RgbaPayload.size_no_padding;
                if (m > 0x7fffffff) return error.Overflow;
                break :blk @intCast(m);
            },
        };
        payload = .{ .main = {} };
        try encoder.encodeChunk(&chunk, &payload);

        // 'PACK' must come before 'SIZE'/'XYZI' chunks
        chunk = .{
            .id = FourCc.fromLiteral("PACK"),
            .length_n = PackPayload.size_no_padding,
            .length_m = 0,
        };
        payload = .{ .pack = .{ .model_count = @intCast(self.models.len) } };
        try encoder.encodeChunk(&chunk, &payload);

        // 'SIZE'/'XYZI' must be interleaved
        for (self.models) |model| {
            chunk = .{
                .id = FourCc.fromLiteral("SIZE"),
                .length_n = SizePayload.size_no_padding,
                .length_m = 0,
            };
            payload = .{ .size = model.size };
            try encoder.encodeChunk(&chunk, &payload);

            chunk = .{
                .id = FourCc.fromLiteral("XYZI"),
                .length_n = try model.xyzi.size(),
                .length_m = 0,
            };
            payload = .{ .xyzi = model.xyzi };
            try encoder.encodeChunk(&chunk, &payload);
        }

        // 'RGBA' must come last
        chunk = .{
            .id = FourCc.fromLiteral("RGBA"),
            .length_n = RgbaPayload.size_no_padding,
            .length_m = 0,
        };
        payload = .{ .rgba = self.palette };
        try encoder.encodeChunk(&chunk, &payload);
    }
};

pub fn decode(reader: anytype, allocator: Allocator) !Data {
    var decoder = Decoder(@TypeOf(reader)).init(reader, allocator);

    var header: Header = undefined;
    try decoder.decodeHeader(&header);
    if (!mem.eql(u8, @as([*]u8, @ptrCast(&header))[0..4], "VOX ")) return error.BadStream;
    // TODO: What about versions greater than 150?
    if (header.version != 150) return error.VersionNotSupported;

    var data = try Data.init(allocator);
    errdefer data.deinit();

    var chunk: Chunk = undefined;
    var payload: Payload = undefined;

    var remaining = blk: {
        try decoder.decodeChunk(&chunk, &payload);
        if (payload != .main) return error.BadStream;
        break :blk chunk.length_m;
    };

    const chnk_len: i32 = Chunk.size_no_padding;
    var size_i: usize = 0;
    var xyzi_i: usize = 0;

    while (remaining > 0) {
        if (decoder.decodeChunk(&chunk, &payload)) {
            switch (payload) {
                .pack => |pack| {
                    const n = @max(1, pack.model_count);
                    if (n != data.models.len)
                        data.models = try allocator.realloc(data.models, n);
                },
                .size => |size| {
                    // Must come after 'PACK' (if present)
                    // Note that init allocates one entry
                    if (size_i >= data.models.len) return error.BadStream;
                    // Must come before 'XYZI'
                    if (size_i != xyzi_i) return error.BadStream;
                    data.models[size_i].size = size;
                    size_i += 1;
                },
                .xyzi => |xyzi| {
                    // Must come after 'SIZE'
                    if (xyzi_i >= size_i) return error.BadStream;
                    data.models[xyzi_i].xyzi = xyzi;
                    xyzi_i += 1;
                },
                .rgba => |rgba| data.palette = rgba,
                .main => return error.BadStream,
                else => {}, // TODO
            }
            remaining -= chnk_len + @max(chunk.length_n, 0);
        } else |err| {
            switch (err) {
                error.UnknownChunk => {
                    // Chunk itself is valid in this case
                    remaining -= chnk_len + @max(chunk.length_n + chunk.length_m, 0);
                    continue;
                },
                else => return err,
            }
        }
    }
    // These come in pairs
    if (size_i != xyzi_i) return error.BadStream;
    return data;
}

test "basic decoding 3x3x3" {
    const allocator = std.testing.allocator;
    var stream = io.fixedBufferStream(&test_data);
    var data = try decode(stream.reader(), allocator);
    defer data.deinit();
    try expectEqual(data.models.len, 1);
    try expectEqual(data.models[0].size.x, 3);
    try expectEqual(data.models[0].size.y, 3);
    try expectEqual(data.models[0].size.z, 3);
    try expectEqual(data.models[0].xyzi.voxel_count, 3 * 3 * 3);
    try expectEqual(data.models[0].xyzi.voxels.len, 3 * 3 * 3);
    try expectEqual(mem.eql(i32, &data.palette.palette, &[_]i32{0} ** 256), false);
}

test "basic encoding 3x3x3" {
    const allocator = std.testing.allocator;

    var stream = io.fixedBufferStream(&test_data);
    var data = try decode(stream.reader(), allocator);
    defer data.deinit();

    // 8B from header + 12B from MAIN chunk + 1200B from MAIN contents
    // TODO: Update the length when adding other chunks
    var rw_buf = [_]u8{0} ** 1220;
    var rw_strm = io.fixedBufferStream(&rw_buf);
    try data.encode(rw_strm.writer());

    try expectEqual(rw_strm.getPos(), rw_buf.len);

    rw_strm.reset();
    var data2 = try decode(rw_strm.reader(), allocator);
    defer data2.deinit();

    try expectEqual(rw_strm.getPos(), rw_buf.len);

    try expectEqual(data2.models.len, 1);
    try expectEqual(data2.models[0].size.x, 3);
    try expectEqual(data2.models[0].size.y, 3);
    try expectEqual(data2.models[0].size.z, 3);
    try expectEqual(data2.models[0].xyzi.voxel_count, 3 * 3 * 3);
    try expectEqual(data2.models[0].xyzi.voxels.len, 3 * 3 * 3);
    try expectEqual(mem.eql(i32, &data2.palette.palette, &[_]i32{0} ** 256), false);

    try expectEqual(data2.models.len, data.models.len);
    try expectEqual(data2.models[0].size.x, data.models[0].size.x);
    try expectEqual(data2.models[0].size.y, data.models[0].size.y);
    try expectEqual(data2.models[0].size.z, data.models[0].size.z);
    try expectEqual(data2.models[0].xyzi.voxel_count, data.models[0].xyzi.voxel_count);
    try expectEqual(data2.models[0].xyzi.voxels.len, data.models[0].xyzi.voxels.len);
    try expectEqual(data2.palette.palette, data.palette.palette);
}

/// Filled 3x3x3 voxel grid.
// zig fmt: off
const test_data = [22680]u8{
    86,  79,  88,  32,  150, 0,   0,   0,   77,  65,  73,  78,  0,   0,   0,   0,
    132, 88,  0,   0,   83,  73,  90,  69,  12,  0,   0,   0,   0,   0,   0,   0,
    3,   0,   0,   0,   3,   0,   0,   0,   3,   0,   0,   0,   88,  89,  90,  73,
    112, 0,   0,   0,   0,   0,   0,   0,   27,  0,   0,   0,   0,   0,   0,   79,
    1,   0,   0,   79,  2,   0,   0,   79,  0,   1,   0,   79,  1,   1,   0,   79,
    2,   1,   0,   79,  0,   2,   0,   79,  1,   2,   0,   79,  2,   2,   0,   79,
    0,   0,   1,   79,  1,   0,   1,   79,  2,   0,   1,   79,  0,   1,   1,   79,
    1,   1,   1,   79,  2,   1,   1,   79,  0,   2,   1,   79,  1,   2,   1,   79,
    2,   2,   1,   79,  0,   0,   2,   79,  1,   0,   2,   79,  2,   0,   2,   79,
    0,   1,   2,   79,  1,   1,   2,   79,  2,   1,   2,   79,  0,   2,   2,   79,
    1,   2,   2,   79,  2,   2,   2,   79,  110, 84,  82,  78,  28,  0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   0,
    255, 255, 255, 255, 255, 255, 255, 255, 1,   0,   0,   0,   0,   0,   0,   0,
    110, 71,  82,  80,  16,  0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   0,
    0,   0,   0,   0,   1,   0,   0,   0,   2,   0,   0,   0,   110, 84,  82,  78,
    45,  0,   0,   0,   0,   0,   0,   0,   2,   0,   0,   0,   0,   0,   0,   0,
    3,   0,   0,   0,   255, 255, 255, 255, 0,   0,   0,   0,   1,   0,   0,   0,
    1,   0,   0,   0,   2,   0,   0,   0,   95,  116, 7,   0,   0,   0,   45,  49,
    32,  45,  49,  32,  49,  110, 83,  72,  80,  20,  0,   0,   0,   0,   0,   0,
    0,   3,   0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   76,  65,  89,  82,  37,  0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,  111,
    108, 111, 114, 11,  0,   0,   0,   50,  53,  53,  32,  50,  48,  52,  32,  49,
    53,  51,  255, 255, 255, 255, 76,  65,  89,  82,  35,  0,   0,   0,   0,   0,
    0,   0,   1,   0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,
    111, 108, 111, 114, 9,   0,   0,   0,   50,  53,  53,  32,  56,  48,  32,  56,
    48,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,   0,   0,   0,   0,   0,
    0,   2,   0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,  111,
    108, 111, 114, 11,  0,   0,   0,   50,  52,  54,  32,  49,  50,  57,  32,  49,
    52,  51,  255, 255, 255, 255, 76,  65,  89,  82,  36,  0,   0,   0,   0,   0,
    0,   0,   3,   0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,
    111, 108, 111, 114, 10,  0,   0,   0,   49,  55,  55,  32,  56,  51,  32,  50,
    48,  48,  255, 255, 255, 255, 76,  65,  89,  82,  36,  0,   0,   0,   0,   0,
    0,   0,   4,   0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,
    111, 108, 111, 114, 10,  0,   0,   0,   56,  54,  32,  49,  51,  53,  32,  50,
    49,  48,  255, 255, 255, 255, 76,  65,  89,  82,  35,  0,   0,   0,   0,   0,
    0,   0,   5,   0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,
    111, 108, 111, 114, 9,   0,   0,   0,   56,  48,  32,  56,  53,  32,  50,  48,
    48,  255, 255, 255, 255, 76,  65,  89,  82,  36,  0,   0,   0,   0,   0,   0,
    0,   6,   0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,  111,
    108, 111, 114, 10,  0,   0,   0,   54,  48,  32,  49,  54,  53,  32,  49,  54,
    51,  255, 255, 255, 255, 76,  65,  89,  82,  36,  0,   0,   0,   0,   0,   0,
    0,   7,   0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,  111,
    108, 111, 114, 10,  0,   0,   0,   49,  52,  52,  32,  49,  56,  48,  32,  55,
    53,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,   0,   0,   0,   0,   0,
    0,   8,   0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,  111,
    108, 111, 114, 11,  0,   0,   0,   49,  53,  48,  32,  49,  53,  48,  32,  49,
    53,  48,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,   0,   0,   0,   0,
    0,   0,   9,   0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,
    111, 108, 111, 114, 11,  0,   0,   0,   49,  53,  48,  32,  49,  53,  48,  32,
    49,  53,  48,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,   0,   0,   0,
    0,   0,   0,   10,  0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,
    99,  111, 108, 111, 114, 11,  0,   0,   0,   49,  53,  48,  32,  49,  53,  48,
    32,  49,  53,  48,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,   0,   0,
    0,   0,   0,   0,   11,  0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,
    95,  99,  111, 108, 111, 114, 11,  0,   0,   0,   49,  53,  48,  32,  49,  53,
    48,  32,  49,  53,  48,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,   0,
    0,   0,   0,   0,   0,   12,  0,   0,   0,   1,   0,   0,   0,   6,   0,   0,
    0,   95,  99,  111, 108, 111, 114, 11,  0,   0,   0,   49,  53,  48,  32,  49,
    53,  48,  32,  49,  53,  48,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,
    0,   0,   0,   0,   0,   0,   13,  0,   0,   0,   1,   0,   0,   0,   6,   0,
    0,   0,   95,  99,  111, 108, 111, 114, 11,  0,   0,   0,   49,  53,  48,  32,
    49,  53,  48,  32,  49,  53,  48,  255, 255, 255, 255, 76,  65,  89,  82,  37,
    0,   0,   0,   0,   0,   0,   0,   14,  0,   0,   0,   1,   0,   0,   0,   6,
    0,   0,   0,   95,  99,  111, 108, 111, 114, 11,  0,   0,   0,   49,  53,  48,
    32,  49,  53,  48,  32,  49,  53,  48,  255, 255, 255, 255, 76,  65,  89,  82,
    37,  0,   0,   0,   0,   0,   0,   0,   15,  0,   0,   0,   1,   0,   0,   0,
    6,   0,   0,   0,   95,  99,  111, 108, 111, 114, 11,  0,   0,   0,   49,  53,
    48,  32,  49,  53,  48,  32,  49,  53,  48,  255, 255, 255, 255, 76,  65,  89,
    82,  37,  0,   0,   0,   0,   0,   0,   0,   16,  0,   0,   0,   1,   0,   0,
    0,   6,   0,   0,   0,   95,  99,  111, 108, 111, 114, 11,  0,   0,   0,   49,
    53,  48,  32,  49,  53,  48,  32,  49,  53,  48,  255, 255, 255, 255, 76,  65,
    89,  82,  37,  0,   0,   0,   0,   0,   0,   0,   17,  0,   0,   0,   1,   0,
    0,   0,   6,   0,   0,   0,   95,  99,  111, 108, 111, 114, 11,  0,   0,   0,
    49,  53,  48,  32,  49,  53,  48,  32,  49,  53,  48,  255, 255, 255, 255, 76,
    65,  89,  82,  37,  0,   0,   0,   0,   0,   0,   0,   18,  0,   0,   0,   1,
    0,   0,   0,   6,   0,   0,   0,   95,  99,  111, 108, 111, 114, 11,  0,   0,
    0,   49,  53,  48,  32,  49,  53,  48,  32,  49,  53,  48,  255, 255, 255, 255,
    76,  65,  89,  82,  37,  0,   0,   0,   0,   0,   0,   0,   19,  0,   0,   0,
    1,   0,   0,   0,   6,   0,   0,   0,   95,  99,  111, 108, 111, 114, 11,  0,
    0,   0,   49,  53,  48,  32,  49,  53,  48,  32,  49,  53,  48,  255, 255, 255,
    255, 76,  65,  89,  82,  37,  0,   0,   0,   0,   0,   0,   0,   20,  0,   0,
    0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,  111, 108, 111, 114, 11,
    0,   0,   0,   49,  53,  48,  32,  49,  53,  48,  32,  49,  53,  48,  255, 255,
    255, 255, 76,  65,  89,  82,  37,  0,   0,   0,   0,   0,   0,   0,   21,  0,
    0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,  111, 108, 111, 114,
    11,  0,   0,   0,   49,  53,  48,  32,  49,  53,  48,  32,  49,  53,  48,  255,
    255, 255, 255, 76,  65,  89,  82,  37,  0,   0,   0,   0,   0,   0,   0,   22,
    0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,  111, 108, 111,
    114, 11,  0,   0,   0,   49,  53,  48,  32,  49,  53,  48,  32,  49,  53,  48,
    255, 255, 255, 255, 76,  65,  89,  82,  37,  0,   0,   0,   0,   0,   0,   0,
    23,  0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,  111, 108,
    111, 114, 11,  0,   0,   0,   49,  53,  48,  32,  49,  53,  48,  32,  49,  53,
    48,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,   0,   0,   0,   0,   0,
    0,   24,  0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,  111,
    108, 111, 114, 11,  0,   0,   0,   49,  53,  48,  32,  49,  53,  48,  32,  49,
    53,  48,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,   0,   0,   0,   0,
    0,   0,   25,  0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,  99,
    111, 108, 111, 114, 11,  0,   0,   0,   49,  53,  48,  32,  49,  53,  48,  32,
    49,  53,  48,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,   0,   0,   0,
    0,   0,   0,   26,  0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   95,
    99,  111, 108, 111, 114, 11,  0,   0,   0,   49,  53,  48,  32,  49,  53,  48,
    32,  49,  53,  48,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,   0,   0,
    0,   0,   0,   0,   27,  0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,
    95,  99,  111, 108, 111, 114, 11,  0,   0,   0,   49,  53,  48,  32,  49,  53,
    48,  32,  49,  53,  48,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,   0,
    0,   0,   0,   0,   0,   28,  0,   0,   0,   1,   0,   0,   0,   6,   0,   0,
    0,   95,  99,  111, 108, 111, 114, 11,  0,   0,   0,   49,  53,  48,  32,  49,
    53,  48,  32,  49,  53,  48,  255, 255, 255, 255, 76,  65,  89,  82,  37,  0,
    0,   0,   0,   0,   0,   0,   29,  0,   0,   0,   1,   0,   0,   0,   6,   0,
    0,   0,   95,  99,  111, 108, 111, 114, 11,  0,   0,   0,   49,  53,  48,  32,
    49,  53,  48,  32,  49,  53,  48,  255, 255, 255, 255, 76,  65,  89,  82,  37,
    0,   0,   0,   0,   0,   0,   0,   30,  0,   0,   0,   1,   0,   0,   0,   6,
    0,   0,   0,   95,  99,  111, 108, 111, 114, 11,  0,   0,   0,   49,  53,  48,
    32,  49,  53,  48,  32,  49,  53,  48,  255, 255, 255, 255, 76,  65,  89,  82,
    37,  0,   0,   0,   0,   0,   0,   0,   31,  0,   0,   0,   1,   0,   0,   0,
    6,   0,   0,   0,   95,  99,  111, 108, 111, 114, 11,  0,   0,   0,   49,  53,
    48,  32,  49,  53,  48,  32,  49,  53,  48,  255, 255, 255, 255, 82,  71,  66,
    65,  0,   4,   0,   0,   0,   0,   0,   0,   255, 255, 255, 255, 255, 255, 204,
    255, 255, 255, 153, 255, 255, 255, 102, 255, 255, 255, 51,  255, 255, 255, 0,
    255, 255, 204, 255, 255, 255, 204, 204, 255, 255, 204, 153, 255, 255, 204, 102,
    255, 255, 204, 51,  255, 255, 204, 0,   255, 255, 153, 255, 255, 255, 153, 204,
    255, 255, 153, 153, 255, 255, 153, 102, 255, 255, 153, 51,  255, 255, 153, 0,
    255, 255, 102, 255, 255, 255, 102, 204, 255, 255, 102, 153, 255, 255, 102, 102,
    255, 255, 102, 51,  255, 255, 102, 0,   255, 255, 51,  255, 255, 255, 51,  204,
    255, 255, 51,  153, 255, 255, 51,  102, 255, 255, 51,  51,  255, 255, 51,  0,
    255, 255, 0,   255, 255, 255, 0,   204, 255, 255, 0,   153, 255, 255, 0,   102,
    255, 255, 0,   51,  255, 255, 0,   0,   255, 204, 255, 255, 255, 204, 255, 204,
    255, 204, 255, 153, 255, 204, 255, 102, 255, 204, 255, 51,  255, 204, 255, 0,
    255, 204, 204, 255, 255, 204, 204, 204, 255, 204, 204, 153, 255, 204, 204, 102,
    255, 204, 204, 51,  255, 204, 204, 0,   255, 204, 153, 255, 255, 204, 153, 204,
    255, 204, 153, 153, 255, 204, 153, 102, 255, 204, 153, 51,  255, 204, 153, 0,
    255, 204, 102, 255, 255, 204, 102, 204, 255, 204, 102, 153, 255, 204, 102, 102,
    255, 204, 102, 51,  255, 204, 102, 0,   255, 204, 51,  255, 255, 204, 51,  204,
    255, 204, 51,  153, 255, 204, 51,  102, 255, 204, 51,  51,  255, 204, 51,  0,
    255, 204, 0,   255, 255, 204, 0,   204, 255, 204, 0,   153, 255, 204, 0,   102,
    255, 204, 0,   51,  255, 204, 0,   0,   255, 153, 255, 255, 255, 153, 255, 204,
    255, 153, 255, 153, 255, 153, 255, 102, 255, 153, 255, 51,  255, 153, 255, 0,
    255, 153, 204, 255, 255, 153, 204, 204, 255, 153, 204, 153, 255, 153, 204, 102,
    255, 153, 204, 51,  255, 153, 204, 0,   255, 153, 153, 255, 255, 153, 153, 204,
    255, 153, 153, 153, 255, 153, 153, 102, 255, 153, 153, 51,  255, 153, 153, 0,
    255, 153, 102, 255, 255, 153, 102, 204, 255, 153, 102, 153, 255, 153, 102, 102,
    255, 153, 102, 51,  255, 153, 102, 0,   255, 153, 51,  255, 255, 153, 51,  204,
    255, 153, 51,  153, 255, 153, 51,  102, 255, 153, 51,  51,  255, 153, 51,  0,
    255, 153, 0,   255, 255, 153, 0,   204, 255, 153, 0,   153, 255, 153, 0,   102,
    255, 153, 0,   51,  255, 153, 0,   0,   255, 102, 255, 255, 255, 102, 255, 204,
    255, 102, 255, 153, 255, 102, 255, 102, 255, 102, 255, 51,  255, 102, 255, 0,
    255, 102, 204, 255, 255, 102, 204, 204, 255, 102, 204, 153, 255, 102, 204, 102,
    255, 102, 204, 51,  255, 102, 204, 0,   255, 102, 153, 255, 255, 102, 153, 204,
    255, 102, 153, 153, 255, 102, 153, 102, 255, 102, 153, 51,  255, 102, 153, 0,
    255, 102, 102, 255, 255, 102, 102, 204, 255, 102, 102, 153, 255, 102, 102, 102,
    255, 102, 102, 51,  255, 102, 102, 0,   255, 102, 51,  255, 255, 102, 51,  204,
    255, 102, 51,  153, 255, 102, 51,  102, 255, 102, 51,  51,  255, 102, 51,  0,
    255, 102, 0,   255, 255, 102, 0,   204, 255, 102, 0,   153, 255, 102, 0,   102,
    255, 102, 0,   51,  255, 102, 0,   0,   255, 51,  255, 255, 255, 51,  255, 204,
    255, 51,  255, 153, 255, 51,  255, 102, 255, 51,  255, 51,  255, 51,  255, 0,
    255, 51,  204, 255, 255, 51,  204, 204, 255, 51,  204, 153, 255, 51,  204, 102,
    255, 51,  204, 51,  255, 51,  204, 0,   255, 51,  153, 255, 255, 51,  153, 204,
    255, 51,  153, 153, 255, 51,  153, 102, 255, 51,  153, 51,  255, 51,  153, 0,
    255, 51,  102, 255, 255, 51,  102, 204, 255, 51,  102, 153, 255, 51,  102, 102,
    255, 51,  102, 51,  255, 51,  102, 0,   255, 51,  51,  255, 255, 51,  51,  204,
    255, 51,  51,  153, 255, 51,  51,  102, 255, 51,  51,  51,  255, 51,  51,  0,
    255, 51,  0,   255, 255, 51,  0,   204, 255, 51,  0,   153, 255, 51,  0,   102,
    255, 51,  0,   51,  255, 51,  0,   0,   255, 0,   255, 255, 255, 0,   255, 204,
    255, 0,   255, 153, 255, 0,   255, 102, 255, 0,   255, 51,  255, 0,   255, 0,
    255, 0,   204, 255, 255, 0,   204, 204, 255, 0,   204, 153, 255, 0,   204, 102,
    255, 0,   204, 51,  255, 0,   204, 0,   255, 0,   153, 255, 255, 0,   153, 204,
    255, 0,   153, 153, 255, 0,   153, 102, 255, 0,   153, 51,  255, 0,   153, 0,
    255, 0,   102, 255, 255, 0,   102, 204, 255, 0,   102, 153, 255, 0,   102, 102,
    255, 0,   102, 51,  255, 0,   102, 0,   255, 0,   51,  255, 255, 0,   51,  204,
    255, 0,   51,  153, 255, 0,   51,  102, 255, 0,   51,  51,  255, 0,   51,  0,
    255, 0,   0,   255, 255, 0,   0,   204, 255, 0,   0,   153, 255, 0,   0,   102,
    255, 0,   0,   51,  255, 238, 0,   0,   255, 221, 0,   0,   255, 187, 0,   0,
    255, 170, 0,   0,   255, 136, 0,   0,   255, 119, 0,   0,   255, 85,  0,   0,
    255, 68,  0,   0,   255, 34,  0,   0,   255, 17,  0,   0,   255, 0,   238, 0,
    255, 0,   221, 0,   255, 0,   187, 0,   255, 0,   170, 0,   255, 0,   136, 0,
    255, 0,   119, 0,   255, 0,   85,  0,   255, 0,   68,  0,   255, 0,   34,  0,
    255, 0,   17,  0,   255, 0,   0,   238, 255, 0,   0,   221, 255, 0,   0,   187,
    255, 0,   0,   170, 255, 0,   0,   136, 255, 0,   0,   119, 255, 0,   0,   85,
    255, 0,   0,   68,  255, 0,   0,   34,  255, 0,   0,   17,  255, 238, 238, 238,
    255, 221, 221, 221, 255, 187, 187, 187, 255, 170, 170, 170, 255, 136, 136, 136,
    255, 119, 119, 119, 255, 85,  85,  85,  255, 68,  68,  68,  255, 34,  34,  34,
    255, 17,  17,  17,  255, 0,   0,   0,   0,   77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   1,   0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   2,   0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   3,   0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   4,   0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   5,   0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   6,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   7,   0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   8,   0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   9,   0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   10,  0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   11,  0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   12,  0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   13,  0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   14,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   15,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   16,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   17,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   18,  0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   19,  0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   20,  0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   21,  0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   22,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   23,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   24,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   25,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   26,  0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   27,  0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   28,  0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   29,  0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   30,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   31,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   32,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   33,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   34,  0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   35,  0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   36,  0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   37,  0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   38,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   39,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   40,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   41,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   42,  0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   43,  0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   44,  0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   45,  0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   46,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   47,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   48,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   49,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   50,  0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   51,  0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   52,  0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   53,  0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   54,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   55,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   56,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   57,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   58,  0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   59,  0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   60,  0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   61,  0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   62,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   63,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   64,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   65,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   66,  0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   67,  0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   68,  0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   69,  0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   70,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   71,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   72,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   73,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   74,  0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   75,  0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   76,  0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   77,  0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   78,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   79,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   80,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   81,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   82,  0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   83,  0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   84,  0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   85,  0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   86,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   87,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   88,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   89,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   90,  0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   91,  0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   92,  0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   93,  0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   94,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   95,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   96,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   97,  0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   98,  0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   99,  0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   100, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   101, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   102,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   103, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   104, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   105, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   106, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   107, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   108, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   109, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   110,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   111, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   112, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   113, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   114, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   115, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   116, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   117, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   118,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   119, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   120, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   121, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   122, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   123, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   124, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   125, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   126,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   127, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   128, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   129, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   130, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   131, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   132, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   133, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   134,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   135, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   136, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   137, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   138, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   139, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   140, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   141, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   142,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   143, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   144, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   145, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   146, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   147, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   148, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   149, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   150,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   151, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   152, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   153, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   154, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   155, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   156, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   157, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   158,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   159, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   160, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   161, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   162, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   163, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   164, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   165, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   166,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   167, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   168, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   169, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   170, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   171, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   172, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   173, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   174,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   175, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   176, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   177, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   178, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   179, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   180, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   181, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   182,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   183, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   184, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   185, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   186, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   187, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   188, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   189, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   190,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   191, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   192, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   193, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   194, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   195, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   196, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   197, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   198,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   199, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   200, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   201, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   202, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   203, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   204, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   205, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   206,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   207, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   208, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   209, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   210, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   211, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   212, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   213, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   214,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   215, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   216, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   217, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   218, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   219, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   220, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   221, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   222,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   223, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   224, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   225, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   226, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   227, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   228, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   229, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   230,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   231, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   232, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   233, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   234, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   235, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   236, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   237, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   238,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   239, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   240, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   241, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   242, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   243, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   244, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   245, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   246,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   247, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   248, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,
    0,   0,   0,   0,   0,   249, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,
    0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,
    0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,
    0,   0,   0,   0,   0,   0,   0,   250, 0,   0,   0,   3,   0,   0,   0,   6,
    0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,
    4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,
    0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,  65,  84,
    76,  54,  0,   0,   0,   0,   0,   0,   0,   251, 0,   0,   0,   3,   0,   0,
    0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,   0,   48,
    46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,   48,  46,
    51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,  53,  77,
    65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   252, 0,   0,   0,   3,
    0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,   0,   0,
    0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,   0,   0,
    48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,  46,  48,
    53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   253, 0,   0,
    0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103, 104, 3,
    0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114, 3,   0,
    0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,   0,   48,
    46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,   0,   254,
    0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111, 117, 103,
    104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105, 111, 114,
    3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,   0,   0,
    0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,   0,   0,
    0,   255, 0,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,  114, 111,
    117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,   95,  105,
    111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,  100, 4,
    0,   0,   0,   48,  46,  48,  53,  77,  65,  84,  76,  54,  0,   0,   0,   0,
    0,   0,   0,   0,   1,   0,   0,   3,   0,   0,   0,   6,   0,   0,   0,   95,
    114, 111, 117, 103, 104, 3,   0,   0,   0,   48,  46,  49,  4,   0,   0,   0,
    95,  105, 111, 114, 3,   0,   0,   0,   48,  46,  51,  2,   0,   0,   0,   95,
    100, 4,   0,   0,   0,   48,  46,  48,  53,  114, 79,  66,  74,  92,  0,   0,
    0,   0,   0,   0,   0,   5,   0,   0,   0,   5,   0,   0,   0,   95,  116, 121,
    112, 101, 7,   0,   0,   0,   95,  98,  111, 117, 110, 99,  101, 8,   0,   0,
    0,   95,  100, 105, 102, 102, 117, 115, 101, 1,   0,   0,   0,   50,  9,   0,
    0,   0,   95,  115, 112, 101, 99,  117, 108, 97,  114, 1,   0,   0,   0,   53,
    8,   0,   0,   0,   95,  115, 99,  97,  116, 116, 101, 114, 1,   0,   0,   0,
    53,  7,   0,   0,   0,   95,  101, 110, 101, 114, 103, 121, 1,   0,   0,   0,
    51,  114, 79,  66,  74,  35,  0,   0,   0,   0,   0,   0,   0,   2,   0,   0,
    0,   5,   0,   0,   0,   95,  116, 121, 112, 101, 4,   0,   0,   0,   95,  101,
    110, 118, 5,   0,   0,   0,   95,  109, 111, 100, 101, 1,   0,   0,   0,   48,
    114, 79,  66,  74,  105, 0,   0,   0,   0,   0,   0,   0,   6,   0,   0,   0,
    5,   0,   0,   0,   95,  116, 121, 112, 101, 4,   0,   0,   0,   95,  105, 110,
    102, 2,   0,   0,   0,   95,  105, 3,   0,   0,   0,   48,  46,  55,  2,   0,
    0,   0,   95,  107, 11,  0,   0,   0,   50,  53,  53,  32,  50,  53,  53,  32,
    50,  53,  53,  6,   0,   0,   0,   95,  97,  110, 103, 108, 101, 5,   0,   0,
    0,   53,  48,  32,  53,  48,  5,   0,   0,   0,   95,  97,  114, 101, 97,  4,
    0,   0,   0,   48,  46,  48,  55,  5,   0,   0,   0,   95,  100, 105, 115, 107,
    1,   0,   0,   0,   48,  114, 79,  66,  74,  55,  0,   0,   0,   0,   0,   0,
    0,   3,   0,   0,   0,   5,   0,   0,   0,   95,  116, 121, 112, 101, 4,   0,
    0,   0,   95,  117, 110, 105, 2,   0,   0,   0,   95,  105, 3,   0,   0,   0,
    48,  46,  55,  2,   0,   0,   0,   95,  107, 11,  0,   0,   0,   50,  53,  53,
    32,  50,  53,  53,  32,  50,  53,  53,  114, 79,  66,  74,  78,  0,   0,   0,
    0,   0,   0,   0,   4,   0,   0,   0,   5,   0,   0,   0,   95,  116, 121, 112,
    101, 4,   0,   0,   0,   95,  105, 98,  108, 5,   0,   0,   0,   95,  112, 97,
    116, 104, 20,  0,   0,   0,   72,  68,  82,  95,  48,  52,  49,  95,  80,  97,
    116, 104, 95,  69,  110, 118, 46,  104, 100, 114, 2,   0,   0,   0,   95,  105,
    1,   0,   0,   0,   49,  4,   0,   0,   0,   95,  114, 111, 116, 1,   0,   0,
    0,   48,  114, 79,  66,  74,  160, 0,   0,   0,   0,   0,   0,   0,   8,   0,
    0,   0,   5,   0,   0,   0,   95,  116, 121, 112, 101, 4,   0,   0,   0,   95,
    97,  116, 109, 6,   0,   0,   0,   95,  114, 97,  121, 95,  100, 3,   0,   0,
    0,   48,  46,  52,  6,   0,   0,   0,   95,  114, 97,  121, 95,  107, 10,  0,
    0,   0,   52,  53,  32,  49,  48,  52,  32,  50,  53,  53,  6,   0,   0,   0,
    95,  109, 105, 101, 95,  100, 3,   0,   0,   0,   48,  46,  52,  6,   0,   0,
    0,   95,  109, 105, 101, 95,  107, 11,  0,   0,   0,   50,  53,  53,  32,  50,
    53,  53,  32,  50,  53,  53,  6,   0,   0,   0,   95,  109, 105, 101, 95,  103,
    4,   0,   0,   0,   48,  46,  56,  53,  5,   0,   0,   0,   95,  111, 51,  95,
    100, 1,   0,   0,   0,   48,  5,   0,   0,   0,   95,  111, 51,  95,  107, 11,
    0,   0,   0,   49,  48,  53,  32,  50,  53,  53,  32,  49,  49,  48,  114, 79,
    66,  74,  68,  0,   0,   0,   0,   0,   0,   0,   4,   0,   0,   0,   5,   0,
    0,   0,   95,  116, 121, 112, 101, 8,   0,   0,   0,   95,  102, 111, 103, 95,
    117, 110, 105, 2,   0,   0,   0,   95,  100, 1,   0,   0,   0,   48,  2,   0,
    0,   0,   95,  107, 11,  0,   0,   0,   50,  53,  53,  32,  50,  53,  53,  32,
    50,  53,  53,  2,   0,   0,   0,   95,  103, 1,   0,   0,   0,   48,  114, 79,
    66,  74,  105, 0,   0,   0,   0,   0,   0,   0,   6,   0,   0,   0,   5,   0,
    0,   0,   95,  116, 121, 112, 101, 5,   0,   0,   0,   95,  108, 101, 110, 115,
    5,   0,   0,   0,   95,  112, 114, 111, 106, 1,   0,   0,   0,   48,  4,   0,
    0,   0,   95,  102, 111, 118, 2,   0,   0,   0,   52,  53,  9,   0,   0,   0,
    95,  97,  112, 101, 114, 116, 117, 114, 101, 4,   0,   0,   0,   48,  46,  50,
    53,  8,   0,   0,   0,   95,  98,  108, 97,  100, 101, 95,  110, 1,   0,   0,
    0,   48,  8,   0,   0,   0,   95,  98,  108, 97,  100, 101, 95,  114, 1,   0,
    0,   0,   48,  114, 79,  66,  74,  78,  0,   0,   0,   0,   0,   0,   0,   5,
    0,   0,   0,   5,   0,   0,   0,   95,  116, 121, 112, 101, 5,   0,   0,   0,
    95,  102, 105, 108, 109, 5,   0,   0,   0,   95,  101, 120, 112, 111, 1,   0,
    0,   0,   49,  4,   0,   0,   0,   95,  118, 105, 103, 1,   0,   0,   0,   48,
    5,   0,   0,   0,   95,  97,  99,  101, 115, 1,   0,   0,   0,   49,  4,   0,
    0,   0,   95,  103, 97,  109, 3,   0,   0,   0,   50,  46,  50,  114, 79,  66,
    74,  88,  0,   0,   0,   0,   0,   0,   0,   5,   0,   0,   0,   5,   0,   0,
    0,   95,  116, 121, 112, 101, 6,   0,   0,   0,   95,  98,  108, 111, 111, 109,
    4,   0,   0,   0,   95,  109, 105, 120, 3,   0,   0,   0,   48,  46,  53,  6,
    0,   0,   0,   95,  115, 99,  97,  108, 101, 1,   0,   0,   0,   48,  7,   0,
    0,   0,   95,  97,  115, 112, 101, 99,  116, 1,   0,   0,   0,   48,  10,  0,
    0,   0,   95,  116, 104, 114, 101, 115, 104, 111, 108, 100, 1,   0,   0,   0,
    49,  114, 79,  66,  74,  61,  0,   0,   0,   0,   0,   0,   0,   3,   0,   0,
    0,   5,   0,   0,   0,   95,  116, 121, 112, 101, 7,   0,   0,   0,   95,  103,
    114, 111, 117, 110, 100, 6,   0,   0,   0,   95,  99,  111, 108, 111, 114, 8,
    0,   0,   0,   56,  48,  32,  56,  48,  32,  56,  48,  4,   0,   0,   0,   95,
    104, 111, 114, 3,   0,   0,   0,   48,  46,  49,  114, 79,  66,  74,  39,  0,
    0,   0,   0,   0,   0,   0,   2,   0,   0,   0,   5,   0,   0,   0,   95,  116,
    121, 112, 101, 3,   0,   0,   0,   95,  98,  103, 6,   0,   0,   0,   95,  99,
    111, 108, 111, 114, 5,   0,   0,   0,   48,  32,  48,  32,  48,  114, 79,  66,
    74,  58,  0,   0,   0,   0,   0,   0,   0,   3,   0,   0,   0,   5,   0,   0,
    0,   95,  116, 121, 112, 101, 5,   0,   0,   0,   95,  101, 100, 103, 101, 6,
    0,   0,   0,   95,  99,  111, 108, 111, 114, 5,   0,   0,   0,   48,  32,  48,
    32,  48,  6,   0,   0,   0,   95,  119, 105, 100, 116, 104, 3,   0,   0,   0,
    48,  46,  50,  114, 79,  66,  74,  93,  0,   0,   0,   0,   0,   0,   0,   5,
    0,   0,   0,   5,   0,   0,   0,   95,  116, 121, 112, 101, 5,   0,   0,   0,
    95,  103, 114, 105, 100, 6,   0,   0,   0,   95,  99,  111, 108, 111, 114, 5,
    0,   0,   0,   48,  32,  48,  32,  48,  8,   0,   0,   0,   95,  115, 112, 97,
    99,  105, 110, 103, 1,   0,   0,   0,   49,  6,   0,   0,   0,   95,  119, 105,
    100, 116, 104, 4,   0,   0,   0,   48,  46,  48,  50,  8,   0,   0,   0,   95,
    100, 105, 115, 112, 108, 97,  121, 1,   0,   0,   0,   48,  114, 79,  66,  74,
    130, 0,   0,   0,   0,   0,   0,   0,   8,   0,   0,   0,   5,   0,   0,   0,
    95,  116, 121, 112, 101, 8,   0,   0,   0,   95,  115, 101, 116, 116, 105, 110,
    103, 7,   0,   0,   0,   95,  103, 114, 111, 117, 110, 100, 1,   0,   0,   0,
    49,  5,   0,   0,   0,   95,  103, 114, 105, 100, 1,   0,   0,   0,   48,  5,
    0,   0,   0,   95,  101, 100, 103, 101, 1,   0,   0,   0,   48,  5,   0,   0,
    0,   95,  98,  103, 95,  99,  1,   0,   0,   0,   48,  5,   0,   0,   0,   95,
    98,  103, 95,  97,  1,   0,   0,   0,   48,  6,   0,   0,   0,   95,  115, 99,
    97,  108, 101, 5,   0,   0,   0,   49,  32,  49,  32,  49,  5,   0,   0,   0,
    95,  99,  101, 108, 108, 1,   0,   0,   0,   49,  114, 67,  65,  77,  117, 0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   6,   0,   0,   0,   5,   0,
    0,   0,   95,  109, 111, 100, 101, 4,   0,   0,   0,   112, 101, 114, 115, 6,
    0,   0,   0,   95,  102, 111, 99,  117, 115, 5,   0,   0,   0,   48,  32,  48,
    32,  48,  6,   0,   0,   0,   95,  97,  110, 103, 108, 101, 5,   0,   0,   0,
    48,  32,  48,  32,  48,  7,   0,   0,   0,   95,  114, 97,  100, 105, 117, 115,
    1,   0,   0,   0,   48,  8,   0,   0,   0,   95,  102, 114, 117, 115, 116, 117,
    109, 8,   0,   0,   0,   48,  46,  52,  49,  52,  50,  49,  52,  4,   0,   0,
    0,   95,  102, 111, 118, 2,   0,   0,   0,   52,  53,  114, 67,  65,  77,  117,
    0,   0,   0,   0,   0,   0,   0,   1,   0,   0,   0,   6,   0,   0,   0,   5,
    0,   0,   0,   95,  109, 111, 100, 101, 4,   0,   0,   0,   112, 101, 114, 115,
    6,   0,   0,   0,   95,  102, 111, 99,  117, 115, 5,   0,   0,   0,   48,  32,
    48,  32,  48,  6,   0,   0,   0,   95,  97,  110, 103, 108, 101, 5,   0,   0,
    0,   48,  32,  48,  32,  48,  7,   0,   0,   0,   95,  114, 97,  100, 105, 117,
    115, 1,   0,   0,   0,   48,  8,   0,   0,   0,   95,  102, 114, 117, 115, 116,
    117, 109, 8,   0,   0,   0,   48,  46,  52,  49,  52,  50,  49,  52,  4,   0,
    0,   0,   95,  102, 111, 118, 2,   0,   0,   0,   52,  53,  114, 67,  65,  77,
    117, 0,   0,   0,   0,   0,   0,   0,   2,   0,   0,   0,   6,   0,   0,   0,
    5,   0,   0,   0,   95,  109, 111, 100, 101, 4,   0,   0,   0,   112, 101, 114,
    115, 6,   0,   0,   0,   95,  102, 111, 99,  117, 115, 5,   0,   0,   0,   48,
    32,  48,  32,  48,  6,   0,   0,   0,   95,  97,  110, 103, 108, 101, 5,   0,
    0,   0,   48,  32,  48,  32,  48,  7,   0,   0,   0,   95,  114, 97,  100, 105,
    117, 115, 1,   0,   0,   0,   48,  8,   0,   0,   0,   95,  102, 114, 117, 115,
    116, 117, 109, 8,   0,   0,   0,   48,  46,  52,  49,  52,  50,  49,  52,  4,
    0,   0,   0,   95,  102, 111, 118, 2,   0,   0,   0,   52,  53,  114, 67,  65,
    77,  117, 0,   0,   0,   0,   0,   0,   0,   3,   0,   0,   0,   6,   0,   0,
    0,   5,   0,   0,   0,   95,  109, 111, 100, 101, 4,   0,   0,   0,   112, 101,
    114, 115, 6,   0,   0,   0,   95,  102, 111, 99,  117, 115, 5,   0,   0,   0,
    48,  32,  48,  32,  48,  6,   0,   0,   0,   95,  97,  110, 103, 108, 101, 5,
    0,   0,   0,   48,  32,  48,  32,  48,  7,   0,   0,   0,   95,  114, 97,  100,
    105, 117, 115, 1,   0,   0,   0,   48,  8,   0,   0,   0,   95,  102, 114, 117,
    115, 116, 117, 109, 8,   0,   0,   0,   48,  46,  52,  49,  52,  50,  49,  52,
    4,   0,   0,   0,   95,  102, 111, 118, 2,   0,   0,   0,   52,  53,  114, 67,
    65,  77,  117, 0,   0,   0,   0,   0,   0,   0,   4,   0,   0,   0,   6,   0,
    0,   0,   5,   0,   0,   0,   95,  109, 111, 100, 101, 4,   0,   0,   0,   112,
    101, 114, 115, 6,   0,   0,   0,   95,  102, 111, 99,  117, 115, 5,   0,   0,
    0,   48,  32,  48,  32,  48,  6,   0,   0,   0,   95,  97,  110, 103, 108, 101,
    5,   0,   0,   0,   48,  32,  48,  32,  48,  7,   0,   0,   0,   95,  114, 97,
    100, 105, 117, 115, 1,   0,   0,   0,   48,  8,   0,   0,   0,   95,  102, 114,
    117, 115, 116, 117, 109, 8,   0,   0,   0,   48,  46,  52,  49,  52,  50,  49,
    52,  4,   0,   0,   0,   95,  102, 111, 118, 2,   0,   0,   0,   52,  53,  114,
    67,  65,  77,  117, 0,   0,   0,   0,   0,   0,   0,   5,   0,   0,   0,   6,
    0,   0,   0,   5,   0,   0,   0,   95,  109, 111, 100, 101, 4,   0,   0,   0,
    112, 101, 114, 115, 6,   0,   0,   0,   95,  102, 111, 99,  117, 115, 5,   0,
    0,   0,   48,  32,  48,  32,  48,  6,   0,   0,   0,   95,  97,  110, 103, 108,
    101, 5,   0,   0,   0,   48,  32,  48,  32,  48,  7,   0,   0,   0,   95,  114,
    97,  100, 105, 117, 115, 1,   0,   0,   0,   48,  8,   0,   0,   0,   95,  102,
    114, 117, 115, 116, 117, 109, 8,   0,   0,   0,   48,  46,  52,  49,  52,  50,
    49,  52,  4,   0,   0,   0,   95,  102, 111, 118, 2,   0,   0,   0,   52,  53,
    114, 67,  65,  77,  117, 0,   0,   0,   0,   0,   0,   0,   6,   0,   0,   0,
    6,   0,   0,   0,   5,   0,   0,   0,   95,  109, 111, 100, 101, 4,   0,   0,
    0,   112, 101, 114, 115, 6,   0,   0,   0,   95,  102, 111, 99,  117, 115, 5,
    0,   0,   0,   48,  32,  48,  32,  48,  6,   0,   0,   0,   95,  97,  110, 103,
    108, 101, 5,   0,   0,   0,   48,  32,  48,  32,  48,  7,   0,   0,   0,   95,
    114, 97,  100, 105, 117, 115, 1,   0,   0,   0,   48,  8,   0,   0,   0,   95,
    102, 114, 117, 115, 116, 117, 109, 8,   0,   0,   0,   48,  46,  52,  49,  52,
    50,  49,  52,  4,   0,   0,   0,   95,  102, 111, 118, 2,   0,   0,   0,   52,
    53,  114, 67,  65,  77,  117, 0,   0,   0,   0,   0,   0,   0,   7,   0,   0,
    0,   6,   0,   0,   0,   5,   0,   0,   0,   95,  109, 111, 100, 101, 4,   0,
    0,   0,   112, 101, 114, 115, 6,   0,   0,   0,   95,  102, 111, 99,  117, 115,
    5,   0,   0,   0,   48,  32,  48,  32,  48,  6,   0,   0,   0,   95,  97,  110,
    103, 108, 101, 5,   0,   0,   0,   48,  32,  48,  32,  48,  7,   0,   0,   0,
    95,  114, 97,  100, 105, 117, 115, 1,   0,   0,   0,   48,  8,   0,   0,   0,
    95,  102, 114, 117, 115, 116, 117, 109, 8,   0,   0,   0,   48,  46,  52,  49,
    52,  50,  49,  52,  4,   0,   0,   0,   95,  102, 111, 118, 2,   0,   0,   0,
    52,  53,  114, 67,  65,  77,  117, 0,   0,   0,   0,   0,   0,   0,   8,   0,
    0,   0,   6,   0,   0,   0,   5,   0,   0,   0,   95,  109, 111, 100, 101, 4,
    0,   0,   0,   112, 101, 114, 115, 6,   0,   0,   0,   95,  102, 111, 99,  117,
    115, 5,   0,   0,   0,   48,  32,  48,  32,  48,  6,   0,   0,   0,   95,  97,
    110, 103, 108, 101, 5,   0,   0,   0,   48,  32,  48,  32,  48,  7,   0,   0,
    0,   95,  114, 97,  100, 105, 117, 115, 1,   0,   0,   0,   48,  8,   0,   0,
    0,   95,  102, 114, 117, 115, 116, 117, 109, 8,   0,   0,   0,   48,  46,  52,
    49,  52,  50,  49,  52,  4,   0,   0,   0,   95,  102, 111, 118, 2,   0,   0,
    0,   52,  53,  114, 67,  65,  77,  117, 0,   0,   0,   0,   0,   0,   0,   9,
    0,   0,   0,   6,   0,   0,   0,   5,   0,   0,   0,   95,  109, 111, 100, 101,
    4,   0,   0,   0,   112, 101, 114, 115, 6,   0,   0,   0,   95,  102, 111, 99,
    117, 115, 5,   0,   0,   0,   48,  32,  48,  32,  48,  6,   0,   0,   0,   95,
    97,  110, 103, 108, 101, 5,   0,   0,   0,   48,  32,  48,  32,  48,  7,   0,
    0,   0,   95,  114, 97,  100, 105, 117, 115, 1,   0,   0,   0,   48,  8,   0,
    0,   0,   95,  102, 114, 117, 115, 116, 117, 109, 8,   0,   0,   0,   48,  46,
    52,  49,  52,  50,  49,  52,  4,   0,   0,   0,   95,  102, 111, 118, 2,   0,
    0,   0,   52,  53,  78,  79,  84,  69,  136, 0,   0,   0,   0,   0,   0,   0,
    32,  0,   0,   0,   4,   0,   0,   0,   78,  79,  84,  69,  0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,
    0,   0,   0,   0,   0,   0,   0,   0,
};
// zig fmt: on
