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
#include <gio/gio.h>

#include <signal.h>
#include <sys/wait.h>
#include <unistd.h>

#include <cerrno>
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

// How long the backfill text stays on the clipboard after the paste was
// injected before it is removed again. Must be long enough for the target
// application to consume the injected paste.
constexpr guint kClipboardCleanupDelayMs = 1000;

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
  explicit Impl(FlBinaryMessenger* messenger, GtkWindow* window)
      : window_(window) {
    // The backfill writes the transcription into wl-copy's stdin pipe; an
    // outdated wl-copy that exits on unknown options would otherwise kill
    // this process with SIGPIPE.
    signal(SIGPIPE, SIG_IGN);
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

    g_autoptr(FlStandardMethodCodec) lifecycle_codec =
        fl_standard_method_codec_new();
    lifecycle_channel_ = fl_method_channel_new(
        messenger, "dev.raymond.voxwrite/lifecycle",
        FL_METHOD_CODEC(lifecycle_codec));
    fl_method_channel_set_method_call_handler(
        lifecycle_channel_, LifecycleMethodCall, this, nullptr);
  }

  ~Impl() {
    StopShortcutMonitoring();
    CancelClipboardCleanup();
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
    if (lifecycle_channel_ != nullptr) {
      fl_method_channel_set_method_call_handler(lifecycle_channel_, nullptr,
                                                nullptr, nullptr);
    }
    g_clear_object(&permission_channel_);
    g_clear_object(&text_channel_);
    g_clear_object(&shortcut_channel_);
    g_clear_object(&lifecycle_channel_);
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

  static void LifecycleMethodCall(FlMethodChannel*, FlMethodCall* method_call,
                                  gpointer user_data) {
    static_cast<Impl*>(user_data)->HandleLifecycleMethodCall(method_call);
  }

  void StartShortcutMonitoring() {
    if (shortcut_listening_) return;
    shortcut_listening_ = true;
#ifdef GDK_WINDOWING_X11
    if (!EnsureX11()) {
      // Native Wayland session: compositors withhold global key grabs, so
      // register the shortcuts through xdg-desktop-portal instead.
      StartPortalShortcutsWithFallback();
      return;
    }

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
    const unsigned int mode_modifiers[] = {
        0, ShiftMask, ControlMask, ShiftMask | ControlMask};
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
#else
    StartPortalShortcutsWithFallback();
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
    StopPortalShortcuts();
  }

  // ---- xdg-desktop-portal GlobalShortcuts (native Wayland) ----
  //
  // Wayland security does not let a normal client grab keys, focus another
  // window, or inject input, so the F8 workflow cannot reuse the X11 path.
  // On supporting compositors (KDE Plasma 5.27+, GNOME 48+, Hyprland) the
  // GlobalShortcuts portal delivers user-approved activations to this session;
  // text delivery keeps the existing clipboard fallback.

  void StartPortalShortcutsWithFallback() {
    if (StartPortalShortcuts()) return;
    g_warning("VoxWrite: Wayland global shortcuts are unavailable through the "
              "xdg-desktop-portal; falling back to in-app use");
  }

  bool StartPortalShortcuts() {
    GError* error = nullptr;
    GDBusConnection* connection =
        g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
    if (connection == nullptr) {
      g_warning("VoxWrite: cannot connect to the session bus: %s",
                error != nullptr ? error->message : "unknown error");
      g_clear_error(&error);
      return false;
    }
    portal_connection_ = connection;

    GVariantBuilder options;
    g_variant_builder_init(&options, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&options, "{sv}", "handle_token",
                          g_variant_new_string("vx_create_session"));
    g_variant_builder_add(&options, "{sv}", "session_handle_token",
                          g_variant_new_string("vx_session"));

    GVariant* reply = g_dbus_connection_call_sync(
        connection, "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.GlobalShortcuts", "CreateSession",
        g_variant_new("(a{sv})", &options), G_VARIANT_TYPE("(o)"),
        G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
    if (reply == nullptr) {
      g_warning("VoxWrite: portal CreateSession failed: %s",
                error != nullptr ? error->message : "unknown error");
      g_clear_error(&error);
      StopPortalShortcuts();
      return false;
    }

    const gchar* request_path = nullptr;
    g_variant_get(reply, "(o)", &request_path);
    portal_response_subscription_ = g_dbus_connection_signal_subscribe(
        connection, "org.freedesktop.portal.Desktop",
        "org.freedesktop.portal.Request", "Response", request_path, nullptr,
        G_DBUS_SIGNAL_FLAGS_NONE, PortalResponseCallback, this, nullptr);
    g_variant_unref(reply);
    return true;
  }

  static void PortalResponseCallback(GDBusConnection*, const gchar*, const gchar*,
                                     const gchar*, const gchar*, GVariant* parameters,
                                     gpointer user_data) {
    static_cast<Impl*>(user_data)->HandlePortalResponse(parameters);
  }

  void HandlePortalResponse(GVariant* parameters) {
    // Each portal request yields exactly one Response; drop the subscription.
    if (portal_response_subscription_ != 0) {
      g_dbus_connection_signal_unsubscribe(portal_connection_,
                                           portal_response_subscription_);
      portal_response_subscription_ = 0;
    }
    guint response = 1;
    GVariant* results = nullptr;
    g_variant_get(parameters, "(u@a{sv})", &response, &results);
    if (response != 0) {
      g_warning("VoxWrite: portal request was denied or cancelled (response %u)",
                response);
      g_variant_unref(results);
      StopPortalShortcuts();
      return;
    }

    if (portal_session_handle_ == nullptr) {
      // CreateSession succeeded: extract the session handle and bind shortcuts.
      const gchar* session_handle = nullptr;
      if (g_variant_lookup(results, "session_handle", "&s", &session_handle) &&
          session_handle != nullptr) {
        portal_session_handle_ = g_strdup(session_handle);
      }
      g_variant_unref(results);
      if (portal_session_handle_ == nullptr) {
        g_warning("VoxWrite: no session handle in the portal CreateSession "
                  "response");
        StopPortalShortcuts();
        return;
      }
      BindPortalShortcuts();
    } else {
      // BindShortcuts succeeded: shortcut activations now flow to the session.
      g_variant_unref(results);
      SubscribePortalActivations();
    }
  }

  void BindPortalShortcuts() {
    GVariantBuilder shortcuts;
    g_variant_builder_init(&shortcuts, G_VARIANT_TYPE("a(sa{sv})"));
    AddShortcut(&shortcuts, "dictation", "开始口述（Dictation）", "F8");
    AddShortcut(&shortcuts, "translation", "开始翻译（Translation）",
                "SHIFT+F8");
    AddShortcut(&shortcuts, "ask", "开始提问（Ask）", "CTRL+F8");
    // A plain global Escape binding would steal a fundamental desktop key
    // even while VoxWrite is idle. Use a dedicated chord that remains
    // available when Wayland auto-backfill deliberately keeps our window
    // hidden and focused keyboard events cannot reach Flutter.
    AddShortcut(&shortcuts, "cancel", "取消当前录音（Cancel）",
                "CTRL+SHIFT+F8");

    GVariantBuilder options;
    g_variant_builder_init(&options, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&options, "{sv}", "handle_token",
                          g_variant_new_string("vx_bind_shortcuts"));

    GError* error = nullptr;
    GVariant* reply = g_dbus_connection_call_sync(
        portal_connection_, "org.freedesktop.portal.Desktop",
        "/org/freedesktop/portal/desktop",
        "org.freedesktop.portal.GlobalShortcuts", "BindShortcuts",
        // Note: 'o' in a g_variant_new() format string takes a plain string,
        // not a GVariant*; use '@o' only when passing an existing variant.
        g_variant_new("(oa(sa{sv})sa{sv})", portal_session_handle_,
                      &shortcuts, "", &options),
        G_VARIANT_TYPE("(o)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
    if (reply == nullptr) {
      g_warning("VoxWrite: portal BindShortcuts failed: %s",
                error != nullptr ? error->message : "unknown error");
      g_clear_error(&error);
      StopPortalShortcuts();
      return;
    }
    const gchar* request_path = nullptr;
    g_variant_get(reply, "(o)", &request_path);
    portal_response_subscription_ = g_dbus_connection_signal_subscribe(
        portal_connection_, "org.freedesktop.portal.Desktop",
        "org.freedesktop.portal.Request", "Response", request_path, nullptr,
        G_DBUS_SIGNAL_FLAGS_NONE, PortalResponseCallback, this, nullptr);
    g_variant_unref(reply);
  }

  static void AddShortcut(GVariantBuilder* shortcuts, const char* id,
                          const char* description, const char* trigger) {
    GVariantBuilder options;
    g_variant_builder_init(&options, G_VARIANT_TYPE("a{sv}"));
    g_variant_builder_add(&options, "{sv}", "description",
                          g_variant_new_string(description));
    g_variant_builder_add(&options, "{sv}", "preferred_trigger",
                          g_variant_new_string(trigger));
    g_variant_builder_add(shortcuts, "(sa{sv})", id, &options);
  }

  void SubscribePortalActivations() {
    constexpr const char* kInterface = "org.freedesktop.portal.GlobalShortcuts";
    // Session signals are emitted on the portal's main object path (verified
    // against xdg-desktop-portal-kde), not on the session object path.
    // Subscribing without a path and filtering by session_handle in the
    // handler is robust across portal implementations.
    portal_activated_subscription_ = g_dbus_connection_signal_subscribe(
        portal_connection_, "org.freedesktop.portal.Desktop", kInterface,
        "Activated", nullptr, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        PortalActivatedCallback, this, nullptr);
    portal_deactivated_subscription_ = g_dbus_connection_signal_subscribe(
        portal_connection_, "org.freedesktop.portal.Desktop", kInterface,
        "Deactivated", nullptr, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        PortalDeactivatedCallback, this, nullptr);
    portal_changed_subscription_ = g_dbus_connection_signal_subscribe(
        portal_connection_, "org.freedesktop.portal.Desktop", kInterface,
        "ShortcutsChanged", nullptr, nullptr, G_DBUS_SIGNAL_FLAGS_NONE,
        PortalChangedCallback, this, nullptr);
  }

  static void PortalActivatedCallback(GDBusConnection*, const gchar*, const gchar*,
                                      const gchar*, const gchar*, GVariant* parameters,
                                      gpointer user_data) {
    static_cast<Impl*>(user_data)->HandlePortalActivated(parameters);
  }

  static void PortalDeactivatedCallback(GDBusConnection*, const gchar*, const gchar*,
                                        const gchar*, const gchar*, GVariant* parameters,
                                        gpointer user_data) {
    static_cast<Impl*>(user_data)->HandlePortalDeactivated(parameters);
  }

  static void PortalChangedCallback(GDBusConnection*, const gchar*, const gchar*,
                                    const gchar*, const gchar*, GVariant*,
                                    gpointer) {
    // The user may edit the triggers in system settings; activations are keyed
    // by stable shortcut id, so there is nothing to refresh here.
  }

  void HandlePortalActivated(GVariant* parameters) {
    // (o session_handle, s shortcut_id, t timestamp, a{sv} options)
    g_autofree gchar* session_handle = nullptr;
    g_autofree gchar* shortcut_id = nullptr;
    GVariant* timestamp = nullptr;
    GVariant* options = nullptr;
    g_variant_get(parameters, "(os*@a{sv})", &session_handle, &shortcut_id,
                  &timestamp, &options);
    g_variant_unref(timestamp);
    g_variant_unref(options);
    if (g_strcmp0(session_handle, portal_session_handle_) != 0) {
      return;  // Activation belongs to another application's session.
    }
    if (g_strcmp0(shortcut_id, "cancel") == 0) {
      if (session_active_) {
        Emit("cancel");
        if (auto_backfill_) NotifyBackfill("VoxWrite", "本次录音已取消");
      }
      return;
    }
    Emit("fnDown");
    if (g_strcmp0(shortcut_id, "translation") == 0) {
      Emit("selectTranslation");
    } else if (g_strcmp0(shortcut_id, "ask") == 0) {
      Emit("selectAsk");
    }
    // Treat a portal activation as a complete shortcut press. Hyprland's
    // `global` dispatcher emits Activated but no matching Deactivated signal,
    // which otherwise leaves Dart in shortcutPreview and never starts the
    // recorder. Backends that also emit Deactivated are safe: the duplicate
    // fnUp is ignored once the session has left shortcutPreview.
    Emit("fnUp");
    PresentMainWindow();
    if (auto_backfill_) {
      // Silent mode keeps the target app focused; notify so the user knows
      // the voice session actually started.
      NotifyBackfill(
          "VoxWrite", "正在录音…（F8 停止，Ctrl+Shift+F8 取消）");
    }
  }

  void HandlePortalDeactivated(GVariant* parameters) {
    // (o session_handle, s shortcut_id, t timestamp, a{sv} options)
    g_autofree gchar* session_handle = nullptr;
    g_autofree gchar* shortcut_id = nullptr;
    GVariant* timestamp = nullptr;
    GVariant* options = nullptr;
    g_variant_get(parameters, "(os*@a{sv})", &session_handle, &shortcut_id,
                  &timestamp, &options);
    g_variant_unref(timestamp);
    g_variant_unref(options);
    if (g_strcmp0(session_handle, portal_session_handle_) != 0) {
      return;  // Deactivation belongs to another application's session.
    }
    if (g_strcmp0(shortcut_id, "cancel") == 0) return;
    Emit("fnUp");
  }

  void PresentMainWindow() {
    if (window_ == nullptr) return;
    if (auto_backfill_) return;  // keep the target app focused for ydotool paste
    // The global shortcut is a user action; raise VoxWrite so the voice
    // session and its cancel/stop controls are visible on Wayland.
    gtk_window_present(window_);
  }

  void NotifyBackfill(const char* title, const char* message) {
    // g_spawn_async rewrites argv entries (e.g. to a resolved program path),
    // so the array must live on the heap; freeing a stack array would free a
    // stack address and abort. Resolve the binary ourselves and use
    // G_SPAWN_DEFAULT to keep the spawn path fully deterministic.
    g_autofree gchar* notify_send = g_find_program_in_path("notify-send");
    if (notify_send == nullptr) return;
    gchar** argv = g_new0(gchar*, 4);
    argv[0] = g_strdup(notify_send);
    argv[1] = g_strdup(title);
    argv[2] = g_strdup(message);
    g_spawn_async(nullptr, argv, nullptr, G_SPAWN_DEFAULT, nullptr, nullptr,
                  nullptr, nullptr);
    g_strfreev(argv);
  }

  void StopPortalShortcuts() {
    if (portal_connection_ == nullptr) return;
    for (guint* subscription : {&portal_response_subscription_,
                                &portal_activated_subscription_,
                                &portal_deactivated_subscription_,
                                &portal_changed_subscription_}) {
      if (*subscription != 0) {
        g_dbus_connection_signal_unsubscribe(portal_connection_, *subscription);
        *subscription = 0;
      }
    }
    if (portal_session_handle_ != nullptr) {
      // Best-effort close of the portal session (interface Session::Close).
      g_dbus_connection_call_sync(
          portal_connection_, "org.freedesktop.portal.Desktop",
          portal_session_handle_, "org.freedesktop.portal.Session", "Close",
          nullptr, nullptr, G_DBUS_CALL_FLAGS_NONE, -1, nullptr, nullptr);
      g_clear_pointer(&portal_session_handle_, g_free);
    }
    g_clear_object(&portal_connection_);
    portal_connection_ = nullptr;
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

  void HandleLifecycleMethodCall(FlMethodCall* method_call) {
    g_autoptr(FlMethodResponse) response = nullptr;
    const gchar* method = fl_method_call_get_name(method_call);
    if (strcmp(method, "hideWindow") == 0) {
      // Close-to-tray: the Dart side vetoes the app-exit request that the
      // Flutter embedder raises when the window's close button is pressed,
      // then asks us to hide the window so the process keeps running in the
      // background (global F8 shortcuts stay active).
      if (window_ != nullptr) {
        gtk_widget_hide(GTK_WIDGET(window_));
      }
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    }
    Respond(method_call, response);
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
    } else if (strcmp(method, "setWaylandBackfill") == 0) {
      bool enabled = false;
      FlValue* arguments = fl_method_call_get_args(method_call);
      if (arguments != nullptr &&
          fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP) {
        FlValue* enabled_value =
            fl_value_lookup_string(arguments, "enabled");
        if (enabled_value != nullptr &&
            fl_value_get_type(enabled_value) == FL_VALUE_TYPE_BOOL) {
          enabled = fl_value_get_bool(enabled_value);
        }
      }
      auto_backfill_ = enabled;
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
    if (EnsureX11()) {
      if (!IsUsableWindow(display_, target_window_)) {
        ClearTarget();
        return false;
      }

      GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
      // Remember any text already on the clipboard so the backfill text can
      // be removed again once the target app has consumed the paste, matching
      // the macOS bridge. The transient text is deliberately not stored with
      // gtk_clipboard_store(): it must not enter clipboard-manager history.
      gchar* previous_raw = gtk_clipboard_wait_for_text(clipboard);
      std::string* previous_text =
          previous_raw != nullptr ? new std::string(previous_raw) : nullptr;
      g_free(previous_raw);
      // Offer the text together with KDE's password-manager hint so clipboard
      // managers such as Klipper do not persist the transcription in their
      // history.
      auto* transient_text = new std::string(text);
      GtkTargetEntry targets[] = {
          {const_cast<gchar*>("UTF8_STRING"), 0, 0},
          {const_cast<gchar*>("text/plain;charset=utf-8"), 0, 0},
          {const_cast<gchar*>("TEXT"), 0, 0},
          {const_cast<gchar*>("STRING"), 0, 0},
          {const_cast<gchar*>("x-kde-passwordManagerHint"), 0, 0},
      };
      gtk_clipboard_set_with_data(clipboard, targets, G_N_ELEMENTS(targets),
                                  ClipboardTextGet, ClipboardTextClear,
                                  transient_text);

      if (!ActivateTargetWindow()) {
        delete previous_text;
        ClearTarget();
        return false;
      }
      g_usleep(160 * 1000);
      if (ActiveWindow() != target_window_) {
        delete previous_text;
        ClearTarget();
        return false;
      }

      const KeyCode control = XKeysymToKeycode(display_, XK_Control_L);
      const KeyCode v = XKeysymToKeycode(display_, XK_v);
      if (control == 0 || v == 0) {
        delete previous_text;
        ClearTarget();
        return false;
      }

      bool sent = XTestFakeKeyEvent(display_, control, True, CurrentTime) != 0;
      sent = XTestFakeKeyEvent(display_, v, True, CurrentTime) != 0 && sent;
      sent = XTestFakeKeyEvent(display_, v, False, CurrentTime) != 0 && sent;
      sent =
          XTestFakeKeyEvent(display_, control, False, CurrentTime) != 0 && sent;
      XFlush(display_);
      if (sent) {
        ClipboardCleanup cleanup;
        cleanup.inserted_text = text;
        cleanup.previous_text = previous_text;
        ScheduleClipboardCleanup(cleanup);
      } else {
        delete previous_text;
      }
      ClearTarget();
      return sent;
    }
#endif
    // Native Wayland: inject a paste through ydotool (kernel uinput) into the
    // still-focused target application. Falls back to the clipboard in Dart
    // when the tool or its daemon is unavailable.
    if (auto_backfill_) {
      return InsertTextViaYdotool(text);
    }
    return false;
  }

  bool InsertTextViaYdotool(const std::string& text) {
    // GTK's own clipboard claim proved unreliable for a window that receives
    // no fresh input serial, so hand the Wayland clipboard to wl-copy: it
    // claims the selection and keeps serving the data in the background.
    // --foreground keeps the spawned process as the selection owner so it
    // can be terminated again once the injected paste has been consumed.
    // Injecting the paste before the compositor sees the new owner would
    // paste whatever the previous owner (e.g. the clipboard manager) holds.
    g_autofree gchar* wl_copy_path = g_find_program_in_path("wl-copy");
    if (wl_copy_path == nullptr) {
      g_warning("VoxWrite: wl-copy is unavailable; falling back to the "
                "clipboard");
      return false;
    }

    // Remember the text the clipboard held before the backfill. KDE's
    // Klipper re-offers the last clipboard content when the owner exits
    // ("prevent empty clipboard"), so it is asked to restore this text
    // during cleanup.
    std::string* previous_text = nullptr;
    g_autoptr(GDBusConnection) bus_connection = SessionBus();
    if (bus_connection != nullptr) {
      g_autofree gchar* previous =
          KlipperGetClipboardContents(bus_connection);
      if (previous != nullptr && previous[0] != '\0') {
        previous_text = new std::string(previous);
      }
    }

    gchar** copy_argv = g_new0(gchar*, 4);
    copy_argv[0] = g_strdup(wl_copy_path);
    copy_argv[1] = g_strdup("--foreground");
    // --sensitive also offers x-kde-passwordManagerHint, which keeps KDE's
    // Klipper from persisting the transcription in its clipboard history.
    copy_argv[2] = g_strdup("--sensitive");
    gint stdin_fd = -1;
    GPid wl_copy_pid = 0;
    g_autoptr(GError) copy_error = nullptr;
    const gboolean copy_launched = g_spawn_async_with_pipes(
        nullptr, copy_argv, nullptr, G_SPAWN_DEFAULT, nullptr, nullptr,
        &wl_copy_pid, &stdin_fd, nullptr, nullptr, &copy_error);
    g_strfreev(copy_argv);
    if (!copy_launched) {
      g_warning("VoxWrite: wl-copy spawn failed: %s",
                copy_error != nullptr ? copy_error->message : "unknown error");
      delete previous_text;
      return false;
    }
    // Feed the text and close stdin so wl-copy claims the selection.
    const ssize_t written = write(stdin_fd, text.data(), text.size());
    close(stdin_fd);
    if (written != static_cast<ssize_t>(text.size())) {
      g_warning("VoxWrite: failed to feed wl-copy (%zd of %zu bytes)",
                written, text.size());
      delete previous_text;
      return false;
    }
    // wl-copy reads stdin, claims the selection, and keeps serving it in the
    // background; give it and the compositor time to complete the handshake.
    g_usleep(400 * 1000);
    // Exiting before the paste is injected means wl-copy failed to claim the
    // selection. Do not inject a paste that would deliver stale clipboard
    // content. GLib spawns the process through an intermediate helper, so it
    // is never our direct child and liveness must be probed with kill(pid, 0)
    // rather than waitpid().
    if (!ProcessAlive(wl_copy_pid)) {
      g_warning("VoxWrite: wl-copy exited before claiming the clipboard");
      delete previous_text;
      return false;
    }

    g_autofree gchar* ydotool_path = g_find_program_in_path("ydotool");
    if (ydotool_path == nullptr) {
      g_warning("VoxWrite: ydotool is unavailable; falling back to the "
                "clipboard");
      delete previous_text;
      return false;
    }
    // ydotool key 29:1 47:1 47:0 29:0 — LeftCtrl down, V down, V up, up.
    // Keep argv on the heap: g_spawn_* may rewrite argv entries in place.
    gchar** argv = g_new0(gchar*, 7);
    argv[0] = g_strdup(ydotool_path);
    argv[1] = g_strdup("key");
    argv[2] = g_strdup("29:1");
    argv[3] = g_strdup("47:1");
    argv[4] = g_strdup("47:0");
    argv[5] = g_strdup("29:0");
    gint status = 0;
    g_autoptr(GError) error = nullptr;
    const gboolean launched =
        g_spawn_sync(nullptr, argv, nullptr, G_SPAWN_DEFAULT, nullptr, nullptr,
                     nullptr, nullptr, &status, &error);
    g_strfreev(argv);
    if (!launched) {
      g_warning("VoxWrite: ydotool spawn failed: %s",
                error != nullptr ? error->message : "unknown error");
      delete previous_text;
      return false;
    }
    if (g_spawn_check_wait_status(status, nullptr) != TRUE) {
      delete previous_text;
      return false;
    }
    // The paste has been injected. The cleanup timer terminates wl-copy and
    // makes sure the transcription does not linger in the clipboard.
    ClipboardCleanup cleanup;
    cleanup.inserted_text = text;
    cleanup.previous_text = previous_text;
    cleanup.wl_copy_pid = wl_copy_pid;
    ScheduleClipboardCleanup(cleanup);
    return true;
  }

  struct ClipboardCleanup {
    // X11: the text injected by the backfill; the clipboard is only touched
    // again if it still holds exactly this text.
    std::string inserted_text;
    // The text the clipboard held before the backfill. Null means the
    // clipboard held no text.
    std::string* previous_text = nullptr;
    // Wayland: the wl-copy process serving the backfill text.
    GPid wl_copy_pid = 0;
  };

  static GDBusConnection* SessionBus() {
    GError* error = nullptr;
    GDBusConnection* connection =
        g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
    if (connection == nullptr) {
      g_warning("VoxWrite: cannot connect to the session bus: %s",
                error != nullptr ? error->message : "unknown error");
      g_clear_error(&error);
    }
    return connection;
  }

  static gchar* KlipperGetClipboardContents(GDBusConnection* connection) {
    if (connection == nullptr) return nullptr;
    GError* error = nullptr;
    GVariant* reply = g_dbus_connection_call_sync(
        connection, "org.kde.klipper", "/klipper",
        "org.kde.klipper.klipper", "getClipboardContents", nullptr,
        G_VARIANT_TYPE("(s)"), G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
    if (reply == nullptr) {
      g_clear_error(&error);
      return nullptr;
    }
    gchar* text = nullptr;
    g_variant_get(reply, "(s)", &text);
    g_variant_unref(reply);
    return text;
  }

  static void KlipperSetClipboardContents(GDBusConnection* connection,
                                          const gchar* text) {
    if (connection == nullptr || text == nullptr) return;
    GError* error = nullptr;
    GVariant* reply = g_dbus_connection_call_sync(
        connection, "org.kde.klipper", "/klipper",
        "org.kde.klipper.klipper", "setClipboardContents",
        g_variant_new("(s)", text), nullptr, G_DBUS_CALL_FLAGS_NONE, -1,
        nullptr, &error);
    if (reply != nullptr) {
      g_variant_unref(reply);
    } else {
      g_warning("VoxWrite: Klipper setClipboardContents failed: %s",
                error != nullptr ? error->message : "unknown error");
      g_clear_error(&error);
    }
  }

  static void KlipperClearClipboardContents(GDBusConnection* connection) {
    if (connection == nullptr) return;
    GError* error = nullptr;
    GVariant* reply = g_dbus_connection_call_sync(
        connection, "org.kde.klipper", "/klipper",
        "org.kde.klipper.klipper", "clearClipboardContents", nullptr, nullptr,
        G_DBUS_CALL_FLAGS_NONE, -1, nullptr, &error);
    if (reply != nullptr) {
      g_variant_unref(reply);
    } else {
      g_clear_error(&error);
    }
  }

  static void ClearWaylandClipboard() {
    g_autofree gchar* wl_copy_path = g_find_program_in_path("wl-copy");
    if (wl_copy_path == nullptr) return;
    gchar** argv = g_new0(gchar*, 3);
    argv[0] = g_strdup(wl_copy_path);
    argv[1] = g_strdup("--clear");
    g_spawn_async(nullptr, argv, nullptr, G_SPAWN_DEFAULT, nullptr, nullptr,
                  nullptr, nullptr);
    g_strfreev(argv);
  }

  static void ClipboardTextGet(GtkClipboard*, GtkSelectionData* selection_data,
                               guint, gpointer user_data) {
    const auto* text = static_cast<const std::string*>(user_data);
    gtk_selection_data_set_text(selection_data, text->c_str(),
                                static_cast<gint>(text->size()));
  }

  static void ClipboardTextClear(GtkClipboard*, gpointer user_data) {
    delete static_cast<std::string*>(user_data);
  }

  void RestoreViaKlipperIfNeeded(const ClipboardCleanup& cleanup) {
    g_autoptr(GDBusConnection) connection = SessionBus();
    if (connection == nullptr) return;
    g_autofree gchar* current = KlipperGetClipboardContents(connection);
    if (current == nullptr) return;
    const bool holds_ours =
        g_strcmp0(current, cleanup.inserted_text.c_str()) == 0;
    const bool holds_previous =
        cleanup.previous_text != nullptr &&
        g_strcmp0(current, cleanup.previous_text->c_str()) == 0;
    if (!holds_ours && !holds_previous) {
      return;  // The user copied something else in the meantime.
    }
    if (cleanup.previous_text != nullptr &&
        !cleanup.previous_text->empty()) {
      // Re-offer the text that preceded the backfill. Klipper ignores the
      // sensitive transcription, so its tracked content is normally already
      // the previous text; re-offering keeps the live clipboard consistent
      // whether or not "prevent empty clipboard" is enabled.
      KlipperSetClipboardContents(connection,
                                  cleanup.previous_text->c_str());
    } else if (holds_ours) {
      // No earlier text to restore and Klipper still tracks the
      // transcription: release the clipboard entirely. Klipper's "prevent
      // empty clipboard" option may re-offer the transcription anyway; that
      // behavior is controlled by the desktop, not this app.
      KlipperClearClipboardContents(connection);
      ClearWaylandClipboard();
    }
  }

  static bool ProcessAlive(GPid pid) {
    if (pid <= 0) return false;
    if (kill(pid, 0) == 0) return true;
    // EPERM means the process exists but is not ours; ESRCH means it is gone.
    return errno == EPERM;
  }

  static void TerminateWlCopy(GPid pid) {
    if (pid <= 0) return;
    // The spawned process is not a direct child (see InsertTextViaYdotool),
    // so it cannot be reaped here; SIGTERM makes wl-copy release the
    // selection and the session subreaper cleans it up.
    if (ProcessAlive(pid)) {
      kill(pid, SIGTERM);
    }
  }

  void ScheduleClipboardCleanup(const ClipboardCleanup& cleanup) {
    CancelClipboardCleanup();
    pending_clipboard_cleanup_ = new ClipboardCleanup(cleanup);
    clipboard_cleanup_source_ = g_timeout_add(
        kClipboardCleanupDelayMs, ClipboardCleanupFired, this);
  }

  static gboolean ClipboardCleanupFired(gpointer user_data) {
    auto* self = static_cast<Impl*>(user_data);
    self->clipboard_cleanup_source_ = 0;
    ClipboardCleanup* cleanup = self->pending_clipboard_cleanup_;
    self->pending_clipboard_cleanup_ = nullptr;
    if (cleanup != nullptr) {
      self->RunClipboardCleanup(*cleanup);
      delete cleanup;
    }
    return G_SOURCE_REMOVE;
  }

  void RunClipboardCleanup(const ClipboardCleanup& cleanup) {
    if (cleanup.wl_copy_pid > 0) {
      // Releasing the selection removes the backfill text from the clipboard.
      // Klipper may re-offer it afterwards; hand the clipboard back to its
      // previous content in that case.
      TerminateWlCopy(cleanup.wl_copy_pid);
      RestoreViaKlipperIfNeeded(cleanup);
      return;
    }

    GtkClipboard* clipboard = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
    // Leave the clipboard alone when it no longer holds the backfill text: a
    // user copy or another application may have replaced it in the meantime.
    gchar* current = gtk_clipboard_wait_for_text(clipboard);
    if (current == nullptr ||
        g_strcmp0(current, cleanup.inserted_text.c_str()) != 0) {
      g_free(current);
      return;
    }
    g_free(current);

    if (cleanup.previous_text != nullptr) {
      gtk_clipboard_set_text(clipboard, cleanup.previous_text->c_str(),
                             static_cast<gint>(cleanup.previous_text->size()));
    } else {
      gtk_clipboard_clear(clipboard);
      RestoreViaKlipperIfNeeded(cleanup);
    }
  }

  void CancelClipboardCleanup() {
    if (pending_clipboard_cleanup_ != nullptr) {
      delete pending_clipboard_cleanup_;
      pending_clipboard_cleanup_ = nullptr;
    }
    if (clipboard_cleanup_source_ != 0) {
      g_source_remove(clipboard_cleanup_source_);
      clipboard_cleanup_source_ = 0;
    }
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
      const bool is_cancel = (key.state & ShiftMask) != 0 &&
                             (key.state & ControlMask) != 0;
      if (is_cancel) {
        if (event->type == KeyPress && self->session_active_) {
          self->Emit("cancel");
        }
        return GDK_FILTER_REMOVE;
      }
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

  guint clipboard_cleanup_source_ = 0;
  ClipboardCleanup* pending_clipboard_cleanup_ = nullptr;

  bool shortcut_listening_ = false;
  bool session_active_ = false;
  bool auto_backfill_ = false;
  GtkWindow* window_ = nullptr;
  GDBusConnection* portal_connection_ = nullptr;
  gchar* portal_session_handle_ = nullptr;
  guint portal_response_subscription_ = 0;
  guint portal_activated_subscription_ = 0;
  guint portal_deactivated_subscription_ = 0;
  guint portal_changed_subscription_ = 0;
  FlEventChannel* shortcut_channel_ = nullptr;
  FlMethodChannel* text_channel_ = nullptr;
  FlMethodChannel* permission_channel_ = nullptr;
  FlMethodChannel* lifecycle_channel_ = nullptr;
};

LinuxIntegration::LinuxIntegration(FlBinaryMessenger* messenger, GtkWindow* window)
    : impl_(std::make_unique<Impl>(messenger, window)) {}

LinuxIntegration::~LinuxIntegration() = default;
