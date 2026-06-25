import 'dart:async';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_project/core/serial/serial_service.dart';

/// Sends cut data to the Mietubl 180T machine using the proper binary protocol.
///
/// The .blt file from the server is a HEX STRING representing the raw cut data.
/// This sender:
/// 1. Reads the hex string from the file
/// 2. Builds a metadata first-command (file size + filename)
/// 3. Splits the hex data into 1024-char chunks (512 bytes each)
/// 4. Wraps each chunk: 9CC9CC + seq + 30 + lenLo + lenHi + data + CRC + 0D0A
/// 5. Sends chunk by chunk via serial port
/// 6. Machine starts cutting after receiving all packets
class MietublCutSender {
  static const String _password = 'mtbznqmji4368637';
  static const int _chunkSize = 1024; // hex chars per chunk (= 512 bytes)

  final CutterSerialService _serial;
  final void Function(int progress)? onProgress;
  final void Function(String status)? onStatus;

  bool _cancelled = false;

  MietublCutSender(
    this._serial, {
    this.onProgress,
    this.onStatus,
  });

  /// Send cut from a .blt file content (hex string).
  /// [fileContent] is the raw text content of the .blt file (hex encoded data).
  /// [fileName] is used for the metadata header.
  Future<bool> sendCutFromBltFile(String fileContent, {String fileName = 'cut.blt'}) async {
    _cancelled = false;

    // Clean the hex data - remove whitespace, newlines, non-hex chars
    final hexData = fileContent.replaceAll(RegExp(r'[^0-9A-Fa-f]'), '').toUpperCase();
    if (hexData.isEmpty) {
      onStatus?.call('Error: Empty cut file');
      return false;
    }
    
    // Ensure even length
    final cleanHex = hexData.length.isOdd ? '${hexData}0' : hexData;

    debugPrint('MietublCutSender: cleaned hex length=${cleanHex.length} (${cleanHex.length ~/ 2} bytes)');
    debugPrint('MietublCutSender: first 40: ${cleanHex.substring(0, cleanHex.length > 40 ? 40 : cleanHex.length)}');

    try {
      // Step 1: Build first command (metadata)
      onStatus?.call('Sending metadata...');
      final firstCmd = _buildFirstCommand(cleanHex.length, fileName);
      debugPrint('MietublCutSender: firstCmd length=${firstCmd.length}');
      await _sendHexPacket(firstCmd);
      await Future.delayed(const Duration(milliseconds: 500));

      // Step 2: Split hex data into chunks and send
      final chunks = _splitHexIntoChunks(cleanHex, _chunkSize);
      debugPrint('MietublCutSender: ${chunks.length} chunks to send');

      for (int i = 0; i < chunks.length; i++) {
        if (_cancelled) return false;

        final progress = ((i + 1) / chunks.length * 100).round();
        onProgress?.call(progress);
        onStatus?.call('Cutting: $progress%');

        final packet = _buildDataPacket(chunks[i], i, chunks.length);
        await _sendHexPacket(packet);

        // Small delay between packets for machine processing
        await Future.delayed(const Duration(milliseconds: 30));
      }

      onStatus?.call('Cut complete!');
      onProgress?.call(100);
      return true;
    } catch (e) {
      debugPrint('MietublCutSender ERROR: $e');
      onStatus?.call('Error: $e');
      return false;
    }
  }

  void cancel() {
    _cancelled = true;
  }

