function Import-Xaml {
    param($XamlString)
    $reader = New-Object System.Xml.XmlNodeReader([xml]$XamlString)
    return [Windows.Markup.XamlReader]::Load($reader)
}

function Get-NamedControls {
    param($XamlString)
    $controls = @{}
    function Recurse($node) {
        if ($null -eq $node) { return }
        if ($node -is [System.Windows.FrameworkElement] -and $node.Name) {
            $controls[$node.Name] = $node
        }
        if ($node -is [System.Windows.DependencyObject]) {
            foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($node)) {
                if ($child -is [System.Windows.DependencyObject]) {
                    Recurse $child
                }
            }
        }
    }
    Recurse $XamlString
    return $controls
}

function Show-Loading {
    param($Controls)
    try {
        $Controls.UI.loadingOverlay.Visibility = 'Visible'
        $Controls.UI.txtStatusBar.Text = "Loading data from AWS..."
    } catch {
        Write-Host "[Show-Loading] error: $_"
    }
}

function Hide-Loading {
    param($Controls)
    try {
        $Controls.UI.loadingOverlay.Visibility = 'Collapsed'
        $Controls.UI.txtStatusBar.Text = "Ready"
    } catch {
        Write-Host "[Hide-Loading] error: $_"
    }
}

function Update-ServerPaging {
    param($Controls)
    try {
        $vars = $Controls.Variables
        $rowsPerPage = $vars.ServerRowsPerPage
        $totalRows = $vars.ServerFiltered.Count
        $vars.ServerTotalPages = [math]::Max([math]::Ceiling($totalRows / $rowsPerPage), 1)
        $vars.ServerCurrentPage = [math]::Min([math]::Max($vars.ServerCurrentPage, 1), $vars.ServerTotalPages)
        $start = [Math]::Max(0, ($vars.ServerCurrentPage - 1) * $rowsPerPage)
        $arr = @($vars.ServerFiltered)
        $end = [math]::Min($start + $rowsPerPage - 1, $arr.Count - 1)
        $paged = if ($start -le $end) { $arr[$start..$end] } else { @() }
        $vars.PagedServers.Clear()
        foreach ($item in $paged) { $vars.PagedServers.Add($item) }
        $Controls.UI.txtPageInfo.Text = "$($vars.ServerCurrentPage) / $($vars.ServerTotalPages)"
    } catch {
        Write-Host "[Update-ServerPaging] error: $_"
    }
}

function Reset-ServerFilterButtons {
    param($Controls)
    try {
        $Controls.UI.btnFilterAll.Background = "#E0E7EF"; $Controls.UI.btnFilterAll.Foreground = "#23272F"
        $Controls.UI.btnFilterOnline.Background = "#E0E7EF"; $Controls.UI.btnFilterOnline.Foreground = "#23272F"
        $Controls.UI.btnFilterOffline.Background = "#E0E7EF"; $Controls.UI.btnFilterOffline.Foreground = "#23272F"
        $Controls.UI.btnFilterImpaired.Background = "#E0E7EF"; $Controls.UI.btnFilterImpaired.Foreground = "#23272F"
    } catch {
        Write-Host "[Reset-ServerFilterButtons] error: $_"
    }
}

function Set-ActiveFilterButton {
    param($filter, $Controls)
    try {
        Reset-ServerFilterButtons $Controls
        switch ($filter) {
            "All"      { $Controls.UI.btnFilterAll.Background = "#4F46E5"; $Controls.UI.btnFilterAll.Foreground = "White" }
            "Online"   { $Controls.UI.btnFilterOnline.Background = "#22C55E"; $Controls.UI.btnFilterOnline.Foreground = "White" }
            "Offline"  { $Controls.UI.btnFilterOffline.Background = "#64748B"; $Controls.UI.btnFilterOffline.Foreground = "White" }
            "Impaired" { $Controls.UI.btnFilterImpaired.Background = "#EF4444"; $Controls.UI.btnFilterImpaired.Foreground = "White" }
        }
    } catch {
        Write-Host "[Set-ActiveFilterButton] error: $_"
    }
}

