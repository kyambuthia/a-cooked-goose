import std;
import gfx;
import os;
import ui;

let GRID_X: i64 = 24;
let GRID_Y: i64 = 16;
let GRID_Z: i64 = 24;
let GRID_N: i64 = 24 * 16 * 24;
let VOXEL_SIZE: f32 = 0.45;

let MAT_AIR: u8 = 0;
let MAT_GROUND: u8 = 1;
let MAT_CONCRETE: u8 = 2;
let MAT_BRICK: u8 = 3;
let MAT_WOOD: u8 = 4;
let MAT_GLASS: u8 = 5;
let MAT_STEEL: u8 = 6;

struct Vertex {
    pos: float3,
    color: u8[4],
}

struct Transform {
    model: gfx::mat4,
    view_proj: gfx::mat4,
    tint: float4,
}

struct Debris {
    pos: float3,
    vel: float3,
    angle: f32,
    spin: f32,
    axis: float3,
    scale: f32,
    color: u8[4],
    life: f32,
}

fn idx(x: i64, y: i64, z: i64) -> i64 {
    return (y * GRID_Z + z) * GRID_X + x;
}

fn in_bounds(x: i64, y: i64, z: i64) -> bool {
    return x >= 0 && x < GRID_X && y >= 0 && y < GRID_Y && z >= 0 && z < GRID_Z;
}

fn voxel_world_pos(x: i64, y: i64, z: i64) -> float3 {
    let half_x = GRID_X * 0.5 * VOXEL_SIZE;
    let half_z = GRID_Z * 0.5 * VOXEL_SIZE;
    return float3 {
        (x + 0.5) * VOXEL_SIZE - half_x,
        (y + 0.5) * VOXEL_SIZE,
        (z + 0.5) * VOXEL_SIZE - half_z
    };
}

fn mat_color(mat: u8, shade: f32, x: i64, y: i64, z: i64) -> u8[4] {
    var r: f32 = 180.0;
    var g: f32 = 180.0;
    var b: f32 = 180.0;
    let checker = ((x + y + z) & 1) as f32;
    if mat == MAT_GROUND {
        r = 56.0 + checker * 14.0;
        g = 68.0 + checker * 16.0;
        b = 82.0 + checker * 16.0;
    } else if mat == MAT_CONCRETE {
        let n = ((x * 7 + y * 13 + z * 19) & 3) as f32 * 5.0;
        r = 165.0 + n;
        g = 168.0 + n;
        b = 174.0 + n;
    } else if mat == MAT_BRICK {
        let alt = ((x + z + y * 2) & 1) as f32 * 16.0;
        r = 188.0 - alt;
        g = 84.0 - alt * 0.5;
        b = 64.0 - alt * 0.4;
    } else if mat == MAT_WOOD {
        let grain = ((x + z) & 1) as f32 * 12.0;
        r = 156.0 + grain;
        g = 108.0 + grain * 0.7;
        b = 62.0 + grain * 0.4;
    } else if mat == MAT_GLASS {
        r = 128.0;
        g = 212.0;
        b = 242.0;
    } else if mat == MAT_STEEL {
        r = 212.0;
        g = 182.0;
        b = 88.0;
    }
    return [
        min(255.0, max(0.0, r * shade)) as u8,
        min(255.0, max(0.0, g * shade)) as u8,
        min(255.0, max(0.0, b * shade)) as u8,
        255
    ];
}

fn init_world(grid: u8[>..]&) {
    grid.resize(0);
    grid.resize(GRID_N, MAT_AIR);

    for z in GRID_Z {
        for x in GRID_X {
            grid[idx(x, 0, z)] = MAT_GROUND;
        }
    }

    // Main multi-story voxel building (x: 5..18, z: 5..18, y: 1..11)
    for y in 1..12 {
        for z in 5..19 {
            for x in 5..19 {
                let on_x_edge = x == 5 || x == 18;
                let on_z_edge = z == 5 || z == 18;
                let is_wall = on_x_edge || on_z_edge;
                let is_floor_slab = y == 6 || y == 11;

                if y == 11 {
                    grid[idx(x, y, z)] = MAT_WOOD;
                } else if is_floor_slab && !is_wall {
                    grid[idx(x, y, z)] = MAT_WOOD;
                } else if is_wall {
                    // Doorway on front (z == 18)
                    if z == 18 && y >= 1 && y <= 3 && x >= 11 && x <= 12 {
                        continue;
                    }
                    // Windows on walls
                    if (y == 3 || y == 4 || y == 8 || y == 9) &&
                       ((on_z_edge && (x == 8 || x == 9 || x == 14 || x == 15)) ||
                        (on_x_edge && (z == 8 || z == 9 || z == 14 || z == 15))) {
                        grid[idx(x, y, z)] = MAT_GLASS;
                    } else if (x == 5 || x == 18) && (z == 5 || z == 18) {
                        grid[idx(x, y, z)] = MAT_CONCRETE;
                    } else {
                        grid[idx(x, y, z)] = MAT_BRICK;
                    }
                }
            }
        }
    }

    // Interior steel/gold core pillar + crates
    for y in 1..11 {
        grid[idx(11, y, 11)] = MAT_STEEL;
        grid[idx(12, y, 11)] = MAT_STEEL;
    }
    for y in 1..3 {
        for z in 7..9 {
            for x in 7..9 {
                grid[idx(x, y, z)] = MAT_WOOD;
            }
        }
    }
}

