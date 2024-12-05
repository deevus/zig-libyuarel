pub const Yuarel = @import("Yuarel.zig");
pub const parse = Yuarel.parse;

test {
    @import("std").testing.refAllDeclsRecursive(@This());
}
