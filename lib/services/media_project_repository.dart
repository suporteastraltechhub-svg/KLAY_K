import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/media_creation_models.dart';
import 'drafts_service.dart';
import 'supabase_service.dart';

/// Repositório de projetos de mídia para o fluxo de criação.
///
/// **Não substitui** o [DraftStore] existente: envolve-o. O `DraftStore`
/// continua sendo quem fala com a tabela `drafts` e o bucket privado, com o
/// mesmo upload e o mesmo `publish` — nenhuma linha é duplicada e nenhuma
/// funcionalidade é reimplementada.
///
/// O que esta camada acrescenta:
///  * os 5 estados reais ([MediaProjectStatus]);
///  * persistência dos efeitos aplicados e das faixas/vVolumes escolhidos,
///    que antes não eram guardados em lugar nenhum;
///  * o arquivo de vídeo **sempre** em disco local — só a referência vai para
///    o banco. Rascunho não se perde ao fechar a tela.
class MediaProjectRepository {
MediaProjectRepository({DraftStore? store, Directory? sidecarDir})
  : _store = store ?? DraftsService.instance,
    _sidecarRoot = sidecarDir;
  final DraftStore _store;
  SupabaseClient get _client => SupabaseService.instance.client;
  Map<String, dynamic> _strMap(Map<dynamic, dynamic> m) =>
      m.map((k, v) => MapEntry(k.toString(), v));
  /// Onde ficam os sidecars. Injetável para que os testes não compartilhem
  /// diretório — com um diretório fixo, dois testes com o mesmo id de rascunho
  /// sobrescrevem o estado um do outro.
  final Directory? _sidecarRoot;
  /// Onde os efeitos/ajustes são guardados enquanto o usuário cria.
  ///
  /// Fica ao lado do vídeo local, não no banco: é estado de trabalho. A linha
  /// `drafts` guarda o que importa para recuperar o rascunho depois.
  File _sidecarFile(String draftId) {
    final root =
        _sidecarRoot ??
        Directory('${Directory.systemTemp.path}/klayk_projects');
    if (!root.existsSync()) root.createSync(recursive: true);
    return File('${root.path}/$draftId.json');
  }
  /// Salva (ou atualiza) um projeto e devolve o rascunho persistido.
  ///
  /// [project.videoPath] deve ser um caminho **local**. Se o usuário gravou um
  /// vídeo, esse arquivo fica no aparelho e a linha guarda a referência.
  Future<Draft> save(MediaProjectModel project) async {
    final row = project.toDraftRow();
    final existing = project.id.isEmpty
        ? null
        : await _safeGet(project.id);
    if (existing == null) {
      final created = await _store.create(
        videoPath: project.videoPath ?? '',
        coverPath: project.thumbnailPath ?? '',
        description: project.description,
        audioName: project.track?.title ?? '',
        hashtags: project.hashtags,
        durationSeconds: row['duration_seconds'] as int? ?? 0,
      );
      // Só grava o sidecar depois de ter o id: o arquivo é nomeado pelo id
      // do rascunho, e na primeira gravação o projeto ainda não tem um.
      await _writeSidecar(project.copyWith(id: created.id));
      return created;
    }
    await _store.update(
      existing,
      videoPath: project.videoPath,
      coverPath: project.thumbnailPath,
      description: project.description,
      audioName: project.track?.title ?? '',
      hashtags: project.hashtags,
      durationSeconds: row['duration_seconds'] as int? ?? 0,
    );
    await _writeSidecar(project);
    return existing;
  }
  /// Recupera um projeto. Os campos extras vêm do sidecar; se ele sumiu
  /// (app limpo), o rascunho ainda é recuperável com o que está no banco.
  Future<MediaProjectModel?> load(String draftId) async {
    final d = await _safeGet(draftId);
    if (d == null) return null;
    final side = await _readSidecar(draftId);
    return MediaProjectModel(
      id: d.id,
      videoPath: d.videoPath.isEmpty ? null : d.videoPath,
      thumbnailPath: d.coverPath.isEmpty ? null : d.coverPath,
      description: d.description,
      hashtags: d.hashtags,
      effectIds: side?.effectIds ?? const [],
      trackVolume: side?.trackVolume ?? 0.6,
      originalVolume: side?.originalVolume ?? 0.3,
      trimStart: side?.trimStart,
      trimEnd: side?.trimEnd,
      status: side?.status ?? MediaProjectStatus.draft,
      createdAt: d.createdAt,
      updatedAt: d.updatedAt,
    );
  }
  /// Rascunhos do usuário, convertidos para projeto. Não inclui publicados.
  Future<List<MediaProjectModel>> listDrafts() async {
    final all = await _safeList();
    final out = <MediaProjectModel>[];
    for (final d in all) {
      // `Draft` do serviço existente não traz `status`; published é marcado
      // por `post_id` preenchido (ver DraftsService.markPublished).
      if (d.postId.isNotEmpty) continue;
      final side = await _readSidecar(d.id);
      out.add(
        MediaProjectModel(
          id: d.id,
          videoPath: d.videoPath.isEmpty ? null : d.videoPath,
          thumbnailPath: d.coverPath.isEmpty ? null : d.coverPath,
          description: d.description,
          hashtags: d.hashtags,
          effectIds: side?.effectIds ?? const [],
          trackVolume: side?.trackVolume ?? 0.6,
          originalVolume: side?.originalVolume ?? 0.3,
          trimStart: side?.trimStart,
          trimEnd: side?.trimEnd,
          status: side?.status ?? MediaProjectStatus.draft,
          createdAt: d.createdAt,
          updatedAt: d.updatedAt,
        ),
      );
    }
    out.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return out;
  }
  /// Exclui o rascunho e o sidecar. Confirmação é responsabilidade da UI.
  Future<bool> delete(String draftId) async {
    try {
      final f = _sidecarFile(draftId);
      if (f.existsSync()) f.deleteSync();
    } catch (_) {}
    await _safeRemove(draftId);
    return true;
  }
  /// Marca como pronto para publicar (estado [MediaProjectStatus.readyToPublish]).
  ///
  /// O estado vai para o banco pela RPC `set_draft_status` (migration
  /// `20261001090000_draft_states.sql`), que valida a transição no servidor. O
  /// sidecar é atualizado em paralelo: se a RPC ainda não existir, o estado
  /// continua sobrevivendo no aparelho.
  Future<MediaProjectModel> markReady(MediaProjectModel project) =>
      _setStatus(project, MediaProjectStatus.readyToPublish);
  Future<MediaProjectModel> markEditing(MediaProjectModel project) =>
      _setStatus(project, MediaProjectStatus.editing);
  Future<MediaProjectModel> markDraft(MediaProjectModel project) =>
      _setStatus(project, MediaProjectStatus.draft);
  Future<MediaProjectModel> _setStatus(
    MediaProjectModel project,
    MediaProjectStatus status,
  ) async {
    final next = project.copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );
    // Lado local primeiro: garante o estado mesmo sem backend.
    await _writeSidecar(next);
    if (project.id.isNotEmpty) {
      try {
        await _client.rpc(
          'set_draft_status',
          params: {'p_draft_id': project.id, 'p_status': status.storageKey},
        );
      } catch (_) {
        // RPC ausente ou offline: o sidecar já garante o estado local.
      }
    }
    return next;
  }
  /// Rascunhos visíveis para edição: usa a view que normaliza o legado.
  Future<List<MediaProjectModel>> listEditable() async {
    try {
      final r = await _client
          .from('drafts_active_view')
          .select()
          .order('updated_at', ascending: false)
          .limit(100);
      if (r.isNotEmpty) {
        final out = <MediaProjectModel>[];
        for (final row in r.whereType<Map>()) {
          final m = _strMap(row);
          final id = m['id']?.toString() ?? '';
          final side = await _readSidecar(id);
          out.add(
            MediaProjectModel(
              id: id,
              videoPath: m['video_path']?.toString(),
              thumbnailPath: m['cover_path']?.toString(),
              description: m['description']?.toString() ?? '',
              hashtags:
                  (m['hashtags'] as List?)
                      ?.map((e) => e.toString())
                      .toList() ??
                  const [],
              effectIds: side?.effectIds ?? const [],
              trackVolume: side?.trackVolume ?? 0.6,
              originalVolume: side?.originalVolume ?? 0.3,
              status: MediaProjectStatus.fromStorageKey(
                m['status']?.toString(),
              ),
              createdAt:
                  DateTime.tryParse(m['created_at']?.toString() ?? '') ??
                  DateTime.now(),
              updatedAt:
                  DateTime.tryParse(m['updated_at']?.toString() ?? '') ??
                  DateTime.now(),
            ),
          );
        }
        return out;
      }
    } catch (_) {
      // Sem backend: cai na listagem local abaixo.
    }
    return listDrafts();
  }
  /// Publica pelo serviço existente — sem duplicar o caminho de upload/post.
  Future<String?> publish(String draftId) async {
    try {
      final post = await _store.publish(draftId);
      try {
        final f = _sidecarFile(draftId);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      return post?.id;
    } catch (_) {
      return null;
    }
  }
  // ---------------------------------------------------------------------------
  // Sidecar: estado de trabalho em disco
  // ---------------------------------------------------------------------------
  Future<void> _writeSidecar(MediaProjectModel p) async {
    try {
      final f = _sidecarFile(p.id);
      await f.writeAsString(
        '{"effectIds":[${_jsonList(p.effectIds)}],'
        '"trackId":"${p.track?.id ?? ''}",'
        '"trackVolume":${p.trackVolume},'
        '"originalVolume":${p.originalVolume},'
        '"trimStartMs":${p.trimStart?.inMilliseconds ?? -1},'
        '"trimEndMs":${p.trimEnd?.inMilliseconds ?? -1},'
        '"status":"${p.status.storageKey}"}',
      );
    } catch (_) {
      // Sem sidecar o rascunho ainda é recuperável pelo banco; não é fatal.
    }
  }
  Future<_Sidecar?> _readSidecar(String id) async {
    try {
      final f = _sidecarFile(id);
      if (!f.existsSync()) return null;
      final raw = await f.readAsString();
      final effects = RegExp(r'"effectIds":\[(.*?)\]').firstMatch(raw)?.group(1);
      final ids = effects == null || effects.trim().isEmpty
          ? const <String>[]
          : effects
                .split(',')
                .map((e) => e.trim().replaceAll('"', ''))
                .where((e) => e.isNotEmpty)
                .toList();
      int ms(String k) =>
          int.tryParse(RegExp('"$k":(-?\\d+)').firstMatch(raw)?.group(1) ?? '') ??
          -1;
      final st = RegExp('"status":"([a-z_]+)"').firstMatch(raw)?.group(1);
      return _Sidecar(
        effectIds: ids,
        trackVolume:
            double.tryParse(
              RegExp('"trackVolume":([0-9.]+)').firstMatch(raw)?.group(1) ?? '',
            ) ??
            0.6,
        originalVolume:
            double.tryParse(
              RegExp('"originalVolume":([0-9.]+)')
                  .firstMatch(raw)
                  ?.group(1) ??
                  '',
            ) ??
            0.3,
        trimStart: ms('trimStartMs') >= 0
            ? Duration(milliseconds: ms('trimStartMs'))
            : null,
        trimEnd: ms('trimEndMs') >= 0
            ? Duration(milliseconds: ms('trimEndMs'))
            : null,
        status: MediaProjectStatus.fromStorageKey(st),
      );
    } catch (_) {
      return null;
    }
  }
  static String _jsonList(List<String> xs) =>
      xs.map((e) => '"${e.replaceAll('"', '')}"').join(',');
  // ---------------------------------------------------------------------------
  // Falhas de rede não podem derrubar o fluxo de criação
  // ---------------------------------------------------------------------------
  Future<Draft?> _safeGet(String id) async {
    try {
      return await _store.get(id);
    } catch (_) {
      return null;
    }
  }
  Future<List<Draft>> _safeList() async {
    try {
      return await _store.list();
    } catch (_) {
      return const [];
    }
  }
  Future<void> _safeRemove(String id) async {
    try {
      await _store.remove(id);
    } catch (_) {}
  }
}
class _Sidecar {
  final List<String> effectIds;
  final double trackVolume;
  final double originalVolume;
  final Duration? trimStart;
  final Duration? trimEnd;
  final MediaProjectStatus status;
  const _Sidecar({
    required this.effectIds,
    required this.trackVolume,
    required this.originalVolume,
    this.trimStart,
    this.trimEnd,
    this.status = MediaProjectStatus.draft,
  });
}
