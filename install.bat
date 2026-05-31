@echo off
setlocal enabledelayedexpansion

:: -------------------------------------------------------
:: LOGGING
:: Re-launches itself so all output goes to console + file.
:: Tries PowerShell Tee-Object first (live output + log).
:: Falls back to plain redirect if PowerShell is blocked
:: -------------------------------------------------------
if not defined _LOGGED (
    :: Generate safe log filename using PowerShell (avoids locale issues with %DATE%/%TIME%)
    for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'"`) do set "_TS=%%D"
    set "_LOGFILE=%~dp0install_log_!_TS!.txt"

    :: Try PowerShell tee (live console output + log file simultaneously)
    powershell -NoProfile -ExecutionPolicy Bypass -Command "exit 0" >nul 2>&1
    if errorlevel 1 (
        :: PowerShell unavailable or blocked - fall back to redirect-only logging
        echo [*] PowerShell unavailable - logging to file only ^(no live output^)
        echo [*] Log: !_LOGFILE!
        set "_LOGGED=1" && cmd /c "%~f0" %* > "!_LOGFILE!" 2>&1
    ) else (
        :: PowerShell available - tee to console and log file simultaneously
        echo.
        echo [*] Saving installation log to: !_LOGFILE!
        echo.
        powershell -NoProfile -ExecutionPolicy Bypass -Command "& { $env:_LOGGED='1'; & cmd /c '%~f0' %* 2>&1 | Tee-Object -FilePath '!_LOGFILE!' }"
    )
    exit /b
)

:: ANSI color support (Windows 10+)
for /f %%a in ('echo prompt $E ^| cmd') do set "ESC=%%a"
set "GREEN=%ESC%[32m"
set "YELLOW=%ESC%[33m"
set "RED=%ESC%[31m"
set "CYAN=%ESC%[36m"
set "BOLD=%ESC%[1m"
set "RESET=%ESC%[0m"

:: Parse --debug flag
set "DEBUG="
set "Q=>nul 2>&1"
set "QQ=--quiet"

for %%A in (%*) do (
    if /I "%%A"=="--debug" (
        set "DEBUG=1"
        set "Q="
        set "QQ=--verbose"
    )
)

:: In debug mode, show all commands; otherwise keep output clean
if defined DEBUG (
    echo %YELLOW%[DEBUG]%RESET% Debug mode enabled - full output will be shown
    echo.
) else (
    cls
)

title comfyui-rocm Installer
echo %CYAN%===================================================%RESET%
echo %CYAN%       comfyui-rocm - Automatic Installer%RESET%
echo %CYAN%  [AMD GCN5/Vega * RDNA1 * RDNA2 * RDNA3 * RDNA4]%RESET%
echo %CYAN%====================================================%RESET%
echo.

:: 1. Check if Python exists
if exist "python_env\python.exe" (
    echo %GREEN%[*]%RESET% Python environment found. Skipping download.
    goto :setup_environment
)

:: 2. Download Python Embeddable (for runtime)
echo %GREEN%[*]%RESET% [1/7] Downloading Python 3.12 Embeddable...
if not exist "python_env" mkdir "python_env"
curl -L --ssl-no-revoke "https://www.python.org/ftp/python/3.12.9/python-3.12.9-embed-amd64.zip" -o "python_embed.zip" --no-progress-meter %Q%
if errorlevel 1 (
    echo %RED%[!]%RESET% Error: Failed to download Python embeddable
    pause
    exit /b 1
)

:: 3. Download Python Full Installer (for dev files)
echo %GREEN%[*]%RESET% [2/7] Downloading Python development files...
curl -L --ssl-no-revoke https://www.python.org/ftp/python/3.12.9/python-3.12.9-amd64.zip -o python_full.zip --no-progress-meter %Q%
if errorlevel 1 (
    echo %RED%[!]%RESET% Error: Failed to download Python installer
    del "python_embed.zip" %Q%
    pause
    exit /b 1
)

:: 4. Extract embeddable Python
echo %GREEN%[*]%RESET% [3/7] Extracting Python runtime...
tar -xf "python_embed.zip" -C "python_env" %Q%
if errorlevel 1 (
    echo %RED%[!]%RESET% Error: Failed to extract Python
    pause
    exit /b 1
)
del "python_embed.zip"

:: 5. Install full Python to temp location to extract dev files
echo %GREEN%[*]%RESET% [4/7] Installing development components...
mkdir pythonfull
tar -xf "python_full.zip" -C "pythonfull" %Q%
:: Wait for installation
timeout /t 3 /nobreak %Q%

