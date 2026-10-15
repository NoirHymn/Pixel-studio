// PixelStudio - PS Touch style editor (batch 1)
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

// ============================================================
// Theme
// ============================================================
// ============================================================
// Palette (theme aware, set from AppTheme)
// ============================================================
class Pal {
  static bool dark = true;
  static Color accent = const Color(0xFF4F8CFF);
  static Color get onAccent =>
      accent.computeLuminance() > 0.45 ? const Color(0xFF0B0D14) : Colors.white;
  static Color get bg => dark ? const Color(0xFF0F1115) : const Color(0xFFEEF0F5);
  static Color get surface => dark ? const Color(0xFF1B1E25) : Colors.white;
  static Color get surface2 => dark ? const Color(0xFF242830) : const Color(0xFFF1F2F7);
  static Color get line => dark ? const Color(0x17FFFFFF) : const Color(0x1C141828);
  static Color get txt => dark ? const Color(0xFFE9EBF1) : const Color(0xFF161A2B);
  static Color get mut => dark ? const Color(0xFF9BA2B1) : const Color(0xFF596079);
  static Color get dim => dark ? const Color(0xFF626978) : const Color(0xFF9096AB);
  static Color get fill => dark ? const Color(0x0DFFFFFF) : const Color(0x0F141828);
  static Color get stageBg => dark ? const Color(0xFF14161C) : const Color(0xFFE3E6EE);
  static Color tint(double a) => accent.withValues(alpha: a);
}

Color get kBarTop => Pal.surface;
Color get kBarBottom => Pal.surface;
Color get kPanel => Pal.surface;
Color get kCanvasBg => Pal.stageBg;
Color get kMenuBg => Pal.surface;
Color get kBlue => Pal.accent;
const comingSoon = 'coming in the next batch';

TextStyle lbl(double size, {Color? color}) => TextStyle(
      fontWeight: FontWeight.w600,
      fontSize: size < 11 ? 11 : size,
      color: color ?? Pal.txt,
    );

BoxDecoration surfaceDeco({double radius = 22, Color? color}) => BoxDecoration(
      color: color ?? Pal.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Pal.line),
      boxShadow: const [
        BoxShadow(color: Color(0x40000000), blurRadius: 18, offset: Offset(0, 6)),
      ],
    );

class AppTheme extends ChangeNotifier {
  bool dark = true;
  Color accent = const Color(0xFF4F8CFF);
  bool haptics = true;

  static const accents = [
    Color(0xFF4F8CFF),
    Color(0xFF2ECC71),
    Color(0xFFFF7A2F),
    Color(0xFFA56BFF),
    Color(0xFFFF4F7B),
    Color(0xFF14C5C5),
  ];

