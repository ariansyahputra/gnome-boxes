// This file is part of GNOME Boxes. License: LGPLv2+
using Clutter;
using Gtk;

public enum Boxes.TopbarPage {
    COLLECTION,
    SELECTION,
    WIZARD,
    PROPERTIES,
    DISPLAY
}

[GtkTemplate (ui = "/org/gnome/Boxes/ui/topbar.ui")]
private class Boxes.Topbar: Gtk.Notebook, Boxes.UI {
    // FIXME: This is really redundant now that App is using widget property
    // instead but parent Boxes.UI currently requires an actor. Hopefully
    // soon we can move more towards new Gtk classes and Boxes.UI requires
    // a widget property instead.
    public Clutter.Actor actor {
        get {
            if (gtk_actor == null)
                gtk_actor = new Clutter.Actor ();
            return gtk_actor;
        }
    }
    private Clutter.Actor gtk_actor;
    public UIState previous_ui_state { get; protected set; }
    public UIState ui_state { get; protected set; }

    [GtkChild]
    public Gtk.Button wizard_cancel_btn;
    [GtkChild]
    public Gtk.Button wizard_back_btn;
    [GtkChild]
    public Gtk.Button wizard_continue_btn;
    [GtkChild]
    public Gtk.Button wizard_create_btn;

    [GtkChild]
    private Gtk.Spinner spinner;
    [GtkChild]
    private Gtk.Button search_btn;
    [GtkChild]
    private Gtk.Button search2_btn;
    [GtkChild]
    private Gtk.Button select_btn;
    [GtkChild]
    private Gtk.Button back_btn;
    [GtkChild]
    private Gtk.Image back_image;
    [GtkChild]
    private Gtk.Button new_btn;
    [GtkChild]
    private Gtk.MenuButton selection_menu_button;
    [GtkChild]
    private Gtk.HeaderBar collection_toolbar;
    [GtkChild]
    private DisplayToolbar display_toolbar;

    public string? _status;
    public string? status {
        get { return _status; }
        set {
            _status = value;
            collection_toolbar.set_title (_status);
            display_toolbar.set_title (_status);
        }
    }

    public Topbar () {
        notify["ui-state"].connect (ui_state_changed);

        setup_topbar ();

        App.app.notify["selected-items"].connect (() => {
            update_selection_label ();
        });
    }

    private void setup_topbar () {
        var back_icon = (get_direction () == Gtk.TextDirection.RTL)? "go-previous-rtl-symbolic" :
                                                                     "go-previous-symbolic";
        back_image.set_from_icon_name (back_icon, Gtk.IconSize.MENU);

        search_btn.bind_property ("active", App.app.searchbar, "visible", BindingFlags.BIDIRECTIONAL);
        search2_btn.bind_property ("active", App.app.searchbar, "visible", BindingFlags.BIDIRECTIONAL);

        App.app.notify["selection-mode"].connect (() => {
            page = App.app.selection_mode ?
                TopbarPage.SELECTION : page = TopbarPage.COLLECTION;
        });
        update_select_btn ();
        App.app.collection.item_added.connect (update_select_btn);
        App.app.collection.item_removed.connect (update_select_btn);
        update_selection_label ();

        var toolbar = App.app.display_page.toolbar;
        toolbar.bind_property ("title", display_toolbar, "title", BindingFlags.SYNC_CREATE);
        toolbar.bind_property ("subtitle", display_toolbar, "subtitle", BindingFlags.SYNC_CREATE);

        update_search_btn ();
        App.app.collection.item_added.connect (update_search_btn);
        App.app.collection.item_removed.connect (update_search_btn);
    }

    private void update_search_btn () {
        search_btn.sensitive = App.app.collection.items.length != 0;
        search2_btn.sensitive = App.app.collection.items.length != 0;
    }

    private void update_select_btn () {
        select_btn.sensitive = App.app.collection.items.length != 0;
    }

    private void update_selection_label () {
        var items = App.app.selected_items.length ();
        if (items > 0) {
            // This goes with the "Click on items to select them" string and is about selection of items (boxes)
            // when the main collection view is in selection mode.
            selection_menu_button.label = ngettext ("%d selected", "%d selected", items).printf (items);
        } else {
            selection_menu_button.label = _("(Click on items to select them)");
        }
    }

    private void ui_state_changed () {
        switch (ui_state) {
        case UIState.COLLECTION:
            page = TopbarPage.COLLECTION;
            back_btn.hide ();
            spinner.hide ();
            select_btn.show ();
            search_btn.show ();
            new_btn.show ();
            break;

        case UIState.CREDS:
            page = TopbarPage.COLLECTION;
            new_btn.hide ();
            back_btn.show ();
            spinner.show ();
            select_btn.hide ();
            search_btn.hide ();
            break;

        case UIState.DISPLAY:
            page = TopbarPage.DISPLAY;
            spinner.hide ();
            break;

        case UIState.PROPERTIES:
            page = TopbarPage.PROPERTIES;
            break;

        case UIState.WIZARD:
            page = TopbarPage.WIZARD;
            break;

        default:
            break;
        }
    }

    [GtkCallback]
    private void on_new_btn_clicked () {
        App.app.set_state (UIState.WIZARD);
    }

    [GtkCallback]
    private void on_back_btn_clicked () {
        App.app.set_state (UIState.COLLECTION);
    }

    [GtkCallback]
    private void on_select_btn_clicked () {
        App.app.selection_mode = true;
    }

    [GtkCallback]
    private void on_cancel_btn_clicked () {
        App.app.selection_mode = false;
    }
}
