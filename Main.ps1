<#
.SYNOPSIS
    Entry point for Manage-RemoteComputers modular GUI tool.
#>

# --- Import required modules ---
$ModulesRootPath = Join-Path $PSScriptRoot 'Modules'
foreach ($module in (Get-ChildItem -Path $ModulesRootPath -Filter '*.psm1')) {
    Import-Module -Name (Join-Path $ModulesRootPath $module.Name) -Force
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# --- Preferences ---
$script:Preferences = @{
    WindowTitle = 'Remote Computer Manager'
    FontFamily  = 'Segoe UI'
    FontSize    = 12
}

# --- Load XAML from file ---
$XamlPath = Join-Path $PSScriptRoot 'MainWindow.xaml'
$XamlContent = Get-Content $XamlPath -Raw
$Window = Import-Xaml -XamlString $XamlContent

$Controls = Get-NamedControls $Window

# --- Async Data Load and Data Structures ---
$AllServers = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
$script:ServerFilter = "All"
$script:ServerRowsPerPage = 25
$script:ServerCurrentPage = 1
$script:ServerFiltered = @()
$script:ServerTotalPages = 1
$script:PagedServers = [System.Collections.ObjectModel.ObservableCollection[psobject]]::new()
$Controls.dgServers.ItemsSource = $script:PagedServers

# --- UI Event Handlers ---
# Auto-discover panels and navigation buttons, and wire up navigation
$Panels = $Controls.GetEnumerator() | Where-Object { $_.Key -like 'panel*' } | ForEach-Object { $_.Value }

function Show-Panel-Wrapper {
    param($panelName)
    Show-Panel $panelName $Panels
}

foreach ($key in $Controls.Keys) {
    if ($key -like 'btnNav*' -and $key -match '^btnNav(.+)$') {
        $panelName = "panel$($Matches[1])"
        $btn = $Controls[$key]
        $btn.Add_Click({
            param($sender, $eventArgs)
            Show-Panel-Wrapper $panelName
        }.GetNewClosure())
    }
}

# Add click handlers for pagination
$Controls.btnPrevPage.Add_Click({ if ($script:ServerCurrentPage -gt 1) { $script:ServerCurrentPage--; Update-ServerPaging $script:ServerRowsPerPage $script:ServerCurrentPage $script:ServerFiltered $script:ServerTotalPages $script:PagedServers $Controls } })
$Controls.btnNextPage.Add_Click({ if ($script:ServerCurrentPage -lt $script:ServerTotalPages) { $script:ServerCurrentPage++; Update-ServerPaging $script:ServerRowsPerPage $script:ServerCurrentPage $script:ServerFiltered $script:ServerTotalPages $script:PagedServers $Controls } })
foreach ($rows in 10,25,50,100) {
    $Controls."btnRows$rows".Add_Click({ Set-RowsPerPage $rows; $Controls.popupRowsPerPage.IsOpen = $false })
}
$Controls.btnRowsPerPageFlyout.Add_Click({ $Controls.popupRowsPerPage.IsOpen = -not $Controls.popupRowsPerPage.IsOpen })

function Set-RowsPerPage ($rows) {
    $script:ServerRowsPerPage = $rows
    $Controls.btnRowsPerPageFlyout.Content = "Rows: $rows ⏷"
    $script:ServerCurrentPage = 1
    Update-ServerPaging $script:ServerRowsPerPage $script:ServerCurrentPage $script:ServerFiltered $script:ServerTotalPages $script:PagedServers $Controls
}

$Controls.btnFilterAll.Add_Click({
    $script:ServerFilter = "All"
    Set-ActiveFilterButton "All" $Controls
    Update-ServerGridFilter $AllServers $Controls ([ref]$script:ServerFilter) ([ref]$script:ServerFiltered) ([ref]$script:ServerCurrentPage)
    Update-ServerPaging $script:ServerRowsPerPage $script:ServerCurrentPage $script:ServerFiltered $script:ServerTotalPages $script:PagedServers $Controls
    $Controls.popupFilters.IsOpen = $false
})
$Controls.btnFilterOnline.Add_Click({
    $script:ServerFilter = "Online"
    Set-ActiveFilterButton "Online" $Controls
    Update-ServerGridFilter $AllServers $Controls ([ref]$script:ServerFilter) ([ref]$script:ServerFiltered) ([ref]$script:ServerCurrentPage)
    Update-ServerPaging $script:ServerRowsPerPage $script:ServerCurrentPage $script:ServerFiltered $script:ServerTotalPages $script:PagedServers $Controls
    $Controls.popupFilters.IsOpen = $false
})
$Controls.btnFilterOffline.Add_Click({
    $script:ServerFilter = "Offline"
    Set-ActiveFilterButton "Offline" $Controls
    Update-ServerGridFilter $AllServers $Controls ([ref]$script:ServerFilter) ([ref]$script:ServerFiltered) ([ref]$script:ServerCurrentPage)
    Update-ServerPaging $script:ServerRowsPerPage $script:ServerCurrentPage $script:ServerFiltered $script:ServerTotalPages $script:PagedServers $Controls
    $Controls.popupFilters.IsOpen = $false
})
$Controls.btnFilterImpaired.Add_Click({
    $script:ServerFilter = "Impaired"
    Set-ActiveFilterButton "Impaired" $Controls
    Update-ServerGridFilter $AllServers $Controls ([ref]$script:ServerFilter) ([ref]$script:ServerFiltered) ([ref]$script:ServerCurrentPage)
    Update-ServerPaging $script:ServerRowsPerPage $script:ServerCurrentPage $script:ServerFiltered $script:ServerTotalPages $script:PagedServers $Controls
    $Controls.popupFilters.IsOpen = $false
})
$Controls.txtServerSearch.Add_TextChanged({
    Update-ServerGridFilter $AllServers $Controls ([ref]$script:ServerFilter) ([ref]$script:ServerFiltered) ([ref]$script:ServerCurrentPage)
    Update-ServerPaging $script:ServerRowsPerPage $script:ServerCurrentPage $script:ServerFiltered $script:ServerTotalPages $script:PagedServers $Controls
})
$Controls.btnFilterFlyout.Add_Click({ $Controls.popupFilters.IsOpen = -not $Controls.popupFilters.IsOpen })
$Controls.btnActionsFlyout.Add_Click({ $Controls.popupActions.IsOpen = -not $Controls.popupActions.IsOpen })
$Controls.btnActionReboot.Add_Click({
    $Controls.popupActions.IsOpen = $false
    $Controls.txtStatusBar.Text = "Reboot action triggered for selected servers."
})
$Controls.btnActionDeploy.Add_Click({
    $Controls.popupActions.IsOpen = $false
    $Controls.txtStatusBar.Text = "Deploy Software action triggered for selected servers."
})
$Controls.btnActionScript.Add_Click({
    $Controls.popupActions.IsOpen = $false
    $Controls.txtStatusBar.Text = "Execute Script action triggered for selected servers."
})

# --- Dashboard Summary Card Handlers ---
$Controls.btnSummaryRunning.Add_Click({
    Show-Panel-Wrapper 'panelServers'
    $script:ServerFilter = "Online"
    Set-ActiveFilterButton "Online" $Controls
    Update-ServerGridFilter $AllServers $Controls ([ref]$script:ServerFilter) ([ref]$script:ServerFiltered) ([ref]$script:ServerCurrentPage)
    Update-ServerPaging $script:ServerRowsPerPage $script:ServerCurrentPage $script:ServerFiltered $script:ServerTotalPages $script:PagedServers $Controls
    $Controls.txtStatusBar.Text = "Showing running EC2 instances."
})
$Controls.btnSummaryStopped.Add_Click({
    Show-Panel-Wrapper 'panelServers'
    $script:ServerFilter = "Offline"
    Set-ActiveFilterButton "Offline" $Controls
    Update-ServerGridFilter $AllServers $Controls ([ref]$script:ServerFilter) ([ref]$script:ServerFiltered) ([ref]$script:ServerCurrentPage)
    Update-ServerPaging $script:ServerRowsPerPage $script:ServerCurrentPage $script:ServerFiltered $script:ServerTotalPages $script:PagedServers $Controls
    $Controls.txtStatusBar.Text = "Showing stopped EC2 instances."
})
$Controls.btnSummaryImpaired.Add_Click({
    Show-Panel-Wrapper 'panelServers'
    $script:ServerFilter = "Impaired"
    Set-ActiveFilterButton "Impaired" $Controls
    Update-ServerGridFilter $AllServers $Controls ([ref]$script:ServerFilter) ([ref]$script:ServerFiltered) ([ref]$script:ServerCurrentPage)
    Update-ServerPaging $script:ServerRowsPerPage $script:ServerCurrentPage $script:ServerFiltered $script:ServerTotalPages $script:PagedServers $Controls
    $Controls.txtStatusBar.Text = "Showing impaired EC2 instances."
})

# --- Dashboard and Top 10 Tables ---
function Update-DashboardAndTop10-Wrapper {
    Update-DashboardAndTop10 $AllServers $Controls
}

# --- Initial UI State ---
Show-Loading $Controls
Set-ActiveFilterButton "All" $Controls
Update-ServerGridFilter $AllServers $Controls ([ref]$script:ServerFilter) ([ref]$script:ServerFiltered) ([ref]$script:ServerCurrentPage)
Update-ServerPaging $script:ServerRowsPerPage $script:ServerCurrentPage $script:ServerFiltered $script:ServerTotalPages $script:PagedServers $Controls

# --- Start async data load ---
Get-ServerDataAsync ([ref]$AllServers) $Controls
Update-DashboardAndTop10-Wrapper

# --- Show the Window ---
$Window.ShowDialog() | Out-Null