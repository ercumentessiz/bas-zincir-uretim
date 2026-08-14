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
  List<Map<String, dynamic>> assistantOperators = [];
  List<Map<String, dynamic>> machines = [];
  List<Map<String, dynamic>> stock = [];
  List<Map<String, dynamic>> wiredraw = [];
  Map<String, String> productResetDates = {}; // key: product id
  Map<String, double> productAdjustments = {}; // key: product id
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

    () async {
      bool orderFixDone = false;
      bool typeFixDone = false;
      try {
        final d = await _db.collection('meta').doc('productOrderFix').get();
        orderFixDone = d.data()?['done'] == true;
      } catch (_) {}
      try {
        final d2 = await _db.collection('meta').doc('productTypeFix').get();
        typeFixDone = d2.data()?['done'] == true;
      } catch (_) {}

      _db.collection('products').snapshots().listen((snap) async {
        if (snap.docs.isEmpty && !_seededProducts) {
          _seededProducts = true;
          final batch = _db.batch();
          final sortedSeed = [...seed.products]
            ..sort((a, b) => productSizeKey(a['name'] as String).compareTo(productSizeKey(b['name'] as String)));
          for (var i = 0; i < sortedSeed.length; i++) {
            final p = sortedSeed[i];
            final type = (p['name'] as String).contains('Spanzet') ? 'spanzet' : 'zincir';
            batch.set(_db.collection('products').doc(), {'name': p['name'], 'gram': p['gram'], 'order': i, 'type': type});
          }
          await batch.commit();
          return;
        }
        final list = snap.docs.map((d) {
          final m = Map<String, dynamic>.from(d.data());
          m['id'] = d.id;
          return m;
        }).toList();

        if (!orderFixDone) {
          orderFixDone = true;
          final sorted = [...list]
            ..sort((a, b) => productSizeKey(a['name'] as String).compareTo(productSizeKey(b['name'] as String)));
          final batch = _db.batch();
          for (var i = 0; i < sorted.length; i++) {
            batch.update(_db.collection('products').doc(sorted[i]['id'] as String), {'order': i});
          }
          batch.set(_db.collection('meta').doc('productOrderFix'), {'done': true});
          await batch.commit();
          return;
        }

        if (!typeFixDone) {
          typeFixDone = true;
          final missingType = list.where((p) => p['type'] == null).toList();
          if (missingType.isNotEmpty) {
            final batch = _db.batch();
            for (final p in missingType) {
              final type = (p['name'] as String).contains('Spanzet') ? 'spanzet' : 'zincir';
              batch.update(_db.collection('products').doc(p['id'] as String), {'type': type});
            }
            batch.set(_db.collection('meta').doc('productTypeFix'), {'done': true});
            await batch.commit();
            return;
          } else {
            await _db.collection('meta').doc('productTypeFix').set({'done': true});
          }
        }

        list.sort((a, b) {
          final oa = (a['order'] as num?)?.toInt() ?? 0;
          final ob = (b['order'] as num?)?.toInt() ?? 0;
          return oa.compareTo(ob);
        });
        products = list;
        notifyListeners();
      });
    }();

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

    _db.collection('assistantOperators').orderBy('name').snapshots().listen((snap) {
      assistantOperators = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();
      notifyListeners();
    });

    _db.collection('productSettings').snapshots().listen((snap) {
      final resets = <String, String>{};
      final adjustments = <String, double>{};
      for (final d in snap.docs) {
        final data = d.data();
        if (data['resetDate'] != null) resets[d.id] = data['resetDate'] as String;
        adjustments[d.id] = (data['adjustment'] as num?)?.toDouble() ?? 0.0;
      }
      productResetDates = resets;
      productAdjustments = adjustments;
      notifyListeners();
    });

    _db.collection('machines').snapshots().listen((snap) async {
      if (snap.docs.isEmpty && !_seededMachines) {
        _seededMachines = true;
        final batch = _db.batch();
        for (var i = 0; i < defaultMachineNames.length; i++) {
          batch.set(_db.collection('machines').doc(), {'name': defaultMachineNames[i], 'order': i});
        }
        await batch.commit();
        return;
      }
      final list = snap.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();
      list.sort((a, b) => compareMachineNames(a['name'] as String, b['name'] as String));
      machines = list;
      notifyListeners();
    });

    _db.collection('stock').snapshots().listen((snap) async {
      if (snap.docs.isEmpty && !_seededStock) {
        _seededStock = true;
        final batch = _db.batch();
        for (final s in stockSeed) {
          batch.set(_db.collection('stock').doc(), {'cap': s['cap'], 'malzeme': s['malzeme'], 'kg': s['kg']});
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
  Future<void> addProduct(String name, double gram, String type) async {
    final sorted = [...products]
      ..sort((a, b) => ((a['order'] as num?)?.toInt() ?? 0).compareTo((b['order'] as num?)?.toInt() ?? 0));
    final newSize = productSizeKey(name);
    int insertAt = sorted.length;
    for (var i = 0; i < sorted.length; i++) {
      if (newSize < productSizeKey(sorted[i]['name'] as String)) { insertAt = i; break; }
    }
    final batch = _db.batch();
    for (var i = insertAt; i < sorted.length; i++) {
      batch.update(_db.collection('products').doc(sorted[i]['id'] as String), {'order': i + 1});
    }
    final newRef = _db.collection('products').doc();
    batch.set(newRef, {'name': name, 'gram': gram, 'order': insertAt, 'type': type});
    await batch.commit();
  }
  Future<void> deleteProduct(String id) => _db.collection('products').doc(id).delete();

  Future<String?> reorderProducts(List<String> orderedIds) async {
    final map = {for (final p in products) p['id'] as String: p};
    final newList = <Map<String, dynamic>>[];
    for (var i = 0; i < orderedIds.length; i++) {
      final id = orderedIds[i];
      if (!map.containsKey(id)) continue;
      final item = Map<String, dynamic>.from(map[id]!);
      item['order'] = i;
      newList.add(item);
    }
    products = newList;
    notifyListeners();
    try {
      final batch = _db.batch();
      for (var i = 0; i < orderedIds.length; i++) {
        batch.update(_db.collection('products').doc(orderedIds[i]), {'order': i});
      }
      await batch.commit();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  bool isProductActiveToday(String name) {
    final d = lastEntryDate();
    return records.any((r) => r['date'] == d && r['status'] == 'Üretimde' && r['product'] == name);
  }

  // ---- Operatörler ----
  Future<void> addOperator(String name) => _db.collection('operators').add({'name': name});
  Future<void> deleteOperator(String id) => _db.collection('operators').doc(id).delete();

  // ---- Yardımcı Operatörler ----
  Future<void> addAssistantOperator(String name) => _db.collection('assistantOperators').add({'name': name});
  Future<void> deleteAssistantOperator(String id) => _db.collection('assistantOperators').doc(id).delete();

  // ---- Makinalar ----
  Future<void> addMachine(String name) => _db.collection('machines').add({'name': name});
  Future<void> deleteMachine(String id) => _db.collection('machines').doc(id).delete();

  // ---- Hammadde Stoku ----
  Future<void> addStock(double cap, String malzeme, double kg) =>
      _db.collection('stock').add({'cap': cap, 'malzeme': malzeme, 'kg': kg});

  Future<void> updateStockKg(String id, double kg) async {
    final idx = stock.indexWhere((s) => s['id'] == id);
    if (idx != -1) {
      final newStock = [...stock];
      newStock[idx] = {...newStock[idx], 'kg': kg};
      stock = newStock;
      notifyListeners();
    }
    await _db.collection('stock').doc(id).update({'kg': kg});
  }

  Future<void> subtractStock(String id, double subtractKg) async {
    final idx = stock.indexWhere((s) => s['id'] == id);
    if (idx == -1) return;
    final next = (stock[idx]['kg'] as num).toDouble() - subtractKg;
    await updateStockKg(id, next);
  }

  Future<void> deleteStock(String id) => _db.collection('stock').doc(id).delete();

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

  // ---- Ürün bazlı sayaç sıfırlama ve manuel düşüm ----
  Future<void> resetProductTotal(String productId) async {
    final date = dateNow();
    productResetDates = {...productResetDates, productId: date};
    productAdjustments = {...productAdjustments, productId: 0};
    notifyListeners();
    await _db.collection('productSettings').doc(productId).set({
      'resetDate': date,
      'adjustment': 0,
    }, SetOptions(merge: true));
  }

  /// Bir ürünün toplamını istenen kg değerine ayarlar (elle ekleme/çıkarma
  /// için tek yöntem — aradaki fark otomatik hesaplanıp saklanır).
  Future<void> setProductTotal(String productId, String productName, double newTotal) async {
    final produced = records
        .where((r) => r['product'] == productName && r['status'] == 'Üretimde' && _afterReset(productId, r['date'] as String))
        .fold(0.0, (s, r) => s + (r['kg'] as num).toDouble());
    final newAdj = newTotal - produced;
    productAdjustments = {...productAdjustments, productId: newAdj};
    notifyListeners();
    await _db.collection('productSettings').doc(productId).set({'adjustment': newAdj}, SetOptions(merge: true));
  }

  bool _afterReset(String productId, String date) {
    final r = productResetDates[productId];
    return r == null || date.compareTo(r) >= 0;
  }

  double totalKgForProduct(String productId, String name) {
    final produced = records
        .where((r) => r['product'] == name && r['status'] == 'Üretimde' && _afterReset(productId, r['date'] as String))
        .fold(0.0, (s, r) => s + (r['kg'] as num).toDouble());
    final adj = productAdjustments[productId] ?? 0.0;
    final total = produced + adj;
    return total < 0 ? 0 : total;
  }

  DateTime? firstDateForProduct(String productId, String name) {
    final ds = records
        .where((r) => r['product'] == name && r['status'] == 'Üretimde' && _afterReset(productId, r['date'] as String))
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

/// Sayfaların appState değişikliklerini, sekme değiştirmeden, doğrudan ve
/// güvenilir şekilde yakalaması için her sayfanın kendi dinleyicisi.
class AppStateBuilder extends StatelessWidget {
  final WidgetBuilder builder;
  const AppStateBuilder({super.key, required this.builder});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: appState, builder: (context, _) => builder(context));
}

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
            : HomePage(key: homeKey),
      ),
    );
  }
}

final homeKey = GlobalKey<_HomePageState>();

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  void goToHome() => setState(() => index = 0);
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
      const NavigationDestination(icon: Icon(Icons.inventory_outlined), selectedIcon: Icon(Icons.inventory), label: 'Hammadde'),
      const NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: 'Ürün Stok'),
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

const turkishWeekdays = ['Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar'];

/// Özet ekranında gösterilecek gün: en son veri girişi yapılan tarih.
/// Böylece hangi gün girilmemiş olursa olsun (hafta sonu, unutulan gün vb.)
/// her zaman gerçek veriye göre doğru günü gösterir.
String lastEntryDate() {
  final dates = <String>{
    ...appState.records.map((r) => r['date'] as String),
    ...appState.wiredraw.map((w) => w['date'] as String),
  };
  if (dates.isEmpty) return dateNow();
  final list = dates.toList()..sort();
  return list.last;
}

String recordsSectionTitle(String isoDate) {
  final d = DateTime.tryParse(isoDate);
  if (d == null) return 'Kayıtlar';
  return '${turkishWeekdays[d.weekday - 1]} Gününe Ait Kayıtlar';
}
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

/// "Makine 23" ya da "23. Makine" biçimlerinin her ikisini de tanıyıp
/// makina numarasını çıkarır. Eşleşme yoksa null döner.
int? extractMakineNumber(String name) {
  final trimmed = name.trim();
  final m1 = RegExp(r'^Makine (\d+)$').firstMatch(trimmed);
  if (m1 != null) return int.parse(m1.group(1)!);
  final m2 = RegExp(r'^(\d+)\.\s*Makine$').firstMatch(trimmed);
  if (m2 != null) return int.parse(m2.group(1)!);
  return null;
}

String displayMachine(String m) {
  final n = extractMakineNumber(m);
  return n != null ? '$n. Makine' : m;
}

String fmtCap(num c) {
  final isWhole = c % 1 == 0;
  return isWhole ? '${c.toInt()} mm' : '${c.toString().replaceAll('.', ',')} mm';
}

/// Ürün adındaki ilk sayıyı (ör. "13x36 mm..." -> 13) sıralama anahtarı olarak döner.
double productSizeKey(String name) {
  final match = RegExp(r'^(\d+(?:[.,]\d+)?)').firstMatch(name.trim());
  if (match == null) return double.infinity;
  return double.tryParse(match.group(1)!.replaceAll(',', '.')) ?? double.infinity;
}

/// Makinaları önce "Makine N" olanlar numara sırasına göre, sonra diğerleri
/// (Spanzet vb.) kendi içindeki numaraya göre sıralar. Yeni eklenen bir
/// makina her zaman doğru sayısal konuma yerleşir, listenin sonuna düşmez.
List<Object> machineSortKey(String name) {
  final n = extractMakineNumber(name);
  if (n != null) return [0, n.toDouble()];
  final m2 = RegExp(r'(\d+(?:[.,]\d+)?)').firstMatch(name);
  final val = m2 != null ? (double.tryParse(m2.group(1)!.replaceAll(',', '.')) ?? double.infinity) : double.infinity;
  return [1, val];
}

int compareMachineNames(String a, String b) {
  final ka = machineSortKey(a);
  final kb = machineSortKey(b);
  final tierCompare = (ka[0] as int).compareTo(kb[0] as int);
  if (tierCompare != 0) return tierCompare;
  return (ka[1] as double).compareTo(kb[1] as double);
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

Future<void> confirmDeleteRecord(BuildContext context, Map<String, dynamic> r) async {
  final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
    title: const Text('Kaydı Sil'),
    content: Text('${displayMachine(r['machine'])} • ${r['product'] ?? r['status']} kaydı kalıcı olarak silinecek. Emin misiniz?'),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
    ],
  ));
  if (ok == true) await appState.deleteRecord(r['id']);
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
  bool showPass = false;

  Future<void> doLogin() async {
    setState(() { busy = true; error = null; });
    final err = await appState.signIn(email.text.trim(), pass.text);
    if (err == null) {
      homeKey.currentState?.goToHome();
    } else if (mounted) {
      setState(() { busy = false; error = err; });
    }
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
        TextField(controller: pass, obscureText: !showPass,
            decoration: InputDecoration(
              labelText: 'Şifre', border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(showPass ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => showPass = !showPass),
              ),
            )),
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
  Widget build(BuildContext context) => AppStateBuilder(builder: (context) {
    final today = lastEntryDate();
    final sectionTitle = recordsSectionTitle(today);
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
        const Text('TOPLAM ÜRETİM', style: TextStyle(fontWeight: FontWeight.w600)),
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
      Text(sectionTitle, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (todayRecords.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Bu tarihte kayıt bulunmuyor.'))),
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
            '${(r['assistantOperator'] as String?)?.isNotEmpty == true ? ' + ${r['assistantOperator']}' : ''}'
            '${(r['note'] as String?)?.isNotEmpty == true ? '\nNot: ${r['note']}' : ''}'),
        trailing: appState.isAdmin
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Text(r['status'] == 'Üretimde' ? '${fmtKg((r['kg'] as num).toDouble())} kg' : r['status']),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => confirmDeleteRecord(context, r)),
              ])
            : Text(r['status'] == 'Üretimde' ? '${fmtKg((r['kg'] as num).toDouble())} kg' : r['status'], textAlign: TextAlign.end),
      ))),
      const SizedBox(height: 18),
      Text('Tel Çekme', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (appState.wiredrawForDate(today).isEmpty)
        const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Bu tarihte tel çekme kaydı yok.'))),
      ...appState.wiredrawForDate(today).map((w) => Card(child: ListTile(
        onTap: appState.isAdmin ? () => confirmDeleteWiredraw(context, w) : null,
        title: Text('${fmtCap(w['cap'] as num)} • ${w['malzeme']}'),
        subtitle: Text('${w['shift']} • ${w['operator']}'),
        trailing: Text('${fmtKg((w['kg'] as num).toDouble())} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
      ))),
    ]));
  });
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
  String machine = 'Makine 1', operator = '', assistantOperator = '', shift = 'Gündüz', status = 'Üretimde';
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
    final isSpanzetMachine = machine.toLowerCase().contains('spanzet');
    return appState.products.where((p) => (p['type'] == 'spanzet') == isSpanzetMachine).toList();
  }

  Future<void> pickProduct() async {
    final list = [...availableProducts]..sort((a, b) => productSizeKey(a['name'] as String).compareTo(productSizeKey(b['name'] as String)));
    String q = '';
    final result = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        final filtered = list.where((p) => (p['name'] as String).toLowerCase().contains(q.toLowerCase())).toList();
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              Text('Ürün Seç', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(autofocus: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Ürün ara', border: OutlineInputBorder()),
                  onChanged: (v) => setSheetState(() => q = v)),
              const SizedBox(height: 8),
              Expanded(child: filtered.isEmpty
                  ? const Center(child: Text('Sonuç bulunamadı.'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(filtered[i]['name'] as String),
                        subtitle: Text('${filtered[i]['gram']} g/bakla'),
                        onTap: () => Navigator.pop(ctx, filtered[i]['id'] as String),
                      ),
                    )),
            ])),
          ),
        );
      }),
    );
    if (result != null) setState(() => productId = result);
  }

  bool get needsProduct => status == 'Üretimde' || status == 'Arızalı' || status == 'Parça Kırdı';

  Future<void> save() async {
    if (operator.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Operatör seçin.')));
      return;
    }
    if (entryMode == 'uretim') {
      final list = availableProducts;
      Map<String, dynamic>? p;
      if (needsProduct) {
        if (list.isEmpty) return;
        p = list.firstWhere((p) => p['id'] == productId, orElse: () => list.first);
      }
      final gram = p == null ? 0.0 : (p['gram'] as num).toDouble();
      final q = int.tryParse(qty.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
      if (status == 'Üretimde' && q <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Üretim adedini girin.')));
        return;
      }
      final kg = status == 'Üretimde' ? q * gram / 1000 : 0;
      setState(() => saving = true);
      try {
        await appState.add({
          'date': dateStr(selectedDate), 'machine': machine, 'product': p?['name'], 'gram': gram,
          'operator': operator, 'assistantOperator': assistantOperator, 'shift': shift, 'status': status, 'qty': q, 'kg': kg, 'note': note.text.trim()
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
      try {
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
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
      } finally {
        if (mounted) setState(() => saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AppStateBuilder(builder: (context) {
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
        _dd('Durum', status, statuses, (v) => setState(() => status = v!)),
        if (needsProduct) ...[
          if (list.isEmpty)
            const Padding(padding: EdgeInsets.only(bottom: 10), child: Text('Bu makina için ürün tanımlı değil. Önce Yönetim > Ürün Yönetimi\'nden ekleyin.', style: TextStyle(color: Colors.red)))
          else
            Card(child: ListTile(
              title: const Text('Ürün'),
              subtitle: Text(list.firstWhere((p) => p['id'] == productId, orElse: () => list.first)['name'] as String),
              trailing: const Icon(Icons.search),
              onTap: pickProduct,
            )),
          if (list.isNotEmpty) Card(child: ListTile(title: const Text('Gramaj'), subtitle: Text('${gram.toStringAsFixed(2)} g / bakla'), leading: const Icon(Icons.scale_outlined))),
        ],
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
      if (appState.assistantOperators.isNotEmpty)
        _dd('Yardımcı Operatör', assistantOperator.isEmpty ? '(Seçilmedi)' : assistantOperator,
            ['(Seçilmedi)', ...appState.assistantOperators.map((o) => o['name'] as String)],
            (v) => setState(() => assistantOperator = v == '(Seçilmedi)' ? '' : v!)),
      if (entryMode == 'uretim') ...[
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
        onPressed: saving || appState.operators.isEmpty || (entryMode == 'uretim' ? (needsProduct && list.isEmpty) : appState.stock.isEmpty) ? null : save,
        icon: const Icon(Icons.save),
        label: Padding(padding: const EdgeInsets.all(12), child: Text(saving ? 'KAYDEDİLİYOR...' : 'KAYDET')),
      ),
    ]));
  });

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
  Widget build(BuildContext context) => AppStateBuilder(builder: (context) {
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
          subtitle: Text('${r['status']}${r['status'] == 'Üretimde' ? ' • ${r['qty']} bakla • ${fmtKg((r['kg'] as num).toDouble())} kg' : ''}\n${r['operator']}${(r['assistantOperator'] as String?)?.isNotEmpty == true ? ' + ${r['assistantOperator']}' : ''} • ${r['shift']}'),
          isThreeLine: true,
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => openEdit(r)),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => confirmDelete(r['id'])),
          ]),
        ))),
      ])),
    );
  });
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
  late String assistantOperator = widget.record['assistantOperator'] ?? '';
  late String shift = widget.record['shift'];
  late String? productId;
  late TextEditingController qty;
  late TextEditingController note;
  bool saving = false;

  bool get needsProduct => status == 'Üretimde' || status == 'Arızalı' || status == 'Parça Kırdı';

  @override
  void initState() {
    super.initState();
    qty = TextEditingController(text: widget.record['qty']?.toString() ?? '');
    note = TextEditingController(text: widget.record['note'] ?? '');
    final match = appState.products.where((p) => p['name'] == widget.record['product']).toList();
    productId = match.isNotEmpty ? match.first['id'] as String : null;
  }

  List<Map<String, dynamic>> get availableProducts {
    final isSpanzetMachine = machine.toLowerCase().contains('spanzet');
    return appState.products.where((p) => (p['type'] == 'spanzet') == isSpanzetMachine).toList();
  }

  Future<void> pickProduct() async {
    final list = [...availableProducts]..sort((a, b) => productSizeKey(a['name'] as String).compareTo(productSizeKey(b['name'] as String)));
    String q = '';
    final result = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setSheetState) {
        final filtered = list.where((p) => (p['name'] as String).toLowerCase().contains(q.toLowerCase())).toList();
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SizedBox(
            height: MediaQuery.of(ctx).size.height * 0.75,
            child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
              Text('Ürün Seç', style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              TextField(autofocus: true, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Ürün ara', border: OutlineInputBorder()),
                  onChanged: (v) => setSheetState(() => q = v)),
              const SizedBox(height: 8),
              Expanded(child: filtered.isEmpty
                  ? const Center(child: Text('Sonuç bulunamadı.'))
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(filtered[i]['name'] as String),
                        subtitle: Text('${filtered[i]['gram']} g/bakla'),
                        onTap: () => Navigator.pop(ctx, filtered[i]['id'] as String),
                      ),
                    )),
            ])),
          ),
        );
      }),
    );
    if (result != null) setState(() => productId = result);
  }

  Future<void> save() async {
    final list = availableProducts;
    Map<String, dynamic>? p;
    if (needsProduct && list.isNotEmpty) p = list.firstWhere((p) => p['id'] == productId, orElse: () => list.first);
    final q = int.tryParse(qty.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
    final gram = p == null ? 0.0 : (p['gram'] as num).toDouble();
    final kg = status == 'Üretimde' ? q * gram / 1000 : 0;
    setState(() => saving = true);
    try {
      await appState.update(widget.record['id'], {
        'machine': machine, 'product': p?['name'], 'gram': gram,
        'operator': operator, 'assistantOperator': assistantOperator, 'shift': shift, 'status': status, 'qty': q, 'kg': kg, 'note': note.text.trim(),
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
        _dd('Durum', status, statuses, (v) => setState(() => status = v!)),
        if (needsProduct && list.isNotEmpty)
          Card(child: ListTile(
            title: const Text('Ürün'),
            subtitle: Text(list.firstWhere((p) => p['id'] == productId, orElse: () => list.first)['name'] as String),
            trailing: const Icon(Icons.search),
            onTap: pickProduct,
          )),
        _dd('Vardiya', shift, shifts, (v) => setState(() => shift = v!)),
        if (appState.operators.isNotEmpty)
          _dd('Operatör', operator, appState.operators.map((o) => o['name'] as String).toList(), (v) => setState(() => operator = v!)),
        if (appState.assistantOperators.isNotEmpty)
          _dd('Yardımcı Operatör', assistantOperator.isEmpty ? '(Seçilmedi)' : assistantOperator,
              ['(Seçilmedi)', ...appState.assistantOperators.map((o) => o['name'] as String)],
              (v) => setState(() => assistantOperator = v == '(Seçilmedi)' ? '' : v!)),
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
  String perfMode = 'uretim';
  String perfPeriod = 'gun';

  @override
  Widget build(BuildContext context) => AppStateBuilder(builder: (context) {
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
      if (appState.isAdmin && list.isNotEmpty)
        Padding(padding: const EdgeInsets.only(bottom: 4), child: Text('Düzeltmek için bir kayda dokunun', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
      ...list.map((r) => Card(child: ListTile(
        onTap: appState.isAdmin ? () => showModalBottomSheet(
          context: context, isScrollControlled: true,
          builder: (_) => Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
            child: EditRecordSheet(record: r),
          ),
        ) : null,
        title: Text(displayMachine(r['machine'])),
        subtitle: Text('${r['product'] ?? r['status']} • ${r['shift']} • ${r['operator']}'
            '${(r['assistantOperator'] as String?)?.isNotEmpty == true ? ' + ${r['assistantOperator']}' : ''}'
            '${(r['note'] as String?)?.isNotEmpty == true ? '\nNot: ${r['note']}' : ''}'),
        trailing: appState.isAdmin
            ? Row(mainAxisSize: MainAxisSize.min, children: [
                Text(r['status'] == 'Üretimde' ? '${fmtKg((r['kg'] as num).toDouble())} kg' : r['status']),
                IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => confirmDeleteRecord(context, r)),
              ])
            : Text(r['status'] == 'Üretimde' ? '${fmtKg((r['kg'] as num).toDouble())} kg' : r['status']),
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
      const SizedBox(height: 18),
      Text('Personel Performansı', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: ChoiceChip(
          label: const Text('Zincir Üretimi'), selected: perfMode == 'uretim',
          onSelected: (_) => setState(() => perfMode = 'uretim'),
        )),
        const SizedBox(width: 8),
        Expanded(child: ChoiceChip(
          label: const Text('Tel Çekme'), selected: perfMode == 'telcekme',
          onSelected: (_) => setState(() => perfMode = 'telcekme'),
        )),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: ChoiceChip(
          label: Text(fmtDate(date)), selected: perfPeriod == 'gun',
          onSelected: (_) => setState(() => perfPeriod = 'gun'),
        )),
        const SizedBox(width: 8),
        Expanded(child: ChoiceChip(
          label: Text('${turkishMonths[selected.month - 1]} ${selected.year}'), selected: perfPeriod == 'ay',
          onSelected: (_) => setState(() => perfPeriod = 'ay'),
        )),
      ]),
      const SizedBox(height: 10),
      ..._operatorBreakdown(perfMode, perfPeriod, date),
    ]));
  });

  List<Widget> _operatorBreakdown(String mode, String period, String date) {
    final source = mode == 'uretim' ? appState.records : appState.wiredraw;
    final filtered = source.where((r) {
      if (mode == 'uretim' && r['status'] != 'Üretimde') return false;
      if (period == 'gun') return r['date'] == date;
      final d = DateTime.tryParse(r['date'] as String? ?? '');
      return d != null && d.year == selected.year && d.month == selected.month;
    });
    final totals = <String, double>{};
    for (final r in filtered) {
      final op = (r['operator'] as String?)?.trim();
      if (op == null || op.isEmpty) continue;
      totals[op] = (totals[op] ?? 0) + (r['kg'] as num).toDouble();
    }
    final sortedOps = totals.keys.toList()..sort((a, b) => totals[b]!.compareTo(totals[a]!));
    if (sortedOps.isEmpty) {
      return [const Padding(padding: EdgeInsets.all(12), child: Text('Bu dönemde kayıt bulunmuyor.'))];
    }
    return sortedOps.asMap().entries.map((e) {
      final kg = totals[e.value]!;
      return Card(child: ListTile(
        leading: CircleAvatar(child: Text('${e.key + 1}')),
        title: Text(e.value),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('${fmtKg(kg)} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${fmtTon(kg)} ton', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
      ));
    }).toList();
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

  Future<void> adjustStockDialog(Map<String, dynamic> item) async {
    final ctrl = TextEditingController();
    final result = await showDialog<double>(context: context, builder: (_) => AlertDialog(
      title: Text('${fmtCap(item['cap'] as num)} • ${item['malzeme']}'),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true,
          decoration: const InputDecoration(labelText: 'Düşülecek miktar (kg)', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () {
          final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
          Navigator.pop(context, v);
        }, child: const Text('Düş')),
      ],
    ));
    if (result != null && result > 0) {
      try {
        await appState.subtractStock(item['id'], result);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${fmtKg(result)} kg düşüldü.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
      }
    }
  }

  /// Çapa göre küçükten büyüğe, aynı çapta malzeme adına göre sabit sıralama.
  List<Map<String, dynamic>> sortedStock() {
    final list = [...appState.stock];
    list.sort((a, b) {
      final c = (a['cap'] as num).compareTo(b['cap'] as num);
      if (c != 0) return c;
      return (a['malzeme'] as String).compareTo(b['malzeme'] as String);
    });
    return list;
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
  Widget build(BuildContext context) => AppStateBuilder(builder: (context) {
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Logo(height: 52), const SizedBox(height: 8),
      Text('Hammadde Stok', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
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
      ...sortedStock().map((s) => Card(child: ListTile(
        title: Text('${fmtCap(s['cap'] as num)} • ${s['malzeme']}'),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${fmtKg((s['kg'] as num).toDouble())} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
          if (appState.isAdmin) ...[
            IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Miktarı ayarla', onPressed: () => editKg(s)),
            IconButton(icon: const Icon(Icons.remove_circle_outline), tooltip: 'Manuel Düş', onPressed: () => adjustStockDialog(s)),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => confirmDelete(s['id'], '${fmtCap(s['cap'] as num)} ${s['malzeme']}')),
          ],
        ]),
      ))),
    ]));
  });
}

