# Fix RenderFlex overflow in _ReceiverTargetCard

The `_ReceiverTargetCard` (specifically the inner `Row` at line 684) overflows because it tries to fit a name and several status badges into a limited horizontal space. On narrow screens or when many badges are active, the combined width of non-expanded children exceeds the available width.

## Proposed Changes

### [MODIFY] [_ReceiverTargetCard in host_view.dart](file:///Users/tdevs/Desktop/Projects/Others/Sync Audio/sync_audio/lib/features/host/views/host_view.dart)

- Add `overflow: TextOverflow.ellipsis` to the `_displayName` Text widget to ensure the name truncates instead of pushing other widgets out.
- Remove the redundant `Text(_signalLabel())` widget. This information is already conveyed by `_PresenceBadge` ("Online"/"Offline") and `ReceiverNetworkQualityBadge` ("Excellent"/"Fair"/"Poor").
- Reduce the spacing between badges to save more horizontal space.
- Wrap the trailing badges in a `Row` with `mainAxisSize: MainAxisSize.min` (optional, for clarity).

## Verification Plan

### Manual Verification
- Resize the window or use a small device emulator to verify that the `ReceiverCard` no longer shows the yellow/black overflow stripes.
- Verify that long receiver names are correctly truncated with an ellipsis.
- Ensure all essential status information (Online/Offline, Signal strength icon, Network quality) is still visible.
