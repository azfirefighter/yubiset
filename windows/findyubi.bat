@ECHO OFF
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

::
:: SETUP SECTION
::
set lib_dir=lib

call %lib_dir%/setup_script_env.bat "%~n0" "%~dp0"

call %lib_dir%/pretty_print.bat "Yubikey smartcard slot find and configuration script"
call %lib_dir%/pretty_print.bat "Version: %yubiset_version%"

set conf_backup=scdaemon.conf.orig
set scdaemon_log=%root_folder%\scdaemon.log

::
:: GPG AGENT RESTART
::
echo.
call %lib_dir%/restart_gpg_agent.bat
%ifErr% echo %error_prefix%: Could not restart gpg-agent. Exiting. goto end_with_error

::
:: SCDAEMON RESTART
::
echo.
call %lib_dir%/restart_scdaemon.bat
%ifErr% echo %error_prefix%: Could not restart scdaemon. Exiting. goto end_with_error

::
:: COMM CHECK
::
call %lib_dir%/reinsert_yubi.bat

echo Now checking if we are able to communicate with your Yubikey..
gpg --card-status 2>&1 >nul
%ifErr% (
	call %lib_dir%/are_you_sure.bat "..Failed :( This is most likely because your GPG does not know which card reader to use. Should we try setting things up for you"
	if defined answerisno echo %error_prefix%: We cannot continue without a properly recognized Yubikey. Exiting. goto end_with_error
) else (
	echo ..Success!
	goto end
)

::
:: ACTIVATE SCDAEMON DEBUG MODE
::
echo.
echo In order to find the correct card slot, we need to switch scdaemon into debug mode. This is done via a change to the config file. We are going to reset the changes, when we are done. Promise :)
call %lib_dir%/are_you_sure.bat "Continue"
if defined answerisno goto end_with_error

if exist %gpg_home%\scdaemon.conf (
	echo Now creating backup: %gpg_home%\%conf_backup%
	%silentCopy% %gpg_home%\scdaemon.conf %gpg_home%\%conf_backup% /Y
	%ifErr% echo %error_prefix%: Could not create backup of scdaemon.conf. Exiting. && call :cleanup && goto end_with_error
	echo ..Success!
)

echo ^#Start: Temporarily added by Yubiset>> %gpg_home%\scdaemon.conf
echo log-file %scdaemon_log%>> %gpg_home%\scdaemon.conf
echo debug-level guru>> %gpg_home%\scdaemon.conf
echo debug-all>> %gpg_home%\scdaemon.conf
echo ^#End: Temporarily added by Yubiset>> %gpg_home%\scdaemon.conf

echo.
echo Please remove your YubiKey.
pause

::
:: GPG AGENT RESTART
::
echo.
call %lib_dir%/restart_gpg_agent.bat
%ifErr% echo %error_prefix%: Could not restart gpg-agent. Exiting. && call :cleanup && goto end_with_error

::
:: SCDAEMON RESTART
::
echo.
call %lib_dir%/restart_scdaemon.bat
%ifErr% echo %error_prefix%: Could not restart scdaemon. Exiting. && call :cleanup && goto end_with_error

echo Please insert your YubiKey.
pause

echo Now running generating debug log..
gpg --card-status 2>&1 >nul
echo ..Done!

::
:: DEACTIVATE SCDAEMON DEBUG MODE
::
echo.
echo Now switching off debug mode..
call :cleanup

::
:: PROCESS DEBUG LOG
::
set array_index=0
for /f "tokens=2 delims=^'" %%i in ('type %scdaemon_log% ^| findstr /C:"detected reader"') do (
	set reader_port_candidate=%%i
	call :removeLastSpaceAndTail reader_port_candidate
	set /a array_index+=1
	set reader_port_candidates[!array_index!]=!reader_port_candidate!
)

for /f "tokens=2 delims==" %%i in ('set reader_port_candidates[') do (
	for /f "tokens=*" %%v in ('echo %%i^| findstr /I /C:"yubi"') do (
		set reader_port_candidate=%%v
		call %lib_dir%/are_you_sure.bat "Found reader port '%reader_port_candidate%' - Is this the right one"
		if defined answerisyes goto addReaderToConf
	)
)

echo Could not find any viable readers.
call :cleanup
goto end_with_error

:addReaderToConf
echo.
echo Writing scdaemon.conf..
call :cleanup
echo reader-port "%reader_port_candidate%">> %gpg_home%\scdaemon.conf
call %lib_dir%/restart_scdaemon.bat
%ifErr% echo %error_prefix%: Could not restart scdaemon. Exiting. && goto end_with_error
echo.
::
:: COMM CHECK
::
call %lib_dir%/reinsert_yubi.bat

echo Now checking if we are able to communicate with your Yubikey..
gpg --card-status 2>&1 >nul
%ifErr% echo Sorry, setting up your Yubikey did not work. Exiting. goto end_with_error
echo ..Success!
goto end

:removeLastSpaceAndTail
set pos=-1
set last_space=0
:removeLastSpaceAndTail_loop
set /a pos+=1
set current_char=!reader_port_candidate:~%pos%,1!
if "%current_char%"==" " set last_space=%pos%
if "%current_char%" NEQ "" goto removeLastSpaceAndTail_loop
set %~1=!%~1:~0,%last_space%!
exit /b 0

:cleanup
%silentCopy% %gpg_home%\%conf_backup% %gpg_home%\scdaemon.conf /Y
%silentDel% %gpg_home%\%conf_backup%
%silentDel% %scdaemon_log%
call %lib_dir%/restart_scdaemon.bat
%ifErr% echo %error_prefix%: Could not restart scdaemon. Exiting. && call :cleanup && goto end_with_error
exit /b 0

:end_with_error
endlocal
exit /b 1
:end
endlocal