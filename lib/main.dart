import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: VoiceTalkieApp(),
  ));
}

class VoiceTalkieApp extends StatefulWidget {
  const VoiceTalkieApp({super.key});

  @override
  State<VoiceTalkieApp> createState() => _VoiceTalkieAppState();
}

class _VoiceTalkieAppState extends State<VoiceTalkieApp> {
  static const String multicastAddress = '239.255.0.1';
  static const int multicastPort = 8888;

  RawDatagramSocket? _socket;
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();
  StreamController<Food>? _audioStreamController;

  bool _isTalking = false;
  bool _isReceiving = false;
  int _peersCount = 0;
  final Set<String> _connectedPeers = {};

  @override
  void initState() {
    super.initState();
    _startSystem();
  }

  Future<void> _startSystem() async {
    await [Permission.microphone, Permission.bluetoothConnect].request();
    await _recorder.openRecorder();
    await _player.openPlayer();

    try {
      _socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        multicastPort,
        reuseAddress: true,
        reusePort: true,
      );
      _socket?.multicastLoopback = false;
      _socket?.joinMulticast(InternetAddress(multicastAddress));

      _socket?.listen((event) {
        if (event == RawSocketEvent.read) {
          Datagram? dg = _socket?.receive();
          if (dg != null) _handleData(dg);
        }
      });

      Timer.periodic(const Duration(seconds: 2), (_) {
        _socket?.send([0x01], InternetAddress(multicastAddress), multicastPort);
      });
    } catch (e) {
      debugPrint("Socket Error: $e");
    }
  }

  void _handleData(Datagram dg) {
    if (dg.data.isEmpty) return;
    int type = dg.data[0];

    if (type == 0x01) {
      if (!_connectedPeers.contains(dg.address.address)) {
        setState(() {
          _connectedPeers.add(dg.address.address);
          _peersCount = _connectedPeers.length;
        });
      }
    } else if (type == 0x02 && !_isTalking) {
      _playAudio(dg.data.sublist(1));
    }
  }

  void _playAudio(Uint8List audio) async {
    if (!_player.isPlaying) {
      setState(() => _isReceiving = true);
      await _player.startPlayerFromStream(
        codec: Codec.pcm16,
        numChannels: 1,
        sampleRate: 16000,
      );
    }
    _player.foodSink?.add(FoodData(audio));
    Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _isReceiving = false);
    });
  }

  Future<void> _talk() async {
    if (_recorder.isRecording) return;
    setState(() => _isTalking = true);

    _audioStreamController = StreamController<Food>();
    _audioStreamController?.stream.listen((food) {
      if (food is FoodData && food.data != null) {
        Uint8List packet = Uint8List(food.data!.length + 1);
        packet[0] = 0x02;
        packet.setRange(1, packet.length, food.data!);
        _socket?.send(packet, InternetAddress(multicastAddress), multicastPort);
      }
    });

    await _recorder.startRecorder(
      toStream: _audioStreamController?.sink,
      codec: Codec.pcm16,
      numChannels: 1,
      sampleRate: 16000,
    );
  }

  Future<void> _stopTalk() async {
    if (!_isTalking) return;
    await _recorder.stopRecorder();
    await _audioStreamController?.close();
    setState(() => _isTalking = false);
  }

  @override
  void dispose() {
    _socket?.close();
    _recorder.closeRecorder();
    _player.closePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Color ringColor = _isTalking
        ? Colors.redAccent
        : (_isReceiving ? Colors.greenAccent : const Color(0xFF2C3246));

    return Scaffold(
      backgroundColor: const Color(0xFF0C0E14),
      appBar: AppBar(
        title: const Text("VOICE TALKIE", style: TextStyle(letterSpacing: 2, fontSize: 16)),
        backgroundColor: Colors.transparent,
        centerTitle: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              "જોડાયેલા ફોન: $_peersCount",
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 15),
            Text(
              _isTalking ? "વાત થઈ રહી છે..." : (_isReceiving ? "અવાજ આવી રહ્યો છે..." : "બોલવા માટે દબાવી રાખો"),
              style: TextStyle(color: ringColor, fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 40),
            GestureDetector(
              onTapDown: (_) => _talk(),
              onTapUp: (_) => _stopTalk(),
              onTapCancel: () => _stopTalk(),
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: ringColor,
                  boxShadow: [
                    BoxShadow(color: ringColor.withOpacity(0.4), blurRadius: 25, spreadRadius: 5)
                  ],
                ),
                child: Icon(_isTalking ? Icons.mic : Icons.mic_none, size: 80, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
