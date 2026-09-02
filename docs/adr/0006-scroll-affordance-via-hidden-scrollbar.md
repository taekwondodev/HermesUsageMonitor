# ADR-0006: Popover hides its scroll bar; scrollability via clipped content edge

- Status: Accepted
- Date: 2026-08-23

## Context

The popover renders its subscription cards inside a single vertical `ScrollView`. On this
machine the macOS overlay scroll bar was rendered persistently: the mouse-driven system does
not auto-hide overlay scrollers, and because the content always exceeds the popover maximum
height, the bar was always present and sat on the right-hand card content (the reset-countdown
and metric column). A first attempt to clear a "scrollbar gutter" with
`contentMargins(_:for: .scrollContent)` did not work.

During grilling the user asked for Apple-style behaviour: no lingering scroll bar, and
content that keeps an even margin from the window edge. Hiding the bar entirely is the only
app-side way to guarantee it never lingers, because on this system SwiftUI's default
`.automatic` indicators stay visible; the app cannot force on-demand overlay scrollers on
macOS.

## Decision

- Hide the scroll bar with `.scrollIndicators(.never)`. Scrollability is signalled by the
  clipped last card at the bottom edge, the affordance the macOS HIG recommends when a scroll
  bar is not shown.
- The content keeps a uniform, symmetric 16pt padding from the window edge on all sides
  (the popover's existing `.padding(16)` around the `ScrollView`). No dedicated trailing
  gutter or asymmetric margin is used.
- Do not use `contentMargins(_:for: .scrollContent)` to position scroll chrome. That modifier
  moves the overlay scroll bar together with the content: both shift left by the inset, so it
  can never create separation between a scroll bar and the content. Pixel measurement of the
  installed popover confirmed the scroll bar shifted left by exactly the inset (16pt).

### Why `.never` and not `.hidden` (revisited 2026-09-02)

The original decision used `.scrollIndicators(.hidden)`, and the popover still showed a
persistent vertical scroll bar at rest. Instrumented runs of the real menu-bar panel logged
the hosting `ScrollView` switching `hasVerticalScroller` back to `true` the moment the user
scrolled, with `scrollerStyle == .legacy`. SwiftUI's `.hidden` is pointer-device aware on
macOS: when a mouse (rather than only a trackpad) is connected, indicators return. That is
exactly this machine's setup, so `.hidden` could never hold the bar off. `.never` hides the
indicators regardless of the connected pointing device.

Switching the value to `.never` fixed both symptoms: no scroll bar at rest, and no scroll
bar (and therefore no width reflow of the cards) while actually scrolling. An AppKit
workaround that walked the window's view tree to force `hasVerticalScroller = false` was
tried first and only suppressed the bar until the next scroll re-enabled it; it is not
needed once `.never` is used.

### Verification

A standalone SwiftUI harness reproducing the exact modifier chain was measured with overlay
scroll bars in a real macOS render. The result evidences the `contentMargins` trap rather
than a final layout value:

| Variant | Card right edge | Scroll bar | Gap |
| --- | --- | --- | --- |
| base (no inset) | ~347 pt | ~350-360 pt | ~3 pt |
| content padding 16pt | ~330 pt | ~350-360 pt | ~20 pt (scroll bar stays at the edge) |
| `contentMargins(for: .scrollContent)` | ~330 pt | ~334-344 pt | ~4 pt (scroll bar followed content) |

The final state hides the scroll bar and uses a uniform margin, so the gap is cosmetic; the
harness table is retained as the record of why `contentMargins` is ruled out. `make test`
passes. cua-driver cannot enumerate the menu-bar `NSPopover` window in this environment, so
the final popover check is manual.

## Consequences

- The popover never shows a scroll bar; a clipped row at the bottom signals scrollability.
- The content uses a symmetric 16pt margin from the window edge; there is no scroll widget to
  reserve space for.
- The `contentMargins(_:for: .scrollContent)` trap is ruled out for every future scrollable
  surface in the app, not just the popover.