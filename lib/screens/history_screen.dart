import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../helpers/database_helper.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<FieldEntry> _historyList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _refreshHistory();
  }

  Future<void> _refreshHistory() async {
    setState(() => _isLoading = true);
    final data = await DatabaseHelper.instance.getFieldEntries();
    if (mounted) {
      setState(() {
        _historyList = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteItem(int id) async {
    await DatabaseHelper.instance.deleteFieldEntry(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Registro removido.'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    _refreshHistory();
  }

  Future<void> _clearAllHistory() async {
    await DatabaseHelper.instance.clearFieldEntries();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Histórico limpo com sucesso.'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    _refreshHistory();
  }

  Future<void> _exportCsv() async {
    if (_historyList.isEmpty) return;

    final buffer = StringBuffer();
    buffer.writeln('dateTime,keyShown,secondShown,confidence,answer');
    for (final item in _historyList) {
      buffer.writeln(
        '${item.dateTime},"${item.keyShown}","${item.secondShown}",${(item.confidence * 100).toStringAsFixed(1)},${item.answer}',
      );
    }

    await Clipboard.setData(ClipboardData(text: buffer.toString()));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('CSV copiado para a área de transferência!'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showClearConfirmationDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Limpar Histórico'),
          content: const Text(
            'Tem certeza de que deseja apagar todos os registros de validação de campo? Esta ação não pode ser desfeita.',
          ),
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
        title: const Text('Histórico de Campo'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Botão Exportar CSV para a monografia
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: 'Exportar CSV',
            onPressed: _historyList.isEmpty ? null : _exportCsv,
          ),
          // Botão Limpar Tudo
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Limpar tudo',
            onPressed:
                _historyList.isEmpty ? null : _showClearConfirmationDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _historyList.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  padding: const EdgeInsets.all(8.0),
                  itemCount: _historyList.length,
                  itemBuilder: (context, index) {
                    final item = _historyList[index];
                    final isCorrect = item.answer.toLowerCase() == 'acertou';

                    return Dismissible(
                      key: Key(item.id.toString()),
                      direction: DismissDirection.endToStart,
                      onDismissed: (direction) {
                        _deleteItem(item.id!);
                      },
                      background: Container(
                        color: Colors.red.shade800,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20.0),
                        child: const Icon(
                          Icons.delete_outline,
                          color: Colors.white,
                        ),
                      ),
                      child: Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          side: BorderSide(
                            color: theme.colorScheme.outline.withOpacity(0.3),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCorrect
                                ? Colors.green.withOpacity(0.2)
                                : Colors.red.withOpacity(0.2),
                            child: Icon(
                              isCorrect
                                  ? Icons.check_rounded
                                  : Icons.close_rounded,
                              color: isCorrect ? Colors.green : Colors.red,
                            ),
                          ),
                          title: Row(
                            children: [
                              Text(
                                item.keyShown,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isCorrect
                                      ? Colors.green.withOpacity(0.15)
                                      : Colors.red.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.answer.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        isCorrect ? Colors.green : Colors.red,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            '2ª: ${item.secondShown} • Confiança: ${(item.confidence * 100).toStringAsFixed(0)}%',
                          ),
                          trailing: Text(
                            DateFormat('dd/MM/yy\nHH:mm').format(
                              DateTime.tryParse(item.dateTime) ??
                                  DateTime.now(),
                            ),
                            textAlign: TextAlign.right,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
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
          Icon(
            Icons.history_toggle_off_outlined,
            size: 80,
            color: Colors.grey.shade600,
          ),
          const SizedBox(height: 20),
          const Text(
            'Nenhum registro de campo.',
            style: TextStyle(fontSize: 18, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 32.0),
            child: Text(
              'Ative o "Teste de Campo" nas Configurações e registre acertos/erros durante a análise.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }
}