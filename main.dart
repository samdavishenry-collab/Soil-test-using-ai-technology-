import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:csv/csv.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Locale _locale = const Locale('en');

  void setLocale(Locale locale) {
    setState(() {
      _locale = locale;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Soil Tester',
      debugShowCheckedModeBanner: false,
      locale: _locale,
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
        Locale('ta'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: SoilApp(onLocaleChange: setLocale),
    );
  }
}

// Simple localized strings (map-based for brevity)
const Map<String, Map<String, String>> L = {
  'en': {
    'title': 'AI Soil Tester',
    'status': 'Status:',
    'select_device': 'Select paired device',
    'read_sensors': 'Read Sensors',
    'suggestion': 'Suggestion:',
    'history': 'History (latest first)',
    'exported': 'Exported CSV to: ',
    'calibration_saved': 'Calibration values updated',
    'refresh_devices': 'Refresh Devices'
  },
  'hi': {
    'title': 'एआई सॉयल टेस्टर',
    'status': 'स्थिति:',
    'select_device': 'पेअर किया गया डिवाइस चुनें',
    'read_sensors': 'सेंसर पढ़ें',
    'suggestion': 'सुझाव:',
    'history': 'इतिहास (नवीनतम पहले)',
    'exported': 'CSV निर्यात किया गया: ',
    'calibration_saved': 'कैलिब्रेशन मान अपडेट किए गए',
    'refresh_devices': 'डिवाइस रिफ्रेश करें'
  },
  'ta': {
    'title': 'ஏஐ மண் சோதகர்',
    'status': 'நிலை:',
    'select_device': 'இணைக்கப்பட்ட சாதனத்தை தேர்வு செய்க',
    'read_sensors': 'சென்சார்கள் படிக்கவும்',
    'suggestion': 'மூலம்:',
    'history': 'வரலாறு (சமீபத்தியது முதலில்)',
    'exported': 'CSV ஏற்றப்பட்டது: ',
    'calibration_saved': 'அளவீட்டு மதிப்புகள் புதுப்பிக்கப்பட்டன',
    'refresh_devices': 'சாதனங்களை புதுப்பிக்கவும்'
  }
};

class SoilApp extends StatefulWidget {
  final Function(Locale) onLocaleChange;
  const SoilApp({Key? key, required this.onLocaleChange}) : super(key: key);

  @override
  _SoilAppState createState() => _SoilAppState();
}

class _SoilAppState extends State<SoilApp> {
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;
  List<BluetoothDevice> _devices = [];
  BluetoothConnection? connection;
  String status = "Not connected";
  Map<String, dynamic> data = {};
  String _buffer = "";
  Database? _db;
  List<Map<String, dynamic>> _history = [];

  double phSlope = -5.7;
  double phIntercept = 21.0;
  double moistDry = 2000.0;
  double moistWet = 800.0;

  Locale get _locale => Localizations.localeOf(context);

  String t(String key) {
    String code = _locale.languageCode;
    return L[code]?[key] ?? L['en']![key] ?? key;
  }

  @override
  void initState() {
    super.initState();
    _initPermissions();
    FlutterBluetoothSerial.instance.state.then((s) {
      setState(() => _bluetoothState = s);
    });
    _loadPairedDevices();
    _initDb();
  }

  Future<void> _initPermissions() async {
    await Permission.bluetooth.request();
    await Permission.locationWhenInUse.request();
  }

  Future<void> _loadPairedDevices() async {
    var d = await FlutterBluetoothSerial.instance.getBondedDevices();
    setState(() => _devices = d);
  }

  Future<void> _initDb() async {
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = p.join(documentsDirectory.path, "ai_soil_tester.db");
    _db = await openDatabase(path, version: 1, onCreate: (db, v) async {
      await db.execute('''
        CREATE TABLE history (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          timestamp TEXT,
          ph REAL,
          moist REAL,
          temp REAL,
          hum REAL
        )
      ''');
    });
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (_db == null) return;
    var rows = await _db!.query('history', orderBy: 'id DESC', limit: 200);
    setState(() => _history = rows);
  }

  Future<void> _saveHistory(Map<String, dynamic> row) async {
    if (_db == null) return;
    await _db!.insert('history', {
      'timestamp': DateTime.now().toIso8601String(),
      'ph': row['pH'],
      'moist': row['moist'],
      'temp': row['temp'],
      'hum': row['hum'],
    });
    _loadHistory();
  }

  Future<void> _exportCsv() async {
    if (_history.isEmpty) return;
    List<List<dynamic>> rows = [
      ['timestamp','pH','moist','temp','hum']
    ];
    for (var r in _history) {
      rows.add([r['timestamp'], r['ph'], r['moist'], r['temp'], r['hum']]);
    }
    String csv = const ListToCsvConverter().convert(rows);
    Directory documentsDirectory = await getApplicationDocumentsDirectory();
    String path = p.join(documentsDirectory.path, "ai_soil_history_${DateTime.now().millisecondsSinceEpoch}.csv");
    File f = File(path);
    await f.writeAsString(csv);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('exported') + path)));
  }

  Future<void> connect(BluetoothDevice device) async {
    setState(() => status = "Connecting to ${device.name}...");
    try {
      connection = await BluetoothConnection.toAddress(device.address);
      setState(() => status = "Connected: ${device.name}");
      connection!.input!.listen((Uint8List bytes) {
        String chunk = String.fromCharCodes(bytes);
        _handleIncoming(chunk);
      }).onDone(() {
        setState(() => status = "Disconnected");
      });
    } catch (e) {
      setState(() => status = "Error: $e");
    }
  }

  void _handleIncoming(String chunk) {
    _buffer += chunk;
    if (_buffer.contains('\n')) {
      List<String> parts = _buffer.split('\n');
      for (int i = 0; i < parts.length - 1; i++) {
        String line = parts[i].trim();
        if (line.isEmpty) continue;
        try {
          var parsed = json.decode(line);
          setState(() {
            data = parsed;
          });
          _saveHistory(parsed);
        } catch (e) {
          // ignore parse errors
        }
      }
      _buffer = parts.last;
    }
  }

  void requestRead() {
    if (connection != null && connection!.isConnected) {
      connection!.output.add(Uint8List.fromList("READ\n".codeUnits));
      connection!.output.allSent;
      setState(() => status = "Request sent...");
    } else {
      setState(() => status = "Not connected");
    }
  }

  String suggestion(Map<String, dynamic> d) {
    if (d.isEmpty) return "No data";
    double pH = (d['pH'] ?? -1.0) + 0.0;
    double moist = (d['moist'] ?? -1.0) + 0.0;
    double temp = (d['temp'] ?? -1.0) + 0.0;
    String out = "";

    if (pH > 0) {
      if (pH < 5.5) out += "Acidic soil — consider liming.\n";
      else if (pH <= 7.5) out += "Neutral pH — good for many cereals.\n";
      else out += "Alkaline soil — consider gypsum or acidifying amendments.\n";
    }
    if (moist >= 0) {
      if (moist < 30) out += "Soil dry — irrigation recommended.\n";
      else if (moist <= 70) out += "Moisture OK for many crops.\n";
      else out += "High moisture — check drainage.\n";
    }
    if (temp > 0) {
      out += "Temp: ${temp.toString()} °C\n";
    }
    return out.isNotEmpty ? out : "No suggestion";
  }

  void _openCalibrationDialog() {
    showDialog(
      context: context,
      builder: (context) {
        TextEditingController phSlopeCtrl = TextEditingController(text: phSlope.toString());
        TextEditingController phInterceptCtrl = TextEditingController(text: phIntercept.toString());
        TextEditingController moistDryCtrl = TextEditingController(text: moistDry.toString());
        TextEditingController moistWetCtrl = TextEditingController(text: moistWet.toString());
        return AlertDialog(
          title: Text('Calibration (Save values)'),
          content: SingleChildScrollView(
            child: Column(
              children: [
                TextField(controller: phSlopeCtrl, decoration: const InputDecoration(labelText: 'pH slope (m)')),
                TextField(controller: phInterceptCtrl, decoration: const InputDecoration(labelText: 'pH intercept (b)')),
                TextField(controller: moistDryCtrl, decoration: const InputDecoration(labelText: 'Moisture ADC dry')),
                TextField(controller: moistWetCtrl, decoration: const InputDecoration(labelText: 'Moisture ADC wet')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () { Navigator.pop(context); }, child: const Text('Cancel')),
            ElevatedButton(onPressed: () {
              setState(() {
                phSlope = double.tryParse(phSlopeCtrl.text) ?? phSlope;
                phIntercept = double.tryParse(phInterceptCtrl.text) ?? phIntercept;
                moistDry = double.tryParse(moistDryCtrl.text) ?? moistDry;
                moistWet = double.tryParse(moistWetCtrl.text) ?? moistWet;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('calibration_saved')));
            }, child: const Text('Save'))
          ],
        );
      }
    );
  }

  Widget _buildHistoryList() {
    if (_history.isEmpty) return Text('No history yet');
    return Expanded(
      child: ListView.builder(
        itemCount: _history.length,
        itemBuilder: (context, idx) {
          var r = _history[idx];
          return ListTile(
            title: Text('${r['timestamp']}'),
            subtitle: Text('pH: ${r['ph']}  Moist: ${r['moist']}%  Temp: ${r['temp']}°C'),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(t('title')),
        backgroundColor: Colors.green[700],
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'en') widget.onLocaleChange(const Locale('en'));
              if (v == 'hi') widget.onLocaleChange(const Locale('hi'));
              if (v == 'ta') widget.onLocaleChange(const Locale('ta'));
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'en', child: Text('English')),
              const PopupMenuItem(value: 'hi', child: Text('हिन्दी')),
              const PopupMenuItem(value: 'ta', child: Text('தமிழ்')),
            ],
          ),
          IconButton(icon: const Icon(Icons.download), onPressed: _exportCsv),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(t('status') + ' ' + status),
            const SizedBox(height: 8),
            DropdownButton<BluetoothDevice>(
              hint: Text(t('select_device')),
              items: _devices.map((d) => DropdownMenuItem(
                child: Text(d.name ?? d.address),
                value: d,
              )).toList(),
              onChanged: (BluetoothDevice? d) {
                if (d != null) connect(d);
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                ElevatedButton(onPressed: requestRead, child: Text(t('read_sensors'))),
                const SizedBox(width: 10),
                ElevatedButton(onPressed: _loadPairedDevices, child: Text(t('refresh_devices')))
              ],
            ),
            const SizedBox(height: 20),
            if (data.isNotEmpty) ...[
              Text("pH: ${data['pH']}", style: const TextStyle(fontSize: 18)),
              Text("Moisture %: ${data['moist']}", style: const TextStyle(fontSize: 18)),
              Text("Temp °C: ${data['temp']}", style: const TextStyle(fontSize: 18)),
              Text("Humidity %: ${data['hum']}", style: const TextStyle(fontSize: 18)),
              const SizedBox(height: 12),
              Text(t('suggestion'), style: const TextStyle(fontWeight: FontWeight.bold)),
              Text(suggestion(data)),
              const SizedBox(height: 12),
            ],
            const Divider(),
            Text(t('history'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildHistoryList(),
          ],
        ),
      ),
    );
  }
}