// =================== RAPORLAR (KÜMÜLATİF) ===================

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String query = '';

  Future<void> confirmReset(String productId, String name) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Ürünü Sıfırla'),
      content: Text('"$name" için kümülatif toplam bugünden itibaren sıfırdan sayılmaya başlayacak. Geçmiş kayıtlar silinmez, sadece bu ürünün toplamı bu tarihten itibaren hesaplanır. Emin misiniz?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sıfırla')),
      ],
    ));
    if (ok == true) {
      await appState.resetProductTotal(productId);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$name" sıfırlandı.')));
    }
  }

  Future<void> editTotalDialog(String productId, String name, double currentTotal) async {
    final ctrl = TextEditingController(text: currentTotal.toStringAsFixed(2).replaceAll('.', ','));
    final result = await showDialog<double>(context: context, builder: (_) => AlertDialog(
      title: Text(name),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number, autofocus: true,
          decoration: const InputDecoration(labelText: 'Güncel toplam (kg)', border: OutlineInputBorder())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(onPressed: () {
          final v = double.tryParse(ctrl.text.replaceAll(',', '.'));
          Navigator.pop(context, v);
        }, child: const Text('Kaydet')),
      ],
    ));
    if (result != null && result >= 0) {
      try {
        await appState.setProductTotal(productId, name, result);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$name" toplamı ${fmtKg(result)} kg olarak güncellendi.')));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
      }
    }
  }

  Future<void> moveProduct(List<Map<String, dynamic>> filtered, int index, int delta) async {
    final newIndex = index + delta;
    if (newIndex < 0 || newIndex >= filtered.length) return;
    final ids = filtered.map((p) => p['id'] as String).toList();
    final id = ids.removeAt(index);
    ids.insert(newIndex, id);
    final err = await appState.reorderProducts(ids);
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sıralama kaydedilemedi: $err')));
    }
  }

  @override
  Widget build(BuildContext context) => AppStateBuilder(builder: (context) {
    final all = [...appState.products];
    all.sort((a, b) {
      final oa = (a['order'] as num?)?.toInt() ?? 0;
      final ob = (b['order'] as num?)?.toInt() ?? 0;
      return oa.compareTo(ob);
    });
    final filtered = all.where((p) => (p['name'] as String).toLowerCase().contains(query.toLowerCase())).toList();
    final canReorder = appState.isAdmin && query.isEmpty;

    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Logo(height: 52), const SizedBox(height: 8),
      Text('Ürün Stok', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Ürün ara', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      Text('Aktif üretimdeki ürünler yeşil ikonla işaretlenir. Sıra tamamen elle belirlenir'
          '${canReorder ? ' — bir kartın sağındaki ok düğmeleriyle yukarı/aşağı taşıyabilirsiniz.' : '.'}',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
      const SizedBox(height: 8),
      ...filtered.asMap().entries.map((e) => _productCard(
            e.value['name'] as String,
            canReorder: canReorder,
            index: e.key,
            total: filtered.length,
            filtered: filtered,
          )),
    ]));
  });

  Widget _productCard(String name, {required bool canReorder, int? index, int? total, List<Map<String, dynamic>>? filtered}) {
    final product = appState.products.firstWhere((p) => p['name'] == name);
    final productId = product['id'] as String;
    final kg = appState.totalKgForProduct(productId, name);
    final d = appState.firstDateForProduct(productId, name);
    final gram = (product['gram'] as num).toDouble();
    final qty = gram == 0 ? 0 : kg * 1000 / gram;
    final resetD = appState.productResetDates[productId];
    final active = appState.isProductActiveToday(name);
    return Card(child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (active) const Padding(padding: EdgeInsets.only(right: 8, top: 2), child: Icon(Icons.play_circle_fill, color: Colors.green, size: 20)),
          Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
          if (canReorder && index != null && total != null && filtered != null)
            Column(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: index > 0 ? () => moveProduct(filtered, index, -1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                iconSize: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: index < total - 1 ? () => moveProduct(filtered, index, 1) : null,
              ),
            ]),
        ]),
        const SizedBox(height: 6),
        Text('İlk üretim: ${d == null ? "—" : fmtDate(dateStr(d))}   •   Toplam bakla: ${qty.toStringAsFixed(0)}'
            '${resetD != null ? '\n${fmtDate(resetD)} tarihinden itibaren' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 10),
        Row(children: [
          Text('${fmtKg(kg)} kg  •  ${fmtTon(kg)} ton', style: const TextStyle(fontWeight: FontWeight.bold)),
          const Spacer(),
          if (appState.isAdmin) ...[
            TextButton(
              onPressed: () => editTotalDialog(productId, name, kg),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('Düzenle', style: TextStyle(fontSize: 12, color: Colors.blue)),
            ),
            TextButton(
              onPressed: () => confirmReset(productId, name),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              child: const Text('Sıfırla', style: TextStyle(fontSize: 12, color: Colors.red)),
            ),
          ],
        ]),
      ]),
    ));
  }
}

