const std = @import("std");

var g_err_msg: ?[]const u8 = null;

fn setErr(alloc: std.mem.Allocator, comptime fmt: []const u8, args: anytype) error{Runtime} {
    g_err_msg = std.fmt.allocPrint(alloc, fmt, args) catch "Error";
    return error.Runtime;
}

fn trim(s: []const u8) []const u8 {
    return std.mem.trim(u8, s, " \t\r\n");
}

fn isSectionHeader(s: []const u8) bool {
    return s.len >= 3 and s[0] == '[' and s[s.len - 1] == ']';
}

fn unquote(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') {
        return s[1 .. s.len - 1];
    }
    return s;
}

fn needsQuotes(s: []const u8) bool {
    return std.mem.indexOfAny(u8, s, " =") != null;
}

fn toLowerAlloc(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = try alloc.alloc(u8, s.len);
    for (s, 0..) |c, i| out[i] = std.ascii.toLower(c);
    return out;
}

fn makeKeyLine(alloc: std.mem.Allocator, key: []const u8, value: []const u8) ![]u8 {
    if (needsQuotes(value)) {
        return std.fmt.allocPrint(alloc, "{s} = \"{s}\"", .{ key, value });
    }
    return std.fmt.allocPrint(alloc, "{s} = {s}", .{ key, value });
}

const StringMapUsize = std.StringHashMap(usize);

fn eprint(io: std.Io, comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    std.Io.File.writeStreamingAll(std.Io.File.stderr(), io, msg) catch {};
}

fn oprint(io: std.Io, comptime fmt: []const u8, args: anytype) void {
    var buf: [2048]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;
    std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, msg) catch {};
}

