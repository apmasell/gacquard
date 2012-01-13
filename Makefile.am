NULL =
ACLOCAL_AMFLAGS = -I m4

bin_PROGRAMS = gacquard

applicationsdir = $(datadir)/applications
applications_DATA = \
	gacquard.desktop \
	$(NULL)

mimedir = $(datadir)/mime/packages
mime_DATA = \
	andremasella-gacquard.xml \
	$(NULL)

gacquard_VALAFLAGS = \
	--pkg gconf-2.0 \
	--pkg gtk+-2.0 \
	$(NULL)

gacquard_CPPFLAGS = \
	$(GCONF_CFLAGS) \
	$(GTK_CFLAGS) \
	$(NULL)

gacquard_LDFLAGS = \
	$(GCONF_LIBS) \
	$(GTK_LIBS) \
	$(NULL)

gacquard_SOURCES = \
	gacquard.vala \
	loom.vala \
	$(NULL)

schemadir = $(GCONF_SCHEMA_FILE_DIR)
schema_DATA = gacquard.schemas

man_MANS = \
	gacquard.1 \
	$(NULL)

EXTRA_DIST = \
	$(applications_DATA) \
	$(man_MANS)	 \
	$(mime_DATA) \
	$(schema_DATA) \
	$(NULL)

if GCONF_SCHEMAS_INSTALL
install-data-local:
	GCONF_CONFIG_SOURCE=$(GCONF_SCHEMA_CONFIG_SOURCE) $(GCONFTOOL) --makefile-install-rule $(schema_DATA)
endif
