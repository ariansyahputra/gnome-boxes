// This file is part of GNOME Boxes. License: LGPLv2+
using Gtk;
using Gdk;

private class Boxes.DisplayToolbar: Gtk.Toolbar {
    public string title {
        set { label.set_markup (value); }
    }
    private Label label;

    public DisplayToolbar () {
        icon_size = IconSize.MENU;
        get_style_context ().add_class (STYLE_CLASS_MENUBAR);
        set_show_arrow (false);

        // Make sure we're the same size as the normal toolbar
        this.set_size_request (-1, (int) Topbar.height);

        var left_group = new ToolItem ();
        insert (left_group, 0);

        var center_group = new ToolItem ();
        center_group.set_expand (true);
        insert (center_group, -1);

        var right_group = new ToolItem ();
        insert (right_group, -1);

        var size_group = new SizeGroup (SizeGroupMode.HORIZONTAL);
        size_group.add_widget (left_group);
        size_group.add_widget (right_group);

        var left_box = new Box (Orientation.HORIZONTAL, 0);
        left_box.valign = Gtk.Align.CENTER;
        left_group.add (left_box);

        var back = new Button ();
        back.add (new Image.from_icon_name ("go-previous-symbolic",
                                            IconSize.MENU));
        back.get_style_context ().add_class ("raised");
        back.clicked.connect ((button) => { App.app.ui_state = UIState.COLLECTION; });
        left_box.pack_start (back, false, false, 0);

        /* center title - unfortunately, metacity doesn't even center its
           own title.. sad panda */
        label = new Label ("Display");
        label.use_markup = true;
        center_group.add (label);

        var right_box = new Box (Orientation.HORIZONTAL, 12);
        right_box.valign = Gtk.Align.CENTER;
        right_group.add(right_box);

        var btn = new Button ();
        btn.add (new Image.from_icon_name ("view-fullscreen-symbolic",
                                           IconSize.MENU));
        btn.get_style_context ().add_class ("raised");
        btn.clicked.connect ((button) => { App.app.fullscreen = !App.app.fullscreen; });
        right_box.pack_start (btn, false, false, 0);

        var props = new Button ();
        props.add (new Image.from_icon_name ("utilities-system-monitor-symbolic",
                                             IconSize.MENU));
        props.get_style_context ().add_class ("raised");
        props.clicked.connect ((button) => { App.app.ui_state = UIState.PROPERTIES; });
        right_box.pack_start (props, false, false, 0);
    }
}

private class Boxes.DisplayPage: GLib.Object {
    public Widget widget { get { return overlay; } }

    private Overlay overlay;
    private EventBox event_box;
    private Box box;
    private DisplayToolbar overlay_toolbar;
    private DisplayToolbar toolbar;
    private uint toolbar_hide_id;
    private ulong display_id;
    private ulong cursor_id;

    private Boxes.Display display;
    private bool can_grab_mouse { get { return display.can_grab_mouse; } }
    private bool grabbed { get { return display.mouse_grabbed; } }
    private ulong display_can_grab_id;
    private ulong display_grabbed_id;

    public DisplayPage () {
        event_box = new EventBox ();
        event_box.set_events (EventMask.POINTER_MOTION_MASK | EventMask.SCROLL_MASK);
        event_box.above_child = true;
        event_box.event.connect ((event) => {
            if (App.app.fullscreen && event.type == EventType.MOTION_NOTIFY) {
                var y = event.motion.y;
                if (y <= 0) {
                    toolbar_event_stop ();
                    if ((event.motion.state &
                         (ModifierType.SHIFT_MASK | ModifierType.CONTROL_MASK |
                          ModifierType.MOD1_MASK | ModifierType.SUPER_MASK |
                          ModifierType.HYPER_MASK | ModifierType.META_MASK |
                          ModifierType.BUTTON1_MASK | ModifierType.BUTTON2_MASK |
                          ModifierType.BUTTON3_MASK | ModifierType.BUTTON4_MASK |
                          ModifierType.BUTTON5_MASK)) == 0)
                        set_overlay_toolbar_visible (true);
                } else if (y > 5 && toolbar_hide_id == 0) {
                    toolbar_event_stop ();
                    toolbar_hide_id = Timeout.add (App.app.duration, () => {
                        set_overlay_toolbar_visible (false);
                        toolbar_hide_id = 0;
                        return false;
                    });
                }
            }

            if (event.type == EventType.GRAB_BROKEN)
                return false;

            if (event_box.get_child () != null)
                event_box.get_child ().event (event);

            return false;
        });

        toolbar = new DisplayToolbar ();

        box = new Box (Orientation.VERTICAL, 0);
        box.pack_start (toolbar, false, false, 0);
        box.pack_start (event_box, true, true, 0);

        overlay = new Overlay ();
        App.app.window.window_state_event.connect ((event) => {
            update_toolbar_visible ();

            return false;
        });
        overlay.margin = 0;
        overlay.add (box);

        overlay_toolbar = new DisplayToolbar ();
        overlay_toolbar.set_valign (Gtk.Align.START);

        overlay.add_overlay (overlay_toolbar);
        overlay.show_all ();
    }