// =================== YÖNETİM ===================

class ManagementPage extends StatelessWidget {
  const ManagementPage({super.key});

  @override
  Widget build(BuildContext context) => AppStateBuilder(builder: (context) {
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
        title: const Text('Hammadde Stok Yönetimi'),
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
      Card(child: ListTile(
        leading: const Icon(Icons.engineering_outlined),
        title: const Text('Yardımcı Operatör Yönetimi'),
        subtitle: Text('${appState.assistantOperators.length} yardımcı operatör'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantOperatorsManagePage())),
      )),
      const SizedBox(height: 8),
      OutlinedButton.icon(onPressed: () => appState.signOut(), icon: const Icon(Icons.logout), label: const Text('Çıkış Yap')),
    ]));
  });
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
  Widget build(BuildContext context) => AppStateBuilder(builder: (context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Makina Yönetimi')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Makina adı (örn. Makine 23 veya 23. Makine)', border: OutlineInputBorder())),
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
  });
}

class ProductsManagePage extends StatefulWidget {
  const ProductsManagePage({super.key});
  @override
  State<ProductsManagePage> createState() => _ProductsManagePageState();
}

class _ProductsManagePageState extends State<ProductsManagePage> {
  final name = TextEditingController();
  final gram = TextEditingController();
  String type = 'zincir';

