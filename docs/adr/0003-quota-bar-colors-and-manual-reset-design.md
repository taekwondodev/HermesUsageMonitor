# ADR-0003: Fixed quota bar colors and Figma-driven manual reset section

- Status: Accepted
- Date: 2026-08-22

## Context

While implementing the ChatGPT manual reset section (issue #34), two visual regressions reached the installed app before being caught:

1. **Quota progress bars inherited the system accent color.** The `ProgressView` bars had always been explicitly tinted through `color(for:freshness:)` (green / orange / red / gray). Adding a `Button("Riscatta").buttonStyle(.borderedProminent)` to the same popover hierarchy propagated its tint through the SwiftUI environment, and the accent-colored system tint visually overrode the per-window colors. The commit that added the section never touched the `ProgressView` code, so the regression was invisible in the diff.
2. **The manual reset section did not match an approved design.** The first implementation invented its own layout, spacing, and label hierarchy instead of reproducing the design the user had prepared.

## Decision

### Quota bar colors are explicit and protected

Every quota `ProgressView` keeps its explicit `.tint(color(for:freshness:))` modifier. Quota bars are never left to inherit a container-level or environment tint, and they always use the fixed semantic palette: green below 80%, orange from 80%, red at 100%, gray when stale. The system accent color is never used for quota state.

When adding any control that sets its own tint (prominent buttons, links, toggles) inside the popover, the new tint must be scoped as narrowly as possible — applied directly on the control or the smallest enclosing subtree — and the full popover must be re-inspected at runtime afterwards, because a diff review cannot catch environment-tint leakage.

### The manual reset section follows the Figma component exactly

The section's source of truth is the Figma component **`reset-manuale-sections`** (file key `leTDr6oEAMH7nl9TZxczUY`, node `47:16`), which defines three variants:

- **Card - Disabled**: count present but credit not redeemable; "Non utilizzabile ora"; disabled button (white text at 40%).
- **Card - Enabled**: applicable credit available; "Utilizzabile ora"; green enabled button.
- **Card - No Reset**: zero resets; "Full reset non disponibile" with no secondary labels.

Exact values implemented in `ManualResetDesignToken`:

| Token | Value |
| --- | --- |
| Header text (title, icon, trailing count) | `#8E8E93` (0.557, 0.557, 0.576) |
| Expanded content background | `#2C2C2E` (0.173, 0.173, 0.180) |
| Primary label | white |
| Applicability label | header gray |
| Expiration label | white at 30% opacity, 10 pt |
| Redeem button | green `#30D158` (0.188, 0.820, 0.345), white label |
| Disabled button | same fill, white label at 40% |

Header structure: chevron, refresh symbol (`arrow.counterclockwise`), title "Reset manuale", trailing count — all in the header gray, not `.secondary`. Future UI work for this section changes the Swift tokens only when the Figma component changes; the component is checked via the Figma MCP tools, not from memory.

Native controls stay native: no custom progress-bar or button replacements to work around color inheritance.

## Consequences

- Quota bar semantics remain stable regardless of what else is added to the popover.
- Tint-affecting controls require runtime popover inspection as part of verification, not just test suites.
- Design changes to the manual reset section start in Figma and flow one-way into `ManualResetDesignToken`.
- Reviewers should treat "unchanged view code" as insufficient evidence that visuals are unchanged when environment-sensitive modifiers were added elsewhere in the hierarchy.