  /// Build the first command packet (metadata: file size + filename hash)
  /// Format: 9CC9 + payload + CRC + 0D0A
  /// Payload: CC 01 30 14 00 + length(4 LE bytes) + filenameChars(16 bytes)
  String _buildFirstCommand(int hexDataLength, String fileName) {
    // The data length represents the original PLT string length
    // Since hexData is hex-encoded, actual PLT length = hexData.length / 2... 
    // Actually looking at original code: convertNumber2(plt.length())
    // plt.length() is the CHARACTER count of the PLT text
    // But our file is already the hex-encoded version of ConvertString output
    // So the "plt length" = hexData.length / 2 (each byte was a char)
    final pltLength = hexDataLength ~/ 2;

    final payload = <int>[
      0xCC, 0x01, 0x30, 0x14, 0x00,
      // Length as 4 little-endian bytes
      pltLength & 0xFF,
      (pltLength >> 8) & 0xFF,
      (pltLength >> 16) & 0xFF,
      (pltLength >> 24) & 0xFF,
    ];

    // Filename: convert to 16 bytes (like Arrays.ConvertString("test", 16))
    final fileNameBytes = List<int>.filled(16, 0);
    final nameStr = 'test'; // Original uses fixed "test" string for filename hash
    for (int i = 0; i < nameStr.length && i < 16; i++) {
      fileNameBytes[i] = nameStr.codeUnitAt(i) & 0xFF;
    }
    payload.addAll(fileNameBytes);

    // Build hex string of payload
    final payloadHex = payload.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

    // CRC using SHA256
    final crcBytes = _calCRC(payload);
    final crcHex = crcBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

    return '9CC9${payloadHex}${crcHex}0D0A';
  }

  /// Build a data packet for a single chunk.
  /// Format: 9CC9CC + seq(2) + 30 + lenLo(2) + lenHi(2) + data + CRC(4) + 0D0A
  String _buildDataPacket(String chunkHex, int chunkIndex, int totalChunks) {
    final isLast = chunkIndex == totalChunks - 1;
    final dataByteCount = chunkHex.length ~/ 2;

    // Sequence number
    String seqHex;
    if (isLast) {
      seqHex = '00'; // Last packet marker
    } else {
      int seq = chunkIndex + 2;
      if (seq > 255) {
        seq = (((chunkIndex ~/ 253) * 2) + chunkIndex - 255) + 1;
      }
      seqHex = seq.toRadixString(16).padLeft(2, '0').toUpperCase();
    }

    // Length bytes (little-endian 16-bit)
    final lenLo = (dataByteCount & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();
    final lenHi = ((dataByteCount >> 8) & 0xFF).toRadixString(16).padLeft(2, '0').toUpperCase();

    // Build the inner payload for CRC calculation: CC + seq + 30 + lenLo + lenHi + data
    final innerPayload = 'CC$seqHex' '30$lenLo$lenHi$chunkHex';

    // Calculate CRC on the inner payload bytes
    final innerBytes = _hexStringToBytes(innerPayload);
    final crcBytes = _calCRC(innerBytes);
    final crcHex = crcBytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');

    // Full packet: 9CC9 + innerPayload + CRC + 0D0A
    return '9CC9$innerPayload${crcHex}0D0A';
  }

  /// SHA256-based CRC (matches original SerialPortSDK.calCRC)
  /// CRC = sha256(data + password), then sum first 16 bytes → crc[0], sum last 16 → crc[1]
  List<int> _calCRC(List<int> data) {
    final pwdBytes = _password.codeUnits;
    final combined = <int>[...data, ...pwdBytes];
    final hash = sha256.convert(combined).bytes;
    int crc0 = 0, crc1 = 0;
    for (int i = 0; i < 16; i++) {
      crc0 = (crc0 + hash[i]) & 0xFF;
      crc1 = (crc1 + hash[i + 16]) & 0xFF;
    }
    return [crc0, crc1];
  }

  /// Split hex string into chunks of given size
  List<String> _splitHexIntoChunks(String hexData, int chunkSize) {
    final chunks = <String>[];
    for (int i = 0; i < hexData.length; i += chunkSize) {
      final end = (i + chunkSize > hexData.length) ? hexData.length : i + chunkSize;
      chunks.add(hexData.substring(i, end));
    }
    return chunks;
  }

  /// Convert hex string to byte list
  List<int> _hexStringToBytes(String hex) {
    final bytes = <int>[];
    for (int i = 0; i < hex.length - 1; i += 2) {
      bytes.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return bytes;
  }

  /// Send a hex-string packet as raw bytes over serial
  Future<void> _sendHexPacket(String hexPacket) async {
    final bytes = _hexStringToBytes(hexPacket);
    await _serial.writeBytes(
      Uint8List.fromList(bytes),
      chunkSize: 64,
      packetDelayMs: 2,
    );
  }
}
