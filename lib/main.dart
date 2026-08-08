import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'products.dart' as seed;

const defaultOperatorNames = [
  'Ekrem Ünal', 'Ozan Tüzün', 'Emircan Akyar', 'Mehmet Kavrık',
  'Süleyman Ak', 'Mehmet Güre', 'Tuncay Üstünel', 'Hüseyin Yurttaş',
  'Oğuzhan Sarıkaya', 'Hüseyin Bıyık'
];

const shifts = ['Gündüz', 'Gece'];
const statuses = ['Üretimde', 'Ayar Dönülüyor', 'Arızalı', 'Parça Kırdı', 'Bakımda', 'Diğer'];
const defaultMachineNames = [
  'Makine 1', 'Makine 2', 'Makine 3', 'Makine 4', 'Makine 5', 'Makine 6', 'Makine 7', 'Makine 8',
  'Makine 9', 'Makine 10', 'Makine 11', 'Makine 12', 'Makine 13', 'Makine 14', 'Makine 15', 'Makine 16',
  'Makine 17', 'Makine 18', 'Makine 19', 'Makine 20', 'Makine 21', 'Makine 22',
  '10 mm Spanzet', '12 mm Spanzet'
];

/// Tüm veriler Firestore'dan gerçek zamanlı dinlenir.
/// Uygulamayı açan herkes (siz, patron, pazarlamacı) aynı veriyi görür.
class AppState extends ChangeNotifier {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> records = [];
  List<Map<String, dynamic>> products = [];
  List<Map<String, dynamic>> operators = [];
  List<Map<String, dynamic>> machines = [];
  Map<String, String> productResetDates = {};
  bool loading = true;
  User? currentUser;
  bool _seededProducts = false;
  bool _seededOperators = false;
  bool _seededMachines = false;

  void init() {
    FirebaseAuth.instance.authStateChanges().listen((u) {
      currentUser = u;
      notifyListeners();
    });

    _db.collection('records').orderBy('createdAt', descending: true).snapshots().listen((snap) {
      records = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();
      loading = false;
      notifyListeners();
    }, onError: (_) { loading = false; notifyListeners(); });

    _db.collection('products').orderBy('name').snapshots().listen((snap) async {
      if (snap.docs.isEmpty && !_seededProducts) {
        _seededProducts = true;
        final batch = _db.batch();
        for (final p in seed.products) {
          batch.set(_db.collection('products').doc(), {'name': p['name'], 'gram': p['gram']});
        }
        await batch.commit();
        return;
      }
      products = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();
      notifyListeners();
    });

    _db.collection('operators').orderBy('name').snapshots().listen((snap) async {
      if (snap.docs.isEmpty && !_seededOperators) {
        _seededOperators = true;
        final batch = _db.batch();
        for (final name in defaultOperatorNames) {
          batch.set(_db.collection('operators').doc(), {'name': name});
        }
        await batch.commit();
        return;
      }
      operators = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();
      notifyListeners();
    });

    _db.collection('meta').doc('settings').snapshots().listen((doc) {
      final raw = doc.data()?['productResetDates'];
      productResetDates = raw == null ? {} : Map<String, String>.from(raw as Map);
      notifyListeners();
    });

    _db.collection('machines').orderBy('order').snapshots().listen((snap) async {
      if (snap.docs.isEmpty && !_seededMachines) {
        _seededMachines = true;
        final batch = _db.batch();
        for (var i = 0; i < defaultMachineNames.length; i++) {
          batch.set(_db.collection('machines').doc(), {'name': defaultMachineNames[i], 'order': i});
        }
        await batch.commit();
        return;
      }
      machines = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();
      notifyListeners();
    });
  }

  bool get isAdmin => currentUser != null;

