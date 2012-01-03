namespace Loom {
	const string CLIP_URI = "application/x-gacquard";

	public delegate bool BoolFunc(bool old);

	public delegate void EndOfLineFunc();

	public enum Action {
		COLOUR,
		COPY,
		DELETE,
		INSERT_AFTER,
		INSERT_BEFORE,
		INVERT,
		PASTE,
		SET_WARP,
		SET_WEFT
	}

	public enum Area {
		WARP,
		WEFT,
		SELECTION
	}

	public delegate void CircFunc<T>(int index, ref T item);
	public delegate void CircFillFunc<T>(int index, out T item);

	public class Circular<T> : Object {
		private T[] items;

		public int length {
			get {
				return items.length;
			}
		}

		public Circular(int length = 1) {
			items = new T[length];
		}

		public Circular.from_array(owned T[] array) {
			items = (owned) array;
		}

		public void foreach(CircFunc<T> func, int start = 0, int stop = -1) {
			start = start % items.length;
			stop = stop % items.length;
			if (stop < 0) {
				stop = (stop + items.length) % items.length;
			}
			for (var it = start; it <= (stop < start ? items.length - 1 : stop); it++) {
				func(it, ref items[it]);
			}
			if (stop < start) {
				for (var it = 0; it <= stop; it++) {
					func(it, ref items[it]);
				}
			}
		}

		public void fill(CircFillFunc<T> func, int start = 0, int stop = -1) {
			start = start % items.length;
			stop = stop % items.length;
			if (stop < 0) {
				stop = (stop + items.length) % items.length;
			}
			for (var it = start; it <= (stop < start ? items.length - 1 : stop); it++) {
				func(it, out items[it]);
			}
			if (stop < start) {
				for (var it = 0; it <= stop; it++) {
					func(it, out items[it]);
				}
			}
		}

		public new T get(int index) {
			return items[(index + items.length) % items.length];
		}

		public new void set(int index, T @value) {
			items[(index + items.length) % items.length] = @value;
		}

		public void insert(int position, int length, CircFillFunc<T> func) requires (length > 0) {
			position = ((position % items.length) + items.length) % items.length;
			var old_length = items.length;
			items.resize(items.length + length);
			for (var it = old_length - 1; it >= position; it--) {
				items[it + length] = (owned) items[it];
			}
			for (var it = 0; it < length; it++) {
				func(it + position, out items[it + position]);
			}
		}

		public void @delete(int position, int length) requires (length < items.length) {
			position = ((position % items.length) + items.length) % items.length;
			if (position + length > items.length) {
				for (var it = 0; it < length; it++) {
					items[it] = (owned) items[it + length];
				}
				for (var it = length; it < items.length; it++) {
					items[it] = null;
				}
			} else {
				for (var it = 0; it < length; it++) {
					items[it + position] = null;
				}
				for (var it = position; it < items.length - length; it++) {
					items[it] = (owned) items[it + length];
				}
			}
			items.resize(items.length - length);
		}
	}

	class Weft : Object {
		internal Gdk.Color colour { get; set; }
		Circular<bool> warps;

		internal Weft(int length, Gdk.Color colour) {
			warps = new Circular<bool>(length);
			this.colour = colour;
		}

		internal void delete(int position, int length) {
			warps.delete(position, length);
		}

		internal void foreach(CircFunc<bool> func, int start, int stop) {
			warps.foreach(func, start, stop);
		}

		internal new bool get(int index) {
			return warps[index];
		}

		internal void insert(int position) {
			warps.insert(position, 1, (it, out warp) => warp = false);
		}

		internal new void set(int index, bool? @value) {
			if (@value == null) {
				warps[index] = !warps[index];
			} else {
				warps[index] = @value;
			}
		}

		internal void to_file(FileStream file) {
			unowned FileStream ufile = file;
			file.printf("%s ", colour.to_string());
			warps.foreach((it, b) => ufile.printf("%c", b ? '|' : '-'));
			file.putc('\n');
		}
	}

	private class ClipOwner : Object {
		private uint8[] data;
		internal ClipOwner(uint8[] data) {
			this.data = data;
		}

		public void get_clip_data(Gtk.Clipboard clipboard, Gtk.SelectionData selection_data, uint info) {
			selection_data.set(selection_data.target, 8, data);
		}
	}

	public class Pattern : Gtk.Widget {

		private Gtk.Clipboard clipboard;

		internal Circular<Gdk.Color?> warp_colours;

		internal Circular<Weft> wefts;

		public int box_size { get; set; default = 30; }

		internal int start_weft = -1;

		internal int start_warp = -1;

		internal int stop_weft = -1;

		internal int stop_warp = -1;

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
			clipboard = Gtk.Clipboard.get_for_display(this.get_display(), Gdk.SELECTION_CLIPBOARD);
		}

		public static Pattern? open(string filename) {
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
			var warp_colours = new Circular<Gdk.Color?>(colours.length-1);
			for (var it = 0; it < warp_colours.length; it++) {
				Gdk.Color colour;
				if (!Gdk.Color.parse(colours[it+1], out colour)) {
					warning("Bad warp colour %s in %s\n", colours[it + 1], filename);
					return null;
				}
				warp_colours[it] = colour;
			}

			Weft[] wefts = {};
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

				wefts += new Weft(colours.length, colour);

				for (var it = 0; it < colours.length; it++) {
					wefts[wefts.length-1][it] = parts[1][it] == '|';
				}
			}
			if (wefts.length == 0) {
				warning("No weft lines in %s\n", filename);
				return null;
			}
			return new Pattern.array(warp_colours, new Circular<Weft>.from_array((owned) wefts));
		}

		public Pattern(int warps, int wefts, Gdk.Color weft_colour, Gdk.Color warp_colour) {
			warp_colours = new Circular<Gdk.Color?>(warps);
			warp_colours.fill((it, out v) => v = warp_colour);
			this.wefts = new Circular<Weft>(wefts);
			this.wefts.fill ((it, out weft) => weft = new Weft(warps, weft_colour));
		}

		Pattern.array(Circular<Gdk.Color?> colours, Circular<Weft> wefts) {
			warp_colours = colours;
			this.wefts = wefts;
		}

		public override bool button_press_event(Gdk.EventButton event) {
			if (event.type == Gdk.EventType.BUTTON_PRESS) {
				if (event.button == 1) {
					start_warp = (int) (event.x / box_size) % warp_colours.length;
					start_weft = (int) (event.y / box_size) % wefts.length;
					return true;
				}
			}
			return false;
		}

		public override bool button_release_event(Gdk.EventButton event) {
			if (event.button == 1) {
				stop_warp = (int) (event.x / box_size) % warp_colours.length;
				stop_weft = (int) (event.y / box_size) % wefts.length;
				if (start_warp == stop_warp && start_weft == stop_weft) {
					this.wefts[start_weft][start_warp] = null;
					start_warp = -1;
					start_weft = -1;
				}
				queue_draw();
				return true;
			} else if (event.button == 2) {
				start_warp = (int) (event.x / box_size) % warp_colours.length;
				start_weft = (int) (event.y / box_size) % wefts.length;
				do_action(Action.PASTE, Area.SELECTION);
				return true;
			}
			return false;
		}

		bool choose_colour(ref Gdk.Color colour, string title) {
			var dialog = new Gtk.ColorSelectionDialog(title);
			((Gtk.ColorSelection)dialog.color_selection).current_color = colour;
			if (dialog.run() == Gtk.ResponseType.OK) {
				colour = ((Gtk.ColorSelection)dialog.color_selection).current_color;
				dialog.destroy();
				return true;
			} else {
				dialog.destroy();
				return false;
			}
		}

		private void do_on_area(Area area, BoolFunc func, EndOfLineFunc? end_of_line = null) {
			var sub_warp = area == Area.WARP || area == Area.SELECTION;
			var sub_weft = area == Area.WEFT || area == Area.SELECTION;
			if (sub_warp && (start_warp == -1 || stop_warp == -1) || sub_weft && (start_weft == -1 || stop_weft == -1))
				return;
			wefts.foreach((i, ref weft) => { weft.foreach((j, ref warp) => warp = func(warp), sub_warp ? start_warp : 0, sub_warp ? stop_warp : -1); if (end_of_line != null) end_of_line(); }, sub_weft ? start_weft : 0, sub_weft ? stop_weft : -1);
		}

		public void do_action(Action action, Area area) {
			switch(action) {
				case Action.INVERT:
					do_on_area(area, (v) => { return !v; });
					break;
				case Action.SET_WARP:
					do_on_area(area, (v) => { return true; });
					break;
				case Action.SET_WEFT:
					do_on_area(area, (v) => { return false; });
					break;
				case Action.DELETE:
					switch (area) {
						case Area.WARP:
							if (start_warp != -1) {
								delete_warp(start_warp, (stop_warp - start_warp + warp_colours.length) % warp_colours.length + 1);
								start_warp = -1;
							}
							break;
						case Area.WEFT:
							if (start_weft != -1) {
								delete_weft(start_weft, (stop_weft - start_weft + wefts.length) % wefts.length + 1);
								start_weft = -1;
							}
							break;
					}
					break;
				case Action.COLOUR:
					switch (area) {
						case Area.WARP:
							if (start_warp != -1) {
								Gdk.Color colour = warp_colours[start_warp];
								if (choose_colour(ref colour, "Select Warp Colour")) {
									for (var it = start_warp; it <= stop_warp; it++) {
										warp_colours[it] = colour;
									}
								}
							}
							break;
						case Area.WEFT:
							if (start_weft != -1) {
								var colour = wefts[start_weft].colour;
								if (choose_colour(ref colour, "Select Weft Colour")) {
									for (var it = start_weft; it <= stop_weft; it++) {
										wefts[it].colour = colour;
									}
								}
							}
							break;
						}
						break;
				case Action.COPY:
					var buffer = new StringBuilder();
					do_on_area(area, (v) => { buffer.append_c(v ? '|' : '-'); return v; }, () => buffer.append_c('\n'));
					if (buffer.len > 0) {
							var clip = new ClipOwner(buffer.str.data);
							clip.ref();
							var result = clipboard.set_with_owner(new Gtk.TargetEntry[] { Gtk.TargetEntry() { target = CLIP_URI, flags = 0, info = area}}, (clipboard, selection, info, user) => ((ClipOwner)user).get_clip_data(clipboard, selection, info), (clipboard, user) => ((ClipOwner)user).unref(), clip);
							if (!result) {
								warning("Failed to set clipboard.");
							}
					}
					break;
				case Action.PASTE:
					if (start_warp == -1 || start_weft == -1) {
						start_warp = -1;
						start_weft = -1;
						stop_warp = -1;
						stop_weft = -1;
						return;
					}
					clipboard.request_contents(Gdk.Atom.intern_static_string(CLIP_URI), this.receive_paste);
					break;
				case Action.INSERT_BEFORE:
					switch (area) {
						case Area.WARP:
							if (start_warp != -1) {
								insert_warp(start_warp);
								start_warp++;
								stop_warp = stop_warp == -1 ? -1 : (stop_warp+1);
							}
							break;
						case Area.WEFT:
							if (start_weft != -1) {
								insert_weft(start_weft);
								start_weft++;
								stop_weft = stop_weft == -1 ? -1 : (stop_weft+1);
							}
							break;
						}
						break;
				case Action.INSERT_AFTER:
					switch (area) {
						case Area.WARP:
							if (start_warp != -1) {
								insert_warp(int.max(start_warp, stop_warp)+1);
							}
							break;
						case Area.WEFT:
							if (start_weft != -1) {
								insert_weft(int.max(start_weft, stop_weft)+1);
							}
							break;
						}
					break;
			}
			queue_draw();
		}

		void receive_paste(Gtk.Clipboard clipboard, Gtk.SelectionData selection) {
			if (selection.length == -1 || start_warp == -1 || start_weft == -1) {
				start_warp = -1;
				start_weft = -1;
				stop_warp = -1;
				stop_weft = -1;
				this.queue_draw();
				return;
			}
			var curr_warp = start_warp;
			for (var it = 0; it < selection.length; it++) {
				var c = selection.data[it];
				if (c == '\n') {
					start_weft++;
					curr_warp = start_warp;
				} else if (c == '|' || c == '-') {
					wefts[start_weft][curr_warp++] = c == '|';
				} else {
					warning("Got bad character `%c' from clipboard.\n", c);
				}
			}
			this.queue_draw();
			start_warp = -1;
			start_weft = -1;
			stop_warp = -1;
			stop_weft = -1;
		}
		public void delete_warp(int position, int length = 1) {
			assert(position >= 0 && position < warp_count && length > 0);
			if (warp_colours.length - length < 1)
				return;
			warp_colours.delete(position, length);
			wefts.foreach((it, ref weft) => weft.delete(position, length));
			queue_resize();
		}

		public void delete_weft(int position, int length = 1) requires (position >= 0 && position < weft_count && length > 0) {
			if (wefts.length-length < 1)
				return;
			wefts.delete(position, length);
			weft_count_changed(wefts.length);
			queue_resize();
		}

		public override bool expose_event(Gdk.EventExpose event) {
			var box_size = this.box_size;
			var context = Gdk.cairo_create(event.window);
			context.rectangle(event.area.x, event.area.y, event.area.width, event.area.height);
			context.clip();
			context.set_line_width(1);
			var max_wefts = allocation.height / box_size + 1;
			var max_warps = allocation.width / box_size + 1;
			for (var weft = 0; weft < max_wefts; weft++) {
				for (var warp = 0; warp < max_warps; warp++) {
					var norm_weft = weft % wefts.length;
					var norm_warp = warp % warp_colours.length;
					var top = wefts[weft][warp];
					Gdk.cairo_set_source_color(context, top ? warp_colours[norm_warp] : wefts[norm_weft].colour);
					context.rectangle(warp * box_size, weft * box_size, box_size, box_size);
					context.fill();
					context.set_source_rgba(0, 0, 0, (weft < wefts.length && warp < warp_colours.length) ? 1 : 0.5);
					context.rectangle(warp * box_size, weft * box_size, box_size, box_size);
					var selected_weft = start_weft != -1 && (start_weft <= stop_weft ? (norm_weft >= start_weft && norm_weft <= stop_weft) : (norm_weft >= start_weft || norm_weft <= stop_weft));
					var selected_warp = start_warp != -1 && (start_warp <= stop_warp ? (norm_warp >= start_warp && norm_warp <= stop_warp) : (norm_warp >= start_warp || norm_warp <= stop_warp));
					if (selected_warp || selected_weft) {
						double dash_length = box_size / (selected_warp && selected_weft ? 8 : 4);
						context.set_dash(new double[] { dash_length, dash_length / 2 }, 0);
					}
					context.stroke();
					context.set_dash(null, 0);
					if (top) {
						context.move_to(warp * box_size + box_size / 2, weft * box_size + box_size / 4);
						context.rel_line_to(0, box_size / 2);
					} else {
						context.move_to(warp * box_size + box_size / 4, weft * box_size + box_size / 2);
						context.rel_line_to(box_size / 2, 0);
					}
					context.stroke();
				}
			}
			return true;
		}

		public void insert_warp(int position, Gdk.Color? colour = null) requires (position >= 0 && position <= warp_count) {
			for (var it = 0; it < wefts.length; it++) {
				wefts[it].insert(position);
			}
			Gdk.Color new_colour = colour ?? warp_colours[position == 0 ? 1 : position - 1];
			warp_colours.insert(position, 1, (it, out warp_colour) => warp_colour = new_colour);
			queue_resize();
		}

		public void insert_weft(int position, Gdk.Color? colour = null) requires (position >= 0 && position <= weft_count) {
			Gdk.Color new_colour = colour ?? wefts[position == 0 ? 1 : position - 1].colour;
			wefts.insert(position, 1, (it, out weft) => weft = new Weft(warp_colours.length, new_colour));
			weft_count_changed(wefts.length);
			queue_resize();
		}

		public override void size_request(out Gtk.Requisition requisition) {
			requisition = Gtk.Requisition();
			requisition.width = warp_colours.length*box_size;
			requisition.height = wefts.length*box_size;
		}

		public override bool motion_notify_event(Gdk.EventMotion event) {
			if (Gdk.ModifierType.BUTTON1_MASK in event.state) {
				stop_warp = (int) (event.x/box_size)%warp_colours.length;
				stop_weft = (int) (event.y/box_size)%wefts.length;
				queue_draw();
				return true;
			}
			return false;
		}

		public override void realize() {
			var attrs = Gdk.WindowAttr() {
				window_type = Gdk.WindowType.CHILD,
										wclass = Gdk.WindowClass.INPUT_OUTPUT,
										event_mask = get_events()|Gdk.EventMask.EXPOSURE_MASK|Gdk.EventMask.BUTTON_PRESS_MASK|Gdk.EventMask.BUTTON_RELEASE_MASK|Gdk.EventMask.BUTTON_MOTION_MASK
			};
			this.window = new Gdk.Window(get_parent_window(), attrs, 0);
			this.window.move_resize(this.allocation.x, this.allocation.y, this.allocation.width, this.allocation.height);
			this.window.set_user_data(this);
			this.style = this.style.attach(this.window);
			this.style.set_background(this.window, Gtk.StateType.NORMAL);
			set_flags(Gtk.WidgetFlags.REALIZED);
		}

		public new bool get(int warp, int weft) requires (warp >= 0 && warp < warp_count && weft >= 0 && weft < weft_count) {
			return wefts[weft][warp];
		}

		public Gdk.Color get_warp_colour(int warp) requires (warp >= 0 && warp < warp_count) {
			return warp_colours[warp];
		}

		public Gdk.Color get_weft_colour(int weft) requires (weft >= 0 && weft < weft_count) {
			return wefts[weft].colour;
		}

		public new void set(int warp, int weft, bool @value) requires (warp >= 0 && warp<warp_count && weft >= 0 && weft < weft_count) {
			wefts[weft][warp] = @value;
		}

		public void set_warp_colour(int warp, Gdk.Color colour) requires (warp >= 0 && warp < warp_count) {
			warp_colours[warp] = colour;
		}

		public void set_weft_colour(int weft, Gdk.Color colour) requires (weft >= 0 && weft < weft_count) {
			wefts[weft].colour = colour;
		}

		public void to_file(FileStream file) {
			unowned FileStream ufile = file;
			file.printf("GACQUARD");
			warp_colours.foreach((it, ref colour) => ufile.printf(" %s", colour.to_string()));
			file.putc('\n');
			wefts.foreach((it, ref weft) => weft.to_file(ufile));
		}
	}

	public interface PatternContainer {
		public abstract void get_pattern_container(out Pattern? pattern, out int rows, out int cols, out int weft);
	}

	public class CardView : Gtk.DrawingArea {
		weak PatternContainer container;
		internal CardView(PatternContainer container) {
			this.container = container;
			set_size_request(100, 100);
		}

		public override bool expose_event(Gdk.EventExpose event) {
			var cr = Gdk.cairo_create(event.window);
			int weft;
			int card_cols;
			int card_rows;
			Pattern? pattern;
			container.get_pattern_container(out pattern, out card_rows, out card_cols, out weft);

			var width = allocation.width*1.0/card_cols;
			var height = allocation.height*1.0/card_rows;
			var radius = double.min(width, height)/2.1;

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
}
