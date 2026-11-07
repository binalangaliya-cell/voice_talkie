import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';

void main() {
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
  bool _isTalking = false;
  bool _isReceiving = false;
  int _peersCount = 0;
  final Set<String> _connectedPeers = {};

  @override
  void initState() {
    super.initState();
    _initNetwork();
  }

  Future<void> _initNetwork() async {
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
      setState(() => _isReceiving = true);
      Timer(const Duration(milliseconds: 400), () {
        if (mounted) setState(() => _isReceiving = false);
      });
    }
  }

  void _startTalk() {
    setState(() => _isTalking = true);
    Uint8List ping = Uint8List.fromList([0x02]);
    _socket?.send(ping, InternetAddress(multicastAddress), multicastPort);
  }

  void _stopTalk() {
    setState(() => _isTalking = false);
  }

  @override
  void dispose() {
    _socket?.close();
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
              onTapDown: (_) => _startTalk(),
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
