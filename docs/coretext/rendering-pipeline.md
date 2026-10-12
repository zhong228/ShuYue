# CoreText Rendering Pipeline

## EPUB Path

1. `CoreTextPageEngine` asks the active `AttributedStringBuilding` implementation
   for a chapter.
2. `EPUBAttributedStringBuilder` resolves chapter HTML, CSS resources, embedded
   images, anchors, and background images.
3. `HTMLAttributedStringBuilder` builds a styled AST and renders it through
   `NodeAttributedStringRenderer`.
4. `CoreTextPaginator` normalizes the attributed string, paginates with
   `CTFramesetter`, extracts images/inline annotations/block renderables, and
   records `pageRanges`.
5. `CoreTextPageView` draws the page and handles taps, selection, image preview,
   playback highlights, and underline annotations.

## Two HTML Rendering Paths

Keep these in sync when changing CSS or RenderStyle fields:

| Path | Builder | Renderer |
| --- | --- | --- |
| Legacy HTML build | `HTMLAttributedStringBuilder.build()` | internally renders styled AST |
| Renderable node path | `buildStyledAST()` -> `HTMLStyledASTRenderableNodeConverter` | `NodeAttributedStringRenderer` |

Shared types include `ResolvedStyle`, `RenderStyle`, `CSSPropertyApplier`, and
`HTMLBuilderStyleResolver`.

## Layout-Affecting Inputs

`CoreTextPaginator.CacheKey` must include values that affect layout:

- string content and layout-affecting attributes
- writing mode
- render size and content insets
- font size, line spacing, paragraph spacing, letter spacing
- image/background inputs

If a change affects page count, visible geometry, or attributed run metrics, make
sure the cache key changes too.
