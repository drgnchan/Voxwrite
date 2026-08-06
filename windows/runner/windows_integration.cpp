#include "windows_integration.h"

#include <windows.h>

#include <flutter/encodable_value.h>
#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <cstring>
#include <memory>
#include <string>

namespace {

std::wstring Utf8ToWide(const std::string& value) {
  if (value.empty()) return std::wstring();
  const int size = MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                                       static_cast<int>(value.size()), nullptr,
                                       0);
  std::wstring result(size, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.c_str(),
                      static_cast<int>(value.size()), result.data(), size);
  return result;
}

bool PutTextOnClipboard(const std::string& text) {
  const std::wstring wide = Utf8ToWide(text);
  if (!OpenClipboard(nullptr)) return false;
  EmptyClipboard();
  const SIZE_T bytes = (wide.size() + 1) * sizeof(wchar_t);
  HGLOBAL memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
  if (!memory) {
    CloseClipboard();
    return false;
  }
  void* destination = GlobalLock(memory);
  std::memcpy(destination, wide.c_str(), bytes);
  GlobalUnlock(memory);
  if (!SetClipboardData(CF_UNICODETEXT, memory)) {
    GlobalFree(memory);
    CloseClipboard();
    return false;
  }
  CloseClipboard();
  return true;
}

void FocusWindow(HWND window) {
  if (!window || !IsWindow(window)) return;
  const DWORD target_thread = GetWindowThreadProcessId(window, nullptr);
  const DWORD current_thread = GetCurrentThreadId();
  if (target_thread != current_thread) {
    AttachThreadInput(current_thread, target_thread, TRUE);
  }
  ShowWindow(window, SW_RESTORE);
  SetForegroundWindow(window);
  SetFocus(window);
  if (target_thread != current_thread) {
    AttachThreadInput(current_thread, target_thread, FALSE);
  }
}

void SendPasteShortcut() {
  INPUT inputs[4] = {};
  inputs[0].type = INPUT_KEYBOARD;
  inputs[0].ki.wVk = VK_CONTROL;
  inputs[1].type = INPUT_KEYBOARD;
  inputs[1].ki.wVk = 'V';
  inputs[2].type = INPUT_KEYBOARD;
  inputs[2].ki.wVk = 'V';
  inputs[2].ki.dwFlags = KEYEVENTF_KEYUP;
  inputs[3].type = INPUT_KEYBOARD;
  inputs[3].ki.wVk = VK_CONTROL;
  inputs[3].ki.dwFlags = KEYEVENTF_KEYUP;
  SendInput(4, inputs, sizeof(INPUT));
}

}  // namespace

class WindowsIntegration::Impl {
 public:
  explicit Impl(flutter::BinaryMessenger* messenger) {
    shortcut_channel_ =
        std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
            messenger, "dev.raymond.voxwrite/shortcuts",
            &flutter::StandardMethodCodec::GetInstance());
    auto handler = std::make_unique<flutter::StreamHandlerFunctions<>>(
        [this](const flutter::EncodableValue*,
               std::unique_ptr<flutter::EventSink<>>&& events) {
          event_sink_ = std::move(events);
          StartHook();
          return std::unique_ptr<flutter::StreamHandlerError<>>();
        },
        [this](const flutter::EncodableValue*) {
          StopHook();
          event_sink_.reset();
          return std::unique_ptr<flutter::StreamHandlerError<>>();
        });
    shortcut_channel_->SetStreamHandler(std::move(handler));

