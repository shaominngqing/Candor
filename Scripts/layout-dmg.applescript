on run arguments
    if (count of arguments) is not 2 then error "Expected the temporary volume name and mount path"
    set volumeName to item 1 of arguments
    set mountPath to item 2 of arguments

    tell application "Finder"
        tell disk volumeName
            open
            tell container window
                set current view to icon view
                set toolbar visible to false
                set statusbar visible to false
                set pathbar visible to false
                set sidebar width to 0
                set bounds to {120, 120, 780, 540}
            end tell

            set opts to the icon view options of container window
            tell opts
                set icon size to 112
                set text size to 13
                set arrangement to not arranged
            end tell
            set background picture of opts to file ".background:CandorDMG.png"

            set position of item "Candor.app" to {175, 210}
            set position of item "Applications" to {485, 210}
            update without registering applications
            close
            open
            delay 1
            set bounds of container window to {120, 120, 770, 530}
            delay 1
            set bounds of container window to {120, 120, 780, 540}
            delay 3
            close
        end tell
    end tell

    repeat with attempt from 1 to 10
        try
            do shell script "test -f " & quoted form of (mountPath & "/.DS_Store")
            exit repeat
        on error
            delay 1
        end try
    end repeat
end run
