using System.Windows;
namespace LokiDot;

public enum MotionStyle { Zoomies, Circle, Prance }
public readonly record struct Pose(Point Point, double Facing, double Bank, double ScaleX, double ScaleY, double? Jump, double Stride);

// Same closed Catmull–Rom/Bézier route and distance lookup as ZoomiesCore.
public sealed class Motion
{
    static readonly Point[] Knots = [new(.76,.80),new(.20,.80),new(.09,.63),new(.30,.56),new(.79,.57),new(.92,.40),new(.84,.20),new(.63,.12),new(.46,.22),new(.57,.36),new(.71,.25),new(.57,.08),new(.29,.12),new(.12,.31),new(.24,.46),new(.49,.41),new(.73,.55),new(.89,.72)];
    readonly (Point a, Point b, Point c, Point d)[] curves;
    readonly List<(double distance, double parameter)> table = [(0, 0)];
    readonly Rect safe;
    readonly double length;
    readonly double scale;
    public double SpriteWidth => 144 * scale;
    public double SpriteHeight => 156 * scale;
    public static double Duration(MotionStyle style) => style switch { MotionStyle.Zoomies => 16, MotionStyle.Circle => 8, _ => 7 };
    public Motion(Rect bounds)
    {
        scale = Math.Min(1, Math.Max(.05, Math.Min(bounds.Width / 600, bounds.Height / 450)));
        double radius = Math.Sqrt(SpriteWidth * SpriteWidth + SpriteHeight * SpriteHeight) / 2 + 12 * scale;
        safe = new(bounds.X + Math.Min(radius, bounds.Width / 2), bounds.Y + Math.Min(radius, bounds.Height / 2), Math.Max(0, bounds.Width - 2 * radius), Math.Max(0, bounds.Height - 2 * radius));
        var points = Knots.Select(p => new Point(safe.X + p.X * safe.Width, safe.Y + p.Y * safe.Height)).ToArray();
        curves = Enumerable.Range(0, points.Length).Select(i => {
            int n = points.Length; var start = points[i]; var end = points[(i + 1) % n];
            return (start, start + (end - points[(i + n - 1) % n]) * .20, end - (points[(i + 2) % n] - start) * .20, end);
        }).ToArray();
        var previous = Curve(0, 0).point;
        for (int i = 0; i < curves.Length; i++) for (int step = 1; step <= 120; step++) {
            double t = step / 120d; var p = Curve(i, t).point; length += (p - previous).Length; table.Add((length, i + t)); previous = p;
        }
    }
    public static double Distance(double t) { t = double.IsFinite(t) ? Math.Clamp(t, 0, 1) : 0; double eased = t - Math.Sin(2 * Math.PI * t) / (2 * Math.PI); return eased + .012 * Math.Sin(4 * Math.PI * eased); }
    (Point point, Vector tangent) Curve(int index, double t)
    {
        var (a,b,c,d) = curves[index]; double s = 1-t;
        Vector p = (Vector)a * (s*s*s) + (Vector)b * (3*s*s*t) + (Vector)c * (3*s*t*t) + (Vector)d * (t*t*t);
        Vector tangent = (b-a)*(3*s*s)+(c-b)*(6*s*t)+(d-c)*(3*t*t);
        return ((Point)p, tangent);
    }
    static (double facing, double bank) Turn(Vector tangent)
    {
        if (tangent.Length < .00001) return (-1, 0);
        double facing = Math.Tanh(tangent.X / tangent.Length * 5);
        return (facing, Math.Clamp(Math.Atan2(tangent.Y, Math.Abs(tangent.X)), -.6, .6) * facing);
    }
    public Pose Sample(MotionStyle style, double progress, int index = 0, int count = 1)
    {
        double t = double.IsFinite(progress) ? Math.Clamp(progress, 0, 1) : 0, phase = (double)index / Math.Max(1, count), time = t * Duration(style);
        if (style == MotionStyle.Zoomies) {
            double distance = ((Distance(t) + phase + 1) % 1) * length;
            int low = 0, high = table.Count - 1;
            while (high - low > 1) { int middle = (low + high) / 2; if (table[middle].distance < distance) low = middle; else high = middle; }
            double span = table[high].distance - table[low].distance;
            double parameter = table[low].parameter + (span > 0 ? (distance - table[low].distance) / span : 0) * (table[high].parameter - table[low].parameter);
            int segment = Math.Min(curves.Length - 1, (int)parameter);
            var (point, tangent) = Curve(segment, parameter - segment); var (facing, bank) = Turn(tangent);
            return new(point, facing, bank * .55, .72 + .28 * Math.Abs(facing), 1, null, Distance(t) * Duration(style));
        }
        if (style == MotionStyle.Circle) {
            double angle = Math.PI/2 + 2*Math.PI*phase + 4*Math.PI*Distance(t), rx = Math.Min(180*scale, safe.Width*.30), ry = Math.Min(64*scale, safe.Height*.16);
            var (facing, bank) = Turn(new(-rx*Math.Sin(angle), ry*Math.Cos(angle))); double depth = .94-.06*Math.Sin(angle);
            return new(new(safe.X+safe.Width/2+rx*Math.Cos(angle), safe.Y+safe.Height/2+ry*Math.Sin(angle)), facing, bank*.35, depth*(.72+.28*Math.Abs(facing)), depth, null, Distance(t)*Duration(style));
        }
        double stagger = Math.Min(.45, (count-1)*.15), delay = count > 1 ? stagger*index/(count-1) : 0;
        double local = Math.Clamp((time-delay)/(Duration(style)-stagger),0,1), cycle=local*6, hop=local==1?1:cycle-Math.Floor(cycle), lift=Math.Pow(Math.Sin(Math.PI*hop),2), sway=Math.Sin(2*Math.PI*Distance(local));
        double anchor=safe.X+safe.Width*(index+1)/(count+1), amplitude=Math.Min(38*scale,safe.Width/(count+1)*.18), height=Math.Min(32*scale,safe.Height*.10), landing=Math.Pow(Math.Max(0,Math.Cos(2*Math.PI*hop)),8)*.035;
        return new(new(anchor+amplitude*sway,safe.Y+safe.Height*.65-height*lift),0,-.045*sway,1+landing,1-landing,hop,time);
    }
}