fn push_quad(verts: Vertex[>..]&, indices: u32[>..]&,
             p0: float3, p1: float3, p2: float3, p3: float3,
             color: u8[4]) {
    let base = verts.len as u32;
    verts.push(Vertex { pos: p0, color: color });
    verts.push(Vertex { pos: p1, color: color });
    verts.push(Vertex { pos: p2, color: color });
    verts.push(Vertex { pos: p3, color: color });
    indices.push(base);
    indices.push(base + 1);
    indices.push(base + 2);
    indices.push(base);
    indices.push(base + 2);
    indices.push(base + 3);
}

fn build_unit_cube(verts: Vertex[>..]&, indices: u32[>..]&) {
    let s: f32 = 0.5;
    let c_top: u8[4] = [255, 255, 255, 255];
    let c_side: u8[4] = [210, 210, 210, 255];
    let c_bot: u8[4] = [150, 150, 150, 255];

    // +Y
    push_quad(verts, indices,
        float3 { -s, s, s }, float3 { s, s, s },
        float3 { s, s, -s }, float3 { -s, s, -s }, c_top);
    // -Y
    push_quad(verts, indices,
        float3 { -s, -s, -s }, float3 { s, -s, -s },
        float3 { s, -s, s }, float3 { -s, -s, s }, c_bot);
    // +X
    push_quad(verts, indices,
        float3 { s, -s, s }, float3 { s, -s, -s },
        float3 { s, s, -s }, float3 { s, s, s }, c_side);
    // -X
    push_quad(verts, indices,
        float3 { -s, -s, -s }, float3 { -s, -s, s },
        float3 { -s, s, s }, float3 { -s, s, -s }, c_side);
    // +Z
    push_quad(verts, indices,
        float3 { -s, -s, s }, float3 { s, -s, s },
        float3 { s, s, s }, float3 { -s, s, s }, c_side);
    // -Z
    push_quad(verts, indices,
        float3 { s, -s, -s }, float3 { -s, -s, -s },
        float3 { -s, s, -s }, float3 { s, s, -s }, c_side);
}

