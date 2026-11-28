# GenoTV

**One app for movies and TV, built for the Iranian community.**

[Install](#install-genotv) · [Content policy](#content-policy-and-lawful-use) · [Build from source](#build-from-source) · [Roadmap](#roadmap) · [فارسی](#فارسی)

## Why GenoTV?

Iranian streaming services have different catalogs and strengths, but many only offer a website or an app for a few devices. Viewers end up juggling apps, and independent developers keep rebuilding the same player and device support. GenoTV brings multiple services into one open-source app so the community can work on those problems together.

## Watch with GenoTV

Browse and search for movies and series in an English or Persian interface, then choose an available source. Free sources include **CCloud**, **Torrentio**, and **public torrents**. To watch through **MovieJavan**, **DigiMoviez**, or **30nama**, select your provider and sign in with your existing account. An active subscription may be required. The available titles and streams depend on the source. You can also play direct links and magnets, stream torrents while they download, and cast to compatible devices.

## Content policy and lawful use

**GenoTV does not host copyrighted movies, TV episodes, or other third-party video streams, and it will never operate a hosting service for them.** GenoTV is a streaming client for watching videos you’re entitled to access from official providers. The provider supplies the stream and controls access through its own terms, accounts, and subscriptions.

GenoTV is not intended for piracy or copyright infringement. A title appearing in search or a source being technically playable does not grant permission to watch, download, or share it. Before using GenoTV, check the laws in your jurisdiction and your provider’s terms. Use official sources and stream, download, or share video only when you have the rights or permission to do so.

## For streaming providers

**Bring your catalog to GenoTV.** Connect a public catalog or let subscribers sign in with the accounts they already use. Your catalog and account system can stay on your own servers. Smaller providers can reach more viewers without building and maintaining a separate app for every platform.

**Build an app under your own brand.** Fork GenoTV, reuse the playback engine, and make the interface and branding your own. If you improve something other providers or viewers could use, send a pull request so the main project can benefit too.

## Install GenoTV

Open **Releases** on the repository’s GitHub page. Once a build is published for your device, choose its file under **Assets**.

| Device | How to install |
| --- | --- |
| Windows | Extract `GenoTV-windows.zip` and run GenoTV from the extracted folder. |
| macOS | Extract `GenoTV-macos.zip` and move **GenoTV.app** to **Applications**. |
| Android and Android TV | Open `GenoTV-android.apk` on your device. On Android TV, transfer the APK to the TV first. Android may ask you to allow installation from the app you opened it with. |
| iPhone, iPad and Apple TV | The iOS and tvOS workflow produces unsigned IPAs. They need to be signed before installation on a device. |

## Build from source

1. Clone this repository and install the [Flutter SDK](https://docs.flutter.dev/install). Use the version pinned in the release workflow.
2. Set up your target’s toolchain. Use Xcode and CocoaPods for Apple builds, the Android SDK and JDK 17 for Android, or Visual Studio with **Desktop development with C++** for Windows. Run `flutter doctor` to check your setup.
3. Prepare any missing native libraries using the matching job in the release workflow. It lists the tools and build steps for the playback, downloading, torrent, and casting libraries.
4. From the repository root, run:

   ```bash
   cd app
   flutter pub get
   flutter devices
   flutter run -d <device-id>
   ```

For a release build, follow the matching workflow job. Apple TV uses the [Flutter tvOS fork](https://github.com/fluttertv/flutter-tvos) and its `flutter-tvos` command. Use your own signing credentials when packaging for distribution.

## Roadmap

- [ ] Linux support
- [ ] Samsung TV support through Tizen
- [ ] More streaming providers
- [ ] Lightweight version for older devices

Issues and pull requests are welcome, including device compatibility reports, provider integrations, and improvements to Persian translations.

## License

GenoTV is licensed under the GNU General Public License v3.0. You can use, modify, rebrand, and sell it. If you distribute a modified version, you must make its corresponding source code available to recipients under GPL-3.0. Bundled third-party components retain their respective licenses.

## فارسی

<div dir="rtl">

<p><strong>یک برنامه برای تماشای فیلم و سریال، ساخته‌شده برای جامعهٔ ایرانی.</strong></p>

<h3>چرا گنو تیوی؟</h3>

<p>سرویس‌های پخش ایرانی هر کدام مجموعه و ویژگی‌های خودشان را دارند، اما خیلی از آن‌ها فقط وب‌سایت دارند یا برنامه‌شان روی چند دستگاه محدود اجرا می‌شود. کاربران مجبورند بین چند برنامه جابه‌جا شوند و توسعه‌دهندگان مستقل بارها پخش‌کننده و امکانات مشابهی می‌سازند. گنو تیوی چند سرویس را در یک برنامهٔ متن‌باز کنار هم می‌آورد تا همه بتوانند برای بهتر کردن تجربهٔ تماشا روی یک پروژه کار کنند.</p>

<h3>تماشا با گنو تیوی</h3>

<p>در رابط فارسی یا انگلیسی دنبال فیلم و سریال بگردید و یکی از منابع موجود را برای پخش انتخاب کنید. <strong>CCloud، Torrentio و تورنت‌های عمومی</strong> از منابع رایگان‌اند. برای استفاده از <strong>مووی‌جوان، دیجی‌موویز و سی‌نما</strong>، سرویس موردنظر را انتخاب کنید و با حساب فعلی‌تان وارد شوید. ممکن است به اشتراک فعال نیاز داشته باشید. فیلم‌ها، سریال‌ها و گزینه‌های پخش به منبع انتخابی بستگی دارند. می‌توانید لینک مستقیم یا مگنت را هم باز کنید، تورنت را هم‌زمان با دانلود تماشا کنید و تصویر را به دستگاه‌های سازگار بفرستید.</p>

<h3>سیاست محتوا و استفادهٔ قانونی</h3>

<p><strong>گنو تیوی هیچ فیلم، قسمت سریال یا جریان ویدیویی متعلق به دیگران و تحت حمایت حق نشر را میزبانی نمی‌کند و هرگز سرویس میزبانی برای این محتوا راه‌اندازی نخواهد کرد.</strong> گنو تیوی برنامه‌ای برای تماشای ویدیوهایی است که حق دسترسی به آن‌ها را از طریق سرویس‌های رسمی دارید. پخش از طرف خود سرویس ارائه می‌شود و شرایط استفاده، حساب کاربری و اشتراک را همان سرویس تعیین می‌کند.</p>

<p>گنو تیوی برای تماشای غیرمجاز یا نقض حق نشر ساخته نشده است. پیدا شدن یک عنوان در جست‌وجو یا امکان پخش یک منبع به شما اجازهٔ تماشا، دانلود یا انتشار آن را نمی‌دهد. پیش از استفاده، قوانین محل زندگی‌تان و شرایط استفادهٔ سرویس را بررسی کنید. از منابع رسمی استفاده کنید و فقط زمانی ویدیو را پخش، دانلود یا منتشر کنید که حق یا اجازهٔ انجام آن را دارید.</p>

<h3>برای سرویس‌های پخش</h3>

<p><strong>مجموعهٔ خود را به گنو تیوی اضافه کنید.</strong> می‌توانید فهرست عمومی فیلم‌ها و سریال‌هایتان را متصل کنید یا به مشترکان اجازه دهید با حسابی که از قبل دارند وارد شوند. فهرست محتوا و سامانهٔ حساب‌ها می‌تواند روی سرورهای خودتان بماند. این‌طوری سرویس‌های کوچک‌تر هم می‌توانند بدون ساخت و نگهداری یک برنامهٔ جداگانه برای هر سیستم‌عامل، به کاربران بیشتری دسترسی پیدا کنند.</p>

<p><strong>برنامه‌ای با نام و ظاهر خودتان بسازید.</strong> از گنو تیوی یک فورک بگیرید، موتور پخش آن را نگه دارید و لوگو و رابط کاربری خودتان را جایگزین کنید. اگر تغییری دادید که برای کاربران یا سرویس‌های دیگر هم مفید است، با یک پول ریکوئست آن را به پروژهٔ اصلی پیشنهاد دهید.</p>

<h3>نصب گنو تیوی</h3>

<p>در صفحهٔ گیت‌هاب پروژه بخش <bdi>Releases</bdi> را باز کنید. پس از انتشار نسخهٔ مناسب دستگاهتان، فایل آن را از قسمت <bdi>Assets</bdi> بگیرید.</p>

<ul>
<li><strong>ویندوز:</strong> فایل <code dir="ltr">GenoTV-windows.zip</code> را از حالت فشرده خارج کنید و گنو تیوی را از همان پوشه اجرا کنید.</li>
<li><strong>مک:</strong> فایل <code dir="ltr">GenoTV-macos.zip</code> را از حالت فشرده خارج کنید و <bdi>GenoTV.app</bdi> را به پوشهٔ <bdi>Applications</bdi> ببرید.</li>
<li><strong>اندروید و اندروید تی‌وی:</strong> فایل <code dir="ltr">GenoTV-android.apk</code> را روی دستگاه باز و نصب کنید. برای اندروید تی‌وی ابتدا فایل را به تلویزیون منتقل کنید. ممکن است اندروید برای برنامه‌ای که فایل را با آن باز می‌کنید اجازهٔ نصب بخواهد.</li>
<li><strong>آیفون، آیپد و اپل تی‌وی:</strong> فرایند ساخت نسخه‌های iOS و tvOS فایل‌های IPA بدون امضا تولید می‌کند. این فایل‌ها برای نصب روی دستگاه باید امضا شوند.</li>
</ul>

<h3>ساخت از کد منبع</h3>

<ol>
<li>مخزن را کلون کنید و <a href="https://docs.flutter.dev/install">Flutter</a> را با نسخه‌ای که در گردش‌کار انتشار مشخص شده، نصب کنید.</li>
<li>ابزارهای سیستم‌عامل مقصد را آماده کنید. برای اپل به Xcode و CocoaPods، برای اندروید به Android SDK و JDK 17 و برای ویندوز به Visual Studio با ابزارهای ساخت دسکتاپ C++ نیاز دارید. با <code>flutter doctor</code> وضعیت ابزارها را بررسی کنید.</li>
<li>اگر کتابخانه‌های بومی پخش، دانلود، تورنت یا ارسال تصویر به تلویزیون آماده نیستند، طبق مراحل سیستم‌عامل مقصد در گردش‌کار انتشار آن‌ها را بسازید.</li>
<li>از ریشهٔ مخزن این دستورها را اجرا کنید:</li>
</ol>

<pre dir="ltr"><code>cd app
flutter pub get
flutter devices
flutter run -d &lt;device-id&gt;</code></pre>

<p>برای ساخت نسخهٔ انتشار، مراحل سیستم‌عامل مقصد را در گردش‌کار انتشار دنبال کنید. ساخت نسخهٔ اپل تی‌وی به <a href="https://github.com/fluttertv/flutter-tvos">فورک Flutter برای tvOS</a> و دستور <code>flutter-tvos</code> نیاز دارد. برای انتشار، از اطلاعات امضای خودتان استفاده کنید.</p>

<h3>نقشهٔ راه</h3>

<ul>
<li>پشتیبانی از لینوکس</li>
<li>پشتیبانی از تلویزیون‌های سامسونگ با Tizen</li>
<li>افزودن سرویس‌های پخش بیشتر</li>
<li>نسخهٔ سبک برای دستگاه‌های قدیمی‌تر</li>
</ul>

<p>از گزارش مشکلات سازگاری با دستگاه‌ها، پیشنهاد اتصال سرویس‌های جدید و پول ریکوئست برای بهبود ترجمهٔ فارسی استقبال می‌کنیم.</p>

<h3>مجوز</h3>

<p>گنو تیوی تحت مجوز GNU GPL نسخهٔ ۳ منتشر می‌شود. می‌توانید از آن استفاده کنید، تغییرش دهید، با نام خودتان عرضه کنید و بفروشید. اگر نسخهٔ تغییریافته‌ای را توزیع می‌کنید، باید کد منبع متناظر را با همین مجوز در اختیار دریافت‌کنندگان بگذارید. اجزای شخص ثالث با مجوزهای خودشان عرضه می‌شوند.</p>

</div>

## Acknowledgments · سپاسگزاری

- **App and interface / برنامه و رابط کاربری** — [Flutter](https://flutter.dev), [Dart](https://dart.dev), [Phosphor Icons](https://github.com/phosphor-icons/phosphor-flutter), [Thinking Orbs](https://pub.dev/packages/flutter_thinking_orbs), [Flutter Animate](https://pub.dev/packages/flutter_animate), [Animations](https://pub.dev/packages/animations), [Skeletonizer](https://pub.dev/packages/skeletonizer), [Drift](https://drift.simonbinder.eu), [Shamsi Date](https://pub.dev/packages/shamsi_date), [Intl](https://pub.dev/packages/intl), [qr_flutter](https://pub.dev/packages/qr_flutter), [file_selector](https://pub.dev/packages/file_selector), [url_launcher](https://pub.dev/packages/url_launcher), [wakelock_plus](https://pub.dev/packages/wakelock_plus), [path_provider](https://pub.dev/packages/path_provider), [Inter](https://rsms.me/inter/).
- **Playback and subtitles / پخش و زیرنویس** — [media_kit](https://github.com/media-kit/media-kit), [mpv](https://github.com/mpv-player/mpv), [FFmpeg](https://ffmpeg.org), [libass](https://github.com/libass/libass), [HarfBuzz](https://github.com/harfbuzz/harfbuzz), [FriBidi](https://github.com/fribidi/fribidi), [Mbed TLS](https://github.com/Mbed-TLS/mbedtls), [media_kit’s Darwin builds](https://github.com/media-kit/libmpv-darwin-build), [Android builds](https://github.com/media-kit/libmpv-android-video-build), [Android helper](https://github.com/media-kit/media-kit-android-helper), [fftools-ffi](https://github.com/moffatman/fftools-ffi), [Kodi](https://kodi.tv) (playback reference / مرجع پخش).
- **Transport, sources and casting / دریافت، منابع و ارسال تصویر** — [aria2](https://aria2.github.io), [libtorrent](https://libtorrent.org), [Boost](https://www.boost.org), [OpenSSL](https://www.openssl.org), [PlayTorrio V3](https://github.com/ayman708-UX/PlayTorrioV3), [Flyx](https://github.com/Vynx-Velvet/Flyx-main), [dart_cast](https://github.com/abdelaziz-mahdy/dart_cast), [TMDB](https://www.themoviedb.org), [OMDb](https://www.omdbapi.com).
