import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'watch_crypto.dart' as wcrypto;

class AdminConfigDialog extends StatefulWidget {
  final Function(bool) onLoginStatusChanged;
  const AdminConfigDialog({Key? key, required this.onLoginStatusChanged}) : super(key: key);

  @override
  State<AdminConfigDialog> createState() => _AdminConfigDialogState();
}

class _AdminConfigDialogState extends State<AdminConfigDialog> {
  bool _isAuthenticated = false;
  final TextEditingController _passwordLoginController = TextEditingController();
  
  // Controllers do Formulário de Configuração
  final TextEditingController _mikrotikUrlController = TextEditingController();
  final TextEditingController _mikrotikUserController = TextEditingController();
  final TextEditingController _mikrotikPassController = TextEditingController();
  final TextEditingController _mikrotikPollController = TextEditingController();
  final TextEditingController _serverUrlController = TextEditingController();
  final TextEditingController _serverTokenController = TextEditingController();
  final TextEditingController _adminPassController = TextEditingController();
  
  List<String> _monitoredPaths = [];
  final TextEditingController _newPathController = TextEditingController();

  Map<String, dynamic> _configData = {};
  // Hash da senha admin atualmente salvo (não exibido). Vazio = primeiro acesso.
  String _currentAdminHash = "";

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _passwordLoginController.dispose();
    _mikrotikUrlController.dispose();
    _mikrotikUserController.dispose();
    _mikrotikPassController.dispose();
    _mikrotikPollController.dispose();
    _serverUrlController.dispose();
    _serverTokenController.dispose();
    _adminPassController.dispose();
    _newPathController.dispose();
    super.dispose();
  }

  // Caminho do arquivo de configuração
  File _getConfigFile() {
    if (Platform.isWindows) {
      return File('C:\\ProgramData\\OnliDeskWhatch\\watch_config.json');
    } else {
      final home = Platform.environment['HOME'] ?? '.';
      return File('$home/.config/onlidesk-watch/watch_config.json');
    }
  }

  // Carrega as configurações do JSON
  void _loadConfig() {
    try {
      final file = _getConfigFile();
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        _configData = jsonDecode(content);
      } else {
        // Valores default
        _configData = {
          "mikrotik_api_url": "https://192.168.88.1",
          "mikrotik_username": "admin",
          "mikrotik_password": "",
          "mikrotik_poll_interval_secs": 10,
          "monitored_paths": [],
          "local_log_path": "C:\\ProgramData\\OnliDeskWhatch\\logs\\audit.log",
          "webhook_url": "https://onlideskwatch.onlitec.com.br/api/logs",
          "webhook_token": "WatchSecretToken2026",
          "admin_password_hash": ""
        };
      }

      // Hash da senha admin (aceita alias legado 'admin_password' em texto plano)
      _currentAdminHash =
          _configData["admin_password_hash"] ?? _configData["admin_password"] ?? "";

      // Inicializa os text controllers
      _mikrotikUrlController.text = _configData["mikrotik_api_url"] ?? "";
      _mikrotikUserController.text = _configData["mikrotik_username"] ?? "";
      // Decifra a senha do Mikrotik para exibir/editar
      _mikrotikPassController.text =
          wcrypto.decryptSecret(_configData["mikrotik_password"] ?? "");
      _mikrotikPollController.text = (_configData["mikrotik_poll_interval_secs"] ?? 10).toString();
      _serverUrlController.text = _configData["webhook_url"] ?? "";
      _serverTokenController.text = _configData["webhook_token"] ?? "";
      // Campo de senha admin fica em branco (só preencher para trocar)
      _adminPassController.text = "";

      final pathsRaw = _configData["monitored_paths"];
      if (pathsRaw is List) {
        _monitoredPaths = List<String>.from(pathsRaw);
      } else {
        _monitoredPaths = [];
      }
    } catch (e) {
      debugPrint("Erro ao carregar configurações: $e");
    }
  }

  // Salva as configurações de volta para o JSON
  void _saveConfig() {
    try {
      // Inclui um caminho digitado mas ainda nao adicionado com o botao "+".
      final pending = _newPathController.text.trim();
      if (pending.isNotEmpty && !_monitoredPaths.contains(pending)) {
        _monitoredPaths.add(pending);
        _newPathController.clear();
      }

      final file = _getConfigFile();
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }

      // Senha admin: se o campo foi preenchido, gera novo hash; senão mantém o atual
      final newAdminHash = _adminPassController.text.isNotEmpty
          ? wcrypto.hashAdminPassword(_adminPassController.text)
          : _currentAdminHash;

      // Preserva demais campos existentes (ex.: device_token, device_status)
      final updatedConfig = Map<String, dynamic>.from(_configData);
      updatedConfig.remove("admin_password"); // remove chave legada em texto plano
      updatedConfig.addAll({
        "mikrotik_api_url": _mikrotikUrlController.text,
        "mikrotik_username": _mikrotikUserController.text,
        // Cifra a senha do Mikrotik (formato enc:v1:)
        "mikrotik_password": wcrypto.encryptSecret(_mikrotikPassController.text),
        "mikrotik_poll_interval_secs": int.tryParse(_mikrotikPollController.text) ?? 10,
        "monitored_paths": _monitoredPaths,
        "local_log_path": _configData["local_log_path"] ?? "C:\\ProgramData\\OnliDeskWhatch\\logs\\audit.log",
        "webhook_url": _serverUrlController.text,
        "webhook_token": _serverTokenController.text,
        "admin_password_hash": newAdminHash,
      });

      _currentAdminHash = newAdminHash;
      file.writeAsStringSync(jsonEncode(updatedConfig));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configurações salvas com sucesso!')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao salvar: $e')),
      );
    }
  }

  // Verifica a senha do admin (por hash; primeiro acesso aceita a senha padrão)
  void _handleLogin() {
    final entered = _passwordLoginController.text;
    // Primeiro acesso (sem hash salvo): aceita a senha inicial "admin123"
    final firstRun = _currentAdminHash.isEmpty;
    final ok = firstRun
        ? entered == "admin123"
        : wcrypto.verifyAdminPassword(entered, _currentAdminHash);

    if (ok) {
      setState(() {
        _isAuthenticated = true;
      });
      widget.onLoginStatusChanged(true);
      if (firstRun) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Primeiro acesso: defina uma nova senha de administrador antes de salvar.')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Senha administrativa incorreta!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isAuthenticated) {
      return AlertDialog(
        title: const Text('Login Administrativo'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Digite a senha para acessar as configurações de monitoramento:'),
            const SizedBox(height: 15),
            TextField(
              controller: _passwordLoginController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Senha de Admin',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _handleLogin(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: _handleLogin,
            child: const Text('Acessar'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Configurações de Monitoramento OnliDeskWhatch'),
      content: SizedBox(
        width: 550,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPairingStatusWidget(),
              const Divider(height: 25),
              // Seção Mikrotik
              const Text('Integração Roteador / Mikrotik', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 10),
              TextField(
                controller: _mikrotikUrlController,
                decoration: const InputDecoration(
                  labelText: 'URL da API REST (ex: https://192.168.88.1)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _mikrotikUserController,
                      decoration: const InputDecoration(
                        labelText: 'Usuário API',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _mikrotikPassController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Senha API',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _mikrotikPollController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Intervalo de Varredura (segundos)',
                  border: OutlineInputBorder(),
                ),
              ),
              const Divider(height: 30),

              // Seção Servidor Nuvem
              const Text('Sincronização com Servidor em Nuvem', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 10),
              TextField(
                controller: _serverUrlController,
                decoration: const InputDecoration(
                  labelText: 'Endpoint de Ingestão (ex: http://10.10.10.1:4450/api/logs)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _serverTokenController,
                decoration: const InputDecoration(
                  labelText: 'Token de Segurança (Bearer Token)',
                  border: OutlineInputBorder(),
                ),
              ),
              const Divider(height: 30),

              // Seção Auditoria de Arquivos
              const Text('Pastas de Servidor Monitoradas (SMB / Mapeamento)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 10),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _monitoredPaths.length,
                itemBuilder: (context, index) {
                  return Card(
                    color: Theme.of(context).hoverColor,
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      dense: true,
                      title: Text(_monitoredPaths[index]),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            _monitoredPaths.removeAt(index);
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newPathController,
                      decoration: const InputDecoration(
                        labelText: 'Adicionar caminho (ex: S:\\ ou \\\\servidor\\compartilhado)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(Icons.add_circle, color: Colors.blue, size: 30),
                    onPressed: () {
                      if (_newPathController.text.isNotEmpty) {
                        setState(() {
                          _monitoredPaths.add(_newPathController.text);
                          _newPathController.clear();
                        });
                      }
                    },
                  )
                ],
              ),
              const Divider(height: 30),

              // Seção Senha Admin Local
              const Text('Segurança da Aplicação', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 10),
              TextField(
                controller: _adminPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Alterar Senha do Administrador Local',
                  helperText: 'Deixe em branco para manter a senha atual.',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: _saveConfig,
          child: const Text('Salvar Configurações'),
        ),
      ],
    );
  }

  Widget _buildPairingStatusWidget() {
    final status = _configData["device_status"] ?? "pending";
    Color statusColor;
    String statusText;
    IconData statusIcon;

    if (status == "approved") {
      statusColor = Colors.green;
      statusText = "Pareamento Autorizado e Ativo";
      statusIcon = Icons.check_circle;
    } else if (status == "blocked") {
      statusColor = Colors.red;
      statusText = "Dispositivo Bloqueado na Nuvem";
      statusIcon = Icons.block;
    } else {
      statusColor = Colors.orange;
      statusText = "Aguardando aprovação no servidor central";
      statusIcon = Icons.hourglass_empty;
    }

    return Card(
      color: statusColor.withOpacity(0.1),
      shape: RoundedRectangleBorder(
        side: BorderSide(color: statusColor, width: 1.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(statusIcon, color: statusColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Status de Pareamento',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
