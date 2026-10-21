<#
.SYNOPSIS
  NIS16 Capture Wizard - GUI version (point-and-click front-end).

.DESCRIPTION
  A window alternative to run_wizard.ps1 (the CLI wizard stays, unchanged in
  behaviour - use whichever you like). Added oct. 17 2026.

  DESIGN RULE - the GUI is a FRONT-END, not a second wizard:
    * It READS data directly: presets\, member_boards.json, the campaign plan
      (tools\inventory_cells.py --json), the redo list (tools\redo_list.py --json),
      the analysis tree.
    * It LAUNCHES the proven CLI pieces for anything that touches hardware or
      runs long: a capture = run_wizard.ps1 -Preset <file> in its own console
      window; analysis = analyze.ps1 in its own window. Read-only checks (the
      attack verifier, the topology check) run in the background and their
      report is shown inside the window.
    Flashing / monitoring logic therefore exists ONCE (in the CLI) and cannot
    drift between two copies.

  Run it from the ESP-IDF PowerShell (same as run_wizard.ps1), so a capture it
  launches can build and flash:
      .\run_gui.ps1
  Nothing is installed: WPF ships with Windows / .NET Framework.
#>
param(
    [switch]$DryRun,
    # Tester mode: build the window off-screen, load every page with real data,
    # wait for the background jobs, save a PNG of each page into -ShotDir, exit.
    # Lets the layout be checked without anyone clicking (oct. 17 2026).
    [switch]$SelfTest,
    [string]$ShotDir = $env:TEMP
)

$ErrorActionPreference = 'Stop'
$base = $PSScriptRoot

# WPF needs an STA thread. Windows PowerShell 5.1's console is STA already;
# relaunch once if something started us MTA.
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    Start-Process powershell -ArgumentList @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"") | Out-Null
    return
}
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ── shared logic: the CLI's own functions (oct. 17 2026) ─────────────────────
# Every top-level function and constant of run_wizard.ps1 that comes BEFORE its
# main program is loaded here WITHOUT running any menu - so MAC reading, the
# location command, Wireshark views, preset reading, file naming ... exist ONCE
# and both front-ends use the same code. GUI functions defined further down win
# on a name clash. Read-Line (the console prompt) is replaced so nothing here
# can ever sit waiting for typed input behind the window.
$wizAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $base 'run_wizard.ps1'), [ref]$null, [ref]$null)
$wizStop = ($wizAst.EndBlock.Statements | Where-Object { $_.Extent.Text -like '$originalPreset = $Preset*' } | Select-Object -First 1).Extent.StartLineNumber
foreach ($wizSt in $wizAst.EndBlock.Statements) {
    if ($wizSt.Extent.StartLineNumber -ge $wizStop) { break }
    if ($wizSt -is [Management.Automation.Language.FunctionDefinitionAst]) { . ([scriptblock]::Create($wizSt.Extent.Text)); continue }
    if ($wizSt -is [Management.Automation.Language.AssignmentStatementAst] -and $wizSt.Extent.Text -notmatch '^\$ErrorActionPreference') {
        try { . ([scriptblock]::Create($wizSt.Extent.Text)) } catch { }
    }
}
# Restore $base BEFORE using it: the wizard's own '$base = $PSScriptRoot'
# runs above inside a [scriptblock]::Create, where $PSScriptRoot is empty.
$base = $PSScriptRoot
foreach ($wizTool in 'tools\Show-MemberBoards.ps1', 'tools\ImportBatch.ps1') { $t = Join-Path $base $wizTool; if (Test-Path $t) { . $t } }
# GUI feature modules (oct. 18 2026): one file per feature in gui\, so two people
# can work on the GUI without editing the same 8,000-line file. Each defines
# functions only; Initialize-Gui* ones run once the window exists.
foreach ($guiMod in @(Get-ChildItem (Join-Path $base 'gui') -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name)) { . $guiMod.FullName }
$base = $PSScriptRoot
# the wizard's build roots were computed from the empty $base too - redo them
# (same formula as run.ps1 / run_wizard.ps1, so the GUI predicts the same dirs)
$repoTag        = (Split-Path (Split-Path $base -Parent) -Leaf) + '_' + ([math]::Abs($base.GetHashCode())).ToString('x8')
$buildRoot      = Join-Path $env:LOCALAPPDATA "esp32_builds\$repoTag"
$shortBuildRoot = Join-Path $env:SystemDrive "esp32b\$repoTag"
function Read-Line { throw 'This step needs typed input - it is not available from the GUI.' }

# ── calm palette (same meaning as the CLI's $script:Soft) ─────────────────────
# Named $Pal, NOT $C: PowerShell variable names are case-INSENSITIVE, so a
# palette called $C was silently replaced by any local $c (a cell / preset)
# - every colour in that handler became empty (found by -SelfTest).
# oct. 17 2026 redesign: deep-indigo base + colourful accents (user asked for
# "modern, fun, some colours"). Same key names, so every page keeps its meaning:
# red = blackhole / missing, purple = wormhole, green = done / plugged in,
# amber = in progress / check, blue = child, accent = primary actions.
$Pal = @{
    Bg = '#11121D'; Panel = '#181A2A'; Card = '#20233A'; Card2 = '#272B47'; Line = '#2F3352'; Hover = '#2B2F50'
    Text = '#ECEEFF'; Dim = '#A3A8C8'; Faint = '#6D7299'
    Red = '#FB7185'; Purple = '#C084FC'; Green = '#34D399'; Amber = '#FBBF24'; Orange = '#FB923C'; Blue = '#60A5FA'
    Pink = '#F472B6'; Cyan = '#22D3EE'; Lime = '#A3E635'
    Accent = '#8B5CF6'; Accent2 = '#22D3EE'
}
# The dark controls every window shares (main window AND the preset editor).
$StyleXaml = @"
    <DataTemplate x:Key="TextItem"><TextBlock Text="{Binding Text}"/></DataTemplate>
    <LinearGradientBrush x:Key="GradMain" StartPoint="0,0" EndPoint="1,1"><GradientStop Color="#8B5CF6" Offset="0"/><GradientStop Color="#EC4899" Offset="1"/></LinearGradientBrush>
    <LinearGradientBrush x:Key="GradCool" StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#8B5CF6" Offset="0"/><GradientStop Color="#22D3EE" Offset="1"/></LinearGradientBrush>
    <LinearGradientBrush x:Key="GradGood" StartPoint="0,0" EndPoint="1,0"><GradientStop Color="#34D399" Offset="0"/><GradientStop Color="#22D3EE" Offset="1"/></LinearGradientBrush>
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="$($Pal.Card2)"/><Setter Property="Foreground" Value="$($Pal.Text)"/>
      <Setter Property="BorderBrush" Value="$($Pal.Accent)"/><Setter Property="Padding" Value="10,6"/>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="$($Pal.Card2)"/>
      <Setter Property="Foreground" Value="$($Pal.Text)"/>
      <Setter Property="BorderBrush" Value="$($Pal.Line)"/>
      <Setter Property="Padding" Value="16,8"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="RenderTransformOrigin" Value="0.5,0.5"/>
      <Setter Property="RenderTransform"><Setter.Value><ScaleTransform/></Setter.Value></Setter>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Grid>
              <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}"
                      BorderThickness="1" CornerRadius="10" Padding="{TemplateBinding Padding}">
                <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <Border x:Name="glow" CornerRadius="10" Background="#FFFFFF" Opacity="0" IsHitTestVisible="False"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="$($Pal.Accent)"/>
                <Setter TargetName="glow" Property="Opacity" Value="0.06"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="glow" Property="Opacity" Value="0.14"/>
                <Setter Property="RenderTransform"><Setter.Value><ScaleTransform ScaleX="0.97" ScaleY="0.97"/></Setter.Value></Setter>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="{StaticResource GradMain}"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Cool" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="{StaticResource GradCool}"/>
      <Setter Property="BorderBrush" Value="Transparent"/>
      <Setter Property="Foreground" Value="White"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
    </Style>
    <Style x:Key="Danger" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background" Value="#3A1E2C"/>
      <Setter Property="BorderBrush" Value="#7A2E45"/>
      <Setter Property="Foreground" Value="$($Pal.Red)"/>
    </Style>
    <Style x:Key="Chip" TargetType="RadioButton">
      <Setter Property="Foreground" Value="$($Pal.Dim)"/>
      <Setter Property="Margin" Value="0,0,6,8"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Border x:Name="b" Background="$($Pal.Card)" BorderBrush="$($Pal.Line)" BorderThickness="1" CornerRadius="14" Padding="13,5">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="$($Pal.Accent)"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="{StaticResource GradCool}"/>
                <Setter TargetName="b" Property="BorderBrush" Value="Transparent"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="$($Pal.Dim)"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="track" Width="34" Height="18" CornerRadius="9" Background="$($Pal.Line)" VerticalAlignment="Center">
                <Ellipse x:Name="knob" Width="12" Height="12" Fill="$($Pal.Dim)" HorizontalAlignment="Left" Margin="3,0"/>
              </Border>
              <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="track" Property="Background" Value="{StaticResource GradCool}"/>
                <Setter TargetName="knob" Property="HorizontalAlignment" Value="Right"/>
                <Setter TargetName="knob" Property="Fill" Value="White"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True"><Setter Property="Foreground" Value="$($Pal.Text)"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- a real check box (rounded square + check mark) for ticking ROWS in a
         table; the switch look above stays for on/off settings -->
    <Style x:Key="TickBox" TargetType="CheckBox">
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="HorizontalAlignment" Value="Center"/>
      <Setter Property="VerticalAlignment" Value="Center"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <Border x:Name="box" Width="20" Height="20" CornerRadius="6" Background="Transparent" BorderBrush="$($Pal.Dim)" BorderThickness="1.5">
              <Path x:Name="mark" Data="M 4.5,10 L 8.5,14 L 15.5,6" Stroke="White" StrokeThickness="2.4"
                    StrokeStartLineCap="Round" StrokeEndLineCap="Round" StrokeLineJoin="Round" Visibility="Collapsed"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="box" Property="BorderBrush" Value="$($Pal.Text)"/></Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="box" Property="Background" Value="{StaticResource GradCool}"/>
                <Setter TargetName="box" Property="BorderThickness" Value="0"/>
                <Setter TargetName="mark" Property="Visibility" Value="Visible"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="box" Property="Opacity" Value="0.4"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="$($Pal.Card)"/><Setter Property="Foreground" Value="$($Pal.Text)"/>
      <Setter Property="BorderBrush" Value="$($Pal.Line)"/><Setter Property="CaretBrush" Value="$($Pal.Text)"/>
      <Setter Property="Padding" Value="8,5"/><Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TextBox">
            <Border x:Name="b" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="8">
              <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="$($Pal.Accent)"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="$($Pal.Text)"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="b" Background="Transparent" CornerRadius="6" Padding="{TemplateBinding Padding}" Margin="2,1">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True"><Setter TargetName="b" Property="Background" Value="$($Pal.Hover)"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="Background" Value="#3B2F6B"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="$($Pal.Text)"/>
      <Setter Property="Background" Value="$($Pal.Card)"/>
      <Setter Property="BorderBrush" Value="$($Pal.Line)"/>
      <Setter Property="Margin" Value="0,0,8,8"/>
      <Setter Property="Padding" Value="10,6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="tg" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="bd" Background="$($Pal.Card)" BorderBrush="$($Pal.Line)" BorderThickness="1" CornerRadius="8">
                      <TextBlock Text="&#xE70D;" FontFamily="Segoe MDL2 Assets" FontSize="10" Foreground="$($Pal.Dim)"
                                 HorizontalAlignment="Right" VerticalAlignment="Center" Margin="0,0,10,0"/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="$($Pal.Accent)"/></Trigger>
                      <Trigger Property="IsChecked" Value="True"><Setter TargetName="bd" Property="BorderBrush" Value="$($Pal.Accent)"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter x:Name="cp" IsHitTestVisible="False" Margin="12,6,28,6" VerticalAlignment="Center"
                                Content="{TemplateBinding SelectionBoxItem}" ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"/>
              <TextBox x:Name="PART_EditableTextBox" Style="{x:Null}" Visibility="Hidden" Margin="2,0,24,0" Background="Transparent" BorderThickness="0"
                       Foreground="$($Pal.Text)" CaretBrush="$($Pal.Text)" VerticalAlignment="Center" IsReadOnly="{TemplateBinding IsReadOnly}"/>
              <Popup x:Name="PART_Popup" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom" AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                <Border Background="$($Pal.Card2)" BorderBrush="$($Pal.Accent)" BorderThickness="1" CornerRadius="8" Margin="0,4,0,0"
                        MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}" MaxHeight="360">
                  <ScrollViewer Margin="2,4"><ItemsPresenter KeyboardNavigation.DirectionalNavigation="Contained"/></ScrollViewer>
                </Border>
              </Popup>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsEditable" Value="True">
                <Setter TargetName="PART_EditableTextBox" Property="Visibility" Value="Visible"/>
                <Setter TargetName="cp" Property="Visibility" Value="Hidden"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ScrollBar">
      <Setter Property="Width" Value="8"/><Setter Property="MinWidth" Value="8"/>
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ScrollBar">
            <Track x:Name="PART_Track" IsDirectionReversed="True">
              <Track.Thumb>
                <Thumb>
                  <Thumb.Template>
                    <ControlTemplate TargetType="Thumb"><Border CornerRadius="4" Background="$($Pal.Line)" Margin="1"/></ControlTemplate>
                  </Thumb.Template>
                </Thumb>
              </Track.Thumb>
            </Track>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="Orientation" Value="Horizontal">
          <Setter Property="Width" Value="Auto"/><Setter Property="Height" Value="8"/><Setter Property="MinHeight" Value="8"/>
          <Setter Property="Template">
            <Setter.Value>
              <ControlTemplate TargetType="ScrollBar">
                <Track x:Name="PART_Track">
                  <Track.Thumb>
                    <Thumb>
                      <Thumb.Template>
                        <ControlTemplate TargetType="Thumb"><Border CornerRadius="4" Background="$($Pal.Line)" Margin="1"/></ControlTemplate>
                      </Thumb.Template>
                    </Thumb>
                  </Track.Thumb>
                </Track>
              </ControlTemplate>
            </Setter.Value>
          </Setter>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="DataGrid">
      <Setter Property="Background" Value="$($Pal.Panel)"/>
      <Setter Property="Foreground" Value="$($Pal.Text)"/>
      <Setter Property="RowBackground" Value="$($Pal.Panel)"/>
      <Setter Property="AlternatingRowBackground" Value="#1C1F33"/>
      <Setter Property="BorderBrush" Value="$($Pal.Line)"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="GridLinesVisibility" Value="None"/>
      <Setter Property="HeadersVisibility" Value="Column"/>
      <Setter Property="AutoGenerateColumns" Value="False"/>
      <Setter Property="IsReadOnly" Value="True"/>
      <Setter Property="SelectionMode" Value="Single"/>
      <Setter Property="CanUserAddRows" Value="False"/>
      <Setter Property="RowHeight" Value="30"/>
      <Setter Property="VerticalContentAlignment" Value="Center"/>
    </Style>
    <Style TargetType="DataGridRow">
      <Setter Property="Cursor" Value="Hand"/>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Background" Value="$($Pal.Hover)"/></Trigger>
      </Style.Triggers>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="$($Pal.Card)"/>
      <Setter Property="Foreground" Value="$($Pal.Dim)"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="10,8"/>
      <Setter Property="BorderBrush" Value="$($Pal.Line)"/>
      <Setter Property="BorderThickness" Value="0,0,0,1"/>
    </Style>
    <Style TargetType="DataGridCell">
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Padding" Value="8,0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="DataGridCell">
            <Border Background="{TemplateBinding Background}" Padding="{TemplateBinding Padding}">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsSelected" Value="True">
          <Setter Property="Background" Value="#3B2F6B"/>
          <Setter Property="Foreground" Value="$($Pal.Text)"/>
        </Trigger>
      </Style.Triggers>
    </Style>
    <Style x:Key="SubTab" TargetType="TabItem">
      <Setter Property="Foreground" Value="$($Pal.Dim)"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="b" Background="$($Pal.Card)" BorderBrush="$($Pal.Line)" BorderThickness="1" CornerRadius="16" Padding="12,6" Margin="0,0,6,4">
              <ContentPresenter ContentSource="Header"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="$($Pal.Accent)"/></Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="b" Property="Background" Value="{StaticResource GradMain}"/>
                <Setter TargetName="b" Property="BorderBrush" Value="Transparent"/>
                <Setter Property="Foreground" Value="White"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ProgressBar">
      <Setter Property="Height" Value="8"/>
      <Setter Property="Foreground" Value="{StaticResource GradGood}"/>
      <Setter Property="Background" Value="$($Pal.Line)"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ProgressBar">
            <Grid>
              <Border x:Name="PART_Track" Background="{TemplateBinding Background}" CornerRadius="4"/>
              <Border x:Name="PART_Indicator" Background="{TemplateBinding Foreground}" CornerRadius="4" HorizontalAlignment="Left"/>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style x:Key="H1" TargetType="TextBlock"><Setter Property="Foreground" Value="$($Pal.Text)"/><Setter Property="FontSize" Value="26"/><Setter Property="FontWeight" Value="Bold"/><Setter Property="Margin" Value="0,0,0,4"/></Style>
    <Style x:Key="Sub" TargetType="TextBlock"><Setter Property="Foreground" Value="$($Pal.Dim)"/><Setter Property="Margin" Value="0,0,0,16"/><Setter Property="TextWrapping" Value="Wrap"/></Style>
    <Style x:Key="Label" TargetType="TextBlock"><Setter Property="Foreground" Value="$($Pal.Faint)"/><Setter Property="FontSize" Value="11"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,0,0,4"/></Style>
    <!-- oct. 19 2026: cards lit from above - a lighter top edge fading to the old line colour -->
    <LinearGradientBrush x:Key="CardEdge" StartPoint="0,0" EndPoint="0,1"><GradientStop Color="#454B7A" Offset="0"/><GradientStop Color="$($Pal.Line)" Offset="0.35"/><GradientStop Color="#23263D" Offset="1"/></LinearGradientBrush>
    <Style x:Key="Card" TargetType="Border"><Setter Property="Background" Value="$($Pal.Card)"/><Setter Property="CornerRadius" Value="16"/><Setter Property="Padding" Value="20"/><Setter Property="BorderBrush" Value="{StaticResource CardEdge}"/><Setter Property="BorderThickness" Value="1"/></Style>
"@

# ── data helpers ──────────────────────────────────────────────────────────────
$TOPOLOGY_ORDER = @('linear', 'tree', 'star', 'partial', 'partial_mesh')
$SCENARIO_ORDER = @('stationary', 'burst', 'highload', 'jitter', 'mobility', 'powercycle')
$ATTACK_ORDER   = @('none', 'baseline', 'blackhole', 'wormhole')
$LOCATION_ORDER = @('G402', 'DLSU_Library', 'Yuchengco', 'home')
function Get-Rank($list, $v) { $i = [array]::IndexOf(@($list), [string]$v); if ($i -lt 0) { 99 } else { $i } }

function Get-ShortMac([string]$Mac) {
    $p = @($Mac -split '[:\-\s]' | Where-Object { $_ })
    if ($p.Count -lt 2) { return $Mac.ToUpper() }
    return ('{0}:{1}' -f $p[0], $p[$p.Count - 1]).ToUpper()
}

function Get-Nicknames {
    $map = @{}
    $f = Join-Path $base 'member_boards.json'
    if (-not (Test-Path $f)) { return $map }
    try {
        $j = Get-Content $f -Raw | ConvertFrom-Json
        foreach ($m in $j.members) { foreach ($b in $m.boards) { if ($b.mac) { $map[(Get-ShortMac $b.mac)] = [string]$b.nickname } } }
    } catch { }
    return $map
}

function Get-Ports {
    $names = @()
    try { $names = @([IO.Ports.SerialPort]::GetPortNames() | Sort-Object -Unique) } catch { }
    $desc = @{}
    try {
        Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '\((COM\d+)\)' } |
            ForEach-Object { if ($_.Name -match '\((COM\d+)\)') { $desc[$Matches[1]] = ($_.Name -replace '\s*\(COM\d+\)\s*$', '') } }
    } catch { }
    return @($names | ForEach-Object { [pscustomobject]@{ Port = $_; Description = $(if ($desc[$_]) { $desc[$_] } else { '' }) } })
}

function Get-Presets {
    $root = Join-Path $base 'presets'
    if (-not (Test-Path $root)) { return @() }
    $nick = Get-Nicknames
    $out = @()
    foreach ($f in Get-ChildItem $root -Recurse -Filter *.json -File) {
        try { $c = Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { continue }
        $owner = if ($f.Directory.FullName -ne (Resolve-Path $root).Path) { $f.Directory.Name } else { '(unfiled)' }
        $attack = [string]$c.attack; if (-not $attack -or $attack -eq 'none') { $attack = 'baseline' }
        $scn = [string]$c.scenario; if (-not $scn -or $scn -eq 'none') { $scn = 'stationary' }
        $when = $f.LastWriteTime
        if ($c.savedAt) { $d = [datetime]::MinValue; if ([datetime]::TryParseExact([string]$c.savedAt, 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture, 'None', [ref]$d)) { $when = $d } }
        $boards = @($c.boards)
        $key = @()
        foreach ($b in $boards) {
            switch ([string]$b.Kind) {
                'attacker' { $key += ('atk ' + (Get-ShortMac ([string]$b.Mac))) }
                'A'        { $key += ('A ' + (Get-ShortMac ([string]$b.Mac))) }
                'B'        { $key += ('B ' + (Get-ShortMac ([string]$b.Mac))) }
            }
        }
        $key = @($key | Sort-Object { switch -Regex ($_) { '^atk' { 0 } '^A ' { 1 } default { 2 } } })
        $want = ('{0}-{1}-{2}-{3}' -f $attack, ($c.topology -replace '^partial$', 'partial_mesh'), $c.location, $scn).ToLower()
        $out += [pscustomobject]@{
            Owner = $owner; Attack = $attack; Topology = [string]$c.topology; Location = [string]$c.location
            Scenario = $scn; Repeat = [int]$c.repeat; Boards = $boards.Count
            KeyBoards = ($key -join '  '); Saved = $when; SavedText = $when.ToString('MMM dd  hh:mm tt', [Globalization.CultureInfo]::InvariantCulture)
            NameFlag = $(if ($f.BaseName.ToLower().StartsWith($want)) { '' } else { '!' })
            File = $f.Name; Path = $f.FullName; Cfg = $c; Nick = $nick
        }
    }
    return @($out | Sort-Object @{ E = { Get-Rank $ATTACK_ORDER $_.Attack } }, @{ E = { Get-Rank $TOPOLOGY_ORDER $_.Topology } },
                                @{ E = { Get-Rank $SCENARIO_ORDER $_.Scenario } }, @{ E = { Get-Rank $LOCATION_ORDER $_.Location } },
                                @{ E = { $_.Saved }; Descending = $true })
}

function Find-PandasPython {
    foreach ($cand in @('python', 'py', 'python3')) {
        if (-not (Get-Command $cand -ErrorAction SilentlyContinue)) { continue }
        # oct. 19 2026 (teammate's laptop): this file runs with ErrorActionPreference = Stop,
        # and in PowerShell 5.1 a native program's stderr is then a TERMINATING error even
        # with 2>$null - a Python WITHOUT pandas printed a traceback and killed the GUI at
        # start-up instead of being skipped. Probe with Continue; any failure = next one.
        $ok = $false
        $eap = $ErrorActionPreference
        try { $ErrorActionPreference = 'Continue'; $null = & $cand -c "import pandas" 2>&1; $ok = ($LASTEXITCODE -eq 0) }
        catch { $ok = $false }
        finally { $ErrorActionPreference = $eap }
        if ($ok) { return $cand }
    }
    return $null
}

# ── background jobs: run a tool, show its output when it finishes ────────────
# A process with redirected output + a DispatcherTimer polling it, so the window
# stays responsive (the redo list takes about a minute).
$script:Jobs = New-Object System.Collections.ArrayList
function Start-ToolJob {
    param([string]$Exe, [string[]]$ToolArgs, [scriptblock]$OnDone, $State = $null)
    $out = [IO.Path]::GetTempFileName(); $err = [IO.Path]::GetTempFileName()
    $env:PYTHONIOENCODING = 'utf-8'; $env:NO_COLOR = '1'
    $quoted = @($ToolArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
    $p = Start-Process -FilePath $Exe -ArgumentList $quoted -WorkingDirectory $base -NoNewWindow -PassThru `
        -RedirectStandardOutput $out -RedirectStandardError $err
    # Touch the handle NOW: without it .NET drops the exit code of a process
    # started this way, and the verifier verdict (0 / 1 / 3) read as empty.
    $null = $p.Handle
    [void]$script:Jobs.Add([pscustomobject]@{ Proc = $p; Out = $out; Err = $err; Done = $OnDone; State = $State })
}
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(400)
$timer.Add_Tick({ Measure-GuiTick 'jobs' {   # gui\Perf.ps1: a tick over 150 ms is logged
    foreach ($j in @($script:Jobs)) {
        if (-not $j.Proc.HasExited) { continue }
        [void]$script:Jobs.Remove($j)
        $text = (Get-Content $j.Out -Raw -Encoding UTF8) + "`n" + (Get-Content $j.Err -Raw -Encoding UTF8)
        Remove-Item $j.Out, $j.Err -ErrorAction SilentlyContinue
        # State is passed in, not captured with GetNewClosure(): a closure cannot
        # see this script's own functions (Set-Status, New-Card ...).
        try { & $j.Done $text $j.Proc.ExitCode $j.State } catch {
            # oct. 19 2026: say WHERE (a bare message cost a guessing round)
            $msg = "Could not show the result: {0}  (line {1}: {2})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber, ([string]$_.InvocationInfo.Line).Trim()
            Set-Status $msg $Pal.Red
            if ($SelfTest) { Write-Output ("TOOLJOB ERROR: " + $msg) }
        }
    }
} })
$timer.Start()

function Start-ConsoleWindow {
    # Hardware / long work: its own PowerShell window, inheriting this
    # session's environment (ESP-IDF, python) - exactly like typing it.
    param([string]$Script, [string[]]$ScriptArgs, [string]$Title)
    $cmd = "`$Host.UI.RawUI.WindowTitle = '$Title'; Set-Location '$base'; & '$Script' " + ($ScriptArgs -join ' ')
    $p = Start-Process powershell -ArgumentList @('-NoExit', '-ExecutionPolicy', 'Bypass', '-Command', $cmd) -WorkingDirectory $base -PassThru
    # remembered so the board watcher never resets a board while it is open
    if ($script:Consoles -ne $null) { [void]$script:Consoles.Add($p) }
    # a capture window: when it closes, offer the next step (import)
    if ($Title -like 'Capture:*' -and $script:Captures -ne $null) { [void]$script:Captures.Add([pscustomobject]@{ Proc = $p; Title = $Title }) }
}

# ── the window ────────────────────────────────────────────────────────────────
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="NIS16 Capture Studio" Width="1440" Height="900" MinWidth="1120" MinHeight="680"
        Background="$($Pal.Bg)" Foreground="$($Pal.Text)" FontFamily="Segoe UI" FontSize="13"
        WindowStartupLocation="CenterScreen">
  <Window.Resources>
$StyleXaml
    <Style x:Key="Nav" TargetType="RadioButton">
      <Setter Property="Foreground" Value="$($Pal.Dim)"/>
      <Setter Property="FontSize" Value="14"/>
      <Setter Property="Margin" Value="0,2"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="RadioButton">
            <Grid>
              <Border x:Name="b" Background="Transparent" CornerRadius="12" Padding="12,10">
                <StackPanel Orientation="Horizontal">
                  <TextBlock x:Name="ic" Text="{TemplateBinding Tag}" FontFamily="Segoe MDL2 Assets" FontSize="16" Width="22"
                             VerticalAlignment="Center" Foreground="$($Pal.Faint)"/>
                  <ContentPresenter Margin="10,0,0,0" VerticalAlignment="Center"/>
                </StackPanel>
              </Border>
              <Border x:Name="bar" Width="4" CornerRadius="2" HorizontalAlignment="Left" Margin="0,8" Background="{StaticResource GradMain}" Opacity="0"/>
            </Grid>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="b" Property="Background" Value="$($Pal.Card)"/>
                <Setter Property="Foreground" Value="$($Pal.Text)"/>
              </Trigger>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="b" Property="Background" Value="$($Pal.Card2)"/>
                <Setter TargetName="bar" Property="Opacity" Value="1"/>
                <Setter TargetName="ic" Property="Foreground" Value="$($Pal.Pink)"/>
                <Setter Property="Foreground" Value="$($Pal.Text)"/>
                <Setter Property="FontWeight" Value="SemiBold"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- Run a capture: one preset card (oct. 18 2026: a template, so WPF builds
         the cards itself - the script-built cards froze the window ~1.6 s) -->
    <Style x:Key="CardGroup" TargetType="ListBox">
      <Setter Property="Background" Value="Transparent"/><Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="ListBox"><ItemsPresenter/></ControlTemplate></Setter.Value></Setter>
      <Setter Property="ItemsPanel"><Setter.Value><ItemsPanelTemplate><WrapPanel/></ItemsPanelTemplate></Setter.Value></Setter>
    </Style>
    <Style x:Key="PresetCardItem" TargetType="ListBoxItem">
      <Setter Property="Margin" Value="0,0,10,10"/><Setter Property="Padding" Value="0"/><Setter Property="Cursor" Value="Hand"/>
      <Setter Property="ToolTip" Value="{Binding Tip}"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ListBoxItem">
            <Border x:Name="b" Width="192" CornerRadius="14" Padding="14,12" Background="{Binding CardBg}" BorderBrush="$($Pal.Line)" BorderThickness="1.5">
              <ContentPresenter/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="$($Pal.Accent)"/></Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="b" Property="BorderBrush" Value="#FFFFFF"/><Setter TargetName="b" Property="BorderThickness" Value="2"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <DataTemplate x:Key="PresetCardTpl">
      <StackPanel>
        <DockPanel>
          <Border DockPanel.Dock="Right" CornerRadius="8" Padding="7,2" VerticalAlignment="Top" Background="{Binding RibBg}">
            <TextBlock Text="{Binding RibText}" Foreground="{Binding RibFg}" FontSize="10" FontWeight="Bold"/>
          </Border>
          <Image Source="{Binding Art}" Width="64" Height="38" HorizontalAlignment="Left"/>
        </DockPanel>
        <TextBlock Margin="0,10,0,0" FontSize="10" FontWeight="Bold">
          <Run Text="{Binding AtkText, Mode=OneWay}" Foreground="{Binding AtkFg, Mode=OneWay}"/><Run Text="{Binding RepText, Mode=OneWay}" Foreground="$($Pal.Amber)"/>
        </TextBlock>
        <TextBlock Text="{Binding Topo}" FontSize="16" FontWeight="Bold" Foreground="$($Pal.Text)" Margin="0,1,0,1"/>
        <TextBlock Text="{Binding DateText}" Foreground="$($Pal.Dim)" FontSize="11" Margin="0,0,0,6" ToolTip="{Binding DateFull}"/>
        <WrapPanel>
          <Border CornerRadius="8" Padding="7,1" Background="{Binding LocBg}" Margin="0,0,5,4">
            <TextBlock Text="{Binding LocText}" Foreground="{Binding LocFg}" FontSize="11" FontWeight="SemiBold"/>
          </Border>
          <Border CornerRadius="8" Padding="7,1" Background="{Binding ScnBg}" Margin="0,0,5,4">
            <TextBlock Text="{Binding ScnText}" Foreground="{Binding ScnFg}" FontSize="11" FontWeight="SemiBold"/>
          </Border>
        </WrapPanel>
        <DockPanel Margin="0,6,0,0">
          <TextBlock DockPanel.Dock="Right" Text="{Binding HereText}" Foreground="{Binding HereFg}" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>
          <ItemsControl ItemsSource="{Binding Dots}" VerticalAlignment="Center">
            <ItemsControl.ItemsPanel><ItemsPanelTemplate><WrapPanel/></ItemsPanelTemplate></ItemsControl.ItemsPanel>
            <ItemsControl.ItemTemplate>
              <DataTemplate><Ellipse Width="9" Height="9" Margin="0,0,4,0" Fill="{Binding Fill}" Stroke="{Binding Stroke}" StrokeThickness="1.4" Opacity="{Binding Op}" ToolTip="{Binding Tip}"/></DataTemplate>
            </ItemsControl.ItemTemplate>
          </ItemsControl>
        </DockPanel>
      </StackPanel>
    </DataTemplate>
  </Window.Resources>

  <Grid>
  <DockPanel>
    <!-- sidebar -->
    <Border DockPanel.Dock="Left" Width="236" Background="$($Pal.Panel)" BorderBrush="$($Pal.Line)" BorderThickness="0,0,1,0">
      <DockPanel Margin="14,18">
        <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="4,0,0,24">
          <Border Width="42" Height="42" CornerRadius="12" Background="{StaticResource GradMain}">
            <TextBlock Text="&#xE945;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
          </Border>
          <StackPanel Margin="12,0,0,0" VerticalAlignment="Center">
            <TextBlock Text="Capture Studio" FontSize="17" FontWeight="Bold"/>
            <TextBlock Text="NIS16  ·  ESP-WIFI-MESH" FontSize="11" Foreground="$($Pal.Faint)"/>
          </StackPanel>
        </StackPanel>
        <StackPanel DockPanel.Dock="Bottom">
          <DockPanel Margin="6,0,0,10">
            <TextBlock Text="I AM" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="0,0,10,0"/>
            <ComboBox x:Name="MePick" Margin="0" ToolTip="Your presets are shown first and new presets are saved under your name. Remembered on this laptop."/>
          </DockPanel>
          <Button x:Name="OpenPalette" Margin="0,0,0,12" Padding="10,7" HorizontalContentAlignment="Stretch"
                  ToolTip="Jump to anything: pages, actions, presets, campaign runs">
            <DockPanel>
              <Border DockPanel.Dock="Right" CornerRadius="5" Background="$($Pal.Line)" Padding="6,1"><TextBlock Text="Ctrl+K" FontSize="11" Foreground="$($Pal.Dim)"/></Border>
              <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" Foreground="$($Pal.Cyan)" VerticalAlignment="Center" Margin="2,0,8,0"/>
              <TextBlock Text="Search / do anything" Foreground="$($Pal.Dim)" VerticalAlignment="Center"/>
            </DockPanel>
          </Button>
          <CheckBox x:Name="DryRun" Content="Dry run (flash nothing)" Margin="6,0,0,12"/>
          <CheckBox x:Name="AutoMac" Content="Identify boards (no reset)" ToolTip="New boards are asked who they are (GET_ID) - never reset. Read all MACs on Home is the only thing that resets a board." IsChecked="True" Margin="6,0,0,12"/>
          <Button x:Name="OpenCli" Content="Open the CLI wizard" Margin="0,0,0,8"/>
          <TextBlock x:Name="EnvInfo" Foreground="$($Pal.Faint)" FontSize="11" TextWrapping="Wrap" Margin="6,4,0,0"/>
        </StackPanel>
        <DockPanel>
          <StackPanel DockPanel.Dock="Top">
            <RadioButton x:Name="NavHome"     Style="{StaticResource Nav}" Tag="&#xE80F;" Content="Home" GroupName="nav" IsChecked="True"/>
            <RadioButton x:Name="NavCapture"  Style="{StaticResource Nav}" Tag="&#xE768;" Content="Run a capture" GroupName="nav"/>
            <RadioButton x:Name="NavRun"      Style="{StaticResource Nav}" Tag="&#xE945;" Content="Live run" GroupName="nav"/>
            <RadioButton x:Name="NavVerify"   Style="{StaticResource Nav}" Tag="&#xE73E;" Content="Verify &amp; analyse" GroupName="nav"/>
            <RadioButton x:Name="NavCampaign" Style="{StaticResource Nav}" Tag="&#xE787;" Content="Campaign" GroupName="nav"/>
            <RadioButton x:Name="NavBoards"   Style="{StaticResource Nav}" Tag="&#xE88E;" Content="Boards" GroupName="nav"/>
            <RadioButton x:Name="NavData"     Style="{StaticResource Nav}" Tag="&#xE8B7;" Content="Data" GroupName="nav"/>
            <RadioButton x:Name="NavSync"     Style="{StaticResource Nav}" Tag="&#xE895;" Content="GitHub sync" GroupName="nav"/>
            <RadioButton x:Name="NavWire"     Style="{StaticResource Nav}" Tag="&#xE701;" Content="Wireshark &amp; sniffer" GroupName="nav"/>
            <!-- live: every board plugged in right now (refreshed by itself) -->
            <DockPanel Margin="8,20,4,8">
              <Border DockPanel.Dock="Right" x:Name="SideCountBadge" CornerRadius="9" Padding="8,1" Background="{StaticResource GradGood}">
                <TextBlock x:Name="SideCount" Text="0" Foreground="#0B1020" FontWeight="Bold" FontSize="11"/>
              </Border>
              <TextBlock Text="PLUGGED IN NOW" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="0"/>
            </DockPanel>
            <!-- dot legend (user, oct. 20 2026: "what does the red dot mean") -->
            <WrapPanel Margin="8,0,4,6"><StackPanel Orientation="Horizontal" Margin="0,0,10,2" ToolTip="The GUI knows this board (its MAC was read)."><Ellipse Width="7" Height="7" Fill="$($Pal.Green)" VerticalAlignment="Center" Margin="0,0,4,0"/><TextBlock Text="identified" Foreground="$($Pal.Faint)" FontSize="10"/></StackPanel><StackPanel Orientation="Horizontal" Margin="0,0,10,2" ToolTip="Asking its ID / reading its MAC right now - wait a few seconds."><Ellipse Width="7" Height="7" Fill="$($Pal.Cyan)" VerticalAlignment="Center" Margin="0,0,4,0"/><TextBlock Text="identifying" Foreground="$($Pal.Faint)" FontSize="10"/></StackPanel><StackPanel Orientation="Horizontal" Margin="0,0,10,2" ToolTip="Not identified yet, or paused because a capture / export is running. Home > Read all MACs when nothing runs."><Ellipse Width="7" Height="7" Fill="$($Pal.Amber)" VerticalAlignment="Center" Margin="0,0,4,0"/><TextBlock Text="not yet / paused" Foreground="$($Pal.Faint)" FontSize="10"/></StackPanel><StackPanel Orientation="Horizontal" Margin="0,0,10,2" ToolTip="The board did not answer (MAC read failed): stuck, unplugged mid-read, or a sniffer (it never replies). Re-plug it, or ignore a sniffer."><Ellipse Width="7" Height="7" Fill="$($Pal.Red)" VerticalAlignment="Center" Margin="0,0,4,0"/><TextBlock Text="no answer" Foreground="$($Pal.Faint)" FontSize="10"/></StackPanel></WrapPanel>
            <TextBlock x:Name="SideEmpty" Text="No board plugged in - plug one in and it appears here." Foreground="$($Pal.Faint)" FontSize="11" TextWrapping="Wrap" Margin="8,0,0,0"/>
          </StackPanel>
          <!-- takes whatever height is left, scrolls when the boards do not fit -->
          <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,0,0,10">
            <ItemsControl x:Name="SideBoards" Margin="4,0,0,0">
              <ItemsControl.ItemTemplate>
                <DataTemplate>
                  <Border Background="$($Pal.Card)" CornerRadius="9" Padding="10,5" Margin="0,0,4,4" ToolTip="{Binding Tip}">
                    <DockPanel>
                      <Ellipse DockPanel.Dock="Left" Width="8" Height="8" Fill="{Binding Dot}" VerticalAlignment="Center" Margin="0,0,8,0"/>
                      <TextBlock DockPanel.Dock="Left" Text="{Binding Port}" FontWeight="SemiBold" FontSize="12" Width="50" VerticalAlignment="Center"/>
                      <TextBlock Text="{Binding Who}" Foreground="$($Pal.Dim)" FontSize="11" TextTrimming="CharacterEllipsis" VerticalAlignment="Center"/>
                    </DockPanel>
                  </Border>
                </DataTemplate>
              </ItemsControl.ItemTemplate>
            </ItemsControl>
          </ScrollViewer>
        </DockPanel>
      </DockPanel>
    </Border>

    <!-- status bar -->
    <Border DockPanel.Dock="Bottom" Background="$($Pal.Panel)" BorderBrush="$($Pal.Line)" BorderThickness="0,1,0,0" Padding="16,7">
      <DockPanel>
        <Button x:Name="ToggleActivity" DockPanel.Dock="Right" Content="Show activity" Padding="10,2" Margin="0" FontSize="11"/>
        <Ellipse x:Name="StatusDot" Width="8" Height="8" Fill="$($Pal.Green)" Margin="0,0,10,0" VerticalAlignment="Center"/>
        <TextBlock x:Name="Status" Foreground="$($Pal.Dim)" Text="Ready." VerticalAlignment="Center"/>
      </DockPanel>
    </Border>

    <!-- activity pane: live output of the running task -->
    <Border x:Name="ActivityPane" DockPanel.Dock="Bottom" Background="#0D0E17" BorderBrush="$($Pal.Line)" BorderThickness="0,1,0,0" Height="170" Visibility="Collapsed">
      <DockPanel>
        <DockPanel DockPanel.Dock="Top" Margin="16,8,12,2">
          <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
            <Button x:Name="StopTask" Content="Stop" Style="{StaticResource Danger}" IsEnabled="False" Padding="12,3" Margin="0,0,6,0"/>
            <Button x:Name="ClearActivity" Content="Clear" Padding="12,3" Margin="0"/>
          </StackPanel>
          <TextBlock Text="&#xE756;" FontFamily="Segoe MDL2 Assets" Foreground="$($Pal.Cyan)" VerticalAlignment="Center" Margin="0,0,8,0"/>
          <TextBlock Text="ACTIVITY  -  live output of what the GUI runs" Foreground="$($Pal.Faint)" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>
        </DockPanel>
        <RichTextBox x:Name="Activity" Background="Transparent" Foreground="$($Pal.Text)" BorderThickness="0" Padding="12,0,12,6"
                     FontFamily="Cascadia Mono, Consolas" FontSize="11" IsReadOnly="True" VerticalScrollBarVisibility="Auto"/>
      </DockPanel>
    </Border>

    <TabControl x:Name="Pages" Background="Transparent" Foreground="$($Pal.Text)" BorderThickness="0" Padding="30,24">
      <TabControl.ItemContainerStyle>
        <Style TargetType="TabItem">
          <Setter Property="Visibility" Value="Collapsed"/>
          <Setter Property="Foreground" Value="$($Pal.Text)"/>
        </Style>
      </TabControl.ItemContainerStyle>

      <!-- HOME -->
      <TabItem>
        <ScrollViewer VerticalScrollBarVisibility="Auto">
          <StackPanel>
            <!-- hero -->
            <Border CornerRadius="20" Padding="28,24" Margin="0,0,0,18" Background="{StaticResource GradMain}">
              <DockPanel>
                <StackPanel DockPanel.Dock="Right" VerticalAlignment="Center">
                  <Button x:Name="HomeGoCapture" Content="Start the next capture  &#x2192;" Background="White" Foreground="#5B21B6" BorderBrush="Transparent"
                          FontWeight="Bold" FontSize="14" Padding="22,12" Margin="0,0,0,8"/>
                  <Button x:Name="HomeRefresh" Content="Refresh" Background="#33FFFFFF" Foreground="White" BorderBrush="#55FFFFFF" Margin="0"/>
                </StackPanel>
                <StackPanel>
                  <TextBlock x:Name="HomeHello" Text="Hello, team" FontSize="30" FontWeight="Bold" Foreground="White"/>
                  <TextBlock x:Name="HomeSub" Text="Loading the campaign plan..." Foreground="#EDE9FE" FontSize="14" Margin="0,4,0,14" TextWrapping="Wrap"/>
                  <TextBlock Text="NEXT CAPTURE" Foreground="#DDD6FE" FontSize="11" FontWeight="SemiBold"/>
                  <TextBlock x:Name="HomeNext" FontSize="22" FontWeight="Bold" Foreground="White" Text="-"/>
                  <TextBlock x:Name="HomeNextWhy" Foreground="#EDE9FE" Text="" TextWrapping="Wrap"/>
                </StackPanel>
              </DockPanel>
            </Border>
            <!-- campaign cards -->
            <WrapPanel x:Name="HomeCards"/>
            <Grid Margin="0,6,0,0">
              <Grid.ColumnDefinitions><ColumnDefinition Width="3*"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
              <!-- live boards -->
              <Border Grid.Column="0" Style="{StaticResource Card}" Margin="0,0,14,14">
                <StackPanel>
                  <DockPanel Margin="0,0,0,12">
                    <Button x:Name="HomeReadMacs" DockPanel.Dock="Right" Content="Read all MACs" Margin="0" Padding="12,5"/>
                    <TextBlock Text="&#xE88E;" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="$($Pal.Green)" VerticalAlignment="Center" Margin="0,0,10,0"/>
                    <StackPanel>
                      <TextBlock Text="Boards plugged in" FontSize="16" FontWeight="SemiBold"/>
                      <TextBlock x:Name="HomeBoardsSub" Text="Plug a board in - it shows up here by itself." Foreground="$($Pal.Dim)" FontSize="12"/>
                    </StackPanel>
                  </DockPanel>
                  <WrapPanel x:Name="HomeBoards"/>
                </StackPanel>
              </Border>
              <!-- quick actions -->
              <Border Grid.Column="1" Style="{StaticResource Card}" Margin="0,0,0,14">
                <StackPanel>
                  <TextBlock Text="Quick actions" FontSize="16" FontWeight="SemiBold" Margin="0,0,0,12"/>
                  <UniformGrid x:Name="HomeActions" Columns="2"/>
                </StackPanel>
              </Border>
            </Grid>
          </StackPanel>
        </ScrollViewer>
      </TabItem>
      <!-- RUN A CAPTURE (oct. 18 2026 redesign, same look as Campaign: one box
           per person, a card per preset with a little drawing of its mesh, the
           campaign status on every card, an "up next" banner, board readiness) -->
      <TabItem>
        <DockPanel>
          <DockPanel DockPanel.Dock="Top">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Top">
              <Grid Width="240" Margin="0,0,8,8">
                <TextBox x:Name="PresetSearch" Margin="0" Padding="30,6,8,6" ToolTip="Type any part: wormhole tree g402, burst, a MAC, an owner..."/>
                <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" Foreground="$($Pal.Faint)" VerticalAlignment="Center" Margin="11,0,0,0" IsHitTestVisible="False"/>
                <TextBlock x:Name="PresetSearchHint" Text="Search presets..." Foreground="$($Pal.Faint)" VerticalAlignment="Center" Margin="31,0,0,0" IsHitTestVisible="False"/>
              </Grid>
              <Button x:Name="PresetsRefresh" Content="&#x21BB;  Refresh"/>
              <Button x:Name="PresetNew" Style="{StaticResource Primary}" Content="+  New preset"/>
            </StackPanel>
            <StackPanel>
              <TextBlock Style="{StaticResource H1}" Text="Run a capture"/>
              <TextBlock x:Name="CapSub" Style="{StaticResource Sub}" Text="Pick a preset card, check its boards, then start. The run opens on the Live run page: compile, flash, monitor, START and export - the same steps as the CLI, no console window."/>
            </StackPanel>
          </DockPanel>
          <!-- up next (campaign run order) -->
          <Border x:Name="CapHero" DockPanel.Dock="Top" CornerRadius="16" Padding="18,10" Margin="0,0,0,12" Background="{StaticResource GradMain}" Visibility="Collapsed">
            <DockPanel>
              <Button x:Name="CapHeroGo" DockPanel.Dock="Right" Content="Pick it  &#x2192;" Background="White" Foreground="#5B21B6" BorderBrush="Transparent"
                      FontWeight="SemiBold" Padding="18,8" Margin="12,0,0,0" VerticalAlignment="Center"/>
              <Border DockPanel.Dock="Left" Width="40" Height="40" CornerRadius="20" Background="#33FFFFFF" Margin="0,0,14,0" VerticalAlignment="Center">
                <TextBlock x:Name="CapHeroIcon" Text="&#xE768;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <StackPanel VerticalAlignment="Center">
                <TextBlock x:Name="CapHeroKicker" Text="UP NEXT FOR THE CAMPAIGN" FontSize="10" FontWeight="Bold" Foreground="#F5D0FE"/>
                <TextBlock x:Name="CapHeroTitle" FontSize="17" FontWeight="Bold" Foreground="White" TextWrapping="Wrap"/>
                <TextBlock x:Name="CapHeroSub" Foreground="#EDE9FE" TextWrapping="Wrap"/>
              </StackPanel>
            </DockPanel>
          </Border>
          <!-- filters: people, attack, ready only, search -->
          <WrapPanel DockPanel.Dock="Top" Margin="0,0,0,6">
            <TextBlock Text="WHOSE" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="0,0,10,8"/>
            <WrapPanel x:Name="OwnerChips"/>
            <TextBlock Text="ATTACK" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="10,0,10,8"/>
            <WrapPanel x:Name="AttackChips"/>
            <TextBlock Text="FILTER" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="10,0,10,8"/>
            <ComboBox x:Name="PresetFTopo" Width="140" ToolTip="Only this topology"/>
            <ComboBox x:Name="PresetFLoc" Width="150" ToolTip="Only this location"/>
            <ComboBox x:Name="PresetFScn" Width="140" ToolTip="Only this scenario"/>
            <RadioButton x:Name="PresetFAll" Style="{StaticResource Chip}" GroupName="capState" Content="All" IsChecked="True"/>
            <RadioButton x:Name="PresetFNeed" Style="{StaticResource Chip}" GroupName="capState" Content="Campaign needs it" ToolTip="UP NEXT, NEEDED, RE-CAPTURE and REDO - the runs still to capture"/>
            <RadioButton x:Name="PresetFDone" Style="{StaticResource Chip}" GroupName="capState" Content="Done already" ToolTip="DONE, CHECK and ANALYSE - captured already"/>
            <Button x:Name="PresetFClear" Content="Clear filters" Padding="12,5" ToolTip="Back to: all attacks, topologies, locations, scenarios, no search (the person stays)"/>
            <TextBlock Text="SORT" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="10,0,10,8"/>
            <RadioButton x:Name="PresetSNew" Style="{StaticResource Chip}" GroupName="capSort" Content="Newest first" IsChecked="True" ToolTip="Most recently saved preset on top"/>
            <RadioButton x:Name="PresetSOld" Style="{StaticResource Chip}" GroupName="capSort" Content="Oldest first"/>
            <RadioButton x:Name="PresetSType" Style="{StaticResource Chip}" GroupName="capSort" Content="By type" ToolTip="attack > topology > scenario > location, newest first inside each"/>
            <CheckBox x:Name="ReadyOnly" Content="Only presets I can run now" Margin="10,0,14,8" VerticalAlignment="Center"
                      ToolTip="Hide presets whose boards are not all plugged into this laptop (boards found by MAC, any USB socket)"/>
            <!-- the real filters / selection: the chips and cards drive these, so
                 every other page (palette, campaign, self-test) keeps working -->
            <ComboBox x:Name="OwnerPick" Visibility="Collapsed"/>
            <ComboBox x:Name="AttackPick" Visibility="Collapsed"/>
            <DataGrid x:Name="PresetGrid" Visibility="Collapsed"/>
          </WrapPanel>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="440"/></Grid.ColumnDefinitions>
            <!-- the gallery -->
            <ScrollViewer x:Name="PresetScroll" Grid.Column="0" VerticalScrollBarVisibility="Auto" Margin="0,0,14,0">
              <StackPanel x:Name="PresetGallery"/>
            </ScrollViewer>
            <!-- Everyone = one designed list (user, oct. 18 2026: faster; a person's
                 name shows their card boxes). Virtualised: only visible rows exist. -->
            <ListBox x:Name="PresetList" Grid.Column="0" Margin="0,0,14,0" Background="Transparent" BorderThickness="0" Visibility="Collapsed"
                     ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.CanContentScroll="True"
                     VirtualizingPanel.IsVirtualizing="True" VirtualizingPanel.VirtualizationMode="Recycling" VirtualizingPanel.ScrollUnit="Pixel"
                     VirtualizingPanel.IsVirtualizingWhenGrouping="True">
              <ListBox.GroupStyle>
                <GroupStyle>
                  <GroupStyle.HeaderTemplate>
                    <DataTemplate>
                      <DockPanel Margin="0,6,6,10">
                        <Border DockPanel.Dock="Left" CornerRadius="8" Padding="10,2" Background="{Binding Items[0].AtkBg}">
                          <TextBlock FontSize="11" FontWeight="Bold">
                            <Run Text="{Binding Name, Mode=OneWay}" Foreground="{Binding Items[0].AtkFg, Mode=OneWay}"/><Run Text="   " /><Run Text="{Binding ItemCount, Mode=OneWay}" Foreground="$($Pal.Dim)"/>
                          </TextBlock>
                        </Border>
                        <Border Height="2" CornerRadius="1" Margin="10,0,0,0" VerticalAlignment="Center" Background="{Binding Items[0].AtkLine}"/>
                      </DockPanel>
                    </DataTemplate>
                  </GroupStyle.HeaderTemplate>
                </GroupStyle>
              </ListBox.GroupStyle>
              <ListBox.ItemContainerStyle>
                <Style TargetType="ListBoxItem">
                  <Setter Property="Padding" Value="0"/>
                  <Setter Property="Margin" Value="0,0,6,8"/>
                  <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                  <Setter Property="ToolTip" Value="{Binding Tip}"/>
                  <Setter Property="Template">
                    <Setter.Value>
                      <ControlTemplate TargetType="ListBoxItem">
                        <Border x:Name="b" Background="{Binding RowBg}" BorderBrush="$($Pal.Line)" BorderThickness="1.5" CornerRadius="14" Padding="14,9" Cursor="Hand">
                          <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                          <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="$($Pal.Accent)"/></Trigger>
                          <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#FFFFFF"/><Setter TargetName="b" Property="BorderThickness" Value="2"/></Trigger>
                        </ControlTemplate.Triggers>
                      </ControlTemplate>
                    </Setter.Value>
                  </Setter>
                </Style>
              </ListBox.ItemContainerStyle>
              <ListBox.ItemTemplate>
                <DataTemplate>
                  <DockPanel>
                    <Image DockPanel.Dock="Left" Source="{Binding Art}" Width="64" Height="38" Margin="0,0,16,0" VerticalAlignment="Center"/>
                    <Border DockPanel.Dock="Right" CornerRadius="8" Padding="8,2" Background="{Binding RibBg}" VerticalAlignment="Center" Margin="10,0,0,0" MinWidth="70">
                      <TextBlock Text="{Binding RibText}" Foreground="{Binding RibFg}" FontSize="10" FontWeight="Bold" HorizontalAlignment="Center"/>
                    </Border>
                    <TextBlock DockPanel.Dock="Right" Text="{Binding HereText}" Foreground="{Binding HereFg}" FontSize="11.5" FontWeight="SemiBold" VerticalAlignment="Center" Width="70" TextAlignment="Right"/>
                    <StackPanel DockPanel.Dock="Right" VerticalAlignment="Center" Margin="10,0,0,0" Width="104" ToolTip="{Binding DateFull}">
                      <TextBlock Text="{Binding DateDay}" Foreground="$($Pal.Text)" FontSize="12" FontWeight="SemiBold"/>
                      <TextBlock Text="{Binding DateAgo}" Foreground="$($Pal.Faint)" FontSize="10.5"/>
                    </StackPanel>
                    <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center" Margin="10,0,0,0" Width="74">
                      <Border Width="22" Height="22" CornerRadius="11" Background="{Binding OwnerBg}">
                        <TextBlock Text="{Binding OwnerInit}" Foreground="White" FontSize="11" FontWeight="Bold" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      </Border>
                      <TextBlock Text="{Binding Owner}" Foreground="$($Pal.Dim)" FontSize="11.5" Margin="6,0,0,0" VerticalAlignment="Center"/>
                    </StackPanel>
                    <StackPanel VerticalAlignment="Center">
                      <TextBlock FontSize="10" FontWeight="Bold">
                        <Run Text="{Binding AtkText, Mode=OneWay}" Foreground="{Binding AtkFg, Mode=OneWay}"/><Run Text="{Binding RepText, Mode=OneWay}" Foreground="$($Pal.Amber)"/>
                      </TextBlock>
                      <WrapPanel Margin="0,1,0,0">
                        <TextBlock Text="{Binding Topo}" FontSize="15" FontWeight="Bold" Foreground="$($Pal.Text)" VerticalAlignment="Center" Margin="0,0,10,0"/>
                        <Border CornerRadius="8" Padding="7,1" Background="{Binding LocBg}" Margin="0,0,5,0" VerticalAlignment="Center">
                          <TextBlock Text="{Binding LocText}" Foreground="{Binding LocFg}" FontSize="11" FontWeight="SemiBold"/>
                        </Border>
                        <Border CornerRadius="8" Padding="7,1" Background="{Binding ScnBg}" VerticalAlignment="Center">
                          <TextBlock Text="{Binding ScnText}" Foreground="{Binding ScnFg}" FontSize="11" FontWeight="SemiBold"/>
                        </Border>
                      </WrapPanel>
                    </StackPanel>
                  </DockPanel>
                </DataTemplate>
              </ListBox.ItemTemplate>
            </ListBox>
            <!-- the selected preset -->
            <Border Grid.Column="1" Style="{StaticResource Card}" Padding="0">
              <DockPanel>
                <Border x:Name="DetHero" DockPanel.Dock="Top" CornerRadius="16,16,0,0" Padding="18,14" Background="$($Pal.Card2)">
                  <DockPanel>
                    <Border DockPanel.Dock="Right" Width="132" Height="84" CornerRadius="12" Background="#26000000" Margin="10,0,0,0" VerticalAlignment="Top">
                      <ContentControl x:Name="DetArt" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel>
                      <TextBlock x:Name="DetKicker" Text="PRESET" FontSize="10" FontWeight="Bold" Foreground="#CCFFFFFF"/>
                      <TextBlock x:Name="DetTitle" FontSize="20" FontWeight="Bold" Foreground="White" TextWrapping="Wrap" Text="Pick a preset"/>
                      <TextBlock x:Name="DetFile" Foreground="#DDFFFFFF" FontSize="11" TextWrapping="Wrap" Margin="0,2,0,0" Text="click one on the left to look inside - double-click to use it straight away"/>
                      <WrapPanel x:Name="DetChips" Margin="0,8,0,0"/>
                    </StackPanel>
                  </DockPanel>
                </Border>
                <StackPanel DockPanel.Dock="Bottom" Margin="18,10,18,16">
                  <Button x:Name="StartCapture" Style="{StaticResource Primary}" Content="&#x25B6;  Use this preset" ToolTip="Opens it on the Live run page - nothing compiles or flashes until you press 1 or 2 there" IsEnabled="False" Padding="20,11" Margin="0,0,0,8"/>
                  <Button x:Name="FixPorts" Style="{StaticResource Cool}" Content="&#x21C4;  Use the ports the boards are on now" IsEnabled="False" Margin="0,0,0,8" Visibility="Collapsed"
                          ToolTip="Matches every board by its MAC to the COM port it is plugged into right now and saves that into the preset."/>
                  <UniformGrid Columns="4">
                    <Button x:Name="PresetEdit" Content="Edit" IsEnabled="False" Margin="0,0,4,0" Padding="8,7"/>
                    <Button x:Name="PresetCopy" Content="Copy" IsEnabled="False" Margin="2,0,2,0" Padding="8,7"/>
                    <Button x:Name="OpenPresetFile" Content="File" ToolTip="Open the preset file in Notepad" IsEnabled="False" Margin="2,0,2,0" Padding="8,7"/>
                    <Button x:Name="PresetDelete" Style="{StaticResource Danger}" Content="Delete" IsEnabled="False" Margin="4,0,0,0" Padding="8,7"/>
                  </UniformGrid>
                </StackPanel>
                <StackPanel DockPanel.Dock="Top" Margin="18,14,18,0">
                  <DockPanel Margin="0,0,0,4">
                    <TextBlock x:Name="DetReadyNum" DockPanel.Dock="Right" FontWeight="Bold" Foreground="$($Pal.Green)"/>
                    <TextBlock Style="{StaticResource Label}" Text="BOARDS  (flashed in this order - root last)"/>
                  </DockPanel>
                  <ProgressBar x:Name="DetReady" Height="6" Margin="0,0,0,6"/>
                  <TextBlock x:Name="DetPorts" Margin="0,0,0,8" TextWrapping="Wrap"/>
                </StackPanel>
                <TextBlock x:Name="DetNote" DockPanel.Dock="Bottom" Foreground="$($Pal.Dim)" FontSize="12" Margin="18,6,18,0" TextWrapping="Wrap"/>
                <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="12,0,12,0">
                  <StackPanel x:Name="DetBoards"/>
                </ScrollViewer>
              </DockPanel>
            </Border>
          </Grid>
        </DockPanel>
      </TabItem>

      <!-- VERIFY & ANALYSE (oct. 17 2026 redesign: run list + files / result / plots) -->
      <TabItem>
        <DockPanel>
          <DockPanel DockPanel.Dock="Top">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Top">
              <Button x:Name="AnaVerifyAll" Content="Check all verdicts" ToolTip="Runs the (read-only) 3-sigma verifier on every analysed attack run, a few seconds each, so every run in the list shows CONFIRMED / SETUP INVALID / NOT CONFIRMED"/>
              <Button x:Name="AnaAllNew" Style="{StaticResource Cool}" Content="Analyse everything new" ToolTip="Trim + analyse + verify every run whose data is newer than its analysis (or never analysed), one after the other"/>
              <Button x:Name="AnaAllRe" Content="Re-analyse everything" ToolTip="Trim + analyse + verify EVERY captured run again, one after the other - use it after the analysis code changes (e.g. D-25, oct. 19 2026). Long: every run's tables and plots are rebuilt"/>
              <Button x:Name="AnaRefresh" Content="Refresh"/>
            </StackPanel>
            <StackPanel>
              <TextBlock Style="{StaticResource H1}" Text="Verify &amp; analyse"/>
              <TextBlock x:Name="AnaSub" Style="{StaticResource Sub}" Text="Pick a captured run on the left. Analyse + verify runs here (trim -> features -> EDA -> 3-sigma verifier); the result, every board's file and the plots show on the right."/>
            </StackPanel>
          </DockPanel>
          <Grid>
            <Grid.ColumnDefinitions><ColumnDefinition Width="390"/><ColumnDefinition Width="*"/></Grid.ColumnDefinitions>
            <!-- the runs -->
            <Border Grid.Column="0" Style="{StaticResource Card}" Padding="10" Margin="0,0,14,0">
              <DockPanel>
                <Grid DockPanel.Dock="Top" Margin="0,0,0,8">
                  <TextBox x:Name="AnaSearch" Margin="0" Padding="30,6,8,6" ToolTip="Type any part: worm tree dlsu, highload, redo..."/>
                  <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" Foreground="$($Pal.Faint)" VerticalAlignment="Center" Margin="11,0,0,0" IsHitTestVisible="False"/>
                  <TextBlock x:Name="AnaSearchHint" Text="Search runs..." Foreground="$($Pal.Faint)" VerticalAlignment="Center" Margin="31,0,0,0" IsHitTestVisible="False"/>
                </Grid>
                <Grid DockPanel.Dock="Top" Margin="0,0,0,8">
                  <Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="8"/><ColumnDefinition/></Grid.ColumnDefinitions>
                  <Grid.RowDefinitions><RowDefinition/><RowDefinition Height="6"/><RowDefinition/></Grid.RowDefinitions>
                  <ComboBox x:Name="AnaFAtk" Grid.Row="0" Grid.Column="0" Margin="0" ToolTip="Attack"/>
                  <ComboBox x:Name="AnaFTopo" Grid.Row="0" Grid.Column="2" Margin="0" ToolTip="Topology"/>
                  <ComboBox x:Name="AnaFLoc" Grid.Row="2" Grid.Column="0" Margin="0" ToolTip="Location"/>
                  <ComboBox x:Name="AnaFScn" Grid.Row="2" Grid.Column="2" Margin="0" ToolTip="Scenario"/>
                </Grid>
                <WrapPanel DockPanel.Dock="Top" Margin="0,0,0,8">
                  <RadioButton x:Name="AnaFAll" Style="{StaticResource Chip}" GroupName="anaf" Content="all" IsChecked="True"/>
                  <RadioButton x:Name="AnaFTodo" Style="{StaticResource Chip}" GroupName="anaf" Content="needs analysis"/>
                  <RadioButton x:Name="AnaFBad" Style="{StaticResource Chip}" GroupName="anaf" Content="needs a recapture / redo"/>
                  <Button x:Name="AnaFClear" Content="clear filters" Padding="10,4" FontSize="11"/>
                </WrapPanel>
                <TextBlock x:Name="AnaCount" DockPanel.Dock="Top" Foreground="$($Pal.Faint)" FontSize="11" Margin="2,0,0,6"/>
                <ListBox x:Name="CellPick" Background="Transparent" BorderThickness="0" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
                  <ListBox.ItemContainerStyle>
                    <Style TargetType="ListBoxItem">
                      <Setter Property="Padding" Value="0"/>
                      <Setter Property="Margin" Value="0,0,0,6"/>
                      <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
                      <Setter Property="Template">
                        <Setter.Value>
                          <ControlTemplate TargetType="ListBoxItem">
                            <Border x:Name="b" Background="$($Pal.Card2)" BorderBrush="$($Pal.Line)" BorderThickness="1" CornerRadius="10" Padding="10,7" Cursor="Hand">
                              <ContentPresenter/>
                            </Border>
                            <ControlTemplate.Triggers>
                              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="$($Pal.Accent)"/></Trigger>
                              <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#FFFFFF"/><Setter TargetName="b" Property="BorderThickness" Value="2"/></Trigger>
                            </ControlTemplate.Triggers>
                          </ControlTemplate>
                        </Setter.Value>
                      </Setter>
                    </Style>
                  </ListBox.ItemContainerStyle>
                  <ListBox.ItemTemplate>
                    <DataTemplate>
                      <DockPanel>
                      <Image DockPanel.Dock="Left" Source="{Binding Art}" Width="40" Height="26" Margin="0,0,10,0" VerticalAlignment="Center"/>
                      <StackPanel>
                        <DockPanel>
                          <Border DockPanel.Dock="Right" CornerRadius="7" Background="{Binding BadgeBg}" Padding="7,1" VerticalAlignment="Center">
                            <TextBlock Text="{Binding Badge}" Foreground="{Binding BadgeFg}" FontSize="10.5" FontWeight="Bold"/>
                          </Border>
                          <TextBlock FontSize="12.5" TextTrimming="CharacterEllipsis">
                            <Run Text="{Binding Attack, Mode=OneWay}" Foreground="{Binding AtkFg, Mode=OneWay}" FontWeight="Bold"/><Run Text="{Binding Rest, Mode=OneWay}" Foreground="$($Pal.Text)"/>
                          </TextBlock>
                        </DockPanel>
                        <TextBlock Text="{Binding Sub}" Foreground="$($Pal.Faint)" FontSize="11" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
                      </StackPanel>
                      </DockPanel>
                    </DataTemplate>
                  </ListBox.ItemTemplate>
                </ListBox>
              </DockPanel>
            </Border>
            <!-- the selected run -->
            <DockPanel Grid.Column="1">
              <Border DockPanel.Dock="Top" CornerRadius="16" Padding="18,12" Margin="0,0,0,10" Background="$($Pal.Card2)" BorderBrush="{StaticResource GradCool}" BorderThickness="2">
                <DockPanel>
                  <WrapPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
                    <TextBlock Text="DATA" Foreground="$($Pal.Dim)" FontSize="10.5" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,8,6"/>
                    <RadioButton x:Name="AnaUseTrim" Style="{StaticResource Chip}" GroupName="anause" Content="trimmed (recommended)" IsChecked="True"
                                 ToolTip="trim_run.py first keeps only the experiment session of each file (drops boot / idle / export sessions), then analyses that - the normal pipeline"/>
                    <RadioButton x:Name="AnaUseRaw" Style="{StaticResource Chip}" GroupName="anause" Content="raw (no trim)"
                                 ToolTip="Analyses the export files exactly as imported (analyze.ps1 -SkipTrim) - to compare, or when trimming picks the wrong session. Writes the same analysis folder."/>
                  </WrapPanel>
                  <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,4,0,0">
                    <Button x:Name="DoAnalyze" Style="{StaticResource Primary}" Content="&#x25B6;  Analyse + verify" FontWeight="Bold" Padding="16,8" Margin="0,0,8,0"
                            ToolTip="analyze.ps1 -Verify: trim -> preprocess -> features -> EDA -> integrity + topology + 3-sigma verifier. Output streams in the activity pane."/>
                    <Button x:Name="DoVerify" Content="Verify only" Margin="0,0,8,0"/>
                    <Button x:Name="DoTopology" Content="Topology" Margin="0,0,8,0"/>
                    <Button x:Name="DoOpenCell" Content="Open folder" Margin="0"/>
                  </StackPanel>
                  <StackPanel>
                    <TextBlock Text="SELECTED RUN" Foreground="$($Pal.Faint)" FontSize="10.5" FontWeight="SemiBold"/>
                    <TextBlock x:Name="AnaTitle" Text="-" FontSize="20" FontWeight="Bold" Foreground="White" TextWrapping="Wrap"/>
                    <TextBlock x:Name="AnaInfo" Text="" Foreground="$($Pal.Dim)" FontSize="12" TextWrapping="Wrap"/>
                  </StackPanel>
                </DockPanel>
              </Border>
              <Border x:Name="Verdict" DockPanel.Dock="Top" CornerRadius="14" Padding="16,10" Margin="0,0,0,10" Visibility="Collapsed" Background="$($Pal.Card)">
                <StackPanel Orientation="Horizontal">
                  <Border Width="40" Height="40" CornerRadius="20" Background="#33FFFFFF">
                    <TextBlock x:Name="VerdictIcon" Text="&#xE73E;" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                  </Border>
                  <StackPanel Margin="14,0,0,0" VerticalAlignment="Center">
                    <TextBlock x:Name="VerdictTitle" FontSize="18" FontWeight="Bold" Foreground="White"/>
                    <TextBlock x:Name="VerdictText" Foreground="#E5E7FF" TextWrapping="Wrap" MaxWidth="900"/>
                  </StackPanel>
                </StackPanel>
              </Border>
              <TabControl x:Name="AnaTabs" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource SubTab}">
                <TabItem Header="  Result  ">
                  <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,8,0,0">
                    <StackPanel x:Name="AnaResult">
                      <TextBlock x:Name="AnaResultEmpty" Text="No result yet for this run - press 'Analyse + verify' (or 'Verify only' if it was analysed before)." Foreground="$($Pal.Dim)" Margin="4,10,0,0" TextWrapping="Wrap"/>
                    </StackPanel>
                  </ScrollViewer>
                </TabItem>
                <TabItem Header="  Files  ">
                  <ScrollViewer VerticalScrollBarVisibility="Auto" Margin="0,8,0,0">
                    <StackPanel>
                      <TextBlock x:Name="AnaFilesNote" Foreground="$($Pal.Dim)" FontSize="12" TextWrapping="Wrap" Margin="2,0,0,8"/>
                      <WrapPanel Margin="2,0,0,8">
                        <Border Width="12" Height="12" CornerRadius="3" Background="#4B5075" Margin="0,0,5,0"/><TextBlock Text="stabilise" Foreground="$($Pal.Dim)" FontSize="11" Margin="0,0,12,0"/>
                        <Border Width="12" Height="12" CornerRadius="3" Background="$($Pal.Green)" Margin="0,0,5,0"/><TextBlock Text="baseline" Foreground="$($Pal.Dim)" FontSize="11" Margin="0,0,12,0"/>
                        <Border Width="12" Height="12" CornerRadius="3" Background="$($Pal.Pink)" Margin="0,0,5,0"/><TextBlock Text="attack" Foreground="$($Pal.Dim)" FontSize="11" Margin="0,0,12,0"/>
                        <Border Width="12" Height="12" CornerRadius="3" Background="$($Pal.Cyan)" Margin="0,0,5,0"/><TextBlock Text="cooldown" Foreground="$($Pal.Dim)" FontSize="11" Margin="0,0,12,0"/>
                        <Border Width="12" Height="12" CornerRadius="3" Background="$($Pal.Purple)" Margin="0,0,5,0"/><TextBlock Text="terminate" Foreground="$($Pal.Dim)" FontSize="11"/>
                      </WrapPanel>
                      <StackPanel x:Name="AnaFiles"/>
                    </StackPanel>
                  </ScrollViewer>
                </TabItem>
                <TabItem Header="  Plots  ">
                  <DockPanel Margin="0,8,0,0">
                    <TextBlock x:Name="AnaPlotsNote" DockPanel.Dock="Top" Foreground="$($Pal.Dim)" FontSize="12" Margin="2,0,0,8" TextWrapping="Wrap"/>
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                      <WrapPanel x:Name="AnaPlots"/>
                    </ScrollViewer>
                  </DockPanel>
                </TabItem>
                <TabItem Header="  Full report  ">
                  <Border Background="#0D0E17" BorderBrush="$($Pal.Line)" BorderThickness="1" CornerRadius="14" Margin="0,8,0,0">
                    <RichTextBox x:Name="VerifyOut" Background="Transparent" Foreground="$($Pal.Text)" BorderThickness="0" Padding="12"
                                 FontFamily="Cascadia Mono, Consolas" FontSize="12" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                                 HorizontalScrollBarVisibility="Auto"/>
                  </Border>
                </TabItem>
              </TabControl>
            </DockPanel>
          </Grid>
        </DockPanel>
      </TabItem>

      <!-- CAMPAIGN -->
      <TabItem>
        <DockPanel>
          <DockPanel DockPanel.Dock="Top">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Top">
              <Button x:Name="LoadRedo" Style="{StaticResource Cool}" Content="&#x21BB;  Re-check the redo list"/>
              <Button x:Name="CampRefresh" Content="Refresh"/>
              <Button x:Name="CampPlan" Content="&#x2699;  Plan settings"
                      ToolTip="Tick / untick scenarios, locations, topologies, attacks to change what the campaign plans (gui\PlanSettings.ps1)"/>
            </StackPanel>
            <StackPanel>
              <TextBlock Style="{StaticResource H1}" Text="Campaign"/>
              <TextBlock x:Name="CampSub" Style="{StaticResource Sub}" Text="Every planned run at a glance - click a tile to see why, and capture it in one click."/>
            </StackPanel>
          </DockPanel>
          <WrapPanel x:Name="CampStats" DockPanel.Dock="Top" Margin="0,0,0,10"/>
          <TabControl x:Name="CampTabs" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource SubTab}">
            <TabItem Header="  &#x25A6;  Checklist grid  ">
              <Grid Margin="0,10,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="*" MinWidth="380"/><ColumnDefinition Width="10"/><ColumnDefinition Width="400" MinWidth="320"/></Grid.ColumnDefinitions>
                <GridSplitter Grid.Column="1" Width="10" HorizontalAlignment="Stretch" Background="Transparent" Cursor="SizeWE" ToolTip="Drag to make the run panel wider or narrower"/>
                <DockPanel Grid.Column="0" Margin="0,0,4,0">
                  <WrapPanel DockPanel.Dock="Top">
                    <TextBlock Text="SHOW" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="0,0,10,8"/>
                    <RadioButton x:Name="CfAll"     Style="{StaticResource Chip}" GroupName="cf" Content="Everything" IsChecked="True"/>
                    <RadioButton x:Name="CfTodo"    Style="{StaticResource Chip}" GroupName="cf" Content="To do"/>
                    <RadioButton x:Name="CfRedo"    Style="{StaticResource Chip}" GroupName="cf" Content="Needs redo / check"/>
                    <RadioButton x:Name="CfDone"    Style="{StaticResource Chip}" GroupName="cf" Content="Done"/>
                    <TextBlock Text="WHERE" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="14,0,10,8"/>
                    <RadioButton x:Name="ClAll"     Style="{StaticResource Chip}" GroupName="cl" Content="All locations" IsChecked="True"/>
                    <RadioButton x:Name="ClG402"    Style="{StaticResource Chip}" GroupName="cl" Content="G402" Tag="G402"/>
                    <RadioButton x:Name="ClDlsu"    Style="{StaticResource Chip}" GroupName="cl" Content="DLSU Library" Tag="DLSU_Library"/>
                    <RadioButton x:Name="ClYuch"    Style="{StaticResource Chip}" GroupName="cl" Content="Yuchengco" Tag="Yuchengco"/>
                  </WrapPanel>
                  <WrapPanel x:Name="CampLegend" DockPanel.Dock="Bottom" Margin="0,10,0,0"/>
                  <Border Style="{StaticResource Card}" Padding="16">
                    <ScrollViewer VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto">
                      <Grid x:Name="CampMatrix" HorizontalAlignment="Left"/>
                    </ScrollViewer>
                  </Border>
                </DockPanel>
                <Border Grid.Column="2" Style="{StaticResource Card}">
                  <DockPanel>
                    <StackPanel DockPanel.Dock="Bottom" Margin="0,12,0,0">
                      <Button x:Name="CampCapture" Style="{StaticResource Primary}" Content="&#x25B6;  Capture this run" IsEnabled="False" Margin="0,0,0,8" Padding="16,11"/>
                      <UniformGrid Columns="2">
                        <Button x:Name="CampVerify" Content="Verify" IsEnabled="False" Margin="0,0,4,8"/>
                        <Button x:Name="CampAnalyse" Content="Analyse" IsEnabled="False" Margin="4,0,0,8"/>
                        <Button x:Name="CampOpen" Content="Open folder" IsEnabled="False" Margin="0,0,4,0"/>
                        <Button x:Name="CampNext" Content="Jump to next" Margin="4,0,0,0"/>
                      </UniformGrid>
                    </StackPanel>
                    <StackPanel DockPanel.Dock="Top">
                      <TextBlock Style="{StaticResource Label}" Text="SELECTED RUN"/>
                      <TextBlock x:Name="CampDetTitle" FontSize="18" FontWeight="Bold" TextWrapping="Wrap" Text="Click a tile"/>
                      <TextBlock x:Name="CampDetPlace" Foreground="$($Pal.Dim)" TextWrapping="Wrap" Margin="0,2,0,10"/>
                      <Border x:Name="CampDetBadge" HorizontalAlignment="Left" CornerRadius="10" Padding="10,3" Background="$($Pal.Line)" Margin="0,0,0,12">
                        <TextBlock x:Name="CampDetState" FontWeight="SemiBold" FontSize="12" Text="-"/>
                      </Border>
                    </StackPanel>
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                      <StackPanel x:Name="CampDetBody"/>
                    </ScrollViewer>
                  </DockPanel>
                </Border>
              </Grid>
            </TabItem>
            <TabItem Header="  &#x2630;  Table  ">
              <DockPanel Margin="0,10,0,0">
                <StackPanel DockPanel.Dock="Top" Orientation="Horizontal">
                  <Button x:Name="LoadPlan" Content="Show the checklist"/>
                  <ComboBox x:Name="PlanFilter" Width="170"/>
                  <TextBlock Text="or press Re-check (top right) for the redo list with every reason" Foreground="$($Pal.Faint)" VerticalAlignment="Center" Margin="6,0,0,8"/>
                </StackPanel>
                <Grid>
                  <Grid.RowDefinitions><RowDefinition Height="3*"/><RowDefinition Height="2*"/></Grid.RowDefinitions>
                  <DataGrid x:Name="CampaignGrid" Grid.Row="0">
                    <DataGrid.Columns>
                      <DataGridTextColumn Header="STATUS" Binding="{Binding Status}" Width="80">
                        <DataGridTextColumn.ElementStyle>
                          <Style TargetType="TextBlock">
                            <Setter Property="FontWeight" Value="SemiBold"/>
                            <Style.Triggers>
                              <DataTrigger Binding="{Binding Status}" Value="REDO"><Setter Property="Foreground" Value="$($Pal.Red)"/></DataTrigger>
                              <DataTrigger Binding="{Binding Status}" Value="CHECK"><Setter Property="Foreground" Value="$($Pal.Amber)"/></DataTrigger>
                              <DataTrigger Binding="{Binding Status}" Value="OK"><Setter Property="Foreground" Value="$($Pal.Green)"/></DataTrigger>
                              <DataTrigger Binding="{Binding Status}" Value="done"><Setter Property="Foreground" Value="$($Pal.Green)"/></DataTrigger>
                              <DataTrigger Binding="{Binding Status}" Value="partial"><Setter Property="Foreground" Value="$($Pal.Cyan)"/></DataTrigger>
                              <DataTrigger Binding="{Binding Status}" Value="todo"><Setter Property="Foreground" Value="$($Pal.Faint)"/></DataTrigger>
                            </Style.Triggers>
                          </Style>
                        </DataGridTextColumn.ElementStyle>
                      </DataGridTextColumn>
                      <DataGridTextColumn Header="LOCATION" Binding="{Binding Location}" Width="110"/>
                      <DataGridTextColumn Header="ATTACK" Binding="{Binding Attack}" Width="90"/>
                      <DataGridTextColumn Header="TOPOLOGY" Binding="{Binding Topology}" Width="100"/>
                      <DataGridTextColumn Header="SCENARIO" Binding="{Binding Scenario}" Width="90"/>
                      <DataGridTextColumn Header="LAST CAPTURE" Binding="{Binding When}" Width="130">
                        <DataGridTextColumn.ElementStyle><Style TargetType="TextBlock"><Setter Property="Foreground" Value="$($Pal.Dim)"/></Style></DataGridTextColumn.ElementStyle>
                      </DataGridTextColumn>
                      <DataGridTextColumn Header="WHY" Binding="{Binding Why}" Width="*"/>
                    </DataGrid.Columns>
                  </DataGrid>
                  <Border Grid.Row="1" Style="{StaticResource Card}" Padding="16" Margin="0,12,0,0">
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                      <TextBlock x:Name="CampaignDetail" TextWrapping="Wrap" Foreground="$($Pal.Text)" Text="Select a row to see every reason and what to do."/>
                    </ScrollViewer>
                  </Border>
                </Grid>
              </DockPanel>
            </TabItem>
          </TabControl>
        </DockPanel>
      </TabItem>
      <!-- BOARDS (phase 2) -->
      <TabItem>
        <DockPanel>
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Style="{StaticResource H1}" Text="Boards"/>
            <TextBlock Style="{StaticResource Sub}" Text="Identify the boards plugged in, set their location, wipe one, clean its SD card, keep the member list - all from here. Output appears in the activity pane below."/>
          </StackPanel>
          <TabControl x:Name="BoardTabs" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource SubTab}">
            <TabItem Header="  Plugged-in boards  ">
              <Grid Margin="0,10,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="3*"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
                <DockPanel Grid.Column="0" Margin="0,0,14,0">
                  <StackPanel DockPanel.Dock="Top" Orientation="Horizontal">
                    <Button x:Name="PortsRefresh" Content="Rescan ports"/>
                    <Button x:Name="IdentifyAll" Style="{StaticResource Primary}" Content="Identify all (read MACs)"/>
                    <TextBlock Text="reads each board ~5 s and briefly resets it - never during a capture" Foreground="$($Pal.Faint)" FontSize="11" VerticalAlignment="Center" TextWrapping="Wrap" Width="240"/>
                  </StackPanel>
                  <DataGrid x:Name="PortGrid" RowHeight="36">
                    <DataGrid.Columns>
                      <DataGridTemplateColumn Header="" Width="26">
                        <DataGridTemplateColumn.CellTemplate><DataTemplate>
                          <Ellipse Width="10" Height="10" Fill="{Binding Dot}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                        </DataTemplate></DataGridTemplateColumn.CellTemplate>
                      </DataGridTemplateColumn>
                      <DataGridTextColumn Header="port" Binding="{Binding Port}" Width="70">
                        <DataGridTextColumn.ElementStyle><Style TargetType="TextBlock"><Setter Property="FontWeight" Value="Bold"/></Style></DataGridTextColumn.ElementStyle>
                      </DataGridTextColumn>
                      <!-- MAC: big + monospaced, the last 2 bytes (what tells boards apart) in colour -->
                      <DataGridTemplateColumn Header="MAC   (last 2 bytes = which board)" Width="215">
                        <DataGridTemplateColumn.CellTemplate><DataTemplate>
                          <TextBlock FontFamily="Consolas" FontSize="13.5" VerticalAlignment="Center">
                            <Run Text="{Binding MacHead, Mode=OneWay}" Foreground="$($Pal.Text)"/><Run Text="{Binding MacTail, Mode=OneWay}" Foreground="$($Pal.Cyan)" FontWeight="Bold"/>
                          </TextBlock>
                        </DataTemplate></DataGridTemplateColumn.CellTemplate>
                      </DataGridTemplateColumn>
                      <DataGridTextColumn Header="member board" Binding="{Binding Nick}" Width="150">
                        <DataGridTextColumn.ElementStyle><Style TargetType="TextBlock"><Setter Property="Foreground" Value="$($Pal.Amber)"/><Setter Property="FontWeight" Value="SemiBold"/></Style></DataGridTextColumn.ElementStyle>
                      </DataGridTextColumn>
                      <DataGridTextColumn Header="device" Binding="{Binding Description}" Width="*">
                        <DataGridTextColumn.ElementStyle><Style TargetType="TextBlock"><Setter Property="Foreground" Value="$($Pal.Dim)"/></Style></DataGridTextColumn.ElementStyle>
                      </DataGridTextColumn>
                    </DataGrid.Columns>
                  </DataGrid>
                </DockPanel>
                <Border Grid.Column="1" Style="{StaticResource Card}" Padding="16">
                  <ScrollViewer VerticalScrollBarVisibility="Auto">
                    <StackPanel>
                      <Border CornerRadius="14" Padding="14,12" Margin="0,0,0,14" Background="{StaticResource GradCool}">
                        <DockPanel>
                          <Border DockPanel.Dock="Left" Width="44" Height="44" CornerRadius="22" Background="#33FFFFFF" Margin="0,0,12,0" VerticalAlignment="Top">
                            <TextBlock Text="&#xE88E;" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                          </Border>
                          <StackPanel>
                            <TextBlock Text="SELECTED BOARD" FontSize="10" FontWeight="Bold" Foreground="#DDFFFFFF"/>
                            <TextBlock x:Name="SelBoard" FontSize="17" FontWeight="Bold" Foreground="White" TextWrapping="Wrap" Text="Select a port on the left"/>
                            <ContentControl x:Name="SelMac" Margin="0,6,0,0" HorizontalAlignment="Left"/>
                          </StackPanel>
                        </DockPanel>
                      </Border>
                      <Border Background="$($Pal.Card2)" CornerRadius="12" Padding="12,10" Margin="0,0,0,10" BorderThickness="3,0,0,0" BorderBrush="$($Pal.Cyan)">
                        <StackPanel>
                          <TextBlock Style="{StaticResource Label}" Foreground="$($Pal.Cyan)" TextWrapping="Wrap" Text="&#x25C9;  LOCATION  (location.txt on its SD card - the board must be running)"/>
                          <StackPanel Orientation="Horizontal" Margin="0,4,0,0">
                            <ComboBox x:Name="LocPick" Width="140"/>
                            <Button x:Name="LocRead" Content="Read"/>
                            <Button x:Name="LocWrite" Content="Write"/>
                          </StackPanel>
                        </StackPanel>
                      </Border>
                      <Border Background="$($Pal.Card2)" CornerRadius="12" Padding="12,10" Margin="0,0,0,10" BorderThickness="3,0,0,0" BorderBrush="$($Pal.Amber)">
                        <StackPanel>
                          <TextBlock Style="{StaticResource Label}" Foreground="$($Pal.Amber)" Text="&#x25A4;  DELETE A FOLDER FROM ITS SD CARD  (permanent)"/>
                          <WrapPanel Margin="0,4,0,0">
                            <ComboBox x:Name="SdAttack" Width="100"/>
                            <ComboBox x:Name="SdTopology" Width="100"/>
                            <ComboBox x:Name="SdLocation" Width="120"/>
                            <Button x:Name="SdDelete" Style="{StaticResource Danger}" Content="Delete folder"/>
                          </WrapPanel>
                        </StackPanel>
                      </Border>
                      <Border Background="$($Pal.Card2)" CornerRadius="12" Padding="12,10" Margin="0,0,0,10" BorderThickness="3,0,0,0" BorderBrush="$($Pal.Red)">
                        <StackPanel>
                          <TextBlock Style="{StaticResource Label}" Foreground="$($Pal.Red)" Text="&#x26A0;  WIPE  (full chip erase - the board ends up blank)"/>
                          <Button x:Name="WipeBoard" Style="{StaticResource Danger}" Content="Wipe this board" HorizontalAlignment="Left" Margin="0,4,0,0"/>
                        </StackPanel>
                      </Border>
                    </StackPanel>
                  </ScrollViewer>
                </Border>
              </Grid>
            </TabItem>
            <TabItem Header="  Member board list  ">
              <DockPanel Margin="0,10,0,0">
                <StackPanel DockPanel.Dock="Top" Orientation="Horizontal">
                  <Button x:Name="MemAdd" Content="+ Add board"/>
                  <Button x:Name="MemRemove" Content="Remove selected"/>
                  <Button x:Name="MemSave" Style="{StaticResource Primary}" Content="Save member_boards.json"/>
                  <Button x:Name="MemReload" Content="Reload"/>
                  <TextBlock Text="double-click a cell to edit  |  MAC = first:last byte is enough (e.g. B0:18)" Foreground="$($Pal.Faint)" FontSize="11" VerticalAlignment="Center"/>
                </StackPanel>
                <DataGrid x:Name="MemberGrid" IsReadOnly="False" CanUserAddRows="False"/>
              </DockPanel>
            </TabItem>
            <TabItem Header="  Firmware tests  ">
              <ScrollViewer VerticalScrollBarVisibility="Auto">
                <StackPanel Margin="0,14,0,0">
                  <TextBlock Foreground="$($Pal.Dim)" TextWrapping="Wrap" Margin="0,0,0,14" Text="Both build + flash test firmware and show the result right here in the activity pane - pick the boards by their MAC, nothing to type. Needs the GUI started from the ESP-IDF PowerShell."/>
                  <WrapPanel>
                    <Border Style="{StaticResource Card}" Width="440" Margin="0,0,14,14">
                      <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                          <TextBlock Text="&#xE9D9;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="$($Pal.Cyan)" VerticalAlignment="Center" Margin="0,0,10,0"/>
                          <TextBlock Text="Firmware self-test" FontSize="17" FontWeight="SemiBold"/>
                        </StackPanel>
                        <TextBlock Foreground="$($Pal.Dim)" TextWrapping="Wrap" Margin="0,0,0,12" Text="Flashes the plain baseline firmware to ONE board and proves its SD card + location commands answer. No capture, nothing exported."/>
                        <TextBlock Text="BOARD" Style="{StaticResource Label}"/>
                        <ComboBox x:Name="TSelfPort" ItemTemplate="{StaticResource TextItem}" Margin="0,0,0,10"/>
                        <TextBlock Text="FLASH AS" Style="{StaticResource Label}"/>
                        <WrapPanel>
                          <RadioButton x:Name="TSelfRoot" Style="{StaticResource Chip}" GroupName="tselfrole" Content="root (recommended - boots alone)" IsChecked="True"/>
                          <RadioButton x:Name="TSelfChild" Style="{StaticResource Chip}" GroupName="tselfrole" Content="child (needs a root on)"/>
                        </WrapPanel>
                        <TextBlock Text="ALSO TEST WRITING A LOCATION  (the card's old value is put back)" Style="{StaticResource Label}" Margin="0,4,0,4"/>
                        <ComboBox x:Name="TSelfLoc" Margin="0,0,0,12"/>
                        <Button x:Name="TSelfTest" Style="{StaticResource Primary}" Content="Build, flash + test  &#x2192;" HorizontalAlignment="Left" Padding="16,8"/>
                      </StackPanel>
                    </Border>
                    <Border Style="{StaticResource Card}" Width="440" Margin="0,0,14,14">
                      <StackPanel>
                        <StackPanel Orientation="Horizontal" Margin="0,0,0,6">
                          <TextBlock Text="&#xE71B;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="$($Pal.Purple)" VerticalAlignment="Center" Margin="0,0,10,0"/>
                          <TextBlock Text="Wormhole UART cable test" FontSize="17" FontWeight="SemiBold"/>
                        </StackPanel>
                        <TextBlock Foreground="$($Pal.Dim)" TextWrapping="Wrap" Margin="0,0,0,12" Text="Flashes uart_link_test to the two tunnel boards and checks the jumper wire BOTH ways (GPIO17 -> GPIO16 crossed + GND). The next wormhole capture flashes the real firmware back."/>
                        <TextBlock Text="TUNNEL BOARD 1  (Node A)" Style="{StaticResource Label}"/>
                        <ComboBox x:Name="TUartA" ItemTemplate="{StaticResource TextItem}" Margin="0,0,0,10"/>
                        <TextBlock Text="TUNNEL BOARD 2  (Node B)" Style="{StaticResource Label}"/>
                        <ComboBox x:Name="TUartB" ItemTemplate="{StaticResource TextItem}" Margin="0,0,0,10"/>
                        <WrapPanel>
                          <RadioButton x:Name="TUartQuick" Style="{StaticResource Chip}" GroupName="tuartlen" Content="quick check - 10 s" IsChecked="True"/>
                          <RadioButton x:Name="TUartSoak" Style="{StaticResource Chip}" GroupName="tuartlen" Content="soak - 2 min (long wires)"/>
                        </WrapPanel>
                        <Button x:Name="TUartTest" Style="{StaticResource Primary}" Content="Flash both + test the cable  &#x2192;" HorizontalAlignment="Left" Padding="16,8" Margin="0,6,0,0"/>
                      </StackPanel>
                    </Border>
                  </WrapPanel>
                </StackPanel>
              </ScrollViewer>
            </TabItem>
          </TabControl>
        </DockPanel>
      </TabItem>

      <!-- DATA (phase 3) -->
      <TabItem>
        <DockPanel>
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Style="{StaticResource H1}" Text="Data"/>
            <TextBlock Style="{StaticResource Sub}" Text="Bring captures in from an SD card, trim, archive, read run logs and clean up - all from here. Sharing with the team: GitHub sync in the sidebar."/>
          </StackPanel>
          <TabControl x:Name="DataTabs" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource SubTab}">
            <TabItem Header="  Import / export  ">
              <Grid Margin="0,12,0,0">
                <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
                <Grid Grid.Row="0" Margin="0,0,0,12">
                  <Grid.ColumnDefinitions><ColumnDefinition Width="11*"/><ColumnDefinition Width="14"/><ColumnDefinition Width="10*"/></Grid.ColumnDefinitions>
                  <!-- 1: where -->
                  <Border Grid.Column="0" Style="{StaticResource Card}" Padding="16,12">
                    <StackPanel>
                      <TextBlock Text="1   WHERE ARE THE FILES?" Style="{StaticResource Label}"/>
                      <WrapPanel Margin="0,2,0,6">
                        <RadioButton x:Name="SrcPort" Style="{StaticResource Chip}" GroupName="impsrc" IsChecked="True" Content="&#x2B21;  through a board over USB  (card stays in)"/>
                        <RadioButton x:Name="SrcCard" Style="{StaticResource Chip}" GroupName="impsrc" Content="&#x25A3;  SD card in a reader"/>
                      </WrapPanel>
                      <StackPanel x:Name="ImpPortPane">
                        <ComboBox x:Name="CardPortPick" Margin="0,0,0,4">
                          <ComboBox.ItemTemplate>
                            <DataTemplate>
                              <StackPanel Margin="0,1">
                                <TextBlock FontFamily="Cascadia Mono, Consolas">
                                  <Run Text="{Binding Port, Mode=OneWay}" Foreground="#22D3EE" FontWeight="Bold"/><Run Text="   "/><Run Text="{Binding MacTxt, Mode=OneWay}" Foreground="#93C5FD"/><Run Text="   "/><Run Text="{Binding Who, Mode=OneWay}" Foreground="$($Pal.Text)" FontWeight="SemiBold"/>
                                </TextBlock>
                                <TextBlock FontSize="11.5" Margin="18,2,0,0">
                                  <Run Text="{Binding Icon, Mode=OneWay}" Foreground="{Binding IconFg, Mode=OneWay}" FontWeight="Bold"/><Run Text=" "/><Run Text="{Binding Lead, Mode=OneWay}" Foreground="{Binding LeadFg, Mode=OneWay}"/><Run Text="{Binding When, Mode=OneWay}" Foreground="{Binding WhenFg, Mode=OneWay}" FontWeight="Bold"/><Run Text="{Binding Arrow, Mode=OneWay}" Foreground="$($Pal.Faint)"/><Run Text="{Binding Atk, Mode=OneWay}" Foreground="{Binding AtkFg, Mode=OneWay}" FontWeight="Bold"/><Run Text="{Binding Rest, Mode=OneWay}" Foreground="$($Pal.Text)"/><Run Text="{Binding Rep, Mode=OneWay}" Foreground="#FBBF24" FontWeight="Bold"/>
                                </TextBlock>
                              </StackPanel>
                            </DataTemplate>
                          </ComboBox.ItemTemplate>
                        </ComboBox>
                        <TextBlock Foreground="$($Pal.Faint)" FontSize="11" TextWrapping="Wrap" Text="Each port shows the board's MAC + nickname. Only after its run has ENDED - reading a card while the board is still logging is not allowed (and never unplug it while it is read)."/>
                      </StackPanel>
                      <StackPanel x:Name="ImpCardPane" Visibility="Collapsed">
                        <DockPanel Margin="0,0,0,4">
                          <Button x:Name="ImpRescan" DockPanel.Dock="Right" Content="Rescan" Padding="10,4" Margin="6,0,0,0"/>
                          <ComboBox x:Name="CardPick" ItemTemplate="{StaticResource TextItem}" Margin="0"/>
                        </DockPanel>
                        <TextBlock Foreground="$($Pal.Faint)" FontSize="11" TextWrapping="Wrap" Text="Cards with baseline / blackhole / wormhole folders are listed first. Nothing touches a board."/>
                      </StackPanel>
                    </StackPanel>
                  </Border>
                  <!-- 2: which run -->
                  <Border Grid.Column="2" Style="{StaticResource Card}" Padding="16,12">
                    <StackPanel>
                      <TextBlock Text="2   WHICH RUN IS IT?  (filled in from the card - change it if needed)" Style="{StaticResource Label}"/>
                      <WrapPanel Margin="0,2,0,4">
                        <StackPanel Margin="0,0,10,6">
                          <TextBlock Text="attack" Foreground="$($Pal.Dim)" FontSize="11"/>
                          <ComboBox x:Name="ImpAttack" Width="112" Margin="0"/>
                        </StackPanel>
                        <StackPanel Margin="0,0,10,6">
                          <TextBlock Text="topology" Foreground="$($Pal.Dim)" FontSize="11"/>
                          <ComboBox x:Name="ImpTopology" Width="118" Margin="0"/>
                        </StackPanel>
                        <StackPanel Margin="0,0,10,6">
                          <TextBlock Text="location" Foreground="$($Pal.Dim)" FontSize="11"/>
                          <ComboBox x:Name="ImpLocation" Width="122" Margin="0"/>
                        </StackPanel>
                        <StackPanel Margin="0,0,10,6">
                          <TextBlock Text="scenario" Foreground="$($Pal.Dim)" FontSize="11"/>
                          <ComboBox x:Name="ImpScenario" Width="112" Margin="0"/>
                        </StackPanel>
                        <StackPanel Margin="0,0,14,6">
                          <TextBlock Text="repeat" Foreground="$($Pal.Dim)" FontSize="11"/>
                          <StackPanel Orientation="Horizontal">
                            <Button x:Name="ImpRepMinus" Content="-" Padding="9,3" Margin="0,0,4,0"/>
                            <TextBox x:Name="ImpRepeat" Width="36" Text="1" TextAlignment="Center" Padding="2,4" Margin="0,0,4,0"/>
                            <Button x:Name="ImpRepPlus" Content="+" Padding="9,3" Margin="0"/>
                          </StackPanel>
                        </StackPanel>
                        <CheckBox x:Name="ImpAborted" Content="show aborted" VerticalAlignment="Bottom" Margin="0,0,0,10"/>
                      </WrapPanel>
                      <TextBlock x:Name="ImpDest" Text="" Foreground="$($Pal.Cyan)" FontSize="11.5" FontFamily="Cascadia Mono, Consolas" TextWrapping="Wrap" Margin="0,0,0,6"/>
                      <TextBlock Text="names the files after this preset's boards" Foreground="$($Pal.Dim)" FontSize="11"/>
                      <ComboBox x:Name="ImpRoster" ItemTemplate="{StaticResource TextItem}" Margin="0,0,0,8"/>
                      <Button x:Name="ImpList" Style="{StaticResource Primary}" Content="List what's on it  &#x2192;" HorizontalAlignment="Left" Padding="16,7" Margin="0"/>
                    </StackPanel>
                  </Border>
                </Grid>
                <!-- 3: the files -->
                <Border Grid.Row="1" Style="{StaticResource Card}" Padding="10">
                  <DockPanel>
                  <Border x:Name="ImpLiveBar" DockPanel.Dock="Top" CornerRadius="12" Background="#3A2E14" BorderBrush="$($Pal.Amber)" BorderThickness="1" Padding="14,10" Margin="0,0,0,10" Visibility="Collapsed">
                    <DockPanel>
                      <Button x:Name="ImpEndRun" DockPanel.Dock="Right" Style="{StaticResource Primary}" Content="End its run now + close the file safely" Padding="14,7" Margin="10,0,0,0" VerticalAlignment="Center"/>
                      <TextBlock DockPanel.Dock="Left" Text="&#xE7BA;" FontFamily="Segoe MDL2 Assets" FontSize="20" Foreground="$($Pal.Amber)" VerticalAlignment="Center" Margin="0,0,12,0"/>
                      <StackPanel VerticalAlignment="Center">
                        <TextBlock x:Name="ImpLiveTitle" Text="" FontWeight="SemiBold" Foreground="$($Pal.Amber)" TextWrapping="Wrap"/>
                        <TextBlock Foreground="$($Pal.Dim)" TextWrapping="Wrap" FontSize="12" Text="Do NOT unplug it yet - that leaves the file ABORTED. If the run is over (root finished, or this board missed TERMINATE), close it here: the board finishes cleanly (firmware END_RUN), then the list refreshes. If it is still mid-run, closing cuts the capture short."/>
                      </StackPanel>
                    </DockPanel>
                  </Border>
                  <WrapPanel DockPanel.Dock="Bottom" Margin="4,8,0,0">
                    <TextBlock Text="COLOURS:" Foreground="$($Pal.Faint)" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center" Margin="0,0,10,0"/>
                    <Border CornerRadius="7" Background="#1F4D3E" Padding="7,1" Margin="0,0,5,0"><TextBlock Text="green" Foreground="$($Pal.Green)" FontSize="11" FontWeight="Bold"/></Border>
                    <TextBlock Text="ready - import it" Foreground="$($Pal.Dim)" FontSize="11" VerticalAlignment="Center" Margin="0,0,14,0"/>
                    <Border CornerRadius="7" Background="#1E2A44" Padding="7,1" Margin="0,0,5,0"><TextBlock Text="blue" Foreground="$($Pal.Blue)" FontSize="11" FontWeight="Bold"/></Border>
                    <TextBlock Text="just information - nothing wrong" Foreground="$($Pal.Dim)" FontSize="11" VerticalAlignment="Center" Margin="0,0,14,0"/>
                    <Border CornerRadius="7" Background="#2A2E48" Padding="7,1" Margin="0,0,5,0"><TextBlock Text="grey" Foreground="$($Pal.Dim)" FontSize="11" FontWeight="Bold"/></Border>
                    <TextBlock Text="already done" Foreground="$($Pal.Dim)" FontSize="11" VerticalAlignment="Center" Margin="0,0,14,0"/>
                    <Border CornerRadius="7" Background="#3A2E14" Padding="7,1" Margin="0,0,5,0"><TextBlock Text="amber" Foreground="$($Pal.Amber)" FontSize="11" FontWeight="Bold"/></Border>
                    <TextBlock Text="look before importing" Foreground="$($Pal.Dim)" FontSize="11" VerticalAlignment="Center" Margin="0,0,14,0"/>
                    <Border CornerRadius="7" Background="#3A1E2C" Padding="7,1" Margin="0,0,5,0"><TextBlock Text="red" Foreground="$($Pal.Red)" FontSize="11" FontWeight="Bold"/></Border>
                    <TextBlock Text="a real problem - no usable data" Foreground="$($Pal.Dim)" FontSize="11" VerticalAlignment="Center"/>
                  </WrapPanel>
                  <Grid>
                    <DataGrid x:Name="ImpGrid" IsReadOnly="False" CanUserAddRows="False" AutoGenerateColumns="False" HeadersVisibility="Column" SelectionMode="Single">
                      <DataGrid.Columns>
                        <DataGridTemplateColumn Header="" Width="44" MinWidth="44" CanUserResize="False">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><CheckBox Style="{StaticResource TickBox}" IsChecked="{Binding Import, UpdateSourceTrigger=PropertyChanged}" Margin="0"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="status" Width="185">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate>
                              <Border Background="{Binding StatusBg}" CornerRadius="8" Padding="8,1" HorizontalAlignment="Left" ToolTip="{Binding Why}">
                                <TextBlock Text="{Binding Status}" Foreground="{Binding StatusFg}" FontWeight="Bold" FontSize="11"/>
                              </Border>
                            </DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="when it ran" Width="150">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock FontFamily="Cascadia Mono, Consolas" FontSize="11.5"><Run Text="{Binding RanDate, Mode=OneWay}" Foreground="{Binding RanFg, Mode=OneWay}"/><Run Text="{Binding RanTime, Mode=OneWay}" Foreground="#22D3EE" FontWeight="Bold"/></TextBlock></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="board" Width="200">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock><Run Text="{Binding BRole, Mode=OneWay}" Foreground="$($Pal.Faint)"/><Run Text="  "/><Run Text="{Binding BMac, Mode=OneWay}" Foreground="#93C5FD"/><Run Text="  "/><Run Text="{Binding BNick, Mode=OneWay}" Foreground="$($Pal.Text)" FontWeight="SemiBold"/></TextBlock></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="recorded as (on the card)" Width="210">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock><Run Text="{Binding CAtk, Mode=OneWay}" Foreground="{Binding AtkFg, Mode=OneWay}" FontWeight="SemiBold"/><Run Text="{Binding CRest, Mode=OneWay}" Foreground="$($Pal.Text)"/></TextBlock></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="goes to  datasets\exports\" Width="250">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock><Run Text="{Binding CAtk, Mode=OneWay}" Foreground="{Binding AtkFg, Mode=OneWay}"/><Run Text="{Binding DMid, Mode=OneWay}" Foreground="$($Pal.Dim)"/><Run Text="{Binding DScn, Mode=OneWay}" Foreground="#22D3EE" FontWeight="SemiBold"/></TextBlock></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="kind" Binding="{Binding Kind}" Width="70" IsReadOnly="True"/>
                        <DataGridTextColumn Header="boot / run" Binding="{Binding Boot}" Width="80" IsReadOnly="True"/>
                        <DataGridTextColumn Header="rows" Binding="{Binding Rows}" Width="90" IsReadOnly="True"/>
                        <DataGridTextColumn Header="phases" Binding="{Binding Phases}" Width="80" IsReadOnly="True"/>
                        <DataGridTextColumn Header="file" Binding="{Binding File}" Width="*" IsReadOnly="True"/>
                      </DataGrid.Columns>
                    </DataGrid>
                    <StackPanel x:Name="ImpEmpty" VerticalAlignment="Center" HorizontalAlignment="Center">
                      <TextBlock Text="&#xE896;" FontFamily="Segoe MDL2 Assets" FontSize="40" Foreground="$($Pal.Faint)" HorizontalAlignment="Center"/>
                      <TextBlock x:Name="ImpEmptyText" Text="Pick a board or a card, then press 'List what's on it'." Foreground="$($Pal.Dim)" Margin="0,8,0,0" HorizontalAlignment="Center"/>
                    </StackPanel>
                  </Grid>
                  </DockPanel>
                </Border>
                <!-- 4: go -->
                <DockPanel Grid.Row="2" Margin="0,12,0,0">
                  <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
                    <CheckBox x:Name="ImpDelete" Content="delete from the card after a verified copy" VerticalAlignment="Center" Margin="0,0,14,0"/>
                    <Button x:Name="ImpPreview" Content="Preview (copies nothing)" IsEnabled="False"/>
                    <Button x:Name="ImpGo" Style="{StaticResource Primary}" Content="Import" IsEnabled="False" Padding="18,7" Margin="0"/>
                    <Button x:Name="ImpDel" Style="{StaticResource Danger}" Content="Delete from card" IsEnabled="False" Padding="14,7" Margin="8,0,0,0"
                            ToolTip="Deletes the TICKED files from the SD card (in the reader, or through the board over USB) - nothing is imported. A file the board is still writing is never deleted. Files never imported are listed by name first: deleting those destroys the last copy."/>
                  </StackPanel>
                  <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
                    <Button x:Name="ImpNew" Content="tick NEW only" Padding="10,4"/>
                    <Button x:Name="ImpAll" Content="tick all" Padding="10,4"/>
                    <Button x:Name="ImpNone" Content="tick none" Padding="10,4"/>
                    <TextBlock x:Name="ImpSummary" Foreground="$($Pal.Dim)" VerticalAlignment="Center" Margin="8,0,0,0" TextWrapping="Wrap"/>
                  </StackPanel>
                </DockPanel>
              </Grid>
            </TabItem>
            <TabItem Header="  Trim &amp; archive  ">
              <!-- oct. 18 2026 redesign: a designed, virtualised run list for Trim (status per
                   run, preview first) + Archive as a clearly-dangerous step card with the past
                   archives listed. Folders are scanned only when the Data page opens. -->
              <Grid Margin="0,12,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="400"/></Grid.ColumnDefinitions>
                <!-- TRIM -->
                <Border Grid.Column="0" Style="{StaticResource Card}" Padding="16" Margin="0,0,14,0" BorderThickness="0,3,0,0" BorderBrush="{StaticResource GradCool}">
                  <DockPanel>
                    <DockPanel DockPanel.Dock="Top" Margin="0,0,0,10">
                      <Border DockPanel.Dock="Left" Width="40" Height="40" CornerRadius="20" Background="{StaticResource GradCool}" Margin="0,0,12,0" VerticalAlignment="Top">
                        <TextBlock Text="&#xE8C6;" FontFamily="Segoe MDL2 Assets" FontSize="17" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      </Border>
                      <StackPanel>
                        <TextBlock Text="Trim a captured run" FontSize="18" FontWeight="Bold"/>
                        <TextBlock Foreground="$($Pal.Dim)" FontSize="12" TextWrapping="Wrap" Text="Keeps only the real experiment session of every board's file (drops the flash / export boots). Writes a trimmed\ copy - the raw export is never touched. Analyse trims by itself; use this to check or re-trim one run."/>
                      </StackPanel>
                    </DockPanel>
                    <WrapPanel DockPanel.Dock="Top" Margin="0,0,0,4">
                      <RadioButton x:Name="TrimFAll"   Style="{StaticResource Chip}" GroupName="trimf" Content="All" IsChecked="True"/>
                      <RadioButton x:Name="TrimFTodo"  Style="{StaticResource Chip}" GroupName="trimf" Content="Not trimmed"/>
                      <RadioButton x:Name="TrimFStale" Style="{StaticResource Chip}" GroupName="trimf" Content="Needs re-trim"/>
                      <RadioButton x:Name="TrimFDone"  Style="{StaticResource Chip}" GroupName="trimf" Content="Trimmed"/>
                      <Grid Width="220" Margin="6,0,8,8">
                        <TextBox x:Name="TrimSearch" Margin="0" Padding="30,6,8,6" ToolTip="Type any part: worm tree dlsu, highload..."/>
                        <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" Foreground="$($Pal.Faint)" VerticalAlignment="Center" Margin="11,0,0,0" IsHitTestVisible="False"/>
                        <TextBlock x:Name="TrimSearchHint" Text="Search runs..." Foreground="$($Pal.Faint)" VerticalAlignment="Center" Margin="31,0,0,0" IsHitTestVisible="False"/>
                      </Grid>
                      <Button x:Name="TrimRefresh" Content="&#x21BB;  Refresh" Padding="12,5"/>
                    </WrapPanel>
                    <TextBlock x:Name="TrimCount" DockPanel.Dock="Top" Foreground="$($Pal.Faint)" FontSize="11" Margin="2,0,0,8"/>
                    <!-- the selected run + its actions -->
                    <Border DockPanel.Dock="Bottom" CornerRadius="12" Padding="14,10" Margin="0,10,0,0" Background="$($Pal.Card2)">
                      <DockPanel>
                        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                          <Button x:Name="TrimPreview" Style="{StaticResource Cool}" Content="Preview" ToolTip="Shows what would be kept - writes nothing" IsEnabled="False" Margin="0,0,8,0"/>
                          <Button x:Name="TrimGo" Style="{StaticResource Primary}" Content="&#x2702;  Trim it" IsEnabled="False" Margin="0,0,8,0"/>
                          <Button x:Name="TrimOpen" Content="Open folder" IsEnabled="False" Margin="0"/>
                        </StackPanel>
                        <StackPanel VerticalAlignment="Center">
                          <TextBlock x:Name="TrimSel" FontWeight="SemiBold" Text="Pick a run above" TextTrimming="CharacterEllipsis"/>
                          <TextBlock x:Name="TrimSelSub" Foreground="$($Pal.Dim)" FontSize="11.5" TextTrimming="CharacterEllipsis"/>
                        </StackPanel>
                      </DockPanel>
                    </Border>
                    <ListBox x:Name="TrimList" Background="Transparent" BorderThickness="0"
                             ScrollViewer.HorizontalScrollBarVisibility="Disabled" ScrollViewer.CanContentScroll="True"
                             VirtualizingPanel.IsVirtualizing="True" VirtualizingPanel.VirtualizationMode="Recycling" VirtualizingPanel.ScrollUnit="Pixel">
                      <ListBox.ItemContainerStyle>
                        <Style TargetType="ListBoxItem">
                          <Setter Property="Padding" Value="0"/><Setter Property="Margin" Value="0,0,6,6"/>
                          <Setter Property="HorizontalContentAlignment" Value="Stretch"/><Setter Property="ToolTip" Value="{Binding Dir}"/>
                          <Setter Property="Template">
                            <Setter.Value>
                              <ControlTemplate TargetType="ListBoxItem">
                                <Border x:Name="b" Background="{Binding RowBg}" BorderBrush="$($Pal.Line)" BorderThickness="1.5" CornerRadius="12" Padding="12,7" Cursor="Hand">
                                  <ContentPresenter/>
                                </Border>
                                <ControlTemplate.Triggers>
                                  <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="$($Pal.Accent)"/></Trigger>
                                  <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="BorderBrush" Value="#FFFFFF"/><Setter TargetName="b" Property="BorderThickness" Value="2"/></Trigger>
                                </ControlTemplate.Triggers>
                              </ControlTemplate>
                            </Setter.Value>
                          </Setter>
                        </Style>
                      </ListBox.ItemContainerStyle>
                      <ListBox.ItemTemplate>
                        <DataTemplate>
                          <DockPanel>
                            <Image DockPanel.Dock="Left" Source="{Binding Art}" Width="56" Height="34" Margin="0,0,14,0" VerticalAlignment="Center"/>
                            <Border DockPanel.Dock="Right" CornerRadius="8" Padding="8,2" Background="{Binding StatusBg}" VerticalAlignment="Center" Margin="10,0,0,0" MinWidth="96">
                              <TextBlock Text="{Binding Status}" Foreground="{Binding StatusFg}" FontSize="10" FontWeight="Bold" HorizontalAlignment="Center"/>
                            </Border>
                            <StackPanel DockPanel.Dock="Right" VerticalAlignment="Center" Width="120" Margin="10,0,0,0">
                              <TextBlock Text="{Binding Day}" FontSize="12" FontWeight="SemiBold" Foreground="$($Pal.Text)"/>
                              <TextBlock Text="{Binding Sub}" Foreground="$($Pal.Faint)" FontSize="10.5"/>
                            </StackPanel>
                            <StackPanel VerticalAlignment="Center">
                              <TextBlock Text="{Binding AtkText}" Foreground="{Binding AtkFg}" FontSize="10" FontWeight="Bold"/>
                              <WrapPanel Margin="0,1,0,0">
                                <TextBlock Text="{Binding Topo}" FontSize="14" FontWeight="Bold" Foreground="$($Pal.Text)" VerticalAlignment="Center" Margin="0,0,10,0"/>
                                <Border CornerRadius="8" Padding="7,1" Background="{Binding LocBg}" Margin="0,0,5,0" VerticalAlignment="Center">
                                  <TextBlock Text="{Binding LocText}" Foreground="{Binding LocFg}" FontSize="11" FontWeight="SemiBold"/>
                                </Border>
                                <Border CornerRadius="8" Padding="7,1" Background="{Binding ScnBg}" VerticalAlignment="Center">
                                  <TextBlock Text="{Binding ScnText}" Foreground="{Binding ScnFg}" FontSize="11" FontWeight="SemiBold"/>
                                </Border>
                              </WrapPanel>
                            </StackPanel>
                          </DockPanel>
                        </DataTemplate>
                      </ListBox.ItemTemplate>
                    </ListBox>
                  </DockPanel>
                </Border>
                <!-- ARCHIVE -->
                <Border Grid.Column="1" Style="{StaticResource Card}" Padding="16" BorderThickness="0,3,0,0" BorderBrush="$($Pal.Red)">
                  <DockPanel>
                    <DockPanel DockPanel.Dock="Top" Margin="0,0,0,10">
                      <Border DockPanel.Dock="Left" Width="40" Height="40" CornerRadius="20" Background="#3A1E2C" Margin="0,0,12,0" VerticalAlignment="Top">
                        <TextBlock Text="&#xE7B8;" FontFamily="Segoe MDL2 Assets" FontSize="17" Foreground="$($Pal.Red)" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      </Border>
                      <StackPanel>
                        <TextBlock Text="Archive the live data" FontSize="18" FontWeight="Bold"/>
                        <TextBlock Foreground="$($Pal.Dim)" FontSize="12" TextWrapping="Wrap" Text="MOVES every live export, analysis, PCAP capture and run log into archive\&lt;date&gt;_&lt;label&gt;\ - the live checklist starts empty. Code, docs and presets stay. Nothing is deleted."/>
                      </StackPanel>
                    </DockPanel>
                    <StackPanel DockPanel.Dock="Top">
                      <DockPanel Margin="0,4,0,4">
                        <Border DockPanel.Dock="Left" Width="22" Height="22" CornerRadius="11" Background="{StaticResource GradMain}" Margin="0,0,8,0"><TextBlock Text="1" Foreground="White" FontWeight="Bold" FontSize="11" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                        <TextBlock Text="A short label  (becomes the folder name)" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="0"/>
                      </DockPanel>
                      <TextBox x:Name="ArcLabel" Margin="0,0,0,10" ToolTip="e.g. bad-attacker-mac - letters, digits, - and _"/>
                      <DockPanel Margin="0,0,0,4">
                        <Border DockPanel.Dock="Left" Width="22" Height="22" CornerRadius="11" Background="{StaticResource GradMain}" Margin="0,0,8,0"><TextBlock Text="2" Foreground="White" FontWeight="Bold" FontSize="11" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                        <TextBlock Text="Why  (written into the archive's README)" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="0"/>
                      </DockPanel>
                      <TextBox x:Name="ArcReason" Margin="0,0,0,10" Height="54" TextWrapping="Wrap" AcceptsReturn="False" VerticalContentAlignment="Top"/>
                      <DockPanel Margin="0,0,0,6">
                        <Border DockPanel.Dock="Left" Width="22" Height="22" CornerRadius="11" Background="{StaticResource GradMain}" Margin="0,0,8,0"><TextBlock Text="3" Foreground="White" FontWeight="Bold" FontSize="11" HorizontalAlignment="Center" VerticalAlignment="Center"/></Border>
                        <TextBlock Text="Preview first, then archive" Style="{StaticResource Label}" VerticalAlignment="Center" Margin="0"/>
                      </DockPanel>
                      <UniformGrid Columns="2" Margin="0,0,0,12">
                        <Button x:Name="ArcPreview" Style="{StaticResource Cool}" Content="Preview (moves nothing)" Margin="0,0,4,0"/>
                        <Button x:Name="ArcGo" Style="{StaticResource Danger}" Content="Archive now" Margin="4,0,0,0"/>
                      </UniformGrid>
                      <TextBlock Text="PAST ARCHIVES" Style="{StaticResource Label}"/>
                    </StackPanel>
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                      <ItemsControl x:Name="ArcList">
                        <ItemsControl.ItemTemplate>
                          <DataTemplate>
                            <Border Background="$($Pal.Card2)" CornerRadius="10" Padding="10,6" Margin="0,0,0,6" BorderThickness="3,0,0,0" BorderBrush="$($Pal.Line)" ToolTip="{Binding Path}">
                              <StackPanel>
                                <DockPanel>
                                  <TextBlock DockPanel.Dock="Right" Text="{Binding Files}" Foreground="$($Pal.Faint)" FontSize="10.5"/>
                                  <TextBlock><Run Text="{Binding Day, Mode=OneWay}" Foreground="$($Pal.Dim)" FontSize="11"/><Run Text="   "/><Run Text="{Binding Label, Mode=OneWay}" FontWeight="SemiBold"/></TextBlock>
                                </DockPanel>
                                <TextBlock Text="{Binding Reason}" Foreground="$($Pal.Faint)" FontSize="11" TextWrapping="Wrap" Margin="0,2,0,0"/>
                              </StackPanel>
                            </Border>
                          </DataTemplate>
                        </ItemsControl.ItemTemplate>
                      </ItemsControl>
                    </ScrollViewer>
                  </DockPanel>
                </Border>
              </Grid>
            </TabItem>
            <TabItem Header="  Run logs  ">
              <Grid Margin="0,10,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="2*"/><ColumnDefinition Width="3*"/></Grid.ColumnDefinitions>
                <DockPanel Grid.Column="0" Margin="0,0,12,0">
                  <StackPanel DockPanel.Dock="Bottom" Orientation="Horizontal" Margin="0,8,0,0">
                    <Button x:Name="LogRefresh" Content="Refresh"/>
                    <Button x:Name="LogOpen" Content="Open in Notepad"/>
                    <Button x:Name="LogDelete" Content="Move to Recycle Bin"/>
                  </StackPanel>
                  <DataGrid x:Name="LogGrid">
                    <DataGrid.Columns>
                      <DataGridTextColumn Header="when" Binding="{Binding WhenText}" Width="120"/>
                      <DataGridTextColumn Header="cell" Binding="{Binding Cell}" Width="*"/>
                      <DataGridTextColumn Header="KB" Binding="{Binding KB}" Width="50"/>
                    </DataGrid.Columns>
                  </DataGrid>
                </DockPanel>
                <Border Grid.Column="1" Background="#0D0E17" BorderBrush="$($Pal.Line)" BorderThickness="1" CornerRadius="14">
                  <RichTextBox x:Name="LogView" Background="Transparent" Foreground="$($Pal.Text)" BorderThickness="0" Padding="10"
                               FontFamily="Cascadia Mono, Consolas" FontSize="11" IsReadOnly="True" VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"/>
                </Border>
              </Grid>
            </TabItem>
            <TabItem Header="  Delete files  ">
              <DockPanel Margin="0,10,0,0">
                <WrapPanel DockPanel.Dock="Top">
                  <ComboBox x:Name="DelArea" Width="150"/>
                  <TextBox x:Name="DelFilter" Width="260" Margin="0,0,8,8" Padding="4,3" ToolTip="part of the path, e.g. wormhole\tree or oct16"/>
                  <Button x:Name="DelList" Content="List files"/>
                  <Button x:Name="DelGo" Content="Move ticked files to the Recycle Bin"/>
                  <TextBlock Text="this laptop only - GitHub is untouched; restore from the Recycle Bin" Foreground="$($Pal.Faint)" FontSize="11" VerticalAlignment="Center"/>
                </WrapPanel>
                <DataGrid x:Name="DelGrid" IsReadOnly="False" CanUserAddRows="False"/>
              </DockPanel>
            </TabItem>
            <TabItem Header="  Folders &amp; docs  ">
              <StackPanel Margin="0,14,0,0">
                <TextBlock Style="{StaticResource Label}" Text="FOLDERS"/>
                <WrapPanel Margin="0,4,0,16">
                  <Button x:Name="FExports" Content="Exports"/>
                  <Button x:Name="FAnalysis" Content="Analysis"/>
                  <Button x:Name="FRunLogs" Content="Run logs"/>
                  <Button x:Name="FPcap" Content="Sniffer captures (PCAP)"/>
                  <Button x:Name="FPresets" Content="Presets"/>
                </WrapPanel>
                <TextBlock Style="{StaticResource Label}" Text="DOCUMENTS"/>
                <WrapPanel Margin="0,4,0,16">
                  <Button x:Name="DVerif" Content="Verification log"/>
                  <Button x:Name="DChecklist" Content="Thesis update checklist"/>
                  <Button x:Name="DStart" Content="Start here (runbook)"/>
                </WrapPanel>
              </StackPanel>
            </TabItem>
          </TabControl>
        </DockPanel>
      </TabItem>

      <!-- WIRESHARK & SNIFFER (phase 4) -->
      <TabItem>
        <DockPanel>
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Style="{StaticResource H1}" Text="Wireshark &amp; sniffer"/>
            <TextBlock Style="{StaticResource Sub}" Text="Open a capture in a ready-made Wireshark view, check or repair a capture, measure real MAC retries, and record with the ESP32 sniffer board."/>
          </StackPanel>
          <TabControl x:Name="WsTabs" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource SubTab}">
            <TabItem Header="  Captures &amp; views  ">
              <Grid Margin="0,10,0,0">
                <Grid.ColumnDefinitions><ColumnDefinition Width="3*"/><ColumnDefinition Width="2*"/></Grid.ColumnDefinitions>
                <DockPanel Grid.Column="0" Margin="0,0,14,0">
                  <StackPanel DockPanel.Dock="Top" Orientation="Horizontal">
                    <Button x:Name="PcapRefresh" Content="Refresh"/>
                    <Button x:Name="PcapCheck" Content="Check / repair file"/>
                    <Button x:Name="PcapRetry" Content="MAC retry rate (all captures)"/>
                  </StackPanel>
                  <DataGrid x:Name="PcapGrid">
                    <DataGrid.Columns>
                      <DataGridTextColumn Header="when" Binding="{Binding WhenText}" Width="120"/>
                      <DataGridTextColumn Header="capture" Binding="{Binding Name}" Width="*"/>
                      <DataGridTextColumn Header="MB" Binding="{Binding MB}" Width="50"/>
                    </DataGrid.Columns>
                  </DataGrid>
                </DockPanel>
                <Border Grid.Column="1" Style="{StaticResource Card}" Padding="16">
                  <StackPanel>
                    <TextBlock Style="{StaticResource Label}" Text="OPEN IN WIRESHARK"/>
                    <Button x:Name="PcapLoad" Content="Read the boards in this capture" HorizontalAlignment="Left" Margin="0,4,0,10"/>
                    <TextBlock x:Name="PcapBoards" Foreground="$($Pal.Dim)" TextWrapping="Wrap" Margin="0,0,0,10" Text="Select a capture, then read its boards."/>
                    <TextBlock Style="{StaticResource Label}" Text="VIEW"/>
                    <ComboBox x:Name="ViewPick" Margin="0,2,0,10"/>
                    <TextBlock x:Name="ViewBoardLbl" Style="{StaticResource Label}" Text="BOARD"/>
                    <ComboBox x:Name="ViewBoard" Margin="0,2,0,10"/>
                    <TextBlock x:Name="ViewBoard2Lbl" Style="{StaticResource Label}" Text="SECOND BOARD"/>
                    <ComboBox x:Name="ViewBoard2" Margin="0,2,0,12"/>
                    <Button x:Name="ViewOpen" Style="{StaticResource Primary}" Content="Open in Wireshark" HorizontalAlignment="Left"/>
                  </StackPanel>
                </Border>
              </Grid>
            </TabItem>
            <TabItem Header="  ESP32 sniffer  ">
              <ScrollViewer VerticalScrollBarVisibility="Auto">
              <StackPanel Margin="0,14,0,0">
                <TextBlock Foreground="$($Pal.Dim)" TextWrapping="Wrap" Margin="0,0,0,12" Text="Use a SPARE board - the list shows each port's MAC + nickname, so pick it by name. Flash the sniffer firmware once (output streams below), then record here - Stop ends the file cleanly."/>
                <Border Style="{StaticResource Card}" Margin="0,0,0,12" BorderThickness="0,3,0,0" BorderBrush="$($Pal.Cyan)">
                  <StackPanel>
                    <DockPanel Margin="0,0,0,10">
                      <Border DockPanel.Dock="Left" Width="30" Height="30" CornerRadius="15" Background="{StaticResource GradCool}" Margin="0,0,12,0">
                        <TextBlock Text="1" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      </Border>
                      <TextBlock Text="Pick the sniffer board  (first time: flash it)" FontSize="16" FontWeight="SemiBold" VerticalAlignment="Center"/>
                    </DockPanel>
                <WrapPanel>
                  <ComboBox x:Name="SnPort" Width="460" ItemTemplate="{StaticResource TextItem}" FontFamily="Cascadia Mono, Consolas" FontSize="13.5"/>
                  <Button x:Name="SnFlash" Content="Flash sniffer firmware"/>
                </WrapPanel>
                  </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}" Margin="0,0,0,12" BorderThickness="0,3,0,0" BorderBrush="$($Pal.Purple)">
                  <StackPanel>
                    <DockPanel Margin="0,0,0,10">
                      <Border DockPanel.Dock="Left" Width="30" Height="30" CornerRadius="15" Background="{StaticResource GradMain}" Margin="0,0,12,0">
                        <TextBlock Text="2" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      </Border>
                      <TextBlock Text="File it under" FontSize="16" FontWeight="SemiBold" VerticalAlignment="Center"/>
                    </DockPanel>
                <WrapPanel>
                  <CheckBox x:Name="SnTest" Content="just a test (PCAP\standalone)" Foreground="$($Pal.Dim)" VerticalAlignment="Center" Margin="0,0,12,8" IsChecked="False" ToolTip="Ticked = PCAP\standalone\esp32_sniffer_*.pcap (no run). Unticked = named after the run below, like every other PCAP."/>
                  <ComboBox x:Name="SnAttack" Width="100"/>
                  <ComboBox x:Name="SnTopology" Width="90"/>
                  <ComboBox x:Name="SnLocation" Width="120"/>
                  <ComboBox x:Name="SnScenario" Width="100"/>
                  <TextBlock Text="repeat" Foreground="$($Pal.Dim)" VerticalAlignment="Center" Margin="0,0,6,8"/>
                  <TextBox x:Name="SnRepeat" Width="40" Text="1" Margin="0,0,10,8" Padding="4,3"/>
                </WrapPanel>
                  </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}" Margin="0,0,0,12" BorderThickness="0,3,0,0" BorderBrush="$($Pal.Green)">
                  <StackPanel>
                    <DockPanel Margin="0,0,0,10">
                      <Border DockPanel.Dock="Left" Width="30" Height="30" CornerRadius="15" Background="{StaticResource GradGood}" Margin="0,0,12,0">
                        <TextBlock Text="3" FontWeight="Bold" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                      </Border>
                      <TextBlock Text="Record" FontSize="16" FontWeight="SemiBold" VerticalAlignment="Center"/>
                    </DockPanel>
                <WrapPanel>
                  <CheckBox x:Name="SnLive" Content="also watch LIVE in Wireshark" Foreground="$($Pal.Dim)" VerticalAlignment="Center" Margin="0,0,12,8"/>
                  <CheckBox x:Name="SnStartPaused" Content="start paused" Foreground="$($Pal.Dim)" VerticalAlignment="Center" Margin="0,0,12,8" ToolTip="Opens the port and listens, but saves nothing until you press Resume - for starting before the experiment does"/>
                  <Button x:Name="SnStart" Style="{StaticResource Primary}" Content="Start recording"/>
                  <Button x:Name="SnPause" Style="{StaticResource Cool}" Content="&#x2016;  Pause" IsEnabled="False" ToolTip="Pause = the board is still read (never left unread) but nothing is saved; every pause is logged in the .json beside the .pcap"/>
                  <Button x:Name="SnStop" Content="Stop recording" IsEnabled="False"/>
                  <Button x:Name="SnMac" Content="MacBook sniffer test (opens its window)"/>
                </WrapPanel>
                  </StackPanel>
                </Border>
              </StackPanel>
              </ScrollViewer>
            </TabItem>
          </TabControl>
        </DockPanel>
      </TabItem>
      <!-- LIVE RUN: the whole capture inside the GUI (oct. 17 2026) -->
      <TabItem>
        <Grid>
          <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
          <Border Grid.Row="0" CornerRadius="18" Padding="22,14" Margin="0,0,0,14" Background="{StaticResource GradMain}">
            <DockPanel>
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                <Border CornerRadius="12" Background="#33FFFFFF" Padding="14,4" Margin="0,0,10,0">
                  <StackPanel>
                    <TextBlock Text="ELAPSED" Foreground="#EDE9FE" FontSize="10" FontWeight="SemiBold"/>
                    <TextBlock x:Name="RunClock" Text="0:00" FontSize="20" FontWeight="Bold" Foreground="White"/>
                  </StackPanel>
                </Border>
                <Border CornerRadius="12" Background="#33FFFFFF" Padding="14,4" Margin="0,0,10,0">
                  <StackPanel>
                    <TextBlock Text="STEP" Foreground="#EDE9FE" FontSize="10" FontWeight="SemiBold"/>
                    <TextBlock x:Name="RunStepCount" Text="-" FontSize="20" FontWeight="Bold" Foreground="White"/>
                  </StackPanel>
                </Border>
                <Border x:Name="RunStateBadge" CornerRadius="14" Background="White" Padding="16,9" VerticalAlignment="Center">
                  <TextBlock x:Name="RunState" Text="NOT STARTED" Foreground="#5B21B6" FontWeight="Bold" FontSize="13"/>
                </Border>
              </StackPanel>
              <StackPanel>
                <TextBlock Text="LIVE RUN  -  build, flash, monitor, START and export, all in this window" Foreground="#DDD6FE" FontSize="11" FontWeight="SemiBold"/>
                <TextBlock x:Name="RunTitle" Text="No run loaded" FontSize="22" FontWeight="Bold" Foreground="White" TextWrapping="Wrap"/>
                <TextBlock x:Name="RunSub" Text="Pick a preset on 'Run a capture' and press Start - it opens here." Foreground="#EDE9FE" TextWrapping="Wrap"/>
              </StackPanel>
            </DockPanel>
          </Border>
          <Grid Grid.Row="1">
            <Grid.ColumnDefinitions><ColumnDefinition Width="250"/><ColumnDefinition Width="*"/><ColumnDefinition Width="430"/></Grid.ColumnDefinitions>
            <!-- steps -->
            <Border Grid.Column="0" Style="{StaticResource Card}" Margin="0,0,14,0" Padding="12">
              <DockPanel>
                <TextBlock DockPanel.Dock="Top" Text="STEPS  -  click a board for its own actions" Style="{StaticResource Label}" Margin="4,0,0,8"/>
                <ScrollViewer VerticalScrollBarVisibility="Auto">
                  <ItemsControl x:Name="RunSteps">
                    <ItemsControl.ItemTemplate>
                      <DataTemplate>
                        <Border Background="{Binding Bg}" BorderBrush="{Binding Edge}" BorderThickness="1" CornerRadius="12" Padding="10,8" Margin="0,0,0,6" ToolTip="{Binding Tip}">
                          <DockPanel>
                            <Border DockPanel.Dock="Left" Width="30" Height="30" CornerRadius="15" Background="{Binding Dot}" VerticalAlignment="Top" Margin="0,0,10,0">
                              <TextBlock Text="{Binding Glyph}" FontFamily="Segoe MDL2 Assets" Foreground="#0B1020" FontSize="13" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                            </Border>
                            <StackPanel>
                              <TextBlock Text="{Binding Title}" FontWeight="SemiBold" FontSize="12.5" TextTrimming="CharacterEllipsis"/>
                              <TextBlock Text="{Binding Sub}" Foreground="$($Pal.Dim)" FontSize="11" TextWrapping="Wrap"/>
                              <TextBlock Text="{Binding State}" Foreground="{Binding Dot}" FontSize="11" FontWeight="SemiBold"/>
                            </StackPanel>
                          </DockPanel>
                        </Border>
                      </DataTemplate>
                    </ItemsControl.ItemTemplate>
                  </ItemsControl>
                </ScrollViewer>
              </DockPanel>
            </Border>
            <!-- centre: setup, console, what to do now -->
            <Grid Grid.Column="1" Margin="0,0,14,0">
              <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/></Grid.RowDefinitions>
              <Border x:Name="RunSetup" Grid.Row="0" Style="{StaticResource Card}" Padding="16,12" Margin="0,0,0,12">
                <StackPanel>
                  <WrapPanel>
                    <StackPanel Margin="0,0,18,6">
                      <TextBlock Text="REPEAT" Style="{StaticResource Label}"/>
                      <StackPanel Orientation="Horizontal">
                        <Button x:Name="RunRepMinus" Content="-" Padding="10,3" Margin="0,0,4,0"/>
                        <TextBox x:Name="RunRepeat" Width="38" Text="1" TextAlignment="Center" Margin="0,0,4,0" Padding="2,4"/>
                        <Button x:Name="RunRepPlus" Content="+" Padding="10,3" Margin="0"/>
                      </StackPanel>
                    </StackPanel>
                    <StackPanel Margin="0,0,18,6">
                      <TextBlock Text="CHILDREN ON OTHER LAPTOPS" Style="{StaticResource Label}"/>
                      <TextBox x:Name="RunRemote" Width="60" Text="0" TextAlignment="Center" HorizontalAlignment="Left" Padding="2,4" Margin="0"
                               ToolTip="Every non-root board flashed on ANOTHER laptop - the root waits for all of them before Phase 0"/>
                    </StackPanel>
                    <StackPanel Margin="0,0,18,6">
                      <TextBlock Text="AFTER THE ROOT EXPORTS" Style="{StaticResource Label}"/>
                      <WrapPanel>
                        <RadioButton x:Name="RunPostAnalyze" Style="{StaticResource Chip}" GroupName="runpost" Content="trim + analyse" IsChecked="True" ToolTip="Children's CSVs already exported over USB"/>
                        <RadioButton x:Name="RunPostTrim" Style="{StaticResource Chip}" GroupName="runpost" Content="trim only" ToolTip="Children come in later from their SD cards"/>
                        <RadioButton x:Name="RunPostNone" Style="{StaticResource Chip}" GroupName="runpost" Content="export only"/>
                      </WrapPanel>
                    </StackPanel>
                    <StackPanel Margin="0,0,18,6">
                      <TextBlock Text="WHEN A CHILD IS DONE" Style="{StaticResource Label}"/>
                      <WrapPanel>
                        <RadioButton x:Name="RunChildSkip" Style="{StaticResource Chip}" GroupName="runchild" Content="skip its export (SD card)" IsChecked="True"/>
                        <RadioButton x:Name="RunChildExport" Style="{StaticResource Chip}" GroupName="runchild" Content="export over USB"/>
                      </WrapPanel>
                    </StackPanel>
                    <StackPanel Margin="0,0,18,6">
                      <TextBlock Text="FLASH THE CHILDREN" Style="{StaticResource Label}"/>
                      <WrapPanel>
                        <RadioButton x:Name="RunPFlash1" Style="{StaticResource Chip}" GroupName="runpflash" Content="one at a time (the normal way)" ToolTip="Each child: erase + flash + its monitor, then the next one (about 2 min per board)."/>
                        <RadioButton x:Name="RunPFlash2" Style="{StaticResource Chip}" GroupName="runpflash" Content="2 at a time" ToolTip="Two children are erased + flashed at once from the compiled firmware; each is listened to as soon as it runs. A failed one is flashed alone afterwards."/>
                        <RadioButton x:Name="RunPFlash3" Style="{StaticResource Chip}" GroupName="runpflash" Content="3 at a time (faster)" IsChecked="True" ToolTip="Three children at once (7 children: about 5 min instead of 14). Never more than 3 at a time, starts 4 s apart, nothing is cut mid-flash. A failed one is flashed alone afterwards. The root is always last, on its own."/>
                      </WrapPanel>
                    </StackPanel>
                  </WrapPanel>
                  <WrapPanel Margin="0,2,0,0">
                    <CheckBox x:Name="RunSaveLog" Content="save a run log" IsChecked="True" Margin="0,0,18,8"/>
                    <CheckBox x:Name="RunClean" Content="clean rebuild first (on by default)" IsChecked="True" Margin="0,0,18,8"
                              ToolTip="ON by default (user, oct. 20 2026): every run compiles every board from scratch, so no stale build can reach a board. Untick it to save time - it is NOT needed when you change attack / topology / scenario (each combination has its own build folder). It matters when (1) a compile was interrupted (window closed, laptop slept) and builds now fail oddly, (2) right after updating / switching ESP-IDF, or (3) the project folder was moved or re-cloned. It deletes ALL compiled firmware and compiles every board from scratch (~2-4 min per firmware type), once for this run. A failed compile also offers 'Clean + recompile' for just that board."/>
                    <CheckBox x:Name="RunAutoNext" Content="move on by itself once a child has booted" IsChecked="True" Margin="0,0,18,8"/>
                    <CheckBox x:Name="RunWatchKids" Content="keep listening to every child until the run ends (records crashes)" IsChecked="True" Margin="0,0,18,8"
                              ToolTip="After a child is flashed, its serial port keeps being read in the background (no reset, nothing sent). A crash (Guru Meditation / watchdog / brownout) shows up at once on the dashboard and its backtrace is saved and decoded."/>
                  </WrapPanel>
                  <!-- clean rebuild is ON by default (user, oct. 20 2026; was off since oct. 17) -->
                  <Border CornerRadius="8" Background="$($Pal.Card2)" BorderBrush="$($Pal.Line)" BorderThickness="1" Padding="10,6" Margin="0,0,0,8">
                    <DockPanel>
                      <TextBlock DockPanel.Dock="Left" Text="&#xE946;" FontFamily="Segoe MDL2 Assets" Foreground="$($Pal.Cyan)" FontSize="13" VerticalAlignment="Top" Margin="0,1,8,0"/>
                      <TextBlock TextWrapping="Wrap" FontSize="11.5" Foreground="$($Pal.Dim)"><Run Text="Clean rebuild is ON by default - " FontWeight="SemiBold" Foreground="$($Pal.Text)"/><Run Text="the first compile of every run deletes the old builds and compiles every board from scratch (~2-4 min per firmware type), so a stale build never reaches a board. Untick it to save time: switching attack, topology or scenario is safe without it (each has its own build folder). If a compile ever fails, the error card offers 'Clean + recompile' for just that board."/></TextBlock>
                    </DockPanel>
                  </Border>
                  <TextBlock x:Name="RunNotes" Foreground="$($Pal.Amber)" TextWrapping="Wrap" FontSize="12" Margin="0,2,0,8"/>
                  <WrapPanel>
                    <Button x:Name="RunBuild" Style="{StaticResource Cool}" Content="1   Compile every board  (touches no board)" Padding="16,8"/>
                    <Button x:Name="RunGo" Style="{StaticResource Primary}" Content="2   Wipe + flash + run  &#x2192;" Padding="18,8"/>
                    <Button x:Name="RunCli" Content="open in the CLI instead" Padding="10,5" FontSize="11" Foreground="$($Pal.Faint)"/>
                  </WrapPanel>
                </StackPanel>
              </Border>
              <!-- what to do now -->
              <Border x:Name="RunNow" Grid.Row="1" CornerRadius="14" Padding="16,12" Margin="0,0,0,12" Background="$($Pal.Card2)" BorderBrush="$($Pal.Accent)" BorderThickness="1" Visibility="Collapsed">
                <DockPanel>
                  <TextBlock x:Name="RunNowIcon" DockPanel.Dock="Left" Text="&#xE945;" FontFamily="Segoe MDL2 Assets" FontSize="26" Foreground="$($Pal.Cyan)" VerticalAlignment="Top" Margin="0,2,14,0"/>
                  <StackPanel>
                    <TextBlock x:Name="RunNowTitle" Text="" FontWeight="SemiBold" FontSize="15" TextWrapping="Wrap"/>
                    <TextBlock x:Name="RunNowText" Text="" Foreground="$($Pal.Dim)" TextWrapping="Wrap" Margin="0,2,0,0"/>
                    <WrapPanel Margin="0,10,0,0">
                      <Button x:Name="RunNext" Style="{StaticResource Primary}" Content="Done with this board  &#x2192;" Padding="16,8" Margin="0,0,8,0"/>
                      <Button x:Name="RunContinue" Style="{StaticResource Cool}" Content="Continue" Padding="16,8" Margin="0,0,8,0" Visibility="Collapsed"/>
                      <Button x:Name="RunAgain" Content="Run the next repeat" Padding="14,8" Margin="0,0,8,0" Visibility="Collapsed"/>
                      <Button x:Name="RunCleanFix" Content="Clean + recompile" Padding="14,8" Margin="0,0,8,0" Visibility="Collapsed"
                              ToolTip="Deletes ONLY the failed board's build folder and compiles it from scratch - the fix when a build folder got damaged (interrupted compile, ESP-IDF update, moved folder). The other boards' builds are kept."/>
                      <Button x:Name="RunAbort" Style="{StaticResource Danger}" Content="Stop the run" Padding="12,8" Margin="0,0,12,0"/>
                      <CheckBox x:Name="RunSkipExport" Content="skip this board's export" VerticalAlignment="Center"/>
                    </WrapPanel>
                  </StackPanel>
                </DockPanel>
              </Border>
              <Border Grid.Row="2" CornerRadius="14" Background="#0D0E17" BorderBrush="$($Pal.Line)" BorderThickness="1">
                <DockPanel>
                  <DockPanel DockPanel.Dock="Top" Margin="14,8,10,2">
                    <Button x:Name="RunConsoleClear" DockPanel.Dock="Right" Content="Clear" Padding="10,2" Margin="0" FontSize="11"/>
                    <CheckBox x:Name="RunFollow" DockPanel.Dock="Right" Content="follow" IsChecked="True" Margin="0,0,10,0" VerticalAlignment="Center"/>
                    <TextBlock Text="&#xE756;" FontFamily="Segoe MDL2 Assets" Foreground="$($Pal.Cyan)" VerticalAlignment="Center" Margin="0,0,8,0"/>
                    <TextBlock x:Name="RunConsoleTitle" Text="CONSOLE" Foreground="$($Pal.Faint)" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center"/>
                  </DockPanel>
                  <RichTextBox x:Name="RunConsole" Background="Transparent" Foreground="$($Pal.Text)" BorderThickness="0" Padding="12,0,12,6"
                               FontFamily="Cascadia Mono, Consolas" FontSize="11" IsReadOnly="True" VerticalScrollBarVisibility="Auto"/>
                </DockPanel>
              </Border>
            </Grid>
            <!-- right: the ROOT dashboard, read live from the root's monitor -->
            <ScrollViewer Grid.Column="2" VerticalScrollBarVisibility="Auto">
              <StackPanel>
                <Border Style="{StaticResource Card}" Padding="16,12" Margin="0,0,0,12">
                  <StackPanel>
                    <DockPanel>
                      <TextBlock DockPanel.Dock="Right" x:Name="RunPhaseLeft" Text="" FontSize="22" FontWeight="Bold" Foreground="$($Pal.Cyan)"/>
                      <StackPanel>
                        <TextBlock Text="ROOT  -  PHASE" Style="{StaticResource Label}"/>
                        <TextBlock x:Name="RunPhase" Text="not running yet" FontSize="20" FontWeight="Bold"/>
                      </StackPanel>
                    </DockPanel>
                    <Grid x:Name="RunSegs" Margin="0,10,0,2" Height="10"/>
                    <Grid x:Name="RunSegLabels" Margin="0,2,0,0"/>
                    <TextBlock x:Name="RunPhaseNote" Foreground="$($Pal.Dim)" FontSize="11" TextWrapping="Wrap" Margin="0,6,0,0"/>
                  </StackPanel>
                </Border>
                <Border x:Name="RunGateCard" Style="{StaticResource Card}" Padding="16,12" Margin="0,0,0,12">
                  <StackPanel>
                    <DockPanel>
                      <Border DockPanel.Dock="Right" CornerRadius="12" Background="$($Pal.Card2)" Padding="12,4">
                        <StackPanel>
                          <TextBlock Text="CHILDREN IN" Foreground="$($Pal.Faint)" FontSize="10" FontWeight="SemiBold" HorizontalAlignment="Center"/>
                          <TextBlock x:Name="RunKids" Text="-" FontSize="24" FontWeight="Bold" HorizontalAlignment="Center"/>
                        </StackPanel>
                      </Border>
                      <StackPanel>
                        <TextBlock Text="START GATE  (safety net)" Style="{StaticResource Label}"/>
                        <TextBlock x:Name="RunGate" Text="The root waits for every child, checks the setup, then waits for you." TextWrapping="Wrap" FontSize="12.5"/>
                      </StackPanel>
                    </DockPanel>
                    <Grid Margin="0,12,0,0">
                      <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
                      <Button x:Name="RunStart" Grid.Column="0" Content="&#x25B6;  START" Background="{StaticResource GradGood}" Foreground="#0B1020" BorderBrush="Transparent"
                              FontWeight="Bold" FontSize="16" Padding="14,10" Margin="0,0,8,0" IsEnabled="False"
                              ToolTip="Sends START to the root. The root still refuses it while a gate is not met (it keeps it and starts as soon as the gate passes)."/>
                      <Button x:Name="RunStartAnyway" Grid.Column="1" Style="{StaticResource Danger}" Content="START_ANYWAY" Padding="12,10" Margin="0" IsEnabled="False"
                              ToolTip="Overrides every gate. Only when a board is truly gone - the run is then short / not set up, say so wherever it is used."/>
                    </Grid>
                    <DockPanel Margin="0,8,0,0">
                      <Button x:Name="RunSend" DockPanel.Dock="Right" Content="Send" Padding="12,4" Margin="6,0,0,0" IsEnabled="False"/>
                      <TextBox x:Name="RunCmd" Margin="0" Padding="6,4" ToolTip="Any command for the board on this step (e.g. GET_LOCATION), Enter sends"/>
                    </DockPanel>
                  </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}" Padding="16,12" Margin="0,0,0,12">
                  <StackPanel>
                    <DockPanel>
                      <Border DockPanel.Dock="Right" x:Name="RunTopoBadge" CornerRadius="10" Background="$($Pal.Card2)" Padding="10,3" VerticalAlignment="Top">
                        <TextBlock x:Name="RunTopoStatus" Text="-" FontWeight="Bold" FontSize="11"/>
                      </Border>
                      <StackPanel>
                        <TextBlock Text="MESH  (the root's topology table)" Style="{StaticResource Label}"/>
                        <TextBlock x:Name="RunTopoInfo" Text="appears once the root prints its first table" Foreground="$($Pal.Dim)" FontSize="12" TextWrapping="Wrap"/>
                      </StackPanel>
                    </DockPanel>
                    <TextBlock x:Name="RunTopoDetail" Foreground="$($Pal.Faint)" FontSize="11" TextWrapping="Wrap" Margin="0,4,0,8"/>
                    <ItemsControl x:Name="RunNodes">
                      <ItemsControl.ItemTemplate>
                        <DataTemplate>
                          <Border Background="$($Pal.Card2)" CornerRadius="10" Padding="10,6" Margin="0,0,0,5" ToolTip="{Binding Tip}">
                            <DockPanel>
                              <Border DockPanel.Dock="Left" Width="40" CornerRadius="8" Background="{Binding HopBg}" Padding="0,3" Margin="0,0,10,0" VerticalAlignment="Center">
                                <TextBlock Text="{Binding Hop}" FontWeight="Bold" FontSize="11" Foreground="#0B1020" HorizontalAlignment="Center"/>
                              </Border>
                              <TextBlock DockPanel.Dock="Right" Text="{Binding Export}" Foreground="{Binding ExportFg}" FontSize="11" FontWeight="SemiBold" VerticalAlignment="Center" Margin="8,0,0,0"/>
                              <TextBlock DockPanel.Dock="Right" Text="{Binding Phase}" Foreground="{Binding PhaseFg}" FontSize="11" VerticalAlignment="Center" Margin="8,0,0,0"/>
                              <StackPanel>
                                <StackPanel Orientation="Horizontal">
                                  <TextBlock Text="{Binding Name}" FontWeight="SemiBold" FontSize="12"/>
                                  <Border CornerRadius="6" Background="{Binding RoleBg}" Padding="6,0" Margin="8,0,0,0" VerticalAlignment="Center">
                                    <TextBlock Text="{Binding Role}" FontSize="10" FontWeight="Bold" Foreground="#0B1020"/>
                                  </Border>
                                </StackPanel>
                                <TextBlock Text="{Binding Sub}" Foreground="$($Pal.Faint)" FontSize="10.5"/>
                              </StackPanel>
                            </DockPanel>
                          </Border>
                        </DataTemplate>
                      </ItemsControl.ItemTemplate>
                    </ItemsControl>
                  </StackPanel>
                </Border>
                <Border x:Name="RunTunnelCard" Style="{StaticResource Card}" Padding="16,12" Margin="0,0,0,12" Visibility="Collapsed">
                  <StackPanel>
                    <TextBlock Text="WORMHOLE TUNNEL" Style="{StaticResource Label}"/>
                    <TextBlock x:Name="RunTunnel" TextWrapping="Wrap" FontSize="12" FontFamily="Cascadia Mono, Consolas"/>
                  </StackPanel>
                </Border>
                <Border Style="{StaticResource Card}" Padding="16,12" Margin="0,0,0,12">
                  <StackPanel>
                    <TextBlock Text="ALERTS FROM THE BOARDS" Style="{StaticResource Label}"/>
                    <TextBlock x:Name="RunAlertsNone" Text="Nothing wrong so far." Foreground="$($Pal.Green)" FontSize="12"/>
                    <ItemsControl x:Name="RunAlerts">
                      <ItemsControl.ItemTemplate>
                        <DataTemplate>
                          <Border Background="{Binding Bg}" BorderBrush="{Binding Edge}" BorderThickness="1" CornerRadius="10" Padding="10,6" Margin="0,4,0,0">
                            <StackPanel>
                              <TextBlock Text="{Binding When}" Foreground="{Binding Edge}" FontSize="10" FontWeight="SemiBold"/>
                              <TextBlock Text="{Binding Text}" TextWrapping="Wrap" FontSize="11.5"/>
                            </StackPanel>
                          </Border>
                        </DataTemplate>
                      </ItemsControl.ItemTemplate>
                    </ItemsControl>
                  </StackPanel>
                </Border>
              </StackPanel>
            </ScrollViewer>
          </Grid>
        </Grid>
      </TabItem>
      <TabItem>
        <DockPanel>
          <StackPanel DockPanel.Dock="Top">
            <TextBlock Style="{StaticResource H1}" Text="GitHub sync"/>
            <TextBlock Style="{StaticResource Sub}" Text="Shares captures, analysis + EDA, run logs and presets with the team - never code. It checks everything first, analyses before it sends, never re-uploads duplicates or deleted runs, and updates your folder without ever leaving a half-done merge."/>
          </StackPanel>
          <!-- hero: what is going on, one big button -->
          <Border DockPanel.Dock="Top" CornerRadius="18" Padding="20,16" Margin="0,0,0,12" Background="$($Pal.Card2)" BorderBrush="{StaticResource GradCool}" BorderThickness="2">
            <DockPanel>
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                <Button x:Name="SyncCheck" Content="&#x21BB;  Check" Padding="14,9" Margin="0,0,10,0"
                        ToolTip="Looks at GitHub and this laptop and plans everything - changes nothing (about 20 s)."/>
                <Button x:Name="SyncGo" Style="{StaticResource Primary}" Content="Smart sync  &#x2192;" FontSize="15" FontWeight="Bold" Padding="22,11" Margin="0"
                        ToolTip="1 check  2 analyse what is stale  3 send the ticked files  4 receive the ticked files  5 update your folder. Asks once before anything goes to GitHub."/>
              </StackPanel>
              <Border DockPanel.Dock="Left" x:Name="SyncIconBg" Width="56" Height="56" CornerRadius="28" Background="{StaticResource GradCool}" Margin="0,0,16,0" VerticalAlignment="Center">
                <TextBlock x:Name="SyncIcon" Text="&#xE895;" FontFamily="Segoe MDL2 Assets" FontSize="26" Foreground="#0B1020" HorizontalAlignment="Center" VerticalAlignment="Center"/>
              </Border>
              <StackPanel VerticalAlignment="Center">
                <TextBlock x:Name="SyncHead" Text="Not checked yet" FontSize="21" FontWeight="Bold" Foreground="White" TextWrapping="Wrap"/>
                <TextBlock x:Name="SyncSubHead" Text="Nothing is checked until you press Check (or Smart sync) - and nothing is sent until you confirm." Foreground="$($Pal.Dim)" FontSize="12.5" TextWrapping="Wrap" Margin="0,2,0,0"/>
              </StackPanel>
            </DockPanel>
          </Border>
          <!-- time strip (oct. 21 2026): when this laptop last sent / received / updated / pushed code -->
          <ItemsControl x:Name="SyncTimes" DockPanel.Dock="Top" Margin="0,0,0,10">
            <ItemsControl.ItemsPanel><ItemsPanelTemplate><UniformGrid Rows="1"/></ItemsPanelTemplate></ItemsControl.ItemsPanel>
            <ItemsControl.ItemTemplate>
              <DataTemplate>
                <Border Background="$($Pal.Card)" CornerRadius="12" Padding="10,6" Margin="0,0,8,0" ToolTip="{Binding Tip}">
                  <DockPanel>
                    <TextBlock DockPanel.Dock="Left" Text="{Binding Glyph}" FontFamily="Segoe MDL2 Assets" FontSize="18" Foreground="{Binding Fg}" VerticalAlignment="Center" Margin="0,0,10,0"/>
                    <StackPanel>
                      <TextBlock Text="{Binding Name}" Foreground="$($Pal.Dim)" FontSize="11"/>
                      <TextBlock Text="{Binding When}" Foreground="$($Pal.Text)" FontWeight="SemiBold" FontSize="12.5" TextTrimming="CharacterEllipsis"/>
                      <TextBlock Text="{Binding Ago}" Foreground="{Binding Fg}" FontSize="11" TextTrimming="CharacterEllipsis"/>
                    </StackPanel>
                  </DockPanel>
                </Border>
              </DataTemplate>
            </ItemsControl.ItemTemplate>
          </ItemsControl>
          <!-- stepper -->
          <ItemsControl x:Name="SyncSteps" DockPanel.Dock="Top" Margin="0,0,0,10">
            <ItemsControl.ItemsPanel><ItemsPanelTemplate><UniformGrid Rows="1"/></ItemsPanelTemplate></ItemsControl.ItemsPanel>
            <ItemsControl.ItemTemplate>
              <DataTemplate>
                <Border Background="{Binding Bg}" BorderBrush="{Binding Edge}" BorderThickness="1.5" CornerRadius="12" Padding="10,7" Margin="0,0,8,0" ToolTip="{Binding Tip}">
                  <DockPanel>
                    <Border DockPanel.Dock="Left" Width="24" Height="24" CornerRadius="12" Background="{Binding Dot}" Margin="0,0,8,0">
                      <TextBlock Text="{Binding Mark}" Foreground="#0B1020" FontWeight="Bold" FontSize="12" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                    </Border>
                    <StackPanel>
                      <TextBlock Text="{Binding Name}" Foreground="$($Pal.Text)" FontWeight="SemiBold" FontSize="12.5"/>
                      <TextBlock Text="{Binding Info}" Foreground="{Binding InfoFg}" FontSize="11" TextTrimming="CharacterEllipsis"/>
                    </StackPanel>
                  </DockPanel>
                </Border>
              </DataTemplate>
            </ItemsControl.ItemTemplate>
          </ItemsControl>
          <!-- health chips -->
          <ItemsControl x:Name="SyncChips" DockPanel.Dock="Top" Margin="0,0,0,6">
            <ItemsControl.ItemsPanel><ItemsPanelTemplate><WrapPanel/></ItemsPanelTemplate></ItemsControl.ItemsPanel>
            <ItemsControl.ItemTemplate>
              <DataTemplate>
                <Border Background="{Binding Bg}" CornerRadius="10" Padding="10,3" Margin="0,0,6,6" ToolTip="{Binding Tip}">
                  <TextBlock Text="{Binding Text}" Foreground="{Binding Fg}" FontSize="11.5" FontWeight="SemiBold"/>
                </Border>
              </DataTemplate>
            </ItemsControl.ItemTemplate>
          </ItemsControl>
          <!-- banners: blocked (red) / analyse first (amber) -->
          <Border x:Name="SyncBlock" DockPanel.Dock="Top" Visibility="Collapsed" Background="#3A1E2C" BorderBrush="$($Pal.Red)" BorderThickness="1" CornerRadius="12" Padding="14,10" Margin="0,0,0,10">
            <DockPanel>
              <Button x:Name="SyncAbortMerge" DockPanel.Dock="Right" Style="{StaticResource Danger}" Content="Abort unfinished merge" Margin="10,0,0,0" Visibility="Collapsed"
                      ToolTip="git merge --abort: back to your last commit. Every changed file is copied to the backup folder first."/>
              <TextBlock x:Name="SyncBlockText" Foreground="$($Pal.Red)" TextWrapping="Wrap" VerticalAlignment="Center"/>
            </DockPanel>
          </Border>
          <Border x:Name="SyncGate" DockPanel.Dock="Top" Visibility="Collapsed" Background="#3A2E14" BorderBrush="$($Pal.Amber)" BorderThickness="1" CornerRadius="12" Padding="14,10" Margin="0,0,0,10">
            <DockPanel>
              <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center">
                <Button x:Name="SyncGateAna" Style="{StaticResource Primary}" Content="Analyse them first  &#x2192;" Margin="10,0,8,0"/>
                <Button x:Name="SyncGateSkip" Content="Send without analysis" Margin="0"
                        ToolTip="The captures go up; their stale analysis stays on this laptop (never sent). Teammates will see 'not analysed'."/>
              </StackPanel>
              <StackPanel>
                <TextBlock x:Name="SyncGateHead" Foreground="$($Pal.Amber)" FontWeight="Bold" TextWrapping="Wrap"/>
                <TextBlock x:Name="SyncGateText" Foreground="$($Pal.Text)" TextWrapping="Wrap" FontSize="12" Margin="0,2,0,0"/>
              </StackPanel>
            </DockPanel>
          </Border>
          <!-- bottom actions -->
          <DockPanel DockPanel.Dock="Bottom" Margin="0,10,0,0">
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal">
              <CheckBox x:Name="SyncUpdate" Content="also update my folder" IsChecked="True" VerticalAlignment="Center" Margin="0,0,14,0"
                        ToolTip="After sending / receiving, bring this folder up to GitHub's latest commit (the safe way: backs up anything in the way, merges your code edits, never leaves a half-done merge)."/>
              <Button x:Name="SyncSendOnly" Content="Send ticked only"/>
              <Button x:Name="SyncRecvOnly" Content="Receive ticked only"/>
              <Button x:Name="SyncFoldOnly" Content="Update my folder only" Margin="0"/>
            </StackPanel>
            <StackPanel Orientation="Horizontal">
              <Button x:Name="SyncBackups" Content="Backups folder" Padding="10,4"/>
              <Button x:Name="SyncAdvanced2" Content="Delete / restore on GitHub..." Padding="10,4"/>
              <TextBlock x:Name="SyncFoot" Foreground="$($Pal.Faint)" FontSize="11" VerticalAlignment="Center" Margin="6,0,0,0" TextWrapping="Wrap"/>
            </StackPanel>
          </DockPanel>
          <TabControl x:Name="SyncTabs" Background="Transparent" BorderThickness="0" ItemContainerStyle="{StaticResource SubTab}">
            <TabItem x:Name="SyncTabSend" Header="  Send  ">
              <DockPanel Margin="0,10,0,0">
                <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,6">
                  <Button x:Name="SyncSendAll" Content="tick all" Padding="10,3"/>
                  <Button x:Name="SyncSendNone" Content="tick none" Padding="10,3"/>
                  <TextBlock x:Name="SyncSendInfo" Foreground="$($Pal.Dim)" VerticalAlignment="Center" Margin="6,0,0,8" TextWrapping="Wrap"/>
                </StackPanel>
                <DataGrid x:Name="SyncSendGrid" IsReadOnly="False" CanUserAddRows="False" AutoGenerateColumns="False" HeadersVisibility="Column" SelectionMode="Single">
                      <DataGrid.Columns>
                        <DataGridTemplateColumn Header="" Width="44" MinWidth="44" CanUserResize="False">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><CheckBox Style="{StaticResource TickBox}" IsChecked="{Binding Pick, UpdateSourceTrigger=PropertyChanged}" Margin="0"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="status" Width="150">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate>
                              <Border Background="{Binding BadgeBg}" CornerRadius="8" Padding="8,1" HorizontalAlignment="Left" ToolTip="{Binding Why}">
                                <TextBlock Text="{Binding Badge}" Foreground="{Binding BadgeFg}" FontWeight="Bold" FontSize="11"/>
                              </Border>
                            </DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="what" Width="88">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock Text="{Binding Area}" Foreground="{Binding AreaFg}" FontWeight="SemiBold"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="run" Width="300">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock><Run Text="{Binding CAtk, Mode=OneWay}" Foreground="{Binding AtkFg, Mode=OneWay}" FontWeight="SemiBold"/><Run Text="{Binding CRest, Mode=OneWay}" Foreground="$($Pal.Text)"/></TextBlock></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="file" Binding="{Binding File}" Width="*" MinWidth="220" FontFamily="Cascadia Mono, Consolas" FontSize="11.5"/>
                        <DataGridTemplateColumn Header="here (changed)" Width="112" SortMemberPath="HereAt">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock Text="{Binding HereT}" Foreground="$($Pal.Dim)" ToolTip="When this laptop's copy last changed (after a receive: the receive time)"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="on GitHub since" Width="112" SortMemberPath="HubAt">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock Text="{Binding HubT}" Foreground="$($Pal.Dim)" ToolTip="{Binding HubTip}"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="analysis" Width="130">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate>
                              <Border Background="{Binding AnaBg}" CornerRadius="8" Padding="8,1" HorizontalAlignment="Left" ToolTip="{Binding Why}">
                                <TextBlock Text="{Binding Ana}" Foreground="{Binding AnaFg}" FontWeight="Bold" FontSize="11"/>
                              </Border>
                            </DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="why" Binding="{Binding Why}" Width="2*" Foreground="$($Pal.Dim)"/>
                      </DataGrid.Columns>
                    </DataGrid>
              </DockPanel>
            </TabItem>
            <TabItem x:Name="SyncTabRecv" Header="  Receive  ">
              <DockPanel Margin="0,10,0,0">
                <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,6">
                  <Button x:Name="SyncRecvAll" Content="tick all" Padding="10,3"/>
                  <Button x:Name="SyncRecvNone" Content="tick none" Padding="10,3"/>
                  <TextBlock x:Name="SyncRecvInfo" Foreground="$($Pal.Dim)" VerticalAlignment="Center" Margin="6,0,0,8" TextWrapping="Wrap"/>
                </StackPanel>
                <DataGrid x:Name="SyncRecvGrid" IsReadOnly="False" CanUserAddRows="False" AutoGenerateColumns="False" HeadersVisibility="Column" SelectionMode="Single">
                      <DataGrid.Columns>
                        <DataGridTemplateColumn Header="" Width="44" MinWidth="44" CanUserResize="False">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><CheckBox Style="{StaticResource TickBox}" IsChecked="{Binding Pick, UpdateSourceTrigger=PropertyChanged}" Margin="0"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="status" Width="150">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate>
                              <Border Background="{Binding BadgeBg}" CornerRadius="8" Padding="8,1" HorizontalAlignment="Left" ToolTip="{Binding Why}">
                                <TextBlock Text="{Binding Badge}" Foreground="{Binding BadgeFg}" FontWeight="Bold" FontSize="11"/>
                              </Border>
                            </DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="what" Width="88">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock Text="{Binding Area}" Foreground="{Binding AreaFg}" FontWeight="SemiBold"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="run" Width="300">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock><Run Text="{Binding CAtk, Mode=OneWay}" Foreground="{Binding AtkFg, Mode=OneWay}" FontWeight="SemiBold"/><Run Text="{Binding CRest, Mode=OneWay}" Foreground="$($Pal.Text)"/></TextBlock></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="file" Binding="{Binding File}" Width="*" MinWidth="220" FontFamily="Cascadia Mono, Consolas" FontSize="11.5"/>
                        <DataGridTemplateColumn Header="here (changed)" Width="112" SortMemberPath="HereAt">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock Text="{Binding HereT}" Foreground="$($Pal.Dim)" ToolTip="When this laptop's copy last changed (after a receive: the receive time)"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="on GitHub since" Width="112" SortMemberPath="HubAt">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock Text="{Binding HubT}" Foreground="$($Pal.Dim)" ToolTip="{Binding HubTip}"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="from" Binding="{Binding Who}" Width="150" Foreground="$($Pal.Dim)"/>
                        <DataGridTextColumn Header="why" Binding="{Binding Why}" Width="2*" Foreground="$($Pal.Dim)"/>
                      </DataGrid.Columns>
                    </DataGrid>
              </DockPanel>
            </TabItem>
            <TabItem x:Name="SyncTabHeld" Header="  Held back  ">
              <DockPanel Margin="0,10,0,0">
                <TextBlock DockPanel.Dock="Top" Foreground="$($Pal.Dim)" TextWrapping="Wrap" Margin="0,0,0,8" Text="Files the sync will NOT move, and why - stale analysis, duplicates of something GitHub already has, files a teammate deleted, an equivalent analysis already there. Hover a badge for the detail."/>
                <DataGrid x:Name="SyncHeldGrid" IsReadOnly="True" CanUserAddRows="False" AutoGenerateColumns="False" HeadersVisibility="Column" SelectionMode="Single">
                      <DataGrid.Columns>
                        <DataGridTemplateColumn Header="held back" Width="170">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate>
                              <Border Background="{Binding BadgeBg}" CornerRadius="8" Padding="8,1" HorizontalAlignment="Left" ToolTip="{Binding Why}">
                                <TextBlock Text="{Binding Badge}" Foreground="{Binding BadgeFg}" FontWeight="Bold" FontSize="11"/>
                              </Border>
                            </DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="what" Width="88">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock Text="{Binding Area}" Foreground="{Binding AreaFg}" FontWeight="SemiBold"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="run" Width="300">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock><Run Text="{Binding CAtk, Mode=OneWay}" Foreground="{Binding AtkFg, Mode=OneWay}" FontWeight="SemiBold"/><Run Text="{Binding CRest, Mode=OneWay}" Foreground="$($Pal.Text)"/></TextBlock></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="file" Binding="{Binding File}" Width="*" MinWidth="220" FontFamily="Cascadia Mono, Consolas" FontSize="11.5"/>
                        <DataGridTemplateColumn Header="here (changed)" Width="112" SortMemberPath="HereAt">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock Text="{Binding HereT}" Foreground="$($Pal.Dim)" ToolTip="When this laptop's copy last changed (after a receive: the receive time)"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="on GitHub since" Width="112" SortMemberPath="HubAt">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock Text="{Binding HubT}" Foreground="$($Pal.Dim)" ToolTip="{Binding HubTip}"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="why" Binding="{Binding Why}" Width="2*" Foreground="$($Pal.Dim)"/>
                      </DataGrid.Columns>
                    </DataGrid>
              </DockPanel>
            </TabItem>
            <TabItem x:Name="SyncTabRuns" Header="  Runs  ">
              <DockPanel Margin="0,10,0,0">
                <TextBlock DockPanel.Dock="Top" Foreground="$($Pal.Dim)" TextWrapping="Wrap" Margin="0,0,0,8" Text="Every run, here and on GitHub. Analysis is CURRENT only when its feature table covers every capture of that run (checked by content - file times lie after a pull)."/>
                <DataGrid x:Name="SyncRunsGrid" IsReadOnly="True" CanUserAddRows="False" AutoGenerateColumns="False" HeadersVisibility="Column" SelectionMode="Single">
                      <DataGrid.Columns>
                        <DataGridTemplateColumn Header="run" Width="300">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock><Run Text="{Binding CAtk, Mode=OneWay}" Foreground="{Binding AtkFg, Mode=OneWay}" FontWeight="SemiBold"/><Run Text="{Binding CRest, Mode=OneWay}" Foreground="$($Pal.Text)"/></TextBlock></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="boards here" Binding="{Binding Here}" Width="95"/>
                        <DataGridTextColumn Header="on GitHub" Binding="{Binding Hub}" Width="85"/>
                        <DataGridTemplateColumn Header="analysis here" Width="140">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate>
                              <Border Background="{Binding AnaLBg}" CornerRadius="8" Padding="8,1" HorizontalAlignment="Left" ToolTip="{Binding Why}">
                                <TextBlock Text="{Binding AnaL}" Foreground="{Binding AnaLFg}" FontWeight="Bold" FontSize="11"/>
                              </Border>
                            </DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="analysis on GitHub" Width="150">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate>
                              <Border Background="{Binding AnaRBg}" CornerRadius="8" Padding="8,1" HorizontalAlignment="Left" ToolTip="{Binding Why}">
                                <TextBlock Text="{Binding AnaR}" Foreground="{Binding AnaRFg}" FontWeight="Bold" FontSize="11"/>
                              </Border>
                            </DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="what to do" Binding="{Binding Note}" Width="*" Foreground="$($Pal.Dim)"/>
                      </DataGrid.Columns>
                    </DataGrid>
              </DockPanel>
            </TabItem>
            <TabItem x:Name="SyncTabFold" Header="  Your folder  ">
              <DockPanel Margin="0,10,0,0">
                <Border DockPanel.Dock="Top" Style="{StaticResource Card}" Padding="14,10" Margin="0,0,0,10">
                  <TextBlock x:Name="SyncFoldText" Foreground="$($Pal.Text)" TextWrapping="Wrap"/>
                </Border>
                <DataGrid x:Name="SyncFoldGrid" IsReadOnly="True" CanUserAddRows="False" AutoGenerateColumns="False" HeadersVisibility="Column" SelectionMode="Single">
                      <DataGrid.Columns>
                        <DataGridTemplateColumn Header="how" Width="150">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate>
                              <Border Background="{Binding BadgeBg}" CornerRadius="8" Padding="8,1" HorizontalAlignment="Left" ToolTip="{Binding Why}">
                                <TextBlock Text="{Binding Badge}" Foreground="{Binding BadgeFg}" FontWeight="Bold" FontSize="11"/>
                              </Border>
                            </DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="file in the way" Binding="{Binding File}" Width="*" FontFamily="Cascadia Mono, Consolas" FontSize="11.5"/>
                        <DataGridTextColumn Header="why" Binding="{Binding Why}" Width="2*" Foreground="$($Pal.Dim)"/>
                      </DataGrid.Columns>
                    </DataGrid>
              </DockPanel>
            </TabItem>
            <TabItem x:Name="SyncTabGone" Header="  Cleanup  ">
              <DockPanel Margin="0,10,0,0">
                <TextBlock DockPanel.Dock="Top" Foreground="$($Pal.Dim)" TextWrapping="Wrap" Margin="0,0,0,8" Text="Teammates deleted these on GitHub; your copies are byte-identical to GitHub's history, so removing them is undoable (they go to the backups folder, and Restore can bring them back). Never ticked by itself."/>
                <DataGrid x:Name="SyncGoneGrid" IsReadOnly="False" CanUserAddRows="False" AutoGenerateColumns="False" HeadersVisibility="Column" SelectionMode="Single">
                      <DataGrid.Columns>
                        <DataGridTemplateColumn Header="" Width="44" MinWidth="44" CanUserResize="False">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><CheckBox Style="{StaticResource TickBox}" IsChecked="{Binding Pick, UpdateSourceTrigger=PropertyChanged}" Margin="0"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="status" Width="170">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate>
                              <Border Background="{Binding BadgeBg}" CornerRadius="8" Padding="8,1" HorizontalAlignment="Left" ToolTip="{Binding Why}">
                                <TextBlock Text="{Binding Badge}" Foreground="{Binding BadgeFg}" FontWeight="Bold" FontSize="11"/>
                              </Border>
                            </DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="what" Width="88">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock Text="{Binding Area}" Foreground="{Binding AreaFg}" FontWeight="SemiBold"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="run" Width="300">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock><Run Text="{Binding CAtk, Mode=OneWay}" Foreground="{Binding AtkFg, Mode=OneWay}" FontWeight="SemiBold"/><Run Text="{Binding CRest, Mode=OneWay}" Foreground="$($Pal.Text)"/></TextBlock></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="file" Binding="{Binding File}" Width="*" MinWidth="220" FontFamily="Cascadia Mono, Consolas" FontSize="11.5"/>
                        <DataGridTemplateColumn Header="here (changed)" Width="112" SortMemberPath="HereAt">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock Text="{Binding HereT}" Foreground="$($Pal.Dim)" ToolTip="When this laptop's copy last changed (after a receive: the receive time)"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTemplateColumn Header="on GitHub since" Width="112" SortMemberPath="HubAt">
                          <DataGridTemplateColumn.CellTemplate>
                            <DataTemplate><TextBlock Text="{Binding HubT}" Foreground="$($Pal.Dim)" ToolTip="{Binding HubTip}"/></DataTemplate>
                          </DataGridTemplateColumn.CellTemplate>
                        </DataGridTemplateColumn>
                        <DataGridTextColumn Header="why" Binding="{Binding Why}" Width="2*" Foreground="$($Pal.Dim)"/>
                      </DataGrid.Columns>
                    </DataGrid>
              </DockPanel>
            </TabItem>
          </TabControl>
        </DockPanel>
      </TabItem>
    </TabControl>
  </DockPanel>
  <!-- toast: short pop-up for plug / unplug and finished tasks -->
  <Border x:Name="Toast" HorizontalAlignment="Right" VerticalAlignment="Bottom" Margin="0,0,24,64" CornerRadius="14" Padding="16,12"
          Background="$($Pal.Card2)" BorderBrush="$($Pal.Accent)" BorderThickness="1" Opacity="0" IsHitTestVisible="False" MaxWidth="420">
    <Border.Effect><DropShadowEffect BlurRadius="24" ShadowDepth="4" Opacity="0.5" Color="#000000"/></Border.Effect>
    <StackPanel Orientation="Horizontal">
      <Border x:Name="ToastIconBg" Width="30" Height="30" CornerRadius="15" Background="{StaticResource GradGood}" VerticalAlignment="Top">
        <TextBlock x:Name="ToastIcon" Text="&#xE88E;" FontFamily="Segoe MDL2 Assets" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <StackPanel Margin="12,0,0,0" MaxWidth="340">
        <TextBlock x:Name="ToastTitle" FontWeight="SemiBold" FontSize="14" Text=""/>
        <TextBlock x:Name="ToastText" Foreground="$($Pal.Dim)" TextWrapping="Wrap" Text=""/>
        <TextBlock x:Name="ToastAction" Foreground="$($Pal.Cyan)" FontWeight="SemiBold" Margin="0,4,0,0" Visibility="Collapsed"/>
      </StackPanel>
    </StackPanel>
  </Border>
  <!-- Ctrl+K: jump to / do anything -->
  <Grid x:Name="Palette" Visibility="Collapsed" Background="#B30A0B14">
    <Border VerticalAlignment="Top" HorizontalAlignment="Center" Margin="0,90,0,0" Width="640" CornerRadius="18" Background="$($Pal.Card)"
            BorderBrush="$($Pal.Accent)" BorderThickness="1" Padding="10">
      <Border.Effect><DropShadowEffect BlurRadius="40" ShadowDepth="6" Opacity="0.6" Color="#000000"/></Border.Effect>
      <StackPanel>
        <Grid>
          <TextBox x:Name="PalText" FontSize="17" Padding="40,10,10,10" Margin="0" Background="$($Pal.Card2)" BorderBrush="Transparent"/>
          <TextBlock Text="&#xE721;" FontFamily="Segoe MDL2 Assets" FontSize="16" Foreground="$($Pal.Pink)" VerticalAlignment="Center" Margin="14,0,0,0" IsHitTestVisible="False"/>
          <TextBlock x:Name="PalHint" Text="Type to search - pages, actions, presets, campaign runs..." FontSize="15" Foreground="$($Pal.Faint)" VerticalAlignment="Center" Margin="41,0,0,0" IsHitTestVisible="False"/>
        </Grid>
        <ListBox x:Name="PalList" Background="Transparent" BorderThickness="0" Margin="0,8,0,0" MaxHeight="420" ScrollViewer.HorizontalScrollBarVisibility="Disabled">
          <ListBox.ItemContainerStyle>
            <Style TargetType="ListBoxItem">
              <Setter Property="Cursor" Value="Hand"/>
              <Setter Property="Template">
                <Setter.Value>
                  <ControlTemplate TargetType="ListBoxItem">
                    <Border x:Name="b" CornerRadius="10" Padding="12,8" Margin="0,1" Background="Transparent">
                      <ContentPresenter/>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="b" Property="Background" Value="$($Pal.Hover)"/></Trigger>
                      <Trigger Property="IsSelected" Value="True"><Setter TargetName="b" Property="Background" Value="#3B2F6B"/></Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </Setter.Value>
              </Setter>
            </Style>
          </ListBox.ItemContainerStyle>
          <ListBox.ItemTemplate>
            <DataTemplate>
              <DockPanel>
                <Border DockPanel.Dock="Left" Width="30" Height="30" CornerRadius="9" Background="{Binding IconBg}" Margin="0,0,12,0">
                  <TextBlock Text="{Binding Glyph}" FontFamily="Segoe MDL2 Assets" Foreground="{Binding IconFg}" HorizontalAlignment="Center" VerticalAlignment="Center"/>
                </Border>
                <TextBlock DockPanel.Dock="Right" Text="{Binding Kind}" Foreground="$($Pal.Faint)" FontSize="11" VerticalAlignment="Center"/>
                <StackPanel VerticalAlignment="Center">
                  <TextBlock Text="{Binding Title}" Foreground="$($Pal.Text)" FontWeight="SemiBold"/>
                  <TextBlock Text="{Binding Sub}" Foreground="$($Pal.Dim)" FontSize="11" TextTrimming="CharacterEllipsis"/>
                </StackPanel>
              </DockPanel>
            </DataTemplate>
          </ListBox.ItemTemplate>
        </ListBox>
        <TextBlock Text="Enter = go   ·   arrows = move   ·   Esc = close   ·   Ctrl+1..8 = pages   ·   F5 = refresh   ·   Ctrl+N = new preset" Foreground="$($Pal.Faint)" FontSize="11" Margin="8,8,0,2"/>
      </StackPanel>
    </Border>
  </Grid>
  </Grid>
</Window>
"@

$win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xaml))
$ui = @{}
$xaml.SelectNodes('//*[@*[local-name()="Name"]]') | ForEach-Object {
    $n = $_.Attributes | Where-Object { $_.LocalName -eq 'Name' } | Select-Object -First 1
    if ($n) { $ui[$n.Value] = $win.FindName($n.Value) }
}
$brush = { param([string]$Hex) (New-Object Windows.Media.BrushConverter).ConvertFromString($Hex) }

function Set-Status([string]$Text, [string]$Hex = $Pal.Dim) {
    $ui.Status.Text = $Text
    $ui.Status.Foreground = & $brush $Hex
}

# ── navigation ────────────────────────────────────────────────────────────────
$nav = @('NavHome', 'NavCapture', 'NavVerify', 'NavCampaign', 'NavBoards', 'NavData', 'NavWire', 'NavRun', 'NavSync')
for ($i = 0; $i -lt $nav.Count; $i++) {
    $idx = $i
    $ui[$nav[$i]].Add_Checked({ $ui.Pages.SelectedIndex = $idx }.GetNewClosure())
}
function Show-Page([int]$I) { $ui[$nav[$I]].IsChecked = $true }

if ($DryRun) { $ui.DryRun.IsChecked = $true }
$script:Py = Find-PandasPython
$idf = [bool](Get-Command idf.py -ErrorAction SilentlyContinue) -or [bool]$env:IDF_PATH
$ui.EnvInfo.Text = ("python+pandas: {0}`nESP-IDF: {1}" -f $(if ($script:Py) { $script:Py } else { 'NOT FOUND' }),
    $(if ($idf) { 'ready' } else { 'not in this window - start from the ESP-IDF PowerShell to flash' }))

function Get-WizardArgs { if ($ui.DryRun.IsChecked) { @('-DryRun') } else { @() } }
$ui.OpenCli.Add_Click({ Start-ConsoleWindow -Script (Join-Path $base 'run_wizard.ps1') -ScriptArgs (Get-WizardArgs) -Title 'NIS16 wizard (CLI)'; Set-Status 'Opened the CLI wizard in a new window.' })

# ── little UI helpers: toast, page fade, activity pane ───────────────────────
$script:ToastAction = $null
$toastTimer = New-Object Windows.Threading.DispatcherTimer
$toastTimer.Interval = [TimeSpan]::FromSeconds(6)
$toastTimer.Add_Tick({ $toastTimer.Stop(); $ui.Toast.IsHitTestVisible = $false; $script:ToastAction = $null })
$ui.Toast.Cursor = 'Hand'
$ui.Toast.Add_MouseLeftButtonUp({
    $a = $script:ToastAction; $script:ToastAction = $null
    $ui.Toast.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Fade 1 0 150)); $ui.Toast.IsHitTestVisible = $false
    if ($a) { & $a }
})
function Show-Toast([string]$Title, [string]$Text = '', [string]$Glyph = [string][char]0xE88E, [string]$Fill = 'GradGood',
                    [scriptblock]$Action = $null, [string]$ActionText = '') {
    # -Action: the toast becomes clickable for a few seconds ("Import it ->")
    $script:ToastAction = $Action
    $ui.ToastAction.Text = $(if ($Action) { $(if ($ActionText) { $ActionText } else { 'Click to open' }) + '  ' + [char]0x2192 } else { '' })
    $ui.ToastAction.Visibility = $(if ($Action) { 'Visible' } else { 'Collapsed' })
    $ui.Toast.IsHitTestVisible = [bool]$Action
    $toastTimer.Stop(); $toastTimer.Interval = [TimeSpan]::FromSeconds($(if ($Action) { 8 } else { 4 })); $toastTimer.Start()
    $ui.ToastTitle.Text = $Title; $ui.ToastText.Text = $Text
    $ui.ToastText.Visibility = $(if ($Text) { 'Visible' } else { 'Collapsed' })
    $ui.ToastIcon.Text = $Glyph
    $ui.ToastIconBg.Background = $(if ($Fill -like '#*') { & $brush $Fill } else { $win.FindResource($Fill) })
    $a = New-Object Windows.Media.Animation.DoubleAnimationUsingKeyFrames
    foreach ($kf in @(@(0, 0), @(0.18, 1), @(3.6, 1), @(4.1, 0))) {
        [void]$a.KeyFrames.Add((New-Object Windows.Media.Animation.LinearDoubleKeyFrame $kf[1], ([Windows.Media.Animation.KeyTime]::FromTimeSpan([TimeSpan]::FromSeconds($kf[0])))))
    }
    $ui.Toast.BeginAnimation([Windows.UIElement]::OpacityProperty, $a)
}
function New-Fade([double]$From, [double]$To, [double]$Ms) {
    $a = New-Object Windows.Media.Animation.DoubleAnimation $From, $To, ([Windows.Duration][TimeSpan]::FromMilliseconds($Ms))
    $a.EasingFunction = New-Object Windows.Media.Animation.CubicEase
    return $a
}
# gentle fade + slide whenever the page changes (ComboBox / DataGrid selection
# events bubble up to here too - only react to the page TabControl itself)
$ui.Pages.RenderTransform = New-Object Windows.Media.TranslateTransform
$ui.Pages.Add_SelectionChanged({
    param($s, $e)
    if ($e.OriginalSource -ne $ui.Pages) { return }
    $ui.Pages.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Fade 0 1 220))
    $ui.Pages.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::YProperty, (New-Fade 14 0 260))
})
$ui.ToggleActivity.Add_Click({
    $show = $ui.ActivityPane.Visibility -ne 'Visible'
    $ui.ActivityPane.Visibility = $(if ($show) { 'Visible' } else { 'Collapsed' })
    $ui.ToggleActivity.Content = $(if ($show) { 'Hide activity' } else { 'Show activity' })
})

# ── LIVE BOARDS: plug a board in and it shows up everywhere (oct. 17 2026) ───
# A 1.5 s timer compares the COM port list (cheap). On a change the ports are
# re-classified with the CLI's own Get-PortList (BRIDGE / BLOCKED / UNKNOWN)
# and each NEW bridge port gets its MAC read by tools\Get-EspMac.ps1 in the
# background (esptool read_mac - resets that board for ~2 s, nothing else).
# Safety: auto-read never runs while a capture / tool window started from
# here is still open, or while a task streams in the activity pane (the
# BSOD rule - never reset a board that is being read), and never on a
# BLOCKED / UNKNOWN port. One read at a time.
$script:Live = [ordered]@{}
$script:LiveNames = ''
$script:Consoles = New-Object System.Collections.ArrayList
$script:SeenMacs = @{}   # full MAC -> port, every board read this session
function Test-IsSnifferStream { $script:Stream -and [string]$script:Stream.Title -match '^Sniffer recording' }
function Get-SnifferPorts([int]$MaxAgeS = 0) {
    # A sniffer only holds ITS OWN port and needs nothing from the other boards,
    # so it must not block identifying them (oct. 17 2026: a sniffer left
    # recording made every MAC read say 'not now'). Only its port is skipped.
    $ports = @{}
    try {
        # gui\Perf.ps1: one shared process list (MaxAgeS > 0 = may be up to that old)
        foreach ($p in @(Get-ProcRows $MaxAgeS | Where-Object { $_.Name -match '^(?i)py(thon)?\.exe$' -and $_.CommandLine -match '(?i)sniff\.py' })) {
            if ($p.CommandLine -match '(?i)--port\s+"?(COM\d+)') { $ports[$Matches[1].ToUpper()] = $true }
        }
    } catch { }
    return $ports
}
function Test-HandsOff([int]$MaxAgeS = 0) {
    foreach ($p in @($script:Consoles)) { if (-not $p.HasExited) { return 'a capture / tool window opened from this GUI is still open - close it first' } }
    if ($script:Stream -and -not (Test-IsSnifferStream)) { return ("'{0}' is still running in the activity pane - wait for it to finish" -f $script:Stream.Title) }
    if ($script:Run -and $script:Run.Active) { return 'a capture is running on the Live run page' }
    # a capture / monitor / export started OUTSIDE this GUI (the CLI, a second
    # window) - its boards must not be reset either. Named, so the user knows
    # WHICH window to look for.
    try {
        $busy = @(Get-ProcRows $MaxAgeS |
            # idf.py / esptool only count when they name a COM port: a plain 'idf.py build'
            # touches no board (oct. 19 2026: a background compile blocked 'Identify all')
            Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '(?i)run_wizard|(?<![\w-])run\.ps1|menu\.ps1|idf\.py|idf_monitor|gui_monitor|export_logs|import_sdcard|esptool' -and -not ($_.CommandLine -match '(?i)idf\.py|esptool' -and $_.CommandLine -notmatch '(?i)idf_monitor|COM\d+') -and $_.CommandLine -notmatch '(?i)Get-EspMac|sniff\.py' })
        if ($busy.Count) {
            $c = [string]$busy[0].CommandLine
            $what = switch -Regex ($c) {
                '(?i)export_logs|import_sdcard' { 'an export / SD import'; break }
                '(?i)gui_monitor|idf_monitor'    { 'a board monitor'; break }
                '(?i)run_wizard|menu\.ps1'       { 'the CLI wizard'; break }
                '(?i)run\.ps1'                   { 'a capture (run.ps1)'; break }
                '(?i)idf\.py|esptool'            { 'a flash / compile'; break }
                default                          { 'a board tool' }
            }
            $port = if ($c -match '(?i)(COM\d+)') { " on $($Matches[1].ToUpper())" } else { '' }
            return ("{0}{1} is running in another window (process {2}) - let it finish or close that window first" -f $what, $port, $busy[0].ProcessId)
        }
    } catch { }
    return $null
}
function Get-MemberInfo {
    # first:last (lowercase) -> @{ Who = 'nickname [Owner]'; Nick; Role }
    $out = @{}
    try {
        foreach ($m in (Get-Content (Join-Path $base 'member_boards.json') -Raw | ConvertFrom-Json).members) {
            foreach ($b in $m.boards) {
                $k = (Get-ShortMac ([string]$b.mac)).ToLower()
                $out[$k] = @{ Who = ("{0} [{1}]" -f $b.nickname, $m.name); Nick = [string]$b.nickname; Role = [string]$b.role; Owner = [string]$m.name }
            }
        }
    } catch { }
    return $out
}
function Get-BoardCatalog {
    # Every board known by its FULL MAC: plugged in now first, then any MAC
    # saved in a preset. Display = what the MAC drop-downs show.
    $info = Get-MemberInfo
    $cat = [ordered]@{}
    foreach ($r in $script:Live.Values) {
        if ($r.Mac -and -not $cat.Contains($r.Mac)) { $cat[$r.Mac] = @{ Mac = $r.Mac; Port = $r.Port; Live = $true } }
    }
    if (-not $script:Presets) { $script:Presets = Get-Presets }
    foreach ($p in $script:Presets) {
        foreach ($b in @($p.Cfg.boards)) {
            $m = ([string]$b.Mac).ToLower()
            if ($m -match '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' -and -not $cat.Contains($m)) { $cat[$m] = @{ Mac = $m; Port = ''; Live = $false } }
        }
    }
    foreach ($e in $cat.Values) {
        $i = $info[(Get-ShortMac $e.Mac).ToLower()]
        [pscustomobject]@{
            Mac = $e.Mac; Port = $e.Port; Live = $e.Live
            Who = $(if ($i) { $i.Who } else { 'not in the member list' }); Nick = $(if ($i) { $i.Nick } else { '' })
            MemberRole = $(if ($i) { $i.Role } else { 'child' })
            Display = ('{0}    {1}    {2}' -f $e.Mac, $(if ($i) { $i.Who } else { '(unknown board)' }), $(if ($e.Live) { "plugged in on $($e.Port)" } else { 'not plugged in' }))
        }
    }
}
function Get-LiveMacs {
    # full MAC -> port, for the boards plugged in now whose MAC is read
    $m = @{}; foreach ($r in $script:Live.Values) { if ($r.Mac) { $m[$r.Mac] = $r.Port } }; return $m
}
function Get-LivePortList([string[]]$Names) {
    # Same rows as the wizard's Get-PortList, but a port seen before keeps its
    # description: Windows is asked (CIM, ~0.3-0.5 s, froze the window on every
    # plug / unplug) only when a NEW port name shows up (oct. 18 2026).
    $desc = @{}
    $new = @($Names | Where-Object { -not $script:Live.Contains($_) })
    if ($new.Count) {
        foreach ($q in @("PNPClass = 'Ports'", '')) {
            try {
                $cim = if ($q) { Get-CimInstance -ClassName Win32_PnPEntity -Filter $q -ErrorAction SilentlyContinue } else { Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue }
                foreach ($d in @($cim)) { if ($d.Name -match '\((COM\d+)\)') { $desc[$Matches[1]] = ($d.Name -replace '\s*\(COM\d+\)\s*$', '') } }
            } catch { }
            if (-not @($new | Where-Object { -not $desc[$_] }).Count) { break }   # all found - skip the slow full list
        }
    }
    foreach ($n in $Names) {
        $d = if ($script:Live.Contains($n) -and $script:Live[$n].Description) { $script:Live[$n].Description } elseif ($desc[$n]) { $desc[$n] } else { 'unknown device' }
        [pscustomobject]@{ Port = $n; Description = $d; Kind = (Get-PortKind -Description $d) }
    }
}
function Update-LivePorts([switch]$Force) {
    $names = @(try { [IO.Ports.SerialPort]::GetPortNames() | Sort-Object -Unique } catch { })
    # -SelfTest only ever sees its own stand-in ports (COM96+): a real board plugged
    # into this laptop is never listed, read, watched or reset by a test (oct. 18 2026)
    if ($SelfTest) { $names = @($script:Live.Keys | Where-Object { [int]($_ -replace '\D', '') -ge 96 } | Sort-Object) }
    $key = $names -join ','
    if (-not $Force -and $key -eq $script:LiveNames) { return $false }
    $first = -not $script:LiveNames -and -not $script:LiveInit
    $script:LiveInit = $true
    $script:LiveNames = $key
    $list = @(Get-LivePortList $names)
    $info = Get-MemberInfo
    foreach ($gone in @($script:Live.Keys | Where-Object { $names -notcontains $_ })) {
        $r = $script:Live[$gone]; $script:Live.Remove($gone)
        if (-not $first) { Show-Toast "$gone unplugged" $(if ($r.Mac) { "$($r.Who)  ($($r.Mac))" } else { '' }) ([string][char]0xE7E8) '#475569' }
    }
    foreach ($p in $list) {
        if ($script:Live.Contains($p.Port)) { $script:Live[$p.Port].Description = $p.Description; $script:Live[$p.Port].Kind = $p.Kind; continue }
        $script:Live[$p.Port] = [pscustomobject]@{ Port = $p.Port; Description = $p.Description; Kind = $p.Kind; Mac = ''; Who = ''
                                                   State = $(if ($p.Kind -ne 'BRIDGE') { 'skip' } elseif ($first) { 'unread' } else { 'new' }); Since = (Get-Date)
                                                   Asked = $false; Prev = '' }
        if (-not $first -and $p.Kind -eq 'BRIDGE') {
            Show-Toast "Board plugged in on $($p.Port)" $(if ($ui.AutoMac.IsChecked) { 'Identifying it (no reset)...' } else { 'Press Read all MACs to identify it.' })
        }
    }
    # Boards already plugged in when the GUI opens are never RESET by themselves
    # (one could be mid-run): they are only ASKED (GET_ID, no reset) - see Step-MacReads.
    if ($first -and @($script:Live.Values | Where-Object State -eq 'unread').Count) {
        Set-Status ("{0} board(s) already plugged in - identifying them without a reset (GET_ID)..." -f @($script:Live.Values | Where-Object State -eq 'unread').Count) $Pal.Cyan
    }
    $sorted = [ordered]@{}
    foreach ($k in @($script:Live.Keys | Sort-Object { [int]($_ -replace '\D', '') })) { $sorted[$k] = $script:Live[$k] }
    $script:Live = $sorted
    Update-LiveViews
    return $true
}
function Start-MacRead([string]$Port) {
    $r = $script:Live[$Port]; if (-not $r) { return }
    $r.State = 'reading'
    Update-LiveViews
    Start-ToolJob -Exe 'powershell' -ToolArgs @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $base 'tools\Get-EspMac.ps1'), '-Port', $Port) -State $Port -OnDone {
        param($text, $code, $port)
        $r = $script:Live[$port]; if (-not $r) { return }
        $m = [regex]::Match($text, '(?i)\b([0-9a-f]{2}(:[0-9a-f]{2}){5})\b')
        if ($m.Success) {
            Set-LiveMac $r $m.Groups[1].Value
        } else {
            $r.State = 'failed'
            Show-Toast "Could not read $port" 'Busy (a monitor open?), not an ESP32, or esptool missing - try Read all MACs.' ([string][char]0xE7BA) '#B45309'
        }
        Update-LiveViews
        if ($ui.Pages.SelectedIndex -eq 1) { Update-CaptureLive }
    }
}
function Set-LiveMac($R, [string]$Mac, [switch]$Quiet) {
    $R.Mac = $Mac.ToLower(); $R.State = 'ok'
    $i = (Get-MemberInfo)[(Get-ShortMac $R.Mac).ToLower()]
    $R.Who = $(if ($i) { $i.Who } else { 'not in the member list' })
    $script:SeenMacs[$R.Mac] = $R.Port
    if (-not $Quiet) { Show-Toast "$($R.Port) is $($R.Who)" $R.Mac ([string][char]0xE73E) }
}
function Start-IdAsk([string]$Port) {
    # GET_ID: the running firmware names itself - the port is opened WITHOUT a
    # reset (tools\get_id.py), so this is safe for a board in the middle of a run
    $r = $script:Live[$Port]; if (-not $r) { return }
    $r.Prev = $r.State; $r.State = 'asking'
    Update-LiveViews
    Start-ToolJob -Exe 'python' -ToolArgs @('tools\get_id.py', '--port', $Port) -State $Port -OnDone {
        param($text, $code, $port)
        $r = $script:Live[$port]; if (-not $r) { return }
        $r.Asked = $true; $r | Add-Member -NotePropertyName ReAsk -NotePropertyValue $false -Force
        $m = [regex]::Match($text, '(?im)^([0-9a-f]{2}(:[0-9a-f]{2}){5})\s*$')
        if ($code -eq 0 -and $m.Success) { Set-LiveMac $r $m.Groups[1].Value -Quiet:($r.Prev -eq 'unread') }
        else { $r.State = $r.Prev }
        Update-LiveViews
        if ($ui.Pages.SelectedIndex -eq 1) { Update-CaptureLive }
    }
}
function Request-MacReadAll {
    $why = Test-HandsOff
    if ($why) { [void][Windows.MessageBox]::Show("Not now - $why. Reading a MAC resets the board.", 'Read MACs'); return }
    # every board is ASKED again first (GET_ID, no reset) - also the ones whose
    # MAC is known, which before stayed on 'waiting to read' for good
    $sn = Get-SnifferPorts
    foreach ($r in $script:Live.Values) { if ($r.Kind -eq 'BRIDGE' -and -not $sn.ContainsKey(([string]$r.Port).ToUpper())) { $r.State = 'new'; $r.Since = (Get-Date).AddSeconds(-5); $r.Asked = $false; $r | Add-Member -NotePropertyName ReAsk -NotePropertyValue $true -Force } }
    if ($sn.Count) { Set-Status ("Identifying every board except the sniffer on {0} (it is recording)." -f (@($sn.Keys) -join ', ')) $Pal.Cyan }
    $script:ForceRead = $true
    Update-LiveViews
}
function Step-MacReads {
    if (@($script:Live.Values | Where-Object { $_.State -in @('reading', 'asking') }).Count) { return }
    # 1) ask first (no reset) - every unidentified board, also the ones that
    #    were plugged in before the GUI opened. Not while a capture / flash /
    #    export runs: holding a port for 2 s between two esptool steps would
    #    make that flash fail.
    if (-not $script:NoPeek -and ($ui.AutoMac.IsChecked -or $script:ForceRead)) {
        $ask = @($script:Live.Values | Where-Object { $_.Kind -eq 'BRIDGE' -and (-not $_.Mac -or $_.ReAsk) -and -not $_.Asked -and
                                                      $_.State -in @('new', 'unread', 'paused') -and ((Get-Date) - $_.Since).TotalSeconds -ge 3 }) | Select-Object -First 1
        if ($ask -and -not (Test-HandsOff -MaxAgeS 4)) { Start-IdAsk $ask.Port; return }
    }
    # 2) a board that did not answer: read_mac (RESETS it) - only a freshly
    #    plugged one, or after 'Read all MACs'
    $want = @($script:Live.Values | Where-Object { $_.State -in @('new', 'paused') -and ($_.Asked -or $script:NoPeek) -and ((Get-Date) - $_.Since).TotalSeconds -ge 2 })
    if ($want.Count) { $sn = Get-SnifferPorts -MaxAgeS 4; $want = @($want | Where-Object { -not $sn.ContainsKey(([string]$_.Port).ToUpper()) }) }   # never reset a recording sniffer
    if (-not $want.Count) { $script:ForceRead = $false; $script:ResetOk = $false; return }
    # NEVER reset a board by itself (oct. 17 2026: an auto read_mac on plug-in can
    # reset a board whose run is still going -> its file ends ABORTED). Only the
    # no-reset GET_ID above runs on its own; read_mac only after 'Read all MACs'.
    if (-not $script:ForceRead) {
        foreach ($r in $want) { $r.State = 'unread' }; Update-LiveViews; return
    }
    if (Test-HandsOff -MaxAgeS 4) {
        if (@($want | Where-Object { $_.State -ne 'paused' }).Count) { foreach ($r in $want) { $r.State = 'paused' }; Update-LiveViews }
        return
    }
    # The boards left did NOT answer GET_ID (firmware older than GET_ID, still
    # booting, blank). read_mac RESETS them: a board in the middle of a run then
    # ends its file ABORTED. Ask once, naming them - never reset silently.
    if (-not $script:ResetOk) {
        if ($script:MacConfirming) { return }   # the timer ticks on under the dialog
        $script:MacConfirming = $true
        $list = ($want | ForEach-Object { '    {0}   {1}' -f $_.Port, $(if ($_.Mac) { $_.Mac } else { 'MAC unknown' }) }) -join "`n"
        $ok = Confirm-Action ("{0} board(s) did not answer without a reset:`n`n{1}`n`n(old firmware, still booting, or blank.)`n`nReading their MAC RESETS them. If one is still running a capture - even one started on another laptop - that run ends ABORTED.`n`nReset and read them now?" -f $want.Count, $list) 'Reset these boards?'
        $script:MacConfirming = $false
        if (-not $ok) {
            foreach ($r in $want) { $r.State = 'unread' }
            $script:ForceRead = $false; Update-LiveViews
            Set-Status 'Not reset. Boards that answered GET_ID are identified; the rest stay "MAC not read yet".' $Pal.Amber
            return
        }
        $script:ResetOk = $true
    }
    Start-MacRead $want[0].Port
}
$script:StateText = @{ new = 'waiting to read'; reading = 'reading MAC...'; asking = 'identifying (no reset)...'; ok = ''; failed = 'MAC read failed'
                       unread = 'MAC not read yet'
                       paused = 'paused - a capture is running'; skip = 'not an ESP32 bridge - left alone' }
function Update-LiveViews {
    $script:LiveVer++   # Run a capture rows re-check their boards
    $boards = @($script:Live.Values | Where-Object { $_.Kind -ne 'BLOCKED' })
    $dot = { param($r) if ($r.State -eq 'ok') { $Pal.Green } elseif ($r.State -in @('reading', 'new', 'asking')) { $Pal.Cyan } elseif ($r.State -eq 'failed') { $Pal.Red } else { $Pal.Amber } }
    # sidebar
    $ui.SideBoards.ItemsSource = @($boards | ForEach-Object {
        [pscustomobject]@{ Port = $_.Port; ShortMac = $(if ($_.Mac) { Get-ShortMac $_.Mac } else { '' })
                           Who = $(if ($_.Who) { $_.Who } else { $script:StateText[$_.State] })
                           Dot = (& $brush (& $dot $_)); Tip = ("{0}  {1}`n{2}`n{3}" -f $_.Port, $_.Mac, $_.Description, $(switch ($_.State) { 'ok' { 'green = identified' } 'failed' { 'red = did not answer (MAC read failed) - re-plug it, or a sniffer' } { $_ -in @('reading', 'new', 'asking') } { 'cyan = being identified now' } default { 'amber = ' + $script:StateText[$_] } })) } })
    $ui.SideCount.Text = [string]$boards.Count
    $ui.SideEmpty.Visibility = $(if ($boards.Count) { 'Collapsed' } else { 'Visible' })
    # home tiles
    $ui.HomeBoards.Children.Clear()
    foreach ($r in $boards) {
        $role = (Get-MemberInfo)[$(if ($r.Mac) { (Get-ShortMac $r.Mac).ToLower() } else { '-' })]
        $tone = if (-not $role) { $Pal.Blue } elseif ($role.Role -eq 'root') { $Pal.Amber } elseif ($role.Role -eq 'attacker') { $Pal.Red } else { $Pal.Blue }
        $t = New-Object Windows.Controls.Border
        $t.Width = 200; $t.Margin = '0,0,10,10'; $t.Padding = '14,12'; $t.CornerRadius = 14; $t.Cursor = 'Hand'
        $t.Background = & $brush $Pal.Card2; $t.BorderThickness = '0,0,0,3'; $t.BorderBrush = & $brush $tone
        $t.ToolTip = "Click to open it on the Boards page`n$($r.Description)"
        $sp = New-Object Windows.Controls.StackPanel
        $top = New-Object Windows.Controls.DockPanel
        $e = New-Object Windows.Shapes.Ellipse; $e.Width = 9; $e.Height = 9; $e.Fill = & $brush (& $dot $r); $e.Margin = '0,0,8,0'
        $p = New-Object Windows.Controls.TextBlock; $p.Text = $r.Port; $p.FontWeight = 'Bold'; $p.FontSize = 15
        [void]$top.Children.Add($e); [void]$top.Children.Add($p)
        $m = New-Object Windows.Controls.TextBlock; $m.Text = $(if ($r.Mac) { $r.Mac } else { $script:StateText[$r.State] })
        $m.FontFamily = 'Cascadia Mono, Consolas'; $m.FontSize = 11; $m.Foreground = & $brush $(if ($r.Mac) { $Pal.Dim } else { $Pal.Faint }); $m.Margin = '0,6,0,2'
        $w = New-Object Windows.Controls.TextBlock; $w.Text = $(if ($r.Who) { $r.Who } else { $r.Description }); $w.Foreground = & $brush $tone
        $w.TextTrimming = 'CharacterEllipsis'; $w.FontWeight = 'SemiBold'
        foreach ($x in $top, $m, $w) { [void]$sp.Children.Add($x) }
        $t.Child = $sp; $t.Tag = $r.Port
        $t.Add_MouseEnter({ param($s) $s.Background = & $brush $Pal.Hover })
        $t.Add_MouseLeave({ param($s) $s.Background = & $brush $Pal.Card2 })
        $t.Add_MouseLeftButtonUp({ param($s) Show-Page 4; $ui.BoardTabs.SelectedIndex = 0; $ui.PortGrid.SelectedItem = @($script:PortRows | Where-Object Port -eq $s.Tag)[0] })
        [void]$ui.HomeBoards.Children.Add($t)
    }
    $read = @($boards | Where-Object Mac).Count
    $ui.HomeBoardsSub.Text = $(if ($boards.Count) { "$($boards.Count) plugged in  -  $read identified by MAC" } else { 'Plug a board in - it shows up here by itself.' })
    # Boards page grid + the port pickers on other pages
    $sel = if ($ui.PortGrid.SelectedItem) { $ui.PortGrid.SelectedItem.Port }
    $script:PortRows = @($script:Live.Values | ForEach-Object {
        $mp = @(([string]$_.Mac).ToUpper() -split '[:\-]' | Where-Object { $_ })
        [pscustomobject]@{ Port = $_.Port; Description = $_.Description; Mac = $_.Mac
                           MacHead = $(if ($mp.Count -ge 6) { ($mp[0..3] -join ':') + ':' } else { [string][char]0x2014 + '  ' })
                           MacTail = $(if ($mp.Count -ge 6) { $mp[4..($mp.Count - 1)] -join ':' } else { '' })
                           Dot = (& $brush $(if ($_.Who) { $Pal.Green } elseif ($_.Mac) { $Pal.Cyan } else { $Pal.Amber }))
                           Nick = $(if ($_.Who) { $_.Who } else { $script:StateText[$_.State] }) } })
    $ui.PortGrid.ItemsSource = $script:PortRows
    if ($sel) { $ui.PortGrid.SelectedItem = @($script:PortRows | Where-Object Port -eq $sel)[0] }
    foreach ($cb in 'SnPort', 'TSelfPort', 'TUartA', 'TUartB') { if (-not $ui[$cb].IsDropDownOpen) { Update-PortPick $ui[$cb] } }
    Update-ImpPorts
}
$liveTimer = New-Object Windows.Threading.DispatcherTimer
$liveTimer.Interval = [TimeSpan]::FromMilliseconds(1500)
$liveTimer.Add_Tick({ Measure-GuiTick 'live' {   # gui\Perf.ps1: a tick over 150 ms is logged
    try {
        $changed = Update-LivePorts
        Step-MacReads
        if ($changed -and $ui.Pages.SelectedIndex -eq 1) { Update-CaptureLive }
    } catch { Set-Status ("Board watcher: " + $_.Exception.Message) $Pal.Red }
} })
$ui.HomeReadMacs.Add_Click({ Request-MacReadAll })

# ── HOME ──────────────────────────────────────────────────────────────────────
$script:LocTone = @{ G402 = '#8B5CF6'; DLSU_Library = '#22D3EE'; Yuchengco = '#F472B6'; home = '#A3E635' }
function New-Card([string]$Title, [int]$Done, [int]$Partial, [int]$Planned, [string]$Tone = '#8B5CF6') {
    $card = New-Object Windows.Controls.Border
    $card.Background = & $brush $Pal.Card; $card.CornerRadius = 16; $card.Padding = '20,18'; $card.Margin = '0,0,14,14'; $card.Width = 255
    $card.BorderThickness = '0,3,0,0'; $card.BorderBrush = & $brush $Tone
    $sp = New-Object Windows.Controls.StackPanel
    $t = New-Object Windows.Controls.TextBlock; $t.Text = $Title.ToUpper(); $t.Foreground = & $brush $Tone; $t.FontSize = 11; $t.FontWeight = 'Bold'
    $row = New-Object Windows.Controls.DockPanel; $row.Margin = '0,6,0,0'
    $pct = if ($Planned) { [math]::Round(100 * $Done / $Planned) } else { 0 }
    $pc = New-Object Windows.Controls.TextBlock; $pc.Text = "$pct%"; $pc.FontSize = 15; $pc.FontWeight = 'SemiBold'; $pc.Foreground = & $brush $Tone
    $pc.VerticalAlignment = 'Bottom'; $pc.Margin = '0,0,0,4'; [Windows.Controls.DockPanel]::SetDock($pc, 'Right')
    $n = New-Object Windows.Controls.TextBlock; $n.FontSize = 30; $n.FontWeight = 'Bold'; $n.Foreground = & $brush $Pal.Text
    $n.Inlines.Add((New-Object Windows.Documents.Run "$Done")); $sl = New-Object Windows.Documents.Run " / $Planned"; $sl.FontSize = 16; $sl.Foreground = & $brush $Pal.Faint; $n.Inlines.Add($sl)
    [void]$row.Children.Add($pc); [void]$row.Children.Add($n)
    $sub = New-Object Windows.Controls.TextBlock; $sub.Foreground = & $brush $Pal.Dim; $sub.FontSize = 12
    $sub.Text = "$($Planned - $Done) to go" + $(if ($Partial) { "   ·   $Partial in progress" } else { '' })
    $bar = New-Object Windows.Controls.ProgressBar; $bar.Maximum = [math]::Max(1, $Planned); $bar.Value = 0; $bar.Margin = '0,12,0,0'
    $g = New-Object Windows.Media.LinearGradientBrush; $g.StartPoint = '0,0'; $g.EndPoint = '1,0'
    $g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($Tone)), 0))
    $g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString('#34D399')), 1))
    $bar.Foreground = $g
    $bar.BeginAnimation([Windows.Controls.Primitives.RangeBase]::ValueProperty, (New-Fade 0 $Done 900))
    foreach ($x in $t, $row, $sub, $bar) { [void]$sp.Children.Add($x) }
    $card.Child = $sp
    return $card
}
function Get-SlotText($s) { '{0}  /  {1}  /  {2}  /  {3}' -f $(if ($s.kind -eq 'benign') { 'baseline' } else { $s.attack }), $s.topology, $s.location, $s.scenario }
function Update-Home {
    $h = (Get-Date).Hour
    $ui.HomeHello.Text = $(if ($h -lt 12) { 'Good morning, team' } elseif ($h -lt 18) { 'Good afternoon, team' } else { 'Good evening, team' })
    if (-not $script:Py) { $ui.HomeSub.Text = 'Python with pandas not found - campaign data, analysis and verify need it. Install once in a terminal:  python -m pip install -r analysis
equirements.txt   then restart the GUI.'; return }
    $ui.HomeSub.Text = 'Loading the campaign plan...'
    $json = [IO.Path]::GetTempFileName()
    Start-ToolJob -Exe $script:Py -ToolArgs @('tools\inventory_cells.py', '--json', $json, '--no-color') -State $json -OnDone {
        param($text, $code, $json)
        try { $st = Get-Content $json -Raw | ConvertFrom-Json } catch { $ui.HomeSub.Text = 'Could not read the campaign status.'; return }
        Remove-Item $json -ErrorAction SilentlyContinue
        $script:Campaign = $st
        $ui.HomeCards.Children.Clear()
        [void]$ui.HomeCards.Children.Add((New-Card 'whole campaign' $st.total.done $st.total.partial $st.total.planned '#EC4899'))
        foreach ($loc in $st.locations) {
            $pl = $st.per_location.$loc.all
            $tone = if ($script:LocTone[$loc]) { $script:LocTone[$loc] } else { '#60A5FA' }
            [void]$ui.HomeCards.Children.Add((New-Card ($loc -replace '_', ' ') $pl.done $pl.partial $pl.planned $tone))
        }
        $ui.HomeSub.Text = ("{0} of {1} planned runs done  ·  {2} left  ·  about {3} hours of capturing" -f
            $st.total.done, $st.total.planned, $st.remaining, [math]::Round($st.hours_left))
        if ($st.next) {
            $ui.HomeNext.Text = Get-SlotText $st.next
            $ui.HomeNextWhy.Text = "next slot in run order, at the location with the most done runs (session $($st.next.session))"
        } else { $ui.HomeNext.Text = 'Everything planned is captured!'; $ui.HomeNextWhy.Text = '' }
        Update-CampaignMatrix; Update-CaptureCampaign
        try { Update-TodayStrip } catch { }   # gui\TodayStrip.ps1: last 24 hours on Home
        Set-Status 'Campaign loaded.' $Pal.Green
        Update-CampPanelFresh
    }
}
$ui.HomeRefresh.Add_Click({ Update-Home; Update-LivePorts -Force | Out-Null })
$ui.HomeGoCapture.Add_Click({ if ($script:Campaign -and $script:Campaign.next) { Start-CellCapture $script:Campaign.next } else { Show-Page 1 } })
# quick actions: big friendly tiles
$quick = @(
    @{ G = [char]0xE768; T = 'Run a capture';   C = '#8B5CF6'; A = { Show-Page 1 } }
    @{ G = [char]0xE787; T = 'Campaign grid';   C = '#EC4899'; A = { Show-Page 3; $ui.CampTabs.SelectedIndex = 0 } }
    @{ G = [char]0xE73E; T = 'Verify a run';    C = '#34D399'; A = { Show-Page 2 } }
    @{ G = [char]0xE88E; T = 'Boards';          C = '#22D3EE'; A = { Show-Page 4 } }
    @{ G = [char]0xE896; T = 'Import SD card';  C = '#FBBF24'; A = { Show-Page 5; $ui.DataTabs.SelectedIndex = 0 } }
    @{ G = [char]0xE895; T = 'GitHub sync';     C = '#60A5FA'; A = { Show-Page 8 } }
)
foreach ($q in $quick) {
    $b = New-Object Windows.Controls.Button
    $b.Margin = '0,0,8,8'; $b.Padding = '12,14'; $b.HorizontalContentAlignment = 'Left'
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    $ic = New-Object Windows.Controls.Border; $ic.Width = 32; $ic.Height = 32; $ic.CornerRadius = 10; $ic.Background = & $brush ($q.C -replace '#', '#33')
    $g = New-Object Windows.Controls.TextBlock; $g.Text = [string]$q.G; $g.FontFamily = 'Segoe MDL2 Assets'; $g.FontSize = 15; $g.Foreground = & $brush $q.C
    $g.HorizontalAlignment = 'Center'; $g.VerticalAlignment = 'Center'; $ic.Child = $g
    $tx = New-Object Windows.Controls.TextBlock; $tx.Text = $q.T; $tx.FontWeight = 'SemiBold'; $tx.VerticalAlignment = 'Center'; $tx.Margin = '10,0,0,0'
    [void]$sp.Children.Add($ic); [void]$sp.Children.Add($tx); $b.Content = $sp
    $b.Add_Click($q.A)
    [void]$ui.HomeActions.Children.Add($b)
}

# ── RUN A CAPTURE ─────────────────────────────────────────────────────────────
# oct. 18 2026 redesign (user: "more fun and friendly, like Campaign"): a preset
# GALLERY - one box per person (yours first, with a heart), split by attack, a
# card per preset with a little drawing of its mesh, its campaign status (UP
# NEXT / NEEDED / REDO / DONE ...) and one dot per board (filled = plugged in).
# The hidden OwnerPick / AttackPick / PresetGrid stay the real filter and
# selection - the chips and cards only drive them - so the palette, Campaign,
# Home and the self-test keep working unchanged.
$script:OwnerTones = @(@('#8B5CF6', '#EC4899'), @('#22D3EE', '#34D399'), @('#FBBF24', '#FB7185'),
                       @('#60A5FA', '#A78BFA'), @('#F472B6', '#FB923C'), @('#A3E635', '#22D3EE'))
$script:AtkGrad = @{ blackhole = @('#BE123C', '#7C3AED'); wormhole = @('#7C3AED', '#DB2777'); baseline = @('#047857', '#0891B2') }
$script:ScnLook = @{
    stationary = @{ S = [string][char]0x25C9; C = $Pal.Blue }
    burst      = @{ S = [string][char]0x2738; C = $Pal.Amber }
    highload   = @{ S = [string][char]0x25B2; C = '#FB923C' }
    jitter     = @{ S = [string][char]0x224B; C = $Pal.Cyan }
    mobility   = @{ S = [string][char]0x279C; C = $Pal.Lime }
    powercycle = @{ S = [string][char]0x21BB; C = $Pal.Pink }
}
# campaign status -> the ribbon on a card
$script:CardRibbon = @{
    next    = @{ T = 'UP NEXT';    C = $Pal.Pink;  Tip = 'The next run in campaign order - this is the one to capture now.' }
    todo    = @{ T = 'NEEDED';     C = $Pal.Lime;  Tip = 'The campaign still needs this run - not captured yet.' }
    partial = @{ T = 'RE-CAPTURE'; C = '#FB923C';  Tip = 'Captured, but incomplete - capture it again.' }
    redo    = @{ T = 'REDO';       C = $Pal.Red;   Tip = 'On the redo list - capture it again.' }
    check   = @{ T = 'CHECK';      C = $Pal.Amber; Tip = 'Done, with a caveat to look at (Campaign page).' }
    analyse = @{ T = 'ANALYSE';    C = $Pal.Cyan;  Tip = 'Captured - not analysed yet (Verify & analyse page).' }
    ok      = @{ T = 'DONE';       C = $Pal.Green; Tip = 'Captured and verified - only re-run it on purpose.' }
    done    = @{ T = 'DONE';       C = $Pal.Green; Tip = 'Captured - only re-run it on purpose.' }
    off     = @{ T = 'OFF-PLAN';   C = $Pal.Faint; Tip = 'Not in the campaign plan (extra / test run).' }
}
$script:SlotByKey = @{}; $script:CardByPath = @{}
function Get-OwnerTone([string]$Owner) {
    $all = @($script:Presets | ForEach-Object Owner | Sort-Object -Unique)
    $i = [array]::IndexOf($all, $Owner); if ($i -lt 0) { $i = 0 }
    return $script:OwnerTones[$i % $script:OwnerTones.Count]
}
function New-Grad([string]$A, [string]$B, [string]$End = '1,1') {
    $g = New-Object Windows.Media.LinearGradientBrush; $g.StartPoint = '0,0'; $g.EndPoint = $End
    $g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($A)), 0))
    $g.GradientStops.Add((New-Object Windows.Media.GradientStop ([Windows.Media.ColorConverter]::ConvertFromString($B)), 1))
    return $g
}
function New-TopoArt([string]$Topo, [string]$Attack, [double]$W = 64, [double]$H = 38) {
    # a tiny drawing of the mesh: amber = root, red ring = the blackhole,
    # purple + dashed arc = the wormhole tunnel, blue = a plain child
    $cv = New-Object Windows.Controls.Canvas; $cv.Width = $W; $cv.Height = $H; $cv.IsHitTestVisible = $false
    $alt = @()
    switch ($Topo -replace '^partial$', 'partial_mesh') {
        'linear' { $n = @(@(0, 0.5), @(0.33, 0.5), @(0.66, 0.5), @(1, 0.5)); $e = @(@(0, 1), @(1, 2), @(2, 3)); $bad = 1; $tun = @(1, 3) }
        'tree'   { $n = @(@(0.5, 0), @(0.22, 0.5), @(0.78, 0.5), @(0, 1), @(0.42, 1), @(1, 1)); $e = @(@(0, 1), @(0, 2), @(1, 3), @(1, 4), @(2, 5)); $bad = 1; $tun = @(1, 5) }
        'star'   { $n = @(@(0.5, 0.5), @(0.5, 0), @(0.95, 0.32), @(0.8, 1), @(0.2, 1), @(0.05, 0.32)); $e = @(@(0, 1), @(0, 2), @(0, 3), @(0, 4), @(0, 5)); $bad = 2; $tun = @(1, 3) }
        # partial mesh: still ONE parent per child (solid); the dashed lines are the
        # other parent each child could switch to (user, oct. 18 2026: the old
        # drawing looked like a child had 2 parents - ESP-WIFI-MESH never does that)
        default  { $n = @(@(0.5, 0), @(0.08, 0.45), @(0.92, 0.45), @(0.28, 1), @(0.72, 1)); $e = @(@(0, 1), @(0, 2), @(1, 3), @(2, 4)); $alt = @(@(2, 3), @(1, 4)); $bad = 1; $tun = @(1, 4) }
    }
    $r = [math]::Max(3.5, $H / 9)
    $pt = { param($i) @(($r + $n[$i][0] * ($W - 2 * $r)), ($r + $n[$i][1] * ($H - 2 * $r))) }
    foreach ($ed in $e) {
        $a = & $pt $ed[0]; $b = & $pt $ed[1]
        $l = New-Object Windows.Shapes.Line; $l.X1 = $a[0]; $l.Y1 = $a[1]; $l.X2 = $b[0]; $l.Y2 = $b[1]
        $l.Stroke = & $brush '#5A5F8A'; $l.StrokeThickness = [math]::Max(1.2, $r / 3.5)
        [void]$cv.Children.Add($l)
    }
    foreach ($ed in $alt) {
        $a = & $pt $ed[0]; $b = & $pt $ed[1]
        $l = New-Object Windows.Shapes.Line; $l.X1 = $a[0]; $l.Y1 = $a[1]; $l.X2 = $b[0]; $l.Y2 = $b[1]
        $l.Stroke = & $brush '#5A5F8A'; $l.StrokeThickness = [math]::Max(1, $r / 4); $l.Opacity = 0.8
        $l.StrokeDashArray = New-Object Windows.Media.DoubleCollection (, [double[]]@(1.5, 1.5))
        [void]$cv.Children.Add($l)
    }
    if ($Attack -eq 'wormhole') {
        $a = & $pt $tun[0]; $b = & $pt $tun[1]
        $inv = [Globalization.CultureInfo]::InvariantCulture
        $cy = [math]::Max(0, [math]::Min($a[1], $b[1]) - $H * 0.55)
        $arc = New-Object Windows.Shapes.Path
        $arc.Data = [Windows.Media.Geometry]::Parse([string]::Format($inv, 'M {0:0.0},{1:0.0} Q {2:0.0},{3:0.0} {4:0.0},{5:0.0}', $a[0], $a[1], (($a[0] + $b[0]) / 2), $cy, $b[0], $b[1]))
        $arc.Stroke = & $brush $Pal.Purple; $arc.StrokeThickness = [math]::Max(1.4, $r / 3)
        $arc.StrokeDashArray = New-Object Windows.Media.DoubleCollection (, [double[]]@(2, 1.5))
        [void]$cv.Children.Add($arc)
    }
    for ($i = 0; $i -lt $n.Count; $i++) {
        $p = & $pt $i
        $d = New-Object Windows.Shapes.Ellipse; $d.Width = 2 * $r; $d.Height = 2 * $r
        if ($i -eq 0) { $d.Fill = & $brush $Pal.Amber }
        elseif ($Attack -eq 'blackhole' -and $i -eq $bad) { $d.Fill = & $brush '#0B0C14'; $d.Stroke = & $brush $Pal.Red; $d.StrokeThickness = [math]::Max(1.5, $r / 2.5) }
        elseif ($Attack -eq 'wormhole' -and $tun -contains $i) { $d.Fill = & $brush $Pal.Purple }
        else { $d.Fill = & $brush $Pal.Blue }
        [Windows.Controls.Canvas]::SetLeft($d, $p[0] - $r); [Windows.Controls.Canvas]::SetTop($d, $p[1] - $r)
        [void]$cv.Children.Add($d)
    }
    return $cv
}
# the same drawing as a frozen picture, for lists that bind it (one per kind)
$script:TopoImg = @{}
function Get-TopoImage([string]$Topo, [string]$Attack, [int]$W = 80, [int]$H = 52) {
    $k = "$Topo|$Attack|$W"; if ($script:TopoImg[$k]) { return $script:TopoImg[$k] }
    $cv = New-TopoArt $Topo $Attack $W $H
    $cv.Measure((New-Object Windows.Size $W, $H)); $cv.Arrange((New-Object Windows.Rect 0, 0, $W, $H))
    $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap (2 * $W), (2 * $H), 192, 192, ([Windows.Media.PixelFormats]::Pbgra32)
    $bmp.Render($cv); $bmp.Freeze()
    $script:TopoImg[$k] = $bmp; return $bmp
}
function Test-BoardHere($B, $LiveMacs) {
    # same rule as the board list: by MAC first (any USB socket), then by port
    $mac = ([string]$B.Mac).ToLower(); if ($mac -and $LiveMacs[$mac]) { return $true }
    $port = [string]$B.Port
    if (-not $port -or -not $script:Live.Contains($port)) { return $false }
    $other = $script:Live[$port].Mac
    return (-not $other -or $other -eq $mac)
}
function Get-BoardTone($B) {
    if ($B.Role -eq 'root') { $Pal.Amber } elseif ($B.Kind -eq 'attacker') { $Pal.Red } elseif ($B.Kind -in @('A', 'B')) { $Pal.Purple } else { $Pal.Blue }
}
function Get-PresetLook($P) {
    # the preset's cell on the campaign plan -> a ribbon key (or '' while loading)
    if (-not $script:Campaign) { return '' }
    $key = Get-CellKey $P.Attack $P.Topology $P.Location $P.Scenario
    $nx = $script:Campaign.next
    if ($nx -and (Get-CellKey $(if ($nx.kind -eq 'benign') { 'baseline' } else { $nx.attack }) $nx.topology $nx.location $nx.scenario) -eq $key) { return 'next' }
    $s = $script:SlotByKey[$key]
    if (-not $s) { return 'off' }
    return (Get-SlotLook $s)
}
function New-CapChip([string]$Text, [string]$Fg, [string]$Bg) {
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 8; $b.Padding = '7,1'; $b.Margin = '0,0,5,4'; $b.Background = & $brush $Bg
    $b.Child = New-Text $Text 11 $Fg 'SemiBold'; return $b
}
function New-MacChip([string]$Mac, [string]$Tone) {
    # 20:50:0D:E7:[1C:38] - monospaced, upper case, click copies it
    $m = $Mac.ToUpper(); $parts = @($m -split '[:\-]')
    $c = New-Object Windows.Controls.Border; $c.CornerRadius = 6; $c.Padding = '7,2'; $c.Background = & $brush '#12131F'
    $c.BorderBrush = & $brush $Pal.Line; $c.BorderThickness = 1; $c.Cursor = 'Hand'; $c.VerticalAlignment = 'Center'
    $c.ToolTip = "$m`nclick to copy"
    $t = New-Object Windows.Controls.TextBlock; $t.FontFamily = 'Consolas'; $t.FontSize = 13
    if ($parts.Count -ge 6) {
        $r1 = New-Object Windows.Documents.Run (($parts[0..3] -join ':') + ':'); $r1.Foreground = & $brush $Pal.Text; $t.Inlines.Add($r1)
        $r2 = New-Object Windows.Documents.Run ($parts[4..($parts.Count - 1)] -join ':'); $r2.Foreground = & $brush $Tone; $r2.FontWeight = 'Bold'; $t.Inlines.Add($r2)
    } else { $t.Text = $(if ($m) { $m } else { 'no MAC saved' }); $t.Foreground = & $brush $Pal.Text }
    $c.Child = $t; $c.Tag = $m
    $c.Add_MouseLeftButtonUp({ param($x) if ($x.Tag) { try { [Windows.Clipboard]::SetText([string]$x.Tag); Show-Toast 'MAC copied' ([string]$x.Tag) ([string][char]0xE8C8) } catch { } } })
    return $c
}
function New-Avatar([string]$Name, $Tone, [double]$Size) {
    $a = New-Object Windows.Controls.Border; $a.Width = $Size; $a.Height = $Size; $a.CornerRadius = $Size / 2
    $a.Background = New-Grad $Tone[0] $Tone[1]; $a.VerticalAlignment = 'Center'
    $t = New-Text $(if ($Name -eq 'everyone') { [string][char]0x2605 } else { $Name.Substring(0, 1).ToUpper() }) ($Size * 0.48) '#FFFFFF' 'Bold'
    $t.HorizontalAlignment = 'Center'; $a.Child = $t; return $a
}
# frozen, shared brushes for the list rows (cheap, and safe to bind)
$script:FBrush = @{}
function Get-FBrush([string]$A, [string]$B = '', [string]$End = '1,0') {
    $k = "$A|$B|$End"; $x = $script:FBrush[$k]
    if (-not $x) { $x = $(if ($B) { New-Grad $A $B $End } else { & $brush $A }).psobject.BaseObject; $x.Freeze(); $script:FBrush[$k] = $x }
    return $x
}
$script:RowCache = @{}
$script:LiveVer = 0; $script:CampVer = 0
function Format-PresetDate([datetime]$D, [switch]$Ago) {
    # 'today 3:05 PM' / 'yesterday' / '3 days ago' / 'Oct 05' - friendly, short
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $days = ((Get-Date).Date - $D.Date).Days
    if ($Ago) {
        if ($days -le 0) { return 'today' } elseif ($days -eq 1) { return 'yesterday' } elseif ($days -lt 14) { return "$days days ago" }
        elseif ($days -lt 60) { return "$([math]::Floor($days / 7)) weeks ago" } else { return "$([math]::Floor($days / 30)) months ago" }
    }
    if ($days -le 0) { 'today  ' + $D.ToString('h:mm tt', $inv) } elseif ($days -eq 1) { 'yesterday  ' + $D.ToString('h:mm tt', $inv) }
    elseif ($days -lt 7) { "$days days ago  ·  " + $D.ToString('MMM dd', $inv) } else { $D.ToString('MMM dd, yyyy', $inv) }
}
function New-PresetRow($P, $LiveMacs) {
    # rebuilt only when a board was plugged / identified (LiveVer) or the
    # campaign / redo list changed (CampVer) - a filter click reuses the row as is
    $ver = "$($script:LiveVer)|$($script:CampVer)"
    $hit = $script:RowCache[$P.Path]; if ($hit -and $hit.Ver -eq $ver) { return $hit }
    $look = Get-PresetLook $P
    $bs = @($P.Cfg.boards); $mask = -join @($bs | ForEach-Object { if (Test-BoardHere $_ $LiveMacs) { '1' } else { '0' } })
    $here = ($mask.ToCharArray() | Where-Object { $_ -eq '1' }).Count
    $ck = "$($P.Path)|$look|$mask"
    if ($hit -and $hit.Key -eq $ck) { $hit.Ver = $ver; return $hit }
    $tone = if ($script:AtkTone[$P.Attack]) { $script:AtkTone[$P.Attack] } else { $Pal.Text }
    $lt = if ($script:LocTone[$P.Location]) { $script:LocTone[$P.Location] } else { $Pal.Blue }
    $sl = $script:ScnLook[$P.Scenario]; if (-not $sl) { $sl = @{ S = [string][char]0x25CF; C = $Pal.Dim } }
    $rb = if ($look) { $script:CardRibbon[$look] } else { $null }
    $ot = Get-OwnerTone $P.Owner
    $hc = if (-not $bs.Count) { $Pal.Faint } elseif ($here -eq $bs.Count) { $Pal.Green } elseif ($here) { $Pal.Amber } else { $Pal.Faint }
    $dots = @(@($bs | Sort-Object { if ($_.Role -eq 'root') { 1 } else { 0 } }) | ForEach-Object {
        $bt = Get-BoardTone $_; $ok = Test-BoardHere $_ $LiveMacs
        [pscustomobject]@{ Fill = (Get-FBrush $(if ($ok) { $bt } else { '#00000000' })); Stroke = (Get-FBrush $bt); Op = $(if ($ok) { 1.0 } else { 0.55 })
                           Tip = ("{0}  ·  {1}`n{2}`n{3}" -f $_.Label, $(if ($_.Role -eq 'root') { 'ROOT' } else { [string]$_.Kind }), ([string]$_.Mac).ToUpper(), $(if ($ok) { 'plugged in' } else { "not plugged in (saved on $($_.Port))" })) } })
    $row = [pscustomobject]@{
        P = $P; Key = $ck; Ver = $ver; Ready = ($bs.Count -and $here -eq $bs.Count); Look = $look; Dots = $dots
        CardBg = (Get-FBrush ($tone -replace '#', '#30') $Pal.Card '0,1')
        Art = (Get-TopoImage $P.Topology $P.Attack 64 38).psobject.BaseObject
        RowBg = (Get-FBrush ($tone -replace '#', '#2A') $Pal.Card '1,0')
        AtkText = $P.Attack.ToUpper(); AtkFg = (Get-FBrush $tone)
        AtkBg = (Get-FBrush ($tone -replace '#', '#33')); AtkLine = (Get-FBrush ($tone -replace '#', '#66') ($tone -replace '#', '#00') '1,0')
        RepText = $(if ($P.Repeat -gt 1) { "   ·   repeat $($P.Repeat)" } else { '' }) + $(if ($P.NameFlag) { '   (!) name' } else { '' })
        Topo = ($P.Topology -replace '_', ' ')
        LocText = ($P.Location -replace '_', ' '); LocFg = (Get-FBrush $lt); LocBg = (Get-FBrush ($lt -replace '#', '#2A'))
        ScnText = "$($sl.S) $($P.Scenario)"; ScnFg = (Get-FBrush $sl.C); ScnBg = (Get-FBrush ($sl.C -replace '#', '#2A'))
        Owner = $P.Owner; OwnerInit = $P.Owner.Substring(0, 1).ToUpper(); OwnerBg = (Get-FBrush $ot[0] $ot[1] '1,1')
        DateText = ([string][char]0x25F7 + '  ' + (Format-PresetDate $P.Saved))
        DateDay = $P.Saved.ToString('MMM dd, yyyy', [Globalization.CultureInfo]::InvariantCulture); DateAgo = (Format-PresetDate $P.Saved -Ago)
        DateFull = ('saved ' + $P.Saved.ToString('dddd, MMMM dd yyyy  h:mm tt', [Globalization.CultureInfo]::InvariantCulture))
        HereText = $(if ($bs.Count -and $here -eq $bs.Count) { [string][char]0x2714 + ' all here' } else { "$here/$($bs.Count) here" }); HereFg = (Get-FBrush $hc)
        RibText = $(if ($look -eq 'next') { [string][char]0x25B6 + ' UP NEXT' } elseif ($rb) { $rb.T } else { '' })
        RibFg = (Get-FBrush $(if ($look -eq 'next') { '#FFFFFF' } elseif ($rb) { $rb.C } else { $Pal.Faint }))
        RibBg = $(if ($look -eq 'next') { Get-FBrush '#8B5CF6' '#EC4899' '1,0' } elseif ($rb) { Get-FBrush ($rb.C -replace '#', '#2E') } else { Get-FBrush '#00000000' })
        Tip = "$($P.File)`n$($P.Boards) boards  ·  key boards: $(if ($P.KeyBoards) { $P.KeyBoards } else { '-' })`nsaved $($P.SavedText)$(if ($rb) { "`n`n$($rb.Tip)" })`n`nclick = look inside  ·  double-click = use it"
    }
    $script:RowCache[$P.Path] = $row
    return $row
}
function Update-PresetList($Rows, $LiveMacs) {
    $script:ListBusy = $true
    try {
        $items = New-Object System.Collections.ArrayList
        $ready = 0
        foreach ($p in $Rows) { $r = New-PresetRow $p $LiveMacs; if ($r.Ready) { $ready++ }; [void]$items.Add($r) }
        $ui.PresetList.ItemsSource = $items
        # a heading per attack - the rows arrive already grouped (attack, then date)
        $view = [Windows.Data.CollectionViewSource]::GetDefaultView($items)
        if ($view -and -not $view.GroupDescriptions.Count) { $view.GroupDescriptions.Add((New-Object Windows.Data.PropertyGroupDescription 'AtkText')) }
        $sel = $ui.PresetGrid.SelectedItem
        if ($sel) { $hit = @($items | Where-Object { $_.P.Path -eq $sel.Path }); if ($hit.Count) { $ui.PresetList.SelectedItem = $hit[0] } }
        $owners = @($Rows | ForEach-Object Owner | Sort-Object -Unique).Count
        $ui.CapSub.Text = ("{0} preset{1} from {2} {3}  ·  {4} ready to run on this laptop now  ·  click a row to look inside, double-click to use it  ·  pick a name above for their card boxes" -f
            $Rows.Count, $(if ($Rows.Count -ne 1) { 's' } else { '' }), $owners, $(if ($owners -eq 1) { 'person' } else { 'people' }), $ready)
    } finally { $script:ListBusy = $false }
}
$onPick = {
    param($s)
    if ($script:ListBusy) { return }
    $r = $s.SelectedItem
    if ($r -and $ui.PresetGrid.SelectedItem -ne $r.P) { $ui.PresetGrid.SelectedItem = $r.P }
}
$onUse = { param($s) if ($s.SelectedItem) { $ui.StartCapture.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent))) } }
$ui.PresetList.Add_SelectionChanged($onPick)
$ui.PresetList.Add_MouseDoubleClick($onUse)
function Sync-PresetSelection {
    # the hidden PresetGrid holds THE selection; the list / card groups follow it
    $p = $ui.PresetGrid.SelectedItem
    $script:ListBusy = $true
    try {
        foreach ($lb in @(@($ui.PresetList) + @($script:CardGroups))) {
            if (-not $lb -or -not $lb.ItemsSource) { continue }
            $hit = if ($p) { @($lb.ItemsSource | Where-Object { $_.P.Path -eq $p.Path }) } else { @() }
            if ($hit.Count) {
                $lb.SelectedItem = $hit[0]
                if ($lb -eq $ui.PresetList) { if ($lb.IsVisible) { $lb.ScrollIntoView($hit[0]) } }
                else { $ct = $lb.ItemContainerGenerator.ContainerFromItem($hit[0]); if ($ct) { $ct.BringIntoView() } }
            } else { $lb.SelectedItem = $null }
        }
    } finally { $script:ListBusy = $false }
}
function Update-PresetGallery([switch]$Quiet) {
    $g = $ui.PresetGallery
    $g.Children.Clear(); $script:CardGroups = New-Object System.Collections.ArrayList
    $rows = @($ui.PresetGrid.ItemsSource | Where-Object { $_ })
    $liveMacs = Get-LiveMacs
    Update-SlotIndex
    if (-not $rows.Count) {
        $ui.PresetList.Visibility = 'Collapsed'; $ui.PresetScroll.Visibility = 'Visible'; $ui.PresetList.ItemsSource = $null
        $empty = New-Object Windows.Controls.Border; $empty.Style = $win.FindResource('Card'); $empty.Padding = '30,34'
        $es = New-Object Windows.Controls.StackPanel; $es.HorizontalAlignment = 'Center'
        $eg = New-Text ([string][char]0x2727) 44 $Pal.Pink; $eg.HorizontalAlignment = 'Center'
        $et = New-Text 'No preset matches' 18 $Pal.Text 'Bold'; $et.HorizontalAlignment = 'Center'; $et.Margin = '0,6,0,4'
        $ex = New-Text 'Clear the search / filters, or make a new preset with "+ New preset" (top right).' 12 $Pal.Dim; $ex.HorizontalAlignment = 'Center'
        foreach ($x in $eg, $et, $ex) { [void]$es.Children.Add($x) }
        $empty.Child = $es; [void]$g.Children.Add($empty); return
    }
    # Everyone -> the fast list; a person -> their card boxes
    $listMode = ([string]$ui.OwnerPick.SelectedItem -eq 'everyone')
    $ui.PresetList.Visibility = $(if ($listMode) { 'Visible' } else { 'Collapsed' })
    $ui.PresetScroll.Visibility = $(if ($listMode) { 'Collapsed' } else { 'Visible' })
    if ($listMode) { $ui.PresetList.Visibility = 'Visible'; Update-PresetList $rows $liveMacs; Sync-PresetSelection; return }
    $owners = @($rows | ForEach-Object Owner | Sort-Object -Unique | Sort-Object @{ E = { if ($_ -eq $script:Me) { 0 } elseif ($_ -eq '(unfiled)') { 2 } else { 1 } } }, @{ E = { $_ } })
    $readyAll = 0
    foreach ($o in $owners) {
        $tone = Get-OwnerTone $o
        $mine = @($rows | Where-Object { $_.Owner -eq $o })
        $isMe = ($script:Me -and $o -eq $script:Me)
        # the person's box: soft gradient in their colours, a big initial behind it
        $box = New-Object Windows.Controls.Border; $box.CornerRadius = 20; $box.Padding = '18,16,6,4'; $box.Margin = '0,0,0,16'
        $box.Background = New-Grad ($tone[0] -replace '#', '#24') ($tone[1] -replace '#', '#0C')
        $box.BorderBrush = New-Grad ($tone[0] -replace '#', '#99') ($tone[1] -replace '#', '#30'); $box.BorderThickness = 1.5
        $layer = New-Object Windows.Controls.Grid
        $wm = New-Text $(if ($isMe) { [string][char]0x2665 } else { $o.Substring(0, 1).ToUpper() }) 150 ($tone[1] -replace '#', '#16') 'Black'
        $wm.HorizontalAlignment = 'Right'; $wm.VerticalAlignment = 'Top'; $wm.Margin = '0,-48,18,0'; $wm.IsHitTestVisible = $false
        [void]$layer.Children.Add($wm)
        $body = New-Object Windows.Controls.StackPanel
        # header: avatar + name + what is in the box
        $hd = New-Object Windows.Controls.DockPanel; $hd.Margin = '0,0,12,6'
        $av = New-Avatar $o $tone 46; $av.Margin = '0,0,14,0'
        $fx = New-Object Windows.Media.Effects.DropShadowEffect; $fx.ShadowDepth = 0; $fx.BlurRadius = 16; $fx.Opacity = 0.6; $fx.Color = [Windows.Media.ColorConverter]::ConvertFromString($tone[0]); $av.Effect = $fx
        [Windows.Controls.DockPanel]::SetDock($av, 'Left'); [void]$hd.Children.Add($av)
        $nm = New-Object Windows.Controls.StackPanel; $nm.VerticalAlignment = 'Center'
        $nl = New-Object Windows.Controls.StackPanel; $nl.Orientation = 'Horizontal'
        [void]$nl.Children.Add((New-Text $(if ($o -eq '(unfiled)') { 'Unfiled' } else { "$o's presets" }) 19 $Pal.Text 'Bold'))
        if ($isMe) { $yo = New-CapChip ([string][char]0x2665 + '  you') '#FFFFFF' $Pal.Pink; $yo.Margin = '10,4,0,0'; $yo.Background = New-Grad $tone[0] $tone[1]; [void]$nl.Children.Add($yo) }
        [void]$nm.Children.Add($nl)
        $sub = New-Text '' 12 $Pal.Dim; $sub.Margin = '0,2,0,0'
        [void]$nm.Children.Add($sub)
        [void]$hd.Children.Add($nm)
        [void]$body.Children.Add($hd)
        $ready = 0; $needed = 0
        foreach ($atk in @('blackhole', 'wormhole', 'baseline')) {
            $set = @($mine | Where-Object { $_.Attack -eq $atk })
            if (-not $set.Count) { continue }
            $at = $script:AtkTone[$atk]
            # divider: attack pill + a line in its colour
            $band = New-Object Windows.Controls.DockPanel; $band.Margin = '0,10,12,10'
            $pill = New-Object Windows.Controls.Border; $pill.CornerRadius = 8; $pill.Padding = '10,2'; $pill.Background = & $brush ($at -replace '#', '#33')
            $pl = New-Object Windows.Controls.StackPanel; $pl.Orientation = 'Horizontal'
            [void]$pl.Children.Add((New-Text $atk.ToUpper() 11 $at 'Bold')); $pn = New-Text "   $($set.Count)" 11 $Pal.Dim 'SemiBold'; [void]$pl.Children.Add($pn)
            $pill.Child = $pl; [Windows.Controls.DockPanel]::SetDock($pill, 'Left'); [void]$band.Children.Add($pill)
            $ln = New-Object Windows.Controls.Border; $ln.Height = 2; $ln.CornerRadius = 1; $ln.Margin = '10,0,0,0'; $ln.VerticalAlignment = 'Center'
            $ln.Background = New-Grad ($at -replace '#', '#66') ($at -replace '#', '#00') '1,0'
            [void]$band.Children.Add($ln)
            [void]$body.Children.Add($band)
            $items = New-Object System.Collections.ArrayList
            foreach ($p in $set) {
                $r = New-PresetRow $p $liveMacs
                if ($r.Ready) { $ready++ }
                if ($r.Look -in @('next', 'todo', 'partial', 'redo')) { $needed++ }
                [void]$items.Add($r)
            }
            $lb = New-Object Windows.Controls.ListBox
            $lb.Style = $win.FindResource('CardGroup'); $lb.ItemContainerStyle = $win.FindResource('PresetCardItem'); $lb.ItemTemplate = $win.FindResource('PresetCardTpl')
            $lb.ItemsSource = $items
            $lb.Add_SelectionChanged($onPick); $lb.Add_MouseDoubleClick($onUse)
            [void]$script:CardGroups.Add($lb)
            [void]$body.Children.Add($lb)
        }
        $readyAll += $ready
        $bits = @("$($mine.Count) preset$(if ($mine.Count -ne 1) { 's' })")
        if ($ready) { $bits += "$ready ready to run now" }
        if ($needed) { $bits += "$needed the campaign still needs" }
        $sub.Text = $bits -join '   ·   '
        [void]$layer.Children.Add($body)
        $box.Child = $layer
        [void]$g.Children.Add($box)
    }
    $ui.CapSub.Text = ("{0} preset{1} from {2} {3}  ·  {4} ready to run on this laptop now  ·  click a card to look inside, double-click to use it" -f
        $rows.Count, $(if ($rows.Count -ne 1) { 's' } else { '' }), $owners.Count, $(if ($owners.Count -eq 1) { 'person' } else { 'people' }), $readyAll)
    Sync-PresetSelection
}
function Update-SlotIndex {
    # campaign cell -> slot, for the ribbons and the 'needs it / done' filter
    $script:SlotByKey = @{}
    if ($script:Campaign) { foreach ($s in @($script:Campaign.slots)) { $script:SlotByKey[(Get-CellKey $(if ($s.kind -eq 'benign') { 'baseline' } else { $s.attack }) $s.topology $s.location $s.scenario)] = $s } }
}
function Update-CaptureChips {
    # people + attack chips (built from the hidden pickers, kept in step with them)
    $ui.OwnerChips.Children.Clear()
    foreach ($o in @($ui.OwnerPick.ItemsSource)) {
        $rb = New-Object Windows.Controls.RadioButton; $rb.Style = $win.FindResource('Chip'); $rb.GroupName = 'capOwner'; $rb.Tag = $o; $rb.Padding = '0'
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'; $sp.Margin = '-6,0,0,0'
        $tone = if ($o -eq 'everyone') { @('#8B5CF6', '#22D3EE') } else { Get-OwnerTone $o }
        [void]$sp.Children.Add((New-Avatar $o $tone 20))
        $n = if ($o -eq 'everyone') { @($script:Presets).Count } else { @($script:Presets | Where-Object { $_.Owner -eq $o }).Count }
        $nt = New-Object Windows.Controls.TextBlock; $nt.Text = $(if ($o -eq 'everyone') { 'Everyone' } else { $o }); $nt.VerticalAlignment = 'Center'; $nt.Margin = '7,0,0,0'
        [void]$sp.Children.Add($nt)
        $ct = New-Text "  $n" 11 $Pal.Faint 'SemiBold'; [void]$sp.Children.Add($ct)
        if ($o -eq $script:Me) { [void]$sp.Children.Add((New-Text ('  ' + [char]0x2665) 11 $Pal.Pink)) }
        $rb.Content = $sp
        $rb.IsChecked = ($o -eq [string]$ui.OwnerPick.SelectedItem)
        $rb.Add_Checked({ param($x) if ([string]$ui.OwnerPick.SelectedItem -ne [string]$x.Tag) { $ui.OwnerPick.SelectedItem = [string]$x.Tag } })
        [void]$ui.OwnerChips.Children.Add($rb)
    }
    if ($ui.AttackChips.Children.Count) { return }
    foreach ($a in @($ui.AttackPick.ItemsSource)) {
        $rb = New-Object Windows.Controls.RadioButton; $rb.Style = $win.FindResource('Chip'); $rb.GroupName = 'capAtk'; $rb.Tag = $a
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        if ($script:AtkTone[$a]) { $d = New-Object Windows.Shapes.Ellipse; $d.Width = 8; $d.Height = 8; $d.Fill = & $brush $script:AtkTone[$a]; $d.Margin = '0,0,7,0'; $d.VerticalAlignment = 'Center'; [void]$sp.Children.Add($d) }
        $t = New-Object Windows.Controls.TextBlock; $t.Text = $(if ($a -eq 'all attacks') { 'All' } else { $a }); $t.VerticalAlignment = 'Center'; [void]$sp.Children.Add($t)
        $rb.Content = $sp
        $rb.IsChecked = ($a -eq [string]$ui.AttackPick.SelectedItem)
        $rb.Add_Checked({ param($x) if ([string]$ui.AttackPick.SelectedItem -ne [string]$x.Tag) { $ui.AttackPick.SelectedItem = [string]$x.Tag } })
        [void]$ui.AttackChips.Children.Add($rb)
    }
}
function Sync-CaptureChips {
    foreach ($rb in @($ui.OwnerChips.Children)) { if ([string]$rb.Tag -eq [string]$ui.OwnerPick.SelectedItem) { $rb.IsChecked = $true } }
    foreach ($rb in @($ui.AttackChips.Children)) { if ([string]$rb.Tag -eq [string]$ui.AttackPick.SelectedItem) { $rb.IsChecked = $true } }
}
function Update-CaptureHero {
    # the campaign's next run on top of the page, with the preset for it
    $n = if ($script:Campaign) { $script:Campaign.next } else { $null }
    if (-not $n) { $ui.CapHero.Visibility = 'Collapsed'; return }
    $a = if ($n.kind -eq 'benign') { 'baseline' } else { [string]$n.attack }
    $key = Get-CellKey $a $n.topology $n.location $n.scenario
    $hits = @($script:Presets | Where-Object { (Get-CellKey $_.Attack $_.Topology $_.Location $_.Scenario) -eq $key } | Sort-Object Saved -Descending)
    $ui.CapHeroTitle.Text = "$a  ·  $($n.topology -replace '_', ' ')  ·  $($n.location -replace '_', ' ')  ·  $($n.scenario)"
    if ($hits.Count) {
        $liveMacs = Get-LiveMacs; $best = $hits[0]
        $bs = @($best.Cfg.boards); $here = @($bs | Where-Object { Test-BoardHere $_ $liveMacs }).Count
        $ui.CapHeroSub.Text = ("{0} preset{1} for it  ·  newest is {2}'s  ·  {3}/{4} of its boards plugged in here" -f $hits.Count, $(if ($hits.Count -ne 1) { 's' } else { '' }), $best.Owner, $here, $bs.Count)
        $ui.CapHeroGo.Content = 'Pick it  ' + [char]0x2192
    } else {
        $ui.CapHeroSub.Text = 'Nobody has a preset for it yet - make one, the cell is filled in for you.'
        $ui.CapHeroGo.Content = '+  Make its preset'
    }
    if ($ui.CapHero.Visibility -ne 'Visible') { $ui.CapHero.Visibility = 'Visible'; $ui.CapHero.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Fade 0 1 400)) }
}
$ui.CapHeroGo.Add_Click({ if ($script:Campaign -and $script:Campaign.next) { Start-CellCapture $script:Campaign.next } })
function Update-CaptureCampaign {
    # the campaign plan / redo list arrived or changed: ribbons + banner follow
    # (only when the page is open - otherwise when it is next opened)
    $script:CampVer++
    if (-not $script:Presets) { return }
    if ($ui.Pages.SelectedIndex -ne 1) { $script:CapDirty = $true; return }
    Update-CaptureHero; Update-PresetGallery -Quiet
}
$ui.Pages.Add_SelectionChanged({
    param($s, $e)
    if ($e.OriginalSource -ne $ui.Pages -or $ui.Pages.SelectedIndex -ne 1) { return }
    if ($script:CapDirty -and $script:Presets) {
        $script:CapDirty = $false
        $keep = if ($ui.PresetGrid.SelectedItem) { $ui.PresetGrid.SelectedItem.Path } else { '' }
        Update-PresetGrid; if ($keep) { Select-Preset $keep }
        Update-CaptureHero
    }
})
function Update-CaptureLive {
    # a board plugged in / out / identified: card dots, banner and detail follow
    if (-not $script:Presets) { return }
    $keep = if ($ui.PresetGrid.SelectedItem) { $ui.PresetGrid.SelectedItem.Path } else { '' }
    if ($ui.ReadyOnly.IsChecked) { Update-PresetGrid; if ($keep) { Select-Preset $keep } } else { Update-PresetGallery -Quiet }
    Update-CaptureHero; Show-PresetDetail
}

function Update-PresetGrid {
    $who = [string]$ui.OwnerPick.SelectedItem; $atk = [string]$ui.AttackPick.SelectedItem
    # search: every typed word must appear somewhere (cell, owner, file, any MAC)
    $words = @(([string]$ui.PresetSearch.Text).ToLower() -split '\s+' | Where-Object { $_ })
    $ui.PresetSearchHint.Visibility = $(if ($ui.PresetSearch.Text) { 'Collapsed' } else { 'Visible' })
    $liveMacs = Get-LiveMacs
    Update-SlotIndex
    $fTopo = if ($ui.PresetFTopo.SelectedIndex -gt 0) { [string]$ui.PresetFTopo.SelectedItem } else { '' }
    $fLoc = if ($ui.PresetFLoc.SelectedIndex -gt 0) { [string]$ui.PresetFLoc.SelectedItem } else { '' }
    $fScn = if ($ui.PresetFScn.SelectedIndex -gt 0) { [string]$ui.PresetFScn.SelectedItem } else { '' }
    $fState = if ($ui.PresetFNeed.IsChecked) { @('next', 'todo', 'partial', 'redo') } elseif ($ui.PresetFDone.IsChecked) { @('ok', 'done', 'check', 'analyse') } else { $null }
    $rows = @($script:Presets | Where-Object {
        ($who -eq 'everyone' -or $_.Owner -eq $who) -and ($atk -eq 'all attacks' -or $_.Attack -eq $atk) -and
        (-not $fTopo -or ($_.Topology -replace '^partial$', 'partial_mesh') -eq $fTopo) -and (-not $fLoc -or $_.Location -eq $fLoc) -and
        (-not $fScn -or $_.Scenario -eq $fScn) -and (-not $fState -or (New-PresetRow $_ $liveMacs).Look -in $fState) -and
        $(if (-not $ui.ReadyOnly.IsChecked) { $true } else { $bs = @($_.Cfg.boards); $bs.Count -and -not @($bs | Where-Object { -not (Test-BoardHere $_ $liveMacs) }).Count }) -and
        $(if (-not $words.Count) { $true } else {
            $hay = ('{0} {1} {2} {3} {4} {5} {6}' -f $_.Attack, $_.Topology, $_.Location, $_.Scenario, $_.Owner, $_.File, (@($_.Cfg.boards | ForEach-Object { $_.Mac; $_.Port; $_.Label }) -join ' ')).ToLower()
            -not @($words | Where-Object { -not $hay.Contains($_) }).Count }) })
    # sort (user, oct. 18 2026): newest first by default; 'By type' = the old order
    $sortText = 'attack > topology > scenario > location > newest'
    # (user: "group the same attacks, then sort by date" - never one mixed patchwork)
    $atkRank = @{ E = { $r = @('blackhole', 'wormhole', 'baseline').IndexOf([string]$_.Attack); if ($r -lt 0) { 9 } else { $r } } }
    if ($ui.PresetSNew.IsChecked) { $rows = @($rows | Sort-Object $atkRank, @{ E = { $_.Saved }; Descending = $true }); $sortText = 'by attack, newest first' }
    elseif ($ui.PresetSOld.IsChecked) { $rows = @($rows | Sort-Object $atkRank, @{ E = { $_.Saved } }); $sortText = 'by attack, oldest first' }
    # keep the selected preset selected when it is still shown
    $keep = if ($ui.PresetGrid.SelectedItem) { $ui.PresetGrid.SelectedItem.Path } else { '' }
    $ui.PresetGrid.ItemsSource = $rows
    Sync-CaptureChips
    Update-PresetGallery
    if ($rows.Count -and $words.Count) { $ui.PresetGrid.SelectedIndex = 0 }   # searching: the best hit is ready to start
    elseif ($keep) { Select-Preset $keep }
    Set-Status ("{0} preset(s) shown  |  sorted {1}" -f $rows.Count, $sortText)
}
function Update-Presets {
    $script:Presets = Get-Presets
    $script:CardCache = @{}; $script:RowCache = @{}
    $owners = @('everyone') + @($script:Presets | ForEach-Object Owner | Sort-Object -Unique)
    $keep = [string]$ui.OwnerPick.SelectedItem
    $script:Building = $true
    $ui.OwnerPick.ItemsSource = $owners
    $ui.OwnerPick.SelectedItem = $(if ($owners -contains $keep) { $keep } elseif ($script:Me -and $owners -contains $script:Me) { $script:Me } else { 'everyone' })
    if (-not $ui.AttackPick.ItemsSource) { $ui.AttackPick.ItemsSource = @('all attacks', 'blackhole', 'wormhole', 'baseline'); $ui.AttackPick.SelectedIndex = 0 }
    $script:Building = $false
    Update-CaptureChips
    Update-PresetGrid
    Update-CaptureHero
    Update-LastUsedCard
}
$ui.OwnerPick.Add_SelectionChanged({ if ($script:Presets -and -not $script:Building) { Update-PresetGrid } })
$ui.AttackPick.Add_SelectionChanged({ if ($script:Presets -and -not $script:Building) { Update-PresetGrid } })
$ui.ReadyOnly.Add_Checked({ if ($script:Presets) { Update-PresetGrid } })
$ui.PresetFTopo.ItemsSource = @('all topologies', 'linear', 'tree', 'star', 'partial_mesh')
$ui.PresetFLoc.ItemsSource = @('all locations', 'G402', 'DLSU_Library', 'Yuchengco', 'home')
$ui.PresetFScn.ItemsSource = @('all scenarios', 'stationary', 'burst', 'highload', 'jitter', 'mobility', 'powercycle')
foreach ($n in 'PresetFTopo', 'PresetFLoc', 'PresetFScn') { $ui[$n].SelectedIndex = 0; $ui[$n].Add_SelectionChanged({ if ($script:Presets -and -not $script:Building) { Update-PresetGrid } }) }
foreach ($n in 'PresetSNew', 'PresetSOld', 'PresetSType', 'PresetFAll', 'PresetFNeed', 'PresetFDone') { $ui[$n].Add_Checked({ if ($script:Presets -and -not $script:Building) { Update-PresetGrid } }) }
$ui.PresetFClear.Add_Click({
    $script:Building = $true
    foreach ($n in 'PresetFTopo', 'PresetFLoc', 'PresetFScn') { $ui[$n].SelectedIndex = 0 }
    $ui.PresetFAll.IsChecked = $true; $ui.ReadyOnly.IsChecked = $false; $ui.AttackPick.SelectedIndex = 0; $ui.PresetSearch.Text = ''
    $script:Building = $false
    Update-PresetGrid
})
$ui.ReadyOnly.Add_Unchecked({ if ($script:Presets) { Update-PresetGrid } })
$ui.PresetsRefresh.Add_Click({ Update-Presets; Show-PresetDetail })

function Show-PresetDetail {
    $p = $ui.PresetGrid.SelectedItem
    foreach ($b in 'StartCapture', 'OpenPresetFile', 'PresetEdit', 'PresetCopy', 'PresetDelete') { $ui[$b].IsEnabled = [bool]$p }
    $ui.FixPorts.IsEnabled = $false; $ui.FixPorts.Visibility = 'Collapsed'
    $ui.DetBoards.Children.Clear(); $ui.DetChips.Children.Clear()
    if (-not $p) {
        $ui.DetHero.Background = & $brush $Pal.Card2; $ui.DetArt.Content = $null
        $ui.DetKicker.Text = 'PRESET'; $ui.DetTitle.Text = 'Pick a preset'
        $ui.DetFile.Text = 'click one on the left to look inside - double-click to use it straight away'
        foreach ($n in 'DetPorts', 'DetNote', 'DetReadyNum') { $ui[$n].Text = '' }
        $ui.DetReady.Value = 0
        return
    }
    # header: the attack's colours, the mesh drawing, the cell as chips
    $gr = $script:AtkGrad[$p.Attack]; if (-not $gr) { $gr = @($Pal.Accent, $Pal.Pink) }
    $ui.DetHero.Background = New-Grad $gr[0] $gr[1]
    $ui.DetArt.Content = New-TopoArt $p.Topology $p.Attack 112 70
    $ui.DetKicker.Text = ("{0}  ·  {1}" -f $p.Attack.ToUpper(), $(if ($p.Owner -eq '(unfiled)') { 'UNFILED' } else { "$($p.Owner.ToUpper())'S PRESET" + $(if ($p.Owner -eq $script:Me) { '  ' + [char]0x2665 } else { '' }) }))
    $ui.DetTitle.Text = "$($p.Topology -replace '_', ' ')  ·  $($p.Scenario)"
    $ui.DetFile.Text = $p.File + $(if ($p.NameFlag) { '   (!) name does not match its contents - trust the chips' } else { '' })
    $sl = $script:ScnLook[$p.Scenario]
    foreach ($t in @(($p.Location -replace '_', ' '), $(if ($sl) { "$($sl.S) $($p.Scenario)" } else { $p.Scenario }), "repeat $($p.Repeat)", "saved $($p.SavedText)")) {
        [void]$ui.DetChips.Children.Add((New-CapChip $t '#FFFFFF' '#33FFFFFF'))
    }
    $look = Get-PresetLook $p
    if ($look) { $rb = $script:CardRibbon[$look]; $ch = New-CapChip $(if ($look -eq 'next') { [string][char]0x25B6 + ' UP NEXT' } else { $rb.T }) '#FFFFFF' '#55000000'; $ch.ToolTip = $rb.Tip; [void]$ui.DetChips.Children.Add($ch) }
    # A board is found by its MAC first (COM numbers follow the USB socket, so
    # a board moved to another socket is still "here"), then by its port.
    $liveMacs = Get-LiveMacs
    $livePorts = @($script:Live.Keys)
    $moved = 0; $count = 0; $hereN = 0
    $boards = @($p.Cfg.boards | Sort-Object { if ($_.Role -eq 'root') { 1 } else { 0 } })
    foreach ($b in $boards) {
        $count++
        $tone = Get-BoardTone $b
        $role = switch ([string]$b.Kind) {
            'attacker' { 'blackhole ATTACKER' } 'victim' { 'blackhole victim' } 'A' { 'tunnel end (auto A/B)' } 'B' { 'tunnel end (auto A/B)' }
            'control' { 'control (plain fw)' } default { if ($b.Role -eq 'root') { 'ROOT' } else { [string]$b.Display } } }
        if ($b.ScenarioTarget) { $role += '  + target' }
        $sym = if ($b.Role -eq 'root') { [char]0x2605 } elseif ($b.Kind -eq 'attacker') { [char]0x2716 } elseif ($b.Kind -in @('A', 'B')) { [char]0x21C4 } elseif ($b.Kind -eq 'victim') { 'V' } elseif ($b.Kind -eq 'control') { 'C' } else { [char]0x2022 }
        $mac = ([string]$b.Mac).ToLower()
        $at = $liveMacs[$mac]
        $other = if ($script:Live.Contains([string]$b.Port)) { $script:Live[[string]$b.Port].Mac } else { '' }
        if ($at -and $at -eq $b.Port) { $here = $true; $state = 'plugged in'; $st = $Pal.Green }
        elseif ($at) { $here = $true; $state = "on $at"; $st = $Pal.Cyan; $moved++ }
        elseif ($livePorts -contains [string]$b.Port -and $other -and $other -ne $mac) { $here = $false; $state = "$($b.Port) = another board"; $st = $Pal.Red }
        elseif ($livePorts -contains [string]$b.Port) { $here = $true; $state = 'port here (MAC not read)'; $st = $Pal.Amber }
        else { $here = $false; $state = 'not plugged in'; $st = $Pal.Red }
        if ($here) { $hereN++ }
        $nk = $p.Nick[(Get-ShortMac ([string]$b.Mac))]
        # one row: numbered role badge | label + role / port + MAC + nickname | status pill
        $row = New-Object Windows.Controls.Border; $row.CornerRadius = 12; $row.Padding = '10,7'; $row.Margin = '6,0,6,6'
        $row.Background = & $brush $Pal.Card2; $row.BorderThickness = '3,0,0,0'; $row.BorderBrush = & $brush $tone
        $dp = New-Object Windows.Controls.DockPanel
        $badge = New-Object Windows.Controls.Border; $badge.Width = 30; $badge.Height = 30; $badge.CornerRadius = 15; $badge.Margin = '0,0,10,0'
        $badge.Background = & $brush ($tone -replace '#', '#33'); $badge.VerticalAlignment = 'Center'
        $bg = New-Text ([string]$sym) 13 $tone 'Bold'; $bg.HorizontalAlignment = 'Center'; $badge.Child = $bg
        [Windows.Controls.DockPanel]::SetDock($badge, 'Left'); [void]$dp.Children.Add($badge)
        $pill = New-Object Windows.Controls.Border; $pill.CornerRadius = 9; $pill.Padding = '8,2'; $pill.VerticalAlignment = 'Center'; $pill.Margin = '8,0,0,0'
        $pill.Background = & $brush ($st -replace '#', '#2E')
        $pill.Child = New-Text $(if ($here -and $st -eq $Pal.Green) { [string][char]0x2714 + ' ' + $state } else { $state }) 11 $st 'SemiBold'
        [Windows.Controls.DockPanel]::SetDock($pill, 'Right'); [void]$dp.Children.Add($pill)
        $txt = New-Object Windows.Controls.StackPanel; $txt.VerticalAlignment = 'Center'
        $l1 = New-Object Windows.Controls.TextBlock; $l1.TextTrimming = 'CharacterEllipsis'
        $r1 = New-Object Windows.Documents.Run ([string]$b.Label); $r1.FontWeight = 'Bold'; $r1.Foreground = & $brush $Pal.Text; $l1.Inlines.Add($r1)
        $r2 = New-Object Windows.Documents.Run ("   $role"); $r2.FontSize = 11.5; $r2.Foreground = & $brush $tone; $l1.Inlines.Add($r2)
        # the MAC on its own, big and monospaced; the last two bytes (what tells
        # two boards apart, same as the short MACs elsewhere) in the role colour
        $l2 = New-Object Windows.Controls.WrapPanel; $l2.Margin = '0,3,0,0'
        [void]$l2.Children.Add((New-MacChip ([string]$b.Mac) $tone))
        $pt = New-Text ("  {0}{1}" -f $b.Port, $(if ($nk) { "  ·  $nk" } else { '' })) 11.5 $Pal.Dim; $pt.TextTrimming = 'CharacterEllipsis'
        [void]$l2.Children.Add($pt)
        [void]$txt.Children.Add($l1); [void]$txt.Children.Add($l2)
        [void]$dp.Children.Add($txt)
        $row.Child = $dp
        [void]$ui.DetBoards.Children.Add($row)
    }
    $ui.FixPorts.IsEnabled = ($moved -gt 0); $ui.FixPorts.Visibility = $(if ($moved) { 'Visible' } else { 'Collapsed' })
    $ui.DetReady.Maximum = [math]::Max(1, $count)
    $ui.DetReady.BeginAnimation([Windows.Controls.Primitives.RangeBase]::ValueProperty, (New-Fade $ui.DetReady.Value $hereN 500))
    $ui.DetReadyNum.Text = "$hereN / $count here"
    $miss = $count - $hereN
    $rc = if ($miss) { $Pal.Amber } elseif ($moved) { $Pal.Cyan } else { $Pal.Green }
    $ui.DetReadyNum.Foreground = & $brush $rc
    if ($miss) { $ui.DetPorts.Text = "$miss of $count board(s) not plugged in - plug them in; this list updates by itself." }
    elseif ($moved) { $ui.DetPorts.Text = "Every board is here, but $moved moved to another USB socket - press 'Use the ports the boards are on now' (the CLI would also re-match them by MAC)." }
    else { $ui.DetPorts.Text = [string][char]0x2728 + '  Every board is plugged in - ready to start!' }
    $ui.DetPorts.Foreground = & $brush $rc
    $ui.DetNote.Text = switch ($p.Attack) {
        'blackhole' { 'Placement: the attacker only drops traffic that passes THROUGH it - put it between the victims and the root (hop 1-2).' }
        'wormhole'  { 'The two tunnel boards pick A (closer to the root) and B themselves at run start. The root waits until the UART works both ways and A is shallower - then type START.' }
        default     { 'Baseline run - no attacker.' }
    }
}
$ui.PresetGrid.Add_SelectionChanged({ Show-PresetDetail; Sync-PresetSelection })
function Select-Preset([string]$Path) {
    $hit = @($ui.PresetGrid.ItemsSource | Where-Object { $_.Path -eq $Path })
    if ($hit.Count) { $ui.PresetGrid.SelectedItem = $hit[0] }
}
$ui.FixPorts.Add_Click({
    $p = $ui.PresetGrid.SelectedItem; if (-not $p) { return }
    $liveMacs = Get-LiveMacs
    $raw = Get-Content -LiteralPath $p.Path -Raw | ConvertFrom-Json
    $changes = @()
    foreach ($b in @($raw.boards)) {
        $at = $liveMacs[([string]$b.Mac).ToLower()]
        if ($at -and $at -ne $b.Port) { $changes += "$($b.Label): $($b.Port) -> $at"; $b.Port = $at }
    }
    if (-not $changes.Count) { return }
    if (-not (Confirm-Action ("Save these port changes into $($p.File)?`n`n" + ($changes -join "`n")) 'Update ports')) { return }
    $raw | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $p.Path -Encoding UTF8
    Update-Presets; Select-Preset $p.Path
    Show-Toast 'Ports updated' ($changes -join '   ') ([string][char]0xE73E)
})
function Start-CellCapture($Slot) {
    # Campaign / Home -> the capture page with a matching preset selected; no
    # preset for that cell yet -> the editor opens with the cell filled in.
    $a = if ($Slot.kind -eq 'benign' -or $Slot.attack -in @('none', 'baseline')) { 'baseline' } else { [string]$Slot.attack }
    $topo = [string]$Slot.topology; $loc = [string]$Slot.location; $scn = [string]$Slot.scenario
    if (-not $script:Presets) { Update-Presets }
    $hits = @($script:Presets | Where-Object { $_.Attack -eq $a -and $_.Location -eq $loc -and $_.Scenario -eq $scn -and
                                               (($_.Topology -replace '^partial$', 'partial_mesh') -eq ($topo -replace '^partial$', 'partial_mesh')) })
    Show-Page 1
    if (-not $hits.Count) {
        $ans = [Windows.MessageBox]::Show("Nobody has a preset for`n`n    $a / $topo / $loc / $scn`n`nMake one now? (the attack, topology, location and scenario are filled in for you)", 'No preset yet', 'YesNo', 'Question')
        if ($ans -ne 'Yes') { return }
        if (Show-PresetEditor -Prefill @{ attack = $a; topology = $topo; location = $loc; scenario = $scn }) {
            Update-Presets; $ui.OwnerPick.SelectedItem = 'everyone'; $ui.AttackPick.SelectedIndex = 0
            if ($script:EditorSavedPath) { Select-Preset $script:EditorSavedPath }
        }
        return
    }
    $ui.OwnerPick.SelectedItem = 'everyone'; $ui.AttackPick.SelectedItem = $a
    Update-PresetGrid
    $best = @($hits | Sort-Object Saved -Descending)[0]
    Select-Preset $best.Path
    Set-Status ("{0} preset(s) match {1} / {2} / {3} / {4} - the newest is selected" -f $hits.Count, $a, $topo, $loc, $scn) $Pal.Green
}
$script:Captures = New-Object System.Collections.ArrayList
$ui.StartCapture.Add_Click({
    $p = $ui.PresetGrid.SelectedItem; if (-not $p) { return }
    # pre-flight: every board by MAC - moved sockets are fixed in the same
    # step, missing boards are named before anything is flashed
    $liveMacs = Get-LiveMacs
    $moved = @(); $missing = @()
    foreach ($b in @($p.Cfg.boards)) {
        $at = $liveMacs[([string]$b.Mac).ToLower()]
        if ($at -and $at -ne $b.Port) { $moved += "$($b.Label): $($b.Port) -> $at" }
        elseif (-not $at -and -not $script:Live.Contains([string]$b.Port)) { $missing += "$($b.Label)  ($($b.Port), $(Get-ShortMac ([string]$b.Mac)))" }
    }
    if ($missing.Count) {
        $ans = [Windows.MessageBox]::Show(("{0} board(s) of this preset are not plugged in:`n`n    {1}`n`nStart anyway? (boards on another laptop are fine)" -f $missing.Count, ($missing -join "`n    ")), 'Pre-flight', 'YesNo', 'Warning')
        if ($ans -ne 'Yes') { return }
    }
    if ($moved.Count) {
        $ans = [Windows.MessageBox]::Show(("{0} board(s) moved to another USB socket:`n`n    {1}`n`nSave the new ports into the preset and start?" -f $moved.Count, ($moved -join "`n    ")), 'Pre-flight', 'YesNoCancel', 'Question')
        if ($ans -eq 'Cancel') { return }
        if ($ans -eq 'Yes') {
            $raw = Get-Content -LiteralPath $p.Path -Raw | ConvertFrom-Json
            foreach ($b in @($raw.boards)) { $at = $liveMacs[([string]$b.Mac).ToLower()]; if ($at) { $b.Port = $at } }
            $raw | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $p.Path -Encoding UTF8
            Update-Presets; Select-Preset $p.Path; $p = $ui.PresetGrid.SelectedItem
        }
    }
    # the whole run happens on the Live run page (no console window)
    Open-RunPage $p
    Set-Status ("Loaded {0} on Live run - nothing started: press 1 Compile or 2 Wipe + flash + run" -f $p.File) $Pal.Green
})
$ui.OpenPresetFile.Add_Click({ $p = $ui.PresetGrid.SelectedItem; if ($p) { Start-Process notepad $p.Path } })
$ui.PresetNew.Add_Click({ if (Show-PresetEditor) { Update-Presets; if ($script:EditorSavedPath) { Select-Preset $script:EditorSavedPath } } })
$ui.PresetEdit.Add_Click({ $p = $ui.PresetGrid.SelectedItem; if ($p -and (Show-PresetEditor -From $p)) { Update-Presets; Select-Preset $script:EditorSavedPath } })
$ui.PresetCopy.Add_Click({ $p = $ui.PresetGrid.SelectedItem; if ($p -and (Show-PresetEditor -From $p -AsCopy)) { Update-Presets; Select-Preset $script:EditorSavedPath } })
$ui.PresetDelete.Add_Click({
    $p = $ui.PresetGrid.SelectedItem; if (-not $p) { return }
    $ans = [Windows.MessageBox]::Show("Delete this preset for good?`n`n$($p.Owner) \ $($p.File)", 'Delete preset', 'YesNo', 'Warning')
    if ($ans -eq 'Yes') { Remove-Item -LiteralPath $p.Path -Force; Set-Status "Deleted $($p.File)." $Pal.Amber; Update-Presets; Show-PresetDetail }
})

# ── PRESET EDITOR (new / edit / copy) ─────────────────────────────────────────
# Writes the SAME file the CLI's Save-Preset writes (field names, Kind/Role/
# Display strings, root last, savedAt, presets\<owner>\<attack>-<topology>-
# <location>-<scenario>.json), so a preset made here is used by the CLI unchanged.
$ROLE_CHOICES = @{
    blackhole = @('root', 'attacker', 'victim')
    wormhole  = @('root', 'tunnel end', 'control')
    baseline  = @('root', 'plain')
}
function Show-PresetEditor {
    # -Prefill @{ attack; topology; location; scenario }: a NEW preset with the
    # cell already chosen (Campaign -> 'Capture this run' when nobody has one).
    param($From, [switch]$AsCopy, [hashtable]$Prefill)
    [xml]$ex = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Preset" Width="1100" Height="760" Background="$($Pal.Bg)" Foreground="$($Pal.Text)"
        FontFamily="Segoe UI" FontSize="13" WindowStartupLocation="CenterOwner">
  <Window.Resources>
$StyleXaml
    <Style x:Key="L" TargetType="TextBlock"><Setter Property="Foreground" Value="$($Pal.Faint)"/><Setter Property="FontSize" Value="11"/><Setter Property="FontWeight" Value="SemiBold"/><Setter Property="Margin" Value="0,0,0,4"/></Style>
  </Window.Resources>
  <DockPanel Margin="26,22">
    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,16">
      <Border Width="38" Height="38" CornerRadius="11" Background="{StaticResource GradMain}">
        <TextBlock Text="&#xE70F;" FontFamily="Segoe MDL2 Assets" FontSize="17" Foreground="White" HorizontalAlignment="Center" VerticalAlignment="Center"/>
      </Border>
      <TextBlock x:Name="EdTitle" FontSize="21" FontWeight="Bold" Foreground="$($Pal.Text)" VerticalAlignment="Center" Margin="12,0,0,0"/>
    </StackPanel>
    <Border DockPanel.Dock="Top" Style="{StaticResource Card}" Padding="16,14,8,6" Margin="0,0,0,12">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition/><ColumnDefinition Width="80"/><ColumnDefinition Width="100"/>
        </Grid.ColumnDefinitions>
        <StackPanel Grid.Column="0"><TextBlock Style="{StaticResource L}" Text="OWNER"/><ComboBox x:Name="EdOwner" IsEditable="True"/></StackPanel>
        <StackPanel Grid.Column="1"><TextBlock Style="{StaticResource L}" Text="ATTACK"/><ComboBox x:Name="EdAttack"/></StackPanel>
        <StackPanel Grid.Column="2"><TextBlock Style="{StaticResource L}" Text="TOPOLOGY"/><ComboBox x:Name="EdTopology"/></StackPanel>
        <StackPanel Grid.Column="3"><TextBlock Style="{StaticResource L}" Text="LOCATION"/><ComboBox x:Name="EdLocation"/></StackPanel>
        <StackPanel Grid.Column="4"><TextBlock Style="{StaticResource L}" Text="SCENARIO"/><ComboBox x:Name="EdScenario"/></StackPanel>
        <StackPanel Grid.Column="5"><TextBlock Style="{StaticResource L}" Text="REPEAT"/><TextBox x:Name="EdRepeat"/></StackPanel>
        <StackPanel Grid.Column="6"><TextBlock Style="{StaticResource L}" Text="CHILDREN" ToolTip="Total children in the run, across every laptop"/><TextBox x:Name="EdExpected" ToolTip="Total children in the run, across every laptop - the root waits for all of them. 0 = do not wait."/></StackPanel>
      </Grid>
    </Border>
    <DockPanel DockPanel.Dock="Top" Margin="0,0,0,6">
      <Button x:Name="EdAddLive" DockPanel.Dock="Right" Style="{StaticResource Cool}" Content="+  Add every plugged board" Margin="0"/>
      <TextBlock Text="&#xE88E;" FontFamily="Segoe MDL2 Assets" Foreground="$($Pal.Green)" VerticalAlignment="Center" Margin="0,0,8,0"/>
      <TextBlock x:Name="EdPorts" Text="PLUGGED IN NOW - click one to add it (or to fill the selected row)" Style="{StaticResource L}" VerticalAlignment="Center" Margin="0"/>
    </DockPanel>
    <WrapPanel DockPanel.Dock="Top" x:Name="EdLive" Margin="0,0,0,8"/>
    <TextBlock DockPanel.Dock="Top" Text="BOARDS  -  pick the MAC from the list (port fills in by itself); the root is saved last (it is flashed last)" Style="{StaticResource L}"/>
    <StackPanel DockPanel.Dock="Bottom" Margin="0,12,0,0">
      <Border x:Name="EdTargetBox" CornerRadius="10" Background="$($Pal.Card2)" BorderBrush="$($Pal.Line)" BorderThickness="1" Padding="12,8" Margin="0,0,0,10">
        <DockPanel>
          <TextBlock DockPanel.Dock="Left" Text="&#xE7BA;" FontFamily="Segoe MDL2 Assets" x:Name="EdTargetIcon" Foreground="$($Pal.Cyan)" FontSize="16" VerticalAlignment="Top" Margin="0,1,10,0"/>
          <TextBlock x:Name="EdTargetHint" TextWrapping="Wrap" Foreground="$($Pal.Text)" FontSize="12.5"/>
        </DockPanel>
      </Border>
      <TextBlock x:Name="EdProblems" Foreground="$($Pal.Amber)" TextWrapping="Wrap" Margin="0,0,0,10"/>
      <DockPanel>
        <StackPanel Orientation="Horizontal">
          <Button x:Name="EdAdd" Content="+ Add board"/>
          <Button x:Name="EdRemove" Style="{StaticResource Danger}" Content="Remove ticked" ToolTip="Removes every ticked board at once (tick the box at the top of the table to tick them all). Nothing ticked = removes the selected rows (Ctrl / Shift + click picks several)."/>
          <ComboBox x:Name="EdMember" Width="120" Margin="12,0,6,8"/>
          <Button x:Name="EdFill" Content="Add this member's boards"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <Button x:Name="EdCancel" Content="Cancel"/>
          <Button x:Name="EdSave" Style="{StaticResource Primary}" Content="&#x2714;  Save preset" Padding="22,8"/>
        </StackPanel>
      </DockPanel>
    </StackPanel>
    <DataGrid x:Name="EdGrid" IsReadOnly="False" RowHeight="34" SelectionMode="Extended"/>
  </DockPanel>
</Window>
"@
    $ed = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $ex))
    $ed.Owner = $win
    $f = @{}; foreach ($n in 'EdTitle', 'EdOwner', 'EdAttack', 'EdTopology', 'EdLocation', 'EdScenario', 'EdRepeat', 'EdExpected', 'EdGrid',
                             'EdProblems', 'EdAdd', 'EdRemove', 'EdMember', 'EdFill', 'EdCancel', 'EdSave', 'EdPorts', 'EdLive', 'EdAddLive',
                             'EdTargetBox', 'EdTargetHint', 'EdTargetIcon') { $f[$n] = $ed.FindName($n) }

    $members = @()
    try { $members = @((Get-Content (Join-Path $base 'member_boards.json') -Raw | ConvertFrom-Json).members) } catch { }
    $f.EdOwner.ItemsSource = @($members | ForEach-Object name)
    $f.EdMember.ItemsSource = @($members | ForEach-Object name)
    if ($members.Count) { $f.EdMember.SelectedIndex = 0 }
    $f.EdAttack.ItemsSource = @('blackhole', 'wormhole', 'baseline')
    $f.EdTopology.ItemsSource = @('linear', 'tree', 'star', 'partial')
    $f.EdLocation.ItemsSource = @('G402', 'DLSU_Library', 'Yuchengco', 'home')
    $f.EdScenario.ItemsSource = @('stationary', 'burst', 'highload', 'jitter', 'mobility', 'powercycle')

    # Every board this laptop knows by its FULL MAC: plugged in now (live read)
    # first, then every MAC saved in any preset. The MAC column picks from it,
    # so nobody types a MAC.
    $catalog = @(Get-BoardCatalog)
    $byMac = @{}; foreach ($k in $catalog) { $byMac[$k.Mac] = $k }

    # the board table: a DataTable (reliable two-way editing in a DataGrid)
    $dt = New-Object System.Data.DataTable
    foreach ($col in 'Label', 'Port', 'Role', 'Mac') { [void]$dt.Columns.Add($col, [string]) }
    [void]$dt.Columns.Add('Target', [bool])
    [void]$dt.Columns.Add('Board', [string])
    # Pick = the tick box in front of every row, so several boards go in one
    # Remove (user, oct. 18 2026: removing one at a time was a hassle)
    $pickCol = $dt.Columns.Add('Pick', [bool]); $pickCol.DefaultValue = $false
    $grid = $f.EdGrid
    $tickCol = New-Object Windows.Controls.DataGridTemplateColumn; $tickCol.Width = 44
    $tickAll = New-Object Windows.Controls.CheckBox; $tickAll.Style = $ed.FindResource('TickBox'); $tickAll.ToolTip = 'Tick / untick every board'
    $tickCol.Header = $tickAll
    $tf = New-Object Windows.FrameworkElementFactory ([Windows.Controls.CheckBox])
    $tf.SetValue([Windows.FrameworkElement]::StyleProperty, $ed.FindResource('TickBox'))
    $pb = New-Object Windows.Data.Binding 'Pick'; $pb.Mode = 'TwoWay'; $pb.UpdateSourceTrigger = 'PropertyChanged'
    $tf.SetBinding([Windows.Controls.Primitives.ToggleButton]::IsCheckedProperty, $pb)
    $tickCol.CellTemplate = New-Object Windows.DataTemplate; $tickCol.CellTemplate.VisualTree = $tf
    [void]$grid.Columns.Add($tickCol)
    $mkText = { param($h, $b, $w) $c = New-Object Windows.Controls.DataGridTextColumn; $c.Header = $h; $c.Binding = New-Object Windows.Data.Binding $b; $c.Width = $w; $c }
    [void]$grid.Columns.Add((& $mkText 'LABEL' 'Label' 100))
    $roleCol = New-Object Windows.Controls.DataGridComboBoxColumn
    $roleCol.Header = 'ROLE'; $roleCol.Width = 130; $roleCol.SelectedItemBinding = New-Object Windows.Data.Binding 'Role'
    [void]$grid.Columns.Add($roleCol)
    # MAC: an editable drop-down of the catalog (typing still works for a board
    # never seen before). Picking an entry also fills Port + Board (ColumnChanged).
    $macCol = New-Object Windows.Controls.DataGridTemplateColumn; $macCol.Header = 'MAC  (pick from the list)'; $macCol.Width = 330
    $show = New-Object Windows.FrameworkElementFactory ([Windows.Controls.TextBlock])
    $show.SetBinding([Windows.Controls.TextBlock]::TextProperty, (New-Object Windows.Data.Binding 'Mac'))
    $show.SetValue([Windows.Controls.TextBlock]::FontFamilyProperty, (New-Object Windows.Media.FontFamily 'Cascadia Mono, Consolas'))
    $show.SetValue([Windows.FrameworkElement]::VerticalAlignmentProperty, [Windows.VerticalAlignment]::Center)
    $macCol.CellTemplate = New-Object Windows.DataTemplate; $macCol.CellTemplate.VisualTree = $show
    $pick = New-Object Windows.FrameworkElementFactory ([Windows.Controls.ComboBox])
    $pick.SetValue([Windows.Controls.ComboBox]::IsEditableProperty, $true)
    $pick.SetValue([Windows.Controls.ItemsControl]::ItemsSourceProperty, [string[]]@($catalog | ForEach-Object Display))
    $pick.SetValue([Windows.FrameworkElement]::MarginProperty, (New-Object Windows.Thickness 0))
    $tb = New-Object Windows.Data.Binding 'Mac'; $tb.UpdateSourceTrigger = 'LostFocus'
    $pick.SetBinding([Windows.Controls.ComboBox]::TextProperty, $tb)
    $macCol.CellEditingTemplate = New-Object Windows.DataTemplate; $macCol.CellEditingTemplate.VisualTree = $pick
    [void]$grid.Columns.Add($macCol)
    # Port is still typed-or-filled (any COMx): a saved port that is not plugged
    # in right now must stay visible. Picking a plugged MAC fills it.
    [void]$grid.Columns.Add((& $mkText 'PORT' 'Port' 80))
    $bc = & $mkText 'BOARD' 'Board' 190; $bc.IsReadOnly = $true; [void]$grid.Columns.Add($bc)
    $tgt = New-Object Windows.Controls.DataGridCheckBoxColumn; $tgt.Header = 'SCENARIO TARGET'; $tgt.Binding = New-Object Windows.Data.Binding 'Target'; $tgt.Width = 120
    [void]$grid.Columns.Add($tgt)
    # The TARGET column only means something for burst / mobility / powercycle:
    # show it only then, and say in plain words which board to tick (user, oct. 17
    # 2026: "what is the target tick ... I don't know how to use it").
    $showTarget = {
        $scn = [string]$f.EdScenario.SelectedItem
        $need = $scn -in @('burst', 'mobility', 'powercycle')
        $tgt.Visibility = $(if ($need) { 'Visible' } else { 'Collapsed' })
        if (-not $need) { foreach ($r in @($dt.Rows | Where-Object { $_.RowState -ne 'Deleted' -and $_.Target })) { $r.Target = $false } }
        $f.EdTargetIcon.Foreground = & $brush $(if ($need) { $Pal.Amber } else { $Pal.Faint })
        $f.EdTargetHint.Text = switch ($scn) {
            'burst'      { "SCENARIO TARGET - tick ONE board: the BURST SENDER. Its firmware fires 300 probes back-to-back 60 s into the attack window (on a baseline run: the same moment). Pick a victim / control child - not the root, the attacker or a tunnel end (their firmware has no burst code). On another laptop? Leave all unticked here." }
            'mobility'   { "SCENARIO TARGET - tick ONE child: the board a person will MOVE from its first spot to its second spot, ONCE, just inside the attack (the Live run beeps and tells you when). On another laptop? Leave all unticked here." }
            'powercycle' { "SCENARIO TARGET - tick ONE child: the board a person will UNPLUG for ~10 s and plug back in, ONCE, just inside the attack (the Live run beeps and tells you when). On another laptop? Leave all unticked here." }
            'highload'   { 'No scenario target for highload - EVERY child sends faster (250 ms), nothing to tick.' }
            'jitter'     { 'No scenario target for jitter - only the ROOT changes (random extra seconds on the phase lengths), nothing to tick.' }
            default      { 'No scenario target for stationary - nobody moves or bursts, nothing to tick.' }
        }
    }
    $f.EdScenario.Add_SelectionChanged($showTarget)
    $grid.ItemsSource = $dt.DefaultView
    $edBusy = @{ On = $false }
    $dt.add_ColumnChanged({
        param($s, $e)
        if ($edBusy.On -or $e.Column.ColumnName -ne 'Mac') { return }
        $edBusy.On = $true
        try {
            $m = [regex]::Match([string]$e.ProposedValue, '(?i)\b([0-9a-f]{2}(:[0-9a-f]{2}){5})\b')
            if ($m.Success) {
                $mac = $m.Groups[1].Value.ToLower()
                $e.Row['Mac'] = $mac
                $k = $byMac[$mac]
                if ($k -and $k.Port) { $e.Row['Port'] = $k.Port }
                $e.Row['Board'] = $(if ($k) { $k.Who } else { '' })
            }
        } finally { $edBusy.On = $false }
    })

    $setRoles = { $a = [string]$f.EdAttack.SelectedItem; if (-not $a) { $a = 'blackhole' }; $roleCol.ItemsSource = $ROLE_CHOICES[$a] }
    $f.EdAttack.Add_SelectionChanged({ & $setRoles })
    # member_boards.json role -> the role list of the chosen attack
    $roleFor = {
        param([string]$MemberRole)
        $a = [string]$f.EdAttack.SelectedItem
        switch ($MemberRole) {
            'root'     { 'root' }
            'attacker' { if ($a -eq 'blackhole') { 'attacker' } elseif ($a -eq 'wormhole') { 'tunnel end' } else { 'plain' } }
            default    { if ($a -eq 'blackhole') { 'victim' } elseif ($a -eq 'wormhole') { 'control' } else { 'plain' } }
        }
    }
    $labelFor = {
        param([string]$Nick, [string]$Role)
        if ($Role -eq 'root') { return 'root' }
        if ($Nick -match 'node\s*(\d+)') { $l = "node$($Matches[1])" } else { $l = '' }
        $used = @($dt.Rows | Where-Object { $_.RowState -ne 'Deleted' } | ForEach-Object { [string]$_.Label })
        if (-not $l -or $used -contains $l) { $n = 2; while ($used -contains "node$n") { $n++ }; $l = "node$n" }
        return $l
    }
    $addBoard = {
        param($K)   # a catalog entry
        $have = @($dt.Rows | Where-Object { $_.RowState -ne 'Deleted' -and [string]$_.Mac -eq $K.Mac })
        if ($have.Count) { $f.EdProblems.Text = "$($K.Mac) is already in the table."; return }
        $sel = $grid.SelectedItem
        if ($sel -and $sel -is [Data.DataRowView] -and -not [string]$sel.Row['Mac']) {   # fill the selected empty row
            $sel.Row['Mac'] = $K.Mac; $sel.Row['Port'] = $K.Port; $sel.Row['Board'] = $K.Who; return
        }
        $role = & $roleFor $K.MemberRole
        if ($role -eq 'root' -and @($dt.Rows | Where-Object { $_.RowState -ne 'Deleted' -and $_.Role -eq 'root' }).Count) { $role = & $roleFor 'child' }
        [void]$dt.Rows.Add((& $labelFor $K.Nick $role), $K.Port, $role, $K.Mac, $false, $K.Who)
    }
    $live = @($catalog | Where-Object Live)
    foreach ($k in $live) {
        $chip = New-Object Windows.Controls.Button
        $chip.Content = "+  $($k.Port)   $($k.Who)"
        $chip.ToolTip = "$($k.Mac)  -  click to add (or fill the selected empty row)"
        $chip.Padding = '12,5'; $chip.Tag = $k
        $chip.Add_Click({ param($s) & $addBoard $s.Tag })
        [void]$f.EdLive.Children.Add($chip)
    }
    if (-not $live.Count) {
        $f.EdPorts.Text = 'NO BOARD PLUGGED IN WITH A KNOWN MAC - plug them in (the MAC is read by itself), or pick MACs from the list below'
        $f.EdAddLive.IsEnabled = $false
    }
    $f.EdAddLive.Add_Click({ foreach ($k in $live) { & $addBoard $k } })

    # fill from an existing preset (edit / copy) or a campaign cell (prefill)
    $oldPath = $null
    if ($From) {
        $c = $From.Cfg
        $f.EdOwner.Text = $(if ($From.Owner -ne '(unfiled)') { $From.Owner } else { '' })
        $f.EdAttack.SelectedItem = $From.Attack
        $f.EdTopology.SelectedItem = [string]$c.topology
        $f.EdLocation.SelectedItem = [string]$c.location
        $f.EdScenario.SelectedItem = $From.Scenario
        $f.EdRepeat.Text = [string]([int]$c.repeat)
        $f.EdExpected.Text = $(if ($c.PSObject.Properties['expectedChildren']) { [string]$c.expectedChildren } else { '0' })
        foreach ($b in @($c.boards)) {
            $role = switch ([string]$b.Kind) { 'A' { 'tunnel end' } 'B' { 'tunnel end' } default { [string]$b.Kind } }
            if ($b.Role -eq 'root') { $role = 'root' }
            $k = $byMac[([string]$b.Mac).ToLower()]
            [void]$dt.Rows.Add([string]$b.Label, [string]$b.Port, $role, [string]$b.Mac, [bool]$b.ScenarioTarget, $(if ($k) { $k.Who } else { '' }))
        }
        if (-not $AsCopy) { $oldPath = $From.Path }
        $f.EdTitle.Text = $(if ($AsCopy) { "Copy of  $($From.File)" } else { "Edit  $($From.File)" })
    } else {
        $f.EdAttack.SelectedIndex = 0; $f.EdTopology.SelectedIndex = 0; $f.EdLocation.SelectedIndex = 0; $f.EdScenario.SelectedIndex = 0
        $f.EdRepeat.Text = '1'; $f.EdExpected.Text = '0'
        $f.EdTitle.Text = 'New preset'
        if ($Prefill) {
            $f.EdAttack.SelectedItem = $Prefill.attack
            $f.EdTopology.SelectedItem = $(if ($Prefill.topology -eq 'partial_mesh') { 'partial' } else { $Prefill.topology })
            $f.EdLocation.SelectedItem = $Prefill.location
            $f.EdScenario.SelectedItem = $Prefill.scenario
            $f.EdTitle.Text = "New preset for  $($Prefill.attack) / $($Prefill.topology) / $($Prefill.location) / $($Prefill.scenario)"
        }
        if ($script:Me) { $f.EdOwner.Text = $script:Me }
        # straight to work: every plugged board is already in the table
        if ($live.Count) { foreach ($k in $live) { & $addBoard $k } }
    }
    & $setRoles

    $f.EdAdd.Add_Click({
        $used = @($dt.Rows | ForEach-Object { $_.Label })
        $n = 2; while ($used -contains "node$n") { $n++ }
        [void]$dt.Rows.Add("node$n", '', $(if ($f.EdAttack.SelectedItem -eq 'wormhole') { 'control' } elseif ($f.EdAttack.SelectedItem -eq 'baseline') { 'plain' } else { 'victim' }), '', $false, '')
    })
    $setRemove = {
        $n = @($dt.Rows | Where-Object { $_.RowState -ne 'Deleted' -and $_['Pick'] -eq $true }).Count
        $f.EdRemove.Content = $(if ($n) { "Remove $n ticked" } else { 'Remove ticked' })
    }
    $dt.add_ColumnChanged({ param($s, $e) if ($e.Column.ColumnName -eq 'Pick') { & $setRemove } })
    $tickAll.Add_Click({
        $on = [bool]$tickAll.IsChecked
        foreach ($r in @($dt.Rows | Where-Object { $_.RowState -ne 'Deleted' })) { $r['Pick'] = $on }
        & $setRemove
    })
    $f.EdRemove.Add_Click({
        [void]$grid.CommitEdit(); [void]$grid.CommitEdit()
        $rows = @($dt.Rows | Where-Object { $_.RowState -ne 'Deleted' -and $_['Pick'] -eq $true })
        if (-not $rows.Count) { $rows = @($grid.SelectedItems | Where-Object { $_ -is [Data.DataRowView] } | ForEach-Object { $_.Row }) }
        if (-not $rows.Count) { $f.EdProblems.Text = 'Tick the boards to remove (or select rows with Ctrl / Shift + click), then press Remove.'; return }
        foreach ($r in $rows) { $r.Delete() }
        $tickAll.IsChecked = $false; & $setRemove
        $f.EdProblems.Text = "Removed $($rows.Count) board(s)."
    })
    $f.EdFill.Add_Click({
        $m = $members | Where-Object { $_.name -eq $f.EdMember.SelectedItem } | Select-Object -First 1
        if (-not $m) { return }
        $short = 0
        foreach ($b in $m.boards) {
            $role = & $roleFor ([string]$b.role)
            # member_boards.json keeps only first:last byte - use the full MAC
            # if this laptop has seen that board (plugged in, or in a preset).
            $sm = (Get-ShortMac ([string]$b.mac)).ToLower()
            $k = $catalog | Where-Object { (Get-ShortMac $_.Mac).ToLower() -eq $sm } | Select-Object -First 1
            $mac = if ($k) { $k.Mac } else { $short++; [string]$b.mac }
            [void]$dt.Rows.Add((& $labelFor ([string]$b.nickname) $role), $(if ($k) { $k.Port } else { '' }), $role, $mac, $false, $(if ($k) { $k.Who } else { "$($b.nickname) [$($m.name)]" }))
        }
        $f.EdProblems.Text = "Added $($m.name)'s boards." + $(if ($short) { " $short of them only have a SHORT MAC (never seen in full here) - plug them in and pick the full MAC from the list." } else { '' })
    })
    $f.EdCancel.Add_Click({ $ed.DialogResult = $false })

    $f.EdSave.Add_Click({
        [void]$grid.CommitEdit(); [void]$grid.CommitEdit()
        $a = [string]$f.EdAttack.SelectedItem; $topo = [string]$f.EdTopology.SelectedItem
        $loc = [string]$f.EdLocation.SelectedItem; $scn = [string]$f.EdScenario.SelectedItem
        $owner = ([string]$f.EdOwner.Text).Trim()
        $rows = @($dt.Rows | Where-Object { $_.RowState -ne 'Deleted' })
        $probs = @()
        if (-not $owner) { $probs += 'Pick an owner (whose boards these are).' }
        $rep = 0; if (-not [int]::TryParse($f.EdRepeat.Text, [ref]$rep) -or $rep -lt 1) { $probs += 'Repeat must be a number from 1.' }
        $exp = 0; if (-not [int]::TryParse($f.EdExpected.Text, [ref]$exp) -or $exp -lt 0) { $probs += 'Children must be a number (0 = do not wait).' }
        if (-not $rows.Count) { $probs += 'Add at least one board.' }
        $labels = @($rows | ForEach-Object { ([string]$_.Label).Trim() })
        if (@($labels | Where-Object { -not $_ }).Count) { $probs += 'Every board needs a label.' }
        if (@($labels | Group-Object | Where-Object Count -gt 1).Count) { $probs += 'Two boards share a label.' }
        $roles = @($rows | ForEach-Object { [string]$_.Role })
        foreach ($r in $roles) { if ($ROLE_CHOICES[$a] -notcontains $r) { $probs += "Role '$r' does not fit a $a preset."; break } }
        if (@($roles | Where-Object { $_ -eq 'root' }).Count -gt 1) { $probs += 'Only one root.' }
        if ($a -eq 'blackhole' -and @($roles | Where-Object { $_ -eq 'attacker' }).Count -gt 1) { $probs += 'A blackhole has exactly one attacker.' }
        $ends = @($roles | Where-Object { $_ -eq 'tunnel end' }).Count
        if ($a -eq 'wormhole' -and $ends -notin @(0, 2)) { $probs += 'A wormhole needs the 2 boards on the UART cable (or 0 if they live on another laptop).' }
        $tg = @($rows | Where-Object { $_.Target }).Count
        if ($tg -gt 1) { $probs += 'Only one scenario target.' }
        if ($tg -and $scn -notin @('burst', 'mobility', 'powercycle')) { $probs += "A $scn run has no target board - untick it." }
        # Same rule as the CLI's Test-BurstEligible: only victim_main.c has burst
        # code, so a target on the root / attacker / tunnel end would burst nothing
        # and the CLI refuses the preset at Start.
        $tgRow = @($rows | Where-Object { $_.Target }) | Select-Object -First 1
        if ($tgRow -and [string]$tgRow.Role -eq 'root') { $probs += 'The root cannot be the scenario target - tick a child.' }
        elseif ($tgRow -and $scn -eq 'burst' -and [string]$tgRow.Role -notin @('victim', 'control', 'plain')) {
            $probs += "The burst target must be a $(if ($a -eq 'wormhole') { 'control' } else { 'victim' }) board - a $($tgRow.Role) has no burst code."
        }
        foreach ($r in $rows) { if ($r.Mac -and ([string]$r.Mac) -notmatch '^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$' -and ([string]$r.Mac) -notmatch '^[0-9A-Fa-f]{2}:[0-9A-Fa-f]{2}$') { $probs += "MAC '$($r.Mac)' is not aa:bb:cc:dd:ee:ff."; break } }
        if ($probs.Count) { $f.EdProblems.Text = ($probs -join "`n"); return }

        $attackField = if ($a -eq 'baseline') { 'none' } else { $a }
        $fileName = '{0}-{1}-{2}-{3}.json' -f $a, $(if ($topo -eq 'partial') { 'partial_mesh' } else { $topo }), $loc.ToLower(), $scn
        $dir = Join-Path (Join-Path $base 'presets') $owner
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
        $path = Join-Path $dir $fileName
        if ((Test-Path $path) -and $path -ne $oldPath) {
            $ow = [Windows.MessageBox]::Show("$owner already has $fileName.`nReplace it?", 'Preset exists', 'YesNo', 'Warning')
            if ($ow -ne 'Yes') { return }
        }
        $tun = 0
        $ordered = @($rows | Sort-Object { if ($_.Role -eq 'root') { 1 } else { 0 } })
        $boards = foreach ($r in $ordered) {
            $role = [string]$r.Role
            $kind = $role; $disp = ''; $boardRole = 'child'
            switch ($role) {
                'root'       { $boardRole = 'root'; $kind = 'root'; $disp = 'ROOT (announces the phases)' }
                'attacker'   { $disp = 'blackhole ATTACKER' }
                'victim'     { $disp = 'blackhole victim' }
                'control'    { $disp = 'control (plain firmware)' }
                'plain'      { $disp = 'plain child' }
                'tunnel end' { $tun++; $kind = $(if ($tun -eq 1) { 'A' } else { 'B' }); $disp = "wormhole tunnel board $tun (entry/exit chosen automatically)" }
            }
            if ($r.Target) { $disp += " + $($scn.ToUpper()) TARGET" }
            [pscustomobject]@{ Label = ([string]$r.Label).Trim(); Port = ([string]$r.Port).Trim(); Role = $boardRole; Kind = $kind
                               Display = $disp; Mac = ([string]$r.Mac).Trim().ToLower(); ScenarioTarget = [bool]$r.Target }
        }
        $fields = [ordered]@{ attack = $attackField; topology = $topo; location = $loc; scenario = $scn; owner = $owner; repeat = $rep }
        if ($exp -gt 0) { $fields.expectedChildren = $exp }
        $fields.savedAt = (Get-Date).ToString('yyyy-MM-dd HH:mm')
        $fields.boards = @($boards)
        [pscustomobject]$fields | ConvertTo-Json -Depth 6 | Set-Content -Path $path -Encoding UTF8
        if ($oldPath -and $oldPath -ne $path -and (Test-Path $oldPath)) { Remove-Item -LiteralPath $oldPath -Force }   # renamed by the edit
        Set-Status "Saved $owner\$fileName" $Pal.Green
        $script:EditorSavedPath = $path
        $ed.DialogResult = $true
    })
    $script:EditorSavedPath = $null
    # -SelfTest drives the REAL modal dialog through this hook (it runs while
    # ShowDialog is open, so every handler sees the editor's state exactly as
    # when a person clicks). Never set in normal use.
    if ($script:EditorHook) {
        $ed.WindowStartupLocation = 'Manual'; $ed.Left = -20000; $ed.Top = 0; $ed.ShowInTaskbar = $false
        $ed.Add_ContentRendered({ & $script:EditorHook })
    }
    & $showTarget
    Initialize-PresetEditorNote $ed $f $(if ($AsCopy) { $null } else { $From })
    return [bool]$ed.ShowDialog()
}

# ── VERIFY & ANALYSE ──────────────────────────────────────────────────────────
function Add-Report([string]$Text) {
    # the Full report tab: same colouring as the consoles (New-ConsoleParagraph)
    $doc = New-Object Windows.Documents.FlowDocument
    $doc.PagePadding = '0'; $doc.LineHeight = 1
    foreach ($line in ($Text -replace "\x1b\[[0-9;]*m", '' -split "`r?`n")) { [void]$doc.Blocks.Add((New-ConsoleParagraph $line '')) }
    $ui.VerifyOut.Document = $doc
}
# ── VERIFY & ANALYSE (oct. 17 2026 redesign) ─────────────────────────────────
# Every CAPTURED run (datasets\exports), not only analysed ones, with a badge:
# not analysed / new data since the analysis / the last verdict. The verdict and
# the report of each run are cached per laptop (%LOCALAPPDATA%\NIS16) so a run
# shows its result without re-running anything. Nothing here changes data:
# analysis = analyze.ps1 -Verify, verify = verify_attack.py, as before.
$script:AnaDir = Join-Path $env:LOCALAPPDATA 'NIS16'
$script:Verdicts = @{}
function Get-AnaKey($C) { '{0}/{1}/{2}/{3}' -f $C.Attack, $C.Topology, $C.Location, $C.Scenario }
function Read-Verdicts {
    try {
        $j = Get-Content (Join-Path $script:AnaDir 'verdicts.json') -Raw -ErrorAction Stop | ConvertFrom-Json
        foreach ($p in $j.PSObject.Properties) { $script:Verdicts[$p.Name] = $p.Value }
    } catch { }
}
function Get-VerdictCode([string]$Text) {
    # from verify_attack / analyze.ps1 text: 0 confirmed, 3 setup invalid, 2 inconclusive, 1 not confirmed, -1 none
    $t = $Text -replace "\x1b\[[0-9;]*m", ''
    $v = @($t -split "`r?`n" | Where-Object { $_ -match '^\s*(VERDICT|RESULT)\b|^\s*attack\s*:' }) -join ' '
    if (-not $v) { return -1 }
    if ($v -match 'SETUP INVALID') { return 3 }
    if ($v -match 'INCONCLUSIVE') { return 2 }
    if ($v -match 'NOT CONFIRMED') { return 1 }
    if ($v -match 'CONFIRMED') { return 0 }
    return -1
}
function Save-AnaResult([string]$Key, [string]$Text, [int]$Code = -99, [string]$Data = '') {
    if ($SelfTest) { return }
    if ($Code -eq -99) { $Code = Get-VerdictCode $Text }
    $t = $Text -replace "\x1b\[[0-9;]*m", ''
    $line = @($t -split "`r?`n" | Where-Object { $_ -match '^\s*VERDICT\s*:' } | Select-Object -Last 1)
    if (-not $line) { $line = @($t -split "`r?`n" | Where-Object { $_ -match '^\s*RESULT' } | Select-Object -First 1) }
    try {
        New-Item -ItemType Directory -Force -Path (Join-Path $script:AnaDir 'reports') | Out-Null
        [IO.File]::WriteAllText((Join-Path $script:AnaDir ('reports\' + ($Key -replace '/', '__') + '.txt')), $t)
        # oct. 21 2026 (user: "selected run notes didn't match the Verify page"): the list in
        # memory is from GUI start; saving it whole wrote every OTHER run's old verdict back
        # over results verified meanwhile (a batch Verify, a sync). Re-read the file first.
        Read-Verdicts
        if ($Code -ge 0) {
            $prevData = if ($script:Verdicts[$Key] -and $script:Verdicts[$Key].PSObject.Properties['Data']) { $script:Verdicts[$Key].Data } else { '' }
            $script:Verdicts[$Key] = [pscustomobject]@{ Code = $Code; Line = ([string]$line).Trim(); When = (Get-Date).ToString('yyyy-MM-dd HH:mm'); Data = $(if ($Data) { $Data } else { $prevData }) }
            $o = [ordered]@{}; foreach ($k in ($script:Verdicts.Keys | Sort-Object)) { $o[$k] = $script:Verdicts[$k] }
            [pscustomobject]$o | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $script:AnaDir 'verdicts.json') -Encoding UTF8
        } elseif ($script:Verdicts.ContainsKey($Key)) {
            # oct. 20 2026: the new report has NO verdict (tool error / analysis stopped) - drop
            # the old one, or the banner keeps showing the previous result over the new report
            [void]$script:Verdicts.Remove($Key)
            $o = [ordered]@{}; foreach ($k in ($script:Verdicts.Keys | Sort-Object)) { $o[$k] = $script:Verdicts[$k] }
            [pscustomobject]$o | ConvertTo-Json -Depth 4 | Set-Content -Path (Join-Path $script:AnaDir 'verdicts.json') -Encoding UTF8
        }
    } catch { }
}
function Get-AnaReport([string]$Key) {
    $f = Join-Path $script:AnaDir ('reports\' + ($Key -replace '/', '__') + '.txt')
    if (Test-Path $f) { return [IO.File]::ReadAllText($f) } else { return '' }
}
function Initialize-GuiReportTidy {
    # oct. 19 2026 (user: "why do some runs not show the new verdict"): a saved report
    # of a run whose export folder no longer exists (deleted / renamed run) is never
    # re-verified, so it would show an old verdict forever. Park it in reports\_orphaned
    # (nothing deleted). Runs once at start; a few file checks, no data read.
    try {
        $rd = Join-Path $script:AnaDir 'reports'; if (-not (Test-Path $rd)) { return }
        $exp = Join-Path $base 'datasets\exports'
        foreach ($f in Get-ChildItem $rd -Filter '*.txt' -File -ErrorAction SilentlyContinue) {
            $parts = $f.BaseName -split '__'
            if ($parts.Count -ne 4) { continue }
            $parts[1] = $parts[1] -replace '^partial$', 'partial_mesh'
            if (Test-Path (Join-Path $exp ($parts -join '\'))) { continue }
            $od = Join-Path $rd '_orphaned'; New-Item -ItemType Directory -Force -Path $od | Out-Null
            Move-Item -LiteralPath $f.FullName -Destination (Join-Path $od $f.Name) -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}
$script:AnaBadge = @{
    todo    = @{ T = 'NOT ANALYSED';  Bg = '#3A2E14'; Fg = $Pal.Amber }
    stale   = @{ T = 'NEW DATA';      Bg = '#13343C'; Fg = $Pal.Cyan }
    ok      = @{ T = 'CONFIRMED';     Bg = '#1F4D3E'; Fg = $Pal.Green }
    invalid = @{ T = 'SETUP INVALID'; Bg = '#3A2E14'; Fg = $Pal.Amber }
    incon   = @{ T = 'INCONCLUSIVE';  Bg = '#3A2E14'; Fg = $Pal.Amber }
    notok   = @{ T = 'FAILED'; Bg = '#3A1E2C'; Fg = $Pal.Red }
    done    = @{ T = 'ANALYSED';      Bg = '#2A2E48'; Fg = $Pal.Dim }
}
function Get-RunStatus([string]$A, [string]$T, [string]$L, [string]$S, [string]$Look) {
    # one run's status in the Campaign words: the redo verdict when it is known, else the
    # verifier code; IN PROGRESS when the analysis is missing / older than the data
    if ($Look -in @('todo', 'stale')) { return @{ K = 'progress'; T = $(if ($Look -eq 'stale') { 'IN PROGRESS - new data' } else { 'IN PROGRESS' }); Bg = '#0F3644'; Fg = $Pal.Cyan } }
    $ck = Get-CellKey $A $T $L $S
    $map = @{ ok = @('DONE', '#123B33', $Pal.Green); check = @('DONE - RECAPTURE ADVISED', '#42330F', $Pal.Amber); required = @('RECAPTURE REQUIRED', '#43260F', '#FB923C')
              redo = @('REDO', '#46182A', $Pal.Red); loading = @('CHECKING...', '#2A2E48', '#E5E7EB') }
    $k = $null
    if ($script:RedoChecking.Contains($ck) -or (-not $script:Redo.Count -and -not $ui.LoadRedo.IsEnabled)) { $k = 'loading' }
    elseif ($script:Redo[$ck]) {
        $r = $script:Redo[$ck]
        $k = switch ([string]$r.severity) {
            'REDO' { Get-RedoKind $r }
            'CHECK' { 'check' }
            default { 'ok' } }
        # yellow says WHY: minor gaps -> recapture advised; any other caveat -> check the notes
        if ($k -eq 'check' -and -not @($r.reasons | Where-Object { [string]$_.text -like 'CONFIRMED - MINOR GAPS*' }).Count) { $map['check'] = @('DONE - CHECK NOTES', '#42330F', $Pal.Amber) }
        # oct. 20 2026: a missing board whose role cannot be placed - never 'DONE'
        if ($k -eq 'check' -and @($r.reasons | Where-Object { [string]$_.text -like 'INVESTIGATE*' }).Count) { $map['check'] = @('INVESTIGATE - missing board', '#42330F', $Pal.Amber) }
    }
    else { $k = switch ($Look) { 'ok' { 'ok' } 'done' { 'ok' } default { 'redo' } } }      # no redo entry (e.g. baseline): the verifier code
    $m = $map[$k]
    return @{ K = $k; T = $m[0]; Bg = $m[1]; Fg = $m[2] }
}

function Update-Cells {
    $keep = if ($ui.CellPick.SelectedItem) { $ui.CellPick.SelectedItem.Text } else { '' }
    $exp = Join-Path $base 'datasets\exports'; $ana = Join-Path $base 'datasets\analysis'
    $cells = @()
    if (Test-Path $exp) {
        foreach ($leaf in Get-ChildItem $exp -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue) {
            $rel = $leaf.FullName.Substring($exp.Length).Trim('\') -split '\\'
            if ($rel.Count -ne 4 -or $rel -contains 'trimmed') { continue }
            $csv = @(Get-ChildItem $leaf.FullName -Filter '*.csv' -File -ErrorAction SilentlyContinue)
            $telem = @($csv | Where-Object { $_.Name -like '*_telem.csv' })
            if (-not $telem.Count) { continue }
            $newest = ($csv | Measure-Object LastWriteTime -Maximum).Maximum
            $adir = Join-Path $ana ($rel -join '\'); $ft = Join-Path $adir 'feature_table.csv'
            $analysed = Test-Path $ft; $atime = if ($analysed) { (Get-Item $ft).LastWriteTime } else { $null }
            $c = [pscustomobject]@{ Attack = $rel[0]; Topology = $rel[1]; Location = $rel[2]; Scenario = $rel[3]
                                    Text = ($rel -join '  /  '); Dir = $(if ($analysed) { $adir } else { $leaf.FullName }); ExportDir = $leaf.FullName; AnaDir = $adir
                                    Table = $ft; Analysed = $analysed; Stale = ($analysed -and $newest -gt $atime.AddSeconds(5)); Boards = $telem.Count
                                    DataTime = $newest; AnaTime = $atime; Art = $null; Look = ''; Status = ''; Badge = ''; BadgeBg = $null; BadgeFg = $null; AtkFg = $null; Rest = ''; Sub = '' }
            $v = $script:Verdicts[(Get-AnaKey $c)]
            $c.Look = if (-not $analysed) { 'todo' } elseif ($c.Stale) { 'stale' } elseif ($v) { switch ([int]$v.Code) { 0 { 'ok' } 3 { 'invalid' } 2 { 'incon' } default { 'notok' } } } else { 'done' }
            # oct. 19 2026: the badge uses the SAME words / colours as the Campaign tile
            # (DONE / DONE - WITH MINOR GAPS / MAJOR GAPS / REDO / IN PROGRESS / CHECKING...)
            $st_ = Get-RunStatus $rel[0] $rel[1] $rel[2] $rel[3] $c.Look
            $c.Status = $st_.K; $c.Badge = $st_.T; $c.BadgeBg = Get-Brush $st_.Bg; $c.BadgeFg = Get-Brush $st_.Fg
            # unwrapped: a list cannot show a picture still inside a PowerShell object
            $c.Art = (Get-TopoImage $c.Topology $c.Attack).psobject.BaseObject
            $c.AtkFg = Get-Brush (Get-AtkHex $c.Attack); $c.Rest = '  /  {0}  /  {1}  /  {2}' -f $c.Topology, $c.Location, $c.Scenario
            $c.Sub = '{0} board(s)  -  data {1}{2}' -f $c.Boards, (Format-When $newest), $(if ($analysed) { "  -  analysed $(Format-When $atime)" } else { '' })
            try { $c.Sub += '  -  next: ' + (Get-NextStep $rel[0] $rel[1] $rel[2] $rel[3]).Text } catch { }
            $cells += $c
        }
    }
    $script:Cells = @($cells | Sort-Object @{ E = { Get-Rank $ATTACK_ORDER $_.Attack } }, @{ E = { Get-Rank $TOPOLOGY_ORDER $_.Topology } },
                                            @{ E = { Get-Rank $LOCATION_ORDER $_.Location } }, @{ E = { Get-Rank $SCENARIO_ORDER $_.Scenario } })
    $ui.CellPick.ItemsSource = $script:Cells
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($ui.CellPick.ItemsSource)
    if ($view) { $view.Filter = [Predicate[object]] { param($o) Test-AnaShown $o } }
    $hit = @($script:Cells | Where-Object Text -eq $keep)
    if ($hit.Count) { $ui.CellPick.SelectedItem = $hit[0] } elseif ($script:Cells.Count) { $ui.CellPick.SelectedIndex = 0 }
    Update-AnaFilter
    $todo = @($script:Cells | Where-Object { $_.Look -in @('todo', 'stale') }).Count
    $ui.AnaAllNew.Content = $(if ($todo) { "Analyse everything new ($todo)" } else { 'Everything is analysed' }); $ui.AnaAllNew.IsEnabled = [bool]$todo
    # the same five words as the Campaign page (oct. 19 2026)
    $cntS = @{}; foreach ($x in $script:Cells) { $cntS[$x.Status] = 1 + [int]$cntS[$x.Status] }
    $ui.AnaSub.Text = ('{0} captured run(s):  {1} DONE  -  {2} DONE - RECAPTURE ADVISED  -  {3} RECAPTURE REQUIRED  -  {4} REDO  -  {5} IN PROGRESS{6}.  Click a run - its result, every board''s file and the plots show on the right.' -f
        $script:Cells.Count, [int]$cntS['ok'], [int]$cntS['check'], [int]$cntS['required'], [int]$cntS['redo'], [int]$cntS['progress'],
        $(if ([int]$cntS['loading']) { "  -  $([int]$cntS['loading']) CHECKING..." } else { '' }))
}
$ui.AnaFAtk.ItemsSource = @('all attacks', 'baseline', 'blackhole', 'wormhole')
$ui.AnaFTopo.ItemsSource = @('all topologies', 'linear', 'tree', 'star', 'partial_mesh')
$ui.AnaFLoc.ItemsSource = @('all locations', 'G402', 'DLSU_Library', 'Yuchengco', 'home')
$ui.AnaFScn.ItemsSource = @('all scenarios', 'stationary', 'burst', 'highload', 'jitter', 'mobility', 'powercycle')
foreach ($n in 'AnaFAtk', 'AnaFTopo', 'AnaFLoc', 'AnaFScn') { $ui[$n].SelectedIndex = 0; $ui[$n].Add_SelectionChanged({ Update-AnaFilter }) }
function Test-AnaShown($O) {
    foreach ($pair in @(@('AnaFAtk', 'Attack'), @('AnaFTopo', 'Topology'), @('AnaFLoc', 'Location'), @('AnaFScn', 'Scenario'))) {
        if ($ui[$pair[0]].SelectedIndex -gt 0 -and [string]$O.($pair[1]) -ne [string]$ui[$pair[0]].SelectedItem) { return $false }
    }
    if ($ui.AnaFTodo.IsChecked -and $O.Look -notin @('todo', 'stale')) { return $false }
    if ($ui.AnaFBad.IsChecked -and $O.Status -notin @('redo', 'required', 'check')) { return $false }
    $q = ([string]$ui.AnaSearch.Text).Trim().ToLower()
    if (-not $q) { return $true }
    $hay = ('{0} {1} {2}' -f $O.Text, $O.Badge, $O.Sub).ToLower() -replace 'partial_mesh', 'partial_mesh partial mesh'
    foreach ($w in ($q -split '\s+')) { if ($hay -notmatch [regex]::Escape($w)) { return $false } }
    return $true
}
function Update-AnaFilter {
    $ui.AnaSearchHint.Visibility = $(if ($ui.AnaSearch.Text) { 'Collapsed' } else { 'Visible' })
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($ui.CellPick.ItemsSource); if ($view) { $view.Refresh() }
    $shown = @($script:Cells | Where-Object { Test-AnaShown $_ }).Count
    $ui.AnaCount.Text = $(if ($shown -eq @($script:Cells).Count) { "showing all $shown run(s)" } else { "showing $shown of $(@($script:Cells).Count) run(s)" })
}
$ui.AnaFClear.Add_Click({
    foreach ($n in 'AnaFAtk', 'AnaFTopo', 'AnaFLoc', 'AnaFScn') { $ui[$n].SelectedIndex = 0 }
    $ui.AnaSearch.Text = ''; $ui.AnaFAll.IsChecked = $true; Update-AnaFilter
})
$ui.AnaSearch.Add_TextChanged({ Update-AnaFilter })
foreach ($n in 'AnaFAll', 'AnaFTodo', 'AnaFBad') { $ui[$n].Add_Checked({ Update-AnaFilter }) }
function Get-Cell { $ui.CellPick.SelectedItem }
function Select-Cell($C) {
    if (-not $C) { return }
    foreach ($n in 'AnaFAtk', 'AnaFTopo', 'AnaFLoc', 'AnaFScn') { $ui[$n].SelectedIndex = 0 }
    $ui.AnaSearch.Text = ''; $ui.AnaFAll.IsChecked = $true; Update-AnaFilter
    $ui.CellPick.SelectedItem = $C; $ui.CellPick.ScrollIntoView($C)
}
function Set-VerdictBanner([int]$Code, [string]$Line, [switch]$Toast) {
    if ($Code -lt 0) { $ui.Verdict.Visibility = 'Collapsed'; return }
    $lk = switch ($Code) {
        0 { @{ T = 'Attack CONFIRMED'; G = [char]0xE73E; B = 'GradGood' } }
        3 { @{ T = 'Setup invalid - the run cannot be judged'; G = [char]0xE7BA; B = '#B45309' } }
        2 { @{ T = 'Inconclusive'; G = [char]0xE9CE; B = '#B45309' } }
        default { @{ T = 'Attack NOT confirmed'; G = [char]0xE711; B = '#BE123C' } }
    }
    $ui.VerdictTitle.Text = $lk.T
    $ui.VerdictText.Text = (($Line -replace '^\s*(VERDICT|RESULT)\s*:\s*', '').Trim())
    $ui.VerdictIcon.Text = [string]$lk.G
    $ui.Verdict.Background = $(if ($lk.B -like '#*') { & $brush $lk.B } else { $win.FindResource($lk.B) })
    $ui.Verdict.Visibility = 'Visible'
    try { Set-VerdictGradeLook } catch { }     # gui\VerdictDesign.ps1: the grade's words / colour win
    $ui.Verdict.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Fade 0 1 300))
    if ($Toast -and (Get-Cell)) { Show-Toast $lk.T (Get-Cell).Text ([string]$lk.G) $lk.B }
}
function Show-Verdict([string]$Text, [int]$Code) {
    # kept for callers of the old page
    $line = @(($Text -replace "\x1b\[[0-9;]*m", '') -split "`r?`n" | Where-Object { $_ -match '^\s*(VERDICT|RESULT)' } | Select-Object -Last 1)
    Set-VerdictBanner $Code ([string]$line) -Toast
}

# ── the Result tab: the verifier report as cards ─────────────────────────────
function New-AnaCard([string]$Title, [string]$Hex = '') {
    $b = New-Object Windows.Controls.Border; $b.CornerRadius = 14; $b.Padding = '16,12'; $b.Margin = '0,0,0,10'
    $b.Background = Get-Brush $Pal.Card; $b.BorderBrush = Get-Brush $(if ($Hex) { $Hex } else { $Pal.Line }); $b.BorderThickness = 1
    $sp = New-Object Windows.Controls.StackPanel; $b.Child = $sp
    $h = New-Text $Title 11 $Pal.Faint 'SemiBold'; $h.Margin = '0,0,0,8'; [void]$sp.Children.Add($h)
    return @{ Border = $b; Panel = $sp }
}
function New-Pill([string]$T, [string]$Hex, [string]$BgHex) {
    $p = New-Object Windows.Controls.Border; $p.CornerRadius = 7; $p.Padding = '7,1'; $p.Background = Get-Brush $BgHex; $p.VerticalAlignment = 'Center'
    $tb = New-Text $T 10.5 $Hex 'Bold'; $p.Child = $tb; return $p
}
function Get-ResultLook([string]$R) {
    switch -Regex ($R) {
        '^(PASS|OK)'   { @{ Fg = $Pal.Green; Bg = '#1F4D3E'; G = [char]0x2714 }; break }
        '^(FAIL)'      { @{ Fg = $Pal.Red;   Bg = '#3A1E2C'; G = [char]0x2716 }; break }
        '^(WARN|INCON)' { @{ Fg = $Pal.Amber; Bg = '#3A2E14'; G = [char]0x26A0 }; break }
        default        { @{ Fg = $Pal.Dim;   Bg = '#2A2E48'; G = [char]0x2022 } }
    }
}
function Show-AnaReport([string]$Text) {
    $ui.AnaResult.Children.Clear()
    $t = $Text -replace "\x1b\[[0-9;]*m", ''
    if (-not $t.Trim()) { [void]$ui.AnaResult.Children.Add($ui.AnaResultEmpty); return }
    $lines = $t -split "`r?`n"
    # oct. 19 2026: an attack report without the CONFIDENCE grade was made by an older
    # verifier (before oct. 19) - say so on top instead of passing it off as current
    if ($t -match '(?m)^\s*VERDICT\s*:' -and $t -notmatch '(?m)^\s*CONFIDENCE\s*:') {
        $nb = New-Object Windows.Controls.Border; $nb.CornerRadius = 10; $nb.Padding = '12,8'; $nb.Margin = '0,0,0,10'; $nb.Background = Get-Brush '#3A2E14'
        $nt = New-Text ('This report was made by an OLDER version of the verifier (no CONFIDENCE grade, no "why moves were allowed"). ' +
                        'Press Verify to update it - the data is not re-imported, only re-checked.') 12.5 $Pal.Amber 'SemiBold'
        $nt.TextWrapping = 'Wrap'; $nb.Child = $nt; [void]$ui.AnaResult.Children.Add($nb)
    }
    # oct. 20 2026: Campaign status + attack evidence side by side, THIS run's reasons, and a
    # warning when the saved report is older than the analysis (gui\RunStatusCard.ps1)
    try { $rsc = New-RunStatusCard (Get-Cell) $t; if ($rsc) { [void]$ui.AnaResult.Children.Add($rsc) } } catch { }
    $mem = Get-MemberInfo
    # oct. 19 2026: the four validity questions on top + the shared signature card
    $bits = $null; try { $bits = ConvertFrom-ReportText $t } catch { }
    if ($bits -and ($bits.Verdict -or $bits.Sig.Count)) { try { [void]$ui.AnaResult.Children.Add((New-ValidityStrip $bits 4)) } catch { } }
    if ($bits -and $bits.Verdict -and -not $bits.Old) { try { [void]$ui.AnaResult.Children.Add((New-PlainExplain $bits)) } catch { } }
    # gates (analyze.ps1's validation summary)
    $gates = @($lines | Where-Object { $_ -match '^\s*(integrity|topology|attack)\s*:\s*(.+)$' })
    if ($gates.Count) {
        $wp = New-Object Windows.Controls.WrapPanel; $wp.Margin = '0,0,0,10'
        foreach ($g in $gates) {
            [void]($g -match '^\s*(integrity|topology|attack)\s*:\s*(.+)$'); $name = $Matches[1]; $val = $Matches[2].Trim()
            $lk = if ($val -match 'NOT CONFIRMED|FAIL|INVALID') { @{ Fg = $Pal.Red; Bg = '#3A1E2C' } } elseif ($val -match 'WARN|INCON|SKIP') { @{ Fg = $Pal.Amber; Bg = '#3A2E14' } } else { @{ Fg = $Pal.Green; Bg = '#1F4D3E' } }
            $b = New-Object Windows.Controls.Border; $b.CornerRadius = 12; $b.Padding = '14,8'; $b.Margin = '0,0,10,0'; $b.Background = Get-Brush $lk.Bg
            $sp = New-Object Windows.Controls.StackPanel
            [void]$sp.Children.Add((New-Text $name.ToUpper() 10.5 $Pal.Dim 'SemiBold'))
            [void]$sp.Children.Add((New-Text $val 14 $lk.Fg 'Bold'))
            $b.Child = $sp; [void]$wp.Children.Add($b)
        }
        [void]$ui.AnaResult.Children.Add($wp)
    }
    $sec = ''; $feat = @(); $checks = @(); $nodes = @(); $measured = @(); $why = New-Object System.Collections.ArrayList
    $glance = @(); $sketch = New-Object System.Collections.ArrayList; $inSketch = $false
    foreach ($ln in $lines) {
        if ($ln -match '^\s*\[(\d)\]\s') { $sec = $Matches[1]; continue }
        $tr = $ln.Trim()
        if ($sec -eq '1') {
            $parts = @($tr -split '\s{2,}')
            if ($parts.Count -ge 6 -and $parts[0] -match '^(PASS|FAIL|N/A|INCONCL\S*|INFEASIBLE|SKIP|WARN)$') { $feat += , $parts }
        } elseif ($sec -eq '2') {
            if ($tr -match '^-\s+(.+)$') { $measured += $Matches[1] } elseif ($measured.Count -and $ln -match '^\s{6,}\S') { $measured[-1] += ' ' + $tr }
        } elseif ($sec -eq '3') {
            # oct. 19 2026: AT A GLANCE row, the layout drawing, grouped checks
            if ($inSketch) { if (-not $tr) { $inSketch = $false } else { [void]$sketch.Add($(if ($ln.Length -gt 7) { $ln.Substring(7) } else { $tr })) }; continue }
            if ($tr -match '^AT A GLANCE:\s+(.+)$') { $glance = @([regex]::Matches($Matches[1], '([A-Z][A-Z-]+) \[\s*(OK|WARN|FAIL|--)\s*\]') | ForEach-Object { , @($_.Groups[1].Value, $_.Groups[2].Value) }); continue }
            if ($tr -match '^LAYOUT AT THE START') { $inSketch = $true; continue }
            if ($tr -match '^([A-Z][A-Z-]+) \.{3,} (OK|WARN|FAIL|--)$') { $checks += , @('H', $Matches[1], $Matches[2]); continue }
            if ($tr -match '^(OK|WARN|FAIL|SKIP|INFO)\s+(.+)$') { $checks += , @($Matches[1], $Matches[2]) }
            elseif ($checks.Count -and $checks[-1][0] -ne 'H' -and $ln -match '^\s{8,}\S') { $checks[-1][1] += ' ' + $tr }
        } elseif ($sec -eq '4') {
            if ($tr -match '^(NODE_[0-9A-Fa-f]{12})\s+(\S+)\s+(.+?)\s{2,}(\S+)\s+(\S+)\s+(\S+)\s+(\d+)\s*$') { $nodes += , @($Matches[1], $Matches[2], $Matches[3], $Matches[4], $Matches[5], $Matches[6], $Matches[7]) }
        } elseif ($sec -eq '6') {
            # [6] why board moves were allowed (verify_attack.py, oct. 19 2026): one item per
            # paragraph / bullet / source; wrapped lines join the item above
            if (-not $tr -or $tr -match '^-{20,}') { continue }
            if ($tr -match '^(The question|How:|Rules:|Fairness:|This run:|So:|Sources for|- |\[[A-Z]{1,2}\])') { [void]$why.Add($tr) }
            elseif ($why.Count) { $why[$why.Count - 1] = [string]$why[$why.Count - 1] + ' ' + $tr }
        }
    }
    if ($bits -and $bits.Sig.Count) {
        try { [void]$ui.AnaResult.Children.Add((New-SignatureCard $bits)) } catch { }
        if ($measured.Count) {
            $card = New-AnaCard 'MEASURED, NOT SCORED  -  shown for context, never part of the verdict'
            foreach ($m in $measured) { $tb = New-Text ([string][char]0x2022 + ' ' + $m) 11.5 $Pal.Dim; $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,3,0,0'; [void]$card.Panel.Children.Add($tb) }
            [void]$ui.AnaResult.Children.Add($card.Border)
        }
    }
    elseif ($feat.Count) {
        $card = New-AnaCard 'ATTACK SIGNATURE  -  3-sigma test, normal phase vs attack phase'
        $grid = New-Object Windows.Controls.Grid
        # the last column (role) takes whatever width is left, so it is never cut
        foreach ($w in @(64, 220, 140, 80, 70, 0)) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $(if ($w) { New-Object Windows.GridLength $w } else { New-Object Windows.GridLength 1, 'Star' }); [void]$grid.ColumnDefinitions.Add($cd) }
        $r = 0
        $heads = @('result', 'feature', 'normal', 'attack', 'z', 'role')
        $rd = New-Object Windows.Controls.RowDefinition; [void]$grid.RowDefinitions.Add($rd)
        for ($i = 0; $i -lt 6; $i++) { $h = New-Text $heads[$i] 10.5 $Pal.Faint 'SemiBold'; [Windows.Controls.Grid]::SetColumn($h, $i); [void]$grid.Children.Add($h) }
        foreach ($f in $feat) {
            $r++; $rd = New-Object Windows.Controls.RowDefinition; [void]$grid.RowDefinitions.Add($rd)
            $lk = Get-ResultLook $f[0]
            $pill = New-Pill $f[0] $lk.Fg $lk.Bg; $pill.HorizontalAlignment = 'Left'; $pill.Margin = '0,4,0,4'
            $cells = @($pill, (New-Text $f[1] 12.5 $Pal.Text $(if ($f[5] -match 'primary') { 'SemiBold' } else { 'Normal' })), (New-Text $f[2] 12 $Pal.Dim), (New-Text $f[3] 12.5 $lk.Fg 'SemiBold'),
                       (New-Text $f[4] 12 $Pal.Dim), (New-Text ($f[5] -replace ',\s*', ' - ') 11 $(if ($f[5] -match 'primary') { $Pal.Cyan } else { $Pal.Faint })))
            for ($i = 0; $i -lt 6; $i++) { $e = $cells[$i]; if ($i -gt 0) { $e.VerticalAlignment = 'Center' }; [Windows.Controls.Grid]::SetRow($e, $r); [Windows.Controls.Grid]::SetColumn($e, $i); [void]$grid.Children.Add($e) }
        }
        [void]$card.Panel.Children.Add($grid)
        foreach ($m in $measured) { $tb = New-Text ([string][char]0x2022 + ' ' + $m) 11.5 $Pal.Dim; $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,6,0,0'; [void]$card.Panel.Children.Add($tb) }
        [void]$ui.AnaResult.Children.Add($card.Border)
    }
    if ($checks.Count) {
        $bad = @($checks | Where-Object { $_[0] -eq 'FAIL' }).Count
        $card = New-AnaCard ('SETUP CHECKS  -  did the attack run as designed?' + $(if ($bad) { "   ($bad failed)" } else { '' })) $(if ($bad) { $Pal.Red } else { '' })
        if ($glance.Count) {
            # one light per area: where a problem is, before any detail
            $wp = New-Object Windows.Controls.WrapPanel; $wp.Margin = '0,0,0,8'
            foreach ($gl in $glance) {
                $lk = switch ($gl[1]) { 'FAIL' { @{ Fg = $Pal.Red; Bg = '#3A1E2C'; G = [char]0x2716 } } 'WARN' { @{ Fg = $Pal.Amber; Bg = '#3A2E14'; G = [char]0x26A0 } } 'OK' { @{ Fg = $Pal.Green; Bg = '#1F4D3E'; G = [char]0x2714 } } default { @{ Fg = $Pal.Dim; Bg = '#2A2E48'; G = [char]0x2026 } } }
                $pb = New-Object Windows.Controls.Border; $pb.CornerRadius = 10; $pb.Padding = '10,5'; $pb.Margin = '0,0,8,6'; $pb.Background = Get-Brush $lk.Bg
                $pt = New-Text ('{0}  {1}' -f [string]$lk.G, $gl[0]) 12 $lk.Fg 'Bold'; $pb.Child = $pt; [void]$wp.Children.Add($pb)
            }
            [void]$card.Panel.Children.Add($wp)
        }
        if ($sketch.Count) {
            $sh = New-Text 'LAYOUT AT THE START OF THE ATTACK   (who sat under whom;  * = what happened during the attack)' 10.5 $Pal.Faint 'SemiBold'; $sh.Margin = '0,2,0,4'
            [void]$card.Panel.Children.Add($sh)
            $sb = New-Object Windows.Controls.Border; $sb.CornerRadius = 8; $sb.Padding = '12,8'; $sb.Margin = '0,0,0,10'; $sb.Background = Get-Brush $Pal.Bg
            $stb = New-Object Windows.Controls.TextBlock; $stb.FontFamily = 'Cascadia Mono, Consolas'; $stb.FontSize = 12.5
            foreach ($sl in $sketch) {
                $sl = [string]$sl
                $hex = if ($sl -match 'NOT ALLOWED') { $Pal.Red } elseif ($sl -match 'ATTACKER|WORMHOLE') { $Pal.Pink } elseif ($sl -match 'VICTIM') { '#FCA5A5' } elseif ($sl -match 'ROOT') { $Pal.Amber } elseif ($sl -match '^[x?]') { $Pal.Faint } else { $Pal.Cyan }
                $parts = $sl -split '   \* ', 2
                $r1 = New-Object Windows.Documents.Run ($parts[0]); $r1.Foreground = Get-Brush $hex; [void]$stb.Inlines.Add($r1)
                if ($parts.Count -gt 1) { $r2 = New-Object Windows.Documents.Run ('   * ' + $parts[1]); $r2.Foreground = Get-Brush $Pal.Amber; [void]$stb.Inlines.Add($r2) }
                [void]$stb.Inlines.Add((New-Object Windows.Documents.LineBreak))
            }
            $sb.Child = $stb; [void]$card.Panel.Children.Add($sb)
        }
        foreach ($c in $checks) {
            if ($c[0] -eq 'H') {
                $hx = switch ($c[2]) { 'FAIL' { $Pal.Red } 'WARN' { $Pal.Amber } 'OK' { $Pal.Green } default { $Pal.Dim } }
                $hd = New-Text ('{0}   -   {1}' -f $c[1], $c[2]) 11 $hx 'Bold'; $hd.Margin = '0,8,0,2'
                [void]$card.Panel.Children.Add($hd); continue
            }
            $lk = Get-ResultLook $c[0]
            $dp = New-Object Windows.Controls.DockPanel; $dp.Margin = '0,3,0,3'
            $ic = New-Text ([string]$lk.G) 14 $lk.Fg 'Bold'; $ic.Width = 24; [Windows.Controls.DockPanel]::SetDock($ic, 'Left'); [void]$dp.Children.Add($ic)
            $tx = New-Text $c[1] 12.5 $(if ($c[0] -eq 'OK') { $Pal.Text } else { $lk.Fg }); $tx.TextWrapping = 'Wrap'; [void]$dp.Children.Add($tx)
            [void]$card.Panel.Children.Add($dp)
        }
        [void]$ui.AnaResult.Children.Add($card.Border)
    }
    if ($nodes.Count) {
        $card = New-AnaCard 'DELIVERY PER BOARD (PDR)  -  baseline vs attack'
        foreach ($n in $nodes) {
            $mac = $n[0] -replace '^NODE_', ''; $k = $mem[($mac.Substring(0, 2) + ':' + $mac.Substring(10, 2)).ToLower()]
            $vic = $n[2] -match 'VICTIM'
            $g = New-Object Windows.Controls.Grid; $g.Margin = '0,4,0,4'
            foreach ($w in @(190, 130, 60, 1)) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $(if ($w -eq 1) { New-Object Windows.GridLength 1, 'Star' } else { New-Object Windows.GridLength $w }); [void]$g.ColumnDefinitions.Add($cd) }
            $nm = New-Object Windows.Controls.TextBlock; $nm.VerticalAlignment = 'Center'
            $r1 = New-Object Windows.Documents.Run ($mac.Substring(0, 2) + ':' + $mac.Substring(10, 2)); $r1.Foreground = Get-Brush '#93C5FD'; $r1.FontWeight = 'SemiBold'; [void]$nm.Inlines.Add($r1)
            $r2 = New-Object Windows.Documents.Run $(if ($k) { '  ' + $k.Nick } else { '' }); $r2.Foreground = Get-Brush $Pal.Text; [void]$nm.Inlines.Add($r2)
            [Windows.Controls.Grid]::SetColumn($nm, 0); [void]$g.Children.Add($nm)
            $ex = New-Pill ($n[2].Trim()) $(if ($vic) { $Pal.Red } else { $Pal.Dim }) $(if ($vic) { '#3A1E2C' } else { '#2A2E48' }); $ex.HorizontalAlignment = 'Left'
            [Windows.Controls.Grid]::SetColumn($ex, 1); [void]$g.Children.Add($ex)
            $hp = New-Text ('hop ' + $n[3]) 11 $Pal.Faint; $hp.VerticalAlignment = 'Center'; [Windows.Controls.Grid]::SetColumn($hp, 2); [void]$g.Children.Add($hp)
            $bars = New-Object Windows.Controls.StackPanel
            foreach ($pair in @(@('baseline', $n[4], $Pal.Green), @('attack', $n[5], $(if ($vic) { $Pal.Pink } else { $Pal.Cyan })))) {
                $v = 0.0; $ok = [double]::TryParse($pair[1], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$v)
                $row = New-Object Windows.Controls.DockPanel; $row.Margin = '0,1,0,1'
                $lab = New-Text ('{0,-8} {1}' -f $pair[0], $(if ($ok) { '{0:0.00}' -f $v } else { $pair[1] })) 11 $Pal.Dim; $lab.Width = 120; $lab.FontFamily = 'Cascadia Mono, Consolas'
                [Windows.Controls.DockPanel]::SetDock($lab, 'Left'); [void]$row.Children.Add($lab)
                $track = New-Object Windows.Controls.Border; $track.Height = 8; $track.CornerRadius = 4; $track.Background = Get-Brush $Pal.Line; $track.Width = 260; $track.HorizontalAlignment = 'Left'
                $fill = New-Object Windows.Controls.Border; $fill.Height = 8; $fill.CornerRadius = 4; $fill.Background = Get-Brush $pair[2]; $fill.HorizontalAlignment = 'Left'
                $fill.Width = $(if ($ok) { [Math]::Max(0, [Math]::Min(1, $v)) * 260 } else { 0 })
                $track.Child = $fill; [void]$row.Children.Add($track)
                [void]$bars.Children.Add($row)
            }
            [Windows.Controls.Grid]::SetColumn($bars, 3); [void]$g.Children.Add($bars)
            [void]$card.Panel.Children.Add($g)
        }
        [void]$ui.AnaResult.Children.Add($card.Border)
    }
    $vl = @($lines | Where-Object { $_ -match '^\s*VERDICT\s*:' } | Select-Object -Last 1)
    if ($vl) {
        $tb = New-Text ([string]$vl).Trim() 13 $Pal.Text 'Bold'; $tb.TextWrapping = 'Wrap'; $tb.Margin = '4,2,0,8'
        [void]$ui.AnaResult.Children.Add($tb)
    }
    # gui\VerdictDesign.ps1: headline tiles on top + grade / lights inside the banner
    try { Add-ResultHeadline $lines $checks $nodes } catch { }
    try { Set-VerdictExtras $lines } catch { }
    # oct. 19 2026: the CONFIDENCE grade + its reasons, right under the verdict
    $ci = -1; for ($i = $lines.Count - 1; $i -ge 0; $i--) { if ($lines[$i] -match '^\s*CONFIDENCE\s*:') { $ci = $i; break } }
    if ($ci -ge 0) {
        $head = $lines[$ci].Trim() -replace '^CONFIDENCE\s*:\s*', ''
        $grade = if ($head -match '^(STRONG|GOOD|MINOR GAPS|UNDETERMINED|MAJOR GAPS|FAILED|NOT CONFIRMED|SOUND|WITH NOTES|QUALIFIED|-)') { $Matches[1] } else { ($head -split '\s+')[0] }
        $lk = switch ($grade) { 'STRONG' { @{ Fg = $Pal.Green; Bg = '#1F4D3E' } } 'GOOD' { @{ Fg = $Pal.Green; Bg = '#1F4D3E' } } 'MINOR GAPS' { @{ Fg = $Pal.Amber; Bg = '#3A2E14' } } 'MAJOR GAPS' { @{ Fg = $Pal.Orange; Bg = '#35200F' } } 'UNDETERMINED' { @{ Fg = $Pal.Amber; Bg = '#3A2E14' } } { $_ -in 'FAILED', 'NOT CONFIRMED' } { @{ Fg = $Pal.Red; Bg = '#3A1E2C' } } default { @{ Fg = $Pal.Amber; Bg = '#3A2E14' } } }
        $card = New-AnaCard ('CONFIDENCE  -  ' + $head) $lk.Fg
        $items = New-Object System.Collections.ArrayList
        for ($i = $ci + 1; $i -lt $lines.Count; $i++) {
            $t = $lines[$i]
            if ($t -match '^\s*-{20,}' -or -not $t.Trim()) { break }
            if ($t -match '^\s{5}([+~=x])\s(.+)$') { [void]$items.Add(@($Matches[1], $Matches[2])) }
            elseif ($items.Count -and $t -match '^\s{7,}\S') { $items[$items.Count - 1][1] += ' ' + $t.Trim() }
        }
        foreach ($it in $items) {
            $hex = switch ($it[0]) { '+' { $Pal.Green } '~' { Get-IncompleteHex $it[1] } '=' { $Pal.Cyan } default { $Pal.Red } }
            $g = switch ($it[0]) { '+' { [string][char]0x2714 } '~' { Get-IncompleteGlyph $it[1] } '=' { [string][char]0x2192 } default { [string][char]0x2716 } }
            $dp = New-Object Windows.Controls.DockPanel; $dp.Margin = '0,3,0,3'
            $ic = New-Text $g 13 $hex 'Bold'; $ic.Width = 24; [Windows.Controls.DockPanel]::SetDock($ic, 'Left'); [void]$dp.Children.Add($ic)
            $tx = New-Text $it[1] 12.5 $(if ($it[0] -eq '=') { $Pal.Text } else { $hex }) $(if ($it[0] -eq '=') { 'SemiBold' } else { 'Normal' }); $tx.TextWrapping = 'Wrap'; [void]$dp.Children.Add($tx)
            [void]$card.Panel.Children.Add($dp)
        }
        [void]$ui.AnaResult.Children.Add($card.Border)
    }
    if ($why.Count) {
        # below the verdict, like the CLI: why each board move was allowed or not + its sources
        $inv = @($why | Where-Object { $_ -match '^So: .*SETUP INVALID' }).Count
        $card = New-AnaCard 'WHY THE BOARD MOVES WERE ALLOWED - OR NOT   (D-23)' $(if ($inv) { $Pal.Red } else { '' })
        foreach ($w in $why) {
            $w = [string]$w
            if ($w -eq 'This run:') { [void]$card.Panel.Children.Add((New-Text 'THIS RUN' 10.5 $Pal.Faint 'SemiBold')); continue }
            if ($w -eq 'Sources for [6]:') { $h = New-Text 'SOURCES' 10.5 $Pal.Faint 'SemiBold'; $h.Margin = '0,8,0,0'; [void]$card.Panel.Children.Add($h); continue }
            $hex = $Pal.Dim; $size = 12; $weight = 'Normal'; $txt = $w
            if ($w -match '^- (.+)$') {
                $txt = [string][char]0x2022 + ' ' + $Matches[1]
                $hex = if ($w -match 'NOT ALLOWED|NOT confirmed') { $Pal.Red } elseif ($w -match ': ALLOWED|CONFIRMED again') { $Pal.Green } elseif ($w -match 'not possible') { $Pal.Amber } else { $Pal.Text }
                $size = 12.5
            } elseif ($w -match '^So: ') { $hex = $(if ($inv) { $Pal.Red } else { $Pal.Green }); $weight = 'SemiBold'; $size = 12.5 }
            elseif ($w -match '^\[[A-Z]{1,2}\]') { $hex = $Pal.Faint; $size = 11 }
            $tb = New-Text $txt $size $hex $weight; $tb.TextWrapping = 'Wrap'; $tb.Margin = '0,3,0,3'
            [void]$card.Panel.Children.Add($tb)
        }
        [void]$ui.AnaResult.Children.Add($card.Border)
    }
    if ($ui.AnaResult.Children.Count -eq 0) {
        $tb = New-Text 'The report has no attack sections (baseline run, or only a topology check) - see Full report.' 12 $Pal.Dim; $tb.TextWrapping = 'Wrap'
        [void]$ui.AnaResult.Children.Add($tb)
    }
}

# ── the Files tab: one phase timeline per board ──────────────────────────────
$script:PhaseHexes = @{ '255' = '#4B5075'; '254' = '#4B5075'; '0' = $Pal.Green; '1' = $Pal.Pink; '2' = $Pal.Pink; '3' = $Pal.Cyan; '4' = $Pal.Purple }
$script:PhaseNames = @{ '255' = 'stabilise'; '254' = 'prepare'; '0' = 'baseline'; '1' = 'attack'; '2' = 'attack'; '3' = 'cooldown'; '4' = 'terminate' }
function Show-AnaFiles($C) {
    $ui.AnaFiles.Children.Clear()
    if (-not $C -or -not $script:Py) { return }
    $trim = Join-Path $C.ExportDir 'trimmed'
    $hasTrim = (Test-Path $trim) -and @(Get-ChildItem $trim -Filter '*_telem.csv' -ErrorAction SilentlyContinue).Count
    $src = if ($hasTrim -and -not $ui.AnaUseRaw.IsChecked) { $trim } else { $C.ExportDir }
    $ui.AnaFilesNote.Text = $(if ($src -eq $trim) { "TRIMMED data (trimmed\ - what the normal analysis reads). One bar per board: every board should show baseline -> attack -> cooldown." }
                              elseif ($ui.AnaUseRaw.IsChecked) { 'RAW data - the export files exactly as imported (boot / idle sessions included). Switch DATA to trimmed to compare.' }
                              else { 'RAW data - this run has not been trimmed yet (Analyse + verify trims first). One bar per board.' })
    Start-ToolJob -Exe $script:Py -ToolArgs @('tools\phase_summary.py', $src) -State $C -OnDone {
        param($text, $code, $C)
        if (-not (Get-Cell) -or (Get-Cell).Text -ne $C.Text) { return }   # the user picked another run meanwhile
        $ui.AnaFiles.Children.Clear()                                      # a newer load replaces, never stacks
        $line = @($text -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith('[') } | Select-Object -Last 1)
        if (-not $line) { $ui.AnaFilesNote.Text = 'Could not read the files (see the activity pane).'; return }
        $mem = Get-MemberInfo
        foreach ($f in @($line | ConvertFrom-Json | ForEach-Object { $_ })) {
            $mac = ([string]$f.node -replace '^NODE_', '')
            $k = if ($mac.Length -ge 12) { $mem[($mac.Substring(0, 2) + ':' + $mac.Substring(10, 2)).ToLower()] } else { $null }
            $ph = @{}; foreach ($p in $f.phases.PSObject.Properties) { $ph[$p.Name] = [int]$p.Value }
            $isRoot = $f.role -eq 'root'
            $missing = @(); if (-not $ph['0']) { $missing += 'baseline' }; if (-not ($ph['1'] -or $ph['2'])) { if ($C.Attack -ne 'baseline') { $missing += 'attack' } }; if (-not $ph['3']) { $missing += 'cooldown' }
            $card = New-Object Windows.Controls.Border; $card.CornerRadius = 10; $card.Padding = '12,8'; $card.Margin = '0,0,0,6'
            $card.Background = Get-Brush $Pal.Card; $card.BorderBrush = Get-Brush $(if ($missing.Count) { $Pal.Amber } else { $Pal.Line }); $card.BorderThickness = 1
            $g = New-Object Windows.Controls.Grid
            foreach ($w in @(230, 1, 150)) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = $(if ($w -eq 1) { New-Object Windows.GridLength 1, 'Star' } else { New-Object Windows.GridLength $w }); [void]$g.ColumnDefinitions.Add($cd) }
            $left = New-Object Windows.Controls.StackPanel
            $nm = New-Object Windows.Controls.TextBlock
            $r1 = New-Object Windows.Documents.Run $(if ($mac.Length -ge 12) { $mac.Substring(0, 2) + ':' + $mac.Substring(10, 2) } else { $mac }); $r1.Foreground = Get-Brush '#93C5FD'; $r1.FontWeight = 'Bold'; [void]$nm.Inlines.Add($r1)
            $r2 = New-Object Windows.Documents.Run $(if ($k) { '  ' + $k.Nick } else { '' }); $r2.Foreground = Get-Brush $Pal.Text; [void]$nm.Inlines.Add($r2)
            [void]$left.Children.Add($nm)
            $roleHex = switch -Regex ($f.role) { 'root' { $Pal.Amber; break } 'wormhole' { $Pal.Purple; break } 'blackhole|attack' { $Pal.Red; break } default { $Pal.Blue } }
            $rp = New-Pill ([string]$f.role).ToUpper() '#0B1020' $roleHex; $rp.HorizontalAlignment = 'Left'; $rp.Margin = '0,3,0,0'; [void]$left.Children.Add($rp)
            [Windows.Controls.Grid]::SetColumn($left, 0); [void]$g.Children.Add($left)
            # the timeline: segments in the order they happened, width = rows
            $bar = New-Object Windows.Controls.Grid; $bar.Height = 16; $bar.VerticalAlignment = 'Center'; $bar.Margin = '0,0,12,0'
            $i = 0
            foreach ($p in @($f.seq)) {
                $n = [Math]::Max(1, [int]$ph[[string]$p])
                $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = New-Object Windows.GridLength ([double]$n), 'Star'; [void]$bar.ColumnDefinitions.Add($cd)
                $seg = New-Object Windows.Controls.Border; $seg.Background = Get-Brush $(if ($script:PhaseHexes[[string]$p]) { $script:PhaseHexes[[string]$p] } else { $Pal.Faint }); $seg.Margin = '0,0,2,0'; $seg.CornerRadius = 3
                $seg.ToolTip = '{0}: {1:N0} rows (~{2:N0} s at 10 Hz)' -f $(if ($script:PhaseNames[[string]$p]) { $script:PhaseNames[[string]$p] } else { "phase $p" }), $n, ($n / 10)
                [Windows.Controls.Grid]::SetColumn($seg, $i); [void]$bar.Children.Add($seg); $i++
            }
            [Windows.Controls.Grid]::SetColumn($bar, 1); [void]$g.Children.Add($bar)
            $right = New-Object Windows.Controls.StackPanel; $right.VerticalAlignment = 'Center'
            [void]$right.Children.Add((New-Text ('{0:N0} rows  -  {1} s' -f $f.rows, $f.seconds) 11.5 $Pal.Dim))
            $mt = New-Text $(if ($missing.Count) { 'missing: ' + ($missing -join ', ') } else { [string][char]0x2714 + ' full run' }) 11 $(if ($missing.Count) { $Pal.Amber } else { $Pal.Green }) 'SemiBold'
            [void]$right.Children.Add($mt)
            [Windows.Controls.Grid]::SetColumn($right, 2); [void]$g.Children.Add($right)
            $card.Child = $g; $card.ToolTip = $f.file
            [void]$ui.AnaFiles.Children.Add($card)
        }
    }
}

# ── the Plots tab: the EDA pictures ──────────────────────────────────────────
function Show-AnaPlots($C) {
    $ui.AnaPlots.Children.Clear()
    $eda = if ($C) { Join-Path $C.AnaDir 'eda_output' } else { '' }
    $pngs = if ($eda -and (Test-Path $eda)) { @(Get-ChildItem $eda -Filter '*.png' -File) } else { @() }
    if (-not $pngs.Count) { $ui.AnaPlotsNote.Text = 'No plots yet - press Analyse + verify (the EDA step draws them).'; return }
    $order = { param($n) switch -Regex ($n) { '^dimensionality' { 0 } '^timeseries_(baseline|blackhole|wormhole)' { 1 } '^timeseries' { 2 } '^distribution' { 3 } '^correlation_pearson\.png' { 4 } default { 5 } } }
    $ui.AnaPlotsNote.Text = '{0} plot(s) from {1} - click one to open it full size.' -f $pngs.Count, $eda
    foreach ($png in @($pngs | Sort-Object @{ E = { & $order $_.Name } }, Name)) {
        $b = New-Object Windows.Controls.Border; $b.Width = 300; $b.Margin = '0,0,12,12'; $b.CornerRadius = 12; $b.Padding = '8'; $b.Background = Get-Brush $Pal.Card
        $b.BorderBrush = Get-Brush $Pal.Line; $b.BorderThickness = 1; $b.Cursor = 'Hand'; $b.Tag = $png.FullName; $b.ToolTip = $png.Name
        $sp = New-Object Windows.Controls.StackPanel
        try {
            $bi = New-Object Windows.Media.Imaging.BitmapImage
            $bi.BeginInit(); $bi.UriSource = New-Object Uri $png.FullName; $bi.DecodePixelWidth = 560; $bi.CacheOption = 'OnLoad'; $bi.EndInit()
            $img = New-Object Windows.Controls.Image; $img.Source = $bi; $img.Height = 170; $img.Stretch = 'Uniform'
            [void]$sp.Children.Add($img)
        } catch { }
        $cap = New-Text (($png.BaseName -replace '_', ' ') -replace '\s+telem$', '') 11 $Pal.Dim; $cap.TextTrimming = 'CharacterEllipsis'; $cap.Margin = '2,6,0,0'
        [void]$sp.Children.Add($cap)
        $b.Child = $sp
        $b.Add_MouseEnter({ param($x) $x.BorderBrush = Get-Brush $Pal.Accent })
        $b.Add_MouseLeave({ param($x) $x.BorderBrush = Get-Brush $Pal.Line })
        $b.Add_MouseLeftButtonUp({ param($x) Start-Process $x.Tag })
        [void]$ui.AnaPlots.Children.Add($b)
    }
}

# ── selecting a run ──────────────────────────────────────────────────────────
function Show-AnaCell {
    $c = Get-Cell
    if (-not $c) { $ui.AnaTitle.Text = '-'; $ui.AnaInfo.Text = ''; return }
    $ui.AnaTitle.Text = $c.Text
    $v = $script:Verdicts[(Get-AnaKey $c)]
    $ui.AnaInfo.Text = '{0} board file(s)  -  data {1}  -  {2}{3}' -f $c.Boards, (Format-When $c.DataTime),
        $(if ($c.Analysed) { "analysed $(Format-When $c.AnaTime)" } else { 'NOT analysed yet' }),
        $(if ($c.Stale) { '  -  NEW DATA since the analysis: analyse again' } else { '' })
    $ui.DoVerify.IsEnabled = [bool]$c.Analysed
    if ($v) { Set-VerdictBanner ([int]$v.Code) ([string]$v.Line); if ($v.PSObject.Properties['Data'] -and $v.Data) { $ui.VerdictText.Text += "   -   from $($v.Data) data, $($v.When)" } } else { $ui.Verdict.Visibility = 'Collapsed' }
    $rep = Get-AnaReport (Get-AnaKey $c)
    Show-AnaReport $rep
    $ui.VerifyOut.Document.Blocks.Clear(); if ($rep) { Add-Report $rep }
    Show-AnaFiles $c
    Show-AnaPlots $c
}
$ui.CellPick.Add_SelectionChanged({ Show-AnaCell })
foreach ($n in 'AnaUseTrim', 'AnaUseRaw') { $ui[$n].Add_Checked({ if (Get-Cell) { Show-AnaFiles (Get-Cell) } }) }

# ── actions ──────────────────────────────────────────────────────────────────
$ui.DoVerify.Add_Click({
    $c = Get-Cell; if (-not $c -or -not $script:Py) { return }
    if (-not $c.Analysed) { [void][Windows.MessageBox]::Show('This run is not analysed yet - press Analyse + verify.', 'Verify'); return }
    $ui.Verdict.Visibility = 'Collapsed'
    Set-Status 'Running the attack verifier...'
    Start-ToolJob -Exe $script:Py -ToolArgs @('tools\verify_attack.py', $c.Table, '--attack', $(if ($c.Attack -eq 'baseline') { 'none' } else { $c.Attack })) -State (Get-AnaKey $c) -OnDone {
        param($text, $code, $key)
        Save-AnaResult $key $text $code
        Update-Cells                      # first: it re-selects the run and redraws from the cache
        Start-RedoList                    # the Campaign tile's REDO / CHECK follows the new result
        # oct. 20 2026: only onto the run it belongs to - a run picked WHILE the verifier
        # ran used to get this result drawn under its own name (one run's verdict on another)
        $sel = Get-Cell
        if ($sel -and (Get-AnaKey $sel) -eq $key) {
            $ui.VerifyOut.Document.Blocks.Clear(); Add-Report $text
            Show-AnaReport $text
            Show-Verdict $text $code
            $ui.AnaTabs.SelectedIndex = 0
        }
        Set-Status ("Verifier finished (exit {0}: {1})" -f $code, $(switch ($code) { 0 { 'confirmed' } 3 { 'setup invalid' } default { 'not confirmed' } })) $(if ($code -eq 0) { $Pal.Green } else { $Pal.Amber })
    }
})
$ui.DoTopology.Add_Click({
    $c = Get-Cell; if (-not $c -or -not $script:Py) { return }
    $topo = if ($c.Topology -eq 'partial_mesh') { 'partial' } else { $c.Topology }
    $ui.AnaTabs.SelectedIndex = 3
    Add-Report "Rebuilding the topology of $($c.Text) ..."
    Start-ToolJob -Exe $script:Py -ToolArgs @('tools\verify_topology.py', '--topology', $topo, '--attack', $(if ($c.Attack -eq 'baseline') { 'none' } else { $c.Attack }),
        '--location', $c.Location, '--scenario', $c.Scenario, '--structure', '--expect', $topo) -OnDone { param($text, $code) Add-Report $text; Set-Status 'Topology check finished.' }
})
$script:AnaQueue = New-Object System.Collections.Queue
$script:AnaQueueTotal = 0     # set by Analyse everything new - the progress bar shows run k of N
function Start-Analysis([string]$Attack, [string]$Topology, [string]$Location, [string]$Scenario, [string]$Text, [switch]$Raw) {
    # analyze.ps1 -Verify in the activity pane (its own process, so a numpy
    # warning on stderr cannot stop it - MEMORY oct. 7) - no console window
    $key = '{0}/{1}/{2}/{3}' -f $(if ($Attack -in @('none', 'baseline')) { 'baseline' } else { $Attack }), ($Topology -replace '^partial$', 'partial_mesh'), $Location, $Scenario
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $base 'analyze.ps1'),
        '-Attack', $(if ($Attack -in @('none', 'baseline')) { 'baseline' } else { $Attack }), '-Topology', $Topology, '-Location', $Location, '-Scenario', $Scenario, '-Verify')   # analyze.ps1 knows 'baseline', not 'none' (fixed oct. 19 2026)
    if ($Raw) { $a += '-SkipTrim' }   # raw export as imported - no trim_run.py
    $data = if ($Raw) { 'raw (no trim)' } else { 'trimmed' }
    $ok = Start-StreamJob -Exe 'powershell' -ToolArgs $a -Title ("Analyse + verify {0}  [{1} data]" -f $Text, $data) -State @{ Text = $Text; Key = $key; Data = $data } -OnDone {
        param($text, $code, $state)
        Save-AnaResult $state.Key $text -99 $state.Data
        if (-not $script:AnaQueue.Count) { Update-CampaignAfterJob }   # once, after the last queued one
        $v = ($text -split "`r?`n" | Where-Object { $_ -match '^\s*(VERDICT)' } | Select-Object -Last 1)
        Update-Cells
        $c = Get-Cell
        if ($c -and (Get-AnaKey $c) -eq $state.Key) { Show-AnaCell; $ui.AnaTabs.SelectedIndex = 0 }
        if ($script:AnaQueue.Count) { Start-NextAnalysis; return }
        if ($script:SyncResume) { $script:SyncResume = $false; Show-Page 8; Start-SyncCheck -Continue; return }
        Show-Toast 'Analysis finished' $(if ($v) { "$($state.Text)  -  $($v.Trim())" } else { "$($state.Text) (exit $code)" }) ([string][char]0xE9D9) $(if ($code -eq 0) { 'GradGood' } else { 'GradMain' }) { Show-Page 2 } 'Open Verify'
    }
    if ($ok) { Set-Status "Analysing $Text - live output in the activity pane." $Pal.Green }
    return $ok
}
function Start-NextAnalysis {
    if (-not $script:AnaQueue.Count) { return }
    $c = $script:AnaQueue.Dequeue()
    Set-Status ("Analysing {0} ({1} more queued)" -f $c.Text, $script:AnaQueue.Count) $Pal.Cyan
    # the whole queue uses the DATA picked in the popup (Analyse everything new)
    $raw = if ($null -ne $script:AnaQueueRaw) { [bool]$script:AnaQueueRaw } else { [bool]$ui.AnaUseRaw.IsChecked }
    [void](Start-Analysis $(if ($c.Attack -eq 'baseline') { 'none' } else { $c.Attack }) $c.Topology $c.Location $c.Scenario $c.Text -Raw:$raw)
}
$ui.DoAnalyze.Add_Click({
    $c = Get-Cell; if (-not $c) { return }
    $script:AnaQueueTotal = 0
    [void](Start-Analysis $(if ($c.Attack -eq 'baseline') { 'none' } else { $c.Attack }) $c.Topology $c.Location $c.Scenario $c.Text -Raw:([bool]$ui.AnaUseRaw.IsChecked))
})
$ui.AnaAllNew.Add_Click({
    $todo = @($script:Cells | Where-Object { $_.Look -in @('todo', 'stale') })
    if (-not $todo.Count) { return }
    $list = (@($todo | ForEach-Object Text) | Select-Object -First 12) -join "`n    "
    # user, oct. 18 2026: ask which DATA the whole batch uses - trimmed or raw
    $msg = "Analyse + verify {0} run(s), one after the other:`n`n    {1}`n`nWhich data?`n`n    Yes  =  TRIMMED  (recommended: each run is trimmed to the session with the real phase progression first)`n    No   =  RAW  (the export files exactly as imported, boot / idle sessions included)`n    Cancel = do nothing`n`nRaw exports are never changed; each run's analysis tables are rebuilt." -f $todo.Count, $list
    $ans = if ($script:AutoConfirm) { 'Yes' } else { [string][Windows.MessageBox]::Show($msg, 'Analyse everything new - trimmed or raw?', 'YesNoCancel', 'Question') }
    if ($ans -eq 'Cancel') { return }
    $script:AnaQueueRaw = ($ans -eq 'No')
    $ui.AnaUseTrim.IsChecked = -not $script:AnaQueueRaw; $ui.AnaUseRaw.IsChecked = $script:AnaQueueRaw
    $script:AnaQueue.Clear(); foreach ($c in $todo) { $script:AnaQueue.Enqueue($c) }
    $script:AnaQueueTotal = $todo.Count
    Start-NextAnalysis
})
$ui.AnaAllRe.Add_Click({
    # oct. 19 2026 (user): rebuild EVERY run's analysis + verdict - after the analysis code
    # changed, "everything new" finds nothing because the data itself did not change
    $all = @($script:Cells)
    if (-not $all.Count) { return }
    if ($script:AnaQueue.Count) { [void][Windows.MessageBox]::Show('An analysis queue is still running - wait for it to finish.', 'Re-analyse everything', 'OK', 'Information'); return }
    $msg = ("Re-analyse + verify ALL {0} captured run(s), one after the other?`n`nEvery run is trimmed again, its tables and plots are rebuilt and its verdict is checked again. " +
            "This takes a long time (minutes per run). Raw exports are never changed.`n`n    Yes  =  TRIMMED data (recommended)`n    No   =  RAW data`n    Cancel = do nothing") -f $all.Count
    $ans = if ($script:AutoConfirm) { 'Cancel' } else { [string][Windows.MessageBox]::Show($msg, 'Re-analyse everything', 'YesNoCancel', 'Warning') }
    if ($ans -eq 'Cancel') { return }
    $script:AnaQueueRaw = ($ans -eq 'No')
    $ui.AnaUseTrim.IsChecked = -not $script:AnaQueueRaw; $ui.AnaUseRaw.IsChecked = $script:AnaQueueRaw
    $script:AnaQueue.Clear(); foreach ($c in $all) { $script:AnaQueue.Enqueue($c) }
    $script:AnaQueueTotal = $all.Count
    Start-NextAnalysis
})
$ui.AnaRefresh.Add_Click({ Update-Cells; Set-Status 'Run list refreshed.' })
$script:VerQueue = New-Object System.Collections.Queue
function Start-NextVerify {
    if (-not $script:VerQueue.Count) { try { Stop-TaskProgress 0 } catch { }; Update-Cells; Show-AnaCell; $ui.AnaVerifyAll.IsEnabled = $true; Set-Status 'Every analysed run has a verdict now.' $Pal.Green; return }
    $c = $script:VerQueue.Dequeue()
    try {
        if ($script:Prog -and $script:Prog.On -and $script:VerQueueTotal) {
            $k = $script:VerQueueTotal - $script:VerQueue.Count
            $script:Prog.Kind = 'redo'; $script:Prog.Pct = 100.0 * ($k - 1) / $script:VerQueueTotal; $script:Prog.Stage = "run $k of $($script:VerQueueTotal): $($c.Text)"
            Show-TaskProgress
        }
    } catch { }
    Set-Status ("Checking verdicts: {0} ({1} left)" -f $c.Text, $script:VerQueue.Count) $Pal.Cyan
    Start-ToolJob -Exe $script:Py -ToolArgs @('tools\verify_attack.py', $c.Table, '--attack', $(if ($c.Attack -eq 'baseline') { 'none' } else { $c.Attack })) -State (Get-AnaKey $c) -OnDone {
        param($text, $code, $key)
        Save-AnaResult $key $text $code
        Start-NextVerify
    }
}
$ui.AnaVerifyAll.Add_Click({
    if (-not $script:Py) { return }
    $todo = @($script:Cells | Where-Object { $_.Analysed })
    if (-not $todo.Count) { return }
    $script:VerQueue.Clear(); foreach ($c in $todo) { $script:VerQueue.Enqueue($c) }
    $script:VerQueueTotal = $todo.Count
    try { Start-TaskProgress 'Checking verdicts' @() } catch { }
    $ui.AnaVerifyAll.IsEnabled = $false
    Start-NextVerify
})
$ui.DoOpenCell.Add_Click({ $c = Get-Cell; if ($c) { Start-Process explorer $c.Dir } })
Read-Verdicts

# ── CAMPAIGN ──────────────────────────────────────────────────────────────────
# The checklist as ONE heatmap: rows = attack x topology, columns = location x
# scenario, one tile per planned run. Tile colour = the campaign state
# (inventory_cells.py) overlaid with the redo verdict (redo_list.py, run in the
# background at start-up). Click a tile -> its story + one-click actions.
$script:Redo = @{}
function Get-CellKey($Attack, $Topology, $Location, $Scenario) {
    $a = if ($Attack -in @('none', 'benign')) { 'baseline' } else { [string]$Attack }
    ('{0}|{1}|{2}|{3}' -f $a, ($Topology -replace '^partial$', 'partial_mesh'), $Location, $Scenario).ToLower()
}
$script:RedoChecking = New-Object 'System.Collections.Generic.HashSet[string]'    # cell keys being re-checked right now
function Start-RedoList([string[]]$Only = @()) {
    # -Only attack/topology/location/scenario,...: re-check just those runs and
    # merge them in (gui\Stamps.ps1 finds what changed) - seconds, not a minute
    if (-not $script:Py) { return }
    # already checking: run once more when it ends, so it sees the newest result
    if (-not $ui.LoadRedo.IsEnabled) { $script:RedoAgain = $true; return }
    $script:RedoAgain = $false
    $script:RedoCells = Get-CellStamps
    $part = [bool]($Only.Count -and $script:Redo.Count)
    $ui.LoadRedo.IsEnabled = $false
    $ui.LoadRedo.Content = $(if ($part) { "Re-checking $($Only.Count) changed run(s)..." } else { 'Checking every run...' })
    Set-Status $(if ($part) { "Re-checking the $($Only.Count) run(s) whose data changed..." } else { 'Building the redo list - it re-checks every live cell (about a minute)...' }) $Pal.Amber
    $json = [IO.Path]::GetTempFileName()
    $ta = @('tools\redo_list.py', '--json', $json, '--no-color'); if ($part) { $ta += @('--only', ($Only -join ',')) }
    foreach ($o in @($Only)) { $q = $o -split '/'; if ($q.Count -eq 4) { [void]$script:RedoChecking.Add((Get-CellKey $q[0] $q[1] $q[2] $q[3])) } }
    if ($part) { try { Update-CampaignMatrix; Update-Cells } catch { } }    # their tiles turn white "CHECKING..." now
    Start-ToolJob -Exe $script:Py -ToolArgs $ta -State @{ Json = $json; Part = $part; Only = $Only } -OnDone {
        param($text, $code, $st)
        $json = $st.Json
        $ui.LoadRedo.IsEnabled = $true
        $ui.LoadRedo.Content = [string][char]0x21BB + '  Re-check the redo list'
        try { $items = Get-Content $json -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Set-Status 'Could not read the redo list.' $Pal.Red; return }
        Remove-Item $json -ErrorAction SilentlyContinue
        $rank = @{ REDO = 0; CHECK = 1; OK = 2 }
        $script:RedoChecking.Clear()
        if (-not $st.Part) { $script:Redo = @{} }
        else { foreach ($o in @($st.Only)) { $q = $o -split '/'; if ($q.Count -eq 4) { $script:Redo.Remove((Get-CellKey $q[0] $q[1] $q[2] $q[3])) } } }
        foreach ($it in @($items)) { $script:Redo[(Get-CellKey $it.attack $it.topology $it.location $it.scenario)] = $it }
        $items = @($script:Redo.Values)
        $script:RedoOffPlan = @($items | Where-Object { -not $_.planned -and $_.severity -ne 'OK' }).Count
        $rows = @($items | Where-Object { $_.planned } | Sort-Object @{ E = { $rank[[string]$_.severity] } }, location, attack, topology | ForEach-Object {
            $rs = @(@($_.reasons) | Sort-Object { $rank[[string]$_.severity] })
            $top = $rs | Select-Object -First 1
            [pscustomobject]@{ Status = [string]$_.severity; Location = $_.location; Attack = $_.attack; Topology = $_.topology
                               Scenario = $_.scenario; When = $(if ($_.when) { ([datetime]$_.when).ToString('MMM dd  hh:mm tt') } else { '' })
                               Why = $(if ($top) { $top.text } else { 'verified and complete' }); Reasons = $rs } })
        $script:CampaignRows = $rows
        $ui.CampaignGrid.ItemsSource = $rows
        $n = @{}; foreach ($r in $rows) { $n[$r.Status] = 1 + [int]$n[$r.Status] }
        Set-Status ("Redo list: {0} REDO  |  {1} CHECK  |  {2} OK" -f [int]$n.REDO, [int]$n.CHECK, [int]$n.OK) $(if ($n.REDO) { $Pal.Red } else { $Pal.Green })
        if ($n.REDO -and -not $st.Part) { Show-Toast "$([int]$n.REDO) run(s) need a redo" 'They are marked red on the Campaign grid.' ([string][char]0xE72C) '#BE123C' }
        Update-CampaignMatrix; Update-CaptureCampaign
        Set-RedoCheckedTimes @($st.Only) ([bool]$st.Part); Update-CampPanelFresh
        if ($script:RedoAgain) { Start-RedoList }
    }
}
$ui.LoadRedo.Add_Click({ Start-RedoList })
function Update-CampaignAfterJob {
    # user, oct. 17 2026: after Analyse / Verify the Campaign tiles must follow by
    # themselves - inventory_cells.py (analysed or not) + redo_list.py (REDO / CHECK)
    Update-Home; if ($script:RedoCells) { Update-RedoIfChanged } else { Start-RedoList }
    Set-Status 'Updating the Campaign tiles (the redo re-check takes about a minute)...' $Pal.Cyan
}
$ui.CampRefresh.Add_Click({ Update-Home })
$ui.CampPlan.Add_Click({ Show-PlanSettings })

# tile look per state: background, border, glyph, label
$script:TileLook = @{
    # oct. 19 2026 - one colour scheme with the verifier's grade (user's choice):
    #   green  DONE                    STRONG / GOOD (one green only)
    #   yellow DONE - RECAPTURE ADVISED      MINOR GAPS (result not affected), or another CHECK
    #   orange RECAPTURE REQUIRED            MAJOR GAPS (data the result relies on is missing),
    #                                        or another source demands a recapture
    #   red    REDO                    FAILED (attack cannot be confirmed) / setup invalid / a checklist recapture
    ok         = @{ Bg = '#123B33'; Bd = $Pal.Green; G = [char]0xE73E; T = 'DONE' }
    done       = @{ Bg = '#123B33'; Bd = $Pal.Green; G = [char]0xE73E; T = 'DONE' }
    check      = @{ Bg = '#42330F'; Bd = $Pal.Amber; G = [char]0xE7BA; T = 'DONE - RECAPTURE ADVISED / CHECK NOTES' }
    required   = @{ Bg = '#43260F'; Bd = '#FB923C';  G = [char]0xE916; T = 'RECAPTURE REQUIRED' }
    redo       = @{ Bg = '#46182A'; Bd = $Pal.Red;   G = [char]0xE72C; T = 'REDO' }
    # white + sync icon: the run's check has not come back yet (start-up, or a re-check
    # after its files changed) - never shows a colour from stale information
    loading    = @{ Bg = '#2A2E48'; Bd = '#E5E7EB';  G = [char]0xE895; T = 'CHECKING...' }
    analyse = @{ Bg = '#0F3644'; Bd = $Pal.Cyan;  G = [char]0xE9D2; T = 'IN PROGRESS - not analysed yet' }   # captured OK, analysis missing / older than the capture
    partial = @{ Bg = '#43260F'; Bd = '#FB923C';  G = [char]0xE916; T = 'RECAPTURE REQUIRED' }     # the same orange as "required" - one legend entry
    todo    = @{ Bg = '#1B1E33'; Bd = $Pal.Line;  G = '';           T = 'To do' }
}
function Get-RedoKind($R) {
    # red REDO when the VERIFIER rejects the attack; orange RECAPTURE REQUIRED when the attack
    # is confirmed and another source (checklist, completeness, structure, log) asks for it
    $verifierRedo = @($R.reasons | Where-Object { [string]$_.severity -eq 'REDO' -and [string]$_.evidence -eq 'verifier' }).Count
    if ($verifierRedo) { return 'redo' }
    return 'required'
}
function Get-SlotLook($S) {
    # captured OK but not analysed yet: any redo verdict is about the OLDER data
    if ([string]$S.stage -eq 'analyse') { return 'analyse' }
    $ck = Get-CellKey $S.attack $S.topology $S.location $S.scenario
    # checking: the redo check has not come back yet (start-up), or THIS run is being re-checked
    if ($S.state -ne 'todo' -and ((-not $script:Redo.Count -and -not $ui.LoadRedo.IsEnabled) -or $script:RedoChecking.Contains($ck))) { return 'loading' }
    $r = $script:Redo[$ck]
    if ($r -and $S.state -ne 'todo') {
        switch ([string]$r.severity) {
            'REDO' { return (Get-RedoKind $r) }
            'CHECK' { return 'check' }
            'OK' { if ($S.state -eq 'done') { return 'ok' } }
        }
    }
    switch ([string]$S.state) { 'done' { 'done' } 'partial' { 'partial' } default { 'todo' } }
}
function Test-SlotShown($S, [string]$Look) {
    $f = if ($ui.CfTodo.IsChecked) { 'todo' } elseif ($ui.CfRedo.IsChecked) { 'redo' } elseif ($ui.CfDone.IsChecked) { 'done' } else { 'all' }
    switch ($f) {
        'todo' { return $Look -in @('todo', 'partial', 'analyse') }
        'redo' { return $Look -in @('redo', 'required', 'partial', 'check') }
        'done' { return $Look -in @('ok', 'done', 'check') }
    }
    return $true
}
function New-Text([string]$T, [double]$Size = 12, [string]$Hex = $Pal.Text, [string]$Weight = 'Normal') {
    $x = New-Object Windows.Controls.TextBlock; $x.Text = $T; $x.FontSize = $Size; $x.Foreground = & $brush $Hex; $x.FontWeight = $Weight
    $x.VerticalAlignment = 'Center'; return $x
}
$script:ScnShort = @{ stationary = 'STAT'; highload = 'HIGH'; burst = 'BURST'; jitter = 'JITTER'; mobility = 'MOB'; powercycle = 'PWR' }
$script:AtkTone = @{ blackhole = $Pal.Red; wormhole = $Pal.Purple; baseline = $Pal.Green }
$script:CampPulses = New-Object System.Collections.ArrayList
function Update-CampaignMatrix {
    $st = $script:Campaign; if (-not $st) { return }
    # Stop the old 'next' pulse first. A Forever animation keeps running (and
    # keeps its tile alive) after the tile is thrown away - every redraw leaked
    # one, so a GUI left open for hours redrew non-stop and lagged (oct. 18 2026).
    foreach ($x in $script:CampPulses) { $x.BeginAnimation([Windows.UIElement]::OpacityProperty, $null) }
    $script:CampPulses.Clear()
    $g = $ui.CampMatrix
    $g.Children.Clear(); $g.RowDefinitions.Clear(); $g.ColumnDefinitions.Clear()
    $script:CampSelPrev = $script:CampSel
    $script:CampTileMap = @{}      # selection key -> @{ T = tile; Bd; Th } (gui\CampaignVisual.ps1: Set-CampSelection)
    $locSel = @($ui.ClG402, $ui.ClDlsu, $ui.ClYuch | Where-Object IsChecked | ForEach-Object { [string]$_.Tag })
    $locs = @($st.locations | Where-Object { -not $locSel.Count -or $locSel -contains $_ })
    $scns = @($st.scenarios); $topos = @($st.topologies)
    $tileW = if ($locs.Count -eq 1) { 96 } elseif ($locs.Count -eq 2) { 60 } else { 42 }
    # columns: label | (scenario tiles + gap) per location | row tally
    $addCol = { param($w) $c = New-Object Windows.Controls.ColumnDefinition; $c.Width = $w; [void]$g.ColumnDefinitions.Add($c) }
    & $addCol ([Windows.GridLength]::new(112))
    foreach ($l in $locs) { foreach ($s in $scns) { & $addCol ([Windows.GridLength]::new($tileW + 6)) }; & $addCol ([Windows.GridLength]::new(14)) }
    & $addCol ([Windows.GridLength]::new(58))
    $row = 0
    $addRow = { param($h) $r = New-Object Windows.Controls.RowDefinition; $r.Height = $h; [void]$g.RowDefinitions.Add($r) }
    $put = { param($el, $r, $c, $span = 1) [Windows.Controls.Grid]::SetRow($el, $r); [Windows.Controls.Grid]::SetColumn($el, $c); if ($span -gt 1) { [Windows.Controls.Grid]::SetColumnSpan($el, $span) }; [void]$g.Children.Add($el) }
    # header 1: location name + its bar
    & $addRow ([Windows.GridLength]::Auto); & $addRow ([Windows.GridLength]::Auto)
    $c = 1
    foreach ($l in $locs) {
        $tone = if ($script:LocTone[$l]) { $script:LocTone[$l] } else { $Pal.Blue }
        $pl = $st.per_location.$l.all
        $hd = New-Object Windows.Controls.StackPanel; $hd.Margin = '3,0,3,8'
        $dp = New-Object Windows.Controls.DockPanel
        $cnt = New-Text "$($pl.done)/$($pl.planned)" 11 $Pal.Dim; [Windows.Controls.DockPanel]::SetDock($cnt, 'Right')
        [void]$dp.Children.Add($cnt); [void]$dp.Children.Add((New-Text ($l -replace '_', ' ') 13 $tone 'Bold'))
        $bar = New-Object Windows.Controls.ProgressBar; $bar.Height = 5; $bar.Margin = '0,5,0,0'; $bar.Maximum = [math]::Max(1, $pl.planned); $bar.Value = $pl.done
        $bar.Foreground = & $brush $tone
        [void]$hd.Children.Add($dp); [void]$hd.Children.Add($bar)
        & $put $hd 0 $c $scns.Count
        for ($i = 0; $i -lt $scns.Count; $i++) {
            $sh = New-Text $(if ($script:ScnShort[$scns[$i]]) { $script:ScnShort[$scns[$i]] } else { $scns[$i] }) 10 $Pal.Faint 'SemiBold'
            $sh.HorizontalAlignment = 'Center'; $sh.Margin = '0,0,0,6'; $sh.ToolTip = $scns[$i]
            & $put $sh 1 ($c + $i)
        }
        $c += $scns.Count + 1
    }
    $row = 2
    $next = $st.next
    $shownTodo = 0
    foreach ($atk in @('blackhole', 'wormhole', 'baseline')) {
        # attack band
        & $addRow ([Windows.GridLength]::Auto)
        $band = New-Object Windows.Controls.StackPanel; $band.Orientation = 'Horizontal'; $band.Margin = '0,10,0,6'
        $pill = New-Object Windows.Controls.Border; $pill.CornerRadius = 8; $pill.Padding = '10,2'; $pill.Background = & $brush (($script:AtkTone[$atk]) -replace '#', '#33')
        $pill.Child = New-Text $atk.ToUpper() 11 $script:AtkTone[$atk] 'Bold'
        [void]$band.Children.Add($pill)
        & $put $band $row 0 ($g.ColumnDefinitions.Count)
        $row++
        foreach ($topo in $topos) {
            $slots = @($st.slots | Where-Object { $_.topology -eq $topo -and $locs -contains $_.location -and
                (($atk -eq 'baseline' -and $_.kind -eq 'benign') -or ($atk -ne 'baseline' -and $_.kind -ne 'benign' -and $_.attack -eq $atk)) })
            if (-not $slots.Count) { continue }
            & $addRow ([Windows.GridLength]::new(44))
            $lab = New-Text $topo 13 $Pal.Text 'SemiBold'; $lab.Margin = '6,0,0,0'
            & $put $lab $row 0
            $c = 1; $done = 0
            foreach ($l in $locs) {
                for ($i = 0; $i -lt $scns.Count; $i++) {
                    $s = $slots | Where-Object { $_.location -eq $l -and $_.scenario -eq $scns[$i] } | Select-Object -First 1
                    if (-not $s) {
                        $dot = New-Object Windows.Shapes.Ellipse; $dot.Width = 4; $dot.Height = 4; $dot.Fill = & $brush $Pal.Line
                        $dot.HorizontalAlignment = 'Center'; $dot.VerticalAlignment = 'Center'; $dot.ToolTip = 'not planned'
                        & $put $dot $row ($c + $i); continue
                    }
                    $look = Get-SlotLook $s
                    if ($look -in @('ok', 'done', 'check')) { $done++ }
                    $lk = $script:TileLook[$look]
                    $t = New-Object Windows.Controls.Border
                    $t.Width = $tileW; $t.Height = 36; $t.CornerRadius = 9; $t.Cursor = 'Hand'
                    $t.Background = & $brush $lk.Bg; $t.BorderBrush = & $brush $lk.Bd; $t.BorderThickness = 1.5
                    $t.RenderTransformOrigin = '0.5,0.5'; $t.RenderTransform = New-Object Windows.Media.ScaleTransform 1, 1
                    $gl = New-Object Windows.Controls.TextBlock; $gl.Text = [string]$lk.G; $gl.FontFamily = 'Segoe MDL2 Assets'; $gl.FontSize = 14
                    $gl.Foreground = & $brush $lk.Bd; $gl.HorizontalAlignment = 'Center'; $gl.VerticalAlignment = 'Center'
                    $t.Child = $gl
                    $when = if ($s.last) { "  ·  last capture $($s.last)" } else { '' }
                    $t.ToolTip = "$(Get-SlotText $s)`n$($lk.T)$when"
                    $t.Tag = $s
                    if (-not (Test-SlotShown $s $look)) { $t.Opacity = 0.12 } elseif ($look -in @('todo', 'partial', 'analyse')) { $shownTodo++ }
                    # the next capture in run order pulses
                    if ($next -and $s.location -eq $next.location -and $s.topology -eq $next.topology -and $s.scenario -eq $next.scenario -and $s.kind -eq $next.kind -and $s.attack -eq $next.attack) {
                        $t.BorderBrush = $win.FindResource('GradMain'); $t.BorderThickness = 2.5
                        $t.ToolTip = "NEXT IN RUN ORDER`n" + $t.ToolTip
                        $pulse = New-Fade 1 0.45 900; $pulse.AutoReverse = $true; $pulse.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
                        $gl.Text = [string][char]0xE768; $gl.Foreground = & $brush $Pal.Pink
                        $gl.BeginAnimation([Windows.UIElement]::OpacityProperty, $pulse)
                        [void]$script:CampPulses.Add($gl)
                    }
                    $selKey = (Get-CellKey $s.attack $s.topology $s.location $s.scenario) + $s.kind
                    $script:CampTileMap[$selKey] = @{ T = $t; Bd = $t.BorderBrush; Th = $t.BorderThickness }
                    if ($script:CampSel -and $script:CampSel -eq $selKey) {
                        $t.BorderBrush = & $brush '#FFFFFF'; $t.BorderThickness = 2.5
                    }
                    $t.Add_ToolTipOpening({ param($x, $e) try { Set-CampTileTip $x } catch { } })   # grade, read once on hover
                    $t.Add_MouseEnter({ param($x) $x.RenderTransform.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, (New-Fade 1 1.12 120)); $x.RenderTransform.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, (New-Fade 1 1.12 120)) })
                    $t.Add_MouseLeave({ param($x) $x.RenderTransform.BeginAnimation([Windows.Media.ScaleTransform]::ScaleXProperty, (New-Fade 1.12 1 160)); $x.RenderTransform.BeginAnimation([Windows.Media.ScaleTransform]::ScaleYProperty, (New-Fade 1.12 1 160)) })
                    $t.Add_MouseLeftButtonUp({ param($x) Show-CampaignCell $x.Tag })
                    $t.Add_MouseRightButtonUp({ param($x) Start-CellCapture $x.Tag })
                    & $put $t $row ($c + $i)
                }
                $c += $scns.Count + 1
            }
            $tally = New-Text "$done/$($slots.Count)" 12 $(if ($done -eq $slots.Count) { $Pal.Green } else { $Pal.Faint }) 'SemiBold'
            $tally.HorizontalAlignment = 'Right'
            & $put $tally $row ($g.ColumnDefinitions.Count - 1)
            $row++
        }
    }
    # stats chips + legend
    $all = @($st.slots | Where-Object { $locs -contains $_.location })
    $looks = @($all | ForEach-Object { Get-SlotLook $_ })
    $cnt = @{}; foreach ($k in $looks) { $cnt[$k] = 1 + [int]$cnt[$k] }
    $ui.CampStats.Children.Clear()
    try { [void]$ui.CampStats.Children.Add((New-CampRing ([int]$cnt.ok + [int]$cnt.done + [int]$cnt.check) $all.Count)) } catch { }
    foreach ($chip in @(
        @{ T = 'planned'; N = $all.Count; C = $Pal.Text; Tip = 'Every run in the campaign plan (for the locations shown).' },
        @{ T = 'done'; N = ([int]$cnt.ok + [int]$cnt.done + [int]$cnt.check); C = $Pal.Green; Tip = 'Usable: DONE (green) + DONE - RECAPTURE ADVISED (yellow). Recapture required (orange) and REDO (red) are NOT in here.' },
        # user, oct. 17 2026: one number for "how much have we actually captured", good or not
        @{ T = 'captured (incl. redo)'; N = ([int]$cnt.ok + [int]$cnt.done + [int]$cnt.check + [int]$cnt.required + [int]$cnt.partial + [int]$cnt.redo + [int]$cnt.analyse); C = $Pal.Purple; Tip = 'Every run that has data, INCLUDING the ones that must be redone or are not analysed yet = done + redo + in progress. Shows how much capturing has happened; done shows how much of it counts.' },
        @{ T = 'in progress'; N = [int]$cnt.analyse; C = $Pal.Cyan; Tip = 'Captured OK, NOT ANALYSED yet (or the analysis is older than the capture) - click it, press Analyse.' },
        @{ T = 'recapture advised'; N = [int]$cnt.check; C = $Pal.Amber; Tip = 'Yellow - DONE, RECAPTURE ADVISED: the attack is confirmed; some data is missing (MINOR GAPS - e.g. a board cut short or no cooldown) but the impact check proves the result does not need it. Usable with footnotes; a recapture makes it complete. Also counted in done.' },
        @{ T = 'recapture required'; N = ([int]$cnt.required + [int]$cnt.partial); C = '#FB923C'; Tip = 'Orange - RECAPTURE REQUIRED: the attack is confirmed, but the dataset must be captured again (MAJOR GAPS - the result relies on what is missing; or a board missing, a capture cut short, a checklist recapture).' },
        @{ T = 'to do'; N = [int]$cnt.todo; C = $Pal.Dim; Tip = 'Not captured yet.' },
        @{ T = 'redo'; N = [int]$cnt.redo; C = $Pal.Red; Tip = 'Red - REDO: the attack is NOT confirmed or the setup was invalid - everything has to be captured again.' })) {
        $b = New-Object Windows.Controls.Border; $b.CornerRadius = 12; $b.Padding = '14,8'; $b.Margin = '0,0,10,6'; $b.Background = & $brush $Pal.Card
        $b.BorderBrush = & $brush $Pal.Line; $b.BorderThickness = 1; $b.ToolTip = $chip.Tip
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
        [void]$sp.Children.Add((New-Text $(if ($chip.T -like 'captured*') { '{0}/{1}' -f $chip.N, $all.Count } else { [string]$chip.N }) 20 $chip.C 'Bold'))
        $lt = New-Text $chip.T 12 $Pal.Dim; $lt.Margin = '8,4,0,0'; [void]$sp.Children.Add($lt)
        $b.Child = $sp; [void]$ui.CampStats.Children.Add($b)
    }
    $ui.CampSub.Text = ("{0} planned runs · {1} hours of capturing left · click a tile for details, right-click to capture it straight away{2}" -f
        $st.total.planned, [math]::Round($st.hours_left), $(if (-not $script:Redo.Count) { ' · redo check still running...' } elseif ($script:RedoOffPlan) { " · $($script:RedoOffPlan) off-plan run(s) need attention (Table tab)" } else { '' }))
    $ui.CampLegend.Children.Clear()
    foreach ($k in 'ok', 'check', 'required', 'redo', 'analyse', 'loading', 'todo') {
        $lk = $script:TileLook[$k]
        $sw = New-Object Windows.Controls.Border; $sw.Width = 14; $sw.Height = 14; $sw.CornerRadius = 4; $sw.Background = & $brush $lk.Bg; $sw.BorderBrush = & $brush $lk.Bd; $sw.BorderThickness = 1.5
        $sw.Margin = '0,0,6,0'
        $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'; $sp.Margin = '0,0,16,0'
        [void]$sp.Children.Add($sw); [void]$sp.Children.Add((New-Text $lk.T 11 $Pal.Dim))
        [void]$ui.CampLegend.Children.Add($sp)
    }
    $nx = New-Text "$([char]0x25B6) pulsing = next in run order" 11 $Pal.Pink; [void]$ui.CampLegend.Children.Add($nx)
}
foreach ($n in 'CfAll', 'CfTodo', 'CfRedo', 'CfDone', 'ClAll', 'ClG402', 'ClDlsu', 'ClYuch') { $ui[$n].Add_Checked({ Update-CampaignMatrix }) }

function Find-AnalysedCell($S) {
    $a = if ($S.kind -eq 'benign' -or $S.attack -in @('none', 'baseline')) { 'baseline' } else { [string]$S.attack }
    @($script:Cells | Where-Object { $_.Analysed -and $_.Attack -eq $a -and $_.Topology -eq $S.topology -and $_.Location -eq $S.location -and $_.Scenario -eq $S.scenario })[0]
}
function Show-CampaignCell($S) {
    $script:CampSlot = $S
    $script:CampSel = (Get-CellKey $S.attack $S.topology $S.location $S.scenario) + $S.kind
    $look = Get-SlotLook $S
    $lk = $script:TileLook[$look]
    $a = if ($S.kind -eq 'benign') { 'baseline' } else { $S.attack }
    $ui.CampDetTitle.Text = "$a  ·  $($S.topology)"
    $ui.CampDetTitle.Foreground = & $brush $(if ($script:AtkTone[$a]) { $script:AtkTone[$a] } else { $Pal.Text })
    $ui.CampDetPlace.Text = "$($S.location -replace '_', ' ')   ·   $($S.scenario)" + $(if ($S.last) { "`nlast capture $($S.last)" } else { '' })
    $ui.CampDetState.Text = $lk.T; $ui.CampDetState.Foreground = & $brush $lk.Bd
    $ui.CampDetBadge.Background = & $brush $lk.Bg
    $body = $ui.CampDetBody; $body.Children.Clear()
    try { Add-CampVisual $body $S $look } catch { }    # gui\CampaignVisual.ps1: journey, verdict tile, layout
    $r = $script:Redo[(Get-CellKey $S.attack $S.topology $S.location $S.scenario)]
    $sevRank = @{ REDO = 0; CHECK = 1; OK = 2 }
    $reasons = if ($r) { @(@($r.reasons) | Sort-Object { $sevRank[[string]$_.severity] }) } else { @() }
    if ($S.why) { $w = New-Text $S.why 12 $Pal.Dim; $w.TextWrapping = 'Wrap'; $w.Margin = '0,0,0,10'; [void]$body.Children.Add($w) }
    if (-not $reasons.Count -or $look -eq 'analyse') {
        $msg = switch ($look) { 'todo' { 'Not captured yet. Press "Capture this run" - a matching preset is picked for you (or one is made with this cell filled in).' }
                                'partial' { 'Captured, but the capture is not complete - re-capture it.' }
                                'analyse' { 'Captured OK - NOT ANALYSED yet. Press Analyse (it builds the tables), then Verify.' }
                                default { $(if ($script:Redo.Count) { 'Verified and complete - nothing to do.' } else { 'The redo check is still running - its verdict appears here in a moment.' }) } }
        $m = New-Text $msg 12 $Pal.Dim; $m.TextWrapping = 'Wrap'; [void]$body.Children.Add($m)
    }
    foreach ($x in $reasons) {
        $sev = [string]$x.severity
        $tone = switch ($sev) { 'REDO' { $Pal.Red } 'CHECK' { $Pal.Amber } default { $Pal.Green } }
        $card = New-Object Windows.Controls.Border; $card.CornerRadius = 10; $card.Padding = '12,10'; $card.Margin = '0,0,0,8'
        $card.Background = & $brush $Pal.Card2; $card.BorderThickness = '3,0,0,0'; $card.BorderBrush = & $brush $tone
        $sp = New-Object Windows.Controls.StackPanel
        $h = New-Text $sev 10 $tone 'Bold'; [void]$sp.Children.Add($h)
        $t = New-Text ([string]$x.text) 12 $Pal.Text; $t.TextWrapping = 'Wrap'; $t.Margin = '0,3,0,0'; [void]$sp.Children.Add($t)
        if ($x.fix) { $fx = New-Text ("do: " + $x.fix) 12 $Pal.Cyan; $fx.TextWrapping = 'Wrap'; $fx.Margin = '0,5,0,0'; [void]$sp.Children.Add($fx) }
        if ($x.evidence) { $ev = New-Text ("evidence: " + $x.evidence) 11 $Pal.Faint; $ev.TextWrapping = 'Wrap'; $ev.Margin = '0,3,0,0'; [void]$sp.Children.Add($ev) }
        $card.Child = $sp; [void]$body.Children.Add($card)
    }
    Add-NextStepCard $body $a $S.topology $S.location $S.scenario
    Add-CampFreshness $body $S    # gui\CampaignPanel.ps1
    $hasCell = [bool](Find-AnalysedCell $S)
    $ui.CampCapture.IsEnabled = $true
    $ui.CampCapture.Content = $(if ($look -in @('todo', 'partial')) { [string][char]0x25B6 + '  Capture this run' } else { [string][char]0x21BB + '  Capture it again' })
    $ui.CampVerify.IsEnabled = $hasCell
    $ui.CampAnalyse.IsEnabled = $look -ne 'todo'
    $ui.CampOpen.IsEnabled = $look -ne 'todo'
    # oct. 19 2026: a click only moves the white selection border - the old code rebuilt
    # the whole grid (hundreds of tiles) on every click
    if (-not (Set-CampSelection)) { Update-CampaignMatrix }
}
$ui.CampCapture.Add_Click({ if ($script:CampSlot) { Start-CellCapture $script:CampSlot } })
$ui.CampNext.Add_Click({ if ($script:Campaign -and $script:Campaign.next) { $ui.CfAll.IsChecked = $true; $ui.ClAll.IsChecked = $true; Show-CampaignCell $script:Campaign.next } })
$ui.CampVerify.Add_Click({
    $c = Find-AnalysedCell $script:CampSlot; if (-not $c) { return }
    Show-Page 2; Select-Cell $c
    $ui.DoVerify.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
})
$ui.CampAnalyse.Add_Click({
    $s = $script:CampSlot; if (-not $s) { return }
    $a = if ($s.kind -eq 'benign' -or $s.attack -eq 'baseline') { 'none' } else { $s.attack }
    Start-Analysis $a $s.topology $s.location $s.scenario (Get-SlotText $s)
})
$ui.CampOpen.Add_Click({
    $s = $script:CampSlot; if (-not $s) { return }
    $a = if ($s.kind -eq 'benign' -or $s.attack -eq 'none') { 'baseline' } else { $s.attack }
    foreach ($area in 'analysis', 'exports') {
        $d = Join-Path $base ("datasets\{0}\{1}\{2}\{3}\{4}" -f $area, $a, $s.topology, $s.location, $s.scenario)
        if (Test-Path $d) { Start-Process explorer $d; return }
    }
    Set-Status 'No folder for this run on this laptop yet (pull from GitHub on the Data page?).' $Pal.Amber
})

# table view (the old list) - same data, sortable
$ui.PlanFilter.ItemsSource = @('all planned runs', 'not done yet', 'done')
$ui.PlanFilter.SelectedIndex = 1
function Show-Plan {
    if (-not $script:Campaign) { Update-Home; Set-Status 'Loading the campaign first - press Show the checklist again in a moment.'; return }
    $f = [string]$ui.PlanFilter.SelectedItem
    $rows = @($script:Campaign.slots | Where-Object { $f -eq 'all planned runs' -or ($f -eq 'done' -and $_.state -eq 'done') -or ($f -eq 'not done yet' -and $_.state -ne 'done') } |
        ForEach-Object { [pscustomobject]@{ Status = $_.state; Location = $_.location; Attack = $(if ($_.kind -eq 'benign') { 'benign' } else { $_.attack })
                                            Topology = $_.topology; Scenario = $_.scenario; When = $_.last; Why = $_.why; Reasons = @() } })
    $ui.CampaignGrid.ItemsSource = $rows
    Set-Status ("Checklist: {0} run(s) shown" -f $rows.Count)
}
$ui.LoadPlan.Add_Click({ Show-Plan })
$ui.PlanFilter.Add_SelectionChanged({ if ($script:Campaign) { Show-Plan } })
$ui.CampaignGrid.Add_SelectionChanged({
    $r = $ui.CampaignGrid.SelectedItem
    if (-not $r) { return }
    if (-not @($r.Reasons).Count) { $ui.CampaignDetail.Text = "$($r.Attack) / $($r.Topology) / $($r.Location) / $($r.Scenario)`n`n$($r.Why)"; return }
    $txt = "$($r.Status)   $($r.Attack) / $($r.Topology) / $($r.Location) / $($r.Scenario)`n"
    foreach ($x in $r.Reasons) {
        $txt += "`n  [$($x.severity)]  $($x.text)   ($($x.evidence))"
        if ($x.fix) { $txt += "`n           do: $($x.fix)" }
    }
    $ui.CampaignDetail.Text = $txt
})

# ── LIVE OUTPUT ("activity" pane): long commands stream here, one at a time ──
function Get-LineColor([string]$Line) {
    $t = $Line.Trim()
    if ($t -match '^[=\-.]{6,}$') { return $Pal.Faint }
    if ($t -match '^(RESULT|VERDICT)') { if ($t -match 'NOT CONFIRMED') { return $Pal.Red } elseif ($t -match 'INCONCLUSIVE') { return $Pal.Amber } elseif ($t -match 'CONFIRMED') { return $Pal.Green } }
    if ($t -match '^>') { return $Pal.Blue }
    if ($t -match '(?i)\b(error|failed|traceback|not found|could not)\b') { return $Pal.Red }
    if ($t -match '(?i)^(warn|warning)\b|\bwarn:') { return $Pal.Amber }
    if ($t -match '(?i)^(ok|pass|done|saved|deleted|imported|copied|wrote)\b|\bok\b\s*$') { return $Pal.Green }
    return $Pal.Text
}
# ── console colouring (oct. 17 2026): every line split into coloured pieces ──
# Board log lines "I (1234) TAG: message" -> dim prefix, a steady colour per
# tag, the message by level; phase banners bold in their phase colour; MACs,
# COM ports, [CTRL], compile progress, flash %, error / OK words highlighted.
$script:BrushCache = @{}
function Get-Brush([string]$Hex) {
    if (-not $Hex) {
        # to the ERROR stream: a Write-Output here would become part of the returned value
        if ($SelfTest) { [Console]::Error.WriteLine('EMPTY COLOUR from: ' + ((Get-PSCallStack | Select-Object -Skip 1 -First 4 | ForEach-Object { '{0}:{1}' -f $_.Command, $_.ScriptLineNumber }) -join ' <- ')) }
        $Hex = $Pal.Faint
    }
    $b = $script:BrushCache[$Hex]
    if (-not $b) { $b = (New-Object Windows.Media.BrushConverter).ConvertFromString($Hex); $b.Freeze(); $script:BrushCache[$Hex] = $b }
    return $b
}
$script:TagHues = @('#22D3EE', '#C084FC', '#F472B6', '#60A5FA', '#A3E635', '#FBBF24', '#34D399', '#FB923C')
$script:TagHex = @{ ROOT = '#FBBF24'; WORMHOLE = '#C084FC'; BLACKHOLE = '#FB7185'; VICTIM = '#60A5FA'; MESH_SETUP = '#22D3EE'; CSV_LOGGER = '#34D399'; PHASE = '#F472B6' }
function Get-TagHex([string]$Tag) {
    $k = $Tag.Trim().ToUpper(); if ($script:TagHex[$k]) { return $script:TagHex[$k] }
    $h = 0; foreach ($ch in $k.ToCharArray()) { $h = ($h * 31 + [int]$ch) % 9973 }
    $script:TagHex[$k] = $script:TagHues[$h % $script:TagHues.Count]; return $script:TagHex[$k]
}
$script:PhaseHex = [ordered]@{ 'BASELINE' = '#34D399'; 'ATTACK' = '#F472B6'; 'COOLDOWN' = '#22D3EE'; 'TERMINATE' = '#C084FC'; 'READY' = '#A3E635'; 'WAITING' = '#FBBF24'; 'JITTER' = '#FB923C' }
$script:HiRx = [regex]('(?<mac>\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b|\bNODE_[0-9A-Fa-f]{12}\b)|(?<com>\bCOM\d+\b)|(?<ctrl>\[CTRL\])' +
    '|(?<err>(?i:\b(?:error|errors|failed|fail|refused|not found|could not|traceback|exception)\b|!!))' +
    '|(?<warn>(?i:\bwarning\b|\bwarn\b|\bwaiting\b|one-way|no signal))' +
    '|(?<ok>(?i:\u2714|\bbuilt ok\b|\bok\b|\bpass(?:ed)?\b|\bdone\b|\bsafe\b|\bconfirmed\b|\bready\b))' +
    '|(?<pct>\(\s?\d{1,3} ?%\))|(?<hop>\bH[0-9A-F]{1,2}\b)')
function Add-Seg($Para, [string]$Text, [string]$Hex, [switch]$Bold, [string]$Bg) {
    if (-not $Text) { return }
    $r = New-Object Windows.Documents.Run $Text
    $r.Foreground = Get-Brush $Hex
    if ($Bold) { $r.FontWeight = 'SemiBold' }
    if ($Bg) { $r.Background = Get-Brush $Bg }
    [void]$Para.Inlines.Add($r)
}
function Add-Highlighted($Para, [string]$Text, [string]$Base) {
    $at = 0
    foreach ($m in $script:HiRx.Matches($Text)) {
        if ($m.Index -gt $at) { Add-Seg $Para $Text.Substring($at, $m.Index - $at) $Base }
        $v = $m.Value
        if ($m.Groups['mac'].Success)      { Add-Seg $Para $v '#93C5FD' }
        elseif ($m.Groups['com'].Success)  { Add-Seg $Para $v '#22D3EE' -Bold }
        elseif ($m.Groups['ctrl'].Success) { Add-Seg $Para $v '#FBBF24' -Bold }
        elseif ($m.Groups['err'].Success)  { Add-Seg $Para $v '#FB7185' -Bold }
        elseif ($m.Groups['warn'].Success) { Add-Seg $Para $v '#FBBF24' }
        elseif ($m.Groups['ok'].Success)   { Add-Seg $Para $v '#34D399' -Bold }
        elseif ($m.Groups['pct'].Success)  { Add-Seg $Para $v '#22D3EE' -Bold }
        elseif ($m.Groups['hop'].Success)  { Add-Seg $Para $v '#A3E635' }
        else { Add-Seg $Para $v $Base }
        $at = $m.Index + $m.Length
    }
    if ($at -lt $Text.Length) { Add-Seg $Para $Text.Substring($at) $Base }
}
function Add-Banner($Para, [string]$Msg) {
    # "═══ PHASE 0 — BASELINE ═══  @ 10:00:15 PHT" -> bars faint, name bold in its colour
    $m = [regex]::Match($Msg, '^(?<pre>.*?)(?<b1>═{3,})\s*(?<name>.+?)\s*(?<b2>═{3,})(?<post>.*)$')
    if (-not $m.Success) { Add-Highlighted $Para $Msg $Pal.Text; return }
    $hex = '#ECEEFF'; foreach ($k in $script:PhaseHex.Keys) { if ($m.Groups['name'].Value -match $k) { $hex = $script:PhaseHex[$k]; break } }
    Add-Seg $Para $m.Groups['pre'].Value $Pal.Faint
    Add-Seg $Para '━━━ ' $hex
    Add-Seg $Para (' ' + $m.Groups['name'].Value + ' ') '#0B1020' -Bold -Bg $hex
    Add-Seg $Para ' ━━━' $hex
    Add-Seg $Para $m.Groups['post'].Value $Pal.Dim
}
function New-ConsoleParagraph([string]$Line, [string]$Hex) {
    $para = New-Object Windows.Documents.Paragraph; $para.Margin = '0'
    $t = $Line.Trim()
    if ($t -match '^>\s') {
        # a step header written by the GUI itself
        $para.Margin = '0,6,0,2'
        Add-Seg $para ' ▸ ' '#0B1020' -Bold -Bg '#8B5CF6'
        Add-Seg $para (' ' + $t.Substring(1).Trim()) '#C4B5FD' -Bold
        return $para
    }
    if ($Line -match '^\s*you sent:\s*(.+)$') {
        Add-Seg $para '  ➜ you sent  ' $Pal.Faint
        Add-Seg $para (' ' + $Matches[1] + ' ') '#0B1020' -Bold -Bg '#F472B6'
        return $para
    }
    if ($t -match '^[=\-.─━_*]{6,}$') { Add-Seg $para $Line '#3B3F63'; return $para }
    if ($t -match '^(RESULT|VERDICT)') {
        $hx = if ($t -match 'NOT CONFIRMED') { $Pal.Red } elseif ($t -match 'INCONCLUSIVE|INVALID') { $Pal.Amber } elseif ($t -match 'CONFIRMED') { $Pal.Green } else { $Pal.Text }
        Add-Seg $para $Line $hx -Bold; return $para
    }
    if ($Line -match '^\[monitor\]\s*(.*)$') { Add-Seg $para '◉ monitor  ' '#6D7299'; Add-Seg $para $Matches[1] '#8B90B8'; return $para }
    # ESP-IDF log line: "I (1234) TAG: message"
    $m = [regex]::Match($Line, '^(?<lvl>[IWEDV]) \((?<ts>\d+)\) (?<tag>[^:]{1,24}):(?<msg>.*)$')
    if ($m.Success) {
        $lvl = $m.Groups['lvl'].Value
        $lvlHex = switch ($lvl) { 'E' { '#FB7185' } 'W' { '#FBBF24' } 'I' { '#34D399' } default { '#6D7299' } }
        Add-Seg $para $lvl $lvlHex -Bold
        Add-Seg $para (' ({0}) ' -f $m.Groups['ts'].Value) '#4B5075'
        Add-Seg $para $m.Groups['tag'].Value (Get-TagHex $m.Groups['tag'].Value) -Bold
        Add-Seg $para ':' '#4B5075'
        $msg = $m.Groups['msg'].Value
        if ($msg -match '═{3,}') { Add-Banner $para $msg; return $para }
        $base = switch ($lvl) { 'E' { '#FDA4AF' } 'W' { '#FDE68A' } default { '#D6D9F2' } }
        if ($msg.Trim() -match '^[=\-─]{6,}$') { $base = '#3B3F63' }
        Add-Highlighted $para $msg $base
        return $para
    }
    if ($t -match '═{3,}') { Add-Banner $para $Line; return $para }
    # ninja / cmake progress: "[123/1036] Building C object ..."
    $m = [regex]::Match($Line, '^(?<p>\[\d+/\d+\])\s(?<rest>.*)$')
    if ($m.Success) { Add-Seg $para $m.Groups['p'].Value '#22D3EE' -Bold; Add-Seg $para (' ' + $m.Groups['rest'].Value) '#6D7299'; return $para }
    if ($Line -match '^--\s') { Add-Seg $para $Line '#5B6089'; return $para }
    $base = if ($Hex) { $Hex } else { Get-LineColor $Line }
    if ($base -eq $Pal.Text) { $base = '#D6D9F2' }
    Add-Highlighted $para $Line $base
    return $para
}
function Write-Activity([string]$Text, [string]$Hex) {
    foreach ($line in ($Text -replace "\x1b\[[0-9;]*m", '' -split "`r?`n")) {
        # a tool's machine-readable answer (e.g. --list-json) is for the GUI, not for reading
        if ($line.Length -gt 300 -and $line.TrimStart() -match '^[\[{]') { $line = "  (data received: {0:N0} characters - shown in the page above)" -f $line.Length }
        [void]$ui.Activity.Document.Blocks.Add((New-ConsoleParagraph $line $Hex))
    }
    $ui.Activity.ScrollToEnd()
}
$script:Stream = $null
function Read-NewText([string]$Path, [ref]$Pos) {
    try {
        $fs = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
        [void]$fs.Seek($Pos.Value, 'Begin')
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        $t = $sr.ReadToEnd(); $Pos.Value = $fs.Position; $sr.Close()
        return $t
    } catch { return '' }
}
function Start-StreamJob {
    # One task at a time, output streamed into the activity pane as it comes.
    # -NoStop: the task flashes a board or reads one over USB - the Stop button
    # must not cut it (a cut SD read is the CP210x blue-screen trigger)
    param([string]$Exe, [string[]]$ToolArgs, [string]$Title, [scriptblock]$OnDone, $State = $null, [switch]$NoStop)
    if ($script:Stream) { [void][Windows.MessageBox]::Show('Another task is still running - wait for it or press Stop.', 'Busy'); return $false }
    Release-WatchedPorts $ToolArgs    # gui\RunSafety.ps1: a crash watch never blocks a read of the same port
    $out = [IO.Path]::GetTempFileName(); $err = [IO.Path]::GetTempFileName()
    $env:PYTHONIOENCODING = 'utf-8'; $env:PYTHONUNBUFFERED = '1'; $env:NO_COLOR = '1'
    $quoted = @($ToolArgs | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } })
    Write-Activity ''
    Write-Activity ("> {0}   ({1})" -f $Title, (Get-Date).ToString('hh:mm:ss tt')) $Pal.Blue
    try {
        $p = Start-Process -FilePath $Exe -ArgumentList $quoted -WorkingDirectory $base -NoNewWindow -PassThru `
            -RedirectStandardOutput $out -RedirectStandardError $err
    } catch { Write-Activity ("could not start: " + $_.Exception.Message) $Pal.Red; return $false }
    $null = $p.Handle
    $script:Stream = [pscustomobject]@{ Proc = $p; Out = $out; Err = $err; PosO = [long]0; PosE = [long]0
                                        All = (New-Object Text.StringBuilder); Done = $OnDone; State = $State; Title = $Title; NoStop = [bool]$NoStop }
    $ui.StopTask.IsEnabled = $true
    try { Start-TaskProgress $Title $ToolArgs } catch { }   # gui\Progress.ps1
    Update-BusyButtons $true
    $ui.ActivityPane.Visibility = 'Visible'; $ui.ToggleActivity.Content = 'Hide activity'
    Set-Status ("Running: " + $Title) $Pal.Amber
    return $true
}
$streamTimer = New-Object Windows.Threading.DispatcherTimer
$streamTimer.Interval = [TimeSpan]::FromMilliseconds(300)
$streamTimer.Add_Tick({ Measure-GuiTick 'stream' {   # gui\Perf.ps1: a tick over 150 ms is logged
    $s = $script:Stream; if (-not $s) { return }
    $po = $s.PosO; $pe = $s.PosE
    $t = (Read-NewText $s.Out ([ref]$po)) + (Read-NewText $s.Err ([ref]$pe))
    $s.PosO = $po; $s.PosE = $pe
    try { Update-TaskProgress $t } catch { }
    if ($t -and $t.Contains('PROGRESS:')) { $t = (@($t -split "`n" | Where-Object { $_ -notmatch '^\s*PROGRESS:' }) -join "`n") }
    if ($t -and $t.Trim()) { [void]$s.All.Append($t); Write-Activity $t.TrimEnd("`r", "`n") }
    if ($s.Proc.HasExited) {
        Start-Sleep -Milliseconds 100
        $po = $s.PosO; $pe = $s.PosE
        $t = (Read-NewText $s.Out ([ref]$po)) + (Read-NewText $s.Err ([ref]$pe))
        if ($t) { [void]$s.All.Append($t); Write-Activity $t.TrimEnd("`r", "`n") }
        $code = $s.Proc.ExitCode
        $script:Stream = $null
        try { Stop-TaskProgress $code } catch { }
        $ui.StopTask.IsEnabled = $false
        Update-BusyButtons $false
        Remove-Item $s.Out, $s.Err -ErrorAction SilentlyContinue
        Write-Activity ("  finished (exit {0})" -f $code) $(if ($code -eq 0) { $Pal.Green } else { $Pal.Amber })
        Set-Status ("Finished: {0} (exit {1})" -f $s.Title, $code) $(if ($code -eq 0) { $Pal.Green } else { $Pal.Amber })
        if ($s.Done) { try { & $s.Done $s.All.ToString() $code $s.State } catch { Write-Activity ("  {0}   (run_gui.ps1 line {1}: {2})" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.Line.Trim()) $Pal.Red } }
    }
} })
$streamTimer.Start()
$ui.StopTask.Add_Click({
    $s = $script:Stream; if (-not $s) { return }
    if ($s.NoStop) { [void][Windows.MessageBox]::Show("This task is writing to or reading from a board - cutting it can leave the board half-flashed or blue-screen the laptop (CP210x). Let it finish.", 'Not stopping'); return }
    & taskkill.exe /PID $s.Proc.Id /T /F 2>$null | Out-Null
    Write-Activity '  stopped by you' $Pal.Amber
})
$ui.ClearActivity.Add_Click({ $ui.Activity.Document.Blocks.Clear() })
function Get-Py { if ($script:Py) { return $script:Py } [void][Windows.MessageBox]::Show('Python with pandas was not found on this laptop.', 'Python'); return $null }
function Confirm-Action([string]$Text, [string]$Title = 'Please confirm') {
    if ($script:AutoConfirm) { return $true }   # -SelfTest only
    return ([Windows.MessageBox]::Show($Text, $Title, 'YesNo', 'Warning') -eq 'Yes')
}

# ── BOARDS (phase 2) ──────────────────────────────────────────────────────────
$script:PortRows = @()
# The port list is kept by the live board watcher (LIVE BOARDS above); this
# just forces a re-scan now.
function Update-Ports { [void](Update-LivePorts -Force); Set-Status ("{0} COM port(s) seen" -f $script:PortRows.Count) }
function Get-SelectedPort {
    $r = $ui.PortGrid.SelectedItem
    if (-not $r) { [void][Windows.MessageBox]::Show('Select a board (port) in the list first.', 'Boards'); return $null }
    return $r
}
$ui.PortsRefresh.Add_Click({ Update-Ports })
$ui.PortGrid.Add_SelectionChanged({
    $r = $ui.PortGrid.SelectedItem
    $ui.SelBoard.Text = $(if ($r) { "$($r.Port)   ·   $($r.Nick)" } else { 'Select a port on the left' })
    $ui.SelMac.Content = $(if ($r -and $r.Mac) { New-MacChip ([string]$r.Mac) $Pal.Cyan } elseif ($r) { New-CapChip 'MAC not read yet' '#FFFFFF' '#33000000' } else { $null })
})
# Identify: Get-EspMac.ps1 (esptool read_mac) per port, one at a time, through
# the same queue as auto-read on plug-in.
$ui.IdentifyAll.Add_Click({
    if (-not $script:PortRows.Count) { [void][Windows.MessageBox]::Show('No COM ports - plug a board in.', 'Identify'); return }
    if (Confirm-Action ("Identify all {0} board(s)?`n`nEach is first ASKED who it is (GET_ID - no reset). Only a board that does not answer would need a reset, and you are asked again before that happens." -f $script:PortRows.Count)) { Request-MacReadAll }
})
$ui.LocPick.ItemsSource = @('G402', 'DLSU_Library', 'Yuchengco', 'home')   # chosen per board by gui\BoardLocation.ps1
$ui.LocRead.Add_Click({
    $r = Get-SelectedPort; $py = Get-Py; if (-not $r -or -not $py) { return }
    [void](Start-StreamJob -Exe $py -ToolArgs @('tools\export_logs.py', '--port', $r.Port, '--get-location') -Title "Read location on $($r.Port)" -State $r -OnDone { param($t, $c, $s) Complete-LocRead $t $s })
})
$ui.LocWrite.Add_Click({
    $r = Get-SelectedPort; $py = Get-Py; if (-not $r -or -not $py) { return }
    $loc = [string]$ui.LocPick.SelectedItem
    if (-not $loc) { [void][Windows.MessageBox]::Show('Pick the location to write first.', 'Location'); return }
    if ($ui.DryRun.IsChecked) { Write-Activity "DRY RUN - would write location $loc to $($r.Port)." $Pal.Amber; return }
    if (Confirm-Action "Write location '$loc' to the SD card of the board on $($r.Port)?") {
        [void](Start-StreamJob -Exe $py -ToolArgs @('tools\export_logs.py', '--port', $r.Port, '--set-location', $loc) -Title "Set location $loc on $($r.Port)" -State @{ R = $r; Loc = $loc } -OnDone { param($t, $c, $s) Complete-LocWrite $t $c $s })
    }
})
foreach ($pair in @(@('SdAttack', @('blackhole', 'wormhole', 'baseline')), @('SdTopology', @('linear', 'tree', 'star', 'partial_mesh')), @('SdLocation', @('G402', 'DLSU_Library', 'Yuchengco', 'home')))) {
    $ui[$pair[0]].ItemsSource = $pair[1]; $ui[$pair[0]].SelectedIndex = -1   # a permanent delete: pick every part on purpose
}
$ui.SdDelete.Add_Click({
    $r = Get-SelectedPort; $py = Get-Py; if (-not $r -or -not $py) { return }
    if (-not $ui.SdAttack.SelectedItem -or -not $ui.SdTopology.SelectedItem -or -not $ui.SdLocation.SelectedItem) { [void][Windows.MessageBox]::Show('Pick the attack, topology AND location of the folder to delete.', 'Delete SD folder'); return }
    $rel = '{0}/{1}/{2}' -f $ui.SdAttack.SelectedItem, $ui.SdTopology.SelectedItem, $ui.SdLocation.SelectedItem
    if ($ui.DryRun.IsChecked) { Write-Activity "DRY RUN - would delete $rel from the SD card on $($r.Port)." $Pal.Amber; return }
    if (Confirm-Action "PERMANENTLY delete the folder`n`n    $rel`n`nand everything inside it from the SD card of the board on $($r.Port)?" 'Delete SD folder') {
        [void](Start-StreamJob -Exe $py -ToolArgs @('tools\export_logs.py', '--port', $r.Port, '--delete-sd-path', $rel) -Title "Delete SD folder $rel on $($r.Port)")
    }
})
function Get-EsptoolCommand {
    # Same tool the CLI uses: esptool.py from the ESP-IDF environment, else the
    # copy inside IDF_PATH, else 'python -m esptool'.
    $e = Get-Command esptool.py -ErrorAction SilentlyContinue
    if ($e) { return @{ Exe = $e.Source; Pre = @() } }
    if ($env:IDF_PATH) {
        $p = Join-Path $env:IDF_PATH 'components\esptool_py\esptool\esptool.py'
        if (Test-Path $p) { return @{ Exe = 'python'; Pre = @($p) } }
    }
    return @{ Exe = 'python'; Pre = @('-m', 'esptool') }
}
$ui.WipeBoard.Add_Click({
    $r = Get-SelectedPort; if (-not $r) { return }
    if ($ui.DryRun.IsChecked) { Write-Activity "DRY RUN - would erase the flash of $($r.Port)." $Pal.Amber; return }
    $who = if ($r.Mac) { "$($r.Mac)  $($r.Nick)" } else { '(MAC not read - press Identify first to be sure which board this is)' }
    if (Confirm-Action "ERASE the whole flash of the board on $($r.Port)?`n`n    $who`n`nIt ends up blank (no firmware, no saved settings)." 'Wipe board') {
        $t = Get-EsptoolCommand
        [void](Start-StreamJob -Exe $t.Exe -ToolArgs (@($t.Pre) + @('--chip', 'esp32', '--port', $r.Port, 'erase_flash')) -Title "Wipe $($r.Port)")
    }
})
# Every port picker shows WHICH board is on it (MAC + nickname), not just COMx.
function Get-PortItems {
    @($script:Live.Keys | Sort-Object { [int]($_ -replace '\D', '') } | ForEach-Object {
        $L = $script:Live[$_]
        $who = if ($L.Who) { $L.Who } elseif ($L.Mac) { 'unknown board' } else { 'MAC not read yet' }
        [pscustomobject]@{ Port = $_; Mac = [string]$L.Mac; Who = $who
                           Text = ('{0,-6}  {1}   {2}' -f $_, $(if ($L.Mac) { ([string]$L.Mac).ToUpper() } else { '--:--:--:--:--:--' }), $who) } })
}
function Update-PortPick($Combo) {
    $was = if ($Combo.SelectedItem) { $Combo.SelectedItem.Port } else { '' }
    $items = @(Get-PortItems)    # @(): one plugged board must still be a list
    $Combo.ItemsSource = $items
    $hit = @($items | Where-Object Port -eq $was)
    if ($hit.Count) { $Combo.SelectedItem = $hit[0] }
}
foreach ($cb in 'TSelfPort', 'TUartA', 'TUartB', 'SnPort') { $ui[$cb].Add_DropDownOpened({ param($s) Update-PortPick $s }) }
$ui.TSelfLoc.ItemsSource = @('no - read only', 'G402', 'DLSU_Library', 'Yuchengco'); $ui.TSelfLoc.SelectedIndex = 0
function Start-WizardTool([string[]]$ToolArgs, [string]$Title) {
    # run_wizard.ps1 -Tool ... with every answer given: it asks nothing and its
    # output streams into the activity pane (no console window)
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $base 'run_wizard.ps1')) + $ToolArgs + (Get-WizardArgs)
    if (Start-StreamJob -Exe 'powershell' -ToolArgs $a -Title $Title -NoStop) { Set-Status "$Title - live output in the activity pane." $Pal.Green }
}
$ui.TSelfTest.Add_Click({
    $p = $ui.TSelfPort.SelectedItem; if (-not $p) { [void][Windows.MessageBox]::Show('Pick the board first (the list shows each port''s MAC).', 'Self-test'); return }
    if (-not (Confirm-Action ("Flash the plain baseline firmware to`n`n    {0}`n`nand test its SD card + location commands?" -f $p.Text) 'Firmware self-test')) { return }
    $a = @('-Tool', 'selftest', '-ToolPort', $p.Port, '-ToolRole', $(if ($ui.TSelfChild.IsChecked) { 'child' } else { 'root' }))
    if ($ui.TSelfLoc.SelectedIndex -gt 0) { $a += @('-ToolLocation', [string]$ui.TSelfLoc.SelectedItem) }
    Start-WizardTool $a "Firmware self-test on $($p.Port)"
})
$ui.TUartTest.Add_Click({
    $pa = $ui.TUartA.SelectedItem; $pb = $ui.TUartB.SelectedItem
    if (-not $pa -or -not $pb -or $pa.Port -eq $pb.Port) { [void][Windows.MessageBox]::Show('Pick the two tunnel boards - two different ports.', 'UART cable test'); return }
    if (-not (Confirm-Action ("Flash uart_link_test to BOTH tunnel boards and test the cable?`n`n    A: {0}`n    B: {1}" -f $pa.Text, $pb.Text) 'UART cable test')) { return }
    Start-WizardTool @('-Tool', 'uarttest', '-ToolPort', $pa.Port, '-ToolPort2', $pb.Port, '-ToolSecs', $(if ($ui.TUartSoak.IsChecked) { '120' } else { '10' })) "UART cable test ($($pa.Port) <-> $($pb.Port))"
})

# member board list - edited in place, saved in the same shape the CLI reads
$script:MemTable = $null
function Update-Members {
    $dt = New-Object System.Data.DataTable
    foreach ($c in 'Member', 'Nickname', 'Mac', 'Role') { [void]$dt.Columns.Add($c, [string]) }
    $f = Join-Path $base 'member_boards.json'
    if (Test-Path $f) {
        try { foreach ($m in (Get-Content $f -Raw | ConvertFrom-Json).members) { foreach ($b in $m.boards) { [void]$dt.Rows.Add([string]$m.name, [string]$b.nickname, [string]$b.mac, [string]$b.role) } } } catch { }
    }
    $script:MemTable = $dt
    $ui.MemberGrid.Columns.Clear()
    $mk = { param($h, $b, $w) $c = New-Object Windows.Controls.DataGridTextColumn; $c.Header = $h; $c.Binding = New-Object Windows.Data.Binding $b; $c.Width = $w; $c }
    [void]$ui.MemberGrid.Columns.Add((& $mk 'member' 'Member' 110))
    [void]$ui.MemberGrid.Columns.Add((& $mk 'nickname' 'Nickname' 220))
    [void]$ui.MemberGrid.Columns.Add((& $mk 'MAC' 'Mac' 160))
    $rc = New-Object Windows.Controls.DataGridComboBoxColumn; $rc.Header = 'role'; $rc.Width = 140
    $rc.ItemsSource = @('root', 'child', 'attacker'); $rc.SelectedItemBinding = New-Object Windows.Data.Binding 'Role'
    [void]$ui.MemberGrid.Columns.Add($rc)
    $ui.MemberGrid.ItemsSource = $dt.DefaultView
}
$ui.MemAdd.Add_Click({ [void]$script:MemTable.Rows.Add($(if ($ui.MemberGrid.SelectedItem) { $ui.MemberGrid.SelectedItem.Row.Member } else { 'Cal' }), '', '', 'child') })
$ui.MemRemove.Add_Click({ $r = $ui.MemberGrid.SelectedItem; if ($r) { $r.Row.Delete() } })
$ui.MemReload.Add_Click({ Update-Members; Set-Status 'Member list reloaded.' })
$ui.MemSave.Add_Click({
    [void]$ui.MemberGrid.CommitEdit(); [void]$ui.MemberGrid.CommitEdit()
    $f = Join-Path $base 'member_boards.json'
    $help = 'Shown at the top of run_wizard.ps1 and menu.ps1.'
    try { $help = [string](Get-Content $f -Raw | ConvertFrom-Json)._help } catch { }
    $rows = @($script:MemTable.Rows | Where-Object { $_.RowState -ne 'Deleted' -and ([string]$_.Member).Trim() })
    $members = @($rows | Group-Object { ([string]$_.Member).Trim() } | ForEach-Object {
        [ordered]@{ name = $_.Name; boards = @($_.Group | ForEach-Object { [ordered]@{ nickname = ([string]$_.Nickname).Trim(); mac = ([string]$_.Mac).Trim().ToUpper(); role = [string]$_.Role } }) } })
    Copy-Item $f ($f + '.bak') -ErrorAction SilentlyContinue
    ([ordered]@{ _help = $help; members = $members } | ConvertTo-Json -Depth 6) | Set-Content -Path $f -Encoding UTF8
    Set-Status ("Saved member_boards.json ({0} board(s); previous copy kept as .bak)" -f $rows.Count) $Pal.Green
    Update-Ports
})

# ── DATA (phase 3) ────────────────────────────────────────────────────────────
# ── IMPORT / EXPORT (oct. 17 2026 redesign) ──────────────────────────────────
# The CLI's Invoke-ImportSdCard + Import-OneSdCard in one screen: source ->
# run -> list (import_sdcard.py --list-json, the SAME listing the CLI shows,
# incl. its "already imported as ...") -> preview (--dry-run) -> import.
# Boards are picked by MAC + nickname, the naming preset is matched from what
# is on the card, and the list refreshes after an import so every copied file
# flips to ALREADY IMPORTED in front of you.
$ui.ImpScenario.ItemsSource = @('stationary', 'burst', 'highload', 'jitter', 'mobility', 'powercycle'); $ui.ImpScenario.SelectedIndex = 0
# attack / topology / location: the BOARD decided these when it recorded (its
# firmware + location.txt = the card folder) - here they pick the run and CHECK
# every file against it; scenario + repeat are not on the card, so they are set here
$ui.ImpAttack.ItemsSource = @('from card', 'baseline', 'blackhole', 'wormhole'); $ui.ImpAttack.SelectedIndex = 0
$ui.ImpTopology.ItemsSource = @('from card', 'linear', 'tree', 'star', 'partial_mesh'); $ui.ImpTopology.SelectedIndex = 0
$ui.ImpLocation.ItemsSource = @('from card', 'G402', 'DLSU_Library', 'Yuchengco', 'home'); $ui.ImpLocation.SelectedIndex = 0
function Get-ImpPick {
    $a = [string]$ui.ImpAttack.SelectedItem; $t = [string]$ui.ImpTopology.SelectedItem; $l = [string]$ui.ImpLocation.SelectedItem
    if ($a -eq 'from card' -or $t -eq 'from card' -or $l -eq 'from card' -or -not $a) { return $null }
    return ('{0} / {1} / {2}' -f $a, $t, $l)
}
function Set-ImpPick([string]$Attack, [string]$Topology, [string]$Location) {
    if ($Attack -in @('none', '')) { $Attack = 'baseline' }
    $Topology = $Topology -replace '^partial$', 'partial_mesh'
    $ui.ImpAttack.SelectedItem = $Attack; $ui.ImpTopology.SelectedItem = $Topology; $ui.ImpLocation.SelectedItem = $Location
}
function Update-ImpDest {
    Update-ImpDestReal; return    # gui\DataPage.ps1: names where the ticked files REALLY go
    $pk = Get-ImpPick
    $ui.ImpDest.Text = if ($pk) { 'goes to  datasets\exports\{0}\{1}\   (repeat {2})' -f ($pk -replace ' / ', '\'), [string]$ui.ImpScenario.SelectedItem, $ui.ImpRepeat.Text } else { 'pick the run - or press List and it is filled in from the card' }
}
foreach ($cb in 'ImpAttack', 'ImpTopology', 'ImpLocation', 'ImpScenario') {
    $ui[$cb].Add_SelectionChanged({
        Update-ImpDest; Update-ImpPorts
        # re-check the listed files against the new pick (no new read of the card)
        if ($script:ImpItems.Count -and -not $script:ImpFilling) { Show-ImpList $script:ImpItems; $pk = Get-ImpPick; if ($pk) { Update-ImpRosters @($pk -replace ' / ', '/') } }
    })
}
$ui.ImpRepeat.Add_TextChanged({ Update-ImpDest; Update-ImpPorts; if ($script:ImpItems.Count) { Show-ImpList $script:ImpItems } })
$script:ImpTable = $null; $script:ImpItems = @(); $script:ImpRosterWant = ''; $script:ImpLast = $null
$script:ImportIdx = @{}   # export file -> @{ T; When; Mac; Cell; Rep }, re-read only when the file changes
$script:StampMonths = @('jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sept', 'oct', 'nov', 'dec')
function Get-NameStampTime([string]$Name, [datetime]$Fallback) {
    # The import time in the file name (tools\name_stamp.py: oct18_1108PM, or the old
    # 20260918_142233). oct. 19 2026: a GitHub sync / git checkout rewrites every
    # file's modified time, so "last imported" by modified time picked the wrong run
    # (DLSU files synced at the same second as the G402 ones). The year comes from
    # the modified time - the name has none - stepped back if that lands in the future.
    $m = [regex]::Match($Name, '_(\d{8})_(\d{6})_')
    if ($m.Success) { try { return [datetime]::ParseExact($m.Groups[1].Value + $m.Groups[2].Value, 'yyyyMMddHHmmss', $null) } catch { } }
    $m = [regex]::Match($Name, '_(jan|feb|mar|apr|may|jun|jul|aug|sept|oct|nov|dec)(\d{2})_(\d{2})(\d{2})([AP]M)(?:-\d+)?_')
    if ($m.Success) {
        try {
            $h = [int]$m.Groups[3].Value % 12 + $(if ($m.Groups[5].Value -eq 'PM') { 12 } else { 0 })
            $t = New-Object DateTime $Fallback.Year, ([array]::IndexOf($script:StampMonths, $m.Groups[1].Value) + 1), ([int]$m.Groups[2].Value), $h, ([int]$m.Groups[4].Value), 0
            if ($t -gt $Fallback.AddDays(1)) { $t = $t.AddYears(-1) }
            return $t
        } catch { }
    }
    return $Fallback
}
function Get-LastImports {
    # MAC -> its NEWEST telemetry file in datasets\exports: when it landed there
    # and which run (attack / topology / location / scenario, repeat). The MAC
    # comes from the file's own rows (node_id = NODE_<MAC>), not its name.
    $root = Join-Path $base 'datasets\exports'
    $out = @{}
    if (-not (Test-Path $root)) { return $out }
    foreach ($f in [IO.Directory]::EnumerateFiles($root, '*_telem.csv', 'AllDirectories')) {
        if ($f -match '\\(trimmed|_archive)\\') { continue }
        $t = [IO.File]::GetLastWriteTime($f)
        $c = $script:ImportIdx[$f]
        if (-not $c -or $c.T -ne $t.Ticks) {
            $mac = ''
            try {
                $sr = New-Object IO.StreamReader($f); [void]$sr.ReadLine(); $row = $sr.ReadLine(); $sr.Close()
                $m = [regex]::Match([string]$row, 'NODE_([0-9A-Fa-f]{12})')
                if ($m.Success) { $x = $m.Groups[1].Value.ToLower(); $mac = (0..5 | ForEach-Object { $x.Substring($_ * 2, 2) }) -join ':' }
            } catch { }
            $parts = $f.Substring($root.Length).TrimStart('\') -split '\\'
            $cell = if ($parts.Count -ge 5) { $parts[0..3] -join ' / ' } else { $parts[0..($parts.Count - 2)] -join ' / ' }
            $rep = if ([IO.Path]::GetFileName($f) -match '_r(\d+)_') { [int]$Matches[1] } else { 0 }
            $c = @{ T = $t.Ticks; When = (Get-NameStampTime ([IO.Path]::GetFileName($f)) $t); Mac = $mac; Cell = $cell; Rep = $rep }
            $script:ImportIdx[$f] = $c
        }
        if ($c.Mac -and (-not $out[$c.Mac] -or $out[$c.Mac].When -lt $c.When)) { $out[$c.Mac] = $c }
    }
    return $out
}
function Get-AtkHex([string]$A) {
    switch -Regex ($A) { 'blackhole' { $Pal.Red; break } 'wormhole' { $Pal.Purple; break } 'baseline|none' { $Pal.Green; break } default { $Pal.Text } }
}
function Format-When([datetime]$T) {
    $d = ((Get-Date).Date - $T.Date).Days
    $day = if ($d -eq 0) { 'today' } elseif ($d -eq 1) { 'yesterday' } else { $T.ToString('MMM d').ToLower() }
    return '{0} {1}' -f $day, $T.ToString('h:mm tt').ToLower()
}
function Update-ImpPorts {
    # only real ESP32 USB bridges - a reset on anything else can harm it
    $was = if ($ui.CardPortPick.SelectedItem) { $ui.CardPortPick.SelectedItem.Port } else { '' }
    $last = Get-LastImports
    $pick = Get-ImpPick; $scn = [string]$ui.ImpScenario.SelectedItem
    $rep = 1; [void][int]::TryParse($ui.ImpRepeat.Text, [ref]$rep)
    $items = @(Get-PortItems | Where-Object { $script:Live[$_.Port].Kind -ne 'BLOCKED' } | ForEach-Object {
        $li = if ($_.Mac) { $last[$_.Mac.ToLower()] } else { $null }
        # every piece its own colour: mark, words, WHEN, attack, the rest, repeat
        $v = [ordered]@{ MacTxt = $(if ($_.Mac) { $_.Mac.ToUpper() } else { '--:--:--:--:--:--' }); Icon = ''; IconFg = $Pal.Faint; Lead = ''; LeadFg = $Pal.Dim
                         When = ''; WhenFg = $Pal.Cyan; Arrow = ''; Atk = ''; AtkFg = $Pal.Text; Rest = ''; Rep = '' }
        if (-not $_.Mac) { $v.Icon = [string][char]0x25CB; $v.Lead = 'MAC not read yet - its imports show once it is identified'; $v.LeadFg = $Pal.Faint }
        elseif (-not $li) { $v.Icon = [string][char]0x25CB; $v.IconFg = $Pal.Amber; $v.Lead = 'never imported from this board'; $v.LeadFg = $Pal.Amber }
        else {
            $done = $pick -and $li.Cell -eq "$pick / $scn" -and $li.Rep -eq $rep
            $v.Icon = $(if ($done) { [string][char]0x2714 } else { [string][char]0x25CF })
            $v.IconFg = $(if ($done) { $Pal.Green } else { $Pal.Blue })
            $v.Lead = $(if ($done) { 'done for this run - imported ' } else { 'last imported ' })
            $v.LeadFg = $(if ($done) { $Pal.Green } else { $Pal.Dim })
            $v.When = Format-When $li.When
            $age = ((Get-Date).Date - $li.When.Date).Days
            $v.WhenFg = $(if ($age -eq 0) { $Pal.Cyan } elseif ($age -eq 1) { $Pal.Blue } else { $Pal.Faint })
            $cp = $li.Cell -split ' / '
            $v.Arrow = '   ->   '; $v.Atk = $cp[0]; $v.AtkFg = Get-AtkHex $cp[0]
            $v.Rest = $(if ($cp.Count -gt 1) { ' / ' + (($cp[1..($cp.Count - 1)]) -join ' / ') } else { '' })
            $v.Rep = '   r{0}' -f $li.Rep
        }
        foreach ($k in @($v.Keys)) { if ($k -like '*Fg') { $v[$k] = Get-Brush $v[$k] } }
        $o = $_; foreach ($k in $v.Keys) { $o | Add-Member -NotePropertyName $k -NotePropertyValue $v[$k] -Force }; $o })
    $ui.CardPortPick.ItemsSource = $items
    $hit = @($items | Where-Object Port -eq $was)
    if ($hit.Count) { $ui.CardPortPick.SelectedItem = $hit[0] }
}
function Update-Cards {
    $was = if ($ui.CardPick.SelectedItem) { $ui.CardPick.SelectedItem.Root } else { '' }
    $rem = @(Get-RemovableDrives | ForEach-Object { $_ + '\' })
    $items = @(Get-SdCardCandidates | Where-Object { -not $_.IsRepoDrive -and ($_.LooksLikeCard -or $rem -contains $_.Root) } |
        Sort-Object @{ E = { -not $_.LooksLikeCard } }, Root | ForEach-Object {
            $lbl = ''; try { $lbl = (New-Object IO.DriveInfo $_.Root).VolumeLabel } catch { }
            [pscustomobject]@{ Root = $_.Root; Looks = $_.LooksLikeCard
                               Text = ('{0}  {1}   {2}' -f $_.Root, $lbl, $(if ($_.LooksLikeCard) { '- has capture folders, looks like ours' } else { '- no capture folders on it' })) } })
    $ui.CardPick.ItemsSource = $items
    $hit = @($items | Where-Object Root -eq $was)
    if ($hit.Count) { $ui.CardPick.SelectedItem = $hit[0] } elseif ($items.Count) { $ui.CardPick.SelectedIndex = 0 }
}
function Get-ImportSource {
    if ($ui.SrcCard.IsChecked) {
        $d = $ui.CardPick.SelectedItem
        if (-not $d) { Update-Cards; $d = $ui.CardPick.SelectedItem }
        if (-not $d) { [void][Windows.MessageBox]::Show('No SD card drive found - insert the card (or plug in its reader), then press Rescan.', 'Import'); return $null }
        return @('--card', $d.Root)
    }
    $p = $ui.CardPortPick.SelectedItem
    if (-not $p) { [void][Windows.MessageBox]::Show('Pick the board that holds the card - the list shows each port''s MAC and nickname.', 'Import'); return $null }
    return @('--port', $p.Port)
}
$ui.SrcPort.Add_Checked({ $ui.ImpPortPane.Visibility = 'Visible'; $ui.ImpCardPane.Visibility = 'Collapsed'; $ui.ImpDelete.IsChecked = $false; $ui.ImpDelete.IsEnabled = $false; $ui.ImpDelete.ToolTip = 'Over USB the card is never emptied by an import (the CLI does the same).' })
$ui.SrcCard.Add_Checked({ $ui.ImpPortPane.Visibility = 'Collapsed'; $ui.ImpCardPane.Visibility = 'Visible'; $ui.ImpDelete.IsEnabled = $true; $ui.ImpDelete.IsChecked = $true; $ui.ImpDelete.ToolTip = 'Same as the CLI: a file is removed from the card only after its copy is verified.'; Update-Cards })
$ui.ImpDelete.IsEnabled = $false
$script:ImpFilling = $false
Update-ImpDest
$ui.ImpRescan.Add_Click({ Update-Cards; Set-Status ("{0} drive(s) found" -f @($ui.CardPick.ItemsSource).Count) })
$ui.CardPortPick.Add_DropDownOpened({ Update-ImpPorts })
$ui.ImpRepMinus.Add_Click({ $n = 1; [void][int]::TryParse($ui.ImpRepeat.Text, [ref]$n); $ui.ImpRepeat.Text = [string][Math]::Max(1, $n - 1) })
$ui.ImpRepPlus.Add_Click({ $n = 1; [void][int]::TryParse($ui.ImpRepeat.Text, [ref]$n); $ui.ImpRepeat.Text = [string]($n + 1) })

function Update-ImpRosters([string[]]$Cells) {
    # presets whose attack / topology / location / scenario match a run on the
    # card (the CLI's "Naming from preset ...") - yours first, then newest
    $scn = [string]$ui.ImpScenario.SelectedItem
    if (-not $script:Presets) { Update-Presets }
    $norm = { param($a, $t, $l) ('{0}/{1}/{2}' -f $(if ($a -in @('none', 'baseline')) { 'baseline' } else { $a }), ($t -replace '^partial$', 'partial_mesh'), $l).ToLower() }
    $want = @($Cells | ForEach-Object { $_.ToLower() })
    $hits = @($script:Presets | Where-Object { $want -contains (& $norm $_.Attack $_.Topology $_.Location) -and $_.Scenario -eq $scn } |
        Sort-Object @{ E = { $_.Owner -ne $script:Me } }, @{ E = { $_.Saved }; Descending = $true })
    $items = @([pscustomobject]@{ Path = ''; Text = 'none - keep the card''s own names (victim_NODE_<MAC>)' }) +
             @($hits | ForEach-Object { [pscustomobject]@{ Path = $_.Path; Text = ('{0}  [{1}]{2}' -f $_.File, $_.Owner, $(if ($_.Owner -eq $script:Me) { '  - yours' } else { '' })) } })
    $ui.ImpRoster.ItemsSource = $items
    $pick = if ($script:ImpRosterWant) { @($items | Where-Object Path -eq $script:ImpRosterWant) } else { @() }
    $ui.ImpRoster.SelectedItem = $(if ($pick.Count) { $pick[0] } elseif ($items.Count -gt 1) { $items[1] } else { $items[0] })
}
$ui.ImpRoster.Add_SelectionChanged({ if ($ui.ImpRoster.SelectedItem -and $ui.ImpRoster.IsDropDownOpen) { $script:ImpRosterWant = $ui.ImpRoster.SelectedItem.Path } })
$ui.ImpRoster.Add_DropDownClosed({ if ($ui.ImpRoster.SelectedItem) { $script:ImpRosterWant = $ui.ImpRoster.SelectedItem.Path } })

function Get-ImpArgs([switch]$List) {
    $src = Get-ImportSource; if (-not $src) { return $null }
    $rep = 1; [void][int]::TryParse($ui.ImpRepeat.Text, [ref]$rep); if ($rep -lt 1) { $rep = 1 }
    $a = @('tools\import_sdcard.py') + $src + @('--repeat', "$rep", '--scenario', [string]$ui.ImpScenario.SelectedItem)
    $r = if ($ui.ImpRoster.SelectedItem) { $ui.ImpRoster.SelectedItem.Path } else { $script:ImpRosterWant }
    if ($r) { $a += @('--roster', $r) }
    if ($List) { $a += '--list-json' }
    return $a
}
# One meaning per colour (user, oct. 17 2026: a red 'other piece' read as an error):
#   green = ready, import it   blue = information only, nothing wrong
#   grey  = already done       amber = look before importing   red = no usable data
$script:ImpLook = @{
    new     = @{ Bg = '#1F4D3E'; Fg = $Pal.Green;  Text = 'NEW' }
    other   = @{ Bg = '#1E2A44'; Fg = $Pal.Blue;   Text = 'OTHER RUN' }
    piece   = @{ Bg = '#1E2A44'; Fg = $Pal.Blue;   Text = 'EXTRA PIECE' }
    already = @{ Bg = '#2A2E48'; Fg = $Pal.Dim;    Text = 'ALREADY IMPORTED' }
    samerep = @{ Bg = '#3A2E14'; Fg = $Pal.Amber;  Text = 'SAME REPEAT EXISTS' }
    live    = @{ Bg = '#3A2E14'; Fg = $Pal.Amber;  Text = 'STILL RUNNING' }
    aborted = @{ Bg = '#3A2E14'; Fg = $Pal.Amber;  Text = 'ABORTED' }
    nodata  = @{ Bg = '#3A1E2C'; Fg = $Pal.Red;    Text = 'NO DATA' }
    empty   = @{ Bg = '#3A1E2C'; Fg = $Pal.Red;    Text = 'EMPTY' }
}
# why an ABORTED file ended = the reset reason of the NEXT boot on that card
# (import_sdcard.py 'ended_by'; None on firmware before sep. 25 2026)
function Get-EndedShort([string]$R) {
    switch -Regex ($R) { 'POWERON' { 'power cut'; break } 'BROWNOUT' { 'brownout'; break } 'PANIC' { 'crash'; break } 'WDT' { 'watchdog'; break }
                         'SW' { 'restart'; break } 'EXT' { 'reset pin'; break } default { $R } }
}
function Get-EndedText([string]$R) {
    if (-not $R) { return 'the card does not say why (no later boot logged, or older firmware). Usually it was unplugged / its power cut before TERMINATE closed the file.' }
    switch -Regex ($R) {
        'POWERON'  { "ended by POWERON = the power was cut (unplugged from its powerbank / cable), or an EN reset (esptool). It was cut BEFORE TERMINATE closed the file. The rows up to that moment are on the card - tick 'show aborted' to import them."; break }
        'BROWNOUT' { 'ended by BROWNOUT = the supply voltage dropped (weak powerbank, long/thin cable) - the board reset by itself.'; break }
        'PANIC'    { 'ended by PANIC = the firmware crashed.'; break }
        'WDT'      { "ended by a watchdog ($R) = the firmware hung."; break }
        default    { "ended by $R." }
    }
}
# "Already imported?" by CONTENT, not by name (oct. 17 2026). import_sdcard.py
# matches an existing export by its file NAME, and the name depends on the
# naming preset (child_node3_... with one, victim_NODE-<MAC>_... without), so
# a board imported once without a preset listed as NEW again with one. The GUI
# therefore scans ALL of datasets\exports itself (trimmed\ and _archive\ skipped)
# and compares content: same board MAC (read from the file's own rows), same
# kind (telem / arrivals) and the same row count - or, over USB where the row
# count is unknown, about the same size. A match in the folder this import goes
# to must also have the same repeat; a match in ANY other folder is reported
# with its folder (picked the wrong run? it was filed somewhere else already).
# Cached per file by write time, so only new / changed files are re-read.
$script:ExpIdx = @{}
function Get-ExportIndex {
    $root = Join-Path $base 'datasets\exports'
    $out = New-Object System.Collections.ArrayList
    if (-not (Test-Path $root)) { return $out }
    foreach ($path in [IO.Directory]::EnumerateFiles($root, '*.csv', 'AllDirectories')) {
        if ($path -match '\\(trimmed|_archive)\\') { continue }
        $name = [IO.Path]::GetFileName($path)
        $kind = if ($name -like '*_telem.csv') { 'telem' } elseif ($name -like '*_arrivals.csv') { 'arrivals' } else { continue }
        $t = [IO.File]::GetLastWriteTime($path)
        $c = $script:ExpIdx[$path]
        if (-not $c -or $c.T -ne $t.Ticks) {
            $mac = ''; $rows = 0
            try {
                $sr = New-Object IO.StreamReader($path)
                [void]$sr.ReadLine(); $first = $sr.ReadLine()
                if ($first) { $rows = 1; while ($null -ne $sr.ReadLine()) { $rows++ } }
                $sr.Close()
                $m = [regex]::Match([string]$first, 'NODE_([0-9A-Fa-f]{12})'); if ($m.Success) { $mac = $m.Groups[1].Value.ToLower() }
            } catch { }
            $c = @{ T = $t.Ticks; Name = $name; Dir = [IO.Path]::GetDirectoryName($path); Cell = ([IO.Path]::GetDirectoryName($path).Substring($root.Length).TrimStart('\') -replace '\\', ' / ')
                    Mac = $mac; Kind = $kind; Rows = $rows; Size = (New-Object IO.FileInfo $path).Length; When = $t
                    Rep = $(if ($name -match '_r(\d+)_') { [int]$Matches[1] } else { 0 }) }
            $script:ExpIdx[$path] = $c
        }
        [void]$out.Add($c)
    }
    return $out
}
function Test-SameContent($E, $F) {
    # $true same rows/size, $false different, $null = cannot tell (nothing known about the card file)
    if ($null -ne $F.rows) { return ([Math]::Abs([int]$E.Rows - [int]$F.rows) -le 2) }
    if ($null -ne $F.bytes -and [long]$F.bytes -gt 0) { return ([Math]::Abs([double]$E.Size - [double]$F.bytes) -le 0.03 * [double]$F.bytes) }
    return $null
}
function Find-ImportedCopy($F, [string]$Scenario, [int]$Repeat, $Index) {
    # @{ Name; Sure; Cell; Here } when this card file is already in exports, else $null
    $dir = Join-Path $base ("datasets\exports\{0}\{1}\{2}\{3}" -f $F.filed_under, $F.topology, $F.location, $Scenario)
    $mac = ([string]$F.node -replace '^NODE_', '').ToLower()
    if (-not $mac) { return $null }
    $started = $null; try { if ($F.started) { $started = [datetime]::Parse([string]$F.started) } } catch { }
    $mine = @($Index | Where-Object { $_.Mac -eq $mac -and $_.Kind -eq [string]$F.kind -and -not ($started -and $_.When -lt $started) })
    # 1) the folder this import goes to, same repeat
    $unsure = $null
    foreach ($e in @($mine | Where-Object { $_.Dir -eq $dir -and $_.Rep -eq $Repeat })) {
        $same = Test-SameContent $e $F
        if ($same -eq $true) { return @{ Name = $e.Name; Sure = $true; Cell = $e.Cell; Here = $true } }
        if ($null -eq $same -and -not $unsure) { $unsure = @{ Name = $e.Name; Sure = $false; Cell = $e.Cell; Here = $true } }
    }
    # 2) anywhere else in exports (any run / repeat) - only a real content match counts
    foreach ($e in @($mine | Where-Object { $_.Dir -ne $dir -or $_.Rep -ne $Repeat })) {
        if ((Test-SameContent $e $F) -eq $true) { return @{ Name = $e.Name; Sure = $true; Cell = $e.Cell; Here = $false } }
    }
    return $unsure
}
function Test-ImpLocOnly([string]$Cell, [string]$Pick) {
    # same attack + topology, different location = a card whose location.txt was
    # left on the last site (oct. 18 2026), not a different experiment
    if (-not $Pick -or -not $Cell) { return $false }
    $c = $Cell -split ' / '; $p = $Pick -split ' / '
    return ($c.Count -eq 3 -and $p.Count -eq 3 -and $c[0] -eq $p[0] -and $c[1] -eq $p[1] -and $c[2] -ne $p[2])
}
function Show-ImpList($Items) {
    $script:ImpItems = @($Items)
    $mem = Get-MemberInfo
    $newest = ''; foreach ($f in @($Items | Sort-Object { Get-RunStampRaw $_ } -Descending)) { $st = Get-RunStampRaw $f; if ($st) { $newest = $st; break } }
    $dt = New-Object System.Data.DataTable
    [void]$dt.Columns.Add('Import', [bool])
    foreach ($c in 'Status', 'Why', 'Ran', 'Board', 'Cell', 'Dest', 'Kind', 'Boot', 'Rows', 'Phases', 'File', 'Rel', 'Look') { [void]$dt.Columns.Add($c, [string]) }
    # the run picked above: every file the board recorded under another run is flagged
    $pick = Get-ImpPick
    $scn = [string]$ui.ImpScenario.SelectedItem
    $impRep = 1; [void][int]::TryParse($ui.ImpRepeat.Text, [ref]$impRep)
    $expIndex = Get-ExportIndex   # scan datasets\exports first (cached; only new / changed files re-read)
    foreach ($c in 'StatusBg', 'StatusFg', 'RanFg') { [void]$dt.Columns.Add($c, [object]) }
    foreach ($c in 'BRole', 'BMac', 'BNick', 'CAtk', 'CRest', 'DMid', 'DScn', 'RanDate', 'RanTime') { [void]$dt.Columns.Add($c, [string]) }
    [void]$dt.Columns.Add('AtkFg', [object])
    $count = @{}
    # a board that rebooted DURING the run (crash / power) left the run in
    # several files (one per boot). The analysis takes ONE file per board, so
    # tick only the best piece and say so. Pieces of ONE run start within
    # seconds of each other; a separate run of the same cell (another day,
    # another repeat) is hours apart and is NOT a piece (oct. 17 fix).
    # Best = has the attack (when the phases are known), then closed cleanly,
    # then the biggest FILE SIZE. (Bug, oct. 17: rows - known only for a clean
    # file over USB - were compared with bytes of an aborted one, so a small
    # fragment beat the complete file.)
    $best = @{}
    foreach ($g in @($Items | Where-Object { $_.kind -eq 'telem' } | Group-Object { '{0}|{1}|{2}|{3}' -f $_.node, $_.filed_under, $_.topology, $_.location } | Where-Object Count -gt 1)) {
        $clusters = @(); $cur = @(); $prev = $null
        foreach ($f in @($g.Group | Sort-Object { [string]$_.started })) {
            $t = $null; try { if ($f.started) { $t = [datetime]::Parse([string]$f.started) } } catch { }
            if ($cur.Count -and (-not $t -or -not $prev -or ($t - $prev).TotalMinutes -gt 15)) { $clusters += , $cur; $cur = @() }
            $cur += $f; $prev = $t
        }
        if ($cur.Count) { $clusters += , $cur }
        foreach ($cl in $clusters) {
            if (@($cl).Count -lt 2) { continue }
            # oct. 18 2026 (F4:18): a board that crashed and rebooted closes only its post-crash TAIL
            # cleanly - a clean file under half the size of the biggest piece is that tail, not the run
            $maxSz = (@($cl) | ForEach-Object { Get-PieceSize $_ } | Measure-Object -Maximum).Maximum
            $bp = @($cl) | Sort-Object @{ E = { if ($null -ne $_.phases) { [int](@($_.phases) -contains 1 -or @($_.phases) -contains 2) } else { 0 } }; Descending = $true },
                                       @{ E = { [int]($_.clean -eq $true -and (Get-PieceSize $_) -ge 0.5 * $maxSz) }; Descending = $true },
                                       @{ E = { if ($null -ne $_.bytes -and [long]$_.bytes -ge 0) { [long]$_.bytes } elseif ($null -ne $_.rows) { [long]$_.rows * 80 } else { 0 } }; Descending = $true } | Select-Object -First 1
            foreach ($f in @($cl)) { $best[[string]$f.rel] = @{ Rel = $bp.rel; N = @($cl).Count } }
        }
    }
    foreach ($f in @($Items | Sort-Object @{ E = { Get-RunStampRaw $_ }; Descending = $true }, @{ E = { $_.node } }, @{ E = { $_.kind } })) {
        $look = if ($f.live -eq $true) { 'live' } elseif (Test-NoExperimentData $f) { 'nodata' } elseif ($null -ne $f.rows -and [int]$f.rows -eq 0) { 'empty' }
                elseif ($f.clean -eq $false) { 'aborted' } elseif ($f.already -and $null -eq $f.rows) { 'samerep' } elseif ($f.already) { 'already' } else { 'new' }
        # the GUI's own content scan of the destination folder (catches a copy under another name)
        $alreadyName = [string]$f.already
        if ($look -in @('new', 'aborted', 'samerep')) {
            $gm = Find-ImportedCopy $f $scn $impRep $expIndex
            if ($gm -and $gm.Sure) { $look = 'already'; $alreadyName = $(if ($gm.Here) { $gm.Name } else { "$($gm.Name) in $($gm.Cell)" }) }
            elseif ($gm -and $look -eq 'new') { $look = 'samerep'; $alreadyName = $gm.Name }
        }
        $cell = '{0} / {1} / {2}' -f $f.filed_under, $f.topology, $f.location
        if ($pick -and $cell -ne $pick -and $look -in @('new', 'samerep')) { $look = 'other' }
        $grp = $best[[string]$f.rel]
        $isPiece = $grp -and $f.kind -eq 'telem' -and $look -in @('new', 'samerep', 'aborted', 'already')
        if ($isPiece -and $grp.Rel -ne $f.rel -and $look -ne 'already') { $look = 'piece' }
        $count[$look] = 1 + [int]$count[$look]
        $why = switch ($look) {
            'live'    { 'The board is writing to this file right now - wait until its run has ended.' }
            'nodata'  { 'Only pre-run phase 255 - the board stopped before the root''s schedule reached it.' }
            'empty'   { '0 rows - nothing was flushed to the card.' }
            'aborted' { $cz = Get-AbortCauseText $f; 'Started, never closed cleanly - ' + $(if ($cz) { $cz } else { (Get-EndedText $f.ended_by) }) }
            'samerep' { "The same board + repeat is already in exports ($alreadyName) - may be an OLDER run; a new run needs a new repeat number." }
            'already' { "Already imported as $alreadyName (same board, same rows - found by scanning all of datasets\exports, whatever the file is called)" }
            'other'   { if (Test-ImpLocOnly $cell $pick) { "Only the LOCATION differs: the card recorded $cell, you picked $pick. A card files by its own location.txt - if it still held the last site, this IS your run. Tick it and Import asks to file it under your pick." }
                        else { "The board recorded this under $cell - not the run you picked ($pick). It would be filed under $cell, not under your pick. Tick it only if that is right." } }
            'piece'   { "Nothing wrong with this file - it is just NOT NEEDED. This board rebooted during the run, so the run is split over $($grp.N) files, and the analysis uses ONE file per board: the best piece (with the attack, then the biggest) is already ticked." }
            default   { 'Not in exports yet.' }
        }
        $nodeMac = ([string]$f.node -replace '^NODE_', '')
        $k = if ($nodeMac.Length -ge 12) { $mem[($nodeMac.Substring(0, 2) + ':' + $nodeMac.Substring(10, 2)).ToLower()] } else { $null }
        $board = '{0}  {1}{2}' -f $f.role, $(if ($nodeMac.Length -ge 12) { $nodeMac.Substring(0, 2) + ':' + $nodeMac.Substring(10, 2) } else { $nodeMac }), $(if ($k) { "  $($k.Nick)" } else { '' })
        $stamp = Get-RunStampRaw $f
        $rows = if ($null -eq $f.rows) { if ($null -ne $f.bytes -and $f.bytes -ge 0) { '? ({0})' -f (Format-ByteSize $f.bytes) } else { '?' } } else { '{0:N0}' -f [int]$f.rows }
        $ph = if ($null -ne $f.phases) { (@($f.phases) | Where-Object { $_ -ne 255 }) -join ',' } else { '' }
        $L = $script:ImpLook[$look]
        $stTxt = $L.Text + $(if ($look -eq 'aborted' -and $f.ended_by) { ' - ' + (Get-EndedShort $f.ended_by) } else { '' })
        # oct. 20 2026 firmware: closed by the board itself after it lost the root - not a broken file
        if ($look -eq 'aborted' -and $f.root_lost -eq $true) {
            $stTxt = 'CUT SHORT - CLOSED SAFELY'
            $why = 'The board LOST THE ROOT (its link into the mesh broke) and closed this file itself once the planned run was over. Every row up to the loss is good and safe to import; the run is incomplete for this board - check the root log for when it dropped.'
        }
        if ($isPiece -and $grp.Rel -eq $f.rel) { $stTxt += '  (best of {0} pieces)' -f $grp.N; $why = "This board REBOOTED during the run - the run is split over $($grp.N) files; this is the best piece (the analysis takes one file per board). " + $why }
        $tick = ($look -eq 'new') -or ($isPiece -and $grp.Rel -eq $f.rel -and $look -eq 'aborted')
        $row = $dt.Rows.Add($tick, $stTxt + $(if ($f.archived) { '  (_archive)' } else { '' }), $why,
            (Format-RunStamp $f).Trim(), $board, $cell, ('{0}\{1}\{2}\{3}' -f $f.filed_under, $f.topology, $f.location, $scn), [string]$f.kind,
            $(if ($null -ne $f.run) { "b$($f.boot) / r$($f.run)" } else { "b$($f.boot)" }), $rows, $ph, [string]$f.name, [string]$f.rel, $look,
            (& $brush $L.Bg), (& $brush $L.Fg), (& $brush $(if (-not $stamp) { $Pal.Faint } elseif ($stamp -eq $newest) { $Pal.Green } else { $Pal.Amber })))
        # the coloured pieces of the board / recorded-as / goes-to columns
        # "~09 / 22 / 2026 18:03": the date by recency colour, the time bold cyan
        $ran = ([string]$row['Ran']).Trim()
        $mt = [regex]::Match($ran, '^(?<d>.*?)(?<t>\s\d{1,2}:\d{2}(?::\d{2})?)$')
        if ($mt.Success) { $row['RanDate'] = $mt.Groups['d'].Value; $row['RanTime'] = $mt.Groups['t'].Value } else { $row['RanDate'] = $ran; $row['RanTime'] = '' }
        $row['BRole'] = [string]$f.role
        $row['BMac'] = $(if ($nodeMac.Length -ge 12) { $nodeMac.Substring(0, 2) + ':' + $nodeMac.Substring(10, 2) } else { $nodeMac })
        $row['BNick'] = $(if ($k) { $k.Nick } else { '' })
        $row['CAtk'] = [string]$f.filed_under; $row['AtkFg'] = Get-Brush (Get-AtkHex ([string]$f.filed_under))
        # oct. 20 2026: + the SCENARIO the card recorded (scenario.txt, firmware since oct. 20); '?' on older cards
        $row['CRest'] = ' / {0} / {1} / {2}' -f $f.topology, $f.location, $(if ($f.PSObject.Properties['scenario'] -and $f.scenario) { [string]$f.scenario } else { '? (older card)' })
        $row['DMid'] = '\{0}\{1}\' -f $f.topology, $f.location; $row['DScn'] = $scn
    }
    $dt.Add_ColumnChanged({ param($s, $e) if ($e.Column.ColumnName -eq 'Import') { Update-ImpSummary } })
    $script:ImpTable = $dt
    $ui.ImpGrid.ItemsSource = $dt.DefaultView
    $ui.ImpEmpty.Visibility = $(if ($dt.Rows.Count) { 'Collapsed' } else { 'Visible' })
    $ui.ImpEmptyText.Text = 'Nothing on this card / board for import.'
    $script:ImpCounts = $count
    Update-ImpSummary
    # a file the board is STILL WRITING: never imported; over USB it can be
    # closed cleanly first (the CLI's END_RUN offer, Import-OneSdCard)
    $liveN = [int]$count['live']
    $ui.ImpLiveBar.Visibility = $(if ($liveN) { 'Visible' } else { 'Collapsed' })
    $ui.ImpEndRun.Visibility = $(if ($liveN -and $ui.SrcPort.IsChecked) { 'Visible' } else { 'Collapsed' })
    $ui.ImpLiveTitle.Text = $(if ($ui.SrcPort.IsChecked) { "{0} file(s) on this board are STILL RUNNING - the board is still writing them." -f $liveN }
                              else { "{0} file(s) on this card were still open when the card was pulled - put it back in its board and close the run over USB." -f $liveN })
}
function Update-ImpSummary {
    $dt = $script:ImpTable; if (-not $dt) { return }
    $n = @($dt.Rows | Where-Object { $_.Import }).Count
    $c = $script:ImpCounts
    $parts = @()
    foreach ($k in 'new', 'piece', 'other', 'already', 'samerep', 'live', 'aborted', 'nodata', 'empty') { if ($c[$k]) { $parts += ('{0} {1}' -f $c[$k], $script:ImpLook[$k].Text.ToLower()) } }
    $cells = @($script:ImpItems | ForEach-Object { '{0}/{1}/{2}' -f $_.filed_under, $_.topology, $_.location } | Group-Object | Sort-Object Count -Descending)
    $extra = if ($cells.Count -gt 1) { "   -   (!) files from $($cells.Count) different runs on this card - check it is the right one" } else { '' }
    $ui.ImpSummary.Text = ('{0} ticked   -   {1}{2}' -f $n, ($parts -join ', '), $extra)
    $ui.ImpGo.Content = $(if ($n) { "Import $n file(s)  ->" } else { 'Import' })
    $ui.ImpGo.IsEnabled = ($n -gt 0); $ui.ImpPreview.IsEnabled = ($n -gt 0)
    $ui.ImpDel.IsEnabled = ($n -gt 0); $ui.ImpDel.Content = $(if ($n) { "Delete $n from card" } else { 'Delete from card' })
    Update-ImpDestReal
}
function Start-ImpList([switch]$Again) {
    $py = Get-Py; if (-not $py) { return }
    $a = Get-ImpArgs -List; if (-not $a) { return }
    if ($ui.ImpAborted.IsChecked) { $a += '--include-aborted' }
    $ui.ImpEmptyText.Text = $(if ($ui.SrcPort.IsChecked) { 'Reading the card through the board over USB - do not unplug it...' } else { 'Reading the card...' })
    $ui.ImpEmpty.Visibility = 'Visible'; $ui.ImpGrid.ItemsSource = $null
    [void](Start-StreamJob -Exe $py -ToolArgs $a -Title $(if ($Again) { 'Refresh the file list' } else { 'List the files' }) -NoStop:([bool]$ui.SrcPort.IsChecked) -State ([bool]$Again) -OnDone {
        param($text, $code, $again)
        $line = ($text -split "`r?`n" | Where-Object { $_.TrimStart().StartsWith('[') } | Select-Object -Last 1)
        if (-not $line) {
            # a board that just booted (command task not up yet) or is still closing
            # its files answers LIST_SD late - wait a moment and ask once more by itself
            if ($ui.SrcPort.IsChecked -and $text -match 'never finished LIST_SD' -and -not $script:ImpRetried) {
                $script:ImpRetried = $true
                $ui.ImpEmptyText.Text = 'The board was still busy - asking again in 5 s...'
                Write-Activity '  board still busy (just booted / closing its files) - listing again in 5 s by itself' $Pal.Amber
                $script:ImpRetryTimer = New-Object Windows.Threading.DispatcherTimer
                $script:ImpRetryTimer.Interval = [TimeSpan]::FromSeconds(5)
                $script:ImpRetryTimer.Add_Tick({ $script:ImpRetryTimer.Stop(); Start-ImpList })
                $script:ImpRetryTimer.Start()
                return
            }
            $script:ImpRetried = $false
            $ui.ImpEmptyText.Text = $(if ($ui.SrcPort.IsChecked) { 'No file list came back - the board may still be running its capture, have no card, or run firmware older than LIST_SD (see the activity pane). Press List again in a few seconds.' } else { 'No file list came back - see the activity pane.' })
            if ($ui.SrcPort.IsChecked -and $ui.CardPortPick.SelectedItem) { $hold = Get-PortHolderText ([string]$ui.CardPortPick.SelectedItem.Port); if ($hold) { $ui.ImpEmptyText.Text += "`n`n$($ui.CardPortPick.SelectedItem.Port) is $hold."; Write-Activity "  $($ui.CardPortPick.SelectedItem.Port) is $hold" $Pal.Amber } }
            return
        }
        $script:ImpRetried = $false
        $items = @($line | ConvertFrom-Json | ForEach-Object { $_ })
        # the CLI's naming preset: pick it from what is on the card, then list
        # again WITH it so "already imported" is checked against the right names
        $cells = @($items | ForEach-Object { '{0}/{1}/{2}' -f $_.filed_under, $_.topology, $_.location } | Select-Object -Unique)
        $pk = Get-ImpPick; if ($pk) { $cells = @($pk -replace ' / ', '/') }
        $before = if ($ui.ImpRoster.SelectedItem) { $ui.ImpRoster.SelectedItem.Path } else { '' }
        Update-ImpRosters $cells
        $now = if ($ui.ImpRoster.SelectedItem) { $ui.ImpRoster.SelectedItem.Path } else { '' }
        if ($now -ne $before -and -not $again -and $items.Count) { Write-Activity ("  naming from {0} - listing again with its board names" -f (Split-Path $now -Leaf)) $Pal.Cyan; Start-ImpList -Again; return }
        if (-not (Get-ImpPick) -and $items.Count) {
            # the run with the most files on the card (newest first on a tie)
            $top = @($items | Group-Object { '{0}|{1}|{2}' -f $_.filed_under, $_.topology, $_.location } | Sort-Object Count -Descending)[0].Name -split '\|'
            $script:ImpFilling = $true; Set-ImpPick $top[0] $top[1] $top[2]; $script:ImpFilling = $false
            Update-ImpDest
        }
        Show-ImpList $items
        Write-Activity ("  {0} file(s): {1}" -f $items.Count, $ui.ImpSummary.Text) $Pal.Green
    })
}
$ui.ImpList.Add_Click({ $script:ImpRosterWant = $(if ($ui.ImpRoster.SelectedItem) { $ui.ImpRoster.SelectedItem.Path } else { $script:ImpRosterWant }); Start-ImpList })
$ui.ImpAll.Add_Click({ if ($script:ImpTable) { foreach ($r in $script:ImpTable.Rows) { $r.Import = $true } } })
$ui.ImpNone.Add_Click({ if ($script:ImpTable) { foreach ($r in $script:ImpTable.Rows) { $r.Import = $false } } })
$ui.ImpNew.Add_Click({ if ($script:ImpTable) { foreach ($r in $script:ImpTable.Rows) { $r.Import = ($r.Look -eq 'new') } } })
function Start-ImpCopy([switch]$Preview) {
    if (Test-TaskBusy $(if ($Preview) { 'The preview' } else { 'The import' })) { return }
    [void]$ui.ImpGrid.CommitEdit(); [void]$ui.ImpGrid.CommitEdit()
    $py = Get-Py; if (-not $py -or -not $script:ImpTable) { return }
    $picked = @($script:ImpTable.Rows | Where-Object { $_.Import })
    if (-not $picked.Count) { return }
    $a = Get-ImpArgs; if (-not $a) { return }
    $a += @('--files', (@($picked | ForEach-Object Rel) -join ','))
    if ($ui.ImpAborted.IsChecked -or @($picked | Where-Object { $_.Look -eq 'aborted' }).Count) { $a += '--include-aborted' }
    # ticked files whose card recorded another LOCATION for the same attack +
    # topology: offer to file them under the picked run (import --file-location)
    $pk = Get-ImpPick; $locOnly = @($picked | Where-Object { Test-ImpLocOnly ([string]$_.Cell) $pk })
    $refile = $false
    if ($locOnly.Count) {
        $other = @($picked | Where-Object { [string]$_.Cell -ne $pk -and -not (Test-ImpLocOnly ([string]$_.Cell) $pk) })
        $wantLoc = ($pk -split ' / ')[2]; $cardLoc = @($locOnly | ForEach-Object { ([string]$_.Cell -split ' / ')[2] } | Select-Object -Unique) -join ', '
        if ($other.Count) {
            [void][Windows.MessageBox]::Show("{0} ticked file(s) were recorded as {1}, and {2} are from a different attack / topology.`n`nImport them separately: tick only the {1} ones to file them under {3}." -f $locOnly.Count, $cardLoc, $other.Count, $wantLoc, 'Mixed runs', 'OK', 'Warning')
            return
        }
        $ans = [Windows.MessageBox]::Show("{0} file(s) were recorded on the card as {1}, but the run you picked is {2}.`n`nThe card files by its own location.txt, which may still hold the last site.`n`nYes = file them under {2} (this run really was at {2})`nNo = keep the card's {1}" -f $locOnly.Count, $cardLoc, $wantLoc, 'File under which location?', 'YesNoCancel', 'Question')
        if ($ans -eq 'Cancel') { return }
        if ($ans -eq 'Yes') { $a += @('--file-location', $wantLoc); $refile = $true }
    }
    if ($Preview -or $ui.DryRun.IsChecked) { $a += '--dry-run' }
    elseif ($ui.SrcCard.IsChecked -and $ui.ImpDelete.IsChecked) { $a += '--delete-source' }
    if (-not $Preview -and -not $ui.DryRun.IsChecked) {
        $odd = @($picked | Where-Object { $_.Look -ne 'new' })
        $msg = "Import {0} file(s) into datasets\exports?{1}{2}" -f $picked.Count,
            $(if ($odd.Count) { "`n`n{0} of them are not NEW:`n    {1}" -f $odd.Count, ((@($odd | ForEach-Object { "$($_.Status)  $($_.File)" }) | Select-Object -First 6) -join "`n    ") } else { '' }),
            $(if ($a -contains '--delete-source') { "`n`nEach file is deleted from the card AFTER its copy is verified." } else { '' })
        if (-not (Confirm-Action $msg 'Import')) { return }
    }
    $state = @{ Before = @(Get-ExportCsvSet -Base $base); Started = (Get-UnixNow); Preview = [bool]($Preview -or $ui.DryRun.IsChecked); N = $picked.Count
                Cell = $(if ($refile) { $pk } else { @($picked | ForEach-Object Cell | Group-Object | Sort-Object Count -Descending)[0].Name }) }
    [void](Start-StreamJob -Exe $py -ToolArgs $a -Title $(if ($state.Preview) { "Preview: import $($picked.Count) file(s)" } else { "Import $($picked.Count) file(s)" }) -NoStop -State $state -OnDone {
        param($text, $code, $st)
        if ($st.Preview) {
            $n = [regex]::Matches($text, '(?m)^\s*WOULD COPY').Count
            Show-Toast 'Preview ready' ("{0} file(s) would be copied, nothing was changed - where each one goes is in the activity pane." -f $n) ([string][char]0xE7B3) 'GradCool'
            return
        }
        try { Save-ImportBatch -Base $base -Before $st.Before -Started $st.Started } catch { }
        # oct. 20 2026 (user: "it said the export succeeded, but no files were there"): exit 0 only
        # meant "no error" - every ticked file could have been SKIPPED (already imported / same
        # node + repeat / aborted / still running). Success now = files that exist at their real
        # path and read back with rows (IMPORTED_FILE lines, re-checked here), shown by path.
        $files = @([regex]::Matches($text, '(?m)^IMPORTED_FILE: (.+)\|(\d+)\s*$') | ForEach-Object {
            [pscustomobject]@{ Path = $_.Groups[1].Value.Trim(); Rows = [int]$_.Groups[2].Value } } |
            Where-Object { (Test-Path -LiteralPath $_.Path) -and (Get-Item -LiteralPath $_.Path).Length -gt 0 })
        $res = [regex]::Match($text, 'IMPORT_RESULT: copied=(\d+) skipped=(\d+) aborted=(\d+) live=(\d+) failed=(\d+) filtered=(\d+)')
        $skips = @([regex]::Matches($text, '(?m)^\s*SKIP\s+(\S+)\s*\r?\n\s+(.+)$') | ForEach-Object { '{0}: {1}' -f (Split-Path $_.Groups[1].Value -Leaf), $_.Groups[2].Value.Trim() })
        foreach ($f in $files) { Write-Activity ("  WRITTEN + VERIFIED: {0}  ({1} rows)" -f $f.Path, $f.Rows) $Pal.Green }
        foreach ($k in $skips) { Write-Activity ("  NOT IMPORTED: {0}" -f $k) $Pal.Amber }
        if ($code -eq 0 -and -not $files.Count) {
            $why = if ($skips.Count) { ($skips | Select-Object -First 2) -join "`n" } elseif ($res.Success -and [int]$res.Groups[5].Value) { "$($res.Groups[5].Value) file(s) failed to copy / verify" } else { 'no file reached the exports folder' }
            Show-Toast 'NOTHING was imported' ("0 of {0} file(s) written. {1}" -f $st.N, $why) ([string][char]0xE7BA) 'GradMain'
            [void][Windows.MessageBox]::Show(("No file was written to datasets\exports.`n`n{0}`n`nThe full reasons are in the activity pane. 'already imported' = that capture is already in exports (open its run on Verify); 'same node + repeat' = import it again with the next repeat number if it is a NEW run." -f (($skips | Select-Object -First 6) -join "`n")), 'Import - nothing written', 'OK', 'Warning')
            Update-TrimCells; Update-ImpPorts; Start-ImpList -Again
            return
        }
        if ($code -eq 0) {
            # the folder the files REALLY landed in (the importer may file a capture elsewhere by its rows)
            $real = @($files | ForEach-Object { Split-Path $_.Path -Parent } | Select-Object -Unique)
            if ($real.Count -eq 1) {
                $rel = $real[0].Substring((Join-Path $base 'datasets\exports').Length).Trim('\') -split '\\'
                if ($rel.Count -ge 4) { $st.Cell = ('{0} / {1} / {2}' -f $rel[0], $rel[1], $rel[2]) }
            }
            if ($files.Count -lt $st.N) { Write-Activity ("  {0} of {1} ticked file(s) written - the rest were skipped (see NOT IMPORTED above)" -f $files.Count, $st.N) $Pal.Amber }
            $st.N = $files.Count
            $c = ($st.Cell -split ' / ')
            $script:ImpAnalyse = @{ Attack = $(if ($c[0] -eq 'baseline') { 'none' } else { $c[0] }); Topology = $c[1]; Location = $c[2]; Scenario = [string]$ui.ImpScenario.SelectedItem; Text = $st.Cell }
            Show-Toast 'Imported' ("{0} file(s) written + verified -> {1}" -f $st.N, $(if ($real.Count -eq 1) { $real[0].Substring($base.Length).Trim('\') } else { "$($real.Count) folders (see the activity pane)" })) ([string][char]0xE73E) 'GradGood' { $x = $script:ImpAnalyse; Start-Analysis $x.Attack $x.Topology $x.Location $x.Scenario ("{0} / {1}" -f $x.Text, $x.Scenario) } 'Analyse + verify this run'
            $sd = if ($real.Count -eq 1) { $real[0] } else { Join-Path $base ('datasets\exports\{0}\{1}' -f ($st.Cell -replace ' / ', '\'), [string]$ui.ImpScenario.SelectedItem) }
            $c3 = $st.Cell -split ' / '; Show-RunSummary $sd (Get-ExpectedBoards $c3[0] $c3[1] $c3[2] ([string]$ui.ImpScenario.SelectedItem)) 'IMPORTED - RUN SUMMARY'
        } else { Show-Toast 'Import ended with an error' 'Read the activity pane.' ([string][char]0xE783) 'GradMain' }
        Update-TrimCells; Update-ImpPorts
        Start-ImpList -Again
    })
}
$ui.ImpPreview.Add_Click({ Start-ImpCopy -Preview })
$ui.ImpEndRun.Add_Click({
    $p = $ui.CardPortPick.SelectedItem; $py = Get-Py
    if (-not $p -or -not $py) { return }
    $msg = "End the run on {0} now and close its file?`n`nIf the run is OVER (the root finished, or this board missed TERMINATE): the file closes cleanly and imports as complete.`nIf the board is still MID-RUN: its capture is cut short (it stays ABORTED).`n`nThe board is NOT reset and nothing is deleted." -f $p.Text.Trim()
    if (-not (Confirm-Action $msg 'Close the run safely')) { return }
    [void](Start-StreamJob -Exe $py -ToolArgs @('tools\export_logs.py', '--port', $p.Port, '--end-run') -Title "End the run on $($p.Port) (END_RUN)" -NoStop -OnDone {
        param($text, $code)
        $res = ([regex]::Match($text, '(?m)^END_RUN_RESULT:\s*(\S+)')).Groups[1].Value
        switch ($res) {
            'COMPLETE'  { Show-Toast 'Closed - capture complete' 'The run had reached cooldown. Listing again...' ([string][char]0xE73E) 'GradGood' }
            'CUT_SHORT' { Show-Toast 'Closed, but cut short' 'The run had NOT reached cooldown - the file stays ABORTED.' ([string][char]0xE7BA) 'GradMain' }
            'ALREADY'   { Show-Toast 'Already closed' 'The run had already ended on this board. Listing again...' ([string][char]0xE73E) 'GradGood' }
            default     { Show-Toast 'END_RUN failed' 'Read the activity pane. Do NOT reset or unplug the board to fix it.' ([string][char]0xE783) 'GradMain' }
        }
        if ($res -in @('COMPLETE', 'CUT_SHORT', 'ALREADY')) { Start-ImpList }
    })
})
$ui.ImpGo.Add_Click({ Start-ImpCopy })
# Delete the ticked files from the card WITHOUT importing (oct. 18 2026, user
# request). import_sdcard.py --delete-files: one DELETE_SD_FILE per file over
# USB (the firmware refuses a file it has open), or a plain delete on a card
# in a reader. Never a STILL RUNNING file; never-imported files are named first.
function Start-ImpDelete {
    [void]$ui.ImpGrid.CommitEdit(); [void]$ui.ImpGrid.CommitEdit()
    $py = Get-Py; if (-not $py -or -not $script:ImpTable) { return }
    $picked = @($script:ImpTable.Rows | Where-Object { $_.Import })
    if (-not $picked.Count) { return }
    $live = @($picked | Where-Object { $_.Look -eq 'live' })
    $go = @($picked | Where-Object { $_.Look -ne 'live' })
    if (-not $go.Count) { [void][Windows.MessageBox]::Show('Every ticked file is STILL RUNNING - the board is writing it. End the run first (End the run safely).', 'Nothing deleted'); return }
    $lost = @($go | Where-Object { $_.Look -notin @('already', 'nodata', 'empty') })
    $where = if ($ui.SrcPort.IsChecked) { "the card in the board on $($ui.CardPortPick.SelectedItem.Port)" } else { 'the SD card in the reader' }
    $msg = "Delete {0} file(s) from {1}?  Nothing is imported.{2}{3}" -f $go.Count, $where,
        $(if ($live.Count) { "`n`n{0} STILL RUNNING file(s) are left alone." -f $live.Count } else { '' }),
        $(if ($lost.Count) { "`n`n(!) {0} of them are NOT in datasets\exports - this is their LAST copy:`n    {1}" -f $lost.Count, ((@($lost | ForEach-Object { "$($_.Status)  $($_.File)" }) | Select-Object -First 8) -join "`n    ") } else { "`n`nAll of them are already imported (or hold no data)." })
    if (-not (Confirm-Action $msg 'Delete from card')) { return }
    if ($lost.Count -and -not (Confirm-Action ("Really delete {0} file(s) that were never imported? This cannot be undone." -f $lost.Count) 'Delete for good')) { return }
    $a = Get-ImpArgs; if (-not $a) { return }
    $a += @('--delete-files', '--files', (@($go | ForEach-Object Rel) -join ','))
    if ($ui.DryRun.IsChecked) { $a += '--dry-run' }
    [void](Start-StreamJob -Exe $py -ToolArgs $a -Title ("Delete {0} file(s) from the card" -f $go.Count) -NoStop -State $go.Count -OnDone {
        param($text, $code, $n)
        $ok = [regex]::Matches($text, '(?m)^\s*(DELETED|WOULD DELETE) ').Count
        $bad = [regex]::Matches($text, '(?m)^\s*FAILED ').Count
        if ($bad) { Show-Toast 'Some files were not deleted' ("{0} deleted, {1} failed - the activity pane says why." -f $ok, $bad) ([string][char]0xE7BA) 'GradMain' }
        else { Show-Toast 'Deleted from the card' ("{0} file(s) removed. Listing the card again..." -f $ok) ([string][char]0xE74D) 'GradGood' }
        Start-ImpList -Again
    })
}
$ui.ImpDel.Add_Click({ Start-ImpDelete })

function Get-ExportCells {
    # every captured run folder (<attack>\<topology>\<location>\<scenario>) and
    # whether its trimmed\ copy is there and up to date. .NET enumeration, top
    # level of each folder only - fast enough to run whenever the page opens.
    $root = Join-Path $base 'datasets\exports'
    $cells = New-Object System.Collections.ArrayList
    if (-not [IO.Directory]::Exists($root)) { return @() }
    # oct. 20 2026 (user: "the trim page did not show the new files"): judged by NAME as
    # well as time - a raw file with no trimmed copy (imported / collected / pulled with an
    # older timestamp) used to read as TRIMMED. Header-only raw files are left out: trim
    # skips them on purpose, so they would flag a run forever.
    $newest = { param($dir) $n = [datetime]::MinValue; $c = 0; $names = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
                foreach ($f in [IO.Directory]::EnumerateFiles($dir, '*.csv')) {
                    $c++; $t = [IO.File]::GetLastWriteTime($f); if ($t -gt $n) { $n = $t }
                    if ((New-Object IO.FileInfo $f).Length -ge 300) { [void]$names.Add([IO.Path]::GetFileName($f)) }
                }
                @($c, $n, $names) }
    foreach ($a in [IO.Directory]::EnumerateDirectories($root)) {
        foreach ($t in [IO.Directory]::EnumerateDirectories($a)) {
            foreach ($l in [IO.Directory]::EnumerateDirectories($t)) {
                foreach ($s in [IO.Directory]::EnumerateDirectories($l)) {
                    if ([IO.Path]::GetFileName($s) -eq 'trimmed') { continue }
                    $raw = & $newest $s
                    if ($raw[0] -eq 0) { continue }
                    $td = Join-Path $s 'trimmed'
                    $trim = if ([IO.Directory]::Exists($td)) { & $newest $td } else { @(0, [datetime]::MinValue, $null) }
                    $missing = @(); $extra = @()
                    if ($trim[0] -gt 0) {
                        $missing = @($raw[2] | Where-Object { -not $trim[2].Contains($_) })
                        $extra = @($trim[2] | Where-Object { -not $raw[2].Contains($_) })
                    }
                    $look = if ($trim[0] -eq 0) { 'todo' } elseif ($missing.Count -or $extra.Count -or $trim[1] -lt $raw[1].AddSeconds(-5)) { 'stale' } else { 'done' }
                    $rel = @([IO.Path]::GetFileName($a), [IO.Path]::GetFileName($t), [IO.Path]::GetFileName($l), [IO.Path]::GetFileName($s))
                    [void]$cells.Add([pscustomobject]@{ Text = ($rel -join '  /  '); Dir = $s; Rel = $rel; Files = $raw[0]; When = $raw[1]; Look = $look; Trimmed = $trim[0]
                                                         Missing = $missing.Count; Extra = $extra.Count })
                }
            }
        }
    }
    return @($cells | Sort-Object @{ E = { Get-Rank $ATTACK_ORDER $_.Rel[0] } }, @{ E = { $_.When }; Descending = $true })
}
$script:TrimLook = @{
    todo  = @{ T = 'NOT TRIMMED';           C = $Pal.Faint }
    stale = @{ T = 'NEEDS RE-TRIM';         C = $Pal.Amber }
    done  = @{ T = [string][char]0x2714 + ' TRIMMED'; C = $Pal.Green }
}
$script:TrimCells = @(); $script:TrimDirty = $true
function Update-TrimCells {
    # only when the Data page is on screen - otherwise on its next opening
    if ($ui.Pages.SelectedIndex -ne 5) { $script:TrimDirty = $true; return }
    $script:TrimDirty = $false
    $keep = if ($ui.TrimList.SelectedItem) { $ui.TrimList.SelectedItem.Dir } else { '' }
    $rows = foreach ($c in Get-ExportCells) {
        $atk = $c.Rel[0]; $topo = $c.Rel[1]; $loc = $c.Rel[2]; $scn = $c.Rel[3]
        $tone = if ($script:AtkTone[$atk]) { $script:AtkTone[$atk] } else { $Pal.Text }
        $lt = if ($script:LocTone[$loc]) { $script:LocTone[$loc] } else { $Pal.Blue }
        $sl = $script:ScnLook[$scn]; if (-not $sl) { $sl = @{ S = [string][char]0x25CF; C = $Pal.Dim } }
        $lk = $script:TrimLook[$c.Look]
        [pscustomobject]@{
            Text = $c.Text; Dir = $c.Dir; Look = $c.Look; Files = $c.Files; When = $c.When; Trimmed = $c.Trimmed
            Missing = $c.Missing; Extra = $c.Extra
            Art = (Get-TopoImage $topo $(if ($atk -eq 'baseline') { 'baseline' } else { $atk }) 56 34).psobject.BaseObject
            RowBg = (Get-FBrush ($tone -replace '#', '#22') $Pal.Card '1,0')
            AtkText = $atk.ToUpper(); AtkFg = (Get-FBrush $tone); Topo = ($topo -replace '_', ' ')
            LocText = ($loc -replace '_', ' '); LocFg = (Get-FBrush $lt); LocBg = (Get-FBrush ($lt -replace '#', '#2A'))
            ScnText = "$($sl.S) $scn"; ScnFg = (Get-FBrush $sl.C); ScnBg = (Get-FBrush ($sl.C -replace '#', '#2A'))
            Day = $c.When.ToString('MMM dd, yyyy', [Globalization.CultureInfo]::InvariantCulture)
            Sub = ("{0} file(s)  ·  {1}{2}" -f $c.Files, (Format-PresetDate $c.When -Ago),
                   $(if ($c.Missing) { "  ·  $($c.Missing) new file(s) NOT trimmed yet" } elseif ($c.Extra) { "  ·  $($c.Extra) old file(s) in trimmed\" } else { '' }))
            Status = $lk.T; StatusFg = (Get-FBrush $lk.C); StatusBg = (Get-FBrush ($lk.C -replace '#', '#2A'))
        }
    }
    $script:TrimCells = @($rows)
    $ui.TrimList.ItemsSource = $script:TrimCells
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($ui.TrimList.ItemsSource)
    if ($view) { $view.Filter = [Predicate[object]] { param($o) Test-TrimShown $o } }
    if ($keep) { $hit = @($script:TrimCells | Where-Object { $_.Dir -eq $keep }); if ($hit.Count) { $ui.TrimList.SelectedItem = $hit[0] } }
    Update-TrimFilter
    Update-ArcList
}
function Test-TrimShown($O) {
    if ($ui.TrimFTodo.IsChecked -and $O.Look -ne 'todo') { return $false }
    if ($ui.TrimFStale.IsChecked -and $O.Look -ne 'stale') { return $false }
    if ($ui.TrimFDone.IsChecked -and $O.Look -ne 'done') { return $false }
    $q = ([string]$ui.TrimSearch.Text).Trim().ToLower()
    if (-not $q) { return $true }
    $hay = ("{0} {1}" -f $O.Text, $O.Status).ToLower() -replace 'partial_mesh', 'partial_mesh partial mesh'
    foreach ($w in ($q -split '\s+')) { if (-not $hay.Contains($w)) { return $false } }
    return $true
}
function Update-TrimFilter {
    $ui.TrimSearchHint.Visibility = $(if ($ui.TrimSearch.Text) { 'Collapsed' } else { 'Visible' })
    $view = [Windows.Data.CollectionViewSource]::GetDefaultView($ui.TrimList.ItemsSource); if ($view) { $view.Refresh() }
    $all = @($script:TrimCells)
    $n = @{}; foreach ($c in $all) { $n[$c.Look] = 1 + [int]$n[$c.Look] }
    $shown = @($all | Where-Object { Test-TrimShown $_ }).Count
    $ui.TrimCount.Text = ("{0} of {1} captured run(s) shown   ·   {2} trimmed  ·  {3} need a re-trim  ·  {4} not trimmed" -f $shown, $all.Count, [int]$n.done, [int]$n.stale, [int]$n.todo)
    $script:TrimTodoCount = [int]$n.stale + [int]$n.todo
}
foreach ($n in 'TrimFAll', 'TrimFTodo', 'TrimFStale', 'TrimFDone') { $ui[$n].Add_Checked({ Update-TrimFilter }) }
$ui.TrimSearch.Add_TextChanged({ Update-TrimFilter })
$ui.TrimRefresh.Add_Click({ Update-TrimCells })
$ui.TrimList.Add_SelectionChanged({
    $c = $ui.TrimList.SelectedItem
    foreach ($b in 'TrimPreview', 'TrimGo', 'TrimOpen') { $ui[$b].IsEnabled = [bool]$c }
    if (-not $c) { $ui.TrimSel.Text = 'Pick a run above'; $ui.TrimSelSub.Text = ''; return }
    $ui.TrimSel.Text = $c.Text
    $ui.TrimSelSub.Text = switch ($c.Look) {
        'todo'  { "$($c.Files) raw file(s), no trimmed\ copy yet - Preview shows what would be kept" }
        'stale' { if ($c.Missing) { "$($c.Missing) raw file(s) have NO trimmed copy yet (new import) - re-trim it" }
                  elseif ($c.Extra) { "trimmed\ holds $($c.Extra) file(s) that are no longer in the raw export - re-trim it" }
                  else { "$($c.Files) raw file(s) are NEWER than the trimmed\ copy ($($c.Trimmed) file(s)) - re-trim it" } }
        default { "trimmed\ copy is up to date ($($c.Trimmed) file(s) from $($c.Files) raw)" }
    }
    $ui.TrimGo.Content = $(if ($c.Look -eq 'done') { [string][char]0x2702 + '  Trim again' } else { [string][char]0x2702 + '  Trim it' })
})
$ui.TrimList.Add_MouseDoubleClick({ if ($ui.TrimList.SelectedItem) { $ui.TrimPreview.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent))) } })
$ui.TrimPreview.Add_Click({
    $py = Get-Py; $c = $ui.TrimList.SelectedItem; if (-not $py -or -not $c) { return }
    [void](Start-StreamJob -Exe $py -ToolArgs @('tools\trim_run.py', $c.Dir) -Title "Trim preview $($c.Text)  (writes nothing)")
})
$ui.TrimGo.Add_Click({
    $py = Get-Py; $c = $ui.TrimList.SelectedItem; if (-not $py -or -not $c) { return }
    if ($ui.DryRun.IsChecked) { Write-Activity 'DRY RUN - use Preview to see what would be kept.' $Pal.Amber; return }
    [void](Start-StreamJob -Exe $py -ToolArgs @('tools\trim_run.py', $c.Dir, '--apply') -Title "Trim $($c.Text)" -OnDone {
        param($text, $code, $state)
        $script:TrimDirty = $true; Update-TrimCells
        if ($code -eq 0) { Show-Toast 'Trimmed' 'The trimmed\ copy is written - the raw export is untouched.' ([string][char]0xE8C6) 'GradGood' }
    })
})
$ui.TrimOpen.Add_Click({ $c = $ui.TrimList.SelectedItem; if ($c) { Start-Process explorer.exe $c.Dir } })
function Update-ArcList {
    # past archives: archive\<date>_<label>\ + the reason line of its README.md
    $root = Join-Path $base 'archive'
    $items = @()
    if ([IO.Directory]::Exists($root)) {
        foreach ($d in [IO.Directory]::EnumerateDirectories($root)) {
            $name = [IO.Path]::GetFileName($d)
            $day = ''; $label = $name
            if ($name -match '^(\d{4}-\d{2}-\d{2})_(.+)$') { $day = $Matches[1]; $label = $Matches[2] }
            elseif ($name -match '^(\d{4})(\d{2})(\d{2})_(.+)$') { $day = "$($Matches[1])-$($Matches[2])-$($Matches[3])"; $label = $Matches[4] }
            $reason = '(no reason recorded)'; $files = ''
            $rm = Join-Path $d 'README.md'
            if ([IO.File]::Exists($rm)) {
                try {
                    $lines = [IO.File]::ReadAllLines($rm)
                    $r = @($lines | Select-Object -Skip 1 | Where-Object { $_.Trim() } | Select-Object -First 1)
                    if ($r.Count -and $r[0] -notmatch '^Moved here') { $reason = $r[0].Trim() }
                    $fl = @($lines | Where-Object { $_ -match '^(\d+) file\(s\)' } | Select-Object -First 1)
                    if ($fl.Count -and $fl[0] -match '^(\d+) file') { $files = "$($Matches[1]) file(s)" }
                } catch { }
            }
            $items += [pscustomobject]@{ Day = $day; Label = ($label -replace '[-_]', ' '); Reason = $reason; Files = $files; Path = $d; Sort = $name }
        }
    }
    $ui.ArcList.ItemsSource = @($items | Sort-Object Day, Sort -Descending)
}
$ui.Pages.Add_SelectionChanged({
    param($s, $e)
    # always rescan when the Data page opens (top-level listing only - fast): a Collect, a
    # Live run export or a GitHub pull never marked the list dirty, so new files did not show
    if ($e.OriginalSource -eq $ui.Pages -and $ui.Pages.SelectedIndex -eq 5) { Update-TrimCells }
})
function Get-ArchiveArgs([switch]$Preview) {
    $label = ([string]$ui.ArcLabel.Text).Trim() -replace '[^A-Za-z0-9_-]', '-'
    if (-not $label) { [void][Windows.MessageBox]::Show('Give the archive a short label (e.g. bad-attacker-mac).', 'Archive'); return $null }
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $base 'archive.ps1'), '-Label', $label, '-Reason', ([string]$ui.ArcReason.Text))
    if ($Preview) { $a += '-WhatIf' } else { $a += '-Force' }
    return $a
}
$ui.ArcPreview.Add_Click({ $a = Get-ArchiveArgs -Preview; if ($a) { [void](Start-StreamJob -Exe 'powershell' -ToolArgs $a -Title 'Archive preview (moves nothing)') } })
$ui.ArcGo.Add_Click({
    $a = Get-ArchiveArgs; if (-not $a) { return }
    if ($ui.DryRun.IsChecked) { Write-Activity 'DRY RUN - use Preview to see what would move.' $Pal.Amber; return }
    if (Confirm-Action "MOVE all live exports, analysis, PCAP captures and run logs into archive\$((Get-Date).ToString('yyyy-MM-dd'))_$($ui.ArcLabel.Text)\ ?`n`nThey leave the live checklist. Run Preview first if unsure." 'Archive') {
        [void](Start-StreamJob -Exe 'powershell' -ToolArgs $a -Title 'Archive')
    }
})
# ── GitHub sync page (oct. 18 2026) ──────────────────────────────────────────
# tools\smart_sync.py is the brain (status --out json / apply --plan / abort-merge);
# this page shows its plan and runs it. Nothing reaches GitHub without a confirm.
$script:Sync = $null; $script:SyncAuto = $false; $script:SyncGateOk = $false; $script:SyncResume = $false; $script:SyncChecked = $null
$script:SyncLook = @{
    new        = @{ Text = 'NEW';                Bg = '#1F4D3E'; Fg = $Pal.Green }
    update     = @{ Text = 'UPDATE';             Bg = '#123A44'; Fg = $Pal.Cyan }
    replace    = @{ Text = 'REPLACE (analysis)'; Bg = '#123A44'; Fg = $Pal.Cyan }
    ledger     = @{ Text = 'LEDGER - rows merge';Bg = '#1E2A44'; Fg = $Pal.Blue }
    conflict   = @{ Text = 'KEEP BOTH';          Bg = '#3A2E14'; Fg = $Pal.Amber }
    stale      = @{ Text = 'ANALYSE FIRST';      Bg = '#3A2E14'; Fg = $Pal.Amber }
    duplicate  = @{ Text = 'DUPLICATE';          Bg = '#1E2A44'; Fg = $Pal.Blue }
    deleted    = @{ Text = 'DELETED ON GITHUB';  Bg = '#3A1E2C'; Fg = $Pal.Red }
    gone       = @{ Text = 'DELETED ON GITHUB';  Bg = '#3A1E2C'; Fg = $Pal.Red }
    equivalent = @{ Text = 'SAME ANALYSIS';      Bg = '#2A2E48'; Fg = $Pal.Dim }
    older      = @{ Text = 'GITHUB IS NEWER';    Bg = '#2A2E48'; Fg = $Pal.Dim }
    archived   = @{ Text = 'ARCHIVED';           Bg = '#2A2E48'; Fg = $Pal.Dim }
    differ     = @{ Text = 'YOURS DIFFERS';      Bg = '#3A2E14'; Fg = $Pal.Amber }
    delete     = @{ Text = 'DELETE ON GITHUB';   Bg = '#3A1E2C'; Fg = $Pal.Red }
    replaced   = @{ Text = 'OLD RUN - REPLACED'; Bg = '#3A2E14'; Fg = $Pal.Amber }
    busy       = @{ Text = 'BEING WRITTEN';      Bg = '#14304A'; Fg = $Pal.Cyan }
    deletedhere = @{ Text = 'YOU DELETED IT';    Bg = '#2A2E48'; Fg = $Pal.Dim }
    deleteconflict = @{ Text = 'DELETED HERE, CHANGED THERE'; Bg = '#3A2E14'; Fg = $Pal.Amber }
}
$script:SyncFresh = @{
    fresh = @{ Text = 'CURRENT'; Bg = '#1F4D3E'; Fg = $Pal.Green }; stale = @{ Text = 'STALE'; Bg = '#3A2E14'; Fg = $Pal.Amber }
    missing = @{ Text = 'NOT ANALYSED'; Bg = '#3A2E14'; Fg = $Pal.Amber }; unknown = @{ Text = 'OLD TABLE'; Bg = '#2A2E48'; Fg = $Pal.Dim }
    noexports = @{ Text = '-'; Bg = $Pal.Card; Fg = $Pal.Faint }; orphan = @{ Text = 'NO CAPTURES'; Bg = '#2A2E48'; Fg = $Pal.Dim }
}
$script:SyncHow = @{
    same = @{ Text = 'IDENTICAL'; Bg = '#1F4D3E'; Fg = $Pal.Green }; data = @{ Text = "TAKE GITHUB'S"; Bg = '#1E2A44'; Fg = $Pal.Blue }
    keepmine = @{ Text = 'KEEP YOURS'; Bg = '#123A44'; Fg = $Pal.Cyan }; merge = @{ Text = 'MERGE BOTH'; Bg = '#123A44'; Fg = $Pal.Cyan }
    conflict = @{ Text = 'CONFLICT'; Bg = '#3A1E2C'; Fg = $Pal.Red }
}
$script:AreaHex = @{ exports = $Pal.Cyan; analysis = $Pal.Purple; logs = $Pal.Amber; presets = $Pal.Pink }

function Set-SyncSteps([string[]]$States, [string[]]$Infos = @()) {
    # states: todo / run / done / warn / skip / fail
    $names = @('Check', 'Analyse', 'Send', 'Receive', 'Update folder')
    $tips = @('Compare this laptop with GitHub - changes nothing', 'Re-analyse runs whose captures are newer than their analysis',
              'Push the ticked files (data only, byte-verified)', 'Copy the ticked teammate files in (yours never overwritten)',
              "Bring this folder to GitHub's latest commit - backs up, merges, never half-done")
    $items = for ($i = 0; $i -lt 5; $i++) {
        $st = if ($i -lt $States.Count) { $States[$i] } else { 'todo' }
        $look = switch ($st) {
            'run'  { @{ Dot = $Pal.Cyan;  Edge = $Pal.Cyan;  Bg = '#14304A'; Mark = [string][char]0x2022; Fg = $Pal.Cyan } }
            'done' { @{ Dot = $Pal.Green; Edge = '#2C6B55';  Bg = '#173A31'; Mark = [string][char]0x2713; Fg = $Pal.Green } }
            'warn' { @{ Dot = $Pal.Amber; Edge = $Pal.Amber; Bg = '#3A2E14'; Mark = '!'; Fg = $Pal.Amber } }
            'fail' { @{ Dot = $Pal.Red;   Edge = $Pal.Red;   Bg = '#3A1E2C'; Mark = [string][char]0x2715; Fg = $Pal.Red } }
            'skip' { @{ Dot = $Pal.Line;  Edge = $Pal.Line;  Bg = $Pal.Card; Mark = '-'; Fg = $Pal.Faint } }
            default { @{ Dot = $Pal.Line; Edge = $Pal.Line;  Bg = $Pal.Card; Mark = [string]($i + 1); Fg = $Pal.Faint } }
        }
        [pscustomobject]@{ Name = $names[$i]; Tip = $tips[$i]; Info = $(if ($i -lt $Infos.Count -and $Infos[$i]) { $Infos[$i] } else { $st -replace 'todo', 'waiting' -replace 'run', 'working...' })
                           Bg = (Get-Brush $look.Bg); Edge = (Get-Brush $look.Edge); Dot = (Get-Brush $look.Dot); Mark = $look.Mark; InfoFg = (Get-Brush $look.Fg) }
    }
    $ui.SyncSteps.ItemsSource = @($items)
}
Set-SyncSteps @()

function New-SyncTable([string[]]$Cols) {
    $dt = New-Object System.Data.DataTable
    [void]$dt.Columns.Add('Pick', [bool])
    foreach ($c in $Cols) { [void]$dt.Columns.Add($c, [string]) }
    foreach ($c in 'BadgeBg', 'BadgeFg', 'AreaFg', 'AtkFg', 'AnaBg', 'AnaFg', 'AnaLBg', 'AnaLFg', 'AnaRBg', 'AnaRFg') { [void]$dt.Columns.Add($c, [object]) }
    # per-file times (oct. 21 2026): text to show + unix seconds to sort by ("today 1:40 pm" sorts wrong as text)
    foreach ($c in 'HereT', 'HubT', 'HubTip') { [void]$dt.Columns.Add($c, [string]) }
    foreach ($c in 'HereAt', 'HubAt') { [void]$dt.Columns.Add($c, [long]) }
    return , $dt   # the comma: PowerShell would unroll an empty DataTable into $null
}
function Add-SyncRow($Dt, $It, [hashtable]$Look, [bool]$Pick) {
    $r = $Dt.NewRow()
    $r.Pick = $Pick
    $lk = $Look[[string]$It.kind]; if (-not $lk) { $lk = @{ Text = ([string]$It.kind).ToUpper(); Bg = '#2A2E48'; Fg = $Pal.Dim } }
    $r.Badge = $lk.Text; $r.BadgeBg = Get-Brush $lk.Bg; $r.BadgeFg = Get-Brush $lk.Fg
    $r.Area = [string]$It.area; $r.AreaFg = Get-Brush $(if ($script:AreaHex[[string]$It.area]) { $script:AreaHex[[string]$It.area] } else { $Pal.Text })
    $cp = ([string]$It.cell) -split '/'
    $r.CAtk = $(if ($cp[0]) { $cp[0] } else { '-' }); $r.AtkFg = Get-Brush (Get-AtkHex $cp[0])
    $r.CRest = $(if ($cp.Count -gt 1) { '  /  ' + (($cp | Select-Object -Skip 1) -join '  /  ') } else { '' })
    $r.File = ([string]$It.rel).Split('/')[-1]; $r.Rel = [string]$It.rel; $r.Why = [string]$It.why
    if ($It.localWhen) { $r.HereAt = [long]$It.localWhen; $r.HereT = Format-When ([DateTimeOffset]::FromUnixTimeSeconds([long]$It.localWhen).LocalDateTime) } else { $r.HereAt = 0; $r.HereT = 'not here' }
    if ($It.hubWhen) {
        $t = [DateTimeOffset]::FromUnixTimeSeconds([long]$It.hubWhen).LocalDateTime
        $r.HubAt = [long]$It.hubWhen; $r.HubT = Format-When $t
        $r.HubTip = "on GitHub since {0}`nby {1}" -f $t.ToString('ddd MMM d yyyy, h:mm:ss tt'), $It.hubWho
    } elseif ([string]$It.kind -in @('gone', 'deleted')) { $r.HubAt = 0; $r.HubT = 'deleted'; $r.HubTip = [string]$It.why }
    else { $r.HubAt = 0; $r.HubT = 'not on GitHub'; $r.HubTip = 'GitHub does not have this file (yet)' }
    return $r
}
function Show-SyncStatus($St) {
    $script:Sync = $St; $script:SyncChecked = Get-Date
    $h = $St.health
    # chips
    $chips = New-Object System.Collections.ArrayList
    $add = { param($t, $hex, $bg, $tip) [void]$chips.Add([pscustomobject]@{ Text = $t; Fg = (Get-Brush $hex); Bg = (Get-Brush $bg); Tip = $tip }) }
    & $add ("branch  " + $h.branch) $Pal.Cyan '#123A44' "Data follows the branch this folder is on. $($h.url)"
    & $add ("laptop  " + $h.computer) $Pal.Dim $Pal.Card 'How your pushes are signed (and where KEEP-BOTH copies go: sync_conflicts\<laptop>\)'
    if ($h.fetched) { & $add ([string][char]0x2713 + '  GitHub reachable') $Pal.Green '#173A31' '' } else { & $add ([string][char]0x2715 + '  GitHub NOT reachable') $Pal.Red '#3A1E2C' (@($h.warnings) -join "`n") }
    if (@($h.blocking).Count) { & $add ([string][char]0x2715 + '  folder blocked') $Pal.Red '#3A1E2C' (@($h.blocking) -join "`n") } else { & $add ([string][char]0x2713 + '  no unfinished merge') $Pal.Green '#173A31' 'No merge / rebase / cherry-pick half-done in this folder.' }
    $u = $St.update
    if ($u.behind) { & $add ([string][char]0x2193 + "  $($u.behind) commit(s) to bring in") $Pal.Blue '#1E2A44' 'GitHub has commits this folder does not - step 5 brings them in safely.' } else { & $add ([string][char]0x2713 + '  folder up to date') $Pal.Green '#173A31' '' }
    if ($u.ahead) { & $add ([string][char]0x2191 + "  $($u.ahead) code commit(s) not pushed") $Pal.Amber '#3A2E14' 'Commits only this laptop has. Data sync never sends code - push them with git push when ready.' }
    $cd = @($h.codeDirty).Count
    if ($cd) { & $add ("$cd code file(s) edited here") $Pal.Dim $Pal.Card ("Never synced (code goes through git commit / push):`n" + ((@($h.codeDirty) | Select-Object -First 12 | ForEach-Object { "  $($_.status) $($_.path)" }) -join "`n")) }
    if ($h.stashes) { & $add ("$($h.stashes) old stash(es)") $Pal.Amber '#3A2E14' "'git stash list' - make sure nothing is forgotten there." }
    # oct. 21 2026: a run folder holding two captures of the same repeat (the analysis reads both)
    foreach ($m in @($h.mixed)) {
        if (-not $m) { continue }
        & $add ([string][char]0x26A0 + "  GitHub mixes 2 runs: " + ($m.cell -replace '/', ' / ') + $(if ($m.fix) { '  (this sync fixes it)' } else { '' })) $(if ($m.fix) { $Pal.Amber } else { $Pal.Red }) $(if ($m.fix) { '#3A2E14' } else { '#3A1E2C' }) ("Root captures in that folder on GitHub:`n  " + (@($m.roots) -join "`n  ") + $(if ($m.fix) { "`n`nThe OLD run is ticked under Send as 'OLD RUN - REPLACED' (your re-capture archive)." } else { "`n`nNo re-capture archive here says which run is old - decide with the team, then delete the old one on GitHub." }))
    }
    foreach ($m in @($h.mixedHere)) { if ($m) { & $add ([string][char]0x26A0 + "  this laptop mixes 2 runs: " + ($m.cell -replace '/', ' / ')) $Pal.Red '#3A1E2C' ("Root captures in that folder here:`n  " + (@($m.roots) -join "`n  ")) } }
    if ($St.last) { & $add ("last smart sync  " +(Format-When ([DateTimeOffset]::FromUnixTimeSeconds([long]$St.last.when).LocalDateTime))) $Pal.Dim $Pal.Card ("sent {0}, received {1}" -f $St.last.pushed, $St.last.pulled) }
    $ui.SyncChips.ItemsSource = @($chips)
    # blocking banner
    if (@($h.blocking).Count) {
        $ui.SyncBlockText.Text = "Your folder needs attention before it can be updated:`n  " + (@($h.blocking) -join "`n  ")
        $ui.SyncAbortMerge.Visibility = $(if (@($h.blocking) -match 'MERGE') { 'Visible' } else { 'Collapsed' })
        $ui.SyncBlock.Visibility = 'Visible'
    } elseif (-not $u.canUpdate -and $u.why) {
        $ui.SyncBlockText.Text = "Your folder can't be updated automatically: $($u.why)`nSending and receiving data still work."
        $ui.SyncAbortMerge.Visibility = 'Collapsed'; $ui.SyncBlock.Visibility = 'Visible'
    } else { $ui.SyncBlock.Visibility = 'Collapsed' }
    # send / receive / held / cleanup / runs / folder
    $send = New-SyncTable @('Badge', 'Area', 'CAtk', 'CRest', 'File', 'Rel', 'Why', 'Ana')
    $held = New-SyncTable @('Badge', 'Area', 'CAtk', 'CRest', 'File', 'Rel', 'Why')
    foreach ($it in @($St.push)) {
        if ($it.act -eq 'push') {
            # oct. 20 2026: a DELETE ON GITHUB item is never ticked for you (tick = False from smart_sync)
            $r = Add-SyncRow $send $it $script:SyncLook ($it.kind -ne 'delete' -and $it.tick -ne $false)
            if ($it.needsAnalysis) { $f = $script:SyncFresh[[string]$it.needsAnalysis]; $r.Ana = $f.Text; $r.AnaBg = Get-Brush $f.Bg; $r.AnaFg = Get-Brush $f.Fg; $r.Why = $r.Why + "  -  this run's analysis is $($f.Text.ToLower())" }
            [void]$send.Rows.Add($r)
        } else { [void]$held.Rows.Add((Add-SyncRow $held $it $script:SyncLook $false)) }
    }
    $recv = New-SyncTable @('Badge', 'Area', 'CAtk', 'CRest', 'File', 'Rel', 'Why', 'Who')
    foreach ($it in @($St.pull)) {
        if ($it.act -eq 'pull') {
            $r = Add-SyncRow $recv $it $script:SyncLook $true
            $r.Who = [string]$it.who   # its time is in the "on GitHub since" column
            [void]$recv.Rows.Add($r)
        } else { [void]$held.Rows.Add((Add-SyncRow $held $it $script:SyncLook $false)) }
    }
    $gone = New-SyncTable @('Badge', 'Area', 'CAtk', 'CRest', 'File', 'Rel', 'Why')
    foreach ($it in @($St.gone)) { [void]$gone.Rows.Add((Add-SyncRow $gone $it $script:SyncLook $false)) }
    $runs = New-SyncTable @('CAtk', 'CRest', 'Here', 'Hub', 'AnaL', 'AnaR', 'Note', 'Why')
    foreach ($c in @($St.cells)) {
        $r = $runs.NewRow(); $cp = ([string]$c.cell) -split '/'
        $r.CAtk = $cp[0]; $r.AtkFg = Get-Brush (Get-AtkHex $cp[0]); $r.CRest = '  /  ' + (($cp | Select-Object -Skip 1) -join '  /  ')
        $r.Here = [string]$c.localBoards + $(if ($c.onlyHere) { "  (+$($c.onlyHere) not sent)" } else { '' })
        $r.Hub = [string]$c.githubBoards + $(if ($c.onlyGithub) { "  (+$($c.onlyGithub) new)" } else { '' })
        foreach ($side in @(@('AnaL', [string]$c.localAnalysis), @('AnaR', [string]$c.githubAnalysis))) {
            $f = $script:SyncFresh[$side[1]]; if (-not $f) { $f = $script:SyncFresh.unknown }
            $r[$side[0]] = $f.Text; $r[$side[0] + 'Bg'] = Get-Brush $f.Bg; $r[$side[0] + 'Fg'] = Get-Brush $f.Fg
        }
        $r.Note = $(if ($c.localAnalysis -in @('stale', 'missing') -and $c.localBoards) { 'analyse here (Smart sync offers it)' }
                    elseif ($c.onlyHere) { 'captures to send' } elseif ($c.onlyGithub) { 'teammate captures to receive' }
                    elseif ($c.githubAnalysis -in @('stale', 'missing') -and $c.localAnalysis -eq 'fresh') { "send your analysis - GitHub's is $($c.githubAnalysis)" }
                    elseif (-not $c.rootHere) { 'no ROOT file here - incomplete run?' } else { 'in sync' })
        $r.Why = $r.Note
        [void]$runs.Rows.Add($r)
    }
    $fold = New-SyncTable @('Badge', 'File', 'Why')
    foreach ($o in @($u.obstacles)) {
        $r = $fold.NewRow(); $lk = $script:SyncHow[[string]$o.how]; if (-not $lk) { $lk = $script:SyncHow.data }
        $r.Badge = $lk.Text; $r.BadgeBg = Get-Brush $lk.Bg; $r.BadgeFg = Get-Brush $lk.Fg; $r.File = [string]$o.path; $r.Why = [string]$o.text
        [void]$fold.Rows.Add($r)
    }
    $ui.SyncFoldText.Text = $(if (-not $u.behind) { "Your folder already has every commit GitHub has. Nothing to do here." }
        else { "GitHub has $($u.behind) commit(s) this folder does not" + $(if ($u.ahead) { " (and you have $($u.ahead) of your own - they are merged, never lost)" } else { '' }) + ".`n" +
               $(if (@($u.obstacles).Count) { "$(@($u.obstacles).Count) file(s) below are in the way; each is backed up first and handled as shown. " } else { 'Nothing is in the way. ' }) +
               $(if ($u.canUpdate) { "Step 5 brings them in - if anything unexpected happens it rolls back and changes nothing." } else { "BLOCKED: $($u.why)" }) })
    $script:SyncTables = @{ Send = $send; Recv = $recv; Gone = $gone }
    foreach ($t in @($send, $recv, $gone)) { $t.Add_ColumnChanged({ param($s, $e) if ($e.Column.ColumnName -eq 'Pick' -and -not $script:SyncBulk) { Update-SyncCounts } }) }
    $ui.SyncSendGrid.ItemsSource = $send.DefaultView; $ui.SyncRecvGrid.ItemsSource = $recv.DefaultView; $ui.SyncHeldGrid.ItemsSource = $held.DefaultView
    $ui.SyncGoneGrid.ItemsSource = $gone.DefaultView; $ui.SyncRunsGrid.ItemsSource = $runs.DefaultView; $ui.SyncFoldGrid.ItemsSource = $fold.DefaultView
    $ui.SyncTabHeld.Header = "  Held back  ($($held.Rows.Count))  "; $ui.SyncTabRuns.Header = "  Runs  ($($runs.Rows.Count))  "
    $ui.SyncTabFold.Header = $(if ($u.behind) { "  Your folder  ($($u.behind) to bring in)  " } else { '  Your folder  ' })
    $ui.SyncTabGone.Header = "  Cleanup  ($($gone.Rows.Count))  "
    Update-SyncCounts
    Update-SyncGate
    Update-SyncTimes
}
function Get-SyncPicked([string]$Which) {
    $t = $null; if ($script:SyncTables) { $t = $script:SyncTables[$Which] }   # not "$t = if ...": that unrolls the table
    if ($null -eq $t) { return @() }
    return @($t.Rows | Where-Object { $_.Pick } | ForEach-Object { [string]$_.Rel })
}
function Update-SyncCounts {
    $st = $script:Sync; if (-not $st -or -not $script:SyncTables) { return }   # no plan shown (after a sync): keep the result header
    $ns = @(Get-SyncPicked 'Send').Count; $nr = @(Get-SyncPicked 'Recv').Count; $ng = @(Get-SyncPicked 'Gone').Count
    $ts = $script:SyncTables.Send.Rows.Count; $tr = $script:SyncTables.Recv.Rows.Count
    $ui.SyncTabSend.Header = "  Send  ($ns of $ts)  "; $ui.SyncTabRecv.Header = "  Receive  ($nr of $tr)  "
    $by = @{}; foreach ($r in $script:SyncTables.Send.Rows) { if ($r.Pick) { $by[$r.Area] = 1 + [int]$by[$r.Area] } }
    $ui.SyncSendInfo.Text = $(if ($ts) { "ticked: " + ((@($by.Keys | Sort-Object | ForEach-Object { "$($by[$_]) $_" })) -join ', ') + "   -   every file is checked byte-for-byte after it is committed" } else { 'Nothing to send - GitHub already has all of your data.' })
    $ui.SyncRecvInfo.Text = $(if ($tr) { 'your existing files are never overwritten (a replaced analysis is backed up first)' } else { "Nothing to receive - you have all of your teammates' data." })
    $u = $st.update; $bad = @($st.health.blocking).Count
    $total = $ns + $nr + $ng + $(if ($u.behind -and $ui.SyncUpdate.IsChecked) { 1 } else { 0 })
    if ($bad) { $head = 'Your folder needs attention'; $sub = (@($st.health.blocking) -join '  ') ; $icon = [string][char]0xE7BA; $fill = 'GradMain' }
    elseif (-not $total -and -not $ts -and -not $tr) { $head = 'Everything is in sync'; $sub = 'GitHub and this laptop hold the same data' + $(if ($u.behind) { '' } else { ', and your folder is on the latest commit.' }); $icon = [string][char]0xE73E; $fill = 'GradGood' }
    else {
        $bits = @(); if ($ns) { $bits += "$ns to send" }; if ($nr) { $bits += "$nr to receive" }; if ($ng) { $bits += "$ng to clean up" }; if ($u.behind -and $ui.SyncUpdate.IsChecked) { $bits += "$($u.behind) commit(s) to bring in" }
        $head = $(if ($bits.Count) { $bits -join '  ·  ' } else { 'Nothing ticked' }); $icon = [string][char]0xE895; $fill = 'GradCool'
        $hold = @($st.push | Where-Object { $_.act -ne 'push' }).Count + @($st.pull | Where-Object { $_.act -ne 'pull' }).Count
        $sub = "Checked " + (Format-When $script:SyncChecked) + $(if ($hold) { "   -   $hold file(s) held back on purpose (see Held back)" } else { '' }) + "   -   Smart sync asks once before anything goes to GitHub."
    }
    $ui.SyncHead.Text = $head; $ui.SyncSubHead.Text = $sub; $ui.SyncIcon.Text = $icon; $ui.SyncIconBg.Background = $win.FindResource($fill)
    $ui.SyncSendOnly.IsEnabled = ($ns -gt 0); $ui.SyncRecvOnly.IsEnabled = (($nr + $ng) -gt 0); $ui.SyncFoldOnly.IsEnabled = ([bool]$u.behind -and $u.canUpdate -and -not $bad)
}
function Get-SyncGateCells {
    # runs whose captures are being sent while their analysis here is not current
    $st = $script:Sync; if (-not $st) { return @() }
    $picked = @(Get-SyncPicked 'Send')
    $cells = @($st.push | Where-Object { $_.act -eq 'push' -and $_.needsAnalysis -in @('stale', 'missing') -and $picked -contains $_.rel } | ForEach-Object cell)
    $cells += @($st.push | Where-Object { $_.kind -eq 'stale' -and $_.area -eq 'analysis' } | ForEach-Object cell)
    return @($cells | Where-Object { $_ -and ($_ -split '/').Count -ge 4 } | Select-Object -Unique)
}
function Update-SyncGate {
    $cells = @(Get-SyncGateCells)
    if (-not $cells.Count -or $script:SyncGateOk) { $ui.SyncGate.Visibility = 'Collapsed'; return }
    $ui.SyncGateHead.Text = "{0} run(s) are not analysed for their newest captures" -f $cells.Count
    $ui.SyncGateText.Text = "Their analysis does not cover every capture, so it would not be sent - teammates would get data with no (or out-of-date) analysis.`n  " + ((@($cells | Select-Object -First 6 | ForEach-Object { $_ -replace '/', ' / ' })) -join "`n  ") + $(if ($cells.Count -gt 6) { "`n  ... and $($cells.Count - 6) more" } else { '' })
    $ui.SyncGate.Visibility = 'Visible'
}
# After a sync (or an abort) NO automatic re-check (user, oct. 18 2026): the sync
# already verified every file byte-for-byte. The page keeps the result, empties
# the lists it just acted on (they are out of date now) and marks the plan as old,
# so the next Smart sync always checks first. Check shows the new state on demand.
function Set-SyncDone([string]$Head, [string]$Sub, [string]$Fill = 'GradGood', [string]$Glyph = [string][char]0xE73E) {
    $script:SyncChecked = $null; $script:SyncTables = $null
    foreach ($gname in 'SyncSendGrid', 'SyncRecvGrid', 'SyncGoneGrid', 'SyncHeldGrid', 'SyncFoldGrid') { $ui[$gname].ItemsSource = $null }
    $ui.SyncTabSend.Header = '  Send  '; $ui.SyncTabRecv.Header = '  Receive  '; $ui.SyncTabHeld.Header = '  Held back  '
    $ui.SyncTabFold.Header = '  Your folder  '; $ui.SyncTabGone.Header = '  Cleanup  '
    $ui.SyncSendInfo.Text = 'Press Check to see what is left to send.'; $ui.SyncRecvInfo.Text = 'Press Check to see what teammates have sent.'
    $ui.SyncFoldText.Text = 'Press Check to see the folder state after this sync.'
    $ui.SyncGate.Visibility = 'Collapsed'; $ui.SyncBlock.Visibility = 'Collapsed'
    $ui.SyncSendOnly.IsEnabled = $false; $ui.SyncRecvOnly.IsEnabled = $false; $ui.SyncFoldOnly.IsEnabled = $false
    $ui.SyncHead.Text = $Head; $ui.SyncSubHead.Text = $Sub + '   -   press Check to see the latest state.'
    $ui.SyncIcon.Text = $Glyph; $ui.SyncIconBg.Background = $win.FindResource($Fill)
    Update-SyncTimes
}
function Start-SyncCheck([switch]$Continue) {
    $py = Get-Py; if (-not $py) { return }
    $out = Join-Path $env:TEMP ("nis16_sync_{0}.json" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    Set-SyncSteps @('run') @('looking at GitHub + this laptop...')
    $ui.SyncHead.Text = 'Checking...'; $ui.SyncSubHead.Text = 'Comparing every data file here with GitHub (about 20 s) - nothing is changed.'
    $ui.SyncGo.IsEnabled = $false; $ui.SyncCheck.IsEnabled = $false
    $ok = Start-StreamJob -Exe $py -ToolArgs @('tools\smart_sync.py', 'status', '--out', $out) -Title 'GitHub sync: check' -State @{ Out = $out; Continue = [bool]$Continue } -OnDone {
        param($text, $code, $st)
        $ui.SyncGo.IsEnabled = $true; $ui.SyncCheck.IsEnabled = $true
        if ($code -ne 0 -or -not (Test-Path $st.Out)) {
            $err = ($text -split "`r?`n" | Where-Object { $_ -match 'ERROR' } | Select-Object -Last 1)
            Set-SyncSteps @('fail') @('could not check'); $ui.SyncHead.Text = 'Could not check GitHub'; $ui.SyncSubHead.Text = $(if ($err) { $err.Trim() } else { 'See the activity pane.' })
            $script:SyncAuto = $false; return
        }
        $json = Get-Content -Raw -Encoding UTF8 $st.Out | ConvertFrom-Json; Remove-Item $st.Out -ErrorAction SilentlyContinue
        Show-SyncStatus $json
        Set-SyncSteps @('done') @(("{0} to send, {1} to receive" -f @($json.push | Where-Object act -eq 'push').Count, @($json.pull | Where-Object act -eq 'pull').Count))
        if ($st.Continue) { Continue-SmartSync }
    }
    if (-not $ok) { $ui.SyncGo.IsEnabled = $true; $ui.SyncCheck.IsEnabled = $true; Set-SyncSteps @() }
    else { try { $script:Stream.Proc.PriorityClass = 'BelowNormal' } catch { } }
}
function Continue-SmartSync {
    $st = $script:Sync; if (-not $st) { return }
    $check = "{0} to send, {1} to receive" -f @(Get-SyncPicked 'Send').Count, @(Get-SyncPicked 'Recv').Count
    $cells = @(Get-SyncGateCells)
    if ($cells.Count -and -not $script:SyncGateOk) {
        Set-SyncSteps @('done', 'warn') @($check, "$($cells.Count) run(s) to analyse")
        Update-SyncGate; $ui.SyncTabs.SelectedIndex = 0
        Show-Toast 'Analyse first?' ("{0} run(s) would go up without a current analysis - choose on the amber bar." -f $cells.Count) ([string][char]0xE9D9) 'GradMain'
        return
    }
    Start-SyncApply -Push (Get-SyncPicked 'Send') -Pull (Get-SyncPicked 'Recv') -Remove (Get-SyncPicked 'Gone') -Update ([bool]$ui.SyncUpdate.IsChecked) -Steps
}
function Start-SyncApply([string[]]$Push = @(), [string[]]$Pull = @(), [string[]]$Remove = @(), [bool]$Update = $false, [switch]$Steps) {
    $st = $script:Sync; if (-not $st) { return }
    $py = Get-Py; if (-not $py) { return }
    $u = $st.update
    # after a SEND your folder is always one commit behind (your own data commit), even when the
    # check said "up to date" - so a send always includes the folder step (smart_sync re-plans it)
    $doUpdate = $Update -and ([bool]$u.behind -or $Push.Count -gt 0) -and ($u.canUpdate -or -not $u.behind) -and -not @($st.health.blocking).Count
    $Push = @($Push | Where-Object { $_ }); $Pull = @($Pull | Where-Object { $_ }); $Remove = @($Remove | Where-Object { $_ })
    if (-not ($Push.Count + $Pull.Count + $Remove.Count) -and -not $doUpdate) {
        $script:SyncAuto = $false
        Set-SyncSteps @('done', 'skip', 'skip', 'skip', $(if ($u.behind -and -not $u.canUpdate) { 'warn' } else { 'skip' })) @('nothing to do')
        Show-Toast 'Nothing to do' 'Everything ticked is already in sync.' ([string][char]0xE73E) 'GradGood'; return
    }
    $lines = @()
    if ($Push.Count) {
        $by = @{}; foreach ($r in $script:SyncTables.Send.Rows) { if ($Push -contains $r.Rel) { $by[$r.Area] = 1 + [int]$by[$r.Area] } }
        $lines += ("SEND to GitHub ({0}):  {1}" -f $st.health.branch, ((@($by.Keys | Sort-Object | ForEach-Object { "$($by[$_]) $_" })) -join ', '))
        # oct. 21 2026: removals on GitHub are spelled out, never hidden inside a count
        $gone = @($script:SyncTables.Send.Rows | Where-Object { $Push -contains $_.Rel -and $_.Badge -in @('DELETE ON GITHUB', 'OLD RUN - REPLACED') })
        if ($gone.Count) {
            $runs = @($gone | ForEach-Object { ($_.CAtk + $_.CRest) -replace '\s+/\s+', '/' } | Select-Object -Unique)
            $lines += ("REMOVE on GitHub: {0} file(s) of {1} run(s) - {2}`n  (normal commits: they stay in GitHub's history and can be restored)" -f $gone.Count, $runs.Count, ($runs -join ', '))
        }
    }
    if ($Pull.Count) { $lines += ("RECEIVE {0} teammate file(s) - none of yours overwritten" -f $Pull.Count) }
    if ($Remove.Count) { $lines += ("CLEAN UP {0} copy(ies) of files deleted on GitHub (moved to backups)" -f $Remove.Count) }
    if ($doUpdate) { $lines += $(if ($u.behind) { "UPDATE your folder: +{0} commit(s){1}" -f $u.behind, $(if (@($u.obstacles).Count) { ", $(@($u.obstacles).Count) file(s) in the way are backed up first" } else { '' }) } else { "UPDATE your folder to the commit this send creates (keeps it in step with GitHub)" }) }
    if ($ui.DryRun.IsChecked) { Write-Activity ("DRY RUN - would do:`n  " + ($lines -join "`n  ")) $Pal.Amber; $script:SyncAuto = $false; return }
    if (-not (Confirm-Action (($lines -join "`n`n") + "`n`nCode is never sent. Go?") 'Smart sync')) { $script:SyncAuto = $false; Set-SyncSteps @('done') @('cancelled'); return }
    $plan = @{ push = @($Push); pull = @($Pull); remove = @($Remove); update = $doUpdate; allowCodeMerge = $true }
    $pf = Join-Path $env:TEMP ("nis16_syncplan_{0}.json" -f [guid]::NewGuid().ToString('N').Substring(0, 8))
    [IO.File]::WriteAllText($pf, ($plan | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
    Set-SyncSteps @('done', $(if ($script:SyncGateOk) { 'skip' } else { 'done' }), $(if ($Push.Count) { 'run' } else { 'skip' }), $(if ($Pull.Count + $Remove.Count) { 'todo' } else { 'skip' }), $(if ($doUpdate) { 'todo' } else { 'skip' }))
    $ui.SyncHead.Text = 'Syncing...'; $ui.SyncSubHead.Text = 'Do not close the window - git is working (it can not be stopped half-way on purpose).'
    $ui.SyncGo.IsEnabled = $false; $ui.SyncCheck.IsEnabled = $false
    $ok = Start-StreamJob -Exe $py -ToolArgs @('tools\smart_sync.py', 'apply', '--plan', $pf) -Title 'GitHub smart sync' -NoStop -State @{ Plan = $pf; Push = $Push.Count; Pull = ($Pull.Count + $Remove.Count); Update = $doUpdate } -OnDone {
        param($text, $code, $st)
        Remove-Item $st.Plan -ErrorAction SilentlyContinue
        $ui.SyncGo.IsEnabled = $true; $ui.SyncCheck.IsEnabled = $true; $script:SyncAuto = $false; $script:SyncGateOk = $false
        $line = ($text -split "`r?`n" | Where-Object { $_ -match '^RESULT ' } | Select-Object -Last 1)
        $res = if ($line) { try { $line.Substring(7) | ConvertFrom-Json } catch { $null } } else { $null }
        if (-not $res) {
            $err = ($text -split "`r?`n" | Where-Object { $_ -match 'ERROR' } | Select-Object -Last 1)
            Set-SyncSteps @('done', 'done', 'fail') @('', '', 'stopped')
            Show-Toast 'Sync stopped' $(if ($err) { $err.Trim() } else { 'See the activity pane - nothing half-done was left behind.' }) ([string][char]0xE783) 'GradMain'
            Set-SyncDone 'Sync stopped' $(if ($err) { $err.Trim() } else { 'See the activity pane - nothing half-done was left behind' }) 'GradMain' ([string][char]0xE783)
            return
        }
        $upd = $res.updated
        $s5 = if (-not $st.Update) { 'skip' } elseif ($upd -and $upd.ok) { 'done' } else { 'fail' }
        Set-SyncSteps @('done', 'done', $(if ($st.Push) { 'done' } else { 'skip' }), $(if ($st.Pull) { 'done' } else { 'skip' }), $s5) @('', '', "$($res.pushed) sent", "$($res.pulled) received", $(if ($upd -and $upd.ok) { "+$($upd.changed) commit(s)" } elseif ($upd) { 'not updated' } else { '' }))
        $msg = "{0} sent, {1} received{2}" -f $res.pushed, $res.pulled, $(if ($upd -and $upd.ok) { ", folder +$($upd.changed) commit(s)" } elseif ($upd) { " - folder NOT updated: $($upd.why)" } else { '' })
        Show-Toast $(if ($upd -and -not $upd.ok) { 'Synced - folder not updated' } else { 'Smart sync done' }) $msg ([string][char]0xE895) $(if ($upd -and -not $upd.ok) { 'GradMain' } else { 'GradGood' })
        Update-Cells; Update-TrimCells
        $when = (Get-Date).ToString('h:mm tt').ToLower()
        if ($upd -and -not $upd.ok) { Set-SyncDone 'Synced - folder not updated' ("$msg  ($when)") 'GradMain' ([string][char]0xE7BA) }
        else { Set-SyncDone 'Sync done' ("$msg  ($when)") }
    }
    if (-not $ok) { $ui.SyncGo.IsEnabled = $true; $ui.SyncCheck.IsEnabled = $true }
}
$ui.SyncCheck.Add_Click({ $script:SyncGateOk = $false; Start-SyncCheck })
$ui.SyncGo.Add_Click({
    $script:SyncAuto = $true; $script:SyncGateOk = $false
    # a fresh plan unless the shown one is under 2 minutes old (keeps the user's ticks)
    if ($script:Sync -and $script:SyncChecked -and ((Get-Date) - $script:SyncChecked).TotalMinutes -lt 2) { Continue-SmartSync } else { Start-SyncCheck -Continue }
})
$ui.SyncGateSkip.Add_Click({ $script:SyncGateOk = $true; $ui.SyncGate.Visibility = 'Collapsed'; Continue-SmartSync })
$ui.SyncGateAna.Add_Click({
    $cells = @(Get-SyncGateCells); if (-not $cells.Count) { return }
    if (-not (Confirm-Action ("Analyse + verify {0} run(s) one after the other, then continue the sync?`n`n    {1}" -f $cells.Count, ((@($cells | ForEach-Object { $_ -replace '/', ' / ' })) -join "`n    ")) 'Analyse first')) { return }
    $script:AnaQueue.Clear(); $script:AnaQueueRaw = $null   # the Analyse page's DATA choice, not the last popup's
    foreach ($c in $cells) { $p = $c -split '/'; $script:AnaQueue.Enqueue([pscustomobject]@{ Attack = $p[0]; Topology = $p[1]; Location = $p[2]; Scenario = $p[3]; Text = ($p -join ' / ') }) }
    $script:SyncResume = $true; $ui.SyncGate.Visibility = 'Collapsed'
    Set-SyncSteps @('done', 'run') @('', "analysing $($cells.Count) run(s)...")
    Start-NextAnalysis
})
$ui.SyncSendOnly.Add_Click({ Start-SyncApply -Push (Get-SyncPicked 'Send') })
$ui.SyncRecvOnly.Add_Click({ Start-SyncApply -Pull (Get-SyncPicked 'Recv') -Remove (Get-SyncPicked 'Gone') })
$ui.SyncFoldOnly.Add_Click({ Start-SyncApply -Update $true })
$ui.SyncUpdate.Add_Click({ Update-SyncCounts })
foreach ($pair in @(@('SyncSendAll', 'Send', $true), @('SyncSendNone', 'Send', $false), @('SyncRecvAll', 'Recv', $true), @('SyncRecvNone', 'Recv', $false))) {
    $w = $pair[1]; $v = $pair[2]
    $ui[$pair[0]].Add_Click({
        if (-not $script:SyncTables) { return }
        $script:SyncBulk = $true   # one recount at the end, not one per row (282 rows = 80 000 updates)
        try { foreach ($r in $script:SyncTables[$w].Rows) { $r.Pick = $v } } finally { $script:SyncBulk = $false }
        Update-SyncCounts
    }.GetNewClosure())
}
$ui.SyncAbortMerge.Add_Click({
    $py = Get-Py; if (-not $py) { return }
    if (-not (Confirm-Action "Abort the unfinished merge?`n`nThe folder goes back to your last commit. Every changed file is copied to the backups folder first." 'Abort merge')) { return }
    [void](Start-StreamJob -Exe $py -ToolArgs @('tools\smart_sync.py', 'abort-merge') -Title 'Abort unfinished merge' -NoStop -OnDone {
        param($text, $code)
        if ($code -eq 0) { Set-SyncDone 'Unfinished merge aborted' 'Your folder is back on your last commit (changed files copied to Backups first)' }
        else { Set-SyncDone 'Abort failed' 'See the activity pane' 'GradMain' ([string][char]0xE783) }
    })
})
$ui.SyncBackups.Add_Click({
    $d = Join-Path $env:LOCALAPPDATA 'NIS16\sync_backup'; [void](New-Item -ItemType Directory -Force $d); Start-Process explorer.exe $d
})
$ui.SyncAdvanced2.Add_Click({
    # Deleting from / restoring to GitHub picks files one by one - push_data.py's
    # own interactive window, never with --yes.
    Start-Process powershell -ArgumentList @('-NoExit', '-Command', "Set-Location '$base'; Write-Host 'GitHub delete / restore - type: delete or restore, then the area (exports / analysis / logs / presets)' -ForegroundColor Cyan; `$a = Read-Host 'delete or restore'; `$r = Read-Host 'area'; python tools\push_data.py `$a --area `$r")
})
# No automatic check (user, oct. 18 2026): GitHub is only contacted when Check
# again or Smart sync is pressed. Opening the page just shows the last plan.

# ── time strip (user, oct. 21 2026: "put time and date when it was pushed or pulled") ──
# Local only - git's own history + reflogs and smart_sync's sync_state.json, never the
# network. "Last sent" = the newest data commit on GitHub signed by this laptop (any tool),
# "last received" = the newest folder update from GitHub or smart-sync file receive.
function Format-Ago([datetime]$T) {
    $m = ((Get-Date) - $T).TotalMinutes
    if ($m -lt 1) { return 'just now' } elseif ($m -lt 60) { return '{0} min ago' -f [int][math]::Floor($m) }
    elseif ($m -lt 1440) { return '{0} h {1} min ago' -f [int][math]::Floor($m / 60), [int]($m % 60) }
    else { return '{0} day(s) ago' -f [int][math]::Floor($m / 1440) }
}
function Get-RefTimes([string]$Ref, [string]$Pattern) {
    # newest reflog entry of $Ref whose message matches $Pattern -> @{ T; Msg }
    $lines = @(& git -C $base reflog show --date=unix --format='%gd|%gs' -n 300 $Ref 2>$null)
    foreach ($l in $lines) {
        if ($l -notmatch '@\{(\d+)\}\|(.*)$') { continue }
        $sec = [long]$Matches[1]; $msg = $Matches[2]   # copy first: the next -match overwrites $Matches
        if ($msg -match $Pattern) { return @{ T = [DateTimeOffset]::FromUnixTimeSeconds($sec).LocalDateTime; Msg = $msg } }
    }
    return $null
}
function Update-SyncTimes([switch]$AgoOnly) {
    if (-not $AgoOnly -or -not $script:SyncTimeData) {
        $tiles = @()
        try {
            $br = (& git -C $base rev-parse --abbrev-ref HEAD 2>$null | Select-Object -First 1)
            $tag = { param($s) $v = (([string]$s) -replace '[^A-Za-z0-9-]', '-').Trim('-'); if ($v) { $v } else { 'unknown' } }   # = push_data.tag()
            $me = (& $tag $env:COMPUTERNAME) + '_' + (& $tag $env:USERNAME)
            $hub = "refs/remotes/origin/$br"
            $log = @(& git -C $base log $hub --format='%ct|%s' -n 400 2>$null)
            $mine = $log | Where-Object { $_ -match ('from ' + [regex]::Escape($me) + '(\s|$)') } | Select-Object -First 1
            $sent = $null; if ($mine -match '^(\d+)\|(.*)$') { $sent = @{ T = [DateTimeOffset]::FromUnixTimeSeconds([long]$Matches[1]).LocalDateTime; Msg = $Matches[2] } }
            $recv = Get-RefTimes 'HEAD' "^(merge origin/|pull|reset: moving to origin/)"
            $state = $null; $sf = Join-Path $env:LOCALAPPDATA 'NIS16\sync_state.json'
            if (Test-Path $sf) { try { $state = (Get-Content -Raw -Encoding UTF8 $sf | ConvertFrom-Json).$br } catch { } }
            if ($state -and $state.lastRecv) {
                $t = [DateTimeOffset]::FromUnixTimeSeconds([long]$state.lastRecv.when).LocalDateTime
                if (-not $recv -or $t -gt $recv.T) { $recv = @{ T = $t; Msg = "smart sync received $($state.lastRecv.files) file(s)" } }
            }
            $code = Get-RefTimes $hub '^update by push'
            # the reflog only logs a fetch that brought something new; FETCH_HEAD is rewritten by every fetch
            $seen = Get-RefTimes $hub '^(fetch|pull|update by push)'
            $fh = (& git -C $base rev-parse --git-path FETCH_HEAD 2>$null | Select-Object -First 1)
            if ($fh -and -not [IO.Path]::IsPathRooted($fh)) { $fh = Join-Path $base $fh }
            if ($fh -and (Test-Path $fh)) {
                $t = (Get-Item $fh).LastWriteTime
                if (-not $seen -or $t -gt $seen.T) { $seen = @{ T = $t; Msg = 'git fetch (Check / Smart sync)' } }
            }
            $top = $log | Select-Object -First 1; $hubT = $null
            if ($top -match '^(\d+)\|(.*)$') { $hubT = @{ T = [DateTimeOffset]::FromUnixTimeSeconds([long]$Matches[1]).LocalDateTime; Msg = $Matches[2] } }
            $who = ''; if ($hubT -and $hubT.Msg -match 'from (\S+)') { $who = $Matches[1] -replace '\s*\[smart sync\]$', '' }
            $spec = @(
                @('Last sent (data)',        [char]0xE898, $Pal.Green, $sent, "Newest data commit on GitHub from this laptop ($me)"),
                @('Last received',           [char]0xE896, $Pal.Blue,  $recv, 'Your folder last updated from GitHub (or files received by Smart sync)'),
                @('Code pushed',             [char]0xE943, $Pal.Cyan,  $code, 'Last git push of code from this folder'),
                @('GitHub last changed',     [char]0xE753, $Pal.Amber, $hubT, $(if ($who) { "newest commit on $br, by $who (as of the last check)" } else { "newest commit on $br (as of the last check)" })),
                @('Last checked GitHub',     [char]0xE895, $Pal.Dim,   $seen, 'Last time this folder talked to GitHub (Check, sync, fetch or push)'))
            foreach ($s in $spec) {
                $tiles += [pscustomobject]@{ Name = $s[0]; Glyph = [string]$s[1]; Fg = (Get-Brush $s[2]); At = $(if ($s[3]) { $s[3].T } else { $null })
                                             When = $(if ($s[3]) { (Format-When $s[3].T) } else { 'never (on this laptop)' }); Ago = ''
                                             Tip = $s[4] + $(if ($s[3]) { "`n" + $s[3].T.ToString('ddd MMM d yyyy, h:mm:ss tt') + "`n" + $s[3].Msg } else { '' }) }
            }
        } catch { $tiles = @([pscustomobject]@{ Name = 'Sync times'; Glyph = [string][char]0xE783; Fg = (Get-Brush $Pal.Red); At = $null; When = 'could not read git history'; Ago = ''; Tip = $_.Exception.Message }) }
        $script:SyncTimeData = $tiles
    }
    foreach ($t in $script:SyncTimeData) { $t.Ago = $(if ($t.At) { Format-Ago $t.At } else { '' }) }
    $ui.SyncTimes.ItemsSource = $null; $ui.SyncTimes.ItemsSource = @($script:SyncTimeData)
}
$ui.NavSync.Add_Checked({ Update-SyncTimes })
# the "x min ago" lines tick once a minute while the page is open (no git, no network)
$syncClock = New-Object Windows.Threading.DispatcherTimer
$syncClock.Interval = [TimeSpan]::FromSeconds(60)
$syncClock.Add_Tick({ if ($ui.Pages.SelectedIndex -eq 8 -and $script:SyncTimeData) { Update-SyncTimes -AgoOnly } })
$syncClock.Start()

function Update-Logs {
    $root = Join-Path $base 'datasets\run_logs'
    $rows = @()
    if (Test-Path $root) {
        foreach ($f in Get-ChildItem $root -Recurse -Filter *.log -File | Where-Object { $_.FullName -notmatch '\\_archive\\' }) {
            $rows += [pscustomobject]@{ When = $f.LastWriteTime; WhenText = $f.LastWriteTime.ToString('MMM dd  hh:mm tt')
                                        Cell = ($f.Directory.FullName.Substring($root.Length).Trim('\') -replace '\\', ' / '); KB = [math]::Round($f.Length / 1KB); Path = $f.FullName }
        }
    }
    $ui.LogGrid.ItemsSource = @($rows | Sort-Object When -Descending)
}
$ui.LogRefresh.Add_Click({ Update-Logs })
$ui.LogGrid.Add_SelectionChanged({
    $r = $ui.LogGrid.SelectedItem; if (-not $r) { return }
    $doc = New-Object Windows.Documents.FlowDocument; $doc.PagePadding = '0'
    foreach ($line in ((Get-Content $r.Path -Raw -Encoding UTF8) -replace "\x1b\[[0-9;]*m", '' -split "`r?`n")) {
        $p = New-Object Windows.Documents.Paragraph; $p.Margin = '0'
        $run = New-Object Windows.Documents.Run $line; $run.Foreground = & $brush (Get-LineColor $line)
        [void]$p.Inlines.Add($run); [void]$doc.Blocks.Add($p)
    }
    $ui.LogView.Document = $doc
})
$ui.LogOpen.Add_Click({ $r = $ui.LogGrid.SelectedItem; if ($r) { Start-Process notepad $r.Path } })
Add-Type -AssemblyName Microsoft.VisualBasic
function Remove-ToRecycleBin([string]$Path) {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($Path, 'OnlyErrorDialogs', 'SendToRecycleBin')
}
$ui.LogDelete.Add_Click({
    $r = $ui.LogGrid.SelectedItem; if (-not $r) { return }
    if (Confirm-Action "Move this run log to the Recycle Bin?`n`n$($r.Cell)  $($r.WhenText)") { Remove-ToRecycleBin $r.Path; Update-Logs; $ui.LogView.Document.Blocks.Clear(); Set-Status 'Run log moved to the Recycle Bin.' $Pal.Amber }
})
$ui.DelArea.ItemsSource = @('exports', 'analysis', 'run_logs', 'PCAP'); $ui.DelArea.SelectedIndex = 0
$script:DelTable = $null
$ui.DelList.Add_Click({
    $root = Join-Path $base ('datasets\' + [string]$ui.DelArea.SelectedItem)
    $flt = ([string]$ui.DelFilter.Text).Trim()
    $dt = New-Object System.Data.DataTable
    [void]$dt.Columns.Add('Delete', [bool]); foreach ($c in 'File', 'When', 'KB', 'Path') { [void]$dt.Columns.Add($c, [string]) }
    if (Test-Path $root) {
        foreach ($f in Get-ChildItem $root -Recurse -File | Sort-Object LastWriteTime -Descending) {
            $rel = $f.FullName.Substring($root.Length).Trim('\')
            if ($flt -and $rel -notlike "*$flt*") { continue }
            [void]$dt.Rows.Add($false, $rel, $f.LastWriteTime.ToString('MMM dd  hh:mm tt'), [string][math]::Round($f.Length / 1KB), $f.FullName)
        }
    }
    $script:DelTable = $dt
    $ui.DelGrid.Columns.Clear()
    $chk = New-Object Windows.Controls.DataGridCheckBoxColumn; $chk.Header = 'delete'; $chk.Binding = New-Object Windows.Data.Binding 'Delete'; $chk.Width = 60
    $chk.ElementStyle = $win.FindResource('TickBox'); $chk.EditingElementStyle = $win.FindResource('TickBox'); $chk.MinWidth = 60   # check box, not the switch; never squeezed below the box
    [void]$ui.DelGrid.Columns.Add($chk)
    foreach ($c in @(@('file', 'File', 640), @('saved', 'When', 140), @('KB', 'KB', 70))) {
        $col = New-Object Windows.Controls.DataGridTextColumn; $col.Header = $c[0]; $col.Binding = New-Object Windows.Data.Binding $c[1]; $col.Width = $c[2]; $col.IsReadOnly = $true
        [void]$ui.DelGrid.Columns.Add($col)
    }
    $ui.DelGrid.ItemsSource = $dt.DefaultView
    Set-Status ("{0} file(s) listed" -f $dt.Rows.Count)
})
$ui.DelGo.Add_Click({
    [void]$ui.DelGrid.CommitEdit(); [void]$ui.DelGrid.CommitEdit()
    if (-not $script:DelTable) { return }
    $pick = @($script:DelTable.Rows | Where-Object { $_.Delete })
    if (-not $pick.Count) { [void][Windows.MessageBox]::Show('Tick the files to delete first.', 'Delete'); return }
    if (Confirm-Action ("Move {0} file(s) to the Recycle Bin? (this laptop only - GitHub is untouched)" -f $pick.Count)) {
        foreach ($r in $pick) { try { Remove-ToRecycleBin ([string]$r.Path); Write-Activity ("  deleted  " + $r.File) $Pal.Amber } catch { Write-Activity ("  could not delete " + $r.File + ": " + $_.Exception.Message) $Pal.Red } }
        $ui.DelList.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    }
})
$open = { param([string]$Rel) $p = Join-Path $base $Rel; if (Test-Path $p) { Start-Process explorer $p } else { Set-Status "Not found: $Rel" $Pal.Amber } }
$ui.FExports.Add_Click({ & $open 'datasets\exports' })
$ui.FAnalysis.Add_Click({ & $open 'datasets\analysis' })
$ui.FRunLogs.Add_Click({ & $open 'datasets\run_logs' })
$ui.FPcap.Add_Click({ & $open 'datasets\PCAP' })
$ui.FPresets.Add_Click({ & $open 'presets' })
$ui.DVerif.Add_Click({ & $open 'docs\dataset-verification.md' })
$ui.DChecklist.Add_Click({ & $open 'docs\deviations-limitations\THESIS-UPDATE-CHECKLIST.md' })
$ui.DStart.Add_Click({ & $open 'docs\operations\2026-09-14_START-HERE.md' })

# ── WIRESHARK & SNIFFER (phase 4) ─────────────────────────────────────────────
function Update-Pcaps {
    $root = Join-Path $base 'datasets\PCAP'
    $rows = @()
    if (Test-Path $root) {
        foreach ($f in Get-ChildItem $root -Recurse -File -Include *.pcap, *.pcapng | Where-Object { $_.Name -notmatch '_fixed\.' }) {
            $rows += [pscustomobject]@{ When = $f.LastWriteTime; WhenText = $f.LastWriteTime.ToString('MMM dd  hh:mm tt'); Name = $f.Name
                                        MB = [math]::Round($f.Length / 1MB, 1); Path = $f.FullName }
        }
    }
    $ui.PcapGrid.ItemsSource = @($rows | Sort-Object When -Descending)
}
$ui.PcapRefresh.Add_Click({ Update-Pcaps })
function Get-SelectedPcap { $r = $ui.PcapGrid.SelectedItem; if (-not $r) { [void][Windows.MessageBox]::Show('Select a capture first.', 'Wireshark') }; return $r }
$ui.PcapCheck.Add_Click({ $r = Get-SelectedPcap; $py = Get-Py; if ($r -and $py) { [void](Start-StreamJob -Exe $py -ToolArgs @('tools\check_pcap.py', $r.Path) -Title "Check $($r.Name)") } })
$ui.PcapRetry.Add_Click({ $py = Get-Py; if ($py) { [void](Start-StreamJob -Exe $py -ToolArgs @('tools\pcap_retry.py', '--all') -Title 'MAC retry rate (all captures)') } })
$VIEWS = [ordered]@{
    'Overview - all boards'                   = 'overview'
    'One board'                               = 'one'
    'All boards side by side (I/O lines)'     = 'side'
    'Mesh data frames only'                   = 'data'
    'Real MAC retransmissions (Retry bit)'    = 'retry'
    'Topology - joins, re-joins, leaves'      = 'topo'
    'Weak links (below -80 dBm)'              = 'weak'
    'BLACKHOLE proof (attacker -> parent)'    = 'blackhole'
    'WORMHOLE check (B sends vs A uplink)'    = 'wormhole'
}
$ui.ViewPick.ItemsSource = @($VIEWS.Keys); $ui.ViewPick.SelectedIndex = 0
$script:PcapMap = $null
function Update-ViewBoards {
    $k = $VIEWS[[string]$ui.ViewPick.SelectedItem]
    $one = $k -in @('one', 'blackhole', 'wormhole'); $two = $k -in @('blackhole', 'wormhole')
    foreach ($n in 'ViewBoard', 'ViewBoardLbl') { $ui[$n].Visibility = $(if ($one) { 'Visible' } else { 'Collapsed' }) }
    foreach ($n in 'ViewBoard2', 'ViewBoard2Lbl') { $ui[$n].Visibility = $(if ($two) { 'Visible' } else { 'Collapsed' }) }
    $ui.ViewBoardLbl.Text = switch ($k) { 'blackhole' { 'ATTACKER' } 'wormhole' { 'NODE A (re-injects)' } default { 'BOARD' } }
    $ui.ViewBoard2Lbl.Text = switch ($k) { 'blackhole' { "ATTACKER'S PARENT" } default { 'NODE B (tunnels its probes away)' } }
}
$ui.ViewPick.Add_SelectionChanged({ Update-ViewBoards })
$ui.PcapLoad.Add_Click({
    $r = Get-SelectedPcap; if (-not $r) { return }
    Set-Status "Reading the boards in $($r.Name) ..." $Pal.Amber
    # The CLI's own reader (run_wizard.ps1 Get-PcapMeshMap = check_pcap.py --map-json).
    $map = $null
    try { $map = Get-PcapMeshMap -Path $r.Path } catch { }
    $script:PcapMap = $map; $script:PcapPath = $r.Path
    if (-not $map) { $ui.PcapBoards.Text = 'No mesh boards found in this capture - only "Overview" opens it (unfiltered).'; Set-Status 'No mesh boards found.' $Pal.Amber; return }
    $labels = Get-MemberBoardLabels
    $names = @($map.nodes | ForEach-Object {
        $l = $labels[(Get-ShortMac $_.sta)]
        '{0}{1}' -f $_.sta, $(if ($l) { "   $l" } elseif ($map.root_guess -eq $_.sta) { '   (root?)' } else { '' }) })
    foreach ($cb in 'ViewBoard', 'ViewBoard2') { $ui[$cb].ItemsSource = $names; $ui[$cb].SelectedIndex = 0 }
    $atk = Get-ConfiguredAttackerMac
    $ai = [array]::IndexOf(@($map.nodes | ForEach-Object sta), $atk)
    if ($ai -ge 0) { $ui.ViewBoard.SelectedIndex = $ai }
    $ui.PcapBoards.Text = ("{0} board(s) heard: {1}" -f @($map.nodes).Count, (($names | ForEach-Object { ($_ -split '\s{3}')[0] }) -join ', '))
    Set-Status "Boards read from $($r.Name)." $Pal.Green
    Update-ViewBoards
})
$ui.ViewOpen.Add_Click({
    $r = Get-SelectedPcap; if (-not $r) { return }
    $k = $VIEWS[[string]$ui.ViewPick.SelectedItem]
    if ($script:PcapPath -ne $r.Path -or -not $script:PcapMap) {
        if ($k -eq 'overview') { Open-InWireshark -Path $r.Path -IoLines (Get-GenericIoLines) | Out-Null; Set-Status 'Opened in Wireshark (unfiltered overview).'; return }
        [void][Windows.MessageBox]::Show('Press "Read the boards in this capture" first.', 'Wireshark'); return
    }
    $map = $script:PcapMap; $nodes = @($map.nodes)
    $labels = Get-MemberBoardLabels; $owners = Get-MemberBoardOwners; $attacker = Get-ConfiguredAttackerMac
    $n1 = if ($ui.ViewBoard.SelectedIndex -ge 0) { $nodes[$ui.ViewBoard.SelectedIndex] }
    $n2 = if ($ui.ViewBoard2.SelectedIndex -ge 0) { $nodes[$ui.ViewBoard2.SelectedIndex] }
    $filter = $null; $io = @()
    switch ($k) {
        'one' {
            $v = Get-PcapScopedView -View 'overview' -Map $map -Scope @($n1) -Who ("board " + $n1.sta) -Labels $labels -Owners $owners -Attacker $attacker -Path $r.Path
            $filter = "wlan.addr == $($n1.sta) || wlan.addr == $($n1.softap)"; $io = $v.Io
        }
        'blackhole' {
            # Same filters as the CLI: data frames attacker -> its parent's SoftAP.
            $parentAp = $n2.softap
            $filter = "wlan.fc.type == 2 && wlan.ta == $($n1.sta) && wlan.ra == $parentAp"
            $io = @(@{ Name = "Attacker [$($n1.sta)] -> parent [$parentAp] (forwarded)"; Filter = $filter },
                    @{ Name = "Into attacker [$($n1.sta)] (still receiving)"; Filter = "wlan.fc.type == 2 && wlan.ra == $($n1.softap)" },
                    @{ Name = "Attacker [$($n1.sta)] - all traffic"; Filter = "wlan.addr == $($n1.sta) || wlan.addr == $($n1.softap)" })
        }
        'wormhole' {
            $meshSet = 'wlan.addr in {' + (($nodes | ForEach-Object { $_.sta, $_.softap }) -join ', ') + '}'
            $aUp = @($n1.parents)
            $aFilter = if ($aUp.Count -gt 0) { "wlan.fc.type == 2 && wlan.ta == $($n1.sta) && wlan.ra == $($aUp[0].softap)" } else { "wlan.fc.type == 2 && wlan.ta == $($n1.sta)" }
            $filter = "wlan.fc.type_subtype in {0x00, 0x02} && $meshSet"
            $io = @(@{ Name = "B [$($n2.sta)] direct sends"; Filter = "wlan.fc.type == 2 && wlan.ta == $($n2.sta)" },
                    @{ Name = "A [$($n1.sta)] -> its parent"; Filter = $aFilter },
                    @{ Name = 'Joins / re-joins'; Filter = $filter })
        }
        default {
            $v = Get-PcapScopedView -View $k -Map $map -Scope $nodes -All -Who 'All boards' -Labels $labels -Owners $owners -Attacker $attacker -Path $r.Path
            $filter = $v.Filter; $io = $v.Io
        }
    }
    if ($script:NoWireshark) { Write-Activity ("filter: " + $filter); return }
    $ok = Open-InWireshark -Path $r.Path -Filter $filter -IoLines $io
    Write-Activity ("> Wireshark: {0}`n  filter: {1}" -f [string]$ui.ViewPick.SelectedItem, $filter)
    Set-Status $(if ($ok -ne $false) { 'Opened in Wireshark.' } else { 'Wireshark not found - the filter is in the activity pane.' })
})
foreach ($pair in @(@('SnAttack', @('baseline', 'blackhole', 'wormhole')), @('SnTopology', @('linear', 'tree', 'star', 'partial')),
                    @('SnLocation', @('G402', 'DLSU_Library', 'Yuchengco', 'home')), @('SnScenario', @('stationary', 'burst', 'highload', 'jitter', 'mobility', 'powercycle')))) {
    $ui[$pair[0]].ItemsSource = $pair[1]; $ui[$pair[0]].SelectedIndex = 0
}
$ui.SnFlash.Add_Click({
    $p = if ($ui.SnPort.SelectedItem) { $ui.SnPort.SelectedItem.Port } else { '' }
    if (-not $p) { [void][Windows.MessageBox]::Show('Pick the sniffer board''s port.', 'Sniffer'); return }
    Start-WizardTool @('-Tool', 'flashsniffer', '-ToolPort', $p) "Flash the sniffer firmware on $p"
})
$ui.SnMac.Add_Click({ Start-ConsoleWindow -Script (Join-Path $base 'run_wizard.ps1') -ScriptArgs @('-Tool', 'macsniffer') -Title 'MacBook sniffer test' })
function Set-SnifferFromRun {
    # the sniffer records the run loaded on Live run: same attack / topology /
    # location / scenario / repeat -> PCAP\<attack>\<topo>\<loc>\<scn>\<topo>-<attack>-<scn>-<loc>_r<N>_<time>.pcap
    $R = $script:Run; if (-not $R -or -not $R.Plan) { return }
    if ($script:Stream -and (Test-IsSnifferStream)) { return }   # never rename a recording in progress
    $c = $R.Plan
    $ui.SnAttack.SelectedItem = $(if ($c.Attack -eq 'none') { 'baseline' } else { [string]$c.Attack })
    $ui.SnTopology.SelectedItem = $(if ([string]$c.Topology -match '^partial') { 'partial' } else { [string]$c.Topology })
    $ui.SnLocation.SelectedItem = [string]$c.Location
    $ui.SnScenario.SelectedItem = [string]$c.Scenario
    $ui.SnRepeat.Text = [string]$ui.RunRepeat.Text
    $ui.SnTest.IsChecked = $false
}
$ui.SnStart.Add_Click({
    $py = Get-Py; $p = if ($ui.SnPort.SelectedItem) { $ui.SnPort.SelectedItem.Port } else { '' }; if (-not $py) { return }
    if (-not $p) { [void][Windows.MessageBox]::Show('Pick the sniffer board''s port.', 'Sniffer'); return }
    # File name: the CLI's own naming, so the MAC-retry report can pair it with its run.
    if ($ui.SnTest.IsChecked) {
        $dir = Join-Path $base 'datasets\PCAP\standalone'; New-Item -ItemType Directory -Force $dir | Out-Null
        $out = Get-StampedPath -Dir $dir -Head 'esp32_sniffer' -Ext '.pcap'
    } else {
        $rep = 1; [void][int]::TryParse($ui.SnRepeat.Text, [ref]$rep)
        $atk = [string]$ui.SnAttack.SelectedItem; if ($atk -eq 'baseline') { $atk = 'none' }
        $dirs = Get-RunDirs -Attack $atk -Topology ([string]$ui.SnTopology.SelectedItem) -Location ([string]$ui.SnLocation.SelectedItem) -Scenario ([string]$ui.SnScenario.SelectedItem)
        $out = Get-SnifferPcapPath -AttackDir $dirs.AttackDir -TopoDir $dirs.TopoDir -Location ([string]$ui.SnLocation.SelectedItem) -Scenario ([string]$ui.SnScenario.SelectedItem) -RepeatNum $rep
        if (-not (Confirm-Action ("Record this runs PCAP as:`n`n{0}`n`nin {1}`n`nWrong attack / topology / location / scenario / repeat? Press No and fix the boxes (they copy the run loaded on Live run)." -f (Split-Path $out -Leaf), (Split-Path $out -Parent)) 'Sniffer file')) { return }
        New-Item -ItemType Directory -Force (Split-Path $out -Parent) | Out-Null
    }
    $script:SnStop = [IO.Path]::GetTempFileName(); Remove-Item $script:SnStop
    # pause = this file exists (sniff.py --pause-file): the port is still read, nothing saved
    $script:SnPauseFile = [IO.Path]::GetTempFileName(); Remove-Item $script:SnPauseFile
    if ($ui.SnStartPaused.IsChecked) { Set-Content -Path $script:SnPauseFile -Value 'pause' }
    $a = @('tools\sniff.py', '--port', $p, '--out', $out, '--stop-file', $script:SnStop, '--pause-file', $script:SnPauseFile, '--no-stop-on-enter')
    if ($ui.SnLive.IsChecked) { $a += '--live' }
    if (Start-StreamJob -Exe $py -ToolArgs $a -Title "Sniffer recording on $p -> $(Split-Path $out -Leaf)" -OnDone { $ui.SnStop.IsEnabled = $false; $ui.SnPause.IsEnabled = $false; $ui.SnStart.IsEnabled = $true; Remove-Item $script:SnPauseFile -ErrorAction SilentlyContinue; Update-Pcaps }) {
        $ui.SnStop.IsEnabled = $true; $ui.SnStart.IsEnabled = $false; $ui.SnPause.IsEnabled = $true
        Update-SnPause
    }
})
function Update-SnPause {
    $on = $script:SnPauseFile -and (Test-Path $script:SnPauseFile)
    $ui.SnPause.Content = $(if ($on) { "$([char]0x25B6)  Resume" } else { "$([char]0x2016)  Pause" })
    $ui.SnPause.Style = $win.FindResource($(if ($on) { 'Primary' } else { 'Cool' }))
    if ($on) { Set-Status ("Sniffer PAUSED at {0} - the board is still read, nothing is saved. Press Resume." -f (Get-Date).ToString('h:mm:ss tt')) $Pal.Amber }
    else { Set-Status 'Sniffer RECORDING.' $Pal.Green }
}
$ui.SnPause.Add_Click({
    if (-not $script:SnPauseFile) { return }
    if (Test-Path $script:SnPauseFile) { Remove-Item $script:SnPauseFile; Write-Activity '  sniffer: RESUMED - saving frames again' $Pal.Green }
    else { Set-Content -Path $script:SnPauseFile -Value 'pause'; Write-Activity '  sniffer: PAUSED - frames are heard but not saved (the gap is logged in the .json)' $Pal.Amber }
    Update-SnPause
})
$ui.SnStop.Add_Click({ if ($script:SnStop) { Set-Content -Path $script:SnStop -Value 'stop'; Write-Activity '  stopping the recording (closing the file cleanly)...' $Pal.Amber } })

# ── LIVE RUN (oct. 17 2026): the whole capture inside the GUI ─────────────────
# User: "no need for me to open the CLI". Same steps, same order and the SAME
# run.ps1 calls as run_wizard.ps1's capture flow - the plan is built by the
# wizard's own New-RunParams: compile every variant (run.ps1 -BuildOnly) ->
# park the old root -> each board: run.ps1 wipe + flash + monitor + export,
# children first, root last -> summary. Only the console differs: every step
# is a hidden process writing to a file this page tails, and the monitor is
# tools\gui_monitor.py (run.ps1 -GuiMonitor), so START / START_ANYWAY / "done
# with this board" are buttons. The processes do not depend on this window: if
# the GUI closes, a running export still finishes (BSOD rule: never cut one).
$script:Run = $null
# what each step runs - the self-test points these at stand-ins (no board)
$script:RunScript  = Join-Path $base 'run.ps1'
$script:RunEsptool = 'esptool.py'
$script:RunCtlRoot = Join-Path $env:TEMP 'nis16_gui_run'
$script:RunLines = 0
function Write-RunConsole([string]$Text, [string]$Hex) {
    foreach ($line in ($Text -split "`n")) {
        [void]$ui.RunConsole.Document.Blocks.Add((New-ConsoleParagraph $line $Hex))
        $script:RunLines++
    }
    # an 11-minute root monitor prints thousands of lines: keep the pane light
    # (everything still goes to the run log). 400, not 1500 (oct. 18 2026): a
    # RichTextBox re-lays out the whole pane per line - 12 ms a line at 1500
    # vs ~3 ms at 400 - and that starved the phase countdown (it stuttered).
    while ($script:RunLines -gt 400) { $ui.RunConsole.Document.Blocks.Remove($ui.RunConsole.Document.Blocks.FirstBlock); $script:RunLines-- }
    if ($ui.RunFollow.IsChecked) { $ui.RunConsole.ScrollToEnd() }
    if ($script:Run -and $script:Run.LogPath) { try { [IO.File]::AppendAllText($script:Run.LogPath, $Text + "`r`n") } catch { } }
}
$ui.RunConsoleClear.Add_Click({ $ui.RunConsole.Document.Blocks.Clear(); $script:RunLines = 0 })

function Get-RunRoleLook([string]$Kind, [string]$Role) {
    if ($Role -eq 'root') { return @{ Text = 'ROOT'; Hex = $Pal.Amber; Glyph = [string][char]0xE80F } }
    switch ($Kind) {
        'attacker' { @{ Text = 'blackhole attacker'; Hex = $Pal.Red; Glyph = [string][char]0xE7BA } }
        'victim'   { @{ Text = 'blackhole victim'; Hex = $Pal.Blue; Glyph = [string][char]0xE7F4 } }
        'A'        { @{ Text = 'tunnel end'; Hex = $Pal.Purple; Glyph = [string][char]0xE71B } }
        'B'        { @{ Text = 'tunnel end'; Hex = $Pal.Purple; Glyph = [string][char]0xE71B } }
        'control'  { @{ Text = 'control'; Hex = $Pal.Blue; Glyph = [string][char]0xE7F4 } }
        default    { @{ Text = 'child'; Hex = $Pal.Blue; Glyph = [string][char]0xE7F4 } }
    }
}
$script:RunStepLook = @{
    waiting   = @{ Dot = $Pal.Line;   Bg = $Pal.Card;  Edge = $Pal.Line;   Text = 'waiting' }
    running   = @{ Dot = $Pal.Cyan;   Bg = '#1E2A44';  Edge = $Pal.Cyan;   Text = 'running' }
    attention = @{ Dot = $Pal.Amber;  Bg = '#3A2E14';  Edge = $Pal.Amber;  Text = 'needs you' }
    ok        = @{ Dot = $Pal.Green;  Bg = $Pal.Card;  Edge = '#1F5E4A';   Text = 'done' }
    skipped   = @{ Dot = $Pal.Faint;  Bg = $Pal.Card;  Edge = $Pal.Line;   Text = 'skipped' }
    failed    = @{ Dot = $Pal.Red;    Bg = '#3A1E2C';  Edge = $Pal.Red;    Text = 'FAILED' }
}
function Update-RunSteps {
    $R = $script:Run
    if (-not $R) { $ui.RunSteps.ItemsSource = $null; return }
    $ui.RunSteps.ItemsSource = @($R.Steps | ForEach-Object {
        $lk = $script:RunStepLook[$_.State]
        [pscustomobject]@{ Index = [array]::IndexOf(@($R.Steps), $_); Title = $_.Title; Sub = $_.Sub; Glyph = $_.Glyph; Tip = $_.Tip
                           State = $(if ($_.Note) { $_.Note } else { $lk.Text })
                           Dot = (& $brush $(if ($_.State -eq 'waiting' -and $_.Tone) { $_.Tone } else { $lk.Dot })); Bg = (& $brush $lk.Bg); Edge = (& $brush $lk.Edge) } })
    $i = [array]::IndexOf(@($R.Steps), $R.Current)
    $ui.RunStepCount.Text = if ($i -ge 0) { '{0}/{1}' -f ($i + 1), $R.Steps.Count } else { '-' }
}
function Set-RunState([string]$Text, [string]$Hex = '#5B21B6') {
    $ui.RunState.Text = $Text; $ui.RunState.Foreground = & $brush $Hex
}
function Set-RunNow([string]$Title, [string]$Text = '', [string]$Hex = $Pal.Cyan, [string]$Glyph = [string][char]0xE945) {
    $ui.RunNow.Visibility = 'Visible'
    $ui.RunNowTitle.Text = $Title; $ui.RunNowText.Text = $Text
    $ui.RunNowIcon.Text = $Glyph; $ui.RunNowIcon.Foreground = & $brush $Hex
    $ui.RunNow.BorderBrush = & $brush $Hex
}
function Set-RunButtons([string]$Next = '', [string]$Cont = '', [bool]$Abort = $true, [bool]$SkipBox = $false) {
    $ui.RunAgain.Visibility = 'Collapsed'; $ui.RunCleanFix.Visibility = 'Collapsed'
    $ui.RunNext.Visibility = $(if ($Next) { 'Visible' } else { 'Collapsed' }); if ($Next) { $ui.RunNext.Content = $Next }
    $ui.RunContinue.Visibility = $(if ($Cont) { 'Visible' } else { 'Collapsed' }); if ($Cont) { $ui.RunContinue.Content = $Cont }
    $ui.RunAbort.Visibility = $(if ($Abort) { 'Visible' } else { 'Collapsed' })
    $ui.RunSkipExport.Visibility = $(if ($SkipBox) { 'Visible' } else { 'Collapsed' })
}

# ── the plan (what the wizard's confirm table shows) ─────────────────────────
function New-RunPlan($P) {
    # $P = a preset row from the Run-a-capture grid (its ports already checked by MAC)
    $cfg = $P.Cfg
    $attack = [string]$cfg.attack; if ($attack -eq 'baseline') { $attack = 'none' }
    $topology = [string]$cfg.topology
    $scenario = ConvertTo-Scenario $(if ($cfg.PSObject.Properties['scenario']) { [string]$cfg.scenario })
    $location = [string]$cfg.location
    $full = @((ConvertTo-Roster -Cfg $cfg).Roster)
    $local = @($full | Where-Object { $_.Port })
    $remote = @($full | Where-Object { -not $_.Port -and $_.Role -ne 'root' })
    $notes = @(); $stop = @()
    if (-not $local.Count) { $stop += 'No board of this preset has a port on this laptop.' }
    $tg = @($full | Where-Object ScenarioTarget) | Select-Object -First 1
    if ((Test-ScenarioNeedsTarget $scenario) -and -not $tg) { $notes += "No board is marked as the $scenario TARGET - fine only if it is flashed on another laptop." }
    if ($scenario -eq 'burst' -and $tg -and -not (Test-BurstEligible $tg)) { $stop += "The burst TARGET is $($tg.Label), the $($tg.Kind) - that firmware has no burst code, so nothing would burst. Edit the preset and tick a victim/control board." }
    if ($scenario -eq 'burst' -and $tg) { $notes += "Burst sender: $($tg.Label)$(if (-not $tg.Port) { ' (on another laptop - not your job)' })." }
    if ($scenario -in @('mobility', 'powercycle') -and $tg) {
        $notes += ("{0}: {1} must be {2} ONCE during the run - this page reminds you when." -f $scenario, $tg.Label, $(if ($scenario -eq 'mobility') { 'moved to its second spot' } else { 'unplugged ~10 s and plugged back in' }))
    }
    $attMac = ''
    if ($attack -eq 'blackhole') {
        $att = $full | Where-Object { $_.Kind -eq 'attacker' } | Select-Object -First 1
        if ($att) {
            $liveMac = if ($att.Port -and $script:Live.Contains([string]$att.Port)) { [string]$script:Live[[string]$att.Port].Mac } else { '' }
            $attMac = @($liveMac, [string]$att.Mac) | Where-Object { $_ -match '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$' } | Select-Object -First 1
        }
        if ($attMac) { $notes += "Attacker for this run: $attMac - built into every blackhole board flashed here." }
        elseif ($topology -eq 'star') { $notes += "WARNING: the attacker's MAC is unknown - in STAR + blackhole the victims join ONLY the board in mesh_config.h ($(Get-ConfiguredAttackerMac)). Read the MACs first." }
    }
    if ($attack -eq 'wormhole') {
        $ends = @($local | Where-Object { $_.Kind -in @('A', 'B') })
        if ($ends.Count -eq 2) { $notes += 'Wormhole: the two tunnel boards pick A/B themselves. If the jumpers were touched, run Boards > UART cable test first. The root holds Phase 0 until the UART works both ways.' }
        elseif ($ends.Count -eq 1) { $notes += "Only ONE tunnel end ($($ends[0].Label)) is on this laptop - its cable partner must be wired to it." }
        if ($topology -eq 'star') {
            # D-28: built one hop down - root -> end A (hub) -> every other board - so B is deeper than A
            $hub = $full | Where-Object { $_.Kind -eq 'A' } | Select-Object -First 1
            if ($hub) {
                $liveMac = if ($hub.Port -and $script:Live.Contains([string]$hub.Port)) { [string]$script:Live[[string]$hub.Port].Mac } else { '' }
                $attMac = @($liveMac, [string]$hub.Mac) | Where-Object { $_ -match '^([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}$' } | Select-Object -First 1
            }
            if ($attMac) { $notes += "STAR + wormhole: end A ($($hub.Label), $attMac) is the star's HUB - B and every control join ONLY it, so B sits one hop deeper and the tunnel skips that hop (D-28). Power A before the others." }
            # end A on ANOTHER laptop has no MAC in this preset (oct. 19 2026, a teammate flashing
            # only the controls): ask for it instead of blocking - gui\StarHub.ps1
            if (-not $attMac) { $attMac = Read-StarHubMac ([string]$P.File) $(if ($hub) { [string]$hub.Label } else { 'end A' }) }
            if ($attMac) { $notes += "STAR + wormhole: the star's HUB is end A $attMac (typed in - it is on another laptop). Every board flashed here joins ONLY it (D-28)." }
            else { $stop += 'STAR + wormhole: end A has no known MAC, so B and the controls cannot be told which board is the hub (D-28). Load the preset again and type end A''s MAC (ask the laptop that flashes A), or set it in the preset.' }
        }
    }
    if (-not @($local | Where-Object Role -eq 'root').Count -and $local.Count) {
        # oct. 18 2026 (user): the usual setup keeps the root in its OWN preset on THIS
        # laptop (children preset first, root preset last). The old note assumed another
        # laptop and said to start the root FIRST - the opposite of the right order.
        $notes += (Get-RootElsewhereNote $P $attack $topology $location $scenario @($local).Count)
    }
    $ports = @($local | ForEach-Object Port)
    if (@($ports | Group-Object | Where-Object Count -gt 1).Count) { $notes += 'Some boards share a port: the run pauses between them so you can swap the boards.' }
    return [pscustomobject]@{ Preset = $P; Attack = $attack; Topology = $topology; Scenario = $scenario; Location = $location
                              Full = $full; Local = $local; Remote = $remote; Notes = $notes; Stop = $stop; AttackerMac = $attMac; Target = $tg }
}

function Open-RunPage($P) {
    if ($script:Run -and $script:Run.Active) { Show-Page 7; [void][Windows.MessageBox]::Show('A run is already going on the Live run page.', 'Live run'); return }
    $keepWatches = @(Get-AliveWatches)    # gui\RunSafety.ps1: the new run takes over the old run's crash watches
    $plan = New-RunPlan $P
    $script:Run = [pscustomobject]@{ Plan = $plan; Steps = (New-Object System.Collections.ArrayList); Current = $null; Active = $false
                                     Proc = $null; Out = ''; Err = ''; PosO = [long]0; PosE = [long]0; BufO = ''; BufE = ''; Ctl = ''
                                     Started = $null; LogPath = ''; Parked = $false; Used = @{}; Built = $false; GoAfterBuild = $false
                                     BuildQueue = $null; Wait = $null; Dash = $null; Phase = 'setup'; Alarm = $null; StopAfterFlash = $false; AutoAt = $null
                                     Builds = $null; BuildEntry = $null; Failed = $null; Picked = $null; Skipped = 0 }
    if ($keepWatches.Count) { $script:Run | Add-Member -NotePropertyName Bg -NotePropertyValue (New-Object System.Collections.ArrayList) -Force; foreach ($w in $keepWatches) { [void]$script:Run.Bg.Add($w) } }
    $c = $plan
    $ui.RunTitle.Text = '{0}  /  {1}  /  {2}  /  {3}' -f $(if ($c.Attack -eq 'none') { 'baseline' } else { $c.Attack }), $c.Topology, $c.Location, $c.Scenario
    $ui.RunSub.Text = '{0}  -  {1} board(s) on this laptop{2}  -  {3}' -f $P.File, $c.Local.Count,
        $(if ($c.Remote.Count) { ", $($c.Remote.Count) on other laptops" } else { '' }), $(if ($P.Owner) { "owner $($P.Owner)" } else { '' })
    $ui.RunRepeat.Text = [string]$(if ($P.Repeat) { $P.Repeat } else { 1 })
    Set-SnifferFromRun
    $want = 0; try { $want = [int]$P.Cfg.expectedChildren } catch { }
    $localKids = @($c.Local | Where-Object Role -ne 'root').Count
    $ui.RunRemote.Text = [string][Math]::Max($c.Remote.Count, $want - $localKids)
    $rootHere = [bool]@($c.Local | Where-Object Role -eq 'root').Count
    $ui.RunRemote.IsEnabled = $rootHere
    $ui.RunNotes.Text = (@($c.Stop | ForEach-Object { "STOP: $_" }) + $c.Notes) -join "`n"
    $ui.RunNotes.Foreground = & $brush $(if ($c.Stop.Count) { $Pal.Red } else { $Pal.Amber })
    $ui.RunSetup.IsEnabled = $true; $ui.RunBuild.IsEnabled = -not $c.Stop.Count; $ui.RunGo.IsEnabled = -not $c.Stop.Count
    $ui.RunNow.Visibility = 'Collapsed'
    Reset-RootDash
    if (-not $rootHere) {
        $ui.RunPhase.Text = 'root is on another laptop'
        $ui.RunGate.Text = 'START is pressed on the ROOT''s laptop, on its Live run page, once it shows READY. Your children just need to be flashed and powered - the root waits for them.'
        $ui.RunKids.Text = '-'
    }
    # the steps, exactly the wizard's order
    $R = $script:Run
    [void]$R.Steps.Add([pscustomobject]@{ Kind = 'build'; Title = 'Compile the firmware'; Sub = 'every board''s variant, no board touched'; Glyph = [string][char]0xE90F; State = 'waiting'; Note = ''; Tip = ''; Tone = $Pal.Cyan; Plan = $null })
    $rootB = @($c.Local | Where-Object Role -eq 'root')
    if ($rootB.Count -and @($c.Local | Where-Object Role -ne 'root').Count) {
        [void]$R.Steps.Add([pscustomobject]@{ Kind = 'park'; Title = 'Park the old root'; Sub = "$($rootB[0].Label) on $($rootB[0].Port): its old firmware would stop the new children"; Glyph = [string][char]0xE769; State = 'waiting'; Note = ''; Tip = ''; Tone = $Pal.Amber; Plan = $null })
    }
    foreach ($b in $c.Local) {
        $lk = Get-RunRoleLook $b.Kind $b.Role
        [void]$R.Steps.Add([pscustomobject]@{ Kind = 'board'; Title = ('{0}  -  {1}' -f $b.Label, $lk.Text); Sub = ('{0}   {1}' -f $b.Port, $(if ($b.Mac) { Get-ShortMac $b.Mac } else { 'MAC ?' }))
                                               Glyph = $lk.Glyph; State = 'waiting'; Note = ''; Tip = [string]$b.Display; Tone = $lk.Hex; Board = $b; Plan = $null })
    }
    [void]$R.Steps.Add([pscustomobject]@{ Kind = 'summary'; Title = 'Done - check the run'; Sub = 'verify, import the SD cards'; Glyph = [string][char]0xE73E; State = 'waiting'; Note = ''; Tip = ''; Tone = $Pal.Green; Plan = $null })
    Update-RunSteps
    try { Update-RootStepOption } catch { }     # gui\RootStep.ps1: one laptop, whole preset -> root by hand
    try { Initialize-ParallelFlashUi } catch { }  # gui\ParallelFlash.ps1: flash the children N at a time
    Set-RunState 'READY TO START'
    $ui.RunConsole.Document.Blocks.Clear(); $script:RunLines = 0
    Write-RunConsole ("Loaded {0}. Steps: compile -> {1}flash + run each board (root last) -> summary." -f $P.File, $(if ($R.Steps | Where-Object Kind -eq 'park') { 'park the old root -> ' } else { '' })) $Pal.Blue
    foreach ($n in $c.Notes) { Write-RunConsole "  $n" $Pal.Amber }
    foreach ($n in $c.Stop) { Write-RunConsole "  STOP: $n" $Pal.Red }
    Show-Page 7
    # nothing starts by itself (user, oct. 17 2026): only button 1 or 2 does
    if (-not $c.Stop.Count) {
        Set-RunNow 'Preset loaded - nothing has started' 'Check the options above, then press 1 Compile (touches no board) or 2 Wipe + flash + run (compiles first, then flashes).' $Pal.Cyan ([string][char]0xE946)
        Set-RunButtons -Abort $false
    }
}

function Get-RunSettings {
    $rep = 1; [void][int]::TryParse($ui.RunRepeat.Text, [ref]$rep); if ($rep -lt 1) { $rep = 1 }
    $rem = 0; [void][int]::TryParse($ui.RunRemote.Text, [ref]$rem); if ($rem -lt 0) { $rem = 0 }
    $post = if ($ui.RunPostTrim.IsChecked) { 'trim' } elseif ($ui.RunPostNone.IsChecked) { 'none' } else { 'analyze' }
    return @{ Repeat = $rep; Remote = $rem; Post = $post; Child = $(if ($ui.RunChildExport.IsChecked) { 'export' } else { 'now' }) }
}
function Build-RunParams {
    # the wizard's own New-RunParams, with the answers from this page
    $R = $script:Run; $c = $R.Plan; $s = Get-RunSettings
    $script:rootPostExport = $s.Post; $script:childExportMode = $s.Child
    # boards skipped after a failed flash no longer count for the root's roster gate
    $kids = @($c.Local | Where-Object Role -ne 'root').Count + $s.Remote - [int]$R.Skipped
    foreach ($st in @($R.Steps | Where-Object Kind -eq 'board')) {
        $h = New-RunParams -Board $st.Board -Attack $c.Attack -Topology $c.Topology -Location $c.Location -RepeatNum $s.Repeat -Scenario $c.Scenario -ExpectedChildren $kids -AttackerMac $c.AttackerMac
        if ($st.Board.Mac) { $h['Mac'] = [string]$st.Board.Mac }
        $h['SharedBuild'] = $true    # identical firmware = one build dir (run.ps1 -SharedBuild)
        $st.Plan = $h
    }
    $R | Add-Member -NotePropertyName Settings -NotePropertyValue $s -Force
}

# ── processes ────────────────────────────────────────────────────────────────
function Start-RunProc([string]$Command, [string]$What) {
    $R = $script:Run
    $R.Out = [IO.Path]::GetTempFileName(); $R.Err = [IO.Path]::GetTempFileName(); $R.PosO = 0; $R.PosE = 0; $R.BufO = ''; $R.BufE = ''
    $env:PYTHONIOENCODING = 'utf-8'; $env:PYTHONUNBUFFERED = '1'
    $full = "`$ErrorActionPreference = 'Continue'; `$ProgressPreference = 'SilentlyContinue'; [Console]::OutputEncoding = [Text.Encoding]::UTF8; Set-Location '$base'; . '$base\tools\idf_shims.ps1'; " + $Command
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($full))
    Write-RunConsole ''
    Write-RunConsole ("> {0}   ({1})" -f $What, (Get-Date).ToString('hh:mm:ss tt')) $Pal.Blue
    $R.Proc = Start-Process powershell -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-EncodedCommand', $enc) -WorkingDirectory $base `
        -WindowStyle Hidden -PassThru -RedirectStandardOutput $R.Out -RedirectStandardError $R.Err
    $null = $R.Proc.Handle
}
function Get-RunScriptCommand([hashtable]$Params, [string]$Json) {
    $Params | ConvertTo-Json -Depth 4 | Set-Content -Path $Json -Encoding UTF8
    return "try { `$h = @{}; (Get-Content -Raw '$Json' | ConvertFrom-Json).PSObject.Properties | ForEach-Object { `$h[`$_.Name] = `$_.Value }; " +
           "& '$($script:RunScript)' @h; exit `$LASTEXITCODE } catch { Write-Host ('ERROR: ' + `$_.Exception.Message); exit 1 }"
}
function Read-RunOutput {
    # new complete lines from both streams; PowerShell's own CLIXML records on
    # stderr are dropped, a '\r' progress redraw keeps only its last state
    $R = $script:Run; $lines = @()
    foreach ($k in 'O', 'E') {
        $pos = $R.("Pos$k"); $t = Read-NewText $R.$(if ($k -eq 'O') { 'Out' } else { 'Err' }) ([ref]$pos); $R.("Pos$k") = $pos
        if (-not $t) { continue }
        $buf = $R.("Buf$k") + $t
        $parts = $buf -split "`n"
        $R.("Buf$k") = $parts[-1]
        foreach ($ln in $parts[0..($parts.Count - 2)]) {
            $ln = ($ln -split "`r" | Where-Object { $_ } | Select-Object -Last 1)
            if ($null -eq $ln) { continue }
            $ln = $ln -replace "\x1b\[[0-9;]*m", ''
            if ($ln -match '^#< CLIXML' -or $ln -match '^<Objs ') { continue }
            if ($ln -match '^\s*PROGRESS:') { try { Update-LiveExportProgress $ln } catch { }; continue }   # gui\Progress.ps1
            $lines += $ln
        }
    }
    return $lines
}

# ── running the steps ────────────────────────────────────────────────────────
function Get-RunBuildKey($Plan) {
    # the build dir run.ps1 -SharedBuild will use: same firmware -> same key
    $k = [ordered]@{}; foreach ($x in $Plan.Keys) { $k[$x] = $Plan[$x] }; $k.Port = 'GUI'
    return (Get-BoardBuildDir -Params $k)
}
function Start-RunBuild([switch]$ThenGo, [string[]]$Only, [switch]$Quiet) {
    $R = $script:Run; if (-not $R) { return }
    if ($R.Proc -and -not $R.Proc.HasExited) {
        # already compiling (e.g. in the background): just carry on into the run
        if ($ThenGo -and $R.Phase -eq 'build') { $R.GoAfterBuild = $true; $R | Add-Member -NotePropertyName BuildQuiet -NotePropertyValue $false -Force; Set-RunNow 'Finishing the compile, then the run starts by itself' 'No board is touched until every variant compiled.' $Pal.Cyan ([string][char]0xE90F) }
        return
    }
    Build-RunParams
    $R.GoAfterBuild = [bool]$ThenGo
    $R | Add-Member -NotePropertyName BuildQuiet -NotePropertyValue ([bool]$Quiet) -Force
    $st = $R.Steps | Where-Object Kind -eq 'build' | Select-Object -First 1
    # one entry per firmware VARIANT (boards with identical firmware share it)
    $old = @{}; if ($R.Builds) { foreach ($e in $R.Builds) { $old[$e.Key] = $e } }
    $R.Builds = New-Object System.Collections.ArrayList
    foreach ($b in @($R.Steps | Where-Object Kind -eq 'board')) {
        $key = Get-RunBuildKey $b.Plan
        $e = @($R.Builds | Where-Object Key -eq $key)[0]
        if (-not $e) {
            $e = [pscustomobject]@{ Key = $key; Step = $b; Labels = (New-Object System.Collections.ArrayList); State = 'waiting'; Err = ''; Log = ''; Tries = 0; Fresh = $false }
            if ($old.ContainsKey($key)) { $e.State = $old[$key].State; $e.Err = $old[$key].Err; $e.Log = $old[$key].Log }
            [void]$R.Builds.Add($e)
        }
        [void]$e.Labels.Add($b.Board.Label)
    }
    $q = New-Object System.Collections.Queue
    $rootLbl = @(@($R.Steps | Where-Object { $_.Kind -eq 'board' -and $_.Board.Role -eq 'root' }) | ForEach-Object { $_.Board.Label })
    $byHand = $false; try { $byHand = Test-RootByHand } catch { }
    foreach ($e in $R.Builds) {
        $hit = (-not $Only) -or @($e.Labels | Where-Object { $Only -contains $_ }).Count
        # gui\RootStep.ps1 (oct. 20 2026): one laptop + root by hand -> the root is compiled at its own step
        if (-not $Only -and $byHand -and @($e.Labels | Where-Object { $rootLbl -contains $_ }).Count) { $hit = $false }
        if ($hit) { $e.Tries = 0; $e.Err = ''; $q.Enqueue($e) }
    }
    $R.BuildQueue = $q; $R | Add-Member -NotePropertyName BuildTotal -NotePropertyValue $q.Count -Force
    $R | Add-Member -NotePropertyName BuildWatch -NotePropertyValue ([Diagnostics.Stopwatch]::StartNew()) -Force
    # Clean rebuild: on by default and it stays ticked (user, oct. 17 2026), but
    # it runs ONCE per loaded run - on its first compile. Wiping again on the
    # Wipe + flash + run pass, or on 'Recompile only ...', would throw away the
    # builds this run just made and compile everything twice.
    if ($ui.RunClean.IsChecked -and -not $R.PSObject.Properties['Cleaned']) {
        $R | Add-Member -NotePropertyName Cleaned -NotePropertyValue $true -Force
        # oct. 20 2026 (clean rebuild ON by default - "make sure it won't crash our laptop"): a
        # compile never touches the boards' USB driver (the 0xB8 blue screen), so the risks are
        # deleting a build something else still compiles / flashes from, and a full disk.
        # Either one -> no clean this run (the normal incremental compile), said plainly.
        $skipWhy = ''
        try {
            $users = @(Get-CimInstance Win32_Process -Filter "Name='ninja.exe' OR Name='cmake.exe' OR Name='esptool.exe' OR Name='python.exe' OR Name='powershell.exe' OR Name='pwsh.exe'" -ErrorAction Stop |
                Where-Object { $_.ProcessId -ne $PID -and ($_.Name -in @('ninja.exe', 'cmake.exe', 'esptool.exe') -or [string]$_.CommandLine -match '(?i)idf\.py|esptool|(?<![\w-])run\.ps1|run_wizard|menu\.ps1') })
            if ($users.Count) { $skipWhy = ("{0} is still compiling or flashing (process {1})" -f $users[0].Name, $users[0].ProcessId) }
        } catch { }
        try { $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($shortBuildRoot))).AvailableFreeSpace; if ($free -lt 3GB) { $skipWhy = ("only {0:N1} GB free on {1}" -f ($free / 1GB), [IO.Path]::GetPathRoot($shortBuildRoot)) } } catch { }
        if ($skipWhy -and -not $SelfTest) {
            Write-RunConsole ("Clean rebuild SKIPPED for this run: {0}. Compiling normally (only changed code) - safe; tick it again once that is done." -f $skipWhy) $Pal.Amber
            Add-RunAlert ("clean rebuild skipped: {0}" -f $skipWhy) $Pal.Amber
        } else {
        Write-RunConsole "Clean rebuild: removing build_* under $buildRoot and $shortBuildRoot (first compile of this run - every variant compiles from scratch, ~2-4 min each) ..." $Pal.Amber
        # NOT $r: PowerShell names are case-insensitive, $r IS $R (the run) -
        # the old loop overwrote the run with a path and crashed the window
        foreach ($cleanDir in @($buildRoot, $shortBuildRoot)) {
            Remove-Item -Recurse -Force (Join-Path $cleanDir 'child_node\build_*') -ErrorAction SilentlyContinue
            Remove-Item -Recurse -Force (Join-Path $cleanDir 'root_node\build_*') -ErrorAction SilentlyContinue
            # a file held open (antivirus, an open log) leaves a HALF-deleted folder: drop its
            # CMake cache so the compile reconfigures it from scratch instead of failing oddly
            foreach ($left in @(Get-ChildItem -Directory -Path (Join-Path $cleanDir 'child_node'), (Join-Path $cleanDir 'root_node') -Filter 'build_*' -ErrorAction SilentlyContinue)) {
                Remove-Item -Force (Join-Path $left.FullName 'CMakeCache.txt') -ErrorAction SilentlyContinue
                Write-RunConsole ("  could not delete all of {0} (a file is open) - it is reconfigured from scratch instead" -f $left.FullName) $Pal.Amber
            }
        }
        }
    }
    $R.Current = $st; $st.State = 'running'; $st.Note = "0 of $($q.Count)"
    $R.Phase = 'build'; $R.Active = -not $Quiet
    if (-not $R.Started -and -not $Quiet) { $R.Started = Get-Date }
    Set-RunState 'COMPILING' $Pal.Cyan
    $what = if ($Only) { 'Recompiling only ' + ($Only -join ', ') } else { 'Compiling {0} firmware variant(s) for {1} board(s)' -f $q.Count, @($R.Steps | Where-Object Kind -eq 'board').Count }
    Set-RunNow $what 'No board is touched. Boards with identical firmware share one build; an unchanged variant is skipped in a second.' $Pal.Cyan ([string][char]0xE90F)
    Set-RunButtons -Abort (-not $Quiet)
    if (-not $Quiet) { $ui.RunSetup.IsEnabled = $false }
    Update-RunSteps
    Step-RunBuild
}
function Set-RunBoardNotes {
    # every board shows whether ITS firmware is ready
    $R = $script:Run
    foreach ($e in @($R.Builds)) {
        foreach ($b in @($R.Steps | Where-Object { $_.Kind -eq 'board' -and $e.Labels -contains $_.Board.Label })) {
            if ($b.State -in @('waiting', 'failed') -and $R.Phase -in @('build', 'buildfail', 'setup', 'pick')) {
                $b.State = $(if ($e.State -eq 'failed') { 'failed' } else { 'waiting' })
                $b.Note = switch ($e.State) { 'ok' { 'firmware ready' } 'failed' { 'compile FAILED - click me' } 'running' { 'compiling...' } default { '' } }
            }
        }
    }
}
function Step-RunBuild {
    $R = $script:Run; $st = $R.Current
    Set-RunBoardNotes
    if ($R.BuildQueue.Count -eq 0) {
        $R.BuildWatch.Stop()
        $bad = @($R.Builds | Where-Object State -eq 'failed')
        if ($bad.Count) {
            $labels = @($bad | ForEach-Object { $_.Labels }) | Select-Object -Unique
            $good = @($R.Builds | Where-Object State -eq 'ok').Count
            $st.State = 'failed'; $st.Note = 'failed: ' + ($labels -join ', ')
            Set-RunState 'BUILD FAILED' $Pal.Red
            $err = ($bad | ForEach-Object { if ($_.Err) { "{0}:  {1}" -f ($_.Labels -join '/'), $_.Err } }) -join "`n"
            Set-RunNow ('Compile failed for ' + ($labels -join ', ')) ("{0}{1}Nothing was flashed. {2} other variant(s) are ready and kept - only the failed one needs compiling again." -f $(if ($err) { $err } else { 'The first compiler error is in the console.' }), "`n", $good) $Pal.Red ([string][char]0xE783)
            $R.Failed = $labels
            $R.Active = $false; $R.Phase = 'buildfail'; $ui.RunSetup.IsEnabled = $true
            Set-RunButtons -Next ('Recompile only ' + ($labels -join ', ') + '  ->') -Cont $(if (@($bad | Where-Object Log).Count) { 'Open the full log' } else { '' }) -Abort $false
            $ui.RunCleanFix.Content = 'Clean + recompile ' + ($labels -join ', '); $ui.RunCleanFix.Visibility = 'Visible'
            # errors from the BUILD SYSTEM (not the C code) mean a damaged build folder: say which button fixes it
            if (@($bad | Where-Object { $_.Err -match '(?i)CMake Error|ninja: error|recompaction|CMakeCache|sdkconfig|No such file or directory|cannot open|Permission denied' }).Count) {
                $ui.RunNowText.Text += "`n`nThis looks like a damaged build folder, not a code error - press 'Clean + recompile'."
            }
            Update-RunSteps; return
        }
        $nNew = @($R.Builds | Where-Object Fresh).Count
        $st.State = 'ok'; $st.Note = "{0} variant(s) ready in {1}{2}" -f $R.Builds.Count, (Format-Duration ([int]$R.BuildWatch.Elapsed.TotalSeconds)), $(if ($nNew -lt $R.Builds.Count) { " ($nNew compiled, $($R.Builds.Count - $nNew) up to date)" } else { '' })
        $R.Built = $true
        if ($R.PSObject.Properties['RootBuilding'] -and $R.RootBuilding) { Update-RunSteps; Complete-RootCompile; return }   # gui\RootStep.ps1
        Write-RunConsole ("All {0} variant(s) ready - 0 errors." -f @($R.Builds | Where-Object State -eq 'ok').Count) $Pal.Green
        Update-RunSteps
        if ($R.GoAfterBuild) { Start-RunBoards; return }
        $R.Active = $false; $R.Phase = 'setup'; $ui.RunSetup.IsEnabled = $true
        Set-RunState 'COMPILED' $Pal.Green
        Set-RunNow 'Firmware ready' 'Press "2  Wipe + flash + run" when the boards are in place - nothing needs compiling again.' $Pal.Green ([string][char]0xE73E)
        Set-RunButtons -Abort $false
        Show-Toast 'Firmware ready' "$($R.Builds.Count) variant(s) ready - press Wipe + flash + run" ([string][char]0xE73E)
        return
    }
    $e = $R.BuildQueue.Dequeue()
    $R.BuildEntry = $e; $e.State = 'running'; $e.Fresh = $false
    $done = $R.BuildTotal - $R.BuildQueue.Count
    $st.Note = "{0} of {1}: {2}" -f $done, $R.BuildTotal, ($e.Labels -join ', ')
    Set-RunBoardNotes
    Update-RunSteps
    $h = [ordered]@{}; foreach ($k in $e.Step.Plan.Keys) { $h[$k] = $e.Step.Plan[$k] }; $h.BuildOnly = $true
    New-Item -ItemType Directory -Force -Path $script:RunCtlRoot | Out-Null
    Start-RunProc (Get-RunScriptCommand $h (Join-Path $script:RunCtlRoot ("build_{0}.json" -f ($e.Labels[0] -replace '[^\w-]', '')))) ("Compile [{0}/{1}] {2} - {3}" -f $done, $R.BuildTotal, ($e.Labels -join ', '), (Get-RunRoleLook $e.Step.Board.Kind $e.Step.Board.Role).Text)
}
function Read-BuildLine([string]$Line) {
    # remember the first compiler error + the log path for the failure card
    $e = $script:Run.BuildEntry; if (-not $e) { return }
    if ($Line -match 'first error:\s*(.+)$') { $e.Err = $Matches[1].Trim() }
    elseif (-not $e.Err -and $Line -match '(?i)(\berror:|CMake Error)') { $e.Err = ($Line.Trim() -replace '^.*[\\/]', '') }
    if ($Line -match 'full log:\s*(.+)$') { $e.Log = $Matches[1].Trim() }
    if ($Line -match 'Built OK in') { $e.Fresh = $true }
    if ($Line -match '(?i)permission denied|failed recompaction|being used by another process|cannot open output file|access is denied') { $e | Add-Member -NotePropertyName Busy -NotePropertyValue $true -Force }
}

function Start-RunBoards {
    $R = $script:Run
    $s = $R.Settings
    if (-not @($R.Steps | Where-Object { $_.Kind -eq 'board' -and $_.State -eq 'ok' }).Count) { Reset-PreStart }   # a fresh run, not a resume
    Save-LastUsedPreset 'running'
    if ($ui.RunSaveLog.IsChecked -and -not $R.LogPath) {
        try {
            $dirs = Get-RunDirs -Attack $R.Plan.Attack -Topology $R.Plan.Topology -Location $R.Plan.Location -Scenario $R.Plan.Scenario
            $ld = Get-RunLogDir -AttackDir $dirs.AttackDir -TopoDir $dirs.TopoDir -Location $R.Plan.Location -Scenario $R.Plan.Scenario
            New-Item -ItemType Directory -Force -Path $ld | Out-Null
            $R.LogPath = Get-StampedPath -Dir $ld -Head ("{0}_r{1}" -f [IO.Path]::GetFileNameWithoutExtension($R.Plan.Preset.File), $s.Repeat) -Ext '.log'
            [IO.File]::WriteAllText($R.LogPath, ("NIS16 Capture Studio run log - {0} - {1}`r`n" -f $R.Plan.Preset.File, (Get-Date)))
            Write-RunConsole "Logging this run -> $($R.LogPath)" $Pal.Faint
        } catch { Write-RunConsole ("Could not start the run log: " + $_.Exception.Message) $Pal.Amber }
    }
    $R.Phase = 'boards'; $R.Active = $true
    $ui.RunSetup.IsEnabled = $false
    $next = $R.Steps | Where-Object { $_.Kind -in @('park', 'board') -and $_.State -eq 'waiting' } | Select-Object -First 1
    Start-RunStep $next
}
function Start-RunStep($St) {
    $R = $script:Run
    if (-not $St) { Complete-Run; return }
    $R.Current = $St; Update-RunSteps
    if ($St.Kind -eq 'park') {
        $St.State = 'running'; $St.Note = 'parking...'
        Set-RunState 'PARKING ROOT' $Pal.Amber
        $rootB = @($R.Plan.Local | Where-Object Role -eq 'root')[0]
        Set-RunNow "Parking the root on $($rootB.Port)" 'Its OLD firmware would send a stale TERMINATE that stops the new children. Parked = sitting in its bootloader, firmware kept; it is woken right before its own turn.' $Pal.Amber ([string][char]0xE769)
        Set-RunButtons -Abort $true
        Start-RunProc ("& '$($script:RunEsptool)' --chip esp32 --port $($rootB.Port) --after no_reset read_mac; if (`$LASTEXITCODE -eq 0) { & '$($script:RunEsptool)' --chip esp32 --port $($rootB.Port) --before no_reset --after no_reset read_mac }; exit `$LASTEXITCODE") "Park the root on $($rootB.Port)"
        Update-RunSteps; return
    }
    # a board: its port must be live, and a shared port means "swap now"
    $b = $St.Board
    # gui\ParallelFlash.ps1 (oct. 20 2026): the first child step flashes every plugged-in child N at a time
    if ($b.Role -ne 'root') {
        $pfGo = $false
        try { $pfGo = Start-ParallelChildFlash $St } catch { Write-RunConsole ("  parallel flash could not start ({0}) - flashing one at a time" -f $_.Exception.Message) $Pal.Amber }
        if ($pfGo) { return }
    }
    if (-not $script:Live.Contains([string]$b.Port)) {
        $St.State = 'attention'; $St.Note = 'plug it in'
        $R.Wait = @{ Kind = 'port'; Step = $St; Known = @($script:Live.Keys) }
        Set-RunState 'WAITING FOR A BOARD' $Pal.Amber
        Set-RunNow ("Plug in {0} ({1})" -f $b.Label, (Get-RunRoleLook $b.Kind $b.Role).Text) ("It is not on {0}. Plug it in - the run carries on by itself on whatever port it gets{1}." -f $b.Port, $(if ($b.Mac) { " (MAC $(Get-ShortMac $b.Mac))" } else { '' })) $Pal.Amber ([string][char]0xE88E)
        Set-RunButtons -Abort $true
        Update-RunSteps; return
    }
    if ($R.Used.ContainsKey([string]$b.Port) -and -not ($R.Wait -and $R.Wait.Kind -eq 'swapok')) {
        $St.State = 'attention'; $St.Note = 'swap boards'
        $R.Wait = @{ Kind = 'swap'; Step = $St }
        Set-RunState 'SWAP BOARDS' $Pal.Amber
        Set-RunNow ("Swap: unplug {0}, plug {1} into {2}" -f $R.Used[[string]$b.Port], $b.Label, $b.Port) 'This preset shares one port between boards. Press Continue once the right board is on the cable.' $Pal.Amber ([string][char]0xE8AB)
        Set-RunButtons -Cont 'Continue  ->' -Abort $true
        Update-RunSteps; return
    }
    $R.Wait = $null
    # gui\RootStep.ps1 (oct. 20 2026): one laptop + root by hand -> the operator compiles + flashes it
    $byHand = $false; try { $byHand = Test-RootByHand } catch { }
    if ($b.Role -eq 'root' -and $byHand -and -not ($R.PSObject.Properties['RootGo'] -and $R.RootGo)) { Show-RootGate; return }
    # gui\SnifferGate.ps1 (oct. 20 2026): no sniffer recording -> the root waits (asked once per run)
    $needSn = $false; try { $needSn = $b.Role -eq 'root' -and (Test-SnifferGateNeeded) } catch { }
    if ($needSn) { Show-SnifferGate $St; return }
    if ($b.Role -eq 'root' -and $R.Parked) {
        Stop-CrashWatchOn ([string]$b.Port)
        $St.State = 'running'; $St.Note = 'waking the root...'
        $R.Wait = @{ Kind = 'wake'; Step = $St }
        Set-RunNow 'Waking the parked root' 'So run.ps1 can set its clock (about 10 s).' $Pal.Cyan ([string][char]0xE945)
        Start-RunProc ("& '$($script:RunEsptool)' --chip esp32 --port $($b.Port) --before no_reset --after hard_reset read_mac; if (`$LASTEXITCODE -eq 0) { Start-Sleep -Seconds $(if ($SelfTest) { 1 } else { 10 }) }; exit 0") "Wake the root on $($b.Port)"
        Update-RunSteps; return
    }
    Start-RunBoardProc $St
}
function Start-RunBoardProc($St) {
    $R = $script:Run; $b = $St.Board
    if ($b.Role -eq 'root') { Invoke-BeforeRootFlash $St }    # gui\RunSafety.ps1: watch every child, offer a clean restart
    Stop-CrashWatchOn ([string]$b.Port)
    $R.Ctl = Join-Path $script:RunCtlRoot ("ctl_{0}_{1}" -f ($b.Label -replace '[^\w-]', ''), (Get-Date).ToString('HHmmss'))
    New-Item -ItemType Directory -Force -Path $R.Ctl | Out-Null
    $h = [ordered]@{}; foreach ($k in $St.Plan.Keys) { $h[$k] = $St.Plan[$k] }
    $h.Port = [string]$b.Port; $h.GuiMonitor = $R.Ctl
    $St.State = 'running'; $St.Note = 'erasing + flashing...'
    $R.Phase = 'flash'; $R.Used[[string]$b.Port] = $b.Label
    $R | Add-Member -NotePropertyName BoardStart -NotePropertyValue (Get-Date) -Force
    $R | Add-Member -NotePropertyName Booted -NotePropertyValue $false -Force
    $ui.RunSkipExport.IsChecked = $false
    $isRoot = $b.Role -eq 'root'
    Set-RunState $(if ($isRoot) { 'FLASHING ROOT' } else { "FLASHING $($b.Label.ToUpper())" }) $Pal.Cyan
    Set-RunNow ("Flashing {0} on {1}" -f $b.Label, $b.Port) 'Clock set -> full erase -> flash. Do not unplug it. The monitor opens by itself.' $Pal.Cyan ([string][char]0xE896)
    Set-RunButtons -Abort $true
    $ui.RunConsoleTitle.Text = ("CONSOLE  -  {0} on {1}" -f $b.Label, $b.Port)
    if ($isRoot) { Reset-RootDash }
    Start-RunProc (Get-RunScriptCommand $h (Join-Path $R.Ctl 'params.json')) ("{0}  -  {1} on {2}   .\run.ps1 {3}" -f $St.Title, $b.Display, $b.Port, (Format-RunParams $St.Plan))
    Update-RunSteps
}
function Send-RunCommand([string]$Cmd) {
    $R = $script:Run
    if (-not $R -or $R.Phase -ne 'monitor' -or -not $R.Ctl) { return }
    Add-Content -Path (Join-Path $R.Ctl 'send.txt') -Value $Cmd -Encoding ASCII
    Write-RunConsole ("  you sent: {0}" -f $Cmd) $Pal.Cyan
}
function Stop-RunMonitor([switch]$NoExport) {
    $R = $script:Run; if (-not $R -or $R.Phase -ne 'monitor') { return }
    $b = $R.Current.Board
    $exports = (-not $NoExport) -and -not ($b.Role -ne 'root' -and $R.Settings.Child -eq 'now')
    if ($NoExport) { Set-Content -Path (Join-Path $R.Ctl 'noexport') -Value 'skip' }
    Set-Content -Path (Join-Path $R.Ctl 'stop') -Value 'stop'
    # oct. 20 2026 (user): "Finish + export root" also STOPS the sniffer, so its .pcap is closed
    # and saved with the run - the root is the last board, the run is over
    if ($b.Role -eq 'root') { try { Stop-SnifferWithRun } catch { } }
    $R.Phase = $(if ($exports) { 'export' } else { 'closing' })
    $R.Current.Note = $(if ($exports) { 'exporting - do not unplug' } else { 'closing the monitor' })
    if ($exports) {
        Set-RunState "EXPORTING $($b.Label.ToUpper())" $Pal.Amber
        Set-RunNow ("Exporting {0} - do NOT unplug it" -f $b.Label) 'Pulling its CSVs over USB (about a minute). Never cut an export - that is what blue-screens this laptop.' $Pal.Amber ([string][char]0xE896)
        Set-RunButtons -Abort $false
    }
    Update-RunSteps
}
function Complete-RunStep([int]$Code) {
    $R = $script:Run; $st = $R.Current
    switch ($st.Kind) {
        'build' {
            if ($R.Phase -eq 'stopping') { $st.State = 'skipped'; $st.Note = 'stopped by you'; Finish-RunStopped; return }
            $e = $R.BuildEntry
            if ($Code -eq 0) { $e.State = 'ok' }
            elseif ($e.Busy -and $e.Tries -lt 1) {
                # a locked file (OneDrive, antivirus, a second build) - not a code error: once more by itself
                $e.Tries++; $e.Busy = $false; $e.Err = ''; $e.State = 'waiting'
                Write-RunConsole '  a file was busy - compiling that variant once more by itself' $Pal.Amber
                $R.BuildQueue.Enqueue($e); $R.BuildTotal++
            }
            else { $e.State = 'failed' }
            Step-RunBuild; return
        }
        'park' {
            if ($R.StopAfterFlash) { $R.StopAfterFlash = $false; $st.State = 'skipped'; Finish-RunStopped; return }
            if ($Code -eq 0) { $R.Parked = $true; $st.State = 'ok'; $st.Note = 'parked - silent until its turn'; Write-RunConsole '  root parked' $Pal.Green }
            else {
                $st.State = 'attention'; $st.Note = 'unplug the root'
                [void][Windows.MessageBox]::Show("Could not park the root.`n`nUNPLUG THE ROOT now and plug it back in only at its turn - or its old run may terminate the children.`n`nPress OK once it is unplugged.", 'Park the root', 'OK', 'Warning')
                $st.State = 'ok'; $st.Note = 'unplugged by hand'
            }
            Start-RunStep ($R.Steps | Where-Object { $_.Kind -eq 'board' -and $_.State -eq 'waiting' } | Select-Object -First 1); return
        }
        'board' {
            if ($R.Wait -and $R.Wait.Kind -eq 'wake') {
                $R.Wait = $null; $R.Parked = $false
                if ($R.StopAfterFlash) { $R.StopAfterFlash = $false; Finish-RunStopped; return }
                Start-RunBoardProc $st; return
            }
            $b = $st.Board
            $secs = [int]((Get-Date) - $R.BoardStart).TotalSeconds
            if ($R.Phase -eq 'stopping') {
                $st.State = 'failed'; $st.Note = 'stopped by you'
                Finish-RunStopped; return
            }
            if ($R.StopAfterFlash) {
                # Stop pressed mid-flash and the flash itself failed (no monitor)
                $R.StopAfterFlash = $false
                $st.State = 'failed'; $st.Note = "flash failed (exit $Code) - stopped by you"
                Finish-RunStopped; return
            }
            if ($Code -ne 0 -and $b.Role -ne 'root') {
                # one bad board does not throw the run away: retry it, or skip it
                # (the root then waits for one child fewer), or stop
                $st.State = 'failed'; $st.Note = "failed (exit $Code) - retry or skip"
                $R.Failed = $st; $R.Phase = 'boardfail'
                Set-RunState "$($b.Label.ToUpper()) FAILED" $Pal.Red
                Set-RunNow ("{0} failed (exit {1})" -f $b.Label, $Code) 'Usually a USB flash glitch - plug it straight into the laptop (no hub, short data cable) and Retry. Boards already done keep running. Skip = go on without it (the root then waits for one child fewer).' $Pal.Red ([string][char]0xE783)
                Set-RunButtons -Next ("Retry {0}  ->" -f $b.Label) -Cont ("Skip {0}" -f $b.Label) -Abort $true
                Update-RunSteps; return
            }
            $st.State = 'ok'
            $st.Note = $(if ($Code -ne 0) { "root returned exit $Code - check the exports" } else { "done in $(Format-Duration $secs)" })
            if ($b.Role -ne 'root' -and $ui.RunWatchKids.IsChecked -and -not $SelfTest) { Start-CrashWatch $st; $st.Note += ' - listening' }
            if ($Code -ne 0) { $st.State = 'attention' }
            $R.Current = $null
            Start-RunStep ($R.Steps | Where-Object { $_.Kind -eq 'board' -and $_.State -eq 'waiting' } | Select-Object -First 1); return
        }
    }
}
function Complete-Run {
    try { Hide-RootStepBar } catch { }     # gui\RootStep.ps1
    try { Hide-SnifferGateBar } catch { }  # gui\SnifferGate.ps1
    $R = $script:Run
    Stop-CrashWatch
    $sum = $R.Steps | Where-Object Kind -eq 'summary' | Select-Object -First 1
    $R.Current = $sum; $sum.State = 'ok'
    $R.Active = $false; $R.Phase = 'done'
    $mins = Format-Duration ([int]((Get-Date) - $R.Started).TotalSeconds)
    $dirs = Get-RunDirs -Attack $R.Plan.Attack -Topology $R.Plan.Topology -Location $R.Plan.Location -Scenario $R.Plan.Scenario
    $R | Add-Member -NotePropertyName Dirs -NotePropertyValue $dirs -Force
    $sum.Note = "all done in $mins"
    Set-RunState 'DONE' $Pal.Green
    Set-RunNow ("All {0} board(s) done in {1}" -f @($R.Steps | Where-Object Kind -eq 'board').Count, $mins) ("Exports -> {0}`nNext: import the children's SD cards, then verify this run.{1}" -f $dirs.Export, $(if ($R.LogPath) { "`nRun log saved -> $($R.LogPath) (share it from the GitHub sync page)" } else { '' })) $Pal.Green ([string][char]0xE73E)
    # boards that never said SAFE in the root's last table must not be unplugged
    $notSafe = @(); if ($script:Dash -and $script:Dash.Rows) { $notSafe = @($script:Dash.Rows | Where-Object { $_.Export -ne 'SAFE' -and $_.Role -notmatch 'ROOT' } | ForEach-Object { $_.Mac }) }
    $crashed = @(); if ($R.Bg) { $crashed = @($R.Bg | Where-Object Crashes -gt 0 | ForEach-Object { '{0} x{1}' -f $_.Label, $_.Crashes }) }
    $extra = ''
    if ($notSafe.Count) { $extra += "`n`nNOT SAFE yet: {0} - their file is still open. Do NOT unplug them: Data > Import (through the board) > 'End its run now + close the file safely'." -f ($notSafe -join ', ') }
    if ($crashed.Count) { $extra += "`n`nCRASHES recorded: {0} - logs + decoded backtraces in {1}" -f ($crashed -join ', '), (Get-RunLogFolder) }
    if ($extra) { $ui.RunNowText.Text += $extra; $ui.RunNow.BorderBrush = & $brush $Pal.Amber }
    $nKids = @(Get-CollectPorts).Count
    Set-RunButtons -Next 'Verify this run  ->' -Cont $(if ($nKids) { "Collect all $nKids children  ->" } else { 'Import SD cards' }) -Abort $false
    $ui.RunAgain.Visibility = 'Visible'
    $ui.RunSetup.IsEnabled = $true
    Update-RunSteps
    Write-RunConsole ("All boards done in {0}. Exports -> {1}" -f $mins, $dirs.Export) $Pal.Green
    Save-LastUsedPreset 'finished'
    Show-Toast 'Run finished' 'Import the SD cards, then verify it.' ([string][char]0xE73E) 'GradGood' { Show-Page 5 } 'Import now'
    Update-NavBadges
}
function Finish-RunStopped {
    try { Hide-RootStepBar } catch { }     # gui\RootStep.ps1
    try { Hide-SnifferGateBar } catch { }  # gui\SnifferGate.ps1
    $R = $script:Run
    # the flashed children KEEP RUNNING after a stop - keep listening to them
    # (oct. 18 2026: a victim crashed unwatched after a stop + root-only re-run)
    $script:PrevAttemptSeg = $(if ($script:Dash) { [int]$script:Dash.Seg } else { -1 })
    Save-LastUsedPreset 'stopped'
    foreach ($x in @($R.Steps | Where-Object { $_.State -in @('waiting', 'running', 'attention') })) { $x.State = 'skipped' }
    $R.Active = $false; $R.Phase = 'stopped'; $R.Wait = $null
    Set-RunState 'STOPPED' $Pal.Amber
    Set-RunNow 'Run stopped' 'Boards already flashed keep running; nothing more was exported. Press "2 Wipe + flash + run" to RESUME with the boards not done yet, or to start over.' $Pal.Amber ([string][char]0xE71A)
    Set-RunButtons -Abort $false
    $ui.RunSetup.IsEnabled = $true
    Update-RunSteps
}

# ── CRASH WATCH (oct. 17 2026) ───────────────────────────────────────────────
# Verification #39: three victims crashed (PANIC / INT_WDT) in blackhole/tree/
# G402/highload and nobody could say why - a crash report only ever appears on
# the board's serial port, and no child was being listened to after its turn.
# Now every flashed child keeps a console-free monitor (tools\gui_monitor.py:
# DTR/RTS low = no reset, reads non-stop, sends nothing) writing to a log next
# to the run log, until the run ends. Crash lines raise an alert at once; a
# Backtrace is decoded against that board's own firmware .elf.
$script:CrashRx = '(?i)Guru Meditation|abort\(\) was called|Backtrace:|Brownout detector was triggered|Task watchdog got triggered|Interrupt wdt timeout|stack overflow|CORRUPT HEAP|assert failed|rst:0x[0-9a-f]+ \((?!POWERON)'
function Get-RunLogFolder {
    $R = $script:Run
    if ($R.LogPath) { return (Split-Path $R.LogPath -Parent) }
    $d = Join-Path $base 'datasets\run_logs\_serial'
    New-Item -ItemType Directory -Force -Path $d | Out-Null
    return $d
}
function Start-CrashWatch($St) {
    $R = $script:Run; $b = $St.Board
    if (-not $R.Bg) { $R | Add-Member -NotePropertyName Bg -NotePropertyValue (New-Object System.Collections.ArrayList) -Force }
    $ctl = Join-Path $script:RunCtlRoot ("watch_{0}_{1}" -f ($b.Label -replace '[^\w-]', ''), (Get-Date).ToString('HHmmss'))
    New-Item -ItemType Directory -Force -Path $ctl | Out-Null
    $log = Join-Path (Get-RunLogFolder) ("{0}_{1}_serial_{2}.log" -f ($b.Label -replace '[^\w-]', ''), $b.Port, (Get-Date).ToString('MMMdd_hhmmtt').ToLower())
    $env:PYTHONUNBUFFERED = '1'
    try {
        $p = Start-Process python -ArgumentList @((Join-Path $base 'tools\gui_monitor.py'), '--port', $b.Port, '--ctl', "`"$ctl`"", '--max-hours', '3') `
            -WorkingDirectory (Join-Path $base 'tools') -WindowStyle Hidden -PassThru -RedirectStandardOutput $log -RedirectStandardError ($log + '.err')
    } catch { Write-RunConsole ("  could not start the crash watch on {0}: {1}" -f $b.Port, $_.Exception.Message) $Pal.Amber; return }
    $elf = Join-Path (Get-RunBuildKey $St.Plan) $(if ($b.Role -eq 'root') { 'root_node.elf' } else { 'child_node.elf' })
    [void]$R.Bg.Add([pscustomobject]@{ Label = $b.Label; Port = $b.Port; Proc = $p; Log = $log; Pos = [long]0; Buf = ''; Ctl = $ctl; Elf = $elf; Crashes = 0; Recovered = 0; Last = '' })
    Write-RunConsole ("  crash watch on {0} ({1}) -> {2}" -f $b.Label, $b.Port, $log) $Pal.Faint
}
function Stop-CrashWatch {
    $R = $script:Run; if (-not $R -or -not $R.Bg) { return }
    foreach ($w in @($R.Bg)) { if (-not $w.Proc.HasExited) { Set-Content -Path (Join-Path $w.Ctl 'stop') -Value 'stop' -ErrorAction SilentlyContinue } }
}
function Stop-CrashWatchOn([string]$Port) {
    # a shared-port preset (swap boards) flashes the next board on a port the
    # last board's watch still holds open -> erase/flash 'port busy'. Release it
    # first: stop file (polled every few 100 ms), then kill if it lingers.
    $R = $script:Run; if (-not $R -or -not $R.Bg) { return }
    foreach ($w in @($R.Bg | Where-Object { $_.Port -eq $Port -and -not $_.Proc.HasExited })) {
        Set-Content -Path (Join-Path $w.Ctl 'stop') -Value 'stop' -ErrorAction SilentlyContinue
        if (-not $w.Proc.WaitForExit(3000)) { try { $w.Proc.Kill() } catch { } }
        Write-RunConsole ("  crash watch on {0} ({1}) closed - the port is needed for the next board" -f $w.Label, $Port) $Pal.Faint
    }
}
function Read-CrashWatch {
    $R = $script:Run; if (-not $R -or -not $R.Bg) { return }
    foreach ($w in @($R.Bg)) {
        $pos = $w.Pos; $t = Read-NewText $w.Log ([ref]$pos); $w.Pos = $pos
        if (-not $t) { continue }
        $parts = ($w.Buf + $t) -split "`n"; $w.Buf = $parts[-1]
        foreach ($ln in $parts[0..($parts.Count - 2)]) {
            $ln = ($ln -replace "\x1b\[[0-9;]*m", '').TrimEnd("`r")
            if ($w.Crashes -gt $w.Recovered -and $ln -match '=== .*STARTING') {
                $w.Recovered = $w.Crashes
                Add-RunAlert ("{0} ({1}) is back up after the crash" -f $w.Label, $w.Port) $Pal.Green
                continue
            }
            if ($ln -match '\[HEALTH\] LOW') { Read-HealthLine $w.Label $ln; continue }    # gui\RunSafety.ps1
            if ($ln -notmatch $script:CrashRx) { continue }
            if ($ln -match '^Backtrace:') {
                $pcs = @([regex]::Matches($ln, '0x[0-9a-fA-F]{8}(?=:)') | ForEach-Object Value)
                if ($pcs.Count -and (Test-Path $w.Elf) -and (Get-Command xtensa-esp32-elf-addr2line -ErrorAction SilentlyContinue)) {
                    Start-ToolJob -Exe 'xtensa-esp32-elf-addr2line' -ToolArgs (@('-pfiaC', '-e', $w.Elf) + $pcs) -State $w -OnDone {
                        param($text, $code, $w)
                        $dec = ($text -split "`r?`n" | Where-Object { $_.Trim() }) -join "`r`n"
                        try { [IO.File]::AppendAllText($w.Log + '.decoded.txt', ("{0}  {1} ({2}) crash backtrace:`r`n{3}`r`n`r`n" -f (Get-Date), $w.Label, $w.Port, $dec)) } catch { }
                        $top = @($text -split "`r?`n" | Where-Object { $_ -match ': ' -and $_ -notmatch '\?\? ' } | Select-Object -First 2) -join '  <-  '
                        Add-RunAlert ("{0} crash location: {1}" -f $w.Label, $(if ($top) { ($top -replace '0x[0-9a-f]+: ', '') } else { 'see the .decoded.txt' })) $Pal.Red
                        Write-RunConsole ("  {0} crash decoded -> {1}.decoded.txt" -f $w.Label, $w.Log) $Pal.Red
                    }
                }
                continue
            }
            $w.Crashes++
            $what = if ($ln -match '(?i)Guru Meditation[^:]*:\s*(.+)$') { $Matches[1] } elseif ($ln -match '(?i)rst:0x[0-9a-f]+ \(([^)]+)\)') { "reset: $($Matches[1])" } else { $ln.Trim() }
            Add-RunAlert ("{0} ({1}) CRASHED: {2}" -f $w.Label, $w.Port, $what) $Pal.Red
            Write-RunConsole ("  !! {0} ({1}) CRASHED: {2}   (full log: {3})" -f $w.Label, $w.Port, $ln.Trim(), $w.Log) $Pal.Red
            if ($w.Last -ne $what) { Show-Toast ("{0} CRASHED" -f $w.Label) $what ([string][char]0xE783) 'GradMain' { Show-Page 7 } 'Open the run'; $w.Last = $what }
        }
    }
}

# ── the ROOT dashboard, read from the root's own monitor lines ──────────────
$script:RunSegNames = @('Stabilise', 'Baseline', 'Attack', 'Cooldown', 'End')
function Reset-RootDash {
    $d = Get-PhaseDurations
    $script:Dash = @{ Phase = ''; Seg = -1; Since = $null; Len = 0; Kids = ''; Rows = (New-Object System.Collections.ArrayList); Collect = $false
                      Topo = @{}; Tunnel = @(); InTunnel = $false; Alerts = (New-Object System.Collections.ArrayList); Ended = $false; Ready = $false
                      Dur = @($d.Stabilise, $d.Baseline, $d.Attack, $d.Cooldown, 20) }
    $ui.RunPhase.Text = 'not running yet'; $ui.RunPhaseLeft.Text = ''; $ui.RunPhaseNote.Text = ("One run = {0} once the mesh forms (stabilise {1}s, baseline {2}s, attack {3}s, cooldown {4}s)." -f (Format-Duration $d.Total), $d.Stabilise, $d.Baseline, $d.Attack, $d.Cooldown)
    $ui.RunKids.Text = '-'; $ui.RunGate.Text = 'The root waits for every child, checks the setup, then waits for you to press START.'
    $ui.RunTopoStatus.Text = '-'; $ui.RunTopoInfo.Text = 'appears once the root prints its first table'; $ui.RunTopoDetail.Text = ''
    $ui.RunNodes.ItemsSource = $null; $ui.RunAlerts.ItemsSource = $null; $ui.RunAlertsNone.Visibility = 'Visible'
    Reset-SmartAlerts
    try { Reset-BoardHealth } catch { }    # gui\BoardHealth.ps1: live board health card
    $ui.RunTunnelCard.Visibility = 'Collapsed'
    $ui.RunStart.IsEnabled = $false; $ui.RunStartAnyway.IsEnabled = $false
    Update-RootSegs
}
function Update-RootSegs {
    $D = $script:Dash
    foreach ($g in @($ui.RunSegs, $ui.RunSegLabels)) { $g.Children.Clear(); $g.ColumnDefinitions.Clear() }
    for ($i = 0; $i -lt 5; $i++) {
        foreach ($g in @($ui.RunSegs, $ui.RunSegLabels)) { $cd = New-Object Windows.Controls.ColumnDefinition; $cd.Width = New-Object Windows.GridLength ([double]$D.Dur[$i]), 'Star'; [void]$g.ColumnDefinitions.Add($cd) }
        $bd = New-Object Windows.Controls.Border; $bd.CornerRadius = 4; $bd.Margin = '1,0'
        $bd.Background = if ($i -lt $D.Seg) { & $brush $Pal.Green } elseif ($i -eq $D.Seg) { $win.FindResource($(if ($i -eq 2) { 'GradMain' } else { 'GradCool' })) } else { & $brush $Pal.Line }
        [Windows.Controls.Grid]::SetColumn($bd, $i); [void]$ui.RunSegs.Children.Add($bd)
        $tb = New-Text $script:RunSegNames[$i] 10 $(if ($i -eq $D.Seg) { $Pal.Text } else { $Pal.Faint }) 'SemiBold'
        $tb.HorizontalAlignment = 'Center'; [Windows.Controls.Grid]::SetColumn($tb, $i); [void]$ui.RunSegLabels.Children.Add($tb)
    }
}
function Set-RootPhase([string]$Name, [int]$Seg, [int]$Len = 0) {
    $D = $script:Dash
    $D.Phase = $Name; $D.Seg = $Seg; $D.Since = Get-Date; if ($Len -gt 0) { $D.Len = $Len } elseif ($Seg -ge 0 -and $Seg -lt 4) { $D.Len = $D.Dur[$Seg] } else { $D.Len = 0 }
    $ui.RunPhase.Text = $Name
    Update-RootSegs
}
function Add-RunAlert([string]$Text, [string]$Hex) {
    $D = $script:Dash; if (-not $D) { return }
    $old = @($D.Alerts | Where-Object { $_.Text -eq $Text })
    foreach ($o in $old) { [void]$D.Alerts.Remove($o) }
    # user, oct. 18 2026: good news too (green = fixed / working), not only problems
    $good = $Hex -in @($Pal.Green, $Pal.Cyan)
    [void]$D.Alerts.Insert(0, [pscustomobject]@{ Text = $(if ($Hex -eq $Pal.Green) { [string][char]0x2714 + '  ' + $Text } else { $Text })
                                                 When = (Get-Date).ToString('h:mm:ss tt') + $(if ($old.Count) { '  (again)' } else { '' })
                                                 Edge = (& $brush $Hex); Good = $good
                                                 Bg = (& $brush $(switch ($Hex) { $Pal.Red { '#3A1E2C' } $Pal.Green { '#123B33' } $Pal.Cyan { '#0F3644' } default { '#3A2E14' } })) })
    # full: the oldest GOOD alert goes first, so a problem is never pushed out by good news
    while ($D.Alerts.Count -gt 12) {
        $drop = @($D.Alerts | Where-Object { $_.Good }) | Select-Object -Last 1
        if ($drop) { [void]$D.Alerts.Remove($drop) } else { $D.Alerts.RemoveAt($D.Alerts.Count - 1) }
    }
    $ui.RunAlerts.ItemsSource = $null; $ui.RunAlerts.ItemsSource = @($D.Alerts); $ui.RunAlertsNone.Visibility = 'Collapsed'
    Add-RunAlertSmart $Text $Hex    # gui\Alerts.ps1
}
function Update-RootNodes {
    $D = $script:Dash
    $byMac = @{}; foreach ($b in $script:Run.Plan.Full) { if ($b.Mac) { $byMac[([string]$b.Mac).ToLower()] = $b } }
    $mem = Get-MemberInfo
    $ui.RunNodes.ItemsSource = @($D.Rows | ForEach-Object {
        $m = $_.Mac.ToLower(); $b = $byMac[$m]; $k = $mem[(Get-ShortMac $m).ToLower()]
        $role = $_.Role.ToUpper()
        $roleHex = if ($role -match 'ROOT') { $Pal.Amber } elseif ($role -match 'BLACKHOLE') { $Pal.Red } elseif ($role -match 'WORMHOLE') { $Pal.Purple } else { $Pal.Blue }
        $ph = $_.PhaseName
        $phHex = switch -Regex ($ph) { 'BASELINE' { $Pal.Green } 'BLACKHOLE|WORMHOLE' { $Pal.Pink } 'COOLDOWN' { $Pal.Cyan } 'TERMINATE' { $Pal.Faint } default { $Pal.Dim } }
        [pscustomobject]@{ Hop = $_.Hop; HopBg = (& $brush $(if ($_.Hop -match '^H0+$') { $Pal.Amber } else { $Pal.Cyan }))
                           Name = $(if ($b) { $b.Label } elseif ($k) { $k.Nick } else { Get-ShortMac $m })
                           Sub = ("{0}   {1}   RSSI {2}   seen {3}s ago" -f $_.Mac, $(if ($k) { $k.Who } else { '' }), $_.Rssi, $_.Age)
                           Role = $role; RoleBg = (& $brush $roleHex); Phase = $ph; PhaseFg = (& $brush $phHex)
                           Export = $(if ($_.Export -eq 'SAFE') { 'SAFE' } else { '' }); ExportFg = (& $brush $Pal.Green); Tip = $_.Mac } })
}
function Read-RootLine([string]$Line) {
    $D = $script:Dash; if (-not $D) { return }
    $lvl = ''; $msg = $Line
    if ($Line -match '^(?<l>[IWED]) \(\d+\) [^:]+: ?(?<m>.*)$') { $lvl = $Matches.l; $msg = $Matches.m }
    $t = $msg.Trim()
    # phase banners
    if ($t -match '═{4,}\s*(?<n>.+?)\s*═{4,}') {
        $n = $Matches.n
        switch -Regex ($n) {
            'WAITING FOR ALL CHILDREN' { Set-RootPhase 'Waiting for every child' -1; $ui.RunGate.Text = 'Waiting for every child to join the mesh...' ; break }
            '^READY'                   { Set-RootPhase 'READY - press START' -1; $D.Ready = $true; Add-RunAlert 'Root is READY - every child is in and the setup checks passed. Press START.' $Pal.Green; $ui.RunGate.Text = 'READY. Check the mesh table on the right - move a board NOW if it is wrong - then press START.'; $ui.RunGate.Foreground = & $brush $Pal.Green
                                         Show-Toast 'Root is READY' 'Check the mesh, then press START.' ([string][char]0xE768) 'GradGood' { Show-Page 7 } 'Open the run'; break }
            'PHASE 0b'                 { Set-RootPhase 'Baseline window (burst)' 2 ; break }
            'PHASE 0'                  { Set-RootPhase 'Phase 0 - Baseline' 1; $ui.RunStart.IsEnabled = $false; $ui.RunStartAnyway.IsEnabled = $false; $ui.RunGate.Text = 'Started. Leave every board where it is until the end.'; $ui.RunGate.Foreground = & $brush $Pal.Green; Set-RunAlarm; break }
            'ATTACK'                   { Set-RootPhase 'Attack' 2; Add-RunAlert 'Attack phase started' $Pal.Cyan; break }
            'COOLDOWN'                 { Set-RootPhase 'Cooldown' 3; Add-RunAlert 'Cooldown started - the attack phase is over' $Pal.Cyan; break }
            'TERMINATE'                { Set-RootPhase 'Finished - TERMINATE sent' 4; $D.Ended = $true; Add-RunAlert 'Run finished - TERMINATE sent to every board' $Pal.Green
                                         Set-RunNow 'The run has finished' 'Wait for EXPORT: ALL BOARDS DONE (or about 20 s), then press "Finish + export root".' $Pal.Green ([string][char]0xE73E)
                                         Show-Toast 'Run finished' 'Export the root when the table says SAFE.' ([string][char]0xE73E) 'GradGood' { Show-Page 7 } 'Open the run'; break }
        }
        return
    }
    if ($t -match '\[CTRL\] Waiting (\d+) s for mesh to stabilise') { Set-RootPhase 'Stabilising the mesh' 0 ([int]$Matches[1]); return }
    if ($t -match '\[CTRL\] Starting PHASE 0 .*\((\d+) s\)') { $D.Len = [int]$Matches[1]; return }
    if ($t -match '\[CTRL\] Starting PHASE \d+ .*Attack \((\d+) s\)') { $D.Len = [int]$Matches[1]; return }
    if ($t -match '\[CTRL\] Starting PHASE 3 .*\((\d+) s\)') { $D.Len = [int]$Matches[1]; return }
    if ($t -match '\[CTRL\] WAITING: (\d+)/(\d+) children') { $ui.RunKids.Text = "$($Matches[1])/$($Matches[2])"; $ui.RunGate.Text = "Waiting for children: $($Matches[1]) of $($Matches[2]) in the mesh. A missing child is unpowered, brownout-looping or out of range."; $ui.RunGate.Foreground = & $brush $Pal.Amber; $ui.RunStartAnyway.IsEnabled = $true; return }
    if ($t -match '\[CTRL\] All (\d+) children are in, but (.+)$') { $ui.RunKids.Text = "$($Matches[1])/$($Matches[1])"; $ui.RunGate.Text = "All children are in, but $($Matches[2])"; $ui.RunGate.Foreground = & $brush $Pal.Amber; $ui.RunStartAnyway.IsEnabled = $true; return }
    if ($t -match '\[CTRL\] All (\d+) children in the mesh') {
        $ui.RunKids.Text = "$($Matches[1])/$($Matches[1])"
        if ($D.KidsOk -ne $Matches[1]) { $D.KidsOk = $Matches[1]; Add-RunAlert "All $($Matches[1]) children joined the mesh" $Pal.Green }
        return
    }
    if ($t -match '\[CTRL\] (?:\w+: )?(\d+)/(\d+) children in the mesh') { $ui.RunKids.Text = "$($Matches[1])/$($Matches[2])" }
    if ($t -match '\[CTRL\] READY') {
        $ui.RunStart.IsEnabled = $true; $ui.RunStartAnyway.IsEnabled = $true
        if ($t -match 'READY: (\d+)/(\d+) children') { $ui.RunKids.Text = "$($Matches[1])/$($Matches[2])" }
        if ($t -match 'wormhole: (.+)$') { $ui.RunGate.Text = "READY - wormhole: $($Matches[1])" }
        return
    }
    if ($t -match '\[CTRL\] START refused: (.+?)\. Fix') { $ui.RunGate.Text = "START refused (kept - it fires as soon as this is fixed): $($Matches[1])"; $ui.RunGate.Foreground = & $brush $Pal.Amber; Add-RunAlert "START refused: $($Matches[1])" $Pal.Amber; return }
    if ($t -match '\[CTRL\] START received') { Add-RunAlert 'START received - Phase 0 (baseline) is starting' $Pal.Green; $ui.RunGate.Text = 'START received - the run is starting.'; $ui.RunGate.Foreground = & $brush $Pal.Green; return }
    if ($t -match '\[CTRL\] START_ANYWAY') { Add-RunAlert $t $Pal.Red; return }
    # gui\BoardHealth.ps1 (oct. 20 2026): per-board SD / UART / liveness line from the root
    if ($t.StartsWith('NODESTAT ')) { try { [void](Read-BoardHealthLine $t) } catch { }; return }
    # the topology table
    if ($t -eq 'MESH TOPOLOGY') { $D.Collect = $true; $D.Rows.Clear(); $D.InTunnel = $false; return }
    if ($t -match '^TYPE\s+:\s+(.+)$') { $D.Topo.Type = $Matches[1]; return }
    if ($t -match '^NODE COUNT\s+:.*\((\d+)\)') { $D.Topo.Count = $Matches[1]; return }
    if ($t -match '^HOP DEPTH\s+:.*\((\d+)\)') { $D.Topo.Depth = $Matches[1]; return }
    if ($t -match '^REACHABLE\s+:.*\((\d+)\)') { $D.Topo.Reach = $Matches[1]; return }
    if ($t -match '^STATUS\s+:\s+(.+)$') {
        $s = $Matches[1]; $ui.RunTopoStatus.Text = $s
        if ($lvl -in @('E', 'W')) { $D.TopoBad = $true }
        elseif ($D.TopoBad) { $D.TopoBad = $false; Add-RunAlert "Mesh topology OK again ($s)" $Pal.Green }
        elseif (-not $D.TopoOkSaid) { $D.TopoOkSaid = $true; Add-RunAlert "Mesh topology OK ($s)" $Pal.Green }
        $ui.RunTopoBadge.Background = & $brush $(if ($lvl -eq 'E') { $Pal.Red } elseif ($lvl -eq 'W') { $Pal.Amber } else { $Pal.Green })
        $ui.RunTopoStatus.Foreground = & $brush '#0B1020'
        $ui.RunTopoInfo.Text = "{0}  -  {1} node(s), {2} hop(s) deep, {3} reachable" -f $D.Topo.Type, $D.Topo.Count, $D.Topo.Depth, $D.Topo.Reach
        return
    }
    if ($t -match '^DETAIL\s+:\s+(.+)$') { $ui.RunTopoDetail.Text = $Matches[1]; return }
    if ($t -match '^EXPORT\s+:\s+(.+)$') {
        $ui.RunTopoDetail.Text = ($ui.RunTopoDetail.Text + "`nexport: " + $Matches[1]).Trim()
        if ($Matches[1] -match 'ALL \d+ BOARDS DONE') { if (-not $script:Dash.ExportSaid) { $script:Dash.ExportSaid = $true; Add-RunAlert 'Every board is SAFE TO EXPORT' $Pal.Green }; $script:Dash.Ended = $true; Set-RunNow 'Every board says SAFE TO EXPORT' 'Press "Finish + export root".' $Pal.Green ([string][char]0xE73E) }
        return
    }
    if ($D.Collect -and $t -match '^(?<hop>H[0-9A-F-]+)\*?\s+(?<mac>(?:[0-9A-F]{2}:){5}[0-9A-F]{2})\s+(?<role>\S+)\s+(?<rssi>-?\d+|n/a)\s+0x[0-9A-F]{2}\s+(?<ph>\S+)\s+(?<age>\d+)\s+(?<exp>SAFE|not yet)') {
        [void]$D.Rows.Add([pscustomobject]@{ Hop = $Matches.hop; Mac = $Matches.mac; Role = $Matches.role; Rssi = $Matches.rssi; PhaseName = $Matches.ph; Age = $Matches.age; Export = $Matches.exp })
        return
    }
    if ($D.Collect -and $D.Rows.Count -and $t -notmatch '^HOP\s') { $D.Collect = $false; Update-RootNodes }
    # wormhole tunnel box
    if ($t -match '^WORMHOLE TUNNEL') { $D.InTunnel = $true; $D.Tunnel = @(); $ui.RunTunnelCard.Visibility = 'Visible'; return }
    if ($D.InTunnel) {
        if ($t -match '^(ENTRY|EXIT|Normal copy|Tunnel copy|Shortcut|OK: A)') { $D.Tunnel += $t; $ui.RunTunnel.Text = ($D.Tunnel -join "`n"); $ui.RunTunnel.Foreground = & $brush $(if ($t -match 'NONE') { $Pal.Red } else { $Pal.Text }) }
        if ($t -match '^EXPOSURE') { $D.InTunnel = $false }
    }
    if ($t -match '^!!\s*(.+)$') { Add-RunAlert $Matches[1] $(if ($lvl -eq 'W') { $Pal.Amber } else { $Pal.Red }) }
    if ($t -match '^!!.*UART') { $D.RootUartBad = $true }
    elseif ($D.RootUartBad -and $t -match 'UART OK') { $D.RootUartBad = $false; Add-RunAlert 'Wormhole UART tunnel fixed - the root sees UART OK' $Pal.Green }
}
function Read-BoardLine([string]$Line) {
    # every board: alerts and "booted" - the root also feeds its dashboard
    $R = $script:Run; $b = $R.Current.Board
    Read-PreStartLine $b $Line    # gui\PreStart.ps1
    if ($Line -match '^\[monitor\] listening') {
        $R.Phase = 'monitor'; $R.Current.Note = 'running'
        $ui.RunCmd.IsEnabled = $true; $ui.RunSend.IsEnabled = $true
        if ($b.Role -eq 'root') {
            Set-RunState 'ROOT RUNNING' $Pal.Green
            Set-RunNow 'The root is running - watch the dashboard' 'It waits for every child, checks the setup, then shows READY: check the mesh and press START. When it says TERMINATE / SAFE, press "Finish + export root".' $Pal.Green ([string][char]0xE768)
            Set-RunButtons -Next 'Finish + export root  ->' -Abort $true -SkipBox $true
        } else {
            Set-RunState "$($b.Label.ToUpper()) RUNNING" $Pal.Green
            Set-RunNow ("{0} is booting" -f $b.Label) 'Move on once it prints its STARTING banner. Before the root is up a child spams "fail to find a network" - that is normal, not stuck.' $Pal.Cyan ([string][char]0xE768)
            Set-RunButtons -Next 'Done with this board  ->' -Abort $true -SkipBox ($R.Settings.Child -eq 'export')
        }
        Update-RunSteps
        return
    }
    if ($Line -match '^\[monitor\] LOST') { Add-RunAlert ("{0}: {1}" -f $b.Label, ($Line -replace '^\[monitor\] ', '')) $Pal.Red }
    if ($Line -match '\[monitor\] could not open') { $hold = Get-PortHolderText ([string]$b.Port); Add-RunAlert ("{0}: {1}{2}" -f $b.Label, $Line, $(if ($hold) { " - $($b.Port) is $hold" } else { '' })) $Pal.Red }
    # oct. 20 2026: the banner prints right after the flash, often BEFORE the monitor opens
    # (run.ps1's location/scenario check runs first, ~10 s, and may restart the board), so
    # the GUI never saw it and never moved on. A firmware log line from >= 5 s of uptime
    # (not the bootloader) also proves the child's firmware is running.
    $lateBoot = $false
    if (-not $R.Booted -and $b.Role -ne 'root' -and $R.Phase -eq 'monitor' -and
        $Line -match '(?:^|[\sm])[IWE] \((\d+)\) ([\w-]+):' -and [int64]$Matches[1] -ge 5000 -and
        $Matches[2] -notmatch '^(boot|esp_image|cpu_start|heap_init|spi_flash|app_init)$') {
        $lateBoot = $true
        Write-RunConsole ("  {0}: its STARTING banner came before the monitor opened - its firmware is running (log at {1} s uptime)" -f $b.Label, [int]([int64]$Matches[1] / 1000)) $Pal.Faint
    }
    if (-not $R.Booted -and ($lateBoot -or $Line -match '=== .*STARTING')) {
        $R.Booted = $true
        if ($script:Dash) { Add-RunAlert ("{0} booted and is running" -f $b.Label) $Pal.Green }
        if ($b.Role -ne 'root') {
            $R.Current.Note = 'booted'
            Set-RunNow ("{0} booted" -f $b.Label) 'Press "Done with this board" to flash the next one.' $Pal.Green ([string][char]0xE73E)
            Update-RunSteps
            if ($ui.RunAutoNext.IsChecked) { $R | Add-Member -NotePropertyName AutoAt -NotePropertyValue ((Get-Date).AddSeconds(3)) -Force }
        }
    }
    # location.txt (oct. 18 2026): run.ps1 fixes it before the flash; the boot
    # report is the proof. A card that still disagrees files the whole run under
    # the wrong site, so fix it from here and say exactly what to do.
    if ($Line -match '^LOCATION_CHECK: FIXED (.+)$') { Add-RunAlert ("{0}: location.txt {1}" -f $b.Label, $Matches[1]) $Pal.Cyan }
    elseif ($Line -match '^LOCATION_CHECK: (UNKNOWN|FAILED)') { Add-RunAlert ("{0}: could not check location.txt before the flash - checking at boot instead" -f $b.Label) $Pal.Amber }
    elseif ($Line -match 'Recorded location: (\S+)') {
        $want = [string]$R.Plan.Location; $have = $Matches[1]
        if ($want -and $have -ne $want) {
            Send-RunCommand "SET_LOCATION=$want"
            Add-RunAlert ("{0}: its card records '{1}', not '{2}' - location.txt rewritten. POWER-CYCLE {0} now (before START), or its SD data is filed under {1}" -f $b.Label, $have, $want) $Pal.Red
            Show-Toast 'Wrong location on a card' ("{0} records {1}, the run is {2}. Fixed - power-cycle {0} before START." -f $b.Label, $have, $want) ([string][char]0xE783) 'GradMain'
        }
    }
    if ($Line -match 'Writing at 0x[0-9a-f]+\.\.\. \((\d+) ?%\)') { $R.Current.Note = "flashing $($Matches[1])%"; Update-RunSteps }
    elseif ($Line -match '(?i)Erasing flash \(this may take a while\)') { $R.Current.Note = 'full erase...'; Update-RunSteps }
    if ($b.Role -eq 'root') { Read-RootLine $Line }
    elseif ($Line -match '!! (UART TUNNEL [^:]+)') { if ($script:Dash) { $script:Dash["Uart$($b.Label)"] = 'bad'; Add-RunAlert ("{0}: {1}" -f $b.Label, $Matches[1]) $Pal.Red } }
    elseif ($script:Dash -and $Line -match 'UART OK' -and $script:Dash["Uart$($b.Label)"] -ne 'ok') {
        $was = $script:Dash["Uart$($b.Label)"]; $script:Dash["Uart$($b.Label)"] = 'ok'
        Add-RunAlert ("{0}: UART tunnel {1}" -f $b.Label, $(if ($was -eq 'bad') { 'FIXED - it works both ways now' } else { 'OK - it works both ways' })) $Pal.Green
    }
}
function Set-RunAlarm {
    # mobility / powercycle: the human step, timed from the Phase 0 banner
    $R = $script:Run; $c = $R.Plan
    if ($c.Scenario -notin @('mobility', 'powercycle') -or -not $c.Target -or -not $c.Target.Port) { return }
    $base = (Get-PhaseDurations).Baseline
    $wait = if ($c.Attack -ne 'none') { $base + 10 } else { [int]($base / 2) }
    $R.Alarm = @{ At = (Get-Date).AddSeconds($wait); Text = $(if ($c.Scenario -eq 'mobility') { "MOVE $($c.Target.Label) to its second spot NOW - once, then leave it powered." } else { "UNPLUG $($c.Target.Label) for ~10 s, then plug it back in - NOW, once." }) }
    $ui.RunPhaseNote.Text = ("{0} at {1}" -f $c.Scenario, $R.Alarm.At.ToString('h:mm:ss tt'))
}

# ── buttons ──────────────────────────────────────────────────────────────────
$ui.RunRepMinus.Add_Click({ $n = 1; [void][int]::TryParse($ui.RunRepeat.Text, [ref]$n); $ui.RunRepeat.Text = [string][Math]::Max(1, $n - 1) })
$ui.RunRepPlus.Add_Click({ $n = 1; [void][int]::TryParse($ui.RunRepeat.Text, [ref]$n); $ui.RunRepeat.Text = [string]($n + 1) })
$ui.RunRepeat.Add_TextChanged({ Set-SnifferFromRun })   # sniffer file follows the repeat number
$ui.RunBuild.Add_Click({ if ($script:Run) { Start-RunBuild } })
$ui.RunGo.Add_Click({
    $R = $script:Run; if (-not $R) { return }
    $boards = @($R.Steps | Where-Object Kind -eq 'board')
    if ($ui.DryRun.IsChecked) {
        Build-RunParams
        Write-RunConsole '' ; Write-RunConsole 'DRY RUN - exact commands that would run:' $Pal.Amber
        foreach ($b in $boards) { Write-RunConsole ("  .\run.ps1 " + (Format-RunParams $b.Plan)) $Pal.Dim }
        Write-RunConsole 'Nothing was flashed.' $Pal.Amber; return
    }
    $done = @($boards | Where-Object State -eq 'ok')
    if ($done.Count -and $R.Phase -ne 'done') {
        $ans = [Windows.MessageBox]::Show(("{0} board(s) are already flashed and running: {1}`n`nYes = RESUME - flash only the {2} board(s) not done yet`nNo = start over and flash every board again" -f $done.Count, (@($done | ForEach-Object { $_.Board.Label }) -join ', '), ($boards.Count - $done.Count)), 'Resume the run?', 'YesNoCancel', 'Question')
        if ($ans -eq 'Cancel') { return }
        if ($ans -eq 'Yes') {
            foreach ($x in @($R.Steps | Where-Object { $_.Kind -in @('park', 'board') -and $_.State -ne 'ok' })) { $x.State = 'waiting'; $x.Note = '' }
            # a board skipped earlier is 'waiting' again and WILL be flashed, so
            # it counts for the root again - else the root expects one child too
            # few and can start Phase 0 without it
            $R.Skipped = 0
            $ui.RunSetup.IsEnabled = $false
            Start-RunBuild -ThenGo; return
        }
        foreach ($x in @($R.Steps | Where-Object { $_.Kind -in @('park', 'board') })) { $x.State = 'waiting'; $x.Note = '' }
        $R.Used = @{}; $R.Skipped = 0
    }
    $list = ($boards | ForEach-Object { "    {0,-8} {1,-7} {2}" -f $_.Board.Label, $_.Board.Port, (Get-RunRoleLook $_.Board.Kind $_.Board.Role).Text }) -join "`n"
    if (-not (Confirm-Action ("This ERASES and flashes {0} board(s), children first, root last:`n`n{1}`n`nEvery child must already be on its final power and spot. Start?" -f $boards.Count, $list) 'Wipe + flash + run')) { return }
    $ui.RunSetup.IsEnabled = $false
    # always through the compile step: unchanged variants are skipped in a
    # second, and a compile error stops it BEFORE any board is erased
    Start-RunBuild -ThenGo
})
$ui.RunCli.Add_Click({
    $R = $script:Run; if (-not $R) { return }
    Start-ConsoleWindow -Script (Join-Path $base 'run_wizard.ps1') -ScriptArgs (@('-Preset', "'$($R.Plan.Preset.Path)'") + (Get-WizardArgs)) -Title ("Capture: {0}" -f $R.Plan.Preset.File)
})
$ui.RunNext.Add_Click({
    $R = $script:Run; if (-not $R) { return }
    if ($R.Phase -eq 'done') {
        Show-Page 2
        Update-Cells
        Select-Cell (@($script:Cells | Where-Object Text -eq ('{0}  /  {1}  /  {2}  /  {3}' -f $R.Dirs.AttackDir, $R.Dirs.TopoDir, $R.Plan.Location, $R.Plan.Scenario)) | Select-Object -First 1)
        return
    }
    if ($R.Phase -eq 'buildfail') { Start-RunBuild -Only $R.Failed -ThenGo:$R.GoAfterBuild; return }
    if ($R.Phase -eq 'pick' -and $R.Picked) { Start-RunBuild -Only @($R.Picked.Board.Label); return }
    if ($R.Phase -eq 'boardfail' -and $R.Failed) {
        $st = $R.Failed; $R.Failed = $null; $st.State = 'waiting'; $st.Note = 'retrying'
        $R.Phase = 'boards'; $R.Used.Remove([string]$st.Board.Port)
        Start-RunStep $st; return
    }
    if ($R.Phase -ne 'monitor') { return }
    $b = $R.Current.Board
    if ($b.Role -eq 'root' -and -not $script:Dash.Ended) {
        if (-not (Confirm-Action "The root has not finished yet (no TERMINATE / SAFE seen).`n`nFinishing now ends its monitor and exports what it has so far - a SHORT run.`n`nFinish the root now?" 'Finish the root early')) { return }
    }
    Stop-RunMonitor -NoExport:([bool]$ui.RunSkipExport.IsChecked)
})
$ui.RunContinue.Add_Click({
    $R = $script:Run; if (-not $R) { return }
    if ($R.Phase -eq 'done') {
        if (Start-CollectChildren) { return }    # gui\Collect.ps1 - $false = no child plugged in: open Import as before
        $ui.ImpScenario.SelectedItem = $R.Plan.Scenario; $ui.ImpRepeat.Text = [string]$R.Settings.Repeat
        Set-ImpPick $R.Plan.Attack $R.Plan.Topology $R.Plan.Location
        $script:ImpRosterWant = $R.Plan.Preset.Path
        Open-Import; return
    }
    if ($R.Wait -and $R.Wait.Kind -eq 'swap') { $R.Wait = @{ Kind = 'swapok' }; $st = $R.Current; $st.State = 'waiting'; Start-RunStep $st; return }
    if ($R.Phase -eq 'buildfail') {
        $log = @($R.Builds | Where-Object { $_.State -eq 'failed' -and $_.Log } | ForEach-Object Log)[0]
        if ($log -and (Test-Path $log)) { Start-Process notepad $log }
        return
    }
    if ($R.Phase -eq 'boardfail' -and $R.Failed) {
        # skip it: one child fewer for the root's roster gate
        $st = $R.Failed; $R.Failed = $null
        if (-not (Confirm-Action ("Go on WITHOUT {0}?`n`nThe root will then wait for one child fewer. Note it for this run (the capture has one board less than the preset)." -f $st.Board.Label) 'Skip a board')) { $R.Failed = $st; return }
        $st.State = 'skipped'; $st.Note = 'skipped by you'; $R.Skipped++
        $root = @($R.Steps | Where-Object { $_.Kind -eq 'board' -and $_.Board.Role -eq 'root' })[0]
        if ($root -and $root.Plan.ExpectedChildren -gt 0) { $root.Plan.ExpectedChildren = [int]$root.Plan.ExpectedChildren - 1 }
        Write-RunConsole ("  {0} skipped - the root now waits for {1} child(ren)" -f $st.Board.Label, $(if ($root) { $root.Plan.ExpectedChildren } else { '-' })) $Pal.Amber
        $R.Phase = 'boards'
        Start-RunStep ($R.Steps | Where-Object { $_.Kind -eq 'board' -and $_.State -eq 'waiting' } | Select-Object -First 1); return
    }
})
# click a board in STEPS: its own actions (not during a run)
$ui.RunSteps.Add_PreviewMouseLeftButtonUp({
    param($sender, $e)
    $R = $script:Run; if (-not $R -or $R.Active) { return }
    $dc = $e.OriginalSource.DataContext; if (-not $dc -or $null -eq $dc.Index) { return }
    $st = $R.Steps[[int]$dc.Index]; if ($st.Kind -ne 'board') { return }
    $R.Picked = $st; $R.Phase = 'pick'
    $b = $st.Board
    $ent = if ($R.Builds) { @($R.Builds | Where-Object { $_.Labels -contains $b.Label })[0] } else { $null }
    $txt = '{0}   {1}   {2}' -f $b.Port, $(if ($b.Mac) { $b.Mac.ToUpper() } else { 'MAC ?' }), $b.Display
    if ($ent -and $ent.State -eq 'failed' -and $ent.Err) { $txt += "`nLast compile error:  $($ent.Err)" }
    elseif ($ent -and $ent.Labels.Count -gt 1) { $txt += "`nSame firmware as: $(@($ent.Labels | Where-Object { $_ -ne $b.Label }) -join ', ') (compiled once for all of them)" }
    Set-RunNow ("{0}  -  {1}" -f $b.Label, (Get-RunRoleLook $b.Kind $b.Role).Text) $txt $Pal.Cyan $st.Glyph
    Set-RunButtons -Next ("Recompile only {0}  ->" -f $b.Label) -Abort $false
})
$ui.RunAbort.Add_Click({
    $R = $script:Run; if (-not $R) { return }
    if ($R.Phase -eq 'export') { [void][Windows.MessageBox]::Show('An export is running - it must finish (cutting one blue-screens this laptop).', 'Wait'); return }
    if (-not (Confirm-Action 'Stop the run? Boards already flashed keep running; nothing more is exported.' 'Stop the run')) { return }
    if ($R.Phase -eq 'monitor') { Stop-RunMonitor -NoExport; $R.Phase = 'stopping'; return }
    if ($R.Phase -eq 'pflash' -and $R.PF -and $R.PF.Jobs.Count) {
        # gui\ParallelFlash.ps1: boards are being written - never cut them, stop once they finish
        [void][Windows.MessageBox]::Show(("{0} board(s) are being written right now - cutting that leaves them half-flashed. The run stops as soon as they finish (no new board is started)." -f $R.PF.Jobs.Count), 'Stopping after these boards')
        $R | Add-Member -NotePropertyName StopAfterFlash -NotePropertyValue $true -Force; return
    }
    if ($R.Proc -and -not $R.Proc.HasExited) {
        if ($R.Phase -eq 'build') {
            # compiling touches no board - safe to cut
            $R.BuildQueue.Clear(); $R.Phase = 'stopping'
            & taskkill.exe /PID $R.Proc.Id /T /F 2>$null | Out-Null; return
        }
        # flashing / parking / waking talks to a board: never cut it, stop right after
        [void][Windows.MessageBox]::Show('A board is being written to right now - cutting that leaves it half-flashed. The run stops as soon as this step ends.', 'Stopping after this step')
        $R | Add-Member -NotePropertyName StopAfterFlash -NotePropertyValue $true -Force; return
    }
    Finish-RunStopped
})
$ui.RunCleanFix.Add_Click({
    # wipe ONLY the failed variants' build folders (generated output, safe to delete), then recompile them
    $R = $script:Run; if (-not $R -or $R.Phase -ne 'buildfail' -or -not $R.Builds) { return }
    foreach ($e in @($R.Builds | Where-Object State -eq 'failed')) {
        if ($e.Key -and (Test-Path $e.Key) -and (Split-Path $e.Key -Leaf) -like 'build_*') {
            Write-RunConsole ("  clean: removing {0}" -f $e.Key) $Pal.Amber
            Remove-Item -Recurse -Force $e.Key -ErrorAction SilentlyContinue
        }
    }
    Start-RunBuild -Only $R.Failed -ThenGo:$R.GoAfterBuild
})
$ui.RunAgain.Add_Click({
    # same preset, next repeat number, same answers - straight back to setup
    $R = $script:Run; if (-not $R -or $R.Active) { return }
    $next = $R.Settings.Repeat + 1
    $post = @($ui.RunPostAnalyze.IsChecked, $ui.RunPostTrim.IsChecked, $ui.RunPostNone.IsChecked); $child = $ui.RunChildExport.IsChecked
    Open-RunPage $R.Plan.Preset
    $ui.RunRepeat.Text = [string]$next
    $ui.RunPostAnalyze.IsChecked = $post[0]; $ui.RunPostTrim.IsChecked = $post[1]; $ui.RunPostNone.IsChecked = $post[2]; $ui.RunChildExport.IsChecked = $child; $ui.RunChildSkip.IsChecked = -not $child
    Set-Status "Repeat $next loaded - compile, then wipe + flash + run." $Pal.Green
})
$ui.RunStart.Add_Click({ if (Confirm-PreStart) { Send-RunCommand 'START' } })
$ui.RunStartAnyway.Add_Click({
    if (Confirm-Action "START_ANYWAY overrides every safety gate (missing children, a broken wormhole setup).`n`nUse it only when a board is truly gone - the run is then short or not set up, and must be reported that way.`n`nSend START_ANYWAY?" 'Override the gates') { Send-RunCommand 'START_ANYWAY' }
})
$ui.RunSend.Add_Click({ $t = ([string]$ui.RunCmd.Text).Trim(); if ($t) { Send-RunCommand $t; $ui.RunCmd.Text = '' } })
$ui.RunCmd.Add_KeyDown({ param($s, $e) if ($e.Key -eq 'Return') { $t = ([string]$ui.RunCmd.Text).Trim(); if ($t) { Send-RunCommand $t; $ui.RunCmd.Text = '' }; $e.Handled = $true } })

# ── the run's heartbeat ──────────────────────────────────────────────────────
$runTimer = New-Object Windows.Threading.DispatcherTimer
$runTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$runTimer.Add_Tick({ Measure-GuiTick 'run' {   # gui\Perf.ps1: a tick over 150 ms is logged
    $R = $script:Run; if (-not $R) { return }
    Update-PreStartClock
    if ($R.Started -and $R.Active) { $e = (Get-Date) - $R.Started; $ui.RunClock.Text = '{0}:{1:00}' -f [int][Math]::Floor($e.TotalMinutes), $e.Seconds }
    $D = $script:Dash
    if ($D -and $D.Since -and $D.Len -gt 0) {
        $left = $D.Len - [int]((Get-Date) - $D.Since).TotalSeconds
        $ui.RunPhaseLeft.Text = if ($left -gt 0) { '{0}:{1:00}' -f [int][Math]::Floor($left / 60), ($left % 60) } else { '' }
    } elseif ($D) { $ui.RunPhaseLeft.Text = '' }
    # the setup card is only for before a run - it folds away while one goes
    $want = if ($R.Active -or $R.Phase -eq 'done') { 'Collapsed' } else { 'Visible' }
    if ($ui.RunSetup.Visibility -ne $want) { $ui.RunSetup.Visibility = $want }
    if ($R.Alarm -and (Get-Date) -ge $R.Alarm.At) {
        $txt = $R.Alarm.Text; $R.Alarm = $null
        [console]::Beep(880, 300)
        Set-RunNow $txt 'Write down the exact time you did it.' $Pal.Pink ([string][char]0xE7BA)
        Show-Toast 'Your move!' $txt ([string][char]0xE7BA) 'GradMain'
        Add-RunAlert ("{0}  ({1})" -f $txt, (Get-Date).ToString('h:mm:ss tt')) $Pal.Amber
    }
    if ($R.Wait -and $R.Wait.Kind -eq 'port') {
        $st = $R.Wait.Step; $b = $st.Board
        $mac = ([string]$b.Mac).ToLower()
        $hit = $null
        foreach ($k in @($script:Live.Keys)) { if ($mac -and ([string]$script:Live[$k].Mac).ToLower() -eq $mac) { $hit = $k } }
        if (-not $hit) { $hit = @($script:Live.Keys | Where-Object { $R.Wait.Known -notcontains $_ -and -not $R.Used.ContainsKey($_) }) | Select-Object -First 1 }
        if ($hit) {
            Write-RunConsole ("  {0} found on {1}" -f $b.Label, $hit) $Pal.Green
            $b.Port = $hit; $st.Sub = ('{0}   {1}' -f $hit, $(if ($b.Mac) { Get-ShortMac $b.Mac } else { 'MAC ?' })); $st.State = 'waiting'; $R.Wait = $null
            Start-RunStep $st
        }
        return
    }
    Read-CrashWatch
    # a banner seen while the monitor was still opening keeps its move-on pending (oct. 20 2026)
    if ($R.AutoAt -and (Get-Date) -ge $R.AutoAt -and $R.Phase -ne 'flash') { $R.AutoAt = $null; if ($R.Phase -eq 'monitor' -and $R.Current.Board.Role -ne 'root') { Stop-RunMonitor } }
    try { Update-BoardHealth } catch { }    # gui\BoardHealth.ps1: redraws at most every 2 s, only on change
    if ($R.Phase -eq 'pflash') { try { Step-ParallelFlash } catch { Write-RunConsole ("  parallel flash: {0}" -f $_.Exception.Message) $Pal.Red }; return }   # gui\ParallelFlash.ps1
    if (-not $R.Proc) { return }
    $lines = Read-RunOutput
    if ($lines.Count) {
        Write-RunConsole ($lines -join "`n")
        if ($R.Current -and $R.Current.Kind -eq 'board') { foreach ($l in $lines) { Read-BoardLine $l } }
        elseif ($R.Current -and $R.Current.Kind -eq 'build') { foreach ($l in $lines) { Read-BuildLine $l } }
        if ($R.StopAfterFlash -and $R.Phase -eq 'monitor') { $R.StopAfterFlash = $false; Stop-RunMonitor -NoExport; $R.Phase = 'stopping' }
    }
    if ($R.Proc.HasExited) {
        $p = $R.Proc; $R.Proc = $null
        Start-Sleep -Milliseconds 80
        $lines = @(Read-RunOutput)
        foreach ($k in 'BufO', 'BufE') { if ($R.$k) { $lines += ($R.$k -replace "\x1b\[[0-9;]*m", ''); $R.$k = '' } }
        $lines = @($lines | Where-Object { $_ -notmatch '^#< CLIXML|^<Objs ' })
        if ($lines.Count) {
            Write-RunConsole ($lines -join "`n")
            if ($R.Current -and $R.Current.Kind -eq 'board') { foreach ($l in $lines) { Read-BoardLine $l } }
            elseif ($R.Current -and $R.Current.Kind -eq 'build') { foreach ($l in $lines) { Read-BuildLine $l } }
        }
        Remove-Item $R.Out, $R.Err -ErrorAction SilentlyContinue
        $ui.RunCmd.IsEnabled = $false; $ui.RunSend.IsEnabled = $false
        $code = $p.ExitCode
        Write-RunConsole ("  finished (exit {0})" -f $code) $(if ($code -eq 0) { $Pal.Green } else { $Pal.Amber })
        if ($R.Current) { Complete-RunStep $code }
    }
} })
$runTimer.Start()

# ── SPEED-UPS (oct. 17 2026): remember me, Ctrl+K, shortcuts, next-step toasts ─
# Per-laptop conveniences only (who you are, last page) - %LOCALAPPDATA%, never
# the repo, so teammates' laptops are not affected.
$script:SettingsPath = Join-Path $env:LOCALAPPDATA 'NIS16\gui.json'
$script:Settings = @{ Me = ''; Page = 0; Zoom = 0 }
try {
    if (Test-Path $script:SettingsPath) {
        $j = Get-Content $script:SettingsPath -Raw | ConvertFrom-Json
        foreach ($k in 'Me', 'Page', 'Zoom', 'PFlash') { if ($j.PSObject.Properties[$k]) { $script:Settings[$k] = $j.$k } }
    }
} catch { }
$script:Me = [string]$script:Settings.Me
function Save-Settings {
    if ($SelfTest) { return }
    try {
        New-Item -ItemType Directory -Force (Split-Path $script:SettingsPath) | Out-Null
        [pscustomobject]$script:Settings | ConvertTo-Json | Set-Content -Path $script:SettingsPath -Encoding UTF8
    } catch { }
}
$win.Add_Closing({
    param($sender, $e)
    $R = $script:Run
    # an SD read / flash over USB keeps running without the window - and the
    # user, seeing nothing, unplugs mid-read: the CP210x blue-screen trigger
    if ($script:Stream -and $script:Stream.NoStop -and -not $script:Stream.Proc.HasExited -and -not $SelfTest) {
        [void][Windows.MessageBox]::Show(("'{0}' is reading from or writing to a board right now. Wait for it to finish before closing - do NOT unplug that board." -f $script:Stream.Title), 'Board busy')
        $e.Cancel = $true; return
    }
    if ($R -and $R.Active -and -not $SelfTest) {
        if ($R.Phase -eq 'export') {
            [void][Windows.MessageBox]::Show('A board is exporting right now. Wait for it to finish before closing (it would keep going without this window, but you could not see it end).', 'Export running')
            $e.Cancel = $true; return
        }
        if (-not (Confirm-Action "A capture is running on the Live run page.`n`nClosing the window does NOT stop the boards, but you lose the buttons (START, done with this board) and the dashboard.`n`nClose anyway?" 'Run in progress')) { $e.Cancel = $true; return }
    }
    Stop-CrashWatch
    $script:Settings.Page = $ui.Pages.SelectedIndex; Save-Settings
})

# "I am": member names from member_boards.json
try { $ui.MePick.ItemsSource = @((Get-Content (Join-Path $base 'member_boards.json') -Raw | ConvertFrom-Json).members | ForEach-Object name) } catch { }
if ($script:Me) { $ui.MePick.SelectedItem = $script:Me }
$ui.MePick.Add_SelectionChanged({
    $script:Me = [string]$ui.MePick.SelectedItem; $script:Settings.Me = $script:Me; Save-Settings
    if ($script:Presets -and @($ui.OwnerPick.ItemsSource) -contains $script:Me) { $ui.OwnerPick.SelectedItem = $script:Me }
    Show-Toast "Hi $($script:Me)!" 'Your presets are shown first and new presets are saved under your name.' ([string][char]0xE77B) 'GradMain'
})
$searchTimer = New-Object Windows.Threading.DispatcherTimer
$searchTimer.Interval = [TimeSpan]::FromMilliseconds(250)
$searchTimer.Add_Tick({ $searchTimer.Stop(); if ($script:Presets) { Update-PresetGrid } })
$ui.PresetSearch.Add_TextChanged({
    $ui.PresetSearchHint.Visibility = $(if ($ui.PresetSearch.Text) { 'Collapsed' } else { 'Visible' })
    $searchTimer.Stop(); $searchTimer.Start()
})

# sidebar badges (live counts next to the page names)
$script:NavText = @{ NavHome = 'Home'; NavCapture = 'Run a capture'; NavVerify = 'Verify & analyse'; NavCampaign = 'Campaign'
                     NavBoards = 'Boards'; NavData = 'Data'; NavWire = 'Wireshark & sniffer'; NavRun = 'Live run' }
function Set-NavBadge([string]$Nav, [string]$Text, [string]$Hex) {
    $sp = New-Object Windows.Controls.StackPanel; $sp.Orientation = 'Horizontal'
    [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $script:NavText[$Nav]; VerticalAlignment = 'Center' }))
    if ($Text) {
        $b = New-Object Windows.Controls.Border; $b.CornerRadius = 8; $b.Padding = '7,0'; $b.Margin = '8,0,0,0'; $b.VerticalAlignment = 'Center'
        $b.Background = & $brush ($Hex -replace '#', '#40')
        $b.Child = New-Object Windows.Controls.TextBlock -Property @{ Text = $Text; FontSize = 11; FontWeight = 'Bold'; Foreground = (& $brush $Hex) }
        [void]$sp.Children.Add($b)
    }
    $ui[$Nav].Content = $sp
}
$script:BadgeKey = ''
function Update-NavBadges {
    $redo = @($script:Redo.Values | Where-Object { $_.planned -and $_.severity -eq 'REDO' }).Count
    $boards = @($script:Live.Values | Where-Object { $_.Kind -ne 'BLOCKED' }).Count
    $runs = @($script:Captures | Where-Object { -not $_.Proc.HasExited }).Count
    $live = if ($script:Run -and $script:Run.Active) { 'LIVE' } elseif ($script:Run -and $script:Run.Phase -eq 'done') { 'done' } else { '' }
    # trim reminder (oct. 20 2026): runs whose trimmed\ copy is missing or out of date -
    # recounted at most once a minute (a top-level folder listing)
    if (-not $script:TrimCountAt -or ((Get-Date) - $script:TrimCountAt).TotalSeconds -ge 60) {
        $script:TrimCountAt = Get-Date
        try { $script:TrimTodoCount = @(Get-ExportCells | Where-Object { $_.Look -ne 'done' }).Count } catch { }
    }
    $trimTodo = [int]$script:TrimTodoCount
    $key = "$redo|$boards|$runs|$live|$trimTodo"
    if ($key -eq $script:BadgeKey) { return }
    $script:BadgeKey = $key
    Set-NavBadge 'NavCampaign' $(if ($redo) { "$redo redo" } else { '' }) $Pal.Red
    Set-NavBadge 'NavData' $(if ($trimTodo) { "$trimTodo to trim" } else { '' }) $Pal.Amber
    Set-NavBadge 'NavBoards' $(if ($boards) { [string]$boards } else { '' }) $Pal.Green
    Set-NavBadge 'NavCapture' $(if ($runs) { "$runs running" } else { '' }) $Pal.Pink
    Set-NavBadge 'NavRun' $live $(if ($live -eq 'LIVE') { $Pal.Pink } else { $Pal.Green })
}

# next-step watchers: SD card inserted -> import; capture window closed -> import
$script:Drives = $null
function Get-RemovableDrives { @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Removable' -and $_.IsReady } | ForEach-Object { $_.Name.TrimEnd('\') }) }
function Open-Import([string]$Drive) {
    Show-Page 5; $ui.DataTabs.SelectedIndex = 0
    Update-Cards
    if ($Drive) {
        $ui.SrcCard.IsChecked = $true
        $hit = @($ui.CardPick.ItemsSource | Where-Object { $_.Root.TrimEnd('\') -eq $Drive.TrimEnd('\') })
        if ($hit.Count) { $ui.CardPick.SelectedItem = $hit[0] }
        $ui.ImpList.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    }
}
$stepTimer = New-Object Windows.Threading.DispatcherTimer
$stepTimer.Interval = [TimeSpan]::FromSeconds(2)
$stepTimer.Add_Tick({ Measure-GuiTick 'step' {   # gui\Perf.ps1: a tick over 150 ms is logged
    try {
        $now = Get-RemovableDrives
        if ($null -ne $script:Drives) {
            foreach ($d in @($now | Where-Object { $script:Drives -notcontains $_ })) {
                $script:NewDrive = $d
                Show-Toast "SD card inserted ($d)" 'Bring its captures in?' ([string][char]0xE896) '#B45309' -Action { Open-Import $script:NewDrive } -ActionText 'List the files on it'
            }
        }
        $script:Drives = $now
        foreach ($c in @($script:Captures | Where-Object { $_.Proc.HasExited -and -not $_.Told })) {
            $c | Add-Member -NotePropertyName Told -NotePropertyValue $true -Force
            Show-Toast 'Capture window closed' "$($c.Title -replace '^Capture:\s*', '') - next: import the SD cards, then analyse." ([string][char]0xE73E) 'GradMain' -Action { Open-Import $null } -ActionText 'Go to Import'
        }
        Update-NavBadges
    } catch { }
} })

# Ctrl+K palette: pages, actions, presets, campaign runs, analysed cells
function New-PalItem($Kind, $Title, $Sub, $Glyph, $Hex, $Type, $Data) {
    [pscustomobject]@{ Kind = $Kind; Title = $Title; Sub = $Sub; Glyph = [string]$Glyph
                       IconBg = (& $brush ($Hex -replace '#', '#33')); IconFg = (& $brush $Hex); Type = $Type; Data = $Data
                       Hay = ("$Kind $Title $Sub").ToLower() }
}
function Get-PalItems {
    $it = New-Object System.Collections.ArrayList
    $pages = @(@('Home', 0xE80F), @('Run a capture', 0xE768), @('Verify & analyse', 0xE73E), @('Campaign', 0xE787), @('Boards', 0xE88E), @('Data', 0xE8B7), @('Wireshark & sniffer', 0xE701), @('Live run', 0xE945))
    for ($i = 0; $i -lt $pages.Count; $i++) { [void]$it.Add((New-PalItem 'page' $pages[$i][0] "Ctrl+$($i + 1)" ([char]$pages[$i][1]) $Pal.Accent 'page' $i)) }
    foreach ($a in @(
        @('Start the next capture', 'campaign run order', 0xE768, 'next'), @('New preset', 'Ctrl+N - plugged boards are added for you', 0xE710, 'newpreset'),
        @('Read all MACs', 'identify every plugged board', 0xE88E, 'readmacs'), @('Re-check the redo list', 'campaign', 0xE72C, 'redo'),
        @('Import from SD card', 'data', 0xE896, 'import'), @('GitHub sync', 'push / pull data', 0xE895, 'sync'),
        @('Run logs', 'data', 0xE7C3, 'logs'), @('Wireshark captures', 'open a capture in a ready-made view', 0xE701, 'pcap'),
        @('Firmware self-test', 'opens its own window', 0xE9D9, 'selftest'), @('UART cable test', 'wormhole tunnel boards', 0xE9D9, 'uart'),
        @('Toggle dry run', 'flash nothing', 0xE7E8, 'dryrun'), @('Open the CLI wizard', 'run_wizard.ps1', 0xE756, 'cli'),
        @('Open exports folder', 'datasets\exports', 0xE838, 'f:datasets\exports'), @('Open analysis folder', 'datasets\analysis', 0xE838, 'f:datasets\analysis'),
        @('Open presets folder', 'presets', 0xE838, 'f:presets'), @('Verification log', 'docs\dataset-verification.md', 0xE8A5, 'f:docs\dataset-verification.md'))) {
        [void]$it.Add((New-PalItem 'action' $a[0] $a[1] ([char]$a[2]) $Pal.Cyan 'action' $a[3]))
    }
    foreach ($p in @($script:Presets)) {
        $tone = if ($script:AtkTone[$p.Attack]) { $script:AtkTone[$p.Attack] } else { $Pal.Blue }
        [void]$it.Add((New-PalItem 'preset' ("{0} / {1} / {2} / {3}" -f $p.Attack, $p.Topology, $p.Location, $p.Scenario) ("{0}  ·  {1}  ·  {2} boards" -f $p.Owner, $p.File, $p.Boards) ([char]0xE768) $tone 'preset' $p.Path))
    }
    if ($script:Campaign) {
        foreach ($s in @($script:Campaign.slots)) {
            $lk = $script:TileLook[(Get-SlotLook $s)]
            [void]$it.Add((New-PalItem 'campaign run' (Get-SlotText $s) $lk.T ([char]0xE787) $lk.Bd 'slot' $s))
        }
    }
    foreach ($c in @($script:Cells)) { if ($c.Analysed) { [void]$it.Add((New-PalItem 'verify' ("verify  " + $c.Text) 'run the attack verifier' ([char]0xE73E) $Pal.Green 'verify' $c)) } }
    return $it
}
function Update-PalList {
    $words = @(([string]$ui.PalText.Text).ToLower() -split '\s+' | Where-Object { $_ })
    $ui.PalHint.Visibility = $(if ($ui.PalText.Text) { 'Collapsed' } else { 'Visible' })
    $hits = @($script:PalAll | Where-Object { $h = $_.Hay; -not @($words | Where-Object { -not $h.Contains($_) }).Count })
    if (-not $words.Count) { $hits = @($hits | Where-Object { $_.Type -in @('page', 'action') }) }
    $ui.PalList.ItemsSource = @($hits | Select-Object -First 40)
    if ($hits.Count) { $ui.PalList.SelectedIndex = 0 }
}
function Open-Palette {
    $script:PalAll = Get-PalItems
    $ui.PalText.Text = ''
    $ui.Palette.Visibility = 'Visible'
    $ui.Palette.BeginAnimation([Windows.UIElement]::OpacityProperty, (New-Fade 0 1 140))
    Update-PalList
    [void]$ui.PalText.Focus()
}
function Close-Palette { $ui.Palette.Visibility = 'Collapsed' }
function Invoke-PalItem($I) {
    Close-Palette
    if (-not $I) { return }
    $click = { param($b) $b.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent))) }
    switch ($I.Type) {
        'page'   { Show-Page $I.Data }
        'preset' { Show-Page 1; $ui.OwnerPick.SelectedItem = 'everyone'; $ui.AttackPick.SelectedIndex = 0; $ui.PresetSearch.Text = ''; Update-PresetGrid; Select-Preset $I.Data }
        'slot'   { Show-Page 3; $ui.CampTabs.SelectedIndex = 0; $ui.CfAll.IsChecked = $true; $ui.ClAll.IsChecked = $true; Show-CampaignCell $I.Data }
        'verify' { Show-Page 2; Select-Cell $I.Data; & $click $ui.DoVerify }
        'action' {
            $d = [string]$I.Data
            if ($d -like 'f:*') { $p = Join-Path $base $d.Substring(2); if (Test-Path $p) { Start-Process explorer $p }; return }
            switch ($d) {
                'next'      { & $click $ui.HomeGoCapture }
                'newpreset' { Show-Page 1; & $click $ui.PresetNew }
                'readmacs'  { Request-MacReadAll }
                'redo'      { Show-Page 3; Start-RedoList }
                'import'    { Open-Import $null }
                'sync'      { Show-Page 8 }
                'logs'      { Show-Page 5; $ui.DataTabs.SelectedIndex = 2 }
                'pcap'      { Show-Page 6; $ui.WsTabs.SelectedIndex = 0 }
                'selftest'  { & $click $ui.TSelfTest }
                'uart'      { & $click $ui.TUartTest }
                'dryrun'    { $ui.DryRun.IsChecked = -not $ui.DryRun.IsChecked; Show-Toast $(if ($ui.DryRun.IsChecked) { 'Dry run ON - nothing is flashed' } else { 'Dry run OFF' }) '' ([char]0xE7E8) '#475569' }
                'cli'       { & $click $ui.OpenCli }
            }
        }
    }
}
$ui.OpenPalette.Add_Click({ Open-Palette })
$ui.PalText.Add_TextChanged({ Update-PalList })
$ui.PalText.Add_PreviewKeyDown({
    param($s, $e)
    $n = @($ui.PalList.ItemsSource).Count
    switch ($e.Key) {
        'Down'   { if ($n) { $ui.PalList.SelectedIndex = [math]::Min($n - 1, $ui.PalList.SelectedIndex + 1); $ui.PalList.ScrollIntoView($ui.PalList.SelectedItem) }; $e.Handled = $true }
        'Up'     { if ($n) { $ui.PalList.SelectedIndex = [math]::Max(0, $ui.PalList.SelectedIndex - 1); $ui.PalList.ScrollIntoView($ui.PalList.SelectedItem) }; $e.Handled = $true }
        'Return' { Invoke-PalItem $ui.PalList.SelectedItem; $e.Handled = $true }
        'Escape' { Close-Palette; $e.Handled = $true }
    }
})
$ui.PalList.Add_MouseLeftButtonUp({ Invoke-PalItem $ui.PalList.SelectedItem })
$ui.Palette.Add_MouseLeftButtonDown({ param($s, $e) if ($e.OriginalSource -eq $ui.Palette) { Close-Palette } })

# keyboard shortcuts for the whole window
$win.Add_PreviewKeyDown({
    param($s, $e)
    $ctrl = ([Windows.Input.Keyboard]::Modifiers -band [Windows.Input.ModifierKeys]::Control) -ne 0
    if ($ctrl -and $e.Key -eq 'K') { if ($ui.Palette.Visibility -eq 'Visible') { Close-Palette } else { Open-Palette }; $e.Handled = $true; return }
    if ($ui.Palette.Visibility -eq 'Visible') { if ($e.Key -eq 'Escape') { Close-Palette; $e.Handled = $true }; return }
    if ($ctrl -and $e.Key -ge [Windows.Input.Key]::D1 -and $e.Key -le [Windows.Input.Key]::D8) { Show-Page ([int]$e.Key - [int][Windows.Input.Key]::D1); $e.Handled = $true; return }
    if ($ctrl -and $e.Key -eq 'N') { Show-Page 1; $ui.PresetNew.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent))); $e.Handled = $true; return }
    if ($ctrl -and $e.Key -eq 'F' -and $ui.Pages.SelectedIndex -eq 1) { [void]$ui.PresetSearch.Focus(); $e.Handled = $true; return }
    if ($e.Key -eq 'F5') {
        switch ($ui.Pages.SelectedIndex) {
            0 { Update-Home; [void](Update-LivePorts -Force) } 1 { Update-Presets; Show-PresetDetail } 2 { Update-Cells } 3 { Update-Home; Update-RedoIfChanged }
            4 { Update-Ports; Update-Members } 5 { Invoke-DataRefresh } 6 { Update-Pcaps }
        }
        Set-Status 'Refreshed.' $Pal.Green; $e.Handled = $true
    }
})
# double-click a preset = start it (same pre-flight as the button)
$ui.PresetGrid.Add_MouseDoubleClick({ if ($ui.PresetGrid.SelectedItem) { $ui.StartCapture.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent))) } })

# ── start ─────────────────────────────────────────────────────────────────────
Update-Presets
Update-Cells
Update-Ports
foreach ($fn in @(Get-Command -Name 'Initialize-Gui*' -CommandType Function -ErrorAction SilentlyContinue)) {
    try { & $fn.Name } catch { Write-Output ("GUI module {0} failed to start: {1}" -f $fn.Name, $_.Exception.Message) }
}
Update-Members
Update-Cards
Update-TrimCells   # marks itself dirty - scans when the Data page opens
Update-Logs
Update-Pcaps
Update-ViewBoards
Update-Home
Start-RedoList          # background, ~20-60 s: paints REDO / CHECK onto the campaign grid
# self-test never resets a real board: auto MAC read off
if ($SelfTest) { $ui.AutoMac.IsChecked = $false; $script:NoPeek = $true }
$liveTimer.Start()
$stepTimer.Start()
Update-NavBadges
if (-not $SelfTest) {
    if ($script:Settings.Page -gt 0 -and $script:Settings.Page -lt $nav.Count) { Show-Page ([int]$script:Settings.Page) }
    if (-not $script:Me) { $win.Add_ContentRendered({ Show-Toast 'Welcome!' "Pick who you are under 'I AM' (bottom left) - your presets come first. Press Ctrl+K to jump to anything." ([char]0xE77B) 'GradMain' }) }
    [void]$win.ShowDialog()
} else {
    $win.WindowStartupLocation = 'Manual'; $win.Left = -20000; $win.Top = 0
    $win.ShowInTaskbar = $false
    $win.Show()
    $pump = {
        param([int]$Ms)
        $until = (Get-Date).AddMilliseconds($Ms)
        while ((Get-Date) -lt $until) {
            $win.Dispatcher.Invoke([Action]{ }, [Windows.Threading.DispatcherPriority]::Background)
            Start-Sleep -Milliseconds 50
        }
    }
    $shot = {
        param([string]$Name)
        & $pump 600
        $w = [int]$win.ActualWidth; $h = [int]$win.ActualHeight
        $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap $w, $h, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($win)
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $fs = [IO.File]::Create((Join-Path $ShotDir "gui_$Name.png")); $enc.Save($fs); $fs.Close()
        Write-Output "shot: gui_$Name.png"
    }
    # wait for the campaign job
    $t0 = Get-Date
    while ($script:Jobs.Count -and ((Get-Date) - $t0).TotalSeconds -lt 60) { & $pump 300 }
    & $shot 'home'
    # the Everyone list (the fast view)
    Show-Page 1; $ui.OwnerPick.SelectedItem = 'everyone'; & $pump 300
    Write-Output ("everyone list: {0} row(s), list shown = {1}" -f @($ui.PresetList.ItemsSource).Count, $ui.PresetList.Visibility)
    & $shot 'capture_list'
    Show-Page 1
    $ui.OwnerPick.SelectedItem = 'Kyle'
    & $pump 300
    $ui.PresetGrid.SelectedIndex = 0
    & $shot 'capture'
    # preset editor: (1) a copy of the selected preset, screenshot, cancel;
    # (2) a NEW preset filled in and saved, then read back with the CLI reader.
    $script:EditorHook = {
        & $pump 400
        $bmp2 = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$ed.ActualWidth), ([int]$ed.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
        $bmp2.Render($ed); $enc2 = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc2.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp2))
        $fs2 = [IO.File]::Create((Join-Path $ShotDir 'gui_editor.png')); $enc2.Save($fs2); $fs2.Close()
        # multi-remove: tick 2 boards, one Remove press takes both (the copy is cancelled below)
        $before = @($dt.Rows | Where-Object { $_.RowState -ne 'Deleted' }).Count
        $ticked = @($dt.Rows | Where-Object { $_.RowState -ne 'Deleted' } | Select-Object -First 2); foreach ($r in $ticked) { $r['Pick'] = $true }
        $btn = [string]$f.EdRemove.Content
        $f.EdRemove.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        $script:EdMulti = ("editor multi-remove: {0} -> {1} board(s), button said '{2}'" -f $before, @($dt.Rows | Where-Object { $_.RowState -ne 'Deleted' }).Count, $btn)
        $ed.DialogResult = $false
    }
    [void](Show-PresetEditor -From $ui.PresetGrid.SelectedItem -AsCopy)
    Write-Output 'shot: gui_editor.png'
    Write-Output $script:EdMulti
    $script:EditorHook = {
        $f.EdOwner.Text = 'ZZ_GUI_TEST'; $f.EdAttack.SelectedItem = 'wormhole'; $f.EdScenario.SelectedItem = 'burst'
        [void]$dt.Rows.Add('node2', 'COM205', 'tunnel end', '20:50:0d:e7:1c:38', $false)
        [void]$dt.Rows.Add('node3', 'COM206', 'control', '20:50:0d:e7:0c:80', $true)
        [void]$dt.Rows.Add('node4', 'COM207', 'tunnel end', 'f4:2d:c9:73:e6:18', $false)
        [void]$dt.Rows.Add('root', 'COM203', 'root', 'b0:cb:d8:f3:32:18', $false)
        & $pump 200
        $f.EdSave.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        if (-not $script:EditorSavedPath) { $script:EditorProblems = $f.EdProblems.Text; $ed.DialogResult = $false }
    }
    $script:EditorProblems = ''
    $ok = Show-PresetEditor
    $script:EditorHook = $null
    $saved = $script:EditorSavedPath
    Write-Output ("editor save: " + $(if ($ok -and $saved) { $saved } else { 'NOT SAVED - ' + $script:EditorProblems }))
    if ($saved) {
        $wz = [Management.Automation.Language.Parser]::ParseFile((Join-Path $base 'run_wizard.ps1'), [ref]$null, [ref]$null)
        foreach ($fn in $wz.FindAll({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Read-PresetFile' }, $true)) { . ([scriptblock]::Create($fn.Extent.Text)) }
        $rb = Read-PresetFile -Path $saved
        Write-Output ("CLI reader: file={0} attack={1} topology={2} scenario={3} boards={4} kinds={5} roles={6} target={7}" -f (Split-Path $saved -Leaf),
            $rb.attack, $rb.topology, $rb.scenario, @($rb.boards).Count, (@($rb.boards | ForEach-Object Kind) -join ','),
            (@($rb.boards | ForEach-Object Role) -join ','), (@($rb.boards | Where-Object ScenarioTarget | ForEach-Object Label) -join ','))
        Remove-Item (Split-Path $saved -Parent) -Recurse -Force
    }
    # a burst target on a tunnel end must be refused (the CLI would throw at Start)
    $script:EditorHook = {
        $f.EdOwner.Text = 'ZZ_GUI_TEST'; $f.EdAttack.SelectedItem = 'wormhole'; $f.EdScenario.SelectedItem = 'burst'
        [void]$dt.Rows.Add('node2', 'COM205', 'tunnel end', '20:50:0d:e7:1c:38', $true)
        [void]$dt.Rows.Add('node4', 'COM207', 'tunnel end', 'f4:2d:c9:73:e6:18', $false)
        [void]$dt.Rows.Add('root', 'COM203', 'root', 'b0:cb:d8:f3:32:18', $false)
        & $pump 200
        $f.EdSave.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        $script:EditorProblems = $f.EdProblems.Text
        if (-not $script:EditorSavedPath) { $ed.DialogResult = $false }
    }
    $ok = Show-PresetEditor
    $script:EditorHook = $null
    if ($script:EditorSavedPath) { Remove-Item (Split-Path $script:EditorSavedPath -Parent) -Recurse -Force }
    Write-Output ("editor burst target on a tunnel end: " + $(if (-not $script:EditorSavedPath -and $script:EditorProblems -match 'burst target') { 'refused (ok)' } else { 'SAVED - BUG' }))
    Show-Page 2
    Select-Cell (@($script:Cells | Where-Object Text -eq 'wormhole  /  tree  /  DLSU_Library  /  stationary') | Select-Object -First 1)
    $ui.DoVerify.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    $t0 = Get-Date
    while ($script:Jobs.Count -and ((Get-Date) - $t0).TotalSeconds -lt 60) { & $pump 300 }
    & $shot 'verify'
    $ui.AnaTabs.SelectedIndex = 1; $t0 = Get-Date; while ($script:Jobs.Count -and ((Get-Date) - $t0).TotalSeconds -lt 30) { & $pump 200 }; & $pump 300; & $shot 'verify_files'
    $ui.AnaTabs.SelectedIndex = 2; & $pump 600; & $shot 'verify_plots'
    $ui.AnaTabs.SelectedIndex = 0
    $script:VerQueue.Clear(); foreach ($c in @($script:Cells | Where-Object { $_.Analysed -and $_.Attack -ne 'baseline' } | Select-Object -First 2)) { $script:VerQueue.Enqueue($c) }
    Start-NextVerify; $t0 = Get-Date; while (($script:VerQueue.Count -or $script:Jobs.Count) -and ((Get-Date) - $t0).TotalSeconds -lt 90) { & $pump 300 }
    Write-Output ("check all verdicts: queue drained = {0}, status = {1}" -f ($script:VerQueue.Count -eq 0), $ui.Status.Text)
    $a0 = @($script:Cells)[0].Art; Write-Output ("run list pictures: {0} ({1}x{2})" -f $(if ($a0) { $a0.GetType().Name } else { 'NONE' }), $(if ($a0) { $a0.PixelWidth } else { 0 }), $(if ($a0) { $a0.PixelHeight } else { 0 }))
    Write-Output ("analysis page: {0} run(s) listed, {1} need analysis, files rows = {2}, plots = {3}" -f @($script:Cells).Count, @($script:Cells | Where-Object { $_.Look -in @('todo', 'stale') }).Count, $ui.AnaFiles.Children.Count, $ui.AnaPlots.Children.Count)
    Show-Page 3
    $t0 = Get-Date
    while ($script:Jobs.Count -and ((Get-Date) - $t0).TotalSeconds -lt 120) { & $pump 300 }
    if ($script:Campaign.next) { Show-CampaignCell $script:Campaign.next }
    $redoSlot = @($script:Campaign.slots | Where-Object { (Get-SlotLook $_) -eq 'redo' })[0]
    if ($redoSlot) { Show-CampaignCell $redoSlot }
    & $shot 'campaign'
    $ui.CfRedo.IsChecked = $true; $ui.ClG402.IsChecked = $true
    & $shot 'campaign_filtered'
    $ui.CfAll.IsChecked = $true; $ui.ClAll.IsChecked = $true
    $ui.CampTabs.SelectedIndex = 1
    $ui.LoadPlan.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    $ui.CampaignGrid.SelectedIndex = 0
    & $shot 'campaign_table'
    $ui.CampTabs.SelectedIndex = 0
    # live boards: two fake plugged boards (no hardware touched) -> sidebar,
    # home tiles, Boards grid, editor chips
    $script:Live['COM98'] = [pscustomobject]@{ Port = 'COM98'; Description = 'Silicon Labs CP210x (test)'; Kind = 'BRIDGE'; Mac = 'b0:cb:d8:f3:32:18'; Who = 'ROOT [Cal]'; State = 'ok'; Since = (Get-Date) }
    $script:Live['COM99'] = [pscustomobject]@{ Port = 'COM99'; Description = 'Silicon Labs CP210x (test)'; Kind = 'BRIDGE'; Mac = ''; Who = ''; State = 'reading'; Since = (Get-Date) }
    Update-LiveViews
    Show-Toast 'Board plugged in on COM99' 'Reading its MAC...'
    Show-Page 0; & $shot 'home_live'
    # speed-ups: palette search, preset search, verdict banner, toast action
    Update-NavBadges
    Open-Palette; $ui.PalText.Text = 'worm tree dlsu'; & $pump 200
    Write-Output ("palette 'worm tree dlsu': {0} hit(s), first = {1}" -f @($ui.PalList.ItemsSource).Count, $ui.PalList.SelectedItem.Title)
    & $shot 'palette'
    Invoke-PalItem $ui.PalList.SelectedItem
    Write-Output ("palette -> page {0}" -f $ui.Pages.SelectedIndex)
    Show-Page 1; $ui.OwnerPick.SelectedItem = 'everyone'; $ui.PresetSearch.Text = 'wormhole g402'; & $pump 700
    Write-Output ("preset search 'wormhole g402': {0} row(s)" -f @($ui.PresetGrid.ItemsSource).Count)
    & $shot 'capture_search'
    $ui.PresetSearch.Text = ''
    $script:NewDrive = 'Z:'; $script:ToastHit = $false
    Show-Toast 'SD card inserted (Z:)' 'Bring its captures in?' ([string][char]0xE896) '#B45309' -Action { $script:ToastHit = $true } -ActionText 'List the files on it'
    $mev = New-Object Windows.Input.MouseButtonEventArgs ([Windows.Input.Mouse]::PrimaryDevice), 0, ([Windows.Input.MouseButton]::Left)
    $mev.RoutedEvent = [Windows.UIElement]::MouseLeftButtonUpEvent
    $ui.Toast.RaiseEvent($mev)
    Write-Output ("toast click ran its action: " + $script:ToastHit)
    # MAC-read pipeline on a port that does not exist (touches no hardware):
    # must end 'failed', not hang or crash
    $script:Live['COM97'] = [pscustomobject]@{ Port = 'COM97'; Description = 'test'; Kind = 'BRIDGE'; Mac = ''; Who = ''; State = 'new'; Since = (Get-Date) }
    Start-MacRead 'COM97'
    $t0 = Get-Date
    while ($script:Jobs.Count -and ((Get-Date) - $t0).TotalSeconds -lt 60) { & $pump 300 }
    Write-Output ("mac-read pipeline: COM97 state=" + $script:Live['COM97'].State)
    Write-Output ("hands-off check: " + $(if (Test-HandsOff) { Test-HandsOff } else { 'clear' }))
    Show-Page 1; $ui.OwnerPick.SelectedItem = 'everyone'; & $pump 300
    Start-CellCapture $script:Campaign.slots[1]
    Write-Output ("cell->preset: " + $(if ($ui.PresetGrid.SelectedItem) { $ui.PresetGrid.SelectedItem.File } else { 'none selected' }))
    # LIVE RUN end to end with stand-ins for run.ps1 and esptool (no board, no
    # compiler): park -> child flash/monitor/booted/auto-next -> root wake ->
    # READY -> START button -> phases -> TERMINATE -> finish + export -> done
    $fk = Join-Path $env:TEMP 'nis16_gui_selftest'; New-Item -ItemType Directory -Force -Path $fk | Out-Null
    Set-Content -Path (Join-Path $fk 'esptool.ps1') -Encoding UTF8 -Value 'Write-Host "esptool stand-in: $args"; exit 0'
    Set-Content -Path (Join-Path $fk 'run.ps1') -Encoding UTF8 -Value @'
param([string]$Port, [string]$Role, [string]$GuiMonitor, [switch]$BuildOnly, [string]$Label)
[Console]::OutputEncoding = [Text.Encoding]::UTF8
function L([string]$l, [string]$m) { Write-Host ("$([char]27)[0;32m{0} (1234) ROOT: {1}$([char]27)[0m" -f $l, $m) }
$fk = Split-Path $PSCommandPath -Parent
if ($BuildOnly) {
    Write-Host "  What:   $Role firmware (stand-in)"
    Write-Host "[412/1036] Building C object esp-idf/mesh_common/CMakeFiles/__idf_mesh_common.dir/src/csv_logger.c.obj"; Write-Host "[1036/1036] Generating binary image from built executable"
    $f = Join-Path $fk "failbuild_$Label"
    if (Test-Path $f) { Remove-Item $f; Write-Host "csv_logger.c:2100:44: error: missing terminating character"; Write-Host "    first error: csv_logger.c:2100:44: error: missing terminating character"; exit 1 }
    Write-Host "  Built OK in 1s"; exit 0
}
Write-Host "Setting $Port's clock from this laptop ..."
$f = Join-Path $fk "failflash_$Label"
if (Test-Path $f) { Remove-Item $f; Write-Host "Flash FAILED twice on $Port - NOT exporting (the board has no firmware on it)."; exit 1 }
Write-Host "Writing at 0x00010000... (50 %)"; Start-Sleep -Milliseconds 300; Write-Host "Writing at 0x00090000... (100 %)"
Write-Host "[monitor] listening on $Port at 115200 baud"
$send = Join-Path $GuiMonitor 'send.txt'; $stop = Join-Path $GuiMonitor 'stop'
if ($Role -ne 'root') { Write-Host "I (300) VICTIM: === VICTIM NODE STARTING ===" }
else {
    L 'I' '════════════════════ WAITING FOR ALL CHILDREN ════════════════════  @ 10:00:00 PHT'
    L 'W' '[CTRL] WAITING: 0/1 children in the mesh (10 s). Phase 0 will NOT start until all are in.'
    Start-Sleep -Milliseconds 600
    L 'I' '================================================================'
    L 'I' ' MESH TOPOLOGY'
    L 'I' ' TYPE        : TREE'
    L 'I' ' NODE COUNT  : 0x2 (2)'
    L 'I' ' HOP DEPTH   : 0x1 (1)'
    L 'I' ' REACHABLE   : 0x2 (2)'
    L 'I' ' STATUS      : OK'
    L 'I' ' DETAIL      : every node reaches the root'
    L 'I' ' EXPORT      : not yet - run in progress, do not export'
    L 'I' '----------------------------------------------------------------'
    L 'I' ' HOP  MAC ADDRESS        ROLE     RSSI  PHASE        AGE(s)  EXPORT'
    L 'I' ' H0   B0:CB:D8:F3:32:18  ROOT      n/a  0xFF UNSET        0  not yet'
    L 'I' ' H1   20:50:0D:E7:0C:80  VICTIM    -48  0xFF UNSET        1  not yet'
    L 'I' '----------------------------------------------------------------'
    L 'I' ' PARENT/CHILD STRUCTURE (depth-first from root)'
    L 'I' ' NODESTAT 20:50:0D:E7:FE:90 sd=OK uart=NA age=3 up=95 rssi=-41'
    L 'I' ' NODESTAT 20:50:0D:E7:1C:38 sd=STALLED uart=LOST age=55 up=40 rssi=-60'
    L 'I' '[CTRL] All 1 children in the mesh after 12 s - starting the run.'
    L 'I' '════════════════════ READY - TYPE  START  TO BEGIN PHASE 0 ════════════════════  @ 10:00:12 PHT'
    L 'W' '[CTRL] READY: 1/1 children in the mesh. Check the topology table, then type START.'
    L 'E' ' !! TEST ALERT - shown in the alerts card'
    $t0 = Get-Date
    while (-not ((Test-Path $send) -and (Get-Content $send -Raw) -match 'START') -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 200 }
    L 'I' '[CTRL] START received after 3 s - starting the run.'
    L 'I' '════════════════════ PHASE 0 — BASELINE ════════════════════  @ 10:00:15 PHT'
    L 'I' '[CTRL] Starting PHASE 0 — Baseline (300 s)'
    Start-Sleep -Milliseconds 900
    L 'I' '════════════════════ PHASE — ATTACK ════════════════════  @ 10:05:15 PHT'
    Start-Sleep -Milliseconds 300
    L 'I' '════════════════════ PHASE 3 — COOLDOWN ════════════════════  @ 10:08:15 PHT'
    Start-Sleep -Milliseconds 300
    L 'I' '════════════════════ PHASE 4 — TERMINATE ════════════════════  @ 10:10:15 PHT'
    L 'I' ' EXPORT      : ALL 2 BOARDS DONE - SAFE TO EXPORT (a board missing from this table is not covered)'
}
$t0 = Get-Date
while (-not (Test-Path $stop) -and ((Get-Date) - $t0).TotalSeconds -lt 60) { Start-Sleep -Milliseconds 200 }
Write-Host "[monitor] closed"
if (-not (Test-Path (Join-Path $GuiMonitor 'noexport')) -and $Role -eq 'root') { Write-Host "Exporting root CSVs from $Port ..."; Start-Sleep -Milliseconds 400; Write-Host "Done in 1 sec. Files are in datasets\exports\." }
exit 0
'@
    $script:RunScript = Join-Path $fk 'run.ps1'; $script:RunEsptool = Join-Path $fk 'esptool.ps1'; $script:AutoConfirm = $true
    $script:Live['COM98'].State = 'ok'
    $script:Live['COM99'].Mac = '20:50:0d:e7:0c:80'; $script:Live['COM99'].State = 'ok'
    $script:Live['COM96'] = [pscustomobject]@{ Port = 'COM96'; Description = 'test'; Kind = 'BRIDGE'; Mac = '20:50:0d:e7:fe:90'; Who = 'test'; State = 'ok'; Since = (Get-Date); Asked = $true; Prev = '' }
    $fakeCfg = [pscustomobject]@{ attack = 'wormhole'; topology = 'tree'; location = 'G402'; scenario = 'stationary'; owner = 'ZZ_GUI_TEST'; repeat = 2
        boards = @([pscustomobject]@{ Label = 'node2'; Port = 'COM99'; Role = 'child'; Kind = 'control'; Display = 'control (plain firmware)'; Mac = '20:50:0d:e7:0c:80'; ScenarioTarget = $false },
                   [pscustomobject]@{ Label = 'node3'; Port = 'COM96'; Role = 'child'; Kind = 'control'; Display = 'control (plain firmware)'; Mac = '20:50:0d:e7:fe:90'; ScenarioTarget = $false },
                   [pscustomobject]@{ Label = 'node1'; Port = 'COM98'; Role = 'root'; Kind = 'root'; Display = 'ROOT (announces the phases)'; Mac = 'b0:cb:d8:f3:32:18'; ScenarioTarget = $false }) }
    $fakeP = [pscustomobject]@{ File = 'wormhole-tree-g402-stationary.json'; Path = (Join-Path $fk 'p.json'); Cfg = $fakeCfg; Repeat = 2; Owner = 'ZZ_GUI_TEST' }
    Open-RunPage $fakeP
    $ui.RunSaveLog.IsChecked = $false
    $ui.RunClean.IsChecked = $false   # never wipe this laptop's REAL build_* folders from a test
    & $pump 300; & $shot 'liverun_setup'
    Set-Content (Join-Path $fk 'failbuild_node2') 'x'; Set-Content (Join-Path $fk 'failflash_node3') 'x'
    $ui.RunGo.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    $t0 = Get-Date
    while ($script:Run.Phase -ne 'buildfail' -and ((Get-Date) - $t0).TotalSeconds -lt 60) { & $pump 250 }
    Write-Output ("smart compile: {0} board(s) -> {1} build(s); failed = {2}; error = {3}; button = '{4}'" -f @($script:Run.Steps | Where-Object Kind -eq 'board').Count, $script:Run.Builds.Count,
        ($script:Run.Failed -join ','), @($script:Run.Builds | Where-Object State -eq 'failed')[0].Err, $ui.RunNext.Content)
    & $shot 'liverun_buildfail'
    $ui.RunNext.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    $t0 = Get-Date
    while ($script:Run.Phase -ne 'boardfail' -and ((Get-Date) - $t0).TotalSeconds -lt 60) { & $pump 250 }
    Write-Output ("smart run: recompiled only the failed variant ({0} build(s) this time), now '{1}': {2}" -f $script:Run.BuildTotal, $script:Run.Phase, $ui.RunNowTitle.Text)
    & $shot 'liverun_boardfail'
    $ui.RunNext.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    $t0 = Get-Date
    while (-not ($script:Dash -and $script:Dash.Ready) -and ((Get-Date) - $t0).TotalSeconds -lt 90) { & $pump 250 }
    & $pump 600
    Write-Output ("live run: root READY seen={0}, START enabled={1}, kids={2}, nodes={3}, topo={4}" -f [bool]$script:Dash.Ready, $ui.RunStart.IsEnabled, $ui.RunKids.Text, @($ui.RunNodes.ItemsSource).Count, $ui.RunTopoStatus.Text)
    & $shot 'liverun_ready'
    $ui.RunStart.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    $t0 = Get-Date
    while (-not $script:Dash.Ended -and ((Get-Date) - $t0).TotalSeconds -lt 60) { & $pump 250 }
    & $pump 400
    Write-Output ("live run: phase='{0}', ended={1}, alerts={2}" -f $ui.RunPhase.Text, $script:Dash.Ended, @($ui.RunAlerts.ItemsSource).Count)
    & $shot 'liverun_root'
    $ui.RunNext.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    $t0 = Get-Date
    while ($script:Run.Phase -ne 'done' -and ((Get-Date) - $t0).TotalSeconds -lt 60) { & $pump 250 }
    try { $script:BH.DrawnAt = [datetime]::MinValue; $script:BH.Dirty = $true; Update-BoardHealth } catch { Write-Output ("board health ERROR: " + $_.Exception.Message) }
    Write-Output ("board health: boards={0}, chips={1}, link={2}" -f @($script:BH.Stat.Keys).Count, ((@($script:BHChips.Children | ForEach-Object { $_.Child.Text })) -join ' | '), $(if ($script:BHLink.Children.Count -gt 1) { $script:BHLink.Children[1].Text } else { 'none' }))
    Write-Output ("live run: end phase={0}, steps={1}" -f $script:Run.Phase, (@($script:Run.Steps | ForEach-Object { "$($_.Kind):$($_.State)" }) -join ' '))
    & $shot 'liverun_done'
    $script:AutoConfirm = $false; $script:Run = $null
    Remove-Item -Recurse -Force $fk -ErrorAction SilentlyContinue
    # IMPORT page on a fake card folder (list + preview only - nothing is copied)
    $card = Join-Path $env:TEMP 'nis16_gui_fakecard'
    $leaf = Join-Path $card 'wormhole\tree\G402'; New-Item -ItemType Directory -Force -Path $leaf | Out-Null
    $hdr = 'timestamp_us,node_id,role,layer,parent_mac,rssi_dbm,retry_count,tx_count,probes_count,phase_id,gt_label,recv_count,forward_count,drop_count'
    $rows = @($hdr) + @(1..40 | ForEach-Object { '{0},NODE_20500DE70C80,child,2,B0:CB:D8:F3:32:19,-60,0,9,9,{1},0,0,0,0' -f ($_ * 100000), $(if ($_ -lt 20) { 0 } else { 2 }) })
    Set-Content -Path (Join-Path $leaf 'victim_NODE_20500DE70C80_r1_b2_telem.csv') -Value $rows -Encoding ASCII
    Set-Content -Path (Join-Path $leaf 'victim_NODE_20500DE70C80_r1_b1_telem.csv') -Value @($hdr) -Encoding ASCII
    $leaf2 = Join-Path $card 'blackhole\tree\G402'; New-Item -ItemType Directory -Force -Path $leaf2 | Out-Null
    Set-Content -Path (Join-Path $leaf2 'victim_NODE_20500DE7FE90_r1_b3_telem.csv') -Value $rows -Encoding ASCII
    Show-Page 5; $ui.DataTabs.SelectedIndex = 0; & $pump 200
    $ui.SrcCard.IsChecked = $true
    $ui.CardPick.ItemsSource = @([pscustomobject]@{ Root = ($card + '\'); Looks = $true; Text = "$card\  - fake card (self-test)" }); $ui.CardPick.SelectedIndex = 0
    $ui.ImpList.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    $t0 = Get-Date
    while (($script:Stream -or -not $script:ImpTable) -and ((Get-Date) - $t0).TotalSeconds -lt 60) { & $pump 250 }
    & $pump 300
    Write-Output ("import pick: {0}  |  {1}  |  dest of row 1: {2}" -f (Get-ImpPick), $ui.ImpDest.Text, @($script:ImpTable.Rows)[0].Dest)
    Write-Output ("import list: {0} row(s), statuses = {1}, ticked = {2}, roster = {3}" -f @($script:ImpTable.Rows).Count,
        ((@($script:ImpTable.Rows | ForEach-Object Status)) -join ','), @($script:ImpTable.Rows | Where-Object { $_.Import }).Count,
        $(if ($ui.ImpRoster.SelectedItem) { $ui.ImpRoster.SelectedItem.Text } else { '-' }))
    & $shot 'import'
    if (@($script:ImpTable.Rows | Where-Object { $_.Import }).Count) {
        $ui.ImpPreview.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
        $t0 = Get-Date
        while ($script:Stream -and ((Get-Date) - $t0).TotalSeconds -lt 60) { & $pump 250 }
        Write-Output ("import preview: card still has {0} file(s) (must be 2 - preview copies and deletes nothing)" -f @(Get-ChildItem $leaf -File).Count)
    }
    Remove-Item -Recurse -Force $card -ErrorAction SilentlyContinue
    # a STILL RUNNING file over USB -> the safe-close banner + END_RUN button (CLI parity)
    $ui.SrcPort.IsChecked = $true
    $liveItem = [pscustomobject]@{ rel = 'blackhole/tree/G402/victim_NODE_20500DE70C80_r1_b4_telem.csv'; name = 'victim_NODE_20500DE70C80_r1_b4_telem.csv'; attack = 'blackhole'; filed_under = 'blackhole'
        topology = 'tree'; location = 'G402'; role = 'victim'; node = 'NODE_20500DE70C80'; boot = 4; run = 1; kind = 'telem'; rows = $null; bytes = 900000; phases = $null; live = $true
        source = 'port'; clean = $false; built = $null; started = '2026-10-17 17:26:03'; clock_src = 'host'; reset = $null; ended_by = $null; status = $null; already = $null; archived = $false }
    Show-ImpList @($liveItem)
    Write-Output ("still-running over USB: banner={0}, END_RUN button={1}, status='{2}', ticked={3}" -f $ui.ImpLiveBar.Visibility, $ui.ImpEndRun.Visibility, @($script:ImpTable.Rows)[0].Status, @($script:ImpTable.Rows | Where-Object { $_.Import }).Count)
    & $shot 'import_live'
    # a board that REBOOTED mid-run: two pieces -> only the best (attack) piece ticked
    $pa = $liveItem.PSObject.Copy(); $pa.live = $false; $pa.rel = 'p/b2.csv'; $pa.name = 'victim_NODE_20500DE70C80_r1_b2_telem.csv'; $pa.boot = 2; $pa.phases = @(255, 0); $pa.rows = 6290; $pa.ended_by = 'PANIC'
    $pb = $liveItem.PSObject.Copy(); $pb.live = $false; $pb.rel = 'p/b3.csv'; $pb.name = 'victim_NODE_20500DE70C80_r2_b3_telem.csv'; $pb.boot = 3; $pb.phases = @(1, 3); $pb.rows = 2020; $pb.ended_by = $null
    Show-ImpList @($pa, $pb)
    Write-Output ("rebooted mid-run: " + ((@($script:ImpTable.Rows | ForEach-Object { '{0}={1}{2}' -f $_.File.Substring(28, 2), $_.Status, $(if ($_.Import) { ' [ticked]' } else { '' }) })) -join ' | '))
    # the user's oct. 17 case over USB: aborted fragment (bytes only) vs clean complete file (rows) + an OLD separate run
    $u1 = $liveItem.PSObject.Copy(); $u1.live = $false; $u1.rel = 'u/b2.csv'; $u1.name = 'victim_NODE_B4BFE934ED80_r1_b2_telem.csv'; $u1.boot = 2; $u1.phases = $null; $u1.rows = $null; $u1.bytes = 97850; $u1.clean = $false; $u1.ended_by = 'POWERON'; $u1.started = '2026-10-17 16:59:59'
    $u2 = $liveItem.PSObject.Copy(); $u2.live = $false; $u2.rel = 'u/b4.csv'; $u2.name = 'victim_NODE_B4BFE934ED80_r2_b4_telem.csv'; $u2.boot = 4; $u2.phases = $null; $u2.rows = 7289; $u2.bytes = 621685; $u2.clean = $true; $u2.ended_by = $null; $u2.started = '2026-10-17 16:59:59'
    $u3 = $liveItem.PSObject.Copy(); $u3.live = $false; $u3.rel = 'u/b1.csv'; $u3.name = 'victim_NODE_B4BFE934ED80_r9_b1_telem.csv'; $u3.boot = 1; $u3.phases = $null; $u3.rows = 6000; $u3.bytes = 500000; $u3.clean = $true; $u3.ended_by = $null; $u3.started = '2026-10-09 10:00:00'
    $script:ImpFilling = $true; Set-ImpPick 'blackhole' 'tree' 'G402'; $script:ImpFilling = $false
    Show-ImpList @($u1, $u2, $u3)
    Write-Output ("usb pieces: " + ((@($script:ImpTable.Rows | Sort-Object File | ForEach-Object { '{0}={1}{2}' -f $_.File.Substring(28, 5), $_.Status, $(if ($_.Import) { ' [ticked]' } else { '' }) })) -join ' | '))
    # already in exports under ANOTHER name (preset name vs card name) -> found by the folder scan
    $realExp = Get-ChildItem (Join-Path $base 'datasets\exports\baseline\linear\home\highload') -Filter 'child_node2_*_r1_*_telem.csv' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($realExp) {
        $rr = 0; $sr = New-Object IO.StreamReader($realExp.FullName); [void]$sr.ReadLine(); while ($null -ne $sr.ReadLine()) { $rr++ }; $sr.Close()
        $ax = $liveItem.PSObject.Copy(); $ax.live = $false; $ax.rel = 'a/b1.csv'; $ax.name = 'victim_NODE_F42DC973E618_r1_b1_telem.csv'; $ax.node = 'NODE_F42DC973E618'; $ax.rows = $rr; $ax.clean = $true
        $ax.attack = 'baseline'; $ax.filed_under = 'baseline'; $ax.topology = 'linear'; $ax.location = 'home'; $ax.started = $null
        $script:ImpFilling = $true; Set-ImpPick 'baseline' 'linear' 'home'; $ui.ImpScenario.SelectedItem = 'highload'; $ui.ImpRepeat.Text = '1'; $script:ImpFilling = $false
        Show-ImpList @($ax)
        Write-Output ("already under another name: status='{0}', ticked={1}, why='{2}'" -f @($script:ImpTable.Rows)[0].Status, @($script:ImpTable.Rows | Where-Object { $_.Import }).Count, @($script:ImpTable.Rows)[0].Why)
    }
    # crash watch: a fake child log with a panic -> alert
    $wl = Join-Path $env:TEMP 'nis16_crashwatch_test.log'
    Set-Content -Path $wl -Encoding UTF8 -Value @('I (1000) VICTIM: probe sent', "Guru Meditation Error: Core  0 panic'ed (LoadProhibited). Exception was unhandled.", 'Backtrace: 0x400d1234:0x3ffb1230 0x400d5678:0x3ffb1250', 'rst:0xc (SW_CPU_RESET),boot:0x13 (SPI_FAST_FLASH_BOOT)', '')
    $script:Run = [pscustomobject]@{ Bg = (New-Object System.Collections.ArrayList); LogPath = '' }
    [void]$script:Run.Bg.Add([pscustomobject]@{ Label = 'node4'; Port = 'COM233'; Proc = [pscustomobject]@{ HasExited = $true }; Log = $wl; Pos = [long]0; Buf = ''; Ctl = $env:TEMP; Elf = (Join-Path $env:TEMP 'no_such_firmware.elf'); Crashes = 0; Last = '' })
    $script:Dash = @{ Alerts = (New-Object System.Collections.ArrayList) }
    Read-CrashWatch
    Write-Output ("crash watch: crashes counted = {0}, alerts = {1}" -f $script:Run.Bg[0].Crashes, ((@($script:Dash.Alerts | ForEach-Object Text)) -join ' || '))
    $script:Run = $null; Remove-Item $wl -ErrorAction SilentlyContinue
    $sw = [Diagnostics.Stopwatch]::StartNew(); $li = Get-LastImports; $t1 = $sw.ElapsedMilliseconds
    $sw.Restart(); $null = Get-LastImports; $t2 = $sw.ElapsedMilliseconds
    Write-Output ("last-imported index: {0} board(s) found in exports, first scan {1} ms, cached rescan {2} ms" -f $li.Count, $t1, $t2)
    $ui.SrcPort.IsChecked = $true; Update-ImpPorts
    foreach ($it in @($ui.CardPortPick.ItemsSource | Where-Object Mac | Select-Object -First 3)) { Write-Output ("  picker: {0}`n          {1}" -f ("{0}  {1}  {2}" -f $it.Port, $it.MacTxt, $it.Who), ("{0} {1}{2}{3}{4}{5}{6}" -f $it.Icon, $it.Lead, $it.When, $it.Arrow, $it.Atk, $it.Rest, $it.Rep)) }
    $ui.CardPortPick.SelectedIndex = @($ui.CardPortPick.ItemsSource).IndexOf(@($ui.CardPortPick.ItemsSource | Where-Object Mac)[0]); & $shot 'import_usb'
    Show-Page 4; & $shot 'boards'
    $ft = @($ui.BoardTabs.Items | Where-Object { [string]$_.Header -match 'Firmware' })[0]; if ($ft) { $ui.BoardTabs.SelectedItem = $ft; Update-PortPick $ui.TSelfPort; $ui.TSelfPort.SelectedIndex = 0; & $shot 'tests'; $ui.BoardTabs.SelectedIndex = 0 }
    Show-Page 6; $st = @($ui.WsTabs.Items | Where-Object { [string]$_.Header -match 'sniffer' })[0]; if ($st) { $ui.WsTabs.SelectedItem = $st; Update-PortPick $ui.SnPort; $ui.SnPort.SelectedIndex = 0; & $shot 'sniffer' }
    Show-Page 5; & $shot 'data'
    # Trim & archive: scan speed, statuses, filter, screenshot
    $tt = @($ui.DataTabs.Items | Where-Object { [string]$_.Header -match 'Trim' })[0]; if ($tt) { $ui.DataTabs.SelectedItem = $tt }
    $ms = (Measure-Command { $script:TrimDirty = $true; Update-TrimCells }).TotalMilliseconds
    $ui.TrimList.SelectedIndex = 0; & $pump 300
    Write-Output ("trim page: {0} run(s) scanned in {1:N0} ms  |  {2}  |  {3} past archive(s)  |  selected: {4}" -f @($script:TrimCells).Count, $ms, $ui.TrimCount.Text, @($ui.ArcList.ItemsSource).Count, $ui.TrimSel.Text)
    & $shot 'trim'
    $ui.TrimFTodo.IsChecked = $true; & $pump 100; Write-Output ("trim filter 'Not trimmed': " + $ui.TrimCount.Text); $ui.TrimFAll.IsChecked = $true
    $ui.DataTabs.SelectedIndex = 0
    # GitHub sync page: a REAL read-only check (status changes nothing), then the plan as shown
    $t0 = Get-Date; while ($script:Stream -and ((Get-Date) - $t0).TotalSeconds -lt 60) { & $pump 250 }
    Show-Page 8; & $pump 400
    Write-Output ("sync page opened: check started by itself = {0} (must be False)" -f [bool]$script:Stream)
    try { Update-SyncTimes; foreach ($t in @($ui.SyncTimes.ItemsSource)) { Write-Output ("sync time: {0} = {1} ({2})" -f $t.Name, $t.When, $(if ($t.At) { $t.Ago } else { $t.Tip })) } }
    catch { Write-Output ("sync times ERROR: {0} at line {1}" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber) }
    $ui.SyncCheck.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent)))
    $t0 = Get-Date; while (($script:Stream -or -not $script:Sync) -and ((Get-Date) - $t0).TotalSeconds -lt 180) { & $pump 400 }
    & $pump 400
    if ($script:Sync) { try { Show-SyncStatus $script:Sync } catch { Write-Output ("sync page ERROR: {0} at line {1}: {2}" -f $_.Exception.Message, $_.InvocationInfo.ScriptLineNumber, $_.InvocationInfo.Line.Trim()) } }
    if ($script:Sync) {
        Write-Output ("sync page: head='{0}' | send {1} | receive {2} | held {3} | runs {4} | gate={5} | steps={6}" -f $ui.SyncHead.Text, $script:SyncTables.Send.Rows.Count, $script:SyncTables.Recv.Rows.Count,
            $ui.SyncHeldGrid.Items.Count, $ui.SyncRunsGrid.Items.Count, $ui.SyncGate.Visibility, ((@($ui.SyncSteps.ItemsSource | ForEach-Object { "$($_.Name)=$($_.Info)" })) -join ', '))
        Write-Output ("sync chips: " + ((@($ui.SyncChips.ItemsSource | ForEach-Object Text)) -join ' | '))
        foreach ($tn in 'Send', 'Recv') { $r0 = @($script:SyncTables[$tn].Rows) | Select-Object -First 1; if ($r0) { Write-Output ("sync file time ({0}): {1} | here {2} | GitHub {3}" -f $tn, $r0.File, $r0.HereT, $r0.HubT) } }
    } else { Write-Output 'sync page: NO STATUS (check failed)' }
    & $shot 'sync'
    $ui.SyncTabs.SelectedIndex = 3; & $pump 300; & $shot 'sync_runs'
    Set-SyncDone 'Sync done' '3 sent, 0 received  (self-test)'; & $pump 300
    $ui.SyncUpdate.RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Primitives.ButtonBase]::ClickEvent))); & $pump 200
    Write-Output ("after a sync: check started by itself = {0} (must be False), head='{1}', send list cleared = {2}, next Smart sync re-checks = {3}" -f [bool]$script:Stream, $ui.SyncHead.Text, ($null -eq $ui.SyncSendGrid.ItemsSource), ($null -eq $script:SyncChecked))
    & $shot 'sync_done'
    Write-Output ("status: " + $ui.Status.Text)
    $win.Close()
}
# Stop EVERY timer when the window is gone (oct. 18 2026). Only $timer was
# stopped before: the board watcher, run clock, stream, SD watcher... stayed
# alive in the ESP-IDF console and woke up again the next time .\run_gui.ps1
# ran in that console - one extra set per relaunch (lag, 2 GB after a day, and
# an old board watcher could talk to boards behind the new window's back).
foreach ($v in @(Get-Variable -Scope Script)) {
    if ($v.Value -is [Windows.Threading.DispatcherTimer]) { try { $v.Value.Stop() } catch { } }
}
$timer.Stop()
if ($SelfTest) {
    # our timers only (WPF keeps a harmless one-shot TextBox timer of its own)
    $dsp = [Windows.Threading.Dispatcher]::CurrentDispatcher
    $tl = $dsp.GetType().GetField('_timers', [Reflection.BindingFlags]'NonPublic,Instance')
    $tf = [Windows.Threading.DispatcherTimer].GetField('Tick', [Reflection.BindingFlags]'NonPublic,Instance')
    $ours = @(if ($tl -and $tf) { @($tl.GetValue($dsp)) | Where-Object { $h = $tf.GetValue($_); -not $h -or @($h.GetInvocationList() | Where-Object { $_.Method.DeclaringType.FullName -notlike 'System.Windows.*' }).Count } })
    Write-Output ("GUI timers still running after the window closed: {0} (must be 0 - else a relaunch from the same console stacks them)" -f $ours.Count)
}
