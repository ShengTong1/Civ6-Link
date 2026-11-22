<#
  set-broadcast-path.ps1  --  CivLink M0-A helper (v3, audit-remediation)

  STATUS: OFFLINE-REPAIRED COPY. Not applied on any live adapter.
          REV-005 authorises script repair + code review only;
          actual NIC changes remain unapproved.

  PROBLEM
    Windows keeps a local route for 255.255.255.255/32 on EVERY interface
    (Protocol=Local, RouteMetric=256). The broadcast therefore leaves through
    whichever interface has the SMALLEST InterfaceMetric. On a machine with
    several virtual adapters (Radmin VPN, ZeroTier, Hyper-V, WSL) that is
    almost never the adapter that can actually reach the peer.

    Measured on PC-A 2026-11-11 with 100 real broadcast packets:
      no bind (what Civilization VI does) -> 100/100 left via Radmin VPN
      bind 192.168.31.59 (WLAN)            -> 100/100 left via WLAN
      bind 26.74.126.98  (Radmin)          -> 100/100 left via Radmin

  V2 DEFECTS FIXED IN V3 (per REV-004 / REV-005 review)
    D-1  apply overwrote an existing good backup with an EMPTY one when the
         second run had nothing left to raise.  -> v3 never overwrites: every
         apply writes a NEW timestamped file and refuses if the planned
         change set is empty.
    D-2  the keep interface's ORIGINAL metric / AutomaticMetric were never
         saved although apply pins them -> v3 records keep.OriginalMetric and
         keep.OriginalAuto before touching anything.
    D-3  restore ignored failures (every Set-NetIPInterface used
         -ErrorAction SilentlyContinue) and never read the values back.
         -> v3 errors out on failure and verifies every item by readback.
    D-4  restore reported success even when the broadcast exit was wrong
         (the check was piped to Out-Null).  -> v3 readback-verifies each
         item and exits non-zero on any mismatch.
    D-5  no way to capture a trusted state table without changing anything.
         -> v3 adds `snapshot` (writes current state, changes nothing).

  ACTIONS
    status     read-only. Shows adapters, predicted broadcast exit and the
               peer path, then says whether a fix would be needed.
    snapshot   read-only. Writes the CURRENT state table (all connected IPv4
               interfaces: ifIndex/name/metric/AutomaticMetric/IPv4, plus the
               broadcast exit and the peer path) to a JSON + text file.
               Use this to rebuild a trusted pre-change state record.
    apply      requires admin. Finds the interface that routes to -PeerIp,
               raises every competing interface above it, pins the keep
               interface, then VERIFIES by readback.  Writes a new backup.
    restore    requires admin. Restores from a backup file (default: newest
               v3 backup), verifies every item by readback, exits non-zero on
               any mismatch. Refuses backups that contain no items.
    list-backups  lists available backups, oldest first.

  EXIT CODES
    0  success
    1  administrator rights required
    2  bad parameters / missing or unusable backup
    3  restore readback verification FAILED
    4  apply readback verification FAILED
    5  refused (a backup already exists for this peer / empty change set)

  Fix history
    v1 only matched an adapter name ("Radmin"); lifting it merely promoted
    ZeroTier. v2 worked from the peer route but had D-1..D-5. v3 is the
    audit-remediable version.
#>
[CmdletBinding()]
param(
  [ValidateSet('status','snapshot','apply','restore','list-backups','tx-selftest')]
  [string] $Action = 'status',
  [string] $PeerIp,
  [int]    $Margin = 1000,
  [string] $BackupDir,
  [string] $BackupFile,
  [switch] $DryRun
)

$ErrorActionPreference = 'Continue'
$script:Failures = @()

if (-not $BackupDir) {
  $BackupDir = Join-Path $env:USERPROFILE 'civlink-metric-backups'
}

function Write-Head($t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan }
function Write-Ok($t)   { Write-Host $t -ForegroundColor Green }
function Write-Warn2($t){ Write-Host $t -ForegroundColor Yellow }
function Write-Bad($t)  { Write-Host $t -ForegroundColor Red }

function Test-Admin {
  $id = [Security.Principal.WindowsIdentity]::GetCurrent()
  $p  = New-Object Security.Principal.WindowsPrincipal($id)
  return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-IfName([int]$idx) {
  $a = Get-NetAdapter -InterfaceIndex $idx -ErrorAction SilentlyContinue
  if ($a) { return $a.Name }
  return "(if$idx)"
}

function Get-IfRow([int]$idx) {
  $ipif = Get-NetIPInterface -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $ipif) { return $null }
  return [pscustomobject]@{
    ifIndex = $idx
    Name    = (Get-IfName $idx)
    Metric  = [int]$ipif.InterfaceMetric
    Auto    = "$($ipif.AutomaticMetric)"
  }
}

