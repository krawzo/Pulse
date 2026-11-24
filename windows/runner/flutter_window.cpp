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
constexpr UINT kPulseActivateMessage = WM_APP + 10;
constexpr UINT kTrayIconId = 1;
constexpr UINT kTrayOpenCommand = 1001;
constexpr UINT kTrayExitCommand = 1002;
constexpr UINT kTaskbarFavoriteCommand = 2001;
constexpr UINT kTaskbarPreviousCommand = 2002;
constexpr UINT kTaskbarPlayCommand = 2003;
constexpr UINT kTaskbarNextCommand = 2004;

bool ReadBool(const flutter::EncodableMap& values, const char* key,
              bool* output) {
  const auto found = values.find(flutter::EncodableValue(key));
  if (found == values.end()) return false;
  const auto* value = std::get_if<bool>(&found->second);
  if (value == nullptr) return false;
  *output = *value;
  return true;
}

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
  taskbar_button_created_message_ =
      RegisterWindowMessageW(L"TaskbarButtonCreated");
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
        } else if (call.method_name() == "setTaskbarPlayback") {
          const auto* values =
              std::get_if<flutter::EncodableMap>(call.arguments());
          bool has_track = false;
          bool is_playing = false;
          bool is_favorite = false;
          if (values == nullptr ||
              !ReadBool(*values, "hasTrack", &has_track) ||
              !ReadBool(*values, "isPlaying", &is_playing) ||
              !ReadBool(*values, "isFavorite", &is_favorite)) {
            result->Error("invalid_arguments", "Expected playback flags.");
          } else {
            taskbar_has_track_ = has_track;
            taskbar_is_playing_ = is_playing;
            taskbar_is_favorite_ = is_favorite;
            UpdateTaskbarButtons(GetHandle());
            result->Success();
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
  ResetTaskbarButtons();
  RemoveTrayIcon(GetHandle());
  window_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

void FlutterWindow::ResetTaskbarButtons() {
  taskbar_buttons_added_ = false;
  if (taskbar_ != nullptr) {
    taskbar_->Release();
    taskbar_ = nullptr;
  }
}

void FlutterWindow::AddTaskbarButtons(HWND window) {
  if (taskbar_buttons_added_) return;
  if (taskbar_ == nullptr) {
    if (FAILED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&taskbar_)))) {
      return;
    }
    if (FAILED(taskbar_->HrInit())) {
      ResetTaskbarButtons();
      return;
    }
  }
  THUMBBUTTON buttons[4]{};
  const UINT ids[] = {kTaskbarFavoriteCommand, kTaskbarPreviousCommand,
                      kTaskbarPlayCommand, kTaskbarNextCommand};
  const int icons[] = {IDI_TASKBAR_FAVORITE, IDI_TASKBAR_PREVIOUS,
                       IDI_TASKBAR_PLAY, IDI_TASKBAR_NEXT};
  const wchar_t* tips[] = {L"Adicionar aos favoritos", L"Faixa anterior",
                           L"Reproduzir", L"Proxima faixa"};
  for (int index = 0; index < 4; ++index) {
    buttons[index].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
    buttons[index].iId = ids[index];
    buttons[index].hIcon = LoadIconW(GetModuleHandleW(nullptr),
                                     MAKEINTRESOURCEW(icons[index]));
    lstrcpynW(buttons[index].szTip, tips[index],
             ARRAYSIZE(buttons[index].szTip));
    buttons[index].dwFlags = THBF_DISABLED;
  }
  if (SUCCEEDED(taskbar_->ThumbBarAddButtons(window, 4, buttons))) {
    taskbar_buttons_added_ = true;
    UpdateTaskbarButtons(window);
  }
}

void FlutterWindow::UpdateTaskbarButtons(HWND window) {
  if (!taskbar_buttons_added_ || taskbar_ == nullptr) return;
  THUMBBUTTON buttons[4]{};
  const UINT ids[] = {kTaskbarFavoriteCommand, kTaskbarPreviousCommand,
                      kTaskbarPlayCommand, kTaskbarNextCommand};
  const int icons[] = {
      taskbar_is_favorite_ ? IDI_TASKBAR_FAVORITE_ON : IDI_TASKBAR_FAVORITE,
      IDI_TASKBAR_PREVIOUS,
      taskbar_is_playing_ ? IDI_TASKBAR_PAUSE : IDI_TASKBAR_PLAY,
      IDI_TASKBAR_NEXT};
  const wchar_t* tips[] = {
      taskbar_is_favorite_ ? L"Remover dos favoritos"
                           : L"Adicionar aos favoritos",
      L"Faixa anterior", taskbar_is_playing_ ? L"Pausar" : L"Reproduzir",
      L"Proxima faixa"};
  for (int index = 0; index < 4; ++index) {
    buttons[index].dwMask = THB_ICON | THB_TOOLTIP | THB_FLAGS;
    buttons[index].iId = ids[index];
    buttons[index].hIcon = LoadIconW(GetModuleHandleW(nullptr),
                                     MAKEINTRESOURCEW(icons[index]));
    lstrcpynW(buttons[index].szTip, tips[index],
             ARRAYSIZE(buttons[index].szTip));
    buttons[index].dwFlags = taskbar_has_track_ ? THBF_ENABLED : THBF_DISABLED;
  }
  taskbar_->ThumbBarUpdateButtons(window, 4, buttons);
}

void FlutterWindow::SendTaskbarAction(const char* action) {
  if (window_channel_ == nullptr || !taskbar_has_track_) return;
  window_channel_->InvokeMethod(
      "taskbarAction",
      std::make_unique<flutter::EncodableValue>(std::string(action)));
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
  if (message == kPulseActivateMessage) {
    if (tray_icon_added_) {
      RestoreFromTray(hwnd);
    } else {
      ShowWindow(hwnd, IsIconic(hwnd) ? SW_RESTORE : SW_SHOW);
      SetForegroundWindow(hwnd);
    }
    return 0;
  }
  if (taskbar_button_created_message_ != 0 &&
      message == taskbar_button_created_message_) {
    AddTaskbarButtons(hwnd);
    return 0;
  }
  if (taskbar_created_message_ != 0 &&
      message == taskbar_created_message_) {
    ResetTaskbarButtons();
    if (tray_icon_added_) {
      tray_icon_added_ = false;
      MinimizeToTray(hwnd);
    }
    return 0;
  }
  if (message == WM_COMMAND && HIWORD(wparam) == THBN_CLICKED) {
    switch (LOWORD(wparam)) {
      case kTaskbarFavoriteCommand: SendTaskbarAction("favorite"); break;
      case kTaskbarPreviousCommand: SendTaskbarAction("previous"); break;
      case kTaskbarPlayCommand: SendTaskbarAction("playPause"); break;
      case kTaskbarNextCommand: SendTaskbarAction("next"); break;
    }
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
