param([string]$Swipl = 'swipl')

$ErrorActionPreference = 'Stop'
$entrada = & $Swipl -q -s prolog_engine/tests/instancia_viabilidad.pl
if ($LASTEXITCODE -ne 0) { throw 'Falló el generador de la instancia.' }

$opciones = New-Object Diagnostics.ProcessStartInfo
$opciones.FileName = $Swipl
$opciones.Arguments = '-q -s prolog_engine/main.pl'
$opciones.UseShellExecute = $false
$opciones.CreateNoWindow = $true
$opciones.RedirectStandardInput = $true
$opciones.RedirectStandardOutput = $true
$opciones.RedirectStandardError = $true
$reloj = [Diagnostics.Stopwatch]::StartNew()
$motor = [Diagnostics.Process]::Start($opciones)
try {
    $salida = $motor.StandardOutput.ReadToEndAsync()
    $errores = $motor.StandardError.ReadToEndAsync()
    $motor.StandardInput.WriteLine($entrada)
    $motor.StandardInput.Close()
    $pico = 0L
    while (-not $motor.HasExited) {
        try {
            $pico = [Math]::Max($pico, $motor.PeakWorkingSet64)
        } catch [InvalidOperationException] {
            if (-not $motor.HasExited) { throw }
        }
        Start-Sleep -Milliseconds 50
        $motor.Refresh()
    }
    $motor.WaitForExit()
    $reloj.Stop()
    $diagnostico = $errores.GetAwaiter().GetResult()
    if ($diagnostico) { Write-Warning $diagnostico }
    if ($motor.ExitCode -ne 0) { throw "El motor terminó con código $($motor.ExitCode)." }

    $resultado = $salida.GetAwaiter().GetResult() | ConvertFrom-Json
    $primera = $resultado.versiones | Select-Object -First 1
    [pscustomobject]@{
        Estado = $resultado.estado
        TiempoMotorMs = $resultado.tiempoMs
        TiempoProcesoMs = $reloj.ElapsedMilliseconds
        PicoMemoriaMiB = [Math]::Round($pico / 1MB, 1)
        Versiones = $resultado.versiones.Count
        Asignadas = $primera.asignaciones.Count
        Pendientes = $primera.sinAsignar.Count
        Costo = $primera.costo
    }
} finally {
    $motor.Dispose()
}
