import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/key_profiles.dart';
import '../providers/theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _fieldMode = false;

  // Calibração / Experimento (Plano 2 e Plano 3)
  String _stabMode = 'v2';
  int _windowS = 20;
  bool _harmonics = true;
  String _profiles = 'temperley';
  bool _logReadings = false;
  bool _songMemory = true;
  int _songHalflifeS = 60;
  int _songFarS = 12;
  int _songNearS = 45;
  double _evidenceTol = 0.8;
  double _evidenceDrain = 0.5;
  bool _strictNotes = false;

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
      _profiles = prefs.getString('profiles') ?? 'temperley';
      _logReadings = prefs.getBool('log_readings') ?? false;
      _songMemory = prefs.getBool('song_memory') ?? true;
      _songHalflifeS = prefs.getInt('song_halflife_s') ?? 60;
      _songFarS = prefs.getInt('song_far_s') ?? 12;
      _songNearS = prefs.getInt('song_near_s') ?? 45;
      _evidenceTol = prefs.getDouble('evidence_tol') ?? 0.8;
      _evidenceDrain = prefs.getDouble('evidence_drain') ?? 0.5;
      _strictNotes = prefs.getBool('strict_notes') ?? false;
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

  Future<void> _setSongMemory(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('song_memory', value);
    setState(() => _songMemory = value);
  }

  Future<void> _setSongHalflifeS(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('song_halflife_s', value);
    setState(() => _songHalflifeS = value);
  }

  Future<void> _setSongFarS(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('song_far_s', value);
    setState(() => _songFarS = value);
  }

  Future<void> _setSongNearS(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('song_near_s', value);
    setState(() => _songNearS = value);
  }

  Future<void> _setEvidenceTol(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('evidence_tol', value);
    setState(() => _evidenceTol = value);
  }

  Future<void> _setEvidenceDrain(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('evidence_drain', value);
    setState(() => _evidenceDrain = value);
  }

  Future<void> _setStrictNotes(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('strict_notes', value);
    setState(() => _strictNotes = value);
  }

  String get _normalizedProfileValue {
    final lower = _profiles.toLowerCase();
    if (lower.startsWith('temp') && lower.contains('kp')) return ProfileSet.temperleyKP.name;
    if (lower.startsWith('temp')) return ProfileSet.temperley.name;
    if (lower.startsWith('aar')) return ProfileSet.aarden.name;
    return ProfileSet.krumhansl.name;
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

              // Grupo: Experimento (calibração) - Plano 2 e 3
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
                title: const Text('Janela do Trecho'),
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

              // Perfis (profiles) - 4 conjuntos
              ListTile(
                leading: const Icon(Icons.library_music_outlined),
                title: const Text('Perfis de Tonalidade'),
                subtitle: Text(
                  ProfileSet.values
                      .firstWhere((p) => p.name == _normalizedProfileValue)
                      .label,
                ),
                trailing: DropdownButton<String>(
                  value: _normalizedProfileValue,
                  underline: const SizedBox(),
                  items: ProfileSet.values.map((p) {
                    return DropdownMenuItem(
                      value: p.name,
                      child: Text(p.label),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) _setProfiles(val);
                  },
                ),
              ),

              const Divider(),

              // Grupo: Memória da Música (Dual Memory - Plano 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text(
                  'MEMÓRIA DA MÚSICA (PLANO 3)',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ),

              // Memória da Música (song_memory)
              SwitchListTile(
                title: const Text('Memória da Música (Dual Memory)'),
                subtitle: const Text(
                  'Letreiro mostra tom da música; linha "agora" mostra desvios no refrão',
                ),
                value: _songMemory,
                onChanged: _setSongMemory,
                secondary: const Icon(Icons.hourglass_top_outlined),
              ),

              if (_songMemory) ...[
                // Meia-vida da memória da música (song_halflife_s)
                ListTile(
                  leading: const Icon(Icons.history_outlined),
                  title: const Text('Meia-vida da Memória da Música'),
                  subtitle: Text('$_songHalflifeS segundos'),
                  trailing: DropdownButton<int>(
                    value: _songHalflifeS,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 30, child: Text('30 s')),
                      DropdownMenuItem(value: 60, child: Text('60 s (padrão)')),
                      DropdownMenuItem(value: 120, child: Text('120 s')),
                    ],
                    onChanged: (val) {
                      if (val != null) _setSongHalflifeS(val);
                    },
                  ),
                ),

                // Reinício por tom distante (song_far_s)
                ListTile(
                  leading: const Icon(Icons.alt_route_outlined),
                  title: const Text('Reinício em Tom Distante'),
                  subtitle: Text('Após $_songFarS segundos em modulação real'),
                  trailing: DropdownButton<int>(
                    value: _songFarS,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 8, child: Text('8 s')),
                      DropdownMenuItem(value: 12, child: Text('12 s (padrão)')),
                      DropdownMenuItem(value: 20, child: Text('20 s')),
                    ],
                    onChanged: (val) {
                      if (val != null) _setSongFarS(val);
                    },
                  ),
                ),

                // Reinício por tom vizinho sustentado (song_near_s)
                ListTile(
                  leading: const Icon(Icons.repeat_outlined),
                  title: const Text('Reinício em Tom Vizinho Sustentado'),
                  subtitle: Text(
                    _songNearS == 0
                        ? 'Desativado (nunca reinicia por vizinho)'
                        : 'Após $_songNearS segundos de vamp/solo sustentado',
                  ),
                  trailing: DropdownButton<int>(
                    value: _songNearS,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('0 s (nunca)')),
                      DropdownMenuItem(value: 30, child: Text('30 s')),
                      DropdownMenuItem(value: 45, child: Text('45 s (padrão)')),
                      DropdownMenuItem(value: 90, child: Text('90 s')),
                    ],
                    onChanged: (val) {
                      if (val != null) _setSongNearS(val);
                    },
                  ),
                ),

                // Tolerância da evidência de nota nova (evidence_tol)
                ListTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: const Text('Tolerância da Nota Nova'),
                  subtitle: Text(
                    _evidenceTol == 0.8
                        ? '0,8 (padrão)'
                        : _evidenceTol.toStringAsFixed(1),
                  ),
                  trailing: DropdownButton<double>(
                    value: _evidenceTol,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 0.6, child: Text('0,6 (sensível)')),
                      DropdownMenuItem(value: 0.8, child: Text('0,8 (padrão)')),
                      DropdownMenuItem(value: 1.0, child: Text('1,0 (conservador)')),
                    ],
                    onChanged: (val) {
                      if (val != null) _setEvidenceTol(val);
                    },
                  ),
                ),

                // Dreno da evidência (evidence_drain)
                ListTile(
                  leading: const Icon(Icons.water_drop_outlined),
                  title: const Text('Dreno da Evidência'),
                  subtitle: Text(
                    _evidenceDrain == 0.5
                        ? '0,5 s/s (padrão)'
                        : '$_evidenceDrain s/s',
                  ),
                  trailing: DropdownButton<double>(
                    value: _evidenceDrain,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 0.0, child: Text('0 (sem dreno)')),
                      DropdownMenuItem(value: 0.5, child: Text('0,5 s/s (padrão)')),
                      DropdownMenuItem(value: 1.5, child: Text('1,5 s/s (agressivo)')),
                    ],
                    onChanged: (val) {
                      if (val != null) _setEvidenceDrain(val);
                    },
                  ),
                ),
              ],

              // Modo estrito (strict_notes) - Fase 5
              SwitchListTile(
                title: const Text('Modo Estrito (strict_notes)'),
                subtitle: const Text(
                  'Sem nota nova da escala, o tom da música nunca troca para um vizinho',
                ),
                value: _strictNotes,
                onChanged: _setStrictNotes,
                secondary: const Icon(Icons.lock_clock_outlined),
              ),

              const Divider(),

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
