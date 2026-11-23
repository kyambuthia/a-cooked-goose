const GRID_X = 36;
const GRID_Y = 24;
const GRID_Z = 36;
const GRID_N = GRID_X * GRID_Y * GRID_Z;
const VOXEL_SIZE = 0.25;

const MAT_AIR = 0;
const MAT_GROUND = 1;
const MAT_CONCRETE = 2;
const MAT_BRICK = 3;
const MAT_WOOD = 4;
const MAT_GLASS = 5;
const MAT_STEEL = 6;

const canvas = document.getElementById("gl");
const gl = canvas.getContext("webgl2", { antialias: true });
if (!gl) {
  document.body.innerHTML = "<p style=\"padding:24px;color:#111\">WebGL2 not supported in this browser.</p>";
  throw new Error("WebGL2 not supported");
}

const vsSource = `#version 300 es
layout(location = 0) in vec3 a_pos;
layout(location = 1) in vec4 a_color;
uniform mat4 u_model;
uniform mat4 u_view_proj;
uniform vec4 u_tint;
out vec4 v_color;
void main() {
  v_color = a_color * u_tint;
  gl_Position = u_view_proj * u_model * vec4(a_pos, 1.0);
}`;

const fsSource = `#version 300 es
precision mediump float;
in vec4 v_color;
out vec4 outColor;
void main() {
  outColor = v_color;
}`;

function compileShader(type, src) {
  const s = gl.createShader(type);
  gl.shaderSource(s, src);
  gl.compileShader(s);
  if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
    throw new Error(gl.getShaderInfoLog(s));
  }
  return s;
}

const prog = gl.createProgram();
gl.attachShader(prog, compileShader(gl.VERTEX_SHADER, vsSource));
gl.attachShader(prog, compileShader(gl.FRAGMENT_SHADER, fsSource));
gl.linkProgram(prog);
if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) {
  throw new Error(gl.getProgramInfoLog(prog));
}

const uModel = gl.getUniformLocation(prog, "u_model");
const uViewProj = gl.getUniformLocation(prog, "u_view_proj");
const uTint = gl.getUniformLocation(prog, "u_tint");

// Minimal column-major mat4 helpers
function mat4Identity() {
  return new Float32Array([1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]);
}
function mat4Mul(a, b) {
  const o = new Float32Array(16);
  for (let c = 0; c < 4; c++) {
    for (let r = 0; r < 4; r++) {
      o[c*4+r] = a[r]*b[c*4] + a[4+r]*b[c*4+1] + a[8+r]*b[c*4+2] + a[12+r]*b[c*4+3];
    }
  }
  return o;
}
function mat4Perspective(fovy, aspect, near, far) {
  const f = 1.0 / Math.tan(fovy * 0.5);
  const nf = 1.0 / (near - far);
  return new Float32Array([
    f / aspect, 0, 0, 0,
    0, f, 0, 0,
    0, 0, (far + near) * nf, -1,
    0, 0, 2 * far * near * nf, 0
  ]);
}
function mat4LookAt(eye, target, up) {
  let zx = eye[0]-target[0], zy = eye[1]-target[1], zz = eye[2]-target[2];
  let zl = Math.hypot(zx, zy, zz) || 1;
  zx /= zl; zy /= zl; zz /= zl;
  let xx = up[1]*zz - up[2]*zy, xy = up[2]*zx - up[0]*zz, xz = up[0]*zy - up[1]*zx;
  let xl = Math.hypot(xx, xy, xz) || 1;
  xx /= xl; xy /= xl; xz /= xl;
  const yx = zy*xz - zz*xy, yy = zz*xx - zx*xz, yz = zx*xy - zy*xx;
  return new Float32Array([
    xx, yx, zx, 0,
    xy, yy, zy, 0,
    xz, yz, zz, 0,
    -(xx*eye[0]+xy*eye[1]+xz*eye[2]),
    -(yx*eye[0]+yy*eye[1]+yz*eye[2]),
    -(zx*eye[0]+zy*eye[1]+zz*eye[2]),
    1
  ]);
}
function mat4TRS(pos, axis, angle, scale) {
  let [ax, ay, az] = axis;
  const al = Math.hypot(ax, ay, az) || 1;
  ax /= al; ay /= al; az /= al;
  const c = Math.cos(angle), s = Math.sin(angle), t = 1 - c;
  const r00 = t*ax*ax + c,    r01 = t*ax*ay + s*az, r02 = t*ax*az - s*ay;
  const r10 = t*ax*ay - s*az, r11 = t*ay*ay + c,    r12 = t*ay*az + s*ax;
  const r20 = t*ax*az + s*ay, r21 = t*ay*az - s*ax, r22 = t*az*az + c;
  return new Float32Array([
    r00*scale, r01*scale, r02*scale, 0,
    r10*scale, r11*scale, r12*scale, 0,
    r20*scale, r21*scale, r22*scale, 0,
    pos[0], pos[1], pos[2], 1
  ]);
}