:: 6. Copy development files
echo %GREEN%[*]%RESET% [5/7] Copying headers and libraries...
if exist "pythonfull\include" (
    xcopy "pythonfull\include" "python_env\include\" /E /I /Q %Q%
    echo %GREEN%[*]%RESET% - Headers copied
) else (
    echo %YELLOW%[!]%RESET% Warning: Headers not found
)

if exist "pythonfull\libs" (
    xcopy "pythonfull\libs" "python_env\libs\" /E /I /Q %Q%
    echo %GREEN%[*]%RESET% - Libraries copied
) else (
    echo %YELLOW%[!]%RESET% Warning: Libs not found
)

:: Also copy the full Lib folder for completeness
if exist "\Lib" (
    xcopy "\Lib" "python_env\Lib\" /E /I /Q %Q%
    echo %GREEN%[*]%RESET% - Standard library copied
)

:: Clean up temp installation and installer
rd /s /q "pythonfull" %Q%
del "python_full.zip" %Q%

:: 7. Configure Python
echo %GREEN%[*]%RESET% [6/7] Configuring Python...
(
echo python312.zip
echo .
echo ..
echo import site
) > "python_env\python312._pth"

:: 8. Install Pip
echo %GREEN%[*]%RESET% [7/7] Installing Pip and build tools...
curl -L --ssl-no-revoke "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py" --no-progress-meter %Q%
if errorlevel 1 (
    echo %RED%[!]%RESET% Error: Failed to download get-pip.py
    pause
    exit /b 1
)
.\python_env\python.exe get-pip.py --no-warn-script-location %Q%
if errorlevel 1 (
    echo %RED%[!]%RESET% Error: Failed to install pip
    pause
    exit /b 1
)
del "get-pip.py"

:: Install build tools
.\python_env\python.exe -m pip install --upgrade pip setuptools==81 wheel --no-warn-script-location %Q%
.\python_env\python.exe -m pip install mpmath==1.3 --no-warn-script-location %Q%
if errorlevel 1 (
    echo %RED%[!]%RESET% Error: Failed to install build tools
    pause
    exit /b 1
)

:setup_environment
:: Set PATH for portable installation
set "PYTHON_DIR=%~dp0python_env"
set "PATH=%PYTHON_DIR%;%PYTHON_DIR%\Scripts;%PATH%"

:detect_gpu
echo.
echo %GREEN%[*]%RESET% Detecting GPU...

:: Check if detect_gpu.py exists
if not exist "detect_gpu.py" (
    echo %RED%[!]%RESET% Error: detect_gpu.py not found!
    pause
    exit /b 1
)

for /f "delims=" %%A in ('.\python_env\python.exe detect_gpu.py 2^>nul') do (
    if not "%%A"=="" (
        set "arch=%%A"
    )
)

if "!arch!"=="" (
    echo %RED%[!]%RESET% GPU detection failed or unsupported GPU
    pause
    exit /b 1
)

echo %GREEN%[*]%RESET% Detected GPU architecture: %CYAN%!arch!%RESET%

:: Install PyTorch based on detected GPU
if "!arch!"=="gfx101X" (
    echo %GREEN%[*]%RESET% Installing ROCm for RDNA1 ^(gfx101X^)...
    .\python_env\python.exe -m pip install rocm[devel,libraries] --index-url https://rocm.nightlies.amd.com/v2-staging/gfx101X-dgpu/ --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    .\python_env\scripts\rocm-sdk init %Q%
    if errorlevel 1 echo %YELLOW%[!]%RESET% Warning: rocm-sdk init failed, continuing anyway...
    echo %GREEN%[*]%RESET% Installing PyTorch for RDNA1 ^(gfx101X^)...
    .\python_env\python.exe -m pip install --index-url https://rocm.nightlies.amd.com/v2-staging/gfx101X-dgpu/ torch torchaudio torchvision --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    goto :install_requirements
)

if "!arch!"=="gfx103X" (
    echo %GREEN%[*]%RESET% Installing ROCm for RDNA2 ^(gfx103X^)...
    .\python_env\python.exe -m pip install rocm[devel,libraries] --index-url https://rocm.nightlies.amd.com/v2-staging/gfx103X-all/ --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    .\python_env\scripts\rocm-sdk init %Q%
    if errorlevel 1 echo %YELLOW%[!]%RESET% Warning: rocm-sdk init failed, continuing anyway...
    echo %GREEN%[*]%RESET% Installing PyTorch for RDNA2 ^(gfx103X^)...
    .\python_env\python.exe -m pip install --pre --index-url https://rocm.nightlies.amd.com/v2-staging/gfx103X-all/ torch torchaudio torchvision --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    goto :install_requirements
)

