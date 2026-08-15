#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <libayatana-appindicator/app-indicator.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "linux_integration.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  LinuxIntegration* linux_integration;
  AppIndicator* indicator;
  GtkMenu* tray_menu;
  GtkWindow* main_window;
  gboolean tray_ready;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// The window's close button hides VoxWrite to the system tray instead of
// quitting, so the global F8 shortcuts keep working while the app runs in the
// background. Quit explicitly from the tray menu, mirroring the macOS
// menu-bar behaviour. Note: the Flutter embedder intercepts delete-event and
// routes the close through System.requestAppExit to the Dart side, which
// vetoes the exit and asks the LinuxIntegration 'hideWindow' bridge to hide
// the window.
static void tray_open_cb(GtkMenu*, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->main_window == nullptr) return;
  gtk_widget_show(GTK_WIDGET(self->main_window));
  gtk_window_present(self->main_window);
}

static void tray_quit_cb(GtkMenu*, gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  if (self->main_window != nullptr) {
    gtk_widget_destroy(GTK_WIDGET(self->main_window));
    self->main_window = nullptr;
  }
  g_application_quit(G_APPLICATION(self));
}

// Resolves the bundle's data directory from the running executable, e.g.
// "<bundle>/voxwrite" -> "<bundle>/data".
static gchar* bundle_data_dir() {
  g_autofree gchar* exe_path = g_file_read_link("/proc/self/exe", nullptr);
  if (exe_path == nullptr) return nullptr;
  g_autofree gchar* exe_dir = g_path_get_dirname(exe_path);
  return g_build_filename(exe_dir, "data", nullptr);
}

static void setup_tray(MyApplication* self) {
  if (self->tray_ready) return;
  self->tray_ready = TRUE;

  // The library's convenience constructors are deprecated but remain the
  // supported way to create an indicator; silence the deprecation warning.
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
  self->indicator = app_indicator_new(
      "dev.raymond.voxwrite", "voxwrite-tray",
      APP_INDICATOR_CATEGORY_APPLICATION_STATUS);
#pragma GCC diagnostic pop

  // Prefer the bundled app icon; fall back to a themed microphone icon on
  // desktops that cannot resolve the custom icon-theme path. The theme path
  // must end in "icons" and hold a hicolor theme: KDE's StatusNotifierItem
  // host only wires up its custom icon loader when the path ends in "icons".
  gboolean used_bundled_icon = FALSE;
  g_autofree gchar* data_dir = bundle_data_dir();
  if (data_dir != nullptr) {
    g_autofree gchar* icons_dir = g_build_filename(data_dir, "icons", nullptr);
    g_autofree gchar* index_theme =
        g_build_filename(icons_dir, "hicolor", "index.theme", nullptr);
    if (g_file_test(index_theme, G_FILE_TEST_EXISTS)) {
      app_indicator_set_icon_theme_path(self->indicator, icons_dir);
      app_indicator_set_icon_full(self->indicator, "voxwrite-tray",
                                  "VoxWrite");
      used_bundled_icon = TRUE;
    }
  }
  if (!used_bundled_icon) {
    app_indicator_set_icon_full(self->indicator, "audio-input-microphone",
                                "VoxWrite");
  }

  self->tray_menu = GTK_MENU(gtk_menu_new());
  GtkWidget* open_item = gtk_menu_item_new_with_label("打开 VoxWrite");
  g_signal_connect(open_item, "activate", G_CALLBACK(tray_open_cb), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), open_item);

  GtkWidget* separator = gtk_separator_menu_item_new();
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), separator);

  GtkWidget* quit_item = gtk_menu_item_new_with_label("退出 VoxWrite");
  g_signal_connect(quit_item, "activate", G_CALLBACK(tray_quit_cb), self);
  gtk_menu_shell_append(GTK_MENU_SHELL(self->tray_menu), quit_item);

  gtk_widget_show_all(GTK_WIDGET(self->tray_menu));
  app_indicator_set_menu(self->indicator, self->tray_menu);
  app_indicator_set_status(self->indicator, APP_INDICATOR_STATUS_ACTIVE);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "VoxWrite");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "VoxWrite");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  FlEngine* engine = fl_view_get_engine(view);
  self->linux_integration = new LinuxIntegration(
      fl_engine_get_binary_messenger(engine), window);

  gtk_widget_grab_focus(GTK_WIDGET(view));

  // Close-to-tray: keep the process alive in the background so the global F8
  // shortcuts keep working; quit through the tray menu instead. The window is
  // hidden by the Dart close-to-tray handler (see main.dart).
  self->main_window = window;
  setup_tray(self);
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  delete self->linux_integration;
  self->linux_integration = nullptr;

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  delete self->linux_integration;
  self->linux_integration = nullptr;
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {
  self->tray_ready = FALSE;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
