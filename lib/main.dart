import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
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
  double _downloadProgress = 0.0;
  String _downloadSizeInfo = '';
  String _selectedQuality = 'High';
  String? _downloadedFilePath;

  final List<String> _qualityOptions = ['High', 'Medium', 'Low', 'Audio Only'];

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
      _downloadProgress = 0.0;
      _downloadSizeInfo = '';
      _statusMessage = 'جاري تحليل الرابط...';
      _downloadedFilePath = null;
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

  Future<void> _downloadSocialMedia(String url) async {
    final apiUrl = Uri.parse('https://api.cobalt.tools/api/json');
    final response = await http.post(
      apiUrl,
      headers: {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'url': url,
        'downloadMode': _selectedQuality == 'Audio Only' ? 'audio' : 'auto'
      }),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final String? mediaUrl = data['url'];

      if (mediaUrl != null) {
        Directory? downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = await getExternalStorageDirectory();
        }

        var ext = _selectedQuality == 'Audio Only' ? 'mp3' : 'mp4';
        var savePath = '${downloadsDir!.path}/Media_${DateTime.now().millisecondsSinceEpoch}.$ext';

        final client = http.Client();
        final request = http.Request('GET', Uri.parse(mediaUrl));
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
        throw Exception('تعذر استخراج رابط الميديا المباشر.');
      }
    } else {
      throw Exception('المنصة غير مدعومة أو الرابط غير صالح.');
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
        title: const Text(
          'المطور أمين عادل الشيباني',
          style: TextStyle(
            color: Colors.red,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'أدخل رابط الفيديو (YouTube, Twitter, FB, Insta, TikTok)',
                ),
              ),
              const SizedBox(height: 15),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('دقة التنزيل:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  DropdownButton<String>(
                    value: _selectedQuality,
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
              const SizedBox(height: 15),
              ElevatedButton(
                onPressed: _isDownloading ? null : _startDownload,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(45),
                ),
                child: _isDownloading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('بدء التنزيل', style: TextStyle(fontSize: 16)),
              ),
              const SizedBox(height: 20),
              if (_isDownloading) ...[
                LinearProgressIndicator(value: _downloadProgress > 0 ? _downloadProgress : null),
                const SizedBox(height: 10),
                Text(_downloadSizeInfo, style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
              ],
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
              if (_downloadedFilePath != null && !_isDownloading) ...[
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _openFile,
                  icon: const Icon(Icons.play_arrow, color: Colors.white),
                  label: const Text('تشغيل', style: TextStyle(color: Colors.white, fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    minimumSize: const Size.fromHeight(45),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
