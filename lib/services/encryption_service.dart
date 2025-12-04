import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class EncryptionService {
  final _algorithm = AesGcm.with256bits();

  Future<SecretKey> _getSecretKey() async {
    // 1. Fetch key from environment variables
    final base64Key = dotenv.env['SHARED_SECRET_KEY'];

    if (base64Key == null || base64Key.isEmpty) {
      throw Exception("❌ SHARED_SECRET_KEY not found in .env file");
    }

    // 2. Decode the Base64 string to bytes
    final keyBytes = base64Decode(base64Key);
    return SecretKey(keyBytes);
  }

  Future<String> encrypt(String plainText) async {
    final secretKey = await _getSecretKey();

    // 1. Convert text to bytes
    final messageBytes = utf8.encode(plainText);

    // 2. Encrypt (Generates a random nonce automatically)
    final secretBox = await _algorithm.encrypt(
      messageBytes,
      secretKey: secretKey,
    );

    // 3. Pack: Nonce + Ciphertext + Tag (MAC)
    // Note: secretBox.mac.bytes is the Tag
    final combined =
        secretBox.nonce + secretBox.cipherText + secretBox.mac.bytes;

    // 4. Return Base64
    return base64Encode(combined);
  }

  Future<String?> decrypt(String encryptedBase64) async {
    try {
      final secretKey = await _getSecretKey();

      // 1. Decode Base64
      final data = base64Decode(encryptedBase64);

      // 2. Unpack
      // GCM Nonce is 12 bytes
      final nonce = data.sublist(0, 12);
      // Tag (MAC) is last 16 bytes
      final tag = data.sublist(data.length - 16);
      // Ciphertext
      final ciphertext = data.sublist(12, data.length - 16);

      // 3. Reconstruct SecretBox
      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(tag));

      // 4. Decrypt
      final decryptedBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return utf8.decode(decryptedBytes);
    } catch (e) {
      print("Decryption error: $e");
      return null;
    }
  }
}
