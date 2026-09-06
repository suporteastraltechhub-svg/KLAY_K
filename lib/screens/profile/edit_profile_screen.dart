import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/user_profile.dart';
import '../../services/profile_service.dart';
import '../../widgets/profile_widgets.dart';

/// Edição completa do perfil do usuário autenticado:
/// capa, avatar, nome, usuário, bio, site, localização e pronomes.
/// Capa/avatar são enviados na hora (buckets públicos) e o restante é salvo
/// pelo [ProfileService.updateProfile] (validação de @username inclusive).
class EditProfileScreen extends StatefulWidget {
  final UserProfile profile;

  const EditProfileScreen({super.key, required this.profile});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _usernameController;
  late final TextEditingController _bioController;
  late final TextEditingController _websiteController;
  late final TextEditingController _locationController;
  late final TextEditingController _pronounsController;

  String? _avatarUrl;
  String? _bannerUrl;
  bool _saving = false;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _nameController = TextEditingController(text: p.displayName ?? '');
    _usernameController = TextEditingController(text: p.username ?? '');
    _bioController = TextEditingController(text: p.bio ?? '');
    _websiteController = TextEditingController(text: p.website ?? '');
    _locationController = TextEditingController(text: p.location ?? '');
    _pronounsController = TextEditingController(text: p.pronouns ?? '');
    _avatarUrl = p.avatarUrl;
    _bannerUrl = p.bannerUrl;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _websiteController.dispose();
    _locationController.dispose();
    _pronounsController.dispose();
    super.dispose();
  }

  String get _usernameWithoutAt =>
      _usernameController.text.trim().replaceFirst(RegExp(r'^@'), '');

  Future<void> _pickAndUpload(bool avatar) async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 85,
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _uploading = true);
    try {
      final url = avatar
          ? await ProfileService.instance.uploadAvatar(File(picked.path))
          : await ProfileService.instance.uploadBanner(File(picked.path));
      if (!mounted) return;
      setState(() {
        if (avatar) {
          _avatarUrl = url;
        } else {
          _bannerUrl = url;
        }
        _uploading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _uploading = false);
      _snack('Não foi possível enviar a imagem: $e');
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _snack('Informe um nome de exibição.');
      return;
    }
    setState(() => _saving = true);
    try {
      await ProfileService.instance.updateProfile(
        displayName: name,
        username: _usernameWithoutAt,
        bio: _bioController.text,
        website: _websiteController.text,
        location: _locationController.text,
        pronouns: _pronounsController.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ProfileValidationException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Não foi possível salvar: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Editar perfil',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        actions: [
          if (!_saving)
            TextButton(
              onPressed: _save,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              child: const Text('Salvar'),
            ),
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kProfileAccent,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _bannerEditor(),
          const SizedBox(height: 14),
          _avatarEditor(),
          const SizedBox(height: 18),
          _field(
            label: 'Nome de usuário',
            controller: _usernameController,
            hint: 'usuario',
            prefix: '@',
            maxLength: 20,
          ),
          const SizedBox(height: 10),
          _field(
            label: 'Nome de exibição',
            controller: _nameController,
            hint: 'Seu nome',
            maxLength: 30,
          ),
          const SizedBox(height: 10),
          _field(
            label: 'Biografia',
            controller: _bioController,
            hint: 'Conte um pouco sobre você',
            maxLines: 3,
            maxLength: 160,
          ),
          const SizedBox(height: 10),
          _field(
            label: 'Site',
            controller: _websiteController,
            hint: 'https://exemplo.com',
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 10),
          _field(
            label: 'Localização',
            controller: _locationController,
            hint: 'Cidade, Estado',
            maxLength: 60,
          ),
          const SizedBox(height: 10),
          _field(
            label: 'Pronomes',
            controller: _pronounsController,
            hint: 'ex.: ele/dele',
            maxLength: 20,
          ),
          if (_uploading) ...[
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'Enviando imagem…',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bannerEditor() {
    final hasBanner = _bannerUrl != null && _bannerUrl!.isNotEmpty;
    return GestureDetector(
      onTap: _uploading ? null : () => _pickAndUpload(false),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            SizedBox(
              height: 150,
              width: double.infinity,
              child: hasBanner
                  ? Image.network(
                      _bannerUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _bannerFallback(),
                    )
                  : _bannerFallback(),
            ),
            if (hasBanner)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.25),
                ),
              ),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.photo_camera_outlined,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      hasBanner ? 'Trocar capa' : 'Adicionar capa',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bannerFallback() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF3B2A63), Color(0xFF211B33)],
        ),
      ),
      child: const Center(
        child: Icon(Icons.add_photo_alternate_outlined,
            color: Colors.white24, size: 40),
      ),
    );
  }

  Widget _avatarEditor() {
    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap: _uploading ? null : () => _pickAndUpload(true),
            child: Stack(
              children: [
                Container(
                  width: 92,
                  height: 92,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFFA78BFA), Color(0xFF7C3AED)],
                    ),
                  ),
                  padding: const EdgeInsets.all(2),
                  child: ClipOval(
                    child: _avatarUrl != null && _avatarUrl!.isNotEmpty
                        ? Image.network(
                            _avatarUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _avatarFallback(),
                          )
                        : _avatarFallback(),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: kProfileAccent,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Toque para alterar a foto',
            style: TextStyle(
              color: _uploading ? Colors.white24 : Colors.white38,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatarFallback() {
    return Container(
      color: const Color(0xFF2A2740),
      child: const Icon(Icons.person, color: Colors.white54, size: 40),
    );
  }

  Widget _field({
    required String label,
    required TextEditingController controller,
    required String hint,
    String? prefix,
    int? maxLength,
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      cursorColor: kProfileAccent,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54),
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24),
        prefixText: prefix,
        prefixStyle: const TextStyle(color: Colors.white54),
        counterStyle: const TextStyle(color: Colors.white24),
        filled: true,
        fillColor: const Color(0xFF1E1B2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kProfileAccent, width: 1.5),
        ),
      ),
    );
  }
}