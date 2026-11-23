# a-cooked-goose

Technical architecture and design notes for a voxel-based destructible physics and raytracing game engine.

---

## 1. World Representation: Multi-Volume Voxel Architecture

Instead of storing the entire level inside a single monolithic 3D grid, the world is partitioned into **thousands of independent, movable voxel volumes**:

- **Local Rectilinear Grids:** Inside each volume, voxels are arranged on a dense, axis-aligned orthogonal grid (~10 cm per voxel).
- **Arbitrary World Transforms:** Each volume carries its own position and orientation, allowing props, vehicles, doors, and detached debris to translate and rotate freely in 3D space.
- **Dynamic Splitting:** When impacts or explosions carve voxels out of a structure, disconnected clusters split off from the parent volume and spawn as new, independently simulated rigid-body voxel objects.

---

## 2. Direct Voxel Raytracing Pipeline

Aside from a few auxiliary elements (e.g., water surfaces and cables), the renderer does **not** convert voxels into triangle meshes:

- **Screen-Space / Compute Raycasting:** Primary visibility, shadows, and reflections are evaluated directly against voxel volumes in fragment/compute shaders without hardware RT cores.
- **3D DDA Traversal:** Rays step through local voxel grids using a modified **Digital Differential Analysis (DDA)** raymarching algorithm.
- **Mipmap Occupancy Acceleration:** Each volume maintains lower-resolution occupancy mipmaps (hierarchical empty-space skipping) so rays leap across empty regions rather than stepping voxel-by-voxel.
- **Lighting & Volumetrics:**
  - **Soft Shadows & AO:** Raycast occlusion against 10 cm voxel geometry updates immediately as walls and roofs are breached.
  - **Real-Time Global Illumination:** Secondary light bounces are approximated via stochastic ray sampling and irradiance probes.
  - **Reflections & Participating Media:** Smooth surfaces reflect voxel geometry directly, while smoke, dust, and fire integrate into the raymarch loop for volumetric scattering.

---

## 3. Physics, Collisions & Structural Integrity

- **CPU Voxel-vs-Voxel Collision:** Collision detection evaluates overlapping voxel grids directly on the CPU rather than relying on simplified convex hulls, paired with custom rigid-body constraint solvers, broad-phase culling, and body sleeping.
- **Material Metadata:** Each voxel stores material attributes (e.g., wood, concrete, metal, glass, plastic) that govern mass, blast/impact resistance, flammability, and impact audio.
- **Connectivity & Collapse:** After voxels are removed, a structural connectivity pass checks whether remaining clusters still have a supported path to static ground/bedrock. Unsupported sections automatically detach into dynamic falling bodies under gravity.

---

## 4. Core Gameplay Loop

1. **Recon & Preparation:** Unlimited setup phase to scout the level, carve shortcuts through walls, build ramps, position vehicles, and stage routes.
2. **Timed Execution:** Triggering the first objective starts a countdown alarm, turning the prepared environment into a high-speed traversal run through the player-modified geometry.

---

## 5. Assets & Scripting

- **Voxel Models (`.vox`):** Static structures, props, and vehicles are authored as palette-indexed 3D voxel grids (MagicaVoxel `.vox` format) and composed into levels via scene manifests.
- **Embedded Scripting:** Gameplay rules, custom tools, procedural voxel generation, HUD rendering, and networked state sync run through lightweight lifecycle hooks (`init`, `tick`, fixed-step `update`, `draw`).
