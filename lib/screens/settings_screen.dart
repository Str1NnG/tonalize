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

  // Calibração / Experimento (Fase 4)
  String _stabMode = 'v2';
  int _windowS = 20;
  bool _harmonics = true;
  String _profiles = 'Krumhansl';
  bool _logReadings = false;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _fieldMode = prefs.getBool('field_mode') ?? false;
      _stabMode = prefs.getString('stab_mode') ?? 'v2';
      _windowS = prefs.getInt('window_s') ?? 20;
      _harmonics = prefs.getBool('harmonics') ?? true;
      _profiles = prefs.getString('profiles') ?? 'Krumhansl';
      _logReadings = prefs.getBool('log_readings') ?? false;
    });
  }

  Future<void> _setFieldMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('field_mode', value);
    setState(() => _fieldMode = value);
  }

  Future<void> _setStabMode(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('stab_mode', value);
    setState(() => _stabMode = value);
  }

  Future<void> _setWindowS(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('window_s', value);
    setState(() => _windowS = value);
  }

  Future<void> _setHarmonics(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('harmonics', value);
    setState(() => _harmonics = value);
  }

  Future<void> _setProfiles(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('profiles', value);
    setState(() => _profiles = value);
  }

  Future<void> _setLogReadings(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('log_readings', value);
    setState(() => _logReadings = value);
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

              // Grupo: Experimento (calibração) - Fase 4
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'EXPERIMENTO (CALIBRAÇÃO)',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),

              // Modo de Estabilidade
              ListTile(
                leading: const Icon(Icons.tune_outlined),
                title: const Text('Modo de Estabilidade'),
                subtitle: Text(
                  _stabMode == 'v2'
                      ? 'v2: Histerese por margem (0,05/0,08) + hold (4s/6s)'
                      : 'v1: Janela plana 10s + 3 leituras consecutivas (baseline)',
                ),
                trailing: DropdownButton<String>(
                  value: _stabMode,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 'v2', child: Text('v2 (atual)')),
                    DropdownMenuItem(value: 'v1', child: Text('v1 (baseline)')),
                  ],
                  onChanged: (val) {
                    if (val != null) _setStabMode(val);
                  },
                ),
              ),

              // Tamanho da Janela (window_s)
              ListTile(
                leading: const Icon(Icons.timelapse_outlined),
                title: const Text('Tamanho da Janela'),
                subtitle: Text('$_windowS segundos (meia-vida ${_windowS / 2}s)'),
                trailing: DropdownButton<int>(
                  value: _windowS,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(value: 10, child: Text('10 s')),
                    DropdownMenuItem(value: 20, child: Text('20 s')),
                    DropdownMenuItem(value: 30, child: Text('30 s')),
                  ],
                  onChanged: (val) {
                    if (val != null) _setWindowS(val);
                  },
                ),
              ),

              // Subarmônicos / HPCP (harmonics)
              SwitchListTile(
                title: const Text('Crédito de Subarmônicos (HPCP)'),
                subtitle: const Text(
                  'Filtra picos espectrais e credita fundamentais (Gómez 2006)',
                ),
                value: _harmonics,
                onChanged: _setHarmonics,
                secondary: const Icon(Icons.graphic_eq_outlined),
              ),

              // Perfis (profiles)
              ListTile(
                leading: const Icon(Icons.library_music_outlined),
                title: const Text('Perfis de Tonalidade'),
                subtitle: Text(_profiles),
                trailing: DropdownButton<String>(
                  value: _profiles,
                  underline: const SizedBox(),
                  items: const [
                    DropdownMenuItem(
                      value: 'Krumhansl',
                      child: Text('Krumhansl-Kessler'),
                    ),
                    DropdownMenuItem(
                      value: 'Temperley',
                      child: Text('Temperley (1999)'),
                    ),
                  ],
                  onChanged: (val) {
                    if (val != null) _setProfiles(val);
                  },
                ),
              ),

              // Gravar Leituras para Monografia (log_readings)
              SwitchListTile(
                title: const Text('Gravar Leituras da Sessão'),
                subtitle: const Text(
                  'Armazena 2 leituras/s no SQLite para exportar CSV na monografia',
                ),
                value: _logReadings,
                onChanged: _setLogReadings,
                secondary: const Icon(Icons.save_as_outlined),
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
                    applicationVersion: '2.0.0',
                    applicationLegalese: 'Projeto de Pesquisa Científica',
                    children: <Widget>[
                      const Padding(
                        padding: EdgeInsets.only(top: 15),
                        child: Text(
                          'Identificação de tonalidade musical ao vivo via processamento local no smartphone. '
                          'Implementa HPCP com decaimento exponencial, histerese tonal adaptativa e perfis teóricos.',
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
