function Get-NamedControls {
    param($root)
    $named = @{}
    if ($root -is [System.Windows.FrameworkElement] -and $root.Name) {
        $named[$root.Name] = $root
    }
    if ($root -is [System.Windows.DependencyObject]) {
        foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($root)) {
            if ($child -is [System.Windows.DependencyObject]) {
                $named += Get-NamedControls $child
            }
        }
    }
    return $named
}

function Show-Loading {
    param($Controls)
    $Controls.loadingOverlay.Visibility = 'Visible'
    $Controls.txtStatusBar.Text = "Loading data from AWS..."
}

function Hide-Loading {
    param($Controls)
    $Controls.loadingOverlay.Visibility = 'Collapsed'
    $Controls.txtStatusBar.Text = "Ready"
}

function Update-ServerPaging {
    param(
        $script_ServerRowsPerPage,
        $script_ServerCurrentPage,
        $script_ServerFiltered,
        $script_ServerTotalPages,
        $script_PagedServers,
        $Controls
    )
    $rowsPerPage = $script_ServerRowsPerPage
    $totalRows = $script_ServerFiltered.Count
    $script_ServerTotalPages = [math]::Max([math]::Ceiling($totalRows / $rowsPerPage), 1)
    $script_ServerCurrentPage = [math]::Min([math]::Max($script_ServerCurrentPage, 1), $script_ServerTotalPages)
    $start = [Math]::Max(0, ($script_ServerCurrentPage - 1) * $rowsPerPage)
    $arr = @($script_ServerFiltered)
    $end = [math]::Min($start + $rowsPerPage - 1, $arr.Count - 1)
    $paged = ($start -le $end) ? $arr[$start..$end] : @()
    $script_PagedServers.Clear()
    foreach ($item in $paged) { $script_PagedServers.Add($item) }
    $Controls.txtPageInfo.Text = "$($script_ServerCurrentPage) / $($script_ServerTotalPages)"
}

function Reset-ServerFilterButtons {
    param($Controls)
    $Controls.btnFilterAll.Background = "#E0E7EF"
    $Controls.btnFilterOnline.Background = "#E0E7EF"
    $Controls.btnFilterOffline.Background = "#E0E7EF"
    $Controls.btnFilterImpaired.Background = "#E0E7EF"
    $Controls.btnFilterAll.Foreground = "#23272F"
    $Controls.btnFilterOnline.Foreground = "#23272F"
    $Controls.btnFilterOffline.Foreground = "#23272F"
    $Controls.btnFilterImpaired.Foreground = "#23272F"
}

function Set-ActiveFilterButton {
    param($filter, $Controls)
    Reset-ServerFilterButtons $Controls
    switch ($filter) {
        "All"      { $Controls.btnFilterAll.Background = "#4F46E5"; $Controls.btnFilterAll.Foreground = "White" }
        "Online"   { $Controls.btnFilterOnline.Background = "#22C55E"; $Controls.btnFilterOnline.Foreground = "White" }
        "Offline"  { $Controls.btnFilterOffline.Background = "#64748B"; $Controls.btnFilterOffline.Foreground = "White" }
        "Impaired" { $Controls.btnFilterImpaired.Background = "#EF4444"; $Controls.btnFilterImpaired.Foreground = "White" }
    }
}

function Update-ServerGridFilter {
    param(
        $AllServers,
        $Controls,
        [ref]$script_ServerFilter,
        [ref]$script_ServerFiltered,
        [ref]$script_ServerCurrentPage
    )
    $search = $Controls.txtServerSearch.Text.Trim().ToLower()
    $filter = $script_ServerFilter.Value
    $filtered = @()
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
        if ($searchMatch -and $statusMatch) { $filtered += $server }
    }
    $script_ServerFiltered.Value = @($filtered)
    $script_ServerCurrentPage.Value = 1
}

function Show-Panel {
    param($panelName, $Panels)
    foreach ($panel in $Panels) {
        if ($panel.Name -eq $panelName) {
            $panel.Visibility = 'Visible'
        } else {
            $panel.Visibility = 'Collapsed'
        }
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
    param($AllServers, $Controls)
    $runningCount  = ($AllServers | Where-Object { $_.EC2Status -eq "Running" }).Count
    $stoppedCount  = ($AllServers | Where-Object { $_.EC2Status -eq "Stopped" }).Count
    $impairedCount = ($AllServers | Where-Object { $_.EC2Status -eq "Impaired" }).Count
    $Controls.txtSummaryRunning.Text  = $runningCount
    $Controls.txtSummaryStopped.Text  = $stoppedCount
    $Controls.txtSummaryImpaired.Text = $impairedCount

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
    $Controls.dgTopDisk.ItemsSource = $TopDisk

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
    $Controls.dgTopCPU.ItemsSource = $TopCPU

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
    $Controls.dgTopMemory.ItemsSource = $TopMemory
}

function Get-ServerDataAsync {
    param(
        [ref]$AllServers,
        $Controls
    )
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
        $Ec2InstanceQuery = @{
            Name = "OperatingSystem"
            Values = "Windows"
        }
        try {
            $ec2Instances = Get-EC2Instance -Region us-gov-west-1 -Filter $Ec2InstanceQuery -ErrorAction Stop | Select-Object -ExpandProperty Instances
            foreach ($instance in $ec2Instances) {
                $state = $instance.State.Name
                $hostname = $instance.PrivateDnsName
                $ip = $instance.PrivateIpAddress
                $id = $instance.InstanceId
                $os = $instance.PlatformDetails
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

    # Wait for the background job to finish (with timeout)
    $timeout = 30 # seconds
    $elapsed = 0
    while ($shared.Status -eq 'Running' -and $elapsed -lt $timeout) {
        Start-Sleep -Milliseconds 200
        $elapsed += 0.2
    }

    if ($shared.Status -eq 'Completed') {
        $AllServers.Value = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
        foreach ($item in $shared.Data) {
            $AllServers.Value.Add($item)
        }
        # The caller should call Update-ServerPaging and Update-DashboardAndTop10
        $Controls.txtStatusBar.Text = "Data loaded successfully."
    } elseif ($shared.Status -eq 'Error') {
        $Controls.txtStatusBar.Text = "Error loading data: $($shared.Error)"
    } else {
        $Controls.txtStatusBar.Text = "Data load timed out."
    }
    Hide-Loading $Controls

    # Clean up runspace and PowerShell instance
    [void]$ps.EndInvoke($asyncResult)
    [void]$runspace.Close()
    [void]$runspace.Dispose()
    [void]$ps.Dispose()
}

Export-ModuleMember -Function *-*