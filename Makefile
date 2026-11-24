APP := Folio.app/Contents
SOURCES := $(wildcard Sources/*.swift)
export MACOSX_DEPLOYMENT_TARGET := 14.0

.PHONY: build
build: $(APP)/MacOS/Folio $(APP)/Info.plist
	codesign --force --sign - Folio.app

$(APP)/MacOS/Folio: $(SOURCES) Makefile
	mkdir -p $(APP)/MacOS .build/modules
	xcrun swiftc -O -swift-version 5 -module-cache-path .build/modules -o $@ $(SOURCES)

$(APP)/Info.plist: Info.plist
	mkdir -p $(APP)
	cp $< $@

.PHONY: test
test: .build/persistence-check
	sh Tests/Persistence/run.sh $<

.build/persistence-check: Sources/Reader.swift Tests/Persistence/main.swift Makefile
	mkdir -p .build/modules
	xcrun swiftc -swift-version 5 -module-cache-path .build/modules -o $@ Sources/Reader.swift Tests/Persistence/main.swift
