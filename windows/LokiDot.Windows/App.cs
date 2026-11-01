using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;

namespace LokiDot;
public sealed class App : Application
{
    [STAThread] public static int Main(string[] args)
    {
        if (args.Contains("--self-test")) return SelfTest.Run(args);
        var app = new App { ShutdownMode = ShutdownMode.OnMainWindowClose };
        try { app.Run(new ControlsWindow()); return 0; }
        catch (Exception e) { MessageBox.Show(e.Message, "LokiDot Zoomies could not start", MessageBoxButton.OK, MessageBoxImage.Error); return 1; }
    }
}

public sealed class ControlsWindow : Window
{
    readonly ComboBox dogs = new() { MinWidth = 240, Margin = new(0, 4, 0, 12) };
    readonly ComboBox styles = new() { ItemsSource = Enum.GetValues<MotionStyle>(), SelectedIndex = 0, Margin = new(0, 4, 0, 12) };
    readonly CheckBox repeat = new() { Content = "Repeat after 24 seconds of rest", Margin = new(0, 4, 0, 12) };
    readonly TextBlock status = new() { TextWrapping = TextWrapping.Wrap, Margin = new(0, 12, 0, 0) };
    readonly Button pause = new() { Content = "Pause", Margin = new(0, 4, 0, 4) };
    readonly List<SpritePack> packs = [];
    readonly List<PetWindow> pets = [];
    readonly DispatcherTimer timer = new() { Interval = TimeSpan.FromMilliseconds(1000d/60) };
    readonly Stopwatch clock = new();
    bool paused;
    bool finished;
    MotionStyle activeStyle;
    public ControlsWindow()
    {
        Title = "LokiDot Zoomies — Windows preview"; Width = 390; Height = 540; ResizeMode = ResizeMode.CanMinimize;
        var panel = new StackPanel { Margin = new(24) }; Content = panel;
        panel.Children.Add(new TextBlock { Text = "Your desktop, with dogs", FontSize = 23, FontWeight = FontWeights.SemiBold });
        panel.Children.Add(new Label { Content = "Dog", Target = dogs }); panel.Children.Add(dogs);
        panel.Children.Add(new Label { Content = "Routine", Target = styles }); panel.Children.Add(styles); panel.Children.Add(repeat);
        var start = new Button { Content = "Start", Margin = new(0, 4, 0, 4) }; panel.Children.Add(start); panel.Children.Add(pause);
        var add = new Button { Content = "Add your dog…", Margin = new(0, 4, 0, 4) }; panel.Children.Add(add); panel.Children.Add(status);
        foreach (string id in new[] { "whippet", "beagle", "robot-loki" }) packs.Add(SpritePack.Load(Path.Combine(AppContext.BaseDirectory, "Characters", id)));
        RefreshDogs();
        start.Click += (_, _) => Start(); pause.Click += (_, _) => {
            if (finished || pets.Count == 0) return;
            paused = !paused; if (paused) clock.Stop(); else clock.Start(); pause.Content = paused ? "Resume" : "Pause"; status.Text = paused ? "Paused." : "Running.";
        };
        add.Click += (_, _) => {
            var picker = new OpenFolderDialog { Title = "Choose a dog pack folder containing manifest.json and its PNG" };
            if (picker.ShowDialog(this) != true) return;
            try {
                var pack = SpritePack.Load(picker.FolderName); packs.Add(pack); RefreshDogs(); dogs.SelectedIndex = packs.Count;
                status.Text = $"Added {pack.Manifest.Name} for this session.";
            } catch (Exception e) { MessageBox.Show(this, e.Message, "Could not add your dog", MessageBoxButton.OK, MessageBoxImage.Warning); }
        };
        timer.Tick += (_, _) => Tick(); timer.Start();
        Closed += (_, _) => { timer.Stop(); clock.Stop(); foreach (var pet in pets) pet.Close(); };
        status.Text = "Choose a dog and press Start. Close this window to quit.";
    }
    void RefreshDogs() { dogs.Items.Clear(); dogs.Items.Add("All dogs"); foreach (var p in packs) dogs.Items.Add(p); dogs.SelectedIndex = 0; }
    void Start()
    {
        var selected = dogs.SelectedItem is SpritePack pack ? new[] { pack } : packs.ToArray();
        var requestedStyle = styles.SelectedItem is MotionStyle style ? style : MotionStyle.Zoomies;
        try { ValidateRoutine(selected, requestedStyle); }
        catch (InvalidDataException error) {
            status.Text = error.Message;
            MessageBox.Show(this, error.Message, "Cannot start Prance", MessageBoxButton.OK, MessageBoxImage.Information);
            return;
        }
        foreach (var pet in pets) pet.Close(); pets.Clear();
        activeStyle = requestedStyle;
        var bounds = SystemParameters.WorkArea;
        for (int i = 0; i < selected.Length; i++) { var pet = new PetWindow(selected[i], bounds, i, selected.Length); pets.Add(pet); pet.Show(); }
        paused = false; finished = false; pause.Content = "Pause"; clock.Restart(); Tick();
    }
    internal static void ValidateRoutine(IEnumerable<SpritePack> selected, MotionStyle style)
    {
        if (style != MotionStyle.Prance) return;
        var missing = selected.Where(pack => !pack.Frames.ContainsKey("jumping")).Select(pack => pack.Manifest.Name).ToArray();
        if (missing.Length > 0)
            throw new InvalidDataException($"Prance needs authored jumping frames. {string.Join(", ", missing)} has no jumping animation. Choose Zoomies or Circle, or use a complete pet-v2 pack.");
    }
    void Tick()
    {
        if (pets.Count == 0 || paused || finished) return;
        MotionStyle style = activeStyle; double elapsed = clock.Elapsed.TotalSeconds, duration = Motion.Duration(style);
        if (!SystemParameters.ClientAreaAnimation) {
            foreach (var pet in pets) pet.Draw(style, 0, true, 0);
            status.Text = "Windows animations are off: dogs stay still. Enable Windows animation effects to run."; return;
        }
        if (!repeat.IsChecked.GetValueOrDefault() && elapsed >= duration) { elapsed = duration; finished = true; clock.Stop(); status.Text = "Done. Press Start to play again."; }
        double cycle = elapsed % (duration + 24); bool resting = finished || cycle >= duration;
        foreach (var pet in pets) pet.Draw(style, resting ? (finished ? 1 : 0) : cycle/duration, resting, elapsed);
        if (!finished) status.Text = resting ? $"Resting — next routine in {Math.Ceiling(duration+24-cycle)} seconds." : "Running. Desktop dogs let clicks pass through.";
    }
}