fn rebuild_mesh(grid: const u8[:], verts: Vertex[>..]&, indices: u32[>..]&,
                voxel_count: i64&) {
    verts.resize(0);
    indices.resize(0);
    voxel_count = 0;

    let half_x = GRID_X * 0.5 * VOXEL_SIZE;
    let half_z = GRID_Z * 0.5 * VOXEL_SIZE;

    for y in GRID_Y {
        for z in GRID_Z {
            for x in GRID_X {
                let mat = grid[idx(x, y, z)];
                if mat == MAT_AIR { continue; }
                voxel_count += 1;

                let x0 = x * VOXEL_SIZE - half_x;
                let x1 = x0 + VOXEL_SIZE;
                let y0 = y * VOXEL_SIZE;
                let y1 = y0 + VOXEL_SIZE;
                let z0 = z * VOXEL_SIZE - half_z;
                let z1 = z0 + VOXEL_SIZE;

                // +Y
                if !in_bounds(x, y + 1, z) || grid[idx(x, y + 1, z)] == MAT_AIR {
                    push_quad(verts, indices,
                        float3 { x0, y1, z1 }, float3 { x1, y1, z1 },
                        float3 { x1, y1, z0 }, float3 { x0, y1, z0 },
                        mat_color(mat, 1.0, x, y, z));
                }
                // -Y
                if y > 0 && grid[idx(x, y - 1, z)] == MAT_AIR {
                    push_quad(verts, indices,
                        float3 { x0, y0, z0 }, float3 { x1, y0, z0 },
                        float3 { x1, y0, z1 }, float3 { x0, y0, z1 },
                        mat_color(mat, 0.55, x, y, z));
                }
                // +X
                if !in_bounds(x + 1, y, z) || grid[idx(x + 1, y, z)] == MAT_AIR {
                    push_quad(verts, indices,
                        float3 { x1, y0, z1 }, float3 { x1, y0, z0 },
                        float3 { x1, y1, z0 }, float3 { x1, y1, z1 },
                        mat_color(mat, 0.86, x, y, z));
                }
                // -X
                if !in_bounds(x - 1, y, z) || grid[idx(x - 1, y, z)] == MAT_AIR {
                    push_quad(verts, indices,
                        float3 { x0, y0, z0 }, float3 { x0, y0, z1 },
                        float3 { x0, y1, z1 }, float3 { x0, y1, z0 },
                        mat_color(mat, 0.72, x, y, z));
                }
                // +Z
                if !in_bounds(x, y, z + 1) || grid[idx(x, y, z + 1)] == MAT_AIR {
                    push_quad(verts, indices,
                        float3 { x0, y0, z1 }, float3 { x1, y0, z1 },
                        float3 { x1, y1, z1 }, float3 { x0, y1, z1 },
                        mat_color(mat, 0.92, x, y, z));
                }
                // -Z
                if !in_bounds(x, y, z - 1) || grid[idx(x, y, z - 1)] == MAT_AIR {
                    push_quad(verts, indices,
                        float3 { x1, y0, z0 }, float3 { x0, y0, z0 },
                        float3 { x0, y1, z0 }, float3 { x1, y1, z0 },
                        mat_color(mat, 0.66, x, y, z));
                }
            }
        }
    }
}

fn spawn_debris(debris: Debris[>..]&, pos: float3, center: float3, mat: u8,
                x: i64, y: i64, z: i64, strength: f32) {
    if debris.len >= 256 { return; }
    let dx = pos.x - center.x + (((x * 17 + z * 31) & 7) - 3.5) * 0.05;
    let dy = pos.y - center.y + 0.35;
    let dz = pos.z - center.z + (((z * 23 + y * 11) & 7) - 3.5) * 0.05;
    let len = max(0.1, sqrt(dx * dx + dy * dy + dz * dz));
    let speed = strength * (0.7 + ((x + y + z) & 3) * 0.2);

    debris.push(Debris {
        pos: pos,
        vel: float3 { dx / len * speed, dy / len * speed + 2.2, dz / len * speed },
        angle: 0.0,
        spin: 4.0 + ((x * 5 + y * 3) & 7),
        axis: float3 {
            0.3 + (x & 3) * 0.2,
            0.5 + (y & 3) * 0.2,
            0.2 + (z & 3) * 0.2
        },
        scale: VOXEL_SIZE * 0.85,
        color: mat_color(mat, 0.95, x, y, z),
        life: 6.0
    });
}

fn detach_unsupported(grid: u8[>..]&, debris: Debris[>..]&, blast_center: float3) {
    var visited: u8[>..] = [];
    visited.resize(GRID_N, 0);
    var queue: i64[>..] = [];

    for z in GRID_Z {
        for x in GRID_X {
            let i = idx(x, 0, z);
            if grid[i] != MAT_AIR {
                visited[i] = 1;
                queue.push(i);
            }
        }
    }

    var head: i64 = 0;
    while head < queue.len {
        let cur = queue[head];
        head += 1;
        let x = cur % GRID_X;
        let tmp = cur / GRID_X;
        let z = tmp % GRID_Z;
        let y = tmp / GRID_Z;

        if x + 1 < GRID_X {
            let n = idx(x + 1, y, z);
            if grid[n] != MAT_AIR && visited[n] == 0 { visited[n] = 1; queue.push(n); }
        }
        if x - 1 >= 0 {
            let n = idx(x - 1, y, z);
            if grid[n] != MAT_AIR && visited[n] == 0 { visited[n] = 1; queue.push(n); }
        }
        if z + 1 < GRID_Z {
            let n = idx(x, y, z + 1);
            if grid[n] != MAT_AIR && visited[n] == 0 { visited[n] = 1; queue.push(n); }
        }
        if z - 1 >= 0 {
            let n = idx(x, y, z - 1);
            if grid[n] != MAT_AIR && visited[n] == 0 { visited[n] = 1; queue.push(n); }
        }
        if y + 1 < GRID_Y {
            let n = idx(x, y + 1, z);
            if grid[n] != MAT_AIR && visited[n] == 0 { visited[n] = 1; queue.push(n); }
        }
        if y - 1 >= 0 {
            let n = idx(x, y - 1, z);
            if grid[n] != MAT_AIR && visited[n] == 0 { visited[n] = 1; queue.push(n); }
        }
    }

    for y in 1..GRID_Y {
        for z in GRID_Z {
            for x in GRID_X {
                let i = idx(x, y, z);
                if grid[i] != MAT_AIR && visited[i] == 0 {
                    let mat = grid[i];
                    grid[i] = MAT_AIR;
                    spawn_debris(debris, voxel_world_pos(x, y, z), blast_center, mat,
                                 x, y, z, 2.0);
                }
            }
        }
    }
}

