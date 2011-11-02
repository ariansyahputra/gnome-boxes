// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;
using Clutter;

private enum Boxes.AppPage {
    MAIN,
    DISPLAY
}

private class Boxes.App: Boxes.UI {
    public override Clutter.Actor actor { get { return stage; } }
    public Gtk.Window window;
    public Gtk.Notebook notebook;
    public GtkClutter.Embed embed;
    public Clutter.Stage stage;
    public Clutter.State state;
    public Clutter.Box box; // the whole app box
    public CollectionItem current_item; // current object/vm manipulated
    public Topbar topbar;
    public Sidebar sidebar;
    public static const uint duration = 555;  // default to 1/2 for all transitions
    public static GLib.Settings settings;
    public Wizard wizard;
    public Properties properties;
    public DisplayPage display_page;
    public string? uri { get; private set; }

    private Clutter.TableLayout box_table;
    private Collection collection;
    private CollectionView view;

    private HashTable<string,GVir.Connection> connections;

    public App () {
        settings = new GLib.Settings ("org.gnome.boxes");
        setup_ui ();
        collection = new Collection (this);
        connections = new HashTable<string, GVir.Connection> (str_hash, str_equal);
        collection.item_added.connect ((item) => {
            item.actor.set_reactive (true);
            item.actor.button_press_event.connect ((actor, event) => {
                return item_clicked (item, event);
            });

            view.add_item (item);
        });

        setup_sources.begin ();
    }

    public App.with_uri (string uri) {
        this ();
        this.uri = uri;

        ui_state = UIState.WIZARD;
    }

    public void set_category (Category category) {
        topbar.label.set_text (category.name);
    }

    private async void setup_libvirt (CollectionSource source) {
        var connection = new GVir.Connection (source.uri);

        try {
            yield connection.open_async (null);
            connection.fetch_domains (null);
        } catch (GLib.Error error) {
            warning (error.message);
        }

        foreach (var domain in connection.get_domains ()) {
            var machine = new LibvirtMachine (source, this, connection, domain);
            collection.add_item (machine);
        }

        connection.domain_added.connect ((connection, domain) => {
            var machine = new LibvirtMachine (source, this, connection, domain);
            collection.add_item (machine);
        });

        connections.replace (source.uri, connection);
    }

    public void add_collection_source (CollectionSource source) {
        switch (source.source_type) {
        case "libvirt":
            setup_libvirt (source);
            break;

        case "vnc":
        case "spice":
            var machine = new RemoteMachine (source, this);
            collection.add_item (machine);
            break;

        default:
            warning ("Unsupported source type %s", source.source_type);
            break;
        }
    }

    private async void setup_sources () {
        if (!has_pkgconfig_sources ()) {
            var src = File.new_for_path (get_pkgdata_source ("QEMU_Session"));
            var dst = File.new_for_path (get_pkgconfig_source ("QEMU Session"));
            try {
                yield src.copy_async (dst, FileCopyFlags.NONE);
            } catch (GLib.Error error) {
                critical ("Can't setup default sources: %s", error.message);
            }
        }

        var dir = File.new_for_path (get_pkgconfig_source ());
        get_sources_from_dir (dir);
    }

    private async void get_sources_from_dir (File dir) {
        try {
            var enumerator = yield dir.enumerate_children_async (FILE_ATTRIBUTE_STANDARD_NAME,
                                                                 0, Priority.DEFAULT);
            while (true) {
                var files = yield enumerator.next_files_async (10, Priority.DEFAULT);
                if (files == null)
                    break;

                foreach (var file in files) {
                    var source = new CollectionSource.with_file (file.get_name ());
                    add_collection_source (source);
                }
            }
        } catch (GLib.Error error) {
            warning (error.message);
        }
    }

    private void setup_ui () {
        window = new Gtk.Window ();
        window.set_default_size (680, 480);
        window.maximize ();
        notebook = new Gtk.Notebook ();
        notebook.show_border = false;
        notebook.show_tabs = false;
        window.add (notebook);
        embed = new GtkClutter.Embed ();
        notebook.append_page (embed, null);

        display_page = new DisplayPage (this);
        notebook.append_page (display_page.widget, null);

        stage = embed.get_stage () as Clutter.Stage;
        stage.set_color (gdk_rgba_to_clutter_color (get_boxes_bg_color ()));

        state = new Clutter.State ();
        state.set_duration (null, null, duration);

        window.destroy.connect (quit);
        window.key_press_event.connect (on_key_pressed);

        box_table = new Clutter.TableLayout ();
        box = new Clutter.Box (box_table);
        box.add_constraint (new Clutter.BindConstraint (stage, BindCoordinate.SIZE, 0));
        stage.add_actor (box);

        topbar = new Topbar (this);
        sidebar = new Sidebar (this);
        view = new CollectionView (this);

        window.show_all ();

        wizard = new Wizard (this);
        properties = new Properties (this);

        ui_state = UIState.COLLECTION;
    }

    private void set_main_ui_state (string clutter_state) {
        notebook.page = Boxes.AppPage.MAIN;
        box.set_layout_manager (box_table);
        state.set_state (clutter_state);
    }

    public override void ui_state_changed () {
        box.set_layout_manager (box_table);

        foreach (var ui in new Boxes.UI[] { sidebar, topbar, view, wizard, properties }) {
            ui.ui_state = ui_state;
        }

        switch (ui_state) {
        case UIState.DISPLAY:
            box.set_layout_manager (new Clutter.FixedLayout ());
            state.set_state ("display");
            break;

        case UIState.CREDS:
            set_main_ui_state ("creds");
            break;

        case UIState.COLLECTION:
            if (current_item is Machine) {
                var machine = current_item as Machine;

                machine.disconnect_display ();
                machine.update_screenshot.begin ();
            }
            set_main_ui_state ("collection");
            break;

        case UIState.PROPERTIES:
        case UIState.WIZARD:
            set_main_ui_state ("collection");
            break;

        default:
            warning ("Unhandled UI state %s".printf (ui_state.to_string ()));
            break;
        }
    }

    public void quit () {
        Gtk.main_quit ();
    }

    private bool on_key_pressed (Widget widget, Gdk.EventKey event) {
        if (event.keyval == F11_KEY) {
            if (WindowState.FULLSCREEN in window.get_window ().get_state ())
                window.unfullscreen ();
            else
                window.fullscreen ();

            return true;
        }

        return false;
    }

    private bool item_clicked (CollectionItem item, Clutter.ButtonEvent event) {
        if (ui_state == UIState.COLLECTION) {
            current_item = item;

            if (current_item is Machine) {
                var machine = current_item as Machine;

                if (event.button == 1) {
                    machine.connect_display ();
                    ui_state = UIState.CREDS;
                }
            } else
                warning ("unknown item, fix your code");
        }

        return false;
    }
}

