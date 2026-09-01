import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:open_filex/open_filex.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_lib;

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'محمل الوسائط المتقدم',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        colorScheme: const ColorScheme.dark(
          primary: Colors.deepPurpleAccent,
          secondary: Colors.redAccent,
        ),
      ),
      home: const MediaDownloaderScreen(),
    );
  }
}

class MediaDownloaderScreen extends StatefulWidget {
  const MediaDownloaderScreen({super.key});

  @override
  State<MediaDownloaderScreen> createState() => _MediaDownloaderScreenState();
}

class _MediaDownloaderScreenState extends State<MediaDownloaderScreen> {
  final TextEditingController _urlController = TextEditingController();
  bool _isDownloading = false;
  String _statusMessage = '';
  double _downloadProgress = 0.0;
  String _downloadSizeInfo = '';
  String _selectedQuality = 'High';
  String? _downloadedFilePath;

  final List<String> _qualityOptions = ['High', 'Medium', 'Low', 'Audio Only'];

  // رابط سيرفر Render الخاص بك
  final String _backendUrl = 'https://downloader-backend-mfby.onrender.com/extract';

  Future<void> _pasteFromClipboard() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      setState(() {
        _urlController.text = data.text!;
      });
    }
  }

  Future<void> _startDownload() async {
    final rawUrl = _urlController.text.trim();
    if (rawUrl.isEmpty) {
      setState(() {
        _statusMessage = 'يرجى إدخال رابط الفيديو أولاً';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
      _downloadSizeInfo = '';
      _statusMessage = 'جاري التنسيق مع السيرفر الخاص...';
      _downloadedFilePath = null;
    });

    try {
      await Permission.storage.request();
      await Permission.manageExternalStorage.request();

      if (rawUrl.contains('youtube.com') || rawUrl.contains('youtu.be')) {
        await _downloadYouTube(rawUrl);
      } else {
        await _downloadViaCustomBackend(rawUrl);
      }
    } catch (e) {
      setState(() {
        _statusMessage = 'حدث خطأ أثناء التنزيل:\n$e';
      });
    } finally {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  Future<void> _downloadYouTube(String url) async {
    final yt = yt_lib.YoutubeExplode();
    try {
      var video = await yt.videos.get(url);
      var manifest = await yt.videos.streamsClient.getManifest(video.id);
      
      yt_lib.StreamInfo streamInfo;
      if (_selectedQuality == 'Audio Only') {
        streamInfo = manifest.audio.withHighestBitrate();
      } else if (_selectedQuality == 'Low') {
        streamInfo = manifest.muxed.sortByVideoQuality().last;
      } else if (_selectedQuality == 'Medium') {
        var muxedList = manifest.muxed.toList();
        streamInfo = muxedList.length > 1 ? muxedList[muxedList.length ~/ 2] : manifest.muxed.withHighestBitrate();
      } else {
        streamInfo = manifest.muxed.withHighestBitrate();
      }

      Directory? downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        downloadsDir = await getExternalStorageDirectory();
      }

      String safeTitle = video.title.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      var ext = _selectedQuality == 'Audio Only' ? 'mp3' : streamInfo.container.name;
      var savePath = '${downloadsDir!.path}/${safeTitle}.$ext';

      var stream = yt.videos.streamsClient.get(streamInfo);
      var file = File(savePath);
      var fileStream = file.openWrite();

      var totalBytes = streamInfo.size.totalBytes;
      var downloadedBytes = 0;

      await for (var chunk in stream) {
        downloadedBytes += chunk.length;
        fileStream.add(chunk);
        setState(() {
          _downloadProgress = downloadedBytes / totalBytes;
          _downloadSizeInfo = '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
          _statusMessage = 'جاري التحميل... ${(_downloadProgress * 100).toStringAsFixed(0)}%';
        });
      }

      await fileStream.flush();
      await fileStream.close();

      setState(() {
        _downloadedFilePath = savePath;
        _statusMessage = 'تم التنزيل بنجاح!\nالمسار: $savePath';
      });
    } finally {
      yt.close();
    }
  }

  Future<void> _downloadViaCustomBackend(String targetUrl) async {
    final response = await http.post(
      Uri.parse(_backendUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'url': targetUrl}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final String? directMediaUrl = data['direct_url'];
      final String title = data['title'] ?? 'Media_${DateTime.now().millisecondsSinceEpoch}';
      final String ext = _selectedQuality == 'Audio Only' ? 'mp3' : (data['ext'] ?? 'mp4');

      if (directMediaUrl != null && directMediaUrl.isNotEmpty) {
        Directory? downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }

        String safeTitle = title.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
        var savePath = '${downloadsDir!.path}/$safeTitle.$ext';

        final client = http.Client();
        final request = http.Request('GET', Uri.parse(directMediaUrl));
        final httpResponse = await client.send(request);

        final totalBytes = httpResponse.contentLength ?? 0;
        var downloadedBytes = 0;

        final file = File(savePath);
        final fileStream = file.openWrite();

        await httpResponse.stream.forEach((chunk) {
          downloadedBytes += chunk.length;
          fileStream.add(chunk);
          if (totalBytes > 0) {
            setState(() {
              _downloadProgress = downloadedBytes / totalBytes;
              _downloadSizeInfo = '${(downloadedBytes / (1024 * 1024)).toStringAsFixed(1)} MB / ${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
              _statusMessage = 'جاري التحميل... ${(_downloadProgress * 100).toStringAsFixed(0)}%';
            });
          }
        });

        await fileStream.flush();
        await fileStream.close();

        setState(() {
          _downloadedFilePath = savePath;
          _statusMessage = 'تم التنزيل بنجاح!\nالمسار: $savePath';
        });
      } else {
        throw Exception('السيرفر لم يعثر على رابط فيديو مباشر.');
      }
    } else {
      throw Exception('فشل السيرفر في تحليل هذا الرابط.');
    }
  }

  void _openFile() {
    if (_downloadedFilePath != null) {
      OpenFilex.open(_downloadedFilePath!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'المطور أمين عادل الشيباني',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
            fontSize: 22,
          ),
        ),
        centerTitle: true,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E1B2E), Color(0xFF0F0C20)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _urlController,
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: Colors.white10,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                labelText: 'أدخل الرابط (YouTube, Insta, FB, TikTok, X)',
                                labelStyle: const TextStyle(color: Colors.white70),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _pasteFromClipboard,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurpleAccent,
                              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('لصق', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 15),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('دقة التنزيل:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                          DropdownButton<String>(
                            value: _selectedQuality,
                            dropdownColor: const Color(0xFF1E1B2E),
                            style: const TextStyle(color: Colors.white),
                            items: _qualityOptions.map((String quality) {
                              return DropdownMenuItem<String>(
                                value: quality,
                                child: Text(quality),
                              );
                            }).toList(),
                            onChanged: (newValue) {
                              setState(() {
                                _selectedQuality = newValue!;
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton(
                        onPressed: _isDownloading ? null : _startDownload,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isDownloading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Text('بدء التنزيل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                      const SizedBox(height: 20),
                      if (_isDownloading) ...[
                        LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null, color: Colors.redAccent),
                        const SizedBox(height: 10),
                        Text(_downloadSizeInfo, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 10),
                      ],
                      Text(
                        _statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, color: Colors.white70),
                      ),
                      if (_downloadedFilePath != null && !_isDownloading) ...[
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: _openFile,
                          icon: const Icon(Icons.play_arrow, color: Colors.white),
                          label: const Text('تشغيل', style: TextStyle(color: Colors.white, fontSize: 16)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
