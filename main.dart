import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';


class DocLayer {
  final int id;
  String name;
  ui.Image image;
  double opacity;
  bool visible;
  BlendMode blendMode;

  DocLayer({
    required this.id,
    required this.name,
    required this.image,
    this.opacity = 1,
    this.visible = true,
    this.blendMode = BlendMode.srcOver,
  });

  DocLayer copy() => DocLayer(
        id: id,
        name: name,
        image: image,
        opacity: opacity,
        visible: visible,
        blendMode: blendMode,
      );
}



Future<Uint8List?> pickImageBytes() async {
  final x = await ImagePicker().pickImage(source: ImageSource.gallery);
  if (x == null) return null;
  return x.readAsBytes();
}




enum Tool { brush, eraser }

class _Snap {
  final List<DocLayer> layers;
  final int selected;
  _Snap(this.layers, this.selected);
}

class EditorState extends ChangeNotifier {
  static const int maxSide = 2048;
  static const int maxUndo = 20;

  // Document
  int docW = 1080;
  int docH = 1350;
  final List<DocLayer> layers = [];
  int selected = 0;
  int _nextId = 1;

  // Tools
  Tool tool = Tool.brush;
  Color color = Colors.black;
  double brushSize = 24;
  double brushOpacity = 1;

  // Current stroke (document coordinates)
  List<Offset> stroke = [];
  bool _busy = false;

  // History
  final List<_Snap> _undo = [];
  final List<_Snap> _redo = [];
  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  // View
  double scale = 1;
  Offset offset = Offset.zero;
  Size viewport = Size.zero;
  bool _fitPending = true;

  DocLayer? get current => layers.isEmpty ? null : layers[selected];