const idx = (x, y, z) => (y * GRID_Z + z) * GRID_X + x;
const inBounds = (x, y, z) => x >= 0 && x < GRID_X && y >= 0 && y < GRID_Y && z >= 0 && z < GRID_Z;

function voxelWorldPos(x, y, z) {
  const halfX = GRID_X * 0.5 * VOXEL_SIZE;
  const halfZ = GRID_Z * 0.5 * VOXEL_SIZE;
  return [
    (x + 0.5) * VOXEL_SIZE - halfX,
    (y + 0.5) * VOXEL_SIZE,
    (z + 0.5) * VOXEL_SIZE - halfZ
  ];
}

function matColor(mat, shade, x, y, z) {
  let r = 180, g = 180, b = 180;
  const checker = (x + y + z) & 1;
  if (mat === MAT_GROUND) {
    r = 56 + checker * 14; g = 68 + checker * 16; b = 82 + checker * 16;
  } else if (mat === MAT_CONCRETE) {
    const n = ((x * 7 + y * 13 + z * 19) & 3) * 5;
    r = 165 + n; g = 168 + n; b = 174 + n;
  } else if (mat === MAT_BRICK) {
    const alt = ((x + z + y * 2) & 1) * 16;
    r = 188 - alt; g = 84 - alt * 0.5; b = 64 - alt * 0.4;
  } else if (mat === MAT_WOOD) {
    const grain = ((x + z) & 1) * 12;
    r = 156 + grain; g = 108 + grain * 0.7; b = 62 + grain * 0.4;
  } else if (mat === MAT_GLASS) {
    r = 128; g = 212; b = 242;
  } else if (mat === MAT_STEEL) {
    r = 212; g = 182; b = 88;
  }
  return [
    Math.min(255, Math.max(0, (r * shade) | 0)),
    Math.min(255, Math.max(0, (g * shade) | 0)),
    Math.min(255, Math.max(0, (b * shade) | 0)),
    255
  ];
}

const grid = new Uint8Array(GRID_N);
function initWorld() {
  grid.fill(MAT_AIR);
  for (let z = 0; z < GRID_Z; z++) {
    for (let x = 0; x < GRID_X; x++) grid[idx(x, 0, z)] = MAT_GROUND;
  }
  for (let y = 1; y < 17; y++) {
    for (let z = 7; z < 29; z++) {
      for (let x = 7; x < 29; x++) {
        const onX = x === 7 || x === 28;
        const onZ = z === 7 || z === 28;
        const isWall = onX || onZ;
        const isSlab = y === 8 || y === 16;
        if (y === 16) {
          grid[idx(x, y, z)] = MAT_WOOD;
        } else if (isSlab && !isWall) {
          grid[idx(x, y, z)] = MAT_WOOD;
        } else if (isWall) {
          if (z === 28 && y >= 1 && y <= 5 && x >= 16 && x <= 19) continue;
          const winY = (y >= 4 && y <= 6) || (y >= 11 && y <= 13);
          const winX = (x >= 11 && x <= 13) || (x >= 22 && x <= 24);
          const winZ = (z >= 11 && z <= 13) || (z >= 22 && z <= 24);
          if (winY && ((onZ && winX) || (onX && winZ))) {
            grid[idx(x, y, z)] = MAT_GLASS;
          } else if ((x <= 8 || x >= 27) && (z <= 8 || z >= 27)) {
            grid[idx(x, y, z)] = MAT_CONCRETE;
          } else {
            grid[idx(x, y, z)] = MAT_BRICK;
          }
        }
      }
    }
  }
  for (let y = 1; y < 16; y++) {
    grid[idx(17, y, 17)] = MAT_STEEL;
    grid[idx(18, y, 17)] = MAT_STEEL;
    grid[idx(17, y, 18)] = MAT_STEEL;
    grid[idx(18, y, 18)] = MAT_STEEL;
  }
  for (let y = 1; y < 4; y++) {
    for (let z = 10; z < 13; z++) {
      for (let x = 10; x < 13; x++) grid[idx(x, y, z)] = MAT_WOOD;
    }
  }
}