  Future<String?> signIn(String email, String password) async {
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(email: email, password: password);
      return null;
    } on FirebaseAuthException catch (e) {
      return e.message ?? 'Giriş başarısız';
    }
  }

  Future<void> signOut() => FirebaseAuth.instance.signOut();

  // ---- Kayıtlar ----
  Future<void> add(Map<String, dynamic> r) async {
    r['createdAt'] = FieldValue.serverTimestamp();
    await _db.collection('records').add(r);
  }

  Future<void> update(String id, Map<String, dynamic> r) => _db.collection('records').doc(id).update(r);
  Future<void> deleteRecord(String id) => _db.collection('records').doc(id).delete();

  // ---- Ürünler ----
  Future<void> addProduct(String name, double gram) => _db.collection('products').add({'name': name, 'gram': gram});
  Future<void> deleteProduct(String id) => _db.collection('products').doc(id).delete();

  // ---- Operatörler ----
  Future<void> addOperator(String name) => _db.collection('operators').add({'name': name});
  Future<void> deleteOperator(String id) => _db.collection('operators').doc(id).delete();

  // ---- Makinalar ----
  Future<void> addMachine(String name) async {
    final nextOrder = machines.isEmpty ? 0 : machines.map((m) => (m['order'] as num).toInt()).reduce((a, b) => a > b ? a : b) + 1;
    await _db.collection('machines').add({'name': name, 'order': nextOrder});
  }
  Future<void> deleteMachine(String id) => _db.collection('machines').doc(id).delete();

  // ---- Ürün bazlı sayaç sıfırlama ----
  Future<void> resetProductTotal(String productName) =>
      _db.collection('meta').doc('settings').set({'productResetDates.$productName': dateNow()}, SetOptions(merge: true));

  bool _afterReset(String product, String date) {
    final r = productResetDates[product];
    return r == null || date.compareTo(r) >= 0;
  }

  double totalKgForProduct(String name) => records
      .where((r) => r['product'] == name && r['status'] == 'Üretimde' && _afterReset(name, r['date'] as String))
      .fold(0.0, (s, r) => s + (r['kg'] as num).toDouble());

  DateTime? firstDateForProduct(String name) {
    final ds = records
        .where((r) => r['product'] == name && r['status'] == 'Üretimde' && _afterReset(name, r['date'] as String))
        .map((r) => DateTime.tryParse(r['date'] as String))
        .whereType<DateTime>()
        .toList();
    if (ds.isEmpty) return null;
    ds.sort();
    return ds.first;
  }

  double totalTodayKg(String date) => records
      .where((r) => r['date'] == date && r['status'] == 'Üretimde')
      .fold(0.0, (s, r) => s + (r['kg'] as num).toDouble());

  List<Map<String, dynamic>> recordsForDate(String date) =>
      records.where((r) => r['date'] == date).toList();
}

final appState = AppState();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  appState.init();
  runApp(const BasZincirApp());
}

class BasZincirApp extends StatelessWidget {
  const BasZincirApp({super.key});
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appState,
      builder: (_, __) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Baş Zincir',
        locale: const Locale('tr', 'TR'),
        supportedLocales: const [Locale('tr', 'TR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff243a9b)),
          scaffoldBackgroundColor: const Color(0xfff6f7fb),
        ),
        home: appState.loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : const HomePage(),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final isAdmin = appState.isAdmin;
    final pages = [
      const DashboardPage(),
      if (isAdmin) const EntryPage(),
      const CalendarPage(),
      const ReportsPage(),
      isAdmin ? const ManagementPage() : const LoginPage(),
    ];
    final destinations = [
      const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Özet'),
      if (isAdmin) const NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'Giriş'),
      const NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Takvim'),
      const NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: 'Raporlar'),
      NavigationDestination(
        icon: Icon(isAdmin ? Icons.settings_outlined : Icons.login),
        selectedIcon: Icon(isAdmin ? Icons.settings : Icons.login),
        label: isAdmin ? 'Yönetim' : 'Yönetici Girişi',
      ),
    ];
    if (index >= pages.length) index = 0;
    return Scaffold(
      body: pages[index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: destinations,
      ),
    );
  }
}

