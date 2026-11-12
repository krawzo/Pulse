#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
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
    return EXIT_FAILURE;
  }

  // Center the actual DPI-scaled window in the monitor work area before the
  // first Flutter frame makes it visible.
  const HWND handle = window.GetHandle();
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
  return EXIT_SUCCESS;
}
