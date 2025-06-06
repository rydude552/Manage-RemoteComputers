<#
.SYNOPSIS
    Entry point for Manage-RemoteComputers modular GUI tool.
#>

# --- Import required modules ---
foreach ($module in (Get-ChildItem -Path "$PSScriptRoot\Modules" -Filter '*.psm1')) {
    Import-Module -Name $module.FullName -Force
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# --- Load XAML from file ---
$XamlPath = Join-Path $PSScriptRoot 'MainWindow.xaml'
$XamlContent = Get-Content $XamlPath -Raw
$Window = Import-Xaml -XamlString $XamlContent

# --- Controls as plain hashtable ---
$Controls = @{}
$Controls.UI = Get-NamedControls $Window

# --- Async Data Load and Data Structures ---
$Controls.Variables = @{
    AllServers        = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
    ServerFilter      = "All"
    ServerRowsPerPage = 25
    ServerCurrentPage = 1
    ServerFiltered    = [System.Collections.Generic.List[object]]::new()
    ServerTotalPages  = 1
    PagedServers      = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
}
$Controls.UI.dgServers.ItemsSource = $Controls.Variables.PagedServers

# --- UI Event Handlers ---
$Panels = @(
    $Controls.UI.panelDashboard,
    $Controls.UI.panelServers,
    $Controls.UI.panelSoftware,
    $Controls.UI.panelSecurity,
    $Controls.UI.panelScripts,
    $Controls.UI.panelScheduling,
    $Controls.UI.panelAlerts
)

$navBtns = @(
    $Controls.UI.btnNavDashboard,
    $Controls.UI.btnNavServers,
    $Controls.UI.btnNavSoftware,
    $Controls.UI.btnNavSecurity,
    $Controls.UI.btnNavScripts,
    $Controls.UI.btnNavScheduling,
    $Controls.UI.btnNavAlerts
)

foreach ($btn in $navBtns) {
    if ($btn.Name -match '^btnNav(\w+)$') {
        $panelName = "panel$($Matches[1])"
    } else {
        continue
    }
    $btn.Add_Click({
        try {
            foreach ($panel in $Panels) {
                $panel.Visibility = if ($panel.Name -eq $panelName) { 'Visible' } else { 'Collapsed' }
            }
        } catch {
            Write-Host "[NavBtn Click] error: $_"
        }
    }.GetNewClosure())
}

# Pagination
$Controls.UI.btnPrevPage.Add_Click({
    try {
        if ($Controls.Variables.ServerCurrentPage -gt 1) {
            $Controls.Variables.ServerCurrentPage--
            Update-ServerPaging $Controls
        }
    } catch {
        Write-Host "[btnPrevPage Click] error: $_"
    }
})
$Controls.UI.btnNextPage.Add_Click({
    try {
        if ($Controls.Variables.ServerCurrentPage -lt $Controls.Variables.ServerTotalPages) {
            $Controls.Variables.ServerCurrentPage++
            Update-ServerPaging $Controls
        }
    } catch {
        Write-Host "[btnNextPage Click] error: $_"
    }
})
foreach ($rows in 10,25,50,100) {
    $localRows = $rows
    $Controls.UI."btnRows$localRows".Add_Click({
        try {
            $Controls.UI.txtRowsPerPage.Text = "Rows: $localRows"
            $Controls.Variables.ServerRowsPerPage = $localRows
            $Controls.Variables.ServerCurrentPage = 1
            Update-ServerPaging $Controls
            $Controls.UI.popupRowsPerPage.IsOpen = $false
        } catch {
            Write-Host "[btnRows$localRows Click] error: $_"
        }
    }.GetNewClosure())
}
$Controls.UI.btnRowsPerPageFlyout.Add_Click({
    try {
        $Controls.UI.popupRowsPerPage.IsOpen = -not $Controls.UI.popupRowsPerPage.IsOpen
    } catch {
        Write-Host "[btnRowsPerPageFlyout Click] error: $_"
    }
})

# Server Filter Flyout
$Controls.UI.btnFilterAll.Add_Click({
    try {
        $Controls.Variables.ServerFilter = "All"
        $Controls.UI.txtServersFilter.Text = "All"
        Set-ActiveFilterButton "All" $Controls
        Update-ServerGridFilter $Controls
        Update-ServerPaging $Controls
        $Controls.UI.popupFilters.IsOpen = $false
    } catch {
        Write-Host "[btnFilterAll Click] error: $_"
    }
})
$Controls.UI.btnFilterOnline.Add_Click({
    try {
        $Controls.Variables.ServerFilter = "Online"
        $Controls.UI.txtServersFilter.Text = "Online"
        Set-ActiveFilterButton "Online" $Controls
        Update-ServerGridFilter $Controls
        Update-ServerPaging $Controls
        $Controls.UI.popupFilters.IsOpen = $false
    } catch {
        Write-Host "[btnFilterOnline Click] error: $_"
    }
})
$Controls.UI.btnFilterOffline.Add_Click({
    try {
        $Controls.Variables.ServerFilter = "Offline"
        $Controls.UI.txtServersFilter.Text = "Offline"
        Set-ActiveFilterButton "Offline" $Controls
        Update-ServerGridFilter $Controls
        Update-ServerPaging $Controls
        $Controls.UI.popupFilters.IsOpen = $false
    } catch {
        Write-Host "[btnFilterOffline Click] error: $_"
    }
})
$Controls.UI.btnFilterImpaired.Add_Click({
    try {
        $Controls.Variables.ServerFilter = "Impaired"
        $Controls.UI.txtServersFilter.Text = "Impaired"
        Set-ActiveFilterButton "Impaired" $Controls
        Update-ServerGridFilter $Controls
        Update-ServerPaging $Controls
        $Controls.UI.popupFilters.IsOpen = $false
    } catch {
        Write-Host "[btnFilterImpaired Click] error: $_"
    }
})
$Controls.UI.txtServerSearch.Add_TextChanged({
    try {
        Update-ServerGridFilter $Controls
        Update-ServerPaging $Controls
    } catch {
        Write-Host "[txtServerSearch TextChanged] error: $_"
    }
})
$Controls.UI.btnFilterFlyout.Add_Click({
    try {
        $Controls.UI.popupFilters.IsOpen = -not $Controls.UI.popupFilters.IsOpen
    } catch {
        Write-Host "[btnFilterFlyout Click] error: $_"
    }
})

# Actions Flyout
$Controls.UI.btnActionsFlyout.Add_Click({
    try {
        $Controls.UI.popupActions.IsOpen = -not $Controls.UI.popupActions.IsOpen
    } catch {
        Write-Host "[btnActionsFlyout Click] error: $_"
    }
})
$Controls.UI.btnActionReboot.Add_Click({
    try {
        $Controls.UI.popupActions.IsOpen = $false
        $Controls.UI.txtStatusBar.Text = "Reboot action triggered for selected servers."
    } catch {
        Write-Host "[btnActionReboot Click] error: $_"
    }
})
$Controls.UI.btnActionDeploy.Add_Click({
    try {
        $Controls.UI.popupActions.IsOpen = $false
        $Controls.UI.txtStatusBar.Text = "Deploy Software action triggered for selected servers."
    } catch {
        Write-Host "[btnActionDeploy Click] error: $_"
    }
})
$Controls.UI.btnActionScript.Add_Click({
    try {
        $Controls.UI.popupActions.IsOpen = $false
        $Controls.UI.txtStatusBar.Text = "Execute Script action triggered for selected servers."
    } catch {
        Write-Host "[btnActionScript Click] error: $_"
    }
})

# Software Status Filter Flyout
$Controls.UI.btnSoftwareStatusFilterFlyout.Add_Click({
    try {
        $Controls.UI.popupSoftwareStatusFilter.IsOpen = -not $Controls.UI.popupSoftwareStatusFilter.IsOpen
    } catch {
        Write-Host "[btnSoftwareStatusFilterFlyout Click] error: $_"
    }
})
$Controls.UI.btnSoftwareStatusAll.Add_Click({
    try {
        $Controls.UI.txtSoftwareStatusFilter.Text = "All"
        $Controls.UI.popupSoftwareStatusFilter.IsOpen = $false
        # Add your filtering logic here
    } catch {
        Write-Host "[btnSoftwareStatusAll Click] error: $_"
    }
})
$Controls.UI.btnSoftwareStatusUpToDate.Add_Click({
    try {
        $Controls.UI.txtSoftwareStatusFilter.Text = "Up to date"
        $Controls.UI.popupSoftwareStatusFilter.IsOpen = $false
        # Add your filtering logic here
    } catch {
        Write-Host "[btnSoftwareStatusUpToDate Click] error: $_"
    }
})
$Controls.UI.btnSoftwareStatusUpdateAvailable.Add_Click({
    try {
        $Controls.UI.txtSoftwareStatusFilter.Text = "Update available"
        $Controls.UI.popupSoftwareStatusFilter.IsOpen = $false
        # Add your filtering logic here
    } catch {
        Write-Host "[btnSoftwareStatusUpdateAvailable Click] error: $_"
    }
})

# Dashboard Summary Card Handlers
$Controls.UI.btnSummaryRunning.Add_Click({
    try {
        foreach ($panel in $Panels) {
            $panel.Visibility = if ($panel.Name -eq 'panelServers') { 'Visible' } else { 'Collapsed' }
        }
        $Controls.Variables.ServerFilter = "Online"
        Set-ActiveFilterButton "Online" $Controls
        Update-ServerGridFilter $Controls
        Update-ServerPaging $Controls
        $Controls.UI.txtStatusBar.Text = "Showing running EC2 instances."
    } catch {
        Write-Host "[btnSummaryRunning Click] error: $_"
    }
})
$Controls.UI.btnSummaryStopped.Add_Click({
    try {
        foreach ($panel in $Panels) {
            $panel.Visibility = if ($panel.Name -eq 'panelServers') { 'Visible' } else { 'Collapsed' }
        }
        $Controls.Variables.ServerFilter = "Offline"
        Set-ActiveFilterButton "Offline" $Controls
        Update-ServerGridFilter $Controls
        Update-ServerPaging $Controls
        $Controls.UI.txtStatusBar.Text = "Showing stopped EC2 instances."
    } catch {
        Write-Host "[btnSummaryStopped Click] error: $_"
    }
})
$Controls.UI.btnSummaryImpaired.Add_Click({
    try {
        foreach ($panel in $Panels) {
            $panel.Visibility = if ($panel.Name -eq 'panelServers') { 'Visible' } else { 'Collapsed' }
        }
        $Controls.Variables.ServerFilter = "Impaired"
        Set-ActiveFilterButton "Impaired" $Controls
        Update-ServerGridFilter $Controls
        Update-ServerPaging $Controls
        $Controls.UI.txtStatusBar.Text = "Showing impaired EC2 instances."
    } catch {
        Write-Host "[btnSummaryImpaired Click] error: $_"
    }
})

# --- Initial UI State ---
try {
    Set-ActiveFilterButton "All" $Controls
    Update-ServerGridFilter $Controls
    Update-ServerPaging $Controls
} catch {
    Write-Host "[Initial UI State] error: $_"
}

# --- Start async data load after window is loaded ---
$Window.Add_ContentRendered({
    try {
        Get-ServerDataAsync $Controls
    } catch {
        Write-Host "[ContentRendered] error: $_"
    }
})

# --- Show the Window ---
try {
    $Window.ShowDialog() | Out-Null
} catch {
    Write-Host "[ShowDialog] error: $_"
}