String fmtKg(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
String fmtTon(double v) => (v / 1000).toStringAsFixed(3).replaceAll('.', ',');
String dateNow() => DateTime.now().toIso8601String().substring(0, 10);
String dateStr(DateTime d) => d.toIso8601String().substring(0, 10);
String fmtDate(String iso) {
  final p = iso.split('-');
  if (p.length != 3) return iso;
  return '${p[2]}.${p[1]}.${p[0]}';
}

int _machineIndex(String m) {
  final i = appState.machines.indexWhere((x) => x['name'] == m);
  return i == -1 ? appState.machines.length : i;
}
int _shiftOrder(String s) => s == 'Gündüz' ? 0 : (s == 'Gece' ? 1 : 2);

String displayMachine(String m) {
  final match = RegExp(r'^Makine (\d+)$').firstMatch(m);
  if (match != null) return '${match.group(1)}. Makine';
  return m;
}

List<Map<String, dynamic>> sortedRecords(List<Map<String, dynamic>> list) {
  final copy = [...list];
  copy.sort((a, b) {
    final mi = _machineIndex(a['machine'] as String).compareTo(_machineIndex(b['machine'] as String));
    if (mi != 0) return mi;
    return _shiftOrder(a['shift'] as String).compareTo(_shiftOrder(b['shift'] as String));
  });
  return copy;
}

class Logo extends StatelessWidget {
  final double height;
  const Logo({super.key, this.height = 55});
  @override
  Widget build(BuildContext context) => Image.asset('assets/bas_zincir_icon.png', height: height);
}

// =================== GİRİŞ (LOGIN) ===================

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final email = TextEditingController();
  final pass = TextEditingController();
  String? error;
  bool busy = false;

  Future<void> doLogin() async {
    setState(() { busy = true; error = null; });
    final err = await appState.signIn(email.text.trim(), pass.text);
    setState(() { busy = false; error = err; });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(padding: const EdgeInsets.all(18), children: [
        const SizedBox(height: 20),
        const Center(child: Logo(height: 70)),
        const SizedBox(height: 24),
        Text('Yönetici Girişi', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text('Sadece üretim verisi giren kişi giriş yapar. Patron ve pazarlamacılar giriş yapmadan raporları görebilir.',
            style: TextStyle(color: Colors.grey.shade700)),
        const SizedBox(height: 20),
        TextField(controller: email, keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-posta', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: pass, obscureText: true,
            decoration: const InputDecoration(labelText: 'Şifre', border: OutlineInputBorder())),
        if (error != null) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text(error!, style: const TextStyle(color: Colors.red)),
        ),
        const SizedBox(height: 16),
        FilledButton(onPressed: busy ? null : doLogin, child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(busy ? 'Giriş yapılıyor...' : 'GİRİŞ YAP'),
        )),
      ]),
    );
  }
}

// =================== ÖZET (DASHBOARD) ===================

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    final today = dateNow();
    final todayRecords = sortedRecords(appState.recordsForDate(today));
    final active = todayRecords.where((r) => r['status'] == 'Üretimde').length;
    final setup = todayRecords.where((r) => r['status'] == 'Ayar Dönülüyor').length;
    final broken = todayRecords.where((r) => ['Arızalı', 'Parça Kırdı'].contains(r['status'])).length;
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Center(child: Logo(height: 70)),
      const SizedBox(height: 10),
      Text('Günlük Üretim Özeti', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      Text(fmtDate(today), style: Theme.of(context).textTheme.bodyMedium),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('TOPLAM ÜRETİM (Bugün)', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        Text('${fmtTon(appState.totalTodayKg(today))} ton', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
        Text('${fmtKg(appState.totalTodayKg(today))} kg', style: TextStyle(color: Colors.grey.shade700)),
      ]))),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: _stat('Üretimde', active, Colors.green)),
        const SizedBox(width: 8), Expanded(child: _stat('Ayar', setup, Colors.orange)),
        const SizedBox(width: 8), Expanded(child: _stat('Arıza', broken, Colors.red)),
      ]),
      const SizedBox(height: 18),
      Text('Bugünkü Kayıtlar', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (todayRecords.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Bugün henüz kayıt bulunmuyor.'))),
      if (appState.isAdmin && todayRecords.isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('Düzeltmek için bir kayda dokunun', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
      ...todayRecords.map((r) => Card(child: ListTile(
        onTap: appState.isAdmin ? () => showModalBottomSheet(
          context: context, isScrollControlled: true,
          builder: (_) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: EditRecordSheet(record: r),
          ),
        ) : null,
        leading: CircleAvatar(child: Text(r['machine'].toString().replaceAll('Makine ', '').replaceAll('Spanzet ', ''))),
        title: Text(displayMachine(r['machine'])),
        subtitle: Text('${r['product'] ?? ''} • ${r['shift']} • ${r['operator']}'
            '${(r['note'] as String?)?.isNotEmpty == true ? '\nNot: ${r['note']}' : ''}'),
        trailing: Text(r['status'] == 'Üretimde' ? '${fmtKg((r['kg'] as num).toDouble())} kg' : r['status'], textAlign: TextAlign.end),
      ))),
    ]));
  }
  Widget _stat(String t, int n, Color c) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Column(children: [
    Text('$n', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c)), Text(t, style: const TextStyle(fontSize: 12))
  ])));
}

