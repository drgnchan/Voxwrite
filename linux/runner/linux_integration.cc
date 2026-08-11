#include "linux_integration.h"

#include <flutter_linux/flutter_linux.h>
#include <gdk/gdk.h>
#ifdef GDK_WINDOWING_X11
#include <X11/Xatom.h>
#include <X11/XKBlib.h>
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <X11/keysym.h>
#include <gdk/gdkx.h>
#endif
#include <gtk/gtk.h>

#include <cstring>
#include <memory>
#include <set>
#include <string>
#include <vector>

namespace {

FlMethodResponse* SuccessBool(bool value) {
  g_autoptr(FlValue) result = fl_value_new_bool(value);
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

#ifdef GDK_WINDOWING_X11
bool x11_error_occurred = false;

int CaptureX11Error(Display*, XErrorEvent*) {
  x11_error_occurred = true;
  return 0;
}

bool IsUsableWindow(Display* display, Window window) {
  if (display == nullptr || window == None) return false;

  x11_error_occurred = false;
  auto* previous_handler = XSetErrorHandler(CaptureX11Error);
  XWindowAttributes attributes = {};
  const Status status = XGetWindowAttributes(display, window, &attributes);
  XSync(display, False);
  XSetErrorHandler(previous_handler);
  return status != 0 && !x11_error_occurred &&
         attributes.map_state == IsViewable;
}
#endif

}  // namespace

class LinuxIntegration::Impl {
 public:
  explicit Impl(FlBinaryMessenger* messenger) {
    g_autoptr(FlStandardMethodCodec) shortcut_codec =
        fl_standard_method_codec_new();
    shortcut_channel_ = fl_event_channel_new(
        messenger, "dev.raymond.voxwrite/shortcuts",
        FL_METHOD_CODEC(shortcut_codec));
    fl_event_channel_set_stream_handlers(shortcut_channel_, ShortcutListen,
                                         ShortcutCancel, this, nullptr);

    g_autoptr(FlStandardMethodCodec) text_codec =
        fl_standard_method_codec_new();
    text_channel_ = fl_method_channel_new(
        messenger, "dev.raymond.voxwrite/text_destination",
        FL_METHOD_CODEC(text_codec));
    fl_method_channel_set_method_call_handler(text_channel_, TextMethodCall,
                                              this, nullptr);

    g_autoptr(FlStandardMethodCodec) permission_codec =
        fl_standard_method_codec_new();
    permission_channel_ = fl_method_channel_new(
        messenger, "dev.raymond.voxwrite/permissions",
        FL_METHOD_CODEC(permission_codec));
    fl_method_channel_set_method_call_handler(
        permission_channel_, PermissionMethodCall, this, nullptr);
  }

  ~Impl() {
    StopShortcutMonitoring();
    if (shortcut_channel_ != nullptr) {
      fl_event_channel_set_stream_handlers(shortcut_channel_, nullptr, nullptr,
                                           nullptr, nullptr);
    }
    if (text_channel_ != nullptr) {
      fl_method_channel_set_method_call_handler(text_channel_, nullptr, nullptr,
                                                nullptr);
    }
    if (permission_channel_ != nullptr) {
      fl_method_channel_set_method_call_handler(permission_channel_, nullptr,
                                                nullptr, nullptr);
    }
    g_clear_object(&permission_channel_);
    g_clear_object(&text_channel_);
    g_clear_object(&shortcut_channel_);
  }

 private:
  static FlMethodErrorResponse* ShortcutListen(FlEventChannel*, FlValue*,
                                               gpointer user_data) {
    static_cast<Impl*>(user_data)->StartShortcutMonitoring();
    // Wayland is a supported UI/recording fallback. It deliberately has no
    // system-wide shortcut rather than failing the EventChannel repeatedly.
    return nullptr;
  }

  static FlMethodErrorResponse* ShortcutCancel(FlEventChannel*, FlValue*,
                                               gpointer user_data) {
    static_cast<Impl*>(user_data)->StopShortcutMonitoring();
    return nullptr;
  }

