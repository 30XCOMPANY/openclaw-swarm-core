# Design Context

## Users
Developers and technical team leads who use coding agents (Claude Code, Codex, Gemini CLI) and want to move from toy-stage usage to production-grade automated delivery.

## Brand Personality
Technical. Builder-focused. No-bullshit.

## Aesthetic Direction
- **Visual tone**: Terminal-native minimalism with pixel-art texture.
- **Theme**: Light mode only. White background, black text, bright yellow accent.
- **Anti-references**: Rounded SaaS templates, gradient hero sections, anything "app-y".

## Typography
| Role | Font | Weight | Notes |
|------|------|--------|-------|
| Display / Headlines | Geist | Regular (400) or Medium (500) | Never bold. Size does the work. |
| Body | Geist | Regular (400) | Clean, readable. |
| Code / Data / Labels | Geist Mono | Regular (400) | Monospace for anything technical. |
| Decorative / Texture | Geist Pixel (Square/Grid/Line/Circle/Triangle) | Regular | Pixel art texture, labels, accents. |

- No bold (700+) anywhere. Maximum weight: Medium (500).
- Size contrast creates hierarchy, not weight contrast.

## Shape
- **Border radius: 0px everywhere.** No rounded corners.

## Color Palette
| Token | Value | Usage |
|-------|-------|-------|
| `--fg` | `#000000` | Primary text, borders |
| `--bg` | `#FFFFFF` | Background |
| `--accent` | `#E8FF00` | Bright yellow — highlights, tags, emphasis |
| `--fg-muted` | `rgba(0,0,0,0.5)` | Secondary text |
| `--fg-subtle` | `rgba(0,0,0,0.2)` | Tertiary text, placeholders |
| `--border` | `rgba(0,0,0,0.1)` | Dividers |

## Icons
- SF Symbols for all iconography (Apple system icons)
- Reference via SF Symbols Unicode / SVG when needed in HTML

## Design Principles
1. **Subtraction over addition.** Remove what doesn't earn its pixels.
2. **Size over weight.** Hierarchy through scale, not boldness.
3. **Sharp over soft.** No border radius. Ever.
4. **Mono for truth.** Data/code/system values get Geist Mono.
5. **Pixel for texture.** Geist Pixel adds character without clutter.
6. **Yellow for signal.** One accent color, used sparingly for maximum impact.

[PROTOCOL]: Update when design direction changes, then check CLAUDE.md