  Future<File> _file() async {
    final d = await getApplicationDocumentsDirectory();
    return File('${d.path}/settings.json');
  }

  Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        dark = (m['dark'] as bool?) ?? true;
        accent = Color((m['accent'] as int?) ?? accent.toARGB32());
        haptics = (m['haptics'] as bool?) ?? true;
      }
    } catch (_) {}
    _apply();
  }

  void _apply() {
    Pal.dark = dark;
    Pal.accent = accent;
    gHaptics = haptics;
  }

  Future<void> _save() async {
    try {
      final f = await _file();
      await f.writeAsString(
          jsonEncode({'dark': dark, 'accent': accent.toARGB32(), 'haptics': haptics}));
    } catch (_) {}
  }

  void update({bool? dark, Color? accent, bool? haptics}) {
    if (dark != null) this.dark = dark;
    if (accent != null) this.accent = accent;
    if (haptics != null) this.haptics = haptics;
    _apply();
    _save();
    notifyListeners();
  }
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Pal.accent,
    brightness: Pal.dark ? Brightness.dark : Brightness.light,
  ).copyWith(primary: Pal.accent, onPrimary: Pal.onAccent, surface: Pal.surface);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Pal.bg,
    sliderTheme: SliderThemeData(
      activeTrackColor: Pal.accent,
      thumbColor: Pal.accent,
      inactiveTrackColor: Pal.line,
      overlayColor: Pal.tint(0.15),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Pal.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Pal.dark ? const Color(0xFFE9EBF1) : const Color(0xFF1B1E25),
      contentTextStyle: TextStyle(
        color: Pal.dark ? const Color(0xFF0F1115) : Colors.white,
        fontWeight: FontWeight.w500,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

// ============================================================
// Image helpers
// ============================================================
Future<ui.Image> renderImage(
    int w, int h, void Function(Canvas c) draw) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
  draw(c);
  final pic = rec.endRecording();
  final img = await pic.toImage(w, h);
  pic.dispose();
  return img;
}

Future<ui.Image> decodeBytes(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}

Future<ui.Image> imageFromRgba(Uint8List px, int w, int h) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, w, h, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

Future<Uint8List> pngBytes(ui.Image img) async {
  final d = await img.toByteData(format: ui.ImageByteFormat.png);
  return d!.buffer.asUint8List();
}

Future<Uint8List?> pickBytes(ImageSource src) async {
  final x = await ImagePicker().pickImage(source: src);
  if (x == null) return null;
  return x.readAsBytes();
}

Path dashPath(Path src, double on, double off) {
  final out = Path();
  for (final m in src.computeMetrics()) {
    double d = 0;
    while (d < m.length) {
      out.addPath(m.extractPath(d, math.min(d + on, m.length)), Offset.zero);
      d += on + off;
    }
  }
  return out;
}

// ============================================================
// Model
// ============================================================
class DocLayer {
  final int id;
  String name;
  ui.Image image;
  double opacity;
  bool visible;
  BlendMode blendMode;
  ui.Image? mask;
  Map<String, dynamic>? textMeta;

  DocLayer({
    required this.id,
    required this.name,
    required this.image,
    this.opacity = 1,
    this.visible = true,
    this.blendMode = BlendMode.srcOver,
    this.mask,
    this.textMeta,
  });

  DocLayer copy() => DocLayer(
        id: id,
        name: name,
        image: image,
        opacity: opacity,
        visible: visible,
        blendMode: blendMode,
        mask: mask,
        textMeta: textMeta,
      );
}

enum SelMode { replace, add, subtract, intersect }

enum Tool {
  stamp,
  brush,
  fxBrush,
  spray,
  eraser,
  wand,
  colorSelect,
  selBrush,
  smartSel,
  marquee,
  ellipse,
  lasso,
  polygon,
}

const List<List<Tool>> groups = [
  [Tool.stamp],
  [Tool.brush, Tool.fxBrush, Tool.spray, Tool.eraser],
  [Tool.wand, Tool.colorSelect, Tool.selBrush, Tool.smartSel],
  [Tool.marquee, Tool.ellipse, Tool.lasso, Tool.polygon],
];

String toolName(Tool t) {
  switch (t) {
    case Tool.stamp:
      return 'Clone Stamp Tool';
    case Tool.brush:
      return 'Paint Tool';
    case Tool.fxBrush:
      return 'Effect Brush Tool';
    case Tool.spray:
      return 'Spray Tool';
    case Tool.eraser:
      return 'Eraser Tool';
    case Tool.wand:
      return 'Magic Wand Tool';
    case Tool.colorSelect:
      return 'Color Select Tool';
    case Tool.selBrush:
      return 'Selection Brush Tool';
    case Tool.smartSel:
      return 'Smart Select Tool';
    case Tool.marquee:
      return 'Marquee Selection Tool';
    case Tool.ellipse:
      return 'Elliptical Marquee Tool';
    case Tool.lasso:
      return 'Lasso Tool';
    case Tool.polygon:
      return 'Polygonal Lasso Tool';
  }
}

IconData toolIconData(Tool t) {
  switch (t) {
    case Tool.stamp:
      return Icons.content_copy;
    case Tool.brush:
      return Icons.brush;
    case Tool.fxBrush:
      return Icons.palette;
    case Tool.spray:
      return Icons.blur_on;
    case Tool.eraser:
      return Icons.auto_fix_normal;
    case Tool.wand:
      return Icons.auto_fix_high;
    case Tool.colorSelect:
      return Icons.colorize;
    case Tool.selBrush:
      return Icons.draw;
    case Tool.smartSel:
      return Icons.auto_awesome;
    case Tool.marquee:
      return Icons.crop_square;
    case Tool.ellipse:
      return Icons.circle_outlined;
    case Tool.lasso:
      return Icons.gesture;
    case Tool.polygon:
      return Icons.polyline;
  }
}

Widget toolIcon(Tool t, double size, Color color) {
  if (t == Tool.marquee || t == Tool.ellipse) {
    return CustomPaint(
      size: Size(size, size),
      painter: _DashIconPainter(t == Tool.ellipse, color),
    );
  }
  return Icon(toolIconData(t), size: size, color: color);
}

class _DashIconPainter extends CustomPainter {
  final bool oval;
  final Color color;
  _DashIconPainter(this.oval, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
        size.width * 0.1, size.height * 0.18, size.width * 0.8, size.height * 0.64);
    final p = Path();
    if (oval) {
      p.addOval(r);
    } else {
      p.addRect(r);
    }
    canvas.drawPath(
      dashPath(p, size.width * 0.12, size.width * 0.09),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * 0.07
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _DashIconPainter old) =>
      old.oval != oval || old.color != color;
}

// ============================================================
// Projects (gallery storage)
// ============================================================
class ProjectInfo {
  final String id;
  String name;
  int w;
  int h;
  int modified;
  ProjectInfo(this.id, this.name, this.w, this.h, this.modified);
}

class ProjectStore extends ChangeNotifier {
  Directory? _root;
  String? rootPath;
  List<ProjectInfo> items = [];
  bool newestFirst = true;
  bool loaded = false;

  Future<Directory> root() async {
    if (_root != null) return _root!;
    final d = await getApplicationDocumentsDirectory();
    final r = Directory('${d.path}/projects');
    if (!await r.exists()) await r.create(recursive: true);
    _root = r;
    rootPath = r.path;
    return r;
  }

  Future<Directory> dirOf(String id) async {
    final r = await root();
    final d = Directory('${r.path}/$id');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  String newId() => DateTime.now().microsecondsSinceEpoch.toString();

  String nextName() {
    int mx = 0;
    final re = RegExp(r'^Untitled(\d+)$');
    for (final p in items) {
      final m = re.firstMatch(p.name);
      if (m != null) mx = math.max(mx, int.parse(m.group(1)!));
    }
    return 'Untitled${mx + 1}';
  }

  void _sort() {
    items.sort((a, b) =>
        newestFirst ? b.modified.compareTo(a.modified) : a.modified.compareTo(b.modified));
  }

  void toggleSort() {
    newestFirst = !newestFirst;
    _sort();
    notifyListeners();
  }

  Future<void> load() async {
    final r = await root();
    final list = <ProjectInfo>[];
    await for (final e in r.list()) {
      if (e is Directory) {
        final f = File('${e.path}/meta.json');
        if (await f.exists()) {
          try {
            final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
            list.add(ProjectInfo(
              e.path.split(Platform.pathSeparator).last,
              m['name'] as String,
              m['w'] as int,
              m['h'] as int,
              m['modified'] as int,
            ));
          } catch (_) {}
        }
      }
    }
    items = list;
    _sort();
    loaded = true;
    imageCache.clear();
    imageCache.clearLiveImages();
    notifyListeners();
  }

  void touch(ProjectInfo info) {
    final i = items.indexWhere((p) => p.id == info.id);
    if (i >= 0) {
      items[i] = info;
    } else {
      items.add(info);
    }
    _sort();
    notifyListeners();
  }

  Future<void> rename(ProjectInfo p, String name) async {
    final dir = await dirOf(p.id);
    final f = File('${dir.path}/meta.json');
    final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
    m['name'] = name;
    await f.writeAsString(jsonEncode(m));
    p.name = name;
    notifyListeners();
  }

  Future<void> delete(ProjectInfo p) async {
    final dir = await dirOf(p.id);
    if (await dir.exists()) await dir.delete(recursive: true);
    items.removeWhere((e) => e.id == p.id);
    notifyListeners();
  }
}

// ============================================================
// Editor state
// ============================================================
class _Snap {
  final List<DocLayer> layers;
  final int selected;
  final ui.Image? mask;
  final ui.Image? edge;
  final int w;
  final int h;
  _Snap(this.layers, this.selected, this.mask, this.edge, this.w, this.h);
}

class EditorState extends ChangeNotifier {
  static const int maxSide = 2048;
  static const int maxUndo = 15;

  ProjectStore? store;
  String? projectId;
  String projectName = '';
  void Function(String)? onToast;

  // document
  int docW = 1080;
  int docH = 1350;
  final List<DocLayer> layers = [];
  int selected = 0;
  int _nextId = 1;

  // tool settings
  Tool tool = Tool.brush;
  final List<int> groupIdx = [0, 0, 0, 0];
  Color color = Colors.black;
  double brushSize = 24;
  double brushOpacity = 1;
  double brushHardness = 0.8;
  SelMode selMode = SelMode.replace;
  bool antialias = true;
  double corners = 0;
  double tolerance = 27;
  bool contiguous = true;

  // ui flags
  String? menu;
  int fxTab = 0;
  bool toolMenuOpen = false;
  int? openGroup;
  bool layersOpen = false;
  String? busyMsg;

  // selection + clipboard
  ui.Image? selMask;
  ui.Image? selEdge;
  ui.Image? clipboard;

  // in-progress gestures (document coordinates)
  List<Offset> stroke = [];
  Offset? dragA;
  Offset? dragB;
  List<Offset> poly = [];
  bool _busy = false;

  // history
  final List<_Snap> _undo = [];
  final List<_Snap> _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // view
  double scale = 1;
  Offset offset = Offset.zero;
  Size viewport = Size.zero;
  bool _userZoomed = false;

  Timer? _saveTimer;
  bool _saving = false;

  // ---------- getters ----------
  DocLayer? get current => layers.isEmpty ? null : layers[selected];
  bool get hasSel => selMask != null;
  Rect get _rect => Rect.fromLTWH(0, 0, docW.toDouble(), docH.toDouble());
  bool get isPaintTool =>
      tool == Tool.brush ||
      tool == Tool.fxBrush ||
      tool == Tool.spray ||
      tool == Tool.eraser;
  double get _soft => tool == Tool.spray ? 0.7 : (1 - brushHardness);
  double get _op => tool == Tool.spray ? brushOpacity * 0.7 : brushOpacity;

  void toast(String m) => onToast?.call(m);

  // ---------- history ----------
  _Snap _snap() => _Snap(
      layers.map((e) => e.copy()).toList(), selected, selMask, selEdge, docW, docH);

  void _pushUndo() {
    _undo.add(_snap());
    if (_undo.length > maxUndo) _undo.removeAt(0);
    _redo.clear();
    _markDirty();
  }

  void _restore(_Snap s) {
    layers
      ..clear()
      ..addAll(s.layers.map((e) => e.copy()));
    selected = math.max(0, math.min(s.selected, layers.length - 1));
    selMask = s.mask;
    selEdge = s.edge;
    selEdge2 = s.edge;
    selEdges = [];
    if (selMask != null) _rebuildEdges();
    stroke = [];
    poly = [];
    xfActive = false;
    cropActive = false;
    if (docW != s.w || docH != s.h) {
      docW = s.w;
      docH = s.h;
      _fit();
    }
  }

  void undo() {
    if (_undo.isEmpty || _busy) return;
    _redo.add(_snap());
    _restore(_undo.removeLast());
    _markDirty();
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty || _busy) return;
    _undo.add(_snap());
    _restore(_redo.removeLast());
    _markDirty();
    notifyListeners();
  }

  Future<void> _guard(String msg, Future<void> Function() fn) async {
    if (_busy) return;
    _busy = true;
    busyMsg = msg;
    notifyListeners();
    try {
      await fn();
    } catch (e) {
      toast('Error: $e');
    }
    _busy = false;
    busyMsg = null;
    notifyListeners();
  }

  // ---------- project lifecycle ----------
  void _resetState() {
    selected = 0;
    _undo.clear();
    _redo.clear();
    selMask = null;
    selEdge = null;
    stroke = [];
    dragA = null;
    dragB = null;
    poly = [];
    menu = null;
    toolMenuOpen = false;
    openGroup = null;
    layersOpen = false;
    _userZoomed = false;
    _fit();
    notifyListeners();
  }

  Future<void> _startNew(int w, int h, ui.Image first) async {
    docW = w;
    docH = h;
    projectId = store?.newId() ?? DateTime.now().microsecondsSinceEpoch.toString();
    projectName = store?.nextName() ?? 'Untitled1';
    _nextId = 1;
    layers
      ..clear()
      ..add(DocLayer(id: _nextId++, name: 'Background', image: first));
    _resetState();
    await saveProject();
  }

  Future<void> createBlank(int w, int h) async {
    final bg = await renderImage(w, h, (c) {
      c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = Colors.white);
    });
    await _startNew(w, h, bg);
  }

  Future<void> _createFromImage(ui.Image src) async {
    var w = src.width.toDouble();
    var h = src.height.toDouble();
    final m = math.max(w, h);
    if (m > maxSide) {
      final k = maxSide / m;
      w = (w * k).roundToDouble();
      h = (h * k).roundToDouble();
    }
    final dw = w.round();
    final dh = h.round();
    final img = await renderImage(dw, dh, (c) {
      c.drawImageRect(
        src,
        Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
        Rect.fromLTWH(0, 0, dw.toDouble(), dh.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
    });
    await _startNew(dw, dh, img);
  }

  Future<void> createFromBytes(Uint8List bytes) async {
    final src = await decodeBytes(bytes);
    await _createFromImage(src);
    src.dispose();
  }

  Future<void> createFromClipboard() async {
    final c = clipboard;
    if (c == null) return;
    await _createFromImage(c);
  }

  Future<void> openProject(ProjectInfo info) async {
    final st = store;
    if (st == null) return;
    final dir = await st.dirOf(info.id);
    final m = jsonDecode(await File('${dir.path}/meta.json').readAsString())
        as Map<String, dynamic>;
    final ls = <DocLayer>[];
    for (final lm in (m['layers'] as List)) {
      final mm = lm as Map<String, dynamic>;
      final f = File('${dir.path}/l${mm['id']}.png');
      if (!await f.exists()) continue;
      final img = await decodeBytes(await f.readAsBytes());
      ui.Image? maskImg;
      if (mm['mask'] == true) {
        final mf = File('${dir.path}/m${mm['id']}.png');
        if (await mf.exists()) maskImg = await decodeBytes(await mf.readAsBytes());
      }
      ls.add(DocLayer(
        id: mm['id'] as int,
        name: mm['name'] as String,
        image: img,
        opacity: (mm['opacity'] as num).toDouble(),
        visible: mm['visible'] as bool,
        blendMode: BlendMode.values.firstWhere((b) => b.name == mm['blend'],
            orElse: () => BlendMode.srcOver),
        mask: maskImg,
        textMeta: (mm['text'] as Map?)?.cast<String, dynamic>(),
      ));
    }
    if (ls.isEmpty) throw Exception('Empty project');
    projectId = info.id;
    projectName = m['name'] as String;
    docW = m['w'] as int;
    docH = m['h'] as int;
    int mx = 0;
    for (final l in ls) {
      mx = math.max(mx, l.id);
    }
    _nextId = (m['nextId'] as int?) ?? (mx + 1);
    layers
      ..clear()
      ..addAll(ls);
    _resetState();
  }

  void _markDirty() {
    if (projectId == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 4), () {
      saveProject();
    });
  }

  Future<void> saveProject() async {
    _saveTimer?.cancel();
    final st = store;
    final id = projectId;
    if (st == null || id == null || layers.isEmpty || _saving) return;
    _saving = true;
    try {
      final dir = await st.dirOf(id);
      final metaLayers = <Map<String, dynamic>>[];
      final keep = <String>{'meta.json', 'thumb.png'};
      for (final l in layers) {
        final name = 'l${l.id}.png';
        keep.add(name);
        await File('${dir.path}/$name').writeAsBytes(await pngBytes(l.image));
        if (l.mask != null) {
          final mn = 'm${l.id}.png';
          keep.add(mn);
          await File('${dir.path}/$mn').writeAsBytes(await pngBytes(l.mask!));
        }
        metaLayers.add({
          'id': l.id,
          'name': l.name,
          'opacity': l.opacity,
          'visible': l.visible,
          'blend': l.blendMode.name,
          'mask': l.mask != null,
          'text': l.textMeta,
        });
      }
      final k = 300 / math.max(docW, docH);
      final tw = math.max(1, (docW * k).round());
      final th = math.max(1, (docH * k).round());
      final thumb = await renderImage(tw, th, (c) {
        c.scale(tw / docW, th / docH);
        paintDoc(c, preview: false);
      });
      await File('${dir.path}/thumb.png').writeAsBytes(await pngBytes(thumb));
      final now = DateTime.now().millisecondsSinceEpoch;
      await File('${dir.path}/meta.json').writeAsString(jsonEncode({
        'name': projectName,
        'w': docW,
        'h': docH,
        'modified': now,
        'nextId': _nextId,
        'layers': metaLayers,
      }));
      await for (final e in dir.list()) {
        if (e is File) {
          final n = e.path.split(Platform.pathSeparator).last;
          if (!keep.contains(n)) {
            try {
              await e.delete();
            } catch (_) {}
          }
        }
      }
      st.touch(ProjectInfo(id, projectName, docW, docH, now));
    } catch (e) {
      toast('Save failed: $e');
    }
    _saving = false;
  }

  Future<Uint8List> exportPng() async {
    final img = await renderImage(docW, docH, (c) => paintDoc(c, preview: false));
    return pngBytes(img);
  }

  // ---------- layers ----------
  Future<void> addLayer() async {
    final img = await renderImage(docW, docH, (c) {});
    _pushUndo();
    final id = _nextId++;
    layers.insert(selected + 1, DocLayer(id: id, name: 'Layer $id', image: img));
    selected += 1;
    notifyListeners();
  }

  Future<void> addImageLayer(Uint8List bytes) async {
    final src = await decodeBytes(bytes);
    final k = math.min(1.0, math.min(docW / src.width, docH / src.height));
    final w = src.width * k;
    final h = src.height * k;
    final dst = Rect.fromLTWH((docW - w) / 2, (docH - h) / 2, w, h);
    final img = await renderImage(docW, docH, (c) {
      c.drawImageRect(
        src,
        Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.high,
      );
    });
    src.dispose();
    _pushUndo();
    final id = _nextId++;
    layers.insert(selected + 1, DocLayer(id: id, name: 'Photo $id', image: img));
    selected += 1;
    notifyListeners();
  }

  void duplicateLayer() {
    final l = current;
    if (l == null) return;
    _pushUndo();
    final c = l.copy();
    final id = _nextId++;
    layers.insert(
      selected + 1,
      DocLayer(
        id: id,
        name: '${l.name} copy',
        image: c.image,
        opacity: l.opacity,
        visible: l.visible,
        blendMode: l.blendMode,
        mask: l.mask,
        textMeta: l.textMeta,
      ),
    );
    selected += 1;
    notifyListeners();
  }

  Future<void> mergeDown() async {
    if (selected == 0) {
      toast('No layer below');
      return;
    }
    final lower = layers[selected - 1];
    final upper = layers[selected];
    final img = await renderImage(docW, docH, (c) {
      paintLayers(c, [lower, upper], preview: false);
    });
    _pushUndo();
    final merged = DocLayer(id: lower.id, name: lower.name, image: img);
    layers.removeAt(selected);
    layers[selected - 1] = merged;
    selected -= 1;
    notifyListeners();
  }

  void deleteLayer(int i) {
    if (layers.length <= 1) return;
    _pushUndo();
    layers.removeAt(i);
    if (i < selected) selected -= 1;
    selected = math.max(0, math.min(selected, layers.length - 1));
    notifyListeners();
  }

  void selectLayer(int i) {
    selected = i;
    if (layers[i].mask == null) editMask = false;
    notifyListeners();
  }

  void toggleVisible(int i) {
    _pushUndo();
    layers[i].visible = !layers[i].visible;
    notifyListeners();
  }

  void beginLayerEdit() => _pushUndo();

  void setLayerOpacity(int i, double v) {
    layers[i].opacity = v;
    notifyListeners();
  }

  void setLayerName(int i, String n) {
    layers[i].name = n;
    notifyListeners();
  }

  void setBlend(int i, BlendMode m) {
    _pushUndo();
    layers[i].blendMode = m;
    notifyListeners();
  }

  void reorder(int from, int to) {
    if (from == to) return;
    _pushUndo();
    final selId = layers[selected].id;
    final l = layers.removeAt(from);
    layers.insert(to, l);
    selected = layers.indexWhere((e) => e.id == selId);
    notifyListeners();
  }

  // ---------- ui actions ----------
  void toggleMenu(String id) {
    menu = menu == id ? null : id;
    toolMenuOpen = false;
    openGroup = null;
    notifyListeners();
  }

  void closeMenu() {
    menu = null;
    notifyListeners();
  }

  bool closeOverlays() {
    final any = menu != null || toolMenuOpen;
    if (any) {
      menu = null;
      toolMenuOpen = false;
      openGroup = null;
      notifyListeners();
    }
    return any;
  }

  void setFxTab(int t) {
    fxTab = t;
    notifyListeners();
  }

  void toggleToolMenu() {
    toolMenuOpen = !toolMenuOpen;
    openGroup = null;
    menu = null;
    notifyListeners();
  }

  void toggleLayers() {
    layersOpen = !layersOpen;
    notifyListeners();
  }

  void tapGroup(int g) {
    if (groups[g].length == 1) {
      tool = groups[g][0];
      openGroup = null;
      toolMenuOpen = false;
      poly = [];
    } else if (openGroup == g) {
      openGroup = null;
    } else {
      openGroup = g;
      tool = groups[g][groupIdx[g]];
      poly = [];
    }
    notifyListeners();
  }

  void pickTool(int g, int j) {
    groupIdx[g] = j;
    tool = groups[g][j];
    openGroup = null;
    toolMenuOpen = false;
    poly = [];
    notifyListeners();
  }

  void setColor(Color c) {
    color = c;
    notifyListeners();
  }

  void setSize(double v) {
    brushSize = v;
    notifyListeners();
  }

  void setBrushOpacity(double v) {
    brushOpacity = v;
    notifyListeners();
  }

  void setHardness(double v) {
    brushHardness = v;
    notifyListeners();
  }

  void setSelMode(SelMode m) {
    selMode = m;
    notifyListeners();
  }

  void setCorners(double v) {
    corners = v;
    notifyListeners();
  }

  void setTolerance(double v) {
    tolerance = v;
    notifyListeners();
  }

  void toggleAntialias() {
    antialias = !antialias;
    notifyListeners();
  }

  void toggleContiguous() {
    contiguous = !contiguous;
    notifyListeners();
  }

  // ---------- painting ----------
  static void paintStroke(Canvas c, List<Offset> pts, Color color, double size,
      double opacity, double softness, bool erase) {
    if (pts.isEmpty) return;
    final paint = Paint()
      ..isAntiAlias = true
      ..color =
          erase ? const Color(0xFF000000) : color.withValues(alpha: opacity)
      ..blendMode = erase ? BlendMode.clear : BlendMode.srcOver;
    if (softness > 0.02) {
      paint.maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, size * softness * 0.3);
    }
    if (pts.length == 1) {
      c.drawCircle(pts.first, size / 2, paint);
      return;
    }
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = size
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
    } else {
      for (int i = 1; i < pts.length - 1; i++) {
        final mid = (pts[i] + pts[i + 1]) / 2;
        path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(pts.last.dx, pts.last.dy);
    }
    c.drawPath(path, paint);
  }

  void paintDoc(Canvas c, {required bool preview}) =>
      paintLayers(c, layers, preview: preview);

  void paintLayers(Canvas c, List<DocLayer> ls, {required bool preview}) {
    final rect = _rect;
    final cur = current;
    for (final l in ls) {
      if (!l.visible) continue;
      final p = Paint()
        ..color = Color.fromRGBO(0, 0, 0, l.opacity)
        ..blendMode = l.blendMode;
      c.saveLayer(rect, p);
      if (xfActive && identical(l, cur) && xfBase != null && xfFloat != null) {
        c.drawImage(xfBase!, Offset.zero, Paint());
        _drawXf(c, xfFloat!);
      } else if (gradActive && !_skipGrad && identical(l, cur)) {
        c.drawImage(l.image, Offset.zero, Paint());
        if (selMask != null) {
          c.saveLayer(rect, Paint());
          c.drawRect(rect, gradPaint());
          c.drawImage(selMask!, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
          c.restore();
        } else {
          c.drawRect(rect, gradPaint());
        }
      } else if (identical(l, cur) && (previewMatrix != null || previewBlur != null)) {
        final pm = previewMatrix;
        final pb = previewBlur;
        c.saveLayer(
          rect,
          Paint()
            ..colorFilter = pm == null ? null : ColorFilter.matrix(pm)
            ..imageFilter = pb == null ? null : ui.ImageFilter.blur(sigmaX: pb, sigmaY: pb),
        );
        c.drawImage(l.image, Offset.zero, Paint());
        c.restore();
      } else {
        c.drawImage(l.image, Offset.zero, Paint());
      }
      if (preview &&
          identical(l, cur) &&
          stroke.isNotEmpty &&
          isPaintTool &&
          tool != Tool.fxBrush &&
          !(editMask && l.mask != null)) {
        final erase = tool == Tool.eraser;
        if (selMask != null && !erase) {
          c.saveLayer(rect, Paint());
          paintStroke(c, stroke, color, brushSize, _op, _soft, false);
          c.drawImage(selMask!, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
          c.restore();
        } else {
          paintStroke(c, stroke, color, brushSize, _op, _soft, erase);
        }
      }
      if (l.mask != null) {
        c.drawImage(l.mask!, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
      }
      c.restore();
    }
  }

  // old*(1-mask) + neu*mask
  Future<ui.Image> _masked(ui.Image old, ui.Image neu) async {
    final m = selMask;
    if (m == null) return neu;
    final rect = _rect;
    return renderImage(docW, docH, (c) {
      c.saveLayer(rect, Paint());
      c.drawImage(old, Offset.zero, Paint());
      c.drawImage(m, Offset.zero, Paint()..blendMode = BlendMode.dstOut);
      c.restore();
      c.saveLayer(rect, Paint()..blendMode = BlendMode.plus);
      c.drawImage(neu, Offset.zero, Paint());
      c.drawImage(m, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
      c.restore();
    });
  }

  Future<void> endStroke() async {
    if (stroke.isEmpty || _busy) return;
    _busy = true;
    try {
      final layer = current;
      if (layer != null) {
        final pts = List<Offset>.of(stroke);
        final onMask = editMask && layer.mask != null;
        final old = onMask ? layer.mask! : layer.image;
        final rect = _rect;
        final erase = tool == Tool.eraser;
        final col = onMask ? Colors.black : color;
        final size = brushSize;
        final op = _op;
        final soft = _soft;
        final ui.Image painted;
        final so = stampOffset;
        if (tool == Tool.stamp && so != null) {
          final maskImg = await renderImage(docW, docH, (c) {
            paintStroke(c, pts, Colors.black, size, op, soft, false);
          });
          painted = await renderImage(docW, docH, (c) {
            c.drawImage(old, Offset.zero, Paint());
            c.saveLayer(rect, Paint());
            c.drawImage(old, Offset(-so.dx, -so.dy), Paint());
            c.drawImage(maskImg, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
            c.restore();
          });
        } else if (tool == Tool.fxBrush) {
          final bl = await _blurred(old, math.max(1.0, size * 0.18));
          final maskImg = await renderImage(docW, docH, (c) {
            paintStroke(c, pts, Colors.black, size, op, soft, false);
          });
          painted = await renderImage(docW, docH, (c) {
            c.drawImage(old, Offset.zero, Paint());
            c.saveLayer(rect, Paint());
            c.drawImage(bl, Offset.zero, Paint());
            c.drawImage(maskImg, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
            c.restore();
          });
        } else {
          painted = await renderImage(docW, docH, (c) {
            c.saveLayer(rect, Paint());
            c.drawImage(old, Offset.zero, Paint());
            paintStroke(c, pts, col, size, op, soft, erase);
            c.restore();
          });
        }
        final res = await _masked(old, painted);
        _pushUndo();
        if (onMask) {
          layer.mask = res;
        } else {
          layer.image = res;
        }
      }
    } catch (e) {
      toast('Error: $e');
    }
    stroke = [];
    _busy = false;
    notifyListeners();
  }

  // ---------- gestures ----------
  void gestureDown(Offset doc) {
    if (_busy) return;
    if (xfActive) {
      _xfDown(doc);
      return;
    }
    if (cropActive) {
      _cropDown(doc);
      return;
    }
    if (gradActive) {
      _gradDown(doc);
      return;
    }
    if (isPaintTool && !(current?.visible ?? false)) {
      toast('Layer is hidden');
      return;
    }
    if (tool == Tool.stamp) {
      if (!stampSetting && stampSource != null) {
        stampOffset ??= stampSource! - doc;
        stroke = [doc];
      }
    } else if (isPaintTool || tool == Tool.selBrush || tool == Tool.lasso) {
      stroke = [doc];
    } else if (tool == Tool.marquee || tool == Tool.ellipse) {
      dragA = doc;
      dragB = doc;
    }
    notifyListeners();
  }

  void gestureMove(Offset doc) {
    if (xfActive) {
      _xfMove(doc);
      return;
    }
    if (cropActive) {
      _cropMove(doc);
      return;
    }
    if (gradActive) {
      _gradMove(doc);
      return;
    }
    if (stroke.isNotEmpty) {
      stroke.add(doc);
      notifyListeners();
    } else if (dragA != null) {
      dragB = doc;
      notifyListeners();
    }
  }

  void gestureCancel() {
    if (_busy) return;
    _xfKind = 0;
    _cropHandle = -1;
    _gradDrag = 0;
    stroke = [];
    dragA = null;
    dragB = null;
    notifyListeners();
  }

  Future<void> gestureUp(Offset doc, bool moved) async {
    if (xfActive || cropActive || gradActive) {
      _xfKind = 0;
      _cropHandle = -1;
      _gradDrag = 0;
      return;
    }
    if (isPaintTool) {
      await endStroke();
    } else if (tool == Tool.selBrush) {
      await _commitSelBrush();
    } else if (tool == Tool.lasso) {
      await _commitLasso(moved);
    } else if (tool == Tool.marquee || tool == Tool.ellipse) {
      await _commitDrag(moved);
    } else if (tool == Tool.polygon) {
      if (!moved) _polyTap(doc);
    } else if (tool == Tool.wand) {
      if (!moved) await wandAt(doc);
    } else if (tool == Tool.colorSelect) {
      if (!moved) await wandAt(doc, contig: false);
    } else if (tool == Tool.smartSel) {
      if (!moved) await wandAt(doc, contig: true, tolOverride: 48);
    } else if (tool == Tool.stamp) {
      if (stampSetting) {
        stampSource = doc;
        stampOffset = null;
        stampSetting = false;
        notifyListeners();
      } else if (stampSource == null) {
        toast('Tap "Set Source", then tap the area to clone from');
      } else {
        await endStroke();
      }
    } else {
      if (!moved) toast('${toolName(tool)}: $comingSoon');
    }
  }

  Path? shapePath() {
    final a = dragA;
    final b = dragB;
    if (a == null || b == null) return null;
    final r = Rect.fromPoints(a, b);
    final p = Path();
    if (tool == Tool.ellipse) {
      p.addOval(r);
    } else if (corners > 0) {
      p.addRRect(RRect.fromRectAndRadius(r, Radius.circular(corners)));
    } else {
      p.addRect(r);
    }
    return p;
  }

  // ---------- selection ----------
  Future<ui.Image> _pathMask(Path p) => renderImage(docW, docH, (c) {
        c.drawPath(
          p,
          Paint()
            ..color = Colors.black
            ..isAntiAlias = antialias
            ..style = PaintingStyle.fill,
        );
      });

  Future<void> _commitDrag(bool moved) async {
    final a = dragA;
    final b = dragB;
    final path = shapePath();
    dragA = null;
    dragB = null;
    if (!moved || a == null || b == null || path == null) {
      notifyListeners();
      await deselect();
      return;
    }
    final r = Rect.fromPoints(a, b);
    if (r.width < 2 || r.height < 2) {
      notifyListeners();
      await deselect();
      return;
    }
    await _guard('Selecting…', () async {
      final m = await _pathMask(path);
      await applySelection(m, selMode);
    });
  }

  Future<void> _commitLasso(bool moved) async {
    final pts = List<Offset>.of(stroke);
    stroke = [];
    if (!moved || pts.length < 3) {
      notifyListeners();
      await deselect();
      return;
    }
    await _guard('Selecting…', () async {
      final path = Path()..addPolygon(pts, true);
      final m = await _pathMask(path);
      await applySelection(m, selMode);
    });
  }

  Future<void> _commitSelBrush() async {
    final pts = List<Offset>.of(stroke);
    stroke = [];
    if (pts.isEmpty) return;
    await _guard('Selecting…', () async {
      final size = brushSize;
      final m = await renderImage(docW, docH, (c) {
        paintStroke(c, pts, Colors.black, size, 1, 0, false);
      });
      final mode = selMode == SelMode.replace ? SelMode.add : selMode;
      await applySelection(m, mode);
    });
  }

  void _polyTap(Offset doc) {
    if (poly.length >= 3 && (doc - poly.first).distance * scale < 28) {
      finishPolygon();
      return;
    }
    poly = [...poly, doc];
    notifyListeners();
  }

  Future<void> finishPolygon() async {
    final pts = List<Offset>.of(poly);
    poly = [];
    notifyListeners();
    if (pts.length < 3) return;
    await _guard('Selecting…', () async {
      final path = Path()..addPolygon(pts, true);
      final m = await _pathMask(path);
      await applySelection(m, selMode);
    });
  }

  void cancelPolygon() {
    poly = [];
    notifyListeners();
  }

  Future<void> applySelection(ui.Image neu, SelMode mode) async {
    final old = selMask;
    ui.Image result = neu;
    if (old != null && mode != SelMode.replace) {
      result = await renderImage(docW, docH, (c) {
        switch (mode) {
          case SelMode.add:
            c.drawImage(old, Offset.zero, Paint());
            c.drawImage(neu, Offset.zero, Paint());
            break;
          case SelMode.subtract:
            c.drawImage(old, Offset.zero, Paint());
            c.drawImage(neu, Offset.zero, Paint()..blendMode = BlendMode.dstOut);
            break;
          case SelMode.intersect:
            c.drawImage(old, Offset.zero, Paint());
            c.drawImage(neu, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
            break;
          default:
            c.drawImage(neu, Offset.zero, Paint());
        }
      });
    }
    await _setSelection(result);
  }

  Future<List<ui.Image>> _buildEdges(Uint8List sel) async {
    final w = docW;
    final h = docH;
    final n = w * h;
    final idx = <int>[];
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = y * w + x;
        final s = sel[i];
        bool e = false;
        if (x > 0 && sel[i - 1] != s) {
          e = true;
        } else if (x < w - 1 && sel[i + 1] != s) {
          e = true;
        } else if (y > 0 && sel[i - w] != s) {
          e = true;
        } else if (y < h - 1 && sel[i + w] != s) {
          e = true;
        } else if (s == 1 && (x == 0 || y == 0 || x == w - 1 || y == h - 1)) {
          e = true;
        }
        if (e) idx.add(i);
      }
    }
    final out = <ui.Image>[];
    for (int ph = 0; ph < 4; ph++) {
      final px = Uint8List(n * 4);
      for (final i in idx) {
        final x = i % w;
        final y = i ~/ w;
        final v = ((((x + y) + ph * 2) >> 2) & 1) == 0 ? 0 : 255;
        final j = i * 4;
        px[j] = v;
        px[j + 1] = v;
        px[j + 2] = v;
        px[j + 3] = 255;
      }
      out.add(await imageFromRgba(px, w, h));
    }
    return out;
  }

  Future<Uint8List?> _selFlags(ui.Image mask) async {
    final bd = await mask.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return null;
    final b = bd.buffer.asUint8List();
    final n = docW * docH;
    final sel = Uint8List(n);
    bool any = false;
    for (int i = 0; i < n; i++) {
      if (b[i * 4 + 3] > 127) {
        sel[i] = 1;
        any = true;
      }
    }
    return any ? sel : null;
  }

  Future<void> _rebuildEdges() async {
    final m = selMask;
    if (m == null) return;
    final sel = await _selFlags(m);
    if (sel == null) return;
    final edges = await _buildEdges(sel);
    if (!identical(selMask, m)) return;
    selEdges = edges;
    selEdge = edges[0];
    _startAnts();
    notifyListeners();
  }

  Future<void> _setSelection(ui.Image mask, {bool push = true}) async {
    final sel = await _selFlags(mask);
    if (sel == null) {
      if (selMask != null) {
        if (push) _pushUndo();
        selMask = null;
        selEdge = null;
        selEdges = [];
        notifyListeners();
      }
      return;
    }
    final edges = await _buildEdges(sel);
    if (push) _pushUndo();
    selMask = mask;
    selEdge = edges[0];
    selEdge2 = edges[2];
    selEdges = edges;
    _startAnts();
    notifyListeners();
  }

  Future<void> deselect() async {
    if (selMask == null) return;
    _pushUndo();
    selMask = null;
    selEdge = null;
    notifyListeners();
  }

  Future<void> selectAll() => _guard('Selecting…', () async {
        final m = await renderImage(docW, docH, (c) {
          c.drawRect(_rect, Paint()..color = Colors.black);
        });
        await _setSelection(m);
      });

  Future<void> inverse() => _guard('Inverting…', () async {
        final old = selMask;
        if (old == null) return;
        final m = await renderImage(docW, docH, (c) {
          c.saveLayer(_rect, Paint());
          c.drawRect(_rect, Paint()..color = Colors.black);
          c.drawImage(old, Offset.zero, Paint()..blendMode = BlendMode.dstOut);
          c.restore();
        });
        await _setSelection(m);
      });

  Future<void> feather(double radius) => _guard('Feathering…', () async {
        final old = selMask;
        if (old == null) return;
        final sigma = math.max(0.5, radius / 2);
        final m = await renderImage(docW, docH, (c) {
          c.saveLayer(
              _rect, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));
          c.drawImage(old, Offset.zero, Paint());
          c.restore();
        });
        await _setSelection(m);
      });

  Future<void> selectPixels() => _guard('Selecting…', () async {
        final l = current;
        if (l == null) return;
        final m = await renderImage(docW, docH, (c) {
          c.drawImage(
            l.image,
            Offset.zero,
            Paint()..colorFilter = const ColorFilter.mode(Colors.black, BlendMode.srcIn),
          );
        });
        await _setSelection(m);
      });

  Future<void> wandAt(Offset doc, {bool? contig, double? tolOverride}) =>
      _guard('Selecting…', () async {
        final l = current;
        if (l == null) return;
        final w = docW;
        final h = docH;
        final x0 = doc.dx.floor();
        final y0 = doc.dy.floor();
        if (x0 < 0 || y0 < 0 || x0 >= w || y0 >= h) return;
        final bd = await l.image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (bd == null) return;
        final d = bd.buffer.asUint8List();
        final si = (y0 * w + x0) * 4;
        final r0 = d[si];
        final g0 = d[si + 1];
        final b0 = d[si + 2];
        final a0 = d[si + 3];
        final tol = (tolOverride ?? tolerance).round();
        bool match(int i) {
          final j = i * 4;
          return (d[j] - r0).abs() <= tol &&
              (d[j + 1] - g0).abs() <= tol &&
              (d[j + 2] - b0).abs() <= tol &&
              (d[j + 3] - a0).abs() <= tol;
        }

        final out = Uint8List(w * h);
        if (!(contig ?? contiguous)) {
          for (int i = 0; i < w * h; i++) {
            if (match(i)) out[i] = 255;
          }
        } else {
          final stack = <int>[y0 * w + x0];
          while (stack.isNotEmpty) {
            final i = stack.removeLast();
            if (out[i] != 0) continue;
            if (!match(i)) continue;
            out[i] = 255;
            final x = i % w;
            final y = i ~/ w;
            if (x > 0) stack.add(i - 1);
            if (x < w - 1) stack.add(i + 1);
            if (y > 0) stack.add(i - w);
            if (y < h - 1) stack.add(i + w);
          }
        }
        final px = Uint8List(w * h * 4);
        for (int i = 0; i < w * h; i++) {
          px[i * 4 + 3] = out[i];
        }
        final mask = await imageFromRgba(px, w, h);
        await applySelection(mask, selMode);
      });

  // ---------- clipboard / edit ----------
  Future<ui.Image> _extract(ui.Image src) {
    final m = selMask;
    return renderImage(docW, docH, (c) {
      c.saveLayer(_rect, Paint());
      c.drawImage(src, Offset.zero, Paint());
      if (m != null) {
        c.drawImage(m, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
      }
      c.restore();
    });
  }

  Future<void> selCopy() => _guard('Copying…', () async {
        final l = current;
        if (l == null) return;
        clipboard = await _extract(l.image);
        toast('Copied');
      });

  Future<void> selCopyMerged() => _guard('Copying…', () async {
        final flat = await renderImage(docW, docH, (c) => paintDoc(c, preview: false));
        clipboard = await _extract(flat);
        toast('Copied merged');
      });

  Future<void> _clearSel() async {
    final l = current;
    if (l == null) return;
    final old = l.image;
    final m = selMask;
    final res = await renderImage(docW, docH, (c) {
      if (m == null) return;
      c.saveLayer(_rect, Paint());
      c.drawImage(old, Offset.zero, Paint());
      c.drawImage(m, Offset.zero, Paint()..blendMode = BlendMode.dstOut);
      c.restore();
    });
    _pushUndo();
    l.image = res;
  }

  Future<void> selCut() => _guard('Cutting…', () async {
        final l = current;
        if (l == null) return;
        clipboard = await _extract(l.image);
        await _clearSel();
      });

  Future<void> selClear() => _guard('Clearing…', () async {
        await _clearSel();
      });

  Future<void> selPaste() => _guard('Pasting…', () async {
        final c = clipboard;
        if (c == null) return;
        final img = await renderImage(docW, docH, (cv) {
          cv.drawImageRect(
            c,
            Rect.fromLTWH(0, 0, c.width.toDouble(), c.height.toDouble()),
            _rect,
            Paint(),
          );
        });
        _pushUndo();
        final id = _nextId++;
        layers.insert(selected + 1, DocLayer(id: id, name: 'Layer $id', image: img));
        selected += 1;
      });

  Future<void> fillSelection() => _guard('Filling…', () async {
        final l = current;
        if (l == null) return;
        final old = l.image;
        final col = color;
        final neu = await renderImage(docW, docH, (c) {
          c.drawRect(_rect, Paint()..color = col);
        });
        final res = await _masked(old, neu);
        _pushUndo();
        l.image = res;
      });

  // ---------- adjustments / effects ----------
  Future<void> _applyFilter(Paint p) => _guard('Applying…', () async {
        final l = current;
        if (l == null) return;
        final old = l.image;
        final neu = await renderImage(docW, docH, (c) {
          c.saveLayer(_rect, p);
          c.drawImage(old, Offset.zero, Paint());
          c.restore();
        });
        final res = await _masked(old, neu);
        _pushUndo();
        l.image = res;
      });

  Future<void> applyMatrix(List<double> m) =>
      _applyFilter(Paint()..colorFilter = ColorFilter.matrix(m));

  Future<void> applyBlur(double s) => _applyFilter(
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: s, sigmaY: s));

  // ======================================================
  // Batch 2: transform, crop, resize, rotate, text, stamp,
  // more adjustments / effects, animations support
  // ======================================================
  // transform state
  bool xfActive = false;
  ui.Image? xfFloat;
  ui.Image? xfBase;
  Rect xfBounds = Rect.zero;
  Offset xfPos = Offset.zero;
  double xfSx = 1;
  double xfSy = 1;
  double xfRot = 0;
  int _xfKind = 0; // 0 none, 1 move, 2 rotate, 3 corner, 4 edge-x, 5 edge-y
  Offset _xfLast = Offset.zero;

  // crop state
  bool cropActive = false;
  Rect cropRect = Rect.zero;
  int _cropHandle = -1;
  Offset _cropLast = Offset.zero;

  // clone stamp
  Offset? stampSource;
  Offset? stampOffset;
  bool stampSetting = false;

  // animation helpers
  final ValueNotifier<int> antTick = ValueNotifier<int>(0);
  Timer? _antTimer;
  ui.Image? selEdge2;
  List<ui.Image> selEdges = [];
  bool showZoom = false;
  Timer? _zoomTimer;

  void _startAnts() {
    _antTimer?.cancel();
    _antTimer = Timer.periodic(const Duration(milliseconds: 110), (t) {
      if (selEdge == null) {
        t.cancel();
        return;
      }
      antTick.value++;
    });
  }

  void _pingZoom() {
    showZoom = true;
    _zoomTimer?.cancel();
    _zoomTimer = Timer(const Duration(milliseconds: 900), () {
      showZoom = false;
      notifyListeners();
    });
  }

  void toggleStampSetting() {
    stampSetting = !stampSetting;
    notifyListeners();
  }

  Offset _rot(Offset v, double a) {
    final c = math.cos(a);
    final s = math.sin(a);
    return Offset(v.dx * c - v.dy * s, v.dx * s + v.dy * c);
  }

  // ---------- transform ----------
  Offset xfToDoc(Offset local) =>
      xfBounds.center + xfPos + _rot(Offset(local.dx * xfSx, local.dy * xfSy), xfRot);

  Offset xfFromDoc(Offset d) {
    final q = _rot(d - xfBounds.center - xfPos, -xfRot);
    final sx = xfSx == 0 ? 1.0 : xfSx;
    final sy = xfSy == 0 ? 1.0 : xfSy;
    return Offset(q.dx / sx, q.dy / sy);
  }

  List<Offset> xfHandleDocPoints() {
    final hw = xfBounds.width / 2;
    final hh = xfBounds.height / 2;
    final top = xfToDoc(Offset(0, -hh));
    final rotP = top + _rot(Offset(0, -90 / scale), xfRot);
    return [
      xfToDoc(Offset(-hw, -hh)),
      xfToDoc(Offset(hw, -hh)),
      xfToDoc(Offset(hw, hh)),
      xfToDoc(Offset(-hw, hh)),
      top,
      xfToDoc(Offset(hw, 0)),
      xfToDoc(Offset(0, hh)),
      xfToDoc(Offset(-hw, 0)),
      rotP,
    ];
  }

  Future<Rect> _maskBounds() async {
    final m = selMask;
    if (m == null) return _rect;
    final bd = await m.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return _rect;
    final b = bd.buffer.asUint8List();
    final w = docW;
    final h = docH;
    int minX = w, minY = h, maxX = -1, maxY = -1;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (b[(y * w + x) * 4 + 3] > 127) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return _rect;
    return Rect.fromLTRB(minX.toDouble(), minY.toDouble(), maxX + 1.0, maxY + 1.0);
  }

  Future<void> startTransform() => _guard('Preparing...', () async {
        final l = current;
        if (l == null) return;
        final fl = await _extract(l.image);
        ui.Image base;
        final m = selMask;
        if (m != null) {
          base = await renderImage(docW, docH, (c) {
            c.saveLayer(_rect, Paint());
            c.drawImage(l.image, Offset.zero, Paint());
            c.drawImage(m, Offset.zero, Paint()..blendMode = BlendMode.dstOut);
            c.restore();
          });
        } else {
          base = await renderImage(docW, docH, (c) {});
        }
        xfBounds = m != null ? await _maskBounds() : _rect;
        xfFloat = fl;
        xfBase = base;
        xfPos = Offset.zero;
        xfSx = 1;
        xfSy = 1;
        xfRot = 0;
        xfActive = true;
        menu = null;
        toolMenuOpen = false;
        openGroup = null;
      });

  void _drawXf(Canvas c, ui.Image im) {
    c.save();
    final ctr = xfBounds.center;
    c.translate(ctr.dx + xfPos.dx, ctr.dy + xfPos.dy);
    c.rotate(xfRot);
    c.scale(xfSx, xfSy);
    c.translate(-ctr.dx, -ctr.dy);
    c.drawImage(im, Offset.zero, Paint()..filterQuality = FilterQuality.high);
    c.restore();
  }

  Future<void> xfApply() => _guard('Applying...', () async {
        final l = current;
        final fl = xfFloat;
        final base = xfBase;
        if (l == null || fl == null || base == null) {
          xfActive = false;
          return;
        }
        final img = await renderImage(docW, docH, (c) {
          c.drawImage(base, Offset.zero, Paint());
          _drawXf(c, fl);
        });
        ui.Image? newMask;
        final m = selMask;
        if (m != null) {
          newMask = await renderImage(docW, docH, (c) {
            _drawXf(c, m);
          });
        }
        _pushUndo();
        l.image = img;
        xfActive = false;
        xfFloat = null;
        xfBase = null;
        if (newMask != null) await _setSelection(newMask, push: false);
      });

  void xfCancel() {
    xfActive = false;
    xfFloat = null;
    xfBase = null;
    notifyListeners();
  }

  void xfFlipH() {
    xfSx = -xfSx;
    notifyListeners();
  }

  void xfFlipV() {
    xfSy = -xfSy;
    notifyListeners();
  }

  void xfRotate90() {
    xfRot += math.pi / 2;
    notifyListeners();
  }

  void _xfDown(Offset doc) {
    _xfLast = doc;
    _xfKind = 0;
    final pts = xfHandleDocPoints();
    final r = 46 / scale;
    double best = r;
    int idx = -1;
    for (int i = 0; i < pts.length; i++) {
      final d = (pts[i] - doc).distance;
      if (d < best) {
        best = d;
        idx = i;
      }
    }
    if (idx >= 0) {
      if (idx < 4) {
        _xfKind = 3;
      } else if (idx == 8) {
        _xfKind = 2;
      } else if (idx == 5 || idx == 7) {
        _xfKind = 4;
      } else {
        _xfKind = 5;
      }
    } else {
      final l = xfFromDoc(doc);
      final hw = xfBounds.width / 2;
      final hh = xfBounds.height / 2;
      if (l.dx.abs() <= hw && l.dy.abs() <= hh) _xfKind = 1;
    }
  }

  void _xfMove(Offset doc) {
    if (_xfKind == 0) return;
    final c = xfBounds.center + xfPos;
    final q = _rot(doc - c, -xfRot);
    final hw = math.max(1.0, xfBounds.width / 2);
    final hh = math.max(1.0, xfBounds.height / 2);
    if (_xfKind == 1) {
      xfPos = xfPos + (doc - _xfLast);
      _xfLast = doc;
    } else if (_xfKind == 2) {
      xfRot = math.atan2(doc.dy - c.dy, doc.dx - c.dx) + math.pi / 2;
    } else if (_xfKind == 3) {
      final s = math.max(0.03, q.distance / math.sqrt(hw * hw + hh * hh));
      xfSx = (xfSx < 0 ? -1 : 1) * s;
      xfSy = (xfSy < 0 ? -1 : 1) * s;
    } else if (_xfKind == 4) {
      xfSx = (xfSx < 0 ? -1 : 1) * math.max(0.03, q.dx.abs() / hw);
    } else if (_xfKind == 5) {
      xfSy = (xfSy < 0 ? -1 : 1) * math.max(0.03, q.dy.abs() / hh);
    }
    notifyListeners();
  }

  // ---------- crop ----------
  void startCrop() {
    final m = math.min(docW, docH) * 0.05;
    cropRect = _rect.deflate(m);
    cropActive = true;
    menu = null;
    notifyListeners();
  }

  List<Offset> cropHandlePoints() {
    final r = cropRect;
    return [
      r.topLeft,
      r.topRight,
      r.bottomRight,
      r.bottomLeft,
      Offset(r.center.dx, r.top),
      Offset(r.right, r.center.dy),
      Offset(r.center.dx, r.bottom),
      Offset(r.left, r.center.dy),
    ];
  }

  void _cropDown(Offset doc) {
    final pts = cropHandlePoints();
    final r = 46 / scale;
    double best = r;
    _cropHandle = -1;
    for (int i = 0; i < pts.length; i++) {
      final d = (pts[i] - doc).distance;
      if (d < best) {
        best = d;
        _cropHandle = i;
      }
    }
    if (_cropHandle < 0 && cropRect.contains(doc)) _cropHandle = 8;
    _cropLast = doc;
  }

  void _cropMove(Offset doc) {
    if (_cropHandle < 0) return;
    final r = cropRect;
    final d = doc - _cropLast;
    _cropLast = doc;
    const minS = 20.0;
    final W = docW.toDouble();
    final H = docH.toDouble();
    double l = r.left, t = r.top, rt = r.right, b = r.bottom;
    switch (_cropHandle) {
      case 8:
        {
          final nl = math.max(0.0, math.min(l + d.dx, W - r.width));
          final nt = math.max(0.0, math.min(t + d.dy, H - r.height));
          l = nl;
          t = nt;
          rt = nl + r.width;
          b = nt + r.height;
        }
        break;
      case 0:
        l = doc.dx;
        t = doc.dy;
        break;
      case 1:
        rt = doc.dx;
        t = doc.dy;
        break;
      case 2:
        rt = doc.dx;
        b = doc.dy;
        break;
      case 3:
        l = doc.dx;
        b = doc.dy;
        break;
      case 4:
        t = doc.dy;
        break;
      case 5:
        rt = doc.dx;
        break;
      case 6:
        b = doc.dy;
        break;
      case 7:
        l = doc.dx;
        break;
      default:
        break;
    }
    l = math.max(0.0, math.min(l, rt - minS));
    rt = math.min(W, math.max(rt, l + minS));
    t = math.max(0.0, math.min(t, b - minS));
    b = math.min(H, math.max(b, t + minS));
    cropRect = Rect.fromLTRB(l, t, rt, b);
    notifyListeners();
  }

  void cropCancel() {
    cropActive = false;
    notifyListeners();
  }

  Future<void> _rebuildAll(
      int nw, int nh, void Function(Canvas c, ui.Image img) draw) async {
    final out = <ui.Image>[];
    for (final l in layers) {
      out.add(await renderImage(nw, nh, (c) => draw(c, l.image)));
    }
    _pushUndo();
    for (int i = 0; i < layers.length; i++) {
      layers[i].image = out[i];
    }
    docW = nw;
    docH = nh;
    selMask = null;
    selEdge = null;
    _fit();
    notifyListeners();
  }

  Future<void> cropApply() => _guard('Cropping...', () async {
        final r = Rect.fromLTRB(cropRect.left.roundToDouble(), cropRect.top.roundToDouble(),
            cropRect.right.roundToDouble(), cropRect.bottom.roundToDouble());
        final nw = r.width.round();
        final nh = r.height.round();
        if (nw < 2 || nh < 2) return;
        await _rebuildAll(nw, nh, (c, img) {
          c.drawImage(img, Offset(-r.left, -r.top), Paint());
        });
        cropActive = false;
      });

  Future<void> resizeAll(int nw, int nh) => _guard('Resizing...', () async {
        await _rebuildAll(nw, nh, (c, img) {
          c.drawImageRect(
            img,
            Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
            Rect.fromLTWH(0, 0, nw.toDouble(), nh.toDouble()),
            Paint()..filterQuality = FilterQuality.high,
          );
        });
      });

  Future<void> rotateAll(String kind) => _guard('Rotating...', () async {
        final w = docW.toDouble();
        final h = docH.toDouble();
        if (kind == 'cw') {
          await _rebuildAll(docH, docW, (c, img) {
            c.translate(h, 0);
            c.rotate(math.pi / 2);
            c.drawImage(img, Offset.zero, Paint());
          });
        } else if (kind == 'ccw') {
          await _rebuildAll(docH, docW, (c, img) {
            c.translate(0, w);
            c.rotate(-math.pi / 2);
            c.drawImage(img, Offset.zero, Paint());
          });
        } else if (kind == '180') {
          await _rebuildAll(docW, docH, (c, img) {
            c.translate(w, h);
            c.rotate(math.pi);
            c.drawImage(img, Offset.zero, Paint());
          });
        } else if (kind == 'fh') {
          await _rebuildAll(docW, docH, (c, img) {
            c.translate(w, 0);
            c.scale(-1, 1);
            c.drawImage(img, Offset.zero, Paint());
          });
        } else {
          await _rebuildAll(docW, docH, (c, img) {
            c.translate(0, h);
            c.scale(1, -1);
            c.drawImage(img, Offset.zero, Paint());
          });
        }
      });

  // ---------- text ----------
  Future<void> addText(String text, double size, bool bold, String family, Color col) =>
      _guard('Adding text...', () async {
        final rtl = RegExp(r'[\u0600-\u06FF]').hasMatch(text);
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: size,
              color: col,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontFamily: family == 'default' ? null : family,
            ),
          ),
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        tp.layout(maxWidth: docW * 0.9);
        final off = Offset((docW - tp.width) / 2, (docH - tp.height) / 2);
        final img = await renderImage(docW, docH, (c) {
          tp.paint(c, off);
        });
        final blank = await renderImage(docW, docH, (c) {});
        _pushUndo();
        final id = _nextId++;
        layers.insert(
          selected + 1,
          DocLayer(
            id: id,
            name: 'Text',
            image: img,
            textMeta: {
              'text': text,
              'size': size,
              'bold': bold,
              'family': family,
              'color': col.toARGB32(),
            },
          ),
        );
        selected += 1;
        xfBounds = Rect.fromLTWH(off.dx - 12, off.dy - 12, tp.width + 24, tp.height + 24);
        xfFloat = img;
        xfBase = blank;
        xfPos = Offset.zero;
        xfSx = 1;
        xfSy = 1;
        xfRot = 0;
        xfActive = true;
      });

  // ---------- more adjustments ----------
  Future<void> autoFix() async {
    List<double>? m;
    await _guard('Analyzing...', () async {
      final l = current;
      if (l == null) return;
      final bd = await l.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (bd == null) return;
      final d = bd.buffer.asUint8List();
      final hist = List<int>.filled(256, 0);
      int total = 0;
      for (int i = 0; i < d.length; i += 4) {
        if (d[i + 3] > 10) {
          final y = math.min(
              255, math.max(0, (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]).round()));
          hist[y]++;
          total++;
        }
      }
      if (total == 0) return;
      final cut = (total * 0.01).round();
      int lo = 0, hi = 255, acc = 0;
      for (int i = 0; i < 256; i++) {
        acc += hist[i];
        if (acc > cut) {
          lo = i;
          break;
        }
      }
      acc = 0;
      for (int i = 255; i >= 0; i--) {
        acc += hist[i];
        if (acc > cut) {
          hi = i;
          break;
        }
      }
      if (hi - lo < 20) return;
      m = matLevels(lo.toDouble(), hi.toDouble());
    });
    final mm = m;
    if (mm != null) {
      await applyMatrix(mm);
    } else {
      toast('Nothing to fix');
    }
  }

  Future<void> applyTint(double amount) => _applyFilter(Paint()
    ..colorFilter =
        ColorFilter.mode(color.withValues(alpha: amount), BlendMode.srcATop));

  Future<void> applyDirBlur(double hx, double vy) => _applyFilter(Paint()
    ..imageFilter = ui.ImageFilter.blur(
        sigmaX: math.max(0.01, hx), sigmaY: math.max(0.01, vy)));

  Future<void> applyShadow(double dx, double dy, double blur, double op, Color sc) =>
      _guard('Applying...', () async {
        final l = current;
        if (l == null) return;
        final old = l.image;
        final b = math.max(0.1, blur);
        final neu = await renderImage(docW, docH, (c) {
          c.saveLayer(_rect, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: b, sigmaY: b));
          c.drawImage(
            old,
            Offset(dx, dy),
            Paint()..colorFilter = ColorFilter.mode(sc.withValues(alpha: op), BlendMode.srcIn),
          );
          c.restore();
          c.drawImage(old, Offset.zero, Paint());
        });
        final res = await _masked(old, neu);
        _pushUndo();
        l.image = res;
      });

  Future<void> applyGradient(double angleDeg, bool toClear) =>
      _guard('Applying...', () async {
        final l = current;
        if (l == null) return;
        final old = l.image;
        final a = angleDeg * math.pi / 180;
        final cx = docW / 2;
        final cy = docH / 2;
        final len = math.sqrt(docW * docW + docH * docH) / 2;
        final dx = math.cos(a) * len;
        final dy = math.sin(a) * len;
        final col = color;
        final comp = await renderImage(docW, docH, (c) {
          c.drawImage(old, Offset.zero, Paint());
          c.drawRect(
            _rect,
            Paint()
              ..shader = ui.Gradient.linear(
                Offset(cx - dx, cy - dy),
                Offset(cx + dx, cy + dy),
                [col, toClear ? col.withValues(alpha: 0) : Colors.white],
              ),
          );
        });
        final res = await _masked(old, comp);
        _pushUndo();
        l.image = res;
      });

  Future<void> applyFlare(double px, double py, double size) =>
      _guard('Applying...', () async {
        final l = current;
        if (l == null) return;
        final old = l.image;
        final center = Offset(docW * px, docH * py);
        final r = size * math.min(docW, docH) / 2;
        final mid = Offset(docW / 2, docH / 2);
        final comp = await renderImage(docW, docH, (c) {
          c.drawImage(old, Offset.zero, Paint());
          c.drawCircle(
            center,
            r,
            Paint()
              ..blendMode = BlendMode.plus
              ..shader = ui.Gradient.radial(
                center,
                r,
                const [Color(0xFFFFFFFF), Color(0x66FFE0A0), Color(0x00FFE0A0)],
                const [0.0, 0.25, 1.0],
              ),
          );
          for (final t in const [0.6, 1.2, 1.8]) {
            final pos = center + (mid - center) * t;
            c.drawCircle(
              pos,
              r * 0.16 * t,
              Paint()
                ..blendMode = BlendMode.plus
                ..color = const Color(0x33FFFFFF),
            );
          }
        });
        final res = await _masked(old, comp);
        _pushUndo();
        l.image = res;
      });

  Future<void> extractToLayer() => _guard('Extracting...', () async {
        final l = current;
        if (l == null) return;
        final img = await _extract(l.image);
        _pushUndo();
        final id = _nextId++;
        layers.insert(selected + 1, DocLayer(id: id, name: 'Extract $id', image: img));
        selected += 1;
      });

  // ======================================================
  // Batch 3: pixel effects, curves, warp, refine edge ...
  // ======================================================
  // ---------- pointer mode (pad + click button) ----------
  bool ptrMode = false;
  Offset ptr = const Offset(540, 600);
  bool _ptrDown = false;
  Offset _ptrStart = Offset.zero;

  void togglePointer() {
    ptrMode = !ptrMode;
    if (ptrMode) {
      final c = toDoc(Offset(viewport.width / 2, viewport.height / 2));
      ptr = Offset(math.max(0.0, math.min(docW.toDouble(), c.dx)),
          math.max(0.0, math.min(docH.toDouble(), c.dy)));
      toast('Pointer on: drag the pad to move, hold the button to act');
    } else {
      _ptrDown = false;
    }
    notifyListeners();
  }

  void ptrMove(Offset screenDelta) {
    ptr = Offset(
      math.max(0.0, math.min(docW.toDouble(), ptr.dx + screenDelta.dx / scale * 1.15)),
      math.max(0.0, math.min(docH.toDouble(), ptr.dy + screenDelta.dy / scale * 1.15)),
    );
    if (_ptrDown) gestureMove(ptr);
    notifyListeners();
  }

  void ptrPress() {
    if (_ptrDown) return;
    _ptrDown = true;
    _ptrStart = ptr;
    gestureDown(ptr);
    notifyListeners();
  }

  void ptrRelease() {
    if (!_ptrDown) return;
    _ptrDown = false;
    final moved = (ptr - _ptrStart).distance * scale > 8;
    gestureUp(ptr, moved);
  }

  // ---------- pixel helpers ----------
  Future<Uint8List> _px(ui.Image im) async {
    final bd = await im.toByteData(format: ui.ImageByteFormat.rawRgba);
    return Uint8List.fromList(bd!.buffer.asUint8List());
  }

  Future<ui.Image> _blurred(ui.Image im, double sigma) =>
      renderImage(docW, docH, (c) {
        c.saveLayer(_rect,
            Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));
        c.drawImage(im, Offset.zero, Paint());
        c.restore();
      });

  Future<ui.Image> _matrixImage(ui.Image im, List<double> m) =>
      renderImage(docW, docH, (c) {
        c.saveLayer(_rect, Paint()..colorFilter = ColorFilter.matrix(m));
        c.drawImage(im, Offset.zero, Paint());
        c.restore();
      });

  Future<void> _custom(String msg, Future<ui.Image> Function(ui.Image old) fn) =>
      _guard(msg, () async {
        final l = current;
        if (l == null) return;
        final old = l.image;
        final neu = await fn(old);
        final res = await _masked(old, neu);
        _pushUndo();
        l.image = res;
      });

  static int _c255(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

  static double _hash(int a, int b) {
    final v = math.sin(a * 12.9898 + b * 78.233) * 43758.5453;
    return v - v.floorToDouble();
  }

  Future<ui.Image> _mapPixels(ui.Image im, PixFn f, {ui.Image? source}) async {
    final orig = await _px(im);
    final src = source == null ? orig : await _px(source);
    final w = docW;
    final h = docH;
    final out = Uint8List(w * h * 4);
    final o = List<double>.filled(3, 0);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final a = orig[i + 3];
        if (a == 0) continue;
        final sa = src[i + 3];
        final inv = sa == 0 ? 0.0 : 255.0 / sa;
        f(x, y, src[i] * inv, src[i + 1] * inv, src[i + 2] * inv, o);
        final k = a / 255.0;
        out[i] = _c255(o[0] * k);
        out[i + 1] = _c255(o[1] * k);
        out[i + 2] = _c255(o[2] * k);
        out[i + 3] = a;
      }
    }
    return imageFromRgba(out, w, h);
  }

  Float32List _lumArr(Uint8List d) {
    final n = docW * docH;
    final l = Float32List(n);
    for (int i = 0; i < n; i++) {
      final j = i * 4;
      final a = d[j + 3];
      if (a == 0) continue;
      final inv = 255.0 / a;
      l[i] = (0.2126 * d[j] + 0.7152 * d[j + 1] + 0.0722 * d[j + 2]) * inv / 255.0;
    }
    return l;
  }

  Float32List _sobel(Float32List l) {
    final w = docW;
    final h = docH;
    final m = Float32List(w * h);
    for (int y = 1; y < h - 1; y++) {
      for (int x = 1; x < w - 1; x++) {
        final i = y * w + x;
        final gx = -l[i - w - 1] - 2 * l[i - 1] - l[i + w - 1] + l[i - w + 1] + 2 * l[i + 1] + l[i + w + 1];
        final gy = -l[i - w - 1] - 2 * l[i - w] - l[i - w + 1] + l[i + w - 1] + 2 * l[i + w] + l[i + w + 1];
        m[i] = math.sqrt(gx * gx + gy * gy);
      }
    }
    return m;
  }

  Future<ui.Image> _grayImage(ui.Image old, double Function(int x, int y) f) async {
    final orig = await _px(old);
    final w = docW;
    final h = docH;
    final out = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final i = (y * w + x) * 4;
        final a = orig[i + 3];
        if (a == 0) continue;
        final v = _c255(f(x, y) * 255);
        final pv = (v * a / 255).round();
        out[i] = pv;
        out[i + 1] = pv;
        out[i + 2] = pv;
        out[i + 3] = a;
      }
    }
    return imageFromRgba(out, w, h);
  }

  Future<ui.Image> _displace(ui.Image im, Offset Function(int x, int y) f) async {
    final s = await _px(im);
    final w = docW;
    final h = docH;
    final out = Uint8List(w * h * 4);
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final p = f(x, y);
        final sx = p.dx;
        final sy = p.dy;
        if (sx < 0 || sy < 0 || sx >= w - 1 || sy >= h - 1) continue;
        final x0 = sx.floor();
        final y0 = sy.floor();
        final fx = sx - x0;
        final fy = sy - y0;
        final i00 = (y0 * w + x0) * 4;
        final i10 = i00 + 4;
        final i01 = i00 + w * 4;
        final i11 = i01 + 4;
        final o = (y * w + x) * 4;
        for (int ch = 0; ch < 4; ch++) {
          final v = s[i00 + ch] * (1 - fx) * (1 - fy) +
              s[i10 + ch] * fx * (1 - fy) +
              s[i01 + ch] * (1 - fx) * fy +
              s[i11 + ch] * fx * fy;
          out[o + ch] = v.round();
        }
      }
    }
    return imageFromRgba(out, w, h);
  }

  Future<ui.Image> _unsharp(ui.Image old, double amount, double sigma) async {
    final blur = await _blurred(old, sigma);
    final a = await _px(old);
    final b = await _px(blur);
    final out = Uint8List(a.length);
    for (int i = 0; i < a.length; i += 4) {
      final al = a[i + 3];
      out[i + 3] = al;
      if (al == 0) continue;
      for (int c = 0; c < 3; c++) {
        final v = a[i + c] + amount * (a[i + c] - b[i + c]);
        final cl = v < 0 ? 0.0 : (v > al ? al.toDouble() : v);
        out[i + c] = cl.round();
      }
    }
    return imageFromRgba(out, docW, docH);
  }

  // ---------- basic ----------
  Future<void> applySharpen(double amount, double radius) =>
      _custom('Sharpening...', (old) => _unsharp(old, amount, radius));

  Future<void> applyBevel(double depth, double size) => _custom('Bevel...', (old) async {
        final blur = await _blurred(old, size);
        final o = await _px(old);
        final b = await _px(blur);
        final w = docW;
        final h = docH;
        final out = Uint8List(o.length);
        for (int y = 1; y < h - 1; y++) {
          for (int x = 1; x < w - 1; x++) {
            final i = (y * w + x) * 4;
            final a = o[i + 3];
            if (a == 0) continue;
            final dx = b[i + 4 + 3] - b[i - 4 + 3];
            final dy = b[i + w * 4 + 3] - b[i - w * 4 + 3];
            final light = -(dx + dy) * depth * 0.5;
            final inv = 255.0 / a;
            final k = a / 255.0;
            for (int c = 0; c < 3; c++) {
              out[i + c] = _c255((o[i + c] * inv + light) * k);
            }
            out[i + 3] = a;
          }
        }
        return imageFromRgba(out, w, h);
      });

  Future<void> applyEdges(double k) => _custom('Edges...', (old) async {
        final mag = _sobel(_lumArr(await _px(old)));
        final w = docW;
        return _grayImage(old, (x, y) => 1 - math.min(1.0, mag[y * w + x] * k));
      });

  Future<void> applyLighting(double px, double py, double radius, double intensity) =>
      _custom('Lighting...', (old) {
        final center = Offset(docW * px, docH * py);
        final r = radius * math.min(docW, docH);
        return renderImage(docW, docH, (c) {
          c.drawImage(old, Offset.zero, Paint());
          c.drawRect(
            _rect,
            Paint()
              ..shader = ui.Gradient.radial(
                center,
                r,
                [const Color(0x00000000), Color.fromRGBO(0, 0, 0, 0.85 * intensity)],
                const [0.2, 1.0],
                TileMode.clamp,
              ),
          );
          c.drawCircle(
            center,
            r * 0.8,
            Paint()
              ..blendMode = BlendMode.plus
              ..shader = ui.Gradient.radial(
                center,
                r * 0.8,
                [Color.fromRGBO(255, 244, 220, 0.35 * intensity), const Color(0x00FFFFFF)],
              ),
          );
        });
      });

  // ---------- stylize ----------
  Future<void> gradientMap() => _custom('Gradient map...', (old) {
        final col = color;
        final cr = col.r * 255, cg = col.g * 255, cb = col.b * 255;
        return _mapPixels(old, (x, y, r, g, b, o) {
          final l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
          if (l < 0.5) {
            final t = l * 2;
            o[0] = cr * t;
            o[1] = cg * t;
            o[2] = cb * t;
          } else {
            final t = (l - 0.5) * 2;
            o[0] = cr + (255 - cr) * t;
            o[1] = cg + (255 - cg) * t;
            o[2] = cb + (255 - cb) * t;
          }
        });
      });

  Future<void> applyHalftone(double size) => _custom('Halftone...', (old) async {
        final blur = await _blurred(old, size * 0.5);
        return _mapPixels(old, (x, y, r, g, b, o) {
          final cx = (x ~/ size) * size + size / 2;
          final cy = (y ~/ size) * size + size / 2;
          final dx = x - cx;
          final dy = y - cy;
          final dist = math.sqrt(dx * dx + dy * dy);
          final l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
          final rad = size * 0.72 * math.sqrt(math.max(0.0, 1 - l));
          final v = dist < rad ? 0.0 : 255.0;
          o[0] = v;
          o[1] = v;
          o[2] = v;
        }, source: blur);
      });

  Future<void> applyGlass(double size, double strength) => _custom('Glass...', (old) {
        final s = math.max(2, math.min(60, size.round()));
        return _displace(old, (x, y) {
          final cx = x ~/ s;
          final cy = y ~/ s;
          final dx = (_hash(cx, cy) * 2 - 1) * strength;
          final dy = (_hash(cy + 91, cx + 17) * 2 - 1) * strength;
          return Offset(x + dx, y + dy);
        });
      });

  Future<void> applyPosterize(double levels) => _custom('Posterize...', (old) {
        final n = math.max(2.0, levels.roundToDouble());
        return _mapPixels(old, (x, y, r, g, b, o) {
          o[0] = (r / 255 * (n - 1)).round() / (n - 1) * 255;
          o[1] = (g / 255 * (n - 1)).round() / (n - 1) * 255;
          o[2] = (b / 255 * (n - 1)).round() / (n - 1) * 255;
        });
      });

  Future<void> applyPhotocopy(double thr, double noise) =>
      _custom('Photocopy...', (old) => _mapPixels(old, (x, y, r, g, b, o) {
            var l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
            l += (_hash(x, y) - 0.5) * noise * 0.8;
            final v = l < thr ? 0.0 : 255.0;
            o[0] = v;
            o[1] = v;
            o[2] = v;
          }));

  Future<void> applyStampPattern(double freq, double angleDeg) {
    final a = angleDeg * math.pi / 180;
    final ca = math.cos(a);
    final sa = math.sin(a);
    return _custom('Pattern...', (old) => _mapPixels(old, (x, y, r, g, b, o) {
          final l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
          final t = (x * ca + y * sa) * freq;
          final v = math.sin(t) < (l * 2 - 1) * 0.95 ? 255.0 : 0.0;
          o[0] = v;
          o[1] = v;
          o[2] = v;
        }));
  }

  Future<void> colorizeFx() => _custom('Colorize...', (old) {
        final col = color;
        final cr = col.r * 255, cg = col.g * 255, cb = col.b * 255;
        return _mapPixels(old, (x, y, r, g, b, o) {
          final l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
          final k = 0.35 + 1.3 * l;
          o[0] = cr * k;
          o[1] = cg * k;
          o[2] = cb * k;
        });
      });

  Future<void> applyRipple(double amp, double wave) => _custom(
      'Ripple...',
      (old) => _displace(old, (x, y) {
            final dx = amp * math.sin(y / wave * 2 * math.pi);
            final dy = amp * 0.5 * math.sin(x / wave * 2 * math.pi);
            return Offset(x + dx, y + dy);
          }));

  // ---------- artistic ----------
  Future<void> applyGraphicPen(double spacing) =>
      _custom('Graphic pen...', (old) => _mapPixels(old, (x, y, r, g, b, o) {
            final l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
            final t = ((x + y) % spacing) / spacing;
            final v = l < t ? 0.0 : 255.0;
            o[0] = v;
            o[1] = v;
            o[2] = v;
          }));

  Future<void> applyChalk(double grain) =>
      _custom('Chalk...', (old) => _mapPixels(old, (x, y, r, g, b, o) {
            final l = (0.2126 * r + 0.7152 * g + 0.0722 * b);
            final v = l + (_hash(x, y) - 0.5) * grain * 140;
            final t = v < 85 ? 25.0 : (v < 170 ? 145.0 : 240.0);
            o[0] = t;
            o[1] = t;
            o[2] = t;
          }));

  Future<void> applyPencil(double k) => _custom('Pencil...', (old) async {
        final base = await _px(old);
        final lum = _lumArr(base);
        final mag = _sobel(lum);
        final w = docW;
        return _grayImage(old, (x, y) {
          final i = y * w + x;
          final e = 1 - math.min(1.0, mag[i] * k);
          final paper = 0.97 + 0.03 * _hash(x, y);
          return (0.82 * e + 0.18 * (0.55 + 0.45 * lum[i])) * paper;
        });
      });

  Future<void> applyComic(double levels, double outline) => _custom('Comic...', (old) async {
        final mag = _sobel(_lumArr(await _px(old)));
        final w = docW;
        final n = math.max(2.0, levels.roundToDouble());
        final thr = 1.2 - outline;
        return _mapPixels(old, (x, y, r, g, b, o) {
          if (mag[y * w + x] > thr) {
            o[0] = 0;
            o[1] = 0;
            o[2] = 0;
            return;
          }
          o[0] = (r / 255 * (n - 1)).round() / (n - 1) * 255;
          o[1] = (g / 255 * (n - 1)).round() / (n - 1) * 255;
          o[2] = (b / 255 * (n - 1)).round() / (n - 1) * 255;
        });
      });

  Future<void> applyColorDrops(double count, double size) => _custom('Color drops...', (old) {
        final rnd = math.Random(11);
        const pal = [
          Color(0xFF1E88E5), Color(0xFFE53935), Color(0xFFFDD835),
          Color(0xFF43A047), Color(0xFF8E24AA), Color(0xFFFB8C00),
        ];
        return renderImage(docW, docH, (c) {
          c.drawImage(old, Offset.zero, Paint());
          for (int i = 0; i < count.round(); i++) {
            final p = Offset(rnd.nextDouble() * docW, rnd.nextDouble() * docH);
            final r = (10 + rnd.nextDouble() * 50) * size;
            final col = pal[rnd.nextInt(pal.length)].withValues(alpha: 0.7);
            c.drawCircle(p, r, Paint()..color = col);
            for (int j = 0; j < 5; j++) {
              final a = rnd.nextDouble() * math.pi * 2;
              final d = r * (1.2 + rnd.nextDouble() * 1.2);
              c.drawCircle(p + Offset(math.cos(a) * d, math.sin(a) * d),
                  r * (0.06 + rnd.nextDouble() * 0.12), Paint()..color = col);
            }
          }
        });
      });

  Future<void> applyScratches(double count) => _custom('Scratches...', (old) {
        final rnd = math.Random(5);
        return renderImage(docW, docH, (c) {
          c.drawImage(old, Offset.zero, Paint());
          for (int i = 0; i < count.round(); i++) {
            final p = Offset(rnd.nextDouble() * docW, rnd.nextDouble() * docH);
            final a = rnd.nextDouble() * math.pi * 2;
            final len = 40 + rnd.nextDouble() * 260;
            final dark = rnd.nextBool();
            c.drawLine(
              p,
              p + Offset(math.cos(a) * len, math.sin(a) * len),
              Paint()
                ..strokeWidth = 1 + rnd.nextDouble() * 1.6
                ..color = dark ? const Color(0x99000000) : const Color(0x88FFFFFF),
            );
          }
        });
      });

  Future<void> applyWatercolor(double smooth, double levels) =>
      _custom('Watercolor...', (old) async {
        final blur = await _blurred(old, smooth);
        final n = math.max(2.0, levels.roundToDouble());
        return _mapPixels(old, (x, y, r, g, b, o) {
          final nz = (_hash(x, y) - 0.5) * 14;
          o[0] = (r / 255 * (n - 1)).round() / (n - 1) * 255 + nz;
          o[1] = (g / 255 * (n - 1)).round() / (n - 1) * 255 + nz;
          o[2] = (b / 255 * (n - 1)).round() / (n - 1) * 255 + nz;
        }, source: blur);
      });

  Future<void> applyAcrylic(double block) => _custom('Acrylic...', (old) async {
        final bs = math.max(2, block.round());
        final sw = math.max(1, docW ~/ bs);
        final sh = math.max(1, docH ~/ bs);
        final small = await renderImage(sw, sh, (c) {
          c.drawImageRect(
            old,
            Rect.fromLTWH(0, 0, docW.toDouble(), docH.toDouble()),
            Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
            Paint()..filterQuality = FilterQuality.medium,
          );
        });
        return renderImage(docW, docH, (c) {
          c.drawImageRect(
            small,
            Rect.fromLTWH(0, 0, sw.toDouble(), sh.toDouble()),
            _rect,
            Paint()..filterQuality = FilterQuality.none,
          );
        });
      });

  Future<void> applyShred(double width, double amount) => _custom('Shred...', (old) {
        final rnd = math.Random(7);
        final sw = math.max(2.0, width);
        return renderImage(docW, docH, (c) {
          for (double x = 0; x < docW; x += sw) {
            final dy = (rnd.nextDouble() * 2 - 1) * amount;
            c.save();
            c.clipRect(Rect.fromLTWH(x, 0, sw, docH.toDouble()));
            c.drawImage(old, Offset(0, dy), Paint());
            c.restore();
          }
        });
      });

  // ---------- photo ----------
  Future<void> sleepyHollow() => _custom('Sleepy Hollow...', (old) async {
        final m = await _matrixImage(old, const [
          0.62, 0.30, 0.08, 0, -6, //
          0.22, 0.62, 0.16, 0, 0,
          0.12, 0.28, 0.80, 0, 18,
          0, 0, 0, 1, 0,
        ]);
        final rad = math.sqrt(docW * docW + docH * docH) / 2;
        return renderImage(docW, docH, (c) {
          c.drawImage(m, Offset.zero, Paint());
          c.drawRect(
            _rect,
            Paint()
              ..shader = ui.Gradient.radial(
                Offset(docW / 2, docH / 2),
                rad,
                const [Color(0x00000000), Color(0xAA000000)],
                const [0.45, 1.0],
              ),
          );
        });
      });

  Future<void> tvMonitor() => _custom('TV monitor...', (old) async {
        final m = await _matrixImage(old, matSaturation(1.25));
        return renderImage(docW, docH, (c) {
          c.drawImage(m, Offset.zero, Paint());
          for (double y = 0; y < docH; y += 4) {
            c.drawRect(Rect.fromLTWH(0, y, docW.toDouble(), 2), Paint()..color = const Color(0x55000000));
          }
        });
      });

  Future<void> grainyNight(double grain) =>
      _custom('Grainy night...', (old) => _mapPixels(old, (x, y, r, g, b, o) {
            final l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
            final v = ((l - 0.5) * 1.6 + 0.5) * 255 + (_hash(x, y) - 0.5) * grain * 170;
            o[0] = v;
            o[1] = v;
            o[2] = v;
          }));

  Future<void> hdrLook(double amount) => _custom('HDR...', (old) async {
        final u = await _unsharp(old, amount, 18);
        return _matrixImage(u, matSaturation(1.3));
      });

  Future<void> softLightFx(double amount) => _custom('Soft light...', (old) {
        return renderImage(docW, docH, (c) {
          c.drawImage(old, Offset.zero, Paint());
          c.saveLayer(
            _rect,
            Paint()
              ..imageFilter = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12)
              ..color = Color.fromRGBO(0, 0, 0, amount)
              ..blendMode = BlendMode.screen,
          );
          c.drawImage(old, Offset.zero, Paint());
          c.restore();
        });
      });

  Future<void> softSkin(double smooth) => _custom('Soft skin...', (old) {
        return renderImage(docW, docH, (c) {
          c.drawImage(old, Offset.zero, Paint());
          c.saveLayer(
            _rect,
            Paint()
              ..imageFilter = ui.ImageFilter.blur(sigmaX: smooth, sigmaY: smooth)
              ..color = const Color(0xA6000000),
          );
          c.drawImage(old, Offset.zero, Paint());
          c.restore();
        });
      });

  // ---------- adjustments ----------
  Future<void> applyCurves(List<double> ys) {
    final lut = buildLut(ys);
    return _custom('Curves...', (old) => _mapPixels(old, (x, y, r, g, b, o) {
          o[0] = lut[math.max(0, math.min(255, r.round()))].toDouble();
          o[1] = lut[math.max(0, math.min(255, g.round()))].toDouble();
          o[2] = lut[math.max(0, math.min(255, b.round()))].toDouble();
        }));
  }

  Future<void> shadowsHighlights(double sh, double hl) =>
      _custom('Shadows/Highlights...', (old) => _mapPixels(old, (x, y, r, g, b, o) {
            final l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
            final sw = (1 - l) * (1 - l) * sh;
            final hw = l * l * hl;
            final d = 255 * 0.35 * (sw - hw);
            o[0] = r + d;
            o[1] = g + d;
            o[2] = b + d;
          }));

  void _hsv2rgb(double h, double s, double v, List<double> o) {
    final c = v * s;
    final hh = (h % 360) / 60;
    final x = c * (1 - ((hh % 2) - 1).abs());
    double r = 0, g = 0, b = 0;
    if (hh < 1) {
      r = c;
      g = x;
    } else if (hh < 2) {
      r = x;
      g = c;
    } else if (hh < 3) {
      g = c;
      b = x;
    } else if (hh < 4) {
      g = x;
      b = c;
    } else if (hh < 5) {
      r = x;
      b = c;
    } else {
      r = c;
      b = x;
    }
    final m = v - c;
    o[0] = (r + m) * 255;
    o[1] = (g + m) * 255;
    o[2] = (b + m) * 255;
  }

  Future<void> replaceColor(double srcHue, double range, double shift, double satAdj) {
    final tmp = List<double>.filled(3, 0);
    return _custom('Replace color...', (old) => _mapPixels(old, (x, y, r, g, b, o) {
          final mx = math.max(r, math.max(g, b));
          final mn = math.min(r, math.min(g, b));
          final d = mx - mn;
          double hue = 0;
          if (d > 0) {
            if (mx == r) {
              hue = 60 * (((g - b) / d) % 6);
            } else if (mx == g) {
              hue = 60 * ((b - r) / d + 2);
            } else {
              hue = 60 * ((r - g) / d + 4);
            }
          }
          if (hue < 0) hue += 360;
          final sat = mx == 0 ? 0.0 : d / mx;
          final diff = ((hue - srcHue + 540) % 360) - 180;
          o[0] = r;
          o[1] = g;
          o[2] = b;
          if (diff.abs() < range && sat > 0.08) {
            final w = 1 - diff.abs() / range;
            final ns = math.max(0.0, math.min(1.0, sat * (1 + satAdj)));
            _hsv2rgb(hue + shift, ns, mx / 255, tmp);
            o[0] = r + (tmp[0] - r) * w;
            o[1] = g + (tmp[1] - g) * w;
            o[2] = b + (tmp[2] - b) * w;
          }
        }));
  }

  // ---------- & menu ----------
  Future<void> applyWarp(double bulge, double twirl, double radius, double px, double py) {
    final cx = docW * px;
    final cy = docH * py;
    final rad = radius * math.min(docW, docH) / 2;
    return _custom('Warp...', (old) => _displace(old, (x, y) {
          final dx = x - cx;
          final dy = y - cy;
          final dist = math.sqrt(dx * dx + dy * dy);
          if (dist >= rad || dist == 0) return Offset(x.toDouble(), y.toDouble());
          final t = dist / rad;
          final k = (1 - t) * (1 - t);
          final sc = 1 - bulge * k;
          final ang = twirl * k;
          final ca = math.cos(ang);
          final sa = math.sin(ang);
          final ox = dx * sc;
          final oy = dy * sc;
          return Offset(cx + ox * ca - oy * sa, cy + ox * sa + oy * ca);
        }));
  }

  Future<void> applyFade(double angleDeg, double start, double end) =>
      _custom('Fade...', (old) {
        final a = angleDeg * math.pi / 180;
        final cx = docW / 2;
        final cy = docH / 2;
        final len = math.sqrt(docW * docW + docH * docH) / 2;
        final dx = math.cos(a) * len;
        final dy = math.sin(a) * len;
        final s0 = math.min(start, end - 0.01);
        return renderImage(docW, docH, (c) {
          c.saveLayer(_rect, Paint());
          c.drawImage(old, Offset.zero, Paint());
          c.drawRect(
            _rect,
            Paint()
              ..blendMode = BlendMode.dstIn
              ..shader = ui.Gradient.linear(
                Offset(cx - dx, cy - dy),
                Offset(cx + dx, cy + dy),
                const [Color(0xFFFFFFFF), Color(0x00FFFFFF)],
                [s0, end],
              ),
          );
          c.restore();
        });
      });

  Future<void> cameraFill(Uint8List bytes) => _custom('Camera fill...', (old) async {
        final src = await decodeBytes(bytes);
        final k = math.max(docW / src.width, docH / src.height);
        final w = src.width * k;
        final h = src.height * k;
        final dst = Rect.fromLTWH((docW - w) / 2, (docH - h) / 2, w, h);
        final img = await renderImage(docW, docH, (c) {
          c.drawImageRect(
            src,
            Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
            dst,
            Paint()..filterQuality = FilterQuality.high,
          );
        });
        src.dispose();
        return img;
      });

  Future<void> refineEdge(double smooth, double expand) => _guard('Refining...', () async {
        final m = selMask;
        if (m == null) return;
        final bl = await _blurred(m, math.max(0.5, smooth));
        final b = await _px(bl);
        final n = docW * docH;
        final px = Uint8List(n * 4);
        final thr = 0.5 - expand * 0.04;
        for (int i = 0; i < n; i++) {
          final a = b[i * 4 + 3] / 255.0;
          final v = (a - thr) * 6 + 0.5;
          final vv = v < 0 ? 0.0 : (v > 1 ? 1.0 : v);
          px[i * 4 + 3] = (vv * 255).round();
        }
        final nm = await imageFromRgba(px, docW, docH);
        await _setSelection(nm);
      });

  // ======================================================
  // Batch 4: layer masks, editable text, live preview, export
  // ======================================================
  bool editMask = false;
  List<double>? previewMatrix;
  double? previewBlur;

  void setPreviewMatrix(List<double>? m) {
    previewMatrix = m;
    notifyListeners();
  }

  void setPreviewBlur(double? b) {
    previewBlur = b;
    notifyListeners();
  }

  void clearPreview() {
    previewMatrix = null;
    previewBlur = null;
    notifyListeners();
  }

  void maskBadgeTap(int i) {
    final same = selected == i;
    selected = i;
    if (layers[i].mask != null) editMask = same ? !editMask : true;
    toast(editMask ? 'Editing mask: paint = reveal, eraser = hide' : 'Editing layer pixels');
    notifyListeners();
  }

  Future<void> addMask(String kind) => _guard('Mask...', () async {
        final l = current;
        if (l == null) return;
        ui.Image m;
        if (kind == 'hide') {
          m = await renderImage(docW, docH, (c) {});
        } else if (kind == 'selection' && selMask != null) {
          m = selMask!;
        } else {
          m = await renderImage(docW, docH, (c) {
            c.drawRect(_rect, Paint()..color = Colors.black);
          });
        }
        _pushUndo();
        l.mask = m;
        editMask = true;
      });

  Future<void> invertMask() => _guard('Mask...', () async {
        final l = current;
        final mk = l?.mask;
        if (l == null || mk == null) return;
        final inv = await renderImage(docW, docH, (c) {
          c.saveLayer(_rect, Paint());
          c.drawRect(_rect, Paint()..color = Colors.black);
          c.drawImage(mk, Offset.zero, Paint()..blendMode = BlendMode.dstOut);
          c.restore();
        });
        _pushUndo();
        l.mask = inv;
      });

  Future<void> applyMask() => _guard('Applying mask...', () async {
        final l = current;
        final mk = l?.mask;
        if (l == null || mk == null) return;
        final res = await renderImage(docW, docH, (c) {
          c.saveLayer(_rect, Paint());
          c.drawImage(l.image, Offset.zero, Paint());
          c.drawImage(mk, Offset.zero, Paint()..blendMode = BlendMode.dstIn);
          c.restore();
        });
        _pushUndo();
        l.image = res;
        l.mask = null;
        editMask = false;
      });

  void deleteMask() {
    final l = current;
    if (l == null || l.mask == null) return;
    _pushUndo();
    l.mask = null;
    editMask = false;
    notifyListeners();
  }

  Future<void> maskAction(String act) async {
    if (act == 'maskr') {
      await addMask('reveal');
    } else if (act == 'maskh') {
      await addMask('hide');
    } else if (act == 'masks') {
      await addMask('selection');
    } else if (act == 'maski') {
      await invertMask();
    } else if (act == 'maska') {
      await applyMask();
    } else if (act == 'maskd') {
      deleteMask();
    }
  }

  Future<Rect?> _boundsOf(ui.Image im) async {
    final b = await _px(im);
    final w = docW;
    final h = docH;
    int minX = w, minY = h, maxX = -1, maxY = -1;
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        if (b[(y * w + x) * 4 + 3] > 8) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return null;
    return Rect.fromLTRB(minX.toDouble(), minY.toDouble(), maxX + 1.0, maxY + 1.0);
  }

  Future<void> editText(String text, double size, bool bold, String family, Color col) =>
      _guard('Updating text...', () async {
        final l = current;
        if (l == null || l.textMeta == null) return;
        final ob = await _boundsOf(l.image);
        final rtl = RegExp(r'[\u0600-\u06FF]').hasMatch(text);
        final tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              fontSize: size,
              color: col,
              fontWeight: bold ? FontWeight.bold : FontWeight.normal,
              fontFamily: family == 'default' ? null : family,
            ),
          ),
          textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
          textAlign: TextAlign.center,
        );
        tp.layout(maxWidth: docW * 0.9);
        var off = Offset((docW - tp.width) / 2, (docH - tp.height) / 2);
        if (ob != null) off = ob.center - Offset(tp.width / 2, tp.height / 2);
        final img = await renderImage(docW, docH, (c) {
          tp.paint(c, off);
        });
        _pushUndo();
        l.image = img;
        l.textMeta = {
          'text': text,
          'size': size,
          'bold': bold,
          'family': family,
          'color': col.toARGB32(),
        };
      });

  Future<void> exportToPhotos() => _guard('Exporting...', () async {
        final bytes = await exportPng();
        await Gal.putImageBytes(bytes, album: 'PixelStudio');
        toast('Saved to Photos');
      });

  Future<void> flattenImage() => _guard('Flattening...', () async {
        if (layers.length < 2) return;
        final img = await renderImage(docW, docH, (c) => paintDoc(c, preview: false));
        _pushUndo();
        final id = _nextId++;
        layers
          ..clear()
          ..add(DocLayer(id: id, name: 'Background', image: img));
        selected = 0;
        editMask = false;
      });

  // ======================================================
  // Batch 6: interactive gradient tool (PS Touch style)
  // ======================================================
  bool gradActive = false;
  bool gradRadial = false;
  Offset gradA = Offset.zero;
  Offset gradB = Offset.zero;
  Color gradC1 = Colors.black;
  Color gradC2 = const Color(0x00000000);
  int gradStop = 0;
  bool gradEditor = false;
  bool gradPresets = false;
  bool gradHsb = true;
  bool gradPick = false;
  int _gradDrag = 0;
  bool _skipGrad = false;

  Color get gradColor => gradStop == 0 ? gradC1 : gradC2;

  void startGradient() {
    if (current == null) return;
    gradActive = true;
    gradRadial = false;
    gradC1 = color.withValues(alpha: 1);
    gradC2 = color.withValues(alpha: 0);
    gradStop = 0;
    gradEditor = false;
    gradPresets = false;
    gradPick = false;
    gradA = Offset(docW * 0.3, docH * 0.12);
    gradB = Offset(docW * 0.7, docH * 0.88);
    menu = null;
    toolMenuOpen = false;
    openGroup = null;
    notifyListeners();
  }

  Paint gradPaint() {
    final p = Paint();
    if (gradRadial) {
      final r = math.max(1.0, (gradB - gradA).distance);
      p.shader = ui.Gradient.radial(gradA, r, [gradC1, gradC2]);
    } else {
      final b = (gradB - gradA).distance < 1 ? gradA + const Offset(1, 1) : gradB;
      p.shader = ui.Gradient.linear(gradA, b, [gradC1, gradC2]);
    }
    return p;
  }

  void _gradDown(Offset doc) {
    if (gradPick) {
      _gradPickAt(doc);
      return;
    }
    final r = 46 / scale;
    final da = (gradA - doc).distance;
    final db = (gradB - doc).distance;
    if (da < r && da <= db) {
      _gradDrag = 1;
    } else if (db < r) {
      _gradDrag = 2;
    } else {
      gradA = doc;
      gradB = doc;
      _gradDrag = 2;
    }
    notifyListeners();
  }

  void _gradMove(Offset doc) {
    if (_gradDrag == 1) {
      gradA = doc;
    } else if (_gradDrag == 2) {
      gradB = doc;
    } else {
      return;
    }
    notifyListeners();
  }

  Future<void> _gradPickAt(Offset doc) async {
    final x = doc.dx.floor();
    final y = doc.dy.floor();
    if (x < 0 || y < 0 || x >= docW || y >= docH) return;
    _skipGrad = true;
    final fut = renderImage(docW, docH, (c) => paintDoc(c, preview: false));
    _skipGrad = false;
    final img = await fut;
    final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (bd == null) return;
    final d = bd.buffer.asUint8List();
    final i = (y * docW + x) * 4;
    final a = d[i + 3];
    if (a == 0) return;
    final inv = 255.0 / a;
    final c = Color.fromARGB(255, _c255(d[i] * inv), _c255(d[i + 1] * inv), _c255(d[i + 2] * inv));
    gradSetColor(c.withValues(alpha: gradColor.a));
    gradPick = false;
    notifyListeners();
  }

  void gradSetColor(Color c) {
    if (gradStop == 0) {
      gradC1 = c;
    } else {
      gradC2 = c;
    }
    notifyListeners();
  }

  void gradSelectStop(int i) {
    if (gradStop == i && gradEditor) {
      gradEditor = false;
    } else {
      gradStop = i;
      gradEditor = true;
      gradPresets = false;
    }
    notifyListeners();
  }

  void gradTogglePresets() {
    gradPresets = !gradPresets;
    gradEditor = false;
    notifyListeners();
  }

  void gradPreset(Color a, Color b, bool radial) {
    gradC1 = a;
    gradC2 = b;
    gradRadial = radial;
    gradPresets = false;
    notifyListeners();
  }

  void gradSetType(bool radial) {
    gradRadial = radial;
    notifyListeners();
  }

  void gradReverse() {
    final t = gradC1;
    gradC1 = gradC2;
    gradC2 = t;
    notifyListeners();
  }

  void gradSetHsb(bool v) {
    gradHsb = v;
    notifyListeners();
  }

  void gradTogglePick() {
    gradPick = !gradPick;
    if (gradPick) toast('Tap the image to pick a color');
    notifyListeners();
  }

  void gradCancel() {
    gradActive = false;
    gradEditor = false;
    gradPresets = false;
    gradPick = false;
    notifyListeners();
  }

  Future<void> gradApply() => _guard('Applying...', () async {
        final l = current;
        if (l == null) {
          gradActive = false;
          return;
        }
        final old = l.image;
        final comp = await renderImage(docW, docH, (c) {
          c.drawImage(old, Offset.zero, Paint());
          c.drawRect(_rect, gradPaint());
        });
        final res = await _masked(old, comp);
        _pushUndo();
        l.image = res;
        gradActive = false;
        gradEditor = false;
        gradPresets = false;
        gradPick = false;
      });

  // ---------- view ----------
  Offset toDoc(Offset p) => (p - offset) / scale;

  void transformView(Offset prevMid, Offset mid, double ratio) {
    final newScale = (scale * ratio).clamp(0.05, 40.0).toDouble();
    final docPoint = (prevMid - offset) / scale;
    scale = newScale;
    offset = mid - docPoint * scale;
    _userZoomed = true;
    _pingZoom();
    notifyListeners();
  }

  double fitTop = 90;
  double fitBottom = 110;

  void setFitInsets(double t, double b) {
    if ((t - fitTop).abs() < 0.5 && (b - fitBottom).abs() < 0.5) return;
    fitTop = t;
    fitBottom = b;
    if (!_userZoomed) {
      _fit();
      notifyListeners();
    }
  }

  void panBy(Offset d) {
    offset = offset + d;
    _userZoomed = true;
    notifyListeners();
  }

  void _fit() {
    if (viewport == Size.zero) return;
    final availH = math.max(100.0, viewport.height - fitTop - fitBottom);
    final availW = viewport.width - 24;
    final k = math.min(availW / docW, availH / docH);
    scale = k;
    offset = Offset((viewport.width - docW * k) / 2, fitTop + (availH - docH * k) / 2);
    _userZoomed = false;
  }

  void fitToScreen() {
    _fit();
    notifyListeners();
  }

  void setViewport(Size sz) {
    if (sz == viewport) return;
    viewport = sz;
    if (!_userZoomed) _fit();
    notifyListeners();
  }
}

