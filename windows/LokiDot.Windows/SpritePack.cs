using System.Buffers.Binary;
using System.IO;
using System.Diagnostics.CodeAnalysis;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32.SafeHandles;

namespace LokiDot;

[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record Animation(int Row, int Column, int FrameCount, double Fps);
[JsonUnmappedMemberHandling(JsonUnmappedMemberHandling.Disallow)]
public sealed record Manifest(int SchemaVersion, string Format, string Id, string Name, string Image,
    int FrameWidth, int FrameHeight, Dictionary<string, Animation> Animations);

public sealed class SpritePack
{
    public Manifest Manifest { get; }
    public Dictionary<string, BitmapSource[]> Frames { get; } = [];
    public override string ToString() => Manifest.Name;
    internal static readonly string[] States = ["idle", "running-right", "running-left", "waving", "jumping", "failed", "waiting", "running", "review", "look"];
    static readonly int[] Counts = [6, 8, 8, 4, 5, 8, 6, 6, 6, 16];
    static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, RespectRequiredConstructorParameters = true, MaxDepth = 8 };

    public static SpritePack Load(string directory)
    {
        directory = Path.GetFullPath(directory);
        Require(Regex.IsMatch(directory, @"\A[A-Za-z]:\\") && new DriveInfo(Path.GetPathRoot(directory)!).DriveType != DriveType.Network, "Choose a local drive folder; network shares are not supported.");
        for (DirectoryInfo? node = new(directory); node != null; node = node.Parent)
            Require((node.Attributes & FileAttributes.ReparsePoint) == 0, "Pack folder and its parents cannot be links or reparse points.");
        // Hold the directory without delete sharing until both bounded snapshots are read.
        using var folder = Open(directory, true);
        var manifest = Decode(Read(Path.Combine(directory, "manifest.json"), 32768, folder));
        ImageName(manifest.Image);
        return new(manifest, Read(Path.Combine(directory, manifest.Image), 16 * 1024 * 1024, folder));
    }
    internal static Manifest Decode(byte[] bytes)
    {
        Require(bytes.Length <= 32768, "manifest.json exceeds 32 KiB.");
        // Reject duplicate keys as well as unknown fields; ambiguous data is not a pack.
        using var doc = JsonDocument.Parse(bytes, new() { MaxDepth = 8 });
        void Unique(JsonElement value)
        {
            if (value.ValueKind != JsonValueKind.Object) return;
            HashSet<string> keys = [];
            foreach (var p in value.EnumerateObject()) { Require(keys.Add(p.Name), $"Duplicate field: {p.Name}."); Unique(p.Value); }
        }
        Unique(doc.RootElement);
        return JsonSerializer.Deserialize<Manifest>(bytes, Json) ?? throw new InvalidDataException("Missing manifest.");
    }
    internal static void ImageName(string name) => Require(!string.IsNullOrEmpty(name) && System.Text.Encoding.UTF8.GetByteCount(name) <= 128 && !name.StartsWith('.') && name.EndsWith(".png", StringComparison.OrdinalIgnoreCase) && name.IndexOfAny(Path.GetInvalidFileNameChars()) < 0 && !name.Any(char.IsControl), "image must be a plain PNG filename inside the pack folder.");
    internal SpritePack(Manifest m, byte[] png)
    {
        Manifest = m;
        Require(m.SchemaVersion == 1 && m.Format is "zoomies-v1" or "pet-v2", "Use schemaVersion 1 and zoomies-v1 or pet-v2.");
        Require(m.Id != null && Regex.IsMatch(m.Id, @"\A[a-z][a-z0-9-]{0,31}\z"), "id must use 1–32 lowercase letters, digits or hyphens, starting with a letter.");
        Require(!string.IsNullOrWhiteSpace(m.Name) && m.Name.EnumerateRunes().Count() <= 40 && !m.Name.Any(char.IsControl) && m.Name.IndexOfAny(['/', '\\']) < 0, "name must be 1–40 printable characters without slashes.");
        ImageName(m.Image);
        Require(m.FrameWidth is >= 8 and <= 512 && m.FrameHeight is >= 8 and <= 512, "Frame dimensions must be 8–512 pixels.");
        var (width, height) = ValidatePng(png);
        Require(width <= 4096 && height <= 4096 && (long)width * height <= 8388608 && width % m.FrameWidth == 0 && height % m.FrameHeight == 0, "PNG must fit the frame grid, at most 4096 per side and 8,388,608 pixels.");
        var expected = m.Format == "pet-v2" ? States : States[..3];
        Require(m.Animations != null && m.Animations.Keys.Order().SequenceEqual(expected.Order()), "Supply exactly the required animation states for the format.");
        if (m.Format == "pet-v2") Require(width == 1536 && height == 2288 && m.FrameWidth == 192 && m.FrameHeight == 208, "pet-v2 requires a 1536 × 2288 PNG and 192 × 208 cells.");
        using var stream = new MemoryStream(png, false);
        var decoder = new PngBitmapDecoder(stream, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnLoad);
        Require(decoder.Frames.Count == 1, "Supply a single PNG image.");
        var atlas = new FormatConvertedBitmap(decoder.Frames[0], PixelFormats.Bgra32, null, 0);
        int columns = width / m.FrameWidth, rows = height / m.FrameHeight;
        HashSet<int> occupied = [];
        for (int state = 0; state < expected.Length; state++)
        {
            string name = expected[state]; var a = m.Animations![name];
            Require(a != null && a.FrameCount >= (name == "idle" ? 1 : 2) && a.FrameCount <= 64 && double.IsFinite(a.Fps) && a.Fps is >= .5 and <= 30, $"{name}: frameCount or fps out of range.");
            Require(a!.Row >= 0 && a.Row < rows && a.Column >= 0 && a.Column < columns, $"{name}: cell outside PNG.");
            if (m.Format == "pet-v2") Require(a.Row == state && a.Column == 0 && a.FrameCount == Counts[state], $"{name}: incorrect pet-v2 row or count.");
            int start = a.Row * columns + a.Column;
            Require(start + a.FrameCount <= rows * columns, $"{name}: declared frames extend beyond PNG.");
            var frames = new BitmapSource[a.FrameCount];
            for (int i = 0; i < frames.Length; i++)
            {
                int cell = start + i;
                Require(occupied.Add(cell), "Animation frames overlap.");
                var frame = Crop(cell); var (min, max) = Alpha(frame);
                Require(max > 0 && min == 0, $"{name} frame {i + 1}: cell must contain visible artwork and a fully transparent background pixel.");
                frame.Freeze(); frames[i] = frame;
            }
            Frames[name] = frames;
        }
        if (m.Format == "pet-v2")
            for (int cell = 0; cell < columns * rows; cell++)
                if (!occupied.Contains(cell)) Require(Alpha(Crop(cell)).max == 0, "Unused pet-v2 cells must be transparent.");
        CroppedBitmap Crop(int cell) => new(atlas, new Int32Rect(cell % columns * m.FrameWidth, cell / columns * m.FrameHeight, m.FrameWidth, m.FrameHeight));
    }
    static (byte min, byte max) Alpha(BitmapSource frame)
    {
        byte[] pixels = new byte[frame.PixelWidth * frame.PixelHeight * 4]; frame.CopyPixels(pixels, frame.PixelWidth * 4, 0);
        byte min = 255, max = 0;
        for (int i = 3; i < pixels.Length; i += 4) { min = Math.Min(min, pixels[i]); max = Math.Max(max, pixels[i]); }
        return (min, max);
    }
    internal static (int width, int height) ValidatePng(byte[] data)
    {
        Require(data.Length <= 16 * 1024 * 1024 && data.Length >= 33 && data.AsSpan(0, 8).SequenceEqual(new byte[] {137,80,78,71,13,10,26,10}), "Supply a complete PNG smaller than 16 MiB.");
        int offset = 8, width = 0, height = 0; bool pixels = false;
        while (offset <= data.Length - 12)
        {
            uint size = BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(offset));
            Require(size <= data.Length - offset - 12, "Truncated PNG chunk.");
            int end = offset + 8 + (int)size; string kind = System.Text.Encoding.ASCII.GetString(data, offset + 4, 4);
            uint crc = uint.MaxValue;
            for (int i = offset + 4; i < end; i++) { crc ^= data[i]; for (int b = 0; b < 8; b++) crc = (crc >> 1) ^ ((crc & 1) != 0 ? 0xedb88320u : 0); }
            Require((crc ^ uint.MaxValue) == BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(end)) && kind != "acTL", "Invalid PNG checksum or animated PNG.");
            if (offset == 8)
            {
                Require(kind == "IHDR" && size == 13, "Missing PNG header.");
                width = checked((int)BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(16))); height = checked((int)BinaryPrimitives.ReadUInt32BigEndian(data.AsSpan(20)));
                Require(width > 0 && height > 0, "Empty PNG.");
            }
            else Require(kind != "IHDR", "Duplicate PNG header.");
            pixels |= kind == "IDAT";
            if (kind == "IEND") { Require(size == 0 && pixels && end + 4 == data.Length, "Invalid PNG end marker."); return (width, height); }
            offset = end + 4;
        }
        throw new InvalidDataException("Missing PNG end marker.");
    }
    static byte[] Read(string path, int maximum, SafeFileHandle folder)
    {
        using var handle = Open(path, false);
        Require(string.Equals(Path.GetDirectoryName(FinalPath(handle)), FinalPath(folder), StringComparison.OrdinalIgnoreCase), "Pack file resolved outside the selected folder.");
        using var stream = new FileStream(handle, FileAccess.Read);
        Require(stream.Length <= maximum, $"{Path.GetFileName(path)} exceeds {maximum} bytes.");
        byte[] bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes); return bytes;
    }
    static SafeFileHandle Open(string path, bool directory)
    {
        var handle = CreateFile(path, 0x80000000, 1, IntPtr.Zero, 3, 0x00200000u | (directory ? 0x02000000u : 0), IntPtr.Zero);
        if (handle.IsInvalid) { handle.Dispose(); throw new IOException($"Cannot open {Path.GetFileName(path)}. Choose a local pack folder with readable regular files."); }
        if (GetFileType(handle) != 1 || !GetFileInformationByHandle(handle, out var info) || (info.Attributes & 0x400) != 0 || ((info.Attributes & 0x10) != 0) != directory)
        { handle.Dispose(); throw new IOException("Links, reparse points and non-regular pack files are not supported."); }
        return handle;
    }
    static string FinalPath(SafeFileHandle handle)
    {
        var path = new System.Text.StringBuilder(32768);
        uint length = GetFinalPathNameByHandle(handle, path, (uint)path.Capacity, 0);
        Require(length > 0 && length < path.Capacity, "Could not resolve the selected local pack path.");
        return path.ToString().TrimEnd('\\');
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle handle, System.Text.StringBuilder path, uint length, uint flags);
    [DllImport("kernel32.dll")] static extern uint GetFileType(SafeFileHandle handle);
    [StructLayout(LayoutKind.Sequential)] struct FileInfo { public uint Attributes; public System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write; public uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow; }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)] static extern SafeFileHandle CreateFile(string path, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)] [return: MarshalAs(UnmanagedType.Bool)] static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInfo info);
    internal static void Require([DoesNotReturnIf(false)] bool condition, string message) { if (!condition) throw new InvalidDataException(message); }
}