if "!arch!"=="gfx110X" (
    echo %GREEN%[*]%RESET% Installing ROCm for RDNA3 ^(gfx110X^)...
    .\python_env\python.exe -m pip install rocm[devel,libraries] --index-url https://rocm.nightlies.amd.com/v2-staging/gfx110X-dgpu/ --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    .\python_env\scripts\rocm-sdk init %Q%
    if errorlevel 1 echo %YELLOW%[!]%RESET% Warning: rocm-sdk init failed, continuing anyway...
    echo %GREEN%[*]%RESET% Installing PyTorch for RDNA3 ^(gfx110X^)...
    .\python_env\python.exe -m pip install --index-url https://rocm.nightlies.amd.com/v2-staging/gfx110X-dgpu/ torch torchaudio torchvision --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    goto :install_requirements
)

if "!arch!"=="gfx120X" (
    echo %GREEN%[*]%RESET% Installing ROCm for RDNA4 ^(gfx120X^)...
    .\python_env\python.exe -m pip install rocm[devel,libraries] --index-url https://rocm.nightlies.amd.com/v2-staging/gfx120X-dgpu/ --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    .\python_env\scripts\rocm-sdk init %Q%
    if errorlevel 1 echo %YELLOW%[!]%RESET% Warning: rocm-sdk init failed, continuing anyway...
    echo %GREEN%[*]%RESET% Installing PyTorch for RDNA4 ^(gfx120X^)...
    .\python_env\python.exe -m pip install --index-url https://rocm.nightlies.amd.com/v2-staging/gfx120X-dgpu/ torch torchaudio torchvision --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    goto :install_requirements
)

if "!arch!"=="gfx90X" (
    echo %GREEN%[*]%RESET% Installing ROCm for Radeon Pro VII ^(gfx90X^)...
    .\python_env\python.exe -m pip install rocm[devel,libraries] --index-url https://rocm.nightlies.amd.com/v2-staging/gfx90X-dcgpu/ --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    .\python_env\scripts\rocm-sdk init %Q%
    if errorlevel 1 echo %YELLOW%[!]%RESET% Warning: rocm-sdk init failed, continuing anyway...
    echo %GREEN%[*]%RESET% Installing PyTorch for Radeon Pro VII ^(gfx90X^)...
    .\python_env\python.exe -m pip install --index-url https://rocm.nightlies.amd.com/v2-staging/gfx90X-dcgpu/ torch torchaudio torchvision --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    goto :install_requirements
)

if "!arch!"=="gfx94X" (
    echo %GREEN%[*]%RESET% Installing ROCm for MI300/MI325 ^(gfx94X^)...
    .\python_env\python.exe -m pip install rocm[devel,libraries] --index-url https://rocm.nightlies.amd.com/v2-staging/gfx94X-dcgpu/ --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    .\python_env\scripts\rocm-sdk init %Q%
    if errorlevel 1 echo %YELLOW%[!]%RESET% Warning: rocm-sdk init failed, continuing anyway...
    echo %GREEN%[*]%RESET% Installing PyTorch for MI300/MI325 ^(gfx94X^)...
    .\python_env\python.exe -m pip install --index-url https://rocm.nightlies.amd.com/v2-staging/gfx94X-dcgpu/ torch torchaudio torchvision --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    goto :install_requirements
)

if "!arch!"=="gfx950" (
    echo %GREEN%[*]%RESET% Installing ROCm for MI350/MI355 ^(gfx950^)...
    .\python_env\python.exe -m pip install rocm[devel,libraries] --index-url https://rocm.nightlies.amd.com/v2-staging/gfx950-dcgpu/ --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    .\python_env\scripts\rocm-sdk init %Q%
    if errorlevel 1 echo %YELLOW%[!]%RESET% Warning: rocm-sdk init failed, continuing anyway...
    echo %GREEN%[*]%RESET% Installing PyTorch for MI350/MI355 ^(gfx950^)...
    .\python_env\python.exe -m pip install --index-url https://rocm.nightlies.amd.com/v2-staging/gfx950-dcgpu/ torch torchaudio torchvision --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    goto :install_requirements
)

