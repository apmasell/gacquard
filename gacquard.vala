class Gacquard : Object, Loom.PatternContainer {
	private const string APP_PATH = "/apps/gacquard";
	private const string COL_KEY = APP_PATH+"/cols";
	private const string ROW_KEY = APP_PATH+"/rows";
	private static int counts = 0;

	private Gtk.DrawingArea card;
	private int card_cols;
	private int card_rows;
	internal Gtk.Scale card_scale;
	private GConf.Client conf;
	private Gtk.Dialog create;
	private Gtk.SpinButton create_warp_spin;
	private Gtk.ColorSelection create_warp_colour;
	private Gtk.SpinButton create_weft_spin;
	private Gtk.ColorSelection create_weft_colour;
	private string? filename;
	private string? foldername;
	private Loom.Pattern? _pattern;
	private Gtk.HScale pattern_scale;
	private Gtk.Dialog prefs;
	private Gtk.ScrolledWindow pattern_window;
	private Gtk.Window window;

	public Loom.Pattern? pattern {
		get {
			return _pattern;
		}
		private set {
			pattern_window.foreach((widget) => { pattern_window.remove(widget); });
			_pattern = value;
			if (value != null) {
				pattern_window.add_with_viewport(value);
				update_scale();
				card_scale.adjustment.upper = pattern.weft_count;
				pattern.weft_count_changed.connect((num) => { card_scale.adjustment.upper = num; });
				card.queue_draw();
				if (filename == null) {
					window.title = "Loom Editor";
				} else {
					var basename = Path.get_basename(filename);
					if (basename.has_suffix(".gloom")) {
						basename = basename.substring(0, basename.length - 6);
					}
					window.title = @"$(basename) - Loom Editor";
				}
				value.show();
			}
		}
	}

	public Gacquard() {
		AtomicInt.inc(ref counts);
		conf = GConf.Client.get_default();
		try {
			conf.notify_add(APP_PATH, () => { update_conf(); });
		} catch(Error e) {
			warning("Failed to attach to GConf: %s\n", e.message);
		}
		update_conf();
		create_window();
		create_prefs();
		create_new();
		new_loom();

		foldername = Environment.get_home_dir();
	}

	public void get_pattern_container(out Loom.Pattern? pattern, out int rows, out int cols, out int weft) {
		pattern = this.pattern;
		rows = card_rows;
		cols = card_cols;
		weft = (int)(card_scale.get_value()) - 1;
	}

	private Gtk.MenuItem create_menu(bool warp, Gtk.AccelGroup accel_group) {
		var item = new Gtk.MenuItem.with_mnemonic(warp ? "W_arp" : "W_eft");
		var menu = new Gtk.Menu();
		var insert_before = new Gtk.MenuItem.with_mnemonic("Insert strand _before");
		var insert_after = new Gtk.MenuItem.with_mnemonic("Insert strand _after");
		var remove = new Gtk.MenuItem.with_mnemonic("_Delete strands");
		var colour = new Gtk.MenuItem.with_mnemonic("Set _colour...");
		colour.add_accelerator("activate", accel_group, (uint) 'c', warp ? 0 : Gdk.ModifierType.SHIFT_MASK, Gtk.AccelFlags.VISIBLE);
		var copy = new Gtk.MenuItem.with_mnemonic("Copy strands");
		var invert = new Gtk.MenuItem.with_mnemonic("_Invert strands");
		var set_warp = new Gtk.MenuItem.with_mnemonic("Make strands wa_rp");
		var set_weft = new Gtk.MenuItem.with_mnemonic("Make strands we_ft");
		var checker = new Gtk.MenuItem.with_mnemonic("Make a_lternating");

		item.set_submenu(menu);
		menu.append(insert_before);
		menu.append(insert_after);
		menu.append(remove);
		menu.append(new Gtk.SeparatorMenuItem());
		menu.append(colour);
		menu.append(copy);
		menu.append(new Gtk.SeparatorMenuItem());
		menu.append(invert);
		menu.append(set_warp);
		menu.append(set_weft);
		menu.append(checker);

		var area = warp ? Loom.Area.WARP : Loom.Area.WEFT;
		insert_before.activate.connect(() => { do_action(Loom.Action.INSERT_BEFORE, area); });
		insert_after.activate.connect(() => { do_action(Loom.Action.INSERT_AFTER, area); });
		remove.activate.connect(() => { do_action(Loom.Action.DELETE, area); });
		colour.activate.connect(() => { do_action(Loom.Action.COLOUR, area); });
		copy.activate.connect(() => { do_action(Loom.Action.COPY, area); });
		invert.activate.connect(() => { do_action(Loom.Action.INVERT, area); });
		set_warp.activate.connect(() => { do_action(Loom.Action.SET_WARP, area); });
		set_weft.activate.connect(() => { do_action(Loom.Action.SET_WEFT, area); });
		checker.activate.connect(() => { do_action(Loom.Action.CHECKER, area); });

		return item;
	}

	Gtk.Expander create_new_panel(string name, string colour_name, int count, out Gtk.SpinButton spin, out Gtk.ColorSelection picker) {
		Gdk.Color colour;
		Gdk.Color.parse(colour_name, out colour);
		spin = new Gtk.SpinButton.with_range(1, 100, 1);
		spin.digits = 0;
		spin.value = count;
		picker = new Gtk.ColorSelection();
		picker.current_color = colour;
		var box = new Gtk.VBox(false, 0);
		box.pack_start(spin, false, false, 3);
		box.pack_start(picker);
		var expander = new Gtk.Expander(name);
		expander.add(box);
		return expander;
	}

	void create_new() {
		create = new Gtk.Dialog.with_buttons("New Pattern", window, Gtk.DialogFlags.MODAL, Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL, Gtk.Stock.NEW, Gtk.ResponseType.ACCEPT);

		var box = new Gtk.VBox(false, 0);
		box.pack_start(create_new_panel("Warp", "SteelBlue", 10, out create_warp_spin, out create_warp_colour));
		box.pack_start(create_new_panel("Weft", "white", 10, out create_weft_spin, out create_weft_colour));
		box.show_all();
		((Gtk.Box)create.get_content_area()).pack_start(box, true, true, 3);
	}

	void create_prefs() {
		var row_spin = new Gtk.SpinButton.with_range(4, 100, 1);
		row_spin.numeric = true;
		row_spin.value = card_rows;
		row_spin.value_changed.connect((source) => {
				try {
					conf.set_int(ROW_KEY, (int) source.value);
				} catch(Error e) {
					warning("Failed to update GConf: %s\n", e.message);
				}
			});
		var col_spin = new Gtk.SpinButton.with_range(4, 100, 1);
		col_spin.numeric = true;
		col_spin.value = card_cols;
		col_spin.value_changed.connect((source) => {
				try {
					conf.set_int(COL_KEY, (int) source.value);
				} catch(Error e) {
					warning("Failed to update GConf: %s\n", e.message);
				}
			});

		var size_box = new Gtk.HBox(false, 0);
		size_box.pack_start(row_spin, false, false, 0);
		size_box.pack_start(new Gtk.Label("×"));
		size_box.pack_end(col_spin);

		size_box.show_all();

		prefs = new Gtk.Dialog.with_buttons("Preferences - Loom Editor", window, Gtk.DialogFlags.MODAL, Gtk.Stock.CLOSE, Gtk.ResponseType.CLOSE);
		((Gtk.Box)prefs.get_content_area()).pack_start(size_box, true, true, 3);
	}

	void create_window() {
		window = new Gtk.Window();
		window.title = "Loom Editor";
		window.set_default_size(600, 500);
		window.destroy.connect(() => {
				if (AtomicInt.dec_and_test(ref counts)) {
					Gtk.main_quit();
				}
			});

		var accel_group = new Gtk.AccelGroup();
		window.add_accel_group(accel_group);

		var bar = new Gtk.MenuBar();

		var file_menu = new Gtk.Menu();
		var file = new Gtk.MenuItem.with_mnemonic("_File");
		var @new = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.NEW, null);
		var new_window = new Gtk.MenuItem.with_label("New Window");
		var open = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.OPEN, null);
		open.add_accelerator("activate", accel_group, (uint) 'o', Gdk.ModifierType.CONTROL_MASK, Gtk.AccelFlags.VISIBLE);
		var save = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.SAVE, null);
		save.add_accelerator("activate", accel_group, (uint) 's', Gdk.ModifierType.CONTROL_MASK, Gtk.AccelFlags.VISIBLE);
		var save_as = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.SAVE_AS, null);
		var preferences = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.PREFERENCES, null);
		var quit = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.QUIT, accel_group);
		quit.add_accelerator("activate", accel_group, (uint) 'q', Gdk.ModifierType.CONTROL_MASK, Gtk.AccelFlags.VISIBLE);

		file.set_submenu(file_menu);
		file_menu.append(@new);
		file_menu.append(new_window);
		file_menu.append(open);
		file_menu.append(save);
		file_menu.append(save_as);
		file_menu.append(preferences);
		file_menu.append(new Gtk.SeparatorMenuItem());
		file_menu.append(quit);
		bar.append(file);

		var edit_menu = new Gtk.Menu();
		var edit = new Gtk.MenuItem.with_mnemonic("_Edit");
		var undo = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.UNDO, null);
		undo.add_accelerator("activate", accel_group, (uint) 'z', Gdk.ModifierType.CONTROL_MASK, Gtk.AccelFlags.VISIBLE);
		var copy = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.COPY, null);
		copy.add_accelerator("activate", accel_group, (uint) 'c', Gdk.ModifierType.CONTROL_MASK, Gtk.AccelFlags.VISIBLE);
		var paste = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.PASTE, null);
		paste.add_accelerator("activate", accel_group, (uint) 'v', Gdk.ModifierType.CONTROL_MASK, Gtk.AccelFlags.VISIBLE);
		var invert_selection = new Gtk.MenuItem.with_mnemonic("_Invert Selection");
		invert_selection.add_accelerator("activate", accel_group, (uint) 'i', 0, Gtk.AccelFlags.VISIBLE);
		var warp_selection = new Gtk.MenuItem.with_mnemonic("Make selection w_arp");
		warp_selection.add_accelerator("activate", accel_group, (uint) 'a', 0, Gtk.AccelFlags.VISIBLE);
		var weft_selection = new Gtk.MenuItem.with_mnemonic("Make selection w_eft");
		weft_selection.add_accelerator("activate", accel_group, (uint) 'e', 0, Gtk.AccelFlags.VISIBLE);
		var alt_selection = new Gtk.MenuItem.with_mnemonic("Make a_lternating");
		alt_selection.add_accelerator("activate", accel_group, (uint) 'l', 0, Gtk.AccelFlags.VISIBLE);

		var zoom_in = new Gtk.MenuItem.with_mnemonic("Zoom in");
		zoom_in.add_accelerator("activate", accel_group, (uint) '+', 0, Gtk.AccelFlags.VISIBLE);
		var zoom_out = new Gtk.MenuItem.with_mnemonic("Zoom out");
		zoom_out.add_accelerator("activate", accel_group, (uint) '-', 0, Gtk.AccelFlags.VISIBLE);

		edit.set_submenu(edit_menu);
		edit_menu.append(undo);
		edit_menu.append(copy);
		edit_menu.append(paste);
		edit_menu.append(new Gtk.SeparatorMenuItem());
		edit_menu.append(invert_selection);
		edit_menu.append(warp_selection);
		edit_menu.append(weft_selection);
		edit_menu.append(alt_selection);
		edit_menu.append(new Gtk.SeparatorMenuItem());
		edit_menu.append(zoom_in);
		edit_menu.append(zoom_out);
		bar.append(edit);

		bar.append(create_menu(true, accel_group));
		bar.append(create_menu(false, accel_group));

		var vbox = new Gtk.VBox(false, 0);
		window.add(vbox);
		vbox.pack_start(bar, false, false, 3);

		var tab = new Gtk.Notebook();
		pattern_window = new Gtk.ScrolledWindow(null, null);
		var pattern_box = new Gtk.VBox(false, 0);
		pattern_box.pack_start(pattern_window, true, true);
		pattern_scale = new Gtk.HScale.with_range(10, 40, 1);
		pattern_scale.set_value_pos(Gtk.PositionType.LEFT);
		pattern_scale.value_changed.connect(update_scale);
		pattern_scale.set_value(20);
		pattern_scale.digits = 0;
		pattern_box.pack_start(pattern_scale, false, false);
		tab.append_page(pattern_box, new Gtk.Label("Pattern"));

		var card_box = new Gtk.HBox(false, 0);
		card = new Loom.CardView(this);
		card_scale = new Gtk.VScale.with_range(1, 10, 1);
		card_scale.value_changed.connect(card.queue_draw);
		card_scale.digits = 0;
		card_scale.set_value(1);
		card_box.pack_start(card_scale, false, false);
		card_box.pack_end(card);
		tab.append_page(card_box, new Gtk.Label("Cards"));

		vbox.pack_end(tab);

		@new.activate.connect(() => {
				if (create.run() == Gtk.ResponseType.ACCEPT) {
					create.hide();
					this.filename = null;
					this.pattern = new Loom.Pattern(int.max((int)create_warp_spin.value, 1), int.max((int)create_weft_spin.value, 1), create_warp_colour.current_color, create_weft_colour.current_color);
				}
			});
		new_window.activate.connect(() => { new Gacquard(); });
		open.activate.connect(() => {
				var chooser = new Gtk.FileChooserDialog("Open Pattern", window, Gtk.FileChooserAction.OPEN, Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL, Gtk.Stock.OPEN, Gtk.ResponseType.ACCEPT);
				var filter = new Gtk.FileFilter();
				filter.set_name("Gacquard");
				filter.add_pattern("*.gloom");
				chooser.add_filter(filter);
				var all_filter = new Gtk.FileFilter();
				all_filter.set_name("All Files");
				all_filter.add_pattern("*");
				chooser.add_filter(all_filter);
				chooser.local_only = true;
				if (foldername != null) {
					chooser.set_current_folder(foldername);
				}

				if (chooser.run() == Gtk.ResponseType.ACCEPT) {
					foldername = chooser.get_current_folder();
					try {
						var pattern = Loom.Pattern.open(chooser.get_filename());
						if (pattern == null) {
							display_error("Unable to read file %s.", chooser.get_filename());
						} else {
							this.filename = chooser.get_filename();
							this.pattern = pattern;
						}
					} catch (FileError e) {
						display_error(e.message, chooser.get_filename());
					} catch (KeyFileError e) {
						display_error(e.message, chooser.get_filename());
					}
				}
				chooser.hide();
			});
		save.activate.connect(() => { save_file(false); });
		save_as.activate.connect(() => { save_file(true); });
		preferences.activate.connect(() => { prefs.run(); prefs.hide(); });
		quit.activate.connect(Gtk.main_quit);

		undo.activate.connect(() => { do_action(Loom.Action.UNDO, Loom.Area.SELECTION); });
		copy.activate.connect(() => { do_action(Loom.Action.COPY, Loom.Area.SELECTION); });
		paste.activate.connect(() => { do_action(Loom.Action.PASTE, Loom.Area.SELECTION); });
		invert_selection.activate.connect(() => { do_action(Loom.Action.INVERT, Loom.Area.SELECTION); });
		warp_selection.activate.connect(() => { do_action(Loom.Action.SET_WARP, Loom.Area.SELECTION); });
		weft_selection.activate.connect(() => { do_action(Loom.Action.SET_WEFT, Loom.Area.SELECTION); });
		alt_selection.activate.connect(() => { do_action(Loom.Action.CHECKER, Loom.Area.SELECTION); });

		zoom_in.activate.connect(() => { pattern_scale.set_value(pattern_scale.get_value() + 5); });
		zoom_out.activate.connect(() => { pattern_scale.set_value(pattern_scale.get_value() - 5); });

		window.show_all();
	}

	private void do_action(Loom.Action action, Loom.Area area) {
		if (pattern != null) {
			pattern.do_action(action, area);
		}
	}

	void new_loom() {
		Gdk.Color warp_c;
		Gdk.Color weft_c;
		Gdk.Color.parse("SteelBlue", out warp_c);
		Gdk.Color.parse("white", out weft_c);
		filename = null;
		pattern = new Loom.Pattern(20, 10, warp_c, weft_c);
	}

	public void open(string filename) {
		try {
			var pattern = Loom.Pattern.open(filename);
			if (pattern == null) {
			display_error("Unable to read file %s.", filename);
			} else {
				this.filename = filename;
				this.pattern = pattern;
			}
		} catch (KeyFileError e) {
			display_error(e.message, filename);
		} catch (FileError e) {
			display_error(e.message, filename);
		}
	}

	void save_file(bool force_dialog) {
		if (force_dialog || filename == null) {
			var chooser = new Gtk.FileChooserDialog("Save Pattern", window, Gtk.FileChooserAction.SAVE, Gtk.Stock.CANCEL, Gtk.ResponseType.CANCEL, Gtk.Stock.SAVE, Gtk.ResponseType.ACCEPT);
			var filter = new Gtk.FileFilter();
			filter.set_name("Gacquard");
			filter.add_pattern("*.gloom");
			chooser.add_filter(filter);
			chooser.do_overwrite_confirmation = true;
			chooser.local_only = true;
			chooser.set_current_name(filename?? "Untitled pattern.gloom");
			if (foldername != null) {
				chooser.set_current_folder(foldername);
			}

			if (chooser.run() == Gtk.ResponseType.ACCEPT) {
				chooser.hide();
				filename = chooser.get_filename();
				foldername = chooser.get_current_folder();
			} else {
				chooser.hide();
				return;
			}
		}
		try {
			if (!pattern.to_file(filename)) {
				display_error("Could not save to file.", filename);
			}
		} catch (FileError e) {
				display_error(e.message, filename);
		}
	}

	void display_error(string error, string title) {
		var message = new Gtk.MessageDialog(window, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, error, title);
		message.run();
		message.hide();
	}

	void update_conf() {
		try {
			card_rows = conf.get_int(ROW_KEY);
			card_cols = conf.get_int(COL_KEY);
		} catch(Error e) {
			warning("GConf error: %s\n", e.message);
		}
	}

	void update_scale() {
		if (pattern != null) {
			pattern.box_size = int.max((int) pattern_scale.get_value(), 10);
			pattern.queue_draw();
		}
	}
}

public static void main(string[] args) {
	Gtk.init(ref args);
	Gtk.Window.set_default_icon_name("application-x-it87");
	for (var it = 1; it < args.length; it++) {
		var window = new Gacquard();
		window.open(args[it]);
	}

	if (args.length < 2) {
		new Gacquard();
	}
	Gtk.main();
}
