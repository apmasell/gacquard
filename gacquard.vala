struct weft_line {
	Gdk.Color colour;
	bool[] warps;

	internal weft_line(int length, Gdk.Color colour) {
		warps = new bool[length];
		this.colour = colour;
	}

	internal void delete(int position) {
		for (var it = position; it < warps.length-1; it++) {
			warps[it] = warps[it+1];
		}
		warps.resize(warps.length-1);
	}
	internal void insert(int position) {
		var new_warps = new bool[warps.length+1];
		for (var it = 0; it < warps.length; it++) {
			new_warps[it+(it < position ? 0 : 1)] = warps[it];
		}
		warps = (owned) new_warps;
	}

	internal void to_file(FileStream file) {
		file.printf("%s ", colour.to_string());
		foreach (var b in warps) {
			file.printf("%c", b ? '|' : '-');
		}
		file.putc('\n');
	}
}

class LoomMenu : Gtk.Menu {
	private LoomPattern pattern;
	internal int warp = -1;
	internal int weft = -1;

	internal LoomMenu(LoomPattern pattern) {
		this.pattern = pattern;

		var warp_before = new Gtk.MenuItem.with_label("Insert Warp Before");
		var warp_after = new Gtk.MenuItem.with_label("Insert Warp After");
		var warp_colour = new Gtk.MenuItem.with_label("Set Warp Colour");
		var warp_delete = new Gtk.MenuItem.with_label("Delete Warp");
		var sep = new Gtk.SeparatorMenuItem();
		var weft_before = new Gtk.MenuItem.with_label("Insert Weft Before");
		var weft_after = new Gtk.MenuItem.with_label("Insert Weft After");
		var weft_colour = new Gtk.MenuItem.with_label("Set Weft Colour");
		var weft_delete = new Gtk.MenuItem.with_label("Delete Weft");

		warp_before.activate.connect(() => { this.pattern.insert_warp(this.warp); });
		warp_after.activate.connect(() => { this.pattern.insert_warp(this.warp+1); });
		warp_colour.activate.connect(() => { this.choose_colour(true); });
		warp_delete.activate.connect(() => { this.pattern.delete_warp(this.warp); });
		weft_before.activate.connect(() => { this.pattern.insert_weft(this.weft); });
		weft_after.activate.connect(() => { this.pattern.insert_weft(this.weft+1); });
		weft_colour.activate.connect(() => { this.choose_colour(false); });
		weft_delete.activate.connect(() => { this.pattern.delete_weft(this.weft); });

		this.append(warp_before);
		this.append(warp_after);
		this.append(warp_colour);
		this.append(warp_delete);
		this.append(sep);
		this.append(weft_before);
		this.append(weft_after);
		this.append(weft_colour);
		this.append(weft_delete);

		warp_before.show();
		warp_after.show();
		warp_colour.show();
		warp_delete.show();
		sep.show();
		weft_before.show();
		weft_after.show();
		weft_colour.show();
		weft_delete.show();
	}

	void choose_colour(bool is_warp) {
		var dialog = new Gtk.ColorSelectionDialog(@"Select $(is_warp ? "Warp " : "Weft") Colour");
		((Gtk.ColorSelection)dialog.color_selection).current_color = is_warp ? pattern.get_warp_colour(warp) : pattern.get_weft_colour(weft);

		((Gtk.Button)dialog.cancel_button).clicked.connect(() => {
			   dialog.destroy();
		   });
		((Gtk.Button)dialog.ok_button).clicked.connect(() => {
				  if (is_warp) {
				    pattern.set_warp_colour(warp, ((Gtk.ColorSelection)dialog.color_selection).current_color);
				  } else {
				    pattern.set_weft_colour(weft, ((Gtk.ColorSelection)dialog.color_selection).current_color);
				  }
				  pattern.queue_draw();
				  dialog.destroy();
				});
		dialog.run();
	}
}

public class LoomPattern : Gtk.Widget {

	private LoomMenu menu;

	private Gdk.Color[] warp_colours;

	private weft_line[] wefts;

	public int box_size { get; set; default = 30; }

	public int weft_count {
		get {
			return wefts.length;
		}
	}

	public int warp_count {
		get {
			return warp_colours.length;
		}
	}

	public signal void weft_count_changed(int count);

	construct {
		menu = new LoomMenu(this);
	}

