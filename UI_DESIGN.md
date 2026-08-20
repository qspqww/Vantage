# Vantage UI Design

## Product Decision

Vantage is a macOS window-switching workbench, not a dashboard. The first screen is organized around the repeated task of identifying a client from its live thumbnail and switching to it. The preview grid is the single visual focus; discovery and filtering live in the sidebar, while low-frequency overlay settings stay in a collapsed Inspector.

## Core Tasks

1. Find a running client by application name or window title.
2. Compare live thumbnails and select the right client.
3. Toggle floating previews and adjust their behavior without leaving the workspace.

## Information Priority

- Primary: live client previews and selected state.
- Secondary: client name, owner name, capture state, and refresh rate.
- Metadata: last refresh time, Accessibility status, exact matching configuration.
- Primary action: selecting a client.
- Secondary actions: pause, next client, show overlays, show Inspector.
- Low-frequency actions: appearance, layout, permissions, and matching rules.

## Page Structure

```text
Sidebar              Workspace                         Inspector (optional)
Vantage              Window preview                    Overlay settings
Search               count / state / refresh rate      Display
Client list          compact object previews            Arrangement
Refresh              empty / loading / error states
```

## Visual Direction

Native macOS utility surface: dark neutral zones, restrained blue selection, quiet dividers, and no decorative grid, glow, gradient, or oversized branding. The preview card is the only repeated container because it represents a real actionable window object.

## Typography

- System UI font for titles, labels, and actions.
- Monospaced numerals only for shortcuts, dimensions, FPS, and timestamps.
- 14px workspace title, 11px object title, 9–12px supporting text.

## Color and Geometry

- Background `#0F1012`, panel `#15171A`, elevated surface `#1E2125`.
- One selected accent from the existing high-contrast palette; status colors are reserved for success, warning, and error.
- Radius: 5px rows, 6px inputs, 7px preview cards.
- Borders: 1px low-contrast dividers; 2px accent only for selected objects.
- Shadows: none in the main workspace; floating panels use the system panel shadow.

## Interaction and States

- Selecting a card activates its exact target window.
- The actual frontmost window receives the strongest visual treatment: accent border and tinted row background. The last selected card remains a weaker secondary state.
- Floating previews accept the first click without becoming active and do not show a selected border, so another preview remains immediately available for switching back.
- Dragging a floating panel never activates it.
- Empty, loading, permission, and capture-error states each provide one direct next action.
- Inspector is hidden by default so the repeated switching task gets the available width.
- Floating preview size, opacity, and refresh rate remain in compact secondary menus.

## Responsive Behavior

The preview grid uses a fixed maximum card width and adds columns only when they fit. At minimum size it collapses to one column; the sidebar and Inspector retain stable widths so controls never overlap.

Preview images use proportional fit rather than fill-cropping. The main grid follows each captured window's real aspect ratio; floating panels keep a stable panel ratio and letterbox the image when needed, so window edges and controls remain visible.

## Language

English is the source language for code, documentation, identifiers, and accessibility semantics. The interface can switch at runtime between English and Simplified Chinese through Settings without restarting the capture service.

## AI-Style Audit

Removed decorative grid lines, glow effects, oversized logo treatment, status pills, duplicate LIVE metadata, shortcut cards, the METAL label, color swatches, and redundant explanatory copy. These changes reduce visual noise without removing a core task.