  static void TextMethodCall(FlMethodChannel*, FlMethodCall* method_call,
                             gpointer user_data) {
    static_cast<Impl*>(user_data)->HandleTextMethodCall(method_call);
  }

  static void PermissionMethodCall(FlMethodChannel*,
                                   FlMethodCall* method_call,
                                   gpointer user_data) {
    static_cast<Impl*>(user_data)->HandlePermissionMethodCall(method_call);
  }

  void StartShortcutMonitoring() {
    if (shortcut_listening_) return;
    shortcut_listening_ = true;
#ifdef GDK_WINDOWING_X11
    if (!EnsureX11()) return;

    f8_keycode_ = XKeysymToKeycode(display_, XK_F8);
    escape_keycode_ = XKeysymToKeycode(display_, XK_Escape);
    shift_left_keycode_ = XKeysymToKeycode(display_, XK_Shift_L);
    shift_right_keycode_ = XKeysymToKeycode(display_, XK_Shift_R);
    control_left_keycode_ = XKeysymToKeycode(display_, XK_Control_L);
    control_right_keycode_ = XKeysymToKeycode(display_, XK_Control_R);
    if (f8_keycode_ == 0) return;

    Bool detectable_repeat = False;
    XkbSetDetectableAutoRepeat(display_, True, &detectable_repeat);

    x11_error_occurred = false;
    auto* previous_handler = XSetErrorHandler(CaptureX11Error);
    const std::vector<unsigned int> lock_combinations =
        LockModifierCombinations();
    const unsigned int mode_modifiers[] = {0, ShiftMask, ControlMask};
    for (const unsigned int mode_modifier : mode_modifiers) {
      for (const unsigned int locks : lock_combinations) {
        XGrabKey(display_, f8_keycode_, mode_modifier | locks, root_, False,
                 GrabModeAsync, GrabModeAsync);
      }
    }
    XSync(display_, False);
    XSetErrorHandler(previous_handler);
    if (x11_error_occurred) {
      XUngrabKey(display_, f8_keycode_, AnyModifier, root_);
      XSync(display_, False);
      g_warning(
          "Unable to register Linux F8 shortcuts; another application may "
          "own them");
      return;
    }
    gdk_window_add_filter(nullptr, X11EventFilter, this);
    x11_filter_installed_ = true;
    if (session_active_) GrabEscape();
#endif
  }

  void StopShortcutMonitoring() {
    shortcut_listening_ = false;
#ifdef GDK_WINDOWING_X11
    if (display_ != nullptr && root_ != None) {
      if (f8_keycode_ != 0) {
        XUngrabKey(display_, f8_keycode_, AnyModifier, root_);
      }
      UngrabEscape();
      XSync(display_, False);
    }
    if (x11_filter_installed_) {
      gdk_window_remove_filter(nullptr, X11EventFilter, this);
      x11_filter_installed_ = false;
    }
    f8_down_ = false;
#endif
  }

  void SetSessionActive(bool active) {
    if (session_active_ == active) return;
    session_active_ = active;
#ifdef GDK_WINDOWING_X11
    if (!shortcut_listening_ || !EnsureX11()) return;
    if (active) {
      GrabEscape();
    } else {
      UngrabEscape();
    }
#endif
  }

  void HandlePermissionMethodCall(FlMethodCall* method_call) {
    g_autoptr(FlMethodResponse) response = nullptr;
    const gchar* method = fl_method_call_get_name(method_call);
    if (strcmp(method, "setShortcutSessionActive") == 0) {
      bool active = false;
      FlValue* arguments = fl_method_call_get_args(method_call);
      if (arguments != nullptr &&
          fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP) {
        FlValue* active_value = fl_value_lookup_string(arguments, "active");
        if (active_value != nullptr &&
            fl_value_get_type(active_value) == FL_VALUE_TYPE_BOOL) {
          active = fl_value_get_bool(active_value);
        }
      }
      SetSessionActive(active);
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }
    Respond(method_call, response);
  }

