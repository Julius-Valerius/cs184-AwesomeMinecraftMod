# BSDF Shader Pack for Minecraft

A unified BSDF rendering pipeline for Minecraft, implemented via the Iris Shaders framework. Replaces default lighting with a physically-based Cook-Torrance model.

## Tech Stack

| Technology | Purpose |
|------------|---------|
| GLSL 330 (compatibility profile) | Shader programming language |
| Iris Shaders | Minecraft shader loader (OptiFine alternative) |
| Sodium | Rendering optimization (bundled with Iris) |
| LabPBR 1.3 | PBR texture standard (Smoothness / F0 / Metal / Emission) |
| Cook-Torrance BRDF | Microfacet specular reflection model (GGX NDF + Schlick Fresnel + Smith G) |

## Requirements

| Item | Version |
|------|---------|
| Minecraft Java Edition | 26.1.2 |
| Iris Shaders | Latest (download from [irisshaders.dev](https://irisshaders.dev/download)) |
| Java | 21+ (recommended: [Adoptium Temurin 21](https://adoptium.net/)) |
| Editor | VS Code (for vibe coding lol) |
| LabPBR Resource Pack | Vanilla PBR (labPBR version) / Patrix / FLAVOR (optional but recommended) |

## Quick Start

### 0. Load the World
Put the `world` into ..\.minecraft\saves\ folder.

### 1. Install Iris

Download the installer from [irisshaders.dev/download](https://irisshaders.dev/download), select your Minecraft version, and click Install. When launching Minecraft, select the `Iris & Sodium` profile.

### 2. Deploy the Shader Pack

Place the `BSDF-Shader` folder in your shaderpacks directory:

```
Windows:  %APPDATA%\.minecraft\shaderpacks\BSDF-Shader\
macOS:    ~/Library/Application Support/minecraft/shaderpacks/BSDF-Shader/
Linux:    ~/.minecraft/shaderpacks/BSDF-Shader/
```

Quick access via PowerShell:
```powershell
explorer "$env:APPDATA\.minecraft\shaderpacks"
```

### 3. Install a LabPBR Resource Pack

Place the **LabPBR** folder in the `resourcepacks` folder. Enable it in-game. The shader will still work without one, but you won't see per-block PBR material differences.

### 4. Activate In-Game

Options → Video Settings → Shader Packs → Select **BSDF-Shader** → Apply.

### 5. Development Workflow

- Edit `.fsh` / `.vsh` files, save, then press **R** in-game to hot-reload the shader
- Press **Ctrl+D** on the shader selection screen to enable debug mode
- GLSL compilation errors appear in the game log (Minecraft Launcher → Settings → enable "Open output log")

## Project Structure

```
BSDF-Shader/
├── README.md
└── shaders/
    ├── shaders.properties              # Global config (shadow resolution, sun angle, etc.)
    │
    │   ── Terrain Rendering (Phase 1 Core) ──
    ├── gbuffers_terrain.vsh            # Terrain vertex shader: passes UVs, normals, view-space position
    ├── gbuffers_terrain.fsh            # Terrain fragment shader: Cook-Torrance BRDF + LabPBR decoding
    │                                   #   - GGX/Trowbridge-Reitz Normal Distribution Function (D)
    │                                   #   - Schlick Fresnel Approximation (F)
    │                                   #   - Height-Correlated Smith Geometry Function (G)
    │                                   #   - LabPBR 4-channel specular decoding
    │                                   #   - Day/night lighting cycle
    │
    │   ── Water & Glass (Phase 2) ──
    ├── gbuffers_water.vsh              # Translucent geometry vertex shader
    ├── gbuffers_water.fsh              # Water/glass fragment shader
    │                                   #   - Schlick Fresnel reflection blending
    │                                   #   - Direction-aware sky environment reflection
    │                                   #   - Sun specular highlight
    │                                   #   - Block light warm-color reflections
    │
    │   ── Sky ──
    ├── gbuffers_skybasic.vsh/fsh       # Sky background color + stars
    ├── gbuffers_skytextured.vsh/fsh    # Sun / moon textures
    │
    │   ── Post-Processing ──
    ├── composite.vsh/fsh               # Post-processing pass (reserved for IBL / SSR)
    └── final.vsh/fsh                   # Final output (currently passthrough)
```

## Implemented Features (Phase 1 + Partial Phase 2)

### Cook-Torrance BRDF (gbuffers_terrain.fsh)

- **D — GGX/Trowbridge-Reitz NDF**: Microfacet normal distribution controlling specular highlight shape
- **F — Schlick Fresnel**: Increased reflectance at grazing angles
- **G — Height-Correlated Smith GGX**: Microfacet self-shadowing/masking with the 1/(4·NdotV·NdotL) denominator folded in
- **Energy Conservation**: Diffuse component scaled by (1 − F)(1 − metallic)

### LabPBR Texture Decoding (gbuffers_terrain.fsh)

Decoded from the `_s` specular atlas:
- R channel → Perceptual smoothness → Linear roughness: `roughness = pow(1 - smoothness, 2)`
- G channel 0–229 → Dielectric F0 reflectance
- G channel 230–255 → Metal (albedo used as F0)
- A channel → Emission intensity

### Water & Glass Reflections (gbuffers_water.fsh)

- Fresnel reflection blending (F0 = 0.04 for standard dielectrics)
- Direction-aware sky reflection gradient (zenith / horizon / ground)
- Sunset orange tinting
- Sun specular highlight (pow 2048)
- Block light warm-color reflections (for torch/neon light reflections on water)

## TODO (Phase 2 & 3)

### Phase 2

- [ ] **BTDF (Bidirectional Transmittance Distribution Function)**: Snell's Law refraction with IOR
- [ ] **IBL (Image-Based Lighting)**: Sample the dynamic skybox for metallic ambient reflections
- [ ] **Vertex Displacement (Mace Impact)**: Sinusoidal terrain shockwave effect
- [ ] **Normal Mapping**: Build TBN matrix using `at_tangent` attribute for per-pixel normals

### Phase 3

- [ ] Per-block PBR parameter fine-tuning (Metals / Dielectrics / Translucents / Emissives)
- [ ] GPU performance profiling and optimization (reduce branching, optimize texture lookups)
- [ ] Screen Space Reflections (SSR) — improved implementation
- [ ] Energy conservation validation (Physical Consistency Analysis)
- [ ] Vanilla vs. PBR side-by-side comparison video
- [ ] Final Technical Report

## Key Files for Development

| File | Edit Frequency | Description |
|------|---------------|-------------|
| `gbuffers_terrain.fsh` | High | BRDF core — most parameter tuning happens here |
| `gbuffers_water.fsh` | High | Water/glass reflections — BTDF will be implemented here |
| `composite.fsh` | Medium | Post-processing — IBL, SSR, fog go here |
| `final.fsh` | Low | Tone mapping (currently passthrough) |
| `shaders.properties` | Low | Global config — rarely needs changes |

## FAQ

**Q: Changes don't appear after pressing R?**
Make sure you're editing files under `shaderpacks/BSDF-Shader/shaders/`, not a different copy.

**Q: Screen goes entirely black or white?**
Check the game log for GLSL compilation errors. Most likely a syntax issue in the shader code.

**Q: No visible PBR effect?**
You need a LabPBR-format resource pack installed. Without one, specular textures contain default values and all blocks will have default roughness/metallic.

**Q: Can we use `#include`?**
Iris's `#include` preprocessor is picky about path formats and can trigger parser bugs. The current approach inlines all code directly into each `.fsh` file to avoid this issue.

**Q: How does Iris load shader programs?**
Iris looks for specifically-named files (e.g. `gbuffers_terrain`, `gbuffers_water`, `composite`, `final`). Each has a `.vsh` (vertex) and `.fsh` (fragment) pair. If a file is missing, Iris falls back to its default rendering for that category.

## References

- [Iris Shader Docs](https://shaders.properties/) — Official Iris shader development documentation
- [LabPBR Material Standard](https://shaderlabs.org/wiki/LabPBR_Material_Standard) — LabPBR texture format specification
- [LearnOpenGL - PBR Theory](https://learnopengl.com/PBR/Theory) — Cook-Torrance BRDF mathematical derivation
- [Iris GitHub](https://github.com/IrisShaders/Iris) — Iris source code
- [shaderLABS](https://github.com/shaderLABS) — Shader pack templates and community resources