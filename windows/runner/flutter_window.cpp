#include "flutter_window.h"

#include <commctrl.h>
#include <flutter/standard_method_codec.h>

#include <optional>
#include <string>
#include <variant>

#include "flutter/generated_plugin_registrant.h"

namespace {

// HomeTunes (0.1.18): keeps Flutter's accessibility (screen reader) layer switched off.
//
// Flutter switches its accessibility tree on as soon as any program asks the window what's on
// screen (WM_GETOBJECT). On some PCs something always asks (security or desktop tools), and
// Flutter's Windows accessibility bridge then gets confused when parts of the tree move to a new
// parent (the Home page's lists do this while the library loads): it logs "Failed to update
// ui::AXTree ... will not be in the tree" and a later update (e.g. moving the window) crashes
// in flutter_windows.dll (access violation at +0x3c16a in Flutter 3.47.5). Every HomeTunes crash
// on record was this one. Answering WM_GETOBJECT ourselves with the standard window object
// means the engine never builds that tree. Start HomeTunes with --screen-reader to turn it back
// on (e.g. for Narrator), accepting the risk.
LRESULT CALLBACK KeepAccessibilityOff(HWND hwnd, UINT message, WPARAM wparam,
                                      LPARAM lparam, UINT_PTR id, DWORD_PTR) {
  if (message == WM_GETOBJECT) {
    return DefWindowProc(hwnd, message, wparam, lparam);
  }
  if (message == WM_NCDESTROY) {
    RemoveWindowSubclass(hwnd, KeepAccessibilityOff, id);
  }
  return DefSubclassProc(hwnd, message, wparam, lparam);
}

bool ScreenReaderRequested() {
  const std::wstring command_line = GetCommandLineW();
  return command_line.find(L"--screen-reader") != std::wstring::npos;
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

  // HomeTunes (0.1.60): "Always on top" (the pin button, lib/services/window_pin.dart).
  // setAlwaysOnTop(true / false) puts this window above other windows, or lets it go behind
  // them again, without moving, resizing or focusing it.
  window_channel_ = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      flutter_controller_->engine()->messenger(), "hometunes/window",
      &flutter::StandardMethodCodec::GetInstance());
  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setAlwaysOnTop") {
          result->NotImplemented();
          return;
        }
        const auto* on = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
        if (on == nullptr) {
          result->Error("bad-argument", "Expected true or false");
          return;
        }
        ::SetWindowPos(GetHandle(), *on ? HWND_TOPMOST : HWND_NOTOPMOST, 0, 0, 0, 0,
                       SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE);
        result->Success(flutter::EncodableValue(*on));
      });

  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  if (!ScreenReaderRequested()) {
    SetWindowSubclass(flutter_controller_->view()->GetNativeWindow(),
                      KeepAccessibilityOff, 1, 0);
  }

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
  window_channel_ = nullptr;  // before the engine it talks through
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
