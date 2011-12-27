namespace Loom {
	public delegate bool BoolFunc(bool old);

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

	struct weft_line {
		Gdk.Color colour;
		bool[] warps;

		internal weft_line(int length, Gdk.Color colour) {
			warps = new bool[length];
			this.colour = colour;
		}

		internal void delete(int position, int length) {
			for (var it = position; it < warps.length-length; it++) {
				warps[it] = warps[it+length];
			}
			warps.resize(warps.length-length);
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

	public class Pattern : Gtk.Widget {

		private Gdk.Color[] warp_colours;

		private weft_line[] wefts;

		public int box_size { get; set; default = 30; }

		private int start_weft = -1;

		private int start_warp = -1;

		private int stop_weft = -1;

		private int stop_warp = -1;

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
			return new Pattern.array((owned) warp_colours, (owned) wefts);
		}

		public Pattern(int warps, int wefts, Gdk.Color weft_colour, Gdk.Color warp_colour) {
			warp_colours = new Gdk.Color[warps];
			for (var it = 0; it < warps; it++) {
				warp_colours[it] = warp_colour;
			}
			this.wefts = new weft_line[wefts];
			for (var it = 0; it < wefts; it++) {
				this.wefts[it] = weft_line(warps, weft_colour);
			}
		}

		Pattern.array(owned Gdk.Color[] colours, owned weft_line[] wefts) {
			warp_colours = (owned) colours;
			this.wefts = (owned) wefts;
		}

		public override bool button_press_event(Gdk.EventButton event) {
			if (event.type == Gdk.EventType.BUTTON_PRESS) {
				if (event.button == 1) {
					start_warp = (int) (event.x/box_size)%warp_colours.length;
					start_weft = (int) (event.y/box_size)%wefts.length;
					return true;
				}
			}
			return false;
		}

		public override bool button_release_event(Gdk.EventButton event) {
			stop_warp = (int) (event.x/box_size)%warp_colours.length;
			stop_weft = (int) (event.y/box_size)%wefts.length;
			if (event.button == 1) {
				if (start_warp == stop_warp && start_weft == stop_weft) {
					this.wefts[start_weft].warps[start_warp] = !this.wefts[start_weft].warps[start_warp];
					start_warp = -1;
					start_weft = -1;
				}
				queue_draw();
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

		private void do_on_area(Area area, BoolFunc func) {
			switch(area) {
				case Area.WARP:
					if (start_warp == -1)
						return;
					for(var warp = start_warp; warp <= stop_warp; warp++) {
						for(var weft = 0; weft < wefts.length; weft++) {
							wefts[weft].warps[warp] = func(wefts[weft].warps[warp]);
						}
					}
					break;
				case Area.WEFT:
					if (start_weft == -1)
						return;
					for(var weft = start_weft; weft <= stop_weft; weft++) {
						for(var warp = 0; warp < warp_colours.length; warp++) {
							wefts[weft].warps[warp] = func(wefts[weft].warps[warp]);
						}
					}
					break;
				case Area.SELECTION:
					if (start_warp == -1 || start_weft == -1)
						return;
					for(var weft = start_weft; weft <= stop_weft; weft++) {
						for(var warp = start_warp; warp <= stop_warp; warp++) {
							wefts[weft].warps[warp] = func(wefts[weft].warps[warp]);
						}
					}
					break;
			}
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
								delete_warp(start_warp, stop_warp-start_warp+1);
								start_warp = -1;
							}
							break;
						case Area.WEFT:
							if (start_weft != -1) {
								delete_weft(start_weft, stop_weft-start_weft+1);
								start_weft = -1;
							}
							break;
					}
					break;
				case Action.COLOUR:
					switch (area) {
						case Area.WARP:
							if (start_warp != -1) {
								if (choose_colour(ref warp_colours[start_warp], "Select Warp Colour")) {
									for (var it = start_warp+1; it <= stop_warp; it++) {
										warp_colours[it] = warp_colours[start_warp];
									}
								}
							}
							break;
						case Area.WEFT:
							if (start_weft != -1) {
								if (choose_colour(ref wefts[start_weft].colour, "Select Weft Colour")) {
									for (var it = start_weft+1; it <= stop_weft; it++) {
										wefts[it].colour = wefts[start_weft].colour;
									}
								}
							}
							break;
						}
						break;
				case Action.COPY:
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

		public void delete_warp(int position, int length = 1) requires(position >= 0 && position < warp_count && length > 0) {
			if (warp_colours.length-length < 1)
				return;
			for (var it = 0; it < wefts.length; it++) {
				wefts[it].delete(position, length);
			}
			for (var it = position; it < warp_colours.length-length; it++) {
				warp_colours[it] = warp_colours[it+length];
			}
			for (var it = 1; it <= length; it++) {
				warp_colours[warp_colours.length-it] = {};
			}
			warp_colours.resize(warp_colours.length-length);
			queue_resize();
		}

		public void delete_weft(int position, int length = 1) requires(position >= 0 && position < weft_count && length > 0) {
			if (wefts.length-length < 1)
				return;
			for (var it = position; it < wefts.length-length; it++) {
				wefts[it] = (owned) wefts[it+length];
			}
			for (var it = 1; it <= length; it++) {
				wefts[wefts.length-it] = {};
			}
			wefts.resize(wefts.length-length);
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
					var norm_weft = weft%wefts.length;
					var norm_warp = warp%warp_colours.length;
					var top = wefts[norm_weft].warps[norm_warp];
					Gdk.cairo_set_source_color(context, top ? warp_colours[norm_warp] : wefts[norm_weft].colour);
					context.rectangle(warp*box_size, weft*box_size, box_size, box_size);
					context.fill();
					context.set_source_rgba(0, 0, 0, (weft < wefts.length && warp < warp_colours.length) ? 1 : 0.5);
					context.rectangle(warp*box_size, weft*box_size, box_size, box_size);
					var selected_weft = start_weft != -1 && (start_weft <= stop_weft ? (norm_weft >= start_weft && norm_weft <= stop_weft) : (norm_weft >= start_weft || norm_weft <= stop_weft));
					var selected_warp = start_warp != -1 && (start_warp <= stop_warp ? (norm_warp >= start_warp && norm_warp <= stop_warp) : (norm_warp >= start_warp || norm_warp <= stop_warp));
					if (selected_warp || selected_weft) {
						double dash_length = box_size / (selected_warp && selected_weft ? 8 : 4);
						context.set_dash(new double[] { dash_length, dash_length/2 }, 0);
					}
					context.stroke();
					context.set_dash(null, 0);
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