function createMeshBuffers() {
  const vao = gl.createVertexArray();
  const vbo = gl.createBuffer();
  const ibo = gl.createBuffer();
  gl.bindVertexArray(vao);
  gl.bindBuffer(gl.ARRAY_BUFFER, vbo);
  gl.enableVertexAttribArray(0);
  gl.vertexAttribPointer(0, 3, gl.FLOAT, false, 16, 0);
  gl.enableVertexAttribArray(1);
  gl.vertexAttribPointer(1, 4, gl.UNSIGNED_BYTE, true, 16, 12);
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, ibo);
  gl.bindVertexArray(null);
  return { vao, vbo, ibo, count: 0 };
}

function uploadMesh(mesh, posList, colList, idxList) {
  const vCount = posList.length / 3;
  const buf = new ArrayBuffer(vCount * 16);
  const f32 = new Float32Array(buf);
  const u8 = new Uint8Array(buf);
  for (let i = 0; i < vCount; i++) {
    f32[i * 4 + 0] = posList[i * 3 + 0];
    f32[i * 4 + 1] = posList[i * 3 + 1];
    f32[i * 4 + 2] = posList[i * 3 + 2];
    u8[i * 16 + 12] = colList[i * 4 + 0];
    u8[i * 16 + 13] = colList[i * 4 + 1];
    u8[i * 16 + 14] = colList[i * 4 + 2];
    u8[i * 16 + 15] = colList[i * 4 + 3];
  }
  gl.bindBuffer(gl.ARRAY_BUFFER, mesh.vbo);
  gl.bufferData(gl.ARRAY_BUFFER, buf, gl.DYNAMIC_DRAW);
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, mesh.ibo);
  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint32Array(idxList), gl.DYNAMIC_DRAW);
  mesh.count = idxList.length;
}

function pushQuad(pos, col, inds, p0, p1, p2, p3, c) {
  const base = pos.length / 3;
  pos.push(...p0, ...p1, ...p2, ...p3);
  col.push(...c, ...c, ...c, ...c);
  inds.push(base, base + 1, base + 2, base, base + 2, base + 3);
}

const cubeMesh = createMeshBuffers();
{
  const pos = [], col = [], inds = [];
  const s = 0.5;
  const cTop = [255,255,255,255], cSide = [210,210,210,255], cBot = [150,150,150,255];
  pushQuad(pos, col, inds, [-s,s,s], [s,s,s], [s,s,-s], [-s,s,-s], cTop);
  pushQuad(pos, col, inds, [-s,-s,-s], [s,-s,-s], [s,-s,s], [-s,-s,s], cBot);
  pushQuad(pos, col, inds, [s,-s,s], [s,-s,-s], [s,s,-s], [s,s,s], cSide);
  pushQuad(pos, col, inds, [-s,-s,-s], [-s,-s,s], [-s,s,s], [-s,s,-s], cSide);
  pushQuad(pos, col, inds, [-s,-s,s], [s,-s,s], [s,s,s], [-s,s,s], cSide);
  pushQuad(pos, col, inds, [s,-s,-s], [-s,-s,-s], [-s,s,-s], [s,s,-s], cSide);
  uploadMesh(cubeMesh, pos, col, inds);
}

const worldMesh = createMeshBuffers();
let voxelCount = 0;

