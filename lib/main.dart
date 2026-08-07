import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'products.dart';

const operators = [
  'Ekrem Ünal', 'Ozan Tüzün', 'Emircan Akyar', 'Mehmet Kavrık',
  'Süleyman Ak', 'Mehmet Güre', 'Tuncay Üstünel', 'Hüseyin Yurttaş',
  'Oğuzhan Sarıkaya', 'Hüseyin Bıyık'
];

const shifts = ['Gündüz', 'Gece'];
const statuses = ['Üretimde', 'Ayar Dönülüyor', 'Arızalı', 'Parça Kırdı', 'Bakımda', 'Diğer'];

/// Tüm üretim kayıtlarını Firestore'dan gerçek zamanlı dinler.
/// Uygulamayı açan herkes (siz, patron, pazarlamacı) aynı veriyi görür.
class AppState extends ChangeNotifier {
  final _db = FirebaseFirestore.instance;
  List<Map<String, dynamic>> records = [];
  bool loading = true;
  User? currentUser;

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
    }, onError: (e) {
      loading = false;
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

  Future<void> add(Map<String, dynamic> r) async {
    r['createdAt'] = FieldValue.serverTimestamp();
    await _db.collection('records').add(r);
  }

  double totalKgForProduct(String name) => records
      .where((r) => r['product'] == name && r['status'] == 'Üretimde')
      .fold(0.0, (s, r) => s + (r['kg'] as num).toDouble());

  DateTime? firstDateForProduct(String name) {
    final ds = records
        .where((r) => r['product'] == name && r['status'] == 'Üretimde')
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

  double totalTodayTon(String date) => totalTodayKg(date) / 1000;
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
      const ReportsPage(),
      isAdmin ? const AccountPage() : const LoginPage(),
    ];
    final destinations = [
      const NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Özet'),
      if (isAdmin) const NavigationDestination(icon: Icon(Icons.add_circle_outline), selectedIcon: Icon(Icons.add_circle), label: 'Üretim Girişi'),
      const NavigationDestination(icon: Icon(Icons.assessment_outlined), selectedIcon: Icon(Icons.assessment), label: 'Raporlar'),
      NavigationDestination(
        icon: Icon(isAdmin ? Icons.person : Icons.login),
        selectedIcon: Icon(isAdmin ? Icons.person : Icons.login),
        label: isAdmin ? 'Hesap' : 'Yönetici Girişi',
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

class Logo extends StatelessWidget {
  final double height;
  const Logo({super.key, this.height = 55});
  @override
  Widget build(BuildContext context) => Image.asset('assets/bas_zincir_icon.png', height: height);
}

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

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});
  @override
  Widget build(BuildContext context) {
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Center(child: Logo(height: 70)),
      const SizedBox(height: 20),
      Card(child: ListTile(
        leading: const Icon(Icons.person),
        title: const Text('Oturum açık'),
        subtitle: Text(appState.currentUser?.email ?? ''),
      )),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: () => appState.signOut(),
        icon: const Icon(Icons.logout),
        label: const Text('Çıkış Yap'),
      ),
    ]));
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});
  @override
  Widget build(BuildContext context) {
    final today = dateNow();
    final todayRecords = appState.records.where((r) => r['date'] == today).toList();
    final active = todayRecords.where((r) => r['status'] == 'Üretimde').length;
    final setup = todayRecords.where((r) => r['status'] == 'Ayar Dönülüyor').length;
    final broken = todayRecords.where((r) => ['Arızalı', 'Parça Kırdı'].contains(r['status'])).length;
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Center(child: Logo(height: 70)),
      const SizedBox(height: 10),
      Text('Günlük Üretim Özeti', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      Text(today, style: Theme.of(context).textTheme.bodyMedium),
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
      Text('Bugünkü Kayıtlar', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      if (todayRecords.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(18), child: Text('Bugün henüz kayıt bulunmuyor.'))),
      ...todayRecords.map((r) => Card(child: ListTile(
        leading: CircleAvatar(child: Text(r['machine'].toString().replaceAll('Makine ', '').replaceAll('Spanzet ', ''))),
        title: Text(r['machine']),
        subtitle: Text('${r['product']} • ${r['shift']} • ${r['operator']}'),
        trailing: Text(r['status'] == 'Üretimde' ? '${fmtKg((r['kg'] as num).toDouble())} kg' : r['status'], textAlign: TextAlign.end),
      ))),
    ]));
  }
  Widget _stat(String t, int n, Color c) => Card(child: Padding(padding: const EdgeInsets.symmetric(vertical: 14), child: Column(children: [
    Text('$n', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: c)), Text(t, style: const TextStyle(fontSize: 12))
  ])));
}

class EntryPage extends StatefulWidget {
  const EntryPage({super.key});
  @override
  State<EntryPage> createState() => _EntryPageState();
}

