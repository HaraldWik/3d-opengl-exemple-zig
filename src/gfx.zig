const std = @import("std");
const log = @import("std").log;
const sdl = @import("sdl");
pub const gl = @import("gl");
const sdl_img = @cImport(@cInclude("SDL3_image/SDL_image.h")); // TODO: remove C import, for more information read 'build.zig'

pub const Context = struct {
    const Self = @This();

    var procs: gl.ProcTable = undefined;

    window: ?*sdl.SDL_Window,

    pub fn init(window: ?*sdl.SDL_Window) !Self {
        if (!procs.init(sdl.SDL_GL_GetProcAddress)) return error.InitFailed;
        gl.makeProcTableCurrent(&procs);

        if (!sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, 4) or
            !sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MINOR_VERSION, 6) or
            !sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_CORE) or
            !sdl.SDL_GL_SetAttribute(sdl.SDL_GL_DEPTH_SIZE, 100) or
            !sdl.SDL_GL_SetAttribute(sdl.SDL_GL_FRAMEBUFFER_SRGB_CAPABLE, 1))
            return error.SdlSetOpenGLAttribute;

        _ = sdl.SDL_GL_CreateContext(window);

        return .{ .window = window };
    }

    pub fn deinit(_: Self) void {
        const gl_context = sdl.SDL_GL_GetCurrentContext();
        _ = sdl.SDL_GL_DestroyContext(gl_context);

        gl.makeProcTableCurrent(null);
    }

    pub fn clear(self: Self) !void {
        var width: c_int = undefined;
        var height: c_int = undefined;
        if (!sdl.SDL_GetWindowSize(self.window, &width, &height)) return error.SdlGetWindowSize;
        gl.Viewport(0, 0, width, height);
        gl.Enable(gl.FRAMEBUFFER_SRGB);
        gl.Enable(gl.DEPTH_TEST);
        gl.Enable(gl.CULL_FACE);
        gl.CullFace(gl.BACK);
        gl.ClearColor(0, 0.2, 0.7, 1);
        gl.Clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    }

    pub fn present(self: Self) !void {
        if (!sdl.SDL_GL_SwapWindow(self.window)) return error.SdlOpenGlSwapWindow;
    }
};

pub const Pipeline = struct {
    const Self = @This();

    program: u32,

    pub const Uniform = union(enum) {
        bool: bool,
        i32: i32,
        u32: u32,
        f32: f32,
        f64: f64,
        f32x2: [2]f32,
        f64x2: [2]f64,
        f32x3: [3]f32,
        f64x3: [3]f64,
        f32x4: [4]f32,
        f64x4: [4]f64,
        mat4: struct { [16]f32, bool },
    };

    pub fn init(vertex: [:0]const u8, fragment: [:0]const u8, geometry: ?[:0]const u8) !Self {
        const program = gl.CreateProgram();

        const vertex_shaders = try Self.compileShader(vertex, gl.VERTEX_SHADER);
        const fragment_shaders = try Self.compileShader(fragment, gl.FRAGMENT_SHADER);
        const geometry_shaders = if (geometry != null) try Self.compileShader(geometry.?, gl.GEOMETRY_SHADER) else null;

        gl.AttachShader(program, vertex_shaders);
        gl.AttachShader(program, fragment_shaders);
        if (geometry_shaders != null) gl.AttachShader(program, geometry_shaders.?);

        gl.LinkProgram(program);

        gl.DeleteShader(vertex_shaders);
        gl.DeleteShader(fragment_shaders);
        if (geometry_shaders != null) gl.DeleteShader(geometry_shaders.?);

        var success: c_int = undefined;

        gl.GetProgramiv(program, gl.LINK_STATUS, &success);
        if (success != gl.TRUE) {
            var info_log: [512]u8 = undefined;

            gl.GetProgramInfoLog(program, info_log.len, null, &info_log);
            log.err("Failed to create shader program: {s}", .{info_log});
            return error.PipelineProgramCreation;
        }

        return .{ .program = program };
    }

    pub inline fn deinit(self: Self) void {
        gl.DeleteProgram(self.program);
    }

    pub inline fn bind(self: Self) void {
        gl.UseProgram(self.program);
    }

    pub fn setUniform(self: Self, name: [:0]const u8, data: Uniform) !void {
        const location = gl.GetUniformLocation(self.program, name);
        if (location == -1) return error.UniformNotFound;

        switch (data) {
            .bool => |d| gl.ProgramUniform1i(self.program, location, @intFromBool(d)),
            .i32 => |d| gl.ProgramUniform1i(self.program, location, d),
            .u32 => |d| gl.ProgramUniform1ui(self.program, location, d),
            .f32 => |d| gl.ProgramUniform1f(self.program, location, d),
            .f64 => |d| gl.ProgramUniform1d(self.program, location, d),
            .f32x2 => |d| gl.ProgramUniform2f(self.program, location, d[0], d[1]),
            .f64x2 => |d| gl.ProgramUniform2d(self.program, location, d[0], d[1]),
            .f32x3 => |d| gl.ProgramUniform3f(self.program, location, d[0], d[1], d[2]),
            .f64x3 => |d| gl.ProgramUniform3d(self.program, location, d[0], d[1], d[2]),
            .f32x4 => |d| gl.ProgramUniform4f(self.program, location, d[0], d[1], d[2], d[3]),
            .f64x4 => |d| gl.ProgramUniform4d(self.program, location, d[0], d[1], d[2], d[3]),
            .mat4 => |d| gl.ProgramUniformMatrix4fv(self.program, location, 1, @intFromBool(d.@"1"), @ptrCast(&d.@"0")),
        }
    }

    fn compileShader(source: [:0]const u8, kind: u32) !u32 {
        const shader: u32 = gl.CreateShader(@intCast(kind));
        gl.ShaderSource(shader, 1, @ptrCast(&source), null);
        gl.CompileShader(shader);

        var success: c_int = 0;
        gl.GetShaderiv(shader, gl.COMPILE_STATUS, &success);

        if (success != gl.TRUE) {
            var info_log: [512]u8 = undefined;
            gl.GetShaderInfoLog(shader, info_log.len, null, &info_log);
            log.err("Shader compile error: {s}", .{info_log});
            gl.DeleteShader(shader);
            return error.ShaderCompilation;
        }

        return shader;
    }
};