if "!arch!"=="gfx900" (
    echo %GREEN%[*]%RESET% Installing ROCm for Vega 10 / GCN5 ^(gfx900^)...
    .\python_env\python.exe -m pip install rocm[devel,libraries] --index-url https://rocm.nightlies.amd.com/v2-staging/gfx900/ --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    .\python_env\scripts\rocm-sdk init %Q%
    if errorlevel 1 echo %YELLOW%[!]%RESET% Warning: rocm-sdk init failed, continuing anyway...
    echo %GREEN%[*]%RESET% Installing PyTorch for Vega 10 / GCN5 ^(gfx900^)...
    .\python_env\python.exe -m pip install --index-url https://rocm.nightlies.amd.com/v2-staging/gfx900/ torch torchaudio torchvision --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    goto :install_requirements
)

if "!arch!"=="gfx906" (
    echo %GREEN%[*]%RESET% Installing ROCm for Vega 20 / Radeon VII ^(gfx906^)...
    .\python_env\python.exe -m pip install rocm[devel,libraries] --index-url https://rocm.nightlies.amd.com/v2-staging/gfx906/ --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    .\python_env\scripts\rocm-sdk init %Q%
    if errorlevel 1 echo %YELLOW%[!]%RESET% Warning: rocm-sdk init failed, continuing anyway...
    echo %GREEN%[*]%RESET% Installing PyTorch for Vega 20 / Radeon VII ^(gfx906^)...
    .\python_env\python.exe -m pip install --index-url https://rocm.nightlies.amd.com/v2-staging/gfx906/ torch torchaudio torchvision --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    goto :install_requirements
)

if "!arch!"=="gfx908" (
    echo %GREEN%[*]%RESET% Installing ROCm for Arcturus / MI100 ^(gfx908^)...
    .\python_env\python.exe -m pip install rocm[devel,libraries] --index-url https://rocm.nightlies.amd.com/v2-staging/gfx908/ --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    .\python_env\scripts\rocm-sdk init %Q%
    if errorlevel 1 echo %YELLOW%[!]%RESET% Warning: rocm-sdk init failed, continuing anyway...
    echo %GREEN%[*]%RESET% Installing PyTorch for Arcturus / MI100 ^(gfx908^)...
    .\python_env\python.exe -m pip install --index-url https://rocm.nightlies.amd.com/v2-staging/gfx908/ torch torchaudio torchvision --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    goto :install_requirements
)

if "!arch!"=="gfx90a" (
    echo %GREEN%[*]%RESET% Installing ROCm for Aldebaran / MI200 ^(gfx90a^)...
    .\python_env\python.exe -m pip install rocm[devel,libraries] --index-url https://rocm.nightlies.amd.com/v2-staging/gfx90a/ --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    .\python_env\scripts\rocm-sdk init %Q%
    if errorlevel 1 echo %YELLOW%[!]%RESET% Warning: rocm-sdk init failed, continuing anyway...
    echo %GREEN%[*]%RESET% Installing PyTorch for Aldebaran / MI200 ^(gfx90a^)...
    .\python_env\python.exe -m pip install --index-url https://rocm.nightlies.amd.com/v2-staging/gfx90a/ torch torchaudio torchvision --no-warn-script-location %Q%
    if errorlevel 1 goto :install_failed
    goto :install_requirements
)

echo %RED%[!]%RESET% Unknown GPU architecture detected: %CYAN%!arch!%RESET%
pause
exit /b 1

:install_requirements
echo.
echo %GREEN%[*]%RESET% Installing comfyui-rocm...

:: Check if requirements.txt exists
if not exist "requirements.txt" (
    echo %RED%[!]%RESET% Error: requirements.txt not found!
    pause
    exit /b 1
)

.\python_env\python.exe -m pip install -r requirements.txt --no-warn-script-location %Q%
if errorlevel 1 goto :install_failed

echo %GREEN%[*]%RESET% Installing extensions...

cd custom_nodes
if not exist comfyui-manager git clone https://github.com/Comfy-Org/ComfyUI-Manager %QQ%
if not exist CFZ-SwitchMenu git clone https://github.com/patientx/CFZ-SwitchMenu.git %QQ%
if not exist CFZ-Caching git clone https://github.com/patientx/CFZ-Caching %QQ%
if not exist ComfyUI-HFRemoteVae git clone https://github.com/kijai/ComfyUI-HFRemoteVae %QQ%
cd ..

