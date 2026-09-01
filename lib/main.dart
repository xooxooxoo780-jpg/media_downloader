import 'package:flutter/material.dart';
import 'package:process_run/shell.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const DownloaderApp());
}

class DownloaderApp extends StatelessWidget {
  const DownloaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Media Downloader',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _urlController = TextEditingController();
  String _selectedQuality = 'best';
  String _statusMessage = '';
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.storage.request();
    await Permission.manageExternalStorage.request();
  }

  Future<void> _startDownload() async {
    if (_urlController.text.trim().isEmpty) return;

    setState(() {
      _isDownloading = true;
      _statusMessage = 'جاري بدء التنزيل...';
    });

    try {
      final dir = await getExternalStorageDirectory();
      final outputPath = '${dir?.path}/%(title)s.%(ext)s';
      final shell = Shell();

      String formatOption = '-f "bv*+ba/b"';
      if (_selectedQuality == 'medium') {
        formatOption = '-f "m4a/mp4"';
      } else if (_selectedQuality == 'low') {
        formatOption = '-f "worst"';
      } else if (_selectedQuality == 'mp3') {
        formatOption = '-x --audio-format mp3';
      }

      final command = 'yt-dlp $formatOption -o "$outputPath" "${_urlController.text.trim()}"';
      
      await shell.run(command);

      setState(() {
        _statusMessage = 'تم التنزيل بنجاح!';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'حدث خطأ أثناء التنزيل: $e';
      });
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مُحمل الوسائط المتقدم'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'أدخل رابط الفيديو (TikTok, YouTube, Instagram...)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButton<String>(
              value: _selectedQuality,
              isExpanded: true,
              items: const [
                DropdownMenuItem(value: 'best', child: Text('أعلى جودة متاحة (High)')),
                DropdownMenuItem(value: 'medium', child: Text('جودة متوسطة (Medium)')),
                DropdownMenuItem(value: 'low', child: Text('جودة منخفضة (Low)')),
                DropdownMenuItem(value: 'mp3', child: Text('صوت فقط (MP3)')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _selectedQuality = val);
              },
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isDownloading ? null : _startDownload,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              child: _isDownloading
                  ? const CircularProgressIndicator()
                  : const Text('بدء التنزيل'),
            ),
            const SizedBox(height: 20),
            Text(_statusMessage, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
         
