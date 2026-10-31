import '../l10n_gen/app_strings.dart';
import '../l10n/app_text.dart';
import '../components/app_dialog.dart';
import '../components/app_button.dart';
import '../navigation/page_top_inset.dart';
import '../platform/adaptive_behavior.dart';

import 'dart:async';

import 'domain_editor.dart';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../components/ambient_background.dart';
import '../components/app_chip.dart';
import '../components/buy_button.dart';
import '../components/app_text_field.dart';
import '../components/orb_loader.dart';
import '../components/tinted_surface.dart';
import '../navigation/page_back_button.dart';
import '../theme/rivulet_tokens.dart';

/// How a provider signs in.
enum UiProviderLogin {
  /// Free: nothing to sign in to.
  none,

  /// Username and password.
  credentials,

  /// A single personal API key.
  apiKey,

  /// Scan a code with a device already signed in.
  qr,

  /// The provider sells accounts but the app cannot sign in to it yet.
  unavailable,
}

class UiProviderAccount {
  const UiProviderAccount({
    required this.id,
    required this.name,
    this.login = UiProviderLogin.none,
    this.buyUrl,
    this.loggedIn = false,
    this.domain,
    this.domainCustom = false,
    this.signUp = false,
  });

  final String id;
  final String name;
  final UiProviderLogin login;

  /// The provider's own page for buying an account.
  final Uri? buyUrl;
  final bool loggedIn;

  /// The link is for signing up to a free account, not buying one.
  final bool signUp;

  /// The provider's main API domain in use (null: this provider has none).
  final String? domain;
  final bool domainCustom;

  bool get free => login == UiProviderLogin.none;
}

/// A QR sign-in in progress: [url] is what the QR encodes, [code] the same
/// code for typing in by hand.
class UiQrLogin {
  const UiQrLogin({required this.code, required this.url});

  final String code;
  final Uri url;
}

/// Settings → Providers: every provider, free ones first with a Free tag;
/// the others with sign-in and a Buy link (owner 2026-10-10).
class ProvidersScreen extends StatefulWidget {
  const ProvidersScreen({
    required this.load,
    required this.onCredentials,
    required this.onStartQr,
    required this.onPollQr,
    required this.onLogout,
    required this.onBuy,
    this.buyAsQr = false,
    this.onDomain,
    super.key,
  });

  /// Saves a provider's domain (null/empty = built-in); returns an error
  /// message, or null when saved.
  final Future<String?> Function(String id, String? raw)? onDomain;

  final Future<List<UiProviderAccount>> Function() load;

  /// Returns an error message, or null when signed in.
  final Future<String?> Function(String id, String user, String password)
  onCredentials;
  final Future<UiQrLogin> Function(String id) onStartQr;

  /// True once the code was approved and the session saved.
  final Future<bool> Function(String id, UiQrLogin login) onPollQr;
  final Future<void> Function(String id) onLogout;
  final Future<void> Function(Uri url) onBuy;

  /// No browser on this platform (tvOS): Buy shows the link as a QR code and short URL instead.
  final bool buyAsQr;

