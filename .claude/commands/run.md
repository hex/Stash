Kill the running Stash app (if any), regenerate the Xcode project, build, and launch Stash.

Steps:
1. Run `pkill -x Stash` to kill the running app (ignore errors if not running)
2. Run `cd /Users/hex/.claude-sessions/Stash/Stash && xcodegen generate` to regenerate the project
3. Run `xcodebuild -project Stash.xcodeproj -scheme Stash -configuration Debug build` to build
4. If build succeeds, find the built app path from `xcodebuild -project Stash.xcodeproj -scheme Stash -configuration Debug -showBuildSettings | grep -m1 BUILT_PRODUCTS_DIR | awk '{print $3}'` and open the .app with `open`
5. Report success or failure
