const std = @import("std");
const c = @cImport({
    @cInclude("yuarel.h");
});

const len = std.mem.len;
const span = std.mem.span;

const Allocator = std.mem.Allocator;

const Yuarel = @This();

handle: c.yuarel = undefined,
_url: [:0]u8 = undefined,
allocator: Allocator,

scheme: []const u8 = undefined,
username: []const u8 = undefined,
password: []const u8 = undefined,
host: []const u8 = undefined,
port: u16 = undefined,
path: []const u8 = undefined,
query: []const u8 = undefined,
fragment: []const u8 = undefined,

pub fn parse(allocator: Allocator, url: []const u8) !Yuarel {
    var yuarel = Yuarel{
        .allocator = allocator,
    };

    yuarel._url = allocator.dupeZ(u8, url) catch @panic("OOM");

    _ = c.yuarel_parse(&yuarel.handle, yuarel._url.ptr);

    yuarel.scheme = safeSpan(yuarel.handle.scheme) orelse "";
    yuarel.username = safeSpan(yuarel.handle.username) orelse "";
    yuarel.password = safeSpan(yuarel.handle.password) orelse "";
    yuarel.host = safeSpan(yuarel.handle.host) orelse "";
    yuarel.port = @intCast(yuarel.handle.port);
    yuarel.path = safeSpan(yuarel.handle.path) orelse "";
    yuarel.query = safeSpan(yuarel.handle.query) orelse "";
    yuarel.fragment = safeSpan(yuarel.handle.fragment) orelse "";

    return yuarel;
}

pub const ParsedQuery = struct {
    allocator: ?Allocator = null,
    items: []c.yuarel_param,
    _query: [:0]u8,

    pub fn empty() ParsedQuery {
        return .{
            ._query = undefined,
            .items = &[_]c.yuarel_param{},
        };
    }

    pub fn deinit(self: ParsedQuery) void {
        if (self.allocator) |allocator| {
            allocator.free(self._query);
            allocator.free(self.items);
        }
    }
};

pub fn parseQuery(self: Yuarel) !ParsedQuery {
    if (self.query.len == 0) {
        return ParsedQuery.empty();
    }

    // get number of params
    var delimiter_count = std.mem.count(u8, self.query, "&") + 1;
    var query = try self.allocator.dupeZ(u8, self.query);

    if (std.mem.eql(u8, "&", query[query.len - 1 ..])) {
        delimiter_count -= 1;
        query[query.len - 1] = 0;
    }

    if (len(query.ptr) == 0) {
        self.allocator.free(query);
        return ParsedQuery.empty();
    }

    const params = try self.allocator.alloc(c.yuarel_param, delimiter_count);

    _ = c.yuarel_parse_query(query, '&', params.ptr, @intCast(delimiter_count));

    return ParsedQuery{
        ._query = query,
        .items = params,
        .allocator = self.allocator,
    };
}

pub fn splitPath(self: Yuarel) std.mem.SplitIterator(u8, .sequence) {
    return std.mem.splitSequence(u8, self.path, "/");
}

pub fn deinit(self: Yuarel) void {
    self.allocator.free(self._url);
}

fn safeSpan(ptr: anytype) ?[]const u8 {
    const addr = @intFromPtr(ptr);

    if (addr == 0) {
        return null;
    }

    return span(ptr);
}

const testing = std.testing;

test "parse url" {
    const url = "https://example.com:8080/path/to/resource?query=string&one=two&";
    const yuarel = try Yuarel.parse(testing.allocator, url);
    defer yuarel.deinit();

    try testing.expectEqualStrings("https", yuarel.scheme);
    try testing.expectEqualStrings("example.com", yuarel.host);
    try testing.expectEqual(8080, yuarel.port);
    try testing.expectEqualStrings("path/to/resource", yuarel.path);
    try testing.expectEqualStrings("query=string&one=two&", yuarel.query);
}

test "parse query" {
    const url = "https://example.com:8080/path/to/resource?query=string&one=two&";
    const yuarel = try Yuarel.parse(testing.allocator, url);
    defer yuarel.deinit();

    const query = try yuarel.parseQuery();
    defer query.deinit();

    try testing.expectEqualStrings("query", span(query.items[0].key));
    try testing.expectEqualStrings("string", span(query.items[0].val));
    try testing.expectEqualStrings("one", span(query.items[1].key));
    try testing.expectEqualStrings("two", span(query.items[1].val));
}

test "empty query" {
    // no query
    {
        const url = "https://example.com:8080/path/to/resource";
        const yuarel = try Yuarel.parse(testing.allocator, url);
        defer yuarel.deinit();

        const query = try yuarel.parseQuery();
        defer query.deinit();

        try testing.expectEqual(0, query.items.len);
    }

    // empty string
    {
        const url = "https://example.com:8080/path/to/resource?";
        const yuarel = try Yuarel.parse(testing.allocator, url);
        defer yuarel.deinit();

        const query = try yuarel.parseQuery();
        defer query.deinit();

        try testing.expectEqual(0, query.items.len);
    }

    // a single ampersand
    {
        const url = "https://example.com:8080/path/to/resource?&";
        const yuarel = try Yuarel.parse(testing.allocator, url);
        defer yuarel.deinit();

        const query = try yuarel.parseQuery();
        defer query.deinit();

        try testing.expectEqual(0, query.items.len);
    }
}

test "split path" {
    const url = "https://example.com:8080/path/to/resource?query=string&one=two&";
    const yuarel = try Yuarel.parse(testing.allocator, url);
    defer yuarel.deinit();

    var path_iterator = yuarel.splitPath();

    var path_list = std.ArrayList([]const u8).init(testing.allocator);
    defer path_list.deinit();

    while (path_iterator.next()) |path| {
        try path_list.append(path);
    }

    try testing.expectEqualStrings("path", path_list.items[0]);
    try testing.expectEqualStrings("to", path_list.items[1]);
    try testing.expectEqualStrings("resource", path_list.items[2]);
}