  @override
  State<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends State<ProvidersScreen> {
  late Future<List<UiProviderAccount>> _accounts = widget.load();

  void _reload() => setState(() {
    _accounts = widget.load();
  });

  Future<void> _login(UiProviderAccount account) async {
    final done = account.login == UiProviderLogin.qr
        ? await showAppDialog<bool>(
            context: context,
            builder: (_) => _QrDialog(
              name: account.name,
              start: () => widget.onStartQr(account.id),
              poll: (login) => widget.onPollQr(account.id, login),
            ),
          )
        : await showAppDialog<bool>(
            context: context,
            builder: (_) => _CredentialsDialog(
              name: account.name,
              keyOnly: account.login == UiProviderLogin.apiKey,
              submit: (user, password) =>
                  widget.onCredentials(account.id, user, password),
            ),
          );
    if (done == true && mounted) _reload();
  }

  Future<void> _domain(UiProviderAccount account) async {
    final saved = await showDomainDialog(
      context,
      title: '${account.name} - ${AppStrings.of(context).domain_label}',
      current: account.domain ?? '',
      save: (raw) => widget.onDomain!(account.id, raw),
    );
    if (saved == true && mounted) _reload();
  }

  Future<void> _logout(UiProviderAccount account) async {
    await widget.onLogout(account.id);
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) {
    final sizes = AdaptiveBehavior.sizesOf(context);
    final gutter = RivuletSpacing.gutterOf(context);
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            ListView(
              key: const ValueKey<String>('providers-list'),
              padding: EdgeInsets.fromLTRB(
                gutter,
                pageTopInsetOf(context),
                gutter,
                gutter,
              ),
              children: [
                Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: sizes.settingsContentMaxWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        AppText(
                          AppStrings.of(context).settings_providers,
                          style: RivuletTokens.of(context).typeStyles.title,
                        ),
                        SizedBox(
                          height: RivuletSpacing.rowGap(
                            AdaptiveBehavior.formFactorOf(context),
                          ),
                        ),
                        FutureBuilder<List<UiProviderAccount>>(
                          future: _accounts,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return AppText(
                                '${snapshot.error}',
                                style: RivuletTokens.of(context).typeStyles.body
                                    .copyWith(
                                      color: RivuletTokens.of(context)
                                          .colors
                                          .danger,
                                    ),
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Center(child: OrbLoader.medium());
                            }
                            final accounts = [...snapshot.data!]
                              ..sort(
                                (a, b) =>
                                    (a.free ? 0 : 1).compareTo(b.free ? 0 : 1),
                              );
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (final account in accounts)
                                  Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: RivuletSpacing.s8,
                                    ),
                                    child: _ProviderCard(
                                      account: account,
                                      onLogin: () => _login(account),
                                      onLogout: () => _logout(account),
                                      onDomain:
                                          account.domain == null ||
                                              widget.onDomain == null
                                          ? null
                                          : () => _domain(account),
                                      onBuy: account.buyUrl == null
                                          ? null
                                          : () => openBuyLink(
                                              context,
                                              name: account.name,
                                              url: account.buyUrl!,
                                              onBuy: widget.onBuy,
                                              asQr: widget.buyAsQr,
                                            ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const PageBackButton(),
          ],
        ),
      ),
    );
  }
}

class _ProviderCard extends StatelessWidget {
  const _ProviderCard({
    required this.account,
    required this.onLogin,
    required this.onLogout,
    required this.onBuy,
    required this.onDomain,
  });

