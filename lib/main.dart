import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:notification_listener_service/notification_event.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:home_widget/home_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'dart:math';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_ES', null);
  runApp(const EroskiMastercardApp());
}

class EroskiMastercardApp extends StatelessWidget {
  const EroskiMastercardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(      title: 'Tracker Pro v18.13',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true, 
        colorSchemeSeed: const Color(0xFF0055A5), 
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  List<Map<String, dynamic>> _txs = [];
  List<Map<String, dynamic>> _otrosGastos = []; 
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _incomes = [];
  List<Map<String, dynamic>> _iaHistory = []; 
  
  bool _isListening = false;
  double _cargoPendienteBanco = 0.0;
  String _groqApiKey = "";
  String _ultimoConsejoIA = ""; 
  String _ultimoInformeBody = "";
  double _ultimoTotalAnalizado = 0.0;

  StreamSubscription<ServiceNotificationEvent>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _initNFCListener();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _actualizarWidgetNativo();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final dataTxs = prefs.getString('eroski_tx_v2');
    final dataOtros = prefs.getString('eroski_otros_v1');
    final dataHist = prefs.getString('eroski_history_v1');
    final dataIncomes = prefs.getString('eroski_incomes_v1');
    final dataIaHist = prefs.getString('eroski_ia_history_v1');
    
    _cargoPendienteBanco = prefs.getDouble('cargo_pendiente_kutxa') ?? 0.0;
    _groqApiKey = prefs.getString('groq_api_key') ?? "";
    _ultimoConsejoIA = prefs.getString('ultimo_consejo_ia') ?? "";
    _ultimoInformeBody = prefs.getString('ultimo_informe_body') ?? "";
    _ultimoTotalAnalizado = prefs.getDouble('ultimo_total_analizado') ?? 0.0;

    if (dataTxs != null) setState(() => _txs = List<Map<String, dynamic>>.from(jsonDecode(dataTxs)));
    if (dataOtros != null) setState(() => _otrosGastos = List<Map<String, dynamic>>.from(jsonDecode(dataOtros)));
    if (dataHist != null) setState(() => _history = List<Map<String, dynamic>>.from(jsonDecode(dataHist)));
    if (dataIaHist != null) setState(() => _iaHistory = List<Map<String, dynamic>>.from(jsonDecode(dataIaHist)));
    
    if (dataIncomes != null) {
      setState(() => _incomes = List<Map<String, dynamic>>.from(jsonDecode(dataIncomes)));
    } else {
      setState(() => _incomes = [
        {'id': '1', 'titulo': 'Nómina', 'importe': 2330.0},
        {'id': '2', 'titulo': 'Pensión Aitor', 'importe': 445.0},
        {'id': '3', 'titulo': 'Mikel (Garaje)', 'importe': 90.0},
      ]);
      _saveData();
    }
    
    _limpiarGastosExtraAntiguos();
    _actualizarWidgetNativo();
  }

  void _limpiarGastosExtraAntiguos() {
    DateTime now = DateTime.now();
    DateTime inicioCiclo;
    if (now.day >= 29) {
      inicioCiclo = DateTime(now.year, now.month, 29);
    } else {
      inicioCiclo = DateTime(now.year, now.month - 1, 29);
    }
    setState(() {
      for (var i = _otrosGastos.length - 1; i >= 0; i--) {        if (DateTime.parse(_otrosGastos[i]['fecha']).isBefore(inicioCiclo)) {
          if (_otrosGastos[i]['recurrente'] == true) {
            _otrosGastos[i]['fecha'] = DateTime.now().toIso8601String();
          } else {
            _otrosGastos.removeAt(i);
          }
        }
      }
    });
    _saveData();
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('eroski_tx_v2', jsonEncode(_txs));
    await prefs.setString('eroski_otros_v1', jsonEncode(_otrosGastos));
    await prefs.setString('eroski_history_v1', jsonEncode(_history));
    await prefs.setString('eroski_incomes_v1', jsonEncode(_incomes));
    await prefs.setString('eroski_ia_history_v1', jsonEncode(_iaHistory));
    await prefs.setDouble('cargo_pendiente_kutxa', _cargoPendienteBanco);
    await prefs.setString('groq_api_key', _groqApiKey);
    await prefs.setString('ultimo_consejo_ia', _ultimoConsejoIA);
    await prefs.setString('ultimo_informe_body', _ultimoInformeBody);
    await prefs.setDouble('ultimo_total_analizado', _ultimoTotalAnalizado);
    _actualizarWidgetNativo();
  }

  Future<void> _actualizarWidgetNativo() async {
    double totalDeuda = _txs.fold(0.0, (s, t) => s + t['importe']);
    double totalOtros = _otrosGastos.fold(0.0, (s, t) => s + t['importe']);
    try {
      await HomeWidget.saveWidgetData<String>('total', '${(totalDeuda + totalOtros).toStringAsFixed(2)} €');
      await HomeWidget.saveWidgetData<String>('cargo', 'Deuda Activa');
      await HomeWidget.saveWidgetData<String>('sync', 'Actualizado: ${DateFormat('HH:mm').format(DateTime.now())}');
      await HomeWidget.updateWidget(name: 'EroskiWidgetProvider', androidName: 'EroskiWidgetProvider');
    } catch (e) {}
  }

  double _getIngresosTotales() {
    return _incomes.fold(0.0, (s, i) => s + i['importe']);
  }

