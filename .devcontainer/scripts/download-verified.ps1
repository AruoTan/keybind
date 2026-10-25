# Return a cached or newly downloaded file only after the pinned hash matches.
function Get-KeybindVerifiedDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Urls,
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[a-fA-F0-9]{64}$')]
        [string]$Sha256,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )
    $ErrorActionPreference = 'Stop'
    if ((Test-Path -LiteralPath $Destination -PathType Leaf) -and
        (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash -eq $Sha256) {
        return $Destination
    }
    New-Item -ItemType Directory -Path (Split-Path $Destination -Parent) -Force | Out-Null
    $partial = "$Destination.$([Guid]::NewGuid().ToString('N')).partial"
    $failures = New-Object 'System.Collections.Generic.List[string]'
    foreach ($url in $Urls) {
        try {
            Write-Verbose "Downloading $url"
            # Windows PowerShell can leave OutFile empty when PassThru is used.
            Invoke-WebRequest -Uri $url -OutFile $partial -UseBasicParsing `
                -UserAgent 'keybind-build' -TimeoutSec 60 -MaximumRedirection 10
            $actualHash = (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $Sha256) {
                $size = (Get-Item -LiteralPath $partial).Length
                $format = 'unknown'
                $stream = [IO.File]::OpenRead($partial)
                try {
                    $prefix = New-Object byte[] 64
                    $length = $stream.Read($prefix, 0, $prefix.Length)
                    $text = [Text.Encoding]::ASCII.GetString($prefix, 0, $length)
                    if ($size -eq 0) { $format = 'empty' }
                    elseif ($text -match '^\s*(<!DOCTYPE\s+html|<html)') { $format = 'HTML' }
                    elseif ($length -ge 4 -and $prefix[0] -eq 0x50 -and $prefix[1] -eq 0x4B -and
                        $prefix[2] -eq 3 -and $prefix[3] -eq 4) { $format = 'ZIP' }
                }
                finally { $stream.Dispose() }
                throw "SHA256 mismatch; expected=$Sha256; actual=$actualHash; bytes=$size; format=$format"
            }
            Move-Item -LiteralPath $partial -Destination $Destination -Force
            return $Destination
        }
        catch {
            $detail = "${url}: $($_.Exception.Message)"
            $failures.Add($detail)
            Write-Warning $detail
        }
        finally {
            if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
        }
    }
    throw ("No download matched the pinned SHA256. " + ($failures -join ' | '))
}
