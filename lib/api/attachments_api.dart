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
}
