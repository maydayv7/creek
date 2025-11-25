$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$VenvDir = Join-Path $ScriptDir "python_env"

Write-Host "Setting up Python virtual environment..."

# Detect Python 3.11 using Python launcher
$PythonCmd = $null

try {
    $v = & py -3.11 --version 2>$null
    if ($LASTEXITCODE -eq 0 -and $v -like "Python 3.11*") {
        $PythonCmd = @("py", "-3.11")
    }
}
catch {}

if (-not $PythonCmd) {
    Write-Host "ERROR: Python 3.11 is required but not found" -ForegroundColor Red
    exit 1
}

# Print Python version
$ver = & $PythonCmd[0] $PythonCmd[1] --version
Write-Host ("Using Python: " + $ver)

# Create venv
if (-not (Test-Path $VenvDir)) {
    Write-Host ("Creating virtual environment at " + $VenvDir + "...")
    & $PythonCmd[0] $PythonCmd[1] -m venv $VenvDir
    Write-Host "Virtual environment created successfully"
} else {
    Write-Host ("Virtual environment already exists at " + $VenvDir)
}

# Validate
$VenvPython = Join-Path $VenvDir "Scripts\python.exe"

if (Test-Path $VenvPython) {
    $v = & $VenvPython --version
    Write-Host ("Virtual environment Python version: " + $v)
} else {
    Write-Host "ERROR: Failed to create virtual environment" -ForegroundColor Red
    exit 1
}