// =================== ÜRETİM GİRİŞİ ===================

class EntryPage extends StatefulWidget {
  const EntryPage({super.key});
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  String machine = 'Makine 1', operator = '', shift = 'Gündüz', status = 'Üretimde';
  String? productId;
  DateTime selectedDate = DateTime.now();
  final qty = TextEditingController();
  final note = TextEditingController();
  bool saving = false;

  Future<void> pickDate() async {
    final d = await showDatePicker(
      context: context, initialDate: selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 60)),
      lastDate: DateTime.now(),
    );
    if (d != null) setState(() => selectedDate = d);
  }

  List<Map<String, dynamic>> get availableProducts {
    final all = appState.products;
    if (machine == '10 mm Spanzet') return all.where((p) => p['name'] == '10 mm Spanzet').toList();
    if (machine == '12 mm Spanzet') return all.where((p) => p['name'] == '12 mm Spanzet').toList();
    return all.where((p) => p['name'] != '10 mm Spanzet' && p['name'] != '12 mm Spanzet').toList();
  }

  Future<void> save() async {
    final list = availableProducts;
    if (list.isEmpty) return;
    final p = list.firstWhere((p) => p['id'] == productId, orElse: () => list.first);
    final gram = (p['gram'] as num).toDouble();
    final q = int.tryParse(qty.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
    if (status == 'Üretimde' && q <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Üretim adedini girin.')));
      return;
    }
    if (operator.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Operatör seçin.')));
      return;
    }
    final kg = status == 'Üretimde' ? q * gram / 1000 : 0;
    setState(() => saving = true);
    try {
      await appState.add({
        'date': dateStr(selectedDate), 'machine': machine, 'product': p['name'], 'gram': gram,
        'operator': operator, 'shift': shift, 'status': status, 'qty': q, 'kg': kg, 'note': note.text.trim()
      });
      qty.clear(); note.clear();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Üretim kaydı kaydedildi.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = availableProducts;
    if (list.isNotEmpty && !list.any((p) => p['id'] == productId)) productId = list.first['id'];
    if (operator.isEmpty && appState.operators.isNotEmpty) operator = appState.operators.first['name'];
    final gram = list.isEmpty ? 0.0 : (list.firstWhere((p) => p['id'] == productId, orElse: () => list.first)['gram'] as num).toDouble();
    final qn = int.tryParse(qty.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;

    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Logo(height: 52), const SizedBox(height: 10),
      Text('Üretim Girişi', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      Card(child: ListTile(
        leading: const Icon(Icons.event),
        title: const Text('Üretim Tarihi'),
        subtitle: Text('${selectedDate.day.toString().padLeft(2, '0')}.${selectedDate.month.toString().padLeft(2, '0')}.${selectedDate.year}'),
        trailing: TextButton(onPressed: pickDate, child: const Text('Değiştir')),
      )),
      const SizedBox(height: 10),
      _dd('Makine / Bölüm', machine, appState.machines.map((m) => m['name'] as String).toList(), (v) => setState(() => machine = v!), labelOf: displayMachine),
      if (list.isEmpty)
        const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('Bu makina için ürün tanımlı değil. Önce Yönetim > Ürün Yönetimi\'nden ekleyin.', style: TextStyle(color: Colors.red)))
      else
        _dd('Ürün', productId!, list.map((p) => p['id'] as String).toList(), (v) => setState(() => productId = v),
            labelOf: (id) => list.firstWhere((p) => p['id'] == id)['name'] as String),
      if (list.isNotEmpty) Card(child: ListTile(title: const Text('Gramaj'), subtitle: Text('${gram.toStringAsFixed(2)} g / bakla'), leading: const Icon(Icons.scale_outlined))),
      _dd('Vardiya', shift, shifts, (v) => setState(() => shift = v!)),
      if (appState.operators.isEmpty)
        const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('Operatör tanımlı değil. Önce Yönetim > Operatör Yönetimi\'nden ekleyin.', style: TextStyle(color: Colors.red)))
      else
        _dd('Operatör', operator, appState.operators.map((o) => o['name'] as String).toList(), (v) => setState(() => operator = v!)),
      _dd('Durum', status, statuses, (v) => setState(() => status = v!)),
      if (status == 'Üretimde') ...[
        TextField(controller: qty, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Üretilen bakla adedi', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        if (qn > 0) Card(child: ListTile(title: const Text('Otomatik hesap'), subtitle: Text('${fmtKg(qn * gram / 1000)} kg  •  ${fmtTon(qn * gram / 1000)} ton'))),
      ],
      TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', border: OutlineInputBorder())),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: saving || list.isEmpty || appState.operators.isEmpty ? null : save,
        icon: const Icon(Icons.save),
        label: Padding(padding: const EdgeInsets.all(12), child: Text(saving ? 'KAYDEDİLİYOR...' : 'KAYDET')),
      ),
    ]));
  }

  Widget _dd(String label, String value, List<String> items, ValueChanged<String?> onChanged, {String Function(String)? labelOf}) {
    final safeItems = items.contains(value) ? items : [value, ...items];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10), child: DropdownButtonFormField<String>(
        value: value, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: safeItems.map((e) => DropdownMenuItem(value: e, child: Text(labelOf?.call(e) ?? e, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: onChanged));
  }
}