function rebuildWorldMesh() {
  const pos = [], col = [], inds = [];
  voxelCount = 0;
  const halfX = GRID_X * 0.5 * VOXEL_SIZE;
  const halfZ = GRID_Z * 0.5 * VOXEL_SIZE;
  for (let y = 0; y < GRID_Y; y++) {
    for (let z = 0; z < GRID_Z; z++) {
      for (let x = 0; x < GRID_X; x++) {
        const mat = grid[idx(x, y, z)];
        if (mat === MAT_AIR) continue;
        voxelCount++;
        const x0 = x * VOXEL_SIZE - halfX, x1 = x0 + VOXEL_SIZE;
        const y0 = y * VOXEL_SIZE,         y1 = y0 + VOXEL_SIZE;
        const z0 = z * VOXEL_SIZE - halfZ, z1 = z0 + VOXEL_SIZE;
        if (!inBounds(x, y + 1, z) || grid[idx(x, y + 1, z)] === MAT_AIR)
          pushQuad(pos, col, inds, [x0,y1,z1], [x1,y1,z1], [x1,y1,z0], [x0,y1,z0], matColor(mat, 1.0, x, y, z));
        if (y > 0 && grid[idx(x, y - 1, z)] === MAT_AIR)
          pushQuad(pos, col, inds, [x0,y0,z0], [x1,y0,z0], [x1,y0,z1], [x0,y0,z1], matColor(mat, 0.55, x, y, z));
        if (!inBounds(x + 1, y, z) || grid[idx(x + 1, y, z)] === MAT_AIR)
          pushQuad(pos, col, inds, [x1,y0,z1], [x1,y0,z0], [x1,y1,z0], [x1,y1,z1], matColor(mat, 0.86, x, y, z));
        if (!inBounds(x - 1, y, z) || grid[idx(x - 1, y, z)] === MAT_AIR)
          pushQuad(pos, col, inds, [x0,y0,z0], [x0,y0,z1], [x0,y1,z1], [x0,y1,z0], matColor(mat, 0.72, x, y, z));
        if (!inBounds(x, y, z + 1) || grid[idx(x, y, z + 1)] === MAT_AIR)
          pushQuad(pos, col, inds, [x0,y0,z1], [x1,y0,z1], [x1,y1,z1], [x0,y1,z1], matColor(mat, 0.92, x, y, z));
        if (!inBounds(x, y, z - 1) || grid[idx(x, y, z - 1)] === MAT_AIR)
          pushQuad(pos, col, inds, [x1,y0,z0], [x0,y0,z0], [x0,y1,z0], [x1,y1,z0], matColor(mat, 0.66, x, y, z));
      }
    }
  }
  uploadMesh(worldMesh, pos, col, inds);
}

const debris = [];
function spawnDebris(pos, center, mat, x, y, z, strength) {
  if (debris.length >= 256) return;
  const dx = pos[0] - center[0] + (((x * 17 + z * 31) & 7) - 3.5) * 0.05;
  const dy = pos[1] - center[1] + 0.35;
  const dz = pos[2] - center[2] + (((z * 23 + y * 11) & 7) - 3.5) * 0.05;
  const len = Math.max(0.1, Math.hypot(dx, dy, dz));
  const speed = strength * (0.7 + ((x + y + z) & 3) * 0.2);
  debris.push({
    pos: [...pos],
    vel: [dx / len * speed, dy / len * speed + 2.2, dz / len * speed],
    angle: 0,
    spin: 4 + ((x * 5 + y * 3) & 7),
    axis: [0.3 + (x & 3) * 0.2, 0.5 + (y & 3) * 0.2, 0.2 + (z & 3) * 0.2],
    scale: VOXEL_SIZE * 0.85,
    color: matColor(mat, 0.95, x, y, z),
    life: 6.0
  });
}

function detachUnsupported(blastCenter) {
  const visited = new Uint8Array(GRID_N);
  const queue = [];
  for (let z = 0; z < GRID_Z; z++) {
    for (let x = 0; x < GRID_X; x++) {
      const i = idx(x, 0, z);
      if (grid[i] !== MAT_AIR) { visited[i] = 1; queue.push(i); }
    }
  }
  let head = 0;
  while (head < queue.length) {
    const cur = queue[head++];
    const x = cur % GRID_X;
    const tmp = (cur / GRID_X) | 0;
    const z = tmp % GRID_Z;
    const y = (tmp / GRID_Z) | 0;
    const pushN = (nx, ny, nz) => {
      const n = idx(nx, ny, nz);
      if (grid[n] !== MAT_AIR && !visited[n]) { visited[n] = 1; queue.push(n); }
    };
    if (x + 1 < GRID_X) pushN(x + 1, y, z);
    if (x - 1 >= 0)     pushN(x - 1, y, z);
    if (z + 1 < GRID_Z) pushN(x, y, z + 1);
    if (z - 1 >= 0)     pushN(x, y, z - 1);
    if (y + 1 < GRID_Y) pushN(x, y + 1, z);
    if (y - 1 >= 0)     pushN(x, y - 1, z);
  }
  for (let y = 1; y < GRID_Y; y++) {
    for (let z = 0; z < GRID_Z; z++) {
      for (let x = 0; x < GRID_X; x++) {
        const i = idx(x, y, z);
        if (grid[i] !== MAT_AIR && !visited[i]) {
          const mat = grid[i];
          grid[i] = MAT_AIR;
          spawnDebris(voxelWorldPos(x, y, z), blastCenter, mat, x, y, z, 2.0);
        }
      }
    }
  }
}