const IniFile = struct {
    alloc: std.mem.Allocator,
    io: std.Io,
    path: []const u8,

    lines: std.ArrayList([]u8),
    section_lines: std.StringHashMap(usize),
    key_lines: std.StringHashMap(*StringMapUsize),
    data: std.StringHashMap(*std.StringHashMap([]u8)),

    pub fn init(alloc: std.mem.Allocator, io: std.Io, path: []const u8) !IniFile {
        var self = IniFile{
            .alloc = alloc,
            .io = io,
            .path = path,
            .lines = .empty,
            .section_lines = std.StringHashMap(usize).init(alloc),
            .key_lines = std.StringHashMap(*StringMapUsize).init(alloc),
            .data = std.StringHashMap(*std.StringHashMap([]u8)).init(alloc),
        };
        try self.load();
        return self;
    }

    fn load(self: *IniFile) !void {
        const dir = std.Io.Dir.cwd();
        const content = dir.readFileAlloc(self.io, self.path, self.alloc, std.Io.Limit.limited(1 << 26)) catch {
            return setErr(self.alloc, "Error: cannot open file {s}", .{self.path});
        };

        var it = std.mem.splitScalar(u8, content, '\n');
        while (it.next()) |raw_line| {
            var line = raw_line;
            if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
            try self.lines.append(self.alloc, try self.alloc.dupe(u8, line));
        }

        var current_section: ?[]u8 = null;
        for (self.lines.items, 0..) |line_owned, lineno| {
            const t = trim(line_owned);
            if (t.len == 0) continue;
            if (t[0] == ';') continue;

            if (isSectionHeader(t)) {
                const inner = trim(t[1 .. t.len - 1]);
                current_section = try toLowerAlloc(self.alloc, inner);
                try self.section_lines.put(current_section.?, lineno);
                continue;
            }

            if (current_section) |sec| {
                if (std.mem.indexOfScalar(u8, t, '=')) |pos| {
                    const key_part = trim(t[0..pos]);
                    const val_part = trim(t[pos + 1 ..]);
                    const key_lower = try toLowerAlloc(self.alloc, key_part);
                    const val_unq = unquote(val_part);
                    const val_owned = try self.alloc.dupe(u8, val_unq);

                    const sec_map_ptr = blk: {
                        if (self.data.get(sec)) |ptr| break :blk ptr;
                        const ptr = try self.alloc.create(std.StringHashMap([]u8));
                        ptr.* = std.StringHashMap([]u8).init(self.alloc);
                        try self.data.put(sec, ptr);
                        break :blk ptr;
                    };
                    try sec_map_ptr.put(key_lower, val_owned);

                    const keys_ptr = blk: {
                        if (self.key_lines.get(sec)) |ptr| break :blk ptr;
                        const ptr = try self.alloc.create(StringMapUsize);
                        ptr.* = StringMapUsize.init(self.alloc);
                        try self.key_lines.put(sec, ptr);
                        break :blk ptr;
                    };
                    try keys_ptr.put(key_lower, lineno);
                }
            }
        }
    }

    fn write(self: *IniFile) !void {
        const dir = std.Io.Dir.cwd();
        var file = dir.createFile(self.io, self.path, .{}) catch {
            return setErr(self.alloc, "Error: cannot write file {s}", .{self.path});
        };
        defer file.close(self.io);

        for (self.lines.items) |l| {
            std.Io.File.writeStreamingAll(file, self.io, l) catch {
                return setErr(self.alloc, "Error: cannot write file {s}", .{self.path});
            };
            std.Io.File.writeStreamingAll(file, self.io, "\n") catch {
                return setErr(self.alloc, "Error: cannot write file {s}", .{self.path});
            };
        }
    }

    pub fn get(self: *IniFile, section: []const u8, key: []const u8) ![]const u8 {
        const sec_lower = try toLowerAlloc(self.alloc, section);
        const key_lower = try toLowerAlloc(self.alloc, key);

        if (self.data.get(sec_lower)) |sec_map_ptr| {
            if (sec_map_ptr.get(key_lower)) |val| {
                return val;
            }
        }
        return setErr(self.alloc, "Error: key not found", .{});
    }

    pub fn set(self: *IniFile, section: []const u8, key: []const u8, value: []const u8) !void {
        const sec_lower = try toLowerAlloc(self.alloc, section);
        const key_lower = try toLowerAlloc(self.alloc, key);

        if (self.section_lines.get(sec_lower) == null) {
            if (self.lines.items.len > 0 and trim(self.lines.items[self.lines.items.len - 1]).len != 0) {
                try self.lines.append(self.alloc, try self.alloc.dupe(u8, ""));
            }
            try self.lines.append(self.alloc, try std.fmt.allocPrint(self.alloc, "[{s}]", .{section}));
            try self.lines.append(self.alloc, try makeKeyLine(self.alloc, key, value));
            try self.write();
            return;
        }

        const section_line = self.section_lines.get(sec_lower).?;
        if (self.key_lines.get(sec_lower)) |keys_ptr| {
            if (keys_ptr.get(key_lower)) |line_no| {
                const line = self.lines.items[line_no];
                const pos_opt = std.mem.indexOfScalar(u8, line, '=');
                const lhs = if (pos_opt) |pos| trim(line[0..pos]) else trim(line);
                self.lines.items[line_no] = try std.fmt.allocPrint(self.alloc, "{s} = {s}", .{
                    lhs,
                    if (needsQuotes(value))
                        try std.fmt.allocPrint(self.alloc, "\"{s}\"", .{value})
                    else
                        value,
                });
                try self.write();
                return;
            }
        }

        var insert_at: usize = section_line + 1;
        while (insert_at < self.lines.items.len) : (insert_at += 1) {
            const t = trim(self.lines.items[insert_at]);
            if (t.len != 0 and t[0] == '[') {
                if (insert_at > section_line + 1 and trim(self.lines.items[insert_at - 1]).len == 0) {
                    insert_at -= 1;
                }
                break;
            }
        }

        try self.lines.insert(self.alloc, insert_at, try makeKeyLine(self.alloc, key, value));
        try self.write();
    }

    pub fn del(self: *IniFile, section: []const u8, key: []const u8) !void {
        const sec_lower = try toLowerAlloc(self.alloc, section);
        const key_lower = try toLowerAlloc(self.alloc, key);

        const keys_ptr = self.key_lines.get(sec_lower) orelse
            return setErr(self.alloc, "Error: section not found", .{});

        const line_no = keys_ptr.get(key_lower) orelse
            return setErr(self.alloc, "Error: key not found", .{});

        _ = self.lines.orderedRemove(line_no);

        if (self.data.get(sec_lower)) |sec_map_ptr| {
            _ = sec_map_ptr.remove(key_lower);
        }
        _ = keys_ptr.remove(key_lower);

        // Adjust stored line numbers
        var it_sec = self.key_lines.iterator();
        while (it_sec.next()) |entry| {
            const inner = entry.value_ptr.*;
            var it_key = inner.iterator();
            while (it_key.next()) |kentry| {
                if (kentry.value_ptr.* > line_no) kentry.value_ptr.* -= 1;
            }
        }

        var it_sections = self.section_lines.iterator();
        while (it_sections.next()) |entry| {
            if (entry.value_ptr.* > line_no) entry.value_ptr.* -= 1;
        }

        try self.write();
    }
};