// =================== KAYITLAR (DÜZENLE / SİL) ===================

class RecordsPage extends StatefulWidget {
  const RecordsPage({super.key});
  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  String date = dateNow();

  Future<void> pickDate() async {
    final d = await showDatePicker(context: context, initialDate: DateTime.parse(date), firstDate: DateTime(2020), lastDate: DateTime(2100));
    if (d != null) setState(() => date = dateStr(d));
  }

  Future<void> confirmDelete(String id) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Kaydı sil'),
      content: const Text('Bu kayıt kalıcı olarak silinecek. Emin misiniz?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
      ],
    ));
    if (ok == true) await appState.deleteRecord(id);
  }

  void openEdit(Map<String, dynamic> r) {
    showModalBottomSheet(
      context: context, isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: EditRecordSheet(record: r),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = sortedRecords(appState.recordsForDate(date));
    return Scaffold(
      appBar: AppBar(title: const Text('Kayıtları Düzenle')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Card(child: ListTile(
          leading: const Icon(Icons.event),
          title: Text(fmtDate(date)),
          trailing: TextButton(onPressed: pickDate, child: const Text('Tarih Değiştir')),
        )),
        const SizedBox(height: 12),
        if (list.isEmpty) const Padding(padding: EdgeInsets.all(18), child: Text('Bu tarihte kayıt bulunmuyor.')),
        ...list.map((r) => Card(child: ListTile(
          title: Text('${displayMachine(r['machine'])} • ${r['product'] ?? r['status']}'),
          subtitle: Text('${r['status']}${r['status'] == 'Üretimde' ? ' • ${r['qty']} bakla • ${fmtKg((r['kg'] as num).toDouble())} kg' : ''}\n${r['operator']} • ${r['shift']}'),
          isThreeLine: true,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => openEdit(r)),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => confirmDelete(r['id'])),
          ]),
        ))),
      ])),
    );
  }
}