  void _eliminarItem(String id, String tipo) {
    setState(() { 
      if (tipo == 'tx') _txs.removeWhere((t) => t['id'] == id);
      else _otrosGastos.removeWhere((t) => t['id'] == id);
    });
    _saveData();
  }
  Future<void> _initNFCListener() async {
    bool granted = await NotificationListenerService.isPermissionGranted();
    if (!granted) await NotificationListenerService.requestPermission();
    setState(() => _isListening = true);
    _sub = NotificationListenerService.notificationsStream.listen((event) {
      if (event.hasRemoved != null && event.hasRemoved!) return;
      String pkg = event.packageName?.toLowerCase() ?? '';
      if (pkg.contains('wallet') || pkg.contains('kutxa') || pkg.contains('bbk') || pkg.contains('eroski') || pkg.contains('gms') || pkg.contains('pay')) {
        _parseNotification(event.title ?? '', event.content ?? '');
      }
    });
  }

  void _parseNotification(String title, String content) {
    String fullText = "$title $content".toLowerCase();
    RegExp reg = RegExp(r'(\d+[.,]\d{2})\s*(€|EUR)', caseSensitive: false);
    var match = reg.firstMatch("$title $content");

    if (fullText.contains('recibo') || fullText.contains('transferencia') || fullText.contains('ingreso') || fullText.contains('cargo en cuenta') || fullText.contains('liquidación') || fullText.contains('cuota')) return; 

    if (match != null) {
      double importe = double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? 0.0;
      String comercio = title.replaceAll(RegExp(r'(\d+[.,]\d{2})\s*(€|EUR)', caseSensitive: false), '').trim();
      if (comercio.isEmpty) comercio = "Pago NFC";
      
      DateTime now = DateTime.now();
      bool esDuplicado = _txs.any((tx) {
        if (tx['importe'] == importe && tx['comercio'] == comercio) {
          if (now.difference(DateTime.parse(tx['fecha'])).inMinutes < 10) return true;
        }
        return false;
      });
      if (esDuplicado) return;
      if (importe > 0) {
        setState(() { _txs.insert(0, {'id': DateTime.now().millisecondsSinceEpoch.toString(), 'fecha': DateTime.now().toIso8601String(), 'comercio': comercio, 'importe': importe}); });
        _saveData();
      }
    }
  }

