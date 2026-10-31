import 'dart:io' show Platform;
import 'package:content_sources/content_sources.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:ui/ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings → Providers: the free providers, then the paid ones with their
/// sign-in and Buy pages (owner 2026-10-10). Sessions are the files the
/// providers already read, so a sign-in applies to the next lookup.
Future<void> restoreProviderAccounts({
  required ThirtyNamaProvider thirtyNama,
  required DigiMoviezProvider digiMoviez,
  required MovieJavanAccount movieJavan,
}) async {
  await Future.wait([
    thirtyNama.signedIn,
    digiMoviez.signedIn,
    movieJavan.signedIn,
  ]);
}

String _domainOf(DomainSettings domains, String id, String builtIn) =>
    (domains.provider(id) ?? Uri.parse(builtIn)).toString();

/// Runs a domain save; a rejected input becomes the code the editor shows as
/// its en/fa message; the old value stays.
Future<String?> saveDomain(Future<void> Function() save) async {
  try {
    await save();
    return null;
  } on FormatException {
    return 'domain.invalid';
  }
}

/// Settings > Title API (phase 14).
Widget titleApiPage(DomainSettings domains) => TitleApiScreen(
  load: () => [
    for (final e in domains.titleApi())
      UiTitleApiEntry(
        id: e.id,
        name: switch (e.id) {
          'tmdb' => 'TMDB',
          'proxy' => 'Backup proxy',
          'ccloud' => 'CCloud',
          'moviejavan' => 'MovieJavan',
          _ => e.id,
        },
        domain: e.current.toString(),
      ),
  ],
  onReorder: domains.reorderTitle,
  onDomain: (id, raw) => saveDomain(() => domains.setTitleDomain(id, raw)),
  onReset: domains.resetTitle,
);

Widget providersPage({
  required ThirtyNamaProvider thirtyNama,
  required DigiMoviezProvider digiMoviez,
  required MovieJavanAccount movieJavan,
  required SubtitleAccounts subtitles,
  required AppLogger logger,
  required DomainSettings domains,
  Future<void>? restored,
}) => ProvidersScreen(
  buyAsQr: Platform.operatingSystem == 'tvos',
  onDomain: (id, raw) => saveDomain(() => domains.setProvider(id, raw)),
  load: () async {
    await restored;
    return <UiProviderAccount>[
      UiProviderAccount(
        id: 'ccloud',
        name: 'CCloud',
        domain: _domainOf(domains, 'ccloud', 'https://server-hi-speed-iran.info'),
      ),
      const UiProviderAccount(
        id: 'playtorrio_direct',
        name: 'Playtorrio Direct',
      ),
      const UiProviderAccount(id: 'torrents', name: 'Torrents'),
      UiProviderAccount(
        id: 'thirtynama',
        name: '30nama',
        login: UiProviderLogin.qr,
        buyUrl: Uri.parse('https://30nama.com/pricing'),
        loggedIn: await thirtyNama.signedIn,
        domain: _domainOf(domains, 'thirtynama', 'https://interface.30nama.com'),
      ),
      UiProviderAccount(
        id: 'digimoviez',
        name: 'DigiMoviez',
        login: UiProviderLogin.credentials,
        buyUrl: Uri.parse('https://digimoviez.com/account/register'),
        loggedIn: await digiMoviez.signedIn,
        domain: _domainOf(domains, 'digimoviez', 'https://digimoviez.com'),
      ),
      UiProviderAccount(
        id: 'moviejavan',
        name: 'MovieJavan',
        login: UiProviderLogin.credentials,
        buyUrl: Uri.parse('https://moviejavan.com'),
        loggedIn: await movieJavan.signedIn,
        domain: _domainOf(domains, 'moviejavan', 'http://cdntmp.dnstmp10.q5eapp.ir'),
      ),
      for (final (id, name, login, url) in [
        (
          SubtitleAccounts.subdl,
          'SubDL',
          UiProviderLogin.apiKey,
          'https://subdl.com/panel/api',
        ),
        (
          SubtitleAccounts.subsource,
          'SubSource',
          UiProviderLogin.apiKey,
          'https://subsource.net',
        ),
        (
          SubtitleAccounts.openSubtitles,
          'OpenSubtitles',
          UiProviderLogin.credentials,
          'https://www.opensubtitles.com/en/users/sign_up',
        ),
      ])
        UiProviderAccount(
          id: id,
          name: '$name (subtitles)',
          login: login,
          buyUrl: Uri.parse(url),
          loggedIn: await subtitles.signedIn(id),
        ),
    ];
  },
  onCredentials: (id, user, password) async {
    try {
      if (id == SubtitleAccounts.openSubtitles) {
        await subtitles.signInOpenSubtitles(user, password);
      } else if (id == SubtitleAccounts.subdl ||
          id == SubtitleAccounts.subsource) {
        await subtitles.saveKey(id, user);
      } else if (id == 'moviejavan') {
        await movieJavan.signIn(user, password);
      } else {
        await digiMoviez.signIn(user, password);
      }
      return null;
    } on ContentSourceFailure catch (error) {
      logger.warn('$id sign-in failed: ${error.code}');
      return error.message;
    }
  },
  onStartQr: (_) async {
    final login = await thirtyNama.startQrLogin();
    return UiQrLogin(code: login.code, url: login.url);
  },
  onPollQr: (_, login) => thirtyNama.pollQrLogin(login.code),
  onLogout: (id) => switch (id) {
    'thirtynama' => thirtyNama.signOut(),
    'moviejavan' => movieJavan.signOut(),
    SubtitleAccounts.subdl ||
    SubtitleAccounts.subsource ||
    SubtitleAccounts.openSubtitles => subtitles.signOut(id),
    _ => digiMoviez.signOut(),
  },
  // Outside the app, in the default browser (owner 2026-10-10).
  onBuy: (url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      logger.warn('Could not open $url in the browser');
    }
  },
);
