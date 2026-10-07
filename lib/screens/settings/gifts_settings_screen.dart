import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/gift_models.dart';
import '../../services/gift_service.dart';
import '../../services/supabase_service.dart';
import '../wallet_sheet.dart';

const Color _kAccent = Color(0xFF8B5CF6);
const Color _kCard = Color(0xFF1B1A26);
const Color _kMuted = Color(0xFF9A94AD);

const int _historyLimit = 20;

String _timestamp(DateTime value) =>
    DateFormat('dd/MM/yyyy HH:mm').format(value);

class GiftsSettingsScreen extends StatefulWidget {
  const GiftsSettingsScreen({super.key});

  @override
  State<GiftsSettingsScreen> createState() => _GiftsSettingsScreenState();
}

class _GiftsSettingsScreenState extends State<GiftsSettingsScreen> {
  final GiftService _gifts = GiftService.instance;
  final SupabaseService _supabase = SupabaseService.instance;

  GiftHistoryDirection _direction = GiftHistoryDirection.sent;
  List<GiftTransaction> _items = const [];
  Map<String, String> _counterparties = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _gifts.fetchHistory(
        direction: _direction,
        limit: _historyLimit,
      );
      final names = await _resolveCounterparties(items);
      if (!mounted) return;
      setState(() {
        _items = items;
        _counterparties = names;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _counterparties = const {};
        _loading = false;
        _error = 'Não foi possível carregar seu histórico de presentes. $e';
      });
    }
  }

  Future<Map<String, String>> _resolveCounterparties(
    List<GiftTransaction> items,
  ) async {
    final ids = <String>{};
    for (final item in items) {
      final other = _direction == GiftHistoryDirection.sent
          ? item.receiverId
          : item.userId;
      if (other != null && other.isNotEmpty) ids.add(other);
    }
    if (ids.isEmpty) return const {};
    final results = await Future.wait<({String id, String name})>(
      ids.map((id) async {
        String name = '';
        try {
          final profile = await _supabase.profileFor(id);
          final display = profile?['display_name']?.toString() ?? '';
          final username = profile?['username']?.toString() ?? '';
          name = display.isNotEmpty
              ? (username.isNotEmpty ? '$display (@$username)' : display)
              : (username.isNotEmpty ? '@$username' : '');
        } catch (_) {}
        return (id: id, name: name);
      }),
    );
    return {for (final r in results) r.id: r.name};
  }

  void _openWallet() {
    WalletSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final isSent = _direction == GiftHistoryDirection.sent;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        centerTitle: true,
        title: const Text(
          'Presentes',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: RefreshIndicator(
        color: _kAccent,
        backgroundColor: _kCard,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            const _SectionHeader('CARTEIRA DE CRÉDITOS'),
            _walletTile(),
            const SizedBox(height: 20),
            const _SectionHeader('HISTÓRICO'),
            _directionToggle(),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(
                  child: CircularProgressIndicator(color: _kAccent),
                ),
              )
            else if (_error != null)
              _errorCard(_error!)
            else if (_items.isEmpty)
              _emptyCard(isSent)
            else ...[
              const Text(
                '$_historyLimit mais recentes',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              const SizedBox(height: 8),
              ..._items.map((t) => _transactionTile(t, isSent)),
            ],
            const SizedBox(height: 20),
            const _SectionHeader('REGRA DE ENVIO'),
            _selfGiftNote(),
          ],
        ),
      ),
    );
  }

  Widget _walletTile() {
    return Semantics(
      label: 'Abrir carteira de créditos',
      button: true,
      child: Card(
        color: _kCard,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: const Icon(
            Icons.account_balance_wallet_rounded,
            color: _kAccent,
          ),
          title: const Text(
            'Carteira',
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
          subtitle: const Text(
            'Ver saldo, comprar créditos e ver o histórico financeiro.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.white38),
          onTap: _openWallet,
        ),
      ),
    );
  }

  Widget _directionToggle() {
    return Semantics(
      label: 'Alternar entre enviados e recebidos',
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            _segment('Enviados', _direction == GiftHistoryDirection.sent),
            _segment('Recebidos', _direction == GiftHistoryDirection.received),
          ],
        ),
      ),
    );
  }

  Widget _segment(String label, bool selected) {
    return Expanded(
      child: Semantics(
        label: label,
        selected: selected,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: _loading
              ? null
              : () {
                  if (selected) return;
                  setState(() {
                    _direction = label == 'Enviados'
                        ? GiftHistoryDirection.sent
                        : GiftHistoryDirection.received;
                  });
                  _load();
                },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 11),
            decoration: BoxDecoration(
              color: selected ? _kAccent : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _transactionTile(GiftTransaction tx, bool isSent) {
    final otherId = isSent ? tx.receiverId : tx.userId;
    final otherName = otherId == null ? '' : (_counterparties[otherId] ?? '');
    final credits = tx.creditsTotal > 0
        ? tx.creditsTotal
        : tx.creditsPerUnit * tx.amount;
    return Semantics(
      label:
          '${tx.giftName}, quantidade ${tx.amount}, $credits créditos, '
          'em ${_timestamp(tx.createdAt)}',
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _kAccent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isSent ? Icons.card_giftcard_rounded : Icons.redeem_rounded,
                color: _kAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.giftName.isEmpty ? 'Presente' : tx.giftName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isSent ? 'Enviado' : 'Recebido',
                    style: TextStyle(
                      color: isSent
                          ? const Color(0xFFFBBF24)
                          : const Color(0xFF34D399),
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _counterpartyLine(isSent, otherId, otherName),
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${tx.amount}x · $credits créditos · ${_timestamp(tx.createdAt)}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            if (isSent)
              Text(
                '-$credits',
                style: const TextStyle(
                  color: Color(0xFFFBBF24),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              )
            else
              Text(
                '+$credits',
                style: const TextStyle(
                  color: Color(0xFF34D399),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _counterpartyLine(bool isSent, String? otherId, String otherName) {
    final role = isSent ? 'Para' : 'De';
    if (otherId == null || otherId.isEmpty) {
      return '$role: destinatário não informado pelo backend';
    }
    if (otherName.isEmpty) {
      return '$role: perfil não disponível';
    }
    return '$role: $otherName';
  }

  Widget _emptyCard(bool isSent) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Semantics(
        label: isSent
            ? 'Você ainda não enviou presentes.'
            : 'Você ainda não recebeu presentes.',
        child: Row(
          children: [
            const Icon(Icons.inbox_rounded, color: _kMuted, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isSent
                    ? 'Você ainda não enviou presentes. Quando enviar, o '
                          'histórico aparece aqui.'
                    : 'Você ainda não recebeu presentes. Quando receber, o '
                          'histórico aparece aqui.',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selfGiftNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kAccent.withValues(alpha: 0.35)),
      ),
      child: Semantics(
        label:
            'Você não pode enviar presentes para si mesmo. Na sua própria LIVE '
            'o envio é bloqueado.',
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.block_rounded, color: _kAccent, size: 20),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Você não pode enviar presentes para si mesmo. Na sua própria '
                'LIVE o envio é bloqueado.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _errorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFF4D6A).withValues(alpha: 0.4),
        ),
      ),
      child: Semantics(
        label: message,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              color: Color(0xFFFF4D6A),
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: _kAccent,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
