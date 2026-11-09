import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

void main() {
  runApp(
    const MaterialApp(debugShowCheckedModeBanner: false, home: HalamanUtama()),
  );
}

class HalamanUtama extends StatefulWidget {
  const HalamanUtama({Key? key}) : super(key: key);

  @override
  State<HalamanUtama> createState() => _HalamanUtamaState();
}

class _HalamanUtamaState extends State<HalamanUtama> {
  Uint8List? _imageBytes;
  String _imageName = 'foto.jpg';
  bool _isScanning = false;
  final ImagePicker _picker = ImagePicker();

  String? _kategori;
  String? _jenis;
  int? _hargaAcuan;
  int _totalPendapatan = 0;

  final TextEditingController _beratController = TextEditingController();

  // Chrome / Windows / iOS Simulator: 127.0.0.1
  // Emulator Android: 10.0.2.2
  // HP asli: ganti dengan IP laptop, contoh http://192.168.1.10:8000
  String get _apiUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000/v1/predict';
    return 'http://10.0.2.2:8000/v1/predict';
  }

  // Tentukan kategori umum dari nama kelas YOLO
  String _tentukanKategori(String kelas) {
    final k = kelas.toLowerCase();
    if (k.contains('kaca') || k.contains('gelas')) return 'Kaca';
    if (k.contains('plastik')) return 'Plastik';
    if (k.contains('kardus') || k.contains('kertas')) return 'Kertas';
    if (k.contains('kaleng')) return 'Logam';
    return 'Lainnya';
  }

  String _rapikanNama(String kelas) {
    return kelas
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  @override
  void dispose() {
    _beratController.dispose();
    super.dispose();
  }

  void _tampilkanPanduan(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.green),
              SizedBox(width: 10),
              Text(
                'Panduan Penggunaan',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. Tap tombol Kamera atau Galeri untuk memasukkan foto sampah.',
                ),
                SizedBox(height: 8),
                Text(
                  '2. AI YOLOv8 akan memproses gambar dan menentukan kategori serta harga.',
                ),
                SizedBox(height: 8),
                Text(
                  '3. Masukkan estimasi berat (Kg) untuk melihat total pendapatan otomatis.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Mengerti',
                style: TextStyle(
                  color: Colors.green,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _prosesGambarAI(XFile image) async {
    final Uint8List bytes = await image.readAsBytes();

    if (!mounted) return;
    setState(() {
      _imageBytes = bytes;
      _imageName = image.name.isNotEmpty ? image.name : 'foto.jpg';
      _isScanning = true;
      _kategori = null;
      _jenis = null;
      _hargaAcuan = null;
      _totalPendapatan = 0;
      _beratController.clear();
    });

    try {
      final request = http.MultipartRequest('POST', Uri.parse(_apiUrl));
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: _imageName),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (!mounted) return;

      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        final List detail = (jsonResponse['detail'] as List?) ?? [];

        if (detail.isEmpty) {
          setState(() => _isScanning = false);
          _tampilkanNotif('Tidak ada sampah yang terdeteksi.');
          return;
        }

        // Ambil deteksi dengan akurasi tertinggi
        Map best = detail.first as Map;
        for (final d in detail) {
          final akurasi = (d['akurasi'] as num?) ?? 0;
          final akurasiBest = (best['akurasi'] as num?) ?? 0;
          if (akurasi > akurasiBest) best = d as Map;
        }

        final String kelas = (best['jenis_sampah'] ?? 'Tidak Diketahui')
            .toString();

        setState(() {
          _isScanning = false;
          _kategori = _tentukanKategori(kelas);
          _jenis = _rapikanNama(kelas);
          _hargaAcuan = (best['harga_per_kg'] as num?)?.toInt() ?? 0;
        });
      } else {
        setState(() => _isScanning = false);
        _tampilkanNotif('Error dari server: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isScanning = false);
      _tampilkanNotif(
        'Gagal terhubung ke server AI. Pastikan FastAPI menyala!',
      );
    }
  }

  void _tampilkanNotif(String pesan) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(pesan), backgroundColor: Colors.red));
  }

  void _hitungTotal(String val) {
    if (val.isNotEmpty && _hargaAcuan != null) {
      final double berat = double.tryParse(val.replaceAll(',', '.')) ?? 0;
      setState(() {
        _totalPendapatan = (berat * _hargaAcuan!).toInt();
      });
    } else {
      setState(() => _totalPendapatan = 0);
    }
  }

  Future<void> _bukaKamera() async {
    try {
      final XFile? photo = await _picker.pickImage(source: ImageSource.camera);
      if (photo != null) await _prosesGambarAI(photo);
    } catch (e) {
      _tampilkanNotif(
        'Kamera tidak tersedia di perangkat ini. Coba pakai Galeri.',
      );
    }
  }

  Future<void> _bukaGaleri() async {
    try {
      final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
      if (image != null) await _prosesGambarAI(image);
    } catch (e) {
      _tampilkanNotif('Gagal membuka galeri.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Selamat datang,',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
            Text(
              'Bank Sampah',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: CircleAvatar(
              backgroundColor: Colors.white.withOpacity(0.2),
              child: IconButton(
                icon: const Icon(
                  Icons.notifications_active,
                  color: Colors.white,
                ),
                tooltip: 'Panduan Penggunaan',
                onPressed: () => _tampilkanPanduan(context),
              ),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Stack(
          children: [
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Colors.green[800],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    height: 250,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _imageBytes == null
                        ? _buildEmptyState()
                        : ScannerAnimation(
                            isScanning: _isScanning,
                            child: Image.memory(
                              _imageBytes!,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                            ),
                          ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _bukaKamera,
                          icon: const Icon(
                            Icons.camera_alt,
                            color: Colors.green,
                          ),
                          label: const Text(
                            'Kamera',
                            style: TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            backgroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            side: BorderSide(
                              color: Colors.green[700]!,
                              width: 1.5,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _bukaGaleri,
                          icon: const Icon(
                            Icons.photo_library,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Galeri',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[800],
                            padding: const EdgeInsets.symmetric(vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 25),
                  if (_kategori != null) ...[
                    const Text(
                      'Hasil Analisis AI',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildListTile(
                            Icons.category,
                            'Kategori',
                            _kategori!,
                          ),
                          const Divider(),
                          _buildListTile(
                            Icons.recycling,
                            'Jenis',
                            _jenis ?? '-',
                          ),
                          const Divider(),
                          _buildListTile(
                            Icons.sell,
                            'Harga Acuan',
                            'Rp ${_hargaAcuan ?? 0} / kg',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Estimasi Berat',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                      child: TextField(
                        controller: _beratController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: _hitungTotal,
                        decoration: const InputDecoration(
                          icon: Icon(Icons.scale, color: Colors.grey),
                          hintText: 'Masukkan angka...',
                          suffixText: 'Kg',
                          suffixStyle: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                          ),
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.green[800],
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Total Estimasi Pendapatan',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Rp $_totalPendapatan',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.green[50],
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.document_scanner_rounded,
            size: 60,
            color: Colors.green[700],
          ),
        ),
        const SizedBox(height: 15),
        const Text(
          'Area Pemindaian Sampah',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Silakan ambil foto atau pilih dari galeri\nuntuk mulai menganalisis dengan AI.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildListTile(IconData icon, String title, String trailing) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(icon, color: Colors.green[600], size: 20),
            const SizedBox(width: 10),
            Text(title, style: TextStyle(color: Colors.grey[600])),
          ],
        ),
        Flexible(
          child: Text(
            trailing,
            textAlign: TextAlign.right,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class ScannerAnimation extends StatefulWidget {
  final Widget child;
  final bool isScanning;

  const ScannerAnimation({
    Key? key,
    required this.child,
    required this.isScanning,
  }) : super(key: key);

  @override
  State<ScannerAnimation> createState() => _ScannerAnimationState();
}

class _ScannerAnimationState extends State<ScannerAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _animation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
    if (widget.isScanning) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(ScannerAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isScanning && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isScanning) {
      _controller.stop();
      _controller.reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(child: widget.child),
        if (widget.isScanning)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return AnimatedBuilder(
                  animation: _animation,
                  builder: (context, child) {
                    return Stack(
                      children: [
                        Positioned(
                          top: _animation.value * (constraints.maxHeight - 4),
                          left: 0,
                          right: 0,
                          child: Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.greenAccent,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.greenAccent.withOpacity(0.8),
                                  blurRadius: 15,
                                  spreadRadius: 3,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
