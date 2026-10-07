import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';
import '../../models/media_creation_models.dart';
import '../../services/media_project_repository.dart';
import '../drafts_screen.dart';
import 'create_screen.dart';

/// Tela de publicação usada pelo fluxo.
///
/// É um callback, não um import: `UploadScreen` é uma classe **interna de
/// `lib/main.dart`** e importá-lo aqui criaria um ciclo de dependência entre
/// a raiz do app e o fluxo de criação. O `main.dart` injeta a tela ao abrir o
/// fluxo, e aqui só sabemos que ela aceita `preselectedVideo`.
typedef PublishScreenBuilder = Widget Function(String preselectedVideo);

/// Ponte entre a tela de criação e os sistemas que já existiam.
///
/// Não substitui nada: quem publica é o [UploadScreen] (upload, descrição,
/// hashtags, capa) e quem guarda rascunho é o `DraftsService` real, através
/// do [MediaProjectRepository]. A tela de câmera só produz um arquivo local.
class KlaykCreationFlow {
  KlaykCreationFlow._();

  static final KlaykCreationFlow instance = KlaykCreationFlow._();

  /// Injetado por `main.dart` (ver [publishScreenBuilder]).
  PublishScreenBuilder? _publishScreen;

  /// Registra qual widget abrir na hora de publicar.
  ///
  /// [main.dart] chama isto na inicialização porque [UploadScreen] mora
  /// naquele arquivo; assim o fluxo não depende da raiz do app.
  void registerPublishScreen(PublishScreenBuilder builder) =>
      _publishScreen = builder;

  MediaProjectRepository get _repo => MediaProjectRepository();

  /// Abre o fluxo a partir de qualquer tela.
  ///
  /// Grava/seleciona → publica pelo [UploadScreen] **existente**, que agora
  /// aceita `preselectedVideo` e entra direto na revisão com o upload já
  /// iniciado. Se o usuário voltar sem publicar, oferecemos o rascunho: o
  /// arquivo já está em disco e a linha é criada na hora.
  Future<void> open(BuildContext context) async {
    final l10n = AppLocalizations.of(context);

    // Quem chama quando há vídeo pronto (gravado OU vindo da galeria).
    // Devolve `true` se a publicação consumiu o arquivo, para a tela de
    // câmera fechar em vez de voltar vazia para o usuário.
    final opened = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (routeContext) => KlaykCreateScreen(
          // Gravar e Galeria passam pelo MESMO caminho: este callback.
          onCaptured: (r) => _openPublishFor(routeContext, r, l10n),
          onPickFromGallery: pickFromGallery,
        ),
      ),
    );
    if (opened == true) return;

    // Fechou a câmera sem publicar (X). Sem vídeo não há o que revisar.
    if (!context.mounted) return;
  }

  /// Leva o vídeo escolhido para a tela de publicação existente.
  ///
  /// É o único destino tanto para gravação quanto para galeria: mesma
  /// `UploadScreen`, mesmo `preselectedVideo`, mesmo upload progressivo
  /// (que já roda em `_adoptVideo` dentro da tela de publicação).
  Future<bool> _openPublishFor(
    BuildContext screenContext,
    CaptureResult result,
    AppLocalizations? l10n,
  ) async {
    if (!screenContext.mounted) return false;
    if (!fileExists(result.videoPath)) return false;

    final builder = _publishScreen;
    if (builder != null) {
      final published = await Navigator.of(screenContext).push<bool>(
        MaterialPageRoute(builder: (_) => builder(result.videoPath)),
      );
// Saiu da publicação por cima da câmera: remove a câmera do fluxo,
        // em vez de deixar o usuário cair de volta nela.
        if (screenContext.mounted) {
          Navigator.of(screenContext).pop(published == true);
        }
        return published == true;
    }

    // Sem tela de publicação injetada (fluxo aberto fora do app, teste):
    // o caminho seguro é guardar como rascunho.
    final saved = await saveAsDraft(result);
    if (!screenContext.mounted) return false;
    ScaffoldMessenger.of(screenContext).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? (l10n?.draftSavedShort ?? 'Rascunho salvo.')
              : (l10n?.draftSaveFail ?? 'Não foi possível salvar o rascunho.'),
        ),
      ),
    );
    if (saved) Navigator.of(screenContext).pop(true);
    return saved;
  }

  /// Escolhe da galeria. Usa o `image_picker` que o projeto já tinha — não
  /// adiciona pacote novo nem duplica seletor.
  Future<CaptureResult?> pickFromGallery() async {
    try {
      final picked = await ImagePicker().pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 15),
      );
      if (picked == null) return null;
      return CaptureResult(videoPath: picked.path, fromGallery: true);
    } catch (_) {
      return null;
    }
  }

  /// Abre a seção de rascunhos (tela que já existia).
  Future<void> openDrafts(BuildContext context) async {
    await Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => const DraftsScreen()));
  }

  /// Salva a gravação como rascunho imediatamente, sem passar pela publicação.
  ///
  /// Usado pelo atalho "Salvar rascunho" da tela de captura.
  Future<bool> saveAsDraft(
    CaptureResult result, {
    String description = '',
  }) async {
    try {
      final now = DateTime.now();
      await _repo.save(
        MediaProjectModel(
          id: '',
          videoPath: result.videoPath,
          description: description,
          effectIds: result.effectIds,
          createdAt: now,
          updatedAt: now,
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Mensagem amigável para falha de captura/galeria.
  static String captureErrorMessage(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return l10n?.createCaptureFailed ?? 'Não foi possível abrir a câmera.';
  }

  /// Verifica se o arquivo ainda existe antes de oferecer o rascunho.
  static bool fileExists(String? path) {
    if (path == null || path.isEmpty) return false;
    return File(path).existsSync();
  }
}
