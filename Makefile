ifneq ($(realpath .env),)
include .env
endif

PATH  := $(PATH):/usr/local/libexec:/usr/libexec
SHELL := PATH='$(PATH)' $(SHELL) -o 'pipefail'

INC_DIR = inc
LIB_DIR = lib
OUT_DIR = out
SRC_DIR = src
TMP_DIR = tmp

LUAJIT ?= /usr/local/bin/luajit

CC                ?= $(shell xcrun -f clang)
CODESIGN          ?= $(shell xcrun -f codesign)
INSTALL_NAME_TOOL ?= $(shell xcrun -f install_name_tool)
LIPO              ?= $(shell xcrun -f lipo)
NOTARYTOOL        ?= $(shell xcrun -f notarytool)
STAPLER           ?= $(shell xcrun -f stapler)

ARCHES                   ?= $(shell '$(LIPO)' -detailed_info '$(LIB_DIR)/libluajit-5.1.2.dylib' | awk '$$1 == "Non-fat" { print $$NF; }; $$1 == "architecture" { print $$2; };' | sort)
MACOSX_DEPLOYMENT_TARGET ?= 10.15
SDK_PATH                 ?= $(shell xcrun --show-sdk-path)

EMBEDDED_PLIST         ?= $(shell openssl smime -verify -noverify -inform 'der' -in '$(SRC_DIR)/embedded.provisionprofile')
APPLICATION_IDENTIFIER ?= $(shell PlistBuddy -c 'Print :Entitlements:com.apple.application-identifier' '/dev/stdin' <<< '$(EMBEDDED_PLIST)')
TEAM_IDENTIFIER        ?= $(shell PlistBuddy -c 'Print :Entitlements:com.apple.developer.team-identifier' '/dev/stdin' <<< '$(EMBEDDED_PLIST)')
PROFILE_NAME           ?= $(shell PlistBuddy -c 'Print :Name' '/dev/stdin' <<< '$(EMBEDDED_PLIST)')
TEAM_NAME              ?= $(shell PlistBuddy -c 'Print :TeamName' '/dev/stdin' <<< '$(EMBEDDED_PLIST)')

BUNDLE_NAME       ?= $(PROFILE_NAME)
BUNDLE_IDENTIFIER ?= $(shell cut -d '.' -f '2-' <<< '$(APPLICATION_IDENTIFIER)')
BUNDLE_COPYRIGHT  ?= $(shell date +'© %Y $(TEAM_NAME). All rights reserved.')

KEYCHAIN_PROFILE ?= $(TEAM_IDENTIFIER)
SIGNING_IDENTITY ?= $(TEAM_IDENTIFIER)

all: clean build
.PHONY: all

build: $(OUT_DIR)/$(BUNDLE_NAME).app
.PHONY: build

clean:
	rm -Rf '$(INC_DIR)' '$(LIB_DIR)' '$(OUT_DIR)' '$(TMP_DIR)'
.PHONY: clean

$(INC_DIR) $(LIB_DIR) $(OUT_DIR) $(TMP_DIR) $(TMP_DIR)/$(BUNDLE_NAME).app/Contents $(TMP_DIR)/$(BUNDLE_NAME).app/Contents/Frameworks $(TMP_DIR)/$(BUNDLE_NAME).app/Contents/MacOS:
	mkdir -p '$@'

$(INC_DIR)/%.h: /usr/local/include/luajit-2.1/%.h | $(INC_DIR)
	cp -f '$<' '$@'

$(LIB_DIR)/%.dylib: /usr/local/lib/%.dylib | $(LIB_DIR)
	cp -f '$<' '$@'

$(TMP_DIR)/0: | $(TMP_DIR)
	printf '\0' > '$@'

$(TMP_DIR)/Info.plist: $(SRC_DIR)/Info.plist | $(TMP_DIR)
	cp -f '$<' '$@!'
	PlistBuddy -c 'Add :CFBundleExecutable string "$(BUNDLE_NAME)"' '$@!'
	PlistBuddy -c 'Add :CFBundleIdentifier string "$(BUNDLE_IDENTIFIER)"' '$@!'
	PlistBuddy -c 'Add :CFBundleName string "$(BUNDLE_NAME)"' '$@!'
	PlistBuddy -c 'Add :NSHumanReadableCopyright string "$(BUNDLE_COPYRIGHT)"' '$@!'
	mv -f '$@'{'!',''}