function Get-IfaceTable {
  $rows = @()
  foreach ($ipif in (Get-NetIPInterface -AddressFamily IPv4 -ErrorAction SilentlyContinue |
                       Where-Object { $_.ConnectionState -ne 'Disconnected' })) {
    $idx  = $ipif.ifIndex
    $addr = Get-NetIPAddress -InterfaceIndex $idx -AddressFamily IPv4 -ErrorAction SilentlyContinue |
              Where-Object { $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1
    $rows += [pscustomobject]@{
      ifIndex = $idx
      Name    = (Get-IfName $idx)
      Metric  = [int]$ipif.InterfaceMetric
      Auto    = "$($ipif.AutomaticMetric)"
      IPv4    = if ($addr) { "$($addr.IPAddress)/$($addr.PrefixLength)" } else { '-' }
    }
  }
  return @($rows | Sort-Object Metric)
}

function Show-Ifaces($rows) {
  Write-Head '--- IPv4 interfaces (sorted by InterfaceMetric) ---'
  $fmt = @{Expression={$_.ifIndex};Label='ifIndex';Width=7},
         @{Expression={$_.Name};Label='Name';Width=40},
         @{Expression={$_.Metric};Label='Metric';Width=7},
         @{Expression={$_.Auto};Label='Auto';Width=9},
         @{Expression={$_.IPv4};Label='IPv4';Width=20}
  Write-Host (($rows | Format-Table $fmt -AutoSize | Out-String).TrimEnd())
}

function Get-BcastExit {
  $rt = Find-NetRoute -RemoteIPAddress '255.255.255.255' -ErrorAction SilentlyContinue |
          Where-Object { $_.PSObject.Properties.Name -contains 'InterfaceIndex' } | Select-Object -First 1
  if (-not $rt) { return $null }
  return [pscustomobject]@{ ifIndex = [int]$rt.InterfaceIndex; Name = (Get-IfName $rt.InterfaceIndex); SrcIp = $rt.IPAddress }
}

function Show-BcastExit([string]$Tag) {
  Write-Head "--- 255.255.255.255 would leave through ($Tag) ---"
  Write-Host '    (prediction from the routing table - NOT a measured packet path)' -ForegroundColor Gray
  $e = Get-BcastExit
  if ($e) {
    Write-Warn2 ("    if={0}  {1}   srcIp={2}" -f $e.ifIndex, $e.Name, $e.SrcIp)
  } else {
    Write-Bad '    (Find-NetRoute returned nothing)'
  }
  return $e
}

function Test-IfExcluded([object]$row) {
  <# interfaces that must never be touched by this helper.
     D-6 (v3): a metric raise used to include the loopback interface, which
     carries no broadcast and whose metric Windows recomputes; touching it is
     pointless and needlessly widens the blast radius. #>
  $name = "$($row.Name)"
  $ipv4 = "$($row.IPv4)"
  if ($name -match '(?i)loopback')                        { return $true }
  if ($ipv4 -like '127.*')                                { return $true }
  if ($name -match '(?i)^\(if\d+\)$' -and $ipv4 -like '127.*') { return $true }
  return $false
}

function Get-PeerPath([string]$ip) {
  if (-not $ip) { return $null }
  Write-Head "--- path to peer $ip ---"
  $rt = Find-NetRoute -RemoteIPAddress $ip -ErrorAction SilentlyContinue |
          Where-Object { $_.PSObject.Properties.Name -contains 'InterfaceIndex' } | Select-Object -First 1
  if (-not $rt) { Write-Bad '    (no route)'; return $null }
  $p = [pscustomobject]@{
    ifIndex = [int]$rt.InterfaceIndex
    Name    = (Get-IfName $rt.InterfaceIndex)
    SrcIp   = $rt.IPAddress
    NextHop = $rt.NextHop
    Dest    = $rt.DestinationPrefix
    OnLink  = ($rt.NextHop -eq '0.0.0.0')
  }
  Write-Warn2 ("    if={0}  {1}   srcIp={2}   nextHop={3}   dest={4}   onLink={5}" -f `
    $p.ifIndex, $p.Name, $p.SrcIp, $p.NextHop, $p.Dest, $p.OnLink)
  return $p
}

function Set-Metric([int]$idx, [int]$metric, [string]$auto) {
  <# sets metric (+ automatic state) and THROWS on failure - no silent continue #>
  Set-NetIPInterface -InterfaceIndex $idx -AddressFamily IPv4 -InterfaceMetric $metric -ErrorAction Stop | Out-Null
  if ($auto -eq 'Disabled') {
    Set-NetIPInterface -InterfaceIndex $idx -AddressFamily IPv4 -AutomaticMetric Disabled -ErrorAction Stop | Out-Null
  } elseif ($auto -eq 'Enabled') {
    Set-NetIPInterface -InterfaceIndex $idx -AddressFamily IPv4 -AutomaticMetric Enabled -ErrorAction Stop | Out-Null
  }
}

function Test-Row($idx, $metric, [string]$auto, [string]$label) {
  <#
    Readback verification of one interface; records a failure on mismatch.

    $metric may be $null to skip the numeric comparison. That is required when
    the expected state is AutomaticMetric=Enabled: re-enabling automatic metric
    makes Windows recompute the value from link speed, so the number after the
    call is by design not the number that was written. Comparing it would report
    a failure for a correctly restored adapter.
  #>
  $idx = [int]$idx
  $row = Get-IfRow $idx
  if (-not $row) {
    $script:Failures += "$label if=$idx readback: interface disappeared"
    return $false
  }
  $okM = ($null -eq $metric) -or ($row.Metric -eq [int]$metric)
  $okA = ("$auto" -eq '' -or $row.Auto -eq $auto)
  $mark = if ($okM -and $okA) { 'OK  ' } else { 'FAIL' }
  $line = "    [{0}] {1} if={2,-3} {3,-34} metric={4,-6}(want {5,-6}) auto={6,-8}(want {7})" -f `
            $mark, $label, $idx, $row.Name, $row.Metric, $metric, $row.Auto, $(if($auto){$auto}else{'-'})
  if ($okM -and $okA) { Write-Host $line -ForegroundColor Green } else {
    Write-Host $line -ForegroundColor Red
    $script:Failures += "$label if=$idx readback metric=$($row.Metric) want=$metric auto=$($row.Auto) want=$auto"
  }
  return ($okM -and $okA)
}

function Get-BackupList {
  param([switch]$IncludeRestored)
  if (-not (Test-Path $BackupDir)) { return @() }
  $all = @(Get-ChildItem -Path $BackupDir -Filter 'civlink-metric-*.json*' -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -notlike '*.sha256' -and $_.Name -notlike '*.tmp' } |
             Sort-Object LastWriteTime)
  $apply = @($all | Where-Object { $_.Name -notlike '*.restored.json' })
  if ($IncludeRestored) { return $all }
  return $apply
}

function Get-RestoredList {
  if (-not (Test-Path $BackupDir)) { return @() }
  return @(Get-ChildItem -Path $BackupDir -Filter 'civlink-metric-*.restored.json' -ErrorAction SilentlyContinue |
             Sort-Object LastWriteTime)
}

function Read-Backup([string]$path) {
  try {
    $b = Get-Content $path -Raw -ErrorAction Stop | ConvertFrom-Json
  } catch {
    Write-Bad ("!! backup is not readable JSON: {0} ({1})" -f $path, $_.Exception.Message)
    return $null
  }
  if (-not $b.schema -or [int]$b.schema -lt 2) {
    Write-Bad ("!! backup has no schema>=2 marker (likely a v2 backup written by the defective script): {0}" -f $path)
    Write-Bad '   v2 backups do not record keep-interface originals and may hold an empty change set.'
    return $null
  }
  # R-3 (REV-006): a backup taken on another machine must never be applied here -
  # ifIndex values are only meaningful on the host that produced them.
  if ("$($b.host)" -ne "$env:COMPUTERNAME") {
    Write-Bad ("!! backup was taken on host '{0}', this machine is '{1}'" -f $b.host, $env:COMPUTERNAME)
    Write-Bad '   ifIndex values are host-specific. Refusing to apply a foreign backup.'
    return $null
  }
  return $b
}

# ================================================================== tx ops
# Test seam for the backup file transaction (REV-008 ③/④).
# Every filesystem operation the transaction performs goes through this table,
# so a test can make exactly one step fail and observe what is left behind.
# Production runs use the real implementations below; nothing else may swap it.
$script:TxOps = @{
  OpenCreateNew = { param($path) [IO.File]::Open($path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write) }
  WriteAllText  = { param($path, $text, $enc) [IO.File]::WriteAllText($path, $text, $enc) }
  ReadAllText   = { param($path) [IO.File]::ReadAllText($path, [Text.Encoding]::UTF8) }
  Hash          = { param($path) (Get-FileHash $path -Algorithm SHA256).Hash }
  Move          = { param($src, $dst) Move-Item -Path $src -Destination $dst -ErrorAction Stop }
  Remove        = { param($path) if (Test-Path $path) { Remove-Item $path -Force -ErrorAction SilentlyContinue } }
  Exists        = { param($path) (Test-Path $path) }
}

function Invoke-BackupTx {
  <#
    Writes an apply-backup as a two-phase file transaction.

    Phases: stage the JSON (temp) -> verify it by hash AND by re-parsing it ->
    stage the sidecar (temp) -> verify the sidecar by readback -> commit the
    sidecar -> commit the JSON -> confirm the committed hash.

    On any failure the whole set is removed again, so the caller can never see
    "a backup that exists but was not verified". Returns:
      Ok       : $true only if both files are committed and verified
      Stage    : last stage entered (also the stage that failed)
      Message  : failure text
      Residual : files still present after the cleanup attempt
      FinalHash: committed JSON hash when Ok

    Scope limit (REV-008): this is an ORDERED SEQUENCE OF FILE OPERATIONS, not
    an atomic multi-file commit. If the process is killed between the two
    Move-Item calls the cleanup never runs. The residual list exists so a
    leftover can be reported instead of silently trusted.
  #>
  param($Payload, [string]$BakPath)

  $ops    = $script:TxOps
  $tmp    = "$BakPath.tmp"
  $sTmp   = "$BakPath.sha256.tmp"
  $side   = "$BakPath.sha256"
  $stage  = 'start'
  $msg    = $null
  $final  = $null
  $done   = $false

  try {
    $json = $Payload | ConvertTo-Json -Depth 6
    $enc  = [Text.UTF8Encoding]::new($true)

    $stage = 'json-stage'
    $fs = & $ops.OpenCreateNew $tmp
    try {
      $bytes = $enc.GetBytes($json)
      $fs.Write($bytes, 0, $bytes.Length)
      $fs.Flush($true)
    } finally { try { $fs.Close() } catch { } }

    $stage = 'json-hash'
    $hash = & $ops.Hash $tmp

    $stage = 'json-verify'
    $back = (& $ops.ReadAllText $tmp) | ConvertFrom-Json
    if ([int]$back.schema -lt 3)                        { throw 'schema readback < 3' }
    if ("$($back.host)" -ne "$($Payload.host)")         { throw 'host readback mismatch' }
    if ("$($back.peerIp)" -ne "$($Payload.peerIp)")     { throw 'peerIp readback mismatch' }
    if (@($back.changed).Count -ne @($Payload.changed).Count) { throw 'changed count readback mismatch' }
    if (-not $back.keep -or [int]$back.keep.ifIndex -ne [int]$Payload.keepIf) { throw 'keep readback mismatch' }

    $stage = 'sidecar-stage'
    & $ops.WriteAllText $sTmp "$hash`n" ([Text.ASCIIEncoding]::new())

    $stage = 'sidecar-verify'
    $sBack = ((& $ops.ReadAllText $sTmp) -replace "`r", '').Trim()
    if ($sBack -ne $hash) { throw "sidecar readback mismatch: wrote '$hash' got '$sBack'" }

    $stage = 'sidecar-commit'
    & $ops.Move $sTmp $side

    $stage = 'json-commit'
    & $ops.Move $tmp $BakPath

    $stage = 'hash-confirm'
    $committed = & $ops.Hash $BakPath
    if ($committed -ne $hash) { throw "committed backup hash differs from the verified temp hash" }

    $final = $hash
    $done  = $true
    $stage = 'done'
  } catch {
    $msg = $_.Exception.Message
  }

  if (-not $done) {
    # Undo attempt. A failure here is itself recorded: it means a file may be
    # left on disk, and the caller must report that instead of "nothing happened".
    try {
      & $ops.Remove $tmp
      & $ops.Remove $sTmp
      & $ops.Remove $side
      & $ops.Remove $BakPath
    } catch {
      $msg = "$msg ; cleanup also failed: $($_.Exception.Message)"
    }
  }

  # Residual = anything still on disk that the caller must NOT trust.
  # On success the two committed files are expected, so they are not residual.
  $watch = if ($done) { @($tmp, $sTmp) } else { @($tmp, $sTmp, $side, $BakPath) }
  $residual = @()
  foreach ($p in $watch) {
    try { if (& $ops.Exists $p) { $residual += $p } } catch { }
  }

  return [pscustomobject]@{
    Ok = $done; Stage = $stage; Message = $msg; Residual = $residual; FinalHash = $final
  }
}

function Get-PrecheckDrift {
  <#
    Pure restore-precheck (no adapter access): given the backup and the CURRENT
    field values of every interface it would write, return the drift list.

    REV-008 R-3b: Set-NetIPInterface -InterfaceMetric AUTOMATICALLY disables
    AutomaticMetric (official docs). apply therefore leaves a changed adapter in
    (TargetMetric, Disabled), not (TargetMetric, OriginalAuto). The allowed set
    for a changed adapter's AutomaticMetric is consequently
      { OriginalAuto   (apply has not run yet / partially run)
        Disabled       (apply ran and the setter disabled it) }
    and nothing else - in particular not "Enabled" on an adapter whose original
    was Disabled, which would be a third party re-enabling it.
  #>
  param($Backup, [hashtable]$Rows, [scriptblock]$NameDrift)

  $drift = @()
  foreach ($e in @($Backup.changed)) {
    $idx = [int]$e.ifIndex
    $now = $Rows[$idx]
    if (-not $now) { $drift += [pscustomobject]@{ ifIndex=$idx; Name=$e.Name; Field='-'; Expect='present'; Now='(missing)'; Why='interface gone' }; continue }
    if (& $NameDrift $e.Name $now.Name) {
      $drift += [pscustomobject]@{ ifIndex=$idx; Name=$e.Name; Field='Name'; Expect=$e.Name; Now=$now.Name; Why='ifIndex now belongs to a different adapter' }
    }
    if ([int]$now.Metric -ne [int]$e.TargetMetric -and [int]$now.Metric -ne [int]$e.OriginalMetric) {
      $drift += [pscustomobject]@{ ifIndex=$idx; Name=$e.Name; Field='Metric'; Expect="$($e.OriginalMetric)/$($e.TargetMetric)"; Now=$now.Metric; Why='neither original nor target' }
    }
    $autoOk = (@("$($e.OriginalAuto)", 'Disabled') -contains "$($now.Auto)")
    if (-not $autoOk) {
      $drift += [pscustomobject]@{ ifIndex=$idx; Name=$e.Name; Field='AutomaticMetric'; Expect="$(if("$($e.OriginalAuto)" -eq 'Disabled'){'Disabled'}else{"$($e.OriginalAuto)/Disabled"})"; Now=$now.Auto; Why='expected the original value or the value the metric setter leaves behind' }
    }
  }
  $k = $Backup.keep
  if (-not $k) {
    $drift += [pscustomobject]@{ ifIndex=0; Name='(keep)'; Field='-'; Expect='record'; Now='(missing)'; Why='backup has no keep record' }
    return $drift
  }
  $kIdx = [int]$k.ifIndex
  $know = $Rows[$kIdx]
  if (-not $know) { $drift += [pscustomobject]@{ ifIndex=$kIdx; Name=$k.Name; Field='-'; Expect='present'; Now='(missing)'; Why='keep interface gone' } }
  else {
    if (& $NameDrift $k.Name $know.Name) {
      $drift += [pscustomobject]@{ ifIndex=$kIdx; Name=$k.Name; Field='Name'; Expect=$k.Name; Now=$know.Name; Why='ifIndex now belongs to a different adapter' }
    }
    if ([int]$know.Metric -ne [int]$k.TargetMetric -and [int]$know.Metric -ne [int]$k.OriginalMetric) {
      $drift += [pscustomobject]@{ ifIndex=$kIdx; Name=$k.Name; Field='Metric'; Expect="$($k.OriginalMetric)/$($k.TargetMetric)"; Now=$know.Metric; Why='neither original nor target' }
    }
    if ("$($know.Auto)" -ne 'Disabled' -and "$($know.Auto)" -ne "$($k.OriginalAuto)") {
      $drift += [pscustomobject]@{ ifIndex=$kIdx; Name=$k.Name; Field='AutomaticMetric'; Expect="Disabled/$($k.OriginalAuto)"; Now=$know.Auto; Why='expected the pinned value or the original' }
    }
  }
  return $drift
}

# ------------------------------------------------------------ tx self-test
if ($Action -eq 'tx-selftest') {
  <#
    Fault injection for the two-phase backup commit (REV-008 ③/④).
    Runs entirely in a temp directory. It never calls Set-NetIPInterface and
    never touches a real adapter or the real backup directory.
  #>
  $work = Join-Path $env:TEMP ("civlink-tx-selftest-" + [guid]::NewGuid().ToString('N').Substring(0,8))
  New-Item -ItemType Directory -Force -Path $work | Out-Null
  Write-Head ("[tx-selftest] isolated directory: {0}" -f $work)

  $payload = [pscustomobject]@{
    schema='4'; kind='apply'; takenAt=(Get-Date).ToString('o'); host=$env:COMPUTERNAME
    peerIp='192.0.2.10'; keepIf=10
    keep=[pscustomobject]@{ ifIndex=10; Name='TEST-KEEP'; OriginalMetric=45; OriginalAuto='Enabled'; TargetMetric=45 }
    changed=@([pscustomobject]@{ ifIndex=18; Name='TEST-RAISE'; OriginalMetric=1; OriginalAuto='Enabled'; TargetMetric=1045; TargetAuto='Disabled' })
  }

  $realOps = $script:TxOps
  $results = @()
  $failStages = @('json-stage','json-hash','json-verify','sidecar-stage','sidecar-verify','sidecar-commit','json-commit','hash-confirm','cleanup')
  $n = 0
  foreach ($st in $failStages) {
    $n++
    $bak = Join-Path $work ("case{0}-{1}.json" -f $n, $st)
    # one operation fails; everything else behaves normally
    $inj = @{}
    foreach ($k2 in $realOps.Keys) { $inj[$k2] = $realOps[$k2] }
    switch ($st) {
      'json-stage'    { $inj.OpenCreateNew = { param($p) throw 'injected: cannot create temp json' } }
      'json-hash'     { $inj.Hash          = { param($p) if ("$p" -like '*.tmp') { throw 'injected: hash failed' } (Get-FileHash $p -Algorithm SHA256).Hash } }
      'json-verify'   { $inj.ReadAllText   = { param($p) if ("$p" -like '*.tmp') { '{"schema":1}' } else { [IO.File]::ReadAllText($p,[Text.Encoding]::UTF8) } } }
      'sidecar-stage' { $inj.WriteAllText  = { param($p,$t,$e) if ("$p" -like '*.sha256.tmp') { throw 'injected: cannot write sidecar temp' } [IO.File]::WriteAllText($p,$t,$e) } }
      'sidecar-verify'{ $inj.ReadAllText   = { param($p) if ("$p" -like '*.sha256.tmp') { 'deadbeef' + "`n" } else { [IO.File]::ReadAllText($p,[Text.Encoding]::UTF8) } } }
      'sidecar-commit'{ $inj.Move          = { param($s,$d) if ("$d" -like '*.sha256') { throw 'injected: sidecar commit failed' } Move-Item -Path $s -Destination $d -ErrorAction Stop } }
      'json-commit'   { $inj.Move          = { param($s,$d) if ("$d" -like '*.json') { throw 'injected: json commit failed' } Move-Item -Path $s -Destination $d -ErrorAction Stop } }
      'hash-confirm'  { $inj.Hash          = { param($p) if ("$p" -like '*.json' -and "$p" -notlike '*.tmp') { ('0' * 64) } else { (Get-FileHash $p -Algorithm SHA256).Hash } } }
      'cleanup'       {
        # a failure happened AND the cleanup itself fails: the transaction must
        # report the leftovers instead of claiming nothing was written
        $inj.Move   = { param($s,$d) if ("$d" -like '*.json') { throw 'injected: json commit failed' } Move-Item -Path $s -Destination $d -ErrorAction Stop }
        $inj.Remove = { param($p) if ("$p" -like '*.sha256.tmp') { throw 'injected: cleanup failed' } if (Test-Path $p) { Remove-Item $p -Force -ErrorAction SilentlyContinue } }
      }
    }
    $script:TxOps = $inj
    try { $r = Invoke-BackupTx -Payload $payload -BakPath $bak } finally { $script:TxOps = $realOps }

    $jsonExists    = Test-Path $bak
    $sidecarExists = Test-Path "$bak.sha256"
    $sidecarValid  = $false
    if ($sidecarExists -and (Test-Path $bak)) {
      $sv = (Get-Content "$bak.sha256" -Raw -ErrorAction SilentlyContinue)
      $sv = if ($null -eq $sv) { '' } else { $sv.Trim() }
      $sidecarValid = ($sv -match '^[0-9A-Fa-f]{64}$') -and ($sv.ToUpperInvariant() -eq (Get-FileHash $bak -Algorithm SHA256).Hash)
    } elseif ($sidecarExists) {
      # sidecar without a JSON: by definition unusable, and a leftover the user
      # would have to remove by hand
      $sidecarValid = $false
    }
    $okCase = (-not $r.Ok) -and (-not $jsonExists) -and (-not $sidecarValid)
    if ($st -eq 'cleanup') {
      # The injected cleanup failure is EXPECTED to leave files behind; what must
      # hold is that the transaction reported failure and listed the leftovers.
      $okCase = (-not $r.Ok) -and ($r.Residual.Count -gt 0) -and ($r.Message -match 'cleanup also failed')
      Remove-Item (Join-Path $work '*') -Force -ErrorAction SilentlyContinue
    }
    $results += [pscustomobject]@{
      Stage=$st; Ok=$okCase; ReportedFailure=(-not $r.Ok); StageSeen=$r.Stage
      JsonLeft=$jsonExists; SidecarLeft=$sidecarExists; SidecarValid=$sidecarValid
      Residual=$r.Residual.Count; Message=$r.Message
    }
  }

  # success case: both files must exist, sidecar must verify, hash must match
  $bakOk = Join-Path $work 'case-ok.json'
  $script:TxOps = $realOps
  $ok = Invoke-BackupTx -Payload $payload -BakPath $bakOk
  $okHash = if (Test-Path $bakOk) { (Get-FileHash $bakOk -Algorithm SHA256).Hash } else { '' }
  $sideOk = if (Test-Path "$bakOk.sha256") { ((Get-Content "$bakOk.sha256" -Raw).Trim()) } else { '' }
  $okCase2 = $ok.Ok -and (Test-Path $bakOk) -and (Test-Path "$bakOk.sha256") -and ($sideOk -eq $okHash) -and ($ok.Residual.Count -eq 0)

  Write-Host ''
  Write-Host ' stage            ok  reported  stageSeen        jsonLeft sidecarLeft sidecarValid residual' -ForegroundColor Cyan
  foreach ($r in $results) {
    $mark = if ($r.Ok) { 'PASS' } else { 'FAIL' }
    $line = "    {0,-15} {1,-5} {2,-9} {3,-16} {4,-8} {5,-11} {6,-12} {7}" -f $r.Stage, $mark, $r.ReportedFailure, $r.StageSeen, $r.JsonLeft, $r.SidecarLeft, $r.SidecarValid, $r.Residual
    if ($r.Ok) { Write-Host $line } else { Write-Host $line -ForegroundColor Red }
  }
  $line2 = "    {0,-15} {1,-5}" -f 'success-path', $(if ($okCase2) { 'PASS' } else { 'FAIL' })
  if ($okCase2) { Write-Host $line2 } else { Write-Host $line2 -ForegroundColor Red }

  # precheck cases (REV-008 ③): plain data, no adapters involved
  $nd = { param($a, $b) return ("$a" -ne "$b") }
  $bk = [pscustomobject]@{
    keep=[pscustomobject]@{ ifIndex=10; Name='WLAN'; OriginalMetric=45; OriginalAuto='Enabled'; TargetMetric=45 }
    changed=@([pscustomobject]@{ ifIndex=18; Name='Radmin VPN'; OriginalMetric=1; OriginalAuto='Enabled'; TargetMetric=1045; TargetAuto='Disabled' })
  }
  $p1 = @{ 10=@{ ifIndex=10; Name='WLAN'; Metric=45; Auto='Disabled' }
           18=@{ ifIndex=18; Name='Radmin VPN'; Metric=1045; Auto='Disabled' } }
  $p2 = @{ 10=@{ ifIndex=10; Name='WLAN'; Metric=45; Auto='Disabled' }
           18=@{ ifIndex=18; Name='Radmin VPN'; Metric=9966; Auto='Disabled' } }
  $p3 = @{ 10=@{ ifIndex=10; Name='WLAN'; Metric=45; Auto='Disabled' }
           18=@{ ifIndex=18; Name='Radmin VPN'; Metric=1045; Auto='Enabled' } }
  # REV-008 ③: the decisive case - a changed adapter whose ONLY original was
  # AutomaticMetric=Enabled must still be restorable after a real apply, because
  # the metric setter disabled AutomaticMetric in the meantime.
  $bkOff = [pscustomobject]@{
    keep=[pscustomobject]@{ ifIndex=10; Name='WLAN'; OriginalMetric=35; OriginalAuto='Enabled'; TargetMetric=35 }
    changed=@([pscustomobject]@{ ifIndex=15; Name='ZeroTier'; OriginalMetric=9999; OriginalAuto='Disabled'; TargetMetric=1035; TargetAuto='Disabled' })
  }
  $pOff = @{ 10=@{ ifIndex=10; Name='WLAN'; Metric=35; Auto='Disabled' }
             15=@{ ifIndex=15; Name='ZeroTier'; Metric=1035; Auto='Disabled' } }
  $pOn3 = @{ 10=@{ ifIndex=10; Name='WLAN'; Metric=35; Auto='Disabled' }
             15=@{ ifIndex=15; Name='ZeroTier'; Metric=1035; Auto='Enabled' } }
  $c1  = @(Get-PrecheckDrift -Backup $bk    -Rows $p1   -NameDrift $nd).Count  # applied, orig Enabled -> pass
  $c2  = @(Get-PrecheckDrift -Backup $bk    -Rows $p2   -NameDrift $nd).Count  # foreign metric -> fail
  $c3  = @(Get-PrecheckDrift -Backup $bkOff -Rows $pOff -NameDrift $nd).Count  # applied, orig Disabled -> pass
  $c4  = @(Get-PrecheckDrift -Backup $bkOff -Rows $pOn3 -NameDrift $nd).Count  # 3rd party re-enabled (orig Disabled) -> fail
  Write-Host ''
  Write-Host (" [precheck] applied(orig=Enabled)={0}(0)  foreign metric={1}(>0)  applied(orig=Disabled)={2}(0)  re-enabled-after-Disabled={3}(>0)" -f $c1,$c2,$c3,$c4) -ForegroundColor Cyan
  $pcOk = ($c1 -eq 0 -and $c2 -gt 0 -and $c3 -eq 0 -and $c4 -gt 0)

  Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue

  $allOk = ($results | Where-Object { -not $_.Ok }).Count -eq 0
  Write-Host ''
  if ($allOk -and $okCase2 -and $pcOk) {
    Write-Ok '[PASS] two-phase commit fault injection + precheck cases'
    exit 0
  }
  Write-Bad '[FAIL] see the table above'
  exit 2
}

# ------------------------------------------------------------------ banner
Write-Host '======================================================' -ForegroundColor Green
Write-Host ' CivLink M0-A  --  broadcast path helper  (v3.3)' -ForegroundColor Green
Write-Host '======================================================' -ForegroundColor Green
# REV-009 asked for the concrete file identity in every archived run, not just
# a fuzzy version label. Print the real hash of the script that is executing.
try {
  if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
    Write-Host ("Script SHA : {0}" -f (Get-FileHash $PSCommandPath -Algorithm SHA256).Hash)
  }
} catch { }
Write-Host ("Admin      : {0}" -f (Test-Admin))
Write-Host ("Action     : {0}" -f $Action)
Write-Host ("DryRun     : {0}" -f ([bool]$DryRun))
Write-Host ("BackupDir  : {0}" -f $BackupDir)
if ($PeerIp) { Write-Host ("Peer       : {0}" -f $PeerIp) }