    text_channel_ =
        std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
            messenger, "dev.raymond.voxwrite/text_destination",
            &flutter::StandardMethodCodec::GetInstance());
    text_channel_->SetMethodCallHandler(
        [this](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                   result) { HandleTextCall(call, std::move(result)); });
  }

  ~Impl() { StopHook(); }

 private:
  static Impl* active_instance_;

  static LRESULT CALLBACK KeyboardHook(int code, WPARAM wparam,
                                       LPARAM lparam) {
    if (code == HC_ACTION && active_instance_) {
      const auto* event = reinterpret_cast<KBDLLHOOKSTRUCT*>(lparam);
      active_instance_->HandleKeyboardEvent(wparam, event->vkCode);
    }
    return CallNextHookEx(nullptr, code, wparam, lparam);
  }

  void StartHook() {
    if (hook_) return;
    active_instance_ = this;
    hook_ = SetWindowsHookEx(WH_KEYBOARD_LL, KeyboardHook,
                             GetModuleHandle(nullptr), 0);
  }

  void StopHook() {
    if (hook_) UnhookWindowsHookEx(hook_);
    hook_ = nullptr;
    if (active_instance_ == this) active_instance_ = nullptr;
    f8_down_ = false;
    selected_translation_ = false;
    selected_ask_ = false;
  }

  void HandleKeyboardEvent(WPARAM message, DWORD key) {
    const bool down = message == WM_KEYDOWN || message == WM_SYSKEYDOWN;
    const bool up = message == WM_KEYUP || message == WM_SYSKEYUP;
    if (key == VK_F8 && down && !f8_down_) {
      f8_down_ = true;
      selected_translation_ = false;
      selected_ask_ = false;
      Emit("fnDown");
      if (GetAsyncKeyState(VK_SHIFT) & 0x8000) SelectTranslation();
      if (GetAsyncKeyState(VK_CONTROL) & 0x8000) SelectAsk();
      return;
    }
    if (key == VK_F8 && up && f8_down_) {
      f8_down_ = false;
      Emit("fnUp");
      return;
    }
    if (!f8_down_ || !down) return;
    if (key == VK_LSHIFT || key == VK_RSHIFT || key == VK_SHIFT) {
      SelectTranslation();
    } else if (key == VK_SPACE || key == VK_CONTROL || key == VK_LCONTROL ||
               key == VK_RCONTROL) {
      SelectAsk();
    }
  }

  void SelectTranslation() {
    if (selected_translation_) return;
    selected_translation_ = true;
    Emit("selectTranslation");
  }

  void SelectAsk() {
    if (selected_ask_) return;
    selected_ask_ = true;
    Emit("selectAsk");
  }

  void Emit(const std::string& type) {
    if (!event_sink_) return;
    flutter::EncodableMap event;
    event[flutter::EncodableValue("type")] = flutter::EncodableValue(type);
    event_sink_->Success(flutter::EncodableValue(event));
  }

  void HandleTextCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
    if (call.method_name() == "captureTarget") {
      target_window_ = GetForegroundWindow();
      result->Success(flutter::EncodableValue(target_window_ != nullptr));
      return;
    }
    if (call.method_name() == "readSelection") {
      result->Success(flutter::EncodableValue());
      return;
    }
    if (call.method_name() == "clearTarget") {
      target_window_ = nullptr;
      result->Success();
      return;
    }
    if (call.method_name() == "insertText") {
      const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
      if (!arguments) {
        result->Error("INVALID_TEXT", "insertText requires arguments");
        return;
      }
      const auto iterator = arguments->find(flutter::EncodableValue("text"));
      if (iterator == arguments->end()) {
        result->Error("INVALID_TEXT", "insertText requires text");
        return;
      }
      const auto* text = std::get_if<std::string>(&iterator->second);
      if (!text || !target_window_ || !IsWindow(target_window_)) {
        result->Success(flutter::EncodableValue(false));
        return;
      }
      if (!PutTextOnClipboard(*text)) {
        result->Success(flutter::EncodableValue(false));
        return;
      }
      FocusWindow(target_window_);
      Sleep(120);
      SendPasteShortcut();
      target_window_ = nullptr;
      result->Success(flutter::EncodableValue(true));
      return;
    }
    result->NotImplemented();
  }

  HHOOK hook_ = nullptr;
  HWND target_window_ = nullptr;
  bool f8_down_ = false;
  bool selected_translation_ = false;
  bool selected_ask_ = false;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> event_sink_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>>
      shortcut_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> text_channel_;
};

WindowsIntegration::Impl* WindowsIntegration::Impl::active_instance_ = nullptr;

WindowsIntegration::WindowsIntegration(flutter::BinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(messenger)) {}

WindowsIntegration::~WindowsIntegration() = default;
