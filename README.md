# Kontak

Honda Forza için yazılmış, kişisel kullanımlık iPhone sürüş takip uygulaması.

## Özellikler (v0.1)
- **Sürüş kaydı:** Arka planda saniyede bir GPS noktası; mesafe, süre, hareket/durma süresi, ortalama ve azami hız, tırmanış, durak sayısı, sert fren ve sert hızlanma.
- **Hız dağılımı:** Mesafenin hangi kısmının hangi hız aralığında gidildiği (0–30, 30–60, 60–90, 90–120, 120+ km/h).
- **Renkli rota:** Geçmişteki her sürüşün haritası hıza göre renklendirilir.
- **Paylaşım kartı:** Instagram story boyutunda (1080×1920) özet kartı.
- **Haftalık / aylık özet:** Toplam km ve hız dağılımı.
- **Otomatik kayıt (isteğe bağlı):** 20 km/h'yi geçince başlar, 5 dakika durunca biter.
- **Kurtarma:** Uygulama sürüş ortasında kapanırsa kaydedilen kısım bir sonraki açılışta kurtarılır.

Veriler yalnızca telefonda saklanır, hiçbir sunucuya gönderilmez.

## Kurulum (Windows + Sideloadly)
1. [Releases](../../releases/latest) sayfasından `Kontak.ipa` dosyasını indir.
2. iPhone'u bilgisayara bağla, Sideloadly'yi aç, `.ipa`'yı sürükle, Apple ID'ni yaz ve **Start**'a bas.
3. iPhone'da **Ayarlar → Genel → VPN ve Aygıt Yönetimi**'nden profile **Güven** de.
4. Uygulamayı aç ve konum iznini ver. Otomatik kayıt için izni **Her Zaman** yap.

Ücretsiz Apple ID ile yüklenen uygulama 7 gün sonra açılmaz; aynı adımlarla yeniden yükle, sürüşlerin silinmez.

## Geliştirme
`main` dalına her gönderimde GitHub Actions uygulamayı derler ve yeni `Kontak.ipa`'yı Releases'a koyar. Proje [XcodeGen](https://github.com/yonaskolb/XcodeGen) ile üretilir (`project.yml`).