# ------------------------------------------------------------- list-backups
if ($Action -eq 'list-backups') {
  Write-Head "--- backups in $BackupDir ---"
  $list = Get-BackupList
  if ($list.Count -eq 0) { Write-Warn2 '    (none)'; exit 0 }
  foreach ($f in $list) {
    $b = Read-Backup $f.FullName
    if (-not $b) { Write-Bad ("    {0}  <unusable>" -f $f.Name); continue }
    $n = @($b.changed).Count
    Write-Host ("    {0}  schema={1}  peer={2,-16} keepIf={3,-3} changed={4}" -f `
      $f.Name, $b.schema, $b.peerIp, $b.keepIf, $n)
  }
  exit 0
}

$before = Get-IfaceTable
Show-Ifaces $before
$exit0 = Show-BcastExit 'now'
$peer  = Get-PeerPath $PeerIp

# ------------------------------------------------------------------ status
if ($Action -eq 'status') {
  Write-Host ''
  if ($peer) {
    if ($exit0 -and $exit0.ifIndex -eq $peer.ifIndex) {
      Write-Ok ("[OK] predicted broadcast exit (if={0}) EQUALS peer path (if={1})" -f $exit0.ifIndex, $peer.ifIndex)
    } else {
      Write-Bad ("[FIX WOULD BE NEEDED] predicted broadcast exit if={0} but peer is reachable via if={1}" -f `
        $(if($exit0){$exit0.ifIndex}else{'?'}), $peer.ifIndex)
      Write-Host '    Prediction only. The authoritative check is `verify`-style: send real' -ForegroundColor Gray
      Write-Host '    packets and observe which adapter they leave from.' -ForegroundColor Gray
    }
  } else {
    Write-Host 'Tip: pass -PeerIp <peer address> so the script can say whether a fix would be needed.' -ForegroundColor Gray
  }
  Write-Host ''
  Write-Host 'Nothing was changed.' -ForegroundColor Gray
  exit 0
}

