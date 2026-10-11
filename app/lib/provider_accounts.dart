import 'package:content_sources/content_sources.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:ui/ui.dart';
import 'package:url_launcher/url_launcher.dart';

/// Settings → Providers: the free providers, then the paid ones with their
/// sign-in and Buy pages (owner 2026-10-10). Sessions are the files the
/// providers already read, so a sign-in applies to the next lookup.
Widget providersPage({
  required ThirtyNamaProvider thirtyNama,
  required DigiMoviezProvider digiMoviez,
  required MovieJavanAccount movieJavan,
  required AppLogger logger,
}) => ProvidersScreen(
  load: () async => <UiProviderAccount>[
    const UiProviderAccount(id: 'ccloud', name: 'CCloud'),
    const UiProviderAccount(id: 'playtorrio_direct', name: 'Playtorrio Direct'),
    const UiProviderAccount(id: 'torrents', name: 'Torrents'),
    UiProviderAccount(
      id: 'thirtynama',
      name: '30nama',
      login: UiProviderLogin.qr,
      buyUrl: Uri.parse('https://30nama.com/pricing'),
      loggedIn: await thirtyNama.signedIn,
    ),
    UiProviderAccount(
      id: 'digimoviez',
      name: 'DigiMoviez',
      login: UiProviderLogin.credentials,
      buyUrl: Uri.parse('https://digimoviez.com/account/register'),
      loggedIn: await digiMoviez.signedIn,
    ),
    UiProviderAccount(
      id: 'moviejavan',
      name: 'MovieJavan',
      login: UiProviderLogin.credentials,
      buyUrl: Uri.parse('https://moviejavan.com'),
      loggedIn: await movieJavan.signedIn,
    ),
  ],
  onCredentials: (id, user, password) async {
    try {
      if (id == 'moviejavan') {
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
    _ => digiMoviez.signOut(),
  },
  // Outside the app, in the default browser (owner 2026-10-10).
  onBuy: (url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      logger.warn('Could not open $url in the browser');
    }
  },
);