// color matrices
const List<double> kMatInvert = [
  -1, 0, 0, 0, 255, //
  0, -1, 0, 0, 255,
  0, 0, -1, 0, 255,
  0, 0, 0, 1, 0,
];
const List<double> kMatGray = [
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0,
  0.2126, 0.7152, 0.0722, 0, 0,
  0, 0, 0, 1, 0,
];
const List<double> kMatSepia = [
  0.393, 0.769, 0.189, 0, 0, //
  0.349, 0.686, 0.168, 0, 0,
  0.272, 0.534, 0.131, 0, 0,
  0, 0, 0, 1, 0,
];
const List<double> kMatMoon = [
  0.35, 0.2, 0.1, 0, 0, //
  0.2, 0.45, 0.2, 0, 5,
  0.1, 0.25, 0.9, 0, 40,
  0, 0, 0, 1, 0,
];
const List<double> kMatSunny = [
  1.15, 0.05, 0, 0, 15, //
  0, 1.05, 0, 0, 5,
  0, 0, 0.8, 0, 0,
  0, 0, 0, 1, 0,
];
const List<double> kMatThreshold = [
  54.2, 182.4, 18.4, 0, -32640, //
  54.2, 182.4, 18.4, 0, -32640,
  54.2, 182.4, 18.4, 0, -32640,
  0, 0, 0, 1, 0,
];

