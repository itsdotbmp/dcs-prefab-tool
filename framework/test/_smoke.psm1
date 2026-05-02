# Shared helpers for the dcs-sms PowerShell smoke tests.
#
# Each smoke_*.ps1 script imports this module, calls Initialize-Smoke once,
# then uses the Expect-* helpers to assert behavior of the framework via
# tools/dcs-sms.exe. JSON parsing is real (ConvertFrom-Json) so assertions
# match return_value semantically rather than via substring grep.
#
# Pattern:
#   Import-Module "$PSScriptRoot/_smoke.psm1" -Force
#   Initialize-Smoke
#   Invoke-Smoke -File 'load_all.lua' | Out-Null
#
#   $fixtures = @('_sms_test_x')
#   try {
#       Expect-EqString -Label 'sms.version' -Code 'return sms.version' -Expected '0.1.0'
#       # ...
#   } finally {
#       Clear-SmokeFixtures -Names $fixtures
#   }
#
#   Write-Host "ALL <name> checks passed."

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Script:DCSSMS = $null
$Script:FrameworkDir = $null

function Initialize-Smoke {
    [CmdletBinding()]
    param()

    $callerFile = (Get-PSCallStack)[1].ScriptName
    if (-not $callerFile) {
        throw "Initialize-Smoke must be called from a .ps1 script."
    }
    $scriptDir = Split-Path -Parent $callerFile
    $frameworkDir = (Resolve-Path (Join-Path $scriptDir '..')).Path
    $repoRoot = (Resolve-Path (Join-Path $frameworkDir '..')).Path
    $exe = Join-Path $repoRoot 'tools\dcs-sms.exe'

    if (-not (Test-Path $exe)) {
        throw "dcs-sms.exe not found at $exe — build it first (cd tools && go build ./cmd/dcs-sms)."
    }

    $Script:DCSSMS = $exe
    $Script:FrameworkDir = $frameworkDir
    Set-Location $frameworkDir
}

function Get-DcsSmsPath {
    if (-not $Script:DCSSMS) {
        throw "Smoke test not initialized — call Initialize-Smoke first."
    }
    $Script:DCSSMS
}

function Invoke-Smoke {
    # Run dcs-sms.exe exec and return the parsed JSON object.
    # Use -Code for an inline Lua chunk or -File for a framework/ relative file.
    [CmdletBinding(DefaultParameterSetName = 'Code')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Code')]
        [string]$Code,

        [Parameter(Mandatory, ParameterSetName = 'File')]
        [string]$File
    )

    $exe = Get-DcsSmsPath
    if ($PSCmdlet.ParameterSetName -eq 'Code') {
        $raw = & $exe exec --code $Code 2>&1
    } else {
        $raw = & $exe exec --file $File 2>&1
    }
    $text = ($raw | Out-String).Trim()
    if (-not $text) {
        throw "dcs-sms.exe returned no output."
    }
    try {
        $text | ConvertFrom-Json
    } catch {
        throw "dcs-sms.exe returned non-JSON output: $text"
    }
}

function Invoke-Status {
    $exe = Get-DcsSmsPath
    & $exe status
}

# Internal: pretty-print a failure with the raw response and exit non-zero.
function Stop-OnSmokeFail {
    param([string]$Label, [string]$Why, $Response)
    $body = if ($null -ne $Response) { ($Response | ConvertTo-Json -Depth 6 -Compress) } else { '<no response>' }
    Write-Host "FAIL: ${Label}: ${Why}`n  raw: $body"
    exit 1
}

function Expect-True {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Code
    )
    $r = Invoke-Smoke -Code $Code
    if ($r.return_value -ne $true) {
        Stop-OnSmokeFail -Label $Label -Why "expected return_value=true, got '$($r.return_value)'" -Response $r
    }
}

function Expect-False {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Code
    )
    $r = Invoke-Smoke -Code $Code
    if ($r.return_value -ne $false) {
        Stop-OnSmokeFail -Label $Label -Why "expected return_value=false, got '$($r.return_value)'" -Response $r
    }
}

function Expect-Nil {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Code
    )
    $r = Invoke-Smoke -Code $Code
    if ($null -ne $r.return_value) {
        Stop-OnSmokeFail -Label $Label -Why "expected return_value=null, got '$($r.return_value)'" -Response $r
    }
}

function Expect-EqString {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][string]$Expected
    )
    $r = Invoke-Smoke -Code $Code
    if ([string]$r.return_value -ne $Expected) {
        Stop-OnSmokeFail -Label $Label -Why "expected '$Expected', got '$($r.return_value)'" -Response $r
    }
}

