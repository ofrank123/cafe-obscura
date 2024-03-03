// --- Inputs ---
pub const EventType = enum(i32) {
    button_down = 0,
    button_up = 1,
};

pub const KeyCode = enum(i32) {
    key_w = 0,
    key_a = 1,
    key_s = 2,
    key_d = 3,
    mouse_l = 4,
    mouse_r = 5,
};

// --- DEBUG ---
pub extern fn logExt(log_ptr: *const u8, log_len: c_uint, level: c_uint) void;

// --- GRAPHICS ---
/// Clear the screen
pub extern fn clear() void;

// - Textures -

/// Loads a texture from the source directory, and then returns an ID
pub extern fn loadTexture(source: *const u8, len: c_uint) c_uint;

// - Rects -

/// Draw a rect with a texture on it
pub extern fn drawTextureRect(
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    texture_id: c_uint,
) void;

pub extern fn drawRect(
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
) void;

pub extern fn drawCircle(
    x: f32,
    y: f32,
    w: f32,
    h: f32,
    r: f32,
    g: f32,
    b: f32,
    a: f32,
) void;