List<double> matSaturation(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  return [
    lr * (1 - s) + s, lg * (1 - s), lb * (1 - s), 0, 0, //
    lr * (1 - s), lg * (1 - s) + s, lb * (1 - s), 0, 0,
    lr * (1 - s), lg * (1 - s), lb * (1 - s) + s, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

List<double> matBrightnessContrast(double brightness, double contrast) {
  final k = 1 + contrast;
  final o = 128 * (1 - k) + brightness;
  return [
    k, 0, 0, 0, o, //
    0, k, 0, 0, o,
    0, 0, k, 0, o,
    0, 0, 0, 1, 0,
  ];
}

bool gHaptics = true;

void buzz() {
  if (gHaptics) HapticFeedback.selectionClick();
}

typedef PixFn = void Function(int x, int y, double r, double g, double b, List<double> o);

List<int> buildLut(List<double> ys) {
  const xs = [0.0, 0.25, 0.5, 0.75, 1.0];
  const n = 5;
  final m = List<double>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    if (i == 0) {
      m[i] = (ys[1] - ys[0]) / (xs[1] - xs[0]);
    } else if (i == n - 1) {
      m[i] = (ys[n - 1] - ys[n - 2]) / (xs[n - 1] - xs[n - 2]);
    } else {
      m[i] = (ys[i + 1] - ys[i - 1]) / (xs[i + 1] - xs[i - 1]);
    }
  }
  final lut = List<int>.filled(256, 0);
  for (int v = 0; v < 256; v++) {
    final x = v / 255.0;
    int sg = 0;
    while (sg < n - 2 && x > xs[sg + 1]) {
      sg++;
    }
    final h = xs[sg + 1] - xs[sg];
    final t = (x - xs[sg]) / h;
    final t2 = t * t;
    final t3 = t2 * t;
    final y = (2 * t3 - 3 * t2 + 1) * ys[sg] +
        (t3 - 2 * t2 + t) * h * m[sg] +
        (-2 * t3 + 3 * t2) * ys[sg + 1] +
        (t3 - t2) * h * m[sg + 1];
    final yy = math.max(0.0, math.min(1.0, y));
    lut[v] = (yy * 255).round();
  }
  return lut;
}

List<double> matLevels(double black, double white) {
  final k = 255 / math.max(1.0, white - black);
  final o = -black * k;
  return [
    k, 0, 0, 0, o, //
    0, k, 0, 0, o,
    0, 0, k, 0, o,
    0, 0, 0, 1, 0,
  ];
}

List<double> matColorBalance(double r, double g, double b) {
  return [
    1, 0, 0, 0, r, //
    0, 1, 0, 0, g,
    0, 0, 1, 0, b,
    0, 0, 0, 1, 0,
  ];
}

List<double> matTemperature(double t) {
  return [
    1 + 0.3 * t, 0, 0, 0, 0, //
    0, 1, 0, 0, 0,
    0, 0, 1 - 0.3 * t, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

// ============================================================
// Canvas painter + gesture view
// ============================================================
class DocPainter extends CustomPainter {
  final EditorState s;
  DocPainter(this.s) : super(repaint: Listenable.merge([s, s.antTick]));

  static Path? _checker;
  static int _cw = 0;
  static int _ch = 0;

  static Path _checkerPath(int w, int h) {
    if (_checker != null && _cw == w && _ch == h) return _checker!;
    const t = 32.0;
    final p = Path();
    for (int y = 0; y * t < h; y++) {
      for (int x = 0; x < w / t; x++) {
        if ((x + y).isOdd) p.addRect(Rect.fromLTWH(x * t, y * t, t, t));
      }
    }
    _checker = p;
    _cw = w;
    _ch = h;
    return p;
  }

  void _ants(Canvas canvas, Path path) {
    final lw = 2 / s.scale;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lw
        ..color = Colors.white,
    );
    canvas.drawPath(
      dashPath(path, 6 / s.scale, 6 / s.scale),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = lw
        ..color = Colors.black,
    );
  }

  void _handle(Canvas canvas, Offset p, double r, Color fill) {
    canvas.drawCircle(p, r, Paint()..color = fill);
    canvas.drawCircle(
      p,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / s.scale
        ..color = Colors.black87,
    );
  }

  void _extraOverlays(Canvas canvas) {
    final sc = s.scale;
    final lw = 2 / sc;
    if (s.gradActive) {
      final a = s.gradA;
      final b = s.gradB;
      final dark = Paint()
        ..strokeWidth = 4.5 / sc
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x66000000);
      final line = Paint()
        ..strokeWidth = 2.2 / sc
        ..strokeCap = StrokeCap.round
        ..color = Colors.white;
      canvas.drawLine(a, b, dark);
      canvas.drawLine(a, b, line);
      if (s.gradRadial) {
        canvas.drawCircle(
          a,
          (b - a).distance,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6 / sc
            ..color = const Color(0x99FFFFFF),
        );
      }
      for (final p in [a, b]) {
        canvas.drawCircle(p, 20 / sc, Paint()..color = const Color(0x66808080));
        canvas.drawCircle(p, 15 / sc, Paint()..color = Colors.white);
      }
    }
    if (s.ptrMode) {
      final p = s.ptr;
      final r = 20 / sc;
      final shadow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5 / sc
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x99000000);
      final white = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2 / sc
        ..strokeCap = StrokeCap.round
        ..color = Colors.white;
      for (final pp in [shadow, white]) {
        canvas.drawLine(p + Offset(-r * 1.6, 0), p + Offset(-r * 0.45, 0), pp);
        canvas.drawLine(p + Offset(r * 0.45, 0), p + Offset(r * 1.6, 0), pp);
        canvas.drawLine(p + Offset(0, -r * 1.6), p + Offset(0, -r * 0.45), pp);
        canvas.drawLine(p + Offset(0, r * 0.45), p + Offset(0, r * 1.6), pp);
      }
      canvas.drawCircle(p, 3.4 / sc, Paint()..color = Pal.accent);
    }
    if ((s.tool == Tool.fxBrush || (s.editMask && s.current?.mask != null && s.isPaintTool)) &&
        s.stroke.length > 1) {
      canvas.drawPath(
        Path()..addPolygon(s.stroke, false),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.brushSize
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = const Color(0x44FFFFFF),
      );
    }
    if (s.stroke.isNotEmpty && (s.isPaintTool || s.tool == Tool.stamp)) {
      final p = s.stroke.last;
      canvas.drawCircle(
        p,
        s.brushSize / 2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lw
          ..color = Colors.white70,
      );
      canvas.drawCircle(
        p,
        s.brushSize / 2 + lw,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lw
          ..color = Colors.black54,
      );
    }
    if (s.tool == Tool.stamp) {
      Offset? src = s.stampSource;
      if (s.stampOffset != null && s.stroke.isNotEmpty) {
        src = s.stroke.last + s.stampOffset!;
      }
      if (src != null) {
        final r = 16 / sc;
        final pp = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lw
          ..color = const Color(0xFF4DB3FF);
        canvas.drawCircle(src, r, pp);
        canvas.drawLine(src + Offset(-r * 1.6, 0), src + Offset(r * 1.6, 0), pp);
        canvas.drawLine(src + Offset(0, -r * 1.6), src + Offset(0, r * 1.6), pp);
      }
      if (s.stroke.length > 1) {
        canvas.drawPath(
          Path()..addPolygon(s.stroke, false),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.brushSize
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0x44FFFFFF),
        );
      }
    }
    if (s.xfActive) {
      final pts = s.xfHandleDocPoints();
      final box = Path()..addPolygon([pts[0], pts[1], pts[2], pts[3]], true);
      canvas.drawPath(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lw
          ..color = Colors.white,
      );
      canvas.drawPath(
        dashPath(box, 6 / sc, 6 / sc),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lw
          ..color = Colors.black,
      );
      canvas.drawLine(
        pts[4],
        pts[8],
        Paint()
          ..strokeWidth = lw
          ..color = Colors.white,
      );
      for (int i = 0; i < 8; i++) {
        _handle(canvas, pts[i], 11 / sc, Colors.white);
      }
      _handle(canvas, pts[8], 13 / sc, const Color(0xFF4DB3FF));
    }
    if (s.cropActive) {
      final full = Path()..addRect(Rect.fromLTWH(0, 0, s.docW.toDouble(), s.docH.toDouble()));
      final hole = Path()..addRect(s.cropRect);
      canvas.drawPath(
        Path.combine(PathOperation.difference, full, hole),
        Paint()..color = const Color(0xAA000000),
      );
      canvas.drawRect(
        s.cropRect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = lw
          ..color = Colors.white,
      );
      final r = s.cropRect;
      final gp = Paint()
        ..strokeWidth = lw * 0.6
        ..color = Colors.white54;
      for (int i = 1; i < 3; i++) {
        final x = r.left + r.width * i / 3;
        final y = r.top + r.height * i / 3;
        canvas.drawLine(Offset(x, r.top), Offset(x, r.bottom), gp);
        canvas.drawLine(Offset(r.left, y), Offset(r.right, y), gp);
      }
      for (final p in s.cropHandlePoints()) {
        _handle(canvas, p, 11 / sc, Colors.white);
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (s.layers.isEmpty) return;
    final rect = Rect.fromLTWH(0, 0, s.docW.toDouble(), s.docH.toDouble());
    canvas.save();
    canvas.translate(s.offset.dx, s.offset.dy);
    canvas.scale(s.scale);
    canvas.drawRect(rect.inflate(3 / s.scale), Paint()..color = Colors.black54);
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawPath(
        _checkerPath(s.docW, s.docH), Paint()..color = const Color(0xFFD9D9D9));
    s.paintDoc(canvas, preview: true);
    final ei = s.selEdges;
    final edge = ei.isNotEmpty ? ei[s.antTick.value % ei.length] : s.selEdge;
    if (s.selEdge != null && edge != null) {
      canvas.drawImage(edge, Offset.zero, Paint()..filterQuality = FilterQuality.none);
    }
    canvas.restore();

    // in-progress overlays
    _extraOverlays(canvas);
    final shape = s.shapePath();
    if (shape != null) _ants(canvas, shape);

    if (s.stroke.length > 1) {
      if (s.tool == Tool.lasso) {
        final p = Path()..addPolygon(s.stroke, false);
        _ants(canvas, p);
      } else if (s.tool == Tool.selBrush) {
        final p = Path()..addPolygon(s.stroke, false);
        canvas.drawPath(
          p,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.brushSize
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..color = const Color(0x660E8CE6),
        );
      }
    }

    if (s.poly.isNotEmpty) {
      final p = Path()..addPolygon(s.poly, false);
      _ants(canvas, p);
      for (final v in s.poly) {
        canvas.drawCircle(v, 6 / s.scale, Paint()..color = Colors.white);
        canvas.drawCircle(
          v,
          6 / s.scale,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5 / s.scale
            ..color = Colors.black,
        );
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant DocPainter old) => true;
}

class CanvasView extends StatefulWidget {
  const CanvasView({super.key});

  @override
  State<CanvasView> createState() => _CanvasViewState();
}

class _CanvasViewState extends State<CanvasView> {
  final Map<int, Offset> _ptrs = {};
  Offset? _down;
  bool _moved = false;
  bool _multi = false;
  bool _ignore = false;

  @override
  Widget build(BuildContext context) {
    final s = context.read<EditorState>();
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      if (size != s.viewport) {
        WidgetsBinding.instance.addPostFrameCallback((_) => s.setViewport(size));
      }
      return ClipRect(
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            _ptrs[e.pointer] = e.localPosition;
            if (_ptrs.length == 1) {
              _down = e.localPosition;
              _moved = false;
              _multi = false;
              _ignore = s.closeOverlays();
              if (!_ignore && !s.ptrMode) s.gestureDown(s.toDoc(e.localPosition));
            } else {
              _multi = true;
              s.gestureCancel();
            }
          },
          onPointerMove: (e) {
            final prev = _ptrs[e.pointer];
            if (prev == null) return;
            if (_ptrs.length == 1 && !_multi) {
              if (!_moved && _down != null && (e.localPosition - _down!).distance > 10) {
                _moved = true;
              }
              if (!_ignore) {
                if (s.ptrMode) {
                  s.panBy(e.localPosition - prev);
                } else {
                  s.gestureMove(s.toDoc(e.localPosition));
                }
              }
              _ptrs[e.pointer] = e.localPosition;
            } else if (_ptrs.length == 2) {
              final other = _ptrs.entries.firstWhere((x) => x.key != e.pointer).value;
              final prevMid = (prev + other) / 2;
              final prevDist = (prev - other).distance;
              final mid = (e.localPosition + other) / 2;
              final dist = (e.localPosition - other).distance;
              s.transformView(prevMid, mid, prevDist == 0 ? 1 : dist / prevDist);
              _ptrs[e.pointer] = e.localPosition;
            }
          },
          onPointerUp: (e) {
            final wasOne = _ptrs.length == 1 && !_multi && !_ignore;
            _ptrs.remove(e.pointer);
            if (wasOne && !s.ptrMode) s.gestureUp(s.toDoc(e.localPosition), _moved);
            if (_ptrs.isEmpty) {
              _multi = false;
              _ignore = false;
            }
          },
          onPointerCancel: (e) {
            _ptrs.remove(e.pointer);
            s.gestureCancel();
            if (_ptrs.isEmpty) {
              _multi = false;
              _ignore = false;
            }
          },
          child: CustomPaint(
            painter: DocPainter(s),
            size: Size.infinite,
          ),
        ),
      );
    });
  }
}

