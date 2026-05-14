import 'dart:io';

import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import 'endpoints.dart';
import 'evaka_client.dart';
import 'models/message.dart';

class AttachmentsApi {
  AttachmentsApi(this._client);

  final EvakaClient _client;

  /// Lataa liite väliaikaistiedostoon ja palauttaa polun. Jos sama liite on
  /// jo ladattu, käyttää olemassa olevaa tiedostoa.
  Future<String> download(Attachment attachment) async {
    final dir = await getTemporaryDirectory();
    final safeName = attachment.name.replaceAll(RegExp(r'[/\\]'), '_');
    final file = File('${dir.path}/${attachment.id}_$safeName');

    if (await file.exists() && (await file.length()) > 0) {
      return file.path;
    }

    final resp = await _client.dio.get<List<int>>(
      EvakaEndpoints.attachmentDownload(attachment.id, attachment.name),
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = resp.data;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Tyhjä liite vastauksessa');
    }
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  /// Lähettää tiedoston eVakaan multipart/form-data -muodossa ja palauttaa
  /// luodun liitteen id:n. ID liitetään myöhemmin `createThread`-kutsun
  /// `attachmentIds`-listaan jotta liite kiinnittyy luotavaan viestiin.
  ///
  /// Jos käyttäjä peruu lähetyksen, kutsu [deleteAttachment] orpouden
  /// estämiseksi.
  Future<String> uploadMessageAttachment({
    required String filePath,
    required String filename,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(filePath, filename: filename),
    });
    final resp = await _client.dio.post(
      EvakaEndpoints.messageAttachmentUpload,
      data: form,
      options: Options(
        contentType: 'multipart/form-data',
      ),
    );
    final data = resp.data;
    if (data is String) {
      // eVaka palauttaa joskus quotatun stringin: "id-uuid"
      return data.replaceAll('"', '').trim();
    }
    if (data is Map && data['id'] is String) return data['id'] as String;
    return data.toString().replaceAll('"', '').trim();
  }

  Future<void> deleteAttachment(String attachmentId) async {
    await _client.dio.delete(EvakaEndpoints.attachmentDelete(attachmentId));
  }
}