    public void get_size (out int width, out int height) {
        int tb_height;

        App.app.window.get_size (out width, out height);

        if (!App.app.fullscreen) {
            toolbar.get_preferred_height (null, out tb_height);
            height -= tb_height;
        }
    }

     private void update_toolbar_visible() {
         if (App.app.fullscreen && !can_grab_mouse)
             toolbar.visible = false;
         else
             toolbar.visible = true;

         set_overlay_toolbar_visible (false);
     }

     private void set_overlay_toolbar_visible(bool visible) {
        if (visible && toolbar.visible) {
            debug ("toolbar is visible, don't show overlay toolbar");
            return;
        }

        overlay_toolbar.visible = visible;
    }

    ~DisplayPage () {
        toolbar_event_stop ();
    }

    private void toolbar_event_stop () {
        if (toolbar_hide_id != 0)
            GLib.Source.remove (toolbar_hide_id);
        toolbar_hide_id = 0;
    }

    public void show () {
        App.app.notebook.page = Boxes.AppPage.DISPLAY;
    }

    public void update_title () {
        var machine = App.app.current_item as Boxes.Machine;
        return_if_fail (machine != null);

        var title = machine.title;
        if (grabbed)
            title = _("%s <b>(press Ctrl+Alt keys to ungrab)</b>").printf (title);

        overlay_toolbar.title = toolbar.title = title;
    }

    public void show_display (Boxes.Display display, Widget widget) {
        remove_display ();

        this.display = display;
        display_grabbed_id = display.notify["mouse-grabbed"].connect(() => {
            update_title ();
        });
        display_can_grab_id = display.notify["can-grab-mouse"].connect(() => {
            update_toolbar_visible ();
        });

        set_overlay_toolbar_visible (false);
        update_title ();
        widget.set_events (widget.get_events () & ~Gdk.EventMask.POINTER_MOTION_MASK);
        event_box.add (widget);
        event_box.show_all ();

        display_id = widget.event.connect ((event) => {
            switch (event.type) {
            case EventType.LEAVE_NOTIFY:
                toolbar_event_stop ();
                break;
            case EventType.ENTER_NOTIFY:
                toolbar_event_stop ();
                break;
            }
            return false;
        });

        ulong draw_id = 0;
        draw_id = widget.draw.connect (() => {
            widget.disconnect (draw_id);

            cursor_id = widget.get_window ().notify["cursor"].connect (() => {
                event_box.get_window ().set_cursor (widget.get_window ().cursor);
            });

            return false;
        });

        show ();
    }

    public Widget? remove_display () {
        if (display_grabbed_id != 0) {
            display.disconnect (display_grabbed_id);
            display_grabbed_id = 0;
        }

        if (display_can_grab_id != 0) {
            display.disconnect (display_can_grab_id);
            display_can_grab_id = 0;
        }

        var widget = event_box.get_child ();

        if (display_id != 0) {
            widget.disconnect (display_id);
            display_id = 0;
        }
        if (cursor_id != 0) {
            widget.get_window ().disconnect (cursor_id);
            cursor_id = 0;
        }

        if (widget != null)
            event_box.remove (widget);

        return widget;
    }

}