  final VoidCallback? onDomain;
  final UiProviderAccount account;
  final VoidCallback onLogin;
  final VoidCallback onLogout;
  final VoidCallback? onBuy;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final styles = tokens.typeStyles;
    final status = switch (account.login) {
      UiProviderLogin.none => AppStrings.of(context).providers_noAccount,
      UiProviderLogin.unavailable => AppStrings.of(
        context,
      ).providers_unavailable,
      _ =>
        account.loggedIn
            ? AppStrings.of(context).providers_signedIn
            : AppStrings.of(context).providers_signedOut,
    };
    return TintedSurface(
      key: ValueKey<String>('provider-card-${account.id}'),
      radius: RivuletRadius.medium,
      padding: const EdgeInsets.all(RivuletSpacing.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Flexible(child: AppText(account.name, style: styles.headline)),
              if (account.free) ...<Widget>[
                const SizedBox(width: RivuletSpacing.s8),
                TintedSurface(
                  key: ValueKey<String>('provider-free-${account.id}'),
                  radius: RivuletRadius.xs,
                  padding: const EdgeInsets.symmetric(
                    horizontal: RivuletSpacing.s8,
                    vertical: RivuletSpacing.s4,
                  ),
                  child: AppText(
                    AppStrings.of(context).providers_free,
                    style: styles.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: tokens.colors.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: RivuletSpacing.s4),
          AppText(status, style: styles.caption),
          if (account.domain != null) ...<Widget>[
            const SizedBox(height: RivuletSpacing.s8),
            Row(
              key: ValueKey<String>('provider-domain-${account.id}'),
              children: <Widget>[
                const Spacer(),
                if (onDomain != null)
                  AppChip(
                    key: ValueKey<String>('provider-domain-edit-${account.id}'),
                    icon: PhosphorIconsRegular.globe,
                    label: AppStrings.of(context).domain_change,
                    onActivate: onDomain,
                  ),
              ],
            ),
          ],
          if (!account.free) ...<Widget>[
            const SizedBox(height: RivuletSpacing.s16),
            Wrap(
              spacing: RivuletSpacing.s8,
              runSpacing: RivuletSpacing.s8,
              children: <Widget>[
                if (account.login == UiProviderLogin.credentials ||
                    account.login == UiProviderLogin.apiKey ||
                    account.login == UiProviderLogin.qr)
                  account.loggedIn
                      ? AppChip(
                          key: ValueKey<String>(
                            'provider-logout-${account.id}',
                          ),
                          icon: PhosphorIconsRegular.signOut,
                          label: AppStrings.of(context).providers_signOut,
                          onActivate: onLogout,
                        )
                      : AppChip(
                          key: ValueKey<String>('provider-login-${account.id}'),
                          icon: account.login == UiProviderLogin.qr
                              ? PhosphorIconsRegular.qrCode
                              : PhosphorIconsRegular.signIn,
                          label: account.login == UiProviderLogin.qr
                              ? AppStrings.of(context).providers_signInQr
                              : AppStrings.of(context).providers_signIn,
                          onActivate: onLogin,
                        ),
                if (onBuy != null && !account.loggedIn)
                  BuyButton(
                    signUp: account.signUp,
                    key: ValueKey<String>('provider-buy-${account.id}'),
                    onActivate: onBuy,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _CredentialsDialog extends StatefulWidget {
  const _CredentialsDialog({
    required this.name,
    required this.submit,
    this.keyOnly = false,
  });

  final String name;
  final bool keyOnly;
  final Future<String?> Function(String user, String password) submit;

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  final _user = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    String? error;
    try {
      error = await widget.submit(_user.text.trim(), _password.text);
    } on Object catch (failure) {
      error = '$failure';
    }
    if (!mounted) return;
    if (error == null) {
      Navigator.pop(context, true);
      return;
    }
    setState(() {
      _busy = false;
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final styles = RivuletTokens.of(context).typeStyles;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppText(
          AppStrings.of(context).providers_signInTo(widget.name),
          style: styles.title,
        ),
        const SizedBox(height: RivuletSpacing.s24),
        AppText(
          widget.keyOnly
              ? AppStrings.of(context).providers_apiKey
              : AppStrings.of(context).providers_username,
          style: styles.label,
        ),
        const SizedBox(height: RivuletSpacing.s8),
        AppTextField(
          key: const ValueKey<String>('provider-user'),
          controller: _user,
          hint: widget.keyOnly
              ? AppStrings.of(context).providers_apiKey
              : AppStrings.of(context).providers_username,
          icon: widget.keyOnly
              ? PhosphorIconsRegular.key
              : PhosphorIconsRegular.user,
          autofocus: true,
          errorText: widget.keyOnly ? _error : null,
          onSubmitted: widget.keyOnly ? (_) => _submit() : null,
        ),
        if (!widget.keyOnly) ...[
          const SizedBox(height: RivuletSpacing.s16),
          AppText(
            AppStrings.of(context).providers_password,
            style: styles.label,
          ),
          const SizedBox(height: RivuletSpacing.s8),
          AppTextField(
            key: const ValueKey<String>('provider-password'),
            controller: _password,
            hint: AppStrings.of(context).providers_password,
            icon: PhosphorIconsRegular.lock,
            obscureText: true,
            errorText: _error,
            onSubmitted: (_) => _submit(),
          ),
        ],
        const SizedBox(height: RivuletSpacing.s24),
        if (_busy) ...[
          const Center(child: OrbLoader.small()),
          const SizedBox(height: RivuletSpacing.s8),
        ],
        Wrap(
          alignment: WrapAlignment.end,
          spacing: RivuletSpacing.s8,
          runSpacing: RivuletSpacing.s8,
          children: [
            AppButton.secondary(
              label: AppStrings.of(context).common_cancel,
              onActivate: () => Navigator.pop(context, false),
            ),
            AppButton.primary(
              key: const ValueKey<String>('provider-submit'),
              label: _busy
                  ? AppStrings.of(context).providers_signingIn
                  : AppStrings.of(context).providers_signIn,
              onActivate: _busy ? null : _submit,
            ),
          ],
        ),
      ],
    );
  }
}

class _QrDialog extends StatefulWidget {
  const _QrDialog({
    required this.name,
    required this.start,
    required this.poll,
  });

  final String name;
  final Future<UiQrLogin> Function() start;
  final Future<bool> Function(UiQrLogin login) poll;

  @override
  State<_QrDialog> createState() => _QrDialogState();
}

class _QrDialogState extends State<_QrDialog> {
  UiQrLogin? _login;
  String? _error;
  Timer? _timer;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    unawaited(_begin());
  }

  Future<void> _begin() async {
    _timer?.cancel();
    setState(() {
      _login = null;
      _error = null;
    });
    try {
      final login = await widget.start();
      if (!mounted) return;
      setState(() => _login = login);
      // The code is valid for 5 minutes (30nama's QR TTL).
      final deadline = DateTime.now().add(const Duration(minutes: 5));
      _timer = Timer.periodic(const Duration(seconds: 3), (timer) async {
        if (_polling) return;
        if (DateTime.now().isAfter(deadline)) {
          timer.cancel();
          setState(() => _error = AppStrings.of(context).providers_codeExpired);
          return;
        }
        _polling = true;
        try {
          if (await widget.poll(login) && mounted) {
            timer.cancel();
            Navigator.pop(context, true);
          }
        } on Object catch (error) {
          timer.cancel();
          if (mounted) setState(() => _error = '$error');
        } finally {
          _polling = false;
        }
      });
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final styles = tokens.typeStyles;
    final login = _login;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppText(
          AppStrings.of(context).providers_signInTo(widget.name),
          style: styles.title,
        ),
        const SizedBox(height: RivuletSpacing.s24),
        if (login != null) ...[
          Center(
            child: QrImageView(
              key: const ValueKey<String>('provider-qr'),
              data: login.url.toString(),
              size: 240,
              backgroundColor: tokens.colors.textPrimary,
              eyeStyle: QrEyeStyle(color: tokens.colors.onAccent),
              dataModuleStyle: QrDataModuleStyle(color: tokens.colors.onAccent),
            ),
          ),
          const SizedBox(height: RivuletSpacing.s16),
          AppText(
            AppStrings.of(context)
                .providers_scanInstructions(widget.name, login.url.toString()),
            style: styles.body.copyWith(color: tokens.colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: RivuletSpacing.s8),
          SelectableText(
            login.code,
            style: styles.headline,
            textAlign: TextAlign.center,
          ),
        ] else if (_error == null)
          const Padding(
            padding: EdgeInsets.all(RivuletSpacing.s16),
            child: OrbLoader.medium(),
          ),
        if (_error case final error?) ...[
          const SizedBox(height: RivuletSpacing.s8),
          AppText(
            error,
            style: styles.caption.copyWith(color: tokens.colors.danger),
          ),
        ],
        const SizedBox(height: RivuletSpacing.s24),
        Wrap(
          alignment: WrapAlignment.end,
          spacing: RivuletSpacing.s8,
          runSpacing: RivuletSpacing.s8,
          children: [
            AppButton.secondary(
              label: AppStrings.of(context).common_cancel,
              onActivate: () => Navigator.pop(context, false),
            ),
            if (_error != null)
              AppButton.primary(
                label: AppStrings.of(context).providers_newCode,
                onActivate: _begin,
              ),
          ],
        ),
      ],
    );
  }
}

/// Opens a provider's buy page in the browser, or as a QR code where there is none (tvOS).
Future<void> openBuyLink(
  BuildContext context, {
  required String name,
  required Uri url,
  required Future<void> Function(Uri url) onBuy,
  required bool asQr,
}) => asQr
    ? showAppDialog<void>(
        context: context,
        builder: (_) => _LinkQrDialog(name: name, url: url),
      )
    : onBuy(url);

/// A link shown as a QR code and a short URL, for platforms that cannot open a browser.
class _LinkQrDialog extends StatelessWidget {
  const _LinkQrDialog({required this.name, required this.url});

  final String name;
  final Uri url;

  @override
  Widget build(BuildContext context) {
    final tokens = RivuletTokens.of(context);
    final styles = tokens.typeStyles;
    final short = '${url.host}${url.path == '/' ? '' : url.path}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppText(
          '${AppStrings.of(context).providers_buy}: $name',
          style: styles.title,
        ),
        const SizedBox(height: RivuletSpacing.s24),
        Center(
          child: QrImageView(
            key: const ValueKey<String>('link-qr'),
            data: url.toString(),
            size: 240,
            backgroundColor: tokens.colors.textPrimary,
            eyeStyle: QrEyeStyle(color: tokens.colors.onAccent),
            dataModuleStyle: QrDataModuleStyle(color: tokens.colors.onAccent),
          ),
        ),
        const SizedBox(height: RivuletSpacing.s16),
        AppText(
          short,
          key: const ValueKey<String>('link-short-url'),
          style: styles.headline,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: RivuletSpacing.s24),
        Align(
          alignment: Alignment.centerRight,
          child: AppButton.primary(
            label: AppStrings.of(context).common_cancel,
            autofocus: true,
            onActivate: () => Navigator.pop(context),
          ),
        ),
      ],
    );
  }
}