class EditRecordSheet extends StatefulWidget {
  final Map<String, dynamic> record;
  const EditRecordSheet({super.key, required this.record});
  @override
  State<EditRecordSheet> createState() => _EditRecordSheetState();
}

class _EditRecordSheetState extends State<EditRecordSheet> {
  late String machine = widget.record['machine'];
  late String status = widget.record['status'];
  late String operator = widget.record['operator'];
  late String shift = widget.record['shift'];
  late String? productId;
  late TextEditingController qty;
  late TextEditingController note;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    qty = TextEditingController(text: widget.record['qty']?.toString() ?? '');
    note = TextEditingController(text: widget.record['note'] ?? '');
    final match = appState.products.where((p) => p['name'] == widget.record['product']).toList();
    productId = match.isNotEmpty ? match.first['id'] as String : null;
  }

  List<Map<String, dynamic>> get availableProducts {
    final all = appState.products;
    if (machine == '10 mm Spanzet') return all.where((p) => p['name'] == '10 mm Spanzet').toList();
    if (machine == '12 mm Spanzet') return all.where((p) => p['name'] == '12 mm Spanzet').toList();
    return all.where((p) => p['name'] != '10 mm Spanzet' && p['name'] != '12 mm Spanzet').toList();
  }

  Future<void> save() async {
    final list = availableProducts;
    Map<String, dynamic>? p;
    if (list.isNotEmpty) p = list.firstWhere((p) => p['id'] == productId, orElse: () => list.first);
    final q = int.tryParse(qty.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
    final gram = p == null ? 0.0 : (p['gram'] as num).toDouble();
    final kg = status == 'Üretimde' ? q * gram / 1000 : 0;
    setState(() => saving = true);
    try {
      await appState.update(widget.record['id'], {
        'machine': machine, 'product': p?['name'], 'gram': gram,
        'operator': operator, 'shift': shift, 'status': status, 'qty': q, 'kg': kg, 'note': note.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Güncellenemedi: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = availableProducts;
    if (list.isNotEmpty && !list.any((p) => p['id'] == productId)) productId = list.first['id'];
    return Padding(
      padding: const EdgeInsets.all(18),
      child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Kaydı Düzenle', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        _dd('Makine', machine, appState.machines.map((m) => m['name'] as String).toList(), (v) => setState(() => machine = v!), labelOf: displayMachine),
        if (list.isNotEmpty)
          _dd('Ürün', productId!, list.map((p) => p['id'] as String).toList(), (v) => setState(() => productId = v),
              labelOf: (id) => list.firstWhere((p) => p['id'] == id)['name'] as String),
        _dd('Vardiya', shift, shifts, (v) => setState(() => shift = v!)),
        if (appState.operators.isNotEmpty)
          _dd('Operatör', operator, appState.operators.map((o) => o['name'] as String).toList(), (v) => setState(() => operator = v!)),
        _dd('Durum', status, statuses, (v) => setState(() => status = v!)),
        if (status == 'Üretimde')
          TextField(controller: qty, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Bakla adedi', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        TextField(controller: note, decoration: const InputDecoration(labelText: 'Not', border: OutlineInputBorder())),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç'))),
          const SizedBox(width: 10),
          Expanded(child: FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Kaydediliyor...' : 'Kaydet'))),
        ]),
        const SizedBox(height: 12),
      ])),
    );
  }

  Widget _dd(String label, String value, List<String> items, ValueChanged<String?> onChanged, {String Function(String)? labelOf}) {
    final safeItems = items.contains(value) ? items : [value, ...items];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10), child: DropdownButtonFormField<String>(
        value: value, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: safeItems.map((e) => DropdownMenuItem(value: e, child: Text(labelOf?.call(e) ?? e, overflow: TextOverflow.ellipsis))).toList(),
        onChanged: onChanged));
  }
}