$(TMP_DIR)/$(BUNDLE_NAME).entitlements: $(SRC_DIR)/$(BUNDLE_NAME).entitlements | $(TMP_DIR)
	cp -f '$<' '$@!'
	PlistBuddy -c 'Add :com.apple.application-identifier string "$(APPLICATION_IDENTIFIER)"' '$@!'
	mv -f '$@'{'!',''}

$(TMP_DIR)/EndpointSecurity.i: $(SRC_DIR)/EndpointSecurity.h | $(TMP_DIR)
	'$(CC)' -E -o'$@' '$<'

$(TMP_DIR)/cdef.i: $(TMP_DIR)/EndpointSecurity.i
	cat '$<' | grep -Ev '^#' | tr '\n' '\t' | sed -E -e 's/extern [^;]+;//g' -e 's/static const [^;]+;//g' -e 's/static inline [^}]+}//g' | tr '\t' '\n' | grep -Ev '^$$' | sed -E -e 's/enum : [^ ]+/enum/g' -e 's/\(\^/(*/g' -e 's/([ *])_N(onnull|ullable) /\1 /g' -e 's/__attribute__\s*\(\(.+\)\)\s*//g' > '$@'

$(TMP_DIR)/cdef.h: $(TMP_DIR)/cdef.i $(TMP_DIR)/0
	cat $(patsubst %,'%',$(subst ','"'"',$^)) | xxd -i -n 'cdef_i' -u | sed -E -e 's/ 0X/ 0x/g' -e 's/([0-9A-F])$$/\1,/g' -e 's/^unsigned char /const char /g' -e '/^unsigned int /d' > '$@'

$(TMP_DIR)/prelude.luac: $(SRC_DIR)/prelude.lua | $(TMP_DIR)
	'$(LUAJIT)' -b '$^' '$@'

$(TMP_DIR)/prelude.h: $(TMP_DIR)/prelude.luac
	xxd -i -n 'prelude_luac' -u '$^' | sed -E -e 's/ 0X/ 0x/g' -e 's/([0-9A-F])$$/\1,/g' -e 's/^unsigned char /const char /g' -e '/^unsigned int /d' > '$@'

$(SRC_DIR)/lua.c: $(TMP_DIR)/cdef.h $(TMP_DIR)/prelude.h
	touch '$@'

$(TMP_DIR)/$(BUNDLE_NAME): $(SRC_DIR)/main.c $(SRC_DIR)/lua.h $(SRC_DIR)/lua.c $(SRC_DIR)/defer.h $(LIB_DIR)/libluajit-5.1.2.dylib $(INC_DIR)/lualib.h $(INC_DIR)/luajit.h $(INC_DIR)/luaconf.h $(INC_DIR)/lua.h $(INC_DIR)/lauxlib.h $(TMP_DIR)/$(BUNDLE_NAME).entitlements | $(TMP_DIR)
	'$(CC)' -I'$(INC_DIR)' -L'$(LIB_DIR)' -O'2' -W'all' -W'error' -W'extra' -W'pedantic' $(patsubst %,-arch '%',$(ARCHES)) -isysroot '$(SDK_PATH)' -l'luajit-5.1.2' -l'EndpointSecurity' -mmacosx-version-min='$(MACOSX_DEPLOYMENT_TARGET)' -o'$@!' $(patsubst %,'%',$(subst ','"'"',$(filter %.c,$^)))
	'$(CODESIGN)' -s '$(SIGNING_IDENTITY)' --entitlements '$(TMP_DIR)/$(BUNDLE_NAME).entitlements' -o 'runtime' --runtime-version '$(MACOSX_DEPLOYMENT_TARGET)' -f '$@!'
	mv -f '$@'{'!',''}

$(TMP_DIR)/libluajit-5.1.2.dylib: $(LIB_DIR)/libluajit-5.1.2.dylib | $(TMP_DIR)
	cp -f '$<' '$@!'
	'$(CODESIGN)' -s '$(SIGNING_IDENTITY)' -f '$@!'
	mv -f '$@'{'!',''}

$(TMP_DIR)/$(BUNDLE_NAME).app/Contents/Info.plist: $(TMP_DIR)/Info.plist | $(TMP_DIR)/$(BUNDLE_NAME).app/Contents
	cp -f '$<' '$@'

$(TMP_DIR)/$(BUNDLE_NAME).app/Contents/embedded.provisionprofile: $(SRC_DIR)/embedded.provisionprofile | $(TMP_DIR)/$(BUNDLE_NAME).app/Contents
	cp -f '$<' '$@'

$(TMP_DIR)/$(BUNDLE_NAME).app/Contents/Frameworks/libluajit-5.1.2.dylib: $(TMP_DIR)/libluajit-5.1.2.dylib | $(TMP_DIR)/$(BUNDLE_NAME).app/Contents/Frameworks
	cp -f '$<' '$@'

$(TMP_DIR)/$(BUNDLE_NAME).app/Contents/MacOS/$(BUNDLE_NAME): $(TMP_DIR)/$(BUNDLE_NAME) $(TMP_DIR)/$(BUNDLE_NAME).entitlements | $(TMP_DIR)/$(BUNDLE_NAME).app/Contents/MacOS
	cp -f '$<' '$@!'
	'$(INSTALL_NAME_TOOL)' -add_rpath '@loader_path/../Frameworks' -change '/usr/local/lib/libluajit-5.1.2.dylib' '@rpath/libluajit-5.1.2.dylib' '$@!'
	'$(CODESIGN)' -s '$(SIGNING_IDENTITY)' --entitlements '$(TMP_DIR)/$(BUNDLE_NAME).entitlements' -o 'runtime' --runtime-version '$(MACOSX_DEPLOYMENT_TARGET)' -f '$@!'
	mv -f '$@'{'!',''}

$(TMP_DIR)/$(BUNDLE_NAME).app/Contents/_CodeSignature/CodeResources: $(TMP_DIR)/$(BUNDLE_NAME).app/Contents/Info.plist $(TMP_DIR)/$(BUNDLE_NAME).app/Contents/embedded.provisionprofile $(TMP_DIR)/$(BUNDLE_NAME).app/Contents/Frameworks/libluajit-5.1.2.dylib $(TMP_DIR)/$(BUNDLE_NAME).app/Contents/MacOS/$(BUNDLE_NAME) $(TMP_DIR)/$(BUNDLE_NAME).entitlements
	'$(CODESIGN)' -s '$(SIGNING_IDENTITY)' --entitlements '$(TMP_DIR)/$(BUNDLE_NAME).entitlements' -o 'runtime' --runtime-version '$(MACOSX_DEPLOYMENT_TARGET)' -f '$(patsubst %/,%,$(dir $(patsubst %/,%,$(dir $(patsubst %/,%,$(dir $@))))))'

ifdef DISABLE_NOTARIZATION
$(OUT_DIR)/$(BUNDLE_NAME).app: $(TMP_DIR)/$(BUNDLE_NAME).app/Contents/_CodeSignature/CodeResources | $(OUT_DIR)
	cp -af '$(patsubst %/,%,$(dir $(patsubst %/,%,$(dir $(patsubst %/,%,$(dir $<))))))' '$@'
else
$(TMP_DIR)/$(BUNDLE_NAME).zip: $(TMP_DIR)/$(BUNDLE_NAME).app/Contents/_CodeSignature/CodeResources
	ditto -c -k --keepParent --sequesterRsrc '$(patsubst %/,%,$(dir $(patsubst %/,%,$(dir $(patsubst %/,%,$(dir $<))))))' '$@'

$(TMP_DIR)/$(BUNDLE_NAME).app/Contents/CodeResources: $(TMP_DIR)/$(BUNDLE_NAME).zip
	'$(NOTARYTOOL)' submit -p '$(KEYCHAIN_PROFILE)' --wait '$<'
	'$(STAPLER)' staple '$(patsubst %/,%,$(dir $(patsubst %/,%,$(dir $@))))'

$(OUT_DIR)/$(BUNDLE_NAME).app: $(TMP_DIR)/$(BUNDLE_NAME).app/Contents/CodeResources | $(OUT_DIR)
	cp -af '$(patsubst %/,%,$(dir $(patsubst %/,%,$(dir $<))))' '$@'
endif