# ---------------------------------------------------------------- snapshot
if ($Action -eq 'snapshot') {
  if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  $snap = [pscustomobject]@{
    schema        = 2
    kind          = 'snapshot'
    takenAt       = (Get-Date).ToString('o')
    host          = $env:COMPUTERNAME
    peerIp        = $PeerIp
    broadcastExit = if ($exit0) { [pscustomobject]@{ ifIndex = $exit0.ifIndex; Name = $exit0.Name; SrcIp = $exit0.SrcIp; note = 'routing-table prediction' } } else { $null }
    peerPath      = $peer
    interfaces    = @($before)
  }
  $jsonPath = Join-Path $BackupDir ("civlink-state-$stamp.json")
  $snap | ConvertTo-Json -Depth 6 | Set-Content -Path $jsonPath -Encoding UTF8
  $txtPath = Join-Path $BackupDir ("civlink-state-$stamp.txt")
  $lines = @(
    "CivLink state snapshot  $($snap.takenAt)  host=$($snap.host)  peer=$PeerIp",
    ("broadcast exit (predicted) : if={0} {1} srcIp={2}" -f $(if($exit0){$exit0.ifIndex}else{'?'}), $(if($exit0){$exit0.Name}else{'?'}), $(if($exit0){$exit0.SrcIp}else{'?'})),
    ("peer path                   : " + $(if($peer){"if=$($peer.ifIndex) $($peer.Name) srcIp=$($peer.SrcIp) nextHop=$($peer.NextHop)"}else{'(none)'})),
    '',
    'ifIndex  metric  auto      ipv4                    name'
  ) + @($before | ForEach-Object { "{0,-8} {1,-7} {2,-9} {3,-23} {4}" -f $_.ifIndex, $_.Metric, $_.Auto, $_.IPv4, $_.Name })
  $lines | Set-Content -Path $txtPath -Encoding UTF8
  Write-Ok ("[snapshot] written -> {0}" -f $jsonPath)
  Write-Ok ("[snapshot] written -> {0}" -f $txtPath)
  Write-Host 'Nothing was changed.' -ForegroundColor Gray
  exit 0
}

