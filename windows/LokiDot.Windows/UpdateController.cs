using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;

namespace LokiDot;

// Network metadata may be checked automatically. Download/install is a separate,
// explicit user decision and never runs from a timer alone.
internal sealed class UpdateController : IDisposable
{
    readonly Window owner;
    readonly Button check;
    readonly CheckBox automatic;
    readonly TextBlock status;
    readonly UpdateClient client = new();
    readonly CancellationTokenSource lifetime = new();
    readonly DispatcherTimer daily = new() { Interval = TimeSpan.FromDays(1) };
    bool busy;

    internal UpdateController(Window owner, Button check, CheckBox automatic, TextBlock status, bool enabled)
    {
        this.owner = owner; this.check = check; this.automatic = automatic; this.status = status;
        automatic.IsChecked = !enabled || UpdateStorage.LoadAutomaticChecks();
        if (!enabled) { check.IsEnabled = false; automatic.IsEnabled = false; return; }
        check.Click += async (_, _) => await CheckAsync(manual: true);
        automatic.Checked += (_, _) => SavePreference(true);
        automatic.Unchecked += (_, _) => SavePreference(false);
        daily.Tick += async (_, _) => { if (automatic.IsChecked == true) await CheckAsync(manual: false); };
        owner.Loaded += async (_, _) => {
            try {
                await Task.Delay(TimeSpan.FromSeconds(15), lifetime.Token);
                if (automatic.IsChecked == true) await CheckAsync(manual: false);
                if (!lifetime.IsCancellationRequested) daily.Start();
            } catch (OperationCanceledException) { }
        };
    }
    void SavePreference(bool value) {
        try { UpdateStorage.SaveAutomaticChecks(value); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or InvalidDataException) {
            MessageBox.Show(owner, "This setting could not be saved. Your choice applies until you close Zoomies. " + e.Message, "Update preference", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
    async Task CheckAsync(bool manual)
    {
        if (busy || lifetime.IsCancellationRequested) return;
        busy = true; check.IsEnabled = false;
        if (manual) status.Text = "Checking for updates…";
        bool approved = false;
        try {
            var release = await client.CheckAsync(lifetime.Token);
            if (lifetime.IsCancellationRequested || (!manual && automatic.IsChecked != true)) return;
            if (release.Version.CompareTo(ReleaseVersion.Current) <= 0) {
                if (manual) status.Text = $"You're up to date (version {ReleaseVersion.Current}).";
                return;
            }
            status.Text = $"Version {release.Version} is available.";
            approved = Confirm(release);
            if (!approved || lifetime.IsCancellationRequested) return;
            status.Text = $"Downloading and verifying version {release.Version}…";
            using var installer = await client.DownloadAsync(release, userApproved: approved, lifetime.Token);
            lifetime.Token.ThrowIfCancellationRequested();
            status.Text = "Opening Windows Installer…";
            using var guard = await installer.LaunchAsync(userApproved: approved, lifetime.Token);
            // Normal Close triggers the same pet/timer cleanup as closing the controls window.
            owner.Close();
        } catch (Exception e) {
            if (!lifetime.IsCancellationRequested && (manual || approved)) {
                status.Text = e is InstallerHandoffException ? "Installer handoff not confirmed." : "Update not installed.";
                string detail = e is OperationCanceledException ? "The request timed out. Check your connection and try again." : e.Message;
                MessageBox.Show(owner, "The update could not be completed. " + detail, "LokiDot update", MessageBoxButton.OK, MessageBoxImage.Warning);
            }
            // Background offline, malformed-feed and rate-limit failures stay silent.
        } finally {
            busy = false;
            if (!lifetime.IsCancellationRequested) check.IsEnabled = true;
        }
    }
    bool Confirm(UpdateRelease release)
    {
        var dialog = new Window {
            Owner = owner, Title = "LokiDot Zoomies update", Width = 460, SizeToContent = SizeToContent.Height,
            WindowStartupLocation = WindowStartupLocation.CenterOwner, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false
        };
        var panel = new StackPanel { Margin = new(24) };
        panel.Children.Add(new TextBlock { Text = $"Installed: {ReleaseVersion.Current}\nAvailable: {release.Version}", FontSize = 20, Margin = new(0,0,0,16) });
        panel.Children.Add(new TextBlock {
            TextWrapping = TextWrapping.Wrap,
            Text = $"Download the Windows installer ({release.Size / 1048576d:F1} MiB), verify it, and start installation?\n\nIt installs for all users in {Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "LokiDot Zoomies Preview")}, including when you run a portable copy. The installer requires administrator approval.\n\nWindows Installer finishes the installation. Zoomies closes after the installer opens and does not restart automatically."
        });
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new(0,20,0,0) };
        var later = new Button { Content = "Later", IsCancel = true, Padding = new(14,7,14,7), Margin = new(0,0,10,0) };
        var install = new Button { Content = "Download and Install", Padding = new(14,7,14,7) };
        later.Click += (_, _) => dialog.DialogResult = false;
        install.Click += (_, _) => dialog.DialogResult = true;
        buttons.Children.Add(later); buttons.Children.Add(install); panel.Children.Add(buttons); dialog.Content = panel;
        return dialog.ShowDialog() == true;
    }
    public void Dispose() { lifetime.Cancel(); daily.Stop(); client.Dispose(); }
}