:: diffusers install for hfremotevae
.\python_env\python.exe -m pip install diffusers %QQ%

echo %GREEN%[*]%RESET% Installing triton - sageattention^(v1^)...
.\python_env\python.exe -m pip install triton-windows==3.6.0.post25 %QQ%
if errorlevel 1 goto :install_failed
.\python_env\python.exe -m pip install sageattention==1.0.6 %QQ%
if errorlevel 1 goto :install_failed

echo %GREEN%[*]%RESET% Patching sage-attention...
del python_env\Lib\site-packages\sageattention\attn_qk_int8_per_block.py %Q%
curl -sL -o python_env\Lib\site-packages\sageattention\attn_qk_int8_per_block.py https://raw.githubusercontent.com/patientx/ComfyUI-Zluda/refs/heads/master/comfy/customzluda/sa/attn_qk_int8_per_block.py
del python_env\Lib\site-packages\sageattention\attn_qk_int8_per_block_causal.py %Q%
curl -sL -o python_env\Lib\site-packages\sageattention\attn_qk_int8_per_block_causal.py https://raw.githubusercontent.com/patientx/ComfyUI-Zluda/refs/heads/master/comfy/customzluda/sa/attn_qk_int8_per_block_causal.py
del python_env\Lib\site-packages\sageattention\quant_per_block.py %Q%
curl -sL -o python_env\Lib\site-packages\sageattention\quant_per_block.py https://raw.githubusercontent.com/patientx/ComfyUI-Zluda/refs/heads/master/comfy/customzluda/sa/quant_per_block.py

echo %GREEN%[*]%RESET% Installing bitsandbytes if available...

:: Skip unsupported architectures for bitsandbytes prebuilt wheels
for %%G in (gfx90X) do (
    if /I "!arch!"=="%%G" (
        echo %YELLOW%[*]%RESET% Skipping bitsandbytes for %CYAN%!arch!%RESET% - prebuilt wheels not available, build from source required...
        goto :bnb_done
    )
)

:: Install bitsandbytes
echo %GREEN%[*]%RESET% Installing bitsandbytes...
.\python_env\python.exe -m pip install https://github.com/0xDELUXA/bitsandbytes_win_rocm/releases/download/0.50.0.dev0-py3.12-rocm7.14-win_amd64_all/bitsandbytes-0.50.0.dev0-cp312-cp312-win_amd64.whl %QQ%
if errorlevel 1 goto :install_failed

:bnb_done

echo %GREEN%[*]%RESET% Installing flash-attention ^(aiter triton backend^)...
.\python_env\python.exe -m pip install https://github.com/0xDELUXA/flash-attention/releases/download/v2.8.4_win-rocm/flash_attn-2.8.4-py3-none-win_amd64.whl %QQ%
if errorlevel 1 (
    echo %YELLOW%[!]%RESET% Warning: flash-attention install failed, skipping...
    goto :fa_done
)
.\python_env\python.exe -m pip install https://github.com/0xDELUXA/flash-attention/releases/download/v2.8.4_win-rocm/amd_aiter-0.0.0-py3-none-win_amd64.whl %QQ%
if errorlevel 1 echo %YELLOW%[!]%RESET% Warning: aiter install failed, flash-attention will not work...

:fa_done

:verify_installation
echo.
echo %GREEN%[*]%RESET% Verifying installation...
echo.
.\python_env\python.exe -c "import torch; print(f'PyTorch Version: {torch.__version__}'); print(f'ROCm Available: {torch.cuda.is_available()}'); print(f'ROCm Version: {torch.version.hip if torch.cuda.is_available() else \"N/A\"}')"
if errorlevel 1 (
    echo %YELLOW%[!]%RESET% Warning: Installation verification failed
    echo %YELLOW%[!]%RESET% PyTorch may not be properly installed
)

goto :install_complete

:install_complete
copy comfyui-rocm.bat comfyui-user.bat /y %Q%

echo.
echo %GREEN%====================================================%RESET%
echo %GREEN%  Installation Complete!%RESET%
echo %GREEN%  Run "comfyui-user.bat" to start comfyui-rocm%RESET%
echo %GREEN%====================================================%RESET%
goto :end

:install_failed
echo.
echo %RED%====================================================%RESET%
echo %RED%  Installation Failed!%RESET%
echo %RED%  Check the error messages above for details.%RESET%
echo %RED%====================================================%RESET%
goto :end

:end
pause
exit /b
