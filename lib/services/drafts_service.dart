import 'dart:io';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/post_models.dart';
import 'app_config.dart';
import 'content_service.dart';
import 'storage_upload.dart';
import 'supabase_service.dart';

/// Rascunho de publicação (privado; nunca aparece no feed/perfil).
class Draft {
  final String id;
  final String videoPath;
  final String coverPath;
  final String description;
  final String audioName;
  final List<String> hashtags;
  final String location;
  final int durationSeconds;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Post do feed criado pela publicação (idempotência: evita duplicar).
  final String postId;

  const Draft({
    required this.id,
    this.videoPath = '',
    this.coverPath = '',
    this.description = '',
    this.audioName = '',
    this.hashtags = const [],
    this.location = '',
    this.durationSeconds = 0,
    this.postId = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory Draft.fromMap(Map<String, dynamic> json) => Draft(
    id: json['id']?.toString() ?? '',
    videoPath: json['video_path']?.toString() ?? '',
    coverPath: json['cover_path']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    audioName: json['audio_name']?.toString() ?? '',
    hashtags:
        (json['hashtags'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    location: json['location']?.toString() ?? '',
    durationSeconds: (json['duration_seconds'] as num?)?.toInt() ?? 0,
    postId: json['post_id']?.toString() ?? '',
    createdAt:
        DateTime.tryParse(json['created_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
    updatedAt:
        DateTime.tryParse(json['updated_at']?.toString() ?? '')?.toLocal() ??
        DateTime.now(),
  );
}

/// Contrato de armazenamento de rascunhos. [DraftsService] é a implementação
/// real (Supabase); as telas aceitam um [DraftStore] injetado e os testes de
/// widget usam um fake determinístico (sem tocar a rede).
abstract class DraftStore {
  Future<List<Draft>> list();
  Future<Draft?> get(String id);
  Future<Draft> create({
    String videoPath,
    String coverPath,
    String description,
    String audioName,
    List<String> hashtags,
    String location,
    int durationSeconds,
  });
  Future<void> update(
    Draft d, {
    String? videoPath,
    String? coverPath,
    String? description,
    String? audioName,
    List<String>? hashtags,
    String? location,
    int? durationSeconds,
    String? postId,
  });
  Future<void> remove(String id);
  Future<void> markPublished(String id);
  Future<String> uploadVideoBytes(
    String path,
    Uint8List bytes, {
    String contentType,
  });
  Future<String> uploadVideoFile(
    File file, {
    String? contentType,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  });
  Future<String> uploadCoverBytes(
    String path,
    Uint8List bytes, {
    String contentType,
  });
  Future<String?> temporaryUrl(Draft d);
  Future<FeedPost?> publish(String draftId);
}

/// Serviço de rascunhos. Vídeos/capas ficam no bucket privado `drafts`
/// (`{uid}/...`); metadados na tabela `drafts` com RLS de dono. Publicar um
/// rascunho "finaliza" o row (status published) e o cliente carrega o vídeo
/// para o fluxo normal de publicação do feed.
class DraftsService implements DraftStore {
  DraftsService._();

  static final DraftsService instance = DraftsService._();

  SupabaseClient get _db => SupabaseService.instance.client;

  Future<String> _uid() async {
    final u = await SupabaseService.instance.ensureAuthenticated();
    return u.id;
  }

  // ---------------------------------------------------------------------------
  // Metadados
  // ---------------------------------------------------------------------------

  @override
  Future<List<Draft>> list() async {
    final uid = await _uid();
    try {
      final res = await _db
          .from('drafts')
          .select()
          .eq('user_id', uid)
          .neq('status', 'published')
          .order('updated_at', ascending: false);
      return (res as List)
          .whereType<Map>()
          .map((m) => Draft.fromMap(_stringMap(m)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<Draft?> get(String id) async {
    final uid = await _uid();
    try {
      final res = await _db
          .from('drafts')
          .select()
          .eq('id', id)
          .eq('user_id', uid)
          .maybeSingle();
      if (res == null) return null;
      return Draft.fromMap(_stringMap(res));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Draft> create({
    String videoPath = '',
    String coverPath = '',
    String description = '',
    String audioName = '',
    List<String> hashtags = const [],
    String location = '',
    int durationSeconds = 0,
  }) async {
    final uid = await _uid();
    final now = DateTime.now().toUtc().toIso8601String();
    final res = await _db
        .from('drafts')
        .insert({
          'user_id': uid,
          'video_path': videoPath,
          'cover_path': coverPath,
          'description': description,
          'audio_name': audioName,
          'hashtags': hashtags,
          'location': location,
          'duration_seconds': durationSeconds,
          'created_at': now,
          'updated_at': now,
        })
        .select()
        .single();
    return Draft.fromMap(_stringMap(res));
  }

  @override
  Future<void> update(
    Draft d, {
    String? videoPath,
    String? coverPath,
    String? description,
    String? audioName,
    List<String>? hashtags,
    String? location,
    int? durationSeconds,
    String? postId,
  }) async {
    final uid = await _uid();
    final now = DateTime.now().toUtc().toIso8601String();
    final patch = <String, dynamic>{'user_id': uid, 'updated_at': now};
    if (videoPath != null) patch['video_path'] = videoPath;
    if (coverPath != null) patch['cover_path'] = coverPath;
    if (description != null) patch['description'] = description;
    if (audioName != null) patch['audio_name'] = audioName;
    if (hashtags != null) patch['hashtags'] = hashtags;
    if (location != null) patch['location'] = location;
    if (durationSeconds != null) patch['duration_seconds'] = durationSeconds;
    if (postId != null) patch['post_id'] = postId;
    await _db.from('drafts').update(patch).eq('id', d.id).eq('user_id', uid);
  }

  @override
  Future<void> remove(String id) async {
    final uid = await _uid();
    try {
      final d = await get(id);
      if (d != null && d.videoPath.isNotEmpty) {
        await _db.storage.from('drafts').remove([d.videoPath]);
      }
      if (d != null && d.coverPath.isNotEmpty) {
        await _db.storage.from('drafts').remove([d.coverPath]);
      }
    } catch (_) {}
    await _db.from('drafts').delete().eq('id', id).eq('user_id', uid);
  }

  /// Marca como publicado (o post real foi criado no feed normal).
  @override
  Future<void> markPublished(String id) async {
    final uid = await _uid();
    await _db
        .from('drafts')
        .update({
          'status': 'published',
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', id)
        .eq('user_id', uid);
  }

  // ---------------------------------------------------------------------------
  // Armazenamento privado
  // ---------------------------------------------------------------------------

  Future<String> uploadVideo(String path, String mime) async {
    final uid = await _uid();
    final signed = await _db.storage
        .from('drafts')
        .createSignedUploadUrl('$uid/videos/$path');
    return signed.token;
  }

  /// Sobe o vídeo no bucket privado `{uid}/videos/{path}` e devolve o caminho
  /// completo (a ser gravado em `drafts.video_path`).
  @override
  Future<String> uploadVideoBytes(
    String path,
    Uint8List bytes, {
    String contentType = 'video/mp4',
  }) async {
    final uid = await _uid();
    final full = '$uid/videos/$path';
    await _db.storage
        .from('drafts')
        .uploadBinary(
          full,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return full;
  }

  /// Sob o vídeo por STREAM (sem `readAsBytes` do arquivo inteiro na memória),
  /// no bucket privado `{uid}/videos/{nome}`. Implantado no `_saveDraft` —
  /// mesma otimização do feed (progresso real + cancelamento).
  @override
  Future<String> uploadVideoFile(
    File file, {
    String? contentType,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final uid = await _uid();
    final full =
        '$uid/videos/${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
    final db = SupabaseService.instance;
    final token = db.client.auth.currentSession?.accessToken;
    if (token == null || token.isEmpty) {
      throw StateError('Sessão ausente para o upload do vídeo.');
    }
    await streamUploadFile(
      supabaseUrl: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseKey,
      accessToken: token,
      bucket: 'drafts',
      objectPath: full,
      file: file,
      contentType: contentType ?? 'video/mp4',
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    return full;
  }

  /// Sobe a capa no bucket privado `{uid}/covers/{path}` e devolve o caminho
  /// completo (a ser gravado em `drafts.cover_path`).
  @override
  Future<String> uploadCoverBytes(
    String path,
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async {
    final uid = await _uid();
    final full = '$uid/covers/$path';
    await _db.storage
        .from('drafts')
        .uploadBinary(
          full,
          bytes,
          fileOptions: FileOptions(contentType: contentType, upsert: true),
        );
    return full;
  }

  @override
  Future<String?> temporaryUrl(Draft d) async {
    if (d.videoPath.isEmpty) return null;
    try {
      final r = await _db.storage
          .from('drafts')
          .createSignedUrl(d.videoPath, 3600);
      return r;
    } catch (_) {
      return null;
    }
  }

  /// Publica um rascunho: baixa a mídia do bucket privado, reenvia para o
  /// bucket público (videos/covers) e cria o post no feed. Idempotente: o
  /// `post_id` gravado no rascunho impede criar o mesmo post duas vezes (se o
  /// post ainda existe, devolve-o sem re-publicar).
  @override
  Future<FeedPost?> publish(String draftId) async {
    final d = await get(draftId);
    if (d == null) return null;
    final uid = await _uid();

    // Já publicado? Reutiliza o post existente (sem reenviar a mídia).
    if (d.postId.isNotEmpty) {
      try {
        final existing = await _db
            .from('posts')
            .select('*')
            .eq('id', d.postId)
            .eq('user_id', uid)
            .maybeSingle();
        if (existing != null) {
          await markPublished(d.id);
          return FeedPost.fromJson(_stringMap(existing));
        }
      } catch (_) {
        // Post desapareceu: recria a partir do rascunho.
      }
    }

    String? videoPath;
    if (d.videoPath.isNotEmpty) {
      final bytes = await _db.storage.from('drafts').download(d.videoPath);
      final path = await _uploadBytesToPublic(
        bucket: 'videos',
        path: d.videoPath,
        bytes: bytes,
        contentType: 'video/mp4',
      );
      videoPath = path;
    }

    String? coverUrl;
    if (d.coverPath.isNotEmpty) {
      final bytes = await _db.storage.from('drafts').download(d.coverPath);
      final coverPath = await _uploadBytesToPublic(
        bucket: 'covers',
        path: d.coverPath,
        bytes: bytes,
        contentType: _coverMime(d.coverPath),
      );
      coverUrl = _db.storage.from('covers').getPublicUrl(coverPath);
    }

    final post = await ContentService.instance.createPost(
      videoPath: videoPath ?? d.videoPath,
      coverUrl: coverUrl,
      description: d.description,
      audioName: d.audioName.isEmpty ? null : d.audioName,
      hashtags: d.hashtags,
    );
    await update(d, postId: post.id);
    await markPublished(d.id);
    return post;
  }

  Future<String> _uploadBytesToPublic({
    required String bucket,
    required String path,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final uid = await _uid();
    final name = path.split('/').last;
    final newPath = '$uid/${DateTime.now().millisecondsSinceEpoch}_$name';
    await _db.storage
        .from(bucket)
        .uploadBinary(
          newPath,
          bytes,
          fileOptions: FileOptions(
            contentType: contentType,
            cacheControl: '3600',
            upsert: false,
          ),
        );
    return newPath;
  }

  static String _coverMime(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.jpg') || p.endsWith('.jpeg')) return 'image/jpeg';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.gif')) return 'image/gif';
    if (p.endsWith('.png')) return 'image/png';
    return 'image/jpeg';
  }

  Map<String, dynamic> _stringMap(Map<dynamic, dynamic> m) =>
      m.map((k, v) => MapEntry(k.toString(), v));
}
