# List View Implementation Details

## Overview
The list view in `BoxPage` has been refined to provide robust column resizing and clear visual feedback.

## Columns & Resizing
All columns now use explicit widths managed by the parent widget state.
1.  **Name (名称)**: Min 100px, Max 500px. Defaults to filling available space but can be manually resized.
2.  **Date (修改日期)**: Resizable (80-300px).
3.  **Type (类型)**: Resizable (50-200px).
4.  **Size (大小)**: Resizable (50-200px).

## Improvements
-   **Unified Layout**: Uses `kHandleZoneWidth = 24.0` and `kSidePadding = 16.0` to ensure pixel-perfect alignment and zero overflow.
-   **Large Hit Area**: The resizing handle has a 24px wide invisible logic area for effortless dragging, with a visible 1px line at the center.
-   **Explicit Math**: `totalWidth` accurately includes all column widths, handles, and paddings.

## Implementation Details
-   `LayoutBuilder` calculates the available space for the `Name` column after subtracting fixed columns, handles, and padding.
-   `_BoxList` manages column state: `_nameWidth`, `_dateWidth`, `_typeWidth`, `_sizeWidth`.
-   Headers and ListItems share identical spacing logic to ensure vertical alignment.

## Future Improvements
-   Persist column widths.
-   Sort by column.
