# CoreText Interaction

`CoreTextPageView` owns paged CoreText interaction:

- image taps
- internal/external link taps
- long-press text selection
- selection handle dragging
- underline bookmark requests
- playback highlight overlays

The page view creates an `InteractionContext` from the same `CTFrame` used for
rendering. Horizontal and vertical pages share the gesture pipeline but use
different geometry.

## Links

Link attributes are stored with `HTMLAttributedStringBuilder.internalLinkAttribute`.
On tap:

1. `CoreTextPageView` maps the touch point to a string index.
2. It reads the link attribute at that index.
3. `CoreTextPageEngine.configuredPageViewController` resolves internal EPUB
   links with `resolveInternalLink(_:fromSpineIndex:)`.
4. External URLs are opened through `UIApplication`.

Vertical link hit-testing uses column x bounds plus inline advance from the
column top. This lets sideways Latin links such as `PDF`, `BookDNA`, or email
addresses remain tappable in vertical-rl pages.

## Selection and Underlines

Selection uses `TextSelectionManager` for range state. Geometry comes from
`selectionRects(for:in:)`:

- horizontal mode returns horizontal text rects
- vertical mode returns column-local vertical rects using `CTLineGetOffsetForStringIndex`

Underline bookmarks are stored as `CoreTextTextAnnotation` ranges and redrawn by
`InteractionOverlayView`.

In vertical mode, underline strokes are vertical side lines instead of horizontal
bottom lines.

## Existing Caveats

- Scroll-mode `CoreTextChunk` has its own selection geometry and currently
  remains horizontal-only.
- Selection handles work in vertical mode through the shared pipeline, but their
  visual placement is intentionally simple and based on the first/last selection
  rect corners.
