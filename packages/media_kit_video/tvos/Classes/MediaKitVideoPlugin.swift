import Flutter

// tvOS: video is rendered by video_surface (Metal); this plugin only registers.
public class MediaKitVideoPlugin: NSObject, FlutterPlugin {
  public static func register(with _: FlutterPluginRegistrar) {}
}