  Future<void> add() async {
    final g = double.tryParse(gram.text.replaceAll(',', '.'));
    if (name.text.trim().isEmpty || g == null || g <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ürün adı ve geçerli bir gramaj girin.')));
      return;
    }
    await appState.addProduct(name.text.trim(), g, type);
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
  Widget build(BuildContext context) => AppStateBuilder(builder: (context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ürün Yönetimi')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Ürün adı (örn. 7x22 mm zincir)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          TextField(controller: gram, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Gramaj (gram/bakla)', border: OutlineInputBorder())),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: ChoiceChip(label: const Text('Zincir'), selected: type == 'zincir', onSelected: (_) => setState(() => type = 'zincir'))),
            const SizedBox(width: 8),
            Expanded(child: ChoiceChip(label: const Text('Spanzet'), selected: type == 'spanzet', onSelected: (_) => setState(() => type = 'spanzet'))),
          ]),
          const SizedBox(height: 10),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: add, child: const Text('Ürün Ekle'))),
        ]))),
        const SizedBox(height: 12),
        ...appState.products.map((p) => Card(child: ListTile(
          title: Text(p['name']),
          subtitle: Text('${p['gram']} g/bakla  •  ${p['type'] == 'spanzet' ? 'Spanzet' : 'Zincir'}'),
          trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => confirmDelete(p['id'], p['name'])),
        ))),
      ])),
    );
  });
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
  Widget build(BuildContext context) => AppStateBuilder(builder: (context) {
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
  });
}


