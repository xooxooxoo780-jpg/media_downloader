import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

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

  Future<void> _downloadVideo() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() {
        _statusMessage = 'يرجى إدخال رابط الفيديو أولاً';
      });
      return;
    }

    setState(() {
      _isDownloading = true;
      _statusMessage = 'جاري تحضير التحميل...';
    });

    final yt = YoutubeExplode();

    try {
      await Permission.storage.request();

      var video = await yt.videos.get(url);
      var manifest = await yt.videos.streamsClient.getManifest(video.id);
      var streamInfo = manifest.muxed.withHighestBitrate();

      var dir = await getExternalStorageDirectory();
      var savePath = '${dir!.path}/${video.title.replaceAll(RegExp(r'[^\w\s]+'), '')}.${streamInfo.container.name}';

      var stream = yt.videos.streamsClient.get(streamInfo);
      var file = File(savePath);
      var fileStream = file.openWrite();

      setState(() {
        _statusMessage = 'جاري التحميل: ${video.title}';
      });

      await stream.pipe(fileStream);
      await fileStream.flush();
      await fileStream.close();

      setState(() {
        _statusMessage = 'تم التحميل بنجاح!\nالمسار: $savePath';
      });
    } catch (e) {
      setState(() {
        _statusMessage = 'حدث خطأ أثناء التنزيل: $e';
      });
    } finally {
      yt.close();
      setState(() {
        _isDownloading = false;
      });
    }
  }

  @override;
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
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'أدخل رابط الفيديو (YouTube)',
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isDownloading ? null : _downloadVideo,
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
    );
  }
}
