# Baş Zincir — MVP

Bu paket, verilen zincir/gramaj Excel'i ve Baş Zincir logosu temel alınarak hazırlanmış ilk mobil uygulama prototipidir.

## İçerik
- 22 makine + 10 mm Spanzet + 12 mm Spanzet
- Excel'deki 51 ürün ve gramajları
- 10 operatör
- Gündüz / Gece vardiyası
- Üretimde, Ayar Dönülüyor, Arızalı, Parça Kırdı, Bakımda, Diğer durumları
- Bakla adedinden otomatik kg/ton hesabı
- Günlük özet
- Ürün bazında ilk üretim tarihinden bugüne kümülatif kg/ton ve bakla
- Yerel cihazda kayıt

## Önemli
Bu sürüm artık Firebase (Cloud Firestore + Authentication) ile çalışır. Uygulamayı açan herkes aynı verileri gerçek zamanlı görür. Sadece `lib/firebase_options.dart` içindeki 5 değeri kendi Firebase projenizden almanız ve doldurmanız gerekir — adımlar Claude ile olan sohbette anlatılmıştır.

Yönetici (üretim verisi giren kişi) Firebase Authentication'da oluşturulan e-posta/şifre ile "Yönetici Girişi" sekmesinden giriş yapar. Patron ve pazarlamacılar giriş yapmadan doğrudan Özet ve Raporlar sekmelerini görebilir.

## Android APK
Flutter SDK kurulu bir bilgisayarda:
```bash
flutter pub get
flutter build apk --release
```
APK:
`build/app/outputs/flutter-apk/app-release.apk`

## iPhone
macOS + Xcode üzerinde:
```bash
flutter pub get
flutter build ios --release
```

## Sonraki geliştirme
1. Firebase/Supabase kullanıcı girişi
2. Yönetici / Üretim / Patron / Pazarlama rolleri
3. Bulut senkronizasyonu
4. PDF ve Excel raporu
5. Ürün değişim geçmişi ve hedef tonaj
6. Arıza/ayar süreleri
7. Eski Excel kayıtlarının içe aktarılması