# ------------------------------------------------------------------- apply
# NOTE: the administrator gate is inside each action, AFTER -DryRun handling,
#       so a dry run stays a read-only operation (v2 gated before doing anything).
if ($Action -eq 'apply') {
  if (-not $peer) {
    Write-Host ''
    Write-Bad '!! -PeerIp is required for apply: the script must know which adapter'
    Write-Bad '   can actually reach the peer before it decides what to raise.'
    Write-Host '   Example:  -Action apply -PeerIp 192.168.31.59' -ForegroundColor Gray
    exit 2
  }

  $keep = $peer.ifIndex
  $keepRow = $before | Where-Object { $_.ifIndex -eq $keep } | Select-Object -First 1
  if (-not $keepRow) { Write-Bad "!! peer interface if=$keep is not in the IPv4 table"; exit 2 }

  $keepOriginal = Get-IfRow $keep
  if (-not $keepOriginal) { Write-Bad "!! cannot read current state of keep interface if=$keep"; exit 2 }

  $targetMetric = [int]$keepRow.Metric + $Margin
  if ($targetMetric -lt 100) { $targetMetric = 100 }

  $raise = @($before | Where-Object {
              $_.ifIndex -ne $keep -and $_.Metric -le $keepRow.Metric -and -not (Test-IfExcluded $_)
            })
  $excluded = @($before | Where-Object {
              $_.ifIndex -ne $keep -and $_.Metric -le $keepRow.Metric -and (Test-IfExcluded $_)
            })

  Write-Head '[plan]'
  Write-Host ("    keep   if={0} ({1}) metric={2} auto={3}" -f $keep, $keepRow.Name, $keepRow.Metric, $keepOriginal.Auto) -ForegroundColor Green
  if ($excluded.Count -gt 0) {
    Write-Host ("    skip   {0} interface(s) that carry no broadcast (loopback) - never touched:" -f $excluded.Count) -ForegroundColor Gray
    $excluded | ForEach-Object { Write-Host ("             if={0,-3} {1,-36} {2}" -f $_.ifIndex, $_.Name, $_.IPv4) -ForegroundColor Gray }
  }
  if ($raise.Count -gt 0) {
    Write-Host ("    raise  {0} interface(s) to metric {1}:" -f $raise.Count, $targetMetric) -ForegroundColor Green
    $raise | ForEach-Object { Write-Host ("             if={0,-3} {1,-36} {2,-6} -> {3}" -f $_.ifIndex, $_.Name, $_.Metric, $targetMetric) }
  }
  # R-4 (REV-006): -Force removed. Stacking a second apply on top of an
  # un-restored one makes "the newest backup" no longer mean "original
  # values", which is precisely how the v2 backup became unusable.
  # One outstanding apply per machine: restore first, then apply again.
  # NOTE: this check sits BEFORE the -DryRun early exit on purpose. A dry run
  # must predict what a real apply would do; if a real apply would be refused,
  # the dry run has to say so rather than print a plan that cannot execute.
  if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
  $existing = @(Get-BackupList | Where-Object {
      try { $x = Get-Content $_.FullName -Raw -ErrorAction Stop | ConvertFrom-Json; [int]$x.schema -ge 2 -and $x.kind -eq 'apply' } catch { $false }
    })
  if ($existing.Count -gt 0) {
    Write-Host ''
    Write-Bad ("[refused] an unrestored apply-backup already exists: {0}" -f $existing[-1].Name)
    Write-Bad '          Only ONE outstanding apply is allowed: a second apply would record'
    Write-Bad '          already-changed values as if they were original.'
    Write-Bad '          Restore first (-Action restore), then apply again.'
    exit 5
  }

  if ($raise.Count -eq 0) {
    Write-Warn2 '    no competing interface has a metric <= the keep interface'
    Write-Warn2 '    -> NOTHING TO DO. No backup will be written (v2 wrote an empty one here).'
    exit 0
  }

  if ($DryRun) {
    Write-Host ''
    Write-Warn2 '[DryRun] no change made, no backup written.'
    exit 0
  }

  if (-not (Test-Admin)) {
    Write-Host ''
    Write-Bad '!! apply needs administrator rights.'
    Write-Bad '   Right-click the .cmd file and choose "Run as administrator".'
    exit 1
  }

  # full pre-change record: keep interface original AND every changed interface original
  # R-1 (REV-006): a second-resolution timestamp can collide across peers or a -Force
  # rerun, and Set-Content would silently overwrite. Name carries a GUID and the file
  # is created with CreateNew, so a collision is an error, not a silent overwrite.
  $stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'
  $uniq   = [guid]::NewGuid().ToString('N').Substring(0,8)
  # REV-008 R-3b: pass the value the metric setter actually leaves behind.
  # Set-NetIPInterface -InterfaceMetric automatically disables AutomaticMetric,
  # so every changed adapter ends up (TargetMetric, Disabled) - recorded here so
  # the restore precheck can accept exactly that and nothing wider.
  $payload = [pscustomobject]@{
    schema   = 4
    kind     = 'apply'
    takenAt  = (Get-Date).ToString('o')
    host     = $env:COMPUTERNAME
    peerIp   = $PeerIp
    keepIf   = $keep
    keep     = [pscustomobject]@{ ifIndex = $keep; Name = $keepRow.Name
                                  OriginalMetric = [int]$keepOriginal.Metric
                                  OriginalAuto   = "$($keepOriginal.Auto)"
                                  TargetMetric   = [int]$keepRow.Metric
                                  TargetAuto     = 'Disabled' }
    changed  = @($raise | ForEach-Object { [pscustomobject]@{
                                  ifIndex = $_.ifIndex; Name = $_.Name
                                  OriginalMetric = [int]$_.Metric
                                  OriginalAuto   = "$($_.Auto)"
                                  TargetMetric   = $targetMetric
                                  TargetAuto     = 'Disabled' } })
    broadcastExitBefore = if ($exit0) { [pscustomobject]@{ ifIndex = $exit0.ifIndex; Name = $exit0.Name } } else { $null }
  }
  $bakPath = Join-Path $BackupDir ("civlink-metric-$stamp-$uniq.json")

  # R-2 (REV-006) / R-2 rev (REV-007): fail-closed backup write, now as an
  # injectable file transaction so the failure paths can be tested (REV-008).
  $tx = Invoke-BackupTx -Payload $payload -BakPath $bakPath
  if (-not $tx.Ok) {
    Write-Bad ("!! backup write/verify FAILED at stage '{0}': {1}" -f $tx.Stage, $tx.Message)
    if ($tx.Residual.Count -gt 0) {
      Write-Bad ("   Files could NOT be cleaned up ({0} left behind):" -f $tx.Residual.Count)
      $tx.Residual | ForEach-Object { Write-Bad ("     {0}" -f $_) }
      Write-Bad '   Remove them by hand before the next apply - a leftover sidecar or'
      Write-Bad '   JSON would otherwise be treated as a real, unrestored backup.'
    } else {
      Write-Bad '   Any partial backup file has been removed.'
    }
    Write-Bad '   Nothing was changed. No adapter has been touched.'
    exit 2
  }
  Write-Ok ("[1] backup written -> {0}" -f $bakPath)
  Write-Host ("    sha256={0}" -f $tx.FinalHash) -ForegroundColor Gray
  Write-Host ("    keep.OriginalMetric={0} keep.OriginalAuto={1} changed={2}" -f `
    $payload.keep.OriginalMetric, $payload.keep.OriginalAuto, @($payload.changed).Count) -ForegroundColor Gray
  Write-Host ''
  foreach ($e in $raise) {
    Write-Host ("[2] if={0} ({1}) metric {2} -> {3}" -f $e.ifIndex, $e.Name, $e.Metric, $targetMetric)
    try { Set-Metric -idx $e.ifIndex -metric $targetMetric -auto '' }
    catch { Write-Bad ("    !! failed: {0}" -f $_.Exception.Message); $script:Failures += "apply if=$($e.ifIndex): $($_.Exception.Message)" }
  }
  # pin the keep interface so it cannot drift on its own
  Write-Host ("[3] if={0} ({1}) AutomaticMetric -> Disabled (pin metric {2})" -f $keep, $keepRow.Name, $keepRow.Metric)
  try { Set-Metric -idx $keep -metric ([int]$keepRow.Metric) -auto 'Disabled' }
  catch { Write-Bad ("    !! failed: {0}" -f $_.Exception.Message); $script:Failures += "apply keep if=${keep}: $($_.Exception.Message)" }

  Start-Sleep -Milliseconds 900
  Write-Head '[verify] readback'
  # REV-008 ②: the setter disables AutomaticMetric on its own, so readback must
  # check that field too - asking Test-Row for '' would skip it and let an apply
  # whose automatic state differs from what the backup promises look healthy.
  foreach ($e in $raise) { Test-Row -idx $e.ifIndex -metric $targetMetric -auto 'Disabled' -label 'raised' | Out-Null }
  Test-Row -idx $keep -metric ([int]$keepRow.Metric) -auto 'Disabled' -label 'keep  ' | Out-Null
  Write-Host ("    recorded target state: changed => (metric={0}, auto=Disabled); keep => (metric={1}, auto=Disabled)" -f `
    $targetMetric, [int]$keepRow.Metric) -ForegroundColor Gray

  Show-Ifaces (Get-IfaceTable)
  $exit1 = Show-BcastExit 'after apply'

  Write-Host ''
  if ($script:Failures.Count -gt 0) {
    Write-Bad ("[FAIL] {0} readback/set failure(s):" -f $script:Failures.Count)
    $script:Failures | ForEach-Object { Write-Bad ("       - {0}" -f $_) }
    Write-Bad ("       Restore with: -Action restore -BackupFile '{0}'" -f $bakPath)
    exit 4
  }
  if ($exit1 -and $exit1.ifIndex -eq $keep) {
    Write-Ok ("[PASS] predicted broadcast exit is now if={0} ({1}) == peer path" -f $exit1.ifIndex, $exit1.Name)
    Write-Host '       Prediction only - confirm with real packets before trusting it.' -ForegroundColor Gray
  } else {
    Write-Warn2 ("[WARN] predicted exit if={0}, expected if={1}" -f $(if($exit1){$exit1.ifIndex}else{'?'}), $keep)
    Write-Warn2 '       Metrics are set and verified, but the routing-table prediction disagrees.'
    Write-Warn2 '       Do not report this run as a success; report the observation.'
  }
  Write-Host ''
  Write-Host ("Restore later:  -Action restore -BackupFile '{0}'" -f $bakPath) -ForegroundColor Gray
  exit 0
}