function Expect-EqNumber {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)][double]$Expected
    )
    $r = Invoke-Smoke -Code $Code
    $actual = $r.return_value
    if ($null -eq $actual -or [double]$actual -ne $Expected) {
        Stop-OnSmokeFail -Label $Label -Why "expected $Expected, got '$actual'" -Response $r
    }
}

function Expect-Eq {
    # Generic equality (string or number). Coerces both sides to string for compare,
    # matching the bash expect_eq semantics where the operand is always a literal.
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Code,
        [Parameter(Mandatory)]$Expected
    )
    $r = Invoke-Smoke -Code $Code
    if ([string]$r.return_value -ne [string]$Expected) {
        Stop-OnSmokeFail -Label $Label -Why "expected '$Expected', got '$($r.return_value)'" -Response $r
    }
}

function Invoke-TailLog {
    # Read recent dcs.log lines, optionally filtered on the dcs-sms side via
    # --grep (regex) and/or --since ("cursor", "0", or a duration like "60s").
    [CmdletBinding()]
    param(
        [string]$Grep,
        [int]$Lines = 200,
        [string]$Since
    )
    $exe = Get-DcsSmsPath
    $args = @('tail-log', '-n', $Lines)
    if ($Grep)  { $args += @('--grep', $Grep) }
    if ($Since) { $args += @('--since', $Since) }
    & $exe @args 2>&1
}

function Expect-LogContains {
    # Assert the recent dcs.log window matches a regex. -Grep prefilters lines
    # on the dcs-sms side (typically a tag like '[sms.timer]') before the
    # PowerShell regex match runs over the result. -Since narrows the window
    # to "0" (whole file) or a duration like "60s".
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Pattern,
        [string]$Grep,
        [int]$Lines = 200,
        [string]$Since
    )
    # Default to whole-file scan — "cursor" semantics on dcs-sms's tail-log
    # advance after every read, which makes back-to-back assertion calls miss
    # lines they should both see. Assertion fetches want a sliding window, not
    # a tailing cursor.
    if (-not $Since) { $Since = '0' }
    $opts = @{ Lines = $Lines }
    if ($Grep)  { $opts.Grep = $Grep }
    $opts.Since = $Since
    $text = (Invoke-TailLog @opts | Out-String)
    if ($text -notmatch $Pattern) {
        Write-Host "FAIL: ${Label}: log did not contain pattern '$Pattern'"
        Write-Host "  --- log tail (last $Lines, grep='$Grep', since='$Since') ---"
        Write-Host $text
        exit 1
    }
}

function Expect-LogNotContains {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Pattern,
        [string]$Grep,
        [int]$Lines = 200,
        [string]$Since
    )
    # Default to whole-file scan — "cursor" semantics on dcs-sms's tail-log
    # advance after every read, which makes back-to-back assertion calls miss
    # lines they should both see. Assertion fetches want a sliding window, not
    # a tailing cursor.
    if (-not $Since) { $Since = '0' }
    $opts = @{ Lines = $Lines }
    if ($Grep)  { $opts.Grep = $Grep }
    $opts.Since = $Since
    $text = (Invoke-TailLog @opts | Out-String)
    if ($text -match $Pattern) {
        Write-Host "FAIL: ${Label}: log unexpectedly contained pattern '$Pattern'"
        Write-Host "  --- log tail (last $Lines, grep='$Grep', since='$Since') ---"
        Write-Host $text
        exit 1
    }
}

function Clear-SmokeFixtures {
    # Best-effort destruction of test groups/statics by name. Idempotent —
    # only destroys what currently exists. Errors are swallowed because this
    # is meant to run from a finally{} after a possibly-failed test run.
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$Names
    )
    if (-not $Names -or $Names.Count -eq 0) { return }
    $list = ($Names | ForEach-Object { "'$_'" }) -join ','
    $code = @"
for _, n in ipairs({$list}) do
  local g = Group.getByName(n); if g then g:destroy() end
  local s = StaticObject.getByName(n); if s then s:destroy() end
end
"@
    try { Invoke-Smoke -Code $code | Out-Null } catch { }
}

Export-ModuleMember -Function `
    Initialize-Smoke, Get-DcsSmsPath, Invoke-Smoke, Invoke-Status, Invoke-TailLog, `
    Expect-True, Expect-False, Expect-Nil, Expect-EqString, Expect-EqNumber, Expect-Eq, `
    Expect-LogContains, Expect-LogNotContains, `
    Clear-SmokeFixtures