  // ---------- helpers ----------
  Future<ui.Image> _render(int w, int h, void Function(Canvas c) draw) async {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec, Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()));
    draw(c);
    final pic = rec.endRecording();
    final img = await pic.toImage(w, h);
    pic.dispose();
    return img;
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }

  _Snap _snap() => _Snap(layers.map((e) => e.copy()).toList(), selected);

  void _pushUndo() {
    _undo.add(_snap());
    if (_undo.length > maxUndo) _undo.removeAt(0);
    _redo.clear();
  }

  void _restore(_Snap s) {
    layers
      ..clear()
      ..addAll(s.layers.map((e) => e.copy()));
    selected = math.max(0, math.min(s.selected, layers.length - 1));
    stroke = [];
  }

  // ---------- project ----------
  Future<void> init() => newProject(1080, 1350);

  Future<void> newProject(int w, int h) async {
    docW = w;
    docH = h;
    final bg = await _render(w, h, (c) {
      c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          Paint()..color = Colors.white);
    });
    _reset(DocLayer(id: _nextId++, name: 'الخلفية', image: bg));
  }

  Future<void> openImageAsProject(Uint8List bytes) async {
    final src = await _decode(bytes);
    var w = src.width.toDouble();
    var h = src.height.toDouble();
    final m = math.max(w, h);
    if (m > maxSide) {
      final k = maxSide / m;
      w = (w * k).roundToDouble();
      h = (h * k).roundToDouble();
    }
    docW = w.round();
    docH = h.round();
    final img = await _render(docW, docH, (c) {
      c.drawImageRect(
        src,
        Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
        Rect.fromLTWH(0, 0, docW.toDouble(), docH.toDouble()),
        Paint()..filterQuality = FilterQuality.high,
      );
    });
    src.dispose();
    _reset(DocLayer(id: _nextId++, name: 'الصورة', image: img));
  }

  void _reset(DocLayer first) {
    layers
      ..clear()
      ..add(first);
    selected = 0;
    _undo.clear();
    _redo.clear();
    stroke = [];
    _fitPending = true;
    _fit();
    notifyListeners();
  }

  // ---------- layers ----------
  Future<void> addLayer() async {
    final img = await _render(docW, docH, (c) {});
    _pushUndo();
    layers.insert(selected + 1,
        DocLayer(id: _nextId++, name: 'طبقة ${_nextId - 1}', image: img));
    selected += 1;
    notifyListeners();
  }

  Future<void> addImageLayer(Uint8List bytes) async {
    final src = await _decode(bytes);
    final k = math.min(
        1.0, math.min(docW / src.width, docH / src.height));
    final w = src.width * k;
    final h = src.height * k;
    final dst = Rect.fromLTWH((docW - w) / 2, (docH - h) / 2, w, h);
    final img = await _render(docW, docH, (c) {
      c.drawImageRect(
        src,
        Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
        dst,
        Paint()..filterQuality = FilterQuality.high,
      );
    });
    src.dispose();
    _pushUndo();
    layers.insert(selected + 1,
        DocLayer(id: _nextId++, name: 'صورة ${_nextId - 1}', image: img));
    selected += 1;
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

  // ---------- history ----------
  void undo() {
    if (_undo.isEmpty || _busy) return;
    _redo.add(_snap());
    _restore(_undo.removeLast());
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty || _busy) return;
    _undo.add(_snap());
    _restore(_redo.removeLast());
    notifyListeners();
  }

  // ---------- tools ----------
  void setTool(Tool t) {
    tool = t;
    notifyListeners();
  }

  void setColor(Color c) {
    color = c;
    tool = Tool.brush;
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

  // ---------- drawing ----------
  static void paintStroke(Canvas c, List<Offset> pts, Color color,
      double size, double opacity, bool erase) {
    if (pts.isEmpty) return;
    final paint = Paint()
      ..isAntiAlias = true
      ..color = erase
          ? const Color(0xFF000000)
          : color.withValues(alpha: opacity)
      ..blendMode = erase ? BlendMode.clear : BlendMode.srcOver;
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

  void paintDoc(Canvas c, {required bool preview}) {
    final rect = Rect.fromLTWH(0, 0, docW.toDouble(), docH.toDouble());
    for (int i = 0; i < layers.length; i++) {
      final l = layers[i];
      if (!l.visible) continue;
      final p = Paint()
        ..color = Color.fromRGBO(0, 0, 0, l.opacity)
        ..blendMode = l.blendMode;
      c.saveLayer(rect, p);
      c.drawImage(l.image, Offset.zero, Paint());
      if (preview && i == selected && stroke.isNotEmpty) {
        paintStroke(c, stroke, color, brushSize, brushOpacity,
            tool == Tool.eraser);
      }
      c.restore();
    }
  }

  void beginStroke(Offset p) {
    if (_busy || current == null || !current!.visible) return;
    stroke = [p];
    notifyListeners();
  }

  void addPoint(Offset p) {
    if (stroke.isEmpty) return;
    stroke.add(p);
    notifyListeners();
  }

  void cancelStroke() {
    if (stroke.isEmpty || _busy) return;
    stroke = [];
    notifyListeners();
  }

  Future<void> endStroke() async {
    if (stroke.isEmpty || _busy) return;
    _busy = true;
    final layer = current!;
    final pts = List<Offset>.of(stroke);
    final old = layer.image;
    final rect = Rect.fromLTWH(0, 0, docW.toDouble(), docH.toDouble());
    final erase = tool == Tool.eraser;
    final img = await _render(docW, docH, (c) {
      c.saveLayer(rect, Paint());
      c.drawImage(old, Offset.zero, Paint());
      paintStroke(c, pts, color, brushSize, brushOpacity, erase);
      c.restore();
    });
    _pushUndo();
    layer.image = img;
    stroke = [];
    _busy = false;
    notifyListeners();
  }

  // ---------- view ----------
  Offset toDoc(Offset p) => (p - offset) / scale;

  void transformView(Offset prevMid, Offset mid, double ratio) {
    final newScale = (scale * ratio).clamp(0.05, 40.0).toDouble();
    final docPoint = (prevMid - offset) / scale;
    scale = newScale;
    offset = mid - docPoint * scale;
    notifyListeners();
  }

  void _fit() {
    if (viewport == Size.zero) return;
    final k = math.min(viewport.width / docW, viewport.height / docH) * 0.96;
    scale = k;
    offset = Offset((viewport.width - docW * k) / 2,
        (viewport.height - docH * k) / 2);
    _fitPending = false;
  }

  void fitToScreen() {
    _fit();
    notifyListeners();
  }

  void setViewport(Size sz) {
    if (sz == viewport) return;
    viewport = sz;
    if (_fitPending) _fit();
    notifyListeners();
  }

  // ---------- export ----------
  Future<Uint8List> exportPng() async {
    final img = await _render(docW, docH, (c) => paintDoc(c, preview: false));
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  }
}



class DocPainter extends CustomPainter {
  final EditorState s;
  DocPainter(this.s) : super(repaint: s);

  static Path? _checker;
  static int _cw = 0;
  static int _ch = 0;

  static Path _checkerPath(int w, int h) {
    if (_checker != null && _cw == w && _ch == h) return _checker!;
    const t = 32.0;
    final p = Path();
    for (int y = 0; y * t < h; y++) {
      for (int x = 0; x * t < w; x++) {
        if ((x + y).isOdd) p.addRect(Rect.fromLTWH(x * t, y * t, t, t));
      }
    }
    _checker = p;
    _cw = w;
    _ch = h;
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (s.layers.isEmpty) return;
    final rect = Rect.fromLTWH(0, 0, s.docW.toDouble(), s.docH.toDouble());
    canvas.save();
    canvas.translate(s.offset.dx, s.offset.dy);
    canvas.scale(s.scale);
    canvas.drawRect(rect.inflate(3 / s.scale), Paint()..color = Colors.black54);
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawPath(
        _checkerPath(s.docW, s.docH), Paint()..color = const Color(0xFFD9D9D9));
    s.paintDoc(canvas, preview: true);
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
              s.beginStroke(s.toDoc(e.localPosition));
            } else {
              s.cancelStroke();
            }
          },
          onPointerMove: (e) {
            final prev = _ptrs[e.pointer];
            if (prev == null) return;
            if (_ptrs.length == 1) {
              s.addPoint(s.toDoc(e.localPosition));
              _ptrs[e.pointer] = e.localPosition;
            } else if (_ptrs.length == 2) {
              final other =
                  _ptrs.entries.firstWhere((x) => x.key != e.pointer).value;
              final prevMid = (prev + other) / 2;
              final prevDist = (prev - other).distance;
              final mid = (e.localPosition + other) / 2;
              final dist = (e.localPosition - other).distance;
              s.transformView(
                  prevMid, mid, prevDist == 0 ? 1 : dist / prevDist);
              _ptrs[e.pointer] = e.localPosition;
            }
          },
          onPointerUp: (e) {
            final wasOne = _ptrs.length == 1;
            _ptrs.remove(e.pointer);
            if (wasOne) s.endStroke();
          },
          onPointerCancel: (e) {
            _ptrs.remove(e.pointer);
            s.cancelStroke();
          },
          child: Container(
            color: const Color(0xFF2B2B2B),
            child: CustomPaint(
              painter: DocPainter(s),
              size: Size.infinite,
            ),
          ),
        ),
      );
    });
  }
}



