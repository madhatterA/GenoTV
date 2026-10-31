all: Frameworks/.symlinks

Frameworks/Mpv.xcframework/Info.plist:
	@echo 'Run python3 packages/playback/tool/package_macos_engine.py first' >&2; exit 1

Frameworks/.symlinks: Frameworks/Mpv.xcframework/Info.plist
	rm -rf Frameworks/.symlinks
	mkdir -p Frameworks/.symlinks/mpv
	sh create_framework_symlinks.sh Frameworks/Mpv.xcframework Frameworks/.symlinks/mpv