function Update-ServerGridFilter {
    param($Controls)
    try {
        $vars = $Controls.Variables
        $AllServers = $vars.AllServers
        $search = $Controls.UI.txtServerSearch.Text.Trim().ToLower()
        $filter = $vars.ServerFilter
        $filtered = [System.Collections.Generic.List[object]]::new()
        foreach ($server in $AllServers) {
            $searchMatch = (
                $search -eq '' -or
                ($server.Hostname        -and $server.Hostname.ToLower().Contains($search))      -or
                ($server.IPAddress       -and $server.IPAddress.ToLower().Contains($search))     -or
                ($server.EC2InstanceId   -and $server.EC2InstanceId.ToLower().Contains($search)) -or
                ($server.EC2Status       -and $server.EC2Status.ToLower().Contains($search))     -or
                ($server.CPUUsage        -and $server.CPUUsage.ToLower().Contains($search))      -or
                ($server.MemoryUsage     -and $server.MemoryUsage.ToLower().Contains($search))   -or
                ($server.OS              -and $server.OS.ToLower().Contains($search))
            )
            $statusMatch = switch ($filter) {
                "Online"   { $server.EC2Status -eq "Running"; break }
                "Offline"  { $server.EC2Status -eq "Stopped"; break }
                "Impaired" { $server.EC2Status -eq "Impaired"; break }
                default    { $true }
            }
            if ($searchMatch -and $statusMatch) { $null = $filtered.Add($server) }
        }
        $Controls.Variables.ServerFiltered = @($filtered)
        $Controls.Variables.ServerCurrentPage = 1
        $Controls.UI.txtServersHeader.Text = "Servers ($($filtered.Count))"
    } catch {
        Write-Host "[Update-ServerGridFilter] error: $_"
    }
}

function Get-StatusColor {
    param($status)
    switch ($status) {
        "Healthy"   { return "#22C55E" }
        "Warning"   { return "#F59E42" }
        "Critical"  { return "#EF4444" }
        "Stopped"   { return "#64748B" }
        "Running"   { return "#22C55E" }
        "Impaired"  { return "#F59E42" }
        default     { return "#A3A3A3" }
    }
}

function Update-DashboardAndTop10 {
    param($Controls)
    try {
        $vars = $Controls.Variables
        $AllServers = $vars.AllServers
        $runningCount  = ($AllServers | Where-Object { $_.EC2Status -eq "Running" }).Count
        $stoppedCount  = ($AllServers | Where-Object { $_.EC2Status -eq "Stopped" }).Count
        $impairedCount = ($AllServers | Where-Object { $_.EC2Status -eq "Impaired" }).Count
        $Controls.UI.txtSummaryRunning.Text = $runningCount
        $Controls.UI.txtSummaryStopped.Text = $stoppedCount
        $Controls.UI.txtSummaryImpaired.Text = $impairedCount

        $TopDisk = $AllServers |
            Where-Object { $_.DiskUsage -match '^\d+(\.\d+)?%' } |
            Sort-Object { [double]($_.DiskUsage -replace '%','') } -Descending |
            Select-Object -First 10 |
            ForEach-Object {
                $usage = [double]($_.DiskUsage -replace '%','')
                [pscustomobject]@{
                    Hostname    = $_.Hostname
                    Usage       = $_.DiskUsage
                    Status      = if ($usage -ge 90) { "Warning" } else { "Healthy" }
                    StatusColor = (Get-StatusColor -status $(if ($usage -ge 90) { "Warning" } else { "Healthy" }))
                }
            }
        $Controls.UI.dgTopDisk.ItemsSource = $TopDisk

        $TopCPU = $AllServers |
            Where-Object { $_.CPUUsage -match '^\d+(\.\d+)?%' } |
            Sort-Object { [double]($_.CPUUsage -replace '%','') } -Descending |
            Select-Object -First 10 |
            ForEach-Object {
                [pscustomobject]@{
                    Hostname    = $_.Hostname
                    Usage       = $_.CPUUsage
                    Status      = if ([double]($_.CPUUsage -replace '%','') -ge 95) { "Critical" }
                                  elseif ([double]($_.CPUUsage -replace '%','') -ge 85) { "Warning" }
                                  else { "Healthy" }
                    StatusColor = (Get-StatusColor -status $(if ([double]($_.CPUUsage -replace '%','') -ge 95) { "Critical" }
                                                            elseif ([double]($_.CPUUsage -replace '%','') -ge 85) { "Warning" }
                                                            else { "Healthy" }))
                }
            }
        $Controls.UI.dgTopCPU.ItemsSource = $TopCPU

        $TopMemory = $AllServers |
            Where-Object { $_.MemoryUsage -match '^\d+(\.\d+)?%' } |
            Sort-Object { [double]($_.MemoryUsage -replace '%','') } -Descending |
            Select-Object -First 10 |
            ForEach-Object {
                [pscustomobject]@{
                    Hostname    = $_.Hostname
                    Usage       = $_.MemoryUsage
                    Status      = if ([double]($_.MemoryUsage -replace '%','') -ge 90) { "Warning" }
                                  elseif ([double]($_.MemoryUsage -replace '%','') -ge 80) { "Healthy" }
                                  else { "Healthy" }
                    StatusColor = (Get-StatusColor -status $(if ([double]($_.MemoryUsage -replace '%','') -ge 90) { "Warning" }
                                                            else { "Healthy" }))
                }
            }
        $Controls.UI.dgTopMemory.ItemsSource = $TopMemory
    } catch {
        Write-Host "[Update-DashboardAndTop10] error: $_"
    }
}