fn raycast_and_blast(grid: u8[>..]&, debris: Debris[>..]&,
                     origin: float3, dir: float3, radius: f32) -> bool {
    let half_x = GRID_X * 0.5 * VOXEL_SIZE;
    let half_z = GRID_Z * 0.5 * VOXEL_SIZE;
    let step: f32 = VOXEL_SIZE * 0.35;
    var dist: f32 = 0.2;
    var hit = false;
    var hit_pos = float3 { 0.0, 0.0, 0.0 };

    while dist < 32.0 {
        let p = float3 {
            origin.x + dir.x * dist,
            origin.y + dir.y * dist,
            origin.z + dir.z * dist
        };
        let gx = floor((p.x + half_x) / VOXEL_SIZE) as i64;
        let gy = floor(p.y / VOXEL_SIZE) as i64;
        let gz = floor((p.z + half_z) / VOXEL_SIZE) as i64;
        if in_bounds(gx, gy, gz) && grid[idx(gx, gy, gz)] != MAT_AIR {
            hit = true;
            hit_pos = p;
            break;
        }
        dist += step;
    }

    if !hit { return false; }

    let r2 = radius * radius;
    var carved: i64 = 0;
    for y in 1..GRID_Y {
        for z in GRID_Z {
            for x in GRID_X {
                let i = idx(x, y, z);
                let mat = grid[i];
                if mat == MAT_AIR { continue; }
                let wp = voxel_world_pos(x, y, z);
                let dx = wp.x - hit_pos.x;
                let dy = wp.y - hit_pos.y;
                let dz = wp.z - hit_pos.z;
                if dx * dx + dy * dy + dz * dz <= r2 {
                    grid[i] = MAT_AIR;
                    carved += 1;
                    if (carved & 1) == 0 {
                        spawn_debris(debris, wp, hit_pos, mat, x, y, z, 6.5);
                    }
                }
            }
        }
    }

    if carved > 0 {
        detach_unsupported(grid, debris, hit_pos);
        return true;
    }
    return false;
}