public sealed class PetWindow : Window
{
    readonly SpritePack pack;
    readonly Image left = new(), right = new();
    readonly Grid artwork;
    readonly Motion motion;
    readonly int index, count;
    public PetWindow(SpritePack pack, Rect bounds, int index, int count)
    {
        this.pack=pack; this.index=index; this.count=count; motion=new(bounds);
        // A circumscribed square leaves room for every bank angle and the 3.5% landing squash.
        // Keep the artwork centered here; only the inner visual may carry a WPF transform.
        double extent = Math.Ceiling(Math.Sqrt(motion.SpriteWidth * motion.SpriteWidth + motion.SpriteHeight * motion.SpriteHeight) * 1.04 + 4 * motion.SpriteHeight / 156);
        Width=extent; Height=extent; WindowStyle=WindowStyle.None; ResizeMode=ResizeMode.NoResize;
        AllowsTransparency=true; Background=Brushes.Transparent; Topmost=true; ShowInTaskbar=false; ShowActivated=false; Focusable=false; IsHitTestVisible=false;
        artwork = new Grid {
            Width = motion.SpriteWidth, Height = motion.SpriteHeight,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center,
            RenderTransformOrigin = new(.5, .5)
        };
        artwork.Children.Add(left); artwork.Children.Add(right);
        var surface = new Grid(); surface.Children.Add(artwork); Content = surface;
        SourceInitialized += (_, _) => {
            var hwnd=new WindowInteropHelper(this).Handle; var source=HwndSource.FromHwnd(hwnd) ?? throw new InvalidOperationException("Desktop window handle is unavailable.");
            long flags=GetWindowLongPtr(hwnd,-20).ToInt64(); SetWindowLongPtr(hwnd,-20,new IntPtr(flags|0x20|0x80|0x08000000));
            source.AddHook(Hook);
        };
        Draw(MotionStyle.Zoomies,0,true,0);
    }
    public void Draw(MotionStyle style,double progress,bool idle,double elapsed)
    {
        var pose=motion.Sample(style,progress,index,count);
        Left=pose.Point.X-Width/2; Top=pose.Point.Y-Height/2;
        if(idle) { left.Source=Frame("idle",elapsed); left.Opacity=1; right.Opacity=0; artwork.RenderTransform=Transform.Identity; return; }
        if(pose.Jump is double jump) {
            SpritePack.Require(pack.Frames.TryGetValue("jumping", out var jumps), "Prance requires authored jumping frames. Choose Zoomies or Circle for this pack.");
            left.Source=jumps[Math.Min(jumps.Length-1,(int)(jump*jumps.Length))]; left.Opacity=1; right.Opacity=0;
        } else {
            left.Source=Frame("running-left",pose.Stride); right.Source=Frame("running-right",pose.Stride);
            right.Opacity=(pose.Facing+1)/2; left.Opacity=1-right.Opacity;
        }
        var transforms=new TransformGroup(); transforms.Children.Add(new ScaleTransform(pose.ScaleX,pose.ScaleY)); transforms.Children.Add(new RotateTransform(pose.Bank*180/Math.PI)); artwork.RenderTransform=transforms;
    }
    internal Rect ArtworkBounds => artwork.TransformToAncestor(this).TransformBounds(new Rect(0, 0, artwork.ActualWidth, artwork.ActualHeight));
    internal bool HasArtworkTransform => !artwork.RenderTransform.Value.IsIdentity;
    System.Windows.Media.Imaging.BitmapSource Frame(string state,double time) { var frames=pack.Frames[state]; return frames[(int)(time*pack.Manifest.Animations[state].Fps)%frames.Length]; }
    static IntPtr Hook(IntPtr hwnd,int message,IntPtr wParam,IntPtr lParam,ref bool handled) {
        if(message==0x84) { handled=true; return new IntPtr(-1); } // HTTRANSPARENT
        if(message==0x21) { handled=true; return new IntPtr(3); } // MA_NOACTIVATE
        return IntPtr.Zero;
    }
    [DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] static extern IntPtr GetWindowLongPtr(IntPtr hwnd,int index);
    [DllImport("user32.dll",EntryPoint="SetWindowLongPtrW")] static extern IntPtr SetWindowLongPtr(IntPtr hwnd,int index,IntPtr value);
}