  void HandleTextMethodCall(FlMethodCall* method_call) {
    g_autoptr(FlMethodResponse) response = nullptr;
    const gchar* method = fl_method_call_get_name(method_call);

    if (strcmp(method, "captureTarget") == 0) {
      response = SuccessBool(CaptureTarget());
    } else if (strcmp(method, "readSelection") == 0) {
      const std::string selection = ReadSelection();
      if (selection.empty()) {
        response =
            FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
      } else {
        g_autoptr(FlValue) value = fl_value_new_string(selection.c_str());
        response =
            FL_METHOD_RESPONSE(fl_method_success_response_new(value));
      }
    } else if (strcmp(method, "clearTarget") == 0) {
      ClearTarget();
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else if (strcmp(method, "insertText") == 0) {
      FlValue* arguments = fl_method_call_get_args(method_call);
      FlValue* text_value =
          arguments != nullptr &&
                  fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP
              ? fl_value_lookup_string(arguments, "text")
              : nullptr;
      if (text_value == nullptr ||
          fl_value_get_type(text_value) != FL_VALUE_TYPE_STRING) {
        response = FL_METHOD_RESPONSE(fl_method_error_response_new(
            "INVALID_TEXT", "insertText requires a text argument", nullptr));
      } else {
        response = SuccessBool(InsertText(fl_value_get_string(text_value)));
      }
    } else {
      response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }

    Respond(method_call, response);
  }

  static void Respond(FlMethodCall* method_call, FlMethodResponse* response) {
    g_autoptr(GError) error = nullptr;
    if (!fl_method_call_respond(method_call, response, &error)) {
      g_warning("Failed to respond to VoxWrite platform call: %s",
                error->message);
    }
  }

  bool CaptureTarget() {
#ifdef GDK_WINDOWING_X11
    if (!EnsureX11()) {
      target_window_ = None;
      return false;
    }
    target_window_ = ActiveWindow();
    return IsUsableWindow(display_, target_window_);
#else
    return false;
#endif
  }

  std::string ReadSelection() {
#ifdef GDK_WINDOWING_X11
    if (!EnsureX11() || target_window_ == None) return std::string();
    // X11 exposes the currently selected text through PRIMARY, avoiding a
    // synthetic copy and preserving the user's regular clipboard.
    GtkClipboard* primary = gtk_clipboard_get(GDK_SELECTION_PRIMARY);
    gchar* selected = gtk_clipboard_wait_for_text(primary);
    if (selected == nullptr) return std::string();
    std::string result(selected);
    g_free(selected);
    return result;
#else
    return std::string();
#endif
  }

  bool InsertText(const std::string& text) {
    if (text.empty()) {
      ClearTarget();
      return true;
    }
#ifdef GDK_WINDOWING_X11
    if (!EnsureX11() || !IsUsableWindow(display_, target_window_)) {
      ClearTarget();
      return false;
    }

    GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    gtk_clipboard_set_text(clipboard, text.c_str(),
                           static_cast<gint>(text.size()));
    gtk_clipboard_store(clipboard);

    if (!ActivateTargetWindow()) {
      ClearTarget();
      return false;
    }
    g_usleep(160 * 1000);
    if (ActiveWindow() != target_window_) {
      ClearTarget();
      return false;
    }

    const KeyCode control = XKeysymToKeycode(display_, XK_Control_L);
    const KeyCode v = XKeysymToKeycode(display_, XK_v);
    if (control == 0 || v == 0) {
      ClearTarget();
      return false;
    }

    bool sent = XTestFakeKeyEvent(display_, control, True, CurrentTime) != 0;
    sent = XTestFakeKeyEvent(display_, v, True, CurrentTime) != 0 && sent;
    sent = XTestFakeKeyEvent(display_, v, False, CurrentTime) != 0 && sent;
    sent =
        XTestFakeKeyEvent(display_, control, False, CurrentTime) != 0 && sent;
    XFlush(display_);
    ClearTarget();
    return sent;
#else
    return false;
#endif
  }

  void ClearTarget() {
#ifdef GDK_WINDOWING_X11
    target_window_ = None;
#endif
  }

  void Emit(const char* type) {
    if (!shortcut_listening_ || shortcut_channel_ == nullptr) return;
    g_autoptr(FlValue) event = fl_value_new_map();
    fl_value_set_string_take(event, "type", fl_value_new_string(type));
    g_autoptr(GError) error = nullptr;
    if (!fl_event_channel_send(shortcut_channel_, event, nullptr, &error)) {
      g_warning("Failed to send VoxWrite shortcut event: %s", error->message);
    }
  }

#ifdef GDK_WINDOWING_X11
  static GdkFilterReturn X11EventFilter(GdkXEvent* xevent, GdkEvent*,
                                        gpointer user_data) {
    auto* self = static_cast<Impl*>(user_data);
    auto* event = static_cast<XEvent*>(xevent);
    if (event->type != KeyPress && event->type != KeyRelease) {
      return GDK_FILTER_CONTINUE;
    }

    const XKeyEvent& key = event->xkey;
    if (key.keycode == self->f8_keycode_) {
      if (event->type == KeyPress && !self->f8_down_) {
        self->f8_down_ = true;
        self->Emit("fnDown");
        if ((key.state & ControlMask) != 0) {
          self->Emit("selectAsk");
        } else if ((key.state & ShiftMask) != 0) {
          self->Emit("selectTranslation");
        }
      } else if (event->type == KeyRelease && self->f8_down_) {
        self->f8_down_ = false;
        self->Emit("fnUp");
      }
      return GDK_FILTER_REMOVE;
    }

    if (self->f8_down_) {
      const bool is_shift = key.keycode == self->shift_left_keycode_ ||
                            key.keycode == self->shift_right_keycode_;
      const bool is_control = key.keycode == self->control_left_keycode_ ||
                              key.keycode == self->control_right_keycode_;
      if (is_shift || is_control) {
        if (event->type == KeyPress) {
          self->Emit(is_control ? "selectAsk" : "selectTranslation");
        }
        return GDK_FILTER_REMOVE;
      }
    }

    if (self->escape_grabbed_ && key.keycode == self->escape_keycode_) {
      if (event->type == KeyPress) self->Emit("cancel");
      return GDK_FILTER_REMOVE;
    }
    return GDK_FILTER_CONTINUE;
  }

  bool EnsureX11() {
    if (display_ != nullptr) return true;
    GdkDisplay* gdk_display = gdk_display_get_default();
    if (gdk_display == nullptr || !GDK_IS_X11_DISPLAY(gdk_display)) {
      return false;
    }
    display_ = gdk_x11_display_get_xdisplay(gdk_display);
    root_ = DefaultRootWindow(display_);
    return display_ != nullptr && root_ != None;
  }

  unsigned int ModifierMaskFor(KeySym key_sym) const {
    const KeyCode key_code = XKeysymToKeycode(display_, key_sym);
    if (key_code == 0) return 0;
    XModifierKeymap* modifiers = XGetModifierMapping(display_);
    if (modifiers == nullptr) return 0;

    unsigned int mask = 0;
    for (int modifier = 0; modifier < 8; ++modifier) {
      for (int slot = 0; slot < modifiers->max_keypermod; ++slot) {
        const int index = modifier * modifiers->max_keypermod + slot;
        if (modifiers->modifiermap[index] == key_code) {
          mask |= (1U << modifier);
        }
      }
    }
    XFreeModifiermap(modifiers);
    return mask;
  }

  std::vector<unsigned int> LockModifierCombinations() const {
    const unsigned int number_lock = ModifierMaskFor(XK_Num_Lock);
    const unsigned int scroll_lock = ModifierMaskFor(XK_Scroll_Lock);
    const unsigned int optional[] = {LockMask, number_lock, scroll_lock};
    std::set<unsigned int> combinations{0};
    for (const unsigned int modifier : optional) {
      if (modifier == 0) continue;
      const std::vector<unsigned int> current(combinations.begin(),
                                              combinations.end());
      for (const unsigned int value : current) {
        combinations.insert(value | modifier);
      }
    }
    return std::vector<unsigned int>(combinations.begin(), combinations.end());
  }

  void GrabEscape() {
    if (escape_grabbed_ || escape_keycode_ == 0 || display_ == nullptr) return;
    x11_error_occurred = false;
    auto* previous_handler = XSetErrorHandler(CaptureX11Error);
    XGrabKey(display_, escape_keycode_, AnyModifier, root_, False,
             GrabModeAsync, GrabModeAsync);
    XSync(display_, False);
    XSetErrorHandler(previous_handler);
    escape_grabbed_ = !x11_error_occurred;
  }

  void UngrabEscape() {
    if (!escape_grabbed_ || display_ == nullptr) return;
    XUngrabKey(display_, escape_keycode_, AnyModifier, root_);
    XSync(display_, False);
    escape_grabbed_ = false;
  }

  Window ActiveWindow() const {
    if (display_ == nullptr || root_ == None) return None;
    const Atom property = XInternAtom(display_, "_NET_ACTIVE_WINDOW", True);
    if (property == None) return None;

    Atom actual_type = None;
    int actual_format = 0;
    unsigned long item_count = 0;
    unsigned long bytes_after = 0;
    unsigned char* data = nullptr;
    const int status = XGetWindowProperty(
        display_, root_, property, 0, 1, False, XA_WINDOW, &actual_type,
        &actual_format, &item_count, &bytes_after, &data);
    if (status != Success || data == nullptr || item_count == 0) {
      if (data != nullptr) XFree(data);
      return None;
    }
    const Window window = *reinterpret_cast<Window*>(data);
    XFree(data);
    return window;
  }

  bool ActivateTargetWindow() {
    if (target_window_ == None || display_ == nullptr) return false;
    if (ActiveWindow() == target_window_) return true;

    const Atom active_window =
        XInternAtom(display_, "_NET_ACTIVE_WINDOW", False);
    XEvent event = {};
    event.xclient.type = ClientMessage;
    event.xclient.window = target_window_;
    event.xclient.message_type = active_window;
    event.xclient.format = 32;
    // Use a pager-style activation so a user-initiated Voice Session can
    // return to its captured target after asynchronous cloud processing.
    event.xclient.data.l[0] = 2;
    event.xclient.data.l[1] = CurrentTime;

    x11_error_occurred = false;
    auto* previous_handler = XSetErrorHandler(CaptureX11Error);
    XSendEvent(display_, root_, False,
               SubstructureRedirectMask | SubstructureNotifyMask, &event);
    XRaiseWindow(display_, target_window_);
    XSync(display_, False);
    XSetErrorHandler(previous_handler);
    return !x11_error_occurred;
  }

  Display* display_ = nullptr;
  Window root_ = None;
  Window target_window_ = None;
  KeyCode f8_keycode_ = 0;
  KeyCode escape_keycode_ = 0;
  KeyCode shift_left_keycode_ = 0;
  KeyCode shift_right_keycode_ = 0;
  KeyCode control_left_keycode_ = 0;
  KeyCode control_right_keycode_ = 0;
  bool x11_filter_installed_ = false;
  bool f8_down_ = false;
  bool escape_grabbed_ = false;
#endif

  bool shortcut_listening_ = false;
  bool session_active_ = false;
  FlEventChannel* shortcut_channel_ = nullptr;
  FlMethodChannel* text_channel_ = nullptr;
  FlMethodChannel* permission_channel_ = nullptr;
};

LinuxIntegration::LinuxIntegration(FlBinaryMessenger* messenger)
    : impl_(std::make_unique<Impl>(messenger)) {}

LinuxIntegration::~LinuxIntegration() = default;