fn main() {
    guard gfx::open("A COOKED GOOSE // VOXEL DESTRUCTION", 1024, 680,
                    gfx::WINDOW_RESIZABLE) else {
        write_stderr(str("gfx: ", gfx::error(), "\n"));
        return;
    }

    var cube_verts: Vertex[>..] = [];
    var cube_indices: u32[>..] = [];
    build_unit_cube(cube_verts, cube_indices);
    let cube_vb = gfx::vertex_buffer(bytes_of(cube_verts));
    let cube_ib = gfx::index_buffer(bytes_of(cube_indices));
    let cube_index_count = cube_indices.len;

    var grid: u8[>..] = [];
    init_world(grid);

    var verts: Vertex[>..] = [];
    var indices: u32[>..] = [];
    var voxel_count: i64 = 0;
    rebuild_mesh(grid, verts, indices, voxel_count);

    var world_vb = gfx::vertex_buffer(bytes_of(verts));
    var world_ib = gfx::index_buffer(bytes_of(indices));
    var world_index_count = indices.len;

    let vertex_shader = embed_shader("vert", """
        layout(location = 0) in vec3 a_pos;
        layout(location = 1) in vec4 a_color;
        layout(set = 1, binding = 0) uniform Transform {
            mat4 model;
            mat4 view_proj;
            vec4 tint;
        };
        layout(location = 0) out vec4 v_color;
        void main() {
            v_color = a_color * tint;
            gl_Position = view_proj * model * vec4(a_pos, 1.0);
        }
        """);
    let fragment_shader = embed_shader("frag", """
        layout(location = 0) in vec4 v_color;
        layout(location = 0) out vec4 result;
        void main() {
            result = v_color;
        }
        """);

    var desc = gfx::PipelineDesc { depth_test: true, depth_write: true };
    desc.formats[1] = gfx::VERTEX_UBYTE4_NORM;
    let pipeline = gfx::pipeline(vertex_shader, fragment_shader, desc);

    var ctx = ui::create(16.0);
    guard ctx.id != 0 else {
        write_stderr(str("ui: ", ui::error(), "\n"));
        gfx::close();
        return;
    }
    let panel = ui::WINDOW_BORDER | ui::WINDOW_MOVABLE | ui::WINDOW_TITLE;

    var cam_pos = float3 { 0.0, 4.2, 9.5 };
    var yaw: f32 = 0.0;
    var pitch: f32 = -0.26;
    var mouse_captured = false;
    var blast_radius: f32 = 1.15;
    var blasts: i64 = 0;
    var debris: Debris[>..] = [];

    while gfx::frame() {
        let dt = min(0.05, gfx::delta_time() as f32);
        if gfx::key_pressed("Escape") { break; }

        ui::input_from_gfx(ctx);
        if gfx::key_pressed("Tab") {
            let cap = !mouse_captured;
            if gfx::set_mouse_relative(cap) { mouse_captured = cap; }
        }
        if !mouse_captured && gfx::mouse_pressed(gfx::MOUSE_LEFT) && !ui::wants_mouse(ctx) {
            mouse_captured = gfx::set_mouse_relative(true);
        }
        if mouse_captured {
            let mouse = gfx::mouse_delta();
            yaw -= mouse.x * 0.003;
            pitch = max(-1.35, min(1.35, pitch - mouse.y * 0.003));
        }

        let cos_p = cos(pitch);
        let forward = float3 {
            -sin(yaw) * cos_p,
            sin(pitch),
            -cos(yaw) * cos_p
        };
        let right = float3 { cos(yaw), 0.0, -sin(yaw) };
        let speed: f32 = 5.5 * dt;

        if gfx::key_down("W") {
            cam_pos = float3 {
                cam_pos.x + forward.x * speed,
                cam_pos.y + forward.y * speed,
                cam_pos.z + forward.z * speed
            };
        }
        if gfx::key_down("S") {
            cam_pos = float3 {
                cam_pos.x - forward.x * speed,
                cam_pos.y - forward.y * speed,
                cam_pos.z - forward.z * speed
            };
        }
        if gfx::key_down("D") {
            cam_pos = float3 {
                cam_pos.x + right.x * speed,
                cam_pos.y,
                cam_pos.z + right.z * speed
            };
        }
        if gfx::key_down("A") {
            cam_pos = float3 {
                cam_pos.x - right.x * speed,
                cam_pos.y,
                cam_pos.z - right.z * speed
            };
        }
        if gfx::key_down("Space") || gfx::key_down("E") {
            cam_pos.y += speed;
        }
        if gfx::key_down("C") || gfx::key_down("Q") {
            cam_pos.y = max(0.8, cam_pos.y - speed);
        }

        if gfx::key_pressed("1") { blast_radius = 0.75; }
        if gfx::key_pressed("2") { blast_radius = 1.15; }
        if gfx::key_pressed("3") { blast_radius = 1.80; }

        if gfx::key_pressed("R") {
            init_world(grid);
            debris.resize(0);
            blasts = 0;
            rebuild_mesh(grid, verts, indices, voxel_count);
            gfx::release(world_vb);
            gfx::release(world_ib);
            world_vb = gfx::vertex_buffer(bytes_of(verts));
            world_ib = gfx::index_buffer(bytes_of(indices));
            world_index_count = indices.len;
        }

        let fire = (mouse_captured && gfx::mouse_pressed(gfx::MOUSE_LEFT)) ||
                   gfx::key_pressed("F");
        if fire {
            if raycast_and_blast(grid, debris, cam_pos, forward, blast_radius) {
                blasts += 1;
                rebuild_mesh(grid, verts, indices, voxel_count);
                gfx::release(world_vb);
                gfx::release(world_ib);
                world_vb = gfx::vertex_buffer(bytes_of(verts));
                world_ib = gfx::index_buffer(bytes_of(indices));
                world_index_count = indices.len;
            }
        }

        // Update falling/bouncing debris
        var i: i64 = 0;
        while i < debris.len {
            debris[i].vel.y -= 16.0 * dt;
            debris[i].pos.x += debris[i].vel.x * dt;
            debris[i].pos.y += debris[i].vel.y * dt;
            debris[i].pos.z += debris[i].vel.z * dt;
            debris[i].angle += debris[i].spin * dt;
            debris[i].life -= dt;

            let floor_y = VOXEL_SIZE + debris[i].scale * 0.5;
            if debris[i].pos.y < floor_y {
                debris[i].pos.y = floor_y;
                debris[i].vel.y = -debris[i].vel.y * 0.35;
                debris[i].vel.x *= 0.72;
                debris[i].vel.z *= 0.72;
                debris[i].spin *= 0.75;
            }

            if debris[i].life <= 0.0 {
                let last = debris.len - 1;
                debris[i] = debris[last];
                debris.pop();
            } else {
                i += 1;
            }
        }

        let size = gfx::screen_size();
        let aspect = size.x as f32 / max(size.y, 1);
        let target = float3 {
            cam_pos.x + forward.x,
            cam_pos.y + forward.y,
            cam_pos.z + forward.z
        };
        let view = gfx::look_at(cam_pos, target, float3 { 0.0, 1.0, 0.0 });
        let proj = gfx::perspective(1.05, aspect, 0.1, 100.0);
        let view_proj = gfx::mul(proj, view);

        if ui::begin(ctx, "VOXEL SANDBOX", ui::rect(16, 16, 320, 220), panel) {
            ui::layout_row_dynamic(ctx, 22.0, 1);
            ui::label(ctx, str("VOXELS: ", voxel_count, "  |  DEBRIS: ", debris.len), ui::TEXT_LEFT);
            ui::layout_row_dynamic(ctx, 22.0, 1);
            ui::label(ctx, str("BLASTS: ", blasts, "  |  RADIUS: ", blast_radius), ui::TEXT_LEFT);
            ui::layout_row_dynamic(ctx, 22.0, 1);
            ui::label(ctx, "CLICK / TAB: CAPTURE MOUSE", ui::TEXT_LEFT);
            ui::layout_row_dynamic(ctx, 22.0, 1);
            ui::label(ctx, "LMB / F: BLAST  |  1/2/3: RADIUS", ui::TEXT_LEFT);
            ui::layout_row_dynamic(ctx, 22.0, 1);
            ui::label(ctx, "WASD + E/Q: FLY  |  R: RESET", ui::TEXT_LEFT);
            ui::layout_row_dynamic(ctx, 22.0, 1);
            ui::label(ctx, "ESC: QUIT", ui::TEXT_LEFT);
        }
        ui::end(ctx);

        // Simple crosshair
        let cx = size.x / 2 - 12;
        let cy = size.y / 2 - 12;
        if ui::begin(ctx, "CROSSHAIR", ui::rect(cx, cy, 24, 24),
                     ui::WINDOW_NO_SCROLLBAR | ui::WINDOW_NO_INPUT) {
            ui::layout_row_dynamic(ctx, 18.0, 1);
            ui::label(ctx, "+", ui::TEXT_CENTERED);
        }
        ui::end(ctx);

        gfx::begin_screen(float4 { 0.52, 0.72, 0.90, 1.0 });
        gfx::bind(pipeline);

        if world_index_count > 0 {
            gfx::bind_vertex_buffer(world_vb);
            gfx::bind_index_buffer(world_ib, 4);
            gfx::uniforms(gfx::VERTEX, 0, Transform {
                model: gfx::mat4_identity,
                view_proj: view_proj,
                tint: float4 { 1.0, 1.0, 1.0, 1.0 }
            });
            gfx::draw_indexed(world_index_count);
        }

        if debris.len > 0 {
            gfx::bind_vertex_buffer(cube_vb);
            gfx::bind_index_buffer(cube_ib, 4);
            for d in debris {
                let m = gfx::mul(gfx::translate(d.pos),
                                 gfx::mul(gfx::rotate(d.axis, d.angle),
                                          gfx::scale(float3 { d.scale, d.scale, d.scale })));
                let tint = float4 {
                    d.color[0] / 255.0,
                    d.color[1] / 255.0,
                    d.color[2] / 255.0,
                    1.0
                };
                gfx::uniforms(gfx::VERTEX, 0, Transform {
                    model: m,
                    view_proj: view_proj,
                    tint: tint
                });
                gfx::draw_indexed(cube_index_count);
            }
        }

        gfx::end_pass();
        ui::render(ctx);
    }

    ui::destroy(ctx);
    gfx::release(pipeline);
    gfx::release(cube_vb);
    gfx::release(cube_ib);
    gfx::release(world_vb);
    gfx::release(world_ib);
    gfx::close();
}
