#include "flutter_window.h"

#include <optional>
#include <dwmapi.h>
#include <propkey.h>
#include <functiondiscoverykeys_devpkey.h>
#include <mmdeviceapi.h>
#include <propvarutil.h>
#include <shellapi.h>
#include <string>
#include <variant>
#include <vector>

#include "flutter/generated_plugin_registrant.h"
#include "resource.h"

namespace {
constexpr UINT kTrayCallbackMessage = WM_APP + 1;
constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayOpenCommand = 1001;
constexpr UINT kTrayExitCommand = 1002;

struct AccentPolicy {
  int state;
  int flags;
  DWORD color;
  int animation;
};

struct WindowCompositionAttributeData {
  int attribute;
  void* data;
  SIZE_T size;
};

using SetWindowCompositionAttribute = BOOL(WINAPI*)(
    HWND, WindowCompositionAttributeData*);

bool SetGlassBackdrop(HWND window, bool enabled) {
  const auto user32 = GetModuleHandleW(L"user32.dll");
  if (user32 == nullptr) return false;
  const auto set_attribute = reinterpret_cast<SetWindowCompositionAttribute>(
      GetProcAddress(user32, "SetWindowCompositionAttribute"));
  if (set_attribute == nullptr) return false;

  // Remove the Windows 11 system tint so the adjustable acrylic tint is used.
  const int backdrop_none = 1;
  DwmSetWindowAttribute(window, 38, &backdrop_none, sizeof(backdrop_none));
  AccentPolicy accent{enabled ? 4 : 0, 2,
                      enabled ? 0x18262C30u : 0u, 0};
  WindowCompositionAttributeData data{19, &accent, sizeof(accent)};
  return set_attribute(window, &data) != FALSE;
}

std::optional<std::string> GetDefaultAudioOutputName() {
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  if (FAILED(initialized) && initialized != RPC_E_CHANGED_MODE) return std::nullopt;

  IMMDeviceEnumerator* enumerator = nullptr;
  IMMDevice* endpoint = nullptr;
  IPropertyStore* properties = nullptr;
  PROPVARIANT name;
  PropVariantInit(&name);
  std::optional<std::string> output;

  HRESULT result = CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                    CLSCTX_ALL, __uuidof(IMMDeviceEnumerator),
                                    reinterpret_cast<void**>(&enumerator));
  if (SUCCEEDED(result)) {
    result = enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &endpoint);
  }
  if (SUCCEEDED(result)) result = endpoint->OpenPropertyStore(STGM_READ, &properties);
  if (SUCCEEDED(result)) result = properties->GetValue(PKEY_Device_FriendlyName, &name);
  if (SUCCEEDED(result) && name.vt == VT_LPWSTR && name.pwszVal != nullptr) {
    const int size = WideCharToMultiByte(CP_UTF8, 0, name.pwszVal, -1,
                                         nullptr, 0, nullptr, nullptr);
    if (size > 1) {
      std::vector<char> utf8(size);
      WideCharToMultiByte(CP_UTF8, 0, name.pwszVal, -1, utf8.data(),
                          size, nullptr, nullptr);
      output = std::string(utf8.data());
    }
  }

  PropVariantClear(&name);
  if (properties != nullptr) properties->Release();
  if (endpoint != nullptr) endpoint->Release();
  if (enumerator != nullptr) enumerator->Release();
  if (SUCCEEDED(initialized)) CoUninitialize();
  return output;
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  taskbar_created_message_ = RegisterWindowMessageW(L"TaskbarCreated");
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "pulse/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "setCloseToMinimize") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          if (enabled != nullptr) {
            close_to_minimize_ = *enabled;
            SetCloseToMinimize(*enabled);
            result->Success();
          } else {
            result->Error("invalid_arguments", "Expected a boolean value.");
          }
        } else if (call.method_name() == "getAudioOutput") {
          const auto name = GetDefaultAudioOutputName();
          if (name.has_value()) {
            result->Success(flutter::EncodableValue(*name));
          } else {
            result->Success();
          }
        } else if (call.method_name() == "setGlassBackdrop") {
          const auto* enabled = std::get_if<bool>(call.arguments());
          if (enabled == nullptr) {
            result->Error("invalid_arguments", "Expected a boolean value.");
          } else if (SetGlassBackdrop(GetHandle(), *enabled)) {
            result->Success();
          } else {
            result->Error("unsupported", "Windows acrylic is unavailable.");
          }
        } else if (call.method_name() == "quit") {
          close_to_minimize_ = false;
          SetCloseToMinimize(false);
          result->Success();
          PostMessage(GetHandle(), WM_CLOSE, 0, 0);
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  RemoveTrayIcon(GetHandle());
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::MinimizeToTray(HWND window) {
  if (!tray_icon_added_) {
    NOTIFYICONDATAW icon{};
    icon.cbSize = sizeof(icon);
    icon.hWnd = window;
    icon.uID = kTrayIconId;
    icon.uFlags = NIF_MESSAGE | NIF_ICON | NIF_TIP;
    icon.uCallbackMessage = kTrayCallbackMessage;
    icon.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
    if (icon.hIcon == nullptr) {
      icon.hIcon = LoadIconW(nullptr, IDI_APPLICATION);
    }
    lstrcpynW(icon.szTip, L"Pulse", ARRAYSIZE(icon.szTip));
    if (!Shell_NotifyIconW(NIM_ADD, &icon)) {
      return false;
    }
    tray_restore_maximized_ = IsZoomed(window) != FALSE;
    tray_icon_added_ = true;
  }
  ShowWindow(window, SW_HIDE);
  return true;
}

void FlutterWindow::RemoveTrayIcon(HWND window) {
  if (!tray_icon_added_ || window == nullptr) return;
  NOTIFYICONDATAW icon{};
  icon.cbSize = sizeof(icon);
  icon.hWnd = window;
  icon.uID = kTrayIconId;
  Shell_NotifyIconW(NIM_DELETE, &icon);
  tray_icon_added_ = false;
}

void FlutterWindow::RestoreFromTray(HWND window) {
  RemoveTrayIcon(window);
  ShowWindow(window, tray_restore_maximized_ ? SW_SHOWMAXIMIZED : SW_RESTORE);
  SetForegroundWindow(window);
}

void FlutterWindow::ShowTrayMenu(HWND window) {
  HMENU menu = CreatePopupMenu();
  if (menu == nullptr) return;
  AppendMenuW(menu, MF_STRING, kTrayOpenCommand, L"Abrir Pulse");
  AppendMenuW(menu, MF_STRING, kTrayExitCommand, L"Sair do Pulse");
  POINT cursor{};
  GetCursorPos(&cursor);
  SetForegroundWindow(window);
  const UINT choice = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_RIGHTBUTTON | TPM_NONOTIFY, cursor.x,
      cursor.y, 0, window, nullptr);
  DestroyMenu(menu);
  PostMessage(window, WM_NULL, 0, 0);
  if (choice == kTrayOpenCommand) {
    RestoreFromTray(window);
  } else if (choice == kTrayExitCommand) {
    close_to_minimize_ = false;
    SetCloseToMinimize(false);
    PostMessage(window, WM_CLOSE, 0, 0);
  }
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (taskbar_created_message_ != 0 &&
      message == taskbar_created_message_ && tray_icon_added_) {
    tray_icon_added_ = false;
    MinimizeToTray(hwnd);
    return 0;
  }
  if (message == kTrayCallbackMessage) {
    if (lparam == WM_LBUTTONUP || lparam == WM_LBUTTONDBLCLK) {
      RestoreFromTray(hwnd);
    } else if (lparam == WM_RBUTTONUP || lparam == WM_CONTEXTMENU) {
      ShowTrayMenu(hwnd);
    }
    return 0;
  }
  if (message == WM_CLOSE && close_to_minimize_) {
    if (!MinimizeToTray(hwnd)) ShowWindow(hwnd, SW_MINIMIZE);
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