function Get-ServerDataAsync {
    param($Controls, $timeout = 30)

    Show-Loading $Controls

    $shared = [hashtable]::Synchronized(@{
        Status = 'Running'
        Data   = $null
        Error  = $null
    })

    $runspace = [runspacefactory]::CreateRunspace()
    $runspace.ApartmentState = "STA"
    $runspace.ThreadOptions = "ReuseThread"
    [void]$runspace.Open()

    $ps = [PowerShell]::Create()
    $ps.Runspace = $runspace

    [void]$ps.AddScript({
        param($shared)

        $result = @()
        $AWSRegion = 'us-gov-west-1'

        try {
            # Get all managed instances from Systems Manager (SSM)
            $ssmInstances = Get-SSMInstanceInformation -Region $AWSRegion -ErrorAction Stop

            foreach ($instance in $ssmInstances) {
                $id = $instance.InstanceId
                $hostname = $instance.ComputerName
                $ip = $instance.IPAddress
                $os = $instance.PlatformName
                $state = if ($instance.PingStatus -eq 'Online') { 'Running' } else { 'Stopped' }
                $cpu = "N/A"
                $mem = "N/A"
                $disk = "N/A"
                try {
                    $cwMetrics = Get-CWMetricStatistics -Region $AWSRegion `
                        -Namespace "AWS/EC2" `
                        -MetricName "CPUUtilization" `
                        -Dimensions @{ Name="InstanceId"; Value=$id } `
                        -StartTime (Get-Date).AddMinutes(-10) `
                        -EndTime (Get-Date) `
                        -Period 300 `
                        -Statistics "Average" |
                        Sort-Object -Property Timestamp -Descending
                    if ($cwMetrics -and $cwMetrics[0].Average) {
                        $cpu = "{0:N1}%" -f $cwMetrics[0].Average
                    }
                } catch { $cpu = "N/A" }
                try {
                    $totalMemMetrics = Get-CWMetricStatistics -Region $AWSRegion `
                        -Namespace "CWAgent" `
                        -MetricName "Memory Total MBytes" `
                        -Dimensions @{ Name="InstanceId"; Value=$id } `
                        -StartTime (Get-Date).AddMinutes(-10) `
                        -EndTime (Get-Date) `
                        -Period 300 `
                        -Statistics "Average" |
                        Sort-Object -Property Timestamp -Descending
                    $availMemMetrics = Get-CWMetricStatistics -Region $AWSRegion `
                        -Namespace "CWAgent" `
                        -MetricName "Memory Available MBytes" `
                        -Dimensions @{ Name="InstanceId"; Value=$id } `
                        -StartTime (Get-Date).AddMinutes(-10) `
                        -EndTime (Get-Date) `
                        -Period 300 `
                        -Statistics "Average" |
                        Sort-Object -Property Timestamp -Descending
                    if ($totalMemMetrics -and $availMemMetrics -and $totalMemMetrics[0].Average -and $availMemMetrics[0].Average) {
                        $total = [double]$totalMemMetrics[0].Average
                        $avail = [double]$availMemMetrics[0].Average
                        if ($total -gt 0) {
                            $memUsage = (1 - ($avail / $total)) * 100
                            $mem = "{0:N1}%" -f $memUsage
                        }
                    }
                } catch { $mem = "N/A" }
                try {
                    $diskMetrics = Get-CWMetricStatistics -Region $AWSRegion `
                        -Namespace "CWAgent" `
                        -MetricName "LogicalDisk % Free Space" `
                        -Dimensions @(
                            @{ Name="InstanceId"; Value=$id }
                            @{ Name="LogicalDisk"; Value="C:" }
                        ) `
                        -StartTime (Get-Date).AddMinutes(-10) `
                        -EndTime (Get-Date) `
                        -Period 300 `
                        -Statistics "Average" |
                        Sort-Object -Property Timestamp -Descending
                    if ($diskMetrics -and $null -ne $diskMetrics[0].Average) {
                        $free = [double]$diskMetrics[0].Average
                        $used = 100 - $free
                        $disk = "{0:N1}%" -f $used
                    }
                } catch { $disk = "N/A" }
                $result += [pscustomobject]@{
                    Hostname      = $hostname
                    IPAddress     = $ip
                    EC2InstanceId = $id
                    EC2Status     = $state
                    CPUUsage      = $cpu
                    MemoryUsage   = $mem
                    DiskUsage     = $disk
                    OS            = $os
                }
            }

            $shared.Data = $result
            $shared.Status = 'Completed'
            $shared.Error = $null
        } catch {
            $shared.Status = 'Error'
            $shared.Error = $_.Exception.Message
            $shared.Data = $null
        }
    }).AddArgument($shared)

    $asyncResult = $ps.BeginInvoke()

    # Use a timer to monitor the runspace and clean up when done
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(200)
    $elapsed = 0

    $timer.Add_Tick({
        $elapsed += 0.2
        if ($shared.Status -ne 'Running' -or $elapsed -ge $timeout) {
            $timer.Stop()
            try {
                [void]$ps.EndInvoke($asyncResult)
            } catch {
                Write-Host "EndInvoke error: $_"
            }
            try {
                [void]$runspace.Close()
                [void]$runspace.Dispose()
            } catch {
                Write-Host "Runspace cleanup error: $_"
            }
            try {
                [void]$ps.Dispose()
            } catch {
                Write-Host "PS cleanup error: $_"
            }

            try {
                Hide-Loading $Controls
            } catch {
                Write-Host "Hide-Loading error: $_"
            }
            try {
                $Controls.Variables.AllServers.Clear()
            } catch {
                Write-Host "AllServers.Clear error: $_"
            }
            if ($shared.Status -eq 'Completed' -and $shared.Data) {
                foreach ($item in $shared.Data) {
                    try {
                        $Controls.Variables.AllServers.Add($item)
                    } catch {
                        Write-Host "AllServers.Add error: $_"
                    }
                }
                $Controls.UI.txtStatusBar.Text = "Server data loaded successfully."
            } elseif ($shared.Status -eq 'Error') {
                $Controls.UI.txtStatusBar.Text = "Error: $($shared.Error)"
            } else {
                $Controls.UI.txtStatusBar.Text = "Failed to load server data."
            }
            try {
                Update-ServerGridFilter $Controls
            } catch {
                Write-Host "Update-ServerGridFilter error: $_"
            }
            try {
                Update-ServerPaging $Controls
            } catch {
                Write-Host "Update-ServerPaging error: $_"
            }
            try {
                Update-DashboardAndTop10 $Controls
            } catch {
                Write-Host "Update-DashboardAndTop10 error: $_"
            }
        }
    }.GetNewClosure())
    $timer.Start()
}

Export-ModuleMember -Function Import-Xaml, Get-NamedControls, Show-Loading, Hide-Loading, Update-ServerPaging, Reset-ServerFilterButtons, Set-ActiveFilterButton, Update-ServerGridFilter, Get-StatusColor, Update-DashboardAndTop10, Get-ServerDataAsync