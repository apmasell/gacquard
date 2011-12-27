gacquard: gacquard.vala loom.vala
	valac -g --save-temps -o $@ $^ --pkg gtk+-2.0 --pkg gconf-2.0

clean:
	rm -f gacquard gacquard.c