  void _mostrarGestionIngresos() {
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setStateDialog) => AlertDialog(title: const Text("Mis Ingresos Fijos"), content: SizedBox(width: double.maxFinite, child: Column(mainAxisSize: MainAxisSize.min, children: [..._incomes.map((inc) => ListTile(title: Text(inc['titulo']), subtitle: Text("${inc['importe']} €"), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () { setState(() => _incomes.removeWhere((i) => i['id'] == inc['id'])); setStateDialog(() {}); _saveData(); }))), const Divider(), ElevatedButton.icon(onPressed: () => _mostrarDialogoNuevoIngreso(setStateDialog), icon: const Icon(Icons.add), label: const Text("Añadir Ingreso"))])), actions: [TextButton(onPressed: () { Navigator.pop(ctx); setState((){}); }, child: const Text("CERRAR"))])));
  }

  void _mostrarDialogoNuevoIngreso(Function refreshParent) {
    TextEditingController tCtrl = TextEditingController(); TextEditingController iCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Nuevo Ingreso"), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: tCtrl, decoration: const InputDecoration(labelText: "Concepto")), TextField(controller: iCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Importe (€)"))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")), TextButton(onPressed: () { if (tCtrl.text.isNotEmpty && iCtrl.text.isNotEmpty) { setState(() { _incomes.add({'id': DateTime.now().toString(), 'titulo': tCtrl.text, 'importe': double.parse(iCtrl.text.replaceAll(',', '.'))}); }); refreshParent(() {}); _saveData(); Navigator.pop(ctx); } }, child: const Text("GUARDAR"))]));
  }

  void _mostrarDialogoPagoManual() {    TextEditingController comCtrl = TextEditingController(); TextEditingController impCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: Colors.white, title: const Text("Añadir Pago Manual Tarjeta"), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: comCtrl, decoration: const InputDecoration(labelText: "Comercio")), const SizedBox(height: 10), TextField(controller: impCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Importe (€)"))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFCC0000), foregroundColor: Colors.white), onPressed: () { 
              double imp = double.tryParse(impCtrl.text.replaceAll(',', '.')) ?? 0.0; 
              imp = imp.abs(); 
              if (imp > 0 && comCtrl.text.isNotEmpty) { 
                  setState(() { _txs.insert(0, {'id': DateTime.now().millisecondsSinceEpoch.toString(), 'fecha': DateTime.now().toIso8601String(), 'comercio': comCtrl.text + " (Manual)", 'importe': imp}); }); 
                  _saveData(); Navigator.pop(ctx); 
              } 
          }, child: const Text("GUARDAR"))]));
  }

  void _mostrarDialogoGastoExtra() {
    TextEditingController comCtrl = TextEditingController(); TextEditingController impCtrl = TextEditingController();
    bool esRecurrente = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setStateDialog) => AlertDialog(backgroundColor: Colors.white, title: const Text("Añadir Recibo"), content: Column(mainAxisSize: MainAxisSize.min, children: [const Text("Estos gastos no afectan al cuadre de la tarjeta, pero restan de tu saldo mensual.", style: TextStyle(fontSize: 12, color: Colors.grey)), const SizedBox(height: 10), TextField(controller: comCtrl, decoration: const InputDecoration(labelText: "Concepto (Ej: Luz)")), const SizedBox(height: 10), TextField(controller: impCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Importe (€)")), CheckboxListTile(title: const Text("Se repite cada mes", style: TextStyle(fontSize: 13)), value: esRecurrente, onChanged: (v) => setStateDialog(() => esRecurrente = v!))]), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white), onPressed: () { double imp = double.tryParse(impCtrl.text.replaceAll(',', '.')) ?? 0.0; imp = imp.abs(); if (imp > 0 && comCtrl.text.isNotEmpty) { setState(() { _otrosGastos.insert(0, {'id': DateTime.now().millisecondsSinceEpoch.toString(), 'fecha': DateTime.now().toIso8601String(), 'comercio': comCtrl.text, 'importe': imp, 'recurrente': esRecurrente, 'tipo': 'extra'}); }); _saveData(); Navigator.pop(ctx); } }, child: const Text("GUARDAR"))])));
  }

  void _editarGastoExtra(String id, String comercioActual, double importeActual, bool recurrenteActual) {
    TextEditingController comCtrl = TextEditingController(text: comercioActual);
    TextEditingController impCtrl = TextEditingController(text: importeActual.toString());
    bool esRecurrente = recurrenteActual;

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setStateDialog) => AlertDialog(
      backgroundColor: Colors.white, title: const Text("Editar Recibo"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: comCtrl, decoration: const InputDecoration(labelText: "Concepto")), const SizedBox(height: 10), TextField(controller: impCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Importe (€)")), CheckboxListTile(title: const Text("Se repite cada mes", style: TextStyle(fontSize: 13)), value: esRecurrente, onChanged: (v) => setStateDialog(() => esRecurrente = v!))]),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800, foregroundColor: Colors.white), onPressed: () { double imp = double.tryParse(impCtrl.text.replaceAll(',', '.')) ?? 0.0; imp = imp.abs(); if (imp > 0 && comCtrl.text.isNotEmpty) { setState(() { int idx = _otrosGastos.indexWhere((g) => g['id'] == id); if (idx != -1) { _otrosGastos[idx]['comercio'] = comCtrl.text; _otrosGastos[idx]['importe'] = imp; _otrosGastos[idx]['recurrente'] = esRecurrente; } }); _saveData(); Navigator.pop(ctx); } }, child: const Text("GUARDAR"))]
    )));
  }

  Future<void> _exportarDatosFichero() async {
    try { String backupJSON = jsonEncode({'activos': _txs, 'otros': _otrosGastos, 'historial': _history, 'ingresos': _incomes, 'ia_history': _iaHistory}); final dir = await getApplicationDocumentsDirectory(); String fileName = 'EroskiTracker_Backup_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.json'; final file = File('${dir.path}/$fileName'); await file.writeAsString(backupJSON); await Share.shareXFiles([XFile(file.path)], text: 'Copia de seguridad Tracker Pro'); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al exportar.'), backgroundColor: Colors.red)); }
  }

  Future<void> _exportarBovedaCSV() async {
    try { String csv = "FECHA_INICIO;FECHA_FIN;ESPERADO_EUR;REAL_BANCO_EUR;DESCUADRE\n"; for (var h in _history) { double descuadre = h['real'] - h['esperado']; csv += "${DateFormat('dd/MM/yyyy').format(DateTime.parse(h['inicio_ciclo']))};${DateFormat('dd/MM/yyyy').format(DateTime.parse(h['fin_ciclo']))};${h['esperado']};${h['real']};${descuadre.toStringAsFixed(2)}\n"; } final dir = await getApplicationDocumentsDirectory(); String fileName = 'Boveda_Export_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.csv'; final file = File('${dir.path}/$fileName'); await file.writeAsString(csv); await Share.shareXFiles([XFile(file.path)], text: 'Exportación Bóveda CSV Excel'); } catch (e) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error al exportar CSV.'), backgroundColor: Colors.red)); }
  }

  Future<void> _importarDatosFichero() async {
    try { FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json', 'txt']); if (result != null) { File file = File(result.files.single.path!); String contenido = await file.readAsString(); final parsed = jsonDecode(contenido); setState(() { if (parsed['activos'] != null) _txs = List<Map<String, dynamic>>.from(parsed['activos']); if (parsed['otros'] != null) _otrosGastos = List<Map<String, dynamic>>.from(parsed['otros']); if (parsed['historial'] != null) _history = List<Map<String, dynamic>>.from(parsed['historial']); if (parsed['ingresos'] != null) _incomes = List<Map<String, dynamic>>.from(parsed['ingresos']); if (parsed['ia_history'] != null) _iaHistory = List<Map<String, dynamic>>.from(parsed['ia_history']); }); _saveData(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Restaurado con éxito."), backgroundColor: Colors.green)); } } catch (e) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Error: Fichero inválido."), backgroundColor: Colors.red)); }
  }

  void _abrirMenuAcciones() {
    showModalBottomSheet(context: context, shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), builder: (ctx) => SafeArea(
        child: Wrap(children: [
            const Padding(padding: EdgeInsets.all(16.0), child: Text("Menú Rápido", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blueGrey))),
            ListTile(leading: const CircleAvatar(backgroundColor: Color(0xFFE8F5E9), child: Icon(Icons.account_balance, color: Colors.green)), title: const Text("Configurar Ingresos Mensuales"), onTap: () { Navigator.pop(ctx); _mostrarGestionIngresos(); }),
            ListTile(leading: CircleAvatar(backgroundColor: Colors.orange.shade50, child: Icon(Icons.receipt_long, color: Colors.orange.shade800)), title: const Text("Añadir Recibo (Luz, Agua, etc.)"), subtitle: const Text("Con opción de repetición mensual"), onTap: () { Navigator.pop(ctx); _mostrarDialogoGastoExtra(); }),
            ListTile(leading: const CircleAvatar(backgroundColor: Color(0xFFFFEBEE), child: Icon(Icons.add, color: Color(0xFFCC0000))), title: const Text("Añadir Pago Tarjeta Manual"), onTap: () { Navigator.pop(ctx); _mostrarDialogoPagoManual(); }),
            ListTile(leading: const CircleAvatar(backgroundColor: Color(0xFFE3F2FD), child: Icon(Icons.auto_awesome, color: Color(0xFF0055A5))), title: const Text("Cuadre Inteligente Automático"), subtitle: const Text("La app busca los tickets sola"), onTap: () { Navigator.pop(ctx); _iniciarCierreInteligente(); }),
            ListTile(leading: const CircleAvatar(backgroundColor: Color(0xFFE3F2FD), child: Icon(Icons.checklist, color: Color(0xFF0055A5))), title: const Text("Cuadre Manual (Seleccionar tickets)"), subtitle: const Text("Tú eliges qué tickets van a la bóveda"), onTap: () { Navigator.pop(ctx); _mostrarCuadreManual(); }),            const Divider(),
            ListTile(leading: const CircleAvatar(backgroundColor: Colors.black12, child: Icon(Icons.table_chart, color: Colors.black87)), title: const Text("Exportar Bóveda a Excel (.csv)"), onTap: () { Navigator.pop(ctx); _exportarBovedaCSV(); }),
            ListTile(leading: const CircleAvatar(backgroundColor: Colors.black12, child: Icon(Icons.file_upload, color: Colors.black87)), title: const Text("Exportar Backup (.json)"), onTap: () { Navigator.pop(ctx); _exportarDatosFichero(); }),
        ])
    ));
  }

  void _iniciarCierreInteligente() {
    TextEditingController bancoCtrl = TextEditingController(text: _cargoPendienteBanco > 0 ? _cargoPendienteBanco.toStringAsFixed(2) : "");
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Cuadre Automático"),
      content: TextField(controller: bancoCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Cifra del banco")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
        ElevatedButton(onPressed: () {
          double obj = double.tryParse(bancoCtrl.text.replaceAll(',', '.')) ?? 0;
          List<String>? magia = _buscarCombinacionMagica(obj);
          if (magia != null) { _archivarSeleccion(magia, obj); Navigator.pop(ctx); } 
          else { setState(() => _cargoPendienteBanco = obj); _saveData(); Navigator.pop(ctx); }
        }, child: const Text("CUADRAR"))
      ],
    ));
  }

  void _mostrarCuadreManual() {
    if (_txs.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay tickets de tarjeta para archivar.'))); return; }
    List<String> seleccionados = [];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setStateDialog) {
      double sum = _txs.where((t) => seleccionados.contains(t['id'])).fold(0.0, (s, t) => s + t['importe']);
      return AlertDialog(
        title: const Text("Cuadre Manual"),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10)), child: Text("Suma elegida: ${sum.toStringAsFixed(2)} €", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF0055A5)))),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true, itemCount: _txs.length,
                  itemBuilder: (c, i) {
                    var tx = _txs[i];
                    bool isSel = seleccionados.contains(tx['id']);
                    return CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(tx['comercio'], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                      subtitle: Text("${tx['importe']} €", style: const TextStyle(color: Colors.red)),
                      value: isSel,
                      onChanged: (val) { setStateDialog(() { if (val == true) seleccionados.add(tx['id']); else seleccionados.remove(tx['id']); }); }                    );
                  }
                )
              )
            ]
          )
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0055A5), foregroundColor: Colors.white),
            onPressed: seleccionados.isEmpty ? null : () {
              Navigator.pop(ctx);
              _pedirCifraBancoParaManual(seleccionados, sum);
            },
            child: const Text("CONTINUAR")
          )
        ]
      );
    }));
  }

  void _pedirCifraBancoParaManual(List<String> ids, double sumEsperado) {
    TextEditingController bancoCtrl = TextEditingController(text: sumEsperado.toStringAsFixed(2));
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Confirmar Cifra Real"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text("Has agrupado tickets. ¿Cuánto te ha cobrado el banco exactamente por ellos? (Si hay descuadre, lo guardaremos).", style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 10),
        TextField(controller: bancoCtrl, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: "Cifra real del banco (€)"))
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white), onPressed: () {
          double real = double.tryParse(bancoCtrl.text.replaceAll(',', '.')) ?? sumEsperado;
          _archivarSeleccion(ids, real);
          Navigator.pop(ctx);
        }, child: const Text("ARCHIVAR EN BÓVEDA"))
      ]
    ));
  }

  void _archivarSeleccion(List<String> ids, double real) {
    var aArchivar = _txs.where((t) => ids.contains(t['id'])).toList();
    if (aArchivar.isEmpty) return;
    _history.insert(0, {
      'id': DateTime.now().toString(),
      'inicio_ciclo': aArchivar.last['fecha'],
      'fin_ciclo': aArchivar.first['fecha'],
      'esperado': aArchivar.fold(0.0, (s, t) => s + t['importe']),      'real': real,
      'txs': aArchivar
    });
    setState(() { _txs.removeWhere((t) => ids.contains(t['id'])); _cargoPendienteBanco = 0; });
    _saveData();
  }

  List<String>? _buscarCombinacionMagica(double obj) {
    return _recurse(_txs, obj, 0, 0, []);
  }

  List<String>? _recurse(List<Map> cands, double obj, int idx, double sum, List<String> sel) {
    if ((sum - obj).abs() < 0.05) return List.from(sel);
    if (idx >= cands.length || sum > obj + 1) return null;
    sel.add(cands[idx]['id']);
    var r = _recurse(cands, obj, idx+1, sum + cands[idx]['importe'], sel);
    if (r != null) return r;
    sel.removeLast();
    return _recurse(cands, obj, idx+1, sum, sel);
  }

  Future<void> _consultarIA() async {
    if (_groqApiKey.isEmpty) { _mostrarAjustesAPI(); return; }
    setState(() => _isLoadingIA = true);
    
    double totalTx = _txs.fold(0.0, (s, t) => s + t['importe']);
    double totalOtros = _otrosGastos.fold(0.0, (s, t) => s + t['importe']);
    double totalSuma = totalTx + totalOtros;
    double ingresos = _getIngresosTotales();
    
    String txsStr = _txs.map((t) => "[Tarjeta] ${t['comercio']}: ${t['importe']}€").join("\n");
    String otrosStr = _otrosGastos.map((t) => "[Recibo Fijo] ${t['comercio']}: ${t['importe']}€").join("\n");
    
    DateTime now = DateTime.now();
    DateTime inicioCiclo; DateTime finCiclo;
    if (now.day >= 29) { inicioCiclo = DateTime(now.year, now.month, 29); finCiclo = DateTime(now.year, now.month + 1, 28); } 
    else { inicioCiclo = DateTime(now.year, now.month - 1, 29); finCiclo = DateTime(now.year, now.month, 28); }

    try {
      final res = await http.post(Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
        headers: {'Authorization': 'Bearer $_groqApiKey', 'Content-Type': 'application/json'},
        body: jsonEncode({
          "model": "openai/gpt-oss-120b",
          "messages": [
            {"role": "system", "content": "Eres un Asesor Financiero. Ciclo de facturación del 29 al 28. Ingresos: $ingresos€. Analiza los gastos (tarjeta y recibos), calcula la proyección de gasto hasta el día 28 y di cuánto saldo le quedará. Usa texto plano y emojis. Al final escribe 'ALERTA: [consejo corto]'."},
            {"role": "user", "content": "Hoy es ${now.day}/${now.month}. Ciclo actual: ${inicioCiclo.day}/${inicioCiclo.month} al ${finCiclo.day}/${finCiclo.month}.\nGastos:\n$txsStr\n$otrosStr"}
          ],
          "temperature": 0.1
        }));
      if (res.statusCode == 200) {        String body = jsonDecode(utf8.decode(res.bodyBytes))['choices'][0]['message']['content'];
        setState(() { 
          _ultimoInformeBody = body; 
          _ultimoTotalAnalizado = totalSuma;
          _iaHistory.insert(0, {'id': DateTime.now().millisecondsSinceEpoch.toString(), 'fecha': DateTime.now().toIso8601String(), 'informe': body});
          var m = RegExp(r'ALERTA:\s*(.*)').firstMatch(body);
          if (m != null) _ultimoConsejoIA = m.group(1) ?? "";
        });
        _saveData();
        _mostrarRespuestaIAFullPantalla(body);
      }
    } catch (e) {} finally { setState(() => _isLoadingIA = false); }
  }

  bool _isLoadingIA = false;
  
  void _imprimirTextoGenerico(String texto, String titulo) async {
    String printText = "      $titulo      \n--------------------------------\n\n$texto\n\n--------------------------------\n\n\n\n";
    try { await launchUrl(Uri.parse("rawbt:base64,${base64Encode(utf8.encode(printText))}")); } catch (e) { }
  }

  void _mostrarRespuestaIAFullPantalla(String m) {
    Navigator.push(context, MaterialPageRoute(builder: (c) => Scaffold(appBar: AppBar(title: const Text("Asesor IA"), backgroundColor: Colors.purple, foregroundColor: Colors.white, actions: [IconButton(icon: const Icon(Icons.print, color: Colors.white), onPressed: () => _imprimirTextoGenerico(m, "INFORME ASESOR IA"))]), body: SingleChildScrollView(padding: const EdgeInsets.all(24), child: Text(m, style: const TextStyle(fontSize: 16, height: 1.6))))));
  }

  void _mostrarHistorialIA() {
    if (_iaHistory.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Aún no hay informes guardados.'))); return; }
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Bóveda de Informes IA"), content: SizedBox(width: double.maxFinite, child: ListView.builder(shrinkWrap: true, itemCount: _iaHistory.length, itemBuilder: (c, i) { var item = _iaHistory[i]; return Card(elevation: 0, color: Colors.purple.shade50, margin: const EdgeInsets.only(bottom: 8), child: ListTile(leading: const Icon(Icons.smart_toy, color: Colors.purple), title: Text(DateFormat('dd/MM/yyyy - HH:mm').format(DateTime.parse(item['fecha'])), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), subtitle: Text(item['informe'].substring(0, 40).replaceAll('\n', ' ') + "...", style: const TextStyle(fontSize: 12)), trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () { setState(() { _iaHistory.removeAt(i); }); _saveData(); Navigator.pop(ctx); _mostrarHistorialIA(); }), onTap: () { Navigator.pop(ctx); _mostrarRespuestaIAFullPantalla(item['informe']); })); })), actions: [TextButton(onPressed: ()=>Navigator.pop(ctx), child: const Text("CERRAR"))]));
  }

  void _mostrarAjustesAPI() {
    TextEditingController c = TextEditingController(text: _groqApiKey);
    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text("Ajustes API"), content: TextField(controller: c, obscureText: true, decoration: const InputDecoration(labelText: "Groq Key")), actions: [TextButton(onPressed: () { setState(() => _groqApiKey = c.text); _saveData(); Navigator.pop(ctx); }, child: const Text("GUARDAR"))]));
  }

  void _imprimirLista(List txsParaImprimir, String titulo, double total) {
    if (txsParaImprimir.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No hay datos.'))); return; }
    String ticket = "      EROSKI-KUTXA TRACKER      \n--------------------------------\n$titulo\n--------------------------------\n";
    for (var tx in txsParaImprimir.reversed) { String com = tx['comercio'].toString().toUpperCase(); if (com.length > 20) com = com.substring(0, 20); String imp = tx['importe'].toStringAsFixed(2) + " EUR"; ticket += "${com.padRight(21)} ${imp.padLeft(10)}\n"; }
    ticket += "--------------------------------\nTOTAL: ${total.toStringAsFixed(2).padLeft(16)} EUR\n--------------------------------\n\n\n\n";
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: const Color(0xFFFFFFF0), title: const Row(children: [Icon(Icons.receipt_long), SizedBox(width: 10), Text("Pre-Impresión")]), content: SingleChildScrollView(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400)), child: Text(ticket, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)))), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")), ElevatedButton.icon(onPressed: () async { Navigator.pop(ctx); try { await launchUrl(Uri.parse("rawbt:base64,${base64Encode(utf8.encode(ticket))}")); } catch (e) {} }, icon: const Icon(Icons.print), label: const Text("RawBT"), style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white))]));
  }

  void _preguntarBorrarCargoPendiente() {
    showDialog(context: context, builder: (ctx) => AlertDialog(backgroundColor: Colors.white, title: const Text("¿Borrar cargo pendiente?"), content: const Text("¿Te has equivocado al meter la cifra de Kutxabank? Puedes borrar esta alerta y el importe pendiente quedará a cero."), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("CANCELAR")), ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white), onPressed: () { setState(() { _cargoPendienteBanco = 0.0; }); _saveData(); Navigator.pop(ctx); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cargo cancelado.'))); }, child: const Text("BORRAR"))]));
  }

  Widget _buildDashboard() {
    double totalTx = _txs.fold(0.0, (s, t) => s + t['importe']);
    double totalOtros = _otrosGastos.fold(0.0, (s, t) => s + t['importe']);    double totalGeneral = totalTx + totalOtros;
    double ingresos = _getIngresosTotales();
    double porc = ingresos > 0 ? (totalGeneral / ingresos).clamp(0.0, 1.0) : 0.0;

    List<Map<String, dynamic>> listaCombinada = [
      ..._txs.map((t) => {...t, 'tipo': 'tx'}),
      ..._otrosGastos.map((e) => {...e, 'tipo': 'extra'})
    ];
    listaCombinada.sort((a, b) => DateTime.parse(b['fecha']).compareTo(DateTime.parse(a['fecha'])));

    return Column(children: [
      Container(
        width: double.infinity, padding: const EdgeInsets.all(28),
        decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFCC0000), Color(0xFFAA0000)]), borderRadius: BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))),
        child: Column(children: [
          const Text("GASTO TOTAL DEL MES", style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold)),
          Text("${totalGeneral.toStringAsFixed(2)} €", style: const TextStyle(color: Colors.white, fontSize: 50, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          LinearProgressIndicator(value: porc, backgroundColor: Colors.white24, color: porc > 0.8 ? Colors.yellow : Colors.greenAccent),
          Text("${(porc * 100).toStringAsFixed(1)}% de mis ingresos gastados", style: const TextStyle(color: Colors.white60, fontSize: 11)),
          const SizedBox(height: 16),
          if (_cargoPendienteBanco > 0)
             GestureDetector(onTap: _preguntarBorrarCargoPendiente, child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.orange.shade800, borderRadius: BorderRadius.circular(20)), child: Row(mainAxisSize: MainAxisSize.min, children: [Text('⚠️ Esperando tickets por ${_cargoPendienteBanco.toStringAsFixed(2)}€', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), const SizedBox(width: 8), const Icon(Icons.cancel, color: Colors.white70, size: 18)])))
          else
             Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(20)), child: Text('Deuda Tarjeta: ${totalTx.toStringAsFixed(2)}€ | Recibos: ${totalOtros.toStringAsFixed(2)}€', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        ]),
      ),
      if (_ultimoConsejoIA.isNotEmpty) Padding(padding: const EdgeInsets.all(16), child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.purple.shade200)), child: Row(children: [const Icon(Icons.lightbulb, color: Colors.purple), const SizedBox(width: 10), Expanded(child: Text(_ultimoConsejoIA, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple)))]))),
      Expanded(child: ListView.builder(itemCount: listaCombinada.length, padding: const EdgeInsets.symmetric(horizontal: 16), itemBuilder: (c, i) {
        var item = listaCombinada[i];
        bool isExtra = item['tipo'] == 'extra';
        return Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: isExtra ? Colors.orange.shade200 : Colors.grey.shade200)), margin: const EdgeInsets.only(bottom: 8), child: ListTile(
          leading: CircleAvatar(backgroundColor: isExtra ? Colors.orange.shade50 : const Color(0xFFF0F4F8), child: Icon(isExtra ? Icons.receipt_long : Icons.contactless, color: isExtra ? Colors.orange.shade800 : const Color(0xFF0055A5))), 
          title: Text(item['comercio'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
          subtitle: Text(DateFormat('dd/MM - HH:mm', 'es_ES').format(DateTime.parse(item['fecha'])), style: TextStyle(fontSize: 12, color: isExtra ? Colors.orange.shade800 : Colors.grey)), 
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (isExtra && item['recurrente'] == true) const Icon(Icons.repeat, color: Colors.orange, size: 16),
            const SizedBox(width: 4),
            Text("-${item['importe'].abs().toStringAsFixed(2)} €", style: TextStyle(color: isExtra ? Colors.orange.shade800 : Colors.red, fontWeight: FontWeight.bold, fontSize: 16)), 
            if (isExtra) IconButton(icon: const Icon(Icons.edit, color: Colors.grey, size: 20), onPressed: () => _editarGastoExtra(item['id'], item['comercio'], item['importe'], item['recurrente'] ?? false)),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20), onPressed: () => _eliminarItem(item['id'], item['tipo']))
          ])
        ));
      }))
    ]);
  }

  Widget _buildAnalytics() {
    DateTime now = DateTime.now();
    DateTime inicioCiclo; DateTime finCiclo;    if (now.day >= 29) { inicioCiclo = DateTime(now.year, now.month, 29); finCiclo = DateTime(now.year, now.month + 1, 28, 23, 59, 59); } 
    else { inicioCiclo = DateTime(now.year, now.month - 1, 29); finCiclo = DateTime(now.year, now.month, 28, 23, 59, 59); }

    int diasTranscurridos = now.difference(inicioCiclo).inDays + 1; 
    int diasTotalesCiclo = finCiclo.difference(inicioCiclo).inDays + 1;

    Map<int, double> gastosPorDia = {1:0, 2:0, 3:0, 4:0, 5:0, 6:0, 7:0}; 
    double totalGastoMensual = 0; double maxGasto = 0; 

    for(var tx in _txs) {
      if (tx['importe'] <= 0) continue; 
      DateTime d = DateTime.parse(tx['fecha']);
      if (d.isBefore(inicioCiclo)) continue;

      int dia = d.weekday;
      gastosPorDia[dia] = (gastosPorDia[dia] ?? 0) + tx['importe'];
      totalGastoMensual += tx['importe'];
      if(gastosPorDia[dia]! > maxGasto) { maxGasto = gastosPorDia[dia]!; }
    }
    for(var extra in _otrosGastos) {
      if (extra['importe'] <= 0) continue;
      DateTime d = DateTime.parse(extra['fecha']);
      if (d.isBefore(inicioCiclo)) continue;
      totalGastoMensual += extra['importe'];
    }
    
    double avgDiaria = totalGastoMensual / diasTranscurridos; 
    double proy = avgDiaria * diasTotalesCiclo; 
    double ingresos = _getIngresosTotales();
    double saldo = ingresos - proy;

    return SingleChildScrollView(padding: const EdgeInsets.all(24), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text("Ciclo: ${inicioCiclo.day}/${inicioCiclo.month} al ${finCiclo.day}/${finCiclo.month}", style: const TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      const Text("Tendencia Deuda Actual", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0055A5))),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ const Icon(Icons.analytics_outlined, size: 20, color: Color(0xFF0055A5)), const SizedBox(height: 8), const Text("Promedio Diario", style: TextStyle(fontSize: 12, color: Colors.grey)), Text("${avgDiaria.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0055A5))) ]))),
          const SizedBox(width: 12),
          Expanded(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.grey.shade200)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ const Icon(Icons.trending_up, size: 20, color: Colors.redAccent), const SizedBox(height: 8), const Text("Pico Tarjeta", style: TextStyle(fontSize: 12, color: Colors.grey)), Text("${maxGasto.toStringAsFixed(2)} €", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.redAccent)) ]))),
        ],
      ),
      const SizedBox(height: 24),
      SizedBox(
        height: 250,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround, maxY: max(maxGasto + 20, 50),
            barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(tooltipBgColor: const Color(0xFF0055A5), getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem("${rod.toY.toStringAsFixed(2)} €", const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),            titlesData: FlTitlesData(
              show: true, bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, getTitlesWidget: (value, meta) { const dias = ['L', 'M', 'X', 'J', 'V', 'S', 'D']; return Padding(padding: const EdgeInsets.only(top: 8.0), child: Text(dias[value.toInt() - 1], style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))); })),
              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)), rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
            ),
            gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 50, getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade300, strokeWidth: 1)),
            extraLinesData: ExtraLinesData(horizontalLines: [ HorizontalLine(y: avgDiaria, color: Colors.orange.withOpacity(0.8), strokeWidth: 2, dashArray: [5, 5], label: HorizontalLineLabel(show: true, labelResolver: (_) => 'Media', style: const TextStyle(fontSize: 10, color: Colors.orange))) ]),
            borderData: FlBorderData(show: false),
            barGroups: gastosPorDia.entries.map((e) => BarChartGroupData(x: e.key, barRods: [BarChartRodData(toY: e.value, color: e.value > avgDiaria ? const Color(0xFFCC0000) : const Color(0xFF0055A5), width: 18, borderRadius: BorderRadius.circular(4))])).toList(),
          )
        ),
      ),
      const SizedBox(height: 32),
      const Text("Proyección a Fin de Mes", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF0055A5))),
      const SizedBox(height: 20),
      Container(
        padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: saldo < 0 ? Colors.red.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(20), border: Border.all(color: saldo < 0 ? Colors.red : Colors.green)),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Día 28 Saldo Estimado:"), Text("${saldo.toStringAsFixed(2)} €", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: saldo < 0 ? Colors.red : Colors.green))]),
          const Divider(),
          Text("Ingresos: $ingresos€  |  Proyectado ($diasTotalesCiclo días): ${proy.toStringAsFixed(2)}€", style: const TextStyle(fontSize: 12)),
        ]),
      ),
      const SizedBox(height: 30),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(gradient: const LinearGradient(colors: [Colors.purple, Colors.deepPurple]), borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 4))]),
        child: Column(
          children: [
            const Icon(Icons.smart_toy, color: Colors.white, size: 50),
            const SizedBox(height: 16),
            const Text("Oráculo Analítico de Gastos", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            _isLoadingIA 
              ? const CircularProgressIndicator(color: Colors.white)
              : ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.purple, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
                  icon: const Icon(Icons.analytics), label: const Text("ANALIZAR AHORA", style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _consultarIA,
                ),
            const SizedBox(height: 16),
            TextButton.icon(onPressed: _mostrarHistorialIA, icon: const Icon(Icons.history, color: Colors.white70), label: const Text("Ver Historial de IA", style: TextStyle(color: Colors.white70)))
          ],
        ),
      )
    ]));
  }

  Widget _buildHistoryTab() {
    return ListView.builder(itemCount: _history.length, padding: const EdgeInsets.all(16), itemBuilder: (c, i) => Card(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: Colors.grey.shade200)), child: ExpansionTile(leading: CircleAvatar(backgroundColor: Colors.green.shade50, child: const Icon(Icons.verified_rounded, color: Colors.green)), title: Text("${DateFormat('dd MMM').format(DateTime.parse(_history[i]['inicio_ciclo']))} - ${DateFormat('dd MMM yyyy').format(DateTime.parse(_history[i]['fin_ciclo']))}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), subtitle: Text("Banco: ${_history[i]['real']} €", style: const TextStyle(color: Colors.grey, fontSize: 12)), trailing: IconButton(icon: const Icon(Icons.print, color: Colors.black54), onPressed: () => _imprimirLista(_history[i]['txs'], "FACTURACIÓN", _history[i]['esperado'])), children: [ Container(padding: const EdgeInsets.all(16), color: const Color(0xFFF9F9F9), child: Column(children: (_history[i]['txs'] as List).map((t) => Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Expanded(child: Text(t['comercio'], style: const TextStyle(fontSize: 13))), Text("${t['importe'].toStringAsFixed(2)} €", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))]))).toList())) ])));  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Tracker Pro v18.13.0", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)), backgroundColor: const Color(0xFFCC0000), iconTheme: const IconThemeData(color: Colors.white), actions: [IconButton(icon: const Icon(Icons.settings, color: Colors.white), onPressed: _mostrarAjustesAPI), IconButton(icon: const Icon(Icons.print, color: Colors.white), onPressed: () => _imprimirLista(_txs, "TICKETS PENDIENTES DE FACTURAR", _txs.fold(0.0, (s, t) => s + t['importe']))), Icon(_isListening ? Icons.nfc : Icons.nfc_outlined, color: _isListening ? Colors.greenAccent : Colors.white54), const SizedBox(width: 16)]),
      body: IndexedStack(index: _currentIndex, children: [_buildDashboard(), _buildAnalytics(), _buildHistoryTab()]),
      floatingActionButton: _currentIndex == 0 ? FloatingActionButton.extended(onPressed: _abrirMenuAcciones, backgroundColor: const Color(0xFF0055A5), icon: const Icon(Icons.menu, color: Colors.white), label: const Text("MENÚ", style: TextStyle(color: Colors.white))) : null,
      bottomNavigationBar: NavigationBar(selectedIndex: _currentIndex, onDestinationSelected: (i) => setState(() => _currentIndex = i), destinations: const [NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: "Deuda"), NavigationDestination(icon: Icon(Icons.analytics), label: "Analítica"), NavigationDestination(icon: Icon(Icons.history), label: "Bóveda")]),
    );
  }
}
