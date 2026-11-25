APP := Lumen.app/Contents
SOURCES := $(wildcard Sources/*.swift)
export MACOSX_DEPLOYMENT_TARGET := 14.0

.PHONY: build
build: $(APP)/MacOS/Lumen $(APP)/Info.plist
	codesign --force --sign - Lumen.app

$(APP)/MacOS/Lumen: $(SOURCES) Makefile
	mkdir -p $(APP)/MacOS .build/modules
	xcrun swiftc -O -swift-version 5 -module-cache-path .build/modules -o $@ $(SOURCES)

$(APP)/Info.plist: Info.plist
	mkdir -p $(APP)
	cp $< $@

.PHONY: test
test: .build/persistence-check build
	sh Tests/Persistence/run.sh $<

.build/persistence-check: Sources/Reader.swift $(wildcard Tests/Persistence/*.swift) Makefile
	mkdir -p .build/modules
	xcrun swiftc -swift-version 5 -module-cache-path .build/modules -o $@ Sources/Reader.swift $(wildcard Tests/Persistence/*.swift)