function raycastAndBlast(origin, dir, radius) {
  const halfX = GRID_X * 0.5 * VOXEL_SIZE;
  const halfZ = GRID_Z * 0.5 * VOXEL_SIZE;
  const step = VOXEL_SIZE * 0.35;
  let hitPos = null;
  for (let dist = 0.2; dist < 32.0; dist += step) {
    const p = [origin[0] + dir[0]*dist, origin[1] + dir[1]*dist, origin[2] + dir[2]*dist];
    const gx = Math.floor((p[0] + halfX) / VOXEL_SIZE);
    const gy = Math.floor(p[1] / VOXEL_SIZE);
    const gz = Math.floor((p[2] + halfZ) / VOXEL_SIZE);
    if (inBounds(gx, gy, gz) && grid[idx(gx, gy, gz)] !== MAT_AIR) {
      hitPos = p;
      break;
    }
  }
  if (!hitPos) return false;

  const r2 = radius * radius;
  let carved = 0;
  for (let y = 1; y < GRID_Y; y++) {
    for (let z = 0; z < GRID_Z; z++) {
      for (let x = 0; x < GRID_X; x++) {
        const i = idx(x, y, z);
        const mat = grid[i];
        if (mat === MAT_AIR) continue;
        const wp = voxelWorldPos(x, y, z);
        const dx = wp[0] - hitPos[0], dy = wp[1] - hitPos[1], dz = wp[2] - hitPos[2];
        if (dx*dx + dy*dy + dz*dz <= r2) {
          grid[i] = MAT_AIR;
          carved++;
          if ((carved & 1) === 0) spawnDebris(wp, hitPos, mat, x, y, z, 6.5);
        }
      }
    }
  }
  if (carved > 0) {
    detachUnsupported(hitPos);
    rebuildWorldMesh();
    return true;
  }
  return false;
}

const camPos = [0, 4.2, 9.5];
let yaw = 0, pitch = -0.26;
let blastRadius = 0.90;
let blasts = 0;
const keys = new Set();

function resetWorld() {
  initWorld();
  debris.length = 0;
  blasts = 0;
  rebuildWorldMesh();
}

function getForward() {
  const cp = Math.cos(pitch);
  return [-Math.sin(yaw) * cp, Math.sin(pitch), -Math.cos(yaw) * cp];
}

function doBlast() {
  if (raycastAndBlast(camPos, getForward(), blastRadius)) blasts++;
}

function setRadius(r) {
  blastRadius = r;
  document.querySelectorAll("#bar button[data-r]").forEach((b) => {
    b.classList.toggle("active", parseFloat(b.dataset.r) === r);
  });
}

window.addEventListener("keydown", (e) => {
  keys.add(e.code);
  if (e.code === "Digit1") setRadius(0.55);
  if (e.code === "Digit2") setRadius(0.90);
  if (e.code === "Digit3") setRadius(1.45);
  if (e.code === "KeyF") doBlast();
  if (e.code === "KeyR") resetWorld();
});
window.addEventListener("keyup", (e) => keys.delete(e.code));

canvas.addEventListener("mousedown", (e) => {
  if (e.button !== 0) return;
  if (document.pointerLockElement !== canvas) {
    canvas.requestPointerLock?.();
  } else {
    doBlast();
  }
});

window.addEventListener("mousemove", (e) => {
  if (document.pointerLockElement === canvas) {
    yaw -= e.movementX * 0.0025;
    pitch = Math.max(-1.35, Math.min(1.35, pitch - e.movementY * 0.0025));
  }
});

document.querySelectorAll("#bar button[data-r]").forEach((btn) => {
  btn.addEventListener("click", () => setRadius(parseFloat(btn.dataset.r)));
});
document.getElementById("btn-blast").addEventListener("click", doBlast);
document.getElementById("btn-reset").addEventListener("click", resetWorld);

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  canvas.width = Math.floor(window.innerWidth * dpr);
  canvas.height = Math.floor(window.innerHeight * dpr);
  gl.viewport(0, 0, canvas.width, canvas.height);
}
window.addEventListener("resize", resize);
resize();