// ============================================================
// Shared dialogs
// ============================================================
class Param {
  final String label;
  final double min;
  final double max;
  final double init;
  const Param(this.label, this.min, this.max, this.init);
}

Future<List<double>?> paramDialog(
  BuildContext ctx,
  String title,
  List<Param> ps, {
  EditorState? es,
  List<double> Function(List<double>)? matrixOf,
  double Function(List<double>)? blurOf,
}) async {
  final vals = ps.map((p) => p.init).toList();
  void live() {
    if (es == null) return;
    if (matrixOf != null) es.setPreviewMatrix(matrixOf(vals));
    if (blurOf != null) es.setPreviewBlur(blurOf(vals));
  }

  live();
  final r = await showDialog<List<double>>(
    context: ctx,
    barrierColor: (matrixOf != null || blurOf != null) ? Colors.transparent : Colors.black54,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setS) => Dialog(
        backgroundColor: kMenuBg,
        alignment: Alignment.bottomCenter,
        insetPadding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: lbl(20)),
              const SizedBox(height: 6),
              for (int i = 0; i < ps.length; i++)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${ps[i].label}: ${vals[i].toStringAsFixed(1)}', style: lbl(14)),
                    Slider(
                      value: vals[i],
                      min: ps[i].min,
                      max: ps[i].max,
                      onChanged: (v) => setS(() {
                        vals[i] = v;
                        live();
                      }),
                    ),
                  ],
                ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: () => Navigator.pop(dctx, vals), child: const Text('Apply')),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
  es?.clearPreview();
  return r;
}

Future<void> sliderSheet(
  BuildContext ctx,
  String title,
  double min,
  double max,
  double Function() get,
  void Function(double) set,
) {
  return showModalBottomSheet<void>(
    context: ctx,
    backgroundColor: kMenuBg,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$title: ${get().round()}', style: lbl(18)),
            Slider(
              value: get().clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: (v) {
                set(v);
                setS(() {});
              },
            ),
          ],
        ),
      ),
    ),
  );
}

Future<void> colorSheet(BuildContext ctx, EditorState es) {
  const swatches = <int>[
    0xFF000000, 0xFF424242, 0xFF9E9E9E, 0xFFFFFFFF,
    0xFFB71C1C, 0xFFF44336, 0xFFFF9800, 0xFFFFEB3B,
    0xFF8BC34A, 0xFF2E7D32, 0xFF00BCD4, 0xFF2196F3,
    0xFF1A237E, 0xFF9C27B0, 0xFFE91E63, 0xFF795548,
  ];
  return showModalBottomSheet<void>(
    context: ctx,
    backgroundColor: kMenuBg,
    builder: (c) => StatefulBuilder(
      builder: (c, setS) {
        final hsv = HSVColor.fromColor(es.color);
        void setHsv(HSVColor h) {
          es.setColor(h.toColor());
          setS(() {});
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final v in swatches)
                    GestureDetector(
                      onTap: () {
                        es.setColor(Color(v));
                        setS(() {});
                      },
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: Color(v),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white54, width: 1.5),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(children: [
                const SizedBox(width: 30, child: Text('H')),
                Expanded(
                  child: Slider(
                    value: hsv.hue,
                    min: 0,
                    max: 359.9,
                    onChanged: (v) => setHsv(hsv.withHue(v)),
                  ),
                ),
              ]),
              Row(children: [
                const SizedBox(width: 30, child: Text('S')),
                Expanded(
                  child: Slider(
                    value: hsv.saturation,
                    onChanged: (v) => setHsv(hsv.withSaturation(v)),
                  ),
                ),
              ]),
              Row(children: [
                const SizedBox(width: 30, child: Text('B')),
                Expanded(
                  child: Slider(
                    value: hsv.value,
                    onChanged: (v) => setHsv(hsv.withValue(v)),
                  ),
                ),
              ]),
            ],
          ),
        );
      },
    ),
  );
}

