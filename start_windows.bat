@echo off
setlocal enabledelayedexpansion

:: ============================================================================
::                 Debug Configuration
:: ============================================================================
:: To ENABLE debug messages, use: set "DEBUG=echo"
:: To DISABLE debug messages, use: set "DEBUG=rem"

rem set "DEBUG=echo"
set "DEBUG=rem"

:: ============================================================================
::                 Main Execution Flow
:: ============================================================================
%DEBUG% DEBUG SCRIPT START
call :setup_directories
call :load_config
call :handle_properties
call :handle_datapacks
call :handle_mods
call :handle_server_jar
call :handle_eula
call :start_server

goto :cleanup

:: ============================================================================
::                 Subroutines
:: ============================================================================

:setup_directories
    %DEBUG% DEBUG ENTERING setup_directories
    :: Change directory to the script's location
    cd /d "%~dp0"
    %DEBUG% DEBUG Script directory %CD%

    :: Ensure the 'data' subdirectory exists and enter it
    set "DATA_DIR=.\data"
    %DEBUG% DEBUG DATADIR set to %DATA_DIR%
    if not exist "%DATA_DIR%" (
        %DEBUG% DEBUG Data directory not found Creating it
        mkdir "%DATA_DIR%"
    ) else (
        %DEBUG% DEBUG Data directory found
    )
    cd "%DATA_DIR%"
    %DEBUG% DEBUG Current directory changed to %CD%
    echo.
goto :eof


:load_config
    %DEBUG% DEBUG ENTERING load_config
    set "JAR_NAME=fabric-server-mc.1.21.6-loader.0.17.2-launcher.1.1.0.jar"
    set "JAVA_ARGS=-Xmx4G"
    set "FABRIC_URL=https://meta.fabricmc.net/v2/versions/loader/1.21.6/0.17.2/1.1.0/server/jar"
    set "synchronize_mods=true"
    set "include_from_datapacks_folder=true"
    set "datapacks_folder=datapacks"
    set "properties_file=server.properties"

    %DEBUG% DEBUG JAR_NAME %JAR_NAME%
    %DEBUG% DEBUG JAVA_ARGS %JAVA_ARGS%
    %DEBUG% DEBUG synchronize_mods %synchronize_mods%
    %DEBUG% DEBUG include_from_datapacks_folder %include_from_datapacks_folder%
    echo.
goto :eof


:handle_properties
    %DEBUG% DEBUG ENTERING handle_properties
    %DEBUG% DEBUG Checking for %properties_file%
    if not exist "%properties_file%" (
        %DEBUG% DEBUG %properties_file% does not exist
        if exist "default-server.properties" (
            %DEBUG% DEBUG default server properties found Copying
            copy "default-server.properties" "%properties_file%" > nul
        ) else (
            %DEBUG% DEBUG WARNING default server properties also not found Creating empty file
            type nul > "%properties_file%"
        )
    ) else (
        %DEBUG% DEBUG %properties_file% found
    )

    %DEBUG% DEBUG Checking for MC_PORT environment variable
    if not defined MC_PORT (
        %DEBUG% DEBUG MC_PORT not defined Defaulting to 25565
        set "MC_PORT=25565"
    ) else (
        %DEBUG% DEBUG MC_PORT is defined as %MC_PORT%
    )
    %DEBUG% DEBUG Calling set_property for server port
    call :set_property "server-port" "%MC_PORT%" "%properties_file%"
    echo.
goto :eof


:handle_datapacks
    %DEBUG% DEBUG ENTERING handle_datapacks
    if not exist "%properties_file%" (
        %DEBUG% DEBUG Cannot process datapacks %properties_file% not found Skipping
        goto :eof
    )

    %DEBUG% DEBUG Reading initial initial enabled packs value
    set "current_packs_value="
    for /f "usebackq tokens=1,* delims==" %%a in ("%properties_file%") do (
        if /i "%%a"=="initial-enabled-packs" set "current_packs_value=%%b"
    )
    %DEBUG% DEBUG Value from file !current_packs_value!
    set "appended_packs_value=!current_packs_value!"

    if /i "%include_from_datapacks_folder%"=="true" (
        if exist "%datapacks_folder%\" (
            %DEBUG% DEBUG Datapacks folder found Looping through contents
            for %%f in ("%datapacks_folder%\*") do (
                set "pack_name=%%~nxf"
                set "pack_entry=file/!pack_name!"
                %DEBUG% DEBUG Checking pack !pack_entry!

                echo ",!appended_packs_value!," | find ",!pack_entry!," > nul
                if errorlevel 1 (
                    %DEBUG% DEBUG Entry not found Appending
                    if defined appended_packs_value (
                        set "appended_packs_value=!appended_packs_value!,!pack_entry!"
                    ) else (
                        set "appended_packs_value=!pack_entry!"
                    )
                ) else (
                    %DEBUG% DEBUG Entry already exists Skipping
                )
            )
        )
    )

    %DEBUG% DEBUG Datapack check finished
    %DEBUG% DEBUG Original list !current_packs_value!
    %DEBUG% DEBUG Final list !appended_packs_value!
    if "!appended_packs_value!" neq "!current_packs_value!" (
        %DEBUG% DEBUG Datapack list has changed Updating properties file
        call :set_property "initial-enabled-packs" "!appended_packs_value!" "%properties_file%"
        echo Datapack configuration updated
    ) else (
        %DEBUG% DEBUG Datapack list has not changed No update needed
        echo Datapack configuration is already up to date
    )
    echo.
