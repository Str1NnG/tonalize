import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _fieldMode = false;

  @override
  void initState() {
    super.initState();
    _loadFieldMode();
  }

  Future<void> _loadFieldMode() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fieldMode = prefs.getBool('field_mode') ?? false;
    });
  }

  Future<void> _setFieldMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('field_mode', value);
    setState(() {
      _fieldMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Configurações'),
          ),
          body: ListView(
            children: [
              // Seletor de Tema
              SwitchListTile(
                title: const Text('Modo Escuro'),
                value: themeProvider.themeMode == ThemeMode.dark,
                onChanged: (value) {
                  themeProvider.toggleTheme(value);
                },
                secondary: const Icon(Icons.dark_mode_outlined),
              ),
              const Divider(),

              // Modo Teste de Campo (RF06)
              SwitchListTile(
                title: const Text('Teste de Campo'),
                subtitle: const Text(
                  'Exibe botões para registrar acerto/erro na tela de análise',
                ),
                value: _fieldMode,
                onChanged: _setFieldMode,
                secondary: const Icon(Icons.fact_check_outlined),
              ),
              const Divider(),

              // Botão Sobre
              ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Sobre o Tonalize'),
                onTap: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'Tonalize',
                    applicationVersion: '1.0.0',
                    applicationLegalese: 'Projeto de Pesquisa Científica',
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.only(top: 15),
                        child: Text(
                          'Identificação de tonalidade musical ao vivo via processamento no celular, com perfis Krumhansl-Kessler e correlação de Pearson.',
                        ),
                      ),
                    ],
                  );
                },
              ),
              // Botão Contato
              ListTile(
                leading: const Icon(Icons.email_outlined),
                title: const Text('Contato & Feedback'),
                subtitle: const Text('tonalizeapp@gmail.com'),
                onTap: () {},
              ),
            ],
          ),
        );
      },
    );
  }
}
