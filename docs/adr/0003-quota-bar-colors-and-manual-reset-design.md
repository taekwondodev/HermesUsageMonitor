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

Exact values implemented in `ManualResetSection` + `ManualResetDesignToken`:

| Element | Value |
| --- | --- |
| Header text (title, icon, trailing count) | `Label(...).font(.caption.weight(.semibold))` + `.secondary`, same as "Uso osservato da Hermes" header |
| Expanded content surface | `Color.primary.opacity(0.06)`, matches the "Uso osservato da Hermes" accounting blocks in `AccountingSection` |
| Primary label ("Full reset disponibile") | `.font(.caption.weight(.semibold))`, default primary — same as the accounting model label |
| Applicability / expiration labels | `.font(.caption2)` + `.secondary` — same secondary line style as accounting |
| Stale label ("Non aggiornato") | `.caption2` + `.orange` |
| Redeem button | green `#30D158` (0.188, 0.820, 0.345), white label |
| Disabled button | same fill, white label at 40% |
| Expanded content insets | `.vertical` 6, `.horizontal` 8 — same as accounting blocks |

The card uses the **same fonts, sizes, and colors as the accounting card** (`AccountingDetail`): a `.caption.weight(.semibold)` primary label, `.caption2` `.secondary` secondary lines, the identical `Color.primary.opacity(0.06)` rounded-8 surface, and the same 6/8 insets. The original `ManualResetDesignToken` color/font overrides (custom `Color.white`, `#8E8E93`, custom text tokens) were removed so the two cards share one typographic language. The app does not force a color scheme, and all card text uses adaptive semantic colors, so it stays legible in both appearances.

The expanded card content is a single horizontal row — the Figma `flex items-center justify-between` contract: the information block on the left and the Riscatta button vertically centered on the right. This keeps the button horizontally aligned with the text instead of dropping below the fold into its own row.

The manual reset card and its disclosure header carry the **same colors, spacing, and left alignment as the "Uso osservato da Hermes" section**: the identical `Color.primary.opacity(0.06)` rounded-8 surface and insets, no extra leading indent on the expanded card, a header that is a `Label` with the SF symbol `arrow.counterclockwise` styled `.caption.weight(.semibold)` in `.secondary` (same treatment as the `umbrella.fill` header), and a disclosure chevron that is not separately tinted (the accounting section applies no tint either), so both chevrons render identically. The two expandable sections align to the same left edge inside the popover. The surface intentionally does not reproduce the literal Figma hex.

### Manual reset expansion state survives popover reopen

The `DisclosureGroup` expansion state for the manual reset section is **persisted across popover close/reopen**: opening the card, closing the popover, and reopening it restores the same expanded state (matching the behavior of the accounting section, which already persisted via `expandedSubscriptions`). The popover root no longer force-resets `isManualResetExpanded` to `false` on every `onAppear`.

Header structure: chevron, refresh symbol (`arrow.counterclockwise`), title "Reset manuale", trailing count — all styled to match the "Uso osservato da Hermes" header's `.secondary` treatment. Future UI work for this section changes the Swift tokens only when the Figma component changes; the component is checked via the Figma MCP tools, not from memory.

Native controls stay native: no custom progress-bar or button replacements to work around color inheritance.

## Consequences

- Quota bar semantics remain stable regardless of what else is added to the popover.
- Tint-affecting controls require runtime popover inspection as part of verification, not just test suites.
- Design changes to the manual reset section start in Figma and flow one-way into `ManualResetDesignToken`.
- Reviewers should treat "unchanged view code" as insufficient evidence that visuals are unchanged when environment-sensitive modifiers were added elsewhere in the hierarchy.
