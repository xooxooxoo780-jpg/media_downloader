import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
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

  Future<void> _startDownload() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _statusMessage = 'يرجى إدخال رابط الفيديو أولاً';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _statusMessage = 'جاري تحليل الرابط...';
    });

    try {
      await Permission.storage.request();
      await Permission.manageExternalStorage.request();

      if (url.contains('youtube.com') || url.contains('youtu.be')) {
        await _downloadYouTube(url);
      } else {
        await _downloadSocialMedia(url);
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
      var streamInfo = manifest.muxed.isNotEmpty
          ? manifest.muxed.withHighestBitrate()
          : manifest.video.withHighestBitrate();

      Directory? downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        downloadsDir = await getExternalStorageDirectory();
      }

      String safeTitle = video.title.replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]+'), '');
      var savePath = '${downloadsDir!.path}/${safeTitle}.${streamInfo.container.name}';

      var stream = yt.videos.streamsClient.get(streamInfo);
      var file = File(savePath);
      var fileStream = file.openWrite();

      setState(() {
        _statusMessage = 'جاري تنزيل فيديو يوتيوب...';
      });

      await stream.pipe(fileStream);
      await fileStream.flush();
      await fileStream.close();

      setState(() {
        _statusMessage = 'تم التنزيل بنجاح!\nالمسار: $savePath';
      });
    } finally {
      yt.close();
    }
  }

  Future<void> _downloadSocialMedia(String url) async {
    setState(() {
      _statusMessage = 'جاري جلب رابط الميديا...';
    });

    final apiUrl = Uri.parse('https://api.cobalt.tools/api/json');
    final response = await http.post(
      apiUrl,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'url': url}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final String? mediaUrl = data['url'];

      if (mediaUrl != null) {
        Directory? downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }

        var savePath = '${downloadsDir!.path}/Media_${DateTime.now().millisecondsSinceEpoch}.mp4';

        setState(() {
          _statusMessage = 'جاري التحميل إلى الهاتف...';
        });

        final mediaResponse = await http.get(Uri.parse(mediaUrl));
        final file = File(savePath);
        await file.writeAsBytes(mediaResponse.bodyBytes);

        setState(() {
          _statusMessage = 'تم التنزيل بنجاح!\nالمسار: $savePath';
        });
      } else {
        throw Exception('تعذر استخراج رابط الميديا المباشر.');
      }
    } else {
      throw Exception('المنصة غير مدعومة أو الرابط غير صالح.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('محمل الوسائط المتقدم'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TextField(
                      controller: _urlController,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        labelText: 'أدخل رابط (YouTube, Twitter, FB, Insta, TikTok)',
                      ),
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isDownloading ? null : _startDownload,
                      child: _isDownloading
                          ? const CircularProgressIndicator()
                          : const Text('بدء التنزيل'),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _statusMessage,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Text(
                'المطور أمين عادل الشيباني',
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
