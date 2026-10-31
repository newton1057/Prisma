param(
    [string]$Text = 'Hola. Prisma está funcionando en Windows.',
    [ValidateSet('', 'edge', 'piper', 'windows')][string]$Engine = '',
    [string]$Voice = ''
)
$ErrorActionPreference = 'Stop'
$Support = Join-Path $env:LOCALAPPDATA 'Prisma'
$Python = Join-Path $Support 'venv\Scripts\python.exe'
if (-not (Test-Path $Python)) { throw 'Prisma no está instalado. Ejecuta windows\install.ps1.' }
$env:PRISMA_TEST_TEXT = $Text
$env:PRISMA_TEST_ENGINE = $Engine
$env:PRISMA_TEST_VOICE = $Voice
& $Python (Join-Path $PSScriptRoot 'test_voice.py')
if ($LASTEXITCODE -ne 0) { throw 'No se pudo enviar el aviso de prueba.' }