	public static LoomPattern? open(string filename) {
		var file = FileStream.open(filename, "r");
		if (file == null) {
			warning("Unable to open file %s\n", filename);
			return null;
		}
		var colours = (file.read_line()?? "").split(" ");
		if (colours[0] != "GACQUARD") {
			warning("Bad header in %s\n", filename);
			return null;
		}
		var warp_colours = new Gdk.Color[colours.length-1];
		for (var it = 0; it < warp_colours.length; it++) {
			if (!Gdk.Color.parse(colours[it+1], out warp_colours[it])) {
				warning("Bad warp colour %s in %s\n", colours[it+1], filename);
				return null;
			}
		}

		weft_line[] wefts = {};
		string line;
		while ((line = file.read_line()) != null) {
			var parts = line.split(" ");
			Gdk.Color colour = {};
			if (parts.length != 2) {
				warning("Bad weft line `%s' in %s: wrong number of spaces\n", line, filename);
				return null;
			}
			if (parts[1].length != colours.length-1) {
				warning("Bad weft line `%s' in %s: wrong number of warps\n", line, filename);
				return null;
			}
			if (!Gdk.Color.parse(parts[0], out colour)) {
				warning("Bad weft color `%s' in %s\n", parts[0], filename);
				return null;
			}

			wefts += weft_line(colours.length, colour);

			for (var it = 0; it < colours.length; it++) {
				wefts[wefts.length-1].warps[it] = parts[1][it] == '|';
			}
		}
		if (wefts.length == 0) {
			warning("No weft lines in %s\n", filename);
			return null;
		}
		return new LoomPattern.array((owned) warp_colours, (owned) wefts);
	}

	public LoomPattern(int warps, int wefts, Gdk.Color weft_colour, Gdk.Color warp_colour) {
		warp_colours = new Gdk.Color[warps];
		for (var it = 0; it < warps; it++) {
			warp_colours[it] = warp_colour;
		}
		this.wefts = new weft_line[wefts];
		for (var it = 0; it < wefts; it++) {
			this.wefts[it] = weft_line(warps, weft_colour);
		}
	}

	LoomPattern.array(owned Gdk.Color[] colours, owned weft_line[] wefts) {
		warp_colours = (owned) colours;
		this.wefts = (owned) wefts;
	}

	public override bool button_press_event(Gdk.EventButton event) {
		if (event.type == Gdk.EventType.BUTTON_PRESS) {
			int warp = (int) (event.x/box_size)%warp_colours.length;
			int weft = (int) (event.y/box_size)%wefts.length;
			if (event.button == 1) {
				this.wefts[weft].warps[warp] = !this.wefts[weft].warps[warp];
				queue_draw();
			} else if (event.button == 3) {
				menu.warp = warp;
				menu.weft = weft;
				menu.show();
				menu.popup(null, null, null, event.button, event.time);
			} else {
				return false;
			}
			return true;
		}
		return false;
	}

	public void delete_warp(int position) requires(position >= 0 && position < warp_count) {
		if (warp_colours.length == 1)
			return;
		for (var it = 0; it < wefts.length; it++) {
			wefts[it].delete(position);
		}
		for (var it = position; it < warp_colours.length-1; it++) {
			warp_colours[it] = warp_colours[it+1];
		}
		warp_colours.resize(warp_colours.length-1);
		queue_resize();
	}

	public void delete_weft(int position) requires(position >= 0 && position < weft_count) {
		if (wefts.length == 1)
			return;
		for (var it = position; it < wefts.length-1; it++) {
			wefts[it] = (owned) wefts[it+1];
		}
		wefts[wefts.length-1] = {};
		wefts.resize(wefts.length-1);
		weft_count_changed(wefts.length);
		queue_resize();
	}

	public override bool expose_event(Gdk.EventExpose event) {
		var box_size = this.box_size;
		var context = Gdk.cairo_create(event.window);
		context.rectangle(event.area.x, event.area.y, event.area.width, event.area.height);
		context.clip();
		context.set_line_width(1);
		var max_wefts = allocation.height/box_size+1;
		var max_warps = allocation.width/box_size+1;
		for (var weft = 0; weft < max_wefts; weft++) {
			for (var warp = 0; warp < max_warps; warp++) {
				var top = wefts[weft%wefts.length].warps[warp%warp_colours.length];
				Gdk.cairo_set_source_color(context, top ? warp_colours[warp%warp_colours.length] : wefts[weft%wefts.length].colour);
				context.rectangle(warp*box_size, weft*box_size, box_size, box_size);
				context.fill();
				context.set_source_rgba(0, 0, 0, (weft < wefts.length && warp < warp_colours.length) ? 1 : 0.5);
				context.rectangle(warp*box_size, weft*box_size, box_size, box_size);
				context.stroke();
				if (top) {
					context.move_to(warp*box_size+box_size/2, weft*box_size+box_size/4);
					context.rel_line_to(0, box_size/2);
				} else {
					context.move_to(warp*box_size+box_size/4, weft*box_size+box_size/2);
					context.rel_line_to(box_size/2, 0);
				}
				context.stroke();
			}
		}
		return true;
	}