class _EntryPageState extends State<EntryPage> {
  String machine = 'Makine 1', product = products.first['name'] as String, operator = operators.first, shift = 'Gündüz', status = 'Üretimde';
  final qty = TextEditingController();
  final note = TextEditingController();
  bool saving = false;

  List<String> get machines => [...List.generate(22, (i) => 'Makine ${i + 1}'), '10 mm Spanzet', '12 mm Spanzet'];
  List<Map<String, dynamic>> get availableProducts {
    if (machine == '10 mm Spanzet') return products.where((p) => p['name'] == '10 mm Spanzet').toList();
    if (machine == '12 mm Spanzet') return products.where((p) => p['name'] == '12 mm Spanzet').toList();
    return products.where((p) => p['name'] != '10 mm Spanzet' && p['name'] != '12 mm Spanzet').toList();
  }
  double get gram => (availableProducts.firstWhere((p) => p['name'] == product, orElse: () => availableProducts.first)['gram'] as num).toDouble();

  Future<void> save() async {
    final date = dateNow();
    final p = availableProducts.firstWhere((p) => p['name'] == product);
    final q = int.tryParse(qty.text.replaceAll('.', '').replaceAll(',', '')) ?? 0;
    if (status == 'Üretimde' && q <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Üretim adedini girin.')));
      return;
    }
    final kg = status == 'Üretimde' ? q * gram / 1000 : 0;
    setState(() => saving = true);
    try {
      await appState.add({
        'date': date, 'machine': machine, 'product': p['name'], 'gram': p['gram'],
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
    if (!list.any((p) => p['name'] == product)) product = list.first['name'];
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Logo(height: 52), const SizedBox(height: 10),
      Text('Üretim Girişi', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 16),
      _dd('Makine / Bölüm', machine, machines, (v) => setState(() => machine = v!)),
      _dd('Ürün', product, list.map((p) => p['name'] as String).toList(), (v) => setState(() => product = v!)),
      Card(child: ListTile(title: const Text('Gramaj'), subtitle: Text('${gram.toStringAsFixed(2)} g / bakla'), leading: const Icon(Icons.scale_outlined))),
      _dd('Vardiya', shift, shifts, (v) => setState(() => shift = v!)),
      _dd('Operatör', operator, operators, (v) => setState(() => operator = v!)),
      _dd('Durum', status, statuses, (v) => setState(() => status = v!)),
      if (status == 'Üretimde') ...[
        TextField(controller: qty, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Üretilen bakla adedi', border: OutlineInputBorder())),
        const SizedBox(height: 10),
        if ((int.tryParse(qty.text.replaceAll('.', '').replaceAll(',', '')) ?? 0) > 0)
          Card(child: ListTile(title: const Text('Otomatik hesap'), subtitle: Text('${fmtKg((int.parse(qty.text.replaceAll('.', '').replaceAll(',', '')) * gram) / 1000)} kg  •  ${fmtTon((int.parse(qty.text.replaceAll('.', '').replaceAll(',', '')) * gram) / 1000)} ton'))),
      ],
      TextField(controller: note, maxLines: 2, decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', border: OutlineInputBorder())),
      const SizedBox(height: 16),
      FilledButton.icon(onPressed: saving ? null : save, icon: const Icon(Icons.save), label: Padding(padding: const EdgeInsets.all(12), child: Text(saving ? 'KAYDEDİLİYOR...' : 'KAYDET'))),
    ]));
  }
  Widget _dd(String label, String value, List<String> items, ValueChanged<String?> onChanged) => Padding(
    padding: const EdgeInsets.only(bottom: 10), child: DropdownButtonFormField<String>(
      value: value, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(), onChanged: onChanged));
}

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});
  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final names = products.map((p) => p['name'] as String).where((n) => n.toLowerCase().contains(query.toLowerCase())).toList();
    return SafeArea(child: ListView(padding: const EdgeInsets.all(18), children: [
      const Logo(height: 52), const SizedBox(height: 8),
      Text('Ürün Üretim Raporu', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      TextField(onChanged: (v) => setState(() => query = v), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Ürün ara', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      const Text('İlk üretim tarihinden bugüne toplam üretim', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      ...names.map((name) {
        final kg = appState.totalKgForProduct(name);
        final d = appState.firstDateForProduct(name);
        final gram = (products.firstWhere((p) => p['name'] == name)['gram'] as num).toDouble();
        final qty = kg * 1000 / gram;
        return Card(child: ListTile(
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('İlk üretim: ${d == null ? "—" : d.toIso8601String().substring(0, 10)}\nToplam bakla: ${qty.toStringAsFixed(0)}'),
          trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('${fmtKg(kg)} kg', style: const TextStyle(fontWeight: FontWeight.bold)),
            Text('${fmtTon(kg)} ton')
          ]),
        ));
      })
    ]));
  }
}
