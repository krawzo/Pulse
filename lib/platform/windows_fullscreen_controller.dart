import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Switches the app window to the full monitor area and restores its exact
/// previous Windows placement (including maximized state) when leaving.
class WindowsFullscreenController {
  HWND? _window;
  int? _originalStyle;
  Pointer<WINDOWPLACEMENT>? _originalPlacement;
  int? _originalLeft;
  int? _originalTop;
  int? _originalWidth;
  int? _originalHeight;
  bool _wasMaximized = false;

  bool get isActive => _window != null;

  bool enter() {
    if (!Platform.isWindows || isActive) return true;

    final window = GetActiveWindow();
    if (window == HWND(nullptr)) return false;

    final styleResult = GetWindowLongPtr(window, GWL_STYLE);
    if (styleResult.value == 0 && styleResult.error != WIN32_ERROR(0)) {
      return false;
    }

    final placement = calloc<WINDOWPLACEMENT>();
    placement.ref.length = sizeOf<WINDOWPLACEMENT>();
    if (!GetWindowPlacement(window, placement).value) {
      calloc.free(placement);
      return false;
    }

    final originalRect = calloc<RECT>();
    if (!GetWindowRect(window, originalRect).value) {
      calloc.free(originalRect);
      calloc.free(placement);
      return false;
    }

    final monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    final monitorInfo = calloc<MONITORINFO>();
    monitorInfo.ref.cbSize = sizeOf<MONITORINFO>();
    if (monitor == HMONITOR(nullptr) || !GetMonitorInfo(monitor, monitorInfo)) {
      calloc.free(monitorInfo);
      calloc.free(originalRect);
      calloc.free(placement);
      return false;
    }

    final bounds = monitorInfo.ref.rcMonitor;
    final originalStyle = styleResult.value;
    final fullscreenStyle = (originalStyle & ~WS_OVERLAPPEDWINDOW) | WS_POPUP;

    final styleChanged =
        SetWindowLongPtr(window, GWL_STYLE, fullscreenStyle).error ==
            WIN32_ERROR(0);
    final positioned = styleChanged &&
        SetWindowPos(
          window,
          HWND_TOP,
          bounds.left,
          bounds.top,
          bounds.right - bounds.left,
          bounds.bottom - bounds.top,
          SWP_FRAMECHANGED | SWP_SHOWWINDOW | SWP_NOOWNERZORDER,
        ).value;

    calloc.free(monitorInfo);
    if (!positioned) {
      SetWindowLongPtr(window, GWL_STYLE, originalStyle);
      SetWindowPlacement(window, placement);
      SetWindowPos(
        window,
        null,
        0,
        0,
        0,
        0,
        SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOACTIVATE,
      );
      calloc.free(originalRect);
      calloc.free(placement);
      return false;
    }

    _window = window;
    _originalStyle = originalStyle;
    _originalPlacement = placement;
    _originalLeft = originalRect.ref.left;
    _originalTop = originalRect.ref.top;
    _originalWidth = originalRect.ref.right - originalRect.ref.left;
    _originalHeight = originalRect.ref.bottom - originalRect.ref.top;
    _wasMaximized = placement.ref.showCmd == SW_SHOWMAXIMIZED;
    calloc.free(originalRect);
    return true;
  }

  void exit() {
    final window = _window;
    final originalStyle = _originalStyle;
    final placement = _originalPlacement;
    if (window == null || originalStyle == null || placement == null) return;

    SetWindowLongPtr(window, GWL_STYLE, originalStyle);
    // Recalculate the non-client frame before Windows restores the saved
    // placement. Otherwise a maximized window can retain fullscreen bounds
    // and extend beneath the taskbar after Escape.
    SetWindowPos(
      window,
      null,
      0,
      0,
      0,
      0,
      SWP_FRAMECHANGED |
          SWP_NOMOVE |
          SWP_NOSIZE |
          SWP_NOZORDER |
          SWP_NOACTIVATE,
    );
    if (_wasMaximized) {
      ShowWindow(window, SW_RESTORE);
      SetWindowPlacement(window, placement);
      ShowWindow(window, SW_SHOWMAXIMIZED);
    } else {
      ShowWindow(window, SW_RESTORE);
      SetWindowPlacement(window, placement);
      final width = _originalWidth ?? 0;
      final height = _originalHeight ?? 0;
      if (width > 0 && height > 0) {
        SetWindowPos(
          window,
          null,
          _originalLeft ?? 0,
          _originalTop ?? 0,
          width,
          height,
          SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW,
        );
      } else {
        SetWindowPos(
          window,
          null,
          0,
          0,
          1280,
          720,
          SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOACTIVATE | SWP_SHOWWINDOW,
        );
      }
    }
    SetWindowPos(
      window,
      null,
      0,
      0,
      0,
      0,
      SWP_FRAMECHANGED |
          SWP_NOMOVE |
          SWP_NOSIZE |
          SWP_NOZORDER |
          SWP_NOACTIVATE,
    );
    calloc.free(placement);
    _window = null;
    _originalStyle = null;
    _originalPlacement = null;
    _originalLeft = null;
    _originalTop = null;
    _originalWidth = null;
    _originalHeight = null;
    _wasMaximized = false;
  }
}
