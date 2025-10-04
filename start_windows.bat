@echo off
setlocal enabledelayedexpansion

:: ============================================================================
::                 Minecraft Server Startup Script
:: ============================================================================
:: This script prepares and launches a Fabric Minecraft server. It handles
:: configuration, mod/datapack updates, and JAR downloads automatically.
:: ============================================================================

:: Change directory to the script's location to ensure paths are correct
cd /d "%~dp0"

:: The server's operational files are in a 'data' subdirectory.
set "DATA_DIR=.\data"

:: If the data directory doesn't exist, create it and change into it.
if not exist "%DATA_DIR%" mkdir "%DATA_DIR%"
cd "%DATA_DIR%"

:: ============================================================================
:: Configuration
:: ============================================================================
set "JAR_NAME=fabric-server-mc.1.21.6-loader.0.17.2-launcher.1.1.0.jar"
set "JAVA_ARGS=-Xmx4G"
set "FABRIC_URL=https://meta.fabricmc.net/v2/versions/loader/1.21.6/0.17.2/1.1.0/server/jar"
set "synchronize_mods=true"
set "include_from_datapacks_folder=true"
set "datapacks_folder=datapacks"


:: ============================================================================
:: 1. Ensure server.properties exists and is configured
:: ============================================================================
set "properties_file=server.properties"
if not exist "%properties_file%" (
    if exist "default-server.properties" (
        echo server.properties not found. Copying from default-server.properties.
        copy "default-server.properties" "%properties_file%" > nul
    ) else (
        echo WARNING: server.properties and default-server.properties not found. A new one will be generated.
        :: Create a truly empty file so it can be written to.
        type nul > "%properties_file%"
    )
)

:: Set the server port from the environment variable, defaulting to 25565
if not defined MC_PORT set "MC_PORT=25565"
call :set_property "server-port" "%MC_PORT%" "%properties_file%"


:: ============================================================================
:: 2. Append Datapacks to server.properties
:: ============================================================================
if exist "%properties_file%" (
    :: Read the current value of the property.
    set "current_packs_value="
    for /f "usebackq tokens=1,* delims==" %%a in ("%properties_file%") do (
        if /i "%%a"=="initial-enabled-packs" set "current_packs_value=%%b"
    )

    set "appended_packs_value=!current_packs_value!"

    if /i "%include_from_datapacks_folder%"=="true" (
        if exist "%datapacks_folder%\" (
            for %%f in ("%datapacks_folder%\*") do (
                set "pack_name=%%~nxf"
                set "pack_entry=file/!pack_name!"

                :: Check if the pack is already in the comma-separated list.
                :: This method correctly avoids partial matches.
                echo ",!appended_packs_value!," | find ",!pack_entry!," > nul
                if errorlevel 1 (
                    :: Append the new pack if it's not found.
                    if defined appended_packs_value (
                        set "appended_packs_value=!appended_packs_value!,!pack_entry!"
                    ) else (
                        set "appended_packs_value=!pack_entry!"
                    )
                )
            )
        )
    )

    :: Only write to the file if the final list is different from the original.
    if "!appended_packs_value!" neq "!current_packs_value!" (
        echo Datapack configuration has changed. Updating server.properties...
        call :set_property "initial-enabled-packs" "!appended_packs_value!" "%properties_file%"
        echo Datapack configuration updated.
    ) else (
        echo Datapack configuration is already up to date.
    )
    echo.
)


:: ============================================================================
:: 3. Synchronize Mods
:: ============================================================================
set "MODS_UPDATE_SCRIPT=.\update_mods.bat"

if /i "%synchronize_mods%"=="true" (
    echo Synchronizing mods...
    if exist "%MODS_UPDATE_SCRIPT%" (
        call "%MODS_UPDATE_SCRIPT%"
        if %errorlevel% neq 0 (
            echo ERROR: Mod synchronization failed. Aborting server launch.
            exit /b 1
        )
        echo Mods are up to date.
    ) else (
        echo WARNING: Mod update script not found at '%MODS_UPDATE_SCRIPT%'. Skipping.
    )
    echo.
)


:: ============================================================================
:: 4. Check for Server Jar
:: ============================================================================
if not exist "%JAR_NAME%" (
    echo Server JAR not found. Downloading from Fabric...
    curl -o "%JAR_NAME%" -L "%FABRIC_URL%"
    echo.
)


:: ============================================================================
:: 5. EULA Agreement
:: ============================================================================
echo Ensuring EULA is accepted...
echo eula=true> eula.txt
echo.


:: ============================================================================
:: 6. Start Server
:: ============================================================================
echo Starting Minecraft server...
echo --------------------------------------------------

java %JAVA_ARGS% -jar "%JAR_NAME%" nogui

echo --------------------------------------------------
echo Server process has stopped. Script finished.
goto :cleanup


:: ============================================================================
:: Subroutines
:: ============================================================================

:set_property
:: Sets a property in a given file. Updates existing key or appends a new one.
:: Preserves comments and blank lines.
:: Usage: call :set_property "key" "value" "file.properties"
setlocal
set "p_key=%~1"
set "p_value=%~2"
set "p_file=%~3"
set "temp_file=%p_file%.tmp"
set "key_found=false"

if exist "%temp_file%" del "%temp_file%"

for /f "usebackq delims=" %%L in ("%p_file%") do (
    set "line=%%L"
    set "current_key="
    for /f "delims==" %%k in ("!line!") do set "current_key=%%k"

    if /i "!current_key!" equ "%p_key%" (
        :: Key matches, write the new value, but only once.
        if !key_found! == false (
            echo %p_key%=%p_value%>>"%temp_file%"
            set "key_found=true"
        )
    ) else (
        :: Key does not match, write the original line back.
        :: `echo(!line!` correctly handles blank lines.
        echo(!line!>>"%temp_file%"
    )
)

:: If the key was never found in the file, append it to the end.
if "!key_found!"=="false" (
    echo %p_key%=%p_value%>>"%temp_file%"
)

move /y "%temp_file%" "%p_file%" > nul
endlocal
goto :eof


:: ============================================================================
:: Cleanup
:: ============================================================================
:cleanup
endlocal
exit /b 0
