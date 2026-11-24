#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

namespace {
constexpr wchar_t kPulseMutexName[] = L"Local\\PulseMusicPlayer.SingleInstance";
constexpr wchar_t kPulseWindowProperty[] = L"PulseMusicPlayer.SingleInstanceWindow";
constexpr UINT kPulseActivateMessage = WM_APP + 10;

HWND FindPulseWindow() {
  HWND found = nullptr;
  EnumWindows(
      [](HWND window, LPARAM context) -> BOOL {
        if (GetPropW(window, kPulseWindowProperty) == nullptr) return TRUE;
        *reinterpret_cast<HWND*>(context) = window;
        return FALSE;
      },
      reinterpret_cast<LPARAM>(&found));
  return found;
}
}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  const HANDLE single_instance = CreateMutexW(nullptr, TRUE, kPulseMutexName);
  if (single_instance == nullptr) return EXIT_FAILURE;
  if (GetLastError() == ERROR_ALREADY_EXISTS) {
    // The first process may still be creating its window.
    for (int attempt = 0; attempt < 100; ++attempt) {
      if (const HWND existing = FindPulseWindow(); existing != nullptr) {
        DWORD process_id = 0;
        GetWindowThreadProcessId(existing, &process_id);
        if (process_id != 0) AllowSetForegroundWindow(process_id);
        PostMessageW(existing, kPulseActivateMessage, 0, 0);
        break;
      }
      Sleep(100);
    }
    CloseHandle(single_instance);
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  const auto startup_argument = std::find(command_line_arguments.begin(),
                                          command_line_arguments.end(),
                                          "--pulse-startup-minimized");
  const bool start_minimized = startup_argument != command_line_arguments.end();
  if (start_minimized) {
    command_line_arguments.erase(startup_argument);
  }

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  if (start_minimized) {
    window.SetInitialShowCommand(SW_SHOWMINIMIZED);
  }
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Pulse", origin, size)) {
    ReleaseMutex(single_instance);
    CloseHandle(single_instance);
    return EXIT_FAILURE;
  }

  // Center the actual DPI-scaled window in the monitor work area before the
  // first Flutter frame makes it visible.
  const HWND handle = window.GetHandle();
  SetPropW(handle, kPulseWindowProperty, reinterpret_cast<HANDLE>(1));
  RECT window_bounds{};
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(monitor_info);
  const HMONITOR monitor = MonitorFromWindow(handle, MONITOR_DEFAULTTONEAREST);
  if (GetWindowRect(handle, &window_bounds) && monitor != nullptr &&
      GetMonitorInfo(monitor, &monitor_info)) {
    const int width = window_bounds.right - window_bounds.left;
    const int height = window_bounds.bottom - window_bounds.top;
    const int x = monitor_info.rcWork.left +
                  (monitor_info.rcWork.right - monitor_info.rcWork.left -
                   width) /
                      2;
    const int y = monitor_info.rcWork.top +
                  (monitor_info.rcWork.bottom - monitor_info.rcWork.top -
                   height) /
                      2;
    SetWindowPos(handle, nullptr, x, y, 0, 0,
                 SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE);
  }

  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  ReleaseMutex(single_instance);
  CloseHandle(single_instance);
  return EXIT_SUCCESS;
}
