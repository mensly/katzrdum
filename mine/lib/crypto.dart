import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import "package:pointycastle/export.dart";
import 'package:basic_utils/basic_utils.dart';
import 'dart:convert' show base64Decode, utf8;

const secretKeySize = 512;

Future<AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey>> generateKeyPair() {
  return compute(_generateKeyPair, 4096);
}

AsymmetricKeyPair<RSAPublicKey, RSAPrivateKey> _generateKeyPair(int keySize) {
  final pair = CryptoUtils.generateRSAKeyPair(keySize: keySize);
  return AsymmetricKeyPair(pair.publicKey as RSAPublicKey, pair.privateKey as RSAPrivateKey);
}

Uint8List decryptSecretKey(Uint8List cipherData, RSAPrivateKey privateKey) {
  var cipher = PKCS1Encoding(RSAEngine());
  cipher.init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  try {
    return cipher.process(cipherData);
  } catch (e) {
    debugPrint('crypto error $e');
    rethrow;
  }
}

Uint8List _process(bool forEncryption, Uint8List cipherData, Uint8List secretKey, Uint8List iv) {
  final cbcCipher = CBCBlockCipher(AESEngine());
  final ivParams = ParametersWithIV<KeyParameter>(KeyParameter(secretKey), iv);
  final paddingParams = PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>, Null>(ivParams, null);
  final PaddedBlockCipherImpl paddedCipher = PaddedBlockCipherImpl(PKCS7Padding(), cbcCipher);
  paddedCipher.init(forEncryption, paddingParams);
  try {
    return paddedCipher.process(cipherData);
  } catch (e) {
    debugPrint('crypto error $e');
    rethrow;
  }
}


Uint8List encryptString(String cipherMessage, Uint8List secretKey, Uint8List iv) => _process(true, Uint8List.fromList(utf8.encode(cipherMessage)), secretKey, iv);
String decryptString(Uint8List cipherData, Uint8List secretKey, Uint8List iv) => utf8.decode(_process(false, cipherData, secretKey, iv));

String encodePublicKey(PublicKey publicKey) {
  final pem = CryptoUtils.encodeRSAPublicKeyToPem(publicKey as RSAPublicKey);
  final lines = pem.split('\n');
  return lines.sublist(1, lines.length - 1).join('\n');
}

final _intMax = BigInt.parse("9223372036854775807");
String calculateCode(String encodedPublicKey) {
  var sum = BigInt.zero;
  for (final byte in utf8.encode(encodedPublicKey)) {
    sum = (sum + BigInt.from(byte)) % _intMax;
  }
  return sum.toRadixString(10).substring(1);
}

Uint8List calculateIv(String encodedPublicKey) {
  final firstLineEnd = encodedPublicKey.indexOf('\n');
  return Uint8List.fromList(base64Decode(encodedPublicKey.substring(0, firstLineEnd)).sublist(0, 16));
}