fn usage(io: std.Io, argv0: []const u8) void {
    eprint(io, "\nUsage:\n", .{});
    eprint(io, "  {s} -g, --get <file> <section> <key>\n", .{argv0});
    eprint(io, "  {s} -s, --set <file> <section> <key> <value>\n", .{argv0});
    eprint(io, "  {s} -d, --del <file> <section> <key>\n\n", .{argv0});
}

pub fn main(init: std.process.Init) u8 {
    const alloc = init.arena.allocator();
    const io = init.io;

    var it = std.process.Args.Iterator.init(init.minimal.args);
    var argv_list: std.ArrayList([]const u8) = .empty;
    while (it.next()) |argz| {
        argv_list.append(alloc, argz[0..argz.len]) catch return 1;
    }
    const argv = argv_list.items;

    if (argv.len < 2) {
        usage(io, argv[0]);
        return 1;
    }

    const cmd = argv[1];
    if (std.mem.eql(u8, cmd, "--get") or std.mem.eql(u8, cmd, "-g")) {
        if (argv.len != 5) {
            eprint(io, "Usage: {s} --get <file> <section> <key>\n", .{argv[0]});
            return 1;
        }
        var ini = IniFile.init(alloc, io, argv[2]) catch {
            eprint(io, "{s}\n", .{g_err_msg orelse "Error"});
            return 1;
        };
        const val = ini.get(argv[3], argv[4]) catch {
            eprint(io, "{s}\n", .{g_err_msg orelse "Error"});
            return 1;
        };
        std.Io.File.writeStreamingAll(std.Io.File.stdout(), io, val) catch return 1;
        return 0;
    } else if (std.mem.eql(u8, cmd, "--set") or std.mem.eql(u8, cmd, "-s")) {
        if (argv.len != 6) {
            eprint(io, "Usage: {s} --set <file> <section> <key> <value>\n", .{argv[0]});
            return 1;
        }
        var ini = IniFile.init(alloc, io, argv[2]) catch {
            eprint(io, "{s}\n", .{g_err_msg orelse "Error"});
            return 1;
        };
        ini.set(argv[3], argv[4], argv[5]) catch {
            eprint(io, "{s}\n", .{g_err_msg orelse "Error"});
            return 1;
        };
        oprint(io, "Updated [{s}] {s} = {s}\n", .{ argv[3], argv[4], argv[5] });
        return 0;
    } else if (std.mem.eql(u8, cmd, "--del") or std.mem.eql(u8, cmd, "-d")) {
        if (argv.len != 5) {
            eprint(io, "Usage: {s} --del <file> <section> <key>\n", .{argv[0]});
            return 1;
        }
        var ini = IniFile.init(alloc, io, argv[2]) catch {
            eprint(io, "{s}\n", .{g_err_msg orelse "Error"});
            return 1;
        };
        ini.del(argv[3], argv[4]) catch {
            eprint(io, "{s}\n", .{g_err_msg orelse "Error"});
            return 1;
        };
        oprint(io, "Deleted [{s}] {s}\n", .{ argv[3], argv[4] });
        return 0;
    } else {
        eprint(io, "Unknown command: {s}\n", .{cmd});
        return 1;
    }
}

