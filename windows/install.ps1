$ErrorActionPreference = 'Stop'
$Support = Join-Path $env:LOCALAPPDATA 'Prisma'
$Venv = Join-Path $Support 'venv'
$Python = Join-Path $Venv 'Scripts\python.exe'
$PythonW = Join-Path $Venv 'Scripts\pythonw.exe'
New-Item -ItemType Directory -Force $Support | Out-Null
if (-not (Test-Path $Python)) {
    $launcher = Get-Command py -ErrorAction SilentlyContinue
    if (-not $launcher) { throw 'Instala Python 3.11 o 3.12 para Windows con Tkinter y el lanzador py; después vuelve a ejecutar este instalador.' }
    $version = $null
    foreach ($candidate in @('-3.12-64', '-3.11-64')) {
        try {
            & py $candidate -c 'import sys' 2>$null
            if ($LASTEXITCODE -eq 0) { $version = $candidate; break }
        } catch { continue }
    }
    if (-not $version) { throw 'Instala Python 3.11 o 3.12 de 64 bits y vuelve a ejecutar el instalador.' }
    & py $version -m venv $Venv
    if ($LASTEXITCODE -ne 0) { throw 'No se pudo crear el entorno Python.' }
}
& $Python -m pip install -r (Join-Path $PSScriptRoot 'requirements.txt')
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron instalar las dependencias de voz.' }
& $Python -c 'import tkinter'
if ($LASTEXITCODE -ne 0) { throw 'La instalación de Python necesita incluir Tkinter.' }
$voiceDir = Join-Path $Support 'voices'
New-Item -ItemType Directory -Force $voiceDir | Out-Null
$base = 'https://huggingface.co/rhasspy/piper-voices/resolve/main/es/es_MX/claude/high'
foreach ($file in @('es_MX-claude-high.onnx', 'es_MX-claude-high.onnx.json')) {
    $dest = Join-Path $voiceDir $file
    if (-not (Test-Path $dest)) {
        Write-Host "Descargando $file..."
        Invoke-WebRequest -Uri "$base/$file" -OutFile "$dest.download"
        Move-Item -Force "$dest.download" $dest
    }
}
& $Python (Join-Path $PSScriptRoot 'install.py')
if ($LASTEXITCODE -ne 0) { throw 'No se pudieron configurar las integraciones. Revisa el error anterior.' }
$Shell = New-Object -ComObject WScript.Shell
$startMenu = [Environment]::GetFolderPath('Programs')
$shortcut = $Shell.CreateShortcut((Join-Path $startMenu 'Prisma.lnk'))
$shortcut.TargetPath = $PythonW
$shortcut.Arguments = '"' + (Join-Path $Support 'app.py') + '"'
$shortcut.WorkingDirectory = $Support
$shortcut.Description = 'Prisma - avisos de voz para tus agentes'
$shortcut.Save()
Start-Process $PythonW -ArgumentList ('"' + (Join-Path $Support 'app.py') + '"') -WorkingDirectory $Support
Write-Host 'Prisma está instalado. Abre el icono de la bandeja y selecciona Probar voz. Reinicia tus agentes.'
