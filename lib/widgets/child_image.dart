import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/endpoints.dart';
import '../state/app_state.dart';

/// Session-aikaan cachettu raaka tavulataus per imageId.
/// Säilyy app-instanssin eliniän — ei tallenneta levylle.
final _imageCacheProvider =
    FutureProvider.family<Uint8List?, String>((ref, imageId) async {
  final dio = ref.watch(evakaClientProvider).dio;
  try {
    final resp = await dio.get<List<int>>(
      EvakaEndpoints.childImage(imageId),
      options: Options(responseType: ResponseType.bytes),
    );
    final bytes = resp.data;
    if (bytes == null || bytes.isEmpty) return null;
    return Uint8List.fromList(bytes);
  } on DioException {
    return null;
  }
});

/// Lapsen kuva ympyränä. Jos [imageId] on null tai lataus epäonnistuu,
/// näyttää kirjaimen avatarin.
class ChildImage extends ConsumerWidget {
  const ChildImage({
    super.key,
    required this.imageId,
    required this.fallbackLetter,
    this.radius = 20,
  });

  final String? imageId;
  final String fallbackLetter;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (imageId == null) return _fallback(context);
    final async = ref.watch(_imageCacheProvider(imageId!));
    return async.when(
      loading: () => CircleAvatar(
        radius: radius,
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      ),
      error: (_, _) => _fallback(context),
      data: (bytes) {
        if (bytes == null) return _fallback(context);
        return CircleAvatar(
          radius: radius,
          backgroundImage: MemoryImage(bytes),
        );
      },
    );
  }

  Widget _fallback(BuildContext context) {
    final theme = Theme.of(context);
    return CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primaryContainer,
      child: Text(
        fallbackLetter.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
