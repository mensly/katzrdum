import "package:pointycastle/export.dart";
import 'package:basic_utils/basic_utils.dart';

String encrypt(String message, Object? publicKey) =>
    CryptoUtils.rsaEncrypt(message, publicKey as RSAPublicKey);

String decrypt(String cipherMessage, Object? privateKey) =>
    CryptoUtils.rsaDecrypt(cipherMessage, privateKey as RSAPrivateKey);

RSAPublicKey parseClientKey(String key) {
  var pem =
      '${CryptoUtils.BEGIN_PUBLIC_KEY}\n$key\n${CryptoUtils.END_PUBLIC_KEY}';
  return CryptoUtils.rsaPublicKeyFromPem(pem);
}

String encodePublicKey(PublicKey publicKey) {
  final pem = CryptoUtils.encodeRSAPublicKeyToPem(publicKey as RSAPublicKey);
  final lines = pem.split('\n');
  return lines.sublist(1, lines.length - 1).join('\n');
}

final _intMax = BigInt.from(9223372036854775807);
String calculateCode(String encodedPublicKey) {
  var sum = BigInt.zero;
  for (final byte in encodedPublicKey.codeUnits) {
    sum = (sum + BigInt.from(byte)) % _intMax;
  }
  return sum.toRadixString(10).substring(1);
}
