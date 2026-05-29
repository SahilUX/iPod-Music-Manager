# App Icon Generation Prompt

Use this prompt with any AI image tool (Midjourney, DALL-E, Stable Diffusion, Firefly).

---

## Prompt

```
macOS app icon in the macOS 26 squircle format, liquid glass aesthetic.

The icon surface is a thick, translucent glass lens — like a piece of curved optical glass floating above a deep purple-to-indigo gradient background (#1a0533 to #2d1b69). The glass has extreme realism: sharp caustic light refractions along the top-left edge, a soft internal glow, and a subtle rainbow chromatic aberration fringe where light bends through the material.

Embedded inside the glass (as if etched or floating within the medium): an audio waveform that morphs left-to-right — angular brick-wall FLAC peaks on the left dissolving into a smooth sine wave on the right. The waveform is rendered in frosted white with a cyan-to-violet iridescent shimmer, visible through the glass with depth and parallax.

The glass surface catches a single bright specular highlight in the upper-left — a crisp white reflection arc, like light hitting a lens. The bottom edge of the glass shows a soft backlit glow bleeding onto the background.

No text. No flat elements. Everything is volumetric and refractive. The overall mood is Apple Vision Pro meets macOS 26 — physical, premium, impossibly glossy.

Style: photorealistic 3D render, ray-traced glass and caustics, 1024x1024, generous padding inside squircle.
```

---

## Variations to Try

**Variation A — Liquid Glass Music Note:**
```
macOS 26 squircle app icon, liquid glass style. A single oversized music note symbol sculpted entirely from thick curved optical glass, hovering above a deep indigo background. The glass note has ray-traced internal reflections, chromatic aberration at the edges, caustic light patterns cast onto the background, and a bright specular highlight arc on the upper face. The background glows faintly purple-blue beneath the glass. Photorealistic 3D render. No text. 1024x1024.
```

**Variation B — Glass Waveform Pill:**
```
macOS 26 squircle icon, liquid glass aesthetic. A wide rounded-rectangle pill of thick transparent glass, oriented horizontally, centered on a dark indigo background. Inside the glass: a glowing audio waveform in iridescent white-cyan. The glass pill has extreme realism — sharp top-edge caustic line, internal light scatter, frosted underside, and a vivid rainbow fringe on the curved corners. Background picks up soft caustic projections from the glass. No text. 1024x1024. Apple Vision Pro material quality.
```

**Variation C — Refractive Arrow + Waveform:**
```
macOS 26 squircle icon, liquid glass. A thick glass rightward-pointing chevron/arrow, sculpted like a physical glass object with rounded bevels. The arrow's body contains a horizontal sine waveform visible through the glass as a white iridescent trace. Extreme caustic light refractions along all glass edges. Deep purple-black background with soft light bloom behind the glass. Photorealistic, ray-traced. No text. 1024x1024.
```

---

## Usage Notes

- Generate at 1024×1024, then export at: 1024, 512, 256, 128, 64, 32, 16px for the `.icns` file
- Use `iconutil` on macOS to assemble the `.icns` from the `AppIcon.iconset` folder
- Target background color hex for Xcode asset: `#1a0533` (dark) / `#2d1b69` (light mode variant)