pub const Object = struct {
    const Self = @This();

    vao: u32,
    vbo: u32,
    ebo: u32,
    indices_len: usize,

    pub fn init(vertices: []f32, indices: []u32) !Self {
        var vao: u32 = undefined;
        var vbo: u32 = undefined;
        var ebo: u32 = undefined;

        gl.GenVertexArrays(1, @ptrCast(&vao));
        gl.GenBuffers(1, @ptrCast(&vbo));
        gl.GenBuffers(1, @ptrCast(&ebo));

        gl.BindVertexArray(vao);

        // VBO
        gl.BindBuffer(gl.ARRAY_BUFFER, vbo);
        gl.BufferData(
            gl.ARRAY_BUFFER,
            @intCast(vertices.len * @sizeOf(f32)),
            @ptrCast(vertices.ptr),
            gl.STATIC_DRAW,
        );

        // EBO
        gl.BindBuffer(gl.ELEMENT_ARRAY_BUFFER, ebo);
        gl.BufferData(
            gl.ELEMENT_ARRAY_BUFFER,
            @intCast(indices.len * @sizeOf(u32)),
            @ptrCast(indices.ptr),
            gl.STATIC_DRAW,
        );

        const stride = 8 * @sizeOf(f32);

        // Position attribute (location = 0)
        gl.VertexAttribPointer(0, 3, gl.FLOAT, gl.FALSE, stride, 0);
        gl.EnableVertexAttribArray(0);

        // UV attribute (location = 1)
        gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, stride, 3 * @sizeOf(f32));
        gl.EnableVertexAttribArray(1);

        // Color attribute (location = 2)
        gl.VertexAttribPointer(2, 3, gl.FLOAT, gl.FALSE, stride, 5 * @sizeOf(f32));
        gl.EnableVertexAttribArray(2);

        // Only unbind ARRAY_BUFFER — keep EBO bound to VAO
        gl.BindBuffer(gl.ARRAY_BUFFER, 0);
        gl.BindVertexArray(0);

        return .{
            .vao = vao,
            .vbo = vbo,
            .ebo = ebo,
            .indices_len = indices.len,
        };
    }

    pub fn deinit(self: Self) void {
        gl.DeleteVertexArrays(1, @ptrCast(@constCast(&self.vao)));
        gl.DeleteBuffers(1, @ptrCast(@constCast(&self.vbo)));
        gl.DeleteBuffers(1, @ptrCast(@constCast(&self.ebo)));
    }

    pub fn draw(self: Self) void {
        gl.BindVertexArray(self.vao);
        gl.DrawElements(gl.TRIANGLES, @intCast(self.indices_len), gl.UNSIGNED_INT, 0);
        gl.BindVertexArray(0);
    }
};

pub const Texture = struct {
    const Self = @This();

    id: u32,

    pub fn init(path: [*:0]const u8) !Self {
        var texture: u32 = 0;
        gl.GenTextures(1, @ptrCast(&texture));
        gl.BindTexture(gl.TEXTURE_2D, @intCast(texture));

        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.REPEAT);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
        gl.TexParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);

        const surface = sdl_img.IMG_Load(path) orelse return error.LoadImage; // TODO: Change out image loading liberary
        gl.TexImage2D(gl.TEXTURE_2D, 0, gl.RGB, @intCast(surface.*.w), @intCast(surface.*.h), 0, gl.RGB, gl.UNSIGNED_BYTE, surface.*.pixels);
        gl.GenerateMipmap(gl.TEXTURE_2D);

        return .{ .id = texture };
    }

    pub fn deinit(self: Self) void {
        gl.DeleteTextures(1, @ptrCast(@constCast(&self.id)));
    }

    /// Units are from 0-31
    pub fn bind(self: Self, unit: u32) void {
        gl.ActiveTexture(@intCast(gl.TEXTURE0 + unit));
        gl.BindTexture(gl.TEXTURE_2D, self.id);
    }
};
