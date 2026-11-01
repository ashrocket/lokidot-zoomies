using System.IO;
using System.Text;
using System.Text.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Interop;

namespace LokiDot;
internal static class SelfTest
{
    public static int Run(string[] args)
    {
        string evidence = Argument("--evidence") ?? Path.Combine(Environment.CurrentDirectory, "evidence");
        Directory.CreateDirectory(evidence); List<string> results = [];
        try {
            var app = new App { ShutdownMode = ShutdownMode.OnExplicitShutdown };
            void Check(bool ok, string name) { SpritePack.Require(ok, "Self-test failed: " + name); results.Add("PASS " + name); }
            void Reject(Action action, string name) {
                try { action(); } catch (Exception e) when (e is InvalidDataException or JsonException or IOException or ArgumentException or OverflowException or NotSupportedException) { results.Add("PASS reject " + name); return; }
                throw new InvalidDataException("Accepted invalid fixture: " + name);
            }
            var packs = new[] { "whippet", "beagle", "robot-loki" }.Select(id => SpritePack.Load(Path.Combine(AppContext.BaseDirectory,"Characters",id))).ToArray();
            Check(packs.Length == 3 && packs.All(p => p.Frames.Count >= 3), "bundled public packs decoded and every declared frame inspected");
            string json = """
                {"schemaVersion":1,"format":"zoomies-v1","id":"test","name":"Test","image":"atlas.png","frameWidth":8,"frameHeight":8,"animations":{"idle":{"row":0,"column":0,"frameCount":1,"fps":8},"running-right":{"row":1,"column":0,"frameCount":2,"fps":8},"running-left":{"row":2,"column":0,"frameCount":2,"fps":8}}}
                """;
            Manifest Decode(string text) => SpritePack.Decode(Encoding.UTF8.GetBytes(text));
            var manifest = Decode(json); var png = Fixture(false,false);
            var simplePack = new SpritePack(manifest,png);
            Check(simplePack.Frames["running-left"].Length == 2,"zoomies-v1 accepted");
            Reject(() => ControlsWindow.ValidateRoutine([simplePack], MotionStyle.Prance), "Prance without jumping artwork");
            Reject(() => ControlsWindow.ValidateRoutine([packs[0], simplePack], MotionStyle.Prance), "All dogs Prance includes a pack without jumping artwork");
            ControlsWindow.ValidateRoutine([simplePack], MotionStyle.Zoomies);
            ControlsWindow.ValidateRoutine([simplePack], MotionStyle.Circle);
            ControlsWindow.ValidateRoutine(packs, MotionStyle.Prance);
            results.Add("PASS simple-pack running routines and full-pack Prance remain available");
            Reject(() => Decode(json.Replace("\"name\":\"Test\"", "\"name\":\"Test\",\"command\":\"run\"")), "executable / unknown root field");
            Reject(() => Decode(json.Replace("\"fps\":8", "\"fps\":8,\"script\":\"run\"")), "unknown animation field");
            Reject(() => Decode(json.Replace("\"schemaVersion\":1,", "")), "missing required field");
            Reject(() => Decode(json.Replace("\"schemaVersion\":1,", "\"schemaVersion\":1,\"schemaVersion\":1,")), "duplicate JSON key");
            Reject(() => SpritePack.Decode(new byte[32769]), "oversized JSON");
            foreach (var name in new[] { "../atlas.png", "https://a/a.png", "a:stream.png", ".atlas.png", "a\\b.png" }) Reject(() => SpritePack.ImageName(name), "unsafe filename " + name);
            Reject(() => new SpritePack(manifest with { FrameWidth=513 },png), "frame size limit");
            Reject(() => new SpritePack(manifest with { Animations=new(manifest.Animations) { ["unknown"] = new(0,0,1,8) } },png), "unknown animation");
            Reject(() => new SpritePack(manifest with { Animations=new(manifest.Animations) { ["running-left"] = new(1,0,2,8) } },png), "overlapping frames");
            Reject(() => new SpritePack(manifest with { Animations=new(manifest.Animations) { ["idle"] = new(0,0,1,31) } },png), "fps limit");
            Reject(() => new SpritePack(manifest with { Animations=new(manifest.Animations) { ["running-left"] = new(2,1,2,8) } },png), "truncated frame grid");
            Reject(() => new SpritePack(manifest,Fixture(true,false)), "empty declared frames");
            Reject(() => new SpritePack(manifest,Fixture(false,true)), "opaque declared frames");
            var corrupt=(byte[])png.Clone(); corrupt[29]^=1; Reject(() => new SpritePack(manifest,corrupt), "PNG CRC corruption");
            Reject(() => new SpritePack(manifest,png[..^1]), "truncated PNG");
            Reject(() => new SpritePack(manifest,[..png,0]), "PNG trailing bytes");
            Reject(() => new SpritePack(manifest,new byte[16*1024*1024+1]), "oversized PNG");
            string scratch=Path.Combine(Path.GetTempPath(),"lokidot-tests-"+Guid.NewGuid()); Directory.CreateDirectory(scratch);
            try {
                File.WriteAllText(Path.Combine(scratch,"manifest.json"),json); File.WriteAllBytes(Path.Combine(scratch,"atlas.png"),png);
                Check(SpritePack.Load(scratch).Manifest.Id=="test","bounded local snapshot");
                string linked=scratch+"-link";
                // Junctions work without Developer Mode or symlink privilege.
                var process=System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo("cmd.exe", $"/c mklink /J \"{linked}\" \"{scratch}\"") { UseShellExecute=false,CreateNoWindow=true });
                process!.WaitForExit(); Check(process.ExitCode==0,"junction fixture created");
                try { Reject(() => SpritePack.Load(linked),"directory reparse point"); } finally { Directory.Delete(linked); }
            } finally { Directory.Delete(scratch,true); }
            foreach(var bounds in new[] { new Rect(0,0,1920,1080), new Rect(-900,0,900,1600), new Rect(0,0,320,240) }) {
                var motion=new Motion(bounds);
                foreach(var style in Enum.GetValues<MotionStyle>()) for(int i=0;i<3;i++) {
                    var first=motion.Sample(style,0,i,3); var last=motion.Sample(style,1,i,3);
                    Check((first.Point-last.Point).Length < .001,$"{style} closed endpoints {bounds.Size} dog {i}");
                    for(int step=0;step<=1000;step++) {
                        var p=motion.Sample(style,step/1000d,i,3);
                        SpritePack.Require(double.IsFinite(p.Point.X) && double.IsFinite(p.Point.Y) && bounds.Contains(p.Point) && p.Facing is >= -1 and <= 1 && p.ScaleX>0 && p.ScaleY>0,"Motion escaped bounds or became nonfinite.");
                    }
                }
            }
            double previous=0; for(int i=0;i<=1000;i++) { double value=Motion.Distance(i/1000d); SpritePack.Require(value>=previous-1e-12,"Distance reversed."); previous=value; }
            results.Add("PASS bounded finite motion, monotonic distance and routine closure");
            var controls=new ControlsWindow(); controls.Show(); controls.UpdateLayout();
            Save(controls,Path.Combine(evidence,"controls.png")); controls.Close();
            var pet=new PetWindow(packs[0],new Rect(0,0,1920,1080),0,1); pet.Show(); pet.Draw(MotionStyle.Prance,.4,false,2); pet.UpdateLayout();
            var image=Save(pet,Path.Combine(evidence,"sprite-render.png")); byte[] pixels=new byte[image.PixelWidth*image.PixelHeight*4]; image.CopyPixels(pixels,image.PixelWidth*4,0);
            Check(Enumerable.Range(0,pixels.Length/4).Any(i=>pixels[i*4+3]>0) && Enumerable.Range(0,pixels.Length/4).Any(i=>pixels[i*4+3]==0),"WPF render contains transparent and visible pixels");
            bool BorderIsClear(int x, int y) => pixels[(y * image.PixelWidth + x) * 4 + 3] == 0;
            Check(Enumerable.Range(0, image.PixelWidth).All(x => BorderIsClear(x, 0) && BorderIsClear(x, image.PixelHeight - 1))
                && Enumerable.Range(0, image.PixelHeight).All(y => BorderIsClear(0, y) && BorderIsClear(image.PixelWidth - 1, y)), "transformed WPF render retains a transparent border inside the padded window");
            Check(pet.HasArtworkTransform && pet.RenderTransform.Value.IsIdentity, "bank and squash transform inner artwork, leaving Window transform at identity");
            foreach (var bounds in new[] { new Rect(0,0,1920,1080), new Rect(-900,0,900,1600), new Rect(0,0,320,240) }) {
                var performer = new PetWindow(packs[0], bounds, 0, 1); performer.Show();
                try {
                    foreach (var style in Enum.GetValues<MotionStyle>()) for (int step = 0; step <= 80; step++) {
                        performer.Draw(style, step/80d, false, 0); performer.UpdateLayout();
                        var artwork = performer.ArtworkBounds;
                        SpritePack.Require(artwork.Width > 0 && artwork.Height > 0 && new Rect(0,0,performer.ActualWidth,performer.ActualHeight).Contains(artwork), "Transformed artwork clipped its padded pet window.");
                        SpritePack.Require(bounds.Contains(new Rect(performer.Left,performer.Top,performer.Width,performer.Height)), "Padded pet window escaped motion bounds.");
                    }
                } finally { performer.Close(); }
            }
            results.Add("PASS transformed artwork and padded pet windows fit across all routines and screen fixtures");
            Check(pet.AllowsTransparency && pet.Topmost && !pet.ShowActivated && !pet.IsHitTestVisible,"desktop window managed behavior");
            long flags=NativeFlags(new WindowInteropHelper(pet).Handle,-20).ToInt64();
            Check((flags & (0x20|0x08000000|0x80))==(0x20|0x08000000|0x80),"native click-through no-activate tool-window flags");
            pet.Close(); app.Shutdown();
            File.WriteAllLines(Path.Combine(evidence,"self-test.txt"),results); return 0;
        } catch(Exception e) { results.Add("FAIL "+e); File.WriteAllLines(Path.Combine(evidence,"self-test.txt"),results); return 1; }
        string? Argument(string name) { int index=Array.IndexOf(args,name); return index>=0 && index+1<args.Length?args[index+1]:null; }
    }
    static RenderTargetBitmap Save(Window window,string path) {
        var bitmap=new RenderTargetBitmap((int)window.ActualWidth,(int)window.ActualHeight,96,96,PixelFormats.Pbgra32); bitmap.Render(window);
        var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var stream=File.Create(path); encoder.Save(stream); return bitmap;
    }
    static byte[] Fixture(bool empty,bool opaque) {
        byte[] pixels=new byte[16*24*4];
        for(int y=0;y<24;y++) for(int x=0;x<16;x++) { int offset=(y*16+x)*4; pixels[offset+1]=180; pixels[offset+3]=empty?(byte)0:opaque?(byte)255:(byte)((x%8==4 && y%8==4)?255:0); }
        var bitmap=BitmapSource.Create(16,24,96,96,PixelFormats.Bgra32,null,pixels,16*4); var encoder=new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap)); using var stream=new MemoryStream(); encoder.Save(stream); return stream.ToArray();
    }
    [System.Runtime.InteropServices.DllImport("user32.dll",EntryPoint="GetWindowLongPtrW")] static extern IntPtr NativeFlags(IntPtr hwnd,int index);
}