// ============================================================
// Gallery (home screen)
// ============================================================
// ============================================================
// Gallery (home) - batch 5
// ============================================================
class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Pal.surface,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Pal.line),
        ),
        child: Icon(icon, size: 21, color: Pal.txt),
      ),
    );
  }
}

class _FadeIn extends StatelessWidget {
  final int index;
  final Widget child;
  const _FadeIn({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 320 + math.min(index, 8) * 55),
      curve: Curves.easeOutCubic,
      builder: (c, v, ch) => Opacity(
        opacity: v,
        child: Transform.translate(offset: Offset(0, (1 - v) * 22), child: ch),
      ),
      child: child,
    );
  }
}

Future<void> showSettings(BuildContext ctx) {
  final t = ctx.read<AppTheme>();
  return showDialog<void>(
    context: ctx,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setS) => AlertDialog(
        backgroundColor: Pal.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        title: Text('Settings', style: lbl(21)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Theme', style: lbl(13, color: Pal.mut)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment<bool>(
                      value: true, label: Text('Dark'), icon: Icon(Icons.dark_mode_outlined)),
                  ButtonSegment<bool>(
                      value: false, label: Text('Light'), icon: Icon(Icons.light_mode_outlined)),
                ],
                selected: {Pal.dark},
                onSelectionChanged: (s) {
                  t.update(dark: s.first);
                  setS(() {});
                },
              ),
              const SizedBox(height: 18),
              Text('Accent color', style: lbl(13, color: Pal.mut)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in AppTheme.accents)
                    GestureDetector(
                      onTap: () {
                        buzz();
                        t.update(accent: c);
                        setS(() {});
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Pal.accent.toARGB32() == c.toARGB32() ? Pal.txt : Colors.transparent,
                            width: 3,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Haptic feedback', style: lbl(15)),
                value: t.haptics,
                onChanged: (v) {
                  t.update(haptics: v);
                  setS(() {});
                },
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(dctx), child: const Text('Done')),
        ],
      ),
    ),
  );
}

class GalleryPage extends StatelessWidget {
  const GalleryPage({super.key});

  Future<void> _openEditor(BuildContext context) async {
    await Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 340),
      pageBuilder: (_, __, ___) => const EditorPage(),
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
      ),
    ));
    if (context.mounted) await context.read<ProjectStore>().load();
  }

  Future<void> _open(BuildContext context, ProjectInfo p) async {
    final es = context.read<EditorState>();
    try {
      await es.openProject(p);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Open failed: $e')));
      }
      return;
    }
    if (context.mounted) await _openEditor(context);
  }

  Future<void> _newProject(BuildContext context) async {
    final es = context.read<EditorState>();
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => _NewProjectDialog(hasClip: es.clipboard != null),
    );
    if (choice == null || !context.mounted) return;
    try {
      if (choice == 'photo' || choice == 'camera') {
        final b = await pickBytes(choice == 'photo' ? ImageSource.gallery : ImageSource.camera);
        if (b == null) return;
        await es.createFromBytes(b);
      } else if (choice == 'blank') {
        final size = await showDialog<List<int>>(
          context: context,
          builder: (ctx) => SimpleDialog(
            backgroundColor: Pal.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
            title: Text('Blank document', style: lbl(20)),
            children: [
              for (final o in const [
                ['1080 x 1080', 1080, 1080],
                ['1080 x 1350', 1080, 1350],
                ['1080 x 1920 (9:16)', 1080, 1920],
                ['1920 x 1080', 1920, 1080],
                ['2048 x 2048', 2048, 2048],
              ])
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, [o[1] as int, o[2] as int]),
                  child: Text(o[0] as String, style: lbl(17)),
                ),
            ],
          ),
        );
        if (size == null) return;
        await es.createBlank(size[0], size[1]);
      } else {
        await es.createFromClipboard();
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e')));
      return;
    }
    if (context.mounted) await _openEditor(context);
  }

  Future<void> _projectMenu(BuildContext context, ProjectInfo p) async {
    final store = context.read<ProjectStore>();
    final es = context.read<EditorState>();
    final messenger = ScaffoldMessenger.of(context);
    final act = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: Text('Rename', style: lbl(16)),
              onTap: () => Navigator.pop(c, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.save_alt),
              title: Text('Export PNG to Photos', style: lbl(16)),
              onTap: () => Navigator.pop(c, 'export'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: Text('Delete', style: lbl(16)),
              onTap: () => Navigator.pop(c, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (act == null || !context.mounted) return;
    if (act == 'rename') {
      final ctrl = TextEditingController(text: p.name);
      final name = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Pal.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          title: Text('Rename', style: lbl(20)),
          content: TextField(controller: ctrl, autofocus: true),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('OK')),
          ],
        ),
      );
      if (name != null && name.isNotEmpty) await store.rename(p, name);
    } else if (act == 'export') {
      try {
        await es.openProject(p);
        final bytes = await es.exportPng();
        await Gal.putImageBytes(bytes, album: 'PixelStudio');
        messenger.showSnackBar(const SnackBar(content: Text('Saved to Photos')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } else if (act == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Pal.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          title: Text('Delete "${p.name}"?', style: lbl(19)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
          ],
        ),
      );
      if (ok == true) await store.delete(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<ProjectStore>();
    final theme = context.watch<AppTheme>();
    return Scaffold(
      backgroundColor: Pal.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 26, 16, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PixelStudio',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.8,
                                color: Pal.txt,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text('${store.items.length} projects',
                                style: lbl(13, color: Pal.mut)),
                          ],
                        ),
                      ),
                      _RoundBtn(icon: Icons.sort, onTap: store.toggleSort),
                      const SizedBox(width: 8),
                      _RoundBtn(
                        icon: Pal.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                        onTap: () => theme.update(dark: !Pal.dark),
                      ),
                      const SizedBox(width: 8),
                      _RoundBtn(icon: Icons.settings_outlined, onTap: () => showSettings(context)),
                    ],
                  ),
                ),
                Expanded(
                  child: store.items.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.layers_outlined, size: 54, color: Pal.dim),
                              const SizedBox(height: 14),
                              Text(
                                store.loaded ? 'No projects yet' : 'Loading...',
                                style: lbl(17, color: Pal.mut),
                              ),
                              if (store.loaded)
                                Text('Tap New project to start',
                                    style: lbl(13, color: Pal.dim)),
                            ],
                          ),
                        )
                      : GridView.builder(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 18,
                            childAspectRatio: 0.86,
                          ),
                          itemCount: store.items.length,
                          itemBuilder: (c, i) {
                            final p = store.items[i];
                            return _FadeIn(
                              index: i,
                              child: Pressable(
                                onTap: () => _open(context, p),
                                onLongPress: () => _projectMenu(context, p),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Pal.surface,
                                          borderRadius: BorderRadius.circular(22),
                                          border: Border.all(color: Pal.line),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: SizedBox.expand(
                                          child: Image.file(
                                            File('${store.rootPath}/${p.id}/thumb.png'),
                                            fit: BoxFit.cover,
                                            errorBuilder: (a, b, c) => const SizedBox(),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 9),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              p.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: lbl(14),
                                            ),
                                          ),
                                          Text('${p.w}x${p.h}', style: lbl(11, color: Pal.dim)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
            Positioned(
              right: 20,
              bottom: 20,
              child: FloatingActionButton.extended(
                onPressed: () => _newProject(context),
                backgroundColor: Pal.accent,
                foregroundColor: Pal.onAccent,
                icon: const Icon(Icons.add),
                label: Text('New project', style: lbl(15, color: Pal.onAccent)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DlgOpt extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  const _DlgOpt({required this.icon, required this.label, this.onTap, this.primary = false});

  @override
  Widget build(BuildContext context) {
    final en = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: en ? 1 : 0.35,
        child: Pressable(
          onTap: onTap,
          child: Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: primary ? Pal.accent : Pal.fill,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: primary ? Colors.transparent : Pal.line),
            ),
            child: Row(
              children: [
                Icon(icon, size: 22, color: primary ? Pal.onAccent : Pal.accent),
                const SizedBox(width: 14),
                Text(label, style: lbl(15.5, color: primary ? Pal.onAccent : Pal.txt)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewProjectDialog extends StatelessWidget {
  final bool hasClip;
  const _NewProjectDialog({required this.hasClip});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Pal.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New project from', style: lbl(21)),
            const SizedBox(height: 16),
            _DlgOpt(
              icon: Icons.photo_library_outlined,
              label: 'Photo library',
              primary: true,
              onTap: () => Navigator.pop(context, 'photo'),
            ),
            _DlgOpt(
                icon: Icons.photo_camera_outlined,
                label: 'Camera',
                onTap: () => Navigator.pop(context, 'camera')),
            _DlgOpt(
                icon: Icons.crop_portrait_outlined,
                label: 'Blank document',
                onTap: () => Navigator.pop(context, 'blank')),
            _DlgOpt(
              icon: Icons.content_paste_outlined,
              label: 'Clipboard',
              onTap: hasClip ? () => Navigator.pop(context, 'clip') : null,
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showAddLayerDialog(BuildContext ctx, EditorState es) async {
  final act = await showDialog<String>(
    context: ctx,
    builder: (dctx) => Dialog(
      backgroundColor: Pal.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Add layer', style: lbl(21)),
            const SizedBox(height: 16),
            _DlgOpt(
                icon: Icons.add_photo_alternate_outlined,
                label: 'Photo layer',
                onTap: () => Navigator.pop(dctx, 'photo')),
            _DlgOpt(
                icon: Icons.check_box_outline_blank,
                label: 'Empty layer',
                onTap: () => Navigator.pop(dctx, 'empty')),
            _DlgOpt(
                icon: Icons.copy_all,
                label: 'Duplicate layer',
                onTap: () => Navigator.pop(dctx, 'dup')),
            _DlgOpt(
              icon: Icons.filter_center_focus,
              label: 'Layer from selection',
              onTap: es.hasSel ? () => Navigator.pop(dctx, 'sel') : null,
            ),
            const SizedBox(height: 4),
            _DlgOpt(
              icon: Icons.check,
              label: 'Done',
              primary: true,
              onTap: () => Navigator.pop(dctx),
            ),
          ],
        ),
      ),
    ),
  );
  if (act == null) return;
  if (act == 'photo') {
    final b = await pickBytes(ImageSource.gallery);
    if (b != null) await es.addImageLayer(b);
  } else if (act == 'empty') {
    await es.addLayer();
  } else if (act == 'dup') {
    es.duplicateLayer();
  } else if (act == 'sel') {
    await es.extractToLayer();
  }
}

// ============================================================
// Reusable animated widgets
// ============================================================
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool haptic;
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.haptic = true,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) buzz();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ============================================================
// Extra dialogs for batch 2
// ============================================================
Future<void> textDialog(BuildContext ctx, EditorState es, {bool edit = false}) async {
  final meta = edit ? es.current?.textMeta : null;
  final ctrl = TextEditingController(text: (meta?['text'] as String?) ?? '');
  double size = ((meta?['size'] as num?) ?? 120).toDouble();
  bool bold = (meta?['bold'] as bool?) ?? true;
  String family = (meta?['family'] as String?) ?? 'default';
  bool useCur = !edit;
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setS) => AlertDialog(
        backgroundColor: kMenuBg,
        title: Text('Text', style: lbl(20)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLines: 4,
                minLines: 2,
                decoration: const InputDecoration(hintText: 'Type here / اكتب هنا'),
              ),
              const SizedBox(height: 10),
              Text('Size: ${size.round()}', style: lbl(14)),
              Slider(
                value: size,
                min: 20,
                max: 500,
                onChanged: (v) => setS(() => size = v),
              ),
              SwitchListTile(
                dense: true,
                title: Text('Bold', style: lbl(14)),
                value: bold,
                onChanged: (v) => setS(() => bold = v),
              ),
              DropdownButton<String>(
                isExpanded: true,
                value: family,
                items: const [
                  DropdownMenuItem(value: 'default', child: Text('Default')),
                  DropdownMenuItem(value: 'serif', child: Text('Serif')),
                  DropdownMenuItem(value: 'sans-serif', child: Text('Sans')),
                  DropdownMenuItem(value: 'monospace', child: Text('Monospace')),
                ],
                onChanged: (v) {
                  if (v != null) setS(() => family = v);
                },
              ),
              if (edit)
                SwitchListTile(
                  dense: true,
                  title: Text('Use current paint color', style: lbl(14)),
                  value: useCur,
                  onChanged: (v) => setS(() => useCur = v),
                )
              else
                Text('Color = current paint color', style: lbl(12, color: Colors.white54)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Add')),
        ],
      ),
    ),
  );
  if (ok == true && ctrl.text.trim().isNotEmpty) {
    if (edit && meta != null) {
      final col = useCur ? es.color : Color((meta['color'] as int?) ?? es.color.toARGB32());
      await es.editText(ctrl.text.trim(), size, bold, family, col);
    } else {
      await es.addText(ctrl.text.trim(), size, bold, family, es.color);
    }
  }
}

Future<void> rotateSheet(BuildContext ctx, EditorState es) async {
  final act = await showModalBottomSheet<String>(
    context: ctx,
    backgroundColor: kMenuBg,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in const [
            ['cw', 'Rotate 90 clockwise', Icons.rotate_right],
            ['ccw', 'Rotate 90 counter-clockwise', Icons.rotate_left],
            ['180', 'Rotate 180', Icons.refresh],
            ['fh', 'Flip horizontal', Icons.flip],
            ['fv', 'Flip vertical', Icons.swap_vert],
          ])
            ListTile(
              leading: Icon(e[2] as IconData),
              title: Text(e[1] as String, style: lbl(18)),
              onTap: () => Navigator.pop(c, e[0] as String),
            ),
        ],
      ),
    ),
  );
  if (act != null) await es.rotateAll(act);
}

// ============================================================
// Editor page
// ============================================================
class _CurvePainter extends CustomPainter {
  final List<double> ys;
  _CurvePainter(this.ys);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF1B1B1B));
    final grid = Paint()
      ..strokeWidth = 1
      ..color = Colors.white12;
    for (int i = 1; i < 4; i++) {
      canvas.drawLine(Offset(size.width * i / 4, 0), Offset(size.width * i / 4, size.height), grid);
      canvas.drawLine(Offset(0, size.height * i / 4), Offset(size.width, size.height * i / 4), grid);
    }
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), Paint()..color = Colors.white24);
    final lut = buildLut(ys);
    final path = Path();
    for (int v = 0; v < 256; v++) {
      final p = Offset(v / 255 * size.width, (1 - lut[v] / 255) * size.height);
      if (v == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
    for (int i = 0; i < 5; i++) {
      final p = Offset(i / 4 * size.width, (1 - ys[i]) * size.height);
      canvas.drawCircle(p, 9, Paint()..color = const Color(0xFF4DB3FF));
      canvas.drawCircle(
        p,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter old) => true;
}

Future<void> curvesDialog(BuildContext ctx, EditorState es) async {
  final ys = <double>[0, 0.25, 0.5, 0.75, 1];
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setS) {
        const sz = 260.0;
        void drag(Offset p) {
          const xs = [0.0, 0.25, 0.5, 0.75, 1.0];
          int idx = 0;
          double best = 9;
          for (int i = 0; i < 5; i++) {
            final d = (p.dx / sz - xs[i]).abs();
            if (d < best) {
              best = d;
              idx = i;
            }
          }
          setS(() {
            ys[idx] = math.max(0.0, math.min(1.0, 1 - p.dy / sz));
          });
        }

        return AlertDialog(
          backgroundColor: kMenuBg,
          title: Text('Curves', style: lbl(20)),
          content: GestureDetector(
            onPanStart: (d) => drag(d.localPosition),
            onPanUpdate: (d) => drag(d.localPosition),
            onTapDown: (d) => drag(d.localPosition),
            child: CustomPaint(size: const Size(sz, sz), painter: _CurvePainter(List<double>.of(ys))),
          ),
          actions: [
            TextButton(
              onPressed: () => setS(() {
                for (int i = 0; i < 5; i++) {
                  ys[i] = i / 4;
                }
              }),
              child: const Text('Reset'),
            ),
            TextButton(onPressed: () => Navigator.pop(dctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dctx, true), child: const Text('Apply')),
          ],
        );
      },
    ),
  );
  if (ok == true) await es.applyCurves(ys);
}

// ============================================================
// Editor page - batch 5 (floating UI, menus always on top)
// ============================================================
const double kBarH = 58;
const double kDockH = 78;

class _DotGrid extends CustomPainter {
  final bool dark;
  _DotGrid(this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Pal.stageBg);
    final p = Paint()..color = dark ? const Color(0x12FFFFFF) : const Color(0x1A141828);
    for (double y = 11; y < size.height; y += 22) {
      for (double x = 11; x < size.width; x += 22) {
        canvas.drawCircle(Offset(x, y), 1.1, p);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotGrid old) => old.dark != dark;
}

class EditorPage extends StatefulWidget {
  const EditorPage({super.key});

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  late final EditorState _es;

  @override
  void initState() {
    super.initState();
    _es = context.read<EditorState>();
  }

