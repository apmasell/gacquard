VALA_SOURCES=gacquard.vala loom.vala
gacquard: $(VALA_SOURCES)
	valac -g --save-temps -o $@ $^ --pkg gtk+-2.0 --pkg gconf-2.0

clean:
	rm -f gacquard $(VALA_SOURCES:.vala=.c)
