@echo off
setlocal

:: ==============================================================================
:: Mod Downloader for Prism Launcher Index
::
:: Use the Prism Launcher to create/update the .index subdirectory. This script
:: will read .toml files from .index and download the corresponding mod files.
:: ==============================================================================

cd /d "%~dp0"

call :sync_mods
exit /b %errorlevel%

:sync_mods
    set "MODS_DIR=.\mods"
    set "INDEX_DIR=.\mods\.index"
    set "SYNC_STATUS=0"
    set "OVERWRITE_MODIFIED_FILES=false"

    :: Dependency check
    where curl >nul 2>nul & if %errorlevel% neq 0 (echo [ERROR] curl not found.& exit /b 1)
    where certutil >nul 2>nul & if %errorlevel% neq 0 (echo [ERROR] certutil not found.& exit /b 1)

    :: check for mod metadata stored in .toml files in mods\.index\
    if not exist "%MODS_DIR%" (
        echo [INFO] No mods required.
        exit /b 0
    )
    if not exist "%INDEX_DIR%" (
        echo [INFO] No mods required.
        exit /b 0
    )
    dir /b "%INDEX_DIR%\*.toml" >nul 2>nul
    if %errorlevel% neq 0 (
        echo [INFO] No mods required.
        exit /b 0
    )

    echo Starting mod synchronization...
    echo --------------------------------------------------

    for %%F in ("%INDEX_DIR%\*.toml") do call :process_toml_file "%%F"

    echo --------------------------------------------------
    if %SYNC_STATUS% equ 0 (
        echo Synchronization complete. All mods are up-to-date.
    ) else (
        echo Synchronization finished with errors. Some mods may be missing.
    )
    exit /b %SYNC_STATUS%

:process_toml_file
    setlocal enabledelayedexpansion
    set "toml_file=%~1"
    
    set "mod_name=" & set "filename=" & set "url=" & set "expected_hash=" & set "hash_format=" & set "mode=" & set "cf_file_id="
    set "current_section=root"

    for /f "usebackq delims=" %%L in (`type "%toml_file%" 2^>nul`) do (
        set "line=%%L"
        if defined line (
            for /f "tokens=*" %%A in ("!line!") do set "line=%%A"
            if defined line (
                set "first_char=!line:~0,1!"
                if not "!first_char!"=="#" (
                    if "!first_char!"=="[" (
                        set "section_line=!line!"
                        set "current_section=!section_line:~1,-1!"
                    ) else (
                        echo "!line!" | find "=" >nul && (
                            for /f "tokens=1,* delims== " %%A in ("!line!") do (
                                set "key=%%A" & set "value=%%B"
                                if "!value:~0,1!" == """" set "value=!value:~1,-1!"
                                if "!value:~0,1!" == "'" set "value=!value:~1,-1!"
                                if "!current_section!" == "root" (
                                    if /i "!key!" == "name" set "mod_name=!value!"
                                    if /i "!key!" == "filename" set "filename=!value!"
                                )
                                if "!current_section!" == "download" (
                                    if /i "!key!" == "url" set "url=!value!"
                                    if /i "!key!" == "hash" set "expected_hash=!value!"
                                    if /i "!key!" == "hash-format" set "hash_format=!value!"
                                    if /i "!key!" == "mode" set "mode=!value!"
                                )
                                if "!current_section!" == "update.curseforge" (
                                    if /i "!key!" == "file-id" (
                                        set "cf_file_id=!value!"
                                        set "cf_file_id=!cf_file_id: =!"
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )

    if not defined mod_name set "mod_name=!filename!"
    if not defined filename ( echo [ERROR] 'filename' was not found. & ( endlocal & exit /b 1 ) )
    if not defined expected_hash ( echo [ERROR] 'hash' was not found. & ( endlocal & exit /b 1 ) )
    if not defined hash_format ( echo [ERROR] 'hash-format' was not found. & ( endlocal & exit /b 1 ) )

    set "hash_algo="
    if /i "!hash_format!" == "sha512" set "hash_algo=SHA512"
    if /i "!hash_format!" == "sha256" set "hash_algo=SHA256"
    if /i "!hash_format!" == "sha1" set "hash_algo=SHA1"
    if /i "!hash_format!" == "md5" set "hash_algo=MD5"
    if not defined hash_algo ( echo [ERROR] Unsupported hash '!hash_format!'. & ( endlocal & exit /b 1 ) )

    set "target_file=%MODS_DIR%\!filename!"
    if exist "!target_file!" (
        set "local_hash="
        for /f "skip=1 tokens=1" %%H in ('certutil -hashfile "!target_file!" !hash_algo!') do ( if not defined local_hash set "local_hash=%%H" )
        
        if "!local_hash!" == "!expected_hash!" (
            echo [OK]     !mod_name! already up-to-date.
            ( endlocal & goto :eof )
        ) else (
            echo [WARN]   !mod_name! has been modified.
            if /i "!OVERWRITE_MODIFIED_FILES!" == "true" (
                echo [INFO]   Overwriting modified file as per configuration.
            ) else (
                echo [INFO]   Skipping download to preserve local changes.
                ( endlocal & goto :eof )
            )
        )
    )

    if /i "!mode!" == "metadata:curseforge" (
        if not defined cf_file_id (
            echo [WARN] Missing 'file-id' for CurseForge mod
            ( endlocal & goto :eof )
        )
        set "slug_one=!cf_file_id:~0,4!"
        set "slug_two=!cf_file_id:~-3!"
        set /a "slug_two_stripped=1!slug_two! - 1000" 
        set "url=https://mediafilez.forgecdn.net/files/!slug_one!/!slug_two_stripped!/!filename!"
    ) else if /i "!mode!" == "url" (
        rem URL is already set from parsing, no action needed.
    ) else (
        echo [WARN] Unsupported mode for !mod_name! mode: '!mode!'
        ( endlocal & goto :eof )
    )

    echo [GET]    Downloading: !mod_name!...

    curl -L --max-redirs 5 --connect-timeout 10 --retry 3 --retry-delay 2 -A "Mozilla/5.0" -o "!target_file!" "!url!" --silent --show-error
    
    if %errorlevel% neq 0 goto :download_failed

    :: --- Download Success: Verify Hash ---
    set "downloaded_hash="
    for /f "skip=1 tokens=1" %%H in ('certutil -hashfile "!target_file!" !hash_algo!') do ( if not defined downloaded_hash set "downloaded_hash=%%H" )

    if "!downloaded_hash!" == "!expected_hash!" (
        echo [OK]     Download successful and verified.
    ) else (
        echo [ERROR]  Checksum failed for !mod_name!. Deleting corrupt file.
        del "!target_file!" >nul 2>nul
        ( endlocal & set SYNC_STATUS=1 )
    )
    goto :end_of_download_check

:download_failed
    :: --- Download Failure ---
    echo [ERROR]  Failed to download !mod_name! (curl error: %errorlevel%).
    if exist "!target_file!" del "!target_file!" >nul 2>nul
    ( endlocal & set SYNC_STATUS=1 )

:end_of_download_check
    ( endlocal & goto :eof )