const _palette = <int>[
  0xFF000000, 0xFF424242, 0xFF9E9E9E, 0xFFFFFFFF,
  0xFFB71C1C, 0xFFF44336, 0xFFFF9800, 0xFFFFEB3B,
  0xFF8BC34A, 0xFF2E7D32, 0xFF00BCD4, 0xFF2196F3,
  0xFF1A237E, 0xFF9C27B0, 0xFFE91E63, 0xFF795548,
];

class ToolBar extends StatelessWidget {
  const ToolBar({super.key});

  Future<void> _pickColor(BuildContext context, EditorState s) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اللون'),
        content: Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final v in _palette)
              GestureDetector(
                onTap: () {
                  s.setColor(Color(v));
                  Navigator.pop(ctx);
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: Color(v),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white54, width: 1.5),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<EditorState>();
    return Material(
      color: const Color(0xFF1E1E1E),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  ChoiceChip(
                    avatar: const Icon(Icons.brush, size: 18),
                    label: const Text('فرشاة'),
                    selected: s.tool == Tool.brush,
                    onSelected: (_) => s.setTool(Tool.brush),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    avatar: const Icon(Icons.auto_fix_normal, size: 18),
                    label: const Text('ممحاة'),
                    selected: s.tool == Tool.eraser,
                    onSelected: (_) => s.setTool(Tool.eraser),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () => _pickColor(context, s),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: s.color,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              _SliderRow(
                label: 'الحجم',
                value: s.brushSize,
                min: 1,
                max: 200,
                text: s.brushSize.round().toString(),
                onChanged: s.setSize,
              ),
              _SliderRow(
                label: 'الشفافية',
                value: s.brushOpacity * 100,
                min: 5,
                max: 100,
                text: '${(s.brushOpacity * 100).round()}%',
                onChanged: (v) => s.setBrushOpacity(v / 100),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value, min, max;
  final String text;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.text,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 64, child: Text(label)),
        Expanded(
          child: Slider(value: value, min: min, max: max, onChanged: onChanged),
        ),
        SizedBox(width: 44, child: Text(text, textAlign: TextAlign.end)),
      ],
    );
  }
}



const _modes = <BlendMode, String>{
  BlendMode.srcOver: 'Normal',
  BlendMode.multiply: 'Multiply',
  BlendMode.screen: 'Screen',
  BlendMode.overlay: 'Overlay',
  BlendMode.darken: 'Darken',
  BlendMode.lighten: 'Lighten',
  BlendMode.colorDodge: 'Color Dodge',
  BlendMode.colorBurn: 'Color Burn',
  BlendMode.hardLight: 'Hard Light',
  BlendMode.softLight: 'Soft Light',
  BlendMode.difference: 'Difference',
  BlendMode.exclusion: 'Exclusion',
};