// =================== TAKVİM ===================

class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime selected = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final date = dateStr(selected);
    final list = sortedRecords(appState.recordsForDate(date));
    final totalKg = list.where((r) => r['status'] == 'Üretimde').fold(0.0, (s, r) => s + (r['kg'] as num).toDouble());
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Logo(height: 52), const SizedBox(height: 8),
      Text('Takvim', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Card(child: CalendarDatePicker(
        initialDate: selected, firstDate: DateTime(2020), lastDate: DateTime(2100),
        onDateChanged: (d) => setState(() => selected = d),
      )),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${fmtDate(date)} Toplam Üretim', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('${fmtKg(totalKg)} kg  •  ${fmtTon(totalKg)} ton', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ]))),
      const SizedBox(height: 12),
      if (list.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Bu tarihte kayıt bulunmuyor.')),
      ...list.map((r) => Card(child: ListTile(
        title: Text(displayMachine(r['machine'])),
        subtitle: Text('${r['product'] ?? r['status']} • ${r['shift']} • ${r['operator']}'
            '${(r['note'] as String?)?.isNotEmpty == true ? '\nNot: ${r['note']}' : ''}'),
        trailing: Text(r['status'] == 'Üretimde' ? '${fmtKg((r['kg'] as num).toDouble())} kg' : r['status']),
      ))),
    ]));
  }
}

// =================== RAPORLAR (KÜMÜLATİF) ===================

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String query = '';

  Future<void> confirmReset(String name) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Ürünü Sıfırla'),
      content: Text('"$name" için kümülatif toplam bugünden itibaren sıfırdan sayılmaya başlayacak. Geçmiş kayıtlar silinmez, sadece bu ürünün toplamı bu tarihten itibaren hesaplanır. Emin misiniz?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sıfırla')),
      ],
    ));
    if (ok == true) {
      await appState.resetProductTotal(name);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$name" sıfırlandı.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = appState.products.map((p) => p['name'] as String).where((n) => n.toLowerCase().contains(query.toLowerCase())).toList();
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Logo(height: 52), const SizedBox(height: 8),
      Text('Ürün Üretim Raporu', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Ürün ara', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      ...names.map((name) {
        final kg = appState.totalKgForProduct(name);
        final d = appState.firstDateForProduct(name);
        final gram = (appState.products.firstWhere((p) => p['name'] == name)['gram'] as num).toDouble();
        final qty = gram == 0 ? 0 : kg * 1000 / gram;
        final resetD = appState.productResetDates[name];
        return Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ListTile(
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('İlk üretim: ${d == null ? "—" : fmtDate(dateStr(d))}\nToplam bakla: ${qty.toStringAsFixed(0)}'
              '${resetD != null ? '\n${fmtDate(resetD)} tarihinden itibaren' : ''}'),
          isThreeLine: true,
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${fmtKg(kg)} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${fmtTon(kg)} ton'),
            const SizedBox(height: 4),
            if (appState.isAdmin)
              InkWell(onTap: () => confirmReset(name), child: const Text('Sıfırla', style: TextStyle(fontSize: 12, color: Colors.red))),
          ]),
        )));
      })
    ]));
  }
}

// =================== YÖNETİM ===================

class ManagementPage extends StatelessWidget {
  const ManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Center(child: Logo(height: 60)), const SizedBox(height: 16),
      Text('Yönetim', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Card(child: ListTile(
        leading: const Icon(Icons.person),
        title: const Text('Oturum açık'),
        subtitle: Text(appState.currentUser?.email ?? ''),
      )),
      const SizedBox(height: 8),
      Card(child: ListTile(
        leading: const Icon(Icons.edit_note),
        title: const Text('Kayıtları Düzenle / Sil'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RecordsPage())),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.precision_manufacturing_outlined),
        title: const Text('Makina Yönetimi'),
        subtitle: Text('${appState.machines.length} makina'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MachinesManagePage())),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: const Text('Ürün Yönetimi'),
        subtitle: Text('${appState.products.length} ürün'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsManagePage())),
      )),
      Card(child: ListTile(
        leading: const Icon(Icons.people_outline),
        title: const Text('Operatör Yönetimi'),
        subtitle: Text('${appState.operators.length} operatör'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const OperatorsManagePage())),
      )),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: () => appState.signOut(), icon: const Icon(Icons.logout), label: const Text('Çıkış Yap')),
    ]));
  }
}

