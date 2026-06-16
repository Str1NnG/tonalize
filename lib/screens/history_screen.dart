// ARQUIVO TOTALMENTE REDESENHADO: lib/screens/history_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  // Agora a lista é uma variável de estado para podermos modificá-la
  List<AnalysisHistory> _historyList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  // Função para carregar (ou recarregar) o histórico do banco de dados
  Future<void> _refreshHistory() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getHistory();
    setState(() {
      _historyList = data;
      _isLoading = false;
    });
  }

  // Função para apagar um item específico
  Future<void> _deleteItem(int id) async {
    await DatabaseHelper.instance.deleteAnalysis(id);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Análise apagada.'), duration: Duration(seconds: 2)),
    );
    _refreshHistory(); // Recarrega a lista para refletir a mudança
  }

  // Função para limpar todo o histórico
  Future<void> _clearAllHistory() async {
    await DatabaseHelper.instance.clearHistory();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Histórico limpo com sucesso.'), duration: Duration(seconds: 2)),
    );
    _refreshHistory();
  }

  // Diálogo de confirmação para limpar tudo
  void _showClearConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Limpar Histórico'),
          content: const Text('Tem a certeza de que quer apagar todas as análises? Esta ação não pode ser desfeita.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Apagar', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop();
                _clearAllHistory();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Análises'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Botão para limpar tudo
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Limpar tudo',
            // Desabilita o botão se a lista estiver vazia
            onPressed: _historyList.isEmpty ? null : _showClearConfirmationDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _historyList.isEmpty
          ? _buildEmptyState() // Widget para quando não há histórico
          : ListView.builder(
        padding: const EdgeInsets.all(8.0),
        itemCount: _historyList.length,
        itemBuilder: (context, index) {
          final item = _historyList[index];

          // Widget que permite deslizar para apagar
          return Dismissible(
            key: Key(item.id.toString()), // Chave única para cada item
            direction: DismissDirection.endToStart, // Deslizar da direita para a esquerda
            onDismissed: (direction) {
              _deleteItem(item.id!);
            },
            background: Container(
              color: Colors.red.shade800,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: const Icon(Icons.delete_outline, color: Colors.white),
            ),
            child: Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: theme.colorScheme.primary,
                  child: Text(
                    item.keyName.split(' ')[0],
                    style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
                  ),
                ),
                title: Text(item.keyName, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('Confiança: ${item.confidence.toStringAsFixed(0)}%\nNotas: ${item.predominantNotes}'),
                trailing: Text(
                  DateFormat('dd/MM/yy\nHH:mm').format(DateTime.parse(item.dateTime)),
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.history_toggle_off_outlined, size: 80, color: Colors.grey.shade700),
          const SizedBox(height: 20),
          const Text(
            'Nenhuma análise salva.',
            style: TextStyle(fontSize: 20, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Text(
            'Os resultados aparecerão aqui.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}