# ----------------------------------------------------------------- restore
if ($Action -eq 'restore') {
  if (-not $BackupFile) {
    $list = @(Get-BackupList | Where-Object {
        try { $x = Get-Content $_.FullName -Raw -ErrorAction Stop | ConvertFrom-Json; [int]$x.schema -ge 2 -and $x.kind -eq 'apply' } catch { $false }
      })
    if ($list.Count -eq 0) {
      Write-Host ''
      Write-Bad ("!! no v3 apply-backup found in {0}" -f $BackupDir)
      Write-Bad '   Nothing can be restored. Report this instead of guessing values.'
      Write-Bad '   (v2 backups in %USERPROFILE%\civlink-metric-backup.json are unusable: no keep originals.)'
      exit 2
    }
    $BackupFile = $list[-1].FullName
    Write-Host ("[0] auto-selected newest v3 backup: {0}" -f $BackupFile) -ForegroundColor Gray
  }

  if (-not (Test-Path $BackupFile)) {
    Write-Host ''
    Write-Bad ("!! backup not found: {0}" -f $BackupFile)
    exit 2
  }
  $bak = Read-Backup $BackupFile
  if (-not $bak) { exit 2 }

  # R-2b (REV-006) / R-2 rev (REV-007): a schema>=3 backup is only trustworthy if
  # it still matches the hash recorded when it was written. REV-007 asked for this
  # to be fail-closed: a missing/empty/malformed sidecar is a refusal, not a warning.
  # Only pre-schema-3 backups (which cannot be restored anyway - Read-Backup already
  # rejected schema<2, and v2 backups have no keep originals) would take the lenient path.
  $sidecar = "$BackupFile.sha256"
  $actual  = (Get-FileHash $BackupFile -Algorithm SHA256).Hash
  if ([int]$bak.schema -ge 3) {
    if (-not (Test-Path $sidecar)) {
      Write-Bad ("!! schema={0} backup has no .sha256 sidecar: {1}" -f [int]$bak.schema, $BackupFile)
      Write-Bad '   Content identity cannot be proven, so the file may have been altered.'
      Write-Bad '   Refusing (REV-007 requires fail-closed for schema>=3).'
      exit 2
    }
    $expect = (Get-Content $sidecar -Raw -ErrorAction SilentlyContinue)
    $expect = if ($null -eq $expect) { '' } else { $expect.Trim() }
    if ($expect -notmatch '^[0-9A-Fa-f]{64}$') {
      Write-Bad ("!! sidecar is not a 64-hex SHA256: {0}" -f $sidecar)
      Write-Bad ("   content={0}" -f $(if ($expect) { $expect } else { '(empty)' }))
      exit 2
    }
    if ($expect.ToUpperInvariant() -ne $actual) {
      Write-Bad ("!! backup content does not match its sidecar hash: {0}" -f $BackupFile)
      Write-Bad ("   sidecar={0}" -f $expect)
      Write-Bad ("   actual ={0}" -f $actual)
      Write-Bad '   Refusing to restore from a backup that changed after it was written.'
      exit 2
    }
    Write-Host ("    sidecar hash verified: {0}" -f $actual) -ForegroundColor Gray
  } else {
    Write-Warn2 ("    schema={0} backup has no sidecar guarantee - content identity unproven" -f $bak.schema)
  }

  if ($bak.kind -ne 'apply') { Write-Bad ("!! backup kind is '{0}', not 'apply' - refusing" -f $bak.kind); exit 2 }
  $items = @($bak.changed)
  if ($items.Count -eq 0) {
    Write-Bad '!! this backup records ZERO changed interfaces - it cannot restore anything.'
    Write-Bad '   Refusing (this is the v2 empty-backup defect).'
    exit 2
  }

  Write-Host ''
  Write-Ok ("[1] restoring snapshot taken {0} on {1} (peer {2})" -f $bak.takenAt, $bak.host, $bak.peerIp)
  Write-Host ("    changes to revert: {0}; keep interface: if={1}" -f $items.Count, $bak.keepIf) -ForegroundColor Gray

  # R-3 (REV-006) / R-3 rev (REV-007) / R-3b (REV-008): before touching anything,
  # confirm EVERY field this restore is about to write is still in a state that
  # the recorded apply could have produced. Checking only some fields lets restore
  # silently overwrite a change made afterwards (by the user, a VPN client, or a
  # system service). The rule is: nothing may be written unless its current value
  # is in the allowed set for that field.
  #
  #   changed interfaces: apply writes only the metric, and only ever to
  #     TargetMetric. Set-NetIPInterface -InterfaceMetric AUTOMATICALLY DISABLES
  #     AutomaticMetric (official behaviour), so a successfully applied adapter
  #     sits at (TargetMetric, Disabled) whatever its original auto state was.
  #     Allowed therefore: metric in {OriginalMetric, TargetMetric} and
  #     AutomaticMetric in {OriginalAuto, Disabled}. Anything else - including an
  #     adapter whose original was Disabled but now reads Enabled - is a third
  #     party's change and must block the restore.
  #   keep interface: apply writes metric=keep.Metric and AutomaticMetric=Disabled.
  #     Allowed: metric in {OriginalMetric, TargetMetric} and AutomaticMetric in
  #     {Disabled, OriginalAuto}.
  #
  # The comparison itself lives in Get-PrecheckDrift so the same code can be
  # driven by the tx-selftest action with synthetic rows.
  if (-not $bak.keep) {
    Write-Bad '!! this backup has no keep-interface record - cannot precheck. Refusing.'
    exit 2
  }
  # Name comparison is only corroborating evidence, never a hard criterion:
  # Get-NetAdapter does not resolve every interface kind (loopback, some virtual
  # adapters), so Get-IfName falls back to "(ifN)". Comparing a recorded real name
  # against such a placeholder would fire a false "different adapter" drift.
  # Compare only when BOTH sides resolved to a real adapter name.
  function Test-NameDrift([string]$recorded, [string]$current) {
    if ("$recorded" -match '^\(if\d+\)$' -or "$current" -match '^\(if\d+\)$') { return $false }
    return ("$recorded" -ne "$current")
  }
  $rows = @{}
  foreach ($e in $items) { $r0 = Get-IfRow ([int]$e.ifIndex); if ($r0) { $rows[[int]$e.ifIndex] = $r0 } }
  $rK = Get-IfRow ([int]$bak.keep.ifIndex); if ($rK) { $rows[[int]$bak.keep.ifIndex] = $rK }
  $drift = @(Get-PrecheckDrift -Backup $bak -Rows $rows -NameDrift ${function:Test-NameDrift})
  Write-Head '[precheck] every field this restore will write'
  if ($drift.Count -eq 0) {
    Write-Ok '    all fields are still within the states that apply could have produced - safe to restore'
    Write-Host ("    changed: {0} adapter(s) metric in {{orig,target}} + AutomaticMetric in {{orig,Disabled}}" -f $items.Count) -ForegroundColor Gray
    Write-Host ("    keep   : if={0} metric in {{orig,target}} + AutomaticMetric in {{Disabled,orig}}" -f $bak.keep.ifIndex) -ForegroundColor Gray
  } else {
    Write-Bad ("    {0} field(s) drifted since this backup was written:" -f $drift.Count)
    $drift | ForEach-Object { Write-Bad ("      if={0,-3} {1,-30} {2,-16} allowed={3,-14} now={4,-10} ({5})" -f $_.ifIndex, $_.Name, $_.Field, $_.Expect, $_.Now, $_.Why) }
    Write-Bad '    Refusing: restoring would write stale values over a configuration this'
    Write-Bad '    backup does not describe. Nothing has been changed.'
    Write-Bad '    Find what changed the adapters (another tool? a VPN reconnect?) and'
    Write-Bad '    rebuild the original values from E0/Windows evidence instead of guessing.'
    exit 2
  }

  if ($DryRun) {
    Write-Host ''
    Write-Warn2 '[DryRun] plan only:'
    foreach ($e in $items) {
      Write-Warn2 ("    if={0,-3} {1,-36} metric -> {2,-6} auto -> {3}" -f $e.ifIndex, $e.Name, $e.OriginalMetric, $e.OriginalAuto)
    }
    Write-Warn2 ("    if={0,-3} {1,-36} metric -> {2,-6} auto -> {3}" -f $bak.keep.ifIndex, $bak.keep.Name, $bak.keep.OriginalMetric, $bak.keep.OriginalAuto)
    exit 0
  }

  if (-not (Test-Admin)) {
    Write-Host ''
    Write-Bad '!! restore needs administrator rights.'
    Write-Bad '   Right-click the .cmd file and choose "Run as administrator".'
    exit 1
  }

  Write-Host ''
  foreach ($e in $items) {
    Write-Host ("[2] if={0} ({1}) metric -> {2}, automatic -> {3}" -f $e.ifIndex, $e.Name, $e.OriginalMetric, $e.OriginalAuto)
    try { Set-Metric -idx ([int]$e.ifIndex) -metric ([int]$e.OriginalMetric) -auto "$($e.OriginalAuto)" }
    catch { Write-Bad ("    !! failed: {0}" -f $_.Exception.Message); $script:Failures += "restore if=$($e.ifIndex): $($_.Exception.Message)" }
  }
  Write-Host ("[3] if={0} ({1}) metric -> {2}, automatic -> {3}" -f `
    $bak.keep.ifIndex, $bak.keep.Name, $bak.keep.OriginalMetric, $bak.keep.OriginalAuto)
  try { Set-Metric -idx ([int]$bak.keep.ifIndex) -metric ([int]$bak.keep.OriginalMetric) -auto "$($bak.keep.OriginalAuto)" }
  catch { Write-Bad ("    !! failed: {0}" -f $_.Exception.Message); $script:Failures += "restore keep if=$($bak.keep.ifIndex): $($_.Exception.Message)" }

  Start-Sleep -Milliseconds 900
  Write-Head '[verify] readback'
  # When the original automatic state was Enabled the metric is recomputed by
  # Windows from link speed after Set-NetIPInterface -AutomaticMetric Enabled, so
  # the number is not the value that was written. Verify the automatic flag
  # strictly and skip the stale numeric comparison in that case.
  foreach ($e in $items) {
    $m = if ("$($e.OriginalAuto)" -eq 'Enabled') { $null } else { [int]$e.OriginalMetric }
    Test-Row -idx ([int]$e.ifIndex) -metric $m -auto "$($e.OriginalAuto)" -label 'restored' | Out-Null
  }
  $mK = if ("$($bak.keep.OriginalAuto)" -eq 'Enabled') { $null } else { [int]$bak.keep.OriginalMetric }
  Test-Row -idx ([int]$bak.keep.ifIndex) -metric $mK -auto "$($bak.keep.OriginalAuto)" -label 'keep    ' | Out-Null

  Show-Ifaces (Get-IfaceTable)
  $exitR = Show-BcastExit 'after restore'
  $exitBefore = $null
  if ($bak.broadcastExitBefore) { $exitBefore = $bak.broadcastExitBefore.ifIndex }
  if ($exitBefore -and $exitR -and $exitR.ifIndex -ne $exitBefore) {
    Write-Warn2 ("[info] predicted broadcast exit is if={0}, pre-apply it was if={1}" -f $exitR.ifIndex, $exitBefore)
  }

  Write-Host ''
  if ($script:Failures.Count -gt 0) {
    Write-Bad ("[FAIL] {0} restore verification failure(s):" -f $script:Failures.Count)
    $script:Failures | ForEach-Object { Write-Bad ("       - {0}" -f $_) }
    Write-Bad '       The machine is NOT back to its original state. Do not report success.'
    exit 3
  }
  Write-Ok '[PASS] every item verified by readback - original metric/automatic state restored.'
  # Retire the backup: once its values are verified back on the adapters it must
  # stop counting as "one outstanding apply", otherwise a second household apply
  # would be refused forever. The file is renamed, not deleted, so the record of
  # what was changed survives.
  try {
    $retired = [IO.Path]::ChangeExtension($BackupFile, '.restored.json')
    Move-Item -Path $BackupFile -Destination $retired -ErrorAction Stop
    if (Test-Path "$BackupFile.sha256") { Move-Item -Path "$BackupFile.sha256" -Destination "$retired.sha256" -ErrorAction SilentlyContinue }
    Write-Host ("    backup retired -> {0}" -f $retired) -ForegroundColor Gray
  } catch {
    Write-Warn2 ("    could not retire the backup ({0}); rename it by hand if the next apply is refused" -f $_.Exception.Message)
  }
  exit 0
}