class MachinesManagePage extends StatefulWidget {
  const MachinesManagePage({super.key});
  @override
  State<MachinesManagePage> createState() => _MachinesManagePageState();
}

class _MachinesManagePageState extends State<MachinesManagePage> {
  final name = TextEditingController();

  Future<void> add() async {
    if (name.text.trim().isEmpty) return;
    await appState.addMachine(name.text.trim());
    name.clear();
  }

  Future<void> confirmDelete(String id, String label) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Makinayı sil'),
      content: Text('"$label" silinsin mi? Geçmiş üretim kayıtları etkilenmez.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
      ],
    ));
    if (ok == true) await appState.deleteMachine(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Makina Yönetimi')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Makina adı (örn. Makine 23)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: add, child: const Text('Makina Ekle'))),
        ]))),
        const SizedBox(height: 8),
        Text('Yeni makina en sona eklenir. "Makine N" formatında yazarsanız uygulama otomatik olarak "N. Makine" şeklinde gösterir.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 12),
        ...appState.machines.map((m) => Card(child: ListTile(
          title: Text(displayMachine(m['name'])),
          trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => confirmDelete(m['id'], m['name'])),
        ))),
      ])),
    );
  }
}

class ProductsManagePage extends StatefulWidget {
  const ProductsManagePage({super.key});
  @override
  State<ProductsManagePage> createState() => _ProductsManagePageState();
}

class _ProductsManagePageState extends State<ProductsManagePage> {
  final name = TextEditingController();
  final gram = TextEditingController();

  Future<void> add() async {
    final g = double.tryParse(gram.text.replaceAll(',', '.'));
    if (name.text.trim().isEmpty || g == null || g <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ürün adı ve geçerli bir gramaj girin.')));
      return;
    }
    await appState.addProduct(name.text.trim(), g);
    name.clear(); gram.clear();
  }

  Future<void> confirmDelete(String id, String label) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Ürünü sil'),
      content: Text('"$label" silinsin mi? Geçmiş üretim kayıtları etkilenmez.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
      ],
    ));
    if (ok == true) await appState.deleteProduct(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ürün Yönetimi')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Ürün adı (örn. 7x22 mm zincir)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: gram, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Gramaj (gram/bakla)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: add, child: const Text('Ürün Ekle'))),
        ]))),
        const SizedBox(height: 12),
        ...appState.products.map((p) => Card(child: ListTile(
          title: Text(p['name']),
          subtitle: Text('${p['gram']} g/bakla'),
          trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => confirmDelete(p['id'], p['name'])),
        ))),
      ])),
    );
  }
}

class OperatorsManagePage extends StatefulWidget {
  const OperatorsManagePage({super.key});
  @override
  State<OperatorsManagePage> createState() => _OperatorsManagePageState();
}

class _OperatorsManagePageState extends State<OperatorsManagePage> {
  final name = TextEditingController();

  Future<void> add() async {
    if (name.text.trim().isEmpty) return;
    await appState.addOperator(name.text.trim());
    name.clear();
  }

  Future<void> confirmDelete(String id, String label) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Operatörü sil'),
      content: Text('"$label" silinsin mi?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
      ],
    ));
    if (ok == true) await appState.deleteOperator(id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Operatör Yönetimi')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          Expanded(child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Operatör adı', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          FilledButton(onPressed: add, child: const Text('Ekle')),
        ]))),
        const SizedBox(height: 12),
        ...appState.operators.map((o) => Card(child: ListTile(
          title: Text(o['name']),
          trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => confirmDelete(o['id'], o['name'])),
        ))),
      ])),
    );
  }
}