goto :eof


:handle_mods
    %DEBUG% DEBUG ENTERING handle_mods
    if /i not "%synchronize_mods%"=="true" (
        %DEBUG% DEBUG Mod sync is disabled Skipping
        goto :eof
    )

    set "MODS_UPDATE_SCRIPT=.\update_mods.bat"
    %DEBUG% DEBUG Mod sync is enabled Checking for %MODS_UPDATE_SCRIPT%
    if exist "%MODS_UPDATE_SCRIPT%" (
        %DEBUG% DEBUG Mod update script found Executing
        call "%MODS_UPDATE_SCRIPT%"
        %DEBUG% DEBUG Mod update script finished with errorlevel %errorlevel%
        if %errorlevel% neq 0 (
            echo ERROR Mod synchronization failed Aborting server launch
            exit /b 1
        )
        echo Mods are up to date
    ) else (
        %DEBUG% DEBUG WARNING Mod update script not found Skipping
    )
    echo.
goto :eof


:handle_server_jar
    %DEBUG% DEBUG ENTERING handle_server_jar
    %DEBUG% DEBUG Checking for JAR file %JAR_NAME%
    if not exist "%JAR_NAME%" (
        %DEBUG% DEBUG Server JAR not found Downloading from %FABRIC_URL%
        curl -o "%JAR_NAME%" -L "%FABRIC_URL%"
        %DEBUG% DEBUG Download command finished
        echo.
    ) else (
        %DEBUG% DEBUG Server JAR already exists
    )
goto :eof


:handle_eula
    %DEBUG% DEBUG ENTERING handle_eula
    %DEBUG% DEBUG Writing eula equals true to eula dot txt
    echo eula=true> eula.txt
    echo.
goto :eof


:start_server
    %DEBUG% DEBUG ENTERING start_server
    %DEBUG% DEBUG Full command java %JAVA_ARGS% -jar "%JAR_NAME%" nogui
    echo Starting Minecraft server
    echo --------------------------------------------------

    java %JAVA_ARGS% -jar "%JAR_NAME%" nogui

    echo --------------------------------------------------
    echo Server process has stopped Script finished
goto :eof


:set_property
    setlocal
    set "p_key=%~1"
    set "p_value=%~2"
    set "p_file=%~3"
    set "temp_file=%p_file%.tmp"
    set "key_found=false"

    %DEBUG% DEBUG SUBROUTINE set_property
    :: Use delayed expansion for parameters in case they contain special characters
    %DEBUG% DEBUG Key !p_key!
    %DEBUG% DEBUG Value !p_value!
    %DEBUG% DEBUG File !p_file!

    if exist "%temp_file%" del "%temp_file%"

    for /f "usebackq delims=" %%L in ("!p_file!") do (
        set "line=%%L"
        set "current_key="
        for /f "delims==" %%k in ("!line!") do set "current_key=%%k"
        
        :: Use delayed expansion for the key comparison
        if /i "!current_key!" equ "!p_key!" (
            if !key_found! == false (
                %DEBUG% DEBUG ACTION Key MATCHES Replacing line
                :: Use delayed expansion to write the new value
                echo !p_key!=!p_value!>>"%temp_file%"
                set "key_found=true"
            ) else (
                %DEBUG% DEBUG ACTION Duplicate key found Ignoring line
            )
        ) else (
            echo(!line!>>"%temp_file%"
        )
    )

    if "!key_found!"=="false" (
        %DEBUG% DEBUG Key was not found in file Appending to end
        :: Use delayed expansion to append the new value
        echo !p_key!=!p_value!>>"%temp_file%"
    )

    move /y "%temp_file%" "%p_file%" > nul
    %DEBUG% DEBUG END SUBROUTINE set_property
    endlocal
goto :eof


:: ============================================================================
::                 Cleanup
:: ============================================================================
:cleanup
%DEBUG% DEBUG Reached end of script Cleaning up
endlocal
exit /b 0