	public void insert_warp(int position, Gdk.Color? colour = null) requires(position >= 0 && position <= warp_count) {
		for (var it = 0; it < wefts.length; it++) {
			wefts[it].insert(position);
		}
		var new_warp_colours = new Gdk.Color[warp_colours.length+1];
		for (var it = 0; it < warp_colours.length; it++) {
			new_warp_colours[it+(it < position ? 0 : 1)] = warp_colours[it];
		}
		new_warp_colours[position] = colour ?? warp_colours[position == 0 ? 1 : position-1];
		warp_colours = (owned) new_warp_colours;
		queue_resize();
	}

	public void insert_weft(int position, Gdk.Color? colour = null) requires(position >= 0 && position <= weft_count) {
		var length = warp_colours.length;
		wefts.resize(wefts.length+1);
		for (var it = wefts.length-2; it >= position; it--) {
			wefts[it+1] = (owned) wefts[it];
		}
		wefts[position] = weft_line(length, colour ?? wefts[position == 0 ? 1 : position-1].colour);
		weft_count_changed(wefts.length);
		queue_resize();
	}

	public override void size_request(out Gtk.Requisition requisition) {
		requisition = Gtk.Requisition();
		requisition.width = warp_colours.length*box_size;
		requisition.height = wefts.length*box_size;
	}

	public override void realize() {
		var attrs = Gdk.WindowAttr() {
			window_type = Gdk.WindowType.CHILD,
			wclass = Gdk.WindowClass.INPUT_OUTPUT,
			event_mask = get_events()|Gdk.EventMask.EXPOSURE_MASK|Gdk.EventMask.BUTTON_PRESS_MASK
		};
		this.window = new Gdk.Window(get_parent_window(), attrs, 0);
		this.window.move_resize(this.allocation.x, this.allocation.y, this.allocation.width, this.allocation.height);
		this.window.set_user_data(this);
		this.style = this.style.attach(this.window);
		this.style.set_background(this.window, Gtk.StateType.NORMAL);
		set_flags(Gtk.WidgetFlags.REALIZED);
	}

	public new bool get(int warp, int weft) requires(warp >= 0 && warp<warp_count && weft >= 0 && weft < weft_count) {
		return wefts[weft].warps[warp];
	}

	public Gdk.Color get_warp_colour(int warp) requires(warp >= 0 && warp < warp_count) {
		return warp_colours[warp];
	}

	public Gdk.Color get_weft_colour(int weft) requires(weft >= 0 && weft < weft_count) {
		return wefts[weft].colour;
	}

	public new void set(int warp, int weft, bool @value) requires(warp >= 0 && warp<warp_count && weft >= 0 && weft < weft_count) {
		wefts[weft].warps[warp] = @value;
	}

	public void set_warp_colour(int warp, Gdk.Color colour) requires(warp >= 0 && warp < warp_count) {
		warp_colours[warp] = colour;
	}

	public void set_weft_colour(int weft, Gdk.Color colour) requires(weft >= 0 && weft < weft_count) {
		wefts[weft].colour = colour;
	}

	public void to_file(FileStream file) {
		file.printf("GACQUARD");
		foreach (var colour in warp_colours) {
			file.printf(" %s", colour.to_string());
		}
		file.putc('\n');
		for (var it = 0; it < wefts.length; it++) {
			wefts[it].to_file(file);
		}
	}
}

class LoomCard : Gtk.DrawingArea {
	weak Gacquard controller;
	internal LoomCard(Gacquard controller) {
		this.controller = controller;
		set_size_request(100, 100);
	}
	public override bool expose_event(Gdk.EventExpose event) {
		var cr = Gdk.cairo_create(event.window);
		var weft = (int) controller.card_scale.get_value() - 1;
		var card_cols = controller.card_cols;
		var card_rows = controller.card_rows;

		var width = allocation.width*1.0/card_cols;
		var height = allocation.height*1.0/card_rows;
		var radius = double.min(width, height)/2.1;

		var pattern = controller.pattern;
		if (pattern == null || weft < 0 || weft >= pattern.weft_count) {
			return true;
		}
		var warps = pattern.warp_count;
		Gdk.cairo_set_source_color(cr, pattern.get_weft_colour(weft));
		cr.rectangle(0,0, allocation.width, allocation.height);
		cr.fill();
		cr.set_source_rgb(0, 0, 0);
		for (var col = 0; col < card_cols; col++) {
			for (var row = 0; row < card_rows; row++) {
				cr.arc((col+0.5)*width, (row+0.5)*height, radius, 0, 2*Math.PI);
				if (pattern[(col*card_rows+row)%warps, weft]) {
					cr.fill();
				} else {
					cr.stroke();
				}
			}
		}
		return true;
	}
}