  @override
  void dispose() {
    _es.onToast = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final es = context.watch<EditorState>();
    context.watch<AppTheme>();
    es.onToast = (m) {
      final ms = ScaffoldMessenger.of(context);
      ms.hideCurrentSnackBar();
      ms.showSnackBar(SnackBar(content: Text(m), duration: const Duration(seconds: 2)));
    };
    final mq = MediaQuery.of(context);
    final topBarTop = mq.padding.top + 10;
    final topInset = topBarTop + kBarH + 10;
    final dockBottom = mq.padding.bottom + 10;
    final bottomInset = dockBottom + kDockH + 12;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) es.setFitInsets(topInset, bottomInset);
    });

    return Scaffold(
      backgroundColor: Pal.bg,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: _DotGrid(Pal.dark), child: const CanvasView()),
            ),
          ),
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: es.showZoom ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: Pal.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Pal.line),
                    ),
                    child: Text('${(es.scale * 100).round()}%', style: lbl(12.5)),
                  ),
                ),
              ),
            ),
          ),
          if (es.ptrMode)
            PointerControls(
              bottom: bottomInset + 4,
              rightInset: es.layersOpen ? 94 + 10 + 16 : 22,
            ),
          Positioned(
            right: 10,
            top: topInset - 4,
            bottom: bottomInset - 8,
            width: 94,
            child: IgnorePointer(
              ignoring: !es.layersOpen,
              child: AnimatedSlide(
                offset: es.layersOpen ? Offset.zero : const Offset(1.35, 0),
                duration: const Duration(milliseconds: 420),
                curve: Curves.easeOutBack,
                child: AnimatedOpacity(
                  opacity: es.layersOpen ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: LayersPanel(pageContext: context),
                ),
              ),
            ),
          ),
          if (es.tool == Tool.polygon && es.poly.length >= 3)
            Positioned(
              bottom: bottomInset + 6,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'polyNo',
                    backgroundColor: Pal.surface,
                    foregroundColor: Pal.txt,
                    onPressed: es.cancelPolygon,
                    child: const Icon(Icons.close),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton.small(
                    heroTag: 'polyOk',
                    backgroundColor: Pal.accent,
                    foregroundColor: Pal.onAccent,
                    onPressed: es.finishPolygon,
                    child: const Icon(Icons.check),
                  ),
                ],
              ),
            ),
          if (es.toolMenuOpen) ToolColumn(bottom: dockBottom + kDockH + 8),
          if (es.gradActive && es.gradEditor && !es.gradPresets)
            Positioned(
              left: 10,
              right: 10,
              bottom: dockBottom + kDockH + 8,
              child: const GradientEditorPanel(),
            ),
          Positioned(
            left: 10,
            right: 10,
            bottom: dockBottom,
            height: kDockH,
            child: BottomBar(pageContext: context),
          ),
          Positioned(
            left: 10,
            right: 10,
            top: topBarTop,
            height: kBarH,
            child: const TopBar(),
          ),
          if (es.menu != null) MenuLayer(top: topInset - 4, pageContext: context),
          if (es.busyMsg != null)
            Positioned.fill(
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: surfaceDeco(radius: 18),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Pal.accent),
                        ),
                        const SizedBox(width: 14),
                        Text(es.busyMsg!, style: lbl(15)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// Top bar
// ============================================================
class TopBar extends StatelessWidget {
  const TopBar({super.key});

  @override
  Widget build(BuildContext context) {
    final es = context.watch<EditorState>();
    context.watch<AppTheme>();
    const ids = ['sel', 'adj', 'fx', 'amp'];
    final idx = ids.indexOf(es.menu ?? '');

    Widget item(String id, Widget Function(Color c) icon) {
      final on = es.menu == id;
      final c = on ? Pal.accent : Pal.txt;
      return Expanded(
        child: Pressable(
          onTap: () => es.toggleMenu(id),
          child: Container(
            height: 44,
            alignment: Alignment.center,
            child: AnimatedScale(
              scale: on ? 1.14 : 1,
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              child: icon(c),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      decoration: surfaceDeco(radius: 22),
      child: LayoutBuilder(
        builder: (c, box) {
          const doneW = 84.0;
          final itemW = (box.maxWidth - doneW - 6) / 5;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeOutBack,
                left: doneW + 6 + (idx < 0 ? 0 : idx) * itemW,
                top: 7,
                width: itemW,
                height: 44,
                child: AnimatedOpacity(
                  opacity: idx < 0 ? 0 : 1,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Pal.tint(0.16),
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Pal.tint(0.5)),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  SizedBox(
                    width: doneW,
                    child: Center(
                      child: Pressable(
                        onTap: () async {
                          await es.saveProject();
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        child: Container(
                          width: 76,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Pal.accent,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Text('Done', style: lbl(15, color: Pal.onAccent)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  item('sel', (c) => Icon(Icons.highlight_alt, size: 23, color: c)),
                  item('adj', (c) => Icon(Icons.tune, size: 23, color: c)),
                  item(
                    'fx',
                    (c) => Text(
                      'fx',
                      style: TextStyle(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                        fontSize: 22,
                        color: c,
                      ),
                    ),
                  ),
                  item(
                    'amp',
                    (c) => Text('&', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w300, color: c)),
                  ),
                  Expanded(
                    child: Pressable(
                      onTap: es.undo,
                      onLongPress: es.redo,
                      child: Container(
                        height: 44,
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.undo,
                          size: 23,
                          color: es.canUndo ? Pal.txt : Pal.dim,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Item {
  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;
  _Item(this.icon, this.label, this.enabled, this.onTap);
}

class MenuLayer extends StatelessWidget {
  final double top;
  final BuildContext pageContext;
  const MenuLayer({super.key, required this.top, required this.pageContext});

  _Item _pd(EditorState es, IconData i, String l, List<Param> ps,
      Future<void> Function(List<double> v) run) {
    return _Item(i, l, true, () async {
      final v = await paramDialog(pageContext, l, ps);
      if (v != null) await run(v);
    });
  }

  List<_Item> _selItems(EditorState es) {
    final pc = pageContext;
    return [
      _Item(Icons.content_cut, 'Cut', true, es.selCut),
      _Item(Icons.content_copy, 'Copy', true, es.selCopy),
      _Item(Icons.copy_all, 'Copy Merged', true, es.selCopyMerged),
      _Item(Icons.content_paste, 'Paste', es.clipboard != null, es.selPaste),
      _Item(Icons.delete, 'Clear', true, es.selClear),
      _Item(Icons.select_all, 'Select All', true, es.selectAll),
      _Item(Icons.flip_to_front, 'Select Pixels', true, es.selectPixels),
      _Item(Icons.deselect, 'Deselect', es.hasSel, es.deselect),
      _Item(Icons.flip, 'Inverse', es.hasSel, es.inverse),
      _Item(Icons.blur_circular, 'Feather', es.hasSel, () async {
        final v = await paramDialog(pc, 'Feather', [const Param('Radius', 1, 100, 10)]);
        if (v != null) await es.feather(v[0]);
      }),
      _Item(Icons.transform, 'Transform', true, es.startTransform),
      _Item(Icons.brush, 'Refine Edge', es.hasSel, () async {
        final v = await paramDialog(pc, 'Refine Edge', [const Param('Smooth', 0.5, 20, 3), const Param('Expand / Contract', -10, 10, 0)]);
        if (v != null) await es.refineEdge(v[0], v[1]);
      }),
      _Item(Icons.near_me, es.ptrMode ? 'Hide Pointer' : 'Show Pointer', true, es.togglePointer),
      _Item(Icons.filter_center_focus, 'Extract', es.hasSel, es.extractToLayer),
    ];
  }

  List<_Item> _adjItems(EditorState es) {
    final pc = pageContext;
    _Item soon(IconData i, String l) => _Item(i, l, true, () => es.toast('$l: $comingSoon'));
    return [
      _Item(Icons.monochrome_photos, 'Black & White', true, () => es.applyMatrix(kMatGray)),
      _Item(Icons.color_lens, 'Saturation', true, () async {
        final v = await paramDialog(pc, 'Saturation', [const Param('Amount', 0, 2, 1)], es: es, matrixOf: (v) => matSaturation(v[0]));
        if (v != null) await es.applyMatrix(matSaturation(v[0]));
      }),
      _Item(Icons.auto_fix_high, 'Auto Fix', true, es.autoFix),
      _Item(Icons.brightness_6, 'Brightness/Contrast', true, () async {
        final v = await paramDialog(pc, 'Brightness/Contrast', [
          const Param('Brightness', -100, 100, 0),
          const Param('Contrast', -0.8, 0.8, 0),
        ], es: es, matrixOf: (v) => matBrightnessContrast(v[0], v[1]));
        if (v != null) await es.applyMatrix(matBrightnessContrast(v[0], v[1]));
      }),
      _Item(Icons.thermostat, 'Temperature', true, () async {
        final v = await paramDialog(pc, 'Temperature', [const Param('Warm / Cool', -1, 1, 0)], es: es, matrixOf: (v) => matTemperature(v[0]));
        if (v != null) await es.applyMatrix(matTemperature(v[0]));
      }),
      _pd(es, Icons.format_color_fill, 'Replace Color', const [Param('Source hue', 0, 360, 0), Param('Range', 10, 90, 40), Param('Hue shift', -180, 180, 60), Param('Saturation', -1, 1, 0)], (v) => es.replaceColor(v[0], v[1], v[2], v[3])),
      _pd(es, Icons.exposure, 'Shadows/Highlights', const [Param('Shadows', 0, 1, 0.5), Param('Highlights', 0, 1, 0.3)], (v) => es.shadowsHighlights(v[0], v[1])),
      _Item(Icons.balance, 'Color Balance', true, () async {
        final v = await paramDialog(pc, 'Color Balance', [
          const Param('Red', -100, 100, 0),
          const Param('Green', -100, 100, 0),
          const Param('Blue', -100, 100, 0),
        ], es: es, matrixOf: (v) => matColorBalance(v[0], v[1], v[2]));
        if (v != null) await es.applyMatrix(matColorBalance(v[0], v[1], v[2]));
      }),
      _Item(Icons.grain, 'Reduce Noise', true, () async {
        final v = await paramDialog(pc, 'Reduce Noise', [const Param('Strength', 0.5, 4, 1.2)], es: es, blurOf: (v) => v[0]);
        if (v != null) await es.applyBlur(v[0]);
      }),
      _Item(Icons.invert_colors, 'Invert', true, () => es.applyMatrix(kMatInvert)),
      _Item(Icons.bar_chart, 'Levels', true, () async {
        final v = await paramDialog(pc, 'Levels', [
          const Param('Black point', 0, 250, 0),
          const Param('White point', 5, 255, 255),
        ], es: es, matrixOf: (v) => matLevels(v[0], math.max(v[1], v[0] + 4)));
        if (v != null) await es.applyMatrix(matLevels(v[0], math.max(v[1], v[0] + 4)));
      }),
      _Item(Icons.show_chart, 'Curves', true, () => curvesDialog(pc, es)),
    ];
  }

  List<_Item> _fxItems(EditorState es, int tab) {
    final pc = pageContext;
    _Item soon(IconData i, String l) => _Item(i, l, true, () => es.toast('$l: $comingSoon'));
    switch (tab) {
      case 0:
        return [
          _Item(Icons.blur_on, 'Gaussian Blur', true, () async {
            final v = await paramDialog(pc, 'Gaussian Blur', [const Param('Radius', 1, 40, 8)], es: es, blurOf: (v) => v[0]);
            if (v != null) await es.applyBlur(v[0]);
          }),
          _Item(Icons.motion_photos_on, 'Directional Blur', true, () async {
            final v = await paramDialog(pc, 'Directional Blur', [
              const Param('Horizontal', 0, 40, 12),
              const Param('Vertical', 0, 40, 0),
            ]);
            if (v != null) await es.applyDirBlur(v[0], v[1]);
          }),
          _pd(es, Icons.details, 'Sharpen', const [Param('Amount', 0.2, 3, 1), Param('Radius', 0.5, 6, 1.5)], (v) => es.applySharpen(v[0], v[1])),
          _Item(Icons.layers, 'Drop Shadow', true, () async {
            final v = await paramDialog(pc, 'Drop Shadow', [
              const Param('Offset X', -80, 80, 16),
              const Param('Offset Y', -80, 80, 16),
              const Param('Blur', 0, 40, 10),
              const Param('Opacity', 0.1, 1, 0.6),
            ]);
            if (v != null) await es.applyShadow(v[0], v[1], v[2], v[3], Colors.black);
          }),
          _Item(Icons.flare, 'Glow', true, () async {
            final v = await paramDialog(pc, 'Glow', [
              const Param('Blur', 2, 60, 18),
              const Param('Opacity', 0.1, 1, 0.9),
            ]);
            if (v != null) await es.applyShadow(0, 0, v[0], v[1], es.color);
          }),
          _pd(es, Icons.border_style, 'Bevel', const [Param('Depth', 0.5, 5, 2), Param('Size', 1, 12, 3)], (v) => es.applyBevel(v[0], v[1])),
          _pd(es, Icons.border_all, 'Edges', const [Param('Strength', 0.5, 6, 2)], (v) => es.applyEdges(v[0])),
          _Item(Icons.invert_colors_on, 'Tint', true, () async {
            final v = await paramDialog(pc, 'Tint', [const Param('Amount', 0.05, 1, 0.4)]);
            if (v != null) await es.applyTint(v[0]);
          }),
          _pd(es, Icons.wb_incandescent, 'Lighting', const [Param('X', 0, 1, 0.5), Param('Y', 0, 1, 0.4), Param('Radius', 0.2, 1.5, 0.8), Param('Intensity', 0.1, 1, 0.8)], (v) => es.applyLighting(v[0], v[1], v[2], v[3])),
        ];
      case 1:
        return [
          _Item(Icons.gradient, 'Gradient Map', true, es.gradientMap),
          _pd(es, Icons.grain, 'Halftone Pattern', const [Param('Dot size', 4, 40, 10)], (v) => es.applyHalftone(v[0])),
          _Item(Icons.contrast, 'Threshold', true, () => es.applyMatrix(kMatThreshold)),
          _pd(es, Icons.blur_linear, 'Glass', const [Param('Size', 2, 30, 8), Param('Strength', 1, 20, 6)], (v) => es.applyGlass(v[0], v[1])),
          _pd(es, Icons.filter_b_and_w, 'Posterize Color', const [Param('Levels', 2, 10, 4)], (v) => es.applyPosterize(v[0])),
          _pd(es, Icons.print, 'Old Photocopy', const [Param('Threshold', 0.2, 0.8, 0.5), Param('Noise', 0, 1, 0.3)], (v) => es.applyPhotocopy(v[0], v[1])),
          _pd(es, Icons.waves, 'Stamp Pattern', const [Param('Frequency', 0.1, 1.5, 0.5), Param('Angle', 0, 180, 45)], (v) => es.applyStampPattern(v[0], v[1])),
          _Item(Icons.palette, 'Colorize', true, es.colorizeFx),
          _pd(es, Icons.water, 'Ripple', const [Param('Amplitude', 2, 60, 12), Param('Wavelength', 20, 300, 80)], (v) => es.applyRipple(v[0], v[1])),
        ];
      case 2:
        return [
          _pd(es, Icons.edit, 'Graphic Pen', const [Param('Spacing', 3, 14, 6)], (v) => es.applyGraphicPen(v[0])),
          _pd(es, Icons.draw, 'Chalk & Charcoal', const [Param('Grain', 0, 1, 0.5)], (v) => es.applyChalk(v[0])),
          _pd(es, Icons.create, 'Pencil', const [Param('Strength', 0.5, 5, 2)], (v) => es.applyPencil(v[0])),
          _pd(es, Icons.chat_bubble, 'Comic', const [Param('Levels', 3, 8, 4), Param('Outline', 0.2, 1, 0.5)], (v) => es.applyComic(v[0], v[1])),
          _pd(es, Icons.water_drop, 'Color Drops', const [Param('Count', 5, 80, 30), Param('Size', 0.2, 2, 1)], (v) => es.applyColorDrops(v[0], v[1])),
          _pd(es, Icons.gesture, 'Scratches', const [Param('Count', 10, 200, 60)], (v) => es.applyScratches(v[0])),
          _pd(es, Icons.brush, 'Watercolor', const [Param('Smooth', 1, 6, 3), Param('Levels', 3, 10, 6)], (v) => es.applyWatercolor(v[0], v[1])),
          _pd(es, Icons.format_paint, 'Acrylic Paint', const [Param('Block size', 3, 24, 8)], (v) => es.applyAcrylic(v[0])),
          _pd(es, Icons.content_cut, 'Shred', const [Param('Strip width', 4, 60, 16), Param('Amount', 4, 120, 30)], (v) => es.applyShred(v[0], v[1])),
        ];
      default:
        return [
          _Item(Icons.photo_filter, 'Old Sepia', true, () => es.applyMatrix(kMatSepia)),
          _Item(Icons.nights_stay, 'Sleepy Hollow', true, es.sleepyHollow),
          _Item(Icons.wb_sunny, 'Sunny Afternoon', true, () => es.applyMatrix(kMatSunny)),
          _Item(Icons.tv, 'TV Monitor', true, es.tvMonitor),
          _pd(es, Icons.grain, 'Grainy Night', const [Param('Grain', 0, 1, 0.5)], (v) => es.grainyNight(v[0])),
          _Item(Icons.nightlight, 'Moonlight', true, () => es.applyMatrix(kMatMoon)),
          _pd(es, Icons.hdr_on, 'HDR Look', const [Param('Amount', 0.3, 2, 1)], (v) => es.hdrLook(v[0])),
          _pd(es, Icons.light_mode, 'Soft Light', const [Param('Amount', 0.1, 1, 0.5)], (v) => es.softLightFx(v[0])),
          _pd(es, Icons.face, 'Soft Skin', const [Param('Smooth', 1, 8, 3)], (v) => es.softSkin(v[0])),
        ];
    }
  }

  List<_Item> _ampItems(EditorState es) {
    final pc = pageContext;
    _Item soon(IconData i, String l) => _Item(i, l, true, () => es.toast('$l: $comingSoon'));
    return [
      _Item(Icons.crop, 'Crop Image', true, es.startCrop),
      _Item(Icons.photo_size_select_large, 'Image Size', true, () async {
        final v = await paramDialog(pc, 'Image Size (width)', [
          Param('Width', 100, 3000, math.min(3000, es.docW).toDouble()),
        ]);
        if (v != null) {
          final nw = v[0].round();
          final nh = math.max(1, (nw * es.docH / es.docW).round());
          await es.resizeAll(nw, nh);
        }
      }),
      _Item(Icons.rotate_90_degrees_ccw, 'Rotate', true, () => rotateSheet(pc, es)),
      _Item(Icons.text_fields, 'Text', true, () => textDialog(pc, es)),
      _Item(Icons.open_with, 'Transform', true, es.startTransform),
      _pd(es, Icons.grid_on, 'Warp', const [Param('Bulge / Pinch', -1, 1, 0.5), Param('Twirl', -3, 3, 0), Param('Radius', 0.2, 1, 0.6), Param('X', 0, 1, 0.5), Param('Y', 0, 1, 0.5)], (v) => es.applyWarp(v[0], v[1], v[2], v[3], v[4])),
      _Item(Icons.format_color_fill, 'Fill & Stroke', true, es.fillSelection),
      _Item(Icons.gradient, 'Gradient', true, es.startGradient),
      _pd(es, Icons.blur_linear, 'Fade', const [Param('Angle', 0, 360, 90), Param('Start', 0, 0.95, 0.2), Param('End', 0.05, 1, 1)], (v) => es.applyFade(v[0], v[1], v[2])),
      _Item(Icons.flare, 'Lens Flare', true, () async {
        final v = await paramDialog(pc, 'Lens Flare', [
          const Param('X', 0, 1, 0.7),
          const Param('Y', 0, 1, 0.3),
          const Param('Size', 0.1, 1, 0.5),
        ]);
        if (v != null) await es.applyFlare(v[0], v[1], v[2]);
      }),
      _Item(Icons.photo_camera, 'Camera Fill', true, () async {
        final b = await pickBytes(ImageSource.camera);
        if (b != null) await es.cameraFill(b);
      }),
      _Item(Icons.save_alt, 'Save to Photos', true, es.exportToPhotos),
    ];
  }

  Widget _tile(EditorState es, _Item it, int idx) {
    final c = it.enabled ? Pal.txt : Pal.dim;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 260 + math.min(idx, 10) * 28),
      curve: Curves.easeOutCubic,
      builder: (c2, v, ch) =>
          Opacity(opacity: v, child: Transform.scale(scale: 0.9 + 0.1 * v, child: ch)),
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Pressable(
          haptic: it.enabled,
          onTap: it.enabled
              ? () {
                  es.closeMenu();
                  it.onTap();
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              color: Pal.fill,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                it.label == 'Select All'
                    ? toolIcon(Tool.marquee, 26, c)
                    : Icon(it.icon, size: 26, color: c),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    it.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: lbl(11.5, color: c),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final es = context.watch<EditorState>();
    context.watch<AppTheme>();
    List<_Item> items;
    Widget? header;
    switch (es.menu) {
      case 'sel':
        items = _selItems(es);
        break;
      case 'adj':
        items = _adjItems(es);
        break;
      case 'fx':
        items = _fxItems(es, es.fxTab);
        const tabs = ['Basic', 'Stylize', 'Artistic', 'Photo'];
        header = Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Pal.fill,
            borderRadius: BorderRadius.circular(16),
          ),
          child: LayoutBuilder(
            builder: (c, box) {
              final w = box.maxWidth / 4;
              return SizedBox(
                height: 38,
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 340),
                      curve: Curves.easeOutBack,
                      left: es.fxTab * w,
                      top: 0,
                      bottom: 0,
                      width: w,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Pal.accent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (int i = 0; i < tabs.length; i++)
                          SizedBox(
                            width: w,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                buzz();
                                es.setFxTab(i);
                              },
                              child: Center(
                                child: AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: lbl(13, color: es.fxTab == i ? Pal.onAccent : Pal.mut),
                                  child: Text(tabs[i]),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
        break;
      default:
        items = _ampItems(es);
    }

    final panel = Material(
      color: Pal.surface,
      elevation: 14,
      shadowColor: Colors.black87,
      borderRadius: BorderRadius.circular(26),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (header != null) header,
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: GridView.count(
                  key: ValueKey('${es.menu}-${es.fxTab}'),
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.25,
                  children: [for (int i = 0; i < items.length; i++) _tile(es, items[i], i)],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: top,
            bottom: 0,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: es.closeMenu,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            top: top + 4,
            left: 10,
            right: 10,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: 1),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              builder: (c, v, child) => Opacity(
                opacity: math.min(1.0, math.max(0.0, v)),
                child: Transform.translate(
                  offset: Offset(0, (1 - v) * -18),
                  child: Transform.scale(
                    scale: 0.95 + 0.05 * v,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
              ),
              child: panel,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Tool column (left flyout)
// ============================================================
// ============================================================
// Gradient tool UI (PS Touch style): dock, presets, color editor
// ============================================================
class _CheckerPainter extends CustomPainter {
  final double cell;
  const _CheckerPainter([this.cell = 8]);

  @override
  void paint(Canvas canvas, Size size) {
    final a = Paint()..color = const Color(0xFFE2E2E2);
    final b = Paint()..color = const Color(0xFF9C9C9C);
    canvas.drawRect(Offset.zero & size, a);
    for (double y = 0; y < size.height; y += cell) {
      for (double x = 0; x < size.width; x += cell) {
        if (((x / cell).floor() + (y / cell).floor()).isOdd) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), b);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter old) => old.cell != cell;
}

class _GradPreset {
  final Color a;
  final Color b;
  final bool radial;
  const _GradPreset(this.a, this.b, this.radial);
}

const List<_GradPreset> _gradPresets = [
  _GradPreset(Color(0xFF7B1FA2), Color(0xFF2A0A3A), false),
  _GradPreset(Color(0xFFFFFFFF), Color(0xFFD50000), true),
  _GradPreset(Color(0xFF8D4E4E), Color(0xFF3E2222), false),
  _GradPreset(Color(0xFFB36AD9), Color(0xFFE056F0), false),
  _GradPreset(Color(0xFFFF9A3C), Color(0xFFFF3D7F), false),
  _GradPreset(Color(0xFF30E3CA), Color(0xFF1B5CFF), false),
  _GradPreset(Color(0xFFFFFFFF), Color(0xFF000000), false),
  _GradPreset(Color(0xFFFFE08A), Color(0x00FFE08A), true),
];

Widget _gradSwatch(Color a, Color b, bool radial, double w, double h, {double radius = 12}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          const Positioned.fill(child: CustomPaint(painter: _CheckerPainter(6))),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: radial
                    ? RadialGradient(colors: [a, b])
                    : LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [a, b],
                      ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class GradientDock extends StatelessWidget {
  final BuildContext pageContext;
  const GradientDock({super.key, required this.pageContext});

  Widget _circle(IconData icon, VoidCallback onTap, {bool primary = false, Color? iconColor}) {
    return Pressable(
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: primary ? Pal.accent : Pal.fill,
          border: Border.all(color: primary ? Colors.transparent : Pal.line),
        ),
        child: Icon(icon, size: 24, color: iconColor ?? (primary ? Pal.onAccent : Pal.txt)),
      ),
    );
  }

  Widget _stop(EditorState es, int i) {
    final c = i == 0 ? es.gradC1 : es.gradC2;
    final sel = es.gradStop == i && es.gradEditor;
    return Pressable(
      onTap: () => es.gradSelectStop(i),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: sel ? 38 : 32,
        height: sel ? 38 : 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: sel ? Pal.accent : Colors.white, width: sel ? 3 : 2),
          boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 8)],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _CheckerPainter(6))),
            Positioned.fill(child: ColoredBox(color: c)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final es = context.watch<EditorState>();
    context.watch<AppTheme>();
    final cur = _gradSwatch(es.gradC1, es.gradC2, es.gradRadial, 56, 44, radius: 10);

    if (es.gradPresets) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: surfaceDeco(radius: 26),
        child: Row(
          children: [
            _circle(Icons.palette_outlined, es.gradTogglePresets),
            const SizedBox(width: 8),
            Expanded(
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Pressable(
                      onTap: es.gradTogglePresets,
                      child: Stack(
                        children: [
                          cur,
                          Positioned(
                            right: 4,
                            bottom: 4,
                            child: Container(
                              width: 18,
                              height: 18,
                              decoration: const BoxDecoration(
                                color: Color(0x99000000),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.chevron_right, size: 14, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  for (final p in _gradPresets)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Pressable(
                        onTap: () => es.gradPreset(p.a, p.b, p.radial),
                        child: _gradSwatch(p.a, p.b, p.radial, 56, 44, radius: 10),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            _circle(Icons.close, es.gradCancel, iconColor: const Color(0xFFFF6B6B)),
            const SizedBox(width: 8),
            _circle(Icons.check, es.gradApply, primary: true),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: surfaceDeco(radius: 26),
      child: Row(
        children: [
          _circle(Icons.apps, es.gradTogglePresets),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 62,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 14,
                    right: 14,
                    top: 8,
                    height: 26,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(9),
                      child: Stack(
                        children: [
                          const Positioned.fill(child: CustomPaint(painter: _CheckerPainter(6))),
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [es.gradC1, es.gradC2]),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(left: 0, top: 24, child: _stop(es, 0)),
                  Positioned(right: 0, top: 24, child: _stop(es, 1)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          PopupMenuButton<String>(
            color: Pal.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            onSelected: (v) {
              buzz();
              if (v == 'linear') {
                es.gradSetType(false);
              } else if (v == 'radial') {
                es.gradSetType(true);
              } else {
                es.gradReverse();
              }
            },
            itemBuilder: (c) => [
              PopupMenuItem<String>(
                value: 'linear',
                child: Row(children: [
                  Icon(Icons.gradient, color: es.gradRadial ? Pal.txt : Pal.accent),
                  const SizedBox(width: 12),
                  Text('Linear type', style: lbl(15)),
                ]),
              ),
              PopupMenuItem<String>(
                value: 'radial',
                child: Row(children: [
                  Icon(Icons.blur_circular, color: es.gradRadial ? Pal.accent : Pal.txt),
                  const SizedBox(width: 12),
                  Text('Radial type', style: lbl(15)),
                ]),
              ),
              PopupMenuItem<String>(
                value: 'reverse',
                child: Row(children: [
                  Icon(Icons.swap_horiz, color: Pal.txt),
                  const SizedBox(width: 12),
                  Text('Reverse spots', style: lbl(15)),
                ]),
              ),
            ],
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              child: Icon(Icons.menu_open, size: 26, color: Pal.txt),
            ),
          ),
          _circle(Icons.close, es.gradCancel, iconColor: const Color(0xFFFF6B6B)),
          const SizedBox(width: 8),
          _circle(Icons.check, es.gradApply, primary: true),
        ],
      ),
    );
  }
}

class _GSlider extends StatelessWidget {
  final String label;
  final String text;
  final double value;
  final double min;
  final double max;
  final List<Color> track;
  final bool checker;
  final ValueChanged<double> onChanged;
  const _GSlider({
    required this.label,
    required this.text,
    required this.value,
    required this.min,
    required this.max,
    required this.track,
    required this.onChanged,
    this.checker = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(label, style: lbl(11.5, color: Pal.mut)),
                ),
                SizedBox(
                  height: 26,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: Stack(
                              children: [
                                if (checker)
                                  const Positioned.fill(
                                    child: CustomPaint(painter: _CheckerPainter(5)),
                                  ),
                                Positioned.fill(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: track),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 0.01,
                          activeTrackColor: Colors.transparent,
                          inactiveTrackColor: Colors.transparent,
                          thumbColor: Colors.white,
                          overlayShape: SliderComponentShape.noOverlay,
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                        ),
                        child: Slider(
                          value: math.max(min, math.min(max, value)),
                          min: min,
                          max: max,
                          onChanged: onChanged,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 58,
            height: 32,
            alignment: Alignment.center,
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              color: Pal.fill,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Pal.line),
            ),
            child: Text(text, style: lbl(13)),
          ),
        ],
      ),
    );
  }
}

class GradientEditorPanel extends StatelessWidget {
  const GradientEditorPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final es = context.watch<EditorState>();
    context.watch<AppTheme>();
    final c = es.gradColor;
    final hsv = HSVColor.fromColor(c);
    final al = c.a;
    final hsb = es.gradHsb;
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();

    Color fromHsv(double h, double s, double v) =>
        HSVColor.fromAHSV(al, h, s, v).toColor();
    Color fromRgb(int rr, int gg, int bb) =>
        Color.fromARGB((al * 255).round(), rr, gg, bb);

    final rows = <Widget>[];
    if (hsb) {
      rows.addAll([
        _GSlider(
          label: 'Hue',
          text: '${hsv.hue.round()}°',
          value: hsv.hue,
          min: 0,
          max: 359.9,
          track: [
            for (int i = 0; i <= 6; i++) HSVColor.fromAHSV(1, i * 60.0, 0.85, 0.95).toColor(),
          ],
          onChanged: (v) => es.gradSetColor(fromHsv(v, hsv.saturation, hsv.value)),
        ),
        _GSlider(
          label: 'Saturation',
          text: '${(hsv.saturation * 100).round()}%',
          value: hsv.saturation,
          min: 0,
          max: 1,
          track: [fromHsv(hsv.hue, 0, hsv.value).withValues(alpha: 1), fromHsv(hsv.hue, 1, hsv.value).withValues(alpha: 1)],
          onChanged: (v) => es.gradSetColor(fromHsv(hsv.hue, v, hsv.value)),
        ),
        _GSlider(
          label: 'Brightness',
          text: '${(hsv.value * 100).round()}%',
          value: hsv.value,
          min: 0,
          max: 1,
          track: [Colors.black, fromHsv(hsv.hue, hsv.saturation, 1).withValues(alpha: 1)],
          onChanged: (v) => es.gradSetColor(fromHsv(hsv.hue, hsv.saturation, v)),
        ),
      ]);
    } else {
      rows.addAll([
        _GSlider(
          label: 'Red',
          text: '$r',
          value: r.toDouble(),
          min: 0,
          max: 255,
          track: [Color.fromARGB(255, 0, g, b), Color.fromARGB(255, 255, g, b)],
          onChanged: (v) => es.gradSetColor(fromRgb(v.round(), g, b)),
        ),
        _GSlider(
          label: 'Green',
          text: '$g',
          value: g.toDouble(),
          min: 0,
          max: 255,
          track: [Color.fromARGB(255, r, 0, b), Color.fromARGB(255, r, 255, b)],
          onChanged: (v) => es.gradSetColor(fromRgb(r, v.round(), b)),
        ),
        _GSlider(
          label: 'Blue',
          text: '$b',
          value: b.toDouble(),
          min: 0,
          max: 255,
          track: [Color.fromARGB(255, r, g, 0), Color.fromARGB(255, r, g, 255)],
          onChanged: (v) => es.gradSetColor(fromRgb(r, g, v.round())),
        ),
      ]);
    }
    rows.add(
      _GSlider(
        label: 'Opacity',
        text: '${(al * 100).round()}%',
        value: al,
        min: 0,
        max: 1,
        checker: true,
        track: [c.withValues(alpha: 0), c.withValues(alpha: 1)],
        onChanged: (v) => es.gradSetColor(c.withValues(alpha: v)),
      ),
    );

    Widget modeBtn(String t, bool on) => Pressable(
          onTap: () => es.gradSetHsb(t == 'HSB'),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 56,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? Pal.accent : Pal.fill,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(t, style: lbl(12.5, color: on ? Pal.onAccent : Pal.mut)),
          ),
        );

    Widget swatch(Color col, {bool checker = false, VoidCallback? onTap, double w = 52}) => Pressable(
          onTap: onTap,
          child: Container(
            width: w,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Pal.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                if (checker) const Positioned.fill(child: CustomPaint(painter: _CheckerPainter(6))),
                Positioned.fill(child: ColoredBox(color: col)),
              ],
            ),
          ),
        );

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: surfaceDeco(radius: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text(es.gradStop == 0 ? 'Start color' : 'End color', style: lbl(14)),
              const Spacer(),
              modeBtn('HSB', hsb),
              const SizedBox(width: 6),
              modeBtn('RGB', !hsb),
            ],
          ),
          const SizedBox(height: 8),
          ...rows,
          const SizedBox(height: 4),
          Row(
            children: [
              swatch(c, checker: true, w: 78),
              const SizedBox(width: 10),
              swatch(Colors.black, onTap: () => es.gradSetColor(Colors.black.withValues(alpha: al))),
              const SizedBox(width: 10),
              swatch(Colors.white, onTap: () => es.gradSetColor(Colors.white.withValues(alpha: al))),
              const Spacer(),
              Pressable(
                onTap: es.gradTogglePick,
                child: Container(
                  width: 46,
                  height: 38,
                  decoration: BoxDecoration(
                    color: es.gradPick ? Pal.tint(0.25) : Pal.fill,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: es.gradPick ? Pal.accent : Pal.line),
                  ),
                  child: Icon(Icons.colorize, size: 22, color: es.gradPick ? Pal.accent : Pal.txt),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Tool column (left flyout)
// ============================================================
class ToolColumn extends StatelessWidget {
  final double bottom;
  const ToolColumn({super.key, required this.bottom});

  @override
  Widget build(BuildContext context) {
    final es = context.watch<EditorState>();
    context.watch<AppTheme>();
    const tile = 54.0;
    const gap = 8.0;
    const pad = 8.0;
    final n = groups.length;
    final g = es.openGroup;

    final children = <Widget>[
      Positioned(
        left: 10,
        bottom: bottom,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: 0, end: 1),
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          builder: (c, v, ch) => Opacity(
            opacity: math.min(1.0, math.max(0.0, v)),
            child: Transform.translate(offset: Offset(0, (1 - v) * 24), child: ch),
          ),
          child: Container(
            padding: const EdgeInsets.all(pad),
            decoration: surfaceDeco(radius: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < n; i++)
                  Padding(
                    padding: EdgeInsets.only(bottom: i == n - 1 ? 0 : gap),
                    child: Pressable(
                      onTap: () => es.tapGroup(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 240),
                        curve: Curves.easeOut,
                        width: tile,
                        height: tile,
                        decoration: BoxDecoration(
                          color: g == i ? Pal.accent : Pal.fill,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Stack(
                          children: [
                            Center(
                              child: toolIcon(
                                groups[i][es.groupIdx[i]],
                                24,
                                g == i ? Pal.onAccent : Pal.txt,
                              ),
                            ),
                            if (groups[i].length > 1)
                              Positioned(
                                right: 7,
                                top: 7,
                                child: Container(
                                  width: 5,
                                  height: 5,
                                  decoration: BoxDecoration(
                                    color: g == i ? Pal.onAccent : Pal.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ];

    if (g != null) {
      final rowBottom = bottom + pad + (n - 1 - g) * (tile + gap);
      children.add(
        Positioned(
          left: 10 + pad + tile + pad + 6,
          bottom: rowBottom - 5,
          child: TweenAnimationBuilder<double>(
            key: ValueKey('row$g'),
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            builder: (c, v, ch) => Opacity(
              opacity: math.min(1.0, math.max(0.0, v)),
              child: Transform.translate(offset: Offset(-24 * (1 - v), 0), child: ch),
            ),
            child: Container(
              padding: const EdgeInsets.all(7),
              decoration: surfaceDeco(radius: 24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int j = 0; j < groups[g].length; j++)
                    Padding(
                      padding: EdgeInsets.only(right: j == groups[g].length - 1 ? 0 : 6),
                      child: Pressable(
                        onTap: () => es.pickTool(g, j),
                        child: Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: es.tool == groups[g][j] ? Pal.tint(0.22) : Pal.fill,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: es.tool == groups[g][j] ? Pal.accent : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: toolIcon(
                              groups[g][j],
                              23,
                              es.tool == groups[g][j] ? Pal.accent : Pal.txt,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
      children.add(
        Positioned(
          left: 10 + pad + tile + pad + 10,
          bottom: rowBottom + tile + 14,
          child: TweenAnimationBuilder<double>(
            key: ValueKey('tip${es.tool.index}'),
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 220),
            builder: (c, v, ch) => Opacity(opacity: v, child: ch),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Pal.txt,
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 14)],
              ),
              child: Text(toolName(es.tool), style: lbl(12.5, color: Pal.bg)),
            ),
          ),
        ),
      );
    }

    return Positioned.fill(child: Stack(children: children));
  }
}

// ============================================================
// Pointer mode controls (pad + click button)
// ============================================================
class PointerControls extends StatefulWidget {
  final double bottom;
  final double rightInset;
  const PointerControls({super.key, required this.bottom, this.rightInset = 22});

  @override
  State<PointerControls> createState() => _PointerControlsState();
}

class _PointerControlsState extends State<PointerControls> {
  Offset _knob = Offset.zero;
  bool _drag = false;
  bool _press = false;

  @override
  Widget build(BuildContext context) {
    final es = context.read<EditorState>();
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned(
            right: widget.rightInset,
            bottom: widget.bottom,
            child: GestureDetector(
              onPanStart: (_) => setState(() => _drag = true),
              onPanUpdate: (d) {
                es.ptrMove(d.delta);
                setState(() {
                  _knob = Offset(
                    math.max(-14.0, math.min(14.0, _knob.dx + d.delta.dx * 0.7)),
                    math.max(-14.0, math.min(14.0, _knob.dy + d.delta.dy * 0.7)),
                  );
                });
              },
              onPanEnd: (_) => setState(() {
                _drag = false;
                _knob = Offset.zero;
              }),
              onPanCancel: () => setState(() {
                _drag = false;
                _knob = Offset.zero;
              }),
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Pal.surface,
                  border: Border.all(color: Pal.line),
                  boxShadow: const [
                    BoxShadow(color: Color(0x59000000), blurRadius: 22, offset: Offset(0, 8)),
                  ],
                ),
                child: Center(
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: _drag ? 0 : 320),
                    curve: Curves.easeOutBack,
                    transform: Matrix4.translationValues(_knob.dx, _knob.dy, 0),
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Pal.accent,
                      boxShadow: [
                        BoxShadow(color: Pal.tint(0.45), blurRadius: 16, spreadRadius: 1),
                      ],
                    ),
                    child: Icon(Icons.near_me, size: 28, color: Pal.onAccent),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 22,
            bottom: widget.bottom + 8,
            child: Listener(
              onPointerDown: (_) {
                buzz();
                setState(() => _press = true);
                es.ptrPress();
              },
              onPointerUp: (_) {
                setState(() => _press = false);
                es.ptrRelease();
              },
              onPointerCancel: (_) {
                setState(() => _press = false);
                es.ptrRelease();
              },
              child: AnimatedScale(
                scale: _press ? 0.88 : 1,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _press ? Pal.tint(0.35) : Pal.surface,
                    border: Border.all(color: _press ? Pal.accent : Pal.line, width: _press ? 2 : 1),
                    boxShadow: const [
                      BoxShadow(color: Color(0x59000000), blurRadius: 22, offset: Offset(0, 8)),
                    ],
                  ),
                  child: Icon(Icons.touch_app, size: 32, color: _press ? Pal.accent : Pal.txt),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Bottom dock (tool options)
// ============================================================
class _Opt extends StatelessWidget {
  final Widget icon;
  final String label;
  final String? top;
  final bool active;
  final VoidCallback onTap;
  const _Opt({
    required this.icon,
    required this.label,
    required this.onTap,
    this.top,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = active ? Pal.accent : Pal.mut;
    return Pressable(
      onTap: onTap,
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 14,
              child: top == null
                  ? null
                  : Text(top!, style: lbl(11, color: active ? Pal.accent : Pal.txt)),
            ),
            const SizedBox(height: 2),
            icon,
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w500, color: c),
            ),
          ],
        ),
      ),
    );
  }
}

class BottomBar extends StatelessWidget {
  final BuildContext pageContext;
  const BottomBar({super.key, required this.pageContext});

  Future<void> _modeSheet(EditorState es) {
    return showModalBottomSheet<void>(
      context: pageContext,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            for (final e in const [
              [SelMode.replace, 'New selection'],
              [SelMode.add, 'Add to selection'],
              [SelMode.subtract, 'Subtract from selection'],
              [SelMode.intersect, 'Intersect with selection'],
            ])
              ListTile(
                title: Text(e[1] as String, style: lbl(16)),
                trailing: es.selMode == e[0] ? Icon(Icons.check, color: Pal.accent) : null,
                onTap: () {
                  es.setSelMode(e[0] as SelMode);
                  Navigator.pop(c);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  IconData _modeIcon(SelMode m) {
    switch (m) {
      case SelMode.replace:
        return Icons.crop_square;
      case SelMode.add:
        return Icons.add_box_outlined;
      case SelMode.subtract:
        return Icons.indeterminate_check_box_outlined;
      case SelMode.intersect:
        return Icons.filter_none;
    }
  }

  List<Widget> _options(EditorState es) {
    const sz = 22.0;
    final grey = Pal.mut;
    Widget mode() => _Opt(
          icon: Icon(_modeIcon(es.selMode), size: sz, color: grey),
          label: 'Mode',
          onTap: () => _modeSheet(es),
        );
    Widget aa() => _Opt(
          icon: Icon(es.antialias ? Icons.check_box : Icons.check_box_outline_blank,
              size: sz, color: es.antialias ? Pal.accent : grey),
          label: 'Antialias',
          onTap: es.toggleAntialias,
        );
    Widget sizeOpt() => _Opt(
          icon: Icon(Icons.radio_button_checked, size: sz, color: grey),
          label: 'Size',
          top: es.brushSize.round().toString(),
          onTap: () => sliderSheet(pageContext, 'Size', 1, 300, () => es.brushSize, es.setSize),
        );
    Widget opacityOpt() => _Opt(
          icon: Icon(Icons.opacity, size: sz, color: grey),
          label: 'Opacity',
          top: '${(es.brushOpacity * 100).round()}',
          onTap: () => sliderSheet(pageContext, 'Opacity', 5, 100, () => es.brushOpacity * 100,
              (v) => es.setBrushOpacity(v / 100)),
        );
    Widget hardOpt() => _Opt(
          icon: Icon(Icons.blur_on, size: sz, color: grey),
          label: 'Hardness',
          top: '${(es.brushHardness * 100).round()}',
          onTap: () => sliderSheet(pageContext, 'Hardness', 0, 100, () => es.brushHardness * 100,
              (v) => es.setHardness(v / 100)),
        );
    Widget tolOpt() => _Opt(
          icon: Icon(Icons.linear_scale, size: sz, color: grey),
          label: 'Tolerance',
          top: es.tolerance.round().toString(),
          onTap: () =>
              sliderSheet(pageContext, 'Tolerance', 0, 255, () => es.tolerance, es.setTolerance),
        );

    switch (es.tool) {
      case Tool.brush:
      case Tool.fxBrush:
      case Tool.spray:
      case Tool.eraser:
        return [
          if (es.tool != Tool.eraser && es.tool != Tool.fxBrush)
            _Opt(
              icon: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: es.color,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6)],
                ),
              ),
              label: 'Color',
              onTap: () => colorSheet(pageContext, es),
            ),
          sizeOpt(),
          if (es.tool != Tool.eraser) opacityOpt(),
          hardOpt(),
        ];
      case Tool.stamp:
        return [
          _Opt(
            icon: Icon(Icons.my_location, size: sz, color: es.stampSetting ? Pal.accent : grey),
            label: es.stampSetting ? 'Tap source' : 'Set source',
            active: es.stampSetting,
            onTap: es.toggleStampSetting,
          ),
          sizeOpt(),
          opacityOpt(),
          hardOpt(),
        ];
      case Tool.wand:
        return [
          mode(),
          tolOpt(),
          _Opt(
            icon: Icon(es.contiguous ? Icons.check_box : Icons.check_box_outline_blank,
                size: sz, color: es.contiguous ? Pal.accent : grey),
            label: 'Continuous',
            onTap: es.toggleContiguous,
          ),
        ];
      case Tool.colorSelect:
      case Tool.smartSel:
        return [mode(), tolOpt()];
      case Tool.selBrush:
        return [mode(), sizeOpt()];
      case Tool.marquee:
        return [
          mode(),
          _Opt(
            icon: Icon(Icons.rounded_corner, size: sz, color: grey),
            label: 'Corners',
            top: es.corners.round().toString(),
            onTap: () => sliderSheet(pageContext, 'Corners', 0, 300, () => es.corners, es.setCorners),
          ),
          aa(),
        ];
      case Tool.ellipse:
      case Tool.lasso:
      case Tool.polygon:
        return [mode(), aa()];
    }
  }

  Widget _sideBtn(Widget child, VoidCallback onTap, {Color? bg, Color? border}) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: bg ?? Pal.fill,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(color: border ?? Pal.line),
        ),
        child: Center(child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final es = context.watch<EditorState>();
    context.watch<AppTheme>();
    const sz = 22.0;
    final grey = Pal.mut;

    if (es.gradActive) return GradientDock(pageContext: pageContext);

    Widget bar(Widget left, Widget mid, Widget right) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: surfaceDeco(radius: 26),
          child: Row(children: [left, const SizedBox(width: 4), Expanded(child: mid), const SizedBox(width: 4), right]),
        );

    if (es.xfActive) {
      return bar(
        _sideBtn(const Icon(Icons.close, size: 26, color: Color(0xFFFF6B6B)), es.xfCancel),
        Row(children: [
          Expanded(
            child: _Opt(
              icon: Icon(Icons.flip, size: sz, color: grey),
              label: 'Flip H',
              onTap: es.xfFlipH,
            ),
          ),
          Expanded(
            child: _Opt(
              icon: Icon(Icons.swap_vert, size: sz, color: grey),
              label: 'Flip V',
              onTap: es.xfFlipV,
            ),
          ),
          Expanded(
            child: _Opt(
              icon: Icon(Icons.rotate_90_degrees_cw, size: sz, color: grey),
              label: 'Rotate 90',
              onTap: es.xfRotate90,
            ),
          ),
        ]),
        _sideBtn(Icon(Icons.check, size: 28, color: Pal.onAccent), es.xfApply, bg: Pal.accent, border: Colors.transparent),
      );
    }

    if (es.cropActive) {
      return bar(
        _sideBtn(const Icon(Icons.close, size: 26, color: Color(0xFFFF6B6B)), es.cropCancel),
        Center(child: Text('Drag the handles to crop', style: lbl(13.5, color: Pal.mut))),
        _sideBtn(Icon(Icons.check, size: 28, color: Pal.onAccent), es.cropApply, bg: Pal.accent, border: Colors.transparent),
      );
    }

    return bar(
      _sideBtn(
        toolIcon(es.tool, 26, es.toolMenuOpen ? Pal.accent : Pal.txt),
        es.toggleToolMenu,
        bg: Pal.tint(0.2),
        border: Pal.tint(es.toolMenuOpen ? 0.9 : 0.5),
      ),
      Row(children: [for (final o in _options(es)) Expanded(child: o)]),
      Stack(
        clipBehavior: Clip.none,
        children: [
          _sideBtn(
            Icon(Icons.layers, size: 26, color: es.layersOpen ? Pal.accent : Pal.txt),
            es.toggleLayers,
            border: es.layersOpen ? Pal.accent : null,
          ),
          Positioned(
            right: 5,
            top: 5,
            child: Icon(Icons.add, size: 14, color: es.layersOpen ? Pal.accent : Pal.txt),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// Layers panel (right)
// ============================================================
class LayersPanel extends StatelessWidget {
  final BuildContext pageContext;
  const LayersPanel({super.key, required this.pageContext});

  Future<void> _layerMenu(EditorState es) async {
    final act = await showModalBottomSheet<String>(
      context: pageContext,
      backgroundColor: kMenuBg,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final e in <List<Object>>[
              ['props', 'Layer Properties', Icons.tune],
              if (es.current?.textMeta != null) ['text', 'Edit Text', Icons.text_fields],
              ['dup', 'Duplicate Layer', Icons.copy],
              ['merge', 'Merge Down', Icons.merge_type],
              ['flat', 'Flatten Image', Icons.layers_clear],
              ['photo', 'Add Photo as Layer', Icons.add_photo_alternate],
              ['maskr', 'Add Mask (Reveal All)', Icons.add_circle_outline],
              ['maskh', 'Add Mask (Hide All)', Icons.remove_circle_outline],
              if (es.hasSel) ['masks', 'Mask From Selection', Icons.crop_free],
              if (es.current?.mask != null) ['maski', 'Invert Mask', Icons.invert_colors],
              if (es.current?.mask != null) ['maska', 'Apply Mask', Icons.done_all],
              if (es.current?.mask != null) ['maskd', 'Delete Mask', Icons.highlight_off],
              ['del', 'Delete Layer', Icons.delete_outline],
            ])
              ListTile(
                leading: Icon(e[2] as IconData),
                title: Text(e[1] as String, style: lbl(18)),
                onTap: () => Navigator.pop(c, e[0] as String),
              ),
          ],
          ),
        ),
      ),
    );
    if (act == null) return;
    if (act == 'text') {
      if (pageContext.mounted) await textDialog(pageContext, es, edit: true);
    } else if (act == 'flat') {
      await es.flattenImage();
    } else if (act.startsWith('mask')) {
      await es.maskAction(act);
    } else if (act == 'dup') {
      es.duplicateLayer();
    } else if (act == 'merge') {
      await es.mergeDown();
    } else if (act == 'del') {
      es.deleteLayer(es.selected);
    } else if (act == 'photo') {
      final b = await pickBytes(ImageSource.gallery);
      if (b != null) await es.addImageLayer(b);
    } else if (act == 'props') {
      if (pageContext.mounted) await _props(es);
    }
  }

  Future<void> _props(EditorState es) {
    final ctrl = TextEditingController(text: es.current?.name ?? '');
    return showDialog<void>(
      context: pageContext,
      builder: (dctx) => StatefulBuilder(
        builder: (dctx, setS) {
          final l = es.current;
          if (l == null) return const SizedBox();
          return AlertDialog(
            backgroundColor: kMenuBg,
            title: Text('Layer Properties', style: lbl(20)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  onChanged: (v) => es.setLayerName(es.selected, v),
                ),
                const SizedBox(height: 12),
                Text('Opacity: ${(l.opacity * 100).round()}%', style: lbl(14)),
                Slider(
                  value: l.opacity,
                  onChangeStart: (_) => es.beginLayerEdit(),
                  onChanged: (v) {
                    es.setLayerOpacity(es.selected, v);
                    setS(() {});
                  },
                ),
                DropdownButton<BlendMode>(
                  isExpanded: true,
                  value: l.blendMode,
                  items: const [
                    DropdownMenuItem(value: BlendMode.srcOver, child: Text('Normal')),
                    DropdownMenuItem(value: BlendMode.multiply, child: Text('Multiply')),
                    DropdownMenuItem(value: BlendMode.screen, child: Text('Screen')),
                    DropdownMenuItem(value: BlendMode.overlay, child: Text('Overlay')),
                    DropdownMenuItem(value: BlendMode.darken, child: Text('Darken')),
                    DropdownMenuItem(value: BlendMode.lighten, child: Text('Lighten')),
                    DropdownMenuItem(value: BlendMode.colorDodge, child: Text('Color Dodge')),
                    DropdownMenuItem(value: BlendMode.colorBurn, child: Text('Color Burn')),
                    DropdownMenuItem(value: BlendMode.hardLight, child: Text('Hard Light')),
                    DropdownMenuItem(value: BlendMode.softLight, child: Text('Soft Light')),
                    DropdownMenuItem(value: BlendMode.difference, child: Text('Difference')),
                    DropdownMenuItem(value: BlendMode.exclusion, child: Text('Exclusion')),
                  ],
                  onChanged: (m) {
                    if (m != null) {
                      es.setBlend(es.selected, m);
                      setS(() {});
                    }
                  },
                ),
              ],
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(dctx), child: const Text('OK')),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final es = context.watch<EditorState>();
    context.watch<AppTheme>();
    final n = es.layers.length;
    return Container(
      decoration: surfaceDeco(radius: 22),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
              itemCount: n,
              onReorder: (oldD, newD) {
                if (newD > oldD) newD -= 1;
                es.reorder(n - 1 - oldD, n - 1 - newD);
              },
              itemBuilder: (c, d) {
                final i = n - 1 - d;
                final l = es.layers[i];
                final sel = i == es.selected;
                return Padding(
                  key: ValueKey(l.id),
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onTap: () {
                      buzz();
                      es.selectLayer(i);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: sel ? Pal.tint(0.16) : Pal.fill,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: sel ? Pal.accent : Colors.transparent,
                          width: 1.4,
                        ),
                        boxShadow: sel
                            ? [BoxShadow(color: Pal.tint(0.28), blurRadius: 12)]
                            : const [],
                      ),
                      child: Column(
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      color: Pal.surface2,
                                      child: RawImage(image: l.image, fit: BoxFit.contain),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 3,
                                  top: 3,
                                  child: GestureDetector(
                                    onTap: () => es.toggleVisible(i),
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: const Color(0x99000000),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: l.visible ? Colors.white70 : Colors.white24,
                                        ),
                                      ),
                                      child: Icon(
                                        l.visible ? Icons.visibility : Icons.visibility_off,
                                        size: 11,
                                        color: l.visible ? Colors.white : Colors.white54,
                                      ),
                                    ),
                                  ),
                                ),
                                if (l.mask != null)
                                  Positioned(
                                    right: 3,
                                    bottom: 3,
                                    child: GestureDetector(
                                      onTap: () => es.maskBadgeTap(i),
                                      child: Container(
                                        width: 22,
                                        height: 22,
                                        decoration: BoxDecoration(
                                          color: Colors.black,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: (es.editMask && i == es.selected)
                                                ? Pal.accent
                                                : Colors.white54,
                                            width: 1.6,
                                          ),
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: ColorFiltered(
                                          colorFilter: const ColorFilter.mode(
                                              Colors.white, BlendMode.srcIn),
                                          child: RawImage(image: l.mask!, fit: BoxFit.contain),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            l.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 9, color: Pal.mut),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            height: 48,
            decoration: BoxDecoration(border: Border(top: BorderSide(color: Pal.line))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                Pressable(
                  onTap: () => _layerMenu(es),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Pal.fill,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.tune, size: 18, color: Pal.txt),
                  ),
                ),
                Pressable(
                  onTap: () => showAddLayerDialog(pageContext, es),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Pal.accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.add, size: 21, color: Pal.onAccent),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// App
// ============================================================
class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppTheme>(
      builder: (context, theme, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'PixelStudio',
        theme: buildTheme(),
        home: const GalleryPage(),
      ),
    );
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final appTheme = AppTheme();
  await appTheme.load();
  final store = ProjectStore()..load();
  final es = EditorState()..store = store;
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppTheme>.value(value: appTheme),
        ChangeNotifierProvider<ProjectStore>.value(value: store),
        ChangeNotifierProvider<EditorState>.value(value: es),
      ],
      child: const App(),
    ),
  );
}