class AssistantOperatorsManagePage extends StatefulWidget {
  const AssistantOperatorsManagePage({super.key});
  @override
  State<AssistantOperatorsManagePage> createState() => _AssistantOperatorsManagePageState();
}

class _AssistantOperatorsManagePageState extends State<AssistantOperatorsManagePage> {
  final name = TextEditingController();

  Future<void> add() async {
    if (name.text.trim().isEmpty) return;
    await appState.addAssistantOperator(name.text.trim());
    name.clear();
  }

  Future<void> confirmDelete(String id, String label) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Yardımcı operatörü sil'),
      content: Text('"$label" silinsin mi?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
      ],
    ));
    if (ok == true) await appState.deleteAssistantOperator(id);
  }

  @override
  Widget build(BuildContext context) => AppStateBuilder(builder: (context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yardımcı Operatör Yönetimi')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
        Card(child: Padding(padding: const EdgeInsets.all(14), child: Row(children: [
          Expanded(child: TextField(controller: name, decoration: const InputDecoration(labelText: 'Yardımcı operatör adı', border: OutlineInputBorder()))),
          const SizedBox(width: 8),
          FilledButton(onPressed: add, child: const Text('Ekle')),
        ]))),
        const SizedBox(height: 12),
        ...appState.assistantOperators.map((o) => Card(child: ListTile(
          title: Text(o['name']),
          trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () => confirmDelete(o['id'], o['name'])),
        ))),
      ])),
    );
  });
}
