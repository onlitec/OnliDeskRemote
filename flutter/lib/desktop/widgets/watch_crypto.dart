// Criptografia compartilhada do OnliDeskWhatch (lado Flutter).
//
// DEVE produzir/consumir exatamente os mesmos formatos do módulo Rust
// `OnliDeskWhatch/src/crypto.rs`:
//
//  - Senha admin local (`admin_password_hash`): `sha256$<salt_hex>$<hash_hex>`,
//    hash = SHA256(salt_bytes || password_utf8), salt de 16 bytes.
//  - Senha do Mikrotik (`mikrotik_password`): `enc:v1:<iv_b64>:<ct_b64>`,
//    AES-256-CBC + PKCS7, IV de 16 bytes aleatório, com a chave fixa abaixo.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;

// Mesma chave AES-256 (32 bytes) do SECRET_KEY em crypto.rs
final Uint8List _secretKey = Uint8List.fromList([
  0x5f, 0x2b, 0x9c, 0x1e, 0x7a, 0x4d, 0x80, 0x36, 0xb1, 0xe9, 0xf6, 0xc2, 0xa7, 0x0d, 0x53, 0x84,
  0xe2, 0xb8, 0xf1, 0x4c, 0x9d, 0x63, 0xa0, 0x5e, 0x71, 0x82, 0xc4, 0xf6, 0xb3, 0xa9, 0xd0, 0xe5,
]);

const String _encPrefix = 'enc:v1:';

final Random _rng = Random.secure();

Uint8List _randomBytes(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = _rng.nextInt(256);
  }
  return b;
}

/// Gera o hash salgado da senha do administrador local.
String hashAdminPassword(String password) {
  final salt = _randomBytes(16);
  final digest = _sha256Salted(salt, password);
  return 'sha256\$${_toHex(salt)}\$${_toHex(digest)}';
}

/// Verifica a senha contra o valor armazenado. Aceita valor legado em texto plano.
bool verifyAdminPassword(String password, String stored) {
  final parts = stored.split('\$');
  if (parts.length == 3 && parts[0] == 'sha256') {
    try {
      final salt = _fromHex(parts[1]);
      final digest = _sha256Salted(salt, password);
      return _toHex(digest) == parts[2];
    } catch (_) {
      return false;
    }
  }
  // Compatibilidade: config antiga em texto plano
  return stored == password;
}

List<int> _sha256Salted(Uint8List salt, String password) {
  final input = <int>[]
    ..addAll(salt)
    ..addAll(utf8.encode(password));
  return crypto.sha256.convert(input).bytes;
}

/// Cifra um segredo no formato `enc:v1:<iv_b64>:<ct_b64>`. Vazio -> vazio.
String encryptSecret(String plain) {
  if (plain.isEmpty) return '';
  final iv = enc.IV(_randomBytes(16));
  final encrypter = enc.Encrypter(
    enc.AES(enc.Key(_secretKey), mode: enc.AESMode.cbc, padding: 'PKCS7'),
  );
  final encrypted = encrypter.encrypt(plain, iv: iv);
  return '$_encPrefix${base64.encode(iv.bytes)}:${encrypted.base64}';
}

/// Decifra um segredo. Sem o prefixo `enc:v1:` retorna o valor como texto plano
/// (compatibilidade). Falha de decifragem retorna string vazia.
String decryptSecret(String stored) {
  if (!stored.startsWith(_encPrefix)) return stored;
  final rest = stored.substring(_encPrefix.length);
  final i = rest.indexOf(':');
  if (i < 0) return '';
  try {
    final iv = enc.IV(base64.decode(rest.substring(0, i)));
    final ct = enc.Encrypted(base64.decode(rest.substring(i + 1)));
    final encrypter = enc.Encrypter(
      enc.AES(enc.Key(_secretKey), mode: enc.AESMode.cbc, padding: 'PKCS7'),
    );
    return encrypter.decrypt(ct, iv: iv);
  } catch (_) {
    return '';
  }
}

String _toHex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _fromHex(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}
