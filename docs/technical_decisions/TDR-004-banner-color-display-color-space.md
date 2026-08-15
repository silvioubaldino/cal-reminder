---
id: TDR-004
type: tdr
title: Paint the Banner in the display's color space
status: accepted
updated: 2026-08-15
parents: [SPEC-014]
related: [AYD-006, REQ-01]
superseded_by: null
---

# TDR-004: Paint the Banner in the display's color space

> Append-only: never rewrite. A new decision = a new TDR that supersedes this one
> (`superseded_by`).

## Context
SPEC-014 paints the Banner with the Event's Calendar Color (RF-13), parsed from the hex the
Google Calendar API returns. Side by side with Google Calendar, the Banner came out
recognizably the same color but in a **slightly different tone** — a bit more saturated.

The cause is color management, not the value: a Calendar Color hex is defined in **sRGB**,
while Macs since 2016 ship **Display P3** screens. A browser color-manages the CSS color and
converts sRGB → P3 before drawing, so Google Calendar shows the intended tone. Handing the
raw sRGB components to a `CALayer`'s `backgroundColor` can instead paint them as native
display values — the same numbers in a wider gamut, which reads as oversaturated. The Banner
is drawn entirely by layers (`AirplaneBannerView`), so it never went through the
color-managed drawing path an `NSView.draw(_:)` would have used.

## Decision
`DefaultOverlayAnimator` converts both the Banner background and the Banner text color into
the color space of the `NSScreen` the Overlay is about to be shown on
(`NSColor.matchingDisplayColorSpace(_:)`) before handing them to the view.

This is correct regardless of how the compositor treats the color: a color already expressed
in the display's space converts to itself, so the conversion is either the fix or a no-op —
never a second, wrong transform. When the screen reports no color space, the color is passed
through unchanged.

The semantic color stays sRGB everywhere else: `Trigger` carries the hex, and
`bannerBackgroundColor(for:)` still resolves the Calendar-Color-vs-preset rule in sRGB.
Only the last step — handing a color to a layer — is display-matched, which keeps the
resolution rule testable without a real screen.

## Alternatives & trade-offs
- **Set the layer's / window's color space explicitly instead.** Would fix the Banner, but
  spreads a rendering concern across `OverlayPanel` and every layer, and still leaves each
  color's own tagging ambiguous. Converting the two colors at the single point where they
  enter the view is smaller and local.
- **Draw the Banner in `NSView.draw(_:)` instead of layers.** AppKit's drawing path is
  color-managed for free, but the flight is a Core Animation animation — moving to manual
  drawing would trade a one-line conversion for a redraw-per-frame rewrite.
- **Pre-convert the hex to P3 numbers at parse time.** Bakes one display's gamut into the
  domain value; a second screen with a different profile would then be wrong.
