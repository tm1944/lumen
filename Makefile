APP := Folio.app/Contents
SOURCES := $(wildcard Sources/*.swift)

.PHONY: build
build: $(APP)/MacOS/Folio $(APP)/Info.plist
	codesign --force --sign - Folio.app

$(APP)/MacOS/Folio: $(SOURCES)
	mkdir -p $(APP)/MacOS .build/modules
	xcrun swiftc -O -swift-version 5 -module-cache-path .build/modules -o $@ $(SOURCES)

$(APP)/Info.plist: Info.plist
	mkdir -p $(APP)
	cp $< $@