class LayersDrawer extends StatelessWidget {
  const LayersDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<EditorState>();
    final n = s.layers.length;
    final cur = s.current;
    return Drawer(
      width: 340,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Text('الطبقات',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    tooltip: 'طبقة جديدة',
                    icon: const Icon(Icons.add_box_outlined),
                    onPressed: s.addLayer,
                  ),
                  IconButton(
                    tooltip: 'صورة كطبقة',
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    onPressed: () async {
                      final b = await pickImageBytes();
                      if (b != null) await s.addImageLayer(b);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ReorderableListView.builder(
                itemCount: n,
                onReorder: (oldD, newD) {
                  if (newD > oldD) newD -= 1;
                  s.reorder(n - 1 - oldD, n - 1 - newD);
                },
                itemBuilder: (context, d) {
                  final i = n - 1 - d;
                  final l = s.layers[i];
                  return ListTile(
                    key: ValueKey(l.id),
                    selected: i == s.selected,
                    selectedTileColor: Colors.white12,
                    onTap: () => s.selectLayer(i),
                    leading: Container(
                      width: 48,
                      height: 48,
                      color: Colors.grey.shade700,
                      child: RawImage(image: l.image, fit: BoxFit.contain),
                    ),
                    title: Text(l.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(
                              l.visible ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => s.toggleVisible(i),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: n > 1 ? () => s.deleteLayer(i) : null,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (cur != null) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Text('الشفافية'),
                        Expanded(
                          child: Slider(
                            value: cur.opacity,
                            onChangeStart: (_) => s.beginLayerEdit(),
                            onChanged: (v) => s.setLayerOpacity(s.selected, v),
                          ),
                        ),
                        Text('${(cur.opacity * 100).round()}%'),
                      ],
                    ),
                    DropdownButton<BlendMode>(
                      isExpanded: true,
                      value: cur.blendMode,
                      items: [
                        for (final e in _modes.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (m) {
                        if (m != null) s.setBlend(s.selected, m);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}



class EditorPage extends StatelessWidget {
  const EditorPage({super.key});

  Future<void> _menu(BuildContext context, String v) async {
    final s = context.read<EditorState>();
    final msg = ScaffoldMessenger.of(context);
    switch (v) {
      case 'new':
        final size = await showDialog<List<int>>(
          context: context,
          builder: (ctx) => SimpleDialog(
            title: const Text('مشروع جديد'),
            children: [
              for (final o in const [
                ['1080 × 1080', 1080, 1080],
                ['1080 × 1350', 1080, 1350],
                ['1080 × 1920', 1080, 1920],
                ['2048 × 2048', 2048, 2048],
              ])
                SimpleDialogOption(
                  onPressed: () =>
                      Navigator.pop(ctx, [o[1] as int, o[2] as int]),
                  child: Text(o[0] as String),
                ),
            ],
          ),
        );
        if (size != null) await s.newProject(size[0], size[1]);
        break;
      case 'open':
        final b = await pickImageBytes();
        if (b != null) await s.openImageAsProject(b);
        break;
      case 'add':
        final b = await pickImageBytes();
        if (b != null) await s.addImageLayer(b);
        break;
      case 'save':
        try {
          final bytes = await s.exportPng();
          await Gal.putImageBytes(bytes, album: 'PixelStudio');
          msg.showSnackBar(const SnackBar(content: Text('تم الحفظ في المعرض ✅')));
        } catch (e) {
          msg.showSnackBar(SnackBar(content: Text('فشل الحفظ: $e')));
        }
        break;
      case 'fit':
        s.fitToScreen();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.read<EditorState>();
    final canUndo = context.select<EditorState, bool>((e) => e.canUndo);
    final canRedo = context.select<EditorState, bool>((e) => e.canRedo);
    return Scaffold(
      appBar: AppBar(
        title: const Text('PixelStudio'),
        actions: [
          IconButton(
              icon: const Icon(Icons.undo), onPressed: canUndo ? s.undo : null),
          IconButton(
              icon: const Icon(Icons.redo), onPressed: canRedo ? s.redo : null),
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.layers),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (v) => _menu(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('مشروع جديد')),
              PopupMenuItem(value: 'open', child: Text('فتح صورة')),
              PopupMenuItem(value: 'add', child: Text('إضافة صورة كطبقة')),
              PopupMenuItem(value: 'save', child: Text('حفظ في المعرض (PNG)')),
              PopupMenuItem(value: 'fit', child: Text('ملاءمة الشاشة')),
            ],
          ),
        ],
      ),
      endDrawer: const LayersDrawer(),
      body: const Column(
        children: [
          Expanded(child: CanvasView()),
          ToolBar(),
        ],
      ),
    );
  }
}



void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => EditorState()..init(),
      child: const App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PixelStudio',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF2B2B2B),
      ),
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
      home: const EditorPage(),
    );
  }
}