resetWorld();

const statsEl = document.getElementById("stats");
const blastEl = document.getElementById("blast-info");
const identity = mat4Identity();
let lastTime = performance.now();
let fpsSmooth = 60;

function frame(now) {
  const dt = Math.min(0.05, (now - lastTime) * 0.001);
  lastTime = now;
  if (dt > 0) fpsSmooth = fpsSmooth * 0.9 + (1 / dt) * 0.1;

  const fwd = getForward();
  const right = [Math.cos(yaw), 0, -Math.sin(yaw)];
  const speed = 5.5 * dt;
  if (keys.has("KeyW")) { camPos[0]+=fwd[0]*speed; camPos[1]+=fwd[1]*speed; camPos[2]+=fwd[2]*speed; }
  if (keys.has("KeyS")) { camPos[0]-=fwd[0]*speed; camPos[1]-=fwd[1]*speed; camPos[2]-=fwd[2]*speed; }
  if (keys.has("KeyD")) { camPos[0]+=right[0]*speed; camPos[2]+=right[2]*speed; }
  if (keys.has("KeyA")) { camPos[0]-=right[0]*speed; camPos[2]-=right[2]*speed; }
  if (keys.has("Space") || keys.has("KeyE")) camPos[1] += speed;
  if (keys.has("KeyC") || keys.has("KeyQ")) camPos[1] = Math.max(0.8, camPos[1] - speed);

  for (let i = 0; i < debris.length;) {
    const d = debris[i];
    d.vel[1] -= 16.0 * dt;
    d.pos[0] += d.vel[0] * dt;
    d.pos[1] += d.vel[1] * dt;
    d.pos[2] += d.vel[2] * dt;
    d.angle += d.spin * dt;
    d.life -= dt;
    const floorY = VOXEL_SIZE + d.scale * 0.5;
    if (d.pos[1] < floorY) {
      d.pos[1] = floorY;
      d.vel[1] = -d.vel[1] * 0.35;
      d.vel[0] *= 0.72;
      d.vel[2] *= 0.72;
      d.spin *= 0.75;
    }
    if (d.life <= 0) {
      debris[i] = debris[debris.length - 1];
      debris.pop();
    } else {
      i++;
    }
  }

  gl.clearColor(0.52, 0.72, 0.90, 1.0);
  gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
  gl.enable(gl.DEPTH_TEST);
  gl.enable(gl.CULL_FACE);

  const aspect = canvas.width / Math.max(canvas.height, 1);
  const view = mat4LookAt(camPos, [camPos[0]+fwd[0], camPos[1]+fwd[1], camPos[2]+fwd[2]], [0, 1, 0]);
  const proj = mat4Perspective(1.05, aspect, 0.1, 100.0);
  const viewProj = mat4Mul(proj, view);

  gl.useProgram(prog);
  gl.uniformMatrix4fv(uViewProj, false, viewProj);

  if (worldMesh.count > 0) {
    gl.bindVertexArray(worldMesh.vao);
    gl.uniformMatrix4fv(uModel, false, identity);
    gl.uniform4f(uTint, 1, 1, 1, 1);
    gl.drawElements(gl.TRIANGLES, worldMesh.count, gl.UNSIGNED_INT, 0);
  }

  if (debris.length > 0) {
    gl.bindVertexArray(cubeMesh.vao);
    for (const d of debris) {
      gl.uniformMatrix4fv(uModel, false, mat4TRS(d.pos, d.axis, d.angle, d.scale));
      gl.uniform4f(uTint, d.color[0]/255, d.color[1]/255, d.color[2]/255, 1);
      gl.drawElements(gl.TRIANGLES, cubeMesh.count, gl.UNSIGNED_INT, 0);
    }
  }

  statsEl.textContent = `VOXELS: ${voxelCount} | DEBRIS: ${debris.length} | FPS: ${Math.round(fpsSmooth)}`;
  blastEl.textContent = `BLASTS: ${blasts} | RADIUS: ${blastRadius.toFixed(2)}`;
  requestAnimationFrame(frame);
}

requestAnimationFrame(frame);
