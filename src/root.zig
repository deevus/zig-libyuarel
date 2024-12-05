pub const Yuarel = @import("Yuarel.zig");

pub const parse = Yuarel.parse;
pub const ParsedQuery = Yuarel.ParsedQuery;
pub const QueryParam = Yuarel.QueryParam;

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
