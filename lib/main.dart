import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'products.dart' as seed;
import 'stock_seed.dart';

const defaultOperatorNames = [
  'Ekrem Ünal', 'Ozan Tüzün', 'Emircan Akyar', 'Mehmet Kavrık',
  'Süleyman Ak', 'Mehmet Güre', 'Tuncay Üstünel', 'Hüseyin Yurttaş',
  'Oğuzhan Sarıkaya', 'Hüseyin Bıyık'
];

const shifts = ['Gündüz', 'Gece'];
const turkishMonths = ['Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'];
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
  List<Map<String, dynamic>> stock = [];
  List<Map<String, dynamic>> wiredraw = [];
  Map<String, String> productResetDates = {};
  bool loading = true;
  User? currentUser;
  bool _seededProducts = false;
  bool _seededOperators = false;
  bool _seededMachines = false;
  bool _seededStock = false;

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

    _db.collection('products').snapshots().listen((snap) async {
      if (snap.docs.isEmpty && !_seededProducts) {
        _seededProducts = true;
        final batch = _db.batch();
        for (var i = 0; i < seed.products.length; i++) {
          final p = seed.products[i];
          batch.set(_db.collection('products').doc(), {'name': p['name'], 'gram': p['gram'], 'order': i});
        }
        await batch.commit();
        return;
      }
      final list = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();
      list.sort((a, b) {
        final oa = (a['order'] as num?)?.toInt();
        final ob = (b['order'] as num?)?.toInt();
        if (oa != null && ob != null) return oa.compareTo(ob);
        if (oa != null) return -1;
        if (ob != null) return 1;
        return (a['name'] as String).compareTo(b['name'] as String);
      });
      products = list;
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

    _db.collection('stock').snapshots().listen((snap) async {
      if (snap.docs.isEmpty && !_seededStock) {
        _seededStock = true;
        final batch = _db.batch();
        for (var i = 0; i < stockSeed.length; i++) {
          final s = stockSeed[i];
          batch.set(_db.collection('stock').doc(), {'cap': s['cap'], 'malzeme': s['malzeme'], 'kg': s['kg'], 'order': i});
        }
        await batch.commit();
        return;
      }
      final list = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();
      list.sort((a, b) {
        final oa = (a['order'] as num?)?.toInt();
        final ob = (b['order'] as num?)?.toInt();
        if (oa != null && ob != null) return oa.compareTo(ob);
        if (oa != null) return -1;
        if (ob != null) return 1;
        final c = (a['cap'] as num).compareTo(b['cap'] as num);
        if (c != 0) return c;
        return (a['malzeme'] as String).compareTo(b['malzeme'] as String);
      });
      stock = list;
      notifyListeners();
    });

    _db.collection('wiredraw').orderBy('createdAt', descending: true).snapshots().listen((snap) {
      wiredraw = snap.docs.map((d) {
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
  Future<void> addProduct(String name, double gram) async {
    final nextOrder = products.isEmpty ? 0 : products.map((p) => (p['order'] as num?)?.toInt() ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    await _db.collection('products').add({'name': name, 'gram': gram, 'order': nextOrder});
  }
  Future<void> deleteProduct(String id) => _db.collection('products').doc(id).delete();

  Future<void> reorderProducts(List<String> orderedIds) async {
    final map = {for (final p in products) p['id'] as String: p};
    products = orderedIds.where((id) => map.containsKey(id)).map((id) => map[id]!).toList();
    notifyListeners();
    final batch = _db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(_db.collection('products').doc(orderedIds[i]), {'order': i});
    }
    await batch.commit();
  }

  bool isProductActiveToday(String name) {
    final today = dateNow();
    return records.any((r) => r['date'] == today && r['status'] == 'Üretimde' && r['product'] == name);
  }

  // ---- Operatörler ----
  Future<void> addOperator(String name) => _db.collection('operators').add({'name': name});
  Future<void> deleteOperator(String id) => _db.collection('operators').doc(id).delete();

  // ---- Makinalar ----
  Future<void> addMachine(String name) async {
    final nextOrder = machines.isEmpty ? 0 : machines.map((m) => (m['order'] as num).toInt()).reduce((a, b) => a > b ? a : b) + 1;
    await _db.collection('machines').add({'name': name, 'order': nextOrder});
  }
  Future<void> deleteMachine(String id) => _db.collection('machines').doc(id).delete();

  // ---- Hammadde Stoku ----
  Future<void> addStock(double cap, String malzeme, double kg) async {
    final nextOrder = stock.isEmpty ? 0 : stock.map((s) => (s['order'] as num?)?.toInt() ?? 0).reduce((a, b) => a > b ? a : b) + 1;
    await _db.collection('stock').add({'cap': cap, 'malzeme': malzeme, 'kg': kg, 'order': nextOrder});
  }
  Future<void> updateStockKg(String id, double kg) => _db.collection('stock').doc(id).update({'kg': kg});
  Future<void> deleteStock(String id) => _db.collection('stock').doc(id).delete();

  Future<void> reorderStock(List<String> orderedIds) async {
    final map = {for (final s in stock) s['id'] as String: s};
    stock = orderedIds.where((id) => map.containsKey(id)).map((id) => map[id]!).toList();
    notifyListeners();
    final batch = _db.batch();
    for (var i = 0; i < orderedIds.length; i++) {
      batch.update(_db.collection('stock').doc(orderedIds[i]), {'order': i});
    }
    await batch.commit();
  }

  double get totalStockKg => stock.fold(0.0, (s, r) => s + (r['kg'] as num).toDouble());

  // ---- Tel Çekme (hammaddeyi üretime hazırlama) ----
  Future<String?> addWiredraw({
    required String date, required String operator, required String shift,
    required String stockId, required double kg, String note = '',
  }) async {
    final idx = stock.indexWhere((s) => s['id'] == stockId);
    if (idx == -1) return 'Seçilen hammadde stokta bulunamadı.';
    final s = stock[idx];
    await _db.collection('wiredraw').add({
      'date': date, 'operator': operator, 'shift': shift, 'stockId': stockId,
      'cap': s['cap'], 'malzeme': s['malzeme'], 'kg': kg, 'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
    await updateStockKg(stockId, (s['kg'] as num).toDouble() - kg);
    return null;
  }

  Future<void> deleteWiredraw(String id) async {
    final rec = wiredraw.firstWhere((w) => w['id'] == id, orElse: () => {});
    final stockId = rec['stockId'] as String?;
    if (stockId != null) {
      final idx = stock.indexWhere((s) => s['id'] == stockId);
      if (idx != -1) {
        final cur = (stock[idx]['kg'] as num).toDouble();
        await updateStockKg(stockId, cur + (rec['kg'] as num).toDouble());
      }
    }
    await _db.collection('wiredraw').doc(id).delete();
  }

  List<Map<String, dynamic>> wiredrawForDate(String date) => wiredraw.where((w) => w['date'] == date).toList();

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
  bool _wasAdmin = false;
  @override
  Widget build(BuildContext context) {
    final isAdmin = appState.isAdmin;
    if (isAdmin && !_wasAdmin) index = 0;
    _wasAdmin = isAdmin;
    final pages = [
      const DashboardPage(),
      if (isAdmin) const EntryPage(),
      const CalendarPage(),
      const StockPage(),
      const ReportsPage(),
      isAdmin ? const ManagementPage() : const LoginPage(),
    ];
    final destinations = [
      const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Özet'),
      if (isAdmin) const NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'Giriş'),
      const NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Takvim'),
      const NavigationDestination(icon: Icon(Icons.inventory_outlined), selectedIcon: Icon(Icons.inventory), label: 'Stok'),
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

String fmtCap(num c) {
  final isWhole = c % 1 == 0;
  return isWhole ? '${c.toInt()} mm' : '${c.toString().replaceAll('.', ',')} mm';
}

Future<void> confirmDeleteWiredraw(BuildContext context, Map<String, dynamic> w) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
    title: const Text('Tel Çekme Kaydını Sil'),
    content: Text('${fmtCap(w['cap'] as num)} • ${w['malzeme']} • ${(w['kg'] as num).toStringAsFixed(0)} kg silinsin mi? Bu miktar hammadde stokuna geri eklenecek.'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
    ],
  ));
  if (ok == true) await appState.deleteWiredraw(w['id']);
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
      const SizedBox(height: 18),
      Text('Tel Çekme', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (appState.wiredrawForDate(today).isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Bugün henüz tel çekme kaydı yok.'))),
      ...appState.wiredrawForDate(today).map((w) => Card(child: ListTile(
        onTap: appState.isAdmin ? () => confirmDeleteWiredraw(context, w) : null,
        title: Text('${fmtCap(w['cap'] as num)} • ${w['malzeme']}'),
        subtitle: Text('${w['shift']} • ${w['operator']}'),
        trailing: Text('${fmtKg((w['kg'] as num).toDouble())} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
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
  String entryMode = 'uretim';
  String machine = 'Makine 1', operator = '', shift = 'Gündüz', status = 'Üretimde';
  String? productId;
  String? stockId;
  DateTime selectedDate = DateTime.now();
  final qty = TextEditingController();
  final note = TextEditingController();
  final wireKg = TextEditingController();
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
    if (operator.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Operatör seçin.')));
      return;
    }
    if (entryMode == 'uretim') {
      final list = availableProducts;
      if (list.isEmpty) return;
      final p = list.firstWhere((p) => p['id'] == productId, orElse: () => list.first);
      final gram = (p['gram'] as num).toDouble();
      final q = int.tryParse(qty.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
      if (status == 'Üretimde' && q <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Üretim adedini girin.')));
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
    } else {
      if (appState.stock.isEmpty || stockId == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Önce Stok bölümünden hammadde ekleyin.')));
        return;
      }
      final k = double.tryParse(wireKg.text.replaceAll(',', '.'));
      if (k == null || k <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hazırlanan miktarı (kg) girin.')));
        return;
      }
      setState(() => saving = true);
      final err = await appState.addWiredraw(
        date: dateStr(selectedDate), operator: operator, shift: shift,
        stockId: stockId!, kg: k, note: note.text.trim(),
      );
      if (mounted) {
        if (err != null) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
        } else {
          wireKg.clear(); note.clear();
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tel çekme kaydedildi, stok güncellendi.')));
        }
      }
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = availableProducts;
    if (list.isNotEmpty && !list.any((p) => p['id'] == productId)) productId = list.first['id'];
    if (operator.isEmpty && appState.operators.isNotEmpty) operator = appState.operators.first['name'];
    if (appState.stock.isNotEmpty && !appState.stock.any((s) => s['id'] == stockId)) stockId = appState.stock.first['id'];
    final gram = list.isEmpty ? 0.0 : (list.firstWhere((p) => p['id'] == productId, orElse: () => list.first)['gram'] as num).toDouble();
    final qn = int.tryParse(qty.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;

    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Logo(height: 52), const SizedBox(height: 10),
      Text('Üretim Girişi', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: ChoiceChip(
          label: const Text('Zincir Üretimi'), selected: entryMode == 'uretim',
          onSelected: (_) => setState(() => entryMode = 'uretim'),
        )),
        const SizedBox(width: 8),
        Expanded(child: ChoiceChip(
          label: const Text('Tel Çekme'), selected: entryMode == 'telcekme',
          onSelected: (_) => setState(() => entryMode = 'telcekme'),
        )),
      ]),
      const SizedBox(height: 12),
      Card(child: ListTile(
        leading: const Icon(Icons.event),
        title: const Text('Tarih'),
        subtitle: Text('${selectedDate.day.toString().padLeft(2, '0')}.${selectedDate.month.toString().padLeft(2, '0')}.${selectedDate.year}'),
        trailing: TextButton(onPressed: pickDate, child: const Text('Değiştir')),
      )),
      const SizedBox(height: 10),
      if (entryMode == 'uretim') ...[
        _dd('Makine / Bölüm', machine, appState.machines.map((m) => m['name'] as String).toList(), (v) => setState(() => machine = v!), labelOf: displayMachine),
        if (list.isEmpty)
          const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('Bu makina için ürün tanımlı değil. Önce Yönetim > Ürün Yönetimi\'nden ekleyin.', style: TextStyle(color: Colors.red)))
        else
          _dd('Ürün', productId!, list.map((p) => p['id'] as String).toList(), (v) => setState(() => productId = v),
              labelOf: (id) => list.firstWhere((p) => p['id'] == id)['name'] as String),
        if (list.isNotEmpty) Card(child: ListTile(title: const Text('Gramaj'), subtitle: Text('${gram.toStringAsFixed(2)} g / bakla'), leading: const Icon(Icons.scale_outlined))),
      ] else ...[
        if (appState.stock.isEmpty)
          const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('Henüz stok kalemi yok. Önce Stok bölümünden ekleyin.', style: TextStyle(color: Colors.red)))
        else
          _dd('Hazırlanan Hammadde', stockId!, appState.stock.map((s) => s['id'] as String).toList(), (v) => setState(() => stockId = v),
              labelOf: (id) {
                final s = appState.stock.firstWhere((s) => s['id'] == id);
                return '${fmtCap(s['cap'] as num)} • ${s['malzeme']} (mevcut: ${fmtKg((s['kg'] as num).toDouble())} kg)';
              }),
      ],
      _dd('Vardiya', shift, shifts, (v) => setState(() => shift = v!)),
      if (appState.operators.isEmpty)
        const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('Operatör tanımlı değil. Önce Yönetim > Operatör Yönetimi\'nden ekleyin.', style: TextStyle(color: Colors.red)))
      else
        _dd('Operatör', operator, appState.operators.map((o) => o['name'] as String).toList(), (v) => setState(() => operator = v!)),
      if (entryMode == 'uretim') ...[
        _dd('Durum', status, statuses, (v) => setState(() => status = v!)),
        if (status == 'Üretimde') ...[
          TextField(controller: qty, keyboardType: TextInputType.number, onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Üretilen bakla adedi', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          if (qn > 0) Card(child: ListTile(title: const Text('Otomatik hesap'), subtitle: Text('${fmtKg(qn * gram / 1000)} kg  •  ${fmtTon(qn * gram / 1000)} ton'))),
        ],
      ] else
        TextField(controller: wireKg, keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Hazırlanan miktar (kg)', border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', border: OutlineInputBorder())),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: saving || appState.operators.isEmpty || (entryMode == 'uretim' ? list.isEmpty : appState.stock.isEmpty) ? null : save,
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
    final monthKg = appState.records.where((r) {
      final d = DateTime.tryParse(r['date'] as String);
      return d != null && d.year == selected.year && d.month == selected.month && r['status'] == 'Üretimde';
    }).fold(0.0, (s, r) => s + (r['kg'] as num).toDouble());
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
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${turkishMonths[selected.month - 1]} ${selected.year} Aylık Toplam Üretim', style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('${fmtKg(monthKg)} kg  •  ${fmtTon(monthKg)} ton', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ]))),
      const SizedBox(height: 12),
      if (list.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Bu tarihte kayıt bulunmuyor.')),
      ...list.map((r) => Card(child: ListTile(
        title: Text(displayMachine(r['machine'])),
        subtitle: Text('${r['product'] ?? r['status']} • ${r['shift']} • ${r['operator']}'
            '${(r['note'] as String?)?.isNotEmpty == true ? '\nNot: ${r['note']}' : ''}'),
        trailing: Text(r['status'] == 'Üretimde' ? '${fmtKg((r['kg'] as num).toDouble())} kg' : r['status']),
      ))),
      const SizedBox(height: 18),
      Text('Tel Çekme', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (appState.wiredrawForDate(date).isEmpty)
        const Padding(padding: EdgeInsets.all(12), child: Text('Bu tarihte tel çekme kaydı yok.')),
      ...appState.wiredrawForDate(date).map((w) => Card(child: ListTile(
        onTap: appState.isAdmin ? () => confirmDeleteWiredraw(context, w) : null,
        title: Text('${fmtCap(w['cap'] as num)} • ${w['malzeme']}'),
        subtitle: Text('${w['shift']} • ${w['operator']}'),
        trailing: Text('${fmtKg((w['kg'] as num).toDouble())} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
      ))),
    ]));
  }
}

// =================== HAMMADDE STOKU ===================

class StockPage extends StatefulWidget {
  const StockPage({super.key});
  @override
  State<StockPage> createState() => _StockPageState();
}

class _StockPageState extends State<StockPage> {
  final cap = TextEditingController();
  final malzeme = TextEditingController();
  final kg = TextEditingController();

  Future<void> add() async {
    final c = double.tryParse(cap.text.replaceAll(',', '.'));
    final k = double.tryParse(kg.text.replaceAll(',', '.'));
    if (c == null || malzeme.text.trim().isEmpty || k == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Çap, malzeme ve miktarı doğru girin.')));
      return;
    }
    await appState.addStock(c, malzeme.text.trim(), k);
    cap.clear(); malzeme.clear(); kg.clear();
  }

  Future<void> editKg(Map<String, dynamic> item) async {
    final ctrl = TextEditingController(text: (item['kg'] as num).toString().replaceAll('.', ','));
    final result = await showDialog<double>(context: context, builder: (_) => AlertDialog(
      title: Text('${fmtCap(item['cap'] as num)} • ${item['malzeme']}'),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true,
          decoration: const InputDecoration(labelText: 'Güncel stok (kg)', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () {
          final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
          Navigator.pop(context, v);
        }, child: const Text('Kaydet')),
      ],
    ));
    if (result != null) await appState.updateStockKg(item['id'], result);
  }

  Future<void> confirmDelete(String id, String label) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Kalemi sil'),
      content: Text('"$label" listeden silinsin mi?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
      ],
    ));
    if (ok == true) await appState.deleteStock(id);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Logo(height: 52), const SizedBox(height: 8),
      Text('Hammadde Stoku', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('TOPLAM STOK', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('${fmtKg(appState.totalStockKg)} kg  •  ${fmtTon(appState.totalStockKg)} ton', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ]))),
      const SizedBox(height: 12),
      if (appState.isAdmin) Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
        Row(children: [
          Expanded(child: TextField(controller: cap, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Çap (mm)', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: malzeme, decoration: const InputDecoration(labelText: 'Malzeme', border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: kg, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Miktar (kg)', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton(onPressed: add, child: const Text('Yeni Kalem Ekle'))),
      ]))),
      const SizedBox(height: 12),
      if (appState.stock.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Henüz hammadde stok kaydı yok.')),
      if (appState.stock.isNotEmpty && appState.isAdmin) ...[
        Text('Sırayı değiştirmek için bir kalemi basılı tutup sürükleyin. Üstteki kalemler en önemli / aktif kullanılanlar olsun.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: appState.stock.length,
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex -= 1;
            final ids = appState.stock.map((s) => s['id'] as String).toList();
            final id = ids.removeAt(oldIndex);
            ids.insert(newIndex, id);
            appState.reorderStock(ids);
          },
          itemBuilder: (context, i) {
            final s = appState.stock[i];
            return Card(key: ValueKey(s['id']), child: ListTile(
              title: Text('${fmtCap(s['cap'] as num)} • ${s['malzeme']}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('${fmtKg((s['kg'] as num).toDouble())} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => editKg(s)),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => confirmDelete(s['id'], '${fmtCap(s['cap'] as num)} ${s['malzeme']}')),
                const Icon(Icons.drag_handle, color: Colors.grey),
              ]),
            ));
          },
        ),
      ] else
        ...appState.stock.map((s) => Card(child: ListTile(
          title: Text('${fmtCap(s['cap'] as num)} • ${s['malzeme']}'),
          trailing: Text('${fmtKg((s['kg'] as num).toDouble())} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
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
    final all = [...appState.products];
    all.sort((a, b) {
      final aActive = appState.isProductActiveToday(a['name'] as String);
      final bActive = appState.isProductActiveToday(b['name'] as String);
      if (aActive != bActive) return aActive ? -1 : 1;
      final oa = (a['order'] as num?)?.toInt() ?? 0;
      final ob = (b['order'] as num?)?.toInt() ?? 0;
      return oa.compareTo(ob);
    });
    final filtered = all.where((p) => (p['name'] as String).toLowerCase().contains(query.toLowerCase())).toList();
    final canDrag = appState.isAdmin && query.isEmpty;

    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Logo(height: 52), const SizedBox(height: 8),
      Text('Ürün Üretim Raporu', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Ürün ara', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      Text('Bugün üretimde olan ürünler otomatik olarak en üstte gösterilir.'
          '${canDrag ? ' Sırayı değiştirmek için bir kartı basılı tutup sürükleyin.' : ''}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      const SizedBox(height: 8),
      if (canDrag)
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: filtered.length,
          onReorder: (oldIndex, newIndex) {
            if (newIndex > oldIndex) newIndex -= 1;
            final ids = filtered.map((p) => p['id'] as String).toList();
            final id = ids.removeAt(oldIndex);
            ids.insert(newIndex, id);
            appState.reorderProducts(ids);
          },
          itemBuilder: (context, i) => KeyedSubtree(
            key: ValueKey(filtered[i]['id']),
            child: _productCard(filtered[i]['name'] as String, dragHandle: true),
          ),
        )
      else
        ...filtered.map((p) => _productCard(p['name'] as String, dragHandle: false)),
    ]));
  }

  Widget _productCard(String name, {required bool dragHandle}) {
    final kg = appState.totalKgForProduct(name);
    final d = appState.firstDateForProduct(name);
    final gram = (appState.products.firstWhere((p) => p['name'] == name)['gram'] as num).toDouble();
    final qty = gram == 0 ? 0 : kg * 1000 / gram;
    final resetD = appState.productResetDates[name];
    final active = appState.isProductActiveToday(name);
    return Card(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: ListTile(
      leading: active ? const Icon(Icons.play_circle_fill, color: Colors.green) : null,
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('İlk üretim: ${d == null ? "—" : fmtDate(dateStr(d))}\nToplam bakla: ${qty.toStringAsFixed(0)}'
          '${resetD != null ? '\n${fmtDate(resetD)} tarihinden itibaren' : ''}'),
      isThreeLine: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${fmtKg(kg)} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${fmtTon(kg)} ton'),
          const SizedBox(height: 4),
          if (appState.isAdmin)
            InkWell(onTap: () => confirmReset(name), child: const Text('Sıfırla', style: TextStyle(fontSize: 12, color: Colors.red))),
        ]),
        if (dragHandle) const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.drag_handle, color: Colors.grey)),
      ]),
    )));
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
        leading: const Icon(Icons.inventory_outlined),
        title: const Text('Stok Yönetimi'),
        subtitle: Text('${appState.stock.length} kalem'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StockPage())),
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