class Gacquard : Object {
	private const string APP_PATH = "/apps/gacquard";
	private const string COL_KEY = APP_PATH+"/cols";
	private const string ROW_KEY = APP_PATH+"/rows";
	private static int counts = 0;

	private Gtk.DrawingArea card;
	internal int card_cols;
	internal int card_rows;
	internal Gtk.Scale card_scale;
	private GConf.Client conf;
	private Gtk.Dialog create;
	private Gtk.SpinButton create_warp_spin;
	private Gtk.ColorSelection create_warp_colour;
	private Gtk.SpinButton create_weft_spin;
	private Gtk.ColorSelection create_weft_colour;
	private string? filename;
	private string? foldername;
	private LoomPattern? _pattern;
	private Gtk.HScale pattern_scale;
	private Gtk.Dialog prefs;
	private Gtk.ScrolledWindow pattern_window;
	private Gtk.Window window;

	internal LoomPattern? pattern {
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

		var bar = new Gtk.MenuBar();
		var file_menu = new Gtk.Menu();
		var accel_group = new Gtk.AccelGroup();
		window.add_accel_group(accel_group);

		var file = new Gtk.MenuItem.with_mnemonic("_File");
		var @new = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.NEW, null);
		var new_window = new Gtk.MenuItem.with_label("New Window");
		var open = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.OPEN, null);
		var save = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.SAVE, null);
		var save_as = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.SAVE_AS, null);
		var preferences = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.PREFERENCES, null);
		var sep = new Gtk.SeparatorMenuItem();
		var quit = new Gtk.ImageMenuItem.from_stock(Gtk.Stock.QUIT, accel_group);
		quit.add_accelerator("activate", accel_group, (uint) 'q', Gdk.ModifierType.CONTROL_MASK, Gtk.AccelFlags.VISIBLE);

		file.set_submenu(file_menu);
		file_menu.append(@new);
		file_menu.append(new_window);
		file_menu.append(open);
		file_menu.append(save);
		file_menu.append(save_as);
		file_menu.append(preferences);
		file_menu.append(sep);
		file_menu.append(quit);

		bar.append(file);

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
		card = new LoomCard(this);
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
					this.pattern = new LoomPattern(int.max((int)create_warp_spin.value, 1), int.max((int)create_weft_spin.value, 1), create_warp_colour.current_color, create_weft_colour.current_color);
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
						      var pattern = LoomPattern.open(chooser.get_filename());
						      if (pattern == null) {
							      var message = new Gtk.MessageDialog(window, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, "Unable to read file %s.", chooser.get_filename());
							      message.run();
							      message.hide();
						      } else {
							      this.filename = chooser.get_filename();
							      this.pattern = pattern;
						      }
					      }
					      chooser.hide();
				      });
		save.activate.connect(() => { save_file(false); });
		save_as.activate.connect(() => { save_file(true); });
		preferences.activate.connect(() => { prefs.run(); prefs.hide(); });
		quit.activate.connect(Gtk.main_quit);

		window.show_all();
	}

	void new_loom() {
		Gdk.Color warp_c;
		Gdk.Color weft_c;
		Gdk.Color.parse("SteelBlue", out warp_c);
		Gdk.Color.parse("white", out weft_c);
		filename = null;
		pattern = new LoomPattern(20, 10, warp_c, weft_c);
	}

	public void open(string filename) {
		var pattern = LoomPattern.open(filename);
		if (pattern == null) {
			var message = new Gtk.MessageDialog(window, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, "Unable to read file %s.", filename);
			message.run();
			message.hide();
		} else {
			this.filename = filename;
			this.pattern = pattern;
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
		var file = FileStream.open(filename, "w");
		if (file == null) {
			var message = new Gtk.MessageDialog(window, Gtk.DialogFlags.MODAL, Gtk.MessageType.ERROR, Gtk.ButtonsType.CLOSE, "Unable to write to file %s.", filename);
			message.run();
			message.hide();
		} else {
			pattern.to_file(file);
		}
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
	for (var it = 1; it < args.length; it++) {
		var window = new Gacquard();
		window.open(args[it]);
	}

	if (args.length < 2) {
		new Gacquard();
	}
	Gtk.main();
}
